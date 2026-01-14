# RDBMS Internals: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: B+Trees, Write Ahead Log (WAL), Isolation Levels, and MVCC.

> [!IMPORTANT]
> **The Principal Law**: **The Disk is the Truth**. In a database, if it's not fsync'd to disk, it didn't happen.
> **ACID is not free**: Atomicity requires Undo Logs. Durability requires Redo Logs (WAL). Isolation requires Locks/MVCC. Consistency requires Constraints.

---

## 🌳 Data Structures: B+Tree vs LSM

### 1. B+Tree (Read Optimized)
Used by: PostgreSQL, MySQL (InnoDB), Oracle.
*   **Structure**: Balanced Tree. Data is stored only in leaf nodes.
*   **Read**: `O(log N)` random IO. Very fast.
*   **Write**: Random IO. Can be slow because you have to jump around the disk to update leaf pages.
*   **Page**: The limitation unit (usually 8KB or 16KB).

### 2. The WAL (Write Ahead Log)
**Rule**: Never write to the B-Tree before writing to the Append-Only Log.
*   **Why?**: Writing to random B-Tree pages is dangerous (what if power fails?). Writing to the end of a log file is safe and fast (Sequential IO).
*   **Crash Recovery**: On reboot, replay the WAL to reconstruct the B-Tree state.

---

## 🛡️ ACID & Isolation Levels

The database is not a magic black box; it's a trade-off machine.

| Isolation Level | Dirty Read? | Non-Repeatable Read? | Phantom Read? | Perf Cost |
| :--- | :--- | :--- | :--- | :--- |
| **Read Uncommitted** | Yes | Yes | Yes | Low |
| **Read Committed** | No | Yes | Yes | Medium (Default PG) |
| **Repeatable Read** | No | No | Yes | High (Default MySQL) |
| **Serializable** | No | No | No | Very High |

### MVCC (Multi-Version Concurrency Control)
How do we read without blocking writers?
*   **Concept**: Every row has a `created_tx_id` and `deleted_tx_id`.
*   **Reader**: "Show me rows where `created_tx_id` <= My TxID AND `deleted_tx_id` > My TxID."
*   **Result**: Readers don't block Writers. Writers don't block Readers.

---

## ⚡ Performance Tuning (Principal View)

1.  **Vacuuming**: MVCC leaves dead tuples (ghost rows). You MUST clean them up, or your table scan reads 90% garbage.
2.  **Fill Factor**: Don't pack B-Tree pages 100% full. Leave room (e.g., 80%) so updates don't cause massive "Page Splits".
3.  **Buffer Pool**: The database implementation of PageCache. Bypasses the OS Cache for better control.

---

## ✅ Principal Architect Checklist

1.  **Index Selectivity**: An index on `gender` (M/F) is useless (Selectivity 50%). An index on `UUID` is perfect (Selectivity 100%).
2.  **Covering Index**: `SELECT name FROM users WHERE age > 21`. If you have dynamic index `(age, name)`, the DB never touches the Heap (Table). It answers solely from the Index.
3.  **Connection Pooling**: Connecting is expensive (Process Fork). Use PgBouncer.

---

## 🔗 Related Documents
*   [NoSQL Architecture](./nosql-architecture-guide.md) — The write-optimized alternative.
*   [Replication & Consistency](./replication-consistency-guide.md) — Scaling out.
