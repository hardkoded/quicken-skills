---
name: quicken-investments
description: |
  Investment analysis from a Quicken for Mac file: current holdings and unrealized gains,
  allocation by asset class and currency, per-lot gains and holding periods, total return per
  security (invested, proceeds, income, current value), dividends and interest by year, and
  recent trades. Consolidated into one base currency. Use when the user says
  "/quicken-investments", "my portfolio", "what do I hold", "unrealized gains", "how is
  <ticker> doing", "dividends this year", "asset allocation", or "my trades".
---

# quicken-investments

## Before you start

`bash <skill-dir>/../quicken-setup/bin/quicken.sh status` (run `quicken-setup` if there is no
snapshot; `quicken.sh snapshot` if it is over a day old). Then `quicken.sh doctor`: holdings
without a recent price make every value stale. Prices come from Quicken's own quote history,
so if the user has not opened Quicken recently, say the prices are as of `price_date`.

## Recipes

Run with `bash <skill-dir>/../quicken-setup/bin/quicken.sh sql -f <skill-dir>/sql/<name>.sql [--from D --to D] [--base CCY]`.

| Recipe | Question it answers |
|---|---|
| `holdings.sql` | every position: units, price, value, cost, unrealized gain, share of portfolio |
| `allocation.sql` | portfolio by asset class, and by currency |
| `unrealized_by_lot.sql` | each tax lot: bought when, cost, value now, gain, days held |
| `security_return.sql` | per security, all time: invested, proceeds, income, value now, total gain and % |
| `dividends_by_year.sql` | dividend and interest income per year and security, in the base currency |
| `transactions.sql` | trades and income events in the period |

## How it is computed

- Holdings and lots come from Quicken's lot table, which already reflects stock splits.
- `security_return.sql` is a cash-flow view: invested = cash paid on buys plus cost basis of
  added shares; proceeds = cash received on sells; income = dividends and interest; gain =
  value now + proceeds + income - invested. It is a simple total return, not an annualized
  rate. For closed positions (no units left) the gain is realized.
- Quicken does not store the cost of shares sold on the sell row, so there is no per-sale
  realized gain recipe. Say so if the user asks for one, and offer `security_return.sql`
  filtered to closed positions instead.
- Values are in the security currency; `*_base` columns convert at the latest rate (holdings)
  or the transaction-date rate (cash flows, dividends).

## How to present

- Lead with total value in the base currency and total unrealized gain. Then the top
  positions by value, with weight %. Round money to whole units, units to 4 decimals.
- State the base currency, rate source, price dates and the snapshot date.
- Never present the simple total return as an annual rate.
- Tax questions: these numbers are not tax lots matched to sales. Point that out.
