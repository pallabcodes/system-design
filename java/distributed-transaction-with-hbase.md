# Distributed Transaction with HBase

Based on the provided transcript, here is an accurate and comprehensive extraction of the video "Bringing Distributed Transactions to HBase" by Alex Baranau, from start to end.

### **Introduction and Motivation**
Alex Baranau, a software engineer at Cask (formerly Continuity), introduces the topic of bringing transaction support to Apache HBase. He explains that Continuity built "Reactor," a Hadoop application server designed to help Java developers build Big Data applications.

**Why Transactions are Needed:**
1.  **Simplification:** Transactions make developing Big Data applications significantly easier and simplify integration with existing systems.
2.  **Real-Time Processing (Flows):** The application server uses "Flows" (real-time components) consisting of "Flowlets" connected by queues. These units process data and access persistent storage (HBase).
3.  **Shared Data Conflicts:** Different flows may access and modify the same data concurrently. To ensure data consistency, the system needs to detect conflicts, handle failures, retry processing, and guarantee "exactly-once" processing.
4.  **The Solution:** Wrap the consumption from a queue, the writing to the next queue, and all HBase data operations into a single **ACID transaction** (Atomic, Consistent, Isolated, Durable).

**Why HBase Needs Transaction Support:**
HBase is a non-relational, distributed, columnar database. While it provides some atomic operations (row-level atomicity, check-and-put, single-region batching), it lacks:
*   **Cross-Region Atomicity:** You cannot update rows across different regions atomically.
*   **Cross-Table Atomicity:** No multi-table transaction support.
*   **Multi-RPC Atomicity:** You cannot perform read-modify-write operations across multiple remote procedure calls (RPCs) atomically.

**Additional Use Cases for Transactions:**
*   **Secondary Indexes:** Updating a data table and a separate index table atomically.
*   **Performance Optimization:** Applying writes in batches improves performance. Transactions allow using the client-side buffer reliably; if the client crashes before flushing the full buffer, the transaction ensures partial data isn't committed.

### **Implementation Approach**
The implementation uses a mix of **Multi-Version Concurrency Control (MVCC)** and **Optimistic Concurrency Control (OCC)**.

*   **MVCC:** Leverages HBase’s native ability to store multiple versions of a cell. The system overrides the timestamp of the cell with a **Transaction ID**. This allows readers to filter data based on visibility (isolation).
*   **OCC:** Conflict detection is deferred until commit time. This avoids the high cost of locking. It assumes the application is designed to minimize conflicts (via partitioning). If a conflict is detected, the transaction is rolled back.

### **Architecture**
The system consists of three main components:
1.  **Transaction Manager (TM):** A central service (orchestrated by ZooKeeper for High Availability) that manages transaction state.
2.  **Client:** Talks to the TM to get transaction state and performs writes to HBase.
3.  **HBase:** Stores the data using Transaction IDs as timestamps.

### **The Transaction Lifecycle**
1.  **Start:** The client requests a new transaction from the TM. The TM adds it to an "In-Progress" list and returns the state (Write Pointer, Read Pointer, Excludes).
2.  **Execution:** The client writes to HBase using the Transaction ID as the timestamp.
3.  **Commit:** The client sends a list of changes (rows, tables, or prefixes) to the TM.
4.  **Conflict Detection:** The TM checks if any overlapping transactions updated the same data.
    *   **Success:** The transaction is moved to the "Complete" list.
    *   **Conflict:** The client attempts to **Rollback** (delete the writes from HBase). If rollback succeeds, it is treated as complete (no junk left).
    *   **Fatal Error (Rollback Fails):** If the client cannot rollback (e.g., HBase crash), the transaction is added to the **"Invalid" list**. This data is considered "junk" and must be ignored by future readers.

### **Transaction Manager Internals**
*   **Pointers:** The TM maintains a **Read Pointer** (all transactions up to this ID are committed) and a **Write Pointer** (monotonically increasing ID for new transactions).
*   **State Lists:** It keeps lists for In-Progress, Committed, and Invalid transactions.
*   **Storage:** The state is kept **in-memory** for speed. It is not a single point of failure because it writes a **Write-Ahead Log (WAL)** to HDFS.
*   **Snapshots:** To speed up recovery and avoid replaying a massive log, the TM periodically (asynchronously) writes a full state snapshot to HDFS and rotates the logs.

### **Data Cleanup (The Janitor)**
Over time, "Invalid" transactions and old versions of data accumulate as junk in HBase.
*   **Solution:** A **Region Observer Coprocessor** is used for cleanup.
*   **Mechanism:** The Coprocessor accesses the TM snapshots (refreshed periodically, e.g., every 5 minutes).
*   **Execution:** During **MemStore flushes** and **Compactions**, the Coprocessor filters the data.
    *   If data belongs to an Invalid transaction -> **Drop it**.
    *   If data is old and no longer visible to any active transaction -> **Drop it**.
*   **Version Pruning:** Unlike standard HBase `maxVersions`, this system keeps only the versions necessary for currently running transactions (based on the global minimal read pointer) and prunes the rest.

### **Timestamp Handling and TTL**
*   **The Problem:** Standard HBase timestamps are in milliseconds (limiting throughput to 1,000 tx/sec if used directly).
*   **The Encoding:** Transaction IDs are encoded as: `(CurrentTime * 1,000,000) + counter`. This supports 1 billion transactions per second.
*   **Time-To-Live (TTL):** Because HBase timestamps are hijacked for Transaction IDs, native HBase TTL features are broken and must be turned off. TTL logic is re-implemented inside the cleanup Coprocessor and applied during reads.

### **Batch Job Integration (MapReduce)**
*   **Challenge:** Batch jobs are long-running and multi-step. Standard MapReduce guarantees atomicity on HDFS files, but not on HBase.
*   **Strategy:** The entire batch job is wrapped in a single transaction.
*   **Conflict Resolution:** Due to the volume of data, conflict detection and rollback are too expensive for batch jobs.
    *   **Policy:** Often configured so "last write wins" (no conflict detection) or simple invalidation.
*   **Failure Handling:** If a job fails, the transaction is marked **Invalid**. The cleanup Coprocessor removes the partial data later.
*   **Future:** Support for **Nested Transactions** (child transactions visible to the parent, committed as a group).

### **Overhead and Performance**
*   **Cost:** The primary overhead is **2 RPC calls** to the Transaction Manager (Start and Commit).
*   **Efficiency:** Because the TM is in-memory, these RPCs are fast. The overhead is estimated at **2-4%**.
*   **Optimization:** Clients can batch requests (e.g., start 100 transactions in one RPC).
*   **Relaxed Guarantees:** Users can bypass the TM for certain writes. Readers will still see the data as the "latest" version.

### **Future Plans**
*   **Open Source:** They plan to open source the technology (Apache Tephra) under the Apache 2.0 license.
*   **Scaling:** Partitioning transaction management to support higher scale.
*   **Other Data Stores:** Extending support to HDFS files and other stores via two-phase commit.

### **Q&A Session Highlights**
*   **Atomic Batch Semantics:** The approach restores the "all or nothing" semantics of MapReduce when applied to HBase.
*   **Deployment:** The Transaction Manager creates a WAL on HDFS.
*   **Conflict Resolution Granularity:** The client decides what to report to the TM for conflict detection (Table level, Row level, or prefixes). If a client knows data is partitioned (no overlap), it can report nothing to avoid overhead.
*   **Invalid Data:** If a transaction spans multiple regions and fails, the invalid records are cleaned up independently by the Coprocessors on each region server using the shared transaction snapshot.