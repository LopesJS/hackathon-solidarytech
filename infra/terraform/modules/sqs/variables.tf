variable "project"      { 
    type = string 
}
variable "environment"   { 
    type = string 
}
variable "use_kms"       { 
    type = bool
    default = false
    description = "Habilitar KMS no SQS (false em lab, true em prod)" 
}
variable "alarm_sns_arn" { 
    type = string
    default = "" 
}
variable "tags"          { 
    type = map(string)
    default = {} 
}
