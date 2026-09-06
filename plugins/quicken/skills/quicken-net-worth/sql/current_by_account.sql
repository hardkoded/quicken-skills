WITH cash AS (
  SELECT account_id, sum(amount) AS balance
  FROM q_transaction WHERE kind <> 'scheduled' AND date <= date('now')
  GROUP BY 1
),
hold AS (
  SELECT account_id, sum(value) AS value, sum(value_base) AS value_base
  FROM q_holding GROUP BY 1
),
acct AS (
  SELECT a.id, a.name, a.type, a.currency, a.is_liability,
         coalesce(c.balance, 0) AS cash, coalesce(h.value, 0) AS securities, coalesce(h.value_base, 0) AS securities_base,
         CASE WHEN a.currency = f.base_ccy THEN 1.0
              ELSE (SELECT rate FROM fx_rate r WHERE r.from_ccy = a.currency AND r.to_ccy = f.base_ccy ORDER BY date DESC LIMIT 1) END AS fx
  FROM q_account a
  CROSS JOIN fx_config f
  LEFT JOIN cash c ON c.account_id = a.id
  LEFT JOIN hold h ON h.account_id = a.id
  WHERE a.closed = 0
)
SELECT name AS account, type, currency,
       round(cash, 2) AS cash, round(securities, 2) AS securities,
       round(cash + securities, 2) AS total,
       round(cash * fx + securities_base) AS total_{{base}}
FROM acct
WHERE abs(cash) + abs(securities) > 0.005
ORDER BY total_{{base}} DESC;
