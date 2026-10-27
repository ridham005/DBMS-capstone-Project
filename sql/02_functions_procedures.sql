-- =====================================================================
--  UPIShield - File 02 : Stored Functions and Stored Procedures
--  Guideline: Point 5(c)(viii)  |  Syllabus: Unit 2 (Functions), Unit 4 (ACID)
-- =====================================================================
USE upishield;

DROP FUNCTION  IF EXISTS fn_enc_key;
DROP FUNCTION  IF EXISTS fn_mask_account;
DROP FUNCTION  IF EXISTS fn_account_of_vpa;
DROP FUNCTION  IF EXISTS fn_daily_spent;
DROP FUNCTION  IF EXISTS fn_risk_score;
DROP FUNCTION  IF EXISTS fn_age;
DROP PROCEDURE IF EXISTS sp_open_account;
DROP PROCEDURE IF EXISTS sp_transfer;
DROP PROCEDURE IF EXISTS sp_settle_merchants;
DROP PROCEDURE IF EXISTS sp_customer_statement;
DROP PROCEDURE IF EXISTS sp_raise_dispute;

DELIMITER //

-- ---------------------------------------------------------------------
-- FUNCTIONS
-- ---------------------------------------------------------------------

-- Encryption key used by AES_ENCRYPT / AES_DECRYPT.
-- (In production the key would live outside the database, e.g. in a vault.
--  Only the admin role is granted EXECUTE on this function.)
CREATE FUNCTION fn_enc_key()
RETURNS VARBINARY(32)
DETERMINISTIC NO SQL
BEGIN
    RETURN UNHEX(SHA2('UPIShield#DemoKey2026', 256));
END //

-- Masks an account number for display: XXXXXXXX1234
CREATE FUNCTION fn_mask_account(p_last4 CHAR(4))
RETURNS VARCHAR(12)
DETERMINISTIC NO SQL
BEGIN
    RETURN CONCAT('XXXXXXXX', p_last4);
END //

-- Returns the bank account linked to a UPI ID
CREATE FUNCTION fn_account_of_vpa(p_vpa VARCHAR(50))
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_acc INT DEFAULT NULL;
    SELECT account_id INTO v_acc FROM vpa WHERE vpa_id = p_vpa;
    RETURN v_acc;
END //

-- Total successful UPI debits from one account on one day (all its VPAs)
CREATE FUNCTION fn_daily_spent(p_account_id INT, p_day DATE)
RETURNS DECIMAL(14,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(14,2);
    SELECT COALESCE(SUM(t.amount), 0) INTO v_total
    FROM   upi_txn t
    JOIN   vpa v ON v.vpa_id = t.payer_vpa
    WHERE  v.account_id = p_account_id
      AND  t.status = 'SUCCESS'
      AND  t.txn_time >= p_day
      AND  t.txn_time <  p_day + INTERVAL 1 DAY;
    RETURN v_total;
END //

-- Risk score 0-100 for a customer, based on alerts, disputes and KYC
CREATE FUNCTION fn_risk_score(p_customer_id INT)
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_confirmed INT DEFAULT 0;
    DECLARE v_open      INT DEFAULT 0;
    DECLARE v_disputes  INT DEFAULT 0;
    DECLARE v_kyc       VARCHAR(10);
    DECLARE v_score     INT DEFAULT 0;

    SELECT kyc_status INTO v_kyc FROM customer WHERE customer_id = p_customer_id;

    SELECT COALESCE(SUM(fa.status = 'CONFIRMED_FRAUD'), 0),
           COALESCE(SUM(fa.status IN ('OPEN','INVESTIGATING')), 0)
      INTO v_confirmed, v_open
    FROM fraud_alert fa
    JOIN upi_txn t      ON t.txn_id = fa.txn_id
    JOIN vpa v          ON v.vpa_id = t.payer_vpa
    JOIN bank_account a ON a.account_id = v.account_id
    WHERE a.customer_id = p_customer_id;

    SELECT COUNT(*) INTO v_disputes FROM dispute WHERE raised_by = p_customer_id;

    SET v_score = v_confirmed * 30 + v_open * 10 + v_disputes * 5
                + IF(v_kyc = 'VERIFIED', 0, 20);
    RETURN LEAST(v_score, 100);
END //

-- Age in completed years (non-deterministic: depends on CURDATE())
CREATE FUNCTION fn_age(p_dob DATE)
RETURNS INT
NOT DETERMINISTIC NO SQL
BEGIN
    RETURN TIMESTAMPDIFF(YEAR, p_dob, CURDATE());
END //

-- ---------------------------------------------------------------------
-- PROCEDURES
-- ---------------------------------------------------------------------

-- Opens an account atomically: BANK_ACCOUNT + subclass row + VPA.
-- Enforces TOTAL participation of the specialization (no account is left
-- without its SAVINGS/CURRENT row).
CREATE PROCEDURE sp_open_account(
    IN  p_customer_id     INT,
    IN  p_ifsc            CHAR(11),
    IN  p_account_no      VARCHAR(18),
    IN  p_account_type    VARCHAR(10),
    IN  p_initial_deposit DECIMAL(14,2),
    IN  p_interest_rate   DECIMAL(4,2),
    IN  p_min_balance     DECIMAL(10,2),
    IN  p_business_name   VARCHAR(100),
    IN  p_gstin           CHAR(15),
    IN  p_vpa             VARCHAR(50),
    OUT p_account_id      INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_account_id = NULL;
        RESIGNAL;
    END;

    IF p_account_no NOT REGEXP '^[0-9]{9,18}$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account number must be 9-18 digits';
    END IF;

    START TRANSACTION;
        INSERT INTO bank_account (customer_id, ifsc, account_no_enc, account_no_last4,
                                  account_type, balance, status, opened_on)
        VALUES (p_customer_id, p_ifsc, AES_ENCRYPT(p_account_no, fn_enc_key()),
                RIGHT(p_account_no, 4), p_account_type, p_initial_deposit, 'ACTIVE', CURDATE());
        SET p_account_id = LAST_INSERT_ID();

        IF p_account_type = 'SAVINGS' THEN
            INSERT INTO savings_account (account_id, interest_rate, min_balance)
            VALUES (p_account_id, COALESCE(p_interest_rate, 3.00), COALESCE(p_min_balance, 1000.00));
        ELSE
            INSERT INTO current_account (account_id, business_name, gstin)
            VALUES (p_account_id, p_business_name, p_gstin);
        END IF;

        INSERT INTO vpa (vpa_id, account_id, is_primary, created_on)
        VALUES (p_vpa, p_account_id, TRUE, CURDATE());
    COMMIT;
END //

-- UPI payment: debit payer, credit payee, record the transaction.
-- ACID: everything happens inside one transaction; any failure rolls back
-- and a FAILED transaction row is written for the record.
-- Concurrency: both account rows are locked with SELECT ... FOR UPDATE in
-- ascending account_id order (prevents lost updates and deadlocks).
CREATE PROCEDURE sp_transfer(
    IN  p_payer_vpa  VARCHAR(50),
    IN  p_payee_vpa  VARCHAR(50),
    IN  p_amount     DECIMAL(12,2),
    IN  p_device_id  VARCHAR(20),
    IN  p_remarks    VARCHAR(100),
    OUT p_txn_id     BIGINT,
    OUT p_status     VARCHAR(7),
    OUT p_message    VARCHAR(255)
)
BEGIN
    DECLARE v_payer_acc     INT;
    DECLARE v_payee_acc     INT;
    DECLARE v_payer_bal     DECIMAL(14,2);
    DECLARE v_payer_status  VARCHAR(10);
    DECLARE v_payee_status  VARCHAR(10);
    DECLARE v_payer_type    VARCHAR(10);
    DECLARE v_min_bal       DECIMAL(10,2) DEFAULT 0;
    DECLARE v_msg           VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_status  = 'FAILED';
        SET p_message = v_msg;
        SET p_txn_id  = NULL;
        -- keep a record of the failed attempt (only if both VPAs exist)
        IF v_payer_acc IS NOT NULL AND v_payee_acc IS NOT NULL
           AND p_amount > 0 AND p_amount <= 100000 AND p_payer_vpa <> p_payee_vpa THEN
            INSERT INTO upi_txn (payer_vpa, payee_vpa, amount, status, device_id, remarks, failure_reason)
            VALUES (p_payer_vpa, p_payee_vpa, p_amount, 'FAILED', p_device_id, p_remarks, v_msg);
            SET p_txn_id = LAST_INSERT_ID();
        END IF;
    END;

    SET v_payer_acc = fn_account_of_vpa(p_payer_vpa);
    SET v_payee_acc = fn_account_of_vpa(p_payee_vpa);

    IF v_payer_acc IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown payer VPA';
    END IF;
    IF v_payee_acc IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown payee VPA';
    END IF;
    IF p_payer_vpa = p_payee_vpa OR v_payer_acc = v_payee_acc THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payer and payee must be different accounts';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 100000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be between Rs. 0.01 and Rs. 1,00,000';
    END IF;

    START TRANSACTION;
        -- lock both rows in a fixed (ascending) order to avoid deadlocks
        SELECT account_id INTO @lock1 FROM bank_account
         WHERE account_id = LEAST(v_payer_acc, v_payee_acc) FOR UPDATE;
        SELECT account_id INTO @lock2 FROM bank_account
         WHERE account_id = GREATEST(v_payer_acc, v_payee_acc) FOR UPDATE;
        SELECT balance, status, account_type INTO v_payer_bal, v_payer_status, v_payer_type
          FROM bank_account WHERE account_id = v_payer_acc FOR UPDATE;
        SELECT status INTO v_payee_status
          FROM bank_account WHERE account_id = v_payee_acc FOR UPDATE;

        IF v_payer_status <> 'ACTIVE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payer account is not active';
        END IF;
        IF v_payee_status <> 'ACTIVE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payee account is not active';
        END IF;
        IF v_payer_type = 'SAVINGS' THEN
            SELECT min_balance INTO v_min_bal FROM savings_account WHERE account_id = v_payer_acc;
        END IF;
        IF v_payer_bal - p_amount < v_min_bal THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance';
        END IF;

        -- BEFORE INSERT trigger enforces the daily limit; AFTER INSERT runs fraud rules
        INSERT INTO upi_txn (payer_vpa, payee_vpa, amount, status, device_id, remarks)
        VALUES (p_payer_vpa, p_payee_vpa, p_amount, 'SUCCESS', p_device_id, p_remarks);
        SET p_txn_id = LAST_INSERT_ID();

        UPDATE bank_account SET balance = balance - p_amount WHERE account_id = v_payer_acc;
        UPDATE bank_account SET balance = balance + p_amount WHERE account_id = v_payee_acc;
    COMMIT;

    SET p_status  = 'SUCCESS';
    SET p_message = 'Payment successful';
END //

-- Daily merchant settlement.  One transaction for the whole batch, with a
-- SAVEPOINT per merchant: if one merchant fails (e.g. already settled),
-- only that merchant is rolled back and the batch continues.
CREATE PROCEDURE sp_settle_merchants(
    IN  p_date     DATE,
    OUT p_settled  INT,
    OUT p_skipped  INT
)
BEGIN
    DECLARE v_done        BOOLEAN DEFAULT FALSE;
    DECLARE v_err         BOOLEAN DEFAULT FALSE;
    DECLARE v_merchant    INT;
    DECLARE v_type        VARCHAR(10);
    DECLARE v_count       INT;
    DECLARE v_gross       DECIMAL(14,2);
    DECLARE v_mdr         DECIMAL(4,2);
    DECLARE v_fee         DECIMAL(12,2);
    DECLARE v_hold        INT;

    DECLARE cur_merchants CURSOR FOR
        SELECT m.merchant_id, m.merchant_type, COUNT(*), SUM(t.amount)
        FROM   merchant m
        JOIN   upi_txn t ON t.payee_vpa = m.vpa_id
        WHERE  t.status = 'SUCCESS'
          AND  t.txn_time >= p_date AND t.txn_time < p_date + INTERVAL 1 DAY
        GROUP BY m.merchant_id, m.merchant_type;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_err = TRUE;

    SET p_settled = 0, p_skipped = 0;

    START TRANSACTION;
    OPEN cur_merchants;
    settle_loop: LOOP
        FETCH cur_merchants INTO v_merchant, v_type, v_count, v_gross;
        IF v_done THEN LEAVE settle_loop; END IF;

        SAVEPOINT sp_merchant;
        SET v_err = FALSE;

        SET v_mdr = 0;
        IF v_type = 'ENTERPRISE' THEN
            SELECT mdr_rate INTO v_mdr FROM enterprise_merchant WHERE merchant_id = v_merchant;
        END IF;
        SET v_fee = ROUND(v_gross * v_mdr / 100, 2);

        -- hold the payout if a critical alert is still open on that day
        SELECT COUNT(*) INTO v_hold
        FROM fraud_alert fa
        JOIN fraud_rule r ON r.rule_id = fa.rule_id
        JOIN upi_txn t    ON t.txn_id = fa.txn_id
        JOIN merchant m   ON m.vpa_id = t.payee_vpa
        WHERE m.merchant_id = v_merchant
          AND r.severity = 'CRITICAL'
          AND fa.status IN ('OPEN','INVESTIGATING','CONFIRMED_FRAUD')
          AND t.txn_time >= p_date AND t.txn_time < p_date + INTERVAL 1 DAY;

        INSERT INTO settlement (merchant_id, settle_date, txn_count, gross_amount,
                                mdr_fee, net_amount, status)
        VALUES (v_merchant, p_date, v_count, v_gross, v_fee, v_gross - v_fee,
                IF(v_hold > 0, 'ON_HOLD', 'SETTLED'));

        IF v_err THEN
            ROLLBACK TO SAVEPOINT sp_merchant;
            SET p_skipped = p_skipped + 1;
        ELSE
            RELEASE SAVEPOINT sp_merchant;
            SET p_settled = p_settled + 1;
        END IF;
    END LOOP;
    CLOSE cur_merchants;
    COMMIT;
END //

-- Account statement for one customer between two dates (returns a result set)
CREATE PROCEDURE sp_customer_statement(
    IN p_customer_id INT,
    IN p_from        DATE,
    IN p_to          DATE
)
BEGIN
    SELECT t.txn_id, t.txn_time,
           CASE WHEN pv.account_id = a.account_id THEN 'DEBIT' ELSE 'CREDIT' END AS direction,
           t.payer_vpa, t.payee_vpa, t.amount, t.txn_type, t.status, t.remarks
    FROM   bank_account a
    JOIN   vpa v       ON v.account_id = a.account_id
    JOIN   upi_txn t   ON t.payer_vpa = v.vpa_id OR t.payee_vpa = v.vpa_id
    JOIN   vpa pv      ON pv.vpa_id = t.payer_vpa
    WHERE  a.customer_id = p_customer_id
      AND  t.txn_time >= p_from AND t.txn_time < p_to + INTERVAL 1 DAY
    ORDER BY t.txn_time DESC;
END //

-- Raise a dispute (the trigger assigns dispute_no and validates ownership)
CREATE PROCEDURE sp_raise_dispute(
    IN p_txn_id      BIGINT,
    IN p_customer_id INT,
    IN p_reason      VARCHAR(20),
    IN p_description VARCHAR(255)
)
BEGIN
    INSERT INTO dispute (txn_id, raised_by, reason, description, raised_on)
    VALUES (p_txn_id, p_customer_id, p_reason, p_description, NOW());
    SELECT * FROM dispute WHERE txn_id = p_txn_id ORDER BY dispute_no DESC LIMIT 1;
END //

DELIMITER ;

SHOW FUNCTION  STATUS WHERE Db = 'upishield';
SHOW PROCEDURE STATUS WHERE Db = 'upishield';
