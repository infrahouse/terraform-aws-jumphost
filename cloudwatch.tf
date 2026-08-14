# SNS topic for CloudWatch alarm notifications
resource "aws_sns_topic" "alarms" {
  name              = "jumphost-alarms-${random_string.asg_name.result}"
  display_name      = "Jumphost alarms"
  kms_master_key_id = "alias/aws/sns"
  tags              = local.default_module_tags
}

resource "aws_sns_topic_subscription" "alarm_emails" {
  count     = length(var.alarm_emails)
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_emails[count.index]
}

# The alarm was conditional on the removed sns_topic_alarm_arn variable
# and indexed by count; it is now always created.
moved {
  from = aws_cloudwatch_metric_alarm.cpu_utilization_alarm[0]
  to   = aws_cloudwatch_metric_alarm.cpu_utilization_alarm
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization_alarm" {
  alarm_name          = format("CPU Alarm on ASG %s", aws_autoscaling_group.jumphost.name)
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  evaluation_periods  = 1
  period              = 60
  threshold           = 90
  namespace           = "AWS/EC2"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  alarm_description   = format("%s alarm - CPU exceeds 90 percent", aws_autoscaling_group.jumphost.name)
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jumphost.name
  }
}
