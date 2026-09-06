WITH last_full AS (SELECT strftime('%Y-%m', date('now', 'start of month', '-1 day')) AS m),
monthly AS (
  SELECT strftime('%Y-%m', date) AS month,
         substr(category, 1, instr(category || ':', ':') - 1) AS top_category,
         -sum(amount_base) AS spent
  FROM q_split_base
  WHERE category_kind = 'expense' AND is_transfer = 0 AND excluded = 0
    AND date >= date('now', 'start of month', '-13 months') AND date < date('now', 'start of month')
  GROUP BY 1, 2
)
SELECT c.top_category,
       (SELECT m FROM last_full) AS last_full_month,
       round(coalesce(cur.spent, 0)) AS last_month_{{base}},
       round(coalesce(prev.avg_spent, 0)) AS avg_prior_12m_{{base}},
       round(coalesce(cur.spent, 0) - coalesce(prev.avg_spent, 0)) AS diff_{{base}},
       CASE WHEN coalesce(prev.avg_spent, 0) > 0
            THEN round(100.0 * (coalesce(cur.spent, 0) - prev.avg_spent) / prev.avg_spent) END AS diff_pct
FROM (SELECT DISTINCT top_category FROM monthly) c
LEFT JOIN monthly cur ON cur.top_category = c.top_category AND cur.month = (SELECT m FROM last_full)
LEFT JOIN (SELECT top_category, sum(spent) / 12.0 AS avg_spent FROM monthly
           WHERE month < (SELECT m FROM last_full) GROUP BY 1) prev ON prev.top_category = c.top_category
ORDER BY abs(coalesce(cur.spent, 0) - coalesce(prev.avg_spent, 0)) DESC;
