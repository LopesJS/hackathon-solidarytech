# =============================================================================
# MODULE: rds — PostgreSQL gerenciado
# Vocareum/AWS Academy: iam:CreateRole bloqueado.
# Enhanced Monitoring e Performance Insights desabilitados por padrão.
# Habilitados apenas quando var.monitoring_role_arn for fornecido.
# =============================================================================

terraform {
  required_providers {
    aws = { 
      source = "hashicorp/aws"
      version = "~> 5.0" 
      }
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-rds-subnet-group-v3"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name  = "${var.project}-${var.environment}-rds-subnet-group"
    Layer = "database"
  })
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project}-${var.environment}-pg16-v3"
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
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, { Layer = "database" })

  lifecycle {
    create_before_destroy = true
  }
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

  # Credenciais
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Rede
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  # Alta disponibilidade
  multi_az = var.multi_az

  # Backup e manutenção
  backup_retention_period   = var.backup_retention_days
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project}-${var.environment}-final-snapshot"

  # Monitoramento — desabilitado quando não há role disponível (Vocareum)
  # Para habilitar em conta real: passe monitoring_role_arn no tfvars
  monitoring_interval = var.monitoring_role_arn != "" ? 60 : 0
  monitoring_role_arn = var.monitoring_role_arn != "" ? var.monitoring_role_arn : null

  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? 7 : null

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Proteção
  deletion_protection = var.deletion_protection

  tags = merge(var.tags, {
    Name      = "${var.project}-${var.environment}-postgres"
    Layer     = "database"
    DataClass = "PII-Financial"
    Service   = "ngo-service donation-service"
  })

  depends_on = [aws_db_parameter_group.postgres]
}
