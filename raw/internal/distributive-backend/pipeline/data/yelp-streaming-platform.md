# Yelp's Real-Time Streaming Platform (Flink & Kafka)

> **Source**: [Yelp's Evolution to Flink](https://youtu.be/CmBP5bUd2OU)

> [!IMPORTANT]
> **Key Innovation**: The **"Connector Ecosystem"**.
> Instead of writing custom pipelines for every destination, Yelp built generic **Flink Connectors** (Cranes) that move data from Kafka to Redshift/Cassandra/etc with built-in **Auditing** (Consistency Checks).

---

## 📜 The Evolution
*   **Phase 1 (Scribe)**: Log aggregation (Files tailed over TCP). Fragile.
*   **Phase 2 (Storm)**: Attempted for real-time. Failed due to infrastructure complexity.
*   **Phase 3 (The Backbone)**: **Kafka** + **Schematizer** (Avro Registry).
*   **Phase 4 (Stream Processing)**:
    *   **Spark**: Used for Micro-batching.
    *   **Flink**: Chosen for **Stateful** stream processing and **Low Latency**.

---

## 📊 Architecture Diagram

![Yelp Streaming Platform](assets/yelp-streaming-platform.png)

```mermaid
graph LR
    subgraph "Ingestion"
        App[Python App] --> Monk[Monk Sidecar]
        Monk --> Kafka[(Kafka)]
    end

    subgraph "Schema Management"
        Kafka --> Schema[Schematizer - Avro Registry]
    end

    subgraph "Processing"
        Kafka --> Flink[Flink Connector]
        Flink --> Auditor[Auditor - Count Verification]
    end

    subgraph "Sinks"
        Flink --> Redshift[(Redshift)]
        Flink --> Cassandra[(Cassandra)]
        Flink --> S3[(S3)]
    end

    Auditor -->|Compare Counts| Kafka
    Auditor -->|Compare Counts| Redshift

    style Monk fill:#ffe6cc,stroke:#d79b00
    style Schema fill:#dae8fc,stroke:#6c8ebf
    style Flink fill:#d5e8d4,stroke:#82b366
    style Auditor fill:#f8cecc,stroke:#b85450
```

---

## 🏗️ Architecture Components

### 1. Ingestion: The "Monk" Sidecar
How do you get logs from Python web apps to Kafka without blocking user requests?
*   **Monk**: A local daemon running on *every* host.
*   **Flow**: App -> Local Monk (Memory) -> Kafka.
*   **Benefit**: If Kafka is down, Monk buffers locally. The App is never blocked.

### 2. The "Schematizer" (The Brain)
*   **Role**: Central Schema Registry (Avro).
*   **Function**: Controls topic location, evolution rules, and ensures compatibility.

### 3. Flink vs "PastaStorm" (Legacy)
Yelp tried building a Python wrapper around Kafka ("PastaStorm"). It failed because:
*   **State Management**: Handling Window Joins in Python led to corrupted state.
*   **Rebalancing**: Python consumers "thrashed" during Kafka rebalances.
*   **Solution**: **Flink** handles State (RocksDB), Checkpointing, and Event Time natively.

---

## 🔌 The Connector Ecosystem
Yelp treats data movement as a **Platform**, not a script.
*   **Generic Connectors**: A single Flink App moves data from *Any* Topic to *Any* Sink (e.g., Kafka -> Redshift).
*   **The Auditor**: A side-process that verifies data integrity. It counts records in Kafka vs. Redshift to detect data loss or duplication.

---

## 📊 Operational Considerations

| Aspect | Detail |
| :--- | :--- |
| **State Size** | Tens of GBs for window joins. Use RocksDB (disk-backed). |
| **Checkpointing** | Incremental checkpoints to S3. Metadata in DynamoDB (S3 list is inconsistent). |
| **Deployment** | Flink on AWS EMR. Python "Flink Supervisor" for restarts/alerting. |
| **Stability Hack** | Disable Yarn physical/virtual memory checks. Let OS OOM Killer handle issues. |

---

## ✅ Principal Architect Checklist

1.  **Use a Sidecar for Ingestion**: The "Monk" pattern buffers logs locally. If Kafka is down, the App is never blocked. This is critical for user-facing services.
2.  **Centralize Schema Registry**: The "Schematizer" (Avro registry) controls topic allocation and schema evolution. This prevents incompatible changes from breaking consumers.
3.  **Don't Build Python Stream Processors**: Yelp's "PastaStorm" (Python Kafka wrapper) failed due to corrupted state and rebalance thrashing. Use Flink for stateful stream processing.
4.  **Build Generic Connectors**: Instead of N custom pipelines, build 1 Flink app that moves data from *any* Topic to *any* Sink. Pass configuration, not code.
5.  **Audit Everything**: The "Auditor" counts records in Kafka vs. the destination. Without this, you won't know about data loss or duplication until it's too late.
6.  **Streaming SQL for Onboarding**: Yelp provides a "Streaming SQL" service where users submit YAML + SQL. This abstracts Flink entirely, lowering the barrier for non-Java teams.

---

## ⚓ Analogy: The International Shipping Port

> [!TIP]
> **Understanding Generic Connectors**:
> *   **Kafka Topics** = **Ships** arriving with containers.
> *   **Destinations (Redshift)** = **Factories** needing goods.
> *   **Old Way**: Every factory sends a custom truck (Script) to the dock. Chaos.
> *   **New Way (Connectors)**: The Port provides **Standardized Cranes**.
>     *   The Crane doesn't care what's inside the container.
>     *   It just moves it safely from Ship to Factory.
>     *   **The Auditor** is the **Checklist Manager** standing by the crane, counting every container to ensure none fell into the ocean.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
The move from Storm to **Flink** was the defining moment of modern streaming. This architecture is effectively *current*. Use of "Schematizer" (Avro Registry) and "Fink Connectors" is still best practice.

**Is it scalable?**
**Yes.** Flink is the gold standard for stateful streaming at scale.

**What would the architecture look like today?**
1.  **Flink SQL / Table API:** Instead of writing Java code for "Connectors," modern platforms emphasize **Flink SQL**. You define the source/sink in SQL, and Flink handles the movement.
2.  **Data Lakehouses:** The sink might not be Redshift/Cassandra directly. We often sink to **Apache Iceberg**, **Hudi**, or **Delta Lake** on S3. These open table formats allow transactional updates on the data lake, serving as both the warehouse and the real-time sink.
3.  **K8s Operator:** Deployment on "AWS EMR" with "Supervisor scripts" is legacy. Today, we run Flink on Kubernetes using the official **Flink Kubernetes Operator** for native autoscaling and recovery.

## Principal Architect's Q&A

**Q: Why is Flink winning over Spark Streaming?**

**A:** **Latency** and **State**.
1.  **True Streaming**: Spark Streaming is "Micro-batch" (latency > 5s). Flink is "Row-at-a-time" (latency < 10ms).
2.  **State Management**: Flink's **RocksDB** state backend is a masterpiece. It allows you to hold TBs of state (e.g., "User's session history for last 30 days") and access it instantly. Spark struggles with massive state.
3.  **Correctness**: Flink handles "Late Data" using Watermarks correctly. It's the only engine that genuinely solves the "Event Time vs Processing Time" problem at scale.


## Principal Architect's Q&A

**Q: Why is Flink winning over Spark Streaming?**

**A:** **Latency** and **State**.
1.  **True Streaming**: Spark Streaming is "Micro-batch" (latency > 5s). Flink is "Row-at-a-time" (latency < 10ms).
2.  **State Management**: Flink's **RocksDB** state backend is a masterpiece. It allows you to hold TBs of state (e.g., "User's session history for last 30 days") and access it instantly. Spark struggles with massive state.
3.  **Correctness**: Flink handles "Late Data" using Watermarks correctly. It's the only engine that genuinely solves the "Event Time vs Processing Time" problem at scale.

