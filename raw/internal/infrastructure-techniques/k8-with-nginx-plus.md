Resource: https://youtu.be/v_VMLkt4mTA?list=TLGG-9ZETueuM5kxNTAyMjAyNg

Based on the transcript of the presentation by Suresh and Mrunmayi Dhume from Oath (Yahoo), here is an accurate and comprehensive extraction of the content regarding the Kubernetes Ingress Controller with Apache Traffic Server (ATS).

### **Introduction and Context**
Suresh, a Senior Architect, introduces the team from **Oath** (a company formed by the merger of Verizon, Yahoo, and AOL). He and Mrunmayi (Senior Software Engineer) are part of the core infrastructure team powering media products like Yahoo Sports, Finance, and News.

**Scale and Infrastructure:**
*   They manage the complete Kubernetes cluster for these products.
*   The infrastructure consists of **12 Kubernetes clusters** across **6 data centers**.
*   They host 100+ applications.
*   **Scale:** 150,000 requests per second (RPS) at peak. The Ingress layer specifically handles **1.8 million RPS** at peak.
*   **Volume:** They run over 10,000 pods with approximately 40,000 containers.
*   **Philosophy:** They manage the clusters but provide tools (CI/CD) to give product developers an independent pipeline to deploy code.

### **Architecture Overview**
Suresh explains their in-house architecture (running on bare metal, not public cloud):
1.  **Custom Tools (In-house):**
    *   **Screwdriver:** A continuous delivery pipeline allowing users to natively apply `kubectl` YAMLs.
    *   **Webhook Authorization:** A custom webhook ensures that the user or pipeline trying to deploy code to a specific namespace is authorized to do so.
2.  **Identity (Athenz):** An open-source, role-based authorization system (similar to AWS IAM) used for user and service identity.
3.  **Ingress (Apache Traffic Server - ATS):** The custom ingress layer handling traffic from mobile/web users before routing to origin pods.

**The Ingress Challenge:**
*   Origins are dynamically changing pods (new deployments, crashes).
*   Every time a pod changes, it gets a new IP.
*   Roughly 40,000 to 50,000 pods are created/destroyed daily.
*   The Ingress layer must dynamically update routes to these changing IPs.

### **Evolution of the Design**
Suresh details the history of their Ingress design:

**Version 1 (The Reload Method):**
*   **Mechanism:** Whenever an origin IP changed, they fed the data to ATS and reloaded the ATS process.
*   **Problem:** Reloading impacted in-flight requests and increased long-tail latency.
*   **Mitigation Attempt:** Instead of reloading instantly, they batched updates every 5 seconds.
*   **Result:** Latency charts showed "sawtooth" spikes corresponding to reloads.
*   **Second Mitigation:** Increased batching to 30 seconds. This reduced spikes but was not scalable or responsive enough (users had to wait 30 seconds for traffic to route to new pods).

**Requirements for the New Solution:**
1.  **Dynamic Updates:** No process reloads.
2.  **Plugin Support:** Must support existing Yahoo-invested ATS plugins (ESI, SSL) used for media sites.
3.  **Native Specs:** Must use the native Kubernetes Ingress specification (like Nginx controllers).
4.  **Seamless Experience:** Developers should only need to define YAMLs with URLs/Hosts, without dealing with operations teams.

**Why Apache Traffic Server (ATS)?**
*   Fast and scalable.
*   Significant existing investment from Yahoo (plugins).
*   Extensible: Easy to write new load balancing algorithms (e.g., weighted least connection) or modify HTTP transaction hooks.

### **The Kubernetes Ingress Controller Design**
Mrunmayi Dhume takes over to explain the internal design of the controller.

**Flow of Data:**
The controller reacts to cluster changes, processes them, and provides routes to ATS. It consists of four main components:

1.  **Service Watcher:**
    *   Sets a watch on the Kubernetes API for `Ingress` and `Endpoints` resources.
    *   Notified of creation, updates, or deletions.
    *   Fetches info and writes it to a JSON file format.

2.  **Health Monitor:**
    *   Performs periodic health checks on the Pod IPs obtained by the Service Watcher.
    *   **Logic:** Only IPs returning a 200 OK response are written to a second set of JSON files.
    *   **Reasoning:** The Ingress controller sits on bare metal hosts *outside* the Kubernetes cluster. This prevents "Network Split Brain" issues where a pod is healthy inside the cluster but unreachable from the Ingress layer.

3.  **Compiler:**
    *   Watches the JSON directory for changes.
    *   Compiles the JSON changes into a binary format consumable by ATS.

4.  **Traffic Manager Plugin:**
    *   Watches the binary file directory.
    *   Does an **in-memory map** of the binary file into the ATS memory map.
    *   **Benefit:** This updates routes in a matter of seconds without replacing the entire memory map or reloading the process, causing zero impact to in-flight requests.

### **Usage and Annotations**
To use the controller, developers use the native Kubernetes Ingress resource with custom annotations:
*   **Ports:** To specify non-standard ports (e.g., 8080, 9099).
*   **Default Domain:** The domain the application should be routable on.
*   **Aliases:** Allows specifying multiple aliases for the same backend without duplicating host entries.

### **Key Features**
Mrunmayi highlights three specific features built for their environment:

**1. Cluster-Level Fail-out:**
*   **Scenario:** A network issue or maintenance requires taking a whole cluster (region) offline.
*   **Solution:** Admins create a ConfigMap. The Service Watcher detects this and tells ATS to serve a `404` response for the health check URL of that cluster.
*   **Result:** The external DNS routing layer sees the 404 and seamlessly diverts traffic away from that cluster.

**2. Application-Level Fail-out:**
*   **Scenario:** An individual application needs to divert traffic from a specific region.
*   **Solution:** Similar to cluster fail-out, the application specifies a ConfigMap. ATS starts serving 404 health checks *only* for that application, diverting its traffic while leaving other applications on the cluster unaffected.

**3. Ingress Claims ( preventing Domain Hijacking):**
*   **Problem:** "Generic App 1" claims `yahoo.com`. "Generic App 2" applies an ingress claiming the same alias. ATS behavior is non-deterministic (depends on load order), potentially routing Sports traffic to Finance.
*   **Solution:** **Ingress Admission Controller**.
    *   Uses a Kubernetes Dynamic Admission Control webhook.
    *   Before an Ingress resource is created, it is validated by an **Ingress Claim Service**.
    *   This service maintains a map of domains and applications.
    *   If a domain is already claimed by App 1, App 2's request is rejected (validation fails). If unclaimed, it is allowed.

### **Demo**
Mrunmayi conducts a demo:
1.  Accesses `kubecon.media.yahoo.com/kubecon.html`. It shows a "Be Right Back" page (no route exists).
2.  Shows a YAML file with the Ingress specification, custom annotations (alias, ports), and a deployment for an Nginx container.
3.  Runs `kubectl apply`.
4.  Watches the pod status change to "Running".
5.  Refreshes the browser. The Nginx page loads immediately, showing the route was updated in seconds.

### **Future Work and Conclusion**
Suresh returns for concluding remarks.

**Future Work:**
*   **TCP/UDP Support:** ATS is great for HTTP, but lacks TCP support (needed for workloads like Redis). They are evaluating alternatives like **IPVS** or **Envoy** for these use cases and plan to share results at the next KubeCon.

**Open Source:**
*   Components like **Athenz**, the webhook, and dynamic admission controls are already open source.
*   They are in the process of open-sourcing the Ingress Controller and Ingress Claim Service.

**References:**
Suresh recommends viewing his previous presentation on "Bare Metal Kubernetes" to understand their specific network model and cluster management.

### **Q&A Session**
1.  **Caching:**
    *   *Question:* Do you use ATS for caching in front of Kubernetes?
    *   *Answer:* No. This layer is strictly for routing. Applications (like Sports) use their own caching layers (e.g., sidecar Redis or Node.js caches).

2.  **Health Checks:**
    *   *Question:* What challenges led to the active health check design?
    *   *Answer:* Network ACL or switch issues often broke communication between the Ingress layer and the Pod, even though the Kubernetes API reported the Pod as healthy. Active checks were required to ensure reachability from the Ingress layer specifically.

3.  **Annotations:**
    *   *Question:* The annotations (port, domain) are very generic and might conflict with other controllers. How hard is it to namespace them?
    *   *Answer:* It is easy to change, but currently, they use a shared ingress layer. They are evaluating namespace-specific ingress for critical workloads where isolation is required.

4.  **TCP Ingress Specification:**
    *   *Question:* Is the lack of TCP support a limitation of ATS or the Ingress resource spec?
    *   *Answer:* It is a limitation of the Kubernetes Ingress spec itself, which only supports HTTP/HTTPS. They may look into defining TCP protocols in the Service layer or contributing back to the open-source community to expand the Ingress spec.