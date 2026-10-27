-- =====================================================================
--  UPIShield - Concurrency demo : SESSION B   (see session_A.sql)
-- =====================================================================
USE upishield;
SET @acc := 50001;

-- ---------------------------------------------------------------------
-- PART 1 : LOST UPDATE
-- ---------------------------------------------------------------------
-- STEP 2 (B)  reads the SAME old balance as A
START TRANSACTION;
SELECT balance INTO @bal_b FROM bank_account WHERE account_id = @acc;
SELECT @bal_b AS balance_seen_by_B;

-- STEP 3 -> back to session A

-- STEP 4 (B)  overwrites A's update with a value computed from stale data
UPDATE bank_account SET balance = @bal_b - 1000 WHERE account_id = @acc;
COMMIT;

-- STEP 5 -> back to session A

-- ---------------------------------------------------------------------
-- PART 2 : WITH LOCKING
-- ---------------------------------------------------------------------
-- STEP 7 (B)  this statement BLOCKS until session A commits
START TRANSACTION;
SELECT balance INTO @bal_b FROM bank_account WHERE account_id = @acc FOR UPDATE;
SELECT @bal_b AS balance_seen_by_B;     -- already includes A's debit

-- STEP 8 -> back to session A (commit there), then return here

-- STEP 9 (B)
UPDATE bank_account SET balance = @bal_b - 1000 WHERE account_id = @acc;
COMMIT;

-- STEP 10 -> back to session A
