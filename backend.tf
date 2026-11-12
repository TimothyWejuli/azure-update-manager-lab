# Remote state. Create the storage account first, or delete this file to keep state local.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "<your-state-storage-account>"
    container_name       = "tfstate"
    key                  = "azure-update-manager-lab.tfstate"
    use_azuread_auth     = true
  }
}