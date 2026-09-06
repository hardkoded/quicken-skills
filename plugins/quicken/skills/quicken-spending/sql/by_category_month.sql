SELECT strftime('%Y-%m', date) AS month,
       substr(category, 1, instr(category || ':', ':') - 1) AS top_category,
       round(-sum(amount_base)) AS spent_{{base}}
FROM q_split_base
WHERE category_kind = 'expense' AND is_transfer = 0 AND excluded = 0
  AND date BETWEEN '{{from}}' AND '{{to}}'
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
