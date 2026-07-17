variable "project"              { type = string }
variable "environment"          { type = string }
variable "private_subnet_ids"   { type = list(string) }
variable "rds_sg_id"            { type = string }
variable "postgres_version"     { type = string; default = "16.3" }
variable "instance_class"       { type = string; default = "db.t3.micro" }
variable "allocated_storage"    { type = number; default = 20 }
variable "max_allocated_storage"{ type = number; default = 100 }
variable "db_name"              { type = string; default = "solidarytech" }
variable "db_username"          { type = string; default = "solidary_admin" }
variable "db_password"          { type = string; sensitive = true }
variable "multi_az"             { type = bool; default = false }
variable "backup_retention_days"{ type = number; default = 7 }
variable "tags"                 { type = map(string); default = {} }
