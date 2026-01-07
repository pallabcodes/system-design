[RESOURCE]: https://www.youtube.com/watch?v=Uv1GOrZWpBM

The following extraction details the progression of Lutz Huehnken’s talk on maintaining sanity in event-driven architecture, moving from common pitfalls to a fundamental shift in mindset.

### **The "Windows on Mac" Metaphor**
Huehnken begins with an anecdote from 2008 when a company bought Apple hardware but installed Windows XP on it, failing to leverage the benefits of the actual hardware,. He compares this to **putting workflows on top of event-driven architecture (EDA)**, suggesting that while possible, it may counteract the benefits of being event-driven.

### **Common Approaches to Distributed Processes**
The speaker identifies three typical ways developers handle multi-step processes like an order workflow:
*   **Central Coordinator:** A single service (e.g., an "Order Service") manages the overall flow, emitting events and waiting for responses. This often leads to technical bloat within that service, such as handling timeouts and process changes.
*   **Workflow Engines:** Moving the logic into external tools like **Temporal, Camunda, or Google Workflows**. While this separates business logic from process logic, it often results in logic being trapped in XML or YAML files, making unit testing difficult,.
*   **The Saga Pattern:** A popular pattern for "All or Nothing" distributed systems using **compensating transactions** to return to a consistent state if a step fails,. Huehnken views this as a "spiritual successor" to distributed transactions that accepts temporary inconsistencies.

### **The Critique: Why Orchestration Often Fails EDA**
Huehnken argues that these approaches often "suck" because they introduce **complex, stateful technology** (like Saga coordinators or persistence layers using Paxos) that can become single points of failure,. Furthermore, he critiques the use of **"passive-aggressive events"**—commands disguised as events (e.g., an event that really means "reserve this inventory and acknowledge me"),. This creates a request-response pattern that hinders the autonomy of microservices,.

### **The Event-Driven Mindset: Facts and Promises**
To keep architecture "sane," Huehnken advocates for a shift in how developers view communication:
*   **Events as Facts:** Unlike commands (which express intent and can fail), events are **immutable facts**,. Once an event is emitted, the sender should not care who consumes it or what they do with it,.
*   **Clear Responsibility:** In a true EDA, the receiver of an event is solely responsible for handling it and managing its own errors,. 
*   **Micro Workflows:** Instead of one large, monolithic workflow, developers should break processes down into **micro workflows** that align with autonomous teams.
*   **Promise Theory:** Rather than "commanding" services through a central process, systems should rely on **promises**, where services fulfill their specific roles (e.g., handling payment) and emit a fact when finished,.

### **Control vs. Observability**
A major concern in choreography (event-driven) is losing sight of the end-to-end process. Huehnken argues we should **separate control from observability**. Control should be distributed, but observability can be centralized by having a dedicated service aggregate events into a tool like Elasticsearch to provide a view of the process status without controlling it,.

### **Conclusion and Organizational Fit**
The speaker concludes that the friction often stems from a **mismatch between architecture and organization**. He compares using heavy orchestration in microservices to the **"shitty agile" (SAFe)** framework, which attempts to force enterprise structure onto agile processes,. He urges architects to go back to **first principles** and choose choreography over orchestration to leverage the true advantages of being event-driven,.

***

**Analogy for Understanding**
To understand the difference between orchestration and choreography, imagine a **theater production**. **Orchestration** is like a director standing on stage shouting instructions to every actor for every single move. If the director trips, the whole play stops. **Choreography** is like a dance where every performer has learned their part and reacts to the movements of others; there is no single person directing every second, yet the entire group moves in harmony toward the finish.