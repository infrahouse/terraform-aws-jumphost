# Task: launch-time `InspectorEc2Exclusion` tag + `ec2:DeleteTags`

**Status:** implemented, not yet exercised against AWS. The Puppet half is merged and live.

## Why

AWS Inspector scans a freshly launched instance before `unattended-upgrades` has run, opens a finding for
whatever was pending, and closes it on the next upgrade — but by then it has already **reopened the
vulnerability group**, and a group old enough to be reopened that way breaks the remediation SLA.

The fix is not "patch more often on a timer", it is "don't present an unpatched host to Inspector at all":

```
launch  -> instance tagged InspectorEc2Exclusion   (THIS REPO — not done)
boot    -> apt-get update && unattended-upgrade    (puppet-code, done)
success -> aws ec2 delete-tags Key=InspectorEc2Exclusion  (puppet-code, done)
        -> Inspector's first scan sees a patched host
```

## What is already done (infrahouse/puppet-code)

- `profile::boot_security_upgrade` — patches at boot with a bounded retry budget, then drops the tag.
  PRs #294 (development) and #295 (promoted to sandbox + global `modules/`).
- `role::jumphost` includes it. PR #296. Live in all environments.

Tag removal is deliberately **best effort** and never fails a Puppet run: missing permission, missing
`ec2metadata`, or unreadable instance id each log a line and return 0. That was so the Puppet side could
ship before this repo caught up.

## ⚠️ The constraint that shapes everything here

**The tag is fail-open.** If an instance launches tagged and nothing removes the tag, that jumphost is
**permanently invisible to Inspector** — strictly worse than today, and silently so. It will simply never
appear in findings again.

So the two changes below ship **together, in one PR**. Adding the tag without `ec2:DeleteTags` creates the
hole. There is no useful intermediate state.

There is no opt-in variable: `role::jumphost` already includes `profile::boot_security_upgrade` in every
environment and the module does not pin puppet-code (it applies whatever is in `/opt/puppet-code`), so the
removal side is universally present. Tag unconditionally.

## Change 1 — tag instances at launch (`main.tf`)

Add a static `tag` block to `aws_autoscaling_group.jumphost`, alongside the existing `Name` and
`ubuntu_codename` blocks:

```hcl
  # Keeps Inspector from scanning the instance until profile::boot_security_upgrade
  # has applied pending security updates and removed this tag. See
  # .claude/plans/inspector-exclusion-tag.md -- REQUIRES the ec2:DeleteTags
  # statement in data_sources.tf, or the instance is excluded forever.
  tag {
    key                 = "InspectorEc2Exclusion"
    propagate_at_launch = true
    value               = "true"
  }
```

Inspector keys off the tag **key**; the value is arbitrary.

## Change 2 — grant `ec2:DeleteTags` (`data_sources.tf`)

Add to `data.aws_iam_policy_document.required_permissions`. Scope it down on both axes — which tag keys,
and which instances:

```hcl
  statement {
    actions   = ["ec2:DeleteTags"]
    resources = ["arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["InspectorEc2Exclusion"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/created_by_module"
      values   = ["infrahouse/jumphost/aws"]
    }
  }
```

IAM has no "this instance only" variable for EC2, so the `created_by_module` condition (already in
`local.default_module_tags` and propagated at launch) is the closest available blast-radius limit.

`data "aws_region" "current"` is declared in `data_sources.tf` but currently unused — if you reference it,
note this module is on AWS provider **v6**, where the attribute is `.region`; `.name` is deprecated.

## Change 3 — test validation (`tests/test_module.py`)

The full path is asserted end to end: the instance provisions, Puppet completes, the tag is gone. All AWS
access goes through `infrahouse-core` objects — no boto3 clients in the test.

**3a. Bump infrahouse-core to `~= 1.3.0`.** `requirements.txt` pins `~= 1.1.1`, which resolves to neither.
Two things this plan needs landed upstream:

- 1.2.0 — `ASG.tags` (`{key: value}`, same shape as `EC2Instance.tags`) and `ASG.launch_tags` (the subset
  with `PropagateAtLaunch`).
- 1.3.0 — `EC2Instance.wait_for_bootstrap()` and `EC2Instance.cloud_init_status`
  ([#148](https://github.com/infrahouse/infrahouse-core/issues/148)).

**3b. Replace the inline Puppet wait with `instance.wait_for_bootstrap()`.** Lines 41–75 of
`verify_cloudwatch_logging` — the `until test -f /var/run/puppet-done` loop and the `cloud-init status` /
`cloud-init-output.log` diagnostics block — are **deleted**, not extracted. One call in `test_module`
replaces them for both checks:

```python
        instance = asg.instances[0]
        instance.wait_for_bootstrap()
```

Not a like-for-like swap, and the differences are all improvements:

- **It keys on cloud-init, not on the marker.** `ih-bootstrap` runs from `runcmd` under `set -euo
  pipefail`, so cloud-init reports `done` only after `ih-puppet apply` and `post_runcmd` (which is what
  writes `/var/run/puppet-done`) succeeded. Same guarantee, without depending on this module's own marker.
- **It fails fast.** cloud-init `error` raises `IHBootstrapFailed` immediately. The marker loop had no way
  to tell "failed" from "still running" and could only ever burn the full 600s.
- **The diagnostics moved into the library.** `IHBootstrapFailed` / `IHBootstrapTimeout` messages carry
  `cloud-init status --long` and `tail -n 100 /var/log/cloud-init-output.log`, collected best effort with
  short timeouts. pytest renders the exception, so the local `pytest.fail` and its diagnostics loop go.

**Bonus fix.** The facter assertion at test_module.py:261 currently runs *before* the Puppet wait, which
lives inside `verify_cloudwatch_logging` further down — it passes only because the instance-refresh wait
usually leaves enough slack. Hoisting the wait into `test_module` puts it ahead of every check that needs
a converged instance.

**3c. New check.**

```python
def verify_inspector_exclusion_tag_removed(asg, instance):
    """
    The ASG tags instances with InspectorEc2Exclusion at launch and
    profile::boot_security_upgrade removes it once security updates are applied.

    Both halves matter: without the ASG assertion, "the tag is gone" also passes
    on a module that never tags at all.

    Assumes the instance finished bootstrapping (see wait_for_bootstrap).
    """
    LOG.info("Verifying the Inspector exclusion tag lifecycle...")

    # 1. The ASG still asks for the tag at launch
    assert (
        "InspectorEc2Exclusion" in asg.launch_tags
    ), f"ASG does not propagate InspectorEc2Exclusion at launch. Launch tags: {sorted(asg.launch_tags)}"
    LOG.info("✓ ASG propagates InspectorEc2Exclusion at launch")

    # 2. Puppet removed it from the running instance. EC2 tag reads are eventually
    #    consistent and EC2Instance caches its describe call for 10 seconds, so poll
    #    on a longer interval than that TTL rather than asserting once.
    max_wait = 60
    poll_interval = 15

    for _ in range(max_wait // poll_interval):
        if "InspectorEc2Exclusion" not in instance.tags:
            LOG.info("✓ InspectorEc2Exclusion removed from %s", instance.instance_id)
            return
        time.sleep(poll_interval)

    # Still tagged. The likely cause is a missing or mis-scoped ec2:DeleteTags
    # statement -- boot-security-upgrade.sh logs that case and exits 0.
    _, cout, cerr = instance.execute_command(
        "sudo grep -i InspectorEc2Exclusion /var/log/cloud-init-output.log",
        execution_timeout=120,
    )
    pytest.fail(
        f"InspectorEc2Exclusion still present on {instance.instance_id} {max_wait} seconds after "
        f"Puppet completed -- the instance would be invisible to Inspector forever. "
        f"Check the ec2:DeleteTags statement in data_sources.tf.\n"
        f"----- cloud-init-output.log -----\n{cout}{cerr}"
    )
```

**3d. Wire it into `test_module`.** No new fixtures — `asg` and its instances are already built with the
test's region and `role_arn`. Call it after the `wait_for_bootstrap()` from 3b:

```python
        verify_inspector_exclusion_tag_removed(asg=asg, instance=instance)
```

## Gotchas found while reading the module

- **`instance_refresh { triggers = ["tag"] }`** (main.tf ~line 189) — adding an ASG tag **triggers a rolling
  instance refresh**. That is fine and arguably wanted (new instances exercise the new path), but it is not
  a no-op `apply`. `min_healthy_percentage = 100`, so capacity holds.
- **`propagate_at_launch` tags only at launch.** The ASG does not re-apply tags to running instances, so it
  will not fight Puppet's deletion, and deleting a per-instance tag does **not** show as Terraform drift on
  the ASG resource. The tag/untag cycle repeats per launch, which is exactly right.
- **The tag cannot be observed on a booted instance.** Puppet drops it during the same boot, well before
  the test can SSH in, so there is no window in which to assert "tag present". That is why 3c asserts
  `asg.launch_tags` rather than the live instance for the launch half.

## Checklist

- [x] `main.tf` — ASG `tag` block
- [x] `data_sources.tf` — `ec2:DeleteTags` statement
- [x] `requirements.txt` — `infrahouse-core ~= 1.3.0` (`ASG.launch_tags` + `wait_for_bootstrap()`)
- [x] `tests/test_module.py` — inline Puppet wait → `wait_for_bootstrap()` + `verify_inspector_exclusion_tag_removed`
- [x] `make format` / `make lint` (plus `terraform validate` — clean)
- [ ] `make test` — never run against AWS yet
- [ ] `bumpversion minor` (updates `locals.tf`, `README.md`, both `examples/*/main.tf`) — commits **and tags**,
      which fires `release.yml`; CHANGELOG.md is generated there by git-cliff from the commit messages, so
      it is not edited by hand
