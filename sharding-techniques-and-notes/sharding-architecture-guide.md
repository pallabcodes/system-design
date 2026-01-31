# Database Sharding: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Consistent Hashing (Virtual Nodes), Resharding Storms, and Data Skew.

> [!IMPORTANT]
> **The Principal Law**: **Sharding is the last resort**. If you can scale vertically, do it. Sharding introduces CAP theorem complexity to your database layer.

## What is Sharding?

**Database sharding** is a technique that partitions a database across multiple servers/nodes to handle increased load and improve performance.

### Visual 1: What is Sharding?

```
┌─────────────────────────────────────────────────────────────┐
│                    BEFORE SHARDING                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                    SINGLE DATABASE                      │ │
│  │                                                         │ │
│  │  📊 1TB Data, 10M Users                                │ │
│  │  🔥 Overloaded, Slow Queries                           │ │
│  │  ❌ Single Point of Failure                            │ │
│  │  💰 Expensive Vertical Scaling                         │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                             │
│  ❌ PROBLEMS:                                               │
│  • Query time: 5-10 seconds                               │
│  • Storage limit: 2TB max                                 │
│  • No fault tolerance                                     │
│  • Expensive scaling                                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    AFTER SHARDING                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │
│  │ Shard 1 │ │ Shard 2 │ │ Shard 3 │ │ Shard 4 │           │
│  │         │ │         │ │         │ │         │           │
│  │ 250GB   │ │ 250GB   │ │ 250GB   │ │ 250GB   │           │
│  │ 2.5M    │ │ 2.5M    │ │ 2.5M    │ │ 2.5M    │           │
│  │ Users   │ │ Users   │ │ Users   │ │ Users   │           │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘           │
│                                                             │
│  ✅ BENEFITS:                                               │
│  • Query time: 0.5-1 second                               │
│  • Total capacity: 10TB+                                  │
│  • Fault tolerance                                        │
│  • Cost-effective scaling                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 🧠 God Mode: The Math of Sharding

Principal Architects don't just "shard"; they deal with the **Statistical Variance** of sharding.

### 1. The Virtual Node Factor
Why does Consistent Hashing need "Virtual Nodes"?
*   **Problem**: With only 4 physical nodes on a ring, if Node A dies, Node B takes 100% of Node A's load. Node B creates a hotspot and dies. (Cascading Failure).
*   **Solution**: Divide Node A into 200 "Virtual Nodes" scattered randomly on the ring.
*   **Math**: With 200 vNodes, standard deviation of load is ~5%. With 1 vNode, it's ~50%.
*   **Impact**: When Node A dies, its load is evenly split among B, C, and D.

### 2. The Resharding Storm
Why does resharding kill your database?
*   **Scenario**: Moving from 10 shards to 11 shards.
*   **Naive Hashing**: `hash(id) % 10` vs `hash(id) % 11`. Almost **100% of keys** move locations.
*   **Consistent Hashing**: Only `1/N` keys move.
*   **Bandwidth Saturation**: Moving terabytes of data saturates the NIC. Your "Live" queries handle 0 traffic because the NIC is 100% busy copying data.
*   **Mitigation**: Use **Throttle** on migration bandwidth (e.g., 50MB/s limit).

---

## How Sharding Works

1. **Data Partitioning**: Your database data is split into smaller chunks called **logical shards**
2. **Distribution**: These logical shards are distributed across different database nodes called **physical shards**
3. **Independence**: Each shard operates independently and doesn't share data or resources with other shards

### Visual 2: How Sharding Works

```
┌─────────────────────────────────────────────────────────────┐
│                    SHARDING PROCESS                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  📊 STEP 1: DATA PARTITIONING                              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Original Data: 1TB, 10M Users                          │ │
│  │                                                         │ │
│  │  🔄 Split into Logical Shards                          │ │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐     │ │
│  │  │ Shard A │ │ Shard B │ │ Shard C │ │ Shard D │     │ │
│  │  │ 250GB   │ │ 250GB   │ │ 250GB   │ │ 250GB   │     │ │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘     │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                             │
│  🏗️  STEP 2: PHYSICAL DISTRIBUTION                        │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│  │ Server  │    │ Server  │    │ Server  │    │ Server  │ │
│  │ 1       │    │ 2       │    │ 3       │    │ 4       │ │
│  │         │    │         │    │         │    │         │ │
│  │  📊     │    │  📊     │    │  📊     │    │  📊     │ │
│  │ Shard A │    │ Shard B │    │ Shard C │    │ Shard D │ │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘ │
│                                                             │
│  🔄 STEP 3: INDEPENDENT OPERATION                          │
│  • Each shard operates independently                       │
│  • No shared resources between shards                      │
│  • Parallel processing capabilities                        │
└─────────────────────────────────────────────────────────────┘
```

## Application Layer Sharding Techniques

### Visual 3: Hash-Based Sharding

```
┌─────────────────────────────────────────────────────────────┐
│                    HASH-BASED SHARDING                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  🔧 SHARDING FUNCTION: hash(user_id) % NUM_SHARDS          │
│                                                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│  │ Shard 0 │    │ Shard 1 │    │ Shard 2 │    │ Shard 3 │ │
│  │         │    │         │    │         │    │         │ │
│  │ hash(4) │    │ hash(1) │    │ hash(2) │    │ hash(3) │ │
│  │ % 4 = 0 │    │ % 4 = 1 │    │ % 4 = 2 │    │ % 4 = 3 │ │
│  │         │    │         │    │         │    │         │ │
│  │ User 4  │    │ User 1  │    │ User 2  │    │ User 3  │ │
│  │ User 8  │    │ User 5  │    │ User 6  │    │ User 7  │ │
│  │ User 12 │    │ User 9  │    │ User 10 │    │ User 11 │ │
│  │ User 16 │    │ User 13 │    │ User 14 │    │ User 15 │ │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘ │
│                                                             │
│  ✅ BENEFITS:                                               │
│  • Even data distribution                                  │
│  • Simple implementation                                   │
│  • Predictable shard location                              │
│                                                             │
│  ❌ CHALLENGES:                                             │
│  • Difficult to reshard                                    │
│  • No geographic affinity                                  │
│  • Range queries inefficient                               │
└─────────────────────────────────────────────────────────────┘
```

### Visual 4: Range-Based Sharding

```
┌─────────────────────────────────────────────────────────────┐
│                    RANGE-BASED SHARDING                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  📊 SHARDING BY USER_ID RANGES                             │
│                                                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│  │ Shard 1 │    │ Shard 2 │    │ Shard 3 │    │ Shard 4 │ │
│  │         │    │         │    │         │    │         │ │
│  │ 1-      │    │ 2500001-│    │ 5000001-│    │ 7500001-│ │
│  │ 2500000 │    │ 5000000 │    │ 7500000 │    │ 10000000│ │
│  │         │    │         │    │         │    │         │ │
│  │ User 1  │    │ User    │    │ User    │    │ User    │ │
│  │ User 2  │    │ 2500001 │    │ 5000001 │    │ 7500001 │ │
│  │ User 3  │    │ User    │    │ User    │    │ User    │ │
│  │ ...     │    │ 2500002 │    │ 5000002 │    │ 7500002 │ │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘ │
│                                                             │
│  ✅ BENEFITS:                                               │
│  • Efficient range queries                                 │
│  • Easy to understand                                      │
│  • Good for sequential data                                │
│                                                             │
│  ❌ CHALLENGES:                                             │
│  • Uneven data distribution                                │
│  • Hotspots possible                                       │
│  • Resharding complexity                                   │
└─────────────────────────────────────────────────────────────┘
```

### Visual 5: Directory-Based Sharding

```
┌─────────────────────────────────────────────────────────────┐
│                    DIRECTORY-BASED SHARDING                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  🗂️  SHARD LOOKUP SERVICE                                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                    SHARD DIRECTORY                      │ │
│  │                                                         │ │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐     │ │
│  │  │ user_id │ │ shard_id│ │ location│ │ status │     │ │
│  │  ├─────────┤ ├─────────┤ ├─────────┤ ├─────────┤     │ │
│  │  │ user_123│ │ shard_1 │ │ east    │ │ active │     │ │
│  │  │ user_456│ │ shard_2 │ │ west    │ │ active │     │ │
│  │  │ user_789│ │ shard_3 │ │ europe  │ │ active │     │ │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘     │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                             │
│  🔄 REQUEST FLOW:                                          │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐                │
│  │ Client  │    │ Shard   │    │ Target  │                │
│  │ Request │    │ Lookup  │    │ Shard   │                │
│  │         │    │ Service │    │         │                │
│  │  📤     │    │  🔍     │    │  📊     │                │
│  └─────────┘    └─────────┘    └─────────┘                │
│                                                             │
│  ✅ BENEFITS:                                               │
│  • Maximum flexibility                                     │
│  • Easy resharding                                         │
│  • Complex business rules                                  │
│                                                             │
│  ❌ CHALLENGES:                                             │
│  • Additional latency                                      │
│  • Directory service SPOF                                  │
│  • Complex management                                      │
└─────────────────────────────────────────────────────────────┘
```

### Visual 6: Consistent Hashing

```
┌─────────────────────────────────────────────────────────────┐
│                    CONSISTENT HASHING                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  🔄 HASH RING WITH VIRTUAL NODES                           │
│                                                             │
│                    ┌─────────┐                             │
│                   │ Shard A │                             │
│                  └─────────┘                              │
│                 /           \                             │
│        ┌─────────┐         ┌─────────┐                    │
│       │ Shard D │         │ Shard B │                    │
│      └─────────┘         └─────────┘                     │
│     /           \       /           \                    │
│  ┌─────────┐   ┌─────────┐         ┌─────────┐           │
│  │ Shard C │   │ Shard A │         │ Shard C │           │
│  └─────────┘   └─────────┘         └─────────┘           │
│     \           \       \           \                    │
│      └─────────┘         └─────────┘                     │
│       │ Shard D │         │ Shard B │                    │
│       └─────────┘         └─────────┘                     │
│                \           /                             │
│                 └─────────┘                              │
│                   │ Shard A │                             │
│                   └─────────┘                             │
│                                                             │
│  🎯 KEY PLACEMENT:                                         │
│  • User data placed clockwise from hash position          │
│  • Minimal data movement when adding/removing shards      │
│  • Even distribution with virtual nodes                   │
└─────────────────────────────────────────────────────────────┘
```

## Database Layer Sharding Techniques

### Visual 7: Algorithmic vs Dynamic Sharding

```
┌─────────────────────────────────────────────────────────────┐
│                    ALGORITHMIC SHARDING                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  🔧 CLIENT-SIDE SHARDING                                   │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐                │
│  │ Client  │    │ Sharding│    │ Target  │                │
│  │ App     │    │ Function│    │ Shard   │                │
│  │         │    │         │    │         │                │
│  │  📤     │    │  🔧     │    │  📊     │                │
│  │ Request │    │ hash()%N│    │ Data    │                │
│  └─────────┘    └─────────┘    └─────────┘                │
│                                                             │
│  ✅ BENEFITS:                                               │
│  • No lookup service needed                               │
│  • Fast routing                                            │
│  • Simple implementation                                   │
│                                                             │
│  ❌ CHALLENGES:                                             │
│  • Difficult resharding                                    │
│  • Limited flexibility                                     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    DYNAMIC SHARDING                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  🗂️  EXTERNAL LOCATOR SERVICE                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐                │
│  │ Client  │    │ Locator │    │ Target  │                │
│  │ App     │    │ Service │    │ Shard   │                │
│  │         │    │         │    │         │                │
│  │  📤     │    │  🔍     │    │  📊     │                │
│  │ Request │    │ Lookup  │    │ Data    │                │
│  └─────────┘    └─────────┘    └─────────┘                │
│                                                             │
│  ✅ BENEFITS:                                               │
│  • Maximum flexibility                                     │
│  • Easy resharding                                         │
│  • Complex routing rules                                   │
│                                                             │
│  ❌ CHALLENGES:                                             │
│  • Additional latency                                      │
│  • Locator service SPOF                                    │
└─────────────────────────────────────────────────────────────┘
```

## Sharding Strategies Comparison

### Visual 8: Sharding Strategy Comparison

```
┌─────────────────────────────────────────────────────────────┐
│                    SHARDING STRATEGIES COMPARISON           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  📊 PERFORMANCE COMPARISON                                 │
│                                                             │
│  Strategy          │ Complexity │ Flexibility │ Resharding │
│  ──────────────────┼────────────┼─────────────┼────────────┤
│  Hash-based        │    Low     │     Low     │   Hard     │
│  Range-based       │   Medium   │   Medium    │  Medium    │
│  Directory-based   │    High    │    High     │   Easy     │
│  Consistent Hash   │   Medium   │   Medium    │   Easy     │
│                                                             │
│  🎯 USE CASE RECOMMENDATIONS:                              │
│                                                             │
│  🔧 Hash-based:                                            │
│  • Key-value stores                                        │
│  • Uniform data distribution                               │
│  • Simple applications                                     │
│                                                             │
│  📊 Range-based:                                           │
│  • Time-series data                                        │
│  • Sequential access patterns                              │
│  • Geographic data                                         │
│                                                             │
│  🗂️  Directory-based:                                      │
│  • Complex business rules                                  │
│  • Multi-tenant applications                               │
│  • Flexible requirements                                   │
│                                                             │
│  🔄 Consistent Hash:                                       │
│  • Dynamic scaling                                         │
│  • Cache systems                                           │
│  • Load balancing                                          │
└─────────────────────────────────────────────────────────────┘
```

## Performance Impact Visualization

### Visual 9: Performance Before vs After Sharding

```
┌─────────────────────────────────────────────────────────────┐
│                    PERFORMANCE IMPACT                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  📈 QUERY PERFORMANCE                                      │
│                                                             │
│  BEFORE SHARDING:                                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Single Database: 1TB, 10M Users                        │ │
│  │                                                         │ │
│  │  🔍 SELECT * FROM users WHERE country = 'US'          │ │
│  │  ⏱️  Time: 5-10 seconds                               │ │
│  │  📊 Scans: 10M records                                 │ │
│  │  💾 Memory: 8GB+                                       │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                             │
│  AFTER SHARDING:                                           │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ 4 Shards: 250GB each, 2.5M Users per shard            │ │
│  │                                                         │ │
│  │  🔍 SELECT * FROM users WHERE country = 'US'          │ │
│  │  ⏱️  Time: 0.5-1 second                               │ │
│  │  📊 Scans: 2.5M records (parallel)                    │ │
│  │  💾 Memory: 2GB per shard                             │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                             │
│  🚀 PERFORMANCE IMPROVEMENTS:                              │
│  • Query time: 10x faster                                 │
│  • Memory usage: 4x less per shard                        │
│  • Parallel processing: 4x throughput                     │
│  • Scalability: Unlimited                                 │
└─────────────────────────────────────────────────────────────┘
```

## Sharding Implementation Checklist

### Visual 10: Sharding Implementation Guide

```
┌─────────────────────────────────────────────────────────────┐
│                    SHARDING IMPLEMENTATION CHECKLIST        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  🔍 PHASE 1: ANALYSIS                                      │
│  ✅ Identify scaling bottlenecks                           │
│  ✅ Analyze data access patterns                           │
│  ✅ Determine shard key candidates                         │
│  ✅ Estimate data growth                                   │
│                                                             │
│  🏗️  PHASE 2: DESIGN                                       │
│  ✅ Choose sharding strategy                               │
│  ✅ Design shard key                                       │
│  ✅ Plan data distribution                                 │
│  ✅ Design routing logic                                   │
│                                                             │
│  🔧 PHASE 3: IMPLEMENTATION                                │
│  ✅ Implement sharding logic                               │
│  ✅ Create data migration scripts                          │
│  ✅ Build monitoring tools                                 │
│  ✅ Test with sample data                                  │
│                                                             │
│  🚀 PHASE 4: DEPLOYMENT                                    │
│  ✅ Deploy sharded infrastructure                          │
│  ✅ Migrate data incrementally                             │
│  ✅ Monitor performance                                    │
│  ✅ Validate functionality                                 │
│                                                             │
│  📊 PHASE 5: OPTIMIZATION                                  │
│  ✅ Fine-tune shard distribution                           │
│  ✅ Optimize queries                                       │
│  ✅ Implement caching                                      │
│  ✅ Plan for future scaling                                │
└─────────────────────────────────────────────────────────────┘
```

This comprehensive visual guide covers both application layer and database layer sharding techniques, providing clear visual representations of complex concepts and practical implementation guidance.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
The math of sharding never changes. However, **NewSQL** databases (TiDB, CockroachDB) now handle this essentially "under the hood" so you don't have to implement it in your application code.

**Is it scalable?**
**Yes.**

**What would the architecture look like today?**
1.  **Use Vitess:** If running MySQL at scale, use **Vitess**. It automates the sharding/resharding described in this guide.
2.  **Serverless Sharding:** Use **CockroachDB Serverless** or **Neon**, where the "shards" are managed dynamically by the vendor, and you just see a single Postgres endpoint.
