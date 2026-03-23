Resource: https://www.youtube.com/watch?v=WEgCjwyXvwc

Based on the transcript provided, here is an accurate and comprehensive extraction of the presentation "How We Learned to Stop Worrying and Love Fan-In at Twitter" from start to end.

### Introduction: Scale and Goals
The presentation begins by outlining the scale of Twitter's architecture following the decomposition of their "monorail" (a massive Ruby on Rails app).
*   **The Fan-Out System:** This system delivers approximately **20 million tweets per second** to followers' home timelines. This results in nearly **2 trillion tweet deliveries per day** (after filtering rules).
*   **Infrastructure:** This is backed by a custom **Redis** caching cluster operating at **150 million operations per second**.
*   **The Goal:** The presentation describes the evolution away from prioritizing purely low-latency delivery toward showing users the "best possible content" as effortlessly as possible.

### Background: The Home Timeline Architecture
The "Home Timeline" is the primary consumption vehicle for tweets (also known as the news feed or stream), typically displaying tweets from followed accounts in reverse chronological order.

**The Legacy "Fan-Out" Workflow:**
1.  **Write Path:** When a user tweets, it enters the backend and is persisted into a database layer called **Manhattan**.
2.  **Async Fan-Out:** Upon persistence, an asynchronous path delivers the tweet to the home timelines of target users. These timelines are stored in **Redis caches** (in-memory, no disk persistence). All RPCs are handled by **Finagle** (an open-source distributed systems toolkit).
3.  **Read Path:** Users request new tweets, which are served from the cache. The system is optimized for speed:
    *   **Scale:** Thousands of tweets written per second $\times$ follower density = ~20 million deliveries/sec.
    *   **Latency:** The 99th percentile for delivery is **1.8 seconds**, with a median of **0.5 seconds**.
4.  **Structure:** The API talks to a **Timeline Service**, which reads from the **Timeline Cache**.
    *   *Benefits:* It is scalable (just add more cache/fan-out instances) and simple (data is pre-computed and located in one place).

### Limitations of the Fan-Out Model
Despite its speed, the push-based model had three major limitations:

1.  **Expense:** The system performs expensive write operations continuously, even if the target users are not logging in to read them. Furthermore, the read path remains complex because the API layer must still consult graph storage and user services to handle filtering, real-time visibility rules (blocks/mutes), and cache misses.
2.  **Flexibility:** Data lives in the cache for a long time, complicating codec versioning. Crucially, the **ordering** is determined at write time based on the author and timestamp. This prevents the system from prioritizing the recipient's preferences.
3.  **Relevance:** Content is determined exclusively by static network actions (follows). It does not account for user interactions (e.g., close friends vs. acquaintances). It is difficult to apply algorithmic improvements or machine learning at write time because the system does not know when—or if—the user will view the result.

### The Shift to "Fan-In" (Scatter-Gather)
To achieve the goal of showing the best content (ranked tweets, recommendations, and reverse-chronological updates), Twitter moved to a **"Fan-In"** model.
*   **Concept:** Upon a request, an aggregation service scatters requests to various content services and "fans in" (aggregates) the responses.
*   **New Content Sources:**
    *   **Search Index:** Containing every tweet ever tweeted (billions of tweets) for retrieving unseen content.
    *   **Recommendation Systems:** For recommended users and content outside the follow graph.
    *   **Moment and Trend Services:** For trending topics.
    *   **Machine Learning Systems:** For ranking content.

### Implementation Challenges and Strategy
Building this required reorienting the architecture to insert complex services into the read path while maintaining sub-second latency and public API compatibility.

**Step 1: Augmentation**
They did not discard the old system. They layered real-time logic on top of the existing Timeline Service. This allowed the extensive business logic for reverse-chronological timelines to remain intact while tiptoeing into core relevance products.

**Step 2: Service Decomposition**
They eventually split the Timeline Service into two:
*   **Timeline Service:** Continued handling core responsibilities, caching, and fan-out.
*   **Timeline Mixer:** A new aggregation service for real-time workflows.
*   **Shared Library:** Core idioms were pulled into a common library to avoid code duplication.

**Step 3: State and Filtering**
The **Timeline Mixer** introduced state into the request path, enabling features like **pacing** (preventing frequent similar recommendations) and **deduplication**. To manage load, they implemented aggressive request filtering, only executing the expensive aggregation workflow when it was predicted to have maximum impact; otherwise, it falls back to the standard reverse-chronological timeline.

### Operational Contracts and Boundaries
As more teams onboarded to the aggregation layer, ad-hoc relationships became expensive. The team imposed strict contracts:
1.  **Remote Business Logic:** External teams must own their business logic within their own services. This prevents the aggregation service from becoming an unmaintainable monolith.
2.  **Data Model Translation:** Partner teams are responsible for maintaining a translation layer to map their internal data models to the simple timeline data model.

### Resiliency and Latency Management
To handle distributed dependencies, the system defines **Service Tiers**:
*   **Critical vs. Non-Critical:** Non-critical services (like recommendations) have enforced minimum latency cutoffs. Because recommendations do not require the same immediacy as real-time tweets, the system can be flexible.
*   **Degradation:** If a non-critical dependency fails or is slow, the system sandboxes the request and drops it. It can adaptively bypass collections from services unlikely to succeed based on historical characteristics or remaining request time.
*   **Fallback:** In a total failure scenario, the system falls back to the reverse-chronological timeline.
*   **Back Pressure:** The system propagates "fail fast" signals. If a service faces deterministic failure (e.g., database hot shards), it signals callers to stop retries immediately to avoid cascading failures.

### The "Ranked Timeline" Workflow
The speaker details the specific funnel for the algorithmic (Ranked) timeline:
1.  **Retrieval:** The system collects unseen tweets from the **Search Index** (billions of candidates).
2.  **First Pass Ranking:** Candidates are scored based on search features.
3.  **Prediction:** The best candidates are sent to an **Engagement Prediction** service, which uses ML to score the likelihood of user engagement.
4.  **Assembly:** Top-scoring tweets are joined with the reverse-chronological timeline and served.
5.  **Scale:** The funnel reduces **hundreds of billions** of tweets (Search) to roughly **5%** selected for prediction, resulting in **hundreds of millions** served daily. Notably, the bottleneck in this system was network bandwidth, not compute.

### Lessons Learned
1.  **Avoid "Team as a Service":** Model teams after problems solved, not implementations. Don't force new workflows into old services just because a specific team owns them.
2.  **Clear Boundaries:** Establish responsibilities early to prevent logic bleeding.
3.  **Service Tiers:** Distinguish between data that *must* be served and data that can be degraded.
4.  **Iterative Filtering:** Reduce the cardinality of data before performing expensive operations.
5.  **Fail Fast:** Use back pressure to avoid cascading failures.

### Q&A Highlights
*   **Why keep Fan-Out?** While expensive, the fan-out system is remarkably stable and efficient for real-time delivery. Recommendations require accumulating information (less real-time), so both systems are valuable.
*   **Back Pressure Examples:** The system defines a maximum number of Redis commands per second for a key. If exceeded, it throws a back pressure signal rather than attempting to serve.
*   **Dynamic Latency:** The aggregation layer calculates remaining time in a request. If time is tight, it dynamically reduces the timeout for downstream services or bypasses them entirely.
*   **Partner Feedback:** There is currently no great automated system to alert a partner team that their content is being dropped due to poor performance; they must infer it from lack of callbacks or user engagement metrics.
*   **Politics:** While the aggregation team has the final say, decisions are driven by global metrics (user value) rather than internal politics.