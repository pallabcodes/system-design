Resource: https://www.youtube.com/watch?v=SoFjQyAB8to

Based on the provided transcript, here is a comprehensive and accurate extraction of everything discussed in the video "Under the hood of Slack’s real-time messaging at scale," including the promotional content, architectural concepts, and specific component workflows.

### **Introduction and Sponsor Segment**
The video begins by questioning how a company like Slack manages to distribute millions of messages reliably to users worldwide daily. It promises to explore backend concepts such as **consistent hashing**, **server proxies**, and **broadcasting**.

**Sponsor: ZEGOCLOUD**
Before diving into the architecture, the video features a sponsor, **ZEGOCLOUD**.
*   **Service:** A mobile communication service provider offering a developer-friendly SDK and APIs for building features like video calls, chats, video conferences, and live streaming.
*   **UI Kits:** They offer plug-and-play components (UI Kits) to build apps quickly, supporting one-on-one calls, group calls, live audio rooms, and in-app chats. Components can be added or removed based on needs (e.g., dynamic video layouts or face beautification).
*   **Offer & Setup:** The video promotes a link for 10,000 free minutes of usage. The setup process involves creating an account, creating a project, choosing a use case (e.g., video calls), naming the project, selecting UI kits, and choosing a platform (e.g., React Native).

### **Slack’s Backend Concepts**

**1. Definition of "Channels"**
From the backend perspective, Slack defines "Channels" broadly. A "channel" includes standard channels, subsets of channels, direct messages (DMs), and subsets of DMs. These channels must be mapped to specific **Channel Servers**.

**2. The Problem of Mapping and Reliability**
Slack manages millions of active users. If a specific server hosting a channel goes down, the mapping between the channel and the server is lost. To prevent data loss and ensure reliability, Slack utilizes **Consistent Hashing**.
*   **Consistent Hashing Context:** This technique is common in distributed systems like **Cassandra databases** and **AWS DynamoDB**. It is used to spread data across multiple database instances or data centers to mitigate the risk of storing data in a single location.
*   **Slack’s Custom Solution:** Slack built its own service called **Charms** (Consistent Hash Ring Manager), which directly operates this hashing algorithm.

**3. Hashing Algorithms: Naive vs. Consistent**
The video contrasts a naive hashing approach with consistent hashing:

*   **The Naive Approach (Modulus Hashing):**
    *   *Scenario:* A channel (e.g., Channel ID 1) needs to be mapped to one of three available servers.
    *   *Calculation:* The system uses the **Channel ID** and a **Modulus** of the number of servers (e.g., 3).
    *   *The Failure Mode:* If one server (e.g., the blue server) crashes, the number of servers drops from 3 to 2. Because the divisor in the modulus calculation changes, the resulting hash changes entirely. The channel no longer knows where its data lives because the mapping logic is broken for *all* items, not just the ones on the failed server.

*   **The Consistent Hashing Approach (The Ring):**
    *   *Formula:* This method depends on the **Channel Name/ID** and the **Server Count**, arranged in a ring structure.
    *   *Mechanism:* Channels are mapped clockwise on the ring. For example, Channel 1 is bound to Server 1, Channel 2 to Server 2, and Channel 3 to Server 3.
    *   *Resilience:* If Server 3 goes down, the hashing algorithm is not fundamentally broken. The channel previously bound to Server 3 simply moves clockwise to hit the next available server (Server 1). Crucially, the mapping for Server 2 remains unaffected. This makes the system significantly more reliable.

### **Architecture and Message Flow**

**1. Service Discovery**
In a distributed system where microservices are spun up and down frequently (due to scaling or health issues), a central repository is required to track which services are alive. Slack uses **Service Discovery** as a central database that is aware of every **Channel Server** and **Charm** running in the backend.

**2. The User Connection Flow**
When a user loads Slack:
*   **Initial Request:** The client requests the user state (name, surname, company).
*   **WebSocket Connection:** Simultaneously, the browser establishes a WebSocket connection with a **Gateway Server**.

**3. Gateway Servers and Envoy**
*   **Gateway Servers:** These are edge servers distributed globally. Users connect to the Gateway Server geographically closest to them (e.g., a user in Asia connects to an Asian server, not a US one) to minimize latency.
*   **Envoy:** Deployed alongside Gateway Servers (or a subset of them) is **Envoy**, an "Edge Proxy."
    *   *Comparison:* It is compared to Nginx (which handles static files, proxying, and TLS).
    *   *Capabilities:* Envoy is described as more sophisticated for cloud-native applications, offering deep configuration options and integration with CDNs. It sits in front of the Gateway Servers.

**4. Message Delivery Workflow**
1.  **Configuration Fetch:** The Gateway Server reads channel configurations from **Service Discovery** to identify where the user's channels are located. For example, Service Discovery might indicate the user needs Channel IDs 1, 2, and 3.
2.  **Subscription:** The Gateway Server subscribes to those specific Channel Servers.
3.  **Data Retrieval:** The Gateway Server fetches the message history/data for those channels and sends it back to the client via WebSocket.
4.  **Real-Time Event:**
    *   When another user sends a message via WebSocket, it lands on a specific **Channel Server** (e.g., Server 3).
    *   The Channel Server automatically pushes a notification to all Gateway Servers subscribed to it.
    *   The Gateway Server then pushes the message to the recipient user via the WebSocket connection.

This creates an **event-driven architecture** operating between the Channel Servers and the Gateway Servers. The video concludes by acknowledging that while the diagram may look "messy," it explains the speed and reliability of Slack's messaging.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?