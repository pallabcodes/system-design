Resource: https://youtu.be/jQNCuD_hxdQ

Based on the transcript provided, here is an accurate, comprehensive extraction of Marty Weiner’s presentation "Scaling Pinterest," covering the talk from start to end without skipping details or simplifying the technical depth.

### Introduction: The Scaling Story
The presentation begins with a host introduction, noting that while conferences often focus on new, fancy technologies, this talk highlights the value of keeping things simple to achieve scale.

Marty Weiner introduces the trajectory of Pinterest, describing the "mystical magical tour" of building the company from the ground up, including the evolution of their technology, lessons learned, and mistakes made.

### The Evolution of Pinterest
**Phase 1: The Beginning (March 2010)**
*   **The Team:** Two founders (eating Doritos and Ramen) and one engineer.
*   **The Goal:** Moving fast to figure out the product (images, followers, feeds).
*   **Engineering Philosophy:** Optimized for speed of design rather than engineering perfection. The underlying tech was "barely held together".

**Phase 2: Stealth Mode (The next 9 months)**
*   **Infrastructure:** They moved to Amazon AWS (likely for credits).
*   **The Stack:**
    *   **Load Balancing:** NGINX at the top.
    *   **App Server:** 4 web engines running Python.
    *   **Database:** MySQL with one read slave to offload reads.
    *   **Task Queue:** Used for sending emails and social posts (Facebook/Twitter).
    *   **Counters:** A MongoDB box (because "everybody has a MongoDB box").
*   **Office:** The "International Headquarters" was a small apartment where the boardroom was a bedroom.

**Phase 3: The "Fire" Period (2011)**
*   **Growth:** The site took off, doubling every month and a half. "Everything’s on fire."
*   **The Database Trap:** With databases angry, vendors and hype led them to adopt too many technologies. With only three engineers, they were running:
    *   MySQL, Cassandra, Membase, Memcached, Redis, Elasticsearch, and MongoDB.
*   **The Failure:** They learned that every one of these technologies will fail, usually at 3:00 AM. Being the biggest user of a technology is dangerous because you trip over landmines no one else has found yet.

**Phase 4: Re-architecture (Early 2012)**
*   **Consolidation:** They finished a massive re-architecture. They aggressively simplified, removing most of the "fancy" technologies.
*   **The Survivors:** They stripped the stack down to **MySQL, Redis, and Memcached**.
*   **Scaling Strategy:** Once simplified, they reached a point where they could simply "throw boxes at the numbers" (linear scaling) using money to solve growth.

**Phase 5: Scaling People (Late 2012–2013)**
*   **Specialization:** As the team grew, engineers stopped doing "everything." They differentiated into specific roles (Ops, Mobile, Data Infra).
*   **Management:** Reaching 100–130 people required introducing structure, feedback loops, and managers. This introduced cultural anxiety (e.g., "What if we hire 20 Google engineers? Will we become Google?").
*   **Team Splits:** They formed dedicated teams:
    *   **Data Infrastructure:** To ensure the business doesn't "fly blind."
    *   **Search, Spam, Web, Mobile, Growth.**
    *   **Infrastructure & Operations.**
*   **Physical Scaling:** They moved from Palo Alto to San Francisco. Weiner notes that physical distance (even within a building) increases "context switch time" and impedes communication.

### Technical Architecture
Weiner provides a high-level view of the stack used to support the scale at the time of the talk:

1.  **Traffic Entry:**
    *   **AWS ELB (Elastic Load Balancer):** Used for "magic hardware" capabilities like deflecting DDoS attacks.
    *   **Software Load Balancer:** An intermediate layer (using Varnish or similar) to handle granular tasks like blocking specific IPs (e.g., a university student scraping the site).
2.  **Application Layer:**
    *   **Python:** The business logic layer. Web apps talk to the API layer; mobile apps talk directly to the API.
3.  **Task Processing (Pinlater):**
    *   A MySQL-based queue where tasks are inserted, and a sea of Python processes pull them out by priority. They moved away from complex queuing systems (like RabbitMQ) to this simpler method for ACID compliance.
4.  **Storage & CDN:**
    *   Images stored in **Amazon S3**.
    *   Fronted by CDNs like **Akamai**.
5.  **Service Oriented Architecture (SOA):**
    *   **Connection Management:** They use **Zookeeper** to manage connections between the app layer and services. They explicitly **removed load balancers** between internal services to avoid the "middle tier hassle." Apps connect directly to service instances.
    *   **Service Examples:**
        *   **Search Service:** Abstracts away the complexity of indexing.
        *   **Feed Service:** Handles fan-out of pins.
        *   **MySQL Service:** Protected "NASA-style" code. Only a specific team touches this to prevent data corruption (e.g., prevent writing data to the wrong shard).
        *   **Spam Service:** Allows rapid deployment (every 30 seconds) compared to the monolithic main codebase.
6.  **Data Persistence:**
    *   **MySQL:** Primary storage (sharded).
    *   **Memcached & Redis:** Caching and specific data structures.
    *   **HBase:** A newcomer for specific use cases.
7.  **Data Pipeline:**
    *   **Kafka:** The "firehose" that captures all site activity.
    *   **Secor:** A tool to chop Kafka logs and save them to S3 for durability.
    *   **Processing:** Once data is in S3, it is fed into Elastic MapReduce (EMR) or Redshift for analysis.

### Evaluation Framework: Choosing Technology
Weiner outlines how they decide which technologies to adopt, warning against using the "latest and greatest" unless you are building a time machine (the "Flux Capacitor" rule).

**The Questions They Ask:**
1.  **Does it meet needs?** (e.g., MySQL is bad for geographic lookups).
2.  **How Mature is it?** Weiner defines maturity as **(Blood and Sweat) / Complexity**.
    *   **MySQL:** High "blood and sweat" (Facebook has beaten it down), high maturity.
    *   **Memcached:** Extremely simple (hash table with a socket), therefore high maturity.
    *   **MongoDB (at the time):** Low "blood and sweat" but high complexity = low maturity.
3.  **Can you hire for it?** You can find MySQL experts anywhere. HBase experts are rare.
4.  **Is the community active?** If it breaks at 2:00 AM, are there answers on StackExchange? For mature tech, yes. For niche tech (like Membase at the time), the only user in the chat room might be asleep.
5.  **Robustness:** MySQL has never lost their data. Other NoSQL vendors have told them "Sorry, data gone" after drive corruption.
6.  **Debugging Tools:** Mature tech has profilers and online backups.
7.  **Scalability:** MySQL doesn't scale past one box without sharding, whereas NoSQL promises to, though often fails to deliver easily.

### Technology Deep Dive
**1. Amazon AWS**
*   Used EC2, S3, ELB, Route 53 (DNS).
*   **Pros:** "The promise of a new box in seconds changes your whole world." Good security, reliability is generally good despite complaints.
*   **Cons:** Not cheap.

**2. Python**
*   **Pros:** Mature, fast development, excellent libraries.
*   **Cons:** Interpreted (slower), and the Garbage Collector is "stop the world" (source code for GC is suspiciously short).
*   **Transition:** They are moving to **Java and Go** for high-frequency, low-variance systems (like search indexers and MySQL proxies).

**3. MySQL & Memcached**
*   **Verdict:** "These suckers just worked."
*   **Performance:** Response time degraded linearly (predictable) rather than falling off a cliff.
*   **Use Case:** Primary storage for users, pins, boards, and legal compliance data requiring ACID.

**4. Redis**
*   **Verdict:** Surprised them with its reliability and utility.
*   **Features:** Key-value store with data structures (Sets, Lists, Sorted Sets).
*   **Persistence:** They use **Snapshotting** (saving to disk every few hours). If a box dies, they accept losing a few hours of data (e.g., in a feed) for the sake of simplicity and uptime, rather than stalling the disk.
*   **Use Cases:**
    *   **Follower Graph:** Stored entirely in Redis.
    *   **Public Feeds:** Unlike MySQL (which uses B-Trees and is slow for "insert at top" feed operations), Redis has O(1) list insertions.

**5. HBase**
*   **Why:** Redis is expensive because it requires RAM. HBase allows storage on hard drives, supporting massive datasets that don't fit in memory (e.g., expanding feed history from 500 to 10,000 items).
*   **Pros:** Fast tail-appends (O(1)), strong Hadoop integration.
*   **Cons:** Hard to hire for (had to grow their own experts).
*   **Use Cases:** User feeds, Rich Pin details, Spam features.

**6. Failed Technologies**
*   Weiner alludes to technologies that failed (e.g., Membase, Cassandra, MongoDB in early days).
*   **Issues:** No community support, opaque error messages (e.g., "07 EFA AB is opaque"), lack of debugging tools, and catastrophic data loss.

### Lessons Learned: "If I Could Do It Again"
1.  **Logging:** Log to Kafka/S3 immediately on Day 1. Do not log to MySQL (it's a tree, bad for logging).
2.  **Metrics:** Use **StatsD** (from Etsy) immediately. It uses UDP (fire and forget) to track counters and timers.
3.  **Alerting:** Install Nagios or Monit on Day 1 to allow founders to sleep.
4.  **Sharding:** Start sharding the moment you create your first **Read Slave**. Read slaves introduce subtle bugs (lag); sharding solves the capacity problem correctly.
5.  **NoSQL:** Avoid in the early days. Stick to simple tech until you have the engineering team to support the complexity.
6.  **Task Queues:** Don't use complex clusters like RabbitMQ. Use **PyRes** (Redis-based). Split queues into "Important" (Create Pin) and "Unimportant" (Send Tweet) so critical tasks aren't blocked.
7.  **Operations:** Hire an Ops person early to Puppetize/Chef the infrastructure for fast recovery.
8.  **Testing:** Implement Unit Testing and **A/B Testing** (Decider framework) early to control feature rollouts.

### Future and Q&A
*   **Future Challenges:** Growing to 400+ people, maintaining a fun culture, and speeding up development (building "more Legos").
*   **Q&A on Zookeeper:** They use it for configuration management and discovery. Weiner wonders if it was the right choice due to "split brain" issues and complexity, suggesting Redis or S3 might have sufficed for simple config needs.

Q: How did Pinterest implement sharding to handle their massive database growth?


Q: Why was Redis better than MySQL for handling social feeds?


Q: What specific lesson did Pinterest learn from their failed database experiments?

and more


Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
The "Boring" stack (MySQL/Redis) is timeless. However, manual sharding of MySQL is painful. Pinterest later moved to **HBase** and **RocksDB** for many workloads, and adopted **Pinot** for analytics.

**Is it scalable?**
**Yes.** Sharded MySQL + Caching is essentially infinite scale, provided you have the ops team to manage it.

**What would the architecture look like today?**
1.  **NewSQL:** Instead of manually sharding MySQL and building "NASA-style" protection services, modern teams use **Vitess** (which Pinterest actually adopted later!) or **TiDB** / **CockroachDB**. These provide the SQL interface but handle sharding/replication automatically.
2.  **Kubernetes:** "Puppetizing" boxes is replaced by **Kubernetes** and container orchestration.
3.  **Workflow Orchestration:** "Pinlater" (MySQL queue) is an anti-pattern for complex workflows efficiently. Today, we'd use **Temporal** or **Cadence** (which Uber/Pinterest use) for durable, code-based workflow orchestration rather than a simple database-as-a-queue.

## Principal Architect's Q&A

**Q: Pinterest used "Throwing Money at the Problem". Is that valid?**

**A:** **Yes.** Engineering time is 10x more expensive than AWS time.
1.  **Simplify First**: They stripped the stack to MySQL/Redis. 
2.  **Vertical Scale**: Before sharding, buy the biggest RDS instance money can buy. It buys you 6 months of no-sharding sleep.
3.  **Modern Stack**: Today, use **CockroachDB** or **TiDB**. You get the "MySQL" interface but it shards automatically under the hood. Don't write custom sharding logic in your app layer if you can avoid it.

