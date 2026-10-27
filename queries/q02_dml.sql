-- =====================================================================
--  UPIShield - Q02 : DML  (INSERT, UPDATE with/without cascade,
--                          DELETE with/without cascade)
--  Guideline 5(c)(ii)
--  Destructive demos are wrapped in START TRANSACTION ... ROLLBACK so the
--  file can be re-run; take your screenshot BEFORE the ROLLBACK line.
-- =====================================================================
USE upishield;

-- =====================================================================
-- 1. INSERT
-- =====================================================================
-- 1a. Single-row insert
INSERT INTO customer (full_name, phone, email, dob, city, kyc_status, referred_by)
VALUES ('Nisha Raval', '9898012345', 'nisha.raval@gmail.com', '2001-04-18', 'Gandhinagar', 'PENDING', 1001);

-- 1b. Multi-row insert
INSERT INTO device (device_id, model, os, os_version, first_seen) VALUES
    ('DEV900001', 'iPhone 16',        'IOS',     '18.5', NOW()),
    ('DEV900002', 'Redmi Note 13',    'ANDROID', '14',   NOW());

INSERT INTO device_login (customer_id, device_id, login_time, ip_address)
SELECT customer_id, 'DEV900001', NOW(), '49.36.112.10'
FROM   customer WHERE phone = '9898012345';

-- 1c. INSERT ... SELECT : auto-save frequent payees (paid 3+ times, not saved yet)
INSERT INTO saved_payee (customer_id, payee_vpa, nickname, added_on)
SELECT a.customer_id, t.payee_vpa, 'Frequent', CURDATE()
FROM   upi_txn t
JOIN   vpa v          ON v.vpa_id = t.payer_vpa
JOIN   bank_account a ON a.account_id = v.account_id
WHERE  t.status = 'SUCCESS'
  AND  NOT EXISTS (SELECT 1 FROM saved_payee s
                   WHERE s.customer_id = a.customer_id AND s.payee_vpa = t.payee_vpa)
GROUP BY a.customer_id, t.payee_vpa
HAVING COUNT(*) >= 3;
SELECT ROW_COUNT() AS payees_auto_saved;

-- [EXPECTED ERROR] UNIQUE violation: phone number already registered
INSERT INTO customer (full_name, phone, dob, city)
VALUES ('Duplicate Phone', '9898012345', '1999-01-01', 'Surat');

-- [EXPECTED ERROR] Trigger: customer must be 18+
INSERT INTO customer (full_name, phone, dob, city)
VALUES ('Too Young', '9898099999', '2012-05-05', 'Surat');

-- =====================================================================
-- 2. UPDATE WITHOUT CASCADE
-- =====================================================================
-- 2a. Normal update (the audit trigger records the KYC change)
UPDATE customer SET kyc_status = 'VERIFIED' WHERE phone = '9898012345';
SELECT * FROM audit_log ORDER BY log_id DESC LIMIT 1;

-- 2b. Update with an expression on many rows
START TRANSACTION;
    UPDATE savings_account SET interest_rate = interest_rate + 0.25 WHERE min_balance >= 5000;
    SELECT ROW_COUNT() AS accounts_repriced;
ROLLBACK;

-- 2c. [EXPECTED ERROR] FK is ON UPDATE RESTRICT: a category code that merchants
--     still use cannot be changed (no cascade -> update is rejected)
UPDATE merchant_category SET mcc = '5499' WHERE mcc = '5411';

-- =====================================================================
-- 3. UPDATE WITH CASCADE
--    Bank merger: Kalupur Co-op Bank's code changes KCCB -> KCOB.
--    branch.bank_code is ON UPDATE CASCADE, so every branch follows.
-- =====================================================================
START TRANSACTION;
    SELECT ifsc, bank_code, branch_name FROM branch WHERE bank_code IN ('KCCB', 'KCOB');
    UPDATE bank SET bank_code = 'KCOB' WHERE bank_code = 'KCCB';
    SELECT ifsc, bank_code, branch_name FROM branch WHERE bank_code IN ('KCCB', 'KCOB');
ROLLBACK;

-- Second cascade: a branch is renumbered (new IFSC). bank_account.ifsc is
-- ON UPDATE CASCADE, so every account of that branch follows automatically.
SET @old_ifsc := (SELECT ifsc FROM bank_account GROUP BY ifsc ORDER BY COUNT(*) DESC LIMIT 1);
SET @new_ifsc := CONCAT(LEFT(@old_ifsc, 5), '999999');
START TRANSACTION;
    SELECT @old_ifsc AS old_ifsc, COUNT(*) AS accounts FROM bank_account WHERE ifsc = @old_ifsc;
    UPDATE branch SET ifsc = @new_ifsc WHERE ifsc = @old_ifsc;
    SELECT @new_ifsc AS new_ifsc, COUNT(*) AS accounts FROM bank_account WHERE ifsc = @new_ifsc;
ROLLBACK;

-- =====================================================================
-- 4. DELETE WITH CASCADE
--    Delete a brand-new account with no transactions:
--    bank_account -> savings_account (CASCADE)
--                 -> vpa (CASCADE) -> saved_payee rows pointing at it (CASCADE)
-- =====================================================================
SET @acc := (SELECT a.account_id
             FROM   bank_account a
             WHERE  a.opened_on >= '2026-10-01'
               AND  NOT EXISTS (SELECT 1 FROM vpa v JOIN upi_txn t
                                  ON t.payer_vpa = v.vpa_id OR t.payee_vpa = v.vpa_id
                                WHERE v.account_id = a.account_id)
               AND  EXISTS (SELECT 1 FROM vpa v JOIN saved_payee s ON s.payee_vpa = v.vpa_id
                            WHERE v.account_id = a.account_id)
             ORDER BY a.account_id LIMIT 1);
SET @vpa := (SELECT vpa_id FROM vpa WHERE account_id = @acc LIMIT 1);

START TRANSACTION;
    SELECT 'before' AS stage,
           (SELECT COUNT(*) FROM savings_account WHERE account_id = @acc) AS savings_rows,
           (SELECT COUNT(*) FROM vpa             WHERE account_id = @acc) AS vpa_rows,
           (SELECT COUNT(*) FROM saved_payee     WHERE payee_vpa = @vpa)  AS saved_payee_rows;
    DELETE FROM bank_account WHERE account_id = @acc;
    SELECT 'after' AS stage,
           (SELECT COUNT(*) FROM savings_account WHERE account_id = @acc) AS savings_rows,
           (SELECT COUNT(*) FROM vpa             WHERE account_id = @acc) AS vpa_rows,
           (SELECT COUNT(*) FROM saved_payee     WHERE payee_vpa = @vpa)  AS saved_payee_rows;
    SELECT * FROM audit_log WHERE table_name = 'bank_account' AND operation = 'DELETE'
    ORDER BY log_id DESC LIMIT 1;
ROLLBACK;

-- =====================================================================
-- 5. DELETE WITHOUT CASCADE
-- =====================================================================
-- 5a. Normal delete of independent rows
START TRANSACTION;
    DELETE FROM device_login WHERE login_time < '2026-08-10';
    SELECT ROW_COUNT() AS old_logins_deleted;
ROLLBACK;

-- 5b. [EXPECTED ERROR] customer 1001 still owns accounts (ON DELETE RESTRICT)
DELETE FROM customer WHERE customer_id = 1001;

-- 5c. [EXPECTED ERROR] account with transaction history: the cascade to VPA is
--     blocked because upi_txn references the VPA (RESTRICT) -> nothing deleted
DELETE FROM bank_account WHERE account_id = 50001;

-- Clean-up of the rows inserted in section 1 (keeps the file re-runnable)
DELETE FROM device_login WHERE device_id IN ('DEV900001', 'DEV900002');
DELETE FROM device       WHERE device_id IN ('DEV900001', 'DEV900002');
DELETE FROM saved_payee  WHERE nickname = 'Frequent' AND added_on = CURDATE();
DELETE FROM customer     WHERE phone = '9898012345';
