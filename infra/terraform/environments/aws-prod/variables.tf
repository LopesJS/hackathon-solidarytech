variable "aws_region"      { type = string; default = "us-east-1" }
variable "aws_account_id"  { type = string }
variable "owner"           { type = string; default = "devops-team" }
variable "db_password"     { type = string; sensitive = true }
variable "alarm_sns_arn"   { type = string; default = "" }
