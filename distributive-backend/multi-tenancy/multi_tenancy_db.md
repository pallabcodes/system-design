Resource: https://youtu.be/4uxuPfSvTGU

Based on the video transcript, here is a comprehensive extraction of the presentation by Pierre Ducroquet on the good, bad, and ugly aspects of multi-tenant databases using PostgreSQL.

### **Introduction and Context**
Pierre Ducroquet, a developer and DBA with 10 years of experience, works for a French SaaS company (ENT). He shares "traps" he has encountered to help others avoid them.

He begins by illustrating the scale of his current production system:
*   **24,000 tables.**
*   **Almost 1 million indexes.**
*   He warns that while creating many tables might not pain developers, it causes significant issues for DBAs.

### **Defining Multi-Tenancy**
A multi-tenant system is a single instance running on a server shared by multiple groups of users (tenants).
*   **Ideal Scenario:** Each customer has a set of data (Tenant 1, Tenant 2) that is identical in structure but isolated for security.
*   **Reality:** Customers often use different features, meaning what works for one fails for another. Commercial teams often add new customers unpredictably, doubling database size overnight.

Pierre explicitly excludes **containers/Kubernetes** from this specific talk. Using one container per customer on a single server wastes CPU resources and would require double the hardware.

### **Approach 1: The "Tenant ID" Column**
This is the "natural way" most developers implement multi-tenancy: putting all data in one table with a `tenant_id` column.

*   **Security Risks:** You must trust that every single query in the application includes the `tenant_id` criteria.
*   **Optimizer Issues:** PostgreSQL statistics are global. With one huge table, the optimizer struggles to guess execution paths for specific tenants because the statistics don't cover specific tenant distributions well.
*   **Indexing Dilemma:**
    *   If you include `tenant_id` in every index, they become bloated.
    *   If you create specific indexes for big tenants, you have to manage them manually.
*   **Tooling Limitations:** Tools like `pg_profile` or `pg_stat_statements` do not log parameters. If a query is slow for only *one* customer out of 400, you cannot see why, because the query looks identical in the logs.
*   **The "Good":** Most standard PostgreSQL tools generally work fine because the table count remains low (1,000–10,000 tables).

### **Approach 2: Row Level Security (RLS)**
Pierre shares a "ridiculous" story where he used RLS as a security emergency fix because developers forgot `tenant_id` clauses, leading to data leaks.

*   **The Verdict:** "Don't even try that please." He calls it using a "bazooka to catch a fly".
*   **The Problems:**
    *   RLS is designed for high-security standards (PCI-DSS), not general multi-tenancy.
    *   It requires patching PostgreSQL functions to be usable.
    *   Backups may not restore properly.
    *   It ruins performance (detailed in Q&A).

### **Approach 3: One Database Per Tenant**
Pierre currently manages about 300 databases on his server.

*   **Pros:**
    *   **Security:** Security breaches must happen in the application before connecting to the database. Code paths are safer.
    *   **Indexing:** Easier because tables are small. You rarely need complex indexing.
    *   **Tools:** Most work fine with small databases.
*   **Cons (The "Ugly"):**
    *   **Connection Pooling:** This is the main pain point. `PgBouncer` is the only usable tool because of its "auto database" feature. However, you still end up with hundreds/thousands of connections to PostgreSQL.
    *   **Monitoring (Blindness):** `pg_stat_statements` is unusable. It has a memory limit (e.g., storing 10,000 queries). With 300,000 tables total, the stats are flushed instantly. The DBA is effectively blind to performance metrics.
    *   **Replication:** Logical replication is dangerous. It would require 300 decoders running simultaneously to parse the binary log, which burns CPU.

### **Approach 4: One Schema Per Tenant**
This involves one database where each customer gets their own schema.

*   **Security:** Better than a column approach. An attacker needs to inject a full query to access other data, not just change a parameter.
*   **Indexing:** Handles millions of indexes surprisingly well.
*   **Backup & Restore Failures:**
    *   **`pg_dump`:** The `-j` (concurrency) flag is broken for this use case. Creating tables actually takes longer than loading the data.
    *   **File System Limits:** Restoring creates hundreds of thousands of files. Just listing files (`ls`) in a folder with 400,000 files takes huge amounts of time and IOPS.
    *   **Solution:** `pgbackrest` with the "repo bundle" feature is the only tool that works effectively, as it groups small files into one compressed bundle.
*   **Monitoring:** `pg_stat_statements` fails here too. Unless developers use full table names (e.g., `SELECT * FROM tenant1.table`), the normalization process makes all queries look identical, hiding which tenant is responsible for the load.
*   **Connection Pooling Issues:**
    *   Using `search_path` to switch schemas is risky with transaction pooling.
    *   PostgreSQL does not notify the pooler when the `search_path` changes. This can lead to data leaks where a connection intended for Customer A still has Customer B's search path.
    *   **Fix:** Pierre had to write a one-line PostgreSQL extension to force notifications on search path changes.
*   **Visualization:** Monitoring graphs become unreadable with hundreds of lines for different customers.

### **Summary and Advice**
*   **Tenant ID Column:** A recipe for failure and potential legal/GDPR disasters.
*   **Recommendation:** Pierre uses a mix of "One Database per Tenant" and "One Schema per Tenant."
*   **Reality:** There is no perfect solution. You must test and be ready to fix the specific issues of your chosen method (e.g., patching `pg_dump` or connection poolers).

### **Q&A Session**
*   **On PostgreSQL 14/15 Public Schema Changes:** Pierre does not believe recent restrictions on the public schema will make developers or tools more aware of schemas. Most tools (built for MySQL/SQLite) ignore schemas entirely.
*   **On Row Level Security (RLS):**
    *   Functions used in RLS queries must be marked `leakproof`.
    *   Standard operators (like full text search) are not always leakproof.
    *   This forces filtering to happen *before* index usage, destroying performance.
*   **On Sharding (Splitting to new servers):**
    *   Pierre anticipates hitting a wall around 200,000 to 300,000 tables.
    *   Splitting servers requires complex application-side routing and increases human resource costs.
*   **On Autovacuum:**
    *   With millions of tables, `autovacuum` struggles.
    *   Configuration must be very aggressive. There are no good tutorials for this scale; it requires balancing I/O and bloat manually.