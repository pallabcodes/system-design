-- Agriculture & Farming Database Schema (MySQL)
-- Comprehensive schema for modern agricultural operations
-- Adapted for MySQL with InnoDB engine, spatial features, and JSON support

-- ===========================================
-- FARM INFRASTRUCTURE
-- ===========================================

CREATE TABLE farms (
    farm_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    farm_name VARCHAR(255) NOT NULL,
    farm_description TEXT,

    -- Location and contact
    address_line_1 VARCHAR(255),
    address_line_2 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',

    -- Farm characteristics
    total_acres DECIMAL(10,2),
    farming_method ENUM('conventional', 'organic', 'regenerative', 'sustainable', 'mixed') DEFAULT 'conventional',
    farm_type ENUM('crop', 'livestock', 'mixed', 'specialty', 'research') DEFAULT 'mixed',

    -- Geospatial boundaries (MySQL spatial)
    farm_boundary POLYGON NULL COMMENT 'Farm boundary as polygon',

    -- Operational details
    year_established YEAR,
    primary_crops JSON DEFAULT ('[]') COMMENT 'Array of primary crops grown',
    certifications JSON DEFAULT ('[]') COMMENT 'Organic, sustainable, etc. certifications',

    -- Environmental factors
    climate_zone VARCHAR(50),
    soil_type VARCHAR(100),
    water_source VARCHAR(100),

    -- Management
    owner_name VARCHAR(255),
    manager_name VARCHAR(255),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,

    INDEX idx_farms_location (city, state_province),
    INDEX idx_farms_type (farm_type),
    INDEX idx_farms_active (is_active),
    SPATIAL INDEX idx_farms_boundary (farm_boundary)
) ENGINE = InnoDB;

CREATE TABLE fields (
    field_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    farm_id CHAR(36) NOT NULL,

    field_name VARCHAR(100) NOT NULL,
    field_number VARCHAR(20),
    field_description TEXT,

    -- Physical characteristics
    acreage DECIMAL(8,2) NOT NULL,
    field_shape POLYGON NULL COMMENT 'Field boundary as polygon',
    slope_percentage DECIMAL(5,2) DEFAULT 0,
    drainage_class ENUM('excellent', 'good', 'moderate', 'poor', 'very_poor') DEFAULT 'good',
    irrigation_type ENUM('none', 'flood', 'sprinkler', 'drip', 'center_pivot', 'subsurface') DEFAULT 'none',

    -- Soil characteristics
    soil_type VARCHAR(100),
    soil_ph DECIMAL(4,2),
    organic_matter_percentage DECIMAL(5,2),

    -- Environmental factors
    erosion_risk ENUM('none', 'low', 'moderate', 'high', 'severe') DEFAULT 'low',
    flood_risk ENUM('none', 'low', 'moderate', 'high', 'severe') DEFAULT 'low',

    -- Historical performance
    average_yield_per_acre DECIMAL(8,2),
    best_crop_types JSON DEFAULT ('[]'),
    rotation_history JSON DEFAULT ('[]'),

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,

    FOREIGN KEY (farm_id) REFERENCES farms(farm_id) ON DELETE CASCADE,

    INDEX idx_fields_farm (farm_id),
    INDEX idx_fields_active (is_active),
    INDEX idx_fields_erosion (erosion_risk),
    SPATIAL INDEX idx_fields_shape (field_shape)
) ENGINE = InnoDB;

CREATE TABLE soil_tests (
    test_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    field_id CHAR(36) NOT NULL,

    -- Test information
    test_date DATE NOT NULL,
    test_type ENUM('routine', 'problem_diagnosis', 'certification', 'baseline') DEFAULT 'routine',
    lab_name VARCHAR(255),
    sample_depth_inches INT DEFAULT 6,

    -- Soil chemistry
    ph_level DECIMAL(4,2),
    nitrogen_ppm DECIMAL(8,2),
    phosphorus_ppm DECIMAL(8,2),
    potassium_ppm DECIMAL(8,2),
    calcium_ppm DECIMAL(8,2),
    magnesium_ppm DECIMAL(8,2),
    sulfur_ppm DECIMAL(8,2),

    -- Soil physics
    organic_matter_percentage DECIMAL(5,2),
    cation_exchange_capacity DECIMAL(6,2),
    texture ENUM('sand', 'loamy_sand', 'sandy_loam', 'loam', 'silt_loam', 'silt', 'sandy_clay_loam', 'clay_loam', 'silty_clay_loam', 'sandy_clay', 'silty_clay', 'clay'),

    -- Micronutrients
    zinc_ppm DECIMAL(6,2),
    iron_ppm DECIMAL(6,2),
    manganese_ppm DECIMAL(6,2),
    copper_ppm DECIMAL(6,2),
    boron_ppm DECIMAL(6,2),

    -- Salt content
    salinity_dS_m DECIMAL(5,2),
    sodium_adsorption_ratio DECIMAL(5,2),

    -- Recommendations
    lime_recommendation_lbs_acre DECIMAL(8,2),
    fertilizer_recommendations JSON DEFAULT ('{}'),
    amendments_needed JSON DEFAULT ('[]'),

    -- Metadata
    tested_by VARCHAR(255),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (field_id) REFERENCES fields(field_id) ON DELETE CASCADE,

    INDEX idx_soil_tests_field (field_id),
    INDEX idx_soil_tests_date (test_date),
    INDEX idx_soil_tests_type (test_type),
    INDEX idx_soil_tests_ph (ph_level)
) ENGINE = InnoDB;

-- ===========================================
-- CROP MANAGEMENT
-- ===========================================

CREATE TABLE crops (
    crop_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    crop_name VARCHAR(255) NOT NULL,
    scientific_name VARCHAR(255),
    crop_family VARCHAR(100),

    -- Growing characteristics
    growth_habit ENUM('annual', 'biennial', 'perennial') DEFAULT 'annual',
    planting_season ENUM('spring', 'summer', 'fall', 'winter', 'year_round') DEFAULT 'spring',
    harvest_season ENUM('spring', 'summer', 'fall', 'winter') DEFAULT 'fall',

    -- Agronomic requirements
    optimal_ph_min DECIMAL(4,2),
    optimal_ph_max DECIMAL(4,2),
    nitrogen_requirement_lbs_acre DECIMAL(8,2),
    phosphorus_requirement_lbs_acre DECIMAL(8,2),
    potassium_requirement_lbs_acre DECIMAL(8,2),

    -- Performance metrics
    average_yield_per_acre DECIMAL(8,2),
    average_market_price_per_unit DECIMAL(8,2),
    production_cost_per_acre DECIMAL(8,2),
    days_to_maturity INT,

    -- Genetic characteristics
    gmo_status BOOLEAN DEFAULT FALSE,
    drought_tolerance ENUM('low', 'medium', 'high') DEFAULT 'medium',
    disease_resistance JSON DEFAULT ('[]'),

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_crops_family (crop_family),
    INDEX idx_crops_season (planting_season, harvest_season),
    INDEX idx_crops_gmo (gmo_status),
    FULLTEXT INDEX ft_crops_name (crop_name, scientific_name)
) ENGINE = InnoDB;

CREATE TABLE planting_plans (
    plan_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    farm_id CHAR(36) NOT NULL,

    plan_name VARCHAR(255) NOT NULL,
    plan_year YEAR NOT NULL,
    plan_description TEXT,

    -- Planning details
    total_acres_planned DECIMAL(10,2),
    budget_allocated DECIMAL(12,2),
    expected_revenue DECIMAL(12,2),

    -- Rotation strategy
    rotation_strategy JSON DEFAULT ('{}') COMMENT 'Crop rotation plan details',
    sustainability_goals JSON DEFAULT ('[]'),

    -- Status
    status ENUM('draft', 'approved', 'in_progress', 'completed', 'cancelled') DEFAULT 'draft',

    -- Metadata
    created_by VARCHAR(255),
    approved_by VARCHAR(255),
    approved_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (farm_id) REFERENCES farms(farm_id) ON DELETE CASCADE,

    INDEX idx_plans_farm (farm_id),
    INDEX idx_plans_year (plan_year),
    INDEX idx_plans_status (status)
) ENGINE = InnoDB;

CREATE TABLE field_plantings (
    planting_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    field_id CHAR(36) NOT NULL,
    crop_id CHAR(36) NOT NULL,

    -- Planting details
    planting_date DATE NOT NULL,
    acreage DECIMAL(8,2) NOT NULL,
    seed_variety VARCHAR(255),
    seeds_per_acre DECIMAL(10,2),

    -- Growth tracking
    planting_status ENUM('planned', 'planted', 'emerging', 'growing', 'flowering', 'maturing', 'harvested', 'failed') DEFAULT 'planned',
    emergence_date DATE NULL,
    maturity_date DATE NULL,
    harvest_date DATE NULL,

    -- Performance metrics
    yield_per_acre DECIMAL(8,2) NULL,
    yield_quality_rating DECIMAL(3,1) NULL CHECK (yield_quality_rating >= 0 AND yield_quality_rating <= 5),

    -- Agricultural inputs
    fertilizer_applied JSON DEFAULT ('[]'),
    pesticides_applied JSON DEFAULT ('[]'),
    irrigation_schedule JSON DEFAULT ('[]'),

    -- Environmental monitoring
    ndvi_readings JSON DEFAULT ('[]') COMMENT 'Normalized Difference Vegetation Index readings',
    growth_stage VARCHAR(100),
    pest_pressure_rating INT DEFAULT 0 CHECK (pest_pressure_rating >= 0 AND pest_pressure_rating <= 10),
    disease_incidence JSON DEFAULT ('[]'),

    -- Notes and observations
    notes TEXT,

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (field_id) REFERENCES fields(field_id) ON DELETE CASCADE,
    FOREIGN KEY (crop_id) REFERENCES crops(crop_id) ON DELETE CASCADE,

    INDEX idx_plantings_field (field_id),
    INDEX idx_plantings_crop (crop_id),
    INDEX idx_plantings_date (planting_date),
    INDEX idx_plantings_status (planting_status),
    INDEX idx_plantings_harvest (harvest_date)
) ENGINE = InnoDB;

-- ===========================================
-- LIVESTOCK MANAGEMENT
-- ===========================================

CREATE TABLE livestock_types (
    type_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    type_name VARCHAR(100) NOT NULL,
    species VARCHAR(50) NOT NULL,
    breed_category VARCHAR(50),

    -- Production characteristics
    production_type ENUM('meat', 'dairy', 'eggs', 'wool', 'dual_purpose', 'draft') DEFAULT 'meat',
    average_weight_lbs DECIMAL(8,2),
    average_lifespan_years DECIMAL(4,1),

    -- Care requirements
    feed_requirements_daily_lbs DECIMAL(6,2),
    water_requirements_daily_gallons DECIMAL(6,2),
    housing_requirements VARCHAR(255),

    -- Economic metrics
    average_market_price DECIMAL(8,2),
    production_cost_per_animal DECIMAL(8,2),

    -- Health considerations
    common_health_issues JSON DEFAULT ('[]'),
    vaccination_schedule JSON DEFAULT ('{}'),

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_livestock_types_species (species),
    INDEX idx_livestock_types_production (production_type)
) ENGINE = InnoDB;

CREATE TABLE animals (
    animal_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    farm_id CHAR(36) NOT NULL,
    type_id CHAR(36) NOT NULL,

    -- Identification
    animal_tag VARCHAR(50) UNIQUE NOT NULL,
    rfid_tag VARCHAR(100) UNIQUE,
    name VARCHAR(100),

    -- Demographics
    birth_date DATE,
    gender ENUM('male', 'female') NOT NULL,
    breed VARCHAR(100),

    -- Current status
    current_health_status ENUM('healthy', 'sick', 'injured', 'quarantined', 'deceased') DEFAULT 'healthy',
    current_location VARCHAR(255),

    -- Physical characteristics
    weight_lbs DECIMAL(8,2),
    height_inches DECIMAL(6,2),

    -- Genealogy
    sire_id CHAR(36) NULL COMMENT 'Father animal ID',
    dam_id CHAR(36) NULL COMMENT 'Mother animal ID',

    -- Economic tracking
    purchase_price DECIMAL(8,2),
    purchase_date DATE,
    disposal_date DATE NULL,
    disposal_reason VARCHAR(255),

    -- Production tracking
    production_records JSON DEFAULT ('{}') COMMENT 'Milk yield, egg production, wool weight, etc.',

    -- Location tracking (simulated GPS)
    geolocation POINT NULL,

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (farm_id) REFERENCES farms(farm_id) ON DELETE CASCADE,
    FOREIGN KEY (type_id) REFERENCES livestock_types(type_id) ON DELETE CASCADE,
    FOREIGN KEY (sire_id) REFERENCES animals(animal_id) ON DELETE SET NULL,
    FOREIGN KEY (dam_id) REFERENCES animals(animal_id) ON DELETE SET NULL,

    INDEX idx_animals_farm (farm_id),
    INDEX idx_animals_type (type_id),
    INDEX idx_animals_tag (animal_tag),
    INDEX idx_animals_health (current_health_status),
    INDEX idx_animals_gender (gender),
    INDEX idx_animals_birth (birth_date),
    SPATIAL INDEX idx_animals_location (geolocation)
) ENGINE = InnoDB;

CREATE TABLE animal_health_records (
    record_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    animal_id CHAR(36) NOT NULL,

    -- Event details
    event_date DATE NOT NULL,
    event_type ENUM('vaccination', 'treatment', 'checkup', 'surgery', 'birth', 'death', 'sale', 'purchase') NOT NULL,
    event_description TEXT,

    -- Health details
    diagnosis VARCHAR(255),
    treatment_given TEXT,
    medications JSON DEFAULT ('[]'),

    -- Veterinary details
    veterinarian_name VARCHAR(255),
    veterinarian_license VARCHAR(50),

    -- Cost tracking
    cost DECIMAL(8,2),

    -- Follow-up
    follow_up_date DATE NULL,
    follow_up_notes TEXT,

    -- Metadata
    recorded_by VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (animal_id) REFERENCES animals(animal_id) ON DELETE CASCADE,

    INDEX idx_health_animal (animal_id),
    INDEX idx_health_date (event_date),
    INDEX idx_health_type (event_type),
    INDEX idx_health_followup (follow_up_date)
) ENGINE = InnoDB;

-- ===========================================
-- EQUIPMENT MANAGEMENT
-- ===========================================

CREATE TABLE equipment (
    equipment_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    farm_id CHAR(36) NOT NULL,

    equipment_name VARCHAR(255) NOT NULL,
    equipment_type ENUM('tractor', 'combine', 'planter', 'sprayer', 'harvester', 'tiller', 'baler', 'truck', 'utility_vehicle', 'irrigation', 'other') NOT NULL,
    manufacturer VARCHAR(100),
    model VARCHAR(100),

    -- Specifications
    horsepower INT,
    fuel_type ENUM('diesel', 'gasoline', 'electric', 'propane') DEFAULT 'diesel',
    fuel_capacity_gallons DECIMAL(6,2),

    -- Operational details
    equipment_status ENUM('active', 'maintenance', 'repair', 'retired', 'sold') DEFAULT 'active',
    purchase_date DATE,
    purchase_price DECIMAL(10,2),

    -- Maintenance tracking
    service_interval_hours INT DEFAULT 200,
    last_service_date DATE,
    next_service_due DATE,
    total_hours_used DECIMAL(10,2) DEFAULT 0,

    -- Safety and compliance
    safety_certifications JSON DEFAULT ('[]'),
    insurance_policy_number VARCHAR(100),

    -- Configuration
    equipment_config JSON DEFAULT ('{}') COMMENT 'GPS settings, automation features, etc.',

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (farm_id) REFERENCES farms(farm_id) ON DELETE CASCADE,

    INDEX idx_equipment_farm (farm_id),
    INDEX idx_equipment_type (equipment_type),
    INDEX idx_equipment_status (equipment_status),
    INDEX idx_equipment_service (next_service_due)
) ENGINE = InnoDB;

CREATE TABLE equipment_usage (
    usage_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    equipment_id CHAR(36) NOT NULL,

    usage_date DATE NOT NULL,
    hours_used DECIMAL(6,2) NOT NULL,
    fuel_used_gallons DECIMAL(6,2),

    -- Operational details
    operator_name VARCHAR(255),
    field_id CHAR(36) NULL,
    operation_type ENUM('planting', 'harvesting', 'tilling', 'spraying', 'transporting', 'maintenance', 'other') NOT NULL,

    -- Performance metrics
    fuel_efficiency_actual DECIMAL(6,3) COMMENT 'Gallons per hour',
    work_rate_acres_hour DECIMAL(6,2),
    downtime_minutes INT DEFAULT 0,

    -- GPS and precision data
    gps_track LINESTRING NULL COMMENT 'Equipment path during operation',

    -- Notes
    notes TEXT,

    -- Metadata
    recorded_by VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (equipment_id) REFERENCES equipment(equipment_id) ON DELETE CASCADE,
    FOREIGN KEY (field_id) REFERENCES fields(field_id) ON DELETE SET NULL,

    INDEX idx_usage_equipment (equipment_id),
    INDEX idx_usage_date (usage_date),
    INDEX idx_usage_field (field_id),
    INDEX idx_usage_operation (operation_type),
    SPATIAL INDEX idx_usage_track (gps_track)
) ENGINE = InnoDB;

-- ===========================================
-- FINANCIAL MANAGEMENT
-- ===========================================

CREATE TABLE farm_expenses (
    expense_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    farm_id CHAR(36) NOT NULL,

    expense_date DATE NOT NULL,
    expense_category ENUM('seed', 'fertilizer', 'pesticides', 'equipment', 'fuel', 'labor', 'utilities', 'insurance', 'maintenance', 'feed', 'veterinary', 'marketing', 'other') NOT NULL,

    -- Expense details
    description VARCHAR(500) NOT NULL,
    vendor_name VARCHAR(255),
    amount DECIMAL(10,2) NOT NULL,

    -- Categorization
    subcategory VARCHAR(100),
    cost_center VARCHAR(100),  -- Field, equipment, department, etc.

    -- Tax and accounting
    tax_category VARCHAR(50),
    is_tax_deductible BOOLEAN DEFAULT TRUE,

    -- Related entities
    field_id CHAR(36) NULL,
    equipment_id CHAR(36) NULL,
    animal_id CHAR(36) NULL,

    -- Payment details
    payment_method ENUM('cash', 'check', 'credit_card', 'bank_transfer', 'account_payable') DEFAULT 'cash',
    payment_reference VARCHAR(100),

    -- Metadata
    recorded_by VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (farm_id) REFERENCES farms(farm_id) ON DELETE CASCADE,
    FOREIGN KEY (field_id) REFERENCES fields(field_id) ON DELETE SET NULL,
    FOREIGN KEY (equipment_id) REFERENCES equipment(equipment_id) ON DELETE SET NULL,
    FOREIGN KEY (animal_id) REFERENCES animals(animal_id) ON DELETE SET NULL,

    INDEX idx_expenses_farm (farm_id),
    INDEX idx_expenses_date (expense_date),
    INDEX idx_expenses_category (expense_category),
    INDEX idx_expenses_field (field_id),
    INDEX idx_expenses_equipment (equipment_id)
) ENGINE = InnoDB;

CREATE TABLE crop_sales (
    sale_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    farm_id CHAR(36) NOT NULL,

    sale_date DATE NOT NULL,
    crop_id CHAR(36) NOT NULL,

    -- Sale details
    quantity_sold DECIMAL(10,2) NOT NULL,
    unit_of_measure ENUM('bushels', 'tons', 'pounds', 'hundredweight', 'acres') DEFAULT 'bushels',
    unit_price DECIMAL(8,2) NOT NULL,
    total_revenue DECIMAL(10,2) NOT NULL,

    -- Buyer and market details
    buyer_name VARCHAR(255),
    buyer_type ENUM('cooperative', 'processor', 'retail', 'export', 'direct_to_consumer') DEFAULT 'cooperative',
    market_type ENUM('spot', 'contract', 'futures', 'direct_sale') DEFAULT 'spot',

    -- Quality and grading
    quality_grade VARCHAR(50),
    moisture_content_percentage DECIMAL(5,2),
    test_weight DECIMAL(6,2),

    -- Logistics
    delivery_date DATE,
    delivery_location VARCHAR(255),

    -- Metadata
    recorded_by VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (farm_id) REFERENCES farms(farm_id) ON DELETE CASCADE,
    FOREIGN KEY (crop_id) REFERENCES crops(crop_id) ON DELETE CASCADE,

    INDEX idx_sales_farm (farm_id),
    INDEX idx_sales_date (sale_date),
    INDEX idx_sales_crop (crop_id),
    INDEX idx_sales_buyer (buyer_type)
) ENGINE = InnoDB;

CREATE TABLE livestock_sales (
    sale_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    farm_id CHAR(36) NOT NULL,

    sale_date DATE NOT NULL,
    animal_id CHAR(36) NULL,  -- NULL for bulk sales

    -- Sale details
    quantity_sold DECIMAL(8,2) NOT NULL,
    unit_of_measure ENUM('head', 'pounds', 'hundredweight') DEFAULT 'head',
    unit_price DECIMAL(8,2) NOT NULL,
    total_revenue DECIMAL(10,2) NOT NULL,

    -- Sale specifics
    sale_type ENUM('individual', 'bulk', 'auction', 'direct') DEFAULT 'individual',
    buyer_name VARCHAR(255),
    destination VARCHAR(255),

    -- Quality metrics
    average_weight_lbs DECIMAL(8,2),
    quality_grade VARCHAR(50),

    -- Metadata
    recorded_by VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (farm_id) REFERENCES farms(farm_id) ON DELETE CASCADE,
    FOREIGN KEY (animal_id) REFERENCES animals(animal_id) ON DELETE SET NULL,

    INDEX idx_livestock_sales_farm (farm_id),
    INDEX idx_livestock_sales_date (sale_date),
    INDEX idx_livestock_sales_animal (animal_id),
    INDEX idx_livestock_sales_type (sale_type)
) ENGINE = InnoDB;

-- ===========================================
-- ENVIRONMENTAL MONITORING
-- ===========================================

CREATE TABLE environmental_metrics (
    metric_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    farm_id CHAR(36) NOT NULL,

    measurement_date DATE NOT NULL,
    metric_type ENUM('soil_moisture', 'soil_temperature', 'air_temperature', 'humidity', 'wind_speed', 'precipitation', 'solar_radiation', 'carbon_dioxide', 'soil_erosion', 'water_quality', 'air_quality') NOT NULL,

    -- Measurement details
    measurement_value DECIMAL(10,4) NOT NULL,
    unit_of_measure VARCHAR(20) NOT NULL,
    sensor_location VARCHAR(255),

    -- Environmental impact
    environmental_score DECIMAL(5,2) NULL COMMENT 'Environmental impact score 0-100',
    carbon_equivalent_tons DECIMAL(8,4) NULL,

    -- Field-specific (optional)
    field_id CHAR(36) NULL,

    -- Metadata
    sensor_id VARCHAR(100),
    data_quality ENUM('verified', 'estimated', 'interpolated') DEFAULT 'verified',
    notes TEXT,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (farm_id) REFERENCES farms(farm_id) ON DELETE CASCADE,
    FOREIGN KEY (field_id) REFERENCES fields(field_id) ON DELETE SET NULL,

    INDEX idx_metrics_farm (farm_id),
    INDEX idx_metrics_date (measurement_date),
    INDEX idx_metrics_type (metric_type),
    INDEX idx_metrics_field (field_id)
) ENGINE = InnoDB;

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Composite indexes for common queries
CREATE INDEX idx_fields_farm_acreage ON fields (farm_id, acreage);
CREATE INDEX idx_plantings_field_date ON field_plantings (field_id, planting_date);
CREATE INDEX idx_animals_farm_health ON animals (farm_id, current_health_status);
CREATE INDEX idx_health_records_animal_date ON animal_health_records (animal_id, event_date DESC);
CREATE INDEX idx_equipment_usage_equipment_date ON equipment_usage (equipment_id, usage_date DESC);
CREATE INDEX idx_expenses_farm_date_category ON farm_expenses (farm_id, expense_date DESC, expense_category);
CREATE INDEX idx_sales_farm_date ON crop_sales (farm_id, sale_date DESC);

-- ===========================================
-- STORED PROCEDURES FOR AGRICULTURAL ANALYTICS
-- =========================================--

DELIMITER ;;

-- Calculate field irrigation zones based on soil moisture
CREATE PROCEDURE calculate_irrigation_zones(IN field_uuid CHAR(36))
BEGIN
    DECLARE field_boundary POLYGON;
    DECLARE zone_num INT DEFAULT 1;

    -- Get field boundary
    SELECT field_shape INTO field_boundary
    FROM fields WHERE field_id = field_uuid;

    -- Create irrigation zones (simplified - would use actual moisture sensors)
    CREATE TEMPORARY TABLE temp_zones AS
    SELECT
        zone_num as zone_id,
        field_boundary as zone_geometry,
        ROUND(0.4 + RAND() * 0.4, 2) as soil_moisture_level,
        CASE
            WHEN 0.4 + RAND() * 0.4 < 0.5 THEN 'high'
            WHEN 0.4 + RAND() * 0.4 < 0.7 THEN 'medium'
            ELSE 'low'
        END as irrigation_priority,
        ROUND((0.4 + RAND() * 0.4) * 1000, 2) as water_requirement_gallons,
        60 as estimated_application_time_minutes;

    SELECT * FROM temp_zones;
    DROP TEMPORARY TABLE temp_zones;
END;;

-- Predict crop yield with machine learning-style analysis
CREATE FUNCTION predict_crop_yield(
    field_uuid CHAR(36),
    crop_uuid CHAR(36),
    prediction_days INT
) RETURNS JSON
DETERMINISTIC
BEGIN
    DECLARE historical_yields JSON DEFAULT ('[]');
    DECLARE soil_conditions JSON;
    DECLARE prediction_result JSON;

    -- Get historical yield data
    SELECT JSON_ARRAYAGG(fp.yield_per_acre)
    INTO historical_yields
    FROM field_plantings fp
    WHERE fp.field_id = field_uuid
      AND fp.crop_id = crop_uuid
      AND fp.harvest_date IS NOT NULL
    ORDER BY fp.harvest_date DESC
    LIMIT 5;

    -- Get recent soil test data
    SELECT JSON_OBJECT(
        'ph_level', COALESCE(st.ph_level, 6.5),
        'nitrogen_ppm', COALESCE(st.nitrogen_ppm, 25),
        'phosphorus_ppm', COALESCE(st.phosphorus_ppm, 15),
        'potassium_ppm', COALESCE(st.potassium_ppm, 150),
        'organic_matter', COALESCE(st.organic_matter_percentage, 2.5)
    )
    INTO soil_conditions
    FROM soil_tests st
    WHERE st.field_id = field_uuid
    ORDER BY st.test_date DESC
    LIMIT 1;

    -- Generate prediction (simplified ML-style calculation)
    SET prediction_result = JSON_OBJECT(
        'predicted_yield_per_acre', CASE
            WHEN JSON_LENGTH(historical_yields) > 0
            THEN (
                SELECT AVG(yield_val)
                FROM JSON_TABLE(historical_yields, '$[*]' COLUMNS (yield_val DECIMAL(8,2) PATH '$'))
            ) * 1.05  -- Conservative prediction
            ELSE 150.0  -- Default prediction
        END,
        'confidence_level', CASE
            WHEN JSON_LENGTH(historical_yields) > 3 THEN 'high'
            WHEN JSON_LENGTH(historical_yields) > 1 THEN 'medium'
            ELSE 'low'
        END,
        'factors', JSON_OBJECT(
            'historical_data_points', JSON_LENGTH(historical_yields),
            'soil_conditions', soil_conditions,
            'weather_risk', 'moderate',
            'market_conditions', 'stable'
        ),
        'recommendations', JSON_ARRAY(
            'Monitor soil moisture levels',
            'Consider additional nitrogen application',
            'Track weather forecasts for optimal harvest timing'
        )
    );

    RETURN prediction_result;
END;;

-- Monitor livestock health and generate alerts
CREATE PROCEDURE monitor_livestock_health(IN farm_uuid CHAR(36))
BEGIN
    SELECT
        a.animal_id,
        a.animal_tag,
        a.current_health_status,
        lt.type_name,

        -- Health risk calculation
        CASE
            WHEN COUNT(CASE WHEN ahr.event_type = 'treatment' THEN 1 END) > 2 THEN 'high'
            WHEN COUNT(CASE WHEN ahr.event_type = 'vaccination' THEN 1 END) = 0 THEN 'high'
            WHEN MAX(ahr.event_date) < DATE_SUB(CURDATE(), INTERVAL 90 DAY) THEN 'medium'
            ELSE 'low'
        END as risk_level,

        -- Health metrics
        COUNT(CASE WHEN ahr.event_type = 'treatment' THEN 1 END) as treatment_count,
        COUNT(CASE WHEN ahr.event_type = 'vaccination' THEN 1 END) as vaccination_count,
        MAX(ahr.event_date) as last_health_event,

        -- Recommendations
        CASE
            WHEN COUNT(CASE WHEN ahr.event_type = 'vaccination' THEN 1 END) = 0 THEN
                'Schedule comprehensive vaccination program'
            WHEN COUNT(CASE WHEN ahr.event_type = 'treatment' THEN 1 END) > 2 THEN
                'Consult veterinarian for chronic health issues'
            WHEN MAX(ahr.event_date) < DATE_SUB(CURDATE(), INTERVAL 90 DAY) THEN
                'Schedule routine health checkup'
            ELSE 'Continue regular monitoring'
        END as recommendation,

        CASE
            WHEN COUNT(CASE WHEN ahr.event_type = 'treatment' THEN 1 END) > 2 THEN TRUE
            ELSE FALSE
        END as quarantine_recommended

    FROM animals a
    JOIN livestock_types lt ON a.type_id = lt.type_id
    LEFT JOIN animal_health_records ahr ON a.animal_id = ahr.animal_id
        AND ahr.event_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
    WHERE a.farm_id = farm_uuid
      AND a.disposal_date IS NULL
    GROUP BY a.animal_id, a.animal_tag, a.current_health_status, lt.type_name
    ORDER BY
        CASE
            WHEN COUNT(CASE WHEN ahr.event_type = 'treatment' THEN 1 END) > 2 THEN 1
            WHEN COUNT(CASE WHEN ahr.event_type = 'vaccination' THEN 1 END) = 0 THEN 2
            WHEN MAX(ahr.event_date) < DATE_SUB(CURDATE(), INTERVAL 90 DAY) THEN 3
            ELSE 4
        END,
        a.animal_tag;
END;;

-- Predict equipment maintenance needs
CREATE FUNCTION predict_equipment_maintenance(equipment_uuid CHAR(36))
RETURNS JSON
DETERMINISTIC
BEGIN
    DECLARE usage_stats JSON;
    DECLARE maintenance_info JSON;
    DECLARE prediction JSON;

    -- Get usage statistics
    SELECT JSON_OBJECT(
        'total_hours', COALESCE(SUM(eu.hours_used), 0),
        'usage_sessions', COUNT(eu.usage_id),
        'avg_hours_per_session', COALESCE(AVG(eu.hours_used), 0),
        'last_used', MAX(eu.usage_date),
        'avg_fuel_efficiency', COALESCE(AVG(eu.fuel_efficiency_actual), 0)
    )
    INTO usage_stats
    FROM equipment_usage eu
    WHERE eu.equipment_id = equipment_uuid
      AND eu.usage_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY);

    -- Get maintenance info
    SELECT JSON_OBJECT(
        'last_service', e.last_service_date,
        'next_service_due', e.next_service_due,
        'service_interval_hours', e.service_interval_hours,
        'total_hours_used', e.total_hours_used,
        'purchase_date', e.purchase_date,
        'equipment_age_years', TIMESTAMPDIFF(YEAR, e.purchase_date, CURDATE())
    )
    INTO maintenance_info
    FROM equipment e
    WHERE e.equipment_id = equipment_uuid;

    -- Generate prediction
    SET prediction = JSON_OBJECT(
        'equipment_name', (SELECT equipment_name FROM equipment WHERE equipment_id = equipment_uuid),
        'maintenance_prediction', JSON_OBJECT(
            'next_service_due', JSON_EXTRACT(maintenance_info, '$.next_service_due'),
            'predicted_failure_date', CASE
                WHEN JSON_EXTRACT(usage_stats, '$.total_hours') > JSON_EXTRACT(maintenance_info, '$.service_interval_hours') * 0.9
                THEN DATE_ADD(CURDATE(), INTERVAL 7 DAY)
                WHEN JSON_EXTRACT(maintenance_info, '$.equipment_age_years') > 8 THEN DATE_ADD(CURDATE(), INTERVAL 14 DAY)
                ELSE DATE_ADD(CURDATE(), INTERVAL 30 DAY)
            END,
            'failure_probability', CASE
                WHEN JSON_EXTRACT(usage_stats, '$.total_hours') > JSON_EXTRACT(maintenance_info, '$.service_interval_hours') * 0.9 THEN 0.85
                WHEN JSON_EXTRACT(maintenance_info, '$.equipment_age_years') > 8 THEN 0.70
                ELSE 0.25
            END
        ),
        'recommendations', JSON_ARRAY(
            CASE
                WHEN JSON_EXTRACT(usage_stats, '$.total_hours') > JSON_EXTRACT(maintenance_info, '$.service_interval_hours') * 0.9
                THEN 'Schedule immediate maintenance - usage interval reached'
                WHEN JSON_EXTRACT(maintenance_info, '$.equipment_age_years') > 8
                THEN 'Age-related maintenance recommended'
                ELSE 'Continue regular monitoring'
            END,
            'Inspect critical components during service',
            'Consider performance upgrades for aging equipment'
        ),
        'usage_stats', usage_stats,
        'maintenance_info', maintenance_info
    );

    RETURN prediction;
END;;

DELIMITER ;

-- ===========================================
-- PARTITIONING FOR TIME-SERIES DATA
-- =========================================--

-- Partition field plantings by year
ALTER TABLE field_plantings
PARTITION BY RANGE (YEAR(planting_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Partition equipment usage by month
ALTER TABLE equipment_usage
PARTITION BY RANGE (YEAR(usage_date) * 100 + MONTH(usage_date)) (
    PARTITION p2024_01 VALUES LESS THAN (202401),
    PARTITION p2024_02 VALUES LESS THAN (202402),
    PARTITION p2024_03 VALUES LESS THAN (202403),
    PARTITION p2024_04 VALUES LESS THAN (202404),
    PARTITION p2024_05 VALUES LESS THAN (202405),
    PARTITION p2024_06 VALUES LESS THAN (202406),
    PARTITION p2024_07 VALUES LESS THAN (202407),
    PARTITION p2024_08 VALUES LESS THAN (202408),
    PARTITION p2024_09 VALUES LESS THAN (202409),
    PARTITION p2024_10 VALUES LESS THAN (202410),
    PARTITION p2024_11 VALUES LESS THAN (202411),
    PARTITION p2024_12 VALUES LESS THAN (202412),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Partition environmental metrics by quarter
ALTER TABLE environmental_metrics
PARTITION BY RANGE (YEAR(measurement_date) * 4 + QUARTER(measurement_date)) (
    PARTITION q2024_1 VALUES LESS THAN (20241),
    PARTITION q2024_2 VALUES LESS THAN (20242),
    PARTITION q2024_3 VALUES LESS THAN (20243),
    PARTITION q2024_4 VALUES LESS THAN (20244),
    PARTITION q_future VALUES LESS THAN MAXVALUE
);

-- ===========================================
-- INITIAL SAMPLE DATA
-- =========================================--

INSERT INTO farms (farm_id, farm_name, total_acres, farming_method, farm_type, owner_name, contact_email) VALUES
(UUID(), 'Green Valley Farm', 250.5, 'organic', 'mixed', 'John Anderson', 'john@greenvalley.com');

INSERT INTO crops (crop_name, scientific_name, growth_habit, average_yield_per_acre, average_market_price_per_unit) VALUES
('Corn', 'Zea mays', 'annual', 180.5, 4.25),
('Soybeans', 'Glycine max', 'annual', 65.2, 12.80),
('Winter Wheat', 'Triticum aestivum', 'annual', 75.8, 6.45);

INSERT INTO livestock_types (type_name, species, production_type, average_weight_lbs, average_market_price) VALUES
('Holstein Cow', 'cattle', 'dairy', 1400.0, 1800.00),
('Angus Beef', 'cattle', 'meat', 1200.0, 2200.00);

/*
USAGE EXAMPLES:

-- Calculate irrigation zones for a field
CALL calculate_irrigation_zones('field-uuid-here');

-- Predict crop yield
SELECT predict_crop_yield('field-uuid', 'crop-uuid', 90);

-- Monitor livestock health
CALL monitor_livestock_health('farm-uuid-here');

-- Predict equipment maintenance
SELECT predict_equipment_maintenance('equipment-uuid');

This comprehensive agricultural database schema provides enterprise-grade infrastructure for:
- Farm management with geospatial field mapping
- Crop planning with yield prediction and rotation tracking
- Livestock health monitoring and breeding programs
- Equipment maintenance optimization with predictive analytics
- Financial management with expense/revenue tracking
- Environmental monitoring and compliance reporting
- Time-series data partitioning for performance
- Advanced analytics and reporting capabilities

Key features adapted for MySQL:
- UUID primary keys with UUID() function
- JSON data types for flexible metadata storage
- MySQL spatial data types (POLYGON, POINT, LINESTRING)
- InnoDB engine with full-text and spatial indexes
- Partitioning for time-series data management
- Stored procedures and functions for complex agricultural analytics

The schema handles precision agriculture, sustainable farming practices, regulatory compliance, and provides comprehensive analytics for modern farm operations.
*/
