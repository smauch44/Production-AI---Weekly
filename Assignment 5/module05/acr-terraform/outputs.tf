# ACR
output "acr_name" {
  value = azurerm_container_registry.acr.name
}
output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

# AKS
output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}
output "gpu_pool_name" {
  value = azurerm_kubernetes_cluster_node_pool.gpu.name
}
