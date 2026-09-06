WITH x AS (
  SELECT category, -sum(amount_base) AS spent, count(*) AS lines
  FROM q_split_base
  WHERE category_kind = 'expense' AND is_transfer = 0 AND excluded = 0
    AND date BETWEEN '{{from}}' AND '{{to}}'
  GROUP BY 1
)
SELECT category, lines, round(spent) AS spent_{{base}},
       round(100.0 * spent / (SELECT sum(spent) FROM x), 1) AS share_pct
FROM x
ORDER BY spent DESC;
