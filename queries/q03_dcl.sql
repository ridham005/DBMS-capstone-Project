-- =====================================================================
--  UPIShield - Q03 : DCL  (GRANT, REVOKE)
--  Guideline 5(c)(iii)  |  Syllabus Unit 4: Discretionary Access Control
--  Run as root.  Roles and users are created in sql/07_security_roles.sql.
--
--  To SEE the effect, open a second connection as the user, e.g.
--      mysql -u support_riya -pSupport@2026 upishield
--  and run the SELECT shown in each step.
-- =====================================================================
USE upishield;

-- ---------------------------------------------------------------------
-- 1. What each role may do (privileges flow down the role hierarchy)
-- ---------------------------------------------------------------------
SHOW GRANTS FOR 'upi_support';
SHOW GRANTS FOR 'analyst_karan'@'localhost' USING 'upi_analyst';

-- ---------------------------------------------------------------------
-- 2. GRANT an object privilege to a role
--    Support staff should also see the daily merchant volume report.
--    (as support_riya:  SELECT * FROM mv_daily_merchant_volume LIMIT 5;
--     -> denied before this GRANT, allowed after it)
-- ---------------------------------------------------------------------
GRANT SELECT ON upishield.mv_daily_merchant_volume TO 'upi_support';
SHOW GRANTS FOR 'upi_support';

-- ---------------------------------------------------------------------
-- 3. Column-level GRANT
--    The analyst may update only the status and note of an alert,
--    not the txn_id or rule_id (already granted in file 07):
-- ---------------------------------------------------------------------
GRANT SELECT (city, kyc_status) ON upishield.customer TO 'upi_public';
SHOW GRANTS FOR 'upi_public';

-- ---------------------------------------------------------------------
-- 4. GRANT ... WITH GRANT OPTION (delegation) and a direct user grant
-- ---------------------------------------------------------------------
DROP USER IF EXISTS 'teamlead_om'@'localhost';
CREATE USER 'teamlead_om'@'localhost' IDENTIFIED BY 'Lead@2026';
GRANT SELECT ON upishield.v_merchant_performance TO 'teamlead_om'@'localhost' WITH GRANT OPTION;
SHOW GRANTS FOR 'teamlead_om'@'localhost';

-- ---------------------------------------------------------------------
-- 5. REVOKE
-- ---------------------------------------------------------------------
REVOKE SELECT ON upishield.mv_daily_merchant_volume FROM 'upi_support';
REVOKE SELECT (city, kyc_status) ON upishield.customer FROM 'upi_public';
REVOKE GRANT OPTION ON upishield.v_merchant_performance FROM 'teamlead_om'@'localhost';
SHOW GRANTS FOR 'upi_support';
SHOW GRANTS FOR 'teamlead_om'@'localhost';

-- Revoke a role from a user (the user loses all its privileges at once)
REVOKE 'upi_support' FROM 'support_riya'@'localhost';
SHOW GRANTS FOR 'support_riya'@'localhost';
GRANT  'upi_support' TO   'support_riya'@'localhost';    -- give it back
SET DEFAULT ROLE ALL TO 'support_riya'@'localhost';

-- Remove all privileges from a user, then drop the user
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'teamlead_om'@'localhost';
DROP USER 'teamlead_om'@'localhost';

-- Who has which role?
SELECT FROM_USER AS role_name, TO_USER AS granted_to
FROM   mysql.role_edges
WHERE  FROM_USER LIKE 'upi\_%'
ORDER BY role_name;
