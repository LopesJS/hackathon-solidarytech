variable "project"        { type = string }
variable "environment"    { type = string }
variable "billing_mode"   { 
    type = string
    default = "PAY_PER_REQUEST" 
}
variable "read_capacity"  { 
    type = number
    default = 5 
}
variable "write_capacity" { 
    type = number 
    default = 5 
}
variable "tags"           { 
    type = map(string)
    default = {} 
}
