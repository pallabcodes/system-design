Resource: https://youtu.be/yqc3PPmHvrA

Based on the provided transcript, here is an accurate and comprehensive extraction of the presentation "Streaming a Million Likes/Second: Real-Time Interactions on Live Video" from start to end.

### **Introduction and Live Demo**
The speaker opens the session at QCon by initiating a live interactive demo. He asks the audience to visit a specific URL (`tiny.cc/qconlive`) or scan a QR code to log in with LinkedIn credentials. The demo displays a live stream of the talk itself (delayed by one minute) streamed by his wife from the audience. He highlights the comments area where users can interact and ask questions. He warns users not to share the stream as it is a temporary demo.

### **Context and Philosophy**
To set the context for scale, the speaker asks about the largest live stream in the world. He reveals it was the 2019 Cricket World Cup semi-final between India and New Zealand, which reached over 25 million concurrent viewers and 100 million total viewers. The second largest was the British Royal Wedding with 18 million concurrent viewers.

The speaker introduces himself as a member of the "Unreal Real-Time Team" at LinkedIn. Their team philosophy for solving distributed system problems is to "start small," solving the first problem and iteratively adding simple architectural layers to solve larger problems,.

### **The Problem: Real-Time Interactions**
Live video includes telecasts, sports, and broadcasts. The defining feature of *interactive* live video is the ability for users to engage (likes, comments) in real-time. The speaker uses the LinkedIn Talent Connect conference as an example,.

The core technical challenge focuses on a simple interaction: distributing a "like" from a **Sender (S)** to a **Receiver (A)**.
*   The Sender sends a like to the backend via a simple HTTP request.
*   The challenge is sending that like from the server back to the Receiver (A).
*   The system needs a persistent connection between the Real-Time Delivery System and the Receiver.

### **Layer 1: The Delivery Pipe (Server-Sent Events)**
To solve the persistent connection challenge, the team chose **HTTP Long Polling** using **Server-Sent Events (SSE)**.
*   **Mechanism:** The client makes a standard HTTP GET request with the header `Accept: text/event-stream`.
*   **Server Behavior:** The server responds with `200 OK` and `Content-Type: text/event-stream`. Instead of closing the connection, the server keeps it open and streams chunks of data (likes, comments) as they occur.
*   **Client Side:** On the web, the client uses the `EventSource` interface to handle these chunks independently. Android and iOS have lightweight libraries to handle this.

### **Layer 2: Connection Management (Akka Actors)**
The next challenge is managing thousands of concurrent persistent connections on a server. LinkedIn uses the **Akka Toolkit** (specifically Akka Actors).
*   **Actors:** These are objects with state and behavior. They communicate exclusively via messages. A lightweight thread is assigned to an actor only when it has a message to process, allowing a single machine to manage millions of actors,.
*   **Implementation:** LinkedIn uses the Play Framework. When a connection arrives, it is converted to an event source connection and assigned a Connection ID. An actor is instantiated to manage the lifecycle of this specific connection.
*   **Broadcasting:** A "Supervisor Actor" receives a like object from the backend and broadcasts it to its child actors. Each child actor uses `eventsource.send` to push the data down its specific persistent connection to the client,.

### **Layer 3: Routing (Subscriptions)**
The system must ensure clients only receive likes for the specific video they are watching (e.g., Client 3 watching "Red Video" vs. Client 5 watching "Green Video").
*   **Solution:** Clients send a subscription request (HTTP) to the server when they start watching.
*   **Storage:** The server stores these subscriptions in an **in-memory table**.
*   **Why In-Memory?** The subscriptions are strictly local to that machine, and the persistent connection is tied to the machine's lifecycle. If the machine dies, the connection is lost anyway, so the subscription data is no longer needed.
*   **Dispatching:** When a like arrives, the Supervisor Actor checks the in-memory table to identify which connection IDs are subscribed to that video and sends the event only to those actors.

### **Layer 4: Scaling Connections (The Dispatcher)**
To handle more connections than a single machine can support, the team adds more Frontend machines. This introduces the need for a **Real-Time Dispatcher**.
*   **Role:** The Dispatcher receives events from the backend and routes them to the correct Frontend machines.
*   **Frontend-to-Dispatcher Subscription:** Frontend nodes tell the Dispatcher which videos they have subscribers for. The Dispatcher maintains a table mapping Videos to Frontend Nodes,.
*   **Flow:** The backend publishes a like to the Dispatcher. The Dispatcher checks its table, finds the relevant Frontend nodes, and sends the like via HTTP. The Frontend nodes then check their internal tables and send to clients.

### **Layer 5: Scaling Throughput (Multiple Dispatchers)**
The Dispatcher eventually becomes a bottleneck for the number of events published per second. The solution is adding multiple Dispatcher nodes.
*   **Challenge:** Dispatchers are independent; any Frontend can connect to any Dispatcher, and the backend can publish to any Dispatcher. A local subscription table on the Dispatcher no longer works.
*   **Solution:** The subscription table (mapping Videos to Frontend Nodes) is moved to an external **Key-Value (KV) Store**.
*   **Reliability:** This also ensures data safety if a Dispatcher node crashes.
*   **Flow:** Frontend nodes register subscriptions in the KV Store. When a Dispatcher receives a like, it queries the KV Store to find the target Frontend nodes and dispatches the event.

### **Full Architecture Recap (The "Million Likes" Flow)**
1.  **Subscribe:** A Viewer subscribes to a Frontend Node. The Frontend Node updates its in-memory table and subscribes to the Dispatcher. The Dispatcher updates the KV Store.
2.  **Publish:** A Viewer likes a video. The request goes to the Likes Backend. The Backend publishes to a random Dispatcher. The Dispatcher queries the KV Store, finds the Frontend Nodes, and forwards the like. The Frontend Nodes query their in-memory tables and push the like to the clients,.

### **Layer 6: Multiple Data Centers**
When LinkedIn added a new data center (DC), the challenge was routing a like occurring in DC1 to a viewer in DC3.
*   **Strategy:** Keep subscriptions local, but fan-out across data centers during the publish phase.
*   **Flow:**
    1.  A like is published to the Dispatcher in DC1.
    2.  The Dispatcher checks for local subscriptions (in DC1).
    3.  Simultaneously, the Dispatcher broadcasts the like to **Peer Dispatchers** in all other data centers (DC2, DC3).
    4.  The Peer Dispatcher in DC3 checks its local KV store, finds subscribers, and delivers the message. The Peer Dispatcher in DC2 finds nothing and drops it.
*   **Rationale:** It is more efficient to broadcast the event to peer dispatchers than to maintain a global cross-DC subscription list,.

### **Performance and Metrics**
*   **Frontend Scale:** A single Frontend machine can handle **100,000 persistent connections**. To handle the Royal Wedding (18 million viewers), they would need roughly 180 machines.
*   **Dispatcher Scale:** A single Dispatcher node can handle **5,000 incoming events per second**. Because the Dispatcher only fans out to Frontend machines (not clients), 10 dispatchers can handle 50,000 incoming likes/sec, which multiplies to millions of deliveries at the frontend,.
*   **Latency:** The p90 end-to-end latency (from Backend publish to Client receipt) is **75 milliseconds**. This speed is achieved because there is only one KV lookup and one in-memory lookup.
*   **Measurement:** To measure this one-way latency across multiple systems, the team used **Samza** for near-line processing to correlate timestamps.

### **Additional Capabilities**
*   **Presence:** The system powers LinkedIn's online/offline indicators. Since the platform manages persistent connections, it knows exactly when a user connects or disconnects. They built logic to handle mobile network jitter (disconnect/reconnect noise) to provide stable presence indicators,.

### **Summary**
The speaker summarizes the key takeaways:
1.  Real-time delivery enables dynamic interactions (likes, comments, polls).
2.  **Server-Sent Events** (persistent connections) are supported by most browsers and frameworks.
3.  **Actors** are a powerful model for efficiently managing millions of connections.
4.  **Start Small:** Solve distributed challenges by adding simple layers iteratively.
5.  **Horizontal Scale:** When limits are hit, add machines and distribute the work.
6.  **Technology Agnostic:** This architecture works with Node.js, Python, Redis, MongoDB, Couchbase, etc.,.

### **Q&A Session**
*   **Fallbacks:** There is no need for fallbacks for clients that don't support SSE because SSE is just a standard HTTP request. Unlike WebSockets, it is rarely blocked by firewalls.
*   **Syncing Video and Likes:** There is a natural delay (speed of light/processing). While there might be a slight delta between the video and the like appearing, the distribution is real-time enough for the user experience,.
*   **Consistency:** The system prioritizes speed over guaranteed delivery. They do not have strict consistency guarantees (e.g., if a dispatcher fails), but they monitor reliability closely.
*   **Why not Kafka?** Using Kafka would provide guarantees, but every Frontend machine would have to consume every "Live Video" topic to find its subscribers. This prevents the Frontend layer from scaling horizontally because adding more machines doesn't reduce the consumption load (every machine must still consume everything). The current architecture allows Frontends to only care about their specific connected clients,.
*   **Slow Clients:** The Frontend server operates on a "fire and forget" basis. It puts data into the pipe and does not block waiting for acknowledgment. If a client is slow or drops events, it does not cause memory exhaustion or impact the server.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
The "Dispatcher" pattern with Akka Actors is a timeless distributed system pattern. However, the specific technologies might have shifted. LinkedIn still uses this core "start small and layer" philosophy, but Akka has changed licensing (now Pekko for open source).

**Is it scalable?**
**Yes.** The architecture creates excellent isolation:
*   **Frontends** handle connection limits (C10K/C100K).
*   **Dispatchers** handle routing logic and fan-out.
*   **KV Store** handles routing state.
This allows each layer to scale independently.

**What would the architecture look like today?**
1.  **Kafka everywhere:** While the talk explains "Why not Kafka?" (consumer consumption load), modern Kafka consumer groups or efficient filtering might be reconsidered, OR a hybrid approach where Kafka feeds the Dispatchers (instead of direct HTTP/RPC).
2.  **RSocket / gRPC Streaming:** Instead of HTTP Long Polling/SSE, modern implementations might use **gRPC Bidirectional Streaming** or **RSocket**, which provides backpressure and better binary performance than text-based SSE.
3.  **Sidecars / Service Mesh:** Connection management might be offloaded to a sidecar (Envoy) or a specialized gateway that handles the persistent connections and just forwards events from the backend via gRPC/HTTP2, simplifying the application logic.
4.  **Global Routing:** The "Peer Dispatcher" model is essentially a manual mesh. Today, technologies like **Redis Enterprise Active-Active** (CRDTs) or globally distributed databases (CockroachDB, Yugabyte) might simplify the cross-DC subscription state management.