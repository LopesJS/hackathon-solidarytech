variable "project"            { type = string }
variable "environment"        { type = string }
variable "aws_region"         { 
  type = string
  default = "us-east-1" 
}

# Registry ECR — hostname da conta (sem o path do repositório)
variable "registry_base"      { type = string }
variable "image_tag"          { 
  type = string
  default = "latest" 
}

# Rede — subnets e SGs vindos do módulo networking
variable "vpc_id"             { type = string }
variable "public_subnet_ids"  { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "alb_sg_id"          { type = string }
variable "app_sg_id"          { type = string }

# Serviços AWS
variable "sqs_donations_url"  { 
  type = string
  default = "" 
}
variable "volunteer_table"    { 
  type = string
  default = "" 
}

# Fargate
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

# Componentes do RDS para montar DATABASE_URL
variable "db_host"     { 
  type = string
  default = "" 
}
variable "db_port"     { 
  type = number
  default = 5432 
}
variable "db_name"     { 
  type = string
  default = "solidarytech" 
}
variable "db_user"     { 
  type = string
  default = "solidary_admin" 
}
variable "db_password" { 
  type = string
  sensitive = true
  default = "" 
}

# New Relic (opcional — usado na instrumentação OTel)
variable "newrelic_license_key" {
  type      = string
  sensitive = true
  default   = ""
}
