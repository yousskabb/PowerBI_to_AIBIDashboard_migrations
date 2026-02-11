# Migrating Power BI Dashboards to Databricks AI/BI

This repository contains the code and configuration for migrating Power BI reports to Databricks AI/BI dashboards using Databricks Asset Bundles.

## Project Structure

```
├── powerBI_reports/           # Source Power BI project files (.pbip format)
├── dashboard/src/             # Generated Databricks dashboards (.lvdash.json)
├── src/views/                 # SQL view definitions for transformed tables
├── jobs/                      # Databricks job definitions (YAML)
├── warehouses/                # SQL Warehouse configuration (YAML)
├── databricks.yml             # Main Asset Bundle configuration
├── CLAUDE.md                  # Claude Code skills file (project conventions)
├── pbi-dashboard-migration.md # Step-by-step migration guide
└── reports/                   # Visual comparison and reference docs
```

## Dashboards

Three Power BI reports were migrated, each testing different aspects of the conversion:

| Dashboard | Focus Area |
|-----------|------------|
| **BakehouseSales** | DAX measures, Power Query transformations, calculated tables |
| **AdventureWorks Sales** | Cross-filtering, multi-dataset filters, choropleth maps |
| **Sample Superstore** | Skills file validation, single-dataset cross-filtering |

## Prerequisites

- [Databricks CLI](https://docs.databricks.com/dev-tools/cli/install.html) installed
- A Databricks workspace with Unity Catalog enabled
- Permissions to create catalogs, schemas, SQL warehouses, and dashboards

## Configuration

Before deploying, replace all placeholder values with your environment-specific settings. The table below lists every placeholder used across the project.

### Placeholder Reference

| Placeholder | Description | Where to update |
|-------------|-------------|-----------------|
| `<your-databricks-workspace-url>` | Your Databricks workspace URL (e.g. `adb-123456.14.azuredatabricks.net`) | `databricks.yml`, `excel_to_uc/databricks.yml` |
| `<your-catalog>` | Unity Catalog catalog name to use for views and tables | `src/views/*.sql`, `dashboard/src/*.lvdash.json`, `excel_to_uc/resources/excel_import_job.yml` |
| `<your-container>` | Azure storage container name for the catalog managed location | `src/views/create_schema.sql` |
| `<your-storage-account>` | Azure storage account name | `src/views/create_schema.sql` |
| `<your-path>` | Storage path within the container | `src/views/create_schema.sql` |

### Step-by-step Setup

#### 1. Set the Databricks workspace URL

Update the `host` field in both bundle configuration files:

- **`databricks.yml`** (line 5)
- **`excel_to_uc/databricks.yml`** (line 5)

```yaml
workspace:
  host: https://<your-databricks-workspace-url>
```

#### 2. Set the Unity Catalog name

Replace `<your-catalog>` in all SQL and dashboard files. The quickest way is a project-wide find-and-replace:

**SQL views** — these create the schema and views for BakehouseSales:
- `src/views/create_schema.sql`
- `src/views/vw_sales_transactions.sql`
- `src/views/vw_dim_date.sql`

**Dashboard datasets** — these query the tables/views:
- `dashboard/src/BakehouseSales.lvdash.json`
- `dashboard/src/AdventureWorks Sales.lvdash.json`
- `dashboard/src/sample_superstore.lvdash.json`

**Excel import job** (if using the Sample Superstore loader):
- `excel_to_uc/resources/excel_import_job.yml`

#### 3. Set the storage location (BakehouseSales only)

In `src/views/create_schema.sql`, replace the storage placeholders for the catalog managed location:

```sql
CREATE CATALOG IF NOT EXISTS <your-catalog>
MANAGED LOCATION 'abfss://<your-container>@<your-storage-account>.dfs.core.windows.net/<your-path>';
```

If your catalog already exists, you can remove the `CREATE CATALOG` statement and keep only the `CREATE SCHEMA`.

#### 4. Load source data

Each dashboard expects tables to exist in Unity Catalog:

| Dashboard | Expected tables | How to load |
|-----------|----------------|-------------|
| **BakehouseSales** | Source tables in any catalog/schema; SQL views are created by the `create_views` job | Load your source data, then update the `FROM` clauses in `src/views/*.sql` to point to your source tables |
| **AdventureWorks Sales** | `<your-catalog>.dashboard_adventureworks.sales_data`, `date_data`, `reseller_data`, `product_data` | Import the AdventureWorks tables into Unity Catalog |
| **Sample Superstore** | `<your-catalog>.dashboard_sample___superstore.orders` | Use the `excel_to_uc/` bundle to import the Excel file (see below) |

### Power BI Source Files (Optional)

The `powerBI_reports/` directory contains the original `.pbip` project files for reference. If you want to connect Power BI Desktop to your own Databricks workspace, update the placeholders in the `.tmdl` files:

| Placeholder | Description |
|-------------|-------------|
| `<your-workspace-url>` | Databricks workspace hostname |
| `<your-warehouse-id>` | SQL Warehouse ID (found in the warehouse settings page) |

## Getting Started

```bash
# 1. Authenticate to Databricks
databricks auth login --host https://<your-databricks-workspace-url>

# 2. Validate the bundle
databricks bundle validate --target dev

# 3. Deploy dashboards, warehouse, and jobs
databricks bundle deploy --target dev

# 4. Run the view creation job (needed for BakehouseSales)
databricks bundle run create_views --target dev
```

### Loading Sample Superstore data

```bash
cd excel_to_uc

# Authenticate (if different workspace)
databricks auth login --host https://<your-databricks-workspace-url>

databricks bundle deploy --target dev
databricks bundle run excel_import --target dev
```

## Related Projects

### `terraform/`

Terraform configuration to provision a low-cost Azure VM with Power BI Desktop installed. Used for development and testing when a local Power BI installation is not available. See [`terraform/README.md`](terraform/README.md) for setup instructions.

Requires its own configuration — copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill in your values.

### `excel_to_uc/`

A standalone Databricks Asset Bundle that imports Excel files into Unity Catalog as Delta tables. Used to load the Sample Superstore dataset. See [`excel_to_uc/SKILLS.md`](excel_to_uc/SKILLS.md) for usage details.
