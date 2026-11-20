# Financial Transactions SQL Analysis

End-to-end data quality auditing, SQL transformation, and interactive BI reporting on a financial transactions dataset using **PostgreSQL**, **pgAdmin**, and **Power BI Desktop**.

## Overview

This project covers the full workflow from raw CSV ingestion and data quality validation in PostgreSQL to a clean reporting view (`v_transactions_clean`) connected to an interactive Power BI dashboard.

- **Database:** PostgreSQL
- **Client / UI:** pgAdmin / `psql`
- **BI & Visualization:** Power BI Desktop (Import mode)
- **Main Script:** `sql/01_transactions_analysis.sql`

## Dataset

Source: *Financial Transactions Dataset* (`transactions_data.csv`, ~265 MB) and reference lookup data (such as `mcc_codes`).  
Raw CSV files are not committed to the repository; local loading is done into PostgreSQL (`public.transactions_data`).

## How to Run Locally

1. Create a database in PostgreSQL (e.g., `finance_analytics`) and create the `public.transactions_data` table (keeping raw fields like `amount` safe for controlled cleaning).
2. Load `transactions_data.csv` using `\copy` in `psql` or the import workflow in pgAdmin.
3. *(Optional)* Load reference lookup tables such as `public.mcc_codes` for category descriptions.
4. Run sections from `sql/01_transactions_analysis.sql` in pgAdmin Query Tool or `psql`.

## What the SQL Script Covers

1. **Data Quality Audit**
   - Total row count, distinct transaction IDs, duplicate ID checks, and date range coverage.
   - Null / blank checks across key identifiers, timestamps, amounts, locations, and MCC codes.
   - Format validation of raw `amount` strings prior to numeric casting.
2. **Core Business Metrics & Breakdowns**
   - Net total amount, positive/negative sums, average, and median transaction value.
   - Volume and share breakdowns by transaction channel (`use_chip`) and merchant category (`mcc`).
3. **Time Trends, Errors & Anomalies**
   - Monthly transaction volume and value trends, plus day-of-week distribution.
   - Frequency and monetary value of recorded `errors`.
   - Flagging negative (refund/reversal), zero, and high-value transactions for review.

## Key Findings (Fill After Running Queries)

- **Data quality / coverage:** `[e.g., X rows from YYYY-MM to YYYY-MM; 0 duplicate IDs; Y% missing merchant_city]`
- **Main volume & category drivers:** `[e.g., Top MCC categories and dominant transaction channel]`
- **Notable anomalies / errors:** `[e.g., Most frequent error code and share of negative/high-value transactions]`
