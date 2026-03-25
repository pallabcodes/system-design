Resource: https://youtu.be/ykbYNBE-V3k?list=TLGGOG6lhQ8d_uYwMjAzMjAyNg

**Introduction and the Philosophy of Streaming Architectures**
Jeremy Taylor and Jon Pither, developers at a UK-based software company called JUXT ("jugs" in the transcript), begin by expressing their affinity for open source, simple tools, and the Clojure programming language. The presentation focuses on how to handle time within streaming architectures, leading to the introduction of their open-source database, **Crux**. 

They advocate for event-driven streaming architectures because they embody simplicity, a decoupled nature, and the UNIX philosophy of having lightweight components that do one thing well. They reference Martin Kleppmann's vision of an "unbundled database" where a Kafka event stream acts as the central nervous system of an enterprise; the canonical information lives in Kafka, and all other databases or applications are merely materialized views that can be rebuilt or replayed at will. 

**The Limitation of Logs and the Dual Nature of Time**
While event streams and logs are highly valued, the presenters emphasize that **"the log is not enough"**. A log is fundamentally just an append-only storage mechanism that primarily records **ingestion time** (the exact moment an event hits the log). However, raw facts on a log often lack full meaning until they are collated over time (e.g., aggregating individual stock trades to determine daily profit and loss). 

Furthermore, ingestion time is rarely the time that the business actually cares about. This introduces the concept of **bitemporality**, which defines time on two distinct axes:
1.  **Transaction Time:** This records when a fact is transacted onto the system's event log. It provides a strict, immutable audit log. Crucially, it guarantees **consistent queries**; if you query the system "as of" a specific point in transaction time, the results will never change because the past of the transaction log is immutable.
2.  **Valid Time:** This records when a fact is actually said to be *true* in the real world. For example, a trader might execute a paper trade that takes an hour to weave through the enterprise's systems before hitting the event stream. The trader needs to query the system based on when the trade actually happened (Valid Time), not when the system finally recorded it (Transaction Time). Valid time is fungible and forgiving, allowing users to insert delayed events retroactively into the valid time past.

Combining both axes allows developers to query a system as of a specific valid time, while anchoring the query to a specific transaction time to guarantee consistent, repeatable results.

**Historical Approaches to Bitemporality and Their Flaws**
Bitemporality is not a new concept; heavily regulated industries (like finance and insurance) have handcrafted solutions for decades by adding columns like "valid from" and "valid to" to relational tables without ever deleting rows. While the SQL standard added temporal support in 2011, implementations vary and remain complex. 

When attempting to add bitemporality to modern streaming architectures, developers typically try three approaches, the first two of which have major downsides:
1.  **Monolithic Databases:** Bringing in a heavy database like Oracle or Postgres with temporal support. **Downsides:** It requires expensive licensing, ongoing maintenance, and breaks the UNIX philosophy by introducing a massive "sledgehammer" component. Furthermore, if the monolith's query capabilities aren't sufficient, you might still need to introduce additional stores (like Elasticsearch), resulting in an ad-hoc, multi-database mess. 
2.  **Stream Processing Tools:** Utilizing tools like Kafka Streams, Flink, or Samza, which are optimized for high-throughput and complex event processing. They handle event ordering via **Windowing** (tumbling, sliding, etc.). **Downsides:** Windows are a mechanical approach designed for real-time firehoses, not generic historical querying. To use windows for deep bitemporal valid time, you have to create unlimited, infinitely open windows, which leads to severe performance problems.

**A Case Study in Unbundled Simplicity**
The presenters share a real-world case study from a high-throughput trading environment where traders desperately needed bitemporal querying, but the existing monolithic database was failing. Instead of buying a new monolith, the team built a simple, lightweight materialized view using **RocksDB** (a highly scalable key-value store built by Facebook). 

They created three basic indices:
*   **Index A:** Keyed by `[Entity ID + Valid Time]`, mapping to the trade data. This allowed queries by valid time. 
*   **Index B:** Keyed by `[Entity ID + Valid Time + Transaction Time]`. This allowed them to filter out any trades that were transacted *after* the supplied transaction time, ensuring query consistency.
*   **Index C:** An attribute-value index (e.g., `[Stock = IBM]`). This allowed them to find candidate trades, which were then cross-referenced against Index B for temporal correctness. 

They wrapped this simple Key-Value logic in a GraphQL API, providing the business with fast, scalable bitemporal queries directly off the event log without the overhead of a massive database.

**The Creation and Architecture of Crux**
The success of that simple RocksDB implementation seeded the creation of **Crux**, an open-source (MIT licensed) database tailored specifically for streaming architectures. Crux was built to provide four main features: Bitemporality, Eviction capabilities, Datalog queries (for graph algorithms), and a proper Database API feel. 

To operate, Crux relies on four core operations: **Put, Delete** (which retracts documents in valid time but preserves them in transaction time), **Evict**, and **Compare-and-Swap** (for transaction consistency). 

**Architecture and Eviction:**
Crux uses Kafka topics as its transaction log (acting as a write-ahead log). To solve the incredibly difficult problem of data eviction (e.g., GDPR compliance) in an immutable event stream, **Crux only stores the *hashes* of documents in the transaction log**. The transaction log is linearly ordered and never compacted. The actual document contents are stored in a separate document topic, which is mutable; when an eviction is requested, Crux places a tombstone in the document log, completely eradicating the data while leaving the transaction history intact.

**Pluggability and Performance:**
Crux is designed internally with Clojure protocols, making it highly pluggable. Users can swap out the underlying Key-Value store depending on their needs: **RocksDB** for high ingestion speeds, or **LMDB** for faster queries. Because it is extensible, community members have even swapped in **Exodus** (a JVM-only KV store) to run Crux seamlessly on Windows environments. 

To solve the performance degradation that typically occurs when scanning deep linear histories in Bitemporal databases, the team implemented **fractal Morton curves** (Z-order curves). This algorithm encodes the two-dimensional coordinates (Valid Time and Transaction Time) into a single index, ensuring point-in-time queries remain exceptionally snappy regardless of how much history the database holds.

**Console Demonstration**
The presenters demonstrate the new Crux console interface, which allows developers to interact with the database without needing to write Clojure. 
*   The UI displays attribute frequencies and cardinalities, which the Crux engine uses internally to optimize Datalog join orders.
*   They demonstrate preparing a transaction to ingest nested documents. The system returns a **Transaction ID**, which corresponds exactly to the underlying Kafka offset (or JDBC offset, as Crux also supports SQL backends like Postgres if Kafka isn't desired).
*   Using Datalog (which they describe as a pattern-matching language of "filling in the blanks"), they demonstrate querying the database to find specific stock tickers, view their complete valid time history, and execute complex joins with specific arguments (e.g., finding tickets priced between 10 and 60 within a specific market). 

**Future Roadmap**
The presenters conclude by outlining what is next for Crux:
*   **Streaming Queries:** They are integrating a Rust/Clojure dataflow project called `3DF` to enable streaming Datalog queries, pushing live database updates directly to browsers via WebSockets.
*   **Transaction Functions:** Validating capabilities to allow for complex schema enforcement and event-store projections directly within the database.
*   **Time-Series Capabilities:** Developing bitemporal range queries and columnar compression to better support time-series use cases.
*   **Broader API Support:** Adding SQL and JSON support to reach a wider audience beyond Datalog/Clojure users.
*   **Scaling:** Addressing the current limitation where all data must fit on a single node by researching adaptive indexing and sharding over time.