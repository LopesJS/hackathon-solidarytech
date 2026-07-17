variable "azure_location"     { type = string; default = "East US" }
variable "kubernetes_version" { type = string; default = "1.30" }
variable "node_count"         { type = number; default = 1 }
variable "vm_size"            { type = string; default = "Standard_B2s" }
variable "db_password"        { type = string; sensitive = true }
