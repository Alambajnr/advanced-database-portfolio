-- ============================================================================
-- MIT 8103: ADVANCED DATABASE SYSTEMS - CONTINUOUS ASSESSMENT
-- PORTFOLIO 1: DATABASE DESIGN AND MODELLING
-- CASE STUDY: NovaPay Financial Technologies (Digital Banking & Payments Core)
-- RDBMS Engine: PostgreSQL 15+ / 16
-- ============================================================================

-- Drop schema if exists for clean, reproducible environment setup
DROP SCHEMA IF EXISTS novapay_core CASCADE;
CREATE SCHEMA novapay_core;
SET search_path TO novapay_core, public;

-- Enable UUID extension for cryptographically secure, globally unique identifiers
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. ENUMERATED TYPES (Domain Integrity Constraints)

CREATE TYPE kyc_tier_level AS ENUM ('TIER_1_BASIC', 'TIER_2_VERIFIED', 'TIER_3_ENHANCED');
CREATE TYPE account_status_type AS ENUM ('ACTIVE', 'FROZEN', 'DORMANT', 'CLOSED');
CREATE TYPE account_class_type AS ENUM ('SAVINGS', 'CHECKING', 'MERCHANT_SETTLEMENT', 'SYSTEM_RESERVE');
CREATE TYPE transaction_type_enum AS ENUM ('P2P_TRANSFER', 'MERCHANT_PAYMENT', 'BILL_PAYMENT', 'CASH_DEPOSIT', 'WITHDRAWAL', 'REVERSAL');
CREATE TYPE transaction_status_enum AS ENUM ('PENDING', 'PROCESSING', 'SETTLED', 'FAILED', 'REVERSED');
CREATE TYPE ledger_entry_type AS ENUM ('DEBIT', 'CREDIT');

-- 2. CORE RELATIONAL TABLES

-- ----------------------------------------------------------------------------
-- Table: customers
-- Description: Stores retail customer identity and KYC compliance attributes
-- ----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    national_identity_no VARCHAR(20) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    residential_address TEXT NOT NULL,
    postal_code VARCHAR(10) NOT NULL,
    city VARCHAR(50) NOT NULL,
    country_code CHAR(2) NOT NULL DEFAULT 'NG',
    date_of_birth DATE NOT NULL,
    kyc_tier kyc_tier_level NOT NULL DEFAULT 'TIER_1_BASIC',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Table Constraints
    CONSTRAINT uq_customers_nin UNIQUE (national_identity_no),
    CONSTRAINT uq_customers_email UNIQUE (email),
    CONSTRAINT uq_customers_phone UNIQUE (phone_number),
    CONSTRAINT chk_customer_age CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years')
);

-- ----------------------------------------------------------------------------
-- Table: accounts
-- Description: Financial depository ledger accounts holding customer balances
-- ----------------------------------------------------------------------------
CREATE TABLE accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL,
    account_number CHAR(10) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'NGN',
    account_type account_class_type NOT NULL DEFAULT 'SAVINGS',
    status account_status_type NOT NULL DEFAULT 'ACTIVE',
    available_balance NUMERIC(16, 4) NOT NULL DEFAULT 0.0000,
    ledger_balance NUMERIC(16, 4) NOT NULL DEFAULT 0.0000,
    daily_transfer_limit NUMERIC(16, 4) NOT NULL DEFAULT 500000.0000,
    version_no BIGINT NOT NULL DEFAULT 1, -- Optimistic concurrency control marker
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Table Constraints
    CONSTRAINT uq_accounts_account_no UNIQUE (account_number),
    CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_positive_balance CHECK (available_balance >= 0.0000),
    CONSTRAINT chk_positive_ledger CHECK (ledger_balance >= 0.0000),
    CONSTRAINT chk_valid_currency CHECK (currency_code IN ('NGN', 'USD', 'GBP', 'EUR', 'KES'))
);

-- ----------------------------------------------------------------------------
-- Table: merchants
-- Description: Registered commercial entities accepting digital payments
-- ----------------------------------------------------------------------------
CREATE TABLE merchants (
    merchant_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_name VARCHAR(120) NOT NULL,
    registration_rc_number VARCHAR(30) NOT NULL,
    merchant_category_code CHAR(4) NOT NULL, -- ISO 18245 MCC
    settlement_account_id UUID NOT NULL,
    contact_email VARCHAR(100) NOT NULL,
    commission_rate NUMERIC(5, 4) NOT NULL DEFAULT 0.0150, -- 1.5% fee
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Table Constraints
    CONSTRAINT uq_merchants_rc UNIQUE (registration_rc_number),
    CONSTRAINT fk_merchants_settlement_account FOREIGN KEY (settlement_account_id)
        REFERENCES accounts(account_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_commission_rate CHECK (commission_rate >= 0.0000 AND commission_rate <= 0.2000)
);

-- ----------------------------------------------------------------------------
-- Table: transactions
-- Description: Primary financial transfer instructions across accounts
-- ----------------------------------------------------------------------------
CREATE TABLE transactions (
    transaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reference_no VARCHAR(36) NOT NULL,
    external_provider_ref VARCHAR(100),
    source_account_id UUID NOT NULL,
    destination_account_id UUID NOT NULL,
    merchant_id UUID,
    amount NUMERIC(16, 4) NOT NULL,
    fee_amount NUMERIC(16, 4) NOT NULL DEFAULT 0.0000,
    currency_code CHAR(3) NOT NULL DEFAULT 'NGN',
    transaction_type transaction_type_enum NOT NULL,
    status transaction_status_enum NOT NULL DEFAULT 'PENDING',
    narration VARCHAR(255) NOT NULL,
    ip_address INET,
    initiated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    settled_at TIMESTAMPTZ,

    -- Table Constraints
    CONSTRAINT uq_transactions_ref UNIQUE (reference_no),
    CONSTRAINT fk_tx_source_account FOREIGN KEY (source_account_id)
        REFERENCES accounts(account_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_tx_destination_account FOREIGN KEY (destination_account_id)
        REFERENCES accounts(account_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_tx_merchant FOREIGN KEY (merchant_id)
        REFERENCES merchants(merchant_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_positive_amount CHECK (amount > 0.0000),
    CONSTRAINT chk_positive_fee CHECK (fee_amount >= 0.0000),
    CONSTRAINT chk_distinct_accounts CHECK (source_account_id <> destination_account_id)
);

-- ----------------------------------------------------------------------------
-- Table: ledger_entries
-- Description: Immutable double-entry bookkeeping journal.
-- Every financial transaction MUST yield at least 2 balanced ledger entries:
-- (Debit = Credit)
-- ----------------------------------------------------------------------------
CREATE TABLE ledger_entries (
    entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL,
    account_id UUID NOT NULL,
    entry_type ledger_entry_type NOT NULL,
    amount NUMERIC(16, 4) NOT NULL,
    running_balance_after NUMERIC(16, 4) NOT NULL,
    entry_timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Table Constraints
    CONSTRAINT fk_ledger_transaction FOREIGN KEY (transaction_id)
        REFERENCES transactions(transaction_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ledger_account FOREIGN KEY (account_id)
        REFERENCES accounts(account_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_ledger_positive_amount CHECK (amount > 0.0000)
);

-- ----------------------------------------------------------------------------
-- Table: system_audit_logs
-- Description: Regulatory compliance, forensic audit trails and DDL/DML history
-- ----------------------------------------------------------------------------
CREATE TABLE system_audit_logs (
    audit_id BIGSERIAL PRIMARY KEY,
    entity_name VARCHAR(50) NOT NULL,
    entity_id UUID NOT NULL,
    action_type VARCHAR(20) NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
    performed_by VARCHAR(100) NOT NULL,
    old_state JSONB,
    new_state JSONB,
    client_ip INET,
    log_timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. AUDIT TRIGGER FOR DATA INTEGRITY


CREATE OR REPLACE FUNCTION trg_fn_audit_account_changes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO system_audit_logs (
        entity_name,
        entity_id,
        action_type,
        performed_by,
        old_state,
        new_state
    ) VALUES (
        'accounts',
        COALESCE(NEW.account_id, OLD.account_id),
        TG_OP,
        CURRENT_USER,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_accounts
AFTER INSERT OR UPDATE OR DELETE ON accounts
FOR EACH ROW EXECUTE FUNCTION trg_fn_audit_account_changes();

-- 4. DOUBLE-ENTRY INTEGRITY ASSERTION FUNCTION


CREATE OR REPLACE FUNCTION verify_transaction_double_entry(p_transaction_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_total_debits NUMERIC(16, 4) := 0;
    v_total_credits NUMERIC(16, 4) := 0;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO v_total_debits
    FROM ledger_entries
    WHERE transaction_id = p_transaction_id AND entry_type = 'DEBIT';

    SELECT COALESCE(SUM(amount), 0) INTO v_total_credits
    FROM ledger_entries
    WHERE transaction_id = p_transaction_id AND entry_type = 'CREDIT';

    IF v_total_debits <> v_total_credits THEN
        RAISE EXCEPTION 'Double-entry bookkeeping invariant violated! Debits (%) != Credits (%)',
            v_total_debits, v_total_credits;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
