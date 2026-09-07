#!/usr/bin/env bash
# Read-only access to a Quicken for Mac data file for AI skills.
# The Quicken file is opened read-only and never copied. Exchange rates and settings live
# in ~/.quicken-skills. Works on macOS bash 3.2 and Linux. Needs sqlite3; fx sync also needs curl.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$SCRIPT_DIR/../sql"
STATE_DIR="${QUICKEN_SKILLS_HOME:-$HOME/.quicken-skills}"
CONFIG="$STATE_DIR/config"
FX_DB="$STATE_DIR/fx.sqlite"
FX_DIR="$STATE_DIR/fx"
EPOCH_OFFSET=978307200

QUICKEN_FILE=""
BASE_CURRENCY=""
LIVE=""

die() { echo "quicken: $*" >&2; exit 1; }
warn() { echo "quicken: $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
sql_str() { printf '%s' "$1" | sed "s/'/''/g"; }
uri_path() { printf '%s' "$1" | sed -e 's/%/%25/g' -e 's/?/%3F/g' -e 's/#/%23/g'; }

# Raw read-only queries on the open Quicken file (no views).
live() { sqlite3 -readonly -cmd '.timeout 5000' "$LIVE" "$@"; }
# Queries on our own exchange-rate database.
fxdb() { sqlite3 -cmd '.timeout 5000' "$FX_DB" "$@"; }

load_config() {
  if [ -f "$CONFIG" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG"
  fi
}

config_get() {
  load_config
  eval "printf '%s' \"\${$1:-}\""
}

config_set() {
  mkdir -p "$STATE_DIR"
  touch "$CONFIG"
  { grep -v "^$1=" "$CONFIG" || true; printf '%s=%q\n' "$1" "$2"; } > "$CONFIG.tmp"
  mv "$CONFIG.tmp" "$CONFIG"
  chmod 600 "$CONFIG"
}

# Quicken keeps the data file populated only while the file is open in Quicken.
# A closed file has a handful of metadata tables and no accounts.
check_file_is_open() {
  local n
  n=$(sqlite3 -readonly -cmd '.timeout 5000' "$1" "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'ZACCOUNT'" 2>&1) || die "could not read $1: $n"
  [ "$n" = 1 ] || die "the data file has no account table. Open the file in Quicken and try again."
}

ensure_fx_db() {
  mkdir -p "$STATE_DIR"
  rm -f "$STATE_DIR/snapshot.sqlite" # left behind by 1.0.x
  fxdb < "$SQL_DIR/fx_schema.sql"
  chmod 600 "$FX_DB"
}

ensure_base_currency() {
  if [ -z "$BASE_CURRENCY" ]; then
    BASE_CURRENCY=$(live "SELECT ZSTRINGVALUE FROM ZDOCUMENTPROPERTY WHERE ZNAME = 'homeCurrencyCode' AND ZSTRINGVALUE <> '' LIMIT 1")
    if [ -z "$BASE_CURRENCY" ]; then
      BASE_CURRENCY=$(live "SELECT ZCURRENCY FROM ZACCOUNT WHERE ZDELETIONCOUNT = 0 AND ZCURRENCY IS NOT NULL GROUP BY 1 ORDER BY count(*) DESC LIMIT 1")
    fi
    [ -n "$BASE_CURRENCY" ] || die "could not determine a base currency; set one with: quicken.sh base <CCY>"
    config_set BASE_CURRENCY "$BASE_CURRENCY"
  fi
}

# Every command that reads Quicken data starts here.
require_live() {
  load_config
  [ -n "$QUICKEN_FILE" ] || die "not configured. Run: quicken.sh init <path-to-.quicken>"
  LIVE="$QUICKEN_FILE/data"
  [ -f "$LIVE" ] || die "data file not found: $LIVE"
  check_file_is_open "$LIVE"
  ensure_base_currency
  if [ ! -s "$FX_DB" ]; then ensure_fx_db; load_fx; fi
}

# find / init

cmd_find() {
  {
    if command -v mdfind >/dev/null 2>&1; then
      mdfind "kMDItemFSName == '*.quicken'" 2>/dev/null || true
    fi
    for d in "$HOME/Documents" "$HOME/Library/Mobile Documents/com~apple~CloudDocs" "$HOME/Library/Application Support/Quicken"; do
      [ -d "$d" ] && find "$d" -maxdepth 4 -name '*.quicken' -type d 2>/dev/null
    done
  } | sort -u
}

cmd_init() {
  local p="${1:-}"
  [ -n "$p" ] || die "usage: quicken.sh init <path-to-.quicken>"
  case "$p" in */data) p="${p%/data}" ;; esac
  p="${p%/}"
  [ -f "$p/data" ] || die "no data file inside $p"
  [ -r "$p/data" ] || die "cannot read $p/data (permission denied)"
  head -c 16 "$p/data" | grep -q 'SQLite format 3' || die "$p/data is not a SQLite database"
  check_file_is_open "$p/data"
  config_set QUICKEN_FILE "$p"
  ensure_fx_db
  require_live
  load_fx
  cmd_status
}

# views

# Prints views.sql with the Core Data entity numbers and the user-tag join table of this
# file filled in. They change between Quicken versions, so they are resolved on every run.
render_views() {
  local cf it sm ct ut jt ecol="" tcol=""
  IFS='|' read -r cf it sm ct ut jt <<EOF
$(live "SELECT (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'CashFlowTransaction'),
               (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'InvestmentTransaction'),
               coalesce((SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'SmartCashFlowTransaction'), -1),
               (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'CategoryTag'),
               (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'UserTag'),
               coalesce((SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'Z\_%USERTAGS' ESCAPE '\'
                         AND sql LIKE '%CASHFLOWTRANSACTIONENTRIES%' LIMIT 1), '')")
EOF
  [ -n "$cf" ] && [ -n "$it" ] && [ -n "$ct" ] && [ -n "$ut" ] || die "unexpected schema: entity names not found in Z_PRIMARYKEY"
  if [ -n "$jt" ]; then
    IFS='|' read -r ecol tcol <<EOF
$(live "SELECT coalesce((SELECT name FROM pragma_table_info('$jt') WHERE name LIKE '%CASHFLOWTRANSACTIONENTRIES' LIMIT 1), ''),
               coalesce((SELECT name FROM pragma_table_info('$jt') WHERE name LIKE '%USERTAGS' LIMIT 1), '')")
EOF
  fi
  if [ -z "$jt" ] || [ -z "$ecol" ] || [ -z "$tcol" ]; then
    # No user-tag join table in this file: the tags column stays empty. doctor reports it.
    echo "CREATE TEMP TABLE q_usertags_missing (entry_id INTEGER, tag_id INTEGER);"
    jt=q_usertags_missing; ecol=entry_id; tcol=tag_id
  fi
  sed -e "s/{{ENT_CashFlowTransaction}}/$cf/g" \
      -e "s/{{ENT_InvestmentTransaction}}/$it/g" \
      -e "s/{{ENT_SmartCashFlowTransaction}}/$sm/g" \
      -e "s/{{ENT_CategoryTag}}/$ct/g" \
      -e "s/{{ENT_UserTag}}/$ut/g" \
      -e "s/{{USERTAGS_TABLE}}/$jt/g" \
      -e "s/{{USERTAGS_ENTRY_COL}}/$ecol/g" \
      -e "s/{{USERTAGS_TAG_COL}}/$tcol/g" \
      "$SQL_DIR/views.sql"
}

# Runs a SQL script from stdin against the open Quicken file, read-only, with the rate
# database attached as `fx` and the q_* views created as TEMP objects. Nothing is written.
live_session() { # [base]
  local base="${1:-$BASE_CURRENCY}"
  {
    printf '.bail on\n.timeout 5000\nATTACH %s AS fx;\n' "'$(sql_str "$FX_DB")'"
    printf 'CREATE TEMP TABLE fx_config (base_ccy TEXT NOT NULL);\nINSERT INTO fx_config VALUES (%s);\n' "'$(sql_str "$base")'"
    render_views
    cat
  } | sqlite3 -readonly "$LIVE"
}

qv() { printf '%s\n' "$1" | live_session; }
qv_table() { printf '.headers on\n.mode column\n%s\n' "$1" | live_session; }

# fx

# Rebuild fx_rate from Quicken's own current rate plus the cached CSV series.
load_fx() {
  fxdb "DELETE FROM fx_rate;"
  fxdb "ATTACH 'file:$(sql_str "$(uri_path "$LIVE")")?mode=ro' AS q;
      INSERT OR REPLACE INTO fx_rate
        SELECT ZFROMCURRENCY, ZTOCURRENCY, date(ZQUOTEDATE + $EPOCH_OFFSET, 'unixepoch'),
               coalesce(nullif(ZEXCHANGERATE, 0), ZMANUALEXCHANGERATE), 'quicken'
        FROM q.ZFOREXQUOTE WHERE ZDELETIONCOUNT = 0 AND coalesce(nullif(ZEXCHANGERATE, 0), ZMANUALEXCHANGERATE) > 0;
      INSERT OR REPLACE INTO fx_rate
        SELECT ZTOCURRENCY, ZFROMCURRENCY, date(ZQUOTEDATE + $EPOCH_OFFSET, 'unixepoch'),
               1.0 / coalesce(nullif(ZEXCHANGERATE, 0), ZMANUALEXCHANGERATE), 'quicken'
        FROM q.ZFOREXQUOTE WHERE ZDELETIONCOUNT = 0 AND coalesce(nullif(ZEXCHANGERATE, 0), ZMANUALEXCHANGERATE) > 0;"
  local f name from to
  for f in "$FX_DIR"/*.csv; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .csv)
    from="${name%-*}"; to="${name#*-}"
    fxdb <<SQL
CREATE TEMP TABLE fx_import (date TEXT, rate REAL, source TEXT);
.mode csv
.import --skip 1 '$f' fx_import
INSERT OR REPLACE INTO fx_rate
  SELECT '$from', '$to', date, CAST(rate AS REAL), coalesce(nullif(source, ''), 'csv')
  FROM fx_import WHERE date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND CAST(rate AS REAL) > 0;
SQL
  done
  # Reverse and cross rates derived from the cached series, so a different base currency
  # still gets daily history. Real rows win over derived ones.
  fxdb "INSERT OR IGNORE INTO fx_rate
          SELECT to_ccy, from_ccy, date, 1.0 / rate, source || '-derived' FROM fx_rate WHERE rate > 0;
        INSERT OR IGNORE INTO fx_rate
          SELECT a.from_ccy, b.from_ccy, a.date, a.rate / b.rate, 'cross-derived'
          FROM fx_rate a JOIN fx_rate b ON b.to_ccy = a.to_ccy AND b.date = a.date AND b.from_ccy <> a.from_ccy
          WHERE b.rate > 0 AND a.to_ccy = '$BASE_CURRENCY';"
}

cmd_base() {
  local b; b=$(upper "${1:-}")
  [ -n "$b" ] || die "usage: quicken.sh base <CCY>"
  config_set BASE_CURRENCY "$b"
  if [ -n "$(config_get QUICKEN_FILE)" ]; then require_live; load_fx; fi
  echo "base currency: $b"
  echo "run 'quicken.sh fx sync' to download rates into $b for every other currency"
}

fetch_frankfurter() { # from to since out
  local json="$STATE_DIR/fx.tmp.json"
  curl -fsSL "https://api.frankfurter.dev/v1/$3..?base=$1&symbols=$2" -o "$json" || return 1
  sqlite3 :memory: "SELECT 'date,rate,source';
    SELECT j.key || ',' || json_extract(j.value, '$.$2') || ',frankfurter'
    FROM json_each(json_extract(readfile('$json'), '$.rates')) j
    WHERE json_extract(j.value, '$.$2') IS NOT NULL ORDER BY j.key" > "$4.tmp"
  rm -f "$json"
  [ "$(wc -l < "$4.tmp")" -gt 1 ] || { rm -f "$4.tmp"; return 1; }
  mv "$4.tmp" "$4"
}

fetch_yahoo_symbol() { # symbol since out invert(0|1)
  local json="$STATE_DIR/fx.tmp.json" p1 p2 expr
  p1=$(sqlite3 :memory: "SELECT strftime('%s', '$2')")
  p2=$(sqlite3 :memory: "SELECT strftime('%s', 'now', '+1 day')")
  curl -fsSL -A "Mozilla/5.0" \
    "https://query1.finance.yahoo.com/v8/finance/chart/$1?period1=$p1&period2=$p2&interval=1d" -o "$json" || return 1
  if [ "$4" = 1 ]; then expr="1.0 / c.value"; else expr="c.value"; fi
  # Yahoo stamps a daily FX bar at 23:00 UTC of the previous day (00:00 London); one hour
  # forward lands on the trading day. The current bar is intraday, so cap at today.
  sqlite3 :memory: "SELECT 'date,rate,source';
    SELECT * FROM (
      SELECT date(t.value + 3600, 'unixepoch') AS d, ($expr) AS r
      FROM json_each(json_extract(readfile('$json'), '$.chart.result[0].timestamp')) t
      JOIN json_each(json_extract(readfile('$json'), '$.chart.result[0].indicators.quote[0].close')) c ON c.key = t.key
      WHERE c.value IS NOT NULL AND c.value > 0
    ) WHERE d <= date('now') GROUP BY d HAVING r = max(r) ORDER BY d" | sed -e '1!s/|/,/' -e '1!s/$/,yahoo/' > "$3.tmp" 2>/dev/null || { rm -f "$json" "$3.tmp"; return 1; }
  rm -f "$json"
  [ "$(wc -l < "$3.tmp")" -gt 1 ] || { rm -f "$3.tmp"; return 1; }
  mv "$3.tmp" "$3"
}

fetch_yahoo() { # from to since out
  fetch_yahoo_symbol "$1$2=X" "$3" "$4" 0 || fetch_yahoo_symbol "$2$1=X" "$3" "$4" 1
}

fetch_csv() { # from to since out
  local src; src=$(config_get "FX_CSV_$1_$2")
  [ -n "$src" ] && [ -f "$src" ] || { warn "FX_CSV_$1_$2 is not set or the file is missing"; return 1; }
  { echo "date,rate,source"; awk -F, 'NR > 1 && $1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ { print $1 "," $2 ",csv" }' "$src"; } > "$4"
}

# A daily series whose last date is more than 30 days old cannot be forward-filled safely.
series_is_stale() { # csv
  [ -f "$1" ] || return 0
  local last cutoff
  last=$(tail -n 1 "$1" | cut -d, -f1)
  cutoff=$(sqlite3 :memory: "SELECT date('now', '-30 days')")
  [ "$last" \< "$cutoff" ]
}

sync_pair() { # from to since
  local from="$1" to="$2" since="$3" provider out
  provider=$(config_get "FX_PROVIDER_${from}_${to}")
  [ -n "$provider" ] || provider=frankfurter
  mkdir -p "$FX_DIR"
  out="$FX_DIR/$from-$to.csv"
  echo "fx $from -> $to since $since via $provider"
  case "$provider" in
    frankfurter)
      if ! fetch_frankfurter "$from" "$to" "$since" "$out" || series_is_stale "$out"; then
        warn "frankfurter has no current data for $from/$to, trying yahoo"
        if ! fetch_yahoo "$from" "$to" "$since" "$out.yahoo"; then
          warn "yahoo returned no rates for $from/$to either"
        elif series_is_stale "$out.yahoo"; then
          warn "yahoo series for $from/$to is also stale; keeping the longer one"
          [ -f "$out" ] || mv "$out.yahoo" "$out"
        else
          mv "$out.yahoo" "$out"
        fi
        rm -f "$out.yahoo"
        [ -f "$out" ] || warn "no provider returned rates for $from/$to; only Quicken's current rate will be used"
      fi ;;
    yahoo)   fetch_yahoo "$from" "$to" "$since" "$out" || warn "yahoo returned no rates for $from/$to" ;;
    csv)     fetch_csv "$from" "$to" "$since" "$out" || true ;;
    quicken) rm -f "$out"; echo "  using Quicken's current rate only" ;;
    *)       die "unknown provider '$provider' for $from/$to (use frankfurter, yahoo, csv or quicken)" ;;
  esac
  if [ -f "$out" ]; then
    echo "  $(( $(wc -l < "$out") - 1 )) daily rates cached in $out"
  fi
}

cmd_fx() {
  local sub="${1:-sync}"; shift || true
  case "$sub" in
    sync)
      need curl
      require_live
      local since="" c
      while [ $# -gt 0 ]; do
        case "$1" in --from) since="$2"; shift ;; *) die "unknown option $1" ;; esac
        shift
      done
      [ -n "$since" ] || since=$(qv "SELECT coalesce(min(date), date('now', '-1 year')) FROM q_transaction WHERE kind <> 'scheduled'")
      for c in $(qv "SELECT DISTINCT currency FROM (SELECT currency FROM q_account UNION SELECT currency FROM q_holding) WHERE currency IS NOT NULL AND currency <> '$BASE_CURRENCY'"); do
        sync_pair "$c" "$BASE_CURRENCY" "$since"
      done
      load_fx
      fx_coverage ;;
    provider)
      [ $# -ge 2 ] || die "usage: quicken.sh fx provider <FROM> <frankfurter|yahoo|csv|quicken> [csv-path]"
      require_live
      config_set "FX_PROVIDER_$(upper "$1")_$BASE_CURRENCY" "$2"
      if [ "$2" = csv ]; then
        [ -n "${3:-}" ] || die "csv provider needs a file path: date,rate per line"
        config_set "FX_CSV_$(upper "$1")_$BASE_CURRENCY" "$3"
      fi
      echo "provider for $(upper "$1") -> $BASE_CURRENCY: $2. Run: quicken.sh fx sync" ;;
    *) die "usage: quicken.sh fx sync [--from YYYY-MM-DD] | fx provider <FROM> <provider> [csv-path]" ;;
  esac
}

fx_coverage() {
  echo "fx coverage (pair, source, first, last, days):"
  fxdb -column -header "SELECT from_ccy || '/' || to_ccy AS pair, source, min(date) AS first, max(date) AS last, count(*) AS days
                        FROM fx_rate GROUP BY 1, 2 ORDER BY 1, 2"
}

# sql

cmd_sql() {
  require_live
  local mode=markdown file="" query="" base="" from="" to=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) mode=json ;;
      --csv) mode=csv ;;
      -f) file="$2"; shift ;;
      --base) base=$(upper "$2"); shift ;;
      --from) from="$2"; shift ;;
      --to) to="$2"; shift ;;
      *) query="$1" ;;
    esac
    shift
  done
  [ -n "$file" ] && query=$(cat "$file")
  [ -n "$query" ] || die "usage: quicken.sh sql [-f file.sql | \"SELECT ...\"] [--json|--csv] [--base CCY] [--from D] [--to D]"
  [ -n "$from" ] || from=$(sqlite3 :memory: "SELECT date('now', '-12 months')")
  [ -n "$to" ] || to=$(sqlite3 :memory: "SELECT date('now')")
  [ -n "$base" ] || base="$BASE_CURRENCY"
  if [ "$base" != "$BASE_CURRENCY" ] &&
     [ "$(fxdb "SELECT count(*) FROM fx_rate WHERE to_ccy = '$base' AND source NOT IN ('quicken', 'quicken-derived')")" = 0 ]; then
    warn "no daily rates into $base; amounts convert at Quicken's single current rate. Run: quicken.sh base $base && quicken.sh fx sync"
  fi
  query=$(printf '%s\n' "$query" | sed -e "s/{{from}}/$from/g" -e "s/{{to}}/$to/g" -e "s/{{base}}/$base/g")
  printf '.headers on\n.mode %s\n%s\n' "$mode" "$query" | live_session "$base"
}

# status / doctor

cmd_status() {
  load_config
  echo "file:          ${QUICKEN_FILE:-<not configured>}"
  if [ -z "$QUICKEN_FILE" ]; then
    echo "run: quicken.sh init <path-to-.quicken>"
    return
  fi
  require_live
  echo "rates db:      $FX_DB"
  echo "base currency: $BASE_CURRENCY"
  echo "transactions:  $(qv "SELECT count(*) || ' from ' || min(date) || ' to ' || max(date) FROM q_transaction WHERE kind <> 'scheduled'")"
  echo "accounts by currency (open only):"
  qv_table "SELECT currency, count(*) AS accounts, sum(is_investment) AS investment, sum(is_liability) AS liability
            FROM q_account WHERE closed = 0 GROUP BY 1 ORDER BY 2 DESC"
  fx_coverage
}

cmd_doctor() {
  require_live
  local ok=1 v n err="$STATE_DIR/doctor.err"
  while IFS= read -r v; do
    if n=$(qv "SELECT count(*) FROM $v" 2>"$err"); then
      printf '  ok   %-28s %s rows\n' "$v" "$n"
    else
      printf '  FAIL %-28s %s\n' "$v" "$(tail -n 1 "$err")"; ok=0
    fi
  done < <(sed -n 's/^CREATE TEMP VIEW \(q_[a-z_]*\) AS.*/\1/p' "$SQL_DIR/views.sql")
  rm -f "$err"
  if [ "$(qv "SELECT count(*) FROM sqlite_temp_master WHERE name = 'q_usertags_missing'")" = 1 ]; then
    echo "  WARN user-tag join table not found in this file; the tags column is empty"
  fi
  n=$(qv "SELECT count(*) FROM q_split_base WHERE amount_base IS NULL")
  if [ "$n" -gt 0 ]; then
    echo "  WARN $n split lines have no exchange rate to the base currency. Run: quicken.sh fx sync"; ok=0
  fi
  for v in $(fxdb "SELECT from_ccy || '/' || to_ccy FROM fx_rate GROUP BY from_ccy, to_ccy HAVING max(date) < date('now', '-30 days')"); do
    echo "  WARN exchange rates for $v end more than 30 days ago. Run: quicken.sh fx sync"; ok=0
  done
  for v in $(qv "SELECT c.currency FROM (SELECT currency FROM q_account WHERE closed = 0 UNION SELECT currency FROM q_holding) c
                 CROSS JOIN fx_config f
                 WHERE c.currency IS NOT NULL AND c.currency <> f.base_ccy
                   AND (SELECT count(*) FROM fx.fx_rate r WHERE r.from_ccy = c.currency AND r.to_ccy = f.base_ccy
                        AND r.source NOT IN ('quicken', 'quicken-derived')) = 0"); do
    echo "  WARN only Quicken's single current rate is known for $v; history converts at today's rate. Run: quicken.sh fx sync"; ok=0
  done
  if [ "$ok" = 1 ]; then echo "doctor: all good"; else echo "doctor: issues found"; return 1; fi
}

cmd_help() {
  cat <<'HELP'
usage: quicken.sh <command>

  find                         list .quicken files on this machine
  init <path-to-.quicken>      remember the file, load exchange rates, show status
  status                       file, base currency, accounts by currency, fx coverage
  doctor                       check every view and the exchange-rate coverage
  base <CCY>                   set the base currency for all *_base columns
  fx sync [--from YYYY-MM-DD]  download daily exchange rates for every account currency
  fx provider <FROM> <frankfurter|yahoo|csv|quicken> [csv-path]
  sql [-f file | "query"] [--json|--csv] [--base CCY] [--from D] [--to D]
                               run SQL against the open Quicken file, read-only
                               ({{from}}, {{to}}, {{base}} are substituted)

Queries read the live file, so they always see what Quicken shows. The file must be open in
Quicken. State in ~/.quicken-skills (override with QUICKEN_SKILLS_HOME) holds only the config
and cached exchange rates. The Quicken file is opened read-only and never copied or written.
HELP
}

case "${1:-help}" in
  find) cmd_find ;;
  init) shift; cmd_init "$@" ;;
  status) cmd_status ;;
  doctor) cmd_doctor ;;
  base) shift; cmd_base "$@" ;;
  fx) shift; cmd_fx "$@" ;;
  sql) shift; cmd_sql "$@" ;;
  help|-h|--help) cmd_help ;;
  *) die "unknown command '$1'. Try: quicken.sh help" ;;
esac
