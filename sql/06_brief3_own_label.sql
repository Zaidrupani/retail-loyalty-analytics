-- Brief 3: is own-label taking sales from branded, and where?

-- 1. Spend, units, shelf value and loyalty discount by category,

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b3_commodity_brand` AS
SELECT
  department,
  commodity_desc,
  brand,
  IF(week_no BETWEEN 18 AND 59, 'Early', 'Late')            AS half,
  SUM(sales_value)                                          AS spend,
  SUM(IF(quantity > 0, quantity, 0))                        AS units,
  SUM(sales_value - retail_disc - coupon_match_disc)        AS shelf_value,
  -SUM(retail_disc)                                         AS loyalty_discount,
  COUNT(DISTINCT household_key)                             AS buyers
FROM `retail-loyalty.clean.transactions`
WHERE NOT is_non_merch
  AND week_no BETWEEN 18 AND 101
  AND brand IN ('Private', 'National')
GROUP BY department, commodity_desc, brand, half;

-- 2. One row per category: own-label share in each half, the change,

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b3_category_scan` AS
WITH p AS (
  SELECT
    department,
    commodity_desc,
    SUM(IF(half = 'Early', spend, 0))                                  AS early_spend,
    SUM(IF(half = 'Late',  spend, 0))                                  AS late_spend,
    SUM(IF(half = 'Early' AND brand = 'Private',  spend, 0))           AS early_pl,
    SUM(IF(half = 'Late'  AND brand = 'Private',  spend, 0))           AS late_pl,
    SUM(IF(half = 'Early' AND brand = 'Private',  shelf_value, 0))     AS early_pl_shelf,
    SUM(IF(half = 'Early' AND brand = 'Private',  units, 0))           AS early_pl_units,
    SUM(IF(half = 'Early' AND brand = 'National', shelf_value, 0))     AS early_nat_shelf,
    SUM(IF(half = 'Early' AND brand = 'National', units, 0))           AS early_nat_units,
    SUM(IF(half = 'Late'  AND brand = 'National', shelf_value, 0))     AS late_nat_shelf,
    SUM(IF(half = 'Early' AND brand = 'National', loyalty_discount, 0)) AS early_nat_disc,
    SUM(IF(half = 'Late'  AND brand = 'National', loyalty_discount, 0)) AS late_nat_disc
  FROM `retail-loyalty.analysis.b3_commodity_brand`
  GROUP BY department, commodity_desc
)
SELECT
  department,
  commodity_desc,
  early_spend,
  late_spend,
  ROUND(100 * SAFE_DIVIDE(early_pl, early_spend), 1) AS early_own_label_pct,
  ROUND(100 * SAFE_DIVIDE(late_pl,  late_spend),  1) AS late_own_label_pct,
  ROUND(100 * SAFE_DIVIDE(late_pl,  late_spend)
      - 100 * SAFE_DIVIDE(early_pl, early_spend), 1) AS own_label_pp_change,
  ROUND(100 * (SAFE_DIVIDE(SAFE_DIVIDE(early_pl_shelf,  early_pl_units),
                           SAFE_DIVIDE(early_nat_shelf, early_nat_units)) - 1), 1)
                                                     AS own_label_price_gap_pct,
  ROUND(100 * SAFE_DIVIDE(early_nat_disc, early_nat_shelf), 1) AS branded_on_discount_pct_early,
  ROUND(100 * SAFE_DIVIDE(late_nat_disc,  late_nat_shelf),  1) AS branded_on_discount_pct_late
FROM p;

-- 3. Deep dive: one row per household that bought the chosen category

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b3_deepdive_households` AS
WITH params AS (
  SELECT 'PAPER TOWELS' AS category
),
hh AS (
  SELECT
    t.household_key,
    SUM(IF(t.week_no BETWEEN 18 AND 59,  t.sales_value, 0))                         AS early_spend,
    SUM(IF(t.week_no BETWEEN 60 AND 101, t.sales_value, 0))                         AS late_spend,
    SUM(IF(t.week_no BETWEEN 18 AND 59  AND t.brand = 'Private', t.sales_value, 0)) AS early_pl,
    SUM(IF(t.week_no BETWEEN 60 AND 101 AND t.brand = 'Private', t.sales_value, 0)) AS late_pl,
    SUM(IF(t.week_no BETWEEN 18 AND 59  AND t.quantity > 0, t.quantity, 0))         AS early_units,
    SUM(IF(t.week_no BETWEEN 60 AND 101 AND t.quantity > 0, t.quantity, 0))         AS late_units
  FROM `retail-loyalty.clean.transactions` AS t
  CROSS JOIN params AS p
  WHERE t.commodity_desc = p.category
    AND NOT t.is_non_merch
    AND t.week_no BETWEEN 18 AND 101
    AND t.brand IN ('Private', 'National')
  GROUP BY t.household_key
),
shares AS (
  SELECT
    *,
    SAFE_DIVIDE(early_pl, early_spend) AS early_pl_share,
    SAFE_DIVIDE(late_pl,  late_spend)  AS late_pl_share
  FROM hh
)
SELECT
  *,
  CASE
    WHEN early_spend = 0                         THEN 'Started buying'
    WHEN late_spend = 0                          THEN 'Stopped buying'
    WHEN late_pl_share - early_pl_share >= 0.2   THEN 'Moved to own-label'
    WHEN late_pl_share - early_pl_share <= -0.2  THEN 'Moved to branded'
    ELSE 'No real change'
  END AS switch_group,
  CASE
    WHEN early_spend = 0                         THEN 5
    WHEN late_spend = 0                          THEN 4
    WHEN late_pl_share - early_pl_share >= 0.2   THEN 1
    WHEN late_pl_share - early_pl_share <= -0.2  THEN 2
    ELSE 3
  END AS switch_order
FROM shares;

-- CHECKS

-- A. Own-label share of all grocery spend, early and late
SELECT
  half,
  ROUND(SUM(spend), 0)                                                  AS grocery_spend,
  ROUND(SUM(IF(brand = 'Private', spend, 0)), 0)                        AS own_label_spend,
  ROUND(100 * SUM(IF(brand = 'Private', spend, 0)) / SUM(spend), 1)     AS own_label_pct
FROM `retail-loyalty.analysis.b3_commodity_brand`
GROUP BY half
ORDER BY half;

-- B. Categories where own-label GAINED most share (top 12)
SELECT
  department,
  commodity_desc,
  ROUND(early_spend, 0) AS early_spend,
  early_own_label_pct,
  late_own_label_pct,
  own_label_pp_change,
  own_label_price_gap_pct,
  branded_on_discount_pct_early,
  branded_on_discount_pct_late
FROM `retail-loyalty.analysis.b3_category_scan`
WHERE early_spend >= 10000
  AND early_own_label_pct BETWEEN 10 AND 90
ORDER BY own_label_pp_change DESC
LIMIT 12;

-- C. Categories where own-label LOST most share (top 8)
SELECT
  department,
  commodity_desc,
  ROUND(early_spend, 0) AS early_spend,
  early_own_label_pct,
  late_own_label_pct,
  own_label_pp_change,
  own_label_price_gap_pct,
  branded_on_discount_pct_early,
  branded_on_discount_pct_late
FROM `retail-loyalty.analysis.b3_category_scan`
WHERE early_spend >= 10000
  AND early_own_label_pct BETWEEN 10 AND 90
ORDER BY own_label_pp_change ASC
LIMIT 8;

-- D. How many categories qualify, and the typical change
SELECT
  COUNT(*)                                  AS categories_compared,
  COUNTIF(own_label_pp_change > 0)          AS own_label_gained,
  COUNTIF(own_label_pp_change < 0)          AS own_label_lost,
  ROUND(AVG(own_label_pp_change), 1)        AS avg_pp_change,
  ROUND(AVG(own_label_price_gap_pct), 1)    AS avg_price_gap_pct
FROM `retail-loyalty.analysis.b3_category_scan`
WHERE early_spend >= 10000
  AND early_own_label_pct BETWEEN 10 AND 90;

-- E. Across qualifying categories: does branded promotion explain

  COUNT(*) AS categories,
  ROUND(CORR(CAST(own_label_pp_change AS FLOAT64),
             CAST(branded_on_discount_pct_late - branded_on_discount_pct_early AS FLOAT64)), 2) AS correlation,
  COUNTIF(branded_on_discount_pct_late < branded_on_discount_pct_early) AS categories_branded_promo_fell,
  ROUND(AVG(IF(branded_on_discount_pct_late < branded_on_discount_pct_early,
               own_label_pp_change, NULL)), 2)                         AS avg_own_label_change_when_fell,
  COUNTIF(branded_on_discount_pct_late > branded_on_discount_pct_early) AS categories_branded_promo_rose,
  ROUND(AVG(IF(branded_on_discount_pct_late > branded_on_discount_pct_early,
               own_label_pp_change, NULL)), 2)                         AS avg_own_label_change_when_rose
FROM `retail-loyalty.analysis.b3_category_scan`
WHERE early_spend >= 10000
  AND early_own_label_pct BETWEEN 10 AND 90;

-- F. Deep dive: who switched and what happened to their spend
SELECT
  switch_group,
  COUNT(*)                                          AS households,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_households,
  ROUND(100 * AVG(early_pl_share), 1)               AS avg_own_label_pct_early,
  ROUND(100 * AVG(late_pl_share), 1)                AS avg_own_label_pct_late,
  ROUND(SUM(early_spend), 0)                        AS early_spend,
  ROUND(SUM(late_spend), 0)                         AS late_spend,
  ROUND(100 * SAFE_DIVIDE(SUM(late_spend) - SUM(early_spend), SUM(early_spend)), 1) AS pct_spend_change,
  SUM(early_units)                                  AS early_units,
  SUM(late_units)                                   AS late_units,
  ROUND(100 * SAFE_DIVIDE(SUM(late_units) - SUM(early_units), SUM(early_units)), 1) AS pct_unit_change
FROM `retail-loyalty.analysis.b3_deepdive_households`
GROUP BY switch_group, switch_order
ORDER BY switch_order;
