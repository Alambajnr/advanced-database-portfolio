# Portfolio 4: NoSQL and Advanced Data Models
**Course:** MIT 8103 Advanced Database Systems  
**Case Study:** NovaPay Financial Technologies Ltd.  
**Focus Area:** Document Store Modeling (MongoDB 7.0), JSON Schema Validation, Real-Time Aggregation Pipelines, CAP & PACELC Theorems, and Polyglot Persistence

---

## 1. Architectural Rationale & Polyglot Persistence

In financial technology engineering, no single database engine satisfies all operational requirements. NovaPay adopts a **Polyglot Persistence Architecture**:
- **PostgreSQL 16 (Relational ACID Core):** Acts as the single source of truth for depository accounts, multi-currency balances, and legal double-entry ledger journals.
- **MongoDB 7.0 (Document Store Event Stream):** Ingests high-velocity, semi-structured mobile telemetry, device fingerprints, biometric verification flags, and heterogeneous third-party payment webhooks (Stripe, Paystack, Flutterwave).

The architecture diagram is provided as an actual high-resolution image directly in this folder:
- **JPEG:** [`polyglot_architecture.jpg`](file:///C:/Users/Alamba%20Jnr/Desktop/Miva%20CA/advanced-database-portfolio/portfolio-4-nosql/polyglot_architecture.jpg)
- **PNG:** [`polyglot_architecture.png`](file:///C:/Users/Alamba%20Jnr/Desktop/Miva%20CA/advanced-database-portfolio/portfolio-4-nosql/polyglot_architecture.png)

![NovaPay Polyglot Architecture](polyglot_architecture.png)

---

## 2. Document Data Modeling & Schema Validation

### 2.1 Collections Implemented:
1. `customer_audit_events`: Stores nested mobile device telemetry (`is_rooted_jailbroken`, `ip_address`, `app_version`), GPS geolocations, and risk assessments. Enforced using MongoDB `$jsonSchema` validation.
2. `payment_webhook_payloads`: Ingests heterogeneous payloads from external gateways without requiring SQL DDL migrations.

### 2.2 Indexing Engineering in MongoDB:
- **Compound Index:** `{ customer_id: 1, timestamp: -1 }` accelerates chronological customer activity lookups.
- **Geo-IP Index:** `{ "device_telemetry.ip_address": 1, timestamp: -1 }` accelerates velocity analysis.
- **TTL (Time-To-Live) Index:** `{ timestamp: 1 }` with `expireAfterSeconds: 7776000` automatically purges non-critical audit records after 90 days, fulfilling regulatory data retention rules.
- **Idempotency Index:** `{ gateway_provider: 1, "raw_payload.event_id": 1 }` with `unique: true` prevents double-crediting from duplicate external webhooks.

---

## 3. Real-Time Fraud Anomaly Aggregation Pipeline

A multi-stage pipeline aggregates sliding 24-hour windows to calculate real-time composite fraud scores:
```javascript
db.customer_audit_events.aggregate([
  { $match: { timestamp: { $gte: new Date(Date.now() - 24 * 3600000) } } },
  { $group: {
      _id: "$customer_id",
      total_events: { $sum: 1 },
      distinct_ips: { $addToSet: "$device_telemetry.ip_address" },
      distinct_countries: { $addToSet: "$device_telemetry.geolocation.country" },
      max_risk_score: { $max: "$risk_assessment.velocity_risk_score" },
      has_rooted_device: { $max: "$device_telemetry.is_rooted_jailbroken" },
      last_activity: { $max: "$timestamp" }
  }},
  { $project: {
      customer_id: "$_id",
      unique_ip_count: { $size: "$distinct_ips" },
      unique_country_count: { $size: "$distinct_countries" },
      max_risk_score: 1, has_rooted_device: 1, last_activity: 1
  }},
  { $match: {
      $or: [
        { max_risk_score: { $gte: 50 } },
        { unique_country_count: { $gt: 1 } },
        { has_rooted_device: true }
      ]
  }},
  { $sort: { max_risk_score: -1 } }
]);
```
*Detection Capability:* Automatically catches impossible travel velocities (e.g. login from Lagos followed by login from London 45 minutes later) and rooted device tampering.

---

## 4. Theoretical Analysis: CAP & PACELC Theorems

### 4.1 CAP Theorem in NovaPay:
- **Core Ledger (PostgreSQL): CP System.** Under network partitioning, consistency is non-negotiable. The cluster rejects unacknowledged writes rather than risking double-spend anomalies or ledger imbalance.
- **Telemetry Stream (MongoDB): AP System.** High-velocity event ingestion favors availability and sub-millisecond response time, tolerating eventual consistency across read replicas.

### 4.2 PACELC Theorem Deep Dive:
$$\textbf{If Partition (P)} \implies \text{[Availability (A)] vs [Consistency (C)]}$$
$$\textbf{Else (E)} \implies \text{[Latency (L)] vs [Consistency (C)]}$$
- **PostgreSQL Core Ledger: PC / EC.** When partitioned, choose Consistency. When operating normally, choose Consistency over Latency (synchronous WAL commits).
- **MongoDB Telemetry Stream: PA / EL.** When partitioned, choose Availability. When operating normally, choose low Latency over immediate Consistency.

---

## 5. Files in this Directory

| File | Type | Description |
| :--- | :---: | :--- |
| `01_nosql_data_model.json` | JSON Schema | Schema specifications with `$jsonSchema` rules for telemetry and heterogeneous webhooks. |
| `02_mongodb_implementation.js` | JavaScript | Executable mongosh script with collections, compound/TTL indexes, sample data, and fraud pipeline. |
| `polyglot_architecture.jpg` | JPEG Image | High-resolution 300 DPI diagram of NovaPay Polyglot Persistence Architecture. |
| `polyglot_architecture.png` | PNG Image | Crisp lossless PNG diagram of NovaPay Polyglot Persistence Architecture. |
| `README.md` | Markdown | Comprehensive activity guide, CAP/PACELC theorem evaluation, and trade-off analysis. |

---

## 6. How to Run and Verify

```bash
# Run MongoDB in Docker:
docker run -d --name novapay-mongo -p 27017:27017 mongo:7.0

# Execute MongoDB Script via mongosh:
mongosh "mongodb://localhost:27017" 02_mongodb_implementation.js
```
