SELECT account, security, ticker, currency, round(units, 4) AS units, price, price_date,
       round(value) AS value, round(cost_basis) AS cost_basis, round(unrealized_gain) AS unrealized_gain,
       CASE WHEN cost_basis > 0 THEN round(100.0 * unrealized_gain / cost_basis, 1) END AS gain_pct,
       round(value_base) AS value_{{base}},
       round(100.0 * value_base / (SELECT sum(value_base) FROM q_holding), 1) AS weight_pct
FROM q_holding
ORDER BY value_base DESC;
