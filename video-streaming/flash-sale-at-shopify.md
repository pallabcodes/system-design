Resource: https://youtu.be/MV5Kdwzwcag?list=TLGGPN7nm9MwsvwyNTAxMjAyNg

Based on the provided transcript, here is an accurate and comprehensive extraction of the presentation "Shopify’s Architecture to Handle the World’s Biggest Flash Sales" by Bart de Water, covering the content from start to end.

### Introduction and Context
Bart de Water, Lead of the Insights and Reporting team at Shopify Payments, introduces the platform's mission to offer a multi-channel platform for millions of merchants. The talk focuses on handling "Flash Sales," which are sales for a limited time with limited stock. While these used to resemble crowded mall openings, the current iteration is popularized by digital-first brands doing "product drops" (e.g., sneakers or lipstick) driven by social media hype. This creates a traffic pattern where today's flash sale becomes tomorrow's base load.

### Technology Stack
Shopify’s backend is primarily built on **Ruby on Rails**, utilizing **MySQL**, **Redis**, and **Memcached** as data stores.
*   **Performance Layers:** They use **Go** and **Lua** for performance-critical backend parts.
*   **Frontend:** They use **React** with **GraphQL** APIs and **React Native** for mobile apps (like the Point of Sale).
*   **Deployment:** The main Rails application is a monolith deployed approximately 40 times a day by hundreds of developers.

### Architecture Concepts
The talk focuses on two major sections: **Storefront** (mostly read traffic) and **Checkout** (mostly write traffic/external interactions).

**The Shopify Pod**
A "Pod" is a self-contained unit that holds data for one-to-many shops. It is a complete version of Shopify capable of running anywhere.
*   **Isolation:** Pods are stateful and completely separate; they are more than just relational data shards.
*   **Infrastructure:** While data stores are isolated, stateless workers are shared to balance load within a region. If a specific Pod has an issue (e.g., an overloaded MySQL instance), it does not affect shops on other Pods.
*   **Regions:** A Pod is active in a single region but exists in two, with replication set up to allow failing over an entire Pod to a non-active region in catastrophic scenarios.

**Routing and Branding**
Merchants can use a `myshopify.com` subdomain or a custom domain (e.g., `t-shirthero.com`).
*   **OpenResty:** Traffic first hits OpenResty (Nginx with Lua scripting). This layer handles blocking bots (which hammer systems harder than real buyers during flash sales) and routing.
*   **Sorting Hat:** A Lua module called "Sorting Hat" looks up the host in the routing table, identifies the corresponding Pod, and routes the request to the region where that Pod is active.

### Checkout and Payment Processing
Checkout involves collaboration between various components (Line Items, Discounts, Taxes, Shipping) within the Rails monolith. Processing credit cards introduces **PCI Compliance** challenges.

**Handling PCI Compliance**
To avoid bringing the entire monolith (and its rapid deployment cycle) into PCI scope, Shopify isolates sensitive card data.
1.  **Iframes:** Credit card fields (number, name, CVV, expiry) are iframes hosted on a separate domain.
2.  **CardSync:** When a user submits payment, data goes to an application called **CardSync**, which encrypts it and returns a token to the frontend.
3.  **Token Submission:** The checkout code submits this token (not raw data) to the main Shopify monolith.
4.  **CardServer:** A background job in the monolith sends the token and metadata to an app called **CardServer**. CardServer uses the token to retrieve/decrypt the data from CardSync and uses an adapter library to communicate with the specific payment processor.

### Scaling for Black Friday Cyber Monday (BFCM)
BFCM is Shopify's largest event (e.g., $6.3 billion in sales and peaks of 32 million requests per minute in the previous year). To support this, Shopify relies on **Tenant Isolation**. Code is written to care about "Shops," not "Pods," allowing horizontal scaling by adding more Pods.

**Rebalancing (The Shop Mover)**
To manage growth, Shopify rebalances Pods by moving shops with minimal downtime.
1.  **Copy Data:** They copy MySQL rows matching the Shop ID to the new Pod.
2.  **Bin Log Replication:** To sync new data coming in during the copy, they replicate the MySQL binary log (stream of events). They open-sourced a library for this called **Ghostferry**.
3.  **Cutover:** Once nearly synced, they lock the shop for writes, queue incoming data, copy Redis jobs, update the routing table (Sorting Hat), and remove the lock.
4.  **Result:** This takes less than 10–20 seconds of downtime. Old data on the original Pod is deleted asynchronously.

### Storefront Evolution
Shopify rewrote their Storefront rendering code into a separate Ruby application, detached from the original monolith.
*   **Compatibility:** They verified this using a "shadow configuration" to ensure new rendering matched the old logic (Liquid templates) before switching production traffic.
*   **Headless Commerce:** For merchants wanting custom frontends, Shopify is building a React-based framework called **Hydrogen**, optionally hosted on **Oxygen**.

### Load Testing in Production
Shopify uses a tool called **Genghis** for load testing.
*   **Methodology:** Instead of simple GET requests, Genghis uses Lua scripts to simulate end-to-end user behaviors (browsing, adding to cart, checking out), distinguishing between logged-in and anonymous flows.
*   **Benchmark Stores:** Tests run against specific benchmark stores present on every production Pod.
*   **Benchmark Gateway:** To stress-test the PCI environment without hitting real banks, they use a "Benchmark Gateway" (a Go app) that simulates processor latency, success, and failure distributions.

### Resiliency Patterns
Shopify maintains a "Resiliency Matrix" and runs "Game Days" to simulate outages.

**Circuit Breakers (Semian)**
They utilize circuit breakers to protect resources. If a service times out repeatedly, the breaker trips (opens), instantly raising exceptions instead of waiting for further timeouts.
*   **Degradation:** This allows for degraded experiences (e.g., showing a logged-out view if Redis is down) rather than a hard crash.
*   **Semian:** They developed a Ruby library called **Semian** for this. It includes "Half-Open" states to test if a service has recovered.
*   **Testing:** They use a proxy tool called **Toxiproxy** to inject latency and failures in unit tests to verify circuit breaker behavior.
*   **Scoping:** While usually keyed by host/port, payment circuit breakers are keyed by **Country** (so a Canadian outage doesn't block US payments). Shipping aggregators might be keyed by **Carrier**.

**Idempotency (Resumption)**
To prevent double charges during retries (ensuring "exactly-once" semantics), Shopify uses idempotency keys.
*   **Resumption Library:** An internal library (potentially to be open-sourced) where actions consist of multiple steps recorded in the database. If a retry occurs, the system looks up progress and runs recovery steps before attempting the remote call again.

### Q&A Session Extraction
Following the presentation, Bart de Water answered several questions:

1.  **Special Treatment for Large Merchants:** Extra-large merchants may get their own dedicated Pod. For others, the system ensures flash sales don't monopolize capacity, allowing smaller co-located merchants to function.
2.  **Pods as Pets or Cattle:** Pods are treated as "cattle." They can be rebuilt or moved (e.g., for Kubernetes upgrades) rather than being hand-maintained "pets".
3.  **Job Queues (Temporal):** They do not use Temporal. The job system evolved from `Delayed::Job` to `Resque` (Redis-based) to a heavily customized version.
4.  **Pod Size Limits:** Limits are determined via "Scale Tests" (breaking point tests) distinct from "Architecture Tests" (correctness tests).
5.  **Microservices:** The monolith is not breaking into microservices soon. They use a "Deconstructing the Monolith" approach, enforcing component boundaries (like APIs) within the monolith to avoid spaghetti code without the network latency of microservices.
6.  **Rebalancing Downtime:** Downtime is minimal (seconds) required only during the final cutover/routing update.
7.  **Rationale for Pods:** Sharding was adopted around 2010/2012 when Shopify outgrew a single database.
8.  **Analytics:** Data is aggregated from Pod read-replicas into a data warehouse (using Presto) for analysis.
9.  **Current Challenges:** The team is currently working on optimizing transaction speeds with financial partners to reduce wait times for buyers.
10. **Storefront vs. Checkout Decoupling:** Storefront is a separate app; Checkout is in the monolith due to complex write dependencies (Orders, Shipping, Inventory). They communicate via the client (Cart transitions to Checkout).
11. **Enforcing Boundaries (Packwerk):** They use an open-source static analysis tool called **Packwerk**. It detects if a component (e.g., Payments) accesses another (e.g., Orders) illegally without using the public API. It can break the build to enforce architecture rules.
12. **Future of Ruby:** Shopify invests heavily in Ruby. They employ core maintainers working on **YJIT** (Yet Another Just-In-Time compiler). In Ruby 3.1, YJIT is rewritten in **Rust** for better maintainability and performance. Shopify runs development versions of Ruby/Rails in production to test these improvements early.
13. **Go Architecture:** They do not use a "Packwerk for Go" because their Go applications are small, focused services rather than monoliths.