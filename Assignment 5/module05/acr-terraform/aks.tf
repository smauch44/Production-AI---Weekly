resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.aks_name}-dns"

  kubernetes_version = "1.32"

  default_node_pool {
    name                 = "system"
    vm_size              = "Standard_D2s_v3"
    node_count           = var.system_node_count
    orchestrator_version = "1.32"
    upgrade_settings { max_surge = "10%" }
  }

  identity { type = "SystemAssigned" }
}

resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpunp"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_NC4as_T4_v3"
  node_count            = var.gpu_node_count
  mode                  = "User"
  node_taints           = ["sku=gpu:NoSchedule"]
  orchestrator_version  = "1.32"
}

# Let AKS pull images from your ACR
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
