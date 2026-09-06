-- Worked examples for quicken-query. Placeholders {{from}}, {{to}}, {{base}} are
-- replaced by quicken.sh sql. Amounts: outflows negative, inflows positive.

-- 1. How much did I spend on a category (loose name match) per month?
SELECT strftime('%Y-%m', date) AS month, round(-sum(amount_base)) AS spent_{{base}}
FROM q_split_base
WHERE category LIKE '%groc%' AND is_transfer = 0 AND excluded = 0 AND kind = 'cashflow'
  AND date BETWEEN '{{from}}' AND '{{to}}'
GROUP BY 1 ORDER BY 1;

-- 2. Which payees did I pay most, in the base currency?
SELECT payee, count(*) AS n, round(-sum(amount_base)) AS total_{{base}}
FROM q_split_base
WHERE category_kind = 'expense' AND is_transfer = 0 AND excluded = 0
  AND date BETWEEN '{{from}}' AND '{{to}}'
GROUP BY 1 ORDER BY 3 DESC LIMIT 20;

-- 3. All transactions with a given tag.
SELECT date, account, payee, category, amount, currency, tags
FROM q_split
WHERE tags LIKE '%vacation%' ORDER BY date;

-- 4. Transfers between two accounts.
SELECT date, account, transfer_account, amount, currency
FROM q_split
WHERE is_transfer = 1 AND account LIKE '%checking%' AND transfer_account LIKE '%savings%'
ORDER BY date DESC;

-- 5. Balance of one account at each month end, in its currency and the base.
SELECT month, balance, currency, balance_base, base_currency
FROM q_account_balance_monthly
WHERE account LIKE '%visa%' AND month >= strftime('%Y-%m', '{{from}}')
ORDER BY month;

-- 6. Income by category and year.
SELECT strftime('%Y', date) AS year, category, round(sum(amount_base)) AS income_{{base}}
FROM q_split_base
WHERE category_kind = 'income' AND is_transfer = 0 AND excluded = 0
GROUP BY 1, 2 ORDER BY 1, 3 DESC;

-- 7. What do I hold in a given ticker, across accounts?
SELECT account, units, price, currency, value, value_base
FROM q_holding WHERE ticker = 'VTI';

-- 8. Every dividend received from one security, converted at the payment date.
SELECT i.date, i.account, i.amount, i.currency, round(i.amount * s.fx_rate, 2) AS amount_{{base}}
FROM q_investment_transaction i
JOIN q_split_base s ON s.transaction_id = i.id
WHERE i.action = 'Dividend Income' AND i.ticker = 'VTI'
ORDER BY i.date;

-- 9. Largest single expenses in a period.
SELECT date, account, payee, category, amount, currency, amount_base
FROM q_split_base
WHERE category_kind = 'expense' AND is_transfer = 0 AND excluded = 0
  AND date BETWEEN '{{from}}' AND '{{to}}'
ORDER BY amount_base ASC LIMIT 25;

-- 10. Budget targets from the raw tables (no view yet).
SELECT b.ZNAME AS budget, c.full_name AS category, t.ZEFFECTIVEDATENUM AS effective, t.ZAMOUNT AS target
FROM ZBUDGETTARGET t
JOIN ZBUDGETLINEITEM li ON li.Z_PK = t.ZLINEITEM AND li.ZDELETIONCOUNT = 0
JOIN ZBUDGET b ON b.Z_PK = li.ZBUDGET AND b.ZDELETIONCOUNT = 0
LEFT JOIN q_category c ON c.id = li.ZCATEGORYTAG
WHERE t.ZDELETIONCOUNT = 0
ORDER BY 1, 3, 2;
