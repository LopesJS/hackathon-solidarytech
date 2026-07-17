# =============================================================================
# ENVIRONMENT: azure
# Multicloud DR — AKS (Azure Kubernetes Service) como região de warm standby.
# Ativado apenas em cenário de DR (RTO: 4h para donation-service).
# =============================================================================

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
  backend "azurerm" {
    resource_group_name  = "solidarytech-tfstate-rg"
    storage_account_name = "solidarytechstate"
    container_name       = "tfstate"
    key                  = "azure/terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group { prevent_deletion_if_contains_resources = false }
  }
}

locals {
  common_tags = {
    Project     = "SolidaryTech"
    Environment = "azure-dr"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
    Phase       = "Hackathon-Phase5"
  }
  location    = var.azure_location
  prefix      = "solidarytech-dr"
}

# ─── Resource Group ───────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "${local.prefix}-rg"
  location = local.location
  tags     = local.common_tags
}

# ─── Virtual Network ──────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "${local.prefix}-vnet"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks" {
  name                 = "${local.prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.1.0/24"]
}

# ─── AKS Cluster (warm standby mínimo) ───────────────────────────────────────
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.prefix}-aks"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.vm_size
    vnet_subnet_id = azurerm_subnet.aks.id
    os_disk_size_gb = 50
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = local.common_tags
}

# ─── Azure Container Registry (ACR) ───────────────────────────────────────────
resource "azurerm_container_registry" "main" {
  name                = "solidarytechdrregistry"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.common_tags
}

# Permitir AKS fazer pull do ACR
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}

# ─── PostgreSQL Flexible Server (DR) ──────────────────────────────────────────
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${local.prefix}-postgres"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "16"
  administrator_login    = "solidary_admin"
  administrator_password = var.db_password
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"   # Mínimo — warm standby
  backup_retention_days  = 7
  tags                   = local.common_tags
}
