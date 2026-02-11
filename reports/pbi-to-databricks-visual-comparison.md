# Power BI to Databricks AI/BI Dashboard - Visual Type Comparison Report

**Date:** 2026-02-06
**Project:** PBI Dashboard Migration to Databricks

---

## Overview

This report provides a comprehensive comparison of Power BI visual types and their Databricks AI/BI dashboard equivalents, documenting which visuals have a direct 1:1 match, which require approximation, and which have no equivalent.

---

## 1. Complete Visual Type Mapping

### Direct 1:1 Matches

These Power BI visuals map directly to a Databricks widget with equivalent functionality.

| Power BI Visual | Databricks Widget | `widgetType` | Spec Version | Notes |
|-----------------|-------------------|-------------|--------------|-------|
| card | counter | `counter` | 2 | Single KPI value display |
| multi-row card | counter (multiple) | `counter` | 2 | Use multiple counter widgets |
| textbox | textbox | `textbox_spec` | N/A | Supports markdown |
| slicer | filter-single-select | `filter-single-select` | 2 | Use field-based filtering for dropdown |
| slicer (multi) | filter-multi-select | `filter-multi-select` | 2 | Use field-based filtering for dropdown |
| lineChart | line | `line` | 3 | Trends over time |
| barChart | bar | `bar` | 3 | Horizontal/vertical bars |
| clusteredBarChart | bar | `bar` | 3 | Same widget, categorical x-axis |
| stackedBarChart | bar | `bar` | 3 | Use color encoding for stacking |
| pieChart | pie | `pie` | 3 | Proportional data |
| donutChart | pie | `pie` | 3 | Rendered as pie (no donut variant) |
| tableEx | table | `table` | 1 | Data table with column definitions |
| matrix | pivot | `pivot` | 1 | Pivot/crosstab table |
| scatterChart | scatter | `scatter` | 3 | X/Y relationship |
| bubbleChart | scatter | `scatter` | 3 | Scatter with size encoding |
| areaChart (stacked) | area | `area` | 3 | Stacked area chart |
| combo chart | combo | `combo` | 3 | Combined bar + line, dual axis |
| funnel | funnel | `funnel` | 3 | Pipeline/stage progression (added Aug 2025) |
| waterfall | waterfall | `waterfall` | 3 | Cumulative values (added Oct 2025) |
| map / filledMap | choropleth | `choropleth` | 3 | Colored geographic regions (added Apr 2025) |
| map (points) | point-map | `point-map` | 3 | Markers at lat/long coordinates |

### Approximate Matches (Partial Parity)

These Power BI visuals require a different Databricks widget that provides similar but not identical functionality.

| Power BI Visual | Databricks Widget | `widgetType` | Limitation |
|-----------------|-------------------|-------------|------------|
| gauge | counter | `counter` | Shows number only, no dial/arc visual. Counter supports sparkline (Nov 2025) for trend indication |
| KPI | counter | `counter` | No target line or trend arrow. Use sparkline for trend |
| areaChart (non-stacked) | line | `line` | Databricks area charts are always stacked; non-stacked must use line |
| ribbon chart | line | `line` | Use line with color encoding as approximation |
| 100% stacked bar | bar | `bar` | No native 100% stacking; use regular stacked bar |

### No Databricks Equivalent

These Power BI visuals have no matching Databricks widget type.

| Power BI Visual | Suggested Workaround |
|-----------------|---------------------|
| treemap | Use pie chart or bar chart as approximation |
| decomposition tree | No equivalent; consider table or pivot with drill-down |
| key influencers | No equivalent; use separate analysis |
| Q&A (natural language) | Use Databricks Genie as a separate feature |
| smart narrative | No equivalent |
| paginated report | No equivalent within dashboards |
| R / Python visuals | No equivalent; use Databricks notebooks for custom visuals |
| shape map | Use choropleth as approximation |
| ArcGIS map | Use point-map or choropleth |

---

## 2. Databricks-Only Widget Types

These Databricks widgets have no direct Power BI equivalent:

| Databricks Widget | `widgetType` | Description |
|-------------------|-------------|-------------|
| heatmap | `heatmap` | Color intensity matrix for correlation |
| histogram | `histogram` | Frequency distribution with configurable bins |
| box plot | `box` | Data distribution (added Sep 2024) |
| cohort | `cohort` | Retention/behavior tracking over time |
| sankey | `sankey` | Flow visualization between values (added Apr 2025) |

---

## 3. Filter Widget Mapping

| Power BI Slicer Type | Databricks Filter Widget | `widgetType` |
|---------------------|------------------------|-------------|
| List slicer | filter-single-select | `filter-single-select` |
| List slicer (multi) | filter-multi-select | `filter-multi-select` |
| Date slicer | filter-date-picker | `filter-date-picker` |
| Date range slicer | filter-date-range-picker | `filter-date-range-picker` |
| Numeric range slicer | filter-range-slider | `filter-range-slider` |
| Search/text slicer | filter-text-entry | `filter-text-entry` |

---

## 4. Migration Status - Current Reports

### AdventureWorks Sales

| Power BI Visual | Original Type | Databricks Widget | Match Quality |
|-----------------|--------------|-------------------|---------------|
| Title | textbox | textbox_spec | 1:1 |
| Fiscal Year Slicer | slicer | filter-single-select | 1:1 |
| Sales by Order/Due Date | areaChart (non-stacked) | line | Approximate (no non-stacked area) |
| Order Qty by Country | map | choropleth | 1:1 (updated) |
| Sales by Category/Business Type | tableEx | table | 1:1 |

### Sample Superstore

| Power BI Visual | Original Type | Databricks Widget | Match Quality |
|-----------------|--------------|-------------------|---------------|
| Title | textbox | textbox_spec | 1:1 |
| City Filter | slicer | filter-single-select | 1:1 |
| Total Profit | gauge | counter | Approximate (no dial) |
| Total Quantity | gauge | counter | Approximate (no dial) |
| Total Sales | gauge | counter | Approximate (no dial) |
| Profit by Region | lineChart | line | 1:1 |
| Profit by Sub-Category | barChart | bar | 1:1 |
| Profit by Segment | pieChart | pie | 1:1 |
| Profit by Category | pieChart | pie | 1:1 |

---

## 5. Key Technical Differences

| Feature | Power BI | Databricks AI/BI |
|---------|----------|------------------|
| Data model | Semantic model with relationships | Independent SQL datasets per dashboard |
| Cross-filtering | Automatic via relationships | Only between widgets on same dataset |
| Filter propagation | Automatic to all visuals | Must explicitly bind filter to each dataset |
| Area chart stacking | Configurable (stacked/non-stacked) | Always stacked |
| Gauge visual | Native gauge with dial | Not available (use counter) |
| Conditional formatting | Extensive | Limited |
| Drill-through | Supported | Not supported in dashboards |
| Bookmarks | Supported | Not supported |
| Custom visuals | Marketplace | Not supported |

---

*Generated as part of the PBI Dashboard Migration to Databricks project.*
