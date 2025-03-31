terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

##############################################
# Terraform Backend Configuration (AzureRM)
##############################################

terraform {
  backend "azurerm" {}
}

##############################################
# Azure Provider Configuration
##############################################

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

##############################################
# Retrieve Existing Resource Group and OIDC SPN
##############################################

data "azurerm_resource_group" "main" {
  name = var.rg_name
}

data "azuread_service_principal" "github_actions_oidc" {
  display_name = "github-actions-oidc"
}

##############################################
# Create Azure Kubernetes Service (AKS) Cluster
##############################################

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = "aks"

  default_node_pool {
    name       = "agentpool"
    node_count = var.node_count
    vm_size    = "Standard_D2s_v3"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "production"
  }
}

##############################################
# Create Azure Key Vault
##############################################

resource "azurerm_key_vault" "main" {
  name                        = var.keyvault_name
  location                    = var.location
  resource_group_name         = var.rg_name
  tenant_id                   = var.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = false
  enable_rbac_authorization   = true
}

##############################################
# Assign GitHub Actions OIDC as Key Vault Secrets Officer
##############################################

resource "azurerm_role_assignment" "keyvault_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_service_principal.github_actions_oidc.object_id
  depends_on           = [azurerm_key_vault.main]
}
