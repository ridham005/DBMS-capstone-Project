-- =====================================================================
--  UPIShield - File 03 : Triggers
--  Guideline: Point 5(c)(viii)  |  Syllabus: Unit 4 (Audit trails)
--
--  Why triggers?  CHECK constraints in MySQL cannot use sub-queries or
--  non-deterministic functions (CURDATE), so every rule that looks at
--  OTHER rows or the current date is enforced here with SIGNAL.
-- =====================================================================
USE upishield;

DROP TRIGGER IF EXISTS trg_customer_bi;
DROP TRIGGER IF EXISTS trg_customer_bu;
DROP TRIGGER IF EXISTS trg_customer_au;
DROP TRIGGER IF EXISTS trg_savings_bi;
DROP TRIGGER IF EXISTS trg_current_bi;
DROP TRIGGER IF EXISTS trg_account_au;
DROP TRIGGER IF EXISTS trg_account_ad;
DROP TRIGGER IF EXISTS trg_txn_bi;
DROP TRIGGER IF EXISTS trg_txn_ai;
DROP TRIGGER IF EXISTS trg_txn_au;
DROP TRIGGER IF EXISTS trg_alert_au;
DROP TRIGGER IF EXISTS trg_dispute_bi;

DELIMITER //

-- ---------------------------------------------------------------------
-- CUSTOMER: must be 18+ (CHECK cannot use CURDATE)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_customer_bi
BEFORE INSERT ON customer
FOR EACH ROW
BEGIN
    IF TIMESTAMPDIFF(YEAR, NEW.dob, CURDATE()) < 18 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer must be at least 18 years old';
    END IF;
END //

CREATE TRIGGER trg_customer_bu
BEFORE UPDATE ON customer
FOR EACH ROW
BEGIN
    IF TIMESTAMPDIFF(YEAR, NEW.dob, CURDATE()) < 18 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer must be at least 18 years old';
    END IF;
    IF NEW.referred_by = NEW.customer_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A customer cannot refer themselves';
    END IF;
END //

-- Audit: KYC status changes
CREATE TRIGGER trg_customer_au
AFTER UPDATE ON customer
FOR EACH ROW
BEGIN
    IF NOT (OLD.kyc_status <=> NEW.kyc_status) THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_value, new_value, changed_by)
        VALUES ('customer', 'UPDATE', NEW.customer_id,
                CONCAT('kyc_status=', OLD.kyc_status),
                CONCAT('kyc_status=', NEW.kyc_status), CURRENT_USER());
    END IF;
END //

-- ---------------------------------------------------------------------
-- SPECIALIZATION: disjointness. A SAVINGS row can only point to an
-- account whose discriminator is SAVINGS (same for CURRENT).
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_savings_bi
BEFORE INSERT ON savings_account
FOR EACH ROW
BEGIN
    IF (SELECT account_type FROM bank_account WHERE account_id = NEW.account_id) <> 'SAVINGS' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Disjoint specialization: account is not of type SAVINGS';
    END IF;
END //

CREATE TRIGGER trg_current_bi
BEFORE INSERT ON current_account
FOR EACH ROW
BEGIN
    IF (SELECT account_type FROM bank_account WHERE account_id = NEW.account_id) <> 'CURRENT' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Disjoint specialization: account is not of type CURRENT';
    END IF;
END //

-- ---------------------------------------------------------------------
-- BANK_ACCOUNT: audit trail of every balance / status change and delete
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_account_au
AFTER UPDATE ON bank_account
FOR EACH ROW
BEGIN
    IF OLD.balance <> NEW.balance OR OLD.status <> NEW.status THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_value, new_value, changed_by)
        VALUES ('bank_account', 'UPDATE', NEW.account_id,
                CONCAT('balance=', OLD.balance, '; status=', OLD.status),
                CONCAT('balance=', NEW.balance, '; status=', NEW.status), CURRENT_USER());
    END IF;
END //

CREATE TRIGGER trg_account_ad
AFTER DELETE ON bank_account
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_value, new_value, changed_by)
    VALUES ('bank_account', 'DELETE', OLD.account_id,
            CONCAT('customer=', OLD.customer_id, '; balance=', OLD.balance, '; type=', OLD.account_type),
            NULL, CURRENT_USER());
END //

-- ---------------------------------------------------------------------
-- UPI_TXN BEFORE INSERT
--   1. derive txn_type (P2M if the payee VPA belongs to a merchant)
--   2. enforce the Rs. 1,00,000 per-day limit per account
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_txn_bi
BEFORE INSERT ON upi_txn
FOR EACH ROW
BEGIN
    DECLARE v_acc INT;

    IF NEW.txn_time IS NULL THEN
        SET NEW.txn_time = NOW();
    END IF;

    SET NEW.txn_type = IF(EXISTS (SELECT 1 FROM merchant WHERE vpa_id = NEW.payee_vpa), 'P2M', 'P2P');

    IF NEW.status = 'SUCCESS' THEN
        SELECT account_id INTO v_acc FROM vpa WHERE vpa_id = NEW.payer_vpa;
        IF fn_daily_spent(v_acc, DATE(NEW.txn_time)) + NEW.amount > 100000 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Daily UPI limit of Rs. 1,00,000 exceeded for this account';
        END IF;
    END IF;
END //

-- ---------------------------------------------------------------------
-- UPI_TXN AFTER INSERT : rule-based fraud monitoring
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_txn_ai
AFTER INSERT ON upi_txn
FOR EACH ROW
BEGIN
    IF NEW.status = 'SUCCESS' THEN

        -- R1 VELOCITY: too many payments from one VPA in a short window
        INSERT IGNORE INTO fraud_alert (txn_id, rule_id, alert_time)
        SELECT NEW.txn_id, r.rule_id, NEW.txn_time
        FROM   fraud_rule r
        WHERE  r.rule_code = 'VELOCITY' AND r.is_active
          AND  (SELECT COUNT(*) FROM upi_txn t
                WHERE t.payer_vpa = NEW.payer_vpa
                  AND t.status = 'SUCCESS'
                  AND t.txn_time BETWEEN NEW.txn_time - INTERVAL r.window_minutes MINUTE
                                     AND NEW.txn_time) >= r.threshold_count;

        -- R2 HIGH_VALUE_NEW_PAYEE: large payment to someone never paid before
        INSERT IGNORE INTO fraud_alert (txn_id, rule_id, alert_time)
        SELECT NEW.txn_id, r.rule_id, NEW.txn_time
        FROM   fraud_rule r
        WHERE  r.rule_code = 'HIGH_VALUE_NEW_PAYEE' AND r.is_active
          AND  NEW.amount >= r.threshold_amount
          AND  NOT EXISTS (SELECT 1 FROM upi_txn t
                           WHERE t.payer_vpa = NEW.payer_vpa
                             AND t.payee_vpa = NEW.payee_vpa
                             AND t.status = 'SUCCESS'
                             AND t.txn_time < NEW.txn_time);

        -- R3 NIGHT_HIGH_VALUE: large payment between midnight and 5 AM
        INSERT IGNORE INTO fraud_alert (txn_id, rule_id, alert_time)
        SELECT NEW.txn_id, r.rule_id, NEW.txn_time
        FROM   fraud_rule r
        WHERE  r.rule_code = 'NIGHT_HIGH_VALUE' AND r.is_active
          AND  HOUR(NEW.txn_time) < 5
          AND  NEW.amount >= r.threshold_amount;

        -- R4 NEW_DEVICE: large payment from a device first seen < 24 h ago
        INSERT IGNORE INTO fraud_alert (txn_id, rule_id, alert_time)
        SELECT NEW.txn_id, r.rule_id, NEW.txn_time
        FROM   fraud_rule r
        JOIN   device d ON d.device_id = NEW.device_id
        WHERE  r.rule_code = 'NEW_DEVICE' AND r.is_active
          AND  NEW.amount >= r.threshold_amount
          AND  d.first_seen > NEW.txn_time - INTERVAL 24 HOUR;

        -- R5 HIGH_RISK_MERCHANT: large P2M payment to a high-risk category
        INSERT IGNORE INTO fraud_alert (txn_id, rule_id, alert_time)
        SELECT NEW.txn_id, r.rule_id, NEW.txn_time
        FROM   fraud_rule r
        JOIN   merchant m           ON m.vpa_id = NEW.payee_vpa
        JOIN   merchant_category mc ON mc.mcc = m.mcc
        WHERE  r.rule_code = 'HIGH_RISK_MERCHANT' AND r.is_active
          AND  mc.risk_level = 'HIGH'
          AND  NEW.amount >= r.threshold_amount;
    END IF;
END //

-- Audit: transaction status changes (e.g. PENDING -> SUCCESS)
CREATE TRIGGER trg_txn_au
AFTER UPDATE ON upi_txn
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_value, new_value, changed_by)
        VALUES ('upi_txn', 'UPDATE', NEW.txn_id,
                CONCAT('status=', OLD.status), CONCAT('status=', NEW.status), CURRENT_USER());
    END IF;
END //

-- Audit: analyst decisions on alerts
CREATE TRIGGER trg_alert_au
AFTER UPDATE ON fraud_alert
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_value, new_value, changed_by)
        VALUES ('fraud_alert', 'UPDATE', NEW.alert_id,
                CONCAT('status=', OLD.status),
                CONCAT('status=', NEW.status, IFNULL(CONCAT('; note=', NEW.analyst_note), '')),
                CURRENT_USER());
    END IF;
END //

-- ---------------------------------------------------------------------
-- DISPUTE (weak entity): assign the partial key and validate ownership
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_dispute_bi
BEFORE INSERT ON dispute
FOR EACH ROW
BEGIN
    DECLARE v_owner  INT;
    DECLARE v_status VARCHAR(7);

    SELECT a.customer_id, t.status INTO v_owner, v_status
    FROM   upi_txn t
    JOIN   vpa v          ON v.vpa_id = t.payer_vpa
    JOIN   bank_account a ON a.account_id = v.account_id
    WHERE  t.txn_id = NEW.txn_id;

    IF v_owner IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transaction does not exist';
    END IF;
    IF v_owner <> NEW.raised_by THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only the payer can raise a dispute on this transaction';
    END IF;
    IF v_status = 'FAILED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot dispute a failed transaction';
    END IF;

    SET NEW.dispute_no = (SELECT COALESCE(MAX(dispute_no), 0) + 1
                          FROM dispute WHERE txn_id = NEW.txn_id);
    IF NEW.raised_on IS NULL THEN
        SET NEW.raised_on = NOW();
    END IF;
END //

DELIMITER ;

SHOW TRIGGERS FROM upishield;
