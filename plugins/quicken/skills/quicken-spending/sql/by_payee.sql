SELECT coalesce(payee, '(no payee)') AS payee, count(*) AS charges,
       round(-avg(amount_base)) AS avg_{{base}}, round(-sum(amount_base)) AS total_{{base}},
       group_concat(DISTINCT currency) AS currencies
FROM q_split_base
WHERE category_kind = 'expense' AND is_transfer = 0 AND excluded = 0
  AND date BETWEEN '{{from}}' AND '{{to}}'
GROUP BY 1
ORDER BY total_{{base}} DESC
LIMIT 25;
