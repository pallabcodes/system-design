Resource: https://youtu.be/dcroxRr8uJc

Based on the transcript provided, here is an accurate and comprehensive extraction of the video "Scaling Websockets Horizontally | SocketIo | Redis Pub\Sub | HandsOn" from start to end.

### Introduction to Horizontal Scaling Challenges
The video begins by explaining that WebSockets enable real-time, bidirectional communication between a client and a server, creating a persistent connection that makes the server stateful. This stateful nature makes horizontal scaling—increasing the number of servers in the backend—complicated.

In a basic horizontal scaling architecture, a load balancer (in this case, Nginx) distributes traffic across multiple servers (e.g., three servers). However, a problem arises due to the persistent nature of WebSockets:
*   When a connection opens, the server remembers the specific socket ID of that client.
*   If a client sends a message, it goes through Nginx to the specific server holding that connection.
*   If a second client makes a request that Nginx routes to a *different* server, the two clients cannot communicate.
*   The servers are isolated; Server 1 holds the session details for Client A, but Server 2 and Server 3 do not know about those messages or session details. Consequently, messages sent to Server 1 cannot be retrieved by a client connected to Server 2.

### Solution 1: Session Stickiness (And Its Flaws)
One method to address this is **Session Stickiness**. This ensures a client is always routed to the same specific server rather than being distributed to others.
*   **Mechanism:** This is often implemented using an **IP Hash algorithm**, where the client's IP is hashed to a string that determines the server destination.
*   **The Problem:** While this maintains the connection, it defeats the purpose of load balancing. One server might become bloated with requests while others remain idle because traffic is not truly distributed. If too many clients hash to the same server, it may run out of CPU/memory and crash.

### Solution 2: Redis Pub/Sub (The Fan-Out Architecture)
To fix the bloating issue and utilize the entire server pool, the system needs an algorithm to distribute messages across all servers. This is achieved using a **Message Queue** or **Pub/Sub model**. The presenter uses a **Redis Adapter** for this tutorial.

**The Architecture Flow:**
1.  **Connection:** A client connects to Nginx, which redirects it to a server.
2.  **Publishing:** When that server receives a message from the client, it publishes the message to Redis, which acts as a broker.
3.  **Fan Out:** Redis broadcasts (fans out) the message to all other servers in the pool.
4.  **Delivery:** Because the message is broadcasted to every server, a client connected to *any* server can receive the bidirectional messages.

### Hands-On Implementation
The presenter moves to a code demonstration using a demo application consisting of:
*   **Socket.io Server:** A basic Node.js server initialized with CORS enabled.
*   **Client:** A simple HTML/JS file using the `socket.io-client` library to send and display messages.
*   **Nginx:** Configured as a load balancer distributing load between `socket-server-1` and `socket-server-2`.
*   **Docker:**
    *   A `Dockerfile` to containerize the application.
    *   A `docker-compose.yml` file that creates a Redis container, two replicas of the socket server (Server 1 and Server 2) for horizontal scaling, and the Nginx container dependent on the socket servers. The setup uses a watch command to reflect file changes in real-time.

### Testing the Implementation
**Scenario 1: Clients on the Same Server (Success)**
The presenter runs the containers (`docker compose up`).
*   Two browser clients connect. The logs show both user IDs (e.g., `26q` and `fhr`) connected to **socket-server-1**.
*   Because they are on the same server, sending "hi" from one client successfully appears on the other.

**Scenario 2: Clients on Different Servers (Failure)**
The presenter refreshes the browsers to force Nginx to redistribute the connections.
*   One client (`xlg`) connects to **socket-server-1**, and the other (`xofw`) connects to **socket-server-2**.
*   When a message is sent from the client on Server 1, it is **not received** by the client on Server 2.
*   **Reason:** The servers lack the session details for the clients connected to the *other* server, and there is no broker to bridge them.

**Scenario 3: Enabling Redis Adapter (Success)**
To fix this, the presenter modifies the server code:
*   He uncomments code to initialize a **Pub client** and a **Sub client** connected to Redis.
*   **Mechanism:** The Pub client publishes messages to subscribers. Once the subscriber receives the session details, the user can get messages from any server.
*   The servers restart automatically via Docker.
*   **Result:** One client (`nfz`) connects to Server 1, and another (`ezo`) connects to Server 2.
*   When the message "hello" is sent, **both** clients receive it, proving the application is successfully scaled horizontally using the broker.

### Monitoring and Conclusion
The presenter demonstrates how to monitor the process by going into the Redis container via the Docker Desktop terminal. Using the Redis client inside the container, he verifies that Redis is actively publishing and subscribing messages across the nodes.

The video concludes by stating this architecture helps at a large scale, and the presenter requests feedback and sharing.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?