Resource: https://youtu.be/jzn-Q0n-8_w?list=TLGGNTFJUCDbAkQxNTAyMjAyNg


Based on the transcript of the presentation by Sehrope Sarkuni at PGConf NYC 2021, here is an accurate and comprehensive extraction of the content regarding advanced Postgres schema design.

### **Introduction and Philosophy**
Sehrope Sarkuni, founder of JackDB and maintainer of several Postgres drivers (Java, Node.js), introduces the talk on designing smarter, scalable schemas. He highlights the relationship between data structures and code:
*   **Smart vs. Dumb:** Smart data structures make code straightforward. Conversely, "dumb schemas require really smart code," whereas smart schemas prevent "dumb code" (developers unintentionally doing the wrong thing).
*   **The Database Environment:** Unlike a single app, a database is a concurrent system accessed by various sources (reporting systems, OLTP systems, new and old application versions).
*   **Schema as API:** The schema dictates what you *can* do (permissions, reading, writing) and what you *cannot* do. The "cannot do" aspect is crucial for preventing invalid states (e.g., negative balances) regardless of who or what is accessing the data.

**Design Priorities:**
When designing a schema, the priority hierarchy should be:
1.  **Consistency:** The absolute most important factor. Data must be valid and not lost.
2.  **Efficiency:** If data cannot be accessed in a reasonable time (e.g., querying a billion rows takes 6 hours), it is effectively useless.
3.  **Simplicity:** Desirable to avoid edge cases and aid onboarding, but less important than consistency and efficiency.

### **Data Types and Storage Efficiency**
The design begins at the column level. Postgres is strongly typed, offering specific types (integers of various bytes, timestamps, UUIDs, Booleans, etc.) rather than generic ones.
*   **The Fishbowl Metaphor:** Sarkuni uses an image of fish in bowls to illustrate that smaller data types allow you to fit "more fish" (data) into memory and disk.
*   **UUID vs. Text:** Storing UUIDs as text is inefficient (36 characters + overhead) compared to the native `uuid` type (16 bytes). The native type is smaller, faster, and ensures correctness (validating the 16-byte structure), whereas text fields allow invalid data insertion.

**Column Alignment (Padding):**
Similar to C structs, Postgres aligns columns based on their size (e.g., an 8-byte integer requires 8-byte alignment).
*   **The Problem:** Placing a 1-byte Boolean followed by an 8-byte BigInt results in 7 bytes of empty padding. Repeating this pattern creates significant wasted space.
*   **The Solution:** Order columns from **biggest to smallest**. This naturally aligns fields and eliminates unnecessary padding. It also allows adding new small columns later without increasing row size if they fit into existing alignment gaps.

### **Constraints and Validation**
**Check Constraints:**
These are the building blocks of validation.
*   **Regex:** You can use regular expressions to validate patterns (e.g., ensuring a username matches a specific format).
*   **Descriptive Naming:** Sarkuni advises against generic constraint names (e.g., `ck12345`). Using descriptive names (e.g., `person_check_username_pattern`) helps developers immediately understand what went wrong when an error occurs.
*   **Multi-Column Constraints:** Constraints can define relationships between columns in the same row (e.g., a widget must have a manager, which can be a person OR a group, but not both).

**Arrays:**
Postgres supports arrays for every data type. While powerful, they should not be the default choice over normalized tables.
*   **Issues:** Postgres arrays have no dimension limits (a text array can handle multi-dimensional matrices), no ordering enforcement, and no uniqueness enforcement.
*   **Advanced Constraints:** You can use immutable functions inside check constraints to enforce array hygiene.
    *   *Example:* Define a function `array_sort` that un-nests and re-aggregates an array. Use a check constraint (`CHECK array = array_sort(array)`) to ensure data is always stored sorted.
    *   *Uniqueness:* A similar approach (`select distinct`) can enforce that an array contains no duplicates.

### **Migrations and Schema Evolution**
**Flex Fields vs. Migrations:**
Sarkuni criticizes "Flex Fields" (adding generic columns like `flex1`, `flex2` to avoid schema changes). Schema migration is unavoidable if the application evolves.
*   **The Diode Analogy:** Database migrations are unidirectional (forward only). You don't "revert" a database; you move forward to a state where the change is undone.
*   **Testing Migrations:** Postgres allows cloning databases instantly using `CREATE DATABASE ... TEMPLATE`. Developers can clone a local DB, run migrations, and if they fail, drop and re-clone instantly for rapid iteration.

**Locking Management:**
Migrations must be planned based on locking impact:
*   **Zero/Low Impact:** Creating tables/types, adding data.
*   **Short Locks:** `CREATE INDEX CONCURRENTLY`, adding columns *without* defaults.
*   **Long Locks (The Danger Zone):** Standard `CREATE INDEX`, modifying views, or adding columns *with* defaults (which forces a table rewrite). These must be broken down or handled carefully to avoid downtime.

### **Access Patterns and Indexes**
**Access Categories:**
1.  **Small/Consistent:** Single row lookups (fast).
2.  **Known/Small:** Recent items, pagination (predictable).
3.  **Known/Big:** Data exports (predictable but heavy).
4.  **Unknown:** Ad-hoc reporting. This should be isolated (e.g., via replication) because you cannot optimize for every possible query.

**Advanced Indexing:**
Indexes are redundant data maintained by Postgres to speed up lookups.
*   **Partial Indexes:** Index only a subset of data (e.g., `WHERE active = true`). This reduces index size and increases speed.
*   **Include Clause:** Adds extra payload columns to the index (not part of the B-Tree key) to enable index-only scans without visiting the heap.
*   **Expression Indexes:** Index the result of a function, such as `lower(name)`. This allows case-insensitive searches to be backed by a specific structure.
*   **Combinations:** You can combine these (e.g., a unique index on `lower(name)` only for `active` rows) to enforce complex invariants.

### **Views and Functions**
*   **Views:** Good for hiding query complexity (e.g., joining tables).
*   **Set Returning Functions:** Described as a "strict superset of views." They can accept parameters (e.g., `accessible_product(person_id)`). This allows embedding complex security/access logic into a function that looks like a table to the query planner, which can then optimize it inline with other filters.

### **The Hotel Room Problem (Range Types)**
Sarkuni presents the "Hotel Room Problem" (preventing double-booking) as an example of Postgres's power.
*   **Traditional Failures:** Using start/end dates and application logic requires locking tables or risking race conditions where two people book the same slot.
*   **Postgres Solution:** Use **Range Types** (e.g., `daterange`) combined with an **Exclusion Constraint**.
*   **Implementation:** You create a constraint that excludes rows where the `room_id` matches AND the `booking_dates` overlap (`&&` operator). This solves the problem entirely within the database schema with no complex application locking required.

### **Q&A**
*   **Missing Features:** Sarkuni wishes Postgres supported foreign keys that enforce relationships where two child tables share a parent via a third relationship without duplicating the parent ID.
*   **Business Logic Placement:** Invariants (constraints) *must* be in the database to guarantee consistency. Flow logic (how to insert) is often easier in the application, but the database is the final gatekeeper.


Q: How do range types solve the hotem room bokking problem?

Q: Explain why sorting columns from biggest to smallest optimizes storage.

Q: How can set returning functions act as advanced database views?