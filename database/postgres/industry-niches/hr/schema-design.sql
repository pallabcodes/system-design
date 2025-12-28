-- HR & Recruitment Platform Database Schema
-- Comprehensive schema for Human Resources Management and Recruitment Systems

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text search on resumes
CREATE EXTENSION IF NOT EXISTS "unaccent"; -- For accent-insensitive search

-- ===========================================
-- ORGANIZATIONAL STRUCTURE
-- ===========================================

CREATE TABLE companies (
    company_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_name VARCHAR(255) NOT NULL,
    legal_name VARCHAR(255),
    tax_id VARCHAR(50) UNIQUE,
    industry VARCHAR(100),
    company_size VARCHAR(20) CHECK (company_size IN ('startup', 'small', 'medium', 'large', 'enterprise')),
    website VARCHAR(500),
    logo_url VARCHAR(500),

    -- Contact Information
    address_line_1 VARCHAR(255),
    address_line_2 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',

    -- Business Details
    founded_date DATE,
    revenue_range VARCHAR(50),
    description TEXT,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE departments (
    department_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    department_name VARCHAR(100) NOT NULL,
    department_code VARCHAR(10) UNIQUE NOT NULL,
    parent_department_id UUID REFERENCES departments(department_id),
    department_head_id UUID, -- References employees(employee_id), set later
    budget DECIMAL(15,2),
    location VARCHAR(255),

    -- Hierarchy level
    hierarchy_level INTEGER DEFAULT 1,
    sort_order INTEGER DEFAULT 0,

    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (company_id, department_code)
);

CREATE TABLE job_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    department_id UUID NOT NULL REFERENCES departments(department_id) ON DELETE CASCADE,
    position_title VARCHAR(255) NOT NULL,
    position_code VARCHAR(20) UNIQUE NOT NULL,
    position_level VARCHAR(30) CHECK (position_level IN ('entry', 'junior', 'mid', 'senior', 'lead', 'manager', 'director', 'executive')),

    -- Job Details
    job_description TEXT,
    requirements TEXT,
    responsibilities TEXT,

    -- Compensation
    salary_min DECIMAL(12,2),
    salary_max DECIMAL(12,2),
    salary_currency CHAR(3) DEFAULT 'USD',
    benefits JSONB DEFAULT '{}', -- health, dental, retirement, etc.

    -- Employment Type
    employment_type VARCHAR(20) DEFAULT 'full_time' CHECK (employment_type IN ('full_time', 'part_time', 'contract', 'temporary', 'internship', 'freelance')),
    work_arrangement VARCHAR(20) DEFAULT 'office' CHECK (work_arrangement IN ('office', 'remote', 'hybrid')),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- EMPLOYEE MANAGEMENT
-- ===========================================

CREATE TABLE employees (
    employee_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    user_id UUID UNIQUE, -- References global users table

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,

    -- Employment Details
    employee_number VARCHAR(20) UNIQUE NOT NULL,
    hire_date DATE NOT NULL,
    termination_date DATE,
    employment_status VARCHAR(20) DEFAULT 'active' CHECK (employment_status IN ('active', 'terminated', 'on_leave', 'suspended')),

    -- Position Information
    position_id UUID REFERENCES job_positions(position_id),
    department_id UUID REFERENCES departments(department_id),
    manager_id UUID REFERENCES employees(employee_id),
    reports_to UUID REFERENCES employees(employee_id), -- Same as manager_id but more flexible

    -- Compensation
    salary DECIMAL(12,2),
    salary_currency CHAR(3) DEFAULT 'USD',
    pay_frequency VARCHAR(20) DEFAULT 'monthly' CHECK (pay_frequency IN ('weekly', 'biweekly', 'monthly', 'quarterly')),

    -- Work Details
    work_location VARCHAR(255),
    work_arrangement VARCHAR(20) DEFAULT 'office',
    office_location VARCHAR(255),

    -- Demographics
    gender VARCHAR(20),
    ethnicity VARCHAR(50),
    nationality VARCHAR(50),

    -- Emergency Contact
    emergency_contact_name VARCHAR(200),
    emergency_contact_phone VARCHAR(20),
    emergency_contact_relationship VARCHAR(50),

    -- System Fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID
);

-- Update department head reference
ALTER TABLE departments ADD CONSTRAINT fk_department_head
    FOREIGN KEY (department_head_id) REFERENCES employees(employee_id);

-- ===========================================
-- RECRUITMENT & TALENT ACQUISITION
-- ===========================================

CREATE TABLE job_postings (
    job_posting_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    position_id UUID NOT NULL REFERENCES job_positions(position_id),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Posting Details
    job_title VARCHAR(255) NOT NULL,
    job_description TEXT NOT NULL,
    requirements TEXT,
    benefits TEXT,

    -- Compensation (may differ from position for specific posting)
    salary_range_min DECIMAL(12,2),
    salary_range_max DECIMAL(12,2),
    salary_currency CHAR(3) DEFAULT 'USD',

    -- Posting Settings
    employment_type VARCHAR(20) DEFAULT 'full_time',
    work_arrangement VARCHAR(20) DEFAULT 'office',
    application_deadline DATE,

    -- Status and Visibility
    posting_status VARCHAR(20) DEFAULT 'draft' CHECK (posting_status IN ('draft', 'published', 'closed', 'filled', 'cancelled')),
    is_remote_friendly BOOLEAN DEFAULT FALSE,
    featured BOOLEAN DEFAULT FALSE,

    -- Posting Metadata
    posted_by UUID NOT NULL REFERENCES employees(employee_id),
    posted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP WITH TIME ZONE,
    closed_at TIMESTAMP WITH TIME ZONE,

    -- Application tracking
    application_count INTEGER DEFAULT 0,
    view_count INTEGER DEFAULT 0,

    -- Search optimization
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', COALESCE(job_title, '') || ' ' || COALESCE(job_description, '') || ' ' || COALESCE(requirements, ''))
    ) STORED,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE candidates (
    candidate_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE, -- References global users table

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),

    -- Profile
    headline VARCHAR(255), -- Professional summary
    bio TEXT,
    profile_picture_url VARCHAR(500),
    resume_url VARCHAR(500),

    -- Location Preferences
    current_location VARCHAR(255),
    preferred_locations TEXT[], -- Array of preferred locations
    willing_to_relocate BOOLEAN DEFAULT FALSE,
    remote_work_preference VARCHAR(20) DEFAULT 'open' CHECK (remote_work_preference IN ('remote_only', 'office_only', 'hybrid', 'open')),

    -- Work Preferences
    desired_salary_min DECIMAL(12,2),
    desired_salary_max DECIMAL(12,2),
    desired_employment_type VARCHAR(20) DEFAULT 'full_time',
    available_start_date DATE,

    -- Demographics (optional)
    date_of_birth DATE,
    gender VARCHAR(20),
    ethnicity VARCHAR(50),

    -- Profile Status
    profile_completion_percentage DECIMAL(5,2) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,

    -- Search and matching
    skills TEXT[],
    search_vector TSVECTOR,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE applications (
    application_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_posting_id UUID NOT NULL REFERENCES job_postings(job_posting_id),
    candidate_id UUID NOT NULL REFERENCES candidates(candidate_id),

    -- Application Details
    application_status VARCHAR(30) DEFAULT 'submitted' CHECK (application_status IN (
        'submitted', 'under_review', 'phone_screen', 'interview_scheduled',
        'interview_completed', 'offer_extended', 'offer_accepted', 'offer_declined',
        'rejected', 'withdrawn'
    )),

    -- Cover letter and documents
    cover_letter TEXT,
    resume_url VARCHAR(500),
    portfolio_url VARCHAR(500),
    additional_documents JSONB DEFAULT '[]', -- Array of document URLs

    -- Application Timeline
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    rejected_at TIMESTAMP WITH TIME ZONE,

    -- Interview and offer details
    interview_scheduled_at TIMESTAMP WITH TIME ZONE,
    interview_completed_at TIMESTAMP WITH TIME ZONE,
    offer_extended_at TIMESTAMP WITH TIME ZONE,
    offer_amount DECIMAL(12,2),
    offer_accepted_at TIMESTAMP WITH TIME ZONE,

    -- Feedback and notes
    internal_notes TEXT,
    rejection_reason VARCHAR(100),
    candidate_rating DECIMAL(3,1) CHECK (candidate_rating >= 1 AND candidate_rating <= 5),

    -- Assigned recruiters/reviewers
    primary_recruiter_id UUID REFERENCES employees(employee_id),
    secondary_recruiter_id UUID REFERENCES employees(employee_id),

    -- Source tracking
    application_source VARCHAR(50) DEFAULT 'website', -- website, referral, job_board, agency
    referral_employee_id UUID REFERENCES employees(employee_id),
    source_campaign VARCHAR(100),

    UNIQUE (job_posting_id, candidate_id)
);

-- ===========================================
-- PERFORMANCE MANAGEMENT
-- ===========================================

CREATE TABLE performance_reviews (
    review_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(employee_id),
    reviewer_id UUID NOT NULL REFERENCES employees(employee_id),

    -- Review Details
    review_type VARCHAR(30) NOT NULL CHECK (review_type IN ('annual', 'mid_year', 'probation', 'project', 'ad_hoc')),
    review_period_start DATE NOT NULL,
    review_period_end DATE NOT NULL,

    -- Ratings and Feedback
    overall_rating DECIMAL(3,1) CHECK (overall_rating >= 1 AND overall_rating <= 5),
    strengths TEXT,
    areas_for_improvement TEXT,
    goals_achieved TEXT,
    goals_missed TEXT,
    development_plan TEXT,

    -- Competency Ratings
    technical_skills_rating DECIMAL(3,1) CHECK (technical_skills_rating >= 1 AND technical_skills_rating <= 5),
    communication_rating DECIMAL(3,1) CHECK (communication_rating >= 1 AND communication_rating <= 5),
    leadership_rating DECIMAL(3,1) CHECK (leadership_rating >= 1 AND leadership_rating <= 5),
    teamwork_rating DECIMAL(3,1) CHECK (teamwork_rating >= 1 AND teamwork_rating <= 5),

    -- Status
    review_status VARCHAR(20) DEFAULT 'draft' CHECK (review_status IN ('draft', 'submitted', 'employee_reviewed', 'completed', 'cancelled')),
    is_self_review BOOLEAN DEFAULT FALSE,

    -- Timeline
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMP WITH TIME ZONE,
    employee_acknowledged_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Additional Data
    review_form_data JSONB DEFAULT '{}', -- Flexible form data
    attachments JSONB DEFAULT '[]', -- Supporting documents

    CHECK (review_period_start < review_period_end)
);

CREATE TABLE goals (
    goal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(employee_id),
    review_id UUID REFERENCES performance_reviews(review_id),

    -- Goal Details
    goal_title VARCHAR(300) NOT NULL,
    goal_description TEXT,
    goal_category VARCHAR(50) DEFAULT 'professional' CHECK (goal_category IN ('professional', 'personal', 'team', 'organizational')),

    -- Timeline
    start_date DATE,
    target_completion_date DATE,
    actual_completion_date DATE,

    -- Progress Tracking
    progress_percentage DECIMAL(5,2) DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),
    status VARCHAR(20) DEFAULT 'not_started' CHECK (status IN ('not_started', 'in_progress', 'completed', 'cancelled', 'on_hold')),

    -- Metrics
    measurement_criteria TEXT,
    target_value VARCHAR(100),
    current_value VARCHAR(100),

    -- Approval and Review
    created_by UUID NOT NULL REFERENCES employees(employee_id),
    approved_by UUID REFERENCES employees(employee_id),
    approved_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- TIME TRACKING & ATTENDANCE
-- ===========================================

CREATE TABLE time_entries (
    time_entry_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(employee_id),

    -- Time Details
    clock_in_time TIMESTAMP WITH TIME ZONE NOT NULL,
    clock_out_time TIMESTAMP WITH TIME ZONE,
    break_start_time TIMESTAMP WITH TIME ZONE,
    break_end_time TIMESTAMP WITH TIME ZONE,

    -- Calculated Fields
    total_hours DECIMAL(6,2) GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (clock_out_time - clock_in_time)) / 3600
    ) STORED,
    break_hours DECIMAL(6,2) GENERATED ALWAYS AS (
        CASE WHEN break_start_time IS NOT NULL AND break_end_time IS NOT NULL
             THEN EXTRACT(EPOCH FROM (break_end_time - break_start_time)) / 3600
             ELSE 0 END
    ) STORED,
    productive_hours DECIMAL(6,2) GENERATED ALWAYS AS (
        total_hours - break_hours
    ) STORED,

    -- Work Details
    work_date DATE NOT NULL DEFAULT CURRENT_DATE,
    project_id UUID, -- References project if applicable
    task_description TEXT,
    work_location VARCHAR(255),

    -- Status
    entry_status VARCHAR(20) DEFAULT 'active' CHECK (entry_status IN ('active', 'submitted', 'approved', 'rejected')),
    submitted_at TIMESTAMP WITH TIME ZONE,
    approved_by UUID REFERENCES employees(employee_id),
    approved_at TIMESTAMP WITH TIME ZONE,

    -- Notes
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (clock_in_time < clock_out_time),
    CHECK (break_start_time IS NULL OR (break_start_time >= clock_in_time AND break_start_time <= clock_out_time)),
    CHECK (break_end_time IS NULL OR (break_end_time >= break_start_time AND break_end_time <= clock_out_time))
);

CREATE TABLE attendance_records (
    attendance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(employee_id),
    attendance_date DATE NOT NULL,

    -- Attendance Status
    status VARCHAR(20) NOT NULL DEFAULT 'present' CHECK (status IN ('present', 'absent', 'late', 'half_day', 'holiday', 'sick_leave', 'vacation', 'personal_leave')),

    -- Time Details
    scheduled_start_time TIME,
    scheduled_end_time TIME,
    actual_start_time TIME,
    actual_end_time TIME,

    -- Hours
    scheduled_hours DECIMAL(4,2),
    actual_hours DECIMAL(4,2),

    -- Leave Details (if applicable)
    leave_type VARCHAR(30),
    leave_reason TEXT,

    -- Approval
    approved_by UUID REFERENCES employees(employee_id),
    approved_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (employee_id, attendance_date)
);

-- ===========================================
-- LEARNING & DEVELOPMENT
-- ===========================================

CREATE TABLE training_programs (
    program_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(company_id),

    -- Program Details
    program_name VARCHAR(255) NOT NULL,
    program_description TEXT,
    program_type VARCHAR(30) CHECK (program_type IN ('technical', 'soft_skills', 'compliance', 'leadership', 'certification')),

    -- Duration and Format
    duration_hours DECIMAL(6,2),
    delivery_method VARCHAR(30) CHECK (delivery_method IN ('in_person', 'online', 'blended', 'self_paced')),
    max_participants INTEGER,

    -- Scheduling
    start_date DATE,
    end_date DATE,

    -- Status
    program_status VARCHAR(20) DEFAULT 'planned' CHECK (program_status IN ('planned', 'active', 'completed', 'cancelled')),

    -- Instructor and Provider
    instructor_id UUID REFERENCES employees(employee_id),
    external_provider VARCHAR(255),
    cost_per_participant DECIMAL(8,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE employee_training (
    training_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(employee_id),
    program_id UUID NOT NULL REFERENCES training_programs(program_id),

    -- Enrollment and Progress
    enrollment_date DATE DEFAULT CURRENT_DATE,
    completion_date DATE,
    progress_percentage DECIMAL(5,2) DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),

    -- Assessment
    pre_assessment_score DECIMAL(5,2),
    post_assessment_score DECIMAL(5,2),
    certification_earned VARCHAR(255),

    -- Status
    training_status VARCHAR(20) DEFAULT 'enrolled' CHECK (training_status IN ('enrolled', 'in_progress', 'completed', 'dropped', 'failed')),

    -- Feedback
    employee_feedback TEXT,
    trainer_feedback TEXT,
    overall_rating DECIMAL(3,1) CHECK (overall_rating >= 1 AND overall_rating <= 5),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (employee_id, program_id)
);

-- ===========================================
-- COMPENSATION & BENEFITS
-- ===========================================

CREATE TABLE salary_history (
    salary_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(employee_id),

    -- Salary Details
    salary_amount DECIMAL(12,2) NOT NULL,
    salary_currency CHAR(3) DEFAULT 'USD',
    pay_frequency VARCHAR(20) DEFAULT 'monthly',

    -- Effective Dates
    effective_date DATE NOT NULL,
    end_date DATE,

    -- Change Details
    salary_change_type VARCHAR(30) CHECK (salary_change_type IN ('hire', 'merit_increase', 'promotion', 'cost_of_living', 'correction', 'demotion')),
    change_reason TEXT,
    performance_rating DECIMAL(3,1),

    -- Approval
    approved_by UUID REFERENCES employees(employee_id),
    approved_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (effective_date <= COALESCE(end_date, CURRENT_DATE))
);

CREATE TABLE benefits_enrollment (
    enrollment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(employee_id),

    -- Benefit Details
    benefit_type VARCHAR(50) NOT NULL, -- health_insurance, dental, vision, retirement, etc.
    benefit_plan VARCHAR(100),
    coverage_level VARCHAR(30), -- employee_only, employee_spouse, family, etc.

    -- Enrollment Period
    enrollment_date DATE DEFAULT CURRENT_DATE,
    effective_date DATE,
    termination_date DATE,

    -- Cost Information
    employee_contribution DECIMAL(8,2),
    employer_contribution DECIMAL(8,2),

    -- Status
    enrollment_status VARCHAR(20) DEFAULT 'active' CHECK (enrollment_status IN ('active', 'terminated', 'pending', 'denied')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Employee indexes
CREATE INDEX idx_employees_company ON employees (company_id);
CREATE INDEX idx_employees_department ON employees (department_id);
CREATE INDEX idx_employees_manager ON employees (manager_id);
CREATE INDEX idx_employees_status ON employees (employment_status);
CREATE INDEX idx_employees_hire_date ON employees (hire_date);

-- Job posting indexes
CREATE INDEX idx_job_postings_company ON job_postings (company_id);
CREATE INDEX idx_job_postings_position ON job_postings (position_id);
CREATE INDEX idx_job_postings_status ON job_postings (posting_status);
CREATE INDEX idx_job_postings_search ON job_postings USING gin (search_vector);

-- Application indexes
CREATE INDEX idx_applications_job_posting ON applications (job_posting_id);
CREATE INDEX idx_applications_candidate ON applications (candidate_id);
CREATE INDEX idx_applications_status ON applications (application_status);
CREATE INDEX idx_applications_submitted ON applications (submitted_at DESC);

-- Performance review indexes
CREATE INDEX idx_performance_reviews_employee ON performance_reviews (employee_id);
CREATE INDEX idx_performance_reviews_reviewer ON performance_reviews (reviewer_id);
CREATE INDEX idx_performance_reviews_period ON performance_reviews (review_period_start, review_period_end);

-- Time tracking indexes
CREATE INDEX idx_time_entries_employee ON time_entries (employee_id);
CREATE INDEX idx_time_entries_date ON time_entries (work_date);
CREATE INDEX idx_time_entries_status ON time_entries (entry_status);

-- Training indexes
CREATE INDEX idx_employee_training_employee ON employee_training (employee_id);
CREATE INDEX idx_employee_training_program ON employee_training (program_id);
CREATE INDEX idx_employee_training_status ON employee_training (training_status);

-- ===========================================
-- USEFUL VIEWS
-- =========================================--

-- Employee hierarchy view
CREATE VIEW employee_hierarchy AS
WITH RECURSIVE emp_hierarchy AS (
    -- Base case: top-level employees (no manager)
    SELECT
        employee_id,
        first_name,
        last_name,
        position_id,
        department_id,
        manager_id,
        0 as hierarchy_level,
        ARRAY[employee_id] as path
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- Recursive case: employees with managers
    SELECT
        e.employee_id,
        e.first_name,
        e.last_name,
        e.position_id,
        e.department_id,
        e.manager_id,
        eh.hierarchy_level + 1,
        eh.path || e.employee_id
    FROM employees e
    JOIN emp_hierarchy eh ON e.manager_id = eh.employee_id
)
SELECT * FROM emp_hierarchy;

-- Comprehensive employee profile view
CREATE VIEW employee_profiles AS
SELECT
    e.*,
    jp.position_title,
    d.department_name,
    m.first_name as manager_first_name,
    m.last_name as manager_last_name,
    c.company_name,

    -- Latest salary
    (SELECT salary_amount FROM salary_history sh
     WHERE sh.employee_id = e.employee_id
     ORDER BY effective_date DESC LIMIT 1) as current_salary,

    -- Performance rating
    (SELECT overall_rating FROM performance_reviews pr
     WHERE pr.employee_id = e.employee_id
     ORDER BY review_period_end DESC LIMIT 1) as latest_performance_rating,

    -- Years of service
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, e.hire_date)) as years_of_service,

    -- Active benefits count
    (SELECT COUNT(*) FROM benefits_enrollment be
     WHERE be.employee_id = e.employee_id
       AND be.enrollment_status = 'active') as active_benefits_count

FROM employees e
LEFT JOIN job_positions jp ON e.position_id = jp.position_id
LEFT JOIN departments d ON e.department_id = d.department_id
LEFT JOIN employees m ON e.manager_id = m.employee_id
LEFT JOIN companies c ON e.company_id = c.company_id;

-- Job application analytics view
CREATE VIEW job_application_analytics AS
SELECT
    jp.job_posting_id,
    jp.job_title,
    jp.posted_at,
    jp.application_deadline,
    jp.application_count,
    jp.view_count,

    -- Application status breakdown
    COUNT(CASE WHEN a.application_status = 'submitted' THEN 1 END) as submitted_count,
    COUNT(CASE WHEN a.application_status = 'under_review' THEN 1 END) as under_review_count,
    COUNT(CASE WHEN a.application_status = 'interview_scheduled' THEN 1 END) as interview_count,
    COUNT(CASE WHEN a.application_status = 'offer_extended' THEN 1 END) as offer_count,
    COUNT(CASE WHEN a.application_status = 'offer_accepted' THEN 1 END) as hire_count,

    -- Time to hire metrics
    AVG(EXTRACT(EPOCH FROM (a.offer_accepted_at - a.submitted_at))/86400) as avg_days_to_hire,
    MIN(EXTRACT(EPOCH FROM (a.offer_accepted_at - a.submitted_at))/86400) as min_days_to_hire,
    MAX(EXTRACT(EPOCH FROM (a.offer_accepted_at - a.submitted_at))/86400) as max_days_to_hire,

    -- Conversion rates
    ROUND(100.0 * COUNT(CASE WHEN a.application_status = 'interview_scheduled' THEN 1 END) / NULLIF(jp.application_count, 0), 1) as interview_rate,
    ROUND(100.0 * COUNT(CASE WHEN a.application_status = 'offer_extended' THEN 1 END) / NULLIF(jp.application_count, 0), 1) as offer_rate,
    ROUND(100.0 * COUNT(CASE WHEN a.application_status = 'offer_accepted' THEN 1 END) / NULLIF(jp.application_count, 0), 1) as acceptance_rate

FROM job_postings jp
LEFT JOIN applications a ON jp.job_posting_id = a.job_posting_id
WHERE jp.posting_status = 'closed'
GROUP BY jp.job_posting_id, jp.job_title, jp.posted_at, jp.application_deadline, jp.application_count, jp.view_count;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample company
INSERT INTO companies (company_name, legal_name, industry, company_size, website) VALUES
('TechCorp Solutions', 'TechCorp Solutions Inc.', 'Technology', 'large', 'https://techcorp.com');

-- Insert departments
INSERT INTO departments (company_id, department_name, department_code) VALUES
((SELECT company_id FROM companies WHERE company_name = 'TechCorp Solutions' LIMIT 1), 'Engineering', 'ENG'),
((SELECT company_id FROM companies WHERE company_name = 'TechCorp Solutions' LIMIT 1), 'Human Resources', 'HR'),
((SELECT company_id FROM companies WHERE company_name = 'TechCorp Solutions' LIMIT 1), 'Sales', 'SALES');

-- Insert job positions
INSERT INTO job_positions (department_id, position_title, position_code, position_level, salary_min, salary_max) VALUES
((SELECT department_id FROM departments WHERE department_code = 'ENG' LIMIT 1), 'Senior Software Engineer', 'SSE001', 'senior', 120000, 160000),
((SELECT department_id FROM departments WHERE department_code = 'HR' LIMIT 1), 'HR Manager', 'HRM001', 'manager', 90000, 120000);

-- Insert sample employee
INSERT INTO employees (
    company_id, first_name, last_name, email, employee_number,
    hire_date, position_id, department_id
) VALUES (
    (SELECT company_id FROM companies WHERE company_name = 'TechCorp Solutions' LIMIT 1),
    'John', 'Smith', 'john.smith@techcorp.com', 'EMP001',
    '2023-01-15',
    (SELECT position_id FROM job_positions WHERE position_code = 'SSE001' LIMIT 1),
    (SELECT department_id FROM departments WHERE department_code = 'ENG' LIMIT 1)
);

-- This schema provides a comprehensive foundation for HR and recruitment management
-- with support for organizational structure, employee lifecycle, recruitment, and performance management.
