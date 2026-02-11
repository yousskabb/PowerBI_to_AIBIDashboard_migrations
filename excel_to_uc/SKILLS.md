# Excel to Unity Catalog - Skills File

## Purpose

Import Excel files (`.xls`, `.xlsx`) into Databricks Unity Catalog as Delta tables. Each Excel file becomes a schema, and each sheet becomes a table. Column names and table names are preserved from the original Excel file.

## Naming Convention

- **Catalog:** `<your-catalog>`
- **Schema:** `dashboard_<sanitized_excel_filename>` (e.g., `Sample - Superstore.xls` → `dashboard_sample___superstore`)
- **Table:** `<sanitized_sheet_name>` (e.g., sheet `Orders` → `orders`)
- **Columns:** Preserved exactly as in the Excel sheet (spaces and special characters supported via Delta column mapping)

## Project Structure

```
excel_to_uc/
├── databricks.yml              # Databricks Asset Bundle configuration
├── datasets/                   # Excel files to import (copy here before deploying)
│   └── Sample - Superstore.xls
├── resources/
│   └── excel_import_job.yml    # Job definition (serverless compute)
└── src/
    └── excel_to_uc.py          # Databricks notebook
```

## How It Works

1. The notebook reads all `.xls`/`.xlsx` files from the synced `datasets/` folder
2. For each file, a schema is created: `<your-catalog>.dashboard_<filename>`
3. For each sheet, a Delta table is created with:
   - Column mapping enabled (`delta.columnMapping.mode = name`) to support spaces in column names
   - Mode `overwrite` — re-running replaces existing tables
4. Pandas reads the Excel data, then it's converted to a Spark DataFrame and written as a managed table

## Key Commands

```bash
# Navigate to the bundle directory
cd excel_to_uc

# Validate the bundle
databricks bundle validate --target dev --profile dev

# Deploy the notebook, datasets, and job definition
databricks bundle deploy --target dev --profile dev

# Run the import job
databricks bundle run excel_import --target dev --profile dev
```

## Adding New Excel Files

1. Place the `.xls` or `.xlsx` file in the `excel_to_uc/datasets/` folder
2. Deploy and run:
   ```bash
   cd excel_to_uc
   databricks bundle deploy --target dev --profile dev
   databricks bundle run excel_import --target dev --profile dev
   ```
3. Tables will appear under `<your-catalog>.dashboard_<filename>` in Unity Catalog

## Job Configuration

- **Compute:** Serverless (no cluster provisioning needed)
- **Dependencies:** `openpyxl` (for `.xlsx`) and `xlrd` (for `.xls`), installed via the environment spec
- **Parameters:**
  - `catalog` — Unity Catalog catalog name (default: `<your-catalog>`)
  - `datasets_path` — Workspace path to the synced datasets folder

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `DELTA_INVALID_CHARACTERS_IN_COLUMN_NAMES` | Column names have spaces/special chars | Already handled — column mapping is enabled in the write options |
| `CREATE CATALOG ... Metastore storage root URL does not exist` | Catalog doesn't exist and can't be auto-created | Create the catalog manually in Databricks first, or provide a managed location |
| `FileNotFoundError: datasets` | Datasets folder not synced | Ensure files are in `excel_to_uc/datasets/` (not a symlink — DABs doesn't follow symlinks) |
| `No module named 'xlrd'` / `No module named 'openpyxl'` | Missing Excel libraries | Already handled via the `%pip install` in the notebook and the environment spec |
| `notebook ... does not exist` | Notebook path includes `.py` extension | Notebook path in the job YAML must omit the `.py` extension |

## Important Notes

- **Symlinks are not followed** by Databricks Asset Bundles — always copy Excel files directly into `excel_to_uc/datasets/`
- **The catalog must already exist** — the notebook creates schemas but not the catalog itself
- **Re-running is safe** — tables are overwritten with `overwriteSchema: true`
- **Empty sheets are skipped** automatically
