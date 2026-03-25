-- Nonprofit & Charity Management Database Schema
-- Comprehensive schema for nonprofit organizations, donor management, grant tracking, and program management

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- ORGANIZATION AND PROGRAM MANAGEMENT
-- ===========================================

CREATE TABLE nonprofit_organizations (
    organization_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_name VARCHAR(255) NOT NULL,
    organization_code VARCHAR(20) UNIQUE NOT NULL,

    -- Organization Details
    organization_type VARCHAR(50) CHECK (organization_type IN (
        'charity', 'foundation', 'advocacy', 'religious', 'educational',
        'healthcare', 'environmental', 'humanitarian', 'animal_welfare', 'other'
    )),
    tax_id VARCHAR(50) UNIQUE,
    ein VARCHAR(20) UNIQUE, -- Employer Identification Number

    -- Legal and Regulatory
    incorporation_date DATE,
    state_of_incorporation VARCHAR(50),
    bylaws_document_url VARCHAR(500),
    board_members JSONB DEFAULT '[]', -- Array of board member objects

    -- Mission and Focus
    mission_statement TEXT,
    vision_statement TEXT,
    core_values TEXT,
    primary_focus_areas TEXT[], -- Education, poverty, healthcare, etc.
    geographic_focus TEXT[], -- Local, national, international, specific regions

    -- Operational Details
    annual_budget DECIMAL(12,2),
    number_of_employees INTEGER,
    volunteer_count INTEGER,
    service_area_population INTEGER,

    -- Contact Information
    address JSONB,
    phone VARCHAR(20),
    email VARCHAR(255),
    website VARCHAR(500),

    -- Accreditation and Ratings
    accreditations JSONB DEFAULT '[]', -- BBB, Charity Navigator, etc.
    charity_navigator_rating VARCHAR(10),
    bbb_accreditation BOOLEAN DEFAULT FALSE,

    -- Status and Governance
    organization_status VARCHAR(20) DEFAULT 'active' CHECK (organization_status IN ('active', 'inactive', 'dissolved', 'merged')),
    governance_model VARCHAR(50) CHECK (governance_model IN ('board_governed', 'member_governed', 'individual_led')),
    fiscal_year_end DATE DEFAULT '12-31',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE programs (
    program_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Program Details
    program_name VARCHAR(255) NOT NULL,
    program_code VARCHAR(20) UNIQUE NOT NULL,
    program_description TEXT,

    -- Program Classification
    program_type VARCHAR(50) CHECK (program_type IN (
        'direct_service', 'advocacy', 'education', 'research', 'capacity_building',
        'emergency_relief', 'community_development', 'policy_reform', 'other'
    )),
    program_category VARCHAR(50),
    target_beneficiaries TEXT[], -- Children, elderly, homeless, etc.

    -- Program Scope and Impact
    geographic_scope TEXT[], -- Local, regional, national, international
    estimated_beneficiaries INTEGER,
    program_goals TEXT,

    -- Budget and Funding
    annual_budget DECIMAL(10,2),
    funding_sources JSONB DEFAULT '[]', -- Grants, donations, government, etc.

    -- Timeline and Status
    start_date DATE,
    end_date DATE,
    program_status VARCHAR(20) DEFAULT 'active' CHECK (program_status IN (
        'planning', 'active', 'completed', 'suspended', 'cancelled'
    )),

    -- Performance Metrics
    success_metrics JSONB DEFAULT '{}',
    evaluation_methodology TEXT,
    last_evaluation_date DATE,

    -- Resources and Partnerships
    required_resources JSONB DEFAULT '[]',
    partner_organizations JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (start_date <= end_date OR end_date IS NULL)
);

CREATE TABLE program_metrics (
    metric_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    program_id UUID NOT NULL REFERENCES programs(program_id),

    -- Metric Details
    metric_name VARCHAR(255) NOT NULL,
    metric_type VARCHAR(50) CHECK (metric_type IN (
        'output', 'outcome', 'impact', 'efficiency', 'quality'
    )),
    metric_description TEXT,

    -- Measurement
    measurement_period VARCHAR(20) CHECK (measurement_period IN ('monthly', 'quarterly', 'annual', 'one_time')),
    baseline_value DECIMAL(10,2),
    target_value DECIMAL(10,2),
    actual_value DECIMAL(10,2),

    -- Tracking
    measurement_date DATE DEFAULT CURRENT_DATE,
    data_source VARCHAR(255),
    responsible_person VARCHAR(100),

    -- Performance Assessment
    performance_rating VARCHAR(20) CHECK (performance_rating IN ('exceeded', 'met', 'below_target', 'not_measured')),
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- DONOR AND FUNDRAISING MANAGEMENT
-- ===========================================

CREATE TABLE donors (
    donor_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Donor Identity
    donor_type VARCHAR(20) CHECK (donor_type IN ('individual', 'corporation', 'foundation', 'government', 'anonymous')),
    donor_number VARCHAR(20) UNIQUE,

    -- Personal/Business Information
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    company_name VARCHAR(255),
    contact_person VARCHAR(255),

    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(20),
    mobile_phone VARCHAR(20),
    address JSONB,

    -- Donor Profile
    donor_category VARCHAR(50), -- Major donor, recurring donor, etc.
    giving_capacity VARCHAR(20) CHECK (giving_capacity IN ('under_1000', '1000_10000', '10000_50000', '50000_100000', 'over_100000')),
    interests_and_causes TEXT[],

    -- Relationship Management
    acquisition_source VARCHAR(100),
    first_donation_date DATE,
    last_contact_date DATE,
    communication_preferences JSONB DEFAULT '{}',

    -- Recognition and Stewardship
    recognition_level VARCHAR(50), -- Named gift, donor wall, etc.
    stewardship_notes TEXT,
    volunteer_history JSONB DEFAULT '[]',

    -- Status and Compliance
    donor_status VARCHAR(20) DEFAULT 'active' CHECK (donor_status IN ('active', 'inactive', 'deceased', 'lapsed')),
    tax_deductible BOOLEAN DEFAULT TRUE,
    anonymous_donor BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK ((donor_type = 'corporation' AND company_name IS NOT NULL) OR
           (donor_type IN ('individual', 'anonymous') AND first_name IS NOT NULL) OR
           (donor_type = 'foundation'))
);

CREATE TABLE donations (
    donation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    donor_id UUID NOT NULL REFERENCES donors(donor_id),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Donation Details
    donation_number VARCHAR(30) UNIQUE NOT NULL,
    donation_type VARCHAR(30) CHECK (donation_type IN (
        'cash', 'check', 'credit_card', 'stock', 'property', 'in_kind',
        'planned_gift', 'matching_gift', 'corporate_sponsorship'
    )),

    -- Financial Information
    donation_amount DECIMAL(12,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    payment_method VARCHAR(50),

    -- Donation Purpose
    designation VARCHAR(50) CHECK (designation IN ('unrestricted', 'restricted', 'specific_program')),
    designated_program_id UUID REFERENCES programs(program_id),
    designation_notes TEXT,

    -- Recognition and Tribute
    tribute_type VARCHAR(30) CHECK (tribute_type IN ('honor', 'memory', 'celebration', 'none')),
    tribute_recipient_name VARCHAR(255),
    tribute_notification_address JSONB,

    -- Tax and Legal
    tax_year INTEGER,
    tax_receipt_issued BOOLEAN DEFAULT FALSE,
    tax_receipt_number VARCHAR(50),
    tax_deductible_amount DECIMAL(12,2),

    -- Matching Gifts
    matching_gift_eligible BOOLEAN DEFAULT FALSE,
    matching_company VARCHAR(255),
    matching_amount DECIMAL(12,2),

    -- Processing and Status
    donation_date DATE DEFAULT CURRENT_DATE,
    received_date DATE,
    deposited_date DATE,
    donation_status VARCHAR(20) DEFAULT 'received' CHECK (donation_status IN (
        'pledged', 'received', 'processed', 'deposited', 'refunded', 'cancelled'
    )),

    -- Acknowledgment
    acknowledgment_sent BOOLEAN DEFAULT FALSE,
    acknowledgment_date DATE,
    acknowledgment_method VARCHAR(30) CHECK (acknowledgment_method IN ('email', 'mail', 'phone', 'personal')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (donation_amount > 0),
    CHECK (designation != 'specific_program' OR designated_program_id IS NOT NULL)
);

CREATE TABLE pledges (
    pledge_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    donor_id UUID NOT NULL REFERENCES donors(donor_id),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Pledge Details
    pledge_number VARCHAR(30) UNIQUE NOT NULL,
    pledge_amount DECIMAL(12,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',

    -- Pledge Terms
    pledge_type VARCHAR(30) CHECK (pledge_type IN ('outright', 'multi_year', 'annual', 'monthly', 'event')),
    payment_schedule VARCHAR(50), -- Annual, quarterly, monthly, etc.
    pledge_start_date DATE,
    pledge_end_date DATE,

    -- Designation
    designation VARCHAR(50) CHECK (designation IN ('unrestricted', 'restricted', 'specific_program')),
    designated_program_id UUID REFERENCES programs(program_id),

    -- Payment Tracking
    total_paid DECIMAL(12,2) DEFAULT 0,
    remaining_balance DECIMAL(12,2) GENERATED ALWAYS AS (pledge_amount - total_paid) STORED,

    -- Status and Management
    pledge_status VARCHAR(20) DEFAULT 'active' CHECK (pledge_status IN ('active', 'completed', 'cancelled', 'defaulted')),
    payment_reminders BOOLEAN DEFAULT TRUE,
    last_payment_date DATE,

    -- Special Terms
    pledge_conditions TEXT,
    recognition_agreement TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (pledge_amount > 0),
    CHECK (pledge_start_date <= pledge_end_date OR pledge_end_date IS NULL)
);

-- ===========================================
-- GRANT AND FUNDING MANAGEMENT
-- ===========================================

CREATE TABLE grants (
    grant_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Grant Details
    grant_number VARCHAR(30) UNIQUE NOT NULL,
    grant_title VARCHAR(255) NOT NULL,
    grant_description TEXT,

    -- Funding Source
    funder_type VARCHAR(30) CHECK (funder_type IN ('government', 'foundation', 'corporate', 'individual', 'other')),
    funder_name VARCHAR(255) NOT NULL,
    funder_contact JSONB,

    -- Grant Terms
    total_amount DECIMAL(12,2) NOT NULL,
    awarded_amount DECIMAL(12,2),
    grant_period_start DATE,
    grant_period_end DATE,

    -- Program and Purpose
    associated_program_id UUID REFERENCES programs(program_id),
    grant_purpose TEXT,
    deliverables JSONB DEFAULT '[]',

    -- Application and Award
    application_date DATE,
    award_date DATE,
    acceptance_date DATE,
    grant_status VARCHAR(20) DEFAULT 'applied' CHECK (grant_status IN (
        'applied', 'awarded', 'accepted', 'active', 'completed',
        'terminated', 'rejected', 'withdrawn'
    )),

    -- Financial Management
    budget_allocated DECIMAL(12,2),
    amount_received DECIMAL(12,2) DEFAULT 0,
    amount_spent DECIMAL(12,2) DEFAULT 0,
    remaining_balance DECIMAL(12,2) GENERATED ALWAYS AS (amount_received - amount_spent) STORED,

    -- Reporting Requirements
    reporting_schedule VARCHAR(30) CHECK (reporting_schedule IN ('monthly', 'quarterly', 'annual', 'final_only')),
    next_report_due DATE,
    final_report_due DATE,

    -- Compliance and Restrictions
    grant_restrictions TEXT,
    compliance_requirements JSONB DEFAULT '[]',
    audit_requirements TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (total_amount > 0),
    CHECK (grant_period_start <= grant_period_end)
);

CREATE TABLE grant_reports (
    report_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    grant_id UUID NOT NULL REFERENCES grants(grant_id) ON DELETE CASCADE,

    -- Report Details
    report_type VARCHAR(30) CHECK (report_type IN ('progress', 'financial', 'final', 'audit')),
    report_period_start DATE,
    report_period_end DATE,
    due_date DATE,
    submitted_date DATE,

    -- Report Content
    executive_summary TEXT,
    activities_completed TEXT,
    challenges_encountered TEXT,
    next_steps TEXT,

    -- Financial Information
    budget_vs_actual JSONB DEFAULT '{}',
    funds_used DECIMAL(10,2),

    -- Impact Metrics
    outcomes_achieved JSONB DEFAULT '[]',
    beneficiaries_served INTEGER,

    -- Status and Approval
    report_status VARCHAR(20) DEFAULT 'draft' CHECK (report_status IN ('draft', 'submitted', 'approved', 'rejected', 'revision_required')),
    funder_feedback TEXT,
    approval_date DATE,

    -- Supporting Documents
    attachments JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (report_period_start <= report_period_end)
);

-- ===========================================
-- VOLUNTEER AND EVENT MANAGEMENT
-- ===========================================

CREATE TABLE volunteers (
    volunteer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Volunteer Identity
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),

    -- Personal Information
    date_of_birth DATE,
    address JSONB,
    emergency_contact JSONB,

    -- Volunteer Profile
    skills_and_interests TEXT[],
    availability_schedule JSONB DEFAULT '{}',
    preferred_roles TEXT[],

    -- Background and Screening
    background_check_completed BOOLEAN DEFAULT FALSE,
    background_check_date DATE,
    references JSONB DEFAULT '[]',

    -- Volunteer History
    first_volunteer_date DATE DEFAULT CURRENT_DATE,
    total_hours_volunteered DECIMAL(8,2) DEFAULT 0,
    volunteer_status VARCHAR(20) DEFAULT 'active' CHECK (volunteer_status IN ('active', 'inactive', 'suspended', 'alumni')),

    -- Recognition
    recognition_level VARCHAR(50),
    awards_received JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE volunteer_assignments (
    assignment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    volunteer_id UUID NOT NULL REFERENCES volunteers(volunteer_id),
    program_id UUID REFERENCES programs(program_id),

    -- Assignment Details
    role_title VARCHAR(100) NOT NULL,
    role_description TEXT,
    assignment_type VARCHAR(30) CHECK (assignment_type IN ('ongoing', 'project_based', 'event_based', 'one_time')),

    -- Schedule and Commitment
    start_date DATE,
    end_date DATE,
    weekly_hours_commitment DECIMAL(4,1),
    schedule_details JSONB DEFAULT '{}',

    -- Tracking and Management
    hours_logged DECIMAL(6,2) DEFAULT 0,
    assignment_status VARCHAR(20) DEFAULT 'active' CHECK (assignment_status IN ('active', 'completed', 'cancelled', 'on_hold')),

    -- Supervisor and Training
    supervisor_id UUID REFERENCES volunteers(volunteer_id),
    training_completed JSONB DEFAULT '[]',
    training_required JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (start_date <= end_date OR end_date IS NULL)
);

CREATE TABLE events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Event Details
    event_name VARCHAR(255) NOT NULL,
    event_code VARCHAR(20) UNIQUE NOT NULL,
    event_description TEXT,

    -- Event Type and Purpose
    event_type VARCHAR(50) CHECK (event_type IN (
        'fundraiser', 'awareness', 'volunteer_recruitment', 'community_outreach',
        'advocacy', 'education', 'celebration', 'meeting', 'conference'
    )),
    event_purpose TEXT,

    -- Scheduling
    event_date DATE NOT NULL,
    start_time TIME,
    end_time TIME,
    setup_time TIME,
    cleanup_time TIME,

    -- Location and Logistics
    venue_name VARCHAR(255),
    address JSONB,
    capacity INTEGER,
    expected_attendance INTEGER,

    -- Event Management
    event_status VARCHAR(20) DEFAULT 'planned' CHECK (event_status IN (
        'planned', 'confirmed', 'in_progress', 'completed', 'cancelled'
    )),
    registration_required BOOLEAN DEFAULT FALSE,
    registration_deadline DATE,

    -- Budget and Financial
    event_budget DECIMAL(8,2),
    actual_cost DECIMAL(8,2),
    revenue_generated DECIMAL(8,2),

    -- Resources and Volunteers
    required_volunteers INTEGER,
    assigned_volunteers JSONB DEFAULT '[]',
    equipment_needed JSONB DEFAULT '[]',

    -- Marketing and Communication
    marketing_materials JSONB DEFAULT '[]',
    target_audience VARCHAR(100),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE event_registrations (
    registration_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,

    -- Registrant Information
    registrant_type VARCHAR(20) CHECK (registrant_type IN ('donor', 'volunteer', 'community_member', 'staff')),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(20),

    -- Registration Details
    registration_date DATE DEFAULT CURRENT_DATE,
    ticket_type VARCHAR(50),
    ticket_price DECIMAL(6,2) DEFAULT 0,
    payment_status VARCHAR(20) CHECK (payment_status IN ('paid', 'pending', 'complimentary')),

    -- Attendance Tracking
    checked_in BOOLEAN DEFAULT FALSE,
    check_in_time TIMESTAMP WITH TIME ZONE,

    -- Additional Information
    special_requirements TEXT,
    dietary_restrictions TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- FINANCIAL AND REPORTING MANAGEMENT
-- ===========================================

CREATE TABLE budgets (
    budget_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Budget Details
    budget_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
    budget_version VARCHAR(20) DEFAULT '1.0',
    budget_name VARCHAR(100),

    -- Budget Categories
    total_budget DECIMAL(12,2),
    revenue_budget DECIMAL(12,2),
    expense_budget DECIMAL(12,2),

    -- Revenue Breakdown
    donations_budget DECIMAL(10,2),
    grants_budget DECIMAL(10,2),
    events_budget DECIMAL(10,2),
    other_revenue_budget DECIMAL(10,2),

    -- Expense Breakdown
    program_expenses_budget DECIMAL(10,2),
    administrative_expenses_budget DECIMAL(10,2),
    fundraising_expenses_budget DECIMAL(10,2),

    -- Budget Status
    budget_status VARCHAR(20) DEFAULT 'draft' CHECK (budget_status IN ('draft', 'approved', 'active', 'archived')),
    approval_date DATE,
    approved_by VARCHAR(100),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE financial_reports (
    report_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Report Details
    report_type VARCHAR(30) CHECK (report_type IN ('monthly', 'quarterly', 'annual', 'audit', '990')),
    report_period_start DATE,
    report_period_end DATE,
    filing_deadline DATE,

    -- Financial Summary
    total_revenue DECIMAL(12,2),
    total_expenses DECIMAL(12,2),
    net_assets DECIMAL(12,2),

    -- Revenue Breakdown
    donations_revenue DECIMAL(10,2),
    grants_revenue DECIMAL(10,2),
    program_service_revenue DECIMAL(10,2),
    other_revenue DECIMAL(10,2),

    -- Expense Breakdown
    program_expenses DECIMAL(10,2),
    management_expenses DECIMAL(10,2),
    fundraising_expenses DECIMAL(10,2),

    -- Program Efficiency Ratios
    program_expense_ratio DECIMAL(5,2), -- Program expenses / total expenses
    fundraising_efficiency DECIMAL(5,2), -- Average donation amount / fundraising expense
    administrative_cost_ratio DECIMAL(5,2), -- Admin expenses / total expenses

    -- Status and Compliance
    report_status VARCHAR(20) DEFAULT 'draft' CHECK (report_status IN ('draft', 'filed', 'audited', 'public')),
    filed_date DATE,
    auditor_name VARCHAR(255),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (report_period_start <= report_period_end)
);

-- ===========================================
-- ANALYTICS AND IMPACT MEASUREMENT
-- ===========================================

CREATE TABLE impact_metrics (
    metric_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES nonprofit_organizations(organization_id),

    -- Metric Details
    metric_name VARCHAR(255) NOT NULL,
    metric_category VARCHAR(50) CHECK (metric_category IN (
        'beneficiaries_served', 'program_outcomes', 'community_impact',
        'financial_sustainability', 'organizational_capacity', 'advocacy_impact'
    )),
    metric_description TEXT,

    -- Measurement
    measurement_period VARCHAR(20) CHECK (measurement_period IN ('monthly', 'quarterly', 'annual')),
    baseline_value DECIMAL(10,2),
    current_value DECIMAL(10,2),
    target_value DECIMAL(10,2),

    -- Data Source and Collection
    data_source VARCHAR(255),
    collection_method VARCHAR(100),
    responsible_person VARCHAR(100),
    last_updated DATE DEFAULT CURRENT_DATE,

    -- Performance Assessment
    trend VARCHAR(20) CHECK (trend IN ('improving', 'stable', 'declining', 'insufficient_data')),
    performance_rating VARCHAR(20) CHECK (performance_rating IN ('exceeds_target', 'meets_target', 'below_target', 'off_track')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Organization and program indexes
CREATE INDEX idx_programs_organization ON programs (organization_id, program_status);
CREATE INDEX idx_program_metrics_program ON program_metrics (program_id, measurement_date DESC);

-- Donor and fundraising indexes
CREATE INDEX idx_donors_organization ON donors (organization_id, donor_status);
CREATE INDEX idx_donations_donor ON donations (donor_id, donation_date DESC);
CREATE INDEX idx_donations_organization ON donations (organization_id, donation_date DESC);
CREATE INDEX idx_pledges_donor ON pledges (donor_id, pledge_status);

-- Grant management indexes
CREATE INDEX idx_grants_organization ON grants (organization_id, grant_status);
CREATE INDEX idx_grant_reports_grant ON grant_reports (grant_id, submitted_date DESC);

-- Volunteer and event indexes
CREATE INDEX idx_volunteers_organization ON volunteers (organization_id, volunteer_status);
CREATE INDEX idx_volunteer_assignments_volunteer ON volunteer_assignments (volunteer_id, assignment_status);
CREATE INDEX idx_events_organization ON events (organization_id, event_date DESC);
CREATE INDEX idx_event_registrations_event ON event_registrations (event_id, registration_date DESC);

-- Financial indexes
CREATE INDEX idx_budgets_organization ON budgets (organization_id, budget_year DESC);
CREATE INDEX idx_financial_reports_organization ON financial_reports (organization_id, report_period_start DESC);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Donor summary dashboard
CREATE VIEW donor_summary AS
SELECT
    d.donor_id,
    d.donor_number,
    d.first_name || ' ' || d.last_name as donor_name,
    d.donor_type,
    d.donor_category,

    -- Donation history
    COUNT(do.donation_id) as total_donations,
    SUM(do.donation_amount) as total_donated,
    AVG(do.donation_amount) as avg_donation_amount,
    MAX(do.donation_date) as last_donation_date,
    MIN(do.donation_date) as first_donation_date,

    -- Pledge information
    COUNT(p.pledge_id) as active_pledges,
    SUM(p.remaining_balance) as total_pledge_balance,

    -- Engagement metrics
    d.last_contact_date,
    CASE WHEN d.last_contact_date >= CURRENT_DATE - INTERVAL '90 days' THEN 'highly_engaged'
         WHEN d.last_contact_date >= CURRENT_DATE - INTERVAL '180 days' THEN 'moderately_engaged'
         ELSE 'low_engagement' END as engagement_level,

    -- Donor value
    CASE WHEN SUM(do.donation_amount) >= 10000 THEN 'platinum'
         WHEN SUM(do.donation_amount) >= 5000 THEN 'gold'
         WHEN SUM(do.donation_amount) >= 1000 THEN 'silver'
         ELSE 'bronze' END as donor_tier,

    -- Status and flags
    d.donor_status,
    CASE WHEN MAX(do.donation_date) < CURRENT_DATE - INTERVAL '365 days' THEN TRUE ELSE FALSE END as lapsed_donor

FROM donors d
LEFT JOIN donations do ON d.donor_id = do.donor_id AND do.donation_status = 'deposited'
LEFT JOIN pledges p ON d.donor_id = p.donor_id AND p.pledge_status = 'active'
WHERE d.donor_status = 'active'
GROUP BY d.donor_id, d.donor_number, d.first_name, d.last_name, d.donor_type, d.donor_category, d.last_contact_date, d.donor_status;

-- Program performance overview
CREATE VIEW program_performance AS
SELECT
    p.program_id,
    p.program_name,
    p.program_type,
    o.organization_name,

    -- Budget and spending
    p.annual_budget,
    COALESCE(SUM(g.amount_received), 0) as grant_funding_received,
    p.annual_budget - COALESCE(SUM(g.amount_received), 0) as funding_gap,

    -- Impact metrics
    AVG(pm.actual_value) as avg_metric_performance,
    COUNT(CASE WHEN pm.performance_rating = 'exceeds_target' THEN 1 END) as metrics_exceeding_target,
    COUNT(pm.metric_id) as total_metrics,

    -- Volunteer engagement
    COUNT(va.assignment_id) as active_volunteer_assignments,
    SUM(va.hours_logged) as total_volunteer_hours,

    -- Program status and timeline
    p.program_status,
    p.start_date,
    p.end_date,
    CASE WHEN p.end_date < CURRENT_DATE AND p.program_status = 'active' THEN 'overdue'
         WHEN p.end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' THEN 'ending_soon'
         ELSE 'on_track' END as timeline_status

FROM programs p
JOIN nonprofit_organizations o ON p.organization_id = o.organization_id
LEFT JOIN grants g ON p.program_id = g.associated_program_id AND g.grant_status = 'active'
LEFT JOIN program_metrics pm ON p.program_id = pm.program_id
LEFT JOIN volunteer_assignments va ON p.program_id = va.program_id AND va.assignment_status = 'active'
GROUP BY p.program_id, p.program_name, p.program_type, o.organization_name, p.annual_budget, p.program_status, p.start_date, p.end_date;

-- Financial health dashboard
CREATE VIEW financial_health AS
SELECT
    o.organization_id,
    o.organization_name,

    -- Revenue streams (last 12 months)
    COALESCE(SUM(d.donation_amount), 0) as total_donations,
    COALESCE(SUM(g.amount_received), 0) as total_grants,
    COALESCE(SUM(e.revenue_generated), 0) as total_event_revenue,
    COALESCE(SUM(d.donation_amount + g.amount_received + e.revenue_generated), 0) as total_revenue,

    -- Expense breakdown
    COALESCE(SUM(b.program_expenses_budget), 0) as program_expenses,
    COALESCE(SUM(b.administrative_expenses_budget), 0) as administrative_expenses,
    COALESCE(SUM(b.fundraising_expenses_budget), 0) as fundraising_expenses,

    -- Financial ratios
    CASE WHEN SUM(b.program_expenses_budget) > 0
         THEN ROUND(SUM(b.program_expenses_budget) / (SUM(b.program_expenses_budget) + SUM(b.administrative_expenses_budget) + SUM(b.fundraising_expenses_budget)) * 100, 1)
         ELSE 0 END as program_expense_ratio,

    CASE WHEN SUM(b.fundraising_expenses_budget) > 0
         THEN ROUND(AVG(d.donation_amount) / SUM(b.fundraising_expenses_budget) * 100, 1)
         ELSE 0 END as fundraising_efficiency_ratio,

    -- Liquidity and reserves
    CASE WHEN SUM(b.expense_budget) > 0
         THEN ROUND((SUM(d.donation_amount) + SUM(g.amount_received)) / SUM(b.expense_budget), 1)
         ELSE 0 END as operating_reserve_ratio,

    -- Growth trends
    ROUND(
        (SUM(CASE WHEN d.donation_date >= CURRENT_DATE - INTERVAL '6 months' THEN d.donation_amount END) -
         SUM(CASE WHEN d.donation_date >= CURRENT_DATE - INTERVAL '12 months' AND d.donation_date < CURRENT_DATE - INTERVAL '6 months' THEN d.donation_amount END)) /
        NULLIF(SUM(CASE WHEN d.donation_date >= CURRENT_DATE - INTERVAL '12 months' AND d.donation_date < CURRENT_DATE - INTERVAL '6 months' THEN d.donation_amount END), 0) * 100, 1
    ) as revenue_growth_rate,

    -- Financial health score
    ROUND(
        (
            -- Program efficiency (30%)
            LEAST(COALESCE(SUM(b.program_expenses_budget) / NULLIF((SUM(b.program_expenses_budget) + SUM(b.administrative_expenses_budget) + SUM(b.fundraising_expenses_budget)), 0) * 100, 0) / 65 * 30, 30) +
            -- Fundraising efficiency (25%)
            LEAST(COALESCE(AVG(d.donation_amount) / NULLIF(SUM(b.fundraising_expenses_budget), 0) * 100, 0) / 20 * 25, 25) +
            -- Operating reserves (25%)
            LEAST(COALESCE((SUM(d.donation_amount) + SUM(g.amount_received)) / NULLIF(SUM(b.expense_budget), 0) * 100, 0) / 300 * 25, 25) +
            -- Revenue growth (20%)
            GREATEST(LEAST(COALESCE(
                (SUM(CASE WHEN d.donation_date >= CURRENT_DATE - INTERVAL '6 months' THEN d.donation_amount END) -
                 SUM(CASE WHEN d.donation_date >= CURRENT_DATE - INTERVAL '12 months' AND d.donation_date < CURRENT_DATE - INTERVAL '6 months' THEN d.donation_amount END)) /
                NULLIF(SUM(CASE WHEN d.donation_date >= CURRENT_DATE - INTERVAL '12 months' AND d.donation_date < CURRENT_DATE - INTERVAL '6 months' THEN d.donation_amount END), 0) * 100, 0
            ) / 10 * 20 + 10, 20), 0)
        ), 1
    ) as financial_health_score

FROM nonprofit_organizations o
LEFT JOIN donations d ON o.organization_id = d.organization_id AND d.donation_date >= CURRENT_DATE - INTERVAL '12 months'
LEFT JOIN grants g ON o.organization_id = g.organization_id AND g.grant_status IN ('active', 'completed')
LEFT JOIN events e ON o.organization_id = e.organization_id AND e.event_date >= CURRENT_DATE - INTERVAL '12 months'
LEFT JOIN budgets b ON o.organization_id = b.organization_id AND b.budget_year = EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
GROUP BY o.organization_id, o.organization_name;

-- ===========================================
-- FUNCTIONS FOR NONPROFIT OPERATIONS
-- =========================================--

-- Function to calculate donor lifetime value
CREATE OR REPLACE FUNCTION calculate_donor_ltv(donor_uuid UUID)
RETURNS TABLE (
    total_donated DECIMAL,
    donation_frequency DECIMAL,
    average_donation DECIMAL,
    donor_lifespan_months INTEGER,
    lifetime_value DECIMAL,
    donor_value_segment VARCHAR
) AS $$
DECLARE
    donor_stats RECORD;
BEGIN
    SELECT
        COUNT(d.donation_id) as donation_count,
        SUM(d.donation_amount) as total_amount,
        AVG(d.donation_amount) as avg_amount,
        MIN(d.donation_date) as first_donation,
        MAX(d.donation_date) as last_donation
    INTO donor_stats
    FROM donations d
    WHERE d.donor_id = donor_uuid AND d.donation_status = 'deposited';

    RETURN QUERY SELECT
        donor_stats.total_amount,
        CASE WHEN donor_stats.donation_count > 1 AND donor_stats.first_donation IS NOT NULL AND donor_stats.last_donation IS NOT NULL
             THEN donor_stats.donation_count::DECIMAL / EXTRACT(EPOCH FROM (donor_stats.last_donation - donor_stats.first_donation)) / 86400 * 30
             ELSE donor_stats.donation_count::DECIMAL END as donation_frequency,
        donor_stats.avg_amount,
        CASE WHEN donor_stats.first_donation IS NOT NULL
             THEN EXTRACT(EPOCH FROM (CURRENT_DATE - donor_stats.first_donation)) / 86400 / 30
             ELSE 0 END::INTEGER as donor_lifespan_months,
        donor_stats.total_amount as lifetime_value,
        CASE WHEN donor_stats.total_amount >= 10000 THEN 'high_value'
             WHEN donor_stats.total_amount >= 1000 THEN 'medium_value'
             WHEN donor_stats.total_amount > 0 THEN 'low_value'
             ELSE 'prospect' END as donor_value_segment;
END;
$$ LANGUAGE plpgsql;

-- Function to assess program effectiveness
CREATE OR REPLACE FUNCTION assess_program_effectiveness(program_uuid UUID)
RETURNS TABLE (
    program_name VARCHAR,
    effectiveness_score DECIMAL,
    outcome_achievement DECIMAL,
    efficiency_rating DECIMAL,
    sustainability_score DECIMAL,
    overall_rating VARCHAR
) AS $$
DECLARE
    program_record programs%ROWTYPE;
    metrics_summary RECORD;
    volunteer_engagement RECORD;
BEGIN
    -- Get program details
    SELECT * INTO program_record FROM programs WHERE program_id = program_uuid;

    -- Calculate metrics summary
    SELECT
        COUNT(*) as total_metrics,
        AVG(CASE WHEN performance_rating = 'exceeds_target' THEN 100
                 WHEN performance_rating = 'meets_target' THEN 75
                 WHEN performance_rating = 'below_target' THEN 25
                 ELSE 0 END) as avg_performance_score,
        COUNT(CASE WHEN actual_value >= target_value THEN 1 END)::DECIMAL / COUNT(*) as target_achievement_rate
    INTO metrics_summary
    FROM program_metrics
    WHERE program_id = program_uuid;

    -- Calculate volunteer engagement
    SELECT
        COUNT(*) as total_assignments,
        AVG(hours_logged) as avg_hours_per_assignment,
        COUNT(CASE WHEN assignment_status = 'completed' THEN 1 END)::DECIMAL / COUNT(*) as completion_rate
    INTO volunteer_engagement
    FROM volunteer_assignments
    WHERE program_id = program_uuid;

    RETURN QUERY SELECT
        program_record.program_name,
        -- Effectiveness score (weighted average of metrics)
        COALESCE(metrics_summary.avg_performance_score, 0) as effectiveness_score,
        -- Outcome achievement
        COALESCE(metrics_summary.target_achievement_rate * 100, 0) as outcome_achievement,
        -- Efficiency rating (volunteer engagement)
        COALESCE(volunteer_engagement.completion_rate * 100, 0) as efficiency_rating,
        -- Sustainability score (placeholder - would need more data)
        75.0 as sustainability_score,
        -- Overall rating
        CASE
            WHEN COALESCE(metrics_summary.avg_performance_score, 0) >= 80 THEN 'excellent'
            WHEN COALESCE(metrics_summary.avg_performance_score, 0) >= 60 THEN 'good'
            WHEN COALESCE(metrics_summary.avg_performance_score, 0) >= 40 THEN 'fair'
            ELSE 'needs_improvement'
        END as overall_rating;
END;
$$ LANGUAGE plpgsql;

-- Function to generate donor thank you letters
CREATE OR REPLACE FUNCTION generate_donor_acknowledgment(donation_uuid UUID)
RETURNS TABLE (
    donor_name VARCHAR,
    donation_amount DECIMAL,
    donation_date DATE,
    acknowledgment_letter TEXT,
    tax_receipt_info JSONB
) AS $$
DECLARE
    donation_record donations%ROWTYPE;
    donor_record donors%ROWTYPE;
    organization_record nonprofit_organizations%ROWTYPE;
BEGIN
    -- Get donation and related records
    SELECT * INTO donation_record FROM donations WHERE donation_id = donation_uuid;
    SELECT * INTO donor_record FROM donors WHERE donor_id = donation_record.donor_id;
    SELECT * INTO organization_record FROM nonprofit_organizations WHERE organization_id = donation_record.organization_id;

    RETURN QUERY SELECT
        CASE WHEN donor_record.donor_type = 'individual'
             THEN donor_record.first_name || ' ' || donor_record.last_name
             ELSE donor_record.company_name END as donor_name,
        donation_record.donation_amount,
        donation_record.donation_date,
        format(
            'Dear %s,

On behalf of %s, I want to extend our deepest gratitude for your generous donation of $%s on %s.

Your support enables us to %s and make a meaningful impact in our community. %s

%s

Thank you once again for your generosity and commitment to our mission.

Sincerely,
[Executive Director Name]
%s',

            CASE WHEN donor_record.donor_type = 'individual'
                 THEN donor_record.first_name || ' ' || donor_record.last_name
                 ELSE donor_record.company_name END,
            organization_record.organization_name,
            to_char(donation_record.donation_amount, 'FM999,999,999.00'),
            to_char(donation_record.donation_date, 'Month DD, YYYY'),
            organization_record.mission_statement,
            CASE WHEN donation_record.designation = 'specific_program'
                 THEN format('Your donation has been designated for our %s program.',
                           (SELECT program_name FROM programs WHERE program_id = donation_record.designated_program_id))
                 ELSE 'Your unrestricted donation allows us to allocate funds where they are needed most.' END,
            CASE WHEN donation_record.tribute_type != 'none'
                 THEN format('This donation is given in %s of %s.',
                           donation_record.tribute_type, donation_record.tribute_recipient_name)
                 ELSE '' END,
            organization_record.organization_name
        ) as acknowledgment_letter,
        jsonb_build_object(
            'tax_year', donation_record.tax_year,
            'tax_deductible_amount', donation_record.tax_deductible_amount,
            'receipt_issued', donation_record.tax_receipt_issued,
            'receipt_number', donation_record.tax_receipt_number,
            'ein', organization_record.ein
        ) as tax_receipt_info;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample nonprofit organization
INSERT INTO nonprofit_organizations (
    organization_name, organization_code, organization_type,
    mission_statement, tax_id, primary_focus_areas, annual_budget
) VALUES (
    'Community Hope Foundation', 'CHF001', 'charity',
    'To provide essential services and support to underserved communities',
    '12-3456789', ARRAY['poverty_relief', 'education', 'healthcare'], 2500000.00
);

-- Insert sample program
INSERT INTO programs (
    organization_id, program_name, program_code, program_type,
    program_description, annual_budget, estimated_beneficiaries
) VALUES (
    (SELECT organization_id FROM nonprofit_organizations WHERE organization_code = 'CHF001' LIMIT 1),
    'Community Food Bank', 'CFB001', 'direct_service',
    'Providing nutritious food to families in need', 500000.00, 5000
);

-- Insert sample donor
INSERT INTO donors (
    organization_id, donor_type, donor_number, first_name, last_name,
    email, donor_category, giving_capacity
) VALUES (
    (SELECT organization_id FROM nonprofit_organizations WHERE organization_code = 'CHF001' LIMIT 1),
    'individual', 'D001', 'Sarah', 'Johnson',
    'sarah.johnson@email.com', 'recurring_donor', '1000_10000'
);

-- Insert sample donation
INSERT INTO donations (
    donor_id, organization_id, donation_number, donation_amount,
    designation, tax_year, tax_deductible_amount
) VALUES (
    (SELECT donor_id FROM donors WHERE donor_number = 'D001' LIMIT 1),
    (SELECT organization_id FROM nonprofit_organizations WHERE organization_code = 'CHF001' LIMIT 1),
    'DON001', 500.00,
    'unrestricted', 2024, 500.00
);

-- Insert sample volunteer
INSERT INTO volunteers (
    organization_id, first_name, last_name, email,
    skills_and_interests, volunteer_status
) VALUES (
    (SELECT organization_id FROM nonprofit_organizations WHERE organization_code = 'CHF001' LIMIT 1),
    'Michael', 'Chen', 'michael.chen@email.com',
    ARRAY['food_service', 'community_outreach'], 'active'
);

-- This nonprofit schema provides comprehensive infrastructure for charity management,
-- donor relations, program delivery, volunteer coordination, and regulatory compliance.
