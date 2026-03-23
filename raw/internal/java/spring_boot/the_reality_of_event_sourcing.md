Resource: https://youtu.be/lWWWjwV4-3A

Based on the transcript of the presentation "The harsh reality of Event Sourcing - mitigated with Spring and Axon on Tanzu Application Platform," here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction: The "David Bike Rental" Pitch**
The speakers, Alex Bauzer and David Kohl, begin with a roleplay scenario styled after "Shark Tank." They introduce themselves as founders of a startup called "David Bike Rental".
*   **The Business Model:** They are seeking investment to hire a front-end developer and scale a unique bike rental business globally. Their goal is to replace cars with bikes and have "six million bicycles in Beijing" by the end of the year.
*   **The Technology:** The application uses a beautiful app backed by a Spring-based backend.

### **Infrastructure Strategy: Kubernetes and Tanzu**
To scale globally, the founders plan to deploy on Kubernetes because it is the universal infrastructure API. They require multi-cloud capability to switch providers for cost efficiency. However, acknowledging that Kubernetes is hard, they choose not to build their own platform or CI/CD pipelines. Instead, they utilize the **Tanzu Application Platform (TAP)** as a "software factory".

**Key Components of the Platform:**
*   **Supply Chain Choreographer (Cartographer):** This automates the path from code to production, gluing together CI/CD components so developers don't have to manage Jenkins or "snowflake" pipelines.
*   **Buildpacks:** Based on Cloud Native Buildpacks (a CNCF project), these automate the creation of containers from source code. They handle dependencies (JRE, OS layers) and security. Using **kpack**, the platform can automatically update containers across the entire fleet when base images or dependencies (like the OS) require patching, without developer intervention.
*   **Knative:** The speakers highlight the value of Knative for Java Spring developers on Kubernetes:
    *   **Knative Serving:** Provides higher-level abstractions, automatic URL routing, traffic shaping (for blue/green deployments), and auto-scaling (including scaling to zero to save costs).
    *   **Knative Eventing:** Abstracts event-driven architectures, allowing developers to plug in RabbitMQ or Kafka underneath without managing them directly.

### **Application Architecture: CQRS and Event Sourcing**
To handle the immense scale of the bike rental business, the team rejects standard CRUD architectures in favor of **CQRS (Command Query Responsibility Segregation)** and **Event Sourcing**.
*   **Event Sourcing Definition:** They capture every event (e.g., rentals, movements) to track history strictly. This allows for analytics (selling movement data to cities) and recalculating state based on a truthful representation of what happened.

### **The "Harsh Reality": Performance Challenges**
The presentation shifts to a live demo where the audience is invited to rent bikes via a QR code. The demo fails to perform adequately, showing high latency and failures. The speakers use this failure to illustrate that "events aren't magic pixie dust" and naively implementing event sourcing on a monolith leads to performance issues worse than CRUD applications.

**Identified Problems and Solutions:**
1.  **Write Performance (Relational Databases):**
    *   *Problem:* Storing events in a relational database gets slower as the dataset grows. They are not designed for streams.
    *   *Solution:* Use a dedicated **Event Store** (e.g., Axon Server), which maintains flat, high performance regardless of the number of stored events.

2.  **Read Performance (Loading Aggregates):**
    *   *Problem:* To validate a rental, the system loads the "Bike" aggregate by replaying its history. As the history grows, loading takes longer.
    *   *Attempted Solution 1 (Caching):* Caching the state in memory. In a distributed environment, this fails because requests hitting different nodes may rely on stale cache data, leading to conflicts (optimistic locking failures), retries, and actually *worse* performance than no cache.
    *   *Attempted Solution 2 (Consistent Hashing):* Routing commands for the same bike identifier to the same machine. This improves performance by ensuring local cache hits.
    *   *Attempted Solution 3 (Snapshotting):* Consistent hashing still leaves "cache invalidation spikes." Snapshotting solves this by periodically storing the aggregate's state. The system loads the latest snapshot and only the subsequent events, capping the load time and stabilizing performance.

### **Eventual Consistency**
The speakers discuss the inevitability of eventual consistency in decoupled systems.
*   **Eventual Inconsistency:** Trying to avoid eventual consistency often leads to "eventual inconsistency," where separated systems (like in banking) develop divergent truths that must be consolidated later.
*   **The UI Lag Problem:** In a typical flow (Command -> Event -> Query), the query might execute before the database updates, leading to a user renting a bike but not seeing it in their possession immediately.
*   **Solution (Subscription Query):** Using Axon's subscription queries, the UI asks for the current state *and* stays open for updates. When the event handler updates the projection, it pushes the new state to the client immediately, enabling a real-time UI without polling.

### **Scaling and Location Transparency**
The demo failure is partially attributed to the load balancer routing users to two monolithic instances indiscriminately.
*   **Goal:** The system should treat parts of the application as components, utilizing **Location Transparency**. Components should interact without knowing if they are in the same JVM or distributed.
*   **Routing Strategy:** Instead of "smart pipes" (ESB) or just "dumb pipes" (Message Broker), they advocate for **Stereotype-based Routing** (supported by Axon Server).
    *   **Events:** Pub-sub routing (something happened in the past).
    *   **Commands:** Consistent hashing routing (intent to change state, routed to specific instances for optimization).
    *   **Queries:** Point-to-point or scatter-gather (request for information).

### **Code Walkthrough and Second Failure**
The speakers attempt to show the code while the audience continues to crash the demo application.
*   **Code:** They demonstrate using Axon and Spring Boot together ("doing a Tango").
    *   `@Aggregate`: Annotates the Bike class. Spring and Axon automatically wire the necessary infrastructure.
    *   Configuration: They show how to configure snapshot triggers and weak-reference caching (allowing garbage collection to reclaim memory if needed).
    *   Projections: They use a Spring Data JPA repository and a `QueryUpdateEmitter`. When a "BikeInUse" event arrives, the handler updates the database and emits an update to any active subscription queries.

**The Second Crash:** The demo endpoint becomes completely unresponsive during the code walkthrough. The speakers jokingly blame the audience for "pounding" the environment and realize they under-provisioned the infrastructure.

### **Conclusion and Q&A**
The speakers conclude the "Shark Tank" pitch, admitting the demo crashed but inviting people to try the code via Docker Desktop or visit their booth for a working version.

**Q&A Session:**
1.  **JDBC vs. JPA:** A specific question is asked about using JDBC templates. The speaker admits using JPA out of laziness but confirms JDBC templates are a valid option.
2.  **Aggregate Lifespan:** An audience member asks if a Bike is a bad aggregate because it lives for years (too many events). The speaker agrees it is the "worst combination" (active and long-lived) but was chosen specifically to create performance problems for the demonstration.
3.  **Cause of Failure:** When asked why the demo crashed, the speakers speculate that the "scale-to-zero" or "min-scale" settings on the platform were too aggressive. When the audience hit the app simultaneously, the platform spent too much time starting new containers to handle the load.
4.  **Event Sourcing for Time Series:** A question is asked about applying event sourcing to time series data. The speaker argues event sourcing is *more* valuable than typical time series databases because it captures business intent (events) rather than just state changes, allowing for "time travel" and new insights later.