Resource: https://youtu.be/mc27pPLDFAw

Based on the transcript of the presentation "AWS re:Invent 2024 - Real-time event patterns with WebSockets and AWS AppSync (FWM302)," here is an accurate and comprehensive extraction of the content from start to end.

### Introduction and Real-Time Context
Kim, a Solutions Architect at AWS, opens the session at 8:30 AM, welcoming attendees to re:Invent 2024. She begins with audience engagement, asking attendees to identify if they operate applications with real-time requirements or if they have struggled to implement real-time due to infrastructure complexity or operational overhead,. She notes that challenges often include managing infrastructure, building custom code for auth and message handling, and managing connections.

The agenda includes discussing real-time use cases, challenges with existing solutions, an introduction to **AWS AppSync Events**, and real-world architecture patterns presented by Bill Fine, Senior Manager of Product Management for AWS AppSync,.

### Use Cases and Challenges
Kim outlines specific scenarios where real-time enhances user experience:
*   **Event Broadcasting:** Example given of a Seattle Seahawks fan needing immediate updates on a touchdown, or e-commerce inventory availability (avoiding "out of stock" emails after purchase),,.
*   **Real-Time Collaboration:** Examples include multi-turn gameplay where players need strategy updates, or call centers avoiding duplicated effort on tickets,.

She details three main struggles customers face with traditional implementations:
1.  **Polling:** Clients repeatedly asking servers for updates leads to increased latency, unnecessary resource utilization (compute running even when no updates exist), and scalability challenges during high-traffic events,,.
2.  **WebSockets (DIY):** Requires managing connection IDs, tracking connected/disconnected clients, and handling message fan-out across multiple servers, which becomes complex at scale,.
3.  **Backend Code:** Implementing custom Pub/Sub, filtering, and enterprise features like logging requires "undifferentiated heavy lifting".

### Existing AWS Solutions
Kim reviews existing options on AWS:
*   **Amazon API Gateway WebSockets:** Fully managed APIs, but connection management and fan-out are "do-it-yourself".
*   **AWS IoT Core:** Uses MQTT with a managed broker. Best suited for IoT devices due to X.509 certificates and lightweight protocol.
*   **AWS AppSync GraphQL:** Provides real-time subscriptions via GraphQL mutations. Benefits include managed connection management and fan-out, but it requires GraphQL expertise (schema writing),.

### Introducing AWS AppSync Events
Kim references a request from the previous year's re:Invent for a standalone event API without GraphQL requirements. In late October, AWS launched **AWS AppSync Events**, a fully managed Pub/Sub service. Features include built-in auth, connection management, broadcast, and message transformation. It is serverless and pay-for-use.

**How it Works:**
*   **Publishers:** Clients or backend services (EventBridge, DynamoDB) publish via HTTP POST.
*   **Subscribers:** Connect via WebSockets.
*   **AppSync Events:** Sits in the middle handling namespaces, channels, and segments.

### Demo 1: Emoji Thrower
Kim initiates a live demo where the audience scans a QR code to access a React web application. As users click emojis on their phones, they appear in real-time on the presentation screen.
*   **Under the hood:** The client publishes a JSON payload via HTTP POST to a namespace (`/re:Invent`) and channel (`/emoji`). The screen subscribes to the same channel,.
*   **Code:** The implementation uses the AWS Amplify API client (approx. 20 lines of code), though any HTTP/WebSocket client can be used.

### Deep Dive: Namespaces and Handlers
Kim explains the core concepts of the API:
*   **Channel Namespaces:** Provide a scalable way to define behavior. The namespace is the first segment (e.g., `/A`), and channels (e.g., `/A/abc`) are ephemeral,.
*   **Event Handlers:** Written in JavaScript (AppSync JS runtime), these intercept operations.
    *   **OnPublish Handler:** Can enrich events (adding timestamps, session IDs), validate schemas, or filter events. Kim shows code mapping through a batch of events to add metadata,.
    *   **OnSubscribe Handler:** Can enforce granular authorization (e.g., checking if a user is part of a group required by the channel segment),.

### Authorization and Authentication
Security can be configured at two levels:
1.  **API Level:** Default authorization modes for connections and publish/subscribe operations.
2.  **Namespace Level:** Overrides available (e.g., a public namespace using API Keys vs. a private one using OpenID Connect),.
*   **Supported Modes:** Amazon Cognito, OpenID Connect, AWS Lambda, API Keys, and IAM.

### Key Benefits Summary
Kim summarizes four key benefits:
1.  **Start Fast:** Configure an API in minutes using simple HTTP/WebSocket protocols,.
2.  **Scale:** Supports 1 million messages per second by default, deployed in 30 global regions.
3.  **Fully Managed:** Reduces operational overhead by handling connection management and fan-out.
4.  **Serverless/Cost:** Pay-per-use model with a free tier.

### Demo 2: Creating an API
Kim demonstrates creating an API in the AWS Console, naming it "emoji demo live." She uses the **Pub/Sub Editor** to test immediately,.
*   **Testing:** She connects a WebSocket client and subscribes to a default channel. She then publishes a JSON payload via the publisher panel, verifying receipt,,.
*   **Custom Namespace:** She creates a `re:Invent` namespace and adds event handlers.
    *   *Enrichment:* Adds code to inject a timestamp and a message ("This is a great session"),.
    *   *Auth Logic:* Adds logic to restrict subscriptions to channels containing the segment "emoji." She encounters a live coding typo but corrects it to demonstrate logic flow,.
*   **Result:** When publishing to the "emoji" channel, the events arrive with the enriched metadata.

### Real-World Architecture Patterns
Bill Fine takes the stage to discuss architecture patterns, noting the service was designed to be simple but not simplistic—capable of mission-critical workloads like the Super Bowl or Black Friday,.

**1. Event Broadcast Pattern**
One or few publishers to many subscribers. Examples include stock portfolios, crypto trading, Amazon Live, and sports scores,.
*   **PGA Tour Example:** Bill notes the PGA Tour helped inspire AppSync Events by asking for a simpler Pub/Sub solution than GraphQL. Their architecture involves capturing golf shot data on-course -> DynamoDB -> DynamoDB Streams -> Lambda -> AppSync -> Fans/Betting Platforms,,.
*   **Betting/Odds:** Similar pattern using Kinesis or Managed Kafka -> Lambda -> AppSync to update odds every ~500ms,.
*   **EventBridge Integration:** An EventBridge Event Bus can be configured with an API Destination to target AppSync Events directly, reducing the architecture to just two services,.

**2. Collaborative Pattern**
Many publishers interacting with a finite set of subscribers (e.g., chat, doc editing, gaming).
*   **Connect 4 Demo:** Bill references a workshop and blog post for a turn-based Connect 4 game using Next.js, Amplify, and AppSync Events. Features include ephemeral leaderboards and group chat,.

### Advanced Patterns
Bill addresses that AppSync Events is stateless and unordered by default,.
*   **Persistence:** To allow clients to retrieve missed messages upon reconnection, publishers can persist events to a database (like RDS) in parallel with publishing to AppSync.
*   **Ordering:** Use event handlers to stamp events with a timestamp so clients can order them.

### Service Specs and Cost
*   **Quotas:** 1 million events/sec outbound, 10,000 inbound. Unlimited connections (throttled creation at 2,000/sec),.
*   **Latency:** P50 < 50ms, P99 < 200ms.
*   **Cost:** $1.00 per million event operations (inbound/outbound/connect). $0.08 per connection-minute. Includes a free tier for the first year (250k operations/minutes per month),.

### Roadmap (What's Next)
Bill outlines upcoming features:
*   **Private APIs:** For use within VPCs.
*   **WebSocket Publish:** Full-duplex WebSocket support for publishing (currently HTTP only).
*   **Lambda Ejection:** Ability to use Lambda for handlers (Python/Go support or network access) instead of just JS.
*   **Built-in Targets:** Ability for event handlers to talk directly to DynamoDB, Aurora, OpenSearch, EventBridge, and HTTP APIs,.
*   **Bedrock Integration:** A generative AI use case where a user prompt is sent via AppSync, processed by Bedrock (with RAG via a database), and the response is sent back over the same socket,,.
*   **Built-in Features:** Native support for event persistence, ordering, presence detection, and schema validation (e.g., CloudEvents),.

### Conclusion
Bill concludes by emphasizing that customer feedback (like the PGA Tour's) drives the roadmap. He encourages attendees to use the QR codes for documentation and to fill out the session survey, noting they read feedback carefully to plan future content and speakers,. The session ends without time for Q&A, though Bill offers to chat in the hall.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?