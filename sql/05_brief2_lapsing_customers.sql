-- 1. One row per household: spend in each half, trips, last week seen,

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b2_households` AS
WITH hh AS (
  SELECT
    household_key,
    SUM(IF(week_no BETWEEN 18 AND 59,  sales_value, 0))               AS early_spend,
    SUM(IF(week_no BETWEEN 60 AND 101, sales_value, 0))               AS late_spend,
    COUNT(DISTINCT IF(week_no BETWEEN 18 AND 59,  basket_id, NULL))   AS early_baskets,
    COUNT(DISTINCT IF(week_no BETWEEN 60 AND 101, basket_id, NULL))   AS late_baskets,
    MAX(week_no)                                                      AS last_week
  FROM `retail-loyalty.clean.transactions`
  WHERE NOT is_non_merch
    AND week_no BETWEEN 18 AND 101
  GROUP BY household_key
)
SELECT
  *,
  late_spend - early_spend AS spend_change,
  CASE
    WHEN early_spend = 0                THEN 'New or returning'
    WHEN early_baskets < 10             THEN 'Occasional'
    WHEN last_week < 90                 THEN 'Lapsed'
    WHEN late_spend < 0.7 * early_spend THEN 'Declining'
    WHEN late_spend > 1.3 * early_spend THEN 'Growing'
    ELSE 'Stable'
  END AS segment,
  CASE
    WHEN early_spend = 0                THEN 6
    WHEN early_baskets < 10             THEN 5
    WHEN last_week < 90                 THEN 1
    WHEN late_spend < 0.7 * early_spend THEN 2
    WHEN late_spend > 1.3 * early_spend THEN 4
    ELSE 3
  END AS segment_order,
  CASE
    WHEN early_baskets < 10 THEN '1 Light (under 10 trips)'
    WHEN early_baskets < 30 THEN '2 Medium (10 to 29 trips)'
    ELSE '3 Heavy (30+ trips)'
  END AS early_frequency
FROM hh;

-- 2. Spend per household per category, early and late

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b2_household_commodity` AS
SELECT
  household_key,
  department,
  commodity_desc,
  SUM(IF(week_no BETWEEN 18 AND 59,  sales_value, 0)) AS early_spend,
  SUM(IF(week_no BETWEEN 60 AND 101, sales_value, 0)) AS late_spend
FROM `retail-loyalty.clean.transactions`
WHERE NOT is_non_merch
  AND week_no BETWEEN 18 AND 101
GROUP BY household_key, department, commodity_desc;

-- 3. Where declining households cut back, by department, with stable

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b2_department_change` AS
WITH s AS (
  SELECT
    c.department,
    h.segment,
    SUM(c.early_spend) AS early_spend,
    SUM(c.late_spend)  AS late_spend
  FROM `retail-loyalty.analysis.b2_household_commodity` AS c
  JOIN `retail-loyalty.analysis.b2_households` AS h
    ON h.household_key = c.household_key
  WHERE h.segment IN ('Declining', 'Stable')
  GROUP BY c.department, h.segment
)
SELECT
  d.department,
  d.early_spend AS declining_early,
  d.late_spend  AS declining_late,
  ROUND(100 * SAFE_DIVIDE(d.late_spend - d.early_spend, d.early_spend), 1) AS declining_pct_change,
  ROUND(100 * SAFE_DIVIDE(d.late_spend - d.early_spend,
                          SUM(d.late_spend - d.early_spend) OVER ()), 1)   AS share_of_decline,
  ROUND(100 * SAFE_DIVIDE(st.late_spend - st.early_spend, st.early_spend), 1) AS stable_pct_change
FROM s AS d
LEFT JOIN s AS st
  ON st.department = d.department AND st.segment = 'Stable'
WHERE d.segment = 'Declining';

-- 4. Categories declining households stopped buying altogether

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b2_commodity_stop` AS
WITH g AS (
  SELECT
    c.department,
    c.commodity_desc,
    h.segment,
    COUNTIF(c.early_spend > 0)                      AS early_buyers,
    COUNTIF(c.early_spend > 0 AND c.late_spend = 0) AS stopped,
    SUM(c.early_spend)                              AS early_spend,
    SUM(c.late_spend)                               AS late_spend
  FROM `retail-loyalty.analysis.b2_household_commodity` AS c
  JOIN `retail-loyalty.analysis.b2_households` AS h
    ON h.household_key = c.household_key
  WHERE h.segment IN ('Declining', 'Stable')
  GROUP BY c.department, c.commodity_desc, h.segment
)
SELECT
  d.department,
  d.commodity_desc,
  d.early_buyers                                         AS declining_buyers,
  ROUND(100 * SAFE_DIVIDE(d.stopped, d.early_buyers), 1) AS declining_stop_rate,
  s.early_buyers                                         AS stable_buyers,
  ROUND(100 * SAFE_DIVIDE(s.stopped, s.early_buyers), 1) AS stable_stop_rate,
  ROUND(100 * SAFE_DIVIDE(d.stopped, d.early_buyers)
      - 100 * SAFE_DIVIDE(s.stopped, s.early_buyers), 1) AS stop_rate_gap,
  ROUND(d.late_spend - d.early_spend, 0)                 AS declining_spend_change
FROM g AS d
LEFT JOIN g AS s
  ON s.department = d.department
 AND s.commodity_desc = d.commodity_desc
 AND s.segment = 'Stable'
WHERE d.segment = 'Declining';

-- 5. Drift rate by household type (801 households with demographics,

CREATE OR REPLACE TABLE `retail-loyalty.analysis.b2_demographics` AS
WITH base AS (
  SELECT
    h.segment,
    d.age_desc,
    d.income_desc,
    d.hh_comp_desc,
    d.kid_category_desc
  FROM `retail-loyalty.analysis.b2_households` AS h
  JOIN `retail-loyalty.clean.households` AS d
    ON d.household_key = h.household_key
  WHERE d.has_demographics
    AND h.segment IN ('Lapsed', 'Declining', 'Stable', 'Growing')
),
long AS (
  SELECT '0 All' AS attribute, 'All regulars with demographics' AS value, segment FROM base
  UNION ALL SELECT '1 Age',       age_desc,          segment FROM base
  UNION ALL SELECT '2 Income',    income_desc,       segment FROM base
  UNION ALL SELECT '3 Household', hh_comp_desc,      segment FROM base
  UNION ALL SELECT '4 Children',  kid_category_desc, segment FROM base
)
SELECT
  attribute,
  value,
  COUNT(*) AS households,
  ROUND(100 * COUNTIF(segment IN ('Declining', 'Lapsed')) / COUNT(*), 1) AS pct_drifting,
  ROUND(100 * COUNTIF(segment = 'Growing') / COUNT(*), 1)                AS pct_growing
FROM long
GROUP BY attribute, value;

-- CHECKS

SELECT
  segment,
  COUNT(*)                                         AS households,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_households,
  ROUND(SUM(early_spend), 0)                       AS early_spend,
  ROUND(SUM(late_spend), 0)                        AS late_spend,
  ROUND(SUM(spend_change), 0)                      AS spend_change,
  ROUND(AVG(early_baskets), 1)                     AS avg_early_trips,
  ROUND(AVG(late_baskets), 1)                      AS avg_late_trips,
  ROUND(SAFE_DIVIDE(SUM(early_spend), SUM(early_baskets)), 2) AS early_spend_per_trip,
  ROUND(SAFE_DIVIDE(SUM(late_spend),  SUM(late_baskets)), 2)  AS late_spend_per_trip
FROM `retail-loyalty.analysis.b2_households`
GROUP BY segment, segment_order
ORDER BY segment_order;

-- B. Segments by how often households shopped in the early half
SELECT
  early_frequency,
  COUNTIF(segment = 'Lapsed')           AS lapsed,
  COUNTIF(segment = 'Declining')        AS declining,
  COUNTIF(segment = 'Stable')           AS stable,
  COUNTIF(segment = 'Growing')          AS growing,
  COUNTIF(segment = 'Occasional')       AS occasional,
  COUNTIF(segment = 'New or returning') AS new_or_returning,
  COUNT(*)                              AS households
FROM `retail-loyalty.analysis.b2_households`
GROUP BY early_frequency
ORDER BY early_frequency;

-- C. The whole base, early against late
SELECT
  COUNT(*)                   AS households_in_table,
  COUNTIF(early_spend > 0)   AS active_early,
  COUNTIF(late_spend > 0)    AS active_late,
  ROUND(SUM(early_spend), 0) AS total_early_spend,
  ROUND(SUM(late_spend), 0)  AS total_late_spend,
  ROUND(100 * (SUM(late_spend) - SUM(early_spend)) / SUM(early_spend), 1) AS pct_change
FROM `retail-loyalty.analysis.b2_households`;

-- D. Share of their usual categories each segment dropped
SELECT
  h.segment,
  COUNTIF(c.early_spend > 0) AS category_buys_early,
  ROUND(100 * COUNTIF(c.early_spend > 0 AND c.late_spend = 0)
            / COUNTIF(c.early_spend > 0), 1) AS pct_categories_dropped
FROM `retail-loyalty.analysis.b2_household_commodity` AS c
JOIN `retail-loyalty.analysis.b2_households` AS h
  ON h.household_key = c.household_key
WHERE h.segment IN ('Lapsed', 'Declining', 'Stable', 'Growing')
GROUP BY h.segment, h.segment_order
ORDER BY h.segment_order;

-- E. Departments where declining households cut most
SELECT
  department,
  ROUND(declining_early, 0) AS declining_early,
  ROUND(declining_late, 0)  AS declining_late,
  declining_pct_change,
  share_of_decline,
  stable_pct_change
FROM `retail-loyalty.analysis.b2_department_change`
WHERE declining_early >= 5000
ORDER BY share_of_decline DESC;

-- F. Categories declining households stopped buying (top 15)
SELECT
  department,
  commodity_desc,
  declining_buyers,
  declining_stop_rate,
  stable_buyers,
  stable_stop_rate,
  stop_rate_gap,
  declining_spend_change
FROM `retail-loyalty.analysis.b2_commodity_stop`
WHERE declining_buyers >= 50
ORDER BY stop_rate_gap DESC
LIMIT 15;

-- G. Drift rate by household type (ignore groups under ~30 households)
SELECT *
FROM `retail-loyalty.analysis.b2_demographics`
ORDER BY attribute, value;
