SELECT account, currency, count(*) AS uncleared, min(date) AS oldest, round(sum(amount), 2) AS net_amount
FROM q_transaction
WHERE kind = 'cashflow' AND status = 'uncleared' AND date < date('now', '-90 days')
GROUP BY account_id
ORDER BY uncleared DESC;
