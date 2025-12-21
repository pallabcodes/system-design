# IoT & Sensor Data Management Database Design

## Overview

This comprehensive database schema supports Internet of Things (IoT) deployments with sensor data collection, real-time processing, device management, and analytics. The design handles high-volume time-series data, device lifecycle management, and complex event processing for IoT applications.

## Key Features

### 🌐 Device & Sensor Management
- **Device type catalog** with specifications and capabilities
- **Device lifecycle management** from provisioning to decommissioning
- **Sensor calibration** and maintenance tracking
- **Geospatial device tracking** with location management

### 📊 Data Collection & Processing
- **High-volume time-series data** with monthly partitioning
- **Real-time data processing** with rule-based transformations
- **Data quality assessment** and anomaly detection
- **Configurable data retention** and archival policies

### 🚨 Alerting & Monitoring
- **Rule-based alerting** with configurable thresholds
- **Multi-channel notifications** (email, SMS, webhooks)
- **Alert escalation** and resolution tracking
- **Device health monitoring** and predictive maintenance

### ⚙️ Command & Control
- **Remote device management** with command queuing
- **Configuration versioning** with rollback support
- **Firmware update orchestration**
- **Bulk device operations**

## Database Schema Highlights

### Core Tables

#### Device Management
- **`device_types`** - Device specifications and capabilities catalog
- **`devices`** - Device instances with status and configuration
- **`sensors`** - Sensor definitions with calibration and specifications

#### Data Collection
- **`sensor_data`** - Time-series sensor measurements with partitioning
- **`data_processing_rules`** - Rules for real-time data transformation
- **`processed_data`** - Derived and aggregated data results

#### Alerting System
- **`alert_rules`** - Configurable alert conditions and thresholds
- **`alerts`** - Alert instances with escalation and resolution tracking

#### Command & Control
- **`device_commands`** - Remote command execution and tracking
- **`device_configuration_versions`** - Configuration management with versioning

#### Organization
- **`organizations`** - Multi-tenant organizational hierarchy
- **`device_groups`** - Logical device groupings for management
- **`device_group_members`** - Dynamic group membership management

## Key Design Patterns

### 1. Time-Series Data Partitioning
```sql
-- Monthly partitioning for sensor data scalability
CREATE TABLE sensor_data PARTITION BY RANGE (measurement_timestamp);

CREATE TABLE sensor_data_2024_01 PARTITION OF sensor_data
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Efficient time-range queries
SELECT * FROM sensor_data
WHERE measurement_timestamp >= '2024-01-01'
  AND measurement_timestamp < '2024-02-01';
```

### 2. Real-Time Data Processing Pipeline
```sql
-- Process incoming sensor data with validation and alerting
CREATE OR REPLACE FUNCTION process_sensor_data(
    sensor_uuid UUID,
    measurement_value DECIMAL,
    measurement_metadata JSONB DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
    sensor_record sensors%ROWTYPE;
    processed_value DECIMAL;
    is_anomaly BOOLEAN := FALSE;
BEGIN
    -- Validate sensor exists and is active
    SELECT * INTO sensor_record
    FROM sensors WHERE sensor_id = sensor_uuid AND sensor_status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sensor not found or inactive';
    END IF;

    -- Apply calibration
    processed_value := measurement_value;
    IF sensor_record.calibration_data != '{}' THEN
        processed_value := measurement_value *
            (sensor_record.calibration_data->>'multiplier')::DECIMAL;
    END IF;

    -- Check for anomalies using statistical analysis
    SELECT
        CASE WHEN ABS(processed_value - avg_val) > 3 * stddev_val THEN TRUE ELSE FALSE END,
        CASE WHEN stddev_val > 0 THEN LEAST(ABS(processed_value - avg_val) / stddev_val, 5.0) ELSE 0 END
    INTO is_anomaly, anomaly_score
    FROM (
        SELECT AVG(measurement_value) as avg_val, STDDEV(measurement_value) as stddev_val
        FROM sensor_data
        WHERE sensor_id = sensor_uuid
          AND measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
    ) stats;

    -- Insert processed data
    INSERT INTO sensor_data (
        sensor_id, device_id, measurement_value, measurement_unit,
        data_quality, is_anomaly, anomaly_score, measurement_metadata
    ) VALUES (
        sensor_uuid, sensor_record.device_id, processed_value,
        sensor_record.unit_of_measure, 'valid', is_anomaly, anomaly_score, measurement_metadata
    );

    -- Trigger alerts if necessary
    PERFORM check_alert_rules(sensor_uuid, processed_value, measurement_metadata);

    RETURN data_id;
END;
$$ LANGUAGE plpgsql;
```

### 3. Alert Rule Engine
```sql
-- Flexible alert rule evaluation
CREATE OR REPLACE FUNCTION evaluate_alert_condition(
    rule_conditions JSONB,
    sensor_value DECIMAL,
    sensor_metadata JSONB DEFAULT '{}'
)
RETURNS BOOLEAN AS $$
DECLARE
    condition_result BOOLEAN := TRUE;
    condition_key TEXT;
    condition_value JSONB;
BEGIN
    -- Evaluate each condition in the rule
    FOR condition_key, condition_value IN SELECT * FROM jsonb_each(rule_conditions)
    LOOP
        CASE condition_key
            WHEN 'threshold_high' THEN
                condition_result := condition_result AND
                    (sensor_value > (condition_value #>> '{}')::DECIMAL);
            WHEN 'threshold_low' THEN
                condition_result := condition_result AND
                    (sensor_value < (condition_value #>> '{}')::DECIMAL);
            WHEN 'metadata_check' THEN
                -- Check metadata conditions
                condition_result := condition_result AND
                    (sensor_metadata @> condition_value);
            WHEN 'time_window' THEN
                -- Time-based conditions
                condition_result := condition_result AND
                    (CURRENT_TIME BETWEEN
                     (condition_value->>'start')::TIME AND
                     (condition_value->>'end')::TIME);
        END CASE;

        -- Short circuit if any condition fails
        IF NOT condition_result THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN condition_result;
END;
$$ LANGUAGE plpgsql;
```

### 4. Device Command Orchestration
```sql
-- Queue and execute device commands
CREATE OR REPLACE FUNCTION queue_device_command(
    device_uuid UUID,
    command_type_param VARCHAR,
    command_params JSONB DEFAULT '{}',
    scheduled_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
)
RETURNS UUID AS $$
DECLARE
    command_uuid UUID;
    device_status VARCHAR;
BEGIN
    -- Check device status
    SELECT device_status INTO device_status
    FROM devices WHERE device_id = device_uuid;

    IF device_status NOT IN ('active', 'maintenance') THEN
        RAISE EXCEPTION 'Device is not in a commandable state: %', device_status;
    END IF;

    -- Create command record
    INSERT INTO device_commands (
        device_id, command_type, command_parameters,
        scheduled_at, execution_status
    ) VALUES (
        device_uuid, command_type_param, command_params,
        scheduled_time, 'pending'
    ) RETURNING command_id INTO command_uuid;

    -- Notify command processor (could be a queue system)
    PERFORM pg_notify('device_commands', command_uuid::TEXT);

    RETURN command_uuid;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Time-based partitioning for sensor data
CREATE TABLE sensor_data PARTITION BY RANGE (measurement_timestamp);

-- Sub-partitioning by sensor type for very large deployments
CREATE TABLE sensor_data_temp PARTITION OF sensor_data
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01')
    PARTITION BY LIST (sensor_type);

CREATE TABLE sensor_data_temp_a PARTITION OF sensor_data_temp
    FOR VALUES IN ('temperature', 'humidity');
```

### Indexing Strategy
```sql
-- Time-series optimized indexes
CREATE INDEX idx_sensor_data_sensor_time ON sensor_data (sensor_id, measurement_timestamp DESC);
CREATE INDEX idx_sensor_data_time_bucket ON sensor_data (hour_bucket, sensor_id);
CREATE INDEX idx_sensor_data_device_time ON sensor_data (device_id, measurement_timestamp DESC);

-- Partial indexes for active data
CREATE INDEX idx_devices_active ON devices (device_id) WHERE device_status = 'active';
CREATE INDEX idx_sensors_active ON sensors (sensor_id) WHERE sensor_status = 'active';

-- JSONB indexes for metadata queries
CREATE INDEX idx_sensor_data_metadata ON sensor_data USING gin (measurement_metadata);
CREATE INDEX idx_alerts_metadata ON alerts USING gin (alert_metadata);

-- BRIN indexes for time-series data (PostgreSQL 10+)
CREATE INDEX idx_sensor_data_time_brin ON sensor_data USING brin (measurement_timestamp);
```

### Materialized Views for Analytics
```sql
-- Hourly sensor aggregations
CREATE MATERIALIZED VIEW sensor_hourly_aggregates AS
SELECT
    sensor_id,
    hour_bucket,
    COUNT(*) as measurement_count,
    AVG(measurement_value) as avg_value,
    MIN(measurement_value) as min_value,
    MAX(measurement_value) as max_value,
    STDDEV(measurement_value) as value_stddev,

    -- Data quality metrics
    AVG(CASE WHEN data_quality = 'valid' THEN 1 ELSE 0 END) as data_quality_ratio,
    COUNT(CASE WHEN is_anomaly THEN 1 END) as anomaly_count

FROM sensor_data
WHERE measurement_timestamp >= CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY sensor_id, hour_bucket
ORDER BY sensor_id, hour_bucket;

-- Refresh every hour
CREATE UNIQUE INDEX idx_sensor_hourly_agg ON sensor_hourly_aggregates (sensor_id, hour_bucket);
REFRESH MATERIALIZED VIEW CONCURRENTLY sensor_hourly_aggregates;
```

### Hypertable Optimization (TimescaleDB)
```sql
-- Convert to TimescaleDB hypertable for better time-series performance
SELECT create_hypertable('sensor_data', 'measurement_timestamp', chunk_time_interval => INTERVAL '1 day');

-- Add compression policy
ALTER TABLE sensor_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sensor_id',
    timescaledb.compress_orderby = 'measurement_timestamp DESC'
);

-- Add retention policy (keep 1 year of raw data)
SELECT add_retention_policy('sensor_data', INTERVAL '1 year');
```

## Security Considerations

### Device Authentication
```sql
-- Secure device registration with certificate-based authentication
CREATE OR REPLACE FUNCTION register_device(
    device_serial VARCHAR,
    device_cert TEXT,
    device_key_hash VARCHAR
)
RETURNS UUID AS $$
DECLARE
    device_uuid UUID;
    device_type_uuid UUID;
BEGIN
    -- Validate certificate (simplified)
    IF NOT validate_device_certificate(device_cert) THEN
        RAISE EXCEPTION 'Invalid device certificate';
    END IF;

    -- Register device
    INSERT INTO devices (
        device_type_id, device_serial_number,
        authentication_key_hash, device_status
    ) VALUES (
        device_type_uuid, device_serial,
        device_key_hash, 'provisioning'
    ) RETURNING device_id INTO device_uuid;

    -- Generate initial configuration
    PERFORM generate_device_config(device_uuid);

    RETURN device_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Data Encryption
```sql
-- Encrypt sensitive sensor data at rest
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypt sensitive measurements
CREATE OR REPLACE FUNCTION encrypt_sensor_value(plain_value DECIMAL)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(plain_value::TEXT, current_setting('iot.encryption_key'));
END;
$$ LANGUAGE plpgsql;

-- Decrypt for authorized queries
CREATE OR REPLACE FUNCTION decrypt_sensor_value(encrypted_value BYTEA)
RETURNS DECIMAL AS $$
BEGIN
    RETURN pgp_sym_decrypt(encrypted_value, current_setting('iot.encryption_key'))::DECIMAL;
END;
$$ LANGUAGE plpgsql;
```

### Access Control
```sql
-- Row Level Security for multi-tenant data access
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY device_organization_policy ON devices
    FOR ALL USING (
        organization_id = current_setting('app.organization_id')::UUID OR
        current_setting('app.user_role')::TEXT = 'admin'
    );

CREATE POLICY sensor_data_access_policy ON sensor_data
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM devices d
            JOIN device_group_members dgm ON d.device_id = dgm.device_id
            JOIN user_group_members ugm ON dgm.group_id = ugm.group_id
            WHERE d.device_id = sensor_data.device_id
              AND ugm.user_id = current_setting('app.user_id')::UUID
        )
    );
```

## Integration Points

### External Systems
- **MQTT Brokers** for device communication (Mosquitto, HiveMQ)
- **Time-Series Databases** for high-volume analytics (InfluxDB, TimescaleDB)
- **Stream Processing** platforms (Apache Kafka, Apache Flink)
- **Edge Computing** platforms for local processing

### API Endpoints
- **Device Management APIs** for provisioning and configuration
- **Data Ingestion APIs** for sensor data submission
- **Real-time Streaming APIs** for live data access
- **Analytics APIs** for historical data queries

## Monitoring & Analytics

### Key Performance Indicators
- **Device uptime** and connectivity statistics
- **Data ingestion rates** and processing latency
- **Alert response times** and false positive rates
- **Data quality metrics** and anomaly detection accuracy
- **System resource utilization** (CPU, memory, storage)

### Real-Time Dashboards
```sql
-- IoT operations dashboard
CREATE VIEW iot_operations_dashboard AS
SELECT
    -- Device metrics
    (SELECT COUNT(*) FROM devices WHERE device_status = 'active') as active_devices,
    (SELECT COUNT(*) FROM devices WHERE last_seen_at < CURRENT_TIMESTAMP - INTERVAL '1 hour') as offline_devices,
    (SELECT AVG(battery_level) FROM devices WHERE battery_level IS NOT NULL) as avg_battery_level,

    -- Data metrics
    (SELECT COUNT(*) FROM sensor_data WHERE measurement_timestamp >= CURRENT_DATE) as todays_measurements,
    (SELECT COUNT(*) FROM sensor_data WHERE is_anomaly AND measurement_timestamp >= CURRENT_DATE) as todays_anomalies,

    -- Alert metrics
    (SELECT COUNT(*) FROM alerts WHERE alert_status = 'active') as active_alerts,
    (SELECT COUNT(*) FROM alerts WHERE alert_timestamp >= CURRENT_DATE) as todays_alerts,
    (SELECT AVG(EXTRACT(EPOCH FROM (resolved_at - alert_timestamp))/3600)
     FROM alerts WHERE resolved_at IS NOT NULL AND alert_timestamp >= CURRENT_DATE) as avg_resolution_hours,

    -- System health
    (SELECT COUNT(*) FROM device_commands WHERE execution_status = 'pending') as pending_commands,
    (SELECT COUNT(*) FROM data_processing_rules WHERE is_active = TRUE) as active_processing_rules
;
```

This IoT database schema provides enterprise-grade infrastructure for large-scale sensor networks with high-performance time-series data handling, real-time processing capabilities, and comprehensive device management features.
