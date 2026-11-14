# Portfolio 1: Database Design and Modelling
**Course:** MIT 8103 Advanced Database Systems  
**Case Study:** NovaPay Financial Technologies Ltd. (Core Banking & Payments System)

---

## 1. Selected Organisation & Business Scenario

**Organisation Name:** NovaPay Financial Technologies Ltd.  
**System Mission:** NovaPay operates a high-throughput, multi-currency neo-banking and payments infrastructure handling real-time peer-to-peer (P2P) transfers, merchant settlements, and bill payments. The platform requires strict double-entry legal ledger compliance, zero overdraft tolerance on non-credit accounts, sub-100ms response times, and full auditability.

### Database Users:
1. **Retail Customers:** Query balances, initiate P2P transfers, review transaction statements.
2. **Merchants:** Receive payment transfers, review settlement balances, reconcile commissions.
3. **Automated Settlement Engines:** Execute scheduled end-of-day reconciliation and interest processing.
4. **Compliance & Risk Officers:** Monitor suspicious transaction velocities and verify KYC tiers.
5. **System Administrators:** Supervise replication synchronicity, manage partitions, and maintain data integrity.

### Major Data Stored:
- Customer personal identities, national IDs (NIN), contact information, and KYC tiers.
- Depository accounts (multi-currency balances, transfer limits).
- Payment transactions (source, destination, merchant, amounts, fees, statuses).
- Immutable double-entry bookkeeping ledger journals (`ledger_entries`).
- Merchant profiles with merchant category codes (MCC) and commission rates.
- Forensic audit logs capturing state mutations (`old_state` and `new_state` as JSONB).

---

## 2. Entity-Relationship (ER) Diagram

The visual ER diagram is provided as an actual high-resolution image file directly in this folder:
- **JPEG:** [`erd_diagram.jpg`](file:///C:/Users/Alamba%20Jnr/Desktop/Miva%20CA/advanced-database-portfolio/portfolio-1-database-design/erd_diagram.jpg)
- **PNG:** [`erd_diagram.png`](file:///C:/Users/Alamba%20Jnr/Desktop/Miva%20CA/advanced-database-portfolio/portfolio-1-database-design/erd_diagram.png)

![NovaPay ER Diagram](erd_diagram.png)

### Relationship Cardinalities & Participation:
- `CUSTOMERS` to `ACCOUNTS`: **1 : N** (One customer owns one or more accounts).
- `ACCOUNTS` to `TRANSACTIONS`: **1 : N** (An account acts as source or destination for multiple transfers).
- `ACCOUNTS` to `MERCHANTS`: **1 : 1** (Each registered merchant links to a dedicated settlement account).
- `MERCHANTS` to `TRANSACTIONS`: **0..1 : N** (Merchants receive payments from customer transactions).
- `TRANSACTIONS` to `LEDGER_ENTRIES`: **1 : 2..N** (Every settled transaction generates at least two balanced debit/credit legs: $\sum \text{Debits} = \sum \text{Credits}$).
- `ACCOUNTS` to `LEDGER_ENTRIES`: **1 : N** (Ledger entries record immutable running balances for an account).

---

## 3. Relational Keys & Integrity Constraints

| Table Name | Primary Key | Alternate / Candidate Keys | Foreign Keys (Action) | Domain & Business Constraints |
| :--- | :--- | :--- | :--- | :--- |
| `customers` | `customer_id` (UUID) | `national_identity_no`, `email`, `phone_number` | None | Age $\ge 18$ years (`chk_customer_age`); `NOT NULL` on identity attributes. |
| `accounts` | `account_id` (UUID) | `account_number` (CHAR(10)) | `customer_id` $\to$ `customers` (`RESTRICT`) | `available_balance >= 0` (`chk_positive_balance`); valid ISO currencies. |
| `merchants` | `merchant_id` (UUID) | `registration_rc_number` | `settlement_account_id` $\to$ `accounts` (`RESTRICT`) | Commission rate between 0% and 20% (`chk_commission_rate`). |
| `transactions` | `transaction_id` (UUID) | `reference_no` | `source_account_id` $\to$ `accounts`<br>`destination_account_id` $\to$ `accounts` | `amount > 0`; `source <> destination`; valid transaction status ENUM. |
| `ledger_entries`| `entry_id` (UUID) | None (Surrogate) | `transaction_id` $\to$ `transactions`<br>`account_id` $\to$ `accounts` | `entry_type` IN ('DEBIT', 'CREDIT'); double-entry balancing invariant. |
| `system_audit_logs`| `audit_id` (BIGSERIAL)| None | `entity_id` (Synthetic pointer) | Automated trigger logs JSONB state before and after mutation. |

---

## 4. Normalisation Walkthrough & Functional Dependencies

### 4.1 Unnormalised Form (UNF)
Flat transaction slip with repeating groups and redundant customer attributes:
$$\text{UNF} = \{ \text{TxRef}, \text{TxDate}, \text{CustNIN}, \text{CustName}, \text{CustEmail}, \text{CustCity}, \text{CustZip}, \text{AccNo}, \text{Balance}, \text{DestAccNo}, \text{Amount}, \text{Fee}, \{ \text{AuditOfficer}, \text{AuditAction} \} \}$$
*Anomalies:* Duplication of customer data on every transaction; inability to insert new customer without a transaction.

### 4.2 First Normal Form (1NF)
Eliminated repeating groups and enforced atomic, single-valued attributes:
- Split customer full name into atomic `first_name` and `last_name`.
- Extracted repeating audit entries into a separate `system_audit_logs` table.
- Defined primary keys for each entity.

### 4.3 Second Normal Form (2NF)
Eliminated partial functional dependencies on composite candidate keys:
- In the composite staging key $\{\text{acc\_no}, \text{tx\_id}\}$:
  - $\text{FD}_1: \{ \text{acc\_no}, \text{tx\_id} \} \to \text{amount}, \text{fee}$ (Full dependency)
  - $\text{FD}_2: \text{acc\_no} \to \text{cust\_nin}, \text{balance}, \text{acc\_type}$ (Partial dependency)
- Decomposed into distinct `ACCOUNTS` and `TRANSACTIONS` relations where every non-key attribute depends entirely on the relation's primary key.

### 4.4 Third Normal Form (3NF) & Boyce-Codd Normal Form (BCNF)
Eliminated transitive dependencies:
- In customer staging: $\text{customer\_id} \to \text{postal\_code} \to \text{city}$ (Transitive). Separated address attributes.
- In merchant staging: $\text{merchant\_id} \to \text{mcc} \to \text{standard\_fee}$ (Transitive).
- **BCNF Verification:** Every non-trivial functional dependency $X \to Y$ has a determinant $X$ that is a candidate superkey (`customer_id`, `national_identity_no`, `account_id`, `account_number`, `transaction_id`). Therefore, the schema is strictly in **BCNF**.

### 4.5 Controlled Denormalisation Rationale
Pure normalization dictates that an account balance must never be stored, but computed dynamically as $\sum \text{Credits} - \sum \text{Debits}$. In an active OLTP banking system with millions of ledger entries, computing dynamic sums on every balance check causes massive CPU bottlenecks. NovaPay implements controlled denormalization: `available_balance` is cached on `accounts` and updated atomically within the same transaction that creates immutable balanced rows in `ledger_entries`.

---

## 5. Files in this Directory

| File | Type | Description |
| :--- | :---: | :--- |
| `01_schema_ddl.sql` | SQL Script | Production PostgreSQL 16 DDL with tables, custom ENUMs, constraints, and audit triggers. |
| `erd_diagram.jpg` | JPEG Image | High-resolution 300 DPI visual Entity-Relationship Diagram. |
| `erd_diagram.png` | PNG Image | Crisp lossless PNG visual Entity-Relationship Diagram. |
| `README.md` | Markdown | Comprehensive activity documentation, normalisation analysis, and execution instructions. |

---

## 6. How to Execute and Test

```bash
psql -U postgres -d postgres -f 01_schema_ddl.sql
```
Verify objects:
```sql
\dn novapay_core
\dt novapay_core.*
```
