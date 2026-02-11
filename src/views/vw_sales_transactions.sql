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
