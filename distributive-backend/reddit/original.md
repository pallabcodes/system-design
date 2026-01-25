Based on the transcript provided, here is an accurate, comprehensive extraction of the presentation "The Evolution of Reddit.com's Architecture" from start to end.

### Introduction and Scale
The speaker begins by introducing Reddit as the "front page of the internet" and a community hub. He highlights the scale of the site to contextualize the architecture:
*   Reddit is the fourth largest site in the US.
*   It serves **320 million monthly users**.
*   Users generate **1 million posts** and cast **75 million votes** daily.

### High-Level Architecture
The architecture is described as a "work in progress" moving away from a legacy structure.
*   **The Monolith ("r2"):** A giant "blob" in the middle of the architecture known as **r2**. This is a monolithic Python application that has been the core of Reddit since 2008.
*   **Front-End Evolution:** Front-end engineers moved away from r2 to build modern applications using **Node.js**. These apps share code between client and server and act as API clients talking to the API Gateway or r2.
*   **Back-End Services:** The team is splitting r2 into backend services (e.g., API team, listing team). These are written in Python using a common library to avoid reinventing the wheel (monitoring/tracing included). They use **Thrift** for strong schemas.
*   **CDN (Fastly):** Fastly sits in front of everything. It handles decision logic at the edge, routing requests to specific stacks based on domain, path, cookies, or experiment buckets.

### Deep Dive: The "r2" Monolith
Even though r2 is being dismantled, it remains a complicated beast.
*   **Load Balancing:** **HAProxy** performs load balancing, splitting user requests into various application server pools. This isolates different request paths (e.g., if the comments page is slow, it doesn't affect the front page).
*   **Codebase:** The same monolithic code is deployed to every server, though different servers may run different parts of it.
*   **Async Processing:** Expensive operations (voting, submitting links) are deferred to an asynchronous job queue via **RabbitMQ**.
*   **Data Storage:**
    *   **Postgres & Memcache:** Used for the core data model called "Thing" (accounts, links, subreddits, comments).
    *   **Cassandra:** Heavily used for new features for about seven years due to its fault tolerance.

### Core Functionality: Listings
A "listing" is the foundation of Reddit (ordered lists of links).
*   **Caching Strategy:** Reddit does not run a `SELECT` query against the database for every page load. Instead, the query is run once, and the resulting list of IDs is cached in **Memcache**. The system then looks up the link details by primary key.
*   **Invalidation/Mutation:** Listings change frequently due to voting. Because re-running the query is expensive, Reddit uses a "read-mutate-write" operation.
    *   When a vote occurs, the system fetches the cached listing.
    *   It modifies the ordering and score of the specific link within that list.
    *   It writes the listing back.
    *   This data is essentially a denormalized index, now persisted in **Cassandra**.

**Scaling Challenges with Listings (2012):**
1.  **The Lock Contention:** In mid-2012, vote queues backed up. Adding more processors made it worse due to lock contention on the popular listings.
    *   **Fix:** They partitioned the vote queues by **Subreddit ID (modulo 10)**. This reduced contention as processors weren't vying for the same subreddit lock.
2.  **The Domain Listing Issue:** Late 2012 saw P99 latencies spike again. While subreddits were partitioned, votes for links from the same domain (e.g., multiple subreddits linking to the same news site) caused contention on the "Domain Listing."
    *   **Fix:** They split the monolithic vote job into multiple smaller messages. One vote now spawns separate messages for subreddit updates, domain updates, etc., allowing them to route to the correct partitions.

**Lessons:** Granular timers and P99 monitoring are essential to finding these specific contention points.

### Core Data Model: "Thing"
The "Thing" model is Reddit's oldest data model, stored in Postgres.
*   **Structure:** It is designed to be vaguely schema-less and key-value based to avoid expensive joins and schema migrations.
    *   **Thing Table:** One row per object with fixed columns (metadata needed for sorting/filtering).
    *   **Data Table:** Multiple rows per object (Key-Value pairs) holding the properties.
*   **Infrastructure:** Uses a single database cluster with a primary for writes and read-only replicas. r2 prefers reading from replicas to scale.
*   **Memcache Integration:** The entire "Thing" object is serialized into Memcache. r2 reads cache first; on a miss, it hits Postgres. Writes go directly to Memcache to avoid stale data.

**Postgres Scaling Incidents:**
1.  **Replication Crash (2011):** A replication crash led to a database getting out of date. After rebuilding, cached listings pointed to IDs that didn't exist in the Postgres replica yet, causing page crashes. This required custom tooling to clean bad data from listings.
2.  **The "Permissions" Incident:** During maintenance, a primary was bumped offline. The r2 connection pool logic naively selected the "first available" database as primary. Since the true primary was down, it selected a **secondary**.
    *   Because write permissions were enabled on the secondary, the app wrote data there.
    *   When the secondary was taken out to be rebuilt/resynced, that data was lost.
    *   **Lesson:** Use strict permissions and service discovery to manage database roles.

### Comments and Tree Structures
Comments are threaded trees, making them expensive to render.
*   **Denormalization:** Parent relationships are stored in a denormalized listing to quickly determine which subset of comments to show.
*   **Batching:** Tree mutations are batched for efficiency.
*   **The "Fast Lane" Incident (Early 2016):**
    *   During a major news event, a mega-thread slowed down the site. Engineers manually moved it to a "Fast Lane" queue.
    *   **The Failure:** The Fast Lane queue filled up immediately, consuming all memory on the RabbitMQ broker. This prevented *any* new messages (site-wide) from being added. They had to restart the broker, losing all messages.
    *   **Root Cause:** "Missing Parent" issues. Comments in the normal queue hadn't been processed yet, so new replies in the Fast Lane saw a broken tree and requested re-computation, creating a loop.
    *   **Fix:** Implementation of **Queue Quotas** to prevent one queue from hogging all resources.

### Autoscaling and Infrastructure
Reddit experiences seasonal traffic (half volume at night vs. day). They use AWS Auto Scaling Groups driven by load balancer utilization metrics.
*   **Health Checks:** Originally relied on a daemon on every host registering with a **Zookeeper** cluster.

**The VPC Migration Incident (Mid-2016):**
*   **Context:** Migrating the Zookeeper cluster (used for autoscaling) to a VPC.
*   **The Plan:** Launch new ZK cluster, stop autoscaler services, repoint agents, restart autoscaler.
*   **The Error:** A Puppet run triggered automatically on the autoscaler server. It restarted the autoscaler daemons *before* configuration changes were complete. The daemons pointed to the *old* ZK cluster, saw the migrated servers as "unhealthy" (because they were in the new environment), and **terminated 1/3 of the fleet**.
*   **The Fallout:**
    *   The autoscaler also managed cache servers (stateful). When these were terminated, the new ones came up empty.
    *   Traffic hammered the Postgres replicas, which couldn't handle the load.
*   **Lessons:**
    *   Destructive actions (like termination) need sanity checks (e.g., "Am I killing 30% of the fleet? Stop.").
    *   Stateful services (cache) and stateless services (app servers) should be treated differently.
    *   The next-gen autoscaler uses service discovery for health checks rather than simple host agents.

### Summary
The speaker concludes by emphasizing that observability is key, humans make mistakes, and systems require multiple layers of safeguards. He notes that simplicity is crucial and announces that the team is hiring and holding an AMA.