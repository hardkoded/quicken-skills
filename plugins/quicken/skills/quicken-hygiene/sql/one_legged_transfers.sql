SELECT s.date, s.account, s.payee, s.amount, s.currency, e.ZTRANSFER AS transfer_ref, s.note
FROM q_split s
JOIN ZCASHFLOWTRANSACTIONENTRY e ON e.Z_PK = s.id
WHERE s.is_transfer = 1 AND s.transfer_account_id IS NULL
ORDER BY s.date DESC;
