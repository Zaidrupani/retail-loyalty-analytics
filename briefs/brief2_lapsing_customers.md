# Brief 2: Which customers are we losing?

## The client's question

"Our loyalty base looks steady week to week, but we suspect some regular customers are drifting away. Who are we losing, how much is it costing us, and what are they buying less of before they go?"

## What the client wants back

- How many households are lapsed, declining, stable or growing, and how much spend each group gained or lost.
- What declining households have cut back on, by department and category.
- Which kinds of households are most likely to be declining.
- One recommendation for the loyalty team.

## Scope

- All 2,500 households, grocery spend only (non-merch excluded).
- Weeks 18 to 101, split into two equal halves of 42 weeks: **early** (weeks 18 to 59) and **late** (weeks 60 to 101). Weeks 1 to 16 are left out because households were still joining the panel (finding 5 in `docs/dq_notes.md`). Week 17 is dropped so the halves are equal. Each half contains one holiday peak.
- Demographics cover 801 households only, so that part is labelled as a subset.
- Money is in US dollars.

## Segments

| Segment | Rule |
|---|---|
| Occasional | Fewer than 10 trips in the early half: too few to call a trend either way |
| Lapsed | Shopped regularly in the early half, but no purchase in the last 12 weeks (weeks 90 to 101) |
| Declining | Still shopping, but late-half spend is under 70% of early-half spend |
| Stable | Late-half spend between 70% and 130% of early-half spend |
| Growing | Late-half spend over 130% of early-half spend |
| New or returning | No spend in the early half, some in the late half |

The 12-week and 30% thresholds are judgement calls. The segment sizes are checked before any further analysis.

The Occasional segment was added after the first check. Half the households first marked "lapsed" (91 of 178), and 224 of the 825 marked "growing", had shopped fewer than 10 times in the early half. For them, a swing from 5 trips to 9 is noise, not a trend, so the other segments now describe regular customers only.

## Method, in plain words

1. Work out each household's spend in the early and late halves, and when they last shopped.
2. Place each household in a segment using the rules above.
3. For declining households, find what they cut back on: the spend lost by department, and the categories they stopped buying altogether, compared with stable households.
4. For the 801 households with demographics, compare how often each type of household is declining or lapsed.

## Known limitations

- **Leaving the panel looks the same as lapsing.** A household that stopped using its loyalty card, moved away or left the study cannot be told apart from one that switched to a competitor.
- **Some movement is noise.** A household with one unusually big early half can look "declining" without any real change. Light shoppers are most affected.
- **This describes, it does not explain.** It shows who is drifting and what they buy less of, not why.
- **The demographic subset is not typical.** The 785 regular households with demographics drift less than regulars overall (15% against 26%), so drift rates by household type are a guide, not a precise figure.

## Files

- SQL: `sql/05_brief2_lapsing_customers.sql`
- Tables built: `retail-loyalty.analysis.b2_*`
- One-page summary for the client: "Brief 2: Which Customers Are We Losing?" (export as `briefs/brief2_summary.md`)
