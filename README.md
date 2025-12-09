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

## Port Forwearding for connecting to your Windows Instance using RDP Client

If you have your EC2 instances managed by SSM and you dont have a public IP for your instances. Then Port forwarding using SSM plugin is the best way forward.
Use the following setup to organise this.

### Download the SSM Plugin.
- curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg" -o "session-manager-plugin.pkg"
- sudo installer -pkg session-manager-plugin.pkg -target /
- sudo ln -s /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/local/bin/session-manager-plugin

#### Check for the plugin

- session-manager-plugin

#### Create an SSM session on your local machine
- aws ssm start-session --target i-011439d8f10d91f11 --document-name AWS-StartPortForwardingSession --parameters "portNumber"=["3389"],"localPortNumber"=["55678"]
