# Retail & Point of Sale Database Design

## Overview

This comprehensive database schema supports retail operations including point-of-sale (POS) systems, inventory management, customer relationship management, loyalty programs, and retail analytics. The design handles multi-store operations, omnichannel retailing, and complex pricing/promotion systems.

## Key Features

### 🏪 Store & Location Management
- **Multi-store operations** with hierarchical organization (regions, districts, stores)
- **Store profiling** with operating hours, layout zones, and performance metrics
- **Geographic store clustering** for regional analytics and supply chain optimization
- **Store-specific configurations** for pricing, promotions, and operations

### 📦 Product Catalog & Inventory
- **Hierarchical product categorization** with flexible classification
- **Product variants and attributes** (size, color, style, materials)
- **Multi-location inventory tracking** with real-time availability
- **Automated reorder point management** and safety stock calculations

### 💰 Point of Sale & Transactions
- **Real-time transaction processing** with multiple payment methods
- **Transaction-level item tracking** with serial numbers and lot tracking
- **Integrated promotion application** with coupon and loyalty integration
- **Return and exchange processing** with audit trails

### 👥 Customer Relationship Management
- **Unified customer profiles** across online and in-store channels
- **Customer segmentation** based on purchase behavior and demographics
- **Multi-tier loyalty programs** with points, rewards, and personalization
- **Customer lifetime value analysis** and retention strategies

### 📊 Analytics & Business Intelligence
- **Real-time sales analytics** by store, product, and time period
- **Customer behavior analysis** with purchase patterns and preferences
- **Inventory optimization** with turnover analysis and stock recommendations
- **Performance dashboards** for operational and strategic decision-making

## Database Schema Highlights

### Core Tables

#### Store Operations
- **`stores`** - Store master data with location, hierarchy, and operational details
- **`store_zones`** - Physical store layout and zone-based analytics
- **`pos_terminals`** - POS terminal management and transaction routing

#### Product Management
- **`product_categories`** - Hierarchical product classification system
- **`products`** - Complete product catalog with variants and pricing
- **`product_variants`** - Size, color, and style variations

#### Transaction Processing
- **`sales_transactions`** - Transaction headers with customer and payment details
- **`transaction_items`** - Line-item details with pricing and inventory tracking

#### Customer Management
- **`customers`** - Unified customer profiles across channels
- **`loyalty_programs`** - Flexible loyalty program configurations
- **`loyalty_accounts`** - Customer enrollment and points tracking

#### Inventory Management
- **`inventory_locations`** - Multi-level warehouse and store location tracking
- **`inventory_items`** - Detailed inventory with cost, quality, and tracking
- **`inventory_transactions`** - Complete inventory movement audit trail

#### Purchasing & Supply Chain
- **`suppliers`** - Supplier management with performance tracking
- **`purchase_orders`** - Purchase order processing and receiving
- **`purchase_order_items`** - Detailed line-item tracking

#### Promotions & Pricing
- **`promotions`** - Complex promotion rules and eligibility criteria
- **`promotion_usage`** - Promotion application tracking and analytics

## Key Design Patterns

### 1. Dynamic Product Pricing with Promotions
```sql
-- Calculate final product price with all applicable promotions
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
    current_price DECIMAL;
    total_discount DECIMAL := 0;
    applied_promos JSONB := '[]';
BEGIN
    -- Get base product pricing
    SELECT * INTO product_record FROM products WHERE product_id = product_uuid;
    current_price := product_record.base_price;

    -- Apply sale pricing if active
    IF product_record.is_on_sale AND CURRENT_DATE BETWEEN
       COALESCE(product_record.sale_start_date, CURRENT_DATE) AND
       COALESCE(product_record.sale_end_date, CURRENT_DATE) THEN
        current_price := product_record.sale_price;
        applied_promos := applied_promos || jsonb_build_object('type', 'sale_pricing');
    END IF;

    -- Apply eligible promotions
    FOR promotion_record IN
        SELECT * FROM promotions
        WHERE is_active = TRUE
          AND (product_uuid = ANY(applicable_products) OR array_length(applicable_products, 1) IS NULL)
          AND (customer_uuid IS NULL OR customer_uuid IN (
              SELECT customer_id FROM customers
              WHERE customer_type = ANY(applicable_customer_types)
          ))
    LOOP
        -- Calculate promotion discount
        CASE promotion_record.promotion_type
            WHEN 'percentage_discount' THEN
                total_discount := total_discount + (current_price * promotion_record.discount_percentage / 100);
            WHEN 'fixed_amount_discount' THEN
                total_discount := total_discount + promotion_record.discount_amount;
        END CASE;

        applied_promos := applied_promos || jsonb_build_object(
            'promotion_id', promotion_record.promotion_id,
            'discount_type', promotion_record.promotion_type,
            'discount_amount', total_discount
        );
    END LOOP;

    RETURN QUERY SELECT
        product_record.base_price,
        total_discount,
        GREATEST(current_price - total_discount, 0),
        applied_promos;
END;
$$ LANGUAGE plpgsql;
```

### 2. Real-Time Inventory Management
```sql
-- Update inventory with automatic reorder alerts
CREATE OR REPLACE FUNCTION update_inventory_quantity(
    product_uuid UUID,
    location_uuid UUID,
    quantity_change INTEGER,
    transaction_type VARCHAR DEFAULT 'adjustment'
)
RETURNS TABLE (
    previous_quantity INTEGER,
    new_quantity INTEGER,
    reorder_alert BOOLEAN,
    stock_status VARCHAR
) AS $$
DECLARE
    inventory_record inventory_items%ROWTYPE;
    new_qty INTEGER;
    reorder_triggered BOOLEAN := FALSE;
BEGIN
    -- Get current inventory
    SELECT * INTO inventory_record
    FROM inventory_items
    WHERE product_id = product_uuid AND location_id = location_uuid;

    IF NOT FOUND THEN
        -- Create new inventory record
        INSERT INTO inventory_items (product_id, location_id, quantity_on_hand)
        VALUES (product_uuid, location_uuid, GREATEST(quantity_change, 0))
        RETURNING quantity_on_hand INTO new_qty;
    ELSE
        -- Update existing inventory
        new_qty := inventory_record.quantity_on_hand + quantity_change;
        UPDATE inventory_items
        SET quantity_on_hand = new_qty,
            last_movement_date = CURRENT_DATE
        WHERE inventory_item_id = inventory_record.inventory_item_id;
    END IF;

    -- Log inventory transaction
    INSERT INTO inventory_transactions (
        transaction_type, product_id, quantity,
        from_location_id, to_location_id, transaction_date
    ) VALUES (
        transaction_type, product_uuid, quantity_change,
        CASE WHEN quantity_change < 0 THEN location_uuid ELSE NULL END,
        CASE WHEN quantity_change > 0 THEN location_uuid ELSE NULL END,
        CURRENT_DATE
    );

    -- Check for reorder alerts
    IF new_qty <= inventory_record.reorder_point AND NOT reorder_triggered THEN
        reorder_triggered := TRUE;
        -- Trigger reorder process (could send notification, create PO, etc.)
        PERFORM create_reorder_alert(product_uuid, location_uuid, new_qty);
    END IF;

    -- Determine stock status
    stock_status := CASE
        WHEN new_qty <= 0 THEN 'out_of_stock'
        WHEN new_qty <= inventory_record.safety_stock THEN 'critical'
        WHEN new_qty <= inventory_record.reorder_point THEN 'low_stock'
        ELSE 'in_stock'
    END CASE;

    RETURN QUERY SELECT
        inventory_record.quantity_on_hand,
        new_qty,
        reorder_triggered,
        stock_status;
END;
$$ LANGUAGE plpgsql;
```

### 3. Customer Segmentation and Personalization
```sql
-- Analyze customer behavior for segmentation
CREATE OR REPLACE FUNCTION analyze_customer_segment(customer_uuid UUID)
RETURNS TABLE (
    customer_segment VARCHAR,
    lifetime_value DECIMAL,
    purchase_frequency DECIMAL,
    average_order_value DECIMAL,
    preferred_categories TEXT[],
    loyalty_tier VARCHAR,
    churn_risk VARCHAR
) AS $$
DECLARE
    customer_metrics RECORD;
    segment VARCHAR;
    churn_risk VARCHAR;
BEGIN
    -- Calculate customer metrics
    SELECT
        COUNT(st.transaction_id) as total_orders,
        SUM(st.total_amount) as total_spent,
        AVG(st.total_amount) as avg_order_value,
        MAX(st.transaction_date) as last_purchase_date,
        EXTRACT(EPOCH FROM (CURRENT_DATE - MAX(st.transaction_date))) / 30 as months_since_last_purchase,
        array_agg(DISTINCT pc.category_name) as categories
    INTO customer_metrics
    FROM sales_transactions st
    JOIN transaction_items ti ON st.transaction_id = ti.transaction_id
    JOIN products p ON ti.product_id = p.product_id
    JOIN product_categories pc ON p.category_id = pc.category_id
    WHERE st.customer_id = customer_uuid AND st.transaction_status = 'completed';

    -- Determine customer segment
    segment := CASE
        WHEN customer_metrics.total_spent >= 10000 AND customer_metrics.total_orders >= 50 THEN 'vip'
        WHEN customer_metrics.total_spent >= 1000 AND customer_metrics.total_orders >= 10 THEN 'loyal'
        WHEN customer_metrics.total_spent >= 100 THEN 'regular'
        WHEN customer_metrics.total_spent > 0 THEN 'occasional'
        ELSE 'prospect'
    END CASE;

    -- Calculate churn risk
    churn_risk := CASE
        WHEN customer_metrics.months_since_last_purchase >= 12 THEN 'high'
        WHEN customer_metrics.months_since_last_purchase >= 6 THEN 'medium'
        WHEN customer_metrics.months_since_last_purchase >= 3 THEN 'low'
        ELSE 'active'
    END CASE;

    RETURN QUERY SELECT
        segment,
        customer_metrics.total_spent,
        customer_metrics.total_orders::DECIMAL / GREATEST(EXTRACT(EPOCH FROM (CURRENT_DATE - (SELECT registration_date FROM customers WHERE customer_id = customer_uuid))) / 30, 1),
        customer_metrics.avg_order_value,
        customer_metrics.categories,
        COALESCE((SELECT current_tier FROM loyalty_accounts WHERE customer_id = customer_uuid), 'none'),
        churn_risk;
END;
$$ LANGUAGE plpgsql;
```

### 4. Promotion Engine with Complex Rules
```sql
-- Evaluate promotion eligibility with complex rules
CREATE OR REPLACE FUNCTION evaluate_promotion_eligibility(
    promotion_uuid UUID,
    customer_uuid UUID DEFAULT NULL,
    products UUID[] DEFAULT ARRAY[]::UUID[],
    purchase_amount DECIMAL DEFAULT 0
)
RETURNS TABLE (
    is_eligible BOOLEAN,
    disqualifying_reasons TEXT[],
    discount_amount DECIMAL,
    promotion_details JSONB
) AS $$
DECLARE
    promotion_record promotions%ROWTYPE;
    customer_record customers%ROWTYPE;
    reasons TEXT[] := ARRAY[]::TEXT[];
    eligible BOOLEAN := TRUE;
    discount DECIMAL := 0;
BEGIN
    -- Get promotion details
    SELECT * INTO promotion_record FROM promotions WHERE promotion_id = promotion_uuid;

    -- Check if promotion is active
    IF NOT promotion_record.is_active THEN
        reasons := reasons || 'Promotion not currently active';
        eligible := FALSE;
    END IF;

    -- Check usage limits
    IF promotion_record.usage_limit IS NOT NULL AND
       (SELECT COUNT(*) FROM promotion_usage WHERE promotion_id = promotion_uuid) >= promotion_record.usage_limit THEN
        reasons := reasons || 'Promotion usage limit exceeded';
        eligible := FALSE;
    END IF;

    -- Check customer eligibility
    IF customer_uuid IS NOT NULL THEN
        SELECT * INTO customer_record FROM customers WHERE customer_id = customer_uuid;

        IF promotion_record.usage_limit_per_customer IS NOT NULL AND
           (SELECT COUNT(*) FROM promotion_usage WHERE promotion_id = promotion_uuid AND customer_id = customer_uuid) >= promotion_record.usage_limit_per_customer THEN
            reasons := reasons || 'Customer usage limit exceeded for this promotion';
            eligible := FALSE;
        END IF;

        IF array_length(promotion_record.applicable_customer_types, 1) > 0 AND
           customer_record.customer_type != ALL(promotion_record.applicable_customer_types) THEN
            reasons := reasons || 'Customer type not eligible for this promotion';
            eligible := FALSE;
        END IF;
    END IF;

    -- Check product eligibility
    IF array_length(products, 1) > 0 THEN
        IF NOT (products <@ promotion_record.applicable_products OR
                array_length(promotion_record.applicable_products, 1) IS NULL) THEN
            reasons := reasons || 'Products not eligible for this promotion';
            eligible := FALSE;
        END IF;

        IF products && promotion_record.excluded_products THEN
            reasons := reasons || 'Some products are excluded from this promotion';
            eligible := FALSE;
        END IF;
    END IF;

    -- Check minimum purchase requirement
    IF promotion_record.minimum_purchase IS NOT NULL AND purchase_amount < promotion_record.minimum_purchase THEN
        reasons := reasons || 'Purchase amount below minimum requirement';
        eligible := FALSE;
    END IF;

    -- Calculate discount if eligible
    IF eligible THEN
        CASE promotion_record.promotion_type
            WHEN 'percentage_discount' THEN
                discount := purchase_amount * promotion_record.discount_percentage / 100;
            WHEN 'fixed_amount_discount' THEN
                discount := promotion_record.discount_amount;
        END CASE;
    END IF;

    RETURN QUERY SELECT
        eligible,
        reasons,
        discount,
        jsonb_build_object(
            'promotion_id', promotion_record.promotion_id,
            'promotion_type', promotion_record.promotion_type,
            'description', promotion_record.description,
            'discount_percentage', promotion_record.discount_percentage,
            'discount_amount', promotion_record.discount_amount
        );
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition sales transactions by month for performance
CREATE TABLE sales_transactions PARTITION BY RANGE (transaction_date);

CREATE TABLE sales_transactions_2024_01 PARTITION OF sales_transactions
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition inventory transactions by quarter
CREATE TABLE inventory_transactions PARTITION BY RANGE (transaction_date);

CREATE TABLE inventory_transactions_q1_2024 PARTITION OF inventory_transactions
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

-- Partition analytics data by month
CREATE TABLE sales_analytics PARTITION BY RANGE (report_date);

CREATE TABLE sales_analytics_2024 PARTITION OF sales_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### Advanced Indexing
```sql
-- Composite indexes for transaction queries
CREATE INDEX idx_sales_transactions_store_customer_date ON sales_transactions
    (store_id, customer_id, transaction_date DESC);

CREATE INDEX idx_transaction_items_product_transaction ON transaction_items
    (product_id, transaction_id);

-- Partial indexes for active records
CREATE INDEX idx_active_products ON products (product_id) WHERE product_status = 'active';
CREATE INDEX idx_active_promotions ON promotions (promotion_id) WHERE is_active = TRUE;

-- GIN indexes for array and JSON operations
CREATE INDEX idx_promotions_applicable_products ON promotions USING gin (applicable_products);
CREATE INDEX idx_promotions_customer_types ON promotions USING gin (applicable_customer_types);
CREATE INDEX idx_products_additional_images ON products USING gin (additional_images);

-- Functional indexes for computed values
CREATE INDEX idx_products_sale_active ON products (product_id)
    WHERE is_on_sale = TRUE
      AND CURRENT_DATE BETWEEN COALESCE(sale_start_date, CURRENT_DATE)
                           AND COALESCE(sale_end_date, CURRENT_DATE);
```

### Materialized Views for Analytics
```sql
-- Daily sales summary for fast reporting
CREATE MATERIALIZED VIEW daily_sales_summary AS
SELECT
    st.store_id,
    sa.report_date,
    SUM(sa.total_sales) as total_sales,
    SUM(sa.transaction_count) as transaction_count,
    AVG(sa.average_transaction_value) as avg_transaction_value,
    COUNT(DISTINCT sa.report_hour) as operating_hours,

    -- Customer metrics
    SUM(sa.unique_customers) as unique_customers,
    SUM(sa.new_customers) as new_customers,
    SUM(sa.returning_customers) as returning_customers,

    -- Product metrics
    SUM(pa.units_sold) as total_units_sold,
    COUNT(DISTINCT pa.product_id) as products_sold,

    -- Performance indicators
    CASE WHEN SUM(sa.total_sales) > (SELECT monthly_sales_target FROM stores WHERE store_id = st.store_id) / 30
         THEN 'above_target' ELSE 'below_target' END as daily_performance

FROM sales_analytics sa
JOIN stores st ON sa.store_id = st.store_id
LEFT JOIN product_analytics pa ON sa.store_id = pa.store_id AND sa.report_date = pa.report_date
WHERE sa.report_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY st.store_id, sa.report_date;

-- Refresh hourly for real-time analytics
CREATE UNIQUE INDEX idx_daily_sales_summary_store_date ON daily_sales_summary (store_id, report_date);
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_sales_summary;
```

## Security Considerations

### Data Encryption
```sql
-- Encrypt sensitive customer and payment data
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypt payment information
CREATE OR REPLACE FUNCTION encrypt_payment_data(card_number TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(card_number, current_setting('retail.payment_key'));
END;
$$ LANGUAGE plpgsql;

-- Mask sensitive data in queries
CREATE OR REPLACE FUNCTION mask_credit_card(card_number TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN '****-****-****-' || RIGHT(card_number, 4);
END;
$$ LANGUAGE plpgsql;
```

### Access Control
```sql
-- Role-based security for retail operations
ALTER TABLE sales_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY store_staff_policy ON sales_transactions
    FOR SELECT USING (
        store_id = current_setting('app.store_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('manager', 'regional_manager', 'admin')
    );

CREATE POLICY customer_privacy_policy ON customers
    FOR SELECT USING (
        customer_id = current_setting('app.customer_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('store_manager', 'admin') OR
        current_setting('app.has_customer_data_access')::BOOLEAN = TRUE
    );
```

### Audit Trail
```sql
-- Comprehensive retail audit logging
CREATE TABLE retail_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    store_id UUID REFERENCES stores(store_id),
    terminal_id UUID REFERENCES pos_terminals(terminal_id),
    session_id TEXT,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Audit trigger for sensitive operations
CREATE OR REPLACE FUNCTION retail_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO retail_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, store_id, terminal_id, session_id
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        current_setting('app.store_id', TRUE)::UUID,
        current_setting('app.terminal_id', TRUE)::UUID,
        current_setting('app.session_id', TRUE)::TEXT
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Payment processors** (Stripe, Square, Authorize.net) for transaction processing
- **Inventory management systems** for automated stock updates
- **Customer relationship platforms** (Salesforce, HubSpot) for unified customer views
- **E-commerce platforms** (Shopify, WooCommerce) for omnichannel operations

### API Endpoints
- **POS APIs** for real-time transaction processing and inventory updates
- **Customer APIs** for loyalty program integration and personalization
- **Inventory APIs** for stock level queries and reorder automation
- **Analytics APIs** for business intelligence and reporting

## Monitoring & Analytics

### Key Performance Indicators
- **Sales per square foot** and conversion rates by store
- **Inventory turnover** and stock-out rates
- **Customer acquisition cost** and lifetime value
- **Employee productivity** and transaction processing times
- **Promotion effectiveness** and ROI analysis

### Real-Time Dashboards
```sql
-- Retail operations dashboard
CREATE VIEW retail_operations_dashboard AS
SELECT
    -- Sales performance (today)
    (SELECT SUM(total_sales) FROM daily_sales_summary WHERE report_date = CURRENT_DATE) as todays_sales,
    (SELECT SUM(transaction_count) FROM daily_sales_summary WHERE report_date = CURRENT_DATE) as todays_transactions,
    (SELECT AVG(avg_transaction_value) FROM daily_sales_summary WHERE report_date = CURRENT_DATE) as avg_transaction_value,

    -- Inventory health
    (SELECT COUNT(*) FROM inventory_items WHERE quantity_available <= reorder_point) as items_needing_reorder,
    (SELECT COUNT(*) FROM inventory_items WHERE quantity_available = 0) as out_of_stock_items,
    (SELECT SUM(total_value) FROM inventory_items) as total_inventory_value,

    -- Customer metrics
    (SELECT COUNT(*) FROM customers WHERE registration_date >= CURRENT_DATE) as new_customers_today,
    (SELECT COUNT(*) FROM sales_transactions WHERE customer_id IS NOT NULL AND transaction_date = CURRENT_DATE) as transactions_with_loyalty,

    -- Operational efficiency
    (SELECT AVG(processing_time_seconds) FROM sales_transactions WHERE transaction_date = CURRENT_DATE) as avg_transaction_time,
    (SELECT COUNT(*) FROM pos_terminals WHERE last_transaction_at < CURRENT_TIMESTAMP - INTERVAL '1 hour') as idle_terminals
;
```

This retail database schema provides enterprise-grade infrastructure for modern retail operations with comprehensive POS capabilities, inventory management, customer analytics, and operational intelligence.
