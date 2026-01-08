-- Food Delivery & Restaurant Management Database Schema
-- Comprehensive schema for food delivery platforms, restaurant management, and order fulfillment

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "postgis"; -- For delivery zone management

-- ===========================================
-- RESTAURANT AND MENU MANAGEMENT
-- ===========================================

CREATE TABLE restaurants (
    restaurant_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_name VARCHAR(255) NOT NULL,
    restaurant_code VARCHAR(20) UNIQUE NOT NULL,

    -- Location and Contact
    address JSONB,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),
    phone VARCHAR(20),
    email VARCHAR(255),

    -- Restaurant Details
    cuisine_type VARCHAR(50) CHECK (cuisine_type IN (
        'italian', 'chinese', 'japanese', 'indian', 'mexican', 'american',
        'thai', 'french', 'mediterranean', 'korean', 'vietnamese', 'other'
    )),
    price_range VARCHAR(10) CHECK (price_range IN ('$', '$$', '$$$', '$$$$')),
    description TEXT,

    -- Operational Details
    opening_hours JSONB DEFAULT '{}', -- Hours for each day
    delivery_radius_km DECIMAL(5,2),
    minimum_order_amount DECIMAL(8,2) DEFAULT 0,
    estimated_delivery_time_minutes INTEGER DEFAULT 30,

    -- Service Options
    accepts_delivery BOOLEAN DEFAULT TRUE,
    accepts_pickup BOOLEAN DEFAULT TRUE,
    accepts_dine_in BOOLEAN DEFAULT FALSE,
    is_vegetarian_friendly BOOLEAN DEFAULT FALSE,
    is_vegan_friendly BOOLEAN DEFAULT FALSE,

    -- Quality and Ratings
    average_rating DECIMAL(3,2),
    review_count INTEGER DEFAULT 0,
    food_quality_rating DECIMAL(3,1),
    service_rating DECIMAL(3,1),
    value_rating DECIMAL(3,1),

    -- Business Information
    owner_id UUID, -- References restaurant owners
    commission_rate DECIMAL(5,2) DEFAULT 15.0, -- Platform commission percentage
    subscription_plan VARCHAR(20) CHECK (subscription_plan IN ('free', 'basic', 'premium', 'enterprise')),

    -- Status and Operations
    restaurant_status VARCHAR(20) DEFAULT 'active' CHECK (restaurant_status IN (
        'active', 'inactive', 'temporarily_closed', 'permanently_closed', 'under_review'
    )),
    is_featured BOOLEAN DEFAULT FALSE,
    featured_until DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE menu_categories (
    category_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,

    -- Category Details
    category_name VARCHAR(100) NOT NULL,
    category_description TEXT,
    display_order INTEGER DEFAULT 0,

    -- Category Settings
    is_active BOOLEAN DEFAULT TRUE,
    available_from TIME,
    available_until TIME,
    is_seasonal BOOLEAN DEFAULT FALSE,
    seasonal_start_date DATE,
    seasonal_end_date DATE,

    -- Images and Display
    category_image_url VARCHAR(500),
    category_icon VARCHAR(100),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (restaurant_id, category_name)
);

CREATE TABLE menu_items (
    item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
    category_id UUID REFERENCES menu_categories(category_id),

    -- Item Details
    item_name VARCHAR(255) NOT NULL,
    item_description TEXT,
    item_code VARCHAR(20) UNIQUE,

    -- Pricing and Cost
    base_price DECIMAL(8,2) NOT NULL,
    cost_price DECIMAL(6,2), -- Restaurant's cost
    discounted_price DECIMAL(8,2),
    discount_percentage DECIMAL(5,2),

    -- Item Specifications
    preparation_time_minutes INTEGER DEFAULT 15,
    serving_size VARCHAR(50),
    calories INTEGER,
    allergens TEXT[], -- Array of allergens

    -- Dietary Information
    is_vegetarian BOOLEAN DEFAULT FALSE,
    is_vegan BOOLEAN DEFAULT FALSE,
    is_gluten_free BOOLEAN DEFAULT FALSE,
    is_dairy_free BOOLEAN DEFAULT FALSE,
    is_kosher BOOLEAN DEFAULT FALSE,
    is_halal BOOLEAN DEFAULT FALSE,

    -- Availability and Stock
    is_available BOOLEAN DEFAULT TRUE,
    stock_quantity INTEGER, -- NULL means unlimited
    max_daily_orders INTEGER, -- NULL means unlimited
    orders_today INTEGER DEFAULT 0,

    -- Customization Options
    customization_options JSONB DEFAULT '[]', -- Size, spice level, etc.

    -- Images and Media
    item_image_url VARCHAR(500),
    additional_images JSONB DEFAULT '[]',

    -- Popularity Metrics
    popularity_score DECIMAL(5,2) DEFAULT 0,
    total_orders INTEGER DEFAULT 0,
    average_rating DECIMAL(3,2),

    -- Status and Timing
    item_status VARCHAR(20) DEFAULT 'active' CHECK (item_status IN ('active', 'inactive', 'discontinued', 'seasonal')),
    available_from TIME,
    available_until TIME,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (discounted_price IS NULL OR discounted_price < base_price),
    CHECK (stock_quantity IS NULL OR stock_quantity >= 0)
);

CREATE TABLE item_customizations (
    customization_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id UUID NOT NULL REFERENCES menu_items(item_id) ON DELETE CASCADE,

    -- Customization Details
    customization_name VARCHAR(100) NOT NULL,
    customization_type VARCHAR(30) CHECK (customization_type IN (
        'single_choice', 'multiple_choice', 'text_input', 'quantity'
    )),
    display_order INTEGER DEFAULT 0,

    -- Options
    options JSONB DEFAULT '[]', -- Array of option objects with name, price, default
    is_required BOOLEAN DEFAULT FALSE,
    max_selections INTEGER, -- For multiple choice
    min_selections INTEGER DEFAULT 0,

    -- Pricing
    base_price_modifier DECIMAL(6,2) DEFAULT 0,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- CUSTOMER AND USER MANAGEMENT
-- ===========================================

CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_number VARCHAR(20) UNIQUE,

    -- Personal Information
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),

    -- Profile Information
    date_of_birth DATE,
    gender VARCHAR(20),
    preferred_language VARCHAR(10) DEFAULT 'en',

    -- Location and Delivery
    default_address JSONB,
    saved_addresses JSONB DEFAULT '[]',
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),

    -- Preferences and Dietary
    dietary_restrictions TEXT[],
    allergies TEXT[],
    favorite_cuisines TEXT[],
    spice_preference VARCHAR(20) CHECK (spice_preference IN ('mild', 'medium', 'hot', 'very_hot')),

    -- Order History and Loyalty
    total_orders INTEGER DEFAULT 0,
    total_spent DECIMAL(10,2) DEFAULT 0,
    average_order_value DECIMAL(8,2),
    last_order_date DATE,
    favorite_restaurant_id UUID REFERENCES restaurants(restaurant_id),

    -- Loyalty Program
    loyalty_points INTEGER DEFAULT 0,
    loyalty_tier VARCHAR(20) DEFAULT 'bronze' CHECK (loyalty_tier IN ('bronze', 'silver', 'gold', 'platinum')),
    loyalty_member_since DATE,

    -- Communication Preferences
    email_notifications BOOLEAN DEFAULT TRUE,
    sms_notifications BOOLEAN DEFAULT TRUE,
    promotional_emails BOOLEAN DEFAULT TRUE,

    -- Account Status
    account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN ('active', 'inactive', 'suspended', 'banned')),
    email_verified BOOLEAN DEFAULT FALSE,
    phone_verified BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer_addresses (
    address_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,

    -- Address Details
    address_name VARCHAR(50), -- 'Home', 'Work', 'Other'
    street_address VARCHAR(255) NOT NULL,
    apartment VARCHAR(50),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',

    -- Geographic Data
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),

    -- Address Metadata
    delivery_instructions TEXT,
    is_default BOOLEAN DEFAULT FALSE,
    address_type VARCHAR(20) CHECK (address_type IN ('home', 'work', 'other')),

    -- Validation
    is_validated BOOLEAN DEFAULT FALSE,
    validation_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (customer_id, address_name)
);

-- ===========================================
-- ORDER MANAGEMENT AND FULFILLMENT
-- ===========================================

CREATE TABLE orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number VARCHAR(30) UNIQUE NOT NULL,

    -- Order Relationships
    customer_id UUID NOT NULL REFERENCES customers(customer_id),
    restaurant_id UUID NOT NULL REFERENCES restaurants(restaurant_id),

    -- Order Details
    order_type VARCHAR(20) CHECK (order_type IN ('delivery', 'pickup', 'dine_in')) DEFAULT 'delivery',
    order_status VARCHAR(30) DEFAULT 'pending' CHECK (order_status IN (
        'pending', 'confirmed', 'preparing', 'ready_for_pickup', 'out_for_delivery',
        'delivered', 'cancelled', 'refunded', 'failed'
    )),

    -- Order Items and Pricing
    items JSONB NOT NULL, -- Array of order items with customizations
    subtotal DECIMAL(8,2) NOT NULL,
    tax_amount DECIMAL(6,2) DEFAULT 0,
    delivery_fee DECIMAL(6,2) DEFAULT 0,
    service_fee DECIMAL(6,2) DEFAULT 0,
    discount_amount DECIMAL(6,2) DEFAULT 0,
    tip_amount DECIMAL(6,2) DEFAULT 0,
    total_amount DECIMAL(8,2) NOT NULL,

    -- Delivery Information
    delivery_address JSONB,
    delivery_latitude DECIMAL(10,8),
    delivery_longitude DECIMAL(11,8),
    delivery_distance_km DECIMAL(5,2),
    estimated_delivery_time TIMESTAMP WITH TIME ZONE,

    -- Timing
    order_date DATE DEFAULT CURRENT_DATE,
    order_time TIME DEFAULT CURRENT_TIME,
    requested_delivery_time TIMESTAMP WITH TIME ZONE,
    actual_delivery_time TIMESTAMP WITH TIME ZONE,

    -- Assignment and Tracking
    assigned_driver_id UUID, -- References delivery drivers
    driver_assigned_at TIMESTAMP WITH TIME ZONE,
    pickup_time TIMESTAMP WITH TIME ZONE,
    delivery_start_time TIMESTAMP WITH TIME ZONE,

    -- Special Instructions
    customer_notes TEXT,
    restaurant_notes TEXT,
    delivery_instructions TEXT,

    -- Payment Information
    payment_method VARCHAR(30) CHECK (payment_method IN ('card', 'cash', 'digital_wallet', 'loyalty_points')),
    payment_reference VARCHAR(100),
    payment_status VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded')),

    -- Quality and Feedback
    customer_rating INTEGER CHECK (customer_rating BETWEEN 1 AND 5),
    customer_feedback TEXT,
    driver_rating INTEGER CHECK (driver_rating BETWEEN 1 AND 5),
    restaurant_rating INTEGER CHECK (restaurant_rating BETWEEN 1 AND 5),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (total_amount >= 0),
    CHECK (tip_amount >= 0)
);

CREATE TABLE order_items (
    order_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,

    -- Item Details
    item_id UUID NOT NULL REFERENCES menu_items(item_id),
    quantity INTEGER NOT NULL,

    -- Pricing
    unit_price DECIMAL(6,2) NOT NULL,
    total_price DECIMAL(8,2) NOT NULL,

    -- Customizations
    customizations JSONB DEFAULT '[]', -- Selected customization options

    -- Preparation Status
    preparation_status VARCHAR(20) DEFAULT 'pending' CHECK (preparation_status IN (
        'pending', 'preparing', 'ready', 'served', 'cancelled'
    )),
    prepared_at TIMESTAMP WITH TIME ZONE,
    prepared_by UUID, -- Kitchen staff

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity > 0),
    CHECK (unit_price >= 0)
);

CREATE TABLE delivery_zones (
    zone_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(restaurant_id),

    -- Zone Definition
    zone_name VARCHAR(100) NOT NULL,
    zone_boundary GEOGRAPHY(POLYGON, 4326), -- Geographic boundary
    zone_center GEOGRAPHY(POINT, 4326),

    -- Delivery Rules
    base_delivery_fee DECIMAL(5,2) DEFAULT 0,
    delivery_fee_per_km DECIMAL(4,2) DEFAULT 0,
    minimum_order_amount DECIMAL(6,2) DEFAULT 0,
    estimated_delivery_time_minutes INTEGER DEFAULT 30,

    -- Zone Status
    is_active BOOLEAN DEFAULT TRUE,
    zone_priority INTEGER DEFAULT 1, -- For overlapping zones

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- DELIVERY AND LOGISTICS MANAGEMENT
-- ===========================================

CREATE TABLE delivery_drivers (
    driver_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_number VARCHAR(20) UNIQUE NOT NULL,

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20) NOT NULL,

    -- Vehicle Information
    vehicle_type VARCHAR(30) CHECK (vehicle_type IN ('car', 'motorcycle', 'bicycle', 'scooter', 'walking')),
    vehicle_make VARCHAR(50),
    vehicle_model VARCHAR(50),
    license_plate VARCHAR(20),
    vehicle_color VARCHAR(30),

    -- Location and Availability
    current_latitude DECIMAL(10,8),
    current_longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),
    location_updated_at TIMESTAMP WITH TIME ZONE,

    -- Work Status
    driver_status VARCHAR(20) DEFAULT 'offline' CHECK (driver_status IN (
        'offline', 'available', 'busy', 'on_break', 'inactive'
    )),
    current_order_id UUID REFERENCES orders(order_id),

    -- Performance Metrics
    total_deliveries INTEGER DEFAULT 0,
    average_rating DECIMAL(3,2),
    on_time_delivery_rate DECIMAL(5,2),
    customer_rating DECIMAL(3,2),

    -- Earnings and Payments
    total_earnings DECIMAL(10,2) DEFAULT 0,
    pending_payments DECIMAL(8,2) DEFAULT 0,
    payment_cycle VARCHAR(20) DEFAULT 'weekly',

    -- Documents and Compliance
    drivers_license_number VARCHAR(30),
    license_expiry_date DATE,
    insurance_document_url VARCHAR(500),
    background_check_status VARCHAR(20) CHECK (background_check_status IN ('pending', 'approved', 'rejected')),

    -- Work Schedule
    work_schedule JSONB DEFAULT '{}',
    preferred_zones UUID[], -- Preferred delivery zones

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE driver_shifts (
    shift_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES delivery_drivers(driver_id),

    -- Shift Details
    shift_date DATE NOT NULL,
    shift_start_time TIME NOT NULL,
    shift_end_time TIME NOT NULL,
    shift_type VARCHAR(20) CHECK (shift_type IN ('regular', 'peak', 'weekend', 'holiday')),

    -- Performance Metrics
    orders_delivered INTEGER DEFAULT 0,
    distance_traveled_km DECIMAL(6,2) DEFAULT 0,
    earnings DECIMAL(8,2) DEFAULT 0,

    -- Time Tracking
    clock_in_time TIMESTAMP WITH TIME ZONE,
    clock_out_time TIMESTAMP WITH TIME ZONE,
    break_start_time TIMESTAMP WITH TIME ZONE,
    break_end_time TIMESTAMP WITH TIME ZONE,

    -- Status
    shift_status VARCHAR(20) DEFAULT 'scheduled' CHECK (shift_status IN ('scheduled', 'active', 'completed', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (driver_id, shift_date, shift_start_time)
);

CREATE TABLE delivery_tracking (
    tracking_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(order_id),

    -- Location Tracking
    latitude DECIMAL(10,8) NOT NULL,
    longitude DECIMAL(11,8) NOT NULL,
    geolocation GEOGRAPHY(POINT, 4326),

    -- Tracking Details
    tracking_status VARCHAR(30) CHECK (tracking_status IN (
        'order_placed', 'restaurant_confirmed', 'preparing', 'ready_for_pickup',
        'picked_up', 'out_for_delivery', 'arrived_at_destination', 'delivered'
    )),
    status_description VARCHAR(255),

    -- Timing
    tracked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    estimated_arrival_time TIMESTAMP WITH TIME ZONE,

    -- Additional Info
    driver_id UUID REFERENCES delivery_drivers(driver_id),
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- PROMOTIONS AND MARKETING
-- ===========================================

CREATE TABLE promotions (
    promotion_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    promotion_name VARCHAR(255) NOT NULL,
    promotion_code VARCHAR(20) UNIQUE,

    -- Promotion Details
    promotion_type VARCHAR(30) CHECK (promotion_type IN (
        'percentage_discount', 'fixed_amount_discount', 'free_delivery',
        'free_item', 'loyalty_points_bonus', 'first_order_discount'
    )),
    description TEXT,

    -- Discount Rules
    discount_percentage DECIMAL(5,2),
    discount_amount DECIMAL(6,2),
    maximum_discount DECIMAL(6,2),
    minimum_order_amount DECIMAL(6,2),

    -- Applicability
    applicable_restaurants UUID[], -- Specific restaurants
    applicable_items UUID[], -- Specific menu items
    applicable_customers UUID[], -- Specific customers
    applicable_cuisines TEXT[], -- Specific cuisine types

    -- Timing and Availability
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

    -- Targeting
    customer_segment VARCHAR(30) CHECK (customer_segment IN ('new', 'returning', 'loyalty', 'all')),
    order_type_restriction VARCHAR(20) CHECK (order_type_restriction IN ('delivery', 'pickup', 'all')),

    -- Marketing
    promotion_image_url VARCHAR(500),
    terms_and_conditions TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE promotion_usage (
    usage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    promotion_id UUID NOT NULL REFERENCES promotions(promotion_id),
    order_id UUID NOT NULL REFERENCES orders(order_id),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Usage Details
    discount_applied DECIMAL(6,2) NOT NULL,
    promotion_code_used VARCHAR(20),

    -- Tracking
    used_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (promotion_id, order_id)
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

CREATE TABLE order_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_hour INTEGER CHECK (report_hour BETWEEN 0 AND 23),

    -- Order Metrics
    total_orders INTEGER DEFAULT 0,
    total_revenue DECIMAL(12,2) DEFAULT 0,
    average_order_value DECIMAL(8,2),

    -- Order Types
    delivery_orders INTEGER DEFAULT 0,
    pickup_orders INTEGER DEFAULT 0,
    dine_in_orders INTEGER DEFAULT 0,

    -- Performance Metrics
    average_delivery_time_minutes DECIMAL(5,2),
    on_time_delivery_rate DECIMAL(5,2),
    customer_satisfaction_rating DECIMAL(3,2),

    -- Geographic Metrics
    orders_by_zone JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (report_date, report_hour)
);

CREATE TABLE restaurant_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(restaurant_id),

    -- Time Dimensions
    report_date DATE NOT NULL,

    -- Performance Metrics
    total_orders INTEGER DEFAULT 0,
    total_revenue DECIMAL(10,2) DEFAULT 0,
    average_order_value DECIMAL(8,2),
    average_preparation_time DECIMAL(5,2),

    -- Item Performance
    top_items JSONB DEFAULT '[]',
    top_categories JSONB DEFAULT '[]',

    -- Customer Metrics
    unique_customers INTEGER DEFAULT 0,
    new_customers INTEGER DEFAULT 0,
    repeat_customers INTEGER DEFAULT 0,

    -- Quality Metrics
    average_rating DECIMAL(3,2),
    review_count INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (restaurant_id, report_date)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Restaurant and menu indexes
CREATE INDEX idx_restaurants_location ON restaurants USING gist (geolocation);
CREATE INDEX idx_restaurants_cuisine_status ON restaurants (cuisine_type, restaurant_status);
CREATE INDEX idx_menu_items_restaurant ON menu_items (restaurant_id, item_status);
CREATE INDEX idx_menu_items_category ON menu_items (category_id);

-- Customer indexes
CREATE INDEX idx_customers_email ON customers (email);
CREATE INDEX idx_customers_location ON customers USING gist (geolocation);
CREATE INDEX idx_customer_addresses_customer ON customer_addresses (customer_id);

-- Order indexes
CREATE INDEX idx_orders_customer_date ON orders (customer_id, order_date DESC);
CREATE INDEX idx_orders_restaurant_status ON orders (restaurant_id, order_status);
CREATE INDEX idx_orders_delivery_time ON orders (estimated_delivery_time) WHERE order_status IN ('confirmed', 'preparing', 'out_for_delivery');
CREATE INDEX idx_order_items_order ON order_items (order_id);

-- Delivery indexes
CREATE INDEX idx_delivery_drivers_location ON delivery_drivers USING gist (geolocation);
CREATE INDEX idx_delivery_drivers_status ON delivery_drivers (driver_status);
CREATE INDEX idx_delivery_tracking_order ON delivery_tracking (order_id, tracked_at DESC);
CREATE INDEX idx_delivery_zones_restaurant ON delivery_zones (restaurant_id);

-- Promotion indexes
CREATE INDEX idx_promotions_active ON promotions (promotion_id) WHERE is_active = TRUE;
CREATE INDEX idx_promotion_usage_promotion ON promotion_usage (promotion_id);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Restaurant performance dashboard
CREATE VIEW restaurant_performance AS
SELECT
    r.restaurant_id,
    r.restaurant_name,
    r.cuisine_type,
    r.average_rating,

    -- Today's performance
    COUNT(o.order_id) as orders_today,
    COALESCE(SUM(o.total_amount), 0) as revenue_today,
    AVG(o.total_amount) as avg_order_value_today,

    -- Current status
    r.restaurant_status,
    COUNT(CASE WHEN o.order_status IN ('preparing', 'ready_for_pickup') THEN 1 END) as active_orders,
    COUNT(CASE WHEN o.order_status = 'out_for_delivery' THEN 1 END) as orders_out_for_delivery,

    -- Menu availability
    COUNT(mi.item_id) as total_menu_items,
    COUNT(CASE WHEN mi.is_available THEN 1 END) as available_items,
    ROUND(COUNT(CASE WHEN mi.is_available THEN 1 END)::DECIMAL / COUNT(mi.item_id) * 100, 1) as menu_availability_percentage,

    -- Customer metrics
    COUNT(DISTINCT o.customer_id) as unique_customers_today,
    AVG(o.customer_rating) as avg_customer_rating_today,

    -- Delivery performance
    AVG(EXTRACT(EPOCH FROM (o.actual_delivery_time - o.estimated_delivery_time))/60) as avg_delivery_delay_minutes,
    COUNT(CASE WHEN o.actual_delivery_time <= o.estimated_delivery_time THEN 1 END)::DECIMAL /
    NULLIF(COUNT(o.order_id), 0) * 100 as on_time_delivery_rate

FROM restaurants r
LEFT JOIN orders o ON r.restaurant_id = o.restaurant_id
    AND o.order_date = CURRENT_DATE
LEFT JOIN menu_items mi ON r.restaurant_id = mi.restaurant_id
    AND mi.item_status = 'active'
GROUP BY r.restaurant_id, r.restaurant_name, r.cuisine_type, r.average_rating, r.restaurant_status;

-- Customer order history and preferences
CREATE VIEW customer_order_history AS
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name as customer_name,
    c.email,

    -- Order statistics
    COUNT(o.order_id) as total_orders,
    COUNT(DISTINCT o.restaurant_id) as restaurants_used,
    SUM(o.total_amount) as total_spent,
    AVG(o.total_amount) as avg_order_value,
    MAX(o.order_date) as last_order_date,

    -- Order patterns
    MODE() WITHIN GROUP (ORDER BY o.order_type) as preferred_order_type,
    MODE() WITHIN GROUP (ORDER BY r.cuisine_type) as favorite_cuisine,
    AVG(o.customer_rating) as avg_rating_given,

    -- Loyalty status
    c.loyalty_tier,
    c.loyalty_points,
    CASE
        WHEN COUNT(o.order_id) >= 50 THEN 'VIP'
        WHEN COUNT(o.order_id) >= 20 THEN 'Regular'
        WHEN COUNT(o.order_id) >= 5 THEN 'Occasional'
        ELSE 'New'
    END as customer_segment,

    -- Recent activity
    COUNT(CASE WHEN o.order_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as orders_last_30_days,
    SUM(CASE WHEN o.order_date >= CURRENT_DATE - INTERVAL '30 days' THEN o.total_amount END) as spent_last_30_days

FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.order_status NOT IN ('cancelled', 'failed')
LEFT JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE c.account_status = 'active'
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.loyalty_tier, c.loyalty_points;

-- Delivery driver performance
CREATE VIEW driver_performance AS
SELECT
    dd.driver_id,
    dd.first_name || ' ' || dd.last_name as driver_name,
    dd.vehicle_type,

    -- Today's performance
    COUNT(o.order_id) as deliveries_today,
    SUM(o.delivery_fee) as earnings_today,
    AVG(o.customer_rating) as avg_rating_today,

    -- Overall performance
    dd.total_deliveries,
    dd.average_rating,
    dd.on_time_delivery_rate,

    -- Current status
    dd.driver_status,
    CASE WHEN dd.current_order_id IS NOT NULL THEN 'On delivery' ELSE 'Available' END as current_status,

    -- Geographic efficiency
    AVG(o.delivery_distance_km) as avg_delivery_distance_today,
    SUM(o.delivery_distance_km) as total_distance_today,

    -- Time performance
    AVG(EXTRACT(EPOCH FROM (o.actual_delivery_time - o.delivery_start_time))/60) as avg_delivery_time_minutes,
    COUNT(CASE WHEN o.actual_delivery_time <= o.estimated_delivery_time THEN 1 END) as on_time_deliveries_today

FROM delivery_drivers dd
LEFT JOIN orders o ON dd.driver_id = o.assigned_driver_id
    AND o.order_date = CURRENT_DATE
    AND o.order_status IN ('delivered', 'out_for_delivery')
GROUP BY dd.driver_id, dd.first_name, dd.last_name, dd.vehicle_type,
         dd.total_deliveries, dd.average_rating, dd.on_time_delivery_rate,
         dd.driver_status, dd.current_order_id;

-- Popular menu items analysis
CREATE VIEW menu_item_popularity AS
SELECT
    mi.item_id,
    mi.item_name,
    r.restaurant_name,
    mc.category_name,

    -- Order statistics
    COUNT(oi.order_item_id) as total_orders,
    SUM(oi.quantity) as total_quantity_ordered,
    SUM(oi.total_price) as total_revenue,

    -- Performance metrics
    AVG(mi.average_rating) as avg_item_rating,
    mi.popularity_score,

    -- Trends
    COUNT(CASE WHEN o.order_date >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as orders_last_week,
    COUNT(CASE WHEN o.order_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as orders_last_month,

    -- Availability
    mi.is_available,
    CASE
        WHEN mi.stock_quantity IS NULL THEN 'Unlimited'
        WHEN mi.stock_quantity > 10 THEN 'In stock'
        WHEN mi.stock_quantity > 0 THEN 'Low stock'
        ELSE 'Out of stock'
    END as stock_status,

    -- Pricing
    mi.base_price,
    mi.discounted_price,
    CASE WHEN mi.discounted_price IS NOT NULL
         THEN ROUND((1 - mi.discounted_price / mi.base_price) * 100, 1)
         ELSE 0 END as discount_percentage

FROM menu_items mi
JOIN restaurants r ON mi.restaurant_id = r.restaurant_id
LEFT JOIN menu_categories mc ON mi.category_id = mc.category_id
LEFT JOIN order_items oi ON mi.item_id = oi.item_id
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE mi.item_status = 'active'
GROUP BY mi.item_id, mi.item_name, r.restaurant_name, mc.category_name,
         mi.average_rating, mi.popularity_score, mi.is_available,
         mi.stock_quantity, mi.base_price, mi.discounted_price;

-- ===========================================
-- FUNCTIONS FOR FOOD DELIVERY OPERATIONS
-- =========================================--

-- Function to calculate delivery fee based on distance and zone
CREATE OR REPLACE FUNCTION calculate_delivery_fee(
    restaurant_uuid UUID,
    customer_lat DECIMAL,
    customer_lng DECIMAL,
    order_amount DECIMAL DEFAULT 0
)
RETURNS TABLE (
    delivery_fee DECIMAL,
    delivery_zone_id UUID,
    estimated_time_minutes INTEGER,
    distance_km DECIMAL
) AS $$
DECLARE
    restaurant_location GEOGRAPHY(POINT, 4326);
    customer_location GEOGRAPHY(POINT, 4326);
    delivery_distance DECIMAL;
    zone_record delivery_zones%ROWTYPE;
BEGIN
    -- Get restaurant location
    SELECT geolocation INTO restaurant_location
    FROM restaurants WHERE restaurant_id = restaurant_uuid;

    -- Create customer location point
    customer_location := ST_Point(customer_lng, customer_lat)::GEOGRAPHY(POINT, 4326);

    -- Calculate distance in kilometers
    delivery_distance := ST_Distance(restaurant_location, customer_location) / 1000;

    -- Find applicable delivery zone
    SELECT * INTO zone_record
    FROM delivery_zones
    WHERE restaurant_id = restaurant_uuid
      AND is_active = TRUE
      AND ST_Contains(zone_boundary, customer_location)
    ORDER BY zone_priority DESC
    LIMIT 1;

    -- Calculate delivery fee
    IF zone_record.zone_id IS NOT NULL THEN
        RETURN QUERY SELECT
            GREATEST(zone_record.base_delivery_fee + (delivery_distance * zone_record.delivery_fee_per_km), 0),
            zone_record.zone_id,
            zone_record.estimated_delivery_time_minutes,
            ROUND(delivery_distance, 2);
    ELSE
        -- Default calculation if no zone found
        RETURN QUERY SELECT
            GREATEST(2.99 + (delivery_distance * 0.50), 0),
            NULL::UUID,
            30,
            ROUND(delivery_distance, 2);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to assign optimal delivery driver
CREATE OR REPLACE FUNCTION assign_delivery_driver(order_uuid UUID)
RETURNS UUID AS $$
DECLARE
    order_record orders%ROWTYPE;
    restaurant_location GEOGRAPHY(POINT, 4326);
    customer_location GEOGRAPHY(POINT, 4326);
    assigned_driver_uuid UUID;
BEGIN
    -- Get order details
    SELECT * INTO order_record FROM orders WHERE order_id = order_uuid;

    -- Get locations
    SELECT geolocation INTO restaurant_location
    FROM restaurants WHERE restaurant_id = order_record.restaurant_id;

    customer_location := ST_Point(order_record.delivery_longitude, order_record.delivery_latitude)::GEOGRAPHY(POINT, 4326);

    -- Find best available driver
    SELECT dd.driver_id INTO assigned_driver_uuid
    FROM delivery_drivers dd
    WHERE dd.driver_status = 'available'
      AND dd.current_order_id IS NULL
      -- Check if driver is in preferred zones (if applicable)
      AND (dd.preferred_zones IS NULL OR
           EXISTS (SELECT 1 FROM delivery_zones dz
                  WHERE dz.restaurant_id = order_record.restaurant_id
                    AND dz.zone_id = ANY(dd.preferred_zones)
                    AND ST_Contains(dz.zone_boundary, customer_location)))
    ORDER BY
        -- Prioritize drivers closer to restaurant
        ST_Distance(dd.geolocation, restaurant_location),
        -- Then by performance rating
        dd.average_rating DESC,
        -- Finally by total deliveries (experience)
        dd.total_deliveries DESC
    LIMIT 1;

    -- Update driver status and assignment
    IF assigned_driver_uuid IS NOT NULL THEN
        UPDATE delivery_drivers SET
            driver_status = 'busy',
            current_order_id = order_uuid
        WHERE driver_id = assigned_driver_uuid;

        UPDATE orders SET
            assigned_driver_id = assigned_driver_uuid,
            driver_assigned_at = CURRENT_TIMESTAMP,
            order_status = 'out_for_delivery'
        WHERE order_id = order_uuid;
    END IF;

    RETURN assigned_driver_uuid;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate order total with promotions
CREATE OR REPLACE FUNCTION calculate_order_total(
    customer_uuid UUID,
    restaurant_uuid UUID,
    items JSONB,
    delivery_address JSONB,
    promo_code VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    subtotal DECIMAL,
    tax_amount DECIMAL,
    delivery_fee DECIMAL,
    service_fee DECIMAL,
    discount_amount DECIMAL,
    total_amount DECIMAL,
    applied_promotion JSONB
) AS $$
DECLARE
    subtotal_val DECIMAL := 0;
    delivery_fee_val DECIMAL := 0;
    service_fee_val DECIMAL := 0;
    discount_val DECIMAL := 0;
    tax_rate DECIMAL := 0.08; -- 8% tax
    promotion_record promotions%ROWTYPE;
    applied_promo JSONB := NULL;
    item_record JSONB;
    menu_item menu_items%ROWTYPE;
BEGIN
    -- Calculate subtotal from items
    FOR item_record IN SELECT * FROM jsonb_array_elements(items)
    LOOP
        SELECT * INTO menu_item FROM menu_items WHERE item_id = (item_record->>'item_id')::UUID;

        -- Apply customizations pricing
        subtotal_val := subtotal_val + (menu_item.base_price * (item_record->>'quantity')::INTEGER);
    END LOOP;

    -- Calculate delivery fee
    SELECT df.delivery_fee INTO delivery_fee_val
    FROM calculate_delivery_fee(
        restaurant_uuid,
        (delivery_address->>'latitude')::DECIMAL,
        (delivery_address->>'longitude')::DECIMAL,
        subtotal_val
    ) df;

    -- Calculate service fee (platform fee)
    service_fee_val := ROUND(subtotal_val * 0.02, 2); -- 2% service fee

    -- Apply promotion if provided
    IF promo_code IS NOT NULL THEN
        SELECT * INTO promotion_record FROM promotions
        WHERE promotion_code = promo_code AND is_active = TRUE;

        IF FOUND THEN
            -- Check eligibility
            IF (promotion_record.applicable_customers IS NULL OR customer_uuid = ANY(promotion_record.applicable_customers))
               AND (promotion_record.minimum_order_amount IS NULL OR subtotal_val >= promotion_record.minimum_order_amount) THEN

                -- Calculate discount
                CASE promotion_record.promotion_type
                    WHEN 'percentage_discount' THEN
                        discount_val := ROUND(subtotal_val * promotion_record.discount_percentage / 100, 2);
                    WHEN 'fixed_amount_discount' THEN
                        discount_val := promotion_record.discount_amount;
                    WHEN 'free_delivery' THEN
                        discount_val := delivery_fee_val;
                        delivery_fee_val := 0;
                END CASE;

                -- Apply maximum discount limit
                IF promotion_record.maximum_discount IS NOT NULL THEN
                    discount_val := LEAST(discount_val, promotion_record.maximum_discount);
                END IF;

                applied_promo := jsonb_build_object(
                    'promotion_id', promotion_record.promotion_id,
                    'promotion_name', promotion_record.promotion_name,
                    'discount_applied', discount_val
                );

                -- Update promotion usage
                UPDATE promotions SET current_usage = current_usage + 1
                WHERE promotion_id = promotion_record.promotion_id;
            END IF;
        END IF;
    END IF;

    RETURN QUERY SELECT
        subtotal_val,
        ROUND((subtotal_val - discount_val) * tax_rate, 2),
        delivery_fee_val,
        service_fee_val,
        discount_val,
        ROUND(subtotal_val + ((subtotal_val - discount_val) * tax_rate) + delivery_fee_val + service_fee_val - discount_val, 2),
        applied_promo;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample restaurant
INSERT INTO restaurants (
    restaurant_name, restaurant_code, cuisine_type, price_range,
    address, latitude, longitude, phone, opening_hours, minimum_order_amount
) VALUES (
    'Mario''s Italian Kitchen', 'MRIT001', 'italian', '$$',
    '{"street": "123 Main St", "city": "New York", "state": "NY", "zip": "10001"}',
    40.7128, -74.0060, '+1-555-0123',
    '{"monday": {"open": "11:00", "close": "22:00"}, "tuesday": {"open": "11:00", "close": "22:00"}}',
    15.00
);

-- Insert sample menu category
INSERT INTO menu_categories (restaurant_id, category_name, display_order) VALUES
((SELECT restaurant_id FROM restaurants WHERE restaurant_code = 'MRIT001' LIMIT 1), 'Pasta', 1),
((SELECT restaurant_id FROM restaurants WHERE restaurant_code = 'MRIT001' LIMIT 1), 'Pizza', 2);

-- Insert sample menu items
INSERT INTO menu_items (
    restaurant_id, category_id, item_name, base_price, description,
    preparation_time_minutes, is_vegetarian
) VALUES
((SELECT restaurant_id FROM restaurants WHERE restaurant_code = 'MRIT001' LIMIT 1),
 (SELECT category_id FROM menu_categories WHERE category_name = 'Pasta' LIMIT 1),
 'Spaghetti Carbonara', 18.99, 'Classic Italian pasta with eggs, cheese, and pancetta', 12, FALSE);

-- Insert sample customer
INSERT INTO customers (customer_number, first_name, last_name, email, phone) VALUES
('CUST001', 'John', 'Doe', 'john.doe@email.com', '+1-555-0456');

-- Insert sample order
INSERT INTO orders (
    order_number, customer_id, restaurant_id, order_type, subtotal,
    delivery_fee, total_amount, delivery_address, payment_method
) VALUES (
    'ORD001234', (SELECT customer_id FROM customers WHERE customer_number = 'CUST001' LIMIT 1),
    (SELECT restaurant_id FROM restaurants WHERE restaurant_code = 'MRIT001' LIMIT 1),
    'delivery', 18.99, 3.99, 25.96,
    '{"street": "456 Oak Ave", "city": "New York", "state": "NY", "zip": "10002"}',
    'card'
);

-- Insert sample delivery driver
INSERT INTO delivery_drivers (driver_number, first_name, last_name, phone, vehicle_type) VALUES
('DRV001', 'Mike', 'Johnson', '+1-555-0789', 'car');

-- This food delivery schema provides comprehensive infrastructure for restaurant ordering,
-- delivery management, customer service, and operational analytics.
