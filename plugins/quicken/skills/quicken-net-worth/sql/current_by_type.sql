WITH cash AS (
  SELECT account_id, sum(amount) AS balance
  FROM q_transaction WHERE kind <> 'scheduled' AND date <= date('now') GROUP BY 1
),
hold AS (SELECT account_id, sum(value_base) AS value_base FROM q_holding GROUP BY 1),
acct AS (
  SELECT a.type, a.is_liability,
         coalesce(c.balance, 0) * CASE WHEN a.currency = f.base_ccy THEN 1.0 ELSE fx.rate END
           + coalesce(h.value_base, 0) AS total_base
  FROM q_account a
  CROSS JOIN fx_config f
  LEFT JOIN q_fx_latest fx ON fx.from_ccy = a.currency AND fx.to_ccy = f.base_ccy
  LEFT JOIN cash c ON c.account_id = a.id
  LEFT JOIN hold h ON h.account_id = a.id
  WHERE a.closed = 0
)
SELECT * FROM (
  SELECT type, 0 AS rank, count(*) AS accounts, round(sum(total_base)) AS total_{{base}} FROM acct GROUP BY 1
  UNION ALL
  SELECT 'ASSETS', 1, count(*), round(sum(total_base)) FROM acct WHERE total_base > 0
  UNION ALL
  SELECT 'LIABILITIES', 2, count(*), round(sum(total_base)) FROM acct WHERE total_base < 0
  UNION ALL
  SELECT 'NET WORTH', 3, count(*), round(sum(total_base)) FROM acct
)
ORDER BY rank, total_{{base}} DESC;
