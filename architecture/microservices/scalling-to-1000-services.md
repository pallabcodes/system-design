Resource: https://youtu.be/kb-m2fasdDY?list=TLGGZ4Dzu6GkhvoyNTAxMjAyNg

Based on the transcript provided, here is an accurate and comprehensive extraction of Matt Ranney’s presentation "What I Wish I Had Known Before Scaling Uber to 1000 Services," covering the talk from start to end.

### Introduction: The Pace of Hyper-Growth
Matt Ranney begins by illustrating the sheer speed of Uber's growth. He shows time-lapse videos of Beijing and Chengdu, demonstrating how Uber’s presence in a city can explode over a single year,.
*   **Engineering Growth:** When Ranney started 1.5 years prior, there were 200 engineers. At the time of the talk, there were approximately 2,000 (a 10x growth).
*   **The Premise:** He reflects on the advice he would give his "young and naive" self from a year and a half ago, acknowledging that while people often only learn the hard way, he hopes to share lessons learned,.

### Service Architecture and "Microservices"
Ranney presents a graph showing service growth, noting they don't have a reliable way to track the exact number, but it is roughly around 1,000 services.
*   **The Buzzword:** He admits they must use the word "microservices" because it is a technology conference, but he aims to explore the surprising trade-offs of breaking up monoliths.
*   **Immutable Services:** He draws a parallel to "immutable databases." With so many services, they accidentally stumbled into a pattern where they rarely touch a service once it is deployed. This reduces breakage, as systems are most reliable when engineers aren't changing them,.
*   **Why do it?:** The primary benefits are allowing new people to form teams quickly, move fast, and release independently. They adopted the "own your own uptime" model, where teams run the code they write.

### The Hidden Costs of Microservices
Ranney argues that while "using the best tool for the job" sounds obvious, it introduces shakiness when costs are examined closely.
*   **Distributed Systems Complexity:** Everything becomes a Remote Procedure Call (RPC). You must handle complex failure modes and troubleshooting becomes difficult (e.g., finding which service in a chain is broken).
*   **Opportunity Costs:** You might choose to build a new service rather than fixing something broken, simply to avoid wading into old code.
*   **Trading Complexity for Politics:** Writing new software is often an easy way to avoid awkward human conversations or compromises. Engineers can keep their biases (e.g., preferring Python over Node.js) by building a separate service rather than contributing to an existing one,.

### The Polyglot Challenge
Uber moved from 100% outsourced -> Node.js (Dispatch) -> Python (Core Services) -> Go and Java (Maps/Data).
*   **The Problem:** While microservices allow for many languages, this makes sharing code and moving people between teams difficult. It fragments the culture into tribes (e.g., "I'm a Node programmer"),.

### RPCs: Servers are Not Browsers
Ranney emphasizes that communication between services (RPCs) is fundamentally different from browser communication.
*   **HTTP Weaknesses:** At scale, HTTP semantics (status codes, headers, methods) become complicated and subtle.
*   **JSON Weaknesses:** Without types, JSON becomes a "crazy mess" where future breakages occur due to subtle interpretation differences (e.g., empty string vs. null).
*   **The Lesson:** Talking across a data center should be treated like a function call with types, not a web request. He wishes he knew earlier that "servers are not browsers".

### The Repo Debate: One vs. Many
Ranney discusses the trade-off between having one giant repository (Google style) vs. many small ones.
*   **Trade-offs:** "Many" is open-source friendly but makes cross-cutting changes hard. "One" makes changes easy but requires massive, specialized tooling (like Google's virtual file system),.
*   **Uber's Reality:** They have over 8,000 repositories. They are so far to the "many" side that moving to a single repo seems impossible.

### Operational Surprises
*   **Dependency Blocking:** Even with independent teams, you effectively get blocked if a dependent team isn't ready to release.
*   **Loss of Context:** After spending all that time decomposing the system, they realized they still needed to understand the system as one giant machine,.

### Performance and Tooling
*   **Profiling:** Different languages have different tools (e.g., `pprof` for Go). To understand performance across languages, Uber standardized on **Flame Graphs** for Go, Node, Python, and Java.
*   **Dashboards:** Teams naturally build their own unique dashboards. To fix this, Uber now automatically generates standard dashboards for every new service,.
*   **Performance Philosophy:** Ranney critiques the "premature optimization is the root of all evil" mindset. He argues that performance doesn't matter until it suddenly does.
    *   **The Fix:** Mandate a performance SLA for *every* service automatically (even if it's loose, like 20 seconds). This ensures there is always a number to measure and tighten later,.

### Fan-Out and Tracing
Fan-out (one request triggering many others) causes tail latencies (P99) to hit users more frequently.
*   **Tracing:** You need distributed tracing (like Zipkin or OpenTracing) to find these problems.
*   **Example 1 (Unintentional Fan-out):** A service was fetching a list of IDs and resolving them one-by-one instead of using a bulk endpoint,.
*   **Example 2 (ORM Magic):** Looping over an object where accessing a property triggered a hidden database query, resulting in 10,000 DB requests,.
*   **Context Propagation:** The hardest part of tracing is passing context (User ID, Auth, Headers) through intermediate services that don't even understand that context. This requires cross-language support.

### Logging
*   **The Problem:** Inconsistent logging across languages and "logging too much" causing cascading failures.
*   **Solutions:**
    *   **Structured Logging:** Mandate tools that force structure (Uber uses a custom tool called **Zap**, which is zero-allocation and fast),.
    *   **Back Pressure:** Drop logs if the system can't keep up.
    *   **Accounting:** Track who is logging what so you can "bill" the team that is spamming the indexing cluster,.

### Testing Strategies
*   **Load Testing:** It is impossible to build a test environment as big as production. Uber runs load tests **in production** during off-peak times.
    *   **Challenge:** This blows up metrics. You need context propagation to tag these requests as "test traffic" so they don't count towards business metrics,.
*   **Failure Testing:** Ranney advocates for Chaos Monkey-style testing.
    *   **Lesson:** Developers hate this because it breaks their "baby." It cannot be opt-in; it must happen automatically so teams are forced to withstand random failures.

### Migrations and Human Factors
*   **Constant Migration:** Everything is legacy immediately. People are always migrating storage or services.
*   **The "Immutable" Trap:** If you never touch a service, you eventually fear touching it, making cross-cutting upgrades (like security fixes) very expensive.
*   **Carrots vs. Sticks:** Mandates (sticks) to migrate are bad. You must build new systems that are so much better (carrots) that people want to move,,.

### Politics and Infrastructure
*   **Build vs. Buy:** Anything that looks like infrastructure is eventually a commodity (Amazon will sell it). Engineers get sad when you replace their custom platform with a commodity service.
*   **Defining Politics:** Ranney defines politics as making a decision that violates the hierarchy of values: **Company > Team > Self**.
    *   If you put yourself above the team, or the team above the company, that is politics,.
    *   Microservices tempt people to violate this by prioritizing shipping their small piece over the health of the wider system.

### Conclusion and Q&A
Ranney concludes that while he wasn't explicitly making these trade-offs at the time, he wishes he had made them intentionally.

**Q&A:**
*   **Coupling:** A questioner asks how to avoid coupling when using RPCs. Ranney answers that sometimes you can't. Duplication and coupling happen. The trade-off is accepting that coupling while maintaining the ability to release components independently,.