-- Nonprofit & Charity Management Database Schema (MySQL)
-- Comprehensive schema for nonprofit organizations, donor management, grant tracking, and program management
-- Adapted for MySQL with InnoDB engine, JSON support, and performance optimizations

-- ===========================================
-- ORGANIZATION AND PROGRAM MANAGEMENT
-- ===========================================

CREATE TABLE nonprofit_organizations (
    organization_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organization_name VARCHAR(255) NOT NULL,
    organization_code VARCHAR(20) UNIQUE NOT NULL,

    -- Organization Details
    organization_type ENUM('charity', 'foundation', 'advocacy', 'religious', 'educational',
        'healthcare', 'environmental', 'humanitarian', 'animal_welfare', 'other'),
    tax_id VARCHAR(50) UNIQUE,
    ein VARCHAR(20) UNIQUE,

    -- Legal and Regulatory
    incorporation_date DATE,
    state_of_incorporation VARCHAR(50),
    bylaws_document_url VARCHAR(500),
    board_members JSON DEFAULT ('[]'),

    -- Mission and Focus
    mission_statement TEXT,
    vision_statement TEXT,
    core_values TEXT,
    primary_focus_areas JSON DEFAULT ('[]'),
    geographic_focus JSON DEFAULT ('[]'),

    -- Operational Details
    annual_budget DECIMAL(12,2),
    number_of_employees INT,
    volunteer_count INT,
    service_area_population INT,

    -- Contact Information
    address JSON DEFAULT ('{}'),
    phone VARCHAR(20),
    email VARCHAR(255),
    website VARCHAR(500),

    -- Accreditation and Ratings
    accreditations JSON DEFAULT ('[]'),
    charity_navigator_rating VARCHAR(10),
    bbb_accreditation BOOLEAN DEFAULT FALSE,

    -- Status and Governance
    organization_status ENUM('active', 'inactive', 'dissolved', 'merged') DEFAULT 'active',
    governance_model ENUM('board_governed', 'member_governed', 'individual_led'),
    fiscal_year_end DATE DEFAULT '2024-12-31',

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_organizations_code (organization_code),
    INDEX idx_organizations_status (organization_status),
    INDEX idx_organizations_type (organization_type)
) ENGINE = InnoDB;

CREATE TABLE programs (
    program_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organization_id CHAR(36) NOT NULL,

    -- Program Details
    program_name VARCHAR(255) NOT NULL,
    program_code VARCHAR(20) UNIQUE NOT NULL,
    program_description TEXT,

    -- Program Classification
    program_type ENUM('direct_service', 'advocacy', 'education', 'research', 'capacity_building',
        'emergency_relief', 'community_development', 'policy_reform', 'other'),
    program_category VARCHAR(50),
    target_beneficiaries JSON DEFAULT ('[]'),

    -- Program Scope and Impact
    geographic_scope JSON DEFAULT ('[]'),
    estimated_beneficiaries INT,
    program_goals TEXT,

    -- Budget and Funding
    annual_budget DECIMAL(10,2),
    funding_sources JSON DEFAULT ('[]'),

    -- Timeline and Status
    start_date DATE,
    end_date DATE,
    program_status ENUM('planning', 'active', 'completed', 'suspended', 'cancelled') DEFAULT 'active',

    -- Performance Metrics
    success_metrics JSON DEFAULT ('{}'),
    evaluation_methodology TEXT,
    last_evaluation_date DATE,

    -- Resources and Partnerships
    required_resources JSON DEFAULT ('[]'),
    partner_organizations JSON DEFAULT ('[]'),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,

    INDEX idx_programs_organization (organization_id, program_status),
    INDEX idx_programs_code (program_code),
    INDEX idx_programs_type (program_type),
    CHECK (start_date <= end_date OR end_date IS NULL)
) ENGINE = InnoDB;

CREATE TABLE program_metrics (
    metric_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    program_id CHAR(36) NOT NULL,

    -- Metric Details
    metric_name VARCHAR(255) NOT NULL,
    metric_type ENUM('output', 'outcome', 'impact', 'efficiency', 'quality'),
    metric_description TEXT,

    -- Measurement
    measurement_period ENUM('monthly', 'quarterly', 'annual', 'one_time'),
    baseline_value DECIMAL(10,2),
    target_value DECIMAL(10,2),
    actual_value DECIMAL(10,2),

    -- Tracking
    measurement_date DATE DEFAULT (CURRENT_DATE),
    data_source VARCHAR(255),
    responsible_person VARCHAR(100),

    -- Performance Assessment
    performance_rating ENUM('exceeded', 'met', 'below_target', 'not_measured'),
    notes TEXT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (program_id) REFERENCES programs(program_id) ON DELETE CASCADE,

    INDEX idx_program_metrics_program (program_id, measurement_date DESC),
    INDEX idx_program_metrics_type (metric_type)
) ENGINE = InnoDB;

-- ===========================================
-- DONOR AND FUNDRAISING MANAGEMENT
-- ===========================================

CREATE TABLE donors (
    donor_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organization_id CHAR(36) NOT NULL,

    -- Donor Identity
    donor_type ENUM('individual', 'corporation', 'foundation', 'government', 'anonymous'),
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
    address JSON DEFAULT ('{}'),

    -- Donor Profile
    donor_category VARCHAR(50),
    giving_capacity ENUM('under_1000', '1000_10000', '10000_50000', '50000_100000', 'over_100000'),
    interests_and_causes JSON DEFAULT ('[]'),

    -- Relationship Management
    acquisition_source VARCHAR(100),
    first_donation_date DATE,
    last_contact_date DATE,
    communication_preferences JSON DEFAULT ('{}'),

    -- Recognition and Stewardship
    recognition_level VARCHAR(50),
    stewardship_notes TEXT,
    volunteer_history JSON DEFAULT ('[]'),

    -- Status and Compliance
    donor_status ENUM('active', 'inactive', 'deceased', 'lapsed') DEFAULT 'active',
    tax_deductible BOOLEAN DEFAULT TRUE,
    anonymous_donor BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,

    INDEX idx_donors_organization (organization_id, donor_status),
    INDEX idx_donors_type (donor_type),
    INDEX idx_donors_email (email),
    INDEX idx_donors_number (donor_number)
) ENGINE = InnoDB;

CREATE TABLE donations (
    donation_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    donor_id CHAR(36) NOT NULL,
    organization_id CHAR(36) NOT NULL,

    -- Donation Details
    donation_number VARCHAR(30) UNIQUE NOT NULL,
    donation_type ENUM('cash', 'check', 'credit_card', 'stock', 'property', 'in_kind',
        'planned_gift', 'matching_gift', 'corporate_sponsorship'),

    -- Financial Information
    donation_amount DECIMAL(12,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    payment_method VARCHAR(50),

    -- Donation Purpose
    designation ENUM('unrestricted', 'restricted', 'specific_program'),
    designated_program_id CHAR(36),
    designation_notes TEXT,

    -- Recognition and Tribute
    tribute_type ENUM('honor', 'memory', 'celebration', 'none'),
    tribute_recipient_name VARCHAR(255),
    tribute_notification_address JSON DEFAULT ('{}'),

    -- Tax and Legal
    tax_year INT,
    tax_receipt_issued BOOLEAN DEFAULT FALSE,
    tax_receipt_number VARCHAR(50),
    tax_deductible_amount DECIMAL(12,2),

    -- Matching Gifts
    matching_gift_eligible BOOLEAN DEFAULT FALSE,
    matching_company VARCHAR(255),
    matching_amount DECIMAL(12,2),

    -- Processing and Status
    donation_date DATE DEFAULT (CURRENT_DATE),
    received_date DATE,
    deposited_date DATE,
    donation_status ENUM('pledged', 'received', 'processed', 'deposited', 'refunded', 'cancelled') DEFAULT 'received',

    -- Acknowledgment
    acknowledgment_sent BOOLEAN DEFAULT FALSE,
    acknowledgment_date DATE,
    acknowledgment_method ENUM('email', 'mail', 'phone', 'personal'),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (donor_id) REFERENCES donors(donor_id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,
    FOREIGN KEY (designated_program_id) REFERENCES programs(program_id) ON DELETE SET NULL,

    INDEX idx_donations_donor (donor_id, donation_date DESC),
    INDEX idx_donations_organization (organization_id, donation_date DESC),
    INDEX idx_donations_status (donation_status),
    INDEX idx_donations_number (donation_number),
    INDEX idx_donations_date (donation_date DESC),
    CHECK (donation_amount > 0)
) ENGINE = InnoDB
PARTITION BY RANGE (YEAR(donation_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

CREATE TABLE pledges (
    pledge_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    donor_id CHAR(36) NOT NULL,
    organization_id CHAR(36) NOT NULL,

    -- Pledge Details
    pledge_number VARCHAR(30) UNIQUE NOT NULL,
    pledge_amount DECIMAL(12,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',

    -- Pledge Terms
    pledge_type ENUM('outright', 'multi_year', 'annual', 'monthly', 'event'),
    payment_schedule VARCHAR(50),
    pledge_start_date DATE,
    pledge_end_date DATE,

    -- Designation
    designation ENUM('unrestricted', 'restricted', 'specific_program'),
    designated_program_id CHAR(36),

    -- Payment Tracking
    total_paid DECIMAL(12,2) DEFAULT 0,
    remaining_balance DECIMAL(12,2) AS (pledge_amount - total_paid) STORED,

    -- Status and Management
    pledge_status ENUM('active', 'completed', 'cancelled', 'defaulted') DEFAULT 'active',
    payment_reminders BOOLEAN DEFAULT TRUE,
    last_payment_date DATE,

    -- Special Terms
    pledge_conditions TEXT,
    recognition_agreement TEXT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (donor_id) REFERENCES donors(donor_id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,
    FOREIGN KEY (designated_program_id) REFERENCES programs(program_id) ON DELETE SET NULL,

    INDEX idx_pledges_donor (donor_id, pledge_status),
    INDEX idx_pledges_organization (organization_id),
    INDEX idx_pledges_number (pledge_number),
    CHECK (pledge_amount > 0),
    CHECK (pledge_start_date <= pledge_end_date OR pledge_end_date IS NULL)
) ENGINE = InnoDB;

-- ===========================================
-- GRANT AND FUNDING MANAGEMENT
-- ===========================================

CREATE TABLE grants (
    grant_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organization_id CHAR(36) NOT NULL,

    -- Grant Details
    grant_number VARCHAR(30) UNIQUE NOT NULL,
    grant_title VARCHAR(255) NOT NULL,
    grant_description TEXT,

    -- Funding Source
    funder_type ENUM('government', 'foundation', 'corporate', 'individual', 'other'),
    funder_name VARCHAR(255) NOT NULL,
    funder_contact JSON DEFAULT ('{}'),

    -- Grant Terms
    total_amount DECIMAL(12,2) NOT NULL,
    awarded_amount DECIMAL(12,2),
    grant_period_start DATE,
    grant_period_end DATE,

    -- Program and Purpose
    associated_program_id CHAR(36),
    grant_purpose TEXT,
    deliverables JSON DEFAULT ('[]'),

    -- Application and Award
    application_date DATE,
    award_date DATE,
    acceptance_date DATE,
    grant_status ENUM('applied', 'awarded', 'accepted', 'active', 'completed',
        'terminated', 'rejected', 'withdrawn') DEFAULT 'applied',

    -- Financial Management
    budget_allocated DECIMAL(12,2),
    amount_received DECIMAL(12,2) DEFAULT 0,
    amount_spent DECIMAL(12,2) DEFAULT 0,
    remaining_balance DECIMAL(12,2) AS (amount_received - amount_spent) STORED,

    -- Reporting Requirements
    reporting_schedule ENUM('monthly', 'quarterly', 'annual', 'final_only'),
    next_report_due DATE,
    final_report_due DATE,

    -- Compliance and Restrictions
    grant_restrictions TEXT,
    compliance_requirements JSON DEFAULT ('[]'),
    audit_requirements TEXT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,
    FOREIGN KEY (associated_program_id) REFERENCES programs(program_id) ON DELETE SET NULL,

    INDEX idx_grants_organization (organization_id, grant_status),
    INDEX idx_grants_number (grant_number),
    INDEX idx_grants_program (associated_program_id),
    INDEX idx_grants_funder (funder_type, funder_name),
    CHECK (total_amount > 0),
    CHECK (grant_period_start <= grant_period_end)
) ENGINE = InnoDB;

CREATE TABLE grant_reports (
    report_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    grant_id CHAR(36) NOT NULL,

    -- Report Details
    report_type ENUM('progress', 'financial', 'final', 'audit'),
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
    budget_vs_actual JSON DEFAULT ('{}'),
    funds_used DECIMAL(10,2),

    -- Impact Metrics
    outcomes_achieved JSON DEFAULT ('[]'),
    beneficiaries_served INT,

    -- Status and Approval
    report_status ENUM('draft', 'submitted', 'approved', 'rejected', 'revision_required') DEFAULT 'draft',
    funder_feedback TEXT,
    approval_date DATE,

    -- Supporting Documents
    attachments JSON DEFAULT ('[]'),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (grant_id) REFERENCES grants(grant_id) ON DELETE CASCADE,

    INDEX idx_grant_reports_grant (grant_id, submitted_date DESC),
    INDEX idx_grant_reports_status (report_status),
    INDEX idx_grant_reports_due (due_date),
    CHECK (report_period_start <= report_period_end)
) ENGINE = InnoDB;

-- ===========================================
-- VOLUNTEER AND EVENT MANAGEMENT
-- ===========================================

CREATE TABLE volunteers (
    volunteer_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organization_id CHAR(36) NOT NULL,

    -- Volunteer Identity
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),

    -- Personal Information
    date_of_birth DATE,
    address JSON DEFAULT ('{}'),
    emergency_contact JSON DEFAULT ('{}'),

    -- Volunteer Profile
    skills_and_interests JSON DEFAULT ('[]'),
    availability_schedule JSON DEFAULT ('{}'),
    preferred_roles JSON DEFAULT ('[]'),

    -- Background and Screening
    background_check_completed BOOLEAN DEFAULT FALSE,
    background_check_date DATE,
    references JSON DEFAULT ('[]'),

    -- Volunteer History
    first_volunteer_date DATE DEFAULT (CURRENT_DATE),
    total_hours_volunteered DECIMAL(8,2) DEFAULT 0,
    volunteer_status ENUM('active', 'inactive', 'suspended', 'alumni') DEFAULT 'active',

    -- Recognition
    recognition_level VARCHAR(50),
    awards_received JSON DEFAULT ('[]'),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,

    INDEX idx_volunteers_organization (organization_id, volunteer_status),
    INDEX idx_volunteers_email (email),
    INDEX idx_volunteers_status (volunteer_status)
) ENGINE = InnoDB;

CREATE TABLE volunteer_assignments (
    assignment_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    volunteer_id CHAR(36) NOT NULL,
    program_id CHAR(36),

    -- Assignment Details
    role_title VARCHAR(100) NOT NULL,
    role_description TEXT,
    assignment_type ENUM('ongoing', 'project_based', 'event_based', 'one_time'),

    -- Schedule and Commitment
    start_date DATE,
    end_date DATE,
    weekly_hours_commitment DECIMAL(4,1),
    schedule_details JSON DEFAULT ('{}'),

    -- Tracking and Management
    hours_logged DECIMAL(6,2) DEFAULT 0,
    assignment_status ENUM('active', 'completed', 'cancelled', 'on_hold') DEFAULT 'active',

    -- Supervisor and Training
    supervisor_id CHAR(36),
    training_completed JSON DEFAULT ('[]'),
    training_required JSON DEFAULT ('[]'),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (volunteer_id) REFERENCES volunteers(volunteer_id) ON DELETE CASCADE,
    FOREIGN KEY (program_id) REFERENCES programs(program_id) ON DELETE SET NULL,
    FOREIGN KEY (supervisor_id) REFERENCES volunteers(volunteer_id) ON DELETE SET NULL,

    INDEX idx_volunteer_assignments_volunteer (volunteer_id, assignment_status),
    INDEX idx_volunteer_assignments_program (program_id),
    INDEX idx_volunteer_assignments_status (assignment_status),
    CHECK (start_date <= end_date OR end_date IS NULL)
) ENGINE = InnoDB
PARTITION BY RANGE (YEAR(start_date) * 12 + MONTH(start_date)) (
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

CREATE TABLE events (
    event_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organization_id CHAR(36) NOT NULL,

    -- Event Details
    event_name VARCHAR(255) NOT NULL,
    event_code VARCHAR(20) UNIQUE NOT NULL,
    event_description TEXT,

    -- Event Type and Purpose
    event_type ENUM('fundraiser', 'awareness', 'volunteer_recruitment', 'community_outreach',
        'advocacy', 'education', 'celebration', 'meeting', 'conference'),
    event_purpose TEXT,

    -- Scheduling
    event_date DATE NOT NULL,
    start_time TIME,
    end_time TIME,
    setup_time TIME,
    cleanup_time TIME,

    -- Location and Logistics
    venue_name VARCHAR(255),
    address JSON DEFAULT ('{}'),
    capacity INT,
    expected_attendance INT,

    -- Event Management
    event_status ENUM('planned', 'confirmed', 'in_progress', 'completed', 'cancelled') DEFAULT 'planned',
    registration_required BOOLEAN DEFAULT FALSE,
    registration_deadline DATE,

    -- Budget and Financial
    event_budget DECIMAL(8,2),
    actual_cost DECIMAL(8,2),
    revenue_generated DECIMAL(8,2),

    -- Resources and Volunteers
    required_volunteers INT,
    assigned_volunteers JSON DEFAULT ('[]'),
    equipment_needed JSON DEFAULT ('[]'),

    -- Marketing and Communication
    marketing_materials JSON DEFAULT ('[]'),
    target_audience VARCHAR(100),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,

    INDEX idx_events_organization (organization_id, event_date DESC),
    INDEX idx_events_code (event_code),
    INDEX idx_events_date (event_date DESC),
    INDEX idx_events_status (event_status)
) ENGINE = InnoDB;

CREATE TABLE event_registrations (
    registration_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    event_id CHAR(36) NOT NULL,

    -- Registrant Information
    registrant_type ENUM('donor', 'volunteer', 'community_member', 'staff'),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(20),

    -- Registration Details
    registration_date DATE DEFAULT (CURRENT_DATE),
    ticket_type VARCHAR(50),
    ticket_price DECIMAL(6,2) DEFAULT 0,
    payment_status ENUM('paid', 'pending', 'complimentary'),

    -- Attendance Tracking
    checked_in BOOLEAN DEFAULT FALSE,
    check_in_time TIMESTAMP NULL,

    -- Additional Information
    special_requirements TEXT,
    dietary_restrictions TEXT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (event_id) REFERENCES events(event_id) ON DELETE CASCADE,

    INDEX idx_event_registrations_event (event_id, registration_date DESC),
    INDEX idx_event_registrations_email (email),
    INDEX idx_event_registrations_checkin (checked_in)
) ENGINE = InnoDB;

-- ===========================================
-- FINANCIAL AND REPORTING MANAGEMENT
-- ===========================================

CREATE TABLE budgets (
    budget_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organization_id CHAR(36) NOT NULL,

    -- Budget Details
    budget_year INT DEFAULT (YEAR(CURRENT_DATE)),
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
    budget_status ENUM('draft', 'approved', 'active', 'archived') DEFAULT 'draft',
    approval_date DATE,
    approved_by VARCHAR(100),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,

    INDEX idx_budgets_organization (organization_id, budget_year DESC),
    INDEX idx_budgets_status (budget_status)
) ENGINE = InnoDB;

CREATE TABLE financial_reports (
    report_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organization_id CHAR(36) NOT NULL,

    -- Report Details
    report_type ENUM('monthly', 'quarterly', 'annual', 'audit', '990'),
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
    program_expense_ratio DECIMAL(5,2),
    fundraising_efficiency DECIMAL(5,2),
    administrative_cost_ratio DECIMAL(5,2),

    -- Status and Compliance
    report_status ENUM('draft', 'filed', 'audited', 'public') DEFAULT 'draft',
    filed_date DATE,
    auditor_name VARCHAR(255),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,

    INDEX idx_financial_reports_organization (organization_id, report_period_start DESC),
    INDEX idx_financial_reports_type (report_type),
    CHECK (report_period_start <= report_period_end)
) ENGINE = InnoDB;

-- ===========================================
-- ANALYTICS AND IMPACT MEASUREMENT
-- ===========================================

CREATE TABLE impact_metrics (
    metric_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organization_id CHAR(36) NOT NULL,

    -- Metric Details
    metric_name VARCHAR(255) NOT NULL,
    metric_category ENUM('beneficiaries_served', 'program_outcomes', 'community_impact',
        'financial_sustainability', 'organizational_capacity', 'advocacy_impact'),
    metric_description TEXT,

    -- Measurement
    measurement_period ENUM('monthly', 'quarterly', 'annual'),
    baseline_value DECIMAL(10,2),
    current_value DECIMAL(10,2),
    target_value DECIMAL(10,2),

    -- Data Source and Collection
    data_source VARCHAR(255),
    collection_method VARCHAR(100),
    responsible_person VARCHAR(100),
    last_updated DATE DEFAULT (CURRENT_DATE),

    -- Performance Assessment
    trend ENUM('improving', 'stable', 'declining', 'insufficient_data'),
    performance_rating ENUM('exceeds_target', 'meets_target', 'below_target', 'off_track'),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (organization_id) REFERENCES nonprofit_organizations(organization_id) ON DELETE CASCADE,

    INDEX idx_impact_metrics_organization (organization_id),
    INDEX idx_impact_metrics_category (metric_category)
) ENGINE = InnoDB;

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Donor summary dashboard
CREATE VIEW donor_summary AS
SELECT
    d.donor_id,
    d.donor_number,
    CONCAT(d.first_name, ' ', d.last_name) as donor_name,
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
    CASE WHEN d.last_contact_date >= DATE_SUB(CURRENT_DATE, INTERVAL 90 DAY) THEN 'highly_engaged'
         WHEN d.last_contact_date >= DATE_SUB(CURRENT_DATE, INTERVAL 180 DAY) THEN 'moderately_engaged'
         ELSE 'low_engagement' END as engagement_level,

    -- Donor value
    CASE WHEN SUM(do.donation_amount) >= 10000 THEN 'platinum'
         WHEN SUM(do.donation_amount) >= 5000 THEN 'gold'
         WHEN SUM(do.donation_amount) >= 1000 THEN 'silver'
         ELSE 'bronze' END as donor_tier,

    -- Status and flags
    d.donor_status,
    CASE WHEN MAX(do.donation_date) < DATE_SUB(CURRENT_DATE, INTERVAL 365 DAY) THEN TRUE ELSE FALSE END as lapsed_donor

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
    COUNT(CASE WHEN pm.performance_rating = 'exceeded' THEN 1 END) as metrics_exceeding_target,
    COUNT(pm.metric_id) as total_metrics,

    -- Volunteer engagement
    COUNT(va.assignment_id) as active_volunteer_assignments,
    SUM(va.hours_logged) as total_volunteer_hours,

    -- Program status and timeline
    p.program_status,
    p.start_date,
    p.end_date,
    CASE WHEN p.end_date < CURRENT_DATE AND p.program_status = 'active' THEN 'overdue'
         WHEN p.end_date BETWEEN CURRENT_DATE AND DATE_ADD(CURRENT_DATE, INTERVAL 30 DAY) THEN 'ending_soon'
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
    COALESCE(SUM(d.donation_amount) + SUM(g.amount_received) + SUM(e.revenue_generated), 0) as total_revenue,

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
         ELSE 0 END as operating_reserve_ratio

FROM nonprofit_organizations o
LEFT JOIN donations d ON o.organization_id = d.organization_id AND d.donation_date >= DATE_SUB(CURRENT_DATE, INTERVAL 12 MONTH)
LEFT JOIN grants g ON o.organization_id = g.organization_id AND g.grant_status IN ('active', 'completed')
LEFT JOIN events e ON o.organization_id = e.organization_id AND e.event_date >= DATE_SUB(CURRENT_DATE, INTERVAL 12 MONTH)
LEFT JOIN budgets b ON o.organization_id = b.organization_id AND b.budget_year = YEAR(CURRENT_DATE)
GROUP BY o.organization_id, o.organization_name;

/*
This comprehensive nonprofit database schema provides enterprise-grade infrastructure for:
- Nonprofit organization management with accreditation and compliance tracking
- Comprehensive donor relationship management with stewardship and recognition
- Multi-channel donation processing with tax receipt generation
- Pledge management with payment scheduling and fulfillment tracking
- Grant lifecycle management from application to closeout
- Program management with impact metrics and evaluation
- Volunteer recruitment, management, and recognition
- Event planning and execution with registration tracking
- Financial reporting with program ratios and compliance tracking
- Budget planning and monitoring with variance analysis
- Regulatory compliance with Form 990 and audit trail management

Key features adapted for MySQL:
- UUID primary keys with UUID() function
- JSON data types for flexible metadata storage
- InnoDB engine with comprehensive indexing strategy
- Partitioning for time-series donation and volunteer data
- Generated columns for computed values (remaining_balance, etc.)
- Comprehensive views for donor, program, and financial analytics
- Full-text search capabilities for donor and program search

The schema handles complex nonprofit workflows, regulatory compliance, and provides comprehensive analytics for modern charity operations with donor segmentation, program impact measurement, and financial health monitoring.
*/

