Based on the transcript of Tom Wilkie’s presentation "Monitoring Microservices" at GOTO 2016, here is a comprehensive extraction of the talk, from start to end.

### **Introduction and Thesis**
Tom Wilkie begins by stating the thesis of his talk: Microservices have fundamentally changed the architecture used to build applications, and therefore, engineers need to think about different techniques to monitor those applications. He emphasizes that monitoring is more than just drawing time-series charts. He structures the talk into three sections: Traditional Monitoring, Visualization, and Tracing.

### **Part 1: Traditional Monitoring**
**The Shift from Monoliths to Microservices**
*   **Monoliths:** Traditional applications are characterized by static architectures with few moving parts, typically running on dedicated hosts or VMs. They are explicitly named and cared for (pets).
*   **Microservices:** These architectures are dynamic, with frequent code pushes (potentially every few minutes). There is no prescribed technology stack; responsibility for tools, languages, and subsystem architecture is delegated to individual teams. This flexibility means you cannot rely on a single static monitoring system.

**The Dashboard Problem**
*   **Old World:** Dashboards for monoliths focus on host-centric metrics (Disk I/O, CPU). The "primary key" for monitoring was the **Host**.
*   **New World:** In a microservices environment, the "primary key" must shift to the **Application** or **Service**.

**Methodologies: USE vs. RED**
*   **The USE Method:** Wilkie references Brendan Gregg's "USE Method," which measures **U**tilization, **S**aturation, and **E**rrors for every resource. Wilkie notes this is excellent for capacity planning but not ideal for service monitoring.
*   **The RED Method:** Wilkie proposes the "RED Method" for service monitoring. For every service, you should measure:
    *   **R**ate (of requests).
    *   **E**rrors (rate of failed requests).
    *   **D**uration (latency of requests).
*   These metrics should be viewed in aggregate for the service, not per individual replica. This data is critical for validating blue/green deployments.

**Implementation Challenges and Solutions**
*   **The Problem with Instrumentation:** The traditional approach requires adding code to every binary to export metrics. This creates a "top-down mandate" where everyone must use specific libraries (e.g., Prometheus clients), violating the microservices principle of team delegation.
*   **The Solution (Platform-Side Monitoring):** The platform itself should provide metrics. Most platforms (like Kubernetes with kube-proxy or Cloud Foundry) have load balancers that see all requests. By instrumenting the load balancer, you get uniform, consistent metrics without forcing developers to instrument their code.
*   **Weave Flux:** Wilkie mentions an open-source project (Flux) which acts as an instrumented, programmable load balancer that exports metrics to Prometheus.

### **Part 2: Visualization**
**The "Whiteboard" Problem**
Wilkie notes that architecture diagrams drawn on whiteboards are often wrong because institutional knowledge lags behind the rapidly changing reality of the application. He argues for a tool that automatically draws a map of the application topology without requiring manual annotation.

**Weave Scope**
He introduces **Weave Scope**, an open-source tool written in Go (focused on Docker and Kubernetes) that discovers and visualizes topology.

**Technical Challenges of Discovery**
Wilkie explains why mapping topology is technically difficult. Getting nodes (containers/processes) is easy via APIs, but getting the edges (connections) is hard.
*   **Conntrack:** Can provide a live stream of connection events, but is hard to interpret (just IP addresses) and difficult to map to containers, especially if they share network namespaces.
*   **Proc File System:** One can scan `/proc/net/tcp` to map file descriptors (FDs) to connections, then map processes to FDs, then processes to containers. However, reading `proc` is CPU-expensive. It must be done periodically, meaning short-lived connections between scans are missed.
*   **The Venn Diagram of Data:** Wilkie describes the data collection as a Venn diagram where `proc` data and `conntrack` data overlap but are incomplete. Neither catches connections from the host net namespace (e.g., Docker daemon) or properly handles virtual IPs used by software load balancers.

**Scope Demo**
Wilkie demonstrates Weave Scope running locally:
*   **Discovery:** Scope scrapes an example app (Python, ElasticSearch, Redis, Nginx) without any annotation or modification to the app.
*   **Search & Interaction:** It supports searching by process name or IP. Users can click nodes to see CPU/Memory metrics, access logs, or launch an interactive terminal inside a container.
*   **Grouping:** To solve the problem of "too much information," Scope can group containers by metadata (e.g., DNS name or Kubernetes Service) to provide a high-level, whiteboard-style view.

### **Part 3: Tracing**
**The Need for Distributed Tracing**
In a monolith, profiling (like a Go profile) is sufficient for debugging. In microservices, a single request traverses tens of services, making standard profiling insufficient. Distributed tracing is required to understand where time is spent.

**Current Approaches (Zipkin/Dapper)**
*   Existing tools like Zipkin are modeled on Google's Dapper paper.
*   **Mechanism:** They work by injecting a unique ID into an incoming request and propagating that ID to all outgoing requests.
*   **The Flaw:** This requires modifying *every* application to propagate headers. If one service is not instrumented (e.g., legacy code or a team that hasn't updated yet), the trace breaks, creating a "black box" that hampers adoption.

**Proposed Solution: Tracing without Modification**
Wilkie asks if tracing can be done without modifying the application. He references a Microsoft Research paper regarding operating system instrumentation.
*   **Concept:** Use `ptrace` (system call interception) to intercept IO system calls. By building an in-memory data structure of which thread is reading/writing to which file descriptors (and which IPs/Ports those FDs represent), one can infer causality.
*   **Limitations:** This assumes a "thread-per-request" model. It breaks down with asynchronous, reactor-based architectures (like Netty) where incoming and outgoing IO happen on different threads. However, Wilkie argues many apps still use thread-per-request logic.

**Tracing Demo (Prototype)**
He demonstrates a prototype tracer:
*   **Setup:** A load generator hits a Python app, which talks to an "Echo Server" and a "Quote of the Day" server.
*   **Causality:** The tracer successfully identifies that one incoming request causes two outgoing requests without any app instrumentation.
*   **Linking Processes:** He demonstrates linking an outgoing request from the App to the incoming request of the Quote server using only IP/Port matching, again without propagated IDs.
*   **Debugging:** He uses the tracer to identify that the "Echo Server" is the specific component causing slowness in the request chain.

**Future of Tracing**
Wilkie notes that `ptrace` is too slow for production because it pauses the application. The future solution lies in using **eBPF** (extended Berkeley Packet Filter) to inject filters into the kernel for high-performance, non-intrusive tracing.

### **Conclusion and Q&A**
Wilkie summarizes the three tenets:
1.  **Monitoring:** Change the primary key from Host to Service.
2.  **Visualization:** Necessary for dynamic architectures; doable without app modification.
3.  **Tracing:** Essential for microservices; hopefully achievable without app modification in the future.

**Q&A Highlights:**
*   **Scale:** When asked if visualization works for hundreds/thousands of containers, Wilkie admits it is an open question. They are adding search and filtering (grouping) to manage complexity.
*   **Message Buses:** For event-driven architectures (message buses) where connections are not direct TCP links, Scope's visualization is less effective. However, plugins can be written to feed custom relationship data to Scope.
*   **Installation:** Scope can be installed on Kubernetes, Mesosphere, Docker Swarm, and ECS.
*   **Non-Docker Support:** Scope works on standard processes (Linux/Darwin) and does not strictly require Docker.
*   **Cross-Network/NAT:** Handling IPs across different networks/NATs is difficult ("nightmares and lost sleep with IP tables"), but work is being done to support it.