-- E-commerce Platform Starter Schema
-- Minimal but complete schema for launching an e-commerce platform
-- Includes essential tables for products, orders, users, and inventory

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ===========================================
-- USERS AND AUTHENTICATION
-- ===========================================

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_addresses (
    address_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    address_type VARCHAR(20) DEFAULT 'shipping' CHECK (address_type IN ('billing', 'shipping')),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    company VARCHAR(100),
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(50) DEFAULT 'USA',
    phone VARCHAR(20),
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- PRODUCTS AND CATALOG
-- ===========================================

CREATE TABLE categories (
    category_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_name VARCHAR(100) NOT NULL,
    slug VARCHAR(120) UNIQUE NOT NULL,
    description TEXT,
    parent_id UUID REFERENCES categories(category_id),
    is_active BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_name VARCHAR(255) NOT NULL,
    slug VARCHAR(280) UNIQUE NOT NULL,
    description TEXT,
    short_description VARCHAR(500),
    sku VARCHAR(100) UNIQUE NOT NULL,
    barcode VARCHAR(50),
    category_id UUID REFERENCES categories(category_id),
    brand VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,
    track_inventory BOOLEAN DEFAULT TRUE,
    weight_grams INTEGER,
    dimensions_json JSONB,  -- {"length": 10, "width": 5, "height": 2}
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE product_variants (
    variant_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    variant_name VARCHAR(255),  -- e.g., "Size: Large, Color: Red"
    sku VARCHAR(100) UNIQUE,
    price DECIMAL(10,2) NOT NULL,
    compare_at_price DECIMAL(10,2),
    cost_price DECIMAL(10,2),
    inventory_quantity INTEGER DEFAULT 0,
    is_available BOOLEAN DEFAULT TRUE,
    weight_grams INTEGER,
    option1 VARCHAR(100),  -- Size
    option2 VARCHAR(100),  -- Color
    option3 VARCHAR(100),  -- Material
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE product_images (
    image_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(variant_id),
    image_url VARCHAR(500) NOT NULL,
    alt_text VARCHAR(255),
    sort_order INTEGER DEFAULT 0,
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INVENTORY MANAGEMENT
-- ===========================================

CREATE TABLE inventory_locations (
    location_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    location_name VARCHAR(255) NOT NULL,
    address_line_1 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE inventory_items (
    inventory_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    variant_id UUID NOT NULL REFERENCES product_variants(variant_id),
    location_id UUID NOT NULL REFERENCES inventory_locations(location_id),
    quantity_available INTEGER DEFAULT 0,
    quantity_reserved INTEGER DEFAULT 0,
    reorder_point INTEGER DEFAULT 0,
    reorder_quantity INTEGER DEFAULT 0,
    last_counted_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (variant_id, location_id)
);

-- ===========================================
-- ORDERS AND CHECKOUT
-- ===========================================

CREATE TABLE carts (
    cart_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(user_id),
    session_id VARCHAR(255),  -- For anonymous users
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 days')
);

CREATE TABLE cart_items (
    cart_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cart_id UUID NOT NULL REFERENCES carts(cart_id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(variant_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (cart_id, variant_id)
);

CREATE TABLE orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number VARCHAR(50) UNIQUE NOT NULL,
    user_id UUID REFERENCES users(user_id),
    email VARCHAR(255) NOT NULL,
    order_status VARCHAR(30) DEFAULT 'pending' CHECK (order_status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded')),
    payment_status VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')),
    fulfillment_status VARCHAR(20) DEFAULT 'unfulfilled' CHECK (fulfillment_status IN ('unfulfilled', 'partial', 'fulfilled')),
    subtotal DECIMAL(10,2) NOT NULL,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    shipping_amount DECIMAL(10,2) DEFAULT 0,
    discount_amount DECIMAL(10,2) DEFAULT 0,
    total_amount DECIMAL(10,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    shipping_address_id UUID REFERENCES user_addresses(address_id),
    billing_address_id UUID REFERENCES user_addresses(address_id),
    order_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_items (
    order_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(variant_id),
    product_name VARCHAR(255) NOT NULL,
    variant_name VARCHAR(255),
    sku VARCHAR(100),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- PAYMENTS AND TRANSACTIONS
-- ===========================================

CREATE TABLE payment_methods (
    payment_method_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    payment_type VARCHAR(20) NOT NULL CHECK (payment_type IN ('credit_card', 'debit_card', 'paypal', 'bank_transfer', 'digital_wallet')),
    provider VARCHAR(50),  -- 'stripe', 'paypal', 'braintree', etc.
    is_default BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES orders(order_id),
    payment_method_id UUID REFERENCES payment_methods(payment_method_id),
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('charge', 'refund', 'authorization')),
    provider_transaction_id VARCHAR(255) UNIQUE,
    amount DECIMAL(10,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    transaction_status VARCHAR(20) DEFAULT 'pending' CHECK (transaction_status IN ('pending', 'processing', 'completed', 'failed', 'cancelled', 'refunded')),
    provider_response JSONB,
    error_message TEXT,
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SHIPPING AND FULFILLMENT
-- ===========================================

CREATE TABLE shipping_methods (
    shipping_method_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    method_name VARCHAR(100) NOT NULL,
    carrier VARCHAR(50),  -- 'UPS', 'FedEx', 'USPS', 'DHL'
    service_type VARCHAR(50),  -- 'Ground', '2-Day', 'Overnight'
    estimated_days_min INTEGER,
    estimated_days_max INTEGER,
    cost DECIMAL(8,2),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE shipments (
    shipment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(order_id),
    shipping_method_id UUID NOT NULL REFERENCES shipping_methods(shipping_method_id),
    tracking_number VARCHAR(100),
    carrier VARCHAR(50),
    shipment_status VARCHAR(20) DEFAULT 'pending' CHECK (shipment_status IN ('pending', 'processing', 'shipped', 'delivered', 'returned', 'cancelled')),
    shipped_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    estimated_delivery_date DATE,
    actual_delivery_date DATE,
    shipping_cost DECIMAL(8,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE shipment_items (
    shipment_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shipment_id UUID NOT NULL REFERENCES shipments(shipment_id) ON DELETE CASCADE,
    order_item_id UUID NOT NULL REFERENCES order_items(order_item_id),
    quantity_shipped INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- User indexes
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_active ON users (is_active);

-- Product indexes
CREATE INDEX idx_products_category ON products (category_id);
CREATE INDEX idx_products_active ON products (is_active);
CREATE INDEX idx_products_sku ON products (sku);
CREATE INDEX idx_product_variants_product ON product_variants (product_id);
CREATE INDEX idx_product_variants_price ON product_variants (price);

-- Order indexes
CREATE INDEX idx_orders_user ON orders (user_id);
CREATE INDEX idx_orders_status ON orders (order_status);
CREATE INDEX idx_orders_created ON orders (created_at DESC);
CREATE INDEX idx_order_items_order ON order_items (order_id);

-- Inventory indexes
CREATE INDEX idx_inventory_variant ON inventory_items (variant_id);
CREATE INDEX idx_inventory_location ON inventory_items (location_id);

-- Transaction indexes
CREATE INDEX idx_transactions_order ON transactions (order_id);
CREATE INDEX idx_transactions_status ON transactions (transaction_status);

-- Shipment indexes
CREATE INDEX idx_shipments_order ON shipments (order_id);
CREATE INDEX idx_shipments_status ON shipments (shipment_status);
CREATE INDEX idx_shipments_tracking ON shipments (tracking_number);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Product catalog view
CREATE VIEW product_catalog AS
SELECT
    p.product_id,
    p.product_name,
    p.slug,
    p.description,
    p.sku,
    c.category_name,
    p.brand,
    p.is_active,
    p.is_featured,
    pv.variant_id,
    pv.variant_name,
    pv.price,
    pv.compare_at_price,
    pv.inventory_quantity,
    pv.is_available,
    pi.image_url as primary_image,
    p.created_at
FROM products p
LEFT JOIN categories c ON p.category_id = c.category_id
LEFT JOIN product_variants pv ON p.product_id = pv.product_id
LEFT JOIN product_images pi ON p.product_id = pi.product_id AND pi.is_primary = TRUE
WHERE p.is_active = TRUE;

-- Order summary view
CREATE VIEW order_summary AS
SELECT
    o.order_id,
    o.order_number,
    o.email,
    o.order_status,
    o.payment_status,
    o.fulfillment_status,
    o.total_amount,
    o.currency_code,
    COUNT(oi.order_item_id) as item_count,
    SUM(oi.quantity) as total_quantity,
    o.created_at,
    o.updated_at
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY o.order_id, o.order_number, o.email, o.order_status,
         o.payment_status, o.fulfillment_status, o.total_amount,
         o.currency_code, o.created_at, o.updated_at;

-- Inventory summary view
CREATE VIEW inventory_summary AS
SELECT
    p.product_name,
    p.sku,
    pv.variant_name,
    SUM(ii.quantity_available) as total_available,
    SUM(ii.quantity_reserved) as total_reserved,
    SUM(ii.quantity_available - ii.quantity_reserved) as available_to_sell,
    MIN(ii.quantity_available) as min_location_quantity,
    MAX(ii.quantity_available) as max_location_quantity,
    COUNT(ii.location_id) as location_count
FROM products p
JOIN product_variants pv ON p.product_id = pv.product_id
JOIN inventory_items ii ON pv.variant_id = ii.variant_id
WHERE p.track_inventory = TRUE
GROUP BY p.product_id, p.product_name, p.sku, pv.variant_id, pv.variant_name;

-- ===========================================
-- BASIC FUNCTIONS
-- ===========================================

-- Function to calculate order total
CREATE OR REPLACE FUNCTION calculate_order_total(order_id_param UUID)
RETURNS DECIMAL(10,2) AS $$
DECLARE
    total DECIMAL(10,2);
BEGIN
    SELECT
        subtotal + COALESCE(tax_amount, 0) + COALESCE(shipping_amount, 0) - COALESCE(discount_amount, 0)
    INTO total
    FROM orders
    WHERE order_id = order_id_param;

    RETURN total;
END;
$$ LANGUAGE plpgsql;

-- Function to check inventory availability
CREATE OR REPLACE FUNCTION check_inventory_availability(variant_id_param UUID, quantity_needed INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    available_quantity INTEGER;
BEGIN
    SELECT SUM(quantity_available - quantity_reserved)
    INTO available_quantity
    FROM inventory_items
    WHERE variant_id = variant_id_param;

    RETURN COALESCE(available_quantity, 0) >= quantity_needed;
END;
$$ LANGUAGE plpgsql;

-- Function to reserve inventory
CREATE OR REPLACE FUNCTION reserve_inventory(variant_id_param UUID, location_id_param UUID, quantity_param INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    current_available INTEGER;
BEGIN
    -- Check current availability
    SELECT quantity_available - quantity_reserved
    INTO current_available
    FROM inventory_items
    WHERE variant_id = variant_id_param AND location_id = location_id_param;

    IF current_available >= quantity_param THEN
        UPDATE inventory_items
        SET quantity_reserved = quantity_reserved + quantity_param,
            updated_at = CURRENT_TIMESTAMP
        WHERE variant_id = variant_id_param AND location_id = location_id_param;

        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample category
INSERT INTO categories (category_name, slug, description) VALUES
('Electronics', 'electronics', 'Electronic devices and gadgets'),
('Clothing', 'clothing', 'Fashion and apparel');

-- Insert sample user
INSERT INTO users (email, password_hash, first_name, last_name) VALUES
('john.doe@example.com', '$2b$10$dummy.hash.here', 'John', 'Doe');

-- Insert sample product
INSERT INTO products (product_name, slug, description, sku, category_id) VALUES
('Wireless Headphones', 'wireless-headphones', 'High-quality wireless headphones', 'WH-001',
 (SELECT category_id FROM categories WHERE slug = 'electronics' LIMIT 1));

-- Insert sample product variant
INSERT INTO product_variants (product_id, variant_name, sku, price, inventory_quantity) VALUES
((SELECT product_id FROM products WHERE sku = 'WH-001' LIMIT 1), 'Black', 'WH-001-BLK', 99.99, 50);

-- Insert sample inventory location
INSERT INTO inventory_locations (location_name, address_line_1, city, state_province, postal_code) VALUES
('Main Warehouse', '123 Industrial Blvd', 'Springfield', 'IL', '62701');

-- This starter schema provides the essential foundation for an e-commerce platform
-- and can be extended with additional features as needed.
