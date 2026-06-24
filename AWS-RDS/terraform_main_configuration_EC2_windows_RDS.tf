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
    cidr_blocks = ["0.0.0.0/0"] # 實務上強烈建議縮小至您的固定公網 IP
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


# ==========================================
# AWS RDS MS SQL SERVER 2022 配置
# ==========================================

# 5. 建立 RDS 子網路群組
resource "aws_db_subnet_group" "mssql_subnet" {
  name        = "mssql-subnet-group"
  description = "Subnet group for MS SQL Server RDS"
  subnet_ids  = data.aws_subnets.default.ids

  tags = {
    Name = "mssql_subnet_group"
  }
}

# 6. 建立 RDS 安全性群組 (僅開放給 Windows EC2 連線)
resource "aws_security_group" "mssql_access" {
  name        = "allow_mssql_from_ec2"
  description = "Allow MS SQL Server inbound traffic from Windows EC2"
  vpc_id      = data.aws_vpc.default.id

  # 【關鍵安全設定】僅允許來自上述 Windows EC2 安全性群組的流量透過 Port 1433 進入 RDS
  ingress {
    description     = "MS SQL Server from Windows EC2 Bastion"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = [aws_security_group.windows_access.id] # 綁定 EC2 安全性群組
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "allow_mssql_sg" }
}

# 7. 建立 AWS RDS MS SQL Server 2022 執行個體
resource "aws_db_instance" "mssql_server" {
  identifier           = "cloud-mssql-db"
  
  # 資料庫引擎與規格
  engine               = "sqlserver-ex"            # 這裡預設使用 Express 版，若是商用可改為 sqlserver-se (Standard) 或 sqlserver-ee (Enterprise)
  engine_version       = "16.00.4236.2.v1"         # SQL Server 2022 版本
  # license_model        = "license-included"        # 微軟授權已含於 AWS 帳單
  # 硬體規格
  instance_class       = "db.t3.small"             #  2 vCPU, 2 GB 記憶體 (滿足至少 2GB 需求)

  # 儲存空間配置
  allocated_storage    = 20                       # 配置 20 GB 硬碟
  storage_type         = "gp2"                     # gp2 高性能儲存體
  max_allocated_storage = 40                      # 自動擴展上限至 40 GB

  # 管理員帳密（此 admin 帳號即具備該 RDS 託管環境下的 sa 最高權限）
  username             = "admin"
  password             = "23760299"

  # 網路安全與子網路綁定
  db_subnet_group_name   = aws_db_subnet_group.mssql_subnet.name
  vpc_security_group_ids = [aws_security_group.mssql_access.id]
  publicly_accessible    = false                     # 設為 false，避免外部網路直接接觸資料庫，由 Windows EC2 連線即可

  # 備份與維護
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:04:30-Sun:05:30"

  # 安全生命週期
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = {
    Name = "cloud-mssql-instance"
  }
}


# ==========================================
# 輸出參數
# ==========================================

# 輸出 Windows Server 的公用 IP
output "windows_instance_public_ip" {
  value       = aws_instance.windows_server.public_ip
  description = "The public IP address of the Windows Server. Use this to RDP."
}

# 輸出 RDS 資料庫的連線端點 (供 Windows 內的 SSMS/應用程式連線使用)
output "db_instance_endpoint" {
  value       = aws_db_instance.mssql_server.endpoint
  description = "The connection endpoint for the MS SQL Server RDS instance."
}