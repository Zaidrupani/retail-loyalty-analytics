# Brief 3: Is own-label taking sales from branded?

## The client's question

"We have been pushing our own-label range. Is it taking sales from branded products, and in which categories? And when shoppers switch to own-label, do they end up spending more or less with us in that category?"

## What the client wants back

- Own-label's share of grocery spend in the early and late halves, overall and by category.
- The categories where own-label gained or lost the most share, with the price gap to branded.
- A deep dive into one category: how many households switched, in which direction, and what happened to their spend in that category.
- One recommendation.

## Scope

- Grocery spend only (non-merch excluded), weeks 18 to 101, split into the same halves as Brief 2: early (weeks 18 to 59) and late (weeks 60 to 101).
- Own-label = products with `brand = 'Private'` (15% of products). Branded = `brand = 'National'`.
- Categories are the product table's `commodity_desc` (308 in total).
- Money is in US dollars.

## Method, in plain words

1. **Scan every category.** For each one, work out own-label's share of spend in each half and how far it moved. Only categories with at least $10,000 of early spend, and where both own-label and branded have at least 10% of spend, are compared. Elsewhere one side is too small to switch to.
2. **Add context.** For each category, compare the average shelf price per unit of own-label and branded, and how much of branded spend was on loyalty discount in each half. A branded promotion pulling back is one reason shoppers might switch.
3. **Pick one category for a deep dive,** based on size, a real own-label presence and a clear change in share. Paper towels was chosen: the biggest gain (+8.1 points) and the clearest promotion change (branded spend on discount fell from 19% to 14%). The category is set in one line of the SQL, so the deep dive can be re-run for any other.
4. **Follow the households.** Among households that bought the category in both halves, find who moved towards own-label, who moved towards branded and who stayed put. Then compare how their total spend in the category changed.

## Known limitations

- **No margin data.** Own-label usually earns the retailer a higher margin, so lower sales can still mean more profit. This analysis can only measure sales.
- **Price per unit is rough.** A category mixes pack sizes, so "per unit" compares averages, not like-for-like products.
- **Switching is not proof of cause.** It shows that households changed what they bought, not why.

## Files

- SQL: `sql/06_brief3_own_label.sql`
- Tables built: `retail-loyalty.analysis.b3_*`
- One-page summary for the client: "Brief 3: Is Own-Label Taking Sales from Branded?" (export as `briefs/brief3_summary.md`)
