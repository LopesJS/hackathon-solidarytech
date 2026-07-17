variable "project" { type = string }
variable "environment" { type = string }

variable "ngo_database_url" {
  type      = string
  sensitive = true
}

variable "donation_database_url" {
  type      = string
  sensitive = true
}

variable "rds_password" {
  type      = string
  sensitive = true
}

variable "recovery_window_days" {
  type    = number
  default = 0   # 0 = deleção imediata (útil no lab)
}

variable "tags" {
  type    = map(string)
  default = {}
}
