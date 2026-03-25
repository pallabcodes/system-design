-- Energy & Utilities Management Database Schema
-- Comprehensive schema for energy utilities, smart grid management, and utility operations

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "postgis"; -- For geographic utility coverage
CREATE EXTENSION IF NOT EXISTS "timescaledb"; -- For time-series data

-- ===========================================
-- UTILITY INFRASTRUCTURE MANAGEMENT
-- ===========================================

CREATE TABLE utilities (
    utility_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    utility_name VARCHAR(255) NOT NULL,
    utility_code VARCHAR(20) UNIQUE NOT NULL,

    -- Utility Details
    utility_type VARCHAR(30) CHECK (utility_type IN (
        'electric', 'gas', 'water', 'wastewater', 'telecom', 'cable'
    )),
    service_area GEOGRAPHY(MULTIPOLYGON, 4326), -- Geographic service area

    -- Regulatory Information
    regulatory_agency VARCHAR(100),
    regulatory_id VARCHAR(50),
    license_number VARCHAR(100),
    license_expiry_date DATE,

    -- Operational Details
    service_territory VARCHAR(255),
    customer_count INTEGER,
    peak_demand_mw DECIMAL(10,2), -- For electric utilities

    -- Financial Information
    rate_base DECIMAL(15,2),
    annual_revenue DECIMAL(15,2),

    -- Contact Information
    headquarters_address JSONB,
    emergency_contact JSONB,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE service_zones (
    zone_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    utility_id UUID NOT NULL REFERENCES utilities(utility_id),

    -- Zone Definition
    zone_name VARCHAR(100) NOT NULL,
    zone_code VARCHAR(20) UNIQUE NOT NULL,
    zone_boundary GEOGRAPHY(MULTIPOLYGON, 4326),

    -- Zone Characteristics
    zone_type VARCHAR(30) CHECK (zone_type IN ('residential', 'commercial', 'industrial', 'rural', 'urban')),
    customer_density INTEGER, -- Customers per square km
    infrastructure_age_years INTEGER,

    -- Service Levels
    voltage_level VARCHAR(20), -- For electric: 120V, 240V, 480V, etc.
    pressure_level VARCHAR(20), -- For gas/water: low, medium, high
    service_quality_rating DECIMAL(3,1),

    -- Operational Data
    peak_load_mw DECIMAL(8,2),
    total_customers INTEGER,
    service_outage_frequency DECIMAL(5,2), -- Outages per year

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE infrastructure_assets (
    asset_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    utility_id UUID NOT NULL REFERENCES utilities(utility_id),

    -- Asset Identification
    asset_number VARCHAR(30) UNIQUE NOT NULL,
    asset_name VARCHAR(255),
    asset_type VARCHAR(50) CHECK (asset_type IN (
        'transformer', 'substation', 'power_line', 'generator',
        'pipeline', 'pump_station', 'treatment_plant', 'meter',
        'pole', 'switchgear', 'cable', 'valve', 'tank'
    )),

    -- Location and Geography
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),
    address JSONB,
    service_zone_id UUID REFERENCES service_zones(zone_id),

    -- Asset Specifications
    manufacturer VARCHAR(100),
    model_number VARCHAR(100),
    serial_number VARCHAR(100),
    installation_date DATE,
    rated_capacity DECIMAL(12,2), -- MW, gallons, etc.
    rated_voltage VARCHAR(20),
    rated_pressure DECIMAL(8,2),

    -- Maintenance and Lifecycle
    maintenance_schedule JSONB DEFAULT '{}',
    last_maintenance_date DATE,
    next_maintenance_date DATE,
    expected_lifespan_years INTEGER,
    replacement_cost DECIMAL(12,2),

    -- Operational Status
    asset_status VARCHAR(30) CHECK (asset_status IN (
        'operational', 'maintenance', 'repair', 'failed', 'decommissioned'
    )),
    operational_since DATE,
    criticality_level VARCHAR(10) CHECK (criticality_level IN ('low', 'medium', 'high', 'critical')),

    -- Monitoring
    monitoring_enabled BOOLEAN DEFAULT FALSE,
    sensor_count INTEGER DEFAULT 0,
    last_reading_timestamp TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- CUSTOMER AND SERVICE MANAGEMENT
-- ===========================================

CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_number VARCHAR(20) UNIQUE NOT NULL,

    -- Customer Information
    customer_type VARCHAR(20) CHECK (customer_type IN ('residential', 'commercial', 'industrial', 'agricultural')),
    business_name VARCHAR(255),
    contact_person VARCHAR(255),
    email VARCHAR(255),
    phone VARCHAR(20),

    -- Service Address
    service_address JSONB NOT NULL,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),

    -- Service Details
    service_start_date DATE,
    service_status VARCHAR(20) DEFAULT 'active' CHECK (service_status IN ('active', 'inactive', 'suspended', 'disconnected')),
    service_zone_id UUID REFERENCES service_zones(zone_id),

    -- Account Information
    account_balance DECIMAL(10,2) DEFAULT 0,
    credit_rating VARCHAR(10) CHECK (credit_rating IN ('excellent', 'good', 'fair', 'poor')),
    payment_method VARCHAR(30) CHECK (payment_method IN ('ach', 'check', 'credit_card', 'cash')),

    -- Usage Profile
    average_monthly_usage DECIMAL(10,2),
    peak_usage_month VARCHAR(20),
    usage_stability_rating DECIMAL(3,1), -- 1-5 scale

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE service_accounts (
    account_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Account Details
    account_number VARCHAR(30) UNIQUE NOT NULL,
    account_type VARCHAR(30) CHECK (account_type IN ('electric', 'gas', 'water', 'dual_fuel', 'bundled')),

    -- Meter Information
    meter_number VARCHAR(30) UNIQUE,
    meter_type VARCHAR(30) CHECK (meter_type IN ('analog', 'digital', 'smart_meter', 'ami')),
    meter_installation_date DATE,
    meter_location JSONB,

    -- Service Details
    service_voltage VARCHAR(20),
    service_pressure DECIMAL(6,2),
    contracted_demand_kw DECIMAL(8,2), -- For commercial/industrial

    -- Billing Information
    rate_schedule VARCHAR(50),
    billing_cycle VARCHAR(20) CHECK (billing_cycle IN ('monthly', 'bimonthly', 'quarterly')),
    bill_delivery_method VARCHAR(20) CHECK (bill_delivery_method IN ('mail', 'email', 'online')),

    -- Account Status
    account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN ('active', 'inactive', 'pending_activation', 'pending_disconnection')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- METERING AND USAGE DATA
-- =========================================--

CREATE TABLE meter_readings (
    reading_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES service_accounts(account_id),
    meter_number VARCHAR(30) NOT NULL,

    -- Reading Details
    reading_date DATE NOT NULL DEFAULT CURRENT_DATE,
    reading_time TIME NOT NULL DEFAULT CURRENT_TIME,
    reading_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Consumption Data
    consumption_kwh DECIMAL(10,2), -- Electricity
    consumption_therms DECIMAL(10,2), -- Gas
    consumption_gallons DECIMAL(12,2), -- Water

    -- Meter Details
    meter_reading DECIMAL(12,2) NOT NULL,
    previous_reading DECIMAL(12,2),
    reading_type VARCHAR(20) CHECK (reading_type IN ('actual', 'estimated', 'final', 'initial')),

    -- Quality Metrics
    reading_quality VARCHAR(20) CHECK (reading_quality IN ('good', 'estimated', 'tampered', 'faulty')),
    data_source VARCHAR(20) CHECK (data_source IN ('manual', 'automated', 'ami', 'estimated')),

    -- Validation
    reading_status VARCHAR(20) DEFAULT 'valid' CHECK (reading_status IN ('valid', 'invalid', 'flagged', 'corrected')),
    validation_notes TEXT,

    -- Metadata
    read_by UUID, -- Meter reader ID
    reading_method VARCHAR(30) CHECK (reading_method IN ('walk_by', 'drive_by', 'ami', 'customer_portal')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (reading_date);

-- Create partitions for meter readings (example for 2024)
CREATE TABLE meter_readings_2024_01 PARTITION OF meter_readings
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE meter_readings_2024_02 PARTITION OF meter_readings
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- ===========================================
-- BILLING AND FINANCIAL MANAGEMENT
-- =========================================--

CREATE TABLE rate_schedules (
    rate_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    utility_id UUID NOT NULL REFERENCES utilities(utility_id),

    -- Rate Details
    rate_schedule_code VARCHAR(20) UNIQUE NOT NULL,
    rate_schedule_name VARCHAR(100) NOT NULL,
    rate_schedule_type VARCHAR(30) CHECK (rate_schedule_type IN (
        'residential', 'commercial', 'industrial', 'time_of_use', 'demand'
    )),

    -- Rate Structure
    base_rate DECIMAL(6,4), -- $/kWh, $/therm, $/gallon
    tiered_rates JSONB DEFAULT '[]', -- For tiered pricing structures
    demand_charge DECIMAL(8,2), -- $/kW for demand charges
    time_of_use_rates JSONB DEFAULT '[]', -- Peak, off-peak, shoulder rates

    -- Additional Charges
    service_charge DECIMAL(6,2), -- Monthly service fee
    delivery_charge DECIMAL(6,2), -- Distribution charge
    taxes_and_fees JSONB DEFAULT '{}',

    -- Effective Dates
    effective_date DATE NOT NULL,
    expiration_date DATE,

    -- Regulatory Approval
    regulatory_approval_date DATE,
    regulatory_approval_number VARCHAR(50),

    -- Status
    rate_status VARCHAR(20) DEFAULT 'active' CHECK (rate_status IN ('active', 'pending', 'expired', 'superseded')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE bills (
    bill_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES service_accounts(account_id),

    -- Billing Period
    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,
    bill_date DATE DEFAULT CURRENT_DATE,
    due_date DATE NOT NULL,

    -- Consumption Details
    usage_kwh DECIMAL(10,2),
    usage_therms DECIMAL(10,2),
    usage_gallons DECIMAL(12,2),
    peak_demand_kw DECIMAL(8,2),

    -- Billing Amounts
    energy_charge DECIMAL(8,2),
    demand_charge DECIMAL(8,2),
    service_charge DECIMAL(8,2),
    delivery_charge DECIMAL(8,2),
    taxes DECIMAL(8,2),
    total_amount DECIMAL(8,2) NOT NULL,

    -- Bill Details
    rate_schedule_used VARCHAR(20),
    billing_status VARCHAR(20) DEFAULT 'unpaid' CHECK (billing_status IN ('unpaid', 'paid', 'overdue', 'credit', 'adjusted')),
    payment_reference VARCHAR(100),

    -- Adjustments and Credits
    adjustments DECIMAL(8,2) DEFAULT 0,
    credits DECIMAL(8,2) DEFAULT 0,
    previous_balance DECIMAL(8,2) DEFAULT 0,

    -- Late Fees and Collections
    late_fee_applied DECIMAL(6,2) DEFAULT 0,
    collection_status VARCHAR(20) CHECK (collection_status IN ('current', 'past_due', 'collections', 'write_off')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (billing_period_start < billing_period_end),
    CHECK (bill_date <= due_date)
);

CREATE TABLE payments (
    payment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES service_accounts(account_id),

    -- Payment Details
    payment_date DATE DEFAULT CURRENT_DATE,
    payment_amount DECIMAL(10,2) NOT NULL,
    payment_method VARCHAR(30) CHECK (payment_method IN ('check', 'ach', 'credit_card', 'cash', 'online')),

    -- Payment Processing
    payment_reference VARCHAR(100), -- Check number, transaction ID
    processing_fee DECIMAL(4,2) DEFAULT 0,

    -- Bill Allocation
    bills_paid JSONB DEFAULT '[]', -- Array of bill IDs and amounts applied

    -- Status and Reconciliation
    payment_status VARCHAR(20) DEFAULT 'processed' CHECK (payment_status IN ('pending', 'processed', 'failed', 'reversed')),
    reconciled BOOLEAN DEFAULT FALSE,
    reconciliation_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (payment_amount > 0)
);

-- ===========================================
-- OUTAGE AND SERVICE MANAGEMENT
-- =========================================--

CREATE TABLE outages (
    outage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    utility_id UUID NOT NULL REFERENCES utilities(utility_id),

    -- Outage Details
    outage_number VARCHAR(30) UNIQUE NOT NULL,
    outage_type VARCHAR(30) CHECK (outage_type IN (
        'planned_maintenance', 'emergency_repair', 'equipment_failure',
        'weather_related', 'construction_damage', 'overload'
    )),

    -- Geographic Impact
    affected_area GEOGRAPHY(MULTIPOLYGON, 4326),
    affected_customers INTEGER,
    affected_accounts UUID[], -- Array of affected account IDs

    -- Timeline
    outage_start TIMESTAMP WITH TIME ZONE,
    estimated_restoration TIMESTAMP WITH TIME ZONE,
    actual_restoration TIMESTAMP WITH TIME ZONE,

    -- Impact Assessment
    outage_cause TEXT,
    affected_infrastructure UUID[], -- Array of affected asset IDs
    estimated_load_lost_mw DECIMAL(8,2),

    -- Restoration Details
    restoration_crew_assigned UUID[], -- Array of crew IDs
    restoration_steps TEXT[],
    restoration_notes TEXT,

    -- Status and Communication
    outage_status VARCHAR(20) DEFAULT 'reported' CHECK (outage_status IN (
        'reported', 'confirmed', 'crew_dispatched', 'repairing', 'restored', 'closed'
    )),
    communication_status VARCHAR(20) CHECK (communication_status IN (
        'notified', 'updating', 'resolved'
    )),

    -- Customer Impact
    customer_notifications_sent INTEGER DEFAULT 0,
    estimated_cost DECIMAL(10,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE outage_updates (
    update_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    outage_id UUID NOT NULL REFERENCES outages(outage_id) ON DELETE CASCADE,

    -- Update Details
    update_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    update_message TEXT NOT NULL,
    update_type VARCHAR(20) CHECK (update_type IN ('status_change', 'crew_update', 'restoration_update', 'information')),

    -- Impact Changes
    affected_customers_new INTEGER,
    estimated_restoration_new TIMESTAMP WITH TIME ZONE,

    -- Internal Notes
    internal_notes TEXT,
    updated_by UUID, -- Staff member making the update

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SMART GRID AND IoT MANAGEMENT
-- =========================================--

CREATE TABLE smart_devices (
    device_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID REFERENCES service_accounts(account_id),
    asset_id UUID REFERENCES infrastructure_assets(asset_id),

    -- Device Details
    device_type VARCHAR(30) CHECK (device_type IN (
        'smart_meter', 'sensor', 'thermostat', 'ev_charger',
        'solar_inverter', 'battery_storage', 'load_controller'
    )),
    device_model VARCHAR(100),
    serial_number VARCHAR(100) UNIQUE,

    -- Installation
    installation_date DATE,
    installation_location JSONB,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),

    -- Connectivity
    communication_protocol VARCHAR(30) CHECK (communication_protocol IN ('zigbee', 'wifi', 'cellular', 'powerline', 'rf_mesh')),
    network_address VARCHAR(100),
    firmware_version VARCHAR(20),

    -- Operational Status
    device_status VARCHAR(20) DEFAULT 'active' CHECK (device_status IN (
        'active', 'inactive', 'maintenance', 'faulty', 'offline'
    )),
    last_communication TIMESTAMP WITH TIME ZONE,
    battery_level DECIMAL(5,2), -- For battery-powered devices

    -- Configuration
    device_configuration JSONB DEFAULT '{}',
    alert_thresholds JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sensor_readings (
    reading_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id UUID NOT NULL REFERENCES smart_devices(device_id),

    -- Reading Details
    reading_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    reading_type VARCHAR(30) CHECK (reading_type IN (
        'voltage', 'current', 'power', 'temperature', 'pressure',
        'flow_rate', 'quality', 'vibration', 'noise', 'humidity'
    )),

    -- Measurement Values
    numeric_value DECIMAL(12,4),
    string_value VARCHAR(100),
    boolean_value BOOLEAN,

    -- Quality and Validation
    reading_quality VARCHAR(20) CHECK (reading_quality IN ('good', 'suspect', 'bad')),
    validation_status VARCHAR(20) CHECK (validation_status IN ('valid', 'invalid', 'estimated')),

    -- Metadata
    units VARCHAR(20),
    sensor_calibration_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (reading_timestamp);

-- Create partitions for sensor readings
CREATE TABLE sensor_readings_2024_01 PARTITION OF sensor_readings
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- ===========================================
-- ANALYTICS AND REPORTING
-- =========================================--

CREATE TABLE usage_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_period VARCHAR(10) CHECK (report_period IN ('daily', 'weekly', 'monthly', 'quarterly', 'yearly')),

    -- Usage Metrics
    total_consumption_kwh DECIMAL(15,2) DEFAULT 0,
    total_consumption_therms DECIMAL(15,2) DEFAULT 0,
    total_consumption_gallons DECIMAL(18,2) DEFAULT 0,

    -- Customer Metrics
    total_customers INTEGER DEFAULT 0,
    average_usage_per_customer DECIMAL(10,2),
    peak_demand_mw DECIMAL(8,2),

    -- Efficiency Metrics
    system_losses_percentage DECIMAL(5,2),
    renewable_energy_percentage DECIMAL(5,2),
    carbon_emissions_tons DECIMAL(12,2),

    -- Reliability Metrics
    saidi_hours DECIMAL(6,2), -- System Average Interruption Duration Index
    saifi_incidents DECIMAL(6,2), -- System Average Interruption Frequency Index
    average_restoration_time_hours DECIMAL(5,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (report_date, report_period)
);

CREATE TABLE customer_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Time Dimensions
    report_date DATE NOT NULL,

    -- Usage Patterns
    monthly_consumption DECIMAL(10,2),
    usage_trend_percentage DECIMAL(6,2), -- Month-over-month change
    peak_usage_hour INTEGER,

    -- Billing Analytics
    average_monthly_bill DECIMAL(8,2),
    payment_history_score DECIMAL(3,1), -- 1-5 scale

    -- Conservation Metrics
    conservation_score DECIMAL(3,1),
    energy_efficiency_rating VARCHAR(10) CHECK (energy_efficiency_rating IN ('excellent', 'good', 'fair', 'poor')),

    -- Smart Device Usage
    smart_devices_count INTEGER DEFAULT 0,
    automation_level DECIMAL(3,1), -- How automated their usage is

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (customer_id, report_date)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Geographic indexes
CREATE INDEX idx_utilities_service_area ON utilities USING gist (service_area);
CREATE INDEX idx_service_zones_boundary ON service_zones USING gist (zone_boundary);
CREATE INDEX idx_infrastructure_assets_location ON infrastructure_assets USING gist (geolocation);
CREATE INDEX idx_customers_location ON customers USING gist (geolocation);

-- Meter reading indexes
CREATE INDEX idx_meter_readings_account_date ON meter_readings (account_id, reading_date DESC);
CREATE INDEX idx_meter_readings_meter_date ON meter_readings (meter_number, reading_date DESC);

-- Billing indexes
CREATE INDEX idx_bills_account_period ON bills (account_id, billing_period_start, billing_period_end);
CREATE INDEX idx_bills_due_date ON bills (due_date) WHERE billing_status = 'unpaid';
CREATE INDEX idx_payments_account_date ON payments (account_id, payment_date DESC);

-- Outage indexes
CREATE INDEX idx_outages_utility_status ON outages (utility_id, outage_status);
CREATE INDEX idx_outages_affected_area ON outages USING gist (affected_area);
CREATE INDEX idx_outage_updates_outage_time ON outage_updates (outage_id, update_timestamp DESC);

-- Smart device indexes
CREATE INDEX idx_smart_devices_account ON smart_devices (account_id);
CREATE INDEX idx_sensor_readings_device_time ON sensor_readings (device_id, reading_timestamp DESC);

-- ===========================================
-- USEFUL VIEWS
-- =========================================--

-- Utility performance dashboard
CREATE VIEW utility_performance AS
SELECT
    u.utility_id,
    u.utility_name,
    u.utility_type,

    -- Service metrics
    COUNT(DISTINCT c.customer_id) as total_customers,
    COUNT(DISTINCT sa.account_id) as total_accounts,
    SUM(b.total_amount) as monthly_revenue,

    -- Operational metrics
    COUNT(DISTINCT ia.asset_id) as total_assets,
    COUNT(CASE WHEN ia.asset_status = 'operational' THEN 1 END) as operational_assets,
    ROUND(
        COUNT(CASE WHEN ia.asset_status = 'operational' THEN 1 END)::DECIMAL /
        COUNT(ia.asset_id) * 100, 1
    ) as asset_availability_percentage,

    -- Reliability metrics
    COUNT(o.outage_id) as total_outages_this_month,
    AVG(EXTRACT(EPOCH FROM (o.actual_restoration - o.outage_start))/3600) as avg_restoration_time_hours,
    SUM(o.affected_customers) as total_customers_affected,

    -- Usage metrics
    SUM(mr.consumption_kwh) as total_kwh_consumed,
    AVG(mr.consumption_kwh) as avg_kwh_per_customer,

    -- Financial metrics
    AVG(b.total_amount) as avg_bill_amount,
    COUNT(CASE WHEN b.billing_status = 'paid' THEN 1 END)::DECIMAL /
    COUNT(b.bill_id) * 100 as payment_rate_percentage

FROM utilities u
LEFT JOIN customers c ON u.utility_id = u.utility_id -- This needs proper relationship
LEFT JOIN service_accounts sa ON c.customer_id = sa.customer_id
LEFT JOIN bills b ON sa.account_id = sa.account_id
    AND b.billing_period_start >= DATE_TRUNC('month', CURRENT_DATE)
LEFT JOIN infrastructure_assets ia ON u.utility_id = ia.utility_id
LEFT JOIN outages o ON u.utility_id = o.utility_id
    AND o.outage_start >= DATE_TRUNC('month', CURRENT_DATE)
LEFT JOIN meter_readings mr ON sa.account_id = mr.account_id
    AND mr.reading_date >= DATE_TRUNC('month', CURRENT_DATE)
GROUP BY u.utility_id, u.utility_name, u.utility_type;

-- Customer usage analysis
CREATE VIEW customer_usage_analysis AS
SELECT
    c.customer_id,
    c.customer_number,
    c.customer_type,
    c.service_status,

    -- Usage statistics
    AVG(mr.consumption_kwh) as avg_monthly_kwh,
    MAX(mr.consumption_kwh) as peak_monthly_kwh,
    STDDEV(mr.consumption_kwh) as usage_volatility,

    -- Billing statistics
    AVG(b.total_amount) as avg_monthly_bill,
    MAX(b.total_amount) as highest_bill,
    COUNT(CASE WHEN b.billing_status = 'overdue' THEN 1 END) as overdue_bills_count,

    -- Trends
    CASE
        WHEN AVG(mr.consumption_kwh) > LAG(AVG(mr.consumption_kwh)) OVER (ORDER BY DATE_TRUNC('month', mr.reading_date)) THEN 'increasing'
        WHEN AVG(mr.consumption_kwh) < LAG(AVG(mr.consumption_kwh)) OVER (ORDER BY DATE_TRUNC('month', mr.reading_date)) THEN 'decreasing'
        ELSE 'stable'
    END as usage_trend,

    -- Efficiency metrics
    CASE
        WHEN AVG(mr.consumption_kwh) < 500 THEN 'efficient'
        WHEN AVG(mr.consumption_kwh) < 1000 THEN 'average'
        ELSE 'high_usage'
    END as efficiency_rating,

    -- Account health
    CASE
        WHEN COUNT(CASE WHEN b.billing_status = 'overdue' THEN 1 END) = 0 THEN 'excellent'
        WHEN COUNT(CASE WHEN b.billing_status = 'overdue' THEN 1 END) <= 2 THEN 'good'
        ELSE 'concerning'
    END as account_health

FROM customers c
LEFT JOIN service_accounts sa ON c.customer_id = sa.customer_id
LEFT JOIN meter_readings mr ON sa.account_id = mr.account_id
    AND mr.reading_date >= CURRENT_DATE - INTERVAL '12 months'
LEFT JOIN bills b ON sa.account_id = sa.account_id
    AND b.billing_period_start >= CURRENT_DATE - INTERVAL '12 months'
WHERE c.service_status = 'active'
GROUP BY c.customer_id, c.customer_number, c.customer_type, c.service_status;

-- Outage impact analysis
CREATE VIEW outage_impact_analysis AS
SELECT
    o.outage_id,
    o.outage_number,
    o.outage_type,
    u.utility_name,

    -- Impact metrics
    o.affected_customers,
    EXTRACT(EPOCH FROM (o.actual_restoration - o.outage_start))/3600 as duration_hours,
    o.affected_customers * EXTRACT(EPOCH FROM (o.actual_restoration - o.outage_start))/3600 as customer_hours_affected,

    -- Restoration performance
    CASE
        WHEN EXTRACT(EPOCH FROM (o.actual_restoration - o.outage_start))/3600 <= 1 THEN 'excellent'
        WHEN EXTRACT(EPOCH FROM (o.actual_restoration - o.outage_start))/3600 <= 4 THEN 'good'
        WHEN EXTRACT(EPOCH FROM (o.actual_restoration - o.outage_start))/3600 <= 24 THEN 'acceptable'
        ELSE 'poor'
    END as restoration_performance,

    -- Economic impact estimate
    o.affected_customers * 50 as estimated_business_impact_dollars, -- $50/hour per customer

    -- Frequency analysis
    COUNT(*) OVER (PARTITION BY u.utility_id ORDER BY o.outage_start RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) as outages_last_30_days,

    -- Trend analysis
    CASE
        WHEN o.actual_restoration <= o.estimated_restoration THEN 'better_than_estimated'
        WHEN o.actual_restoration <= o.estimated_restoration + INTERVAL '2 hours' THEN 'within_tolerance'
        ELSE 'worse_than_estimated'
    END as estimation_accuracy

FROM outages o
JOIN utilities u ON o.utility_id = u.utility_id
WHERE o.outage_status = 'restored'
ORDER BY o.actual_restoration DESC;

-- Smart grid device health
CREATE VIEW smart_device_health AS
SELECT
    sd.device_id,
    sd.device_type,
    sd.device_model,
    c.customer_number,

    -- Connectivity status
    CASE
        WHEN sd.last_communication >= CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 'online'
        WHEN sd.last_communication >= CURRENT_TIMESTAMP - INTERVAL '24 hours' THEN 'recently_online'
        ELSE 'offline'
    END as connectivity_status,

    -- Battery health (for battery-powered devices)
    sd.battery_level,
    CASE
        WHEN sd.battery_level >= 80 THEN 'excellent'
        WHEN sd.battery_level >= 60 THEN 'good'
        WHEN sd.battery_level >= 40 THEN 'fair'
        WHEN sd.battery_level >= 20 THEN 'low'
        ELSE 'critical'
    END as battery_health,

    -- Data quality
    COUNT(sr.reading_id) as total_readings_last_24h,
    COUNT(CASE WHEN sr.reading_quality = 'good' THEN 1 END) as good_readings_last_24h,
    ROUND(
        COUNT(CASE WHEN sr.reading_quality = 'good' THEN 1 END)::DECIMAL /
        NULLIF(COUNT(sr.reading_id), 0) * 100, 1
    ) as data_quality_percentage,

    -- Alert conditions
    CASE WHEN sd.last_communication < CURRENT_TIMESTAMP - INTERVAL '24 hours' THEN TRUE ELSE FALSE END as communication_alert,
    CASE WHEN sd.battery_level < 20 THEN TRUE ELSE FALSE END as battery_alert,
    CASE WHEN (
        COUNT(CASE WHEN sr.reading_quality != 'good' THEN 1 END)::DECIMAL /
        NULLIF(COUNT(sr.reading_id), 0)
    ) > 0.1 THEN TRUE ELSE FALSE END as data_quality_alert

FROM smart_devices sd
LEFT JOIN service_accounts sa ON sd.account_id = sa.account_id
LEFT JOIN customers c ON sa.customer_id = c.customer_id
LEFT JOIN sensor_readings sr ON sd.device_id = sr.device_id
    AND sr.reading_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY sd.device_id, sd.device_type, sd.device_model, c.customer_number,
         sd.last_communication, sd.battery_level;

-- ===========================================
-- FUNCTIONS FOR UTILITY OPERATIONS
-- =========================================--

-- Function to calculate bill amount
CREATE OR REPLACE FUNCTION calculate_bill_amount(
    account_uuid UUID,
    start_date DATE,
    end_date DATE
)
RETURNS TABLE (
    energy_charge DECIMAL,
    demand_charge DECIMAL,
    service_charge DECIMAL,
    taxes DECIMAL,
    total_amount DECIMAL,
    rate_schedule_used VARCHAR
) AS $$
DECLARE
    account_record service_accounts%ROWTYPE;
    rate_record rate_schedules%ROWTYPE;
    total_kwh DECIMAL := 0;
    peak_kw DECIMAL := 0;
    billing_days INTEGER;
BEGIN
    -- Get account details
    SELECT * INTO account_record FROM service_accounts WHERE account_id = account_uuid;

    -- Get applicable rate schedule
    SELECT * INTO rate_record FROM rate_schedules
    WHERE utility_id = (SELECT utility_id FROM service_zones WHERE zone_id = account_record.service_zone_id)
      AND rate_status = 'active'
      AND effective_date <= start_date
    ORDER BY effective_date DESC
    LIMIT 1;

    -- Calculate billing period
    billing_days := end_date - start_date + 1;

    -- Get consumption data
    SELECT COALESCE(SUM(consumption_kwh), 0), COALESCE(MAX(consumption_kwh / 24), 0) -- Rough peak calculation
    INTO total_kwh, peak_kw
    FROM meter_readings
    WHERE account_id = account_uuid
      AND reading_date BETWEEN start_date AND end_date;

    -- Calculate charges
    RETURN QUERY SELECT
        total_kwh * rate_record.base_rate, -- Energy charge
        COALESCE(account_record.contracted_demand_kw, peak_kw) * rate_record.demand_charge, -- Demand charge
        rate_record.service_charge * (billing_days / 30.0), -- Service charge (prorated)
        (total_kwh * rate_record.base_rate + COALESCE(account_record.contracted_demand_kw, peak_kw) * rate_record.demand_charge) * 0.08, -- 8% tax
        (total_kwh * rate_record.base_rate) + (COALESCE(account_record.contracted_demand_kw, peak_kw) * rate_record.demand_charge) +
        (rate_record.service_charge * (billing_days / 30.0)) +
        ((total_kwh * rate_record.base_rate + COALESCE(account_record.contracted_demand_kw, peak_kw) * rate_record.demand_charge) * 0.08),
        rate_record.rate_schedule_code;
END;
$$ LANGUAGE plpgsql;

-- Function to detect usage anomalies
CREATE OR REPLACE FUNCTION detect_usage_anomalies(
    account_uuid UUID,
    analysis_period_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    anomaly_type VARCHAR,
    anomaly_description TEXT,
    severity_score DECIMAL,
    recommended_action TEXT,
    confidence_level DECIMAL
) AS $$
DECLARE
    avg_usage DECIMAL;
    std_dev_usage DECIMAL;
    current_usage DECIMAL;
    recent_readings RECORD;
BEGIN
    -- Calculate baseline usage
    SELECT AVG(consumption_kwh), STDDEV(consumption_kwh)
    INTO avg_usage, std_dev_usage
    FROM meter_readings
    WHERE account_id = account_uuid
      AND reading_date >= CURRENT_DATE - INTERVAL '90 days'
      AND reading_date < CURRENT_DATE - INTERVAL '1 day' * analysis_period_days;

    -- Get recent usage
    SELECT consumption_kwh INTO current_usage
    FROM meter_readings
    WHERE account_id = account_uuid
      AND reading_date >= CURRENT_DATE - INTERVAL '1 day' * analysis_period_days
    ORDER BY reading_date DESC
    LIMIT 1;

    -- Check for high usage anomaly
    IF current_usage > avg_usage + (2 * std_dev_usage) THEN
        RETURN QUERY SELECT
            'high_usage'::VARCHAR,
            format('Usage of %s kWh is %s%% above normal', current_usage, ROUND((current_usage - avg_usage) / avg_usage * 100, 1)),
            LEAST((current_usage - avg_usage) / NULLIF(std_dev_usage, 0), 5.0),
            'Schedule energy audit or inspect for leaks'::TEXT,
            0.85;
    END IF;

    -- Check for zero usage anomaly
    IF current_usage = 0 AND avg_usage > 0 THEN
        RETURN QUERY SELECT
            'zero_usage'::VARCHAR,
            'No usage recorded when historical average is above zero'::TEXT,
            4.0,
            'Check meter functionality or investigate potential bypass'::TEXT,
            0.95;
    END IF;

    -- Check for unusual patterns
    SELECT COUNT(*) as zero_days,
           AVG(consumption_kwh) as period_avg
    INTO recent_readings
    FROM meter_readings
    WHERE account_id = account_uuid
      AND reading_date >= CURRENT_DATE - INTERVAL '1 day' * analysis_period_days;

    IF recent_readings.zero_days > analysis_period_days * 0.5 THEN
        RETURN QUERY SELECT
            'extended_zero_usage'::VARCHAR,
            format('%s days of zero usage in last %s days', recent_readings.zero_days, analysis_period_days),
            3.5,
            'Investigate meter or service connection'::TEXT,
            0.90;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to predict peak demand
CREATE OR REPLACE FUNCTION predict_peak_demand(
    zone_uuid UUID,
    prediction_date DATE DEFAULT CURRENT_DATE,
    prediction_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
    predicted_peak_mw DECIMAL,
    confidence_interval_lower DECIMAL,
    confidence_interval_upper DECIMAL,
    prediction_factors JSONB,
    risk_level VARCHAR
) AS $$
DECLARE
    historical_peak DECIMAL;
    avg_demand DECIMAL;
    weather_factor DECIMAL := 1.0;
    event_factor DECIMAL := 1.0;
    seasonal_factor DECIMAL := 1.0;
BEGIN
    -- Get historical data
    SELECT MAX(consumption_kwh / 1000) as peak_mw, AVG(consumption_kwh / 1000) as avg_mw
    INTO historical_peak, avg_demand
    FROM meter_readings mr
    JOIN service_accounts sa ON mr.account_id = sa.account_id
    WHERE sa.service_zone_id = zone_uuid
      AND DATE_TRUNC('month', mr.reading_date) = DATE_TRUNC('month', prediction_date)
      AND EXTRACT(YEAR FROM mr.reading_date) < EXTRACT(YEAR FROM prediction_date);

    -- Apply weather factor (simplified)
    IF EXTRACT(MONTH FROM prediction_date) IN (6, 7, 8) THEN
        weather_factor := 1.2; -- Summer peak
    ELSIF EXTRACT(MONTH FROM prediction_date) IN (12, 1, 2) THEN
        weather_factor := 1.1; -- Winter peak
    END IF;

    -- Apply event factor (simplified - would integrate with calendar API)
    IF EXTRACT(DOW FROM prediction_date) IN (0, 6) THEN
        event_factor := 0.9; -- Weekend reduction
    END IF;

    -- Calculate prediction
    RETURN QUERY SELECT
        historical_peak * weather_factor * event_factor * seasonal_factor,
        historical_peak * weather_factor * event_factor * seasonal_factor * 0.8,
        historical_peak * weather_factor * event_factor * seasonal_factor * 1.2,
        jsonb_build_object(
            'weather_factor', weather_factor,
            'event_factor', event_factor,
            'seasonal_factor', seasonal_factor,
            'historical_peak', historical_peak
        ),
        CASE
            WHEN historical_peak * weather_factor * event_factor * seasonal_factor > historical_peak * 1.5 THEN 'high'
            WHEN historical_peak * weather_factor * event_factor * seasonal_factor > historical_peak * 1.2 THEN 'medium'
            ELSE 'low'
        END;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample utility
INSERT INTO utilities (
    utility_name, utility_code, utility_type,
    service_territory, customer_count
) VALUES (
    'Metro Power & Light', 'MPL001', 'electric',
    'Greater Metropolitan Area', 500000
);

-- Insert sample service zone
INSERT INTO service_zones (
    utility_id, zone_name, zone_code, zone_type,
    voltage_level, customer_density
) VALUES (
    (SELECT utility_id FROM utilities WHERE utility_code = 'MPL001' LIMIT 1),
    'Downtown District', 'ZONE001', 'commercial',
    '480V', 5000
);

-- Insert sample customer
INSERT INTO customers (
    customer_number, customer_type, contact_person,
    service_address, service_start_date
) VALUES (
    'CUST001', 'residential', 'John Smith',
    '{"street": "123 Main St", "city": "Anytown", "state": "CA", "zip": "12345"}',
    '2020-01-15'
);

-- Insert sample service account
INSERT INTO service_accounts (
    customer_id, account_number, account_type,
    meter_number, rate_schedule
) VALUES (
    (SELECT customer_id FROM customers WHERE customer_number = 'CUST001' LIMIT 1),
    'ACCT001', 'electric',
    'METER001', 'RESIDENTIAL_STANDARD'
);

-- Insert sample meter reading
INSERT INTO meter_readings (
    account_id, meter_number, consumption_kwh,
    meter_reading, reading_type
) VALUES (
    (SELECT account_id FROM service_accounts WHERE account_number = 'ACCT001' LIMIT 1),
    'METER001', 850.50,
    12500.00, 'actual'
);

-- Insert sample bill
INSERT INTO bills (
    account_id, billing_period_start, billing_period_end,
    due_date, usage_kwh, total_amount
) VALUES (
    (SELECT account_id FROM service_accounts WHERE account_number = 'ACCT001' LIMIT 1),
    '2024-01-01', '2024-01-31',
    '2024-02-15', 850.50, 125.75
);

-- This energy utilities schema provides comprehensive infrastructure for utility operations,
-- smart grid management, customer service, and regulatory compliance.
