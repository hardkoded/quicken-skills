WITH flows AS (
  SELECT i.security_id, i.security, i.ticker,
         sum(CASE WHEN i.action IN ('Buy', 'Buy to Cover') THEN -i.amount * s.fx_rate
                  WHEN i.action = 'Add Shares' THEN coalesce(i.cost_basis, 0) * s.fx_rate ELSE 0 END) AS invested_base,
         sum(CASE WHEN i.action IN ('Sell', 'Short Sell') THEN i.amount * s.fx_rate ELSE 0 END) AS proceeds_base,
         sum(CASE WHEN i.action IN ('Dividend Income', 'Interest Income') THEN i.amount * s.fx_rate ELSE 0 END) AS income_base,
         min(i.date) AS first_trade, max(i.date) AS last_trade
  FROM q_investment_transaction i
  LEFT JOIN (SELECT transaction_id, max(fx_rate) AS fx_rate FROM q_split_base GROUP BY 1) s ON s.transaction_id = i.id
  WHERE i.security_id IS NOT NULL
  GROUP BY 1, 2, 3
),
now_value AS (SELECT security_id, sum(units) AS units, sum(value_base) AS value_base FROM q_holding GROUP BY 1)
SELECT f.security, f.ticker,
       CASE WHEN coalesce(n.units, 0) > 0.000001 THEN 'open' ELSE 'closed' END AS status,
       f.first_trade, f.last_trade,
       round(f.invested_base) AS invested_{{base}}, round(f.proceeds_base) AS proceeds_{{base}},
       round(f.income_base) AS income_{{base}}, round(coalesce(n.value_base, 0)) AS value_now_{{base}},
       round(coalesce(n.value_base, 0) + f.proceeds_base + f.income_base - f.invested_base) AS total_gain_{{base}},
       CASE WHEN f.invested_base > 0
            THEN round(100.0 * (coalesce(n.value_base, 0) + f.proceeds_base + f.income_base - f.invested_base) / f.invested_base, 1) END AS gain_pct
FROM flows f
LEFT JOIN now_value n ON n.security_id = f.security_id
ORDER BY status, total_gain_{{base}} DESC;
