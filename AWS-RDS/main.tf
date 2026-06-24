provider "aws" {
  region = "us-east-1"

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

# 1. 使用預設 VPC (簡化範例，實務上可自訂 VPC)
data "aws_vpc" "default" {
  default = true
}

# 2. 建立安全組 (Security Group)，開放 SQL Server 預設的 1433 埠
resource "aws_security_group" "mssql_access" {
  name        = "allow_mssql"
  description = "Allow MS SQL Server inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "MS SQL Server from anywhere"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 建議實務上將此範圍縮小至特定 IP
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "allow_mssql_sg" }
}

# 3. 建立 AWS RDS (MS SQL Server) 執行個體
resource "aws_db_instance" "mssql_server" {
  identifier             = "my-mssql-database"
  
  # 引擎與版本 (目前 AWS 穩定支援最新為 SQL Server 2022，即 16.00)
  engine                 = "sqlserver-ex"      # 這裡預設使用 Express 版，若是商用可改為 sqlserver-se (Standard) 或 sqlserver-ee (Enterprise)
  engine_version         = "16.00.4236.2.v1"   # 對應 SQL Server 2022 (未來開放 2024 後可改為 17.00.xxxx)
  
  # 硬體規格
  instance_class         = "db.t3.small"       # 2 vCPU, 2 GB 記憶體 (滿足至少 2GB 需求)
  allocated_storage      = 20                  # 硬碟配置 20 GB
  storage_type           = "gp2"               # 使用最新 gp2 儲存類型 (預設提供 baseline performance)
  max_allocated_storage  = 40                  # 啟用硬碟自動擴充，上限為 40 GB

  # 帳號與權限
  username               = "admin"             # 設定管理員帳號
  password               = "23760299"          # 設定管理員密碼
  
  # 網路與安全
  vpc_security_group_ids = [aws_security_group.mssql_access.id]
  publicly_accessible    = true                # 為了方便您從外部連線測試，設為 true。實務生產環境建議為 false
  
  # 其他設定
  skip_final_snapshot    = true                # 刪除 RDS 時不建立最終快照 (測試環境適用)
  
  # 注意：針對 SQL Server，Terraform 不支援使用 "db_name" 屬性直接建立預設資料庫。
  # 必須在連線後透過 T-SQL 語法 (CREATE DATABASE cloud) 建立。

  tags = {
    Name = "mssql-rds-server"
  }
}

# 4. 輸出部署後的資料庫連線端點 (Endpoint)
output "rds_endpoint" {
  value       = aws_db_instance.mssql_server.endpoint
  description = "請使用此端點，搭配帳號 admin 與密碼 23760299 透過 SSMS 進行連線"
}