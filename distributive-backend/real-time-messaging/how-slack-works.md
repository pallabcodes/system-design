Resource: https://www.youtube.com/watch?v=WE9c9AZe-DY

Based on the transcript of the presentation "How Slack Works" by Keith Adams, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Scope**
Keith Adams, Chief Architect at Slack, introduces the talk as a focus on the core, original use case of Slack: persistent group messaging. He distinguishes Slack from IRC by emphasizing **persistence**—the ability to catch up on history after being offline—and describes the product as a "virtual water cooler",. He notes that while the concept is simple, executing it at scale and operating it is challenging. He aims to present a case study of a typical Slack session, covering the infrastructure, current challenges, and future plans.

### **Scale and Usage Patterns**
*   **User Base:** Slack operates at "mega scale" (millions of users), not "giga scale." They have a peak of 2.5 million connected users, which Adams believes might be the largest instantaneous number of open WebSocket connections in existence.
*   **Intensity:** Usage is highly intensive. The average user is actively in focus for over two hours per workday and connected for ten hours.
*   **Demographics:** 50% of daily active users are outside the US.

### **Engineering Philosophy**
Adams describes Slack's engineering style as "**conservative**".
*   **Core Infrastructure:** The hard problems (storage, memory, compute, networking) are solved using established technologies rather than bleeding-edge tools which may have "ten years of bugs".
*   **Build vs. Buy:** They are willing to write code. For example, rather than tuning off-the-shelf software like Kafka, Slack’s message bus is written in Java by their team. This ensures the software does exactly what they want and they have in-house expertise to operate it,.
*   **Minimalism:** They avoid introducing new dependencies (e.g., Cassandra) if existing ones (Redis, MySQL) can suffice.

### **High-Level Architecture**
The architecture consists of clients (iOS, Mac, Windows, etc.) interacting with two main gateways in the backend:
1.  **The Web App:** A RESTful application stack.
2.  **The Message Server:** Real-time infrastructure.

Adams draws an analogy between Slack’s architecture and a **Massively Multiplayer Online Game (MMOG)**. Both involve a persistent world (the team) and a thick cache of that world state, requiring low-latency updates for mutations.

### **The Session Lifecycle: `rtm.start`**
When a user logs in, the client hits the `rtm.start` (Real-Time Messaging) API endpoint.
*   **The Web App Stack:** This endpoint is hosted on a "**PHP monolith**" (approx. 1 million lines of code). It creates the "keyframe" or bootstrap state of the world for the client.
*   **Technology Stack:** It is a competent "LAMP stack" using Memcached and MySQL. They use **HHVM** (Facebook's JIT for PHP) and **Hack Lang** (gradual typing).
*   **Adams on PHP:** He posits that PHP is a "bad programming language" but a "very good choice" for this specific application logic due to its stateless nature and concurrency model.

### **Data Storage and Partitioning**
*   **Sharding by Team:** Data is sharded by "Team." This is not done via consistent hashing but through an arbitrary lookup table.
*   **"The Mains":** A specific database pair called "the mains" stores the metadata mapping domains/teams to specific shards. This allows for manual or automatic splitting of shards.
*   **Bootstrapping:** The `rtm.start` process executes thousands of SQL queries to construct the initial payload (users, channels, profile pictures).

### **Database Architecture (MySQL)**
Slack uses MySQL not just for storage but in a specific "active-active" configuration across two data centers.
*   **Master-Master Replication:** They use Master-Master replication to create an eventually consistent store. This prioritizes write availability and automatic master promotion during failures,.
*   **Conflict Resolution:** Conflicts do happen. Most are resolved automatically via application logic (knowing what the user intended), but some require manual intervention.
*   **Consistency Tricks:** To minimize "read-what-you-wrote" issues, they use the Team ID to direct writes: even-numbered teams prefer the "left" head, and odd-numbered teams prefer the "right" head, failing over only if necessary.

### **Real-Time Messaging (The Message Server)**
Once `rtm.start` returns the state and a WebSocket URL, the client connects to the **Message Server**.
*   **Function:** The Message Server is a Java application that acts as a "write amplifier," broadcasting events to connected users and persisting messages to the future (via the Web App/Database).
*   **The Gap:** There is a race condition between the API call returning and the WebSocket connecting. The Message Server maintains a buffer (approx. 30 seconds) of recent events to "catch up" the client upon connection,.
*   **Persistence:** The Message Server side-calls the Web App to persist messages. It maintains local queues (memory and disk) to handle network weather or temporary backend unavailability.
*   **Presence:** A major load driver is "presence" (green dots/online status). This generates **$N^2$ traffic** relative to team size because every user update must be broadcast to every other connected user.

### **The Job Queue**
Slack uses an asynchronous job queue (manifested in Redis) to handle long-running tasks ("bottom half" work) like link unfurling or data imports. This keeps the web request ("top half") fast. Workers poll Redis to execute these tasks,,.

### **Additional Components**
*   **Memcached:** Used heavily for read caching. Currently manual (engineers decide what to cache).
*   **Search:** Powered by Solr. Indices are updated in real-time via the Job Queue.
*   **CDS (Computer Data Service):** Handles search quality and machine learning models via a Thrift interface.
*   **Rate Limiting:** Pervasive throughout the system to prevent overload.

### **Current Challenges**
1.  **"The Mains" as Single Point of Failure:** The metadata database is a bottleneck. If both heads fail (as happened in November 2015), Slack is essentially down for new connections,.
2.  **Quadratic Load on `rtm.start`:** As teams grow, the payload size for `rtm.start` grows quadratically (users $\times$ channels). For large teams, this payload is massive, and generating it places immense load on the database.
3.  **Mass Reconnects:** If a large office (e.g., 1,000 users) loses internet and reconnects simultaneously, the **$N^3$ load** (quadratic payload $\times$ number of users) hits the specific database shard and "The Mains" simultaneously, potentially causing outages.

### **Solutions and The Future: Flannel**
To address these scalability issues, Slack is developing **Flannel**.
*   **What is it?** An application-aware **Edge Cache**.
*   **Function:** It caches the results of `rtm.start` and session data. It sits closer to the user (in remote POPs) and mediates the connection.
*   **Benefits:** It offloads the heavy lifting from the Web App and Database. It allows independent scaling of edge capacity versus backend capacity.
*   **Status:** At the time of the talk, it was in use internally by Slack employees and expected to roll out to customers soon.
*   **Client Architecture Changes:** They are also moving clients toward partial queries rather than downloading the full state at startup.

### **Q&A Session**
1.  **Three Data Centers:** Moving from 2 to 3 data centers with Master-Master replication is difficult because the replication logic doesn't form a clean ring. They may move to a Master/Slave model with a "write capital" or per-shard write heads.
2.  **Hot Spots:** Currently handled by alerting, manual sharding/splitting, and throwing expensive hardware at the problem.
3.  **Security/Privacy:** Team partitioning makes intrusion attempts more legible. Developers do not have access to production environments or data.
4.  **Engineer Satisfaction with PHP:** Engineers coming from environments like Facebook understand it; others find it surprising. While they may not love the language, they love the ability to deploy 40 times a day, which the architecture enables.

Resource 2: https://youtu.be/C4AUHFhzYZo

Based on the provided transcript of the presentation "Scaling Slack" by Bing Wei, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Growth**
Bing Wei, a software engineer on Slack’s infrastructure team, introduces the platform's structure and growth trajectory. Slack is organized by "teams," where users join channels (self-selected groups sharing interests) to send real-time messages, upload files, search content, and use apps.

She presents specific numbers to illustrate the scale of growth:
*   **2016:** Slack had 4 million Daily Active Users (DAU). The largest team had 20,000 users, and peak simultaneous connections reached 2.5 million.
*   **Current (at time of talk):** Slack has grown to 10 million DAU. The largest team has over 400,000 users (a 20x increase). Peak concurrent connections reached nearly 8 million.

The core challenge addressed is how to scale Slack to 10x its current size while ensuring reliability and security, particularly given past instances of degraded performance.

### **The 2016 Architecture**
In 2016, Slack’s architecture relied on two main components:
1.  **Web App:** An HTTP service handling business logic (authentication, request processing).
2.  **Message Server:** A real-time event hub using WebSockets (a duplex communication protocol) to push updates between clients and servers.

**The Connection Flow:**
1.  A user connects by sending an `rtm.start` HTTP request to the Web App.
2.  The Web App authenticates the user and returns a payload containing team data (users, channels) and a WebSocket URL.
3.  The client establishes a long-standing WebSocket connection using that URL to receive real-time updates from the Message Server.

This model worked well when Slack was small because clients cached data locally, making interactions feel fast. Scaling was simple: as more teams joined, Slack simply added more servers, as everything was scoped by team.

### **Scaling Challenges**
As the user base grew, four specific challenges emerged:
1.  **Connection Slowness:** The initial payload size grew with team size, causing slow connection times.
2.  **Thundering Herd:** Establishing connections is expensive; mass reconnections made Slack vulnerable.
3.  **Database Hotspots:** The sharding strategy created uneven load.
4.  **Failures:** The need to remain resilient despite inevitable hardware or network failures.

### **Challenge 1: Connection Slowness**
**The Problem:** The payload sent during `rtm.start` grows with the number of users and channels. For a team with a few hundred users, the payload is kilobytes. For thousands, it is megabytes. For teams with hundreds of thousands of users, the payload becomes massive, making it nearly impossible to connect reasonably on mobile or low-bandwidth networks.

**The Solution: Lazy Loading and "Flannel"**
Slack introduced **Client Lazy Loading**, where clients download less data upfront and load the rest on demand. This required rewriting the client data access layer to stop assuming data is always locally available. To mitigate the latency of remote loading, Slack built **Flannel**:
*   **What it is:** An application-level edge cache service deployed in 10 regions globally to be closer to users.
*   **The Name:** It was named "Flannel" simply because the lead engineer was wearing a flannel shirt when the project started.
*   **How it works:** Flannel caches team data in-process. It subscribes to the Message Server (acting like a client) to receive real-time updates on users and channels.
*   **Results:** Flannel provides HTTP and WebSocket APIs. By serving queries from the edge region closest to the user, p99 latency for channel membership queries dropped by two seconds. This also alleviated the Thundering Herd problem by making connections lightweight.

### **Challenge 2: Database Hotspots**
**The Problem:** Slack originally used MySQL sharded by Team. A "Main Shard" mapped Team IDs to Shard IDs.
*   **Drawbacks:**
    *   **Single Point of Failure:** If the Main Shard failed, no data could be accessed.
    *   **Hotspots:** Large teams created very busy shards, while others were idle.
    *   **Manual Splitting:** Moving large teams off busy shards was a manual process.
    *   **Feature Limitations:** New features like "Shared Channels" (where two teams share a channel) broke the model because data could not cleanly reside on just one team's shard.

**The Solution: Vitess**
Slack migrated to **Vitess**, an open-source project providing flexible sharding on top of MySQL.
*   **Flexible Sharding:** It allows sharding by different keys based on usage (e.g., sharding the Users table by User ID and the Channels table by Channel ID) rather than just by Team.
*   **Abstraction:** The application views the database cluster as a single logical database, while Vitess handles routing and topology.
*   **Migration Process:** The migration is done feature-by-feature involving query analysis, double-writing to both systems, backfilling historical data, and finally flipping the switch. At the time of the talk, 20% of traffic was served by Vitess.

### **Challenge 3: Resiliency and Failures**
To handle hardware failures, network partitions, traffic surges, and bugs, Slack adopted three resiliency measures.

**1. Auto-Scaling**
Using AWS tools, Slack scales clusters up or down based on metrics like CPU usage, memory, or packets per second. It scales up fast during surges and scales down slowly.

**2. Admission Control (Rate Limiting)**
To protect servers from overload, Slack tracks concurrent requests.
*   **Mechanism:** A counter increases when a request arrives and decreases when it finishes.
*   **Static Limits:** Reject traffic if the count exceeds a tested static capacity.
*   **Dynamic Limits:** Reject traffic based on real-time CPU or memory usage thresholds.
*   **Benefit:** Combined with auto-scaling, this manages Thundering Herds by rejecting excess traffic while waiting for new servers to spin up.

**3. Regional Failover**
Slack uses multiple regions (e.g., three in Europe).
*   **Server-Side Failover:** If a region is detected as unhealthy (via load balancer health checks), Slack updates DNS to block that region's IP, routing new traffic elsewhere.
*   **Client-Side Failover:** Used for partial/localized failures. When a client connects:
    1.  It asks DNS for the primary WebSocket URL (e.g., Dublin).
    2.  If that fails, it asks for a secondary URL.
    3.  DNS provides a list of healthy nearby regions (e.g., London or Dublin).
    4.  The client picks one randomly.
    *   **Result:** With three retries, there is an 87.5% chance of reaching a healthy region. This was demonstrated when traffic from a failing Sao Paulo region automatically shifted to US and EU regions.

### **Q&A Session**
*   **Analytics Infrastructure:** The audience asked if the described infrastructure handles analytics. Bing Wei clarified that the talk focused on messaging and Flannel; analytics utilizes a different infrastructure.
*   **Lazy Loading Rollout:** A question was raised about the consequences of not delivering all data immediately (Lazy Loading). Wei explained it was not a one-step switch but a year-long gradual rollout. They started by putting user data into Flannel, prototyped it, dog-fooded it internally, and then gradually moved channel objects, memberships, and user groups into the service.