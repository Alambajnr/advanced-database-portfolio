# Portfolio 2: Query Processing and Optimisation
**Course:** MIT 8103 Advanced Database Systems  
**Case Study:** NovaPay Financial Technologies Ltd.  
**Focus Area:** Workload Profiling, Execution Plan Analysis (`EXPLAIN ANALYZE`), Indexing Engineering, and Quantitative Benchmarking

---

## 1. Overview & Dataset Scale

To demonstrate query optimization over non-trivial volume, this module generates a realistic synthetic dataset across the `novapay_core` relational schema:
- **Customers:** 5,000 rows
- **Accounts:** 10,000 depository accounts
- **Merchants:** 200 registered commercial vendors
- **Transactions:** 150,000+ financial transaction instructions
- **Ledger Entries:** 300,000+ balanced double-entry debit/credit journal legs

The data is generated using PostgreSQL set-returning functions (`generate_series()`, `random()`, array lookups, and chronological distribution intervals).

---

## 2. Quantitative Performance Benchmark Matrix

| Workload Query | Baseline Access Path | Optimized Access Path | Baseline Time | Optimized Time | Latency Improvement | I/O Buffer Improvement |
| :--- | :--- | :--- | :--- | :--- | :---: | :---: |
| **Q1: Account Statement (50 rows)** | Parallel Seq Scan + Top-N Sort | Index Scan (`idx_transactions_src_acc_initiated`) | **68.61 ms** | **0.23 ms** | **99.66% Faster** (298x) | 4,232 $\to$ 18 blocks (-99.5%) |
| **Q2: Pending Settlements (2% rows)** | Parallel Seq Scan | Bitmap Index Scan (`idx_transactions_pending_settlement`)| **44.18 ms** | **0.31 ms** | **99.30% Faster** (142x) | 3,840 $\to$ 14 blocks (-99.6%) |
| **Q3: Account Verification Check** | Heap Sequential Scan | Index Only Scan (`idx_accounts_accno_covering`) | **3.45 ms** | **0.04 ms** | **98.84% Faster** (86x) | 215 $\to$ 3 blocks (0 heap fetches) |
| **Q4: Merchant 30-Day Volume** | Full Table Join + Hash Aggregate | Bitmap Scan + Hash Aggregate | **112.50 ms** | **4.85 ms** | **95.69% Faster** (23x) | 5,612 $\to$ 86 blocks (-98.5%) |

---

## 3. Technical Mechanics of the Indexing Strategies

### 3.1 Composite B-Tree Index: `idx_transactions_src_acc_initiated`
- **Definition:** `(source_account_id, initiated_at DESC)`
- **Problem:** Baseline queries scanned 150,000 rows across 3,800+ disk blocks and performed a memory-intensive `Top-N Heapsort`.
- **Solution:** Organizes index tuples first by `source_account_id` and pre-sorted by `initiated_at DESC`. The optimizer traverses the B-Tree in $O(\log N)$ time and streams the 50 rows in exact sort order without a runtime sort step.

### 3.2 Partial (Filtered) Index: `idx_transactions_pending_settlement`
- **Definition:** `(initiated_at ASC) WHERE status = 'PENDING'`
- **Problem:** Settled transactions represent >95% of the table, while pending transactions awaiting settlement represent only ~2%. A full index would waste 15 MB of RAM.
- **Solution:** Indexing only `status = 'PENDING'` produces an ultra-compact index (~240 KB) that permanently resides in PostgreSQL `shared_buffers`, enabling sub-millisecond retrieval for settlement workers.

### 3.3 Covering Index: `idx_accounts_accno_covering` with `INCLUDE`
- **Definition:** `(account_number) INCLUDE (customer_id, available_balance, currency_code, status)`
- **Problem:** Standard index scans must retrieve tuple pointers from the index and read the table heap pages to get non-indexed columns.
- **Solution:** The `INCLUDE` clause embeds the payload columns into the index leaf pages. Because PostgreSQL's Visibility Map confirms no dead tuples exist on the pages, the engine executes an **Index Only Scan** with **zero heap fetches**.

---

## 4. Query Optimizer Cost Model Insights

PostgreSQL's Cost-Based Optimizer (CBO) evaluates total execution cost using:

$$\text{Cost} = (N_{\text{seq\_pages}} \times \text{seq\_page\_cost}) + (N_{\text{rnd\_pages}} \times \text{random\_page\_cost}) + (N_{\text{tuples}} \times \text{cpu\_tuple\_cost}) + (N_{\text{ops}} \times \text{cpu\_operator\_cost})$$

In unindexed queries, $N_{\text{seq\_pages}}$ was over 3,800 pages, driving baseline costs above 7,800 units. Targeted indexing reduced $N_{\text{rnd\_pages}}$ to 3–18 pages, reducing estimated costs to under 9 units.

---

## 5. Files in this Directory

| File | Type | Description |
| :--- | :---: | :--- |
| `01_seed_data.sql` | SQL Script | High-velocity synthetic data generation script populating 150,000+ transactions and 300,000+ ledger entries. |
| `02_complex_queries.sql` | SQL Script | 4 production business queries (Window functions, CTEs, self-joins, aggregations, DENSE_RANK). |
| `03_query_optimization_and_benchmarks.sql` | SQL Script | DDL for composite, partial, and covering indexes with before-and-after `EXPLAIN (ANALYZE, BUFFERS)` queries. |
| `execution_plans_and_benchmarks.txt` | Text Log | Raw terminal outputs of PostgreSQL execution plans showing buffers, timing, and costs. |
| `README.md` | Markdown | Comprehensive activity guide, quantitative benchmark matrix, and optimizer cost analysis. |

---

## 6. How to Run the Benchmarks

1. **Seed the Database:**
   ```bash
   psql -U postgres -d postgres -f 01_seed_data.sql
   ```
2. **Execute Complex Queries:**
   ```bash
   psql -U postgres -d postgres -f 02_complex_queries.sql
   ```
3. **Run Indexing & Benchmarks:**
   ```bash
   psql -U postgres -d postgres -f 03_query_optimization_and_benchmarks.sql
   ```
