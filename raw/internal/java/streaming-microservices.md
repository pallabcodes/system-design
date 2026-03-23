Resource: 


Based on the transcript of the video "Apache Kafka + Apache Mesos = Highly Scalable Streaming Microservices" by Kai Waehner from Confluent, here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Agenda**
Kai Waehner, working for Confluent (a company partnering closely with Mesosphere), introduces the session at MesosCon Europe. The presentation focuses on building highly scalable streaming microservices using the combination of Apache Kafka and Mesos.

The agenda covers:
1.  **Motivation:** Defining scalable microservices.
2.  **Apache Kafka & Confluent Platform:** Ensuring a shared baseline of knowledge.
3.  **Kafka Streams:** A deep dive into the stream processing library and how it differs from engines like Spark Streaming, Flink, or Storm.
4.  **Kafka + Mesos/DC/OS:** Why customers use this combination and the benefits.
5.  **Live Demo:** Deploying and scaling Kafka Streams microservices on Mesos.

### **Motivation: Scalable Microservices**
Waehner argues that the goal of microservices is to move away from complex monoliths toward smaller, independent services. He notes that the term "micro" is often misleading; they are simply independent services with specific domains or functions.

There are two main benefits to this approach:
1.  **Independent Deployment:** Teams can develop, test, debug, version, and deploy independently. This is an organizational benefit that allows teams to work without blocking one another.
2.  **Infrastructure Scaling:** Instead of scaling a heavy monolith, you can independently scale specific business functions up or down.

To succeed with this architecture, two characteristics are required:
*   **Loose Coupling:** Services must be fully independent.
*   **Event-Driven Architecture:** Services should produce data independently of consumers. One consumer might need real-time updates while another runs batch analytics.

### **Apache Kafka and Confluent Platform Overview**
Apache Kafka was built as a **distributed, fault-tolerant commit log**, not just a traditional messaging queue where messages disappear after consumption. It allows many consumers to read the same logs at their own pace (batch or real-time) and acts as a storage layer.

**The Ecosystem:**
*   **Apache Kafka Core:** Includes the brokers (messaging), **Kafka Connect** (integration with DBs, HDFS, S3), and **Kafka Streams** (stream processing).
*   **Confluent Open Source:** Adds tools like the **REST Proxy** (for non-Java languages like Go or Python) and the **Schema Registry** (for defining Avro structures and handling schema evolution/validation).
*   **Confluent Enterprise:** Includes **Control Center** (end-to-end monitoring, latency tracking) and **Confluent Replicator** (a more powerful data center replication tool than MirrorMaker).

Kafka acts as the central nervous system, decoupling microservices so they can be upgraded or taken down independently.

### **Kafka Streams and Stream Processing**
Waehner defines stream processing as processing data continuously while it is in motion, rather than the request/response model of data at rest.

**Evolution of Stream Processing:**
Historically, stream processing started as "faster MapReduce" using frameworks like Spark Streaming or Storm on top of heavy Big Data clusters. Kafka Streams differs because it does not require a cluster. It is a **Java library** that can be embedded into any application (WAR file, Docker container, Mesos, Kubernetes).

**Why Kafka Streams?**
*   **Decentralization:** It allows different teams (Fraud, Monitoring, Payment) to run their own infrastructure and versions independently, rather than relying on a central Big Data team to manage jobs on a shared cluster.
*   **Features:** It supports standard operations (map, filter, aggregate, join, windowing) but leverages Kafka for fault tolerance, scalability, and reprocessing.
*   **Local State:** It manages local state (fault-tolerant) so if one instance fails, others take over without data loss.
*   **Streams and Tables:** It supports both continuous streams and database-like tables (compacted topics) in a single API.
*   **KSQL:** Waehner mentions the recent announcement of KSQL, which allows writing SQL-like queries for streaming logic instead of Java code.

### **Kafka + Mesos (DC/OS) Architecture**
In a Mesos architecture, the Kafka Brokers (messaging) and Kafka Streams applications (processing) run as tasks. Both the Kafka Brokers and Mesos rely on Zookeeper (though there is a long-term goal to remove this dependency).

**Key Benefits of the Combination:**
1.  **Automated Provisioning/Upgrading:** DC/OS allows easy deployment of all Kafka components (Connect, Streams, Rest Proxy) via the catalog.
2.  **Unified Management:** You can manage multiple Kafka clusters and other big data frameworks (Spark, Cassandra) on the same infrastructure, optimizing resource usage.
3.  **Elastic Scaling:** Fault tolerance and scaling capabilities.
4.  **Kafka VIP Connection:** A specific feature providing a static bootstrap server URL. This allows applications to connect to a stable address even if the underlying broker IPs change or the cluster is restarted.

### **Use Case and Live Demo**
**The Scenario:** A flight delay prediction microservice.
*   **Tech Stack:** Java, H2O (machine learning framework for the analytic model), Kafka Streams, DC/OS on AWS.
*   **Architecture:** Marathon orchestrates the Kafka Brokers and the Kafka Streams microservices.

**Demo Steps:**
1.  **Infrastructure:** Waehner shows a DC/OS dashboard running on AWS (deployed via CloudFormation). It includes a Confluent Kafka cluster and Zookeeper.
2.  **Deployment:** He deploys the flight prediction microservice (a Docker container from Docker Hub) using the DC/OS UI, allocating CPU and memory.
3.  **Execution:**
    *   He uses command-line scripts to create input and output topics.
    *   He starts a consumer to watch the output (predictions).
    *   He starts a producer script that continuously generates flight data.
    *   The single microservice instance processes the data and outputs predictions (simulated as "YES" for delays).
4.  **Scaling:**
    *   Using the UI, he scales the application from **1 to 5 instances**.
    *   Within seconds, all five instances begin processing data.
    *   Kafka handles the load balancing automatically (defaulting to round-robin if no key is present, or by key if configured) ensuring every message is processed exactly once across the group.

**Technical Note:** Waehner notes a specific issue with the standard Mesosphere Kafka Client in tutorials. It uses an older Kafka version (0.9) which lacks timestamps required by Kafka Streams (introduced in 0.10). He had to build his own Docker client to support the demo.

### **Conclusion and Takeaways**
*   **SMACK Stack:** While the SMACK stack (Spark, Mesos, Akka, Cassandra, Kafka) is popular, replacing parts of it with Kafka Streams microservices on Mesos is a powerful alternative.
*   **Future Trends:** There is a growing trend of using Kubernetes for orchestration on top of Mesos/DC/OS.

### **Q&A Session**
1.  **Data Retention:** Kafka retention is configurable by time (e.g., 4 weeks) or storage size (e.g., 100GB). It is not a search engine with indexing, but a log.
2.  **Joins:** Kafka Streams and KSQL support joins, but they are performed based on keys.
3.  **Message Size Limits:** There is no strict practical limit (people store pictures), but it is generally used for event data.
4.  **Aggregating Across Clusters:** For multi-datacenter aggregation (e.g., Uber matching NY and SF data), replication is used. Options include the open-source **MirrorMaker** or the commercial **Confluent Replicator** (Active-Passive or Active-Active setups).
5.  **Exposing Kafka Externally:** To expose Kafka outside the DC/OS cluster, **REST Proxy** is the easiest method (HTTP), though it has lower throughput than native clients. You can expose native protocols if security (Kerberos/SSL) is configured correctly.