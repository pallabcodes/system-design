Resrouce: https://youtu.be/gfh-VCTwMw8

Based on the transcript provided, here is an accurate, comprehensive extraction of Jimmy Bogard’s presentation "Avoiding Microservice Megadisasters," covering the narrative from start to end.

### Introduction: The Story of "Bell Computers"
Jimmy Bogard introduces the session as "Story Time," detailing his year-and-a-half engagement with a company he pseudonymously calls "Bell Computers." He outlines the history of their IT infrastructure:
*   **Mid-90s (The Mainframe Era):** The company ran on an HP Tandem Mainframe. This single system held everything—sales, catalogs, CRM, supply chain. It was a classic "big ball of mud," but it worked for mail-order and phone sales.
*   **The Dot-Com Era (2000s):** They built their first e-commerce site using ASP.NET 1.0 webforms. Initially, the design was decent, featuring distinct subdomains (catalog.bell.com, orders.bell.com) with individual databases. However, fulfillment still required communicating with the backend mainframe.
*   **The Distributed Ball of Mud:** Over time, the architecture degraded. Applications called each other via API calls, SOAP calls, and embedded DLLs. With the advent of SQL 2005, they utilized "linked servers" to join tables across different physical databases. The result was a "distributed ball of mud" where everything was tightly coupled to the legacy mainframe, which was embarrassingly maintained by consultants from a competitor.

### The Rewrite Decision
After 15 years, the existing application was generating billions in revenue but had hit a wall.
*   **The Catalyst:** A specific business requirement could not be met: the ability to place an order in one country, bill it from a second, and ship it to a third.
*   **The Strategy:** They decided to rewrite the system using a Service-Oriented Architecture (SOA) or Microservices, inspired by the "Netflix" architecture.
*   **Core Principles:**
    1.  **No Data Duplication:** A strict "single source of truth" policy.
    2.  **Isolation and Autonomy:** Services should be independent.
    3.  **Web APIs for Everything:** All communication must occur via HTTP.
    4.  **"Bell on Bell":** Move off the competitor’s mainframe onto their own hardware.

### The "Megadisaster" Launch
The team spent 18 months with hundreds of developers building this new system.
*   **The Go-Live:** When they finally flipped the switch, **nothing happened**. The website did not load.
*   **The Troubleshooting:** They assumed hardware constraints, so they upgraded to the most expensive servers available and connected them via gigabit fiber. Still nothing.
*   **The "Infinity" Fix:** Suspecting timeouts, they increased all timeout settings to infinity.
*   **The Result:** The page finally loaded after **9 minutes and 30 seconds**. This was just a simple list of products.

### The Root Cause Analysis (Regret-rospective)
Bogard’s team was brought in to diagnose the failure. They discovered several critical architectural flaws:
*   **Network Saturation:** A single external request triggered a cascading graph of thousands of internal API calls.
*   **Distributed Deadlocks:** Service A would call Service B, which called Service C, which circled back to call Service A.
*   **Resiliency Failures:** There were no circuit breakers. If one API call failed, the whole request failed.
*   **The SLA Math:** They aimed for 99.9% uptime. However, with 200 interdependent calls per request, probability theory dictates a **0% chance** of the site ever being up.
*   **The SLA Loophole:** Developers claimed they met their 150ms latency SLA, but they only measured their own code execution time, excluding the time spent waiting on external service calls.
*   **Fallacies of Distributed Computing:** The team believed the network was reliable, latency was zero, and bandwidth was infinite. This happened because developers mocked external services on their local machines, never testing real network hops until production.

### Incorrect Service Boundaries
The team had fundamentally misunderstood how to draw service boundaries.
*   **The "Microsoft Blog" Mistake:** They followed a diagram suggesting that to build microservices, one should break a tiered architecture (Web, Business, Data) into separate microservices for each layer.
*   **Result:** They had "Usage Analytics" services and other technical groupings that didn't map to business units. They essentially created services just so managers could have teams to manage to further their careers.
*   **Vertical Slicing:** Bogard explains that correct boundaries should be vertical slices (e.g., Catalog, Cart, Configuration) that own their logic from the UI down to the database.

### Redefining Services
Bogard clarifies the definition of a service using three sources:
1.  **SOA Definition:** Emphasizes autonomy, ownership, and contract assurances.
2.  **Microservices (Sam Newman):** Small, focused, doing one thing well, and autonomous.
3.  **Domain-Driven Design (DDD):** Focuses on **Bounded Contexts**. A "Customer" means something different to Sales than it does to Fulfillment. A service should define a boundary where a model is logically unified.

### The Solution: Fixing the Search Service
Bogard details how they fixed one specific service—Search—to prove the architecture could be salvaged.
*   **The Problem:** The Search service didn't own data. A search for "Windows 10 Laptop" returned T-shirts because it called the Catalog service, which returned items alphabetically by SKU. The Search service had to call ~12 other services to render a page.
*   **The Concept:** Search needs to own the **shape** of the data and the **SLA** (relevance and speed), even if it doesn't own the "source of truth."
*   **Dependency Inversion:** Instead of Search calling other services (pull), other services needed to push data to Search. This removes temporal coupling—Search only talks to its local database.

**Implementation Details by Service:**
1.  **Catalog Service:** Had roughly 1,000 standard configurations. Bogard’s team set up a process to ping the existing SOAP service once a day and store the results in a local document database.
2.  **Pricing Service:** Was overly complex and owned by no specific business unit. They discovered pricing was already included in the Catalog response. They severed the direct connection to Pricing entirely, improving the Pricing service's latency simply by stopping the traffic to it.
3.  **Localization:** Huge dataset (translations), rarely changed. They found existing apps used a daily flat-file dump on a shared drive. The Search service simply ingested this file daily.
4.  **Content Service:** Changed frequently and needed near real-time updates. The team "bribed the DBA with whiskey" to add **database triggers** that generated messages whenever the content table changed. Search consumed these messages to update its index.

**The Outcome:**
By aggregating this data into a local search database via offline processes, the Search page latency dropped from 9.5 minutes to a second or two.

### The Organizational Aftermath
While the technical fix worked for Search, the wider organization struggled due to cultural issues.
*   **Broken Incentives:** Managers were promoted based on headcount. This incentivized them to grow teams and bloat services unnecessarily. Teams complained that "work is great, but we just keep adding people".
*   **Conway's Law:** Systems mirror the organization's communication structure. Bogard adds a corollary: **"A broken dysfunctional organization driven by meeting unhealthy goals and metrics will produce broken and dysfunctional systems"**.
*   **Example of Dysfunction:** Years prior, the Cart Checkout team was bonused on "completion rate." To maximize this, they turned off all validations (credit card checks, address checks) because error messages made users leave. They relied on help desk calls to fix the data later.
*   **The Inverse Conway Maneuver:** To fix the architecture, you must first redesign the organization to align with the desired system structure. If the org is unhealthy, the system will be too.

### Q&A
*   **On Multiple Hops:** Bogard has a "Golden Rule": You can make one hop to another service, but that service cannot call anyone else. If you need multiple hops, you have drawn boundaries wrong or need to invert dependencies.
*   **On Data Duplication:** When asked how to convince people data duplication is okay, Bogard points out the business already runs on it (e.g., printed catalogs). Stale data is acceptable in many contexts (e.g., a price change doesn't need to propagate instantly; the checkout will catch it).