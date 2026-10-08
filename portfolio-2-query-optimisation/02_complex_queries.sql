-- ============================================================================
-- MIT 8103: ADVANCED DATABASE SYSTEMS - CONTINUOUS ASSESSMENT
-- PORTFOLIO 2: QUERY PROCESSING AND OPTIMISATION
-- SCRIPT 02: ADVANCED BUSINESS & ANALYTICAL SQL QUERIES
-- ============================================================================

SET search_path TO novapay_core, public;

-- ============================================================================
-- QUERY 1: CUSTOMER MONTHLY ACCOUNT STATEMENT WITH RUNNING BALANCE
-- Technique: Window functions (SUM() OVER, LAG(), ROW_NUMBER()), CTEs
-- Business Goal: Generate an accurate chronological bank statement with
-- running ledger balances and interval delta for a target account.
-- ============================================================================

EXPLAIN (ANALYZE, BUFFERS, COSTS)
WITH target_account AS (
    SELECT account_id, account_number, currency_code
    FROM accounts
    LIMIT 1
),
account_tx_stream AS (
    SELECT 
        t.transaction_id,
        t.reference_no,
        t.initiated_at,
        t.narration,
        t.transaction_type,
        CASE 
            WHEN t.source_account_id = ta.account_id THEN -(t.amount + t.fee_amount)
            ELSE t.amount
        END AS net_flow,
        t.fee_amount
    FROM transactions t
    CROSS JOIN target_account ta
    WHERE (t.source_account_id = ta.account_id OR t.destination_account_id = ta.account_id)
      AND t.status = 'SETTLED'
      AND t.initiated_at >= CURRENT_TIMESTAMP - INTERVAL '90 days'
)
SELECT 
    initiated_at,
    reference_no,
    transaction_type,
    narration,
    net_flow,
    -- Compute progressive running balance over time partition
    SUM(net_flow) OVER (ORDER BY initiated_at ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_net_position,
    -- Compute elapsed seconds between successive transactions
    EXTRACT(EPOCH FROM (initiated_at - LAG(initiated_at) OVER (ORDER BY initiated_at ASC))) AS seconds_since_prev_tx
FROM account_tx_stream
ORDER BY initiated_at DESC
LIMIT 50;



-- QUERY 2: MERCHANT SETTLEMENT VOLUME, COMMISSION YIELD & TIER RANKING
-- Technique: Multi-table JOINs, GROUP BY, Aggregate Filtering, DENSE_RANK()
-- Business Goal: Financial audit of top-performing merchants, calculating
-- total gross transaction value, net settlement payable, and fee commissions.
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT 
    m.merchant_id,
    m.business_name,
    m.merchant_category_code,
    COUNT(t.transaction_id) AS total_settled_transactions,
    ROUND(SUM(t.amount), 2) AS gross_transaction_volume,
    ROUND(SUM(t.amount * m.commission_rate), 2) AS total_novapay_commission,
    ROUND(SUM(t.amount * (1.0 - m.commission_rate)), 2) AS net_merchant_settlement,
    DENSE_RANK() OVER (ORDER BY SUM(t.amount) DESC) AS volume_rank
FROM merchants m
INNER JOIN transactions t ON t.merchant_id = m.merchant_id
INNER JOIN accounts a ON m.settlement_account_id = a.account_id
WHERE t.status = 'SETTLED'
  AND t.initiated_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY m.merchant_id, m.business_name, m.merchant_category_code, a.account_number
HAVING SUM(t.amount) > 50000.00
ORDER BY gross_transaction_volume DESC
LIMIT 20;



-- QUERY 3: FRAUD & ANOMALY VELOCITY DETECTION (AML COMPLIANCE ENGINE)
-- Technique: Self-JOINs, Sliding Time Windows, Conditional Aggregations
-- Business Goal: Identify customer accounts executing 3 or more high-value
-- outbound transfers within any 10-minute sliding window (burst velocity).


EXPLAIN (ANALYZE, BUFFERS, COSTS)
WITH suspicious_bursts AS (
    SELECT 
        t1.source_account_id,
        t1.transaction_id AS primary_tx_id,
        t1.initiated_at AS window_start,
        COUNT(t2.transaction_id) AS burst_count,
        SUM(t2.amount) AS total_burst_value
    FROM transactions t1
    INNER JOIN transactions t2 
        ON t1.source_account_id = t2.source_account_id
       AND t2.initiated_at BETWEEN t1.initiated_at AND (t1.initiated_at + INTERVAL '10 minutes')
       AND t2.status = 'SETTLED'
    WHERE t1.status = 'SETTLED'
      AND t1.amount >= 20000.0000
      AND t1.initiated_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    GROUP BY t1.source_account_id, t1.transaction_id, t1.initiated_at
    HAVING COUNT(t2.transaction_id) >= 3
)
SELECT 
    c.first_name || ' ' || c.last_name AS customer_name,
    c.national_identity_no,
    a.account_number,
    sb.burst_count,
    sb.total_burst_value,
    sb.window_start,
    'HIGH_RISK_VELOCITY_ALERT' AS alert_classification
FROM suspicious_bursts sb
INNER JOIN accounts a ON sb.source_account_id = a.account_id
INNER JOIN customers c ON a.customer_id = c.customer_id
ORDER BY sb.total_burst_value DESC
LIMIT 25;



-- QUERY 4: GENERAL LEDGER INTEGRITY & RECONCILIATION AUDIT
-- Technique: Correlated Subqueries, Full Outer Aggregation Comparison
-- Business Goal: Verify that the cached `available_balance` on the accounts
-- table matches the exact net sum of double-entry debits and credits.


EXPLAIN (ANALYZE, BUFFERS, COSTS)
WITH ledger_aggregates AS (
    SELECT 
        account_id,
        SUM(CASE WHEN entry_type = 'CREDIT' THEN amount ELSE -amount END) AS calculated_net_balance
    FROM ledger_entries
    GROUP BY account_id
)
SELECT 
    a.account_id,
    a.account_number,
    a.available_balance AS cached_account_balance,
    COALESCE(la.calculated_net_balance, 0.0000) AS audited_ledger_balance,
    ABS(a.available_balance - COALESCE(la.calculated_net_balance, 0.0000)) AS discrepancy_amount,
    CASE 
        WHEN ABS(a.available_balance - COALESCE(la.calculated_net_balance, 0.0000)) < 0.0001 
        THEN 'RECONCILED_BALANCED'
        ELSE 'AUDIT_DISCREPANCY_DETECTED'
    END AS reconciliation_status
FROM accounts a
LEFT JOIN ledger_aggregates la ON a.account_id = la.account_id
WHERE a.status = 'ACTIVE'
LIMIT 50;
