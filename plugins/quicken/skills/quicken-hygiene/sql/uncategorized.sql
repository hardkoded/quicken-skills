SELECT date, account, payee, amount, currency, amount_base, note
FROM q_split_base
WHERE kind = 'cashflow' AND is_transfer = 0 AND excluded = 0
  AND (category_id IS NULL OR category_leaf = 'Uncategorized')
  AND date BETWEEN '{{from}}' AND '{{to}}'
ORDER BY abs(coalesce(amount_base, amount)) DESC
LIMIT 50;
