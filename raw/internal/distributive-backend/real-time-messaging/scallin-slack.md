Resource: https://youtu.be/o4f5G9q_9O4?list=TLGGEW30Xuk8bLEzMTAxMjAyNg

Based on the transcript of the presentation "Scaling Slack" by Keith Adams, here is a comprehensive extraction of the content from start to end, detailing the architectural evolution, theoretical underpinnings, and technical decision-making at Slack.

### **Introduction and Core Premise**
Keith Adams, an engineer at Slack for two and a half years, presents work done by hundreds of engineers at the company. The presentation begins with a "twist": the argument that Slack technically cannot work, followed by the resolution of how it functions despite theoretical impossibility.

**Slack vs. IRC**
Slack is a persistent messaging application organized around users sending messages in channels (a combination of subject line and audience). While often compared to IRC, Slack is fundamentally different because IRC is ephemeral (if you aren't online, you miss the message), whereas Slack is persistent by default, allowing for search, archiving, and catching up on history.

**The Theoretical Impossibility (Atomic Broadcast)**
To build a minimal persistent chat product, the system must satisfy the requirements of "Atomic Broadcast" (or Consensus):
1.  **Validity:** If a message is sent, all members receive it.
2.  **Integrity:** The system does not hallucinate messages; they originate from actual sends.
3.  **Total Order:** Everyone agrees on the order of messages (A then B, not B then A).

The problem is that Atomic Broadcast is equivalent to the **Consensus** problem in distributed systems. In a system where components fail and networks are unreliable, solving Consensus is theoretically impossible.

**The Resolution: The End-to-End Argument**
In practice, systems like Blockchains, Paxos, Raft, and Zookeeper work by relaxing specific constraints. For example, blockchains relax the notion of receipt to be probabilistic. Other algorithms relax the time constraint, meaning convergence isn't guaranteed within a specific timeframe if an adversary delays messages.

This aligns with the **End-to-End Argument in System Design** (Saltzer, Reed, and Clark): it is difficult to provide strong semantic guarantees at the network or storage layer. Instead, these semantics should be pushed to the edges (the client and server application logic). Slack solves its problems by choosing which constraints to relax based on user needs and the technological environment.

---

### **Case Study 1: The Evolution of Sending Messages**

To discuss message sending, Adams simplifies Slack’s architecture into two components:
1.  **Web App:** A monolithic "grown-up LAMP stack" application written in Hack (Facebook’s gradual typing system for PHP). It handles auth, storage logic, and business rules.
2.  **Channel Server (CS):** A real-time message bus written in Java. It handles server push (WebSockets), typing indicators, presence, and is the arbiter of message ordering.

**The Old Send Flow (Optimistic/Low Latency)**
*   **The Process:** A client sends a message to the Channel Server. The Channel Server cascades (fans out) the message to other connected clients and immediately acknowledges the send to the sender. Only *after* this user-facing interaction is complete does the Channel Server asynchronously call the Web App to persist the message, unfurl URLs, and index it for search.
*   **The Benefit:** Extremely low latency for text interaction, which is foundational to Slack's user experience.
*   **The Failure Mode:** If the Channel Server crashes after acking but before persisting, or if the Web App is down, the message exists in limbo.
*   **The Complexity:** The Channel Server must maintain a persistent buffer of unsent messages to retry later, making it a stateful, complex service that is hard to maintain or deploy.
*   **Degraded Mode:** A side effect was that if the Web App (monolith) was down, users could still chat via the Channel Server, providing a "degraded mode" during outages.

**The New Send Flow (Reliable/Stateless)**
Over time, the Web App became more reliable, and Slack improved its asynchronous job queue (migrating to a Kafka-based system). This allowed for a new architecture:
*   **The Process:** The client sends an HTTP POST to the Web App. The Web App enqueues a job to handle persistence/parsing, and then *it* invokes the Channel Server to push the message to clients.
*   **The Trade-off:** This adds a network hop and relies on the Web App being up.
*   **The Benefits:** The Channel Server becomes stateless and crash-safe. The system naturally rolls forward (message sends) or backward (user gets an error) based on failure. It also allows sending messages (e.g., from mobile notifications) without establishing a heavy WebSocket session.

---

### **Case Study 2: Session Establishment (`rtm.start`)**

Slack measures load in simultaneous sessions (peaking over 5 million) rather than just requests per second.

**The Old Session Start**
*   **The Process:** A client calls `rtm.start`. The Web App harvests all team data (users, channels, unread states) and returns a massive JSON payload and a WebSocket URL. The client connects to that URL.
*   **The Rationale:** This provides a "keyframe" or snapshot of the team state, allowing the client to only listen for incremental updates afterward. This worked perfectly for teams of 100 people.
*   **The Scaling Problem:** For teams with 10,000+ or 100,000+ users, the payload became massive (tens of megabytes) because channel membership data grows quadratically (users × channels). Decoding this payload took tens of seconds on client devices.
*   **The "Thundering Herd":** If a network partition disconnected thousands of users, their simultaneous reconnection attempts (and the resulting massive database queries) could knock over the backend, specifically in the US East data center.

**The Solution: Flannel (Edge Caching)**
Slack introduced **Flannel**, a stateful, geo-distributed edge cache (microservice).
*   **How it Works:** Flannel sits at the edge and terminates the WebSocket connection. It maintains a pre-hydrated, in-memory model of the team's state by watching the WebSocket traffic passing through it.
*   **Efficiency:** Instead of downloading the full state, the client connects to Flannel. Flannel performs "lazy loading," sending a thin initial payload and allowing the client to query for missing data via an API.
*   **Mechanism:** Flannel acts as a filter. If it sees a message referencing a user the client doesn't know, it injects that user's metadata into the stream immediately before the message arrives.
*   **Result:** It protects the backend database from reconnect storms and speeds up connection times for global users.

---

### **Philosophy and Conclusion**
Adams concludes that while Flannel is "better," one should not simply clone it without the requisite scale, as it introduces complexity. He challenges the notion that software architects should always act as "priests of simplicity". While most of the stack should be simple and orthogonal, the "end-to-end" parts—the core value differentiators of the product—require complex intelligence to deliver user value.

---

### **Q&A Session**

*   **Message Bus Technology:** The Channel Server bus is fully custom Java code over TCP/IP because it is core to Slack's value proposition. The asynchronous job queue uses Kafka for storage and Redis for working memory.
*   **Hack Lang:** Slack uses Hack (the backend language) partially because the founders knew PHP. However, Adams defends Hack as a great platform offering the iteration speed of a dynamic language with the safety of a rich, gradual type system, similar to TypeScript.
*   **HTTP/2 vs. WebSockets:** HTTP/2 was not mature enough when Slack started. While one could try to merge the app logic and connection handling into one box (like Discord does with Elixir), Slack’s separation of the edge (connections) and state (logic) remains useful.
*   **Message Duplication:** Most duplicates come from client retries. Slack accepts duplicates if a client sends the exact same message twice, prioritizing human intent over strict idempotency.
*   **Testing Failures:** While formal modeling (like TLA+) is useful, real production bugs still occur. The best way to migrate critical systems (like storage) is to "double write" to both the old and new systems and compare results. When you start finding bugs in the *old* system during this process, it is time to switch.
*   **Sharding:** Session connections are routed via a tree structure from US East to edge gateways. Storage sharding is transitioning to Vitess (YouTube’s MySQL sharding system) because sharding by "team" no longer works for massive enterprise customers.
*   **Future Fears:** Adams is most scared of a competitor simply executing better—building a Slack that is faster, more reliable, and uses fewer resources.