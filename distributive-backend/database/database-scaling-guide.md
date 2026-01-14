# Database Scaling: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Vertical vs Horizontal Scaling, Sharding, Read Replicas, and NewSQL.

> [!IMPORTANT]
> **The Scaling Ladder**:
> 1. **Optimize Queries** (Indexing, EXPLAIN ANALYZE).
> 2. **Vertical Scaling** (Bigger machine).
> 3. **Read Replicas** (Separate Read/Write).
> 4. **Horizontal Sharding** (Distribute data).
> Most applications never need to go past Step 3.

---

## 📈 The Scaling Ladder

### Step 1: Optimize Before Scaling
Before adding hardware, fix your queries.
*   **Index Your WHERE Clauses**: No full table scans.
*   **Use `EXPLAIN ANALYZE`**: Understand query plans.
*   **Connection Pooling**: Use PgBouncer (Postgres) or ProxySQL (MySQL).

### Step 2: Vertical Scaling
*   **What**: Buy a bigger server (more RAM, faster CPU, NVMe SSD).
*   **Limit**: Eventually you hit the biggest machine available.
*   **Use Case**: Simpler than sharding. Works for most SaaS apps up to 1TB.

### Step 3: Read Replicas
*   **What**: Offload read traffic to replica databases.
*   **Architecture**: Primary (Writes) → Replica 1 (Reads), Replica 2 (Reads).
*   **Trade-off**: **Replication Lag**. Reads may be slightly stale.
*   **Use Case**: Read-heavy workloads (E-commerce product pages).

### Step 4: Horizontal Sharding
*   **What**: Split the dataset across multiple database servers.
*   **Methods**:
    *   **Range Sharding**: User ID 1-1M → Shard 1. User ID 1M-2M → Shard 2. (Risk: Hotspots on newest shard).
    *   **Hash Sharding**: `hash(user_id) % num_shards`. (Even distribution, but resharding is painful).
    *   **Directory-Based**: A lookup table maps key → shard. (Flexible, but the directory is a single point of failure).

---

## ⚔️ Sharding: The Trade-offs

| Benefit | Cost |
| :--- | :--- |
| Infinite horizontal scale. | Cross-shard joins are impossible (or very expensive). |
| Fault isolation. | Resharding requires data migration. |
| Geo-locality (shard per region). | Application must be shard-aware. |

---

## 🆕 NewSQL: The Best of Both Worlds

NewSQL databases provide the scalability of NoSQL with the ACID guarantees of SQL.

| Database | Key Feature |
| :--- | :--- |
| **CockroachDB** | Survives datacenter failures. Postgres-compatible. |
| **Vitess** | MySQL-compatible sharding proxy (used by YouTube). |
| **TiDB** | MySQL-compatible. Hybrid OLTP + OLAP. |
| **Google Spanner** | Globally distributed with TrueTime. |

---

## 🏛️ Principal Pattern: "Logical Sharding"

Before you *physically* shard, add a `shard_key` to your tables.
```sql
-- Add shard_key NOW, shard LATER
CREATE TABLE orders (
    id BIGSERIAL,
    shard_key INT NOT NULL, -- e.g., customer_id % 256
    customer_id BIGINT,
    total DECIMAL(10, 2),
    PRIMARY KEY (shard_key, id)
);
```
*   **Benefit**: When you eventually need to shard, you already have the key baked in. Migration is straightforward.

---

## ✅ Principal Architect Checklist

1.  **Don't Shard Prematurely**. You probably don't need it until 1TB+.
2.  **Choose a Good Shard Key**: High cardinality, evenly distributed, rarely changes (e.g., `customer_id`, `tenant_id`).
3.  **Avoid Cross-Shard Operations**: Design your data model so that related data lives on the same shard.
4.  **Plan for Resharding**: Your sharding strategy WILL need to change. Use consistent hashing or Vitess.
5.  **Consider NewSQL**: CockroachDB or TiDB might be simpler than sharding MySQL.

---

## 📚 Sources
*   [Database Scaling (Stripe)](https://www.youtube.com/watch?v=v1zD4zW5rBs)
*   [Vitess at YouTube](https://www.youtube.com/watch?v=z7a2mBVBjP4)
*   [Postgres at Scale (Instagram)](https://www.youtube.com/watch?v=EfMIWTnbhGw)
*   [NewSQL Databases](https://www.youtube.com/watch?v=4TE1xErXwGc)
