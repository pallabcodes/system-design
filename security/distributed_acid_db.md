Resource: https://youtu.be/pn8mCeX3LDE?list=TLGGx_aLExbr_MkwMjAzMjAyNg

### **Introduction and Speaker Background**
Attila Szegedi introduces himself as a Senior Software Engineer at Fauna, working on FaunaDB, which is a distributed and ACID-compliant database. He details his extensive background, having worked at Oracle on the Java platform (including JDK Dynalink and the Nashorn JavaScript runtime), at Twitter on the runtime systems team doing performance tuning and scaling distributed systems, and maintaining open-source projects like Mozilla Rhino and the Apache FreeMarker template engine. He notes a recurring theme in his career where everything he touches becomes either a distributed system or a language runtime—and FaunaDB happens to be both.

He outlines the agenda for the presentation:
1. Why build another database?
2. How to implement strong ACID-compliant transactions in a distributed database.
3. The transaction log implementation.
4. Balancing eventual versus strong consistency.
5. Applying control theory to distributed systems to make them faster.

### **Why Build Another Database?**
Szegedi explains that traditional relational databases provide well-understood transactions but generally fail to offer global distribution, multi-tenancy, and temporality. Conversely, NoSQL databases offer scalability but typically force businesses to sacrifice transactional guarantees and data consistency. 

Fauna was founded by former Twitter engineers who wanted to build the database they wished they had while at Twitter, taking the best of both the relational and NoSQL worlds. While Fauna includes core innovations like multi-tenancy and temporality (storing historical values so users can query the database at any point in the past), the presentation focuses primarily on distributed ACID transactions.

### **The Calvin Protocol**
To implement ACID transactions in a distributed system, Fauna utilizes the **Calvin protocol**, which was introduced in a 2012 SIGMOD paper by Professor Daniel Abadi and other authors. While Calvin shares similarities with Google Spanner, Szegedi notes that Fauna prefers Calvin because it does not require specialized custom hardware or highly synchronized atomic clocks (like Spanner's GPS clocks) to function correctly.

### **Architecture and Transaction Execution**
FaunaDB is a horizontally scalable, multi-value concurrency control store. Data is stored in multiple geographic replicas (e.g., San Francisco and Washington DC), and within each replica, data is sharded into partitions.

**The Transaction Scenario:**
Szegedi illustrates the process using a scenario where two customers in different geographic regions try to buy the exact same widget simultaneously, but only one is in stock. Both transactions check the stock, check the customer's store credit, subtract one from the stock, and subtract the price from the credit.

**The Coordinator and Optimistic Concurrency:**
1. A node in each local replica acts as the "query coordinator". 
2. It fetches the required data from local partitions (or other nodes in the replica) and calculates the "write effects" (e.g., the new stock value of 0 and the new store credit values).
3. Instead of using pessimistic locking, the system uses **optimistic locking** (Optimistic Concurrency Control or OCC). The coordinator bundles the calculated write effects alongside the timestamps and keys of the data it just read.

### **The Transaction Log and Raft Consensus**
Both the San Francisco and Washington DC coordinators submit their transactions to a transaction log. 
*   This log is governed by an interestingly modified version of the **Raft consensus protocol**. 
*   The log guarantees a strict ordering of transactions. 
*   One transaction (e.g., T10) will deterministically get committed to the log first, and the other (T11) will be second.
*   Once written to the log entirely, the transaction is durable and cannot be lost unless more than a quorum of nodes fails. This log guarantees ordering (helping consistency and isolation) and atomicity.

### **Applying and Aborting Transactions**
Data nodes independently read the transaction log and process the transactions. 
*   **Applying (T10):** The nodes rerun the reads at the new transaction time (T10) to see if they match the optimistic timestamps originally submitted. Because all replicas contain the same data and read the exact same ordered log, they deterministically arrive at the same conclusion. If the timestamps haven't changed, the write effects are safely applied to the underlying storage. 
*   **Aborting (T11):** When the nodes process the second transaction (T11), they will notice that the widget's stock timestamp has changed because T10 just modified it. T11 will therefore fail the Optimistic Concurrency Control (OCC) check, and both replicas will deterministically abort it. 

Crucially, **all cross-system coordination only happens when achieving consensus on the log**. If data nodes fail or shut down, they simply resume reading their persisted index of the log when they come back online, eventually catching up in a deterministic manner.

### **Vanilla Calvin vs. Fauna's Modifications**
Szegedi details a major difference between their implementation and "Vanilla Calvin":
*   **Vanilla Calvin** requires the actual transaction logic (the program itself) to be shipped and rerun deterministically on every node. This means the logic cannot invoke random functions, fetch the current system time, or perform file I/O, and it adds heavy computational expense because every node must execute the transaction.
*   **Fauna's Modification** runs the transaction on a single coordinator node, calculates the write effects, and ships *those effects* (along with read timestamps) to the log. To mitigate the quadratic network overhead of nodes fetching read data from each other to perform the OCC checks, nodes eagerly broadcast and cache read data locally within their replica.

### **Scaling the Log (Raft Rings and Epochs)**
To prevent a single log from becoming a performance bottleneck, the transaction log is fully distributed. 
*   Typically, there is one log node per replica to avoid putting all eggs in a single basket. 
*   The Calvin protocol operates in "epochs" of 10 milliseconds. Log nodes gather transactions in memory for 10ms and then propose them as a single batch message to the Raft system.
*   Fauna utilizes **multiple Raft rings** (called log segments) simultaneously. 
*   Data nodes must fetch batches from all log segments and **deterministically merge them** (e.g., applying all transactions from segment 1 first, then segment 2, etc.). 

**The Role of Clocks:**
This deterministic merging protocol **does not rely on physical clocks for correctness**. While Fauna uses NTP internally to keep epochs roughly aligned, if a log segment drifts into the future, it only affects *availability*. Transactions must wait for other segments to catch up before they can be merged; if they are queued more than 30 seconds in the future, they will simply experience timeouts, but correctness is never violated.

### **Eventual vs. Strong Consistency**
Szegedi explains a design choice regarding when to acknowledge a transaction back to the client:
*   Once a transaction achieves consensus on the log, it is durable. The database *could* acknowledge the client immediately at this stage, resulting in an eventually consistent system. 
*   Fauna chooses not to do this. Instead, they wait until the data nodes process the log, perform the OCC check, and all independently agree on the final outcome and timestamp. 
*   Furthermore, they wait to acknowledge the client until the coordinator's local read clock catches up to that timestamp. This ensures that if the client immediately performs a subsequent read using that snapshot time, they will not be blocked and are guaranteed to observe the effects of their own write. 

### **Transaction Language and Sessions**
Fauna uses an expressive, "LISP-like" query language, though they also offer a GraphQL adapter. 
*   Currently, the system does not support "session transactions" (like traditional SQL `BEGIN` and `COMMIT` spread across multiple client-server roundtrips). 
*   The entire transaction logic must be sent in a single request, similar to a stored procedure. 
*   Szegedi notes that while Vanilla Calvin outright prevented session transactions, Fauna's architectural modifications technically open the door to implementing them in the future if desired.

### **Applying Control Theory (PID Controllers & Kalman Filters)**
Finally, Szegedi discusses using control theory to make correct distributed systems run faster by dealing with coordination bottlenecks and latencies. 

**The PID Controller:**
Similar to cruise control in a car, a PID (Proportional-Integral-Derivative) controller acts as a feedback loop to continuously modulate a system. It uses K coefficients to weight the proportional, integral, and derivative parts to avoid overshooting and oscillation.
*   Fauna uses a PID controller to determine **when to issue "backup reads"**. When a node needs data from another node, it requests it locally. If it doesn't get a response, it must issue a backup read to a node in a different replica. 
*   Issuing a backup read immediately doubles network traffic, but never issuing one (waiting for a timeout) hurts the user experience. 
*   The PID controller dynamically adjusts the wait time (`delta T`) based on the process variable: the proportion of recent reads that have timed out. 
*   If the system is humming along perfectly, the controller increases the wait time so backup reads are never issued unnecessarily. If the system starts acting erratically, the controller automatically shrinks the wait time down to zero, issuing backup reads instantly alongside the first read to maintain performance.

**The Kalman Filter:**
Due to time constraints, Szegedi briefly mentions the Kalman filter (the mathematical model used by GPS to find a precise location from noisy sensor data). He notes that while Fauna does not use it yet, they plan to implement it to further speed up distributed operations in the future.