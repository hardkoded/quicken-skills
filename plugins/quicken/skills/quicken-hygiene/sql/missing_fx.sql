SELECT c.currency, f.base_ccy AS base, r.first_rate, r.last_rate, r.days,
       CASE WHEN r.days IS NULL THEN 'no rates' WHEN r.last_rate < date('now', '-30 days') THEN 'stale' ELSE 'ok' END AS state
FROM (SELECT currency FROM q_account UNION SELECT currency FROM q_holding) c
CROSS JOIN fx_config f
LEFT JOIN (SELECT from_ccy, to_ccy, min(date) AS first_rate, max(date) AS last_rate, count(*) AS days
           FROM fx_rate GROUP BY 1, 2) r ON r.from_ccy = c.currency AND r.to_ccy = f.base_ccy
WHERE c.currency IS NOT NULL AND c.currency <> f.base_ccy
ORDER BY state DESC, c.currency;
