Resource: https://youtu.be/AguWva8P_DI

Based on the transcript provided, here is an accurate and comprehensive extraction of the presentation "Keynote: Twitter's search architecture" from start to end.

### Introduction and Scale
The speaker is **Michael Busch**, a German engineer living in San Francisco who has worked at Twitter for four years. The presentation covers Twitter's numbers, the evolution of its search engine, the high-level architecture, and deep technical details regarding modifications to Lucene.

**Twitter’s Scale:**
*   **Users:** More than 230 million monthly active users.
*   **Volume:** 500 million tweets sent daily. The platform has seen over 300 billion tweets since its founding in 2006.
*   **Records:** A world record of roughly 33,000 (or 143,000 depending on interpretation of the transcript's "30 3,000") tweets per second was achieved. Busch notes that in 2010, they were nervous about exceeding 1,000 tweets per second.
*   **Search Queries:** Over 2 billion queries per day, including API and user-entered queries.

### Evolution of Twitter Search
*   **2008:** Twitter acquired a startup called **Summize**, which had a real-time search implementation based on **MySQL**. It worked initially but failed to scale as tweet volume grew.
*   **2010:** Busch joined Twitter. They needed to replace the MySQL implementation with inverted indexes. They built a prototype based on **Lucene** with specific changes for real-time search. This project, code-named **Earlybird**, shipped in late 2010/early 2011 and provided orders of magnitude better performance.
*   **2011:** New features were launched, such as image and video search (Vine videos, etc.). They implemented index compression similar to modern Lucene and added **Relevance Search** (ranking tweets by importance rather than just time).
*   **2012–2013:** Launch of **Archive Search**. Previously, users could only search the last few days of tweets. The archive search allows searching all 300 billion tweets (e.g., historical events like the Hudson River plane landing). This utilizes vanilla, unmodified Lucene indexes.
*   **Recent:** They switched the Earlybird real-time index to a new posting format that supports all document types, moving the technology closer to being contributable back to the Lucene codebase.

### High-Level Search Architecture
**1. Ingestion Pipeline:**
*   A real-time stream of raw tweets enters an **Analyzer/Partitioner** component.
*   This component performs normalization, tokenization (analyzing), geocoding, and URL expansion.
*   The data is stored in **Thrift** objects (a data serialization format).
*   **Hash Partitioning:** Tweets are distributed into different partitions based on the Tweet ID modulo the number of partitions.

**2. Earlybird (Real-Time Indexer):**
*   This is the modified Lucene version.
*   **Key Difference:** Unlike Lucene's Near Real-Time (NRT) feature, Earlybird does **not** flush in-memory buffers to disk to make them searchable. Flushing requires reopening the index writer, which decreases throughput. Earlybird allows searching the in-memory buffer while simultaneously appending to it.
*   **Segment Layout:** Indexes are in-memory and hash-partitioned. Each index contains a fixed number of tweets (8 to 16 million). Indexes are replicated for redundancy and read scaling.
*   **Time Sorting:** Segments are sorted by time. The newest segments (top) are mutable and appended to. Older segments (bottom) are fixed/immutable. This acts as a sliding window cache.

**3. Archive Pipeline:**
*   Raw tweets stored in **HDFS** are processed by **MapReduce** jobs daily.
*   These jobs analyze text, aggregate metadata (retweets, favorites), and build **vanilla Lucene 4.4 indexes**.
*   These indexes are reverse-time sorted (new to old) to support early termination during search.
*   **Two Tiers:**
    *   **Tier 1 (Memory):** Holds the "best tweets" of all time (determined by engagement signals). High throughput.
    *   **Tier 2 (SSD):** Much bigger, stored on SSDs. Lower throughput (limited by IOPS), but used if the memory tier doesn't return enough results.

**4. The Blender:**
*   A Thrift aggregation service and workflow management system.
*   It receives search requests and orchestrates calls to various services (indexes, Geo service, User ID mapping, etc.).
*   It determines which services can be called in parallel versus serially.
*   It merges results, performs ranking/deduplication, and returns the response to the user.

**5. Updates:**
*   A separate pipeline handles updates (deletes, favorites).
*   Earlybird supports updating **Column Stride Fields** (similar to Lucene DocValues) in-place in memory, whereas standard Lucene would require merging segments.

### Technical Deep Dive: Inverted Indexes and Posting Lists
Busch explains the concept of an **inverted index**: A dictionary of unique terms points to **posting lists** (lists of document IDs where the term occurs).

**Compression Issues:**
*   Lucene uses **Delta Encoding** (storing the difference between document IDs) and **VInt** (Variable Integer) compression (using 1 to 5 bytes per number).
*   **Problem 1 (Direction):** VInt/Delta encoding requires reading from Old-to-New. Twitter needs **New-to-Old** (Reverse) reading for real-time relevance and early termination.
*   **Problem 2 (Concurrency):** Variable byte writes are not atomic in Java. Twitter's lock-free concurrency model requires atomic writes to prevent dirty reads.

**Earlybird’s Old Posting List Format:**
*   **Encoding:** Used a fixed 32-bit integer per posting.
    *   **24 bits:** Document ID (limiting segments to ~16.7 million docs).
    *   **8 bits:** Term position (for phrase queries). Sufficient for tweets which rarely exceed 255 tokens.
*   **Advantages:** Atomic writes, readable in reverse order, supports efficient skipping.
*   **Memory Storage:** Uses four levels of integer arrays (pools).
    *   Allocates "slices" of different sizes (2, 16, 128, 2048 integers) depending on term frequency.
    *   New terms start with a small slice (size 2). As frequency grows, larger slices are allocated on higher levels.
*   **Linking:** Pointers between slices are encoded within 32-bit integers (using bits for pool level, slice index, and offset). This creates a reverse linked list.

**Earlybird’s New Posting List Format:**
*   **Objectives:** Support 32-bit positions, payloads (metadata), term frequencies (TF), and large documents while maintaining concurrency and space efficiency.
*   **Solution:** Split data into **two separate streams**:
    1.  **DocID Stream:** Fixed-size integers (mostly DocIDs) similar to the old format.
    2.  **Position/Payload Stream:** Variable-length data.
*   **Linking (Skip Lists):** Instead of storing a pointer for every posting (which would double space usage), they embed a **Skip List** into the header of the slices in the DocID stream. Skip points contain pointers to the corresponding location in the Position/Payload stream.
*   **Slice IDs:** Used to calculate the length of a posting list at a specific point in time, enabling compatibility with Lucene's index reader semantics.
*   **Optimization (Inlining):** Since most tweets are short and terms often appear only once (TF=1), they "steal" one bit from the 8-bit section of the integer.
    *   If the bit is 0 (and TF=1 and position < 127), they inline the position directly into the remaining 7 bits. This avoids accessing the secondary data structure for 99% of cases in tweets.
*   **Result:** Supports full Lucene features (payloads, large docs) with performance and size almost identical to the highly optimized tweet-only format.

### Q&A Session Summary
*   **Why not use Vanilla Lucene NRT?** Lucene NRT flushes buffers to disk/RAM to make them searchable, which triggers merging and kills indexing throughput. Twitter completely decouples indexing and searching; their in-memory buffers are searchable without flushing.
*   **Handling large Doc Frequencies:** If a position is >127, they store 127 in the inline bits and the actual value in the secondary structure.
*   **Index Size:** The new format is roughly 30% larger than compressed Lucene segments, but the fair comparison is against unoptimized in-memory buffers.
*   **Contribution to Lucene:** Contributing back involves converting the custom in-memory format to standard Lucene segments upon flushing. The main blocker is their custom updatable DocValues implementation.
*   **Log Analysis Use Case:** Busch agrees this architecture is excellent for log analysis or any use case requiring high write throughput, high query volume, and low latency.
*   **Faceting:** Twitter does not have standard user-facing facets but uses facet-like technology internally (e.g., identifying "best photos" by faceting on photo IDs within search results).
*   **Caching:** They do not flush caches like Solr. They use **Partial Query Caching** (e.g., caching the result of a "no spam" filter) and Blender-level result caching.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
This is from 2013-2015. It is ancient in internet years. Twitter has rewritten its search stack multiple times (moving from Java to Scala, and adopting new frameworks).

**Is it scalable?**
**Yes**, but the "Custom Lucene" approach is extremely expensive to maintain.

**What would the architecture look like today?**
1.  **Elasticsearch / OpenSearch:** For 99% of companies, managing custom inverted indexes is madness. We would use **Elasticsearch** (which uses Lucene under the hood) but handles the replication/sharding for us.
2.  **ClickHouse:** For log analysis or high-ingest "search" (where we just need to filter by some tags), **ClickHouse** or **StarRocks** is often faster and cheaper than an Inverted Index because it uses columnar storage + vectorized execution.
3.  **Vector Search:** Modern search includes "Semantic Search" (Embeddings). We would add a **Vector Database** (e.g., **Milvus**, **Weaviate**, or Lucene's own KNN vectors) to the pipeline to find tweets by *meaning*, not just keywords.