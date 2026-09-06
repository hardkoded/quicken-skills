SELECT date, account, payee, amount, currency, count(*) AS copies,
       group_concat(status, ', ') AS statuses
FROM q_transaction
WHERE kind = 'cashflow' AND date BETWEEN '{{from}}' AND '{{to}}'
GROUP BY account_id, date, payee, amount
HAVING count(*) > 1
ORDER BY abs(amount) DESC
LIMIT 50;
