-- =====================================================================
--  UPIShield - Q07 : Views and Materialized Views
--  Guideline 5(c)(vii).   Definitions are in sql/06_views.sql.
-- =====================================================================
USE upishield;

-- ---------------------------------------------------------------------
-- 1. Querying views (external level of the 3-level architecture)
-- ---------------------------------------------------------------------
SELECT * FROM v_support_customer      WHERE city = 'Gandhinagar' LIMIT 10;
SELECT * FROM v_merchant_performance  ORDER BY total_collected DESC LIMIT 10;
SELECT * FROM v_fraud_analyst_alerts  WHERE alert_status IN ('OPEN', 'INVESTIGATING');
SELECT * FROM v_public_city_stats;
SELECT * FROM v_customer_summary      ORDER BY risk_score DESC LIMIT 10;

-- ---------------------------------------------------------------------
-- 2. Updatable view + WITH CHECK OPTION
-- ---------------------------------------------------------------------
SET @sav := (SELECT MIN(account_id) FROM v_active_savings_accounts);

START TRANSACTION;
    -- allowed: row stays inside the view (still ACTIVE SAVINGS)
    UPDATE v_active_savings_accounts SET balance = balance + 1 WHERE account_id = @sav;
    SELECT account_id, balance FROM bank_account WHERE account_id = @sav;
ROLLBACK;

-- [EXPECTED ERROR] CHECK OPTION failed: the row would leave the view
UPDATE v_active_savings_accounts SET status = 'FROZEN' WHERE account_id = @sav;

-- [EXPECTED ERROR] aggregate views are not updatable
UPDATE v_merchant_performance SET total_collected = 0 WHERE merchant_id = 701;

-- Which views are updatable?
SELECT TABLE_NAME, IS_UPDATABLE, CHECK_OPTION
FROM   information_schema.VIEWS
WHERE  TABLE_SCHEMA = 'upishield';

-- ---------------------------------------------------------------------
-- 3. CREATE OR REPLACE / ALTER / DROP VIEW
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_high_value_txns AS
SELECT txn_id, payer_vpa, payee_vpa, amount, txn_time
FROM   upi_txn WHERE status = 'SUCCESS' AND amount >= 25000;

ALTER VIEW v_high_value_txns AS
SELECT txn_id, payer_vpa, payee_vpa, amount, txn_type, txn_time
FROM   upi_txn WHERE status = 'SUCCESS' AND amount >= 30000;

SELECT COUNT(*) AS high_value_txns FROM v_high_value_txns;
SHOW CREATE VIEW v_high_value_txns;
DROP VIEW v_high_value_txns;

-- ---------------------------------------------------------------------
-- 4. MATERIALIZED VIEW (emulated)
--    A normal view is re-computed on every read; a materialized view stores
--    the result and becomes STALE until it is refreshed.
-- ---------------------------------------------------------------------
SELECT * FROM mv_daily_merchant_volume ORDER BY txn_date DESC, gross_amount DESC LIMIT 5;

-- make a new merchant payment today
SET @payer := (SELECT vpa_id FROM vpa WHERE account_id = 50001 AND is_primary);
SET @shop  := (SELECT vpa_id FROM merchant WHERE merchant_id = 701);
CALL sp_transfer(@payer, @shop, 250.00, NULL, 'MV staleness demo', @t, @s, @m);
SELECT @t AS txn_id, @s AS status;

-- the MV does NOT show today's payment yet (stale) ...
SELECT * FROM mv_daily_merchant_volume WHERE txn_date = CURDATE() AND merchant_id = 701;

-- ... until it is refreshed
CALL sp_refresh_mv_daily_merchant_volume();
SELECT * FROM mv_daily_merchant_volume WHERE txn_date = CURDATE() AND merchant_id = 701;

-- the scheduled refresh
SHOW EVENTS FROM upishield;
SELECT * FROM mv_city_fraud_stats ORDER BY fraud_rate_pct DESC;
