Resoruce: https://youtu.be/jTNeooqyTnc


Based on the transcript of the video "Divide and Conquer: Multi-tenancy in Postgres," presented by Karen Jex at Citus Con 2023, here is a comprehensive extraction of the presentation from start to end.

### **Introduction**
Karen Jex, a Senior Solutions Architect at Crunchy Data (formerly a DBA and database consultant), introduces the topic of multi-tenancy in Postgres. She defines multi-tenancy as hosting one or more database applications or users—referred to as tenants—on a single Virtual Machine (VM), server, or Postgres cluster.

**Why Multi-tenancy Matters:**
Most organizations no longer possess just a single Postgres database or application. While Jex started her career in a simple environment managing two isolated applications, modern environments involve managing multiple databases and applications, each with internal or external users. Consequently, DBAs must consider multi-tenancy because managing an individual Postgres database or cluster for every single user is often too expensive and complicated.

### **The Scenario: "Hare for Cake" Bakery**
To illustrate the concepts, Jex uses a bakery analogy. You are cast as the DBA for "Hare for Cake," a popular bakery growing rapidly from a one-person operation to a franchise model across Europe.
*   **The Requirement:** Each franchise needs to manage its own data, but the head office requires central access for reporting.
*   **The Goal:** You have a data model and know you will use Postgres, but you must decide largely on the physical architecture: how many clusters, databases, or schemas are needed.
*   **Initial State:** A single host (`hfcvm`), a single cluster (`hfc cluster`), and a single database (`hfcdb`) containing the tables.
*   **The Challenge:** How to adapt this architecture for multiple franchises (e.g., London, Paris, Berlin) or eventually hundreds/thousands of franchises for "world domination".

### **Selecting an Architecture**
There is no single "right" architecture; the choice depends on balancing conflicting requirements:
*   **Performance:** Does one tenant impact others?
*   **Isolation:** Do tenants have interdependence, or must they be completely independent?
*   **Cost:** Licensing, hardware, and personnel costs.
*   **High Availability:** Do maintenance windows and availability requirements differ per tenant?
*   **Manageability:** Centralized vs. decentralized backup/restore and management.
*   **Customer Confidence:** Meeting specific customer architectural demands.

### **The Cake Analogy for Postgres Layers**
Jex maps bakery items to Postgres infrastructure:
*   **Tray:** VM or Server.
*   **Plate:** Postgres Cluster.
*   **Cake:** Database.
*   **Layers:** Schemas.
*   **Slices:** Tables.

This analogy is used to explore specific architecture options:

#### **1. One Host Per Tenant (One tray, one plate, one cake per customer)**
Each tenant (franchise) has its own VM, cluster, schema, and tables.
*   **Pros:** Maximum flexibility and separation. You can customize OS and Postgres parameters per tenant. Upgrades, backups, and restores are performed individually. Performance of one tenant does not impact others. It allows for geographical distribution.
*   **Cons:** Global reporting is difficult (requires Foreign Data Wrappers). Managing shared reference data is difficult (requires Logical Replication). High overheads for setting up new VMs, monitoring, and maintenance for every new franchise.
*   **Use Case:** High isolation requirements, no shared data.

#### **2. Partitioning (One tray, single layered cake)**
A single VM, single cluster, single database, and single schema where tables are partitioned by tenant (franchise ID).
*   **Implementation:** Requires adding a franchise ID to tables and partitioning them. Shared reference tables remain non-partitioned.
*   **Security:** To ensure tenants only see their own data, **Row Level Security (RLS)** is enabled. Security policies are created to allow franchises to see their own data while allowing head office to see all data.
*   **Pros:** Easy to share reference data. Easy global reporting (select from the whole table). Lower overheads (one server to manage). Reduced maintenance/monitoring.
*   **Cons:** Reduced flexibility (parameters affect everyone). Reduced separation (upgrades and backups affect everyone). "Noisy neighbor" risk where one tenant's heavy usage impacts others.
*   **Use Case:** Centralized management, global reporting required, small number of tenants (to avoid excessive partition counts).

#### **3. Intermediate Options**
Between the two extremes, Jex outlines other configurations:

*   **One VM, Multiple Clusters (One tray, separate plates):** Hosting distinct clusters (e.g., London, Paris) on one VM. Each must have a unique name and listen on a different port.
*   **One Database Per Tenant (One tray, one plate, multiple cakes):** A single cluster containing distinct databases for each tenant.
    *   **Verdict:** Jex calls this "the worst of both worlds." Backups and parameters are shared (because it's one cluster), but global reporting and shared data are difficult (because they are separate databases).
*   **One Schema Per Tenant (Multi-tiered cake):** Single server/cluster/database, but a distinct schema for each tenant.
*   **One Set of Tables Per Franchise (Slices):** Similar to schemas, but involves renaming tables within the same namespace to avoid clashes. Requires application changes to access the correct tables.

#### **4. Sharding (Separating layers to different places)**
An extension of partitioning where partitions reside on different clusters.
*   **Architecture:** A control VM (coordinator) and separate VMs for tenants.
*   **Implementation:** Postgres does not natively support sharding yet. "Bake it yourself" sharding is complex and risky. It is recommended to use an extension like **Citus** to handle the heavy lifting.
*   **Pros:** Geographical distribution, central management, and scalability.

#### **5. Containerization**
Using Kubernetes and Postgres operators to implement containerized databases, which can be applied to these architectures.

### **Decision Framework and Conclusion**
Jex presents a comparison using a "cake scale" (from one cupcake = low to four cupcakes = high) to help choose the right path.

*   **Shared Reference Data/Reporting:** Best achieved with Schema per Tenant or Partitioning.
*   **Geographical Distribution:** Requires One VM per Tenant or Sharding.
*   **Isolation:** Highest with One VM per Tenant.
*   **Central Management:** Easiest with Partitioning or Schema per Tenant.
*   **Flexibility:** Highest with One VM per Tenant.

**Key Principle:** Keep it simple. Complexity introduces problems, so choose the simplest architecture that meets the requirements.

**Final Decision for "Hare for Cake":**
In the role of the DBA for the bakery:
*   You have a small number of tenants (three franchises).
*   Everything is managed centrally.
*   You have shared reference data and need global reporting.
*   There are no specific privacy or performance concerns requiring geographical distribution.

**The Verdict:** You decide to "bake a layered cake." You will implement a **single database with partitioned tables and Row Level Security** to ensure data isolation while enabling reporting.