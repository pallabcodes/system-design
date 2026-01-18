# GIS (Geospatial Information Systems): The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: PostGIS, S2 Geometry, R-Trees, and Location Queries at Scale.

> [!IMPORTANT]
> **The Principal Rule**: Never query `WHERE lat BETWEEN X AND Y AND lon BETWEEN A AND B`. It's a **Cartesian product**. Use **Spatial Indexes**.
> **The Goal**: "Find all drivers within 5km of me" in <10ms.

---

## 🎯 When Exactly GIS?

| Use Case | Technology | Notes |
| :--- | :--- | :--- |
| **"Nearby" Queries** (Uber, DoorDash) | PostGIS / S2 | Polygon containment, distance. |
| **Real-Time Tracking** (Million Moving Points) | Redis + Geohash / S2 | In-memory, fast updates. |
| **Geofencing** (Alerts when entering zone) | Tile38 / PostGIS | Stream processing with geo triggers. |
| **Mapping / Rendering** | Mapbox / Google Maps API | Vector tiles, styling. |

---

## 🧠 God Mode: Spatial Indexing

### 1. R-Trees (PostGIS Default)
*   **Structure**: A tree where each node is a **Bounding Box**.
*   **Advantage**: Good for polygons, complex shapes.
*   **Disadvantage**: Poor for high-write-rate data (rebalancing).

### 2. Geohash (Simple but Limited)
*   **Structure**: Encodes Lat/Lon into a **Base32 String** (`u4pruydqqvj`).
*   **Advantage**: Simple prefix query. Points in the same cell share prefix.
*   **Disadvantage**: **Edge Cases**. Two points 1 meter apart can have completely different prefixes if they are on opposite sides of a cell boundary.

### 3. Google S2 Geometry (The Gold Standard)
> **Research Paper**: *"S2 Geometry"* (Google).

*   **Structure**: Maps the 2D sphere onto a **1D Hilbert Curve**.
*   **Advantage**:
    *   **Locality Preserved**: Nearby points have nearby Cell IDs.
    *   **Hierarchical**: Level 0 = Face of Cube. Level 30 = cm².
    *   **No Edge Cases**: Unlike Geohash, S2 Cells cover the globe uniformly.
*   **Use**: Uber, Google Maps, Pokemon GO.

```mermaid
graph TD
    subgraph "S2 Geometry"
        Earth[2D Sphere] -->|Project| Cube[6-Faced Cube]
        Cube -->|Hilbert Curve| Line[1D Integer (Cell ID)]
        Line -->|Prefix Scan| Index[Database Index]
    end
    
    Query["Find Points Near (40.7, -74.0)"] --> S2Lib[S2 Library]
    S2Lib -->|Covering| CellIDs["Cell IDs: 0x487a..., 0x487b..."]
    CellIDs --> Index
```

---

## 🏗️ Technology Comparison

| Tech | Type | Best For | Scalability |
| :--- | :--- | :--- | :--- |
| **PostGIS** | Extension to Postgres | Complex queries (ST_Intersects, ST_DWithin) | Vertical (Read Replicas) |
| **Redis + Geohash** | In-Memory Cache | Real-time proximity (GEORADIUS) | Cluster Mode |
| **Tile38** | Geospatial DB | Geofencing, Webhooks | Single Node |
| **S2 + DynamoDB/Cassandra** | DIY | Massive scale, write-heavy | Infinite (Partition by Cell ID) |

---

## 🔧 PostGIS Cheat Sheet

```sql
-- Enable PostGIS
CREATE EXTENSION postgis;

-- Create a table with a geography column
CREATE TABLE drivers (
    id SERIAL PRIMARY KEY,
    name TEXT,
    location GEOGRAPHY(Point, 4326) -- SRID 4326 = WGS84 (GPS)
);

-- Insert a point
INSERT INTO drivers (name, location)
VALUES ('Driver A', ST_SetSRID(ST_MakePoint(-73.9857, 40.7484), 4326)); -- NYC

-- Create a Spatial Index (GIST)
CREATE INDEX idx_drivers_location ON drivers USING GIST (location);

-- Find drivers within 5km
SELECT name, ST_Distance(location, ST_MakePoint(-73.99, 40.75)::geography) AS distance_meters
FROM drivers
WHERE ST_DWithin(location, ST_MakePoint(-73.99, 40.75)::geography, 5000) -- 5000 meters
ORDER BY distance_meters;
```

---

## ✅ Principal Architect Checklist

1.  **Use Geography, Not Geometry**: `GEOGRAPHY` type calculates distance on a sphere (Earth). `GEOMETRY` is for flat projections.
2.  **Shard by Cell ID**: For massive scale (Uber), use S2 Cell ID as the Partition Key.
3.  **Avoid `ST_Distance` in WHERE**: Use `ST_DWithin` which leverages the index. `ST_Distance` is computed for every row.
4.  **H3 for Analytics**: Uber's H3 is optimized for hexagonal tiling (better for heatmaps than S2's squares).

---

## 🔗 Related Documents
*   [Sharding Architecture](../sharding-techniques-and-notes/sharding-architecture-guide.md) — Partitioning by geography.
*   [NoSQL Guide](./nosql-architecture-guide.md) — DynamoDB with S2 for geo queries.
