# Time Series Databases (TSDB): The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Gorilla Compression, Downsampling, and Retention Policies.

> [!IMPORTANT]
> **The Principal Rule**: A TSDB is **NOT** a fancy Postgres with a timestamp column. It's a database optimized for **append-only, time-ordered, high-cardinality** data.
> **The Use Case**: Metrics, IoT Sensors, Financial Ticks, Logs.

---

## 🎯 When Exactly TSDB?

### The Decision Matrix

| Scenario | Use TSDB? | Why? |
| :--- | :---: | :--- |
| **Metrics** (CPU, Memory, Latency) | ✅ Yes | High cardinality labels (host, service, region). |
| **IoT Sensors** (Temperature, GPS) | ✅ Yes | Millions of streams, append-only. |
| **Financial Tick Data** | ✅ Yes | Sub-millisecond precision, range queries. |
| **Event Logs** | ⚠️ Maybe | Consider Elasticsearch/Loki for text search. |
| **User Activity** | ❌ No | Use RDBMS/NoSQL (User ID is primary key, not time). |

---

## 🧠 God Mode: Gorilla Compression (Facebook)

> **Research Paper**: *"Gorilla: A Fast, Scalable, In-Memory Time Series Database"* (Facebook VLDB 2015).

Why is Prometheus so space-efficient? It uses **Gorilla Compression**.

### 1. Delta-of-Delta (Timestamps)
*   Timestamps are monotonically increasing.
*   Instead of storing `[1000, 1001, 1002, 1003]`, store `[1000, +1, +0, +0]`.
*   If deltas are stable, store **1 bit** (same as previous delta).

### 2. XOR Encoding (Values)
*   Consecutive metric values are often similar (CPU: 50.1%, 50.2%, 50.1%).
*   XOR `current_value ^ previous_value`. Most bits are 0.
*   Store only the differing bits.

**Result**: 1.37 bytes per data point (vs 16 bytes raw).

---

## 🏗️ TSDB Comparison

| Feature | Prometheus | InfluxDB | TimescaleDB | QuestDB |
| :--- | :--- | :--- | :--- | :--- |
| **Storage Engine** | TSDB (Custom) | TSM (Custom) | PostgreSQL (Hypertable) | Column Store (Custom) |
| **Query Language** | PromQL | InfluxQL / Flux | SQL | SQL |
| **Best For** | Metrics (Kubernetes) | IoT | SQL Users, Joins | High Ingest (4M rows/sec) |
| **Cardinality Limit** | ⚠️ Memory Bound | ⚠️ Series Limit | ✅ Disk-Based | ✅ Disk-Based |
| **Managed Option** | Grafana Cloud, Cortex | InfluxDB Cloud | Timescale Cloud | QuestDB Cloud |

---

## 🔧 Production Patterns

### 1. Downsampling (Rollups)
You don't need per-second resolution for data older than 7 days.
*   **Raw**: 1s resolution, 7 days retention.
*   **1m Rollup**: 1m aggregates (avg, max, min), 30 days retention.
*   **1h Rollup**: 1h aggregates, 1 year retention.

### 2. Retention Policies
*   **Hot Tier**: SSD, recent data.
*   **Cold Tier**: Object Storage (S3), older data.
*   Prometheus: `--storage.tsdb.retention.time=15d`.

### 3. High Cardinality (The TSDB Killer)
*   Each unique combination of labels is a **Series**.
*   `metric{host="A", service="B", endpoint="/users/123"}` = 1 series.
*   If `endpoint` has 1M unique values, you have 1M series. **Memory explodes.**
*   **Solution**: Don't put high-cardinality fields (User ID, Request ID) in labels. Put them in log systems.

---

## ✅ Principal Architect Checklist

1.  **Cardinality Budget**: Set a maximum number of series. Alert if exceeded.
2.  **Compaction**: Understand how your TSDB merges SSTables/Blocks. Schedule during low traffic.
3.  **Backfill Carefully**: TSDBs are optimized for append. Writing old data out-of-order is expensive.
4.  **Use Remote Write**: Push Prometheus data to a scalable backend (Cortex, Thanos, Mimir) for long-term storage.

---

## 🔗 Related Documents
*   [Monitoring & Observability](../infrastructure-techniques/monitoring-observability-comprehensive.md) — Prometheus/Grafana stack.
*   [Kafka Deep Dive](../pubsub-techniques-and-notes/kafka-deep-dive-guide.md) — Event streaming for logs.
