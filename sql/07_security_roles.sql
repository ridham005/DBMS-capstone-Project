-- =====================================================================
--  UPIShield - File 07 : Security setup (roles, users, access levels)
--  Guideline: Point 5(c)(iii) DCL  |  Syllabus Unit 4: Discretionary &
--             Mandatory Access Control, Multi-Level Security
--  Run as root / an admin account.
-- =====================================================================
USE upishield;

-- ---------------------------------------------------------------------
-- Multi-level security (simulated MAC).
-- MySQL has no native mandatory access control, so each data object gets a
-- classification level and each role a clearance level.  A role may only
-- read objects at or below its clearance ("no read up"); this is enforced
-- by granting each role ONLY the views of its level and below.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS security_level;
CREATE TABLE security_level (
    level_no      TINYINT      NOT NULL,
    level_name    VARCHAR(15)  NOT NULL,
    role_name     VARCHAR(30)  NOT NULL,
    objects       VARCHAR(255) NOT NULL,
    CONSTRAINT pk_security_level PRIMARY KEY (level_no),
    CONSTRAINT uq_security_name  UNIQUE (level_name),
    CONSTRAINT chk_level_no      CHECK (level_no BETWEEN 1 AND 4)
);
INSERT INTO security_level VALUES
 (1, 'PUBLIC',       'upi_public',  'v_public_city_stats, mv_city_fraud_stats'),
 (2, 'INTERNAL',     'upi_support', 'level 1 + v_support_customer, v_merchant_performance'),
 (3, 'CONFIDENTIAL', 'upi_analyst', 'level 2 + v_fraud_analyst_alerts, upi_txn, fraud_alert, dispute'),
 (4, 'SECRET',       'upi_auditor', 'level 3 + v_auditor_trail, audit_log, fn_enc_key (decryption)');

-- ---------------------------------------------------------------------
-- Roles (Discretionary Access Control with GRANT)
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'upi_public', 'upi_support', 'upi_analyst', 'upi_auditor', 'upi_admin', 'upi_app';
CREATE ROLE 'upi_public', 'upi_support', 'upi_analyst', 'upi_auditor', 'upi_admin', 'upi_app';

-- Level 1 PUBLIC
GRANT SELECT ON upishield.v_public_city_stats  TO 'upi_public';
GRANT SELECT ON upishield.mv_city_fraud_stats  TO 'upi_public';

-- Level 2 INTERNAL (support desk) = level 1 + masked customer data
GRANT 'upi_public' TO 'upi_support';
GRANT SELECT ON upishield.v_support_customer      TO 'upi_support';
GRANT SELECT ON upishield.v_merchant_performance  TO 'upi_support';
GRANT SELECT, INSERT ON upishield.dispute         TO 'upi_support';

-- Level 3 CONFIDENTIAL (fraud analyst) = level 2 + transactions and alerts
GRANT 'upi_support' TO 'upi_analyst';
GRANT SELECT ON upishield.v_fraud_analyst_alerts  TO 'upi_analyst';
GRANT SELECT ON upishield.upi_txn                 TO 'upi_analyst';
GRANT SELECT ON upishield.fraud_rule              TO 'upi_analyst';
GRANT SELECT, UPDATE (status, analyst_note) ON upishield.fraud_alert TO 'upi_analyst';
GRANT SELECT, UPDATE (status, resolved_on)  ON upishield.dispute     TO 'upi_analyst';

-- Level 4 SECRET (auditor) = level 3 + audit trail + decryption key
GRANT 'upi_analyst' TO 'upi_auditor';
GRANT SELECT ON upishield.v_auditor_trail  TO 'upi_auditor';
GRANT SELECT ON upishield.audit_log        TO 'upi_auditor';
GRANT EXECUTE ON FUNCTION upishield.fn_enc_key TO 'upi_auditor';

-- Administrator: everything on the database
GRANT ALL PRIVILEGES ON upishield.* TO 'upi_admin';

-- Application account used by the Python front end
GRANT SELECT, INSERT, UPDATE ON upishield.* TO 'upi_app';
GRANT EXECUTE ON upishield.* TO 'upi_app';

-- ---------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------
DROP USER IF EXISTS 'support_riya'@'localhost', 'analyst_karan'@'localhost',
                    'auditor_meera'@'localhost', 'public_dash'@'localhost',
                    'upishield_app'@'localhost';
CREATE USER 'support_riya'@'localhost'  IDENTIFIED BY 'Support@2026';
CREATE USER 'analyst_karan'@'localhost' IDENTIFIED BY 'Analyst@2026';
CREATE USER 'auditor_meera'@'localhost' IDENTIFIED BY 'Auditor@2026';
CREATE USER 'public_dash'@'localhost'   IDENTIFIED BY 'Public@2026';
CREATE USER 'upishield_app'@'localhost' IDENTIFIED BY 'UpiApp@2026';

GRANT 'upi_support' TO 'support_riya'@'localhost';
GRANT 'upi_analyst' TO 'analyst_karan'@'localhost';
GRANT 'upi_auditor' TO 'auditor_meera'@'localhost';
GRANT 'upi_public'  TO 'public_dash'@'localhost';
GRANT 'upi_app'     TO 'upishield_app'@'localhost';

SET DEFAULT ROLE ALL TO 'support_riya'@'localhost', 'analyst_karan'@'localhost',
                        'auditor_meera'@'localhost', 'public_dash'@'localhost',
                        'upishield_app'@'localhost';

SHOW GRANTS FOR 'upi_analyst';
SELECT * FROM security_level;
