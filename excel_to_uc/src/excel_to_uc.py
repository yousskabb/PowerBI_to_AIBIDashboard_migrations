# Databricks notebook source

# COMMAND ----------

# MAGIC %pip install openpyxl xlrd

# COMMAND ----------

dbutils.library.restartPython()

# COMMAND ----------

import pandas as pd
import os
import re

# COMMAND ----------

# Parameters
dbutils.widgets.text("catalog", "<your-catalog>", "Catalog Name")
dbutils.widgets.text("datasets_path", "", "Path to datasets folder")

catalog = dbutils.widgets.get("catalog")
datasets_path = dbutils.widgets.get("datasets_path")

print(f"Catalog: {catalog}")
print(f"Datasets path: {datasets_path}")

# COMMAND ----------

excel_files = [f for f in os.listdir(datasets_path) if f.endswith((".xls", ".xlsx"))]
print(f"Found Excel files: {excel_files}")

# COMMAND ----------

for excel_file in excel_files:
    file_path = os.path.join(datasets_path, excel_file)

    # Schema name from file name (sanitize for UC)
    file_name_no_ext = os.path.splitext(excel_file)[0]
    schema_name_clean = re.sub(r"[^a-zA-Z0-9]", "_", file_name_no_ext).lower().strip("_")
    schema_name = f"dashboard_{schema_name_clean}"

    print(f"\n--- Processing: {excel_file} ---")
    print(f"Schema: {catalog}.{schema_name}")

    spark.sql(f"CREATE SCHEMA IF NOT EXISTS {catalog}.{schema_name}")

    xls = pd.ExcelFile(file_path)

    for sheet_name in xls.sheet_names:
        df_pd = pd.read_excel(xls, sheet_name=sheet_name)

        if df_pd.empty:
            print(f"  Skipping empty sheet: {sheet_name}")
            continue

        # Table name: preserve original sheet name via backticks
        table_name_clean = re.sub(r"[^a-zA-Z0-9]", "_", sheet_name).lower().strip("_")

        # Convert to Spark DataFrame (preserves original column names)
        df_spark = spark.createDataFrame(df_pd)

        full_table_name = f"{catalog}.{schema_name}.{table_name_clean}"
        (df_spark.write
            .mode("overwrite")
            .option("overwriteSchema", "true")
            .option("delta.columnMapping.mode", "name")
            .option("delta.minReaderVersion", "2")
            .option("delta.minWriterVersion", "5")
            .saveAsTable(full_table_name))

        print(f"  Created table: {full_table_name} ({len(df_pd)} rows, {len(df_pd.columns)} columns)")
        print(f"    Columns: {list(df_pd.columns)}")
