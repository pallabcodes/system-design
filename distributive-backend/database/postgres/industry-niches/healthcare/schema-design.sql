-- Healthcare Database Schema Design
-- Comprehensive PostgreSQL schema for healthcare management system
-- Includes HIPAA compliance, patient management, clinical data, and administrative functions

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "ltree";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- CORE PATIENT MANAGEMENT
-- ===========================================

-- Patients table with PHI protection
CREATE TABLE patients (
    patient_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    mrn VARCHAR(20) UNIQUE NOT NULL,  -- Medical Record Number
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender CHAR(1) CHECK (gender IN ('M', 'F', 'O', 'U')),  -- M=Male, F=Female, O=Other, U=Unknown

    -- Contact Information
    email VARCHAR(255),
    phone_primary VARCHAR(20),
    phone_secondary VARCHAR(20),

    -- Address (separate table for history tracking)
    current_address_id UUID,

    -- Demographics
    race VARCHAR(50),
    ethnicity VARCHAR(50),
    preferred_language VARCHAR(10) DEFAULT 'en',
    marital_status VARCHAR(20),

    -- Emergency Contact
    emergency_contact_name VARCHAR(200),
    emergency_contact_relationship VARCHAR(50),
    emergency_contact_phone VARCHAR(20),

    -- Insurance Information
    primary_insurance_id UUID,
    secondary_insurance_id UUID,

    -- Status and Flags
    patient_status VARCHAR(20) DEFAULT 'active'
        CHECK (patient_status IN ('active', 'inactive', 'deceased', 'transferred')),
    vip_flag BOOLEAN DEFAULT FALSE,
    deceased_date DATE,
    deceased_cause TEXT,

    -- Audit Fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id),

    -- Constraints
    CHECK (deceased_date IS NULL OR patient_status = 'deceased'),
    CHECK (deceased_date IS NULL OR deceased_date >= date_of_birth)
);

-- Patient Addresses (with history)
CREATE TABLE patient_addresses (
    address_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,

    -- Address Components
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(50) DEFAULT 'USA',

    -- Address Type and Status
    address_type VARCHAR(20) DEFAULT 'home'
        CHECK (address_type IN ('home', 'work', 'temporary', 'mailing')),
    is_primary BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,

    -- Validity Period
    valid_from DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_to DATE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),

    -- Constraints
    CHECK (valid_to IS NULL OR valid_to >= valid_from),
    UNIQUE (patient_id, address_type, valid_from)  -- Prevent overlapping periods
);

-- Patient Insurance Information
CREATE TABLE patient_insurance (
    insurance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,

    -- Insurance Details
    insurance_provider_id UUID NOT NULL REFERENCES insurance_providers(provider_id),
    policy_number VARCHAR(50) NOT NULL,
    group_number VARCHAR(50),
    subscriber_id VARCHAR(50),

    -- Relationship to Subscriber
    relationship_to_subscriber VARCHAR(20) DEFAULT 'self'
        CHECK (relationship_to_subscriber IN ('self', 'spouse', 'child', 'parent', 'other')),

    -- Coverage Period
    coverage_start_date DATE NOT NULL,
    coverage_end_date DATE,

    -- Priority (primary, secondary, tertiary)
    priority INTEGER DEFAULT 1 CHECK (priority BETWEEN 1 AND 3),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Copay and Deductible Information
    copay_amount DECIMAL(8,2),
    deductible_amount DECIMAL(10,2),
    deductible_met DECIMAL(10,2) DEFAULT 0,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id),

    -- Constraints
    CHECK (coverage_end_date IS NULL OR coverage_end_date >= coverage_start_date),
    CHECK (deductible_met <= deductible_amount),
    UNIQUE (patient_id, insurance_provider_id, priority)
);

-- ===========================================
-- CLINICAL DATA MANAGEMENT
-- ===========================================

-- Encounters (visits, admissions, etc.)
CREATE TABLE encounters (
    encounter_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id),

    -- Encounter Details
    encounter_type VARCHAR(30) NOT NULL
        CHECK (encounter_type IN ('office_visit', 'hospital_admission', 'emergency', 'telemedicine', 'procedure', 'consultation')),
    encounter_status VARCHAR(20) DEFAULT 'scheduled'
        CHECK (encounter_status IN ('scheduled', 'in_progress', 'completed', 'cancelled', 'no_show')),

    -- Timing
    scheduled_start TIMESTAMP WITH TIME ZONE,
    scheduled_end TIMESTAMP WITH TIME ZONE,
    actual_start TIMESTAMP WITH TIME ZONE,
    actual_end TIMESTAMP WITH TIME ZONE,

    -- Location and Providers
    facility_id UUID REFERENCES facilities(facility_id),
    department_id UUID REFERENCES departments(department_id),
    attending_provider_id UUID REFERENCES providers(provider_id),
    supervising_provider_id UUID REFERENCES providers(provider_id),

    -- Chief Complaint and Reason
    chief_complaint TEXT,
    reason_for_visit TEXT,

    -- Vital Signs (stored as JSON for flexibility)
    vital_signs JSONB,

    -- Billing Information
    billing_status VARCHAR(20) DEFAULT 'pending'
        CHECK (billing_status IN ('pending', 'billed', 'paid', 'written_off')),
    insurance_coverage JSONB,  -- Coverage details for this encounter

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id),

    -- Constraints
    CHECK (scheduled_end IS NULL OR scheduled_end > scheduled_start),
    CHECK (actual_end IS NULL OR actual_end > actual_start)
);

-- Diagnoses (ICD-10 codes)
CREATE TABLE diagnoses (
    diagnosis_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id UUID NOT NULL REFERENCES encounters(encounter_id) ON DELETE CASCADE,

    -- Diagnosis Information
    icd10_code VARCHAR(10) NOT NULL,
    icd10_description TEXT NOT NULL,
    diagnosis_type VARCHAR(20) DEFAULT 'primary'
        CHECK (diagnosis_type IN ('primary', 'secondary', 'complication', 'comorbidity')),

    -- Provider and Timing
    diagnosing_provider_id UUID REFERENCES providers(provider_id),
    diagnosis_date DATE DEFAULT CURRENT_DATE,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    resolved_date DATE,

    -- Clinical Notes
    clinical_notes TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),

    -- Constraints
    CHECK (resolved_date IS NULL OR resolved_date >= diagnosis_date),
    FOREIGN KEY (icd10_code) REFERENCES icd10_codes(code)
);

-- Procedures and Treatments
CREATE TABLE procedures (
    procedure_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id UUID NOT NULL REFERENCES encounters(encounter_id) ON DELETE CASCADE,

    -- Procedure Information
    cpt_code VARCHAR(10) NOT NULL,
    cpt_description TEXT NOT NULL,
    procedure_category VARCHAR(50),

    -- Timing and Duration
    procedure_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    procedure_duration_minutes INTEGER,

    -- Providers
    performing_provider_id UUID REFERENCES providers(provider_id),
    assisting_provider_id UUID REFERENCES providers(provider_id),

    -- Procedure Details
    procedure_notes TEXT,
    complications TEXT,
    outcome VARCHAR(50),

    -- Status
    procedure_status VARCHAR(20) DEFAULT 'completed'
        CHECK (procedure_status IN ('scheduled', 'in_progress', 'completed', 'cancelled', 'aborted')),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id),

    -- Constraints
    FOREIGN KEY (cpt_code) REFERENCES cpt_codes(code)
);

-- Medications and Prescriptions
CREATE TABLE prescriptions (
    prescription_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id),
    encounter_id UUID REFERENCES encounters(encounter_id),

    -- Medication Details
    medication_id UUID NOT NULL REFERENCES medications(medication_id),
    dosage VARCHAR(100) NOT NULL,
    frequency VARCHAR(100) NOT NULL,
    duration_days INTEGER,

    -- Prescription Details
    prescribed_by UUID NOT NULL REFERENCES providers(provider_id),
    prescribed_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    start_date DATE DEFAULT CURRENT_DATE,
    end_date DATE,

    -- Instructions
    instructions TEXT,
    indications TEXT,
    side_effects TEXT,

    -- Status and Refills
    prescription_status VARCHAR(20) DEFAULT 'active'
        CHECK (prescription_status IN ('active', 'completed', 'discontinued', 'expired')),
    refills_allowed INTEGER DEFAULT 0,
    refills_used INTEGER DEFAULT 0,

    -- Pharmacy Information
    pharmacy_id UUID REFERENCES pharmacies(pharmacy_id),
    filled_date DATE,
    filled_by VARCHAR(100),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id),

    -- Constraints
    CHECK (end_date IS NULL OR end_date >= start_date),
    CHECK (refills_used <= refills_allowed)
);

-- Lab Results and Imaging
CREATE TABLE lab_results (
    result_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id),
    encounter_id UUID REFERENCES encounters(encounter_id),

    -- Test Information
    test_code VARCHAR(20) NOT NULL,
    test_name VARCHAR(200) NOT NULL,
    test_category VARCHAR(50),

    -- Ordering Information
    ordered_by UUID REFERENCES providers(provider_id),
    ordered_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    collected_date TIMESTAMP WITH TIME ZONE,
    received_date TIMESTAMP WITH TIME ZONE,
    resulted_date TIMESTAMP WITH TIME ZONE,

    -- Results
    result_value VARCHAR(100),
    result_unit VARCHAR(20),
    reference_range VARCHAR(50),
    interpretation VARCHAR(20) CHECK (interpretation IN ('normal', 'abnormal', 'critical', 'pending')),
    notes TEXT,

    -- Status
    status VARCHAR(20) DEFAULT 'pending'
        CHECK (status IN ('pending', 'collected', 'received', 'resulted', 'reviewed', 'final')),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    reviewed_by UUID REFERENCES users(user_id),

    -- Constraints
    FOREIGN KEY (test_code) REFERENCES lab_tests(test_code)
);

-- ===========================================
-- MEDICATION MANAGEMENT
-- ===========================================

-- Medication Dictionary
CREATE TABLE medications (
    medication_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    drug_name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255),
    brand_name VARCHAR(255),

    -- Drug Classification
    drug_class VARCHAR(100),
    therapeutic_class VARCHAR(100),

    -- Strength and Form
    strength VARCHAR(50),
    form VARCHAR(50),  -- tablet, capsule, injection, etc.

    -- Regulatory Information
    ndc_code VARCHAR(20) UNIQUE,  -- National Drug Code
    rxnorm_cui VARCHAR(20),       -- RxNorm Concept Unique Identifier

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    controlled_substance BOOLEAN DEFAULT FALSE,
    controlled_substance_class VARCHAR(10),  -- I, II, III, IV, V

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Drug Interactions and Allergies
CREATE TABLE drug_interactions (
    interaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    drug1_id UUID NOT NULL REFERENCES medications(medication_id),
    drug2_id UUID NOT NULL REFERENCES medications(medication_id),

    -- Interaction Details
    interaction_type VARCHAR(20) NOT NULL
        CHECK (interaction_type IN ('major', 'moderate', 'minor', 'unknown')),
    description TEXT NOT NULL,
    clinical_consequences TEXT,

    -- Severity and Management
    severity VARCHAR(10) CHECK (severity IN ('high', 'medium', 'low')),
    management_guidance TEXT,

    -- Source
    data_source VARCHAR(50),  -- e.g., 'FDA', 'Lexicomp', etc.
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (drug1_id, drug2_id)
);

-- Patient Allergies
CREATE TABLE patient_allergies (
    allergy_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,

    -- Allergy Information
    allergen_type VARCHAR(30) NOT NULL
        CHECK (allergen_type IN ('drug', 'food', 'environmental', 'other')),
    allergen_name VARCHAR(255) NOT NULL,

    -- Reaction Details
    reaction_severity VARCHAR(20)
        CHECK (reaction_severity IN ('mild', 'moderate', 'severe', 'life_threatening')),
    reaction_description TEXT,
    onset_date DATE,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    confirmed_by UUID REFERENCES providers(provider_id),
    confirmed_date DATE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id)
);

-- ===========================================
-- PROVIDER AND STAFF MANAGEMENT
-- ===========================================

-- Healthcare Providers
CREATE TABLE providers (
    provider_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    npi VARCHAR(10) UNIQUE,  -- National Provider Identifier

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    credentials VARCHAR(50),  -- MD, DO, RN, PA, etc.

    -- Professional Information
    specialty VARCHAR(100),
    license_number VARCHAR(50),
    license_state VARCHAR(2),
    license_expiration DATE,

    -- Employment
    department_id UUID REFERENCES departments(department_id),
    employment_status VARCHAR(20) DEFAULT 'active'
        CHECK (employment_status IN ('active', 'inactive', 'terminated', 'retired')),

    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(20),

    -- System Access
    user_id UUID REFERENCES users(user_id),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (license_expiration > CURRENT_DATE)
);

-- Departments and Facilities
CREATE TABLE facilities (
    facility_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_name VARCHAR(255) NOT NULL,
    facility_type VARCHAR(50) NOT NULL
        CHECK (facility_type IN ('hospital', 'clinic', 'urgent_care', 'nursing_home', 'pharmacy')),

    -- Address
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,

    -- Contact
    phone VARCHAR(20),
    email VARCHAR(255),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE departments (
    department_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(facility_id),
    department_name VARCHAR(100) NOT NULL,
    department_type VARCHAR(50)
        CHECK (department_type IN ('emergency', 'cardiology', 'oncology', 'pediatrics', 'surgery', 'radiology', 'laboratory', 'pharmacy', 'administration')),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (facility_id, department_name)
);

-- ===========================================
-- BILLING AND INSURANCE
-- ===========================================

-- Insurance Providers
CREATE TABLE insurance_providers (
    provider_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_name VARCHAR(255) NOT NULL,
    payer_id VARCHAR(50) UNIQUE,  -- Standard insurance payer ID

    -- Contact Information
    address_line_1 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(50),
    postal_code VARCHAR(20),
    phone VARCHAR(20),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Claims and Billing
CREATE TABLE claims (
    claim_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id),
    encounter_id UUID REFERENCES encounters(encounter_id),

    -- Claim Information
    claim_number VARCHAR(50) UNIQUE NOT NULL,
    claim_type VARCHAR(20) DEFAULT 'professional'
        CHECK (claim_type IN ('professional', 'institutional', 'dental', 'pharmacy')),

    -- Insurance Information
    insurance_id UUID NOT NULL REFERENCES patient_insurance(insurance_id),
    payer_id VARCHAR(50),

    -- Dates
    service_start_date DATE NOT NULL,
    service_end_date DATE,
    submission_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Financial Information
    billed_amount DECIMAL(10,2) NOT NULL,
    allowed_amount DECIMAL(10,2),
    paid_amount DECIMAL(10,2) DEFAULT 0,
    patient_responsibility DECIMAL(10,2) DEFAULT 0,
    adjustments DECIMAL(10,2) DEFAULT 0,

    -- Status
    claim_status VARCHAR(30) DEFAULT 'submitted'
        CHECK (claim_status IN ('submitted', 'received', 'processing', 'approved', 'denied', 'paid', 'appealed', 'closed')),

    -- Denial Information
    denial_code VARCHAR(10),
    denial_reason TEXT,

    -- Processing Information
    processed_date TIMESTAMP WITH TIME ZONE,
    payment_date TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id),

    -- Constraints
    CHECK (service_end_date IS NULL OR service_end_date >= service_start_date),
    CHECK (paid_amount <= billed_amount)
);

-- ===========================================
-- CLINICAL DOCUMENTATION
-- ===========================================

-- Clinical Notes and Documentation
CREATE TABLE clinical_notes (
    note_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id),
    encounter_id UUID REFERENCES encounters(encounter_id),

    -- Note Information
    note_type VARCHAR(50) NOT NULL
        CHECK (note_type IN ('progress_note', 'consultation', 'procedure_note', 'discharge_summary', 'history_physical', 'soap_note')),
    note_title VARCHAR(255),

    -- Content
    note_content TEXT NOT NULL,
    note_summary TEXT,

    -- Author and Review
    author_id UUID NOT NULL REFERENCES providers(provider_id),
    authored_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_modified TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Review and Approval
    reviewed_by UUID REFERENCES providers(provider_id),
    reviewed_date TIMESTAMP WITH TIME ZONE,
    approved_by UUID REFERENCES providers(provider_id),
    approved_date TIMESTAMP WITH TIME ZONE,

    -- Status
    note_status VARCHAR(20) DEFAULT 'draft'
        CHECK (note_status IN ('draft', 'final', 'amended', 'deleted')),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id),

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', note_content)) STORED
);

-- Document Management
CREATE TABLE clinical_documents (
    document_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id),
    encounter_id UUID REFERENCES encounters(encounter_id),

    -- Document Information
    document_type VARCHAR(50) NOT NULL
        CHECK (document_type IN ('lab_result', 'imaging', 'ekg', 'pathology', 'consent_form', 'advance_directive', 'other')),
    document_title VARCHAR(255) NOT NULL,

    -- File Storage
    file_path VARCHAR(500),
    file_name VARCHAR(255),
    mime_type VARCHAR(100),
    file_size_bytes INTEGER,

    -- Document Content (for small documents or extracted text)
    document_content TEXT,

    -- Metadata
    document_date DATE DEFAULT CURRENT_DATE,
    expiration_date DATE,
    is_confidential BOOLEAN DEFAULT FALSE,

    -- Provider Information
    uploaded_by UUID REFERENCES providers(provider_id),
    reviewed_by UUID REFERENCES providers(provider_id),

    -- Status
    document_status VARCHAR(20) DEFAULT 'active'
        CHECK (document_status IN ('active', 'archived', 'deleted')),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search for OCR'd content
    content_vector TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', COALESCE(document_content, ''))) STORED
);

-- ===========================================
-- QUALITY AND COMPLIANCE
-- ===========================================

-- Quality Measures
CREATE TABLE quality_measures (
    measure_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id),

    -- Measure Information
    measure_type VARCHAR(100) NOT NULL,  -- e.g., 'HbA1c', 'Blood Pressure', 'BMI'
    measure_code VARCHAR(20),  -- Standardized code (LOINC, SNOMED)
    measure_value DECIMAL(8,2),
    measure_unit VARCHAR(20),

    -- Measurement Details
    measured_date DATE NOT NULL,
    measured_by UUID REFERENCES providers(provider_id),
    measurement_method VARCHAR(50),

    -- Reference Ranges
    normal_range_low DECIMAL(8,2),
    normal_range_high DECIMAL(8,2),
    is_normal BOOLEAN GENERATED ALWAYS AS (
        measure_value >= normal_range_low AND measure_value <= normal_range_high
    ) STORED,

    -- Quality Program
    quality_program VARCHAR(50),  -- e.g., 'Meaningful Use', 'PQRS', 'MIPS'

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id)
);

-- Compliance Tracking
CREATE TABLE compliance_events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID REFERENCES patients(patient_id),
    provider_id UUID REFERENCES providers(provider_id),

    -- Event Information
    event_type VARCHAR(50) NOT NULL
        CHECK (event_type IN ('hipaa_breach', 'medication_error', 'protocol_deviation', 'consent_violation', 'documentation_error')),
    event_severity VARCHAR(20) DEFAULT 'minor'
        CHECK (event_severity IN ('minor', 'moderate', 'major', 'critical')),

    -- Event Details
    event_description TEXT NOT NULL,
    event_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    reported_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Resolution
    resolution_status VARCHAR(20) DEFAULT 'open'
        CHECK (resolution_status IN ('open', 'investigating', 'resolved', 'closed')),
    resolution_description TEXT,
    resolved_date TIMESTAMP WITH TIME ZONE,

    -- Regulatory Reporting
    reported_to_regulator BOOLEAN DEFAULT FALSE,
    regulator_reference_number VARCHAR(50),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Core patient indexes
CREATE INDEX idx_patients_mrn ON patients (mrn);
CREATE INDEX idx_patients_name ON patients (last_name, first_name);
CREATE INDEX idx_patients_dob ON patients (date_of_birth);
CREATE INDEX idx_patients_status ON patients (patient_status);

-- Encounter indexes
CREATE INDEX idx_encounters_patient ON encounters (patient_id);
CREATE INDEX idx_encounters_date ON encounters (scheduled_start, scheduled_end);
CREATE INDEX idx_encounters_provider ON encounters (attending_provider_id);
CREATE INDEX idx_encounters_status ON encounters (encounter_status);

-- Diagnosis indexes
CREATE INDEX idx_diagnoses_encounter ON diagnoses (encounter_id);
CREATE INDEX idx_diagnoses_patient ON diagnoses (patient_id);
CREATE INDEX idx_diagnoses_icd10 ON diagnoses (icd10_code);
CREATE INDEX idx_diagnoses_active ON diagnoses (patient_id, is_active) WHERE is_active = true;

-- Prescription indexes
CREATE INDEX idx_prescriptions_patient ON prescriptions (patient_id);
CREATE INDEX idx_prescriptions_medication ON prescriptions (medication_id);
CREATE INDEX idx_prescriptions_status ON prescriptions (prescription_status);

-- Lab results indexes
CREATE INDEX idx_lab_results_patient ON lab_results (patient_id);
CREATE INDEX idx_lab_results_encounter ON lab_results (encounter_id);
CREATE INDEX idx_lab_results_test ON lab_results (test_code);
CREATE INDEX idx_lab_results_date ON lab_results (resulted_date);

-- Clinical notes full-text search
CREATE INDEX idx_clinical_notes_search ON clinical_notes USING gin (search_vector);
CREATE INDEX idx_clinical_notes_patient ON clinical_notes (patient_id);
CREATE INDEX idx_clinical_notes_encounter ON clinical_notes (encounter_id);

-- Claims indexes
CREATE INDEX idx_claims_patient ON claims (patient_id);
CREATE INDEX idx_claims_encounter ON claims (encounter_id);
CREATE INDEX idx_claims_status ON claims (claim_status);
CREATE INDEX idx_claims_dates ON claims (service_start_date, service_end_date);

-- ===========================================
-- REFERENCE DATA TABLES
-- ===========================================

-- ICD-10 Codes
CREATE TABLE icd10_codes (
    code VARCHAR(10) PRIMARY KEY,
    description TEXT NOT NULL,
    category VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- CPT Codes
CREATE TABLE cpt_codes (
    code VARCHAR(10) PRIMARY KEY,
    description TEXT NOT NULL,
    category VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Lab Tests
CREATE TABLE lab_tests (
    test_code VARCHAR(20) PRIMARY KEY,
    test_name VARCHAR(200) NOT NULL,
    test_category VARCHAR(50),
    loinc_code VARCHAR(20),
    normal_range TEXT,
    units VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Pharmacies
CREATE TABLE pharmacies (
    pharmacy_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_name VARCHAR(255) NOT NULL,
    npi VARCHAR(10),
    address_line_1 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(50),
    postal_code VARCHAR(20),
    phone VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- USERS AND PERMISSIONS
-- ===========================================

-- System Users (extends the general users table concept)
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(200) NOT NULL,

    -- Role and Permissions
    user_role VARCHAR(30) NOT NULL
        CHECK (user_role IN ('admin', 'provider', 'nurse', 'staff', 'patient', 'billing')),
    department_id UUID REFERENCES departments(department_id),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP WITH TIME ZONE,
    password_changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Security
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id)
);

-- ===========================================
-- AUDIT AND COMPLIANCE TABLES
-- ===========================================

-- Comprehensive audit trail
CREATE TABLE audit_log (
    audit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    changed_by UUID REFERENCES users(user_id),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    client_ip INET,
    user_agent TEXT
) PARTITION BY RANGE (changed_at);

-- PHI access log (HIPAA requirement)
CREATE TABLE phi_access_log (
    access_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    patient_id UUID NOT NULL REFERENCES patients(patient_id),
    table_name VARCHAR(100),
    record_id UUID,
    access_type VARCHAR(20) NOT NULL
        CHECK (access_type IN ('read', 'write', 'delete', 'export')),
    purpose_of_use VARCHAR(100),  -- HIPAA required
    accessed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    client_ip INET,
    success BOOLEAN DEFAULT TRUE,
    error_message TEXT
);

-- ===========================================
-- PARTITIONING SETUP
-- ===========================================

-- Create monthly partitions for audit logs
CREATE TABLE audit_log_2024_01 PARTITION OF audit_log
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE audit_log_2024_02 PARTITION OF audit_log
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- Function to create future partitions
CREATE OR REPLACE FUNCTION create_audit_partition(target_date DATE)
RETURNS VOID AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    start_date := date_trunc('month', target_date);
    end_date := start_date + INTERVAL '1 month';
    partition_name := 'audit_log_' || to_char(start_date, 'YYYY_MM');

    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_log
        FOR VALUES FROM (%L) TO (%L)',
        partition_name, start_date, end_date
    );
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- ROW LEVEL SECURITY POLICIES
-- ===========================================

-- Enable RLS on sensitive tables
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE encounters ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinical_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY;

-- Patient data access policy
CREATE POLICY patient_data_policy ON patients
    FOR ALL
    USING (
        current_setting('app.user_role') IN ('admin', 'provider', 'nurse') OR
        patient_id::TEXT = current_setting('app.current_patient_id')
    );

-- Provider access to assigned patients
CREATE POLICY provider_patient_access ON encounters
    FOR ALL
    USING (
        attending_provider_id::TEXT = current_setting('app.current_user_id') OR
        current_setting('app.user_role') = 'admin'
    );

-- Department-based access for clinical notes
CREATE POLICY clinical_notes_access ON clinical_notes
    FOR ALL
    USING (
        author_id::TEXT = current_setting('app.current_user_id') OR
        EXISTS (
            SELECT 1 FROM providers p
            WHERE p.provider_id = clinical_notes.author_id
              AND p.department_id::TEXT = current_setting('app.user_department_id')
        ) OR
        current_setting('app.user_role') = 'admin'
    );

-- ===========================================
-- TRIGGERS FOR AUDIT AND INTEGRITY
-- ===========================================

-- Generic audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    audit_record audit_log%ROWTYPE;
BEGIN
    audit_record.table_name := TG_TABLE_NAME;
    audit_record.operation := TG_OP;
    audit_record.old_values := CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::JSONB ELSE NULL END;
    audit_record.new_values := CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::JSONB ELSE NULL END;
    audit_record.changed_by := current_setting('app.current_user_id', TRUE)::UUID;
    audit_record.changed_at := CURRENT_TIMESTAMP;
    audit_record.client_ip := inet_client_addr();
    audit_record.record_id := COALESCE(NEW.id, OLD.id);

    INSERT INTO audit_log VALUES (audit_record.*);
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Apply audit triggers to sensitive tables
CREATE TRIGGER audit_patients AFTER INSERT OR UPDATE OR DELETE ON patients
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_encounters AFTER INSERT OR UPDATE OR DELETE ON encounters
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- PHI access logging trigger
CREATE OR REPLACE FUNCTION log_phi_access()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO phi_access_log (
        user_id, patient_id, table_name, record_id, access_type
    ) VALUES (
        current_setting('app.current_user_id')::UUID,
        COALESCE(NEW.patient_id, OLD.patient_id),
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        CASE TG_OP
            WHEN 'INSERT' THEN 'write'
            WHEN 'UPDATE' THEN 'write'
            WHEN 'DELETE' THEN 'delete'
            ELSE 'read'
        END
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER phi_access_trigger AFTER INSERT OR UPDATE OR DELETE ON patients
    FOR EACH ROW EXECUTE FUNCTION log_phi_access();

-- Update timestamps trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    NEW.updated_by = current_setting('app.current_user_id', TRUE)::UUID;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_patients_updated_at BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Patient summary view
CREATE VIEW patient_summary AS
SELECT
    p.patient_id,
    p.mrn,
    p.first_name || ' ' || p.last_name AS full_name,
    p.date_of_birth,
    EXTRACT(YEAR FROM AGE(p.date_of_birth)) AS age,
    p.gender,
    p.patient_status,
    pa.address_line_1 || ', ' || pa.city || ', ' || pa.state_province || ' ' || pa.postal_code AS address,
    p.phone_primary,
    p.email,
    (
        SELECT COUNT(*) FROM encounters e
        WHERE e.patient_id = p.patient_id AND e.encounter_status = 'completed'
    ) AS total_encounters,
    (
        SELECT MAX(e.actual_start) FROM encounters e
        WHERE e.patient_id = p.patient_id AND e.encounter_status = 'completed'
    ) AS last_visit_date
FROM patients p
LEFT JOIN patient_addresses pa ON p.current_address_id = pa.address_id AND pa.is_active = true;

-- Active prescriptions view
CREATE VIEW active_prescriptions AS
SELECT
    pr.prescription_id,
    pr.patient_id,
    m.drug_name,
    m.brand_name,
    pr.dosage,
    pr.frequency,
    pr.start_date,
    pr.end_date,
    pr.prescribed_date,
    p.first_name || ' ' || p.last_name AS patient_name,
    prov.first_name || ' ' || prov.last_name AS prescribing_provider,
    pr.prescription_status,
    pr.refills_used || '/' || pr.refills_allowed AS refills
FROM prescriptions pr
JOIN patients p ON pr.patient_id = p.patient_id
JOIN medications m ON pr.medication_id = m.medication_id
JOIN providers prov ON pr.prescribed_by = prov.provider_id
WHERE pr.prescription_status = 'active'
  AND (pr.end_date IS NULL OR pr.end_date >= CURRENT_DATE);

-- Encounter summary view
CREATE VIEW encounter_summary AS
SELECT
    e.encounter_id,
    e.patient_id,
    p.first_name || ' ' || p.last_name AS patient_name,
    e.encounter_type,
    e.encounter_status,
    e.scheduled_start,
    e.actual_start,
    e.actual_end,
    f.facility_name,
    d.department_name,
    prov.first_name || ' ' || prov.last_name AS provider_name,
    e.chief_complaint,
    (
        SELECT STRING_AGG(dg.icd10_description, '; ')
        FROM diagnoses dg
        WHERE dg.encounter_id = e.encounter_id AND dg.is_active = true
    ) AS diagnoses
FROM encounters e
JOIN patients p ON e.patient_id = p.patient_id
LEFT JOIN facilities f ON e.facility_id = f.facility_id
LEFT JOIN departments d ON e.department_id = d.department_id
LEFT JOIN providers prov ON e.attending_provider_id = prov.provider_id;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample facility
INSERT INTO facilities (facility_name, facility_type, address_line_1, city, state_province, postal_code, phone)
VALUES ('General Hospital', 'hospital', '123 Medical Center Dr', 'Anytown', 'CA', '12345', '555-0123');

-- Insert sample department
INSERT INTO departments (facility_id, department_name, department_type)
SELECT facility_id, 'Emergency Department', 'emergency'
FROM facilities WHERE facility_name = 'General Hospital';

-- Insert sample provider
INSERT INTO providers (npi, first_name, last_name, credentials, specialty, department_id)
SELECT '1234567890', 'John', 'Smith', 'MD', 'Emergency Medicine', department_id
FROM departments WHERE department_name = 'Emergency Department';

-- Insert sample patient
INSERT INTO patients (mrn, first_name, last_name, date_of_birth, gender, phone_primary, email)
VALUES ('MRN001', 'Jane', 'Doe', '1985-03-15', 'F', '555-0456', 'jane.doe@email.com');

-- This schema provides a comprehensive foundation for a healthcare information system
-- with proper indexing, security, audit trails, and compliance features.
