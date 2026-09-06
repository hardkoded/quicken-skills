-- Month-end net worth in the base currency. Cash from q_account_balance_monthly;
-- securities from units rebuilt out of investment transactions and the last price on or
-- before month end (raw ZSECURITYQUOTE is used for speed).
WITH RECURSIVE
cash AS (
  SELECT month, month_end, sum(balance_base) AS cash_base
  FROM q_account_balance_monthly
  WHERE month >= strftime('%Y-%m', '{{from}}')
  GROUP BY 1, 2
),
unit_moves AS (
  SELECT i.account_id, i.security_id, coalesce(s.currency, i.currency) AS currency,
         strftime('%Y-%m', i.date) AS month, sum(i.units) AS units
  FROM q_investment_transaction i
  JOIN q_security s ON s.id = i.security_id
  WHERE i.units IS NOT NULL AND i.units <> 0
  GROUP BY 1, 2, 3, 4
),
positions AS (SELECT DISTINCT account_id, security_id, currency FROM unit_moves),
cells AS (
  SELECT c.month, c.month_end, p.account_id, p.security_id, p.currency,
         (SELECT sum(u.units) FROM unit_moves u
           WHERE u.account_id = p.account_id AND u.security_id = p.security_id AND u.month <= c.month) AS units
  FROM cash c CROSS JOIN positions p
),
valued AS (
  SELECT x.month, x.currency,
         x.units * (SELECT q.ZCLOSINGPRICE FROM ZSECURITYQUOTE q
                     WHERE q.ZSECURITY = x.security_id AND q.ZDELETIONCOUNT = 0 AND q.ZCLOSINGPRICE IS NOT NULL
                       AND q.ZQUOTEDATE <= strftime('%s', x.month_end) - 978307200
                     ORDER BY q.ZQUOTEDATE DESC LIMIT 1) AS value,
         CASE WHEN x.currency = f.base_ccy THEN 1.0
              ELSE coalesce(
                (SELECT rate FROM fx_rate r WHERE r.from_ccy = x.currency AND r.to_ccy = f.base_ccy AND r.date <= x.month_end ORDER BY r.date DESC LIMIT 1),
                (SELECT rate FROM fx_rate r WHERE r.from_ccy = x.currency AND r.to_ccy = f.base_ccy ORDER BY r.date ASC LIMIT 1)) END AS fx
  FROM cells x CROSS JOIN fx_config f
  WHERE abs(coalesce(x.units, 0)) > 0.000001
),
sec AS (SELECT month, sum(value * fx) AS securities_base FROM valued GROUP BY 1)
SELECT c.month, round(c.cash_base) AS cash_{{base}}, round(coalesce(s.securities_base, 0)) AS securities_{{base}},
       round(c.cash_base + coalesce(s.securities_base, 0)) AS net_worth_{{base}}
FROM cash c LEFT JOIN sec s ON s.month = c.month
ORDER BY c.month;
