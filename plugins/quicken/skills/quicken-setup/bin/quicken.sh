#!/usr/bin/env bash
# Read-only access to a Quicken for Mac data file for AI skills.
# Works on macOS bash 3.2 and Linux. Needs sqlite3; fx sync also needs curl.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$SCRIPT_DIR/../sql"
STATE_DIR="${QUICKEN_SKILLS_HOME:-$HOME/.quicken-skills}"
CONFIG="$STATE_DIR/config"
SNAPSHOT="$STATE_DIR/snapshot.sqlite"
FX_DIR="$STATE_DIR/fx"
EPOCH_OFFSET=978307200

QUICKEN_FILE=""
BASE_CURRENCY=""
SNAPSHOT_AT=0

die() { echo "quicken: $*" >&2; exit 1; }
warn() { echo "quicken: $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
sq() { require_snapshot; sqlite3 "$SNAPSHOT" "$@"; }
sq_ro() { require_snapshot; sqlite3 -readonly "$SNAPSHOT" "$@"; }

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

snapshot_ready=0
require_snapshot() {
  [ "$snapshot_ready" = 1 ] || [ -s "$SNAPSHOT" ] || die "no snapshot yet. Run: quicken.sh init <path-to-.quicken>"
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
  head -c 16 "$p/data" | grep -q 'SQLite format 3' || die "$p/data is not a SQLite database"
  check_file_is_open "$p/data"
  config_set QUICKEN_FILE "$p"
  cmd_snapshot
  cmd_status
}

# snapshot

ent_id() {
  sq "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = '$1' LIMIT 1"
}

render_views() {
  local cf it sm ct ut jt ecol tcol
  cf=$(ent_id CashFlowTransaction)
  it=$(ent_id InvestmentTransaction)
  sm=$(ent_id SmartCashFlowTransaction)
  ct=$(ent_id CategoryTag)
  ut=$(ent_id UserTag)
  [ -n "$cf" ] && [ -n "$it" ] && [ -n "$ct" ] && [ -n "$ut" ] || die "unexpected schema: entity names not found in Z_PRIMARYKEY"
  [ -n "$sm" ] || sm=-1
  jt=$(sq "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'Z\_%USERTAGS' ESCAPE '\' AND sql LIKE '%CASHFLOWTRANSACTIONENTRIES%' LIMIT 1")
  if [ -n "$jt" ]; then
    ecol=$(sq "SELECT name FROM pragma_table_info('$jt') WHERE name LIKE '%CASHFLOWTRANSACTIONENTRIES' LIMIT 1")
    tcol=$(sq "SELECT name FROM pragma_table_info('$jt') WHERE name LIKE '%USERTAGS' LIMIT 1")
  fi
  if [ -z "${jt:-}" ] || [ -z "${ecol:-}" ] || [ -z "${tcol:-}" ]; then
    warn "user-tag join table not found; tags column will be empty"
    sq "CREATE TABLE IF NOT EXISTS q_usertags_missing (entry_id INTEGER, tag_id INTEGER)"
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

ensure_base_currency() {
  load_config
  if [ -z "$BASE_CURRENCY" ]; then
    BASE_CURRENCY=$(sq "SELECT ZSTRINGVALUE FROM ZDOCUMENTPROPERTY WHERE ZNAME = 'homeCurrencyCode' AND ZSTRINGVALUE <> '' LIMIT 1")
    if [ -z "$BASE_CURRENCY" ]; then
      BASE_CURRENCY=$(sq "SELECT currency FROM q_account WHERE currency IS NOT NULL GROUP BY 1 ORDER BY count(*) DESC LIMIT 1")
    fi
    [ -n "$BASE_CURRENCY" ] || die "could not determine a base currency; set one with: quicken.sh base <CCY>"
    config_set BASE_CURRENCY "$BASE_CURRENCY"
  fi
}

# Load fx_config and fx_rate into the snapshot from Quicken's own rate plus cached CSVs.
load_fx() {
  ensure_base_currency
  sq "DELETE FROM fx_config; INSERT INTO fx_config VALUES ('$BASE_CURRENCY'); DELETE FROM fx_rate;"
  sq "INSERT OR REPLACE INTO fx_rate
        SELECT ZFROMCURRENCY, ZTOCURRENCY, date(ZQUOTEDATE + $EPOCH_OFFSET, 'unixepoch'),
               coalesce(nullif(ZEXCHANGERATE, 0), ZMANUALEXCHANGERATE), 'quicken'
        FROM ZFOREXQUOTE WHERE ZDELETIONCOUNT = 0 AND coalesce(nullif(ZEXCHANGERATE, 0), ZMANUALEXCHANGERATE) > 0;
      INSERT OR REPLACE INTO fx_rate
        SELECT ZTOCURRENCY, ZFROMCURRENCY, date(ZQUOTEDATE + $EPOCH_OFFSET, 'unixepoch'),
               1.0 / coalesce(nullif(ZEXCHANGERATE, 0), ZMANUALEXCHANGERATE), 'quicken'
        FROM ZFOREXQUOTE WHERE ZDELETIONCOUNT = 0 AND coalesce(nullif(ZEXCHANGERATE, 0), ZMANUALEXCHANGERATE) > 0;"
  local f name from to
  for f in "$FX_DIR"/*.csv; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .csv)
    from="${name%-*}"; to="${name#*-}"
    sq <<SQL
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
  sq "INSERT OR IGNORE INTO fx_rate
        SELECT to_ccy, from_ccy, date, 1.0 / rate, source || '-derived' FROM fx_rate WHERE rate > 0;
      INSERT OR IGNORE INTO fx_rate
        SELECT a.from_ccy, b.from_ccy, a.date, a.rate / b.rate, 'cross-derived'
        FROM fx_rate a JOIN fx_rate b ON b.to_ccy = a.to_ccy AND b.date = a.date AND b.from_ccy <> a.from_ccy
        WHERE b.rate > 0 AND a.to_ccy = '$BASE_CURRENCY';"
}

# Quicken keeps the data file populated only while the file is open in Quicken.
# A closed file has a handful of metadata tables and no accounts.
check_file_is_open() {
  local n
  n=$(sqlite3 -readonly "file:$1?immutable=1" "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'ZACCOUNT'" 2>/dev/null || echo 0)
  [ "$n" = 1 ] || die "the data file has no account table. Open the file in Quicken and try again."
}

cmd_snapshot() {
  load_config
  [ -n "$QUICKEN_FILE" ] || die "not configured. Run: quicken.sh init <path-to-.quicken>"
  local live="$QUICKEN_FILE/data" tmp="$SNAPSHOT.tmp"
  [ -f "$live" ] || die "data file not found: $live"
  check_file_is_open "$live"
  mkdir -p "$STATE_DIR"
  rm -f "$tmp"
  if ! sqlite3 -readonly "$live" ".backup '$tmp'" 2>/dev/null; then
    warn "live file is locked; reading it as immutable (very recent edits may be missing)"
    rm -f "$tmp"
    sqlite3 -readonly "file:$live?immutable=1" ".backup '$tmp'" || die "could not read $live"
  fi
  mv "$tmp" "$SNAPSHOT"
  chmod 600 "$SNAPSHOT"
  snapshot_ready=1
  sq < "$SQL_DIR/fx_schema.sql"
  render_views | sq
  load_fx
  config_set SNAPSHOT_AT "$(date +%s)"
  echo "snapshot refreshed: $SNAPSHOT"
}

cmd_base() {
  local b; b=$(upper "${1:-}")
  [ -n "$b" ] || die "usage: quicken.sh base <CCY>"
  config_set BASE_CURRENCY "$b"
  BASE_CURRENCY="$b"
  if [ -s "$SNAPSHOT" ]; then load_fx; fi
  echo "base currency: $b"
  echo "run 'quicken.sh fx sync' to download rates into $b for every other currency"
}

# fx

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
      require_snapshot
      ensure_base_currency
      local since="" c
      while [ $# -gt 0 ]; do
        case "$1" in --from) since="$2"; shift ;; *) die "unknown option $1" ;; esac
        shift
      done
      [ -n "$since" ] || since=$(sq "SELECT coalesce(min(date), date('now', '-1 year')) FROM q_transaction WHERE kind <> 'scheduled'")
      for c in $(sq "SELECT DISTINCT currency FROM (SELECT currency FROM q_account UNION SELECT currency FROM q_holding) WHERE currency IS NOT NULL AND currency <> '$BASE_CURRENCY'"); do
        sync_pair "$c" "$BASE_CURRENCY" "$since"
      done
      load_fx
      fx_coverage ;;
    provider)
      [ $# -ge 2 ] || die "usage: quicken.sh fx provider <FROM> <frankfurter|yahoo|csv|quicken> [csv-path]"
      require_snapshot
      ensure_base_currency
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
  sq -column -header "SELECT from_ccy || '/' || to_ccy AS pair, source, min(date) AS first, max(date) AS last, count(*) AS days
                      FROM fx_rate GROUP BY 1, 2 ORDER BY 1, 2"
}

# sql

cmd_sql() {
  require_snapshot
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
  local configured; configured=$(sq_ro "SELECT base_ccy FROM fx_config LIMIT 1")
  [ -n "$base" ] || base="$configured"
  query=$(printf '%s\n' "$query" | sed -e "s/{{from}}/$from/g" -e "s/{{to}}/$to/g" -e "s/{{base}}/$base/g")
  if [ "$base" = "$configured" ]; then
    printf '.bail on\n.headers on\n.mode %s\n%s\n' "$mode" "$query" | sq_ro
  else
    # Temporary base switch: the views read fx_config, so update it inside a rolled-back transaction.
    if [ "$(sq_ro "SELECT count(*) FROM fx_rate WHERE to_ccy = '$base' AND source NOT IN ('quicken', 'quicken-derived')")" = 0 ]; then
      warn "no daily rates into $base; amounts convert at Quicken's single current rate. Run: quicken.sh base $base && quicken.sh fx sync"
    fi
    {
      printf '.bail on\n.headers on\n.mode %s\n' "$mode"
      printf 'BEGIN;\nUPDATE fx_config SET base_ccy = %s;\n' "'$base'"
      printf '%s\n;\nROLLBACK;\n' "$query"
    } | sq
  fi
}

# status / doctor

snapshot_age_hours() {
  load_config
  echo $(( ( $(date +%s) - ${SNAPSHOT_AT:-0} ) / 3600 ))
}

cmd_status() {
  load_config
  echo "file:          ${QUICKEN_FILE:-<not configured>}"
  if [ -f "$SNAPSHOT" ]; then
    echo "snapshot:      $SNAPSHOT ($(snapshot_age_hours)h old)"
    echo "base currency: $(sq "SELECT base_ccy FROM fx_config LIMIT 1")"
    echo "transactions:  $(sq "SELECT count(*) || ' from ' || min(date) || ' to ' || max(date) FROM q_transaction WHERE kind <> 'scheduled'")"
    echo "accounts by currency (open only):"
    sq -column -header "SELECT currency, count(*) AS accounts, sum(is_investment) AS investment, sum(is_liability) AS liability
                        FROM q_account WHERE closed = 0 GROUP BY 1 ORDER BY 2 DESC"
    fx_coverage
  else
    echo "snapshot:      none. Run: quicken.sh init <path-to-.quicken>"
  fi
}

cmd_doctor() {
  require_snapshot
  local ok=1 v n
  for v in $(sq "SELECT name FROM sqlite_master WHERE type = 'view' AND name LIKE 'q\_%' ESCAPE '\' ORDER BY name"); do
    if n=$(sq "SELECT count(*) FROM $v" 2>&1); then
      printf '  ok   %-28s %s rows\n' "$v" "$n"
    else
      printf '  FAIL %-28s %s\n' "$v" "$n"; ok=0
    fi
  done
  n=$(sq "SELECT count(*) FROM q_split_base WHERE amount_base IS NULL")
  if [ "$n" -gt 0 ]; then
    echo "  WARN $n split lines have no exchange rate to the base currency. Run: quicken.sh fx sync"; ok=0
  fi
  for v in $(sq "SELECT from_ccy || '/' || to_ccy FROM fx_rate GROUP BY from_ccy, to_ccy HAVING max(date) < date('now', '-30 days')"); do
    echo "  WARN exchange rates for $v end more than 30 days ago. Run: quicken.sh fx sync"; ok=0
  done
  for v in $(sq "SELECT c.currency FROM (SELECT currency FROM q_account WHERE closed = 0 UNION SELECT currency FROM q_holding) c
                 CROSS JOIN fx_config f
                 WHERE c.currency IS NOT NULL AND c.currency <> f.base_ccy
                   AND (SELECT count(*) FROM fx_rate r WHERE r.from_ccy = c.currency AND r.to_ccy = f.base_ccy
                        AND r.source NOT IN ('quicken', 'quicken-derived')) = 0"); do
    echo "  WARN only Quicken's single current rate is known for $v; history converts at today's rate. Run: quicken.sh fx sync"; ok=0
  done
  local age; age=$(snapshot_age_hours)
  if [ "$age" -ge 24 ]; then echo "  WARN snapshot is ${age}h old. Run: quicken.sh snapshot"; fi
  if [ "$ok" = 1 ]; then echo "doctor: all good"; else echo "doctor: issues found"; return 1; fi
}

cmd_help() {
  cat <<'HELP'
usage: quicken.sh <command>

  find                         list .quicken files on this machine
  init <path-to-.quicken>      remember the file, take a snapshot, show status
  snapshot                     refresh the read-only snapshot and rebuild the q_* views
  status                       file, snapshot age, accounts by currency, fx coverage
  doctor                       check every view, fx coverage, snapshot age
  base <CCY>                   set the base currency for all *_base columns
  fx sync [--from YYYY-MM-DD]  download daily exchange rates for every account currency
  fx provider <FROM> <frankfurter|yahoo|csv|quicken> [csv-path]
  sql [-f file | "query"] [--json|--csv] [--base CCY] [--from D] [--to D]
                               run SQL against the snapshot ({{from}}, {{to}}, {{base}} are substituted)

State lives in ~/.quicken-skills (override with QUICKEN_SKILLS_HOME). The live Quicken file is never written.
HELP
}

case "${1:-help}" in
  find) cmd_find ;;
  init) shift; cmd_init "$@" ;;
  snapshot) cmd_snapshot ;;
  status) cmd_status ;;
  doctor) cmd_doctor ;;
  base) shift; cmd_base "$@" ;;
  fx) shift; cmd_fx "$@" ;;
  sql) shift; cmd_sql "$@" ;;
  help|-h|--help) cmd_help ;;
  *) die "unknown command '$1'. Try: quicken.sh help" ;;
esac
