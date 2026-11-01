// ============================================================================
// MIT 8103: ADVANCED DATABASE SYSTEMS - CONTINUOUS ASSESSMENT
// PORTFOLIO 4: NoSQL AND ADVANCED DATA MODELS
// SCRIPT 02: MONGODB IMPLEMENTATION, SCHEMA VALIDATION & AGGREGATION PIPELINES
// Compatibility: MongoDB 6.0+ / 7.0+ (mongosh)
// ============================================================================

// Switch to NovaPay NoSQL database
db = db.getSiblingDB("novapay_nosql");

// Drop existing collections for clean reproducible execution
db.customer_audit_events.drop();
db.payment_webhook_payloads.drop();

// ----------------------------------------------------------------------------
// 1. CREATE COLLECTIONS WITH JSON SCHEMA VALIDATION
// ----------------------------------------------------------------------------

db.createCollection("customer_audit_events", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["event_id", "customer_id", "event_type", "timestamp", "device_telemetry"],
      properties: {
        event_id: { bsonType: "string" },
        customer_id: { bsonType: "string" },
        event_type: { 
          enum: [
            "LOGIN_ATTEMPT", 
            "BIOMETRIC_AUTH_VERIFIED", 
            "PASSWORD_CHANGE", 
            "PIN_RETRY_EXCEEDED", 
            "BENEFICIARY_ADDED", 
            "HIGH_VALUE_TRANSFER_ATTEMPT"
          ] 
        },
        timestamp: { bsonType: "date" },
        device_telemetry: {
          bsonType: "object",
          required: ["device_id", "os_platform", "ip_address"],
          properties: {
            device_id: { bsonType: "string" },
            os_platform: { enum: ["iOS", "Android", "Web", "macOS", "Windows"] },
            ip_address: { bsonType: "string" },
            is_rooted_jailbroken: { bsonType: "bool" },
            is_emulator: { bsonType: "bool" }
          }
        },
        risk_assessment: {
          bsonType: "object",
          properties: {
            velocity_risk_score: { bsonType: "number" },
            risk_flags: { bsonType: "array" }
          }
        }
      }
    }
  }
});

db.createCollection("payment_webhook_payloads");

// ----------------------------------------------------------------------------
// 2. CREATE INDEXES (COMPOUND, TTL, AND TEXT)
// ----------------------------------------------------------------------------

// Compound Index: Accelerates chronological customer event lookups
db.customer_audit_events.createIndex(
  { customer_id: 1, timestamp: -1 },
  { name: "idx_cust_timestamp_desc" }
);

// Geo-Velocity Index: Used for anomaly detection across IP addresses
db.customer_audit_events.createIndex(
  { "device_telemetry.ip_address": 1, timestamp: -1 },
  { name: "idx_ip_timestamp" }
);

// TTL (Time-To-Live) Index: Automatically purges telemetry after 90 days (7,776,000 seconds)
db.customer_audit_events.createIndex(
  { timestamp: 1 },
  { expireAfterSeconds: 7776000, name: "ttl_90_days_retention" }
);

// Webhook Idempotency Index: Prevents duplicate webhook event processing
db.payment_webhook_payloads.createIndex(
  { "gateway_provider": 1, "raw_payload.event_id": 1 },
  { unique: true, sparse: true, name: "idx_webhook_idempotency" }
);

// ----------------------------------------------------------------------------
// 3. INSERT REALISTIC DOCUMENT DATA
// ----------------------------------------------------------------------------

const now = new Date();
const customerA = "11111111-aaaa-bbbb-cccc-111111111111";
const customerB = "22222222-aaaa-bbbb-cccc-222222222222";

db.customer_audit_events.insertMany([
  {
    event_id: "evt-001",
    customer_id: customerA,
    event_type: "LOGIN_ATTEMPT",
    timestamp: new Date(now.getTime() - 3600000 * 2), // 2 hrs ago
    device_telemetry: {
      device_id: "dev-iphone-14-pro",
      os_platform: "iOS",
      app_version: "4.2.0",
      ip_address: "102.89.34.12",
      geolocation: { city: "Lagos", region: "Lagos State", country: "NG" },
      is_rooted_jailbroken: false,
      is_emulator: false
    },
    risk_assessment: {
      velocity_risk_score: 12.5,
      risk_flags: []
    }
  },
  {
    event_id: "evt-002",
    customer_id: customerA,
    event_type: "HIGH_VALUE_TRANSFER_ATTEMPT",
    timestamp: new Date(now.getTime() - 3600000 * 1), // 1 hr ago
    device_telemetry: {
      device_id: "dev-iphone-14-pro",
      os_platform: "iOS",
      app_version: "4.2.0",
      ip_address: "102.89.34.12",
      geolocation: { city: "Lagos", region: "Lagos State", country: "NG" },
      is_rooted_jailbroken: false,
      is_emulator: false
    },
    risk_assessment: {
      velocity_risk_score: 25.0,
      risk_flags: ["ABOVE_AVERAGE_AMOUNT"]
    }
  },
  // Suspicious impossible travel: Login from London 15 minutes later!
  {
    event_id: "evt-003",
    customer_id: customerA,
    event_type: "LOGIN_ATTEMPT",
    timestamp: new Date(now.getTime() - 60000 * 45), // 45 mins ago
    device_telemetry: {
      device_id: "dev-unknown-android",
      os_platform: "Android",
      app_version: "4.1.0",
      ip_address: "185.220.101.5",
      geolocation: { city: "London", region: "Greater London", country: "GB" },
      is_rooted_jailbroken: true,
      is_emulator: true
    },
    risk_assessment: {
      velocity_risk_score: 95.0,
      risk_flags: ["IMPOSSIBLE_TRAVEL_VELOCITY", "ROOTED_DEVICE_DETECTED", "KNOWN_TOR_EXIT_NODE"]
    }
  },
  {
    event_id: "evt-004",
    customer_id: customerB,
    event_type: "LOGIN_ATTEMPT",
    timestamp: new Date(now.getTime() - 3600000 * 3),
    device_telemetry: {
      device_id: "dev-pixel-7",
      os_platform: "Android",
      app_version: "4.2.0",
      ip_address: "105.112.44.19",
      geolocation: { city: "Abuja", region: "FCT", country: "NG" },
      is_rooted_jailbroken: false,
      is_emulator: false
    },
    risk_assessment: {
      velocity_risk_score: 5.0,
      risk_flags: []
    }
  }
]);

// Insert Heterogeneous Payment Webhooks (Illustrates Schema Flexibility)
db.payment_webhook_payloads.insertMany([
  {
    webhook_id: "wh-stripe-99182",
    gateway_provider: "STRIPE",
    received_at: new Date(),
    processing_status: "PROCESSED",
    raw_payload: {
      id: "evt_3MjjFwLkdIwHu7ix0rW",
      object: "event",
      type: "payment_intent.succeeded",
      data: {
        object: {
          id: "pi_3MjjFwLkdIwHu7ix0",
          amount: 250000,
          currency: "usd",
          customer: "cus_99812",
          payment_method_types: ["card"]
        }
      }
    }
  },
  {
    webhook_id: "wh-paystack-55214",
    gateway_provider: "PAYSTACK",
    received_at: new Date(),
    processing_status: "PROCESSED",
    raw_payload: {
      event: "charge.success",
      data: {
        id: 3029102,
        domain: "live",
        status: "success",
        reference: "novapay_ref_778129",
        amount: 5000000,
        gateway_response: "Successful",
        channel: "card",
        customer: { email: "customer@domain.com" }
      }
    }
  }
]);

// ----------------------------------------------------------------------------
// 4. COMPLEX AGGREGATION PIPELINE: REAL-TIME FRAUD RISK ENGINE
// Aggregates multi-signal risk metrics across sliding windows
// ----------------------------------------------------------------------------

const fraudReport = db.customer_audit_events.aggregate([
  // Stage 1: Filter events from the past 24 hours
  {
    $match: {
      timestamp: { $gte: new Date(now.getTime() - 24 * 3600000) }
    }
  },
  // Stage 2: Group by customer to analyze telemetry diversity and risk spikes
  {
    $group: {
      _id: "$customer_id",
      total_events: { $sum: 1 },
      distinct_ips: { $addToSet: "$device_telemetry.ip_address" },
      distinct_countries: { $addToSet: "$device_telemetry.geolocation.country" },
      max_risk_score: { $max: "$risk_assessment.velocity_risk_score" },
      detected_flags: { $push: "$risk_assessment.risk_flags" },
      has_rooted_device: { $max: "$device_telemetry.is_rooted_jailbroken" },
      last_activity: { $max: "$timestamp" }
    }
  },
  // Stage 3: Flatten nested risk flag arrays
  {
    $project: {
      customer_id: "$_id",
      total_events: 1,
      unique_ip_count: { $size: "$distinct_ips" },
      distinct_countries: 1,
      unique_country_count: { $size: "$distinct_countries" },
      max_risk_score: 1,
      has_rooted_device: 1,
      last_activity: 1,
      aggregated_flags: {
        $reduce: {
          input: "$detected_flags",
          initialValue: [],
          in: { $setUnion: ["$$value", "$$this"] }
        }
      }
    }
  },
  // Stage 4: Filter accounts exhibiting high risk (> 50 score or multiple countries in 24h)
  {
    $match: {
      $or: [
        { max_risk_score: { $gte: 50 } },
        { unique_country_count: { $gt: 1 } },
        { has_rooted_device: true }
      ]
    }
  },
  // Stage 5: Sort by severity descending
  {
    $sort: { max_risk_score: -1 }
  }
]).toArray();

print("--- REAL-TIME FRAUD ANOMALY DETECTION AGGREGATION RESULT ---");
printjson(fraudReport);
