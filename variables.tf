variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "rg-aumlab"
}

variable "admin_username" {
  type    = string
  default = "labadmin"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Local admin password for all VMs. Set with TF_VAR_admin_password; never commit it."
}

variable "allowed_rdp_ip" {
  type        = string
  description = "Your public IP in CIDR form (x.x.x.x/32) allowed to RDP to the VMs."
}

variable "domain_name" {
  type    = string
  default = "aumlab.local"
}

variable "domain_netbios" {
  type    = string
  default = "AUMLAB"
}
