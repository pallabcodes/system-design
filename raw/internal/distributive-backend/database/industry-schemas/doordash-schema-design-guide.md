# DoorDash Quick Commerce: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Merchants, Menus, Orders, Delivery Tracking, Dasher Matching — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Treating inventory as static. Quick commerce requires **real-time** inventory sync — a 0-count item still showing as available destroys customer trust.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [DoorDash Microservices](https://doordash.engineering/category/backend/) | Architecture blog |
| [Scaling DoorDash's Menu Platform](https://doordash.engineering/2020/08/27/modularizing-doordashs-menus/) | Menu service |
| [Real-time ETA Prediction](https://doordash.engineering/2021/11/30/real-time-eta-modeling/) | ML for delivery |

---

## 🎯 The Principal Laws of Quick Commerce Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Geo Is Everything** | Users, merchants, dashers all have location | PostGIS or H3 for all geo queries |
| **Law 2: Inventory Is Real-Time** | Item availability changes by the minute | Cache invalidation on every order |
| **Law 3: Order Is State Machine** | Strict transitions | Audit every state change |
| **Law 4: ETA Drives Experience** | Wrong ETA = bad reviews | ML model, not simple calculation |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Find restaurants near me | 10M/s | < 100ms | PostGIS + Cache |
| 2 | Get restaurant menu | 5M/s | < 30ms | Cache + PostgreSQL |
| 3 | Check item availability | 10M/s | < 20ms | Redis |
| 4 | Place order | 100K/s | < 500ms | PostgreSQL (ACID) |
| 5 | Get order status | 5M/s | < 50ms | Cache + PostgreSQL |
| 6 | Find available dashers | 100K/s | < 100ms | Redis GeoHash |
| 7 | Update dasher location | 500K/s | < 50ms | Redis → Cassandra |
| 8 | Track delivery in real-time | 1M/s | < 100ms | Redis Pub/Sub |
| 9 | Calculate delivery ETA | 500K/s | < 200ms | ML Service |
| 10 | Search restaurants | 1M/s | < 200ms | Elasticsearch |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    DOORDASH DATA ARCHITECTURE                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL + PostGIS                     │
│  ✓ ACID orders    ✓ Merchant data   ✓ Geo queries               │
│                                                                  │
│  • users, dashers, merchants                                     │
│  • stores, menus, items                                          │
│  • orders, order_items                                           │
│  • delivery_zones, surge_zones                                   │
└─────────────────────────────────────────────────────────────────┘
                              │ CDC
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Real-time    ✓ Geo    ✓ Pub/Sub    ✓ Inventory               │
│                                                                  │
│  • dasher_locations (GEOADD)                                     │
│  • item_availability:{store_id}                                  │
│  • active_orders:{dasher_id}                                     │
│  • order_tracking:{order_id} (Pub/Sub)                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Apache Cassandra                         │
│  ✓ Dasher history    ✓ Order events   ✓ Location logs           │
│                                                                  │
│  • dasher_location_history                                       │
│  • order_events (event sourcing)                                 │
│  • completed_orders_by_user                                      │
│  • completed_orders_by_dasher                                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Elasticsearch                            │
│  ✓ Restaurant search    ✓ Menu search   ✓ Facets                 │
│                                                                  │
│  • stores (name, cuisine, rating)                                │
│  • items (name, description, tags)                               │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- DOORDASH SCHEMA: PostgreSQL + PostGIS Production DDL
-- Version: Quick commerce orders and delivery
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";


-- ===========================================
-- SECTION 1: USERS (Customers)
-- ===========================================

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Auth
    phone_number        VARCHAR(20) NOT NULL UNIQUE,
    email               VARCHAR(255),
    password_hash       TEXT,
    
    -- Profile
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    avatar_url          TEXT,
    
    -- Stats
    order_count         INT DEFAULT 0,
    
    -- Default address
    default_address_id  UUID,
    
    -- Subscription
    dashpass_active     BOOLEAN DEFAULT FALSE,
    dashpass_expires_at TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_phone ON users(phone_number);
CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;


-- User addresses
CREATE TABLE user_addresses (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id),
    
    label               VARCHAR(50),  -- 'Home', 'Work'
    
    street_address      VARCHAR(255) NOT NULL,
    apt_suite           VARCHAR(50),
    city                VARCHAR(100) NOT NULL,
    state               VARCHAR(50) NOT NULL,
    postal_code         VARCHAR(20) NOT NULL,
    country             VARCHAR(2) DEFAULT 'US',
    
    -- Geo
    location            GEOGRAPHY(Point, 4326) NOT NULL,
    
    -- Delivery instructions
    delivery_instructions TEXT,
    
    is_default          BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_addresses_user ON user_addresses(user_id);
CREATE INDEX idx_addresses_location ON user_addresses USING GIST(location);


-- ===========================================
-- SECTION 2: MERCHANTS AND STORES
-- ===========================================

CREATE TABLE merchants (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    business_name       VARCHAR(255) NOT NULL,
    contact_email       VARCHAR(255),
    contact_phone       VARCHAR(20),
    
    -- Payout
    stripe_account_id   VARCHAR(50),
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    is_verified         BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TYPE store_status AS ENUM ('active', 'paused', 'closed', 'pending');

CREATE TABLE stores (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id         UUID NOT NULL REFERENCES merchants(id),
    
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    
    -- Location
    street_address      VARCHAR(255) NOT NULL,
    city                VARCHAR(100) NOT NULL,
    state               VARCHAR(50) NOT NULL,
    postal_code         VARCHAR(20) NOT NULL,
    location            GEOGRAPHY(Point, 4326) NOT NULL,
    
    -- Images
    logo_url            TEXT,
    cover_image_url     TEXT,
    
    -- Contact
    phone_number        VARCHAR(20),
    
    -- Categories/Cuisine
    cuisine_types       TEXT[],  -- ['italian', 'pizza', 'pasta']
    tags                TEXT[],  -- ['fast-food', 'healthy', 'vegan-options']
    
    -- Ratings (denormalized)
    rating              DECIMAL(3,2) DEFAULT 0,
    rating_count        INT DEFAULT 0,
    
    -- Operating hours (JSON for flexibility)
    hours               JSONB,
    
    -- Delivery settings
    delivery_radius_km  DECIMAL(5,2) DEFAULT 5.0,
    min_order_amount    INT DEFAULT 0,  -- In cents
    delivery_fee        INT DEFAULT 299,  -- In cents
    
    -- Status
    status              store_status DEFAULT 'pending',
    is_accepting_orders BOOLEAN DEFAULT TRUE,
    
    -- Prep time
    avg_prep_time_min   INT DEFAULT 20,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_stores_merchant ON stores(merchant_id);
CREATE INDEX idx_stores_location ON stores USING GIST(location);
CREATE INDEX idx_stores_cuisine ON stores USING GIN(cuisine_types);
CREATE INDEX idx_stores_status ON stores(status) WHERE status = 'active';


-- ===========================================
-- SECTION 3: MENUS AND ITEMS
-- ===========================================

CREATE TABLE menus (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id            UUID NOT NULL REFERENCES stores(id),
    
    name                VARCHAR(100) NOT NULL,  -- 'Lunch', 'Dinner', 'All Day'
    
    -- Active hours
    available_start     TIME,
    available_end       TIME,
    available_days      INT[],  -- [1,2,3,4,5] for Mon-Fri
    
    sort_order          INT DEFAULT 0,
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_menus_store ON menus(store_id);

CREATE TABLE menu_categories (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    menu_id             UUID NOT NULL REFERENCES menus(id),
    
    name                VARCHAR(100) NOT NULL,  -- 'Appetizers', 'Main Course'
    description         TEXT,
    
    sort_order          INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_categories_menu ON menu_categories(menu_id);

CREATE TABLE items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id            UUID NOT NULL REFERENCES stores(id),
    category_id         UUID REFERENCES menu_categories(id),
    
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    
    -- Pricing
    price               INT NOT NULL,  -- In cents
    original_price      INT,  -- For discounts
    
    -- Images
    image_url           TEXT,
    
    -- Dietary info
    is_vegetarian       BOOLEAN DEFAULT FALSE,
    is_vegan            BOOLEAN DEFAULT FALSE,
    is_gluten_free      BOOLEAN DEFAULT FALSE,
    spicy_level         INT DEFAULT 0,  -- 0-3
    allergens           TEXT[],
    
    -- Availability
    is_available        BOOLEAN DEFAULT TRUE,
    available_quantity  INT,  -- NULL = unlimited
    
    -- Popularity (denormalized)
    order_count         INT DEFAULT 0,
    
    sort_order          INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_items_store ON items(store_id);
CREATE INDEX idx_items_category ON items(category_id);
CREATE INDEX idx_items_available ON items(store_id, is_available) WHERE is_available = TRUE;


-- Item modifiers (customizations)
CREATE TABLE modifier_groups (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id            UUID NOT NULL REFERENCES stores(id),
    
    name                VARCHAR(100) NOT NULL,  -- 'Size', 'Toppings'
    
    min_selections      INT DEFAULT 0,
    max_selections      INT DEFAULT 1,
    is_required         BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE modifiers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id            UUID NOT NULL REFERENCES modifier_groups(id),
    
    name                VARCHAR(100) NOT NULL,  -- 'Large', 'Extra Cheese'
    price_adjustment    INT DEFAULT 0,  -- In cents, can be negative
    
    is_default          BOOLEAN DEFAULT FALSE,
    is_available        BOOLEAN DEFAULT TRUE,
    
    sort_order          INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE item_modifier_groups (
    item_id             UUID NOT NULL REFERENCES items(id),
    modifier_group_id   UUID NOT NULL REFERENCES modifier_groups(id),
    
    PRIMARY KEY (item_id, modifier_group_id)
);


-- ===========================================
-- SECTION 4: DASHERS (Delivery Drivers)
-- ===========================================

CREATE TYPE dasher_status AS ENUM ('offline', 'online', 'busy');

CREATE TABLE dashers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Auth
    phone_number        VARCHAR(20) NOT NULL UNIQUE,
    email               VARCHAR(255),
    
    -- Profile
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    avatar_url          TEXT,
    
    -- Vehicle
    vehicle_type        VARCHAR(20),  -- 'car', 'bike', 'scooter'
    license_plate       VARCHAR(20),
    
    -- Verification
    background_check_passed BOOLEAN DEFAULT FALSE,
    
    -- Rating
    rating              DECIMAL(3,2) DEFAULT 5.0,
    rating_count        INT DEFAULT 0,
    
    -- Stats
    total_deliveries    INT DEFAULT 0,
    acceptance_rate     DECIMAL(5,2),
    completion_rate     DECIMAL(5,2),
    
    -- Current state (also in Redis)
    status              dasher_status DEFAULT 'offline',
    current_location    GEOGRAPHY(Point, 4326),
    last_location_at    TIMESTAMP WITH TIME ZONE,
    
    -- Active delivery
    current_order_id    UUID,
    
    -- Payout
    stripe_account_id   VARCHAR(50),
    
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_dashers_phone ON dashers(phone_number);
CREATE INDEX idx_dashers_status ON dashers(status) WHERE status = 'online';
CREATE INDEX idx_dashers_location ON dashers USING GIST(current_location);


-- ===========================================
-- SECTION 5: ORDERS (State Machine)
-- ===========================================

CREATE TYPE order_status AS ENUM (
    'created',              -- Cart submitted
    'confirmed',            -- Payment successful
    'preparing',            -- Store is making order
    'ready_for_pickup',     -- Waiting for dasher
    'picked_up',            -- Dasher has order
    'arriving',             -- Dasher approaching
    'delivered',            -- Complete
    'cancelled'             -- Cancelled
);

CREATE TYPE order_type AS ENUM ('delivery', 'pickup', 'curbside');

CREATE TABLE orders (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number        VARCHAR(20) NOT NULL UNIQUE,  -- DD-123456
    
    -- Participants
    user_id             UUID NOT NULL REFERENCES users(id),
    store_id            UUID NOT NULL REFERENCES stores(id),
    dasher_id           UUID REFERENCES dashers(id),
    
    -- Type and status
    order_type          order_type NOT NULL DEFAULT 'delivery',
    status              order_status NOT NULL DEFAULT 'created',
    
    -- Delivery address
    delivery_address    JSONB,  -- Snapshot of address at order time
    delivery_location   GEOGRAPHY(Point, 4326),
    delivery_instructions TEXT,
    
    -- Pricing (all in cents)
    subtotal            INT NOT NULL,
    delivery_fee        INT DEFAULT 0,
    service_fee         INT DEFAULT 0,
    tax                 INT DEFAULT 0,
    tip                 INT DEFAULT 0,
    discount            INT DEFAULT 0,
    total               INT NOT NULL,
    
    -- Promo codes
    promo_code          VARCHAR(50),
    promo_discount      INT DEFAULT 0,
    
    -- Payment
    payment_method_id   UUID,
    payment_intent_id   VARCHAR(50),  -- Stripe
    payment_status      VARCHAR(20) DEFAULT 'pending',
    
    -- Timing
    placed_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    confirmed_at        TIMESTAMP WITH TIME ZONE,
    preparing_at        TIMESTAMP WITH TIME ZONE,
    ready_at            TIMESTAMP WITH TIME ZONE,
    picked_up_at        TIMESTAMP WITH TIME ZONE,
    delivered_at        TIMESTAMP WITH TIME ZONE,
    cancelled_at        TIMESTAMP WITH TIME ZONE,
    
    -- ETAs
    estimated_prep_time_min     INT,
    estimated_delivery_time_min INT,
    estimated_delivery_at       TIMESTAMP WITH TIME ZONE,
    
    -- Cancellation
    cancellation_reason TEXT,
    cancelled_by        VARCHAR(20),  -- 'user', 'store', 'dasher', 'system'
    
    -- Special instructions
    special_instructions TEXT,
    
    -- DashPass
    dashpass_applied    BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_store ON orders(store_id);
CREATE INDEX idx_orders_dasher ON orders(dasher_id) WHERE dasher_id IS NOT NULL;
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_placed ON orders(placed_at DESC);
CREATE INDEX idx_orders_number ON orders(order_number);


-- Order items
CREATE TABLE order_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id            UUID NOT NULL REFERENCES orders(id),
    item_id             UUID NOT NULL REFERENCES items(id),
    
    -- Snapshot at order time
    name                VARCHAR(255) NOT NULL,
    unit_price          INT NOT NULL,
    quantity            INT NOT NULL DEFAULT 1,
    total_price         INT NOT NULL,
    
    -- Modifiers applied
    modifiers           JSONB,  -- [{name, price}, ...]
    
    -- Special instructions
    special_instructions TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_order_items_order ON order_items(order_id);


-- ===========================================
-- SECTION 6: ORDER STATE TRANSITIONS
-- ===========================================

CREATE TABLE order_status_history (
    id                  BIGSERIAL PRIMARY KEY,
    order_id            UUID NOT NULL REFERENCES orders(id),
    
    from_status         order_status,
    to_status           order_status NOT NULL,
    
    changed_by_type     VARCHAR(20),  -- 'user', 'store', 'dasher', 'system'
    changed_by_id       UUID,
    
    notes               TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_status_history_order ON order_status_history(order_id);


-- ===========================================
-- SECTION 7: DELIVERY ZONES AND SURGE
-- ===========================================

CREATE TABLE delivery_zones (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(100) NOT NULL,
    
    -- Polygon boundary
    boundary            GEOGRAPHY(Polygon, 4326) NOT NULL,
    
    -- Zone settings
    base_delivery_fee   INT DEFAULT 299,
    min_order_amount    INT DEFAULT 0,
    
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_zones_boundary ON delivery_zones USING GIST(boundary);

CREATE TABLE surge_pricing (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    zone_id             UUID NOT NULL REFERENCES delivery_zones(id),
    
    multiplier          DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    
    -- Demand metrics (at time of surge)
    active_orders       INT,
    available_dashers   INT,
    
    started_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ended_at            TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_surge_zone ON surge_pricing(zone_id);
CREATE INDEX idx_surge_active ON surge_pricing(ended_at) WHERE ended_at IS NULL;


-- ===========================================
-- SECTION 8: RATINGS AND REVIEWS
-- ===========================================

CREATE TABLE ratings (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id            UUID NOT NULL UNIQUE REFERENCES orders(id),
    
    -- Store rating
    store_rating        INT,  -- 1-5
    food_rating         INT,  -- 1-5
    store_comment       TEXT,
    
    -- Dasher rating
    dasher_rating       INT,  -- 1-5
    dasher_comment      TEXT,
    
    -- Tip adjustment (positive or negative)
    tip_adjustment      INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_ratings_order ON ratings(order_id);
```

---

# Part 4: Order State Machine

```
┌─────────────────────────────────────────────────────────────────┐
│                    ORDER STATE MACHINE                           │
└─────────────────────────────────────────────────────────────────┘

                    ┌─────────────┐
                    │  created    │
                    └──────┬──────┘
                           │ payment succeeds
                           ▼
                    ┌─────────────┐
                    │  confirmed  │
                    └──────┬──────┘
                           │ store starts prep
                           ▼
                    ┌─────────────┐
                    │ preparing   │
                    └──────┬──────┘
                           │ food ready
                           ▼
              ┌─────────────────────────┐
              │   ready_for_pickup      │
              └────────────┬────────────┘
                           │ dasher arrives at store
                           ▼
                    ┌─────────────┐
                    │  picked_up  │
                    └──────┬──────┘
                           │ approaching customer
                           ▼
                    ┌─────────────┐
                    │  arriving   │
                    └──────┬──────┘
                           │ delivered
                           ▼
                    ┌─────────────┐
                    │  delivered  │
                    └─────────────┘

Any state → cancelled (with reason)
```

```sql
-- Validate state transitions
CREATE OR REPLACE FUNCTION validate_order_transition(
    p_from_status order_status,
    p_to_status order_status
) RETURNS BOOLEAN AS $$
BEGIN
    -- Can always cancel (except if already delivered/cancelled)
    IF p_to_status = 'cancelled' AND p_from_status NOT IN ('delivered', 'cancelled') THEN
        RETURN TRUE;
    END IF;
    
    -- Valid forward transitions
    RETURN (p_from_status, p_to_status) IN (
        ('created', 'confirmed'),
        ('confirmed', 'preparing'),
        ('preparing', 'ready_for_pickup'),
        ('ready_for_pickup', 'picked_up'),
        ('picked_up', 'arriving'),
        ('arriving', 'delivered')
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

---

# Part 5: Dasher Matching (Redis + PostGIS)

```sql
-- Find available dashers near store
CREATE OR REPLACE FUNCTION find_available_dashers(
    p_store_location GEOGRAPHY,
    p_radius_m INT DEFAULT 3000,
    p_limit INT DEFAULT 10
) RETURNS TABLE (
    dasher_id UUID,
    distance_m FLOAT,
    rating DECIMAL,
    total_deliveries INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.id AS dasher_id,
        ST_Distance(d.current_location, p_store_location) AS distance_m,
        d.rating,
        d.total_deliveries
    FROM dashers d
    WHERE d.status = 'online'
      AND d.is_active = TRUE
      AND d.current_order_id IS NULL  -- Not on a delivery
      AND ST_DWithin(d.current_location, p_store_location, p_radius_m)
    ORDER BY 
        d.rating DESC,
        ST_Distance(d.current_location, p_store_location) ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;
```

```python
# Redis for real-time dasher tracking

import redis

class DasherTracker:
    def __init__(self):
        self.redis = redis.Redis()
    
    def update_location(self, dasher_id: str, lat: float, lng: float):
        """
        Called every 5 seconds from dasher app.
        """
        # Update geo position
        self.redis.geoadd("dasher_locations:online", lng, lat, dasher_id)
        
        # Update last seen
        self.redis.hset(f"dasher:{dasher_id}", mapping={
            "lat": lat,
            "lng": lng,
            "updated_at": int(time.time())
        })
        
        # Publish for real-time tracking
        if order_id := self.redis.hget(f"dasher:{dasher_id}", "current_order"):
            self.redis.publish(
                f"order_tracking:{order_id}",
                json.dumps({"lat": lat, "lng": lng})
            )
    
    def find_nearby(self, lat: float, lng: float, radius_km: float = 3) -> List[str]:
        """
        Find dashers within radius.
        """
        return self.redis.georadius(
            "dasher_locations:online",
            lng, lat,
            radius_km, unit="km",
            withdist=True,
            sort="ASC",
            count=20
        )
    
    def go_online(self, dasher_id: str, lat: float, lng: float):
        self.redis.geoadd("dasher_locations:online", lng, lat, dasher_id)
        self.redis.hset(f"dasher:{dasher_id}", "status", "online")
    
    def go_offline(self, dasher_id: str):
        self.redis.zrem("dasher_locations:online", dasher_id)
        self.redis.hset(f"dasher:{dasher_id}", "status", "offline")
```

---

# Part 6: Inventory Management (Redis)

```python
# Real-time inventory in Redis

class InventoryManager:
    def __init__(self):
        self.redis = redis.Redis()
    
    def get_availability(self, store_id: str, item_id: str) -> bool:
        """
        Check if item is available (Redis first, fallback to DB).
        """
        key = f"inventory:{store_id}"
        
        # Check cache
        available = self.redis.hget(key, item_id)
        if available is not None:
            return available == b"1"
        
        # Fallback to DB
        # item = db.query(Item).get(item_id)
        # return item.is_available
    
    def mark_unavailable(self, store_id: str, item_id: str):
        """
        Called when item sells out (86'd).
        """
        key = f"inventory:{store_id}"
        self.redis.hset(key, item_id, "0")
        
        # Invalidate menu cache
        self.redis.delete(f"menu_cache:{store_id}")
        
        # Notify active carts
        self.redis.publish(f"inventory_updates:{store_id}", json.dumps({
            "item_id": item_id,
            "available": False
        }))
    
    def mark_available(self, store_id: str, item_id: str):
        """
        Called when item is back in stock.
        """
        key = f"inventory:{store_id}"
        self.redis.hset(key, item_id, "1")
        self.redis.delete(f"menu_cache:{store_id}")
    
    def decrement_on_order(self, store_id: str, item_id: str, quantity: int):
        """
        Decrement inventory count on order placement.
        """
        key = f"inventory_count:{store_id}:{item_id}"
        remaining = self.redis.incrby(key, -quantity)
        
        if remaining <= 0:
            self.mark_unavailable(store_id, item_id)
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | PostGIS for geo queries | Stores, dashers, addresses indexed |
| 2 | Order state machine | All transitions validated |
| 3 | Real-time inventory | Redis with pub/sub updates |
| 4 | Dasher location in Redis | GEOADD with 5s updates |
| 5 | Order status history | Audit trail in order_status_history |
| 6 | Surge pricing by zone | Zone polygons with active pricing |
| 7 | Item modifiers modeled | modifier_groups → modifiers → items |
| 8 | Payment snapshots | Order contains delivery_address JSON |

---

# Part 7: DynamoDB Single-Table Design

```
============================================================
DOORDASH: DynamoDB Single-Table Design
For high-scale order events and dasher logs
(PostgreSQL + PostGIS remains primary for Geo/Relational)
============================================================

TABLE: doordash_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (Store/Dasher queries)
- GSI2: GSI2PK / GSI2SK (Status/Geo queries)

============================================================
ENTITY PATTERNS
============================================================

ORDER EVENT LOG (Immutable)
  PK: ORD#{order_id}
  SK: EVT#{timestamp}
  
  Attributes: event_type, old_status, new_status, actor_id, lat, lng

DASHER LOCATION TRACK (History)
  PK: DASHER#{dasher_id}
  SK: LOC#{timestamp}
  GSI1PK: DASHER#{dasher_id}
  GSI1SK: LOC#{timestamp}
  
  Attributes: lat, lng, speed, heading, is_on_delivery

STORE MENU (Read-Optimized)
  PK: STORE#{store_id}
  SK: MENU#{menu_id}
  
  Attributes: full_menu_json (denormalized for fast app load)

DELIVERY ZONE SURGE RULES
  PK: ZONE#{zone_id}
  SK: SURGE#{timestamp}
  
  Attributes: multiplier, active_orders_count

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get full order history (Audit)
   Table: PK=ORD#{order_id}, SK begins_with "EVT#"

2. Get dasher path for a delivery
   Table: PK=DASHER#{dasher_id}, SK between start_time and end_time

3. Get active menu for store (Fast Read)
   Table: PK=STORE#{store_id}, SK=MENU#current

4. Get surge history for zone
   Table: PK=ZONE#{zone_id}, SK begins_with "SURGE#"
```

---

# Part 8: Query Examples with EXPLAIN

```sql
-- ============================================================
-- DOORDASH QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Find Restaurants Near User (Geo)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    s.id, s.name, s.rating, s.avg_prep_time_min,
    ST_Distance(s.location, $1) as distance_meters,
    s.delivery_fee,
    sp.multiplier as surge_multiplier
FROM stores s
LEFT JOIN surge_pricing sp 
    ON sp.zone_id = (SELECT id FROM delivery_zones WHERE ST_Intersects(boundary, s.location) LIMIT 1)
    AND sp.ended_at IS NULL
WHERE ST_DWithin(s.location, $1, s.delivery_radius_km * 1000)
  AND s.is_active = TRUE
  AND s.is_accepting_orders = TRUE
ORDER BY distance_meters ASC
LIMIT 50;

-- Expected: GiST index scan on idx_stores_location, ~20ms


-- ===========================================
-- QUERY 2: Get Active Orders for User
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    o.id, o.order_number, o.status, s.name as store_name,
    o.total, o.estimated_delivery_at
FROM orders o
JOIN stores s ON s.id = o.store_id
WHERE o.user_id = $1
  AND o.status NOT IN ('delivered', 'cancelled')
ORDER BY o.placed_at DESC;

-- Expected: Index scan on idx_orders_user + status filter, ~5ms


-- ===========================================
-- QUERY 3: Calculate Dasher Pay (Weekly)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    d.id,
    COUNT(o.id) as deliveries_completed,
    SUM(o.delivery_fee * 0.8 + o.tip) as total_earnings -- Simplified formula
FROM dashers d
JOIN orders o ON o.dasher_id = d.id
WHERE d.id = $1
  AND o.delivered_at >= NOW() - INTERVAL '7 days'
GROUP BY d.id;

-- Expected: Index scan on idx_orders_dasher, ~10ms


-- ===========================================
-- QUERY 4: Menu Items Search (Full Text)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    i.id, i.name, i.price, s.name as store_name
FROM items i
JOIN stores s ON s.id = i.store_id
WHERE i.store_id = $1
  AND to_tsvector('english', i.name || ' ' || i.description) 
      @@ plainto_tsquery('english', $2)
  AND i.is_available = TRUE;

-- Expected: Seq scan unless GIN index added to items(name, description).
```

---

# Part 9: Capacity Planning

```
============================================================
DOORDASH CAPACITY PLANNING
============================================================

ASSUMPTIONS (Scale X):
- 20M Monthly Active Users
- 1M Average Daily Orders (Peak: 2M)
- 500K Active Dashers
- Peak 90% traffic: 5pm-9pm (Dinner Rush)

============================================================
STORAGE ESTIMATES (1 Year)
============================================================

ORDERS (PostgreSQL)
  Rows: 365 Million
  Row Size: ~1KB
  Total: ~365 GB/year (Manageable)

DASHER LOCATIONS (Cassandra/Dynamo)
  Update every 5s per active dasher.
  50K users * 12 updates/min * 60 min * 4 hours = 1.4B updates/day
  Total: ~500 Billion points/year -> Must TTL after 30 days.

MENUS
  Stores: 500K
  Items: 50M
  Static data, heavily cached (CDN/Redis).

IMAGES (S3)
  50M items * 200KB = 10 TB
  Requires resizing pipeline (Lambda) for mobile thumbnails.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

SEARCH (Read Heavy):
- 100K QPS searching "pizza" nearby.
- Scale Elasticsearch + Redis Cache + Read Replicas.

ORDERING (Write Heavy Burst):
- 1000 orders/sec at peak.
- Postgres Master handles this fine if correctly tuned.
- Inventory locking is the bottleneck (Redis Lua scripts).

DASHER MATCHING (Compute Heavy):
- 1000 matches/sec.
- "Traveling Salesman" problem on small scale.
- Async matching service (Flink/Kafka).

============================================================
SCALING STRATEGY
============================================================

1. GEO-SHARDING (The "Pod" Model)
   - Shard everything by City/Region (Cell Architecture).
   - "San Francisco" DB, "New York" DB.
   - Fault tolerance: SF outage doesn't affect NY.

2. READ REPLICAS
   - 1 Master : 5 Replicas per Region.
   - All "Get Menu", "Get Status" go to replicas.

3. CACHE LAYERING
   - L1: Device Cache (Menu versioning).
   - L2: CDN (Images).
   - L3: Redis (Menu JSON, Store Status).
   - L4: DB.
```

---

# Part 10: Anti-Patterns to Avoid

```
============================================================
DOORDASH ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Real-time Count of Items
-----------------------------------------
WRONG:
  SELECT COUNT(*) FROM items WHERE available=true
  -- During Super Bowl, this kills the DB.
  
RIGHT:
  -- Redis Counter: INCR/DECR.
  -- "Available" boolean flag only.


❌ ANTI-PATTERN 2: Polling for Order Status
-----------------------------------------
WRONG:
  Client -> GET /order/status every 2s
  -- 1M users = 500K RPS.
  
RIGHT:
  -- WebSocket / Server-Sent Events (SSE).
  -- Push status changes only.


❌ ANTI-PATTERN 3: Storing Lat/Long History in Postgres
-----------------------------------------
WRONG:
  INSERT INTO location_logs (lat, lng)
  -- 1.4B rows/day. Postgres fills up in hours.
  
RIGHT:
  -- Cassandra / DynamoDB (Write optimized time-series).
  -- Keep only "Last Known Location" in Postgres/Redis.


❌ ANTI-PATTERN 4: Synchronous Matching
-----------------------------------------
WRONG:
  User Places Order -> Wait for Dasher to Accept -> Response
  -- Dasher might take 2 mins to accept. Request times out.
  
RIGHT:
  -- Async: Order Placed -> Queue -> Matcher Service -> Notify User.


❌ ANTI-PATTERN 5: Global "Items" Table Search
-----------------------------------------
WRONG:
  SELECT * FROM items WHERE name LIKE '%burger%'
  -- Scans 50M items across all cities.
  
RIGHT:
  -- Geo-filtered search (Elasticsearch).
  -- "Search items WHERE store_id IN (stores_near_me)".


❌ ANTI-PATTERN 6: Hard Deleting Menu Items
-----------------------------------------
WRONG:
  DELETE FROM items WHERE id = ?
  -- Breaks old order history ("What did I eat?").
  
RIGHT:
  -- Soft Delete or Versioning.
  -- Order Items copy item name/price at time of order.


❌ ANTI-PATTERN 7: Calculating ETA with SQL
-----------------------------------------
WRONG:
  SELECT avg(delivery_time) FROM history WHERE store_id = ?
  -- Too simple. Ignores weather, traffic, dasher load.
  
RIGHT:
  -- ML Model Service (Gradient Boosted Trees).
  -- Inputs: Traffic, Weather, Store Prep Load, Dasher Supply.


❌ ANTI-PATTERN 8: Ignoring Timezones
-----------------------------------------
WRONG:
  store_open_time = '09:00'
  -- Server is UTC. Store is PST.
  
RIGHT:
  -- Store Timezone in `stores` table.
  -- Convert all logic to Local Time for "Is Open" check.


❌ ANTI-PATTERN 9: Surge Pricing Global Config
-----------------------------------------
WRONG:
  UPDATE config SET surge = 1.5
  -- Surges everywhere.
  
RIGHT:
  -- Granular Hexagon-based Surge (H3 Grid).
  -- Surge only in "Downtown", not "Suburbs".


❌ ANTI-PATTERN 10: 2-Phase Commit for Order+Payment
-----------------------------------------
WRONG:
  Start Txn -> Charge Stripe -> Insert Order -> Commit
  -- Stripe timeout = DB Lock held.
  
RIGHT:
  -- Insert Order (Pending Payment).
  -- Client confirms Payment with Stripe.
  -- Webhook calculates state -> Confirmed.
```

---

# Part 11: CDC & Event Streaming

```
============================================================
DOORDASH CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (Orders)    │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ Dispatch  │    │ Analytics │   │ ETA Model │  │ Notific. │
  │ (Matching)│    │ (Dashboards)│   │ (Training)│  │ (SMS/Push)│
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- orders.created          (Trigger Matching)
- orders.status_changed   (Notify User)
- dasher.location         (Update Force Map)
- menu.updates            (Invalidate Cache)

============================================================
DISASTER RECOVERY
============================================================

RPO: < 1 minute
RTO: < 15 minutes

STRATEGY:
1. Region Insolation
   - "Cell" based architecture.
   - If US-EAST fails, shift traffic to US-CENTRAL (degraded).

2. Degraded Modes
   - If Matching Service fails -> Manual Dispatch or "Pickup Only" mode.
   - If Search fails -> Show "Recent Orders" and "Favorites".

3. Backups
   - Point-In-Time (PITR) for Postgres.
   - Replay Kafka stream to rebuild state if cache is lost.
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- DOORDASH: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / CHANGE HISTORY
-- ===========================================

CREATE TABLE entity_change_log (
    id                  BIGSERIAL PRIMARY KEY,
    entity_type         VARCHAR(50) NOT NULL,  -- 'order', 'merchant', 'menu_item'
    entity_id           UUID NOT NULL,
    field_name          VARCHAR(100) NOT NULL,
    old_value           TEXT,
    new_value           TEXT,
    changed_by_id       UUID NOT NULL,
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    change_source       VARCHAR(50),  -- 'merchant_portal', 'admin', 'bulk_import'
    ip_address          INET
) PARTITION BY RANGE (changed_at);

CREATE INDEX idx_ecl_entity ON entity_change_log(entity_type, entity_id);


-- ===========================================
-- B. MENU MEDIA
-- ===========================================

CREATE TABLE menu_media (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id         UUID NOT NULL REFERENCES merchants(id),
    menu_item_id        UUID REFERENCES menu_items(id),
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    cdn_url             VARCHAR(500),
    is_primary          BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_media_item ON menu_media(menu_item_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID,
    dasher_id           UUID,
    channel             VARCHAR(20) NOT NULL,  -- 'push', 'sms'
    recipient           VARCHAR(255) NOT NULL,
    notification_type   VARCHAR(100) NOT NULL,  -- 'order_ready', 'dasher_arriving'
    title               VARCHAR(100),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS / MERCHANT INTEGRATIONS
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id         UUID NOT NULL REFERENCES merchants(id),
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['order.created', 'order.cancelled']
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
-- E. API KEYS (For POS Integration)
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id         UUID REFERENCES merchants(id),
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 100,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- F. OAUTH / SSO
-- ===========================================

CREATE TABLE oauth_providers (
    id                  SERIAL PRIMARY KEY,
    provider_type       VARCHAR(50) NOT NULL,
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
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_type         VARCHAR(50),
    ip_address          INET NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    target_market_ids   UUID[],  -- Specific markets only
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
DOORDASH: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. DISPATCH OPTIMIZATION (THE "TSP" PROBLEM)
============================================================

THE CHALLENGE:
Matching orders to Dashers is the Traveling Salesman Problem (NP-Hard).
Constraint: Hot food gets cold in 15 minutes.
Solution: "Segmented Dispatch".

GEOSPATIAL INDEXING (Redis Geo + S2/H3):
- We don't just query "Who is nearby?".
- We query "Who is nearby AND moving towards the restaurant?".
- Dasher telemetry (GPS ping every 3s) -> Kafka -> Redis Geospatial Index.
- Key: `driver_loc:{h3_cell}` -> List[DriverID, Heading].

"BATCHING" LOGIC (Stacking Orders):
- If Dasher A is picking up at Burger King, and Order B comes in for next-door Taco Bell going to same neighborhood.
- Database Support: `active_batches` table prevents "locked" drivers from being assigned incompatible orders.

============================================================
2. MENU VERSIONING (THE "ITEM 86" PROBLEM)
============================================================

THE RACE CONDITION:
User adds "Spicy Tuna Roll" to cart.
Restaurant marks "Spicy Tuna Roll" out of stock (86'd).
User checks out. Order fails? Or Restaurant rejects?

SOLUTION: MENU SNAPSHOTS
1. Menu stored as JSONB with a `version_id`.
2. Cart Item references `(menu_item_id, menu_version_id)`.
3. Checkout Validation:
   `IF current_menu_version != cart_item_version THEN WarnUser("Menu updated")`.

CACHING STRATEGY:
- Menus are Read-Heavy (10M reads/sec).
- Write-Through Cache: Restaurant update -> invalidates Redis key `menu:{store_id}`.
- "Stale-While-Revalidate": Allow serving 5-second old menu to prevent thundering herd.

============================================================
3. ORDER STATE MACHINE CONSISTENCY
============================================================

STATES:
Created -> Confirmed -> DasherAssigned -> ArrivedAtStore -> PickedUp -> Arriving -> Delivered.

FAILURE MODE: "Ghost Orders"
- Dasher accepts order, network drops. Server thinks Dasher assigned. Dasher app thinks assignment failed.
- Mitigation: "Assignment TTL".
- Redis Key: `assignment:{order_id}:{dasher_id}` EX 30s.
- Dasher must ACK within 30s. If no ACK, server re-dispatches.

LOCKING:
- Optimistic Locking on Order Status.
- `UPDATE orders SET status = 'ASSIGNED', dasher_id = X WHERE id = Y AND status = 'CONFIRMED'`.
- Driver app retries on 0 rows updated.

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Dispatch Latency (p99)       │ < 2s    │ > 5s = PAGE     │
│  (Time from Order → Dasher Offered)                        │
├─────────────────────────────────────────────────────────────┤
│  Order Acceptance Rate        │ > 90%   │ < 85% = WARN    │
│  Dasher App Heartbeat         │ < 60s   │ > 2m = INFO     │
│  Menu Load Latency (p99)      │ < 100ms │ > 200ms = WARN  │
└─────────────────────────────────────────────────────────────┘

INFRASTRUCTURE METRICS:
- `redis_geo_commands_per_sec`: High volume indicates driver movement.
- `db_deadlocks`: Complex state updates often collide.
- `payment_gateway_latency`: Stripe/Square timeouts block checkout.

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: "THE RAIN STORM" (Supply Shock)
Symptom: It rains. Demand +50%. Dashers log off (-20%).
Impact: Dispatch loop creates "Unassignable Orders".
Mitigation:
- "Dynamic Delivery Fees" (Surge).
- Disable "Long Distance" orders (> 5 miles).
- "Batching Aggressiveness": Force triple-stacking orders.

SCENARIO 2: RESTAURANT TABLET OFFLINE
Symptom: 100 orders unconfirmed by merchant.
Mitigation:
- Auto-Confirm (Robo-Call): IVR system calls restaurant.
- "Dasher-Place-Order": Dispatch Dasher to order manually at counter (Red card).

SCENARIO 3: GPS DRIFT
Symptom: Dasher marked "Arrived" but is 1 mile away.
Mitigation:
- Geofence Check: Server verifies Lat/Long before allowing status transition.
- "Hysteresis": Require 2 consecutive pings inside geofence.

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

STORAGE TIERING:
- "Active Orders" (Last 24h): Postgres (NVMe). High IOPS.
- "Completed Orders" (< 2 years): Postgres (Partitioned by Month).
- "Cold Orders" (> 2 years): S3 Parquet.

MAPS API COSTS (Google/Mapbox):
- Geocoding/Routing is expensive ($5 per 1000 reqs).
- Caching: Cache route `(start_h3, end_h3)` distance/time for 24h.
- Don't route every polling cycle. Estimate using linear distance ("as the crow flies") * 1.3 traffic factor for initial filtering. only route top 3 candidates.
```

---

## 🔗 Related Documents

- [Uber Schema](./uber-schema-design-guide.md) — Similar geo + real-time patterns
- [Stripe Schema](./stripe-schema-design-guide.md) — Payment integration
- [Service Discovery](../system-design-notes/service-discovery.md) — Microservice coordination
