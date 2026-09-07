-- Normalized read-only views over the Quicken for Mac Core Data store.
-- This file is a template. quicken.sh resolves the {{...}} placeholders from the open
-- Quicken file (Z_PRIMARYKEY and sqlite_master) on every run, because
-- Core Data entity numbers change between Quicken versions.
-- The views are TEMP: they exist only for one sqlite3 session and nothing is stored in
-- the Quicken file. fx_config is a TEMP table filled by quicken.sh; fx_rate and
-- q_fx_latest live in ~/.quicken-skills/fx.sqlite, attached as `fx`.
--
-- Dates: Core Data stores seconds since 2001-01-01 UTC. Quicken writes them at
-- UTC noon (or midnight), so date(x + 978307200, 'unixepoch') is the calendar day.
-- ZENTEREDDATE is the transaction date and is always set. ZPOSTEDDATE is only set
-- on downloaded transactions (the bank's posting date).

CREATE TEMP VIEW q_account AS
SELECT a.Z_PK                       AS id,
       a.ZNAME                      AS name,
       a.ZTYPENAME                  AS type,
       a.ZCURRENCY                  AS currency,
       a.ZCLOSED                    AS closed,
       a.ZACTIVE                    AS active,
       CASE WHEN a.ZTYPENAME LIKE 'BROKERAGE%' THEN 1 ELSE 0 END                         AS is_investment,
       CASE WHEN a.ZTYPENAME IN ('CREDITCARD', 'LIABILITY') OR a.ZTYPENAME LIKE 'LOAN%' THEN 1 ELSE 0 END AS is_liability,
       a.ZCREDITLIMIT               AS credit_limit,
       fi.ZNAME                     AS institution,
       date(a.ZONLINEBANKINGLASTCONNECTEDTIMESTAMP + 978307200, 'unixepoch') AS last_download_date,
       a.ZONLINEBANKINGLEDGERBALANCEAMOUNT AS bank_reported_balance,
       a.ZNOTES                     AS notes
FROM ZACCOUNT a
LEFT JOIN ZFINANCIALINSTITUTION fi ON fi.Z_PK = a.ZFINANCIALINSTITUTION
WHERE a.ZDELETIONCOUNT = 0;

CREATE TEMP VIEW q_category AS
WITH RECURSIVE c AS (
  SELECT Z_PK AS id, ZNAME AS name, ZNAME AS full_name, ZPARENTCATEGORY AS parent_id, 0 AS depth,
         ZTYPE AS type_code, ZHIDDEN AS hidden, ZTAXREFUS AS tax_ref_us, ZTAXREFCA AS tax_ref_ca
  FROM ZTAG
  WHERE Z_ENT = {{ENT_CategoryTag}} AND ZDELETIONCOUNT = 0
    AND (ZPARENTCATEGORY IS NULL OR ZPARENTCATEGORY NOT IN
         (SELECT Z_PK FROM ZTAG WHERE Z_ENT = {{ENT_CategoryTag}} AND ZDELETIONCOUNT = 0))
  UNION ALL
  SELECT t.Z_PK, t.ZNAME, c.full_name || ':' || t.ZNAME, t.ZPARENTCATEGORY, c.depth + 1,
         t.ZTYPE, t.ZHIDDEN, t.ZTAXREFUS, t.ZTAXREFCA
  FROM ZTAG t
  JOIN c ON t.ZPARENTCATEGORY = c.id
  WHERE t.Z_ENT = {{ENT_CategoryTag}} AND t.ZDELETIONCOUNT = 0
)
SELECT id, name, full_name, parent_id, depth,
       CASE type_code WHEN 1 THEN 'expense' WHEN 2 THEN 'income' ELSE 'system' END AS kind,
       hidden, tax_ref_us, tax_ref_ca
FROM c;

CREATE TEMP VIEW q_tag AS
SELECT Z_PK AS id, ZNAME AS name, ZUSERDESCRIPTION AS description
FROM ZTAG
WHERE Z_ENT = {{ENT_UserTag}} AND ZDELETIONCOUNT = 0;

CREATE TEMP VIEW q_payee AS
SELECT Z_PK AS id, ZNAME AS name
FROM ZUSERPAYEE
WHERE ZDELETIONCOUNT = 0;

CREATE TEMP VIEW q_security AS
SELECT s.Z_PK       AS id,
       s.ZNAME      AS name,
       s.ZTICKER    AS ticker,
       s.ZCURRENCY  AS currency,
       s.ZTYPE      AS type_code,
       s.ZISSUETYPE AS issue_type,
       s.ZASSETCLASS AS asset_class,
       s.ZWATCHLIST AS watchlist
FROM ZSECURITY s
WHERE s.ZDELETIONCOUNT = 0;

CREATE TEMP VIEW q_transaction AS
SELECT t.Z_PK          AS id,
       t.ZQUICKENID    AS quicken_id,
       date(t.ZENTEREDDATE + 978307200, 'unixepoch') AS date,
       date(t.ZPOSTEDDATE + 978307200, 'unixepoch')  AS posted_date,
       t.ZACCOUNT      AS account_id,
       a.ZNAME         AS account,
       a.ZCURRENCY     AS currency,
       t.ZUSERPAYEE    AS payee_id,
       p.ZNAME         AS payee,
       t.ZAMOUNT       AS amount,
       t.ZNOTE         AS note,
       t.ZCHECKNUMBER  AS check_number,
       CASE t.Z_ENT
         WHEN {{ENT_CashFlowTransaction}}      THEN 'cashflow'
         WHEN {{ENT_InvestmentTransaction}}    THEN 'investment'
         WHEN {{ENT_SmartCashFlowTransaction}} THEN 'scheduled'
         ELSE 'other' END AS kind,
       t.ZRECONCILESTATUS AS reconcile_code,
       CASE t.ZRECONCILESTATUS WHEN 2 THEN 'reconciled' WHEN 1 THEN 'cleared' WHEN 0 THEN 'uncleared' END AS status,
       t.ZEXCLUDEFROMREPORTS AS excluded,
       CASE WHEN t.ZFITRANSACTION IS NOT NULL THEN 1 ELSE 0 END AS downloaded
FROM ZTRANSACTION t
JOIN ZACCOUNT a ON a.Z_PK = t.ZACCOUNT AND a.ZDELETIONCOUNT = 0
LEFT JOIN ZUSERPAYEE p ON p.Z_PK = t.ZUSERPAYEE
WHERE t.ZDELETIONCOUNT = 0;

-- One row per split line. This is the grain for spending and income analysis.
-- Investment transactions also have one split whose category is the action
-- (Buy, Sell, Dividend Income, ...). Filter on kind or category_kind as needed.
CREATE TEMP VIEW q_split AS
SELECT e.Z_PK            AS id,
       e.ZPARENT         AS transaction_id,
       tx.date,
       tx.account_id,
       tx.account,
       tx.currency,
       tx.payee_id,
       tx.payee,
       tx.kind,
       e.ZCATEGORYTAG    AS category_id,
       c.full_name       AS category,
       c.name            AS category_leaf,
       c.kind            AS category_kind,
       e.ZAMOUNT         AS amount,
       e.ZNOTE           AS note,
       CASE WHEN e.ZTRANSFER IS NOT NULL THEN 1 ELSE 0 END AS is_transfer,
       coalesce(ot.ZACCOUNT, na.Z_PK) AS transfer_account_id,
       coalesce(oa.ZNAME, na.ZNAME)   AS transfer_account,
       (SELECT group_concat(ut.ZNAME, ', ')
          FROM {{USERTAGS_TABLE}} j
          JOIN ZTAG ut ON ut.Z_PK = j.{{USERTAGS_TAG_COL}}
         WHERE j.{{USERTAGS_ENTRY_COL}} = e.Z_PK) AS tags,
       tx.status,
       tx.excluded
FROM ZCASHFLOWTRANSACTIONENTRY e
JOIN q_transaction tx ON tx.id = e.ZPARENT
LEFT JOIN q_category c ON c.id = e.ZCATEGORYTAG
LEFT JOIN ZCASHFLOWTRANSACTIONENTRY oe
       ON e.ZTRANSFER GLOB '[0-9]*'
      AND oe.ZQUICKENID = CAST(e.ZTRANSFER AS INTEGER)
      AND oe.ZDELETIONCOUNT = 0
LEFT JOIN ZTRANSACTION ot ON ot.Z_PK = oe.ZPARENT
LEFT JOIN ZACCOUNT oa ON oa.Z_PK = ot.ZACCOUNT
-- Older files store the counterpart account's name instead of a line id.
LEFT JOIN ZACCOUNT na
       ON e.ZTRANSFER IS NOT NULL AND NOT (e.ZTRANSFER GLOB '[0-9]*')
      AND na.ZNAME = trim(e.ZTRANSFER, ' ' || char(9))
      AND na.ZDELETIONCOUNT = 0
WHERE e.ZDELETIONCOUNT = 0
  AND tx.kind <> 'scheduled';

-- q_split plus the amount converted to the base currency at the transaction date.
-- Rate lookup: latest rate on or before the date; if none, the earliest rate known.
CREATE TEMP VIEW q_split_base AS
SELECT x.*, round(x.amount * x.fx_rate, 2) AS amount_base
FROM (
  SELECT s.*,
         c.base_ccy AS base_currency,
         CASE WHEN s.currency = c.base_ccy THEN 1.0
              ELSE coalesce(
                (SELECT f.rate FROM fx.fx_rate f
                  WHERE f.from_ccy = s.currency AND f.to_ccy = c.base_ccy AND f.date <= s.date
                  ORDER BY f.date DESC LIMIT 1),
                (SELECT f.rate FROM fx.fx_rate f
                  WHERE f.from_ccy = s.currency AND f.to_ccy = c.base_ccy
                  ORDER BY f.date ASC LIMIT 1))
         END AS fx_rate
  FROM q_split s
  CROSS JOIN fx_config c
) x;

CREATE TEMP VIEW q_quote AS
SELECT ZSECURITY AS security_id,
       date(ZQUOTEDATE + 978307200, 'unixepoch') AS date,
       max(ZCLOSINGPRICE) AS close
FROM ZSECURITYQUOTE
WHERE ZDELETIONCOUNT = 0 AND ZCLOSINGPRICE IS NOT NULL
GROUP BY 1, 2;

CREATE TEMP VIEW q_quote_latest AS
SELECT q.security_id, q.date, q.close
FROM q_quote q
JOIN (SELECT security_id, max(date) AS date FROM q_quote GROUP BY 1) m
  ON m.security_id = q.security_id AND m.date = q.date;

-- Current holdings in open accounts from Quicken's lots (lots already reflect stock splits).
-- Values are in the security currency; value_base uses the latest known rate.
CREATE TEMP VIEW q_holding AS
SELECT h.*, round(h.value * h.fx_rate, 2) AS value_base
FROM (
  SELECT p.Z_PK                          AS position_id,
         a.id                            AS account_id,
         a.name                          AS account,
         s.id                            AS security_id,
         s.name                          AS security,
         s.ticker,
         coalesce(s.currency, a.currency) AS currency,
         l.units,
         q.close                         AS price,
         q.date                          AS price_date,
         round(l.units * q.close, 2)     AS value,
         l.cost_basis,
         round(l.units * q.close - l.cost_basis, 2) AS unrealized_gain,
         s.asset_class,
         c.base_ccy                      AS base_currency,
         CASE WHEN coalesce(s.currency, a.currency) = c.base_ccy THEN 1.0 ELSE r.rate END AS fx_rate
  FROM ZPOSITION p
  JOIN (SELECT ZPOSITION AS position_id, sum(ZLATESTUNITS) AS units, sum(ZLATESTCOSTBASIS) AS cost_basis
          FROM ZLOT WHERE ZDELETIONCOUNT = 0 GROUP BY 1) l ON l.position_id = p.Z_PK
  JOIN q_account a  ON a.id = p.ZACCOUNT
  JOIN q_security s ON s.id = p.ZSECURITY
  LEFT JOIN q_quote_latest q ON q.security_id = s.id
  CROSS JOIN fx_config c
  LEFT JOIN fx.q_fx_latest r ON r.from_ccy = coalesce(s.currency, a.currency) AND r.to_ccy = c.base_ccy
  WHERE p.ZDELETIONCOUNT = 0 AND a.closed = 0 AND abs(l.units) > 0.000001
) h;

CREATE TEMP VIEW q_investment_transaction AS
SELECT t.Z_PK        AS id,
       tx.date,
       tx.account_id,
       tx.account,
       tx.currency,
       s.id          AS security_id,
       s.name        AS security,
       s.ticker,
       t.ZTYPE       AS action_code,
       coalesce(
         (SELECT g.ZNAME FROM ZCASHFLOWTRANSACTIONENTRY e JOIN ZTAG g ON g.Z_PK = e.ZCATEGORYTAG
           WHERE e.ZPARENT = t.Z_PK AND e.ZDELETIONCOUNT = 0 ORDER BY e.ZSEQUENCENUMBER LIMIT 1),
         CASE t.ZTYPE WHEN 2 THEN 'Add Shares' WHEN 3 THEN 'Buy' WHEN 5 THEN 'Buy to Cover'
                      WHEN 6 THEN 'Margin Interest Expense' WHEN 10 THEN 'Dividend Income'
                      WHEN 11 THEN 'Interest Income' WHEN 17 THEN 'Remove Shares' WHEN 19 THEN 'Sell'
                      WHEN 21 THEN 'Short Sell' WHEN 23 THEN 'Stock Split' END) AS action,
       t.ZUNITS      AS units,
       t.ZAMOUNT     AS amount,
       t.ZCOSTBASIS  AS cost_basis,
       t.ZCOMMISSION AS commission,
       tx.note
FROM ZTRANSACTION t
JOIN q_transaction tx ON tx.id = t.Z_PK
LEFT JOIN ZPOSITION p ON p.Z_PK = t.ZPOSITION
LEFT JOIN q_security s ON s.id = p.ZSECURITY
WHERE tx.kind = 'investment';

-- Month-end balance of every account, from the sum of transaction amounts.
-- Brokerage accounts: this is the cash side only; add q_holding for securities.
CREATE TEMP VIEW q_account_balance_monthly AS
WITH RECURSIVE
bounds AS (
  SELECT strftime('%Y-%m-01', min(date)) AS first_month,
         strftime('%Y-%m-01', max(max(date), date('now'))) AS last_month
  FROM q_transaction WHERE kind <> 'scheduled'
),
months(month_start) AS (
  SELECT first_month FROM bounds
  UNION ALL
  SELECT date(month_start, '+1 month') FROM months, bounds WHERE month_start < last_month
),
per_month AS (
  SELECT account_id, strftime('%Y-%m-01', date) AS month_start, sum(amount) AS delta
  FROM q_transaction WHERE kind <> 'scheduled'
  GROUP BY 1, 2
),
running AS (
  SELECT account_id, month_start,
         sum(delta) OVER (PARTITION BY account_id ORDER BY month_start) AS balance
  FROM per_month
),
cells AS (
  SELECT strftime('%Y-%m', mo.month_start)          AS month,
         date(mo.month_start, '+1 month', '-1 day') AS month_end,
         a.id AS account_id, a.name AS account, a.type, a.currency, a.is_investment, a.is_liability,
         coalesce((SELECT r.balance FROM running r
                    WHERE r.account_id = a.id AND r.month_start <= mo.month_start
                    ORDER BY r.month_start DESC LIMIT 1), 0) AS balance,
         c.base_ccy AS base_currency
  FROM months mo
  CROSS JOIN q_account a
  CROSS JOIN fx_config c
)
SELECT x.*, round(x.balance * x.fx_rate, 2) AS balance_base
FROM (
  SELECT cells.*,
         CASE WHEN currency = base_currency THEN 1.0
              ELSE coalesce(
                (SELECT f.rate FROM fx.fx_rate f
                  WHERE f.from_ccy = cells.currency AND f.to_ccy = cells.base_currency AND f.date <= cells.month_end
                  ORDER BY f.date DESC LIMIT 1),
                (SELECT f.rate FROM fx.fx_rate f
                  WHERE f.from_ccy = cells.currency AND f.to_ccy = cells.base_currency
                  ORDER BY f.date ASC LIMIT 1))
         END AS fx_rate
  FROM cells
) x;

-- Scheduled (not yet posted) transactions.
CREATE TEMP VIEW q_scheduled AS
SELECT t.Z_PK AS id,
       date(t.ZENTEREDDATE + 978307200, 'unixepoch') AS next_date,
       a.ZNAME AS account, a.ZCURRENCY AS currency,
       p.ZNAME AS payee, t.ZAMOUNT AS amount, t.ZNOTE AS note,
       t.ZRECURRENCEJSON AS recurrence_json
FROM ZTRANSACTION t
JOIN ZACCOUNT a ON a.Z_PK = t.ZACCOUNT
LEFT JOIN ZUSERPAYEE p ON p.Z_PK = t.ZUSERPAYEE
WHERE t.Z_ENT = {{ENT_SmartCashFlowTransaction}} AND t.ZDELETIONCOUNT = 0;
