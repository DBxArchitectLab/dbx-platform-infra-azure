terraform {
  required_version = ">= 1.9.0" # cross-variable validation in variables.tf

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.105.0"
    }
  }
}
