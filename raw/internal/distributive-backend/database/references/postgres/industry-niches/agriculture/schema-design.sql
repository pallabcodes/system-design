-- Agriculture & Farming Database Schema
-- Comprehensive schema for farm management, crop planning, livestock tracking, and agricultural operations

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "postgis"; -- For farm mapping and GPS tracking

-- ===========================================
-- FARM AND LAND MANAGEMENT
-- ===========================================

CREATE TABLE farms (
    farm_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_name VARCHAR(255) NOT NULL,
    farm_code VARCHAR(20) UNIQUE NOT NULL,

    -- Farm Details
    farm_type VARCHAR(50) CHECK (farm_type IN (
        'crop_farm', 'livestock_farm', 'mixed_farm', 'organic_farm',
        'dairy_farm', 'poultry_farm', 'specialty_crops', 'aquaculture'
    )),
    total_acres DECIMAL(10,2),
    owned_acres DECIMAL(10,2),
    leased_acres DECIMAL(10,2),

    -- Location and Geography
    address JSONB,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    farm_boundary GEOGRAPHY(POLYGON, 4326), -- Geographic boundary of the farm

    -- Climate and Soil
    climate_zone VARCHAR(50),
    soil_types JSONB DEFAULT '[]', -- Array of soil classifications
    average_annual_rainfall DECIMAL(6,2), -- Inches per year
    frost_free_days INTEGER,

    -- Operational Details
    farming_method VARCHAR(30) CHECK (farming_method IN (
        'conventional', 'organic', 'regenerative', 'precision', 'hydroponic', 'aquaponic'
    )),
    irrigation_system VARCHAR(30) CHECK (irrigation_system IN (
        'none', 'flood', 'sprinkler', 'drip', 'pivot', 'subsurface'
    )),
    energy_sources JSONB DEFAULT '[]', -- Solar, wind, diesel, etc.

    -- Certifications and Compliance
    certifications JSONB DEFAULT '[]', -- Organic, GAP, HACCP, etc.
    regulatory_compliance JSONB DEFAULT '{}', -- EPA, USDA, state regulations

    -- Financial Information
    annual_budget DECIMAL(12,2),
    insurance_coverage JSONB DEFAULT '{}',

    -- Management
    primary_owner VARCHAR(255),
    farm_manager VARCHAR(255),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE fields (
    field_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),

    -- Field Identification
    field_name VARCHAR(100) NOT NULL,
    field_code VARCHAR(20) UNIQUE NOT NULL,

    -- Physical Characteristics
    acreage DECIMAL(8,2) NOT NULL,
    field_shape GEOGRAPHY(POLYGON, 4326), -- Precise field boundary
    soil_type VARCHAR(50),
    soil_ph DECIMAL(3,1),
    drainage_class VARCHAR(20) CHECK (drainage_class IN ('excellent', 'good', 'fair', 'poor', 'very_poor')),

    -- Current Status
    current_crop VARCHAR(100),
    planting_date DATE,
    expected_harvest_date DATE,

    -- Historical Performance
    average_yield_per_acre DECIMAL(8,2), -- Bushels/tons per acre
    yield_variability DECIMAL(5,2), -- Coefficient of variation
    last_soil_test_date DATE,

    -- Equipment Access
    equipment_accessible BOOLEAN DEFAULT TRUE,
    access_road_condition VARCHAR(20) CHECK (access_road_condition IN ('excellent', 'good', 'fair', 'poor')),

    -- Environmental Factors
    slope_percentage DECIMAL(4,1),
    erosion_risk VARCHAR(20) CHECK (erosion_risk IN ('low', 'moderate', 'high', 'severe')),
    water_source_distance DECIMAL(6,1), -- Meters to nearest water source

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE soil_tests (
    test_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    field_id UUID NOT NULL REFERENCES fields(field_id),

    -- Test Details
    test_date DATE DEFAULT CURRENT_DATE,
    test_type VARCHAR(30) CHECK (test_type IN (
        'comprehensive', 'ph_only', 'nutrient_panel', 'organic_matter', 'salinity', 'micronutrients'
    )),
    lab_name VARCHAR(100),

    -- Soil Chemistry
    ph_level DECIMAL(3,1),
    organic_matter_percentage DECIMAL(4,1),
    cation_exchange_capacity DECIMAL(6,2),

    -- Primary Nutrients (PPM)
    nitrogen_ppm DECIMAL(6,2),
    phosphorus_ppm DECIMAL(6,2),
    potassium_ppm DECIMAL(6,2),

    -- Secondary Nutrients
    calcium_ppm DECIMAL(6,2),
    magnesium_ppm DECIMAL(6,2),
    sulfur_ppm DECIMAL(6,2),

    -- Micronutrients
    zinc_ppm DECIMAL(5,2),
    iron_ppm DECIMAL(5,2),
    manganese_ppm DECIMAL(5,2),
    copper_ppm DECIMAL(5,2),
    boron_ppm DECIMAL(5,2),

    -- Soil Physical Properties
    texture VARCHAR(30), -- Sandy, loam, clay, etc.
    bulk_density DECIMAL(4,2), -- g/cm³
    salinity_ppm DECIMAL(6,2),

    -- Recommendations
    fertilizer_recommendations JSONB DEFAULT '[]',
    amendments_needed JSONB DEFAULT '[]',
    next_test_due DATE,

    -- Cost and Quality
    test_cost DECIMAL(6,2),
    lab_accuracy_rating INTEGER CHECK (lab_accuracy_rating BETWEEN 1 AND 5),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- CROP AND PLANTING MANAGEMENT
-- ===========================================

CREATE TABLE crops (
    crop_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    crop_name VARCHAR(100) NOT NULL,
    crop_code VARCHAR(20) UNIQUE NOT NULL,

    -- Botanical Classification
    scientific_name VARCHAR(150),
    crop_family VARCHAR(50),
    crop_type VARCHAR(30) CHECK (crop_type IN (
        'grain', 'vegetable', 'fruit', 'nut', 'fiber', 'oilseed',
        'forage', 'cover_crop', 'industrial', 'ornamental'
    )),

    -- Growing Requirements
    growing_season VARCHAR(20) CHECK (growing_season IN ('spring', 'summer', 'fall', 'winter', 'year_round')),
    days_to_maturity INTEGER,
    optimal_temperature_range VARCHAR(20), -- e.g., "60-80°F"
    water_requirement VARCHAR(20) CHECK (water_requirement IN ('low', 'medium', 'high', 'very_high')),

    -- Planting and Harvesting
    planting_depth_inches DECIMAL(4,1),
    row_spacing_inches DECIMAL(5,1),
    seed_spacing_inches DECIMAL(4,1),
    yield_units VARCHAR(20), -- bushels, tons, pounds, etc.

    -- Economic Information
    average_market_price_per_unit DECIMAL(6,2),
    production_cost_per_acre DECIMAL(6,2),
    profit_margin_percentage DECIMAL(5,2),

    -- Pest and Disease Resistance
    pest_resistance JSONB DEFAULT '[]',
    disease_resistance JSONB DEFAULT '[]',
    drought_tolerance VARCHAR(10) CHECK (drought_tolerance IN ('poor', 'fair', 'good', 'excellent')),

    -- Genetic Information
    variety_name VARCHAR(100),
    gmo_status BOOLEAN DEFAULT FALSE,
    organic_certified BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE planting_plans (
    plan_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),

    -- Plan Details
    plan_name VARCHAR(255) NOT NULL,
    plan_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
    plan_type VARCHAR(30) CHECK (plan_type IN ('annual', 'crop_rotation', 'cover_crop', 'fallow')),

    -- Planning Information
    total_acres_planned DECIMAL(10,2),
    estimated_total_cost DECIMAL(12,2),
    estimated_total_revenue DECIMAL(12,2),
    expected_profit DECIMAL(12,2) GENERATED ALWAYS AS (estimated_total_revenue - estimated_total_cost) STORED,

    -- Crop Rotation Strategy
    rotation_strategy TEXT,
    previous_crops JSONB DEFAULT '[]', -- Crops grown in previous years
    next_crops_planned JSONB DEFAULT '[]', -- Crops planned for next years

    -- Environmental Goals
    soil_health_targets JSONB DEFAULT '{}',
    water_conservation_goals JSONB DEFAULT '{}',
    biodiversity_targets JSONB DEFAULT '{}',

    -- Status and Approval
    plan_status VARCHAR(20) DEFAULT 'draft' CHECK (plan_status IN ('draft', 'approved', 'implemented', 'completed', 'cancelled')),
    approved_by VARCHAR(100),
    approval_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE field_plantings (
    planting_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    field_id UUID NOT NULL REFERENCES fields(field_id),
    crop_id UUID NOT NULL REFERENCES crops(crop_id),
    plan_id UUID REFERENCES planting_plans(plan_id),

    -- Planting Details
    planting_date DATE NOT NULL,
    expected_harvest_date DATE,
    actual_harvest_date DATE,

    -- Seed and Variety Information
    seed_variety VARCHAR(100),
    seed_source VARCHAR(100),
    seed_lot_number VARCHAR(50),
    seeds_per_acre INTEGER,
    seed_cost_per_acre DECIMAL(6,2),

    -- Fertilizer and Amendments
    fertilizer_applied JSONB DEFAULT '[]', -- Array of fertilizer applications
    soil_amendments JSONB DEFAULT '[]',

    -- Irrigation and Water Management
    irrigation_schedule JSONB DEFAULT '{}',
    water_applied_gallons DECIMAL(10,2),

    -- Pest and Disease Management
    pest_control_measures JSONB DEFAULT '[]',
    disease_treatments JSONB DEFAULT '[]',

    -- Growth Monitoring
    growth_stages JSONB DEFAULT '[]', -- Phenological stages with dates
    ndvi_readings JSONB DEFAULT '[]', -- Normalized Difference Vegetation Index

    -- Harvest Information
    yield_per_acre DECIMAL(8,2),
    yield_quality_rating INTEGER CHECK (yield_quality_rating BETWEEN 1 AND 5),
    harvest_costs DECIMAL(8,2),

    -- Status Tracking
    planting_status VARCHAR(20) DEFAULT 'planned' CHECK (planting_status IN (
        'planned', 'planted', 'growing', 'harvested', 'failed'
    )),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (planting_date <= expected_harvest_date),
    CHECK (expected_harvest_date <= actual_harvest_date OR actual_harvest_date IS NULL)
);

-- ===========================================
-- LIVESTOCK AND ANIMAL MANAGEMENT
-- ===========================================

CREATE TABLE livestock_types (
    type_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type_name VARCHAR(100) NOT NULL,
    type_code VARCHAR(20) UNIQUE NOT NULL,

    -- Classification
    species VARCHAR(50), -- Cattle, swine, poultry, sheep, etc.
    breed_category VARCHAR(50),
    production_type VARCHAR(30) CHECK (production_type IN (
        'meat', 'dairy', 'eggs', 'wool', 'labor', 'breeding', 'mixed'
    )),

    -- Physiological Requirements
    average_weight_lbs DECIMAL(6,2),
    average_lifespan_years DECIMAL(4,1),
    gestation_period_days INTEGER,
    weaning_age_days INTEGER,

    -- Production Metrics
    average_daily_gain_lbs DECIMAL(4,2),
    feed_conversion_ratio DECIMAL(4,2),
    average_production_yield DECIMAL(8,2), -- Milk, eggs, wool, etc.

    -- Economic Information
    market_price_per_unit DECIMAL(6,2),
    production_cost_per_unit DECIMAL(6,2),
    profit_margin_per_unit DECIMAL(6,2),

    -- Health and Welfare Standards
    vaccination_schedule JSONB DEFAULT '[]',
    nutritional_requirements JSONB DEFAULT '{}',
    welfare_standards JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE animals (
    animal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),
    type_id UUID NOT NULL REFERENCES livestock_types(type_id),

    -- Identification
    animal_tag VARCHAR(50) UNIQUE NOT NULL,
    rfid_tag VARCHAR(50),
    name VARCHAR(100),

    -- Biological Information
    birth_date DATE,
    breed VARCHAR(50),
    gender VARCHAR(10) CHECK (gender IN ('male', 'female')),
    color_markings TEXT,

    -- Pedigree and Genetics
    sire_id UUID REFERENCES animals(animal_id),
    dam_id UUID REFERENCES animals(animal_id),
    genetic_profile JSONB DEFAULT '{}',

    -- Health and Medical
    current_health_status VARCHAR(20) DEFAULT 'healthy' CHECK (current_health_status IN (
        'healthy', 'sick', 'injured', 'quarantined', 'deceased'
    )),
    vaccination_history JSONB DEFAULT '[]',
    medical_history JSONB DEFAULT '[]',
    current_medications JSONB DEFAULT '[]',

    -- Production Tracking
    production_records JSONB DEFAULT '[]', -- Milk, eggs, wool production history
    breeding_history JSONB DEFAULT '[]',

    -- Location and Movement
    current_location VARCHAR(100), -- Barn, pasture, field name
    gps_coordinates GEOGRAPHY(POINT, 4326),
    movement_history JSONB DEFAULT '[]',

    -- Economic Information
    acquisition_cost DECIMAL(8,2),
    current_value DECIMAL(8,2),
    cumulative_production_value DECIMAL(10,2),

    -- Lifecycle Events
    weaning_date DATE,
    first_breeding_date DATE,
    last_calving_date DATE,
    retirement_date DATE,
    disposal_date DATE,
    disposal_reason VARCHAR(100),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE animal_health_records (
    record_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    animal_id UUID NOT NULL REFERENCES animals(animal_id),

    -- Health Event Details
    event_date DATE DEFAULT CURRENT_DATE,
    event_type VARCHAR(30) CHECK (event_type IN (
        'vaccination', 'treatment', 'illness', 'injury', 'checkup',
        'pregnancy_check', 'birth', 'weaning', 'death'
    )),

    -- Medical Information
    condition_diagnosis VARCHAR(255),
    treatment_administered TEXT,
    medication_dosage VARCHAR(100),
    medication_cost DECIMAL(6,2),

    -- Veterinary Details
    veterinarian_name VARCHAR(100),
    veterinarian_license VARCHAR(50),
    clinic_name VARCHAR(100),

    -- Follow-up and Monitoring
    follow_up_date DATE,
    recovery_status VARCHAR(20) CHECK (recovery_status IN ('recovered', 'improving', 'chronic', 'terminal')),
    quarantine_required BOOLEAN DEFAULT FALSE,
    quarantine_end_date DATE,

    -- Preventative Measures
    vaccination_type VARCHAR(100),
    vaccination_batch_number VARCHAR(50),
    next_vaccination_due DATE,

    -- Notes and Observations
    symptoms TEXT,
    treatment_notes TEXT,
    behavioral_observations TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- EQUIPMENT AND MACHINERY MANAGEMENT
-- ===========================================

CREATE TABLE equipment (
    equipment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),

    -- Equipment Details
    equipment_name VARCHAR(100) NOT NULL,
    equipment_code VARCHAR(20) UNIQUE NOT NULL,
    equipment_type VARCHAR(30) CHECK (equipment_type IN (
        'tractor', 'combine', 'planter', 'sprayer', 'harvester',
        'tillage', 'irrigation', 'feeding', 'milking', 'other'
    )),

    -- Technical Specifications
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    serial_number VARCHAR(50),
    year_manufactured INTEGER,

    -- Operational Details
    horsepower INTEGER,
    fuel_type VARCHAR(20) CHECK (fuel_type IN ('diesel', 'gasoline', 'electric', 'hybrid')),
    fuel_capacity_gallons DECIMAL(6,2),

    -- Maintenance and Service
    purchase_date DATE,
    purchase_price DECIMAL(10,2),
    warranty_expiration DATE,
    last_service_date DATE,
    next_service_due DATE,
    service_interval_hours INTEGER,

    -- Usage Tracking
    total_hours_used DECIMAL(8,2) DEFAULT 0,
    fuel_efficiency_mpg DECIMAL(5,2),
    maintenance_cost_yearly DECIMAL(8,2),

    -- Status and Availability
    equipment_status VARCHAR(20) DEFAULT 'active' CHECK (equipment_status IN (
        'active', 'maintenance', 'repair', 'retired', 'sold'
    )),
    current_location VARCHAR(100),
    assigned_operator VARCHAR(100),

    -- Safety and Compliance
    safety_certifications JSONB DEFAULT '[]',
    emissions_compliance VARCHAR(20) CHECK (emissions_compliance IN ('compliant', 'non_compliant', 'exempt')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE equipment_usage (
    usage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    equipment_id UUID NOT NULL REFERENCES equipment(equipment_id),
    field_id UUID REFERENCES fields(field_id),

    -- Usage Details
    usage_date DATE DEFAULT CURRENT_DATE,
    start_time TIME,
    end_time TIME,
    hours_used DECIMAL(5,2),

    -- Activity Information
    activity_type VARCHAR(50) CHECK (activity_type IN (
        'planting', 'cultivating', 'spraying', 'harvesting',
        'tillage', 'irrigation', 'feeding', 'milking', 'transport'
    )),
    crop_id UUID REFERENCES crops(crop_id),
    acres_covered DECIMAL(8,2),

    -- Fuel and Operating Costs
    fuel_used_gallons DECIMAL(6,2),
    fuel_cost DECIMAL(6,2),
    operating_cost DECIMAL(6,2),

    -- Performance Metrics
    work_rate_acres_per_hour DECIMAL(6,2),
    fuel_efficiency_actual DECIMAL(5,2),
    equipment_downtime_minutes INTEGER,

    -- Operator and Conditions
    operator_name VARCHAR(100),
    weather_conditions VARCHAR(100),
    soil_conditions VARCHAR(50),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- FINANCIAL AND ECONOMIC MANAGEMENT
-- ===========================================

CREATE TABLE farm_expenses (
    expense_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),

    -- Expense Details
    expense_date DATE DEFAULT CURRENT_DATE,
    expense_category VARCHAR(50) CHECK (expense_category IN (
        'seed', 'fertilizer', 'pesticides', 'equipment', 'fuel',
        'labor', 'utilities', 'insurance', 'maintenance', 'feed',
        'veterinary', 'marketing', 'other'
    )),
    expense_subcategory VARCHAR(100),
    vendor_name VARCHAR(100),

    -- Financial Information
    amount DECIMAL(10,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    payment_method VARCHAR(30) CHECK (payment_method IN ('cash', 'check', 'credit_card', 'transfer', 'account')),

    -- Tax and Accounting
    tax_category VARCHAR(50),
    deductible BOOLEAN DEFAULT TRUE,
    receipt_number VARCHAR(50),

    -- Related Items
    field_id UUID REFERENCES fields(field_id),
    equipment_id UUID REFERENCES equipment(equipment_id),
    animal_id UUID REFERENCES animals(animal_id),

    -- Approval and Budgeting
    budget_category VARCHAR(50),
    approved_by VARCHAR(100),
    expense_status VARCHAR(20) DEFAULT 'approved' CHECK (expense_status IN ('pending', 'approved', 'rejected', 'reimbursed')),

    -- Supporting Documentation
    receipt_url VARCHAR(500),
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (amount > 0)
);

CREATE TABLE crop_sales (
    sale_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),
    crop_id UUID NOT NULL REFERENCES crops(crop_id),

    -- Sale Details
    sale_date DATE DEFAULT CURRENT_DATE,
    buyer_name VARCHAR(100),
    buyer_type VARCHAR(30) CHECK (buyer_type IN ('elevator', 'cooperative', 'processor', 'retail', 'export')),

    -- Product Information
    quantity_sold DECIMAL(10,2), -- In appropriate units
    unit_of_measure VARCHAR(20), -- bushels, tons, pounds, etc.
    quality_grade VARCHAR(20),
    moisture_content_percentage DECIMAL(4,1),

    -- Pricing
    price_per_unit DECIMAL(6,2),
    total_revenue DECIMAL(10,2) GENERATED ALWAYS AS (quantity_sold * price_per_unit) STORED,

    -- Marketing and Contracts
    contract_number VARCHAR(50),
    delivery_terms VARCHAR(100),
    payment_terms VARCHAR(50),

    -- Logistics
    delivery_date DATE,
    delivery_location VARCHAR(255),
    transportation_cost DECIMAL(6,2),
    storage_cost DECIMAL(6,2),

    -- Quality and Testing
    quality_test_results JSONB DEFAULT '{}',
    contaminant_levels JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity_sold > 0),
    CHECK (price_per_unit > 0)
);

CREATE TABLE livestock_sales (
    sale_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),

    -- Sale Details
    sale_date DATE DEFAULT CURRENT_DATE,
    buyer_name VARCHAR(100),
    sale_type VARCHAR(30) CHECK (sale_type IN ('auction', 'direct', 'contract', 'export')),

    -- Animal Information
    animal_ids UUID[], -- Array of sold animal IDs
    total_animals_sold INTEGER,

    -- Sale Metrics
    total_weight_lbs DECIMAL(8,2),
    average_weight_lbs DECIMAL(6,2),
    average_price_per_lb DECIMAL(5,2),
    total_revenue DECIMAL(10,2),

    -- Quality and Grading
    average_grade VARCHAR(20),
    health_certifications JSONB DEFAULT '[]',
    vaccination_status VARCHAR(20),

    -- Marketing Information
    marketing_channel VARCHAR(50),
    advertised_weight_range VARCHAR(30),
    sale_location VARCHAR(100),

    -- Post-Sale Analysis
    market_average_price DECIMAL(5,2),
    price_premium_percentage DECIMAL(5,2),
    buyer_feedback TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (total_animals_sold > 0),
    CHECK (total_revenue > 0)
);

-- ===========================================
-- ENVIRONMENTAL AND SUSTAINABILITY TRACKING
-- =========================================--

CREATE TABLE environmental_metrics (
    metric_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),

    -- Measurement Details
    measurement_date DATE DEFAULT CURRENT_DATE,
    metric_type VARCHAR(50) CHECK (metric_type IN (
        'soil_erosion', 'water_usage', 'energy_consumption', 'carbon_footprint',
        'biodiversity_index', 'soil_organic_matter', 'water_quality', 'air_quality'
    )),

    -- Measurement Data
    measurement_value DECIMAL(10,2),
    unit_of_measure VARCHAR(20),
    measurement_method VARCHAR(100),

    -- Location Context
    field_id UUID REFERENCES fields(field_id),
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),

    -- Benchmarking
    industry_average DECIMAL(10,2),
    baseline_value DECIMAL(10,2),
    target_value DECIMAL(10,2),

    -- Environmental Impact
    carbon_equivalent_tons DECIMAL(8,2),
    environmental_score DECIMAL(5,2), -- 1-10 scale

    -- Compliance and Reporting
    regulatory_standard VARCHAR(100),
    compliance_status VARCHAR(20) CHECK (compliance_status IN ('compliant', 'non_compliant', 'exempt', 'pending')),
    reporting_required BOOLEAN DEFAULT FALSE,

    -- Notes and Observations
    measurement_notes TEXT,
    weather_conditions VARCHAR(100),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sustainability_initiatives (
    initiative_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),

    -- Initiative Details
    initiative_name VARCHAR(255) NOT NULL,
    initiative_type VARCHAR(50) CHECK (initiative_type IN (
        'conservation', 'renewable_energy', 'water_management',
        'soil_health', 'biodiversity', 'waste_reduction', 'carbon_sequestration'
    )),
    initiative_description TEXT,

    -- Implementation
    start_date DATE,
    completion_date DATE,
    implementation_cost DECIMAL(10,2),
    funding_sources JSONB DEFAULT '[]',

    -- Impact Assessment
    expected_impact JSONB DEFAULT '{}',
    actual_impact JSONB DEFAULT '{}',
    measurement_methodology TEXT,

    -- Status and Progress
    initiative_status VARCHAR(20) DEFAULT 'planned' CHECK (initiative_status IN (
        'planned', 'in_progress', 'completed', 'cancelled', 'failed'
    )),
    progress_percentage DECIMAL(5,2) DEFAULT 0,

    -- Certification and Recognition
    certifications_earned JSONB DEFAULT '[]',
    awards_recognitions JSONB DEFAULT '[]',

    -- Monitoring and Reporting
    monitoring_frequency VARCHAR(20) CHECK (monitoring_frequency IN ('daily', 'weekly', 'monthly', 'quarterly', 'annual')),
    next_monitoring_date DATE,
    reporting_requirements TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

CREATE TABLE farm_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_period VARCHAR(10) CHECK (report_period IN ('daily', 'weekly', 'monthly', 'quarterly', 'annual')),

    -- Production Metrics
    total_acres_farmed DECIMAL(10,2),
    crops_planted_count INTEGER,
    livestock_count INTEGER,
    equipment_utilization_percentage DECIMAL(5,2),

    -- Financial Performance
    total_revenue DECIMAL(12,2),
    total_expenses DECIMAL(12,2),
    net_profit DECIMAL(12,2) GENERATED ALWAYS AS (total_revenue - total_expenses) STORED,
    profit_margin_percentage DECIMAL(5,2),

    -- Yield and Productivity
    average_crop_yield DECIMAL(6,2),
    yield_variance_percentage DECIMAL(5,2),
    production_efficiency_rating DECIMAL(3,1),

    -- Resource Usage
    water_usage_gallons DECIMAL(12,2),
    energy_consumption_kwh DECIMAL(10,2),
    fuel_consumption_gallons DECIMAL(8,2),

    -- Environmental Impact
    carbon_footprint_tons DECIMAL(8,2),
    water_efficiency_rating DECIMAL(3,1),
    soil_health_score DECIMAL(3,1),

    -- Market Performance
    average_market_price DECIMAL(6,2),
    price_variance_percentage DECIMAL(5,2),
    market_share_percentage DECIMAL(4,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (farm_id, report_date, report_period)
);

CREATE TABLE crop_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    crop_id UUID NOT NULL REFERENCES crops(crop_id),
    farm_id UUID NOT NULL REFERENCES farms(farm_id),

    -- Time Dimensions
    report_date DATE NOT NULL,
    growing_season VARCHAR(10) CHECK (growing_season IN ('spring', 'summer', 'fall', 'winter')),

    -- Performance Metrics
    acres_planted DECIMAL(8,2),
    expected_yield DECIMAL(10,2),
    actual_yield DECIMAL(10,2),
    yield_efficiency DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN expected_yield > 0 THEN (actual_yield / expected_yield) * 100 ELSE 0 END
    ) STORED,

    -- Cost Analysis
    cost_per_acre DECIMAL(8,2),
    cost_per_unit DECIMAL(6,2),
    break_even_price DECIMAL(6,2),

    -- Quality Metrics
    quality_rating DECIMAL(3,1),
    market_grade_percentage DECIMAL(5,2),
    rejection_rate_percentage DECIMAL(5,2),

    -- Environmental Factors
    weather_impact_score DECIMAL(3,1),
    pest_pressure_rating DECIMAL(3,1),
    disease_incidence_percentage DECIMAL(5,2),

    -- Economic Performance
    revenue_per_acre DECIMAL(8,2),
    profit_per_acre DECIMAL(8,2),
    roi_percentage DECIMAL(5,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (crop_id, farm_id, report_date)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Farm and field indexes
CREATE INDEX idx_farms_location ON farms USING gist (farm_boundary);
CREATE INDEX idx_fields_farm ON fields (farm_id);
CREATE INDEX idx_fields_location ON fields USING gist (field_shape);
CREATE INDEX idx_soil_tests_field ON soil_tests (field_id, test_date DESC);

-- Crop and planting indexes
CREATE INDEX idx_crops_type ON crops (crop_type, crop_family);
CREATE INDEX idx_planting_plans_farm ON planting_plans (farm_id, plan_year);
CREATE INDEX idx_field_plantings_field ON field_plantings (field_id, planting_date DESC);
CREATE INDEX idx_field_plantings_crop ON field_plantings (crop_id);

-- Livestock indexes
CREATE INDEX idx_animals_farm ON animals (farm_id, current_health_status);
CREATE INDEX idx_animals_type ON animals (type_id);
CREATE INDEX idx_animal_health_records_animal ON animal_health_records (animal_id, event_date DESC);

-- Equipment indexes
CREATE INDEX idx_equipment_farm ON equipment (farm_id, equipment_status);
CREATE INDEX idx_equipment_usage_equipment ON equipment_usage (equipment_id, usage_date DESC);

-- Financial indexes
CREATE INDEX idx_farm_expenses_farm ON farm_expenses (farm_id, expense_date DESC);
CREATE INDEX idx_crop_sales_farm ON crop_sales (farm_id, sale_date DESC);
CREATE INDEX idx_livestock_sales_farm ON livestock_sales (farm_id, sale_date DESC);

-- Environmental indexes
CREATE INDEX idx_environmental_metrics_farm ON environmental_metrics (farm_id, measurement_date DESC);
CREATE INDEX idx_sustainability_initiatives_farm ON sustainability_initiatives (farm_id, initiative_status);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Farm overview dashboard
CREATE VIEW farm_overview AS
SELECT
    f.farm_id,
    f.farm_name,
    f.farm_type,
    f.total_acres,
    f.farming_method,

    -- Current season summary
    COUNT(DISTINCT fp.field_id) as fields_in_production,
    COUNT(DISTINCT fp.crop_id) as crops_planted,
    SUM(fp.acreage) as acres_planted,

    -- Livestock summary
    COUNT(DISTINCT a.animal_id) as total_animals,
    COUNT(DISTINCT CASE WHEN a.current_health_status = 'healthy' THEN a.animal_id END) as healthy_animals,

    -- Equipment status
    COUNT(DISTINCT e.equipment_id) as total_equipment,
    COUNT(DISTINCT CASE WHEN e.equipment_status = 'active' THEN e.equipment_id END) as active_equipment,

    -- Recent financial summary (last 30 days)
    COALESCE(SUM(fe.amount), 0) as recent_expenses,
    COALESCE(SUM(cs.total_revenue), 0) as recent_crop_revenue,
    COALESCE(SUM(ls.total_revenue), 0) as recent_livestock_revenue,

    -- Environmental health
    AVG(em.measurement_value) FILTER (WHERE em.metric_type = 'soil_organic_matter') as avg_soil_organic_matter,
    AVG(em.environmental_score) as avg_environmental_score,

    -- Operational efficiency
    ROUND(
        COUNT(DISTINCT CASE WHEN a.current_health_status = 'healthy' THEN a.animal_id END)::DECIMAL /
        NULLIF(COUNT(DISTINCT a.animal_id), 0) * 100, 1
    ) as animal_health_rate,

    ROUND(
        COUNT(DISTINCT CASE WHEN e.equipment_status = 'active' THEN e.equipment_id END)::DECIMAL /
        NULLIF(COUNT(DISTINCT e.equipment_id), 0) * 100, 1
    ) as equipment_availability_rate,

    -- Recent activity indicators
    MAX(fp.planting_date) as last_planting_date,
    MAX(ahr.event_date) as last_health_check_date,
    MAX(eu.usage_date) as last_equipment_usage_date

FROM farms f
LEFT JOIN fields fi ON f.farm_id = fi.farm_id
LEFT JOIN field_plantings fp ON fi.field_id = fp.field_id
    AND fp.planting_status IN ('planted', 'growing')
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
LEFT JOIN animal_health_records ahr ON a.animal_id = ahr.animal_id
    AND ahr.event_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN equipment_usage eu ON e.equipment_id = eu.equipment_id
    AND eu.usage_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY f.farm_id, f.farm_name, f.farm_type, f.total_acres, f.farming_method;

-- Crop performance analysis
CREATE VIEW crop_performance_analysis AS
SELECT
    c.crop_name,
    c.crop_type,
    f.farm_name,

    -- Planting and yield metrics
    COUNT(DISTINCT fp.planting_id) as planting_instances,
    SUM(fp.acreage) as total_acres_planted,
    AVG(fp.yield_per_acre) as avg_yield_per_acre,
    STDDEV(fp.yield_per_acre) as yield_variability,

    -- Cost analysis
    AVG(fp.seed_cost_per_acre + COALESCE(fp.fertilizer_cost_per_acre, 0)) as avg_cost_per_acre,
    AVG(fp.harvest_costs) as avg_harvest_cost_per_acre,

    -- Quality metrics
    AVG(fp.yield_quality_rating) as avg_quality_rating,
    COUNT(CASE WHEN fp.yield_quality_rating >= 4 THEN 1 END)::DECIMAL /
    COUNT(fp.planting_id) * 100 as high_quality_percentage,

    -- Time performance
    AVG(fp.actual_harvest_date - fp.planting_date) as avg_growing_days,
    COUNT(CASE WHEN fp.actual_harvest_date <= fp.expected_harvest_date THEN 1 END)::DECIMAL /
    COUNT(fp.planting_id) * 100 as on_time_harvest_percentage,

    -- Profitability
    AVG(fp.yield_per_acre * c.average_market_price_per_unit) as avg_revenue_per_acre,
    AVG(fp.yield_per_acre * c.average_market_price_per_unit - fp.seed_cost_per_acre) as avg_profit_per_acre,

    -- Recent performance (last season)
    AVG(CASE WHEN fp.planting_date >= CURRENT_DATE - INTERVAL '1 year' THEN fp.yield_per_acre END) as recent_avg_yield,
    MAX(fp.planting_date) as last_planting_date

FROM crops c
JOIN field_plantings fp ON c.crop_id = fp.crop_id
JOIN fields fi ON fp.field_id = fi.field_id
JOIN farms f ON fi.farm_id = f.farm_id
WHERE fp.planting_status = 'harvested'
GROUP BY c.crop_id, c.crop_name, c.crop_type, c.average_market_price_per_unit, f.farm_id, f.farm_name;

-- Equipment utilization and maintenance
CREATE VIEW equipment_utilization AS
SELECT
    e.equipment_name,
    e.equipment_type,
    e.manufacturer,
    f.farm_name,

    -- Usage metrics (last 90 days)
    COUNT(eu.usage_id) as usage_sessions,
    SUM(eu.hours_used) as total_hours_used,
    AVG(eu.hours_used) as avg_hours_per_session,
    SUM(eu.acres_covered) as total_acres_covered,

    -- Cost analysis
    SUM(eu.fuel_used_gallons) as total_fuel_used,
    SUM(eu.fuel_cost) as total_fuel_cost,
    SUM(eu.operating_cost) as total_operating_cost,
    SUM(eu.fuel_cost + eu.operating_cost) / NULLIF(SUM(eu.hours_used), 0) as cost_per_hour,

    -- Performance metrics
    AVG(eu.work_rate_acres_per_hour) as avg_work_rate_acres_per_hour,
    AVG(eu.fuel_efficiency_actual) as avg_fuel_efficiency,
    SUM(eu.equipment_downtime_minutes) as total_downtime_minutes,

    -- Maintenance tracking
    e.last_service_date,
    e.next_service_due,
    CASE WHEN e.next_service_due < CURRENT_DATE THEN TRUE ELSE FALSE END as maintenance_overdue,

    -- Utilization rate
    ROUND(
        SUM(eu.hours_used)::DECIMAL /
        (90 * 12) * 100, 1  -- Assuming 12 hours/day max utilization
    ) as utilization_percentage_last_90_days,

    -- Cost efficiency
    SUM(eu.acres_covered) / NULLIF(SUM(eu.fuel_used_gallons), 0) as acres_per_gallon_fuel,
    SUM(eu.acres_covered) / NULLIF(SUM(eu.fuel_cost + eu.operating_cost), 0) as acres_per_dollar_cost

FROM equipment e
JOIN farms f ON e.farm_id = f.farm_id
LEFT JOIN equipment_usage eu ON e.equipment_id = eu.equipment_id
    AND eu.usage_date >= CURRENT_DATE - INTERVAL '90 days'
WHERE e.equipment_status = 'active'
GROUP BY e.equipment_id, e.equipment_name, e.equipment_type, e.manufacturer,
         e.last_service_date, e.next_service_due, f.farm_name;

-- ===========================================
-- FUNCTIONS FOR AGRICULTURAL OPERATIONS
-- =========================================--

-- Function to calculate crop profitability
CREATE OR REPLACE FUNCTION calculate_crop_profitability(
    crop_uuid UUID,
    farm_uuid UUID,
    analysis_period_months INTEGER DEFAULT 12
)
RETURNS TABLE (
    crop_name VARCHAR,
    total_acres DECIMAL,
    total_yield DECIMAL,
    avg_yield_per_acre DECIMAL,
    total_revenue DECIMAL,
    total_costs DECIMAL,
    gross_profit DECIMAL,
    profit_per_acre DECIMAL,
    roi_percentage DECIMAL,
    profitability_rating VARCHAR
) AS $$
DECLARE
    crop_record crops%ROWTYPE;
BEGIN
    -- Get crop details
    SELECT * INTO crop_record FROM crops WHERE crop_id = crop_uuid;

    RETURN QUERY
    SELECT
        crop_record.crop_name,
        SUM(fp.acreage) as total_acres,
        SUM(fp.yield_per_acre * fp.acreage) as total_yield,
        AVG(fp.yield_per_acre) as avg_yield_per_acre,

        -- Revenue calculation
        SUM(fp.yield_per_acre * fp.acreage * crop_record.average_market_price_per_unit) as total_revenue,

        -- Cost calculation (simplified)
        SUM((fp.seed_cost_per_acre + fp.harvest_costs) * fp.acreage) as total_costs,

        -- Profit calculations
        SUM(fp.yield_per_acre * fp.acreage * crop_record.average_market_price_per_unit -
            (fp.seed_cost_per_acre + fp.harvest_costs) * fp.acreage) as gross_profit,

        AVG(fp.yield_per_acre * crop_record.average_market_price_per_unit -
            fp.seed_cost_per_acre - fp.harvest_costs) as profit_per_acre,

        ROUND(
            (
                SUM(fp.yield_per_acre * fp.acreage * crop_record.average_market_price_per_unit) /
                NULLIF(SUM((fp.seed_cost_per_acre + fp.harvest_costs) * fp.acreage), 0) - 1
            ) * 100, 2
        ) as roi_percentage,

        CASE
            WHEN AVG(fp.yield_per_acre * crop_record.average_market_price_per_unit - fp.seed_cost_per_acre - fp.harvest_costs) > 200 THEN 'excellent'
            WHEN AVG(fp.yield_per_acre * crop_record.average_market_price_per_unit - fp.seed_cost_per_acre - fp.harvest_costs) > 100 THEN 'good'
            WHEN AVG(fp.yield_per_acre * crop_record.average_market_price_per_unit - fp.seed_cost_per_acre - fp.harvest_costs) > 0 THEN 'marginal'
            ELSE 'unprofitable'
        END as profitability_rating

    FROM field_plantings fp
    JOIN fields fi ON fp.field_id = fi.field_id
    WHERE fp.crop_id = crop_uuid
      AND fi.farm_id = farm_uuid
      AND fp.planting_date >= CURRENT_DATE - INTERVAL '1 month' * analysis_period_months
      AND fp.planting_status = 'harvested'
    GROUP BY crop_record.crop_name;
END;
$$ LANGUAGE plpgsql;

-- Function to generate crop rotation recommendations
CREATE OR REPLACE FUNCTION recommend_crop_rotation(field_uuid UUID)
RETURNS TABLE (
    field_name VARCHAR,
    current_crop VARCHAR,
    recommended_crops JSONB,
    rotation_benefits JSONB,
    risk_reduction_score DECIMAL,
    expected_yield_improvement DECIMAL
) AS $$
DECLARE
    field_record fields%ROWTYPE;
    current_crop_name VARCHAR;
    previous_crops VARCHAR[];
BEGIN
    -- Get field and current crop information
    SELECT f.*, c.crop_name INTO field_record, current_crop_name
    FROM fields f
    LEFT JOIN field_plantings fp ON f.field_id = fp.field_id
        AND fp.planting_status IN ('planted', 'growing')
    LEFT JOIN crops c ON fp.crop_id = c.crop_id
    WHERE f.field_id = field_uuid;

    -- Get previous crops (last 3 years)
    SELECT array_agg(DISTINCT c2.crop_name)
    INTO previous_crops
    FROM field_plantings fp2
    JOIN crops c2 ON fp2.crop_id = c2.crop_id
    WHERE fp2.field_id = field_uuid
      AND fp2.planting_date >= CURRENT_DATE - INTERVAL '3 years'
      AND fp2.planting_status = 'harvested'
    LIMIT 3;

    RETURN QUERY SELECT
        field_record.field_name,
        current_crop_name,
        jsonb_build_array(
            jsonb_build_object(
                'crop', 'Winter Wheat',
                'planting_time', 'fall',
                'benefits', 'Excellent soil erosion control, nitrogen fixation'
            ),
            jsonb_build_object(
                'crop', 'Soybeans',
                'planting_time', 'spring',
                'benefits', 'Nitrogen fixation, break pest cycles, good residue'
            ),
            jsonb_build_object(
                'crop', 'Corn',
                'planting_time', 'spring',
                'benefits', 'High biomass production, good cash crop'
            )
        ) as recommended_crops,

        jsonb_build_object(
            'soil_health', 'Improved organic matter and structure',
            'pest_management', 'Break pest and disease cycles',
            'yield_stability', 'More consistent long-term yields',
            'economic', 'Diversified income streams'
        ) as rotation_benefits,

        7.5 as risk_reduction_score, -- Out of 10
        12.5 as expected_yield_improvement; -- Percentage
END;
$$ LANGUAGE plpgsql;

-- Function to calculate irrigation requirements
CREATE OR REPLACE FUNCTION calculate_irrigation_needs(
    field_uuid UUID,
    weather_forecast_days INTEGER DEFAULT 7
)
RETURNS TABLE (
    field_name VARCHAR,
    crop_name VARCHAR,
    current_soil_moisture DECIMAL,
    evapotranspiration_rate DECIMAL,
    irrigation_needed_inches DECIMAL,
    recommended_schedule JSONB,
    water_efficiency_rating VARCHAR,
    cost_estimate DECIMAL
) AS $$
DECLARE
    field_record fields%ROWTYPE;
    crop_record crops%ROWTYPE;
    planting_record field_plantings%ROWTYPE;
    soil_moisture DECIMAL := 0.75; -- Default 75% field capacity
    et_rate DECIMAL := 0.15; -- Default ET rate in inches/day
BEGIN
    -- Get field, crop, and planting information
    SELECT f.* INTO field_record FROM fields WHERE field_id = field_uuid;

    SELECT fp.*, c.* INTO planting_record, crop_record
    FROM field_plantings fp
    JOIN crops c ON fp.crop_id = c.crop_id
    WHERE fp.field_id = field_uuid
      AND fp.planting_status IN ('planted', 'growing')
    ORDER BY fp.planting_date DESC
    LIMIT 1;

    -- Calculate irrigation needs based on crop water requirements
    CASE crop_record.crop_type
        WHEN 'grain' THEN
            et_rate := 0.12;
            soil_moisture := 0.70;
        WHEN 'vegetable' THEN
            et_rate := 0.18;
            soil_moisture := 0.80;
        WHEN 'fruit' THEN
            et_rate := 0.15;
            soil_moisture := 0.75;
        ELSE
            et_rate := 0.10;
            soil_moisture := 0.65;
    END CASE;

    RETURN QUERY SELECT
        field_record.field_name,
        crop_record.crop_name,
        soil_moisture * 100 as current_soil_moisture,
        et_rate * 24 as evapotranspiration_rate, -- Convert to inches/day
        et_rate * weather_forecast_days as irrigation_needed_inches,

        jsonb_build_object(
            'frequency', CASE
                WHEN et_rate > 0.15 THEN 'daily'
                WHEN et_rate > 0.10 THEN 'every 2-3 days'
                ELSE 'weekly'
            END,
            'amount_per_application', ROUND(et_rate * weather_forecast_days / 3, 2),
            'best_time', 'Early morning',
            'method', 'Drip irrigation'
        ) as recommended_schedule,

        CASE
            WHEN et_rate < 0.12 THEN 'excellent'
            WHEN et_rate < 0.15 THEN 'good'
            ELSE 'needs_improvement'
        END as water_efficiency_rating,

        ROUND(et_rate * weather_forecast_days * field_record.acreage * 27.15, 2) as cost_estimate; -- Cost per acre-inch
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample farm
INSERT INTO farms (
    farm_name, farm_code, farm_type, total_acres,
    farming_method, irrigation_system, address
) VALUES (
    'Green Valley Farms', 'GVF001', 'mixed_farm', 500.00,
    'organic', 'drip',
    '{"street": "123 Farm Road", "city": "Springfield", "state": "IL", "zip": "62701"}'
);

-- Insert sample crop
INSERT INTO crops (
    crop_name, crop_code, crop_type, scientific_name,
    growing_season, days_to_maturity, average_market_price_per_unit
) VALUES (
    'Corn', 'CORN001', 'grain', 'Zea mays',
    'summer', 110, 4.50
);

-- Insert sample field
INSERT INTO fields (
    farm_id, field_name, field_code, acreage, soil_type
) VALUES (
    (SELECT farm_id FROM farms WHERE farm_code = 'GVF001' LIMIT 1),
    'North Field', 'NF001', 80.50, 'silt_loam'
);

-- Insert sample animal type
INSERT INTO livestock_types (
    type_name, type_code, species, production_type,
    average_weight_lbs, average_lifespan_years
) VALUES (
    'Holstein Dairy Cow', 'HOLSTEIN', 'cattle', 'dairy',
    1500.00, 8.0
);

-- Insert sample animal
INSERT INTO animals (
    farm_id, type_id, animal_tag, birth_date,
    gender, current_health_status
) VALUES (
    (SELECT farm_id FROM farms WHERE farm_code = 'GVF001' LIMIT 1),
    (SELECT type_id FROM livestock_types WHERE type_code = 'HOLSTEIN' LIMIT 1),
    'HOL001', '2020-03-15',
    'female', 'healthy'
);

-- Insert sample equipment
INSERT INTO equipment (
    farm_id, equipment_name, equipment_code, equipment_type,
    manufacturer, model, horsepower, purchase_date
) VALUES (
    (SELECT farm_id FROM farms WHERE farm_code = 'GVF001' LIMIT 1),
    'John Deere Tractor 8R', 'JD8R001', 'tractor',
    'John Deere', '8R 250', 250, '2018-05-01'
);

-- Insert sample expense
INSERT INTO farm_expenses (
    farm_id, expense_category, vendor_name, amount,
    expense_date, payment_method
) VALUES (
    (SELECT farm_id FROM farms WHERE farm_code = 'GVF001' LIMIT 1),
    'seed', 'AgriSeed Co', 2500.00,
    '2024-04-15', 'check'
);

-- This agriculture schema provides comprehensive infrastructure for farm management,
-- crop planning, livestock tracking, equipment management, and financial operations.
