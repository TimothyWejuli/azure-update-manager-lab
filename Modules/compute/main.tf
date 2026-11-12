variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "admin_username" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type = string
}

variable "domain_netbios" {
  type = string
}

# Public IPs: Static so addresses are reserved immediately and do not change
resource "azurerm_public_ip" "dc01" {
  name                = "pip-dc01"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "ws01" {
  name                = "pip-ws01"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "ws02" {
  name                = "pip-ws02"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# All NICs use Static private IPs so Azure cannot hand .4 to a workstation
resource "azurerm_network_interface" "dc01" {
  name                = "nic-dc01"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.4"
    public_ip_address_id          = azurerm_public_ip.dc01.id
  }
}

resource "azurerm_network_interface" "ws01" {
  name                = "nic-ws01"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.5"
    public_ip_address_id          = azurerm_public_ip.ws01.id
  }
}

resource "azurerm_network_interface" "ws02" {
  name                = "nic-ws02"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.6"
    public_ip_address_id          = azurerm_public_ip.ws02.id
  }
}

locals {
  img = {
    pub   = "MicrosoftWindowsServer"
    offer = "WindowsServer"
    sku   = "2022-Datacenter"
    ver   = "latest"
  }
}

# All three VMs use Windows Server 2022 Datacenter
resource "azurerm_windows_virtual_machine" "dc01" {
  name                  = "DC01"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = "Standard_D2as_v4"
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.dc01.id]

  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.img.pub
    offer     = local.img.offer
    sku       = local.img.sku
    version   = local.img.ver
  }
}

resource "azurerm_windows_virtual_machine" "ws01" {
  name                  = "WS01"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = "Standard_D2as_v4"
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.ws01.id]

  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.img.pub
    offer     = local.img.offer
    sku       = local.img.sku
    version   = local.img.ver
  }
}

resource "azurerm_windows_virtual_machine" "ws02" {
  name                  = "WS02"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = "Standard_D2as_v4"
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.ws02.id]

  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.img.pub
    offer     = local.img.offer
    sku       = local.img.sku
    version   = local.img.ver
  }
}

# DC01: promote to Domain Controller via CustomScriptExtension.
# LAB ONLY: DSRM password is hardcoded. Never do this in production.
resource "azurerm_virtual_machine_extension" "setup_dc" {
  name                 = "SetupDC"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc01.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = join(" ", [
      "powershell -ExecutionPolicy Unrestricted -Command",
      "\"Install-WindowsFeature AD-Domain-Services -IncludeManagementTools;",
      "Import-Module ADDSDeployment;",
      "Install-ADDSForest -DomainName '${var.domain_name}'",
      "-DomainNetBiosName '${var.domain_netbios}'",
      "-SafeModeAdministratorPassword (ConvertTo-SecureString 'P@ssw0rd123!' -AsPlainText -Force)",
      "-InstallDns -Force\""
    ])
  })
}

# Join command: skips if already joined, retries until the DC answers
locals {
  join_cmd = join(" ", [
    "powershell -ExecutionPolicy Unrestricted -Command",
    "\"if((Get-CimInstance Win32_ComputerSystem).PartOfDomain){exit 0};",
    "$a=Get-NetAdapter|?{$_.Status -eq 'Up'}|Select -First 1;",
    "Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses '10.0.1.4';",
    "$cred=New-Object PSCredential('${var.domain_netbios}\\${var.admin_username}',(ConvertTo-SecureString '${var.admin_password}' -AsPlainText -Force));",
    "for($i=0;$i -lt 40;$i++){",
    "try{Add-Computer -DomainName '${var.domain_name}' -Credential $cred -Restart -Force -ErrorAction Stop;exit 0}",
    "catch{Start-Sleep 30}};",
    "exit 1\""
  ])
}

# depends_on makes the joins wait for the DC01 extension to finish
resource "azurerm_virtual_machine_extension" "join_ws01" {
  name                 = "JoinDomain"
  virtual_machine_id   = azurerm_windows_virtual_machine.ws01.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  protected_settings = jsonencode({
    commandToExecute = local.join_cmd
  })

  depends_on = [azurerm_virtual_machine_extension.setup_dc]
}

resource "azurerm_virtual_machine_extension" "join_ws02" {
  name                 = "JoinDomain"
  virtual_machine_id   = azurerm_windows_virtual_machine.ws02.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  protected_settings = jsonencode({
    commandToExecute = local.join_cmd
  })

  depends_on = [azurerm_virtual_machine_extension.setup_dc]
}

output "dc01_id" {
  value = azurerm_windows_virtual_machine.dc01.id
}

output "ws01_id" {
  value = azurerm_windows_virtual_machine.ws01.id
}

output "ws02_id" {
  value = azurerm_windows_virtual_machine.ws02.id
}

output "dc01_public_ip" {
  value = azurerm_public_ip.dc01.ip_address
}

output "ws01_public_ip" {
  value = azurerm_public_ip.ws01.ip_address
}

output "ws02_public_ip" {
  value = azurerm_public_ip.ws02.ip_address
}