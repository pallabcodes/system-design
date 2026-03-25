Resource: https://youtu.be/5ZjhNTM8XU8?list=TLGGcPyrT_hUu9YyMjAyMjAyNg


Based on the transcript of the video "Transactions: myths, surprises and opportunities" by Martin Kleppmann, here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Context**
Martin Kleppmann introduces the talk with alternative titles he considered, such as "Transactions: Joys, Challenges, and Misery," reflecting that researching consistency guarantees drove him "a little bit insane." The talk is based on research for Chapter 7 of his book, *Designing Data-Intensive Applications*.

### **History of Transactions**
He traces the origin of transactions back to the mid-1970s at IBM with **System R**, the first SQL database. This system laid the groundwork for relational databases for the next 30 years. When the NoSQL movement emerged in the late 2000s, followed by "NewSQL," the core differentiator was not the query language (SQL) but the transactional guarantees offered by the databases.

### **Deconstructing ACID**
Kleppmann breaks down the ACID acronym, citing Eric Brewer’s comment that the term is "more mnemonic than precise."

**1. Durability (D)**
Historically, this meant writing the transaction log to archive tape. As technology evolved, it meant `fsync`-ing to disk to prevent data loss during crashes. More recently, it is often associated with replication.

**2. Consistency (C)**
Kleppmann emphasizes that the "C" in ACID is **not** the same as the "C" in the CAP theorem.
*   In ACID, Consistency refers to the database moving from one valid state to another, adhering to invariants (e.g., in an accounting system, credits must equal debits).
*   Unlike A, I, and D, Consistency is actually a property of the **application**, not the database. Joe Hellerstein suggested "C" was tossed in just to make the acronym work.

**3. Atomicity (A)**
This is often confused with concurrency (atomic operations in multi-threading). In the context of ACID, Atomicity refers to **fault handling**.
*   It ensures "all or nothing" execution.
*   Kleppmann suggests a better term would be **Abortability**. It allows a system to collapse all types of faults (crashes, network issues, deadlocks) into a single concept: the **Abort**. If a transaction aborts, all partial changes are rolled back.

**4. Isolation (I)**
This is the most complex component.
*   Ideally, it implies **Serializability**: transactions appear to execute serially (one after another), even if they run concurrently.
*   In practice, databases implement weaker isolation levels (Read Committed, Repeatable Read) based on 1970s implementation details (locking strategies) rather than intuitive definitions.
*   Kleppmann notes that very few people can accurately explain the difference between "Read Committed" and "Repeatable Read," yet they are expected to choose between them.
*   According to Peter Bailis's research, only about half of databases support serializable isolation, and very few use it as the default.

### **Isolation Levels and Race Conditions**
Kleppmann explores specific race conditions to define isolation levels accurately.

**Read Committed**
This level guarantees the prevention of two anomalies:
1.  **Dirty Reads:** Reading data written by a transaction that has not yet committed.
2.  **Dirty Writes:** Overwriting a value written by a concurrent, uncommitted transaction.
    *   *Example:* Transactions A and B write to X and Y. Without protection, X could end up with B's value and Y with A's value, creating inconsistent mixed state.

**Snapshot Isolation (and Read Skew)**
Kleppmann introduces the **Read Skew** anomaly using a banking example:
*   *Scenario:* A transfer of $100 moves from Account X to Account Y. Total balance is $1000.
*   *Anomaly:* A concurrent backup process reads Y ($500) before the transfer, and reads X ($400) after the transfer. The backup sees a total of $900. Money seemingly vanished.
*   *Solution:* **Snapshot Isolation** (often called Repeatable Read in databases like MySQL and PostgreSQL). Using Multi-Version Concurrency Control (MVCC), the database keeps old versions of data so a transaction sees a consistent snapshot from a single point in time.

**Serializable (and Write Skew)**
Even Snapshot Isolation is not fully serializable. Kleppmann demonstrates **Write Skew** using a "Doctor on Call" example:
*   *Invariant:* At least one doctor must be on call.
*   *Scenario:* Alice and Bob are both on call. Both feel sick. Both initiate a transaction to go off-call.
*   *Logic:* The database checks: "Are count(doctors) >= 2?" Both transactions see "2". Both proceed to set themselves to "off-call."
*   *Result:* Zero doctors are on call. The invariant is violated.
*   *Cause:* The transactions made a decision based on a premise (count=2) that was invalidated by the other transaction’s write. Because they wrote to different rows, simple row-locking does not detect the conflict.

### **Implementing Serializability**
Kleppmann outlines three ways databases implement true serializability:

1.  **Two-Phase Locking (2PL):** The standard for 30 years. If you read data, you take a shared lock that blocks others from writing. This kills performance because a large read query can block all writes.
2.  **Serial Execution (e.g., VoltDB, Redis):** Literally execute transactions one at a time on a single thread. This is very fast *if* the dataset fits in memory and transactions are short (stored procedures), avoiding network round-trips.
3.  **Serializable Snapshot Isolation (SSI) (e.g., PostgreSQL):** An optimistic approach. The database tracks reads and writes. If it detects a conflict that could cause a serialization anomaly, it aborts one transaction. This works well if contention is low.

### **Distributed Transactions and Microservices**
Kleppmann shifts to systems larger than a single node: microservices and stream processing.
*   The industry standard is to wrap each service around its own database, preventing shared state.
*   To achieve serializability across services, you need **Atomic Commit** (like Two-Phase Commit).
*   However, Atomic Commit is a form of **Consensus** (Atomic Broadcast). This is expensive and brittle; if one service fails, the transaction stalls. It amplifies failures, which contradicts the goal of decoupling services.

**The "Greenspun's 10th Rule" of Transactions**
Since distributed transactions are avoided, developers implement ad-hoc replacements:
*   **Compensating Transactions:** (e.g., Un-booking an item). This is essentially an application-level implementation of **Atomicity** (Abort).
*   **Apologies:** (e.g., "Sorry we oversold this flight, here is a refund"). This is an application-level implementation of **Consistency** (fixing broken invariants after the fact).

Kleppmann jokingly posits that "every sufficiently complex deployment of microservices contains an ad-hoc, informally specified, bug-ridden, slow implementation of half of transactions".

**The Problem of Distributed Isolation**
He highlights that Isolation is usually missing in these ad-hoc implementations.
*   *Example:* A user unfriends an ex-partner, then posts a complaint about them.
*   *The expectation:* The ex-partner should not see the post.
*   *The reality:* If "Unfriending" and "Posting" are handled by different services, the "Post" event might arrive at the notification service before the "Unfriend" event due to network delays. The causal relationship is lost.

### **Future Opportunities: Causality**
Kleppmann concludes by looking at research opportunities.
*   We cannot easily do distributed serializability (too expensive).
*   We want more than eventual consistency.
*   **Causality** is the middle ground. It captures the ordering of events (e.g., the unfriend happened *before* the post) without requiring global coordination or consensus.
*   Consistent snapshots are essentially about obeying causality (if you see the effect, you must see the cause).
*   The challenge is making tracking causality efficient regarding metadata overhead.

### **Conclusion**
Kleppmann summarizes the journey from 1970s System R definitions to the modern need for causality in distributed systems. He mentions his bibliography of research papers and announces a giveaway of early copies of his book.