
-- Brief 1: did campaigns 8, 13 and 18 make households spend more?

-- 0. A separate dataset for analysis outputs

CREATE SCHEMA IF NOT EXISTS `retail-loyalty.analysis`
OPTIONS (location = 'EU');


-- 1. Windows: one row per test

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b1_campaign_windows` AS
SELECT
  CONCAT('Campaign ', CAST(campaign AS STRING)) AS test,
  campaign                      AS test_order,
  campaign,
  households_sent,
  length_days,
  start_day - length_days - 112 AS base_from,
  start_day - length_days - 1   AS base_to,
  start_day - length_days       AS pre_from,
  start_day - 1                 AS pre_to,
  start_day                     AS during_from,
  end_day                       AS during_to,
  end_day + 1                   AS post_from,
  end_day + length_days         AS post_to
FROM `retail-loyalty.clean.campaigns`
WHERE campaign IN (8, 13, 18)

UNION ALL

SELECT
  'Placebo (no campaign)', 99, 8, NULL, 37,
  113, 149, 150, 186, 187, 223, NULL, NULL;

-- 2. Households in each comparison

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b1_households` AS
WITH first_seen AS (
  SELECT household_key, MIN(day) AS first_day
  FROM `retail-loyalty.clean.transactions`
  GROUP BY household_key
),
targeted AS (
  SELECT w.test, ch.household_key, 'Targeted' AS grp
  FROM `retail-loyalty.analysis.b1_campaign_windows` AS w
  JOIN `retail-loyalty.clean.campaign_households` AS ch
    ON ch.campaign = w.campaign
),
control AS (
  SELECT w.test, h.household_key, 'Control' AS grp
  FROM `retail-loyalty.analysis.b1_campaign_windows` AS w
  CROSS JOIN `retail-loyalty.clean.households` AS h
  WHERE NOT h.sent_any_campaign
),
both_groups AS (
  SELECT * FROM targeted
  UNION ALL
  SELECT * FROM control
)
SELECT g.test, g.household_key, g.grp
FROM both_groups AS g
JOIN `retail-loyalty.analysis.b1_campaign_windows` AS w
  ON w.test = g.test
JOIN first_seen AS f
  ON f.household_key = g.household_key
WHERE f.first_day <= w.base_from;

-- 3. Spend per household in each window

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b1_household_change` AS
WITH spend AS (
  SELECT
    h.test,
    h.household_key,
    SUM(IF(t.day BETWEEN w.base_from   AND w.base_to,   t.sales_value, 0)) AS base_sales,
    SUM(IF(t.day BETWEEN w.pre_from    AND w.pre_to,    t.sales_value, 0)) AS pre_sales,
    SUM(IF(t.day BETWEEN w.during_from AND w.during_to, t.sales_value, 0)) AS during_sales,
    SUM(IF(t.day BETWEEN w.post_from   AND w.post_to,   t.sales_value, 0)) AS post_sales
  FROM `retail-loyalty.analysis.b1_households` AS h
  JOIN `retail-loyalty.analysis.b1_campaign_windows` AS w
    ON w.test = h.test
  JOIN `retail-loyalty.clean.transactions` AS t
    ON t.household_key = h.household_key
   AND t.day BETWEEN w.base_from AND COALESCE(w.post_to, w.during_to)
   AND NOT t.is_non_merch
  GROUP BY h.test, h.household_key
),
totals AS (
  SELECT
    h.test,
    h.household_key,
    h.grp,
    CAST(COALESCE(s.base_sales, 0)   AS FLOAT64) AS base_sales,
    CAST(COALESCE(s.pre_sales, 0)    AS FLOAT64) AS pre_sales,
    CAST(COALESCE(s.during_sales, 0) AS FLOAT64) AS during_sales,
    IF(w.post_to IS NULL, NULL,
       CAST(COALESCE(s.post_sales, 0) AS FLOAT64)) AS post_sales
  FROM `retail-loyalty.analysis.b1_households` AS h
  JOIN `retail-loyalty.analysis.b1_campaign_windows` AS w
    ON w.test = h.test
  LEFT JOIN spend AS s
    ON s.test = h.test AND s.household_key = h.household_key
)
SELECT
  *,
  during_sales - pre_sales AS change_during,
  post_sales - pre_sales   AS change_post,
  NTILE(5) OVER (PARTITION BY test ORDER BY pre_sales)  AS band_v1,
  NTILE(5) OVER (PARTITION BY test ORDER BY base_sales) AS band_v2
FROM totals;

-- 4. Uplift inside each band, for all three methods

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b1_uplift_by_band` AS
WITH stacked AS (
  SELECT test, grp, 'v0 No banding' AS method, 1 AS band,
         pre_sales, change_during, change_post
  FROM `retail-loyalty.analysis.b1_household_change`
  UNION ALL
  SELECT test, grp, 'v1 Banded on before-window', band_v1,
         pre_sales, change_during, change_post
  FROM `retail-loyalty.analysis.b1_household_change`
  UNION ALL
  SELECT test, grp, 'v2 Banded on 16-week baseline', band_v2,
         pre_sales, change_during, change_post
  FROM `retail-loyalty.analysis.b1_household_change`
),
cells AS (
  SELECT
    test, method, band, grp,
    COUNT(*)                AS n,
    AVG(pre_sales)          AS avg_pre,
    AVG(change_during)      AS avg_change_during,
    VAR_SAMP(change_during) AS var_change_during,
    AVG(change_post)        AS avg_change_post,
    VAR_SAMP(change_post)   AS var_change_post
  FROM stacked
  GROUP BY test, method, band, grp
)
SELECT
  t.test,
  t.method,
  t.band,
  t.n                                                   AS targeted_hh,
  COALESCE(c.n, 0)                                      AS control_hh,
  t.avg_pre                                             AS targeted_avg_pre,
  c.avg_pre                                             AS control_avg_pre,
  t.avg_change_during                                   AS targeted_change_during,
  c.avg_change_during                                   AS control_change_during,
  t.avg_change_during - c.avg_change_during             AS uplift_during,
  t.var_change_during / t.n + c.var_change_during / c.n AS var_uplift_during,
  t.avg_change_post - c.avg_change_post                 AS uplift_post,
  t.var_change_post / t.n + c.var_change_post / c.n     AS var_uplift_post,
  COALESCE(c.n, 0) >= 20                                AS usable
FROM cells AS t
LEFT JOIN cells AS c
  ON c.test = t.test
 AND c.method = t.method
 AND c.band = t.band
 AND c.grp = 'Control'
WHERE t.grp = 'Targeted';

-- 5. Summary: one row per test and method

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b1_summary` AS
WITH b AS (
  SELECT
    *,
    targeted_hh / SUM(targeted_hh) OVER (PARTITION BY test, method) AS w
  FROM `retail-loyalty.analysis.b1_uplift_by_band`
  WHERE usable
),
s AS (
  SELECT
    test,
    method,
    SUM(targeted_hh)                     AS targeted_hh_compared,
    SUM(w * uplift_during)               AS uplift_during,
    SQRT(SUM(w * w * var_uplift_during)) AS se_during,
    SUM(w * uplift_post)                 AS uplift_post,
    SQRT(SUM(w * w * var_uplift_post))   AS se_post
  FROM b
  GROUP BY test, method
)
SELECT
  s.test,
  s.method,
  win.test_order,
  win.households_sent,
  s.targeted_hh_compared,
  ROUND(s.uplift_during, 2)                          AS uplift_per_hh_during,
  ROUND(s.uplift_during - 1.96 * s.se_during, 2)     AS range_low_during,
  ROUND(s.uplift_during + 1.96 * s.se_during, 2)     AS range_high_during,
  ABS(s.uplift_during) > 1.96 * s.se_during          AS clear_effect_during,
  ROUND(s.uplift_during * s.targeted_hh_compared, 0) AS extra_sales_during,
  ROUND(s.uplift_post, 2)                            AS uplift_per_hh_post,
  ROUND(s.uplift_post - 1.96 * s.se_post, 2)         AS range_low_post,
  ROUND(s.uplift_post + 1.96 * s.se_post, 2)         AS range_high_post,
  ABS(s.uplift_post) > 1.96 * s.se_post              AS clear_effect_post
FROM s
JOIN `retail-loyalty.analysis.b1_campaign_windows` AS win
  ON win.test = s.test;

-- 6. Couponed products vs the rest of the basket, per household

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b1_coupon_change` AS
WITH products AS (
  SELECT DISTINCT campaign, product_id
  FROM `retail-loyalty.clean.coupon`
  WHERE campaign IN (8, 13, 18)
),
spend AS (
  SELECT
    h.test,
    h.household_key,
    SUM(IF(t.day BETWEEN w.pre_from    AND w.pre_to,    t.sales_value, 0)) AS pre_coupon,
    SUM(IF(t.day BETWEEN w.during_from AND w.during_to, t.sales_value, 0)) AS during_coupon,
    SUM(IF(t.day BETWEEN w.post_from   AND w.post_to,   t.sales_value, 0)) AS post_coupon
  FROM `retail-loyalty.analysis.b1_households` AS h
  JOIN `retail-loyalty.analysis.b1_campaign_windows` AS w
    ON w.test = h.test
  JOIN products AS p
    ON p.campaign = w.campaign
  JOIN `retail-loyalty.clean.transactions` AS t
    ON t.household_key = h.household_key
   AND t.product_id = p.product_id
   AND t.day BETWEEN w.pre_from AND COALESCE(w.post_to, w.during_to)
   AND NOT t.is_non_merch
  GROUP BY h.test, h.household_key
)
SELECT
  hc.test,
  hc.household_key,
  hc.grp,
  hc.band_v2,
  CAST(COALESCE(s.pre_coupon, 0)    AS FLOAT64) AS pre_coupon,
  CAST(COALESCE(s.during_coupon, 0) AS FLOAT64) AS during_coupon,
  IF(w.post_to IS NULL, NULL,
     CAST(COALESCE(s.post_coupon, 0) AS FLOAT64)) AS post_coupon,
  hc.pre_sales,
  hc.during_sales,
  hc.post_sales
FROM `retail-loyalty.analysis.b1_household_change` AS hc
JOIN `retail-loyalty.analysis.b1_campaign_windows` AS w
  ON w.test = hc.test
LEFT JOIN spend AS s
  ON s.test = hc.test AND s.household_key = hc.household_key;

-- 7. Uplift by band for couponed products and the rest of the basket

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b1_coupon_uplift_by_band` AS
WITH stacked AS (
  SELECT
    test, grp, band_v2 AS band,
    'Couponed products'            AS measure,
    pre_coupon                     AS pre,
    during_coupon - pre_coupon     AS change_during,
    post_coupon - pre_coupon       AS change_post
  FROM `retail-loyalty.analysis.b1_coupon_change`
  UNION ALL
  SELECT
    test, grp, band_v2,
    'Rest of basket',
    pre_sales - pre_coupon,
    (during_sales - during_coupon) - (pre_sales - pre_coupon),
    (post_sales - post_coupon)     - (pre_sales - pre_coupon)
  FROM `retail-loyalty.analysis.b1_coupon_change`
),
cells AS (
  SELECT
    test, measure, band, grp,
    COUNT(*)                AS n,
    AVG(pre)                AS avg_pre,
    AVG(change_during)      AS avg_change_during,
    VAR_SAMP(change_during) AS var_change_during,
    AVG(change_post)        AS avg_change_post,
    VAR_SAMP(change_post)   AS var_change_post
  FROM stacked
  GROUP BY test, measure, band, grp
)
SELECT
  t.test,
  t.measure,
  t.band,
  t.n                                                   AS targeted_hh,
  COALESCE(c.n, 0)                                      AS control_hh,
  t.avg_pre                                             AS targeted_avg_pre,
  c.avg_pre                                             AS control_avg_pre,
  t.avg_change_during - c.avg_change_during             AS uplift_during,
  t.var_change_during / t.n + c.var_change_during / c.n AS var_uplift_during,
  t.avg_change_post - c.avg_change_post                 AS uplift_post,
  t.var_change_post / t.n + c.var_change_post / c.n     AS var_uplift_post,
  COALESCE(c.n, 0) >= 20                                AS usable
FROM cells AS t
LEFT JOIN cells AS c
  ON c.test = t.test
 AND c.measure = t.measure
 AND c.band = t.band
 AND c.grp = 'Control'
WHERE t.grp = 'Targeted';

-- 8. Summary: one row per test and measure, with % uplift

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b1_coupon_summary` AS
WITH b AS (
  SELECT
    *,
    targeted_hh / SUM(targeted_hh) OVER (PARTITION BY test, measure) AS w
  FROM `retail-loyalty.analysis.b1_coupon_uplift_by_band`
  WHERE usable
),
s AS (
  SELECT
    test,
    measure,
    SUM(targeted_hh)                     AS targeted_hh_compared,
    SUM(w * targeted_avg_pre)            AS base_pre,
    SUM(w * uplift_during)               AS uplift_during,
    SQRT(SUM(w * w * var_uplift_during)) AS se_during,
    SUM(w * uplift_post)                 AS uplift_post,
    SQRT(SUM(w * w * var_uplift_post))   AS se_post
  FROM b
  GROUP BY test, measure
)
SELECT
  s.test,
  s.measure,
  win.test_order,
  s.targeted_hh_compared,
  ROUND(s.base_pre, 2)                                     AS targeted_spend_before,
  ROUND(s.uplift_during, 2)                                AS uplift_per_hh_during,
  ROUND(s.uplift_during - 1.96 * s.se_during, 2)           AS range_low_during,
  ROUND(s.uplift_during + 1.96 * s.se_during, 2)           AS range_high_during,
  ABS(s.uplift_during) > 1.96 * s.se_during                AS clear_effect_during,
  ROUND(100 * SAFE_DIVIDE(s.uplift_during, s.base_pre), 1) AS uplift_pct_during,
  ROUND(s.uplift_post, 2)                                  AS uplift_per_hh_post,
  ROUND(s.uplift_post - 1.96 * s.se_post, 2)               AS range_low_post,
  ROUND(s.uplift_post + 1.96 * s.se_post, 2)               AS range_high_post,
  ABS(s.uplift_post) > 1.96 * s.se_post                    AS clear_effect_post
FROM s
JOIN `retail-loyalty.analysis.b1_campaign_windows` AS win
  ON win.test = s.test;

-- CHECKS

-- C1. The naive answer: targeted vs control spend, before and during
WITH g AS (
  SELECT test, grp,
         AVG(pre_sales)    AS pre,
         AVG(during_sales) AS during
  FROM `retail-loyalty.analysis.b1_household_change`
  GROUP BY test, grp
)
SELECT
  t.test,
  ROUND(t.pre, 2)               AS targeted_pre,
  ROUND(t.during, 2)            AS targeted_during,
  ROUND(c.pre, 2)               AS control_pre,
  ROUND(c.during, 2)            AS control_during,
  ROUND(t.during - c.during, 2) AS naive_gap
FROM g AS t
JOIN g AS c
  ON c.test = t.test AND c.grp = 'Control'
WHERE t.grp = 'Targeted'
ORDER BY t.test;

-- C2. All methods side by side, including the placebo
SELECT
  test,
  method,
  targeted_hh_compared,
  uplift_per_hh_during,
  range_low_during,
  range_high_during,
  clear_effect_during,
  extra_sales_during,
  uplift_per_hh_post,
  range_low_post,
  range_high_post,
  clear_effect_post
FROM `retail-loyalty.analysis.b1_summary`
ORDER BY test_order, method;

-- C3. The final method's bands
SELECT
  u.test,
  u.band,
  u.targeted_hh,
  u.control_hh,
  ROUND(u.targeted_avg_pre, 2)       AS targeted_avg_pre,
  ROUND(u.control_avg_pre, 2)        AS control_avg_pre,
  ROUND(u.targeted_change_during, 2) AS targeted_change,
  ROUND(u.control_change_during, 2)  AS control_change,
  ROUND(u.uplift_during, 2)          AS uplift_during,
  u.usable
FROM `retail-loyalty.analysis.b1_uplift_by_band` AS u
JOIN `retail-loyalty.analysis.b1_campaign_windows` AS w
  ON w.test = u.test
WHERE u.method = 'v2 Banded on 16-week baseline'
ORDER BY w.test_order, u.band;

-- C4. Why redeemers alone mislead: their spend BEFORE the campaign
SELECT
  b.test,
  r.household_key IS NOT NULL   AS redeemed,
  COUNT(*)                      AS households,
  ROUND(AVG(b.pre_sales), 2)    AS avg_pre_spend,
  ROUND(AVG(b.during_sales), 2) AS avg_during_spend
FROM `retail-loyalty.analysis.b1_household_change` AS b
JOIN `retail-loyalty.analysis.b1_campaign_windows` AS w
  ON w.test = b.test
LEFT JOIN (
  SELECT DISTINCT campaign, household_key
  FROM `retail-loyalty.clean.coupon_redempt`
) AS r
  ON r.campaign = w.campaign AND r.household_key = b.household_key
WHERE b.grp = 'Targeted' AND w.test_order < 99
GROUP BY b.test, redeemed
ORDER BY b.test, redeemed;

-- C5. How many households got one, two or all three campaigns?
SELECT
  campaigns_received AS of_campaigns_8_13_18,
  COUNT(*)           AS households
FROM (
  SELECT household_key, COUNT(DISTINCT campaign) AS campaigns_received
  FROM `retail-loyalty.clean.campaign_households`
  WHERE campaign IN (8, 13, 18)
  GROUP BY household_key
)
GROUP BY campaigns_received
ORDER BY campaigns_received;

-- C6. What each campaign put coupons on
SELECT
  c.campaign,
  COUNT(DISTINCT c.coupon_upc)      AS coupons,
  COUNT(DISTINCT c.product_id)      AS products_on_coupon,
  APPROX_TOP_COUNT(p.department, 3) AS top_departments
FROM `retail-loyalty.clean.coupon` AS c
JOIN `retail-loyalty.clean.product` AS p
  ON p.product_id = c.product_id
WHERE c.campaign IN (8, 13, 18)
GROUP BY c.campaign
ORDER BY c.campaign;

-- C7. Couponed products vs the rest of the basket
SELECT
  test,
  measure,
  targeted_hh_compared,
  targeted_spend_before,
  uplift_per_hh_during,
  range_low_during,
  range_high_during,
  clear_effect_during,
  uplift_pct_during,
  uplift_per_hh_post,
  range_low_post,
  range_high_post,
  clear_effect_post
FROM `retail-loyalty.analysis.b1_coupon_summary`
ORDER BY test_order, measure;
