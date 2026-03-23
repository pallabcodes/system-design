Resource: https://youtu.be/vXJsJ52vwAA

Based on the provided transcript of the video "How to scale WebSockets to millions of connections," here is an accurate and comprehensive extraction of the content from start to end:

**Introduction to WebSocket Scaling**
The speaker, Alex from Ably, introduces the topic of scaling WebSockets, noting that unlike the stateless, short-lived connections of HTTP, WebSockets operate over stateful, long-lived connections. This requires the server to tie up resources like memory and CPU for indefinite periods. Consequently, as an application gains traction, a server may hit hardware limits, causing performance and stability issues.

**Production Realities and Fallbacks**
While raw benchmarks often show WebSockets scaling to millions of connections, these are often unrealistic because production environments require additional processing, such as heartbeats, buffering, and delivered messages, which make the protocol more resource-hungry. Furthermore, developers must consider fallback options like HTTP long polling for situations where firewalls or misconfigured proxies block WebSocket connections. HTTP long polling is widely compatible but inefficient, placing more tax on the server and requiring a completely different scaling approach, adding complexity.

**Vertical Scaling (Scaling Up)**
There are two general ways to scale backend servers: vertical scaling (adding more resources to an existing machine) and horizontal scaling (adding more servers with a load balancer).
*   **Capacity:** It is difficult to answer exactly how many connections one server can support because it depends on resources, implementation, and specific requirements.
*   **Cost:** Vertical scaling requires provisioning for maximum capacity, which is expensive given that the server will not operate at that capacity most of the time (e.g., at night).
*   **Resource Limits:** Even powerful servers eventually hit resource limits, such as available threads or ephemeral ports, which require expertise in tinkering with kernel parameters to overcome.
*   **Single Point of Failure:** A single server represents a single point of failure. Routine tasks like upgrades or redeployments require taking the service offline, interrupting the user experience, which is the antithesis of continuous deployment. There are also risks of catastrophic code errors (like memory leaks) or service provider outages in a specific availability zone.

**Horizontal Scaling (Scaling Out)**
Horizontal scaling involves spreading the load across multiple machines, allowing for the dynamic addition or removal of servers based on demand to manage costs. A load balancer sits in front of the server array, typically using a round-robin algorithm to distribute incoming connections evenly. While robust, this method introduces architectural complexity.

**The Data Synchronization Challenge**
A major issue with horizontal scaling is that connections are fragmented across different servers.
*   **The Disconnection Problem:** If User A connects to Server 1 and User B connects to Server 2, they cannot communicate because the servers are disconnected from a state point of view.
*   **Broadcasting:** There is no single place to get a list of all connections to send a broadcast update.
*   **The Solution (The Backplane):** The solution is to store connection state out-of-process using a message broker (e.g., Redis) and the Pub/Sub design pattern. When User A sends a message to Server 1, it forwards the message to Server 2 via Redis, allowing Server 2 to deliver it to User B.

**Challenges of Horizontal Scaling**
Horizontal scaling is not a "silver bullet" and presents several challenges:
*   **Synchronization:** Developers must synchronize connection states (e.g., notifying when a user goes offline).
*   **New Failure Points:** Utilizing Redis means managing the replication of that broker to ensure the system remains robust.
*   **Overload Management:** To prevent a server from reaching hardware limits, developers need mechanisms to reject new connections and shed existing ones.
*   **Thundering Herd:** Shedding connections or losing a server can cause a "thundering herd" problem, where disconnected users try to reconnect simultaneously, putting undue pressure on the remaining servers and causing performance degradation or errors.

**Conclusion**
Asking how many connections a server can support is a moot question because connection activity varies. Relying on a single server makes an application prone to downtime, which can affect user confidence and business continuity.
*   **Vertical vs. Horizontal:** Some companies use a single, well-optimized vertical server if the risk of downtime is acceptable. However, for financial apps or platforms where the real-time experience is core to the user flow, downtime is not an option, making the investment in horizontal scaling necessary.

The video concludes with an offer to create specific technical tutorials on scaling if there is enough interest in the comments.

Q: How does The Elixir web framework, Phoenix, solves pretty much all of these problems. The BEAM VM was basically built for this?

Q: Probably, when people ask how many WS connections can a server have - they actually mean "What is the limit of WS/other connections on LB, and what does it depend on? Is it the number of opened file descriptors? Amount of RAM? Anything else?"

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?