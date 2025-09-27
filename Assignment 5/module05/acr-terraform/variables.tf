# Core variables (used by both ACR and AKS)
variable "resource_group_name" {
  description = "Existing resource group name"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

# ACR inputs
variable "acr_name" {
  description = "Container Registry name (no FQDN)"
  type        = string
}

# AKS inputs
variable "aks_name" {
  description = "AKS cluster name"
  type        = string
  default     = "aks-m09-tf"
}

variable "system_node_count" {
  description = "System nodepool count"
  type        = number
  default     = 1
}

variable "gpu_node_count" {
  description = "GPU nodepool count"
  type        = number
  default     = 1
}
