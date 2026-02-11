# Power BI Desktop VM - Terraform

Low-cost Azure VM with Power BI Desktop for development/testing.

## Cost Estimate

| Usage | Monthly Cost |
|-------|--------------|
| VM running ~10 hours/month | ~$2-3 |
| Storage (always on) | ~$10 |
| **Total for occasional use** | **~$12-15/month** |

## Prerequisites

1. [Terraform](https://www.terraform.io/downloads) installed
2. [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed
3. Azure subscription

## Quick Start

```bash
# 1. Login to Azure
az login

# 2. Set your subscription (if you have multiple)
az account set --subscription "YOUR_SUBSCRIPTION_NAME"

# 3. Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 4. Initialize Terraform
terraform init

# 5. Review the plan
terraform plan

# 6. Deploy
terraform apply
```

## Connect to VM

After deployment, connect via RDP:

```bash
# Get connection info
terraform output rdp_connection

# On Mac, use Microsoft Remote Desktop app
# On Windows, run the output command directly
```

**Credentials:**
- Username: `powerbi-admin` (or your configured value)
- Password: The password you set in terraform.tfvars

## Start/Stop VM (Save Money!)

```bash
# Stop VM (stops billing for compute)
az vm deallocate --resource-group rg-powerbi-dev --name vm-powerbi

# Start VM when needed
az vm start --resource-group rg-powerbi-dev --name vm-powerbi

# Check VM status
az vm show --resource-group rg-powerbi-dev --name vm-powerbi --show-details --query powerState
```

## Destroy (Remove All Resources)

```bash
terraform destroy
```

## Important Notes

- **Spot VM**: By default uses Spot pricing (up to 90% cheaper). Can be evicted by Azure with 30s notice.
- **Auto-shutdown**: VM shuts down daily at 7 PM UTC. Change `auto_shutdown_time` to adjust.
- **Security**: Restrict `allowed_rdp_ips` to your IP address for security.
- **Power BI**: Installed automatically during provisioning (~10-15 min after VM starts).

## Troubleshooting

**Power BI not installed?**
- Wait 15 minutes after first boot
- Check C:\WindowsAzure\Logs for installation logs
- RDP in and run: `winget install Microsoft.PowerBI`

**VM evicted (Spot)?**
- Just restart: `az vm start --resource-group rg-powerbi-dev --name vm-powerbi`

**Can't connect via RDP?**
- Verify VM is running: `az vm show ... --query powerState`
- Check your IP is in `allowed_rdp_ips`
- Verify NSG rules in Azure Portal
