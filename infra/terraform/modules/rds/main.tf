# =============================================================================
# MODULE: rds
# PostgreSQL gerenciado para ngo-service e donation-service.
# Multi-AZ em produção, Single-AZ em lab (FinOps).
# =============================================================================

terraform {
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name  = "${var.project}-${var.environment}-rds-subnet-group"
    Layer = "database"
  })
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project}-${var.environment}-pg16"
  family = "postgres16"

  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_duration"
    value = "1"
  }
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, { Layer = "database" })
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project}-${var.environment}-postgres"

  # Engine
  engine               = "postgres"
  engine_version       = var.postgres_version
  instance_class       = var.instance_class
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Credenciais — injetadas via Secrets Manager
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Rede
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  # Alta disponibilidade (desabilitado em lab para economizar)
  multi_az = var.multi_az

  # Backup e manutenção
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot   = true
  skip_final_snapshot     = var.environment == "lab" ? true : false
  final_snapshot_identifier = var.environment == "lab" ? null : "${var.project}-${var.environment}-final-snapshot"

  # Monitoramento
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = true
  performance_insights_retention_period = 7
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Proteção (desabilitada em lab)
  deletion_protection = var.environment == "lab" ? false : true

  tags = merge(var.tags, {
    Name        = "${var.project}-${var.environment}-postgres"
    Layer       = "database"
    DataClass   = "PII-Financial"
    Service     = "ngo-service,donation-service"
  })
}

# IAM Role para Enhanced Monitoring
data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service"; identifiers = ["monitoring.rds.amazonaws.com"] }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.project}-${var.environment}-rds-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
  tags               = merge(var.tags, { Layer = "database" })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
