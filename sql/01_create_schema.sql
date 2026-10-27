-- =====================================================================
--  UPIShield : A Database System for UPI Payments and Fraud Monitoring
--  File 01  : Schema creation (DDL with all integrity constraints)
--  Engine   : MySQL 8.0.31+ (InnoDB)
--  Guideline: Point 5(a) - create all tables with integrity constraints
-- =====================================================================

DROP DATABASE IF EXISTS upishield;
CREATE DATABASE upishield CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE upishield;

-- ---------------------------------------------------------------------
-- 1. BANK  (strong entity)
-- ---------------------------------------------------------------------
CREATE TABLE bank (
    bank_code         CHAR(4)       NOT NULL,
    bank_name         VARCHAR(100)  NOT NULL,
    bank_type         VARCHAR(12)   NOT NULL,
    hq_city           VARCHAR(50)   NOT NULL,
    established_year  SMALLINT      NOT NULL,
    CONSTRAINT pk_bank            PRIMARY KEY (bank_code),
    CONSTRAINT uq_bank_name       UNIQUE (bank_name),
    CONSTRAINT chk_bank_type      CHECK (bank_type IN ('PUBLIC','PRIVATE','PAYMENTS','COOPERATIVE')),
    CONSTRAINT chk_bank_year      CHECK (established_year BETWEEN 1800 AND 2026)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 2. BRANCH  (identified by IFSC; bank code change cascades here)
-- ---------------------------------------------------------------------
CREATE TABLE branch (
    ifsc         CHAR(11)      NOT NULL,
    bank_code    CHAR(4)       NOT NULL,
    branch_name  VARCHAR(100)  NOT NULL,
    city         VARCHAR(50)   NOT NULL,
    state        VARCHAR(50)   NOT NULL,
    CONSTRAINT pk_branch       PRIMARY KEY (ifsc),
    CONSTRAINT chk_ifsc_format CHECK (REGEXP_LIKE(ifsc, '^[A-Z]{4}0[A-Z0-9]{6}$', 'c')),
    CONSTRAINT fk_branch_bank  FOREIGN KEY (bank_code) REFERENCES bank (bank_code)
        ON UPDATE CASCADE       -- demo: UPDATE with cascade (bank merger)
        ON DELETE RESTRICT
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 3. CUSTOMER  (recursive relationship: referred_by -> customer)
-- ---------------------------------------------------------------------
CREATE TABLE customer (
    customer_id  INT           NOT NULL AUTO_INCREMENT,
    full_name    VARCHAR(100)  NOT NULL,
    phone        CHAR(10)      NOT NULL,
    email        VARCHAR(100)  NULL,
    dob          DATE          NOT NULL,
    city         VARCHAR(50)   NOT NULL,
    kyc_status   VARCHAR(10)   NOT NULL DEFAULT 'PENDING',
    referred_by  INT           NULL,
    created_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_customer        PRIMARY KEY (customer_id),
    CONSTRAINT uq_customer_phone  UNIQUE (phone),
    CONSTRAINT uq_customer_email  UNIQUE (email),
    CONSTRAINT chk_phone_format   CHECK (REGEXP_LIKE(phone, '^[6-9][0-9]{9}$')),
    CONSTRAINT chk_email_format   CHECK (email IS NULL OR email LIKE '%_@_%._%'),
    CONSTRAINT chk_kyc_status     CHECK (kyc_status IN ('PENDING','VERIFIED','REJECTED')),
    CONSTRAINT fk_customer_referrer FOREIGN KEY (referred_by) REFERENCES customer (customer_id)
        ON DELETE SET NULL          -- recursive relationship (self-reference)
) ENGINE = InnoDB AUTO_INCREMENT = 1001;

-- ---------------------------------------------------------------------
-- 4. BANK_ACCOUNT  (superclass of SAVINGS_ACCOUNT / CURRENT_ACCOUNT)
--    Specialization: disjoint (account_type discriminator), total
-- ---------------------------------------------------------------------
CREATE TABLE bank_account (
    account_id        INT            NOT NULL AUTO_INCREMENT,
    customer_id       INT            NOT NULL,
    ifsc              CHAR(11)       NOT NULL,
    account_no_enc    VARBINARY(64)  NOT NULL,     -- AES_ENCRYPT(account number)
    account_no_last4  CHAR(4)        NOT NULL,
    account_type      VARCHAR(10)    NOT NULL,
    balance           DECIMAL(14,2)  NOT NULL DEFAULT 0.00,
    status            VARCHAR(10)    NOT NULL DEFAULT 'ACTIVE',
    opened_on         DATE           NOT NULL,
    CONSTRAINT pk_account          PRIMARY KEY (account_id),
    CONSTRAINT uq_account_no       UNIQUE (account_no_enc),
    CONSTRAINT chk_acc_last4       CHECK (REGEXP_LIKE(account_no_last4, '^[0-9]{4}$')),
    CONSTRAINT chk_acc_type        CHECK (account_type IN ('SAVINGS','CURRENT')),
    CONSTRAINT chk_acc_balance     CHECK (balance >= 0),
    CONSTRAINT chk_acc_status      CHECK (status IN ('ACTIVE','FROZEN','CLOSED')),
    CONSTRAINT fk_account_customer FOREIGN KEY (customer_id) REFERENCES customer (customer_id)
        ON DELETE RESTRICT          -- demo: DELETE without cascade
        ON UPDATE CASCADE,
    CONSTRAINT fk_account_branch   FOREIGN KEY (ifsc) REFERENCES branch (ifsc)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE = InnoDB AUTO_INCREMENT = 50001;

CREATE TABLE savings_account (
    account_id     INT           NOT NULL,
    interest_rate  DECIMAL(4,2)  NOT NULL DEFAULT 3.00,
    min_balance    DECIMAL(10,2) NOT NULL DEFAULT 1000.00,
    CONSTRAINT pk_savings          PRIMARY KEY (account_id),
    CONSTRAINT chk_sav_interest    CHECK (interest_rate BETWEEN 0 AND 10),
    CONSTRAINT chk_sav_min_balance CHECK (min_balance >= 0),
    CONSTRAINT fk_savings_account  FOREIGN KEY (account_id) REFERENCES bank_account (account_id)
        ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE TABLE current_account (
    account_id     INT           NOT NULL,
    business_name  VARCHAR(100)  NOT NULL,
    gstin          CHAR(15)      NULL,
    CONSTRAINT pk_current          PRIMARY KEY (account_id),
    CONSTRAINT uq_current_gstin    UNIQUE (gstin),
    CONSTRAINT chk_gstin_format    CHECK (gstin IS NULL OR
        REGEXP_LIKE(gstin, '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$', 'c')),
    CONSTRAINT fk_current_account  FOREIGN KEY (account_id) REFERENCES bank_account (account_id)
        ON DELETE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 5. VPA  (UPI ID, e.g. jeet.s@oksbi)
-- ---------------------------------------------------------------------
CREATE TABLE vpa (
    vpa_id      VARCHAR(50)  NOT NULL,
    account_id  INT          NOT NULL,
    is_primary  BOOLEAN      NOT NULL DEFAULT TRUE,
    created_on  DATE         NOT NULL,
    CONSTRAINT pk_vpa          PRIMARY KEY (vpa_id),
    CONSTRAINT chk_vpa_format  CHECK (REGEXP_LIKE(vpa_id, '^[a-z0-9._-]{3,}@[a-z]{2,}$', 'c')),
    CONSTRAINT fk_vpa_account  FOREIGN KEY (account_id) REFERENCES bank_account (account_id)
        ON DELETE CASCADE          -- demo: DELETE with cascade
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 6. MERCHANT_CATEGORY / MERCHANT (superclass of SMALL / ENTERPRISE)
-- ---------------------------------------------------------------------
CREATE TABLE merchant_category (
    mcc          CHAR(4)       NOT NULL,
    description  VARCHAR(100)  NOT NULL,
    risk_level   VARCHAR(6)    NOT NULL,
    CONSTRAINT pk_mcc           PRIMARY KEY (mcc),
    CONSTRAINT uq_mcc_desc      UNIQUE (description),
    CONSTRAINT chk_mcc_format   CHECK (REGEXP_LIKE(mcc, '^[0-9]{4}$')),
    CONSTRAINT chk_mcc_risk     CHECK (risk_level IN ('LOW','MEDIUM','HIGH'))
) ENGINE = InnoDB;

CREATE TABLE merchant (
    merchant_id    INT           NOT NULL AUTO_INCREMENT,
    merchant_name  VARCHAR(100)  NOT NULL,
    vpa_id         VARCHAR(50)   NOT NULL,
    mcc            CHAR(4)       NOT NULL,
    city           VARCHAR(50)   NOT NULL,
    merchant_type  VARCHAR(10)   NOT NULL,
    onboarded_on   DATE          NOT NULL,
    CONSTRAINT pk_merchant         PRIMARY KEY (merchant_id),
    CONSTRAINT uq_merchant_vpa     UNIQUE (vpa_id),
    CONSTRAINT chk_merchant_type   CHECK (merchant_type IN ('SMALL','ENTERPRISE')),
    CONSTRAINT fk_merchant_vpa     FOREIGN KEY (vpa_id) REFERENCES vpa (vpa_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_merchant_mcc     FOREIGN KEY (mcc) REFERENCES merchant_category (mcc)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT         -- demo: UPDATE without cascade (blocked)
) ENGINE = InnoDB AUTO_INCREMENT = 701;

CREATE TABLE small_merchant (
    merchant_id             INT            NOT NULL,
    daily_collection_limit  DECIMAL(12,2)  NOT NULL DEFAULT 200000.00,
    static_qr               BOOLEAN        NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_small_merchant  PRIMARY KEY (merchant_id),
    CONSTRAINT chk_small_limit    CHECK (daily_collection_limit > 0),
    CONSTRAINT fk_small_merchant  FOREIGN KEY (merchant_id) REFERENCES merchant (merchant_id)
        ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE TABLE enterprise_merchant (
    merchant_id       INT           NOT NULL,
    mdr_rate          DECIMAL(4,2)  NOT NULL DEFAULT 0.30,   -- % fee charged on settlement
    settlement_cycle  VARCHAR(4)    NOT NULL DEFAULT 'T+1',
    gst_registered    BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_ent_merchant   PRIMARY KEY (merchant_id),
    CONSTRAINT chk_ent_mdr       CHECK (mdr_rate BETWEEN 0 AND 3),
    CONSTRAINT chk_ent_cycle     CHECK (settlement_cycle IN ('T+0','T+1','T+2')),
    CONSTRAINT fk_ent_merchant   FOREIGN KEY (merchant_id) REFERENCES merchant (merchant_id)
        ON DELETE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 7. DEVICE  and  DEVICE_LOGIN  (M:N between CUSTOMER and DEVICE)
-- ---------------------------------------------------------------------
CREATE TABLE device (
    device_id   VARCHAR(20)  NOT NULL,
    model       VARCHAR(50)  NOT NULL,
    os          VARCHAR(7)   NOT NULL,
    os_version  VARCHAR(10)  NULL,
    first_seen  DATETIME     NOT NULL,
    CONSTRAINT pk_device     PRIMARY KEY (device_id),
    CONSTRAINT chk_device_os CHECK (os IN ('ANDROID','IOS'))
) ENGINE = InnoDB;

CREATE TABLE device_login (
    customer_id  INT          NOT NULL,
    device_id    VARCHAR(20)  NOT NULL,
    login_time   DATETIME     NOT NULL,
    ip_address   VARCHAR(45)  NOT NULL,
    CONSTRAINT pk_device_login      PRIMARY KEY (customer_id, device_id, login_time),
    CONSTRAINT fk_login_customer    FOREIGN KEY (customer_id) REFERENCES customer (customer_id)
        ON DELETE RESTRICT,         -- login history is kept for fraud forensics
    CONSTRAINT fk_login_device      FOREIGN KEY (device_id) REFERENCES device (device_id)
        ON DELETE RESTRICT
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 8. UPI_TXN  (central fact table)
-- ---------------------------------------------------------------------
CREATE TABLE upi_txn (
    txn_id          BIGINT         NOT NULL AUTO_INCREMENT,
    payer_vpa       VARCHAR(50)    NOT NULL,
    payee_vpa       VARCHAR(50)    NOT NULL,
    amount          DECIMAL(12,2)  NOT NULL,
    txn_type        VARCHAR(3)     NOT NULL DEFAULT 'P2P',   -- set by trigger
    status          VARCHAR(7)     NOT NULL DEFAULT 'PENDING',
    device_id       VARCHAR(20)    NULL,
    remarks         VARCHAR(100)   NULL,
    failure_reason  VARCHAR(255)   NULL,
    txn_time        DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_upi_txn        PRIMARY KEY (txn_id),
    CONSTRAINT chk_txn_amount    CHECK (amount > 0 AND amount <= 100000),
    CONSTRAINT chk_txn_type      CHECK (txn_type IN ('P2P','P2M')),
    CONSTRAINT chk_txn_status    CHECK (status IN ('SUCCESS','FAILED','PENDING')),
    CONSTRAINT chk_txn_not_self  CHECK (payer_vpa <> payee_vpa),
    CONSTRAINT fk_txn_payer      FOREIGN KEY (payer_vpa) REFERENCES vpa (vpa_id),
    CONSTRAINT fk_txn_payee      FOREIGN KEY (payee_vpa) REFERENCES vpa (vpa_id),
    CONSTRAINT fk_txn_device     FOREIGN KEY (device_id) REFERENCES device (device_id),
    INDEX idx_txn_payer_time (payer_vpa, txn_time),
    INDEX idx_txn_payee_time (payee_vpa, txn_time)
) ENGINE = InnoDB AUTO_INCREMENT = 900000001;

-- ---------------------------------------------------------------------
-- 9. FRAUD_RULE  and  FRAUD_ALERT (M:N between FRAUD_RULE and UPI_TXN)
-- ---------------------------------------------------------------------
CREATE TABLE fraud_rule (
    rule_id           INT            NOT NULL,
    rule_code         VARCHAR(25)    NOT NULL,
    rule_name         VARCHAR(100)   NOT NULL,
    description       VARCHAR(255)   NULL,
    threshold_count   INT            NULL,
    window_minutes    INT            NULL,
    threshold_amount  DECIMAL(12,2)  NULL,
    severity          VARCHAR(8)     NOT NULL,
    is_active         BOOLEAN        NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_fraud_rule     PRIMARY KEY (rule_id),
    CONSTRAINT uq_rule_code      UNIQUE (rule_code),
    CONSTRAINT chk_rule_count    CHECK (threshold_count IS NULL OR threshold_count > 0),
    CONSTRAINT chk_rule_window   CHECK (window_minutes IS NULL OR window_minutes > 0),
    CONSTRAINT chk_rule_amount   CHECK (threshold_amount IS NULL OR threshold_amount > 0),
    CONSTRAINT chk_rule_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL'))
) ENGINE = InnoDB;

CREATE TABLE fraud_alert (
    alert_id      INT           NOT NULL AUTO_INCREMENT,
    txn_id        BIGINT        NOT NULL,
    rule_id       INT           NOT NULL,
    alert_time    DATETIME      NOT NULL,
    status        VARCHAR(16)   NOT NULL DEFAULT 'OPEN',
    analyst_note  VARCHAR(255)  NULL,
    CONSTRAINT pk_fraud_alert    PRIMARY KEY (alert_id),
    CONSTRAINT uq_alert_txn_rule UNIQUE (txn_id, rule_id),
    CONSTRAINT chk_alert_status  CHECK (status IN ('OPEN','INVESTIGATING','CONFIRMED_FRAUD','FALSE_POSITIVE')),
    CONSTRAINT fk_alert_txn      FOREIGN KEY (txn_id) REFERENCES upi_txn (txn_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_alert_rule     FOREIGN KEY (rule_id) REFERENCES fraud_rule (rule_id)
        ON DELETE RESTRICT
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 10. DISPUTE  (WEAK entity: identified by owner txn_id + dispute_no)
-- ---------------------------------------------------------------------
CREATE TABLE dispute (
    txn_id       BIGINT            NOT NULL,
    dispute_no   TINYINT UNSIGNED  NOT NULL DEFAULT 1,   -- partial key, set by trigger
    raised_by    INT               NOT NULL,
    reason       VARCHAR(20)       NOT NULL,
    description  VARCHAR(255)      NULL,
    status       VARCHAR(12)       NOT NULL DEFAULT 'OPEN',
    raised_on    DATETIME          NOT NULL,
    resolved_on  DATETIME          NULL,
    CONSTRAINT pk_dispute          PRIMARY KEY (txn_id, dispute_no),
    CONSTRAINT chk_dispute_no      CHECK (dispute_no BETWEEN 1 AND 5),
    CONSTRAINT chk_dispute_reason  CHECK (reason IN ('NOT_RECEIVED','WRONG_AMOUNT','UNAUTHORIZED','DUPLICATE','MERCHANT_ISSUE')),
    CONSTRAINT chk_dispute_status  CHECK (status IN ('OPEN','UNDER_REVIEW','RESOLVED','REJECTED')),
    CONSTRAINT chk_dispute_dates   CHECK (resolved_on IS NULL OR resolved_on >= raised_on),
    CONSTRAINT fk_dispute_txn      FOREIGN KEY (txn_id) REFERENCES upi_txn (txn_id)
        ON DELETE CASCADE,          -- identifying relationship
    CONSTRAINT fk_dispute_customer FOREIGN KEY (raised_by) REFERENCES customer (customer_id)
        ON DELETE RESTRICT
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 11. SAVED_PAYEE  (M:N between CUSTOMER and VPA)
-- ---------------------------------------------------------------------
CREATE TABLE saved_payee (
    customer_id  INT          NOT NULL,
    payee_vpa    VARCHAR(50)  NOT NULL,
    nickname     VARCHAR(50)  NOT NULL,
    added_on     DATE         NOT NULL,
    CONSTRAINT pk_saved_payee      PRIMARY KEY (customer_id, payee_vpa),
    CONSTRAINT fk_payee_customer   FOREIGN KEY (customer_id) REFERENCES customer (customer_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_payee_vpa        FOREIGN KEY (payee_vpa) REFERENCES vpa (vpa_id)
        ON DELETE CASCADE           -- demo: DELETE with cascade (account -> vpa -> saved_payee)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 12. SETTLEMENT  (daily merchant payout, written by sp_settle_merchants)
-- ---------------------------------------------------------------------
CREATE TABLE settlement (
    settlement_id  INT            NOT NULL AUTO_INCREMENT,
    merchant_id    INT            NOT NULL,
    settle_date    DATE           NOT NULL,
    txn_count      INT            NOT NULL,
    gross_amount   DECIMAL(14,2)  NOT NULL,
    mdr_fee        DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    net_amount     DECIMAL(14,2)  NOT NULL,
    status         VARCHAR(8)     NOT NULL DEFAULT 'SETTLED',
    settled_at     DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement        PRIMARY KEY (settlement_id),
    CONSTRAINT uq_settlement_day    UNIQUE (merchant_id, settle_date),
    CONSTRAINT chk_settle_count     CHECK (txn_count >= 0),
    CONSTRAINT chk_settle_gross     CHECK (gross_amount >= 0),
    CONSTRAINT chk_settle_fee       CHECK (mdr_fee >= 0),
    CONSTRAINT chk_settle_net       CHECK (net_amount = gross_amount - mdr_fee),
    CONSTRAINT chk_settle_status    CHECK (status IN ('SETTLED','ON_HOLD')),
    CONSTRAINT fk_settlement_merchant FOREIGN KEY (merchant_id) REFERENCES merchant (merchant_id)
        ON DELETE RESTRICT
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 13. AUDIT_LOG  (audit trail, filled only by triggers)
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    log_id      BIGINT        NOT NULL AUTO_INCREMENT,
    table_name  VARCHAR(30)   NOT NULL,
    operation   VARCHAR(6)    NOT NULL,
    record_id   VARCHAR(50)   NOT NULL,
    old_value   TEXT          NULL,
    new_value   TEXT          NULL,
    changed_by  VARCHAR(100)  NOT NULL,
    changed_at  DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT pk_audit_log     PRIMARY KEY (log_id),
    CONSTRAINT chk_audit_op     CHECK (operation IN ('INSERT','UPDATE','DELETE'))
) ENGINE = InnoDB;

-- Quick check
SHOW TABLES;
