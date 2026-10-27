-- =====================================================================
--  UPIShield - File 00 : Rebuild the whole database from scratch
--  Use with the mysql command-line client, run FROM THE PROJECT ROOT:
--      mysql --local-infile=1 -u root -p < sql/00_rebuild.sql
--  (MySQL Workbench does not support SOURCE: open and run files 01-07 in
--   order instead.)
-- =====================================================================
SOURCE sql/01_create_schema.sql;
SOURCE sql/02_functions_procedures.sql;
SOURCE sql/03_triggers.sql;
SOURCE sql/04_seed_data.sql;
SOURCE sql/05_load_paysim.sql;
SOURCE sql/06_views.sql;
SOURCE sql/07_security_roles.sql;
SELECT 'UPIShield rebuilt successfully' AS status;
