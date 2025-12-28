-- SaaS Multi-Tenant Platform Starter Schema
-- Complete schema for Software-as-a-Service applications with multi-tenant architecture

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- ===========================================
-- TENANT MANAGEMENT
-- ===========================================

CREATE TABLE tenants (
    tenant_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_name VARCHAR(255) NOT NULL,
    subdomain VARCHAR(100) UNIQUE,
    domain VARCHAR(255) UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    tenant_status VARCHAR(20) DEFAULT 'active' CHECK (tenant_status IN ('active', 'suspended', 'inactive', 'cancelled')),

    -- Billing and Subscription
    subscription_plan VARCHAR(50) DEFAULT 'free',
    subscription_status VARCHAR(20) DEFAULT 'active' CHECK (subscription_status IN ('active', 'past_due', 'cancelled', 'unpaid')),
    trial_ends_at TIMESTAMP WITH TIME ZONE,
    current_period_start TIMESTAMP WITH TIME ZONE,
    current_period_end TIMESTAMP WITH TIME ZONE,

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
    tenant_settings JSONB DEFAULT '{}',
    feature_flags JSONB DEFAULT '{}',  -- Enabled features per tenant

    -- Limits and Quotas
    user_limit INTEGER DEFAULT 10,
    storage_limit_gb INTEGER DEFAULT 1,
    api_rate_limit INTEGER DEFAULT 1000,  -- requests per hour

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,  -- Reference to global admin users table
    activated_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE tenant_users (
    tenant_user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,

    -- User Information (shadow copy for performance)
    global_user_id UUID NOT NULL,  -- Reference to global users table
    email VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    avatar_url VARCHAR(500),

    -- Tenant-specific Role and Permissions
    role VARCHAR(30) DEFAULT 'user' CHECK (role IN ('owner', 'admin', 'manager', 'user', 'viewer')),
    permissions JSONB DEFAULT '[]',
    is_active BOOLEAN DEFAULT TRUE,

    -- Status within tenant
    invitation_status VARCHAR(20) DEFAULT 'accepted' CHECK (invitation_status IN ('pending', 'accepted', 'declined', 'expired')),
    invited_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    invited_by UUID,
    joined_at TIMESTAMP WITH TIME ZONE,

    -- Preferences
    timezone VARCHAR(50) DEFAULT 'UTC',
    language VARCHAR(10) DEFAULT 'en',
    notification_preferences JSONB DEFAULT '{"email": true, "in_app": true}',

    UNIQUE (tenant_id, global_user_id),
    UNIQUE (tenant_id, email)
);

-- ===========================================
-- GLOBAL USERS (Shared across tenants)
-- ===========================================

CREATE TABLE global_users (
    global_user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    email_verified BOOLEAN DEFAULT FALSE,
    password_hash VARCHAR(255),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    avatar_url VARCHAR(500),

    -- Account Status
    is_active BOOLEAN DEFAULT TRUE,
    account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN ('active', 'suspended', 'inactive')),

    -- Security
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    login_count INTEGER DEFAULT 0,

    -- Profile
    bio TEXT,
    website VARCHAR(255),
    location VARCHAR(100),
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- TENANT DATA ISOLATION
-- ===========================================

-- Row Level Security setup
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;

-- Policies for tenant data access
CREATE POLICY tenant_data_policy ON tenants
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id')::UUID);

CREATE POLICY tenant_users_policy ON tenant_users
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id')::UUID);

-- ===========================================
-- APPLICATION DATA (Per-tenant)
-- ===========================================

-- Example: Project/Task Management Application
CREATE TABLE projects (
    project_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    project_name VARCHAR(255) NOT NULL,
    project_description TEXT,
    project_status VARCHAR(20) DEFAULT 'active' CHECK (project_status IN ('active', 'completed', 'on_hold', 'cancelled')),

    -- Project Details
    start_date DATE,
    end_date DATE,
    budget DECIMAL(12,2),
    priority VARCHAR(10) DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),

    -- Team and Access
    owner_id UUID NOT NULL,  -- References tenant_users(tenant_user_id)
    team_members UUID[] DEFAULT '{}',  -- Array of tenant_user_ids

    -- Progress Tracking
    progress_percentage DECIMAL(5,2) DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),
    completed_tasks INTEGER DEFAULT 0,
    total_tasks INTEGER DEFAULT 0,

    -- Metadata
    project_tags TEXT[],
    custom_fields JSONB DEFAULT '{}',

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL,
    updated_by UUID
);

CREATE TABLE tasks (
    task_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    project_id UUID REFERENCES projects(project_id) ON DELETE CASCADE,

    -- Task Details
    task_title VARCHAR(300) NOT NULL,
    task_description TEXT,
    task_status VARCHAR(20) DEFAULT 'todo' CHECK (task_status IN ('todo', 'in_progress', 'review', 'completed', 'cancelled')),
    task_priority VARCHAR(10) DEFAULT 'medium' CHECK (task_priority IN ('low', 'medium', 'high', 'urgent')),

    -- Assignment
    assigned_to UUID,  -- References tenant_users(tenant_user_id)
    assigned_by UUID,
    assigned_at TIMESTAMP WITH TIME ZONE,

    -- Scheduling
    due_date DATE,
    estimated_hours DECIMAL(6,2),
    actual_hours DECIMAL(6,2),

    -- Progress
    progress_percentage DECIMAL(5,2) DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Dependencies
    depends_on UUID[],  -- Array of task_ids
    blocks UUID[],      -- Array of task_ids this task blocks

    -- Labels and Categories
    labels TEXT[],
    category VARCHAR(50),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL,
    updated_by UUID
);

-- ===========================================
-- BILLING AND USAGE TRACKING
-- ===========================================

CREATE TABLE tenant_usage (
    usage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,

    -- Usage Period
    usage_date DATE DEFAULT CURRENT_DATE,
    billing_period_start DATE,
    billing_period_end DATE,

    -- Resource Usage
    active_users INTEGER DEFAULT 0,
    storage_used_gb DECIMAL(8,3) DEFAULT 0,
    api_calls INTEGER DEFAULT 0,
    data_transfer_gb DECIMAL(8,3) DEFAULT 0,

    -- Feature Usage
    feature_usage JSONB DEFAULT '{}',  -- Detailed feature usage metrics

    -- Computed Costs
    base_cost DECIMAL(8,2) DEFAULT 0,
    overage_cost DECIMAL(8,2) DEFAULT 0,
    total_cost DECIMAL(8,2) DEFAULT 0,

    UNIQUE (tenant_id, usage_date)
) PARTITION BY RANGE (usage_date);

CREATE TABLE invoices (
    invoice_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,

    -- Invoice Details
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    invoice_date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    billing_period_start DATE,
    billing_period_end DATE,

    -- Amounts
    subtotal DECIMAL(10,2) NOT NULL,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    discount_amount DECIMAL(10,2) DEFAULT 0,
    total_amount DECIMAL(10,2) NOT NULL,

    -- Currency and Status
    currency_code CHAR(3) DEFAULT 'USD',
    invoice_status VARCHAR(20) DEFAULT 'draft' CHECK (invoice_status IN ('draft', 'sent', 'paid', 'overdue', 'cancelled')),

    -- Payment
    payment_date DATE,
    payment_method VARCHAR(50),
    payment_reference VARCHAR(100),

    -- Line Items
    line_items JSONB DEFAULT '[]',

    -- Notes
    notes TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMP WITH TIME ZONE,
    paid_at TIMESTAMP WITH TIME ZONE
);

-- ===========================================
-- API MANAGEMENT AND RATE LIMITING
-- ===========================================

CREATE TABLE api_keys (
    api_key_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,

    -- Key Details
    api_key_name VARCHAR(100) NOT NULL,
    api_key_hash VARCHAR(128) NOT NULL,  -- Store hash, not plain key
    api_key_prefix VARCHAR(10) NOT NULL,  -- First 10 chars for identification

    -- Permissions
    permissions JSONB DEFAULT '["read"]',  -- Array of permissions
    rate_limit INTEGER DEFAULT 1000,  -- requests per hour
    allowed_ips TEXT[],  -- IP whitelist

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMP WITH TIME ZONE,

    -- Usage Tracking
    last_used_at TIMESTAMP WITH TIME ZONE,
    usage_today INTEGER DEFAULT 0,
    usage_this_hour INTEGER DEFAULT 0,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    revoked_by UUID
);

CREATE TABLE api_requests (
    request_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    api_key_id UUID REFERENCES api_keys(api_key_id),

    -- Request Details
    request_method VARCHAR(10),
    request_path VARCHAR(500),
    request_ip INET,
    user_agent TEXT,
    response_status INTEGER,
    response_time_ms INTEGER,

    -- Timing
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Additional Data
    request_size_bytes INTEGER,
    response_size_bytes INTEGER,
    error_message TEXT
) PARTITION BY RANGE (requested_at);

-- ===========================================
-- AUDIT AND COMPLIANCE
-- ===========================================

CREATE TABLE tenant_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,

    -- Audit Details
    table_name TEXT NOT NULL,
    record_id TEXT,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,

    -- Context
    user_id UUID,  -- References tenant_users(tenant_user_id)
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,

    -- Timestamp
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- ===========================================
-- NOTIFICATIONS AND COMMUNICATION
-- ===========================================

CREATE TABLE notifications (
    notification_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,

    -- Recipients
    recipient_user_id UUID NOT NULL,  -- References tenant_users(tenant_user_id)
    recipient_type VARCHAR(20) DEFAULT 'individual' CHECK (recipient_type IN ('individual', 'team', 'all_users')),

    -- Notification Content
    notification_type VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    action_url VARCHAR(500),

    -- Delivery
    email_sent BOOLEAN DEFAULT FALSE,
    email_sent_at TIMESTAMP WITH TIME ZONE,
    in_app_read BOOLEAN DEFAULT FALSE,
    in_app_read_at TIMESTAMP WITH TIME ZONE,
    push_sent BOOLEAN DEFAULT FALSE,
    push_sent_at TIMESTAMP WITH TIME ZONE,

    -- Priority and Expiry
    priority VARCHAR(10) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 days'),

    -- Metadata
    related_object_type VARCHAR(50),  -- 'project', 'task', 'invoice', etc.
    related_object_id UUID,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    scheduled_at TIMESTAMP WITH TIME ZONE
);

-- ===========================================
-- FILE STORAGE AND ASSETS
-- ===========================================

CREATE TABLE tenant_files (
    file_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,

    -- File Information
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,

    -- Classification
    file_category VARCHAR(30) DEFAULT 'document' CHECK (file_category IN ('document', 'image', 'video', 'archive', 'other')),
    is_public BOOLEAN DEFAULT FALSE,

    -- Access Control
    uploaded_by UUID NOT NULL,  -- References tenant_users(tenant_user_id)
    access_permissions JSONB DEFAULT '[]',  -- Array of user/role IDs with access

    -- Versioning
    version_number INTEGER DEFAULT 1,
    parent_file_id UUID REFERENCES tenant_files(file_id),

    -- Metadata
    file_metadata JSONB DEFAULT '{}',  -- EXIF, dimensions, etc.

    -- Usage Tracking
    download_count INTEGER DEFAULT 0,
    last_accessed_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SYSTEM TABLES FOR TENANT MANAGEMENT
-- ===========================================

CREATE TABLE tenant_jobs (
    job_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,

    -- Job Details
    job_type VARCHAR(50) NOT NULL,
    job_status VARCHAR(20) DEFAULT 'pending' CHECK (job_status IN ('pending', 'running', 'completed', 'failed')),
    job_priority INTEGER DEFAULT 1 CHECK (job_priority BETWEEN 1 AND 10),

    -- Job Data
    job_data JSONB NOT NULL,
    result_data JSONB,

    -- Scheduling
    scheduled_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Retry Logic
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    last_error TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Tenant indexes
CREATE INDEX idx_tenants_status ON tenants (tenant_status);
CREATE INDEX idx_tenants_subdomain ON tenants (subdomain);
CREATE INDEX idx_tenants_active ON tenants (is_active);

-- Tenant users indexes
CREATE INDEX idx_tenant_users_tenant ON tenant_users (tenant_id);
CREATE INDEX idx_tenant_users_global_user ON tenant_users (global_user_id);
CREATE INDEX idx_tenant_users_email ON tenant_users (tenant_id, email);
CREATE INDEX idx_tenant_users_role ON tenant_users (tenant_id, role);

-- Global users indexes
CREATE INDEX idx_global_users_email ON global_users (email);
CREATE INDEX idx_global_users_active ON global_users (is_active);

-- Application data indexes (using tenant_id for partitioning)
CREATE INDEX idx_projects_tenant ON projects (tenant_id, project_status);
CREATE INDEX idx_tasks_tenant ON tasks (tenant_id, task_status);
CREATE INDEX idx_tasks_project ON tasks (project_id);
CREATE INDEX idx_tasks_assigned_to ON tasks (assigned_to);

-- Billing indexes
CREATE INDEX idx_tenant_usage_tenant ON tenant_usage (tenant_id, usage_date DESC);
CREATE INDEX idx_invoices_tenant ON invoices (tenant_id, invoice_status);

-- API indexes
CREATE INDEX idx_api_keys_tenant ON api_keys (tenant_id);
CREATE INDEX idx_api_requests_key ON api_requests (api_key_id, requested_at DESC);
CREATE INDEX idx_api_requests_requested_at ON api_requests (requested_at DESC);

-- Audit indexes
CREATE INDEX idx_tenant_audit_tenant ON tenant_audit_log (tenant_id, changed_at DESC);
CREATE INDEX idx_tenant_audit_table ON tenant_audit_log (tenant_id, table_name);

-- Notification indexes
CREATE INDEX idx_notifications_tenant ON notifications (tenant_id);
CREATE INDEX idx_notifications_recipient ON notifications (recipient_user_id, created_at DESC);

-- File indexes
CREATE INDEX idx_tenant_files_tenant ON tenant_files (tenant_id, file_category);
CREATE INDEX idx_tenant_files_uploaded_by ON tenant_files (uploaded_by);

-- ===========================================
-- PARTITIONING SETUP
-- ===========================================

-- Usage partitioning (monthly)
CREATE TABLE tenant_usage_2024_01 PARTITION OF tenant_usage
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- API requests partitioning (daily for high volume)
CREATE TABLE api_requests_2024_01_01 PARTITION OF api_requests
    FOR VALUES FROM ('2024-01-01') TO ('2024-01-02');

-- Audit log partitioning (monthly)
CREATE TABLE tenant_audit_log_2024_01 PARTITION OF tenant_audit_log
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Tenant overview dashboard
CREATE VIEW tenant_overview AS
SELECT
    t.tenant_id,
    t.tenant_name,
    t.subdomain,
    t.is_active,
    t.subscription_plan,
    t.user_limit,
    t.storage_limit_gb,

    -- Current usage
    COALESCE(u.active_users, 0) as current_users,
    COALESCE(u.storage_used_gb, 0) as storage_used_gb,
    COALESCE(u.api_calls, 0) as api_calls_this_month,

    -- Limits check
    CASE WHEN COALESCE(u.active_users, 0) >= t.user_limit THEN TRUE ELSE FALSE END as at_user_limit,
    CASE WHEN COALESCE(u.storage_used_gb, 0) >= t.storage_limit_gb THEN TRUE ELSE FALSE END as at_storage_limit,

    -- Activity
    t.created_at,
    t.activated_at,
    u.usage_date as last_usage_date

FROM tenants t
LEFT JOIN tenant_usage u ON t.tenant_id = u.tenant_id
  AND u.usage_date = (SELECT MAX(usage_date) FROM tenant_usage WHERE tenant_id = t.tenant_id)
ORDER BY t.created_at DESC;

-- Tenant user summary
CREATE VIEW tenant_user_summary AS
SELECT
    tu.tenant_id,
    COUNT(*) as total_users,
    COUNT(CASE WHEN tu.role = 'owner' THEN 1 END) as owners,
    COUNT(CASE WHEN tu.role = 'admin' THEN 1 END) as admins,
    COUNT(CASE WHEN tu.role = 'manager' THEN 1 END) as managers,
    COUNT(CASE WHEN tu.role = 'user' THEN 1 END) as regular_users,
    COUNT(CASE WHEN tu.invitation_status = 'pending' THEN 1 END) as pending_invitations,
    COUNT(CASE WHEN tu.is_active = FALSE THEN 1 END) as inactive_users
FROM tenant_users tu
GROUP BY tu.tenant_id;

-- API usage summary
CREATE VIEW api_usage_summary AS
SELECT
    ak.tenant_id,
    COUNT(DISTINCT ak.api_key_id) as active_keys,
    SUM(ar.request_id) as total_requests_today,
    AVG(ar.response_time_ms) as avg_response_time,
    COUNT(CASE WHEN ar.response_status >= 400 THEN 1 END) as error_requests,
    MAX(ar.requested_at) as last_request
FROM api_keys ak
LEFT JOIN api_requests ar ON ak.api_key_id = ar.api_key_id
  AND ar.requested_at >= CURRENT_DATE
WHERE ak.is_active = TRUE
GROUP BY ak.tenant_id;

-- ===========================================
-- FUNCTIONS FOR TENANT MANAGEMENT
-- =========================================--

-- Function to create a new tenant
CREATE OR REPLACE FUNCTION create_tenant(
    tenant_name_param TEXT,
    admin_email TEXT,
    admin_first_name TEXT,
    admin_last_name TEXT
)
RETURNS UUID AS $$
DECLARE
    new_tenant_id UUID;
    admin_user_id UUID;
BEGIN
    -- Create tenant
    INSERT INTO tenants (tenant_name, subscription_plan, trial_ends_at)
    VALUES (tenant_name_param, 'trial', CURRENT_TIMESTAMP + INTERVAL '30 days')
    RETURNING tenant_id INTO new_tenant_id;

    -- Create or get global user
    INSERT INTO global_users (email, first_name, last_name, is_active)
    VALUES (admin_email, admin_first_name, admin_last_name, TRUE)
    ON CONFLICT (email) DO UPDATE SET
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name
    RETURNING global_user_id INTO admin_user_id;

    -- Create tenant user as owner
    INSERT INTO tenant_users (tenant_id, global_user_id, email, first_name, last_name, role, invitation_status)
    VALUES (new_tenant_id, admin_user_id, admin_email, admin_first_name, admin_last_name, 'owner', 'accepted');

    RETURN new_tenant_id;
END;
$$ LANGUAGE plpgsql;

-- Function to check tenant limits
CREATE OR REPLACE FUNCTION check_tenant_limits(check_tenant_id UUID)
RETURNS TABLE (
    limit_type TEXT,
    current_value INTEGER,
    max_value INTEGER,
    within_limit BOOLEAN
) AS $$
DECLARE
    tenant_record tenants%ROWTYPE;
    current_users INTEGER;
BEGIN
    -- Get tenant info
    SELECT * INTO tenant_record FROM tenants WHERE tenant_id = check_tenant_id;

    -- Count current users
    SELECT COUNT(*) INTO current_users
    FROM tenant_users
    WHERE tenant_id = check_tenant_id AND is_active = TRUE;

    -- Return limit checks
    RETURN QUERY
    SELECT
        'users'::TEXT,
        current_users,
        tenant_record.user_limit,
        (current_users <= tenant_record.user_limit);

    -- Add more limit checks as needed
END;
$$ LANGUAGE plpgsql;

-- Function to get current tenant context
CREATE OR REPLACE FUNCTION get_current_tenant()
RETURNS tenants AS $$
DECLARE
    tenant_id_value UUID;
    tenant_record tenants%ROWTYPE;
BEGIN
    tenant_id_value := current_setting('app.current_tenant_id')::UUID;

    IF tenant_id_value IS NULL THEN
        RAISE EXCEPTION 'No tenant context set';
    END IF;

    SELECT * INTO tenant_record FROM tenants WHERE tenant_id = tenant_id_value;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tenant not found: %', tenant_id_value;
    END IF;

    RETURN tenant_record;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Create sample global admin user
INSERT INTO global_users (email, password_hash, first_name, last_name, is_active) VALUES
('admin@saasplatform.com', '$2b$10$dummy.hash.here', 'Platform', 'Admin', TRUE);

-- Create sample tenant
INSERT INTO tenants (tenant_name, subdomain, subscription_plan, contact_email, user_limit) VALUES
('Acme Corporation', 'acme', 'professional', 'billing@acme.com', 50);

-- Create tenant user
INSERT INTO tenant_users (
    tenant_id,
    global_user_id,
    email,
    first_name,
    last_name,
    role,
    permissions
) VALUES (
    (SELECT tenant_id FROM tenants WHERE subdomain = 'acme' LIMIT 1),
    (SELECT global_user_id FROM global_users WHERE email = 'admin@saasplatform.com' LIMIT 1),
    'admin@acme.com',
    'John',
    'Smith',
    'owner',
    '["admin", "billing", "user_management"]'::JSONB
);

-- Create sample project
INSERT INTO projects (
    tenant_id,
    project_name,
    project_description,
    owner_id,
    created_by
) VALUES (
    (SELECT tenant_id FROM tenants WHERE subdomain = 'acme' LIMIT 1),
    'Website Redesign',
    'Complete overhaul of company website',
    (SELECT tenant_user_id FROM tenant_users WHERE email = 'admin@acme.com' LIMIT 1),
    (SELECT tenant_user_id FROM tenant_users WHERE email = 'admin@acme.com' LIMIT 1)
);

-- This starter schema provides the foundation for a multi-tenant SaaS application
-- with proper tenant isolation, billing, API management, and audit trails.
