-- Small synthetic data set. Base currency USD, one EUR account, one brokerage account.
-- Dates are given as seconds since 2001-01-01 at UTC noon, like Quicken writes them.
INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER, Z_MAX) VALUES
  (1, 'Account', 0, 4), (15, 'CashFlowTransactionEntry', 0, 207), (73, 'Tag', 0, 20),
  (74, 'CashFlowTag', 73, 20), (75, 'CategoryTag', 74, 20), (76, 'UserTag', 74, 20),
  (78, 'Transaction', 0, 107), (79, 'CashFlowTransaction', 78, 107),
  (80, 'SmartCashFlowTransaction', 79, 107), (81, 'InvestmentTransaction', 78, 107),
  (60, 'Security', 0, 40), (61, 'Position', 0, 50), (62, 'Lot', 0, 60), (63, 'SecurityQuote', 0, 71),
  (64, 'UserPayee', 0, 32), (65, 'ForexQuote', 0, 1), (66, 'DocumentProperty', 0, 1), (67, 'FinancialInstitution', 0, 1);

INSERT INTO ZDOCUMENTPROPERTY (Z_PK, Z_ENT, Z_OPT, ZNAME, ZSTRINGVALUE) VALUES (1, 66, 1, 'homeCurrencyCode', 'USD');
INSERT INTO ZFINANCIALINSTITUTION (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZNAME) VALUES (1, 67, 1, 0, 'Test Bank');

INSERT INTO ZACCOUNT (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZACTIVE, ZCLOSED, ZNAME, ZTYPENAME, ZCURRENCY, ZFINANCIALINSTITUTION) VALUES
  (1, 1, 1, 0, 1, 0, 'Checking', 'CHECKING', 'USD', 1),
  (2, 1, 1, 0, 1, 0, 'Euro Checking', 'CHECKING', 'EUR', NULL),
  (3, 1, 1, 0, 1, 0, 'Brokerage', 'BROKERAGENORMAL', 'USD', NULL),
  (4, 1, 1, 0, 1, 0, 'Credit Card', 'CREDITCARD', 'USD', 1);

INSERT INTO ZTAG (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZNAME, ZTYPE, ZHIDDEN, ZPARENTCATEGORY) VALUES
  (10, 75, 1, 0, 'Food', 1, 0, NULL),
  (11, 75, 1, 0, 'Groceries', 1, 0, 10),
  (12, 75, 1, 0, 'Salary', 2, 0, NULL),
  (13, 75, 1, 0, 'Transfer', 0, 0, NULL),
  (14, 75, 1, 0, 'Buy', 0, 0, NULL),
  (15, 75, 1, 0, 'Dividend Income', 2, 0, NULL),
  (20, 76, 1, 0, 'vacation', NULL, 0, NULL);

INSERT INTO ZUSERPAYEE (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZNAME) VALUES
  (30, 64, 1, 0, 'Grocer'), (31, 64, 1, 0, 'Employer'), (32, 64, 1, 0, 'Broker');

INSERT INTO ZSECURITY (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZNAME, ZTICKER, ZCURRENCY, ZASSETCLASS) VALUES
  (40, 60, 1, 0, 'Test Fund', 'TST', 'USD', 'Large Cap');
INSERT INTO ZPOSITION (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZACCOUNT, ZSECURITY) VALUES (50, 61, 1, 0, 3, 40);
INSERT INTO ZLOT (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZPOSITION, ZLATESTUNITS, ZLATESTCOSTBASIS, ZACQUISITIONDATE) VALUES
  (60, 62, 1, 0, 50, 10, 400, strftime('%s', '2024-02-20 12:00:00') - 978307200);
INSERT INTO ZSECURITYQUOTE (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZSECURITY, ZQUOTEDATE, ZCLOSINGPRICE) VALUES
  (70, 63, 1, 0, 40, strftime('%s', '2024-06-28 12:00:00') - 978307200, 45),
  (71, 63, 1, 0, 40, strftime('%s', '2024-12-31 12:00:00') - 978307200, 50);

-- Quicken's single current rate, dated today so it is not stale.
INSERT INTO ZFOREXQUOTE (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZFROMCURRENCY, ZTOCURRENCY, ZEXCHANGERATE, ZMANUALEXCHANGERATE, ZQUOTEDATE) VALUES
  (1, 65, 1, 0, 'EUR', 'USD', 1.10, NULL, strftime('%s', 'now') - 978307200);

-- Transactions. Z_ENT 79 = cash flow, 81 = investment.
INSERT INTO ZTRANSACTION (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZQUICKENID, ZACCOUNT, ZUSERPAYEE, ZENTEREDDATE, ZPOSTEDDATE, ZAMOUNT, ZRECONCILESTATUS, ZEXCLUDEFROMREPORTS, ZTYPE, ZPOSITION, ZUNITS, ZCOSTBASIS) VALUES
  (100, 79, 1, 0, 100, 1, 31, strftime('%s', '2024-01-15 12:00:00') - 978307200, NULL, 3000, 1, 0, NULL, NULL, NULL, NULL),
  (101, 79, 1, 0, 101, 1, 30, strftime('%s', '2024-01-20 12:00:00') - 978307200, strftime('%s', '2024-01-21 12:00:00') - 978307200, -100, 1, 0, NULL, NULL, NULL, NULL),
  (102, 79, 1, 0, 102, 2, 30, strftime('%s', '2024-02-10 12:00:00') - 978307200, NULL, -50, 0, 0, NULL, NULL, NULL, NULL),
  (103, 79, 1, 0, 103, 1, NULL, strftime('%s', '2024-02-15 12:00:00') - 978307200, NULL, -500, 0, 0, NULL, NULL, NULL, NULL),
  (104, 79, 1, 0, 104, 3, NULL, strftime('%s', '2024-02-15 12:00:00') - 978307200, NULL, 500, 0, 0, NULL, NULL, NULL, NULL),
  (105, 79, 1, 0, 105, 4, 30, strftime('%s', '2024-03-01 12:00:00') - 978307200, NULL, -80, 0, 0, NULL, NULL, NULL, NULL),
  (106, 81, 1, 0, 106, 3, 32, strftime('%s', '2024-02-20 12:00:00') - 978307200, NULL, -400, NULL, 0, 3, 50, 10, 400),
  (107, 81, 1, 0, 107, 3, 32, strftime('%s', '2024-06-01 12:00:00') - 978307200, NULL, 5, NULL, 0, 10, 50, NULL, 0);

-- Split lines. ZTRANSFER holds the counterpart line's ZQUICKENID as text.
INSERT INTO ZCASHFLOWTRANSACTIONENTRY (Z_PK, Z_ENT, Z_OPT, ZDELETIONCOUNT, ZQUICKENID, ZPARENT, ZCATEGORYTAG, ZAMOUNT, ZSEQUENCENUMBER, ZTRANSFER) VALUES
  (200, 15, 1, 0, 200, 100, 12, 3000, 0, NULL),
  (201, 15, 1, 0, 201, 101, 11, -100, 0, NULL),
  (202, 15, 1, 0, 202, 102, 11, -50, 0, NULL),
  (203, 15, 1, 0, 203, 103, 13, -500, 0, '204'),
  (204, 15, 1, 0, 204, 104, 13, 500, 0, '203'),
  (205, 15, 1, 0, 205, 105, 11, -80, 0, NULL),
  (206, 15, 1, 0, 206, 106, 14, -400, 0, NULL),
  (207, 15, 1, 0, 207, 107, 15, 5, 0, NULL);

INSERT INTO Z_15USERTAGS (Z_15CASHFLOWTRANSACTIONENTRIES, Z_76USERTAGS) VALUES (201, 20);
