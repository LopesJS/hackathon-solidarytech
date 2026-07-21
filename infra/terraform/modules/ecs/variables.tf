variable "project"             { type = string }
variable "environment"         { type = string }
variable "aws_region"          { 
    type = string
    default = "us-east-1" 
}
variable "registry_base"       { type = string }
variable "image_tag"           { 
    type = string
    default = "latest" 
}
variable "private_subnet_ids"  { type = list(string) }
variable "app_sg_id"           { type = string }
variable "db_endpoint"         { 
    type = string
    default = "" 
}
variable "sqs_donations_url"   { 
    type = string
    default = "" 
}
variable "volunteer_table"     { 
    type = string
    default = "" 
}
variable "use_spot"            { 
    type = bool
    default = true 
}
variable "desired_count"       { 
    type = number
    default = 1 
}
variable "log_retention_days"  { 
    type = number
    default = 7 
}
variable "tags"                { 
    type = map(string)
    default = {} 
}
