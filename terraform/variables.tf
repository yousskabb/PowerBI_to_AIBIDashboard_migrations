variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-powerbi-dev"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "vm-powerbi"
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_D2s_v3" # 2 vCPU, 8GB RAM - good for Power BI
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "powerbi-admin"
}

variable "admin_password" {
  description = "Admin password for the VM (ignored if using Key Vault)"
  type        = string
  sensitive   = true
  default     = null
}

variable "key_vault_id" {
  description = "ID of existing Key Vault containing the admin password secret (leave null to create new)"
  type        = string
  default     = null
}

variable "key_vault_secret_name" {
  description = "Name of the secret in Key Vault containing the admin password"
  type        = string
  default     = "vm-admin-password"
}

variable "create_key_vault" {
  description = "Create a new Key Vault and generate random password"
  type        = bool
  default     = true
}

variable "allowed_rdp_ips" {
  description = "List of IP addresses allowed to RDP (use your public IP)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Restrict this to your IP in production
}

variable "use_spot_vm" {
  description = "Use Spot VM for cost savings (can be evicted)"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Daily auto-shutdown time in UTC (HHMM format)"
  type        = string
  default     = "1900" # 7 PM UTC
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Purpose     = "powerbi-development"
    ManagedBy   = "terraform"
  }
}
