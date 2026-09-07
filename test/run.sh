#!/usr/bin/env bash
# Builds a synthetic Quicken file, runs quicken.sh against it, checks every view and
# recipe, and asserts a few known totals. Needs sqlite3 only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
Q="$ROOT/plugins/quicken/skills/quicken-setup/bin/quicken.sh"
SKILLS="$ROOT/plugins/quicken/skills"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export QUICKEN_SKILLS_HOME="$TMP/state"

mkdir -p "$TMP/fixture.quicken" "$QUICKEN_SKILLS_HOME/fx"
sqlite3 "$TMP/fixture.quicken/data" < "$ROOT/test/fixture-schema.sql"
sqlite3 "$TMP/fixture.quicken/data" < "$ROOT/test/fixture-data.sql"
printf 'date,rate,source\n2024-01-01,1.10,csv\n2024-02-01,1.08,csv\n' > "$QUICKEN_SKILLS_HOME/fx/EUR-USD.csv"

fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"
  else printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}
q() { bash "$Q" sql --csv "$@" | tail -n +2 | tr -d '\r"'; }

echo "closed file is rejected"
mkdir -p "$TMP/closed.quicken"
sqlite3 "$TMP/closed.quicken/data" "CREATE TABLE Z_METADATA (Z_VERSION INTEGER)"
if bash "$Q" init "$TMP/closed.quicken" > /dev/null 2>&1; then echo "  FAIL init accepted a closed file"; fail=1; else echo "  ok   init rejects a closed file"; fi

before=$(shasum "$TMP/fixture.quicken/data" | cut -d' ' -f1)
echo "init"
bash "$Q" init "$TMP/fixture.quicken" > /dev/null
echo "doctor"
bash "$Q" doctor

echo "views"
check "accounts"              "4"                        "$(q "SELECT count(*) FROM q_account")"
check "category path"         "Food:Groceries,expense,1" "$(q "SELECT full_name, kind, depth FROM q_category WHERE id = 11")"
check "base currency"         "USD"                      "$(q "SELECT base_ccy FROM fx_config")"
check "split lines"           "8"                        "$(q "SELECT count(*) FROM q_split")"
check "transaction date"      "2024-01-20,2024-01-21"    "$(q "SELECT date, posted_date FROM q_transaction WHERE id = 101")"
check "transfer resolved"     "1,Brokerage"              "$(q "SELECT is_transfer, transfer_account FROM q_split WHERE id = 203")"
check "tags"                  "vacation"                 "$(q "SELECT tags FROM q_split WHERE id = 201")"
check "fx on date (1.08)"     "-54.0"                    "$(q "SELECT amount_base FROM q_split_base WHERE id = 202")"
check "investment action"     "Buy,10,-400"          "$(q "SELECT action, units, amount FROM q_investment_transaction WHERE id = 106")"
check "holding"               "10,50,500.0,100.0"    "$(q "SELECT units, price, value, unrealized_gain FROM q_holding")"
check "month-end balance"     "2400"                   "$(q "SELECT balance FROM q_account_balance_monthly WHERE account = 'Checking' AND month = '2024-02'")"
check "stale days sane"       "2024-02-15"               "$(q "SELECT max(coalesce(max(t.date), '1900-01-01'), coalesce(a.last_download_date, '1900-01-01')) FROM q_account a LEFT JOIN q_transaction t ON t.account_id = a.id WHERE a.name = 'Checking' GROUP BY a.id")"

echo "recipes"
check "spending by category"  "Food:Groceries,3,234.0,100.0" \
  "$(q -f "$SKILLS/quicken-spending/sql/by_category.sql" --from 2024-01-01 --to 2024-12-31)"
check "savings rate"          "2024-01,3000.0,100.0,2900.0,97.0," \
  "$(q -f "$SKILLS/quicken-spending/sql/income_vs_expense_monthly.sql" --from 2024-01-01 --to 2024-01-31)"
check "net worth"             "NET WORTH,3,4,2870.0" \
  "$(q -f "$SKILLS/quicken-net-worth/sql/current_by_type.sql" | grep '^NET WORTH')"
check "exposure"              "EUR,-50.0,0.0,-55.0" \
  "$(q -f "$SKILLS/quicken-net-worth/sql/exposure_by_currency.sql" | grep '^EUR' | cut -d, -f1-4)"
check "security return"       "Test Fund,TST,open,400.0,0.0,5.0,500.0,105.0" \
  "$(q -f "$SKILLS/quicken-investments/sql/security_return.sql" | cut -d, -f1-3,6-10)"
check "hygiene summary rows"  "9" "$(q -f "$SKILLS/quicken-hygiene/sql/summary.sql" | wc -l | tr -d ' ')"
check "history month-end quote" "2024-12,2371.0,500.0,2871.0" \
  "$(q -f "$SKILLS/quicken-net-worth/sql/history_monthly.sql" --from 2024-01-01 | grep '^2024-12')"
check "stale accounts detail"  "4" "$(q -f "$SKILLS/quicken-hygiene/sql/stale_accounts.sql" | awk -F, '$NF < 2000' | wc -l | tr -d ' ')"

echo "every recipe compiles and runs"
for f in "$SKILLS"/quicken-*/sql/*.sql; do
  case "$f" in */quicken-setup/*) continue ;; esac
  if bash "$Q" sql -f "$f" --from 2024-01-01 --to 2024-12-31 > /dev/null 2> "$TMP/err"; then
    printf '  ok   %s\n' "${f#"$SKILLS"/}"
  else
    printf '  FAIL %s\n' "${f#"$SKILLS"/}"; sed 's/^/       /' "$TMP/err"; fail=1
  fi
done

echo "base currency switch"
check "base EUR total"        "EUR" "$(q "SELECT base_currency FROM q_split_base LIMIT 1" --base EUR)"
check "base EUR derived rate" "-90.91" "$(q "SELECT amount_base FROM q_split_base WHERE id = 201" --base EUR 2>/dev/null)"
check "base unchanged after"  "USD" "$(q "SELECT base_ccy FROM fx_config")"

echo "read-only"
check "quicken file unchanged"  "$before" "$(shasum "$TMP/fixture.quicken/data" | cut -d' ' -f1)"
check "no journal left behind"  "$TMP/fixture.quicken/data" "$(echo "$TMP"/fixture.quicken/*)"
check "no copy of the file"     "config fx fx.sqlite" "$(cd "$QUICKEN_SKILLS_HOME" && echo *)"

if [ "$fail" = 0 ]; then echo "all tests passed"; else echo "tests failed"; exit 1; fi
