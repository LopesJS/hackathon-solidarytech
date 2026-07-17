# =============================================================================
# MODULE: ecs
# ECS Fargate — alternativa ao EKS para ambientes lab/DR (custo menor).
# Executa os três microsserviços SolidaryTech sem necessidade de gerenciar nós.
# =============================================================================

terraform {
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
  }
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
# CloudWatch Log Group
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
# IAM — Task Execution Role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service"; identifiers = ["ecs-tasks.amazonaws.com"] }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.project}-${var.environment}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = merge(var.tags, { Layer = "ecs" })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# Task Definitions (uma por serviço)
# ---------------------------------------------------------------------------
locals {
  services = {
    "ngo-service" = {
      port   = 8081
      cpu    = 256
      memory = 512
      image  = "${var.ecr_base_url}/solidarytech/ngo-service:${var.image_tag}"
      env = [
        { name = "PORT",          value = "8081" },
        { name = "DB_HOST",       value = var.db_endpoint },
        { name = "DB_NAME",       value = "ngo_db" },
        { name = "ENVIRONMENT",   value = var.environment },
      ]
    }
    "donation-service" = {
      port   = 8082
      cpu    = 512
      memory = 1024
      image  = "${var.ecr_base_url}/solidarytech/donation-service:${var.image_tag}"
      env = [
        { name = "PORT",          value = "8082" },
        { name = "DB_HOST",       value = var.db_endpoint },
        { name = "DB_NAME",       value = "donation_db" },
        { name = "SQS_URL",       value = var.sqs_donations_url },
        { name = "ENVIRONMENT",   value = var.environment },
      ]
    }
    "volunteer-service" = {
      port   = 8083
      cpu    = 256
      memory = 512
      image  = "${var.ecr_base_url}/solidarytech/volunteer-service:${var.image_tag}"
      env = [
        { name = "PORT",          value = "8083" },
        { name = "DYNAMO_TABLE",  value = var.volunteer_table },
        { name = "ENVIRONMENT",   value = var.environment },
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
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_execution.arn

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
      startPeriod = 10
    }
  }])

  tags = merge(var.tags, {
    Service = each.key
    Layer   = "compute"
  })
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
    ignore_changes = [desired_count]  # gerenciado pelo autoscaling
  }
}
