# =============================================================================
# ENVIRONMENT: aws-prod
# Produção AWS: EKS + RDS Multi-AZ + Velero DR + monitoramento completo.
# =============================================================================

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "solidarytech-tfstate"
    key            = "aws-prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "solidarytech-tfstate-lock"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project            = "SolidaryTech"
    Environment        = "Production"
    CostCenter         = "NGO-Core"
    ManagedBy          = "Terraform"
    Owner              = var.owner
    Phase              = "Hackathon-Phase5"
    DataClassification = "confidential"
    Compliance         = "LGPD"
    BackupEnabled      = "true"
  }
}

# ─── Networking ───────────────────────────────────────────────────────────────
module "networking" {
  source = "../../modules/networking"

  project     = "solidarytech"
  environment = "prod"
  vpc_cidr    = "10.0.0.0/16"

  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
  tags               = local.common_tags
}

# ─── ECR ──────────────────────────────────────────────────────────────────────
module "ecr" {
  source     = "../../modules/ecr"
  project    = "solidarytech"
  max_images = 20
  tags       = local.common_tags
}

# ─── EKS ──────────────────────────────────────────────────────────────────────
module "eks" {
  source = "../../modules/eks"

  project            = "solidarytech"
  environment        = "prod"
  kubernetes_version = "1.30"
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  cluster_sg_id      = module.networking.app_sg_id

  instance_types = ["t3.medium", "t3.large"]
  use_spot       = true   # Spot com On-Demand fallback
  node_desired   = 3
  node_min       = 2
  node_max       = 10

  tags = local.common_tags
}

# ─── RDS ──────────────────────────────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  project            = "solidarytech"
  environment        = "prod"
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id

  instance_class        = "db.t3.small"
  allocated_storage     = 50
  max_allocated_storage = 200
  multi_az              = true    # Alta disponibilidade
  backup_retention_days = 30      # 30 dias de backup
  db_password           = var.db_password
  tags                  = local.common_tags
}

# ─── DynamoDB ─────────────────────────────────────────────────────────────────
module "dynamodb" {
  source       = "../../modules/dynamodb"
  project      = "solidarytech"
  environment  = "prod"
  billing_mode = "PAY_PER_REQUEST"
  tags         = local.common_tags
}

# ─── SQS ──────────────────────────────────────────────────────────────────────
module "sqs" {
  source        = "../../modules/sqs"
  project       = "solidarytech"
  environment   = "prod"
  alarm_sns_arn = var.alarm_sns_arn
  tags          = local.common_tags
}

# ─── S3 para backups Velero ───────────────────────────────────────────────────
resource "aws_s3_bucket" "velero" {
  bucket = "solidarytech-velero-backups-${var.aws_account_id}"
  tags   = merge(local.common_tags, { Name = "solidarytech-velero-backups", Layer = "backup" })
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id
  rule {
    id     = "transition-old-backups"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    noncurrent_version_expiration { noncurrent_days = 180 }
  }
}
