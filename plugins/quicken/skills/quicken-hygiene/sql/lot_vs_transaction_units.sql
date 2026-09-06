SELECT a.name AS account, s.name AS security, s.ticker,
       round(coalesce(l.u, 0), 4) AS lot_units,
       round(coalesce(t.u, 0), 4) AS transaction_units,
       round(coalesce(l.u, 0) - coalesce(t.u, 0), 4) AS difference
FROM ZPOSITION p
JOIN q_account a ON a.id = p.ZACCOUNT
JOIN q_security s ON s.id = p.ZSECURITY
LEFT JOIN (SELECT ZPOSITION AS pid, sum(ZLATESTUNITS) AS u FROM ZLOT WHERE ZDELETIONCOUNT = 0 GROUP BY 1) l ON l.pid = p.Z_PK
LEFT JOIN (SELECT ZPOSITION AS pid, sum(ZUNITS) AS u FROM ZTRANSACTION WHERE ZDELETIONCOUNT = 0 GROUP BY 1) t ON t.pid = p.Z_PK
WHERE p.ZDELETIONCOUNT = 0 AND abs(coalesce(l.u, 0) - coalesce(t.u, 0)) > 0.0001
ORDER BY abs(difference) DESC;
