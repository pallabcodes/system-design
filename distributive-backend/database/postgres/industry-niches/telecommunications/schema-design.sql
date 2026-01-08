-- Telecommunications Database Schema
-- Comprehensive schema for telecom operations, network management, and customer services

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "postgis"; -- For network coverage mapping

-- ===========================================
-- NETWORK INFRASTRUCTURE MANAGEMENT
-- ===========================================

CREATE TABLE telecom_providers (
    provider_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_name VARCHAR(255) NOT NULL,
    provider_code VARCHAR(20) UNIQUE NOT NULL,

    -- Provider Details
    provider_type VARCHAR(30) CHECK (provider_type IN (
        'mobile', 'fixed_line', 'broadband', 'cable', 'satellite', 'fiber'
    )),
    regulatory_id VARCHAR(50),
    license_number VARCHAR(100),

    -- Service Areas
    service_regions TEXT[], -- Geographic regions served
    coverage_area GEOGRAPHY(MULTIPOLYGON, 4326),

    -- Network Capabilities
    supported_technologies TEXT[], -- 5G, 4G, LTE, DSL, Cable, Fiber
    frequency_bands TEXT[], -- MHz/GHz bands used
    network_capacity INTEGER, -- Maximum concurrent connections

    -- Business Information
    market_share DECIMAL(5,2),
    customer_base INTEGER,
    annual_revenue DECIMAL(15,2),

    -- Operational Status
    provider_status VARCHAR(20) DEFAULT 'active' CHECK (provider_status IN ('active', 'inactive', 'merger', 'bankruptcy')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE network_elements (
    element_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_id UUID NOT NULL REFERENCES telecom_providers(provider_id),

    -- Element Identification
    element_name VARCHAR(255) NOT NULL,
    element_code VARCHAR(30) UNIQUE NOT NULL,
    element_type VARCHAR(50) CHECK (element_type IN (
        'cell_tower', 'base_station', 'switch', 'router', 'amplifier',
        'fiber_node', 'satellite_dish', 'cable_headend', 'data_center'
    )),

    -- Location and Coverage
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),
    coverage_area GEOGRAPHY(POLYGON, 4326), -- For cell towers/base stations

    -- Technical Specifications
    technology VARCHAR(20) CHECK (technology IN ('5G', '4G', '3G', 'LTE', 'DSL', 'Cable', 'Fiber', 'Satellite')),
    frequency_band VARCHAR(20),
    max_capacity INTEGER, -- Maximum throughput/connections
    power_rating_kw DECIMAL(6,2),

    -- Equipment Details
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    serial_number VARCHAR(100),
    installation_date DATE,

    -- Operational Status
    operational_status VARCHAR(20) DEFAULT 'active' CHECK (operational_status IN (
        'active', 'maintenance', 'failed', 'decommissioned', 'standby'
    )),
    last_maintenance_date DATE,
    next_maintenance_date DATE,

    -- Performance Metrics
    uptime_percentage DECIMAL(5,2),
    signal_strength_dbm DECIMAL(5,1),
    interference_level DECIMAL(5,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE network_topology (
    link_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Link Details
    source_element_id UUID NOT NULL REFERENCES network_elements(element_id),
    target_element_id UUID NOT NULL REFERENCES network_elements(element_id),
    link_type VARCHAR(30) CHECK (link_type IN (
        'fiber_optic', 'copper', 'wireless', 'satellite', 'microwave'
    )),

    -- Physical Characteristics
    distance_km DECIMAL(8,2),
    link_path GEOGRAPHY(LINESTRING, 4326), -- Geographic path of the link

    -- Technical Specifications
    bandwidth_mbps INTEGER,
    latency_ms DECIMAL(6,2),
    signal_loss_db DECIMAL(5,2),

    -- Operational Status
    link_status VARCHAR(20) DEFAULT 'active' CHECK (link_status IN ('active', 'maintenance', 'failed', 'planned')),
    installation_date DATE,
    last_tested TIMESTAMP WITH TIME ZONE,

    -- Reliability Metrics
    uptime_percentage DECIMAL(5,2),
    failure_count INTEGER DEFAULT 0,
    mean_time_between_failures_days INTEGER,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (source_element_id, target_element_id)
);

-- ===========================================
-- CUSTOMER AND SERVICE MANAGEMENT
-- ===========================================

CREATE TABLE telecom_customers (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_number VARCHAR(20) UNIQUE NOT NULL,

    -- Customer Identity
    customer_type VARCHAR(20) CHECK (customer_type IN ('individual', 'business', 'government')),
    title VARCHAR(10),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    company_name VARCHAR(255),

    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(20),
    mobile VARCHAR(20),
    fax VARCHAR(20),

    -- Service Address
    service_address JSONB NOT NULL,
    billing_address JSONB,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),

    -- Account Details
    account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN (
        'active', 'inactive', 'suspended', 'disconnected', 'pending_activation'
    )),
    account_type VARCHAR(30) CHECK (account_type IN ('prepaid', 'postpaid', 'business', 'government')),
    credit_rating VARCHAR(10) CHECK (credit_rating IN ('excellent', 'good', 'fair', 'poor')),

    -- Customer Lifecycle
    acquisition_date DATE,
    churn_risk_score DECIMAL(3,1), -- 1-10 scale
    lifetime_value DECIMAL(10,2),
    customer_satisfaction_score DECIMAL(3,1),

    -- Preferences and Consent
    contact_preferences JSONB DEFAULT '{}',
    marketing_opt_in BOOLEAN DEFAULT TRUE,
    data_sharing_consent BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE service_plans (
    plan_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_id UUID NOT NULL REFERENCES telecom_providers(provider_id),

    -- Plan Details
    plan_name VARCHAR(255) NOT NULL,
    plan_code VARCHAR(20) UNIQUE NOT NULL,
    plan_type VARCHAR(30) CHECK (plan_type IN (
        'mobile_voice', 'mobile_data', 'fixed_broadband', 'cable_tv',
        'bundled', 'business_connectivity', 'iot_connectivity'
    )),

    -- Plan Specifications
    data_allowance_gb DECIMAL(8,2), -- For data plans
    voice_minutes INTEGER, -- For voice plans
    sms_count INTEGER, -- For SMS plans
    speed_mbps_down INTEGER,
    speed_mbps_up INTEGER,

    -- Pricing
    base_price DECIMAL(8,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    billing_cycle VARCHAR(20) CHECK (billing_cycle IN ('monthly', 'quarterly', 'annual', 'prepaid')),

    -- Terms and Conditions
    contract_length_months INTEGER DEFAULT 0, -- 0 for month-to-month
    early_termination_fee DECIMAL(8,2),
    overage_charge_per_gb DECIMAL(6,2),

    -- Availability and Status
    plan_status VARCHAR(20) DEFAULT 'active' CHECK (plan_status IN ('active', 'discontinued', 'coming_soon')),
    available_regions TEXT[],
    target_customer_type VARCHAR(20) CHECK (target_customer_type IN ('consumer', 'business', 'enterprise')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer_services (
    service_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES telecom_customers(customer_id),
    plan_id UUID NOT NULL REFERENCES service_plans(plan_id),

    -- Service Details
    service_number VARCHAR(30) UNIQUE NOT NULL, -- Phone number, account number, etc.
    service_type VARCHAR(30) CHECK (service_type IN ('mobile', 'fixed_line', 'broadband', 'cable', 'satellite')),

    -- Service Configuration
    imei VARCHAR(20), -- For mobile devices
    mac_address MACADDR, -- For broadband/cable
    ip_address INET, -- Assigned IP address

    -- Activation and Lifecycle
    activation_date DATE,
    service_status VARCHAR(20) DEFAULT 'active' CHECK (service_status IN (
        'pending_activation', 'active', 'suspended', 'disconnected', 'porting'
    )),
    porting_status VARCHAR(20) CHECK (porting_status IN ('none', 'porting_in', 'porting_out', 'completed')),

    -- Service Location
    service_latitude DECIMAL(10,8),
    service_longitude DECIMAL(11,8),
    coverage_quality VARCHAR(20) CHECK (coverage_quality IN ('excellent', 'good', 'fair', 'poor')),

    -- Equipment
    equipment_provided JSONB DEFAULT '[]', -- Router, modem, phone, etc.

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- USAGE TRACKING AND BILLING
-- =========================================--

CREATE TABLE usage_records (
    usage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id UUID NOT NULL REFERENCES customer_services(service_id),

    -- Usage Details
    usage_date DATE DEFAULT CURRENT_DATE,
    usage_time TIME DEFAULT CURRENT_TIME,
    usage_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Usage Metrics
    data_usage_bytes BIGINT DEFAULT 0,
    voice_seconds INTEGER DEFAULT 0,
    sms_count INTEGER DEFAULT 0,

    -- Service Quality
    signal_strength_dbm DECIMAL(5,1),
    connection_type VARCHAR(20) CHECK (connection_type IN ('5G', '4G', '3G', 'LTE', 'WiFi', 'Ethernet')),
    network_element_id UUID REFERENCES network_elements(element_id),

    -- Location Tracking (for mobile)
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    location_accuracy_meters DECIMAL(6,1),

    -- Application/Service Usage
    application_used VARCHAR(100), -- App name or service
    destination_ip INET,
    destination_port INTEGER,

    -- Billing Information
    billable BOOLEAN DEFAULT TRUE,
    billing_period_start DATE,
    billing_period_end DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (usage_timestamp);

-- Create partitions for usage records (example for 2024)
CREATE TABLE usage_records_2024_01 PARTITION OF usage_records
    FOR VALUES FROM ('2024-01-01 00:00:00') TO ('2024-02-01 00:00:00');

CREATE TABLE bills (
    bill_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES telecom_customers(customer_id),

    -- Billing Period
    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,
    bill_date DATE DEFAULT CURRENT_DATE,
    due_date DATE NOT NULL,

    -- Bill Components
    service_charges DECIMAL(8,2) DEFAULT 0,
    usage_charges DECIMAL(8,2) DEFAULT 0,
    equipment_charges DECIMAL(8,2) DEFAULT 0,
    taxes DECIMAL(8,2) DEFAULT 0,
    fees DECIMAL(8,2) DEFAULT 0,
    total_amount DECIMAL(8,2) NOT NULL,

    -- Bill Details
    previous_balance DECIMAL(8,2) DEFAULT 0,
    payments_credits DECIMAL(8,2) DEFAULT 0,
    amount_due DECIMAL(8,2) GENERATED ALWAYS AS (total_amount - payments_credits) STORED,

    -- Bill Status and Processing
    bill_status VARCHAR(20) DEFAULT 'unpaid' CHECK (bill_status IN ('unpaid', 'paid', 'overdue', 'disputed', 'adjusted')),
    payment_status VARCHAR(20) CHECK (payment_status IN ('pending', 'processing', 'completed', 'failed')),

    -- Delivery and Communication
    bill_delivery_method VARCHAR(20) CHECK (bill_delivery_method IN ('email', 'mail', 'online', 'sms')),
    last_reminder_sent DATE,
    collection_status VARCHAR(20) CHECK (collection_status IN ('current', 'past_due', 'collections', 'write_off')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (billing_period_start < billing_period_end),
    CHECK (bill_date <= due_date)
);

CREATE TABLE payments (
    payment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES telecom_customers(customer_id),

    -- Payment Details
    payment_date DATE DEFAULT CURRENT_DATE,
    payment_amount DECIMAL(10,2) NOT NULL,
    payment_method VARCHAR(30) CHECK (payment_method IN (
        'credit_card', 'debit_card', 'ach', 'check', 'cash', 'online_wallet', 'auto_pay'
    )),

    -- Payment Processing
    payment_reference VARCHAR(100),
    processing_fee DECIMAL(4,2) DEFAULT 0,
    currency_code CHAR(3) DEFAULT 'USD',

    -- Bill Allocation
    bills_paid JSONB DEFAULT '[]', -- Array of bill IDs and amounts applied

    -- Status and Reconciliation
    payment_status VARCHAR(20) DEFAULT 'completed' CHECK (payment_status IN ('pending', 'completed', 'failed', 'reversed')),
    reconciled BOOLEAN DEFAULT FALSE,

    -- Auto-pay Information
    auto_pay_setup BOOLEAN DEFAULT FALSE,
    auto_pay_day INTEGER CHECK (auto_pay_day BETWEEN 1 AND 31),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (payment_amount > 0)
);

-- ===========================================
-- NETWORK PERFORMANCE AND MONITORING
-- =========================================--

CREATE TABLE network_performance (
    performance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    element_id UUID NOT NULL REFERENCES network_elements(element_id),

    -- Time Dimensions
    measurement_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    measurement_date DATE GENERATED ALWAYS AS (measurement_timestamp::DATE) STORED,

    -- Performance Metrics
    signal_strength_dbm DECIMAL(5,1),
    signal_quality_percentage DECIMAL(5,2),
    bandwidth_utilization_percentage DECIMAL(5,2),
    latency_ms DECIMAL(6,2),
    jitter_ms DECIMAL(6,2),
    packet_loss_percentage DECIMAL(5,2),

    -- Capacity Metrics
    active_connections INTEGER,
    max_connections INTEGER,
    throughput_mbps DECIMAL(8,2),
    error_rate_percentage DECIMAL(5,2),

    -- Environmental Factors
    temperature_celsius DECIMAL(4,1),
    humidity_percentage DECIMAL(5,2),
    power_consumption_kw DECIMAL(6,2),

    -- Location Context
    connected_devices INTEGER,
    coverage_radius_meters DECIMAL(6,1),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (measurement_timestamp);

-- Create partitions for performance data
CREATE TABLE network_performance_2024_01 PARTITION OF network_performance
    FOR VALUES FROM ('2024-01-01 00:00:00') TO ('2024-02-01 00:00:00');

CREATE TABLE service_quality (
    quality_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id UUID NOT NULL REFERENCES customer_services(service_id),

    -- Quality Assessment
    assessment_date DATE DEFAULT CURRENT_DATE,
    speed_test_download_mbps DECIMAL(6,2),
    speed_test_upload_mbps DECIMAL(6,2),
    ping_latency_ms DECIMAL(6,2),

    -- Customer Experience
    customer_rating INTEGER CHECK (customer_rating BETWEEN 1 AND 5),
    quality_complaints INTEGER DEFAULT 0,
    outage_experiences INTEGER DEFAULT 0,

    -- Network Quality
    signal_bars INTEGER CHECK (signal_bars BETWEEN 0 AND 5),
    data_speed_satisfaction VARCHAR(20) CHECK (data_speed_satisfaction IN ('very_satisfied', 'satisfied', 'neutral', 'dissatisfied', 'very_dissatisfied')),
    call_quality_rating INTEGER CHECK (call_quality_rating BETWEEN 1 AND 5),

    -- Usage Context
    device_type VARCHAR(50),
    location_type VARCHAR(30) CHECK (location_type IN ('home', 'office', 'public', 'mobile')),
    network_type VARCHAR(20) CHECK (network_type IN ('wifi', 'cellular', 'ethernet')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- CUSTOMER SERVICE AND SUPPORT
-- ===========================================

CREATE TABLE support_tickets (
    ticket_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES telecom_customers(customer_id),

    -- Ticket Details
    ticket_number VARCHAR(30) UNIQUE NOT NULL,
    ticket_subject VARCHAR(255) NOT NULL,
    ticket_description TEXT,

    -- Classification
    ticket_type VARCHAR(30) CHECK (ticket_type IN (
        'technical_support', 'billing_inquiry', 'service_outage',
        'speed_issue', 'equipment_problem', 'account_issue',
        'porting_request', 'complaint', 'feature_request'
    )),
    ticket_priority VARCHAR(10) CHECK (ticket_priority IN ('low', 'medium', 'high', 'urgent')),

    -- Service Context
    service_id UUID REFERENCES customer_services(service_id),
    network_element_id UUID REFERENCES network_elements(element_id),

    -- Assignment and Resolution
    assigned_to UUID, -- Support agent ID
    assigned_at TIMESTAMP WITH TIME ZONE,
    department VARCHAR(50),

    -- Status and Resolution
    ticket_status VARCHAR(20) DEFAULT 'open' CHECK (ticket_status IN (
        'open', 'assigned', 'in_progress', 'waiting_customer',
        'resolved', 'closed', 'escalated'
    )),
    resolution TEXT,
    resolution_category VARCHAR(50),

    -- Customer Satisfaction
    customer_satisfaction_rating INTEGER CHECK (customer_satisfaction_rating BETWEEN 1 AND 5),
    feedback TEXT,

    -- SLA Tracking
    sla_breach BOOLEAN DEFAULT FALSE,
    first_response_time INTERVAL,
    resolution_time INTERVAL,
    sla_target_response_time INTERVAL DEFAULT INTERVAL '4 hours',
    sla_target_resolution_time INTERVAL DEFAULT INTERVAL '24 hours',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE outages (
    outage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_id UUID NOT NULL REFERENCES telecom_providers(provider_id),

    -- Outage Details
    outage_number VARCHAR(30) UNIQUE NOT NULL,
    outage_type VARCHAR(30) CHECK (outage_type IN (
        'network_failure', 'equipment_failure', 'fiber_cut',
        'power_outage', 'maintenance', 'cyber_attack', 'natural_disaster'
    )),

    -- Impact Assessment
    affected_services INTEGER,
    affected_customers INTEGER,
    affected_area GEOGRAPHY(MULTIPOLYGON, 4326),

    -- Timeline
    outage_start TIMESTAMP WITH TIME ZONE,
    estimated_restoration TIMESTAMP WITH TIME ZONE,
    actual_restoration TIMESTAMP WITH TIME ZONE,

    -- Technical Details
    root_cause TEXT,
    affected_elements UUID[], -- Array of network element IDs
    severity_level VARCHAR(10) CHECK (severity_level IN ('minor', 'moderate', 'major', 'critical')),

    -- Communication
    status_updates JSONB DEFAULT '[]',
    customer_notifications_sent INTEGER DEFAULT 0,

    -- Resolution
    resolution_description TEXT,
    preventive_measures TEXT,

    -- Status
    outage_status VARCHAR(20) DEFAULT 'reported' CHECK (outage_status IN (
        'reported', 'investigating', 'repairing', 'resolved', 'closed'
    )),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- =========================================--

CREATE TABLE telecom_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_period VARCHAR(10) CHECK (report_period IN ('daily', 'weekly', 'monthly', 'quarterly')),

    -- Network Performance
    average_network_uptime DECIMAL(5,2),
    average_latency_ms DECIMAL(6,2),
    peak_bandwidth_utilization DECIMAL(5,2),
    network_coverage_percentage DECIMAL(5,2),

    -- Service Quality
    average_customer_satisfaction DECIMAL(3,1),
    service_outage_incidents INTEGER DEFAULT 0,
    average_resolution_time_hours DECIMAL(4,1),

    -- Customer Metrics
    total_customers INTEGER DEFAULT 0,
    new_customers INTEGER DEFAULT 0,
    churned_customers INTEGER DEFAULT 0,
    customer_acquisition_cost DECIMAL(8,2),

    -- Financial Metrics
    monthly_recurring_revenue DECIMAL(15,2),
    average_revenue_per_user DECIMAL(8,2),
    churn_rate_percentage DECIMAL(5,2),

    -- Usage Metrics
    total_data_usage_tb DECIMAL(8,2),
    average_data_usage_per_customer_gb DECIMAL(6,2),
    peak_usage_hour INTEGER,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (report_date, report_period)
);

CREATE TABLE customer_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES telecom_customers(customer_id),

    -- Time Dimensions
    report_date DATE NOT NULL,

    -- Usage Patterns
    monthly_data_usage_gb DECIMAL(8,2),
    monthly_voice_minutes INTEGER,
    peak_usage_day VARCHAR(10),
    preferred_usage_time TIME,

    -- Service Quality
    average_signal_strength DECIMAL(4,1),
    service_downtime_minutes INTEGER,
    speed_test_count INTEGER,
    average_download_speed_mbps DECIMAL(6,2),

    -- Billing and Payment
    monthly_bill_amount DECIMAL(8,2),
    payment_history_score DECIMAL(3,1), -- 1-5 scale
    days_overdue_average DECIMAL(4,1),

    -- Customer Behavior
    app_usage_frequency VARCHAR(20) CHECK (app_usage_frequency IN ('daily', 'weekly', 'monthly', 'rarely')),
    self_service_interactions INTEGER,
    support_ticket_count INTEGER,

    -- Churn Indicators
    churn_probability DECIMAL(3,2),
    engagement_score DECIMAL(3,1),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (customer_id, report_date)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Geographic indexes
CREATE INDEX idx_telecom_providers_coverage ON telecom_providers USING gist (coverage_area);
CREATE INDEX idx_network_elements_location ON network_elements USING gist (geolocation);
CREATE INDEX idx_network_elements_coverage ON network_elements USING gist (coverage_area);
CREATE INDEX idx_network_topology_path ON network_topology USING gist (link_path);
CREATE INDEX idx_telecom_customers_location ON telecom_customers USING gist (geolocation);

-- Service and customer indexes
CREATE INDEX idx_customer_services_customer ON customer_services (customer_id, service_status);
CREATE INDEX idx_customer_services_number ON customer_services (service_number);
CREATE INDEX idx_service_plans_provider ON service_plans (provider_id, plan_status);

-- Usage and billing indexes
CREATE INDEX idx_usage_records_service_timestamp ON usage_records (service_id, usage_timestamp DESC);
CREATE INDEX idx_bills_customer_period ON bills (customer_id, billing_period_start DESC, bill_status);
CREATE INDEX idx_payments_customer_date ON payments (customer_id, payment_date DESC);

-- Network monitoring indexes
CREATE INDEX idx_network_performance_element_time ON network_performance (element_id, measurement_timestamp DESC);
CREATE INDEX idx_service_quality_service_date ON service_quality (service_id, assessment_date DESC);

-- Support and outage indexes
CREATE INDEX idx_support_tickets_customer_status ON support_tickets (customer_id, ticket_status);
CREATE INDEX idx_support_tickets_assigned ON support_tickets (assigned_to, ticket_status);
CREATE INDEX idx_outages_provider_status ON outages (provider_id, outage_status);
CREATE INDEX idx_outages_affected_area ON outages USING gist (affected_area);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Network health dashboard
CREATE VIEW network_health_dashboard AS
SELECT
    tp.provider_name,

    -- Network elements status
    COUNT(ne.element_id) as total_elements,
    COUNT(CASE WHEN ne.operational_status = 'active' THEN 1 END) as active_elements,
    ROUND(
        COUNT(CASE WHEN ne.operational_status = 'active' THEN 1 END)::DECIMAL /
        COUNT(ne.element_id) * 100, 1
    ) as element_uptime_percentage,

    -- Network performance (last 24 hours)
    AVG(np.signal_strength_dbm) as avg_signal_strength,
    AVG(np.bandwidth_utilization_percentage) as avg_bandwidth_utilization,
    AVG(np.latency_ms) as avg_latency_ms,

    -- Network topology health
    COUNT(nt.link_id) as total_links,
    COUNT(CASE WHEN nt.link_status = 'active' THEN 1 END) as active_links,
    ROUND(
        COUNT(CASE WHEN nt.link_status = 'active' THEN 1 END)::DECIMAL /
        COUNT(nt.link_id) * 100, 1
    ) as link_uptime_percentage,

    -- Current outages
    COUNT(o.outage_id) as active_outages,
    SUM(o.affected_customers) as customers_affected_by_outages,

    -- Service quality
    AVG(sq.speed_test_download_mbps) as avg_download_speed,
    AVG(sq.customer_rating) as avg_customer_rating,

    -- Overall health score
    ROUND(
        (
            -- Element uptime (20%)
            COALESCE(ROUND(
                COUNT(CASE WHEN ne.operational_status = 'active' THEN 1 END)::DECIMAL /
                COUNT(ne.element_id) * 100, 1
            ), 0) / 100 * 20 +
            -- Link uptime (15%)
            COALESCE(ROUND(
                COUNT(CASE WHEN nt.link_status = 'active' THEN 1 END)::DECIMAL /
                COUNT(nt.link_id) * 100, 1
            ), 0) / 100 * 15 +
            -- Performance (25%)
            CASE WHEN AVG(np.bandwidth_utilization_percentage) < 80 THEN 25
                 WHEN AVG(np.bandwidth_utilization_percentage) < 90 THEN 20
                 ELSE 15 END +
            -- Customer satisfaction (20%)
            COALESCE(AVG(sq.customer_rating), 0) / 5 * 20 +
            -- Outage impact (20%)
            CASE WHEN COUNT(o.outage_id) = 0 THEN 20
                 WHEN SUM(o.affected_customers) < 100 THEN 15
                 ELSE 5 END
        ), 1
    ) as overall_network_health_score

FROM telecom_providers tp
LEFT JOIN network_elements ne ON tp.provider_id = ne.provider_id
LEFT JOIN network_topology nt ON ne.element_id = nt.source_element_id OR ne.element_id = nt.target_element_id
LEFT JOIN network_performance np ON ne.element_id = np.element_id
    AND np.measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
LEFT JOIN service_quality sq ON sq.assessment_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN outages o ON tp.provider_id = o.provider_id
    AND o.outage_status IN ('reported', 'investigating', 'repairing')
GROUP BY tp.provider_id, tp.provider_name;

-- Customer service overview
CREATE VIEW customer_service_overview AS
SELECT
    tc.customer_id,
    tc.customer_number,
    tc.first_name || ' ' || tc.last_name as customer_name,

    -- Service details
    COUNT(cs.service_id) as total_services,
    COUNT(CASE WHEN cs.service_status = 'active' THEN 1 END) as active_services,
    STRING_AGG(DISTINCT sp.plan_name, ', ') as service_plans,

    -- Usage summary (last 30 days)
    SUM(ur.data_usage_bytes) / 1073741824 as data_usage_gb_last_30d, -- Convert bytes to GB
    SUM(ur.voice_seconds) / 60 as voice_minutes_last_30d,
    AVG(ur.signal_strength_dbm) as avg_signal_strength,

    -- Billing summary
    AVG(b.total_amount) as avg_monthly_bill,
    MAX(b.due_date) as last_bill_due_date,
    COUNT(CASE WHEN b.bill_status = 'overdue' THEN 1 END) as overdue_bills,

    -- Support interaction
    COUNT(st.ticket_id) as total_support_tickets,
    COUNT(CASE WHEN st.ticket_status IN ('open', 'in_progress') THEN 1 END) as open_tickets,
    AVG(st.customer_satisfaction_rating) as avg_support_rating,

    -- Service quality
    AVG(sq.speed_test_download_mbps) as avg_download_speed,
    AVG(sq.customer_rating) as avg_service_rating,

    -- Customer health score
    ROUND(
        (
            -- Service status (20%)
            CASE WHEN COUNT(CASE WHEN cs.service_status = 'active' THEN 1 END) = COUNT(cs.service_id) THEN 20 ELSE 10 END +
            -- Billing health (20%)
            CASE WHEN COUNT(CASE WHEN b.bill_status = 'overdue' THEN 1 END) = 0 THEN 20 ELSE 5 END +
            -- Support satisfaction (20%)
            COALESCE(AVG(st.customer_satisfaction_rating), 0) / 5 * 20 +
            -- Service quality (20%)
            COALESCE(AVG(sq.customer_rating), 0) / 5 * 20 +
            -- Usage engagement (20%)
            CASE WHEN SUM(ur.data_usage_bytes) > 0 THEN 20 ELSE 5 END
        ), 1
    ) as customer_health_score

FROM telecom_customers tc
LEFT JOIN customer_services cs ON tc.customer_id = cs.customer_id
LEFT JOIN service_plans sp ON cs.plan_id = sp.plan_id
LEFT JOIN usage_records ur ON cs.service_id = ur.service_id
    AND ur.usage_timestamp >= CURRENT_TIMESTAMP - INTERVAL '30 days'
LEFT JOIN bills b ON tc.customer_id = b.customer_id
    AND b.billing_period_start >= CURRENT_DATE - INTERVAL '90 days'
LEFT JOIN support_tickets st ON tc.customer_id = st.customer_id
LEFT JOIN service_quality sq ON cs.service_id = sq.service_id
    AND sq.assessment_date >= CURRENT_DATE - INTERVAL '30 days'
WHERE tc.account_status = 'active'
GROUP BY tc.customer_id, tc.customer_number, tc.first_name, tc.last_name;

-- Service performance analysis
CREATE VIEW service_performance_analysis AS
SELECT
    sp.plan_name,
    sp.plan_type,

    -- Customer adoption
    COUNT(cs.service_id) as total_subscriptions,
    COUNT(CASE WHEN cs.service_status = 'active' THEN 1 END) as active_subscriptions,
    ROUND(
        COUNT(CASE WHEN cs.service_status = 'active' THEN 1 END)::DECIMAL /
        COUNT(cs.service_id) * 100, 1
    ) as activation_rate,

    -- Usage metrics
    AVG(ur.data_usage_bytes / 1073741824) as avg_data_usage_gb_per_user,
    AVG(ur.voice_seconds / 60) as avg_voice_minutes_per_user,
    MAX(ur.data_usage_bytes / 1073741824) as max_data_usage_gb,

    -- Revenue metrics
    SUM(sp.base_price) as total_plan_revenue,
    AVG(sp.base_price) as avg_revenue_per_subscription,

    -- Quality metrics
    AVG(sq.speed_test_download_mbps) as avg_download_speed,
    AVG(sq.customer_rating) as avg_customer_rating,
    COUNT(CASE WHEN sq.speed_test_download_mbps < sp.speed_mbps_down * 0.8 THEN 1 END) as speed_complaint_count,

    -- Churn analysis
    COUNT(CASE WHEN cs.service_status = 'disconnected' THEN 1 END) as disconnected_services,
    ROUND(
        COUNT(CASE WHEN cs.service_status = 'disconnected' THEN 1 END)::DECIMAL /
        COUNT(cs.service_id) * 100, 1
    ) as churn_rate,

    -- Performance score
    ROUND(
        (
            -- Adoption rate (20%)
            LEAST(COUNT(CASE WHEN cs.service_status = 'active' THEN 1 END)::DECIMAL / NULLIF(COUNT(cs.service_id), 0) * 20, 20) +
            -- Quality satisfaction (25%)
            COALESCE(AVG(sq.customer_rating), 0) / 5 * 25 +
            -- Speed performance (25%)
            CASE WHEN AVG(sq.speed_test_download_mbps) >= sp.speed_mbps_down * 0.9 THEN 25
                 WHEN AVG(sq.speed_test_download_mbps) >= sp.speed_mbps_down * 0.7 THEN 15
                 ELSE 5 END +
            -- Usage engagement (15%)
            CASE WHEN AVG(ur.data_usage_bytes) > 0 THEN 15 ELSE 0 END +
            -- Low churn (15%)
            CASE WHEN COUNT(CASE WHEN cs.service_status = 'disconnected' THEN 1 END)::DECIMAL / NULLIF(COUNT(cs.service_id), 0) <= 0.05 THEN 15
                 WHEN COUNT(CASE WHEN cs.service_status = 'disconnected' THEN 1 END)::DECIMAL / NULLIF(COUNT(cs.service_id), 0) <= 0.10 THEN 10
                 ELSE 0 END
        ), 1
    ) as overall_performance_score

FROM service_plans sp
LEFT JOIN customer_services cs ON sp.plan_id = cs.plan_id
LEFT JOIN usage_records ur ON cs.service_id = ur.service_id
    AND ur.usage_timestamp >= CURRENT_TIMESTAMP - INTERVAL '30 days'
LEFT JOIN service_quality sq ON cs.service_id = sq.service_id
    AND sq.assessment_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY sp.plan_id, sp.plan_name, sp.plan_type, sp.speed_mbps_down;

-- ===========================================
-- FUNCTIONS FOR TELECOM OPERATIONS
-- =========================================--

-- Function to calculate customer lifetime value
CREATE OR REPLACE FUNCTION calculate_customer_ltv(customer_uuid UUID)
RETURNS TABLE (
    total_revenue DECIMAL,
    total_cost DECIMAL,
    lifetime_value DECIMAL,
    average_monthly_revenue DECIMAL,
    customer_lifespan_months INTEGER,
    churn_probability DECIMAL
) AS $$
DECLARE
    customer_record telecom_customers%ROWTYPE;
    total_rev DECIMAL := 0;
    avg_monthly_rev DECIMAL := 0;
    lifespan_months INTEGER := 0;
BEGIN
    -- Get customer details
    SELECT * INTO customer_record FROM telecom_customers WHERE customer_id = customer_uuid;

    -- Calculate total revenue
    SELECT COALESCE(SUM(b.total_amount), 0) INTO total_rev
    FROM bills b WHERE b.customer_id = customer_uuid;

    -- Calculate average monthly revenue
    SELECT AVG(b.total_amount) INTO avg_monthly_rev
    FROM bills b WHERE b.customer_id = customer_uuid;

    -- Calculate customer lifespan in months
    SELECT EXTRACT(EPOCH FROM (CURRENT_DATE - customer_record.acquisition_date)) / 2592000 INTO lifespan_months
    FROM telecom_customers WHERE customer_id = customer_uuid;

    -- Return LTV calculation
    RETURN QUERY SELECT
        total_rev,
        0::DECIMAL as total_cost, -- Would integrate with actual cost data
        total_rev as lifetime_value,
        avg_monthly_rev,
        lifespan_months,
        customer_record.churn_risk_score / 10.0 as churn_probability;
END;
$$ LANGUAGE plpgsql;

-- Function to detect network anomalies
CREATE OR REPLACE FUNCTION detect_network_anomalies(element_uuid UUID, analysis_window_hours INTEGER DEFAULT 24)
RETURNS TABLE (
    anomaly_type VARCHAR,
    severity_level VARCHAR,
    description TEXT,
    affected_metrics JSONB,
    recommended_actions JSONB,
    confidence_score DECIMAL
) AS $$
DECLARE
    baseline_record RECORD;
    current_record RECORD;
BEGIN
    -- Get baseline performance (last 7 days average)
    SELECT
        AVG(signal_strength_dbm) as avg_signal,
        AVG(bandwidth_utilization_percentage) as avg_bandwidth,
        AVG(latency_ms) as avg_latency,
        STDDEV(signal_strength_dbm) as signal_stddev,
        STDDEV(bandwidth_utilization_percentage) as bandwidth_stddev,
        STDDEV(latency_ms) as latency_stddev
    INTO baseline_record
    FROM network_performance
    WHERE element_id = element_uuid
      AND measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '7 days'
      AND measurement_timestamp < CURRENT_TIMESTAMP - INTERVAL '1 hour' * analysis_window_hours;

    -- Get current performance
    SELECT
        AVG(signal_strength_dbm) as current_signal,
        AVG(bandwidth_utilization_percentage) as current_bandwidth,
        AVG(latency_ms) as current_latency
    INTO current_record
    FROM network_performance
    WHERE element_id = element_uuid
      AND measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '1 hour' * analysis_window_hours;

    -- Check for signal strength anomaly
    IF ABS(current_record.current_signal - baseline_record.avg_signal) > baseline_record.signal_stddev * 2 THEN
        RETURN QUERY SELECT
            'signal_anomaly'::VARCHAR,
            CASE WHEN ABS(current_record.current_signal - baseline_record.avg_signal) > baseline_record.signal_stddev * 3
                 THEN 'critical' ELSE 'warning' END,
            format('Signal strength deviated by %s dBm from baseline',
                   ROUND(ABS(current_record.current_signal - baseline_record.avg_signal), 1)),
            jsonb_build_object(
                'current_signal', current_record.current_signal,
                'baseline_signal', baseline_record.avg_signal,
                'deviation', current_record.current_signal - baseline_record.avg_signal
            ),
            jsonb_build_array(
                'Check antenna alignment',
                'Inspect cable connections',
                'Schedule maintenance visit'
            ),
            0.85;
    END IF;

    -- Check for bandwidth utilization anomaly
    IF current_record.current_bandwidth > baseline_record.avg_bandwidth + baseline_record.bandwidth_stddev * 2 THEN
        RETURN QUERY SELECT
            'bandwidth_anomaly'::VARCHAR,
            CASE WHEN current_record.current_bandwidth > baseline_record.avg_bandwidth + baseline_record.bandwidth_stddev * 3
                 THEN 'critical' ELSE 'warning' END,
            format('Bandwidth utilization is %s%% above baseline',
                   ROUND(current_record.current_bandwidth - baseline_record.avg_bandwidth, 1)),
            jsonb_build_object(
                'current_bandwidth', current_record.current_bandwidth,
                'baseline_bandwidth', baseline_record.avg_bandwidth
            ),
            jsonb_build_array(
                'Monitor traffic patterns',
                'Consider capacity upgrade',
                'Implement traffic shaping'
            ),
            0.80;
    END IF;

    -- Check for latency anomaly
    IF current_record.current_latency > baseline_record.avg_latency + baseline_record.latency_stddev * 2 THEN
        RETURN QUERY SELECT
            'latency_anomaly'::VARCHAR,
            CASE WHEN current_record.current_latency > baseline_record.avg_latency + baseline_record.latency_stddev * 3
                 THEN 'critical' ELSE 'warning' END,
            format('Latency increased by %s ms from baseline',
                   ROUND(current_record.current_latency - baseline_record.avg_latency, 1)),
            jsonb_build_object(
                'current_latency', current_record.current_latency,
                'baseline_latency', baseline_record.avg_latency
            ),
            jsonb_build_array(
                'Check network routing',
                'Inspect equipment performance',
                'Monitor for congestion'
            ),
            0.75;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to optimize service plans based on usage patterns
CREATE OR REPLACE FUNCTION recommend_service_plan_upgrades()
RETURNS TABLE (
    customer_id UUID,
    current_plan VARCHAR,
    recommended_plan VARCHAR,
    upgrade_reason VARCHAR,
    estimated_savings DECIMAL,
    confidence_score DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        tc.customer_id,
        sp.plan_name as current_plan,
        sp2.plan_name as recommended_plan,

        -- Determine upgrade reason
        CASE
            WHEN AVG(ur.data_usage_bytes / 1073741824) > sp.data_allowance_gb * 0.9 THEN 'data_overage'
            WHEN AVG(sq.speed_test_download_mbps) < sp.speed_mbps_down * 0.7 THEN 'speed_insufficient'
            WHEN tc.churn_risk_score > 7 THEN 'retention_upgrade'
            ELSE 'usage_pattern_upgrade'
        END as upgrade_reason,

        -- Calculate potential savings
        CASE
            WHEN AVG(ur.data_usage_bytes / 1073741824) > sp.data_allowance_gb * 0.9 THEN
                (AVG(ur.data_usage_bytes / 1073741824) - sp.data_allowance_gb) * 10 -- Assume $10/GB overage
            ELSE 0
        END as estimated_savings,

        -- Confidence score
        CASE
            WHEN AVG(ur.data_usage_bytes / 1073741824) > sp.data_allowance_gb THEN 0.9
            WHEN tc.churn_risk_score > 7 THEN 0.8
            ELSE 0.7
        END as confidence_score

    FROM telecom_customers tc
    JOIN customer_services cs ON tc.customer_id = cs.customer_id
    JOIN service_plans sp ON cs.plan_id = sp.plan_id
    LEFT JOIN usage_records ur ON cs.service_id = ur.service_id
        AND ur.usage_timestamp >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    LEFT JOIN service_quality sq ON cs.service_id = sq.service_id
        AND sq.assessment_date >= CURRENT_DATE - INTERVAL '30 days'

    -- Join with potentially better plans
    JOIN service_plans sp2 ON sp2.provider_id = sp.provider_id
        AND sp2.plan_type = sp.plan_type
        AND (
            sp2.data_allowance_gb > sp.data_allowance_gb OR
            sp2.speed_mbps_down > sp.speed_mbps_down
        )
        AND sp2.base_price <= sp.base_price * 1.5 -- Don't recommend plans more than 50% more expensive

    WHERE tc.account_status = 'active'
      AND cs.service_status = 'active'
    GROUP BY tc.customer_id, sp.plan_name, sp2.plan_name, sp.data_allowance_gb,
             sp.speed_mbps_down, tc.churn_risk_score
    HAVING AVG(ur.data_usage_bytes / 1073741824) > sp.data_allowance_gb * 0.8
        OR AVG(sq.speed_test_download_mbps) < sp.speed_mbps_down * 0.8
        OR tc.churn_risk_score > 6;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample telecom provider
INSERT INTO telecom_providers (
    provider_name, provider_code, provider_type,
    service_regions, customer_count, annual_revenue
) VALUES (
    'MetroNet Communications', 'MNC001', 'mobile',
    ARRAY['New York', 'New Jersey', 'Connecticut'], 2500000, 12000000000.00
);

-- Insert sample network element
INSERT INTO network_elements (
    provider_id, element_name, element_code, element_type,
    latitude, longitude, technology, max_capacity, operational_status
) VALUES (
    (SELECT provider_id FROM telecom_providers WHERE provider_code = 'MNC001' LIMIT 1),
    'Manhattan Cell Tower 1', 'CT001', 'cell_tower',
    40.7128, -74.0060, '5G', 1000, 'active'
);

-- Insert sample customer
INSERT INTO telecom_customers (
    customer_number, customer_type, first_name, last_name,
    service_address, acquisition_date, account_type
) VALUES (
    'CUST001', 'individual', 'John', 'Smith',
    '{"street": "123 Main St", "city": "New York", "state": "NY", "zip": "10001"}',
    '2020-03-15', 'postpaid'
);

-- Insert sample service plan
INSERT INTO service_plans (
    provider_id, plan_name, plan_code, plan_type,
    data_allowance_gb, speed_mbps_down, base_price, billing_cycle
) VALUES (
    (SELECT provider_id FROM telecom_providers WHERE provider_code = 'MNC001' LIMIT 1),
    'Unlimited 5G', 'UNL5G', 'mobile_data',
    NULL, 1000, 75.00, 'monthly'
);

-- Insert sample customer service
INSERT INTO customer_services (
    customer_id, plan_id, service_number, service_type,
    activation_date, service_status
) VALUES (
    (SELECT customer_id FROM telecom_customers WHERE customer_number = 'CUST001' LIMIT 1),
    (SELECT plan_id FROM service_plans WHERE plan_code = 'UNL5G' LIMIT 1),
    '+1-555-0123', 'mobile',
    '2020-03-15', 'active'
);

-- Insert sample usage record
INSERT INTO usage_records (
    service_id, data_usage_bytes, signal_strength_dbm,
    connection_type, network_element_id
) VALUES (
    (SELECT service_id FROM customer_services WHERE service_number = '+1-555-0123' LIMIT 1),
    2147483648, -65, '5G',
    (SELECT element_id FROM network_elements WHERE element_code = 'CT001' LIMIT 1)
);

-- Insert sample bill
INSERT INTO bills (
    customer_id, billing_period_start, billing_period_end,
    due_date, service_charges, total_amount
) VALUES (
    (SELECT customer_id FROM telecom_customers WHERE customer_number = 'CUST001' LIMIT 1),
    '2024-01-01', '2024-01-31',
    '2024-02-15', 75.00, 87.38
);

-- This telecommunications schema provides comprehensive infrastructure for telecom operations,
-- network management, customer service, and regulatory compliance.
