# Database Scaling: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ DBA
> **Scope**: Sharding, Consistent Hashing, Vitess, CockroachDB — With Hotspot Mitigation and Production Patterns

> [!CAUTION]
> **The Cardinal Sin**: Sharding prematurely. 90% of applications will never need horizontal sharding. Vertical scaling + read replicas gets you to 1TB+.

---

## 📚 Required Reading

| Resource | Topic |
| :--- | :--- |
| [Dynamo Paper](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf) | Consistent hashing |
| [Vitess Architecture](https://vitess.io/docs/overview/architecture/) | MySQL sharding |
| [CockroachDB Architecture](https://www.cockroachlabs.com/docs/stable/architecture/overview.html) | Distributed SQL |
| [YouTube: Scaling Databases at Stripe](https://www.youtube.com/watch?v=dO0dqc3MNvM) | Real-world sharding |

---

## 🎯 The Principal Laws of Scaling

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Premature Sharding is Evil** | Sharding adds complexity, not just capacity | Exhaust vertical scaling first |
| **Law 2: Shard Key is Forever** | Changing shard key = full migration | Choose wisely on day 1 |
| **Law 3: Cross-Shard = Death** | Joins across shards are distributed txns | Co-locate related data |
| **Law 4: Hotspots Kill** | All traffic to one shard = bottleneck | Design for even distribution |

---

# Part 1: The Scaling Ladder

## Step 0: Optimize Before Scaling (Free)
```sql
-- 1. Index your WHERE clauses
CREATE INDEX idx_orders_customer_status 
ON orders(customer_id, status, created_at DESC);

-- 2. EXPLAIN ANALYZE every slow query
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;

-- 3. Connection pooling
-- PgBouncer: 50 app connections → 10 DB connections
[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
```

## Step 1: Vertical Scaling ($)
```
Before:  8 vCPU, 32GB RAM, 500GB SSD
After:   96 vCPU, 768GB RAM, 8TB NVMe

Cost: ~$5K/month → ~$50K/month
Capacity: 10x improvement is typical

When to stop:
- Largest cloud instance isn't enough
- Network bandwidth is bottleneck
- You need geographic distribution
```

## Step 2: Read Replicas ($$)
```
        Writes
           │
           ▼
      ┌─────────┐
      │ Primary │
      └────┬────┘
           │ Async Replication
    ┌──────┼──────┐
    ▼      ▼      ▼
 Replica  Replica  Replica
    │      │      │
    ▼      ▼      ▼
   Reads  Reads  Reads

Caveat: Replication lag (eventual consistency)
Solution: Read-your-writes with LSN tracking
```

### Connection Routing (PostgreSQL)
```python
# Using libpq target_session_attrs
import psycopg2

# Writes: Connect to primary
write_conn = psycopg2.connect(
    "host=primary,replica1,replica2 target_session_attrs=read-write"
)

# Reads: Connect to any
read_conn = psycopg2.connect(
    "host=primary,replica1,replica2 target_session_attrs=any"
)
```

## Step 3: Horizontal Sharding ($$$)
```
Only when:
- Single node can't handle write throughput
- Dataset exceeds single-node storage
- You need geo-locality

Complexity increase:
- Application must be shard-aware
- No cross-shard foreign keys
- Distributed transactions are expensive
- Operations become N times as complex
```

---

# Part 2: Sharding Strategies

## 🔢 Hash Sharding

### Basic: Modulo
```python
def get_shard(customer_id, num_shards):
    return customer_id % num_shards

# Problem: Adding a shard redistributes almost ALL data
# Before: 4 shards → customer 5 → shard 1
# After:  5 shards → customer 5 → shard 0  (moved!)
# Every 1/N records stay in place, (N-1)/N move
```

### Consistent Hashing (Dynamo/Cassandra)
```python
import hashlib
import bisect

class ConsistentHash:
    def __init__(self, nodes, replicas=100):  # 100 virtual nodes each
        self.replicas = replicas
        self.ring = []  # Sorted list of (hash, node)
        self.node_to_hashes = {}
        
        for node in nodes:
            self.add_node(node)
    
    def _hash(self, key):
        return int(hashlib.sha256(key.encode()).hexdigest(), 16)
    
    def add_node(self, node):
        self.node_to_hashes[node] = []
        for i in range(self.replicas):
            h = self._hash(f"{node}:{i}")
            self.ring.append((h, node))
            self.node_to_hashes[node].append(h)
        self.ring.sort()
    
    def remove_node(self, node):
        for h in self.node_to_hashes[node]:
            self.ring.remove((h, node))
        del self.node_to_hashes[node]
    
    def get_node(self, key):
        h = self._hash(key)
        idx = bisect.bisect_left([x[0] for x in self.ring], h)
        if idx == len(self.ring):
            idx = 0
        return self.ring[idx][1]

# Adding a node: Only ~1/N keys need to move
# Removing a node: Only that node's keys move to next node
```

### Jump Consistent Hash (Google)
```python
def jump_consistent_hash(key: int, num_buckets: int) -> int:
    """
    Fast, memory-efficient consistent hashing.
    Paper: arxiv.org/abs/1406.2294
    """
    b, j = -1, 0
    while j < num_buckets:
        b = j
        key = (key * 2862933555777941757 + 1) & 0xFFFFFFFFFFFFFFFF
        j = int((b + 1) * (float(1 << 31) / float((key >> 33) + 1)))
    return b

# O(log n) time, O(1) space
# Only ~1/N keys move when adding bucket
# Drawback: Buckets must be numbered 0..N-1 (no gaps)
```

## 🔤 Range Sharding

```
Shard 0: customer_id < 1,000,000
Shard 1: 1,000,000 <= customer_id < 2,000,000
Shard 2: customer_id >= 2,000,000

Pros:
- Range queries within shard are efficient
- Sequential IDs stay together

Cons:
- Hotspot on newest shard (new users)
- Requires periodic rebalancing
```

### Anti-Pattern: Sequential ID Hotspot
```python
# All new users go to the last shard
# Solution 1: Random-ish IDs (ULIDs, Snowflake IDs)
# Solution 2: Write sharding (random shard + scatter-gather reads)
```

## 📖 Directory Sharding

```python
# Lookup table maps key → shard
class DirectoryShard:
    def __init__(self, db):
        self.db = db
    
    def get_shard(self, customer_id):
        result = self.db.execute(
            "SELECT shard_id FROM shard_directory WHERE customer_id = %s",
            [customer_id]
        )
        if result:
            return result[0]
        
        # New customer: Assign to least-loaded shard
        shard_id = self.get_least_loaded_shard()
        self.db.execute(
            "INSERT INTO shard_directory (customer_id, shard_id) VALUES (%s, %s)",
            [customer_id, shard_id]
        )
        return shard_id
    
    def move_customer(self, customer_id, new_shard):
        # Migrate data, then update directory
        self.db.execute(
            "UPDATE shard_directory SET shard_id = %s WHERE customer_id = %s",
            [new_shard, customer_id]
        )

# Pros: Full flexibility, can rebalance any key
# Cons: Directory is single point of failure
#       Extra hop for every query
```

---

# Part 3: Hotspot Mitigation

## 🔥 The Hotspot Problem

```
Scenario: Black Friday sale. 
Product ID 12345 is featured.
1M users view product 12345 simultaneously.

Result: All 1M requests hit Shard 3 (where 12345 lives).
Shard 3 dies. Black Friday ruined.
```

## ⚡ Write Sharding (Fan-out)

```python
NUM_WRITE_SHARDS = 10

def write_view(product_id, user_id, timestamp):
    # Distribute writes across N shards
    write_shard = hash(f"{product_id}:{timestamp}") % NUM_WRITE_SHARDS
    
    table = f"product_views_{write_shard}"
    db.execute(f"""
        INSERT INTO {table} (product_id, user_id, ts)
        VALUES (%s, %s, %s)
    """, [product_id, user_id, timestamp])

def get_view_count(product_id):
    # Scatter-gather: Query all shards, sum results
    total = 0
    for shard in range(NUM_WRITE_SHARDS):
        table = f"product_views_{shard}"
        count = db.execute(f"""
            SELECT COUNT(*) FROM {table} WHERE product_id = %s
        """, [product_id])
        total += count
    return total

# Trade-off: Reads are N times slower
# Use for write-heavy, read-light scenarios
```

## 🧂 Salted Keys

```python
# Problem: Row key "product:12345" is hot
# Solution: Append random salt

NUM_SALTS = 10

def write_with_salt(product_id, data):
    salt = random.randint(0, NUM_SALTS - 1)
    key = f"{salt}#{product_id}"
    table.put(key, data)

def read_all_salts(product_id):
    results = []
    for salt in range(NUM_SALTS):
        key = f"{salt}#{product_id}"
        results.extend(table.get(key))
    return results

# Writes distributed across N keys
# Reads require N lookups (parallelizable)
```

## 🔄 Read-Through Cache

```python
import redis

def get_product(product_id):
    # Check cache first
    cached = redis.get(f"product:{product_id}")
    if cached:
        return json.loads(cached)
    
    # Cache miss: Query DB
    product = db.execute("SELECT * FROM products WHERE id = %s", [product_id])
    
    # Cache with TTL
    redis.setex(f"product:{product_id}", 300, json.dumps(product))  # 5 min
    
    return product

# Hot products stay in cache
# DB shard is protected
```

---

# Part 4: Shard Rebalancing

## 🔀 Online Shard Splitting (Vitess)

```
Before: 
  Shard -80 (keys < 80): 500GB
  Shard 80- (keys >= 80): 500GB

Shard 80- is getting too big. Split it.

After:
  Shard -80:   keys < 80     (500GB)
  Shard 80-c0: 80 <= keys < c0 (250GB)
  Shard c0-:   keys >= c0    (250GB)
```

### Vitess Split Workflow
```bash
# 1. Create target shards (empty)
vtctl ApplySchema -sql="..." commerce/-80
vtctl ApplySchema -sql="..." commerce/80-c0
vtctl ApplySchema -sql="..." commerce/c0-

# 2. Start VReplication (copy data, follow binlog)
vtctl MoveShard -workflow=split commerce.80- commerce.80-c0,commerce.c0-

# 3. Monitor progress
vtctl Workflow commerce.split show

# 4. Cutover traffic (brief read-only period)
vtctl Workflow commerce.split switchTraffic

# 5. Cleanup old shard
vtctl Workflow commerce.split complete
```

## 🔁 Dual-Write Migration

```python
# Phase 1: Write to old AND new shard (feature flag)
def write_order(order):
    old_shard = get_old_shard(order.customer_id)
    new_shard = get_new_shard(order.customer_id)
    
    old_shard.insert(order)
    if FEATURE_FLAG_DUAL_WRITE:
        new_shard.insert(order)

# Phase 2: Backfill old data to new shards
run_backfill_job(start_date, end_date)

# Phase 3: Verify data consistency
for _id in sample(all_orders, 10000):
    old = old_shard.get(_id)
    new = new_shard.get(_id)
    assert old == new

# Phase 4: Read from new, write to both
# Phase 5: Write only to new, decommission old
```

---

# Part 5: NewSQL Databases

## 🪳 CockroachDB

### Architecture
```
                 ┌─────────────────┐
                 │   SQL Layer     │
                 │  (PostgreSQL)   │
                 └────────┬────────┘
                          │
                 ┌────────▼────────┐
                 │  Transaction    │
                 │  (Serializable) │
                 └────────┬────────┘
                          │
                 ┌────────▼────────┐
                 │  Distribution   │
                 │  (Raft / Leaseholder) │
                 └────────┬────────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
    ┌────▼────┐      ┌────▼────┐      ┌────▼────┐
    │  Node 1 │      │  Node 2 │      │  Node 3 │
    │(Ranges) │      │(Ranges) │      │(Ranges) │
    └─────────┘      └─────────┘      └─────────┘
```

### Key Concepts
```
Range: Contiguous chunk of key-space (64MB default)
Leaseholder: Single node that serves reads/writes for a range
Raft Group: 3-5 replicas of a range for fault tolerance

Scaling:
- Add node → Ranges automatically rebalance
- Remove node → Ranges move to remaining nodes
- No manual sharding!
```

### DDL: Multi-Region Setup
```sql
-- Create multi-region database
CREATE DATABASE commerce PRIMARY REGION "us-east1" 
  REGIONS "us-west1", "eu-west1";

-- Tables survive region failure
ALTER DATABASE commerce SURVIVE REGION FAILURE;

-- Pin table data to specific region
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email STRING,
  region STRING
) LOCALITY REGIONAL BY ROW AS region;

-- Insert with region hint
INSERT INTO users (id, email, region) 
VALUES (gen_random_uuid(), 'alice@example.com', 'us-east1');

-- Reads from regional row are local
SELECT * FROM users WHERE region = 'us-east1' AND email = 'alice@example.com';
```

## 🌍 Vitess (MySQL Sharding)

### Architecture
```
        Application
             │
             ▼
       ┌───────────┐
       │  vtgate   │  ← Connection pooling, query routing
       └─────┬─────┘
             │
    ┌────────┼────────┐
    │        │        │
 ┌──▼──┐  ┌──▼──┐  ┌──▼──┐
 │vttab│  │vttab│  │vttab│  ← Query execution, replication
 └──┬──┘  └──┬──┘  └──┬──┘
    │        │        │
 ┌──▼──┐  ┌──▼──┐  ┌──▼──┐
 │MySQL│  │MySQL│  │MySQL│  ← Storage
 └─────┘  └─────┘  └─────┘
```

### VSchema (Sharding Config)
```json
{
  "sharded": true,
  "vindexes": {
    "hash": {
      "type": "hash"
    }
  },
  "tables": {
    "customers": {
      "column_vindexes": [
        {
          "column": "customer_id",
          "name": "hash"
        }
      ]
    },
    "orders": {
      "column_vindexes": [
        {
          "column": "customer_id",
          "name": "hash"
        }
      ]
    }
  }
}
```

### Routing Logic
```sql
-- Direct to single shard (shard key in WHERE)
SELECT * FROM customers WHERE customer_id = 123;
-- vtgate routes to shard with key 123

-- Scatter-gather (no shard key)
SELECT * FROM customers WHERE email = 'alice@example.com';
-- vtgate queries ALL shards, merges results

-- Cross-shard join (expensive!)
SELECT c.name, o.total 
FROM customers c 
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.email = 'alice@example.com';
-- vtgate: Query shards for email, then query shards for orders
```

---

# Part 6: Production Patterns

## 📊 Shard Health Monitoring

```sql
-- PostgreSQL: Check shard sizes
SELECT 
    current_database() AS shard,
    pg_size_pretty(pg_database_size(current_database())) AS size,
    (SELECT count(*) FROM customers) AS customer_count,
    (SELECT count(*) FROM orders) AS order_count;

-- Run on each shard, aggregate in monitoring
```

### Prometheus Metrics
```yaml
# Shard imbalance alert
groups:
  - name: sharding
    rules:
      - alert: ShardImbalance
        expr: |
          max(shard_size_bytes) / min(shard_size_bytes) > 2
        for: 1h
        annotations:
          summary: "Shard size imbalance > 2x"
      
      - alert: ShardHotspot
        expr: |
          max(rate(shard_queries_total[5m])) / 
          avg(rate(shard_queries_total[5m])) > 3
        for: 15m
        annotations:
          summary: "Shard receiving 3x average queries"
```

## 🔐 Logical Sharding (Prepare for Physical)

```sql
-- Add shard key NOW, shard LATER
CREATE TABLE orders (
    id BIGSERIAL,
    customer_id BIGINT NOT NULL,
    shard_key SMALLINT GENERATED ALWAYS AS (customer_id % 256) STORED,
    total NUMERIC(12,2),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (shard_key, id)
);

-- Index includes shard key
CREATE INDEX idx_orders_customer 
ON orders(shard_key, customer_id, created_at DESC);

-- When you shard:
-- Shard 0: shard_key IN (0..63)
-- Shard 1: shard_key IN (64..127)
-- Shard 2: shard_key IN (128..191)
-- Shard 3: shard_key IN (192..255)
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Vertical scaling exhausted | Tried largest instance? |
| 2 | Read replicas configured | Replica lag < 1 second? |
| 3 | Shard key is high cardinality | Not status, country, etc. |
| 4 | Shard key rarely changes | Not email, name, etc. |
| 5 | Related data co-located | Orders with same customer_id on same shard |
| 6 | No cross-shard foreign keys | FK constraints are shard-local only |
| 7 | Hotspot monitoring enabled | Alert on query imbalance |
| 8 | Rebalancing procedure tested | Practiced shard splitting |

---

## 🔗 Related Documents
*   [NoSQL Architecture](./nosql-architecture-guide.md) — Bigtable, DynamoDB sharding.
*   [Replication & Consistency](./replication-consistency-guide.md) — Quorums, consensus.
*   [RDBMS Internals](./rdbms-internals-guide.md) — Connection pooling, partitioning.
