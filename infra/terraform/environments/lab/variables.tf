variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Região AWS para o ambiente lab"
}

variable "owner" {
  type        = string
  default     = "devops-team"
  description = "Time responsável pelos recursos"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Senha do PostgreSQL — passe via TF_VAR_db_password ou -var"
  validation {
    condition     = length(var.db_password) >= 12
    error_message = "Senha deve ter ao menos 12 caracteres."
  }
}
