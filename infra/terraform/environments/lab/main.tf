# =============================================================================
# ENVIRONMENT: lab
# Custo mínimo: ECS Fargate Spot + RDS Single-AZ + DynamoDB On-Demand
# Estratégia de provisionamento incremental:
#   Step 1: networking + ecr
#   Step 2: sqs + dynamodb
#   Step 3: rds
#   Step 4: ecs (depende de tudo acima)
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws"
    version = "~> 5.0" }
  }

  # Descomente após criar o bucket:
  #   aws s3 mb s3://solidarytech-tfstate --region us-east-1
  # backend "s3" {
  #   bucket  = "solidarytech-tfstate"
  #   key     = "lab/terraform.tfstate"
  #   region  = "us-east-1"
  #   encrypt = true
  # }
}

provider "aws" {
  region = var.aws_region
}

# ─── Tags globais ─────────────────────────────────────────────────────────────
locals {
  common_tags = {
    Project     = "SolidaryTech"
    Environment = "lab"
    CostCenter  = "NGO-Labs"
    ManagedBy   = "Terraform"
    Owner       = var.owner
    Phase       = "Hackathon-Phase5"
  }
}

# ─── STEP 1A: Networking ──────────────────────────────────────────────────────
module "networking" {
  source = "../../modules/networking"

  project     = "solidarytech"
  environment = "lab"
  vpc_cidr    = "10.10.0.0/16"

  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]

  enable_nat_gateway = true
  tags               = local.common_tags
}

# ─── STEP 1B: ECR ─────────────────────────────────────────────────────────────
module "ecr" {
  source     = "../../modules/ecr"
  project    = "solidarytech"
  max_images = 5
  tags       = local.common_tags
}

# ─── STEP 2A: SQS ─────────────────────────────────────────────────────────────
module "sqs" {
  source      = "../../modules/sqs"
  project     = "solidarytech"
  environment = "lab"
  use_kms     = false  # KMS desabilitado em lab (custo e complexidade)
  tags        = local.common_tags
}

# ─── STEP 2B: DynamoDB ────────────────────────────────────────────────────────
module "dynamodb" {
  source       = "../../modules/dynamodb"
  project      = "solidarytech"
  environment  = "lab"
  billing_mode = "PAY_PER_REQUEST"
  tags         = local.common_tags
}

# ─── STEP 3: RDS ──────────────────────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  project            = "solidarytech"
  environment        = "lab"
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id

  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 50
  multi_az              = false
  backup_retention_days = 1
  skip_final_snapshot   = true
  deletion_protection   = false
  db_password           = var.db_password
  tags                  = local.common_tags
}

# ─── STEP 4: ECS Fargate Spot ─────────────────────────────────────────────────
module "ecs" {
  source = "../../modules/ecs"

  project            = "solidarytech"
  environment        = "lab"
  aws_region         = var.aws_region
  registry_base      = module.ecr.registry_base
  private_subnet_ids = module.networking.private_subnet_ids
  app_sg_id          = module.networking.app_sg_id
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  alb_sg_id          = module.networking.alb_sg_id
  sqs_donations_url  = module.sqs.donations_queue_url
  volunteer_table    = module.dynamodb.volunteer_matches_table_name
  use_spot           = true
  desired_count      = 1
  log_retention_days = 3
  tags               = local.common_tags

  # Novos parâmetros para montar a URL do banco dentro do módulo do ECS
  db_host     = module.rds.endpoint
  db_port     = module.rds.port
  db_name     = module.rds.db_name
  db_user     = module.rds.username
  db_password = module.rds.password
}
