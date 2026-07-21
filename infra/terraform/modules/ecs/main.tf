# =============================================================================
# MODULE: ecs — ECS Fargate
# Vocareum/AWS Academy: iam:CreateRole bloqueado.
# Usa LabRole pré-existente via data source.
# DATABASE_URL montada a partir dos componentes do RDS (sem Secrets Manager).
# =============================================================================

terraform {
  required_providers {
    aws = { 
      source = "hashicorp/aws"
      version = "~> 5.0" 
    }
  }
}

# ---------------------------------------------------------------------------
# IAM — Vocareum: usa LabRole pré-existente (iam:CreateRole não permitido)
# ---------------------------------------------------------------------------
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# ---------------------------------------------------------------------------
# Cluster ECS
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, {
    Name  = "${var.project}-${var.environment}-ecs"
    Layer = "compute"
  })
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Log Groups
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "services" {
  for_each          = toset(["ngo-service", "donation-service", "volunteer-service"])
  name              = "/ecs/${var.project}/${var.environment}/${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Service = each.key
    Layer   = "logging"
  })
}

# ---------------------------------------------------------------------------
# DATABASE_URL montada a partir dos componentes individuais do RDS
# Evita dependência de Secrets Manager (Vocareum não permite iam:PassRole
# para injeção de secrets em task definitions sem role própria)
# ---------------------------------------------------------------------------
locals {
  database_url = "postgres://${var.db_user}:${var.db_password}@${var.db_host}:${var.db_port}/${var.db_name}?sslmode=require"
}

# ---------------------------------------------------------------------------
# Task Definitions — uma por serviço
# ---------------------------------------------------------------------------
locals {
  services = {
    "ngo-service" = {
      port   = 8081
      cpu    = 256
      memory = 512
      image  = "${var.registry_base}/solidarytech/ngo-service:${var.image_tag}"
      env = [
        { name = "PORT",         value = "8081" },
        { name = "DATABASE_URL", value = local.database_url },
        { name = "ENVIRONMENT",  value = var.environment },
      ]
    }
    "donation-service" = {
      port   = 8082
      cpu    = 512
      memory = 1024
      image  = "${var.registry_base}/solidarytech/donation-service:${var.image_tag}"
      env = [
        { name = "PORT",         value = "8082" },
        { name = "DATABASE_URL", value = local.database_url },
        { name = "AWS_SQS_URL",  value = var.sqs_donations_url },
        { name = "AWS_REGION",   value = var.aws_region },
        { name = "ENVIRONMENT",  value = var.environment },
      ]
    }
    "volunteer-service" = {
      port   = 8083
      cpu    = 256
      memory = 512
      image  = "${var.registry_base}/solidarytech/volunteer-service:${var.image_tag}"
      env = [
        { name = "PORT",         value = "8083" },
        { name = "DYNAMO_TABLE", value = var.volunteer_table },
        { name = "AWS_REGION",   value = var.aws_region },
        { name = "ENVIRONMENT",  value = var.environment },
      ]
    }
  }
}

resource "aws_ecs_task_definition" "services" {
  for_each = local.services

  family                   = "${var.project}-${var.environment}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = each.value.image
    essential = true
    portMappings = [{ containerPort = each.value.port, protocol = "tcp" }]
    environment  = each.value.env
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.project}/${var.environment}/${each.key}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${each.value.port}/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
  }])

  tags = merge(var.tags, {
    Service = each.key
    Layer   = "compute"
  })

  depends_on = [aws_cloudwatch_log_group.services]
}

# ---------------------------------------------------------------------------
# ECS Services
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "services" {
  for_each = local.services

  name            = each.key
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_sg_id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(var.tags, {
    Service = each.key
    Layer   = "compute"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }
}
