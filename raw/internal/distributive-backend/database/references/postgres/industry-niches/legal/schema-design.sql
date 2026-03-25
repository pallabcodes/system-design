-- Legal Services & Case Management Database Schema
-- Comprehensive schema for law firms, legal case management, document handling, and compliance

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- FIRM AND ORGANIZATION MANAGEMENT
-- ===========================================

CREATE TABLE law_firms (
    firm_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_name VARCHAR(255) NOT NULL,
    firm_code VARCHAR(20) UNIQUE NOT NULL,

    -- Firm Details
    firm_type VARCHAR(30) CHECK (firm_type IN ('solo_practice', 'small_firm', 'mid_size', 'large_firm', 'corporate_legal')),
    practice_areas TEXT[], -- Criminal, Corporate, Family, Intellectual Property, etc.

    -- Business Information
    tax_id VARCHAR(50),
    bar_association_id VARCHAR(50),
    insurance_policy_number VARCHAR(100),

    -- Contact Information
    address JSONB,
    phone VARCHAR(20),
    email VARCHAR(255),
    website VARCHAR(500),

    -- Operational Details
    time_tracking_method VARCHAR(20) CHECK (time_tracking_method IN ('manual', 'automated', 'hybrid')),
    billing_cycle VARCHAR(20) CHECK (billing_cycle IN ('monthly', 'quarterly', 'case_based')),
    retainer_policy TEXT,

    -- Quality and Compliance
    malpractice_insurance_provider VARCHAR(255),
    malpractice_insurance_expiry DATE,
    last_ethics_training_date DATE,

    -- Status and Accreditation
    firm_status VARCHAR(20) DEFAULT 'active' CHECK (firm_status IN ('active', 'inactive', 'dissolved', 'merged')),
    accreditations JSONB DEFAULT '[]', -- ABA accredited, etc.

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE attorneys (
    attorney_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID NOT NULL REFERENCES law_firms(firm_id),

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),

    -- Professional Credentials
    bar_number VARCHAR(50) UNIQUE NOT NULL,
    bar_state VARCHAR(50) NOT NULL,
    admitted_date DATE,
    practice_jurisdictions TEXT[], -- States/countries where licensed

    -- Professional Details
    job_title VARCHAR(100),
    practice_areas TEXT[],
    years_experience INTEGER,
    education_history JSONB DEFAULT '[]',

    -- Compensation and Billing
    hourly_rate DECIMAL(8,2),
    billing_increment_minutes INTEGER DEFAULT 6, -- 6-minute increments = 0.1 hours
    retainer_rate DECIMAL(8,2),

    -- Availability and Workload
    work_status VARCHAR(20) DEFAULT 'active' CHECK (work_status IN ('active', 'inactive', 'retired', 'suspended')),
    current_workload_hours INTEGER DEFAULT 0,
    max_workload_hours INTEGER DEFAULT 2000,

    -- Performance Metrics
    client_satisfaction_rating DECIMAL(3,1),
    case_win_rate DECIMAL(5,2),
    average_case_value DECIMAL(10,2),

    -- System Access
    user_id UUID, -- References system users table
    permissions JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- CLIENT AND MATTER MANAGEMENT
-- ===========================================

CREATE TABLE clients (
    client_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID NOT NULL REFERENCES law_firms(firm_id),

    -- Client Identity
    client_type VARCHAR(20) CHECK (client_type IN ('individual', 'business', 'government', 'nonprofit')),
    client_number VARCHAR(20) UNIQUE,

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

    -- Client Profile
    date_of_birth DATE,
    ssn_last_four VARCHAR(4), -- Last 4 digits for identity verification
    tax_id VARCHAR(50),

    -- Client Classification
    client_tier VARCHAR(20) CHECK (client_tier IN ('platinum', 'gold', 'silver', 'bronze')),
    referral_source VARCHAR(100),
    industry VARCHAR(50),

    -- Financial Information
    credit_score INTEGER,
    payment_terms VARCHAR(50),
    billing_preferences JSONB DEFAULT '{}',

    -- Relationship Management
    assigned_attorney_id UUID REFERENCES attorneys(attorney_id),
    relationship_manager_id UUID REFERENCES attorneys(attorney_id),
    client_since DATE DEFAULT CURRENT_DATE,

    -- Status and Compliance
    client_status VARCHAR(20) DEFAULT 'active' CHECK (client_status IN ('active', 'inactive', 'former', 'deceased', 'bankrupt')),
    conflict_check_status VARCHAR(20) CHECK (conflict_check_status IN ('cleared', 'conflict_found', 'pending_review')),
    kyc_status VARCHAR(20) CHECK (kyc_status IN ('verified', 'pending', 'failed')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK ((client_type = 'business' AND company_name IS NOT NULL) OR
           (client_type = 'individual' AND first_name IS NOT NULL))
);

CREATE TABLE matters (
    matter_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID NOT NULL REFERENCES law_firms(firm_id),
    client_id UUID NOT NULL REFERENCES clients(client_id),

    -- Matter Identification
    matter_number VARCHAR(30) UNIQUE NOT NULL,
    matter_title VARCHAR(255) NOT NULL,

    -- Matter Classification
    practice_area VARCHAR(50),
    matter_type VARCHAR(50) CHECK (matter_type IN (
        'litigation', 'transaction', 'regulatory', 'intellectual_property',
        'employment', 'family', 'estate_planning', 'bankruptcy', 'immigration'
    )),
    matter_subtype VARCHAR(100),

    -- Matter Details
    description TEXT,
    opposing_party VARCHAR(255),
    court_jurisdiction VARCHAR(100),
    case_number VARCHAR(100),

    -- Legal Strategy
    legal_strategy TEXT,
    key_issues JSONB DEFAULT '[]',
    desired_outcome TEXT,

    -- Timeline and Deadlines
    opened_date DATE DEFAULT CURRENT_DATE,
    target_resolution_date DATE,
    actual_resolution_date DATE,
    statute_of_limitations DATE,

    -- Financial Information
    estimated_fee DECIMAL(12,2),
    retainer_amount DECIMAL(10,2),
    hourly_rate DECIMAL(8,2),
    flat_fee DECIMAL(10,2),

    -- Team Assignment
    lead_attorney_id UUID REFERENCES attorneys(attorney_id),
    assigned_attorneys UUID[], -- Array of attorney IDs
    paralegal_id UUID, -- References support staff
    secretary_id UUID, -- References administrative staff

    -- Matter Status and Progress
    matter_status VARCHAR(30) CHECK (matter_status IN (
        'intake', 'opened', 'discovery', 'pre_trial', 'trial', 'appeal',
        'settled', 'dismissed', 'won', 'lost', 'closed'
    )),
    priority_level VARCHAR(10) CHECK (priority_level IN ('low', 'medium', 'high', 'critical')),
    completion_percentage DECIMAL(5,2) DEFAULT 0,

    -- Confidentiality and Security
    confidentiality_level VARCHAR(20) CHECK (confidentiality_level IN ('public', 'confidential', 'privileged', 'highly_sensitive')),
    data_room_access JSONB DEFAULT '[]', -- Authorized personnel

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (opened_date <= target_resolution_date),
    CHECK (completion_percentage >= 0 AND completion_percentage <= 100)
);

-- ===========================================
-- TIME TRACKING AND BILLING
-- ===========================================

CREATE TABLE time_entries (
    time_entry_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    attorney_id UUID NOT NULL REFERENCES attorneys(attorney_id),
    matter_id UUID NOT NULL REFERENCES matters(matter_id),

    -- Time Details
    entry_date DATE DEFAULT CURRENT_DATE,
    start_time TIME,
    end_time TIME,
    duration_minutes INTEGER,

    -- Activity Details
    activity_type VARCHAR(50) CHECK (activity_type IN (
        'research', 'document_review', 'court_appearance', 'client_meeting',
        'opposing_counsel', 'deposition', 'brief_writing', 'negotiation',
        'travel', 'administration'
    )),
    activity_description TEXT,
    billable BOOLEAN DEFAULT TRUE,

    -- Billing Information
    hourly_rate DECIMAL(8,2),
    billed_amount DECIMAL(8,2) GENERATED ALWAYS AS (
        CASE WHEN billable THEN
            ROUND((duration_minutes::DECIMAL / 60) * hourly_rate, 2)
        ELSE 0 END
    ) STORED,

    -- Quality and Approval
    work_quality_rating INTEGER CHECK (work_quality_rating BETWEEN 1 AND 5),
    approved_by UUID REFERENCES attorneys(attorney_id),
    approved_at TIMESTAMP WITH TIME ZONE,

    -- Additional Details
    location VARCHAR(100),
    client_involvement BOOLEAN DEFAULT FALSE,
    internal_notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (start_time < end_time OR start_time IS NULL OR end_time IS NULL),
    CHECK (duration_minutes > 0)
);

CREATE TABLE invoices (
    invoice_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID NOT NULL REFERENCES law_firms(firm_id),
    client_id UUID NOT NULL REFERENCES clients(client_id),

    -- Invoice Details
    invoice_number VARCHAR(30) UNIQUE NOT NULL,
    invoice_date DATE DEFAULT CURRENT_DATE,
    due_date DATE NOT NULL,

    -- Invoice Content
    invoice_period_start DATE,
    invoice_period_end DATE,
    matters_included UUID[], -- Array of matter IDs

    -- Financial Amounts
    subtotal DECIMAL(10,2) NOT NULL,
    taxes DECIMAL(8,2) DEFAULT 0,
    total_amount DECIMAL(10,2) NOT NULL,

    -- Invoice Status
    invoice_status VARCHAR(20) DEFAULT 'draft' CHECK (invoice_status IN (
        'draft', 'sent', 'paid', 'overdue', 'disputed', 'written_off'
    )),
    payment_terms VARCHAR(100),
    payment_method VARCHAR(50),

    -- Collections
    collection_status VARCHAR(20) CHECK (collection_status IN ('current', 'past_due', 'collections', 'paid')),
    last_payment_date DATE,
    outstanding_balance DECIMAL(10,2),

    -- Additional Information
    invoice_notes TEXT,
    payment_instructions TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (invoice_date <= due_date),
    CHECK (invoice_period_start <= invoice_period_end)
);

CREATE TABLE invoice_items (
    invoice_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_id UUID NOT NULL REFERENCES invoices(invoice_id) ON DELETE CASCADE,

    -- Item Details
    matter_id UUID REFERENCES matters(matter_id),
    item_type VARCHAR(30) CHECK (item_type IN ('time_entry', 'expense', 'fee', 'adjustment')),
    item_description VARCHAR(255),

    -- Time Entry Reference
    time_entry_id UUID REFERENCES time_entries(time_entry_id),

    -- Financial Details
    quantity DECIMAL(8,2) DEFAULT 1,
    unit_price DECIMAL(8,2),
    line_total DECIMAL(10,2) NOT NULL,

    -- Additional Information
    taxable BOOLEAN DEFAULT TRUE,
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity > 0),
    CHECK (unit_price >= 0)
);

-- ===========================================
-- DOCUMENT AND CASE MANAGEMENT
-- ===========================================

CREATE TABLE documents (
    document_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    matter_id UUID NOT NULL REFERENCES matters(matter_id),

    -- Document Details
    document_title VARCHAR(255) NOT NULL,
    document_type VARCHAR(50) CHECK (document_type IN (
        'complaint', 'motion', 'brief', 'contract', 'deposition',
        'correspondence', 'evidence', 'pleading', 'settlement', 'other'
    )),
    document_subtype VARCHAR(100),

    -- File Information
    file_name VARCHAR(255),
    file_path VARCHAR(500),
    file_size_bytes INTEGER,
    mime_type VARCHAR(100),

    -- Document Metadata
    author_id UUID REFERENCES attorneys(attorney_id),
    created_date DATE,
    last_modified_date DATE,
    version_number DECIMAL(4,2) DEFAULT 1.0,

    -- Legal Metadata
    confidentiality_level VARCHAR(20) CHECK (confidentiality_level IN ('public', 'confidential', 'privileged')),
    privilege_log JSONB DEFAULT '[]', -- Work product privilege details
    production_status VARCHAR(20) CHECK (production_status IN ('not_produced', 'produced', 'withheld')),

    -- Document Status
    document_status VARCHAR(20) DEFAULT 'draft' CHECK (document_status IN ('draft', 'final', 'executed', 'filed', 'archived')),

    -- Security and Access
    access_control JSONB DEFAULT '[]', -- Authorized personnel
    encryption_status VARCHAR(20) CHECK (encryption_status IN ('not_encrypted', 'encrypted', 'redacted')),

    -- Court Filing Information
    filed_with_court BOOLEAN DEFAULT FALSE,
    court_filing_date DATE,
    court_docket_number VARCHAR(50),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE document_versions (
    version_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID NOT NULL REFERENCES documents(document_id) ON DELETE CASCADE,

    -- Version Details
    version_number DECIMAL(4,2) NOT NULL,
    version_label VARCHAR(50),
    change_description TEXT,

    -- File Information
    file_path VARCHAR(500),
    file_size_bytes INTEGER,

    -- Version Control
    created_by UUID REFERENCES attorneys(attorney_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (document_id, version_number)
);

CREATE TABLE case_events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    matter_id UUID NOT NULL REFERENCES matters(matter_id),

    -- Event Details
    event_type VARCHAR(50) CHECK (event_type IN (
        'filing', 'hearing', 'deposition', 'trial', 'settlement',
        'appeal', 'motion', 'discovery', 'mediation', 'arbitration'
    )),
    event_title VARCHAR(255) NOT NULL,
    event_description TEXT,

    -- Scheduling
    scheduled_date DATE NOT NULL,
    scheduled_time TIME,
    duration_hours DECIMAL(4,2),

    -- Location and Participants
    location VARCHAR(255),
    court_name VARCHAR(255),
    judge_name VARCHAR(100),
    participants JSONB DEFAULT '[]', -- Attorneys, witnesses, etc.

    -- Event Status and Outcome
    event_status VARCHAR(20) DEFAULT 'scheduled' CHECK (event_status IN (
        'scheduled', 'confirmed', 'completed', 'cancelled', 'postponed'
    )),
    event_outcome TEXT,
    court_ruling TEXT,

    -- Document Associations
    associated_documents UUID[], -- Array of document IDs
    court_filing_deadline DATE,

    -- Follow-up Actions
    follow_up_required BOOLEAN DEFAULT FALSE,
    follow_up_actions JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- CALENDAR AND DEADLINE MANAGEMENT
-- ===========================================

CREATE TABLE calendar_events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID NOT NULL REFERENCES law_firms(firm_id),

    -- Event Details
    event_title VARCHAR(255) NOT NULL,
    event_type VARCHAR(30) CHECK (event_type IN (
        'court_hearing', 'deposition', 'client_meeting', 'staff_meeting',
        'deadline', 'filing_deadline', 'conference', 'seminar', 'personal'
    )),
    event_description TEXT,

    -- Scheduling
    start_date DATE NOT NULL,
    start_time TIME,
    end_date DATE,
    end_time TIME,
    all_day_event BOOLEAN DEFAULT FALSE,

    -- Recurrence
    is_recurring BOOLEAN DEFAULT FALSE,
    recurrence_pattern VARCHAR(50), -- daily, weekly, monthly, etc.
    recurrence_end_date DATE,

    -- Participants and Assignment
    organizer_id UUID REFERENCES attorneys(attorney_id),
    attendees UUID[], -- Array of attorney/staff IDs
    matter_id UUID REFERENCES matters(matter_id),

    -- Location and Resources
    location VARCHAR(255),
    virtual_meeting_link VARCHAR(500),
    required_resources JSONB DEFAULT '[]', -- Conference rooms, equipment

    -- Status and Reminders
    event_status VARCHAR(20) DEFAULT 'confirmed' CHECK (event_status IN ('tentative', 'confirmed', 'cancelled')),
    reminder_minutes INTEGER DEFAULT 15,

    -- Privacy and Visibility
    visibility VARCHAR(20) CHECK (visibility IN ('public', 'private', 'confidential')),
    client_access BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (start_date <= end_date OR end_date IS NULL)
);

CREATE TABLE deadlines (
    deadline_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    matter_id UUID NOT NULL REFERENCES matters(matter_id),

    -- Deadline Details
    deadline_title VARCHAR(255) NOT NULL,
    deadline_type VARCHAR(50) CHECK (deadline_type IN (
        'court_filing', 'discovery', 'brief_due', 'response_due',
        'motion_deadline', 'appeal_deadline', 'statute_of_limitations'
    )),
    deadline_description TEXT,

    -- Timing
    deadline_date DATE NOT NULL,
    reminder_date DATE,
    completed_date DATE,

    -- Assignment and Responsibility
    assigned_to UUID REFERENCES attorneys(attorney_id),
    backup_assigned_to UUID REFERENCES attorneys(attorney_id), -- For redundancy

    -- Status and Tracking
    deadline_status VARCHAR(20) DEFAULT 'pending' CHECK (deadline_status IN ('pending', 'in_progress', 'completed', 'overdue', 'cancelled')),
    completion_percentage DECIMAL(5,2) DEFAULT 0,

    -- Associated Items
    associated_documents UUID[],
    associated_events UUID[],

    -- Consequences
    consequences_of_missing TEXT,
    contingency_plan TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (completion_percentage >= 0 AND completion_percentage <= 100)
);

-- ===========================================
-- FINANCIAL AND EXPENSE MANAGEMENT
-- ===========================================

CREATE TABLE expenses (
    expense_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    matter_id UUID NOT NULL REFERENCES matters(matter_id),

    -- Expense Details
    expense_type VARCHAR(50) CHECK (expense_type IN (
        'court_fees', 'filing_fees', 'expert_witness', 'travel',
        'research', 'photocopying', 'postage', 'technology', 'other'
    )),
    expense_description VARCHAR(255),
    vendor_name VARCHAR(255),

    -- Financial Details
    amount DECIMAL(10,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    tax_amount DECIMAL(8,2) DEFAULT 0,

    -- Expense Date and Billing
    expense_date DATE DEFAULT CURRENT_DATE,
    billed_to_client BOOLEAN DEFAULT TRUE,
    invoice_number VARCHAR(50),

    -- Approval Workflow
    submitted_by UUID REFERENCES attorneys(attorney_id),
    approved_by UUID REFERENCES attorneys(attorney_id),
    approval_date DATE,
    approval_status VARCHAR(20) DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected')),

    -- Supporting Documentation
    receipt_url VARCHAR(500),
    expense_report_url VARCHAR(500),
    approval_notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (amount > 0)
);

CREATE TABLE trust_accounts (
    account_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID NOT NULL REFERENCES law_firms(firm_id),
    client_id UUID NOT NULL REFERENCES clients(client_id),

    -- Account Details
    account_number VARCHAR(30) UNIQUE NOT NULL,
    account_type VARCHAR(20) CHECK (account_type IN ('client_trust', 'operating', 'retainer')),

    -- Financial Information
    current_balance DECIMAL(12,2) DEFAULT 0,
    available_balance DECIMAL(12,2) DEFAULT 0,
    minimum_balance DECIMAL(10,2) DEFAULT 0,

    -- Account Rules
    interest_bearing BOOLEAN DEFAULT FALSE,
    interest_rate DECIMAL(5,2),
    overdraft_protection BOOLEAN DEFAULT FALSE,

    -- Banking Information
    bank_name VARCHAR(255),
    routing_number VARCHAR(20),
    account_holder_name VARCHAR(255),

    -- Compliance and Auditing
    last_audit_date DATE,
    next_audit_date DATE,
    compliance_status VARCHAR(20) CHECK (compliance_status IN ('compliant', 'under_review', 'non_compliant')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE trust_transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES trust_accounts(account_id),

    -- Transaction Details
    transaction_type VARCHAR(30) CHECK (transaction_type IN (
        'deposit', 'withdrawal', 'transfer', 'interest', 'fee', 'adjustment'
    )),
    transaction_description VARCHAR(255),

    -- Financial Details
    amount DECIMAL(10,2) NOT NULL,
    transaction_date DATE DEFAULT CURRENT_DATE,
    effective_date DATE DEFAULT CURRENT_DATE,

    -- References
    matter_id UUID REFERENCES matters(matter_id),
    invoice_id UUID REFERENCES invoices(invoice_id),
    expense_id UUID REFERENCES expenses(expense_id),

    -- Authorization
    authorized_by UUID REFERENCES attorneys(attorney_id),
    authorization_method VARCHAR(20) CHECK (authorization_method IN ('signature', 'digital_signature', 'system_generated')),

    -- Banking Details
    check_number VARCHAR(20),
    bank_reference_number VARCHAR(50),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (amount != 0)
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

CREATE TABLE matter_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    matter_id UUID NOT NULL REFERENCES matters(matter_id),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_period VARCHAR(10) CHECK (report_period IN ('daily', 'weekly', 'monthly', 'quarterly')),

    -- Matter Metrics
    total_time_logged DECIMAL(8,2), -- Hours
    total_expenses DECIMAL(10,2),
    total_invoiced DECIMAL(10,2),
    outstanding_invoices DECIMAL(10,2),

    -- Progress Metrics
    tasks_completed INTEGER,
    tasks_remaining INTEGER,
    deadlines_met INTEGER,
    deadlines_missed INTEGER,

    -- Quality Metrics
    client_satisfaction_rating DECIMAL(3,1),
    internal_quality_score DECIMAL(3,1),

    -- Financial Performance
    budgeted_amount DECIMAL(12,2),
    actual_cost DECIMAL(12,2),
    cost_variance DECIMAL(10,2) GENERATED ALWAYS AS (actual_cost - budgeted_amount) STORED,
    profit_margin DECIMAL(5,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (matter_id, report_date, report_period)
);

CREATE TABLE attorney_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    attorney_id UUID NOT NULL REFERENCES attorneys(attorney_id),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_period VARCHAR(10) CHECK (report_period IN ('weekly', 'monthly', 'quarterly')),

    -- Workload Metrics
    billable_hours DECIMAL(6,2),
    non_billable_hours DECIMAL(6,2),
    total_hours DECIMAL(6,2) GENERATED ALWAYS AS (billable_hours + non_billable_hours) STORED,

    -- Productivity Metrics
    matters_handled INTEGER,
    cases_won INTEGER,
    cases_lost INTEGER,
    win_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN (cases_won + cases_lost) > 0 THEN (cases_won::DECIMAL / (cases_won + cases_lost)) * 100 ELSE 0 END
    ) STORED,

    -- Financial Metrics
    revenue_generated DECIMAL(12,2),
    average_hourly_rate DECIMAL(8,2),
    utilization_rate DECIMAL(5,2), -- Billable hours / total available hours

    -- Quality Metrics
    client_satisfaction DECIMAL(3,1),
    peer_reviews_average DECIMAL(3,1),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (attorney_id, report_date, report_period)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Firm and attorney indexes
CREATE INDEX idx_attorneys_firm ON attorneys (firm_id, work_status);
CREATE INDEX idx_attorneys_bar ON attorneys (bar_number);

-- Client and matter indexes
CREATE INDEX idx_clients_firm ON clients (firm_id, client_status);
CREATE INDEX idx_matters_firm ON matters (firm_id, matter_status);
CREATE INDEX idx_matters_client ON matters (client_id);
CREATE INDEX idx_matters_lead_attorney ON matters (lead_attorney_id);

-- Time tracking and billing indexes
CREATE INDEX idx_time_entries_attorney ON time_entries (attorney_id, entry_date DESC);
CREATE INDEX idx_time_entries_matter ON time_entries (matter_id, entry_date DESC);
CREATE INDEX idx_invoices_client ON invoices (client_id, invoice_date DESC);
CREATE INDEX idx_invoice_items_invoice ON invoice_items (invoice_id);

-- Document management indexes
CREATE INDEX idx_documents_matter ON documents (matter_id, document_type);
CREATE INDEX idx_documents_author ON documents (author_id, created_date DESC);

-- Calendar and deadline indexes
CREATE INDEX idx_calendar_events_firm ON calendar_events (firm_id, start_date);
CREATE INDEX idx_calendar_events_attendee ON calendar_events (organizer_id, start_date);
CREATE INDEX idx_deadlines_matter ON deadlines (matter_id, deadline_date);
CREATE INDEX idx_deadlines_assigned ON deadlines (assigned_to, deadline_date);

-- Financial indexes
CREATE INDEX idx_expenses_matter ON expenses (matter_id, expense_date DESC);
CREATE INDEX idx_trust_transactions_account ON trust_transactions (account_id, transaction_date DESC);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Matter overview dashboard
CREATE VIEW matter_overview AS
SELECT
    m.matter_id,
    m.matter_number,
    m.matter_title,
    m.matter_status,
    m.priority_level,

    -- Client and attorney information
    c.first_name || ' ' || c.last_name as client_name,
    c.company_name,
    a.first_name || ' ' || a.last_name as lead_attorney,

    -- Financial summary
    m.estimated_fee,
    COALESCE(SUM(te.billed_amount), 0) as total_billed,
    COALESCE(SUM(e.amount), 0) as total_expenses,
    COALESCE(SUM(i.total_amount), 0) as total_invoiced,

    -- Time and progress
    m.opened_date,
    m.target_resolution_date,
    m.completion_percentage,
    COALESCE(SUM(te.duration_minutes), 0) / 60.0 as total_hours_logged,

    -- Activity counts
    COUNT(DISTINCT te.time_entry_id) as time_entries_count,
    COUNT(DISTINCT d.document_id) as documents_count,
    COUNT(DISTINCT ce.event_id) as case_events_count,
    COUNT(DISTINCT dl.deadline_id) as active_deadlines_count,

    -- Status indicators
    CASE WHEN m.target_resolution_date < CURRENT_DATE AND m.matter_status NOT IN ('closed', 'settled', 'dismissed')
         THEN TRUE ELSE FALSE END as overdue,
    CASE WHEN COUNT(d.document_id) = 0 THEN TRUE ELSE FALSE END as missing_documents,
    CASE WHEN COUNT(te.time_entry_id) = 0 THEN TRUE ELSE FALSE END as no_time_logged

FROM matters m
LEFT JOIN clients c ON m.client_id = c.client_id
LEFT JOIN attorneys a ON m.lead_attorney_id = a.attorney_id
LEFT JOIN time_entries te ON m.matter_id = te.matter_id
LEFT JOIN expenses e ON m.matter_id = e.matter_id
LEFT JOIN invoices i ON m.client_id = i.client_id
    AND m.matter_id = ANY(i.matters_included)
LEFT JOIN documents d ON m.matter_id = d.matter_id
LEFT JOIN case_events ce ON m.matter_id = ce.matter_id
LEFT JOIN deadlines dl ON m.matter_id = dl.matter_id
    AND dl.deadline_status != 'completed'
GROUP BY m.matter_id, m.matter_number, m.matter_title, m.matter_status, m.priority_level,
         c.first_name, c.last_name, c.company_name, a.first_name, a.last_name,
         m.estimated_fee, m.opened_date, m.target_resolution_date, m.completion_percentage;

-- Attorney workload and productivity
CREATE VIEW attorney_workload AS
SELECT
    a.attorney_id,
    a.first_name || ' ' || a.last_name as attorney_name,
    a.job_title,
    a.work_status,

    -- Current workload
    a.current_workload_hours,
    a.max_workload_hours,
    ROUND((a.current_workload_hours::DECIMAL / a.max_workload_hours) * 100, 1) as workload_percentage,

    -- Recent activity (last 30 days)
    COALESCE(SUM(te.duration_minutes), 0) / 60.0 as billable_hours_last_30d,
    COUNT(DISTINCT te.matter_id) as active_matters_last_30d,
    COUNT(DISTINCT te.time_entry_id) as time_entries_last_30d,

    -- Financial performance
    a.hourly_rate,
    COALESCE(SUM(te.billed_amount), 0) as revenue_last_30d,
    CASE WHEN SUM(te.duration_minutes) > 0
         THEN (SUM(te.billed_amount) / (SUM(te.duration_minutes) / 60.0))::DECIMAL
         ELSE 0 END as effective_hourly_rate,

    -- Matter assignment
    COUNT(DISTINCT m.matter_id) as total_matters,
    COUNT(DISTINCT CASE WHEN m.matter_status IN ('opened', 'discovery', 'pre_trial', 'trial', 'appeal')
                       THEN m.matter_id END) as active_matters,
    COUNT(DISTINCT CASE WHEN m.matter_status IN ('won', 'settled') THEN m.matter_id END) as successful_matters,

    -- Performance indicators
    a.client_satisfaction_rating,
    a.case_win_rate,
    CASE WHEN a.current_workload_hours > a.max_workload_hours THEN 'overloaded'
         WHEN a.current_workload_hours > a.max_workload_hours * 0.8 THEN 'busy'
         WHEN a.current_workload_hours < a.max_workload_hours * 0.5 THEN 'underutilized'
         ELSE 'optimal' END as workload_status

FROM attorneys a
LEFT JOIN time_entries te ON a.attorney_id = te.attorney_id
    AND te.entry_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN matters m ON a.attorney_id = m.lead_attorney_id
WHERE a.work_status = 'active'
GROUP BY a.attorney_id, a.first_name, a.last_name, a.job_title, a.work_status,
         a.current_workload_hours, a.max_workload_hours, a.hourly_rate,
         a.client_satisfaction_rating, a.case_win_rate;

-- Financial overview dashboard
CREATE VIEW financial_overview AS
SELECT
    lf.firm_id,
    lf.firm_name,

    -- Revenue metrics
    COALESCE(SUM(i.total_amount), 0) as total_revenue_last_30d,
    COALESCE(AVG(i.total_amount), 0) as avg_invoice_amount,
    COUNT(CASE WHEN i.invoice_status = 'paid' THEN 1 END)::DECIMAL /
    COUNT(i.invoice_id) * 100 as payment_rate,

    -- Expense metrics
    COALESCE(SUM(e.amount), 0) as total_expenses_last_30d,
    COALESCE(SUM(CASE WHEN e.approval_status = 'pending' THEN e.amount END), 0) as pending_expenses,

    -- Trust account metrics
    COALESCE(SUM(ta.current_balance), 0) as total_trust_balance,
    COUNT(CASE WHEN ta.current_balance < ta.minimum_balance THEN 1 END) as accounts_below_minimum,

    -- Time billing metrics
    COALESCE(SUM(te.billed_amount), 0) as total_time_billing_last_30d,
    COALESCE(SUM(te.duration_minutes), 0) / 60.0 as total_hours_logged,
    CASE WHEN SUM(te.duration_minutes) > 0
         THEN (SUM(te.billed_amount) / (SUM(te.duration_minutes) / 60.0))::DECIMAL
         ELSE 0 END as average_hourly_rate,

    -- Outstanding receivables
    COALESCE(SUM(CASE WHEN i.invoice_status != 'paid' THEN i.total_amount END), 0) as total_outstanding,
    COUNT(CASE WHEN i.due_date < CURRENT_DATE AND i.invoice_status != 'paid' THEN 1 END) as overdue_invoices,

    -- Profitability indicators
    CASE WHEN SUM(i.total_amount) > 0
         THEN ROUND(((SUM(i.total_amount) - SUM(e.amount)) / SUM(i.total_amount)) * 100, 1)
         ELSE 0 END as profit_margin_percentage

FROM law_firms lf
LEFT JOIN attorneys a ON lf.firm_id = a.firm_id
LEFT JOIN time_entries te ON a.attorney_id = te.attorney_id
    AND te.entry_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN invoices i ON lf.firm_id = i.firm_id
    AND i.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN expenses e ON lf.firm_id = e.firm_id
    AND e.expense_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN trust_accounts ta ON lf.firm_id = ta.firm_id
GROUP BY lf.firm_id, lf.firm_name;

-- ===========================================
-- FUNCTIONS FOR LEGAL OPERATIONS
-- =========================================--

-- Function to calculate matter profitability
CREATE OR REPLACE FUNCTION calculate_matter_profitability(matter_uuid UUID)
RETURNS TABLE (
    total_revenue DECIMAL,
    total_expenses DECIMAL,
    total_time_cost DECIMAL,
    net_profit DECIMAL,
    profit_margin DECIMAL,
    roi_percentage DECIMAL
) AS $$
DECLARE
    revenue_total DECIMAL := 0;
    expense_total DECIMAL := 0;
    time_cost_total DECIMAL := 0;
BEGIN
    -- Calculate total revenue from invoices
    SELECT COALESCE(SUM(ii.line_total), 0) INTO revenue_total
    FROM invoice_items ii
    JOIN invoices i ON ii.invoice_id = i.invoice_id
    WHERE i.invoice_status = 'paid'
      AND ii.matter_id = matter_uuid;

    -- Calculate total expenses
    SELECT COALESCE(SUM(amount), 0) INTO expense_total
    FROM expenses
    WHERE matter_id = matter_uuid
      AND approval_status = 'approved';

    -- Calculate time costs (opportunity cost)
    SELECT COALESCE(SUM(billed_amount), 0) INTO time_cost_total
    FROM time_entries
    WHERE matter_id = matter_uuid;

    RETURN QUERY SELECT
        revenue_total,
        expense_total,
        time_cost_total,
        revenue_total - expense_total - time_cost_total,
        CASE WHEN revenue_total > 0 THEN ((revenue_total - expense_total - time_cost_total) / revenue_total) * 100 ELSE 0 END,
        CASE WHEN (expense_total + time_cost_total) > 0 THEN ((revenue_total - expense_total - time_cost_total) / (expense_total + time_cost_total)) * 100 ELSE 0 END;
END;
$$ LANGUAGE plpgsql;

-- Function to check for conflicts of interest
CREATE OR REPLACE FUNCTION check_conflicts_of_interest(
    client_uuid UUID,
    attorney_uuid UUID,
    matter_description TEXT DEFAULT NULL
)
RETURNS TABLE (
    conflict_detected BOOLEAN,
    conflict_type VARCHAR,
    conflict_description TEXT,
    severity_level VARCHAR,
    recommended_action TEXT
) AS $$
DECLARE
    client_record clients%ROWTYPE;
    attorney_record attorneys%ROWTYPE;
    existing_matters INTEGER := 0;
BEGIN
    -- Get client and attorney details
    SELECT * INTO client_record FROM clients WHERE client_id = client_uuid;
    SELECT * INTO attorney_record FROM attorneys WHERE attorney_id = attorney_uuid;

    -- Check for existing representation conflicts
    SELECT COUNT(*) INTO existing_matters
    FROM matters m
    WHERE m.client_id = client_uuid
       OR m.opposing_party = client_record.company_name
       OR m.opposing_party = client_record.first_name || ' ' || client_record.last_name;

    -- Check for personal conflicts
    IF existing_matters > 0 THEN
        RETURN QUERY SELECT
            TRUE::BOOLEAN,
            'existing_representation'::VARCHAR,
            'Attorney or firm has previously represented or is currently representing a conflicting party'::TEXT,
            'high'::VARCHAR,
            'Decline representation or obtain informed consent from all parties'::TEXT;
        RETURN;
    END IF;

    -- Check for business relationship conflicts
    IF client_record.industry = 'competitor' THEN
        RETURN QUERY SELECT
            TRUE::BOOLEAN,
            'business_relationship'::VARCHAR,
            'Client operates in a competitive industry with existing firm clients'::TEXT,
            'medium'::VARCHAR,
            'Implement information barriers and obtain client consent'::TEXT;
        RETURN;
    END IF;

    -- No conflicts detected
    RETURN QUERY SELECT
        FALSE::BOOLEAN,
        NULL::VARCHAR,
        'No conflicts of interest detected'::TEXT,
        'none'::VARCHAR,
        'Proceed with representation'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- Function to generate invoice from time entries
CREATE OR REPLACE FUNCTION generate_invoice_from_time_entries(
    client_uuid UUID,
    invoice_period_start DATE,
    invoice_period_end DATE,
    matter_ids UUID[] DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    invoice_uuid UUID;
    subtotal_val DECIMAL := 0;
    tax_rate DECIMAL := 0.08;
    invoice_number_val VARCHAR(30);
BEGIN
    -- Generate invoice number
    invoice_number_val := 'INV-' || UPPER(SUBSTRING(uuid_generate_v4()::TEXT, 1, 8));

    -- Calculate subtotal from time entries
    SELECT COALESCE(SUM(te.billed_amount), 0) INTO subtotal_val
    FROM time_entries te
    JOIN matters m ON te.matter_id = m.matter_id
    WHERE m.client_id = client_uuid
      AND te.entry_date BETWEEN invoice_period_start AND invoice_period_end
      AND te.approved_at IS NOT NULL
      AND (matter_ids IS NULL OR te.matter_id = ANY(matter_ids));

    -- Create invoice
    INSERT INTO invoices (
        firm_id, client_id, invoice_number,
        invoice_period_start, invoice_period_end,
        subtotal, taxes, total_amount
    )
    SELECT
        c.firm_id, client_uuid, invoice_number_val,
        invoice_period_start, invoice_period_end,
        subtotal_val, subtotal_val * tax_rate, subtotal_val * (1 + tax_rate)
    FROM clients c WHERE c.client_id = client_uuid
    RETURNING invoice_id INTO invoice_uuid;

    -- Create invoice items from time entries
    INSERT INTO invoice_items (
        invoice_id, matter_id, item_type, item_description,
        time_entry_id, unit_price, line_total
    )
    SELECT
        invoice_uuid, te.matter_id, 'time_entry',
        'Legal services - ' || te.activity_type || ' on ' || te.entry_date::TEXT,
        te.time_entry_id, te.hourly_rate, te.billed_amount
    FROM time_entries te
    JOIN matters m ON te.matter_id = m.matter_id
    WHERE m.client_id = client_uuid
      AND te.entry_date BETWEEN invoice_period_start AND invoice_period_end
      AND te.approved_at IS NOT NULL
      AND (matter_ids IS NULL OR te.matter_id = ANY(matter_ids));

    RETURN invoice_uuid;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample law firm
INSERT INTO law_firms (
    firm_name, firm_code, firm_type, practice_areas,
    billing_cycle, time_tracking_method
) VALUES (
    'Smith & Associates LLP', 'SAA001', 'mid_size',
    ARRAY['corporate', 'litigation', 'intellectual_property'],
    'monthly', 'automated'
);

-- Insert sample attorney
INSERT INTO attorneys (
    firm_id, first_name, last_name, bar_number, bar_state,
    job_title, practice_areas, hourly_rate, years_experience
) VALUES (
    (SELECT firm_id FROM law_firms WHERE firm_code = 'SAA001' LIMIT 1),
    'John', 'Smith', 'JS123456', 'CA',
    'Senior Partner', ARRAY['corporate', 'litigation'], 450.00, 15
);

-- Insert sample client
INSERT INTO clients (
    firm_id, client_number, client_type, company_name,
    contact_person, email, client_tier, industry
) VALUES (
    (SELECT firm_id FROM law_firms WHERE firm_code = 'SAA001' LIMIT 1),
    'CLT001', 'business', 'TechCorp Inc',
    'Jane Doe', 'jane.doe@techcorp.com', 'gold', 'technology'
);

-- Insert sample matter
INSERT INTO matters (
    firm_id, client_id, matter_number, matter_title,
    practice_area, matter_type, opened_date, estimated_fee,
    lead_attorney_id, matter_status
) VALUES (
    (SELECT firm_id FROM law_firms WHERE firm_code = 'SAA001' LIMIT 1),
    (SELECT client_id FROM clients WHERE client_number = 'CLT001' LIMIT 1),
    'MAT001', 'Corporate Merger Transaction',
    'corporate', 'transaction', '2024-01-15', 50000.00,
    (SELECT attorney_id FROM attorneys WHERE bar_number = 'JS123456' LIMIT 1),
    'opened'
);

-- Insert sample time entry
INSERT INTO time_entries (
    attorney_id, matter_id, activity_type, billable,
    duration_minutes, hourly_rate
) VALUES (
    (SELECT attorney_id FROM attorneys WHERE bar_number = 'JS123456' LIMIT 1),
    (SELECT matter_id FROM matters WHERE matter_number = 'MAT001' LIMIT 1),
    'client_meeting', TRUE,
    120, 450.00
);

-- Insert sample document
INSERT INTO documents (
    matter_id, document_title, document_type,
    author_id, document_status
) VALUES (
    (SELECT matter_id FROM matters WHERE matter_number = 'MAT001' LIMIT 1),
    'Merger Agreement Draft', 'contract',
    (SELECT attorney_id FROM attorneys WHERE bar_number = 'JS123456' LIMIT 1),
    'draft'
);

-- This legal services schema provides comprehensive infrastructure for law firm operations,
-- case management, time tracking, billing, and regulatory compliance.
