variable "client_id" {
  description = "Azure client ID"
  type        = string
}

variable "rg_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
}

variable "node_count" {
  description = "Number of nodes"
  type        = number
}

variable "backend_rg" {
  description = "Backend resource group for state"
  type        = string
}

variable "storage_account_name" {
  description = "Storage account for backend state"
  type        = string
}

variable "container_name" {
  description = "Container for backend state"
  type        = string
}

variable "state_file_name" {
  description = "State file name"
  type        = string
}

variable "keyvault_name" {
  default = "my-keyvault-name"
}

variable "tenant_id" {}

