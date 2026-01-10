Resource: https://www.youtube.com/watch?v=9tNZ4hAOhzs&pp=ygUXZXZlbnQgc291cmNpbmcgYXQgc2NhbGXSBwkJTQoBhyohjO8%3D

The following extraction details the presentation by Joseph Breuer and Robert Retta regarding Netflix’s implementation of **Event Sourcing** for their global "Downloads" feature.

### **Background: The Journey to Netflix**
Joseph Breuer joined Netflix in 2016 to work on the "Netflix Downloads" feature, which allows offline playback. His team was tasked with managing distributed data for all offline events. Breuer’s approach was shaped by previous failures at a startup where he worked on products for HBO:
*   **The Cassandra/Solr Failure:** The team lacked NoSQL experience and tried to layer Apache Solr over Cassandra to avoid learning NoSQL mechanics. Load testing caused latency spikes because Solr had to replicate index files, saturating the network and causing data inconsistency.
*   **The Relational Failure:** Switching to MySQL (NDB engine) for active-active replication failed because non-deterministic operations (like using UIDs for identifiers) caused data drift during network partitions. This forced a retreat from global active-active models to a single active site with a warm failover.

### **The Challenge of Global Scale**
Netflix serves over 100 million customers across 190 countries, handling approximately **one-third of all internet traffic** at peak.
*   **The Paradigm Gap:** Traditional relational systems (RDBMS) use **Object-Relational Mapping (ORM)** and foreign keys to outsource data modeling logic to the database. 
*   **NoSQL Constraints:** Cassandra has no joins; it requires developers to denormalize data and design schemas that mirror specific API queries (the "query-oriented" approach). 
*   **Global Distribution:** Netflix requires a consistent experience worldwide, meaning data must be replicated across three regions (US, Europe, and Asia) while maintaining performance.

### **The Event Sourcing Pattern**
To bridge the "paradigm gap," Netflix adopted Event Sourcing.
*   **State vs. Events:** Traditional databases store the "current state" (e.g., the current color of an object). Event sourcing stores the **sequence of events** that led to that state.
*   **The Bakery Analogy:** Robert Retta compares this to frosting. If the starting state is cream-colored and the goal is purple, the system records "Add Red" and "Add Blue" events. The **Aggregate** (the domain model) can be decomposed into these events and rebuilt at any time by replaying them.
*   **Commands as "Wishes":** A command is not an authoritative change but a request that can be rejected. For example, if a baker wants to turn purple frosting back to red, the system rejects the command because blue cannot be "extracted".

### **Technical Architecture and Mechanics**
The system is built on four primary components:
1.  **Event Store:** The database implementation (Netflix uses Cassandra) that returns a list of events for a specific Row ID.
2.  **Repository:** Translates domain logic into database queries, fetches events, and "buckets" them by **Aggregate ID**. It hydrates the aggregate in memory by replaying events.
3.  **Aggregate Service:** The public-facing API where business logic lives; it can reject requests based on rules (e.g., streaming plans or download limits).
4.  **Command Handler:** Determines which events are needed to fulfill a command based on the current state.

### **Real-World Use Case: Download Licensing**
Netflix uses two main aggregates:
*   **License Aggregate:** Tracks licenses issued to a device.
*   **Downloaded Aggregate:** Tracks how many times a customer has downloaded a specific title (e.g., *Glow*).
*   **Workflow:** When a user requests a download, the service checks the Downloaded Aggregate to see if they have reached their yearly limit (some studios only allow three downloads per title per year). If approved, a new License Aggregate is initialized, an event is persisted to the store, and the DRM server issues a license.

### **Cassandra Implementation and Optimization**
Netflix utilizes specific Cassandra features to ensure performance at scale:
*   **Schema Design:** They use the **Customer ID** as the partition key for fast access. The **Aggregate ID** is a clustering column to co-locate events, and **Time** is a second clustering column to provide natural ordering during hydration.
*   **Serialization with Kryo:** Netflix uses the Kryo library with a **Versioned Serializer**. This allows them to change data requirements frequently without resetting the database; the system simply fills in missing fields with default values when reading older event versions.
*   **Snapshotting:** To avoid replaying years of events, the system periodically serializes the aggregate state into a **Snapshot Table**. Future reads fetch the snapshot and only the events that occurred after that snapshot version.
*   **Data Management:** They use **Time to Live (TTL)** settings to automatically expire old records. Because the system only interacts with the latest snapshot and subsequent events, older logs can be archived or deleted like a "log rotation" without causing tombstone issues in Cassandra.

### **Managing Failures and Concurrency**
Joseph Breuer highlights that event sourcing requires a shift in handling technical errors:
*   **Handling Retries:** Latency can lead to client retries, resulting in multiple identical events being written to Cassandra. 
*   **Idempotency over Locking:** Developers should **not** try to enforce strict RDBMS-style transactions or high consistency levels in Cassandra. Instead, the **Aggregate Handler** must be built to handle duplicate events safely and identifiers should be made **idempotent** based on the request context.

***

**Analogy for Understanding**
To understand **Event Sourcing with Snapshotting**, imagine a **long-running ledger** for a bank. Instead of calculating your balance by reading every transaction since you opened the account in 1990 (Event Sourcing), the bank writes a "Total Balance" at the end of every year (**Snapshotting**). When you check your balance today, they take the 2023 year-end total and only add the transactions from 2024. This gives you the full history and current accuracy without the massive effort of reading every single coffee you've ever bought.