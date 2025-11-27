#########################################################
# VARIABLES
#########################################################
# EC2 Linux Instance Variables
variable "create_linux_ec2" {
  description = "Whether to create the Linux EC2 instance"
  type        = bool
  default     = true
}

variable "linux_instance_type" {
  type        = string
  description = "EC2 Linux Instance Type"
  default     = "t3.nano"
}
variable "linux_instance_ami" {
  type        = string
  description = "EC2 Instance Amazon Linux 2023 AMI"
  #default     = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  # Corresponds to Amazon Linux 2023 in eu-west-2 al2023-ami-2023.9.20251027.0-kernel-6.1-x86_64
  default = "ami-024294779773cf91a"
}
variable "linux_instance_name" {
  type        = string
  description = "Name of the EC2 instance"
  default     = "linux_vm_ssm"
}
variable "linux_ebs_volume_size_gb" {
  description = "Size of the EBS volume in GB"
  type        = number
  default     = 4
}

variable "linux_enable_public_ip_address" {
  type        = bool
  description = "Whether to enable a public IP address for the Linux EC2 instance"
  default     = true
}
# Setup EC2 instance
#########################################################
# EC2 INSTANCE
#########################################################
# Setup Key Pair
resource "aws_key_pair" "this_linux_keypair" {
  key_name   = "linux-ec2-instance-keypair"
  public_key = file("../../ec2_all_keys/aws-ec2-linux-instance-public-key.pub")
}

# Setup EC2 instance
resource "aws_instance" "linux_instance" {
  count                       = var.create_linux_ec2 ? 1 : 0
  ami                         = var.linux_instance_ami
  instance_type               = var.linux_instance_type
  subnet_id                   = aws_subnet.this_private_subnet.id
  vpc_security_group_ids      = [aws_security_group.ec2_instance_sg.id]
  key_name                    = aws_key_pair.this_linux_keypair.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2-instance-profile-for-ssm.name
  associate_public_ip_address = var.linux_enable_public_ip_address
  user_data                   = <<-EOF
#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x
sleep 30
retry=3
while [[ $retry > 0 ]]; do
  # Detect the root NVMe device dynamically
  ROOT_NAME=$(lsblk -no PKNAME $(findmnt / -o SOURCE -n))
  # Detect secondary EBS NVMe volume
  DEVICE=$(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}' | grep nvme | grep -v "$ROOT_NAME" | head -n 1)
  if [[ -n $DEVICE ]]; then 
    DEVICE="/dev/$DEVICE"
    # Create filesystem only if none exists
    if ! blkid $DEVICE; then
      mkfs -t xfs $DEVICE
    fi
    mkdir -p /mnt/data
    mount $DEVICE /mnt/data
    uuid=$(blkid -s UUID -o value $DEVICE)
    grep $uuid /etc/fstab > /dev/null
    if [[ $? -ne 0 ]]; then
      echo "UUID=$uuid /mnt/data xfs defaults,nofail 0 2" >> /etc/fstab
      chown ec2-user:ec2-user /mnt/data
      chmod 775 /mnt/data
      ## To Survive Reboot.
      echo "chown ec2-user:ec2-user /mnt/data" >> /etc/rc.local
      echo "chmod 775 /mnt/data" >> /etc/rc.local
      chmod +x /etc/rc.local
    fi
    break
  else
    sleep 30
    retry=$((retry-1))
  fi
done
EOF
  tags                        = { Name = var.linux_instance_name }
}

resource "aws_ebs_volume" "data_volume" {
  count             = var.create_linux_ec2 ? 1 : 0
  availability_zone = aws_instance.linux_instance[count.index].availability_zone
  size              = var.linux_ebs_volume_size_gb
  type              = "gp3"
  tags              = { Name = "${var.linux_instance_name}-data" }
}

#########################
# Attach EBS volume
#########################
resource "aws_volume_attachment" "attach_data" {
  count        = var.create_linux_ec2 ? 1 : 0
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.data_volume[count.index].id
  instance_id  = aws_instance.linux_instance[count.index].id
  force_detach = true
}

#########################################################
# OUTPUTS
#########################################################
# EC2 Instance details
output "linux_instance_id" {
  value = var.create_linux_ec2 ? aws_instance.linux_instance[0].id : null
}
output "linux_instance_name" {
  value = var.create_linux_ec2 ? aws_instance.linux_instance[0].tags.Name : null

}
output "linux_instance_public_ip" {
  value = var.create_linux_ec2 ? aws_instance.linux_instance[0].public_ip : null
}
output "linux_instance_ami_id" {
  value = var.create_linux_ec2 ? aws_instance.linux_instance[0].ami : null

}
output "linux_instance_type" {
  value = var.create_linux_ec2 ? aws_instance.linux_instance[0].instance_type : null
}
