# Portfolio 5: Distributed and Cloud Database Exercise
**Course:** MIT 8103 Advanced Database Systems  
**Case Study:** NovaPay Financial Technologies Ltd.  
**Focus Area:** Declarative Table Partitioning, Partition Pruning, Multi-Region High-Availability Topology, Synchronous Physical Streaming Replication, Raft Consensus Quorum, and Horizontal Sharding

---

## 1. Cloud-Native Distributed Architecture Blueprint

To ensure 99.999% availability ("five nines") and sub-100ms latencies, NovaPay deploys a resilient, multi-region distributed cloud topology on AWS / GCP.

The architecture diagram is provided as an actual high-resolution image directly in this folder:
- **JPEG:** [`cloud_ha_architecture.jpg`](file:///C:/Users/Alamba%20Jnr/Desktop/Miva%20CA/advanced-database-portfolio/portfolio-5-distributed-cloud/cloud_ha_architecture.jpg)
- **PNG:** [`cloud_ha_architecture.png`](file:///C:/Users/Alamba%20Jnr/Desktop/Miva%20CA/advanced-database-portfolio/portfolio-5-distributed-cloud/cloud_ha_architecture.png)

![NovaPay Cloud High Availability & Sharding Architecture](cloud_ha_architecture.png)

---

## 2. High-Availability (HA) & Disaster Recovery Strategy

### 2.1 Recovery Metrics Specification:
- **Zero Data Loss (RPO = 0 seconds):** Primary writer in Availability Zone `af-south-1a` replicates synchronously to Hot Standby in `af-south-1b` using **Synchronous Physical Streaming Replication** (`synchronous_commit = on`). Write transactions do not return `COMMIT SUCCESS` until the WAL buffer is acknowledged and flushed to disk by the standby node.
- **Failover Recovery (RTO < 30 seconds):** Orchestrated via **Patroni** and a 3-node **etcd** consensus quorum implementing the **Raft consensus algorithm**. If the primary node fails heartbeat checks for 10 consecutive seconds, the DCS promotes the synchronous standby and updates routing without manual intervention.

### 2.2 Split-Brain Prevention via Quorum Consensus:
A network partition between database nodes could trick both into believing the other failed, leading to simultaneous independent writes (split-brain) that corrupt double-entry ledgers.  
NovaPay solves this using a **3-node etcd cluster implementing Raft**:
- A node may only accept writes if it holds the active leader lock granted by a majority ($N/2 + 1 = 2$ of 3) of etcd quorum nodes.
- An isolated primary automatically demotes itself to read-only mode (fencing) within 10 seconds.

---

## 3. Declarative Range Partitioning & Partition Pruning

The high-volume `transactions` table is partitioned by `RANGE (initiated_at)` into quarterly fiscal tables:
- `transactions_2026_q1` (Jan 1, 2026 to Apr 1, 2026)
- `transactions_2026_q2` (Apr 1, 2026 to Jul 1, 2026)
- `transactions_2026_q3` (Jul 1, 2026 to Oct 1, 2026)
- `transactions_2026_q4` (Oct 1, 2026 to Jan 1, 2027)
- `transactions_default` (Catch-all)

Each partition features its own dedicated local B-Tree index.  
**Partition Pruning Verification:** When a query specifies an `initiated_at` filter within Q1, PostgreSQL's query optimizer eliminates Q2, Q3, Q4, and Default partitions entirely at plan time, eliminating 75% of table scans and reducing disk I/O.

---

## 4. Horizontal Hash Sharding Architecture

When ledger size exceeds single-server limits (>10 TB), NovaPay shards accounts by customer ID:
$$\text{Shard ID} = \text{CRC32}(\text{customer\_id}) \pmod{N_{\text{shards}}}$$
- **Data Locality:** All accounts, profile details, and outgoing orders belonging to a single customer reside on the same shard node.
- **Cross-Shard Transfers (Saga Pattern):** Inter-shard fund transfers are managed via orchestrated Sagas over Apache Kafka, executing debits on the source shard and credits on the destination shard, with automated compensating reversal transactions if the beneficiary credit fails.

---

## 5. Files in this Directory

| File | Type | Description |
| :--- | :---: | :--- |
| `01_table_partitioning.sql` | SQL Script | Declarative range partitioning DDL, quarterly tables, seed data, and partition pruning test query. |
| `03_docker_compose_ha_cluster.yml` | YAML Config | Complete Docker Compose configuration setting up a 2-node PostgreSQL HA streaming replication cluster. |
| `cloud_ha_architecture.jpg` | JPEG Image | High-resolution 300 DPI diagram of NovaPay Multi-Region HA & Sharding topology. |
| `cloud_ha_architecture.png` | PNG Image | Crisp lossless PNG diagram of NovaPay Multi-Region HA & Sharding topology. |
| `partition_pruning_explain_plan.txt` | Text Log | Raw PostgreSQL `EXPLAIN ANALYZE` output log verifying partition pruning. |
| `README.md` | Markdown | Comprehensive activity guide, HA replication specs, consensus quorum, and sharding analysis. |

---

## 6. How to Run and Deploy

1. **Verify Partition Pruning in PostgreSQL:**
   ```bash
   psql -U postgres -d postgres -f 01_table_partitioning.sql
   ```
2. **Launch HA Cluster via Docker Compose:**
   ```bash
   docker compose -f 03_docker_compose_ha_cluster.yml up -d
   ```
3. **Verify Replication Status on Primary:**
   ```sql
   SELECT client_addr, state, sync_state, sync_priority FROM pg_stat_replication;
   ```
