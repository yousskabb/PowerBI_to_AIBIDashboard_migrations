-- Catalog and schema for BakehouseSales dashboard views

CREATE CATALOG IF NOT EXISTS <your-catalog>
MANAGED LOCATION 'abfss://<your-container>@<your-storage-account>.dfs.core.windows.net/<your-path>';

CREATE SCHEMA IF NOT EXISTS <your-catalog>.dashboard_bakehousesales_views
