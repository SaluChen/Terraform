provider "aws" {
  region = "us-east-1"

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

# 1. 取得預設 VPC 與子網段 (Subnets)，Beanstalk 需要知道在哪裡建立資源
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  
  # 新增這段過濾條件：只抓取明確支援 t3.micro 的可用區，避開不支援的區域通常是"us-east-1e"為較舊的資料中心
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

# 2. 自動獲取最新的 Elastic Beanstalk Solution Stack (以 Node.js 為例)
# 如果您想用 Python、Java 或 PHP，可以修改 name_regex 中的關鍵字
data "aws_elastic_beanstalk_solution_stack" "latest_stack" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 (.*) running PHP (.*)$"
}

# 4. 建立 Elastic Beanstalk 應用程式
resource "aws_elastic_beanstalk_application" "terraform_app" {
  name        = "terraform-web-app"
  description = "My Elastic Beanstalk Application created via Terraform"
}

# 5. 建立 Elastic Beanstalk 環境
resource "aws_elastic_beanstalk_environment" "terraform_env" {
  name                = "terraform-web-env"
  application         = aws_elastic_beanstalk_application.terraform_app.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.latest_stack.name

  # 指定 Elastic Beanstalk 服務角色 (Service Role) - 實驗室預設 LabRole
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = "LabRole"
  }

  # 指定 IAM 執行個體設定檔 - 實驗室預設 LabInstanceProfile
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = "LabInstanceProfile"
  }

  # 指定 EC2 登入金鑰對 - 實驗室預設 vockey
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "EC2KeyName"
    value     = "vockey"
  }

  # 指定 EC2 規格 (使用免費層級的 t3.micro 以避免實驗室權限問題)
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.micro"
  }

  # 網路設定：指定 VPC
  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = data.aws_vpc.default.id
  }

  # 網路設定：指定 Subnets
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", data.aws_subnets.default.ids)
  }
    
  # --- 新增：設定應用程式環境變數 (Environment Variables) ---
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = "database-1.cr24osc8weuk.us-east-1.rds.amazonaws.com,1433"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = "admin"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = "salu26315181"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_DB_NAME"
    value     = "cloud"
  }
}

# 6. 輸出 Elastic Beanstalk 部署後的網址
output "eb_environment_url" {
  value       = aws_elastic_beanstalk_environment.terraform_env.cname
  description = "您的 Elastic Beanstalk 應用程式網址"
}