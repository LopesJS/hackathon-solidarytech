# =============================================================================
# SOLIDARYTECH — POLÍTICA GLOBAL DE TAGS (FinOps)
# Fase 5 · POSTECH DCLT Hackathon
# =============================================================================
# Todas as tags obrigatórias são definidas aqui e propagadas via merge()
# em todos os módulos. Nunca adicione recursos sem passar var.tags.
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # Tags obrigatórias — FinOps / governança
  # ---------------------------------------------------------------------------
  mandatory_tags = {
    Project     = "SolidaryTech"
    ManagedBy   = "Terraform"
    Repository  = "github.com/seu-org/solidarytech-infra"
    Phase       = "Hackathon-Phase5"
    UpdatedAt   = timestamp()
  }

  # ---------------------------------------------------------------------------
  # Tags por ambiente — injetadas pelo caller (environments/*)
  # ---------------------------------------------------------------------------
  environment_tags = {
    Environment = var.environment          # lab | prod | dr
    CostCenter  = var.cost_center          # NGO-Core | NGO-Labs
    Owner       = var.owner                # equipe responsável
    Region      = var.aws_region
  }

  # ---------------------------------------------------------------------------
  # Tags de compliance e segurança
  # ---------------------------------------------------------------------------
  compliance_tags = {
    DataClassification = var.data_classification  # public | internal | confidential
    Compliance         = "LGPD"
    BackupEnabled      = tostring(var.backup_enabled)
  }

  # ---------------------------------------------------------------------------
  # Tag set final — use em todos os recursos:
  #   tags = merge(local.common_tags, { Service = "donation-service" })
  # ---------------------------------------------------------------------------
  common_tags = merge(
    local.mandatory_tags,
    local.environment_tags,
    local.compliance_tags,
  )
}

# ---------------------------------------------------------------------------
# Variáveis injetadas pelo environment (não têm default aqui de propósito)
# ---------------------------------------------------------------------------
variable "environment" {
  description = "Nome do ambiente (lab | aws-prod | dr)"
  type        = string
  validation {
    condition     = contains(["lab", "aws-prod", "dr"], var.environment)
    error_message = "Ambiente inválido. Use: lab, aws-prod ou dr."
  }
}

variable "cost_center" {
  description = "Centro de custo para alocação FinOps"
  type        = string
  default     = "NGO-Core"
}

variable "owner" {
  description = "Time ou pessoa responsável pelos recursos"
  type        = string
  default     = "devops-team"
}

variable "aws_region" {
  description = "Região AWS onde os recursos são criados"
  type        = string
  default     = "us-east-1"
}

variable "data_classification" {
  description = "Classificação dos dados processados (public | internal | confidential)"
  type        = string
  default     = "confidential"
}

variable "backup_enabled" {
  description = "Indica se backup automático está habilitado"
  type        = bool
  default     = true
}
