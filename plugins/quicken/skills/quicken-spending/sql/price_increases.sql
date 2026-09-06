WITH charges AS (
  SELECT payee, currency, date, -amount AS amount,
         row_number() OVER (PARTITION BY payee, currency ORDER BY date DESC) AS rn,
         count(*) OVER (PARTITION BY payee, currency) AS n,
         (julianday(max(date) OVER (PARTITION BY payee, currency)) -
          julianday(min(date) OVER (PARTITION BY payee, currency))) /
          (count(*) OVER (PARTITION BY payee, currency) - 1) AS cadence_days
  FROM q_split_base
  WHERE category_kind = 'expense' AND is_transfer = 0 AND excluded = 0 AND payee IS NOT NULL
    AND amount < 0 AND date BETWEEN '{{from}}' AND '{{to}}'
)
SELECT cur.payee, cur.currency, cur.n AS charges, round(cur.cadence_days) AS every_days,
       prev.date AS previous_date, round(prev.amount, 2) AS previous_amount,
       cur.date AS latest_date, round(cur.amount, 2) AS latest_amount,
       round(100.0 * (cur.amount - prev.amount) / prev.amount, 1) AS increase_pct
FROM charges cur
JOIN charges prev ON prev.payee = cur.payee AND prev.currency = cur.currency AND prev.rn = 2
WHERE cur.rn = 1 AND cur.n >= 3 AND cur.cadence_days BETWEEN 20 AND 40
  AND cur.amount > prev.amount * 1.02
ORDER BY increase_pct DESC;
