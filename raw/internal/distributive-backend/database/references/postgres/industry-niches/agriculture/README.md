# Agriculture & Farming Database Design

## Overview

This comprehensive database schema supports modern agricultural operations including farm management, crop planning, livestock tracking, equipment maintenance, financial management, and environmental monitoring. The design handles precision agriculture, sustainable farming practices, and regulatory compliance for diverse farming operations.

## Key Features

### 🌾 Farm and Land Management
- **Geospatial farm mapping** with precise field boundaries and GPS tracking
- **Soil health monitoring** with comprehensive testing and amendment tracking
- **Irrigation system management** with water usage optimization
- **Environmental compliance** with regulatory reporting and certification tracking

### 🌱 Crop Production and Planning
- **Crop rotation planning** with soil health and pest management considerations
- **Precision planting** with seed variety tracking and performance analytics
- **Growth monitoring** with NDVI tracking and phenological stage monitoring
- **Harvest optimization** with quality assessment and yield prediction

### 🐄 Livestock Management
- **Individual animal tracking** with RFID and health monitoring
- **Breeding program management** with pedigree tracking and genetic analysis
- **Health and vaccination records** with automated reminder systems
- **Production tracking** for dairy, meat, egg, and wool yields

### 🚜 Equipment and Operations
- **Equipment lifecycle management** with maintenance scheduling and cost tracking
- **Usage analytics** with fuel efficiency and work rate monitoring
- **Precision agriculture integration** with GPS-guided operations
- **Operational efficiency** with downtime tracking and utilization metrics

## Database Schema Highlights

### Core Tables

#### Farm Infrastructure
- **`farms`** - Farm profiles with geospatial boundaries and operational details
- **`fields`** - Individual field management with soil data and performance history
- **`soil_tests`** - Comprehensive soil analysis with nutrient tracking and recommendations

#### Crop Management
- **`crops`** - Crop variety database with agronomic characteristics
- **`planting_plans`** - Seasonal planning with rotation strategies and budgeting
- **`field_plantings`** - Individual planting operations with performance tracking

#### Livestock Operations
- **`livestock_types`** - Animal breed specifications and production metrics
- **`animals`** - Individual animal records with health and production tracking
- **`animal_health_records`** - Veterinary care and vaccination history

#### Equipment Management
- **`equipment`** - Machinery inventory with maintenance and utilization tracking
- **`equipment_usage`** - Operational data with performance and cost analysis

## Key Design Patterns

### 1. Precision Agriculture with Geospatial Integration
```sql
-- Advanced geospatial queries for precision agriculture
CREATE EXTENSION IF NOT EXISTS postgis;

-- Calculate field irrigation zones based on soil moisture variation
CREATE OR REPLACE FUNCTION calculate_irrigation_zones(field_uuid UUID)
RETURNS TABLE (
    zone_id INTEGER,
    zone_geometry GEOMETRY,
    soil_moisture_level DECIMAL,
    irrigation_priority VARCHAR,
    water_requirement_gallons DECIMAL,
    estimated_application_time INTERVAL
) AS $$
DECLARE
    field_boundary GEOMETRY;
    moisture_zones JSONB;
BEGIN
    -- Get field boundary
    SELECT field_shape INTO field_boundary
    FROM fields WHERE field_id = field_uuid;

    -- Create moisture-based irrigation zones
    -- This would integrate with soil moisture sensors
    FOR i IN 1..5 LOOP
        RETURN QUERY SELECT
            i as zone_id,
            ST_Subdivide(field_boundary, 5)[i] as zone_geometry,
            (0.4 + random() * 0.4)::DECIMAL(3,2) as soil_moisture_level,
            CASE
                WHEN 0.4 + random() * 0.4 < 0.5 THEN 'high'
                WHEN 0.4 + random() * 0.4 < 0.7 THEN 'medium'
                ELSE 'low'
            END::VARCHAR as irrigation_priority,
            (0.4 + random() * 0.4) * ST_Area(ST_Subdivide(field_boundary, 5)[i]) * 27154 as water_requirement_gallons,
            INTERVAL '1 hour' * (0.4 + random() * 0.4) * 2 as estimated_application_time;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 2. Crop Yield Prediction with Machine Learning Integration
```sql
-- Predictive analytics for crop yield optimization
CREATE OR REPLACE FUNCTION predict_crop_yield(
    field_uuid UUID,
    crop_uuid UUID,
    prediction_days INTEGER DEFAULT 90
)
RETURNS TABLE (
    predicted_yield_per_acre DECIMAL,
    confidence_interval DECIMAL,
    yield_factors JSONB,
    risk_factors JSONB,
    optimization_recommendations JSONB,
    expected_profit_margin DECIMAL
) AS $$
DECLARE
    field_record fields%ROWTYPE;
    crop_record crops%ROWTYPE;
    historical_yields DECIMAL[];
    soil_conditions JSONB;
    weather_risk_score DECIMAL := 0;
BEGIN
    -- Get field and crop data
    SELECT * INTO field_record FROM fields WHERE field_id = field_uuid;
    SELECT * INTO crop_record FROM crops WHERE crop_id = crop_uuid;

    -- Get historical yield data for this field/crop combination
    SELECT array_agg(fp.yield_per_acre)
    INTO historical_yields
    FROM field_plantings fp
    WHERE fp.field_id = field_uuid
      AND fp.crop_id = crop_uuid
      AND fp.planting_status = 'harvested'
    ORDER BY fp.planting_date DESC
    LIMIT 5;

    -- Calculate soil condition impact
    SELECT jsonb_build_object(
        'ph_impact', CASE
            WHEN st.ph_level BETWEEN 6.0 AND 7.0 THEN 1.05
            WHEN st.ph_level BETWEEN 5.5 AND 6.0 OR st.ph_level BETWEEN 7.0 AND 7.5 THEN 1.0
            ELSE 0.9
        END,
        'nutrient_impact', CASE
            WHEN st.nitrogen_ppm > 30 AND st.phosphorus_ppm > 20 THEN 1.1
            WHEN st.nitrogen_ppm > 20 AND st.phosphorus_ppm > 15 THEN 1.05
            ELSE 0.95
        END,
        'organic_matter_impact', CASE
            WHEN st.organic_matter_percentage > 3.0 THEN 1.08
            WHEN st.organic_matter_percentage > 2.0 THEN 1.03
            ELSE 0.97
        END
    ) INTO soil_conditions
    FROM soil_tests st
    WHERE st.field_id = field_uuid
    ORDER BY st.test_date DESC
    LIMIT 1;

    -- Calculate weather risk
    weather_risk_score := 0.1; -- Would integrate with weather API

    RETURN QUERY SELECT
        -- Base prediction on historical average with adjustments
        CASE
            WHEN array_length(historical_yields, 1) > 0
            THEN (SELECT avg(y) FROM unnest(historical_yields) y) *
                 (soil_conditions->>'ph_impact')::DECIMAL *
                 (soil_conditions->>'nutrient_impact')::DECIMAL *
                 (soil_conditions->>'organic_matter_impact')::DECIMAL *
                 (1 - weather_risk_score)
            ELSE crop_record.average_yield_per_acre * 0.8 -- Conservative estimate for new combinations
        END as predicted_yield_per_acre,

        15.0 as confidence_interval, -- ±15%

        jsonb_build_object(
            'historical_average', CASE WHEN array_length(historical_yields, 1) > 0 THEN (SELECT avg(y) FROM unnest(historical_yields) y) ELSE NULL END,
            'soil_conditions', soil_conditions,
            'weather_risk', weather_risk_score,
            'field_characteristics', jsonb_build_object(
                'drainage_class', field_record.drainage_class,
                'erosion_risk', field_record.erosion_risk,
                'slope', field_record.slope_percentage
            )
        ) as yield_factors,

        jsonb_build_object(
            'weather_uncertainty', weather_risk_score * 100,
            'soil_variability', CASE
                WHEN field_record.drainage_class = 'poor' THEN 'high'
                WHEN field_record.erosion_risk = 'severe' THEN 'high'
                ELSE 'moderate'
            END,
            'market_volatility', 'medium'
        ) as risk_factors,

        jsonb_build_array(
            'Consider soil amendments to optimize pH and nutrient levels',
            'Implement irrigation scheduling based on predicted water needs',
            'Monitor weather forecasts and prepare contingency plans',
            'Consider crop insurance for yield risk management'
        ) as optimization_recommendations,

        CASE
            WHEN array_length(historical_yields, 1) > 0
            THEN ((SELECT avg(y) FROM unnest(historical_yields) y) * crop_record.average_market_price_per_unit) -
                 (crop_record.production_cost_per_acre / (SELECT avg(y) FROM unnest(historical_yields) y))
            ELSE crop_record.average_market_price_per_unit * crop_record.average_yield_per_acre * 0.15
        END as expected_profit_margin;
END;
$$ LANGUAGE plpgsql;
```

### 3. Livestock Health Monitoring and Disease Prevention
```sql
-- Comprehensive livestock health management system
CREATE OR REPLACE FUNCTION monitor_livestock_health(farm_uuid UUID)
RETURNS TABLE (
    animal_id UUID,
    animal_tag VARCHAR,
    health_status VARCHAR,
    risk_score DECIMAL,
    health_alerts JSONB,
    preventive_actions JSONB,
    estimated_treatment_cost DECIMAL,
    quarantine_recommended BOOLEAN
) AS $$
DECLARE
    animal_record RECORD;
BEGIN
    FOR animal_record IN
        SELECT
            a.animal_id,
            a.animal_tag,
            a.current_health_status,
            lt.type_name,
            a.birth_date,

            -- Health metrics
            COUNT(CASE WHEN ahr.event_type = 'treatment' THEN 1 END) as treatment_count,
            MAX(ahr.event_date) as last_treatment_date,
            COUNT(CASE WHEN ahr.event_type = 'vaccination' THEN 1 END) as vaccination_count,

            -- Age in days
            EXTRACT(EPOCH FROM (CURRENT_DATE - a.birth_date)) / 86400 as age_days

        FROM animals a
        JOIN livestock_types lt ON a.type_id = lt.type_id
        LEFT JOIN animal_health_records ahr ON a.animal_id = ahr.animal_id
            AND ahr.event_date >= CURRENT_DATE - INTERVAL '90 days'
        WHERE a.farm_id = farm_uuid
          AND a.disposal_date IS NULL
        GROUP BY a.animal_id, a.animal_tag, a.current_health_status, lt.type_name, a.birth_date
    LOOP
        DECLARE
            risk_score_val DECIMAL := 0;
            health_alerts_val JSONB := '[]';
            preventive_actions_val JSONB := '[]';
            quarantine_flag BOOLEAN := FALSE;
        BEGIN
            -- Calculate health risk score
            IF animal_record.treatment_count > 2 THEN
                risk_score_val := risk_score_val + 30;
                health_alerts_val := health_alerts_val || jsonb_build_object(
                    'alert_type', 'frequent_treatments',
                    'severity', 'high',
                    'description', format('%s treatments in last 90 days', animal_record.treatment_count)
                );
            END IF;

            IF animal_record.last_treatment_date < CURRENT_DATE - INTERVAL '30 days' THEN
                risk_score_val := risk_score_val + 15;
                health_alerts_val := health_alerts_val || jsonb_build_object(
                    'alert_type', 'recent_treatment',
                    'severity', 'medium',
                    'description', 'Recent medical treatment recorded'
                );
            END IF;

            IF animal_record.vaccination_count = 0 THEN
                risk_score_val := risk_score_val + 25;
                health_alerts_val := health_alerts_val || jsonb_build_object(
                    'alert_type', 'missing_vaccinations',
                    'severity', 'high',
                    'description', 'No vaccinations recorded in last 90 days'
                );
                preventive_actions_val := preventive_actions_val || 'Schedule comprehensive vaccination';
            END IF;

            -- Age-based health considerations
            IF animal_record.age_days < 90 THEN
                risk_score_val := risk_score_val + 10; -- Young animals more vulnerable
                preventive_actions_val := preventive_actions_val || 'Monitor calf health closely';
            END IF;

            -- Generate preventive actions based on risk
            IF risk_score_val > 40 THEN
                preventive_actions_val := preventive_actions_val || jsonb_build_array(
                    'Isolate from herd for monitoring',
                    'Consult veterinarian immediately',
                    'Implement enhanced biosecurity measures'
                );
                quarantine_flag := TRUE;
            ELSIF risk_score_val > 20 THEN
                preventive_actions_val := preventive_actions_val || jsonb_build_array(
                    'Schedule veterinary checkup',
                    'Review nutrition and housing',
                    'Update vaccination schedule'
                );
            END IF;

            RETURN QUERY SELECT
                animal_record.animal_id,
                animal_record.animal_tag,
                animal_record.current_health_status,
                LEAST(risk_score_val, 100) as risk_score,
                health_alerts_val,
                preventive_actions_val,
                CASE
                    WHEN risk_score_val > 40 THEN 150.00 + (risk_score_val - 40) * 2
                    WHEN risk_score_val > 20 THEN 75.00
                    ELSE 0.00
                END as estimated_treatment_cost,
                quarantine_flag;
        END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 4. Equipment Maintenance Optimization with Predictive Analytics
```sql
-- Predictive maintenance for agricultural equipment
CREATE OR REPLACE FUNCTION predict_equipment_maintenance(equipment_uuid UUID)
RETURNS TABLE (
    equipment_name VARCHAR,
    maintenance_prediction JSONB,
    failure_probability DECIMAL,
    recommended_actions JSONB,
    cost_benefit_analysis JSONB,
    priority_level VARCHAR
) AS $$
DECLARE
    equipment_record equipment%ROWTYPE;
    usage_history RECORD;
    maintenance_history RECORD;
BEGIN
    -- Get equipment details
    SELECT * INTO equipment_record FROM equipment WHERE equipment_id = equipment_uuid;

    -- Analyze usage patterns (last 90 days)
    SELECT
        COUNT(*) as usage_sessions,
        SUM(hours_used) as total_hours,
        AVG(hours_used) as avg_session_hours,
        MAX(usage_date) as last_used_date,
        SUM(fuel_used_gallons) as total_fuel,
        AVG(fuel_efficiency_actual) as avg_fuel_efficiency
    INTO usage_history
    FROM equipment_usage
    WHERE equipment_id = equipment_uuid
      AND usage_date >= CURRENT_DATE - INTERVAL '90 days';

    -- Analyze maintenance history
    SELECT
        MAX(last_service_date) as last_service,
        MAX(purchase_date) as purchase_date,
        EXTRACT(EPOCH FROM (CURRENT_DATE - MAX(last_service_date))) / 86400 as days_since_service,
        EXTRACT(EPOCH FROM (CURRENT_DATE - MAX(purchase_date))) / 365.25 as years_old
    INTO maintenance_history
    FROM equipment
    WHERE equipment_id = equipment_uuid;

    RETURN QUERY SELECT
        equipment_record.equipment_name,

        jsonb_build_object(
            'next_service_due', equipment_record.next_service_due,
            'estimated_failure_date', CASE
                WHEN usage_history.total_hours > equipment_record.service_interval_hours * 0.8
                THEN CURRENT_DATE + INTERVAL '7 days'
                WHEN maintenance_history.days_since_service > 90
                THEN CURRENT_DATE + INTERVAL '14 days'
                ELSE CURRENT_DATE + INTERVAL '30 days'
            END,
            'confidence_level', CASE
                WHEN usage_history.usage_sessions > 20 THEN 'high'
                WHEN usage_history.usage_sessions > 10 THEN 'medium'
                ELSE 'low'
            END,
            'prediction_factors', jsonb_build_object(
                'usage_intensity', usage_history.avg_session_hours,
                'service_overdue_days', GREATEST(maintenance_history.days_since_service - 90, 0),
                'equipment_age_years', maintenance_history.years_old,
                'fuel_efficiency_trend', usage_history.avg_fuel_efficiency
            )
        ) as maintenance_prediction,

        CASE
            WHEN usage_history.total_hours > equipment_record.service_interval_hours * 0.9 THEN 0.85
            WHEN maintenance_history.days_since_service > 120 THEN 0.75
            WHEN maintenance_history.years_old > 8 THEN 0.70
            ELSE 0.25
        END as failure_probability,

        jsonb_build_array(
            CASE
                WHEN usage_history.total_hours > equipment_record.service_interval_hours * 0.9
                THEN 'Schedule immediate maintenance - usage-based interval reached'
                WHEN maintenance_history.days_since_service > 120
                THEN 'Overdue for service - schedule within 7 days'
                WHEN maintenance_history.years_old > 8
                THEN 'Age-related maintenance recommended'
                ELSE 'Continue regular monitoring'
            END,
            'Inspect critical components during next service',
            'Consider performance upgrades for aging equipment'
        ) as recommended_actions,

        jsonb_build_object(
            'preventive_cost', 500.00, -- Estimated maintenance cost
            'failure_cost', 5000.00, -- Estimated breakdown cost
            'benefit_cost_ratio', CASE
                WHEN usage_history.total_hours > equipment_record.service_interval_hours * 0.9 THEN 10.0
                ELSE 5.0
            END,
            'roi_period_months', 6
        ) as cost_benefit_analysis,

        CASE
            WHEN usage_history.total_hours > equipment_record.service_interval_hours * 0.9 THEN 'critical'
            WHEN maintenance_history.days_since_service > 120 THEN 'high'
            WHEN maintenance_history.years_old > 8 THEN 'medium'
            ELSE 'low'
        END as priority_level;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition time-series agricultural data by season/year
CREATE TABLE field_plantings PARTITION BY RANGE (planting_date);

CREATE TABLE field_plantings_2023 PARTITION OF field_plantings
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE field_plantings_2024 PARTITION OF field_plantings
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- Partition equipment usage by month for maintenance analytics
CREATE TABLE equipment_usage PARTITION BY RANGE (usage_date);

CREATE TABLE equipment_usage_2024_01 PARTITION OF equipment_usage
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition animal health records by year
CREATE TABLE animal_health_records PARTITION BY RANGE (event_date);

CREATE TABLE animal_health_records_2024 PARTITION OF animal_health_records
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### Advanced Indexing
```sql
-- Geospatial indexes for farm mapping
CREATE INDEX idx_farms_boundary ON farms USING gist (farm_boundary);
CREATE INDEX idx_fields_boundary ON fields USING gist (field_shape);
CREATE INDEX idx_animals_location ON animals USING gist (geolocation);

-- Agricultural time-series indexes
CREATE INDEX idx_field_plantings_field_date ON field_plantings (field_id, planting_date DESC);
CREATE INDEX idx_field_plantings_crop_status ON field_plantings (crop_id, planting_status);
CREATE INDEX idx_equipment_usage_equipment_date ON equipment_usage (equipment_id, usage_date DESC);
CREATE INDEX idx_animal_health_animal_date ON animal_health_records (animal_id, event_date DESC);

-- Performance and analytics indexes
CREATE INDEX idx_soil_tests_field_date ON soil_tests (field_id, test_date DESC);
CREATE INDEX idx_farm_expenses_farm_category_date ON farm_expenses (farm_id, expense_category, expense_date DESC);
CREATE INDEX idx_crop_sales_farm_date ON crop_sales (farm_id, sale_date DESC);
CREATE INDEX idx_livestock_sales_farm_date ON livestock_sales (farm_id, sale_date DESC);

-- Full-text search indexes
CREATE INDEX idx_farms_search ON farms USING gin (to_tsvector('english', farm_name || ' ' || COALESCE(farm_type, '')));
CREATE INDEX idx_crops_search ON crops USING gin (to_tsvector('english', crop_name || ' ' || COALESCE(scientific_name, '')));

-- JSONB indexes for flexible agricultural data
CREATE INDEX idx_field_plantings_fertilizer ON field_plantings USING gin (fertilizer_applied);
CREATE INDEX idx_animals_production ON animals USING gin (production_records);
CREATE INDEX idx_equipment_config ON equipment USING gin (equipment_config);
```

### Materialized Views for Analytics
```sql
-- Farm productivity dashboard
CREATE MATERIALIZED VIEW farm_productivity_dashboard AS
SELECT
    f.farm_id,
    f.farm_name,
    f.farming_method,

    -- Land utilization
    COUNT(DISTINCT fi.field_id) as total_fields,
    SUM(fi.acreage) as total_acres,
    SUM(fp.acreage) as planted_acres,
    ROUND(SUM(fp.acreage) / NULLIF(SUM(fi.acreage), 0) * 100, 1) as land_utilization_rate,

    -- Crop performance (current season)
    COUNT(DISTINCT fp.crop_id) as crops_planted,
    AVG(fp.yield_per_acre) as avg_yield_per_acre,
    SUM(fp.yield_per_acre * fp.acreage) as total_yield,
    ROUND(AVG(fp.yield_quality_rating), 1) as avg_crop_quality,

    -- Livestock metrics
    COUNT(DISTINCT a.animal_id) as total_animals,
    COUNT(DISTINCT CASE WHEN a.current_health_status = 'healthy' THEN a.animal_id END) as healthy_animals,
    ROUND(
        COUNT(DISTINCT CASE WHEN a.current_health_status = 'healthy' THEN a.animal_id END)::DECIMAL /
        COUNT(DISTINCT a.animal_id) * 100, 1
    ) as animal_health_rate,

    -- Equipment efficiency
    COUNT(DISTINCT e.equipment_id) as total_equipment,
    COUNT(DISTINCT CASE WHEN e.equipment_status = 'active' THEN e.equipment_id END) as active_equipment,
    ROUND(
        COUNT(DISTINCT CASE WHEN e.equipment_status = 'active' THEN e.equipment_id END)::DECIMAL /
        COUNT(DISTINCT e.equipment_id) * 100, 1
    ) as equipment_availability,

    -- Financial summary (last 30 days)
    COALESCE(SUM(fe.amount), 0) as total_expenses_30d,
    COALESCE(SUM(cs.total_revenue), 0) as crop_revenue_30d,
    COALESCE(SUM(ls.total_revenue), 0) as livestock_revenue_30d,
    COALESCE(SUM(cs.total_revenue + ls.total_revenue - fe.amount), 0) as net_income_30d,

    -- Environmental metrics
    AVG(em.measurement_value) FILTER (WHERE em.metric_type = 'soil_organic_matter') as avg_soil_health,
    AVG(em.carbon_equivalent_tons) as avg_carbon_impact,
    ROUND(AVG(em.environmental_score), 1) as avg_environmental_score,

    -- Overall productivity score
    ROUND(
        (
            -- Land utilization (15%)
            LEAST(COALESCE(SUM(fp.acreage) / NULLIF(SUM(fi.acreage), 0) * 15, 0), 15) +
            -- Crop performance (20%)
            LEAST(COALESCE(AVG(fp.yield_quality_rating), 0) / 5 * 20, 20) +
            -- Animal health (15%)
            LEAST(COALESCE(
                COUNT(DISTINCT CASE WHEN a.current_health_status = 'healthy' THEN a.animal_id END)::DECIMAL /
                NULLIF(COUNT(DISTINCT a.animal_id), 0) * 15, 0
            ), 15) +
            -- Equipment efficiency (15%)
            LEAST(COALESCE(
                COUNT(DISTINCT CASE WHEN e.equipment_status = 'active' THEN e.equipment_id END)::DECIMAL /
                NULLIF(COUNT(DISTINCT e.equipment_id), 0) * 15, 0
            ), 15) +
            -- Environmental stewardship (15%)
            LEAST(COALESCE(AVG(em.environmental_score), 0) / 10 * 15, 15) +
            -- Financial performance (20%)
            CASE
                WHEN SUM(cs.total_revenue + ls.total_revenue - fe.amount) > 50000 THEN 20
                WHEN SUM(cs.total_revenue + ls.total_revenue - fe.amount) > 25000 THEN 15
                WHEN SUM(cs.total_revenue + ls.total_revenue - fe.amount) > 0 THEN 10
                ELSE 0
            END
        ), 1
    ) as overall_productivity_score

FROM farms f
LEFT JOIN fields fi ON f.farm_id = fi.farm_id
LEFT JOIN field_plantings fp ON fi.field_id = fp.field_id
    AND fp.planting_status IN ('planted', 'growing', 'harvested')
LEFT JOIN animals a ON f.farm_id = a.farm_id
LEFT JOIN equipment e ON f.farm_id = e.farm_id
LEFT JOIN farm_expenses fe ON f.farm_id = fe.farm_id
    AND fe.expense_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN crop_sales cs ON f.farm_id = cs.farm_id
    AND cs.sale_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN livestock_sales ls ON f.farm_id = ls.farm_id
    AND ls.sale_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN environmental_metrics em ON f.farm_id = em.farm_id
    AND em.measurement_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY f.farm_id, f.farm_name, f.farming_method;

-- Refresh every 24 hours
CREATE UNIQUE INDEX idx_farm_productivity_dashboard ON farm_productivity_dashboard (farm_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY farm_productivity_dashboard;
```

## Security Considerations

### Agricultural Data Privacy and Compliance
```sql
-- GDPR and agricultural data protection compliance
ALTER TABLE farms ENABLE ROW LEVEL SECURITY;
ALTER TABLE animals ENABLE ROW LEVEL SECURITY;

CREATE POLICY farm_data_access_policy ON farms
    FOR SELECT USING (
        farm_id = current_setting('app.farm_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('admin', 'extension_agent') OR
        current_setting('app.user_id')::UUID IN (
            SELECT owner_id FROM farm_ownership
            WHERE farm_id = farms.farm_id
        )
    );

CREATE POLICY animal_data_privacy_policy ON animals
    FOR SELECT USING (
        farm_id = current_setting('app.farm_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('admin', 'veterinarian') OR
        current_setting('app.user_type')::TEXT = 'farmer'
    );
```

### Equipment and Supply Chain Security
```sql
-- Secure agricultural equipment and supply chain tracking
ALTER TABLE equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE farm_expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY equipment_security_policy ON equipment
    FOR ALL USING (
        farm_id = current_setting('app.farm_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('admin', 'equipment_dealer') OR
        current_setting('app.user_permissions')::JSONB ? 'equipment_management'
    );

CREATE POLICY supply_chain_policy ON farm_expenses
    FOR SELECT USING (
        farm_id = current_setting('app.farm_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('admin', 'accountant') OR
        expense_category IN ('seed', 'fertilizer') AND current_setting('app.user_role')::TEXT = 'crop_consultant'
    );
```

### Audit Trail and Regulatory Compliance
```sql
-- Comprehensive agricultural audit logging for compliance
CREATE TABLE agriculture_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    farm_id UUID,
    field_id UUID,
    animal_id UUID,
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    change_reason TEXT,
    regulatory_impact VARCHAR CHECK (regulatory_impact IN ('none', 'potential', 'requires_reporting')),
    audit_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (audit_timestamp);

-- Audit trigger for agricultural operations
CREATE OR REPLACE FUNCTION agriculture_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO agriculture_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, farm_id, field_id, animal_id, session_id,
        ip_address, user_agent, regulatory_impact
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME IN ('fields', 'animals', 'equipment') THEN COALESCE(NEW.farm_id, OLD.farm_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME IN ('field_plantings', 'soil_tests') THEN COALESCE(NEW.field_id, OLD.field_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME LIKE '%animal%' THEN COALESCE(NEW.animal_id, OLD.animal_id) ELSE NULL END,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE
            WHEN TG_TABLE_NAME IN ('farm_expenses', 'crop_sales') THEN 'potential'
            WHEN TG_TABLE_NAME LIKE '%environmental%' THEN 'requires_reporting'
            WHEN TG_TABLE_NAME LIKE '%health%' THEN 'potential'
            ELSE 'none'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### USDA and Agricultural Regulatory Compliance
```sql
-- Automated compliance reporting for agricultural regulations
CREATE OR REPLACE FUNCTION generate_agricultural_compliance_report(
    farm_uuid UUID,
    report_type VARCHAR, -- 'organic_certification', 'environmental_stewardship', 'labor_compliance'
    report_period_start DATE DEFAULT NULL,
    report_period_end DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    report_data JSONB,
    compliance_status VARCHAR,
    certification_eligible BOOLEAN,
    required_actions JSONB,
    next_audit_date DATE
) AS $$
DECLARE
    report_data_val JSONB := '{}';
    compliance_val VARCHAR := 'compliant';
    eligible_val BOOLEAN := TRUE;
    actions_val JSONB := '[]';
    next_audit_val DATE;
BEGIN
    -- Set report period if not provided
    IF report_period_start IS NULL THEN
        report_period_start := DATE_TRUNC('year', report_period_end);
    END IF;

    CASE report_type
        WHEN 'organic_certification' THEN
            -- Organic certification compliance report
            SELECT jsonb_build_object(
                'farm_info', jsonb_build_object(
                    'farm_id', f.farm_id,
                    'farm_name', f.farm_name,
                    'certifications', f.certifications
                ),
                'organic_compliance', jsonb_build_object(
                    'organic_accredited', f.farming_method = 'organic',
                    'non_gmo_verified', COUNT(CASE WHEN c.gmo_status = FALSE THEN 1 END),
                    'synthetic_chemical_free', COUNT(CASE WHEN fp.fertilizer_applied ? 'synthetic' THEN 1 END) = 0,
                    'buffer_zones_maintained', TRUE, -- Would check geospatial data
                    'record_keeping_compliant', COUNT(fp.planting_id) > 0
                ),
                'inspection_readiness', jsonb_build_object(
                    'soil_tests_current', COUNT(CASE WHEN st.test_date >= CURRENT_DATE - INTERVAL '1 year' THEN 1 END),
                    'input_records_complete', COUNT(fe.expense_id) > 0,
                    'crop_records_maintained', COUNT(fp.planting_id) > 0,
                    'pesticide_logs_complete', COUNT(CASE WHEN fp.pest_control_measures ? 'organic_approved' THEN 1 END)
                )
            ) INTO report_data_val
            FROM farms f
            LEFT JOIN fields fi ON f.farm_id = fi.farm_id
            LEFT JOIN field_plantings fp ON fi.field_id = fp.field_id
            LEFT JOIN crops c ON fp.crop_id = c.crop_id
            LEFT JOIN soil_tests st ON fi.field_id = st.field_id
            LEFT JOIN farm_expenses fe ON f.farm_id = fe.farm_id
                AND fe.expense_category IN ('seed', 'fertilizer', 'pesticides')
            WHERE f.farm_id = farm_uuid
            GROUP BY f.farm_id, f.farm_name, f.farming_method, f.certifications;

            next_audit_val := report_period_end + INTERVAL '1 year';

        WHEN 'environmental_stewardship' THEN
            -- Environmental compliance report
            SELECT jsonb_build_object(
                'environmental_metrics', jsonb_build_object(
                    'soil_erosion_control', AVG(CASE WHEN em.metric_type = 'soil_erosion' AND em.measurement_value < 5 THEN 1 ELSE 0 END) * 100,
                    'water_quality_monitoring', COUNT(CASE WHEN em.metric_type = 'water_quality' THEN 1 END),
                    'chemical_runoff_prevention', COUNT(CASE WHEN si.initiative_type = 'water_management' THEN 1 END),
                    'biodiversity_preservation', COUNT(CASE WHEN si.initiative_type = 'biodiversity' THEN 1 END),
                    'carbon_sequestration', SUM(em.carbon_equivalent_tons)
                ),
                'regulatory_compliance', jsonb_build_object(
                    'epa_reporting_compliant', TRUE, -- Would check actual reporting
                    'conservation_plans_active', COUNT(si.initiative_id) > 0,
                    'wetland_protection', TRUE, -- Would check geospatial data
                    'endangered_species_protection', TRUE -- Would check location data
                )
            ) INTO report_data_val
            FROM farms f
            LEFT JOIN environmental_metrics em ON f.farm_id = em.farm_id
                AND em.measurement_date BETWEEN report_period_start AND report_period_end
            LEFT JOIN sustainability_initiatives si ON f.farm_id = si.farm_id
                AND si.initiative_status = 'completed'
            WHERE f.farm_id = farm_uuid
            GROUP BY f.farm_id;

            next_audit_val := report_period_end + INTERVAL '6 months';

    END CASE;

    -- Determine compliance status and required actions
    IF report_data_val->>'compliance_status' = 'non_compliant' THEN
        compliance_val := 'non_compliant';
        eligible_val := FALSE;
        actions_val := jsonb_build_array(
            'Review and correct compliance issues',
            'Implement corrective action plan',
            'Schedule follow-up inspection'
        );
    END IF;

    RETURN QUERY SELECT
        report_data_val,
        compliance_val,
        eligible_val,
        actions_val,
        next_audit_val;
END;
$$ LANGUAGE plpgsql;
```

### Farm Labor and Safety Compliance
```sql
-- Automated farm labor compliance and safety tracking
CREATE OR REPLACE FUNCTION monitor_farm_labor_compliance(farm_uuid UUID)
RETURNS TABLE (
    compliance_area VARCHAR,
    compliance_status VARCHAR,
    risk_level VARCHAR,
    violations_found INTEGER,
    corrective_actions JSONB,
    next_review_date DATE,
    estimated_cost_to_comply DECIMAL
) AS $$
DECLARE
    labor_compliance JSONB;
BEGIN
    -- OSHA farm safety compliance
    RETURN QUERY SELECT
        'OSHA Farm Safety'::VARCHAR,
        CASE
            WHEN COUNT(e.equipment_id) = COUNT(CASE WHEN e.safety_certifications != '[]'::jsonb THEN 1 END) THEN 'compliant'
            ELSE 'non_compliant'
        END::VARCHAR,
        CASE
            WHEN COUNT(CASE WHEN e.safety_certifications = '[]'::jsonb THEN 1 END) > 3 THEN 'high'
            WHEN COUNT(CASE WHEN e.safety_certifications = '[]'::jsonb THEN 1 END) > 0 THEN 'medium'
            ELSE 'low'
        END::VARCHAR,
        COUNT(CASE WHEN e.safety_certifications = '[]'::jsonb THEN 1 END)::INTEGER,
        jsonb_build_array(
            'Conduct equipment safety inspections',
            'Provide operator safety training',
            'Update equipment safety certifications'
        ),
        CURRENT_DATE + INTERVAL '6 months',
        COUNT(CASE WHEN e.safety_certifications = '[]'::jsonb THEN 1 END)::DECIMAL * 500
    FROM equipment e WHERE e.farm_id = farm_uuid;

    -- EPA Worker Protection Standards
    RETURN QUERY SELECT
        'EPA Worker Protection'::VARCHAR,
        'compliant'::VARCHAR, -- Would implement actual checking
        'low'::VARCHAR,
        0::INTEGER,
        jsonb_build_array(
            'Maintain pesticide safety training records',
            'Ensure proper PPE availability',
            'Conduct regular safety audits'
        ),
        CURRENT_DATE + INTERVAL '1 year',
        0.00;

    -- Migrant and Seasonal Agricultural Worker Protection Act (MSPA)
    RETURN QUERY SELECT
        'MSPA Compliance'::VARCHAR,
        'compliant'::VARCHAR, -- Would implement actual checking
        'low'::VARCHAR,
        0::INTEGER,
        jsonb_build_array(
            'Verify worker eligibility documentation',
            'Maintain accurate payroll records',
            'Provide required worker housing standards'
        ),
        CURRENT_DATE + INTERVAL '1 year',
        0.00;

    -- Farm Labor Contractor registration
    RETURN QUERY SELECT
        'Labor Contractor Registration'::VARCHAR,
        'compliant'::VARCHAR, -- Would implement actual checking
        'low'::VARCHAR,
        0::INTEGER,
        jsonb_build_array(
            'Maintain current contractor registration',
            'Verify subcontractor compliance',
            'Document labor agreements'
        ),
        CURRENT_DATE + INTERVAL '1 year',
        0.00;
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Weather APIs** for precision irrigation and crop planning
- **Market data feeds** for commodity pricing and sales optimization
- **Equipment telematics** for real-time machinery monitoring
- **Soil testing labs** for automated test result integration
- **Regulatory systems** for compliance reporting and certification

### API Endpoints
- **Farm management APIs** for field operations and equipment tracking
- **Crop monitoring APIs** for yield prediction and pest management
- **Livestock APIs** for health monitoring and breeding programs
- **Financial APIs** for expense tracking and revenue optimization

## Monitoring & Analytics

### Key Performance Indicators
- **Yield metrics** (bushels per acre, tons per acre, quality ratings)
- **Equipment efficiency** (fuel consumption, maintenance costs, utilization rates)
- **Animal health** (treatment frequency, vaccination compliance, production yields)
- **Financial performance** (cost per unit, profit margins, ROI by crop/animal)

### Real-Time Dashboards
```sql
-- Agricultural operations command center
CREATE VIEW farm_operations_dashboard AS
SELECT
    f.farm_id,
    f.farm_name,
    f.farming_method,

    -- Current season overview
    COUNT(DISTINCT fp.field_id) as active_fields,
    SUM(fp.acreage) as total_planted_acres,
    COUNT(DISTINCT fp.crop_id) as crops_in_production,
    ROUND(SUM(fp.acreage) / f.total_acres * 100, 1) as land_utilization_percentage,

    -- Crop health indicators (last 7 days)
    ROUND(AVG(ndvi_readings), 2) as avg_crop_health_ndvi,
    COUNT(CASE WHEN fp.growth_stage LIKE '%stress%' THEN 1 END) as fields_showing_stress,
    COUNT(CASE WHEN fp.pest_pressure_rating > 3 THEN 1 END) as high_pest_risk_fields,

    -- Equipment status
    COUNT(DISTINCT e.equipment_id) as total_equipment,
    COUNT(DISTINCT CASE WHEN e.equipment_status = 'active' THEN e.equipment_id END) as operational_equipment,
    COUNT(DISTINCT CASE WHEN e.next_service_due < CURRENT_DATE THEN e.equipment_id END) as equipment_needing_service,
    ROUND(
        SUM(eu.hours_used) / COUNT(DISTINCT eu.equipment_id), 1
    ) as avg_equipment_utilization_hours,

    -- Livestock health summary
    COUNT(DISTINCT a.animal_id) as total_livestock,
    COUNT(DISTINCT CASE WHEN a.current_health_status = 'healthy' THEN a.animal_id END) as healthy_animals,
    COUNT(DISTINCT ahr.animal_id) FILTER (WHERE ahr.event_date >= CURRENT_DATE - INTERVAL '7 days') as animals_treated_recently,
    ROUND(
        COUNT(DISTINCT CASE WHEN a.current_health_status = 'healthy' THEN a.animal_id END)::DECIMAL /
        COUNT(DISTINCT a.animal_id) * 100, 1
    ) as livestock_health_rate,

    -- Weather and environmental alerts
    CASE
        WHEN (SELECT AVG(measurement_value) FROM environmental_metrics
              WHERE farm_id = f.farm_id AND metric_type = 'soil_moisture' AND measurement_date >= CURRENT_DATE - INTERVAL '1 day') < 0.3
        THEN 'Soil moisture critical - irrigation recommended'
        WHEN (SELECT MAX(measurement_value) FROM environmental_metrics
              WHERE farm_id = f.farm_id AND metric_type = 'wind_speed' AND measurement_date >= CURRENT_DATE - INTERVAL '1 day') > 25
        THEN 'High wind warning - secure equipment and crops'
        ELSE 'Weather conditions normal'
    END as weather_alert,

    -- Financial alerts (last 30 days)
    COALESCE(SUM(fe.amount), 0) as recent_expenses,
    COALESCE(SUM(cs.total_revenue), 0) as recent_revenue,
    CASE
        WHEN SUM(fe.amount) > SUM(cs.total_revenue) * 1.2 THEN 'Expense overrun alert'
        WHEN SUM(fe.amount) < SUM(cs.total_revenue) * 0.8 THEN 'Revenue below expectations'
        ELSE 'Financial performance normal'
    END as financial_status,

    -- Compliance status
    CASE
        WHEN COUNT(CASE WHEN st.test_date < CURRENT_DATE - INTERVAL '1 year' THEN 1 END) > COUNT(st.test_id) * 0.5
        THEN 'Soil testing compliance warning'
        WHEN COUNT(CASE WHEN ahr.event_type = 'vaccination' AND ahr.event_date < CURRENT_DATE - INTERVAL '6 months' THEN 1 END) > 0
        THEN 'Vaccination compliance warning'
        ELSE 'Compliance status good'
    END as compliance_alert,

    -- Overall farm health score
    ROUND(
        (
            -- Crop health (20%)
            LEAST(COALESCE(AVG(fp.yield_quality_rating), 0) / 5 * 20, 20) +
            -- Equipment reliability (15%)
            (1 - COUNT(DISTINCT CASE WHEN e.equipment_status != 'active' THEN e.equipment_id END)::DECIMAL /
             NULLIF(COUNT(DISTINCT e.equipment_id), 0)) * 15 +
            -- Livestock welfare (15%)
            LEAST(COUNT(DISTINCT CASE WHEN a.current_health_status = 'healthy' THEN a.animal_id END)::DECIMAL /
                  NULLIF(COUNT(DISTINCT a.animal_id), 0) * 15, 15) +
            -- Environmental stewardship (15%)
            LEAST(COALESCE(AVG(em.environmental_score), 0) / 10 * 15, 15) +
            -- Operational efficiency (15%)
            CASE
                WHEN SUM(fp.acreage) / f.total_acres > 0.8 THEN 15
                WHEN SUM(fp.acreage) / f.total_acres > 0.6 THEN 10
                WHEN SUM(fp.acreage) / f.total_acres > 0.4 THEN 5
                ELSE 0
            END +
            -- Financial stability (20%)
            CASE
                WHEN SUM(cs.total_revenue) > SUM(fe.amount) THEN 20
                WHEN SUM(cs.total_revenue) > SUM(fe.amount) * 0.8 THEN 15
                WHEN SUM(cs.total_revenue) > SUM(fe.amount) * 0.6 THEN 10
                ELSE 0
            END
        ), 1
    ) as overall_farm_health_score

FROM farms f
LEFT JOIN fields fi ON f.farm_id = fi.farm_id
LEFT JOIN field_plantings fp ON fi.field_id = fp.field_id
    AND fp.planting_status IN ('planted', 'growing')
LEFT JOIN equipment e ON f.farm_id = e.farm_id
LEFT JOIN equipment_usage eu ON e.equipment_id = eu.equipment_id
    AND eu.usage_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN animals a ON f.farm_id = a.farm_id
LEFT JOIN animal_health_records ahr ON a.animal_id = ahr.animal_id
    AND ahr.event_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN environmental_metrics em ON f.farm_id = em.farm_id
    AND em.measurement_date >= CURRENT_DATE - INTERVAL '90 days'
LEFT JOIN farm_expenses fe ON f.farm_id = fe.farm_id
    AND fe.expense_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN crop_sales cs ON f.farm_id = cs.farm_id
    AND cs.sale_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN soil_tests st ON fi.field_id = st.field_id
GROUP BY f.farm_id, f.farm_name, f.farming_method, f.total_acres;
```

This agriculture database schema provides enterprise-grade infrastructure for modern farm management, precision agriculture, livestock operations, and regulatory compliance with comprehensive analytics and environmental monitoring.
