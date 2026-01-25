# RDBMS Internals: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ DBA
> **Scope**: Storage Engines, Indexing, Query Optimization, Locking, Partitioning — Production DDL with Performance Annotations

> [!CAUTION]
> **The Cardinal Sin**: Adding indexes without understanding the write penalty. Every index is a hidden B-Tree maintained on every INSERT/UPDATE. 5 indexes = 6x write amplification.

---

## 📚 Required Reading

| Resource | Topic |
| :--- | :--- |
| [Use The Index, Luke](https://use-the-index-luke.com/) | B-Tree mechanics, query optimization |
| [PostgreSQL Internals](https://www.interdb.jp/pg/) | Buffer pool, MVCC, checkpoints |
| [CMU Database Systems (Andy Pavlo)](https://www.youtube.com/playlist?list=PLSE8ODhjZXjaKScG3l0nuOiDTTqpfnWFf) | Storage engines, recovery |

---

## 🎯 The Principal Laws of RDBMS

| Law | Rule | Consequence |
| :--- | :--- | :--- |
| **Law 1: Disk is 10,000x Slower** | Random IOPS: SSD=10K, NVMe=500K, RAM=10M | Indexes exist to make random access sequential |
| **Law 2: Indexes are Sorted** | B-Tree is ordered by key | Range queries are O(log N + K) |
| **Law 3: Writes Pay Later** | Every index adds O(log N) per write | 5 indexes = 6x write amplification |
| **Law 4: Locks are Contention** | Row locks are cheap, table locks are death | Design for `SELECT ... FOR UPDATE SKIP LOCKED` |

---

# Part 1: Storage Engine Internals

## 📦 Page Layout (PostgreSQL)

```
Page (8KB default):
┌─────────────────────────────────────────────────┐
│ Page Header (24 bytes)                           │
│   - LSN (8 bytes): Last WAL position             │
│   - Checksum (2 bytes)                           │
│   - Flags, etc.                                  │
├─────────────────────────────────────────────────┤
│ Item Pointers (4 bytes each) →                   │
│   [offset, length, flags]                        │
│   [offset, length, flags]                        │
│   ...                                            │
├─────────────────────────────────────────────────┤
│ Free Space                                       │
├─────────────────────────────────────────────────┤
│                   ← Tuples (rows) grow toward   │
│ [Tuple 2] [Tuple 1]                             │
│   - Header (23 bytes): xmin, xmax, infomask     │
│   - Null bitmap                                  │
│   - Data                                         │
└─────────────────────────────────────────────────┘
```

### Why This Matters
```
- Item pointers allow HOT (Heap Only Tuple) updates
- If no indexed column changes, new tuple version goes in same page
- Pointer updated to point to new tuple
- No index update needed! (10x faster for UPDATE)

Production rule: 
- Leave ~20% free space (fillfactor=80) for HOT updates
- For append-only tables, use fillfactor=100
```

### DDL: Optimized Table Storage
```sql
-- Write-heavy table with frequent updates
CREATE TABLE orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    customer_id BIGINT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    total NUMERIC(12,2),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
) WITH (
    fillfactor = 80,     -- Leave 20% for HOT updates
    autovacuum_vacuum_scale_factor = 0.01,  -- Vacuum at 1% dead tuples
    autovacuum_analyze_scale_factor = 0.005 -- Analyze at 0.5% changes
);

-- Append-only table (no updates)
CREATE TABLE events (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    event_time TIMESTAMPTZ NOT NULL,
    event_type VARCHAR(50),
    payload JSONB
) WITH (
    fillfactor = 100,    -- Pack pages fully
    autovacuum_enabled = false  -- No dead tuples to clean
);
```

## 📋 WAL (Write-Ahead Log)

### The Algorithm
```
1. Transaction modifies buffer (in memory)
2. WAL record written to WAL buffer → fsync to disk
3. Transaction commits (user sees "success")
4. Buffer NOT written to disk yet (dirty page)
5. Background: Checkpointer writes dirty pages, records checkpoint in WAL
6. Old WAL segments recycled after checkpoint
```

### Why This Works
```
WAL is sequential writes only.
Data files are random writes.
Sequential is 100x faster than random on spinning disk.
On NVMe: 4x faster.

Crash recovery:
1. Load last checkpoint
2. Replay WAL from checkpoint LSN to end
3. Database is consistent
```

### Tuning (PostgreSQL)
```
# postgresql.conf

# WAL buffer size (default 16MB is usually fine)
wal_buffers = 64MB

# fsync settings
wal_sync_method = fdatasync  # Linux default
synchronous_commit = on       # Set 'off' for async (unsafe but fast)

# Checkpoint frequency
checkpoint_timeout = 10min           # Time between checkpoints
checkpoint_completion_target = 0.9   # Spread I/O over 90% of interval
max_wal_size = 2GB                   # Trigger checkpoint if WAL exceeds this

# WAL compression (PostgreSQL 15+)
wal_compression = lz4
```

## 🔄 MVCC (Multi-Version Concurrency Control)

### How It Works (PostgreSQL)
```
Every row has hidden columns:
- xmin: Transaction ID that created this row version
- xmax: Transaction ID that deleted/updated this row (0 if alive)
- cmin/cmax: Command ID within transaction

Transaction visibility:
- Row is visible if:
  - xmin is committed AND xmin < current_snapshot
  - xmax is 0 OR xmax is aborted OR xmax > current_snapshot
```

### The Bloat Problem
```
UPDATE users SET name = 'Bob' WHERE id = 1;

This creates a NEW row version. Old version is still there.
Dead tuples accumulate until VACUUM.

Symptom: Table is 10GB but only 1GB of live data.
Check: SELECT pg_size_pretty(pg_total_relation_size('users'));
       vs actual row count * average row size
```

### Aggressive VACUUM for High-Update Tables
```sql
-- Per-table autovacuum settings
ALTER TABLE orders SET (
    autovacuum_vacuum_threshold = 50,        -- Start after 50 dead tuples
    autovacuum_vacuum_scale_factor = 0.01,   -- Plus 1% of table size
    autovacuum_vacuum_cost_delay = 0,        -- No throttling
    autovacuum_vacuum_cost_limit = 1000      -- More aggressive
);

-- For tables with massive deletes (partition drop is better)
ALTER TABLE logs SET (
    autovacuum_freeze_min_age = 10000000,    -- Freeze early
    autovacuum_freeze_max_age = 100000000,   -- Force freeze threshold
    autovacuum_freeze_table_age = 50000000
);
```

---

# Part 2: Index Deep Dive

## 🌲 B-Tree Internals

### Structure
```
                     [Root: 50,100]
                    /      |       \
        [Leaf:10,20,30] [Leaf:60,70,80] [Leaf:110,120,130]
            │               │                   │
         (heap pointers) (heap pointers)    (heap pointers)
```

### Key Properties
```
- Height: log_b(N) where b = branching factor (~200 for 8KB pages)
- For 1 billion rows: height = log_200(1B) ≈ 4 levels
- 4 disk reads to find any row (O(log N))
- Range scan: Find start, then sequential read (O(log N + K))
```

### Page Split (The Write Cost)
```
Inserting into a full leaf page:
1. Allocate new page
2. Move half the keys to new page
3. Add pointer in parent
4. If parent is full, split recursively

Cost: 3+ page writes per split (plus WAL)
Mitigation: Leave free space (fillfactor < 100)
```

### Ordered Inserts Optimization
```sql
-- BAD: Random UUIDs cause random page splits
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ...
);

-- GOOD: Sequential IDs, inserts always go to the rightmost page
CREATE TABLE events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ...
);

-- GOOD: ULIDs are time-ordered UUIDs
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT ulid_generate(),  -- Extension needed
    ...
);
```

## 📊 Index Types Comparison

| Index Type | Structure | Best For | Overhead | Example Use |
| :--- | :--- | :--- | :--- | :--- |
| **B-Tree** | Sorted tree | Equality, Range, Sorting | Medium | `WHERE id = 123`, `ORDER BY date` |
| **Hash** | Hash table | Equality only | Low | `WHERE uuid = 'abc'` |
| **GiST** | Generalized tree | Geometric, Full-text | High | `WHERE point <@ box`, `@@` |
| **GIN** | Inverted index | Arrays, JSONB, Full-text | Very High | `WHERE tags @> '{x}'` |
| **BRIN** | Block summaries | Time-series, append-only | Very Low | `WHERE ts > '2024-01-01'` |
| **Bitmap** | Bit vector | Low cardinality, AND/OR | Low | Combined index scans |

## 📐 Partial Indexes (The 80/20 Rule)

### The Problem
```sql
-- Full index on 10M rows, but you only query 'pending' orders
CREATE INDEX idx_orders_status ON orders(status);

-- Query: SELECT * FROM orders WHERE status = 'pending';
-- 99% of rows are 'completed', 1% are 'pending'
-- Index has 10M entries, but you only need 100K
```

### The Solution
```sql
-- Partial index: Only index the rows you query
CREATE INDEX idx_orders_pending 
ON orders(created_at) 
WHERE status = 'pending';

-- Index has 100K entries, not 10M
-- 100x smaller, 100x faster to maintain

-- IMPORTANT: Query must match the WHERE clause
SELECT * FROM orders 
WHERE status = 'pending'  -- Must match index predicate
  AND created_at > '2024-01-01';
```

### Common Patterns
```sql
-- Active users only
CREATE INDEX idx_users_active_email 
ON users(email) 
WHERE is_active = true;

-- Unprocessed queue items
CREATE INDEX idx_jobs_pending 
ON jobs(priority, created_at) 
WHERE processed_at IS NULL;

-- Recent data only
CREATE INDEX idx_events_recent 
ON events(event_type, created_at) 
WHERE created_at > NOW() - INTERVAL '7 days';
-- NOTE: This requires periodic recreation as the predicate is static
```

## 🧱 BRIN Indexes (Block Range INdex)

### How It Works
```
Table is divided into "ranges" of pages (default: 128 pages = 1MB)
For each range, store min/max values of indexed column

Range 1 (pages 1-128):   min=2024-01-01, max=2024-01-15
Range 2 (pages 129-256): min=2024-01-16, max=2024-01-31
Range 3 (pages 257-384): min=2024-02-01, max=2024-02-15

Query: WHERE created_at > '2024-01-20'
- Skip Range 1 (max < '2024-01-20')
- Scan Range 2, 3, ...
```

### When to Use BRIN
```
✅ Data is physically sorted (time-series, append-only)
✅ Table is huge (100M+ rows)
✅ Query filter is on the sorted column
✅ Disk space is critical

❌ Data is randomly ordered
❌ Updates reorder data
❌ You need exact lookups
```

### DDL: Time-Series with BRIN
```sql
-- Events table: Append-only, always query by time range
CREATE TABLE events (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    event_time TIMESTAMPTZ NOT NULL,
    event_type VARCHAR(50),
    payload JSONB
);

-- BRIN index: ~1MB for 10TB of data
CREATE INDEX idx_events_time ON events USING BRIN (event_time)
WITH (pages_per_range = 64);  -- Smaller ranges for better selectivity

-- Compare sizes
SELECT pg_size_pretty(pg_relation_size('idx_events_time'));  -- ~1MB
-- B-Tree would be ~20GB for the same table
```

## 🎯 GIN Indexes (Generalized Inverted Index)

### How It Works
```
For JSONB: {"tags": ["a", "b", "c"]}

GIN creates inverted index:
  "a" → [row1, row5, row12]
  "b" → [row1, row3]
  "c" → [row1, row7, row8]

Query: WHERE tags @> '["a", "b"]'
  Lookup "a" → [row1, row5, row12]
  Lookup "b" → [row1, row3]
  Intersect → [row1]
```

### DDL: JSONB Indexing
```sql
-- Index for containment queries (@>, <@, ?, ?&, ?|)
CREATE INDEX idx_orders_payload ON orders USING GIN (payload);

-- Query examples:
SELECT * FROM orders WHERE payload @> '{"customer": {"type": "premium"}}';
SELECT * FROM orders WHERE payload ? 'discount_code';
SELECT * FROM orders WHERE payload ?& array['shipping', 'billing'];

-- Expression index for specific path
CREATE INDEX idx_orders_customer_type 
ON orders USING BTREE ((payload->'customer'->>'type'));

-- This is faster than GIN if you always query this specific path
SELECT * FROM orders WHERE payload->'customer'->>'type' = 'premium';
```

### GIN vs GiST Trade-offs
```
GIN:
- Faster reads (exact posting lists)
- Slower writes (update posting lists)
- Larger size

GiST:
- Faster writes (tree structure)
- Slower reads (tree traversal)
- Smaller size

Rule: Use GIN for read-heavy, GiST for balanced or write-heavy
```

---

# Part 3: Query Optimizer

## 📊 EXPLAIN ANALYZE (The Truth Machine)

### Reading the Output
```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM orders 
WHERE customer_id = 123 
  AND status = 'pending'
ORDER BY created_at DESC
LIMIT 10;
```

```
Limit  (cost=0.43..12.34 rows=10 width=128) (actual time=0.052..0.089 rows=10 loops=1)
  Buffers: shared hit=15
  ->  Index Scan Backward using idx_orders_customer_status on orders  
        (cost=0.43..45.67 rows=100 width=128) (actual time=0.051..0.086 rows=10 loops=1)
        Index Cond: ((customer_id = 123) AND (status = 'pending'::text))
        Buffers: shared hit=15
Planning Time: 0.234 ms
Execution Time: 0.123 ms
```

### Key Metrics
```
cost=0.43..12.34:
  - 0.43 = Startup cost (time before first row)
  - 12.34 = Total cost (arbitrary units, compare between plans)

rows=10:
  - Estimated rows (from statistics)

actual time=0.052..0.089:
  - Real execution time in milliseconds
  - 0.052 = First row, 0.089 = All rows

Buffers: shared hit=15:
  - 15 pages read from buffer cache (no disk I/O = good)
  - shared read=X means disk I/O (bad if high)
```

### Finding Problems
```sql
-- Rows estimate way off? Statistics are stale
ANALYZE orders;

-- Sequential scan on large table? Missing index
-- "Seq Scan on orders (cost=0.00..123456.00 rows=10000000 width=128)"

-- Bitmap scan? Multiple conditions, consider composite index
-- "Bitmap Heap Scan on orders"
-- "  -> BitmapAnd"
-- "      -> Bitmap Index Scan on idx_customer"
-- "      -> Bitmap Index Scan on idx_status"
```

## 🔗 Join Algorithms

### Nested Loop (Small Tables)
```
for each row in outer_table:
    for each row in inner_table:
        if join_condition:
            emit row

Cost: O(N * M)
Best when: Inner table is small and indexed
```

### Hash Join (Medium Tables)
```
1. Build hash table from smaller table
2. Probe hash table with larger table

Cost: O(N + M)
Best when: No useful indexes, tables fit in work_mem
```

### Merge Join (Sorted Tables)
```
1. Sort both tables (or use index)
2. Merge like mergesort

Cost: O(N log N + M log M) for sort, O(N + M) for merge
Best when: Both tables have indexes, or large sorted tables
```

### Forcing Join Order (When Optimizer is Wrong)
```sql
-- Optimizer chooses wrong order? Set join_collapse_limit
SET join_collapse_limit = 1;  -- Disable reordering

-- Or use explicit JOIN order
SELECT /*+ Leading(orders customers) HashJoin(orders customers) */ *
FROM orders
JOIN customers ON orders.customer_id = customers.id
WHERE ...;  -- pg_hint_plan extension
```

---

# Part 4: Locking & Concurrency

## 🔒 Lock Hierarchy

| Lock Level | Conflicts With | Use Case |
| :--- | :--- | :--- |
| **ACCESS SHARE** | ACCESS EXCLUSIVE | `SELECT` |
| **ROW SHARE** | EXCLUSIVE, ACCESS EXCLUSIVE | `SELECT FOR UPDATE` |
| **ROW EXCLUSIVE** | SHARE, SHARE ROW EXCL, EXCL, ACCESS EXCL | `INSERT`, `UPDATE`, `DELETE` |
| **SHARE** | ROW EXCL, SHARE ROW EXCL, EXCL, ACCESS EXCL | `CREATE INDEX CONCURRENTLY` |
| **ACCESS EXCLUSIVE** | All | `DROP TABLE`, `ALTER TABLE` |

## 🏃 SKIP LOCKED (Distributed Queue Pattern)

### The Problem
```sql
-- 10 workers trying to claim jobs
-- Without SKIP LOCKED, they all wait on the same row

BEGIN;
SELECT * FROM jobs WHERE status = 'pending' LIMIT 1 FOR UPDATE;
-- All 10 workers wait on row 1
```

### The Solution
```sql
-- Each worker skips locked rows, grabs the next available
BEGIN;
SELECT * FROM jobs 
WHERE status = 'pending' 
ORDER BY priority DESC, created_at 
FOR UPDATE SKIP LOCKED
LIMIT 1;

-- Claim the job
UPDATE jobs SET status = 'processing', worker_id = 'worker-1' WHERE id = ...;
COMMIT;
```

### Production DDL: Job Queue
```sql
CREATE TABLE jobs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    queue_name VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    priority INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    claimed_at TIMESTAMPTZ,
    worker_id VARCHAR(100),
    attempts INT DEFAULT 0,
    max_attempts INT DEFAULT 3,
    next_attempt_at TIMESTAMPTZ
);

-- Partial index for pending jobs only
CREATE INDEX idx_jobs_pending 
ON jobs(queue_name, priority DESC, created_at)
WHERE status = 'pending';

-- Partial index for retryable jobs
CREATE INDEX idx_jobs_retry 
ON jobs(next_attempt_at)
WHERE status = 'failed' AND attempts < max_attempts;

-- Claim a job
WITH claimed AS (
    SELECT id FROM jobs
    WHERE queue_name = 'emails'
      AND status = 'pending'
    ORDER BY priority DESC, created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1
)
UPDATE jobs 
SET status = 'processing', 
    claimed_at = NOW(), 
    worker_id = 'worker-1',
    attempts = attempts + 1
FROM claimed
WHERE jobs.id = claimed.id
RETURNING jobs.*;
```

## 🔐 Advisory Locks (Distributed Coordination)

### Use Case: Exactly-Once Processing
```sql
-- Acquire lock before processing event
SELECT pg_try_advisory_lock(hashtext('event:12345'));
-- Returns TRUE if acquired, FALSE if already locked

-- Process event...

SELECT pg_advisory_unlock(hashtext('event:12345'));
-- Release when done
```

### Use Case: Rate Limiting
```python
def with_rate_limit(resource_id, max_concurrent=5):
    """Allow max 5 concurrent operations per resource."""
    for slot in range(max_concurrent):
        lock_id = hash(f"{resource_id}:{slot}")
        acquired = db.execute("SELECT pg_try_advisory_lock(%s)", [lock_id]).scalar()
        if acquired:
            try:
                yield  # Do work
            finally:
                db.execute("SELECT pg_advisory_unlock(%s)", [lock_id])
            return
    raise RateLimitExceeded()
```

---

# Part 5: Partitioning

## 🗂️ Partition Strategies

| Strategy | Use Case | Example |
| :--- | :--- | :--- |
| **Range** | Time-series, ordered data | Partition by month |
| **List** | Categorical data | Partition by region, tenant |
| **Hash** | Even distribution | Partition by customer_id % N |

## 📅 Range Partitioning (Most Common)

### DDL: Time-Series Events
```sql
CREATE TABLE events (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    event_time TIMESTAMPTZ NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB
) PARTITION BY RANGE (event_time);

-- Create partitions for each month
CREATE TABLE events_2024_01 PARTITION OF events
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE events_2024_02 PARTITION OF events
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
-- ...

-- Index template (automatically created on each partition)
CREATE INDEX ON events(event_time);
CREATE INDEX ON events(event_type, event_time);

-- Default partition for out-of-range data
CREATE TABLE events_default PARTITION OF events DEFAULT;
```

### Automatic Partition Management (pg_partman)
```sql
-- Install extension
CREATE EXTENSION pg_partman;

-- Configure automatic partition creation
SELECT partman.create_parent(
    p_parent_table := 'public.events',
    p_control := 'event_time',
    p_type := 'native',
    p_interval := 'monthly',
    p_premake := 3  -- Create 3 months ahead
);

-- Schedule maintenance (run daily via cron/pg_cron)
SELECT partman.run_maintenance();

-- Drop partitions older than 1 year
UPDATE partman.part_config 
SET retention = '1 year', retention_keep_table = false
WHERE parent_table = 'public.events';
```

## 🏢 List Partitioning (Multi-Tenancy)

```sql
CREATE TABLE tenant_data (
    tenant_id VARCHAR(36) NOT NULL,
    id BIGINT NOT NULL,
    data JSONB
) PARTITION BY LIST (tenant_id);

-- One partition per tenant
CREATE TABLE tenant_data_acme PARTITION OF tenant_data
    FOR VALUES IN ('acme');
CREATE TABLE tenant_data_globex PARTITION OF tenant_data
    FOR VALUES IN ('globex');

-- Benefits:
-- 1. Drop tenant = DROP PARTITION (instant, no scan)
-- 2. Per-tenant vacuum/analyze
-- 3. Can move tenants to different tablespaces
```

---

# Part 6: Production DDL Reference

## 👤 Users & Authentication
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    attributes JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
) WITH (fillfactor = 90);

-- Unique email for active users only
CREATE UNIQUE INDEX idx_users_email_active 
ON users(lower(email)) 
WHERE is_active = true;

-- GIN for attribute queries
CREATE INDEX idx_users_attrs ON users USING GIN (attributes jsonb_path_ops);

-- Function index for case-insensitive search
CREATE INDEX idx_users_email_lower ON users(lower(email));
```

## 📦 Orders with Audit Trail
```sql
-- Main orders table
CREATE TABLE orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES customers(id),
    status VARCHAR(20) DEFAULT 'pending',
    total NUMERIC(12,2),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
) WITH (fillfactor = 80);

-- Composite index for customer queries
CREATE INDEX idx_orders_customer_status 
ON orders(customer_id, status, created_at DESC);

-- Partial index for active orders
CREATE INDEX idx_orders_pending 
ON orders(created_at DESC) 
WHERE status IN ('pending', 'processing');

-- Audit trail with trigger
CREATE TABLE orders_audit (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    action VARCHAR(10) NOT NULL,  -- INSERT, UPDATE, DELETE
    old_data JSONB,
    new_data JSONB,
    changed_by UUID,
    changed_at TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (changed_at);

CREATE OR REPLACE FUNCTION orders_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO orders_audit (order_id, action, old_data, new_data, changed_by)
    VALUES (
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END,
        current_setting('app.current_user', true)::UUID
    );
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_audit
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION orders_audit_trigger();
```

---

## ✅ Principal Architect Checklist

| # | Item | Command |
| :--- | :--- | :--- |
| 1 | Index usage verified | `SELECT * FROM pg_stat_user_indexes WHERE idx_scan = 0;` |
| 2 | No sequential scans on large tables | `EXPLAIN ANALYZE <query>` |
| 3 | Bloat under 20% | `pgstattuple('table_name')` |
| 4 | Partial indexes for common filters | Review `WHERE status = 'pending'` patterns |
| 5 | Composite indexes match query patterns | Check column order matches query |
| 6 | Connection pooling configured | pg_bouncer with transaction mode |
| 7 | Autovacuum tuned per table | Check `pg_stat_user_tables.n_dead_tup` |
| 8 | Partitioning for tables > 100M rows | `PARTITION BY RANGE/LIST/HASH` |

---

## 🔗 Related Documents
*   [NoSQL Architecture](./nosql-architecture-guide.md) — LSM, Bigtable, Spanner.
*   [Replication & Consistency](./replication-consistency-guide.md) — Leader-follower, quorums.
*   [Database Scaling](./database-scaling-guide.md) — Sharding patterns.
