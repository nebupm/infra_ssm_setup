#########################################################
# Variables
#########################################################

variable "cloudtrail_enabled" {
  description = "Enable or disable CloudTrail logging"
  type        = bool
  default     = true
}

variable "enable_management_events" {
  type    = bool
  default = true
}

variable "enable_s3_data_events" {
  type    = bool
  default = false
}

variable "enable_dynamodb_data_events" {
  type    = bool
  default = false
}

#########################################################
# S3 Bucket and the Config.
#########################################################
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  force_destroy = true # allow terraform destroy to remove bucket

  tags = {
    Name = "cloudtrail-logs"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: Keep logs for 7 days only
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 7
    }
  }
}

#########################################################
# CloudTrail IAM policy for S3
#########################################################
resource "aws_s3_bucket_policy" "cloudtrail_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}


#########################################################
# Enable CloudTrail
#########################################################

resource "aws_cloudtrail" "this_cloudtrail" {
  name                          = "management-events"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.bucket
  enable_logging                = var.cloudtrail_enabled
  is_multi_region_trail         = false
  include_global_service_events = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = var.enable_management_events
  }

  dynamic "event_selector" {
    for_each = var.enable_s3_data_events ? [1] : []
    content {
      read_write_type = "All"
      data_resource {
        type   = "AWS::S3::Object"
        values = ["arn:aws:s3:::"]
      }
    }
  }
  dynamic "event_selector" {
    for_each = var.enable_dynamodb_data_events ? [1] : []

    content {
      read_write_type = "All"

      data_resource {
        type   = "AWS::DynamoDB::Table"
        values = var.dynamodb_data_event_arns
      }
    }
  }
  depends_on = [
    aws_s3_bucket_policy.cloudtrail_policy
  ]
}
