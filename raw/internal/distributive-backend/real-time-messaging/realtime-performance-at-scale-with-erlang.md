Resource: https://youtu.be/2Llc_k28a-U

Based on the transcript of the video "Fredrik Linder - Realtime performance at scale," here is a comprehensive and accurate extraction of the content from start to end.

### **Introduction and Company Background**
The speaker is Fred Linder, who has over 15 years of server-side development experience, primarily in Erlang and C++, and formerly worked at Ericsson. He currently works at Machine Zone, which has grown from about 40 people in a single building in Palo Alto to a multinational technology company with offices worldwide. Machine Zone views itself as a tech company because they must build proprietary technology to handle the scale required for their products, primarily free-to-play mobile games.

The mobile market differs from the PC market because mobile devices have limited energy (batteries), unstable network connections, and lower CPU/graphics power. Machine Zone's major success is "Game of War," which is the world's largest single-world interactive game. Unlike other games that isolate players into smaller, sharded worlds due to capacity limits, Game of War places all players in the same world. The game launched progressively, starting in New Zealand, moving to Australia, then larger countries like Russia, France, the U.S., and Mexico, and is now available worldwide in over 40 countries.

### **Game Mechanics and Social Requirements**
"Game of War" is a medieval fantasy game where players build cities, armies, and heroes. Players improve their cities by building farms, quarries, and weapon smithies, and they use armies to attack others or defend themselves. The game utilizes a large map built on a grid of tiles containing kingdoms, cities, resources, and monsters.

The game is fundamentally social; players join alliances for protection and assistance, and social interactions can run deep, leading to real-world marriages. A major challenge is the language barrier among global players. To address this, the game requires a chat system with real-time translation. Traditional translation services (like Google or Bing) rely on large text volumes, but chat consists of short, slang-heavy text ("chat speak"), making language detection difficult. This translation must happen in real-time to maintain natural conversation flow.

### **Technology Stack and Services**
Machine Zone’s technology side builds reusable services, such as app services, chat services, and translation services. The presentation focuses on the map service and the chat service, both of which are implemented as Pub/Sub (Publish/Subscribe) systems.

**Pub/Sub Implementation:**
*   **The Map:** The map is a grid where every square acts as a separate channel for events. A player's view (viewport) subscribes to events in specific tiles (e.g., a green area). As the player scrolls, they must subscribe to new tiles and unsubscribe from old ones to save bandwidth and battery life. This subscription switching must be fast enough to prevent lag while scrolling.
*   **The Chat:** Each chat room (Kingdom chat, Alliance chat, one-on-1) acts as a separate topic or channel. Kingdom chats include everyone in a kingdom, while alliance chats are private groups.

### **Performance Goals and Theory**
The current system provides sub-second latency, but the game team requested 10x to 1000x improvements to enable new features. A 1000x improvement would theoretically handle unforeseen future features. The theoretical limit is determined by network connection rates (e.g., 10Mb connection with 100-byte payloads implies a specific message rate).

Performance is defined by throughput and latency. Linder cites **Little’s Law**: The average number of messages in a stable system equals the average throughput multiplied by the average queuing delay. Latency experienced by the client is the sum of processing time and queuing delay. To maximize performance, one must maximize messages while minimizing queuing delay and processing time.

**Optimization Strategies:**
1.  **Parallelism:** This scales only up to the number of cores.
2.  **Ordering:** Unlike Erlang's message delivery guarantees, Machine Zone does not guarantee strict ordering or delivery to reduce costs; they use an acknowledgment system instead.
3.  **Batching:** Grouping messages (like loading a truck) reduces the cost per message.
4.  **Minimizing Queuing Delay:** Ideally, the read rate should exceed the write rate to keep TCP buffers empty. They use `gen_tcp` with a controlled buffer size. Ideally, an Erlang process's inbox should be empty when it is scheduled out (after 2000 reductions). Large inboxes increase queuing delay. Blocking calls should be avoided.
5.  **Minimizing Processing Time:** Requires efficient algorithms and data structures, but crucially, avoiding the generation of garbage (waste data) to reduce overhead.

### **Architecture Evolution**
**The Current System:**
The existing system is based on `gproc` and uses a single node type in a mesh network where all nodes interconnect. It uses XMPP, which is protocol-heavy.

**The New System:**
The new in-house system uses multiple node types and a machine-to-machine (M2M) connection mesh where internal nodes do not all connect to each other. It uses JSON (for ease of use) and an in-house protocol.
*   **Node Splitting:** The system splits "Multiplexing" (MX) nodes, which handle client connections, from "Queue" (Q) nodes, which handle topics. This allows independent scaling; more MX nodes are added for more users, and more Q nodes are added for more data volume.
*   **Resiliency:** If a node dies, the system can simply add another, and reconnected clients resume work.

### **Data Path Optimizations**
**1. Connection Layer:**
Using `ranch` for TCP, they tested active/passive modes. `active, once` was chosen as the fastest option that allows for clean back-pressure control. They added a 20,000-message buffer to maximize throughput, though large buffers can increase queuing delay. To avoid contention on the inbox, the connection process was split: one process handles incoming traffic, and another handles outgoing traffic. This prevents a slow send (e.g., due to radio shadow) from blocking the reading process.

**2. Node-to-Node Communication:**
Standard Erlang distribution capped at ~250,000 messages/second between two nodes. To improve this, they buffer/batch Pub/Sub messages together into fewer Erlang messages. Standard `ets` tables were too slow for this, so they wrote a NIF (Native Implemented Function).

**3. Queue to Multiplexing (Q to MX):**
Initial push/pull models caused resource contention and latency issues. The solution was a subscription-based system where the topic process pushes data to a subscription process on the path, allowing parallel sending.

**4. Fan-out (Broadcasting):**
They strictly avoid sending the same message twice between nodes; messages are "exploded" (distributed to individual clients) only at the MX node. However, sending a message to 20,000 processes takes about 80ms, which scales linearly. To address this, they wrote a specialized NIF to handle the broadcasting more efficiently.

### **Erlang Code Optimizations (Garbage Generation)**
Linder demonstrates how code choices impact garbage collection and performance:
*   **List Construction:** Using a `foldl` to create a list generates garbage that is thrown away, whereas a `foreach` loop does not.
*   **List Comprehensions:** If the result of a list comprehension is used, it is comparable to other methods. However, if the result is *not* used (e.g., just for side effects), the compiler optimizes it such that the list is never generated, making it significantly faster (3x speed difference in the example) due to lack of garbage collection.
*   **Inline Operations:** Accumulating lists in steps generates intermediate garbage. Doing operations inline (e.g., inside a single pass) avoids this waste (4x waste difference in example).
*   **Reductions:** Generating intermediate lists also consumes more reductions, negatively impacting processing time.

The presentation concludes with Linder noting they can stretch the content slightly if needed, but ends the main technical portion there.