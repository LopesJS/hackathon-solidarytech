variable "project"               { type = string }
variable "environment"           { type = string }
variable "private_subnet_ids"    { type = list(string) }
variable "rds_sg_id"             { type = string }
variable "postgres_version"      { 
  type = string
  default = "16" 
}
variable "instance_class"        { 
  type = string
  default = "db.t3.micro" 
}
variable "allocated_storage"     { 
  type = number
  default = 20 
}
variable "max_allocated_storage" { 
  type = number
  default = 100 
}
variable "db_name"               { 
  type = string
  default = "solidarytech" 
}
variable "db_username"           { 
  type = string
  default = "solidary_admin" 
}
variable "db_password"           { 
  type = string
  sensitive = true 
}
variable "multi_az"              { 
  type = bool
  default = false 
}
variable "backup_retention_days" { 
  type = number
  default = 7 
}
variable "skip_final_snapshot"   { 
  type = bool
  default = true 
}
variable "deletion_protection"   { 
  type = bool
  default = false 
}
variable "tags"                  { 
  type = map(string)
  default = {} 
}

# Monitoramento avançado — deixar vazio em Vocareum (sem permissão iam:CreateRole)
# Em conta real: passe o ARN da role AmazonRDSEnhancedMonitoringRole
variable "monitoring_role_arn" {
  type        = string
  default     = ""
  description = "ARN da IAM Role para Enhanced Monitoring. Deixar vazio em Vocareum."
}

variable "enable_performance_insights" {
  type        = bool
  default     = false
  description = "Habilitar Performance Insights. false em Vocareum (conta Academy)."
}
