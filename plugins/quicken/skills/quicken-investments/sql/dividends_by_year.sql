SELECT strftime('%Y', i.date) AS year, i.security, i.ticker, i.action, count(*) AS payments,
       round(sum(i.amount), 2) AS amount, i.currency,
       round(sum(i.amount * s.fx_rate)) AS amount_{{base}}
FROM q_investment_transaction i
LEFT JOIN (SELECT transaction_id, max(fx_rate) AS fx_rate FROM q_split_base GROUP BY 1) s ON s.transaction_id = i.id
WHERE i.action IN ('Dividend Income', 'Interest Income')
  AND i.date BETWEEN '{{from}}' AND '{{to}}'
GROUP BY 1, 2, 3, 4, 7
ORDER BY 1 DESC, amount_{{base}} DESC;
