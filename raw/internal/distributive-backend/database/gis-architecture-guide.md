# GIS (Geospatial) Architecture: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: S2 Geometry, H3, PostGIS, R-Trees, Redis Geo — With Production DDL and Paper References

> [!CAUTION]
> **The Cardinal Sin**: `WHERE lat BETWEEN X AND Y AND lon BETWEEN A AND B`. This is a Cartesian product on a sphere. It's wrong, expensive, and will never use a spatial index.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [S2 Geometry Library](https://s2geometry.io/) | Google's spherical geometry, hierarchical cells |
| [H3: Uber's Hexagonal Hierarchical Index](https://eng.uber.com/h3/) | Hexagonal tiling for analytics |
| [PostGIS Manual](https://postgis.net/docs/) | PostgreSQL geospatial extension |

---

## 🎯 The Principal Laws of Geospatial

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Earth is Spherical** | Euclidean distance is wrong | Use haversine or geodesic calculations |
| **Law 2: Indexes are Everything** | Full-table scan on 1B points = death | R-Tree, S2 Cell, or H3 |
| **Law 3: Precision is Trade-off** | Higher precision = more cells = slower | Choose resolution for your use case |
| **Law 4: Coordinates are Lies** | GPS accuracy: 3-5m typical | Don't rely on cm precision |

---

# Part 1: Spatial Indexing Internals

## 🌲 R-Trees (Used in PostGIS)

### Structure
```
              ┌─────────────────────────────┐
              │    Root MBR (World)         │
              └─────────────┬───────────────┘
              ┌─────────────┴───────────────┐
              │                             │
     ┌────────┴─────────┐        ┌──────────┴───────┐
     │  MBR: North USA  │        │  MBR: Europe     │
     └────────┬─────────┘        └─────────┬────────┘
              │                            │
    ┌─────────┼─────────┐       ┌──────────┼────────┐
    │         │         │       │          │        │
  NYC LA   Chicago   Seattle  London   Paris   Berlin

MBR = Minimum Bounding Rectangle (Box containing all children)
```

### Query Algorithm
```python
def range_query(node, query_box):
    results = []
    for child in node.children:
        if intersects(child.mbr, query_box):
            if child.is_leaf:
                if intersects(child.geometry, query_box):
                    results.append(child)
            else:
                results.extend(range_query(child, query_box))
    return results

# Complexity: O(log N) for well-balanced tree
# Worst case: O(N) if boxes heavily overlap
```

### When R-Trees Struggle
```
High-velocity updates (Uber drivers moving every second):
- Each update changes the point's position
- Parent MBRs must be recalculated
- Can cause tree rebalancing
- Performance degrades

Solution: Use S2 Cells or H3 with simple B-Tree index
```

## 🌐 S2 Geometry (Google)

### Core Concepts
```
1. Earth → 6-faced cube (projection)
2. Each face → Hilbert curve (space-filling)
3. Hilbert curve → 1D integer (Cell ID)
4. Cell ID → 30 levels of hierarchy

Level 0:  Face (~10,000 km edge)
Level 12: City (~1-2 km edge)
Level 16: Block (~150 m edge)
Level 20: Building (~20 m edge)
Level 30: Millimeter (~1 cm edge)
```

### Cell ID Structure (64-bit integer)
```
Face (3 bits) | Position (61 bits)
─────────────────────────────────
001          | 0101010101...01   (Hilbert position at level)

- Prefix comparison = spatial containment
- Range scan = spatial query
- B-Tree index works perfectly!
```

### Python: S2 Cell Covering
```python
import s2sphere

def get_covering(lat, lng, radius_meters, max_cells=8):
    """Get S2 cells that cover a circle."""
    cap = s2sphere.Cap.from_axis_height(
        s2sphere.LatLng.from_degrees(lat, lng).to_point(),
        s2sphere.Cap.earth_radius_km() * radius_meters / 1000
    )
    
    coverer = s2sphere.RegionCoverer()
    coverer.min_level = 12
    coverer.max_level = 16
    coverer.max_cells = max_cells
    
    cover = coverer.get_covering(cap)
    return [cell.id() for cell in cover]

# Usage:
cells = get_covering(40.7128, -74.0060, 5000)  # NYC, 5km radius
# Returns: [9749618424903204864, 9749619524414832640, ...]

# Query:
# SELECT * FROM locations 
# WHERE s2_cell_id >= :cell1_min AND s2_cell_id <= :cell1_max
# UNION ALL
# SELECT * FROM locations 
# WHERE s2_cell_id >= :cell2_min AND s2_cell_id <= :cell2_max
```

### S2 + DynamoDB (Production Pattern)
```python
# Schema: Partition by S2 prefix, sort by full cell ID
# PK: S2_CELL_PREFIX#<level12_prefix>
# SK: S2_CELL#<full_cell_id>#<entity_id>

import s2sphere

def get_s2_keys(lat, lng):
    ll = s2sphere.LatLng.from_degrees(lat, lng)
    cell = s2sphere.CellId.from_lat_lng(ll).parent(12)  # Level 12 for partition
    full_cell = s2sphere.CellId.from_lat_lng(ll).parent(20)  # Level 20 for sort
    
    return {
        'PK': f'S2_CELL_PREFIX#{cell.id() >> 32}',  # High 32 bits
        'SK': f'S2_CELL#{full_cell.id()}#<entity_id>'
    }

def query_nearby(lat, lng, radius_m):
    cells = get_covering(lat, lng, radius_m, max_cells=8)
    
    results = []
    for cell_id in cells:
        cell = s2sphere.CellId(cell_id)
        prefix_cell = cell.parent(12)
        
        response = table.query(
            KeyConditionExpression=Key('PK').eq(f'S2_CELL_PREFIX#{prefix_cell.id() >> 32}')
            & Key('SK').between(
                f'S2_CELL#{cell.range_min().id()}',
                f'S2_CELL#{cell.range_max().id()}'
            )
        )
        results.extend(response['Items'])
    
    # Post-filter for exact distance
    return [r for r in results 
            if haversine(lat, lng, r['lat'], r['lng']) <= radius_m]
```

## ⬡ H3 (Uber's Hexagonal Index)

### Why Hexagons?
```
Squares: Neighbors are at 4 different distances (side vs corner)
         Corner neighbors: sqrt(2) * edge_length
         Side neighbors: edge_length

Hexagons: All 6 neighbors are equidistant
          Better for analytics (heat maps, clustering)
          No "corner problem"
```

### Resolution Levels
```
Res 0:  1,107 km edge (122 cells cover Earth)
Res 5:  8 km edge (~2M cells)
Res 9:  174 m edge (~569M cells)
Res 12: 9 m edge (~10B cells)
Res 15: 0.5 m edge (~180B cells)
```

### Python: H3 Usage
```python
import h3

# Get H3 index for a point
cell = h3.geo_to_h3(40.7128, -74.0060, resolution=9)
# Returns: '892a100d2c7ffff'

# Get all cells within radius
cells = h3.k_ring(cell, k=2)  # All cells within 2 hops
# Returns: {'892a100d2c7ffff', '892a100d2cfffff', ...}

# For k-ring at radius 2 and resolution 9:
# ~174m * 2 ≈ 350m radius

# Get hexagon boundary (for visualization)
boundary = h3.h3_to_geo_boundary(cell)
```

### H3 + PostgreSQL
```sql
-- Extension or custom function
CREATE EXTENSION h3;

-- Table with H3 index
CREATE TABLE locations (
    id UUID PRIMARY KEY,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    h3_res9 BIGINT GENERATED ALWAYS AS (h3_lat_lng_to_cell(lat, lng, 9)) STORED,
    h3_res6 BIGINT GENERATED ALWAYS AS (h3_lat_lng_to_cell(lat, lng, 6)) STORED
);

CREATE INDEX idx_locations_h3_res9 ON locations(h3_res9);
CREATE INDEX idx_locations_h3_res6 ON locations(h3_res6);

-- Query: Find locations in hexagons within 2 rings
WITH target_cells AS (
    SELECT unnest(h3_k_ring(h3_lat_lng_to_cell(40.7128, -74.0060, 9), 2)) AS cell
)
SELECT l.* 
FROM locations l
JOIN target_cells t ON l.h3_res9 = t.cell;
```

---

# Part 2: PostGIS Deep Dive

## 📐 Geometry vs Geography

| Type | Model | Distance Unit | Use Case |
| :--- | :--- | :--- | :--- |
| **GEOMETRY** | Flat plane | Same as input (degrees? meters?) | Small areas, projected coordinates |
| **GEOGRAPHY** | Spheroid | Meters (always) | Global, GPS coordinates |

```sql
-- DANGER: Geometry with lat/lng treats them as flat x/y
SELECT ST_Distance(
    ST_MakePoint(-122.4194, 37.7749),  -- SF
    ST_MakePoint(-73.9857, 40.7484)    -- NYC
);
-- Returns: 48.6 (degrees, meaningless!)

-- CORRECT: Geography calculates on spheroid
SELECT ST_Distance(
    ST_MakePoint(-122.4194, 37.7749)::geography,
    ST_MakePoint(-73.9857, 40.7484)::geography
);
-- Returns: 4,129,086 (meters, correct!)
```

## 🗺️ Production DDL: Driver Tracking

```sql
-- Create extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Drivers table with location
CREATE TABLE drivers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    vehicle_type TEXT NOT NULL,
    is_available BOOLEAN DEFAULT true,
    
    -- Location as geography (spheroid)
    location GEOGRAPHY(Point, 4326) NOT NULL,
    
    -- Heading (0-360 degrees)
    heading SMALLINT CHECK (heading >= 0 AND heading < 360),
    
    -- Last update time
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- GiST index for spatial queries
CREATE INDEX idx_drivers_location ON drivers USING GIST (location);

-- B-Tree for availability filtering
CREATE INDEX idx_drivers_available ON drivers(is_available) WHERE is_available = true;

-- Compound index for common query pattern
CREATE INDEX idx_drivers_available_location 
ON drivers USING GIST (location) WHERE is_available = true;

-- Function: Update driver location
CREATE OR REPLACE FUNCTION update_driver_location(
    p_driver_id UUID,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_heading SMALLINT
) RETURNS VOID AS $$
BEGIN
    UPDATE drivers
    SET location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        heading = p_heading,
        updated_at = NOW()
    WHERE id = p_driver_id;
END;
$$ LANGUAGE plpgsql;

-- Query: Find 10 nearest available drivers
SELECT 
    id,
    name,
    vehicle_type,
    ST_Distance(location, ST_MakePoint(-73.9857, 40.7484)::geography) AS distance_m
FROM drivers
WHERE is_available = true
  AND ST_DWithin(location, ST_MakePoint(-73.9857, 40.7484)::geography, 5000)  -- 5km radius
ORDER BY location <-> ST_MakePoint(-73.9857, 40.7484)::geography
LIMIT 10;

-- The <-> operator uses the GiST index for K-nearest-neighbor
```

## 🔷 Geofencing

```sql
-- Geofences table (zones)
CREATE TABLE geofences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    zone_type TEXT NOT NULL,  -- 'airport', 'surge_zone', 'restricted'
    
    -- Polygon boundary
    boundary GEOGRAPHY(Polygon, 4326) NOT NULL,
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_geofences_boundary ON geofences USING GIST (boundary);

-- Insert a geofence (Times Square)
INSERT INTO geofences (name, zone_type, boundary) VALUES (
    'Times Square',
    'surge_zone',
    ST_GeogFromText('POLYGON((-73.9876 40.7562, -73.9847 40.7562, -73.9847 40.7527, -73.9876 40.7527, -73.9876 40.7562))')
);

-- Check if point is inside any geofence
SELECT g.name, g.zone_type
FROM geofences g
WHERE ST_Intersects(
    g.boundary,
    ST_MakePoint(-73.9857, 40.7549)::geography
) AND g.is_active = true;

-- Find all drivers inside a surge zone
SELECT d.id, d.name, g.name AS zone_name
FROM drivers d
JOIN geofences g ON ST_Intersects(g.boundary, d.location)
WHERE g.zone_type = 'surge_zone' AND g.is_active = true;
```

---

# Part 3: Real-Time Tracking (Redis + S2)

## ⚡ Redis GEO Commands

```bash
# Add driver locations
GEOADD drivers:available -73.9857 40.7484 driver:1
GEOADD drivers:available -73.9900 40.7500 driver:2
GEOADD drivers:available -74.0000 40.7600 driver:3

# Find drivers within 5km radius
GEOSEARCH drivers:available FROMMEMBER driver:1 BYRADIUS 5 km WITHDIST
# Returns:
# 1) driver:1, 0
# 2) driver:2, 0.5km
# 3) driver:3, 1.8km

# Find by coordinates
GEORADIUS drivers:available -73.9857 40.7484 5 km WITHDIST WITHCOORD

# Get distance between two members
GEODIST drivers:available driver:1 driver:2 km
# Returns: 0.5
```

### Redis + S2 for Sharding
```python
import redis
import s2sphere

class GeoTracker:
    def __init__(self):
        self.redis_nodes = [
            redis.Redis(host='redis-1', port=6379),
            redis.Redis(host='redis-2', port=6379),
            redis.Redis(host='redis-3', port=6379),
            redis.Redis(host='redis-4', port=6379),
        ]
    
    def _get_shard(self, lat, lng):
        """Shard by S2 cell face (0-5) mod num_shards."""
        ll = s2sphere.LatLng.from_degrees(lat, lng)
        cell = s2sphere.CellId.from_lat_lng(ll)
        face = cell.face()
        return self.redis_nodes[face % len(self.redis_nodes)]
    
    def update_location(self, driver_id, lat, lng):
        shard = self._get_shard(lat, lng)
        shard.geoadd('drivers', (lng, lat, driver_id))
    
    def find_nearby(self, lat, lng, radius_km):
        # Query all shards (geo queries can cross shard boundaries)
        results = []
        for shard in self.redis_nodes:
            nearby = shard.georadius(
                'drivers', 
                lng, lat, radius_km, unit='km',
                withdist=True
            )
            results.extend(nearby)
        
        # Sort by distance and dedupe
        results.sort(key=lambda x: x[1])
        return results[:10]
```

---

# Part 4: Production Patterns

## 🔄 Location Update Batching

```python
from dataclasses import dataclass
from typing import List
import asyncio

@dataclass
class LocationUpdate:
    driver_id: str
    lat: float
    lng: float
    timestamp: int

class LocationBatcher:
    def __init__(self, batch_size=100, flush_interval_ms=100):
        self.batch_size = batch_size
        self.flush_interval = flush_interval_ms / 1000
        self.buffer: List[LocationUpdate] = []
        self.lock = asyncio.Lock()
    
    async def add(self, update: LocationUpdate):
        async with self.lock:
            self.buffer.append(update)
            if len(self.buffer) >= self.batch_size:
                await self._flush()
    
    async def _flush(self):
        if not self.buffer:
            return
        
        batch = self.buffer[:self.batch_size]
        self.buffer = self.buffer[self.batch_size:]
        
        # Batch insert to Redis
        pipeline = redis_client.pipeline()
        for update in batch:
            pipeline.geoadd('drivers', (update.lng, update.lat, update.driver_id))
        await pipeline.execute()
        
        # Batch insert to PostgreSQL (for history)
        await db.executemany(
            "INSERT INTO location_history (driver_id, location, ts) VALUES ($1, ST_MakePoint($2, $3)::geography, $4)",
            [(u.driver_id, u.lng, u.lat, u.timestamp) for u in batch]
        )
```

## 📊 Monitoring: Location Service Metrics

```yaml
# Prometheus metrics
groups:
  - name: geo_service
    rules:
      - alert: GeoQueryLatencyHigh
        expr: histogram_quantile(0.99, rate(geo_query_duration_seconds_bucket[5m])) > 0.1
        for: 5m
        annotations:
          summary: "Geo queries taking >100ms at P99"
      
      - alert: LocationUpdateLag
        expr: |
          time() - max(location_update_timestamp) > 10
        for: 1m
        annotations:
          summary: "No location updates in 10 seconds"
      
      - alert: HotspotDetected
        expr: |
          topk(1, count by (h3_cell) (rate(location_updates_total[1m]))) 
          / 
          avg(count by (h3_cell) (rate(location_updates_total[1m]))) > 10
        for: 5m
        annotations:
          summary: "Hotspot: one cell getting 10x average updates"
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Using GEOGRAPHY not GEOMETRY for GPS | Check DDL |
| 2 | Spatial index created | `\di` in psql |
| 3 | ST_DWithin for radius queries (not ST_Distance) | EXPLAIN ANALYZE shows index use |
| 4 | S2/H3 for sharding hot data | Review partition strategy |
| 5 | Location history TTL configured | Check retention policy |
| 6 | Batching for high-velocity updates | Measure throughput |
| 7 | Geofence cache invalidation | Test zone updates |
| 8 | Fallback for Redis failure | Can query PostgreSQL directly |

---

## 🔗 Related Documents
*   [NoSQL Architecture](./nosql-architecture-guide.md) — DynamoDB with S2.
*   [Database Scaling](./database-scaling-guide.md) — Sharding by geography.
*   [TSDB Architecture](./tsdb-architecture-guide.md) — Location time-series.
