WITH cash AS (
  SELECT a.currency, sum(t.amount) AS amount
  FROM q_transaction t JOIN q_account a ON a.id = t.account_id
  WHERE t.kind <> 'scheduled' AND t.date <= date('now') AND a.closed = 0
  GROUP BY 1
),
parts AS (
  SELECT c.currency, c.amount AS amount,
         c.amount * CASE WHEN c.currency = f.base_ccy THEN 1.0 ELSE fx.rate END AS amount_base,
         'cash' AS part
  FROM cash c CROSS JOIN fx_config f
  LEFT JOIN q_fx_latest fx ON fx.from_ccy = c.currency AND fx.to_ccy = f.base_ccy
  UNION ALL
  SELECT currency, sum(value), sum(value_base), 'securities' FROM q_holding GROUP BY 1
),
by_ccy AS (
  SELECT currency, round(sum(CASE WHEN part = 'cash' THEN amount ELSE 0 END), 2) AS cash,
         round(sum(CASE WHEN part = 'securities' THEN amount ELSE 0 END), 2) AS securities,
         sum(amount_base) AS total_base
  FROM parts GROUP BY 1
)
SELECT currency, cash, securities, round(total_base) AS total_{{base}},
       round(100.0 * total_base / (SELECT sum(total_base) FROM by_ccy), 1) AS share_pct
FROM by_ccy
ORDER BY total_base DESC;
