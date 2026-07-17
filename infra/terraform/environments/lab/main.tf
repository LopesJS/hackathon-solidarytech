terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Backend remoto: state armazenado no S3 com lock via DynamoDB
  # Crie o bucket e a tabela manualmente ANTES do primeiro terraform init
  # Veja o passo a passo no DEPLOY.md
  backend "s3" {
    bucket         = "solidarytech-tfstate-lab"    # altere para o nome do seu bucket
    key            = "lab/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "solidarytech-tfstate-lock"   # tabela para state locking
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SolidaryTech"
      Environment = "lab"
      CostCenter  = "NGO-Core"
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# ─── SENHA DO RDS (gerada automaticamente) ────────────────────────────────────
resource "random_password" "rds" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
  rds_username    = "solidary"
  rds_password    = random_password.rds.result
  ngo_db_url      = "postgres://${local.rds_username}:${local.rds_password}@${module.rds.address}:5432/ngo_db"
  donation_db_url = "postgres://${local.rds_username}:${local.rds_password}@${module.rds.address}:5432/donation_db"
}

# ─── MÓDULOS ─────────────────────────────────────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  project     = var.project
  environment = var.environment

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b"]
  enable_nat_gateway   = true   # false para economizar no lab (tasks precisam de acesso à internet para pull de imagens ECR)

  tags = {}
}

module "ecr" {
  source = "../../modules/ecr"

  project         = var.project
  environment     = var.environment
  services        = ["ngo-service", "donation-service", "volunteer-service"]
  max_image_count = 5   # lab: guarda apenas 5 imagens

  tags = {}
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids        = module.networking.private_subnet_ids
  security_group_id = module.networking.sg_rds_id
  db_username       = local.rds_username
  db_password       = local.rds_password

  # Lab: configurações mínimas para economizar custo
  instance_class               = "db.t3.micro"
  allocated_storage            = 20
  max_allocated_storage        = 30
  multi_az                     = false
  backup_retention_days        = 1
  deletion_protection          = false
  skip_final_snapshot          = true
  performance_insights_enabled = false   # não disponível no t3.micro free tier

  tags = {}
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  table_name = "SolidaryTechVolunteers"
  enable_ttl = false

  tags = {}
}

module "sqs" {
  source = "../../modules/sqs"

  queue_name         = "solidary-donations"
  visibility_timeout = 30
  max_receive_count  = 3
  allowed_role_arns  = []   # preenchido após criação do ECS (chicken-and-egg resolvido pelo Terraform)

  tags = {}
}

module "secrets" {
  source = "../../modules/secrets"

  project     = var.project
  environment = var.environment

  ngo_database_url      = local.ngo_db_url
  donation_database_url = local.donation_db_url
  rds_password          = local.rds_password
  recovery_window_days  = 0   # lab: deleção imediata dos secrets ao fazer destroy

  tags = {}
}

module "ecs" {
  source = "../../modules/ecs"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  sg_alb_id          = module.networking.sg_alb_id
  sg_ecs_tasks_id    = module.networking.sg_ecs_tasks_id

  ecr_ngo_url       = module.ecr.repository_urls["ngo-service"]
  ecr_donation_url  = module.ecr.repository_urls["donation-service"]
  ecr_volunteer_url = module.ecr.repository_urls["volunteer-service"]
  image_tag         = var.image_tag

  ngo_db_secret_arn      = module.secrets.ngo_db_url_arn
  donation_db_secret_arn = module.secrets.donation_db_url_arn
  secret_arns = [
    module.secrets.ngo_db_url_arn,
    module.secrets.donation_db_url_arn,
  ]

  sqs_queue_url      = module.sqs.queue_url
  sqs_queue_arn      = module.sqs.queue_arn
  dynamodb_table_arn  = module.dynamodb.table_arn
  dynamodb_table_name = module.dynamodb.table_name

  # Lab: 1 task por serviço, resources mínimos
  ngo_cpu      = "256"
  ngo_memory   = "512"
  donation_cpu = "256"
  donation_memory   = "512"
  volunteer_cpu     = "256"
  volunteer_memory  = "512"

  ngo_desired_count       = 1
  donation_desired_count  = 1
  volunteer_desired_count = 1

  log_retention_days = 3   # lab: 3 dias de logs

  tags = {}

  depends_on = [module.rds, module.secrets, module.dynamodb, module.sqs]
}
