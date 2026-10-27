-- =====================================================================
--  UPIShield - Q04 : TCL  (COMMIT, SAVEPOINT, ROLLBACK)
--  Guideline 5(c)(iv)  |  Syllabus Unit 4: ACID properties
-- =====================================================================
USE upishield;

-- Two customers' primary VPAs used in the demos
SET @payer := (SELECT vpa_id FROM vpa WHERE account_id = 50001 AND is_primary);
SET @payee := (SELECT v.vpa_id FROM vpa v JOIN bank_account a ON a.account_id = v.account_id
               WHERE a.customer_id = 1003 AND v.is_primary LIMIT 1);
SET @payer_acc := fn_account_of_vpa(@payer);
SET @payee_acc := fn_account_of_vpa(@payee);
SELECT @payer AS payer, @payee AS payee;

-- ---------------------------------------------------------------------
-- 1. COMMIT : a manual UPI transfer as ONE atomic unit of work
--    (debit + credit + transaction record succeed together)
-- ---------------------------------------------------------------------
SELECT account_id, balance FROM bank_account WHERE account_id IN (@payer_acc, @payee_acc);

START TRANSACTION;
    UPDATE bank_account SET balance = balance - 500 WHERE account_id = @payer_acc;
    UPDATE bank_account SET balance = balance + 500 WHERE account_id = @payee_acc;
    INSERT INTO upi_txn (payer_vpa, payee_vpa, amount, status, remarks)
    VALUES (@payer, @payee, 500, 'SUCCESS', 'TCL demo - commit');
COMMIT;

SELECT account_id, balance FROM bank_account WHERE account_id IN (@payer_acc, @payee_acc);

-- ---------------------------------------------------------------------
-- 2. ROLLBACK : undo everything since START TRANSACTION
-- ---------------------------------------------------------------------
START TRANSACTION;
    UPDATE bank_account SET balance = balance - 99999 WHERE account_id = @payer_acc;
    SELECT account_id, balance AS balance_inside_txn FROM bank_account WHERE account_id = @payer_acc;
ROLLBACK;
SELECT account_id, balance AS balance_after_rollback FROM bank_account WHERE account_id = @payer_acc;

-- ---------------------------------------------------------------------
-- 3. SAVEPOINT + ROLLBACK TO SAVEPOINT : three payments in one batch,
--    the third one is cancelled, the first two are kept.
-- ---------------------------------------------------------------------
START TRANSACTION;
    INSERT INTO upi_txn (payer_vpa, payee_vpa, amount, status, remarks)
    VALUES (@payer, @payee, 101, 'SUCCESS', 'TCL demo - batch 1');
    UPDATE bank_account SET balance = balance - 101 WHERE account_id = @payer_acc;
    UPDATE bank_account SET balance = balance + 101 WHERE account_id = @payee_acc;
    SAVEPOINT after_payment_1;

    INSERT INTO upi_txn (payer_vpa, payee_vpa, amount, status, remarks)
    VALUES (@payer, @payee, 202, 'SUCCESS', 'TCL demo - batch 2');
    UPDATE bank_account SET balance = balance - 202 WHERE account_id = @payer_acc;
    UPDATE bank_account SET balance = balance + 202 WHERE account_id = @payee_acc;
    SAVEPOINT after_payment_2;

    INSERT INTO upi_txn (payer_vpa, payee_vpa, amount, status, remarks)
    VALUES (@payer, @payee, 303, 'SUCCESS', 'TCL demo - batch 3');
    UPDATE bank_account SET balance = balance - 303 WHERE account_id = @payer_acc;
    UPDATE bank_account SET balance = balance + 303 WHERE account_id = @payee_acc;

    SELECT txn_id, amount, remarks FROM upi_txn WHERE remarks LIKE 'TCL demo - batch%';

    ROLLBACK TO SAVEPOINT after_payment_2;      -- cancels payment 3 only
    RELEASE SAVEPOINT after_payment_1;
COMMIT;

SELECT txn_id, amount, remarks FROM upi_txn WHERE remarks LIKE 'TCL demo - batch%';

-- ---------------------------------------------------------------------
-- 4. autocommit = 0 : every statement waits for an explicit COMMIT/ROLLBACK
-- ---------------------------------------------------------------------
SELECT @@autocommit;
SET autocommit = 0;
    UPDATE customer SET city = 'Ahmedabad' WHERE customer_id = 1001;
    SELECT customer_id, city FROM customer WHERE customer_id = 1001;
ROLLBACK;
SELECT customer_id, city FROM customer WHERE customer_id = 1001;
SET autocommit = 1;

-- ---------------------------------------------------------------------
-- 5. DDL causes an IMPLICIT COMMIT (cannot be rolled back)
-- ---------------------------------------------------------------------
START TRANSACTION;
    INSERT INTO device (device_id, model, os, first_seen) VALUES ('DEV_TCL_1', 'Demo Phone', 'ANDROID', NOW());
    CREATE TABLE tmp_implicit_commit (id INT);     -- commits the INSERT above!
ROLLBACK;
SELECT device_id FROM device WHERE device_id = 'DEV_TCL_1';   -- row is still there
DROP TABLE tmp_implicit_commit;
DELETE FROM device WHERE device_id = 'DEV_TCL_1';

-- ---------------------------------------------------------------------
-- 6. TCL inside stored procedures
--    sp_transfer rolls back automatically on failure (atomicity);
--    sp_settle_merchants uses one SAVEPOINT per merchant.
-- ---------------------------------------------------------------------
SET @low_payer := (SELECT v.vpa_id FROM vpa v JOIN bank_account a ON a.account_id = v.account_id
                   WHERE a.account_type = 'SAVINGS' AND a.status = 'ACTIVE' AND v.is_primary
                     AND a.balance < 30000 ORDER BY a.balance LIMIT 1);
CALL sp_transfer(@low_payer, @payee, 50000, NULL, 'more than the balance', @txn, @st, @msg);
SELECT @txn AS txn_id, @st AS status, @msg AS message;

CALL sp_settle_merchants('2026-10-23', @settled, @skipped);
SELECT @settled AS merchants_settled, @skipped AS merchants_skipped;
-- second run: every merchant already settled -> each INSERT fails on the
-- UNIQUE key, is rolled back to its savepoint, and the batch still commits
CALL sp_settle_merchants('2026-10-23', @settled, @skipped);
SELECT @settled AS merchants_settled, @skipped AS merchants_skipped;
