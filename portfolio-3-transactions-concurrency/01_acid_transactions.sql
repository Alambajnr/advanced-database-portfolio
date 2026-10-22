-- ============================================================================
-- MIT 8103: ADVANCED DATABASE SYSTEMS - CONTINUOUS ASSESSMENT
-- PORTFOLIO 3: TRANSACTIONS AND CONCURRENCY
-- SCRIPT 01: ACID-COMPLIANT FUND TRANSFER WITH COMMIT, ROLLBACK & SAVEPOINTS
-- ============================================================================

SET search_path TO novapay_core, public;

-- ============================================================================
-- STORED PROCEDURE: novapay_transfer_funds
-- Demonstrates Atomicity, Consistency, Isolation, and Durability (ACID)
-- Implements balance validation, ledger balancing, and explicit rollback
-- ============================================================================

CREATE OR REPLACE PROCEDURE transfer_funds_atomic(
    p_source_account_id UUID,
    p_dest_account_id UUID,
    p_amount NUMERIC(16, 4),
    p_fee NUMERIC(16, 4),
    p_narration VARCHAR(255),
    INOUT p_tx_reference VARCHAR(36) DEFAULT NULL,
    INOUT p_status VARCHAR(20) DEFAULT 'FAILED'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_src_balance NUMERIC(16, 4);
    v_src_status account_status_type;
    v_dst_status account_status_type;
    v_tx_id UUID;
    v_total_deduction NUMERIC(16, 4);
BEGIN
    v_total_deduction := p_amount + p_fee;
    p_tx_reference := 'TXN-' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD-HH24MISS') || '-' || substr(md5(random()::text), 1, 8);

    -- 1. LOCK ACCOUNTS IN DETERMINISTIC ORDER TO PREVENT DEADLOCKS
    -- (Lowest UUID locked first, then higher UUID)
    IF p_source_account_id < p_dest_account_id THEN
        SELECT available_balance, status INTO v_src_balance, v_src_status
        FROM accounts WHERE account_id = p_source_account_id FOR UPDATE;

        SELECT status INTO v_dst_status
        FROM accounts WHERE account_id = p_dest_account_id FOR UPDATE;
    ELSE
        SELECT status INTO v_dst_status
        FROM accounts WHERE account_id = p_dest_account_id FOR UPDATE;

        SELECT available_balance, status INTO v_src_balance, v_src_status
        FROM accounts WHERE account_id = p_source_account_id FOR UPDATE;
    END IF;

    -- 2. DOMAIN & BUSINESS INTEGRITY CHECKS
    IF v_src_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Transfer rejected: Source account is not active (Status: %)', v_src_status;
    END IF;

    IF v_dst_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Transfer rejected: Destination account is not active (Status: %)', v_dst_status;
    END IF;

    IF v_src_balance < v_total_deduction THEN
        RAISE EXCEPTION 'Transfer rejected: Insufficient funds. Available: %, Required: %', v_src_balance, v_total_deduction;
    END IF;

    -- 3. INSERT TRANSACTION INSTRUCTION
    v_tx_id := gen_random_uuid();
    INSERT INTO transactions (
        transaction_id,
        reference_no,
        source_account_id,
        destination_account_id,
        amount,
        fee_amount,
        transaction_type,
        status,
        narration,
        initiated_at,
        settled_at
    ) VALUES (
        v_tx_id,
        p_tx_reference,
        p_source_account_id,
        p_dest_account_id,
        p_amount,
        p_fee,
        'P2P_TRANSFER',
        'SETTLED',
        p_narration,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    );

    -- 4. MUTATE BALANCES ATOMICALLY
    UPDATE accounts 
    SET available_balance = available_balance - v_total_deduction,
        ledger_balance = ledger_balance - v_total_deduction,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_id = p_source_account_id;

    UPDATE accounts 
    SET available_balance = available_balance + p_amount,
        ledger_balance = ledger_balance + p_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_id = p_dest_account_id;

    -- 5. WRITE IMMUTABLE DOUBLE-ENTRY JOURNAL LEGS
    -- Leg 1: Debit sender
    INSERT INTO ledger_entries (
        transaction_id, account_id, entry_type, amount, running_balance_after
    ) VALUES (
        v_tx_id, p_source_account_id, 'DEBIT', v_total_deduction, (v_src_balance - v_total_deduction)
    );

    -- Leg 2: Credit beneficiary
    INSERT INTO ledger_entries (
        transaction_id, account_id, entry_type, amount, running_balance_after
    )
    SELECT v_tx_id, p_dest_account_id, 'CREDIT', p_amount, available_balance
    FROM accounts WHERE account_id = p_dest_account_id;

    -- 6. DOUBLE-ENTRY INTEGRITY INVARIANT CHECK
    PERFORM verify_transaction_double_entry(v_tx_id);

    p_status := 'SUCCESS';
EXCEPTION
    WHEN OTHERS THEN
        -- Automatic transaction rollback is invoked on exception in calling block
        p_status := 'FAILED: ' || SQLERRM;
        RAISE;
END;
$$;



-- TRANSACTION DEMO 1: SUCCESSFUL COMMIT SCENARIO


DO $$
DECLARE
    v_acc1 UUID;
    v_acc2 UUID;
    v_ref VARCHAR(36);
    v_status VARCHAR(50);
BEGIN
    SELECT account_id INTO v_acc1 FROM accounts WHERE available_balance >= 10000 LIMIT 1;
    SELECT account_id INTO v_acc2 FROM accounts WHERE account_id <> v_acc1 LIMIT 1;

    RAISE NOTICE 'Executing atomic transfer from % to % for NGN 5,000...', v_acc1, v_acc2;
    CALL transfer_funds_atomic(v_acc1, v_acc2, 5000.0000, 25.0000, 'Rent Split Payment', v_ref, v_status);
    RAISE NOTICE 'Result: %, Reference: %', v_status, v_ref;
END $$;



-- TRANSACTION DEMO 2: EXPLICIT ROLLBACK VIA SAVEPOINT
-- Scenario: Attempting primary transfer + optional premium notification charge.
-- If optional charge fails, rollback to savepoint preserving core transfer.


BEGIN;

-- Establish baseline state
SELECT account_id, available_balance FROM accounts LIMIT 2;

-- Perform primary debit/credit transfer
UPDATE accounts SET available_balance = available_balance - 1000.0000 
WHERE account_id = (SELECT account_id FROM accounts LIMIT 1);

-- Establish SAVEPOINT
SAVEPOINT before_optional_service;

-- Simulate secondary service that triggers a check constraint violation (negative balance)
UPDATE accounts SET available_balance = available_balance - 999999999.0000 
WHERE account_id = (SELECT account_id FROM accounts LIMIT 1);
-- (This statement will fail due to chk_positive_balance constraint)

-- In case of failure:
ROLLBACK TO SAVEPOINT before_optional_service;

-- The primary transfer state is preserved, and transaction can commit successfully:
COMMIT;
