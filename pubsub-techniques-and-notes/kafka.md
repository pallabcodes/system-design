Resource: https://youtu.be/9RMOc0SwRro


- Request/Response (HTTP)

- Batching

- Stream processing


Based on the transcript of the presentation "Apache Kafka and the Next 700 Stream Processing Systems" by Jay Kreps, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Inspiration**
Jay Kreps, one of the original authors of Apache Kafka, introduces the talk by referencing a 1960s computer programming paper titled "The Next 700 Programming Languages" (regarding a system called ISWIM). He admires how that paper broke a language down into constituent parts to see how they could be recombined, and his goal is to explain the parts that make up Kafka and how they recombine for stream processing.

### **Defining Stream Processing**
Kreps defines stream processing by situating it among three paradigms of computer programming, sliced by how they handle inputs and outputs:
1.  **Request-Response:** The standard for interactive systems (HTTP, REST). The system receives one request (input) and sends back one response (output) synchronously.
2.  **Batch Processing:** The back-end of most companies (Hadoop, Data Warehouses). It takes all inputs and produces all outputs at once. This method persists because it is highly efficient due to data locality and pre-organization.
3.  **Stream Processing:** A generalization of the two extremes. The program controls the trade-off; it takes some inputs and produces some outputs.

**Clarifications on Stream Processing:**
*   It does not mean computation that is transient, approximate, or lossy.
*   It can compute the exact answers and the full set of things computable by batch processes.
*   Its domain is **asynchronous** and **decoupled** work, which is typically safer and more efficient than synchronous processing.

**Programming in the Large:**
Kreps distinguishes between stream processing libraries for a single process (like RxJava) and stream processing at the **datacenter level**. He proposes that a company can be modeled as a set of streams: input streams (sales, shipments), processing streams (price adjustments, inventory updates, analytics), and output streams.

### **The Infrastructure Gap**
Historically, there has been a lack of infrastructure for this middle ground.
*   **Request-Response:** Well-served by OLTP databases and REST frameworks.
*   **Batch:** Well-served by Hadoop and Data Warehouses.
*   **The Middle:** For processing faster than hours but slower than milliseconds, developers were often on their own. Previous attempts like Enterprise Service Buses (ESB), Complex Event Processing (CEP), and database triggers were insufficient for building large, critical infrastructure.

### **Hard Problems in Stream Processing**
To build a viable system, several hard problems must be addressed:
1.  **Partitioning and Scalability:** How to elastically spread data and processing across machines.
2.  **Semantics and Fault Tolerance:** How to handle machine failures.
3.  **Unifying Streams and Tables:** Combining streams of events (like sales) with tables of state (like stock on hand).
4.  **Time:** Handling the lack of a global clock and processing late-arriving data.
5.  **Reprocessing:** The ability to rerun logic and get new answers when code changes.

### **Apache Kafka Architecture**
Kreps explains that Kafka functions as a messaging system or stream database where producers publish streams, the system maintains them fault-tolerantly, and consumers read them.

**The Log Abstraction:**
*   Internally, Kafka stores data as a **Log**: a totally ordered sequence of records appended to the end.
*   This structure is akin to the commit logs found in databases and consensus algorithms (like Raft or Paxos).
*   A **Stream** is formally defined as a log, or specifically, a set of **partitioned logs** to allow for parallelism.

**Stream Processing Definition:**
Stream processing is simply transforming input logs into output logs. If the process requires maintaining state (counts, joins), it must ensure that state is protected if the code fails.

### **Key Mechanisms for Solving Hard Problems**
Kreps details the specific Kafka ingredients used to solve the hard problems identified earlier.

**1. The Change Log and Log Compaction**
*   A **Change Log** records mutations (put operations) to a key-value pair over time.
*   This concept allows for the replication of state (used by databases like MySQL and Oracle).
*   Kafka uses **Log Compaction** to maintain this state efficiently by removing redundant updates, keeping only the most recent value for a key.

**2. Consumer Groups (Partitioning & Scalability)**
*   Kafka uses **Consumer Groups** to allow a group of processes to divide up the logs and process them in parallel.
*   This dynamic membership handles scaling (adding consumers) and fault tolerance (handling dead consumers).

**3. State Management (Unifying Streams and Tables)**
*   Stream processors function as stateful services.
*   They maintain local state (in memory or a store like RocksDB) and journal changes to a Kafka Change Log.
*   This unifies streams and tables: the log represents the stream, and the materialization of that log represents the table.

**4. Time and Late Data**
*   Handling late data requires maintaining counts or aggregations as **mutable tables** that can be updated when new data arrives, rather than static snapshots.

**5. Reprocessing**
*   Reprocessing is solved by rewinding to the beginning of the log (offset 0) and re-running the logic.
*   This unifies batch and stream processing: a batch process is simply a stream process that shuts down when it reaches the end of the log, while a stream process keeps waiting for more data.

### **Kafka Streams**
Kreps mentions existing frameworks that work with Kafka (Spark, Storm, Samza, Flink) and introduces **Kafka Streams**, a new library (released shortly after the talk). Kafka Streams is not a cluster or framework but a library that leverages these Kafka primitives (groups, change logs) to solve the hard problems of stream processing directly within the application code.

### **The Stream Data Platform**
Kreps outlines the resulting architecture, a "Stream Data Platform," which consists of three layers:
1.  **Top Layer:** Request-Response systems (REST services, DBs) capturing changes into Kafka.
2.  **Middle Layer:** Asynchronous stream processing (Transformation, Analytics).
3.  **Bottom Layer:** Batch storage (Hadoop, Data Warehouses) fed by the same streams.

### **Conclusion**
Kreps concludes by noting that this architecture was put into practice at LinkedIn, handling over 1.1 trillion messages per day, serving as the backbone for offline data feeds, real-time analytics, and database commit logs. He directs the audience to the Apache Kafka project, the Confluent blog, and the design document (KIP-28) for further reading.