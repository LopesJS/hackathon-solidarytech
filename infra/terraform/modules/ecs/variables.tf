variable "project"            { type = string }
variable "environment"        { type = string }
variable "aws_region"         { 
  type = string
  default = "us-east-1" 
}

# Registry ECR — hostname da conta (sem o path do repositório)
# Exemplo: 486630403283.dkr.ecr.us-east-1.amazonaws.com
variable "registry_base"      { type = string }

variable "image_tag"          { 
  type = string
  default = "latest" 
}
variable "private_subnet_ids" { type = list(string) }
variable "app_sg_id"          { type = string }
variable "sqs_donations_url"  { 
  type = string
  default = "" 
}
variable "volunteer_table"    { 
  type = string
  default = "" 
}
variable "use_spot"           { 
  type = bool   
  default = true 
}
variable "desired_count"      { 
  type = number
  default = 1 
}
variable "log_retention_days" { 
  type = number
  default = 7 
}
variable "tags"               { 
  type = map(string)
  default = {} 
}

# ---------------------------------------------------------------------------
# Componentes do RDS para montar DATABASE_URL
# Passados pelo lab/main.tf a partir dos outputs do módulo rds
# ---------------------------------------------------------------------------
variable "db_host" {
  type        = string
  default     = ""
  description = "Endpoint do RDS (module.rds.endpoint)"
}

variable "db_port" {
  type        = number
  default     = 5432
  description = "Porta do PostgreSQL (module.rds.port)"
}

variable "db_name" {
  type        = string
  default     = "solidarytech"
  description = "Nome do banco (module.rds.db_name)"
}

variable "db_user" {
  type        = string
  default     = "solidary_admin"
  description = "Usuário do banco (module.rds.username)"
}

variable "db_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Senha do banco (module.rds.password)"
}
