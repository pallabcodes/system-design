-- MySQL DDL (Data Definition Language) Schema Design Examples
-- Comprehensive examples of table creation, constraints, indexes, and schema evolution
-- Adapted for MySQL with InnoDB engine and MySQL-specific features

-- ===========================================
-- BASIC TABLE CREATION PATTERNS
-- ===========================================

-- Simple table with auto-increment primary key
CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE = InnoDB;

-- Table with UUID primary key (MySQL 8.0+)
CREATE TABLE products (
    product_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    product_name VARCHAR(255) NOT NULL,
    sku VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL CHECK (price > 0),
    stock_quantity INT DEFAULT 0 CHECK (stock_quantity >= 0),
    category_id INT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_products_category (category_id),
    INDEX idx_products_active (is_active),
    INDEX idx_products_price (price),
    FULLTEXT INDEX ft_products_name_desc (product_name, description)
) ENGINE = InnoDB;

-- ===========================================
-- ADVANCED CONSTRAINTS AND RELATIONSHIPS
-- =========================================--

-- Categories table with self-referencing foreign key
CREATE TABLE categories (
    category_id INT PRIMARY KEY AUTO_INCREMENT,
    category_name VARCHAR(100) NOT NULL,
    parent_category_id INT NULL,
    category_path VARCHAR(1000) GENERATED ALWAYS AS (
        CASE
            WHEN parent_category_id IS NULL THEN CONCAT('/', category_id)
            ELSE CONCAT('/', category_id)  -- Would need trigger for full path
        END
    ) STORED,
    is_active BOOLEAN DEFAULT TRUE,
    sort_order INT DEFAULT 0,

    FOREIGN KEY (parent_category_id) REFERENCES categories(category_id) ON DELETE SET NULL,
    UNIQUE KEY unique_category_name_parent (category_name, parent_category_id),
    INDEX idx_categories_parent (parent_category_id),
    INDEX idx_categories_active (is_active, sort_order)
) ENGINE = InnoDB;

-- Orders table with complex relationships
CREATE TABLE orders (
    order_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    user_id CHAR(36) NOT NULL,
    order_number VARCHAR(20) UNIQUE NOT NULL,
    order_status ENUM('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled') DEFAULT 'pending',

    -- Billing address
    billing_address_line_1 VARCHAR(255) NOT NULL,
    billing_address_line_2 VARCHAR(255),
    billing_city VARCHAR(100) NOT NULL,
    billing_state VARCHAR(50) NOT NULL,
    billing_postal_code VARCHAR(20) NOT NULL,
    billing_country VARCHAR(50) DEFAULT 'USA',

    -- Shipping address (can be different from billing)
    shipping_address_line_1 VARCHAR(255),
    shipping_address_line_2 VARCHAR(255),
    shipping_city VARCHAR(100),
    shipping_state VARCHAR(50),
    shipping_postal_code VARCHAR(20),
    shipping_country VARCHAR(50),

    -- Order totals (calculated fields)
    subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
    tax_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    shipping_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_amount DECIMAL(10,2) GENERATED ALWAYS AS (subtotal + tax_amount + shipping_amount - discount_amount) STORED,

    -- Payment info
    payment_method ENUM('credit_card', 'paypal', 'bank_transfer', 'cash_on_delivery') DEFAULT 'credit_card',
    payment_status ENUM('pending', 'paid', 'failed', 'refunded') DEFAULT 'pending',

    -- Dates
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    shipped_date TIMESTAMP NULL,
    delivered_date TIMESTAMP NULL,
    estimated_delivery_date DATE,

    -- Notes and metadata
    customer_notes TEXT,
    internal_notes TEXT,
    order_metadata JSON DEFAULT ('{}'),

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_orders_user (user_id),
    INDEX idx_orders_status (order_status),
    INDEX idx_orders_date (order_date DESC),
    INDEX idx_orders_total (total_amount),
    INDEX idx_orders_payment (payment_status),
    INDEX idx_orders_number (order_number)
) ENGINE = InnoDB;

-- ===========================================
-- COMPLEX DATA TYPES AND STRUCTURES
-- =========================================--

-- Products with JSON specifications and inventory tracking
CREATE TABLE product_inventory (
    inventory_id INT PRIMARY KEY AUTO_INCREMENT,
    product_id CHAR(36) NOT NULL,
    warehouse_location VARCHAR(50) NOT NULL,
    batch_number VARCHAR(50),
    manufacturing_date DATE,
    expiry_date DATE,

    -- Quantity tracking
    quantity_on_hand INT NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    quantity_reserved INT NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    quantity_available INT GENERATED ALWAYS AS (quantity_on_hand - quantity_reserved) STORED,

    -- Cost tracking
    unit_cost DECIMAL(8,2),
    landed_cost DECIMAL(8,2),  -- Includes shipping, duties, etc.

    -- Quality and condition
    quality_status ENUM('new', 'refurbished', 'used', 'damaged') DEFAULT 'new',
    condition_notes TEXT,

    -- Location tracking (spatial)
    warehouse_lat DECIMAL(10,8),
    warehouse_lng DECIMAL(11,8),
    warehouse_location_point POINT AS (POINT(warehouse_lng, warehouse_lat)) STORED,

    -- Metadata
    last_inventory_count TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    inventory_metadata JSON DEFAULT ('{}'),

    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE,
    UNIQUE KEY unique_product_warehouse (product_id, warehouse_location),

    INDEX idx_inventory_product (product_id),
    INDEX idx_inventory_location (warehouse_location),
    INDEX idx_inventory_available (quantity_available),
    INDEX idx_inventory_expiry (expiry_date),
    SPATIAL INDEX idx_inventory_location_point (warehouse_location_point)
) ENGINE = InnoDB;

-- ===========================================
-- TEMPORAL AND AUDIT TABLES
-- =========================================--

-- User sessions with temporal validity
CREATE TABLE user_sessions (
    session_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    user_id CHAR(36) NOT NULL,
    session_token VARCHAR(255) UNIQUE NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,

    -- Temporal validity
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Session metadata
    is_active BOOLEAN DEFAULT TRUE,
    device_type ENUM('mobile', 'tablet', 'desktop', 'other') DEFAULT 'desktop',
    location_data JSON DEFAULT ('{}'),

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_sessions_user (user_id),
    INDEX idx_sessions_token (session_token),
    INDEX idx_sessions_active (is_active),
    INDEX idx_sessions_expires (expires_at),
    INDEX idx_sessions_last_activity (last_activity)
) ENGINE = InnoDB;

-- Audit trail table
CREATE TABLE audit_log (
    audit_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    table_name VARCHAR(100) NOT NULL,
    record_id VARCHAR(36) NOT NULL,
    operation ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    old_values JSON,
    new_values JSON,
    changed_by VARCHAR(255),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    connection_id INT DEFAULT CONNECTION_ID(),

    INDEX idx_audit_table_record (table_name, record_id),
    INDEX idx_audit_changed_at (changed_at DESC),
    INDEX idx_audit_operation (operation),
    INDEX idx_audit_changed_by (changed_by)
) ENGINE = InnoDB;

-- ===========================================
-- POLYMORPHIC RELATIONSHIPS
-- =========================================--

-- Generic comments system (supports comments on any entity)
CREATE TABLE comments (
    comment_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    comment_text TEXT NOT NULL,

    -- Polymorphic relationship (can comment on any entity)
    entity_type ENUM('product', 'order', 'user', 'category') NOT NULL,
    entity_id CHAR(36) NOT NULL,

    -- Author information
    author_id CHAR(36),  -- NULL for anonymous comments
    author_name VARCHAR(255),  -- For anonymous comments
    author_email VARCHAR(255),  -- For anonymous comments

    -- Comment hierarchy
    parent_comment_id CHAR(36) NULL,

    -- Status and moderation
    is_approved BOOLEAN DEFAULT TRUE,
    is_spam BOOLEAN DEFAULT FALSE,
    rating INT DEFAULT 0 CHECK (rating >= -1 AND rating <= 5),  -- -1 for flagged

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ip_address VARCHAR(45),
    user_agent TEXT,

    FOREIGN KEY (author_id) REFERENCES users(user_id) ON DELETE SET NULL,
    FOREIGN KEY (parent_comment_id) REFERENCES comments(comment_id) ON DELETE CASCADE,

    INDEX idx_comments_entity (entity_type, entity_id),
    INDEX idx_comments_author (author_id),
    INDEX idx_comments_parent (parent_comment_id),
    INDEX idx_comments_approved (is_approved),
    INDEX idx_comments_created (created_at),
    FULLTEXT INDEX ft_comments_text (comment_text)
) ENGINE = InnoDB;

-- ===========================================
-- SCHEMA EVOLUTION EXAMPLES
-- =========================================--

-- Add new columns with defaults
ALTER TABLE users
ADD COLUMN phone VARCHAR(20) NULL,
ADD COLUMN date_of_birth DATE NULL,
ADD COLUMN preferences JSON DEFAULT ('{}');

-- Add constraints after data exists
ALTER TABLE users
ADD CONSTRAINT chk_age CHECK (date_of_birth IS NULL OR date_of_birth <= CURDATE()),
ADD CONSTRAINT chk_phone_format CHECK (phone IS NULL OR phone REGEXP '^\\+?[0-9\\s\\-\\(\\)]+$');

-- Add indexes for performance
ALTER TABLE users
ADD INDEX idx_users_phone (phone),
ADD INDEX idx_users_dob (date_of_birth);

-- Create a view for user profiles
CREATE VIEW user_profiles AS
SELECT
    u.user_id,
    u.username,
    u.email,
    u.phone,
    u.date_of_birth,
    TIMESTAMPDIFF(YEAR, u.date_of_birth, CURDATE()) as age,
    u.preferences,
    u.created_at,
    u.updated_at
FROM users u
WHERE u.is_active = TRUE;

-- ===========================================
-- PARTITIONING EXAMPLES
-- =========================================--

-- Partition orders by year for performance
ALTER TABLE orders
PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Partition audit log by month
ALTER TABLE audit_log
PARTITION BY RANGE (YEAR(changed_at) * 100 + MONTH(changed_at)) (
    PARTITION p2024_01 VALUES LESS THAN (202401),
    PARTITION p2024_02 VALUES LESS THAN (202402),
    PARTITION p2024_03 VALUES LESS THAN (202403),
    PARTITION p2024_04 VALUES LESS THAN (202404),
    PARTITION p2024_05 VALUES LESS THAN (202405),
    PARTITION p2024_06 VALUES LESS THAN (202406),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- ===========================================
-- TRIGGERS FOR AUTOMATION
-- =========================================--

DELIMITER ;;

-- Audit trigger for users table
CREATE TRIGGER audit_users_trigger AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, operation, new_values, changed_by)
    VALUES ('users', NEW.user_id, 'INSERT', JSON_OBJECT(
        'username', NEW.username,
        'email', NEW.email,
        'created_at', NEW.created_at
    ), USER());
END;;

-- Audit trigger for users updates
CREATE TRIGGER audit_users_update_trigger AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, operation, old_values, new_values, changed_by)
    VALUES ('users', NEW.user_id, 'UPDATE', JSON_OBJECT(
        'username', OLD.username,
        'email', OLD.email
    ), JSON_OBJECT(
        'username', NEW.username,
        'email', NEW.email
    ), USER());
END;;

-- Update inventory when orders are placed (simplified)
CREATE TRIGGER update_inventory_on_order AFTER INSERT ON orders
FOR EACH ROW
BEGIN
    -- This would typically involve order_items table
    -- For demo purposes, just logging
    INSERT INTO audit_log (table_name, record_id, operation, new_values, changed_by)
    VALUES ('orders', NEW.order_id, 'INSERT', JSON_OBJECT(
        'user_id', NEW.user_id,
        'total_amount', NEW.total_amount,
        'order_date', NEW.order_date
    ), USER());
END;;

DELIMITER ;

-- ===========================================
-- STORED PROCEDURES FOR DDL OPERATIONS
-- =========================================--

DELIMITER ;;

-- Create table with audit triggers automatically
CREATE PROCEDURE create_auditable_table(
    IN table_name VARCHAR(100),
    IN table_definition TEXT
)
BEGIN
    DECLARE create_sql TEXT;
    DECLARE audit_trigger_sql TEXT;

    -- Create the main table
    SET @create_sql = CONCAT('CREATE TABLE `', table_name, '` (', table_definition, ') ENGINE = InnoDB');
    PREPARE stmt FROM @create_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    -- Create audit table
    SET @audit_sql = CONCAT('
        CREATE TABLE `', table_name, '_audit` (
            audit_id BIGINT PRIMARY KEY AUTO_INCREMENT,
            record_id VARCHAR(36) NOT NULL,
            operation ENUM(\'INSERT\', \'UPDATE\', \'DELETE\') NOT NULL,
            old_values JSON,
            new_values JSON,
            changed_by VARCHAR(255),
            changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_audit_record (record_id),
            INDEX idx_audit_operation (operation)
        ) ENGINE = InnoDB');
    PREPARE stmt2 FROM @audit_sql;
    EXECUTE stmt2;
    DEALLOCATE PREPARE stmt2;

    -- Create audit triggers (simplified - would need more complex logic for real implementation)
    SET @trigger_sql = CONCAT('
        CREATE TRIGGER `trg_', table_name, '_audit`
        AFTER INSERT ON `', table_name, '`
        FOR EACH ROW
        BEGIN
            INSERT INTO `', table_name, '_audit` (record_id, operation, new_values, changed_by)
            VALUES (NEW.id, \'INSERT\', JSON_OBJECT(\'created\', NOW()), USER());
        END');
    PREPARE stmt3 FROM @trigger_sql;
    EXECUTE stmt3;
    DEALLOCATE PREPARE stmt3;
END;;

-- Add column with proper defaults and constraints
CREATE PROCEDURE add_column_safely(
    IN target_table VARCHAR(100),
    IN column_name VARCHAR(100),
    IN column_definition VARCHAR(500),
    IN default_value VARCHAR(255)
)
BEGIN
    DECLARE column_exists INT DEFAULT 0;

    -- Check if column already exists
    SELECT COUNT(*) INTO column_exists
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = target_table
      AND COLUMN_NAME = column_name;

    IF column_exists = 0 THEN
        -- Add the column
        SET @add_sql = CONCAT('ALTER TABLE `', target_table, '` ADD COLUMN `', column_name, '` ', column_definition);
        PREPARE stmt FROM @add_sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        -- Set default value if provided
        IF default_value IS NOT NULL AND default_value != '' THEN
            SET @update_sql = CONCAT('UPDATE `', target_table, '` SET `', column_name, '` = ', default_value, ' WHERE `', column_name, '` IS NULL');
            PREPARE stmt2 FROM @update_sql;
            EXECUTE stmt2;
            DEALLOCATE PREPARE stmt2;
        END IF;

        -- Log the change
        INSERT INTO audit_log (table_name, operation, new_values, changed_by)
        VALUES (target_table, 'ALTER', JSON_OBJECT('action', 'add_column', 'column', column_name), USER());
    END IF;
END;;

DELIMITER ;

-- ===========================================
-- INDEXING STRATEGIES FOR DDL
-- =========================================--

-- Create comprehensive indexes for e-commerce schema
CREATE INDEX idx_orders_user_status ON orders (user_id, order_status);
CREATE INDEX idx_orders_date_status ON orders (order_date DESC, order_status);
CREATE INDEX idx_orders_total ON orders (total_amount);
CREATE INDEX idx_products_category_price ON products (category_id, price DESC);
CREATE INDEX idx_products_search ON products (product_name, sku);
CREATE INDEX idx_inventory_product_location ON product_inventory (product_id, warehouse_location);
CREATE INDEX idx_comments_entity_created ON comments (entity_type, entity_id, created_at DESC);

-- ===========================================
-- CONSTRAINTS AND DATA VALIDATION
-- =========================================--

-- Add check constraints for data integrity
ALTER TABLE products
ADD CONSTRAINT chk_positive_price CHECK (price > 0),
ADD CONSTRAINT chk_non_negative_stock CHECK (stock_quantity >= 0),
ADD CONSTRAINT chk_sku_format CHECK (sku REGEXP '^[A-Z0-9-]+$');

ALTER TABLE orders
ADD CONSTRAINT chk_valid_dates CHECK (shipped_date IS NULL OR shipped_date >= order_date),
ADD CONSTRAINT chk_delivery_after_ship CHECK (delivered_date IS NULL OR delivered_date >= shipped_date);

-- ===========================================
-- USAGE EXAMPLES
-- =========================================--

/*
-- Create an auditable table
CALL create_auditable_table('customers',
    'id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
     name VARCHAR(255) NOT NULL,
     email VARCHAR(255) UNIQUE NOT NULL,
     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP'
);

-- Add column safely
CALL add_column_safely('users', 'marketing_opt_in', 'BOOLEAN DEFAULT FALSE', 'FALSE');

-- Check constraints ensure data integrity
INSERT INTO products (product_name, sku, price, stock_quantity) VALUES
('Laptop', 'LT-001', 999.99, 50),
('Mouse', 'MS-002', 25.99, 100);

-- Partitioning improves query performance on large datasets
-- Indexes optimize query performance
-- Triggers automate audit logging
-- Views provide simplified interfaces

This DDL schema design demonstrates:
- Proper table design with constraints and indexes
- UUID primary keys and auto-increment alternatives
- JSON data types for flexible metadata
- Generated columns for computed values
- Partitioning strategies for large tables
- Audit triggers for change tracking
- Stored procedures for automated DDL operations
- Comprehensive indexing strategies
- Data validation through constraints

The schema supports e-commerce functionality with proper relationships,
data integrity, and performance optimizations.
*/
