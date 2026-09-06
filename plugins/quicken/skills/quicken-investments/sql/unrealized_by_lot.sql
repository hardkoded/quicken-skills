SELECT a.name AS account, s.name AS security, s.ticker,
       date(l.ZACQUISITIONDATE + 978307200, 'unixepoch') AS acquired,
       CAST(julianday('now') - julianday(date(l.ZACQUISITIONDATE + 978307200, 'unixepoch')) AS INTEGER) AS days_held,
       round(l.ZLATESTUNITS, 4) AS units,
       round(l.ZLATESTCOSTBASIS, 2) AS cost_basis,
       round(l.ZLATESTCOSTBASIS / l.ZLATESTUNITS, 4) AS cost_per_unit,
       q.close AS price,
       round(l.ZLATESTUNITS * q.close, 2) AS value,
       round(l.ZLATESTUNITS * q.close - l.ZLATESTCOSTBASIS, 2) AS unrealized_gain,
       round(100.0 * (l.ZLATESTUNITS * q.close - l.ZLATESTCOSTBASIS) / l.ZLATESTCOSTBASIS, 1) AS gain_pct,
       coalesce(s.currency, a.currency) AS currency
FROM ZLOT l
JOIN ZPOSITION p ON p.Z_PK = l.ZPOSITION AND p.ZDELETIONCOUNT = 0
JOIN q_account a ON a.id = p.ZACCOUNT
JOIN q_security s ON s.id = p.ZSECURITY
LEFT JOIN q_quote_latest q ON q.security_id = s.id
WHERE l.ZDELETIONCOUNT = 0 AND abs(l.ZLATESTUNITS) > 0.000001 AND l.ZLATESTCOSTBASIS <> 0
ORDER BY s.name, acquired;
