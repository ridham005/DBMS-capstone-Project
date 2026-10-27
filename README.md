# UPIShield – A Database System for UPI Payments and Fraud Monitoring

DBMS course project (24CS202T) · MySQL 8.0.31+ · Python/Tkinter front end (bonus)

UPIShield models the UPI payment ecosystem – customers, banks, accounts, UPI IDs (VPAs), merchants and devices – and adds a rule-based fraud-monitoring layer: triggers check every payment against fraud rules, raise alerts, enforce the Rs. 1,00,000 daily limit, and keep an audit trail.

## Folder structure

```
UPIShield/
├── README.md
├── rebuild.bat / rebuild.sh        one-click rebuild of the whole database
├── sql/                            build scripts – run in this order
│   ├── 00_rebuild.sql              runs 01–07 (mysql command line)
│   ├── 01_create_schema.sql        20 tables + all integrity constraints        (5a)
│   ├── 02_functions_procedures.sql 6 functions, 5 procedures                     (5c-viii)
│   ├── 03_triggers.sql             12 triggers (validation, fraud rules, audit)  (5c-viii)
│   ├── 04_seed_data.sql            ~8,900 rows of data                           (5b)
│   ├── 05_load_paysim.sql          LOAD DATA INFILE from CSV (optional)          (5b)
│   ├── 06_views.sql                views + materialized views + refresh event    (5c-vii)
│   └── 07_security_roles.sql       roles, users, security levels                 (5c-iii)
├── queries/                        demonstration queries – one file per guideline item
│   ├── q01_ddl.sql                 CREATE, ALTER, RENAME, TRUNCATE, DROP         (5c-i)
│   ├── q02_dml.sql                 INSERT, UPDATE / DELETE with & without cascade (5c-ii)
│   ├── q03_dcl.sql                 GRANT, REVOKE                                 (5c-iii)
│   ├── q04_tcl.sql                 COMMIT, SAVEPOINT, ROLLBACK                   (5c-iv)
│   ├── q05_dql.sql                 SELECT items 1–8 (all joins, set ops, ANY/ALL)(5c-v)
│   ├── q06_subqueries.sql          scalar, IN, correlated, EXISTS, derived, CTE  (5c-vi)
│   ├── q07_views_mv.sql            views, CHECK OPTION, materialized views      (5c-vii)
│   ├── q08_procs_funcs_triggers.sql procedures, functions, triggers in action    (5c-viii)
│   ├── q09_syllabus_extras.sql     indexing, hashing, EXPLAIN, encryption, isolation
│   └── concurrency/session_A.sql, session_B.sql   two-window lost-update demo
├── frontend/                       Python + Tkinter GUI (bonus)
│   ├── app.py  db.py  query_catalog.py  requirements.txt
├── data/
│   ├── generate_data.py            generator used to create 04_seed_data.sql
│   └── paysim_sample.csv           CSV in PaySim format for LOAD DATA
└── docs/
    ├── erd.png / erd.svg / erd.dot           ER diagram (Chen notation)          (point 2)
    ├── schema_diagram.png / .svg / .dot      relational schema diagram           (point 3)
    ├── data_dictionary.md                    tables, domains, keys, constraints  (point 3)
    ├── normalization.md                      FDs, closures, minimal cover, 1NF→3NF, BCNF (point 4)
    ├── theory_notes.md                       relational algebra, 3-level architecture,
    │                                         serializability, security, indexing
    ├── generate_diagrams.py                  regenerates the diagrams + dictionary
    ├── screenshots/                          front-end screenshots
    └── UPIShield_Project_Proposal.docx
```

## Quick start

### Option A – MySQL Workbench (Windows / macOS)

1. Check the version: `SELECT VERSION();` must be **8.0.31 or later** (needed for INTERSECT / EXCEPT).
2. Open and execute (lightning icon) the files in `sql/` **in order: 01 → 02 → 03 → 04 → 06 → 07**.
3. *Optional* `05_load_paysim.sql`: edit the connection → **Advanced → Others**: add `OPT_LOCAL_INFILE=1`, reconnect, and put the **full path** of `data/paysim_sample.csv` in the `LOAD DATA` line.
4. Open any file in `queries/` and run it statement by statement (Ctrl+Enter) to take screenshots.

> Workbench stops a script at the first error. Statements marked `-- [EXPECTED ERROR]` fail **on purpose** (they prove a constraint works). Run them one at a time, or enable *Edit → Preferences → SQL Editor → Continue on SQL script error*.

### Option B – command line (one command)

From the project folder:

```
mysql --local-infile=1 -u root -p < sql/00_rebuild.sql
```

or double-click `rebuild.bat` (Windows) / run `./rebuild.sh`. To run a demo file and keep going past the expected errors:

```
mysql --force -u root -p < queries/q05_dql.sql
```

The rebuild resets everything, so you can re-run it any time the demos have changed the data.

## Front end (bonus)

```
pip install -r frontend/requirements.txt
python frontend/app.py
```

Log in with your MySQL user, or with the application account created by `07_security_roles.sql`:
user `upishield_app`, password `UpiApp@2026`.

Tabs: **Dashboard**, **Customers** (register, search, update KYC), **Accounts** (`sp_open_account`), **Payments** (`sp_transfer`, statement via `sp_customer_statement`), **Fraud & Disputes** (review alerts, `sp_raise_dispute`), **Reports** (views, materialized views, settlement, audit trail), **SQL Console** (predefined queries for every DQL category, or any SQL).

Try in the Payments tab: pay Rs. 60,000 from one customer's UPI ID to a VPA they have never paid – the trigger raises a CRITICAL fraud alert that immediately appears in the Fraud tab.

## Demo accounts (created by 07_security_roles.sql)

| User | Password | Role / clearance |
|---|---|---|
| public_dash | Public@2026 | upi_public – level 1 PUBLIC |
| support_riya | Support@2026 | upi_support – level 2 INTERNAL |
| analyst_karan | Analyst@2026 | upi_analyst – level 3 CONFIDENTIAL |
| auditor_meera | Auditor@2026 | upi_auditor – level 4 SECRET |
| upishield_app | UpiApp@2026 | upi_app – front end |

## Guideline coverage

| Guideline point | Where |
|---|---|
| 1. Project statement | `docs/UPIShield_Project_Proposal.docx`, presentation |
| 2. ERD (entities, keys, cardinality, participation, specialization) | `docs/erd.png` |
| 3. Relational model + schema diagram + constraints | `docs/schema_diagram.png`, `docs/data_dictionary.md`, `sql/01_create_schema.sql` |
| 4. Normalization up to 3NF (and BCNF) | `docs/normalization.md` |
| 5a. Tables with integrity constraints | `sql/01_create_schema.sql` |
| 5b. Data (hundreds of rows) + forms | `sql/04_seed_data.sql`, `sql/05_load_paysim.sql`, front end |
| 5c-i … 5c-viii | `queries/q01` … `queries/q08` |
| Syllabus extras (indexing, hashing, query cost, concurrency, security, statistical DB) | `queries/q09_syllabus_extras.sql`, `queries/concurrency/`, `docs/theory_notes.md` |

## Notes

- **Data:** the seed data is synthetic but realistic (Indian banks, IFSC/GSTIN/UPI formats) and respects every business rule, so it loads with all triggers active. Fraud patterns are injected deliberately so the fraud triggers have something to catch. `paysim_sample.csv` uses the column format of the public PaySim dataset; a sample of the real PaySim file can be dropped in instead.
- **Encryption key:** `fn_enc_key()` returns a fixed demo key. In a real system the key would be stored outside the database.
- **MySQL limitations handled:** no materialized views (table + refresh procedure + event), no FULL OUTER JOIN (LEFT ⋃ RIGHT), CHECK cannot use sub-queries or `CURDATE()` (triggers with `SIGNAL`), no native mandatory access control (security levels + views + roles).

## Troubleshooting

| Problem | Fix |
|---|---|
| `INTERSECT` / `EXCEPT` syntax error | upgrade to MySQL 8.0.31+ |
| `Loading local data is disabled` | client: `--local-infile=1` (Workbench: `OPT_LOCAL_INFILE=1`); server: `SET GLOBAL local_infile = 1;` |
| Event does not run | `SET GLOBAL event_scheduler = ON;` |
| `You do not have the SUPER privilege and binary logging is enabled` while creating functions | `SET GLOBAL log_bin_trust_function_creators = 1;` then re-run file 02 |
| Front end: `No module named mysql` | `pip install mysql-connector-python` |
| Front end: `No module named tkinter` (Linux) | `sudo apt install python3-tk` |
