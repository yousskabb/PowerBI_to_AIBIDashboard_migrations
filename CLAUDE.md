# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a migration toolkit for converting Power BI reports (.pbip format) to Databricks AI/BI dashboards. The migration process transforms:
- Power BI Semantic Models → SQL Views + direct table references
- Power BI Report Visuals → Databricks Dashboard JSON (`.lvdash.json`)
- Power BI Measures → SQL aggregations in dashboard queries
- Deployment configuration → Databricks Asset Bundles

## Project Structure

```
├── powerBI_reports/           # Source Power BI project files (read-only input)
│   └── <ReportName>.Report/
│       ├── definition/pages/  # Visual definitions (visual.json per widget)
│       └── StaticResources/   # Theme colors and styling
│   └── <ReportName>.SemanticModel/
│       └── definition/tables/ # Table definitions (.tmdl files)
├── dashboard/src/             # Generated Databricks dashboards (.lvdash.json)
├── src/views/                 # SQL view definitions for transformed tables
├── jobs/                      # Databricks job definitions (YAML)
├── warehouses/                # SQL Warehouse configuration (YAML)
└── databricks.yml             # Main Asset Bundle configuration
```

## Key Commands

```bash
# Authenticate to Databricks
databricks auth login --host <workspace-url>

# Validate bundle configuration
databricks bundle validate

# Deploy warehouse, dashboard, and jobs
databricks bundle deploy --target dev

# Run view creation job
databricks bundle run create_views --target dev
```

## Architecture

The migration follows a conversion pipeline:

1. **Parse** - Read `.tmdl` files from semantic model, `visual.json` from report pages
2. **Analyze** - Identify tables needing SQL views (calculated columns, transformations)
3. **Transform** - Create SQL views matching Power BI column names exactly
4. **Generate** - Build `.lvdash.json` with datasets, pages, and widgets
5. **Deploy** - Use Databricks Asset Bundles for deployment

### Naming Conventions

- **Views catalog**: `<your-catalog>`
- **Views schema**: `dashboard_<dashboardname>_views`
- **View names**: `vw_<original_table_name>`
- **Dashboard file**: `<ReportName>.lvdash.json`

## Critical Technical Details

### Column Naming
Power BI transforms column names via M query functions. Views must output exact Power BI column names:
- Source `transactionID` → Power BI `Transactionid` (use AS alias)

### Dashboard JSON
- Use 8-character hex IDs for dataset/page/widget names
- Grid is 6 columns wide
- Do NOT use parameters (`:param_name`) for filtering — use field-based filter widgets instead
- Datasets should return all data (no WHERE clause for filters); filter widgets handle filtering client-side
- Counter widgets use `spec.version: 2`
- Table widgets use `spec.version: 1` with `disaggregated: true`
- Chart widgets use `spec.version: 3`

### Table Widget Requirements
Table widgets require complete column definitions including:
- `type`, `displayAs`, `visible`, `order`, `title`, `alignContent`
- All template properties (`imageUrlTemplate`, `linkUrlTemplate`, etc.)
- Spec-level: `invisibleColumns: []`, `allowHTMLByDefault`, `paginationSize`

### Filter Widget Requirements (Preferred: Field-Based Filtering)

Use **field-based filtering** instead of parameter-based filtering. Field-based filters show a dropdown list of values from the dataset and filter all widgets on the same dataset when a value is selected. This is the preferred approach because:
- It shows a proper dropdown list (not a text input)
- No parameters or `WHERE` clauses needed in the dataset SQL
- Datasets return all data; the filter widget handles filtering client-side
- Closer to Power BI slicer behavior (select a value, or clear to see all)

**Single dataset filter example:**
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
  "position": { "x": 0, "y": 0, "width": 1, "height": 1 }
}
```

**Multiple datasets filter (filter controls two datasets):**

When using separate datasets, add one query entry per dataset with the same field name, and a corresponding entry in `encodings.fields`. The filter field must exist in all referenced datasets.

```json
{
  "widget": {
    "name": "w_filter",
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
          { "fieldName": "Fiscal_Year", "displayName": "Fiscal Year", "queryName": "field_datasetA" },
          { "fieldName": "Fiscal_Year", "displayName": "Fiscal Year", "queryName": "field_datasetB" }
        ]
      },
      "frame": { "showTitle": true, "title": "Fiscal Year" }
    }
  }
}
```

**Important:**
- The filter field (e.g., `Fiscal_Year`, `City`) must be included in the SELECT of every dataset the filter references.
- Do NOT use parameters (`parameters` array, `:param_name` in SQL, `parameterName` in encodings) — this creates a text input instead of a dropdown.
- Do NOT use a standalone "lookup" dataset (e.g., `SELECT DISTINCT Year`) — integrate the field into the main dataset(s).

### Connecting Datasets with Filter Widgets
In Power BI, slicers filter all visuals through the semantic model. In Databricks, a **filter widget only filters the dataset(s) it explicitly references** via query entries.

**To filter multiple datasets from one filter widget**, add a query entry per dataset in the filter widget's `queries` array, each with a `fields` entry for the filter column, and a corresponding entry in `encodings.fields`.

**When to use separate datasets:**
- When one chart needs UNION ALL (e.g., multiple measures with different joins) but other charts need a simple query
- This avoids double-counting in the simple charts while keeping filter interactions working via multi-query field bindings
- Ensure the filter field is included in both datasets' SELECT clauses

**When to use a single dataset:**
- When all charts can share the same SQL query without UNION ALL
- Enables cross-filtering (clicking on a bar in one chart filters another chart)
- Filter widgets only need one query entry

### Widget Field Expression Limitations
- **`CASE WHEN` does NOT work** in widget field expressions — widgets will show empty/no results
- Widget field expressions support only simple aggregations: `SUM()`, `COUNT()`, `AVG()`, `MIN()`, `MAX()`
- For conditional logic, handle it in the dataset SQL query, not in widget expressions

### Cross-Filtering Between Visuals

**Rule: Every categorical dimension visible or clickable on the report must have a filter widget that filters all visualizations.** In Power BI, clicking on any category (e.g., a bar segment, pie slice, table row) cross-filters all other visuals automatically. Databricks does not do this across datasets, so you must create explicit filter widgets for every categorical column that appears on the dashboard (e.g., Category, Country, Region, Segment). This ensures users can filter the entire report by any dimension, replicating the Power BI experience.

There are two types of filtering in Databricks dashboards:
1. **Cross-filtering** (clicking on a chart element filters other charts) — only works between widgets using the **same dataset**
2. **Filter widgets** (dropdown filter) — can filter across **multiple datasets** by adding a field query entry per dataset in the filter widget

**How to implement:**
- Identify every categorical/dimension column that is visible on any chart, table, or map (e.g., used in x-axis, color encoding, table column, map region)
- For each such column, create a `filter-single-select` widget referencing **all datasets** that contain that column
- Ensure the column exists in the SELECT and GROUP BY of every dataset the filter references
- When using multiple datasets, add JOINs to each dataset as needed so the filter column is available in all of them

### Visual Type Mapping

| Power BI | Databricks | Spec Version | Notes |
|----------|------------|--------------|-------|
| card | counter | 2 | |
| tableEx | table | 1 | |
| matrix | pivot | 1 | |
| lineChart | line | 3 | |
| areaChart (stacked) | area | 3 | Databricks area charts are always stacked |
| areaChart (non-stacked) | line | 3 | Non-stacked area charts must use line type |
| barChart | bar | 3 | |
| pieChart / donutChart | pie | 3 | |
| scatterChart / bubbleChart | scatter | 3 | Bubble = scatter with size encoding |
| map / filledMap | choropleth | 3 | Colored geographic regions |
| map (points) | point-map | 3 | Markers at lat/long coordinates |
| combo chart | combo | 3 | Combined bar + line, dual axis |
| funnel | funnel | 3 | |
| waterfall | waterfall | 3 | |
| gauge | counter | 2 | No gauge dial; shows number only |
| slicer | filter-single-select | 2 | Field-based for dropdown list |
| slicer (multi) | filter-multi-select | 2 | Field-based for dropdown list |

### SQL Transformations Reference

| Power BI M | SQL |
|------------|-----|
| Text.Trim() | TRIM() |
| Text.Upper() | UPPER() |
| DISTINCTCOUNT() | COUNT(DISTINCT) |
| CALENDAR() | explode(sequence()) |

## Reference Documentation

- `pbi-dashboard-migration.md` - Complete step-by-step migration guide with templates
- `databricks-dashboard-json-agent.md` - Dashboard JSON structure and widget specs
