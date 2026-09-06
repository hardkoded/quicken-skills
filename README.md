# quicken-skills

Skills that let an AI agent explore your **Quicken for Mac** data in plain language,
read-only, across currencies. Packaged as a plugin for Claude Code, Cursor, GitHub Copilot,
and Codex.

Ask things like:

- "What is my net worth in USD, and how much of it is in EUR?"
- "Where did my money go last month?"
- "Which subscriptions got more expensive this year?"
- "How is my portfolio doing? Show unrealized gains by lot."
- "What is wrong with my data? Uncategorized, duplicates, stale accounts."
- "List every transaction tagged vacation in 2024."

## Included skills

| Skill | What it does |
|---|---|
| `quicken-setup` | Finds your `.quicken` file, takes a read-only snapshot, builds normalized SQL views, downloads daily exchange rates. Run first. |
| `quicken-query` | Turns a question into SQL over the views. Ships a schema reference of the Quicken data model. |
| `quicken-net-worth` | Net worth by account, type and currency, and month-by-month history, in one base currency. |
| `quicken-spending` | Spending by category, payee and month, trends, recurring charges, price increases, savings rate. |
| `quicken-investments` | Holdings, allocation, lot-level gains, total return per security, dividends, trades. |
| `quicken-hygiene` | Uncategorized lines, duplicates, one-legged transfers, stale accounts, missing prices and rates. |

## Installation

### Claude Code

```bash
/plugin marketplace add hardkoded/quicken-skills
/plugin install quicken@quicken-skills
```

### Cursor

Import this repository as a team marketplace, then install `quicken` from the Cursor plugin UI.

### GitHub Copilot (VS Code)

Use **Chat: Install Plugin From Source** and provide:

```text
https://github.com/hardkoded/quicken-skills
```

### Codex

```bash
codex plugin marketplace add hardkoded/quicken-skills
codex plugin add quicken@quicken-skills
```

## Requirements

- Quicken Classic for Mac. The data file is a `.quicken` package with a SQLite database inside.
- **The file must be open in Quicken.** Quicken only keeps the database populated while the
  file is open; a closed file has no accounts in it and the setup skill tells you so. Leave
  Quicken running while you ask questions. The skills read a snapshot, never the live file.
- `sqlite3` and `curl`, both included with macOS. Nothing to install.

Quicken for Windows (`.QDF`) is not supported yet. Its file format is not plain SQLite.

## Examples

Ask in plain language. The agent picks the skill, runs the SQL recipe, and explains the
table. The outputs below come from the small synthetic file in `test/` (base currency USD,
one EUR account, one brokerage account), so the numbers are tiny but real.

### Setup

> Connect my Quicken file.

```
$ quicken.sh find
/Users/me/Documents/My Finances.quicken
$ quicken.sh init "/Users/me/Documents/My Finances.quicken"
snapshot refreshed: /Users/me/.quicken-skills/snapshot.sqlite
base currency: USD
transactions:  8 from 2024-01-15 to 2024-06-01
accounts by currency (open only):
currency  accounts  investment  liability
--------  --------  ----------  ---------
USD       3         1           1
EUR       1         0           0
fx coverage (pair, source, first, last, days):
pair     source       first       last        days
-------  -----------  ----------  ----------  ----
EUR/USD  csv          2024-01-01  2024-02-01  2
EUR/USD  quicken      2026-09-06  2026-09-06  1
```

### Net worth

> What is my net worth, and how much of it is in euros?

| type            | accounts | total_USD |
|-----------------|----------|-----------|
| CHECKING        | 2        | 2345.0    |
| BROKERAGENORMAL | 1        | 605.0     |
| CREDITCARD      | 1        | -80.0     |
| ASSETS          | 2        | 3005.0    |
| LIABILITIES     | 2        | -135.0    |
| NET WORTH       | 4        | 2870.0    |

| currency | cash   | securities | total_USD | share_pct |
|----------|--------|------------|-----------|-----------|
| USD      | 2425.0 | 500.0      | 2925.0    | 101.9     |
| EUR      | -50.0  | 0.0        | -55.0     | -1.9      |

The agent answers: net worth is 2,870 USD (Quicken home currency, rates from the cached CSV
and Quicken's current rate). The euro account is overdrawn by 50 EUR, about 55 USD.

### Spending

> Where did my money go in 2024, and what was my savings rate in January?

| category       | lines | spent_USD | share_pct |
|----------------|-------|-----------|-----------|
| Food:Groceries | 3     | 234.0     | 100.0     |

| month   | income_USD | expenses_USD | net_USD | savings_rate_pct |
|---------|------------|--------------|---------|------------------|
| 2024-01 | 3000.0     | 100.0        | 2900.0  | 97.0             |
| 2024-02 | 0.0        | 54.0         | -54.0   |                  |
| 2024-03 | 0.0        | 80.0         | -80.0   |                  |

The 54 USD in February is a 50 EUR purchase converted at the rate on that day (1.08), not
today's rate. Transfers between accounts are excluded.

Other spending questions: "top payees this year", "which subscriptions do I pay monthly",
"what got more expensive", "biggest expenses last quarter", "this month vs my 12-month average".

### Investments

> How is my portfolio doing?

| account   | security  | ticker | units | price | value | cost_basis | unrealized_gain | gain_pct | weight_pct |
|-----------|-----------|--------|-------|-------|-------|------------|-----------------|----------|------------|
| Brokerage | Test Fund | TST    | 10.0  | 50    | 500.0 | 400.0      | 100.0           | 25.0     | 100.0      |

| security  | status | invested_USD | proceeds_USD | income_USD | value_now_USD | total_gain_USD | gain_pct |
|-----------|--------|--------------|--------------|------------|---------------|----------------|----------|
| Test Fund | open   | 400.0        | 0.0          | 5.0        | 500.0         | 105.0          | 26.3     |

Total return counts the 5 USD dividend. Prices are Quicken's own quote history, so the
agent also reports the price date.

### Data hygiene

> Is there anything wrong with my data?

| check_name                                    | n |
|-----------------------------------------------|---|
| uncategorized lines (period)                  | 0 |
| possible duplicate groups (period)            | 0 |
| one-legged transfers (all time)               | 0 |
| stale open accounts                           | 4 |
| uncleared older than 90 days                  | 4 |
| holdings without a recent price               | 1 |
| positions where lots differ from transactions | 0 |
| split lines with no exchange rate             | 0 |
| currency pairs with stale rates               | 0 |

Then it drills into the non-zero checks and says what each one means for the other numbers.

### Free-form questions

> Show me everything I tagged "vacation".

```sql
SELECT date, account, payee, category, amount, currency, amount_base
FROM q_split_base WHERE tags LIKE '%vacation%';
```

| date       | account  | payee  | category       | amount | currency | amount_base |
|------------|----------|--------|----------------|--------|----------|-------------|
| 2024-01-20 | Checking | Grocer | Food:Groceries | -100   | USD      | -100.0      |

`quicken-query` writes SQL like this against the `q_*` views. Its `reference/schema.md`
documents every view and the raw Quicken tables for anything the views do not cover
(budgets, scheduled transactions, loan terms).

## How it works

1. `quicken-setup` copies `<file>.quicken/data` to `~/.quicken-skills/snapshot.sqlite`
   with SQLite's backup API (read-only) and creates `q_*` views on the copy: accounts,
   categories, split lines, balances by month, holdings, quotes, investment transactions.
2. Quicken stores only one *current* exchange rate per currency pair. To consolidate history,
   the setup skill downloads daily rates (ECB via Frankfurter by default, Yahoo Finance as
   fallback, or a CSV you provide) and caches them in `~/.quicken-skills/fx/`. Every `*_base`
   column converts at the rate on the transaction date.
3. The analysis skills are markdown instructions plus `.sql` recipes. The agent runs them
   with `quicken.sh sql` and explains the result. Numbers come from SQL, not from the model.

The base currency defaults to Quicken's home currency. Change it with `quicken.sh base EUR`.

## Privacy

- The live Quicken file is never opened for writing and nothing inside the package is changed.
- The snapshot is a full copy of your finances, stored with mode 600 in your home directory.
  Delete `~/.quicken-skills` at any time; the next `snapshot` recreates it.
- The only network calls are exchange-rate downloads. They contain currency codes and dates,
  never your transactions.
- Your AI agent, of course, sees the query results you ask for. Use an agent you trust with
  your financial data.

## Repository layout

```text
quicken-skills/
├── .claude-plugin/marketplace.json
├── .cursor-plugin/marketplace.json
├── plugin.json
├── test/                         synthetic fixture + test runner (bash test/run.sh)
└── plugins/
    └── quicken/
        ├── .claude-plugin/plugin.json
        ├── .cursor-plugin/plugin.json
        ├── .codex-plugin/plugin.json
        └── skills/
            ├── quicken-setup/        SKILL.md, bin/quicken.sh, sql/views.sql, sql/fx_schema.sql
            ├── quicken-query/        SKILL.md, reference/schema.md, sql/examples.sql
            ├── quicken-net-worth/    SKILL.md, sql/*.sql
            ├── quicken-spending/     SKILL.md, sql/*.sql
            ├── quicken-investments/  SKILL.md, sql/*.sql
            └── quicken-hygiene/      SKILL.md, sql/*.sql
```

Every install path above resolves skills through a plugin manifest's `"skills"` field,
which points at `plugins/quicken/skills/`, the single copy of each skill in this repo.

## Development

```bash
bash test/run.sh
```

Builds an empty Quicken schema (captured from a real 9.x file), loads a few synthetic rows,
runs every view and recipe, and checks known totals. CI runs it on Linux and macOS.

## License

MIT
