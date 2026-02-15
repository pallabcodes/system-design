Resource: https://youtu.be/fB2Nz56bebA

Based on the transcript of the video "AWS re:Invent 2022 - Being good neighbors: Rate limiting in a modern application world (BOA311)," here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Motivation**
Boaz introduces Liel from DoControl to discuss how to develop modern applications that act as "good neighbors," specifically when interacting with legacy and traditional systems.

**The Origin Story:**
The idea for the talk originated two years prior when Boaz recorded an episode of "This is My Architecture" with Nielsen Media. Nielsen had developed a fully serverless application processing 55 terabytes of data daily.
*   **The Feedback:** Viewers commented that the system was so powerful and scalable that it effectively launched a DDoS attack on Nielsen's partners.
*   **Internal Impact:** Another comment noted it was also a DDoS attack on their internal systems, requiring significant effort to make internal components handle the capacity.
*   **The Goal:** The session focuses on how to design systems that are super scalable and modern without causing damage to less scalable, external, or legacy parts of the system.

### **Characteristics of Modern Applications**
Boaz outlines four key changes in application development over the last 20 years:
1.  **Scale:** Moving from hundreds of users to millions (including API interactions).
2.  **Global Reach:** Customers are everywhere, introducing technical and cultural/regulatory challenges.
3.  **Response Time:** Users are no longer willing to wait seconds; expectations are now in milliseconds.
4.  **Data:** Volumes have grown from gigabytes to petabytes.

### **The Core Problem: Scalability Mismatches**
Boaz illustrates the problem using architectural examples:
*   **Container Scaling:** An online store can scale its catalog pods rapidly. If the checkout pods scale less frequently, that is fine.
*   **Serverless Fan-out:** A Lambda function analyzes a data stream and fans out to thousands of other functions. If these connect to modern services (SQS, DynamoDB), it works. However, if they connect to a legacy system, relational database, or third-party API, failures often occur.

**Why Failures Happen:**
1.  **Speed of Scaling:** Lambda scales in milliseconds/seconds. Physical servers or VMs (EC2) take minutes to scale.
2.  **Resource Isolation:** Legacy backend developers used to share resources (threads, connections). Serverless functions are "egoistic"—they consume assigned resources and do not release them until finished, lacking resource reuse.

**Consequences:**
Failure to manage this results in throttling, blocking, timeouts, and increased costs due to paying for endless retries.

### **The Solution: Limits**
The general solution is to introduce limits to ensure the modern application respects the capabilities of other systems.

### **Demo Part 1: The "Bad Neighbor"**
Boaz initiates an interactive demo where the audience votes on colors via a web app.
*   **Architecture:** AWS Amplify, API Gateway, Lambda, and DynamoDB (Auto-scaling).
*   **Configuration:** A 1-second wait time is injected to simulate load.
*   **Result:** The serverless stack scales effortlessly to handle the audience's traffic without errors, but costs rise quickly.

### **Limiting Techniques (Compute)**
Boaz details methods to limit compute resources:
1.  **Lambda Concurrency:**
    *   There is a default soft limit of 1,000 concurrent executions per account per region.
    *   You can set specific concurrency limits per function.
    *   *Tip:* Setting a function's reserved concurrency to 0 is the fastest way to stop a damaging function immediately.
2.  **Event Filtering:**
    *   Instead of filtering data inside the code (which costs money to run), use Lambda Event Filtering to trigger the function only when payload criteria are met (e.g., `tire_pressure < 32`).

### **Relational Database Challenges**
Boaz switches the demo backend from DynamoDB to Amazon RDS (Relational Database Service).
*   **Result:** The application immediately crashes ("Service unavailable") for the audience.
*   **Cause:** Lambda functions do not reuse connections by default. The small RDS instance ran out of connections rapidly.

**Solutions for Databases:**
1.  **Buffers:** Use SQS (Simple Queue Service) to decouple the write process. A separate process reads from the queue at a controlled rate to aggregate writes.
2.  **Proxy:** Use **Amazon RDS Proxy**. This service sits between the app and the database to manage and pool connections.

### **Case Study: DoControl (Presented by Liel)**
Liel, CTO of DoControl, takes the stage. DoControl is a SaaS security platform connecting to vendors like Slack, Zoom, and Google Drive.
*   **The Challenge:** Product requirements forced a move from DynamoDB to RDS for complex aggregations, leading to connection pool issues.
*   **The Solution:** They implemented Amazon RDS Proxy.
    *   **Implementation:** Minimal code changes; the app simply points to the proxy instead of the DB.
    *   **Benefits:** It handles connection pooling/sharing, supports Read Replicas for workload separation, and supports IAM authentication (replacing plain text passwords with short-lived tokens).

### **Protecting Legacy Systems & APIs**
Boaz returns to discuss protecting external or legacy interfaces.

**1. API Throttling ("Make it somebody else's problem"):**
*   Use API Gateway **Usage Plans**.
*   Set a strict limit (e.g., 10 requests/second) for legacy routes.
*   Set high/unlimited limits for modern routes.
*   This enforces protection at the entry point.

**2. Caching ("The Neighbor's Sugar"):**
*   Reduce the load on legacy systems by fetching data once and reusing it.
*   **Local Caching:** Use Lambda local storage (now 10GB), EFS, or memory.
*   **Service Caching:** Use Amazon ElastiCache (Redis/Memcached). Update the cache periodically via a recurring Lambda event rather than hitting the DB on every request.

### **Asynchronous Workflows (Presented by Liel)**
Liel discusses "Async Thinking"—releasing resources as soon as possible.

**AWS Services for Async Workflows:**
1.  **SNS & SQS:** Standard tools for buffering. DoControl used SQS to buffer heavy file-write operations to the database, utilizing Dead Letter Queues (DLQ) and retries.
2.  **EventBridge (API Destinations):**
    *   Used for sending data to partners (e.g., Datadog, Splunk) or HTTP APIs.
    *   **Features:** Built-in authentication (API keys, OAuth) and **Rate Limiting**. You can set a max invocations per second, and AWS manages the throttling and error handling.
3.  **Step Functions:**
    *   A state machine service for long-running processes (minutes to days).
    *   Provides visualization, audit trails, and integration with other AWS services.

**Step Functions Demo:**
Liel demonstrates a booking workflow (Flight -> Hotel -> Ticket -> Car) where any step might fail.
*   **The Failure Scenario:** API providers often return a `429 Too Many Requests` error with a `Retry-After` header indicating how long to wait.
*   **Scenario 1 (Naive):** Code without error handling fails most of the time.
*   **Scenario 2 (Default Handling):** Uses exponential backoff. It eventually succeeds but may sleep longer than necessary or retry blindly.
*   **Scenario 3 (Smart Handling):** The workflow extracts the `Retry-After` header value, calculates the specific date/time to resume, and passes it to the Step Function "Wait" state.
    *   **Key Benefit:** Waiting inside the Step Function (Native Sleep) costs nothing. Waiting inside code (e.g., `sleep()`) costs money for compute time.

### **Conclusion**
*   **Liel:** Move complexity (state management, retries, rate limiting) out of the code and into managed services like Step Functions and API Destinations.
*   **Boaz:** Modern applications do not run in a vacuum. To be a "good neighbor," you must design your architecture to respect the limits of the ecosystem you inhabit.