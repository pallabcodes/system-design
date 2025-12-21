# Food Delivery & Restaurant Management Database Design

## Overview

This comprehensive database schema supports food delivery platforms, restaurant management systems, and order fulfillment operations including real-time order processing, delivery logistics, customer management, and restaurant operations. The design handles complex menu customization, multi-zone delivery, driver assignment, and real-time tracking.

## Key Features

### 🍽️ Restaurant & Menu Management
- **Dynamic menu management** with categories, items, and customizations
- **Real-time inventory tracking** and stock management
- **Flexible pricing** with promotions and discounts
- **Dietary compliance** and allergen management

### 🚚 Delivery & Logistics Management
- **Intelligent driver assignment** based on location and performance
- **Real-time delivery tracking** with GPS coordinates
- **Multi-zone delivery** with dynamic pricing
- **Performance analytics** for drivers and restaurants

### 📱 Order Processing & Fulfillment
- **Complex order customization** with multiple options
- **Real-time order status** updates and notifications
- **Payment processing** with multiple methods
- **Order routing** and kitchen management

### 👥 Customer Experience Management
- **Personalized recommendations** based on order history
- **Loyalty programs** and customer segmentation
- **Review and rating systems** for continuous improvement
- **Saved preferences** and delivery addresses

## Database Schema Highlights

### Core Tables

#### Restaurant Management
- **`restaurants`** - Restaurant profiles with operational details and ratings
- **`menu_categories`** - Menu organization with timing and availability
- **`menu_items`** - Comprehensive item catalog with customizations and inventory
- **`item_customizations`** - Flexible customization options and pricing

#### Order Management
- **`orders`** - Complete order lifecycle with status tracking and delivery
- **`order_items`** - Individual items with customizations and preparation status
- **`delivery_zones`** - Geographic delivery areas with pricing rules

#### Customer Management
- **`customers`** - Customer profiles with preferences and loyalty
- **`customer_addresses`** - Saved delivery addresses with validation

#### Delivery Operations
- **`delivery_drivers`** - Driver profiles with performance metrics and vehicles
- **`driver_shifts`** - Work scheduling and performance tracking
- **`delivery_tracking`** - Real-time GPS tracking and status updates

## Key Design Patterns

### 1. Dynamic Menu Pricing with Customizations
```sql
-- Calculate item price with all customizations and promotions
CREATE OR REPLACE FUNCTION calculate_item_price(
    item_uuid UUID,
    customizations JSONB DEFAULT '[]',
    customer_uuid UUID DEFAULT NULL,
    quantity INTEGER DEFAULT 1
)
RETURNS TABLE (
    base_price DECIMAL,
    customization_price DECIMAL,
    discount_amount DECIMAL,
    final_price DECIMAL,
    applied_promotions JSONB
) AS $$
DECLARE
    item_record menu_items%ROWTYPE;
    customization_record item_customizations%ROWTYPE;
    customization_option JSONB;
    custom_price DECIMAL := 0;
    discount_val DECIMAL := 0;
    applied_promos JSONB := '[]';
BEGIN
    -- Get item details
    SELECT * INTO item_record FROM menu_items WHERE item_id = item_uuid;

    -- Calculate customization pricing
    FOR customization_record IN
        SELECT * FROM item_customizations
        WHERE item_id = item_uuid AND is_active = TRUE
    LOOP
        -- Find selected options for this customization
        FOR customization_option IN SELECT * FROM jsonb_array_elements(customizations)
        LOOP
            IF (customization_option->>'customization_id')::UUID = customization_record.customization_id THEN
                -- Add price modifier for selected option
                custom_price := custom_price + COALESCE(
                    (customization_option->>'price_modifier')::DECIMAL, 0
                );
            END IF;
        END LOOP;
    END LOOP;

    -- Apply item-level promotions
    SELECT discount_amount, applied_promotions INTO discount_val, applied_promos
    FROM calculate_item_promotions(item_uuid, customer_uuid, item_record.base_price + custom_price);

    RETURN QUERY SELECT
        item_record.base_price,
        custom_price,
        discount_val,
        (item_record.base_price + custom_price - discount_val) * quantity,
        applied_promos;
END;
$$ LANGUAGE plpgsql;
```

### 2. Intelligent Driver Assignment Algorithm
```sql
-- Assign optimal driver based on multiple factors
CREATE OR REPLACE FUNCTION find_optimal_driver(
    restaurant_uuid UUID,
    customer_lat DECIMAL,
    customer_lng DECIMAL,
    order_priority VARCHAR DEFAULT 'normal'
)
RETURNS TABLE (
    driver_id UUID,
    driver_name VARCHAR,
    vehicle_type VARCHAR,
    estimated_pickup_time INTERVAL,
    estimated_delivery_time INTERVAL,
    distance_to_restaurant DECIMAL,
    driver_rating DECIMAL,
    assignment_score DECIMAL
) AS $$
DECLARE
    restaurant_location GEOGRAPHY(POINT, 4326);
    customer_location GEOGRAPHY(POINT, 4326);
    priority_multiplier DECIMAL := 1.0;
BEGIN
    -- Set priority multiplier
    CASE order_priority
        WHEN 'high' THEN priority_multiplier := 1.5;
        WHEN 'urgent' THEN priority_multiplier := 2.0;
        ELSE priority_multiplier := 1.0;
    END CASE;

    -- Get locations
    SELECT geolocation INTO restaurant_location FROM restaurants WHERE restaurant_id = restaurant_uuid;
    customer_location := ST_Point(customer_lng, customer_lat)::GEOGRAPHY(POINT, 4326);

    RETURN QUERY
    SELECT
        dd.driver_id,
        dd.first_name || ' ' || dd.last_name,
        dd.vehicle_type,

        -- Estimated times based on distance and speed
        INTERVAL '1 minute' * (ST_Distance(dd.geolocation, restaurant_location) / 1000 / 0.05), -- 50 km/h average
        INTERVAL '1 minute' * (ST_Distance(restaurant_location, customer_location) / 1000 / 0.04), -- 40 km/h in city

        -- Distances
        ST_Distance(dd.geolocation, restaurant_location) / 1000,
        dd.average_rating,

        -- Assignment score calculation
        (
            -- Distance factor (closer is better)
            (1 / (1 + ST_Distance(dd.geolocation, restaurant_location) / 1000)) * 0.3 +

            -- Rating factor (higher rating is better)
            (dd.average_rating / 5.0) * 0.3 +

            -- On-time performance factor
            (dd.on_time_delivery_rate / 100.0) * 0.2 +

            -- Current workload factor (less busy is better)
            CASE WHEN dd.current_order_id IS NULL THEN 1.0 ELSE 0.5 END * 0.1 +

            -- Priority multiplier
            priority_multiplier * 0.1
        ) as assignment_score

    FROM delivery_drivers dd
    WHERE dd.driver_status = 'available'
      AND dd.current_order_id IS NULL
      AND dd.location_updated_at >= CURRENT_TIMESTAMP - INTERVAL '10 minutes' -- Recent location update
    ORDER BY assignment_score DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;
```

### 3. Real-Time Order Status and ETA Calculation
```sql
-- Calculate real-time delivery ETA based on current progress
CREATE OR REPLACE FUNCTION calculate_delivery_eta(order_uuid UUID)
RETURNS TABLE (
    current_status VARCHAR,
    estimated_arrival TIMESTAMP,
    minutes_remaining INTEGER,
    distance_remaining DECIMAL,
    average_speed DECIMAL,
    last_update TIMESTAMP
) AS $$
DECLARE
    order_record orders%ROWTYPE;
    driver_record delivery_drivers%ROWTYPE;
    last_tracking delivery_tracking%ROWTYPE;
    customer_location GEOGRAPHY(POINT, 4326);
    driver_location GEOGRAPHY(POINT, 4326);
    distance_to_customer DECIMAL;
    estimated_speed DECIMAL := 0.04; -- 40 km/h = 0.04 km/minute
BEGIN
    -- Get order and driver details
    SELECT * INTO order_record FROM orders WHERE order_id = order_uuid;
    SELECT * INTO driver_record FROM delivery_drivers WHERE driver_id = order_record.assigned_driver_id;

    -- Get last tracking update
    SELECT * INTO last_tracking FROM delivery_tracking
    WHERE order_id = order_uuid
    ORDER BY tracked_at DESC
    LIMIT 1;

    -- Create locations
    customer_location := ST_Point(order_record.delivery_longitude, order_record.delivery_latitude)::GEOGRAPHY(POINT, 4326);
    driver_location := ST_Point(driver_record.current_longitude, driver_record.current_latitude)::GEOGRAPHY(POINT, 4326);

    -- Calculate distance remaining
    distance_to_customer := ST_Distance(driver_location, customer_location) / 1000;

    -- Adjust speed based on traffic and time of day
    IF EXTRACT(HOUR FROM CURRENT_TIME) BETWEEN 7 AND 9 OR EXTRACT(HOUR FROM CURRENT_TIME) BETWEEN 16 AND 18 THEN
        estimated_speed := estimated_speed * 0.7; -- Rush hour
    END IF;

    -- Estimate arrival time
    RETURN QUERY SELECT
        last_tracking.tracking_status,
        CURRENT_TIMESTAMP + INTERVAL '1 minute' * (distance_to_customer / estimated_speed),
        CEIL(distance_to_customer / estimated_speed),
        ROUND(distance_to_customer, 2),
        ROUND(estimated_speed * 60, 1), -- Convert to km/h
        last_tracking.tracked_at;
END;
$$ LANGUAGE plpgsql;
```

### 4. Customer Order Recommendation Engine
```sql
-- Generate personalized food recommendations based on history and preferences
CREATE OR REPLACE FUNCTION recommend_menu_items(
    customer_uuid UUID,
    restaurant_uuid UUID DEFAULT NULL,
    max_recommendations INTEGER DEFAULT 5
)
RETURNS TABLE (
    item_id UUID,
    item_name VARCHAR,
    restaurant_name VARCHAR,
    predicted_rating DECIMAL,
    recommendation_reason VARCHAR,
    confidence_score DECIMAL
) AS $$
DECLARE
    customer_record customers%ROWTYPE;
    cuisine_preference TEXT;
    dietary_restrictions TEXT[];
    price_preference VARCHAR;
BEGIN
    -- Get customer preferences
    SELECT * INTO customer_record FROM customers WHERE customer_id = customer_uuid;

    -- Analyze order history for preferences
    SELECT
        MODE() WITHIN GROUP (ORDER BY r.cuisine_type) as favorite_cuisine,
        array_agg(DISTINCT mi.allergens) FILTER (WHERE mi.allergens IS NOT NULL) as common_allergens
    INTO cuisine_preference, dietary_restrictions
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN menu_items mi ON oi.item_id = mi.item_id
    JOIN restaurants r ON mi.restaurant_id = r.restaurant_id
    WHERE o.customer_id = customer_uuid
      AND o.order_status = 'delivered'
    GROUP BY o.customer_id;

    RETURN QUERY
    SELECT
        mi.item_id,
        mi.item_name,
        r.restaurant_name,

        -- Simple prediction based on category popularity and ratings
        LEAST(mi.average_rating + 0.5, 5.0) as predicted_rating,

        -- Recommendation reason
        CASE
            WHEN r.cuisine_type = cuisine_preference THEN 'Based on your favorite cuisine'
            WHEN mi.item_name ILIKE ANY(customer_record.favorite_cuisines) THEN 'Similar to your favorites'
            WHEN mi.popularity_score > 8 THEN 'Popular with other customers'
            ELSE 'Highly rated item'
        END as recommendation_reason,

        -- Confidence score
        CASE
            WHEN r.cuisine_type = cuisine_preference THEN 0.9
            WHEN mi.popularity_score > 8 THEN 0.8
            WHEN mi.average_rating >= 4.5 THEN 0.7
            ELSE 0.6
        END as confidence_score

    FROM menu_items mi
    JOIN restaurants r ON mi.restaurant_id = r.restaurant_id
    WHERE mi.item_status = 'active'
      AND mi.is_available = TRUE
      AND (restaurant_uuid IS NULL OR mi.restaurant_id = restaurant_uuid)
      AND (dietary_restrictions IS NULL OR NOT (mi.allergens && dietary_restrictions))
      AND mi.average_rating >= 4.0
    ORDER BY confidence_score DESC, mi.popularity_score DESC
    LIMIT max_recommendations;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition orders by month for performance
CREATE TABLE orders PARTITION BY RANGE (order_date);

CREATE TABLE orders_2024_01 PARTITION OF orders
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition delivery tracking by week
CREATE TABLE delivery_tracking PARTITION BY RANGE (tracked_at);

CREATE TABLE delivery_tracking_2024_01 PARTITION OF delivery_tracking
    FOR VALUES FROM ('2024-01-01') TO ('2024-01-08');

-- Partition order analytics by month
CREATE TABLE order_analytics PARTITION BY RANGE (report_date);

CREATE TABLE order_analytics_2024 PARTITION OF order_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### Advanced Indexing
```sql
-- Spatial indexes for location-based queries
CREATE INDEX idx_restaurants_location ON restaurants USING gist (geolocation);
CREATE INDEX idx_customers_location ON customers USING gist (geolocation);
CREATE INDEX idx_delivery_drivers_location ON delivery_drivers USING gist (geolocation);
CREATE INDEX idx_delivery_zones_boundary ON delivery_zones USING gist (zone_boundary);

-- Composite indexes for order queries
CREATE INDEX idx_orders_customer_status_date ON orders (customer_id, order_status, order_date DESC);
CREATE INDEX idx_orders_restaurant_status ON orders (restaurant_id, order_status, estimated_delivery_time);
CREATE INDEX idx_orders_delivery_time ON orders (estimated_delivery_time) WHERE order_status IN ('out_for_delivery', 'preparing');

-- Full-text search for menu items
CREATE INDEX idx_menu_items_search ON menu_items USING gin (to_tsvector('english', item_name || ' ' || description));
CREATE INDEX idx_restaurants_search ON restaurants USING gin (to_tsvector('english', restaurant_name || ' ' || description));

-- Partial indexes for active records
CREATE INDEX idx_active_menu_items ON menu_items (restaurant_id, category_id) WHERE item_status = 'active' AND is_available = TRUE;
CREATE INDEX idx_available_drivers ON delivery_drivers (driver_id) WHERE driver_status = 'available' AND current_order_id IS NULL;

-- JSONB indexes for flexible queries
CREATE INDEX idx_orders_items ON orders USING gin (items);
CREATE INDEX idx_menu_items_customizations ON menu_items USING gin (customization_options);
```

### Materialized Views for Analytics
```sql
-- Real-time order dashboard
CREATE MATERIALIZED VIEW order_dashboard AS
SELECT
    DATE_TRUNC('hour', o.order_date) as order_hour,

    -- Order volume metrics
    COUNT(o.order_id) as total_orders,
    COUNT(CASE WHEN o.order_type = 'delivery' THEN 1 END) as delivery_orders,
    COUNT(CASE WHEN o.order_type = 'pickup' THEN 1 END) as pickup_orders,
    SUM(o.total_amount) as total_revenue,

    -- Performance metrics
    AVG(EXTRACT(EPOCH FROM (o.actual_delivery_time - o.estimated_delivery_time))/60) as avg_delivery_delay,
    COUNT(CASE WHEN o.actual_delivery_time <= o.estimated_delivery_time THEN 1 END)::DECIMAL /
    NULLIF(COUNT(o.order_id), 0) * 100 as on_time_delivery_rate,

    -- Customer satisfaction
    AVG(o.customer_rating) as avg_customer_rating,
    COUNT(CASE WHEN o.customer_rating >= 4 THEN 1 END) as satisfied_customers,

    -- Restaurant performance
    COUNT(DISTINCT o.restaurant_id) as active_restaurants,
    AVG(o.restaurant_rating) as avg_restaurant_rating

FROM orders o
WHERE o.order_date >= CURRENT_DATE - INTERVAL '7 days'
  AND o.order_status IN ('delivered', 'completed')
GROUP BY DATE_TRUNC('hour', o.order_date)
ORDER BY order_hour DESC;

-- Refresh every 15 minutes
CREATE UNIQUE INDEX idx_order_dashboard_hour ON order_dashboard (order_hour);
REFRESH MATERIALIZED VIEW CONCURRENTLY order_dashboard;
```

## Security Considerations

### Access Control
```sql
-- Role-based security for food delivery operations
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_order_access_policy ON orders
    FOR SELECT USING (
        customer_id = current_setting('app.customer_id')::UUID OR
        restaurant_id IN (
            SELECT restaurant_id FROM restaurant_staff
            WHERE user_id = current_setting('app.user_id')::UUID
        ) OR
        assigned_driver_id = current_setting('app.driver_id')::UUID OR
        current_setting('app.user_role')::TEXT = 'admin'
    );

CREATE POLICY restaurant_menu_access_policy ON menu_items
    FOR ALL USING (
        restaurant_id IN (
            SELECT restaurant_id FROM restaurant_staff
            WHERE user_id = current_setting('app.user_id')::UUID
        ) OR
        current_setting('app.user_role')::TEXT IN ('admin', 'platform_manager')
    );
```

### Data Encryption
```sql
-- Encrypt sensitive customer and payment information
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypt payment card information
CREATE OR REPLACE FUNCTION encrypt_payment_data(card_number TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(card_number, current_setting('food_delivery.payment_key'));
END;
$$ LANGUAGE plpgsql;

-- Encrypt delivery addresses for privacy
CREATE OR REPLACE FUNCTION encrypt_address_data(address_data JSONB)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(address_data::TEXT, current_setting('food_delivery.address_key'));
END;
$$ LANGUAGE plpgsql;
```

### Audit Trail
```sql
-- Comprehensive food delivery audit logging
CREATE TABLE food_delivery_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    customer_id UUID,
    order_id UUID,
    restaurant_id UUID,
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    change_reason TEXT,
    data_sensitivity VARCHAR(20) CHECK (data_sensitivity IN ('low', 'medium', 'high', 'critical')),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Audit trigger for order operations
CREATE OR REPLACE FUNCTION food_delivery_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO food_delivery_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, customer_id, order_id, restaurant_id, session_id,
        ip_address, user_agent, data_sensitivity
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME IN ('orders', 'customers') THEN COALESCE(NEW.customer_id, OLD.customer_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME = 'orders' THEN COALESCE(NEW.order_id, OLD.order_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME LIKE '%restaurant%' THEN COALESCE(NEW.restaurant_id, OLD.restaurant_id) ELSE NULL END,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE
            WHEN TG_TABLE_NAME LIKE '%payment%' THEN 'critical'
            WHEN TG_TABLE_NAME IN ('customers', 'orders') THEN 'high'
            WHEN TG_TABLE_NAME LIKE '%address%' THEN 'medium'
            ELSE 'low'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### Food Safety and Allergen Compliance
```sql
-- Automated allergen checking and food safety compliance
CREATE OR REPLACE FUNCTION check_allergen_compliance(order_uuid UUID)
RETURNS TABLE (
    compliance_status VARCHAR,
    allergen_warnings JSONB,
    safety_concerns JSONB,
    recommended_actions JSONB
) AS $$
DECLARE
    customer_allergies TEXT[];
    order_allergens TEXT[] := ARRAY[]::TEXT[];
    warnings JSONB := '[]';
    concerns JSONB := '[]';
    actions JSONB := '[]';
BEGIN
    -- Get customer allergies
    SELECT allergies INTO customer_allergies
    FROM customers WHERE customer_id = (SELECT customer_id FROM orders WHERE order_id = order_uuid);

    -- Check all items in order for allergens
    SELECT array_agg(DISTINCT allergen)
    INTO order_allergens
    FROM order_items oi
    JOIN menu_items mi ON oi.item_id = mi.item_id
    WHERE oi.order_id = order_uuid
      AND mi.allergens IS NOT NULL;

    -- Check for conflicts
    IF customer_allergies IS NOT NULL AND order_allergens IS NOT NULL THEN
        IF customer_allergies && order_allergens THEN
            warnings := warnings || jsonb_build_object(
                'type', 'allergen_conflict',
                'severity', 'critical',
                'message', 'Order contains allergens customer is allergic to',
                'conflicting_allergens', (SELECT array_agg(allergen)
                                        FROM unnest(customer_allergies) as customer_allergen(allergen)
                                        WHERE allergen = ANY(order_allergens))
            );

            concerns := concerns || jsonb_build_object(
                'type', 'food_safety',
                'risk_level', 'high',
                'description', 'Potential severe allergic reaction'
            );

            actions := actions || jsonb_build_object(
                'action', 'cancel_order',
                'priority', 'immediate',
                'reason', 'Customer safety concern'
            );
        END IF;
    END IF;

    -- Check for cross-contamination risks
    IF EXISTS (
        SELECT 1 FROM order_items oi
        JOIN menu_items mi ON oi.item_id = mi.item_id
        WHERE oi.order_id = order_uuid
          AND mi.allergens && customer_allergies
    ) THEN
        warnings := warnings || jsonb_build_object(
            'type', 'cross_contamination_risk',
            'severity', 'high',
            'message', 'Potential cross-contamination with allergens'
        );
    END IF;

    RETURN QUERY SELECT
        CASE WHEN jsonb_array_length(warnings) > 0 THEN 'non_compliant' ELSE 'compliant' END,
        warnings,
        concerns,
        actions;
END;
$$ LANGUAGE plpgsql;
```

### Delivery Time Compliance and SLA Management
```sql
-- Monitor delivery time compliance and SLA performance
CREATE OR REPLACE FUNCTION monitor_delivery_sla(order_uuid UUID)
RETURNS TABLE (
    sla_status VARCHAR,
    delivery_delay_minutes INTEGER,
    compensation_eligible BOOLEAN,
    compensation_amount DECIMAL,
    escalation_required BOOLEAN,
    performance_impact VARCHAR
) AS $$
DECLARE
    order_record orders%ROWTYPE;
    delay_minutes INTEGER;
    compensation_amt DECIMAL := 0;
    requires_escalation BOOLEAN := FALSE;
BEGIN
    -- Get order details
    SELECT * INTO order_record FROM orders WHERE order_id = order_uuid;

    -- Calculate delay
    delay_minutes := EXTRACT(EPOCH FROM (order_record.actual_delivery_time - order_record.estimated_delivery_time)) / 60;

    -- Determine SLA status and compensation
    IF delay_minutes > 30 THEN
        compensation_amt := ROUND(order_record.total_amount * 0.1, 2); -- 10% compensation
        requires_escalation := TRUE;
    ELSIF delay_minutes > 15 THEN
        compensation_amt := ROUND(order_record.total_amount * 0.05, 2); -- 5% compensation
    END IF;

    -- Check for repeated issues with restaurant/driver
    IF delay_minutes > 10 THEN
        -- Check if this restaurant/driver has multiple delays
        IF (SELECT COUNT(*) FROM orders
            WHERE restaurant_id = order_record.restaurant_id
              AND order_date >= CURRENT_DATE - INTERVAL '7 days'
              AND EXTRACT(EPOCH FROM (actual_delivery_time - estimated_delivery_time)) / 60 > 10) > 3 THEN
            requires_escalation := TRUE;
        END IF;
    END IF;

    RETURN QUERY SELECT
        CASE
            WHEN delay_minutes <= 5 THEN 'excellent'
            WHEN delay_minutes <= 10 THEN 'good'
            WHEN delay_minutes <= 20 THEN 'acceptable'
            ELSE 'breach'
        END,
        delay_minutes,
        compensation_amt > 0,
        compensation_amt,
        requires_escalation,
        CASE
            WHEN delay_minutes > 30 THEN 'severe_impact'
            WHEN delay_minutes > 15 THEN 'moderate_impact'
            WHEN delay_minutes > 0 THEN 'minor_impact'
            ELSE 'positive_impact'
        END;
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Payment processors** (Stripe, PayPal, Square) for secure transactions
- **Mapping services** (Google Maps, Mapbox) for delivery routing
- **Restaurant POS systems** for order synchronization
- **SMS/Notification services** for order updates

### API Endpoints
- **Order management APIs** for real-time order processing and status updates
- **Restaurant APIs** for menu updates and availability synchronization
- **Driver APIs** for location tracking and assignment optimization
- **Customer APIs** for order history and preference management

## Monitoring & Analytics

### Key Performance Indicators
- **Order fulfillment rates** and average delivery times
- **Customer satisfaction scores** and repeat order rates
- **Driver utilization** and performance metrics
- **Restaurant performance** and menu item popularity
- **Platform revenue** and commission tracking

### Real-Time Dashboards
```sql
-- Food delivery operations dashboard
CREATE VIEW food_delivery_operations_dashboard AS
SELECT
    -- Order metrics (today)
    (SELECT COUNT(*) FROM orders WHERE DATE(order_date) = CURRENT_DATE) as orders_today,
    (SELECT COUNT(*) FROM orders WHERE DATE(order_date) = CURRENT_DATE AND order_status = 'delivered') as completed_orders_today,
    (SELECT SUM(total_amount) FROM orders WHERE DATE(order_date) = CURRENT_DATE AND order_status = 'delivered') as revenue_today,

    -- Delivery performance
    (SELECT AVG(EXTRACT(EPOCH FROM (actual_delivery_time - estimated_delivery_time))/60)
     FROM orders WHERE DATE(order_date) = CURRENT_DATE AND order_status = 'delivered') as avg_delivery_delay_today,
    (SELECT COUNT(*) FROM orders WHERE DATE(order_date) = CURRENT_DATE AND actual_delivery_time <= estimated_delivery_time) /
    NULLIF((SELECT COUNT(*) FROM orders WHERE DATE(order_date) = CURRENT_DATE AND order_status = 'delivered'), 0) * 100 as on_time_delivery_rate,

    -- Driver metrics
    (SELECT COUNT(*) FROM delivery_drivers WHERE driver_status = 'available') as available_drivers,
    (SELECT COUNT(*) FROM delivery_drivers WHERE driver_status = 'busy') as busy_drivers,
    (SELECT AVG(average_rating) FROM delivery_drivers) as avg_driver_rating,

    -- Restaurant metrics
    (SELECT COUNT(*) FROM restaurants WHERE restaurant_status = 'active') as active_restaurants,
    (SELECT COUNT(*) FROM menu_items WHERE is_available = TRUE) as available_menu_items,
    (SELECT AVG(average_rating) FROM restaurants WHERE restaurant_status = 'active') as avg_restaurant_rating,

    -- Customer metrics
    (SELECT COUNT(DISTINCT customer_id) FROM orders WHERE DATE(order_date) = CURRENT_DATE) as unique_customers_today,
    (SELECT AVG(customer_rating) FROM orders WHERE DATE(order_date) = CURRENT_DATE AND customer_rating IS NOT NULL) as avg_customer_rating_today,

    -- System health
    (SELECT COUNT(*) FROM orders WHERE order_status IN ('pending', 'confirmed', 'preparing', 'ready_for_pickup', 'out_for_delivery')) as active_orders,
    (SELECT COUNT(*) FROM support_tickets WHERE ticket_status = 'open') as open_support_tickets
;
```

This food delivery database schema provides enterprise-grade infrastructure for order processing, delivery logistics, restaurant management, and customer service operations required for modern food delivery platforms.
