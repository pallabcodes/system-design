Resource: https://youtu.be/K-fI2BeTLkk

# Uber's Trillion-Event Infrastructure: The "God Mode" Architecture Guide

> **Level**: Principal Architect / Distinguished Engineer
> **Scope**: Hyper-Scale Streaming, Reliability Engineering, and Distributed Auditing.

> [!IMPORTANT]
> **The Principal Law**: **At Scale, "Exactly Once" is a Cost Function, not a Guarantee.**
> You can have low latency, or you can have zero data loss. You cannot have both. Uber's architecture explicitly bifurcates these:
> *   **Rider Coords**: "Fire and Forget" (High Throuput, Data Loss OK).
> *   **Payments**: "Synchronous ACK" (High Latency, Zero Data Loss).

> **The Scale**: 1 Trillion Messages/Day. 10M+ Msg/Sec. Petabytes/Day.

---

## 🏛️ The Core Problem: The "Polyglot" Nightmare

Standard Kafka guides say "Use the Java Client".
**The Reality**: Uber had 3000+ microservices written in Go, Python, Node.js, and C++.
**The Failure Mode**: Maintaining high-performance, threat-safe, updated Kafka libraries for 5 languages is an operational suicide mission.

### The Solution: The "Dumb Pipe" (REST Proxy)
Instead of smart clients, Uber built a massive **REST Proxy** layer.
*   **Protocol**: HTTP/1.1 (Universal).
*   **Format**: Binary (Avro) embedded in HTTP.
*   **The Hack**: **Kill the Framework**.
    *   They started with Confluent's REST Proxy (Jersey/JaxRS).
    *   **Bottleneck**: Object allocation and Reflection in Java frameworks killed performance at 10M RPS.
    *   **God Mode Optimization**: They rewrote it using **Raw Servlet API**.
    *   **Result**: 7k RPS -> **30k RPS** per node.

---

## ⚡ God Mode: The Reliability Pattern (The "Local Agent")

What happens when the Kafka Cluster dies?
*   **Junior Dev**: "The app throws an exception."
*   **Senior Dev**: "The app retries 3 times."
*   **Principal Architect**: "The app writes to the local disk, because the network is a lie."

### The "Local Agent" Pattern (Pre-Kubernetes Sidecar)
Every single host at Uber ran a lightweight **Local Agent** (Go/C++).
1.  **Happy Path**: App -> Load Balancer -> REST Proxy -> Kafka.
2.  **Sad Path**: REST Proxy returns 503.
3.  **Survive**: App -> **Local Agent (localhost)** -> Local Disk (WAL).
4.  **Recovery**: Local Agent tails the disk file and pushes to Kafka when online.

> [!TIP]
> This is effectively the **"Dead Letter Queue"** pushed to the extreme edge (the client's machine).

---

## 🔄 Distributed Replication: The "uReplicator" Invention

Uber's biggest contribution to the Kafka ecosystem was fixing **MirrorMaker**.

### The Problem: Rebalancing Storms
*   **MirrorMaker 1**: Standard high-level consumer.
*   **Scenario**: You have 10,000 topics. You add 1 node.
*   **Result**: The "Stop-the-World" Rebalance. All consumers stop. Partitions are reshuffled. Latency spikes to **15 minutes**.

### The Solution: uReplicator (Federated Controller)
*   They ditched the High-Level Consumer.
*   **Controller**: Uses **Apache Helix** to assign specific partitions to specific workers.
*   **Worker**: "I am assigned partitions [0-50]. I explicitly fetch them. I do not join a consumer group."
*   **Impact**: Adding a node moves *only* the necessary partitions. **Zero downtime.**

```mermaid
graph LR
    subgraph "West Coast (Source)"
        KafkaW[Kafka West]
    end

    subgraph "The Bridge (uReplicator)"
        Helix[Helix Controller]
        W1[Worker 1 (Partitions 0-100)]
        W2[Worker 2 (Partitions 101-200)]
        
        Helix -->|Assign| W1
        Helix -->|Assign| W2
    end
    
    subgraph "East Coast (Aggregate)"
        KafkaE[Kafka Agg]
    end

    KafkaW -->|Fetch| W1
    KafkaW -->|Fetch| W2
    W1 -->|Produce| KafkaE
    W2 -->|Produce| KafkaE

    style Helix fill:#f96,stroke:#333
```

---

## 🔍 The "Chaperone": Trust But Verify

At 1 Trillion events, how do you know you lost 0.0001%?
You cannot rely on TCP ACKs. You need **Application-Level Auditing**.

### The Chaperone Architecture
1.  **Tagging**: Every message gets a `Creation-Timestamp` and `Tier` (Critical/Non-Critical).
2.  **Audit Trail**:
    *   Client emits: `(TopicA, Count: 100, T1)`
    *   Proxy emits: `(TopicA, Count: 99, T1)` -> **ALERT (Data Loss)**
    *   Kafka emits: `(TopicA, Count: 99, T1)`
3.  **Dedup**: Chaperone aggregates these stats in a secondary database (MySQL/Cassandra) to produce "Loss Reports".

---

## ⚖️ Critical Matrix: "No One Size Fits All"

Uber separates traffic into **Traffic Tiers**.

| Tier | Example | Latency | Durability | Strategy |
| :--- | :--- | :--- | :--- | :--- |
| **P0 (Critical)** | Payments, Fraud | High (ok) | **Extreme** | Sync Send, `acks=all`, 3-Replica Min |
| **P1 (Standard)** | Surge Pricing | Low | High | `acks=1`, Async Batching |
| **P2 (Log)** | App Logs | **Lowest** | Low | `acks=0`, Fire & Forget, Aggressive Drop |

---

## 🔮 The Modern Perspective (2025 Update)

If we rebuilt Uber's infrastructure today, 5 years later, what changes?

### 1. The Death of the REST Proxy -> Service Mesh
In 2016, we needed a REST Proxy because clients were fragmented.
*   **Today**: We use **Envoy Proxy** with the **Kafka Filter**.
*   **Why**: Envoy runs as a sidecar. It speaks Kafka Protocol native. No need for a custom HTTP->Kafka bridge. The efficiency is built into C++ Envoy.

### 2. The Death of uReplicator -> MirrorMaker 2
uReplicator was great. But the community caught up.
*   **Legacy**: MirrorMaker 1 (Scala/High-level consumer).
*   **Modern**: **MirrorMaker 2** (Built on Kafka Connect framework).
*   **Why**: It handles offset translation (Active/Active) and "rebalancing" cleanly using the Connect worker model.

### 3. Tiered Storage (The Cost Saver)
Uber ran thousands of HDD brokers.
*   **Today**: **KIP-405 (Tiered Storage)**.
*   **Architecture**: Local Brokers hold 4 hours of data (NVMe). Historical data offloads to **S3/GCS** transparently.
*   **Impact**: 70% Cost Reduction. "Infinite" retention topics.

### 4. WarpStream / BYOC
*   **New Paradigm**: Separation of Compute and Storage.
*   **Effect**: Using S3 as the *primary* storage (like **WarpStream** or **Confluent Cloud Freight**). This eliminates the need for "Rebalancing" entirely, as brokers are stateless.

---

## 🏁 Conclusion

Uber's architecture teaches us that **General Purpose = Mediocre**.
To process Trillions, they specialized:
1.  **Specialized Protocols**: Raw Servlets over Jersey.
2.  **Specialized Consumers**: Helix-managed workers over Consumer Groups.
3.  **Specialized Tiers**: Tuning `acks` per topic.

Principal Engineers don't just "install Kafka". They turn the knobs until the engine screams.