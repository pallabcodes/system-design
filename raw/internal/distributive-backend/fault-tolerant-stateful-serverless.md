Based on the transcript of the presentation "Fault-tolerant and transactional stateful serverless workflows" by Haoran (University of Pennsylvania) at OSDI '20, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction to Serverless Challenges**
The presentation begins by defining Serverless or Function-as-a-Service (FaaS). In this model, utilized by AWS Lambda, Google Cloud Functions, and Azure Functions, developers offload server maintenance to cloud providers. Developers send code snippets or binaries, and an API gateway forwards requests to available workers to launch the code. While used for stateless applications, serverless is also used for stateful applications by connecting to remote storage systems like DynamoDB, Spanner, or Cosmos DB.

**The Problem of Failure**
While serverless removes the burden of server management, it places a heavy burden on developers regarding failure handling. The speaker uses a "lunch attendee counter" example:
1.  A program reads a value from a database, increments it by one, and writes it back.
2.  If the cloud provider returns an error or times out, the user does not know *when* the crash occurred.
3.  If the crash happened *after* the write but *before* the response, retrying the request will incorrectly increment the count again (double counting).

**Idempotence**
To fix this, functions need to be "idempotent"—meaning they can be applied multiple times without changing the result beyond the initial application. This allows safe retries. While developers can write logic to ensure this, it requires significant changes.

### **Beldi System Architecture**
The researchers propose **Beldi**, a system that makes serverless applications automatically idempotent and guarantees exactly-once semantics during failures.

**Infrastructure**
Beldi acts as a "shim layer" between the workers and the storage system. It exposes three APIs:
1.  Read/Write to the database.
2.  Invoke another serverless function.
3.  Define transactions across multiple functions.

**Table Structure**
Each Lambda function utilizes three tables:
1.  **Progress Table:** Tracks the execution progress.
2.  **User Table:** Stores actual data.
3.  **Log Table:** Logs operations and return values.

**Execution Flow:**
*   When a Lambda starts, the cloud provider assigns it a unique **Instance ID**.
*   The Lambda registers itself in the **Progress Table** using this ID and marks itself as "unfinished."
*   When finished, it marks itself as "done."
*   A "Progress Lambda" runs periodically to restart unfinished Lambdas.

### **Ensuring Exactly-Once Semantics**
Beldi guarantees exactly-once semantics by logging operations, inspired by the "Olive" system (OSDI '16).

**Read Operations:**
1.  Beldi reads a value from the database.
2.  It stores the value in the **Log Table** using an Operation ID (e.g., InstanceID-1).
3.  **Recovery:** If the Lambda crashes after reading and is restarted, it tries to re-read. The database will report a key conflict (log entry exists). Beldi then reads the result directly from the log instead of the original table.

**Write Operations:**
Writes must be logged atomically with the data update. If a crash occurs between writing data and logging the operation, exactly-once semantics are violated.
*   **The DAO Approach:** Beldi adopts a mechanism called **DAO** (Data Access Object), co-locating log entries with the item's data in the same row.
*   The User Table has a column called `recent_writes`.
*   A single request updates the data and inserts the log entry simultaneously.

**Garbage Collection:**
Because logs grow over time, a Garbage Collector (triggered periodically) runs to free storage space.

### **Technical Challenges and Solutions**
The speaker outlines specific challenges in implementing this system on databases like DynamoDB.

**Challenge 1: Storage Space Constraints (The Linked Log)**
DynamoDB rows have a size limit (e.g., 400KB). Colocating logs with data fills rows quickly.
*   **Solution:** A data structure called **Linked Log** (or Linked DAO).
*   Logs are spread across multiple rows. When a row fills, a new row is created and appended.
*   **Traversal:** Only the tail contains the newest data. Reading/writing requires traversing to the tail.
*   **Optimization:** To avoid slow linear traversal (multiple round trips), Beldi uses **Scan and Projection**.
    *   It issues a single scan to retrieve all rows for a target key.
    *   It uses a "Projection" to download *only* the Row ID and Next Row pointer (256 bits per row).
    *   Beldi builds a local map to quickly identify and jump directly to the tail.

**Challenge 2: Invocations in a Federated Setup**
In serverless, each Lambda is federated, meaning it has its own independent Progress Lambda and Garbage Collector. This complicates function invocations.
*   **The Problem:**
    1.  Lambda 1 invokes Lambda 2.
    2.  Lambda 2 finishes and marks itself done.
    3.  Lambda 1 crashes before receiving the response.
    4.  Lambda 1 recovers and retries the invocation (expecting exactly-once semantics to skip the re-execution).
    5.  **Failure Mode:** If Lambda 2's Garbage Collector has already cleaned up its logs, Lambda 2 will execute *again* upon the retry, violating exactly-once semantics.
*   **The Solution (Callback Mechanism):**
    1.  A "Result" field is added to the **Caller's (Lambda 1)** log table.
    2.  Before Lambda 2 marks itself done, it sends a **callback** to Lambda 1, asking it to save the result in Lambda 1's log table.
    3.  If Lambda 1 crashes and retries, it finds the result in its *own* log and skips the invocation.
    4.  This moves the result storage to the caller side, allowing Lambda 2 to be garbage collected independently.

### **Evaluation**
The experiments were run on AWS Lambda (1GB memory per Lambda).

**1. Microbenchmarks (Overhead)**
*   Beldi operations (Read, Write, Invoke) are approximately **2 to 4 times more expensive** than the baseline.
*   Sources of overhead include scanning the Linked Log and the logging/callback mechanisms for invocations.

**2. Real-World Application (Travel Reservation)**
*   Adapted from "DeathStarBench" (microservice benchmark).
*   Workload: A travel reservation app (10 services) supporting user accounts, hotel/flight search, and sorting. Includes a transaction across "Reserve Hotel" and "Reserve Flight."
*   **Saturation:** Both Beldi and the baseline saturated at around **700 requests per second**.
    *   *Bottleneck:* The primary bottleneck was the AWS Lambda limit of 1,000 concurrent Lambdas per account.
*   **Throughput & Latency:** Beldi achieved the same throughput as the baseline (which lacked fault tolerance/transactions) but with **3.3x higher median response time** due to the logging overhead.

### **Conclusion**
The presentation concludes that Beldi successfully provides a framework for transactional and fault-tolerant serverless applications. Key contributions include:
*   **Linked Log:** A lock-free data structure for fast logging within storage limits.
*   **Collaborative Transaction Protocol:** Handles cross-function transactions (detailed in the paper).
*   **Efficient Garbage Collection:** Operates independently without affecting running Lambdas.
*   The code is available on GitHub.