-- ============================================================================
-- Projekt: Financial Transactions Analysis (PostgreSQL)
-- Zrodlo: transactions_data (oraz opcjonalnie slownik public.mcc_codes)
-- Cel:
--   1. Audyt jakosci danych (kompletnosc, unikalnosc, poprawnosc formatow)
--   2. Glowne metryki biznesowe i rozbicia (wolumeny, kanaly, kategorie MCC)
--   3. Trendy w czasie oraz kontrola bledow i nietypowych kwot
-- ============================================================================


-- ============================================================================
-- SEKCJA 1: AUDYT JAKOSCI DANYCH
-- ============================================================================

-- 1.1 Liczebnosc zbioru, unikalnosc ID transakcji oraz zakres dat
-- Pozwala szybko ocenic skale danych, duplikaty ID i pokrycie czasowe.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT id) AS unique_txn_ids,
    COUNT(*) - COUNT(DISTINCT id) AS duplicate_id_count,
    MIN(date::timestamp) AS min_txn_date,
    MAX(date::timestamp) AS max_txn_date
FROM public.transactions_data;

-- 1.2 Braki danych (NULL / puste wartosci) w kluczowych kolumnach
-- Pomaga sprawdzic, czy pola wymagane do raportowania i laczenia sa kompletne.
SELECT
    COUNT(*) FILTER (WHERE id IS NULL) AS null_id,
    COUNT(*) FILTER (WHERE date IS NULL) AS null_date,
    COUNT(*) FILTER (WHERE client_id IS NULL) AS null_client_id,
    COUNT(*) FILTER (WHERE card_id IS NULL) AS null_card_id,
    COUNT(*) FILTER (WHERE amount IS NULL OR TRIM(amount) = '') AS empty_amount,
    COUNT(*) FILTER (WHERE merchant_city IS NULL OR TRIM(merchant_city) = '') AS empty_city,
    COUNT(*) FILTER (WHERE mcc IS NULL) AS null_mcc
FROM public.transactions_data;

-- 1.3 Walidacja formatu kolumny amount przed konwersja na typ liczbowy
-- Weryfikuje, czy wartosci tekstowe (np. z symbolem waluty) daja sie bezpiecznie
-- zamienic na liczbe.
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE REGEXP_REPLACE(COALESCE(amount, ''), '[^0-9.-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
    ) AS valid_numeric_format,
    COUNT(*) FILTER (
        WHERE NOT (REGEXP_REPLACE(COALESCE(amount, ''), '[^0-9.-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$')
    ) AS invalid_numeric_format
FROM public.transactions_data;


-- ============================================================================
-- SEKCJA 2: KLUCZOWE METRYKI BIZNESOWE I ROZBICIA
-- ============================================================================

-- 2.1 Glowne KPI dla oczyszczonych transakcji (wolumen netto, dodatni, ujemny, srednia, mediana)
-- Rozdziela kwoty dodatnie i ujemne oraz dodaje mediane, aby lepiej ocenic typowa kwote.
WITH clean_txn AS (
    SELECT
        REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g')::numeric AS amt
    FROM public.transactions_data
    WHERE amount IS NOT NULL
      AND REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
)
SELECT
    COUNT(*) AS total_transactions,
    ROUND(SUM(amt), 2) AS net_total_amount,
    ROUND(SUM(amt) FILTER (WHERE amt > 0), 2) AS positive_amount_sum,
    ROUND(SUM(amt) FILTER (WHERE amt < 0), 2) AS negative_amount_sum,
    ROUND(AVG(amt), 2) AS avg_transaction_amount,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amt)::numeric, 2) AS median_transaction_amount
FROM clean_txn;

-- 2.2 Wolumeny i srednie wedlug kanalu / sposobu realizacji (use_chip)
-- Pokazuje udzial poszczegolnych kanalow w liczbie i wartosci transakcji.
WITH clean_txn AS (
    SELECT
        COALESCE(NULLIF(TRIM(use_chip), ''), 'Unknown') AS channel_type,
        REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g')::numeric AS amt
    FROM public.transactions_data
    WHERE amount IS NOT NULL
      AND REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
)
SELECT
    channel_type,
    COUNT(*) AS txn_count,
    ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS txn_share_pct,
    ROUND(SUM(amt), 2) AS total_amount,
    ROUND(100.0 * SUM(amt) / NULLIF(SUM(SUM(amt)) OVER (), 0), 2) AS amount_share_pct,
    ROUND(AVG(amt), 2) AS avg_amount
FROM clean_txn
GROUP BY channel_type
ORDER BY total_amount DESC;

-- 2.3 Top kategorie MCC (z dolaczeniem slownika mcc_codes)
-- Laczy transakcje ze slownikiem kategorii, aby pokazac najwieksze obszary operacji.

WITH clean_txn AS (
    SELECT
        t.mcc,
        COALESCE(m.mcc_description, 'Brak opisu w slowniku MCC') AS mcc_category,
        REGEXP_REPLACE(t.amount, '[^0-9.-]', '', 'g')::numeric AS amt
    FROM public.transactions_data t
    LEFT JOIN public.mcc_codes m
        ON t.mcc = m.mcc
    WHERE t.amount IS NOT NULL
      AND REGEXP_REPLACE(t.amount, '[^0-9.-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
)
SELECT
    mcc,
    mcc_category,
    COUNT(*) AS txn_count,
    ROUND(SUM(amt), 2) AS total_amount,
    ROUND(AVG(amt), 2) AS avg_amount,
    ROUND(100.0 * SUM(amt) / NULLIF(SUM(SUM(amt)) OVER (), 0), 2) AS amount_share_pct
FROM clean_txn
GROUP BY mcc, mcc_category
ORDER BY total_amount DESC
LIMIT 20;


-- ============================================================================
-- SEKCJA 3: TRENDY W CZASIE ORAZ ANOMALIE I BLEDY
-- ============================================================================

-- 3.1 Trend miesieczny liczby i wartosci transakcji
-- Ulatwia wychwycenie sezonowosci, naglych skokow lub spadkow wolumenu w czasie.
WITH clean_txn AS (
    SELECT
        date::timestamp AS txn_ts,
        REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g')::numeric AS amt
    FROM public.transactions_data
    WHERE amount IS NOT NULL
      AND REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
)
SELECT
    DATE_TRUNC('month', txn_ts)::date AS month_start,
    COUNT(*) AS txn_count,
    ROUND(SUM(amt), 2) AS total_amount,
    ROUND(AVG(amt), 2) AS avg_amount
FROM clean_txn
GROUP BY 1
ORDER BY 1;

-- 3.2 Rozklad transakcji wedlug dni tygodnia
-- Pomaga ocenic tygodniowy rytm operacyjny (np. roznice miedzy dniami roboczymi a weekendem).
WITH clean_txn AS (
    SELECT
        date::timestamp AS txn_ts,
        REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g')::numeric AS amt
    FROM public.transactions_data
    WHERE amount IS NOT NULL
      AND REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
)
SELECT
    EXTRACT(ISODOW FROM txn_ts)::int AS day_of_week_num,
    TO_CHAR(txn_ts, 'Dy') AS day_name,
    COUNT(*) AS txn_count,
    ROUND(SUM(amt), 2) AS total_amount
FROM clean_txn
GROUP BY 1, 2
ORDER BY 1;

-- 3.3 Zestawienie bledow zapisanych w kolumnie errors
-- Pokazuje czestosc i wartosc transakcji oznaczonych komunikatem bledu.
WITH clean_txn AS (
    SELECT
        COALESCE(NULLIF(TRIM(errors), ''), 'No Error') AS error_status,
        REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g')::numeric AS amt
    FROM public.transactions_data
    WHERE amount IS NOT NULL
      AND REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
)
SELECT
    error_status,
    COUNT(*) AS txn_count,
    ROUND(SUM(amt), 2) AS total_amount
FROM clean_txn
GROUP BY 1
ORDER BY txn_count DESC;

-- 3.4 Podzial transakcji na zakres standardowy oraz nietypowe kwoty (ujemne, zerowe, wysokie)

WITH clean_txn AS (
    SELECT
        REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g')::numeric AS amt
    FROM public.transactions_data
    WHERE amount IS NOT NULL
      AND REGEXP_REPLACE(amount, '[^0-9.-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
)
SELECT
    CASE
        WHEN amt < 0 THEN 'Negative amount (refund/reversal)'
        WHEN amt = 0 THEN 'Zero amount'
        WHEN amt >= 5000 THEN 'High amount (>= 5000)'
        ELSE 'Normal range'
    END AS anomaly_flag,
    COUNT(*) AS txn_count,
    ROUND(SUM(amt), 2) AS total_amount,
    MIN(amt) AS min_amt,
    MAX(amt) AS max_amt
FROM clean_txn
GROUP BY 1
ORDER BY txn_count DESC;