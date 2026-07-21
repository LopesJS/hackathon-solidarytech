# =============================================================================
# MODULE: dynamodb
# Tabelas DynamoDB para volunteer-service e analytics de doações.
# On-Demand em lab/dev; Provisioned em produção com autoscaling.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Tabela: volunteer_matches
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "volunteer_matches" {
  # Modificado: adicionado o sufixo -v2 para contornar o recurso órfão do Lab
  name         = "${var.project}-${var.environment}-volunteer-matches-v2"
  billing_mode = var.billing_mode
  hash_key     = "volunteerId"
  range_key    = "campaignId"

  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  attribute {
    name = "volunteerId"
    type = "S"
  }

  attribute {
    name = "campaignId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "campaignId"
    projection_type = "ALL"

    read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
    write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = var.environment == "lab" ? false : true

  tags = merge(var.tags, {
    Name    = "${var.project}-${var.environment}-volunteer-matches-v2"
    Service = "volunteer-service"
    Layer   = "database"
  })
}

# ---------------------------------------------------------------------------
# Tabela: donation_events (analytics)
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "donation_events" {
  # Modificado: adicionado o sufixo -v2 por consistência de arquitetura
  name         = "${var.project}-${var.environment}-donation-events-v2"
  billing_mode = var.billing_mode
  hash_key     = "donationId"
  range_key    = "eventTimestamp"

  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  attribute {
    name = "donationId"
    type = "S"
  }

  attribute {
    name = "eventTimestamp"
    type = "S"
  }

  attribute {
    name = "ngoId"
    type = "S"
  }

  global_secondary_index {
    name            = "ngo-timeline-index"
    hash_key        = "ngoId"
    range_key       = "eventTimestamp"
    projection_type = "ALL"

    read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
    write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = var.environment == "lab" ? false : true

  tags = merge(var.tags, {
    Name      = "${var.project}-${var.environment}-donation-events-v2"
    Service   = "donation-service"
    Layer     = "database"
    DataClass = "PII-Financial"
  })
}
