# Brief 1: Did our coupon campaigns actually work?

## The client's question

"We sent three large mailed coupon campaigns (campaigns 8, 13 and 18, all TypeA), each to about 1,100 loyalty card households. Redemptions looked healthy. But did the campaigns make customers spend more than they would have anyway? If so, by how much?"

## What the client wants back

- Extra spend per targeted household during each campaign, with a range showing how sure we are.
- Total extra spend per campaign.
- Whether the effect lasted after the campaign ended.
- One recommendation for the next campaign.

## Scope

- Campaigns 8, 13 and 18 only. They are the only campaigns with enough households (over 1,000 each) and enough data afterwards (69 days or more). See finding 7 in `docs/dq_notes.md`.
- Grocery spend only. Fuel, coupons and other non-product lines are excluded (`is_non_merch`).
- Money is in US dollars, as the retailer is American.

## Method, in plain words

1. **Measure everyone who was sent the campaign, not just those who redeemed.** Redeemers tend to be heavy shoppers who would have spent the money anyway. Counting only them makes any campaign look good.
2. **Use a comparison group.** 916 households were never sent any campaign. They show what happens to spend when nobody gets a coupon, for example seasonal swings.
3. **Compare before with during.** For each campaign, take a window of the same length just before it starts. Uplift = the change in spend for targeted households, minus the change for the comparison group. This is called difference-in-differences.
4. **Compare like with like.** Campaigns went to heavier shoppers, so the two groups start at different levels. Households are split into five bands by their spend over the 16 weeks before the before-window, and the comparison is made inside each band.
5. **Give a range, not just a number.** Each uplift comes with a 95% confidence range. If the range includes zero, we cannot say the campaign worked.
6. **Test the method where the answer is known.** The same method is run over days 113 to 223, before any campaign existed, where the true uplift is zero. A fair method should find nothing there.
7. **Split the uplift into couponed products and the rest of the basket.** This shows whether the coupons changed what households bought, how much they bought, or neither. The two parts add up to the total uplift.

### Why the banding uses a separate baseline

The first version banded households on the same before-window used to measure the change. The placebo test exposed this: it found a clear +$65 "uplift" with no campaign running. That is regression to the mean. Control households that land in a high band are mostly light shoppers who had an unusually big few weeks, so they fall back hard and make the targeted group look better. Banding on an earlier 16-week period fixed it: the placebo then showed +$8, not clearly different from zero. Both versions are kept in the SQL so the difference can be checked.

## Known limitations

- **Overlapping campaigns.** Campaign 13's before-window includes the last 5 days of campaign 8, and campaign 18's includes 21 days of campaign 13. If campaigns raise spend, this makes the measured uplift smaller, so the estimates lean cautious.
- **After-windows overlap too.** Campaign 8's after-window runs into the first 6 days of campaign 13, and campaign 13's into the first 13 days of campaign 18. Only campaign 18's after-window is clean.
- **Other campaigns at the same time.** Targeted households may also have received smaller TypeB or TypeC campaigns during the same period.
- **The comparison group is not random.** Never-contacted households may differ in ways the spend bands do not capture.
- **The coupons were broad.** Campaigns 13 and 18 each covered about 35,500 products (roughly 40% of the range) and campaign 8 about 17,000, so "couponed products" were already around half of what targeted households bought.
- **Several comparisons were run.** With eight comparisons, one may clear the 95% bar by chance, so a single clear result is treated as a lead, not proof.
- **The heaviest spenders cannot be measured.** Never-contacted households are mostly light shoppers, so the top spend band has only 10 to 15 of them, too few to compare. Only 308 of campaign 8's 1,076 targeted households could be compared (29%), and about 65% for campaigns 13 and 18.

## Files

- SQL: `sql/04_brief1_campaign_uplift.sql`
- Tables built: `retail-loyalty.analysis.b1_*`
- One-page summary for the client: "Brief 1: Did the Coupon Campaigns Work?" (export as `briefs/brief1_summary.md`)
