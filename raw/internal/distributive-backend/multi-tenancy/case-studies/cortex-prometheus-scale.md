# Cortex: Multi-Tenant Prometheus at Scale

> **Source**: [Project Frankenstein - PromCon 2016 (Tom Wilkie, Weaveworks)](https://youtu.be/3Tb4Wc0kfCM)

> [!IMPORTANT]
> **The Core Achievement**: Project Frankenstein (now **Cortex**) transforms Prometheus from a single-instance monitoring tool into a **multi-tenant, horizontally scalable** observability platform capable of handling **tens of millions of samples per second** with **infinite retention**.

---

## 📊 Architecture Overview

![Cortex Multi-Tenant Architecture](assets/cortex-architecture.png)

---

## 🔄 Prometheus vs Cortex

![Prometheus vs Cortex](assets/prometheus-vs-cortex.png)

### Why Cortex?
Standard Prometheus is a **monolith** with limitations:
*   Single instance (vertical scaling only).
*   Local storage (disk limits retention).
*   No multi-tenancy (no auth, no isolation).

Cortex solves all three by **decomposing Prometheus into microservices**.

---

## 🎯 Design Goals

| Goal | Description |
| :--- | :--- |
| **100% API Compatibility** | Drop-in replacement for Prometheus queries. |
| **Multi-Tenancy** | Authentication, access control, tenant isolation. |
| **Horizontal Scalability** | Handle 10M+ samples/sec via scale-out. |
| **Infinite Retention** | Leverage cloud storage (S3) for unlimited history. |
| **Low Operational Overhead** | Stateless services; state offloaded to AWS. |

---

## 🏗️ The Three Microservices

### 1. Retriever (User Datacenter)
*   A **vanilla Prometheus** instance running in the customer's environment.
*   Acts as a **scraper only**—gathers samples and pushes via Remote Write.
*   Can run **without local storage** (pure gateway mode).

### 2. Distributor (Stateless Router)
*   Receives incoming samples from Retrievers.
*   Uses **consistent hashing** on `(tenant_id, metric_name)`.
*   Routes samples to the correct Ingester.
*   Also handles **PromQL query parsing**.

### 3. Ingester (In-Memory Buffer)
*   Buffers samples in memory for **~1 hour**.
*   Maintains an **in-memory inverted index** for fast recent queries.
*   Periodically **flushes** data:
    *   Chunks → **S3** (immutable time-series data).
    *   Index → **DynamoDB** (label-to-chunk mapping).

---

## 🔀 Write & Query Paths

![Write and Query Paths](assets/cortex-data-flow.png)

### Write Path
1.  Prometheus **scrapes** targets locally.
2.  **Remote Write** sends samples to Cortex.
3.  **Distributor** hashes by tenant + metric, routes to Ingester.
4.  **Ingester** buffers in memory (~1 hour).
5.  **Flush** writes chunks to S3, index to DynamoDB.

### Query Path
1.  **PromQL query** arrives at Query Frontend.
2.  **Query Frontend** splits by time range, deduplicates.
3.  **Querier** checks Ingester for recent data.
4.  **Querier** fetches historical data from S3/DynamoDB.
5.  **Memcached** caches frequently accessed chunks.
6.  **Response** merges and returns results.

---

## 🗄️ Storage Architecture

| Component | Purpose | Technology |
| :--- | :--- | :--- |
| **Chunks** | Immutable time-series data | Amazon S3 |
| **Index** | Label → Chunk ID mapping | DynamoDB |
| **Cache** | Query acceleration | Memcached |

### Why DynamoDB + S3?
*   Weaveworks is a small team—didn't want to manage Cassandra.
*   DynamoDB: Low latency, high availability (expensive but managed).
*   S3: Infinite storage, cheap for historical data.

---

## 🔒 Multi-Tenancy Implementation

### How It Works
*   Every sample tagged with `tenant_id`.
*   **Distributor** authenticates requests, extracts tenant.
*   **Consistent hashing** ensures tenant data stays together.
*   **Access control** prevents cross-tenant queries.

### Live Demo Example (from talk)
Switching between "dev" and "prod" environments showed:
*   Independent load tracking per tenant.
*   Automatic load balancing across Ingesters.
*   Complete isolation at query layer.

---

## ⚠️ Trade-offs & Limitations

| Limitation | Description | Mitigation |
| :--- | :--- | :--- |
| **Metric Name Required** | Hashing scheme requires all queries to specify metric name. | Planned improvement (later versions). |
| **Ingester Data Loss** | If Ingester crashes before flush, ~1 hour of data is lost. | Implement **Write-Ahead Log (WAL)**. |
| **DynamoDB Cost** | Expensive for high write throughput. | Switch to Cassandra for large deployments. |

---

## 📊 Operational Metrics

| Metric | Target |
| :--- | :--- |
| **Ingestion Rate** | 10M+ samples/sec |
| **Query Latency (Recent)** | < 100ms (in-memory) |
| **Query Latency (Historical)** | < 5s (with caching) |
| **Retention** | Infinite (cloud storage) |
| **Tenant Density** | Thousands per cluster |

---

## ✅ Principal Architect Checklist

1.  **Use Remote Write**: Don't fight Prometheus—extend it. Keep Prometheus as the scraper.
2.  **Design for Statelessness**: All Cortex components should be stateless. State lives in S3/DynamoDB.
3.  **Plan for Ingester Failures**: Implement WAL or accept 1-hour data loss window.
4.  **Cache Aggressively**: Memcached is critical for query performance at scale.
5.  **Size Ingesters for Memory**: Each Ingester buffers ~1 hour of data in RAM. Plan capacity.
6.  **Monitor Tenant Cardinality**: High-cardinality tenants can hotspot Ingesters. Track per-tenant series count.

---

## 📖 Analogy: The Global Banking Vault

> [!TIP]
> Standard Prometheus is like a **personal filing cabinet** in your home:
> *   Easy to use, but limited space.
> *   If your house burns down, records are lost.
>
> **Cortex** is like a **global banking vault**:
> *   Records (samples) are assigned a specific security box based on your ID (Distributor/hashing).
> *   Documents stored in a massive, infinite underground warehouse (S3).
> *   Thousands of people use the same vault, but **security guards** (multi-tenancy) ensure you only see your own boxes.

---

## 🔗 Related Documents
*   [Multi-Tenancy with Spring](multi-tenancy-spring.md) — Application-level multi-tenancy
