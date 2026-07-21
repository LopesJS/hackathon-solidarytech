variable "project"            { type = string }
variable "environment"        { type = string }
variable "kubernetes_version" { 
    type = string
    default = "1.30" 
}
variable "public_subnet_ids"  { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "cluster_sg_id"      { type = string }
variable "public_access"      { 
    type = bool
    default = true 
}
variable "instance_types"     { 
    type = list(string)
    default = ["t3.medium"] 
}
variable "use_spot"           { 
    type = bool
    default = false 
}
variable "node_desired"       { 
    type = number
    default = 2 
}
variable "node_min"           { 
    type = number
    default = 1 
}
variable "node_max"           { 
    type = number
    default = 5 
}
variable "tags"               { 
    type = map(string)
    default = {} 
}
