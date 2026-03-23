Resource: https://youtu.be/XuQfXQYUsgY


Based on the transcript of the video "NSDI '15 - Retro: Targeted Resource Management in Multi-tenant Distributed Systems," here is an accurate and comprehensive extraction of the presentation from start to end.

**Introduction and Motivation**
The presentation, a collaboration between Brown University and Microsoft Research, begins by addressing failures in distributed systems caused by insufficient resource management. Examples of such failures include outages cascading from isolated availability zones to shared control planes due to overloaded shared queues, misconfigured background tasks aggressively consuming resources, and unmanaged resources like database locks or disk throughput (in YARN) becoming unexpected bottlenecks.

**The Problem with Shared Systems**
Actively controlling multi-tenant systems is challenging because user requests traverse shared processes involving various system resources (disk, CPU, network) and application-level resources (locks, thread pool queues). Operating systems and hypervisors lack visibility into which tenant is responsible for resource consumption within a shared process. Furthermore, requests traverse multiple machines and services, requiring coordination along the entire execution path. While containers and VMs provide some isolation, underlying shared systems like storage, databases, and coordination services remain vulnerable if their resources are not carefully managed.

**Retro Framework Overview**
The researchers introduce Retro, a comprehensive framework for active resource management in multi-tenant distributed systems. Retro monitors resources in near real-time and actively throttles tenants based on centralized, high-level policies. It utilizes three novel abstractions to separate resource management logic from system implementation details.

**Concrete Example: HDFS**
To demonstrate the problem, the speaker uses the Hadoop Distributed File System (HDFS), which consists of a central NameNode (metadata) and DataNodes (file data). Operations consume various resources, such as shared RPC thread pools, read/write locks on the NameNode, and system resources like disk on DataNodes.

In an experiment, a tenant running a loop of 8KB reads experiences latency spikes due to three other workloads:
1.  **4MB Reads:** Causes congestion on DataNode disks.
2.  **Directory Listings:** Causes congestion on the NameNode's incoming RPC queue.
3.  **File Renaming:** Causes congestion on the NameNode's read/write lock (requiring write locks unlike the others).

This demonstrates that bottlenecks can appear anywhere (system or application level), change dynamically, and interfere with each other. Co-locating applications like HBase (distributed database) or MapReduce exacerbates this as they traverse multiple systems and consume resources directly or via HDFS.

**Retro’s Goals**
Retro aims to coordinate control across varying processes and machines, manage both system and application-level resources, account for all tenants/tasks, operate in real-time, and maximize the utilization of remaining capacity when resource management goals are met.

**Retro’s Three Abstractions**
1.  **Workflows:** Since systems lack visibility into which tenant is executing, Retro introduces the "workflow" abstraction. A workflow corresponds to requests from a user or a background task over time. It is the unit of resource measurement and enforcement, orthogonal to threads or processes. Retro propagates a workflow ID alongside execution, similar to end-to-end tracing.
2.  **Resources:** Retro abstracts resources by focusing on two metrics:
    *   **Slowdown:** Identifies congestion by comparing current performance to an uncontended baseline (e.g., queue wait time).
    *   **Load:** Attributes congestion to specific workflows (e.g., time spent executing). This avoids needing to know low-level implementation details.
3.  **Control Points:** These are decoupled from resources and represent points where Retro can rate-limit workflows. Implementation examples include token bucket rate limiters (pausing threads) or priority queues. This allows Retro to throttle aggressive tenants across all tiers to relieve congestion.

**Architecture and Policies**
Retro aggregates resource measurements locally and sends them to a central controller once per second. This controller maintains a global view and runs a continuous control loop executing resource management policies.

The speaker details a **Latency SLO (Service Level Objective) Policy**:
*   **Goal:** Provide guaranteed average latency to high-priority workflows while allowing low-priority workflows to use spare capacity.
*   **Logic:**
    1.  Select the high-priority workflow with the worst performance relative to its guarantee.
    2.  Calculate an interference weight for all low-priority workflows based on their load on resources that are congested and important to the high-priority workflow.
    3.  Throttle low-priority workflows based on these weights or relax them if the guarantee is met.
*   **Parameters:** The policy operates incrementally using alpha and beta parameters to control step sizes.

Other policies mentioned include "Bottleneck Fairness" (fairly sharing the most overloaded resource) and "Dominant Resource Fairness" (DRF).

**Implementation**
Retro is implemented in Java, consisting of an instrumentation library and a central controller. It intercepts API calls to aggregate counters in memory. Workflow IDs are stored in thread-local variables and passed across RPCs. Much of the instrumentation is automated using AspectJ (dynamic bytecode modification), requiring only 50–200 lines of manual code per system. The overhead is low, affecting throughput and latency by only 1–2%.

**Evaluation**
Experiments were conducted on a 200-node cluster using 5 open-source systems (including HDFS and HBase) managing CPU, disk, network, locks, and queues.

*   **Scenario:** Three high-priority workflows (HDFS read, HBase disk read, HBase cache read) and three low-priority workflows (HBase table scan, HDFS make directory, HBase cache scan).
*   **Without Retro:** Making low-priority workflows aggressive caused high-priority latencies to spike significantly above their SLOs due to bottlenecks in disk, CPU, locks, and RPC queues.
*   **With Retro:** The policy successfully prevented high-priority latencies from violating guarantees.
    *   The table scan was throttled because the policy identified disk as the bottleneck.
    *   The `mkdir` client was throttled because the policy identified the HDFS metadata lock as the bottleneck.
    *   The cached table scan was throttled because the policy identified the HBase RPC queue as the bottleneck.

**Conclusion**
Retro successfully provides comprehensive, centralized resource management across distributed systems using its three key abstractions to run concise, general-purpose policies.

**Q&A Session**
1.  **HDFS Sharing:** An audience member asked how common it is to share HDFS clusters. The speaker replied that based on experience with Windows Azure Storage and other workloads, resource contention patterns are common, and the system is designed to be agnostic.
2.  **Zookeeper:** A question was raised about HDFS performance and Zookeeper results. The speaker noted Zookeeper provides no multi-tenancy or isolation, so blocking is easy. Retro handled bottlenecks in the shared log.
3.  **Control Point Placement:** A questioner asked how to determine where to inject control points automatically. The speaker admitted this required intuition: points must be high enough to avoid conflicting with OS schedulers but low enough to be effective. However, it only required modifying about two lines of code (e.g., HDFS data transfer threads and a general-purpose RPC queue).


Q: How does User impersonation solve the Service Account token risk?

Q: What criteria should I use to pick a database architechture?

Q: How do slowdown and load metrics identify system bottlenecks?