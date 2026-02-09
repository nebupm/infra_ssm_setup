# The AWS region to deploy resources in
aws_region = "eu-west-2"

# The AWS profile to use for running the code
aws_profile = "default"

#Enable or Disable Cloud Trail Events.check 
cloudtrail_enabled = false
# Selective use of the Cloudtrail event type as well.
enable_management_events    = true
enable_s3_data_events       = false
enable_dynamodb_data_events = false

#Enable or Disable VPC Flow logs to Cloud watch and S3 Bucket.
vpcflowlog_enabled = false

#Create or Not create a Windows EC2 instance.
create_windows_ec2               = false
windows_enable_public_ip_address = false

#Create or Not create a Linux EC2 instance.
create_linux_ec2               = true
linux_enable_public_ip_address = false
linux_instance_count           = 1
linux_instance_type            = "t3.nano"
