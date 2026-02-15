Resource: https://youtu.be/MXkdJH_ztpA

Based on the transcript of the video ""Drop-in Replacement": Defining Compatibility for Postgres and MySQL Derivatives [FOSDEM 2026]," here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Speakers**
The session follows a previous talk on Postgres and MySQL, focusing specifically on the concept of "compatibility." Jimmy Angelakos speaks first regarding Postgres, followed by Daniel regarding MySQL families.

**Opening Remarks:**
*   The speakers aim to clarify "compatibility," a term currently used "semi-randomly" and decided more by marketing teams than by technical merit.
*   **Jimmy Angelakos:** Based in Edinburgh, he works for PG Edge. He is a long-time open-source contributor, the author of the book *PostgresQL Mistakes and How to Avoid Them*, and the maintainer of the Postgres extension `pg_stat_monitor`.
*   **Daniel:** Based in the Netherlands, he works for PingCAP on TiDB (a MySQL-compatible database). He has extensive experience running MySQL, contributes to the Wireshark project (MySQL protocol decoder), and was awarded the MySQL Rockstar Award in 2023.

### **The Landscape and Definition of Compatibility**
**Current State:**
*   Postgres and MySQL are the top two databases, leading many other systems to claim compatibility with them.
*   This leads to user confusion. For example, Amazon DocumentDB claiming Postgres compatibility despite being a non-relational database that lacks support for sequences, triggers, or views.
*   These claims dilute the brand and detract from the actual merits of the Postgres project.

**Defining Compatibility:**
*   Compatibility is not a binary "True/False" or absolute state.
*   Even within a single platform, versions are not fully compatible (e.g., Postgres 11 and 12 cannot talk to each other directly due to feature additions and removals).
*   **User Perspective:** Users care about practical questions:
    *   Will the application work?
    *   What drivers and APIs are needed?
    *   Can data be replicated in and out of the system?
    *   Is the cloud experience identical to bare metal installation?
    *   Can existing tools (backups, replication) be used?

### **Establishing the Postgres Standard (Jimmy Angelakos)**
The Postgres community held a working session at **PGConf.EU in Riga** to discuss establishing a practical framework for compatibility.

**The Framework:**
*   Instead of a pass/fail metric, the goal is a **checklist of features** weighted by importance.
*   The standard must account for **Managed Services** where users do not have superuser access or direct file system access.

**Specific Compatibility Criteria:**
1.  **No Silent Failures:** Commands must actually perform the requested action, not just be accepted syntactically (e.g., `CREATE INDEX`).
2.  **Implicit Behaviors:** Systems must support undocumented but understood behaviors, such as `INSERT INTO ... SELECT` guaranteeing ordering if the select is ordered.
3.  **Data Types & Dependencies:** Support for types like `JSONB` and Arrays is required. Features with dependencies must work (e.g., you cannot have Triggers without `PL/pgSQL`).
4.  **Transaction Isolation:** Must support the same isolation levels as Postgres.
5.  **Error Codes & Catalogs:** Consistency is required for monitoring tools that query the `PG_CATALOG`.
6.  **Identifier Limits:** If a compatible database supports identifiers longer than Postgres (e.g., 256,000 characters), it breaks compatibility because that data cannot be back-ported to standard Postgres.
7.  **Tooling:** Standard drivers and `pg_dump` must work.
8.  **Execution Plans:** They do not need to be identical, but they must function similarly (e.g., partition pruning must occur where expected).

**Replication and Recovery:**
*   Replication must be bi-directional and observable via standard views like `pg_stat_replication`.
*   Vendor extensions must not break replication to a vanilla Postgres node.
*   **Point-in-Time Recovery (PITR):** This is a key feature that typically requires access to Write-Ahead Logs (WAL).

**Testing:**
*   A test suite must reside outside the Postgres codebase.
*   Tests should target specific versions (e.g., "Compatible with Postgres 14").
*   Vendors must provide build targets for verification.

### **MySQL Compatibility Implementation (Daniel)**
Daniel discusses the practical implementation of compatibility using TiDB as a case study.

**The Protocol vs. The Backend:**
*   Implementing the network protocol is not enough. Daniel gives an example of a Go tool that speaks the MySQL protocol but does nothing in the backend; this does not make it "MySQL Compatible."
*   **Language Differences:** TiDB is written in Go (with Rust storage), while MySQL is C/C++. This makes exact replication of behavior difficult.

**Handling Syntax and Features:**
*   **Syntax Ignorance:** TiDB accepts `ENGINE=InnoDB` syntax but ignores it because that storage engine concept doesn't apply to their distributed system. This allows dumps to be loaded without errors.
*   **Feature Transparency:** Vendors must be open about what is *not* supported.
    *   TiDB supports Vector but does not support Geospatial or XML (noting that most users prefer JSON over XML).
*   **Extensions:** TiDB supports Sequences, a feature not in MySQL but present in MariaDB. They implemented it to not limit themselves, resulting in a "Frankenstein" solution that is still broadly compatible because the feature is optional.

**MariaDB vs. MySQL:**
*   MariaDB started as a drop-in replacement using the same codebase.
*   Over time, they diverged. MariaDB is no longer fully compatible; users must export/import data rather than swapping binaries.
*   **Divergent Implementations:**
    *   **JSON:** MariaDB implemented JSON as text with functions; MySQL used a binary JSON data type.
    *   **UUID:** MariaDB has a UUID data type; MySQL does not (it uses functions).

**Specific Incompatibilities in TiDB:**
*   **Connectors:** TiDB had to fork `Connector/J` for specific authentication mechanisms, though most customers use the vanilla version.
*   **Explain Plans:** TiDB decided **not** to be compatible with MySQL's explain output. Because TiDB is distributed, mimicking the MySQL format would hide critical information needed by DBAs.
*   **Error Codes:** They attempt to match MySQL error codes for the same situations. However, since they have no control over what codes MySQL might use in the future, avoiding conflicts for new, distributed-specific errors is difficult.

### **Conclusion**
The session concludes with the speakers noting there is no time for questions on stage, but they are available outside for further discussion.