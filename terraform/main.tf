# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Fetch password from existing Key Vault if configured
data "azurerm_key_vault_secret" "admin_password" {
  count        = var.key_vault_id != null ? 1 : 0
  name         = var.key_vault_secret_name
  key_vault_id = var.key_vault_id
}

# Generate random password if creating new Key Vault
resource "random_password" "admin" {
  count            = var.create_key_vault ? 1 : 0
  length           = 24
  special          = true
  override_special = "!@#$%&*"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Create Key Vault
resource "azurerm_key_vault" "main" {
  count                      = var.create_key_vault ? 1 : 0
  name                       = "kv-${var.vm_name}-${random_string.kv_suffix[0].result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge",
      "Recover"
    ]
  }

  tags = var.tags
}

# Random suffix for Key Vault name (must be globally unique)
resource "random_string" "kv_suffix" {
  count   = var.create_key_vault ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

# Store password in Key Vault
resource "azurerm_key_vault_secret" "admin_password" {
  count        = var.create_key_vault ? 1 : 0
  name         = var.key_vault_secret_name
  value        = random_password.admin[0].result
  key_vault_id = azurerm_key_vault.main[0].id

  depends_on = [azurerm_key_vault.main]
}

locals {
  # Priority: 1) Existing Key Vault, 2) New Key Vault, 3) Direct password
  admin_password = (
    var.key_vault_id != null ? data.azurerm_key_vault_secret.admin_password[0].value :
    var.create_key_vault ? random_password.admin[0].result :
    var.admin_password
  )
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.vm_name}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = "snet-${var.vm_name}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "nsg-${var.vm_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefixes    = var.allowed_rdp_ips
    destination_address_prefix = "*"
  }
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Public IP
resource "azurerm_public_ip" "main" {
  name                = "pip-${var.vm_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "nic-${var.vm_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Windows Virtual Machine (Spot for cost savings)
resource "azurerm_windows_virtual_machine" "main" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = local.admin_password
  tags                = var.tags
  zone                = "3"

  network_interface_ids = [azurerm_network_interface.main.id]

  # Spot VM configuration for cost savings
  priority        = var.use_spot_vm ? "Spot" : "Regular"
  eviction_policy = var.use_spot_vm ? "Deallocate" : null
  max_bid_price   = var.use_spot_vm ? -1 : null # -1 means pay up to on-demand price

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # Standard SSD for cost savings
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-23h2-pro"
    version   = "latest"
  }

  # Enable boot diagnostics with managed storage
  boot_diagnostics {
    storage_account_uri = null # Use managed storage account
  }
}

# Auto-shutdown schedule
resource "azurerm_dev_test_global_vm_shutdown_schedule" "main" {
  virtual_machine_id = azurerm_windows_virtual_machine.main.id
  location           = azurerm_resource_group.main.location
  enabled            = true

  daily_recurrence_time = var.auto_shutdown_time
  timezone              = "UTC"

  notification_settings {
    enabled = false
  }

  tags = var.tags
}

# Custom Script Extension to install Power BI Desktop
resource "azurerm_virtual_machine_extension" "install_powerbi" {
  name                       = "install-powerbi"
  virtual_machine_id         = azurerm_windows_virtual_machine.main.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
  {
    "commandToExecute": "powershell -ExecutionPolicy Unrestricted -Command \"Start-Sleep -Seconds 60; $url='https://download.microsoft.com/download/8/8/0/880BCA75-79DD-466A-927D-1ABF1F5454B0/PBIDesktopSetup_x64.exe'; $out='C:\\temp\\PBIDesktopSetup_x64.exe'; New-Item -ItemType Directory -Force -Path 'C:\\temp'; Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing; Start-Process -FilePath $out -ArgumentList '-quiet','-norestart','ACCEPT_EULA=1' -Wait\""
  }
  SETTINGS

  tags = var.tags

  depends_on = [azurerm_windows_virtual_machine.main]
}
