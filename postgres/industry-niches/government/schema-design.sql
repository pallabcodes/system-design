-- Government & Public Services Database Schema
-- Comprehensive schema for government agencies, public services, and civic data management

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "postgis"; -- For geospatial data

-- ===========================================
-- CITIZEN AND CONSTITUENT MANAGEMENT
-- ===========================================

CREATE TABLE citizens (
    citizen_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    national_id VARCHAR(20) UNIQUE, -- National ID number (encrypted)

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(20),
    marital_status VARCHAR(20) CHECK (marital_status IN ('single', 'married', 'divorced', 'widowed')),

    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(20),
    mailing_address JSONB, -- Full address structure
    residential_address JSONB,

    -- Demographics
    ethnicity VARCHAR(50),
    nationality VARCHAR(50),
    language_primary VARCHAR(10) DEFAULT 'en',
    languages_additional TEXT[],

    -- Government-specific Information
    voter_registration_status VARCHAR(20) CHECK (voter_registration_status IN ('registered', 'not_registered', 'suspended', 'ineligible')),
    voter_id VARCHAR(50),
    precinct_id VARCHAR(20),

    -- Employment and Education
    employment_status VARCHAR(30),
    education_level VARCHAR(30),
    occupation VARCHAR(100),

    -- Status and Flags
    citizen_status VARCHAR(20) DEFAULT 'active' CHECK (citizen_status IN ('active', 'inactive', 'deceased', 'emigrated')),
    is_military_veteran BOOLEAN DEFAULT FALSE,
    disability_status BOOLEAN DEFAULT FALSE,
    disability_details TEXT,

    -- Security and Verification
    identity_verified BOOLEAN DEFAULT FALSE,
    identity_verification_date DATE,
    biometric_data JSONB, -- Fingerprint, facial recognition data (encrypted)

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_verified_at TIMESTAMP WITH TIME ZONE,

    CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years')
);

-- ===========================================
-- GOVERNMENT AGENCIES AND DEPARTMENTS
-- ===========================================

CREATE TABLE government_agencies (
    agency_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agency_code VARCHAR(10) UNIQUE NOT NULL,
    agency_name VARCHAR(255) NOT NULL,

    -- Agency Classification
    agency_type VARCHAR(30) NOT NULL CHECK (agency_type IN (
        'executive', 'legislative', 'judicial', 'independent',
        'state', 'local', 'federal', 'international'
    )),
    parent_agency_id UUID REFERENCES government_agencies(agency_id),

    -- Jurisdiction
    jurisdiction_level VARCHAR(20) CHECK (jurisdiction_level IN ('federal', 'state', 'county', 'municipal', 'special_district')),
    jurisdiction_area GEOGRAPHY(POLYGON, 4326), -- Geographic boundaries

    -- Contact Information
    address JSONB,
    phone VARCHAR(20),
    website VARCHAR(500),
    email VARCHAR(255),

    -- Agency Details
    established_date DATE,
    budget_authority DECIMAL(15,2),
    employee_count INTEGER,

    -- Status
    agency_status VARCHAR(20) DEFAULT 'active' CHECK (agency_status IN ('active', 'inactive', 'dissolved', 'merged')),

    -- Hierarchy level for reporting
    hierarchy_level INTEGER DEFAULT 1,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE government_employees (
    employee_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agency_id UUID NOT NULL REFERENCES government_agencies(agency_id),
    citizen_id UUID REFERENCES citizens(citizen_id), -- Link to citizen record

    -- Employment Information
    employee_number VARCHAR(20) UNIQUE NOT NULL,
    job_title VARCHAR(100) NOT NULL,
    job_grade VARCHAR(20), -- GS scale, etc.
    department VARCHAR(100),
    division VARCHAR(100),

    -- Employment Details
    hire_date DATE NOT NULL,
    termination_date DATE,
    employment_status VARCHAR(20) DEFAULT 'active' CHECK (employment_status IN ('active', 'inactive', 'terminated', 'retired', 'leave')),

    -- Compensation
    salary DECIMAL(12,2),
    pay_scale VARCHAR(20),
    benefits_package JSONB DEFAULT '{}',

    -- Security Clearance
    security_clearance_level VARCHAR(20) CHECK (security_clearance_level IN ('none', 'confidential', 'secret', 'top_secret', 'special_access')),
    clearance_granted_date DATE,
    clearance_expiry_date DATE,

    -- Supervisor and Reporting
    supervisor_id UUID REFERENCES government_employees(employee_id),
    reports_to UUID REFERENCES government_employees(employee_id),

    -- Work Location
    office_location VARCHAR(255),
    work_schedule JSONB DEFAULT '{}', -- Flexible work schedules

    -- Performance and Training
    performance_rating DECIMAL(3,1),
    last_performance_review DATE,
    training_completed JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (hire_date <= COALESCE(termination_date, CURRENT_DATE))
);

-- ===========================================
-- LEGISLATIVE AND POLICY MANAGEMENT
-- ===========================================

CREATE TABLE legislation (
    legislation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    legislation_number VARCHAR(50) UNIQUE NOT NULL, -- e.g., "HR 1234", "S. 567"

    -- Legislation Details
    title VARCHAR(500) NOT NULL,
    description TEXT,
    legislation_type VARCHAR(30) CHECK (legislation_type IN ('bill', 'resolution', 'amendment', 'treaty', 'executive_order')),

    -- Sponsors and Authors
    primary_sponsor_id UUID REFERENCES government_employees(employee_id),
    co_sponsors UUID[], -- Array of sponsor IDs
    committee_id UUID, -- Assigned committee

    -- Status and Lifecycle
    legislation_status VARCHAR(30) DEFAULT 'introduced' CHECK (legislation_status IN (
        'introduced', 'referred_to_committee', 'reported_by_committee',
        'passed_house', 'passed_senate', 'sent_to_president',
        'signed_into_law', 'vetoed', 'failed', 'withdrawn'
    )),

    -- Dates
    introduced_date DATE DEFAULT CURRENT_DATE,
    enacted_date DATE,
    effective_date DATE,

    -- Content
    full_text TEXT,
    summary TEXT,
    key_provisions JSONB DEFAULT '[]',

    -- Categories and Tags
    subject_areas TEXT[],
    keywords TEXT[],

    -- Voting Records
    house_vote_date DATE,
    house_vote_result JSONB, -- {"yea": 234, "nay": 201, "present": 0}
    senate_vote_date DATE,
    senate_vote_result JSONB,

    -- Impact Assessment
    estimated_cost DECIMAL(15,2),
    affected_agencies UUID[], -- Array of affected agency IDs
    sunset_date DATE, -- Expiration date if applicable

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE regulations (
    regulation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    regulation_number VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(500) NOT NULL,

    -- Agency and Authority
    issuing_agency_id UUID NOT NULL REFERENCES government_agencies(agency_id),
    authority_citation VARCHAR(255), -- Legal authority for the regulation

    -- Regulation Details
    regulation_type VARCHAR(30) CHECK (regulation_type IN ('proposed', 'final', 'interim', 'emergency')),
    abstract TEXT,
    full_text TEXT,

    -- Publication
    federal_register_citation VARCHAR(100),
    publication_date DATE,
    effective_date DATE,

    -- Status
    regulation_status VARCHAR(20) DEFAULT 'active' CHECK (regulation_status IN ('proposed', 'active', 'withdrawn', 'superseded')),

    -- Compliance
    compliance_requirements TEXT,
    compliance_deadline DATE,
    penalties_for_noncompliance TEXT,

    -- Review and Sunset
    review_date DATE,
    sunset_date DATE,

    -- Related Legislation
    related_legislation UUID[], -- Array of legislation IDs

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- PUBLIC SERVICES AND BENEFITS
-- ===========================================

CREATE TABLE public_services (
    service_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_name VARCHAR(255) NOT NULL,
    service_code VARCHAR(20) UNIQUE NOT NULL,

    -- Service Classification
    service_category VARCHAR(50) CHECK (service_category IN (
        'healthcare', 'education', 'housing', 'nutrition', 'employment',
        'transportation', 'utilities', 'legal_aid', 'childcare', 'elder_care'
    )),
    service_type VARCHAR(30) CHECK (service_type IN ('benefit', 'service', 'program', 'subsidy')),

    -- Service Provider
    providing_agency_id UUID REFERENCES government_agencies(agency_id),
    service_provider_name VARCHAR(255),
    contact_information JSONB,

    -- Eligibility Criteria
    eligibility_criteria JSONB NOT NULL, -- Complex eligibility rules
    income_limits JSONB, -- Income-based eligibility
    geographic_restrictions GEOGRAPHY(POLYGON, 4326),

    -- Service Details
    description TEXT,
    application_process TEXT,
    required_documents TEXT[],
    processing_time_days INTEGER,

    -- Financial Information
    annual_budget DECIMAL(15,2),
    cost_per_recipient DECIMAL(10,2),

    -- Status and Availability
    service_status VARCHAR(20) DEFAULT 'active' CHECK (service_status IN ('active', 'inactive', 'suspended', 'terminated')),
    available_online BOOLEAN DEFAULT FALSE,
    available_in_person BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE service_applications (
    application_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id UUID NOT NULL REFERENCES public_services(service_id),
    citizen_id UUID NOT NULL REFERENCES citizens(citizen_id),

    -- Application Details
    application_status VARCHAR(30) DEFAULT 'submitted' CHECK (application_status IN (
        'draft', 'submitted', 'under_review', 'approved', 'denied',
        'appeal_pending', 'appeal_approved', 'appeal_denied', 'withdrawn'
    )),

    -- Application Data
    application_data JSONB NOT NULL, -- Complete application form
    supporting_documents JSONB DEFAULT '[]', -- Array of document references

    -- Processing
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    decision_date DATE,

    -- Case Worker
    assigned_case_worker_id UUID REFERENCES government_employees(employee_id),
    processing_agency_id UUID REFERENCES government_agencies(agency_id),

    -- Financial Information
    household_income DECIMAL(12,2),
    household_size INTEGER,
    calculated_eligibility_score DECIMAL(5,2),

    -- Decision Details
    approval_amount DECIMAL(12,2),
    denial_reason VARCHAR(100),
    appeal_deadline DATE,

    -- Benefit Details (if approved)
    benefit_start_date DATE,
    benefit_end_date DATE,
    recurring_amount DECIMAL(10,2),
    payment_frequency VARCHAR(20) DEFAULT 'monthly',

    -- Audit
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES government_employees(employee_id),

    CHECK (benefit_start_date <= benefit_end_date)
);

-- ===========================================
-- TAXATION AND REVENUE MANAGEMENT
-- ===========================================

CREATE TABLE tax_records (
    tax_record_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    citizen_id UUID NOT NULL REFERENCES citizens(citizen_id),

    -- Tax Year and Type
    tax_year INTEGER NOT NULL,
    tax_type VARCHAR(30) NOT NULL CHECK (tax_type IN ('income', 'property', 'sales', 'business', 'excise', 'estate')),

    -- Filing Information
    filing_status VARCHAR(20) CHECK (filing_status IN ('single', 'married_joint', 'married_separate', 'head_of_household')),
    tax_return_filed BOOLEAN DEFAULT FALSE,
    filing_date DATE,

    -- Income and Deductions
    gross_income DECIMAL(15,2),
    taxable_income DECIMAL(15,2),
    total_deductions DECIMAL(12,2),
    total_credits DECIMAL(12,2),

    -- Tax Calculation
    tax_owed DECIMAL(12,2),
    tax_paid DECIMAL(12,2),
    tax_refund DECIMAL(12,2),
    balance_due DECIMAL(12,2) GENERATED ALWAYS AS (tax_owed - tax_paid) STORED,

    -- Payment Information
    payment_plan BOOLEAN DEFAULT FALSE,
    payment_deadline DATE,
    last_payment_date DATE,

    -- Audit and Compliance
    audit_status VARCHAR(20) DEFAULT 'not_audited' CHECK (audit_status IN ('not_audited', 'selected_for_audit', 'under_audit', 'audit_completed', 'audit_appeal')),
    audit_start_date DATE,
    audit_completion_date DATE,

    -- Collections
    collections_status VARCHAR(20) DEFAULT 'current' CHECK (collections_status IN ('current', 'delinquent', 'collections', 'paid_in_full')),
    collections_agency_assigned BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (citizen_id, tax_year, tax_type)
);

CREATE TABLE property_tax_assessments (
    assessment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id VARCHAR(50) NOT NULL, -- Property identification number
    citizen_id UUID REFERENCES citizens(citizen_id), -- Property owner

    -- Assessment Details
    assessment_year INTEGER NOT NULL,
    assessment_date DATE DEFAULT CURRENT_DATE,

    -- Property Information
    property_address JSONB NOT NULL,
    property_type VARCHAR(30) CHECK (property_type IN ('residential', 'commercial', 'industrial', 'agricultural', 'vacant')),
    square_footage INTEGER,
    land_value DECIMAL(12,2),
    improvement_value DECIMAL(12,2),

    -- Assessment Calculation
    assessed_value DECIMAL(12,2),
    tax_rate DECIMAL(6,4), -- Property tax rate (e.g., 0.0125 for 1.25%)
    annual_tax_amount DECIMAL(10,2) GENERATED ALWAYS AS (assessed_value * tax_rate) STORED,

    -- Exemptions and Reductions
    exemptions_applied JSONB DEFAULT '[]',
    senior_discount BOOLEAN DEFAULT FALSE,
    disability_discount BOOLEAN DEFAULT FALSE,
    total_exemptions DECIMAL(10,2) DEFAULT 0,

    -- Adjusted Tax
    adjusted_tax_amount DECIMAL(10,2) GENERATED ALWAYS AS (annual_tax_amount - total_exemptions) STORED,

    -- Payment Status
    tax_year INTEGER,
    amount_paid DECIMAL(10,2) DEFAULT 0,
    payment_status VARCHAR(20) DEFAULT 'unpaid' CHECK (payment_status IN ('paid', 'unpaid', 'delinquent', 'tax_lien')),

    -- Appeals
    appeal_filed BOOLEAN DEFAULT FALSE,
    appeal_date DATE,
    appeal_status VARCHAR(20) CHECK (appeal_status IN ('pending', 'approved', 'denied', 'withdrawn')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (property_id, assessment_year)
);

-- ===========================================
-- ELECTIONS AND VOTING
-- ===========================================

CREATE TABLE elections (
    election_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    election_name VARCHAR(255) NOT NULL,
    election_type VARCHAR(30) CHECK (election_type IN ('general', 'primary', 'special', 'recall', 'referendum')),

    -- Election Details
    election_date DATE NOT NULL,
    registration_deadline DATE,
    early_voting_start DATE,
    absentee_ballot_deadline DATE,

    -- Jurisdiction
    jurisdiction_level VARCHAR(20) CHECK (jurisdiction_level IN ('federal', 'state', 'county', 'municipal')),
    jurisdiction_area GEOGRAPHY(POLYGON, 4326),

    -- Status
    election_status VARCHAR(20) DEFAULT 'scheduled' CHECK (election_status IN ('scheduled', 'active', 'completed', 'cancelled')),

    -- Turnout and Results
    registered_voters INTEGER,
    ballots_cast INTEGER,
    voter_turnout DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN registered_voters > 0 THEN (ballots_cast::DECIMAL / registered_voters) * 100 ELSE 0 END
    ) STORED,

    -- Administration
    election_officials JSONB DEFAULT '[]',
    polling_places JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (registration_deadline < election_date),
    CHECK (early_voting_start < election_date)
);

CREATE TABLE ballot_measures (
    measure_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    election_id UUID NOT NULL REFERENCES elections(election_id),

    -- Measure Details
    measure_number VARCHAR(10) NOT NULL,
    measure_title VARCHAR(500) NOT NULL,
    measure_text TEXT NOT NULL,

    -- Measure Type
    measure_type VARCHAR(30) CHECK (measure_type IN ('initiative', 'referendum', 'recall', 'constitutional_amendment', 'bond_measure')),

    -- Sponsor Information
    sponsor_name VARCHAR(255),
    sponsor_type VARCHAR(30) CHECK (sponsor_type IN ('citizen', 'legislature', 'executive', 'court')),

    -- Voting Requirements
    majority_required VARCHAR(20) DEFAULT 'simple' CHECK (majority_required IN ('simple', 'supermajority', 'two_thirds')),
    minimum_turnout_required DECIMAL(5,2), -- Percentage of registered voters

    -- Results
    votes_for INTEGER DEFAULT 0,
    votes_against INTEGER DEFAULT 0,
    votes_abstain INTEGER DEFAULT 0,

    -- Status
    measure_status VARCHAR(20) DEFAULT 'on_ballot' CHECK (measure_status IN ('proposed', 'qualified', 'on_ballot', 'passed', 'failed', 'withdrawn')),

    -- Financial Impact (for bond measures)
    estimated_cost DECIMAL(15,2),
    funding_source VARCHAR(100),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- PUBLIC INFRASTRUCTURE AND ASSETS
-- ===========================================

CREATE TABLE public_assets (
    asset_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_number VARCHAR(50) UNIQUE NOT NULL,

    -- Asset Information
    asset_name VARCHAR(255) NOT NULL,
    asset_type VARCHAR(50) NOT NULL CHECK (asset_type IN (
        'building', 'road', 'bridge', 'park', 'vehicle', 'equipment',
        'land', 'water_system', 'sewer_system', 'power_grid', 'technology'
    )),
    asset_category VARCHAR(30) CHECK (asset_category IN ('infrastructure', 'vehicle', 'equipment', 'land', 'building')),

    -- Location and Ownership
    location GEOGRAPHY(POINT, 4326),
    address JSONB,
    owning_agency_id UUID REFERENCES government_agencies(agency_id),

    -- Asset Details
    acquisition_date DATE,
    acquisition_cost DECIMAL(15,2),
    current_value DECIMAL(15,2),
    useful_life_years INTEGER,
    depreciation_method VARCHAR(30) CHECK (deprecation_method IN ('straight_line', 'declining_balance', 'units_of_production')),

    -- Maintenance and Condition
    condition_rating INTEGER CHECK (condition_rating BETWEEN 1 AND 5), -- 1=poor, 5=excellent
    last_inspection_date DATE,
    next_maintenance_date DATE,
    maintenance_history JSONB DEFAULT '[]',

    -- Usage and Performance
    utilization_rate DECIMAL(5,2), -- Percentage of capacity used
    performance_metrics JSONB DEFAULT '{}',

    -- Status
    asset_status VARCHAR(20) DEFAULT 'active' CHECK (asset_status IN ('active', 'inactive', 'maintenance', 'retired', 'disposed')),

    -- Insurance and Risk
    insured_value DECIMAL(15,2),
    insurance_policy_number VARCHAR(50),
    risk_assessment JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- EMERGENCY MANAGEMENT AND RESPONSE
-- ===========================================

CREATE TABLE emergency_incidents (
    incident_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_number VARCHAR(30) UNIQUE NOT NULL,

    -- Incident Details
    incident_type VARCHAR(50) NOT NULL CHECK (incident_type IN (
        'fire', 'medical_emergency', 'accident', 'natural_disaster',
        'hazardous_material', 'security_threat', 'public_safety', 'other'
    )),
    incident_severity VARCHAR(20) DEFAULT 'minor' CHECK (incident_severity IN ('minor', 'moderate', 'major', 'critical')),

    -- Location and Time
    incident_location GEOGRAPHY(POINT, 4326),
    incident_address JSONB,
    incident_datetime TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Description and Response
    incident_description TEXT,
    initial_response TEXT,
    responding_agencies UUID[], -- Array of agency IDs

    -- Status and Resolution
    incident_status VARCHAR(30) DEFAULT 'reported' CHECK (incident_status IN (
        'reported', 'responding', 'contained', 'resolved', 'under_investigation'
    )),
    resolution_datetime TIMESTAMP WITH TIME ZONE,
    resolution_summary TEXT,

    -- Impact Assessment
    injuries_count INTEGER DEFAULT 0,
    fatalities_count INTEGER DEFAULT 0,
    property_damage DECIMAL(15,2),
    economic_impact DECIMAL(15,2),

    -- Investigation
    investigation_required BOOLEAN DEFAULT FALSE,
    investigating_agency_id UUID REFERENCES government_agencies(agency_id),
    investigation_status VARCHAR(20) CHECK (investigation_status IN ('pending', 'active', 'completed', 'closed')),

    -- Public Communication
    public_alert_issued BOOLEAN DEFAULT FALSE,
    media_releases JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Citizen indexes
CREATE INDEX idx_citizens_national_id ON citizens (national_id);
CREATE INDEX idx_citizens_date_of_birth ON citizens (date_of_birth);
CREATE INDEX idx_citizens_status ON citizens (citizen_status);
CREATE INDEX idx_citizens_voter_status ON citizens (voter_registration_status);

-- Government employee indexes
CREATE INDEX idx_gov_employees_agency ON government_employees (agency_id);
CREATE INDEX idx_gov_employees_status ON government_employees (employment_status);
CREATE INDEX idx_gov_employees_supervisor ON government_employees (supervisor_id);

-- Legislation indexes
CREATE INDEX idx_legislation_status ON legislation (legislation_status);
CREATE INDEX idx_legislation_type ON legislation (legislation_type);
CREATE INDEX idx_legislation_sponsor ON legislation (primary_sponsor_id);
CREATE INDEX idx_legislation_dates ON legislation (introduced_date, enacted_date);

-- Service application indexes
CREATE INDEX idx_service_applications_citizen ON service_applications (citizen_id);
CREATE INDEX idx_service_applications_service ON service_applications (service_id);
CREATE INDEX idx_service_applications_status ON service_applications (application_status);

-- Tax record indexes
CREATE INDEX idx_tax_records_citizen ON tax_records (citizen_id);
CREATE INDEX idx_tax_records_year_type ON tax_records (tax_year, tax_type);
CREATE INDEX idx_tax_records_status ON tax_records (audit_status, collections_status);

-- Election indexes
CREATE INDEX idx_elections_date ON elections (election_date);
CREATE INDEX idx_elections_type ON elections (election_type);
CREATE INDEX idx_elections_status ON elections (election_status);

-- Emergency indexes
CREATE INDEX idx_emergency_incidents_type ON emergency_incidents (incident_type);
CREATE INDEX idx_emergency_incidents_status ON emergency_incidents (incident_status);
CREATE INDEX idx_emergency_incidents_datetime ON emergency_incidents (incident_datetime DESC);
CREATE INDEX idx_emergency_incidents_location ON emergency_incidents USING gist (incident_location);

-- ===========================================
-- USEFUL VIEWS
-- =========================================--

-- Citizen demographic summary
CREATE VIEW citizen_demographics AS
SELECT
    EXTRACT(YEAR FROM AGE(date_of_birth)) as age,
    gender,
    ethnicity,
    employment_status,
    education_level,
    citizen_status,
    voter_registration_status,
    is_military_veteran,
    disability_status,
    COUNT(*) as citizen_count
FROM citizens
WHERE citizen_status = 'active'
GROUP BY age, gender, ethnicity, employment_status, education_level,
         citizen_status, voter_registration_status, is_military_veteran, disability_status;

-- Government workforce summary
CREATE VIEW government_workforce_summary AS
SELECT
    ga.agency_name,
    ge.job_grade,
    ge.employment_status,
    ge.security_clearance_level,
    COUNT(*) as employee_count,
    AVG(ge.salary) as avg_salary,
    AVG(ge.performance_rating) as avg_performance_rating
FROM government_employees ge
JOIN government_agencies ga ON ge.agency_id = ga.agency_id
WHERE ge.employment_status = 'active'
GROUP BY ga.agency_name, ge.job_grade, ge.employment_status, ge.security_clearance_level;

-- Legislation tracking view
CREATE VIEW legislation_tracking AS
SELECT
    l.legislation_id,
    l.legislation_number,
    l.title,
    l.legislation_status,
    l.introduced_date,
    l.enacted_date,
    l.effective_date,
    ga.agency_name as primary_sponsor_agency,
    l.subject_areas,
    l.estimated_cost,
    l.affected_agencies
FROM legislation l
LEFT JOIN government_employees ge ON l.primary_sponsor_id = ge.employee_id
LEFT JOIN government_agencies ga ON ge.agency_id = ga.agency_id;

-- Public services utilization view
CREATE VIEW public_services_utilization AS
SELECT
    ps.service_name,
    ps.service_category,
    ps.service_status,
    COUNT(sa.application_id) as total_applications,
    COUNT(CASE WHEN sa.application_status = 'approved' THEN 1 END) as approved_applications,
    COUNT(CASE WHEN sa.application_status = 'denied' THEN 1 END) as denied_applications,
    AVG(sa.calculated_eligibility_score) as avg_eligibility_score,
    SUM(sa.approval_amount) as total_benefits_approved,
    AVG(sa.processing_time_days) as avg_processing_days
FROM public_services ps
LEFT JOIN service_applications sa ON ps.service_id = sa.service_id
WHERE ps.service_status = 'active'
GROUP BY ps.service_id, ps.service_name, ps.service_category, ps.service_status;

-- Tax revenue summary view
CREATE VIEW tax_revenue_summary AS
SELECT
    tax_year,
    tax_type,
    COUNT(*) as returns_filed,
    SUM(gross_income) as total_gross_income,
    SUM(taxable_income) as total_taxable_income,
    SUM(tax_owed) as total_tax_owed,
    SUM(tax_paid) as total_tax_paid,
    SUM(tax_refund) as total_refunds_issued,
    COUNT(CASE WHEN audit_status = 'under_audit' THEN 1 END) as returns_under_audit,
    COUNT(CASE WHEN collections_status = 'delinquent' THEN 1 END) as delinquent_accounts
FROM tax_records
GROUP BY tax_year, tax_type
ORDER BY tax_year DESC, tax_type;

-- Emergency response summary view
CREATE VIEW emergency_response_summary AS
SELECT
    DATE_TRUNC('month', incident_datetime) as incident_month,
    incident_type,
    incident_severity,
    COUNT(*) as incident_count,
    AVG(EXTRACT(EPOCH FROM (resolution_datetime - incident_datetime))/3600) as avg_response_hours,
    SUM(injuries_count) as total_injuries,
    SUM(fatalities_count) as total_fatalities,
    SUM(property_damage) as total_property_damage,
    COUNT(CASE WHEN investigation_required THEN 1 END) as investigations_required
FROM emergency_incidents
WHERE incident_datetime >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', incident_datetime), incident_type, incident_severity
ORDER BY incident_month DESC;

-- ===========================================
-- FUNCTIONS FOR GOVERNMENT OPERATIONS
-- =========================================--

-- Function to calculate citizen age and age group
CREATE OR REPLACE FUNCTION get_citizen_age_group(birth_date DATE)
RETURNS VARCHAR(20) AS $$
DECLARE
    age_years INTEGER;
BEGIN
    age_years := EXTRACT(YEAR FROM AGE(birth_date));

    CASE
        WHEN age_years < 18 THEN RETURN 'minor';
        WHEN age_years < 25 THEN RETURN 'young_adult';
        WHEN age_years < 35 THEN RETURN 'adult';
        WHEN age_years < 50 THEN RETURN 'middle_age';
        WHEN age_years < 65 THEN RETURN 'senior';
        ELSE RETURN 'elderly';
    END CASE;
END;
$$ LANGUAGE plpgsql;

-- Function to check service eligibility
CREATE OR REPLACE FUNCTION check_service_eligibility(
    citizen_uuid UUID,
    service_uuid UUID,
    application_data JSONB DEFAULT '{}'
)
RETURNS TABLE (
    is_eligible BOOLEAN,
    eligibility_score DECIMAL,
    disqualifying_factors TEXT[],
    recommended_actions TEXT[]
) AS $$
DECLARE
    service_record public_services%ROWTYPE;
    citizen_record citizens%ROWTYPE;
    income_level DECIMAL;
    eligibility_score_val DECIMAL := 100.0;
    disqualifiers TEXT[] := ARRAY[]::TEXT[];
    recommendations TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Get service and citizen details
    SELECT * INTO service_record FROM public_services WHERE service_id = service_uuid;
    SELECT * INTO citizen_record FROM citizens WHERE citizen_id = citizen_uuid;

    -- Check income eligibility
    income_level := COALESCE((application_data->>'household_income')::DECIMAL, citizen_record.annual_income);

    IF service_record.income_limits IS NOT NULL THEN
        IF income_level > (service_record.income_limits->>'max_income')::DECIMAL THEN
            eligibility_score_val := eligibility_score_val - 50;
            disqualifiers := disqualifiers || 'Income exceeds limit';
            recommendations := recommendations || 'Consider alternative assistance programs';
        END IF;
    END IF;

    -- Check geographic eligibility
    IF service_record.geographic_restrictions IS NOT NULL THEN
        -- Geographic check would require PostGIS functions
        -- Simplified for this example
        eligibility_score_val := eligibility_score_val - 10;
        recommendations := recommendations || 'Verify residence within service area';
    END IF;

    -- Check age requirements
    IF service_record.eligibility_criteria ? 'min_age' THEN
        IF EXTRACT(YEAR FROM AGE(citizen_record.date_of_birth)) < (service_record.eligibility_criteria->>'min_age')::INTEGER THEN
            disqualifiers := disqualifiers || 'Below minimum age requirement';
        END IF;
    END IF;

    RETURN QUERY SELECT
        (array_length(disqualifiers, 1) IS NULL OR array_length(disqualifiers, 1) = 0),
        eligibility_score_val,
        disqualifiers,
        recommendations;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate tax liability
CREATE OR REPLACE FUNCTION calculate_tax_liability(
    taxable_income DECIMAL,
    filing_status VARCHAR,
    tax_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
)
RETURNS DECIMAL AS $$
DECLARE
    tax_brackets JSONB;
    tax_owed DECIMAL := 0;
    remaining_income DECIMAL := taxable_income;
    bracket_min DECIMAL;
    bracket_max DECIMAL;
    bracket_rate DECIMAL;
    taxable_in_bracket DECIMAL;
BEGIN
    -- Get tax brackets for the year and filing status
    -- This would typically come from a tax_brackets table
    -- Simplified example with static brackets
    CASE filing_status
        WHEN 'single' THEN
            tax_brackets := '[
                {"min": 0, "max": 11000, "rate": 0.10},
                {"min": 11000, "max": 44725, "rate": 0.12},
                {"min": 44725, "max": 95375, "rate": 0.22}
            ]'::JSONB;
        WHEN 'married_joint' THEN
            tax_brackets := '[
                {"min": 0, "max": 22000, "rate": 0.10},
                {"min": 22000, "max": 89450, "rate": 0.12},
                {"min": 89450, "max": 190750, "rate": 0.22}
            ]'::JSONB;
        ELSE
            RETURN 0; -- Unsupported filing status
    END CASE;

    -- Calculate tax using progressive brackets
    FOR i IN 0..jsonb_array_length(tax_brackets) - 1 LOOP
        bracket_min := (tax_brackets->i->>'min')::DECIMAL;
        bracket_max := (tax_brackets->i->>'max')::DECIMAL;
        bracket_rate := (tax_brackets->i->>'rate')::DECIMAL;

        IF remaining_income > bracket_min THEN
            taxable_in_bracket := LEAST(remaining_income - bracket_min, bracket_max - bracket_min);
            tax_owed := tax_owed + (taxable_in_bracket * bracket_rate);
        END IF;
    END LOOP;

    RETURN ROUND(tax_owed, 2);
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample citizen
INSERT INTO citizens (
    national_id, first_name, last_name, date_of_birth,
    email, phone, citizen_status, voter_registration_status
) VALUES (
    '123-45-6789', 'John', 'Citizen', '1985-03-15',
    'john.citizen@email.com', '+1-555-0123', 'active', 'registered'
);

-- Insert sample government agency
INSERT INTO government_agencies (
    agency_code, agency_name, agency_type, jurisdiction_level,
    established_date, employee_count
) VALUES (
    'DHS', 'Department of Human Services', 'executive', 'state',
    '1950-01-01', 5000
);

-- Insert sample legislation
INSERT INTO legislation (
    legislation_number, title, legislation_type,
    primary_sponsor_id, legislation_status, introduced_date
) VALUES (
    'HB 1234', 'Education Funding Reform Act', 'bill',
    NULL, 'introduced', CURRENT_DATE
);

-- Insert sample public service
INSERT INTO public_services (
    service_name, service_code, service_category,
    providing_agency_id, description, eligibility_criteria
) VALUES (
    'SNAP Food Assistance', 'SNAP', 'nutrition',
    (SELECT agency_id FROM government_agencies WHERE agency_code = 'DHS' LIMIT 1),
    'Supplemental Nutrition Assistance Program',
    '{"max_income_percent_fpl": 130, "asset_limits": {"max_assets": 2500}}'::JSONB
);

-- This government schema provides comprehensive infrastructure for public services,
-- legislative tracking, tax administration, elections, and emergency management.
