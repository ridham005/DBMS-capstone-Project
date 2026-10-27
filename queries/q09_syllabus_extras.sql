-- =====================================================================
--  UPIShield - Q09 : Syllabus extras
--    Unit 3 : indexing (B+ tree), multi-key index, hashing
--    Unit 4 : query cost (EXPLAIN), isolation levels, encryption,
--             statistical databases (inference control)
-- =====================================================================
USE upishield;

-- =====================================================================
-- 1. INDEXING AND QUERY COST  (InnoDB indexes are B+ trees)
-- =====================================================================
-- 1a. Without an index on amount -> full table scan (type = ALL)
EXPLAIN SELECT txn_id, amount FROM upi_txn WHERE amount BETWEEN 40000 AND 60000;
EXPLAIN ANALYZE SELECT txn_id, amount FROM upi_txn WHERE amount BETWEEN 40000 AND 60000;

-- 1b. Create a single-column B+ tree index -> range scan (type = range)
CREATE INDEX idx_txn_amount ON upi_txn (amount);
EXPLAIN SELECT txn_id, amount FROM upi_txn WHERE amount BETWEEN 40000 AND 60000;
EXPLAIN ANALYZE SELECT txn_id, amount FROM upi_txn WHERE amount BETWEEN 40000 AND 60000;

-- 1c. Multi-key (composite) index: useful when the query filters on the
--     LEFT-MOST column(s) of the index
CREATE INDEX idx_txn_status_time ON upi_txn (status, txn_time);
EXPLAIN SELECT COUNT(*) FROM upi_txn
WHERE  status = 'FAILED' AND txn_time >= '2026-10-01';          -- uses the index
EXPLAIN SELECT COUNT(*) FROM upi_txn
WHERE  txn_time >= '2026-10-01';                                 -- cannot use it (no status)

-- 1d. Cost of a join: the optimizer's plan as a tree
EXPLAIN FORMAT = TREE
SELECT c.city, SUM(t.amount)
FROM   upi_txn t
JOIN   vpa v          ON v.vpa_id = t.payer_vpa
JOIN   bank_account a ON a.account_id = v.account_id
JOIN   customer c     ON c.customer_id = a.customer_id
WHERE  t.status = 'SUCCESS'
GROUP BY c.city;

SHOW INDEX FROM upi_txn;

-- =====================================================================
-- 2. HASHING : a MEMORY table with a HASH index (direct-access file)
--    Equality look-ups go straight to the bucket; range queries cannot use it.
--    (InnoDB ignores USING HASH, so the MEMORY engine is used here.)
-- =====================================================================
DROP TABLE IF EXISTS vpa_lookup_cache;
CREATE TABLE vpa_lookup_cache (
    vpa_id      VARCHAR(50) NOT NULL,
    account_id  INT         NOT NULL,
    PRIMARY KEY (vpa_id) USING HASH
) ENGINE = MEMORY;
INSERT INTO vpa_lookup_cache SELECT vpa_id, account_id FROM vpa;

SHOW INDEX FROM vpa_lookup_cache;                                  -- Index_type = HASH
SET @some_vpa := (SELECT vpa_id FROM vpa WHERE account_id = 50001 AND is_primary);
EXPLAIN SELECT account_id FROM vpa_lookup_cache WHERE vpa_id = @some_vpa;   -- direct (hash) look-up
EXPLAIN SELECT account_id FROM vpa_lookup_cache WHERE vpa_id LIKE 'a%';     -- range: full scan

-- =====================================================================
-- 3. DATA ENCRYPTION
-- =====================================================================
-- 3a. Account numbers are stored with AES encryption
SELECT account_id, HEX(account_no_enc) AS stored_value, account_no_last4
FROM   bank_account LIMIT 3;

-- 3b. Decryption needs the key (EXECUTE on fn_enc_key is granted to auditors only)
SELECT account_id, CAST(AES_DECRYPT(account_no_enc, fn_enc_key()) AS CHAR) AS account_no
FROM   bank_account LIMIT 3;

-- 3c. One-way hashing (for passwords / API keys): cannot be reversed
SELECT SHA2('MyUpiPin#1234', 256) AS sha256_hash;

-- =====================================================================
-- 4. STATISTICAL DATABASE : inference control
--    The public role sees only v_public_city_stats.  Cities with fewer
--    than 5 customers are hidden, otherwise an average over a group of
--    1-2 people would reveal an individual's data.
-- =====================================================================
SELECT c.city, COUNT(DISTINCT c.customer_id) AS customers
FROM   customer c GROUP BY c.city ORDER BY customers;          -- (admin view)
SELECT * FROM v_public_city_stats ORDER BY customers;            -- (public view)

-- =====================================================================
-- 5. TRANSACTION ISOLATION LEVELS (concurrency control)
--    See queries/concurrency/ for the two-session lost-update demo.
-- =====================================================================
SELECT @@transaction_isolation AS default_level;                -- REPEATABLE-READ
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT @@transaction_isolation AS now_level;
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT @@transaction_isolation AS now_level;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- current locks held by open transactions (useful during the concurrency demo)
SELECT ENGINE_TRANSACTION_ID, OBJECT_NAME, LOCK_TYPE, LOCK_MODE, LOCK_STATUS, LOCK_DATA
FROM   performance_schema.data_locks;

-- =====================================================================
-- 6. THREE-LEVEL ARCHITECTURE in this project
--    Physical  : InnoDB files, B+ tree indexes, the MEMORY hash table
--    Conceptual: the 20 base tables in sql/01_create_schema.sql
--    External  : role-specific views (v_support_customer,
--                v_fraud_analyst_alerts, v_auditor_trail, v_public_city_stats)
--    Data independence: adding idx_txn_amount above changed the physical
--    level without changing any query or view.
-- =====================================================================
SELECT TABLE_NAME, TABLE_TYPE, ENGINE, TABLE_ROWS
FROM   information_schema.TABLES
WHERE  TABLE_SCHEMA = 'upishield'
ORDER BY TABLE_TYPE, TABLE_NAME;

-- Clean-up so this file can be run again
DROP INDEX idx_txn_amount ON upi_txn;
DROP INDEX idx_txn_status_time ON upi_txn;
DROP TABLE vpa_lookup_cache;
