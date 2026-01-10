-- Insurance Management Database Schema
-- Comprehensive schema for insurance operations including underwriting, claims, and policy management

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- ===========================================
-- POLICYHOLDERS AND INSUREDS
-- ===========================================

CREATE TABLE policyholders (
    policyholder_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type VARCHAR(20) NOT NULL CHECK (entity_type IN ('individual', 'business', 'organization')),

    -- Contact Information
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),
    fax VARCHAR(20),

    -- Address Information
    mailing_address JSONB,
    billing_address JSONB,

    -- Status and Classification
    policyholder_status VARCHAR(20) DEFAULT 'active' CHECK (policyholder_status IN ('active', 'inactive', 'suspended', 'terminated')),
    risk_classification VARCHAR(20) DEFAULT 'standard' CHECK (risk_classification IN ('preferred', 'standard', 'substandard', 'declined')),

    -- Financial Information
    credit_score INTEGER,
    payment_history_rating VARCHAR(10) CHECK (payment_history_rating IN ('excellent', 'good', 'fair', 'poor')),

    -- Marketing and Preferences
    marketing_consent BOOLEAN DEFAULT FALSE,
    communication_preferences JSONB DEFAULT '{"email": true, "sms": false, "mail": true}',

    -- Regulatory Compliance
    kyc_status VARCHAR(20) DEFAULT 'pending' CHECK (kyc_status IN ('pending', 'approved', 'rejected')),
    pep_status BOOLEAN DEFAULT FALSE, -- Politically Exposed Person

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID
);

-- Individual policyholders
CREATE TABLE individual_policyholders (
    policyholder_id UUID PRIMARY KEY REFERENCES policyholders(policyholder_id) ON DELETE CASCADE,

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(20),
    marital_status VARCHAR(20) CHECK (marital_status IN ('single', 'married', 'divorced', 'widowed')),

    -- Identification
    ssn_encrypted BYTEA, -- Encrypted SSN
    drivers_license VARCHAR(50),
    passport_number VARCHAR(50),

    -- Employment and Income
    employment_status VARCHAR(30) CHECK (employment_status IN ('employed', 'self_employed', 'unemployed', 'student', 'retired', 'homemaker')),
    employer_name VARCHAR(255),
    occupation VARCHAR(100),
    annual_income DECIMAL(15,2),

    -- Health Information (for health insurance)
    height_inches INTEGER,
    weight_pounds INTEGER,
    tobacco_use BOOLEAN DEFAULT FALSE,
    medical_conditions TEXT[],

    -- Family Information
    spouse_id UUID REFERENCES individual_policyholders(policyholder_id),
    dependents JSONB DEFAULT '[]', -- Array of dependent information

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Business policyholders
CREATE TABLE business_policyholders (
    policyholder_id UUID PRIMARY KEY REFERENCES policyholders(policyholder_id) ON DELETE CASCADE,

    -- Business Information
    business_name VARCHAR(255) NOT NULL,
    legal_business_name VARCHAR(255),
    business_type VARCHAR(50) CHECK (business_type IN ('corporation', 'llc', 'partnership', 'sole_proprietorship', 'non_profit')),

    -- Registration
    ein VARCHAR(20) UNIQUE, -- Employer Identification Number
    state_of_incorporation VARCHAR(50),
    date_of_incorporation DATE,

    -- Business Details
    industry VARCHAR(100),
    business_description TEXT,
    number_of_employees INTEGER,
    annual_revenue DECIMAL(15,2),

    -- Contact Information
    primary_contact_name VARCHAR(200),
    primary_contact_title VARCHAR(100),

    -- Risk Factors
    business_age_years INTEGER,
    claims_history TEXT,
    safety_programs JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INSURANCE PRODUCTS AND POLICIES
-- ===========================================

CREATE TABLE insurance_products (
    product_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Product Information
    product_name VARCHAR(255) NOT NULL,
    product_code VARCHAR(20) UNIQUE NOT NULL,
    product_type VARCHAR(30) NOT NULL CHECK (product_type IN (
        'auto', 'home', 'life', 'health', 'disability', 'liability',
        'workers_compensation', 'property', 'cyber', 'flood', 'earthquake'
    )),
    product_category VARCHAR(20) CHECK (product_category IN ('personal', 'commercial', 'group', 'specialty')),

    -- Product Details
    description TEXT,
    coverage_details JSONB, -- Detailed coverage information
    exclusions TEXT,
    conditions TEXT,

    -- Pricing and Limits
    base_premium DECIMAL(10,2),
    minimum_premium DECIMAL(10,2),
    maximum_coverage DECIMAL(15,2),
    deductible_options JSONB DEFAULT '[]',

    -- Underwriting Rules
    underwriting_requirements JSONB DEFAULT '{}',
    risk_factors JSONB DEFAULT '{}',

    -- Status
    product_status VARCHAR(20) DEFAULT 'active' CHECK (product_status IN ('active', 'inactive', 'discontinued')),

    -- Regulatory
    state_approvals TEXT[], -- Array of approved states
    filing_status VARCHAR(20) DEFAULT 'filed' CHECK (filing_status IN ('draft', 'filed', 'approved', 'rejected')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE policies (
    policy_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    policy_number VARCHAR(30) UNIQUE NOT NULL,

    -- Relationships
    policyholder_id UUID NOT NULL REFERENCES policyholders(policyholder_id),
    product_id UUID NOT NULL REFERENCES insurance_products(product_id),

    -- Policy Details
    policy_type VARCHAR(20) DEFAULT 'individual' CHECK (policy_type IN ('individual', 'group', 'family', 'business')),
    policy_status VARCHAR(20) DEFAULT 'active' CHECK (policy_status IN (
        'quote', 'application', 'underwriting', 'approved', 'issued',
        'active', 'cancelled', 'expired', 'lapsed', 'surrendered'
    )),

    -- Coverage Information
    coverage_amount DECIMAL(15,2),
    deductible DECIMAL(10,2),
    coverage_limits JSONB DEFAULT '{}', -- Specific limits for different coverage types

    -- Premium Information
    premium_amount DECIMAL(10,2),
    premium_frequency VARCHAR(20) DEFAULT 'monthly' CHECK (premium_frequency IN ('annual', 'semi_annual', 'quarterly', 'monthly')),
    payment_method VARCHAR(30) CHECK (payment_method IN ('credit_card', 'ach', 'check', 'wire', 'cash')),

    -- Policy Period
    effective_date DATE NOT NULL,
    expiration_date DATE NOT NULL,
    renewal_date DATE,

    -- Underwriting
    underwriting_class VARCHAR(20),
    risk_score DECIMAL(5,2),
    special_conditions TEXT,

    -- Agent and Servicing
    agent_id UUID, -- References agents table
    underwriter_id UUID, -- References underwriters table
    service_team_id UUID,

    -- Financial Tracking
    total_premium_paid DECIMAL(12,2) DEFAULT 0,
    outstanding_balance DECIMAL(10,2) DEFAULT 0,
    cancellation_date DATE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    issued_at TIMESTAMP WITH TIME ZONE,

    CHECK (effective_date < expiration_date),
    CHECK (coverage_amount > 0),
    CHECK (premium_amount >= 0)
);

-- Policy coverage details
CREATE TABLE policy_coverages (
    coverage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    policy_id UUID NOT NULL REFERENCES policies(policy_id) ON DELETE CASCADE,

    -- Coverage Details
    coverage_type VARCHAR(50) NOT NULL,
    coverage_description TEXT,
    coverage_limit DECIMAL(15,2),
    deductible DECIMAL(10,2),
    premium DECIMAL(8,2),

    -- Status
    coverage_status VARCHAR(20) DEFAULT 'active' CHECK (coverage_status IN ('active', 'inactive', 'excluded')),

    -- Additional Details
    coverage_details JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (policy_id, coverage_type)
);

-- ===========================================
-- CLAIMS MANAGEMENT
-- ===========================================

CREATE TABLE claims (
    claim_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    claim_number VARCHAR(30) UNIQUE NOT NULL,

    -- Relationships
    policy_id UUID NOT NULL REFERENCES policies(policy_id),
    policyholder_id UUID NOT NULL REFERENCES policyholders(policyholder_id),

    -- Claim Details
    claim_type VARCHAR(30) NOT NULL CHECK (claim_type IN (
        'auto_accident', 'property_damage', 'theft', 'medical', 'disability',
        'liability', 'workers_compensation', 'life', 'critical_illness'
    )),
    incident_date DATE NOT NULL,
    reported_date DATE DEFAULT CURRENT_DATE,
    loss_date DATE,

    -- Incident Information
    incident_description TEXT,
    incident_location JSONB, -- Address and coordinates
    weather_conditions TEXT,
    police_report_number VARCHAR(50),

    -- Financial Information
    estimated_loss DECIMAL(15,2),
    claimed_amount DECIMAL(15,2),
    approved_amount DECIMAL(15,2),
    paid_amount DECIMAL(15,2) DEFAULT 0,

    -- Claim Status
    claim_status VARCHAR(30) DEFAULT 'reported' CHECK (claim_status IN (
        'reported', 'investigating', 'pending_approval', 'approved',
        'denied', 'paid', 'closed', 'appealed', 'reopened'
    )),

    -- Assignment and Processing
    assigned_adjuster_id UUID, -- References adjusters table
    supervisor_id UUID,
    fraud_score DECIMAL(5,2), -- Fraud detection score

    -- Timeline
    investigation_start_date DATE,
    approval_date DATE,
    payment_date DATE,
    closed_date DATE,

    -- Additional Details
    cause_of_loss VARCHAR(100),
    subrogation_possible BOOLEAN DEFAULT FALSE,
    litigation_pending BOOLEAN DEFAULT FALSE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID,

    CHECK (incident_date <= reported_date),
    CHECK (estimated_loss >= 0),
    CHECK (claimed_amount >= 0),
    CHECK (approved_amount >= 0),
    CHECK (paid_amount >= 0)
);

-- Claim payments
CREATE TABLE claim_payments (
    payment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    claim_id UUID NOT NULL REFERENCES claims(claim_id) ON DELETE CASCADE,

    -- Payment Details
    payment_amount DECIMAL(12,2) NOT NULL,
    payment_date DATE DEFAULT CURRENT_DATE,
    payment_type VARCHAR(30) CHECK (payment_type IN ('partial', 'final', 'advance', 'supplemental')),

    -- Payment Method
    payment_method VARCHAR(30) CHECK (payment_method IN ('check', 'direct_deposit', 'wire', 'credit_card')),
    payment_reference VARCHAR(100), -- Check number, transaction ID, etc.

    -- Recipient Information
    payee_name VARCHAR(255),
    payee_address JSONB,

    -- Approval and Processing
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    processed_by UUID,
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Additional Details
    payment_notes TEXT,
    tax_withheld DECIMAL(8,2) DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (payment_amount > 0)
);

-- Claim documents and evidence
CREATE TABLE claim_documents (
    document_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    claim_id UUID NOT NULL REFERENCES claims(claim_id) ON DELETE CASCADE,

    -- Document Information
    document_type VARCHAR(50) CHECK (document_type IN (
        'police_report', 'medical_report', 'repair_estimate', 'photos',
        'witness_statement', 'invoice', 'receipt', 'correspondence'
    )),
    document_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500),
    file_size_bytes BIGINT,

    -- Metadata
    uploaded_by UUID,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    document_date DATE,

    -- Content and Classification
    document_summary TEXT,
    confidential BOOLEAN DEFAULT FALSE,

    -- Processing Status
    ocr_processed BOOLEAN DEFAULT FALSE,
    ocr_text TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- UNDERWRITING AND RISK ASSESSMENT
-- ===========================================

CREATE TABLE underwriting_applications (
    application_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    policyholder_id UUID NOT NULL REFERENCES policyholders(policyholder_id),

    -- Application Details
    product_id UUID NOT NULL REFERENCES insurance_products(product_id),
    application_status VARCHAR(20) DEFAULT 'draft' CHECK (application_status IN (
        'draft', 'submitted', 'under_review', 'approved', 'declined', 'withdrawn'
    )),

    -- Application Data
    application_data JSONB NOT NULL, -- Complete application form data
    risk_assessment JSONB DEFAULT '{}',

    -- Processing
    submitted_at TIMESTAMP WITH TIME ZONE,
    assigned_underwriter_id UUID,
    review_started_at TIMESTAMP WITH TIME ZONE,
    decision_date DATE,

    -- Decision Details
    decision VARCHAR(20) CHECK (decision IN ('approved', 'declined', 'referred', 'conditional')),
    decline_reason VARCHAR(100),
    conditions TEXT,

    -- Pricing
    quoted_premium DECIMAL(10,2),
    final_premium DECIMAL(10,2),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

-- Risk assessment scores
CREATE TABLE risk_assessments (
    assessment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    policyholder_id UUID NOT NULL REFERENCES policyholders(policyholder_id),
    application_id UUID REFERENCES underwriting_applications(application_id),

    -- Assessment Details
    assessment_type VARCHAR(50) CHECK (assessment_type IN (
        'credit_score', 'driving_record', 'medical_history',
        'business_risk', 'property_inspection', 'criminal_background'
    )),
    assessment_date DATE DEFAULT CURRENT_DATE,

    -- Scoring
    risk_score DECIMAL(5,2),
    risk_rating VARCHAR(20) CHECK (risk_rating IN ('very_low', 'low', 'moderate', 'high', 'very_high')),
    confidence_level DECIMAL(5,2),

    -- Assessment Data
    assessment_details JSONB,
    assessor_notes TEXT,

    -- Source and Verification
    data_source VARCHAR(100),
    verified BOOLEAN DEFAULT FALSE,
    verification_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- AGENTS AND DISTRIBUTION
-- ===========================================

CREATE TABLE agents (
    agent_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Agent Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),

    -- License and Certification
    license_number VARCHAR(50) UNIQUE,
    license_state VARCHAR(50),
    license_expiration DATE,
    certifications TEXT[], -- Array of certification types

    -- Agency Information
    agency_id UUID, -- References agencies table
    agent_type VARCHAR(20) CHECK (agent_type IN ('independent', 'captive', 'agency')),
    commission_structure JSONB DEFAULT '{}',

    -- Status and Performance
    agent_status VARCHAR(20) DEFAULT 'active' CHECK (agent_status IN ('active', 'inactive', 'suspended', 'terminated')),
    hire_date DATE,
    termination_date DATE,

    -- Production Metrics
    total_policies INTEGER DEFAULT 0,
    total_premium DECIMAL(12,2) DEFAULT 0,
    ytd_policies INTEGER DEFAULT 0,
    ytd_premium DECIMAL(12,2) DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Agent commissions
CREATE TABLE agent_commissions (
    commission_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID NOT NULL REFERENCES agents(agent_id),
    policy_id UUID NOT NULL REFERENCES policies(policy_id),

    -- Commission Details
    commission_type VARCHAR(20) CHECK (commission_type IN ('new_business', 'renewal', 'bonus', 'override')),
    commission_amount DECIMAL(8,2) NOT NULL,
    commission_rate DECIMAL(5,2), -- Percentage rate

    -- Payment Information
    earned_date DATE DEFAULT CURRENT_DATE,
    paid_date DATE,
    payment_reference VARCHAR(100),

    -- Status
    commission_status VARCHAR(20) DEFAULT 'earned' CHECK (commission_status IN ('earned', 'pending', 'paid', 'adjusted', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (commission_amount >= 0)
);

-- ===========================================
-- BILLING AND PAYMENTS
-- ===========================================

CREATE TABLE premium_billing (
    billing_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    policy_id UUID NOT NULL REFERENCES policies(policy_id),

    -- Billing Details
    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,
    due_date DATE NOT NULL,

    -- Amounts
    billed_amount DECIMAL(10,2) NOT NULL,
    paid_amount DECIMAL(10,2) DEFAULT 0,
    outstanding_amount DECIMAL(10,2) GENERATED ALWAYS AS (billed_amount - paid_amount) STORED,

    -- Status
    billing_status VARCHAR(20) DEFAULT 'pending' CHECK (billing_status IN ('pending', 'paid', 'overdue', 'cancelled', 'written_off')),

    -- Payment Information
    payment_method VARCHAR(30),
    payment_reference VARCHAR(100),
    paid_at TIMESTAMP WITH TIME ZONE,

    -- Late Fees and Adjustments
    late_fee DECIMAL(6,2) DEFAULT 0,
    adjustments DECIMAL(8,2) DEFAULT 0,

    -- Notifications
    reminder_sent BOOLEAN DEFAULT FALSE,
    reminder_sent_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (billing_period_start < billing_period_end),
    CHECK (billed_amount >= 0)
);

-- Payment transactions
CREATE TABLE payment_transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    billing_id UUID REFERENCES premium_billing(billing_id),
    policy_id UUID REFERENCES policies(policy_id),

    -- Transaction Details
    transaction_type VARCHAR(20) CHECK (transaction_type IN ('premium_payment', 'claim_payment', 'refund', 'adjustment')),
    amount DECIMAL(10,2) NOT NULL,
    transaction_date DATE DEFAULT CURRENT_DATE,

    -- Payment Method
    payment_method VARCHAR(30) CHECK (payment_method IN ('credit_card', 'ach', 'check', 'wire', 'cash')),
    payment_reference VARCHAR(100),

    -- Processing
    processed_by VARCHAR(50),
    authorization_code VARCHAR(20),
    response_code VARCHAR(3),

    -- Status
    transaction_status VARCHAR(20) DEFAULT 'completed' CHECK (transaction_status IN ('pending', 'completed', 'failed', 'reversed')),

    -- Additional Details
    notes TEXT,
    external_transaction_id VARCHAR(100),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (amount != 0)
);

-- ===========================================
-- COMPLIANCE AND REGULATORY
-- ===========================================

CREATE TABLE compliance_events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Event Details
    event_type VARCHAR(50) NOT NULL,
    event_severity VARCHAR(20) DEFAULT 'info' CHECK (event_severity IN ('info', 'warning', 'critical')),

    -- Related Entities
    policyholder_id UUID REFERENCES policyholders(policyholder_id),
    policy_id UUID REFERENCES policies(policy_id),
    claim_id UUID REFERENCES claims(claim_id),

    -- Event Data
    event_data JSONB NOT NULL,
    event_description TEXT,

    -- Resolution
    assigned_to UUID,
    resolution_status VARCHAR(20) DEFAULT 'open' CHECK (resolution_status IN ('open', 'investigating', 'resolved', 'escalated')),
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,

    -- Regulatory Reporting
    reportable BOOLEAN DEFAULT FALSE,
    reported_to VARCHAR(100), -- Regulator name
    report_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

-- Fraud detection
CREATE TABLE fraud_alerts (
    alert_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Alert Details
    alert_type VARCHAR(50) NOT NULL,
    severity_score DECIMAL(5,2) CHECK (severity_score >= 0 AND severity_score <= 10),

    -- Related Entities
    policyholder_id UUID REFERENCES policyholders(policyholder_id),
    policy_id UUID REFERENCES policies(policy_id),
    claim_id UUID REFERENCES claims(claim_id),

    -- Alert Data
    alert_data JSONB NOT NULL,
    alert_description TEXT,

    -- Investigation
    investigation_status VARCHAR(20) DEFAULT 'new' CHECK (investigation_status IN ('new', 'investigating', 'confirmed', 'dismissed')),
    investigator_id UUID,
    investigation_notes TEXT,

    -- Resolution
    resolution VARCHAR(50),
    resolved_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Policyholder indexes
CREATE INDEX idx_policyholders_type_status ON policyholders (entity_type, policyholder_status);
CREATE INDEX idx_policyholders_email ON policyholders (email);

-- Policy indexes
CREATE INDEX idx_policies_policyholder ON policies (policyholder_id);
CREATE INDEX idx_policies_product ON policies (product_id);
CREATE INDEX idx_policies_status ON policies (policy_status);
CREATE INDEX idx_policies_dates ON policies (effective_date, expiration_date);
CREATE INDEX idx_policies_number ON policies (policy_number);

-- Claims indexes
CREATE INDEX idx_claims_policy ON claims (policy_id);
CREATE INDEX idx_claims_policyholder ON claims (policyholder_id);
CREATE INDEX idx_claims_status ON claims (claim_status);
CREATE INDEX idx_claims_type ON claims (claim_type);
CREATE INDEX idx_claims_dates ON claims (incident_date, reported_date);

-- Underwriting indexes
CREATE INDEX idx_underwriting_applications_policyholder ON underwriting_applications (policyholder_id);
CREATE INDEX idx_underwriting_applications_product ON underwriting_applications (product_id);
CREATE INDEX idx_underwriting_applications_status ON underwriting_applications (application_status);

-- Agent indexes
CREATE INDEX idx_agents_license ON agents (license_number);
CREATE INDEX idx_agents_status ON agents (agent_status);
CREATE INDEX idx_agents_agency ON agents (agency_id);

-- Billing indexes
CREATE INDEX idx_premium_billing_policy ON premium_billing (policy_id);
CREATE INDEX idx_premium_billing_status ON premium_billing (billing_status);
CREATE INDEX idx_premium_billing_due_date ON premium_billing (due_date);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Policy summary view
CREATE VIEW policy_summary AS
SELECT
    p.policy_id,
    p.policy_number,
    ph.entity_type,
    CASE
        WHEN ph.entity_type = 'individual' THEN ip.first_name || ' ' || ip.last_name
        ELSE bp.business_name
    END as policyholder_name,
    ipro.product_name,
    ipro.product_type,
    p.policy_status,
    p.coverage_amount,
    p.premium_amount,
    p.effective_date,
    p.expiration_date,
    p.total_premium_paid,
    p.outstanding_balance
FROM policies p
JOIN policyholders ph ON p.policyholder_id = ph.policyholder_id
LEFT JOIN individual_policyholders ip ON ph.policyholder_id = ip.policyholder_id
LEFT JOIN business_policyholders bp ON ph.policyholder_id = bp.policyholder_id
JOIN insurance_products ipro ON p.product_id = ipro.product_id;

-- Claims summary view
CREATE VIEW claims_summary AS
SELECT
    c.claim_id,
    c.claim_number,
    c.claim_type,
    c.claim_status,
    c.incident_date,
    c.reported_date,
    c.estimated_loss,
    c.claimed_amount,
    c.approved_amount,
    c.paid_amount,
    p.policy_number,
    CASE
        WHEN ph.entity_type = 'individual' THEN ip.first_name || ' ' || ip.last_name
        ELSE bp.business_name
    END as claimant_name,
    c.fraud_score,
    c.assigned_adjuster_id,
    c.closed_date
FROM claims c
JOIN policies p ON c.policy_id = p.policy_id
JOIN policyholders ph ON c.policyholder_id = ph.policyholder_id
LEFT JOIN individual_policyholders ip ON ph.policyholder_id = ip.policyholder_id
LEFT JOIN business_policyholders bp ON ph.policyholder_id = bp.policyholder_id;

-- Underwriting pipeline view
CREATE VIEW underwriting_pipeline AS
SELECT
    ua.application_id,
    ua.application_status,
    ua.submitted_at,
    ua.decision,
    ua.quoted_premium,
    ua.final_premium,
    ipro.product_name,
    ipro.product_type,
    CASE
        WHEN ph.entity_type = 'individual' THEN ip.first_name || ' ' || ip.last_name
        ELSE bp.business_name
    END as applicant_name,
    ua.assigned_underwriter_id,
    ua.decision_date
FROM underwriting_applications ua
JOIN policyholders ph ON ua.policyholder_id = ph.policyholder_id
LEFT JOIN individual_policyholders ip ON ph.policyholder_id = ip.policyholder_id
LEFT JOIN business_policyholders bp ON ph.policyholder_id = bp.policyholder_id
JOIN insurance_products ipro ON ua.product_id = ipro.product_id
WHERE ua.application_status NOT IN ('withdrawn', 'declined');

-- Agent performance view
CREATE VIEW agent_performance AS
SELECT
    a.agent_id,
    a.first_name || ' ' || a.last_name as agent_name,
    a.agent_status,
    a.total_policies,
    a.total_premium,
    a.ytd_policies,
    a.ytd_premium,

    -- Commission calculations
    COALESCE(SUM(ac.commission_amount) FILTER (WHERE ac.commission_status = 'paid'), 0) as ytd_commissions,

    -- Policy metrics
    COUNT(DISTINCT p.policy_id) as active_policies,

    -- Recent activity
    MAX(ac.earned_date) as last_commission_date,
    COUNT(ac.commission_id) FILTER (WHERE ac.earned_date >= CURRENT_DATE - INTERVAL '30 days') as recent_commissions

FROM agents a
LEFT JOIN agent_commissions ac ON a.agent_id = ac.agent_id
LEFT JOIN policies p ON ac.policy_id = p.policy_id AND p.policy_status = 'active'
WHERE a.agent_status = 'active'
GROUP BY a.agent_id, a.first_name, a.last_name, a.agent_status, a.total_policies, a.total_premium, a.ytd_policies, a.ytd_premium;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample individual policyholder
INSERT INTO policyholders (entity_type, email, phone, policyholder_status) VALUES
('individual', 'john.doe@email.com', '+1-555-0123', 'active');

INSERT INTO individual_policyholders (
    policyholder_id, first_name, last_name, date_of_birth,
    employment_status, annual_income
) VALUES (
    (SELECT policyholder_id FROM policyholders WHERE email = 'john.doe@email.com' LIMIT 1),
    'John', 'Doe', '1985-03-15', 'employed', 75000
);

-- Insert sample insurance product
INSERT INTO insurance_products (
    product_name, product_code, product_type, product_category,
    base_premium, minimum_premium, maximum_coverage
) VALUES (
    'Comprehensive Auto Insurance', 'AUTO_COMP_001', 'auto', 'personal',
    120.00, 80.00, 500000.00
);

-- Insert sample policy
INSERT INTO policies (
    policy_number, policyholder_id, product_id,
    coverage_amount, premium_amount, effective_date, expiration_date
) VALUES (
    'POL001234567', 
    (SELECT policyholder_id FROM policyholders WHERE email = 'john.doe@email.com' LIMIT 1),
    (SELECT product_id FROM insurance_products WHERE product_code = 'AUTO_COMP_001' LIMIT 1),
    250000.00, 150.00, '2024-01-01', '2025-01-01'
);

-- This insurance schema provides a comprehensive foundation for insurance operations
-- including policy management, claims processing, underwriting, and regulatory compliance.
