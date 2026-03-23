-- Retail & Point of Sale Database Schema
-- Comprehensive schema for retail operations, POS systems, inventory management, and customer analytics

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- STORE AND LOCATION MANAGEMENT
-- ===========================================

CREATE TABLE stores (
    store_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_code VARCHAR(20) UNIQUE NOT NULL,
    store_name VARCHAR(255) NOT NULL,

    -- Store Classification
    store_type VARCHAR(30) CHECK (store_type IN ('brick_and_mortar', 'online', 'pop_up', 'warehouse', 'outlet')),
    store_format VARCHAR(30) CHECK (store_format IN ('flagship', 'mall', 'strip_center', 'downtown', 'suburban', 'rural')),

    -- Location Information
    address JSONB NOT NULL,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Store Details
    square_footage INTEGER,
    parking_spaces INTEGER,
    operating_hours JSONB DEFAULT '{}', -- Hours for each day of week

    -- Contact Information
    phone VARCHAR(20),
    email VARCHAR(255),
    website VARCHAR(500),

    -- Store Hierarchy
    parent_store_id UUID REFERENCES stores(store_id),
    district_id UUID,
    region_id UUID,

    -- Status and Operations
    store_status VARCHAR(20) DEFAULT 'active' CHECK (store_status IN ('active', 'inactive', 'renovation', 'closed', 'temporarily_closed')),
    grand_opening_date DATE,
    closing_date DATE,

    -- Financial Information
    annual_rent DECIMAL(12,2),
    monthly_sales_target DECIMAL(12,2),

    -- Operational Data
    manager_id UUID, -- References employees
    staff_count INTEGER,
    register_count INTEGER,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE store_zones (
    zone_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID NOT NULL REFERENCES stores(store_id) ON DELETE CASCADE,

    -- Zone Information
    zone_name VARCHAR(100) NOT NULL,
    zone_type VARCHAR(30) CHECK (zone_type IN ('department', 'aisle', 'section', 'fixture', 'display')),

    -- Physical Layout
    zone_coordinates JSONB, -- Polygon coordinates for zone boundaries
    square_footage DECIMAL(8,2),

    -- Operational Details
    responsible_employee_id UUID,
    restocking_schedule JSONB DEFAULT '{}',
    cleaning_schedule JSONB DEFAULT '{}',

    -- Performance Metrics
    foot_traffic_count INTEGER DEFAULT 0,
    conversion_rate DECIMAL(5,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- PRODUCT CATALOG AND INVENTORY
-- ===========================================

CREATE TABLE product_categories (
    category_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_name VARCHAR(255) NOT NULL,
    category_code VARCHAR(20) UNIQUE NOT NULL,

    -- Category Hierarchy
    parent_category_id UUID REFERENCES product_categories(category_id),
    hierarchy_level INTEGER DEFAULT 1,

    -- Category Details
    description TEXT,
    category_type VARCHAR(30) CHECK (category_type IN ('product', 'service', 'bundle', 'virtual')),

    -- Display and Navigation
    display_order INTEGER DEFAULT 0,
    is_visible BOOLEAN DEFAULT TRUE,
    icon_url VARCHAR(500),
    banner_image_url VARCHAR(500),

    -- SEO and Marketing
    seo_keywords TEXT[],
    meta_description TEXT,

    -- Status
    category_status VARCHAR(20) DEFAULT 'active' CHECK (category_status IN ('active', 'inactive', 'discontinued')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_sku VARCHAR(50) UNIQUE NOT NULL,
    product_name VARCHAR(255) NOT NULL,

    -- Product Classification
    category_id UUID NOT NULL REFERENCES product_categories(category_id),
    brand_id UUID,
    supplier_id UUID,

    -- Product Details
    description TEXT,
    short_description TEXT,
    product_type VARCHAR(30) CHECK (product_type IN ('physical', 'digital', 'service', 'bundle', 'gift_card')),

    -- Physical Attributes
    weight_ounces DECIMAL(8,2),
    dimensions JSONB, -- length, width, height
    color VARCHAR(50),
    size VARCHAR(50),

    -- Pricing
    base_price DECIMAL(10,2) NOT NULL,
    cost_price DECIMAL(10,2),
    msrp DECIMAL(10,2),
    wholesale_price DECIMAL(10,2),

    -- Inventory Management
    track_inventory BOOLEAN DEFAULT TRUE,
    reorder_point INTEGER DEFAULT 0,
    safety_stock INTEGER DEFAULT 0,

    -- Sales and Marketing
    is_featured BOOLEAN DEFAULT FALSE,
    is_on_sale BOOLEAN DEFAULT FALSE,
    sale_price DECIMAL(10,2),
    sale_start_date DATE,
    sale_end_date DATE,

    -- Status and Lifecycle
    product_status VARCHAR(20) DEFAULT 'active' CHECK (product_status IN ('active', 'inactive', 'discontinued', 'out_of_stock')),
    introduced_date DATE,
    discontinued_date DATE,

    -- Images and Media
    primary_image_url VARCHAR(500),
    additional_images JSONB DEFAULT '[]',

    -- Compliance and Legal
    requires_age_verification BOOLEAN DEFAULT FALSE,
    minimum_age INTEGER,
    regulated_item BOOLEAN DEFAULT FALSE,
    regulation_type VARCHAR(50),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (sale_price IS NULL OR sale_price < base_price),
    CHECK (minimum_age IS NULL OR minimum_age >= 0)
);

CREATE TABLE product_variants (
    variant_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_product_id UUID NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,

    -- Variant Details
    variant_sku VARCHAR(50) UNIQUE NOT NULL,
    variant_name VARCHAR(255),

    -- Variant Attributes
    color VARCHAR(50),
    size VARCHAR(50),
    material VARCHAR(100),
    style VARCHAR(100),

    -- Pricing (overrides parent)
    price_modifier DECIMAL(10,2) DEFAULT 0,
    cost_modifier DECIMAL(10,2) DEFAULT 0,

    -- Inventory
    variant_inventory INTEGER DEFAULT 0,

    -- Images
    variant_image_url VARCHAR(500),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- POINT OF SALE AND TRANSACTIONS
-- ===========================================

CREATE TABLE pos_terminals (
    terminal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID NOT NULL REFERENCES stores(store_id),

    -- Terminal Details
    terminal_number VARCHAR(20) NOT NULL,
    terminal_type VARCHAR(30) CHECK (terminal_type IN ('register', 'self_checkout', 'mobile', 'online')),

    -- Hardware Information
    hardware_id VARCHAR(100) UNIQUE,
    ip_address INET,
    mac_address MACADDR,

    -- Status and Operation
    terminal_status VARCHAR(20) DEFAULT 'active' CHECK (terminal_status IN ('active', 'inactive', 'maintenance', 'out_of_order')),
    last_transaction_at TIMESTAMP WITH TIME ZONE,

    -- Security
    encryption_enabled BOOLEAN DEFAULT TRUE,
    pin_required BOOLEAN DEFAULT TRUE,

    -- Configuration
    receipt_printer_id VARCHAR(50),
    cash_drawer_id VARCHAR(50),
    scanner_type VARCHAR(50),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (store_id, terminal_number)
);

CREATE TABLE sales_transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_number VARCHAR(30) UNIQUE NOT NULL,

    -- Transaction Context
    store_id UUID NOT NULL REFERENCES stores(store_id),
    terminal_id UUID REFERENCES pos_terminals(terminal_id),
    cashier_id UUID, -- References employees

    -- Transaction Details
    transaction_type VARCHAR(20) DEFAULT 'sale' CHECK (transaction_type IN ('sale', 'return', 'exchange', 'void', 'gift_card_sale')),
    transaction_status VARCHAR(20) DEFAULT 'completed' CHECK (transaction_status IN ('pending', 'completed', 'voided', 'refunded')),

    -- Customer Information
    customer_id UUID,
    customer_type VARCHAR(20) CHECK (customer_type IN ('registered', 'guest', 'loyalty_member')),

    -- Financial Information
    subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    discount_amount DECIMAL(10,2) DEFAULT 0,
    total_amount DECIMAL(10,2) NOT NULL,

    -- Payment Information
    payment_method VARCHAR(30) CHECK (payment_method IN ('cash', 'credit_card', 'debit_card', 'gift_card', 'check', 'mobile_payment')),
    payment_reference VARCHAR(100), -- Authorization code, etc.
    card_last_four VARCHAR(4),

    -- Transaction Timing
    transaction_date DATE DEFAULT CURRENT_DATE,
    transaction_time TIME DEFAULT CURRENT_TIME,
    processing_time_seconds DECIMAL(5,2),

    -- Additional Details
    notes TEXT,
    loyalty_points_earned INTEGER DEFAULT 0,
    loyalty_points_used INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (total_amount >= 0),
    CHECK (discount_amount >= 0),
    CHECK (loyalty_points_earned >= 0),
    CHECK (loyalty_points_used >= 0)
);

CREATE TABLE transaction_items (
    transaction_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID NOT NULL REFERENCES sales_transactions(transaction_id) ON DELETE CASCADE,

    -- Product Information
    product_id UUID NOT NULL REFERENCES products(product_id),
    variant_id UUID REFERENCES product_variants(variant_id),

    -- Item Details
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    line_total DECIMAL(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,

    -- Discounts and Adjustments
    discount_amount DECIMAL(8,2) DEFAULT 0,
    discount_reason VARCHAR(100),

    -- Inventory Tracking
    serial_numbers TEXT[], -- For serialized items
    lot_numbers TEXT[], -- For lot-tracked items

    -- Returns and Exchanges
    original_transaction_item_id UUID REFERENCES transaction_items(transaction_item_id),
    return_reason VARCHAR(100),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity != 0),
    CHECK (unit_price >= 0),
    CHECK (discount_amount >= 0)
);

-- ===========================================
-- CUSTOMER MANAGEMENT AND LOYALTY
-- ===========================================

CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_number VARCHAR(20) UNIQUE,

    -- Personal Information
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),

    -- Account Details
    account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN ('active', 'inactive', 'suspended', 'closed')),
    registration_date DATE DEFAULT CURRENT_DATE,

    -- Contact Preferences
    email_opt_in BOOLEAN DEFAULT TRUE,
    sms_opt_in BOOLEAN DEFAULT FALSE,
    mail_opt_in BOOLEAN DEFAULT TRUE,

    -- Demographics
    date_of_birth DATE,
    gender VARCHAR(20),
    household_income_range VARCHAR(30),

    -- Address Information
    billing_address JSONB,
    shipping_address JSONB,
    preferred_store_id UUID REFERENCES stores(store_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE loyalty_programs (
    program_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    program_name VARCHAR(255) NOT NULL,
    program_code VARCHAR(20) UNIQUE NOT NULL,

    -- Program Details
    description TEXT,
    program_type VARCHAR(30) CHECK (program_type IN ('points_based', 'tiered', 'coalition', 'paid')),

    -- Point System
    points_per_dollar DECIMAL(5,2) DEFAULT 1.0,
    points_value_cents DECIMAL(5,2) DEFAULT 1.0, -- Value per point in cents

    -- Tier System (if applicable)
    tier_structure JSONB DEFAULT '{}', -- Tier names, requirements, benefits

    -- Program Rules
    enrollment_fee DECIMAL(8,2) DEFAULT 0,
    annual_fee DECIMAL(8,2) DEFAULT 0,
    points_expiry_months INTEGER DEFAULT 24,

    -- Status
    program_status VARCHAR(20) DEFAULT 'active' CHECK (program_status IN ('active', 'inactive', 'discontinued')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE loyalty_accounts (
    loyalty_account_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),
    program_id UUID NOT NULL REFERENCES loyalty_programs(program_id),

    -- Account Details
    account_number VARCHAR(30) UNIQUE NOT NULL,
    enrollment_date DATE DEFAULT CURRENT_DATE,

    -- Points and Status
    current_points INTEGER DEFAULT 0,
    lifetime_points INTEGER DEFAULT 0,
    current_tier VARCHAR(50),
    points_to_next_tier INTEGER,

    -- Account Status
    account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN ('active', 'inactive', 'suspended', 'closed')),

    -- Expiration and Renewal
    points_expiry_date DATE,
    membership_expiry_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (customer_id, program_id)
);

CREATE TABLE loyalty_transactions (
    loyalty_transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    loyalty_account_id UUID NOT NULL REFERENCES loyalty_accounts(loyalty_account_id),

    -- Transaction Details
    transaction_type VARCHAR(30) CHECK (transaction_type IN ('earn', 'redeem', 'expire', 'adjust', 'transfer')),
    points_amount INTEGER NOT NULL,

    -- Related Transactions
    sales_transaction_id UUID REFERENCES sales_transactions(transaction_id),
    reference_number VARCHAR(50),

    -- Transaction Details
    transaction_date DATE DEFAULT CURRENT_DATE,
    description TEXT,

    -- Balance Tracking
    points_balance_before INTEGER,
    points_balance_after INTEGER,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (points_amount != 0)
);

-- ===========================================
-- INVENTORY AND SUPPLY CHAIN
-- ===========================================

CREATE TABLE inventory_locations (
    location_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(store_id),

    -- Location Details
    location_code VARCHAR(20) UNIQUE NOT NULL,
    location_name VARCHAR(100) NOT NULL,
    location_type VARCHAR(30) CHECK (location_type IN ('store', 'warehouse', 'distribution_center', 'supplier')),

    -- Physical Details
    address JSONB,
    capacity_cubic_feet DECIMAL(10,2),
    temperature_controlled BOOLEAN DEFAULT FALSE,

    -- Operational Status
    is_active BOOLEAN DEFAULT TRUE,
    operating_hours JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE inventory_items (
    inventory_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    location_id UUID NOT NULL REFERENCES inventory_locations(location_id),
    product_id UUID NOT NULL REFERENCES products(product_id),

    -- Inventory Details
    quantity_on_hand INTEGER DEFAULT 0,
    quantity_allocated INTEGER DEFAULT 0,
    quantity_available INTEGER GENERATED ALWAYS AS (quantity_on_hand - quantity_allocated) STORED,

    -- Cost and Valuation
    average_cost DECIMAL(10,2),
    last_cost DECIMAL(10,2),
    total_value DECIMAL(12,2) GENERATED ALWAYS AS (quantity_on_hand * average_cost) STORED,

    -- Inventory Tracking
    reorder_point INTEGER DEFAULT 0,
    safety_stock INTEGER DEFAULT 0,
    maximum_stock INTEGER,

    -- Quality Control
    lot_number VARCHAR(50),
    serial_number VARCHAR(100),
    expiration_date DATE,
    quality_status VARCHAR(20) DEFAULT 'good' CHECK (quality_status IN ('good', 'fair', 'poor', 'quarantine', 'expired')),

    -- Last Movement
    last_receipt_date DATE,
    last_issue_date DATE,
    last_count_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (location_id, product_id, COALESCE(lot_number, ''))
);

CREATE TABLE inventory_transactions (
    inventory_transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Transaction Details
    transaction_type VARCHAR(30) NOT NULL CHECK (transaction_type IN (
        'receipt', 'issue', 'transfer', 'adjustment', 'count', 'return', 'damage'
    )),
    transaction_reference VARCHAR(50), -- PO number, sales transaction, etc.

    -- Location Details
    from_location_id UUID REFERENCES inventory_locations(location_id),
    to_location_id UUID REFERENCES inventory_locations(location_id),

    -- Product Details
    product_id UUID NOT NULL REFERENCES products(product_id),
    quantity INTEGER NOT NULL,
    unit_cost DECIMAL(10,2),

    -- Transaction Details
    transaction_date DATE DEFAULT CURRENT_DATE,
    authorized_by UUID,
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity != 0),
    CHECK ((from_location_id IS NOT NULL OR to_location_id IS NOT NULL))
);

-- ===========================================
-- PURCHASING AND SUPPLIER MANAGEMENT
-- ===========================================

CREATE TABLE suppliers (
    supplier_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_code VARCHAR(20) UNIQUE NOT NULL,
    supplier_name VARCHAR(255) NOT NULL,

    -- Supplier Classification
    supplier_type VARCHAR(30) CHECK (supplier_type IN ('manufacturer', 'distributor', 'wholesaler', 'dropship')),
    supplier_category VARCHAR(50),

    -- Contact Information
    contact_person VARCHAR(255),
    email VARCHAR(255),
    phone VARCHAR(20),
    address JSONB,

    -- Supplier Performance
    on_time_delivery_rate DECIMAL(5,2),
    quality_rating DECIMAL(3,1),
    responsiveness_rating DECIMAL(3,1),
    overall_rating DECIMAL(3,1),

    -- Business Terms
    payment_terms VARCHAR(50) DEFAULT 'net_30',
    shipping_terms VARCHAR(100),
    minimum_order_quantity INTEGER DEFAULT 1,

    -- Status
    supplier_status VARCHAR(20) DEFAULT 'active' CHECK (supplier_status IN ('active', 'inactive', 'suspended', 'terminated')),
    approved_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE purchase_orders (
    purchase_order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_number VARCHAR(30) UNIQUE NOT NULL,

    -- Order Details
    supplier_id UUID NOT NULL REFERENCES suppliers(supplier_id),
    store_id UUID REFERENCES stores(store_id),
    order_date DATE DEFAULT CURRENT_DATE,

    -- Order Status
    po_status VARCHAR(20) DEFAULT 'draft' CHECK (po_status IN (
        'draft', 'approved', 'sent', 'confirmed', 'partially_received',
        'received', 'cancelled', 'closed'
    )),

    -- Financial Information
    subtotal DECIMAL(10,2),
    tax_amount DECIMAL(10,2),
    shipping_amount DECIMAL(10,2),
    total_amount DECIMAL(10,2),

    -- Terms and Delivery
    expected_delivery_date DATE,
    actual_delivery_date DATE,
    shipping_method VARCHAR(50),

    -- Approval and Processing
    requested_by UUID,
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE purchase_order_items (
    po_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(purchase_order_id) ON DELETE CASCADE,

    -- Item Details
    product_id UUID NOT NULL REFERENCES products(product_id),
    quantity_ordered INTEGER NOT NULL,
    unit_cost DECIMAL(10,2) NOT NULL,

    -- Line Amounts
    line_total DECIMAL(10,2) GENERATED ALWAYS AS (quantity_ordered * unit_cost) STORED,

    -- Receiving
    quantity_received INTEGER DEFAULT 0,
    quantity_rejected INTEGER DEFAULT 0,

    -- Status
    item_status VARCHAR(20) DEFAULT 'open' CHECK (item_status IN ('open', 'partially_received', 'received', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity_ordered > 0),
    CHECK (unit_cost >= 0)
);

-- ===========================================
-- PROMOTIONS AND PRICING
-- ===========================================

CREATE TABLE promotions (
    promotion_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    promotion_name VARCHAR(255) NOT NULL,
    promotion_code VARCHAR(20) UNIQUE,

    -- Promotion Details
    promotion_type VARCHAR(30) CHECK (promotion_type IN (
        'percentage_discount', 'fixed_amount_discount', 'buy_one_get_one',
        'bundle_pricing', 'loyalty_points_bonus', 'free_shipping'
    )),
    description TEXT,

    -- Discount Details
    discount_percentage DECIMAL(5,2),
    discount_amount DECIMAL(10,2),
    minimum_purchase DECIMAL(10,2),

    -- Product Scope
    applicable_products UUID[], -- Specific product IDs
    applicable_categories UUID[], -- Product category IDs
    excluded_products UUID[], -- Products not eligible

    -- Customer Scope
    applicable_customer_types TEXT[], -- 'registered', 'loyalty_member', etc.
    minimum_loyalty_tier VARCHAR(50),

    -- Store Scope
    applicable_stores UUID[], -- Specific store IDs
    applicable_regions UUID[], -- Geographic regions

    -- Timing
    start_date TIMESTAMP WITH TIME ZONE,
    end_date TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN GENERATED ALWAYS AS (
        start_date <= CURRENT_TIMESTAMP AND
        (end_date IS NULL OR end_date > CURRENT_TIMESTAMP)
    ) STORED,

    -- Usage Limits
    usage_limit INTEGER, -- Total uses allowed
    usage_limit_per_customer INTEGER, -- Uses per customer
    current_usage INTEGER DEFAULT 0,

    -- Marketing
    coupon_code VARCHAR(20),
    redemption_instructions TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE promotion_usage (
    usage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    promotion_id UUID NOT NULL REFERENCES promotions(promotion_id),
    transaction_id UUID NOT NULL REFERENCES sales_transactions(transaction_id),
    customer_id UUID REFERENCES customers(customer_id),

    -- Usage Details
    discount_applied DECIMAL(10,2) NOT NULL,
    coupon_code_used VARCHAR(20),

    -- Tracking
    used_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (promotion_id, transaction_id)
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

CREATE TABLE sales_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(store_id),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_hour INTEGER CHECK (report_hour BETWEEN 0 AND 23),

    -- Sales Metrics
    transaction_count INTEGER DEFAULT 0,
    total_sales DECIMAL(12,2) DEFAULT 0,
    total_discounts DECIMAL(10,2) DEFAULT 0,
    total_tax DECIMAL(10,2) DEFAULT 0,

    -- Product Metrics
    units_sold INTEGER DEFAULT 0,
    unique_customers INTEGER DEFAULT 0,
    average_transaction_value DECIMAL(10,2),

    -- Customer Metrics
    new_customers INTEGER DEFAULT 0,
    returning_customers INTEGER DEFAULT 0,
    loyalty_members INTEGER DEFAULT 0,

    -- Operational Metrics
    average_transaction_time_seconds DECIMAL(6,2),
    peak_hour_transaction_count INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (store_id, report_date, report_hour)
);

CREATE TABLE product_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(product_id),
    store_id UUID REFERENCES stores(store_id),

    -- Time Dimensions
    report_date DATE NOT NULL,

    -- Product Metrics
    units_sold INTEGER DEFAULT 0,
    revenue DECIMAL(12,2) DEFAULT 0,
    gross_margin DECIMAL(10,2),
    gross_margin_percentage DECIMAL(5,2),

    -- Inventory Metrics
    beginning_inventory INTEGER,
    ending_inventory INTEGER,
    inventory_turnover DECIMAL(5,2),

    -- Performance Metrics
    sell_through_rate DECIMAL(5,2),
    stock_to_sales_ratio DECIMAL(5,2),
    average_daily_sales DECIMAL(8,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (product_id, store_id, report_date)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Store and location indexes
CREATE INDEX idx_stores_type_status ON stores (store_type, store_status);
CREATE INDEX idx_stores_region ON stores (region_id);
CREATE INDEX idx_store_zones_store ON store_zones (store_id);

-- Product indexes
CREATE INDEX idx_products_category ON products (category_id);
CREATE INDEX idx_products_status ON products (product_status);
CREATE INDEX idx_products_sku ON products (product_sku);
CREATE INDEX idx_product_variants_parent ON product_variants (parent_product_id);

-- Transaction indexes
CREATE INDEX idx_sales_transactions_store_date ON sales_transactions (store_id, transaction_date DESC);
CREATE INDEX idx_sales_transactions_customer ON sales_transactions (customer_id);
CREATE INDEX idx_sales_transactions_status ON sales_transactions (transaction_status);
CREATE INDEX idx_transaction_items_transaction ON transaction_items (transaction_id);
CREATE INDEX idx_transaction_items_product ON transaction_items (product_id);

-- Customer and loyalty indexes
CREATE INDEX idx_customers_email ON customers (email);
CREATE INDEX idx_customers_status ON customers (account_status);
CREATE INDEX idx_loyalty_accounts_customer ON loyalty_accounts (customer_id);
CREATE INDEX idx_loyalty_transactions_account ON loyalty_transactions (loyalty_account_id);

-- Inventory indexes
CREATE INDEX idx_inventory_items_location_product ON inventory_items (location_id, product_id);
CREATE INDEX idx_inventory_items_expiration ON inventory_items (expiration_date) WHERE expiration_date IS NOT NULL;
CREATE INDEX idx_inventory_transactions_location ON inventory_transactions (from_location_id, to_location_id);
CREATE INDEX idx_inventory_transactions_product ON inventory_transactions (product_id, transaction_date DESC);

-- Supplier and purchasing indexes
CREATE INDEX idx_suppliers_type_status ON suppliers (supplier_type, supplier_status);
CREATE INDEX idx_purchase_orders_supplier ON purchase_orders (supplier_id);
CREATE INDEX idx_purchase_orders_status ON purchase_orders (po_status);
CREATE INDEX idx_po_items_po ON purchase_order_items (purchase_order_id);

-- Promotion indexes
CREATE INDEX idx_promotions_active ON promotions (promotion_id) WHERE is_active = TRUE;
CREATE INDEX idx_promotion_usage_promotion ON promotion_usage (promotion_id);
CREATE INDEX idx_promotion_usage_transaction ON promotion_usage (transaction_id);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Store performance dashboard
CREATE VIEW store_performance AS
SELECT
    s.store_id,
    s.store_name,
    s.store_type,
    s.store_status,

    -- Sales metrics (last 30 days)
    COALESCE(SUM(sa.total_sales), 0) as sales_last_30_days,
    COALESCE(SUM(sa.transaction_count), 0) as transactions_last_30_days,
    COALESCE(AVG(sa.average_transaction_value), 0) as avg_transaction_value,

    -- Customer metrics
    COUNT(DISTINCT st.customer_id) as unique_customers_last_30_days,
    COUNT(CASE WHEN c.registration_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as new_customers,

    -- Inventory metrics
    SUM(ii.total_value) as total_inventory_value,
    COUNT(CASE WHEN ii.quantity_available <= ii.reorder_point THEN 1 END) as items_below_reorder,

    -- Performance indicators
    CASE WHEN SUM(sa.total_sales) > s.monthly_sales_target THEN 'exceeding_target'
         WHEN SUM(sa.total_sales) > s.monthly_sales_target * 0.8 THEN 'on_track'
         ELSE 'below_target' END as sales_performance

FROM stores s
LEFT JOIN sales_analytics sa ON s.store_id = sa.store_id
    AND sa.report_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN sales_transactions st ON s.store_id = st.store_id
    AND st.transaction_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN customers c ON st.customer_id = c.customer_id
LEFT JOIN inventory_items ii ON s.store_id = ii.location_id
GROUP BY s.store_id, s.store_name, s.store_type, s.store_status, s.monthly_sales_target;

-- Product performance analysis
CREATE VIEW product_performance AS
SELECT
    p.product_id,
    p.product_sku,
    p.product_name,
    pc.category_name,

    -- Sales metrics (last 30 days)
    COALESCE(SUM(pa.units_sold), 0) as units_sold_last_30,
    COALESCE(SUM(pa.revenue), 0) as revenue_last_30,
    COALESCE(AVG(pa.gross_margin_percentage), 0) as avg_margin_percentage,

    -- Inventory metrics
    COALESCE(AVG(pa.ending_inventory), 0) as current_inventory,
    COALESCE(AVG(pa.inventory_turnover), 0) as inventory_turnover,

    -- Performance indicators
    CASE WHEN COALESCE(AVG(pa.ending_inventory), 0) <= p.reorder_point THEN 'reorder_needed'
         WHEN COALESCE(AVG(pa.ending_inventory), 0) <= p.safety_stock THEN 'low_stock'
         ELSE 'in_stock' END as inventory_status,

    -- Trends
    COALESCE(
        (SUM(CASE WHEN pa.report_date >= CURRENT_DATE - INTERVAL '7 days' THEN pa.units_sold END) -
         SUM(CASE WHEN pa.report_date >= CURRENT_DATE - INTERVAL '14 days'
                  AND pa.report_date < CURRENT_DATE - INTERVAL '7 days' THEN pa.units_sold END)) /
        NULLIF(SUM(CASE WHEN pa.report_date >= CURRENT_DATE - INTERVAL '14 days'
                        AND pa.report_date < CURRENT_DATE - INTERVAL '7 days' THEN pa.units_sold END), 0) * 100,
        0
    ) as sales_trend_percentage

FROM products p
JOIN product_categories pc ON p.category_id = pc.category_id
LEFT JOIN product_analytics pa ON p.product_id = pa.product_id
    AND pa.report_date >= CURRENT_DATE - INTERVAL '30 days'
WHERE p.product_status = 'active'
GROUP BY p.product_id, p.product_sku, p.product_name, pc.category_name, p.reorder_point, p.safety_stock;

-- Customer lifetime value analysis
CREATE VIEW customer_lifetime_value AS
SELECT
    c.customer_id,
    c.customer_number,
    c.first_name || ' ' || c.last_name as customer_name,
    c.registration_date,

    -- Transaction metrics
    COUNT(st.transaction_id) as total_transactions,
    SUM(st.total_amount) as total_spent,
    AVG(st.total_amount) as avg_transaction_amount,
    MAX(st.transaction_date) as last_transaction_date,

    -- Loyalty metrics
    COALESCE(la.current_points, 0) as current_loyalty_points,
    COALESCE(la.lifetime_points, 0) as lifetime_loyalty_points,
    la.current_tier,

    -- Recency, Frequency, Monetary (RFM) analysis
    EXTRACT(EPOCH FROM (CURRENT_DATE - MAX(st.transaction_date))) / 86400 as days_since_last_purchase,
    COUNT(st.transaction_id) as purchase_frequency,
    SUM(st.total_amount) as monetary_value,

    -- Customer segment
    CASE
        WHEN SUM(st.total_amount) >= 1000 AND COUNT(st.transaction_id) >= 10 THEN 'high_value'
        WHEN SUM(st.total_amount) >= 500 OR COUNT(st.transaction_id) >= 5 THEN 'medium_value'
        WHEN SUM(st.total_amount) > 0 THEN 'low_value'
        ELSE 'prospect'
    END as customer_segment

FROM customers c
LEFT JOIN sales_transactions st ON c.customer_id = st.customer_id AND st.transaction_status = 'completed'
LEFT JOIN loyalty_accounts la ON c.customer_id = la.customer_id
WHERE c.account_status = 'active'
GROUP BY c.customer_id, c.customer_number, c.first_name, c.last_name, c.registration_date,
         la.current_points, la.lifetime_points, la.current_tier;

-- Inventory optimization dashboard
CREATE VIEW inventory_optimization AS
SELECT
    ii.product_id,
    p.product_name,
    il.location_name,

    -- Current inventory levels
    ii.quantity_on_hand,
    ii.quantity_available,
    ii.reorder_point,
    ii.safety_stock,

    -- Inventory health indicators
    CASE
        WHEN ii.quantity_available <= 0 THEN 'out_of_stock'
        WHEN ii.quantity_available <= ii.safety_stock THEN 'critical'
        WHEN ii.quantity_available <= ii.reorder_point THEN 'reorder'
        ELSE 'healthy'
    END as inventory_health,

    -- Turnover analysis
    COALESCE(pa.inventory_turnover, 0) as inventory_turnover_ratio,
    CASE
        WHEN COALESCE(pa.inventory_turnover, 0) >= 12 THEN 'excellent'
        WHEN COALESCE(pa.inventory_turnover, 0) >= 6 THEN 'good'
        WHEN COALESCE(pa.inventory_turnover, 0) >= 3 THEN 'fair'
        ELSE 'poor'
    END as turnover_rating,

    -- Carrying cost estimate
    ii.total_value * 0.25 as estimated_annual_carrying_cost, -- 25% carrying cost

    -- Stock recommendations
    CASE
        WHEN ii.quantity_available <= ii.safety_stock THEN 'urgent_reorder'
        WHEN ii.quantity_available <= ii.reorder_point THEN 'reorder'
        WHEN ii.quantity_on_hand > ii.maximum_stock THEN 'overstocked'
        ELSE 'optimal'
    END as stock_recommendation

FROM inventory_items ii
JOIN products p ON ii.product_id = p.product_id
JOIN inventory_locations il ON ii.location_id = il.location_id
LEFT JOIN product_analytics pa ON ii.product_id = pa.product_id
    AND pa.store_id = il.store_id
    AND pa.report_date = CURRENT_DATE - INTERVAL '1 day'
WHERE ii.quantity_on_hand > 0;

-- ===========================================
-- FUNCTIONS FOR RETAIL OPERATIONS
-- =========================================--

-- Function to calculate product pricing with promotions
CREATE OR REPLACE FUNCTION calculate_product_price(
    product_uuid UUID,
    customer_uuid UUID DEFAULT NULL,
    promotion_codes TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS TABLE (
    base_price DECIMAL,
    discount_amount DECIMAL,
    final_price DECIMAL,
    applied_promotions JSONB
) AS $$
DECLARE
    product_record products%ROWTYPE;
    customer_record customers%ROWTYPE;
    promotion_record promotions%ROWTYPE;
    current_price DECIMAL;
    total_discount DECIMAL := 0;
    applied_promos JSONB := '[]';
BEGIN
    -- Get product details
    SELECT * INTO product_record FROM products WHERE product_id = product_uuid;

    -- Get customer details if provided
    IF customer_uuid IS NOT NULL THEN
        SELECT * INTO customer_record FROM customers WHERE customer_id = customer_uuid;
    END IF;

    -- Start with base price
    current_price := product_record.base_price;

    -- Check for sale pricing
    IF product_record.is_on_sale AND product_record.sale_price IS NOT NULL
       AND CURRENT_DATE BETWEEN COALESCE(product_record.sale_start_date, CURRENT_DATE)
                           AND COALESCE(product_record.sale_end_date, CURRENT_DATE) THEN
        current_price := product_record.sale_price;
        applied_promos := applied_promos || jsonb_build_object(
            'type', 'sale',
            'discount', product_record.base_price - product_record.sale_price,
            'description', 'Sale pricing'
        );
    END IF;

    -- Apply promotions
    FOR promotion_record IN
        SELECT * FROM promotions
        WHERE is_active = TRUE
          AND (product_uuid = ANY(applicable_products) OR array_length(applicable_products, 1) IS NULL)
          AND (customer_uuid IS NULL OR customer_record.customer_type = ANY(applicable_customer_types))
          AND (array_length(promotion_codes, 1) = 0 OR coupon_code = ANY(promotion_codes))
    LOOP
        -- Calculate discount based on promotion type
        CASE promotion_record.promotion_type
            WHEN 'percentage_discount' THEN
                total_discount := total_discount + (current_price * promotion_record.discount_percentage / 100);
            WHEN 'fixed_amount_discount' THEN
                total_discount := total_discount + promotion_record.discount_amount;
        END CASE;

        applied_promos := applied_promos || jsonb_build_object(
            'promotion_id', promotion_record.promotion_id,
            'promotion_name', promotion_record.promotion_name,
            'discount_type', promotion_record.promotion_type,
            'discount_amount', CASE promotion_record.promotion_type
                WHEN 'percentage_discount' THEN current_price * promotion_record.discount_percentage / 100
                ELSE promotion_record.discount_amount END
        );
    END LOOP;

    RETURN QUERY SELECT
        product_record.base_price,
        total_discount,
        GREATEST(current_price - total_discount, 0),
        applied_promos;
END;
$$ LANGUAGE plpgsql;

-- Function to process sales transaction
CREATE OR REPLACE FUNCTION process_sales_transaction(
    store_uuid UUID,
    terminal_uuid UUID,
    cashier_uuid UUID,
    customer_uuid UUID DEFAULT NULL,
    items JSONB,
    payment_info JSONB
)
RETURNS UUID AS $$
DECLARE
    transaction_uuid UUID;
    item_record JSONB;
    product_record products%ROWTYPE;
    line_total DECIMAL;
    subtotal DECIMAL := 0;
    tax_rate DECIMAL := 0.08; -- Default 8% tax
    total_amount DECIMAL;
BEGIN
    -- Generate transaction number
    transaction_uuid := uuid_generate_v4();

    -- Insert transaction header
    INSERT INTO sales_transactions (
        transaction_id, transaction_number,
        store_id, terminal_id, cashier_id, customer_id,
        subtotal, tax_amount, total_amount,
        payment_method, payment_reference
    ) VALUES (
        transaction_uuid,
        'TXN-' || UPPER(SUBSTRING(uuid_generate_v4()::TEXT, 1, 8)),
        store_uuid, terminal_uuid, cashier_uuid, customer_uuid,
        0, 0, 0, -- Will calculate below
        payment_info->>'method',
        payment_info->>'reference'
    );

    -- Process each item
    FOR item_record IN SELECT * FROM jsonb_array_elements(items)
    LOOP
        -- Get product details and calculate pricing
        SELECT * INTO product_record FROM products
        WHERE product_id = (item_record->>'product_id')::UUID;

        -- Calculate line total with promotions
        SELECT final_price INTO line_total
        FROM calculate_product_price(
            (item_record->>'product_id')::UUID,
            customer_uuid,
            CASE WHEN item_record ? 'promotion_codes'
                 THEN ARRAY(SELECT jsonb_array_elements_text(item_record->'promotion_codes'))
                 ELSE ARRAY[]::TEXT[] END
        );

        line_total := line_total * (item_record->>'quantity')::INTEGER;

        -- Insert transaction item
        INSERT INTO transaction_items (
            transaction_id, product_id, quantity, unit_price, line_total
        ) VALUES (
            transaction_uuid,
            (item_record->>'product_id')::UUID,
            (item_record->>'quantity')::INTEGER,
            line_total / (item_record->>'quantity')::INTEGER,
            line_total
        );

        -- Update inventory
        UPDATE inventory_items
        SET quantity_on_hand = quantity_on_hand - (item_record->>'quantity')::INTEGER,
            last_issue_date = CURRENT_DATE
        WHERE product_id = (item_record->>'product_id')::UUID
          AND location_id = store_uuid;

        subtotal := subtotal + line_total;
    END LOOP;

    -- Calculate totals
    total_amount := subtotal * (1 + tax_rate);

    -- Update transaction with calculated totals
    UPDATE sales_transactions
    SET subtotal = subtotal,
        tax_amount = subtotal * tax_rate,
        total_amount = total_amount
    WHERE transaction_id = transaction_uuid;

    -- Process loyalty points if applicable
    IF customer_uuid IS NOT NULL THEN
        PERFORM award_loyalty_points(customer_uuid, subtotal);
    END IF;

    RETURN transaction_uuid;
END;
$$ LANGUAGE plpgsql;

-- Function to award loyalty points
CREATE OR REPLACE FUNCTION award_loyalty_points(customer_uuid UUID, purchase_amount DECIMAL)
RETURNS INTEGER AS $$
DECLARE
    loyalty_account_record loyalty_accounts%ROWTYPE;
    points_earned INTEGER;
    program_record loyalty_programs%ROWTYPE;
BEGIN
    -- Get active loyalty account
    SELECT la.*, lp.* INTO loyalty_account_record, program_record
    FROM loyalty_accounts la
    JOIN loyalty_programs lp ON la.program_id = lp.program_id
    WHERE la.customer_id = customer_uuid
      AND la.account_status = 'active'
      AND lp.program_status = 'active';

    IF NOT FOUND THEN
        RETURN 0;
    END IF;

    -- Calculate points earned
    points_earned := FLOOR(purchase_amount * program_record.points_per_dollar);

    -- Update loyalty account
    UPDATE loyalty_accounts
    SET current_points = current_points + points_earned,
        lifetime_points = lifetime_points + points_earned
    WHERE loyalty_account_id = loyalty_account_record.loyalty_account_id;

    -- Log points transaction
    INSERT INTO loyalty_transactions (
        loyalty_account_id, transaction_type, points_amount,
        points_balance_after, description
    ) VALUES (
        loyalty_account_record.loyalty_account_id, 'earn', points_earned,
        loyalty_account_record.current_points + points_earned,
        'Points earned from purchase'
    );

    RETURN points_earned;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample store
INSERT INTO stores (store_code, store_name, store_type, address, operating_hours) VALUES
('STORE001', 'Main Street Retail', 'brick_and_mortar',
 '{"street": "123 Main St", "city": "Anytown", "state": "CA", "zip": "12345"}',
 '{"monday": {"open": "09:00", "close": "21:00"}, "tuesday": {"open": "09:00", "close": "21:00"}}'
);

-- Insert sample product category
INSERT INTO product_categories (category_name, category_code, description) VALUES
('Electronics', 'ELEC', 'Electronic devices and accessories');

-- Insert sample product
INSERT INTO products (product_sku, product_name, category_id, base_price, description) VALUES
('PROD001', 'Wireless Headphones', (SELECT category_id FROM product_categories WHERE category_code = 'ELEC' LIMIT 1),
 199.99, 'High-quality wireless headphones with noise cancellation');

-- Insert sample customer
INSERT INTO customers (customer_number, first_name, last_name, email) VALUES
('CUST001', 'John', 'Doe', 'john.doe@email.com');

-- Insert sample sales transaction
INSERT INTO sales_transactions (
    transaction_number, store_id, customer_id, subtotal, tax_amount, total_amount,
    payment_method, transaction_date
) VALUES (
    'TXN-001', (SELECT store_id FROM stores WHERE store_code = 'STORE001' LIMIT 1),
    (SELECT customer_id FROM customers WHERE customer_number = 'CUST001' LIMIT 1),
    199.99, 15.99, 215.98, 'credit_card', CURRENT_DATE
);

-- This retail schema provides comprehensive infrastructure for POS operations,
-- inventory management, customer loyalty, and retail analytics.
