-- ============================================================================
-- MIT 8103: ADVANCED DATABASE SYSTEMS - CONTINUOUS ASSESSMENT
-- PORTFOLIO 3: TRANSACTIONS AND CONCURRENCY
-- SCRIPT 02: CONCURRENCY ANOMALIES & TRANSACTION ISOLATION LEVELS
-- ============================================================================

SET search_path TO novapay_core, public;


-- ANOMALY 1: THE LOST UPDATE PHENOMENON
-- Scenario: Two concurrent ATMs/mobile sessions attempt to withdraw funds
-- from the same account with Initial Balance = NGN 100,000.
-- Both sessions read balance = 100,000.
-- Session 1 withdraws 60,000 (expects balance = 40,000).
-- Session 2 withdraws 70,000 (expects balance = 30,000).
-- Without concurrency control, Session 2 overwrites Session 1!


-- SESSION 1 (Simulated step-by-step):
-- STEP 1.1:
BEGIN;
SELECT available_balance FROM accounts WHERE account_number = '1000000001';
-- Returns 100,000.0000

-- SESSION 2 (Simulated simultaneously):
-- STEP 2.1:
BEGIN;
SELECT available_balance FROM accounts WHERE account_number = '1000000001';
-- Returns 100,000.0000

-- STEP 1.2: Session 1 calculates (100,000 - 60,000 = 40,000) and updates:
UPDATE accounts SET available_balance = 40000.0000 WHERE account_number = '1000000001';
COMMIT;

-- STEP 2.2: Session 2 calculates (100,000 - 70,000 = 30,000) based on its stale read and updates:
UPDATE accounts SET available_balance = 30000.0000 WHERE account_number = '1000000001';
COMMIT;

-- RESULT: Final balance is 30,000.0000!
-- Total withdrawn = 130,000 from an account that only had 100,000!
-- Session 1's withdrawal deduction was completely LOST!



-- ANOMALY 2: NON-REPEATABLE READ UNDER READ COMMITTED vs REPEATABLE READ
-- Scenario: An audit process verifies customer balances while a transfer occurs.


-- A. DEMONSTRATION UNDER 'READ COMMITTED' (Default in PostgreSQL)
-- Session A (Audit Officer):
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT available_balance FROM accounts WHERE account_number = '1000000002'; -- Reads 50,000.00

-- Session B (Concurrent Transfer):
BEGIN;
UPDATE accounts SET available_balance = 45000.00 WHERE account_number = '1000000002';
COMMIT;

-- Session A re-queries within the SAME transaction:
SELECT available_balance FROM accounts WHERE account_number = '1000000002'; -- Reads 45,000.00!
-- Observation: Non-repeatable read occurred because committed changes from Session B became visible.
COMMIT;


-- B. RESOLUTION UNDER 'REPEATABLE READ'
-- Session A (Audit Officer):
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT available_balance FROM accounts WHERE account_number = '1000000002'; -- Reads 45,000.00

-- Session B:
BEGIN;
UPDATE accounts SET available_balance = 40000.00 WHERE account_number = '1000000002';
COMMIT;

-- Session A re-queries within the same transaction:
SELECT available_balance FROM accounts WHERE account_number = '1000000002'; -- Still reads 45,000.00!
-- Observation: Repeatable Read guarantees snapshot isolation; Session A sees consistent snapshot from transaction start.
COMMIT;



-- ANOMALY 3: PHANTOM READ & SERIALIZATION ANOMALY
-- Scenario: Compliance rule states that an account may not have more than 3 active cards.
-- Two concurrent sessions attempt to add a new card simultaneously.


-- SESSION 1:
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) FROM transactions WHERE source_account_id = 'c1111111-1111-1111-1111-111111111111' AND initiated_at >= CURRENT_DATE;
-- Count is 2

-- SESSION 2:
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) FROM transactions WHERE source_account_id = 'c1111111-1111-1111-1111-111111111111' AND initiated_at >= CURRENT_DATE;
-- Count is 2

-- SESSION 1 inserts:
INSERT INTO transactions (reference_no, source_account_id, destination_account_id, amount, transaction_type, status, narration)
VALUES ('REF-SER-001', 'c1111111-1111-1111-1111-111111111111', 'd2222222-2222-2222-2222-222222222222', 100, 'P2P_TRANSFER', 'SETTLED', 'Card tap 1');
COMMIT; -- Succeeds

-- SESSION 2 inserts:
INSERT INTO transactions (reference_no, source_account_id, destination_account_id, amount, transaction_type, status, narration)
VALUES ('REF-SER-002', 'c1111111-1111-1111-1111-111111111111', 'd2222222-2222-2222-2222-222222222222', 200, 'P2P_TRANSFER', 'SETTLED', 'Card tap 2');
COMMIT;
-- In SERIALIZABLE isolation, PostgreSQL detects the write-skew / serialization dependency graph cycle and throws:
-- ERROR: could not serialize access due to read/write dependencies among transactions
-- Detail: Reason code = Canceled on identification as a pivot, during commit attempt.
-- Hint: The transaction might succeed if it is retried.
