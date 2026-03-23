Resource: https://youtu.be/k01PHa5YDpQ

Based on the provided transcript of the video "Evolution of Edge @Netflix," here is an accurate and comprehensive extraction of the presentation from start to end.

### Introduction and Definition of Edge
The speaker, Vasily, introduces the topic by asking the audience to imagine a startup scenario to illustrate how infrastructure and business evolve over time. He uses Netflix as a case study for this evolution. He defines "edge" not as a distinct category, but as a quality of being close to the client. For instance, DNS is considered "edgier" than a database, though both are infrastructure components.

### Stage 1: The Startup Phase (Time to Market)
In the early stages, the priority is **time to market** rather than complex tooling.
*   **Architecture:** The company adopts a simple **three-tier architecture**: a client, a single API application, and a database. The API application serves as the edge.
*   **Infrastructure:** A load balancer terminates encrypted traffic, and a simple DNS record allows clients to find the service.
*   **Netflix Context:** Early Netflix used a monolithic application called **NCCP** (Netflix Content Control Protocol). It was the only application exposed to clients, sitting behind a hardware load balancer and a single domain name,.

### Stage 2: Growth and Microservices (Engineering Velocity)
As the company adds features and engineers, it transitions to **microservices** to preserve engineering velocity and avoid stepping on toes.
*   **The API Monolith:** While backend concerns are split into microservices, the API application remains the edge and acts as an orchestrator. Over time, the API itself becomes a monolith due to the accumulation of orchestration code.
*   **Splitting the Edge:** To manage the growing API, the edge must be split. This requires orchestration to route traffic correctly. Netflix utilized two approaches:
    1.  **Client-side Orchestration:** Splitting NCCP into separate services for playback and discovery, using different domain names.
    2.  **API Gateway (Zuul):** Introducing a gateway to route traffic transparently. Netflix added **Zuul** to handle further functional splitting,.

**The Role of the API Gateway (Zuul)**
The introduction of the API Gateway provided significant benefits:
1.  **Decoupling:** It creates a bridge between client contracts and service contracts.
2.  **Authentication:** Instead of implementing auth on every edge service (which complicates security patches), the Gateway handles authentication (e.g., OAuth, mTLS). It passes an **end-to-end identity token** (a signed token) to downstream services, so they know *who* is calling without knowing *how* they authenticated,.
3.  **Routing and Sharding:** The Gateway decouples the client from the backend structure.
    *   *Sharding:* Traffic can be routed to specific clusters (e.g., a TV-specific cluster) without the client knowing,.
    *   *Self-Service Routing:* Developers can route specific traffic (e.g., their own account) to a "bleeding edge" test cluster via **Deep Override Rules** based on headers or identity,.
    *   *Safety:* To prevent bad configurations (like routing 100% of traffic to a laptop), a traffic estimation job warns engineers of the impact before they apply routing rules.
4.  **Insights:** Because the Gateway is a choke point, it provides consistent metrics for all backends.
    *   **Atlas:** An open-source real-time dimensional database used for metrics.
    *   **Raven and Mantis:** Systems that allow engineers to filter and stream specific requests (e.g., "sample 5% of iOS errors") for debugging without logging everything.
    *   **Raju:** An anomaly detection service that alerts if error rates exceed acceptable thresholds.
5.  **Resiliency:** The Gateway implements **"choice of two"** load balancing (randomly choosing two instances and picking the best based on criteria) and performs retries on behalf of the client,.

### Stage 3: Resiliency and Quality of Service
The next evolution focused on **resiliency** and preventing outages (active-active multi-region deployment).
*   **GeoDNS:** Netflix moved from simple DNS records to traffic steering (via UltraDNS) based on the client's physical location (e.g., US West users go to the US West region).
*   **Traffic Evacuation:** To handle region outages, Netflix evacuates traffic by pointing DNS records to a healthy region.
*   **Cross-Region Proxying:** Because **DNS TTL** (Time To Live) is often ignored by resolvers (despite being set to 60 seconds), a trickle of traffic persists in the bad region. To solve this, Zuul gateways in the evacuated region open HTTP connections to healthy regions to proxy the remaining traffic,.

### Stage 4: Latency and Connectivity (Speed of Light)
The final stage addressed the physical limitations of the **speed of light** and long-distance networking.
*   **The Problem:** High latency (Round Trip Time) significantly delays the start of a request because establishing a secure connection requires TCP and TLS handshakes (approx. 3 round trips). For a client with 100ms latency to the data center, this means waiting **300ms** before sending the first byte. Wireless networks also introduce packet loss and congestion.
*   **The Solution:** Introducing **Points of Presence (PoPs)** and a **Backbone** network.
    *   *PoP:* An intermediary placed close to the client to terminate TLS and TCP.
    *   *Backbone:* A private internet connection between the PoP and the data center (like a "private highway").
*   **The Result:** By terminating the connection at a nearby PoP, the handshake latency is drastically reduced (e.g., to 90ms). The PoP then uses pre-warmed, multiplexed connections (HTTP/2) over the backbone to talk to the data center, improving congestion avoidance and recovery from packet loss,.

### Conclusion
Vasily concludes that a well-designed edge enables business evolution. He notes that Netflix went through this journey over years, summarizing that wise choices at the edge are critical for scaling.

### Q&A Session
1.  **Rented PoPs:** If using rented PoPs where you don't control the hardware, **TLS session tickets** should be used to offload termination securely.
2.  **ALB vs. Zuul:** AWS Application Load Balancers (ALB) are generally used to terminate TLS and route to Zuul. However, Zuul terminates TLS directly in specific cases, such as to support HTTP/2 ALPN, which AWS did not support at the time,.
3.    *   *Deep Routing:* The routing rules applied at the Zuul layer (Custom Request Routing) can override the target VIP not just for the next hop, but for the entire invocation chain downstream (e.g., telling a service deep in the stack to call a specific test cluster),.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
Yes. **Zuul 1** (Blocking) was replaced by **Zuul 2** (Netty/Non-blocking). More recently, many companies (including parts of Netflix) use **Envoy** for this layer universally.

**Is it scalable?**
**Yes.** Netflix's edge handles ~15% of global internet traffic.

**What would the architecture look like today?**
1.  **Envoy/Istio:** We would use **Envoy** as the Edge Gateway instead of writing a custom Java application like Zuul, leveraging its native C++ performance and Wast (WebAssembly) extensibility.
2.  **eBPF:** We would use **Cilium** or **Katran** (L4) to accelerate packet processing before it even hits the L7 Gateway.