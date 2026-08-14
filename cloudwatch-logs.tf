# Log groups named /aws/ec2/jumphost/<environment>/<hostname> (pre-5.1) collided
# across deployments sharing an environment (GH-67, GH-70). The old group is
# forgotten, not destroyed, so its audit logs survive the upgrade and expire
# per their retention policy.
removed {
  from = aws_cloudwatch_log_group.jumphost

  lifecycle {
    destroy = false
  }
}

# CloudWatch log group for jumphost logs (always created).
# The hostname.zone pair is unique per deployment: the Route53 record
# already requires it, so concurrent deployments can't collide.
resource "aws_cloudwatch_log_group" "jumphost_logs" {
  name              = "/aws/ec2/jumphost/${var.environment}/${var.route53_hostname}.${trimsuffix(data.aws_route53_zone.jumphost_zone.name, ".")}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_arn

  tags = merge(
    local.default_module_tags,
    {
      purpose = "Security and compliance logging"
    }
  )
}

# IAM policy document for CloudWatch logging permissions
data "aws_iam_policy_document" "cloudwatch_logs" {
  # Permissions for CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      aws_cloudwatch_log_group.jumphost_logs.arn,
      "${aws_cloudwatch_log_group.jumphost_logs.arn}:*"
    ]
  }

  # Permissions for CloudWatch Metrics (optional but recommended)
  statement {
    sid    = "CloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.cloudwatch_namespace]
    }
  }

  # EC2 metadata access for CloudWatch agent
  statement {
    sid    = "EC2Metadata"
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus"
    ]
    resources = ["*"]
  }
}
