SELECT a.name AS account, a.type, a.currency, a.institution,
       max(t.date) AS last_transaction, a.last_download_date,
       CAST(julianday('now') - julianday(coalesce(max(max(t.date), a.last_download_date), '1900-01-01')) AS INTEGER) AS days_silent
FROM q_account a
LEFT JOIN q_transaction t ON t.account_id = a.id AND t.kind <> 'scheduled'
WHERE a.closed = 0
GROUP BY a.id
HAVING days_silent > 30
ORDER BY days_silent DESC;
