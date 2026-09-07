---
name: quicken-setup
description: |
  Connect an AI agent to a Quicken for Mac data file, read-only. Finds the .quicken file,
  opens it read-only, defines normalized q_* SQL views, and caches daily exchange rates so
  accounts in different currencies can be consolidated into one base currency.
  Use when the user says "/quicken-setup", "connect my quicken file", "quicken status",
  "sync exchange rates", "change base currency", or before any other quicken-* skill runs
  for the first time in a session.
---

# quicken-setup

Foundation for every `quicken-*` skill. It opens the Quicken file read-only and never copies
it, so every answer reflects what Quicken shows right now. Only settings and exchange rates
are stored, in `~/.quicken-skills/` (mode 600).

## How to invoke

Always call the script by absolute path, next to this file:

```
bash <skill-dir>/bin/quicken.sh <command> [args]
```

`<skill-dir>` is the directory this `SKILL.md` was read from. Other `quicken-*` skills
live beside this one and call `bash <their-skill-dir>/../quicken-setup/bin/quicken.sh`.

Requirements: `sqlite3` (ships with macOS) and `curl` for exchange rates. No Node, no Python.
**The file must be open in Quicken.** Quicken keeps the database populated only while the file
is open; a closed file has no account table and every command stops with a message saying so.

## First run

1. `quicken.sh find` lists `.quicken` files on the machine. If there is exactly one, use it.
   If there are several, ask the user which one. Backups (`.quickenbackup`) are not listed.
2. `quicken.sh init "<path>.quicken"` remembers the file, picks the base currency from
   Quicken's home currency setting, loads Quicken's current exchange rates, and prints `status`.
3. If `status` shows more than one account currency, run `quicken.sh fx sync`. It downloads
   daily rates from the first transaction date to today for every account currency.
4. `quicken.sh doctor` confirms every view works and every currency has current rates.

## Every later session

Run `quicken.sh status`. If it says "not configured", do the first run. There is nothing to
refresh: queries read the open file directly, so edits made in Quicken show up immediately.

## Commands

- `find` — print candidate `.quicken` paths.
- `init <path>` — configure, load rates, status. Safe to re-run.
- `status` — file, base currency, transaction count and date range, accounts per currency, fx coverage.
- `doctor` — runs every view, reports missing or stale rates.
- `base <CCY>` — change the base currency for every `*_base` column (for example `base EUR`).
- `fx sync [--from YYYY-MM-DD]` — download and cache daily rates for each account currency to the base.
- `fx provider <FROM> <frankfurter|yahoo|csv|quicken> [csv-path]` — choose the rate source for one currency.
- `sql [-f file | "query"] [--json|--csv] [--base CCY] [--from D] [--to D]` — run SQL on the open file.
  Output is a markdown table by default. `{{from}}`, `{{to}}` and `{{base}}` in the query are
  replaced (defaults: 12 months ago, today, configured base). `--base` applies to that run only.

## How a query runs

Each `sql` call opens `<file>.quicken/data` with `sqlite3 -readonly`, attaches
`~/.quicken-skills/fx.sqlite` as `fx`, creates the `q_*` views as `TEMP` views (they exist
only for that session) and runs the query. Nothing is created inside the Quicken file. A
query holds a shared lock for a few milliseconds; Quicken keeps working.

## Exchange rates

Quicken stores only one current rate per currency pair, so history has to come from outside.
Rates are cached as CSV in `~/.quicken-skills/fx/<FROM>-<TO>.csv` and loaded into the
`fx_rate` table of `fx.sqlite`. `rate` is units of the base currency per one unit of the
other currency.

Providers, in the order the default tries them:
- `frankfurter` — European Central Bank reference rates. About 30 major currencies.
  If the series ends more than 30 days ago the currency is treated as unsupported.
- `yahoo` — Yahoo Finance daily closes. Wide coverage, long history, unofficial endpoint.
- `csv` — a file the user supplies with `date,rate` rows. Use this when the user wants a
  specific rate source, such as a central bank series or a parallel-market rate.
- `quicken` — only the current rate from Quicken. Every historical amount converts at today's rate.

When you report converted amounts, always name the base currency and the rate source
(see `status`). If `doctor` warns that rates are stale or missing, say so before quoting totals.

## What lives where

- `~/.quicken-skills/config` — `QUICKEN_FILE`, `BASE_CURRENCY`, `FX_PROVIDER_*`, `FX_CSV_*`.
- `~/.quicken-skills/fx.sqlite` — cached exchange rates. Delete it any time; the next command recreates it.
- `~/.quicken-skills/fx/*.csv` — the downloaded rate series.
- Set `QUICKEN_SKILLS_HOME` to move this directory.

## Rules

- Never open the live `.quicken/data` file for writing and never edit anything inside the package.
- Never send transaction data anywhere. Only exchange-rate requests leave the machine, and they
  carry currency codes and dates only.
- Read `../quicken-query/reference/schema.md` before writing SQL against raw `Z*` tables.
