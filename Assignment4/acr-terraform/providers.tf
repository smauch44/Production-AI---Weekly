terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.117" }
  }
}
provider "azurerm" {
  features {}
}
