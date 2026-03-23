# Pattern: Consistent Hashing

## Problem
Distributing data or requests across a dynamic set of nodes (N) such that adding or removing a node (N+1 or N-1) results in minimal data movement. Traditional hashing (`hash(key) % N`) causes nearly 100% of keys to be remapped when the number of nodes changes, causing massive disruptions.

## Symptoms
- Massive cache misses after scaling a cluster up or down
- Excessive data migration/reshuffling between nodes during deployments
- Uneven distribution of load ("Hot Spots") on specific nodes
- Cluster instability during auto-scaling events

## Context
Distributed Caches (Redis Cluster, Memcached), Distributed Databases (Cassandra, DynamoDB, Riak), Load Balancers, Distributed Storage.

## Causes
- Traditional modulo hashing heavily depends on the exact total number of nodes.
- Unpredictable node failures or intentional scaling events changing the node count.

## Solution
1. **Hash Ring**: Map both the node identifiers and the data keys onto a large circular numerical space (e.g., 0 to 2^32-1).
2. **Clockwise Assignment**: A key is assigned to the first node encountered by moving clockwise on the ring from the key's hashed position.
3. **Virtual Nodes (VNodes)**: Map each physical node to multiple artificial points on the ring to ensure uniform distribution of keys and better load balancing.

## Tradeoffs
- More complex implementation and key lookup (requires traversing a sorted list or binary search tree) compared to simple modulo.
- VNodes require extra memory to store the routing table and management overhead.
- "Minimal" data movement still involves *some* data movement, which can cause temporary spikes.

## When to use
- Distributed systems that need to scale up or down without massive performance hits.
- Caching layers where a full cache flush (due to remapping) would take down the backend database.
- Sharding data across heterogeneous nodes (assign more VNodes to more powerful machines).

## Tags
distributed, scalability, performance, hashing, sharding, load-balancing

## Signals
- "massive cache miss on scale"
- "data rebalancing storm"
- "hot spot on one node"
- "minimal key remapping"
- "smooth scaling for cache"

## Sources
- raw/internal/system-design-notes/consistent-hashing-guide.md
