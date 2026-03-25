-- IoT & Sensor Data Management Database Schema
-- Comprehensive schema for Internet of Things data collection, processing, and analytics

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "timescaledb";  -- For time-series data (if available)
CREATE EXTENSION IF NOT EXISTS "postgis";     -- For geospatial data (if available)

-- ===========================================
-- DEVICE AND SENSOR MANAGEMENT
-- ===========================================

CREATE TABLE device_types (
    device_type_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_type_name VARCHAR(100) NOT NULL,
    device_category VARCHAR(50) NOT NULL CHECK (device_category IN (
        'sensor', 'actuator', 'gateway', 'controller', 'monitor', 'tracker'
    )),
    manufacturer VARCHAR(100),
    model VARCHAR(100),

    -- Technical Specifications
    specifications JSONB DEFAULT '{}', -- CPU, memory, power requirements, etc.
    capabilities TEXT[], -- Array of device capabilities
    supported_protocols TEXT[], -- MQTT, CoAP, HTTP, etc.

    -- Power and Connectivity
    power_type VARCHAR(30) CHECK (power_type IN ('battery', 'wired', 'solar', 'kinetic')),
    battery_life_hours INTEGER,
    connectivity_type VARCHAR(50) CHECK (connectivity_type IN ('wifi', 'bluetooth', 'zigbee', 'lora', 'cellular', 'ethernet')),

    -- Certification and Compliance
    certifications TEXT[], -- FCC, CE, safety certifications
    compliance_standards TEXT[],

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE devices (
    device_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_type_id UUID NOT NULL REFERENCES device_types(device_type_id),

    -- Device Identity
    device_serial_number VARCHAR(100) UNIQUE NOT NULL,
    device_name VARCHAR(255),
    mac_address MACADDR,
    imei VARCHAR(50), -- For cellular devices

    -- Ownership and Location
    owner_id UUID, -- References users or organizations
    location_id UUID, -- References locations

    -- Physical Location (if PostGIS available)
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    altitude DECIMAL(7,1),
    geolocation GEOGRAPHY(POINT, 4326), -- PostGIS geography type

    -- Installation and Configuration
    installation_date DATE,
    firmware_version VARCHAR(50),
    configuration JSONB DEFAULT '{}',

    -- Status and Health
    device_status VARCHAR(30) DEFAULT 'inactive' CHECK (device_status IN (
        'inactive', 'provisioning', 'active', 'maintenance', 'failed', 'decommissioned'
    )),
    last_seen_at TIMESTAMP WITH TIME ZONE,
    last_health_check TIMESTAMP WITH TIME ZONE,

    -- Security
    authentication_key_hash VARCHAR(128), -- Hashed device key
    encryption_enabled BOOLEAN DEFAULT TRUE,

    -- Operational Data
    battery_level DECIMAL(5,2), -- Percentage 0-100
    signal_strength DECIMAL(5,2), -- Signal quality
    temperature DECIMAL(5,2), -- Device temperature

    -- Maintenance
    warranty_expiration DATE,
    maintenance_schedule JSONB DEFAULT '{}',
    next_maintenance_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (battery_level >= 0 AND battery_level <= 100),
    CHECK (signal_strength >= 0 AND signal_strength <= 100)
);

CREATE TABLE sensors (
    sensor_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id UUID NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,

    -- Sensor Details
    sensor_type VARCHAR(50) NOT NULL CHECK (sensor_type IN (
        'temperature', 'humidity', 'pressure', 'motion', 'light', 'sound',
        'vibration', 'proximity', 'gas', 'smoke', 'water', 'current', 'voltage',
        'gps', 'accelerometer', 'gyroscope', 'magnetometer', 'ph', 'conductivity'
    )),
    sensor_name VARCHAR(100),
    sensor_model VARCHAR(100),

    -- Measurement Specifications
    unit_of_measure VARCHAR(20), -- Celsius, Fahrenheit, Pascal, Lux, etc.
    measurement_range_min DECIMAL(15,6),
    measurement_range_max DECIMAL(15,6),
    accuracy DECIMAL(10,6), -- Measurement accuracy
    resolution DECIMAL(10,6), -- Measurement resolution

    -- Configuration
    sampling_rate_hz INTEGER, -- Samples per second
    reporting_interval_seconds INTEGER, -- How often to report data
    calibration_data JSONB DEFAULT '{}',

    -- Status
    sensor_status VARCHAR(20) DEFAULT 'active' CHECK (sensor_status IN ('active', 'inactive', 'calibrating', 'failed')),
    last_calibration_date DATE,

    -- Quality Control
    data_quality_score DECIMAL(3,2), -- 0.00 to 1.00
    outlier_detection_enabled BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- DATA COLLECTION AND STORAGE
-- ===========================================

CREATE TABLE sensor_data (
    data_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sensor_id UUID NOT NULL REFERENCES sensors(sensor_id),
    device_id UUID NOT NULL REFERENCES devices(device_id),

    -- Measurement Data
    measurement_value DECIMAL(15,6) NOT NULL,
    measurement_unit VARCHAR(20) NOT NULL,
    measurement_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Quality and Metadata
    data_quality VARCHAR(20) DEFAULT 'valid' CHECK (data_quality IN ('valid', 'suspect', 'invalid', 'calibration')),
    confidence_level DECIMAL(3,2), -- 0.00 to 1.00
    measurement_metadata JSONB DEFAULT '{}', -- Additional sensor-specific data

    -- Processing Flags
    is_processed BOOLEAN DEFAULT FALSE,
    is_anomaly BOOLEAN DEFAULT FALSE,
    anomaly_score DECIMAL(5,3),

    -- Aggregation Support
    hour_bucket TIMESTAMP WITH TIME ZONE GENERATED ALWAYS AS (
        date_trunc('hour', measurement_timestamp)
    ) STORED,
    day_bucket DATE GENERATED ALWAYS AS (
        measurement_timestamp::DATE
    ) STORED,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (measurement_timestamp);

-- Partitioning by month for time-series data
CREATE TABLE sensor_data_2024_01 PARTITION OF sensor_data
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE sensor_data_2024_02 PARTITION OF sensor_data
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- ===========================================
-- DATA PROCESSING AND ANALYTICS
-- ===========================================

CREATE TABLE data_processing_rules (
    rule_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rule_name VARCHAR(255) NOT NULL,
    rule_description TEXT,

    -- Rule Configuration
    sensor_types TEXT[], -- Applicable sensor types
    conditions JSONB NOT NULL, -- Rule conditions in JSON logic format
    actions JSONB NOT NULL, -- Actions to take when conditions met

    -- Rule Properties
    priority INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    processing_mode VARCHAR(20) DEFAULT 'realtime' CHECK (processing_mode IN ('realtime', 'batch', 'scheduled')),

    -- Performance and Limits
    max_execution_time_ms INTEGER DEFAULT 5000,
    retry_count INTEGER DEFAULT 3,

    -- Audit
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE processed_data (
    processed_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    original_data_id UUID REFERENCES sensor_data(data_id),

    -- Processing Results
    processing_rule_id UUID REFERENCES data_processing_rules(rule_id),
    processing_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Derived Data
    derived_value DECIMAL(15,6),
    derived_unit VARCHAR(20),
    calculation_method VARCHAR(100),

    -- Aggregation Data
    aggregation_type VARCHAR(30) CHECK (aggregation_type IN ('raw', 'averaged', 'summed', 'min', 'max', 'count', 'percentile')),
    aggregation_window INTERVAL, -- 1 hour, 1 day, etc.
    aggregation_count INTEGER, -- Number of data points aggregated

    -- Quality Metrics
    data_quality_score DECIMAL(3,2),
    processing_confidence DECIMAL(3,2),

    -- Storage
    processed_data JSONB DEFAULT '{}', -- Additional processing results

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ALERTS AND NOTIFICATIONS
-- ===========================================

CREATE TABLE alert_rules (
    alert_rule_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rule_name VARCHAR(255) NOT NULL,
    rule_description TEXT,

    -- Rule Conditions
    sensor_ids UUID[], -- Specific sensors to monitor
    sensor_types TEXT[], -- Sensor types to monitor
    conditions JSONB NOT NULL, -- Alert trigger conditions

    -- Alert Configuration
    alert_severity VARCHAR(20) DEFAULT 'medium' CHECK (alert_severity IN ('low', 'medium', 'high', 'critical')),
    alert_message_template TEXT,
    cooldown_period_minutes INTEGER DEFAULT 60, -- Minimum time between alerts

    -- Notification Settings
    notification_channels TEXT[] DEFAULT ARRAY['email'], -- email, sms, webhook, etc.
    notification_recipients JSONB DEFAULT '[]', -- List of recipients

    -- Escalation
    escalation_enabled BOOLEAN DEFAULT FALSE,
    escalation_delay_minutes INTEGER DEFAULT 30,
    escalation_recipients JSONB DEFAULT '[]',

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE alerts (
    alert_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    alert_rule_id UUID NOT NULL REFERENCES alert_rules(alert_rule_id),

    -- Alert Details
    alert_message TEXT NOT NULL,
    alert_severity VARCHAR(20) NOT NULL,
    alert_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Related Entities
    sensor_id UUID REFERENCES sensors(sensor_id),
    device_id UUID REFERENCES devices(device_id),
    data_point_id UUID REFERENCES sensor_data(data_id),

    -- Alert Data
    trigger_value DECIMAL(15,6),
    threshold_value DECIMAL(15,6),
    alert_metadata JSONB DEFAULT '{}',

    -- Status and Resolution
    alert_status VARCHAR(20) DEFAULT 'active' CHECK (alert_status IN ('active', 'acknowledged', 'resolved', 'escalated')),
    acknowledged_by UUID,
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    resolved_by UUID,
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,

    -- Escalation Tracking
    escalation_level INTEGER DEFAULT 0,
    escalated_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- COMMAND AND CONTROL
-- ===========================================

CREATE TABLE device_commands (
    command_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id UUID NOT NULL REFERENCES devices(device_id),

    -- Command Details
    command_type VARCHAR(50) NOT NULL CHECK (command_type IN (
        'reboot', 'firmware_update', 'configuration_change', 'calibration',
        'maintenance_mode', 'data_sync', 'reset', 'shutdown'
    )),
    command_parameters JSONB DEFAULT '{}',

    -- Scheduling
    scheduled_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,

    -- Execution
    execution_status VARCHAR(20) DEFAULT 'pending' CHECK (execution_status IN (
        'pending', 'sent', 'received', 'executing', 'completed', 'failed', 'expired'
    )),
    sent_at TIMESTAMP WITH TIME ZONE,
    received_at TIMESTAMP WITH TIME ZONE,
    executed_at TIMESTAMP WITH TIME ZONE,

    -- Results
    execution_result JSONB DEFAULT '{}',
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,

    -- Audit
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE device_configuration_versions (
    config_version_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id UUID NOT NULL REFERENCES devices(device_id),

    -- Configuration Details
    version_number INTEGER NOT NULL,
    configuration_data JSONB NOT NULL,
    configuration_hash VARCHAR(64), -- SHA-256 hash for integrity

    -- Metadata
    change_reason TEXT,
    applied_at TIMESTAMP WITH TIME ZONE,
    applied_by UUID,

    -- Rollback Support
    previous_version_id UUID REFERENCES device_configuration_versions(config_version_id),
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (device_id, version_number)
);

-- ===========================================
-- FLEET MANAGEMENT AND ORGANIZATION
-- ===========================================

CREATE TABLE organizations (
    organization_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_name VARCHAR(255) NOT NULL,
    organization_type VARCHAR(30) CHECK (organization_type IN ('company', 'department', 'facility', 'project')),

    -- Hierarchy
    parent_organization_id UUID REFERENCES organizations(organization_id),
    hierarchy_level INTEGER DEFAULT 1,

    -- Contact Information
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),

    -- Settings
    timezone VARCHAR(50) DEFAULT 'UTC',
    settings JSONB DEFAULT '{}',

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE device_groups (
    group_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),

    -- Group Details
    group_name VARCHAR(255) NOT NULL,
    group_description TEXT,
    group_type VARCHAR(30) CHECK (group_type IN ('geographic', 'functional', 'environmental', 'maintenance')),

    -- Membership Criteria
    membership_criteria JSONB DEFAULT '{}', -- Auto-membership rules

    -- Settings
    alert_aggregation_enabled BOOLEAN DEFAULT TRUE,
    data_retention_days INTEGER DEFAULT 365,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE device_group_members (
    membership_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID NOT NULL REFERENCES device_groups(group_id),
    device_id UUID NOT NULL REFERENCES devices(device_id),

    -- Membership Details
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    added_by UUID,
    membership_type VARCHAR(20) DEFAULT 'manual' CHECK (membership_type IN ('manual', 'automatic', 'temporary')),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMP WITH TIME ZONE, -- For temporary memberships

    UNIQUE (group_id, device_id)
);

-- ===========================================
-- DATA RETENTION AND ARCHIVING
-- ===========================================

CREATE TABLE data_retention_policies (
    policy_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    policy_name VARCHAR(255) NOT NULL,

    -- Retention Rules
    sensor_types TEXT[],
    data_types TEXT[], -- raw, processed, aggregated
    retention_period_days INTEGER NOT NULL,

    -- Archival Settings
    archival_enabled BOOLEAN DEFAULT FALSE,
    archival_destination VARCHAR(255), -- S3 bucket, external storage, etc.
    compression_enabled BOOLEAN DEFAULT TRUE,

    -- Cleanup Settings
    auto_cleanup_enabled BOOLEAN DEFAULT TRUE,
    cleanup_batch_size INTEGER DEFAULT 1000,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE data_archives (
    archive_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    policy_id UUID NOT NULL REFERENCES data_retention_policies(policy_id),

    -- Archive Details
    archive_date DATE DEFAULT CURRENT_DATE,
    data_start_date TIMESTAMP WITH TIME ZONE,
    data_end_date TIMESTAMP WITH TIME ZONE,

    -- Archive Contents
    record_count BIGINT,
    compressed_size_bytes BIGINT,
    original_size_bytes BIGINT,

    -- Storage
    storage_location VARCHAR(500),
    storage_checksum VARCHAR(64),

    -- Status
    archive_status VARCHAR(20) DEFAULT 'completed' CHECK (archive_status IN ('in_progress', 'completed', 'failed', 'corrupted')),
    verified_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

CREATE TABLE analytics_dashboards (
    dashboard_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(organization_id),

    -- Dashboard Details
    dashboard_name VARCHAR(255) NOT NULL,
    dashboard_description TEXT,
    dashboard_type VARCHAR(30) CHECK (dashboard_type IN ('operational', 'analytical', 'executive', 'maintenance')),

    -- Configuration
    dashboard_config JSONB NOT NULL, -- Layout, widgets, filters
    default_time_range INTERVAL DEFAULT '7 days',
    auto_refresh_interval_seconds INTEGER,

    -- Access Control
    is_public BOOLEAN DEFAULT FALSE,
    allowed_users UUID[],
    allowed_groups UUID[],

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE dashboard_widgets (
    widget_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dashboard_id UUID NOT NULL REFERENCES analytics_dashboards(dashboard_id) ON DELETE CASCADE,

    -- Widget Details
    widget_type VARCHAR(50) NOT NULL CHECK (widget_type IN (
        'line_chart', 'bar_chart', 'gauge', 'map', 'table', 'kpi', 'heatmap'
    )),
    widget_title VARCHAR(255),
    widget_position JSONB DEFAULT '{"x": 0, "y": 0, "width": 4, "height": 3}',

    -- Data Configuration
    data_source_type VARCHAR(30) CHECK (data_source_type IN ('sensor_data', 'processed_data', 'alerts', 'devices')),
    data_query JSONB NOT NULL, -- Query configuration
    data_filters JSONB DEFAULT '{}',

    -- Visualization
    chart_config JSONB DEFAULT '{}',
    refresh_interval_seconds INTEGER DEFAULT 300,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Device and sensor indexes
CREATE INDEX idx_devices_status_location ON devices (device_status, location_id);
CREATE INDEX idx_devices_last_seen ON devices (last_seen_at DESC);
CREATE INDEX idx_sensors_device_type ON sensors (device_id, sensor_type);
CREATE INDEX idx_sensors_status ON sensors (sensor_status);

-- Time-series data indexes
CREATE INDEX idx_sensor_data_sensor_timestamp ON sensor_data (sensor_id, measurement_timestamp DESC);
CREATE INDEX idx_sensor_data_device_timestamp ON sensor_data (device_id, measurement_timestamp DESC);
CREATE INDEX idx_sensor_data_hour_bucket ON sensor_data (sensor_id, hour_bucket);
CREATE INDEX idx_sensor_data_day_bucket ON sensor_data (sensor_id, day_bucket);
CREATE INDEX idx_sensor_data_quality ON sensor_data (data_quality, measurement_timestamp DESC);

-- Alert indexes
CREATE INDEX idx_alerts_rule_timestamp ON alerts (alert_rule_id, alert_timestamp DESC);
CREATE INDEX idx_alerts_status_severity ON alerts (alert_status, alert_severity);
CREATE INDEX idx_alerts_sensor_timestamp ON alerts (sensor_id, alert_timestamp DESC);

-- Command and control indexes
CREATE INDEX idx_device_commands_device_status ON device_commands (device_id, execution_status);
CREATE INDEX idx_device_commands_scheduled ON device_commands (scheduled_at) WHERE execution_status = 'pending';

-- Organization indexes
CREATE INDEX idx_device_groups_org ON device_groups (organization_id);
CREATE INDEX idx_device_group_members_group ON device_group_members (group_id);
CREATE INDEX idx_device_group_members_device ON device_group_members (device_id);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Device health overview
CREATE VIEW device_health_overview AS
SELECT
    d.device_id,
    d.device_name,
    d.device_serial_number,
    dt.device_type_name,
    dt.device_category,
    d.device_status,
    d.last_seen_at,
    d.battery_level,
    d.signal_strength,
    d.temperature,

    -- Health indicators
    CASE
        WHEN d.last_seen_at < CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 'offline'
        WHEN d.battery_level < 10 THEN 'low_battery'
        WHEN d.temperature > 70 THEN 'overheating'
        WHEN d.signal_strength < 20 THEN 'weak_signal'
        ELSE 'healthy'
    END as health_status,

    -- Sensor count and status
    COUNT(s.sensor_id) as sensor_count,
    COUNT(CASE WHEN s.sensor_status = 'active' THEN 1 END) as active_sensors,
    COUNT(CASE WHEN s.sensor_status = 'failed' THEN 1 END) as failed_sensors,

    -- Recent data activity
    MAX(sd.measurement_timestamp) as last_data_timestamp,
    COUNT(sd.data_id) as data_points_last_24h

FROM devices d
JOIN device_types dt ON d.device_type_id = dt.device_type_id
LEFT JOIN sensors s ON d.device_id = s.device_id
LEFT JOIN sensor_data sd ON d.device_id = sd.device_id
    AND sd.measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY d.device_id, d.device_name, d.device_serial_number,
         dt.device_type_name, dt.device_category, d.device_status,
         d.last_seen_at, d.battery_level, d.signal_strength, d.temperature;

-- Sensor data summary with aggregations
CREATE VIEW sensor_data_summary AS
SELECT
    s.sensor_id,
    s.sensor_name,
    s.sensor_type,
    s.unit_of_measure,
    d.device_name,

    -- Current values
    (SELECT sd.measurement_value
     FROM sensor_data sd
     WHERE sd.sensor_id = s.sensor_id
     ORDER BY sd.measurement_timestamp DESC
     LIMIT 1) as current_value,

    (SELECT sd.measurement_timestamp
     FROM sensor_data sd
     WHERE sd.sensor_id = s.sensor_id
     ORDER BY sd.measurement_timestamp DESC
     LIMIT 1) as last_measurement,

    -- 24-hour statistics
    AVG(CASE WHEN sd.measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
             THEN sd.measurement_value END) as avg_24h,

    MIN(CASE WHEN sd.measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
             THEN sd.measurement_value END) as min_24h,

    MAX(CASE WHEN sd.measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
             THEN sd.measurement_value END) as max_24h,

    COUNT(CASE WHEN sd.measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
               THEN 1 END) as measurements_24h,

    -- Data quality
    AVG(CASE WHEN sd.measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
             THEN CASE WHEN sd.data_quality = 'valid' THEN 1 ELSE 0 END END) as data_quality_24h

FROM sensors s
JOIN devices d ON s.device_id = d.device_id
LEFT JOIN sensor_data sd ON s.sensor_id = sd.sensor_id
WHERE s.sensor_status = 'active'
GROUP BY s.sensor_id, s.sensor_name, s.sensor_type, s.unit_of_measure, d.device_name;

-- Alert summary dashboard
CREATE VIEW alert_summary_dashboard AS
SELECT
    DATE_TRUNC('hour', a.alert_timestamp) as alert_hour,
    a.alert_severity,
    ar.rule_name,

    COUNT(*) as alert_count,
    COUNT(DISTINCT a.device_id) as affected_devices,
    COUNT(DISTINCT a.sensor_id) as affected_sensors,

    -- Resolution metrics
    COUNT(CASE WHEN a.alert_status = 'resolved' THEN 1 END) as resolved_count,
    AVG(EXTRACT(EPOCH FROM (a.resolved_at - a.alert_timestamp))/3600) as avg_resolution_hours,

    -- Escalation tracking
    COUNT(CASE WHEN a.escalation_level > 0 THEN 1 END) as escalated_count

FROM alerts a
JOIN alert_rules ar ON a.alert_rule_id = ar.alert_rule_id
WHERE a.alert_timestamp >= CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', a.alert_timestamp), a.alert_severity, ar.rule_name
ORDER BY alert_hour DESC, alert_severity;

-- ===========================================
-- FUNCTIONS FOR DATA PROCESSING
-- =========================================--

-- Function to process incoming sensor data
CREATE OR REPLACE FUNCTION process_sensor_data(
    sensor_uuid UUID,
    measurement_value DECIMAL,
    measurement_unit VARCHAR DEFAULT NULL,
    measurement_metadata JSONB DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
    sensor_record sensors%ROWTYPE;
    device_record devices%ROWTYPE;
    data_id UUID;
    processed_value DECIMAL;
    is_anomaly BOOLEAN := FALSE;
    anomaly_score DECIMAL := 0;
BEGIN
    -- Get sensor and device details
    SELECT s.*, d.* INTO sensor_record, device_record
    FROM sensors s
    JOIN devices d ON s.device_id = d.device_id
    WHERE s.sensor_id = sensor_uuid;

    -- Validate measurement is within sensor range
    IF measurement_value < sensor_record.measurement_range_min OR
       measurement_value > sensor_record.measurement_range_max THEN
        -- Log out-of-range measurement
        INSERT INTO sensor_data (
            sensor_id, device_id, measurement_value,
            measurement_unit, data_quality, measurement_metadata
        ) VALUES (
            sensor_uuid, device_record.device_id, measurement_value,
            COALESCE(measurement_unit, sensor_record.unit_of_measure),
            'suspect', measurement_metadata || '{"out_of_range": true}'
        ) RETURNING data_id INTO data_id;

        RETURN data_id;
    END IF;

    -- Apply calibration if available
    processed_value := measurement_value;
    IF sensor_record.calibration_data != '{}' THEN
        -- Apply calibration formula (simplified)
        processed_value := measurement_value *
            (sensor_record.calibration_data->>'multiplier')::DECIMAL;
    END IF;

    -- Check for anomalies (simplified statistical check)
    SELECT
        CASE WHEN processed_value < (avg_val - 3 * stddev_val) OR
                  processed_value > (avg_val + 3 * stddev_val)
             THEN TRUE ELSE FALSE END,
        CASE WHEN stddev_val > 0
             THEN LEAST(ABS(processed_value - avg_val) / stddev_val, 5.0)
             ELSE 0 END
    INTO is_anomaly, anomaly_score
    FROM (
        SELECT
            AVG(measurement_value) as avg_val,
            STDDEV(measurement_value) as stddev_val
        FROM sensor_data
        WHERE sensor_id = sensor_uuid
          AND measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
          AND data_quality = 'valid'
    ) stats;

    -- Insert sensor data
    INSERT INTO sensor_data (
        sensor_id, device_id, measurement_value, measurement_unit,
        data_quality, confidence_level, measurement_metadata,
        is_anomaly, anomaly_score
    ) VALUES (
        sensor_uuid, device_record.device_id, processed_value,
        COALESCE(measurement_unit, sensor_record.unit_of_measure),
        'valid', sensor_record.data_quality_score,
        measurement_metadata, is_anomaly, anomaly_score
    ) RETURNING data_id INTO data_id;

    -- Update device last seen
    UPDATE devices
    SET last_seen_at = CURRENT_TIMESTAMP,
        battery_level = measurement_metadata->>'battery_level',
        signal_strength = measurement_metadata->>'signal_strength',
        temperature = measurement_metadata->>'device_temperature'
    WHERE device_id = device_record.device_id;

    -- Check alert rules
    PERFORM check_alert_rules(sensor_uuid, processed_value, measurement_metadata);

    RETURN data_id;
END;
$$ LANGUAGE plpgsql;

-- Function to check alert rules
CREATE OR REPLACE FUNCTION check_alert_rules(
    sensor_uuid UUID,
    measurement_value DECIMAL,
    measurement_metadata JSONB DEFAULT '{}'
)
RETURNS INTEGER AS $$
DECLARE
    alert_rule_record alert_rules%ROWTYPE;
    alert_count INTEGER := 0;
    should_trigger BOOLEAN;
BEGIN
    -- Check each active alert rule
    FOR alert_rule_record IN
        SELECT * FROM alert_rules
        WHERE is_active = TRUE
          AND (sensor_uuid = ANY(sensor_ids) OR
               (SELECT sensor_type FROM sensors WHERE sensor_id = sensor_uuid) = ANY(sensor_types))
    LOOP
        -- Evaluate alert conditions (simplified)
        should_trigger := FALSE;

        -- Check if value exceeds threshold (example condition)
        IF alert_rule_record.conditions ? 'threshold' THEN
            IF measurement_value > (alert_rule_record.conditions->>'threshold')::DECIMAL THEN
                should_trigger := TRUE;
            END IF;
        END IF;

        -- Check cooldown period
        IF should_trigger THEN
            -- Check if alert was triggered recently
            IF NOT EXISTS (
                SELECT 1 FROM alerts
                WHERE alert_rule_id = alert_rule_record.alert_rule_id
                  AND alert_timestamp > CURRENT_TIMESTAMP - INTERVAL '1 minute' * alert_rule_record.cooldown_period_minutes
            ) THEN
                -- Create alert
                INSERT INTO alerts (
                    alert_rule_id, sensor_id, device_id, alert_message,
                    alert_severity, trigger_value, threshold_value, alert_metadata
                ) VALUES (
                    alert_rule_record.alert_rule_id,
                    sensor_uuid,
                    (SELECT device_id FROM sensors WHERE sensor_id = sensor_uuid),
                    replace(alert_rule_record.alert_message_template,
                           '{{value}}', measurement_value::TEXT),
                    alert_rule_record.alert_severity,
                    measurement_value,
                    (alert_rule_record.conditions->>'threshold')::DECIMAL,
                    measurement_metadata
                );

                alert_count := alert_count + 1;
            END IF;
        END IF;
    END LOOP;

    RETURN alert_count;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample device type
INSERT INTO device_types (device_type_name, device_category, manufacturer, model, power_type, connectivity_type) VALUES
('Environmental Sensor', 'sensor', 'IoT Corp', 'ENV-100', 'battery', 'wifi');

-- Insert sample device
INSERT INTO devices (device_type_id, device_serial_number, device_name, latitude, longitude) VALUES
((SELECT device_type_id FROM device_types WHERE device_type_name = 'Environmental Sensor' LIMIT 1),
 'DEV001234', 'Warehouse Sensor A1', 40.7128, -74.0060);

-- Insert sample sensors
INSERT INTO sensors (device_id, sensor_type, sensor_name, unit_of_measure, measurement_range_min, measurement_range_max) VALUES
((SELECT device_id FROM devices WHERE device_serial_number = 'DEV001234' LIMIT 1),
 'temperature', 'Ambient Temperature', 'celsius', -40, 85),
((SELECT device_id FROM devices WHERE device_serial_number = 'DEV001234' LIMIT 1),
 'humidity', 'Relative Humidity', 'percent', 0, 100);

-- Insert sample sensor data
INSERT INTO sensor_data (sensor_id, device_id, measurement_value, measurement_unit) VALUES
((SELECT sensor_id FROM sensors WHERE sensor_name = 'Ambient Temperature' LIMIT 1),
 (SELECT device_id FROM devices WHERE device_serial_number = 'DEV001234' LIMIT 1),
 23.5, 'celsius');

-- This IoT schema provides comprehensive infrastructure for sensor data collection,
-- processing, alerting, and analytics with enterprise scalability and reliability.
