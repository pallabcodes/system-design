-- Logistics Industry Database Schema Design
-- Comprehensive PostgreSQL schema for logistics and supply chain management
-- Includes inventory, orders, shipping, transportation, and warehouse management

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "postgis";  -- For geospatial data
CREATE EXTENSION IF NOT EXISTS "ltree";    -- For hierarchical location structures

-- ===========================================
-- CORE ENTITIES
-- ===========================================

-- Companies and Organizations
CREATE TABLE companies (
    company_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_name VARCHAR(255) NOT NULL,
    company_type VARCHAR(50) NOT NULL
        CHECK (company_type IN ('manufacturer', 'distributor', 'retailer', 'carrier', 'warehouse', '3pl_provider')),
    tax_id VARCHAR(50) UNIQUE,
    registration_number VARCHAR(100),

    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(20),
    website VARCHAR(255),

    -- Address
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(50) DEFAULT 'USA',

    -- Status and Compliance
    is_active BOOLEAN DEFAULT TRUE,
    compliance_status VARCHAR(20) DEFAULT 'pending'
        CHECK (compliance_status IN ('pending', 'approved', 'suspended', 'revoked')),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Locations and Facilities
CREATE TABLE locations (
    location_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Location Details
    location_name VARCHAR(255) NOT NULL,
    location_type VARCHAR(50) NOT NULL
        CHECK (location_type IN ('warehouse', 'distribution_center', 'store', 'manufacturing', 'port', 'airport')),

    -- Address and Geospatial
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(50) DEFAULT 'USA',
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOMETRY(Point, 4326),

    -- Operational Details
    timezone VARCHAR(50) DEFAULT 'UTC',
    operating_hours JSONB,  -- {'monday': {'open': '09:00', 'close': '17:00'}}
    total_area_sqft INTEGER,
    storage_capacity_cuft BIGINT,

    -- Capabilities
    capabilities JSONB,  -- ['hazmat', 'refrigerated', 'secure', 'cross_dock']

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Hierarchical structure (for multi-level warehouses)
    parent_location_id UUID REFERENCES locations(location_id),
    location_path LTREE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (company_id, location_name)
);

-- ===========================================
-- PRODUCT AND INVENTORY MANAGEMENT
-- ===========================================

-- Products
CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Product Information
    product_name VARCHAR(255) NOT NULL,
    product_description TEXT,
    sku VARCHAR(100) UNIQUE NOT NULL,
    upc VARCHAR(20),
    product_category VARCHAR(100),

    -- Physical Properties
    weight_lbs DECIMAL(10,2),
    length_inches DECIMAL(8,2),
    width_inches DECIMAL(8,2),
    height_inches DECIMAL(8,2),
    volume_cuft DECIMAL(10,4) GENERATED ALWAYS AS (
        (length_inches * width_inches * height_inches) / 1728
    ) STORED,

    -- Classification
    is_hazmat BOOLEAN DEFAULT FALSE,
    hazmat_class VARCHAR(10),
    requires_refrigeration BOOLEAN DEFAULT FALSE,
    storage_temperature_range VARCHAR(50),  -- '-20°C to 5°C'

    -- Economic Properties
    unit_cost DECIMAL(10,2),
    unit_price DECIMAL(10,2),
    currency_code CHAR(3) DEFAULT 'USD',

    -- Packaging
    packaging_type VARCHAR(50),  -- 'box', 'pallet', 'bulk', etc.
    units_per_package INTEGER DEFAULT 1,
    package_weight_lbs DECIMAL(8,2),
    package_volume_cuft DECIMAL(10,4),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Inventory Management
CREATE TABLE inventory (
    inventory_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    location_id UUID NOT NULL REFERENCES locations(location_id),
    product_id UUID NOT NULL REFERENCES products(product_id),

    -- Inventory Levels
    quantity_on_hand INTEGER DEFAULT 0,
    quantity_allocated INTEGER DEFAULT 0,
    quantity_available INTEGER GENERATED ALWAYS AS (
        quantity_on_hand - quantity_allocated
    ) STORED,

    -- Quality and Status
    inventory_status VARCHAR(20) DEFAULT 'available'
        CHECK (inventory_status IN ('available', 'reserved', 'damaged', 'expired', 'quarantined')),

    -- Storage Details
    storage_location VARCHAR(100),  -- Aisle, shelf, bin location
    lot_number VARCHAR(50),
    serial_numbers TEXT[],  -- For serialized items
    expiration_date DATE,

    -- Cost and Valuation
    unit_cost DECIMAL(10,2),
    total_value DECIMAL(12,2) GENERATED ALWAYS AS (
        quantity_on_hand * unit_cost
    ) STORED,

    -- Reordering
    reorder_point INTEGER,
    reorder_quantity INTEGER,
    safety_stock INTEGER,

    -- Last Activity
    last_count_date DATE,
    last_movement_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (location_id, product_id, lot_number)
);

-- ===========================================
-- ORDER MANAGEMENT
-- ===========================================

-- Sales Orders
CREATE TABLE sales_orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Order Information
    order_number VARCHAR(50) UNIQUE NOT NULL,
    order_type VARCHAR(20) DEFAULT 'standard'
        CHECK (order_type IN ('standard', 'rush', 'backorder', 'transfer', 'return')),

    -- Parties Involved
    customer_id UUID NOT NULL REFERENCES companies(company_id),
    bill_to_location_id UUID REFERENCES locations(location_id),
    ship_to_location_id UUID REFERENCES locations(location_id),

    -- Order Details
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    requested_ship_date DATE,
    promised_ship_date DATE,
    actual_ship_date DATE,

    -- Financial
    subtotal_amount DECIMAL(12,2),
    tax_amount DECIMAL(10,2),
    shipping_amount DECIMAL(10,2),
    discount_amount DECIMAL(10,2),
    total_amount DECIMAL(12,2) GENERATED ALWAYS AS (
        COALESCE(subtotal_amount, 0) + COALESCE(tax_amount, 0) +
        COALESCE(shipping_amount, 0) - COALESCE(discount_amount, 0)
    ) STORED,

    currency_code CHAR(3) DEFAULT 'USD',

    -- Status
    order_status VARCHAR(30) DEFAULT 'draft'
        CHECK (order_status IN ('draft', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'returned')),

    -- Shipping Preferences
    shipping_method VARCHAR(50),
    carrier_id UUID REFERENCES companies(company_id),
    tracking_number VARCHAR(100),

    -- Special Instructions
    customer_notes TEXT,
    internal_notes TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id)
);

-- Order Line Items
CREATE TABLE order_line_items (
    line_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES sales_orders(order_id) ON DELETE CASCADE,

    -- Product Information
    product_id UUID NOT NULL REFERENCES products(product_id),
    product_sku VARCHAR(100),
    product_name VARCHAR(255),

    -- Quantities
    ordered_quantity INTEGER NOT NULL,
    shipped_quantity INTEGER DEFAULT 0,
    backordered_quantity INTEGER DEFAULT 0,
    cancelled_quantity INTEGER DEFAULT 0,

    -- Pricing
    unit_price DECIMAL(10,2) NOT NULL,
    line_total DECIMAL(12,2) GENERATED ALWAYS AS (
        ordered_quantity * unit_price
    ) STORED,

    -- Status
    line_status VARCHAR(20) DEFAULT 'open'
        CHECK (line_status IN ('open', 'shipped', 'backordered', 'cancelled', 'returned')),

    -- Delivery Schedule
    requested_delivery_date DATE,
    promised_delivery_date DATE,
    actual_delivery_date DATE,

    -- Special Requirements
    special_instructions TEXT,
    quality_requirements JSONB,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SHIPPING AND TRANSPORTATION
-- ===========================================

-- Shipments
CREATE TABLE shipments (
    shipment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES sales_orders(order_id),

    -- Shipment Details
    shipment_number VARCHAR(50) UNIQUE NOT NULL,
    shipment_type VARCHAR(20) DEFAULT 'outbound'
        CHECK (shipment_type IN ('inbound', 'outbound', 'transfer', 'return')),

    -- Carrier and Transportation
    carrier_id UUID NOT NULL REFERENCES companies(company_id),
    carrier_service_type VARCHAR(50),  -- 'ground', 'air', 'ocean', 'express'
    tracking_number VARCHAR(100),
    pro_number VARCHAR(50),  -- Carrier's shipment number

    -- Origin and Destination
    origin_location_id UUID NOT NULL REFERENCES locations(location_id),
    destination_location_id UUID NOT NULL REFERENCES locations(location_id),

    -- Dates and Times
    ship_date TIMESTAMP WITH TIME ZONE,
    estimated_delivery_date TIMESTAMP WITH TIME ZONE,
    actual_delivery_date TIMESTAMP WITH TIME ZONE,
    delivered_by UUID REFERENCES users(user_id),

    -- Shipment Contents
    total_weight_lbs DECIMAL(10,2),
    total_volume_cuft DECIMAL(12,4),
    package_count INTEGER,
    pallet_count INTEGER,

    -- Cost and Billing
    shipping_cost DECIMAL(10,2),
    fuel_surcharge DECIMAL(8,2),
    insurance_cost DECIMAL(8,2),

    -- Status and Tracking
    shipment_status VARCHAR(30) DEFAULT 'created'
        CHECK (shipment_status IN ('created', 'packed', 'loaded', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')),

    -- Current Location (for tracking)
    current_location GEOMETRY(Point, 4326),
    last_location_update TIMESTAMP WITH TIME ZONE,

    -- Exception Handling
    exception_code VARCHAR(20),
    exception_description TEXT,
    exception_date TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id)
);

-- Shipment Items
CREATE TABLE shipment_items (
    shipment_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shipment_id UUID NOT NULL REFERENCES shipments(shipment_id) ON DELETE CASCADE,
    order_line_item_id UUID REFERENCES order_line_items(line_item_id),

    -- Product Information
    product_id UUID NOT NULL REFERENCES products(product_id),
    product_name VARCHAR(255),
    product_sku VARCHAR(100),

    -- Quantities
    shipped_quantity INTEGER NOT NULL,
    received_quantity INTEGER,
    damaged_quantity INTEGER DEFAULT 0,

    -- Packaging
    package_type VARCHAR(50),
    package_id VARCHAR(50),  -- SSCC-18 barcode
    serial_numbers TEXT[],

    -- Quality Control
    quality_check_passed BOOLEAN,
    quality_notes TEXT,
    inspected_by UUID REFERENCES users(user_id),
    inspection_date TIMESTAMP WITH TIME ZONE,

    UNIQUE (shipment_id, order_line_item_id)
);

-- Transportation Assets
CREATE TABLE vehicles (
    vehicle_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Vehicle Information
    vehicle_number VARCHAR(50) UNIQUE NOT NULL,
    license_plate VARCHAR(20) UNIQUE NOT NULL,
    vehicle_type VARCHAR(30) NOT NULL
        CHECK (vehicle_type IN ('truck', 'trailer', 'van', 'railcar', 'aircraft', 'ship')),

    -- Specifications
    make VARCHAR(50),
    model VARCHAR(50),
    year INTEGER,
    capacity_weight_lbs INTEGER,
    capacity_volume_cuft INTEGER,

    -- Equipment and Features
    equipment JSONB,  -- ['refrigerated', 'hazmat_certified', 'gps_tracking']
    fuel_type VARCHAR(20) DEFAULT 'diesel',

    -- Status and Maintenance
    vehicle_status VARCHAR(20) DEFAULT 'active'
        CHECK (vehicle_status IN ('active', 'maintenance', 'out_of_service', 'retired')),

    last_maintenance_date DATE,
    next_maintenance_date DATE,
    mileage INTEGER,

    -- Location Tracking
    current_location GEOMETRY(Point, 4326),
    last_location_update TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Routes and Trips
CREATE TABLE routes (
    route_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Route Information
    route_name VARCHAR(255) NOT NULL,
    route_type VARCHAR(30) NOT NULL
        CHECK (route_type IN ('local_delivery', 'regional', 'cross_country', 'international')),

    -- Route Details
    origin_location_id UUID NOT NULL REFERENCES locations(location_id),
    destination_location_id UUID NOT NULL REFERENCES locations(location_id),
    distance_miles INTEGER,
    estimated_duration_hours DECIMAL(6,2),

    -- Route Geometry (for mapping)
    route_geometry GEOMETRY(LineString, 4326),

    -- Cost and Optimization
    fuel_cost_per_mile DECIMAL(6,2),
    labor_cost_per_hour DECIMAL(8,2),
    total_route_cost DECIMAL(10,2),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- WAREHOUSE MANAGEMENT
-- ===========================================

-- Warehouse Zones and Locations
CREATE TABLE warehouse_zones (
    zone_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    location_id UUID NOT NULL REFERENCES locations(location_id),

    -- Zone Information
    zone_name VARCHAR(100) NOT NULL,
    zone_type VARCHAR(30) NOT NULL
        CHECK (zone_type IN ('receiving', 'storage', 'picking', 'packing', 'shipping', 'quarantine')),

    -- Physical Layout
    aisle_prefix VARCHAR(10),
    aisle_range_start INTEGER,
    aisle_range_end INTEGER,
    level_range_start INTEGER,
    level_range_end INTEGER,

    -- Capacity and Utilization
    total_slots INTEGER,
    occupied_slots INTEGER DEFAULT 0,
    utilization_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN total_slots > 0 THEN (occupied_slots::DECIMAL / total_slots) * 100 ELSE 0 END
    ) STORED,

    -- Environmental Conditions
    temperature_range VARCHAR(20),
    humidity_range VARCHAR(20),
    security_level VARCHAR(20),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    UNIQUE (location_id, zone_name)
);

-- Storage Locations (bins, shelves, etc.)
CREATE TABLE storage_locations (
    storage_location_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    zone_id UUID NOT NULL REFERENCES warehouse_zones(zone_id),

    -- Location Details
    location_code VARCHAR(50) UNIQUE NOT NULL,  -- A01-L02-P03
    location_type VARCHAR(20) DEFAULT 'bin'
        CHECK (location_type IN ('bin', 'shelf', 'pallet_rack', 'floor', 'bulk')),

    -- Dimensions and Capacity
    max_weight_lbs INTEGER,
    max_volume_cuft DECIMAL(8,2),
    max_items INTEGER,

    -- Current Utilization
    current_weight_lbs DECIMAL(8,2) DEFAULT 0,
    current_volume_cuft DECIMAL(8,2) DEFAULT 0,
    current_items INTEGER DEFAULT 0,

    -- Status and Availability
    location_status VARCHAR(20) DEFAULT 'available'
        CHECK (location_status IN ('available', 'occupied', 'reserved', 'maintenance', 'damaged')),

    -- Product Compatibility
    allowed_product_categories TEXT[],
    restricted_products TEXT[],

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Inventory Movements
CREATE TABLE inventory_movements (
    movement_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    inventory_id UUID NOT NULL REFERENCES inventory(inventory_id),

    -- Movement Details
    movement_type VARCHAR(30) NOT NULL
        CHECK (movement_type IN ('receipt', 'putaway', 'transfer', 'picking', 'shipping', 'adjustment', 'cycle_count')),

    -- Quantities
    quantity_changed INTEGER NOT NULL,
    quantity_before INTEGER,
    quantity_after INTEGER,

    -- Locations
    from_storage_location_id UUID REFERENCES storage_locations(storage_location_id),
    to_storage_location_id UUID REFERENCES storage_locations(storage_location_id),

    -- Related Documents
    order_id UUID REFERENCES sales_orders(order_id),
    shipment_id UUID REFERENCES shipments(shipment_id),
    adjustment_reason TEXT,

    -- Quality and Notes
    movement_notes TEXT,
    quality_check_required BOOLEAN DEFAULT FALSE,
    quality_check_passed BOOLEAN,

    -- Performed By
    performed_by UUID NOT NULL REFERENCES users(user_id),
    performed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SUPPLY CHAIN MANAGEMENT
-- ===========================================

-- Purchase Orders
CREATE TABLE purchase_orders (
    po_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Order Information
    po_number VARCHAR(50) UNIQUE NOT NULL,
    supplier_id UUID NOT NULL REFERENCES companies(company_id),

    -- Dates
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    requested_delivery_date DATE,
    promised_delivery_date DATE,
    actual_delivery_date DATE,

    -- Financial
    subtotal_amount DECIMAL(12,2),
    tax_amount DECIMAL(10,2),
    shipping_amount DECIMAL(10,2),
    total_amount DECIMAL(12,2),

    -- Status
    po_status VARCHAR(20) DEFAULT 'draft'
        CHECK (po_status IN ('draft', 'approved', 'ordered', 'partial_receipt', 'received', 'cancelled')),

    -- Terms and Conditions
    payment_terms VARCHAR(100),
    shipping_terms VARCHAR(100),
    special_instructions TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    approved_at TIMESTAMP WITH TIME ZONE,
    approved_by UUID REFERENCES users(user_id)
);

-- Purchase Order Line Items
CREATE TABLE po_line_items (
    po_line_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id UUID NOT NULL REFERENCES purchase_orders(po_id) ON DELETE CASCADE,

    -- Product Information
    product_id UUID NOT NULL REFERENCES products(product_id),
    product_name VARCHAR(255),
    product_sku VARCHAR(100),

    -- Quantities
    ordered_quantity INTEGER NOT NULL,
    received_quantity INTEGER DEFAULT 0,
    rejected_quantity INTEGER DEFAULT 0,

    -- Pricing
    unit_cost DECIMAL(10,2) NOT NULL,
    line_total DECIMAL(12,2) GENERATED ALWAYS AS (
        ordered_quantity * unit_cost
    ) STORED,

    -- Delivery Schedule
    requested_delivery_date DATE,
    actual_delivery_date DATE,

    -- Quality Requirements
    quality_specifications TEXT,
    inspection_required BOOLEAN DEFAULT FALSE,

    -- Status
    line_status VARCHAR(20) DEFAULT 'open'
        CHECK (line_status IN ('open', 'partial', 'received', 'rejected', 'cancelled'))
);

-- Suppliers and Vendors
CREATE TABLE suppliers (
    supplier_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Supplier Information
    supplier_name VARCHAR(255) NOT NULL,
    supplier_type VARCHAR(30) DEFAULT 'manufacturer'
        CHECK (supplier_type IN ('manufacturer', 'distributor', 'importer', 'service_provider')),

    -- Contact Information
    contact_person VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(20),

    -- Performance Metrics
    on_time_delivery_rate DECIMAL(5,2),
    quality_rating DECIMAL(3,1),
    average_lead_time_days INTEGER,

    -- Contract Information
    contract_start_date DATE,
    contract_end_date DATE,
    payment_terms VARCHAR(50),

    -- Status
    supplier_status VARCHAR(20) DEFAULT 'active'
        CHECK (supplier_status IN ('active', 'inactive', 'suspended', 'terminated')),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

-- Inventory Analytics
CREATE TABLE inventory_analytics (
    analytic_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    location_id UUID NOT NULL REFERENCES locations(location_id),

    -- Time Period
    date_recorded DATE DEFAULT CURRENT_DATE,
    week_start DATE,

    -- Inventory Metrics
    total_sku_count INTEGER,
    total_quantity BIGINT,
    total_value DECIMAL(15,2),

    -- Turnover and Velocity
    inventory_turnover_ratio DECIMAL(6,2),
    sell_through_rate DECIMAL(5,2),
    stockout_rate DECIMAL(5,2),

    -- Age Analysis
    aged_30_days_quantity BIGINT,
    aged_90_days_quantity BIGINT,
    aged_365_days_quantity BIGINT,

    -- ABC Analysis
    a_items_count INTEGER,
    b_items_count INTEGER,
    c_items_count INTEGER,

    UNIQUE (location_id, date_recorded)
) PARTITION BY RANGE (date_recorded);

-- Order Fulfillment Analytics
CREATE TABLE fulfillment_analytics (
    analytic_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Time Period
    date_recorded DATE DEFAULT CURRENT_DATE,
    month_year DATE,

    -- Order Metrics
    orders_received INTEGER DEFAULT 0,
    orders_shipped INTEGER DEFAULT 0,
    orders_delivered INTEGER DEFAULT 0,
    orders_cancelled INTEGER DEFAULT 0,

    -- Performance Metrics
    on_time_delivery_rate DECIMAL(5,2),
    order_accuracy_rate DECIMAL(5,2),
    average_order_processing_time_hours DECIMAL(6,2),
    average_shipping_time_days DECIMAL(4,1),

    -- Cost Metrics
    total_shipping_cost DECIMAL(12,2),
    cost_per_order DECIMAL(8,2),
    cost_per_item DECIMAL(6,2),

    -- Quality Metrics
    damage_rate DECIMAL(5,2),
    return_rate DECIMAL(5,2),

    UNIQUE (company_id, date_recorded)
) PARTITION BY RANGE (date_recorded);

-- ===========================================
-- USERS AND PERMISSIONS
-- ===========================================

-- System Users
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- User Information
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(200) NOT NULL,

    -- Authentication
    password_hash VARCHAR(255),
    two_factor_enabled BOOLEAN DEFAULT FALSE,

    -- Role and Department
    user_role VARCHAR(30) NOT NULL
        CHECK (user_role IN ('admin', 'manager', 'supervisor', 'operator', 'driver', 'warehouse_staff', 'analyst')),
    department VARCHAR(50),
    location_id UUID REFERENCES locations(location_id),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Core company and location indexes
CREATE INDEX idx_companies_type_status ON companies (company_type, is_active);
CREATE INDEX idx_locations_company_type ON locations (company_id, location_type);
CREATE INDEX idx_locations_geolocation ON locations USING gist (geolocation);

-- Product and inventory indexes
CREATE INDEX idx_products_company_category ON products (company_id, product_category);
CREATE INDEX idx_products_sku ON products (sku);
CREATE INDEX idx_inventory_location_product ON inventory (location_id, product_id);
CREATE INDEX idx_inventory_status ON inventory (inventory_status);

-- Order management indexes
CREATE INDEX idx_sales_orders_company_status ON sales_orders (company_id, order_status);
CREATE INDEX idx_sales_orders_dates ON sales_orders (order_date, requested_ship_date);
CREATE INDEX idx_order_line_items_order ON order_line_items (order_id);
CREATE INDEX idx_order_line_items_product ON order_line_items (product_id);

-- Shipping and transportation indexes
CREATE INDEX idx_shipments_order ON shipments (order_id);
CREATE INDEX idx_shipments_carrier_status ON shipments (carrier_id, shipment_status);
CREATE INDEX idx_shipments_tracking ON shipments (tracking_number);
CREATE INDEX idx_shipment_items_shipment ON shipment_items (shipment_id);
CREATE INDEX idx_vehicles_company_status ON vehicles (company_id, vehicle_status);

-- Warehouse management indexes
CREATE INDEX idx_warehouse_zones_location ON warehouse_zones (location_id, zone_type);
CREATE INDEX idx_storage_locations_zone ON storage_locations (zone_id, location_status);
CREATE INDEX idx_inventory_movements_inventory ON inventory_movements (inventory_id, performed_at DESC);
CREATE INDEX idx_inventory_movements_type ON inventory_movements (movement_type, performed_at DESC);

-- Analytics indexes
CREATE INDEX idx_inventory_analytics_location ON inventory_analytics (location_id, date_recorded DESC);
CREATE INDEX idx_fulfillment_analytics_company ON fulfillment_analytics (company_id, date_recorded DESC);

-- User and security indexes
CREATE INDEX idx_users_company_role ON users (company_id, user_role);
CREATE INDEX idx_users_username_email ON users (username, email);

-- ===========================================
-- PARTITIONING SETUP
-- ===========================================

-- Analytics partitioning (monthly)
CREATE TABLE inventory_analytics_2024_01 PARTITION OF inventory_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE fulfillment_analytics_2024_01 PARTITION OF fulfillment_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Inventory Summary View
CREATE VIEW inventory_summary AS
SELECT
    l.location_name,
    p.product_name,
    p.sku,
    i.quantity_on_hand,
    i.quantity_available,
    i.unit_cost,
    i.total_value,
    i.reorder_point,
    CASE
        WHEN i.quantity_available <= i.reorder_point THEN 'REORDER'
        WHEN i.quantity_available <= i.safety_stock THEN 'LOW_STOCK'
        ELSE 'NORMAL'
    END AS stock_status
FROM inventory i
JOIN locations l ON i.location_id = l.location_id
JOIN products p ON i.product_id = p.product_id
WHERE i.inventory_status = 'available';

-- Order Fulfillment Status View
CREATE VIEW order_fulfillment_status AS
SELECT
    so.order_number,
    so.order_date,
    so.requested_ship_date,
    so.order_status,
    c.company_name AS customer_name,
    COUNT(oli.line_item_id) AS total_lines,
    COUNT(CASE WHEN oli.line_status = 'shipped' THEN 1 END) AS shipped_lines,
    COUNT(CASE WHEN oli.line_status = 'backordered' THEN 1 END) AS backordered_lines,
    SUM(oli.ordered_quantity) AS total_quantity,
    SUM(oli.shipped_quantity) AS shipped_quantity,
    CASE
        WHEN COUNT(oli.line_item_id) = COUNT(CASE WHEN oli.line_status = 'shipped' THEN 1 END)
             AND so.order_status = 'shipped' THEN 'COMPLETE'
        WHEN COUNT(CASE WHEN oli.line_status = 'backordered' THEN 1 END) > 0 THEN 'PARTIAL'
        WHEN so.order_status = 'cancelled' THEN 'CANCELLED'
        ELSE 'IN_PROGRESS'
    END AS fulfillment_status
FROM sales_orders so
JOIN companies c ON so.customer_id = c.company_id
LEFT JOIN order_line_items oli ON so.order_id = oli.order_id
GROUP BY so.order_id, so.order_number, so.order_date, so.requested_ship_date,
         so.order_status, c.company_name;

-- Shipment Tracking View
CREATE VIEW shipment_tracking AS
SELECT
    s.shipment_number,
    s.shipment_status,
    s.ship_date,
    s.estimated_delivery_date,
    s.actual_delivery_date,
    c.company_name AS carrier_name,
    s.tracking_number,
    ol.location_name AS origin_location,
    dl.location_name AS destination_location,
    s.total_weight_lbs,
    s.package_count,
    COUNT(si.shipment_item_id) AS items_count,
    SUM(si.shipped_quantity) AS total_quantity
FROM shipments s
JOIN companies c ON s.carrier_id = c.company_id
JOIN locations ol ON s.origin_location_id = ol.location_id
JOIN locations dl ON s.destination_location_id = dl.location_id
LEFT JOIN shipment_items si ON s.shipment_id = si.shipment_id
GROUP BY s.shipment_id, s.shipment_number, s.shipment_status, s.ship_date,
         s.estimated_delivery_date, s.actual_delivery_date, c.company_name,
         s.tracking_number, ol.location_name, dl.location_name,
         s.total_weight_lbs, s.package_count;

-- ===========================================
-- TRIGGERS FOR BUSINESS LOGIC
-- ===========================================

-- Update inventory levels on movements
CREATE OR REPLACE FUNCTION update_inventory_levels()
RETURNS TRIGGER AS $$
DECLARE
    quantity_change INTEGER;
BEGIN
    -- Calculate quantity change based on movement type
    CASE NEW.movement_type
        WHEN 'receipt' THEN quantity_change := NEW.quantity_changed;
        WHEN 'putaway' THEN quantity_change := 0; -- Location change only
        WHEN 'picking' THEN quantity_change := -NEW.quantity_changed;
        WHEN 'shipping' THEN quantity_change := -NEW.quantity_changed;
        WHEN 'adjustment' THEN quantity_change := NEW.quantity_changed;
        ELSE quantity_change := 0;
    END CASE;

    -- Update inventory quantity if there's a change
    IF quantity_change != 0 THEN
        UPDATE inventory
        SET quantity_on_hand = quantity_on_hand + quantity_change,
            last_movement_at = NEW.performed_at,
            updated_at = CURRENT_TIMESTAMP
        WHERE inventory_id = NEW.inventory_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_inventory_levels
    AFTER INSERT ON inventory_movements
    FOR EACH ROW EXECUTE FUNCTION update_inventory_levels();

-- Update order line item status based on shipments
CREATE OR REPLACE FUNCTION update_order_line_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Update line item shipped quantity
    UPDATE order_line_items
    SET shipped_quantity = shipped_quantity + NEW.shipped_quantity,
        updated_at = CURRENT_TIMESTAMP
    WHERE line_item_id = NEW.order_line_item_id;

    -- Update line status
    UPDATE order_line_items
    SET line_status = CASE
        WHEN shipped_quantity >= ordered_quantity THEN 'shipped'
        WHEN shipped_quantity > 0 THEN 'partial'
        ELSE line_status
    END,
    updated_at = CURRENT_TIMESTAMP
    WHERE line_item_id = NEW.order_line_item_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_order_line_status
    AFTER INSERT ON shipment_items
    FOR EACH ROW EXECUTE FUNCTION update_order_line_status();

-- This comprehensive logistics database schema provides a solid foundation
-- for supply chain management, warehouse operations, transportation, and order fulfillment
-- with support for multi-company operations and complex logistics workflows.
