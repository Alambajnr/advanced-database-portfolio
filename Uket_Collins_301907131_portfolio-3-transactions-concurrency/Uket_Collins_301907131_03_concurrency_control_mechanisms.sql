-- ============================================================================
-- MIT 8103: ADVANCED DATABASE SYSTEMS - CONTINUOUS ASSESSMENT
-- PORTFOLIO 3: TRANSACTIONS AND CONCURRENCY
-- SCRIPT 03: CONCURRENCY CONTROL MECHANISMS (PESSIMISTIC vs OPTIMISTIC) & DEADLOCK RESOLUTION
-- ============================================================================

SET search_path TO novapay_core, public;


-- 1. PESSIMISTIC CONCURRENCY CONTROL (PCC) VIA ROW-LEVEL LOCKING


-- Solution to the Lost Update problem using SELECT ... FOR UPDATE
-- When Session 1 locks the row, Session 2 is forced into a lock wait state
-- until Session 1 completes its COMMIT.

-- SESSION 1:
BEGIN;
SELECT available_balance 
FROM accounts 
WHERE account_number = '1000000001' 
FOR UPDATE; -- Exclusive row-level lock acquired!

-- Calculate: 100,000 - 60,000 = 40,000
UPDATE accounts SET available_balance = 40000.0000 WHERE account_number = '1000000001';
-- Simulate think time or processing delay
SELECT pg_sleep(3);
COMMIT; -- Releases lock.

-- SESSION 2 (Executed concurrently):
BEGIN;
SELECT available_balance 
FROM accounts 
WHERE account_number = '1000000001' 
FOR UPDATE; 
-- BLOCKS HERE until Session 1 commits!
-- Once unblocked, Session 2 immediately reads the UPDATED balance of 40,000!
-- Session 2 sees that 40,000 < 70,000 and gracefully rejects the transaction!
ROLLBACK;



-- 2. DEADLOCK SIMULATION AND RESOLUTION


-- A. CAUSING A DEADLOCK (Unordered Locks)
-- Given Account X ('11111111-1111-1111-1111-111111111111') and Account Y ('22222222-2222-2222-2222-222222222222')

-- Session 1:
-- BEGIN;
-- SELECT * FROM accounts WHERE account_id = '11111111-1111-1111-1111-111111111111' FOR UPDATE;
-- (Wants Account Y next)

-- Session 2:
-- BEGIN;
-- SELECT * FROM accounts WHERE account_id = '22222222-2222-2222-2222-222222222222' FOR UPDATE;
-- (Wants Account X next)

-- Session 1 tries to lock Account Y:
-- SELECT * FROM accounts WHERE account_id = '22222222-2222-2222-2222-222222222222' FOR UPDATE; -- BLOCKS!

-- Session 2 tries to lock Account X:
-- SELECT * FROM accounts WHERE account_id = '11111111-1111-1111-1111-111111111111' FOR UPDATE; -- DEADLOCK!

-- Postgres Deadlock detector triggers after deadlock_timeout (default 1s):
-- ERROR: deadlock detected
-- DETAIL: Process 2314 waits for ShareLock on transaction 8213; blocked by process 2315.
-- Process 2315 waits for ExclusiveLock on tuple (0,2) of relation "accounts"; blocked by process 2314.
-- HINT: See server log for query details.


-- B. DEADLOCK PREVENTION STRATEGY (DETERMINISTIC GLOBAL LOCK ORDERING)
-- By enforcing that transactions always acquire locks in ascending order of primary key,
-- a cyclic dependency in the Resource Allocation Graph (RAG) is mathematically impossible!

CREATE OR REPLACE PROCEDURE transfer_deadlock_free(
    p_acc_a UUID,
    p_acc_b UUID,
    p_amount NUMERIC(16, 4)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_first_acc UUID;
    v_second_acc UUID;
BEGIN
    -- Sort keys deterministically
    IF p_acc_a < p_acc_b THEN
        v_first_acc := p_acc_a;
        v_second_acc := p_acc_b;
    ELSE
        v_first_acc := p_acc_b;
        v_second_acc := p_acc_a;
    END IF;

    -- Acquire locks strictly in ordered sequence
    PERFORM * FROM accounts WHERE account_id = v_first_acc FOR UPDATE;
    PERFORM * FROM accounts WHERE account_id = v_second_acc FOR UPDATE;

    -- Proceed with transfer operations safely without risk of deadlock
    UPDATE accounts SET available_balance = available_balance - p_amount WHERE account_id = p_acc_a;
    UPDATE accounts SET available_balance = available_balance + p_amount WHERE account_id = p_acc_b;
END;
$$;



-- 3. OPTIMISTIC CONCURRENCY CONTROL (OCC) VIA VERSION NUMBERING
-- Ideal for high-throughput, low-contention scenarios (e.g. mobile profile updates)


CREATE OR REPLACE FUNCTION update_account_limit_occ(
    p_account_id UUID,
    p_new_limit NUMERIC(16, 4),
    p_expected_version BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows_affected INT;
BEGIN
    UPDATE accounts
    SET daily_transfer_limit = p_new_limit,
        version_no = version_no + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_id = p_account_id 
      AND version_no = p_expected_version;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected = 0 THEN
        -- Another transaction updated this row concurrently! Version mismatch!
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

-- Demonstration of OCC in action:
DO $$
DECLARE
    v_acc UUID;
    v_current_version BIGINT;
    v_success BOOLEAN;
BEGIN
    SELECT account_id, version_no INTO v_acc, v_current_version FROM accounts LIMIT 1;
    
    -- Transaction 1 updates using verified version
    v_success := update_account_limit_occ(v_acc, 750000.0000, v_current_version);
    RAISE NOTICE 'First update attempt: % (Expected version %)', v_success, v_current_version;

    -- Transaction 2 attempts to update using STALE version number
    v_success := update_account_limit_occ(v_acc, 900000.0000, v_current_version);
    RAISE NOTICE 'Concurrent update attempt with stale version: % (OCC Conflict Handled Successfully)', v_success;
END $$;
