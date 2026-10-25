-- 1. Row counts per table

SELECT 'transaction_data' AS table_name, COUNT(*) AS row_count FROM `retail-loyalty.complete_journey.transaction_data`
UNION ALL SELECT 'hh_demographic', COUNT(*) FROM `retail-loyalty.complete_journey.hh_demographic`
UNION ALL SELECT 'product',        COUNT(*) FROM `retail-loyalty.complete_journey.product`
UNION ALL SELECT 'campaign_table', COUNT(*) FROM `retail-loyalty.complete_journey.campaign_table`
UNION ALL SELECT 'campaign_desc',  COUNT(*) FROM `retail-loyalty.complete_journey.campaign_desc`
UNION ALL SELECT 'coupon',         COUNT(*) FROM `retail-loyalty.complete_journey.coupon`
UNION ALL SELECT 'coupon_redempt', COUNT(*) FROM `retail-loyalty.complete_journey.coupon_redempt`
ORDER BY row_count DESC;

-- 2. Sanity check: did the columns load into the right places?

SELECT
  COUNT(DISTINCT household_key) AS households,
  COUNT(DISTINCT basket_id)     AS baskets,
  MIN(day)          AS min_day,
  MAX(day)          AS max_day,
  MIN(week_no)      AS min_week,
  MAX(week_no)      AS max_week,
  MIN(trans_time)   AS min_time,
  MAX(trans_time)   AS max_time,
  MIN(sales_value)  AS min_sales_value,
  MAX(sales_value)  AS max_sales_value,
  MIN(retail_disc)  AS min_retail_disc,
  MAX(retail_disc)  AS max_retail_disc
FROM `retail-loyalty.complete_journey.transaction_data`;
