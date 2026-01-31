


Based on the provided transcript, here is an accurate and comprehensive extraction of the presentation "Uber Marketplace: Location Serving & Storage in the Uber Marketplace" by Archit Khode from the Marketplace Locations team at Uber.

### Introduction and Motivation
The presentation focuses on the indexing, serving, and storage systems Uber built to process location points (latitude and longitude coordinates). To motivate the need for these systems, the speaker walks through the lifecycle of a typical Uber trip:

1.  **Opening the App:** Users see available cars moving on the map. This live view requires tracking cars and knowing specific details, such as which side of the road they are on and their direction. Directionality is crucial for calculating accurate Estimated Time of Arrival (ETA); a car facing the wrong way may take minutes longer to arrive.
2.  **Dispatching:** When a user requests a ride, the system must determine the best car to dispatch. This requires a system capable of storing all car locations and quickly indexing them to answer queries, such as finding available vehicles within a specific radius of a pickup point.
3.  ** The Trip:** Once a match occurs, the trip begins. The system must track "route trip points" (latitude, longitude, and timestamp) as the driver travels to the pickup and destination. This data is visualized for the user at the end of the ride and is essential for calculating the fare based on time and distance.

### Data Types and Terminology
Uber collects data from the GPS sensors on both rider and driver phones. The presentation focuses on driver data. Two key concepts are defined:
*   **Location Point:** A car's position at a specific instance (latitude and longitude).
*   **Location Time Series:** A set of location points tracking an entity over time.

**Map Matching:** Raw GPS sensor data is often noisy, misses points due to poor signal, or places cars off-road. The system uses "map matching" to transform raw, noisy GPS signals into a clean path snapped to actual roads.

The infrastructure is divided into two primary systems: **Location Indexing** (finding current cars) and **Location Storage** (storing historical time series).

---

### System 1: Location Indexing (GeoBase)

**Requirements**
The indexing system must:
1.  Know the *current* location of all cars.
2.  Provide fast query responses, as the system is hit every time an app opens or a ride is requested.
3.  Filter by properties beyond location, such as vehicle status (on-trip vs. available), seat count (crucial for Uber Pool), or destination.
4.  Handle high volumes of both write traffic (driver updates) and read traffic (user queries).
5.  Store data in an ephemeral manner (long-term durability is not required for current locations).

These requirements led to the creation of an **in-memory search index called GeoBase**.

**Architecture**
*   **Single Worker Functionality:** A single GeoBase worker stores driver objects in memory. It handles **Update** operations (updating a driver's location and properties) and **Query** operations (finding drivers within a radius of a center point, filtered by criteria like "on trip" or "seats available").
*   **Distributed Coordination (Ringpop):** GeoBase uses an internal library called **Ringpop**. This is a coordination library that allows workers to gossip messages and discover each other. It enables the distribution of the application across multiple workers.

**Sharding Strategies**
To split data across hosts, Uber explored several strategies:
1.  **City Sharding:** Assigning specific workers to specific cities (e.g., SF vs. NY). This was used in early versions but has limitations.
2.  **Geo/Map Sharding:** Splitting the map into arbitrary polygons or grids.
3.  **Product Sharding (Selected Approach):** The system splits data by product type (e.g., UberX, Uber Pool). This is effective because products naturally provide geographic separation. Queries use simple Haversine distance calculations to filter cars by location within these product shards.

**Scaling Challenges**
The system faces challenges related to Index Size ($K$) and Traffic Volume ($Q$ or QPS). Both dimensions vary greatly over time and location, leading to "hot spots" where one worker becomes a bottleneck.

**Solutions for Scaling:**
1.  **Partitioning:** Large indexes are split into smaller pieces.
2.  **Replication:** Indexes are replicated across multiple hosts to split read traffic.
3.  **The Controller:** An external agent called "Controller" monitors the stats ($K$ and $Q$) of all GeoBase shards. It periodically reassigns partitions and replicas to handle spikes, such as those occurring on New Year's Eve, automating the re-partitioning process.

---

### System 2: Location Storage (Location Store)

**Requirements**
Like the indexing system, the storage system must handle high write volumes. However, unlike indexing, it requires **durable storage** to maintain history (for fare calculation and trip history). It must support queries for a driver's location between specific timestamps ($T_1$ to $T_2$) and map-matched output.

**Architecture**
The system, named **Location Store**, ingests raw locations from apps.

1.  **Persistence Layer (Cassandra):**
    *   Uber uses Cassandra for durability and high availability.
    *   **Data Modeling:** Data is partitioned by **Driver ID** and a **Time Bucket**. Within a partition, writes are ordered by timestamp. This design minimizes the number of nodes (tablets) required to read a full trip request.
    *   **Write Replication:** To ensure availability, Cassandra clusters exist in multiple data centers. Writes are forwarded from one data center to another to ensure data survives even if a cluster goes down.

2.  **Read Optimization (Redis):**
    *   Because Cassandra is optimized for writes, Uber adds a **Redis** caching layer on top to handle read traffic.
    *   Most reads are for the most recent trip data (last few minutes). This data is cached in Redis, shedding the read load from Cassandra.

3.  **Map Matching Integration:**
    *   To provide map-fitted paths, the system buffers raw points in Redis to build sufficient context (it is difficult to match a single point without knowing the trajectory).
    *   Periodically, map matching logic runs on the buffered data. The resulting map-matched locations are persisted in a separate schema within the Location Store.

**Summary**
The talk concludes by recapping that Uber uses a custom in-memory search index (GeoBase) for real-time indexing and a combination of Cassandra and Redis (Location Store) for durable time-series storage.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
Yes. **Ringpop** (the gossip scale-out library) was largely deprecated by Uber in favor of standard Service Mesh (Envoy) and more robust orchestration. Maintaining a custom "Distributed Hash Ring" library is less common today than using consistent hashing at the Load Balancer level.

**Is it scalable?**
**Yes**, putting the index in-memory (GeoBase) is still the way to go for high QPS.

**What would the architecture look like today?**
1.  **H3:** Uber open-sourced **H3** (Hexagonal Hierarchical Spatial Index). Today, we would use H3 for the sharding and indexing logic natively.
2.  **Redis Geospatial:** We might just use **Redis 6+** which has built-in Geo commands (based on H3/Geohash) if the scale fits in RAM, avoiding a custom C++ service.
3.  **Tile38:** We might use an off-the-shelf Geo-fence server like **Tile38** instead of building GeoBase from scratch.
