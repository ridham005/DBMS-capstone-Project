-- =====================================================================
--  UPIShield - File 05 : Bulk load from CSV (PaySim format)
--  Guideline: Point 5(b) - populating tables
--
--  data/paysim_sample.csv uses the same columns as the public PaySim
--  mobile-money dataset (Kaggle).  You can replace it with a sample of the
--  real PaySim file - the script works unchanged.
--
--  Requirements
--    * mysql CLI :  mysql --local-infile=1 -u root -p  (run from project root)
--    * Workbench :  Edit connection -> Advanced -> Others:  OPT_LOCAL_INFILE=1
--                   and change the file path below to the FULL path, e.g.
--                   'C:/Users/you/UPIShield/data/paysim_sample.csv'
--    * Server    :  SET GLOBAL local_infile = 1;   (done below, needs admin)
--  This file is optional: every other script works without it.
-- =====================================================================
USE upishield;
SET GLOBAL local_infile = 1;

-- 1. Staging table: raw copy of the CSV (no constraints, mirrors the file)
DROP TABLE IF EXISTS stg_paysim;
CREATE TABLE stg_paysim (
    step            INT,
    type            VARCHAR(10),
    amount          DECIMAL(14,2),
    nameOrig        VARCHAR(20),
    oldbalanceOrg   DECIMAL(14,2),
    newbalanceOrig  DECIMAL(14,2),
    nameDest        VARCHAR(20),
    oldbalanceDest  DECIMAL(14,2),
    newbalanceDest  DECIMAL(14,2),
    isFraud         TINYINT,
    isFlaggedFraud  TINYINT
) ENGINE = InnoDB;

-- 2. Bulk load
LOAD DATA LOCAL INFILE 'C:/Users/Ridham ROG/Downloads/UPIShield/UPIShield/data/paysim_sample.csv'
INTO TABLE stg_paysim
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT type, COUNT(*) AS rows_in_file, ROUND(AVG(amount), 2) AS avg_amount
FROM stg_paysim GROUP BY type;

-- 3. Transform + load into UPI_TXN
--    * only PAYMENT (-> P2M) and TRANSFER (-> P2P) rows are UPI-like
--    * PaySim customers/merchants are mapped onto existing VPAs with CRC32
--    * amounts are scaled down and capped at Rs. 15,000
--    * step = hour offset from 1 Aug 2026
INSERT INTO upi_txn (payer_vpa, payee_vpa, amount, status, remarks, txn_time)
WITH payer_pool AS (
    SELECT v.vpa_id, ROW_NUMBER() OVER (ORDER BY v.vpa_id) - 1 AS rn
    FROM   vpa v
    JOIN   bank_account a ON a.account_id = v.account_id
    WHERE  a.account_type = 'SAVINGS' AND a.status = 'ACTIVE'
      AND  v.is_primary AND a.opened_on < '2026-08-01'
),
merchant_pool AS (
    SELECT m.vpa_id, ROW_NUMBER() OVER (ORDER BY m.merchant_id) - 1 AS rn
    FROM   merchant m
    JOIN   merchant_category mc ON mc.mcc = m.mcc
    WHERE  mc.risk_level <> 'HIGH'
),
sizes AS (
    SELECT (SELECT COUNT(*) FROM payer_pool) AS np,
           (SELECT COUNT(*) FROM merchant_pool) AS nm
)
SELECT p.vpa_id,
       COALESCE(mp.vpa_id, pp.vpa_id),
       LEAST(GREATEST(ROUND(s.amount / 25, 2), 1.00), 15000.00),
       'SUCCESS',
       CONCAT('PaySim ', LOWER(s.type), IF(s.isFraud = 1, ' (labelled fraud)', '')),
       TIMESTAMP('2026-08-01') + INTERVAL s.step HOUR
FROM   stg_paysim s
CROSS JOIN sizes z
JOIN   payer_pool p      ON p.rn  = CRC32(s.nameOrig) % z.np
LEFT JOIN merchant_pool mp ON s.type = 'PAYMENT'  AND mp.rn = CRC32(s.nameDest) % z.nm
LEFT JOIN payer_pool pp    ON s.type = 'TRANSFER' AND pp.rn = CRC32(s.nameDest) % z.np
WHERE  s.type IN ('PAYMENT', 'TRANSFER')
  AND  p.vpa_id <> COALESCE(mp.vpa_id, pp.vpa_id)
ORDER BY s.step;

SELECT ROW_COUNT() AS paysim_rows_inserted;

-- 4. Staging data is no longer needed (TRUNCATE keeps the table for reuse)
TRUNCATE TABLE stg_paysim;

SELECT COUNT(*) AS total_txns,
       SUM(txn_time < '2026-09-01') AS from_paysim
FROM upi_txn;
