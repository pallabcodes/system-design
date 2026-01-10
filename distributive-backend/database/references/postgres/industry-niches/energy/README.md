# Energy & Utilities Database Design

## Overview

This comprehensive database schema supports energy utilities, smart grid operations, customer service management, and regulatory compliance for electric, gas, water, and telecommunications utilities. The design handles complex metering, billing, outage management, and IoT device integration.

## Key Features

### 🏭 Utility Infrastructure Management
- **Asset lifecycle tracking** with maintenance scheduling and replacement planning
- **Geographic service territories** with zone-based operations
- **Infrastructure monitoring** with sensor data and predictive maintenance
- **Regulatory compliance** tracking and reporting

### ⚡ Smart Grid & IoT Integration
- **Real-time sensor data** collection from smart meters and infrastructure
- **Automated demand response** and load balancing
- **Predictive analytics** for equipment failure and maintenance needs
- **IoT device management** with firmware updates and security monitoring

### 📊 Metering & Billing Operations
- **Advanced metering infrastructure (AMI)** with automated readings
- **Complex rate structures** including time-of-use and demand charges
- **Usage analytics** with anomaly detection and efficiency monitoring
- **Multi-utility billing** consolidation and payment processing

### 🚨 Outage & Service Management
- **Real-time outage tracking** with customer impact assessment
- **Automated customer notifications** and status updates
- **Crew dispatch optimization** and restoration planning
- **Service reliability metrics** and performance reporting

## Database Schema Highlights

### Core Tables

#### Infrastructure Management
- **`utilities`** - Utility company profiles with regulatory and operational details
- **`service_zones`** - Geographic service areas with characteristics and performance metrics
- **`infrastructure_assets`** - Equipment and facility asset tracking with maintenance schedules

#### Customer & Service Management
- **`customers`** - Customer profiles with service addresses and account information
- **`service_accounts`** - Individual utility accounts with meter and billing details

#### Metering & Consumption
- **`meter_readings`** - Time-series consumption data with quality validation
- **`smart_devices`** - IoT device management with connectivity and configuration
- **`sensor_readings`** - Real-time sensor data from smart infrastructure

#### Billing & Financial
- **`rate_schedules`** - Complex rate structures with tiered and time-of-use pricing
- **`bills`** - Customer billing with detailed charge breakdowns
- **`payments`** - Payment processing and reconciliation

#### Operations & Reliability
- **`outages`** - Service interruption tracking with impact assessment
- **`outage_updates`** - Real-time outage status communications

## Key Design Patterns

### 1. Time-Series Data Management with TimescaleDB
```sql
-- Create hypertable for efficient time-series storage
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Convert meter readings to hypertable for optimal time-series performance
CREATE TABLE meter_readings_hyper AS SELECT * FROM meter_readings;
SELECT create_hypertable('meter_readings_hyper', 'reading_timestamp', chunk_time_interval => INTERVAL '1 month');

-- Efficient time-series queries with automatic partitioning
SELECT time_bucket('1 hour', reading_timestamp) as bucket,
       AVG(consumption_kwh) as avg_consumption,
       MAX(consumption_kwh) as peak_consumption
FROM meter_readings_hyper
WHERE account_id = $1
  AND reading_timestamp >= $2
  AND reading_timestamp < $3
GROUP BY bucket
ORDER BY bucket;
```

### 2. Complex Rate Calculation Engine
```sql
-- Calculate bill with multiple rate components and tiers
CREATE OR REPLACE FUNCTION calculate_complex_bill(
    account_uuid UUID,
    billing_start DATE,
    billing_end DATE
)
RETURNS TABLE (
    energy_charge DECIMAL,
    demand_charge DECIMAL,
    time_of_use_charge DECIMAL,
    service_charge DECIMAL,
    taxes_and_fees DECIMAL,
    total_amount DECIMAL,
    rate_breakdown JSONB
) AS $$
DECLARE
    rate_record rate_schedules%ROWTYPE;
    total_kwh DECIMAL := 0;
    peak_kw DECIMAL := 0;
    off_peak_kwh DECIMAL := 0;
    on_peak_kwh DECIMAL := 0;
    billing_days INTEGER;
    breakdown JSONB := '{}';
BEGIN
    -- Get rate schedule
    SELECT rs.* INTO rate_record
    FROM service_accounts sa
    JOIN customers c ON sa.customer_id = c.customer_id
    JOIN service_zones sz ON c.service_zone_id = sz.zone_id
    JOIN rate_schedules rs ON sz.utility_id = rs.utility_id
    WHERE sa.account_id = account_uuid
      AND rs.rate_status = 'active'
      AND rs.effective_date <= billing_start
    ORDER BY rs.effective_date DESC
    LIMIT 1;

    billing_days := billing_end - billing_start + 1;

    -- Calculate consumption by time periods
    SELECT
        SUM(mr.consumption_kwh) as total_kwh,
        MAX(mr.consumption_kwh / 24) as peak_kw, -- Rough peak calculation
        SUM(CASE WHEN EXTRACT(HOUR FROM mr.reading_time) BETWEEN 6 AND 18 THEN mr.consumption_kwh ELSE 0 END) as on_peak_kwh,
        SUM(CASE WHEN EXTRACT(HOUR FROM mr.reading_time) NOT BETWEEN 6 AND 18 THEN mr.consumption_kwh ELSE 0 END) as off_peak_kwh
    INTO total_kwh, peak_kw, on_peak_kwh, off_peak_kwh
    FROM meter_readings mr
    WHERE mr.account_id = account_uuid
      AND mr.reading_date BETWEEN billing_start AND billing_end;

    -- Build rate breakdown
    breakdown := jsonb_build_object(
        'rate_schedule', rate_record.rate_schedule_name,
        'billing_period_days', billing_days,
        'total_kwh', total_kwh,
        'peak_kw', peak_kw,
        'on_peak_kwh', on_peak_kwh,
        'off_peak_kwh', off_peak_kwh
    );

    -- Calculate charges based on rate structure
    RETURN QUERY SELECT
        total_kwh * rate_record.base_rate,
        COALESCE(peak_kw * rate_record.demand_charge, 0),
        -- Time-of-use calculation (simplified)
        COALESCE(on_peak_kwh * (rate_record.time_of_use_rates->>'on_peak_rate')::DECIMAL, 0) +
        COALESCE(off_peak_kwh * (rate_record.time_of_use_rates->>'off_peak_rate')::DECIMAL, 0),
        rate_record.service_charge,
        (total_kwh * rate_record.base_rate) * 0.08, -- 8% tax
        (total_kwh * rate_record.base_rate) +
        COALESCE(peak_kw * rate_record.demand_charge, 0) +
        COALESCE(on_peak_kwh * (rate_record.time_of_use_rates->>'on_peak_rate')::DECIMAL, 0) +
        COALESCE(off_peak_kwh * (rate_record.time_of_use_rates->>'off_peak_rate')::DECIMAL, 0) +
        rate_record.service_charge +
        (total_kwh * rate_record.base_rate) * 0.08,
        breakdown;
END;
$$ LANGUAGE plpgsql;
```

### 3. Smart Grid Load Balancing and Demand Response
```sql
-- Intelligent load balancing with demand response
CREATE OR REPLACE FUNCTION optimize_grid_load(
    zone_uuid UUID,
    target_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    optimization_window INTERVAL DEFAULT INTERVAL '1 hour'
)
RETURNS TABLE (
    recommended_actions JSONB,
    expected_load_reduction_mw DECIMAL,
    affected_customers INTEGER,
    implementation_priority VARCHAR,
    risk_assessment JSONB
) AS $$
DECLARE
    current_load DECIMAL;
    capacity_limit DECIMAL;
    high_usage_customers INTEGER := 0;
    recommended_actions_val JSONB := '[]';
    total_reduction DECIMAL := 0;
BEGIN
    -- Get current load for zone
    SELECT SUM(mr.consumption_kwh / 1000) as current_load_mw,
           sz.peak_load_mw as capacity_limit_mw
    INTO current_load, capacity_limit
    FROM meter_readings mr
    JOIN service_accounts sa ON mr.account_id = sa.account_id
    JOIN customers c ON sa.customer_id = c.customer_id
    JOIN service_zones sz ON c.service_zone_id = sz.zone_id
    WHERE sz.zone_id = zone_uuid
      AND mr.reading_timestamp >= target_timestamp - INTERVAL '15 minutes'
      AND mr.reading_timestamp <= target_timestamp
    GROUP BY sz.peak_load_mw;

    -- Check if load balancing is needed
    IF current_load < capacity_limit * 0.9 THEN
        -- No action needed
        RETURN QUERY SELECT '[]'::JSONB, 0::DECIMAL, 0, 'none', '{}'::JSONB;
        RETURN;
    END IF;

    -- Identify high-usage customers for demand response
    SELECT COUNT(*), SUM(mr.consumption_kwh / 1000)
    INTO high_usage_customers, total_reduction
    FROM (
        SELECT mr.account_id, SUM(mr.consumption_kwh) as recent_usage
        FROM meter_readings mr
        JOIN service_accounts sa ON mr.account_id = sa.account_id
        JOIN customers c ON sa.customer_id = c.customer_id
        WHERE c.service_zone_id = zone_uuid
          AND mr.reading_timestamp >= target_timestamp - INTERVAL '1 hour'
        GROUP BY mr.account_id
        ORDER BY recent_usage DESC
        LIMIT 50 -- Top 50 high-usage accounts
    ) high_usage
    JOIN meter_readings mr ON high_usage.account_id = mr.account_id
    WHERE mr.reading_timestamp >= target_timestamp - INTERVAL '15 minutes';

    -- Estimate 10% reduction through demand response
    total_reduction := total_reduction * 0.1;

    -- Build recommended actions
    recommended_actions_val := jsonb_build_object(
        'action_type', 'demand_response',
        'target_customers', high_usage_customers,
        'reduction_target_mw', total_reduction,
        'implementation_method', 'smart_thermostat_adjustment',
        'estimated_duration', '30 minutes'
    );

    -- Risk assessment
    risk_assessment := jsonb_build_object(
        'customer_discomfort_risk', 'medium',
        'equipment_stress_risk', 'low',
        'service_reliability_impact', 'minimal',
        'regulatory_compliance', 'compliant'
    );

    RETURN QUERY SELECT
        recommended_actions_val,
        total_reduction,
        high_usage_customers,
        CASE
            WHEN current_load > capacity_limit THEN 'critical'
            WHEN current_load > capacity_limit * 0.95 THEN 'high'
            ELSE 'medium'
        END,
        risk_assessment;
END;
$$ LANGUAGE plpgsql;
```

### 4. Predictive Maintenance with Sensor Analytics
```sql
-- Predictive maintenance using sensor data patterns
CREATE OR REPLACE FUNCTION predict_equipment_failure(
    asset_uuid UUID,
    prediction_window_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    failure_probability DECIMAL,
    estimated_time_to_failure INTERVAL,
    failure_mode VARCHAR,
    confidence_level DECIMAL,
    recommended_actions JSONB,
    risk_assessment VARCHAR
) AS $$
DECLARE
    vibration_trend DECIMAL;
    temperature_trend DECIMAL;
    noise_trend DECIMAL;
    baseline_vibration DECIMAL;
    baseline_temperature DECIMAL;
    baseline_noise DECIMAL;
    current_vibration DECIMAL;
    current_temperature DECIMAL;
    current_noise DECIMAL;
    failure_probability_val DECIMAL := 0;
    estimated_ttf INTERVAL;
    failure_mode_val VARCHAR;
BEGIN
    -- Get baseline readings (last 90 days average)
    SELECT
        AVG(CASE WHEN reading_type = 'vibration' THEN numeric_value END) as baseline_vib,
        AVG(CASE WHEN reading_type = 'temperature' THEN numeric_value END) as baseline_temp,
        AVG(CASE WHEN reading_type = 'noise' THEN numeric_value END) as baseline_noise
    INTO baseline_vibration, baseline_temperature, baseline_noise
    FROM sensor_readings sr
    JOIN smart_devices sd ON sr.device_id = sd.device_id
    WHERE sd.asset_id = asset_uuid
      AND sr.reading_timestamp >= CURRENT_TIMESTAMP - INTERVAL '90 days'
      AND sr.reading_timestamp < CURRENT_TIMESTAMP - INTERVAL '7 days';

    -- Get current readings (last 24 hours)
    SELECT
        AVG(CASE WHEN reading_type = 'vibration' THEN numeric_value END) as current_vib,
        AVG(CASE WHEN reading_type = 'temperature' THEN numeric_value END) as current_temp,
        AVG(CASE WHEN reading_type = 'noise' THEN numeric_value END) as current_noise
    INTO current_vibration, current_temperature, current_noise
    FROM sensor_readings sr
    JOIN smart_devices sd ON sr.device_id = sd.device_id
    WHERE sd.asset_id = asset_uuid
      AND sr.reading_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours';

    -- Calculate trends
    vibration_trend := COALESCE(current_vibration / NULLIF(baseline_vibration, 0), 1);
    temperature_trend := COALESCE(current_temperature / NULLIF(baseline_temperature, 0), 1);
    noise_trend := COALESCE(current_noise / NULLIF(baseline_noise, 0), 1);

    -- Determine failure probability and mode
    IF vibration_trend > 1.5 THEN
        failure_probability_val := 0.8;
        failure_mode_val := 'bearing_failure';
        estimated_ttf := INTERVAL '7 days';
    ELSIF temperature_trend > 1.3 THEN
        failure_probability_val := 0.6;
        failure_mode_val := 'overheating';
        estimated_ttf := INTERVAL '14 days';
    ELSIF noise_trend > 1.4 THEN
        failure_probability_val := 0.5;
        failure_mode_val := 'mechanical_wear';
        estimated_ttf := INTERVAL '21 days';
    ELSE
        failure_probability_val := 0.1;
        failure_mode_val := 'normal_wear';
        estimated_ttf := INTERVAL '90 days';
    END IF;

    -- Build recommended actions
    recommended_actions := jsonb_build_object(
        'immediate_actions', CASE
            WHEN failure_probability_val > 0.7 THEN jsonb_build_array('schedule_emergency_inspection', 'reduce_load')
            WHEN failure_probability_val > 0.5 THEN jsonb_build_array('schedule_maintenance', 'increase_monitoring')
            ELSE jsonb_build_array('continue_monitoring')
        END,
        'preventive_measures', jsonb_build_array('lubrication', 'calibration', 'parts_replacement'),
        'estimated_cost', CASE
            WHEN failure_mode_val = 'bearing_failure' THEN 5000
            WHEN failure_mode_val = 'overheating' THEN 3000
            ELSE 1000
        END
    );

    RETURN QUERY SELECT
        failure_probability_val,
        estimated_ttf,
        failure_mode_val,
        0.85, -- Confidence level
        recommended_actions,
        CASE
            WHEN failure_probability_val > 0.7 THEN 'critical'
            WHEN failure_probability_val > 0.5 THEN 'high'
            WHEN failure_probability_val > 0.3 THEN 'medium'
            ELSE 'low'
        END;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition time-series data by time for optimal performance
CREATE TABLE meter_readings PARTITION BY RANGE (reading_date);

-- Monthly partitions for meter readings
CREATE TABLE meter_readings_2024_01 PARTITION OF meter_readings
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE meter_readings_2024_02 PARTITION OF meter_readings
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- Partition sensor readings by time
CREATE TABLE sensor_readings PARTITION BY RANGE (reading_timestamp);

CREATE TABLE sensor_readings_2024_01 PARTITION OF sensor_readings
    FOR VALUES FROM ('2024-01-01 00:00:00') TO ('2024-02-01 00:00:00');

-- Partition bills by billing period
CREATE TABLE bills PARTITION BY RANGE (billing_period_start);

CREATE TABLE bills_2024_q1 PARTITION OF bills
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');
```

### Advanced Indexing
```sql
-- Geographic indexes for spatial queries
CREATE INDEX idx_utilities_service_area ON utilities USING gist (service_area);
CREATE INDEX idx_service_zones_boundary ON service_zones USING gist (zone_boundary);
CREATE INDEX idx_infrastructure_assets_location ON infrastructure_assets USING gist (geolocation);
CREATE INDEX idx_customers_service_location ON customers USING gist (geolocation);

-- Time-series indexes for efficient queries
CREATE INDEX idx_meter_readings_account_time ON meter_readings (account_id, reading_timestamp DESC);
CREATE INDEX idx_sensor_readings_device_time ON sensor_readings (device_id, reading_timestamp DESC);
CREATE INDEX idx_sensor_readings_type_time ON sensor_readings (reading_type, reading_timestamp DESC);

-- Composite indexes for billing queries
CREATE INDEX idx_bills_account_period ON bills (account_id, billing_period_start DESC, billing_status);
CREATE INDEX idx_bills_due_status ON bills (due_date, billing_status) WHERE billing_status != 'paid';

-- Partial indexes for active records
CREATE INDEX idx_active_smart_devices ON smart_devices (device_id, device_status) WHERE device_status = 'active';
CREATE INDEX idx_operational_assets ON infrastructure_assets (utility_id, asset_status) WHERE asset_status = 'operational';
CREATE INDEX idx_open_outages ON outages (utility_id, outage_status) WHERE outage_status IN ('reported', 'confirmed', 'crew_dispatched', 'repairing');

-- JSONB indexes for flexible queries
CREATE INDEX idx_rate_schedules_tou_rates ON rate_schedules USING gin (time_of_use_rates);
CREATE INDEX idx_infrastructure_maintenance ON infrastructure_assets USING gin (maintenance_schedule);
CREATE INDEX idx_outages_affected_assets ON outages USING gin (affected_infrastructure);
```

### Materialized Views for Analytics
```sql
-- Real-time utility operations dashboard
CREATE MATERIALIZED VIEW utility_operations_dashboard AS
SELECT
    u.utility_id,
    u.utility_name,

    -- Current system status
    COUNT(DISTINCT CASE WHEN o.outage_status IN ('reported', 'confirmed', 'crew_dispatched', 'repairing') THEN o.outage_id END) as active_outages,
    COUNT(DISTINCT CASE WHEN o.outage_status IN ('reported', 'confirmed', 'crew_dispatched', 'repairing') THEN o.outage_id END) as customers_affected_by_outages,
    SUM(CASE WHEN o.outage_status IN ('reported', 'confirmed', 'crew_dispatched', 'repairing') THEN o.estimated_load_lost_mw END) as current_load_lost_mw,

    -- Asset health
    COUNT(ia.asset_id) as total_assets,
    COUNT(CASE WHEN ia.asset_status = 'operational' THEN 1 END) as operational_assets,
    ROUND(COUNT(CASE WHEN ia.asset_status = 'operational' THEN 1 END)::DECIMAL / COUNT(ia.asset_id) * 100, 1) as asset_availability,

    -- Customer metrics
    COUNT(DISTINCT c.customer_id) as total_customers,
    COUNT(CASE WHEN c.service_status = 'active' THEN 1 END) as active_customers,
    AVG(CASE WHEN ua.report_date >= CURRENT_DATE - INTERVAL '30 days' THEN ua.average_usage_per_customer END) as avg_usage_per_customer,

    -- Billing metrics
    SUM(CASE WHEN b.due_date >= CURRENT_DATE AND b.billing_status != 'paid' THEN b.total_amount END) as outstanding_billings,
    COUNT(CASE WHEN b.due_date < CURRENT_DATE AND b.billing_status != 'paid' THEN 1 END) as overdue_bills,

    -- Smart grid metrics
    COUNT(sd.device_id) as total_smart_devices,
    COUNT(CASE WHEN sd.device_status = 'active' THEN 1 END) as active_smart_devices,
    ROUND(COUNT(CASE WHEN sd.last_communication >= CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 1 END)::DECIMAL / COUNT(sd.device_id) * 100, 1) as device_connectivity_rate

FROM utilities u
LEFT JOIN outages o ON u.utility_id = o.utility_id
LEFT JOIN infrastructure_assets ia ON u.utility_id = ia.utility_id
LEFT JOIN service_zones sz ON u.utility_id = sz.utility_id
LEFT JOIN customers c ON sz.zone_id = c.service_zone_id
LEFT JOIN service_accounts sa ON c.customer_id = sa.customer_id
LEFT JOIN bills b ON sa.account_id = sa.account_id
LEFT JOIN usage_analytics ua ON ua.report_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN smart_devices sd ON sd.account_id = sa.account_id
GROUP BY u.utility_id, u.utility_name;

-- Refresh every 15 minutes
CREATE UNIQUE INDEX idx_utility_operations_dashboard ON utility_operations_dashboard (utility_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY utility_operations_dashboard;
```

## Security Considerations

### Data Encryption
```sql
-- Encrypt sensitive customer and operational data
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypt payment and personal information
CREATE OR REPLACE FUNCTION encrypt_customer_data(pii_data TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(pii_data, current_setting('utility.pii_key'));
END;
$$ LANGUAGE plpgsql;

-- Encrypt operational data (sensor readings, etc.)
CREATE OR REPLACE FUNCTION encrypt_operational_data(op_data TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(op_data, current_setting('utility.op_key'));
END;
$$ LANGUAGE plpgsql;

-- Mask sensitive data in logs
CREATE OR REPLACE FUNCTION mask_account_number(account_num TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN LEFT(account_num, 4) || REPEAT('*', LENGTH(account_num) - 8) || RIGHT(account_num, 4);
END;
$$ LANGUAGE plpgsql;
```

### Access Control
```sql
-- Role-based security for utility operations
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE meter_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE outages ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_data_access_policy ON customers
    FOR SELECT USING (
        customer_id = current_setting('app.customer_id')::UUID OR
        service_zone_id IN (
            SELECT sz.zone_id FROM service_zones sz
            JOIN utility_staff us ON sz.utility_id = us.utility_id
            WHERE us.user_id = current_setting('app.user_id')::UUID
        ) OR
        current_setting('app.user_role')::TEXT IN ('utility_admin', 'regulator')
    );

CREATE POLICY outage_access_policy ON outages
    FOR ALL USING (
        utility_id IN (
            SELECT utility_id FROM utility_staff
            WHERE user_id = current_setting('app.user_id')::UUID
        ) OR
        affected_customers > 100 OR -- Major outages are public
        current_setting('app.user_role')::TEXT IN ('emergency_services', 'regulator')
    );
```

### Audit Trail
```sql
-- Comprehensive utility audit logging
CREATE TABLE utility_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    utility_id UUID REFERENCES utilities(utility_id),
    customer_id UUID,
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    change_reason TEXT,
    data_classification VARCHAR(20) CHECK (data_classification IN ('public', 'internal', 'confidential', 'restricted')),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Audit trigger for critical utility operations
CREATE OR REPLACE FUNCTION utility_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO utility_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, utility_id, customer_id, session_id, ip_address, user_agent,
        data_classification
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME IN ('customers', 'service_accounts', 'bills') THEN
            (SELECT sz.utility_id FROM service_zones sz
             JOIN customers c ON sz.zone_id = c.service_zone_id
             WHERE c.customer_id = COALESCE(NEW.customer_id, OLD.customer_id))
        ELSE NULL END,
        COALESCE(NEW.customer_id, OLD.customer_id),
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE
            WHEN TG_TABLE_NAME IN ('customers', 'meter_readings') THEN 'confidential'
            WHEN TG_TABLE_NAME LIKE '%payment%' THEN 'restricted'
            WHEN TG_TABLE_NAME LIKE '%outage%' THEN 'internal'
            ELSE 'public'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### Regulatory Reporting Automation
```sql
-- Automated regulatory reporting for utility oversight
CREATE OR REPLACE FUNCTION generate_regulatory_report(
    utility_uuid UUID,
    report_type VARCHAR, -- 'quarterly', 'annual', 'incident'
    report_period_start DATE DEFAULT NULL,
    report_period_end DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    report_data JSONB,
    compliance_status VARCHAR,
    submission_deadline DATE,
    required_filings JSONB
) AS $$
DECLARE
    report_data_val JSONB := '{}';
    compliance_val VARCHAR := 'compliant';
    deadline_val DATE;
    filings_val JSONB := '[]';
BEGIN
    -- Set report period if not provided
    IF report_period_start IS NULL THEN
        report_period_start := CASE report_type
            WHEN 'quarterly' THEN date_trunc('quarter', report_period_end)
            WHEN 'annual' THEN date_trunc('year', report_period_end)
            ELSE report_period_end - INTERVAL '30 days'
        END;
    END IF;

    CASE report_type
        WHEN 'quarterly' THEN
            -- Generate quarterly operational report
            SELECT jsonb_build_object(
                'utility_info', jsonb_build_object('id', u.utility_id, 'name', u.utility_name),
                'reporting_period', jsonb_build_object('start', report_period_start, 'end', report_period_end),
                'operational_metrics', jsonb_build_object(
                    'total_customers', COUNT(DISTINCT c.customer_id),
                    'average_billing_rate', AVG(b.total_amount / b.usage_kwh),
                    'system_reliability', jsonb_build_object(
                        'saidi', AVG(ua.saidi_hours),
                        'saifi', AVG(ua.saifi_incidents)
                    ),
                    'outage_performance', jsonb_build_object(
                        'total_outages', COUNT(o.outage_id),
                        'average_restoration_time', AVG(EXTRACT(EPOCH FROM (o.actual_restoration - o.outage_start))/3600)
                    )
                ),
                'financial_metrics', jsonb_build_object(
                    'total_revenue', SUM(b.total_amount),
                    'average_revenue_per_customer', AVG(b.total_amount)
                )
            ) INTO report_data_val
            FROM utilities u
            LEFT JOIN service_zones sz ON u.utility_id = sz.utility_id
            LEFT JOIN customers c ON sz.zone_id = c.service_zone_id
            LEFT JOIN bills b ON c.customer_id = c.customer_id AND b.billing_period_start >= report_period_start
            LEFT JOIN usage_analytics ua ON ua.report_date BETWEEN report_period_start AND report_period_end
            LEFT JOIN outages o ON u.utility_id = o.utility_id AND o.outage_start BETWEEN report_period_start AND report_period_end
            WHERE u.utility_id = utility_uuid;

            deadline_val := report_period_end + INTERVAL '45 days';
            filings_val := jsonb_build_array(
                jsonb_build_object('form', 'FERC-1', 'description', 'Annual Report of Major Electric Utilities'),
                jsonb_build_object('form', 'EIA-861', 'description', 'Annual Electric Power Industry Report')
            );

        WHEN 'incident' THEN
            -- Generate incident report for major outages
            SELECT jsonb_build_object(
                'incident_details', jsonb_agg(
                    jsonb_build_object(
                        'outage_id', o.outage_id,
                        'start_time', o.outage_start,
                        'restoration_time', o.actual_restoration,
                        'duration_hours', EXTRACT(EPOCH FROM (o.actual_restoration - o.outage_start))/3600,
                        'affected_customers', o.affected_customers,
                        'cause', o.outage_cause,
                        'impact', jsonb_build_object(
                            'estimated_cost', o.estimated_cost,
                            'load_lost_mw', o.estimated_load_lost_mw
                        )
                    )
                ),
                'summary', jsonb_build_object(
                    'total_incidents', COUNT(o.outage_id),
                    'total_customers_affected', SUM(o.affected_customers),
                    'total_cost_estimate', SUM(o.estimated_cost)
                )
            ) INTO report_data_val
            FROM outages o
            WHERE o.utility_id = utility_uuid
              AND o.outage_start BETWEEN report_period_start AND report_period_end
              AND o.affected_customers > 100; -- Major incidents only

            deadline_val := report_period_end + INTERVAL '15 days';

    END CASE;

    -- Check compliance status
    IF deadline_val < CURRENT_DATE AND report_data_val = '{}'::jsonb THEN
        compliance_val := 'overdue';
    END IF;

    RETURN QUERY SELECT
        report_data_val,
        compliance_val,
        deadline_val,
        filings_val;
END;
$$ LANGUAGE plpgsql;
```

### Smart Meter Data Privacy and Security
```sql
-- Privacy-preserving smart meter data analytics
CREATE OR REPLACE FUNCTION aggregate_usage_privacy_preserving(
    zone_uuid UUID,
    aggregation_level VARCHAR DEFAULT 'hourly', -- 'hourly', 'daily', 'weekly'
    privacy_epsilon DECIMAL DEFAULT 0.1 -- Differential privacy parameter
)
RETURNS TABLE (
    time_bucket TIMESTAMP WITH TIME ZONE,
    aggregated_usage DECIMAL,
    customer_count INTEGER,
    privacy_guarantee DECIMAL,
    confidence_interval JSONB
) AS $$
DECLARE
    bucket_interval INTERVAL;
    noise_scale DECIMAL;
BEGIN
    -- Set aggregation level
    bucket_interval := CASE aggregation_level
        WHEN 'hourly' THEN INTERVAL '1 hour'
        WHEN 'daily' THEN INTERVAL '1 day'
        WHEN 'weekly' THEN INTERVAL '1 week'
        ELSE INTERVAL '1 hour'
    END;

    -- Calculate noise scale for differential privacy
    noise_scale := 1.0 / privacy_epsilon;

    RETURN QUERY
    SELECT
        date_trunc(CASE aggregation_level
            WHEN 'hourly' THEN 'hour'
            WHEN 'daily' THEN 'day'
            WHEN 'weekly' THEN 'week'
            ELSE 'hour'
        END, mr.reading_timestamp) as bucket,

        -- Add differential privacy noise to aggregated usage
        SUM(mr.consumption_kwh) + (random() - 0.5) * noise_scale * COUNT(*) as noisy_usage,

        COUNT(DISTINCT mr.account_id) as customer_count,

        privacy_epsilon,

        -- Provide confidence interval for the noisy result
        jsonb_build_object(
            'lower_bound', SUM(mr.consumption_kwh) - 1.96 * noise_scale * SQRT(COUNT(*)),
            'upper_bound', SUM(mr.consumption_kwh) + 1.96 * noise_scale * SQRT(COUNT(*)),
            'confidence_level', 0.95
        )

    FROM meter_readings mr
    JOIN service_accounts sa ON mr.account_id = sa.account_id
    JOIN customers c ON sa.customer_id = c.customer_id
    WHERE c.service_zone_id = zone_uuid
      AND mr.reading_timestamp >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY date_trunc(CASE aggregation_level
        WHEN 'hourly' THEN 'hour'
        WHEN 'daily' THEN 'day'
        WHEN 'weekly' THEN 'week'
        ELSE 'hour'
    END, mr.reading_timestamp)
    ORDER BY bucket;
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **SCADA systems** for real-time grid monitoring and control
- **GIS platforms** for infrastructure mapping and planning
- **Weather services** for demand forecasting and outage prediction
- **Regulatory systems** for automated reporting and compliance

### API Endpoints
- **Smart meter APIs** for real-time data collection and device management
- **Billing APIs** for automated bill generation and payment processing
- **Outage APIs** for real-time status updates and customer notifications
- **Analytics APIs** for operational insights and regulatory reporting

## Monitoring & Analytics

### Key Performance Indicators
- **System reliability metrics** (SAIDI, SAIFI, CAIDI)
- **Asset utilization** and maintenance effectiveness
- **Customer satisfaction** and billing accuracy rates
- **Smart grid performance** and IoT device connectivity
- **Regulatory compliance** and reporting timeliness

### Real-Time Dashboards
```sql
-- Utility control center dashboard
CREATE VIEW utility_control_center AS
SELECT
    u.utility_name,

    -- Real-time system status
    (SELECT COUNT(*) FROM outages WHERE outage_status IN ('reported', 'confirmed', 'crew_dispatched', 'repairing')) as active_outages,
    (SELECT SUM(affected_customers) FROM outages WHERE outage_status IN ('reported', 'confirmed', 'crew_dispatched', 'repairing')) as customers_without_power,
    (SELECT SUM(estimated_load_lost_mw) FROM outages WHERE outage_status IN ('reported', 'confirmed', 'crew_dispatched', 'repairing')) as current_load_shed_mw,

    -- Grid performance
    (SELECT AVG(consumption_kwh) FROM meter_readings WHERE reading_timestamp >= CURRENT_TIMESTAMP - INTERVAL '1 hour') as current_system_load_mw,
    (SELECT MAX(consumption_kwh) FROM meter_readings WHERE reading_timestamp >= CURRENT_TIMESTAMP - INTERVAL '24 hours') as peak_load_today_mw,

    -- Asset health
    (SELECT COUNT(*) FROM infrastructure_assets WHERE asset_status = 'operational') /
    (SELECT COUNT(*) FROM infrastructure_assets) * 100 as asset_availability_percentage,

    -- Customer service
    (SELECT COUNT(*) FROM support_tickets WHERE ticket_status = 'open') as open_customer_tickets,
    (SELECT AVG(customer_rating) FROM orders WHERE order_date = CURRENT_DATE) as todays_customer_satisfaction,

    -- Smart grid metrics
    (SELECT COUNT(*) FROM smart_devices WHERE device_status = 'active') as active_smart_devices,
    (SELECT COUNT(*) FROM sensor_readings WHERE reading_quality = 'good' AND reading_timestamp >= CURRENT_TIMESTAMP - INTERVAL '1 hour') /
    (SELECT COUNT(*) FROM sensor_readings WHERE reading_timestamp >= CURRENT_TIMESTAMP - INTERVAL '1 hour') * 100 as sensor_data_quality,

    -- Financial snapshot
    (SELECT SUM(total_amount) FROM bills WHERE billing_status = 'paid' AND payment_date = CURRENT_DATE) as todays_collections,
    (SELECT COUNT(*) FROM bills WHERE due_date < CURRENT_DATE AND billing_status != 'paid') as overdue_accounts
;
```

This energy utilities database schema provides enterprise-grade infrastructure for smart grid operations, customer service management, regulatory compliance, and operational analytics required for modern utility companies.
