variable "gcp_project_id" { type = string }
variable "gcp_region"     { type = string; default = "us-east1" }
variable "db_password"    { type = string; sensitive = true }
