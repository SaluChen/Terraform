provider "aws" {
  region = "us-east-1"

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

}

# 1. 取得預設 VPC 與子網路資訊
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ==========================================
# WINDOWS SERVER 2022 EC2 配置
# ==========================================
# 2. 自動獲取最新的 Windows Server 2022 官方 AMI ID
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 3. 建立 Windows EC2 安全性群組 (開放 RDP 遠端桌面連線)
resource "aws_security_group" "windows_access" {
  name        = "allow_rdp"
  description = "Allow RDP inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  # 開放 RDP Port 3389 供遠端連線
  ingress {
    description = "RDP from anywhere"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 實務上強烈建議縮小至您的固定公網 IP，在學校還是要全開避免因DHCP問題影響
  }

  # 允許所有對外連線（以便 Windows Update 或連線至 RDS）
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "allow_rdp_sg" }
}


# 4. 建立 Windows Server 2022 EC2 執行個體
resource "aws_instance" "windows_server" {
  ami           = data.aws_ami.windows_2022.id
  
  # 說明：Windows Server 具備圖形介面 (GUI)，建議至少使用 t3.medium (2 vCPU, 4GiB RAM) 
  # 或 t3.large (2 vCPU, 8GiB RAM) 以確保系統流暢運作。
  instance_type = "t3.small"

  # 關聯 RDP 安全性群組
  vpc_security_group_ids = [aws_security_group.windows_access.id]

  # 啟用公用 IP，以便從外部網路透過 RDP 進行管理
  associate_public_ip_address = true

  # 建議設定：請確保您已在 AWS 上建立 Key Pair，以便解密 Windows 的 Administrator 密碼
  # key_name = "your_key_pair_name"
  key_name      = "vockey" # 必須是您在 AWS Console 上已建立的金鑰對名稱
  
  # 硬碟設定：Windows Server 系統碟建議至少配置 50GB 以上
  root_block_device {
    volume_size           = 50
    volume_type           = "gp2"
    delete_on_termination = true
  }
  tags = {
    Name = "windows-bastion-server"
  }
}
# 5. 輸出 Windows Server 的公用 IP
output "windows_instance_public_ip" {
  value       = aws_instance.windows_server.public_ip
  description = "The public IP address of the Windows Server. Use this to RDP."
}
