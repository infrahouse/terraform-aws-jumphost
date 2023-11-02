from os import environ
import boto3
from botocore.exceptions import ClientError


def complete_lifecycle_action(
    lifecyclehookname,
    autoscalinggroupname,
    lifecycleactiontoken,
    instanceid,
    lifecycleactionresult="CONTINUE",
):
    print("Completing lifecycle hook action")
    print(f"{lifecyclehookname=}")
    print(f"{autoscalinggroupname=}")
    print(f"{lifecycleactiontoken=}")
    print(f"{lifecycleactionresult=}")
    print(f"{instanceid=}")
    client = boto3.client("autoscaling")
    client.complete_lifecycle_action(
        LifecycleHookName=lifecyclehookname,
        AutoScalingGroupName=autoscalinggroupname,
        LifecycleActionToken=lifecycleactiontoken,
        LifecycleActionResult=lifecycleactionresult,
        InstanceId=instanceid,
    )


def add_record(zone_id, zone_name, hostname, instance_id, ttl: int):
    """Add the instance to DNS."""
    print(f"Adding instance {instance_id} as a hostname {hostname} to zone {zone_id}")
    print(f"{zone_name =}")
    public_ip = get_public_ip(instance_id)
    print(f"{public_ip = }")

    route53_client = boto3.client("route53")
    response = route53_client.list_resource_record_sets(
        HostedZoneId=zone_id,
        StartRecordType="A",
        StartRecordName=f"{hostname}.{zone_name}",
        MaxItems="1",
    )
    ip_set = {public_ip}
    for rr_set in response["ResourceRecordSets"]:
        if "ResourceRecords" in rr_set:
            for rr in rr_set["ResourceRecords"]:
                ip_set.add(rr["Value"])

    r_records = [{"Value": ip} for ip in list(ip_set)]
    route53_client.change_resource_record_sets(
        HostedZoneId=zone_id,
        ChangeBatch={
            "Changes": [
                {
                    "Action": "UPSERT",
                    "ResourceRecordSet": {
                        "Name": f"{hostname}.{zone_name}",
                        "Type": "A",
                        "ResourceRecords": r_records,
                        "TTL": ttl,
                    },
                }
            ]
        },
    )
    ec2_client = boto3.client("ec2")
    ec2_client.create_tags(
        Resources=[
            instance_id,
        ],
        Tags=[
            {"Key": "PublicIpAddress", "Value": public_ip},
        ],
    )


def remove_record(zone_id, zone_name, hostname, instance_id, ttl: int):
    """Remove the instance from DNS."""
    print(f"Removing instance {instance_id} from zone {zone_id}")
    print(f"{zone_name =}")
    public_ip = get_public_ip(instance_id)
    print(f"{public_ip = }")

    route53_client = boto3.client("route53")
    response = route53_client.list_resource_record_sets(
        HostedZoneId=zone_id,
        StartRecordType="A",
        StartRecordName=f"{hostname}.{zone_name}",
        MaxItems="1",
    )
    ip_set = set()
    for rr_set in response["ResourceRecordSets"]:
        for rr in rr_set["ResourceRecords"]:
            ip = rr["Value"]
            if ip != public_ip:
                ip_set.add(rr["Value"])
    r_records = [{"Value": ip} for ip in list(ip_set)]
    if r_records:
        route53_client.change_resource_record_sets(
            HostedZoneId=zone_id,
            ChangeBatch={
                "Changes": [
                    {
                        "Action": "UPSERT",
                        "ResourceRecordSet": {
                            "Name": f"{hostname}.{zone_name}",
                            "Type": "A",
                            "ResourceRecords": r_records,
                            "TTL": ttl,
                        },
                    }
                ]
            },
        )
    else:
        route53_client.change_resource_record_sets(
            HostedZoneId=zone_id,
            ChangeBatch={
                "Changes": [
                    {
                        "Action": "DELETE",
                        "ResourceRecordSet": {
                            "Name": f"{hostname}.{zone_name}",
                            "Type": "A",
                            "ResourceRecords": [{"Value": public_ip}],
                            "TTL": ttl,
                        },
                    }
                ]
            },
        )


def get_public_ip(instance_id):
    """Get the instance's public IP address by its instance_id"""
    ec2_client = boto3.client("ec2")

    response = ec2_client.describe_instances(
        InstanceIds=[
            instance_id,
        ],
    )
    print(f"describe_instances({instance_id}): {response=}")
    if "PublicIpAddress" in response["Reservations"][0]["Instances"][0]:
        return response["Reservations"][0]["Instances"][0]["PublicIpAddress"]
    else:
        for tag in response["Reservations"][0]["Instances"][0]["Tags"]:
            if tag["Key"] == "PublicIpAddress":
                return tag["Value"]

        raise RuntimeError(f"Could not determine public IP of {instance_id}")


def lambda_handler(event, context):
    print(f"{event = }")

    lifecycle_transition = event["detail"]["LifecycleTransition"]
    print(f"{lifecycle_transition = }")

    lifecycle_result = "CONTINUE"
    try:
        if lifecycle_transition == "autoscaling:EC2_INSTANCE_TERMINATING":
            remove_record(
                environ["ROUTE53_ZONE_ID"],
                environ["ROUTE53_ZONE_NAME"],
                environ["ROUTE53_HOSTNAME"],
                event["detail"]["EC2InstanceId"],
                int(environ["ROUTE53_TTL"]),
            )
        elif lifecycle_transition == "autoscaling:EC2_INSTANCE_LAUNCHING":
            try:
                add_record(
                    environ["ROUTE53_ZONE_ID"],
                    environ["ROUTE53_ZONE_NAME"],
                    environ["ROUTE53_HOSTNAME"],
                    event["detail"]["EC2InstanceId"],
                    int(environ["ROUTE53_TTL"]),
                )
            except ClientError as err:
                print(f"{err}")
                lifecycle_result = "ABANDON"

    finally:
        complete_lifecycle_action(
            lifecyclehookname=event["detail"]["LifecycleHookName"],
            autoscalinggroupname=event["detail"]["AutoScalingGroupName"],
            lifecycleactiontoken=event["detail"]["LifecycleActionToken"],
            instanceid=event["detail"]["EC2InstanceId"],
            lifecycleactionresult=lifecycle_result
        )
