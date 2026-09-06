SELECT 'uncategorized lines (period)' AS check_name, count(*) AS n
FROM q_split WHERE kind = 'cashflow' AND is_transfer = 0 AND excluded = 0
  AND (category_id IS NULL OR category_leaf = 'Uncategorized') AND date BETWEEN '{{from}}' AND '{{to}}'
UNION ALL
SELECT 'possible duplicate groups (period)', count(*) FROM (
  SELECT 1 FROM q_transaction WHERE kind = 'cashflow' AND date BETWEEN '{{from}}' AND '{{to}}'
  GROUP BY account_id, date, payee, amount HAVING count(*) > 1)
UNION ALL
SELECT 'one-legged transfers (all time)', count(*) FROM q_split WHERE is_transfer = 1 AND transfer_account_id IS NULL
UNION ALL
SELECT 'stale open accounts', count(*) FROM (
  SELECT a.id FROM q_account a LEFT JOIN q_transaction t ON t.account_id = a.id AND t.kind <> 'scheduled'
  WHERE a.closed = 0 GROUP BY a.id
  HAVING max(coalesce(max(t.date), '1900-01-01'), coalesce(a.last_download_date, '1900-01-01')) < date('now', '-30 days'))
UNION ALL
SELECT 'uncleared older than 90 days', count(*) FROM q_transaction
WHERE kind = 'cashflow' AND status = 'uncleared' AND date < date('now', '-90 days')
UNION ALL
SELECT 'holdings without a recent price', count(*) FROM q_holding
WHERE price IS NULL OR price_date < date('now', '-30 days')
UNION ALL
SELECT 'positions where lots differ from transactions', count(*) FROM (
  SELECT p.Z_PK FROM ZPOSITION p
  LEFT JOIN (SELECT ZPOSITION AS pid, sum(ZLATESTUNITS) u FROM ZLOT WHERE ZDELETIONCOUNT = 0 GROUP BY 1) l ON l.pid = p.Z_PK
  LEFT JOIN (SELECT ZPOSITION AS pid, sum(ZUNITS) u FROM ZTRANSACTION WHERE ZDELETIONCOUNT = 0 GROUP BY 1) t ON t.pid = p.Z_PK
  WHERE p.ZDELETIONCOUNT = 0 AND abs(coalesce(l.u, 0) - coalesce(t.u, 0)) > 0.0001)
UNION ALL
SELECT 'split lines with no exchange rate', count(*) FROM q_split_base WHERE amount_base IS NULL
UNION ALL
SELECT 'currency pairs with stale rates', count(*) FROM (
  SELECT from_ccy, to_ccy FROM fx_rate GROUP BY 1, 2 HAVING max(date) < date('now', '-30 days'));
