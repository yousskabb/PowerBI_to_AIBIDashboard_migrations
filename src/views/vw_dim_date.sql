-- View: vw_dim_date
-- Source: Calculated from sales_transactions date range
-- Equivalent to Power BI CALENDAR() DAX function

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
