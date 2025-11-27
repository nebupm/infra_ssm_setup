# infra_ssm_setup
AWS setup using SSM service

# terraform-module: vpc-flow-logs

Features:
- Flow logs to CloudWatch (7 day retention)
- Flow logs to S3 (lifecycle to Glacier, expiration)
- Optional parquet + hive partitions (enable_parquet = true)
- Toggleable: enable_cloudwatch, enable_s3, overall vpcflowlog_enabled
- IAM role & least-privilege policy created automatically (only when needed)
- S3 force_destroy controlled by variable

IMPORTANT:
- Parquet partitioning requires AWS provider >= 5.25.0 (Terraform init with -upgrade if needed).
- S3 bucket names must be globally unique if you provide `s3_bucket_name`.

