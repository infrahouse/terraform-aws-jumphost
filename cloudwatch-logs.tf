# CloudWatch log group for jumphost logs (always created)
resource "aws_cloudwatch_log_group" "jumphost" {
  name              = "/aws/ec2/jumphost/${var.environment}/${var.route53_hostname}"
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
      aws_cloudwatch_log_group.jumphost.arn,
      "${aws_cloudwatch_log_group.jumphost.arn}:*"
    ]
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