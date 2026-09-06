SELECT date, account, payee, category, amount, currency, round(amount_base) AS amount_{{base}}, note
FROM q_split_base
WHERE category_kind = 'expense' AND is_transfer = 0 AND excluded = 0
  AND date BETWEEN '{{from}}' AND '{{to}}'
ORDER BY amount_base ASC
LIMIT 30;
