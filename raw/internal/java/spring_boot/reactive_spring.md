Resource: https://youtu.be/1F10gr2pbvQ


Based on the transcript of the video "Reactive Spring • Josh Long • GOTO 2019," here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Announcements**
Josh Long begins by welcoming the audience and noting the limited time available (approx. 50 minutes) compared to the several hours he wished for. He encourages attendees to join his "masterclass" session scheduled later in the conference (an eight-hour session). He directs the audience to the slides for code examples and his contact information, specifically highlighting Twitter as the best place to reach him and the developer community ("the new IRC"). He briefly mentions his disdain for email and preference for Slack, joking that Slack might be mining Bitcoin based on its CPU usage.

### **Speaker Background**
Josh Long introduces himself as a Spring Developer Advocate at Pivotal (now part of VMware) and mentions his presence on WeChat for Chinese attendees. He lists his various content outputs:
*   Detailed video courses on Safari.
*   The "Cloud Native Java" book.
*   "A Bootiful Podcast" (released every Friday).
*   "Spring Tips" screencasts (released every Wednesday).
*   His new book, "Reactive Spring," which covers the session's topic in long form.

### **The Case for Reactive Programming**
Long explains that reactive programming is a new response to an old problem: **Scaling Input/Output (I/O)**. As organizations move to microservices, Big Data, IoT, and NoSQL, they struggle to scale the increasing amount of network data.

**The Problem with Traditional Threads:**
*   In traditional JVM-based applications using `java.io` (InputStream/OutputStream), a thread blocks while waiting for data.
*   Scaling by creating more threads is not viable because:
    *   **Expense:** Threads are expensive in terms of memory (approx. 1MB stack size per thread) and OS management. A thousand threads equal a gigabyte of RAM just for startup.
    *   **Scheduling:** You cannot truly schedule thousands of things simultaneously unless you have thousands of cores. The OS relies on time-slicing (context switching), which is an illusion of concurrency.

**The Horizontal Scaling Workaround:**
*   The pragmatic industry response has been horizontal scaling in the cloud (Cloud Native).
*   By making services stateless (12-factor apps), developers can spin up many instances behind a load balancer.
*   While effective, this is expensive and inefficient because it ignores the inefficiencies within the code itself.

**The Core Inefficiency:**
*   Blocking I/O wastes CPU cycles. When a thread waits for bytes (latency, network outages), it sits idle and cannot be repurposed.
*   **The Solution: Asynchronous I/O:** You request data and provide a callback. The thread is immediately freed for other work. When data arrives, an interrupt triggers the callback. This allows a single thread to handle thousands of requests (solving the C10K problem).

### **The Standardization Journey**
Long notes that Asynchronous I/O is not new—it has been in operating systems for decades and in Java (NIO) since version 1.4 (2002). However, developers rarely write low-level NIO code. They work with higher-level abstractions (Collections, Spring, Hibernate).

**The Need for a New Metaphor:**
*   If underlying frameworks (like Hibernate) are hostile to asynchronous types, developers won't use them.
*   To make asynchronous I/O usable, the ecosystem needed a shared, standardized abstraction.
*   **Reactive Streams Specification (2015):** Created by Pivotal, Netflix, Lightbend, Eclipse, and others to define types for potentially unbounded, asynchronous, latent streams of data with flow control. These types were eventually incorporated into Java 9 (java.util.concurrent.Flow).

**The Reactive Stack:**
1.  **Reactive Streams:** The foundational types (Publisher, Subscriber, Subscription, Processor).
2.  **Implementation Libraries:** Project Reactor, RxJava 2, Akka Streams. These provide operators to manipulate streams.
3.  **Framework Support:** Spring Framework 5 (September 2017) was the first release to natively support Project Reactor, followed by Spring Data Kay, Spring Security 5, Spring Boot 2.0, and Spring Cloud Finchley.

### **Coding Demonstration 1: Reactive Data Access**
Long moves to "start.spring.io" to generate a project with the following dependencies:
*   Java 11
*   Reactive Web
*   Lombok
*   DevTools
*   Reactive MongoDB
*   RSocket

**Setting up the Entity:**
*   He creates a MongoDB entity class `Reservation` with an `@Id` and uses Lombok's `@Data`, `@AllArgsConstructor`, and `@NoArgsConstructor` to avoid boilerplate code.

**The Reactive Repository:**
*   He defines a `ReservationRepository` extending `ReactiveCrudRepository`.
*   The methods look standard (`save`, `findAll`), but the types are different. They utilize **Reactive Streams types**:
    *   **Publisher<T>:** Publishes items to a Subscriber.
    *   **Subscriber<T>:** Consumes items via `onNext`, handles errors via `onError`, and completion via `onComplete`.
    *   **Subscription:** The link between the two. Crucially, it enables **Backpressure** (Flow Control). The consumer requests `n` records via `subscription.request(n)`, preventing the producer from overwhelming the consumer.

**Project Reactor Types:**
*   **Mono:** A Publisher producing at most one value (0 or 1). Like an asynchronous `CompletableFuture`.
*   **Flux:** A Publisher producing 0 to N values. Like a Java Stream but supports backpressure.

**Writing the Logic:**
Long writes a `SampleDataInitializer` to seed the database:
1.  Creates a Flux of names (Josh, Dr. Syer, Violeta, Stéphane, Madhura, Sebastian).
2.  Maps names to `Reservation` objects.
3.  Uses `flatMap` to save them via the repository (unpacking the `Mono<Reservation>` returned by save).
4.  **The Pipeline:** He constructs a pipeline that deletes all existing data, then saves the new data, then finds all data, and finally subscribes to log the results.
5.  **Schedulers:** He notes that `subscribeOn` can control which thread pool runs the logic, but defaults are usually sufficient (one event loop per core) as long as code is non-blocking.
6.  He runs the app, demonstrating data being written and queried.

*(Side Note: Long humorously complains about IntelliJ IDEA's "Hide ASCII Art" checkbox in the run configuration, sharing a screenshot from a JetBrains friend claiming it will be removed, though he remains skeptical.)*

### **Coding Demonstration 2: Reactive Web (HTTP)**
**Spring WebFlux Controller:**
*   He creates a `ReservationRestController`.
*   Instead of the Servlet API, this uses Spring WebFlux, built on Netty.
*   He creates a standard `@GetEndpoint` returning `Publisher<Reservation>`.

**Server-Sent Events (SSE):**
*   He demonstrates a streaming endpoint. HTTP is usually request/reply, but SSE allows long-lived connections for streaming text.
*   He creates a helper class `GreetingsRequest` and `GreetingsResponse`.
*   He creates a producer that generates a new `GreetingsResponse` every second using `Flux.interval`.
*   The endpoint returns `MediaType.TEXT_EVENT_STREAM_VALUE`.
*   When accessed in the browser, it pushes a new JSON object every second without blocking a thread on the server.

**Functional Reactive Endpoints:**
*   Long shows an alternative to `@RestController`: Functional Reactive Endpoints using Router Functions.
*   He defines routes programmatically (e.g., `route(GET("/reservations"), request -> ok().body(repository.findAll(), Reservation.class))`).

### **Coding Demonstration 3: R2DBC (Reactive SQL)**
Long addresses the common question: "What about SQL?"
*   JDBC is blocking and synchronous.
*   He introduces **R2DBC (Reactive Relational Database Connectivity)**, an open specification for non-blocking SQL drivers. Implementations exist for PostgreSQL, H2, Microsoft SQL Server, and MySQL.
*   **Warning:** At the time of the talk, R2DBC was not yet General Availability (GA). He compares its stability playfully to PHP ("Never the two shall meet in production").

**Migration to R2DBC:**
1.  He swaps MongoDB dependencies for R2DBC and PostgreSQL dependencies.
2.  He changes the repository to extend `ReactiveCrudRepository` (which works for both).
3.  He manually configures the `ConnectionFactory` for PostgreSQL (since auto-configuration wasn't ready in that snapshot).
4.  He updates the Entity to use a generated ID (Long) instead of a String ID.
5.  He runs the app, proving that the reactive stack works identically with a relational database (PostgreSQL).

### **Coding Demonstration 4: RSocket**
Long critiques HTTP as an application protocol:
*   It lacks fire-and-forget, bi-directional streaming (without hacks like WebSockets), and proper headers in WebSockets.
*   It is text-based (inefficient for binary) and typically requires polling or inefficient encoding (Base64).

**Introducing RSocket:**
*   Created by engineers from Netflix (who moved to Facebook) to solve service-to-service communication.
*   It is a binary, message-driven protocol that is natively reactive.
*   It supports Request/Response, Request/Stream, Fire-and-Forget, and Channel (bi-directional streams).
*   It has features like backpressure and availability reporting built-in.

**RSocket Demo:**
1.  **Server:** Long adds `spring-boot-starter-rsocket`. He creates a controller using `@MessageMapping("greetings")` (similar to Spring MVC but for RSocket). It accepts a stream request and returns a `Flux` that emits data every second.
2.  **Client:** He builds a separate client application.
    *   He configures an `RSocketRequester` (similar to `WebClient` or `RestTemplate`).
    *   He connects to the server on port 8000 using TCP.
    *   He creates a REST endpoint on the client side that accepts an HTTP request (SSE), delegates to the RSocket backend to get the stream, and pipes the results back to the browser.
3.  **Result:** The browser connects to the client (HTTP/SSE), the client connects to the server (RSocket/TCP), and data streams efficiently end-to-end.

### **Conclusion**
Josh Long concludes by emphasizing the efficiency and potential of RSocket and the reactive stack. He thanks the audience and reminds them once more about his upcoming masterclass.