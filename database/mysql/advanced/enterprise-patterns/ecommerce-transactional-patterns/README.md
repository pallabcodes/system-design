# Ecommerce & Quick Commerce Transactional Patterns

Advanced transactional patterns, inventory management, order processing, and real-time delivery coordination techniques used by product engineers at Amazon, Shopify, Uber Eats, DoorDash, and other ecommerce/quick commerce platforms.

## 🛒 Ecommerce Transactional Patterns

### The "Inventory Reservation with Optimistic Locking" Pattern
```sql
-- Inventory management with optimistic locking
CREATE TABLE inventory_reservations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_variant_id BIGINT NOT NULL,
    warehouse_id BIGINT NOT NULL,
    reserved_quantity INT NOT NULL DEFAULT 0,
    available_quantity INT NOT NULL DEFAULT 0,
    reserved_for_orders INT NOT NULL DEFAULT 0,
    reserved_for_carts INT NOT NULL DEFAULT 0,
    version INT DEFAULT 1,  -- Optimistic locking version
    last_updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_variant_warehouse (product_variant_id, warehouse_id),
    INDEX idx_warehouse_inventory (warehouse_id, available_quantity),
    INDEX idx_variant_availability (product_variant_id, available_quantity)
);

-- Inventory reservation procedure
DELIMITER //
CREATE PROCEDURE reserve_inventory_optimistic(
    IN p_product_variant_id BIGINT,
    IN p_warehouse_id BIGINT,
    IN p_quantity INT,
    IN p_reservation_type ENUM('cart', 'order') NOT NULL,
    IN p_expected_version INT,
    IN p_timeout_minutes INT DEFAULT 30
)
BEGIN
    DECLARE current_version INT;
    DECLARE current_available INT;
    DECLARE reservation_expires_at TIMESTAMP;
    DECLARE rows_affected INT;
    
    -- Calculate reservation expiry
    SET reservation_expires_at = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL p_timeout_minutes MINUTE);
    
    START TRANSACTION;
    
    -- Get current inventory state with lock
    SELECT version, available_quantity INTO current_version, current_available
    FROM inventory_reservations 
    WHERE product_variant_id = p_product_variant_id 
    AND warehouse_id = p_warehouse_id 
    FOR UPDATE;
    
    -- Check version and availability
    IF current_version = p_expected_version AND current_available >= p_quantity THEN
        -- Update inventory with new version
        UPDATE inventory_reservations 
        SET available_quantity = available_quantity - p_quantity,
            reserved_quantity = reserved_quantity + p_quantity,
            reserved_for_orders = reserved_for_orders + IF(p_reservation_type = 'order', p_quantity, 0),
            reserved_for_carts = reserved_for_carts + IF(p_reservation_type = 'cart', p_quantity, 0),
            version = version + 1,
            last_updated_at = CURRENT_TIMESTAMP
        WHERE product_variant_id = p_product_variant_id 
        AND warehouse_id = p_warehouse_id 
        AND version = p_expected_version;
        
        SET rows_affected = ROW_COUNT();
        
        IF rows_affected > 0 THEN
            -- Create reservation record
            INSERT INTO inventory_reservation_logs (
                product_variant_id, warehouse_id, quantity, reservation_type, 
                expires_at, status
            ) VALUES (
                p_product_variant_id, p_warehouse_id, p_quantity, p_reservation_type,
                reservation_expires_at, 'active'
            );
            
            COMMIT;
            SELECT 'RESERVATION_SUCCESS' as result, current_version + 1 as new_version;
        ELSE
            ROLLBACK;
            SELECT 'CONCURRENT_MODIFICATION' as result, current_version as current_version;
        END IF;
    ELSE
        ROLLBACK;
        IF current_version != p_expected_version THEN
            SELECT 'VERSION_MISMATCH' as result, current_version as current_version;
        ELSE
            SELECT 'INSUFFICIENT_STOCK' as result, current_available as available_quantity;
        END IF;
    END IF;
END //
DELIMITER ;

### The "Order Processing with Saga Pattern" Pattern
```sql
-- Order processing saga
CREATE TABLE order_sagas (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    saga_id VARCHAR(100) UNIQUE NOT NULL,
    order_id BIGINT NOT NULL,
    saga_type ENUM('order_creation', 'order_cancellation', 'order_modification', 'refund_processing') NOT NULL,
    saga_status ENUM('pending', 'in_progress', 'completed', 'failed', 'compensating') DEFAULT 'pending',
    saga_data JSON NOT NULL,  -- Order data
    current_step INT DEFAULT 0,
    total_steps INT NOT NULL,
    compensation_data JSON,  -- Compensation actions
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_order_saga (order_id, saga_type),
    INDEX idx_saga_status (saga_status, saga_type)
);

-- Order processing steps
CREATE TABLE order_processing_steps (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    saga_id VARCHAR(100) NOT NULL,
    step_number INT NOT NULL,
    step_name VARCHAR(100) NOT NULL,
    step_type ENUM('inventory_check', 'payment_processing', 'order_creation', 'notification_send', 'compensation') NOT NULL,
    step_status ENUM('pending', 'executing', 'completed', 'failed', 'compensated') DEFAULT 'pending',
    step_data JSON,  -- Step-specific data
    error_message TEXT,
    executed_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    
    UNIQUE KEY uk_saga_step (saga_id, step_number),
    INDEX idx_saga_steps (saga_id, step_status)
);

-- Order processing procedure
DELIMITER //
CREATE PROCEDURE process_order_saga(
    IN p_order_id BIGINT,
    IN p_order_data JSON
)
BEGIN
    DECLARE saga_id_val VARCHAR(100);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        -- Trigger compensation
        UPDATE order_sagas SET saga_status = 'compensating' WHERE saga_id = saga_id_val;
    END;
    
    SET saga_id_val = CONCAT('ORDER_', p_order_id, '_', UNIX_TIMESTAMP());
    
    START TRANSACTION;
    
    -- Initialize saga
    INSERT INTO order_sagas (saga_id, order_id, saga_type, saga_data, total_steps)
    VALUES (saga_id_val, p_order_id, 'order_creation', p_order_data, 4);
    
    -- Initialize processing steps
    INSERT INTO order_processing_steps (saga_id, step_number, step_name, step_type, step_data) VALUES
    (saga_id_val, 1, 'inventory_check', 'inventory_check', JSON_OBJECT('order_id', p_order_id)),
    (saga_id_val, 2, 'payment_processing', 'payment_processing', JSON_OBJECT('order_id', p_order_id)),
    (saga_id_val, 3, 'order_creation', 'order_creation', JSON_OBJECT('order_id', p_order_id)),
    (saga_id_val, 4, 'notification_send', 'notification_send', JSON_OBJECT('order_id', p_order_id));
    
    COMMIT;
    
    -- Execute steps (application level)
    SELECT 'SAGA_INITIATED' as result, saga_id_val as saga_id;
END //
DELIMITER ;

### The "Payment Processing with Idempotency" Pattern
```sql
-- Payment processing with idempotency
CREATE TABLE payment_transactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(100) UNIQUE NOT NULL,
    order_id BIGINT NOT NULL,
    payment_method ENUM('credit_card', 'debit_card', 'paypal', 'apple_pay', 'google_pay', 'crypto') NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    status ENUM('pending', 'processing', 'completed', 'failed', 'refunded', 'cancelled') DEFAULT 'pending',
    gateway_response JSON,  -- Payment gateway response
    idempotency_key VARCHAR(100) UNIQUE NOT NULL,  -- For idempotency
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_order_payment (order_id, status),
    INDEX idx_transaction_status (status, created_at),
    INDEX idx_idempotency (idempotency_key)
);

-- Payment idempotency procedure
DELIMITER //
CREATE PROCEDURE process_payment_idempotent(
    IN p_order_id BIGINT,
    IN p_payment_method ENUM('credit_card', 'debit_card', 'paypal', 'apple_pay', 'google_pay', 'crypto'),
    IN p_amount DECIMAL(10,2),
    IN p_idempotency_key VARCHAR(100),
    IN p_gateway_data JSON
)
BEGIN
    DECLARE existing_transaction_id VARCHAR(100);
    DECLARE existing_status ENUM('pending', 'processing', 'completed', 'failed', 'refunded', 'cancelled');
    
    START TRANSACTION;
    
    -- Check for existing transaction with same idempotency key
    SELECT transaction_id, status INTO existing_transaction_id, existing_status
    FROM payment_transactions 
    WHERE idempotency_key = p_idempotency_key
    FOR UPDATE;
    
    IF existing_transaction_id IS NOT NULL THEN
        -- Idempotency: return existing result
        IF existing_status = 'completed' THEN
            COMMIT;
            SELECT 'PAYMENT_ALREADY_COMPLETED' as result, existing_transaction_id as transaction_id;
        ELSEIF existing_status IN ('pending', 'processing') THEN
            COMMIT;
            SELECT 'PAYMENT_IN_PROGRESS' as result, existing_transaction_id as transaction_id;
        ELSE
            COMMIT;
            SELECT 'PAYMENT_FAILED' as result, existing_transaction_id as transaction_id;
        END IF;
    ELSE
        -- Create new payment transaction
        INSERT INTO payment_transactions (
            transaction_id, order_id, payment_method, amount, 
            idempotency_key, gateway_response
        ) VALUES (
            CONCAT('PAY_', p_order_id, '_', UNIX_TIMESTAMP()),
            p_order_id, p_payment_method, p_amount,
            p_idempotency_key, p_gateway_data
        );
        
        COMMIT;
        
        -- Process payment (application level)
        SELECT 'PAYMENT_INITIATED' as result, LAST_INSERT_ID() as transaction_id;
    END IF;
END //
DELIMITER ;

## 🚚 Quick Commerce Transactional Patterns

### The "Real-Time Order Assignment with Load Balancing" Pattern
```sql
-- Real-time order assignment for quick commerce
CREATE TABLE delivery_orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    restaurant_id BIGINT NOT NULL,
    driver_id BIGINT NULL,  -- Assigned driver
    order_status ENUM('pending', 'confirmed', 'preparing', 'ready', 'picked_up', 'in_transit', 'delivered', 'cancelled') DEFAULT 'pending',
    order_total DECIMAL(10,2) NOT NULL,
    delivery_fee DECIMAL(5,2) DEFAULT 0,
    tip_amount DECIMAL(5,2) DEFAULT 0,
    estimated_delivery_time TIMESTAMP NULL,
    actual_delivery_time TIMESTAMP NULL,
    pickup_time TIMESTAMP NULL,
    customer_location POINT NOT NULL,  -- Customer delivery location
    restaurant_location POINT NOT NULL,  -- Restaurant location
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_order_status (order_status, created_at),
    INDEX idx_driver_orders (driver_id, order_status),
    INDEX idx_restaurant_orders (restaurant_id, order_status),
    SPATIAL INDEX idx_customer_location (customer_location),
    SPATIAL INDEX idx_restaurant_location (restaurant_location)
);

-- Driver availability and load tracking
CREATE TABLE driver_availability (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    driver_id BIGINT NOT NULL,
    current_location POINT NOT NULL,
    is_available BOOLEAN DEFAULT TRUE,
    current_load INT DEFAULT 0,  -- Number of active orders
    max_load INT DEFAULT 3,  -- Maximum orders driver can handle
    last_location_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    status ENUM('online', 'offline', 'busy', 'on_break') DEFAULT 'offline',
    
    UNIQUE KEY uk_driver_availability (driver_id),
    SPATIAL INDEX idx_driver_location (current_location),
    INDEX idx_available_drivers (is_available, current_load, status)
);

-- Real-time order assignment procedure
DELIMITER //
CREATE PROCEDURE assign_order_to_driver(
    IN p_order_id BIGINT,
    IN p_customer_lat DECIMAL(10,8),
    IN p_customer_lng DECIMAL(10,8),
    IN p_restaurant_lat DECIMAL(10,8),
    IN p_restaurant_lng DECIMAL(10,8),
    IN p_max_distance_km DECIMAL(5,2) DEFAULT 5.0
)
BEGIN
    DECLARE assigned_driver_id BIGINT;
    DECLARE driver_count INT DEFAULT 0;
    
    START TRANSACTION;
    
    -- Find available drivers within range with load balancing
    SELECT da.driver_id INTO assigned_driver_id
    FROM driver_availability da
    WHERE da.is_available = TRUE 
    AND da.status = 'online'
    AND da.current_load < da.max_load
    AND ST_Distance_Sphere(
        da.current_location, 
        POINT(p_customer_lat, p_customer_lng)
    ) <= (p_max_distance_km * 1000)  -- Convert km to meters
    ORDER BY da.current_load ASC,  -- Load balancing: prefer drivers with fewer orders
           ST_Distance_Sphere(da.current_location, POINT(p_customer_lat, p_customer_lng)) ASC
    LIMIT 1
    FOR UPDATE;
    
    IF assigned_driver_id IS NOT NULL THEN
        -- Assign order to driver
        UPDATE delivery_orders 
        SET driver_id = assigned_driver_id,
            order_status = 'confirmed',
            updated_at = CURRENT_TIMESTAMP
        WHERE order_id = p_order_id;
        
        -- Update driver load
        UPDATE driver_availability 
        SET current_load = current_load + 1,
            last_location_update = CURRENT_TIMESTAMP
        WHERE driver_id = assigned_driver_id;
        
        COMMIT;
        SELECT 'ORDER_ASSIGNED' as result, assigned_driver_id as driver_id;
    ELSE
        ROLLBACK;
        SELECT 'NO_AVAILABLE_DRIVERS' as result;
    END IF;
END //
DELIMITER ;

### The "Dynamic Pricing with Inventory Synchronization" Pattern
```sql
-- Dynamic pricing for quick commerce
CREATE TABLE dynamic_pricing_rules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    restaurant_id BIGINT NOT NULL,
    rule_type ENUM('demand_based', 'time_based', 'weather_based', 'inventory_based') NOT NULL,
    rule_conditions JSON NOT NULL,  -- When to apply this rule
    price_multiplier DECIMAL(3,2) NOT NULL,  -- Price multiplier (1.0 = no change)
    max_multiplier DECIMAL(3,2) DEFAULT 2.0,  -- Maximum allowed multiplier
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_restaurant_rules (restaurant_id, is_active),
    INDEX idx_rule_type (rule_type, is_active)
);

-- Real-time demand tracking
CREATE TABLE demand_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    restaurant_id BIGINT NOT NULL,
    time_slot TIMESTAMP NOT NULL,  -- 15-minute time slots
    order_count INT DEFAULT 0,
    avg_preparation_time INT DEFAULT 0,  -- in minutes
    driver_wait_time INT DEFAULT 0,  -- in minutes
    demand_score DECIMAL(3,2) DEFAULT 1.0,  -- Normalized demand (1.0 = normal)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_restaurant_time (restaurant_id, time_slot),
    INDEX idx_demand_score (demand_score, time_slot)
);

-- Dynamic pricing calculation procedure
DELIMITER //
CREATE PROCEDURE calculate_dynamic_pricing(
    IN p_restaurant_id BIGINT,
    IN p_base_price DECIMAL(10,2)
)
BEGIN
    DECLARE final_price DECIMAL(10,2);
    DECLARE demand_multiplier DECIMAL(3,2) DEFAULT 1.0;
    DECLARE time_multiplier DECIMAL(3,2) DEFAULT 1.0;
    DECLARE current_demand_score DECIMAL(3,2);
    DECLARE current_hour INT;
    
    -- Get current demand score
    SELECT demand_score INTO current_demand_score
    FROM demand_metrics 
    WHERE restaurant_id = p_restaurant_id 
    AND time_slot >= DATE_SUB(NOW(), INTERVAL 15 MINUTE)
    ORDER BY time_slot DESC 
    LIMIT 1;
    
    -- Get current hour for time-based pricing
    SET current_hour = HOUR(NOW());
    
    -- Calculate demand-based multiplier
    IF current_demand_score > 1.5 THEN
        SET demand_multiplier = LEAST(current_demand_score, 2.0);
    END IF;
    
    -- Calculate time-based multiplier (peak hours)
    IF current_hour BETWEEN 11 AND 14 OR current_hour BETWEEN 17 AND 21 THEN
        SET time_multiplier = 1.2;  -- 20% increase during peak hours
    END IF;
    
    -- Apply dynamic pricing rules
    SELECT COALESCE(
        (SELECT price_multiplier 
         FROM dynamic_pricing_rules 
         WHERE restaurant_id = p_restaurant_id 
         AND is_active = TRUE 
         AND JSON_CONTAINS(rule_conditions, JSON_OBJECT('demand_score', current_demand_score))
         ORDER BY price_multiplier DESC 
         LIMIT 1), 
        1.0
    ) INTO demand_multiplier;
    
    -- Calculate final price with caps
    SET final_price = p_base_price * demand_multiplier * time_multiplier;
    
    -- Ensure price doesn't exceed maximum multiplier
    SELECT LEAST(final_price, p_base_price * 2.0) INTO final_price;
    
    SELECT final_price as dynamic_price, 
           demand_multiplier as demand_multiplier,
           time_multiplier as time_multiplier,
           current_demand_score as demand_score;
END //
DELIMITER ;

### The "Multi-Warehouse Inventory Synchronization" Pattern
```sql
-- Multi-warehouse inventory for quick commerce
CREATE TABLE warehouse_inventory (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    warehouse_id BIGINT NOT NULL,
    product_variant_id BIGINT NOT NULL,
    available_quantity INT NOT NULL DEFAULT 0,
    reserved_quantity INT NOT NULL DEFAULT 0,
    in_transit_quantity INT NOT NULL DEFAULT 0,  -- Items being transferred
    reorder_point INT DEFAULT 10,  -- When to reorder
    max_stock INT DEFAULT 100,  -- Maximum stock level
    last_restocked_at TIMESTAMP NULL,
    version INT DEFAULT 1,  -- Optimistic locking
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_warehouse_product (warehouse_id, product_variant_id),
    INDEX idx_product_availability (product_variant_id, available_quantity),
    INDEX idx_warehouse_stock (warehouse_id, available_quantity)
);

-- Inventory transfers between warehouses
CREATE TABLE inventory_transfers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transfer_id VARCHAR(100) UNIQUE NOT NULL,
    from_warehouse_id BIGINT NOT NULL,
    to_warehouse_id BIGINT NOT NULL,
    product_variant_id BIGINT NOT NULL,
    quantity INT NOT NULL,
    transfer_status ENUM('pending', 'in_transit', 'completed', 'cancelled', 'failed') DEFAULT 'pending',
    transfer_reason ENUM('rebalancing', 'demand_shift', 'stockout_prevention', 'seasonal') NOT NULL,
    estimated_arrival TIMESTAMP NULL,
    actual_arrival TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_transfer_status (transfer_status, created_at),
    INDEX idx_warehouse_transfers (from_warehouse_id, to_warehouse_id, transfer_status)
);

-- Multi-warehouse inventory synchronization procedure
DELIMITER //
CREATE PROCEDURE synchronize_warehouse_inventory(
    IN p_product_variant_id BIGINT,
    IN p_quantity INT,
    IN p_from_warehouse_id BIGINT,
    IN p_to_warehouse_id BIGINT,
    IN p_transfer_reason ENUM('rebalancing', 'demand_shift', 'stockout_prevention', 'seasonal')
)
BEGIN
    DECLARE from_warehouse_version INT;
    DECLARE to_warehouse_version INT;
    DECLARE from_available_quantity INT;
    DECLARE transfer_id_val VARCHAR(100);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Inventory synchronization failed';
    END;
    
    SET transfer_id_val = CONCAT('TRANSFER_', p_product_variant_id, '_', UNIX_TIMESTAMP());
    
    START TRANSACTION;
    
    -- Lock source warehouse inventory
    SELECT version, available_quantity INTO from_warehouse_version, from_available_quantity
    FROM warehouse_inventory 
    WHERE warehouse_id = p_from_warehouse_id 
    AND product_variant_id = p_product_variant_id 
    FOR UPDATE;
    
    -- Lock destination warehouse inventory
    SELECT version INTO to_warehouse_version
    FROM warehouse_inventory 
    WHERE warehouse_id = p_to_warehouse_id 
    AND product_variant_id = p_product_variant_id 
    FOR UPDATE;
    
    -- Check if source has enough inventory
    IF from_available_quantity >= p_quantity THEN
        -- Update source warehouse
        UPDATE warehouse_inventory 
        SET available_quantity = available_quantity - p_quantity,
            in_transit_quantity = in_transit_quantity + p_quantity,
            version = version + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE warehouse_id = p_from_warehouse_id 
        AND product_variant_id = p_product_variant_id;
        
        -- Update destination warehouse
        UPDATE warehouse_inventory 
        SET in_transit_quantity = in_transit_quantity + p_quantity,
            version = version + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE warehouse_id = p_to_warehouse_id 
        AND product_variant_id = p_product_variant_id;
        
        -- Create transfer record
        INSERT INTO inventory_transfers (
            transfer_id, from_warehouse_id, to_warehouse_id, 
            product_variant_id, quantity, transfer_reason
        ) VALUES (
            transfer_id_val, p_from_warehouse_id, p_to_warehouse_id,
            p_product_variant_id, p_quantity, p_transfer_reason
        );
        
        COMMIT;
        SELECT 'TRANSFER_INITIATED' as result, transfer_id_val as transfer_id;
    ELSE
        ROLLBACK;
        SELECT 'INSUFFICIENT_INVENTORY' as result, from_available_quantity as available_quantity;
    END IF;
END //
DELIMITER ;

## 🔄 Advanced Ecommerce Transaction Patterns

### The "Flash Sale with Rate Limiting" Pattern
```sql
-- Flash sale management with rate limiting
CREATE TABLE flash_sales (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sale_id VARCHAR(100) UNIQUE NOT NULL,
    product_variant_id BIGINT NOT NULL,
    original_price DECIMAL(10,2) NOT NULL,
    sale_price DECIMAL(10,2) NOT NULL,
    total_quantity INT NOT NULL,
    reserved_quantity INT NOT NULL DEFAULT 0,
    sold_quantity INT NOT NULL DEFAULT 0,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    max_per_customer INT DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_sale_active (is_active, start_time, end_time),
    INDEX idx_product_sale (product_variant_id, is_active)
);

-- Flash sale reservations
CREATE TABLE flash_sale_reservations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sale_id VARCHAR(100) NOT NULL,
    customer_id BIGINT NOT NULL,
    quantity INT NOT NULL,
    reservation_token VARCHAR(100) UNIQUE NOT NULL,
    reservation_expires_at TIMESTAMP NOT NULL,
    reservation_status ENUM('reserved', 'confirmed', 'expired', 'cancelled') DEFAULT 'reserved',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_sale_customer (sale_id, customer_id),
    INDEX idx_reservation_status (reservation_status, reservation_expires_at),
    INDEX idx_reservation_token (reservation_token)
);

-- Flash sale reservation procedure with rate limiting
DELIMITER //
CREATE PROCEDURE reserve_flash_sale_item(
    IN p_sale_id VARCHAR(100),
    IN p_customer_id BIGINT,
    IN p_quantity INT,
    IN p_reservation_duration_minutes INT DEFAULT 10
)
BEGIN
    DECLARE sale_available_quantity INT;
    DECLARE customer_already_reserved INT;
    DECLARE max_per_customer_val INT;
    DECLARE reservation_token_val VARCHAR(100);
    DECLARE reservation_expires_at TIMESTAMP;
    
    SET reservation_expires_at = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL p_reservation_duration_minutes MINUTE);
    SET reservation_token_val = CONCAT('FLASH_', p_sale_id, '_', p_customer_id, '_', UNIX_TIMESTAMP());
    
    START TRANSACTION;
    
    -- Check flash sale availability
    SELECT (total_quantity - reserved_quantity - sold_quantity), max_per_customer 
    INTO sale_available_quantity, max_per_customer_val
    FROM flash_sales 
    WHERE sale_id = p_sale_id 
    AND is_active = TRUE 
    AND NOW() BETWEEN start_time AND end_time
    FOR UPDATE;
    
    -- Check if customer already has a reservation
    SELECT COALESCE(SUM(quantity), 0) INTO customer_already_reserved
    FROM flash_sale_reservations 
    WHERE sale_id = p_sale_id 
    AND customer_id = p_customer_id 
    AND reservation_status = 'reserved'
    AND reservation_expires_at > NOW();
    
    -- Validate reservation
    IF sale_available_quantity IS NULL THEN
        ROLLBACK;
        SELECT 'SALE_NOT_AVAILABLE' as result;
    ELSEIF sale_available_quantity < p_quantity THEN
        ROLLBACK;
        SELECT 'INSUFFICIENT_QUANTITY' as result, sale_available_quantity as available_quantity;
    ELSEIF (customer_already_reserved + p_quantity) > max_per_customer_val THEN
        ROLLBACK;
        SELECT 'EXCEEDS_CUSTOMER_LIMIT' as result, max_per_customer_val as max_per_customer;
    ELSE
        -- Create reservation
        INSERT INTO flash_sale_reservations (
            sale_id, customer_id, quantity, reservation_token, reservation_expires_at
        ) VALUES (
            p_sale_id, p_customer_id, p_quantity, reservation_token_val, reservation_expires_at
        );
        
        -- Update flash sale reserved quantity
        UPDATE flash_sales 
        SET reserved_quantity = reserved_quantity + p_quantity
        WHERE sale_id = p_sale_id;
        
        COMMIT;
        SELECT 'RESERVATION_SUCCESS' as result, reservation_token_val as reservation_token;
    END IF;
END //
DELIMITER ;

### The "Subscription Management with Billing Cycles" Pattern
```sql
-- Subscription management for ecommerce
CREATE TABLE subscriptions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    subscription_id VARCHAR(100) UNIQUE NOT NULL,
    customer_id BIGINT NOT NULL,
    product_variant_id BIGINT NOT NULL,
    subscription_plan ENUM('weekly', 'biweekly', 'monthly', 'quarterly', 'yearly') NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    status ENUM('active', 'paused', 'cancelled', 'expired') DEFAULT 'active',
    current_billing_cycle INT DEFAULT 1,
    total_billing_cycles INT NULL,  -- NULL for unlimited
    next_billing_date DATE NOT NULL,
    last_billing_date DATE NULL,
    billing_amount DECIMAL(10,2) NOT NULL,
    discount_percentage DECIMAL(5,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_customer_subscriptions (customer_id, status),
    INDEX idx_next_billing (next_billing_date, status),
    INDEX idx_subscription_status (status, next_billing_date)
);

-- Subscription billing cycles
CREATE TABLE subscription_billing_cycles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    subscription_id VARCHAR(100) NOT NULL,
    billing_cycle_number INT NOT NULL,
    billing_date DATE NOT NULL,
    order_id BIGINT NULL,  -- Generated order for this cycle
    billing_status ENUM('pending', 'processing', 'completed', 'failed', 'skipped') DEFAULT 'pending',
    billing_amount DECIMAL(10,2) NOT NULL,
    discount_applied DECIMAL(10,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_subscription_cycle (subscription_id, billing_cycle_number),
    INDEX idx_billing_status (billing_status, billing_date),
    INDEX idx_pending_billing (billing_status, billing_date)
);

-- Subscription billing procedure
DELIMITER //
CREATE PROCEDURE process_subscription_billing(
    IN p_billing_date DATE
)
BEGIN
    DECLARE done BOOLEAN DEFAULT FALSE;
    DECLARE subscription_id_val VARCHAR(100);
    DECLARE customer_id_val BIGINT;
    DECLARE product_variant_id_val BIGINT;
    DECLARE quantity_val INT;
    DECLARE billing_amount_val DECIMAL(10,2);
    DECLARE billing_cycle_val INT;
    DECLARE order_id_val BIGINT;
    
    -- Cursor for subscriptions due for billing
    DECLARE subscription_cursor CURSOR FOR
        SELECT s.subscription_id, s.customer_id, s.product_variant_id, 
               s.quantity, s.billing_amount, s.current_billing_cycle
        FROM subscriptions s
        WHERE s.status = 'active' 
        AND s.next_billing_date = p_billing_date
        AND (s.total_billing_cycles IS NULL OR s.current_billing_cycle <= s.total_billing_cycles);
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN subscription_cursor;
    
    billing_loop: LOOP
        FETCH subscription_cursor INTO subscription_id_val, customer_id_val, 
                                       product_variant_id_val, quantity_val, 
                                       billing_amount_val, billing_cycle_val;
        
        IF done THEN
            LEAVE billing_loop;
        END IF;
        
        START TRANSACTION;
        
        -- Create billing cycle record
        INSERT INTO subscription_billing_cycles (
            subscription_id, billing_cycle_number, billing_date, billing_amount
        ) VALUES (
            subscription_id_val, billing_cycle_val, p_billing_date, billing_amount_val
        );
        
        -- Create order for this billing cycle
        INSERT INTO orders (customer_id, order_type, status, total_amount)
        VALUES (customer_id_val, 'subscription', 'pending', billing_amount_val);
        
        SET order_id_val = LAST_INSERT_ID();
        
        -- Add order item
        INSERT INTO order_items (order_id, product_variant_id, quantity, unit_price)
        VALUES (order_id_val, product_variant_id_val, quantity_val, billing_amount_val / quantity_val);
        
        -- Update subscription
        UPDATE subscriptions 
        SET current_billing_cycle = current_billing_cycle + 1,
            last_billing_date = p_billing_date,
            next_billing_date = CASE subscription_plan
                WHEN 'weekly' THEN DATE_ADD(p_billing_date, INTERVAL 1 WEEK)
                WHEN 'biweekly' THEN DATE_ADD(p_billing_date, INTERVAL 2 WEEK)
                WHEN 'monthly' THEN DATE_ADD(p_billing_date, INTERVAL 1 MONTH)
                WHEN 'quarterly' THEN DATE_ADD(p_billing_date, INTERVAL 3 MONTH)
                WHEN 'yearly' THEN DATE_ADD(p_billing_date, INTERVAL 1 YEAR)
            END,
            updated_at = CURRENT_TIMESTAMP
        WHERE subscription_id = subscription_id_val;
        
        -- Update billing cycle with order ID
        UPDATE subscription_billing_cycles 
        SET order_id = order_id_val,
            billing_status = 'processing'
        WHERE subscription_id = subscription_id_val 
        AND billing_cycle_number = billing_cycle_val;
        
        COMMIT;
        
    END LOOP;
    
    CLOSE subscription_cursor;
    
    SELECT 'BILLING_PROCESSED' as result, p_billing_date as billing_date;
END //
DELIMITER ;

These ecommerce and quick commerce transactional patterns show the real-world techniques that product engineers use to handle complex inventory management, order processing, payment handling, and delivery coordination in high-scale ecommerce and quick commerce platforms! 🚀

## 📊 Ecommerce & Quick Commerce Window Functions

### The "Customer Lifetime Value (CLV) Analysis" Pattern
```sql
-- Customer lifetime value calculation with window functions
CREATE VIEW customer_lifetime_value AS
SELECT 
    customer_id,
    customer_name,
    total_orders,
    total_spent,
    avg_order_value,
    first_order_date,
    last_order_date,
    days_since_first_order,
    days_since_last_order,
    -- Running total of customer spending
    SUM(total_spent) OVER (
        PARTITION BY customer_id 
        ORDER BY last_order_date 
        ROWS UNBOUNDED PRECEDING
    ) as cumulative_spending,
    -- Customer spending rank within their segment
    RANK() OVER (
        PARTITION BY customer_segment 
        ORDER BY total_spent DESC
    ) as spending_rank_in_segment,
    -- Percentage of total revenue from this customer
    (total_spent / SUM(total_spent) OVER ()) * 100 as revenue_percentage,
    -- Moving average of order values (last 5 orders)
    AVG(avg_order_value) OVER (
        PARTITION BY customer_id 
        ORDER BY last_order_date 
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ) as moving_avg_order_value,
    -- Customer spending trend (positive/negative)
    CASE 
        WHEN LAG(avg_order_value) OVER (
            PARTITION BY customer_id 
            ORDER BY last_order_date
        ) < avg_order_value THEN 'increasing'
        WHEN LAG(avg_order_value) OVER (
            PARTITION BY customer_id 
            ORDER BY last_order_date
        ) > avg_order_value THEN 'decreasing'
        ELSE 'stable'
    END as spending_trend
FROM (
    SELECT 
        c.id as customer_id,
        c.name as customer_name,
        c.segment as customer_segment,
        COUNT(o.id) as total_orders,
        SUM(o.total_amount) as total_spent,
        AVG(o.total_amount) as avg_order_value,
        MIN(o.created_at) as first_order_date,
        MAX(o.created_at) as last_order_date,
        DATEDIFF(CURRENT_DATE, MIN(o.created_at)) as days_since_first_order,
        DATEDIFF(CURRENT_DATE, MAX(o.created_at)) as days_since_last_order
    FROM customers c
    LEFT JOIN orders o ON c.id = o.customer_id
    WHERE o.status = 'completed'
    GROUP BY c.id, c.name, c.segment
) customer_metrics;
```

### The "Product Performance Analytics" Pattern
```sql
-- Product performance analysis with window functions
CREATE VIEW product_performance_analytics AS
SELECT 
    p.id as product_id,
    p.name as product_name,
    p.category_id,
    c.name as category_name,
    total_sales,
    total_revenue,
    avg_price,
    total_orders,
    -- Product rank within category
    RANK() OVER (
        PARTITION BY p.category_id 
        ORDER BY total_revenue DESC
    ) as category_rank,
    -- Product rank overall
    RANK() OVER (
        ORDER BY total_revenue DESC
    ) as overall_rank,
    -- Revenue percentage within category
    (total_revenue / SUM(total_revenue) OVER (PARTITION BY p.category_id)) * 100 as category_revenue_percentage,
    -- Moving average of daily sales (last 30 days)
    AVG(daily_sales) OVER (
        PARTITION BY p.id 
        ORDER BY sale_date 
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) as moving_avg_daily_sales,
    -- Sales trend (last 7 days vs previous 7 days)
    CASE 
        WHEN LAG(weekly_sales, 1) OVER (
            PARTITION BY p.id 
            ORDER BY week_start_date
        ) < weekly_sales THEN 'increasing'
        WHEN LAG(weekly_sales, 1) OVER (
            PARTITION BY p.id 
            ORDER BY week_start_date
        ) > weekly_sales THEN 'decreasing'
        ELSE 'stable'
    END as sales_trend,
    -- Cumulative revenue over time
    SUM(total_revenue) OVER (
        PARTITION BY p.id 
        ORDER BY sale_date 
        ROWS UNBOUNDED PRECEDING
    ) as cumulative_revenue
FROM (
    SELECT 
        p.id,
        p.name,
        p.category_id,
        c.name as category_name,
        SUM(oi.quantity) as total_sales,
        SUM(oi.quantity * oi.unit_price) as total_revenue,
        AVG(oi.unit_price) as avg_price,
        COUNT(DISTINCT o.id) as total_orders,
        DATE(o.created_at) as sale_date,
        DATE_SUB(DATE(o.created_at), INTERVAL WEEKDAY(o.created_at) DAY) as week_start_date,
        SUM(oi.quantity) OVER (
            PARTITION BY p.id, DATE(o.created_at)
        ) as daily_sales,
        SUM(oi.quantity) OVER (
            PARTITION BY p.id, DATE_SUB(DATE(o.created_at), INTERVAL WEEKDAY(o.created_at) DAY)
        ) as weekly_sales
    FROM products p
    JOIN categories c ON p.category_id = c.id
    JOIN order_items oi ON p.id = oi.product_id
    JOIN orders o ON oi.order_id = o.id
    WHERE o.status = 'completed'
    GROUP BY p.id, p.name, p.category_id, c.name, DATE(o.created_at)
) product_metrics;
```

### The "Inventory Forecasting with Window Functions" Pattern
```sql
-- Inventory forecasting using window functions
CREATE VIEW inventory_forecasting AS
SELECT 
    product_variant_id,
    warehouse_id,
    current_stock,
    avg_daily_demand,
    -- Demand volatility (standard deviation)
    STDDEV(daily_demand) OVER (
        PARTITION BY product_variant_id, warehouse_id
    ) as demand_volatility,
    -- Moving average of daily demand (last 30 days)
    AVG(daily_demand) OVER (
        PARTITION BY product_variant_id, warehouse_id 
        ORDER BY demand_date 
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) as moving_avg_demand,
    -- Demand trend (last 7 days vs previous 7 days)
    CASE 
        WHEN LAG(weekly_demand, 1) OVER (
            PARTITION BY product_variant_id, warehouse_id 
            ORDER BY week_start_date
        ) < weekly_demand THEN 'increasing'
        WHEN LAG(weekly_demand, 1) OVER (
            PARTITION BY product_variant_id, warehouse_id 
            ORDER BY week_start_date
        ) > weekly_demand THEN 'decreasing'
        ELSE 'stable'
    END as demand_trend,
    -- Days until stockout (current_stock / avg_daily_demand)
    CASE 
        WHEN avg_daily_demand > 0 THEN FLOOR(current_stock / avg_daily_demand)
        ELSE NULL
    END as days_until_stockout,
    -- Reorder recommendation
    CASE 
        WHEN current_stock <= reorder_point THEN 'reorder_now'
        WHEN days_until_stockout <= 7 THEN 'reorder_soon'
        ELSE 'sufficient_stock'
    END as reorder_status,
    -- Seasonal demand pattern (compare to same period last year)
    LAG(daily_demand, 365) OVER (
        PARTITION BY product_variant_id, warehouse_id 
        ORDER BY demand_date
    ) as demand_same_period_last_year,
    -- Demand growth rate
    CASE 
        WHEN LAG(daily_demand, 365) OVER (
            PARTITION BY product_variant_id, warehouse_id 
            ORDER BY demand_date
        ) > 0 THEN 
            ((daily_demand - LAG(daily_demand, 365) OVER (
                PARTITION BY product_variant_id, warehouse_id 
                ORDER BY demand_date
            )) / LAG(daily_demand, 365) OVER (
                PARTITION BY product_variant_id, warehouse_id 
                ORDER BY demand_date
            )) * 100
        ELSE NULL
    END as demand_growth_percentage
FROM (
    SELECT 
        oi.product_variant_id,
        o.warehouse_id,
        i.available_quantity as current_stock,
        i.reorder_point,
        DATE(o.created_at) as demand_date,
        DATE_SUB(DATE(o.created_at), INTERVAL WEEKDAY(o.created_at) DAY) as week_start_date,
        SUM(oi.quantity) as daily_demand,
        SUM(oi.quantity) OVER (
            PARTITION BY oi.product_variant_id, o.warehouse_id, DATE(o.created_at)
        ) as daily_demand_total,
        SUM(oi.quantity) OVER (
            PARTITION BY oi.product_variant_id, o.warehouse_id, DATE_SUB(DATE(o.created_at), INTERVAL WEEKDAY(o.created_at) DAY)
        ) as weekly_demand,
        AVG(oi.quantity) OVER (
            PARTITION BY oi.product_variant_id, o.warehouse_id
        ) as avg_daily_demand
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    JOIN inventory i ON oi.product_variant_id = i.product_variant_id AND o.warehouse_id = i.warehouse_id
    WHERE o.status = 'completed'
    GROUP BY oi.product_variant_id, o.warehouse_id, DATE(o.created_at)
) demand_metrics;
```

### The "Quick Commerce Delivery Performance" Pattern
```sql
-- Delivery performance analysis for quick commerce
CREATE VIEW delivery_performance_analytics AS
SELECT 
    driver_id,
    driver_name,
    total_deliveries,
    avg_delivery_time_minutes,
    on_time_deliveries,
    late_deliveries,
    -- Driver performance rank
    RANK() OVER (
        ORDER BY (on_time_deliveries / total_deliveries) DESC, avg_delivery_time_minutes ASC
    ) as performance_rank,
    -- On-time delivery percentage
    (on_time_deliveries / total_deliveries) * 100 as on_time_percentage,
    -- Moving average of delivery times (last 20 deliveries)
    AVG(delivery_time_minutes) OVER (
        PARTITION BY driver_id 
        ORDER BY delivery_date 
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) as moving_avg_delivery_time,
    -- Delivery time trend
    CASE 
        WHEN LAG(avg_delivery_time_minutes) OVER (
            PARTITION BY driver_id 
            ORDER BY delivery_date
        ) > avg_delivery_time_minutes THEN 'improving'
        WHEN LAG(avg_delivery_time_minutes) OVER (
            PARTITION BY driver_id 
            ORDER BY delivery_date
        ) < avg_delivery_time_minutes THEN 'declining'
        ELSE 'stable'
    END as performance_trend,
    -- Driver efficiency (deliveries per hour)
    (total_deliveries / (SUM(delivery_time_minutes) OVER (PARTITION BY driver_id) / 60)) as deliveries_per_hour,
    -- Peak hour performance vs off-peak
    AVG(CASE 
        WHEN HOUR(pickup_time) BETWEEN 11 AND 14 OR HOUR(pickup_time) BETWEEN 17 AND 21 
        THEN delivery_time_minutes 
    END) OVER (PARTITION BY driver_id) as peak_hour_avg_time,
    AVG(CASE 
        WHEN HOUR(pickup_time) NOT BETWEEN 11 AND 14 AND HOUR(pickup_time) NOT BETWEEN 17 AND 21 
        THEN delivery_time_minutes 
    END) OVER (PARTITION BY driver_id) as off_peak_avg_time,
    -- Distance efficiency (delivery time per km)
    AVG(delivery_time_minutes / delivery_distance_km) OVER (PARTITION BY driver_id) as minutes_per_km
FROM (
    SELECT 
        d.id as driver_id,
        d.name as driver_name,
        COUNT(do.id) as total_deliveries,
        AVG(TIMESTAMPDIFF(MINUTE, do.pickup_time, do.actual_delivery_time)) as avg_delivery_time_minutes,
        SUM(CASE 
            WHEN TIMESTAMPDIFF(MINUTE, do.pickup_time, do.actual_delivery_time) <= 30 
            THEN 1 ELSE 0 
        END) as on_time_deliveries,
        SUM(CASE 
            WHEN TIMESTAMPDIFF(MINUTE, do.pickup_time, do.actual_delivery_time) > 30 
            THEN 1 ELSE 0 
        END) as late_deliveries,
        DATE(do.pickup_time) as delivery_date,
        do.pickup_time,
        TIMESTAMPDIFF(MINUTE, do.pickup_time, do.actual_delivery_time) as delivery_time_minutes,
        ST_Distance_Sphere(
            do.restaurant_location, 
            do.customer_location
        ) / 1000 as delivery_distance_km
    FROM drivers d
    JOIN delivery_orders do ON d.id = do.driver_id
    WHERE do.order_status = 'delivered'
    AND do.actual_delivery_time IS NOT NULL
    GROUP BY d.id, d.name, DATE(do.pickup_time)
) delivery_metrics;
```

### The "Dynamic Pricing Analytics" Pattern
```sql
-- Dynamic pricing analysis with window functions
CREATE VIEW dynamic_pricing_analytics AS
SELECT 
    restaurant_id,
    restaurant_name,
    base_price,
    dynamic_price,
    demand_score,
    -- Price elasticity (how demand changes with price)
    CASE 
        WHEN LAG(demand_score) OVER (
            PARTITION BY restaurant_id 
            ORDER BY time_slot
        ) > 0 THEN 
            ((demand_score - LAG(demand_score) OVER (
                PARTITION BY restaurant_id 
                ORDER BY time_slot
            )) / LAG(demand_score) OVER (
                PARTITION BY restaurant_id 
                ORDER BY time_slot
            )) / ((dynamic_price - base_price) / base_price)
        ELSE NULL
    END as price_elasticity,
    -- Revenue impact of dynamic pricing
    (dynamic_price - base_price) * order_count as additional_revenue,
    -- Moving average of demand (last 4 time slots)
    AVG(demand_score) OVER (
        PARTITION BY restaurant_id 
        ORDER BY time_slot 
        ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ) as moving_avg_demand,
    -- Demand percentile within restaurant's history
    PERCENT_RANK() OVER (
        PARTITION BY restaurant_id 
        ORDER BY demand_score
    ) as demand_percentile,
    -- Price multiplier trend
    CASE 
        WHEN LAG(dynamic_price / base_price) OVER (
            PARTITION BY restaurant_id 
            ORDER BY time_slot
        ) < (dynamic_price / base_price) THEN 'increasing'
        WHEN LAG(dynamic_price / base_price) OVER (
            PARTITION BY restaurant_id 
            ORDER BY time_slot
        ) > (dynamic_price / base_price) THEN 'decreasing'
        ELSE 'stable'
    END as price_trend,
    -- Peak hour pricing effectiveness
    CASE 
        WHEN HOUR(time_slot) BETWEEN 11 AND 14 OR HOUR(time_slot) BETWEEN 17 AND 21 THEN
            AVG(dynamic_price / base_price) OVER (
                PARTITION BY restaurant_id, 
                CASE 
                    WHEN HOUR(time_slot) BETWEEN 11 AND 14 OR HOUR(time_slot) BETWEEN 17 AND 21 
                    THEN 'peak' ELSE 'off_peak' 
                END
            )
        ELSE NULL
    END as peak_hour_price_multiplier,
    -- Revenue ranking among similar restaurants
    RANK() OVER (
        PARTITION BY restaurant_category 
        ORDER BY (dynamic_price * order_count) DESC
    ) as revenue_rank_in_category
FROM (
    SELECT 
        r.id as restaurant_id,
        r.name as restaurant_name,
        r.category as restaurant_category,
        dm.time_slot,
        dm.demand_score,
        dm.order_count,
        p.base_price,
        dp.dynamic_price,
        (dp.dynamic_price - p.base_price) as price_difference
    FROM restaurants r
    JOIN demand_metrics dm ON r.id = dm.restaurant_id
    JOIN products p ON r.id = p.restaurant_id
    JOIN dynamic_pricing_rules dpr ON r.id = dpr.restaurant_id
    CROSS JOIN LATERAL (
        SELECT calculate_dynamic_pricing(r.id, p.base_price) as dynamic_price
    ) dp
    WHERE dpr.is_active = TRUE
) pricing_data;
```

### The "Subscription Churn Analysis" Pattern
```sql
-- Subscription churn analysis with window functions
CREATE VIEW subscription_churn_analysis AS
SELECT 
    subscription_id,
    customer_id,
    subscription_plan,
    current_billing_cycle,
    total_billing_cycles,
    -- Days since last billing
    DATEDIFF(CURRENT_DATE, last_billing_date) as days_since_last_billing,
    -- Churn risk score (higher = more likely to churn)
    CASE 
        WHEN days_since_last_billing > 30 THEN 100
        WHEN days_since_last_billing > 15 THEN 75
        WHEN days_since_last_billing > 7 THEN 50
        ELSE 25
    END as churn_risk_score,
    -- Customer tenure (days since first billing)
    DATEDIFF(CURRENT_DATE, first_billing_date) as customer_tenure_days,
    -- Billing cycle completion rate
    (current_billing_cycle - 1) / NULLIF(total_billing_cycles, 0) * 100 as completion_rate,
    -- Payment failure rate
    (failed_billing_cycles / total_billing_cycles) * 100 as payment_failure_rate,
    -- Average billing amount trend
    CASE 
        WHEN LAG(avg_billing_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY billing_cycle_number
        ) < avg_billing_amount THEN 'increasing'
        WHEN LAG(avg_billing_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY billing_cycle_number
        ) > avg_billing_amount THEN 'decreasing'
        ELSE 'stable'
    END as billing_amount_trend,
    -- Customer segment rank
    RANK() OVER (
        PARTITION BY customer_segment 
        ORDER BY customer_tenure_days DESC
    ) as segment_tenure_rank,
    -- Churn prediction (based on historical patterns)
    CASE 
        WHEN payment_failure_rate > 20 THEN 'high_risk'
        WHEN days_since_last_billing > 15 THEN 'medium_risk'
        WHEN completion_rate < 50 THEN 'medium_risk'
        ELSE 'low_risk'
    END as churn_prediction,
    -- Revenue impact if customer churns
    avg_billing_amount * (total_billing_cycles - current_billing_cycle) as potential_revenue_loss
FROM (
    SELECT 
        s.subscription_id,
        s.customer_id,
        s.subscription_plan,
        s.current_billing_cycle,
        s.total_billing_cycles,
        s.last_billing_date,
        c.segment as customer_segment,
        MIN(sbc.billing_date) as first_billing_date,
        AVG(sbc.billing_amount) as avg_billing_amount,
        COUNT(CASE WHEN sbc.billing_status = 'failed' THEN 1 END) as failed_billing_cycles,
        COUNT(*) as total_billing_cycles,
        sbc.billing_cycle_number
    FROM subscriptions s
    JOIN customers c ON s.customer_id = c.id
    LEFT JOIN subscription_billing_cycles sbc ON s.subscription_id = sbc.subscription_id
    WHERE s.status = 'active'
    GROUP BY s.subscription_id, s.customer_id, s.subscription_plan, s.current_billing_cycle, 
             s.total_billing_cycles, s.last_billing_date, c.segment, sbc.billing_cycle_number
) subscription_metrics;
```

These window function patterns provide powerful analytical capabilities for ecommerce and quick commerce platforms, enabling real-time insights into customer behavior, product performance, inventory forecasting, delivery optimization, dynamic pricing effectiveness, and subscription management! 📊

### The "Advanced Window Functions for Ecommerce" Pattern
```sql
-- Advanced window functions for comprehensive ecommerce analytics
CREATE VIEW advanced_ecommerce_analytics AS
SELECT 
    customer_id,
    customer_name,
    total_orders,
    total_spent,
    avg_order_value,
    -- DENSE_RANK: No gaps in ranking (same rank for ties)
    DENSE_RANK() OVER (
        ORDER BY total_spent DESC
    ) as spending_dense_rank,
    -- ROW_NUMBER: Unique sequential numbers
    ROW_NUMBER() OVER (
        PARTITION BY customer_segment 
        ORDER BY total_spent DESC
    ) as segment_row_number,
    -- NTILE: Divide into buckets (e.g., quartiles, deciles)
    NTILE(4) OVER (
        ORDER BY total_spent DESC
    ) as spending_quartile,
    NTILE(10) OVER (
        ORDER BY total_spent DESC
    ) as spending_decile,
    -- FIRST_VALUE: First value in the window
    FIRST_VALUE(customer_name) OVER (
        PARTITION BY customer_segment 
        ORDER BY total_spent DESC
    ) as top_spender_in_segment,
    -- LAST_VALUE: Last value in the window
    LAST_VALUE(customer_name) OVER (
        PARTITION BY customer_segment 
        ORDER BY total_spent DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as lowest_spender_in_segment,
    -- NTH_VALUE: Nth value in the window
    NTH_VALUE(customer_name, 2) OVER (
        PARTITION BY customer_segment 
        ORDER BY total_spent DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as second_best_spender_in_segment,
    -- LEAD: Next value in the window
    LEAD(total_spent, 1) OVER (
        ORDER BY total_spent DESC
    ) as next_highest_spending,
    -- LAG: Previous value in the window
    LAG(total_spent, 1) OVER (
        ORDER BY total_spent DESC
    ) as previous_higher_spending,
    -- CUME_DIST: Cumulative distribution
    CUME_DIST() OVER (
        ORDER BY total_spent DESC
    ) as spending_percentile_rank,
    -- PERCENT_RANK: Percentage rank
    PERCENT_RANK() OVER (
        ORDER BY total_spent DESC
    ) as spending_percentage_rank
FROM customer_lifetime_value;
```

### The "Product Ranking and Segmentation" Pattern
```sql
-- Product ranking and segmentation using advanced window functions
CREATE VIEW product_ranking_analytics AS
SELECT 
    product_id,
    product_name,
    category_name,
    total_revenue,
    total_sales,
    avg_price,
    -- DENSE_RANK vs RANK comparison
    RANK() OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
    ) as category_rank,
    DENSE_RANK() OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
    ) as category_dense_rank,
    -- Product performance tiers (A, B, C, D)
    CASE 
        WHEN NTILE(4) OVER (
            PARTITION BY category_name 
            ORDER BY total_revenue DESC
        ) = 1 THEN 'A'
        WHEN NTILE(4) OVER (
            PARTITION BY category_name 
            ORDER BY total_revenue DESC
        ) = 2 THEN 'B'
        WHEN NTILE(4) OVER (
            PARTITION BY category_name 
            ORDER BY total_revenue DESC
        ) = 3 THEN 'C'
        ELSE 'D'
    END as performance_tier,
    -- Top product in each category
    FIRST_VALUE(product_name) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
    ) as category_leader,
    -- Revenue gap to category leader
    (FIRST_VALUE(total_revenue) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
    ) - total_revenue) as revenue_gap_to_leader,
    -- Revenue gap to next product
    (LEAD(total_revenue, 1) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
    ) - total_revenue) as revenue_gap_to_next,
    -- Revenue gap to previous product
    (total_revenue - LAG(total_revenue, 1) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
    )) as revenue_gap_from_previous,
    -- Product position in overall ranking
    ROW_NUMBER() OVER (
        ORDER BY total_revenue DESC
    ) as overall_position,
    -- Revenue percentile
    CUME_DIST() OVER (
        ORDER BY total_revenue DESC
    ) as revenue_percentile
FROM product_performance_analytics;
```

### The "Inventory Tier Management" Pattern
```sql
-- Inventory management using NTILE and ranking functions
CREATE VIEW inventory_tier_management AS
SELECT 
    product_variant_id,
    warehouse_id,
    current_stock,
    avg_daily_demand,
    days_until_stockout,
    -- Inventory priority tiers (1 = highest priority)
    NTILE(5) OVER (
        ORDER BY days_until_stockout ASC
    ) as inventory_priority_tier,
    -- Stockout risk ranking
    DENSE_RANK() OVER (
        ORDER BY days_until_stockout ASC
    ) as stockout_risk_rank,
    -- Demand urgency ranking within warehouse
    ROW_NUMBER() OVER (
        PARTITION BY warehouse_id 
        ORDER BY avg_daily_demand DESC
    ) as demand_urgency_rank,
    -- Reorder urgency (1 = most urgent)
    NTILE(3) OVER (
        PARTITION BY warehouse_id 
        ORDER BY days_until_stockout ASC
    ) as reorder_urgency_level,
    -- Stock level percentile within warehouse
    CUME_DIST() OVER (
        PARTITION BY warehouse_id 
        ORDER BY current_stock DESC
    ) as stock_level_percentile,
    -- Most critical product in each warehouse
    FIRST_VALUE(product_variant_id) OVER (
        PARTITION BY warehouse_id 
        ORDER BY days_until_stockout ASC
    ) as most_critical_product,
    -- Days until stockout gap to next product
    (LEAD(days_until_stockout, 1) OVER (
        PARTITION BY warehouse_id 
        ORDER BY days_until_stockout ASC
    ) - days_until_stockout) as stockout_gap_to_next
FROM inventory_forecasting
WHERE days_until_stockout IS NOT NULL;
```

### The "Driver Performance Tiers" Pattern
```sql
-- Driver performance analysis using advanced window functions
CREATE VIEW driver_performance_tiers AS
SELECT 
    driver_id,
    driver_name,
    total_deliveries,
    avg_delivery_time_minutes,
    on_time_percentage,
    -- Driver performance tiers (1 = best, 5 = needs improvement)
    NTILE(5) OVER (
        ORDER BY on_time_percentage DESC, avg_delivery_time_minutes ASC
    ) as performance_tier,
    -- Performance ranking with no gaps
    DENSE_RANK() OVER (
        ORDER BY on_time_percentage DESC, avg_delivery_time_minutes ASC
    ) as performance_rank,
    -- Top performer in each tier
    FIRST_VALUE(driver_name) OVER (
        PARTITION BY NTILE(5) OVER (
            ORDER BY on_time_percentage DESC, avg_delivery_time_minutes ASC
        )
        ORDER BY on_time_percentage DESC, avg_delivery_time_minutes ASC
    ) as tier_leader,
    -- Performance gap to tier leader
    (FIRST_VALUE(on_time_percentage) OVER (
        PARTITION BY NTILE(5) OVER (
            ORDER BY on_time_percentage DESC, avg_delivery_time_minutes ASC
        )
        ORDER BY on_time_percentage DESC, avg_delivery_time_minutes ASC
    ) - on_time_percentage) as performance_gap_to_leader,
    -- Driver efficiency percentile
    CUME_DIST() OVER (
        ORDER BY (total_deliveries / avg_delivery_time_minutes) DESC
    ) as efficiency_percentile,
    -- Delivery time ranking
    ROW_NUMBER() OVER (
        ORDER BY avg_delivery_time_minutes ASC
    ) as speed_rank,
    -- Performance trend (comparing to previous period)
    CASE 
        WHEN LAG(on_time_percentage) OVER (
            ORDER BY driver_id
        ) < on_time_percentage THEN 'improving'
        WHEN LAG(on_time_percentage) OVER (
            ORDER BY driver_id
        ) > on_time_percentage THEN 'declining'
        ELSE 'stable'
    END as performance_trend
FROM delivery_performance_analytics;
```

### The "Customer Segmentation with NTILE" Pattern
```sql
-- Customer segmentation using NTILE for RFM analysis
CREATE VIEW customer_rfm_segmentation AS
SELECT 
    customer_id,
    customer_name,
    total_orders,
    total_spent,
    days_since_last_order,
    -- Recency tiers (1 = most recent, 5 = least recent)
    NTILE(5) OVER (
        ORDER BY days_since_last_order ASC
    ) as recency_tier,
    -- Frequency tiers (1 = most frequent, 5 = least frequent)
    NTILE(5) OVER (
        ORDER BY total_orders DESC
    ) as frequency_tier,
    -- Monetary tiers (1 = highest spending, 5 = lowest spending)
    NTILE(5) OVER (
        ORDER BY total_spent DESC
    ) as monetary_tier,
    -- RFM Score (combination of all tiers)
    CONCAT(
        NTILE(5) OVER (ORDER BY days_since_last_order ASC),
        NTILE(5) OVER (ORDER BY total_orders DESC),
        NTILE(5) OVER (ORDER BY total_spent DESC)
    ) as rfm_score,
    -- Customer value tier (1 = highest value, 4 = lowest value)
    NTILE(4) OVER (
        ORDER BY total_spent DESC
    ) as value_tier,
    -- Top customer in each value tier
    FIRST_VALUE(customer_name) OVER (
        PARTITION BY NTILE(4) OVER (ORDER BY total_spent DESC)
        ORDER BY total_spent DESC
    ) as tier_champion,
    -- Customer ranking within value tier
    ROW_NUMBER() OVER (
        PARTITION BY NTILE(4) OVER (ORDER BY total_spent DESC)
        ORDER BY total_spent DESC
    ) as tier_position,
    -- Spending gap to tier champion
    (FIRST_VALUE(total_spent) OVER (
        PARTITION BY NTILE(4) OVER (ORDER BY total_spent DESC)
        ORDER BY total_spent DESC
    ) - total_spent) as spending_gap_to_champion,
    -- Customer lifetime value percentile
    CUME_DIST() OVER (
        ORDER BY total_spent DESC
    ) as clv_percentile
FROM customer_lifetime_value;
```

### The "Dynamic Pricing Tiers" Pattern
```sql
-- Dynamic pricing analysis using advanced window functions
CREATE VIEW dynamic_pricing_tiers AS
SELECT 
    restaurant_id,
    restaurant_name,
    base_price,
    dynamic_price,
    demand_score,
    -- Price sensitivity tiers (1 = most sensitive, 5 = least sensitive)
    NTILE(5) OVER (
        ORDER BY ABS(price_elasticity) DESC
    ) as price_sensitivity_tier,
    -- Demand percentile ranking
    PERCENT_RANK() OVER (
        ORDER BY demand_score DESC
    ) as demand_percentile_rank,
    -- Revenue performance ranking
    DENSE_RANK() OVER (
        ORDER BY additional_revenue DESC
    ) as revenue_performance_rank,
    -- Top performer in each sensitivity tier
    FIRST_VALUE(restaurant_name) OVER (
        PARTITION BY NTILE(5) OVER (ORDER BY ABS(price_elasticity) DESC)
        ORDER BY additional_revenue DESC
    ) as tier_top_performer,
    -- Price multiplier ranking
    ROW_NUMBER() OVER (
        ORDER BY (dynamic_price / base_price) DESC
    ) as price_multiplier_rank,
    -- Revenue gap to tier leader
    (FIRST_VALUE(additional_revenue) OVER (
        PARTITION BY NTILE(5) OVER (ORDER BY ABS(price_elasticity) DESC)
        ORDER BY additional_revenue DESC
    ) - additional_revenue) as revenue_gap_to_leader,
    -- Demand trend ranking
    CASE 
        WHEN LAG(demand_score) OVER (
            PARTITION BY restaurant_id 
            ORDER BY time_slot
        ) < demand_score THEN 'increasing'
        WHEN LAG(demand_score) OVER (
            PARTITION BY restaurant_id 
            ORDER BY time_slot
        ) > demand_score THEN 'decreasing'
        ELSE 'stable'
    END as demand_trend,
    -- Price effectiveness percentile
    CUME_DIST() OVER (
        ORDER BY (additional_revenue / base_price) DESC
    ) as price_effectiveness_percentile
FROM dynamic_pricing_analytics;
```

### The "Subscription Cohort Analysis" Pattern
```sql
-- Subscription cohort analysis using advanced window functions
CREATE VIEW subscription_cohort_analysis AS
SELECT 
    subscription_id,
    customer_id,
    subscription_plan,
    current_billing_cycle,
    customer_tenure_days,
    churn_risk_score,
    -- Cohort tiers based on tenure (1 = newest, 5 = oldest)
    NTILE(5) OVER (
        ORDER BY customer_tenure_days ASC
    ) as cohort_tier,
    -- Churn risk ranking within cohort
    DENSE_RANK() OVER (
        PARTITION BY NTILE(5) OVER (ORDER BY customer_tenure_days ASC)
        ORDER BY churn_risk_score DESC
    ) as churn_risk_rank_in_cohort,
    -- Top retention performer in each cohort
    FIRST_VALUE(customer_id) OVER (
        PARTITION BY NTILE(5) OVER (ORDER BY customer_tenure_days ASC)
        ORDER BY churn_risk_score ASC
    ) as cohort_retention_champion,
    -- Subscription value ranking
    ROW_NUMBER() OVER (
        ORDER BY avg_billing_amount DESC
    ) as subscription_value_rank,
    -- Billing cycle completion ranking
    PERCENT_RANK() OVER (
        ORDER BY completion_rate DESC
    ) as completion_percentile,
    -- Risk tier classification
    CASE 
        WHEN NTILE(4) OVER (ORDER BY churn_risk_score DESC) = 1 THEN 'high_risk'
        WHEN NTILE(4) OVER (ORDER BY churn_risk_score DESC) = 2 THEN 'medium_high_risk'
        WHEN NTILE(4) OVER (ORDER BY churn_risk_score DESC) = 3 THEN 'medium_low_risk'
        ELSE 'low_risk'
    END as risk_tier,
    -- Revenue impact ranking
    DENSE_RANK() OVER (
        ORDER BY potential_revenue_loss DESC
    ) as revenue_impact_rank,
    -- Cohort retention leader
    FIRST_VALUE(customer_id) OVER (
        PARTITION BY NTILE(5) OVER (ORDER BY customer_tenure_days ASC)
        ORDER BY completion_rate DESC
    ) as cohort_retention_leader
FROM subscription_churn_analysis;
```

These advanced window function patterns provide comprehensive analytical capabilities for ecommerce and quick commerce platforms, covering all major window functions including `DENSE_RANK()`, `NTILE()`, `FIRST_VALUE()`, `LAST_VALUE()`, `NTH_VALUE()`, `ROW_NUMBER()`, `LEAD()`, `LAG()`, `CUME_DIST()`, and `PERCENT_RANK()`! 📊

### The "Complete Window Functions Reference" Pattern
```sql
-- Comprehensive window functions demonstration for ecommerce
CREATE VIEW complete_window_functions_demo AS
SELECT 
    customer_id,
    customer_name,
    total_spent,
    total_orders,
    avg_order_value,
    days_since_last_order,
    
    -- ROW_NUMBER: Unique sequential numbers (no ties)
    ROW_NUMBER() OVER (
        ORDER BY total_spent DESC
    ) as row_num,
    
    -- RANK: Ranking with gaps for ties
    RANK() OVER (
        ORDER BY total_spent DESC
    ) as rank_with_gaps,
    
    -- DENSE_RANK: Ranking without gaps for ties
    DENSE_RANK() OVER (
        ORDER BY total_spent DESC
    ) as dense_rank_no_gaps,
    
    -- NTILE: Divide into buckets
    NTILE(4) OVER (
        ORDER BY total_spent DESC
    ) as quartile_bucket,
    NTILE(10) OVER (
        ORDER BY total_spent DESC
    ) as decile_bucket,
    
    -- LAG: Previous value (default offset = 1)
    LAG(total_spent, 1) OVER (
        ORDER BY total_spent DESC
    ) as previous_spending,
    LAG(total_spent, 2) OVER (
        ORDER BY total_spent DESC
    ) as two_positions_back,
    
    -- LEAD: Next value (default offset = 1)
    LEAD(total_spent, 1) OVER (
        ORDER BY total_spent DESC
    ) as next_spending,
    LEAD(total_spent, 3) OVER (
        ORDER BY total_spent DESC
    ) as three_positions_ahead,
    
    -- FIRST_VALUE: First value in window
    FIRST_VALUE(customer_name) OVER (
        ORDER BY total_spent DESC
    ) as top_spender_name,
    FIRST_VALUE(total_spent) OVER (
        ORDER BY total_spent DESC
    ) as top_spending_amount,
    
    -- LAST_VALUE: Last value in window (requires ROWS clause)
    LAST_VALUE(customer_name) OVER (
        ORDER BY total_spent DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as bottom_spender_name,
    
    -- NTH_VALUE: Nth value in window
    NTH_VALUE(customer_name, 2) OVER (
        ORDER BY total_spent DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as second_best_spender,
    NTH_VALUE(total_spent, 5) OVER (
        ORDER BY total_spent DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as fifth_best_spending,
    
    -- CUME_DIST: Cumulative distribution (0 to 1)
    CUME_DIST() OVER (
        ORDER BY total_spent DESC
    ) as cumulative_distribution,
    
    -- PERCENT_RANK: Percentage rank (0 to 1)
    PERCENT_RANK() OVER (
        ORDER BY total_spent DESC
    ) as percentage_rank,
    
    -- Aggregation functions with window
    SUM(total_spent) OVER (
        ORDER BY total_spent DESC
        ROWS UNBOUNDED PRECEDING
    ) as cumulative_spending,
    
    AVG(total_spent) OVER (
        ORDER BY total_spent DESC
        ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
    ) as moving_avg_5_rows,
    
    COUNT(*) OVER (
        ORDER BY total_spent DESC
        ROWS UNBOUNDED PRECEDING
    ) as running_count,
    
    MAX(total_spent) OVER (
        ORDER BY total_spent DESC
        ROWS UNBOUNDED PRECEDING
    ) as running_max,
    
    MIN(total_spent) OVER (
        ORDER BY total_spent DESC
        ROWS UNBOUNDED PRECEDING
    ) as running_min
    
FROM customer_lifetime_value
ORDER BY total_spent DESC;
```

### The "Window Functions Comparison" Pattern
```sql
-- Demonstrating differences between ranking functions
CREATE VIEW ranking_functions_comparison AS
SELECT 
    customer_id,
    customer_name,
    total_spent,
    
    -- ROW_NUMBER: Always unique, no ties
    ROW_NUMBER() OVER (ORDER BY total_spent DESC) as row_number,
    
    -- RANK: Same rank for ties, gaps in sequence
    RANK() OVER (ORDER BY total_spent DESC) as rank_with_gaps,
    
    -- DENSE_RANK: Same rank for ties, no gaps
    DENSE_RANK() OVER (ORDER BY total_spent DESC) as dense_rank,
    
    -- Example with ties:
    -- If customers have same total_spent:
    -- ROW_NUMBER: 1, 2, 3, 4, 5
    -- RANK: 1, 1, 3, 4, 5 (gaps)
    -- DENSE_RANK: 1, 1, 2, 3, 4 (no gaps)
    
    -- NTILE examples
    NTILE(2) OVER (ORDER BY total_spent DESC) as binary_split,
    NTILE(4) OVER (ORDER BY total_spent DESC) as quartiles,
    NTILE(5) OVER (ORDER BY total_spent DESC) as quintiles,
    NTILE(10) OVER (ORDER BY total_spent DESC) as deciles,
    NTILE(100) OVER (ORDER BY total_spent DESC) as percentiles
    
FROM customer_lifetime_value
ORDER BY total_spent DESC;
```

### The "LAG and LEAD Patterns" Pattern
```sql
-- Advanced LAG and LEAD usage patterns
CREATE VIEW lag_lead_patterns AS
SELECT 
    customer_id,
    customer_name,
    order_date,
    order_amount,
    
    -- LAG patterns
    LAG(order_amount, 1) OVER (
        PARTITION BY customer_id 
        ORDER BY order_date
    ) as previous_order_amount,
    
    LAG(order_amount, 1, 0) OVER (
        PARTITION BY customer_id 
        ORDER BY order_date
    ) as previous_order_amount_default_0,
    
    LAG(order_amount, 2) OVER (
        PARTITION BY customer_id 
        ORDER BY order_date
    ) as two_orders_back,
    
    LAG(order_date, 1) OVER (
        PARTITION BY customer_id 
        ORDER BY order_date
    ) as previous_order_date,
    
    -- LEAD patterns
    LEAD(order_amount, 1) OVER (
        PARTITION BY customer_id 
        ORDER BY order_date
    ) as next_order_amount,
    
    LEAD(order_amount, 1, 0) OVER (
        PARTITION BY customer_id 
        ORDER BY order_date
    ) as next_order_amount_default_0,
    
    LEAD(order_date, 1) OVER (
        PARTITION BY customer_id 
        ORDER BY order_date
    ) as next_order_date,
    
    -- Trend analysis
    CASE 
        WHEN LAG(order_amount, 1) OVER (
            PARTITION BY customer_id 
            ORDER BY order_date
        ) < order_amount THEN 'increasing'
        WHEN LAG(order_amount, 1) OVER (
            PARTITION BY customer_id 
            ORDER BY order_date
        ) > order_amount THEN 'decreasing'
        ELSE 'stable'
    END as spending_trend,
    
    -- Growth rate calculation
    CASE 
        WHEN LAG(order_amount, 1) OVER (
            PARTITION BY customer_id 
            ORDER BY order_date
        ) > 0 THEN 
            ((order_amount - LAG(order_amount, 1) OVER (
                PARTITION BY customer_id 
                ORDER BY order_date
            )) / LAG(order_amount, 1) OVER (
                PARTITION BY customer_id 
                ORDER BY order_date
            )) * 100
        ELSE NULL
    END as growth_percentage,
    
    -- Days between orders
    DATEDIFF(
        order_date,
        LAG(order_date, 1) OVER (
            PARTITION BY customer_id 
            ORDER BY order_date
        )
    ) as days_since_previous_order
    
FROM (
    SELECT 
        c.id as customer_id,
        c.name as customer_name,
        o.created_at as order_date,
        o.total_amount as order_amount
    FROM customers c
    JOIN orders o ON c.id = o.customer_id
    WHERE o.status = 'completed'
    ORDER BY c.id, o.created_at
) customer_orders;
```

### The "Value Functions Deep Dive" Pattern
```sql
-- Deep dive into FIRST_VALUE, LAST_VALUE, and NTH_VALUE
CREATE VIEW value_functions_deep_dive AS
SELECT 
    category_name,
    product_name,
    total_revenue,
    
    -- FIRST_VALUE examples
    FIRST_VALUE(product_name) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
    ) as category_leader,
    
    FIRST_VALUE(total_revenue) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
    ) as category_leader_revenue,
    
    FIRST_VALUE(product_name) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue ASC
    ) as category_laggard,
    
    -- LAST_VALUE examples (requires ROWS clause)
    LAST_VALUE(product_name) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as category_lowest,
    
    LAST_VALUE(total_revenue) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as category_lowest_revenue,
    
    -- NTH_VALUE examples
    NTH_VALUE(product_name, 2) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as category_second_best,
    
    NTH_VALUE(product_name, 3) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as category_third_best,
    
    NTH_VALUE(total_revenue, 5) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as category_fifth_best_revenue,
    
    -- Revenue gap to leader
    (FIRST_VALUE(total_revenue) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
    ) - total_revenue) as revenue_gap_to_leader,
    
    -- Revenue gap to second best
    (NTH_VALUE(total_revenue, 2) OVER (
        PARTITION BY category_name 
        ORDER BY total_revenue DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) - total_revenue) as revenue_gap_to_second
    
FROM product_performance_analytics
ORDER BY category_name, total_revenue DESC;
```

### The "Distribution Functions" Pattern
```sql
-- CUME_DIST and PERCENT_RANK usage patterns
CREATE VIEW distribution_functions AS
SELECT 
    customer_id,
    customer_name,
    total_spent,
    
    -- CUME_DIST: Cumulative distribution (0 to 1)
    CUME_DIST() OVER (
        ORDER BY total_spent DESC
    ) as cumulative_distribution,
    
    -- Convert to percentage
    (CUME_DIST() OVER (
        ORDER BY total_spent DESC
    ) * 100) as cumulative_percentage,
    
    -- PERCENT_RANK: Percentage rank (0 to 1)
    PERCENT_RANK() OVER (
        ORDER BY total_spent DESC
    ) as percentage_rank,
    
    -- Convert to percentage
    (PERCENT_RANK() OVER (
        ORDER BY total_spent DESC
    ) * 100) as percentage_rank_percent,
    
    -- Customer segment based on spending distribution
    CASE 
        WHEN CUME_DIST() OVER (ORDER BY total_spent DESC) <= 0.1 THEN 'Top 10%'
        WHEN CUME_DIST() OVER (ORDER BY total_spent DESC) <= 0.25 THEN 'Top 25%'
        WHEN CUME_DIST() OVER (ORDER BY total_spent DESC) <= 0.5 THEN 'Top 50%'
        WHEN CUME_DIST() OVER (ORDER BY total_spent DESC) <= 0.75 THEN 'Top 75%'
        ELSE 'Bottom 25%'
    END as spending_segment,
    
    -- Percentile rank interpretation
    CASE 
        WHEN PERCENT_RANK() OVER (ORDER BY total_spent DESC) <= 0.01 THEN 'Top 1%'
        WHEN PERCENT_RANK() OVER (ORDER BY total_spent DESC) <= 0.05 THEN 'Top 5%'
        WHEN PERCENT_RANK() OVER (ORDER BY total_spent DESC) <= 0.1 THEN 'Top 10%'
        WHEN PERCENT_RANK() OVER (ORDER BY total_spent DESC) <= 0.25 THEN 'Top 25%'
        ELSE 'Below Top 25%'
    END as percentile_segment
    
FROM customer_lifetime_value
ORDER BY total_spent DESC;
```

This comprehensive reference covers ALL MySQL window functions with practical ecommerce examples, including the complete syntax and usage patterns for `ROW_NUMBER()`, `RANK()`, `DENSE_RANK()`, `NTILE()`, `LAG()`, `LEAD()`, `FIRST_VALUE()`, `LAST_VALUE()`, `NTH_VALUE()`, `CUME_DIST()`, and `PERCENT_RANK()`! 📊
```
