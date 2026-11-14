-- ============================================================================
-- MIT 8103: ADVANCED DATABASE SYSTEMS - CONTINUOUS ASSESSMENT
-- PORTFOLIO 2: QUERY PROCESSING AND OPTIMISATION
-- SCRIPT 01: REALISTIC DATA POPULATION SCRIPT (SYNTHETIC DATA GENERATOR)
-- Target Scale: ~5,000 Customers, ~10,000 Accounts, ~200 Merchants, ~150,000 Transactions
-- ============================================================================

SET search_path TO novapay_core, public;

-- Disable triggers and foreign key checks during bulk load for high-speed ingestion
SET session_replication_role = 'replica';

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. SEED CUSTOMERS (5,000 Rows)
-- ----------------------------------------------------------------------------
INSERT INTO customers (
    customer_id,
    national_identity_no,
    first_name,
    last_name,
    email,
    phone_number,
    residential_address,
    postal_code,
    city,
    country_code,
    date_of_birth,
    kyc_tier,
    is_active,
    created_at
)
SELECT 
    gen_random_uuid(),
    'NIN' || lpad(i::text, 11, '0'),
    (ARRAY['Chinedu', 'Amina', 'Babajide', 'Ngozi', 'Olumide', 'Fatima', 'Emeka', 'Zainab', 'Kelechi', 'Tariq', 'Funke', 'Ibrahim'])[1 + (i % 12)],
    (ARRAY['Adeyemi', 'Okonkwo', 'Bello', 'Eze', 'Danjuma', 'Okafor', 'Balogun', 'Garba', 'Nwosu', 'Abubakar', 'Soyinka', 'Suleiman'])[1 + ((i / 12) % 12)],
    'user.' || i || '.' || substr(md5(random()::text), 1, 6) || '@novapay-demo.com',
    '+23480' || lpad((10000000 + i)::text, 8, '0'),
    (i % 999 + 1) || ' Financial Boulevard, Victoria Island',
    lpad((100000 + (i % 89999))::text, 6, '0'),
    (ARRAY['Lagos', 'Abuja', 'Port Harcourt', 'Kano', 'Ibadan', 'Enugu', 'Kaduna', 'Benin City'])[1 + (i % 8)],
    'NG',
    (CURRENT_DATE - INTERVAL '20 years' - (i % 10000 || ' days')::INTERVAL)::DATE,
    (ARRAY['TIER_1_BASIC'::kyc_tier_level, 'TIER_2_VERIFIED'::kyc_tier_level, 'TIER_3_ENHANCED'::kyc_tier_level])[1 + (i % 3)],
    (i % 50 <> 0), -- 98% active
    CURRENT_TIMESTAMP - (INTERVAL '1 day' * (i % 730))
FROM generate_series(1, 5000) AS i;

-- ----------------------------------------------------------------------------
-- 2. SEED ACCOUNTS (10,000 Rows: 2 Accounts Per Customer on Average)
-- ----------------------------------------------------------------------------
INSERT INTO accounts (
    account_id,
    customer_id,
    account_number,
    currency_code,
    account_type,
    status,
    available_balance,
    ledger_balance,
    daily_transfer_limit,
    created_at
)
SELECT 
    gen_random_uuid(),
    c.customer_id,
    lpad((1000000000 + row_number() OVER())::text, 10, '0'),
    CASE WHEN (row_number() OVER()) % 10 = 0 THEN 'USD' ELSE 'NGN' END,
    CASE WHEN (row_number() OVER()) % 4 = 0 THEN 'CHECKING'::account_class_type ELSE 'SAVINGS'::account_class_type END,
    'ACTIVE'::account_status_type,
    round((random() * 2500000 + 5000)::numeric, 4),
    round((random() * 2500000 + 5000)::numeric, 4),
    CASE WHEN c.kyc_tier = 'TIER_3_ENHANCED' THEN 5000000.0000 ELSE 500000.0000 END,
    c.created_at + INTERVAL '1 hour'
FROM customers c
CROSS JOIN generate_series(1, 2) AS acc_num;

-- ----------------------------------------------------------------------------
-- 3. SEED MERCHANTS (200 Rows)
-- ----------------------------------------------------------------------------
INSERT INTO merchants (
    merchant_id,
    business_name,
    registration_rc_number,
    merchant_category_code,
    settlement_account_id,
    contact_email,
    commission_rate,
    is_verified,
    created_at
)
SELECT 
    gen_random_uuid(),
    'Enterprise Merchant ' || i || ' Ltd',
    'RC' || lpad(i::text, 8, '0'),
    (ARRAY['5411', '5812', '5311', '4814', '7011', '5912'])[1 + (i % 6)], -- Grocery, Restaurant, Department, Telecom, Hotel, Pharmacy
    a.account_id,
    'support@merchant' || i || '.org',
    (ARRAY[0.0100, 0.0150, 0.0200, 0.0250])[1 + (i % 4)],
    TRUE,
    CURRENT_TIMESTAMP - (INTERVAL '1 day' * (i % 365))
FROM generate_series(1, 200) AS i
JOIN LATERAL (
    SELECT account_id FROM accounts ORDER BY account_id LIMIT 1 OFFSET (i * 5)
) a ON TRUE;

-- ----------------------------------------------------------------------------
-- 4. SEED TRANSACTIONS (150,000 Rows across past 12 months)
-- ----------------------------------------------------------------------------
WITH sample_accounts AS (
    SELECT account_id, row_number() OVER () AS rnum FROM accounts LIMIT 2000
),
sample_merchants AS (
    SELECT merchant_id, row_number() OVER () AS rnum FROM merchants LIMIT 100
)
INSERT INTO transactions (
    transaction_id,
    reference_no,
    external_provider_ref,
    source_account_id,
    destination_account_id,
    merchant_id,
    amount,
    fee_amount,
    currency_code,
    transaction_type,
    status,
    narration,
    ip_address,
    initiated_at,
    settled_at
)
SELECT 
    gen_random_uuid(),
    'TXN-' || to_char(CURRENT_TIMESTAMP - (INTERVAL '1 minute' * (i * 3)), 'YYYYMMDD') || '-' || lpad(i::text, 8, '0'),
    'EXT-' || md5(i::text),
    src.account_id,
    dst.account_id,
    CASE WHEN i % 3 = 0 THEN m.merchant_id ELSE NULL END,
    round((random() * 95000 + 500)::numeric, 4),
    round((random() * 150 + 10)::numeric, 4),
    'NGN',
    (ARRAY['P2P_TRANSFER'::transaction_type_enum, 'MERCHANT_PAYMENT'::transaction_type_enum, 'BILL_PAYMENT'::transaction_type_enum])[1 + (i % 3)],
    CASE 
        WHEN i % 50 = 0 THEN 'PENDING'::transaction_status_enum
        WHEN i % 70 = 0 THEN 'FAILED'::transaction_status_enum
        ELSE 'SETTLED'::transaction_status_enum 
    END,
    'Payment transfer transaction item #' || i,
    ('192.168.' || (i % 250) || '.' || ((i * 7) % 250))::inet,
    CURRENT_TIMESTAMP - (INTERVAL '2 minutes' * i),
    CURRENT_TIMESTAMP - (INTERVAL '2 minutes' * i) + INTERVAL '2 seconds'
FROM generate_series(1, 150000) AS i
JOIN sample_accounts src ON src.rnum = (1 + (i % 1000))
JOIN sample_accounts dst ON dst.rnum = (1001 + (i % 999))
LEFT JOIN sample_merchants m ON m.rnum = (1 + (i % 100));

-- ----------------------------------------------------------------------------
-- 5. SEED BALANCED LEDGER ENTRIES (Double-Entry: 300,000 Rows)
-- ----------------------------------------------------------------------------
-- Debit leg from Source Account
INSERT INTO ledger_entries (
    entry_id,
    transaction_id,
    account_id,
    entry_type,
    amount,
    running_balance_after,
    entry_timestamp
)
SELECT 
    gen_random_uuid(),
    t.transaction_id,
    t.source_account_id,
    'DEBIT'::ledger_entry_type,
    (t.amount + t.fee_amount),
    round(1000000.0000 - (t.amount + t.fee_amount), 4),
    t.initiated_at
FROM transactions t
WHERE t.status = 'SETTLED';

-- Credit leg to Destination Account
INSERT INTO ledger_entries (
    entry_id,
    transaction_id,
    account_id,
    entry_type,
    amount,
    running_balance_after,
    entry_timestamp
)
SELECT 
    gen_random_uuid(),
    t.transaction_id,
    t.destination_account_id,
    'CREDIT'::ledger_entry_type,
    t.amount,
    round(500000.0000 + t.amount, 4),
    t.settled_at
FROM transactions t
WHERE t.status = 'SETTLED';

COMMIT;

-- Re-enable normal constraints and triggers
SET session_replication_role = 'origin';

-- Update optimizer table statistics for precise cost estimations
ANALYZE customers;
ANALYZE accounts;
ANALYZE merchants;
ANALYZE transactions;
ANALYZE ledger_entries;
