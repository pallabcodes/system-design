# Kafka at Scale: Reliability & Operations

> **Source**: [Uber's Kafka Engineering](https://youtu.be/xsdoQkoao2U), [Confluent: Production Failures](https://youtu.be/1vLMuWsfMcA)

> [!IMPORTANT]
> **The Paradox**: Kafka is optimized for **Streaming** (Ordering, Throughput), but engineers often abuse it for **Queuing** (Blocking work, Retries).
> **The Result**: Head-of-Line Blocking. If Message A fails, Message B (which is fine) waits.

---

## 🏛️ Part 1: The Uber Architecture (Reliable Reprocessing)

How do you handle failures without stopping the stream? Use a **Leveled Retry Architecture**.

### The "Queue on Stream" Pattern

![Uber Reliable Reprocessing Architecture](assets/uber-retry.png)

You cannot use Kafka like SQS. You cannot "leave a message on the topic" while you retry. You must **commit** to move forward.

```mermaid
graph LR
    Produce[Producer] --> MainTopic[Main Topic]
    
    subgraph "Consumer Group"
        MainConsumer[Consumer]
    end
    
    MainTopic --> MainConsumer
    
    MainConsumer --"Success"--> Commit[Commit Offset]
    MainConsumer --"Fail (Network)"--> Retry1[Retry Topic (1m Delay)]
    
    Retry1 --"Wait 1m"--> RetryConsumer[Retry Consumer]
    RetryConsumer --"Fail Again"--> DLQ[DLQ Topic]
    
    DLQ -->|Manual Inspection| Admin[Dev Tooling]
    Admin --"Republish"--> MainTopic
```

1.  **Non-Blocking**: If `msg_1` fails, produce it to `retry_topic` and **commit** `msg_1` on `main_topic`. The stream continues.
2.  **Leveled Delays**:
    *   `retry-1m`: Consumer checks timestamp. If `now < msg.timer`, pause.
    *   `retry-10m`: For persistent failures.
    *   `DLQ`: The graveyard.
3.  **No Data Loss**: At-Least-Once guarantees mean you *will* have duplicates. Your consumer **must be Idempotent**.

---

## 🔧 Part 2: Operational Scars (The "Don't Do This" List)

Running Kafka at scale (Petabytes/day) reveals 3 deadly sins.

### 1. The "ISR Shrink" (Version Mismatch)
*   *Scenario*: You upgrade Broker A to Kafka 3.0. Broker B and C are on 2.8.
*   *Mechanism*: Kafka 3.0 has a faster replication protocol. Broker A (Leader) writes faster than B/C (Followers) can copy.
*   *Result*: B and C fall out of the **In-Sync Replica (ISR)** list.
*   *Output*: **Data Loss Risk**. If A crashes, B/C are missing data.

### 2. Automation is a Sharp Knife
*   *Scenario*: script `check-health.sh` pings port 9092.
*   *Mechanism*: A generic switch blip causes a 1-second timeout.
*   *Result*: The script assumes the broker is dead and `term`s the process. It does this to *all* brokers.
*   *Recovery*: Restarting a broker with 20,000 partitions takes **20 minutes** (loading index files). You caused a 1-hour outage for a 1-second blip.

### 3. The "Stage vs Prod" Migration
*   *Scenario*: Using `kafka-reassign-partitions` to move data.
*   *Failure*: Staging has 100 partitions. Prod has 100,000.
*   *Result*: The movement plan saturates the NIC (Network Interface) of the Leader. Produciton traffic (Rides/Food) is dropped because the bandwidth is used for "rebalancing".

---

## 💾 Streaming Mechanics: The Immutable Log

Kafka is not a database. It is a **Log**.

| Feature | Database | Kafka (Log) |
| :--- | :--- | :--- |
| **Write** | Insert/Update | Append Only |
| **Read** | Query (Random Access) | Scan (Sequential) |
| **Delete** | `DELETE FROM` | Compaction (Keep Key's last value) |
| **Scale** | Sharding (Hard) | Partitioning (Native) |

> [!TIP]
> **Forward Compatibility**: New services (e.g., "Fraud Detection") can replay the *entire history* of the `bookings` topic to train their models without impacting the "Booking Service". This is the superpower of the Log.

---

## ✅ Principal Architect Checklist

1.  **Separate Queuing from Streaming**: If you need individual message tracking (ACK/NAK), build the **Uber Pattern** (Retry Topics). Do not block the partition.
2.  **Monitor ISR**: Alert immediately if `ISR < ReplicationFactor`. This is your "Defcon 1".
3.  **Idempotency is Mandatory**: `At-Least-Once` + `Network Failure` = `Duplicates`. Your DB updates must be `INSERT IGNORE` or `UPSERT`.
4.  **Bulkheads for Topics**: Do not put "High Volume / Low Value" logs on the same brokers as "Low Volume / High Value" financial transactions. Isolate the workloads.

---

## 🔗 Related Documents
*   [Resiliency Patterns](../../cicuit-breaker/resiliency-patterns-guide.md) — Circuit breakers to prevent cascading Kafka failures.
*   [Event Sourcing](../../event-drive-microservices/event-sourcing/event-sourcing-guide.md) — Utilizing the Immutable Log for state.
