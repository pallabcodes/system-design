# Pattern: Gossip Protocol (Membership & Failure Detection)

## Problem
Maintaining an up-to-date list of active nodes in a large, decentralized cluster without relying on a central coordinator, and detecting node failures efficiently and robustly.

## Symptoms
- Stale cluster membership info leading to misrouted requests
- "Split brain" scenarios where sub-clusters lose track of each other
- Difficulty or bottlenecks scaling a central service-discovery node (like ZooKeeper)
- Slow propagation of configuration changes across thousands of nodes

## Context
Decentralized clusters (Cassandra, Consul, Bitcoin), large-scale service discovery, peer-to-peer networks.

## Causes
- Centralized coordinators become bottlenecks or single points of failure at massive scale.
- Network partitions making central views inconsistent or unavailable.
- High overhead of broadcast messages in a large network.

## Solution
1. **Epidemic Communication**: Each node periodically picks a few random peers and exchanges state (membership, heartbeats, config).
2. **SWIM (Scalable Weakly-consistent Infection-style Process Group Membership Protocol)**: A specific protocol for fast, low-overhead membership and failure detection.
3. **Infection-style propagation**: Information spreads exponentially, reaching all nodes in O(log N) time.
4. **Indirect Pings**: If Node A can't reach Node B, it asks Node C to ping Node B before marking it as dead.

## Tradeoffs
- Eventually consistent, not strongly consistent; there's a delay before all nodes see the same state.
- Background network overhead, though usually low and bounded.
- Debugging decentralized, non-deterministic state propagation is harder than a central ledger.

## When to use
- Clusters with hundreds or thousands of nodes where centralization is impossible.
- When high availability, partition tolerance, and decentralization are prioritized over strict consistency.
- Dynamic environments where nodes frequently join and leave.

## Tags
distributed, reliability, networking, discovery, peer-to-peer

## Signals
- "decentralized node discovery"
- "split brain cluster"
- "eventual consistency membership"
- "peer-to-peer state sync"
- "detect node failure without master"

## Sources
- raw/internal/system-design-notes/gossip-protocol-guide.md
