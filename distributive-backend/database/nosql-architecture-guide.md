# NoSQL Architecture: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: LSM Trees, Bloom Filters, CAP Theorem implementation.

> [!IMPORTANT]
> **The Principal Law**: **NoSQL means "Not Only SQL"**. It generally trades **ACID** implementation complexity for **Write Throughput** and **Horizontal Scaling**.

---

## 🚀 LSM Trees (Log Structured Merge)
Used by: Cassandra, RocksDB, LevelDB, DynamoDB.

### The Algorithm (Write Optimized)
1.  **MemTable**: Write data to in-memory Red-Black Tree. (Fast).
2.  **SSTable (Sorted String Table)**: When MemTable is full, flush to disk as an immutable file.
3.  **Compaction**: Background process merges small SSTables into larger ones to remove duplicates/deleted keys.

**Advantage**: Writes are always Sequential IO. No random disk jumps.
**Disadvantage**: Reads are slower (might have to check MemTable + 5 SSTables).

### Bloom Filters (The Read Optimizer)
How do we know which SSTable has key "User:123" without reading all of them?
*   **Bloom Filter**: A probabilistic data structure.
*   Asks: "Is Key X definitely NOT in this file?"
*   Response: "Definitely No" (Skip file) or "Maybe Yes" (Check file).
*   **Impact**: Saves 90% of disk lookups.

---

## 🗺️ Data Models & Use Cases

### 1. Key-Value (Redis, DynamoDB)
*   **Model**: Hash Map.
*   **Use Case**: User Sessions, Caching, Shopping Carts.
*   **Anti-Pattern**: Complex querying (Joins).

### 2. Wide Column (Cassandra, HBase)
*   **Model**: Two-dimensional Key-Value. `RowKey -> {Col1: Val1, Col2: Val2}`.
*   **Use Case**: Time series, IoT, Write-heavy logs.
*   **Modeling Rule**: **Query-First Design**. You design the table to fit the exact query. `SELECT * FROM messages WHERE room_id = X`.

### 3. Document (MongoDB)
*   **Model**: JSON.
*   **Use Case**: Content Management, Flexible Schema.
*   **Warning**: Schema validation is now the Application's responsibility.

---

## ✅ Principal Architect Checklist

1.  **Hot Partitions**: In DynamoDB/Cassandra, if everyone writes to `PartitionKey="Today"`, you burn out one node while others sleep. Use randomness/sharding suffixes.
2.  **Tombstones**: Deletes in LSM trees are just "Markers". They don't free space until compaction. Massive deletes = Slow reads.
3.  **Eventual Consistency**: Understanding `R + W > N` (Quorum). If you write to 1 node (`W=1`) and read from 1 node (`R=1`) in a 3-node cluster, you **will** see stale data.

---

## 🔗 Related Documents
*   [RDBMS Internals](./rdbms-internals-guide.md) — The read-optimized alternative.
*   [Sharding Guide](../../../../sharding-techniques-and-notes/sharding-architecture-guide.md) — How NoSQL manages partitions.
