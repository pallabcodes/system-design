-- ============================================
-- E-COMMERCE PLATFORM SCHEMA DESIGN
-- ============================================
-- Comprehensive schema for online shopping, marketplace, and quick commerce
-- Supports products, orders, payments, shipping, inventory, reviews, and analytics

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "hstore";
CREATE EXTENSION IF NOT EXISTS "postgis";  -- For location-based features

-- ============================================
-- CORE ENTITIES
-- ============================================

-- Users (Customers, Sellers, Administrators)
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(20),
    date_of_birth DATE,
    gender VARCHAR(10) CHECK (gender IN ('male', 'female', 'other', 'prefer_not_to_say')),

    -- Account settings
    email_verified BOOLEAN DEFAULT FALSE,
    phone_verified BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    user_type VARCHAR(20) DEFAULT 'customer' CHECK (user_type IN ('customer', 'seller', 'admin', 'moderator')),
    preferred_language VARCHAR(5) DEFAULT 'en',

    -- Marketing preferences
    marketing_email BOOLEAN DEFAULT FALSE,
    marketing_sms BOOLEAN DEFAULT FALSE,
    marketing_push BOOLEAN DEFAULT FALSE,

    -- Authentication
    last_login_at TIMESTAMP WITH TIME ZONE,
    login_count INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', first_name || ' ' || last_name || ' ' || email)
    ) STORED,

    CONSTRAINT chk_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_phone_format CHECK (phone IS NULL OR phone ~* '^\+?[0-9\s\-\(\)]+$')
);

-- User addresses for shipping and billing
CREATE TABLE addresses (
    address_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    -- Address components
    address_type VARCHAR(20) DEFAULT 'shipping' CHECK (address_type IN ('shipping', 'billing')),
    is_default BOOLEAN DEFAULT FALSE,
    label VARCHAR(50), -- e.g., 'Home', 'Work', 'Mom''s house'

    -- Address fields
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    company VARCHAR(100),
    street_address VARCHAR(255) NOT NULL,
    apartment VARCHAR(50),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100),
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(100) DEFAULT 'USA',

    -- Geographic data (for delivery optimization)
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326), -- PostGIS point

    -- Contact info
    phone VARCHAR(20),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id, address_type, is_default) DEFERRABLE INITIALLY DEFERRED
);

-- ============================================
-- PRODUCT CATALOG
-- ============================================

-- Product categories (hierarchical)
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    slug VARCHAR(120) NOT NULL UNIQUE,
    description TEXT,
    parent_category_id INTEGER REFERENCES categories(category_id),
    display_order INTEGER DEFAULT 0,

    -- Category metadata
    image_url VARCHAR(500),
    is_active BOOLEAN DEFAULT TRUE,
    meta_title VARCHAR(60),
    meta_description VARCHAR(160),

    -- SEO and analytics
    search_keywords TEXT[],
    featured BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', name || ' ' || description || ' ' || array_to_string(search_keywords, ' '))
    ) STORED
);

-- Brands/Manufacturers
CREATE TABLE brands (
    brand_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    slug VARCHAR(120) NOT NULL UNIQUE,
    description TEXT,
    logo_url VARCHAR(500),
    website_url VARCHAR(500),
    is_active BOOLEAN DEFAULT TRUE,

    -- Brand verification
    is_verified BOOLEAN DEFAULT FALSE,
    verification_documents JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Products
CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(280) NOT NULL UNIQUE,
    description TEXT,
    short_description VARCHAR(500),

    -- Categorization
    brand_id INTEGER REFERENCES brands(brand_id),
    category_id INTEGER REFERENCES categories(category_id),

    -- Pricing
    base_price DECIMAL(10,2) NOT NULL CHECK (base_price >= 0),
    sale_price DECIMAL(10,2) CHECK (sale_price >= 0),
    cost_price DECIMAL(10,2),

    -- Inventory
    stock_quantity INTEGER DEFAULT 0 CHECK (stock_quantity >= 0),
    stock_status VARCHAR(20) DEFAULT 'in_stock' CHECK (stock_status IN ('in_stock', 'out_of_stock', 'on_backorder')),
    low_stock_threshold INTEGER DEFAULT 5,
    track_inventory BOOLEAN DEFAULT TRUE,

    -- Product status
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'inactive', 'discontinued')),
    visibility VARCHAR(20) DEFAULT 'public' CHECK (visibility IN ('public', 'hidden', 'search_only')),

    -- Physical properties
    weight DECIMAL(8,3), -- in kg
    dimensions JSONB, -- {"length": 10, "width": 5, "height": 2, "unit": "cm"}

    -- Shipping
    requires_shipping BOOLEAN DEFAULT TRUE,
    shipping_class VARCHAR(50) DEFAULT 'standard',

    -- Tax
    tax_class VARCHAR(50) DEFAULT 'standard',
    tax_rate DECIMAL(5,4),

    -- Media
    main_image_url VARCHAR(500),
    gallery_images JSONB DEFAULT '[]', -- Array of image URLs

    -- SEO
    meta_title VARCHAR(60),
    meta_description VARCHAR(160),
    search_keywords TEXT[],

    -- Sales data (denormalized for performance)
    total_sales INTEGER DEFAULT 0,
    total_reviews INTEGER DEFAULT 0,
    average_rating DECIMAL(3,2) DEFAULT 0.00,

    -- Seller information (for marketplace)
    seller_id UUID REFERENCES users(user_id),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP WITH TIME ZONE,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english',
            name || ' ' || description || ' ' || short_description || ' ' ||
            array_to_string(search_keywords, ' ') || ' ' || sku
        )
    ) STORED,

    CONSTRAINT chk_sale_price CHECK (sale_price IS NULL OR sale_price <= base_price),
    CONSTRAINT chk_rating_range CHECK (average_rating BETWEEN 0 AND 5),
    CONSTRAINT chk_published_status CHECK (
        (status = 'active' AND published_at IS NOT NULL) OR
        (status != 'active' AND published_at IS NULL)
    )
);

-- Product variations (size, color, etc.)
CREATE TABLE product_variations (
    variation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES products(product_id) ON DELETE CASCADE,
    sku VARCHAR(50) UNIQUE,
    variation_name VARCHAR(255) NOT NULL, -- e.g., "Color: Red, Size: Large"

    -- Variation attributes
    attributes JSONB NOT NULL, -- {"color": "red", "size": "large"}

    -- Pricing and inventory (can override parent)
    price_modifier DECIMAL(8,2) DEFAULT 0.00,
    sale_price_modifier DECIMAL(8,2) DEFAULT 0.00,
    stock_quantity INTEGER DEFAULT 0 CHECK (stock_quantity >= 0),
    stock_status VARCHAR(20) DEFAULT 'in_stock',

    -- Media (can override parent)
    image_url VARCHAR(500),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (product_id, attributes)
);

-- Product attributes (for filtering)
CREATE TABLE product_attributes (
    attribute_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    type VARCHAR(20) DEFAULT 'text' CHECK (type IN ('text', 'number', 'boolean', 'date', 'color', 'size')),
    display_name VARCHAR(100) NOT NULL,
    is_filterable BOOLEAN DEFAULT TRUE,
    is_searchable BOOLEAN DEFAULT FALSE,
    display_order INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Product attribute values
CREATE TABLE product_attribute_values (
    product_id UUID REFERENCES products(product_id) ON DELETE CASCADE,
    attribute_id INTEGER REFERENCES product_attributes(attribute_id) ON DELETE CASCADE,
    value_text TEXT,
    value_number DECIMAL(10,2),
    value_boolean BOOLEAN,
    value_date DATE,

    PRIMARY KEY (product_id, attribute_id),
    CONSTRAINT chk_attribute_value CHECK (
        (value_text IS NOT NULL AND value_number IS NULL AND value_boolean IS NULL AND value_date IS NULL) OR
        (value_text IS NULL AND value_number IS NOT NULL AND value_boolean IS NULL AND value_date IS NULL) OR
        (value_text IS NULL AND value_number IS NULL AND value_boolean IS NOT NULL AND value_date IS NULL) OR
        (value_text IS NULL AND value_number IS NULL AND value_boolean IS NULL AND value_date IS NOT NULL)
    )
);

-- ============================================
-- SHOPPING CART & ORDERS
-- ============================================

-- Shopping carts
CREATE TABLE carts (
    cart_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    session_id VARCHAR(255), -- For anonymous users

    -- Cart metadata
    currency VARCHAR(3) DEFAULT 'USD',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 days'),

    -- Constraints
    CONSTRAINT chk_cart_user CHECK (user_id IS NOT NULL OR session_id IS NOT NULL),
    CONSTRAINT chk_cart_expiry CHECK (expires_at > created_at)
);

-- Cart items
CREATE TABLE cart_items (
    cart_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_id UUID REFERENCES carts(cart_id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(product_id),
    variation_id UUID REFERENCES product_variations(variation_id),

    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),

    -- Customizations (e.g., gift wrapping, engraving)
    customizations JSONB DEFAULT '{}',

    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (cart_id, product_id, variation_id),
    CONSTRAINT chk_product_or_variation CHECK (
        (product_id IS NOT NULL AND variation_id IS NULL) OR
        (product_id IS NULL AND variation_id IS NOT NULL)
    )
);

-- Orders
CREATE TABLE orders (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number VARCHAR(50) UNIQUE NOT NULL, -- Human-readable order number
    user_id UUID REFERENCES users(user_id),

    -- Order status and workflow
    status VARCHAR(30) DEFAULT 'pending' CHECK (status IN (
        'pending', 'confirmed', 'processing', 'shipped', 'delivered',
        'cancelled', 'refunded', 'returned', 'disputed'
    )),
    payment_status VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN (
        'pending', 'paid', 'failed', 'refunded', 'partially_refunded'
    )),
    fulfillment_status VARCHAR(20) DEFAULT 'unfulfilled' CHECK (fulfillment_status IN (
        'unfulfilled', 'partially_fulfilled', 'fulfilled'
    )),

    -- Pricing and amounts
    currency VARCHAR(3) DEFAULT 'USD',
    subtotal DECIMAL(12,2) NOT NULL CHECK (subtotal >= 0),
    tax_amount DECIMAL(10,2) DEFAULT 0.00 CHECK (tax_amount >= 0),
    shipping_amount DECIMAL(10,2) DEFAULT 0.00 CHECK (shipping_amount >= 0),
    discount_amount DECIMAL(10,2) DEFAULT 0.00 CHECK (discount_amount >= 0),
    total_amount DECIMAL(12,2) NOT NULL CHECK (total_amount >= 0),

    -- Addresses
    billing_address_id UUID REFERENCES addresses(address_id),
    shipping_address_id UUID REFERENCES addresses(address_id),

    -- Shipping
    shipping_method VARCHAR(50),
    tracking_number VARCHAR(100),
    estimated_delivery_date DATE,

    -- Customer information (denormalized for performance)
    customer_email VARCHAR(255),
    customer_phone VARCHAR(20),

    -- Order notes and metadata
    customer_notes TEXT,
    internal_notes TEXT,
    metadata JSONB DEFAULT '{}',

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    confirmed_at TIMESTAMP WITH TIME ZONE,
    shipped_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english',
            order_number || ' ' || customer_email || ' ' ||
            COALESCE(customer_notes, '') || ' ' || COALESCE(internal_notes, '')
        )
    ) STORED,

    CONSTRAINT chk_total_calculation CHECK (
        total_amount = subtotal + tax_amount + shipping_amount - discount_amount
    ),
    CONSTRAINT chk_status_timestamps CHECK (
        (status = 'confirmed' AND confirmed_at IS NOT NULL) OR
        (status != 'confirmed' AND confirmed_at IS NULL)
    )
);

-- Order items
CREATE TABLE order_items (
    order_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(product_id),
    variation_id UUID REFERENCES product_variations(variation_id),

    -- Product details at time of order (immutable)
    product_name VARCHAR(255) NOT NULL,
    product_sku VARCHAR(50) NOT NULL,
    variation_name VARCHAR(255),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    total_price DECIMAL(10,2) NOT NULL CHECK (total_price >= 0),

    -- Fulfillment
    fulfilled_quantity INTEGER DEFAULT 0 CHECK (fulfilled_quantity <= quantity),
    fulfillment_status VARCHAR(20) DEFAULT 'pending' CHECK (fulfillment_status IN (
        'pending', 'processing', 'shipped', 'delivered', 'cancelled'
    )),

    -- Customizations and metadata
    customizations JSONB DEFAULT '{}',
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (order_id, product_id, variation_id),
    CONSTRAINT chk_total_price CHECK (total_price = quantity * unit_price)
);

-- ============================================
-- PAYMENTS & FINANCIAL
-- ============================================

-- Payment methods
CREATE TABLE payment_methods (
    payment_method_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    -- Payment method details
    type VARCHAR(20) NOT NULL CHECK (type IN ('credit_card', 'debit_card', 'paypal', 'apple_pay', 'google_pay', 'bank_transfer')),
    provider VARCHAR(50), -- 'stripe', 'paypal', 'braintree', etc.

    -- Card/bank details (encrypted in production)
    last_four VARCHAR(4),
    expiry_month INTEGER CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year INTEGER CHECK (expiry_year >= EXTRACT(YEAR FROM CURRENT_DATE)),
    card_brand VARCHAR(20),

    -- Bank account details for ACH
    account_holder_name VARCHAR(100),
    account_number_last_four VARCHAR(4),
    routing_number_last_four VARCHAR(4),

    -- Billing address
    billing_address_id UUID REFERENCES addresses(address_id),

    -- Status
    is_default BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,

    -- Tokenization (for PCI compliance)
    provider_token VARCHAR(255),
    provider_customer_id VARCHAR(255),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id, is_default) DEFERRABLE INITIALLY DEFERRED
);

-- Payments (payment transactions)
CREATE TABLE payments (
    payment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(order_id) ON DELETE CASCADE,

    -- Payment details
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    currency VARCHAR(3) DEFAULT 'USD',
    payment_method_id UUID REFERENCES payment_methods(payment_method_id),

    -- Payment processing
    provider VARCHAR(50) NOT NULL,
    provider_payment_id VARCHAR(255) UNIQUE,
    provider_transaction_id VARCHAR(255),

    -- Status and processing
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN (
        'pending', 'processing', 'succeeded', 'failed', 'cancelled', 'refunded'
    )),
    failure_reason TEXT,

    -- Risk assessment
    risk_score DECIMAL(5,2),
    risk_level VARCHAR(20) CHECK (risk_level IN ('low', 'medium', 'high')),

    -- Metadata
    metadata JSONB DEFAULT '{}',

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT chk_status_timestamps CHECK (
        (status IN ('succeeded', 'failed', 'cancelled') AND processed_at IS NOT NULL) OR
        (status NOT IN ('succeeded', 'failed', 'cancelled') AND processed_at IS NULL)
    )
);

-- Refunds
CREATE TABLE refunds (
    refund_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id UUID REFERENCES payments(payment_id) ON DELETE CASCADE,
    order_id UUID REFERENCES orders(order_id),

    -- Refund details
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    currency VARCHAR(3) DEFAULT 'USD',
    reason VARCHAR(100) CHECK (reason IN (
        'customer_request', 'defective_product', 'wrong_item', 'late_delivery',
        'duplicate_charge', 'fraud', 'other'
    )),
    description TEXT,

    -- Processing
    provider_refund_id VARCHAR(255) UNIQUE,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN (
        'pending', 'processing', 'succeeded', 'failed', 'cancelled'
    )),

    -- Metadata
    metadata JSONB DEFAULT '{}',

    -- Timestamps
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_refund_amount CHECK (amount <= (
        SELECT amount FROM payments WHERE payment_id = refunds.payment_id
    ))
);

-- ============================================
-- INVENTORY & WAREHOUSING
-- ============================================

-- Warehouses/Locations
CREATE TABLE warehouses (
    warehouse_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(20) UNIQUE NOT NULL,

    -- Location
    address JSONB NOT NULL,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),

    -- Contact information
    contact_name VARCHAR(100),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),

    -- Capabilities
    supports_express_shipping BOOLEAN DEFAULT FALSE,
    operating_hours JSONB, -- {"monday": {"open": "09:00", "close": "17:00"}}

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Product inventory by warehouse
CREATE TABLE product_inventory (
    inventory_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES products(product_id) ON DELETE CASCADE,
    variation_id UUID REFERENCES product_variations(variation_id) ON DELETE CASCADE,
    warehouse_id INTEGER REFERENCES warehouses(warehouse_id) ON DELETE CASCADE,

    -- Inventory levels
    quantity_available INTEGER DEFAULT 0 CHECK (quantity_available >= 0),
    quantity_reserved INTEGER DEFAULT 0 CHECK (quantity_reserved >= 0),
    quantity_on_order INTEGER DEFAULT 0 CHECK (quantity_on_order >= 0),

    -- Reordering
    reorder_point INTEGER DEFAULT 10,
    reorder_quantity INTEGER DEFAULT 50,

    -- Location within warehouse
    aisle VARCHAR(20),
    shelf VARCHAR(20),
    bin VARCHAR(20),

    -- Last updated
    last_counted_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (product_id, variation_id, warehouse_id),
    CONSTRAINT chk_available_quantity CHECK (quantity_available >= quantity_reserved)
);

-- Inventory transactions (for audit trail)
CREATE TABLE inventory_transactions (
    transaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inventory_id UUID REFERENCES product_inventory(inventory_id) ON DELETE CASCADE,

    -- Transaction details
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN (
        'stock_in', 'stock_out', 'adjustment', 'transfer', 'reservation', 'release'
    )),
    quantity_change INTEGER NOT NULL,
    previous_quantity INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,

    -- References
    order_id UUID REFERENCES orders(order_id),
    reference_document VARCHAR(50), -- PO number, adjustment reason, etc.

    -- User and notes
    performed_by UUID REFERENCES users(user_id),
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_quantity_change CHECK (
        (transaction_type IN ('stock_in', 'adjustment') AND quantity_change > 0) OR
        (transaction_type IN ('stock_out', 'reservation') AND quantity_change < 0) OR
        (transaction_type = 'release' AND quantity_change > 0) OR
        (transaction_type = 'transfer' AND quantity_change != 0)
    )
);

-- ============================================
-- SHIPPING & FULFILLMENT
-- ============================================

-- Shipping methods
CREATE TABLE shipping_methods (
    shipping_method_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(50) UNIQUE NOT NULL,

    -- Provider
    provider VARCHAR(50), -- 'fedex', 'ups', 'usps', 'dhl'
    provider_service_code VARCHAR(50),

    -- Cost calculation
    base_cost DECIMAL(8,2) NOT NULL CHECK (base_cost >= 0),
    cost_per_weight DECIMAL(8,2) DEFAULT 0.00,
    cost_per_item DECIMAL(8,2) DEFAULT 0.00,

    -- Delivery estimates
    min_delivery_days INTEGER DEFAULT 1,
    max_delivery_days INTEGER DEFAULT 5,

    -- Restrictions
    max_weight DECIMAL(8,2),
    max_dimensions JSONB, -- {"length": 100, "width": 50, "height": 50}
    restricted_items TEXT[], -- Product categories that can't use this method

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Shipments
CREATE TABLE shipments (
    shipment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(order_id) ON DELETE CASCADE,

    -- Shipping details
    shipping_method_id INTEGER REFERENCES shipping_methods(shipping_method_id),
    tracking_number VARCHAR(100) UNIQUE,
    carrier VARCHAR(50),

    -- Addresses
    ship_from_address JSONB,
    ship_to_address JSONB,

    -- Package details
    package_weight DECIMAL(8,2),
    package_dimensions JSONB,
    package_count INTEGER DEFAULT 1,

    -- Status tracking
    status VARCHAR(30) DEFAULT 'pending' CHECK (status IN (
        'pending', 'processing', 'shipped', 'in_transit', 'out_for_delivery',
        'delivered', 'failed_delivery', 'returned', 'cancelled'
    )),
    status_history JSONB DEFAULT '[]', -- Array of status changes with timestamps

    -- Costs
    shipping_cost DECIMAL(8,2) NOT NULL CHECK (shipping_cost >= 0),
    insurance_cost DECIMAL(6,2) DEFAULT 0.00,

    -- Dates
    shipped_at TIMESTAMP WITH TIME ZONE,
    estimated_delivery_date DATE,
    actual_delivery_date DATE,

    -- Metadata
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_delivery_dates CHECK (
        (actual_delivery_date IS NULL) OR
        (shipped_at IS NOT NULL AND actual_delivery_date >= shipped_at::DATE)
    )
);

-- Shipment items
CREATE TABLE shipment_items (
    shipment_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shipment_id UUID REFERENCES shipments(shipment_id) ON DELETE CASCADE,
    order_item_id UUID REFERENCES order_items(order_item_id) ON DELETE CASCADE,

    quantity_shipped INTEGER NOT NULL CHECK (quantity_shipped > 0),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (shipment_id, order_item_id)
);

-- ============================================
-- REVIEWS & RATINGS
-- ============================================

-- Product reviews
CREATE TABLE product_reviews (
    review_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES products(product_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    order_id UUID REFERENCES orders(order_id), -- Link to purchase

    -- Review content
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title VARCHAR(200),
    review_text TEXT,
    pros TEXT,
    cons TEXT,

    -- Media attachments
    images JSONB DEFAULT '[]',
    videos JSONB DEFAULT '[]',

    -- Review status
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'flagged')),
    is_verified_purchase BOOLEAN DEFAULT FALSE,
    is_featured BOOLEAN DEFAULT FALSE,

    -- Moderation
    moderator_id UUID REFERENCES users(user_id),
    moderation_notes TEXT,
    moderated_at TIMESTAMP WITH TIME ZONE,

    -- Analytics
    helpful_votes INTEGER DEFAULT 0,
    total_votes INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (product_id, user_id),
    CONSTRAINT chk_helpful_votes CHECK (helpful_votes <= total_votes)
);

-- Review votes
CREATE TABLE review_votes (
    review_vote_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id UUID REFERENCES product_reviews(review_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    vote_type VARCHAR(10) NOT NULL CHECK (vote_type IN ('helpful', 'unhelpful')),
    voted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (review_id, user_id)
);

-- Product questions and answers
CREATE TABLE product_questions (
    question_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES products(product_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    question_text TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'answered', 'rejected')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE product_answers (
    answer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id UUID REFERENCES product_questions(question_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    answer_text TEXT NOT NULL,
    is_official_answer BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- PROMOTIONS & DISCOUNTS
-- ============================================

-- Coupons/Discount codes
CREATE TABLE coupons (
    coupon_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,

    -- Discount details
    discount_type VARCHAR(20) NOT NULL CHECK (discount_type IN ('percentage', 'fixed_amount', 'free_shipping')),
    discount_value DECIMAL(8,2) NOT NULL CHECK (discount_value > 0),
    max_discount_amount DECIMAL(8,2), -- For percentage discounts

    -- Usage limits
    usage_limit INTEGER, -- NULL for unlimited
    usage_count INTEGER DEFAULT 0,
    per_user_limit INTEGER DEFAULT 1,

    -- Eligibility
    minimum_order_amount DECIMAL(8,2),
    applicable_categories INTEGER[], -- Category IDs
    applicable_products UUID[], -- Product IDs
    excluded_products UUID[], -- Products not eligible

    -- Validity
    starts_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,

    -- Usage tracking
    first_used_at TIMESTAMP WITH TIME ZONE,
    last_used_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_coupon_limits CHECK (
        (usage_limit IS NULL OR usage_count <= usage_limit) AND
        (expires_at IS NULL OR expires_at > starts_at)
    ),
    CONSTRAINT chk_discount_value CHECK (
        (discount_type = 'percentage' AND discount_value <= 100) OR
        (discount_type != 'percentage')
    )
);

-- Applied coupons (for audit)
CREATE TABLE applied_coupons (
    applied_coupon_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coupon_id UUID REFERENCES coupons(coupon_id),
    order_id UUID REFERENCES orders(order_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id),

    discount_amount DECIMAL(8,2) NOT NULL CHECK (discount_amount >= 0),

    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (coupon_id, order_id)
);

-- ============================================
-- ANALYTICS & REPORTING
-- ============================================

-- Product analytics
CREATE TABLE product_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES products(product_id) ON DELETE CASCADE,
    date DATE NOT NULL,

    -- View metrics
    page_views INTEGER DEFAULT 0,
    unique_visitors INTEGER DEFAULT 0,

    -- Conversion metrics
    add_to_cart_count INTEGER DEFAULT 0,
    purchase_count INTEGER DEFAULT 0,
    conversion_rate DECIMAL(5,2),

    -- Sales metrics
    revenue DECIMAL(12,2) DEFAULT 0.00,
    units_sold INTEGER DEFAULT 0,
    avg_order_value DECIMAL(8,2),

    -- Inventory metrics
    stock_turnover DECIMAL(8,2),
    days_of_inventory INTEGER,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (product_id, date)
) PARTITION BY RANGE (date);

-- Customer analytics
CREATE TABLE customer_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    date DATE NOT NULL,

    -- Engagement metrics
    session_count INTEGER DEFAULT 0,
    page_views INTEGER DEFAULT 0,
    time_on_site_seconds INTEGER DEFAULT 0,

    -- Purchase metrics
    orders_placed INTEGER DEFAULT 0,
    total_spent DECIMAL(10,2) DEFAULT 0.00,
    avg_order_value DECIMAL(8,2),

    -- Product interaction
    products_viewed INTEGER DEFAULT 0,
    cart_additions INTEGER DEFAULT 0,
    reviews_written INTEGER DEFAULT 0,

    -- Customer health score
    engagement_score DECIMAL(5,2), -- Calculated metric

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id, date)
) PARTITION BY RANGE (date);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Core product indexes
CREATE INDEX idx_products_category ON products (category_id);
CREATE INDEX idx_products_brand ON products (brand_id);
CREATE INDEX idx_products_status ON products (status);
CREATE INDEX idx_products_price ON products (base_price);
CREATE INDEX idx_products_search ON products USING GIN (search_vector);

-- Order indexes
CREATE INDEX idx_orders_user ON orders (user_id);
CREATE INDEX idx_orders_status ON orders (status);
CREATE INDEX idx_orders_created_at ON orders (created_at DESC);
CREATE INDEX idx_orders_search ON orders USING GIN (search_vector);

-- Order items indexes
CREATE INDEX idx_order_items_order ON order_items (order_id);
CREATE INDEX idx_order_items_product ON order_items (product_id);

-- Cart indexes
CREATE INDEX idx_carts_user ON carts (user_id);
CREATE INDEX idx_carts_session ON carts (session_id);
CREATE INDEX idx_cart_items_cart ON cart_items (cart_id);

-- Inventory indexes
CREATE INDEX idx_product_inventory_product ON product_inventory (product_id);
CREATE INDEX idx_product_inventory_warehouse ON product_inventory (warehouse_id);

-- Review indexes
CREATE INDEX idx_product_reviews_product ON product_reviews (product_id);
CREATE INDEX idx_product_reviews_user ON product_reviews (user_id);
CREATE INDEX idx_product_reviews_rating ON product_reviews (rating);

-- Analytics indexes
CREATE INDEX idx_product_analytics_product_date ON product_analytics (product_id, date DESC);
CREATE INDEX idx_customer_analytics_user_date ON customer_analytics (user_id, date DESC);

-- ============================================
-- USEFUL VIEWS
-- ============================================

-- Complete product view with all related data
CREATE VIEW product_details AS
SELECT
    p.*,
    b.name AS brand_name,
    b.logo_url AS brand_logo,
    c.name AS category_name,
    c.slug AS category_slug,

    -- Inventory summary
    COALESCE(SUM(pi.quantity_available), 0) AS total_stock,
    COALESCE(SUM(pi.quantity_reserved), 0) AS total_reserved,

    -- Rating summary
    ROUND(AVG(pr.rating), 1) AS avg_rating,
    COUNT(pr.review_id) AS review_count,

    -- Pricing info
    CASE WHEN p.sale_price IS NOT NULL THEN p.sale_price ELSE p.base_price END AS current_price,
    CASE WHEN p.sale_price IS NOT NULL THEN
        ROUND(((p.base_price - p.sale_price) / p.base_price) * 100, 2)
        ELSE 0 END AS discount_percentage

FROM products p
LEFT JOIN brands b ON p.brand_id = b.brand_id
LEFT JOIN categories c ON p.category_id = c.category_id
LEFT JOIN product_inventory pi ON p.product_id = pi.product_id
LEFT JOIN product_reviews pr ON p.product_id = pr.product_id AND pr.status = 'approved'
GROUP BY p.product_id, b.name, b.logo_url, c.name, c.slug;

-- Order summary view
CREATE VIEW order_summary AS
SELECT
    o.*,
    u.first_name || ' ' || u.last_name AS customer_name,
    u.email AS customer_email,

    -- Shipping info
    s.tracking_number,
    s.carrier,
    s.status AS shipping_status,
    s.estimated_delivery_date,

    -- Payment info
    p.status AS payment_status,
    p.provider AS payment_provider,

    -- Item count
    COUNT(oi.order_item_id) AS item_count,
    SUM(oi.quantity) AS total_quantity

FROM orders o
LEFT JOIN users u ON o.user_id = u.user_id
LEFT JOIN shipments s ON o.order_id = s.order_id
LEFT JOIN payments p ON o.order_id = p.order_id
LEFT JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY o.order_id, u.first_name, u.last_name, u.email, s.tracking_number, s.carrier, s.status, s.estimated_delivery_date, p.status, p.provider;

-- ============================================
-- USEFUL FUNCTIONS
-- ============================================

-- Function to calculate product rating
CREATE OR REPLACE FUNCTION update_product_rating(product_uuid UUID)
RETURNS VOID AS $$
DECLARE
    avg_rating DECIMAL(3,2);
    review_count INTEGER;
BEGIN
    SELECT
        ROUND(AVG(rating), 2),
        COUNT(*)
    INTO avg_rating, review_count
    FROM product_reviews
    WHERE product_id = product_uuid AND status = 'approved';

    UPDATE products
    SET
        average_rating = COALESCE(avg_rating, 0),
        total_reviews = review_count,
        updated_at = CURRENT_TIMESTAMP
    WHERE product_id = product_uuid;
END;
$$ LANGUAGE plpgsql;

-- Function to reserve inventory
CREATE OR REPLACE FUNCTION reserve_inventory(
    product_uuid UUID,
    variation_uuid UUID DEFAULT NULL,
    warehouse_id INTEGER DEFAULT NULL,
    quantity INTEGER
)
RETURNS BOOLEAN AS $$
DECLARE
    available_qty INTEGER;
BEGIN
    -- Find available inventory
    SELECT quantity_available - quantity_reserved
    INTO available_qty
    FROM product_inventory
    WHERE product_id = product_uuid
      AND (variation_id = variation_uuid OR variation_uuid IS NULL)
      AND (warehouse_id IS NULL OR warehouse_id = warehouse_id)
    ORDER BY quantity_available - quantity_reserved DESC
    LIMIT 1;

    IF available_qty >= quantity THEN
        UPDATE product_inventory
        SET quantity_reserved = quantity_reserved + quantity,
            updated_at = CURRENT_TIMESTAMP
        WHERE product_id = product_uuid
          AND (variation_id = variation_uuid OR variation_uuid IS NULL)
          AND (warehouse_id IS NULL OR warehouse_id = warehouse_id);

        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Function to apply coupon
CREATE OR REPLACE FUNCTION apply_coupon(
    order_uuid UUID,
    coupon_code VARCHAR
)
RETURNS DECIMAL(8,2) AS $$
DECLARE
    coupon_record coupons%ROWTYPE;
    discount_amount DECIMAL(8,2) := 0;
    order_total DECIMAL(12,2);
BEGIN
    -- Get coupon details
    SELECT * INTO coupon_record
    FROM coupons
    WHERE code = coupon_code
      AND is_active = TRUE
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or expired coupon';
    END IF;

    -- Get order total
    SELECT total_amount INTO order_total
    FROM orders WHERE order_id = order_uuid;

    -- Calculate discount
    CASE coupon_record.discount_type
        WHEN 'percentage' THEN
            discount_amount := LEAST(
                order_total * (coupon_record.discount_value / 100),
                COALESCE(coupon_record.max_discount_amount, order_total)
            );
        WHEN 'fixed_amount' THEN
            discount_amount := LEAST(coupon_record.discount_value, order_total);
        WHEN 'free_shipping' THEN
            -- Would need to check shipping amount separately
            discount_amount := 0;
    END CASE;

    -- Apply coupon to order
    UPDATE orders
    SET discount_amount = discount_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = order_uuid;

    -- Record coupon usage
    INSERT INTO applied_coupons (coupon_id, order_id, discount_amount)
    VALUES (coupon_record.coupon_id, order_uuid, discount_amount);

    -- Update coupon usage count
    UPDATE coupons
    SET usage_count = usage_count + 1,
        last_used_at = CURRENT_TIMESTAMP
    WHERE coupon_id = coupon_record.coupon_id;

    RETURN discount_amount;
END;
$$ LANGUAGE plpgsql;
