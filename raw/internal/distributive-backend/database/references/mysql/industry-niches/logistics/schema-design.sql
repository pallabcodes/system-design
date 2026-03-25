-- Logistics Industry Database Schema (MySQL)
-- Comprehensive schema for supply chain management, warehouse operations, transportation, and order fulfillment
-- Adapted for MySQL with InnoDB engine, JSON support, spatial features, and performance optimizations

-- ===========================================
-- CORE ENTITIES
-- ===========================================

-- Companies and Organizations
CREATE TABLE companies (
    company_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    company_name VARCHAR(255) NOT NULL,
    company_type ENUM('manufacturer', 'distributor', 'retailer', 'carrier', 'warehouse', '3pl_provider') NOT NULL,
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
    compliance_status ENUM('pending', 'approved', 'suspended', 'revoked') DEFAULT 'pending',

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_companies_type_status (company_type, is_active),
    INDEX idx_companies_active (is_active)
) ENGINE = InnoDB;

-- Locations and Facilities
CREATE TABLE locations (
    location_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    company_id CHAR(36) NOT NULL,

    -- Location Details
    location_name VARCHAR(255) NOT NULL,
    location_type ENUM('warehouse', 'distribution_center', 'store', 'manufacturing', 'port', 'airport') NOT NULL,

    -- Address and Geospatial
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(50) DEFAULT 'USA',
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    location_point POINT AS (POINT(longitude, latitude)) STORED,

    -- Operational Details
    timezone VARCHAR(50) DEFAULT 'UTC',
    operating_hours JSON DEFAULT ('{}'),
    total_area_sqft INT,
    storage_capacity_cuft BIGINT,

    -- Capabilities
    capabilities JSON DEFAULT ('[]'),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Hierarchical structure
    parent_location_id CHAR(36),

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE CASCADE,
    FOREIGN KEY (parent_location_id) REFERENCES locations(location_id) ON DELETE SET NULL,

    UNIQUE KEY uk_location_company_name (company_id, location_name),
    INDEX idx_locations_company_type (company_id, location_type),
    INDEX idx_locations_active (is_active),
    SPATIAL INDEX idx_locations_point (location_point)
) ENGINE = InnoDB;

-- ===========================================
-- PRODUCT AND INVENTORY MANAGEMENT
-- ===========================================

-- Products
CREATE TABLE products (
    product_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    company_id CHAR(36) NOT NULL,

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
    volume_cuft DECIMAL(10,4) AS ((length_inches * width_inches * height_inches) / 1728) STORED,

    -- Classification
    is_hazmat BOOLEAN DEFAULT FALSE,
    hazmat_class VARCHAR(10),
    requires_refrigeration BOOLEAN DEFAULT FALSE,
    storage_temperature_range VARCHAR(50),

    -- Economic Properties
    unit_cost DECIMAL(10,2),
    unit_price DECIMAL(10,2),
    currency_code CHAR(3) DEFAULT 'USD',

    -- Packaging
    packaging_type VARCHAR(50),
    units_per_package INT DEFAULT 1,
    package_weight_lbs DECIMAL(8,2),
    package_volume_cuft DECIMAL(10,4),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE CASCADE,

    INDEX idx_products_company_category (company_id, product_category),
    INDEX idx_products_sku (sku),
    INDEX idx_products_active (is_active)
) ENGINE = InnoDB;

-- Inventory Management
CREATE TABLE inventory (
    inventory_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    location_id CHAR(36) NOT NULL,
    product_id CHAR(36) NOT NULL,

    -- Inventory Levels
    quantity_on_hand INT DEFAULT 0,
    quantity_allocated INT DEFAULT 0,
    quantity_available INT AS (quantity_on_hand - quantity_allocated) STORED,

    -- Quality and Status
    inventory_status ENUM('available', 'reserved', 'damaged', 'expired', 'quarantined') DEFAULT 'available',

    -- Storage Details
    storage_location VARCHAR(100),
    lot_number VARCHAR(50),
    serial_numbers JSON DEFAULT ('[]'),
    expiration_date DATE,

    -- Cost and Valuation
    unit_cost DECIMAL(10,2),
    total_value DECIMAL(12,2) AS (quantity_on_hand * unit_cost) STORED,

    -- Reordering
    reorder_point INT,
    reorder_quantity INT,
    safety_stock INT,

    -- Last Activity
    last_count_date DATE,
    last_movement_at TIMESTAMP NULL,

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (location_id) REFERENCES locations(location_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE,

    UNIQUE KEY uk_inventory_location_product_lot (location_id, product_id, lot_number),
    INDEX idx_inventory_location_product (location_id, product_id),
    INDEX idx_inventory_status (inventory_status),
    INDEX idx_inventory_expiration (expiration_date)
) ENGINE = InnoDB;

-- ===========================================
-- ORDER MANAGEMENT
-- ===========================================

-- Sales Orders
CREATE TABLE sales_orders (
    order_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    company_id CHAR(36) NOT NULL,

    -- Order Information
    order_number VARCHAR(50) UNIQUE NOT NULL,
    order_type ENUM('standard', 'rush', 'backorder', 'transfer', 'return') DEFAULT 'standard',

    -- Parties Involved
    customer_id CHAR(36) NOT NULL,
    bill_to_location_id CHAR(36),
    ship_to_location_id CHAR(36),

    -- Order Details
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    requested_ship_date DATE,
    promised_ship_date DATE,
    actual_ship_date DATE,

    -- Financial
    subtotal_amount DECIMAL(12,2),
    tax_amount DECIMAL(10,2),
    shipping_amount DECIMAL(10,2),
    discount_amount DECIMAL(10,2),
    total_amount DECIMAL(12,2) AS (
        COALESCE(subtotal_amount, 0) + COALESCE(tax_amount, 0) +
        COALESCE(shipping_amount, 0) - COALESCE(discount_amount, 0)
    ) STORED,

    currency_code CHAR(3) DEFAULT 'USD',

    -- Status
    order_status ENUM('draft', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'returned') DEFAULT 'draft',

    -- Shipping Preferences
    shipping_method VARCHAR(50),
    carrier_id CHAR(36),
    tracking_number VARCHAR(100),

    -- Special Instructions
    customer_notes TEXT,
    internal_notes TEXT,

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by CHAR(36),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    updated_by CHAR(36),

    FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE CASCADE,
    FOREIGN KEY (customer_id) REFERENCES companies(company_id) ON DELETE RESTRICT,
    FOREIGN KEY (bill_to_location_id) REFERENCES locations(location_id) ON DELETE SET NULL,
    FOREIGN KEY (ship_to_location_id) REFERENCES locations(location_id) ON DELETE SET NULL,
    FOREIGN KEY (carrier_id) REFERENCES companies(company_id) ON DELETE SET NULL,

    INDEX idx_sales_orders_company_status (company_id, order_status),
    INDEX idx_sales_orders_dates (order_date, requested_ship_date),
    INDEX idx_sales_orders_tracking (tracking_number)
) ENGINE = InnoDB;

-- Order Line Items
CREATE TABLE order_line_items (
    line_item_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    order_id CHAR(36) NOT NULL,

    -- Product Information
    product_id CHAR(36) NOT NULL,
    product_sku VARCHAR(100),
    product_name VARCHAR(255),

    -- Quantities
    ordered_quantity INT NOT NULL,
    shipped_quantity INT DEFAULT 0,
    backordered_quantity INT DEFAULT 0,
    cancelled_quantity INT DEFAULT 0,

    -- Pricing
    unit_price DECIMAL(10,2) NOT NULL,
    line_total DECIMAL(12,2) AS (ordered_quantity * unit_price) STORED,

    -- Status
    line_status ENUM('open', 'shipped', 'backordered', 'cancelled', 'returned') DEFAULT 'open',

    -- Delivery Schedule
    requested_delivery_date DATE,
    promised_delivery_date DATE,
    actual_delivery_date DATE,

    -- Special Requirements
    special_instructions TEXT,
    quality_requirements JSON DEFAULT ('{}'),

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (order_id) REFERENCES sales_orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE RESTRICT,

    INDEX idx_order_line_items_order (order_id),
    INDEX idx_order_line_items_product (product_id),
    INDEX idx_order_line_items_status (line_status)
) ENGINE = InnoDB;

-- ===========================================
-- SHIPPING AND TRANSPORTATION
-- ===========================================

-- Shipments
CREATE TABLE shipments (
    shipment_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    order_id CHAR(36),

    -- Shipment Details
    shipment_number VARCHAR(50) UNIQUE NOT NULL,
    shipment_type ENUM('inbound', 'outbound', 'transfer', 'return') DEFAULT 'outbound',

    -- Carrier and Transportation
    carrier_id CHAR(36) NOT NULL,
    carrier_service_type VARCHAR(50),
    tracking_number VARCHAR(100),
    pro_number VARCHAR(50),

    -- Origin and Destination
    origin_location_id CHAR(36) NOT NULL,
    destination_location_id CHAR(36) NOT NULL,

    -- Dates and Times
    ship_date TIMESTAMP NULL,
    estimated_delivery_date TIMESTAMP NULL,
    actual_delivery_date TIMESTAMP NULL,
    delivered_by CHAR(36),

    -- Shipment Contents
    total_weight_lbs DECIMAL(10,2),
    total_volume_cuft DECIMAL(12,4),
    package_count INT,
    pallet_count INT,

    -- Cost and Billing
    shipping_cost DECIMAL(10,2),
    fuel_surcharge DECIMAL(8,2),
    insurance_cost DECIMAL(8,2),

    -- Status and Tracking
    shipment_status ENUM('created', 'packed', 'loaded', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned') DEFAULT 'created',

    -- Current Location
    current_latitude DECIMAL(10,8),
    current_longitude DECIMAL(11,8),
    current_location_point POINT AS (POINT(current_longitude, current_latitude)) STORED,
    last_location_update TIMESTAMP NULL,

    -- Exception Handling
    exception_code VARCHAR(20),
    exception_description TEXT,
    exception_date TIMESTAMP NULL,

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by CHAR(36),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    updated_by CHAR(36),

    FOREIGN KEY (order_id) REFERENCES sales_orders(order_id) ON DELETE SET NULL,
    FOREIGN KEY (carrier_id) REFERENCES companies(company_id) ON DELETE RESTRICT,
    FOREIGN KEY (origin_location_id) REFERENCES locations(location_id) ON DELETE RESTRICT,
    FOREIGN KEY (destination_location_id) REFERENCES locations(location_id) ON DELETE RESTRICT,

    INDEX idx_shipments_order (order_id),
    INDEX idx_shipments_carrier_status (carrier_id, shipment_status),
    INDEX idx_shipments_tracking (tracking_number),
    INDEX idx_shipments_dates (ship_date, estimated_delivery_date),
    SPATIAL INDEX idx_shipments_location (current_location_point)
) ENGINE = InnoDB;

-- Shipment Items
CREATE TABLE shipment_items (
    shipment_item_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    shipment_id CHAR(36) NOT NULL,
    order_line_item_id CHAR(36),

    -- Product Information
    product_id CHAR(36) NOT NULL,
    product_name VARCHAR(255),
    product_sku VARCHAR(100),

    -- Quantities
    shipped_quantity INT NOT NULL,
    received_quantity INT,
    damaged_quantity INT DEFAULT 0,

    -- Packaging
    package_type VARCHAR(50),
    package_id VARCHAR(50),
    serial_numbers JSON DEFAULT ('[]'),

    -- Quality Control
    quality_check_passed BOOLEAN,
    quality_notes TEXT,
    inspected_by CHAR(36),
    inspection_date TIMESTAMP NULL,

    FOREIGN KEY (shipment_id) REFERENCES shipments(shipment_id) ON DELETE CASCADE,
    FOREIGN KEY (order_line_item_id) REFERENCES order_line_items(line_item_id) ON DELETE SET NULL,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE RESTRICT,

    UNIQUE KEY uk_shipment_order_line (shipment_id, order_line_item_id),
    INDEX idx_shipment_items_shipment (shipment_id),
    INDEX idx_shipment_items_product (product_id)
) ENGINE = InnoDB;

-- ===========================================
-- WAREHOUSE MANAGEMENT
-- ===========================================

-- Warehouse Zones
CREATE TABLE warehouse_zones (
    zone_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    location_id CHAR(36) NOT NULL,

    -- Zone Information
    zone_name VARCHAR(100) NOT NULL,
    zone_type ENUM('receiving', 'storage', 'picking', 'packing', 'shipping', 'quarantine') NOT NULL,

    -- Physical Layout
    aisle_prefix VARCHAR(10),
    aisle_range_start INT,
    aisle_range_end INT,
    level_range_start INT,
    level_range_end INT,

    -- Capacity and Utilization
    total_slots INT,
    occupied_slots INT DEFAULT 0,
    utilization_rate DECIMAL(5,2) AS (
        CASE WHEN total_slots > 0 THEN (occupied_slots / total_slots) * 100 ELSE 0 END
    ) STORED,

    -- Environmental Conditions
    temperature_range VARCHAR(20),
    humidity_range VARCHAR(20),
    security_level VARCHAR(20),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    FOREIGN KEY (location_id) REFERENCES locations(location_id) ON DELETE CASCADE,

    UNIQUE KEY uk_zone_location_name (location_id, zone_name),
    INDEX idx_warehouse_zones_location (location_id, zone_type)
) ENGINE = InnoDB;

-- Storage Locations
CREATE TABLE storage_locations (
    storage_location_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    zone_id CHAR(36) NOT NULL,

    -- Location Details
    location_code VARCHAR(50) UNIQUE NOT NULL,
    location_type ENUM('bin', 'shelf', 'pallet_rack', 'floor', 'bulk') DEFAULT 'bin',

    -- Dimensions and Capacity
    max_weight_lbs INT,
    max_volume_cuft DECIMAL(8,2),
    max_items INT,

    -- Current Utilization
    current_weight_lbs DECIMAL(8,2) DEFAULT 0,
    current_volume_cuft DECIMAL(8,2) DEFAULT 0,
    current_items INT DEFAULT 0,

    -- Status and Availability
    location_status ENUM('available', 'occupied', 'reserved', 'maintenance', 'damaged') DEFAULT 'available',

    -- Product Compatibility
    allowed_product_categories JSON DEFAULT ('[]'),
    restricted_products JSON DEFAULT ('[]'),

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (zone_id) REFERENCES warehouse_zones(zone_id) ON DELETE CASCADE,

    INDEX idx_storage_locations_zone (zone_id, location_status),
    INDEX idx_storage_locations_code (location_code)
) ENGINE = InnoDB;

-- Inventory Movements
CREATE TABLE inventory_movements (
    movement_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    inventory_id CHAR(36) NOT NULL,

    -- Movement Details
    movement_type ENUM('receipt', 'putaway', 'transfer', 'picking', 'shipping', 'adjustment', 'cycle_count') NOT NULL,

    -- Quantities
    quantity_changed INT NOT NULL,
    quantity_before INT,
    quantity_after INT,

    -- Locations
    from_storage_location_id CHAR(36),
    to_storage_location_id CHAR(36),

    -- Related Documents
    order_id CHAR(36),
    shipment_id CHAR(36),
    adjustment_reason TEXT,

    -- Quality and Notes
    movement_notes TEXT,
    quality_check_required BOOLEAN DEFAULT FALSE,
    quality_check_passed BOOLEAN,

    -- Performed By
    performed_by CHAR(36) NOT NULL,
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (inventory_id) REFERENCES inventory(inventory_id) ON DELETE CASCADE,
    FOREIGN KEY (from_storage_location_id) REFERENCES storage_locations(storage_location_id) ON DELETE SET NULL,
    FOREIGN KEY (to_storage_location_id) REFERENCES storage_locations(storage_location_id) ON DELETE SET NULL,
    FOREIGN KEY (order_id) REFERENCES sales_orders(order_id) ON DELETE SET NULL,
    FOREIGN KEY (shipment_id) REFERENCES shipments(shipment_id) ON DELETE SET NULL,

    INDEX idx_inventory_movements_inventory (inventory_id, performed_at DESC),
    INDEX idx_inventory_movements_type (movement_type, performed_at DESC),
    INDEX idx_inventory_movements_date (performed_at DESC)
) ENGINE = InnoDB;

-- ===========================================
-- SUPPLY CHAIN MANAGEMENT
-- ===========================================

-- Purchase Orders
CREATE TABLE purchase_orders (
    po_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    company_id CHAR(36) NOT NULL,

    -- Order Information
    po_number VARCHAR(50) UNIQUE NOT NULL,
    supplier_id CHAR(36) NOT NULL,

    -- Dates
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    requested_delivery_date DATE,
    promised_delivery_date DATE,
    actual_delivery_date DATE,

    -- Financial
    subtotal_amount DECIMAL(12,2),
    tax_amount DECIMAL(10,2),
    shipping_amount DECIMAL(10,2),
    total_amount DECIMAL(12,2),

    -- Status
    po_status ENUM('draft', 'approved', 'ordered', 'partial_receipt', 'received', 'cancelled') DEFAULT 'draft',

    -- Terms and Conditions
    payment_terms VARCHAR(100),
    shipping_terms VARCHAR(100),
    special_instructions TEXT,

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by CHAR(36),
    approved_at TIMESTAMP NULL,
    approved_by CHAR(36),

    FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE CASCADE,
    FOREIGN KEY (supplier_id) REFERENCES companies(company_id) ON DELETE RESTRICT,

    INDEX idx_purchase_orders_company_status (company_id, po_status),
    INDEX idx_purchase_orders_supplier (supplier_id)
) ENGINE = InnoDB;

-- Purchase Order Line Items
CREATE TABLE po_line_items (
    po_line_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    po_id CHAR(36) NOT NULL,

    -- Product Information
    product_id CHAR(36) NOT NULL,
    product_name VARCHAR(255),
    product_sku VARCHAR(100),

    -- Quantities
    ordered_quantity INT NOT NULL,
    received_quantity INT DEFAULT 0,
    rejected_quantity INT DEFAULT 0,

    -- Pricing
    unit_cost DECIMAL(10,2) NOT NULL,
    line_total DECIMAL(12,2) AS (ordered_quantity * unit_cost) STORED,

    -- Delivery Schedule
    requested_delivery_date DATE,
    actual_delivery_date DATE,

    -- Quality Requirements
    quality_specifications TEXT,
    inspection_required BOOLEAN DEFAULT FALSE,

    -- Status
    line_status ENUM('open', 'partial', 'received', 'rejected', 'cancelled') DEFAULT 'open',

    FOREIGN KEY (po_id) REFERENCES purchase_orders(po_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE RESTRICT,

    INDEX idx_po_line_items_po (po_id),
    INDEX idx_po_line_items_product (product_id)
) ENGINE = InnoDB;

-- Suppliers
CREATE TABLE suppliers (
    supplier_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    company_id CHAR(36) NOT NULL,

    -- Supplier Information
    supplier_name VARCHAR(255) NOT NULL,
    supplier_type ENUM('manufacturer', 'distributor', 'importer', 'service_provider') DEFAULT 'manufacturer',

    -- Contact Information
    contact_person VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(20),

    -- Performance Metrics
    on_time_delivery_rate DECIMAL(5,2),
    quality_rating DECIMAL(3,1),
    average_lead_time_days INT,

    -- Contract Information
    contract_start_date DATE,
    contract_end_date DATE,
    payment_terms VARCHAR(50),

    -- Status
    supplier_status ENUM('active', 'inactive', 'suspended', 'terminated') DEFAULT 'active',

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE CASCADE,

    INDEX idx_suppliers_company (company_id),
    INDEX idx_suppliers_status (supplier_status)
) ENGINE = InnoDB;

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

-- Inventory Analytics
CREATE TABLE inventory_analytics (
    analytic_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    location_id CHAR(36) NOT NULL,

    -- Time Period
    date_recorded DATE DEFAULT (CURRENT_DATE),
    week_start DATE,

    -- Inventory Metrics
    total_sku_count INT,
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
    a_items_count INT,
    b_items_count INT,
    c_items_count INT,

    FOREIGN KEY (location_id) REFERENCES locations(location_id) ON DELETE CASCADE,

    UNIQUE KEY uk_analytics_location_date (location_id, date_recorded),
    INDEX idx_inventory_analytics_location (location_id, date_recorded DESC)
) ENGINE = InnoDB
PARTITION BY RANGE (YEAR(date_recorded)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Order Fulfillment Analytics
CREATE TABLE fulfillment_analytics (
    analytic_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    company_id CHAR(36) NOT NULL,

    -- Time Period
    date_recorded DATE DEFAULT (CURRENT_DATE),
    month_year DATE,

    -- Order Metrics
    orders_received INT DEFAULT 0,
    orders_shipped INT DEFAULT 0,
    orders_delivered INT DEFAULT 0,
    orders_cancelled INT DEFAULT 0,

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

    FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE CASCADE,

    UNIQUE KEY uk_fulfillment_company_date (company_id, date_recorded),
    INDEX idx_fulfillment_analytics_company (company_id, date_recorded DESC)
) ENGINE = InnoDB
PARTITION BY RANGE (YEAR(date_recorded)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

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

/*
This comprehensive logistics database schema provides enterprise-grade infrastructure for:
- Multi-company supply chain management
- Real-time inventory tracking across multiple locations
- Order processing and fulfillment workflows
- Multi-modal transportation and shipping management
- Warehouse operations with zone and storage location management
- Purchase order and supplier relationship management
- Analytics and reporting for performance optimization

Key features adapted for MySQL:
- UUID primary keys with UUID() function
- JSON data types for flexible metadata storage
- MySQL spatial data types (POINT) for geolocation
- InnoDB engine with full-text and spatial indexes
- Partitioning for time-series analytics data
- Generated columns for computed values
- Comprehensive indexing strategy for performance

The schema handles complex logistics workflows, regulatory compliance, and provides comprehensive analytics for modern supply chain operations.
*/

