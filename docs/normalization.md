# UPIShield – Normalization (Guideline Point 4)

## 0. Starting point: the un-normalized "UPI alert report" export

A bank's operations team typically works from one flat spreadsheet that mixes transaction, customer, bank, merchant, device and fraud-alert data:

```
UPI_REPORT(txn_id, txn_time, amount, status, payer_vpa, account_id, customer_id,
           customer_name, phone, city, ifsc, bank_code, bank_name, payee_vpa,
           merchant_id, merchant_name, mcc, mcc_description, risk_level,
           device_id, device_model, alert_rules)
```

Sample rows:

| txn_id | amount | payer_vpa | customer_name | bank_name | payee_vpa | merchant_name | mcc_description | device_model | alert_rules |
|---|---|---|---|---|---|---|---|---|---|
| 900000101 | 650 | aarav.mehta@axl | Aarav Mehta | ICICI Bank | cafemochapoint@okaxis | Cafe Mocha Point | Restaurants | iPhone 15 | – |
| 900002553 | 3857 | riya.jain@ybl | Riya Jain | HDFC Bank | kunal.rao@ibl | – | – | Redmi Note 13 | VELOCITY |
| 900002746 | 57485 | sai.shah@oksbi | Sai Shah | SBI | om.gupta@paytm | – | – | Vivo T3 | NIGHT_HIGH_VALUE, NEW_DEVICE, HIGH_VALUE_NEW_PAYEE |

**Anomalies in this design**

- **Update anomaly:** a bank renames itself → the change must be repeated in every row of every customer of that bank.
- **Insertion anomaly:** a new merchant cannot be recorded until it receives its first payment; a new fraud rule cannot be stored until it fires.
- **Deletion anomaly:** deleting the only transaction of a customer also deletes that customer's name, phone and bank.
- **Redundancy:** customer, bank and merchant details repeat in thousands of rows.

## 1. Functional dependencies

| # | Functional dependency | Meaning |
|---|---|---|
| F1 | txn_id → txn_time, amount, status, payer_vpa, payee_vpa, device_id | a transaction is identified by its id |
| F2 | payer_vpa → account_id  (in general: vpa_id → account_id) | a UPI ID is linked to one account |
| F3 | account_id → customer_id, ifsc | an account has one owner and one home branch |
| F4 | customer_id → customer_name, phone, city | customer details |
| F5 | phone → customer_id | a phone number is registered once (candidate key) |
| F6 | ifsc → bank_code | an IFSC belongs to one bank |
| F7 | bank_code → bank_name | bank details |
| F8 | merchant_id → merchant_name, mcc, payee_vpa | merchant details |
| F9 | payee_vpa → merchant_id  (for merchant VPAs) | a merchant collects on one VPA |
| F10 | mcc → mcc_description, risk_level | category details |
| F11 | device_id → device_model | device details |
| F12 | rule_code → rule_name, severity | fraud rule details |
| F13 | txn_id, rule_code → alert_time, alert_status | one alert per rule per transaction |

### Closures and keys (Armstrong's axioms)

Using **reflexivity**, **augmentation** and **transitivity** (and the derived union / decomposition rules):

- txn_id → payer_vpa (F1), payer_vpa → account_id (F2) ⇒ **txn_id → account_id** (transitivity)
- txn_id → account_id, account_id → customer_id (F3) ⇒ **txn_id → customer_id** (transitivity)
- customer_id → phone (F4, decomposition) and phone → customer_id (F5) ⇒ customer_id and phone are **equivalent** (both candidate keys of CUSTOMER)

**{txn_id}⁺** = {txn_id, txn_time, amount, status, payer_vpa, payee_vpa, device_id, account_id, customer_id, customer_name, phone, city, ifsc, bank_code, bank_name, merchant_id, merchant_name, mcc, mcc_description, risk_level, device_model}

{txn_id}⁺ does **not** contain rule_code, alert_time or alert_status, so txn_id alone is not a key once the multi-valued alert column is flattened (step 2).

**{txn_id, rule_code}⁺** = all attributes ⇒ **(txn_id, rule_code)** is the candidate key of the 1NF relation.

### Minimal (canonical) cover

1. **Single attribute on the right:** split every FD, e.g. F1 becomes txn_id → txn_time, txn_id → amount, … (six FDs).
2. **No extraneous attribute on the left:** only F13 has two attributes. {txn_id}⁺ does not contain alert_status and {rule_code}⁺ does not contain it either, so neither attribute is extraneous – F13 stays.
3. **No redundant FD:** an FD such as txn_id → account_id (if it had been listed) is removed because it is implied by F1 + F2. After this check, F1–F13 (split form) is the minimal cover.

## 2. First Normal Form (1NF)

**Rule:** every attribute holds a single atomic value.

`alert_rules` is multi-valued ("NIGHT_HIGH_VALUE, NEW_DEVICE, …"). It is replaced by one row per (transaction, rule) and the rule attributes are added:

```
UPI_REPORT_1NF(txn_id, rule_code, txn_time, amount, status, payer_vpa, account_id,
               customer_id, customer_name, phone, city, ifsc, bank_code, bank_name,
               payee_vpa, merchant_id, merchant_name, mcc, mcc_description, risk_level,
               device_id, device_model, rule_name, severity, alert_time, alert_status)
Key: (txn_id, rule_code)        -- transactions without alerts use rule_code = 'NONE'
```

## 3. Second Normal Form (2NF)

**Rule:** 1NF and no non-key attribute depends on only *part* of a composite key.

Partial dependencies on (txn_id, rule_code):

- txn_id → txn_time, amount, … (F1 and everything derived from it)
- rule_code → rule_name, severity (F12)

Decomposition:

```
TXN_REPORT(txn_id, txn_time, amount, status, payer_vpa, account_id, customer_id,
           customer_name, phone, city, ifsc, bank_code, bank_name, payee_vpa,
           merchant_id, merchant_name, mcc, mcc_description, risk_level,
           device_id, device_model)                                  Key: txn_id
FRAUD_RULE(rule_code, rule_name, severity)                           Key: rule_code
FRAUD_ALERT(txn_id, rule_code, alert_time, alert_status)             Key: (txn_id, rule_code)
```

Every relation is now in 2NF (the two new ones have no partial dependencies, TXN_REPORT has a single-attribute key).

## 4. Third Normal Form (3NF)

**Rule:** 2NF and no non-key attribute depends transitively on the key (for every X → A, X is a superkey or A is a prime attribute).

Transitive chains inside TXN_REPORT:

- txn_id → payer_vpa → account_id → customer_id → customer_name, phone, city
- txn_id → payer_vpa → account_id → ifsc → bank_code → bank_name
- txn_id → payee_vpa → merchant_id → merchant_name, mcc → mcc_description, risk_level
- txn_id → device_id → device_model

Each determinant becomes its own relation:

```
UPI_TXN(txn_id, txn_time, amount, status, payer_vpa, payee_vpa, device_id)
VPA(vpa_id, account_id)
BANK_ACCOUNT(account_id, customer_id, ifsc)
CUSTOMER(customer_id, customer_name, phone, city)
BRANCH(ifsc, bank_code)
BANK(bank_code, bank_name)
MERCHANT(merchant_id, merchant_name, vpa_id, mcc)
MERCHANT_CATEGORY(mcc, mcc_description, risk_level)
DEVICE(device_id, device_model)
FRAUD_RULE(rule_code, rule_name, severity)
FRAUD_ALERT(txn_id, rule_code, alert_time, alert_status)
```

## 5. Final set of decomposed relations

These match the implemented tables in `sql/01_create_schema.sql` (the implementation adds the remaining attributes from the ER model and the tables that never existed in the report: SAVINGS_ACCOUNT, CURRENT_ACCOUNT, SMALL_MERCHANT, ENTERPRISE_MERCHANT, DEVICE_LOGIN, SAVED_PAYEE, DISPUTE, SETTLEMENT, AUDIT_LOG).

| Relation | Key | Normal form |
|---|---|---|
| UPI_TXN | txn_id | BCNF |
| VPA | vpa_id | BCNF |
| BANK_ACCOUNT | account_id | BCNF |
| CUSTOMER | customer_id (phone is also a candidate key) | BCNF |
| BRANCH | ifsc | BCNF |
| BANK | bank_code | BCNF |
| MERCHANT | merchant_id (vpa_id is also a candidate key) | BCNF |
| MERCHANT_CATEGORY | mcc | BCNF |
| DEVICE | device_id | BCNF |
| FRAUD_RULE | rule_code / rule_id | BCNF |
| FRAUD_ALERT | (txn_id, rule_code) | BCNF |
| DISPUTE (weak) | (txn_id, dispute_no) | BCNF |

## 6. Verification

- **Lossless join:** every split was made on a common attribute that is a key of one of the two resulting relations (e.g. TXN_REPORT ⋈ CUSTOMER on customer_id, which is the key of CUSTOMER). By the lossless-join test (R1 ∩ R2 → R1 or R1 ∩ R2 → R2) every step is lossless.
- **Dependency preserving:** each FD F1–F13 is fully contained in one final relation, so all can be checked without joins.
- **BCNF check (beyond 3NF):** in every final relation, the left side of every non-trivial FD is a superkey. The only FDs whose left side is not the primary key are phone → customer_id and vpa_id → merchant_id, and phone and vpa_id are declared UNIQUE (candidate keys), so these are BCNF as well.

**Discussion point for the viva – `txn_type`:** UPI_TXN also stores txn_type (P2P/P2M), which is derived from the payee VPA. It is kept on purpose as the type *at the time of payment* (a VPA could become a merchant later) and is filled automatically by the trigger `trg_txn_bi`, so it can never become inconsistent.
