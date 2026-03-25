# Logging at Scale: A Case Study (Shopify)

> **Source**: Shopify Engineering (Daniel Oliveira) - "Replacing a Vendor with a Custom Pipeline"

> [!IMPORTANT]
> **The Scale**: 46 GB/sec. 26 Million log lines/sec.
> **The Win**: Built a custom pipeline that handles **3x the volume** at **50% of the cost** of the previous vendor.

---

## 📊 Pipeline Architecture

![Shopify Logging Pipeline](assets/shopify-pipeline.png)

```mermaid
graph LR
    subgraph "Collection Layer"
        Pod1[Pod 1] --> VF1[Vector Sidecar]
        Pod2[Pod 2] --> VF2[Vector Sidecar]
        Pod3[Pod N] --> VFN[Vector Sidecar]
    end

    subgraph "Aggregation Layer"
        VF1 --> VA[Vector Aggregator]
        VF2 --> VA
        VFN --> VA
        VA -->|Enrich with K8s metadata| VA
    end

    subgraph "Ingestion Layer"
        VA --> API[Log API - Schema-less]
        VA --> Kafka[(Kafka - High Volume)]
    end

    subgraph "Storage Layer"
        API --> CH[(ClickHouse)]
        Kafka --> CH
    end

    style VF1 fill:#ffe6cc,stroke:#d79b00
    style VA fill:#dae8fc,stroke:#6c8ebf
    style CH fill:#d5e8d4,stroke:#82b366
```

---

## 🏗️ Architecture Stack

A custom-built pipeline relying on high-performance open-source tools.

| Layer | Technology | Function |
| :--- | :--- | :--- |
| **Collection** | **Vector** (Sidecars) | Runs on every node/pod. Collects via file system or JournalD. |
| **Transport** | **Vector Aggregators** | Batches data, enriches with K8s metadata. |
| **Ingestion** | **Log API** (Custom) | Schema-less entry point. Handles JSON Ingestion. |
| **Buffer** | **Kafka** | Used for specific high-volume streams (Nginx). |
| **Storage** | **ClickHouse** | Columnar store. High compression, standard 30-day retention. |

---

## 🚀 Key Design Decisions

### 1. The Power of Vector
Shopify leans heavily on **Vector** (by Datadog) and its **VRL (Vector Remap Language)**.
*   **Why?**: VRL allows extremely fast, safe transformation of logs (parsing routes, scrubbing fields) at the edge, reducing downstream load.

### 2. Schema-less Ingestion
*   **Approach**: The custom Log API accepts *any* JSON.
*   **Trade-off**: Flexibility vs Query Performance. ClickHouse handles the JSON columns efficiently enough for their search patterns.

### 3. Cost-Driven Engineering
*   **Problem**: "Junk" logs cost millions at this scale.
*   **Solution**: **Cost Attribution**. The platform shows every team exactly how much their logs cost ($), incentivizing them to delete noisy `DEBUG` logs.

---

## ⚠️ Challenges of "Shopify Scale"

### 1. Open Source Limits
> "Industry-Standard tools often break at this volume."
Shopify teams frequently have to patch or reconfigure OSS tools because default assumptions (buffer sizes, connection pools) collapse under **26M events/second**.

### 2. Testing is Impossible
You cannot spin up a "Staging" environment that mimics 46GB/sec traffic without doubling your cloud bill.
*   **Strategy**: Fast iteration + Canary deployments + Feedback from internal power users (SREs).

---

## 📊 Operational Metrics

| Metric | Value |
| :--- | :--- |
| **Ingestion Rate** | 46 GB/sec (26M lines/sec) |
| **Infrastructure** | ~5,000 CPUs, 40 TB RAM |
| **Retention** | 30 days (default), some datasets 1+ year |
| **Cost vs Vendor** | 50% cheaper, 3x more volume |
| **Latency (Log to Search)** | < 2 minutes |

---

## ✅ Principal Architect Checklist

1.  **Adopt Vector**: VRL (Vector Remap Language) allows safe, fast transformation at the edge. This reduces downstream load and enables field scrubbing before storage.
2.  **Implement Cost Attribution**: Show each team their $ cost for logs. This incentivizes deleting `DEBUG` noise. At 46GB/sec, "junk" logs cost millions.
3.  **Accept Testing Limits**: You cannot replicate 46GB/sec in staging. Use **Canary deployments** + **Internal Power Users (SREs)** for validation.
4.  **Expect OSS to Break**: Default buffer sizes, connection pools, and thread limits in tools like Vector/Kafka collapse at this scale. Budget engineering time for tuning and upstreaming patches.
5.  **Use Schema-less Ingestion Carefully**: Flexibility is good, but query performance on JSON columns in ClickHouse degrades with complexity. Monitor query latency.
6.  **Multi-Cluster Topology**: Spread load across clusters to limit "blast radius" of failures.

---

## 🧩 Analogy: The Metropolitan Postal Service

> [!TIP]
> **The Architecture Explained**:
> *   **Services**: Citizens writing letters.
> *   **Vector Forwarders**: **Collection Boxes** on every street corner (Node).
> *   **Vector Aggregators**: **Local Sorting Facilities** that Bundle mail and stamp it with "District Info" (Metadata).
> *   **ClickHouse**: The **Massive Automated Warehouse** where mail is stored on shelves.
> *   **Resilience**: If a truck breaks down, mail goes to a **Holding Area** (Kafka/Queue), ensuring that even in a blizzard (Flash Sale), nothing is lost.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
This is actually a very modern architecture (Vector + ClickHouse). It represents the current "Post-ELK" (Elasticsearch, Logstash, Kibana) standard. **Vector** (written in Rust) has replaced Fluentd/Logstash for performance, and **ClickHouse** has replaced Elasticsearch for log storage due to superior compression and cost.

**Is it scalable?**
**Yes.** This architecture is specifically designed to solve the scalability limits of previous generations.

**What would the architecture look like today?**
**It looks like this.**
*   **Minor tweaks:** We might use **OpenTelemetry** collectors instead of pure Vector if we want a vendor-neutral standard, but Vector is often preferred for raw performance.
*   **Storage:** We might use **S3** with a query engine (like **Quickwit** or **Loki** with object storage) if ClickHouse SSD costs become too high for long retention, but for "hot/warm" logs, ClickHouse is still king.

## Principal Architect's Q&A

**Q: Is "Logstash" dead?**

**A:** Mostly, yes. It's too heavy (JVM).
1.  **Vector/FluentBit**: Use **Vector** (Rust) or **FluentBit** (C). They consume 1/10th the RAM of Logstash.
2.  **OpenTelemetry**: The future is OTel Collectors. They are vendor-neutral. Vector supports OTel.
3.  **ClickHouse vs Elastic**: Elasticsearch is great for "Relevance" (Search). ClickHouse is great for "Aggregation" (Logs). For logs, you mostly want "Count errors grouped by service". ClickHouse is 10x faster and cheaper for this than Elastic (Lucene).


## Principal Architect's Q&A

**Q: Is "Logstash" dead?**

**A:** Mostly, yes. It's too heavy (JVM).
1.  **Vector/FluentBit**: Use **Vector** (Rust) or **FluentBit** (C). They consume 1/10th the RAM of Logstash.
2.  **OpenTelemetry**: The future is OTel Collectors. They are vendor-neutral. Vector supports OTel.
3.  **ClickHouse vs Elastic**: Elasticsearch is great for "Relevance" (Search). ClickHouse is great for "Aggregation" (Logs). For logs, you mostly want "Count errors grouped by service". ClickHouse is 10x faster and cheaper for this than Elastic (Lucene).

