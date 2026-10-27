# UPIShield - Data Dictionary

Generated from `information_schema` (run `python docs/generate_diagrams.py` to refresh).

Key: **PK** primary key, **FK** foreign key, **U** unique, NN = NOT NULL.

## audit_log

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| log_id | bigint | yes | PK | auto_increment |  |
| table_name | varchar(30) | yes |  |  |  |
| operation | varchar(6) | yes |  |  |  |
| record_id | varchar(50) | yes |  |  |  |
| old_value | text |  |  |  |  |
| new_value | text |  |  |  |  |
| changed_by | varchar(100) | yes |  |  |  |
| changed_at | datetime(3) | yes |  | CURRENT_TIMESTAMP(3) DEFAULT_GENERATED |  |

CHECK constraints:

- `chk_audit_op`: `(`operation` in (_latin1\'INSERT\',_latin1\'UPDATE\',_latin1\'DELETE\'))`

## bank

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| bank_code | char(4) | yes | PK |  |  |
| bank_name | varchar(100) | yes | U |  |  |
| bank_type | varchar(12) | yes |  |  |  |
| hq_city | varchar(50) | yes |  |  |  |
| established_year | smallint | yes |  |  |  |

CHECK constraints:

- `chk_bank_type`: `(`bank_type` in (_latin1\'PUBLIC\',_latin1\'PRIVATE\',_latin1\'PAYMENTS\',_latin1\'COOPERATIVE\'))`
- `chk_bank_year`: `(`established_year` between 1800 and 2026)`

## bank_account

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| account_id | int | yes | PK | auto_increment |  |
| customer_id | int | yes | FK |  | customer(customer_id) - CASCADE / RESTRICT |
| ifsc | char(11) | yes | FK |  | branch(ifsc) - CASCADE / RESTRICT |
| account_no_enc | varbinary(64) | yes | U |  |  |
| account_no_last4 | char(4) | yes |  |  |  |
| account_type | varchar(10) | yes |  |  |  |
| balance | decimal(14,2) | yes |  | 0.00 |  |
| status | varchar(10) | yes |  | ACTIVE |  |
| opened_on | date | yes |  |  |  |

CHECK constraints:

- `chk_acc_balance`: `(`balance` >= 0)`
- `chk_acc_last4`: `regexp_like(`account_no_last4`,_latin1\'^[0-9]{4}$\')`
- `chk_acc_status`: `(`status` in (_latin1\'ACTIVE\',_latin1\'FROZEN\',_latin1\'CLOSED\'))`
- `chk_acc_type`: `(`account_type` in (_latin1\'SAVINGS\',_latin1\'CURRENT\'))`

## branch

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| ifsc | char(11) | yes | PK |  |  |
| bank_code | char(4) | yes | FK |  | bank(bank_code) - CASCADE / RESTRICT |
| branch_name | varchar(100) | yes |  |  |  |
| city | varchar(50) | yes |  |  |  |
| state | varchar(50) | yes |  |  |  |

CHECK constraints:

- `chk_ifsc_format`: `regexp_like(`ifsc`,_latin1\'^[A-Z]{4}0[A-Z0-9]{6}$\',_latin1\'c\')`

## current_account

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| account_id | int | yes | PK FK |  | bank_account(account_id) - NO ACTION / CASCADE |
| business_name | varchar(100) | yes |  |  |  |
| gstin | char(15) |  | U |  |  |

CHECK constraints:

- `chk_gstin_format`: `((`gstin` is null) or regexp_like(`gstin`,_latin1\'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$\',_latin1\'c\'))`

## customer

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| customer_id | int | yes | PK | auto_increment |  |
| full_name | varchar(100) | yes |  |  |  |
| phone | char(10) | yes | U |  |  |
| email | varchar(100) |  | U |  |  |
| dob | date | yes |  |  |  |
| city | varchar(50) | yes |  |  |  |
| kyc_status | varchar(10) | yes |  | PENDING |  |
| referred_by | int |  | FK |  | customer(customer_id) - NO ACTION / SET NULL |
| created_at | datetime | yes |  | CURRENT_TIMESTAMP DEFAULT_GENERATED |  |

CHECK constraints:

- `chk_email_format`: `((`email` is null) or (`email` like _latin1\'%_@_%._%\'))`
- `chk_kyc_status`: `(`kyc_status` in (_latin1\'PENDING\',_latin1\'VERIFIED\',_latin1\'REJECTED\'))`
- `chk_phone_format`: `regexp_like(`phone`,_latin1\'^[6-9][0-9]{9}$\')`

## device

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| device_id | varchar(20) | yes | PK |  |  |
| model | varchar(50) | yes |  |  |  |
| os | varchar(7) | yes |  |  |  |
| os_version | varchar(10) |  |  |  |  |
| first_seen | datetime | yes |  |  |  |

CHECK constraints:

- `chk_device_os`: `(`os` in (_latin1\'ANDROID\',_latin1\'IOS\'))`

## device_login

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| customer_id | int | yes | PK FK |  | customer(customer_id) - NO ACTION / RESTRICT |
| device_id | varchar(20) | yes | PK FK |  | device(device_id) - NO ACTION / RESTRICT |
| login_time | datetime | yes | PK |  |  |
| ip_address | varchar(45) | yes |  |  |  |

## dispute

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| txn_id | bigint | yes | PK FK |  | upi_txn(txn_id) - NO ACTION / CASCADE |
| dispute_no | tinyint unsigned | yes | PK | 1 |  |
| raised_by | int | yes | FK |  | customer(customer_id) - NO ACTION / RESTRICT |
| reason | varchar(20) | yes |  |  |  |
| description | varchar(255) |  |  |  |  |
| status | varchar(12) | yes |  | OPEN |  |
| raised_on | datetime | yes |  |  |  |
| resolved_on | datetime |  |  |  |  |

CHECK constraints:

- `chk_dispute_dates`: `((`resolved_on` is null) or (`resolved_on` >= `raised_on`))`
- `chk_dispute_no`: `(`dispute_no` between 1 and 5)`
- `chk_dispute_reason`: `(`reason` in (_latin1\'NOT_RECEIVED\',_latin1\'WRONG_AMOUNT\',_latin1\'UNAUTHORIZED\',_latin1\'DUPLICATE\',_latin1\'MERCHANT_ISSUE\'))`
- `chk_dispute_status`: `(`status` in (_latin1\'OPEN\',_latin1\'UNDER_REVIEW\',_latin1\'RESOLVED\',_latin1\'REJECTED\'))`

## enterprise_merchant

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| merchant_id | int | yes | PK FK |  | merchant(merchant_id) - NO ACTION / CASCADE |
| mdr_rate | decimal(4,2) | yes |  | 0.30 |  |
| settlement_cycle | varchar(4) | yes |  | T+1 |  |
| gst_registered | tinyint(1) | yes |  | 1 |  |

CHECK constraints:

- `chk_ent_cycle`: `(`settlement_cycle` in (_latin1\'T+0\',_latin1\'T+1\',_latin1\'T+2\'))`
- `chk_ent_mdr`: `(`mdr_rate` between 0 and 3)`

## fraud_alert

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| alert_id | int | yes | PK | auto_increment |  |
| txn_id | bigint | yes | FK U |  | upi_txn(txn_id) - NO ACTION / CASCADE |
| rule_id | int | yes | FK U |  | fraud_rule(rule_id) - NO ACTION / RESTRICT |
| alert_time | datetime | yes |  |  |  |
| status | varchar(16) | yes |  | OPEN |  |
| analyst_note | varchar(255) |  |  |  |  |

CHECK constraints:

- `chk_alert_status`: `(`status` in (_latin1\'OPEN\',_latin1\'INVESTIGATING\',_latin1\'CONFIRMED_FRAUD\',_latin1\'FALSE_POSITIVE\'))`

## fraud_rule

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| rule_id | int | yes | PK |  |  |
| rule_code | varchar(25) | yes | U |  |  |
| rule_name | varchar(100) | yes |  |  |  |
| description | varchar(255) |  |  |  |  |
| threshold_count | int |  |  |  |  |
| window_minutes | int |  |  |  |  |
| threshold_amount | decimal(12,2) |  |  |  |  |
| severity | varchar(8) | yes |  |  |  |
| is_active | tinyint(1) | yes |  | 1 |  |

CHECK constraints:

- `chk_rule_amount`: `((`threshold_amount` is null) or (`threshold_amount` > 0))`
- `chk_rule_count`: `((`threshold_count` is null) or (`threshold_count` > 0))`
- `chk_rule_severity`: `(`severity` in (_latin1\'LOW\',_latin1\'MEDIUM\',_latin1\'HIGH\',_latin1\'CRITICAL\'))`
- `chk_rule_window`: `((`window_minutes` is null) or (`window_minutes` > 0))`

## merchant

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| merchant_id | int | yes | PK | auto_increment |  |
| merchant_name | varchar(100) | yes |  |  |  |
| vpa_id | varchar(50) | yes | FK U |  | vpa(vpa_id) - CASCADE / RESTRICT |
| mcc | char(4) | yes | FK |  | merchant_category(mcc) - RESTRICT / RESTRICT |
| city | varchar(50) | yes |  |  |  |
| merchant_type | varchar(10) | yes |  |  |  |
| onboarded_on | date | yes |  |  |  |

CHECK constraints:

- `chk_merchant_type`: `(`merchant_type` in (_latin1\'SMALL\',_latin1\'ENTERPRISE\'))`

## merchant_category

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| mcc | char(4) | yes | PK |  |  |
| description | varchar(100) | yes | U |  |  |
| risk_level | varchar(6) | yes |  |  |  |

CHECK constraints:

- `chk_mcc_format`: `regexp_like(`mcc`,_latin1\'^[0-9]{4}$\')`
- `chk_mcc_risk`: `(`risk_level` in (_latin1\'LOW\',_latin1\'MEDIUM\',_latin1\'HIGH\'))`

## mv_city_fraud_stats

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| city | varchar(50) | yes | PK |  |  |
| total_txns | int | yes |  |  |  |
| flagged_txns | int | yes |  |  |  |
| confirmed_fraud | int | yes |  |  |  |
| fraud_rate_pct | decimal(6,3) | yes |  |  |  |
| refreshed_at | datetime | yes |  |  |  |

## mv_daily_merchant_volume

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| txn_date | date | yes | PK |  |  |
| merchant_id | int | yes | PK |  |  |
| merchant_name | varchar(100) | yes |  |  |  |
| txn_count | int | yes |  |  |  |
| gross_amount | decimal(14,2) | yes |  |  |  |
| refreshed_at | datetime | yes |  |  |  |

## saved_payee

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| customer_id | int | yes | PK FK |  | customer(customer_id) - NO ACTION / CASCADE |
| payee_vpa | varchar(50) | yes | PK FK |  | vpa(vpa_id) - NO ACTION / CASCADE |
| nickname | varchar(50) | yes |  |  |  |
| added_on | date | yes |  |  |  |

## savings_account

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| account_id | int | yes | PK FK |  | bank_account(account_id) - NO ACTION / CASCADE |
| interest_rate | decimal(4,2) | yes |  | 3.00 |  |
| min_balance | decimal(10,2) | yes |  | 1000.00 |  |

CHECK constraints:

- `chk_sav_interest`: `(`interest_rate` between 0 and 10)`
- `chk_sav_min_balance`: `(`min_balance` >= 0)`

## security_level

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| level_no | tinyint | yes | PK |  |  |
| level_name | varchar(15) | yes | U |  |  |
| role_name | varchar(30) | yes |  |  |  |
| objects | varchar(255) | yes |  |  |  |

CHECK constraints:

- `chk_level_no`: `(`level_no` between 1 and 4)`

## settlement

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| settlement_id | int | yes | PK | auto_increment |  |
| merchant_id | int | yes | FK U |  | merchant(merchant_id) - NO ACTION / RESTRICT |
| settle_date | date | yes | U |  |  |
| txn_count | int | yes |  |  |  |
| gross_amount | decimal(14,2) | yes |  |  |  |
| mdr_fee | decimal(12,2) | yes |  | 0.00 |  |
| net_amount | decimal(14,2) | yes |  |  |  |
| status | varchar(8) | yes |  | SETTLED |  |
| settled_at | datetime | yes |  | CURRENT_TIMESTAMP DEFAULT_GENERATED |  |

CHECK constraints:

- `chk_settle_count`: `(`txn_count` >= 0)`
- `chk_settle_fee`: `(`mdr_fee` >= 0)`
- `chk_settle_gross`: `(`gross_amount` >= 0)`
- `chk_settle_net`: `(`net_amount` = (`gross_amount` - `mdr_fee`))`
- `chk_settle_status`: `(`status` in (_latin1\'SETTLED\',_latin1\'ON_HOLD\'))`

## small_merchant

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| merchant_id | int | yes | PK FK |  | merchant(merchant_id) - NO ACTION / CASCADE |
| daily_collection_limit | decimal(12,2) | yes |  | 200000.00 |  |
| static_qr | tinyint(1) | yes |  | 1 |  |

CHECK constraints:

- `chk_small_limit`: `(`daily_collection_limit` > 0)`

## upi_txn

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| txn_id | bigint | yes | PK | auto_increment |  |
| payer_vpa | varchar(50) | yes | FK |  | vpa(vpa_id) - NO ACTION / NO ACTION |
| payee_vpa | varchar(50) | yes | FK |  | vpa(vpa_id) - NO ACTION / NO ACTION |
| amount | decimal(12,2) | yes |  |  |  |
| txn_type | varchar(3) | yes |  | P2P |  |
| status | varchar(7) | yes |  | PENDING |  |
| device_id | varchar(20) |  | FK |  | device(device_id) - NO ACTION / NO ACTION |
| remarks | varchar(100) |  |  |  |  |
| failure_reason | varchar(255) |  |  |  |  |
| txn_time | datetime | yes |  | CURRENT_TIMESTAMP DEFAULT_GENERATED |  |

CHECK constraints:

- `chk_txn_amount`: `((`amount` > 0) and (`amount` <= 100000))`
- `chk_txn_not_self`: `(`payer_vpa` <> `payee_vpa`)`
- `chk_txn_status`: `(`status` in (_latin1\'SUCCESS\',_latin1\'FAILED\',_latin1\'PENDING\'))`
- `chk_txn_type`: `(`txn_type` in (_latin1\'P2P\',_latin1\'P2M\'))`

## vpa

| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |
|---|---|---|---|---|---|
| vpa_id | varchar(50) | yes | PK |  |  |
| account_id | int | yes | FK |  | bank_account(account_id) - NO ACTION / CASCADE |
| is_primary | tinyint(1) | yes |  | 1 |  |
| created_on | date | yes |  |  |  |

CHECK constraints:

- `chk_vpa_format`: `regexp_like(`vpa_id`,_latin1\'^[a-z0-9._-]{3,}@[a-z]{2,}$\',_latin1\'c\')`
