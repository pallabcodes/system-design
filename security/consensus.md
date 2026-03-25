Resource: https://youtu.be/em9zLzM8O7c?list=TLGGNgaxlf9gg8MwMjAzMjAyNg

Based on the transcript of the presentation "Consistency without consensus in production systems" by Peter Bourgon at the Strange Loop Conference, here is an accurate and comprehensive extraction of the content from start to end, without any omissions or simplifications.

### **Introduction to Distributed Programming**
Peter Bourgon introduces himself as a pragmatic software engineer working in the infrastructure department at SoundCloud, building data systems that power the platform. He defines distributed programming using a quote from mi.net: "the art of solving the same problem that you can solve on a single computer using multiple computers". He also offers his own definition: "it's generally a bad idea and you should probably avoid it if you can". 

To illustrate this, he compares local versus distributed operations. In a local environment (like IPython), setting a variable and reading it back works predictably. In a distributed system using a REST endpoint, posting a value might succeed, but trying to read it back often results in a "service unavailable" error. Bourgon stresses that network failures are completely normal and must be accounted for.

### **The Lineage of Distributed Programming Idioms**
Bourgon traces the historical evolution of how developers have dealt with distributed complexity:
*   **The 1980s (RPC):** Remote Procedure Calls attempted to model network communication as a local function call. However, Bourgon argues there is a fundamental difference in kind between moving a program counter in a CPU and serializing/deserializing requests over a network, making this an insufficient idiom.
*   **The 1990s (CORBA):** Higher-level abstractions like CORBA promised "location transparency" (the idea that interacting with a local object or one across the Atlantic should be identical). Bourgon argues this abstraction went too far, too fast by treating the network as more reliable than it actually was, failing to provide robust error handling. He notes that many legacy banking systems (like Bank of America) still rely on CORBA.
*   **The Year 2000 (The CAP Theorem):** Introduced by Eric Brewer, CAP forced developers to acknowledge network partitions via "Partition Tolerance" (the system operating despite message loss or node failure). CAP dictated that a system cannot have Consistency, Availability, and Partition Tolerance simultaneously. Since network partitions are inevitable, systems must choose Partition Tolerance, leaving a choice between CP systems (Consistency/Partition Tolerance) and AP systems (Availability/Partition Tolerance).

### **CP vs. AP Systems**
**CP Systems:**
Built using consensus protocols that guarantee strong consistency up to a certain failure level. Examples include Paxos (used by Chubby/Doer), Zab (Zookeeper), Raft (Consul/etcd), and Viewstamped Replication. While provably correct, they are difficult to explain, implement, debug, and maintain. Furthermore, they suffer from high latency per transaction and low overall throughput, making them unsuitable for high-volume tasks like storing tweet streams.

**AP Systems:**
Most distributed data systems (Cassandra, Riak, Mongo, CouchDB, Couchbase) fall here. They do not sacrifice consistency entirely; they use "eventual consistency," accepting temporary node staleness provided the system converges to a correct state. However, early ad-hoc implementations of eventual consistency lacked provable guarantees, leading to embarrassing public failures due to a gap between customer expectations and actual system capabilities. 

### **Theoretical Foundations for AP Systems**
Networks inherently delay, drop, reorder, and duplicate messages. CP systems abstract these failures away, but AP systems allow them to happen. To prevent System state corruption, new theoretical frameworks emerged in the mid-to-late 2000s:
*   **CALM Principle (Consistency as Logical Monotonicity):** The concept that a system should only "grow" in one direction as it accepts messages (e.g., a counter that only gets bigger), as seen in the Bloom programming language.
*   **ACID 2.0:** A reification of CALM where operations must be **A**ssociative, **C**ommutative, **I**dempotent, and **D**istributed. 
*   **CRDTs (Conflict-free Replicated Data Types):** Distributed data types that abide by ACID 2.0 properties, making them *provably* eventually consistent without needing strong consensus.

### **CRDT Example: The Increment-Only Counter**
Bourgon provides an example of counting unique track plays on SoundCloud. 
*   **The Problem with Math:** Standard addition is associative and commutative, but *not* idempotent (adding 1 repeatedly changes the result). Thus, simple addition cannot make a CRDT.
*   **The Solution with Sets:** Set Union is associative, commutative, and idempotent (unioning the same element multiple times changes nothing). By bending the problem domain and tracking unique User IDs in a set instead of abstract integers, you achieve CRDT properties.
*   **Handling Partitions (G-Set):** If a track is played and inserted into a 3-node system, but the network partitions, one node might show 1 play while others show 0. If a read occurs across all nodes, the system can perform a Union to get the correct count. Furthermore, by computing the "symmetric difference," the system identifies missing elements and performs a "read repair" by rewriting the missing data to the inconsistent nodes, achieving eventual consistency safely.

### **The "DevOps" Philosophy for Distributed Systems**
Bourgon presents a philosophical interlude comparing this to the DevOps revolution. In the 1990s, developers threw code over the wall to sysadmins, resulting in poor software. Acknowledging the invariant that developers are best qualified to run and monitor their own code led to DevOps, vastly improving software quality. Similarly, acknowledging the invariant that networks are faulty and utilizing tools like CRDTs to embrace those faults—often by bending the problem description to fit the solution—results in vastly more reliable distributed systems.

### **CRDTs in Production at SoundCloud: The "Roshi" System**
SoundCloud's user feed (the "stream") displays chronological events. Every event is unique, consisting of a timestamp, user, verb, and object (e.g., Snoop Dogg reposting an Economist podcast).

**Fan-out vs. Fan-in:**
*   **Fan-out on write (Twitter/Facebook model):** Every action is copied to the inbox of every follower. This generates massive data (one action by a user with 2.5 million followers equals 2.5 million writes) and makes handling unfollows extremely difficult.
*   **Fan-in on read:** Creators write solely to their own outbox. The stream is dynamically materialized at read-time by checking the outboxes of everyone the user follows. This limits writes to 1 per action and allows dynamic reordering/recommendations, but requires a strict read latency of single-digit milliseconds.

**The Roshi Set:**
To build a fan-in system, SoundCloud evaluated existing CRDT sets. G-Sets cannot delete, 2P-Sets can only delete once, and OR-Sets have too much storage overhead. They built **Roshi**, a modified Last-Writer-Wins (LWW) element set with inline garbage collection. 
*   It uses a physical "Add Set" and a "Remove Set" merged semantically to form the logical set. 
*   **Write Logic:** An insert (Key, Element, Score/Timestamp) scans both sets. If the element exists with a score greater than or equal to the incoming score, it exits (no-op). Otherwise, it inserts into the Add Set and deletes from the Remove Set. Deletes are the exact inverse. 
*   This ensures that no matter how many times operations are delayed, duplicated, or reordered, pouring them into the system always results in the exact same final state, vastly simplifying operations.

**Infrastructure and Architecture:**
*   **Redis:** They utilize Redis because its Sorted Sets (Z-Sets) and atomic Lua scripting natively provide the exact primitives needed for the Roshi algorithm.
*   **Sharding (Pool & Cluster):** Because data exceeds a single machine, Redis instances are sharded using the User ID as the key. The instances do not communicate. A "Pool" layer maps keys to instances, and a "Cluster" layer provides the CRDT insert/delete/select API.
*   **Replication (The Farm):** To ensure high availability, the entire stack is replicated. A top-level "Farm" layer acts as command and control. There is no background gossip between clusters. 
*   **Writing/Reading:** Writes are copied to all clusters, returning success once a 51% quorum is reached. For reads, they avoid the naive approach (reading just one cluster) and the expensive approach (reading all clusters and calculating unions/differences synchronously). Instead, they use a hybrid approach: they return the first responder to the client for speed, but a background listener collects all other responses, computes the semantic difference, and silently issues read-repairs to any inconsistent nodes (a 2,000-line Go implementation mimicking Cassandra's read repair).

### **Concluding Remarks and Q&A**
Bourgon concludes with three takeaways:
1. Consistency without consensus means CRDTs, the current best practice for eventual consistency.
2. Embrace invariants (like faulty networks) instead of abstracting them away.
3. Bend your problem description to fit the solution domain rather than forcing the solution.

**Q&A:**
*   **Tombstoning:** Tombstones (entries in the delete set) are computed and written immediately via atomic operations as soon as the delete operation hits the system.
*   **Clock Drift:** The system ignores clock drift and strictly trusts the timestamp provided by the event sender.
*   **Inactive Users:** If a user has no followers and no reads, they could theoretically remain inconsistent. To solve this, a separate background "Walker" process scans the entire keyspace sequentially every 8 hours to force consistency checks across the system.