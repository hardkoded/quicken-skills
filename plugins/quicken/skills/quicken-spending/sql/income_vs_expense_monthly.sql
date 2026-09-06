WITH m AS (
  SELECT strftime('%Y-%m', date) AS month,
         sum(CASE WHEN category_kind = 'income' THEN amount_base ELSE 0 END) AS income,
         -sum(CASE WHEN category_kind = 'expense' THEN amount_base ELSE 0 END) AS expenses
  FROM q_split_base
  WHERE category_kind IN ('income', 'expense') AND is_transfer = 0 AND excluded = 0
    AND date BETWEEN '{{from}}' AND '{{to}}'
  GROUP BY 1
)
SELECT month, round(income) AS income_{{base}}, round(expenses) AS expenses_{{base}},
       round(income - expenses) AS net_{{base}},
       CASE WHEN month = strftime('%Y-%m', 'now') THEN NULL
            WHEN income > 0 THEN round(100.0 * (income - expenses) / income) END AS savings_rate_pct,
       CASE WHEN month = strftime('%Y-%m', 'now') THEN 'partial month' END AS note
FROM m
ORDER BY month;
