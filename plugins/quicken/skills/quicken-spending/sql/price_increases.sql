-- Recurring payees whose latest charge is above their earlier charges.
-- Prior charges must be stable (max within 25% of min) so a different item under the
-- same payee does not show up as a price increase; jumps above 100% are treated as noise.
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
),
prior AS (
  SELECT payee, currency, count(*) AS prior_charges, avg(amount) AS prior_avg,
         min(amount) AS prior_min, max(amount) AS prior_max, max(date) AS previous_date
  FROM charges WHERE rn > 1 GROUP BY 1, 2
)
SELECT cur.payee, cur.currency, cur.n AS charges, round(cur.cadence_days) AS every_days,
       p.previous_date, round(p.prior_avg, 2) AS previous_avg_amount,
       cur.date AS latest_date, round(cur.amount, 2) AS latest_amount,
       round(100.0 * (cur.amount - p.prior_avg) / p.prior_avg, 1) AS increase_pct
FROM charges cur
JOIN prior p ON p.payee = cur.payee AND p.currency = cur.currency
WHERE cur.rn = 1 AND cur.n >= 3 AND cur.cadence_days BETWEEN 20 AND 40
  AND p.prior_max <= p.prior_min * 1.25
  AND cur.amount > p.prior_avg * 1.02 AND cur.amount <= p.prior_avg * 2
ORDER BY increase_pct DESC;
