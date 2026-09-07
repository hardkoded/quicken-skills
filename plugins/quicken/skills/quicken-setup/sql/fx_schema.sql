-- Exchange rates cached from providers. rate = units of to_ccy per 1 unit of from_ccy,
-- so amount_in_to = amount_in_from * rate.
CREATE TABLE IF NOT EXISTS fx_rate (
  from_ccy TEXT NOT NULL,
  to_ccy   TEXT NOT NULL,
  date     TEXT NOT NULL,
  rate     REAL NOT NULL,
  source   TEXT NOT NULL,
  PRIMARY KEY (from_ccy, to_ccy, date)
);

CREATE VIEW IF NOT EXISTS q_fx_latest AS
SELECT f.from_ccy, f.to_ccy, f.date, f.rate, f.source
FROM fx_rate f
JOIN (SELECT from_ccy, to_ccy, max(date) AS date FROM fx_rate GROUP BY 1, 2) m
  ON m.from_ccy = f.from_ccy AND m.to_ccy = f.to_ccy AND m.date = f.date;
