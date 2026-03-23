Resource: https://youtu.be/Lqkq4GFEP6k

Based on the transcript of the presentation **"Java 21: The revolution of virtual threads - A Deep dive"** by **Christian Woerz** at CPH DevFest 2024, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Agenda**
Christian Woerz begins by welcoming the audience to the early morning session. He introduces himself as a software engineer with 15 years of experience, currently in a full-stack role using TypeScript, JavaScript, and Java. He mentions his website (type.ro) where attendees can find his slides, GitHub, and social links.

**The Agenda:**
He outlines the structure of the talk, which focuses on building a Spring Boot application in three distinct stages:
1.  **The Blocking Approach:** The traditional way.
2.  **The Reactive Approach:** Switching to asynchronous handling.
3.  **The Migration to Virtual Threads:** Using Project Loom in Java 21.

### **Part 1: The Blocking Approach**
Woerz starts with the "early days" approach using blocking I/O (e.g., `RestTemplate`). He notes that many developers still use this for internal applications with low throughput (e.g., 100 users/day) because it lacks the overhead of reactivity.

**The Code Demo:**
*   He creates a Spring Boot application with a `Speaker` record containing just a name.
*   He builds a `FakeHTTPService` to simulate an API call. Inside, he uses `Thread.sleep(1000)` to simulate a 1-second delay, mimicking a blocking HTTP request.
*   He creates a Controller with a `/speakers` endpoint that calls this service.
*   **Performance Test:** Using **JMeter**, he simulates 1,000 concurrent users over 20 seconds.
*   **Result:** The application is slow. Initial requests take over 2 seconds, and eventually, latency rises to almost 5 seconds because the server runs out of available threads.

### **Part 2: The Problem with Platform Threads**
Woerz explains *why* the blocking approach fails at load.
*   In Java, a **Platform Thread** (the traditional thread) maps 1:1 to an **Operating System (OS) Thread**.
*   OS threads are expensive to create. Consequently, servers like Tomcat use a thread pool to reuse them rather than creating new ones indefinitely.

**The "Out of Memory" Demonstration:**
*   He runs a test creating 1,000 threads using the new `Thread.ofPlatform()` syntax. Using a script to count OS threads, he verifies that 1,000 Java threads equal 1,000 OS threads.
*   He attempts to increase this to **1 million threads**.
*   **Result:** The application crashes with an `OutOfMemoryError: unable to create native thread`.
*   **Reason:** Threads require stack memory (e.g., 1MB or 2MB). Creating 1 million threads would require approximately 1 Terabyte of RAM.
*   **Inefficiency:** He points out that during a blocking call, the CPU usage is near zero because the thread is simply waiting. To get 100% CPU usage with blocking code, you would need millions of threads, which is impossible due to memory constraints.

### **Part 3: The Reactive Approach**
To solve the throughput issue without adding threads, developers shifted to reactive programming (Java 8+, `CompletableFuture`, Project Reactor, etc.).

**The Code Demo:**
*   He creates a new endpoint `/speakers-async` returning `CompletableFuture<List<Speaker>>`.
*   He updates the service to use `CompletableFuture.supplyAsync` with a `delayedExecutor` to simulate the 1-second delay without blocking the thread.
*   **Performance Test:** Running JMeter again shows that requests finish in roughly 1 second, regardless of concurrency. The threads are freed up immediately when blocking occurs, allowing a small pool to handle high traffic.

### **Part 4: The Problem with Reactivity**
Woerz argues that while reactive works, it sacrifices simplicity. He demonstrates this by adding complexity: fetching a "Talk" for each "Speaker".

**Blocking vs. Reactive Complexity:**
*   **Blocking:** He iterates over speakers and calls `retrieveTalk` (simulated 500ms delay). The code is easy to read.
*   **Reactive:** He attempts to replicate this using `CompletableFuture`.
    *   He must use `thenApply`, `SupplyAsync`, and `CompletableFuture.join`.
    *   He has to convert a `List<CompletableFuture<Talk>>` into a `CompletableFuture<List<Talk>>`, which is complex and verbose.
*   **Downsides:**
    *   **Readability:** The code becomes "callback hell" or hard-to-read chains.
    *   **Testing:** Business logic is buried in framework code, making unit tests difficult.
    *   **Ecosystem:** You need reactive drivers for everything (e.g., R2DBC for databases) to maintain the non-blocking chain.

### **Part 5: The Virtual Threads Solution (Java 21)**
He introduces **Virtual Threads** (Project Loom), designed to bring the performance of reactive code to the simplicity of blocking code.
*   **Concept:** Virtual threads exist only in the JVM (heap), not the OS.
*   **Mechanism:**
    *   When a request comes in, a Virtual Thread is created. It "mounts" to a **Carrier Thread** (a Platform/Worker thread).
    *   When the Virtual Thread blocks (e.g., waiting for HTTP), it "unmounts" from the Carrier Thread and sits on the Heap.
    *   The Carrier Thread is free to handle other work.
    *   When the response returns, the Virtual Thread remounts to *any* available Carrier Thread.
*   **Cost:** Virtual threads are cheap (kilobytes of memory), allowing the creation of millions of them.

**Virtual Threads Demonstration:**
*   He runs a test creating **1 million virtual threads** using `Thread.ofVirtual()`.
*   **Result:** The script shows only about **40 OS threads** are created to handle the execution of 1 million virtual threads.
*   He demonstrates that a virtual thread effectively "hops" between different worker threads (e.g., Worker 1, then Worker 10) after sleeping, proving they are not tied to a single OS thread.

### **Part 6: Migrating the Application**
Woerz demonstrates how to migrate the original blocking Spring Boot application to use virtual threads.
1.  **Configuration:** In `application.properties` (Spring Boot 3.2+), he adds `spring.threads.virtual.enabled=true`.
2.  **Effect:** This changes Tomcat's executor from a thread pool to a **Virtual Thread Per Task Executor**.
3.  **Result:** He reruns the *blocking* code (from Part 1) in JMeter. It now handles the load with high performance (1-second response times), identical to the reactive approach but with simple code.

### **Part 7: Structured Concurrency**
He addresses the scenario of parallelizing sub-tasks (fetching talks for speakers) without the complexity of `CompletableFuture`.
*   **StructuredTaskScope:** He introduces this API to fork tasks.
*   **Custom Scope:** He writes a custom class `CollectionTaskScope` extending `StructuredTaskScope`.
    *   He overrides `handleComplete` to automatically add successful results to a `ConcurrentLinkedQueue`.
    *   This reduces the calling code to just a few lines: creating the scope, iterating over speakers, calling `scope.fork()`, and finally `scope.getResults()`.
*   **Result:** The endpoint processes requests in parallel (1.5 seconds total) while maintaining readable, imperative-style code.

### **Part 8: Restrictions and Pitfalls**
Woerz outlines limitations to be aware of:
1.  **ThreadLocals:** Since virtual threads are created in the millions, extensive use of `ThreadLocal` variables (which are often not cleaned up) can lead to massive memory leaks. He suggests looking into **ScopedValues** as a replacement.
2.  **Synchronized Blocks:** Using `synchronized` inside a virtual thread "pins" it to the OS thread, blocking the carrier.
    *   **Solution:** Replace `synchronized` with `ReentrantLock`. Libraries like Tomcat have already done this.
3.  **Native Calls (JNI):** Calling C code or native libraries also pins the thread because it accesses memory addresses on the stack.
4.  **CPU-Intensive Tasks:** Virtual threads do not make CPU-heavy work faster; they only help with I/O waiting.

### **Conclusion**
Woerz concludes that Java 21 completes a full circle: from blocking, to reactive, and back to blocking (powered by virtual threads).
*   **Benefits:** Easier proof of concepts, no third-party libraries needed (baked into JDK), less boilerplate, and easier testing.
*   **Closing Anecdote:** He mentions that during a previous talk, his Mac froze due to a macOS bug related to Java apps, but a recent OS update fixed it, allowing this demo to run smoothly.
*   He asks for feedback and thanks the audience.