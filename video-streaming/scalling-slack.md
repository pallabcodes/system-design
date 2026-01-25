Resource: https://youtu.be/_M-oHxknfnI?list=TLGGa5scCzk1Zx0yNTAxMjAyNg

Based on the transcript provided, here is an accurate and comprehensive extraction of the presentation "Scaling Slack - The Good, the Unexpected, and the Road Ahead" from start to end.

### Introduction and Scope
The speaker introduces the talk as a review of the transitions Slack underwent over the two years prior to the presentation (roughly 2016–2018). He clarifies that this is not a standard "monolith to microservices" talk, but rather a focus on what changed in the system to meet new requirements and scaling challenges.

### The 2016 Architecture: "The Barn"
To frame the conversation, the speaker details Slack's architecture in 2016.
*   **Product Context:** Slack is a messaging hub organized around "workspaces." Users log into a specific domain (bubble), and all communication and profiles live within that workspace.
*   **2016 Usage Specs:** There were 4 million Daily Active Users (DAU) and 2.5 million peak connected users. Sessions were long (10+ hours/day), and the largest organizations had around 10,000 users.
*   **Engineering Culture:** The style was pragmatic and conservative, utilizing a simple architecture.
*   **The 5-Box Architecture:**
    1.  **Client Applications:** Interacted with the backend.
    2.  **PHP Monolith:** A "LAMP" stack web app hosted mostly in Amazon's US East region.
    3.  **MySQL Database Tier:** Backing the web app.
    4.  **Async Job Queue:** Handled tasks like link unfurling and search indexing.
    5.  **Real-Time Message Stack:** A custom Java tier handling pub/sub distribution. This included a **Message Proxy** (for edge SSL termination) and the **Message Server**.
*   **Client Connection Flow:** Upon opening, the client called `rtm.start` to the PHP backend. This downloaded the *entire* workspace model (every user, channel, preference, and avatar). The client then used a URL from that payload to open a WebSocket connection to the message proxy.
*   **Scaling Strategy (Sharding):** Workspaces were assigned to specific database and message server shards. Bootstrapping involved looking up the workspace in a "domains" database, which directed the request to the correct numbered shards. Once routed, all interactions for that workspace were confined to that one data shard and message server.
*   **Database Configuration:** Slack used "Master-Master" active-active replication for MySQL. This prioritized availability over consistency, allowing automatic failover if one side failed, though it caused some conflict issues.
*   **"Herd of Pets":** Servers were managed individually by number (e.g., "Shard 35"). Configurations were manually updated in PHP files mapping hostnames to shard numbers.

This model worked well in 2016 because the "rich client" model made the product feel fast (data was local), and the simple backend allowed the small engineering team to debug issues quickly by looking at only a few specific servers.

### The Challenges of 2018
By 2018, the landscape had changed significantly due to scale and product evolution.
*   **Scale:** Daily users doubled to 8 million (7 million connected simultaneously), and the largest organizations grew to over 125,000 users.
*   **Enterprise Grid:** Large companies could now have multiple workspaces (e.g., "Wayne Security" vs. "Wayne Global") under one umbrella. This meant users and channels no longer belonged to a single backend "bucket" or shard.
*   **Shared Channels:** Different organizations (e.g., a PR agency and their client) could share a channel. This fundamentally broke the architecture where a channel belonged to exactly one workspace.
*   **Thundering Herds:** As organizations grew, the `rtm.start` payloads became massive (hundreds of megabytes per user), making connection storms prohibitively expensive.
*   **Operational Toil:** The "herd of pets" approach became unmanageable as the server count grew into the hundreds.

### Solution 1: Flannel and the Edge Cache
To solve the payload size issue, Slack introduced an edge caching service called **Flannel**.
*   **The Problem:** The `rtm.start` payload size grew linearly with the number of users and channels. For large teams, this could prevent laptops or phones from connecting efficiently.
*   **The Solution:** Instead of downloading everything, clients now make a thin connection to the backend and connect their WebSocket to a nearby **Flannel** cache.
    *   Flannel is globally distributed and deployed in edge POPs.
    *   It acts as a proxy for the WebSocket connection to the message server.
    *   It maintains an in-memory model of the workspace data.
*   **Mechanism:** Flannel allows "lazy loading." The initial payload is slim, and clients use a callback query API to fetch missing data (e.g., a user profile) from Flannel with low latency.
*   **"Man-in-the-Middle":** Initially, Flannel would "sniff" WebSocket messages. If it saw a reference to a user or channel the client might not have, it injected that metadata into the stream immediately *before* the client asked for it, preventing crashes or lag.
*   **Result:** This maintained the "real-time feel" without the massive initial download, enabling support for large organizations.

### Solution 2: Vitess and Database Sharding
To solve database hotspots caused by co-locating huge teams on single shards, Slack introduced **Vitess**.
*   **The Problem:** Hotspots occurred when a single large team overwhelmed its assigned shard. One shard could be 5-10x busier than others because of specific user activity or features.
*   **The Solution:** Vitess is a database topology management system (originally from YouTube) that runs on top of MySQL.
    *   Applications connect to a routing tier called **VTGate** via the MySQL protocol.
    *   VTGate handles sharding logic and makes the cluster look like one giant database to the PHP app.
    *   It allows sharding by **Entity** (User ID, Channel ID) rather than Workspace.
*   **Benefits:** This spreads the load of large organizations across the entire fleet rather than pinning them to one server.
*   **Topology Changes:** Vitess manages topology, allowing Slack to move away from Master-Master replication to a standard Master-Replica model managed by **Orchestrator**.
*   **Status:** Migration has been slow due to the complexity of changing the data model and the need for safety, but it has proven effective where deployed.

### Solution 3: Service Decomposition (Real-Time Messaging)
To support Shared Channels, Slack refactored the real-time message server.
*   **The Problem:** The monolithic message server assumed one workspace per server, which prevented channels from being shared across workspaces.
*   **The Solution:** The monolith was decomposed into five distinct services:
    1.  **Gateway Server:** Replaces the message proxy; manages WebSocket connections.
    2.  **Channel Servers:** Core pub/sub system.
    3.  **Admin Service:** Manages cluster topology.
    4.  **Presence Server:** Distributes user presence (online/offline) status.
    5.  **Legacy Message Server:** Kept for niche features like scheduled broadcast messages that didn't fit the new model.
*   **New Model:** The system is now a generic pub/sub model where everything (channels, user profiles, workspace updates) is a "channel". Clients subscribe to specific objects of interest rather than receiving a firehose for a whole workspace.
*   **Result:** This enabled Shared Channels and simplified the logic, though it introduced new failure modes where a user depends on many more servers.

### Key Themes and Lessons
The speaker highlights several cross-cutting themes resulting from these changes:
1.  **Cattle, Not Pets:** Servers now self-register using **Consul**. There are no more hard-coded hostnames or manual replacements.
2.  **Service Ownership:** The organizational structure had to change to match the architecture (inverse Conway’s Law). Debugging the new complex system requires specialized knowledge rather than general knowledge of "5 boxes".
3.  **Scatter-Gather & Consistency:** With fine-grained sharding (Vitess), retrieving data (e.g., for the sidebar) requires querying many shards. Slack had to relax consistency requirements. If a shard is slow, the client accepts partial results and retries later, rather than letting the slowest shard delay the entire request.
4.  **Legacy Persists:** Almost all components from the 2016 architecture (the "barn") still exist in production alongside the new systems due to legacy clients and ongoing migrations.
5.  **Performance "Papercuts":** Beyond grand architecture, scaling required hundreds of small fixes, such as adding **jitter** to client operations to prevent the client acting like a "botnet" during connection storms.

### The Road Ahead
The current architecture is more complicated but necessary for the scale. Looking forward, the speaker notes areas for future improvement:
*   Decomposing the PHP monolith.
*   Adopting multiple storage backends.
*   Improving the asynchronous job queue.
*   Moving further toward eventual consistency to maintain the real-time feel while tolerating backend latency.