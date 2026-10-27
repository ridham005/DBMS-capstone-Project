# UPIShield – Theory Notes (syllabus topics for the report and viva)

## 1. Relational algebra for key queries (Unit 1)

Notation: σ select, π project, ⋈ natural/theta join, ∪ union, ∩ intersection, − difference, γ grouping/aggregation, ρ rename.

| # | Query (file `queries/q05_dql.sql`) | Relational algebra |
|---|---|---|
| 1 | Successful payments ≥ Rs. 50,000 | π txn_id, payer_vpa, amount ( σ status='SUCCESS' ∧ amount≥50000 (UPI_TXN) ) |
| 2 | Merchants in high-risk categories | π merchant_id, merchant_name ( σ risk_level='HIGH' (MERCHANT ⋈ MERCHANT_CATEGORY) ) |
| 3 | P2M payments with merchant name | π txn_id, amount, merchant_name ( UPI_TXN ⋈ payee_vpa = vpa_id MERCHANT ) |
| 4 | Payments per type | txn_type γ COUNT(txn_id), SUM(amount) (UPI_TXN) |
| 5 | Referrals (self join) | π C.full_name, R.full_name ( ρ C(CUSTOMER) ⋈ C.referred_by = R.customer_id ρ R(CUSTOMER) ) |
| 6 | VPAs in disputed payments (UNION) | π payer_vpa (DISPUTE ⋈ UPI_TXN) ∪ π payee_vpa (DISPUTE ⋈ UPI_TXN) |
| 7 | Disputed AND flagged customers (INTERSECT) | π raised_by (DISPUTE) ∩ π customer_id (FRAUD_ALERT ⋈ UPI_TXN ⋈ VPA ⋈ BANK_ACCOUNT) |
| 8 | Saved payees never paid (EXCEPT) | π payee_vpa (SAVED_PAYEE) − π payee_vpa ( σ status='SUCCESS' (UPI_TXN) ) |
| 9 | Customers with no disputes | π customer_id (CUSTOMER) − π raised_by (DISPUTE) |
| 10 | Customers flagged by **every** active rule (division) | π customer_id, rule_id (FRAUD_ALERT ⋈ UPI_TXN ⋈ VPA ⋈ BANK_ACCOUNT) ÷ π rule_id ( σ is_active (FRAUD_RULE) ) |

## 2. Three-level architecture and data independence (Unit 1)

| Level | In UPIShield |
|---|---|
| **External** (user views) | `v_support_customer` (support desk), `v_fraud_analyst_alerts` (analysts), `v_auditor_trail` (auditors), `v_public_city_stats` (public dashboard) |
| **Conceptual** (logical schema) | the 20 base tables in `sql/01_create_schema.sql` with their constraints |
| **Internal** (physical) | InnoDB storage, clustered primary-key B+ trees, secondary indexes, the MEMORY hash table in `q09` |

- **Physical data independence:** adding `idx_txn_amount` in `q09_syllabus_extras.sql` changes the internal level only; no query or view changes.
- **Logical data independence:** the support view hides balances and masks numbers; base tables can gain columns (`ALTER TABLE customer ADD alternate_phone` in `q01`) without changing the view users see.

## 3. Transactions, schedules and serializability (Unit 4)

### ACID in `sp_transfer`

| Property | How it is achieved |
|---|---|
| Atomicity | debit, credit and the transaction row are inside one `START TRANSACTION … COMMIT`; any error → `ROLLBACK` in the exit handler |
| Consistency | CHECK (`balance >= 0`, `amount <= 100000`), FKs, and the daily-limit trigger reject invalid states |
| Isolation | `SELECT … FOR UPDATE` row locks (InnoDB, REPEATABLE READ) |
| Durability | InnoDB redo log: once COMMIT returns, the payment survives a crash |

### Two concurrent payments from account A (balance 10,000)

T1 = pay Rs. 1,000 from A, T2 = pay Rs. 2,000 from A.

**Schedule S1 (non-serializable – lost update):**

| Time | T1 | T2 |
|---|---|---|
| 1 | R(A) = 10,000 | |
| 2 | | R(A) = 10,000 |
| 3 | W(A) = 9,000 | |
| 4 | | W(A) = 8,000 |

Conflicts: R1(A) before W2(A) ⇒ edge T1 → T2; R2(A) before W1(A) ⇒ edge T2 → T1.

Precedence graph: **T1 ⇄ T2 (cycle)** ⇒ S1 is **not conflict-serializable**. Final balance 8,000 instead of 7,000 – T1's update is lost. Reproduce with `queries/concurrency/session_A.sql` / `session_B.sql`, Part 1.

**Schedule S2 (with `FOR UPDATE`, strict two-phase locking):**

| Time | T1 | T2 |
|---|---|---|
| 1 | X-lock(A), R(A) = 10,000 | |
| 2 | | request X-lock(A) → **waits** |
| 3 | W(A) = 9,000, COMMIT (release) | |
| 4 | | X-lock(A), R(A) = 9,000 |
| 5 | | W(A) = 7,000, COMMIT |

Precedence graph: **T1 → T2 only (no cycle)** ⇒ conflict-serializable, equivalent to the serial schedule T1, T2. Final balance 7,000 (correct). This is Part 2 of the concurrency demo.

**Deadlock avoidance:** `sp_transfer` always locks the two accounts in ascending `account_id` order, so two opposite transfers (A→B and B→A) can never wait for each other in a cycle.

## 4. Security (Unit 4)

| Topic | Implementation |
|---|---|
| Discretionary access control | `GRANT` / `REVOKE` on tables, views, columns and functions; role hierarchy `upi_public` ⊂ `upi_support` ⊂ `upi_analyst` ⊂ `upi_auditor` (`sql/07`, `queries/q03`) |
| Mandatory access control / multi-level security (simulated) | `security_level` table: PUBLIC(1) < INTERNAL(2) < CONFIDENTIAL(3) < SECRET(4). Each role is granted only the objects at or below its clearance ("no read-up") |
| Audit trails | `audit_log` filled only by triggers (balance, status, KYC, alert decisions, account deletion) |
| Statistical databases | `v_public_city_stats` returns only aggregates and suppresses groups with fewer than 5 customers (inference control) |
| Data encryption | account numbers stored with `AES_ENCRYPT`; decryption key function executable only by auditors; `SHA2` for one-way hashing |

## 5. File organization and indexing (Unit 3)

- **Indexed (B+ tree):** every InnoDB primary key is a clustered B+ tree; `idx_txn_payer_time` and `idx_txn_payee_time` are secondary B+ tree indexes used by the fraud trigger.
- **Multi-key index:** `idx_txn_status_time (status, txn_time)` – used only when the query filters on the left-most column (`EXPLAIN` in `q09`).
- **Hashing (direct file):** `vpa_lookup_cache` (MEMORY engine, `USING HASH`) – constant-time equality look-ups, but a range/`LIKE` search must scan.
- **Query cost:** `EXPLAIN` / `EXPLAIN ANALYZE` before and after creating an index (type `ALL` → `range`, fewer rows examined).

## 6. NoSQL (introduction)

A document store such as MongoDB could keep each customer's statement as one JSON document (fast reads, flexible schema). UPIShield stays relational because payments need multi-row ACID transactions, foreign keys and joins across customers, accounts and merchants – the strengths of an RDBMS.
