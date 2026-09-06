SELECT 'asset class' AS dimension, coalesce(asset_class, 'Unknown') AS bucket,
       count(*) AS positions, round(sum(value_base)) AS value_{{base}},
       round(100.0 * sum(value_base) / (SELECT sum(value_base) FROM q_holding), 1) AS share_pct
FROM q_holding GROUP BY 2
UNION ALL
SELECT 'currency', currency, count(*), round(sum(value_base)),
       round(100.0 * sum(value_base) / (SELECT sum(value_base) FROM q_holding), 1)
FROM q_holding GROUP BY 2
ORDER BY dimension, value_{{base}} DESC;
