SELECT account, security, ticker, units, price, price_date, currency
FROM q_holding
WHERE price IS NULL OR price_date < date('now', '-30 days')
ORDER BY price_date;
