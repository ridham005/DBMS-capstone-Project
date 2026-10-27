"""Predefined queries shown in the SQL Console tab (one per guideline item)."""

CATALOG = {
    "1. SELECT with WHERE": [
        ("Payments of Rs. 50,000+ in October",
         "SELECT txn_id, payer_vpa, payee_vpa, amount, txn_time\nFROM upi_txn\n"
         "WHERE status = 'SUCCESS' AND amount >= 50000\n  AND txn_time >= '2026-10-01'"),
        ("Payments rejected by the daily limit",
         "SELECT txn_id, payer_vpa, amount, txn_time, failure_reason\nFROM upi_txn\n"
         "WHERE status = 'FAILED' AND failure_reason LIKE 'Daily UPI limit%'"),
    ],
    "2. Aggregate functions": [
        ("Overall payment statistics",
         "SELECT COUNT(*) AS txns, SUM(amount) AS total, ROUND(AVG(amount),2) AS average,\n"
         "       MIN(amount) AS smallest, MAX(amount) AS largest\nFROM upi_txn WHERE status = 'SUCCESS'"),
    ],
    "3. IN, LIKE, DISTINCT": [
        ("Merchants in high-risk categories (IN)",
         "SELECT merchant_id, merchant_name, mcc FROM merchant\nWHERE mcc IN ('5944', '6051', '7995')"),
        ("VPAs on the SBI handle (LIKE)",
         "SELECT vpa_id FROM vpa WHERE vpa_id LIKE '%@oksbi'"),
        ("UPI handles in use (DISTINCT)",
         "SELECT DISTINCT SUBSTRING_INDEX(vpa_id, '@', -1) AS handle FROM vpa ORDER BY handle"),
    ],
    "4. ORDER BY, LIMIT, OFFSET": [
        ("Ten largest payments",
         "SELECT txn_id, payer_vpa, payee_vpa, amount FROM upi_txn\n"
         "WHERE status = 'SUCCESS' ORDER BY amount DESC LIMIT 10"),
        ("Customer directory, page 3",
         "SELECT customer_id, full_name, city FROM customer\nORDER BY full_name LIMIT 10 OFFSET 20"),
    ],
    "5. GROUP BY / HAVING": [
        ("Payments per type and status",
         "SELECT txn_type, status, COUNT(*) AS txns, SUM(amount) AS value\n"
         "FROM upi_txn GROUP BY txn_type, status"),
        ("Merchants with 40+ payments",
         "SELECT m.merchant_name, COUNT(*) AS payments, SUM(t.amount) AS collected\n"
         "FROM merchant m JOIN upi_txn t ON t.payee_vpa = m.vpa_id\nWHERE t.status = 'SUCCESS'\n"
         "GROUP BY m.merchant_id, m.merchant_name HAVING COUNT(*) > 40 ORDER BY payments DESC"),
    ],
    "6. Joins": [
        ("INNER: payments with merchant category",
         "SELECT t.txn_id, t.amount, m.merchant_name, mc.description\nFROM upi_txn t\n"
         "JOIN merchant m ON m.vpa_id = t.payee_vpa\nJOIN merchant_category mc ON mc.mcc = m.mcc\nLIMIT 50"),
        ("LEFT: customers and their dispute count",
         "SELECT c.customer_id, c.full_name, COUNT(d.txn_id) AS disputes\nFROM customer c\n"
         "LEFT JOIN dispute d ON d.raised_by = c.customer_id\nGROUP BY c.customer_id, c.full_name\n"
         "ORDER BY disputes DESC"),
        ("RIGHT: every category, even without merchants",
         "SELECT mc.mcc, mc.description, COUNT(m.merchant_id) AS merchants\nFROM merchant m\n"
         "RIGHT JOIN merchant_category mc ON mc.mcc = m.mcc\nGROUP BY mc.mcc, mc.description"),
        ("SELF: referrals",
         "SELECT c.full_name AS customer, r.full_name AS referred_by\nFROM customer c\n"
         "JOIN customer r ON r.customer_id = c.referred_by"),
        ("NATURAL: banks and branches",
         "SELECT bank_code, bank_name, ifsc, branch_name FROM bank NATURAL JOIN branch"),
        ("CROSS: bank x account type matrix",
         "SELECT b.bank_name, t.account_type, COUNT(a.account_id) AS accounts\nFROM bank b\n"
         "CROSS JOIN (SELECT 'SAVINGS' AS account_type UNION SELECT 'CURRENT') t\n"
         "LEFT JOIN branch br ON br.bank_code = b.bank_code\n"
         "LEFT JOIN bank_account a ON a.ifsc = br.ifsc AND a.account_type = t.account_type\n"
         "GROUP BY b.bank_name, t.account_type"),
    ],
    "7. Set operations": [
        ("INTERSECT: disputed AND flagged customers",
         "SELECT raised_by AS customer_id FROM dispute\nINTERSECT\n"
         "SELECT a.customer_id FROM fraud_alert fa\nJOIN upi_txn t ON t.txn_id = fa.txn_id\n"
         "JOIN vpa v ON v.vpa_id = t.payer_vpa\nJOIN bank_account a ON a.account_id = v.account_id"),
        ("EXCEPT: saved payees never paid",
         "SELECT payee_vpa FROM saved_payee\nEXCEPT\n"
         "SELECT payee_vpa FROM upi_txn WHERE status = 'SUCCESS'"),
    ],
    "8. ANY / ALL": [
        ("Payments above ALL fraud thresholds",
         "SELECT txn_id, amount FROM upi_txn WHERE status = 'SUCCESS'\n"
         "  AND amount > ALL (SELECT threshold_amount FROM fraud_rule\n"
         "                    WHERE threshold_amount IS NOT NULL AND is_active)"),
    ],
    "Subqueries": [
        ("Correlated: unusually large for that payer",
         "SELECT t.txn_id, t.payer_vpa, t.amount FROM upi_txn t\nWHERE t.status = 'SUCCESS'\n"
         "  AND t.amount > 5 * (SELECT AVG(t2.amount) FROM upi_txn t2\n"
         "                      WHERE t2.payer_vpa = t.payer_vpa AND t2.status = 'SUCCESS')"),
        ("EXISTS: customers with confirmed fraud",
         "SELECT c.customer_id, c.full_name FROM customer c\nWHERE EXISTS (\n"
         "  SELECT 1 FROM bank_account a JOIN vpa v ON v.account_id = a.account_id\n"
         "  JOIN upi_txn t ON t.payer_vpa = v.vpa_id JOIN fraud_alert f ON f.txn_id = t.txn_id\n"
         "  WHERE a.customer_id = c.customer_id AND f.status = 'CONFIRMED_FRAUD')"),
    ],
    "Views and materialized views": [
        ("Merchant performance (view)", "SELECT * FROM v_merchant_performance ORDER BY total_collected DESC"),
        ("City fraud statistics (materialized)", "SELECT * FROM mv_city_fraud_stats ORDER BY fraud_rate_pct DESC"),
        ("Public city statistics (statistical view)", "SELECT * FROM v_public_city_stats"),
    ],
}
