# E-commerce Platform: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Products, Catalog, Inventory, Cart, Orders, Fulfillment — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Overselling. Inventory must be **decremented atomically** at checkout, not when added to cart. Use `FOR UPDATE` or Redis atomic operations.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Amazon DynamoDB Paper](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf) | Shopping cart at scale |
| [Shopify's Data Model](https://shopify.engineering/) | Multi-tenant e-commerce |
| [Inventory Management at Scale](https://www.uber.com/blog/inventory/) | Real-time inventory |

---

## 🎯 The Principal Laws of E-commerce Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Inventory Is Critical** | Oversell = refunds + bad reviews | Atomic decrement at checkout |
| **Law 2: Cart Is Ephemeral** | Users abandon carts | TTL in Redis, persist to DB |
| **Law 3: Order Is Immutable** | Price changes shouldn't affect past orders | Snapshot prices in order |
| **Law 4: Multi-Tenancy** | Many sellers, one platform | shop_id everywhere (Shopify model) |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get product details | 100M/s | < 30ms | Cache + PostgreSQL |
| 2 | Search products | 10M/s | < 100ms | Elasticsearch |
| 3 | List products by category | 10M/s | < 50ms | PostgreSQL + Cache |
| 4 | Get/update cart | 20M/s | < 50ms | Redis + PostgreSQL |
| 5 | Checkout (create order) | 100K/s | < 2s | PostgreSQL (ACID) |
| 6 | Reserve inventory | 100K/s | < 100ms | Redis + PostgreSQL |
| 7 | Get order status | 5M/s | < 50ms | Cache + PostgreSQL |
| 8 | Get user's order history | 1M/s | < 100ms | PostgreSQL |
| 9 | Update tracking info | 500K/s | < 200ms | PostgreSQL |
| 10 | Process returns/refunds | 50K/s | < 1s | PostgreSQL |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    E-COMMERCE DATA ARCHITECTURE                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                               │
│  ✓ ACID orders    ✓ Catalog   ✓ Inventory   ✓ Multi-tenant      │
│                                                                  │
│  • shops (multi-tenant)                                          │
│  • products, variants, inventory                                 │
│  • carts, cart_items                                             │
│  • orders, order_items                                           │
│  • fulfillments, shipments                                       │
└─────────────────────────────────────────────────────────────────┘
                              │ CDC
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Shopping carts    ✓ Inventory cache   ✓ Rate limits          │
│                                                                  │
│  • cart:{session_id}                                             │
│  • inventory:{variant_id}                                        │
│  • product_cache:{product_id}                                    │
│  • flash_sale_stock:{sale_id}                                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Elasticsearch                            │
│  ✓ Product search    ✓ Faceted filtering   ✓ Typeahead          │
│                                                                  │
│  • products (title, description, attributes)                     │
│  • categories, brands                                            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    External Services                             │
│                                                                  │
│  • Stripe (payments)                                             │
│  • Shippo/EasyPost (shipping rates)                              │
│  • Warehouse Management System (WMS)                             │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- E-COMMERCE SCHEMA: PostgreSQL Production DDL
-- Version: Multi-tenant e-commerce (Shopify model)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";


-- ===========================================
-- SECTION 1: SHOPS (Multi-Tenancy)
-- ===========================================

CREATE TYPE shop_status AS ENUM ('trial', 'active', 'paused', 'cancelled');

CREATE TABLE shops (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identity
    handle              VARCHAR(50) NOT NULL UNIQUE,  -- mystore.shopify.com
    name                VARCHAR(255) NOT NULL,
    email               VARCHAR(255) NOT NULL,
    
    -- Settings
    currency            VARCHAR(3) NOT NULL DEFAULT 'USD',
    timezone            VARCHAR(50) DEFAULT 'America/New_York',
    
    -- Status
    status              shop_status DEFAULT 'trial',
    
    -- Billing (Stripe)
    stripe_customer_id  VARCHAR(50),
    
    -- Timestamps
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_shops_handle ON shops(handle);


-- ===========================================
-- SECTION 2: CUSTOMERS
-- ===========================================

CREATE TABLE customers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id             UUID NOT NULL REFERENCES shops(id),
    
    -- Identity
    email               VARCHAR(255) NOT NULL,
    phone               VARCHAR(20),
    
    -- Profile
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    
    -- Auth (for customer accounts)
    password_hash       TEXT,
    
    -- Stats
    order_count         INT DEFAULT 0,
    total_spent         BIGINT DEFAULT 0,  -- In cents
    
    -- Marketing
    accepts_marketing   BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_customer_email UNIQUE (shop_id, email)
);

CREATE INDEX idx_customers_shop ON customers(shop_id);
CREATE INDEX idx_customers_email ON customers(shop_id, email);


-- Customer addresses
CREATE TABLE customer_addresses (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    company             VARCHAR(255),
    
    address1            VARCHAR(255) NOT NULL,
    address2            VARCHAR(255),
    city                VARCHAR(100) NOT NULL,
    province            VARCHAR(100),
    province_code       VARCHAR(10),
    country             VARCHAR(100) NOT NULL,
    country_code        VARCHAR(2) NOT NULL,
    zip                 VARCHAR(20),
    phone               VARCHAR(20),
    
    is_default          BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_addresses_customer ON customer_addresses(customer_id);


-- ===========================================
-- SECTION 3: PRODUCTS AND VARIANTS
-- ===========================================

CREATE TYPE product_status AS ENUM ('draft', 'active', 'archived');

CREATE TABLE products (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id             UUID NOT NULL REFERENCES shops(id),
    
    -- Basic info
    title               VARCHAR(255) NOT NULL,
    handle              VARCHAR(255) NOT NULL,  -- URL slug
    description         TEXT,
    
    -- Vendor/brand
    vendor              VARCHAR(255),
    product_type        VARCHAR(255),
    
    -- Tags for search/filter
    tags                TEXT[],
    
    -- Status
    status              product_status DEFAULT 'draft',
    
    -- SEO
    seo_title           VARCHAR(255),
    seo_description     TEXT,
    
    -- Timestamps
    published_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_product_handle UNIQUE (shop_id, handle)
);

CREATE INDEX idx_products_shop ON products(shop_id);
CREATE INDEX idx_products_status ON products(shop_id, status);
CREATE INDEX idx_products_tags ON products USING GIN (tags);
CREATE INDEX idx_products_title_trgm ON products USING GIN (title gin_trgm_ops);


-- Product variants (size, color combinations)
CREATE TABLE variants (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id          UUID NOT NULL REFERENCES products(id),
    
    -- Variant title (e.g., "Small / Red")
    title               VARCHAR(255) NOT NULL,
    
    -- Options
    option1             VARCHAR(255),  -- Size
    option2             VARCHAR(255),  -- Color
    option3             VARCHAR(255),  -- Material
    
    -- Pricing
    price               BIGINT NOT NULL,  -- In cents
    compare_at_price    BIGINT,           -- Original price (for sales)
    cost_per_item       BIGINT,           -- Cost for margin calc
    
    -- SKU
    sku                 VARCHAR(100),
    barcode             VARCHAR(100),
    
    -- Inventory tracking
    inventory_management VARCHAR(20) DEFAULT 'shopify',  -- 'shopify', 'manual', null
    inventory_policy    VARCHAR(20) DEFAULT 'deny',     -- 'deny', 'continue'
    
    -- Shipping
    weight              DECIMAL(10,2),
    weight_unit         VARCHAR(10) DEFAULT 'lb',
    requires_shipping   BOOLEAN DEFAULT TRUE,
    
    -- Status
    position            INT DEFAULT 1,
    
    -- Image
    image_id            UUID,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_variants_product ON variants(product_id);
CREATE INDEX idx_variants_sku ON variants(sku) WHERE sku IS NOT NULL;


-- Product images
CREATE TABLE product_images (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id          UUID NOT NULL REFERENCES products(id),
    
    src                 TEXT NOT NULL,  -- CDN URL
    alt                 VARCHAR(255),
    position            INT DEFAULT 1,
    
    -- Variant association
    variant_ids         UUID[],
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_images_product ON product_images(product_id);


-- ===========================================
-- SECTION 4: INVENTORY
-- ===========================================

-- Inventory locations (warehouses, stores)
CREATE TABLE locations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id             UUID NOT NULL REFERENCES shops(id),
    
    name                VARCHAR(255) NOT NULL,
    
    -- Address
    address1            VARCHAR(255),
    city                VARCHAR(100),
    province            VARCHAR(100),
    country             VARCHAR(100),
    zip                 VARCHAR(20),
    
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_locations_shop ON locations(shop_id);


-- Inventory levels per variant per location
CREATE TABLE inventory_levels (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    variant_id          UUID NOT NULL REFERENCES variants(id),
    location_id         UUID NOT NULL REFERENCES locations(id),
    
    -- Quantities
    available           INT NOT NULL DEFAULT 0,
    reserved            INT NOT NULL DEFAULT 0,  -- Held for pending orders
    committed           INT NOT NULL DEFAULT 0,  -- Allocated to orders
    on_hand             INT GENERATED ALWAYS AS (available + reserved + committed) STORED,
    
    -- Alerts
    reorder_point       INT,
    reorder_quantity    INT,
    
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_inventory UNIQUE (variant_id, location_id),
    CONSTRAINT ck_available_positive CHECK (available >= 0)
);

CREATE INDEX idx_inventory_variant ON inventory_levels(variant_id);
CREATE INDEX idx_inventory_location ON inventory_levels(location_id);
CREATE INDEX idx_inventory_low ON inventory_levels(available) WHERE available <= 10;


-- Inventory adjustments (audit trail)
CREATE TABLE inventory_adjustments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    variant_id          UUID NOT NULL REFERENCES variants(id),
    location_id         UUID NOT NULL REFERENCES locations(id),
    
    adjustment          INT NOT NULL,  -- Positive or negative
    reason              VARCHAR(50) NOT NULL,  -- 'received', 'sold', 'returned', 'damaged', 'correction'
    
    reference_type      VARCHAR(50),  -- 'order', 'purchase_order', 'manual'
    reference_id        UUID,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_adjustments_variant ON inventory_adjustments(variant_id);


-- ===========================================
-- SECTION 5: COLLECTIONS (Categories)
-- ===========================================

CREATE TYPE collection_type AS ENUM ('manual', 'smart');

CREATE TABLE collections (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id             UUID NOT NULL REFERENCES shops(id),
    
    title               VARCHAR(255) NOT NULL,
    handle              VARCHAR(255) NOT NULL,
    description         TEXT,
    
    collection_type     collection_type NOT NULL DEFAULT 'manual',
    
    -- For smart collections
    rules               JSONB,  -- [{"field": "tag", "condition": "equals", "value": "sale"}]
    disjunctive         BOOLEAN DEFAULT FALSE,  -- AND vs OR
    
    -- SEO
    seo_title           VARCHAR(255),
    seo_description     TEXT,
    
    -- Image
    image_url           TEXT,
    
    published_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_collection_handle UNIQUE (shop_id, handle)
);

CREATE INDEX idx_collections_shop ON collections(shop_id);

-- Manual collection membership
CREATE TABLE collection_products (
    collection_id       UUID NOT NULL REFERENCES collections(id),
    product_id          UUID NOT NULL REFERENCES products(id),
    position            INT DEFAULT 0,
    
    PRIMARY KEY (collection_id, product_id)
);


-- ===========================================
-- SECTION 6: SHOPPING CART
-- ===========================================

CREATE TABLE carts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id             UUID NOT NULL REFERENCES shops(id),
    
    -- Owner (can be guest or customer)
    customer_id         UUID REFERENCES customers(id),
    session_id          VARCHAR(100),
    
    -- Totals (denormalized)
    subtotal            BIGINT DEFAULT 0,
    total_discount      BIGINT DEFAULT 0,
    total_tax           BIGINT DEFAULT 0,
    total_price         BIGINT DEFAULT 0,
    
    currency            VARCHAR(3) NOT NULL,
    
    -- Discount codes
    discount_code       VARCHAR(50),
    
    -- Shipping
    shipping_address_id UUID REFERENCES customer_addresses(id),
    
    -- Notes
    note                TEXT,
    
    -- Timestamps
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    abandoned_at        TIMESTAMP WITH TIME ZONE  -- For recovery emails
);

CREATE INDEX idx_carts_shop ON carts(shop_id);
CREATE INDEX idx_carts_customer ON carts(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX idx_carts_session ON carts(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_carts_abandoned ON carts(abandoned_at) WHERE abandoned_at IS NOT NULL;

CREATE TABLE cart_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cart_id             UUID NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    variant_id          UUID NOT NULL REFERENCES variants(id),
    
    quantity            INT NOT NULL DEFAULT 1,
    
    -- Price at time of adding (may differ from current price)
    price               BIGINT NOT NULL,
    
    -- Custom properties (gift message, etc.)
    properties          JSONB,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_cart_variant UNIQUE (cart_id, variant_id)
);

CREATE INDEX idx_cart_items_cart ON cart_items(cart_id);


-- ===========================================
-- SECTION 7: ORDERS
-- ===========================================

CREATE TYPE order_status AS ENUM (
    'pending',           -- Just created
    'confirmed',         -- Payment captured
    'partially_fulfilled',
    'fulfilled',
    'cancelled',
    'refunded'
);

CREATE TYPE financial_status AS ENUM (
    'pending', 'authorized', 'paid', 'partially_refunded', 'refunded', 'voided'
);

CREATE TYPE fulfillment_status AS ENUM (
    'unfulfilled', 'partial', 'fulfilled', 'restocked'
);

CREATE TABLE orders (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id             UUID NOT NULL REFERENCES shops(id),
    customer_id         UUID REFERENCES customers(id),
    
    -- Order number (display)
    order_number        BIGINT NOT NULL,
    name                VARCHAR(50) NOT NULL,  -- #1001
    
    -- Status
    status              order_status DEFAULT 'pending',
    financial_status    financial_status DEFAULT 'pending',
    fulfillment_status  fulfillment_status DEFAULT 'unfulfilled',
    
    -- Pricing (all in smallest currency unit)
    subtotal            BIGINT NOT NULL,
    total_discount      BIGINT DEFAULT 0,
    total_shipping      BIGINT DEFAULT 0,
    total_tax           BIGINT DEFAULT 0,
    total_price         BIGINT NOT NULL,
    currency            VARCHAR(3) NOT NULL,
    
    -- Discounts applied
    discount_codes      JSONB,
    
    -- Addresses (snapshot, not references)
    shipping_address    JSONB NOT NULL,
    billing_address     JSONB,
    
    -- Contact
    email               VARCHAR(255),
    phone               VARCHAR(20),
    
    -- Payment
    payment_gateway     VARCHAR(50),
    stripe_payment_intent_id VARCHAR(50),
    
    -- Shipping
    shipping_method     VARCHAR(255),
    
    -- Notes
    note                TEXT,
    tags                TEXT[],
    
    -- Risk
    risk_level          VARCHAR(20),  -- 'low', 'medium', 'high'
    
    -- Timestamps
    processed_at        TIMESTAMP WITH TIME ZONE,
    cancelled_at        TIMESTAMP WITH TIME ZONE,
    closed_at           TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_order_number UNIQUE (shop_id, order_number)
);

CREATE INDEX idx_orders_shop ON orders(shop_id);
CREATE INDEX idx_orders_customer ON orders(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX idx_orders_status ON orders(shop_id, status);
CREATE INDEX idx_orders_created ON orders(created_at DESC);
CREATE INDEX idx_orders_number ON orders(shop_id, order_number);


-- Order line items
CREATE TABLE order_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id            UUID NOT NULL REFERENCES orders(id),
    variant_id          UUID NOT NULL REFERENCES variants(id),
    product_id          UUID NOT NULL REFERENCES products(id),
    
    -- Snapshot at order time
    title               VARCHAR(255) NOT NULL,
    variant_title       VARCHAR(255),
    sku                 VARCHAR(100),
    
    quantity            INT NOT NULL,
    
    -- Pricing
    price               BIGINT NOT NULL,  -- Unit price
    total_discount      BIGINT DEFAULT 0,
    
    -- Fulfillment
    fulfillable_quantity    INT NOT NULL,
    fulfilled_quantity      INT DEFAULT 0,
    
    -- Weight for shipping
    weight              DECIMAL(10,2),
    
    requires_shipping   BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_order_items_variant ON order_items(variant_id);


-- ===========================================
-- SECTION 8: FULFILLMENT
-- ===========================================

CREATE TYPE fulfillment_status_type AS ENUM (
    'pending', 'in_progress', 'success', 'failure', 'cancelled'
);

CREATE TABLE fulfillments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id            UUID NOT NULL REFERENCES orders(id),
    location_id         UUID NOT NULL REFERENCES locations(id),
    
    status              fulfillment_status_type DEFAULT 'pending',
    
    -- Tracking
    tracking_company    VARCHAR(100),
    tracking_number     VARCHAR(100),
    tracking_url        TEXT,
    
    -- Timestamps
    shipped_at          TIMESTAMP WITH TIME ZONE,
    delivered_at        TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_fulfillments_order ON fulfillments(order_id);

CREATE TABLE fulfillment_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fulfillment_id      UUID NOT NULL REFERENCES fulfillments(id),
    order_item_id       UUID NOT NULL REFERENCES order_items(id),
    quantity            INT NOT NULL
);

CREATE INDEX idx_fulfillment_items ON fulfillment_items(fulfillment_id);
```

---

# Part 4: Inventory Reservation (Atomic)

```sql
-- Reserve inventory at checkout (prevents overselling)
CREATE OR REPLACE FUNCTION reserve_inventory(
    p_variant_id UUID,
    p_location_id UUID,
    p_quantity INT,
    p_order_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    v_available INT;
BEGIN
    -- Lock the row
    SELECT available INTO v_available
    FROM inventory_levels
    WHERE variant_id = p_variant_id AND location_id = p_location_id
    FOR UPDATE;
    
    IF v_available IS NULL THEN
        RAISE EXCEPTION 'Variant not found at location';
    END IF;
    
    IF v_available < p_quantity THEN
        RETURN FALSE;  -- Insufficient stock
    END IF;
    
    -- Move from available to reserved
    UPDATE inventory_levels
    SET available = available - p_quantity,
        reserved = reserved + p_quantity,
        updated_at = NOW()
    WHERE variant_id = p_variant_id AND location_id = p_location_id;
    
    -- Log adjustment
    INSERT INTO inventory_adjustments 
    (variant_id, location_id, adjustment, reason, reference_type, reference_id)
    VALUES 
    (p_variant_id, p_location_id, -p_quantity, 'reserved', 'order', p_order_id);
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- Commit inventory (when order is confirmed/paid)
CREATE OR REPLACE FUNCTION commit_inventory(
    p_variant_id UUID,
    p_location_id UUID,
    p_quantity INT,
    p_order_id UUID
) RETURNS VOID AS $$
BEGIN
    UPDATE inventory_levels
    SET reserved = reserved - p_quantity,
        committed = committed + p_quantity,
        updated_at = NOW()
    WHERE variant_id = p_variant_id AND location_id = p_location_id;
    
    INSERT INTO inventory_adjustments 
    (variant_id, location_id, adjustment, reason, reference_type, reference_id)
    VALUES 
    (p_variant_id, p_location_id, -p_quantity, 'sold', 'order', p_order_id);
END;
$$ LANGUAGE plpgsql;


-- Release reservation (if order cancelled/expired)
CREATE OR REPLACE FUNCTION release_inventory(
    p_variant_id UUID,
    p_location_id UUID,
    p_quantity INT,
    p_order_id UUID
) RETURNS VOID AS $$
BEGIN
    UPDATE inventory_levels
    SET reserved = reserved - p_quantity,
        available = available + p_quantity,
        updated_at = NOW()
    WHERE variant_id = p_variant_id AND location_id = p_location_id;
    
    INSERT INTO inventory_adjustments 
    (variant_id, location_id, adjustment, reason, reference_type, reference_id)
    VALUES 
    (p_variant_id, p_location_id, p_quantity, 'released', 'order', p_order_id);
END;
$$ LANGUAGE plpgsql;
```

---

# Part 5: Redis Cart & Inventory Cache

```python
# ============================================================
# E-COMMERCE REDIS PATTERNS
# ============================================================

import redis
import json
from typing import Optional, Dict, List

class CartService:
    """
    Shopping cart in Redis with PostgreSQL persistence.
    """
    def __init__(self):
        self.redis = redis.Redis()
        self.CART_TTL = 60 * 60 * 24 * 30  # 30 days
    
    def get_cart(self, cart_id: str) -> Dict:
        """Get cart from Redis, fallback to DB."""
        key = f"cart:{cart_id}"
        cart_data = self.redis.get(key)
        
        if cart_data:
            return json.loads(cart_data)
        
        # Fallback to DB and cache
        # cart = db.query(Cart).get(cart_id)
        # self.redis.setex(key, self.CART_TTL, json.dumps(cart.to_dict()))
        return {}
    
    def add_item(self, cart_id: str, variant_id: str, quantity: int) -> Dict:
        """Add item to cart."""
        key = f"cart:{cart_id}"
        items_key = f"cart:{cart_id}:items"
        
        # Add to hash
        self.redis.hincrby(items_key, variant_id, quantity)
        self.redis.expire(items_key, self.CART_TTL)
        
        # Get updated cart
        items = self.redis.hgetall(items_key)
        return {k.decode(): int(v) for k, v in items.items()}
    
    def update_item(self, cart_id: str, variant_id: str, quantity: int):
        """Update item quantity (or remove if 0)."""
        items_key = f"cart:{cart_id}:items"
        
        if quantity <= 0:
            self.redis.hdel(items_key, variant_id)
        else:
            self.redis.hset(items_key, variant_id, quantity)
    
    def clear_cart(self, cart_id: str):
        """Clear cart after checkout."""
        self.redis.delete(f"cart:{cart_id}")
        self.redis.delete(f"cart:{cart_id}:items")


class InventoryCache:
    """
    Real-time inventory cache for flash sales.
    """
    def __init__(self):
        self.redis = redis.Redis()
    
    def get_available(self, variant_id: str, location_id: str) -> int:
        """Get available quantity from cache."""
        key = f"inventory:{variant_id}:{location_id}"
        qty = self.redis.get(key)
        return int(qty) if qty else None
    
    def set_available(self, variant_id: str, location_id: str, quantity: int):
        """Set available quantity (called on CDC update)."""
        key = f"inventory:{variant_id}:{location_id}"
        self.redis.set(key, quantity, ex=300)  # 5 min TTL
    
    def try_reserve(self, variant_id: str, location_id: str, quantity: int) -> bool:
        """
        Attempt atomic reservation for flash sales.
        Uses WATCH/MULTI for optimistic locking.
        """
        key = f"inventory:{variant_id}:{location_id}"
        
        # Use Lua script for atomicity
        lua_script = """
        local current = tonumber(redis.call('GET', KEYS[1]) or 0)
        local quantity = tonumber(ARGV[1])
        if current >= quantity then
            redis.call('DECRBY', KEYS[1], quantity)
            return 1
        else
            return 0
        end
        """
        result = self.redis.eval(lua_script, 1, key, quantity)
        return result == 1
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Multi-tenant by shop_id | shop_id on every table |
| 2 | Atomic inventory reservation | FOR UPDATE + transaction |
| 3 | Price snapshot in orders | order_items.price captured |
| 4 | Variant-level inventory | inventory_levels by variant + location |
| 5 | Cart TTL | 30-day expiry in Redis |
| 6 | Order addresses as JSONB | Snapshot, not foreign key |
| 7 | Inventory audit trail | inventory_adjustments table |
| 8 | Smart collections | JSONB rules for dynamic membership |

---

# Part 7: DynamoDB Single-Table Design

```
============================================================
E-COMMERCE: DynamoDB Single-Table Design
For high-scale catalog and cart management
============================================================

TABLE: ecom_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (shop/collection queries)
- GSI2: GSI2PK / GSI2SK (search/status queries)

============================================================
ENTITY PATTERNS
============================================================

SHOP
  PK: SHOP#{shop_id}
  SK: INFO
  
  Attributes: handle, domain, currency, plan

PRODUCT
  PK: SHOP#{shop_id}
  SK: PROD#{product_id}
  GSI1PK: SHOP#{shop_id}#COLL#{collection_id}
  GSI1SK: PROD#{product_id}
  GSI2PK: SHOP#{shop_id}#STATUS#{status}
  GSI2SK: TITLE#{title}
  
  Attributes: title, handle, vendor, tags, published_at

VARIANT
  PK: PROD#{product_id}
  SK: VAR#{variant_id}
  
  Attributes: title, price, sku, inventory_qty, barcode

CART
  PK: CART#{cart_id}
  SK: META
  
  Attributes: shop_id, customer_id, updated_at

CART_ITEM
  PK: CART#{cart_id}
  SK: ITEM#{variant_id}
  
  Attributes: quantity, price, properties

ORDER
  PK: SHOP#{shop_id}
  SK: ORDER#{order_id}
  GSI1PK: SHOP#{shop_id}#CUST#{customer_id}
  GSI1SK: ORDER#{order_id}
  
  Attributes: order_number, total_price, status, created_at

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get product with all variants
   Table: PK=PROD#{product_id} (BatchGetItem for variants if modeled as PK)
   OR: PK=SHOP#{shop_id}, SK begins_with "PROD#{product_id}"

2. Get products in collection
   GSI1: PK=SHOP#{shop_id}#COLL#{collection_id}

3. Get active products for shop
   GSI2: PK=SHOP#{shop_id}#STATUS#active

4. Get cart items
   Table: PK=CART#{cart_id}, SK begins_with "ITEM#"

5. Get customer order history
   GSI1: PK=SHOP#{shop_id}#CUST#{customer_id}

6. Get shop details by handle (Requires specialized GSI or Lookup table)
   Table: PK=HANDLE#{handle} → shop_id
```

---

# Part 8: Query Examples with EXPLAIN

```sql
-- ============================================================
-- E-COMMERCE QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Product Search with Facets (SQL Fallback)
-- ===========================================

-- NOTE: Usually done in Elasticsearch/Algolia
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    p.id, p.title, p.handle, 
    MIN(v.price) as min_price,
    MAX(v.price) as max_price
FROM products p
JOIN variants v ON v.product_id = p.id
WHERE p.shop_id = $1
  AND p.status = 'active'
  AND p.tags @> ARRAY['summer']
  AND v.price BETWEEN $2 AND $3
GROUP BY p.id
ORDER BY p.published_at DESC
LIMIT 20;

-- Expected: Index scan on idx_products_tags, ~50ms


-- ===========================================
-- QUERY 2: Cart Calculation
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    ci.cart_id,
    SUM(ci.quantity * ci.price) as subtotal_amount,
    COUNT(DISTINCT ci.variant_id) as item_count
FROM cart_items ci
WHERE ci.cart_id = $1
GROUP BY ci.cart_id;

-- Expected: Index scan on idx_cart_items_cart, ~2ms


-- ===========================================
-- QUERY 3: Order History for Customer
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    o.id, o.order_number, o.created_at, 
    o.total_price, o.financial_status, o.fulfillment_status,
    (SELECT json_agg(jsonb_build_object('title', oi.title, 'qty', oi.quantity)) 
     FROM order_items oi WHERE oi.order_id = o.id) as items
FROM orders o
WHERE o.shop_id = $1
  AND o.customer_id = $2
ORDER BY o.created_at DESC
LIMIT 10;

-- Expected: Index scan on idx_orders_customer, ~10ms


-- ===========================================
-- QUERY 4: Inventory Availability Check
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    il.location_id,
    l.name as location_name,
    il.available
FROM inventory_levels il
JOIN locations l ON l.id = il.location_id
WHERE il.variant_id = $1
  AND il.available >= $2
ORDER BY il.available DESC;

-- Expected: Index scan on idx_inventory_variant, ~1ms


-- ===========================================
-- QUERY 5: Sales Report by Product
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    p.title,
    SUM(oi.quantity) as units_sold,
    SUM(oi.price * oi.quantity) as revenue
FROM order_items oi
JOIN products p ON p.id = oi.product_id
JOIN orders o ON o.id = oi.order_id
WHERE o.shop_id = $1
  AND o.created_at >= NOW() - INTERVAL '30 days'
  AND o.financial_status = 'paid'
GROUP BY p.id
ORDER BY revenue DESC
LIMIT 20;

-- Expected: Expensive aggregation, run on Read Replica ~100ms
```

---

# Part 9: Capacity Planning

```
============================================================
E-COMMERCE CAPACITY PLANNING
============================================================

ASSUMPTIONS (Shopify Scale):
- 1M Merchants (Tenants)
- 100M Products
- 1B Orders/Year
- Peak Traffic (BFCM): 100K requests/sec

============================================================
STORAGE ESTIMATES
============================================================

SHOPS
  Rows: 1M
  Size: ~500 MB (RAM Cacheable)

PRODUCTS
  Rows: 100M
  Row Size: ~1KB
  Total: ~100 GB

VARIANTS
  Rows: 500M (5 per product)
  Total: ~200 GB

ORDERS
  Rows: 1B/year
  Row Size: ~1KB
  Total: ~1 TB/year

ORDER_ITEMS
  Rows: 3B/year (3 per order)
  Row Size: ~200 bytes
  Total: ~600 GB/year

INVENTORY
  Rows: 500M variants * 2 locations = 1B rows
  Total: ~100 GB (Hot!)

============================================================
SHARDING STRATEGY
============================================================

SHARD KEY: shop_id
- All data for a single shop resides on one shard.
- Ensures JOINs work correctly.
- Isolation of noisy neighbors.

HOT SHOPS (Flash Sales):
- "Podding" architecture (Shopify).
- Move large merchants to dedicated pods (isolated DB resources).
- Read replicas scale horizontally.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

CHECKOUT:
- 100K checkouts/min = 1.6K TPS
- Requires high-performance inventory Locking (Redis/Postgres).

BROWSING:
- 90% traffic is Read (Product pages).
- CDN captures 99% of static hits.
- Redis/Memcached captures 90% of dynamic hits.

INVENTORY UPDATES:
- Millions of updates/sec during flash sales.
- Async inventory sync to search index (2-5s delay acceptable for search, 0s for checkout).
```

---

# Part 10: Anti-Patterns to Avoid

```
============================================================
E-COMMERCE ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Decrementing Inventory in Cart
-----------------------------------------
WRONG:
  User adds to cart -> Inventory -1.
  -- Users abandon carts 70% of the time. Stock locked up forever.
  
RIGHT:
  -- Reserve only at "Proceed to Checkout" or "Pay".
  -- Release reservation after 5-10 min timeout.


❌ ANTI-PATTERN 2: Mutating Product Prices on Orders
-----------------------------------------
WRONG:
  JOIN products p ON order_items.product_id = p.id
  SELECT p.price ...
  -- Price changed yesterday. Old orders now show wrong total.
  
RIGHT:
  -- Copy price to `order_items.price` at moment of purchase.
  -- Order is an immutable snapshot.


❌ ANTI-PATTERN 3: Storing Money as Float
-----------------------------------------
WRONG:
  price FLOAT = 19.99
  -- Floating point math errors: 19.99 * 3 = 59.970000004
  
RIGHT:
  -- Use INTEGER (cents): 1999
  -- Or DECIMAL(10, 2)


❌ ANTI-PATTERN 4: Synchronous Fulfillment Integration
-----------------------------------------
WRONG:
  Checkout -> Call DHL API -> Success
  -- DHL API down? User can't buy.
  
RIGHT:
  -- Checkout -> DB "pending_fulfillment".
  -- Background Job -> Call DHL API.


❌ ANTI-PATTERN 5: One Big "Inventory" Table
-----------------------------------------
WRONG:
  products.quantity (INT)
  -- Can't track multiple warehouses (New York, London).
  
RIGHT:
  -- `inventory_levels` (variant_id, location_id, qty).
  -- Enables multi-location fulfillment.


❌ ANTI-PATTERN 6: Overselling via Race Conditions
-----------------------------------------
WRONG:
  qty = SELECT available FROM inventory WHERE id = 1;
  if qty > 0: UPDATE inventory SET available = qty - 1;
  -- Two users read "1" at same time. Both buy. Stock becomes -1.
  
RIGHT:
  -- UPDATE inventory SET available = available - 1 
     WHERE id = 1 AND available > 0;
  -- Or SELECT ... FOR UPDATE.


❌ ANTI-PATTERN 7: Hard Deleting Products
-----------------------------------------
WRONG:
  DELETE FROM products WHERE id = 1;
  -- Order history breaks (Foreign Key constraint fails).
  
RIGHT:
  -- Soft Delete: `status = 'archived'`.
  -- Ignore archived products in search queries.


❌ ANTI-PATTERN 8: User Address References
-----------------------------------------
WRONG:
  orders.shipping_address_id -> customer_addresses.id
  -- User moves, updates profile. 
  -- Old order now shows new home address!
  
RIGHT:
  -- Copy address snapshot to `orders` table (JSONB).
  -- Immutable history.


❌ ANTI-PATTERN 9: Calculating Cart Totals in Client
-----------------------------------------
WRONG:
  Client sends: { total: $500 }
  -- User hacks JS, sends $0.01
  
RIGHT:
  -- Server recalculates total from DB prices.
  -- Compare calculated total with payment authorization.


❌ ANTI-PATTERN 10: Missing Idempotency on Payments
-----------------------------------------
WRONG:
  POST /charge (network retry) -> Charged twice.
  
RIGHT:
  -- Idempotency Key (UUID) sent with request.
  -- Payment gateway ensures single charge.
```

---

# Part 11: CDC & Event Streaming

```
============================================================
E-COMMERCE CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (primary)   │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │Elasticsearch│   │ Inventory │   │ Email/SMS │  │ Analytics│
  │ (catalog)   │   │ Broadcast │   │ (receipts)│  │ (Revenue)│
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- ecom.orders.created     (Trigger fulfillment, receipt)
- ecom.products.updated   (Update search index)
- ecom.inventory.changed  (Update "Low Stock" badge, Ads)
- ecom.customers.created  (Welcome email)

============================================================
DISASTER RECOVERY
============================================================

RPO: < 1 minute (Zero for committed orders)
RTO: < 15 minutes

STRATEGY:
1. Multi-Region Replication
   - Sync replication to local standby (AZ-failover).
   - Async replication to DR region (Regional-failover).

2. Order Reliability
   - If DB is down, queue orders in Kafka/SQS? 
   - NO: Don't take money if you can't record order.
   - Fail mode: "Maintenance Page" or Read-Only mode.

3. Backups
   - Point-in-time recovery (PITR) enabled.
   - Daily snapshots to S3 Glacier/Deep Archive.
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- E-COMMERCE: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / CHANGE HISTORY
-- ===========================================

CREATE TABLE entity_change_log (
    id                  BIGSERIAL PRIMARY KEY,
    shop_id             UUID NOT NULL,
    entity_type         VARCHAR(50) NOT NULL,  -- 'product', 'order', 'inventory'
    entity_id           UUID NOT NULL,
    field_name          VARCHAR(100) NOT NULL,
    old_value           TEXT,
    new_value           TEXT,
    changed_by_id       UUID NOT NULL,
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    change_source       VARCHAR(50),  -- 'admin', 'api', 'bulk_import', 'sync'
    ip_address          INET
) PARTITION BY RANGE (changed_at);

CREATE INDEX idx_ecl_entity ON entity_change_log(shop_id, entity_type, entity_id);


-- ===========================================
-- B. PRODUCT MEDIA
-- ===========================================

CREATE TABLE product_media (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id          UUID NOT NULL REFERENCES products(id),
    variant_id          UUID REFERENCES product_variants(id),
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    width               INT,
    height              INT,
    storage_key         VARCHAR(500) NOT NULL,
    cdn_url             VARCHAR(500),
    alt_text            VARCHAR(255),
    display_order       INT DEFAULT 0,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_media_product ON product_media(product_id, display_order);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    shop_id             UUID NOT NULL,
    user_id             UUID,
    channel             VARCHAR(20) NOT NULL,
    recipient           VARCHAR(255) NOT NULL,
    notification_type   VARCHAR(100) NOT NULL,  -- 'order_shipped', 'back_in_stock'
    subject             VARCHAR(255),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id             UUID NOT NULL,
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['order.created', 'product.updated']
    api_version         VARCHAR(20),
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
-- E. API KEYS
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id             UUID NOT NULL,
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 40,  -- Shopify-style limit
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
    shop_id             UUID,
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
    allowed_shop_ids    UUID[],
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
E-COMMERCE: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. INVENTORY LOCKING (THE "FLASH SALE" PROBLEM)
============================================================

THE CHALLENGE:
PS5 Launch. 1000 units. 1 Million concurrent buyers.
`UPDATE inventory SET count = count - 1 WHERE id = ? AND count > 0`
Postgres cannot handle 1M TPS lock contention on a single row.

SOLUTION: REDIS SEMAPHORE + ASYNC DB
1. **Reservation Phase (Redis)**:
   - `DECR inventory:item:123`.
   - Result >= 0? Success. Lock expiry 10 mins.
   - Result < 0? "Sold Out".
2. **Checkout Phase**:
   - User pays.
   - Worker decreases Postgres Inventory asynchronously.
   - "Ghost Stock" risk: Redis crashes. Reconciliation job fixes drift.

ALTERNATIVE: INVENTORY SHARDING
Split 1000 units into 10 rows of 100.
Randomly select row to decrement.

============================================================
2. CATALOG CACHING & SEARCH
============================================================

THE CHALLENGE:
Product pages are 90% read traffic.
Price/Availability changes frequently.

ARCHITECTURE:
- **L1 Cache (Edge/CDN)**: HTML for anon users. TTL 60s. Purge on Update.
- **L2 Cache (Redis)**: Product JSON objects.
- **L3 DB (Read Replicas)**: Powering listings.

STALE-WHILE-REVALIDATE:
- Serve stale price (cached) but fetch fresh price in background.
- "Add to Cart" validation: The "Source of Truth" check happens ONLY at cart addition phase.

============================================================
3. CART ABANDONMENT RECOVERY
============================================================

DATA LIFECYCLE:
- Active Cart: Redis Hash `cart:{session_id}`. TTL 7 days.
- Abandoned Cart: After 1h inactivity -> Move to Postgres `abandoned_carts`.
- Recovery Job: Scanner picks up rows -> Emails "You forgot this!".
- Conversion: If user returns, "Rehydrate" Redis session from Postgres.

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Checkout Success Rate        │ > 99.5% │ < 99.0% = PAGE  │
│  Product Page One-Step Latency│ < 500ms │ > 1s = WARN     │
│  Payment Gateway Latency      │ < 3s    │ > 5s = WARN     │
│  Inventory Oversell Rate      │ 0       │ > 0 = PAGE      │
└─────────────────────────────────────────────────────────────┘

BUSINESS METRICS:
- `GMV_per_minute`: Sudden drop = Outage (even if servers are up).
- `Add_to_Cart_Rate`: UX issues indicator.

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: "OVERSOLD INVENTORY"
Symptom: Sold 1005 units of 1000 stock.
Mitigation:
- "Safety Stock": Always hide 1% of inventory.
- CS Tool: Auto-refund last 5 buyers + $10 coupon apology.

SCENARIO 2: BOT SCALPERS
Symptom: 100% of stock bought in 0.1s by 1 IP.
Mitigation:
- **Queue-it**: Virtual Waiting Room.
- **POW (Proof of Work)**: Client solves JS puzzle before Add-to-Cart.
- Limit 1 per Customer (Hash card fingerprint).

SCENARIO 3: PRICING ERROR
Symptom: $1000 TV listed for $10.
Mitigation:
- "Sanity Check" Guardrail: Block price drops > 50% without Manager Approval.
- Velocity Alert: If sales > 100x normal, killswitch product.

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

IMAGE OPTIMIZATION:
- E-commerce is image heavy.
- Next-Gen Formats: Serve AVIF/WebP.
- Responsive Sizing: Don't serve 4k image to mobile.

LOGISTICS COSTS:
- Address Validation API (shippo/easypost): Validate address BEFORE checkout to prevent failed deliveries (return shipping is expensive).
```

---

## 🔗 Related Documents

- [DoorDash Schema](./doordash-schema-design-guide.md) — Similar order/inventory pattern
- [Stripe Schema](./stripe-schema-design-guide.md) — Payment integration
- [Database Scaling](./database-scaling-guide.md) — Sharding by shop_id

