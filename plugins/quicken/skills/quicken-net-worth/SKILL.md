---
name: quicken-net-worth
description: |
  Net worth from a Quicken for Mac file, consolidated into one base currency: current total
  by account and account type, how much sits in each currency, and the month-by-month history
  of cash plus investments. Use when the user says "/quicken-net-worth", "what is my net
  worth", "how much money do I have", "net worth over time", "how exposed am I to <currency>",
  "assets and liabilities", or asks how their wealth changed since a date.
---

# quicken-net-worth

## Before you start

`bash <skill-dir>/../quicken-setup/bin/quicken.sh status` (run `quicken-setup` if there is no
snapshot; `quicken.sh snapshot` if it is over a day old). With more than one currency, make
sure `fx coverage` lists a provider other than `quicken`; otherwise run `quicken.sh fx sync`.
Run `quicken.sh doctor` once: stale prices or rates change the answer.

## Recipes

Run with `bash <skill-dir>/../quicken-setup/bin/quicken.sh sql -f <skill-dir>/sql/<name>.sql [--base CCY]`.

| Recipe | Question it answers |
|---|---|
| `current_by_account.sql` | every open account: cash, securities, total in its currency and in the base |
| `current_by_type.sql` | totals by account type plus a grand total |
| `exposure_by_currency.sql` | how much of the net worth is denominated in each currency |
| `history_monthly.sql` | month-end cash, securities and total in the base currency, from the first transaction to now |

`history_monthly.sql` takes `--from` to shorten the range. To answer "how did my net worth
change since X", read the two rows for X and the latest month from that recipe.

## How it is computed

- Cash side: sum of all transaction amounts per account up to the date (includes the cash in
  brokerage accounts). Credit cards and loans are negative and reduce the total.
- Securities today: Quicken's lots times the latest price, in the security currency, then
  converted at the latest rate.
- Securities history: units rebuilt from investment transactions times the last price on or
  before month end. Lots can differ from summed transactions after stock splits or manual
  edits; when `quicken-hygiene` reports such a difference, say the history is approximate for
  that security.
- Conversion: rate on the date (month end for history), forward-filled from the last known rate.

## How to present

- Lead with the total in the base currency, then the split assets vs liabilities, then
  the biggest accounts. Round to whole units.
- Always state the base currency, the rate source, and the snapshot date.
- For exposure, explain that a security's currency is the currency it is priced in, which
  may differ from its account.
- Closed accounts are excluded; accounts with a zero balance are hidden in the by-account view.
