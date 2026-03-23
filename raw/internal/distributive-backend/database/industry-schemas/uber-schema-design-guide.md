# Uber Ride-Hailing: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Geospatial, Real-time Matching, Trip Lifecycle, Surge Pricing — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Using a single database for everything. Uber's genius is **polyglot persistence** — PostgreSQL for ACID transactions, Cassandra for high-write throughput, Redis for real-time state.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Uber's Schemaless](https://eng.uber.com/schemaless-rewrite/) | Sharded MySQL for trip data |
| [How Uber Scales Their Real-Time Market Platform](https://eng.uber.com/marketplace/) | Real-time matching |
| [H3: Uber's Hexagonal Hierarchical Spatial Index](https://eng.uber.com/h3/) | Geospatial indexing |
| [Ringpop](https://eng.uber.com/ringpop/) | Consistent hashing for real-time services |

---

## 🎯 The Principal Laws of Ride-Hailing Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Write-Heavy Location** | Driver pings every 4 seconds | Cassandra for location history |
| **Law 2: Read-Heavy Matching** | Find 10 nearest drivers in < 100ms | Redis GeoHash or PostGIS |
| **Law 3: ACID for Money** | Payments must be consistent | PostgreSQL for transactions |
| **Law 4: Eventual for Analytics** | Trip history can be stale | Cassandra for completed trips |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Update driver location | 1M/s | < 50ms | Redis (hot), Cassandra (cold) |
| 2 | Find available drivers within 2km | 100K/s | < 100ms | Redis GeoHash |
| 3 | Create trip request | 10K/s | < 200ms | PostgreSQL |
| 4 | Match driver to rider | 10K/s | < 500ms | Redis + PostgreSQL |
| 5 | Get trip status | 50K/s | < 50ms | PostgreSQL (active), Redis (cache) |
| 6 | Complete trip with payment | 5K/s | < 2s | PostgreSQL (saga) |
| 7 | Get rider trip history | 10K/s | < 200ms | Cassandra |
| 8 | Calculate surge pricing | 100/s | < 100ms | Redis (precomputed) |
| 9 | Get driver earnings | 5K/s | < 200ms | Cassandra |
| 10 | Real-time driver tracking | 100K/s | < 100ms | Redis Pub/Sub |

---

# Part 2: Database Selection Matrix

```
┌─────────────────────────────────────────────────────────────────┐
│                    UBER POLYGLOT ARCHITECTURE                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL + PostGIS                     │
│  ✓ ACID transactions    ✓ Geospatial indexes   ✓ Relations      │
│                                                                  │
│  • users (riders, drivers)                                       │
│  • vehicles                                                      │
│  • active_trips (state machine)                                  │
│  • payments, refunds                                             │
│  • driver_documents (verification)                               │
│  • surge_pricing_zones (geofences)                               │
└─────────────────────────────────────────────────────────────────┘
                              │ CDC
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Apache Cassandra                         │
│  ✓ High write throughput   ✓ Linear scalability   ✓ Multi-DC    │
│                                                                  │
│  • driver_location_history (time-series)                         │
│  • completed_trips_by_rider                                      │
│  • completed_trips_by_driver                                     │
│  • trip_events (granular events)                                 │
│  • driver_earnings_daily                                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Sub-ms latency   ✓ GeoHash   ✓ Pub/Sub   ✓ Sorted Sets       │
│                                                                  │
│  • driver_locations (GEOADD)  — real-time position              │
│  • driver_status (HSET)       — available/busy                  │
│  • surge_multipliers (HSET)   — per H3 cell                     │
│  • active_trips_cache         — fast lookup                     │
│  • trip_tracking_pubsub       — real-time updates               │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL (Transactional Core)

```sql
-- ============================================================
-- UBER SCHEMA: PostgreSQL + PostGIS Production DDL
-- Version: Ride-hailing core
-- ============================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy search


-- ===========================================
-- SECTION 1: USERS (Riders and Drivers)
-- ===========================================

CREATE TYPE user_type AS ENUM ('rider', 'driver', 'both');
CREATE TYPE verification_status AS ENUM ('pending', 'approved', 'rejected', 'expired');

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone_number        VARCHAR(20) NOT NULL UNIQUE,
    email               VARCHAR(255),
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    profile_photo_url   TEXT,
    user_type           user_type NOT NULL DEFAULT 'rider',
    
    -- Rating (denormalized for performance)
    rider_rating        DECIMAL(3,2) DEFAULT 5.00,
    rider_trip_count    INT DEFAULT 0,
    driver_rating       DECIMAL(3,2),
    driver_trip_count   INT DEFAULT 0,
    
    -- Account status
    is_active           BOOLEAN DEFAULT TRUE,
    is_phone_verified   BOOLEAN DEFAULT FALSE,
    is_email_verified   BOOLEAN DEFAULT FALSE,
    
    -- Default payment
    default_payment_method_id UUID,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT ck_rider_rating CHECK (rider_rating >= 1.0 AND rider_rating <= 5.0),
    CONSTRAINT ck_driver_rating CHECK (driver_rating IS NULL OR (driver_rating >= 1.0 AND driver_rating <= 5.0))
);

CREATE INDEX idx_users_phone ON users(phone_number);
CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;
CREATE INDEX idx_users_type ON users(user_type) WHERE user_type IN ('driver', 'both');


-- ===========================================
-- SECTION 2: DRIVERS AND VEHICLES
-- ===========================================

CREATE TYPE driver_status AS ENUM ('offline', 'online', 'busy');

CREATE TABLE drivers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL UNIQUE REFERENCES users(id),
    
    -- License
    license_number      VARCHAR(50) NOT NULL,
    license_expiry      DATE NOT NULL,
    license_state       VARCHAR(50),
    
    -- Verification
    verification_status verification_status DEFAULT 'pending',
    verified_at         TIMESTAMP WITH TIME ZONE,
    
    -- Current state (also in Redis for real-time)
    current_status      driver_status DEFAULT 'offline',
    current_vehicle_id  UUID,  -- FK added after vehicles table
    
    -- Location (cached from Redis, updated periodically)
    last_known_location GEOGRAPHY(Point, 4326),
    last_location_at    TIMESTAMP WITH TIME ZONE,
    
    -- Preferences
    accepts_cash        BOOLEAN DEFAULT TRUE,
    max_distance_km     INT DEFAULT 50,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_drivers_user ON drivers(user_id);
CREATE INDEX idx_drivers_status ON drivers(current_status) WHERE current_status = 'online';
CREATE INDEX idx_drivers_location ON drivers USING GIST(last_known_location);
CREATE INDEX idx_drivers_verified ON drivers(verification_status) WHERE verification_status = 'approved';

CREATE TYPE vehicle_type AS ENUM ('standard', 'premium', 'xl', 'black', 'moto');

CREATE TABLE vehicles (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    
    -- Vehicle details
    make                VARCHAR(100) NOT NULL,
    model               VARCHAR(100) NOT NULL,
    year                INT NOT NULL,
    color               VARCHAR(50) NOT NULL,
    license_plate       VARCHAR(20) NOT NULL UNIQUE,
    
    -- Classification
    vehicle_type        vehicle_type NOT NULL DEFAULT 'standard',
    max_passengers      INT NOT NULL DEFAULT 4,
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    verification_status verification_status DEFAULT 'pending',
    
    -- Insurance
    insurance_provider  VARCHAR(255),
    insurance_expiry    DATE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT ck_vehicle_year CHECK (year >= 2005 AND year <= EXTRACT(YEAR FROM NOW()) + 1)
);

CREATE INDEX idx_vehicles_driver ON vehicles(driver_id);
CREATE INDEX idx_vehicles_plate ON vehicles(license_plate);
CREATE INDEX idx_vehicles_type ON vehicles(vehicle_type);

-- Add FK now that vehicles exists
ALTER TABLE drivers ADD CONSTRAINT fk_driver_vehicle 
    FOREIGN KEY (current_vehicle_id) REFERENCES vehicles(id);


-- ===========================================
-- SECTION 3: PAYMENT METHODS
-- ===========================================

CREATE TYPE payment_type AS ENUM ('card', 'wallet', 'cash', 'corporate');

CREATE TABLE payment_methods (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id),
    payment_type        payment_type NOT NULL,
    
    -- Card details (tokenized - never store full PAN)
    stripe_payment_method_id VARCHAR(255),  -- pm_xxx
    card_brand          VARCHAR(20),  -- visa, mastercard
    card_last4          VARCHAR(4),
    card_exp_month      INT,
    card_exp_year       INT,
    
    -- Wallet
    wallet_balance      DECIMAL(10,2) DEFAULT 0.00,
    
    -- Status
    is_default          BOOLEAN DEFAULT FALSE,
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT ck_wallet_balance CHECK (wallet_balance >= 0)
);

CREATE INDEX idx_payment_user ON payment_methods(user_id);
CREATE INDEX idx_payment_default ON payment_methods(user_id, is_default) WHERE is_default = TRUE;

-- Add FK to users
ALTER TABLE users ADD CONSTRAINT fk_user_default_payment 
    FOREIGN KEY (default_payment_method_id) REFERENCES payment_methods(id);


-- ===========================================
-- SECTION 4: TRIPS (State Machine)
-- ===========================================

CREATE TYPE trip_status AS ENUM (
    'requested',           -- Rider requested, looking for driver
    'driver_assigned',     -- Driver accepted
    'driver_arrived',      -- Driver at pickup
    'in_progress',         -- Trip started
    'completed',           -- Trip finished
    'cancelled_by_rider',
    'cancelled_by_driver',
    'no_drivers_available'
);

CREATE TABLE trips (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Participants
    rider_id            UUID NOT NULL REFERENCES users(id),
    driver_id           UUID REFERENCES drivers(id),
    vehicle_id          UUID REFERENCES vehicles(id),
    
    -- Trip type
    vehicle_type        vehicle_type NOT NULL DEFAULT 'standard',
    
    -- Status
    status              trip_status NOT NULL DEFAULT 'requested',
    
    -- Locations (PostGIS geography for accurate distance)
    pickup_location     GEOGRAPHY(Point, 4326) NOT NULL,
    pickup_address      TEXT NOT NULL,
    dropoff_location    GEOGRAPHY(Point, 4326) NOT NULL,
    dropoff_address     TEXT NOT NULL,
    
    -- Route (actual path taken)
    route_polyline      TEXT,  -- Encoded polyline
    
    -- Estimates (at request time)
    estimated_distance_m INT NOT NULL,
    estimated_duration_s INT NOT NULL,
    estimated_fare      DECIMAL(10,2) NOT NULL,
    surge_multiplier    DECIMAL(4,2) DEFAULT 1.00,
    
    -- Actuals (after completion)
    actual_distance_m   INT,
    actual_duration_s   INT,
    actual_fare         DECIMAL(10,2),
    
    -- Payment
    payment_method_id   UUID REFERENCES payment_methods(id),
    payment_status      VARCHAR(20) DEFAULT 'pending',  -- pending, charged, refunded
    
    -- Timestamps
    requested_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    driver_assigned_at  TIMESTAMP WITH TIME ZONE,
    driver_arrived_at   TIMESTAMP WITH TIME ZONE,
    started_at          TIMESTAMP WITH TIME ZONE,
    completed_at        TIMESTAMP WITH TIME ZONE,
    cancelled_at        TIMESTAMP WITH TIME ZONE,
    
    -- Cancellation
    cancellation_reason TEXT,
    cancellation_fee    DECIMAL(10,2) DEFAULT 0.00,
    
    -- Version for optimistic locking
    version             INT NOT NULL DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Critical indexes
CREATE INDEX idx_trips_rider ON trips(rider_id);
CREATE INDEX idx_trips_driver ON trips(driver_id) WHERE driver_id IS NOT NULL;
CREATE INDEX idx_trips_status ON trips(status);
CREATE INDEX idx_trips_active ON trips(status) WHERE status IN ('requested', 'driver_assigned', 'driver_arrived', 'in_progress');
CREATE INDEX idx_trips_requested ON trips(requested_at DESC);
CREATE INDEX idx_trips_pickup ON trips USING GIST(pickup_location);


-- ===========================================
-- SECTION 5: RATINGS
-- ===========================================

CREATE TABLE ratings (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id             UUID NOT NULL UNIQUE REFERENCES trips(id),
    
    -- Rider rating driver
    rider_to_driver_rating   INT,
    rider_to_driver_comment  TEXT,
    rider_rated_at           TIMESTAMP WITH TIME ZONE,
    
    -- Driver rating rider
    driver_to_rider_rating   INT,
    driver_to_rider_comment  TEXT,
    driver_rated_at          TIMESTAMP WITH TIME ZONE,
    
    -- Tip (optional)
    tip_amount          DECIMAL(10,2) DEFAULT 0.00,
    
    CONSTRAINT ck_rider_rating_range CHECK (rider_to_driver_rating IS NULL OR (rider_to_driver_rating >= 1 AND rider_to_driver_rating <= 5)),
    CONSTRAINT ck_driver_rating_range CHECK (driver_to_rider_rating IS NULL OR (driver_to_rider_rating >= 1 AND driver_to_rider_rating <= 5))
);

CREATE INDEX idx_ratings_trip ON ratings(trip_id);


-- ===========================================
-- SECTION 6: SURGE PRICING ZONES
-- ===========================================

CREATE TABLE surge_zones (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(255) NOT NULL,
    
    -- Geographic boundary (polygon)
    boundary            GEOGRAPHY(Polygon, 4326) NOT NULL,
    
    -- Or H3 cell-based
    h3_resolution       INT DEFAULT 7,  -- Resolution 7 = ~5.16 km²
    h3_cell_ids         TEXT[],  -- Array of H3 cell IDs
    
    -- Current multiplier (also in Redis)
    current_multiplier  DECIMAL(4,2) DEFAULT 1.00,
    
    -- Rules
    min_multiplier      DECIMAL(4,2) DEFAULT 1.00,
    max_multiplier      DECIMAL(4,2) DEFAULT 5.00,
    
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_surge_boundary ON surge_zones USING GIST(boundary);
CREATE INDEX idx_surge_active ON surge_zones(is_active) WHERE is_active = TRUE;

-- Surge history for analytics
CREATE TABLE surge_history (
    id                  BIGSERIAL PRIMARY KEY,
    zone_id             UUID NOT NULL REFERENCES surge_zones(id),
    multiplier          DECIMAL(4,2) NOT NULL,
    demand_count        INT,  -- Requests in zone
    supply_count        INT,  -- Available drivers
    recorded_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (recorded_at);

-- Monthly partitions
CREATE TABLE surge_history_y2024m01 PARTITION OF surge_history
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE surge_history_y2024m02 PARTITION OF surge_history
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
-- Continue for each month...


-- ===========================================
-- SECTION 7: PAYMENTS AND TRANSACTIONS
-- ===========================================

CREATE TYPE transaction_type AS ENUM ('charge', 'refund', 'payout', 'adjustment');
CREATE TYPE transaction_status AS ENUM ('pending', 'processing', 'completed', 'failed');

CREATE TABLE transactions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id             UUID REFERENCES trips(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    payment_method_id   UUID REFERENCES payment_methods(id),
    
    transaction_type    transaction_type NOT NULL,
    amount              DECIMAL(10,2) NOT NULL,
    currency            VARCHAR(3) DEFAULT 'USD',
    
    status              transaction_status DEFAULT 'pending',
    
    -- External references
    stripe_payment_intent_id VARCHAR(255),
    stripe_charge_id    VARCHAR(255),
    
    -- Breakdown
    fare_amount         DECIMAL(10,2),
    surge_amount        DECIMAL(10,2),
    tip_amount          DECIMAL(10,2),
    tax_amount          DECIMAL(10,2),
    discount_amount     DECIMAL(10,2),
    
    -- Error handling
    failure_reason      TEXT,
    retry_count         INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_txn_trip ON transactions(trip_id) WHERE trip_id IS NOT NULL;
CREATE INDEX idx_txn_user ON transactions(user_id);
CREATE INDEX idx_txn_status ON transactions(status);
CREATE INDEX idx_txn_stripe ON transactions(stripe_charge_id) WHERE stripe_charge_id IS NOT NULL;

-- Idempotency key for webhook processing
CREATE TABLE processed_webhooks (
    idempotency_key     VARCHAR(255) PRIMARY KEY,
    event_type          VARCHAR(100) NOT NULL,
    processed_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 4: PostGIS Geospatial Queries

```sql
-- ============================================================
-- GEOSPATIAL QUERIES
-- ============================================================

-- Find available drivers within 2km of pickup
CREATE OR REPLACE FUNCTION find_nearby_drivers(
    p_pickup GEOGRAPHY,
    p_radius_m INT DEFAULT 2000,
    p_vehicle_type vehicle_type DEFAULT 'standard',
    p_limit INT DEFAULT 10
) RETURNS TABLE (
    driver_id UUID,
    user_id UUID,
    vehicle_id UUID,
    distance_m FLOAT,
    driver_rating DECIMAL,
    eta_seconds INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.id AS driver_id,
        d.user_id,
        v.id AS vehicle_id,
        ST_Distance(d.last_known_location, p_pickup) AS distance_m,
        u.driver_rating,
        -- Rough ETA: distance / 30 km/h average city speed
        (ST_Distance(d.last_known_location, p_pickup) / 8.33)::INT AS eta_seconds
    FROM drivers d
    JOIN users u ON d.user_id = u.id
    JOIN vehicles v ON d.current_vehicle_id = v.id
    WHERE d.current_status = 'online'
      AND d.verification_status = 'approved'
      AND v.vehicle_type = p_vehicle_type
      AND v.is_active = TRUE
      AND ST_DWithin(d.last_known_location, p_pickup, p_radius_m)
    ORDER BY ST_Distance(d.last_known_location, p_pickup)
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- Usage:
-- SELECT * FROM find_nearby_drivers(
--     ST_SetSRID(ST_MakePoint(-73.985428, 40.748817), 4326)::geography,
--     2000,
--     'standard',
--     10
-- );


-- Get surge multiplier for a location
CREATE OR REPLACE FUNCTION get_surge_multiplier(
    p_location GEOGRAPHY
) RETURNS DECIMAL AS $$
DECLARE
    v_multiplier DECIMAL := 1.00;
BEGIN
    SELECT current_multiplier INTO v_multiplier
    FROM surge_zones
    WHERE is_active = TRUE
      AND ST_Intersects(boundary, p_location)
    ORDER BY current_multiplier DESC  -- Highest surge wins
    LIMIT 1;
    
    RETURN COALESCE(v_multiplier, 1.00);
END;
$$ LANGUAGE plpgsql STABLE;


-- Calculate fare estimate
CREATE OR REPLACE FUNCTION calculate_fare_estimate(
    p_pickup GEOGRAPHY,
    p_dropoff GEOGRAPHY,
    p_vehicle_type vehicle_type
) RETURNS TABLE (
    distance_m INT,
    duration_s INT,
    base_fare DECIMAL,
    surge_multiplier DECIMAL,
    estimated_fare DECIMAL
) AS $$
DECLARE
    v_distance FLOAT;
    v_base_rate DECIMAL;
    v_per_km DECIMAL;
    v_per_min DECIMAL;
    v_min_fare DECIMAL;
    v_surge DECIMAL;
BEGIN
    -- Calculate straight-line distance (actual would use routing API)
    v_distance := ST_Distance(p_pickup, p_dropoff);
    
    -- Vehicle type pricing
    SELECT 
        CASE p_vehicle_type 
            WHEN 'standard' THEN 2.50
            WHEN 'premium' THEN 5.00
            WHEN 'xl' THEN 3.50
            WHEN 'black' THEN 7.00
            WHEN 'moto' THEN 1.50
        END,
        CASE p_vehicle_type 
            WHEN 'standard' THEN 1.20
            WHEN 'premium' THEN 2.50
            WHEN 'xl' THEN 1.80
            WHEN 'black' THEN 3.50
            WHEN 'moto' THEN 0.80
        END,
        CASE p_vehicle_type 
            WHEN 'standard' THEN 0.25
            WHEN 'premium' THEN 0.50
            WHEN 'xl' THEN 0.35
            WHEN 'black' THEN 0.60
            WHEN 'moto' THEN 0.15
        END,
        CASE p_vehicle_type 
            WHEN 'standard' THEN 5.00
            WHEN 'premium' THEN 15.00
            WHEN 'xl' THEN 8.00
            WHEN 'black' THEN 25.00
            WHEN 'moto' THEN 3.00
        END
    INTO v_base_rate, v_per_km, v_per_min, v_min_fare;
    
    -- Get surge
    v_surge := get_surge_multiplier(p_pickup);
    
    RETURN QUERY
    SELECT 
        v_distance::INT AS distance_m,
        (v_distance / 8.33)::INT AS duration_s,  -- ~30 km/h
        v_base_rate + (v_distance / 1000 * v_per_km) + ((v_distance / 8.33) / 60 * v_per_min) AS base_fare,
        v_surge AS surge_multiplier,
        GREATEST(
            v_min_fare,
            (v_base_rate + (v_distance / 1000 * v_per_km) + ((v_distance / 8.33) / 60 * v_per_min)) * v_surge
        ) AS estimated_fare;
END;
$$ LANGUAGE plpgsql STABLE;
```

---

# Part 5: Cassandra DDL (High-Write Time-Series)

```cql
-- ============================================================
-- UBER SCHEMA: Apache Cassandra Production DDL
-- Keyspace: uber_rides
-- ============================================================

CREATE KEYSPACE IF NOT EXISTS uber_rides
WITH REPLICATION = {
    'class': 'NetworkTopologyStrategy',
    'us-east-1': 3,
    'us-west-2': 3,
    'eu-west-1': 3
}
AND DURABLE_WRITES = true;

USE uber_rides;


-- ===========================================
-- DRIVER LOCATION HISTORY
-- Partition: driver_id (hot driver = hot partition, but acceptable)
-- Clustering: timestamp DESC (most recent first)
-- TTL: 7 days for location pings
-- ===========================================

CREATE TABLE driver_location_history (
    driver_id       UUID,
    recorded_at     TIMESTAMP,
    latitude        DOUBLE,
    longitude       DOUBLE,
    heading         DOUBLE,       -- Direction in degrees
    speed_mps       DOUBLE,       -- Meters per second
    accuracy_m      DOUBLE,       -- GPS accuracy
    battery_pct     INT,          -- Driver phone battery
    is_charging     BOOLEAN,
    
    PRIMARY KEY ((driver_id), recorded_at)
) WITH CLUSTERING ORDER BY (recorded_at DESC)
  AND default_time_to_live = 604800  -- 7 days TTL
  AND gc_grace_seconds = 86400
  AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'HOURS',
    'compaction_window_size': 4
  };

-- Query: Get driver location history for last 10 minutes
-- SELECT * FROM driver_location_history 
-- WHERE driver_id = ? AND recorded_at >= ?;


-- ===========================================
-- TRIP EVENTS (Event Sourcing Pattern)
-- Partition: trip_id
-- Clustering: event_timestamp (for ordered replay)
-- ===========================================

CREATE TABLE trip_events (
    trip_id         UUID,
    event_timestamp TIMESTAMP,
    event_type      TEXT,         -- 'REQUESTED', 'DRIVER_ASSIGNED', 'LOCATION_UPDATE', etc.
    actor_type      TEXT,         -- 'RIDER', 'DRIVER', 'SYSTEM'
    actor_id        UUID,
    latitude        DOUBLE,
    longitude       DOUBLE,
    event_data      MAP<TEXT, TEXT>,  -- Flexible key-value for event-specific data
    
    PRIMARY KEY ((trip_id), event_timestamp)
) WITH CLUSTERING ORDER BY (event_timestamp ASC)
  AND gc_grace_seconds = 86400
  AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',
    'compaction_window_size': 1
  };

-- Query: Replay all events for a trip
-- SELECT * FROM trip_events WHERE trip_id = ? ORDER BY event_timestamp;


-- ===========================================
-- COMPLETED TRIPS BY RIDER
-- Partition: rider_id + month (bucketing to avoid unbounded growth)
-- Clustering: completed_at DESC
-- ===========================================

CREATE TABLE completed_trips_by_rider (
    rider_id        UUID,
    trip_month      TEXT,         -- '2024-01' for bucketing
    completed_at    TIMESTAMP,
    trip_id         UUID,
    
    -- Denormalized for fast reads
    driver_name     TEXT,
    vehicle_type    TEXT,
    pickup_address  TEXT,
    dropoff_address TEXT,
    fare_amount     DECIMAL,
    rating_given    INT,
    
    PRIMARY KEY ((rider_id, trip_month), completed_at)
) WITH CLUSTERING ORDER BY (completed_at DESC)
  AND gc_grace_seconds = 86400;

-- Query: Get rider's trips for January 2024
-- SELECT * FROM completed_trips_by_rider 
-- WHERE rider_id = ? AND trip_month = '2024-01';


-- ===========================================
-- COMPLETED TRIPS BY DRIVER
-- Partition: driver_id + month
-- Clustering: completed_at DESC
-- ===========================================

CREATE TABLE completed_trips_by_driver (
    driver_id       UUID,
    trip_month      TEXT,
    completed_at    TIMESTAMP,
    trip_id         UUID,
    
    -- Denormalized
    rider_name      TEXT,
    vehicle_id      UUID,
    pickup_address  TEXT,
    dropoff_address TEXT,
    fare_amount     DECIMAL,
    earnings        DECIMAL,      -- Driver's cut
    tip_amount      DECIMAL,
    rating_received INT,
    
    PRIMARY KEY ((driver_id, trip_month), completed_at)
) WITH CLUSTERING ORDER BY (completed_at DESC);


-- ===========================================
-- DRIVER EARNINGS (Aggregated)
-- Partition: driver_id + year
-- Clustering: date DESC
-- ===========================================

CREATE TABLE driver_earnings_daily (
    driver_id       UUID,
    year            INT,
    date            DATE,
    
    trip_count      INT,
    total_fare      DECIMAL,
    total_earnings  DECIMAL,
    total_tips      DECIMAL,
    total_bonus     DECIMAL,
    online_hours    DECIMAL,
    
    PRIMARY KEY ((driver_id, year), date)
) WITH CLUSTERING ORDER BY (date DESC);

-- Query: Get driver earnings for 2024
-- SELECT * FROM driver_earnings_daily 
-- WHERE driver_id = ? AND year = 2024;


-- ===========================================
-- SURGE PRICING SNAPSHOTS (Time-Series)
-- Partition: zone_id + date
-- Clustering: recorded_at DESC
-- ===========================================

CREATE TABLE surge_snapshots (
    zone_id         UUID,
    date            DATE,
    recorded_at     TIMESTAMP,
    
    multiplier      DECIMAL,
    demand_count    INT,
    supply_count    INT,
    
    PRIMARY KEY ((zone_id, date), recorded_at)
) WITH CLUSTERING ORDER BY (recorded_at DESC)
  AND default_time_to_live = 2592000  -- 30 days TTL
  AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'HOURS',
    'compaction_window_size': 1
  };
```

---

# Part 6: Redis Data Structures

```redis
# ============================================================
# UBER SCHEMA: Redis Data Structures
# ============================================================

# ===========================================
# DRIVER LOCATIONS (GeoHash)
# Key: driver_locations:{vehicle_type}
# Type: GEOADD (sorted set with geo)
# ===========================================

# Add/update driver location
GEOADD driver_locations:standard -73.985428 40.748817 driver:550e8400-e29b-41d4-a716-446655440000

# Find drivers within 2km
GEORADIUS driver_locations:standard -73.985428 40.748817 2 km WITHDIST WITHCOORD COUNT 10 ASC

# Remove driver (went offline)
ZREM driver_locations:standard driver:550e8400-e29b-41d4-a716-446655440000


# ===========================================
# DRIVER STATUS
# Key: driver_status:{driver_id}
# Type: HASH
# TTL: None (managed by app)
# ===========================================

HSET driver_status:550e8400 status online vehicle_id abc123 updated_at 1705312800
HGET driver_status:550e8400 status
HDEL driver_status:550e8400 status  # When going offline


# ===========================================
# ACTIVE TRIPS CACHE
# Key: active_trip:{trip_id}
# Type: HASH
# TTL: 24 hours (cleanup if stuck)
# ===========================================

HSET active_trip:trip-123 \
    rider_id rider-456 \
    driver_id driver-789 \
    status in_progress \
    pickup_lat 40.748817 \
    pickup_lng -73.985428 \
    current_lat 40.752000 \
    current_lng -73.980000 \
    updated_at 1705312800

EXPIRE active_trip:trip-123 86400


# ===========================================
# SURGE MULTIPLIERS (Per H3 Cell)
# Key: surge:{city}
# Type: HASH (h3_cell_id -> multiplier)
# ===========================================

HSET surge:nyc \
    8a2a1072b59ffff 1.5 \
    8a2a1072b5bffff 2.0 \
    8a2a1072b5dffff 1.0

HGET surge:nyc 8a2a1072b59ffff


# ===========================================
# TRIP TRACKING PUB/SUB
# Channel: trip_updates:{trip_id}
# ===========================================

# Driver publishes location
PUBLISH trip_updates:trip-123 '{"lat": 40.752, "lng": -73.980, "heading": 45, "eta_s": 120}'

# Rider subscribes
SUBSCRIBE trip_updates:trip-123


# ===========================================
# DRIVER MATCHING QUEUE
# Key: ride_requests:{city}:{vehicle_type}
# Type: SORTED SET (score = request timestamp)
# ===========================================

ZADD ride_requests:nyc:standard 1705312800 request-123
ZPOPMIN ride_requests:nyc:standard  # FIFO processing


# ===========================================
# RATE LIMITING
# Key: rate_limit:{user_id}:requests
# Type: STRING with TTL
# ===========================================

INCR rate_limit:user-456:requests
EXPIRE rate_limit:user-456:requests 60  # 60 second window
# Check: GET rate_limit:user-456:requests < 10
```

---

# Part 7: Trip State Machine

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRIP STATE MACHINE                            │
└─────────────────────────────────────────────────────────────────┘

                    ┌─────────────┐
                    │  requested  │
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
┌─────────────────┐  ┌───────────┐  ┌─────────────────┐
│ cancelled_by_   │  │  driver_  │  │ no_drivers_     │
│ rider           │  │  assigned │  │ available       │
└─────────────────┘  └─────┬─────┘  └─────────────────┘
                           │
                   ┌───────┼───────┐
                   │       │       │
                   ▼       ▼       ▼
        ┌─────────────┐          ┌─────────────────┐
        │ cancelled_  │          │   driver_       │
        │ by_driver   │          │   arrived       │
        └─────────────┘          └───────┬─────────┘
                                         │
                              ┌──────────┼──────────┐
                              │          │          │
                              ▼          ▼          ▼
                   ┌─────────────┐ ┌───────────┐ ┌─────────────────┐
                   │ cancelled_  │ │ in_       │ │ cancelled_by_   │
                   │ by_rider    │ │ progress  │ │ driver (no-show)│
                   └─────────────┘ └─────┬─────┘ └─────────────────┘
                                         │
                                         ▼
                                   ┌───────────┐
                                   │ completed │
                                   └───────────┘
```

```sql
-- Transition validation
CREATE OR REPLACE FUNCTION validate_trip_transition(
    p_current_status trip_status,
    p_new_status trip_status
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN (p_current_status, p_new_status) IN (
        ('requested', 'driver_assigned'),
        ('requested', 'cancelled_by_rider'),
        ('requested', 'no_drivers_available'),
        ('driver_assigned', 'driver_arrived'),
        ('driver_assigned', 'cancelled_by_rider'),
        ('driver_assigned', 'cancelled_by_driver'),
        ('driver_arrived', 'in_progress'),
        ('driver_arrived', 'cancelled_by_rider'),
        ('driver_arrived', 'cancelled_by_driver'),
        ('in_progress', 'completed')
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

---

# Part 8: Polyglot Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    UBER DATA FLOW                                │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Driver App      │
│  (Location ping) │
└────────┬─────────┘
         │ 4-second interval
         ▼
┌──────────────────┐     ┌──────────────────┐
│  Kafka           │────►│  Cassandra       │
│  location-events │     │  driver_location │
└────────┬─────────┘     │  _history        │
         │               └──────────────────┘
         ▼
┌──────────────────┐
│  Redis           │◄─── Flink (stream processing)
│  GEOADD          │     Updates real-time location
│  driver_locations│
└──────────────────┘

┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Rider App       │────►│  Trip Service    │────►│  PostgreSQL      │
│  (Request ride)  │     │  (ACID txn)      │     │  trips table     │
└──────────────────┘     └────────┬─────────┘     └──────────────────┘
                                  │
                                  │ CDC (Debezium)
                                  ▼
                         ┌──────────────────┐
                         │  Kafka           │
                         │  trip-events     │
                         └────────┬─────────┘
                                  │
                   ┌──────────────┼──────────────┐
                   ▼              ▼              ▼
         ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
         │ Cassandra    │ │ Analytics    │ │ Notification │
         │ completed_   │ │ (Presto/     │ │ Service      │
         │ trips_by_*   │ │ Hive)        │ │              │
         └──────────────┘ └──────────────┘ └──────────────┘
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | PostGIS for geospatial | ST_DWithin indexes verified |
---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | PostGIS geospatial index | GIST index on locations |
| 2 | Cassandra for location history | TWCS compaction configured |
| 3 | Redis for real-time matching | GEOADD + GEORADIUS tested |
| 4 | Trip state machine | Transition function validates |
| 5 | Surge pricing per H3 cell | Boundary/cell indexes exist |
| 6 | Payment idempotency | processed_webhooks table |
| 7 | Location TTL 7 days | default_time_to_live set |
| 8 | Monthly trip partitioning | Cassandra bucketing by month |

---

# Part 7: DynamoDB Single-Table Design

```
============================================================
UBER: DynamoDB Single-Table Design
For high-scale trip sessions and real-time state
(PostgreSQL/Cassandra remain Primary for Core Data)
============================================================

TABLE: uber_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (Trip/Driver queries)
- GSI2: GSI2PK / GSI2SK (Route/Audit queries)

============================================================
ENTITY PATTERNS
============================================================

ACTIVE TRIP SESSION (State)
  PK: TRIP#{trip_id}
  SK: STATE
  
  Attributes: status, driver_id, rider_id, current_location (lat/lon)

DRIVER OFFER (Dispatch)
  PK: DRV#{driver_id}
  SK: OFFER#{timestamp}
  
  Attributes: trip_id, expires_at, status (ignored, accepted, rejected)

RIDER CURRENT LOCATION (For matching)
  PK: RIDER#{rider_id}
  SK: LOC
  
  Attributes: geohash, last_update_ts

SURGE HEATMAP TILE (H3)
  PK: CELL#{h3_index}
  SK: INFO
  
  Attributes: multiplier, demand_score, supply_score

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get current trip status
   Table: PK=TRIP#{trip_id}, SK=STATE

2. Get recent offers for a driver (Dispatch logic)
   Table: PK=DRV#{driver_id}, SK > OFFER#{5_mins_ago}

3. Update rider location (High frequency)
   Table: PutItem(PK=RIDER#{id}, SK=LOC)

4. Get surge multiplier for geometric cell
   Table: PK=CELL#{h3_index}, SK=INFO
```

---

# Part 8: Query Examples with EXPLAIN

```sql
-- ============================================================
-- UBER QUERY PATTERNS WITH EXPLAIN (PostGIS/Cassandra)
-- ============================================================

-- ===========================================
-- QUERY 1: Find Nearby Drivers (PostGIS)
-- ===========================================

-- "Showing car icons map"
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, vehicle_type, last_known_location
FROM drivers
WHERE ST_DWithin(
    last_known_location, 
    ST_SetSRID(ST_MakePoint(-73.98, 40.74), 4326)::geography, 
    2000 -- 2km radius
)
AND current_status = 'online';

-- Analysis: GIST Index Scan on last_known_location. 
-- Efficient KNN (K-Nearest Neighbors) search.


-- ===========================================
-- QUERY 2: Driver Location History (Cassandra)
-- ===========================================

-- "Draw the path taken" - Fetching points
SELECT latitude, longitude, recorded_at
FROM driver_location_history
WHERE driver_id = ?
  AND recorded_at > '2023-01-01 12:00:00'
ORDER BY recorded_at DESC;

-- Analysis: Sequential Read on Wide Partition. 
-- Extremely fast for time-series range scans.


-- ===========================================
-- QUERY 3: Calculate Driver Earnings (Cassandra)
-- ===========================================

-- "Your weekly payout"
SELECT date, total_earnings, trip_count
FROM driver_earnings_daily
WHERE driver_id = ?
  AND year = 2023
  AND date >= '2023-11-01';

-- Analysis: Partition Key (driver_id, year) hits single node.
-- Range scan on Clustering Key (date).


-- ===========================================
-- QUERY 4: Find Active Trips in Zone (PostgreSQL)
-- ===========================================

-- "Admin Dashboard: Active trips in downtown"
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, status, rider_id
FROM trips
WHERE status = 'in_progress'
  AND ST_Intersects(
      pickup_location::geometry, 
      ST_MakeEnvelope(-74.0, 40.7, -73.9, 40.8, 4326)
  );

-- Analysis: Index Scan using GIST on pickup_location implies spatial filtering.
```

---

# Part 9: Capacity Planning

```
============================================================
UBER CAPACITY PLANNING
============================================================

ASSUMPTIONS (Global Scale):
- 100M Monthly Active Users
- 5M Drivers
- 20M Trips/Day
- Peak: 1000 Trips/sec starts

============================================================
STORAGE ESTIMATES
============================================================

LOCATION HISTORY (Cassandra)
  5M drivers * 1 ping/4sec = 1.25M writes/sec.
  Row size: 50 bytes.
  Volume: ~5 TB/day.
  Retention: 3 months (Hot), then archive to S3 (Cold).

TRIP DATA (PostgreSQL)
  20M trips/day * 1KB/trip = 20 GB/day.
  1 Year = ~7.3 TB.
  Sharding Strategy: Shard by City_ID or Region_ID.
  (New York DB, London DB, Tokyo DB).

ACTIVE TRIPS (Redis)
  1M concurrent trips.
  Size: 1M * 1KB = 1 GB RAM.
  Easily fits in memory.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

DRIVER PINGS (Write Heavy):
- 1M+ writes/sec.
- Cassandra is the only viable persistent store.
- Redis handles the "Latest State" for matching.

MATCHING ENGINE (Compute Heavy):
- "Find nearest N drivers".
- PostGIS handles ~10k queries/sec per replica.
- Redis GeoHash handles ~100k queries/sec.

PAYMENTS (ACID Critical):
- 20M txns/day = ~230 TPS avg, 2k TPS peak.
- Postgres handles this comfortably on a single master per shard.

============================================================
SCALING STRATEGY
============================================================

1. REGIONAL SHARDING
   - Rides in New York never interact with rides in London.
   - Separate DB Clusters for NA, EMEA, APAC.
   - Compliance (GDPR) benefits.

2. SCHEMALESS (Doc Store on MySQL)
   - Uber moved from Postgres to Schemaless (Mezzanine).
   - Append-only immutable log of trip cells.
   - We stick to Postgres for this guide as it's standard industry practice.

3. DISPATCH OPTIMIZATION (Ringpop)
   - Consistent Hash Ring for Dispatch Services.
   - "Dispatch Service NY" handles all state for NYC.
   - Reduces DB load by keeping driver state in memory.
```

---

# Part 10: Anti-Patterns to Avoid

```
============================================================
UBER ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Writing Location History to RDBMS
-----------------------------------------
WRONG:
  INSERT INTO driver_locations ...
  -- 1M TPS kills Postgres WAL and Vacuum process.
  
RIGHT:
  -- Cassandra / ScyllaDB (LSM tree).
  -- Optimized for massive write ingestion.


❌ ANTI-PATTERN 2: Locking Drivers for Matching
-----------------------------------------
WRONG:
  SELECT * FROM drivers FOR UPDATE ...
  -- Locks rows, blocks availability updates.
  
RIGHT:
  -- Optimistic Locking or Redis "Offer" key with TTL.
  -- "First driver to Accept gets the lock".


❌ ANTI-PATTERN 3: Global ACID Transactions
-----------------------------------------
WRONG:
  Start Trip in SF -> Update Global Stats -> Charge Card.
  -- Cross-region latency blocks the user.
  
RIGHT:
  -- Shard transaction by City/Region.
  -- Async "Saga" for payment processing.


❌ ANTI-PATTERN 4: Polling for Ride Status
-----------------------------------------
WRONG:
  Client polls /status every 1s.
  -- 100M users = DDoS attack on your API.
  
RIGHT:
  -- WebSockets / Server-Sent Events (SSE).
  -- Push status updates to client.


❌ ANTI-PATTERN 5: Geospatial Scan on Flat Lat/Lon
-----------------------------------------
WRONG:
  WHERE lat BETWEEN x AND y AND lon BETWEEN a AND b
  -- Table scan unless complex composite indexes used.
  -- Inaccurate near poles.
  
RIGHT:
  -- PostGIS `ST_DWithin` (R-Tree Index).
  -- S2 Geometry for cell-based indexing.


❌ ANTI-PATTERN 6: Storing Maps in Database
-----------------------------------------
WRONG:
  Storing OpenStreetMap chunks in Postgres blobs.
  
RIGHT:
  -- Vector Tiles (MVT) on CDN.
  -- Database stores only Business Logic (Pickups, Cars).


❌ ANTI-PATTERN 7: Calculating ETA in DB
-----------------------------------------
WRONG:
  SELECT distance * speed FROM ...
  -- Ignores traffic, turns, one-ways.
  
RIGHT:
  -- Routing Engine (OSRM / Valhalla).
  -- Dedicated service, not SQL logic.


❌ ANTI-PATTERN 8: Hard Deleting Trips
-----------------------------------------
WRONG:
  DELETE FROM trips WHERE id = X.
  
RIGHT:
  -- Regulatory requirement to keep records for 7+ years.
  -- Soft Delete or Archive to Cold Storage.


❌ ANTI-PATTERN 9: Surge Pricing on Stale Data
-----------------------------------------
WRONG:
  Calculating surge based on 5-min old demand data.
  
RIGHT:
  -- Real-time Streaming (Flink/Kafka).
  -- 1-minute windows for demand/supply ratio.


❌ ANTI-PATTERN 10: Mixing OLTP and OLAP
-----------------------------------------
WRONG:
  Running "City-wide Heatmap" query on Dispatch DB.
  
RIGHT:
  -- ETL to Data Warehouse (Hive/BigQuery).
  -- Keep Dispatch Db focused on "Get Trip", "Update Status".
```

---

# Part 11: CDC & Event Streaming

```
============================================================
UBER CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (Trips)     │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ Surge     │    │ Fraud     │   │ Map       │  │ Receipt  │
  │ Pricing   │    │ Detection │   │ Matching  │  │ Email    │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- trip.requested          (Trigger Dispatch)
- trip.completed          (Trigger Payment, Email, Analytics)
- driver.status_change    (Update Availability Map)
- payment.failed          (Trigger User Lock)

============================================================
DISASTER RECOVERY
============================================================

RPO: < 1 minute (Trips), 0 (Financials)
RTO: < 15 minutes

STRATEGY:
1. Active-Active City Sharding
   - City A is mastered in DC 1. City B in DC 2.
   - If DC 1 fails, failover City A to DC 2 (Capacity planning critical).

2. Trip Recovery
   - State of "Active Trips" is stored in Redis (Volatile) AND Postgres (Persistent).
   - If Redis crashes, rebuild state from Postgres.

3. "Driver App Mode"
   - If Matching Engine is totally down, fallback to "Street Hail" digital mode?
   - (Rare extreme fallback).
```

---

---

# Part 12: Production Internals (Deep Dive)

```
============================================================
1. DATABASE TUNING & INTERNALS
============================================================

POSTGIS TUNING (Geospatial):
- R-Tree Index (GIST):
  - `fillfactor = 90`: Default is fine for mostly-read data.
  - For high-churn table (drivers), use `fillfactor = 70` to allow HOT updates.
- Work Mem:
  - Geospatial joins are memory hungry.
  - Set `work_mem = 64MB` locally for spatial queries.
- JIT Compilation:
  - Disable for simple spatial queries (`jit = off`).
  - Often adds 100ms overhead to 10ms queries.

CASSANDRA TUNING (Location Ingestion):
- Compaction Strategy:
  - Use `TimeWindowCompactionStrategy` (TWCS) for `driver_location_history`.
  - Drivers ping constantly; data expires in 7 days.
  - STCS (Size Tiered) will cause massive read amplification on wide partitions.
- Speculative Retry:
  - Set to `99percentile`.
  - If a replica is slow (GC pause), request another immediately.
- Bloom Filters:
  - Disable on time-series tables (we always scan by time range, rarely point lookup).

REDIS INTERNALS (Geospatial):
- `GEOADD` implementation:
  - Uses Sorted Sets (ZSET) with Geohash as the score.
  - 52-bit integer score = ~0.6m accuracy.
- Pipeline Pings:
  - Do not send 1 `GEOADD` at a time.
  - Batch 100 updates per pipeline to reduce syscall overhead.

============================================================
2. OBSERVABILITY (The "What to Watch" Dashboard)
============================================================

CRITICAL SLIs (Service Level Indicators):
1. Matching Latency: < 200ms (p99)
   - Metric: `timer.matching_engine.find_drivers`
2. Driver Location Freshness: < 5 seconds (p99)
   - Metric: `gauge.driver.last_ping_delta`
3. Dispatch Success Rate: > 99.9%
   - Metric: `counter.trip_created / counter.trip_requested`

KEY DATABASE METRICS:
- Postgres: `pg_stat_activity` (Waiting for Lock)
- Postgres: `dead_tuples` (Autovacuum lagging on active_trips?)
- Cassandra: `pending_compactions` (Is write throughput too high?)
- Redis: `evicted_keys` (Is cache too small? dropping driver locations?)

ALERTING THRESHOLDS:
- [P1] Surge Multiplier Stale (> 5 mins old).
- [P1] Redis Memory Fragmentation > 1.5.
- [P2] Cassandra Read Latency > 100ms (p95).

============================================================
3. FAILURE MODE ANALYSIS (Chaos Engineering)
============================================================

SCENARIO 1: "The Bieber Event" (Hotspot)
- Situation: Concert ends. 50,000 requests in 1 H3 cell.
- Impact: Redis shard for that cell CPU spikes to 100%.
- Mitigation:
  - Read Replicas for popular cells.
  - H3 Cell Splitting (Dynamic resolution from 7 -> 8).

SCENARIO 2: "Redis Cache Failure" (Total Loss)
- Situation: Redis cluster managing "Active Trips" crashes.
- Impact: Nobody knows who is in which car.
- Mitigation:
  - "Trip Reconstruction" Job.
  - Scan `trips` table in Postgres (Persistent source of truth).
  - Re-populate Redis (Slow, takes ~5 mins, but restores state).

SCENARIO 3: "Network Partition" (Split Brain)
- Situation: US-East-1 cannot talk to US-West-2.
- Impact: Payment Saga fails mid-flight.
- Mitigation:
  - Idempotency Keys on all payment requests (Stripe).
  - Background "Reconciliation Bot" fixes stuck transactions after partition heals.

============================================================
4. FINOPS & COST OPTIMIZATION
============================================================

TIERING STRATEGY:
- Hot (0-3 months): Cassandra SSD (NVMe).
- Warm (3-12 months): Cassandra HDD or Compressed (ZSTD).
- Cold (> 1 year): Parquet files on S3 (Query via Trino/Athena).

COMPRESSION:
- Location data compresses extremely well (deltas).
- Use `ZSTD` (Level 3) for Cassandra SSTables.
- Reduces storage cost by ~60% compared to Snappy.

INSTANCE SIZING:
- Cassandra: High I/O instances (e.g., AWS i3en.xlarge).
- Redis: Memory optimized (e.g., AWS r6g.xlarge - Graviton).
- Graviton (ARM) provides ~20% price/performance boost for Redis.
```

---

# Part 15: Production Completeness DDL

```sql
-- ============================================================
-- UBER: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. TRIP AUDIT LOG (Cassandra)
-- ===========================================

CREATE TABLE trip_audit_log (
    trip_id             UUID NOT NULL,
    event_type          VARCHAR(50) NOT NULL,  -- 'status_change', 'price_update', 'route_change'
    old_value           TEXT,
    new_value           TEXT,
    triggered_by        VARCHAR(50),  -- 'driver', 'rider', 'system', 'support'
    actor_id            UUID,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address          INET,
    PRIMARY KEY ((trip_id), created_at, event_type)
) WITH CLUSTERING ORDER BY (created_at DESC);


-- ===========================================
-- B. DOCUMENT STORAGE (Driver Verification)
-- ===========================================

CREATE TABLE driver_documents (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    document_type       VARCHAR(50) NOT NULL,  -- 'drivers_license', 'insurance', 'vehicle_registration'
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    encryption_key_id   VARCHAR(100) NOT NULL,
    verification_status VARCHAR(20) DEFAULT 'pending',
    expires_at          DATE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_driver_doc ON driver_documents(driver_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID,
    driver_id           UUID,
    channel             VARCHAR(20) NOT NULL,  -- 'push', 'sms'
    notification_type   VARCHAR(100) NOT NULL,  -- 'trip_request', 'driver_arriving'
    priority            VARCHAR(10) DEFAULT 'normal',  -- 'critical' for safety
    title               VARCHAR(100),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS (Enterprise API)
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id     UUID NOT NULL,
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['trip.completed', 'receipt.ready']
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_deliveries (
    id                  BIGSERIAL PRIMARY KEY,
    subscription_id     UUID NOT NULL REFERENCES webhook_subscriptions(id),
    event_type          VARCHAR(100) NOT NULL,
    payload             JSONB NOT NULL,
    response_code       INT,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- E. API KEYS (Enterprise / Partner)
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id     UUID,
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 1000,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- F. OAUTH / SSO
-- ===========================================

CREATE TABLE oauth_providers (
    id                  SERIAL PRIMARY KEY,
    provider_type       VARCHAR(50) NOT NULL,  -- 'google', 'facebook', 'apple'
    client_id           VARCHAR(255) NOT NULL,
    client_secret_enc   BYTEA NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE user_oauth_links (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    provider_id         INT NOT NULL REFERENCES oauth_providers(id),
    external_id         VARCHAR(255) NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uk_user_provider UNIQUE (user_id, provider_id)
);


-- ===========================================
-- G. USER SESSIONS
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    user_type           VARCHAR(10) NOT NULL,  -- 'rider', 'driver'
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_type         VARCHAR(50),
    device_id           VARCHAR(100),
    ip_address          INET NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS (City-Level Rollout)
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    target_cities       TEXT[],  -- City codes
    target_user_types   TEXT[],  -- 'rider', 'driver'
    min_app_version     VARCHAR(20),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

## 🔗 Related Documents

- [NoSQL Architecture](./nosql-architecture-guide.md) — Cassandra internals
- [Database Scaling](./database-scaling-guide.md) — Sharding patterns
- [TSDB Architecture](./tsdb-architecture-guide.md) — Time-series patterns
