# Advanced Security Patterns & God Mode Techniques

Real-world security patterns, encryption strategies, and compliance techniques used by product engineers at PayPal, Stripe, financial institutions, and other security-critical companies.

## 🚀 Row-Level Security (RLS) Mastery

### The "Dynamic RLS" Pattern
```sql
-- Row-level security implementation
CREATE TABLE rls_policies (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    policy_name VARCHAR(100) NOT NULL,
    policy_type ENUM('select', 'insert', 'update', 'delete') NOT NULL,
    policy_condition TEXT NOT NULL,  -- SQL condition for the policy
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_policy (table_name, policy_name, policy_type),
    INDEX idx_table_type (table_name, policy_type, is_active)
);

-- User context for RLS
CREATE TABLE user_context (
    session_id VARCHAR(100) PRIMARY KEY,
    user_id BIGINT NOT NULL,
    tenant_id BIGINT NULL,
    role VARCHAR(50) NOT NULL,
    permissions JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    
    INDEX idx_user_session (user_id, session_id),
    INDEX idx_expires (expires_at)
);

-- RLS-enabled users table
CREATE TABLE users_rls (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    tenant_id BIGINT NOT NULL,
    role VARCHAR(50) NOT NULL,
    status ENUM('active', 'inactive', 'suspended') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_tenant_role (tenant_id, role),
    INDEX idx_email (email)
);

-- RLS view with dynamic filtering
CREATE VIEW users_secure AS
SELECT u.*
FROM users_rls u
WHERE EXISTS (
    SELECT 1 FROM user_context uc
    WHERE uc.session_id = @current_session_id
    AND uc.expires_at > NOW()
    AND (
        -- Admin can see all users
        uc.role = 'admin'
        OR 
        -- Users can only see users in their tenant
        (uc.role = 'user' AND u.tenant_id = uc.tenant_id)
        OR
        -- Users can see themselves
        (uc.role = 'user' AND u.id = uc.user_id)
    )
);

-- RLS policy application procedure
DELIMITER $$
CREATE PROCEDURE apply_rls_policies(
    IN table_name VARCHAR(100),
    IN operation_type VARCHAR(20)
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE policy_condition TEXT;
    
    DECLARE policy_cursor CURSOR FOR
        SELECT p.policy_condition
        FROM rls_policies p
        WHERE p.table_name = table_name
        AND p.policy_type = operation_type
        AND p.is_active = TRUE;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN policy_cursor;
    
    policy_loop: LOOP
        FETCH policy_cursor INTO policy_condition;
        IF done THEN
            LEAVE policy_loop;
        END IF;
        
        -- Apply policy condition (this would be integrated with query rewriting)
        SET @sql = CONCAT('SELECT * FROM ', table_name, ' WHERE ', policy_condition);
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END LOOP;
    
    CLOSE policy_cursor;
END$$
DELIMITER ;
```

### The "Multi-Tenant RLS" Pattern
```sql
-- Multi-tenant RLS with tenant isolation
CREATE TABLE tenant_users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    tenant_id BIGINT NOT NULL,
    access_level ENUM('owner', 'admin', 'user', 'readonly') NOT NULL,
    granted_by BIGINT NOT NULL,
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE,
    
    UNIQUE KEY uk_user_tenant (user_id, tenant_id),
    INDEX idx_tenant_access (tenant_id, access_level, is_active),
    INDEX idx_user_access (user_id, is_active)
);

-- Tenant-aware RLS view
CREATE VIEW tenant_secure_data AS
SELECT 
    td.*,
    tu.access_level
FROM tenant_data td
JOIN tenant_users tu ON td.tenant_id = tu.tenant_id
WHERE tu.user_id = @current_user_id
AND tu.is_active = TRUE
AND (tu.expires_at IS NULL OR tu.expires_at > NOW())
AND (
    -- Owners and admins can see all data in their tenant
    tu.access_level IN ('owner', 'admin')
    OR
    -- Users can only see data they created
    (tu.access_level = 'user' AND td.created_by = @current_user_id)
    OR
    -- Readonly users can only see public data
    (tu.access_level = 'readonly' AND td.is_public = TRUE)
);
```

## 🔐 Column-Level Encryption

### The "Transparent Encryption" Pattern
```sql
-- Encrypted data storage
CREATE TABLE encrypted_data (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    column_name VARCHAR(100) NOT NULL,
    record_id BIGINT NOT NULL,
    encrypted_value BLOB NOT NULL,
    encryption_key_id VARCHAR(100) NOT NULL,
    encryption_algorithm VARCHAR(50) DEFAULT 'AES-256-GCM',
    iv BLOB NOT NULL,  -- Initialization vector
    auth_tag BLOB NOT NULL,  -- Authentication tag
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_encrypted_record (table_name, column_name, record_id),
    INDEX idx_encryption_key (encryption_key_id),
    INDEX idx_table_record (table_name, record_id)
);

-- Encryption key management
CREATE TABLE encryption_keys (
    key_id VARCHAR(100) PRIMARY KEY,
    key_type ENUM('master', 'data', 'backup') NOT NULL,
    key_material BLOB NOT NULL,
    key_version INT DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NULL,
    
    INDEX idx_key_type (key_type, is_active),
    INDEX idx_expires (expires_at)
);

-- Encryption/decryption procedures
DELIMITER $$
CREATE PROCEDURE encrypt_column_value(
    IN table_name VARCHAR(100),
    IN column_name VARCHAR(100),
    IN record_id BIGINT,
    IN plaintext_value TEXT,
    IN key_id VARCHAR(100)
)
BEGIN
    DECLARE encrypted_blob BLOB;
    DECLARE iv_blob BLOB;
    DECLARE auth_tag_blob BLOB;
    
    -- In a real implementation, this would use MySQL's encryption functions
    -- or integrate with external encryption libraries
    -- For demo purposes, we'll simulate encryption
    
    -- Generate IV (Initialization Vector)
    SET iv_blob = UNHEX(SHA2(UUID(), 256));
    
    -- Encrypt the value (simplified)
    SET encrypted_blob = AES_ENCRYPT(plaintext_value, key_id);
    
    -- Generate auth tag (simplified)
    SET auth_tag_blob = UNHEX(SHA2(CONCAT(plaintext_value, key_id), 256));
    
    -- Store encrypted data
    INSERT INTO encrypted_data (table_name, column_name, record_id, encrypted_value, encryption_key_id, iv, auth_tag)
    VALUES (table_name, column_name, record_id, encrypted_blob, key_id, iv_blob, auth_tag_blob)
    ON DUPLICATE KEY UPDATE
        encrypted_value = VALUES(encrypted_value),
        encryption_key_id = VALUES(encryption_key_id),
        iv = VALUES(iv),
        auth_tag = VALUES(auth_tag);
END$$

CREATE PROCEDURE decrypt_column_value(
    IN table_name VARCHAR(100),
    IN column_name VARCHAR(100),
    IN record_id BIGINT,
    IN key_id VARCHAR(100)
)
BEGIN
    DECLARE decrypted_value TEXT;
    
    -- Decrypt the value
    SELECT AES_DECRYPT(ed.encrypted_value, ed.encryption_key_id) INTO decrypted_value
    FROM encrypted_data ed
    WHERE ed.table_name = table_name
    AND ed.column_name = column_name
    AND ed.record_id = record_id
    AND ed.encryption_key_id = key_id;
    
    SELECT decrypted_value as decrypted_result;
END$$
DELIMITER ;
```

## 📋 Audit Logging & Compliance

### The "Comprehensive Audit Trail" Pattern
```sql
-- Audit trail for all data changes
CREATE TABLE audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    operation ENUM('INSERT', 'UPDATE', 'DELETE', 'SELECT') NOT NULL,
    record_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    session_id VARCHAR(100) NOT NULL,
    ip_address VARCHAR(45) NOT NULL,
    user_agent TEXT,
    old_values JSON NULL,
    new_values JSON NULL,
    changed_columns JSON NULL,
    query_text TEXT,
    execution_time_ms INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_table_operation (table_name, operation, created_at),
    INDEX idx_user_activity (user_id, created_at),
    INDEX idx_record_changes (table_name, record_id, created_at),
    INDEX idx_session (session_id, created_at)
);

-- Audit trigger for users table
DELIMITER $$
CREATE TRIGGER audit_users_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (
        table_name, operation, record_id, user_id, session_id, ip_address,
        new_values, query_text
    )
    VALUES (
        'users',
        'INSERT',
        NEW.id,
        @current_user_id,
        @current_session_id,
        @current_ip_address,
        JSON_OBJECT(
            'id', NEW.id,
            'email', NEW.email,
            'name', NEW.name,
            'status', NEW.status,
            'created_at', NEW.created_at
        ),
        @current_query_text
    );
END$$

CREATE TRIGGER audit_users_update
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    DECLARE changed_cols JSON;
    
    -- Determine which columns changed
    SET changed_cols = JSON_ARRAY();
    
    IF OLD.email != NEW.email THEN
        SET changed_cols = JSON_ARRAY_APPEND(changed_cols, '$', 'email');
    END IF;
    
    IF OLD.name != NEW.name THEN
        SET changed_cols = JSON_ARRAY_APPEND(changed_cols, '$', 'name');
    END IF;
    
    IF OLD.status != NEW.status THEN
        SET changed_cols = JSON_ARRAY_APPEND(changed_cols, '$', 'status');
    END IF;
    
    INSERT INTO audit_log (
        table_name, operation, record_id, user_id, session_id, ip_address,
        old_values, new_values, changed_columns, query_text
    )
    VALUES (
        'users',
        'UPDATE',
        NEW.id,
        @current_user_id,
        @current_session_id,
        @current_ip_address,
        JSON_OBJECT(
            'id', OLD.id,
            'email', OLD.email,
            'name', OLD.name,
            'status', OLD.status
        ),
        JSON_OBJECT(
            'id', NEW.id,
            'email', NEW.email,
            'name', NEW.name,
            'status', NEW.status
        ),
        changed_cols,
        @current_query_text
    );
END$$
DELIMITER ;
```

### The "Compliance Reporting" Pattern
```sql
-- Compliance reports
CREATE VIEW compliance_audit_report AS
SELECT 
    DATE(created_at) as audit_date,
    table_name,
    operation,
    COUNT(*) as operation_count,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT record_id) as unique_records,
    AVG(execution_time_ms) as avg_execution_time
FROM audit_log
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY DATE(created_at), table_name, operation
ORDER BY audit_date DESC, table_name, operation;

-- Data access report for compliance
CREATE VIEW data_access_report AS
SELECT 
    u.name as user_name,
    u.email as user_email,
    al.table_name,
    al.operation,
    COUNT(*) as access_count,
    MIN(al.created_at) as first_access,
    MAX(al.created_at) as last_access,
    COUNT(DISTINCT al.record_id) as unique_records_accessed
FROM audit_log al
JOIN users u ON al.user_id = u.id
WHERE al.created_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY u.id, al.table_name, al.operation
ORDER BY access_count DESC;
```

## 🎭 Data Masking & Anonymization

### The "Dynamic Data Masking" Pattern
```sql
-- Data masking configuration
CREATE TABLE data_masking_rules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    column_name VARCHAR(100) NOT NULL,
    masking_type ENUM('full', 'partial', 'hash', 'custom') NOT NULL,
    masking_pattern VARCHAR(255) NULL,  -- For custom masking
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_masking_rule (table_name, column_name),
    INDEX idx_table_column (table_name, column_name, is_active)
);

-- Masked data view
CREATE VIEW users_masked AS
SELECT 
    u.id,
    CASE 
        WHEN dmr.masking_type = 'full' THEN '***'
        WHEN dmr.masking_type = 'partial' THEN CONCAT(LEFT(u.email, 2), '***', RIGHT(u.email, 4))
        WHEN dmr.masking_type = 'hash' THEN SHA2(u.email, 256)
        ELSE u.email
    END as email,
    CASE 
        WHEN dmr.masking_type = 'full' THEN '***'
        WHEN dmr.masking_type = 'partial' THEN CONCAT(LEFT(u.name, 1), '***', RIGHT(u.name, 1))
        ELSE u.name
    END as name,
    u.status,
    u.created_at
FROM users u
LEFT JOIN data_masking_rules dmr ON dmr.table_name = 'users' 
    AND dmr.column_name = 'email' 
    AND dmr.is_active = TRUE;

-- Data masking procedure
DELIMITER $$
CREATE PROCEDURE apply_data_masking(
    IN table_name VARCHAR(100),
    IN column_name VARCHAR(100),
    IN masking_type VARCHAR(20)
)
BEGIN
    DECLARE masking_pattern VARCHAR(255);
    
    -- Set masking pattern based on type
    CASE masking_type
        WHEN 'full' THEN
            SET masking_pattern = '***';
        WHEN 'partial' THEN
            SET masking_pattern = 'CONCAT(LEFT(value, 2), ''***'', RIGHT(value, 4))';
        WHEN 'hash' THEN
            SET masking_pattern = 'SHA2(value, 256)';
        ELSE
            SET masking_pattern = masking_type;
    END CASE;
    
    -- Apply masking rule
    INSERT INTO data_masking_rules (table_name, column_name, masking_type, masking_pattern)
    VALUES (table_name, column_name, masking_type, masking_pattern)
    ON DUPLICATE KEY UPDATE
        masking_type = VALUES(masking_type),
        masking_pattern = VALUES(masking_pattern),
        is_active = TRUE;
END$$
DELIMITER ;
```

## 🔒 Access Control Patterns

### The "Role-Based Access Control (RBAC)" Pattern
```sql
-- RBAC implementation
CREATE TABLE roles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    role_name VARCHAR(100) UNIQUE NOT NULL,
    role_description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE permissions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    permission_name VARCHAR(100) UNIQUE NOT NULL,
    resource_type VARCHAR(50) NOT NULL,  -- 'table', 'column', 'procedure'
    resource_name VARCHAR(100) NOT NULL,
    action_type VARCHAR(50) NOT NULL,  -- 'read', 'write', 'delete', 'execute'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE role_permissions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    role_id BIGINT NOT NULL,
    permission_id BIGINT NOT NULL,
    granted_by BIGINT NOT NULL,
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_role_permission (role_id, permission_id),
    FOREIGN KEY (role_id) REFERENCES roles(id),
    FOREIGN KEY (permission_id) REFERENCES permissions(id)
);

CREATE TABLE user_roles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL,
    granted_by BIGINT NOT NULL,
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE,
    
    UNIQUE KEY uk_user_role (user_id, role_id),
    FOREIGN KEY (role_id) REFERENCES roles(id)
);

-- Permission checking function
DELIMITER $$
CREATE FUNCTION check_permission(
    user_id BIGINT,
    resource_type VARCHAR(50),
    resource_name VARCHAR(100),
    action_type VARCHAR(50)
) 
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE has_permission BOOLEAN DEFAULT FALSE;
    
    SELECT TRUE INTO has_permission
    FROM user_roles ur
    JOIN role_permissions rp ON ur.role_id = rp.role_id
    JOIN permissions p ON rp.permission_id = p.id
    WHERE ur.user_id = user_id
    AND ur.is_active = TRUE
    AND (ur.expires_at IS NULL OR ur.expires_at > NOW())
    AND p.resource_type = resource_type
    AND p.resource_name = resource_name
    AND p.action_type = action_type
    LIMIT 1;
    
    RETURN COALESCE(has_permission, FALSE);
END$$
DELIMITER ;
```

## 🛡️ Security Monitoring & Alerting

### The "Security Event Monitoring" Pattern
```sql
-- Security events tracking
CREATE TABLE security_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,  -- 'login_failed', 'permission_denied', 'data_access'
    user_id BIGINT NULL,
    session_id VARCHAR(100) NULL,
    ip_address VARCHAR(45) NOT NULL,
    user_agent TEXT,
    event_details JSON,
    severity ENUM('low', 'medium', 'high', 'critical') DEFAULT 'medium',
    is_suspicious BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_event_type (event_type, created_at),
    INDEX idx_user_events (user_id, created_at),
    INDEX idx_suspicious (is_suspicious, severity, created_at),
    INDEX idx_ip_address (ip_address, created_at)
);

-- Security alerting
CREATE TABLE security_alerts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    alert_type VARCHAR(50) NOT NULL,
    event_id BIGINT NOT NULL,
    alert_message TEXT NOT NULL,
    severity ENUM('low', 'medium', 'high', 'critical') DEFAULT 'medium',
    is_resolved BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP NULL,
    
    INDEX idx_alert_type (alert_type, is_resolved),
    INDEX idx_severity (severity, created_at)
);

-- Security monitoring procedure
DELIMITER $$
CREATE PROCEDURE monitor_security_events()
BEGIN
    DECLARE failed_login_count INT;
    DECLARE suspicious_ip_count INT;
    
    -- Check for failed login attempts
    SELECT COUNT(*) INTO failed_login_count
    FROM security_events
    WHERE event_type = 'login_failed'
    AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR);
    
    IF failed_login_count > 10 THEN
        INSERT INTO security_alerts (alert_type, event_id, alert_message, severity)
        VALUES ('failed_login_attempts', 0, 
                CONCAT('High number of failed login attempts: ', failed_login_count), 'high');
    END IF;
    
    -- Check for suspicious IP activity
    SELECT COUNT(DISTINCT ip_address) INTO suspicious_ip_count
    FROM security_events
    WHERE event_type = 'permission_denied'
    AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR);
    
    IF suspicious_ip_count > 5 THEN
        INSERT INTO security_alerts (alert_type, event_id, alert_message, severity)
        VALUES ('suspicious_ip_activity', 0, 
                CONCAT('Multiple IPs with permission denials: ', suspicious_ip_count), 'medium');
    END IF;
END$$
DELIMITER ;
```

These security patterns show the real-world techniques that product engineers use to build secure, compliant systems! 🚀
