-- =====================================================================
--  UPIShield - File 06 : Views and (emulated) Materialized Views
--  Guideline: Point 5(c)(vii)  |  Syllabus: Unit 1 (external level),
--             Unit 2 (view and its types), Unit 4 (statistical databases)
-- =====================================================================
USE upishield;

-- ---------------------------------------------------------------------
-- A. ORDINARY VIEWS
-- ---------------------------------------------------------------------

-- 1. Simple, UPDATABLE view with CHECK OPTION
--    Any INSERT/UPDATE through this view must keep the row inside the view
--    (i.e. still an ACTIVE SAVINGS account).
CREATE OR REPLACE VIEW v_active_savings_accounts AS
SELECT account_id, customer_id, ifsc, account_type, balance, status, opened_on
FROM   bank_account
WHERE  account_type = 'SAVINGS' AND status = 'ACTIVE'
WITH CASCADED CHECK OPTION;

-- 2. Support-desk view (security level INTERNAL): masked data, no balances
CREATE OR REPLACE VIEW v_support_customer AS
SELECT c.customer_id,
       c.full_name,
       CONCAT('XXXXXX', RIGHT(c.phone, 4))   AS phone_masked,
       c.city,
       c.kyc_status,
       a.account_id,
       fn_mask_account(a.account_no_last4)  AS account_no,
       b.bank_name,
       a.account_type,
       a.status                             AS account_status,
       v.vpa_id
FROM   customer c
JOIN   bank_account a ON a.customer_id = c.customer_id
JOIN   branch br      ON br.ifsc = a.ifsc
JOIN   bank b         ON b.bank_code = br.bank_code
LEFT JOIN vpa v       ON v.account_id = a.account_id AND v.is_primary;

-- 3. Fraud-analyst view (security level CONFIDENTIAL)
CREATE OR REPLACE VIEW v_fraud_analyst_alerts AS
SELECT fa.alert_id, fa.alert_time, r.rule_code, r.severity, fa.status AS alert_status,
       t.txn_id, t.amount, t.txn_type, t.payer_vpa, t.payee_vpa, t.device_id,
       c.customer_id AS payer_customer_id, c.full_name AS payer_name, c.city AS payer_city,
       fa.analyst_note
FROM   fraud_alert fa
JOIN   fraud_rule r    ON r.rule_id = fa.rule_id
JOIN   upi_txn t       ON t.txn_id = fa.txn_id
JOIN   vpa v           ON v.vpa_id = t.payer_vpa
JOIN   bank_account a  ON a.account_id = v.account_id
JOIN   customer c      ON c.customer_id = a.customer_id;

-- 4. Auditor view (security level SECRET)
CREATE OR REPLACE VIEW v_auditor_trail AS
SELECT log_id, changed_at, changed_by, table_name, operation, record_id, old_value, new_value
FROM   audit_log;

-- 5. Complex (aggregate, non-updatable) view
CREATE OR REPLACE VIEW v_merchant_performance AS
SELECT m.merchant_id, m.merchant_name, m.merchant_type, mc.description AS category,
       mc.risk_level, m.city,
       COUNT(t.txn_id)                       AS successful_txns,
       COALESCE(SUM(t.amount), 0)            AS total_collected,
       ROUND(COALESCE(AVG(t.amount), 0), 2)  AS avg_ticket,
       COUNT(DISTINCT t.payer_vpa)           AS unique_payers
FROM   merchant m
JOIN   merchant_category mc ON mc.mcc = m.mcc
LEFT JOIN upi_txn t ON t.payee_vpa = m.vpa_id AND t.status = 'SUCCESS'
GROUP BY m.merchant_id, m.merchant_name, m.merchant_type, mc.description, mc.risk_level, m.city;

-- 6. STATISTICAL view (security level PUBLIC): aggregates only, and groups
--    smaller than 5 customers are suppressed so that no individual can be
--    inferred from the statistics (inference control).
CREATE OR REPLACE VIEW v_public_city_stats AS
SELECT c.city,
       COUNT(DISTINCT c.customer_id)  AS customers,
       COUNT(t.txn_id)                AS successful_txns,
       ROUND(AVG(t.amount), 2)        AS avg_txn_amount
FROM   customer c
JOIN   bank_account a ON a.customer_id = c.customer_id
JOIN   vpa v          ON v.account_id = a.account_id
JOIN   upi_txn t      ON t.payer_vpa = v.vpa_id AND t.status = 'SUCCESS'
GROUP BY c.city
HAVING COUNT(DISTINCT c.customer_id) >= 5;

-- 7. Customer 360 view (used by the front end)
CREATE OR REPLACE VIEW v_customer_summary AS
SELECT c.customer_id, c.full_name, c.city, c.kyc_status,
       (SELECT COUNT(*) FROM bank_account a
         WHERE a.customer_id = c.customer_id)                       AS accounts,
       (SELECT COALESCE(SUM(a.balance), 0) FROM bank_account a
         WHERE a.customer_id = c.customer_id)                       AS total_balance,
       ref.full_name                                                AS referred_by_name,
       fn_risk_score(c.customer_id)                                 AS risk_score
FROM   customer c
LEFT JOIN customer ref ON ref.customer_id = c.referred_by;

-- ---------------------------------------------------------------------
-- B. MATERIALIZED VIEWS (emulated)
--    MySQL has no CREATE MATERIALIZED VIEW.  A materialized view stores the
--    RESULT of a query physically and is refreshed on demand/schedule.
--    We emulate it with: a summary table + a refresh procedure + an EVENT.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS mv_daily_merchant_volume;
CREATE TABLE mv_daily_merchant_volume (
    txn_date        DATE           NOT NULL,
    merchant_id     INT            NOT NULL,
    merchant_name   VARCHAR(100)   NOT NULL,
    txn_count       INT            NOT NULL,
    gross_amount    DECIMAL(14,2)  NOT NULL,
    refreshed_at    DATETIME       NOT NULL,
    PRIMARY KEY (txn_date, merchant_id)
) ENGINE = InnoDB;

DROP TABLE IF EXISTS mv_city_fraud_stats;
CREATE TABLE mv_city_fraud_stats (
    city             VARCHAR(50)    NOT NULL,
    total_txns       INT            NOT NULL,
    flagged_txns     INT            NOT NULL,
    confirmed_fraud  INT            NOT NULL,
    fraud_rate_pct   DECIMAL(6,3)   NOT NULL,
    refreshed_at     DATETIME       NOT NULL,
    PRIMARY KEY (city)
) ENGINE = InnoDB;

DROP PROCEDURE IF EXISTS sp_refresh_mv_daily_merchant_volume;
DROP PROCEDURE IF EXISTS sp_refresh_mv_city_fraud_stats;
DROP PROCEDURE IF EXISTS sp_refresh_all_mv;

DELIMITER //
CREATE PROCEDURE sp_refresh_mv_daily_merchant_volume()
BEGIN
    -- DELETE (not TRUNCATE) so the refresh is transactional and readers never
    -- see an empty table
    START TRANSACTION;
        DELETE FROM mv_daily_merchant_volume;
        INSERT INTO mv_daily_merchant_volume
        SELECT DATE(t.txn_time), m.merchant_id, m.merchant_name,
               COUNT(*), SUM(t.amount), NOW()
        FROM   upi_txn t
        JOIN   merchant m ON m.vpa_id = t.payee_vpa
        WHERE  t.status = 'SUCCESS'
        GROUP BY DATE(t.txn_time), m.merchant_id, m.merchant_name;
    COMMIT;
END //

CREATE PROCEDURE sp_refresh_mv_city_fraud_stats()
BEGIN
    START TRANSACTION;
        DELETE FROM mv_city_fraud_stats;
        INSERT INTO mv_city_fraud_stats
        SELECT c.city,
               COUNT(*),
               SUM(EXISTS (SELECT 1 FROM fraud_alert fa WHERE fa.txn_id = t.txn_id)),
               SUM(EXISTS (SELECT 1 FROM fraud_alert fa WHERE fa.txn_id = t.txn_id
                                                         AND fa.status = 'CONFIRMED_FRAUD')),
               ROUND(100 * SUM(EXISTS (SELECT 1 FROM fraud_alert fa WHERE fa.txn_id = t.txn_id)) / COUNT(*), 3),
               NOW()
        FROM   upi_txn t
        JOIN   vpa v          ON v.vpa_id = t.payer_vpa
        JOIN   bank_account a ON a.account_id = v.account_id
        JOIN   customer c     ON c.customer_id = a.customer_id
        WHERE  t.status = 'SUCCESS'
        GROUP BY c.city;
    COMMIT;
END //

CREATE PROCEDURE sp_refresh_all_mv()
BEGIN
    CALL sp_refresh_mv_daily_merchant_volume();
    CALL sp_refresh_mv_city_fraud_stats();
END //
DELIMITER ;

-- first refresh
CALL sp_refresh_all_mv();

-- Scheduled refresh every hour (requires the event scheduler to be ON)
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_refresh_materialized_views;
CREATE EVENT ev_refresh_materialized_views
ON SCHEDULE EVERY 1 HOUR STARTS CURRENT_TIMESTAMP + INTERVAL 1 HOUR
COMMENT 'Refreshes the emulated materialized views'
DO CALL sp_refresh_all_mv();

SHOW FULL TABLES IN upishield WHERE Table_type = 'VIEW';
SELECT * FROM mv_city_fraud_stats ORDER BY fraud_rate_pct DESC;
