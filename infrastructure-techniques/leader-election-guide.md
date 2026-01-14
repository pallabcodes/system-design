# Leader Election: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Bully Algorithm, Split-Brain, Fencing Tokens, and Lease Patterns.

> [!IMPORTANT]
> **The Principal Law**: **Avoid Leader Election if possible**. It introduces a Single Point of Failure (SPOF) and complex concurrency bugs.
> **Better**: Idempotent Consumers or Partitioned Workloads (Sharding) where each node owns a slice, rather than one node owning everything.

---

## 🧠 Core Algorithms

### 1. The Bully Algorithm
*   **Logic**: "I am the biggest ID. I am the Boss."
*   **Process**:
    1.  Node A notices Leader is dead.
    2.  Node A sends "Election" to all IDs > A.
    3.  If no one replies, A declares victory.
*   **Pro**: Simple.
*   **Con**: High network traffic. If the highest ID node is "flapping" (up/down), it constantly bullies everyone and triggers re-elections.

### 2. Lease-Based Election (The Industry Standard)
Used by Kubernetes, Etcd, ZooKeeper.

*   **Logic**: "I hold the lock for 10 seconds. I will renew it every 3 seconds."
*   **Mechanism**:
    *   Row in DB: `leader_lock` (Owner: NodeA, Expires: 12:00:10).
    *   NodeA acts as leader.
    *   If NodeA acts slow and doesn't renew by 12:00:10, NodeB overwrites the row via CAS (Compare-And-Swap).
*   **Pro**: Robust, relies on external truth (DB/Etcd).

---

## 🛡️ The Split-Brain Problem

What if Node A acts as Leader, but the Network blocked its renewal packet?
Node B becomes Leader.
**Now both Node A and Node B think they are Leader.**
They both write to the database. Data Corruption occurs.

### Solution: Fencing Tokens
1.  Every time a Leader is elected, the Lock Service (ZooKeeper) gives an incrementing `epoch` ID (1, 2, 3...).
2.  Leader 1 (epoch 1) tries to write to DB.
3.  Leader 2 (epoch 2) wakes up and writes to DB.
4.  DB sees epoch 2. Records it internal "max_epoch = 2".
5.  Leader 1 (Zombie) wakes up and tries to write with epoch 1.
6.  DB rejects write: "Epoch 1 < Max Epoch 2".

> [!TIP]
> **You cannot implement Fencing Tokens without Storage support**. The Storage (DB/Filesystem) must check the token.

---

## ✅ Principal Architect Checklist

1.  **TTL Awareness**: Your lease TTL is 10s. Your Garbage Collection pause is 15s. You wake up, think you are leader, but you lost the lock 5s ago. **Check the clock** after every sleep/pause.
2.  **Step Down**: If you fail to renew the lease, immediately stop processing. Crash yourself if necessary. Fail fast.
3.  **Minimum Fleet**: Leader Election usually requires Quorum (Majority). You need 3 nodes to survive 1 failure. You need 5 nodes to survive 2 failures.

---

## 🔗 Related Documents
*   [Distributed Systems Theory](../distributed-systems-theory.md) — Paxos/Raft integration.
*   [Database Sharding](../../sharding-techniques-and-notes/sharding-architecture-guide.md) — Alternative to global leaders.
