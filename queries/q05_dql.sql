-- =====================================================================
--  UPIShield - Q05 : DQL  (SELECT)
--  Guideline 5(c)(v) items 1-8.   Requires MySQL 8.0.31+ for INTERSECT / EXCEPT.
-- =====================================================================
USE upishield;

-- =====================================================================
-- 1. SELECT with WHERE
-- =====================================================================
-- 1a. Successful payments of Rs. 50,000 or more in October 2026
SELECT txn_id, payer_vpa, payee_vpa, amount, txn_time
FROM   upi_txn
WHERE  status = 'SUCCESS' AND amount >= 50000
  AND  txn_time >= '2026-10-01' AND txn_time < '2026-11-01';

-- 1b. Payments rejected because of the daily limit
SELECT txn_id, payer_vpa, amount, txn_time, failure_reason
FROM   upi_txn
WHERE  status = 'FAILED' AND failure_reason LIKE 'Daily UPI limit%';

-- 1c. Customers whose KYC is not complete
SELECT customer_id, full_name, city, kyc_status
FROM   customer
WHERE  kyc_status <> 'VERIFIED';

-- =====================================================================
-- 2. AGGREGATE functions
-- =====================================================================
SELECT COUNT(*)                AS successful_txns,
       SUM(amount)             AS total_value,
       ROUND(AVG(amount), 2)   AS average_value,
       MIN(amount)             AS smallest,
       MAX(amount)             AS largest,
       COUNT(DISTINCT payer_vpa) AS distinct_payers
FROM   upi_txn
WHERE  status = 'SUCCESS';

SELECT COUNT(*) AS total_accounts, SUM(balance) AS deposits_held,
       ROUND(AVG(balance), 2) AS avg_balance
FROM   bank_account WHERE status = 'ACTIVE';

-- =====================================================================
-- 3. IN, LIKE, DISTINCT
-- =====================================================================
-- 3a. IN: merchants in high-risk categories
SELECT merchant_id, merchant_name, mcc FROM merchant
WHERE  mcc IN ('5944', '6051', '7995');

-- 3b. NOT IN
SELECT customer_id, full_name, city FROM customer
WHERE  city NOT IN ('Ahmedabad', 'Gandhinagar', 'Surat', 'Vadodara', 'Rajkot')
LIMIT 10;

-- 3c. LIKE: VPAs on the SBI handle, and customers whose name starts with 'P'
SELECT vpa_id FROM vpa WHERE vpa_id LIKE '%@oksbi' LIMIT 10;
SELECT full_name FROM customer WHERE full_name LIKE 'P%';

-- 3d. LIKE with single-character wildcard: phone numbers starting 98 and ending 0
SELECT full_name, phone FROM customer WHERE phone LIKE '98_______0';

-- 3e. DISTINCT: cities where merchants operate / handles in use
SELECT DISTINCT city FROM merchant ORDER BY city;
SELECT DISTINCT SUBSTRING_INDEX(vpa_id, '@', -1) AS upi_handle FROM vpa ORDER BY upi_handle;

-- =====================================================================
-- 4. ORDER BY, LIMIT, OFFSET
-- =====================================================================
-- 4a. Ten largest successful payments
SELECT txn_id, payer_vpa, payee_vpa, amount, txn_time
FROM   upi_txn WHERE status = 'SUCCESS'
ORDER BY amount DESC
LIMIT 10;

-- 4b. Pagination: page 3 of the customer directory (10 per page)
SELECT customer_id, full_name, city
FROM   customer
ORDER BY full_name ASC, customer_id ASC
LIMIT 10 OFFSET 20;

-- 4c. Multi-column ordering
SELECT account_id, account_type, balance FROM bank_account
ORDER BY account_type ASC, balance DESC
LIMIT 15;

-- =====================================================================
-- 5. GROUP BY, GROUP BY with HAVING
-- =====================================================================
-- 5a. Payments per type and status
SELECT txn_type, status, COUNT(*) AS txns, SUM(amount) AS value
FROM   upi_txn
GROUP BY txn_type, status
ORDER BY txn_type, status;

-- 5b. Daily volume, only days above Rs. 3,00,000
SELECT DATE(txn_time) AS day, COUNT(*) AS txns, SUM(amount) AS value
FROM   upi_txn WHERE status = 'SUCCESS'
GROUP BY DATE(txn_time)
HAVING SUM(amount) > 300000
ORDER BY day;

-- 5c. Merchants with more than 40 successful payments
SELECT m.merchant_name, COUNT(*) AS payments, SUM(t.amount) AS collected
FROM   merchant m JOIN upi_txn t ON t.payee_vpa = m.vpa_id
WHERE  t.status = 'SUCCESS'
GROUP BY m.merchant_id, m.merchant_name
HAVING COUNT(*) > 40
ORDER BY payments DESC;

-- 5d. Customers holding more than one bank account
SELECT customer_id, COUNT(*) AS accounts
FROM   bank_account
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- 5e. Alerts per rule (with ROLLUP total)
SELECT r.rule_code, COUNT(fa.alert_id) AS alerts
FROM   fraud_rule r LEFT JOIN fraud_alert fa ON fa.rule_id = r.rule_id
GROUP BY r.rule_code WITH ROLLUP;

-- =====================================================================
-- 6. JOINS - all types
-- =====================================================================
-- 6a. INNER JOIN: each P2M payment with merchant and category
SELECT t.txn_id, t.amount, m.merchant_name, mc.description AS category
FROM   upi_txn t
INNER JOIN merchant m           ON m.vpa_id = t.payee_vpa
INNER JOIN merchant_category mc ON mc.mcc = m.mcc
WHERE  t.status = 'SUCCESS'
LIMIT 15;

-- 6b. LEFT OUTER JOIN: every customer and the number of disputes (incl. zero)
SELECT c.customer_id, c.full_name, COUNT(d.txn_id) AS disputes
FROM   customer c
LEFT JOIN dispute d ON d.raised_by = c.customer_id
GROUP BY c.customer_id, c.full_name
ORDER BY disputes DESC
LIMIT 15;

-- 6c. LEFT JOIN ... IS NULL: accounts whose VPAs never sent or received money
SELECT a.account_id, a.account_type, a.opened_on
FROM   bank_account a
JOIN   vpa v ON v.account_id = a.account_id
LEFT JOIN upi_txn t ON t.payer_vpa = v.vpa_id OR t.payee_vpa = v.vpa_id
WHERE  t.txn_id IS NULL;

-- 6d. RIGHT OUTER JOIN: every merchant category, even with no merchants
SELECT mc.mcc, mc.description, COUNT(m.merchant_id) AS merchants
FROM   merchant m
RIGHT JOIN merchant_category mc ON mc.mcc = m.mcc
GROUP BY mc.mcc, mc.description
ORDER BY merchants;

-- 6e. FULL OUTER JOIN (emulated: LEFT JOIN UNION RIGHT JOIN)
--     VPAs that paid in September, in October, or both
WITH sep AS (SELECT payer_vpa, COUNT(*) AS sep_txns FROM upi_txn
             WHERE txn_time >= '2026-09-01' AND txn_time < '2026-10-01' GROUP BY payer_vpa),
     oct AS (SELECT payer_vpa, COUNT(*) AS oct_txns FROM upi_txn
             WHERE txn_time >= '2026-10-01' AND txn_time < '2026-11-01' GROUP BY payer_vpa)
SELECT sep.payer_vpa AS vpa, sep.sep_txns, oct.oct_txns
FROM   sep LEFT JOIN oct ON oct.payer_vpa = sep.payer_vpa
UNION
SELECT oct.payer_vpa, sep.sep_txns, oct.oct_txns
FROM   sep RIGHT JOIN oct ON oct.payer_vpa = sep.payer_vpa
ORDER BY sep_txns IS NULL DESC, oct_txns IS NULL DESC, vpa
LIMIT 20;

-- 6f. CROSS JOIN: bank x account type matrix (zeros included)
SELECT b.bank_name, t.account_type, COUNT(a.account_id) AS accounts
FROM   bank b
CROSS JOIN (SELECT 'SAVINGS' AS account_type UNION SELECT 'CURRENT') t
LEFT JOIN branch br      ON br.bank_code = b.bank_code
LEFT JOIN bank_account a ON a.ifsc = br.ifsc AND a.account_type = t.account_type
GROUP BY b.bank_name, t.account_type
ORDER BY b.bank_name, t.account_type;

-- 6g. NATURAL JOIN: bank and branch share the column bank_code
SELECT bank_code, bank_name, ifsc, branch_name, city
FROM   bank NATURAL JOIN branch
ORDER BY bank_code
LIMIT 12;

-- 6h. SELF JOIN (recursive relationship): who referred whom
SELECT c.customer_id, c.full_name AS customer, r.full_name AS referred_by
FROM   customer c
JOIN   customer r ON r.customer_id = c.referred_by
ORDER BY c.customer_id
LIMIT 15;

-- 6i. NON-EQUI JOIN: which amount-based fraud rules each big payment crosses
SELECT t.txn_id, t.amount, r.rule_code, r.threshold_amount
FROM   upi_txn t
JOIN   fraud_rule r ON t.amount >= r.threshold_amount
WHERE  t.status = 'SUCCESS' AND r.is_active AND t.amount >= 40000
ORDER BY t.amount DESC
LIMIT 15;

-- 6j. Multi-table join: full trail of an alert
SELECT fa.alert_id, r.rule_name, t.amount, c.full_name, b.bank_name, d.model AS device
FROM   fraud_alert fa
JOIN   fraud_rule r    ON r.rule_id = fa.rule_id
JOIN   upi_txn t       ON t.txn_id = fa.txn_id
JOIN   vpa v           ON v.vpa_id = t.payer_vpa
JOIN   bank_account a  ON a.account_id = v.account_id
JOIN   customer c      ON c.customer_id = a.customer_id
JOIN   branch br       ON br.ifsc = a.ifsc
JOIN   bank b          ON b.bank_code = br.bank_code
LEFT JOIN device d     ON d.device_id = t.device_id
ORDER BY fa.alert_time DESC
LIMIT 10;

-- =====================================================================
-- 7. UNION, UNION ALL, INTERSECT, EXCEPT
-- =====================================================================
-- 7a. UNION: every VPA involved in a disputed transaction (payer or payee)
SELECT t.payer_vpa AS vpa FROM dispute d JOIN upi_txn t ON t.txn_id = d.txn_id
UNION
SELECT t.payee_vpa        FROM dispute d JOIN upi_txn t ON t.txn_id = d.txn_id;

-- 7b. UNION ALL keeps duplicates (compare the counts)
SELECT 'UNION' AS kind, COUNT(*) AS rows_returned FROM (
    SELECT payer_vpa AS vpa FROM upi_txn WHERE amount >= 20000
    UNION
    SELECT payee_vpa FROM upi_txn WHERE amount >= 20000) u
UNION ALL
SELECT 'UNION ALL', COUNT(*) FROM (
    SELECT payer_vpa AS vpa FROM upi_txn WHERE amount >= 20000
    UNION ALL
    SELECT payee_vpa FROM upi_txn WHERE amount >= 20000) ua;

-- 7c. INTERSECT: customers who raised a dispute AND were flagged by a fraud rule
SELECT raised_by AS customer_id FROM dispute
INTERSECT
SELECT a.customer_id
FROM   fraud_alert fa JOIN upi_txn t ON t.txn_id = fa.txn_id
JOIN   vpa v ON v.vpa_id = t.payer_vpa
JOIN   bank_account a ON a.account_id = v.account_id;

-- 7d. EXCEPT: VPAs that customers saved as payees but never actually paid
SELECT payee_vpa FROM saved_payee
EXCEPT
SELECT payee_vpa FROM upi_txn WHERE status = 'SUCCESS';

-- =====================================================================
-- 8. EXCEPT, ANY, ALL
-- =====================================================================
-- 8a. EXCEPT: Gujarat merchants that never received a flagged payment
SELECT merchant_id, merchant_name FROM merchant
WHERE  city IN ('Ahmedabad', 'Gandhinagar', 'Surat', 'Vadodara', 'Rajkot')
EXCEPT
SELECT m.merchant_id, m.merchant_name
FROM   merchant m JOIN upi_txn t ON t.payee_vpa = m.vpa_id
JOIN   fraud_alert fa ON fa.txn_id = t.txn_id;

-- 8b. > ANY: payments that cross AT LEAST ONE amount-based fraud threshold
SELECT txn_id, amount FROM upi_txn
WHERE  status = 'SUCCESS'
  AND  amount > ANY (SELECT threshold_amount FROM fraud_rule
                     WHERE threshold_amount IS NOT NULL AND is_active)
ORDER BY amount
LIMIT 10;

-- 8c. > ALL: payments that cross EVERY amount-based threshold
SELECT txn_id, amount FROM upi_txn
WHERE  status = 'SUCCESS'
  AND  amount > ALL (SELECT threshold_amount FROM fraud_rule
                     WHERE threshold_amount IS NOT NULL AND is_active)
ORDER BY amount DESC;

-- 8d. >= ALL: the merchant(s) with the highest total collection
SELECT merchant_name, total_collected FROM v_merchant_performance
WHERE  total_collected >= ALL (SELECT total_collected FROM v_merchant_performance);

-- 8e. = ANY (same meaning as IN): customers living in a city that has a jewellery merchant
SELECT customer_id, full_name, city FROM customer
WHERE  city = ANY (SELECT city FROM merchant WHERE mcc = '5944')
LIMIT 10;
