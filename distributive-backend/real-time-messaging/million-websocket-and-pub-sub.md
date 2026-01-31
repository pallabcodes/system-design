Resource: https://youtu.be/1tNfKI03qRU?list=TLGGVID9fMDBbxczMTAxMjAyNg

Based on the provided transcript, here is an accurate and comprehensive extraction of the presentation "Million WebSocket and pub/sub" by Sergey Kamardin from Mail.Ru Group, from start to end.

### **Part 1: Introduction and Architecture**

**Introduction and Core Concepts**
Sergey Kamardin, a programmer at Mail.Ru’s mail team, presents the story of how they built and launched a notification system for messaging between Mail.Ru services and end-users. The talk is divided into two parts:
1.  **Architectural:** How the system works logically.
2.  **Technical:** Specific optimizations in the Go language and problems solved.

He begins with definitions:
*   **State:** Any stored program information required for operation that changes over time (e.g., number of emails, read flags, session life).
*   **Event:** Information about a change in state.
*   **Cost of Reaction:** Reacting to events has a price, but not reacting also has a price (e.g., user dissatisfaction if an email notification is delayed). The goal is to find a middle ground.

**The Legacy Approach: HTTP Polling**
Before WebSockets, the system worked via HTTP Polling.
*   The browser asked the server every 2 minutes if there were changes.
*   **Load:** ~3 million requests per minute (50,000 requests per second).
*   **Inefficiency:** 60% of responses were status `304 Not Modified`, meaning the traffic was wasted as nothing had changed.
*   **Goal:** The server should send notifications only when changes actually occur.

**The Solution: Publisher/Subscriber Pattern**
They adopted the Publisher/Subscriber pattern using a "Bus" (Event Channel) between components.
*   **Old Architecture:** Browser $\rightarrow$ API $\rightarrow$ Storage.
*   **New Architecture:** Two new components were introduced: a **WebSocket Server** (API) and a **Bus** (Event Bus).
    1.  Browser establishes a WebSocket connection with the API.
    2.  Browser sends a subscription request (e.g., "I want updates for mailbox X").
    3.  API saves this subscription internally and forwards it to the Bus.
    4.  The Bus saves the subscription.
    5.  When **Storage** receives a new email, it sends an event to the Bus.
    6.  The Bus routes the event to the specific API node holding the connection.
    7.  The API node sends the event to the Browser.

**Scalability and Routing**
The system must scale horizontally (many Storages, many APIs, many Buses).
*   **Publishing:** When Storage emits an event, it doesn't need to send it to all Buses. It uses Round Robin to send it to just one Bus to balance the load.
*   **Routing Strategies:** Sergey discusses three methods for the Bus to find the correct API node:
    1.  **Flooding:** Send to everyone. (High traffic, CPU load).
    2.  **Gossiping:** Nodes pass packets to neighbors. (High latency).
    3.  **Filtering (Chosen Method):** The Bus knows exactly which connection needs the event.
*   **Implementation:** They use a routing tree in memory. Publishers send full parameters (e.g., A, B, C), and subscribers can subscribe to any subset of those parameters.

**WebSocket Protocol Details**
*   WebSockets use HTTP only for the initial upgrade handshake. After that, it is a binary protocol over TCP.
*   **Frames:** There are 5 types: Ping, Pong (keep-alive), Close (disconnect), Text, and Binary (user data).
*   **Browser Quirks:**
    *   **Chrome:** Does not wait for a server response when sending a Close frame; it disconnects immediately.
    *   **Firefox:** Periodically sends Ping frames (requires Pong responses).
    *   **Internet Explorer:** Periodically sends Pong frames independently. (Older versions had bugs closing connections).

**The Scale Challenge**
*   **Volume:** 3 million active connections.
*   **Unpredictability:** Connection lifespan varies from seconds to days.
*   **Self-DDoS:** If the system crashes or a network issue occurs, millions of clients try to reconnect simultaneously (Thundering Herd), potentially DDoSing the service.

---

### **Part 2: Technical Implementation (Go)**

**Why Go?**
They chose Go because it is compiled, statically typed, has a Garbage Collector, and features concurrency primitives (Channels and Goroutines).

**The "Naive" Implementation and Memory Usage**
Sergey walks through a standard implementation using the `net` package and `goroutines`.
1.  **Goroutines:** A standard approach launches two goroutines per connection (one Reader, one Writer).
    *   Goroutine stack starts at 4KB.
    *   2 goroutines * 4KB = **8KB** per connection.
2.  **Buffers:** To avoid excessive syscalls, IO is buffered.
    *   Read Buffer (4KB) + Write Buffer (4KB) = **8KB**.
3.  **Total for 3 Million Connections:**
    *   Just for stacks and buffers: ~48 GB.
4.  **HTTP Overhead:** Handling the initial HTTP Upgrade request uses the `net/http` library, which allocates Request/Response writers (4KB each) and header maps.
    *   This adds another ~24 GB.
5.  **Total:** ~72 GB of RAM just to hold idle connections. This is too expensive.

**Optimization 1: Netpoll / Epoll (Linux)**
*   **Problem:** In the naive model, goroutines block on `Read()` waiting for data, keeping stacks and buffers allocated.
*   **Mechanism:** Go runtime uses non-blocking IO and `epoll` internally, but exposes a blocking API.
*   **Solution:** They implemented their own integration with `epoll` (Linux event notification).
    *   They subscribe to the socket's file descriptor using `EPOLLIN` and `EPOLLONESHOT`.
    *   Instead of a permanent Reader goroutine, they only wake up to read when the kernel notifies that data is available.
    *   **Write Optimization:** They do not run a permanent Writer goroutine. If the outgoing packet queue is empty, no writer exists. It is spawned only when there is data to send.
*   **Result:** Removes the permanent 48GB overhead of idle goroutines/buffers.

**Optimization 2: Goroutine Pool**
*   **Problem:** If 3 million connections all become active simultaneously (e.g., during a reconnect storm), the `epoll` solution would still spawn 3 million goroutines to handle the reads, causing memory spikes (Self-DDoS).
*   **Solution:** Worker Pool.
    *   They use a fixed number of goroutines (e.g., 128) to handle IO.
    *   When data arrives, the task is scheduled in the pool. If the pool is full, the task waits.
    *   **Benefit:** This strictly limits the number of allocated buffers. The 129th request waits, ensuring memory usage stays flat.

**Optimization 3: Zero-Copy Upgrade**
*   **Problem:** The standard `net/http` library is too "heavy" for a pure WebSocket server. It parses all headers, creates maps, and copies strings during the Upgrade handshake, generating garbage.
*   **Solution:** They wrote a custom library (`gobwas/ws`).
    *   It does not use `net/http`. It works directly with `io.Reader`/`io.Writer`.
    *   It validates the WebSocket handshake (e.g., `Sec-WebSocket-Key`) without copying memory. It checks bytes on the fly.
*   **Result:** 0 allocations during the upgrade process. This reclaimed the remaining ~24GB of overhead.

**Optimization 4: DDoS Protection**
Using the Goroutine Pool allows them to drop connections intentionally. If the pool is overloaded or the queue is full during a handshake attempt, they simply stop accepting/upgrading the connection. The load balancer (Nginx) then handles the rejection or tries another node.

**Final Technical Summary**
*   **Memory Reduction:** Reduced memory per connection from ~60KB+ to ~10KB.
*   **Throughput:** Capable of handling connection bursts (up to 100k upgrades/sec) effectively.

---

### **Part 3: Results and Q&A**

**System Stats**
*   **Connections:** 3 million live connections.
*   **Events:** 30,000 notifications/sec generated by Storage.
*   **Delivery:** 9,000 notifications/sec delivered to users (filtering logic works).
*   **IO:** 75,000 read events/sec.

**Benefits**
*   **Business:** Highly interactive UI.
*   **Architecture:** Loose coupling between services.

**Q&A Highlights**
1.  **DDoS Defense:**
    *   Server side: Rate limiting, dropping connections via the pool.
    *   Client side: Clients implement backoff strategies (don't reconnect immediately or all at once).
2.  **Fallback:**
    *   If WebSockets fail (e.g., ad blockers), the system allows fallback to polling.
    *   On connection, the client syncs state via HTTP to get the current revision, then switches to WebSocket for updates.
3.  **Delivery Guarantees:**
    *   If a client drops and reconnects, how do they know they missed a message?
    *   **Solution:** They use revision numbers. The client compares its local revision with the incoming packet. If there is a gap (e.g., has 0, receives 2), it knows it missed data and requests a full state sync via HTTP.
4.  **Why Go?**
    *   Evaluated Node.js, Scala, Rust. Go chosen for low barrier to entry and ability to optimize deeply (like the optimizations discussed).
5.  **Multiple Tabs:**
    *   Currently, multiple tabs create multiple connections (only ~10% of users do this).
    *   Future plan: Use a "Master Tab" approach via LocalStorage to share one connection.
6.  **Library Availability:**
    *   The Zero-Copy WebSocket library is open source (`gobwas/ws`).
    *   The `epoll` library is also available (`mailru/easygo`).
7.  **Why not standard libraries (Gorilla)?**
    *   Sergey tried submitting PRs to Gorilla for these optimizations, but they were rejected because the maintainers felt the standard use case shouldn't be complicated by such low-level optimizations.

**Conclusion**
The lecture concludes with Sergey emphasizing that for massive concurrency, standard libraries often trade performance for usability, and custom, low-level optimizations (like managing syscalls and memory manually) are necessary to save resources.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?