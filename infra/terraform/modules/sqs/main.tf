# =============================================================================
# MODULE: sqs
# Filas SQS para processamento assíncrono de doações.
# Inclui Dead Letter Queue (DLQ) para mensagens com falha.
# KMS opcional — habilitado em prod, desabilitado em lab por padrão.
# =============================================================================

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" 
    version = "~> 5.0" }
  }
}

locals {
  kms_key = var.use_kms ? "alias/aws/sqs" : null
}

# ---------------------------------------------------------------------------
# DLQ — Dead Letter Queue
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project}-${var.environment}-donations-dlq"
  message_retention_seconds = 1209600  # 14 dias
  kms_master_key_id         = local.kms_key

  tags = merge(var.tags, {
    Name    = "${var.project}-${var.environment}-donations-dlq"
    Service = "donation-service"
    Layer   = "messaging"
    Type    = "dlq"
  })
}

# ---------------------------------------------------------------------------
# Fila principal de doações
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "donations" {
  name                       = "${var.project}-${var.environment}-donations"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
  kms_master_key_id          = local.kms_key

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(var.tags, {
    Name      = "${var.project}-${var.environment}-donations"
    Service   = "donation-service"
    Layer     = "messaging"
    DataClass = "PII-Financial"
  })
}

# ---------------------------------------------------------------------------
# Fila de notificações para voluntários
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "volunteer_notifications" {
  name                      = "${var.project}-${var.environment}-volunteer-notifications"
  message_retention_seconds = 3600
  receive_wait_time_seconds = 10
  kms_master_key_id         = local.kms_key

  tags = merge(var.tags, {
    Name    = "${var.project}-${var.environment}-volunteer-notifications"
    Service = "volunteer-service"
    Layer   = "messaging"
  })
}

# ---------------------------------------------------------------------------
# Alarme CloudWatch — DLQ com mensagens
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.project}-${var.environment}-dlq-not-empty"
  alarm_description   = "Mensagens na DLQ de doações — investigar imediatamente"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
  treat_missing_data  = "notBreaching"

  tags = merge(var.tags, { Layer = "monitoring" })
}
