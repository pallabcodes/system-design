# Replication & Consistency: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Leader-Follower, Multi-Leader, Quorums, and Conflict Resolution.

> [!IMPORTANT]
> **The Principal Law**: **Replication is mostly for Availability, not Speed**.
> Adding replicas makes reads faster but writes slower (if synchronous) or risky (if asynchronous). The speed of light is the hard limit.

---

## 📡 Replication Topologies

### 1. Leader-Follower (Master-Slave)
*   **Write**: Only to Leader.
*   **Read**: Leader or Followers.
*   **Sync vs Async**:
    *   **Sync**: `Write -> Leader -> Follower -> Ack -> User`. Safe but slow. If follower dies, write fails.
    *   **Async**: `Write -> Leader -> User`. Fast but risky. Leader dies, data lost.
*   **Issue**: **Replication Lag**. `Read-Your-Writes` consistency is not guaranteed on followers.

### 2. Multi-Leader (Master-Master)
*   **Write**: To any Leader (DC1 or DC2).
*   **Pro**: Survivability of Data Centers. Offline clients (Git).
*   **Con**: **Conflicts**. User A writes "Title=A" in DC1. User B writes "Title=B" in DC2. Who wins?

### 3. Leaderless (Dynamo-style)
*   **Write**: Send to all N nodes. Wait for W acknowledgments.
*   **Read**: Query all N nodes. Wait for R responses.
*   **Quorum Rule**: If `R + W > N`, you are guaranteed to read the latest write.

---

## ⚔️ Conflict Resolution Strategies

When Multi-Leader or Leaderless systems disagree:

1.  **LWW (Last Write Wins)**: Rely on timestamps.
    *   *Problem*: Clock Skew. CPU clocks drift. You might drop valid data.
2.  **Vector Clocks**: Track causality. `(NodeA: 1, NodeB: 2)`.
    *   *Result*: "These writes are simultaneous siblings".
    *   *Action*: Force the Application/User to merge them (like a Git conflict).
3.  **CRDTs (Conflict-Free Replicated Data Types)**: Data structures that mathematically merge correctly.
    *   *Example*: Counters, Sets (G-Set, OR-Set).

---

## ✅ Principal Architect Checklist

1.  **Monotonic Reads**: Ensure a user doesn't see time go backward. Standard solution: Sticky Sessions (User always reads from same replica).
2.  **Replication Lag Monitoring**: Don't just check "Is replica up?". Check "Replica Lag Bytes". If lag > 100MB, pull it out of rotation.
3.  **Failover Automations**: Be careful. "False Positive" failover causes split-brain. Sometimes a manual switch is safer than a flaky automated one.

---

## 🔗 Related Documents
*   [Consistency Models](../../../infrastructure-techniques/distributed-systems-patterns-comprehensive.md) — CAP Theorem.
*   [DATABASE - Scaling](../database-scaling-guide.md) — Scaling patterns.
