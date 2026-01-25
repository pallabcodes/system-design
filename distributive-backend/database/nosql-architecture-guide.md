# NoSQL Architecture: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ DBA
> **Scope**: Bigtable, Spanner, LSM Internals, DynamoDB, Cassandra — Production DDL with Paper References

> [!CAUTION]
> **The Cardinal Sin**: Using NoSQL because "it scales". NoSQL **trades** query flexibility for write throughput. If you don't understand the trade-off, you will rewrite your data layer in 18 months.

---

## 📚 Required Reading (Google Research Papers)

| Paper | Year | Key Concepts |
| :--- | :--- | :--- |
| [Bigtable: A Distributed Storage System](https://research.google/pubs/bigtable-a-distributed-storage-system-for-structured-data/) | 2006 | Row-key design, Column families, LSM |
| [Spanner: Google's Globally Distributed Database](https://research.google/pubs/spanner-googles-globally-distributed-database/) | 2012 | TrueTime, External consistency, Interleaved tables |
| [F1: A Distributed SQL Database That Scales](https://research.google/pubs/f1-a-distributed-sql-database-that-scales/) | 2013 | Hierarchical schema, Distributed indexes |
| [Dynamo: Amazon's Key-value Store](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf) | 2007 | Consistent hashing, Vector clocks, Sloppy quorum |

---

## 🎯 The Principal Laws of NoSQL

| Law | Rule | Consequence |
| :--- | :--- | :--- |
| **Law 1: Query-First Design** | Design the row-key for your access pattern. | You cannot query what you didn't model. |
| **Law 2: Denormalization is Expected** | Duplicate data. Storage is cheap, joins are not. | Update logic must handle N copies. |
| **Law 3: Row-Key is Everything** | Bad row-key = hotspot = dead cluster. | 90% of Bigtable/Cassandra issues are row-key design. |
| **Law 4: LSM Tax** | Every write pays O(log N) compaction cost eventually. | Write amplification is real. Budget for it. |

---

# Part 1: LSM Tree Internals (The Engine Behind Everything)

**Used by**: Bigtable, Cassandra, RocksDB, LevelDB, HBase, DynamoDB (internal), CockroachDB, TiDB

## 🔧 The LSM Algorithm

```
WRITE PATH:
1. Write to WAL (Write-Ahead Log) — Sequential IO, fsync
2. Insert into MemTable (in-memory Red-Black Tree or SkipList)
3. When MemTable is full (~64MB), flush to disk as SSTable (Sorted String Table)
4. SSTable is immutable. Deletes are "tombstones" (markers)

READ PATH:
1. Check MemTable (newest data)
2. Check Bloom filters for each SSTable level
3. Binary search within SSTables
4. Merge results, apply tombstones

COMPACTION (Background):
- Merge overlapping SSTables
- Remove duplicate keys (keep latest)
- Remove tombstones older than GC grace period
```

## ⚙️ Leveled vs Tiered Compaction

| Aspect | Leveled (RocksDB default) | Tiered (Cassandra STCS) |
| :--- | :--- | :--- |
| **Write Amplification** | Higher (10-30x) | Lower (< 10x) |
| **Read Amplification** | Lower (L0 + 1 file/level) | Higher (many files to check) |
| **Space Amplification** | Lower (~10%) | Higher (~50%) |
| **Best For** | Read-heavy, space-constrained | Write-heavy, logs |

### Leveled Compaction Internals
```
Level 0:  [SSTable] [SSTable] [SSTable]  ← Flushed from MemTable, overlapping
           ↓ compact when L0 > 4 files
Level 1:  [SSTable] [SSTable]            ← Non-overlapping, 10MB each
           ↓ compact when L1 > 10 * target_file_size
Level 2:  [SSTable] [SSTable] [SSTable]  ← 10x size of L1
           ↓
Level N:  ...

Key insight: Each level is 10x the size of the previous.
To find a key: Check L0 (all files), then 1 file per level.
```

### Write Amplification Calculation
```
A key written to L0 will be rewritten when:
- L0 → L1 compaction
- L1 → L2 compaction
- ...
- L(N-1) → LN compaction

Write amplification = 10 * (num_levels - 1) ≈ 10-30x
```

### RocksDB Tuning (Production)
```cpp
// RocksDB options for write-heavy workload
Options options;
options.write_buffer_size = 256 << 20;          // 256MB MemTable
options.max_write_buffer_number = 4;            // 4 MemTables before stall
options.min_write_buffer_number_to_merge = 2;   // Merge 2 before flush
options.level0_file_num_compaction_trigger = 4;
options.level0_slowdown_writes_trigger = 20;
options.level0_stop_writes_trigger = 36;
options.target_file_size_base = 64 << 20;       // 64MB SSTable
options.max_bytes_for_level_base = 512 << 20;   // 512MB L1
options.max_bytes_for_level_multiplier = 10;    // 10x per level
options.compression = kLZ4Compression;
options.bottommost_compression = kZSTD;         // Better ratio for cold data
```

## 🌸 Bloom Filters (The Read Optimizer)

### The Problem
```
You have 1000 SSTables. Key "user:12345" exists in only 1.
Do you read all 1000 files? (Answer: No)
```

### How It Works
```
Write: hash(key) → set bits at positions h1(k), h2(k), ..., hK(k)
Read:  hash(key) → check if ALL bits are set
       - If any bit is 0: Key DEFINITELY NOT in file
       - If all bits are 1: Key MAYBE in file (false positive possible)

False positive rate ≈ (1 - e^(-kn/m))^k
Where: k = number of hash functions
       n = number of keys
       m = number of bits
```

### Tuning: 10 Bits Per Key
```
At 10 bits/key with optimal k:
  False positive rate ≈ 0.82% (< 1%)

At 5 bits/key:
  False positive rate ≈ 9.2%

Production rule: 10 bits/key. Period.
```

### RocksDB Bloom Filter Config
```cpp
BlockBasedTableOptions table_options;
table_options.filter_policy.reset(NewBloomFilterPolicy(10.0, false));
// 10.0 = bits per key
// false = use full filter (not block-based)
options.table_factory.reset(NewBlockBasedTableFactory(table_options));
```

---

# Part 2: Bigtable Schema Design

**Paper**: [Bigtable: A Distributed Storage System for Structured Data](https://research.google/pubs/bigtable-a-distributed-storage-system-for-structured-data/)

## 🏗️ The Data Model

```
Table = Map<RowKey, Map<ColumnFamily:Qualifier, Map<Timestamp, Value>>>

Physically:
- Rows are sorted lexicographically by RowKey
- Rows are split into "tablets" (shards) at row boundaries
- Each ColumnFamily is stored in a separate SSTable
- Timestamps allow versioning (default: keep last N or last T days)
```

## 🔑 Row-Key Design (90% of Success)

### Anti-Pattern: Monotonically Increasing Keys
```
❌ BAD: row_key = timestamp
   Result: All writes go to the last tablet. Hotspot.

❌ BAD: row_key = auto_increment_id
   Result: Same problem.

❌ BAD: row_key = "user_" + user_id (if user_ids are sequential)
   Result: Same problem.
```

### Pattern 1: Reversed Timestamp (Most Common)
```python
# For time-series: Most recent first

# ❌ BAD: newest data at the end, reads scan from beginning
row_key = f"sensor:{sensor_id}:{timestamp}"

# ✅ GOOD: newest data at the beginning of the row range
REVERSED_TS = 9999999999999 - timestamp_ms
row_key = f"sensor:{sensor_id}:{REVERSED_TS}"

# Query "last 10 readings for sensor X":
# scan(start="sensor:X:", end="sensor:X:~", limit=10)
# Reads first 10 rows (newest) without scanning old data
```

### Pattern 2: Salted Keys (Hotspot Prevention)
```python
# ❌ BAD: All events for "viral_video" go to one tablet
row_key = f"video:{video_id}:{timestamp}"

# ✅ GOOD: Distribute using a hash prefix
salt = hash(video_id) % 10  # 0-9
row_key = f"{salt}#video:{video_id}:{timestamp}"

# Trade-off: Reads for one video_id now require 10 parallel scans
# Acceptable if writes >> reads
```

### Pattern 3: Composite Keys for Locality
```python
# Goal: Store user's messages, query by (user_id, mailbox, date)

# ✅ GOOD: Related data is contiguous
row_key = f"{user_id}#{mailbox}#{reversed_timestamp}#{message_id}"

# Query "last 50 messages in user X's inbox":
# scan(start="X#inbox#", end="X#inbox#~", limit=50)

# Query "all mailboxes for user X":
# scan(start="X#", end="X#~")
```

### Pattern 4: Tall vs Wide Tables

| Tall Table | Wide Table |
| :--- | :--- |
| One row per data point | One row per entity, many columns |
| `sensor:1:ts1 → {value: 50}` | `sensor:1 → {ts1: 50, ts2: 51, ts3: 52, ...}` |
| Pro: Scales to billions of rows | Pro: Single read for entity |
| Con: Many rows to scan | Con: Max 100MB per row in Bigtable |
| Best for: Time-series, logs | Best for: User profiles, configs |

## 📦 Column Families

```
Column Family = Logical grouping stored in separate SSTable files

Use Case:
- "profile": name, email, created_at (read frequently, small)
- "activity": login_count, last_login (read frequently, updated often)  
- "history": full activity log (read rarely, large)

DDL (Cloud Bigtable):
```

```bash
cbt createtable users
cbt createfamily users profile
cbt createfamily users activity
cbt createfamily users history

# Set different GC policies per family
cbt setgcpolicy users profile maxversions=1
cbt setgcpolicy users activity maxage=30d
cbt setgcpolicy users history maxage=365d maxversions=1
```

### Production DDL: Messaging System
```bash
# Table: messages
# Row key: {user_id}#{mailbox}#{reversed_ts}#{msg_id}

cbt createtable messages

# Metadata: subject, from, to, read_status (always needed)
cbt createfamily messages meta

# Body: message body (only needed for full view, can be large)
cbt createfamily messages body

# Attachments: stored separately (rarely accessed)
cbt createfamily messages attachments

# GC: Keep 1 version, delete after 2 years
cbt setgcpolicy messages meta maxversions=1 maxage=730d
cbt setgcpolicy messages body maxversions=1 maxage=730d
cbt setgcpolicy messages attachments maxversions=1 maxage=365d
```

### Read Pattern
```python
# List inbox (fast: only reads "meta" column family)
rows = table.read_rows(
    row_set=RowSet(row_ranges=[RowRange(
        start_key=f"{user_id}#inbox#",
        end_key=f"{user_id}#inbox#~"
    )]),
    filter_=ColumnFamilyRegexFilter("meta"),
    limit=50
)

# Read full message (reads "meta" + "body")
row = table.read_row(
    row_key=f"{user_id}#inbox#{reversed_ts}#{msg_id}",
    filter_=ColumnFamilyRegexFilter("meta|body")
)
```

---

# Part 3: Google Spanner Deep Dive

**Paper**: [Spanner: Google's Globally Distributed Database](https://research.google/pubs/spanner-googles-globally-distributed-database/)

## 🕐 TrueTime: The Key Innovation

### The Problem
```
Traditional distributed DBs use wall-clock time.
But clocks drift. NTP sync is ~100ms accurate.

Node A: "I committed at t=1000"
Node B: "I committed at t=1001"

Are they causally ordered? YOU DON'T KNOW.
Clock skew could make t=1001 actually happen before t=1000.
```

### TrueTime API
```
TrueTime.now() returns an interval: [earliest, latest]

tt = TrueTime.now()
tt.earliest = 1000000000  # Cannot be before this
tt.latest   = 1000000007  # Cannot be after this
tt.error    = 7ms         # Uncertainty window (typically 1-7ms)

Guarantee: The actual time is WITHIN this interval.
```

### How It Works
```
GPS receivers in every datacenter → microsecond accuracy to UTC
Atomic clocks as backup → drift < 200μs/second
Software daemon → polls GPS + atomic, estimates error bounds
```

### Commit-Wait: External Consistency
```
To ensure Transaction A (commit time tA) is visible to Transaction B (commit time tB)
where tA < tB in real time:

1. TxA picks commit timestamp s = TrueTime.now().latest
2. TxA WAITS until TrueTime.now().earliest > s
   (This is "commit-wait" — typically 7ms)
3. TxA commits and releases locks

Now any later transaction will see TxA.

Why? Because by waiting, we guarantee:
- s < actual_commit_time (we waited past s)
- Any later read will have start_time > s (TrueTime guarantee)
```

## 🏛️ Interleaved Tables (Parent-Child Locality)

### The Problem
```sql
-- In traditional SQL:
SELECT * FROM Customer c 
JOIN Order o ON c.id = o.customer_id 
WHERE c.id = 123;

-- Customer rows are on Shard A.
-- Order rows are on Shard B, C, D (hashed by order_id).
-- This requires cross-shard RPCs.
```

### Spanner's Solution: Interleaving
```sql
CREATE TABLE Customers (
  CustomerId INT64 NOT NULL,
  Name STRING(MAX),
) PRIMARY KEY (CustomerId);

CREATE TABLE Orders (
  CustomerId INT64 NOT NULL,  -- Parent's PK comes first
  OrderId INT64 NOT NULL,
  Amount NUMERIC,
) PRIMARY KEY (CustomerId, OrderId),
  INTERLEAVE IN PARENT Customers ON DELETE CASCADE;

CREATE TABLE OrderItems (
  CustomerId INT64 NOT NULL,
  OrderId INT64 NOT NULL,
  ItemId INT64 NOT NULL,
  ProductId INT64 NOT NULL,
) PRIMARY KEY (CustomerId, OrderId, ItemId),
  INTERLEAVE IN PARENT Orders ON DELETE CASCADE;
```

### Physical Layout
```
Customer(1, "Alice")
  Order(1, 101, 50.00)
    OrderItem(1, 101, 1, "SKU-A")
    OrderItem(1, 101, 2, "SKU-B")
  Order(1, 102, 30.00)
    OrderItem(1, 102, 1, "SKU-C")
Customer(2, "Bob")
  Order(2, 201, 100.00)
    OrderItem(2, 201, 1, "SKU-D")
```

**Result**: All data for Customer 1 is in the same split.
Query `SELECT * FROM Orders WHERE CustomerId = 1` reads ONE shard.

### When to Use Interleaving
```
✅ Strong parent-child relationship
✅ Always query child by parent key
✅ Cascade delete makes sense

❌ Child is queried by its own key (e.g., OrderId alone)
❌ Many-to-many relationship
❌ Child can exist without parent
```

### DDL: Full E-commerce Schema
```sql
-- Root: Customers
CREATE TABLE Customers (
  CustomerId INT64 NOT NULL,
  Email STRING(255) NOT NULL,
  Name STRING(100),
  CreatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
) PRIMARY KEY (CustomerId);

-- Index for login by email (global secondary index)
CREATE UNIQUE INDEX CustomersByEmail ON Customers(Email);

-- Interleaved: Customer's Addresses
CREATE TABLE CustomerAddresses (
  CustomerId INT64 NOT NULL,
  AddressId INT64 NOT NULL,
  Type STRING(20),  -- 'billing', 'shipping'
  Street STRING(255),
  City STRING(100),
  PostalCode STRING(20),
) PRIMARY KEY (CustomerId, AddressId),
  INTERLEAVE IN PARENT Customers ON DELETE CASCADE;

-- Interleaved: Customer's Orders
CREATE TABLE Orders (
  CustomerId INT64 NOT NULL,
  OrderId INT64 NOT NULL,
  Status STRING(20) DEFAULT ('pending'),
  TotalAmount NUMERIC,
  CreatedAt TIMESTAMP OPTIONS (allow_commit_timestamp=true),
  UpdatedAt TIMESTAMP,
) PRIMARY KEY (CustomerId, OrderId),
  INTERLEAVE IN PARENT Customers ON DELETE NO ACTION;

-- Index for querying orders by status (local to customer)
CREATE INDEX OrdersByCustomerStatus 
ON Orders(CustomerId, Status, CreatedAt DESC);

-- Interleaved: Order's Items
CREATE TABLE OrderItems (
  CustomerId INT64 NOT NULL,
  OrderId INT64 NOT NULL,
  OrderItemId INT64 NOT NULL,
  ProductId INT64 NOT NULL,
  Quantity INT64 NOT NULL,
  UnitPrice NUMERIC NOT NULL,
) PRIMARY KEY (CustomerId, OrderId, OrderItemId),
  INTERLEAVE IN PARENT Orders ON DELETE CASCADE;

-- Non-interleaved: Products (queried independently)
CREATE TABLE Products (
  ProductId INT64 NOT NULL,
  SKU STRING(50) NOT NULL,
  Name STRING(255),
  Price NUMERIC,
  Inventory INT64,
) PRIMARY KEY (ProductId);

CREATE UNIQUE INDEX ProductsBySKU ON Products(SKU);
```

## ⚡ Spanner Transactions

### Read-Write Transaction
```python
def transfer_funds(from_id, to_id, amount):
    def work(transaction):
        from_balance = transaction.read(
            "Accounts", 
            keys=[from_id], 
            columns=["Balance"]
        )
        to_balance = transaction.read(
            "Accounts", 
            keys=[to_id], 
            columns=["Balance"]
        )
        
        if from_balance[0]["Balance"] < amount:
            raise InsufficientFunds()
        
        transaction.update(
            "Accounts",
            columns=["AccountId", "Balance"],
            values=[
                (from_id, from_balance[0]["Balance"] - amount),
                (to_id, to_balance[0]["Balance"] + amount),
            ]
        )
    
    database.run_in_transaction(work)  # Automatic retry on abort
```

### Stale Reads (Performance Optimization)
```python
# Strong read (default): Sees all committed transactions
result = database.execute_sql("SELECT * FROM Customers")

# Stale read: Up to 15 seconds stale, but may hit a nearby replica
result = database.execute_sql(
    "SELECT * FROM Customers",
    staleness=datetime.timedelta(seconds=15)
)

# Exact timestamp read: For time-travel queries
result = database.execute_sql(
    "SELECT * FROM Customers",
    staleness=specific_timestamp
)
```

---

# Part 4: DynamoDB Advanced Patterns

**Paper**: [Dynamo: Amazon's Highly Available Key-value Store](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf)

## 🔧 Single-Table Design (GSI Overloading)

### The Principle
```
In DynamoDB, you pay per table (streams, backups, etc.)
One table with flexible PK/SK is often better than many tables
GSIs project different "views" of the same data
```

### E-commerce Single Table
```
PK                  | SK                        | GSI1PK        | GSI1SK          | Data
--------------------|---------------------------|---------------|-----------------|-------
CUSTOMER#123        | PROFILE                   | EMAIL#a@b.com | CUSTOMER#123    | {name, email}
CUSTOMER#123        | ORDER#2024-01-15#001      | STATUS#pending| 2024-01-15      | {total, items}
CUSTOMER#123        | ORDER#2024-01-12#002      | STATUS#shipped| 2024-01-12      | {total, items}
ORDER#001           | ORDERITEM#1               |               |                 | {sku, qty}
ORDER#001           | ORDERITEM#2               |               |                 | {sku, qty}
PRODUCT#SKU-ABC     | PRODUCT                   | CATEGORY#elec | PRICE#00099.99  | {name, desc}
```

### Access Patterns
```python
# 1. Get customer by email (GSI1)
table.query(
    IndexName='GSI1',
    KeyConditionExpression='GSI1PK = :email',
    ExpressionAttributeValues={':email': 'EMAIL#a@b.com'}
)

# 2. Get customer profile + all orders (main table)
table.query(
    KeyConditionExpression='PK = :pk AND begins_with(SK, :sk)',
    ExpressionAttributeValues={':pk': 'CUSTOMER#123', ':sk': 'ORDER#'}
)

# 3. Get all pending orders across all customers (GSI1)
table.query(
    IndexName='GSI1',
    KeyConditionExpression='GSI1PK = :status',
    ExpressionAttributeValues={':status': 'STATUS#pending'}
)

# 4. Get products in category by price (GSI1)
table.query(
    IndexName='GSI1',
    KeyConditionExpression='GSI1PK = :cat AND GSI1SK BETWEEN :low AND :high',
    ExpressionAttributeValues={
        ':cat': 'CATEGORY#electronics',
        ':low': 'PRICE#00000.00',
        ':high': 'PRICE#00100.00'
    }
)
```

## 🔥 Hotspot Mitigation

### Problem: Monotonic Writes
```
PK = "ORDERS#2024-01-23"
All orders today write to ONE partition. Hotspot.
```

### Solution: Write Sharding
```python
import random

NUM_SHARDS = 10

def write_order(order):
    shard = random.randint(0, NUM_SHARDS - 1)
    table.put_item(Item={
        'PK': f'ORDERS#2024-01-23#{shard}',
        'SK': f'ORDER#{order["timestamp"]}#{order["id"]}',
        ...
    })

def get_todays_orders():
    # Scatter-gather: Query all 10 shards in parallel
    results = []
    with ThreadPoolExecutor(max_workers=NUM_SHARDS) as executor:
        futures = [
            executor.submit(
                table.query,
                KeyConditionExpression='PK = :pk',
                ExpressionAttributeValues={':pk': f'ORDERS#2024-01-23#{i}'}
            )
            for i in range(NUM_SHARDS)
        ]
        for future in as_completed(futures):
            results.extend(future.result()['Items'])
    return results
```

## 💰 Cost Modeling: On-Demand vs Provisioned

```
On-Demand Pricing:
- $1.25 per million WCU (write capacity units)
- $0.25 per million RCU (read capacity units)

Provisioned Pricing:
- $0.00065 per WCU per hour = $0.47/WCU/month
- $0.00013 per RCU per hour = $0.09/RCU/month

Break-even analysis:
- On-demand: 1M writes = $1.25
- Provisioned: 1 WCU * 720 hours * $0.00065 = $0.47/month
  1 WCU = 1 write/second = 2.6M writes/month
  2.6M writes @ provisioned = $0.47
  2.6M writes @ on-demand = $3.25

Conclusion:
- Predictable traffic > 15% utilization → Provisioned
- Spiky traffic, low average → On-Demand
- Use Auto Scaling with provisioned for best of both
```

---

# Part 5: Cassandra Production Patterns

## 🗺️ Virtual Nodes (Vnodes)

### Old Way: Static Token Ranges
```
Node A: tokens 0 - 42
Node B: tokens 43 - 85
Node C: tokens 86 - 127

Problems:
1. Adding Node D requires moving data from all others
2. If Node A is beefy, Node B is weak, uneven load
```

### New Way: Virtual Nodes
```
Node A: tokens [3, 17, 42, 88, 102]   (owns 5 vnodes)
Node B: tokens [8, 29, 55, 71, 120]  (owns 5 vnodes)
Node C: tokens [1, 33, 60, 95, 115]   (owns 5 vnodes)

Benefits:
1. Adding Node D: Steal some vnodes from each existing node
2. Rebuilding: Stream from multiple sources in parallel
3. Heterogeneous hardware: More vnodes for powerful nodes
```

### Configuration (cassandra.yaml)
```yaml
num_tokens: 16          # Vnodes per node (default: 256, but 16 is often better)
allocate_tokens_for_local_replication_factor: 3
```

## 🔧 Repair Strategies

### The Problem: Entropy
```
Writes use CL=QUORUM (2 of 3 replicas).
If one replica is down during write, it misses the data.
Over time, replicas diverge.
```

### Anti-Entropy Repair
```bash
# Full repair: Expensive, reads all data, compares checksums
nodetool repair -full

# Incremental repair: Only repairs data since last repair
nodetool repair

# Subrange repair: Repair specific token ranges (for large clusters)
nodetool repair -st <start_token> -et <end_token>
```

### Repair Scheduling
```yaml
# reaper (Cassandra Reaper) - Automated repair scheduling
schedules:
  - keyspace: my_keyspace
    tables: ["my_table"]
    scheduleDaysBetween: 7
    segmentCountPerNode: 16
    intensity: 0.5  # 50% of available resources
    repairParallelism: DATACENTER_AWARE
```

### Hinted Handoff (Short-term)
```
Node A writes with CL=QUORUM.
Node C is down.
Node A stores a "hint" locally.
When Node C comes back, Node A sends the hint.

Limitation: Hints are stored for max 3 hours (configurable).
If Node C is down > 3 hours, you need repair.
```

## 💀 Tombstone Management

### The Problem
```
DELETE FROM users WHERE user_id = 123;

This doesn't delete data. It writes a TOMBSTONE.
Tombstones are markers that say "this key is deleted".
Reading a deleted key still reads the tombstone.

Too many tombstones = slow reads = OOM on queries.
```

### Tombstone Removal: Compaction + gc_grace_seconds
```
Tombstone is kept for gc_grace_seconds (default: 10 days).
Why? To ensure all replicas see the delete before it's garbage collected.
After gc_grace_seconds, compaction removes the tombstone.
```

### Monitoring
```sql
-- Find tables with high tombstone ratios
SELECT keyspace_name, table_name, 
       live_ss_table_count, tombstones_scanned
FROM system_views.sstable_statistics
WHERE tombstones_scanned > 10000;
```

### Strategies to Reduce Tombstones
```
1. Use TTL instead of DELETE (Cassandra handles TTL'd data more efficiently)
   INSERT INTO logs (...) VALUES (...) USING TTL 86400;

2. Avoid range deletes (they create many tombstones)
   ❌ DELETE FROM logs WHERE day = '2024-01-01'
   ✅ Use table-per-day, DROP TABLE logs_2024_01_01

3. Time Window Compaction Strategy (TWCS) for time-series
   Entire SSTables become fully expired, dropped without reading
```

---

# Part 6: Production DDL Reference

## PostgreSQL: Authorization System
```sql
-- Users with extended attributes (JSONB for flexibility)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    attributes JSONB DEFAULT '{}',  -- {department, level, team}
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Partial index: Only active users for login lookup
CREATE UNIQUE INDEX idx_users_email_active 
ON users(email) 
WHERE (attributes->>'is_active')::boolean = true;

-- GIN index for attribute queries
CREATE INDEX idx_users_attrs ON users USING GIN (attributes jsonb_path_ops);

-- Query: Find all senior engineers in Platform team
SELECT * FROM users 
WHERE attributes @> '{"department": "Engineering", "team": "Platform"}'
  AND (attributes->>'level')::int >= 5;

-- BRIN index for time-series (small index, huge table)
CREATE TABLE events (
    id UUID DEFAULT gen_random_uuid(),
    event_time TIMESTAMPTZ NOT NULL,
    event_type VARCHAR(50),
    payload JSONB
) PARTITION BY RANGE (event_time);

CREATE INDEX idx_events_time ON events USING BRIN (event_time);
-- BRIN: 1MB index for 1TB table (vs 20GB B-Tree)
```

## Cloud Bigtable: Metrics System
```bash
# Table for Prometheus-style metrics
# Row key: {metric_name}#{label_hash}#{reversed_ts}
# Why label_hash? Labels like {host="a",service="b"} are high cardinality
#   Hash them to fixed 8 bytes for consistent row key size

cbt createtable metrics

# Column families
cbt createfamily metrics v    # values: float64
cbt createfamily metrics l    # labels: JSON encoded label set
cbt createfamily metrics m    # metadata: metric type, help

# GC: Keep 15 days of raw data
cbt setgcpolicy metrics v maxage=15d

# Write (Go client)
```

```go
mutation := bigtable.NewMutation()
mutation.Set("v", "value", bigtable.Now(), float64Bytes(42.5))

rowKey := fmt.Sprintf("%s#%x#%d", 
    metricName,
    hashLabels(labels),
    math.MaxInt64 - timestampMicros,  // Reversed for newest-first
)
table.Apply(ctx, rowKey, mutation)
```

## Spanner: Multi-Tenant SaaS
```sql
-- Tenant isolation at the schema level
CREATE TABLE Tenants (
    TenantId STRING(36) NOT NULL,  -- UUID
    Name STRING(255),
    Plan STRING(20),  -- 'free', 'pro', 'enterprise'
    Features ARRAY<STRING(50)>,  -- Enabled features
    CreatedAt TIMESTAMP OPTIONS (allow_commit_timestamp=true),
) PRIMARY KEY (TenantId);

-- All tenant data is interleaved
CREATE TABLE Users (
    TenantId STRING(36) NOT NULL,
    UserId STRING(36) NOT NULL,
    Email STRING(255),
    Role STRING(20),
) PRIMARY KEY (TenantId, UserId),
  INTERLEAVE IN PARENT Tenants ON DELETE CASCADE;

-- Unique email per tenant (not globally)
CREATE UNIQUE INDEX UsersByTenantEmail 
ON Users(TenantId, Email);

-- Projects are per-tenant
CREATE TABLE Projects (
    TenantId STRING(36) NOT NULL,
    ProjectId STRING(36) NOT NULL,
    Name STRING(255),
) PRIMARY KEY (TenantId, ProjectId),
  INTERLEAVE IN PARENT Tenants ON DELETE CASCADE;

-- Issues are per-project (3-level interleaving!)
CREATE TABLE Issues (
    TenantId STRING(36) NOT NULL,
    ProjectId STRING(36) NOT NULL,
    IssueId STRING(36) NOT NULL,
    Summary STRING(500),
    Status STRING(20),
) PRIMARY KEY (TenantId, ProjectId, IssueId),
  INTERLEAVE IN PARENT Projects ON DELETE CASCADE;

-- Query all issues for a tenant: ONE shard, no joins
SELECT * FROM Issues WHERE TenantId = @tenant_id;
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Row-key tested for hotspots | Load test with production traffic pattern |
| 2 | Bloom filter set to 10 bits/key | Check RocksDB/Cassandra config |
| 3 | Compaction strategy matches workload | Leveled for reads, Tiered for writes |
| 4 | Tombstone count monitored | Alert if tombstones > 10k per query |
| 5 | Interleaving used for parent-child | Spanner schema review |
| 6 | Write sharding for high-throughput keys | DynamoDB partition design |
| 7 | Repair scheduled weekly | Cassandra Reaper configured |
| 8 | Paper references understood | Team has read Bigtable/Spanner papers |

---

## 🔗 Related Documents
*   [RDBMS Internals](./rdbms-internals-guide.md) — SQL engine internals.
*   [Replication & Consistency](./replication-consistency-guide.md) — Consensus, TrueTime.
*   [Database Scaling](./database-scaling-guide.md) — Sharding patterns.
