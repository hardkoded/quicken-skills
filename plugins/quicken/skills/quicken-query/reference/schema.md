# Quicken for Mac data model, as seen through SQLite

The `.quicken` package is a folder. `data` inside it is a Core Data SQLite store
(Quicken Classic for Mac; verified on 9.x). `quicken.sh snapshot` copies it and adds the
`q_*` views and the `fx_*` tables described here. Nothing here ever writes to the live file.

## Core Data conventions

- Every table is `Z<ENTITY>` with `Z_PK` (id), `Z_ENT` (entity type), `Z_OPT` (version).
- Entity types are listed in `Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER)`. Subclasses share one
  table: `ZTRANSACTION` holds CashFlowTransaction, SmartCashFlowTransaction (scheduled) and
  InvestmentTransaction rows, distinguished by `Z_ENT`. Entity numbers change between
  Quicken versions. Never hard-code them; the views resolve them at snapshot time.
- Many-to-many join tables are named `Z_<n>USERTAGS` with columns that embed entity numbers.
  The views resolve the right one by column name.
- Timestamps are seconds since 2001-01-01 UTC. Convert with
  `date(col + 978307200, 'unixepoch')`. Quicken writes dates at UTC noon or midnight, so
  no local-time adjustment is needed.
- The transaction date is `ZENTEREDDATE`. `ZPOSTEDDATE` is NULL on most manually entered
  rows; do not use it as the date.
- Soft deletes: `ZDELETIONCOUNT > 0` means deleted. Always filter `ZDELETIONCOUNT = 0`.
- Amount sign: outflows are negative, inflows positive, in the account's currency.

## Views

### q_account
`id, name, type, currency, closed, active, is_investment, is_liability, credit_limit,
institution, last_download_date, bank_reported_balance, notes`
`type` values seen: CHECKING, SAVINGS, CASH, CREDITCARD, LIABILITY, BROKERAGENORMAL,
BROKERAGEOTHER. `is_investment` = type starts with BROKERAGE. Credit card and liability
balances are negative numbers.

### q_category
`id, name, full_name, parent_id, depth, kind, hidden, tax_ref_us, tax_ref_ca`
`full_name` is `Parent:Child`. `kind`: `expense`, `income`, or `system` (Transfer,
Uncategorized, Adjustment, Investments and the investment actions such as Buy and Sell).

### q_tag
User tags: `id, name, description`.

### q_payee
`id, name`.

### q_security
`id, name, ticker, currency, type_code, issue_type, asset_class, watchlist`
`currency` can be NULL; treat it as the account currency. `asset_class` is free text from
Quicken and may be NULL.

### q_transaction
`id, quicken_id, date, posted_date, account_id, account, currency, payee_id, payee,
amount, note, check_number, kind, reconcile_code, status, excluded, downloaded`
`date` is the transaction date the user sees (`ZENTEREDDATE`, always set). `posted_date`
is the bank posting date and is NULL on anything not downloaded.
`kind`: `cashflow`, `investment`, `scheduled`. `status`: `uncleared` (0), `cleared` (1),
`reconciled` (2). Downloaded transactions arrive as `cleared`. `excluded` = the user ticked
"exclude from reports". Includes scheduled rows; most analysis should use `kind <> 'scheduled'`.

### q_split
One row per split line (`ZCASHFLOWTRANSACTIONENTRY`). A transaction without splits still
has one line. Scheduled transactions are excluded.
`id, transaction_id, date, account_id, account, currency, payee_id, payee, kind,
category_id, category, category_leaf, category_kind, amount, note, is_transfer,
transfer_account_id, transfer_account, tags, status, excluded`
- `is_transfer = 1` when the line is one leg of a transfer. `transfer_account` is the other
  side. Exclude transfers from spending and income.
- Investment transactions have exactly one split whose `category` is the action name
  (Buy, Sell, Dividend Income, Interest Income, Add Shares, Remove Shares, ...). Dividend and
  interest lines have `category_kind = 'income'`; the rest are `system`.
- `tags` is a comma-separated list of user tags on the line.

### q_split_base
`q_split` plus `base_currency, fx_rate, amount_base`. `amount_base = amount * fx_rate`,
where `fx_rate` is the latest rate on or before the transaction date. If no rate exists
before that date, the earliest known rate is used. NULL means no rate at all for the pair.

### q_account_balance_monthly
`month, month_end, account_id, account, type, currency, is_investment, is_liability,
balance, base_currency, fx_rate, balance_base`
One row per account per calendar month from the first transaction to now. `balance` is the
sum of all transaction amounts up to month end. For brokerage accounts this is the cash
side only; securities are in `q_holding`.

### q_quote, q_quote_latest
`security_id, date, close`. Prices are in the security currency.

### q_holding
Current positions from Quicken's lots (lots already reflect stock splits).
`position_id, account_id, account, security_id, security, ticker, currency, units, price,
price_date, value, cost_basis, unrealized_gain, asset_class, base_currency, fx_rate, value_base`
`value_base` uses the latest known rate. Positions with zero units are excluded.

### q_investment_transaction
`id, date, account_id, account, currency, security_id, security, ticker, action_code,
action, units, amount, cost_basis, commission, note`
`action` comes from the split category; the code map is 2 Add Shares, 3 Buy, 5 Buy to
Cover, 6 Margin Interest Expense, 10 Dividend Income, 11 Interest Income, 17 Remove Shares,
19 Sell, 21 Short Sell, 23 Stock Split. `amount` is the cash effect (Buy negative, Sell
positive, Add/Remove Shares zero). `cost_basis` is set on Buy and Add Shares rows; Sell
rows usually carry 0, so realized gains need lot matching that Quicken does not expose.
Join `q_split_base` on `transaction_id` for `fx_rate` on the transaction date.

### q_scheduled
`id, next_date, account, currency, payee, amount, note, recurrence_json`.

### q_fx_latest, fx_rate, fx_config
`fx_rate(from_ccy, to_ccy, date, rate, source)`: `rate` is units of `to_ccy` per one
`from_ccy`. `source` is `frankfurter`, `yahoo`, `csv`, or `quicken`, with a `-derived` suffix
for reverse rates computed from a cached series and `cross-derived` for pairs computed
through the base currency. `fx_config(base_ccy)` has one row.

## Raw tables worth knowing

| Table | What it holds | Notes |
|---|---|---|
| `ZACCOUNT` | accounts | `ZTYPENAME`, `ZCURRENCY`, `ZCLOSED`, loan and statement fields |
| `ZTRANSACTION` | all transaction types | `ZENTEREDDATE` (transaction date), `ZPOSTEDDATE` (bank date, often NULL), `ZAMOUNT`, `ZUSERPAYEE`, `ZPOSITION`, `ZUNITS`, `ZCOSTBASIS`, `ZTYPE` (investment action) |
| `ZCASHFLOWTRANSACTIONENTRY` | split lines | `ZPARENT` -> transaction, `ZCATEGORYTAG` -> `ZTAG`, `ZTRANSFER` = counterpart line's `ZQUICKENID` as text |
| `ZTAG` | categories and user tags | `ZPARENTCATEGORY`, `ZTYPE` (1 expense, 2 income, 0 system), `ZTAXREFUS`, `ZTAXREFCA` |
| `ZUSERPAYEE` | payees | `ZNAME`, address fields |
| `ZSECURITY`, `ZPOSITION`, `ZLOT` | securities, positions per account, tax lots | `ZLOT.ZLATESTUNITS`, `ZLATESTCOSTBASIS`, `ZACQUISITIONDATE` |
| `ZSECURITYQUOTE` | daily prices | `ZQUOTEDATE`, `ZCLOSINGPRICE` |
| `ZSECURITYSPLIT` | stock split events | |
| `ZFOREXQUOTE` | current exchange rate per pair | one row per pair, no history |
| `ZBUDGET`, `ZBUDGETLINEITEM`, `ZBUDGETTARGET` | budgets | `ZBUDGETTARGET.ZEFFECTIVEDATENUM`, `ZAMOUNT` |
| `ZDOCUMENTPROPERTY` | file settings | `ZNAME = 'homeCurrencyCode'` |
| `ZFISTATEMENT`, `ZFIBALANCE` | downloaded statements and balances | |
| `ZQUICKFILLRULE`, `ZRENAMINGRULE` | auto-categorization rules | |
| `ZREPORT` | saved report definitions | |

## Known quirks

- A few old transfer lines store an account name in `ZTRANSFER` instead of an id. The views
  treat them as transfers with an unknown counterpart.
- Lot units and summed transaction units can differ after stock splits or manual lot edits.
  Lots are what Quicken shows; use them for current holdings.
- `ZRECONCILESTATUS` is NULL on investment transactions.
- Category `ZTYPE` on a child category can differ from its parent; the views use each
  category's own value.
