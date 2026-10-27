-- =====================================================================
--  UPIShield - Q08 : Stored Procedures, Functions and Triggers in action
--  Guideline 5(c)(viii).  Definitions: sql/02_functions_procedures.sql,
--  sql/03_triggers.sql.
--  Note: procedures COMMIT their own work.  Re-running section 2a gives a
--  duplicate-key error (the account already exists) - that is expected;
--  run sql/00_rebuild to reset.
-- =====================================================================
USE upishield;

-- =====================================================================
-- 1. FUNCTIONS
-- =====================================================================
SELECT fn_mask_account('4321')  AS masked,
       fn_age('2004-08-15')      AS age,
       fn_account_of_vpa((SELECT vpa_id FROM vpa WHERE account_id = 50001 AND is_primary)) AS account;

-- Daily spend of every account that paid on 22 Oct (top 10)
SELECT a.account_id, fn_daily_spent(a.account_id, '2026-10-22') AS spent_on_22_oct
FROM   bank_account a
ORDER BY spent_on_22_oct DESC
LIMIT 10;

-- Ten riskiest customers
SELECT customer_id, full_name, kyc_status, fn_risk_score(customer_id) AS risk_score
FROM   customer
ORDER BY risk_score DESC, customer_id
LIMIT 10;

-- =====================================================================
-- 2. PROCEDURES
-- =====================================================================
-- 2a. Open a savings account (account + subclass row + VPA in one transaction)
SET @ifsc := (SELECT ifsc FROM branch WHERE city = 'Gandhinagar' LIMIT 1);
CALL sp_open_account(1001, @ifsc, '602211887744', 'SAVINGS', 25000.00, 3.50, 1000.00,
                     NULL, NULL, 'aarav.savings@oksbi', @new_acc);
SELECT @new_acc AS new_account_id;
SELECT a.account_id, a.account_type, a.balance, s.interest_rate, v.vpa_id
FROM   bank_account a
JOIN   savings_account s ON s.account_id = a.account_id
JOIN   vpa v             ON v.account_id = a.account_id
WHERE  a.account_id = @new_acc;

-- the stored number is encrypted; only the key holder can read it
SELECT HEX(account_no_enc) AS stored_bytes,
       CAST(AES_DECRYPT(account_no_enc, fn_enc_key()) AS CHAR) AS decrypted
FROM   bank_account WHERE account_id = @new_acc;

-- 2b. Successful payment
SET @payee := (SELECT v.vpa_id FROM vpa v JOIN bank_account a ON a.account_id = v.account_id
               WHERE a.customer_id = 1003 AND v.is_primary LIMIT 1);
CALL sp_transfer('aarav.savings@oksbi', @payee, 1200.00, NULL, 'concert tickets', @txn, @st, @msg);
SELECT @txn AS txn_id, @st AS status, @msg AS message;

-- 2c. Failed payment: would break the minimum-balance rule -> rolled back, logged as FAILED
CALL sp_transfer('aarav.savings@oksbi', @payee, 24000.00, NULL, 'too much', @txn, @st, @msg);
SELECT @txn AS txn_id, @st AS status, @msg AS message;
SELECT txn_id, amount, status, failure_reason FROM upi_txn WHERE txn_id = @txn;

-- 2d. Failed payment: unknown VPA (no row can be logged)
CALL sp_transfer('nobody@ybl', @payee, 100.00, NULL, NULL, @txn, @st, @msg);
SELECT @txn AS txn_id, @st AS status, @msg AS message;

-- 2e. Customer statement (procedure returning a result set)
CALL sp_customer_statement(1001, '2026-10-01', CURDATE());

-- 2f. Raise a dispute on the successful payment from 2b
SET @ok_txn := (SELECT MAX(txn_id) FROM upi_txn
                WHERE payer_vpa = 'aarav.savings@oksbi' AND status = 'SUCCESS');
CALL sp_raise_dispute(@ok_txn, 1001, 'NOT_RECEIVED', 'Tickets never arrived');

-- 2g. Merchant settlement for one day
CALL sp_settle_merchants('2026-10-23', @settled, @skipped);
SELECT @settled AS settled, @skipped AS skipped;
SELECT * FROM settlement WHERE settle_date = '2026-10-23' ORDER BY gross_amount DESC LIMIT 5;

-- =====================================================================
-- 3. TRIGGERS
-- =====================================================================
-- 3a. trg_txn_ai : a Rs. 60,000 payment to a never-paid VPA raises a CRITICAL alert
SET @rich := (SELECT v.vpa_id FROM vpa v JOIN bank_account a ON a.account_id = v.account_id
              WHERE a.account_type = 'SAVINGS' AND a.status = 'ACTIVE' AND v.is_primary
                AND a.balance > 150000
                AND fn_daily_spent(a.account_id, CURDATE()) = 0
              ORDER BY a.account_id LIMIT 1);
SET @rich_owner := (SELECT customer_id FROM bank_account WHERE account_id = fn_account_of_vpa(@rich));
SET @stranger := (SELECT vpa_id FROM vpa WHERE is_primary AND account_id =
                    (SELECT MAX(account_id) FROM bank_account
                     WHERE account_type = 'SAVINGS' AND status = 'ACTIVE'
                       AND customer_id <> @rich_owner));
CALL sp_transfer(@rich, @stranger, 60000.00, NULL, 'urgent', @txn, @st, @msg);
SELECT @txn AS txn_id, @st AS status;
SELECT * FROM v_fraud_analyst_alerts WHERE txn_id = @txn;

-- 3b. trg_txn_bi : the daily limit. Another Rs. 45,000 from the same account
--     today takes the total past Rs. 1,00,000 -> rejected
CALL sp_transfer(@rich, @payee, 45000.00, NULL, 'second big payment', @txn, @st, @msg);
SELECT @txn AS txn_id, @st AS status, @msg AS message;

-- 3c. trg_txn_bi also derives txn_type: P2M when the payee is a merchant
SELECT txn_id, payee_vpa, txn_type FROM upi_txn ORDER BY txn_id DESC LIMIT 5;

-- 3d. [EXPECTED ERROR] trg_savings_bi : disjoint specialization
INSERT INTO savings_account (account_id, interest_rate, min_balance)
SELECT MIN(account_id), 3.00, 0 FROM bank_account WHERE account_type = 'CURRENT';

-- 3e. [EXPECTED ERROR] trg_dispute_bi : only the payer may dispute a payment
CALL sp_raise_dispute(@ok_txn, 1003, 'UNAUTHORIZED', 'not my payment');

-- 3f. trg_alert_au / trg_account_au : the audit trail
UPDATE fraud_alert SET status = 'INVESTIGATING', analyst_note = 'Called customer'
WHERE  txn_id = (SELECT MAX(txn_id) FROM upi_txn WHERE remarks = 'urgent');
SELECT * FROM v_auditor_trail ORDER BY log_id DESC LIMIT 8;

SHOW TRIGGERS FROM upishield;
