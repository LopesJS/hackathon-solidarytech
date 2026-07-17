variable "project"       { type = string }
variable "environment"   { type = string }
variable "alarm_sns_arn" { type = string; default = "" }
variable "tags"          { type = map(string); default = {} }
