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
- `sqlite3` and `curl`, both included with macOS. Nothing to install.
- Quicken can stay open. The skills read a snapshot, never the live file.

Quicken for Windows (`.QDF`) is not supported yet. Its file format is not plain SQLite.

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
