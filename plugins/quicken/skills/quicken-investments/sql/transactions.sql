SELECT i.date, i.account, i.action, i.security, i.ticker, round(i.units, 4) AS units,
       round(i.amount, 2) AS amount, i.currency, round(i.amount * s.fx_rate) AS amount_{{base}},
       round(i.commission, 2) AS commission, i.note
FROM q_investment_transaction i
LEFT JOIN (SELECT transaction_id, max(fx_rate) AS fx_rate FROM q_split_base GROUP BY 1) s ON s.transaction_id = i.id
WHERE i.date BETWEEN '{{from}}' AND '{{to}}'
ORDER BY i.date DESC
LIMIT 100;
