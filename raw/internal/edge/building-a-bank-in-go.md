Resource: https://youtu.be/y2j_TB3NsRc?list=TLGGa38v0c2aT5MzMTAxMjAyNg


Based on the video transcript titled "Building a Bank with Go," here is an accurate and comprehensive extraction of the presentation by Matt Heath, a backend engineer at Monzo.

### **Introduction and Motivation**
Matt Heath introduces himself as a backend engineer who has been working with Go for over four years, transitioning from PHP. He works for Monzo, a company building a new kind of bank to replace traditional banking experiences, which he describes as outdated, requiring physical visits or phone calls,.

Traditional banks rely on disparate IT systems and mainframes running code from the 1960s, making it difficult to update systems or manage technical debt. Monzo began in February 2015, obtained a restricted banking license in August 2016, and aims to be a fully regulated bank shortly,.

### **Monzo's Features**
Monzo differentiates itself by managing everything through a mobile app. Key features include:
*   **Card Control:** Users can freeze and unfreeze their cards instantly via the app. If lost, ordering a replacement is a single tap, arriving the next day,.
*   **Transaction Visibility:** The app shows map locations for purchases, allows receipt attachments (including photos of brunch), and supports search functionality (including searching by emoji).
*   **Transfers:** Instant money transfers to other users.

### **Architectural Evolution**
Heath outlines the standard evolution of app architecture:
1.  **Monolith:** Startups usually begin with an application and a database. Over time, complexity increases, leading to a monolithic structure.
2.  **The Problem:** Monoliths create bottlenecks where developers cannot deploy features independently because they are tied to a single release pipeline managed by others.
3.  **The Solution (Microservices):** Monzo adopted a services-based architecture using the **Single Responsibility Principle** and **Bounded Contexts**. This ensures well-defined interfaces between services and allows teams to scale without stepping on each other,.

### **Why Go?**
Monzo chose Go for several reasons:
*   **Safety and Typing:** It is memory-managed and statically typed, preventing errors like number conversions,.
*   **Concurrency:** It is suited for network services requiring strong concurrency.
*   **Lightweight:** Go services consume very little memory (20–30 MB) compared to JVM applications (100 MB+), allowing for high density on hardware.

### **Concurrency in Go**
Heath details how Go handles concurrency compared to threads:
*   **Goroutines:** These are lightweight functions multiplexed across threads by the Go runtime. They are efficient, with low switching costs and dynamic stack sizes starting around 8KB (vs. megabytes for threads),,.
*   **Implementation:** Using the `go` keyword runs a function concurrently.
*   **Communication:** Go follows the mantra: "Do not communicate by sharing memory; share memory by communicating." Instead of mutexes/locking, Go uses **Channels** to pass values between goroutines,.
*   **Channel Patterns:**
    *   **Pipelines:** Data flows from one worker to another.
    *   **Buffered Channels:** Channels can have a size limit. Heath cites **NSQ** (a messaging system) which uses a buffered channel of 10,000 items in memory before writing to disk, implemented in just a few lines of code,.
    *   **Fan-in/Fan-out:** Distributing work to multiple workers scaling independently.

### **Language and Deployment Benefits**
*   **Simplicity:** Go has a small syntax and creates a single executable binary, eliminating the need to manage runtimes or source trees on servers,.
*   **Standard Library:** It is robust; a production-ready HTTP server (with HTTP/2 support) requires only a few lines of code,.
*   **Deployment:** The process involves compiling the binary, putting it on a server (or S3), and running it.

### **Monzo’s Microservices Infrastructure**
Monzo grew from zero to over 190 discrete Go services.
*   **Tooling:** While tools like **Go kit** and **Micro** exist now, Monzo built a simple library called **Typhon** to handle HTTP services.
*   **Communication:** Services communicate via HTTP. To handle the unreliability of networks (load balancing, timeouts, circuit breaking), Monzo uses **Linkerd**,. Linkerd is a "service mesh" sidecar that manages RPC complexity, allowing Monzo to keep their Go services simple.

**Routing Architecture:**
1.  **Load Balancer:** AWS ELB sits at the top.
2.  **Routing Layer:** A Go-based HTTP layer routes requests to API services based on names (e.g., `/webhooks` routes to the webhook service). This layer rarely changes,.
3.  **API Services:** Small Go binaries that handle business logic (e.g., registering a webhook).
4.  **Interfaces:** Go’s simple interfaces allow defining a service as just a function that takes a request and returns a response. This allows developers to spin up new APIs and deploy them to production in under 30 minutes,.

**Containerization and Kubernetes:**
*   **Docker:** Go binaries allow for "scratch" containers (no shell, very small size), which improves security.
*   **Kubernetes:** Monzo switched from Mesos to Kubernetes, reducing infrastructure costs by two-thirds due to denser packing. Kubernetes handles pod auto-scaling and replication for reliability.
*   **Resiliency:** If a pod fails or is slow, Linkerd automatically balances traffic to faster instances using exponentially weighted moving averages.

### **Asynchronous and Event-Driven Architecture**
Monzo decouples critical paths from non-critical ones using an event-driven model.
*   **Synchronous:** Critical actions (e.g., creating a transaction) happen synchronously.
*   **Asynchronous:** Once a transaction is created, an event is published. Downstream consumers handle non-critical tasks like budgeting, merchant enrichment, or push notifications independently.

### **Distributed Tracing**
With hundreds of services, understanding flow is difficult. Monzo uses Go's **`context`** package (standard in Go 1.7+).
*   **Request IDs:** A unique Request ID is generated at the edge and passed in the context through every function call and over the wire (via headers) to every service.
*   **Visualization:** This data is aggregated into a system (like Zipkin) to visualize the timing and flow of requests across the entire infrastructure.

### **Detailed Transaction Flow**
Heath breaks down exactly what happens when a card is used:
1.  **The Swipe:** A card machine sends a message (often ISO 8583/soap) to Monzo.
2.  **Synchronous Checks:** Monzo checks if the card is frozen, validates the PIN/balance, and returns a success/fail response to the merchant. This must happen immediately so the user can leave the shop,.
3.  **Asynchronous Enrichment:** Parallel to the response, an event is published. The system enriches the transaction (finding the merchant logo, map location, checking budget targets),.
4.  **Push Notification:** The enriched data is pushed to the user's phone. Because computers are faster than 2G/3G networks, the notification often arrives before the paper receipt prints,.

### **Polyglot Environment**
While 99% of services are Go, Monzo uses other languages where appropriate:
*   **Python:** Used for data analysis and machine learning.
*   **Java/Scala:** Used for specific integrations like IBM MQ where Go libraries are less mature.

### **Q&A Session**
*   **Credit/Loans:** Monzo plans to offer overdrafts but not loans/mortgages initially.
*   **Security:** Security involves segregating AWS accounts (management vs. usage), using network policies (Calico) in Kubernetes, and internal Certificate Authorities (CA) for service authentication. They assume clients are untrusted,.
*   **Availability:** Currently UK-only, but cards work globally (MasterCard).
*   **Linkerd Deployment:** It is deployed as a **DaemonSet** in Kubernetes (one copy per physical host). Pods communicate with the local Linkerd instance via the host IP, which then handles service discovery and routing.
*   **Testing:** They use acceptance tests that run against the full stack (dockerized infrastructure) on every commit. In production, they simulate customer behavior (like a "train track" driving a card past a terminal) to verify end-to-end functionality,,.