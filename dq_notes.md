# Data quality notes: dunnhumby The Complete Journey

## Source

- Dataset: dunnhumby, *The Complete Journey* (via Kaggle)
- What it is: two years of loyalty card transactions from 2,500 households at one unnamed US grocery retailer, with campaign, coupon and partial demographic data
- Not included in this project: `causal_data` (in-store display and mailer data)
- Loaded into: BigQuery, project `retail-loyalty`, dataset `complete_journey`, using `01_load_to_bigquery.py`
- Raw tables are kept as an exact copy of the source. All fixes are applied in a separate cleaned layer (`03_clean.sql`), never in the raw data.

## Row counts

| Table | Rows |
|---|---|
| transaction_data | 2,595,732 |
| coupon | 124,548 |
| product | 92,353 |
| campaign_table | 7,208 |
| coupon_redempt | 2,318 |
| hh_demographic | 801 |
| campaign_desc | 30 |

Sanity check passed: day, week, time and discount ranges match the documented structure, so columns loaded in the correct order.

## Checks with no issues

| Check | Result |
|---|---|
| Q1 Missing values | 0 nulls in all 12 columns of `transaction_data` |
| Q2 Exact duplicates | 0 duplicate rows out of 2,595,732 |
| Q3 Basket integrity | 0 baskets linked to more than one household or day |
| Q6 Referential integrity | 0 orphan records: every product, campaign household and coupon redemption matches its parent table |

## Findings and decisions

| # | Check | Finding | Decision |
|---|---|---|---|
| 1 | Load / Q4 | The first load failed on 56 money values written in scientific notation (e.g. 5.551115E-17), which BigQuery's NUMERIC type rejected. Profiling found 63 non-zero values under half a penny in total: 29 in `sales_value`, 34 in `retail_disc`. These are floating-point noise from the source export, effectively zero. | Load money columns as FLOAT64 in raw. Round all money columns to 2 dp in the cleaned layer. |
| 2 | Q5b, V4 Non-product lines | Quantities up to 89,638 (99th percentile is 10). These come from `KIOSK-GAS` and `MISC SALES TRAN` departments: 20,261 rows of coupon/misc items, 2,868 misc sales rows and 6 fuel rows over 100 units. Reviewing the full department list (V4) found further non-product departments: `MISC. TRANS.` (2,351 rows), `COUP/STR & MFG` (817), `POSTAL CENTER` (20), `VIDEO RENTAL` (5) and `CHARITABLE CONT` (2). `COUPON/MISC ITEMS` lines also appear inside normal departments such as `GROCERY` (1,392 rows). | Flag all of these as `is_non_merch` in the cleaned layer. Exclude from product, category and basket analysis. |
| 3 | Q5 Zero rows | 14,466 rows have quantity 0 (67 of these have sales above zero). 4,451 rows have quantity above zero but sales of 0. No negative sales. | Keep all rows, as they do not distort spend. Exclude quantity-0 rows from unit counts. |
| 4 | Q5 Discount sign | Profiling counted 36 rows with a positive `retail_disc`, when discounts are stored as negative values. After rounding to 2 dp, only 10 remain: the other 26 were floating-point noise, not real errors. | Flag the 10 as `is_disc_sign_error`. Impact is negligible. |
| 5 | Q8 Panel ramp-up | Active households rise from 88 in week 1 to about 1,300 by week 16, then stay stable (roughly 1,250 to 1,430 a week). This reflects households joining the panel, not real growth. Week 102 is a partial week (1,205 households, 2,383 baskets). Week 92 has the highest sales (113,193), likely a holiday peak. | Use weeks 17 to 101 for any trend or spend-over-time analysis. Otherwise early growth would be mistaken for customers spending more. |
| 6 | Q9, V3, V4 Blank categories | 15 products have a blank department and commodity. They appear in 7,839 transaction rows, every one with 0 units and 0 sales, so they are placeholder lines rather than products. Two products account for 7,754 of these rows (5978656: 4,887 rows across 1,157 households; 5978648: 2,867 rows across 924 households). | Label as 'Unknown' and flag as `is_non_merch`. |
| 7 | Q10, V5 Campaign timing and reach | 30 campaigns (TypeA 5, TypeB 19, TypeC 6) run from day 224 to day 719. Campaign 24 ends 8 days after the data stops and campaign 15 has only 3 days of data after it ends. Six campaigns were sent to fewer than 50 households (27, 28, 1, 2, 3, 15). The three largest, all TypeA, reached over 1,000 households each: campaign 8 (1,076), 13 (1,077) and 18 (1,133). | In Brief 1, only measure campaigns with a full post-campaign window and enough reach to compare groups, and state which were excluded. |
| 8 | Q7 Coverage | 2,500 households. 801 (32.0%) have demographics. 1,584 (63.4%) were sent at least one campaign. | Demographic analysis is labelled as covering 801 households only. |

## Cleaned layer validation (`03_clean.sql`)

| Check | Result |
|---|---|
| V1 Rows | 2,595,732 raw and 2,595,732 clean: no rows lost. 2,500 households, 30 campaigns. |
| V2 Rounding | 0 noise values left. Total sales 8,057,463.08 in both raw and clean, so rounding changed no totals. |
| V3 Non-merch (first pass) | 29,637 rows (1.1%) flagged, worth 669,415.12 (8.3% of all sales). The department review (V4) widened the flag; see the second run below. |
| V3 Zero quantity | 14,466 rows flagged, matching profiling. |
| V3 Discount sign | 10 rows flagged (see finding 4). |
| V3 Trend window | 2,372,786 rows (91.4%) fall in weeks 17 to 101. |
| V3 Unknown department | The 15 blank products account for 7,839 transaction rows, all at zero sales (see finding 6). |
| V3 Non-merch (after review) | 40,671 rows (1.6%) flagged, worth 681,174.74 (8.5% of all sales). Grocery (merchandise) sales used in the briefs: 7,376,288.34. |

## Useful for the briefs

- **Brief 1 (campaign uplift):** 916 households (36.6%) were never sent a campaign, giving a natural comparison group. The first campaign starts on day 224, leaving about 32 weeks of pre-campaign history as a baseline.
- **Brief 2 (lapsing customers):** trend analysis must use weeks 17 to 101 (see finding 5).
- **Brief 3 (own-label):** 13,816 of 92,353 products (15.0%) are own-label ('Private'); 78,537 are national brands. 44 departments and 308 commodities.

## Known limitations

- Day and week are numbers, not calendar dates, so seasonality can only be read as week-of-period.
- The retailer and brand names are anonymised.
- The data is US grocery and several years old, so results show method rather than current UK behaviour.
