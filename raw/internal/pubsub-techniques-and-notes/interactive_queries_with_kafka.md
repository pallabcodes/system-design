Resource:

Based on the transcript of the presentation by Matthias Sax at the Kafka Summit 2017, here is an accurate and comprehensive extraction of the content provided in the video preview, from start to end.

### **Introduction and Agenda**
Matthias Sax introduces the topic of "Interactive Queries," specifying that this refers to querying the application rather than a database. He outlines the structure of the talk:
1.  **Kafka Streams Overview:** A brief wrap-up for those unfamiliar with the technology.
2.  **State and Stateful Stream Processing:** Defining what state is and why it is important to care about it.
3.  **Technical Deep Dive:** A detailed look at what interactive queries provide and how state is handled within Kafka Streams, which is crucial for understanding how to use interactive queries.
4.  **Wrap Up**.

### **Kafka Streams Overview**
Sax describes Kafka Streams as "the simplest way to process streams in Kafka," though he notes this claim might now be challenged by the existence of KSQL. Key characteristics include:
*   **Library Status:** It is a powerful stream processing library added in the 0.10 release (approximately a year prior to the talk). It represents a new approach compared to technologies that use a dedicated processing cluster,.
*   **Integration:** It is tightly integrated with Kafka.
*   **APIs:** It offers an easy-to-use, high-level DSL (Domain Specific Language) for expressing computation logic with rich operators like joins, aggregations, and filters. It also provides a lower-level Processor API for custom operators if the DSL does not cover specific needs.
*   **Time Semantics:** It supports rich time semantics, including event time, ingestion time, and processing time. Crucially, it handles out-of-order records based on timestamps, addressing the fact that Kafka itself guarantees strict ordering based on offsets but not necessarily by time.
*   **Features:** The library supports aggregations, join windows, and a "duality between streams and tables" that allows for joins between the two. It relies on the Kafka cluster ("standing on the shoulders of giants") to build scalable, elastic, and highly available applications.

**Deployment Model:**
A Kafka Streams application is a regular Java application that can be packaged and deployed anywhere (it does not run inside the brokers). It functions as a "richer" regular consumer that connects to the cluster, forms a consumer group, and acts as a producer by reading data from Kafka and writing results back to it. For connecting to external systems, users would utilize Kafka Connect,.

### **Stateful Stream Processing**
Sax moves on to the core of the talk: state. He defines state as "anything the application needs to remember beyond the scope of one single record".

**Stateless vs. Stateful Operators:**
*   **Stateless Transformations (e.g., Filter, Map, Flatmap):** These are easy to handle because they rely on a single record. For instance, in a filter operation, the decision to drop a record or send it downstream is made solely by evaluating fields in that specific record. No context is needed regarding whether it is the first or the 100,000th record processed.
*   **Stateful Operators:**
    *   **Aggregations (e.g., Count):** A single record is insufficient to determine a count. The application requires context (the current count) to add the new record to it. This current count is the state the application must remember.
    *   **Window Operations:** These involve putting many records into one window, which constitutes state.
    *   **Joins:** These involve at least two records from different streams, requiring information beyond a single record's scope.
    *   **Complex Event Processing:** Detecting patterns in a stream requires context.

Sax concludes this section by emphasizing that almost any non-trivial stream processing application will have state ("state is everywhere"), and therefore, state must be treated as a "first-class citizen" in stream processing.