# SolrCloud Cluster Management at Scale: Bloomreach Case Study

> **Source**: [SolrCloud Multi-DC Management - Bloomreach](https://youtu.be/IW3EglkY-R0)

> [!IMPORTANT]
> **The Challenge**: Bloomreach serves **hundreds of millions of documents** for multiple tenants on SolrCloud. Their retail search app ("Snap") requires **zero downtime** and **low latency** across multiple data centers—while handling customer-specific code that can crash JVMs.

---

## 📊 Multi-DC Architecture

```mermaid
graph TB
    subgraph "Management Layer"
        API[Management API]
        DB[(MySQL RDS<br/>Metadata)]
        API --> DB
    end
    
    subgraph "Cluster: Production"
        subgraph "US-East (Serving)"
            SE1[Solr Nodes]
            ZK1[Zookeeper]
            LB1[Load Balancer]
        end
        
        subgraph "US-West (Serving)"
            SE2[Solr Nodes]
            ZK2[Zookeeper]
            LB2[Load Balancer]
        end
        
        subgraph "Backup DC"
            SB[Solr Nodes]
            ZKB[Zookeeper]
        end
    end
    
    subgraph "Storage"
        S3[(Amazon S3<br/>Indexes, Configs)]
    end
    
    API --> SE1
    API --> SE2
    API --> SB
    SB --> S3
    SE1 -.->|HAFT Replication| SB
    SE2 -.->|HAFT Replication| SB
```

---

## 🔴 Core Challenges

| Challenge | Description |
| :--- | :--- |
| **Custom Tenant Code** | Customer-specific ranking code runs in same JVM. Bad code = JVM crash. |
| **Large Ranking Files** | Some tenants upload massive files → memory spikes, unresponsive nodes. |
| **Multi-DC Coordination** | Global customers need multiple DCs. Single Zookeeper = SPOF. |
| **Zero Downtime** | Retail search cannot afford any outages. |

---

## 🏗️ Logical Abstraction Layer

### Key Concepts

| Concept | Definition |
| :--- | :--- |
| **Logical Data Center** | A unit of Solr + Zookeeper nodes representing a role (serving, backup, preview). |
| **Cluster** | A collection of logical DCs (e.g., "Production Cluster" = US-East + US-West + Backup). |
| **Metadata Storage** | MySQL RDS stores all configuration and state for every node. |

> [!TIP]
> Each DC has **independent Zookeeper**. No single point of failure across DCs.

---

## 🛠️ Management APIs

| API | Purpose |
| :--- | :--- |
| **HAFT (Replication)** | Replicates indexes from indexing clusters to production. Open-sourced. |
| **Ranking File Management** | Versions and stores customer ranking files on S3. |
| **Deployment Service** | Provisions new capacity or restores failed nodes. |
| **Recovery Service** | Automates hardware and software recovery. |

---

## 🔄 Recovery Procedures

```mermaid
flowchart LR
    subgraph "Hardware Recovery"
        H1[Node Fails] --> H2[Get Config from MySQL]
        H2 --> H3[Provision New Host]
        H3 --> H4[Install Solr/ZK]
        H4 --> H5[Fetch Index from Backup]
        H5 --> H6[Smoke Test]
        H6 --> H7[Add to Load Balancer]
    end
```

### Hardware Recovery (Fully Automated)
1.  Detect node failure.
2.  Retrieve existing configuration from MySQL.
3.  Provision new host on AWS.
4.  Install Solr/Zookeeper.
5.  Fetch indexes from backup DC.
6.  **Smoke test**: Compare query results with other DCs.
7.  Add back to load balancer.

### Software Recovery (Soft Recovery)
1.  Detect bad JAR or JVM memory exhaustion.
2.  **Snapshot** current state (configs, jars) to S3.
3.  **Revert** to known stable version.
4.  Sync queued updates.
5.  Return to load balancer.

### Capacity Expansion (On-Demand)
1.  Holiday traffic spike detected.
2.  Provision new DC machines.
3.  Install Solr/ZK via automation.
4.  Fetch indexes from backup DC.
5.  Pull configs from serving DC.
6.  Add to cluster.

---

## 🔧 Maintenance Mode Pattern

```mermaid
sequenceDiagram
    participant LB as Load Balancer
    participant DC1 as DC-1 (Update Target)
    participant DC2 as DC-2 (Active)
    participant DC3 as DC-3 (Active)
    
    Note over DC1: Normal Operation
    LB->>DC1: Traffic
    LB->>DC2: Traffic
    LB->>DC3: Traffic
    
    Note over DC1: Enter Maintenance Mode
    LB--xDC1: Remove from LB
    DC1->>DC1: LOCKED - Apply Updates
    DC2->>DC2: Queue updates for DC1
    
    Note over DC1: Sync & Verify
    DC1->>DC1: Apply queued updates
    DC1->>DC1: Smoke tests
    
    Note over DC1: Back to Normal
    LB->>DC1: Add back to LB
```

### Key Points
*   DC is **locked** and removed from load balancer.
*   Other DCs handle 100% of traffic.
*   Updates are **queued**, not lost.
*   Rollback possible at any stage.

---

## 📊 Monitoring Strategy

| Level | What's Monitored |
| :--- | :--- |
| **Node Level** | Ping nodes, check queryable collections, JVM/CPU usage. |
| **Cluster Level** | Ensure all DCs have consistent indexes and configurations. |

---

## 🚀 Future: Full Auto-Recovery

| Capability | Description |
| :--- | :--- |
| **Auto-Restart** | Automatically restart Zookeeper/Solr nodes on failure. |
| **Auto-Resync** | Resync mismatched configs from S3. |
| **Auto-Rollback** | Roll back code if JVM usage exceeds 90% after deployment. |

---

## ✅ Principal Architect Checklist

1.  **Eliminate Single Points of Failure**: Each DC should have independent Zookeeper. No cross-DC ZK dependencies.
2.  **Store All State Externally**: Configs, indexes, ranking files in S3/MySQL. Nodes should be replaceable.
3.  **Implement Smoke Tests**: Before adding recovered nodes to load balancer, verify query results match other DCs.
4.  **Use Maintenance Mode for Updates**: Never update all DCs simultaneously. Queue updates, roll DC-by-DC.
5.  **Snapshot Before Changes**: Always snapshot to S3 before deployments. Enable instant rollback.
6.  **Monitor at Both Levels**: Node-level (health) AND cluster-level (consistency) monitoring required.

---

## 📖 Analogy: Global Cargo Ship Fleet

> [!TIP]
> Managing this infrastructure is like operating a **global fleet of automated cargo ships**:
>
> *   **Centralized Control Tower** (Management API) instead of a captain on every ship.
> *   **Hardware Failure**: Tower launches new identical ship, transfers cargo from nearby support vessel.
> *   **Software Error**: Tower swaps bad fuel for previous proven version (Snapshot Revert).
> *   **Customers** never notice delays.

---

## 🔗 Related Documents
*   [Atlassian Multi-Tenancy at Scale](atlassian-scale.md) — Database-level multi-tenancy with TiDB