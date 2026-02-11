# Power BI to Databricks Dashboard Migration Guide

This comprehensive guide documents the complete process of converting Power BI reports (.pbip format) and semantic models to Databricks AI/BI dashboards using Databricks Asset Bundles.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Migration Process](#migration-process)
   - [Step 1: Analyze Semantic Model](#step-1-analyze-the-power-bi-semantic-model)
   - [Step 2: Identify Transformations](#step-2-identify-calculated-columns-and-transformations)
   - [Step 3: Create SQL Views](#step-3-create-sql-views)
   - [Step 4: Analyze Report Visuals](#step-4-analyze-report-visuals)
   - [Step 5: Extract Theme Colors](#step-5-extract-theme-colors)
   - [Step 6: Create Dashboard JSON](#step-6-create-dashboard-json)
   - [Step 7: Create SQL Warehouse](#step-7-create-sql-warehouse-definition)
   - [Step 8: Create Job Definition](#step-8-create-job-definition)
   - [Step 9: Configure databricks.yml](#step-9-configure-databricksyml)
   - [Step 10: Deploy](#step-10-deploy)
5. [Dashboard JSON Specification](#dashboard-json-specification)
6. [Widget Templates](#widget-templates)
7. [Reference Tables](#reference-tables)
8. [Troubleshooting](#troubleshooting)
9. [Complete Example: BakehouseSales](#complete-example-bakehousesales-migration)

---

## Overview

The migration process converts:
- **Power BI Semantic Model** → SQL Views + Direct table references
- **Power BI Report Visuals** → Databricks Dashboard JSON (`.lvdash.json`)
- **Power BI Measures** → SQL aggregations in dashboard queries
- **Deployment** → Databricks Asset Bundle with jobs for view creation

## Prerequisites

- Databricks CLI installed and configured
- Access to the Databricks workspace
- Access to source data tables in Databricks
- Power BI report in `.pbip` format (Power BI Project)

## Placeholders Reference

Throughout this guide, replace these placeholders with your actual values:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<ReportName>` | Name of your Power BI report | `BakehouseSales` |
| `<dashboardname>` | Lowercase dashboard name (no spaces) | `bakehousesales` |
| `<source_catalog>` | Catalog containing source tables | `samples` |
| `<source_schema>` | Schema containing source tables | `bakehouse` |
| `<source_table>` | Source table name | `sales_transactions` |
| `<storage-location>` | Azure/AWS/GCP storage path for catalog | `abfss://container@storage.dfs.core.windows.net/path` |
| `<workspace-url>` | Databricks workspace URL | `https://adb-123456.14.azuredatabricks.net/` |

## Project Structure

```
├── databricks.yml                      # Main bundle configuration
├── jobs/
│   └── create_views.yml                # Job definition for creating views
├── warehouses/
│   └── dashboard_warehouse.yml         # SQL Warehouse definition
├── dashboard/
│   └── src/
│       └── <ReportName>.lvdash.json    # Databricks dashboard JSON
├── src/
│   └── views/
│       ├── create_schema.sql           # Catalog and schema creation (run first)
│       ├── vw_<table1>.sql             # View for tables with calculated columns
│       └── vw_<table2>.sql             # View for calculated tables
├── powerBI_reports/                    # Original Power BI reports (reference)
│   └── <ReportName>.Report/
│       └── definition/
│           └── pages/
│               └── <pageId>/
│                   └── visuals/
└── pbi-dashboard-migration.md          # This guide
```

---

## Migration Process

### Step 1: Analyze the Power BI Semantic Model

Navigate to the `powerBI_reports/<ReportName>.SemanticModel/definition/tables/` folder and analyze each `.tmdl` file.

**For each table, determine the action:**

| Scenario | Action |
|----------|--------|
| Table maps directly to source (no transformations) | Reference source table directly in queries |
| Table has calculated columns or measures | Create a SQL view with the transformations |
| Table is fully calculated (e.g., date dimension) | Create a SQL view to generate the data |
| Table is a measures table (`_Measures`) | Implement as SQL aggregations in dashboard queries |

**Create a table analysis like this:**

| Table | Source | Has Transformations | Action |
|-------|--------|---------------------|--------|
| `<table_name>` | `<source_catalog>.<source_schema>.<source_table>` | Yes/No | **Create view** / **Direct reference** |

### Step 2: Identify Calculated Columns and Transformations

Look for these patterns in `.tmdl` files:

**Calculated columns (Power Query M):**
```
partition <table_name> = m
    mode: import
    source =
        let
            ...
            AddedColumn = Table.AddColumn(...),
            ...
        in
            Result
```

**Column transformations (Power Query M):**
```
Table.TransformColumns(
    Source,
    {
        {"ColumnName", Text.Trim, type text},
        {"OtherColumn", Text.Upper, type text}
    }
)
```

**Important:** When you find `Table.TransformColumns`, ensure all transformations are captured in the SQL view. Common transformations include:
- `Text.Trim` → `TRIM(column)`
- `Text.Upper` → `UPPER(column)`
- `Text.Lower` → `LOWER(column)`
- `Text.Clean` → `REGEXP_REPLACE(column, '[\\x00-\\x1F]', '')`

**Calculated tables (DAX):**
```
partition <table_name> = calculated
    mode: import
    source = ```
        DAX_EXPRESSION
        ```
```

### Step 3: Create SQL Views

For each table requiring transformation, create a SQL view in `src/views/`.

**Naming Conventions:**
- **File:** `vw_<original_table_name>.sql`
- **Catalog:** `<your-catalog>` (dedicated catalog for all dashboard views)
- **Schema:** `dashboard_<dashboardname>_views`
- **View:** `vw_<original_table_name>`

**Create Catalog and Schema First:**

Add a `create_schema.sql` file in `src/views/`. When creating a catalog, you must provide a `MANAGED LOCATION` for storage.

**Template - create_schema.sql:**
```sql
-- Catalog and schema for <ReportName> dashboard views

CREATE CATALOG IF NOT EXISTS <your-catalog>
MANAGED LOCATION '<storage-location>';

CREATE SCHEMA IF NOT EXISTS <your-catalog>.dashboard_<dashboardname>_views
```

**Important - Column Naming:**

The view output column names must match the Power BI semantic model column names exactly. Check the `.tmdl` file for the exact column names used in Power BI.

- **Source columns:** Use the actual database column names (e.g., `transactionID`, `customerID`)
- **Output columns:** Use the Power BI semantic model column names as aliases (e.g., `Transactionid`, `Customerid`)

Power BI often transforms column names via M query functions like `Text.Proper()`. For example:
- Source: `transactionID` → Power BI: `Transactionid`
- Source: `unitPrice` → Power BI: `Unitprice`

**Template - View with transformations:**
```sql
-- View: vw_<table_name>
-- Source: <source_catalog>.<source_schema>.<source_table>

CREATE OR REPLACE VIEW <your-catalog>.dashboard_<dashboardname>_views.vw_<table_name> AS
SELECT
    <source_column> AS <PBIColumnName>,           -- Column renaming
    TRIM(<text_column>) AS <PBIColumnName>,       -- Text.Trim transformation
    DATE(<datetime_column>) AS <DateColumn>,      -- Calculated column
    YEAR(<datetime_column>) AS Year,
    MONTH(<datetime_column>) AS Month,
    CONCAT('Q', QUARTER(<datetime_column>)) AS Quarter
FROM <source_catalog>.<source_schema>.<source_table>
```

**Template - Calculated date dimension:**
```sql
-- View: vw_dim_date
-- Source: Calculated from <source_table>

CREATE OR REPLACE VIEW <your-catalog>.dashboard_<dashboardname>_views.vw_dim_date AS
WITH date_range AS (
    SELECT MIN(DATE(<datetime_column>)) AS min_date, MAX(DATE(<datetime_column>)) AS max_date
    FROM <source_catalog>.<source_schema>.<source_table>
),
date_sequence AS (
    SELECT explode(sequence(min_date, max_date, interval 1 day)) AS Date
    FROM date_range
)
SELECT
    Date,
    YEAR(Date) AS Year,
    MONTH(Date) AS MonthNumber,
    DATE_FORMAT(Date, 'MMM') AS Month,
    CONCAT('Q', QUARTER(Date)) AS Quarter,
    DATE_FORMAT(Date, 'yyyy-MM') AS YearMonth,
    DAYOFWEEK(Date) AS DayOfWeek,
    DATE_FORMAT(Date, 'EEE') AS DayName
FROM date_sequence
```

### Step 4: Analyze Report Visuals

Navigate to `powerBI_reports/<ReportName>.Report/definition/pages/<pageId>/visuals/` and analyze each `visual.json`.

**Extract for each visual:**

1. **Visual Type** (`visualType`):
   - `card` → Databricks `counter`
   - `tableEx` → Databricks `table`
   - `lineChart` → Databricks `line`
   - `barChart` → Databricks `bar`
   - `pieChart` → Databricks `pie`

2. **Data Fields** (from `query.queryState`):
   - Dimensions (Category/Axis)
   - Measures (Values)

3. **Position** (from `position`):
   - Map to Databricks 6-column grid

4. **Colors** (from `objects.dataPoint.properties.fill`):
   - Extract ThemeDataColor ColorId values
   - Map to theme dataColors array

### Step 5: Extract Theme Colors

From `powerBI_reports/<ReportName>.Report/StaticResources/RegisteredResources/<theme>.json`:

```json
{
  "dataColors": ["#1F4B99", "#2EA8E0", "#FF9F1C", "#2ECC71", "#E74C3C", ...],
  "background": "#F7F8FA",
  "foreground": "#2D2D2D"
}
```

**Power BI ColorId Mapping:**
- ColorId 0 → dataColors[0]
- ColorId 1 → dataColors[1]
- etc.

**Applying Colors to Databricks Widgets:**

Databricks AI/BI dashboards use theme-based colors via the `mark.colors` property. The `position` value (1-10) selects from the dashboard's visualization color palette.

**Chart Colors (Line, Bar, Area, Pie):**

Use the `mark.colors` array inside the `spec` to set chart colors. The first element sets the primary color for single-series charts. You can use either:
- **Hex color string**: `"#2EA8E0"` - direct color value from Power BI theme
- **Theme color object**: `{ "themeColorType": "visualizationColors", "position": 1 }` - reference to dashboard palette

```json
"spec": {
  "version": 3,
  "widgetType": "line",
  "encodings": {
    "x": { "fieldName": "Date", "displayName": "Date", "scale": { "type": "temporal" } },
    "y": { "fieldName": "Value", "displayName": "Value", "scale": { "type": "quantitative" } }
  },
  "frame": { "showTitle": true, "title": "Chart Title" },
  "mark": {
    "colors": [
      "#2EA8E0",
      { "themeColorType": "visualizationColors", "position": 2 },
      { "themeColorType": "visualizationColors", "position": 3 },
      { "themeColorType": "visualizationColors", "position": 4 },
      { "themeColorType": "visualizationColors", "position": 5 },
      { "themeColorType": "visualizationColors", "position": 6 },
      { "themeColorType": "visualizationColors", "position": 7 },
      { "themeColorType": "visualizationColors", "position": 8 },
      { "themeColorType": "visualizationColors", "position": 9 },
      { "themeColorType": "visualizationColors", "position": 10 }
    ]
  }
}
```

### Step 6: Create Dashboard JSON

Create `dashboard/src/<ReportName>.lvdash.json`.

**Important:** Use the **view name** in queries for tables with transformations:
- `FROM <source_catalog>.<source_schema>.<source_table>`
- `FROM <your-catalog>.dashboard_<dashboardname>_views.vw_<table_name>`

See [Dashboard JSON Specification](#dashboard-json-specification) and [Widget Templates](#widget-templates) sections below for complete details.

### Step 7: Create SQL Warehouse Definition

Create `warehouses/dashboard_warehouse.yml`:

```yaml
resources:
  sql_warehouses:
    dashboard_warehouse:
      name: "Dashboard SQL Warehouse"
      cluster_size: "2X-Small"
      max_num_clusters: 1
      auto_stop_mins: 10
      enable_serverless_compute: true
```

### Step 8: Create Job Definition

Create `jobs/create_views.yml`. Add a task for each view file, with dependencies to ensure schema is created first.

**Template - create_views.yml:**
```yaml
resources:
  jobs:
    create_views:
      name: "Create Dashboard Views"
      tasks:
        - task_key: create_schema
          sql_task:
            warehouse_id: ${resources.sql_warehouses.dashboard_warehouse.id}
            file:
              path: ${workspace.root_path}/files/src/views/create_schema.sql

        - task_key: create_vw_<table1>
          sql_task:
            warehouse_id: ${resources.sql_warehouses.dashboard_warehouse.id}
            file:
              path: ${workspace.root_path}/files/src/views/vw_<table1>.sql
          depends_on:
            - task_key: create_schema

        - task_key: create_vw_<table2>
          sql_task:
            warehouse_id: ${resources.sql_warehouses.dashboard_warehouse.id}
            file:
              path: ${workspace.root_path}/files/src/views/vw_<table2>.sql
          depends_on:
            - task_key: create_vw_<table1>
```

### Step 9: Configure databricks.yml

**Template - databricks.yml:**
```yaml
bundle:
  name: dashboard_deployment

workspace:
  host: <workspace-url>

include:
  - jobs/*.yml
  - warehouses/*.yml

sync:
  include:
    - src/views/*.sql

resources:
  dashboards:
    <dashboardname>_dashboard:
      display_name: "<ReportName>"
      file_path: ./dashboard/src/<ReportName>.lvdash.json
      warehouse_id: ${resources.sql_warehouses.dashboard_warehouse.id}

targets:
  dev:
    mode: development
    default: true
    workspace:
      root_path: /Workspace/Users/${workspace.current_user.userName}/.bundle/${bundle.name}/dev

  prod:
    mode: production
    workspace:
      root_path: /Workspace/Users/${workspace.current_user.userName}/.bundle/${bundle.name}/prod
```

### Step 10: Deploy

```bash
# Authenticate
databricks auth login --host <workspace-url>

# Validate
databricks bundle validate

# Deploy warehouse, dashboard, and job
databricks bundle deploy --target dev

# Create views (run the job)
databricks bundle run create_views --target dev
```

**What gets deployed:**
1. SQL Warehouse (serverless, auto-stops after 10 min)
2. Dashboard (references the created warehouse)
3. Job for creating views (uses the same warehouse)

---

## Dashboard JSON Specification

### Core JSON Structure

Every dashboard follows this structure:

```json
{
  "datasets": [],
  "pages": []
}
```

### Dataset Generation Rules

When creating datasets:

1. **Generate unique IDs**: Use 8-character lowercase hex strings for `name` (e.g., `"a1b2c3d4"`)
2. **Use descriptive displayNames**: Make them human-readable and meaningful
3. **Write optimized SQL**: Include proper aggregations and date handling
4. **Do NOT use parameters for filtering**: Datasets should return all data; filter widgets handle filtering client-side via field-based filtering
5. **Include filter fields in SELECT**: Any field used by a filter widget must be in the dataset's SELECT clause
6. **Ensure proper SQL spacing in queryLines**: Each line should end with a trailing space

### Datasets and Filtering Strategy

The goal is to replicate Power BI report behavior — filters and interactions between visuals must work the same way.

#### Categorical Dimension Filtering Rule

**Every categorical dimension column that is visible or clickable on the report must have a corresponding filter widget that filters all visualizations.** In Power BI, clicking on any category (bar segment, pie slice, table row, map region) automatically cross-filters all other visuals. Databricks does not do this across datasets, so you must:

1. **Identify all categorical columns** visible on any widget (e.g., used as x-axis, color encoding, table column, map region — Category, Country, Region, Segment, Business_Type, etc.)
2. **Create a `filter-single-select` widget** for each categorical column, referencing **all datasets** that contain that column
3. **Ensure the column exists** in the SELECT and GROUP BY of every dataset the filter references
4. **Add JOINs to datasets as needed** so the filter column is available in all of them (e.g., if one dataset uses UNION ALL without a JOIN, add the JOIN so the dimension column is available)

This ensures the user can filter the entire report by any dimension, replicating the Power BI slicer/cross-filter experience.

#### Single Dataset (Preferred)
Use **one dataset per page** when all charts can share the same SQL query. This enables both field-based filtering and cross-filtering (clicking on a chart filters others). Do NOT use parameters or WHERE clauses for filtering — the dataset returns all data and the filter widget handles filtering client-side.

```sql
SELECT
  DATE_FORMAT(TO_DATE(d.Month, 'yyyy MMM'), 'yyyy-MM') AS Month,
  d.MonthKey, d.Fiscal_Year,
  r.`Country-Region` AS Country_Region,
  p.Category, r.Business_Type,
  SUM(s.Sales_Amount) AS Sales_Amount,
  SUM(s.Order_Quantity) AS Order_Quantity
FROM sales_data s
JOIN date_data d ON s.OrderDateKey = d.DateKey
JOIN reseller_data r ON s.ResellerKey = r.ResellerKey
JOIN product_data p ON s.ProductKey = p.ProductKey
GROUP BY DATE_FORMAT(TO_DATE(d.Month, 'yyyy MMM'), 'yyyy-MM'),
  d.MonthKey, d.Fiscal_Year, r.`Country-Region`, p.Category, r.Business_Type
ORDER BY MonthKey
```

#### Multiple Datasets (When Required)
Use separate datasets when one chart needs UNION ALL (e.g., multiple measures with different joins) but other charts need a simple query. This avoids double-counting.

**Important:** A filter widget only filters datasets it explicitly references. To filter multiple datasets from one filter widget, add a field query entry per dataset (see Filter Widget section below). The filter field must be included in every dataset's SELECT clause.

**When to use separate datasets:**
- UNION ALL needed for one chart (e.g., Order Date + Due Date measures) while others need simple aggregation
- Different charts need fundamentally different JOINs

**When NOT to use separate datasets:**
- Avoid splitting just for convenience — it breaks cross-filtering between charts
- Never use a standalone "lookup" dataset for filters (e.g., `SELECT DISTINCT Year`) — the filter won't affect any charts

#### Double-Counting with UNION ALL
When using UNION ALL to show multiple measures (e.g., two date joins), other widgets on the same dataset will see doubled rows. **`CASE WHEN` does NOT work in widget field expressions** to filter rows. The only solution is to put those widgets on a separate dataset with a simple query.

**Example of proper queryLines spacing:**
```json
"queryLines": [
  "SELECT column1, column2 ",
  " FROM schema.table ",
  " WHERE condition = true ",
  " GROUP BY column1 ",
  " ORDER BY column2"
]
```

### Dataset Template

```json
{
  "name": "<8-char-hex-id>",
  "displayName": "<descriptive-name>",
  "queryLines": [
    "SELECT ",
    "  <filter_field>, ",
    "  <dimension_fields>, ",
    "  SUM(<measure>) AS <measure_alias> ",
    "FROM <catalog>.<schema>.<table> ",
    "GROUP BY <filter_field>, <dimension_fields>"
  ]
}
```

**Important - No parameters for filtering:**
- Do NOT use `parameters` arrays or `:param_name` in SQL WHERE clauses for filtering
- Datasets should return all data; filter widgets handle filtering client-side
- Include any field used by a filter widget in the dataset's SELECT and GROUP BY clauses

### Page and Layout Rules

1. **Canvas grid**: 6 columns wide, unlimited height
2. **Position properties**: `x` (0-5), `y` (row), `width` (1-6), `height` (variable)
3. **No overlapping**: Ensure widgets don't overlap
4. **Logical flow**: Place important KPIs at top, details below

### Page Template

```json
{
  "name": "<8-char-hex-id>",
  "displayName": "<page-title>",
  "layout": []
}
```

### Field Expressions

Use backticks for field references in expressions:

| Expression Type | Syntax |
|----------------|--------|
| Direct field | `` `column_name` `` |
| Sum | `SUM(\`column\`)` |
| Average | `AVG(\`column\`)` |
| Count | `COUNT(\`column\`)` |
| Count distinct | `COUNT(DISTINCT \`column\`)` |
| Min/Max | `MIN(\`column\`)`, `MAX(\`column\`)` |
| Date truncation | `DATE_TRUNC("MONTH", \`date_col\`)` |
| Date formatting | `DATE_FORMAT(\`date_col\`, "yyyy-MM")` |

**Limitations — expressions that do NOT work in widget fields:**
- `CASE WHEN` — widgets will show empty/no results
- Complex SQL functions or subqueries
- Conditional aggregation (`SUM(CASE WHEN ... THEN ... END)`)

For conditional logic, handle it in the dataset SQL query instead.

### Common Date Expressions

```json
{ "name": "daily(date_col)", "expression": "DATE_TRUNC(\"DAY\", `date_col`)" }
{ "name": "weekly(date_col)", "expression": "DATE_TRUNC(\"WEEK\", `date_col`)" }
{ "name": "monthly(date_col)", "expression": "DATE_TRUNC(\"MONTH\", `date_col`)" }
{ "name": "quarterly(date_col)", "expression": "DATE_TRUNC(\"QUARTER\", `date_col`)" }
{ "name": "yearly(date_col)", "expression": "DATE_TRUNC(\"YEAR\", `date_col`)" }
```

### Scale Types Reference

| Scale Type | Use For | Example Fields |
|------------|---------|----------------|
| `quantitative` | Continuous numbers | Revenue, count, percentage |
| `temporal` | Dates and times | Order date, timestamp |
| `categorical` | Discrete categories | Product type, region, status |

### Color Customization

```json
{
  "color": {
    "fieldName": "<field>",
    "scale": {
      "type": "categorical",
      "mappings": [
        { "value": "Success", "color": "#2ECC71" },
        { "value": "Warning", "color": "#F39C12" },
        { "value": "Error", "color": "#E74C3C" }
      ]
    }
  }
}
```

### Layout Best Practices

```
Row 0-1:  [  Title/Header (width: 6)  ]
Row 2:    [Filter][Filter][Filter][ KPI ][ KPI ][ KPI ]
Row 3-8:  [ Bar Chart (w:3)  ][ Line Chart (w:3) ]
Row 9-14: [ Table (w:6)                          ]
```

### Position Calculations

- **Full width**: `width: 6`
- **Half width**: `width: 3`
- **Third width**: `width: 2`
- **Quarter width**: `width: 1` (filters typically)

---

## Widget Templates

### Counter (KPI Card)

Power BI `card` → Databricks `counter`

```json
{
  "widget": {
    "name": "<8-char-id>",
    "queries": [
      {
        "name": "main_query",
        "query": {
          "datasetName": "<dataset-name>",
          "fields": [
            { "name": "<FieldName>", "expression": "`<FieldName>`" }
          ],
          "disaggregated": false
        }
      }
    ],
    "spec": {
      "version": 2,
      "widgetType": "counter",
      "encodings": {
        "value": { "fieldName": "<FieldName>", "displayName": "<Display Name>" }
      },
      "frame": { "showTitle": true, "title": "<Widget Title>" }
    }
  },
  "position": { "x": 0, "y": 0, "width": 2, "height": 2 }
}
```

### Line Chart

Power BI `lineChart` → Databricks `line`

```json
{
  "widget": {
    "name": "<8-char-id>",
    "queries": [
      {
        "name": "main_query",
        "query": {
          "datasetName": "<dataset-name>",
          "fields": [
            { "name": "<XField>", "expression": "`<XField>`" },
            { "name": "<YField>", "expression": "`<YField>`" }
          ],
          "disaggregated": true
        }
      }
    ],
    "spec": {
      "version": 3,
      "widgetType": "line",
      "encodings": {
        "x": {
          "fieldName": "<XField>",
          "displayName": "<X Label>",
          "scale": { "type": "temporal" }
        },
        "y": {
          "fieldName": "<YField>",
          "displayName": "<Y Label>",
          "scale": { "type": "quantitative" }
        }
      },
      "frame": { "showTitle": true, "title": "<Chart Title>" },
      "mark": {
        "colors": [
          "#2EA8E0",
          { "themeColorType": "visualizationColors", "position": 2 },
          { "themeColorType": "visualizationColors", "position": 3 },
          { "themeColorType": "visualizationColors", "position": 4 },
          { "themeColorType": "visualizationColors", "position": 5 },
          { "themeColorType": "visualizationColors", "position": 6 },
          { "themeColorType": "visualizationColors", "position": 7 },
          { "themeColorType": "visualizationColors", "position": 8 },
          { "themeColorType": "visualizationColors", "position": 9 },
          { "themeColorType": "visualizationColors", "position": 10 }
        ]
      }
    }
  },
  "position": { "x": 0, "y": 0, "width": 3, "height": 6 }
}
```

### Bar Chart

Power BI `barChart` / `clusteredBarChart` → Databricks `bar`

```json
{
  "widget": {
    "name": "<8-char-hex-id>",
    "queries": [{
      "name": "main_query",
      "query": {
        "datasetName": "<dataset-id>",
        "fields": [
          { "name": "<field-alias>", "expression": "<sql-expression>" }
        ],
        "disaggregated": false
      }
    }],
    "spec": {
      "version": 3,
      "widgetType": "bar",
      "encodings": {
        "x": {
          "fieldName": "<field-alias>",
          "scale": { "type": "temporal|quantitative|categorical" },
          "displayName": "<axis-label>"
        },
        "y": {
          "fieldName": "<field-alias>",
          "scale": { "type": "quantitative" },
          "displayName": "<axis-label>"
        },
        "color": {
          "fieldName": "<field-alias>",
          "scale": { "type": "categorical" },
          "legend": { "position": "bottom" },
          "displayName": "<legend-label>"
        },
        "label": { "show": true }
      },
      "frame": { "showTitle": true, "title": "<chart-title>" }
    }
  },
  "position": { "x": 0, "y": 0, "width": 3, "height": 6 }
}
```

### Pie Chart

Power BI `pieChart` / `donutChart` → Databricks `pie`

```json
{
  "widget": {
    "name": "<8-char-hex-id>",
    "queries": [{
      "name": "main_query",
      "query": {
        "datasetName": "<dataset-id>",
        "fields": [
          { "name": "<measure>", "expression": "SUM(`<column>`)" },
          { "name": "<category>", "expression": "`<column>`" }
        ],
        "disaggregated": false
      }
    }],
    "spec": {
      "version": 3,
      "widgetType": "pie",
      "encodings": {
        "angle": { "fieldName": "<measure>", "scale": { "type": "quantitative" }, "displayName": "<label>" },
        "color": { "fieldName": "<category>", "scale": { "type": "categorical" }, "displayName": "<label>" }
      },
      "frame": { "showTitle": true, "title": "<title>" }
    }
  },
  "position": { "x": 0, "y": 0, "width": 3, "height": 6 }
}
```

### Area Chart

Power BI `areaChart` → Databricks `area`

```json
{
  "widget": {
    "name": "<8-char-hex-id>",
    "queries": [{
      "name": "main_query",
      "query": {
        "datasetName": "<dataset-id>",
        "fields": [
          { "name": "<time-field>", "expression": "`<column>`" },
          { "name": "<measure>", "expression": "SUM(`<column>`)" }
        ],
        "disaggregated": true
      }
    }],
    "spec": {
      "version": 3,
      "widgetType": "area",
      "encodings": {
        "x": { "fieldName": "<time-field>", "scale": { "type": "temporal" }, "displayName": "<label>" },
        "y": { "fieldName": "<measure>", "scale": { "type": "quantitative" }, "displayName": "<label>" },
        "color": { "fieldName": "<category>", "scale": { "type": "categorical" }, "displayName": "<label>" }
      },
      "frame": { "showTitle": true, "title": "<title>" }
    }
  },
  "position": { "x": 0, "y": 0, "width": 3, "height": 6 }
}
```

### Scatter Plot

```json
{
  "widget": {
    "name": "<8-char-hex-id>",
    "queries": [{
      "name": "main_query",
      "query": {
        "datasetName": "<dataset-id>",
        "fields": [
          { "name": "<x-measure>", "expression": "`<column>`" },
          { "name": "<y-measure>", "expression": "`<column>`" }
        ],
        "disaggregated": true
      }
    }],
    "spec": {
      "version": 3,
      "widgetType": "scatter",
      "encodings": {
        "x": { "fieldName": "<x-measure>", "scale": { "type": "quantitative" }, "displayName": "<label>" },
        "y": { "fieldName": "<y-measure>", "scale": { "type": "quantitative" }, "displayName": "<label>" },
        "color": { "fieldName": "<category>", "scale": { "type": "categorical" }, "displayName": "<label>" },
        "size": { "fieldName": "<size-measure>", "scale": { "type": "quantitative" }, "displayName": "<label>" }
      },
      "frame": { "showTitle": true, "title": "<title>" }
    }
  },
  "position": { "x": 0, "y": 0, "width": 3, "height": 6 }
}
```

### Table Widget

Power BI `tableEx` → Databricks `table`

**Key Requirements:**
- `disaggregated: true` in the query (tables show individual rows, not aggregations)
- `spec.version: 1` (tables use version 1, not 2 or 3)
- Each column must include all formatting properties
- Add `invisibleColumns: []`, `allowHTMLByDefault`, and `paginationSize` to the spec

**Column Type Reference:**

| Data Type | `type` | `displayAs` | Format Property | `alignContent` |
|-----------|--------|-------------|-----------------|----------------|
| Text/String | `string` | `string` | - | `left` |
| Integer | `integer` | `number` | `numberFormat: "0"` | `right` |
| Decimal/Currency | `decimal` | `number` | `numberFormat: "#,##0.00"` | `right` |
| Date | `date` | `datetime` | `dateTimeFormat: "DD/MM/YYYY"` | `right` |
| DateTime | `datetime` | `datetime` | `dateTimeFormat: "DD/MM/YYYY HH:mm:ss"` | `right` |

**Complete Table Widget Template:**
```json
{
  "widget": {
    "name": "<8-char-id>",
    "queries": [
      {
        "name": "main_query",
        "query": {
          "datasetName": "<dataset-name>",
          "fields": [
            { "name": "<NumberField>", "expression": "`<NumberField>`" },
            { "name": "<DateField>", "expression": "`<DateField>`" },
            { "name": "<TextField>", "expression": "`<TextField>`" }
          ],
          "disaggregated": true
        }
      }
    ],
    "spec": {
      "version": 1,
      "widgetType": "table",
      "encodings": {
        "columns": [
          {
            "fieldName": "<NumberField>",
            "numberFormat": "0",
            "booleanValues": ["false", "true"],
            "imageUrlTemplate": "{{ @ }}",
            "imageTitleTemplate": "{{ @ }}",
            "imageWidth": "",
            "imageHeight": "",
            "linkUrlTemplate": "{{ @ }}",
            "linkTextTemplate": "{{ @ }}",
            "linkTitleTemplate": "{{ @ }}",
            "linkOpenInNewTab": true,
            "type": "integer",
            "displayAs": "number",
            "visible": true,
            "order": 0,
            "title": "<Number Column Title>",
            "allowSearch": false,
            "alignContent": "right",
            "allowHTML": false,
            "highlightLinks": false,
            "useMonospaceFont": false,
            "preserveWhitespace": false
          },
          {
            "fieldName": "<DateField>",
            "dateTimeFormat": "DD/MM/YYYY",
            "booleanValues": ["false", "true"],
            "imageUrlTemplate": "{{ @ }}",
            "imageTitleTemplate": "{{ @ }}",
            "imageWidth": "",
            "imageHeight": "",
            "linkUrlTemplate": "{{ @ }}",
            "linkTextTemplate": "{{ @ }}",
            "linkTitleTemplate": "{{ @ }}",
            "linkOpenInNewTab": true,
            "type": "date",
            "displayAs": "datetime",
            "visible": true,
            "order": 1,
            "title": "<Date Column Title>",
            "allowSearch": false,
            "alignContent": "right",
            "allowHTML": false,
            "highlightLinks": false,
            "useMonospaceFont": false,
            "preserveWhitespace": false
          },
          {
            "fieldName": "<TextField>",
            "booleanValues": ["false", "true"],
            "imageUrlTemplate": "{{ @ }}",
            "imageTitleTemplate": "{{ @ }}",
            "imageWidth": "",
            "imageHeight": "",
            "linkUrlTemplate": "{{ @ }}",
            "linkTextTemplate": "{{ @ }}",
            "linkTitleTemplate": "{{ @ }}",
            "linkOpenInNewTab": true,
            "type": "string",
            "displayAs": "string",
            "visible": true,
            "order": 2,
            "title": "<Text Column Title>",
            "allowSearch": false,
            "alignContent": "left",
            "allowHTML": false,
            "highlightLinks": false,
            "useMonospaceFont": false,
            "preserveWhitespace": false
          }
        ]
      },
      "invisibleColumns": [],
      "allowHTMLByDefault": false,
      "itemsPerPage": 25,
      "paginationSize": "default",
      "condensed": true,
      "withRowNumber": false
    }
  },
  "position": { "x": 0, "y": 0, "width": 3, "height": 6 }
}
```

### Filter - Single Select (Preferred: Field-Based)

Use **field-based filtering** (not parameter-based). Field-based filters show a proper dropdown list of values from the dataset. Parameter-based filters only show a text input.

**How it works:**
- The filter widget queries a field from the dataset using `fields` (with `expression`)
- The dropdown is populated with distinct values of that field
- Selecting a value filters all widgets on the same dataset
- No parameters, no `WHERE` clause needed — the dataset returns all data

**Critical rules:**
- Use `fields` with `expression` in the query (NOT `parameters` with `name`/`keyword`)
- Use `fieldName`, `displayName`, `queryName` in `encodings.fields` (NOT `parameterName`)
- The filter field must exist in every dataset the filter references
- Do NOT use standalone "lookup" datasets — integrate the field into main dataset(s)

**Single dataset example:**
```json
{
  "widget": {
    "name": "<8-char-hex-id>",
    "queries": [
      {
        "name": "main_query",
        "query": {
          "datasetName": "<dataset_name>",
          "fields": [
            { "name": "<FieldName>", "expression": "`<FieldName>`" }
          ],
          "disaggregated": false
        }
      }
    ],
    "spec": {
      "version": 2,
      "widgetType": "filter-single-select",
      "encodings": {
        "fields": [
          {
            "fieldName": "<FieldName>",
            "displayName": "<Display Label>",
            "queryName": "main_query"
          }
        ]
      },
      "frame": { "showTitle": true, "title": "<Filter Title>" }
    }
  },
  "position": { "x": 0, "y": 0, "width": 1, "height": 2 }
}
```

**Multiple datasets example (filter controls two datasets):**

The filter field must be included in the SELECT of every dataset the filter references.

```json
{
  "widget": {
    "name": "<8-char-hex-id>",
    "queries": [
      {
        "name": "field_datasetA",
        "query": {
          "datasetName": "datasetA",
          "fields": [
            { "name": "Fiscal_Year", "expression": "`Fiscal_Year`" }
          ],
          "disaggregated": false
        }
      },
      {
        "name": "field_datasetB",
        "query": {
          "datasetName": "datasetB",
          "fields": [
            { "name": "Fiscal_Year", "expression": "`Fiscal_Year`" }
          ],
          "disaggregated": false
        }
      }
    ],
    "spec": {
      "version": 2,
      "widgetType": "filter-single-select",
      "encodings": {
        "fields": [
          {
            "fieldName": "Fiscal_Year",
            "displayName": "Fiscal Year",
            "queryName": "field_datasetA"
          },
          {
            "fieldName": "Fiscal_Year",
            "displayName": "Fiscal Year",
            "queryName": "field_datasetB"
          }
        ]
      },
      "frame": { "showTitle": true, "title": "Fiscal Year" }
    }
  },
  "position": { "x": 0, "y": 0, "width": 1, "height": 2 }
}
```

### Filter - Multi Select

Same field-based structure as single select, but with `widgetType: "filter-multi-select"`. Add one query entry per dataset that needs filtering.

```json
{
  "widget": {
    "name": "<8-char-hex-id>",
    "queries": [
      {
        "name": "main_query",
        "query": {
          "datasetName": "<dataset_name>",
          "fields": [
            { "name": "<FieldName>", "expression": "`<FieldName>`" }
          ],
          "disaggregated": false
        }
      }
    ],
    "spec": {
      "version": 2,
      "widgetType": "filter-multi-select",
      "encodings": {
        "fields": [
          {
            "fieldName": "<FieldName>",
            "displayName": "<Display Label>",
            "queryName": "main_query"
          }
        ]
      },
      "frame": { "showTitle": true, "title": "<Filter Title>" }
    }
  },
  "position": { "x": 0, "y": 0, "width": 1, "height": 2 }
}
```

### Text Widget (Markdown)

```json
{
  "widget": {
    "name": "<8-char-hex-id>",
    "textbox_spec": "# Title\n\nMarkdown content with **bold** and *italic*.\n\n- Bullet points\n- Supported"
  },
  "position": { "x": 0, "y": 0, "width": 6, "height": 2 }
}
```

---

## Reference Tables

### Visual Type Mapping

| Power BI Visual | Databricks Widget | Spec Version | disaggregated |
|-----------------|-------------------|--------------|---------------|
| `card` | `counter` | 2 | false |
| `tableEx` | `table` | 1 | true |
| `lineChart` | `line` | 3 | true |
| `barChart` | `bar` | 3 | false |
| `clusteredBarChart` | `bar` | 3 | false |
| `pieChart` | `pie` | 3 | false |
| `donutChart` | `pie` | 3 | false |
| `areaChart` (stacked) | `area` | 3 | true |
| `areaChart` (non-stacked) | `line` | 3 | true |

### Measure Conversion

| Power BI DAX | Databricks SQL |
|--------------|----------------|
| `SUM(table[column])` | `SUM(column)` |
| `COUNT(table[column])` | `COUNT(column)` |
| `DISTINCTCOUNT(table[column])` | `COUNT(DISTINCT column)` |
| `AVERAGE(table[column])` | `AVG(column)` |
| `DIVIDE([measure1], [measure2])` | `measure1 / NULLIF(measure2, 0)` |

### Column Transformation

| Power BI (M/DAX) | Databricks SQL |
|------------------|----------------|
| `Text.Trim([column])` | `TRIM(column)` |
| `Text.Upper([column])` | `UPPER(column)` |
| `Text.Lower([column])` | `LOWER(column)` |
| `Text.Clean([column])` | `REGEXP_REPLACE(column, '[\\x00-\\x1F]', '')` |
| `Date.From([datetime])` | `DATE(datetime)` |
| `Date.Year([date])` | `YEAR(date)` |
| `Date.Month([date])` | `MONTH(date)` |
| `"Q" & QuarterOfYear([date])` | `CONCAT('Q', QUARTER(date))` |
| `[Quantity] * [UnitPrice]` | `quantity * unit_price AS totalprice` |
| `CALENDAR(min, max)` | `explode(sequence(min_date, max_date, interval 1 day))` |

---

## Troubleshooting

### Variable substitution in JSON
DAB doesn't substitute `${var.x}` inside dashboard JSON files. Use hardcoded catalog/schema in queries.

### Catalog creation requires managed location
When creating a catalog, you must provide a storage location:
```sql
CREATE CATALOG IF NOT EXISTS <your-catalog>
MANAGED LOCATION 'abfss://container@storage.dfs.core.windows.net/path';
```

### SQL warehouse already exists
If a warehouse with the same name already exists, you have two options:

**Option 1:** Use `lookup` to reference the existing warehouse:
```yaml
variables:
  warehouse_id:
    lookup:
      warehouse: "Warehouse Name"
```
Then reference via `${var.warehouse_id}` instead of `${resources.sql_warehouses...}`.

**Option 2:** Change the warehouse name in `warehouses/dashboard_warehouse.yml`.

### SQL files in include
Use `sync.include` not `include` for SQL files (YAML/JSON only for `include`):
```yaml
sync:
  include:
    - src/views/*.sql
```

### Organizing resources in folders
Use `include` to reference YAML files from subfolders:
```yaml
include:
  - jobs/*.yml
  - warehouses/*.yml
```

### Table Widget Troubleshooting

If a table doesn't render or shows "spec must NOT have additional properties":
1. Verify `disaggregated: true` in the query
2. Verify `spec.version: 1`
3. Add `"invisibleColumns": []` to the spec (required even if empty)
4. For date columns: use `type: "date"` with `displayAs: "datetime"` (not `displayAs: "date"`)
5. Check that `numberFormat` is set for numeric columns
6. Check that `dateTimeFormat` uses format like `"DD/MM/YYYY"` (not `"YYYY-MM-DD"`)
7. Verify `allowHTMLByDefault` and `paginationSize` are in the spec
8. Use sequential `order` values starting from `0` (not `100000`)

### Validation Checklist

Before deploying:

- [ ] All IDs are unique 8-character hex strings
- [ ] All `datasetName` references exist in `datasets` array
- [ ] All `fieldName` values match field `name` in queries
- [ ] No widget positions overlap
- [ ] Positions stay within 6-column grid (x + width <= 6)
- [ ] SQL queries use proper Unity Catalog paths (catalog.schema.table)
- [ ] All categorical columns visible on charts have corresponding filter widgets
- [ ] JSON is valid and properly escaped

---

## Migration Checklist

### Before Migration
- [ ] Identify all tables in the semantic model
- [ ] List tables requiring views (calculated columns/tables)
- [ ] Document source table locations
- [ ] Extract theme colors

### During Migration
- [ ] Create `create_schema.sql` with catalog and schema
- [ ] Create SQL views in `src/views/` for each transformed table
- [ ] Create dashboard JSON in `dashboard/src/`
- [ ] Create warehouse definition in `warehouses/`
- [ ] Create job definition in `jobs/`
- [ ] Configure `databricks.yml` with includes
- [ ] Map all measures to SQL aggregations
- [ ] Verify dataset queries reference views where applicable

### After Migration
- [ ] Validate bundle configuration (`databricks bundle validate`)
- [ ] Deploy bundle (`databricks bundle deploy --target dev`)
- [ ] Run create_views job (`databricks bundle run create_views --target dev`)
- [ ] Test dashboard visualizations
- [ ] Compare with original Power BI report

---

## Complete Example: BakehouseSales Migration

This example shows a complete migration of the BakehouseSales Power BI report.

**Source Report:** `powerBI_reports/BakehpouseSales.Report/`

### Table Analysis

| Table | Source | Has Transformations | Action |
|-------|--------|---------------------|--------|
| `sales_transactions` | `samples.bakehouse.sales_transactions` | Yes (TRIM, calculated columns) | **Create view** `vw_sales_transactions` |
| `DimDate` | Calculated (DAX CALENDAR) | N/A - fully calculated | **Create view** `vw_dim_date` |
| `_Measures` | N/A | N/A | **SQL aggregations** in queries |
| `sales_customers` | `samples.bakehouse.sales_customers` | No | **Direct reference** |
| `sales_franchises` | `samples.bakehouse.sales_franchises` | No | **Direct reference** |
| `sales_suppliers` | `samples.bakehouse.sales_suppliers` | No | **Direct reference** |
| `media_customer_reviews` | `samples.bakehouse.media_customer_reviews` | No | **Direct reference** |
| `media_gold_reviews_chunked` | `samples.bakehouse.media_gold_reviews_chunked` | No | **Direct reference** |

### Visuals Analysis

| Visual ID | Power BI Type | Databricks Type | Data | Position |
|-----------|---------------|-----------------|------|----------|
| cd1951f9... | card | counter | Revenue | x:1, y:0, w:2, h:2 |
| a79a39dc... | card | counter | Customers | x:3, y:0, w:2, h:2 |
| 9bb4cf05... | card | counter | Franchises | x:5, y:0, w:1, h:2 |
| 09cddf18... | tableEx | table | OrderDate, Customers, Orders, Revenue, Units, Franchises | x:0, y:2, w:3, h:6 |
| 70ec2a0c... | lineChart | line | Customers by OrderDate | x:3, y:2, w:3, h:6 |
| 61d87597... | lineChart | line | Orders by OrderDate | x:0, y:8, w:3, h:5 |
| 7b4e1f6b... | lineChart | line | Revenue by OrderDate | x:3, y:8, w:3, h:5 |

### Theme Colors

From Power BI theme `Modern_Clean_Sales_Template`:
- dataColors[0]: `#1F4B99` (dark blue)
- dataColors[1]: `#2EA8E0` (light blue)
- dataColors[2]: `#FF9F1C` (orange)
- dataColors[3]: `#2ECC71` (green)
- dataColors[4]: `#E74C3C` (red)
- dataColors[5]: `#7F8C8D` (gray)
- dataColors[8]: `#3599B8` (teal)

### Files Created

```
├── databricks.yml
├── jobs/
│   └── create_views.yml
├── warehouses/
│   └── dashboard_warehouse.yml
├── dashboard/src/
│   └── BakehouseSales.lvdash.json
└── src/views/
    ├── create_schema.sql
    ├── vw_sales_transactions.sql
    └── vw_dim_date.sql
```

### create_schema.sql
```sql
-- Catalog and schema for BakehouseSales dashboard views

CREATE CATALOG IF NOT EXISTS <your-catalog>
MANAGED LOCATION 'abfss://<your-container>@<your-storage-account>.dfs.core.windows.net/<your-path>';

CREATE SCHEMA IF NOT EXISTS <your-catalog>.dashboard_bakehousesales_views
```

### vw_sales_transactions.sql
```sql
-- View: vw_sales_transactions
-- Source: samples.bakehouse.sales_transactions
-- Transformations: Column renaming, TRIM on text columns, calculated date columns

CREATE OR REPLACE VIEW <your-catalog>.dashboard_bakehousesales_views.vw_sales_transactions AS
SELECT
    transactionID AS Transactionid,
    customerID AS Customerid,
    franchiseID AS Franchiseid,
    datetime AS Datetime,
    TRIM(product) AS Product,
    quantity AS Quantity,
    unitPrice AS Unitprice,
    CAST(quantity * unitPrice AS BIGINT) AS Totalprice,
    TRIM(paymentMethod) AS Paymentmethod,
    cardNumber AS Cardnumber,
    DATE(datetime) AS OrderDate,
    YEAR(datetime) AS Year,
    MONTH(datetime) AS Month,
    CONCAT('Q', QUARTER(datetime)) AS Quarter
FROM samples.bakehouse.sales_transactions
```

### vw_dim_date.sql
```sql
-- View: vw_dim_date
-- Source: Calculated from sales_transactions date range

CREATE OR REPLACE VIEW <your-catalog>.dashboard_bakehousesales_views.vw_dim_date AS
WITH date_range AS (
    SELECT MIN(DATE(datetime)) AS min_date, MAX(DATE(datetime)) AS max_date
    FROM samples.bakehouse.sales_transactions
),
date_sequence AS (
    SELECT explode(sequence(min_date, max_date, interval 1 day)) AS Date
    FROM date_range
)
SELECT
    Date,
    YEAR(Date) AS Year,
    MONTH(Date) AS MonthNumber,
    DATE_FORMAT(Date, 'MMM') AS Month,
    CONCAT('Q', QUARTER(Date)) AS Quarter,
    DATE_FORMAT(Date, 'yyyy-MM') AS YearMonth,
    DAYOFWEEK(Date) AS DayOfWeek,
    DATE_FORMAT(Date, 'EEE') AS DayName
FROM date_sequence
```

### jobs/create_views.yml
```yaml
resources:
  jobs:
    create_views:
      name: "Create Dashboard Views"
      tasks:
        - task_key: create_schema
          sql_task:
            warehouse_id: ${resources.sql_warehouses.dashboard_warehouse.id}
            file:
              path: ${workspace.root_path}/files/src/views/create_schema.sql

        - task_key: create_vw_sales_transactions
          sql_task:
            warehouse_id: ${resources.sql_warehouses.dashboard_warehouse.id}
            file:
              path: ${workspace.root_path}/files/src/views/vw_sales_transactions.sql
          depends_on:
            - task_key: create_schema

        - task_key: create_vw_dim_date
          sql_task:
            warehouse_id: ${resources.sql_warehouses.dashboard_warehouse.id}
            file:
              path: ${workspace.root_path}/files/src/views/vw_dim_date.sql
          depends_on:
            - task_key: create_vw_sales_transactions
```

### warehouses/dashboard_warehouse.yml
```yaml
resources:
  sql_warehouses:
    dashboard_warehouse:
      name: "Dashboard SQL Warehouse"
      cluster_size: "2X-Small"
      max_num_clusters: 1
      auto_stop_mins: 10
      enable_serverless_compute: true
```

### databricks.yml
```yaml
bundle:
  name: pbi_dashboard_migration

workspace:
  host: https://<your-databricks-workspace-url>

include:
  - jobs/*.yml
  - warehouses/*.yml

sync:
  include:
    - src/views/*.sql

resources:
  dashboards:
    bakehousesales_dashboard:
      display_name: "BakehouseSales"
      file_path: ./dashboard/src/BakehouseSales.lvdash.json
      warehouse_id: ${resources.sql_warehouses.dashboard_warehouse.id}

targets:
  dev:
    mode: development
    default: true
    workspace:
      root_path: /Workspace/Users/${workspace.current_user.userName}/.bundle/${bundle.name}/dev

  prod:
    mode: production
    workspace:
      root_path: /Workspace/Users/${workspace.current_user.userName}/.bundle/${bundle.name}/prod
```

### BakehouseSales.lvdash.json (Complete Dashboard)
```json
{
  "datasets": [
    {
      "name": "d1a2b3c4",
      "displayName": "sales-metrics",
      "queryLines": [
        "SELECT ",
        "  OrderDate, ",
        "  SUM(Totalprice) AS Revenue, ",
        "  COUNT(DISTINCT Transactionid) AS Orders, ",
        "  COUNT(DISTINCT Customerid) AS Customers, ",
        "  SUM(Quantity) AS Units, ",
        "  COUNT(DISTINCT Franchiseid) AS Franchises ",
        " FROM <your-catalog>.dashboard_bakehousesales_views.vw_sales_transactions ",
        " GROUP BY OrderDate ",
        " ORDER BY OrderDate"
      ]
    },
    {
      "name": "d2b3c4d5",
      "displayName": "kpi-totals",
      "queryLines": [
        "SELECT ",
        "  SUM(Totalprice) AS Revenue, ",
        "  COUNT(DISTINCT Transactionid) AS Orders, ",
        "  COUNT(DISTINCT Customerid) AS Customers, ",
        "  SUM(Quantity) AS Units, ",
        "  COUNT(DISTINCT Franchiseid) AS Franchises ",
        " FROM <your-catalog>.dashboard_bakehousesales_views.vw_sales_transactions"
      ]
    }
  ],
  "pages": [
    {
      "name": "p1a2b3c4",
      "displayName": "Sales Overview",
      "layout": [
        {
          "widget": {
            "name": "w1revenue",
            "queries": [
              {
                "name": "main_query",
                "query": {
                  "datasetName": "d2b3c4d5",
                  "fields": [
                    { "name": "Revenue", "expression": "`Revenue`" }
                  ],
                  "disaggregated": false
                }
              }
            ],
            "spec": {
              "version": 2,
              "widgetType": "counter",
              "encodings": {
                "value": { "fieldName": "Revenue", "displayName": "Revenue" }
              },
              "frame": { "showTitle": true, "title": "Revenue" }
            }
          },
          "position": { "x": 0, "y": 0, "width": 2, "height": 2 }
        },
        {
          "widget": {
            "name": "w2custmrs",
            "queries": [
              {
                "name": "main_query",
                "query": {
                  "datasetName": "d2b3c4d5",
                  "fields": [
                    { "name": "Customers", "expression": "`Customers`" }
                  ],
                  "disaggregated": false
                }
              }
            ],
            "spec": {
              "version": 2,
              "widgetType": "counter",
              "encodings": {
                "value": { "fieldName": "Customers", "displayName": "Customers" }
              },
              "frame": { "showTitle": true, "title": "Customers" }
            }
          },
          "position": { "x": 2, "y": 0, "width": 2, "height": 2 }
        },
        {
          "widget": {
            "name": "w3frnchs",
            "queries": [
              {
                "name": "main_query",
                "query": {
                  "datasetName": "d2b3c4d5",
                  "fields": [
                    { "name": "Franchises", "expression": "`Franchises`" }
                  ],
                  "disaggregated": false
                }
              }
            ],
            "spec": {
              "version": 2,
              "widgetType": "counter",
              "encodings": {
                "value": { "fieldName": "Franchises", "displayName": "Franchises" }
              },
              "frame": { "showTitle": true, "title": "Franchises" }
            }
          },
          "position": { "x": 4, "y": 0, "width": 2, "height": 2 }
        },
        {
          "widget": {
            "name": "w4table1",
            "queries": [
              {
                "name": "main_query",
                "query": {
                  "datasetName": "d1a2b3c4",
                  "fields": [
                    { "name": "OrderDate", "expression": "`OrderDate`" },
                    { "name": "Customers", "expression": "`Customers`" },
                    { "name": "Orders", "expression": "`Orders`" },
                    { "name": "Revenue", "expression": "`Revenue`" },
                    { "name": "Units", "expression": "`Units`" },
                    { "name": "Franchises", "expression": "`Franchises`" }
                  ],
                  "disaggregated": true
                }
              }
            ],
            "spec": {
              "version": 1,
              "widgetType": "table",
              "encodings": {
                "columns": [
                  {
                    "fieldName": "OrderDate",
                    "dateTimeFormat": "DD/MM/YYYY",
                    "booleanValues": ["false", "true"],
                    "imageUrlTemplate": "{{ @ }}",
                    "imageTitleTemplate": "{{ @ }}",
                    "imageWidth": "",
                    "imageHeight": "",
                    "linkUrlTemplate": "{{ @ }}",
                    "linkTextTemplate": "{{ @ }}",
                    "linkTitleTemplate": "{{ @ }}",
                    "linkOpenInNewTab": true,
                    "type": "date",
                    "displayAs": "datetime",
                    "visible": true,
                    "order": 0,
                    "title": "Order Date",
                    "allowSearch": false,
                    "alignContent": "right",
                    "allowHTML": false,
                    "highlightLinks": false,
                    "useMonospaceFont": false,
                    "preserveWhitespace": false
                  },
                  {
                    "fieldName": "Customers",
                    "numberFormat": "0",
                    "booleanValues": ["false", "true"],
                    "imageUrlTemplate": "{{ @ }}",
                    "imageTitleTemplate": "{{ @ }}",
                    "imageWidth": "",
                    "imageHeight": "",
                    "linkUrlTemplate": "{{ @ }}",
                    "linkTextTemplate": "{{ @ }}",
                    "linkTitleTemplate": "{{ @ }}",
                    "linkOpenInNewTab": true,
                    "type": "integer",
                    "displayAs": "number",
                    "visible": true,
                    "order": 1,
                    "title": "Customers",
                    "allowSearch": false,
                    "alignContent": "right",
                    "allowHTML": false,
                    "highlightLinks": false,
                    "useMonospaceFont": false,
                    "preserveWhitespace": false
                  },
                  {
                    "fieldName": "Orders",
                    "numberFormat": "0",
                    "booleanValues": ["false", "true"],
                    "imageUrlTemplate": "{{ @ }}",
                    "imageTitleTemplate": "{{ @ }}",
                    "imageWidth": "",
                    "imageHeight": "",
                    "linkUrlTemplate": "{{ @ }}",
                    "linkTextTemplate": "{{ @ }}",
                    "linkTitleTemplate": "{{ @ }}",
                    "linkOpenInNewTab": true,
                    "type": "integer",
                    "displayAs": "number",
                    "visible": true,
                    "order": 2,
                    "title": "Orders",
                    "allowSearch": false,
                    "alignContent": "right",
                    "allowHTML": false,
                    "highlightLinks": false,
                    "useMonospaceFont": false,
                    "preserveWhitespace": false
                  },
                  {
                    "fieldName": "Revenue",
                    "numberFormat": "#,##0",
                    "booleanValues": ["false", "true"],
                    "imageUrlTemplate": "{{ @ }}",
                    "imageTitleTemplate": "{{ @ }}",
                    "imageWidth": "",
                    "imageHeight": "",
                    "linkUrlTemplate": "{{ @ }}",
                    "linkTextTemplate": "{{ @ }}",
                    "linkTitleTemplate": "{{ @ }}",
                    "linkOpenInNewTab": true,
                    "type": "integer",
                    "displayAs": "number",
                    "visible": true,
                    "order": 3,
                    "title": "Revenue",
                    "allowSearch": false,
                    "alignContent": "right",
                    "allowHTML": false,
                    "highlightLinks": false,
                    "useMonospaceFont": false,
                    "preserveWhitespace": false
                  },
                  {
                    "fieldName": "Units",
                    "numberFormat": "#,##0.00",
                    "booleanValues": ["false", "true"],
                    "imageUrlTemplate": "{{ @ }}",
                    "imageTitleTemplate": "{{ @ }}",
                    "imageWidth": "",
                    "imageHeight": "",
                    "linkUrlTemplate": "{{ @ }}",
                    "linkTextTemplate": "{{ @ }}",
                    "linkTitleTemplate": "{{ @ }}",
                    "linkOpenInNewTab": true,
                    "type": "decimal",
                    "displayAs": "number",
                    "visible": true,
                    "order": 4,
                    "title": "Units",
                    "allowSearch": false,
                    "alignContent": "right",
                    "allowHTML": false,
                    "highlightLinks": false,
                    "useMonospaceFont": false,
                    "preserveWhitespace": false
                  },
                  {
                    "fieldName": "Franchises",
                    "numberFormat": "0",
                    "booleanValues": ["false", "true"],
                    "imageUrlTemplate": "{{ @ }}",
                    "imageTitleTemplate": "{{ @ }}",
                    "imageWidth": "",
                    "imageHeight": "",
                    "linkUrlTemplate": "{{ @ }}",
                    "linkTextTemplate": "{{ @ }}",
                    "linkTitleTemplate": "{{ @ }}",
                    "linkOpenInNewTab": true,
                    "type": "integer",
                    "displayAs": "number",
                    "visible": true,
                    "order": 5,
                    "title": "Franchises",
                    "allowSearch": false,
                    "alignContent": "right",
                    "allowHTML": false,
                    "highlightLinks": false,
                    "useMonospaceFont": false,
                    "preserveWhitespace": false
                  }
                ]
              },
              "invisibleColumns": [],
              "allowHTMLByDefault": false,
              "itemsPerPage": 25,
              "paginationSize": "default",
              "condensed": true,
              "withRowNumber": false
            }
          },
          "position": { "x": 0, "y": 2, "width": 3, "height": 6 }
        },
        {
          "widget": {
            "name": "w5custln",
            "queries": [
              {
                "name": "main_query",
                "query": {
                  "datasetName": "d1a2b3c4",
                  "fields": [
                    { "name": "OrderDate", "expression": "`OrderDate`" },
                    { "name": "Customers", "expression": "`Customers`" }
                  ],
                  "disaggregated": true
                }
              }
            ],
            "spec": {
              "version": 3,
              "widgetType": "line",
              "encodings": {
                "x": {
                  "fieldName": "OrderDate",
                  "displayName": "Order Date",
                  "scale": { "type": "temporal" }
                },
                "y": {
                  "fieldName": "Customers",
                  "displayName": "Customers",
                  "scale": { "type": "quantitative" }
                }
              },
              "frame": { "showTitle": true, "title": "Customers by Date" },
              "mark": {
                "colors": [
                  "#E74C3C",
                  { "themeColorType": "visualizationColors", "position": 2 },
                  { "themeColorType": "visualizationColors", "position": 3 },
                  { "themeColorType": "visualizationColors", "position": 4 },
                  { "themeColorType": "visualizationColors", "position": 5 },
                  { "themeColorType": "visualizationColors", "position": 6 },
                  { "themeColorType": "visualizationColors", "position": 7 },
                  { "themeColorType": "visualizationColors", "position": 8 },
                  { "themeColorType": "visualizationColors", "position": 9 },
                  { "themeColorType": "visualizationColors", "position": 10 }
                ]
              }
            }
          },
          "position": { "x": 3, "y": 2, "width": 3, "height": 6 }
        },
        {
          "widget": {
            "name": "w6ordlne",
            "queries": [
              {
                "name": "main_query",
                "query": {
                  "datasetName": "d1a2b3c4",
                  "fields": [
                    { "name": "OrderDate", "expression": "`OrderDate`" },
                    { "name": "Orders", "expression": "`Orders`" }
                  ],
                  "disaggregated": true
                }
              }
            ],
            "spec": {
              "version": 3,
              "widgetType": "line",
              "encodings": {
                "x": {
                  "fieldName": "OrderDate",
                  "displayName": "Order Date",
                  "scale": { "type": "temporal" }
                },
                "y": {
                  "fieldName": "Orders",
                  "displayName": "Orders",
                  "scale": { "type": "quantitative" }
                }
              },
              "frame": { "showTitle": true, "title": "Orders by Date" },
              "mark": {
                "colors": [
                  "#3599B8",
                  { "themeColorType": "visualizationColors", "position": 2 },
                  { "themeColorType": "visualizationColors", "position": 3 },
                  { "themeColorType": "visualizationColors", "position": 4 },
                  { "themeColorType": "visualizationColors", "position": 5 },
                  { "themeColorType": "visualizationColors", "position": 6 },
                  { "themeColorType": "visualizationColors", "position": 7 },
                  { "themeColorType": "visualizationColors", "position": 8 },
                  { "themeColorType": "visualizationColors", "position": 9 },
                  { "themeColorType": "visualizationColors", "position": 10 }
                ]
              }
            }
          },
          "position": { "x": 0, "y": 8, "width": 3, "height": 5 }
        },
        {
          "widget": {
            "name": "w7revlne",
            "queries": [
              {
                "name": "main_query",
                "query": {
                  "datasetName": "d1a2b3c4",
                  "fields": [
                    { "name": "OrderDate", "expression": "`OrderDate`" },
                    { "name": "Revenue", "expression": "`Revenue`" }
                  ],
                  "disaggregated": true
                }
              }
            ],
            "spec": {
              "version": 3,
              "widgetType": "line",
              "encodings": {
                "x": {
                  "fieldName": "OrderDate",
                  "displayName": "Order Date",
                  "scale": { "type": "temporal" }
                },
                "y": {
                  "fieldName": "Revenue",
                  "displayName": "Revenue",
                  "scale": { "type": "quantitative" }
                }
              },
              "frame": { "showTitle": true, "title": "Revenue by Date" },
              "mark": {
                "colors": [
                  "#2ECC71",
                  { "themeColorType": "visualizationColors", "position": 2 },
                  { "themeColorType": "visualizationColors", "position": 3 },
                  { "themeColorType": "visualizationColors", "position": 4 },
                  { "themeColorType": "visualizationColors", "position": 5 },
                  { "themeColorType": "visualizationColors", "position": 6 },
                  { "themeColorType": "visualizationColors", "position": 7 },
                  { "themeColorType": "visualizationColors", "position": 8 },
                  { "themeColorType": "visualizationColors", "position": 9 },
                  { "themeColorType": "visualizationColors", "position": 10 }
                ]
              }
            }
          },
          "position": { "x": 3, "y": 8, "width": 3, "height": 5 }
        }
      ]
    }
  ]
}
```

### Deploy Commands
```bash
# Validate bundle
databricks bundle validate

# Deploy to dev
databricks bundle deploy --target dev

# Create views
databricks bundle run create_views --target dev
```
