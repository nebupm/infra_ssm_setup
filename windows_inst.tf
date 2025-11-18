#########################################################
# VARIABLES
#########################################################
# EC2 Windows Instance Variables
variable "windows_instance_type" {
  type        = string
  description = "EC2 Windows Instance Type"
  default     = "t3.medium"
}

variable "windows_2016_instance_ami" {
  type        = string
  description = "EC2 Instance Windows_Server-2016-English-Full-Base"
  default     = "ami-0b31515a89503365e"
}

variable "windows_2019_instance_ami" {
  type        = string
  description = "EC2 Instance Windows_Server-2019-English-Full-Base"
  default     = "ami-0dfb58a0ca05ad98f"
}

variable "windows_2022_instance_ami" {
  type        = string
  description = "EC2 Instance Windows_Server-2022-English-Full-Base"
  default     = "ami-07c7ade22c224d6fe"
}

variable "windows_2025_instance_ami" {
  type        = string
  description = "EC2 Instance Windows_Server-2025-English-Full-Base"
  default     = "ami-0c7f78741f81ce0c4"
}

variable "windows_instance_name" {
  type        = string
  description = "Name of the Windows EC2 instance"
  default     = "windows_vm_ssm"
}

variable "windows_ebs_volume_size_gb" {
  type    = number
  default = 30
}

#########################################################
#  WINDOWS EC2 INSTANCE
#########################################################
# Setup Key Pair
resource "aws_key_pair" "this_windows_keypair" {
  key_name   = "windows-ec2-instance-keypair"
  public_key = file("../../ec2_all_keys/aws-ec2-windows-instance-public-key.pub")
}

#########################
# EBS volume for Windows
#########################
resource "aws_ebs_volume" "windows_data_volume" {
  availability_zone = aws_instance.windows_instance.availability_zone
  size              = var.windows_ebs_volume_size_gb
  type              = "gp3"
  tags              = { Name = "${var.windows_instance_name}-data" }
}

#########################
# Windows EC2 Instance
#########################
resource "aws_instance" "windows_instance" {
  ami                         = var.windows_2025_instance_ami
  instance_type               = var.windows_instance_type
  subnet_id                   = aws_subnet.this_private_subnet.id
  vpc_security_group_ids      = [aws_security_group.ec2_instance_sg.id]
  key_name                    = aws_key_pair.this_windows_keypair.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2-instance-profile-for-ssm.name
  get_password_data           = true
  associate_public_ip_address = false
  user_data                   = <<-EOF
<powershell>

# Log output
Start-Transcript -Path C:\Windows\Temp\userdata.log -Force

Write-Output "=== Waiting for RAW disk ==="
for ($i = 1; $i -le 30; $i++) {
    $disk = Get-Disk | Where-Object PartitionStyle -Eq 'RAW' | Select-Object -First 1
    if ($disk) { break }
    Start-Sleep -Seconds 5
}

if (-not $disk) {
    Write-Output "No RAW disk found after waiting. Exiting."
    Stop-Transcript
    exit 0
}

Write-Output "=== Disk found: Number $($disk.Number) ==="

# Ensure disk is online and not readonly
Set-Disk -Number $disk.Number -IsOffline $false -ErrorAction SilentlyContinue
Set-Disk -Number $disk.Number -IsReadOnly $false -ErrorAction SilentlyContinue

# Initialize
Initialize-Disk -Number $disk.Number -PartitionStyle GPT -Confirm:$false

# Create partition
$partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter

# Format
Format-Volume -DriveLetter $partition.DriveLetter -FileSystem NTFS -NewFileSystemLabel "Data" -Confirm:$false

# Try to use D: drive
if ($partition.DriveLetter -ne 'D') {

    # Check if D is free
    $letterUsed = (Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter -eq 'D')
    if (-not $letterUsed) {
        Write-Output "Assigning D: drive letter."
        Set-Partition -DriveLetter $partition.DriveLetter -NewDriveLetter 'D'
    } else {
        Write-Output "D: already in use. Keeping $($partition.DriveLetter):"
    }
}

Stop-Transcript

</powershell>
EOF
  tags                        = { Name = var.windows_instance_name }

}

#########################
# Attach EBS volume
#########################
resource "aws_volume_attachment" "attach_windows_data_volume" {
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.windows_data_volume.id
  instance_id  = aws_instance.windows_instance.id
  force_detach = true
}

##################################################
# Outputs
##################################################
output "windows_instance_id" {
  value = aws_instance.windows_instance.id
}
output "windows_instance_public_ip" {
  value = aws_instance.windows_instance.public_ip
}
output "windows_admin_password" {
  description = "Decrypted Windows Administrator password"
  value = rsadecrypt(
    aws_instance.windows_instance.password_data,
    file("../../ec2_all_keys/aws-ec2-windows-instance-private-key.pem")
  )
  sensitive = true
}
#Run the command : terraform  output windows_admin_password