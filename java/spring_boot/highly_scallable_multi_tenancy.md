Resource: https://youtu.be/PKuUXaDl7w0

Based on the transcript of the video presentation by Ansu Ann Varghese from IBM, here is an accurate and comprehensive extraction of the content regarding achieving a highly available and scalable backend in Knative Eventing.

**Introduction and Problem Statement**
Ansu Varghese, a Senior Software Engineer at IBM Hybrid Cloud Research, introduces the topic of achieving a highly available and scalable backend for event-driven architectures. She notes that currently, the Knative Eventing backend and its pool-based components (like Eventing sources) do not provide auto-scaling out of the box, nor do they have a framework to scale up and down for a "rich serverless experience". Because this is a basic requirement for enterprises, her team implemented an Eventing Scheduler to provide scaling solutions and distribute consumers across data plane pods based on priorities.

**User Expectations and Requirements**
The presentation outlines the expectations of a Knative user regarding event-driven architecture:
*   **Serverless Experience:** Users expect services to scale to zero when unused and scale up/down corresponding to the volume of events.
*   **Multi-tenancy:** In a multi-tenant world, auto-scalers must produce a consistent experience regardless of whether there are a few or numerous resource instances.
*   **Cost Efficiency:** Users do not want to pay for resource inefficiencies, particularly when running thousands of source instances.
*   **Performance and Density:** The backend data plane and controller must provide maximum throughput and high compute density.
*   **High Availability:** The system requires resilient support across failure domains in multi-region environments, ensuring quick recovery and minimal disruption.

**The Eventing Scheduler Architecture**
The new Eventing Scheduler serves as the foundation for meeting these expectations. Currently, dispatcher backend replicas instantiate one consumer per Knative resource, requiring manual configuration of consumer counts. The new solution allows for configuring parallel deliveries to increase throughput by scaling data plane deployments and partitioning consumers across them.

**Key Characteristics:**
*   **Integration:** It integrates easily with auto-scalers like KEDA.
*   **Generic Component:** The scheduler is a Knative generic component living in the Knative Eventing repository. It is a reusable framework customizable for various custom resources, not specific to any existing implementation.
*   **Duck Typing:** It uses a "Placement" duck type object (dynamic typing for data plane architectures) to store the pod name and the number of replicas assigned to it.

**Scheduler Sub-components:**
*   **Pod Autoscaler:** Increases or decreases data plane pods based on the number of replicas to be scheduled.
*   **State Collector:** Periodically gathers cluster state information to help select optimal placements.
*   **Compactor:** Checks distribution on every interval; if a lower ordinal pod has space, it evicts replicas from higher pods to scale down.
*   **Plugins:** The scheduler uses a staged approach involving **Predicates** (filters to determine where a replica *cannot* be placed) and **Priorities** (scoring plugins to weight valid pods). The scheduler selects the pod with the highest weighted score sum.

**Resiliency and Recovery:**
The scheduler handles recovery from domain failures or worker restarts. Data plane replicas are part of a StatefulSet architecture using pod anti-affinity rules to constrain scheduling across nodes. It relies on the "sticky identity" of pods in a StatefulSet and initiates rebalancing loops when consumer counts change.

**API Architecture and Consumer Groups**
Varghese presents an architecture diagram involving KEDA, Eventing Kafka Broker backed resources, and the scheduler.
*   **External API:** The Kafka Source API is user-facing and forwards Cloud Events from Kafka topics to a sink.
*   **Internal APIs:** The architecture introduces "Consumer Groups" and "Consumers".
    *   **Consumer Groups:** These behave as virtual pods within the scheduler framework. They can be manually scaled or auto-scaled by KEDA.
    *   **Mapping:** The scheduler places these virtual replicas onto real Kubernetes data plane pods, creating a "Consumer" resource for each bound data plane pod.
*   **Configuration:** A scheduler ConfigMap allows users to define or implement their own predicates and priorities.

**Advantages of the Approach**
*   **Reusability:** A general standalone scheduler prevents "reinventing the wheel" for new resources.
*   **Configurability:** It allows different personas (e.g., developers vs. SREs) to use different scheduling setups.
*   **Extensibility:** Resource controllers remain loosely coupled.
*   **Efficiency:** A shared data plane runtime reduces memory usage.

**Demonstration**
Varghese conducts a demo using the Eventing Kafka Broker repository on an IBM Cloud Kubernetes cluster spread across three US zones. The setup includes Knative Eventing, IBM Event Streams (100 partitions), and KEDA.

1.  **Initial Setup:** A Kafka Source is installed with 12 consumers (without KEDA enabled initially). The status shows 12 replicas scheduled, equally distributed among three dispatcher pods in different zones to satisfy High Availability.
2.  **Auto-scaling with KEDA:** Once KEDA is enabled, the replica count drops to zero because the source is idle.
3.  **Traffic Simulation:** An event producer script sends 10 events. KEDA scales the consumer group replicas from zero to one. The events are successfully received at the sink, and the replica count scales back to zero.
4.  **Recovery/High Load:** Varghese manually scales the consumer group to 60 replicas and sends 10,000 events. She then simulates a failure by updating a worker node to make it temporarily unavailable to demonstrate recovery.

**Performance Tuning and Conclusion**
Using Kafka Eventing Sources provides at-least-once delivery guarantees. While this ensures resilience, it can lead to duplicate events or performance issues. Varghese notes that the Eventing Kafka Broker data plane exposes Kafka consumer configurations via ConfigMaps. Tweaking these parameters can significantly improve performance and reduce duplicate messages.

**Future Work:**
*   Expanding scalability using the scheduler to other components like Triggers and Channels.
*   Directly integrating Kafka-backed resources with the KEDA Auto Scaler to simplify the operator experience, unifying auto-scaling and scheduling on the same APIs.

The presentation concludes with acknowledgments to the Red Hat Serverless team and IBM Research/Product teams.

Q: How can tuning the ConfigMap parameters reduce duplicate event messages?

Q: How the Predicate and Priority Plugins help optimal placement?

Q: Can the Evening Scheduler handler handle scalling for non-Kafka sources too?