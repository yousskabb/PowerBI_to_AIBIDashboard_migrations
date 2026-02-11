output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "key_vault_name" {
  description = "Name of the Key Vault (if created)"
  value       = var.create_key_vault ? azurerm_key_vault.main[0].name : null
}

output "key_vault_id" {
  description = "ID of the Key Vault (if created)"
  value       = var.create_key_vault ? azurerm_key_vault.main[0].id : var.key_vault_id
}

output "password_retrieval_command" {
  description = "Command to retrieve the admin password from Key Vault"
  value       = var.create_key_vault ? "az keyvault secret show --vault-name ${azurerm_key_vault.main[0].name} --name ${var.key_vault_secret_name} --query value -o tsv" : null
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_windows_virtual_machine.main.name
}

output "vm_id" {
  description = "ID of the virtual machine"
  value       = azurerm_windows_virtual_machine.main.id
}

output "public_ip_address" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.main.ip_address
}

output "admin_username" {
  description = "Admin username for RDP"
  value       = var.admin_username
}

output "rdp_connection" {
  description = "RDP connection string"
  value       = "mstsc /v:${azurerm_public_ip.main.ip_address}"
}

output "vm_priority" {
  description = "VM priority (Spot or Regular)"
  value       = azurerm_windows_virtual_machine.main.priority
}

output "auto_shutdown_time" {
  description = "Auto-shutdown time (UTC)"
  value       = var.auto_shutdown_time
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for occasional use"
  value       = var.use_spot_vm ? "~$6-15/month (Spot VM, storage + minimal compute)" : "~$12-20/month (Regular VM, storage + minimal compute)"
}
