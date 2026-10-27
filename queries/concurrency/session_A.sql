-- =====================================================================
--  UPIShield - Concurrency demo : SESSION A
--  Open TWO connections (two Workbench tabs or two terminals):
--      Session A -> this file      Session B -> session_B.sql
--  Run the steps in the order of the STEP numbers, switching windows.
--  Scenario: two payments of Rs. 1,000 hit the SAME account at the same time.
-- =====================================================================
USE upishield;
SET @acc := 50001;

-- ---------------------------------------------------------------------
-- PART 1 : LOST UPDATE (no locking)
-- ---------------------------------------------------------------------
-- STEP 1 (A)
START TRANSACTION;
SELECT balance INTO @bal_a FROM bank_account WHERE account_id = @acc;   -- plain read, no lock
SELECT @bal_a AS balance_seen_by_A;

-- STEP 2 -> go to session B and run its STEP 2

-- STEP 3 (A)  write back "what I read minus 1000"
UPDATE bank_account SET balance = @bal_a - 1000 WHERE account_id = @acc;
COMMIT;

-- STEP 4 -> go to session B and run its STEP 4

-- STEP 5 (A)  two debits of 1,000 happened, but the balance only fell by 1,000
SELECT balance AS final_balance FROM bank_account WHERE account_id = @acc;
-- restore the lost money for the next part
UPDATE bank_account SET balance = balance + 1000 WHERE account_id = @acc;

-- ---------------------------------------------------------------------
-- PART 2 : FIXED with SELECT ... FOR UPDATE (exclusive row lock, 2PL)
-- ---------------------------------------------------------------------
-- STEP 6 (A)
START TRANSACTION;
SELECT balance INTO @bal_a FROM bank_account WHERE account_id = @acc FOR UPDATE;   -- X-lock
SELECT @bal_a AS balance_locked_by_A;

-- STEP 7 -> go to session B and run its STEP 7 (it will WAIT)

-- STEP 8 (A)
UPDATE bank_account SET balance = @bal_a - 1000 WHERE account_id = @acc;
COMMIT;                     -- releases the lock; B continues automatically

-- STEP 9 -> go to session B and run its STEP 9

-- STEP 10 (A)  both debits are now reflected (2,000 in total)
SELECT balance AS final_balance FROM bank_account WHERE account_id = @acc;
UPDATE bank_account SET balance = balance + 2000 WHERE account_id = @acc;   -- restore
