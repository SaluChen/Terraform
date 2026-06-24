provider "aws" {
  region = "us-east-1"

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

}

# 1. 自動獲取最新的 Amazon Linux 2023 AMI ID
data "aws_ami" "amazon_linux_2023" {
  most_recent = true

  filter {
    name = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  owners = ["amazon"] # Amazon
}
# 2. 使用預設 VPC (簡化範例，實務上可自訂 VPC)
data "aws_vpc" "default" {
  default = true
}

# 3. 建立安全組 (Security Group)，開放 SSH 22 埠
resource "aws_security_group" "ssh_access" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 建議實務上將此範圍縮小至特定 IP
 }
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "allow_ssh_sg" }
}

# 4. 建立 Linux EC2 執行個體
resource "aws_instance" "linux_server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"
  key_name      = "vockey" # 必須是您在 AWS Console 上已建立的金鑰對名稱
  
  # 關聯剛剛建立的安全組
  vpc_security_group_ids = [aws_security_group.ssh_access.id]

  # 啟用公用 IP
  associate_public_ip_address = true

  tags = {
    Name = "hashicorp-learn"
  }
}

# 5. 輸出部署後的公用 IP
output "instance_public_ip" {
  value       = aws_instance.linux_server.public_ip
  description = "The public IP address of the main server instance."
}