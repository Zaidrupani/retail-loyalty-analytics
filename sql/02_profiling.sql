
-- 02_profiling.sql

-- Q1. Missing values in the main table

SELECT
  COUNT(*)                          AS total_rows,
  COUNTIF(household_key IS NULL)    AS null_household,
  COUNTIF(basket_id IS NULL)        AS null_basket,
  COUNTIF(day IS NULL)              AS null_day,
  COUNTIF(product_id IS NULL)       AS null_product,
  COUNTIF(quantity IS NULL)         AS null_quantity,
  COUNTIF(sales_value IS NULL)      AS null_sales_value,
  COUNTIF(store_id IS NULL)         AS null_store,
  COUNTIF(retail_disc IS NULL)      AS null_retail_disc,
  COUNTIF(trans_time IS NULL)       AS null_trans_time,
  COUNTIF(week_no IS NULL)          AS null_week_no,
  COUNTIF(coupon_disc IS NULL)      AS null_coupon_disc,
  COUNTIF(coupon_match_disc IS NULL) AS null_coupon_match_disc
FROM `retail-loyalty.complete_journey.transaction_data`;

-- Q2. Exact duplicate rows in the main table

SELECT
  COUNT(*)                                   AS total_rows,
  COUNT(DISTINCT TO_JSON_STRING(t))          AS distinct_rows,
  COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(t)) AS exact_duplicates
FROM `retail-loyalty.complete_journey.transaction_data` AS t;

-- Q3. Does each basket belong to one household on one day?

SELECT COUNT(*) AS baskets_with_conflicts
FROM (
  SELECT basket_id
  FROM `retail-loyalty.complete_journey.transaction_data`
  GROUP BY basket_id
  HAVING COUNT(DISTINCT household_key) > 1
      OR COUNT(DISTINCT day) > 1
);

-- Q4. Floating-point noise in the money columns

SELECT
  COUNTIF(sales_value != 0       AND ABS(sales_value) < 0.005)       AS noise_sales_value,
  COUNTIF(retail_disc != 0       AND ABS(retail_disc) < 0.005)       AS noise_retail_disc,
  COUNTIF(coupon_disc != 0       AND ABS(coupon_disc) < 0.005)       AS noise_coupon_disc,
  COUNTIF(coupon_match_disc != 0 AND ABS(coupon_match_disc) < 0.005) AS noise_coupon_match_disc
FROM `retail-loyalty.complete_journey.transaction_data`;

-- Q5. Odd quantity and sales combinations

SELECT
  COUNTIF(quantity = 0)                        AS qty_zero,
  COUNTIF(quantity = 0 AND sales_value > 0)    AS qty_zero_but_sales,
  COUNTIF(quantity > 0 AND sales_value = 0)    AS sales_zero_but_qty,
  COUNTIF(sales_value < 0)                     AS negative_sales,
  COUNTIF(retail_disc > 0)                     AS positive_retail_disc,
  MAX(quantity)                                AS max_quantity,
  APPROX_QUANTILES(quantity, 100)[OFFSET(99)]  AS p99_quantity
FROM `retail-loyalty.complete_journey.transaction_data`;

-- Q5b. Which products have the biggest quantities?

SELECT
  p.department,
  p.commodity_desc,
  COUNT(*)        AS rows_over_100,
  MAX(t.quantity) AS max_quantity
FROM `retail-loyalty.complete_journey.transaction_data` AS t
LEFT JOIN `retail-loyalty.complete_journey.product` AS p
  USING (product_id)
WHERE t.quantity > 100
GROUP BY p.department, p.commodity_desc
ORDER BY rows_over_100 DESC
LIMIT 10;

-- Q6. Do the tables join up? (referential integrity)

SELECT
  -- products sold that are missing from the product table
  (SELECT COUNT(DISTINCT t.product_id)
   FROM `retail-loyalty.complete_journey.transaction_data` AS t
   LEFT JOIN `retail-loyalty.complete_journey.product` AS p USING (product_id)
   WHERE p.product_id IS NULL)                                   AS products_not_in_product_table,

  -- households sent a campaign who never appear in transactions
  (SELECT COUNT(DISTINCT c.household_key)
   FROM `retail-loyalty.complete_journey.campaign_table` AS c
   LEFT JOIN (SELECT DISTINCT household_key
              FROM `retail-loyalty.complete_journey.transaction_data`) AS t
     USING (household_key)
   WHERE t.household_key IS NULL)                                AS campaign_households_no_transactions,

  -- redemptions whose coupon is not in the coupon table
  (SELECT COUNT(*)
   FROM `retail-loyalty.complete_journey.coupon_redempt` AS r
   LEFT JOIN (SELECT DISTINCT coupon_upc, campaign
              FROM `retail-loyalty.complete_journey.coupon`) AS c
     USING (coupon_upc, campaign)
   WHERE c.coupon_upc IS NULL)                                   AS redemptions_unknown_coupon,

  -- redemptions by households never sent that campaign
  (SELECT COUNT(*)
   FROM `retail-loyalty.complete_journey.coupon_redempt` AS r
   LEFT JOIN `retail-loyalty.complete_journey.campaign_table` AS c
     USING (household_key, campaign)
   WHERE c.household_key IS NULL)                                AS redemptions_campaign_not_received;

-- Q7. Coverage: how many households have demographics and campaigns?

WITH households AS (
  SELECT DISTINCT household_key
  FROM `retail-loyalty.complete_journey.transaction_data`
)
SELECT
  COUNT(*)                                         AS households_with_transactions,
  COUNTIF(d.household_key IS NOT NULL)             AS with_demographics,
  ROUND(100 * COUNTIF(d.household_key IS NOT NULL) / COUNT(*), 1) AS pct_with_demographics,
  COUNTIF(c.household_key IS NOT NULL)             AS sent_any_campaign,
  ROUND(100 * COUNTIF(c.household_key IS NOT NULL) / COUNT(*), 1) AS pct_sent_campaign
FROM households AS h
LEFT JOIN `retail-loyalty.complete_journey.hh_demographic` AS d USING (household_key)
LEFT JOIN (SELECT DISTINCT household_key
           FROM `retail-loyalty.complete_journey.campaign_table`) AS c USING (household_key);

-- Q8. Activity by week

SELECT
  week_no,
  COUNT(DISTINCT household_key) AS active_households,
  COUNT(DISTINCT basket_id)     AS baskets,
  ROUND(SUM(sales_value), 2)    AS sales
FROM `retail-loyalty.complete_journey.transaction_data`
GROUP BY week_no
ORDER BY week_no;

-- Q9. Product table: brand split and blank departments

SELECT
  brand,
  COUNT(*) AS products
FROM `retail-loyalty.complete_journey.product`
GROUP BY brand
ORDER BY products DESC;

SELECT
  COUNT(*)                                             AS products,
  COUNTIF(department IS NULL OR TRIM(department) = '') AS blank_department,
  COUNTIF(commodity_desc IS NULL OR TRIM(commodity_desc) = '') AS blank_commodity,
  COUNT(DISTINCT department)                           AS departments,
  COUNT(DISTINCT commodity_desc)                       AS commodities
FROM `retail-loyalty.complete_journey.product`;

-- Q10. Campaigns: types, counts and length

SELECT
  d.description                              AS campaign_type,
  COUNT(DISTINCT d.campaign)                 AS campaigns,
  ROUND(AVG(d.end_day - d.start_day + 1), 0) AS avg_length_days,
  MIN(d.start_day)                           AS first_start_day,
  MAX(d.end_day)                             AS last_end_day
FROM `retail-loyalty.complete_journey.campaign_desc` AS d
GROUP BY d.description
ORDER BY d.description;
