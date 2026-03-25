Resource: https://youtu.be/QigsygqPXWk


Based on the transcript of the presentation by a representative from Fujitsu Australia, here is an accurate and comprehensive extraction of the discussion regarding multi-tenancy in PostgreSQL, from start to end.

### **Introduction and Motivation**
The speaker, who has ten years of experience with PostgreSQL doing development and DBA work, introduces the topic of achieving multi-tenancy in PostgreSQL—what is currently available and what is needed for the future.

**Drivers for Multi-tenancy:**
*   **Hardware Consolidation:** There is a trend toward building bigger hardware and appliances. Customers appreciate the plug-and-play simplicity and productivity gains of appliances. To justify the hardware, users want to put more instances onto the machine and have them play nicely together, sharing resources.
*   **Cloud Solutions:** While some move to virtualization, there is a need for Database-as-a-Service solutions (private clouds) that require efficiency at the database level.

**Key Requirements:**
When looking for multi-tenancy, users look for three main things:
1.  **Security:** Specifically data and resource isolation. Users must be separate and unaware of other users on the same instance.
2.  **Optimal Resource Utilization:** The system must deliver services efficiently without instances competing destructively. It allows for purchasing a system and using the resources without waste.
3.  **Application Transparency:** Applications should not need to know if they are connecting to a single instance or a cluster with thousands of databases; the connection endpoint should remain standard.

### **Use Cases**
*   **Uniform Platforms:** There is a desire for parity between cloud and on-premise environments (similar to Oracle’s approach with OpenStack in both their cloud and Exadata appliances). Customers want a uniform experience so staff do not need different skill sets for cloud vs. on-premise management.
*   **Generic Infrastructure:** Users want to integrate easily with other infrastructure pieces like backup, storage, and authentication, which must work seamlessly in a multi-tenant environment.

### **Defining Multi-tenancy**
The speaker outlines three definitions of multi-tenancy, ranging from workarounds to niche requirements:
1.  **Multiple Instances:** Running multiple PostgreSQL instances on a single piece of hardware. This is a workaround to achieve resource sharing.
2.  **Self-Contained Databases:** A single instance containing multiple databases where users within one database cannot see shared catalogs or other databases. This is the definition most people consider "multi-tenant".
3.  **One Database, Multiple Customers:** A single gigantic database instance where tables are shared across customers using row-level security (e.g., database.com). This is a niche requirement for 99% of users.

### **Resource Management Challenges**
Even if running multiple instances on one hardware is possible, controlling resource consumption is difficult.
*   **SLAs:** In cloud environments, providers need to define Service Level Agreements (SLAs) for minimum guaranteed resources (CPU, memory) and maximum limits to prevent hogging.
*   **Resource Sharing:** Ideally, a hybrid situation is desired where if resources are idle, they can be allocated to others temporarily.
*   **The Virtualization View:** In a virtualized environment (e.g., 3 VMs on one hardware), load peaks often differ. Combining them into a multi-tenant environment allows better utilization of idle resources compared to porting or managing failover for multiple VMs.

### **Current Solutions and Limitations**
**PostgreSQL Capabilities:**
You can already utilize separate instances, separate databases, or separate schemas to isolate data. However, these methods share hardware resources and compete with one another. While schemas offer isolation, they come with high maintenance overhead (e.g., no automatic user creation for schemas).

**cgroups (Linux Control Groups):**
This Linux kernel feature allows grouping resources (CPU, memory, I/O) and assigning processes to them.
*   **Pros:** You can define a process that will start in the future and assign it to a group. It works well for managing multiple instances.
*   **Cons:** It is process-based, not user-based. Ideally, limits should be applied based on the *database user*. Currently, all client connections translate to Postgres processes, but cgroups cannot easily distinguish which database user owns a specific process connection.
*   **Discussion:** There is a desire to control these limits via database objects so that administration is contained within the database logic rather than the OS kernel.

### **Proposed Solution: Database-Specific Users**
The speaker proposes creating users scoped to specific databases rather than the cluster.
*   **Concept:** Roles could be "Cluster-wide" (connect to any DB) or "Database-wide" (connect only to specific DB). Database-specific users cannot see data or catalogs not belonging to their instance.
*   **The Shared Catalog Problem:** A major challenge is how to treat shared system catalogs.
    *   **Row-Level Security (RLS) on Catalogs:** One idea is to extend RLS (introduced in 9.5) to system tables. Policies could filter objects based on OIDs or User IDs so users only see their relevant objects.
    *   **Implementation:** This could be done at `initdb` time to set policies. This avoids overhead for users who don't want these limitations.
*   **Superuser Challenges:** Defining a "Database Superuser" is tricky. They need privileges to create users and objects within their database without having cluster-wide superuser authority.
    *   **Specific Issues:** Handling `CREATE EXTENSION` (whitelisting scripts to run as superuser) and dropping users/databases that own objects (cascading drops).

### **Internal Instance Architecture**
The grand design goal is to run a single PostgreSQL process/instance that is internally multi-tenant.
*   **Efficiency:** Instead of running thousands of instances (which wastes memory and processes), a single instance manages resources internally. It can allocate idle CPU/memory to tenants who need it but restrict them once they reach their defined limits.
*   **Prioritization:** A difficulty lies in defining which pages or resources are "more important" than others when resources are contended.

### **Storage Limits**
The speaker addresses limiting storage per tenant.
*   **Constraint:** You cannot limit the whole instance size (it needs to write WAL logs), but you want to limit the data in a tablespace.
*   **Implementation:** This can be done via cgroups externally or internally in Postgres.
*   **Challenges:**
    *   What happens when the limit is reached? (Warning? Spillover?)
    *   Expanding storage (e.g., creating a new tablespace and moving data) is difficult without locking the database.
    *   Monitoring: Who watches the limits? Do we need a daemon to wake up and check usage?.

### **Migration and Upgrades**
*   **Migration:** Logical replication is useful for moving tenants to different tablespaces or databases, though handling the initial data snapshot and freezing changes during the move remains a challenge.
*   **Rolling Upgrades:** Users want appliances that support rolling upgrades without downtime.
    *   **Mechanism:** Using tools like PgBouncer or proprietary appliance features to hold connections (queuing them) while switching the backend to a standby node that has been upgraded. This prevents applications from being disconnected during maintenance.