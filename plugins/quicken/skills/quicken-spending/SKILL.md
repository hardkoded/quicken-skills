---
name: quicken-spending
description: |
  Analyze spending and income from a Quicken for Mac file: by category, payee and month,
  trends against the trailing average, recurring charges, price increases at the same
  payee, largest expenses, and monthly savings rate. Amounts are consolidated into one
  base currency. Use when the user says "/quicken-spending", "where did my money go",
  "how much did I spend on", "top payees", "my subscriptions", "what got more expensive",
  "savings rate", "income vs expenses", or asks about spending trends.
---

# quicken-spending

## Before you start

`bash <skill-dir>/../quicken-setup/bin/quicken.sh status` (run `quicken-setup` if there is no
snapshot; `quicken.sh snapshot` if it is over a day old). If the file has several currencies
and `status` shows no `fx coverage` beyond `quicken`, run `quicken.sh fx sync` first.

## Conventions

All recipes exclude transfers and lines marked "exclude from reports", and only count
categories of kind `expense` or `income`. Spending is shown as a positive number
(`-amount_base`). Every recipe takes `--from` and `--to`; the default is the last 12 months.

Run with `bash <skill-dir>/../quicken-setup/bin/quicken.sh sql -f <skill-dir>/sql/<name>.sql [--from D --to D] [--base CCY]`.

| Recipe | Question it answers |
|---|---|
| `by_category.sql` | where did the money go, by full category, with share of total |
| `by_category_month.sql` | month by top-level category, long format for trends |
| `by_payee.sql` | top payees: count, average, total |
| `trend_vs_12mo_avg.sql` | last full month per top-level category vs the average of the 12 months before it (ignores `--from/--to`) |
| `recurring_candidates.sql` | payees charged at a steady monthly cadence with a steady amount |
| `price_increases.sql` | recurring payees whose latest charge is above the previous one |
| `largest_transactions.sql` | biggest single expenses in the period |
| `income_vs_expense_monthly.sql` | income, expenses, net and savings rate per month |

## How to present

- State the period, the base currency, the rate source, and that transfers are excluded.
- Round to whole units. Show top 10 to 15 rows, then "everything else" as one line.
- When a currency other than the base dominates a category, mention the original-currency
  total too; the user thinks in the currency they paid in.
- Trend numbers compare a full month with a full-month average. Do not compare a partial
  current month; say which month is the "last full month".
- Recurring and price-increase results are heuristics (cadence 25 to 35 days, amounts within
  15%). Call them candidates.
- For a follow-up question the recipes do not cover, switch to the `quicken-query` skill.
