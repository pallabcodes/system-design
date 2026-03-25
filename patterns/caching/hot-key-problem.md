# Pattern: Hot Key Problem

## Problem
A single key or a small subset of keys in a distributed datastore (like Redis or Cassandra) is accessed at a drastically higher rate than others, overwhelming the specific node that holds that data partition.

## Symptoms
- High CPU/Network utilization on a single node while others are idle
- Increased latency or timeouts specifically for the hot data
- "OOM" (Out of Memory) crashes or eviction storms on the hot node

## Context
Distributed caches, Sharded databases, Viral social media events, Flash sales.

## Causes
- Viral content (e.g., a celebrity's post) receiving millions of views.
- Shared configuration or aggregate data stored in a single key.
- Ineffective sharding strategies.

## Solution
1. **Local Caching**: Store the hot key in the application server's local memory (e.g., Guava, LRU cache) for a short duration to prevent network calls to the distributed cache.
2. **Key Duplication / Salted Sharding**: Append a random number or hash to the hot key (e.g., `key_1`, `key_2` ... `key_N`) and replicate the data across multiple nodes. Read requests randomly pick one of the duplicated keys.
3. **Read Replicas**: Add more read replica nodes to the cluster to handle the read traffic for the hot partition.

## Tradeoffs
- Local caching makes cache invalidation extremely difficult and leads to stale data.
- Key duplication requires updating multiple keys on write, complicating consistency.
- Adding read replicas doesn't solve write-heavy hot keys.

## When to use
- During high-traffic, predictable events (flash sales, celebrity announcements).
- When monitoring shows severely skewed load distribution across a cluster.

## Tags
caching, scalability, distributed-systems, hot-spot

## Signals
- "redis node cpu 100%"
- "single partition overloaded"
- "viral traffic spike"
- "hot key problem"
- "sharding skewed load"

## Sources
- General Knowledge
