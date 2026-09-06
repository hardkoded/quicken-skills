---
name: quicken-hygiene
description: |
  Find data-quality problems in a Quicken for Mac file: uncategorized transactions,
  possible duplicates, transfers with a missing other side, accounts that stopped updating,
  old uncleared transactions, holdings without prices, and missing exchange rates.
  Use when the user says "/quicken-hygiene", "clean up my quicken data", "what needs
  categorizing", "find duplicates in quicken", "which accounts are stale", "check my
  quicken data", or before trusting totals from other quicken-* skills.
---

# quicken-hygiene

Read-only checks that make every other number more trustworthy. Findings are reported;
fixing them happens in Quicken, by the user.

## Before you start

`bash <skill-dir>/../quicken-setup/bin/quicken.sh status` (run `quicken-setup` if there is no
snapshot; `quicken.sh snapshot` if it is over a day old).

## Recipes

Run with `bash <skill-dir>/../quicken-setup/bin/quicken.sh sql -f <skill-dir>/sql/<name>.sql [--from D --to D]`.
Default period is the last 12 months.

| Recipe | What it finds |
|---|---|
| `summary.sql` | one row per check with a count. Start here. |
| `uncategorized.sql` | expense or income lines with no category, or "Uncategorized", by size |
| `possible_duplicates.sql` | same account, date, payee and amount more than once |
| `one_legged_transfers.sql` | transfer lines whose counterpart cannot be found |
| `stale_accounts.sql` | open accounts with no transaction or download in 30 days |
| `unreconciled_old.sql` | uncleared transactions older than 90 days, per account |
| `securities_without_quotes.sql` | holdings with no price or a price older than 30 days |
| `lot_vs_transaction_units.sql` | positions where Quicken's lots disagree with summed transactions |
| `missing_fx.sql` | currency pairs with no rate or a rate older than 30 days |

## How to present

1. Run `summary.sql` first. Lead with the checks that have non-zero counts.
2. For each non-zero check the user cares about, run the detail recipe and show the top rows.
3. Say what each finding means for the numbers: uncategorized lines understate spending
   categories, one-legged transfers look like spending or income, stale accounts make net
   worth stale, missing rates leave base-currency totals incomplete.
4. Suggest the fix in Quicken terms (categorize, match the transfer, update the account,
   download quotes). Do not offer to edit the file.
5. Duplicates are candidates, not certainties. Two identical coffees on one day are normal.
