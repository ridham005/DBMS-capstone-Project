-- =====================================================================
--  UPIShield - Q06 : Subqueries
--  Guideline 5(c)(vi)  |  Syllabus Unit 2: sub-queries, correlated
--  sub-queries, EXISTS
-- =====================================================================
USE upishield;

-- 1. Scalar subquery in WHERE: payments above the overall average
SELECT txn_id, amount
FROM   upi_txn
WHERE  status = 'SUCCESS'
  AND  amount > (SELECT AVG(amount) FROM upi_txn WHERE status = 'SUCCESS')
ORDER BY amount
LIMIT 10;

-- 2. Scalar subquery in SELECT: each merchant's share of all P2M value
SELECT m.merchant_name,
       (SELECT COALESCE(SUM(t.amount), 0) FROM upi_txn t
         WHERE t.payee_vpa = m.vpa_id AND t.status = 'SUCCESS') AS collected,
       ROUND(100 * (SELECT COALESCE(SUM(t.amount), 0) FROM upi_txn t
                     WHERE t.payee_vpa = m.vpa_id AND t.status = 'SUCCESS')
                 / (SELECT SUM(amount) FROM upi_txn
                     WHERE txn_type = 'P2M' AND status = 'SUCCESS'), 2) AS share_pct
FROM   merchant m
ORDER BY collected DESC
LIMIT 10;

-- 3. IN subquery: customers who own a merchant
SELECT customer_id, full_name FROM customer
WHERE  customer_id IN (SELECT a.customer_id
                       FROM merchant m
                       JOIN vpa v ON v.vpa_id = m.vpa_id
                       JOIN bank_account a ON a.account_id = v.account_id);

-- 4. NOT IN subquery: devices that were never used for a payment
SELECT device_id, model, first_seen FROM device
WHERE  device_id NOT IN (SELECT device_id FROM upi_txn WHERE device_id IS NOT NULL);

-- 5. CORRELATED subquery: payments much larger than that payer's own usual amount
--    (the inner query is re-evaluated for each outer row, using t.payer_vpa)
SELECT t.txn_id, t.payer_vpa, t.amount
FROM   upi_txn t
WHERE  t.status = 'SUCCESS'
  AND  t.amount > 5 * (SELECT AVG(t2.amount) FROM upi_txn t2
                       WHERE t2.payer_vpa = t.payer_vpa AND t2.status = 'SUCCESS')
ORDER BY t.amount DESC;

-- 6. CORRELATED subquery: each customer's most recent payment
SELECT c.full_name, t.txn_id, t.amount, t.txn_time
FROM   customer c
JOIN   bank_account a ON a.customer_id = c.customer_id
JOIN   vpa v          ON v.account_id = a.account_id
JOIN   upi_txn t      ON t.payer_vpa = v.vpa_id
WHERE  t.txn_time = (SELECT MAX(t2.txn_time) FROM upi_txn t2 WHERE t2.payer_vpa = v.vpa_id)
ORDER BY t.txn_time DESC
LIMIT 10;

-- 7. EXISTS: customers with at least one CONFIRMED fraud on their payments
SELECT c.customer_id, c.full_name, c.city
FROM   customer c
WHERE  EXISTS (SELECT 1
               FROM   bank_account a
               JOIN   vpa v         ON v.account_id = a.account_id
               JOIN   upi_txn t     ON t.payer_vpa = v.vpa_id
               JOIN   fraud_alert f ON f.txn_id = t.txn_id
               WHERE  a.customer_id = c.customer_id
                 AND  f.status = 'CONFIRMED_FRAUD');

-- 8. NOT EXISTS: verified customers who have never made any payment
SELECT c.customer_id, c.full_name
FROM   customer c
WHERE  c.kyc_status = 'VERIFIED'
  AND  NOT EXISTS (SELECT 1
                   FROM   bank_account a
                   JOIN   vpa v     ON v.account_id = a.account_id
                   JOIN   upi_txn t ON t.payer_vpa = v.vpa_id
                   WHERE  a.customer_id = c.customer_id);

-- 9. Subquery in FROM (derived table): top 5 spenders
SELECT spender.customer_id, c.full_name, spender.total_spent
FROM  (SELECT a.customer_id, SUM(t.amount) AS total_spent
       FROM   upi_txn t
       JOIN   vpa v          ON v.vpa_id = t.payer_vpa
       JOIN   bank_account a ON a.account_id = v.account_id
       WHERE  t.status = 'SUCCESS'
       GROUP BY a.customer_id) AS spender
JOIN   customer c ON c.customer_id = spender.customer_id
ORDER BY spender.total_spent DESC
LIMIT 5;

-- 10. Subquery in HAVING: cities whose average payment beats the national average
SELECT c.city, ROUND(AVG(t.amount), 2) AS avg_payment
FROM   upi_txn t
JOIN   vpa v          ON v.vpa_id = t.payer_vpa
JOIN   bank_account a ON a.account_id = v.account_id
JOIN   customer c     ON c.customer_id = a.customer_id
WHERE  t.status = 'SUCCESS'
GROUP BY c.city
HAVING AVG(t.amount) > (SELECT AVG(amount) FROM upi_txn WHERE status = 'SUCCESS');

-- 11. Nested (multi-level) subquery: merchants in the category with the most alerts
SELECT merchant_name, mcc FROM merchant
WHERE  mcc = (SELECT m.mcc
              FROM   merchant m
              JOIN   upi_txn t     ON t.payee_vpa = m.vpa_id
              JOIN   fraud_alert f ON f.txn_id = t.txn_id
              GROUP BY m.mcc
              ORDER BY COUNT(*) DESC
              LIMIT 1);

-- 12. Subquery inside UPDATE (rolled back): freeze accounts of customers with 2+ confirmed frauds
START TRANSACTION;
    UPDATE bank_account
    SET    status = 'FROZEN'
    WHERE  customer_id IN (SELECT x.customer_id FROM (
               SELECT a.customer_id
               FROM   fraud_alert f
               JOIN   upi_txn t      ON t.txn_id = f.txn_id
               JOIN   vpa v          ON v.vpa_id = t.payer_vpa
               JOIN   bank_account a ON a.account_id = v.account_id
               WHERE  f.status = 'CONFIRMED_FRAUD'
               GROUP BY a.customer_id
               HAVING COUNT(*) >= 2) AS x);
    SELECT ROW_COUNT() AS accounts_frozen;
ROLLBACK;

-- 13. Common Table Expression (named subquery): weekly growth of P2M value
WITH weekly AS (
    SELECT YEARWEEK(txn_time, 3) AS wk, SUM(amount) AS value
    FROM   upi_txn
    WHERE  status = 'SUCCESS' AND txn_type = 'P2M' AND txn_time >= '2026-09-01'
    GROUP BY YEARWEEK(txn_time, 3)
)
SELECT wk, value,
       value - LAG(value) OVER (ORDER BY wk) AS change_from_last_week
FROM   weekly
ORDER BY wk;
