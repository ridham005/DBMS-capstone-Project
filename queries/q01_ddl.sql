-- =====================================================================
--  UPIShield - Q01 : DDL  (CREATE, ALTER, RENAME, TRUNCATE, DROP)
--  Guideline 5(c)(i).   The full schema CREATE statements are in
--  sql/01_create_schema.sql.  This file demonstrates every DDL command on
--  a new feature table (cashback campaigns) so the main schema is untouched.
--  Note: every DDL statement auto-commits in MySQL (cannot be rolled back).
-- =====================================================================
USE upishield;
DROP TABLE IF EXISTS cashback_campaign;
DROP TABLE IF EXISTS promo_campaign;

-- ---------------------------------------------------------------------
-- 1. CREATE with integrity constraints (PK, FK, UNIQUE, NOT NULL, CHECK, DEFAULT)
-- ---------------------------------------------------------------------
CREATE TABLE promo_campaign (
    campaign_id     INT            NOT NULL AUTO_INCREMENT,
    campaign_code   VARCHAR(20)    NOT NULL,
    merchant_id     INT            NOT NULL,
    cashback_pct    DECIMAL(4,2)   NOT NULL,
    max_cashback    DECIMAL(8,2)   NOT NULL DEFAULT 100.00,
    start_date      DATE           NOT NULL,
    end_date        DATE           NOT NULL,
    CONSTRAINT pk_campaign        PRIMARY KEY (campaign_id),
    CONSTRAINT uq_campaign_code   UNIQUE (campaign_code),
    CONSTRAINT chk_cashback_pct   CHECK (cashback_pct > 0 AND cashback_pct <= 20),
    CONSTRAINT chk_campaign_dates CHECK (end_date >= start_date),
    CONSTRAINT fk_campaign_merchant FOREIGN KEY (merchant_id) REFERENCES merchant (merchant_id)
        ON DELETE CASCADE
);
DESCRIBE promo_campaign;

INSERT INTO promo_campaign (campaign_code, merchant_id, cashback_pct, start_date, end_date)
VALUES ('DIWALI10', 701, 10.00, '2026-11-01', '2026-11-15'),
       ('FUEL5',    (SELECT MIN(merchant_id) FROM merchant WHERE mcc = '5541'), 5.00, '2026-11-01', '2026-11-30');

-- [EXPECTED ERROR] CHECK constraint violated: end date before start date
INSERT INTO promo_campaign (campaign_code, merchant_id, cashback_pct, start_date, end_date)
VALUES ('BADDATES', 701, 5.00, '2026-12-10', '2026-12-01');

-- ---------------------------------------------------------------------
-- 2. ALTER : add / modify / rename columns, add / drop constraints
-- ---------------------------------------------------------------------
ALTER TABLE promo_campaign ADD COLUMN max_redemptions INT NULL AFTER max_cashback;
ALTER TABLE promo_campaign MODIFY COLUMN max_cashback DECIMAL(10,2) NOT NULL DEFAULT 150.00;
ALTER TABLE promo_campaign RENAME COLUMN max_cashback TO max_cashback_amount;
-- (a column used inside a CHECK constraint, e.g. cashback_pct, cannot be renamed)
ALTER TABLE promo_campaign ADD CONSTRAINT chk_redemptions CHECK (max_redemptions IS NULL OR max_redemptions > 0);
ALTER TABLE promo_campaign ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE promo_campaign DROP CHECK chk_redemptions;
ALTER TABLE promo_campaign ADD INDEX idx_campaign_dates (start_date, end_date);
DESCRIBE promo_campaign;

-- ALTER on a real table (and back again)
ALTER TABLE customer ADD COLUMN alternate_phone CHAR(10) NULL;
DESCRIBE customer;
ALTER TABLE customer DROP COLUMN alternate_phone;

-- ---------------------------------------------------------------------
-- 3. RENAME
-- ---------------------------------------------------------------------
RENAME TABLE promo_campaign TO cashback_campaign;
SHOW TABLES LIKE '%campaign%';
SELECT * FROM cashback_campaign;

-- ---------------------------------------------------------------------
-- 4. TRUNCATE : removes all rows, keeps the structure, resets AUTO_INCREMENT
--    (DDL - faster than DELETE, cannot be rolled back, fires no triggers)
-- ---------------------------------------------------------------------
TRUNCATE TABLE cashback_campaign;
SELECT COUNT(*) AS rows_after_truncate FROM cashback_campaign;

-- [EXPECTED ERROR] cannot TRUNCATE a table that other tables reference
TRUNCATE TABLE merchant_category;

-- ---------------------------------------------------------------------
-- 5. DROP
-- ---------------------------------------------------------------------
DROP TABLE cashback_campaign;
SHOW TABLES LIKE '%campaign%';

-- [EXPECTED ERROR] cannot DROP a parent table while child FKs exist
DROP TABLE bank;
