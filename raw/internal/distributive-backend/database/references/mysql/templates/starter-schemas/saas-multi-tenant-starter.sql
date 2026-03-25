-- SaaS Multi-Tenant Platform Starter Schema (MySQL)
-- Complete schema for Software-as-a-Service applications with multi-tenant architecture
-- Adapted for MySQL with row-based tenant isolation and MySQL-specific features

-- ===========================================
-- TENANT MANAGEMENT
-- ===========================================

CREATE TABLE tenants (
    tenant_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_name VARCHAR(255) NOT NULL,
    subdomain VARCHAR(100) UNIQUE,
    domain VARCHAR(255) UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    tenant_status ENUM('active', 'suspended', 'inactive', 'cancelled') DEFAULT 'active',

    -- Billing and Subscription
    subscription_plan ENUM('free', 'starter', 'professional', 'enterprise') DEFAULT 'free',
    subscription_status ENUM('active', 'past_due', 'cancelled', 'unpaid') DEFAULT 'active',
    trial_ends_at TIMESTAMP NULL,
    current_period_start TIMESTAMP NULL,
    current_period_end TIMESTAMP NULL,

    -- Contact Information
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),
    billing_email VARCHAR(255),

    -- Address
    address_line_1 VARCHAR(255),
    address_line_2 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',

    -- Settings and Configuration
    tenant_settings JSON DEFAULT ('{}'),
    feature_flags JSON DEFAULT ('{}'),  -- Enabled features per tenant

    -- Limits and Quotas
    user_limit INTEGER DEFAULT 10,
    storage_limit_gb INTEGER DEFAULT 1,
    api_rate_limit INTEGER DEFAULT 1000,  -- requests per hour

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by VARCHAR(255),

    INDEX idx_tenants_subdomain (subdomain),
    INDEX idx_tenants_domain (domain),
    INDEX idx_tenants_active (is_active),
    INDEX idx_tenants_status (tenant_status),
    INDEX idx_tenants_plan (subscription_plan),
    INDEX idx_tenants_trial_ends (trial_ends_at),
    INDEX idx_tenants_period_end (current_period_end)
) ENGINE = InnoDB;

-- ===========================================
-- USERS AND AUTHENTICATION (Multi-tenant)
-- ===========================================

CREATE TABLE users (
    user_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,

    -- Basic user info
    username VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(200),
    avatar_url VARCHAR(500),

    -- Status and roles
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    role ENUM('owner', 'admin', 'manager', 'user', 'guest') DEFAULT 'user',

    -- Profile
    job_title VARCHAR(100),
    department VARCHAR(100),
    phone VARCHAR(20),

    -- Preferences
    timezone VARCHAR(50) DEFAULT 'UTC',
    language VARCHAR(10) DEFAULT 'en',
    notification_preferences JSON DEFAULT ('{"email": true, "in_app": true}'),

    -- Security
    last_login_at TIMESTAMP NULL,
    failed_login_attempts INT DEFAULT 0,
    locked_until TIMESTAMP NULL,
    password_changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by CHAR(36),

    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL,

    UNIQUE KEY unique_tenant_username (tenant_id, username),
    UNIQUE KEY unique_tenant_email (tenant_id, email),

    INDEX idx_users_tenant (tenant_id),
    INDEX idx_users_email (email),
    INDEX idx_users_active (is_active),
    INDEX idx_users_role (role),
    INDEX idx_users_last_login (last_login_at),
    INDEX idx_users_created_at (created_at)
) ENGINE = InnoDB;

-- ===========================================
-- ORGANIZATIONS AND TEAMS
-- ===========================================

CREATE TABLE organizations (
    org_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,

    org_name VARCHAR(255) NOT NULL,
    org_type ENUM('department', 'division', 'team', 'group') DEFAULT 'department',
    parent_org_id CHAR(36) NULL,

    -- Hierarchy
    org_level INT DEFAULT 1,
    org_path VARCHAR(1000),  -- Materialized path for hierarchy queries

    -- Settings
    max_members INT DEFAULT 100,
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by CHAR(36),

    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    FOREIGN KEY (parent_org_id) REFERENCES organizations(org_id) ON DELETE SET NULL,
    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL,

    INDEX idx_orgs_tenant (tenant_id),
    INDEX idx_orgs_parent (parent_org_id),
    INDEX idx_orgs_type (org_type),
    INDEX idx_orgs_active (is_active),
    INDEX idx_orgs_path (org_path(100))
) ENGINE = InnoDB;

CREATE TABLE user_organizations (
    user_id CHAR(36) NOT NULL,
    org_id CHAR(36) NOT NULL,
    role_in_org ENUM('member', 'lead', 'manager', 'owner') DEFAULT 'member',
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (user_id, org_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (org_id) REFERENCES organizations(org_id) ON DELETE CASCADE,

    INDEX idx_user_orgs_org (org_id),
    INDEX idx_user_orgs_role (role_in_org)
) ENGINE = InnoDB;

-- ===========================================
-- APPLICATION DATA (Multi-tenant)
-- ===========================================

CREATE TABLE projects (
    project_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,

    project_name VARCHAR(255) NOT NULL,
    project_description TEXT,
    project_status ENUM('planning', 'active', 'on_hold', 'completed', 'cancelled') DEFAULT 'planning',

    -- Ownership and access
    owner_id CHAR(36) NOT NULL,
    org_id CHAR(36) NULL,

    -- Timeline
    start_date DATE,
    end_date DATE,
    estimated_hours INT,

    -- Budget and resources
    budget DECIMAL(12,2),
    currency VARCHAR(3) DEFAULT 'USD',

    -- Settings
    is_public BOOLEAN DEFAULT FALSE,
    allow_guest_access BOOLEAN DEFAULT FALSE,

    -- Metadata
    tags JSON DEFAULT ('[]'),
    custom_fields JSON DEFAULT ('{}'),

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by CHAR(36),

    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    FOREIGN KEY (owner_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (org_id) REFERENCES organizations(org_id) ON DELETE SET NULL,
    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL,

    INDEX idx_projects_tenant (tenant_id),
    INDEX idx_projects_owner (owner_id),
    INDEX idx_projects_org (org_id),
    INDEX idx_projects_status (project_status),
    INDEX idx_projects_start_date (start_date),
    INDEX idx_projects_end_date (end_date),
    INDEX idx_projects_public (is_public),
    FULLTEXT INDEX ft_projects_name_desc (project_name, project_description)
) ENGINE = InnoDB;

CREATE TABLE tasks (
    task_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    project_id CHAR(36) NOT NULL,

    task_title VARCHAR(255) NOT NULL,
    task_description TEXT,
    task_status ENUM('todo', 'in_progress', 'review', 'done', 'cancelled') DEFAULT 'todo',
    task_priority ENUM('low', 'medium', 'high', 'urgent') DEFAULT 'medium',

    -- Assignment
    assigned_to CHAR(36) NULL,
    assigned_by CHAR(36) NULL,

    -- Timeline
    due_date DATE,
    estimated_hours DECIMAL(6,2),
    actual_hours DECIMAL(6,2),

    -- Progress
    progress_percentage INT DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),

    -- Relationships
    parent_task_id CHAR(36) NULL,
    task_order INT DEFAULT 0,

    -- Metadata
    tags JSON DEFAULT ('[]'),
    attachments JSON DEFAULT ('[]'),

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by CHAR(36),

    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    FOREIGN KEY (project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (assigned_to) REFERENCES users(user_id) ON DELETE SET NULL,
    FOREIGN KEY (assigned_by) REFERENCES users(user_id) ON DELETE SET NULL,
    FOREIGN KEY (parent_task_id) REFERENCES tasks(task_id) ON DELETE SET NULL,
    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL,

    INDEX idx_tasks_tenant (tenant_id),
    INDEX idx_tasks_project (project_id),
    INDEX idx_tasks_assigned_to (assigned_to),
    INDEX idx_tasks_status (task_status),
    INDEX idx_tasks_priority (task_priority),
    INDEX idx_tasks_due_date (due_date),
    INDEX idx_tasks_parent (parent_task_id),
    INDEX idx_tasks_created_at (created_at)
) ENGINE = InnoDB;

-- ===========================================
-- FILE MANAGEMENT (Multi-tenant)
-- ===========================================

CREATE TABLE files (
    file_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,

    file_name VARCHAR(255) NOT NULL,
    original_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(1000) NOT NULL,
    file_url VARCHAR(1000) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL,

    -- Image dimensions (for images only)
    width INT NULL,
    height INT NULL,

    -- Metadata
    alt_text VARCHAR(255),
    description TEXT,

    -- Associations
    entity_type ENUM('project', 'task', 'user', 'organization') NOT NULL,
    entity_id CHAR(36) NOT NULL,

    -- Upload info
    uploaded_by CHAR(36) NOT NULL,
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Access control
    is_public BOOLEAN DEFAULT FALSE,

    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    FOREIGN KEY (uploaded_by) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_files_tenant (tenant_id),
    INDEX idx_files_entity (entity_type, entity_id),
    INDEX idx_files_uploaded_by (uploaded_by),
    INDEX idx_files_public (is_public),
    INDEX idx_files_uploaded_at (uploaded_at)
) ENGINE = InnoDB;

-- ===========================================
-- AUDIT AND LOGGING (Multi-tenant)
-- ===========================================

CREATE TABLE audit_logs (
    audit_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    tenant_id CHAR(36) NOT NULL,

    -- Event details
    event_type VARCHAR(100) NOT NULL,
    event_description TEXT,
    severity ENUM('low', 'medium', 'high', 'critical') DEFAULT 'medium',

    -- Actor
    user_id CHAR(36) NULL,
    actor_ip VARCHAR(45),
    user_agent TEXT,

    -- Target
    entity_type VARCHAR(100),
    entity_id CHAR(36),

    -- Changes
    old_values JSON,
    new_values JSON,
    metadata JSON DEFAULT ('{}'),

    -- Timestamp
    event_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL,

    INDEX idx_audit_tenant (tenant_id),
    INDEX idx_audit_user (user_id),
    INDEX idx_audit_event_type (event_type),
    INDEX idx_audit_entity (entity_type, entity_id),
    INDEX idx_audit_severity (severity),
    INDEX idx_audit_time (event_time)
) ENGINE = InnoDB;

-- ===========================================
-- API MANAGEMENT
-- ===========================================

CREATE TABLE api_keys (
    api_key_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,

    api_key_name VARCHAR(100) NOT NULL,
    api_key_hash VARCHAR(255) NOT NULL,  -- Hashed version of the actual key
    api_key_preview VARCHAR(20),         -- First 20 chars for display

    -- Permissions and limits
    permissions JSON DEFAULT ('[]'),     -- Array of allowed permissions
    rate_limit_per_hour INT DEFAULT 1000,
    is_active BOOLEAN DEFAULT TRUE,

    -- Ownership
    created_by CHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP NULL,
    expires_at TIMESTAMP NULL,

    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_api_keys_tenant (tenant_id),
    INDEX idx_api_keys_created_by (created_by),
    INDEX idx_api_keys_active (is_active),
    INDEX idx_api_keys_expires (expires_at)
) ENGINE = InnoDB;

-- ===========================================
-- BILLING AND USAGE TRACKING
-- ===========================================

CREATE TABLE usage_metrics (
    metric_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    tenant_id CHAR(36) NOT NULL,

    metric_type VARCHAR(100) NOT NULL,  -- 'api_calls', 'storage_gb', 'users', etc.
    metric_value DECIMAL(12,4) NOT NULL,
    unit VARCHAR(20) DEFAULT 'count',

    -- Time period
    period_start TIMESTAMP NOT NULL,
    period_end TIMESTAMP NOT NULL,

    -- Metadata
    dimensions JSON DEFAULT ('{}'),  -- Additional dimensions for the metric

    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE,

    INDEX idx_metrics_tenant (tenant_id),
    INDEX idx_metrics_type (metric_type),
    INDEX idx_metrics_period (period_start, period_end),
    INDEX idx_metrics_recorded (recorded_at)
) ENGINE = InnoDB;

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Composite indexes for tenant-scoped queries
CREATE INDEX idx_users_tenant_active ON users (tenant_id, is_active);
CREATE INDEX idx_users_tenant_role ON users (tenant_id, role);
CREATE INDEX idx_projects_tenant_status ON projects (tenant_id, project_status);
CREATE INDEX idx_tasks_tenant_status ON tasks (tenant_id, task_status);
CREATE INDEX idx_tasks_project_status ON tasks (project_id, task_status);

-- ===========================================
-- TRIGGERS FOR AUTOMATION
-- ===========================================

DELIMITER ;;

-- Update tenant updated_at timestamp
CREATE TRIGGER update_tenant_timestamp BEFORE UPDATE ON tenants
FOR EACH ROW
BEGIN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END;;

-- Audit trigger for users table
CREATE TRIGGER audit_users AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_logs (tenant_id, event_type, event_description, user_id, entity_type, entity_id, new_values)
    VALUES (NEW.tenant_id, 'user_created', CONCAT('User ', NEW.username, ' created'), NEW.user_id, 'user', NEW.user_id,
           JSON_OBJECT('username', NEW.username, 'email', NEW.email, 'role', NEW.role));
END;;

-- Update user updated_at timestamp
CREATE TRIGGER update_user_timestamp BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END;;

-- Update organization path for hierarchy
CREATE TRIGGER update_org_path BEFORE INSERT ON organizations
FOR EACH ROW
BEGIN
    IF NEW.parent_org_id IS NULL THEN
        SET NEW.org_path = CONCAT('/', NEW.org_id);
        SET NEW.org_level = 1;
    ELSE
        SELECT CONCAT(org_path, '/', NEW.org_id), org_level + 1
        INTO NEW.org_path, NEW.org_level
        FROM organizations WHERE org_id = NEW.parent_org_id;
    END IF;
END;;

DELIMITER ;

-- ===========================================
-- VIEWS FOR COMMON QUERIES
-- ===========================================

-- User details with tenant and organization info
CREATE VIEW user_details AS
SELECT
    u.*,
    t.tenant_name,
    t.subdomain,
    o.org_name,
    uo.role_in_org
FROM users u
JOIN tenants t ON u.tenant_id = t.tenant_id
LEFT JOIN user_organizations uo ON u.user_id = uo.user_id
LEFT JOIN organizations o ON uo.org_id = o.org_id;

-- Project summary with task counts
CREATE VIEW project_summary AS
SELECT
    p.*,
    u.full_name AS owner_name,
    COUNT(t.task_id) AS total_tasks,
    COUNT(CASE WHEN t.task_status = 'done' THEN 1 END) AS completed_tasks,
    COUNT(CASE WHEN t.task_status = 'in_progress' THEN 1 END) AS in_progress_tasks
FROM projects p
LEFT JOIN users u ON p.owner_id = u.user_id
LEFT JOIN tasks t ON p.project_id = t.project_id
GROUP BY p.project_id, u.full_name;

-- ===========================================
-- STORED PROCEDURES
-- ===========================================

DELIMITER ;;

-- Get tenant usage summary
CREATE PROCEDURE get_tenant_usage_summary(IN p_tenant_id CHAR(36))
BEGIN
    SELECT
        u.metric_type,
        SUM(u.metric_value) AS total_value,
        MAX(u.recorded_at) AS last_recorded
    FROM usage_metrics u
    WHERE u.tenant_id = p_tenant_id
      AND u.period_end >= CURRENT_DATE - INTERVAL 30 DAY
    GROUP BY u.metric_type
    ORDER BY u.metric_type;
END;;

-- Create new tenant with default settings
CREATE PROCEDURE create_tenant(
    IN p_tenant_name VARCHAR(255),
    IN p_subdomain VARCHAR(100),
    IN p_contact_email VARCHAR(255),
    IN p_created_by VARCHAR(255)
)
BEGIN
    DECLARE new_tenant_id CHAR(36);

    SET new_tenant_id = UUID();

    INSERT INTO tenants (
        tenant_id, tenant_name, subdomain, contact_email, created_by
    ) VALUES (
        new_tenant_id, p_tenant_name, p_subdomain, p_contact_email, p_created_by
    );

    SELECT new_tenant_id AS tenant_id;
END;;

DELIMITER ;

-- ===========================================
-- INITIAL DATA
-- ===========================================

-- Create a default tenant for development
INSERT INTO tenants (
    tenant_id, tenant_name, subdomain, contact_email, user_limit, subscription_plan
) VALUES (
    UUID(), 'Default Tenant', 'default', 'admin@default.com', 100, 'professional'
);

-- Create system settings table for global configuration
CREATE TABLE system_settings (
    setting_id INT PRIMARY KEY AUTO_INCREMENT,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value LONGTEXT,
    setting_type ENUM('string', 'integer', 'boolean', 'json') DEFAULT 'string',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_system_settings_key (setting_key)
) ENGINE = InnoDB;

INSERT INTO system_settings (setting_key, setting_value, setting_type) VALUES
('max_tenant_users', '10000', 'integer'),
('default_trial_days', '14', 'integer'),
('system_maintenance_mode', 'false', 'boolean');

/*
USAGE EXAMPLES:

-- Create a new tenant
CALL create_tenant('Acme Corp', 'acme', 'admin@acme.com', 'system');

-- Get tenant usage
CALL get_tenant_usage_summary('tenant-uuid-here');

This schema provides a complete foundation for a SaaS multi-tenant platform with:
- Tenant isolation and management
- Multi-tenant users and organizations
- Project and task management
- File management with tenant scoping
- Comprehensive audit logging
- API key management
- Usage tracking and billing
- Hierarchical organizations
- Performance optimizations

Key considerations for multi-tenant applications:
1. Always include tenant_id in WHERE clauses for data isolation
2. Use appropriate indexes for tenant-scoped queries
3. Implement proper audit logging for compliance
4. Handle tenant-specific feature flags and limits
5. Consider partitioning large tables by tenant_id for performance

Adapt and extend based on your specific SaaS requirements!
*/
