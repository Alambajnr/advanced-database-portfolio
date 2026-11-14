# Portfolio 3: Transactions and Concurrency
**Course:** MIT 8103 Advanced Database Systems  
**Case Study:** NovaPay Financial Technologies Ltd.  
**Focus Area:** ACID Transaction Processing, SQL Isolation Levels, Concurrency Anomalies, Pessimistic Row Locking, Deadlock Avoidance, and Optimistic Concurrency Control (OCC)

---

## 1. ACID Guarantees in NovaPay Core Banking

| ACID Property | Implementation Mechanism in NovaPay | Technical Verification |
| :--- | :--- | :--- |
| **Atomicity** | Wrapped in PL/pgSQL procedures (`transfer_funds_atomic`) with explicit `COMMIT`, `ROLLBACK`, and `SAVEPOINT` handlers. | If any check constraint fails (e.g. insufficient balance), all debit, credit, and journal operations are rolled back completely. |
| **Consistency** | Database constraints (`CHECK (available_balance >= 0)`, FK `RESTRICT`, and trigger-enforced double-entry invariant $\sum \text{Debits} = \sum \text{Credits}$). | Any attempted update violating double-entry balance raises a fatal exception and aborts. |
| **Isolation** | Configurable isolation levels (`READ COMMITTED`, `REPEATABLE READ`, `SERIALIZABLE`) alongside pessimistic row-level locking (`SELECT ... FOR UPDATE`). | Eliminates Lost Updates and Dirty Reads, preventing race conditions during concurrent ATM/mobile withdrawals. |
| **Durability** | PostgreSQL Write-Ahead Logging (WAL) with synchronous commit (`synchronous_commit = on`). | State is flushed to persistent disk prior to acknowledging transaction completion; survives sudden power outages. |

---

## 2. Concurrency Anomalies & Control Mechanisms

### 2.1 The Lost Update Problem & Pessimistic Locking
- **The Issue:** Two concurrent sessions (e.g. ATM withdrawal of NGN 70,000 and mobile transfer of NGN 60,000) read the identical initial balance of NGN 100,000. Session 1 commits NGN 40,000; Session 2 calculates NGN 30,000 based on stale read and overwrites Session 1, allowing an unauthorized overdraft of NGN 30,000!
- **The Solution:** We acquire an exclusive row-level lock using `SELECT ... FOR UPDATE`. Session 2 is placed in a lock-wait state until Session 1 commits. Upon waking, Session 2 observes the committed balance of NGN 40,000 and gracefully rejects the NGN 70,000 withdrawal with zero overdraft.

### 2.2 Deadlock Simulation & Deterministic Lock Ordering
- **The Issue:** When Customer A transfers to Customer B while Customer B transfers to Customer A simultaneously, uncoordinated locking of accounts causes cyclic lock waiting, triggering PostgreSQL's deadlock detection engine (`ERROR: deadlock detected`).
- **The Solution:** In `transfer_deadlock_free`, locks are always acquired in ascending order of primary key: `LEAST(acc_a, acc_b)` followed by `GREATEST(acc_a, acc_b)`. This mathematically eliminates cycles in the Resource Allocation Graph (RAG).

### 2.3 Optimistic Concurrency Control (OCC)
For high-frequency, low-contention operations (e.g., customer daily limit updates), acquiring exclusive locks creates unnecessary overhead. We implement OCC using a monotonic `version_no` column on `accounts`:
```sql
UPDATE accounts 
SET daily_transfer_limit = p_new_limit, version_no = version_no + 1
WHERE account_id = p_account_id AND version_no = p_expected_version;
```
If `ROW_COUNT = 0`, a concurrent update modified the row, and the application layer safely retries without database-level blocking.

---

## 3. Files in this Directory

| File | Type | Description |
| :--- | :---: | :--- |
| `01_acid_transactions.sql` | SQL Script | Atomic stored procedure executing double-entry balance updates, explicit `COMMIT`, `ROLLBACK`, and `SAVEPOINT` recovery. |
| `02_concurrency_anomalies_and_isolation.sql` | SQL Script | Demonstrations of Lost Update, Non-Repeatable Read, and Serialization anomalies across SQL isolation levels. |
| `03_concurrency_control_mechanisms.sql` | SQL Script | Implementations of Pessimistic Locking (`SELECT FOR UPDATE`), deadlock-free deterministic lock ordering, and OCC version numbering. |
| `concurrency_test_output.log` | Text Log | Interactive psql dual-session terminal logs, `pg_locks` queries, and deadlock detection traces. |
| `README.md` | Markdown | Comprehensive activity guide, ACID analysis, and concurrency control documentation. |

---

## 4. How to Test and Reproduce

1. **Load the Stored Procedures:**
   ```bash
   psql -U postgres -d postgres -f 01_acid_transactions.sql
   ```
2. **Simulate Concurrent Sessions:**
   Open two separate terminal windows and run Session 1 and Session 2 from `02_concurrency_anomalies_and_isolation.sql` concurrently.
3. **Verify Concurrency Control & OCC:**
   ```bash
   psql -U postgres -d postgres -f 03_concurrency_control_mechanisms.sql
   ```
