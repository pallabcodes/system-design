# E-Commerce Platform Schema Design

## Overview

This comprehensive e-commerce schema supports online shopping, marketplace functionality, inventory management, order processing, payments, shipping, and customer analytics. The design scales to handle millions of products, orders, and users while maintaining performance and data integrity.

## Key Features

- **Multi-Vendor Marketplace**: Support for multiple sellers and vendors
- **Complex Product Catalog**: Products with variations, attributes, and media
- **Advanced Inventory Management**: Multi-warehouse, stock tracking, and reservations
- **Order Processing**: Complete order lifecycle from cart to delivery
- **Payment Processing**: Multiple payment methods and providers
- **Shipping & Fulfillment**: Multi-carrier support with tracking
- **Customer Analytics**: Comprehensive user behavior and purchase analytics
- **Review & Rating System**: Product reviews with voting and moderation
- **Promotions & Discounts**: Coupons, discounts, and promotional campaigns
- **Search & Discovery**: Full-text search with advanced filtering

## Database Architecture

### Core Entities

#### User Management
```sql
-- Multi-role user system with authentication
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    user_type VARCHAR(20), -- 'customer', 'seller', 'admin'
    -- ... authentication and profile fields
);

-- Flexible address management
CREATE TABLE addresses (
    address_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    address_type VARCHAR(20), -- 'shipping', 'billing'
    -- ... complete address fields with geocoding
);
```

#### Product Catalog
```sql
-- Hierarchical product catalog
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    parent_category_id INTEGER REFERENCES categories(category_id),
    -- ... category metadata
);

-- Comprehensive product model
CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    brand_id INTEGER REFERENCES brands(brand_id),
    category_id INTEGER REFERENCES categories(category_id),

    -- Pricing with sale support
    base_price DECIMAL(10,2) NOT NULL,
    sale_price DECIMAL(10,2),

    -- Inventory tracking
    stock_quantity INTEGER DEFAULT 0,
    stock_status VARCHAR(20), -- 'in_stock', 'out_of_stock'

    -- Media and content
    main_image_url VARCHAR(500),
    gallery_images JSONB DEFAULT '[]',

    -- Seller information (marketplace)
    seller_id UUID REFERENCES users(user_id),

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (...),
);
```

#### Product Variations & Attributes
```sql
-- Product variations (size, color, etc.)
CREATE TABLE product_variations (
    variation_id UUID PRIMARY KEY,
    product_id UUID REFERENCES products(product_id),
    variation_name VARCHAR(255), -- "Color: Red, Size: Large"
    attributes JSONB NOT NULL, -- {"color": "red", "size": "large"}
    price_modifier DECIMAL(8,2) DEFAULT 0.00,
    stock_quantity INTEGER,
);

-- Flexible product attributes
CREATE TABLE product_attributes (
    attribute_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20), -- 'text', 'number', 'boolean', 'color'
    is_filterable BOOLEAN DEFAULT TRUE,
);

-- Attribute values for filtering
CREATE TABLE product_attribute_values (
    product_id UUID REFERENCES products(product_id),
    attribute_id INTEGER REFERENCES product_attributes(attribute_id),
    value_text TEXT,
    -- ... typed value fields
);
```

### Shopping Cart & Orders

#### Cart Management
```sql
-- Shopping carts with session support
CREATE TABLE carts (
    cart_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    session_id VARCHAR(255), -- Anonymous users
    -- ... cart metadata
);

-- Cart items with customizations
CREATE TABLE cart_items (
    cart_item_id UUID PRIMARY KEY,
    cart_id UUID REFERENCES carts(cart_id),
    product_id UUID REFERENCES products(product_id),
    variation_id UUID REFERENCES product_variations(variation_id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2),
    customizations JSONB DEFAULT '{}', -- Gift wrapping, engraving
);
```

#### Order Processing
```sql
-- Complete order lifecycle
CREATE TABLE orders (
    order_id UUID PRIMARY KEY,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    user_id UUID REFERENCES users(user_id),

    -- Status tracking
    status VARCHAR(30), -- 'pending', 'confirmed', 'shipped', 'delivered'
    payment_status VARCHAR(20),
    fulfillment_status VARCHAR(20),

    -- Financial breakdown
    subtotal DECIMAL(12,2),
    tax_amount DECIMAL(10,2),
    shipping_amount DECIMAL(10,2),
    discount_amount DECIMAL(10,2),
    total_amount DECIMAL(12,2),

    -- Addresses
    billing_address_id UUID REFERENCES addresses(address_id),
    shipping_address_id UUID REFERENCES addresses(address_id),

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (...),
);

-- Order items with fulfillment tracking
CREATE TABLE order_items (
    order_item_id UUID PRIMARY KEY,
    order_id UUID REFERENCES orders(order_id),
    product_id UUID REFERENCES products(product_id),
    fulfilled_quantity INTEGER DEFAULT 0,
    fulfillment_status VARCHAR(20),
    -- ... item details
);
```

### Payments & Financial

#### Payment Methods
```sql
-- Multiple payment methods per user
CREATE TABLE payment_methods (
    payment_method_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    type VARCHAR(20), -- 'credit_card', 'paypal', 'apple_pay'
    provider VARCHAR(50), -- 'stripe', 'paypal', 'braintree'

    -- Tokenized for PCI compliance
    provider_token VARCHAR(255),
    last_four VARCHAR(4), -- Last 4 digits
    -- ... payment details
);

-- Payment transactions
CREATE TABLE payments (
    payment_id UUID PRIMARY KEY,
    order_id UUID REFERENCES orders(order_id),
    amount DECIMAL(12,2),
    provider VARCHAR(50),
    provider_payment_id VARCHAR(255) UNIQUE,
    status VARCHAR(20), -- 'pending', 'succeeded', 'failed'
    -- ... payment metadata
);
```

#### Refunds & Financial Tracking
```sql
-- Refund management
CREATE TABLE refunds (
    refund_id UUID PRIMARY KEY,
    payment_id UUID REFERENCES payments(payment_id),
    amount DECIMAL(12,2),
    reason VARCHAR(100), -- 'customer_request', 'defective_product'
    status VARCHAR(20),
    -- ... refund details
);
```

### Inventory & Warehousing

#### Multi-Warehouse Support
```sql
-- Warehouse management
CREATE TABLE warehouses (
    warehouse_id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    address JSONB,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326), -- PostGIS
    -- ... warehouse details
);

-- Detailed inventory tracking
CREATE TABLE product_inventory (
    inventory_id UUID PRIMARY KEY,
    product_id UUID REFERENCES products(product_id),
    variation_id UUID REFERENCES product_variations(variation_id),
    warehouse_id INTEGER REFERENCES warehouses(warehouse_id),

    quantity_available INTEGER DEFAULT 0,
    quantity_reserved INTEGER DEFAULT 0,
    quantity_on_order INTEGER DEFAULT 0,

    -- Warehouse location
    aisle VARCHAR(20),
    shelf VARCHAR(20),
    bin VARCHAR(20),

    UNIQUE (product_id, variation_id, warehouse_id)
);
```

#### Inventory Transactions
```sql
-- Complete audit trail
CREATE TABLE inventory_transactions (
    transaction_id UUID PRIMARY KEY,
    inventory_id UUID REFERENCES product_inventory(inventory_id),
    transaction_type VARCHAR(20), -- 'stock_in', 'stock_out', 'adjustment'
    quantity_change INTEGER,
    previous_quantity INTEGER,
    new_quantity INTEGER,
    performed_by UUID REFERENCES users(user_id),
    -- ... transaction details
);
```

### Shipping & Fulfillment

#### Shipping Methods
```sql
-- Flexible shipping configuration
CREATE TABLE shipping_methods (
    shipping_method_id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    provider VARCHAR(50), -- 'fedex', 'ups', 'usps'
    base_cost DECIMAL(8,2),
    cost_per_weight DECIMAL(8,2),
    min_delivery_days INTEGER,
    max_delivery_days INTEGER,
    -- ... shipping constraints
);

-- Shipment tracking
CREATE TABLE shipments (
    shipment_id UUID PRIMARY KEY,
    order_id UUID REFERENCES orders(order_id),
    shipping_method_id INTEGER REFERENCES shipping_methods(shipping_method_id),
    tracking_number VARCHAR(100) UNIQUE,
    carrier VARCHAR(50),

    -- Status with history
    status VARCHAR(30), -- 'pending', 'shipped', 'delivered'
    status_history JSONB DEFAULT '[]',

    shipped_at TIMESTAMP WITH TIME ZONE,
    estimated_delivery_date DATE,
    actual_delivery_date DATE,
);
```

### Reviews & Ratings

#### Product Reviews
```sql
-- Comprehensive review system
CREATE TABLE product_reviews (
    review_id UUID PRIMARY KEY,
    product_id UUID REFERENCES products(product_id),
    user_id UUID REFERENCES users(user_id),
    order_id UUID REFERENCES orders(order_id), -- Verified purchase

    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    title VARCHAR(200),
    review_text TEXT,
    pros TEXT,
    cons TEXT,

    -- Media attachments
    images JSONB DEFAULT '[]',
    videos JSONB DEFAULT '[]',

    -- Moderation
    status VARCHAR(20), -- 'pending', 'approved', 'rejected'
    is_verified_purchase BOOLEAN DEFAULT FALSE,

    -- Voting system
    helpful_votes INTEGER DEFAULT 0,
    total_votes INTEGER DEFAULT 0,
);

-- Review voting
CREATE TABLE review_votes (
    review_vote_id UUID PRIMARY KEY,
    review_id UUID REFERENCES product_reviews(review_id),
    user_id UUID REFERENCES users(user_id),
    vote_type VARCHAR(10), -- 'helpful', 'unhelpful'
    UNIQUE (review_id, user_id)
);
```

#### Q&A System
```sql
-- Product questions and answers
CREATE TABLE product_questions (
    question_id UUID PRIMARY KEY,
    product_id UUID REFERENCES products(product_id),
    user_id UUID REFERENCES users(user_id),
    question_text TEXT,
    status VARCHAR(20), -- 'pending', 'answered'
);

CREATE TABLE product_answers (
    answer_id UUID PRIMARY KEY,
    question_id UUID REFERENCES product_questions(question_id),
    user_id UUID REFERENCES users(user_id),
    answer_text TEXT,
    is_official_answer BOOLEAN DEFAULT FALSE,
);
```

### Promotions & Discounts

#### Coupon System
```sql
-- Flexible coupon management
CREATE TABLE coupons (
    coupon_id UUID PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    discount_type VARCHAR(20), -- 'percentage', 'fixed_amount', 'free_shipping'
    discount_value DECIMAL(8,2),

    -- Usage controls
    usage_limit INTEGER,
    per_user_limit INTEGER DEFAULT 1,

    -- Eligibility rules
    minimum_order_amount DECIMAL(8,2),
    applicable_categories INTEGER[],
    applicable_products UUID[],

    -- Validity period
    starts_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
);

-- Applied coupons audit
CREATE TABLE applied_coupons (
    applied_coupon_id UUID PRIMARY KEY,
    coupon_id UUID REFERENCES coupons(coupon_id),
    order_id UUID REFERENCES orders(order_id),
    discount_amount DECIMAL(8,2),
);
```

## Advanced Features

### Full-Text Search

```sql
-- Product search with ranking
ALTER TABLE products
ADD COLUMN search_vector TSVECTOR
GENERATED ALWAYS AS (
    to_tsvector('english',
        name || ' ' || description || ' ' || short_description || ' ' ||
        array_to_string(search_keywords, ' ') || ' ' || sku
    )
) STORED;

CREATE INDEX idx_products_search ON products USING GIN (search_vector);

-- Advanced search query
SELECT
    product_id,
    name,
    ts_rank(search_vector, query) AS relevance,
    base_price,
    average_rating
FROM products, to_tsquery('english', 'wireless bluetooth headphones') query
WHERE search_vector @@ query
ORDER BY relevance DESC, average_rating DESC
LIMIT 20;
```

### Analytics & Reporting

```sql
-- Daily product analytics
CREATE TABLE product_analytics (
    analytics_id UUID PRIMARY KEY,
    product_id UUID REFERENCES products(product_id),
    date DATE NOT NULL,

    page_views INTEGER DEFAULT 0,
    unique_visitors INTEGER DEFAULT 0,
    add_to_cart_count INTEGER DEFAULT 0,
    purchase_count INTEGER DEFAULT 0,
    revenue DECIMAL(12,2) DEFAULT 0.00,

    UNIQUE (product_id, date)
) PARTITION BY RANGE (date);

-- Customer behavior analytics
CREATE TABLE customer_analytics (
    analytics_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    date DATE NOT NULL,

    session_count INTEGER DEFAULT 0,
    orders_placed INTEGER DEFAULT 0,
    total_spent DECIMAL(10,2) DEFAULT 0.00,
    products_viewed INTEGER DEFAULT 0,

    UNIQUE (user_id, date)
) PARTITION BY RANGE (date);
```

## Usage Examples

### Product Search & Discovery

```sql
-- Advanced product search with filters
SELECT
    p.product_id,
    p.name,
    p.base_price,
    p.average_rating,
    b.name AS brand_name,
    c.name AS category_name,
    ts_rank(p.search_vector, query) AS relevance
FROM products p
JOIN brands b ON p.brand_id = b.brand_id
JOIN categories c ON p.category_id = c.category_id
CROSS JOIN to_tsquery('english', 'wireless headphones') AS query
WHERE p.search_vector @@ query
  AND p.status = 'active'
  AND p.base_price BETWEEN 50 AND 300
  AND c.category_id IN (SELECT category_id FROM categories WHERE name ILIKE '%audio%')
ORDER BY relevance DESC, p.average_rating DESC
LIMIT 50;
```

### Order Processing Flow

```sql
-- Complete order creation process
BEGIN;

-- 1. Create order from cart
INSERT INTO orders (
    order_number, user_id, subtotal, tax_amount,
    shipping_amount, total_amount, shipping_address_id
)
SELECT
    'ORD-' || UPPER(SUBSTRING(MD5(random()::text) FROM 1 FOR 8)),
    c.user_id,
    SUM(ci.quantity * ci.unit_price),
    SUM(ci.quantity * ci.unit_price) * 0.08, -- 8% tax
    9.99, -- Flat shipping
    SUM(ci.quantity * ci.unit_price) * 1.08 + 9.99,
    (SELECT address_id FROM addresses WHERE user_id = c.user_id AND is_default = TRUE LIMIT 1)
FROM carts c
JOIN cart_items ci ON c.cart_id = ci.cart_id
WHERE c.cart_id = 'cart-uuid'
GROUP BY c.user_id;

-- 2. Create order items
INSERT INTO order_items (
    order_id, product_id, variation_id, product_name,
    quantity, unit_price, total_price
)
SELECT
    (SELECT order_id FROM orders WHERE order_number = 'generated-number'),
    ci.product_id,
    ci.variation_id,
    p.name,
    ci.quantity,
    ci.unit_price,
    ci.quantity * ci.unit_price
FROM cart_items ci
JOIN products p ON ci.product_id = p.product_id
WHERE ci.cart_id = 'cart-uuid';

-- 3. Reserve inventory
SELECT reserve_inventory(product_id, variation_id, quantity)
FROM cart_items WHERE cart_id = 'cart-uuid';

-- 4. Clear cart
DELETE FROM cart_items WHERE cart_id = 'cart-uuid';

COMMIT;
```

### Inventory Management

```sql
-- Check product availability across warehouses
SELECT
    p.name AS product_name,
    w.name AS warehouse_name,
    pi.quantity_available,
    pi.quantity_reserved,
    pi.quantity_available - pi.quantity_reserved AS available_to_sell,
    w.latitude,
    w.longitude
FROM products p
CROSS JOIN warehouses w
LEFT JOIN product_inventory pi ON p.product_id = pi.product_id
    AND w.warehouse_id = pi.warehouse_id
WHERE p.product_id = 'product-uuid'
  AND pi.quantity_available > pi.quantity_reserved
ORDER BY pi.quantity_available - pi.quantity_reserved DESC;
```

### Customer Analytics

```sql
-- Customer lifetime value and segmentation
WITH customer_metrics AS (
    SELECT
        c.customer_id,
        c.first_name || ' ' || c.last_name AS customer_name,
        COUNT(o.order_id) AS total_orders,
        SUM(o.total_amount) AS lifetime_value,
        AVG(o.total_amount) AS avg_order_value,
        MAX(o.created_at) AS last_order_date,
        MIN(o.created_at) AS first_order_date,
        EXTRACT(EPOCH FROM (MAX(o.created_at) - MIN(o.created_at))) / 86400 / COUNT(o.order_id) AS avg_days_between_orders
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status NOT IN ('cancelled')
    GROUP BY c.customer_id, c.first_name, c.last_name
)
SELECT
    *,
    CASE
        WHEN lifetime_value >= 10000 THEN 'VIP'
        WHEN lifetime_value >= 5000 THEN 'High Value'
        WHEN lifetime_value >= 1000 THEN 'Medium Value'
        WHEN total_orders >= 10 THEN 'Loyal'
        WHEN last_order_date >= CURRENT_DATE - INTERVAL '90 days' THEN 'Active'
        ELSE 'At Risk'
    END AS customer_segment
FROM customer_metrics
ORDER BY lifetime_value DESC;
```

## Performance Optimizations

### Key Indexes

```sql
-- Product search and filtering
CREATE INDEX idx_products_category_price ON products (category_id, base_price);
CREATE INDEX idx_products_brand_status ON products (brand_id, status);
CREATE INDEX idx_products_search ON products USING GIN (search_vector);

-- Order processing
CREATE INDEX idx_orders_user_status ON orders (user_id, status);
CREATE INDEX idx_orders_created_at ON orders (created_at DESC);
CREATE INDEX idx_order_items_order_product ON order_items (order_id, product_id);

-- Inventory management
CREATE INDEX idx_product_inventory_product ON product_inventory (product_id, warehouse_id);
CREATE INDEX idx_product_inventory_available ON product_inventory (quantity_available - quantity_reserved);

-- Analytics
CREATE INDEX idx_product_analytics_product_date ON product_analytics (product_id, date DESC);
CREATE INDEX idx_customer_analytics_user_date ON customer_analytics (user_id, date DESC);
```

### Partitioning Strategy

```sql
-- Partition orders by month for performance
CREATE TABLE orders PARTITION BY RANGE (created_at);

CREATE TABLE orders_2024_01 PARTITION OF orders FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE orders_2024_02 PARTITION OF orders FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- Partition analytics by date
CREATE TABLE product_analytics PARTITION BY RANGE (date);
CREATE TABLE customer_analytics PARTITION BY RANGE (date);
```

## Security Considerations

### Row-Level Security

```sql
-- Enable RLS for multi-tenant marketplace
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Sellers can only see their own products
CREATE POLICY seller_products_policy ON products
    FOR ALL USING (seller_id = current_user_id() OR seller_id IS NULL);

-- Customers can view active products
CREATE POLICY customer_products_policy ON products
    FOR SELECT USING (status = 'active');
```

### Data Encryption

```sql
-- Encrypt sensitive payment data
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypted payment method storage
CREATE TABLE payment_methods (
    payment_method_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    encrypted_card_data BYTEA, -- Encrypted with pgcrypto
    encryption_key_hash VARCHAR(128),
    -- ... other fields
);
```

## Monitoring & Analytics

### Key Business Metrics

- **Conversion Rate**: Carts created vs orders completed
- **Average Order Value**: Revenue per order
- **Customer Lifetime Value**: Total revenue per customer
- **Inventory Turnover**: Sales velocity
- **Return Rate**: Percentage of returned orders
- **Customer Satisfaction**: Review ratings and feedback

### Real-time Dashboards

```sql
-- Real-time sales dashboard
CREATE VIEW sales_dashboard AS
SELECT
    (SELECT COUNT(*) FROM orders WHERE DATE(created_at) = CURRENT_DATE) AS todays_orders,
    (SELECT SUM(total_amount) FROM orders WHERE DATE(created_at) = CURRENT_DATE) AS todays_revenue,
    (SELECT COUNT(*) FROM users WHERE DATE(created_at) = CURRENT_DATE) AS new_customers_today,
    (SELECT AVG(total_amount) FROM orders WHERE created_at >= CURRENT_DATE - INTERVAL '30 days') AS avg_order_value_30d,
    (SELECT COUNT(*) FROM products WHERE stock_quantity = 0) AS out_of_stock_products,
    (SELECT AVG(rating) FROM product_reviews WHERE created_at >= CURRENT_DATE - INTERVAL '30 days') AS avg_rating_30d
;
```

## Integration Points

### External Systems
- **Payment processors** (Stripe, PayPal, Adyen) for secure transaction processing
- **Shipping carriers** (FedEx, UPS, DHL) for real-time shipping rates and tracking
- **Inventory management systems** (SAP, Oracle) for warehouse synchronization
- **Tax calculation services** (Avalara, TaxJar) for sales tax compliance
- **Fraud detection services** (Sift, Riskified) for transaction security
- **Email marketing platforms** (Mailchimp, Klaviyo) for customer communication
- **Product catalog systems** for PIM (Product Information Management)

### API Endpoints
- **Order management APIs** for order processing, fulfillment, and tracking
- **Product catalog APIs** for inventory management and product information
- **Customer service APIs** for returns, exchanges, and support tickets
- **Analytics APIs** for sales reporting and business intelligence
- **Marketplace APIs** for vendor management and commission processing
- **Integration APIs** for third-party system connectivity and webhooks

This e-commerce schema provides a solid foundation for building scalable online retail platforms with marketplace capabilities, supporting millions of products, orders, and users while maintaining performance and data integrity.
