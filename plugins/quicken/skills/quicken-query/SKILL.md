---
name: quicken-query
description: |
  Answer any question about the user's Quicken for Mac data by writing SQL against the
  normalized q_* views. Use when the user asks something about their finances that the
  focused skills (net worth, spending, investments, hygiene) do not cover directly, or says
  "ask my quicken data", "query quicken", "how much did I ... in quicken", "list my quicken
  transactions for ...", "which payee ...", "show me transactions tagged ...".
---

# quicken-query

Natural language in, one SQL query out, table back. Read-only.

## Before you start

1. `bash <skill-dir>/../quicken-setup/bin/quicken.sh status`. If it says "not configured",
   run the `quicken-setup` skill first. Queries read the open Quicken file, so there is
   nothing to refresh.
2. Read `reference/schema.md` in this folder once per session. It lists every view, its
   columns, and the raw table quirks.

## Procedure

1. Restate the question as a filter and an aggregation. Pick the view:
   - amounts by category, payee, tag, month: `q_split_base` (one row per split line)
   - account-level facts: `q_account`, `q_transaction`
   - balances over time: `q_account_balance_monthly`
   - securities: `q_holding`, `q_investment_transaction`, `q_quote`
2. Write the SQL. Use `{{from}}`, `{{to}}` and `{{base}}` where a period or base currency
   is involved. Filter out noise unless the user wants it:
   `is_transfer = 0 AND excluded = 0 AND kind = 'cashflow'`.
   Expenses are negative amounts. Use `-amount_base` to show spending as positive numbers.
3. Run it:
   `bash <skill-dir>/../quicken-setup/bin/quicken.sh sql "<query>" --from 2025-01-01 --to 2025-12-31`
   Add `--json` when you need to post-process. Add `--base EUR` to convert into another currency for that run.
4. Present the result. Always state: period, base currency, rate source (from `status`),
   and whether transfers were excluded. Round to whole units unless the user
   asks for cents. If a filter matched nothing, say so and show what values exist
   (for example `SELECT DISTINCT category FROM q_split WHERE category LIKE '%word%'`).

## Matching names

Category, payee and tag names are the user's own. Match loosely first:
`WHERE category LIKE '%groc%'` or `payee LIKE '%netflix%'`. If more than one matches,
show the list and ask which one the user meant. `q_category.full_name` is
`Parent:Child`; `category_leaf` is the last segment.

## Multi-currency

Every `*_base` column is converted at the rate on the transaction date (forward-filled from
the last known rate). Amounts in the original currency are in `amount`. When the user mixes
currencies, show both the base total and the per-currency breakdown. If `doctor` reports
missing rates, warn before quoting a base total.

## Raw tables

The views cover the common questions. For anything else (budgets, attachments, scheduled
transactions, loan terms) read the raw table section in `reference/schema.md` and query the
`Z*` tables directly. Convert timestamps with `date(col + 978307200, 'unixepoch')` and always
add `ZDELETIONCOUNT = 0`.

`sql/examples.sql` has worked examples to copy from.
