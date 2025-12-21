-- Construction & Project Management Database Schema
-- Comprehensive schema for construction project management, resource allocation, and progress tracking

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- PROJECT AND CONTRACT MANAGEMENT
-- ===========================================

CREATE TABLE projects (
    project_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_number VARCHAR(20) UNIQUE NOT NULL,
    project_name VARCHAR(255) NOT NULL,

    -- Project Classification
    project_type VARCHAR(50) CHECK (project_type IN (
        'residential', 'commercial', 'industrial', 'infrastructure',
        'renovation', 'demolition', 'maintenance'
    )),
    project_category VARCHAR(30) CHECK (project_category IN ('new_construction', 'remodel', 'repair', 'maintenance')),

    -- Project Details
    description TEXT,
    project_scope TEXT,
    special_requirements TEXT,

    -- Location and Site
    site_address JSONB,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    site_area_sqft DECIMAL(12,2),

    -- Timeline
    planned_start_date DATE,
    planned_completion_date DATE,
    actual_start_date DATE,
    actual_completion_date DATE,

    -- Financial Information
    contract_amount DECIMAL(15,2),
    budgeted_amount DECIMAL(12,2),
    actual_cost DECIMAL(12,2),

    -- Status and Progress
    project_status VARCHAR(30) DEFAULT 'planning' CHECK (project_status IN (
        'planning', 'bid_awarded', 'pre_construction', 'active',
        'on_hold', 'completed', 'cancelled', 'disputed'
    )),
    completion_percentage DECIMAL(5,2) DEFAULT 0 CHECK (completion_percentage >= 0 AND completion_percentage <= 100),

    -- Stakeholders
    client_id UUID, -- References clients
    project_manager_id UUID, -- References employees
    superintendent_id UUID, -- References employees

    -- Quality and Safety
    quality_requirements TEXT,
    safety_requirements TEXT,
    permit_requirements TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (planned_start_date <= planned_completion_date),
    CHECK (actual_start_date <= actual_completion_date)
);

CREATE TABLE contracts (
    contract_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_number VARCHAR(30) UNIQUE NOT NULL,

    -- Contract Relationships
    project_id UUID NOT NULL REFERENCES projects(project_id),
    contractor_id UUID NOT NULL, -- References contractors
    client_id UUID NOT NULL, -- References clients

    -- Contract Details
    contract_type VARCHAR(30) CHECK (contract_type IN (
        'general_contract', 'subcontract', 'supply', 'service',
        'design_build', 'construction_management'
    )),
    scope_of_work TEXT,
    deliverables TEXT,

    -- Financial Terms
    contract_amount DECIMAL(15,2) NOT NULL,
    payment_terms VARCHAR(100),
    retainage_percentage DECIMAL(5,2) DEFAULT 10,

    -- Timeline
    effective_date DATE DEFAULT CURRENT_DATE,
    start_date DATE,
    completion_date DATE,
    warranty_period_months INTEGER DEFAULT 12,

    -- Contract Status
    contract_status VARCHAR(20) DEFAULT 'draft' CHECK (contract_status IN (
        'draft', 'executed', 'active', 'completed', 'terminated', 'disputed'
    )),

    -- Insurance and Bonds
    insurance_requirements TEXT,
    bond_requirements TEXT,

    -- Legal and Compliance
    governing_law VARCHAR(50),
    dispute_resolution TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE contract_milestones (
    milestone_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_id UUID NOT NULL REFERENCES contracts(contract_id) ON DELETE CASCADE,

    -- Milestone Details
    milestone_name VARCHAR(255) NOT NULL,
    milestone_description TEXT,
    milestone_sequence INTEGER NOT NULL,

    -- Timeline and Progress
    planned_completion_date DATE,
    actual_completion_date DATE,
    completion_percentage DECIMAL(5,2) DEFAULT 0,

    -- Financial Impact
    milestone_value DECIMAL(12,2), -- Portion of contract value
    retainage_released DECIMAL(10,2) DEFAULT 0,

    -- Status and Validation
    milestone_status VARCHAR(20) DEFAULT 'pending' CHECK (milestone_status IN (
        'pending', 'in_progress', 'completed', 'delayed', 'cancelled'
    )),
    requires_inspection BOOLEAN DEFAULT TRUE,
    inspection_required BOOLEAN DEFAULT FALSE,
    inspection_completed BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (contract_id, milestone_sequence)
);

-- ===========================================
-- RESOURCE AND MATERIAL MANAGEMENT
-- ===========================================

CREATE TABLE materials (
    material_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    material_code VARCHAR(20) UNIQUE NOT NULL,
    material_name VARCHAR(255) NOT NULL,

    -- Material Classification
    material_type VARCHAR(50) CHECK (material_type IN (
        'lumber', 'concrete', 'steel', 'electrical', 'plumbing',
        'hvac', 'finishing', 'equipment', 'tools'
    )),
    material_category VARCHAR(30) CHECK (material_category IN ('raw', 'processed', 'finished', 'consumable')),

    -- Specifications
    specifications JSONB DEFAULT '{}',
    unit_of_measure VARCHAR(20) DEFAULT 'each',
    standard_cost DECIMAL(10,2),

    -- Quality and Compliance
    quality_standards TEXT,
    certifications_required TEXT[],

    -- Supplier Information
    preferred_suppliers UUID[], -- Array of supplier IDs
    lead_time_days INTEGER,

    -- Status
    material_status VARCHAR(20) DEFAULT 'active' CHECK (material_status IN ('active', 'obsolete', 'discontinued')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE material_requirements (
    requirement_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id),
    material_id UUID NOT NULL REFERENCES materials(material_id),

    -- Quantity Planning
    estimated_quantity DECIMAL(12,4),
    ordered_quantity DECIMAL(12,4) DEFAULT 0,
    received_quantity DECIMAL(12,4) DEFAULT 0,
    used_quantity DECIMAL(12,4) DEFAULT 0,

    -- Cost Tracking
    unit_cost DECIMAL(10,2),
    total_estimated_cost DECIMAL(12,2) GENERATED ALWAYS AS (estimated_quantity * unit_cost) STORED,
    total_actual_cost DECIMAL(12,2) GENERATED ALWAYS AS (received_quantity * unit_cost) STORED,

    -- Timeline
    required_by_date DATE,
    ordered_date DATE,
    expected_delivery_date DATE,
    actual_delivery_date DATE,

    -- Status
    requirement_status VARCHAR(20) DEFAULT 'planned' CHECK (requirement_status IN (
        'planned', 'ordered', 'partially_received', 'received', 'completed', 'cancelled'
    )),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (project_id, material_id)
);

CREATE TABLE equipment (
    equipment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    equipment_code VARCHAR(20) UNIQUE NOT NULL,
    equipment_name VARCHAR(255) NOT NULL,

    -- Equipment Details
    equipment_type VARCHAR(50) CHECK (equipment_type IN (
        'heavy_machinery', 'vehicles', 'tools', 'safety_equipment',
        'measuring_tools', 'power_tools', 'lifting_equipment'
    )),
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    serial_number VARCHAR(100),

    -- Operational Details
    purchase_date DATE,
    purchase_cost DECIMAL(12,2),
    useful_life_years INTEGER,
    depreciation_method VARCHAR(30) CHECK (deprecation_method IN ('straight_line', 'declining_balance')),

    -- Maintenance
    maintenance_schedule JSONB DEFAULT '{}',
    last_maintenance_date DATE,
    next_maintenance_date DATE,

    -- Status and Availability
    equipment_status VARCHAR(20) DEFAULT 'available' CHECK (equipment_status IN (
        'available', 'in_use', 'maintenance', 'repair', 'retired', 'lost_stolen'
    )),
    current_location VARCHAR(255),
    assigned_to UUID, -- Project or employee ID

    -- Safety and Compliance
    safety_certifications TEXT[],
    inspection_required BOOLEAN DEFAULT TRUE,
    last_inspection_date DATE,
    next_inspection_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- LABOR AND WORKFORCE MANAGEMENT
-- ===========================================

CREATE TABLE employees (
    employee_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_number VARCHAR(20) UNIQUE NOT NULL,
    company_id UUID NOT NULL, -- References company

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),

    -- Employment Details
    job_title VARCHAR(100),
    department VARCHAR(50),
    employment_type VARCHAR(20) CHECK (employment_type IN ('full_time', 'part_time', 'contract', 'temporary')),

    -- Skills and Certifications
    skills TEXT[],
    certifications TEXT[],
    licenses TEXT[],

    -- Labor Rates
    hourly_rate DECIMAL(8,2),
    overtime_rate DECIMAL(8,2),
    burden_rate DECIMAL(6,2), -- Insurance, taxes, etc.

    -- Availability and Scheduling
    work_schedule JSONB DEFAULT '{}',
    availability_status VARCHAR(20) DEFAULT 'available' CHECK (availability_status IN ('available', 'assigned', 'on_leave', 'terminated')),

    -- Safety and Training
    safety_training_completed DATE,
    safety_training_expiry DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE work_crews (
    crew_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    crew_name VARCHAR(100) NOT NULL,
    project_id UUID NOT NULL REFERENCES projects(project_id),

    -- Crew Details
    crew_size INTEGER NOT NULL,
    crew_leader_id UUID REFERENCES employees(employee_id),
    crew_type VARCHAR(30) CHECK (crew_type IN ('construction', 'electrical', 'plumbing', 'hvac', 'finishing', 'demolition')),

    -- Skills and Equipment
    required_skills TEXT[],
    assigned_equipment UUID[], -- Array of equipment IDs

    -- Schedule
    work_start_time TIME DEFAULT '08:00',
    work_end_time TIME DEFAULT '17:00',
    work_days INTEGER[] DEFAULT '{1,2,3,4,5}', -- 1=Monday, 7=Sunday

    -- Status
    crew_status VARCHAR(20) DEFAULT 'active' CHECK (crew_status IN ('active', 'inactive', 'on_break', 'completed')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE crew_members (
    crew_member_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    crew_id UUID NOT NULL REFERENCES work_crews(crew_id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES employees(employee_id),

    -- Assignment Details
    assigned_date DATE DEFAULT CURRENT_DATE,
    role_in_crew VARCHAR(50),
    hours_per_week DECIMAL(5,2),

    -- Status
    assignment_status VARCHAR(20) DEFAULT 'active' CHECK (assignment_status IN ('active', 'inactive', 'transferred', 'terminated')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (crew_id, employee_id)
);

-- ===========================================
-- PROJECT PROGRESS AND QUALITY CONTROL
-- ===========================================

CREATE TABLE work_breakdown_structure (
    wbs_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id),

    -- WBS Hierarchy
    wbs_code VARCHAR(20) UNIQUE NOT NULL, -- e.g., "1.1.2"
    parent_wbs_id UUID REFERENCES work_breakdown_structure(wbs_id),
    wbs_level INTEGER DEFAULT 1,

    -- Work Package Details
    work_package_name VARCHAR(255) NOT NULL,
    description TEXT,
    estimated_hours DECIMAL(8,2),
    estimated_cost DECIMAL(12,2),

    -- Progress Tracking
    planned_start_date DATE,
    planned_completion_date DATE,
    actual_start_date DATE,
    actual_completion_date DATE,
    completion_percentage DECIMAL(5,2) DEFAULT 0,

    -- Resources Assigned
    assigned_crew_id UUID REFERENCES work_crews(crew_id),
    required_materials JSONB DEFAULT '[]', -- Array of material requirements

    -- Status
    wbs_status VARCHAR(20) DEFAULT 'planned' CHECK (wbs_status IN (
        'planned', 'in_progress', 'completed', 'delayed', 'cancelled'
    )),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE daily_progress_reports (
    progress_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id),
    report_date DATE DEFAULT CURRENT_DATE,

    -- Progress Summary
    work_completed_today TEXT,
    work_planned_tomorrow TEXT,
    issues_encountered TEXT,
    weather_conditions VARCHAR(50),

    -- Resource Usage
    labor_hours_used DECIMAL(6,2) DEFAULT 0,
    equipment_hours_used DECIMAL(6,2) DEFAULT 0,
    materials_used JSONB DEFAULT '[]',

    -- Quality and Safety
    quality_issues TEXT,
    safety_incidents TEXT,
    near_misses INTEGER DEFAULT 0,

    -- Visitors and Inspections
    visitors_today JSONB DEFAULT '[]',
    inspections_conducted JSONB DEFAULT '[]',

    -- Photos and Documentation
    progress_photos JSONB DEFAULT '[]', -- Array of photo URLs
    daily_report_url VARCHAR(500), -- PDF report URL

    -- Reporting
    reported_by UUID NOT NULL REFERENCES employees(employee_id),
    approved_by UUID REFERENCES employees(employee_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (project_id, report_date)
);

CREATE TABLE quality_inspections (
    inspection_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id),
    wbs_id UUID REFERENCES work_breakdown_structure(wbs_id),

    -- Inspection Details
    inspection_type VARCHAR(30) CHECK (inspection_type IN (
        'pre_construction', 'foundation', 'framing', 'rough_inspection',
        'final_inspection', 'safety_audit', 'quality_audit'
    )),
    inspection_date DATE DEFAULT CURRENT_DATE,

    -- Inspection Scope
    inspection_area TEXT,
    inspection_criteria TEXT,

    -- Results
    inspection_result VARCHAR(20) CHECK (inspection_result IN ('pass', 'fail', 'conditional', 'pending')),
    findings TEXT,
    corrective_actions_required TEXT,
    corrective_actions_taken TEXT,

    -- Follow-up
    follow_up_required BOOLEAN DEFAULT FALSE,
    follow_up_date DATE,
    reinspection_required BOOLEAN DEFAULT FALSE,

    -- Inspector Information
    inspector_name VARCHAR(255),
    inspector_certifications TEXT[],

    -- Documentation
    inspection_report_url VARCHAR(500),
    photos JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SAFETY AND COMPLIANCE MANAGEMENT
-- ===========================================

CREATE TABLE safety_incidents (
    incident_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id),

    -- Incident Details
    incident_date DATE DEFAULT CURRENT_DATE,
    incident_time TIME DEFAULT CURRENT_TIME,
    incident_location TEXT,

    -- Incident Classification
    incident_type VARCHAR(30) CHECK (incident_type IN (
        'injury', 'near_miss', 'property_damage', 'environmental',
        'equipment_damage', 'fire', 'hazard_exposure'
    )),
    incident_severity VARCHAR(10) CHECK (incident_severity IN ('minor', 'serious', 'critical', 'fatal')),

    -- People Involved
    injured_person_name VARCHAR(255),
    injured_person_role VARCHAR(100),
    witnesses JSONB DEFAULT '[]',

    -- Incident Description
    incident_description TEXT,
    immediate_actions_taken TEXT,
    contributing_factors TEXT,

    -- Medical and Emergency Response
    medical_attention_required BOOLEAN DEFAULT FALSE,
    medical_facility VARCHAR(255),
    emergency_services_called BOOLEAN DEFAULT FALSE,

    -- Investigation and Follow-up
    investigation_required BOOLEAN DEFAULT TRUE,
    investigation_conducted BOOLEAN DEFAULT FALSE,
    investigation_findings TEXT,
    preventive_measures TEXT,

    -- Reporting
    reported_to_osha BOOLEAN DEFAULT FALSE,
    osha_report_number VARCHAR(50),

    -- Status
    incident_status VARCHAR(20) DEFAULT 'reported' CHECK (incident_status IN (
        'reported', 'investigating', 'resolved', 'closed'
    )),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE safety_trainings (
    training_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES projects(project_id), -- NULL for company-wide training

    -- Training Details
    training_name VARCHAR(255) NOT NULL,
    training_type VARCHAR(30) CHECK (training_type IN (
        'orientation', 'equipment_specific', 'hazard_specific',
        'certification', 'refresher', 'emergency_response'
    )),
    training_description TEXT,

    -- Schedule and Duration
    training_date DATE,
    training_duration_hours DECIMAL(4,2),
    training_location VARCHAR(255),

    -- Instructor and Provider
    instructor_name VARCHAR(255),
    training_provider VARCHAR(255),

    -- Requirements and Certification
    certification_issued BOOLEAN DEFAULT FALSE,
    certification_expiry DATE,
    retraining_required BOOLEAN DEFAULT FALSE,
    retraining_interval_months INTEGER,

    -- Participants
    required_for_roles TEXT[], -- Job roles that must complete this training
    attendees JSONB DEFAULT '[]', -- Array of attendee records

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE permits_and_licenses (
    permit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id),

    -- Permit Details
    permit_type VARCHAR(50) CHECK (permit_type IN (
        'building_permit', 'electrical_permit', 'plumbing_permit',
        'mechanical_permit', 'demolition_permit', 'grading_permit'
    )),
    permit_number VARCHAR(50) UNIQUE NOT NULL,

    -- Issuing Authority
    issuing_authority VARCHAR(255),
    jurisdiction VARCHAR(100),

    -- Validity Period
    issue_date DATE,
    expiration_date DATE,
    renewal_required BOOLEAN DEFAULT FALSE,
    renewal_date DATE,

    -- Status and Compliance
    permit_status VARCHAR(20) DEFAULT 'applied' CHECK (permit_status IN (
        'applied', 'approved', 'rejected', 'expired', 'revoked', 'closed'
    )),
    inspection_required BOOLEAN DEFAULT TRUE,
    final_inspection_passed BOOLEAN,

    -- Cost and Fees
    permit_fee DECIMAL(8,2),
    additional_fees DECIMAL(8,2),

    -- Documentation
    permit_document_url VARCHAR(500),
    inspection_reports JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- FINANCIAL AND COST MANAGEMENT
-- ===========================================

CREATE TABLE cost_codes (
    cost_code_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cost_code VARCHAR(20) UNIQUE NOT NULL,
    cost_code_name VARCHAR(255) NOT NULL,

    -- Cost Code Hierarchy
    parent_cost_code_id UUID REFERENCES cost_codes(cost_code_id),
    cost_code_level INTEGER DEFAULT 1,

    -- Cost Code Details
    cost_code_type VARCHAR(30) CHECK (cost_code_type IN (
        'labor', 'material', 'equipment', 'subcontractor',
        'overhead', 'permit', 'insurance', 'other'
    )),
    description TEXT,

    -- Budget Control
    budgeted_amount DECIMAL(12,2),
    committed_amount DECIMAL(12,2) DEFAULT 0,
    actual_amount DECIMAL(12,2) DEFAULT 0,

    -- Status
    cost_code_status VARCHAR(20) DEFAULT 'active' CHECK (cost_code_status IN ('active', 'inactive', 'closed')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE project_costs (
    cost_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id),
    cost_code_id UUID REFERENCES cost_codes(cost_code_id),

    -- Cost Details
    cost_description TEXT,
    cost_amount DECIMAL(10,2) NOT NULL,
    cost_date DATE DEFAULT CURRENT_DATE,

    -- Cost Classification
    cost_type VARCHAR(30) CHECK (cost_type IN (
        'labor', 'material', 'equipment', 'subcontractor',
        'permit', 'insurance', 'overhead', 'change_order'
    )),
    cost_category VARCHAR(50),

    -- Vendor/Supplier Information
    vendor_id UUID,
    invoice_number VARCHAR(50),
    purchase_order_number VARCHAR(30),

    -- Approval and Accounting
    approved_by UUID REFERENCES employees(employee_id),
    approved_at TIMESTAMP WITH TIME ZONE,
    accounting_period VARCHAR(10), -- YYYY-MM

    -- Change Order Information
    is_change_order BOOLEAN DEFAULT FALSE,
    change_order_reason TEXT,
    change_order_approved BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (cost_amount > 0)
);

CREATE TABLE change_orders (
    change_order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id),
    change_order_number VARCHAR(20) UNIQUE NOT NULL,

    -- Change Order Details
    title VARCHAR(255) NOT NULL,
    description TEXT,
    reason TEXT,

    -- Financial Impact
    additional_cost DECIMAL(12,2) DEFAULT 0,
    cost_reduction DECIMAL(12,2) DEFAULT 0,
    net_change DECIMAL(12,2) GENERATED ALWAYS AS (additional_cost - cost_reduction) STORED,

    -- Schedule Impact
    schedule_delay_days INTEGER DEFAULT 0,
    schedule_acceleration_days INTEGER DEFAULT 0,

    -- Approval Process
    requested_by UUID NOT NULL REFERENCES employees(employee_id),
    requested_date DATE DEFAULT CURRENT_DATE,
    approved_by UUID REFERENCES employees(employee_id),
    approved_date DATE,

    -- Status
    change_order_status VARCHAR(20) DEFAULT 'draft' CHECK (change_order_status IN (
        'draft', 'submitted', 'approved', 'rejected', 'implemented'
    )),

    -- Documentation
    supporting_documents JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Project indexes
CREATE INDEX idx_projects_status_dates ON projects (project_status, planned_start_date, planned_completion_date);
CREATE INDEX idx_projects_client_manager ON projects (client_id, project_manager_id);
CREATE INDEX idx_projects_location ON projects USING gist (ST_Point(longitude, latitude));

-- Contract indexes
CREATE INDEX idx_contracts_project_status ON contracts (project_id, contract_status);
CREATE INDEX idx_contracts_contractor ON contracts (contractor_id);

-- Material indexes
CREATE INDEX idx_materials_type_category ON materials (material_type, material_category);
CREATE INDEX idx_material_requirements_project ON material_requirements (project_id);
CREATE INDEX idx_material_requirements_status ON material_requirements (requirement_status);

-- Equipment indexes
CREATE INDEX idx_equipment_type_status ON equipment (equipment_type, equipment_status);
CREATE INDEX idx_equipment_assigned ON equipment (assigned_to);

-- Employee indexes
CREATE INDEX idx_employees_department ON employees (department);
CREATE INDEX idx_employees_skills ON employees USING gin (skills);

-- Progress and quality indexes
CREATE INDEX idx_daily_progress_project_date ON daily_progress_reports (project_id, report_date DESC);
CREATE INDEX idx_quality_inspections_project ON quality_inspections (project_id, inspection_date DESC);
CREATE INDEX idx_safety_incidents_project ON safety_incidents (project_id, incident_date DESC);

-- Financial indexes
CREATE INDEX idx_cost_codes_type ON cost_codes (cost_code_type);
CREATE INDEX idx_project_costs_project ON project_costs (project_id, cost_date DESC);
CREATE INDEX idx_change_orders_project ON change_orders (project_id, change_order_status);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Project overview dashboard
CREATE VIEW project_overview AS
SELECT
    p.project_id,
    p.project_number,
    p.project_name,
    p.project_type,
    p.project_status,
    p.completion_percentage,

    -- Timeline
    p.planned_start_date,
    p.planned_completion_date,
    p.actual_start_date,
    p.actual_completion_date,

    -- Financial summary
    p.contract_amount,
    p.budgeted_amount,
    p.actual_cost,
    p.contract_amount - COALESCE(p.actual_cost, 0) as remaining_budget,

    -- Key personnel
    pm.first_name || ' ' || pm.last_name as project_manager,
    sup.first_name || ' ' || sup.last_name as superintendent,

    -- Current progress metrics
    COUNT(dpr.progress_id) as days_reported,
    AVG(dpr.labor_hours_used) as avg_daily_labor_hours,
    COUNT(si.incident_id) as safety_incidents,

    -- Quality metrics
    COUNT(qi.inspection_id) as inspections_conducted,
    COUNT(CASE WHEN qi.inspection_result = 'pass' THEN 1 END) as inspections_passed,
    COUNT(CASE WHEN qi.inspection_result = 'fail' THEN 1 END) as inspections_failed

FROM projects p
LEFT JOIN employees pm ON p.project_manager_id = pm.employee_id
LEFT JOIN employees sup ON p.superintendent_id = sup.employee_id
LEFT JOIN daily_progress_reports dpr ON p.project_id = dpr.project_id
LEFT JOIN safety_incidents si ON p.project_id = si.project_id
LEFT JOIN quality_inspections qi ON p.project_id = qi.project_id
GROUP BY p.project_id, p.project_number, p.project_name, p.project_type,
         p.project_status, p.completion_percentage, p.planned_start_date,
         p.planned_completion_date, p.actual_start_date, p.actual_completion_date,
         p.contract_amount, p.budgeted_amount, p.actual_cost,
         pm.first_name, pm.last_name, sup.first_name, sup.last_name;

-- Material usage and cost analysis
CREATE VIEW material_analysis AS
SELECT
    mr.project_id,
    m.material_name,
    m.material_type,
    mr.estimated_quantity,
    mr.ordered_quantity,
    mr.received_quantity,
    mr.used_quantity,

    -- Cost analysis
    mr.unit_cost,
    mr.total_estimated_cost,
    mr.total_actual_cost,
    mr.total_actual_cost - mr.total_estimated_cost as cost_variance,

    -- Status indicators
    CASE
        WHEN mr.received_quantity >= mr.estimated_quantity THEN 'fully_received'
        WHEN mr.received_quantity > 0 THEN 'partially_received'
        WHEN mr.ordered_quantity > 0 THEN 'ordered'
        ELSE 'not_ordered'
    END as procurement_status,

    -- Delivery performance
    mr.required_by_date,
    mr.expected_delivery_date,
    mr.actual_delivery_date,
    CASE
        WHEN mr.actual_delivery_date <= mr.required_by_date THEN 'on_time'
        WHEN mr.actual_delivery_date IS NULL AND CURRENT_DATE > mr.required_by_date THEN 'overdue'
        ELSE 'delayed'
    END as delivery_status

FROM material_requirements mr
JOIN materials m ON mr.material_id = m.material_id
ORDER BY mr.project_id, m.material_type, m.material_name;

-- Labor productivity analysis
CREATE VIEW labor_productivity AS
SELECT
    p.project_id,
    p.project_name,
    dpr.report_date,

    -- Labor metrics
    dpr.labor_hours_used,
    COUNT(cm.crew_member_id) as crew_size,

    -- Productivity calculations
    dpr.labor_hours_used / COUNT(cm.crew_member_id) as hours_per_worker,
    p.completion_percentage as project_completion,

    -- Cost metrics
    dpr.labor_hours_used * AVG(e.hourly_rate) as labor_cost_today,

    -- Weekly trends
    AVG(dpr.labor_hours_used) OVER (
        PARTITION BY p.project_id
        ORDER BY dpr.report_date
        ROWS 6 PRECEDING
    ) as avg_labor_hours_last_week

FROM projects p
JOIN daily_progress_reports dpr ON p.project_id = dpr.project_id
LEFT JOIN work_crews wc ON p.project_id = wc.project_id AND wc.crew_status = 'active'
LEFT JOIN crew_members cm ON wc.crew_id = cm.crew_id AND cm.assignment_status = 'active'
LEFT JOIN employees e ON cm.employee_id = e.employee_id
GROUP BY p.project_id, p.project_name, dpr.report_date, dpr.labor_hours_used, p.completion_percentage;

-- Safety performance dashboard
CREATE VIEW safety_performance AS
SELECT
    p.project_id,
    p.project_name,

    -- Incident metrics
    COUNT(si.incident_id) as total_incidents,
    COUNT(CASE WHEN si.incident_severity = 'minor' THEN 1 END) as minor_incidents,
    COUNT(CASE WHEN si.incident_severity = 'serious' THEN 1 END) as serious_incidents,
    COUNT(CASE WHEN si.incident_severity = 'critical' THEN 1 END) as critical_incidents,

    -- Incident rate (per 200,000 hours worked - standard safety metric)
    CASE WHEN SUM(dpr.labor_hours_used) > 0 THEN
        (COUNT(si.incident_id) * 200000.0) / SUM(dpr.labor_hours_used)
    ELSE 0 END as incident_rate_per_200k_hours,

    -- Days since last incident
    CURRENT_DATE - MAX(si.incident_date) as days_since_last_incident,

    -- Training compliance
    COUNT(st.training_id) as safety_trainings_completed,
    COUNT(CASE WHEN st.certification_expiry > CURRENT_DATE THEN 1 END) as current_certifications,

    -- Near miss reporting
    SUM(dpr.near_misses) as near_misses_reported

FROM projects p
LEFT JOIN safety_incidents si ON p.project_id = si.project_id
LEFT JOIN daily_progress_reports dpr ON p.project_id = dpr.project_id
LEFT JOIN safety_trainings st ON p.project_id = st.project_id
GROUP BY p.project_id, p.project_name;

-- ===========================================
-- FUNCTIONS FOR CONSTRUCTION MANAGEMENT
-- ===========================================

-- Function to update project completion percentage
CREATE OR REPLACE FUNCTION update_project_completion(project_uuid UUID)
RETURNS DECIMAL AS $$
DECLARE
    wbs_completion DECIMAL;
    milestone_completion DECIMAL;
    overall_completion DECIMAL;
BEGIN
    -- Calculate WBS completion
    SELECT AVG(completion_percentage) INTO wbs_completion
    FROM work_breakdown_structure
    WHERE project_id = project_uuid;

    -- Calculate milestone completion
    SELECT CASE WHEN COUNT(*) > 0 THEN
        (COUNT(CASE WHEN milestone_status = 'completed' THEN 1 END)::DECIMAL / COUNT(*)) * 100
    ELSE 0 END INTO milestone_completion
    FROM contract_milestones cm
    JOIN contracts c ON cm.contract_id = c.contract_id
    WHERE c.project_id = project_uuid;

    -- Weighted average (70% WBS, 30% milestones)
    overall_completion := (COALESCE(wbs_completion, 0) * 0.7) + (COALESCE(milestone_completion, 0) * 0.3);

    -- Update project
    UPDATE projects
    SET completion_percentage = ROUND(overall_completion, 2),
        updated_at = CURRENT_TIMESTAMP
    WHERE project_id = project_uuid;

    RETURN ROUND(overall_completion, 2);
END;
$$ LANGUAGE plpgsql;

-- Function to check material availability for work packages
CREATE OR REPLACE FUNCTION check_material_availability(wbs_uuid UUID)
RETURNS TABLE (
    material_name VARCHAR,
    required_quantity DECIMAL,
    available_quantity DECIMAL,
    shortage_quantity DECIMAL,
    availability_status VARCHAR
) AS $$
DECLARE
    project_uuid UUID;
BEGIN
    -- Get project ID
    SELECT project_id INTO project_uuid
    FROM work_breakdown_structure
    WHERE wbs_id = wbs_uuid;

    -- Check material requirements vs available inventory
    RETURN QUERY
    SELECT
        m.material_name,
        (wbs.required_materials->>m.material_id::TEXT)::DECIMAL as required_quantity,
        COALESCE(ii.quantity_available, 0) as available_quantity,
        GREATEST(0, (wbs.required_materials->>m.material_id::TEXT)::DECIMAL - COALESCE(ii.quantity_available, 0)) as shortage_quantity,
        CASE
            WHEN COALESCE(ii.quantity_available, 0) >= (wbs.required_materials->>m.material_id::TEXT)::DECIMAL THEN 'available'
            WHEN COALESCE(ii.quantity_available, 0) > 0 THEN 'partial'
            ELSE 'unavailable'
        END as availability_status
    FROM work_breakdown_structure wbs
    CROSS JOIN materials m
    LEFT JOIN inventory_items ii ON m.material_id = ii.material_id
        AND ii.location_id IN (
            SELECT location_id FROM inventory_locations
            WHERE location_type = 'warehouse'
        )
    WHERE wbs.wbs_id = wbs_uuid
      AND wbs.required_materials ? m.material_id::TEXT;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate project cost variance
CREATE OR REPLACE FUNCTION calculate_cost_variance(project_uuid UUID)
RETURNS TABLE (
    budgeted_cost DECIMAL,
    actual_cost DECIMAL,
    cost_variance DECIMAL,
    variance_percentage DECIMAL,
    cost_performance_index DECIMAL
) AS $$
DECLARE
    budget_total DECIMAL := 0;
    actual_total DECIMAL := 0;
BEGIN
    -- Calculate budgeted cost
    SELECT COALESCE(budgeted_amount, 0) INTO budget_total
    FROM projects WHERE project_id = project_uuid;

    -- Calculate actual cost
    SELECT COALESCE(SUM(cost_amount), 0) INTO actual_total
    FROM project_costs WHERE project_id = project_uuid;

    RETURN QUERY SELECT
        budget_total,
        actual_total,
        actual_total - budget_total as cost_variance,
        CASE WHEN budget_total > 0 THEN
            ((actual_total - budget_total) / budget_total) * 100
        ELSE 0 END as variance_percentage,
        CASE WHEN actual_total > 0 THEN budget_total / actual_total
        ELSE 0 END as cost_performance_index;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample project
INSERT INTO projects (
    project_number, project_name, project_type, description,
    planned_start_date, planned_completion_date, contract_amount, budgeted_amount
) VALUES (
    'PROJ-001', 'Downtown Office Building', 'commercial', '12-story office building construction',
    '2024-01-01', '2025-06-30', 25000000.00, 24000000.00
);

-- Insert sample materials
INSERT INTO materials (material_code, material_name, material_type, unit_of_measure, standard_cost) VALUES
('MAT-001', 'Concrete Mix - 4000 PSI', 'concrete', 'cubic_yard', 150.00),
('MAT-002', 'Steel Rebar - #5', 'steel', 'linear_foot', 0.85);

-- Insert material requirements for project
INSERT INTO material_requirements (project_id, material_id, estimated_quantity, unit_cost, required_by_date) VALUES
((SELECT project_id FROM projects WHERE project_number = 'PROJ-001' LIMIT 1),
 (SELECT material_id FROM materials WHERE material_code = 'MAT-001' LIMIT 1), 5000, 150.00, '2024-03-01');

-- Insert sample equipment
INSERT INTO equipment (equipment_code, equipment_name, equipment_type, purchase_cost) VALUES
('EQP-001', 'Caterpillar Excavator 320', 'heavy_machinery', 450000.00);

-- Insert sample employee
INSERT INTO employees (employee_number, company_id, first_name, last_name, job_title, hourly_rate) VALUES
('EMP-001', gen_random_uuid(), 'John', 'Smith', 'Project Manager', 75.00);

-- Insert sample contract
INSERT INTO contracts (contract_number, project_id, contractor_id, client_id, contract_amount, start_date, completion_date) VALUES
('CON-001',
 (SELECT project_id FROM projects WHERE project_number = 'PROJ-001' LIMIT 1),
 gen_random_uuid(), gen_random_uuid(), 25000000.00, '2024-01-01', '2025-06-30'
);

-- This construction schema provides comprehensive infrastructure for project management,
-- resource allocation, progress tracking, quality control, and financial management.
