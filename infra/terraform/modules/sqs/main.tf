# =============================================================================
# MODULE: sqs
# Filas SQS para processamento assíncrono de doações.
# Inclui Dead Letter Queue (DLQ) para mensagens com falha.
# =============================================================================

terraform {
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
  }
}

# ---------------------------------------------------------------------------
# DLQ — Dead Letter Queue
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "dlq" {
  name                       = "${var.project}-${var.environment}-donations-dlq"
  message_retention_seconds  = 1209600  # 14 dias
  kms_master_key_id          = "alias/aws/sqs"

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
  visibility_timeout_seconds = 300          # 5 min (tempo para processar 1 doação)
  message_retention_seconds  = 86400        # 24h
  receive_wait_time_seconds  = 20           # Long polling — reduz custo
  kms_master_key_id          = "alias/aws/sqs"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3                 # 3 tentativas antes da DLQ
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
  message_retention_seconds = 3600         # 1h (notificações têm validade curta)
  receive_wait_time_seconds = 10
  kms_master_key_id         = "alias/aws/sqs"

  tags = merge(var.tags, {
    Name    = "${var.project}-${var.environment}-volunteer-notifications"
    Service = "volunteer-service"
    Layer   = "messaging"
  })
}

# ---------------------------------------------------------------------------
# Alarme CloudWatch — DLQ com mensagens (alerta de falhas)
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
