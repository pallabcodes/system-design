# Multi-Tenancy Database Patterns

Advanced multi-tenancy techniques used by SaaS companies like Atlassian, Salesforce, and Shopify.

## Database-Per-Tenant Pattern

### Tenant Isolation Strategy
```sql
-- Tenant registry
CREATE TABLE tenant_registry (
    tenant_id VARCHAR(36) PRIMARY KEY,
    tenant_name VARCHAR(100) NOT NULL,
    database_name VARCHAR(50) NOT NULL,
    status ENUM('active', 'suspended', 'deleted') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_status (status),
    INDEX idx_database (database_name)
);

-- Dynamic database creation
DELIMITER $$
CREATE PROCEDURE create_tenant_database(
    IN tenant_id VARCHAR(36),
    IN tenant_name VARCHAR(100)
)
BEGIN
    DECLARE db_name VARCHAR(50);
    SET db_name = CONCAT('tenant_', REPLACE(tenant_id, '-', '_'));
    
    -- Create database
    SET @sql = CONCAT('CREATE DATABASE ', db_name);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    -- Register tenant
    INSERT INTO tenant_registry (tenant_id, tenant_name, database_name)
    VALUES (tenant_id, tenant_name, db_name);
    
    -- Create tenant schema
    SET @sql = CONCAT('USE ', db_name);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    -- Create tenant tables (example)
    CREATE TABLE users (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        email VARCHAR(255) UNIQUE NOT NULL,
        name VARCHAR(100) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE projects (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        owner_id BIGINT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (owner_id) REFERENCES users(id)
    );
END$$
DELIMITER ;
```

## Schema-Per-Tenant Pattern

### Dynamic Schema Management
```sql
-- Tenant schemas
CREATE TABLE tenant_schemas (
    tenant_id VARCHAR(36) PRIMARY KEY,
    schema_name VARCHAR(50) NOT NULL,
    schema_version INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Schema creation procedure
DELIMITER $$
CREATE PROCEDURE create_tenant_schema(
    IN tenant_id VARCHAR(36)
)
BEGIN
    DECLARE schema_name VARCHAR(50);
    SET schema_name = CONCAT('tenant_', REPLACE(tenant_id, '-', '_'));
    
    -- Create schema
    SET @sql = CONCAT('CREATE SCHEMA ', schema_name);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    -- Register schema
    INSERT INTO tenant_schemas (tenant_id, schema_name)
    VALUES (tenant_id, schema_name);
    
    -- Create tables in tenant schema
    SET @sql = CONCAT('
        CREATE TABLE ', schema_name, '.users (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            email VARCHAR(255) UNIQUE NOT NULL,
            name VARCHAR(100) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;
```

## Row-Level Security (RLS) Pattern

### Tenant-Aware Tables
```sql
-- Base table with tenant isolation
CREATE TABLE users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_tenant_email (tenant_id, email),
    INDEX idx_tenant (tenant_id)
);

-- Tenant context table
CREATE TABLE tenant_context (
    session_id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    user_id BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    INDEX idx_tenant (tenant_id),
    INDEX idx_expires (expires_at)
);

-- RLS views
CREATE VIEW tenant_users AS
SELECT u.* 
FROM users u
JOIN tenant_context tc ON u.tenant_id = tc.tenant_id
WHERE tc.session_id = @session_id
AND tc.expires_at > NOW();

-- RLS stored procedures
DELIMITER $$
CREATE PROCEDURE get_tenant_users(
    IN session_id VARCHAR(36)
)
BEGIN
    DECLARE tenant_id VARCHAR(36);
    
    -- Get tenant from session
    SELECT tc.tenant_id INTO tenant_id
    FROM tenant_context tc
    WHERE tc.session_id = session_id
    AND tc.expires_at > NOW();
    
    IF tenant_id IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Invalid or expired session';
    END IF;
    
    -- Return tenant data
    SELECT * FROM users WHERE tenant_id = tenant_id;
END$$
DELIMITER ;
```

## Resource Pooling Strategy

### Connection Pooling by Tenant
```sql
-- Tenant resource limits
CREATE TABLE tenant_limits (
    tenant_id VARCHAR(36) PRIMARY KEY,
    max_connections INT DEFAULT 10,
    max_storage_gb DECIMAL(10,2) DEFAULT 1.0,
    max_users INT DEFAULT 100,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Connection tracking
CREATE TABLE active_connections (
    connection_id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    user_id BIGINT,
    connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_tenant (tenant_id),
    INDEX idx_last_activity (last_activity)
);

-- Connection limit check
DELIMITER $$
CREATE FUNCTION check_connection_limit(tenant_id VARCHAR(36)) 
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE current_connections INT;
    DECLARE max_connections INT;
    
    -- Get current connections
    SELECT COUNT(*) INTO current_connections
    FROM active_connections 
    WHERE tenant_id = tenant_id
    AND last_activity > DATE_SUB(NOW(), INTERVAL 5 MINUTE);
    
    -- Get limit
    SELECT max_connections INTO max_connections
    FROM tenant_limits 
    WHERE tenant_id = tenant_id;
    
    RETURN current_connections < max_connections;
END$$
DELIMITER ;
```

## Tenant Data Migration

### Cross-Tenant Data Operations
```sql
-- Tenant data export
DELIMITER $$
CREATE PROCEDURE export_tenant_data(
    IN tenant_id VARCHAR(36),
    IN export_path VARCHAR(255)
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE table_name VARCHAR(100);
    DECLARE table_cursor CURSOR FOR
        SELECT TABLE_NAME 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME LIKE 'tenant_%';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN table_cursor;
    
    read_loop: LOOP
        FETCH table_cursor INTO table_name;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Export table data
        SET @sql = CONCAT(
            'SELECT * FROM ', table_name, 
            ' WHERE tenant_id = "', tenant_id, '"',
            ' INTO OUTFILE "', export_path, '/', table_name, '.csv"',
            ' FIELDS TERMINATED BY "," ENCLOSED BY "\""',
            ' LINES TERMINATED BY "\n"'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END LOOP;
    
    CLOSE table_cursor;
END$$
DELIMITER ;
```

## Tenant Analytics & Billing

### Usage Tracking
```sql
-- Tenant usage metrics
CREATE TABLE tenant_usage (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    metric_name VARCHAR(50) NOT NULL,
    metric_value DECIMAL(15,2) NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_tenant_metric (tenant_id, metric_name),
    INDEX idx_recorded (recorded_at)
);

-- Usage aggregation
CREATE VIEW tenant_daily_usage AS
SELECT 
    tenant_id,
    DATE(recorded_at) as usage_date,
    metric_name,
    SUM(metric_value) as total_value,
    AVG(metric_value) as avg_value,
    MAX(metric_value) as peak_value
FROM tenant_usage
GROUP BY tenant_id, DATE(recorded_at), metric_name;

-- Billing calculation
DELIMITER $$
CREATE PROCEDURE calculate_tenant_bill(
    IN tenant_id VARCHAR(36),
    IN billing_month DATE
)
BEGIN
    DECLARE storage_cost DECIMAL(10,2);
    DECLARE user_cost DECIMAL(10,2);
    DECLARE total_cost DECIMAL(10,2);
    
    -- Calculate storage cost
    SELECT SUM(metric_value) * 0.10 INTO storage_cost
    FROM tenant_usage
    WHERE tenant_id = tenant_id
    AND metric_name = 'storage_gb'
    AND DATE_FORMAT(recorded_at, '%Y-%m') = DATE_FORMAT(billing_month, '%Y-%m');
    
    -- Calculate user cost
    SELECT MAX(metric_value) * 2.00 INTO user_cost
    FROM tenant_usage
    WHERE tenant_id = tenant_id
    AND metric_name = 'active_users'
    AND DATE_FORMAT(recorded_at, '%Y-%m') = DATE_FORMAT(billing_month, '%Y-%m');
    
    SET total_cost = COALESCE(storage_cost, 0) + COALESCE(user_cost, 0);
    
    -- Insert billing record
    INSERT INTO tenant_billing (tenant_id, billing_month, storage_cost, user_cost, total_cost)
    VALUES (tenant_id, billing_month, storage_cost, user_cost, total_cost);
    
    SELECT total_cost as bill_amount;
END$$
DELIMITER ;
```
