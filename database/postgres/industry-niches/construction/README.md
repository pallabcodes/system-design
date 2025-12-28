# Construction & Project Management Database Design

## Overview

This comprehensive database schema supports construction project management including resource allocation, progress tracking, quality control, safety management, and financial oversight for construction operations. The design handles complex project workflows, multi-trade coordination, and regulatory compliance.

## Key Features

### 🏗️ Project Lifecycle Management
- **Complete project planning** from bidding to completion with milestone tracking
- **Contract management** with change orders, retainage, and payment schedules
- **Work breakdown structure (WBS)** with hierarchical task decomposition
- **Resource allocation** across labor, materials, and equipment

### 📋 Resource and Material Management
- **Material requirements planning** with procurement tracking
- **Equipment scheduling** and maintenance management
- **Labor resource allocation** with crew management and skill tracking
- **Inventory control** for materials and consumables

### 📊 Progress and Quality Control
- **Daily progress reporting** with work completed documentation
- **Quality inspection workflows** with corrective action tracking
- **Safety incident management** and training compliance
- **Permit and regulatory compliance** tracking

### 💰 Financial and Cost Management
- **Project cost control** with budget vs actual analysis
- **Change order management** with approval workflows
- **Cost code tracking** for detailed expense categorization
- **Contractor payment processing** with retainage management

## Database Schema Highlights

### Core Tables

#### Project Management
- **`projects`** - Project master data with contracts, timelines, and budgets
- **`contracts`** - Contract administration with milestones and deliverables
- **`contract_milestones`** - Payment milestones and progress validation

#### Resource Management
- **`materials`** - Material catalog with specifications and procurement details
- **`material_requirements`** - Project-specific material planning and tracking
- **`equipment`** - Equipment inventory with maintenance scheduling
- **`employees`** - Workforce management with skills and certifications

#### Execution Management
- **`work_breakdown_structure`** - Hierarchical project task decomposition
- **`work_crews`** - Labor crew organization and scheduling
- **`daily_progress_reports`** - Daily work documentation and progress tracking

#### Quality and Safety
- **`quality_inspections`** - Inspection management with findings and follow-up
- **`safety_incidents`** - Incident reporting and investigation tracking
- **`safety_trainings`** - Training compliance and certification management

#### Financial Management
- **`cost_codes`** - Expense categorization with budget control
- **`project_costs`** - Detailed cost tracking with approval workflows
- **`change_orders`** - Contract modification management

## Key Design Patterns

### 1. Project Progress Calculation with WBS
```sql
-- Calculate project completion based on work breakdown structure
CREATE OR REPLACE FUNCTION calculate_project_progress(project_uuid UUID)
RETURNS DECIMAL AS $$
DECLARE
    total_weighted_progress DECIMAL := 0;
    total_weight DECIMAL := 0;
    wbs_record RECORD;
BEGIN
    -- Calculate weighted progress based on WBS structure
    FOR wbs_record IN
        SELECT
            wbs_id,
            estimated_cost,
            completion_percentage,
            CASE
                WHEN parent_wbs_id IS NULL THEN 1.0  -- Top level weight
                ELSE 0.8  -- Sub-level weight
            END as weight_factor
        FROM work_breakdown_structure
        WHERE project_id = project_uuid
    LOOP
        total_weighted_progress := total_weighted_progress +
            (wbs_record.completion_percentage * wbs_record.weight_factor * COALESCE(wbs_record.estimated_cost, 1));
        total_weight := total_weight + (wbs_record.weight_factor * COALESCE(wbs_record.estimated_cost, 1));
    END LOOP;

    -- Return weighted average
    IF total_weight > 0 THEN
        RETURN ROUND(total_weighted_progress / total_weight, 2);
    ELSE
        RETURN 0;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

### 2. Material Requirements Planning (MRP)
```sql
-- Generate material requirements based on project schedule
CREATE OR REPLACE FUNCTION generate_material_requirements(project_uuid UUID)
RETURNS TABLE (
    material_id UUID,
    material_name VARCHAR,
    required_quantity DECIMAL,
    required_date DATE,
    lead_time_days INTEGER,
    order_date DATE,
    supplier_id UUID
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.material_id,
        m.material_name,
        mr.estimated_quantity as required_quantity,
        mr.required_by_date,
        m.lead_time_days,
        mr.required_by_date - INTERVAL '1 day' * m.lead_time_days as order_date,
        (m.preferred_suppliers)[1] as supplier_id  -- First preferred supplier
    FROM material_requirements mr
    JOIN materials m ON mr.material_id = m.material_id
    WHERE mr.project_id = project_uuid
      AND mr.requirement_status = 'planned'
      AND mr.ordered_quantity < mr.estimated_quantity
    ORDER BY mr.required_by_date, m.lead_time_days DESC;
END;
$$ LANGUAGE plpgsql;
```

### 3. Cost Variance Analysis and Forecasting
```sql
-- Analyze project cost performance and forecast completion costs
CREATE OR REPLACE FUNCTION analyze_project_costs(project_uuid UUID)
RETURNS TABLE (
    current_budget DECIMAL,
    costs_to_date DECIMAL,
    estimated_costs_to_complete DECIMAL,
    variance_to_date DECIMAL,
    estimated_final_cost DECIMAL,
    cost_performance_index DECIMAL,
    cost_variance_index DECIMAL
) AS $$
DECLARE
    project_record projects%ROWTYPE;
    costs_incurred DECIMAL;
    completion_percentage DECIMAL;
    estimated_total_cost DECIMAL;
BEGIN
    -- Get project details
    SELECT * INTO project_record FROM projects WHERE project_id = project_uuid;

    -- Calculate costs incurred
    SELECT COALESCE(SUM(cost_amount), 0) INTO costs_incurred
    FROM project_costs WHERE project_id = project_uuid;

    -- Get completion percentage
    completion_percentage := project_record.completion_percentage / 100.0;

    -- Estimate costs to complete (simple linear extrapolation)
    IF completion_percentage > 0 THEN
        estimated_total_cost := costs_incurred / completion_percentage;
    ELSE
        estimated_total_cost := project_record.budgeted_amount;
    END IF;

    RETURN QUERY SELECT
        project_record.budgeted_amount,
        costs_incurred,
        estimated_total_cost - costs_incurred,
        costs_incurred - (project_record.budgeted_amount * completion_percentage),
        estimated_total_cost,
        CASE WHEN costs_incurred > 0 THEN project_record.budgeted_amount * completion_percentage / costs_incurred
             ELSE 0 END as cost_performance_index,
        CASE WHEN project_record.budgeted_amount * completion_percentage > 0
             THEN (project_record.budgeted_amount * completion_percentage - costs_incurred) / (project_record.budgeted_amount * completion_percentage)
             ELSE 0 END as cost_variance_index;
END;
$$ LANGUAGE plpgsql;
```

### 4. Safety Performance Monitoring
```sql
-- Calculate safety metrics and identify trends
CREATE OR REPLACE FUNCTION calculate_safety_metrics(project_uuid UUID, time_period_days INTEGER DEFAULT 30)
RETURNS TABLE (
    total_incidents INTEGER,
    lost_time_incidents INTEGER,
    incident_rate_per_200k_hours DECIMAL,
    severity_rate DECIMAL,
    near_miss_ratio DECIMAL,
    days_since_last_incident INTEGER,
    safety_trend VARCHAR
) AS $$
DECLARE
    incident_count INTEGER;
    lost_time_count INTEGER;
    total_hours DECIMAL;
    near_miss_count INTEGER;
    last_incident_date DATE;
    previous_period_incidents INTEGER;
BEGIN
    -- Count incidents in period
    SELECT COUNT(*) INTO incident_count
    FROM safety_incidents
    WHERE project_id = project_uuid
      AND incident_date >= CURRENT_DATE - INTERVAL '1 day' * time_period_days;

    -- Count lost time incidents
    SELECT COUNT(*) INTO lost_time_count
    FROM safety_incidents
    WHERE project_id = project_uuid
      AND incident_date >= CURRENT_DATE - INTERVAL '1 day' * time_period_days
      AND incident_severity IN ('serious', 'critical', 'fatal');

    -- Calculate total labor hours
    SELECT COALESCE(SUM(labor_hours_used), 0) INTO total_hours
    FROM daily_progress_reports
    WHERE project_id = project_uuid
      AND report_date >= CURRENT_DATE - INTERVAL '1 day' * time_period_days;

    -- Count near misses
    SELECT COALESCE(SUM(near_misses), 0) INTO near_miss_count
    FROM daily_progress_reports
    WHERE project_id = project_uuid
      AND report_date >= CURRENT_DATE - INTERVAL '1 day' * time_period_days;

    -- Get last incident date
    SELECT MAX(incident_date) INTO last_incident_date
    FROM safety_incidents
    WHERE project_id = project_uuid;

    -- Compare with previous period
    SELECT COUNT(*) INTO previous_period_incidents
    FROM safety_incidents
    WHERE project_id = project_uuid
      AND incident_date >= CURRENT_DATE - INTERVAL '1 day' * (time_period_days * 2)
      AND incident_date < CURRENT_DATE - INTERVAL '1 day' * time_period_days;

    RETURN QUERY SELECT
        incident_count,
        lost_time_count,
        CASE WHEN total_hours > 0 THEN (incident_count * 200000.0) / total_hours ELSE 0 END,
        CASE WHEN incident_count > 0 THEN AVG(
            CASE incident_severity
                WHEN 'minor' THEN 1
                WHEN 'serious' THEN 10
                WHEN 'critical' THEN 50
                WHEN 'fatal' THEN 100
            END
        ) ELSE 0 END,
        CASE WHEN incident_count > 0 THEN near_miss_count::DECIMAL / incident_count ELSE 0 END,
        CURRENT_DATE - last_incident_date,
        CASE
            WHEN incident_count < previous_period_incidents THEN 'improving'
            WHEN incident_count > previous_period_incidents THEN 'declining'
            ELSE 'stable'
        END;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition daily progress reports by month
CREATE TABLE daily_progress_reports PARTITION BY RANGE (report_date);

CREATE TABLE daily_progress_reports_2024_01 PARTITION OF daily_progress_reports
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition project costs by month
CREATE TABLE project_costs PARTITION BY RANGE (cost_date);

CREATE TABLE project_costs_2024_01 PARTITION OF project_costs
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition safety incidents by year
CREATE TABLE safety_incidents PARTITION BY RANGE (incident_date);

CREATE TABLE safety_incidents_2024 PARTITION OF safety_incidents
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### Advanced Indexing
```sql
-- Composite indexes for project queries
CREATE INDEX idx_projects_status_dates ON projects (project_status, planned_start_date, planned_completion_date);
CREATE INDEX idx_projects_completion ON projects (completion_percentage);

-- Partial indexes for active projects
CREATE INDEX idx_active_projects ON projects (project_id) WHERE project_status IN ('active', 'pre_construction');

-- Spatial indexes for project locations
CREATE INDEX idx_projects_location ON projects USING gist (ST_Point(longitude, latitude));

-- JSONB indexes for flexible data
CREATE INDEX idx_materials_specifications ON materials USING gin (specifications);
CREATE INDEX idx_equipment_maintenance ON equipment USING gin (maintenance_schedule);

-- Full-text search indexes
CREATE INDEX idx_projects_search ON projects USING gin (to_tsvector('english', project_name || ' ' || description));
CREATE INDEX idx_materials_search ON materials USING gin (to_tsvector('english', material_name || ' ' || description));
```

### Materialized Views for Analytics
```sql
-- Project status dashboard
CREATE MATERIALIZED VIEW project_status_dashboard AS
SELECT
    p.project_id,
    p.project_name,
    p.project_status,
    p.completion_percentage,

    -- Timeline status
    CASE
        WHEN p.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN CURRENT_DATE > p.planned_completion_date THEN 'overdue'
        WHEN CURRENT_DATE BETWEEN p.planned_start_date AND p.planned_completion_date THEN 'on_track'
        ELSE 'upcoming'
    END as timeline_status,

    -- Financial status
    p.budgeted_amount,
    COALESCE(pc.actual_cost, 0) as costs_incurred,
    p.budgeted_amount - COALESCE(pc.actual_cost, 0) as budget_remaining,
    CASE
        WHEN COALESCE(pc.actual_cost, 0) > p.budgeted_amount THEN 'over_budget'
        WHEN COALESCE(pc.actual_cost, 0) > p.budgeted_amount * 0.9 THEN 'budget_warning'
        ELSE 'on_budget'
    END as budget_status,

    -- Resource status
    COUNT(CASE WHEN mr.requirement_status = 'received' THEN 1 END) as materials_received,
    COUNT(mr.requirement_id) as total_material_requirements,
    COUNT(CASE WHEN e.equipment_status = 'available' THEN 1 END) as available_equipment,

    -- Quality and safety
    COUNT(CASE WHEN qi.inspection_result = 'pass' THEN 1 END) as passed_inspections,
    COUNT(CASE WHEN si.incident_severity IN ('critical', 'fatal') THEN 1 END) as serious_incidents

FROM projects p
LEFT JOIN (SELECT project_id, SUM(cost_amount) as actual_cost FROM project_costs GROUP BY project_id) pc ON p.project_id = pc.project_id
LEFT JOIN material_requirements mr ON p.project_id = mr.project_id
LEFT JOIN equipment e ON p.project_id = e.assigned_to
LEFT JOIN quality_inspections qi ON p.project_id = qi.project_id
LEFT JOIN safety_incidents si ON p.project_id = si.project_id
GROUP BY p.project_id, p.project_name, p.project_status, p.completion_percentage,
         p.planned_start_date, p.planned_completion_date, p.actual_completion_date,
         p.budgeted_amount, pc.actual_cost;

-- Refresh daily
CREATE UNIQUE INDEX idx_project_status_dashboard ON project_status_dashboard (project_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY project_status_dashboard;
```

## Security Considerations

### Access Control
```sql
-- Role-based security for construction operations
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_costs ENABLE ROW LEVEL SECURITY;

CREATE POLICY project_access_policy ON projects
    FOR ALL USING (
        project_manager_id = current_setting('app.user_id')::UUID OR
        superintendent_id = current_setting('app.user_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('executive', 'project_admin') OR
        EXISTS (
            SELECT 1 FROM work_crews wc
            JOIN crew_members cm ON wc.crew_id = cm.crew_id
            WHERE wc.project_id = projects.project_id
              AND cm.employee_id = current_setting('app.user_id')::UUID
        )
    );

CREATE POLICY cost_access_policy ON project_costs
    FOR SELECT USING (
        current_setting('app.user_role')::TEXT IN ('accountant', 'project_manager', 'executive') OR
        approved_by = current_setting('app.user_id')::UUID
    );
```

### Audit Trail
```sql
-- Comprehensive construction audit logging
CREATE TABLE construction_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    project_id UUID REFERENCES projects(project_id),
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    change_reason TEXT,
    compliance_impact VARCHAR(20) CHECK (compliance_impact IN ('safety', 'financial', 'regulatory', 'quality', 'none')),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Audit trigger for critical operations
CREATE OR REPLACE FUNCTION construction_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO construction_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, project_id, session_id, ip_address, user_agent,
        compliance_impact
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME IN ('projects', 'daily_progress_reports', 'quality_inspections', 'safety_incidents')
             THEN (SELECT project_id FROM projects WHERE project_id = COALESCE(NEW.project_id, OLD.project_id))
             ELSE NULL END,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE
            WHEN TG_TABLE_NAME = 'safety_incidents' THEN 'safety'
            WHEN TG_TABLE_NAME LIKE '%cost%' THEN 'financial'
            WHEN TG_TABLE_NAME LIKE '%inspection%' THEN 'quality'
            ELSE 'none'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### OSHA Safety Compliance
```sql
-- Automated OSHA reporting and compliance tracking
CREATE OR REPLACE FUNCTION generate_osha_report(project_uuid UUID, report_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER)
RETURNS TABLE (
    establishment_name TEXT,
    total_hours_worked BIGINT,
    total_recordable_incidents INTEGER,
    lost_time_incidents INTEGER,
    fatality_count INTEGER,
    incident_rate DECIMAL,
    days_away_rate DECIMAL,
    osha_recordability_rate DECIMAL
) AS $$
DECLARE
    project_name TEXT;
    total_hours BIGINT;
    recordable_incidents INTEGER;
    lost_time_cases INTEGER;
    fatalities INTEGER;
BEGIN
    -- Get project info
    SELECT project_name INTO project_name FROM projects WHERE project_id = project_uuid;

    -- Calculate total hours worked
    SELECT COALESCE(SUM(labor_hours_used), 0) INTO total_hours
    FROM daily_progress_reports
    WHERE project_id = project_uuid
      AND EXTRACT(YEAR FROM report_date) = report_year;

    -- Count incidents
    SELECT
        COUNT(*) FILTER (WHERE incident_severity IN ('serious', 'critical', 'fatal')),
        COUNT(*) FILTER (WHERE incident_severity IN ('serious', 'critical', 'fatal') AND injury_days > 0),
        COUNT(*) FILTER (WHERE incident_severity = 'fatal')
    INTO recordable_incidents, lost_time_cases, fatalities
    FROM safety_incidents
    WHERE project_id = project_uuid
      AND EXTRACT(YEAR FROM incident_date) = report_year;

    RETURN QUERY SELECT
        project_name,
        total_hours,
        recordable_incidents,
        lost_time_cases,
        fatalities,
        CASE WHEN total_hours > 0 THEN (recordable_incidents * 200000.0) / total_hours ELSE 0 END,
        CASE WHEN total_hours > 0 THEN (lost_time_cases * 200000.0) / total_hours ELSE 0 END,
        CASE WHEN total_hours > 0 THEN (recordable_incidents * 200000.0) / total_hours ELSE 0 END;
END;
$$ LANGUAGE plpgsql;
```

### Regulatory Permit Tracking
```sql
-- Permit compliance monitoring and renewal alerts
CREATE OR REPLACE FUNCTION check_permit_compliance(project_uuid UUID)
RETURNS TABLE (
    permit_type TEXT,
    permit_number TEXT,
    expiration_date DATE,
    days_until_expiration INTEGER,
    compliance_status TEXT,
    renewal_required BOOLEAN,
    renewal_deadline DATE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pp.permit_type::TEXT,
        pp.permit_number,
        pp.expiration_date,
        (pp.expiration_date - CURRENT_DATE)::INTEGER,
        CASE
            WHEN pp.expiration_date < CURRENT_DATE THEN 'expired'
            WHEN pp.expiration_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'expires_soon'
            WHEN pp.inspection_required AND NOT pp.final_inspection_passed THEN 'inspection_pending'
            ELSE 'compliant'
        END,
        pp.renewal_required,
        CASE WHEN pp.renewal_required THEN pp.expiration_date - INTERVAL '60 days' ELSE NULL END
    FROM permits_and_licenses pp
    WHERE pp.project_id = project_uuid
    ORDER BY pp.expiration_date;
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Project management software** (Procore, Buildertrend, CMiC)
- **Accounting systems** (QuickBooks, Sage, Oracle) for financial integration
- **Equipment tracking systems** for GPS and utilization monitoring
- **Safety management platforms** for incident reporting and training

### API Endpoints
- **Project management APIs** for schedule updates and progress tracking
- **Material procurement APIs** for automated ordering and receiving
- **Equipment monitoring APIs** for maintenance scheduling and alerts
- **Financial reporting APIs** for budget analysis and cost control

## Monitoring & Analytics

### Key Performance Indicators
- **Project completion rates** and schedule adherence
- **Cost performance** (earned value management, cost variance)
- **Safety metrics** (incident rates, training compliance)
- **Quality metrics** (defect rates, inspection pass rates)
- **Resource utilization** (equipment uptime, labor productivity)

### Real-Time Dashboards
```sql
-- Construction operations dashboard
CREATE VIEW construction_operations_dashboard AS
SELECT
    -- Project metrics
    (SELECT COUNT(*) FROM projects WHERE project_status = 'active') as active_projects,
    (SELECT AVG(completion_percentage) FROM projects WHERE project_status = 'active') as avg_project_completion,
    (SELECT COUNT(*) FROM projects WHERE actual_completion_date > planned_completion_date) as overdue_projects,

    -- Financial metrics
    (SELECT SUM(budgeted_amount) FROM projects WHERE project_status = 'active') as total_active_budget,
    (SELECT SUM(pc.cost_amount) FROM project_costs pc
     JOIN projects p ON pc.project_id = p.project_id
     WHERE p.project_status = 'active' AND pc.cost_date >= CURRENT_DATE - INTERVAL '30 days') as costs_this_month,

    -- Resource metrics
    (SELECT COUNT(*) FROM equipment WHERE equipment_status = 'available') as available_equipment,
    (SELECT COUNT(*) FROM employees WHERE availability_status = 'available') as available_labor,

    -- Quality and safety
    (SELECT COUNT(*) FROM quality_inspections WHERE inspection_date = CURRENT_DATE AND inspection_result = 'fail') as failed_inspections_today,
    (SELECT COUNT(*) FROM safety_incidents WHERE incident_date >= CURRENT_DATE - INTERVAL '7 days') as incidents_this_week,

    -- Material status
    (SELECT COUNT(*) FROM material_requirements WHERE requirement_status = 'received') as materials_received,
    (SELECT COUNT(*) FROM material_requirements WHERE actual_delivery_date > required_by_date) as late_deliveries
;
```

This construction database schema provides enterprise-grade infrastructure for project management, resource allocation, quality control, safety compliance, and financial oversight required for modern construction operations.
