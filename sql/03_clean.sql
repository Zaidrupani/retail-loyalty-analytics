
-- Create the clean dataset
CREATE SCHEMA IF NOT EXISTS `retail-loyalty.clean`
OPTIONS (location = 'EU');

-- 1. Products

CREATE OR REPLACE TABLE `retail-loyalty.clean.product` AS
SELECT
  product_id,
  manufacturer,
  COALESCE(NULLIF(TRIM(department), ''), 'Unknown')         AS department,
  COALESCE(NULLIF(TRIM(commodity_desc), ''), 'Unknown')     AS commodity_desc,
  COALESCE(NULLIF(TRIM(sub_commodity_desc), ''), 'Unknown') AS sub_commodity_desc,
  brand,
  brand = 'Private'                                         AS is_own_label,
  NULLIF(TRIM(curr_size_of_product), '')                    AS curr_size_of_product,
  COALESCE(
    -- fuel, misc transactions, coupons and non-retail services
    TRIM(department) IN (
      'KIOSK-GAS', 'MISC SALES TRAN', 'MISC. TRANS.', 'COUP/STR & MFG',
      'POSTAL CENTER', 'CHARITABLE CONT', 'VIDEO RENTAL'
    )
    -- coupon and fuel lines sitting inside normal departments
    OR TRIM(commodity_desc) IN ('COUPON/MISC ITEMS', 'FUEL')
    -- blank department: zero-sales placeholder products
    OR NULLIF(TRIM(department), '') IS NULL,
    FALSE
  )                                                         AS is_non_merch
FROM `retail-loyalty.complete_journey.product`;

-- 2. Transactions

CREATE OR REPLACE TABLE `retail-loyalty.clean.transactions`
CLUSTER BY household_key, product_id
AS
SELECT
  t.household_key,
  t.basket_id,
  t.day,
  t.week_no,
  t.trans_time,
  t.store_id,
  t.product_id,
  p.department,
  p.commodity_desc,
  p.sub_commodity_desc,
  p.brand,
  p.is_own_label,
  t.quantity,
  CAST(ROUND(t.sales_value, 2)       AS NUMERIC) AS sales_value,
  CAST(ROUND(t.retail_disc, 2)       AS NUMERIC) AS retail_disc,
  CAST(ROUND(t.coupon_disc, 2)       AS NUMERIC) AS coupon_disc,
  CAST(ROUND(t.coupon_match_disc, 2) AS NUMERIC) AS coupon_match_disc,
  COALESCE(p.is_non_merch, FALSE)                AS is_non_merch,
  t.quantity = 0                                 AS is_zero_qty,
  ROUND(t.retail_disc, 2) > 0                    AS is_disc_sign_error,
  t.week_no BETWEEN 17 AND 101                   AS in_trend_window
FROM `retail-loyalty.complete_journey.transaction_data` AS t
LEFT JOIN `retail-loyalty.clean.product` AS p
  ON t.product_id = p.product_id;

-- 3. Households: one row per household

CREATE OR REPLACE TABLE `retail-loyalty.clean.households` AS
WITH activity AS (
  SELECT
    household_key,
    MIN(week_no)              AS first_week,
    MAX(week_no)              AS last_week,
    COUNT(DISTINCT basket_id) AS baskets,
    SUM(sales_value)          AS total_sales
  FROM `retail-loyalty.clean.transactions`
  GROUP BY household_key
),
campaigns AS (
  SELECT
    household_key,
    COUNT(DISTINCT campaign) AS campaigns_received
  FROM `retail-loyalty.complete_journey.campaign_table`
  GROUP BY household_key
)
SELECT
  a.household_key,
  a.first_week,
  a.last_week,
  a.baskets,
  a.total_sales,
  d.household_key IS NOT NULL         AS has_demographics,
  d.age_desc,
  d.marital_status_code,
  d.income_desc,
  d.homeowner_desc,
  d.hh_comp_desc,
  d.household_size_desc,
  d.kid_category_desc,
  COALESCE(c.campaigns_received, 0)   AS campaigns_received,
  c.household_key IS NOT NULL         AS sent_any_campaign
FROM activity AS a
LEFT JOIN `retail-loyalty.complete_journey.hh_demographic` AS d
  ON a.household_key = d.household_key
LEFT JOIN campaigns AS c
  ON a.household_key = c.household_key;

-- 4. Campaigns: one row per campaign

CREATE OR REPLACE TABLE `retail-loyalty.clean.campaigns` AS
WITH last_day AS (
  SELECT MAX(day) AS max_day
  FROM `retail-loyalty.complete_journey.transaction_data`
),
sent AS (
  SELECT campaign, COUNT(DISTINCT household_key) AS households_sent
  FROM `retail-loyalty.complete_journey.campaign_table`
  GROUP BY campaign
),
redeemed AS (
  SELECT
    campaign,
    COUNT(*)                      AS redemptions,
    COUNT(DISTINCT household_key) AS households_redeemed
  FROM `retail-loyalty.complete_journey.coupon_redempt`
  GROUP BY campaign
)
SELECT
  d.campaign,
  d.description                        AS campaign_type,
  d.start_day,
  d.end_day,
  d.end_day - d.start_day + 1          AS length_days,
  COALESCE(s.households_sent, 0)       AS households_sent,
  COALESCE(r.redemptions, 0)           AS redemptions,
  COALESCE(r.households_redeemed, 0)   AS households_redeemed,
  l.max_day - d.end_day                AS days_of_data_after_end
FROM `retail-loyalty.complete_journey.campaign_desc` AS d
CROSS JOIN last_day AS l
LEFT JOIN sent AS s     ON d.campaign = s.campaign
LEFT JOIN redeemed AS r ON d.campaign = r.campaign;

-- 5. Tables that passed profiling unchanged: exposed as views, so

CREATE OR REPLACE VIEW `retail-loyalty.clean.campaign_households` AS
SELECT household_key, campaign, description AS campaign_type
FROM `retail-loyalty.complete_journey.campaign_table`;

CREATE OR REPLACE VIEW `retail-loyalty.clean.coupon` AS
SELECT coupon_upc, product_id, campaign
FROM `retail-loyalty.complete_journey.coupon`;

CREATE OR REPLACE VIEW `retail-loyalty.clean.coupon_redempt` AS
SELECT household_key, day, coupon_upc, campaign
FROM `retail-loyalty.complete_journey.coupon_redempt`;

-- VALIDATION: check the cleaned layer before using it

SELECT
  (SELECT COUNT(*) FROM `retail-loyalty.complete_journey.transaction_data`) AS raw_rows,
  (SELECT COUNT(*) FROM `retail-loyalty.clean.transactions`)               AS clean_rows,
  (SELECT COUNT(*) FROM `retail-loyalty.clean.households`)                 AS households,
  (SELECT COUNT(*) FROM `retail-loyalty.clean.campaigns`)                  AS campaigns;

-- V2. Rounding worked: no noise left, and total sales barely changed
SELECT
  (SELECT COUNTIF(sales_value != 0 AND ABS(sales_value) < 0.005)
   FROM `retail-loyalty.clean.transactions`)                               AS noise_left,
  (SELECT ROUND(SUM(sales_value), 2)
   FROM `retail-loyalty.complete_journey.transaction_data`)                AS raw_total_sales,
  (SELECT SUM(sales_value)
   FROM `retail-loyalty.clean.transactions`)                               AS clean_total_sales;

-- V3. Flag counts, to record in dq_notes.md
SELECT
  COUNTIF(is_non_merch)                   AS non_merch_rows,
  ROUND(SUM(IF(is_non_merch, sales_value, 0)), 2) AS non_merch_sales,
  COUNTIF(is_zero_qty)                    AS zero_qty_rows,
  COUNTIF(is_disc_sign_error)             AS disc_sign_error_rows,
  COUNTIF(in_trend_window)                AS rows_in_trend_window,
  COUNTIF(department = 'Unknown')         AS unknown_department_rows
FROM `retail-loyalty.clean.transactions`;

-- V4. Department review: are there other non-product departments

SELECT
  department,
  is_non_merch,
  COUNT(*)                 AS rows_sold,
  ROUND(SUM(sales_value), 2) AS sales
FROM `retail-loyalty.clean.transactions`
GROUP BY department, is_non_merch
ORDER BY rows_sold DESC;

-- V5. Campaigns and how much data follows each one

SELECT *
FROM `retail-loyalty.clean.campaigns`
ORDER BY start_day;
