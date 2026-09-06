WITH charges AS (
  SELECT payee, currency, date, -amount AS amount, -amount_base AS amount_base
  FROM q_split_base
  WHERE category_kind = 'expense' AND is_transfer = 0 AND excluded = 0 AND payee IS NOT NULL
    AND amount < 0 AND date BETWEEN '{{from}}' AND '{{to}}'
),
grouped AS (
  SELECT payee, currency, count(*) AS n, min(date) AS first_date, max(date) AS last_date,
         avg(amount) AS avg_amount, min(amount) AS min_amount, max(amount) AS max_amount,
         round(avg(amount_base)) AS avg_amount_{{base}},
         (julianday(max(date)) - julianday(min(date))) / (count(*) - 1) AS cadence_days
  FROM charges
  GROUP BY 1, 2
  HAVING n >= 3
)
SELECT payee, currency, n AS charges, round(cadence_days) AS every_days,
       round(avg_amount, 2) AS avg_amount, avg_amount_{{base}}, first_date, last_date,
       CASE WHEN last_date < date('now', '-45 days') THEN 'maybe cancelled' ELSE 'active' END AS state
FROM grouped
WHERE cadence_days BETWEEN 25 AND 35 AND max_amount <= min_amount * 1.15
ORDER BY avg_amount_{{base}} DESC;
