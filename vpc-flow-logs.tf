#########################################################
# This module enables VPC Flow Logs to **CloudWatch** (7 days retention) 
# and **S3** (with lifecycle: Standard -> Glacier -> Expire).
#########################################################
# Variables
#########################################################
variable "traffic_type" {
  type    = string
  default = "ALL"
}

variable "vpcflowlog_enabled" {
  description = "Master toggle to enable flow logs resources for this VPC"
  type        = bool
  default     = true
}

variable "s3_sse_algorithm" {
  description = "SSE algorithm (AES256 or aws:kms). KMS not handled in this module by default."
  type        = string
  default     = "AES256"
}

locals {
  bucket_name = "vpc-flowlogs-s3-${aws_vpc.this_vpc.id}"
}


#########################################################
# IAM Role for VPC Flow Logs (Cloudwatch + S3)
#########################################################
resource "aws_iam_role" "vpc_flow_logs_role" {
  count = var.vpcflowlog_enabled ? 1 : 0
  name  = "vpcFlowLogsRole-${aws_vpc.this_vpc.id}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "vpc-flow-logs.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "vpcFlowLogsRole-${aws_vpc.this_vpc.id}" }
}

resource "aws_iam_role_policy" "vpc_flow_logs_policy" {
  count = var.vpcflowlog_enabled ? 1 : 0
  name  = "${aws_iam_role.vpc_flow_logs_role[0].name}-policy"
  role  = aws_iam_role.vpc_flow_logs_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      # S3 permissions
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.bucket_name}",
          "arn:aws:s3:::${local.bucket_name}/*"
        ]
      }
    ]
  })
}

#########################################################
# CloudWatch Log Group
#########################################################
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.vpcflowlog_enabled ? 1 : 0
  name              = "vpc-flowlogs-cloudwatch-${aws_vpc.this_vpc.id}"
  retention_in_days = 7
}

resource "aws_flow_log" "to_cloudwatch" {
  count                = var.vpcflowlog_enabled ? 1 : 0
  vpc_id               = aws_vpc.this_vpc.id
  traffic_type         = var.traffic_type
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs_role[0].arn
  depends_on = [
    aws_iam_role.vpc_flow_logs_role,
    aws_iam_role_policy.vpc_flow_logs_policy,
    aws_cloudwatch_log_group.vpc_flow_logs
  ]
  tags = { Name = aws_vpc.this_vpc.id }
}


#########################################################
# S3 Bucket for Storing Flow Logs.
#########################################################
resource "aws_s3_bucket" "s3_bucket_vpc_flow_logs" {
  count         = var.vpcflowlog_enabled ? 1 : 0
  bucket        = local.bucket_name
  force_destroy = true
  tags          = { Name = local.bucket_name }
}

resource "aws_flow_log" "to_s3" {
  count                = var.vpcflowlog_enabled ? 1 : 0
  vpc_id               = aws_vpc.this_vpc.id
  traffic_type         = var.traffic_type
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.s3_bucket_vpc_flow_logs[0].arn
  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true
    per_hour_partition         = true
  }
  depends_on = [
    aws_iam_role.vpc_flow_logs_role,
    aws_iam_role_policy.vpc_flow_logs_policy,
    aws_s3_bucket.s3_bucket_vpc_flow_logs
  ]
  tags = { Name = aws_vpc.this_vpc.id }
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  count                   = var.vpcflowlog_enabled ? 1 : 0
  bucket                  = aws_s3_bucket.s3_bucket_vpc_flow_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "versioning" {
  count  = var.vpcflowlog_enabled ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket_vpc_flow_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse_setup" {
  count  = var.vpcflowlog_enabled ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket_vpc_flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.s3_sse_algorithm
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  count  = var.vpcflowlog_enabled ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket_vpc_flow_logs[0].id

  rule {
    id     = "glacier-transition-expiration"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }
  }
}

# Outputs
output "cloudwatch_log_group_name" {
  value       = try(aws_cloudwatch_log_group.vpc_flow_logs[0].name, "")
  description = "CloudWatch log group name (if created)"
}

output "s3_bucket_arn" {
  value       = try(aws_s3_bucket.s3_bucket_vpc_flow_logs[0].arn, "")
  description = "S3 bucket ARN for flow logs (if created)"
}

output "flow_log_ids" {
  value = compact([
    try(aws_flow_log.to_cloudwatch[0].id, ""),
    try(aws_flow_log.to_s3[0].id, "")
  ])
  description = "List of created flow log resource ids"
}

output "iam_role_arn" {
  value       = try(aws_iam_role.vpc_flow_logs_role[0].arn, "")
  description = "IAM role ARN used by flow logs"
}
