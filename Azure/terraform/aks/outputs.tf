output "kube_config" {
  value = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

output "keyvault_name" {
  value = azurerm_key_vault.main.name
}