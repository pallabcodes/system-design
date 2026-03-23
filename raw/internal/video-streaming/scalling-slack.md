Resource: https://youtu.be/_M-oHxknfnI?list=TLGGa5scCzk1Zx0yNTAxMjAyNg

# Scaling Slack: The "God Mode" Architecture Guide

> **Level**: Principal Architect / Distinguished Engineer
> **Scope**: Hyper-Scale Websockets, Database Sharding, and Edge Caching.

> [!IMPORTANT]
> **The Principal Law**: **The "Thundering Herd" is a Client-Side Problem.**
> If your client needs 10MB of JSON to start, your backend is already dead. You don't need faster servers; you need "Lazy Loading" and "Edge Caching".
> **The Scale**: 10M+ Simultaneously Connected Users. 10+ Hours/Day connection time.

---

## 🏛️ The "Barn" (2016): The Monolithic Reality

Before the fancy microservices, Slack ran on a stack that would make a hacker news commenter sneer, but made them billions.
*   **The Stack**: LAMP (Linux, Apache, MySQL, PHP).
*   **The Design**: **Sharding by Team**.
    *   Team "Acme" -> DB Shard 10 -> Msg Server 10.
    *   Team "Beta" -> DB Shard 11 -> Msg Server 11.
*   **The Benefit**: Fault Isolation. If Shard 10 dies, only Acme is down. Beta is fine.
*   **The Flaw**: **"The Enterprise Whale"**.
    *   When IBM joins (100k users), they don't fit on Shard 10.
    *   The "Barn" burns down.

---

## ⚡ God Mode: The Edge Cache ("Flannel")

The biggest bottleneck was `rtm.start`.
*   **The Scenario**: You open Slack.
*   **The Request**: "Give me *everything*." (Channels, Users, Emojis, Settings).
*   **The Cost**: ~10MB payload. Multiplied by 100k users logging in at 9 AM.
*   **The Crash**: Network saturation. PHP timeouts.

### The Solution: Flannel (Edge Application Cache)
Slack built **Flannel**, a custom specialized Edge Cache deployed in PoPs globally.
1.  **Lazy Loading**: Client connects to Flannel. Flannel returns a *tiny* skeleton payload (Current Channel + Top 5 DMs).
2.  **The "Man-in-the-Middle"**:
    *   Flannel holds the **Websocket** connection to the client.
    *   Flannel proxys data from the Backend.
    *   **Magic Trick**: If the Backend sends a message "User A posted in Channel X", Flannel checks: "Does this client know User A?"
    *   **Surveillance/Injection**: If the client *doesn't* know User A, Flannel **injects** User A's profile data *before* the message packet.
    *   **Result**: The Client never crashes due to missing references. The Client never requests data. It is "pushed" proactively.

```mermaid
graph TB
    Client[Slack Client] -->|WS| Flannel[Flannel Edge Pop]
    
    subgraph "Core AWS Region"
        Flannel -->|Persistent WS| Gateway[Gateway Server]
        Gateway -->|Sub| ChanServ[Channel Server (Pub/Sub)]
        
        Gateway -->|Query| WebApp[PHP Monolith]
    end

    style Flannel fill:#f96,stroke:#333
```

---

## 🗄️ Database Sharding: Enter Vitess

Slack's "Shard by Team" model failed for Shared Channels (two teams sharing one channel).
You need a system that shards by **Entity** (Channel ID, User ID), not by Team.

### The Weapon: Vitess
Created by YouTube to scale MySQL to infinity.
*   **Concept**: It makes 1,000 MySQL instances look like **One Giant Database**.
*   **VTGate**: The proxy component. The PHP app sends a query: `SELECT * FROM msgs WHERE channel_id = 'C123'`.
*   **Routing**: VTGate hashes 'C123' -> Shard 45 -> Replica 2.
*   **Topology**: **Scatter-Gather**.
    *   Query: `SELECT * FROM mentions WHERE user_id = 'U999'`.
    *   If `mentions` is sharded by Team, but you query by User, Vitess must query *all shards* (Scatter) and aggregate results (Gather).
    *   **Principal Warning**: Scatter-Gather is dangerous. One slow shard slows the whole query. You must have strict timeouts and "Partial Results" handling.

---

## 🤝 The "Shared Channel" Complexity

How do you let Company A (Shard 1) and Company B (Shard 2) talk?
*   **Old Model**: Impossible. A channel belongs to a Shard.
*   **New Model**: **Service Decomposition**.
    *   **Channel Server**: A dedicated service just for Pub/Sub.
    *   **Presence Server**: A dedicated service just for "Is User Online?".
    *   **User Profile Service**: A dedicated service just for faces.

The Monolith was broken apart not because "Microservices are cool", but because **Data Locality rules changed**.

---

## 🔮 The Modern Perspective (2025 Update)

If we built Slack today, would we build Flannel?

### 1. Cloudflare Durable Objects (The "Serverless Flannel")
Flannel was hard to build. Today, **Cloudflare Durable Objects** gives you a dedicated reliable "Actor" at the edge.
*   **Design**: Every Slack Channel = 1 Durable Object.
*   **Function**: It holds the recent history and active user list in RAM at the Edge.
*   **Result**: Zero latency. No infrastructure to manage.

### 2. Local-First Architecture (The Death of `rtm.start`)
The "Download Everything" problem is solved by **Sync Engines** (Linear, Replicache, ElectricSQL).
*   **Concept**: The Client has a real SQLite database.
*   **Sync**: It only downloads the **Delta** (changes since last sync).
*   **Impact**: App opens instantly. `rtm.start` is 0 bytes.
*   **Tech**: **CRDTs** (Conflict-free Replicated Data Types) merge edits from offline users automatically.

### 3. Server-Sent Events (SSE) vs WebSockets
Slack accepted the cost of 10M WebSockets.
*   **Modern View**: For mobile devices (battery drain), **HTTP/3 (QUIC)** with **Server-Sent Events** is often preferred for downstream updates, using short-lived POSTs for upstream. It simplifies the Load Balancer tier significantly.

---

## 🏁 Conclusion

Slack's journey is the transition from "Web App" to "Distributed System".
*   **Phase 1**: LAMP (Fast, Simple).
*   **Phase 2**: Flannel (Fixing the Network).
*   **Phase 3**: Vitess (Fixing the Data).

The lesson? **Don't over-engineer early.** The "Barn" got them to 4 Million users. System Design is about solving the bottleneck you have *today*, not the one you might have in 10 years.