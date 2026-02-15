Resource: https://youtu.be/6xBqTUUe0Sg

Based on the transcript of the presentation by Osuito from LINE Corporation, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction**
The speaker introduces himself as Osuito, a senior software engineer who joined LINE in 2015 as a new graduate. His background involves messaging server development and HBase operations. Currently, he leads the team delivering the company-wide Kafka platform. He is active in the open-source community, contributes to the tenets, and recently spoke at the Kafka Summit in the United States.

### **The Company-Wide Kafka Platform at LINE**
The speaker discusses the Kafka platform operated at LINE. He notes that those who attended LINE Developer Day in previous years would know they use large-scale distributed middleware like HBase, and Kafka is one of them.

**What is Kafka?**
Kafka is middleware with an ecosystem built for data streaming. It has several characteristics suitable for large-scale services:
1.  **High Availability and Scalability.**
2.  **Data Persistency:** Once data is written to Kafka, it is persistent.
3.  **Data Distribution:** It supports a Pub/Sub model.

**Kafka Architecture:**
There are three main components:
*   **Producers (Left):** Clients that write data to Kafka.
*   **Brokers (Middle):** An arbitrary number of nodes that host "Topics," which are units of data management. Producers identify a topic to send data to.
*   **Consumers (Right):** Clients that read data from Kafka by specifying a topic. One topic can have multiple consumers for different purposes. Once a topic is written, it can be read multiple times by different consumers (Pub/Sub model).

**Evolution of usage at LINE:**
Initially, the server development team implemented Kafka as an intermediate layer to simplify server architecture. After proving its high reliability, other teams wanted to use it. Consequently, it developed into a company-wide platform.

### **Use Cases and Rationale**
**Two Main Purposes for Using Kafka:**
1.  **Distributed Queuing System:** For example, a web application server needing to offload heavy processing can use the queue to request a background task processor.
2.  **Data Hub:** Used to sync data updates between services. For instance, updating the friend relationships of users (adding/blocking friends). This relationship update is handled as an event written to a Kafka topic. This event is then consumed by statistics systems, user graphs, and systems designed to detect and penalize abusive users (e.g., those adding unknown friends to send spam).

**Why a Shared Multi-Tenant Cluster?**
It is important that one cluster is shared by multiple systems rather than having separate clusters for each.
1.  **Data Centralization:** Centralizing large data allows services to easily discover and access data in a unified way, keeping the architecture simple.
2.  **Operational Efficiency:** If every service required its own Kafka cluster, operational costs would rise in proportion to the number of services. A shared cluster allows engineering resources to concentrate on a small number of clusters to maintain reliability.

**Scale of the Platform:**
The platform supports many services, including LINE, blockchain, Timeline, and others.
*   **Traffic:** 250 billion messages per day.
*   **Data Volume:** 210 Terabytes per day.
*   **Throughput:** Peak traffic reaches Gigabytes per second.
*   **Tenants:** 50 independent services and systems use the cluster.
*   **Status:** It is considered one of the world's largest single clusters.

### **Requirements for Multi-Tenancy**
Because the cluster is a backend for many services, reliability and performance requirements are very high.

**1. Cluster Self-Protection**
The cluster must protect itself from abusive clients. While malicious attacks from internal systems are not expected, misconfigurations or deployment mistakes can cause unexpected workloads. The system needs to:
*   Track which cluster/client is generating the workload.
*   Identify clients causing unexpected resource activity to solve issues.

**2. Workload Isolation**
The system requires isolation so that one client's workload does not negatively impact another (e.g., causing slow response times for unrelated clients).

**3. Request Quotas**
In operating Kafka, the number of requests is often more critical than data size. Kafka utilizes the operating system's page cache (avoiding double caching) and supports batching to merge multiple records into one. While data volume increases, the overhead per request can be minimized. However, the number of requests must be managed.
*   **Request Quota Feature:** This limits the broker resources (specifically thread time) used by a client.
*   **Default Limits:** Limits are set so that if one client goes out of control, the overall cluster performance does not degrade.

### **Troubleshooting and Engineering Examples**
The speaker shares examples of issues encountered in the production environment regarding identifying and solving performance degradation.

**The Issue:**
Produce request response times worsened significantly (99th percentile response time increased by 50 to 100 times).
*   **Investigation Findings:**
    1.  On the broker machine, there were many disk reads.
    2.  The "Network Thread" (I/O thread between clients) utilization was very high.

**Kafka Request Handling Architecture:**
To understand the issue, the speaker explains the request flow:
1.  **Network Thread:** Handles connection between clients. It reads requests, prepares response objects, and writes to sockets.
2.  **Request Queue:** The Network Thread writes the request object here.
3.  **Request Handler Thread:** Takes the request from the queue, processes it (including writing to local disk), creates a response object, and places it in the Response Queue.
4.  **Response Queue:** The Network Thread takes the object from here and writes it back to the client socket.

The Network Thread uses event-driven asynchronous I/O to multiplex several sockets. The investigation showed Network Thread utilization was increasing, even though metrics showed no changes in traffic volume.

**Deep Dive Investigation:**
They analyzed the system calls using `SystemTap`.
*   **Discovery:** They found excessive `read` system calls were occurring. This was linked to the file cache.
*   **The Cause:** In Kafka, data transfer typically uses `sendfile` (Zero Copy) to transfer data from the page cache directly to the network socket. However, under certain conditions, if the data is not in the page cache, it forces a disk read. This triggers a memory copy to user space, losing the efficiency of the Zero Copy mechanism.

This inefficient behavior caused massive memory copying to user space. The team looked into the Linux kernel implementation and Kafka internals to address how to better handle file cache misses and avoid this blocking behavior in the Network Threads.

**Contribution:**
The team contributes these engineering improvements back to the open-source community/world.

### **Future Prospects**
The speaker outlines two main future goals:

**1. Client Standardization and Maintenance**
Currently, supporting clients is difficult because various teams use different frameworks and Kafka client versions.
*   **Issue:** Supporting a client often reveals inefficiency or complexity due to these variations.
*   **Solution:** Developing an internal "Efficient Consumer Framework" and SDKs. They aim to standardize the client implementation to make management easier.

**2. Higher Availability and Cross-Team Engineering**
The platform has experienced major issues that need resolution.
*   **Goal:** Continuously conduct engineering to improve service reliability.
*   **Collaboration:** Performance engineering is currently conducted by various teams. The speaker envisions a cross-departmental approach, leveraging knowledge of operating systems and specific software tools across different teams to increase overall reliability.

**Conclusion:**
The speaker invites the audience to come talk to him for more stimulating conversation regarding these domains.