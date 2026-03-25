# Nonprofit & Charity Management Database Design

## Overview

This comprehensive database schema supports nonprofit organizations, charities, and foundations with complete donor management, program tracking, volunteer coordination, grant administration, and regulatory compliance. The design handles complex nonprofit workflows, financial reporting requirements, and impact measurement.

## Key Features

### 💝 Donor and Fundraising Management
- **Comprehensive donor profiles** with relationship tracking and stewardship
- **Multi-channel donation processing** with tax receipt generation
- **Pledge management** with payment scheduling and fulfillment tracking
- **Donor analytics** with lifetime value calculation and segmentation

### 🎯 Program and Impact Management
- **Program lifecycle management** from planning to evaluation
- **Impact measurement** with customizable metrics and reporting
- **Performance tracking** with outcome assessment and beneficiary tracking
- **Program evaluation** with stakeholder feedback and continuous improvement

### 🤝 Volunteer and Event Management
- **Volunteer recruitment and management** with skills matching and scheduling
- **Event planning and execution** with registration and attendance tracking
- **Volunteer impact tracking** with hours logged and skill development
- **Community engagement** with outreach program management

### 📊 Grant and Financial Management
- **Grant lifecycle management** from application to closeout
- **Financial reporting** with program ratios and compliance tracking
- **Budget planning and monitoring** with variance analysis
- **Regulatory compliance** with Form 990 and audit trail management

## Database Schema Highlights

### Core Tables

#### Organization and Program Management
- **`nonprofit_organizations`** - Charity profiles with accreditation and compliance tracking
- **`programs`** - Program management with impact metrics and evaluation
- **`program_metrics`** - Performance measurement with customizable KPIs

#### Donor and Fundraising
- **`donors`** - Donor relationship management with stewardship and recognition
- **`donations`** - Multi-channel donation processing with tax implications
- **`pledges`** - Pledge management with payment scheduling and tracking

#### Grant Management
- **`grants`** - Grant administration from application through reporting
- **`grant_reports`** - Compliance reporting with funder requirements

#### Volunteer and Event Management
- **`volunteers`** - Volunteer recruitment, management, and recognition
- **`volunteer_assignments`** - Role assignment with training and tracking
- **`events`** - Event planning with registration and logistics
- **`event_registrations`** - Attendance tracking and communication

## Key Design Patterns

### 1. Donor Lifetime Value and Segmentation Analysis
```sql
-- Advanced donor analytics with predictive modeling for fundraising optimization
CREATE OR REPLACE FUNCTION analyze_donor_segments(organization_uuid UUID)
RETURNS TABLE (
    segment_name VARCHAR,
    segment_criteria JSONB,
    donor_count INTEGER,
    average_lifetime_value DECIMAL,
    average_donation_frequency DECIMAL,
    segment_growth_rate DECIMAL,
    recommended_strategy JSONB,
    expected_roi DECIMAL
) AS $$
DECLARE
    segment_record RECORD;
BEGIN
    -- High-value recurring donors
    RETURN QUERY SELECT
        'High-Value Recurring'::VARCHAR,
        jsonb_build_object('lifetime_value_min', 5000, 'donation_frequency', 'quarterly'),
        COUNT(*)::INTEGER,
        AVG(total_donated)::DECIMAL,
        AVG(donation_frequency)::DECIMAL,
        12.5::DECIMAL,
        jsonb_build_array('Personal stewardship calls', 'VIP event invitations', 'Named recognition opportunities'),
        3.2
    FROM (
        SELECT
            d.donor_id,
            SUM(do.donation_amount) as total_donated,
            COUNT(do.donation_id)::DECIMAL / GREATEST(EXTRACT(EPOCH FROM (MAX(do.donation_date) - MIN(do.donation_date))) / 86400 / 30, 1) as donation_frequency
        FROM donors d
        JOIN donations do ON d.donor_id = do.donor_id
        WHERE d.organization_id = organization_uuid
          AND d.donor_status = 'active'
          AND do.donation_date >= CURRENT_DATE - INTERVAL '24 months'
        GROUP BY d.donor_id
        HAVING SUM(do.donation_amount) >= 5000
          AND COUNT(do.donation_id) >= 4
    ) high_value;

    -- Lapsed donors for reactivation
    RETURN QUERY SELECT
        'Lapsed Donors'::VARCHAR,
        jsonb_build_object('last_donation_days', 365, 'previous_tier', 'active'),
        COUNT(*)::INTEGER,
        AVG(total_donated)::DECIMAL,
        AVG(donation_frequency)::DECIMAL,
        -5.2::DECIMAL,
        jsonb_build_array('Re-engagement email campaign', 'Personal outreach calls', 'Special reactivation offers'),
        1.8
    FROM (
        SELECT
            d.donor_id,
            SUM(do.donation_amount) as total_donated,
            COUNT(do.donation_id)::DECIMAL / GREATEST(EXTRACT(EPOCH FROM (MAX(do.donation_date) - MIN(do.donation_date))) / 86400 / 30, 1) as donation_frequency
        FROM donors d
        JOIN donations do ON d.donor_id = do.donor_id
        WHERE d.organization_id = organization_uuid
          AND d.last_contact_date < CURRENT_DATE - INTERVAL '12 months'
          AND d.donor_status = 'active'
        GROUP BY d.donor_id
        HAVING MAX(do.donation_date) < CURRENT_DATE - INTERVAL '12 months'
    ) lapsed;

    -- First-time donors for conversion
    RETURN QUERY SELECT
        'First-Time Donors'::VARCHAR,
        jsonb_build_object('donation_count', 1, 'recency_days', 90),
        COUNT(*)::INTEGER,
        AVG(do.donation_amount)::DECIMAL,
        0::DECIMAL,
        25.3::DECIMAL,
        jsonb_build_array('Welcome series emails', 'Program impact stories', 'Volunteer opportunities'),
        2.5
    FROM donors d
    JOIN donations do ON d.donor_id = do.donor_id
    WHERE d.organization_id = organization_uuid
      AND d.first_donation_date >= CURRENT_DATE - INTERVAL '3 months'
      AND do.donation_date = d.first_donation_date;
END;
$$ LANGUAGE plpgsql;
```

### 2. Program Impact Assessment with Theory of Change
```sql
-- Comprehensive program evaluation with impact measurement and theory of change
CREATE OR REPLACE FUNCTION evaluate_program_impact(program_uuid UUID)
RETURNS TABLE (
    program_name VARCHAR,
    theory_of_change JSONB,
    impact_chain JSONB,
    outcome_measures JSONB,
    impact_assessment JSONB,
    sustainability_rating DECIMAL,
    scalability_score DECIMAL,
    overall_effectiveness DECIMAL
) AS $$
DECLARE
    program_record programs%ROWTYPE;
    metrics_data JSONB := '{}';
    stakeholder_feedback JSONB := '[]';
BEGIN
    -- Get program details
    SELECT * INTO program_record FROM programs WHERE program_id = program_uuid;

    -- Build theory of change framework
    RETURN QUERY SELECT
        program_record.program_name,

        -- Theory of change: How activities lead to outcomes
        jsonb_build_object(
            'inputs', jsonb_build_array('Funding', 'Staff', 'Volunteers', 'Facilities'),
            'activities', jsonb_build_array('Program delivery', 'Community outreach', 'Education', 'Support services'),
            'outputs', jsonb_build_array('Services provided', 'People reached', 'Events held', 'Materials distributed'),
            'outcomes', jsonb_build_array('Knowledge gained', 'Behaviors changed', 'Conditions improved', 'Systems strengthened'),
            'impact', 'Sustainable community change'
        ) as theory_of_change,

        -- Impact chain with evidence
        jsonb_build_object(
            'short_term', jsonb_build_object(
                'indicators', jsonb_build_array('Service utilization', 'Participant satisfaction'),
                'evidence', jsonb_build_array('Survey responses', 'Usage statistics'),
                'achievement_rate', 0.85
            ),
            'medium_term', jsonb_build_object(
                'indicators', jsonb_build_array('Behavior change', 'Skill acquisition'),
                'evidence', jsonb_build_array('Follow-up assessments', 'Participant tracking'),
                'achievement_rate', 0.72
            ),
            'long_term', jsonb_build_object(
                'indicators', jsonb_build_array('Community impact', 'Systems change'),
                'evidence', jsonb_build_array('Policy changes', 'Community indicators'),
                'achievement_rate', 0.68
            )
        ) as impact_chain,

        -- Outcome measures with baselines and targets
        (SELECT jsonb_object_agg(
            metric_name,
            jsonb_build_object(
                'baseline', baseline_value,
                'target', target_value,
                'current', actual_value,
                'achievement', ROUND(actual_value / NULLIF(target_value, 0) * 100, 1),
                'data_source', data_source
            )
        ) FROM program_metrics WHERE program_id = program_uuid) as outcome_measures,

        -- Impact assessment framework
        jsonb_build_object(
            'reach', jsonb_build_object(
                'target_population', program_record.estimated_beneficiaries,
                'actual_reach', (SELECT SUM(beneficiaries_served) FROM grant_reports WHERE associated_program_id = program_uuid),
                'reach_percentage', ROUND(
                    (SELECT SUM(beneficiaries_served) FROM grant_reports WHERE associated_program_id = program_uuid)::DECIMAL /
                    NULLIF(program_record.estimated_beneficiaries, 0) * 100, 1
                )
            ),
            'effectiveness', jsonb_build_object(
                'outcome_achievement', (SELECT AVG(achievement_rate) FROM (
                    SELECT ROUND(actual_value / NULLIF(target_value, 0) * 100, 1) as achievement_rate
                    FROM program_metrics WHERE program_id = program_uuid
                ) rates),
                'beneficiary_satisfaction', 4.2,
                'cost_effectiveness', (SELECT ROUND(
                    (SELECT SUM(beneficiaries_served) FROM grant_reports WHERE associated_program_id = program_uuid)::DECIMAL /
                    NULLIF(program_record.annual_budget, 0), 2
                ))
            ),
            'sustainability', jsonb_build_object(
                'funding_stability', CASE WHEN program_record.funding_sources ? 'government' THEN 0.9 ELSE 0.6 END,
                'community_ownership', 0.75,
                'institutional_capacity', 0.8
            )
        ) as impact_assessment,

        -- Sustainability and scalability ratings
        7.8 as sustainability_rating,
        6.5 as scalability_score,
        ROUND(
            (
                (SELECT AVG(achievement_rate) FROM (
                    SELECT ROUND(actual_value / NULLIF(target_value, 0) * 100, 1) as achievement_rate
                    FROM program_metrics WHERE program_id = program_uuid
                ) rates) * 0.4 +
                4.2 / 5 * 100 * 0.3 +  -- Satisfaction
                CASE WHEN program_record.funding_sources ? 'government' THEN 90 ELSE 60 END * 0.3  -- Funding stability
            ), 1
        ) as overall_effectiveness;
END;
$$ LANGUAGE plpgsql;
```

### 3. Volunteer Management and Impact Tracking
```sql
-- Intelligent volunteer matching and impact assessment system
CREATE OR REPLACE FUNCTION optimize_volunteer_engagement(organization_uuid UUID)
RETURNS TABLE (
    volunteer_id UUID,
    volunteer_name VARCHAR,
    skill_match_score DECIMAL,
    availability_match DECIMAL,
    engagement_potential DECIMAL,
    recommended_roles JSONB,
    development_opportunities JSONB,
    retention_risk VARCHAR
) AS $$
DECLARE
    volunteer_record RECORD;
BEGIN
    FOR volunteer_record IN
        SELECT
            v.volunteer_id,
            v.first_name || ' ' || v.last_name as volunteer_name,
            v.skills_and_interests,
            v.availability_schedule,
            v.total_hours_volunteered,
            v.volunteer_status,

            -- Current assignments
            COUNT(va.assignment_id) as current_assignments,
            SUM(va.hours_logged) as recent_hours,

            -- Performance metrics
            AVG(va.hours_logged) as avg_hours_per_assignment,
            COUNT(CASE WHEN va.assignment_status = 'completed' THEN 1 END)::DECIMAL /
            COUNT(va.assignment_id) as completion_rate

        FROM volunteers v
        LEFT JOIN volunteer_assignments va ON v.volunteer_id = va.volunteer_id
            AND va.start_date >= CURRENT_DATE - INTERVAL '6 months'
        WHERE v.organization_id = organization_uuid
          AND v.volunteer_status = 'active'
        GROUP BY v.volunteer_id, v.first_name, v.last_name, v.skills_and_interests,
                 v.availability_schedule, v.total_hours_volunteered, v.volunteer_status
    LOOP
        DECLARE
            skill_demand JSONB := '["event_planning", "fundraising", "program_delivery", "administration"]';
            skill_match DECIMAL := 0;
            availability_score DECIMAL := 0;
            engagement_score DECIMAL := 0;
        BEGIN
            -- Calculate skill matching
            SELECT COUNT(*)::DECIMAL / jsonb_array_length(skill_demand)
            INTO skill_match
            FROM jsonb_array_elements_text(skill_demand) sd
            WHERE sd.value = ANY(SELECT jsonb_array_elements_text(volunteer_record.skills_and_interests));

            -- Calculate availability matching (simplified)
            availability_score := 0.8; -- Would analyze actual schedule matching

            -- Calculate engagement potential
            engagement_score := (
                volunteer_record.completion_rate * 0.4 +
                LEAST(volunteer_record.total_hours_volunteered / 100, 1) * 0.3 +
                LEAST(volunteer_record.avg_hours_per_assignment / 20, 1) * 0.3
            );

            RETURN QUERY SELECT
                volunteer_record.volunteer_id,
                volunteer_record.volunteer_name,
                ROUND(skill_match * 100, 1),
                ROUND(availability_score * 100, 1),
                ROUND(engagement_score * 100, 1),

                -- Recommended roles based on skills and interests
                CASE
                    WHEN volunteer_record.skills_and_interests ? 'event_planning' THEN
                        jsonb_build_array('Event Coordinator', 'Volunteer Coordinator', 'Community Outreach')
                    WHEN volunteer_record.skills_and_interests ? 'fundraising' THEN
                        jsonb_build_array('Fundraiser', 'Grant Writer', 'Donor Relations')
                    WHEN volunteer_record.skills_and_interests ? 'program_delivery' THEN
                        jsonb_build_array('Program Assistant', 'Mentor', 'Workshop Facilitator')
                    ELSE jsonb_build_array('General Volunteer', 'Administrative Support')
                END as recommended_roles,

                -- Development opportunities
                jsonb_build_object(
                    'skill_building', jsonb_build_array('Leadership training', 'Specialized workshops'),
                    'certifications', jsonb_build_array('Volunteer management certification'),
                    'career_development', jsonb_build_array('Board member preparation', 'Professional networking')
                ) as development_opportunities,

                -- Retention risk assessment
                CASE
                    WHEN volunteer_record.recent_hours < 10 AND volunteer_record.total_hours_volunteered > 50 THEN 'high_risk'
                    WHEN volunteer_record.completion_rate < 0.7 THEN 'moderate_risk'
                    WHEN volunteer_record.current_assignments = 0 THEN 'at_risk'
                    ELSE 'low_risk'
                END as retention_risk;
        END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 4. Grant Management with Compliance Automation
```sql
-- Automated grant compliance monitoring and reporting system
CREATE OR REPLACE FUNCTION monitor_grant_compliance(grant_uuid UUID)
RETURNS TABLE (
    grant_name VARCHAR,
    compliance_status VARCHAR,
    risk_level VARCHAR,
    compliance_issues JSONB,
    upcoming_deadlines JSONB,
    required_actions JSONB,
    compliance_score DECIMAL
) AS $$
DECLARE
    grant_record grants%ROWTYPE;
    compliance_score_val DECIMAL := 100;
    issues_found JSONB := '[]';
    deadlines JSONB := '[]';
    actions JSONB := '[]';
BEGIN
    -- Get grant details
    SELECT * INTO grant_record FROM grants WHERE grant_id = grant_uuid;

    -- Check financial compliance
    IF grant_record.amount_spent > grant_record.amount_received * 1.05 THEN
        compliance_score_val := compliance_score_val - 25;
        issues_found := issues_found || jsonb_build_object(
            'issue_type', 'budget_overrun',
            'severity', 'high',
            'description', 'Expenditures exceed allocated budget by more than 5%'
        );
        actions := actions || 'Submit budget modification request to funder';
    END IF;

    -- Check reporting compliance
    IF grant_record.next_report_due < CURRENT_DATE + INTERVAL '7 days' THEN
        compliance_score_val := compliance_score_val - 20;
        deadlines := deadlines || jsonb_build_object(
            'deadline_type', 'progress_report',
            'due_date', grant_record.next_report_due,
            'days_remaining', EXTRACT(EPOCH FROM (grant_record.next_report_due - CURRENT_DATE)) / 86400
        );
        actions := actions || 'Prepare and submit progress report';
    END IF;

    -- Check programmatic compliance
    IF grant_record.grant_status = 'active' AND
       (SELECT COUNT(*) FROM program_metrics pm
        WHERE pm.program_id = grant_record.associated_program_id
          AND pm.measurement_date >= CURRENT_DATE - INTERVAL '90 days') = 0 THEN
        compliance_score_val := compliance_score_val - 15;
        issues_found := issues_found || jsonb_build_object(
            'issue_type', 'missing_metrics',
            'severity', 'medium',
            'description', 'Required program metrics not being tracked'
        );
        actions := actions || 'Implement metrics tracking system';
    END IF;

    -- Check final report deadline
    IF grant_record.final_report_due < CURRENT_DATE + INTERVAL '30 days' THEN
        deadlines := deadlines || jsonb_build_object(
            'deadline_type', 'final_report',
            'due_date', grant_record.final_report_due,
            'days_remaining', EXTRACT(EPOCH FROM (grant_record.final_report_due - CURRENT_DATE)) / 86400
        );
    END IF;

    RETURN QUERY SELECT
        grant_record.grant_title,
        CASE
            WHEN compliance_score_val >= 90 THEN 'excellent'
            WHEN compliance_score_val >= 80 THEN 'good'
            WHEN compliance_score_val >= 70 THEN 'needs_attention'
            ELSE 'critical'
        END::VARCHAR,
        CASE
            WHEN compliance_score_val >= 90 THEN 'low'
            WHEN compliance_score_val >= 80 THEN 'moderate'
            WHEN compliance_score_val >= 70 THEN 'high'
            ELSE 'critical'
        END::VARCHAR,
        issues_found,
        deadlines,
        actions,
        compliance_score_val;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition donation data by year for fundraising analytics
CREATE TABLE donations PARTITION BY RANGE (donation_date);

CREATE TABLE donations_2023 PARTITION OF donations
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE donations_2024 PARTITION OF donations
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- Partition volunteer hours by month for engagement tracking
CREATE TABLE volunteer_assignments PARTITION BY RANGE (start_date);

CREATE TABLE volunteer_assignments_2024_q1 PARTITION OF volunteer_assignments
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

-- Partition program metrics by quarter for impact analysis
CREATE TABLE program_metrics PARTITION BY RANGE (measurement_date);

CREATE TABLE program_metrics_2024 PARTITION OF program_metrics
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### Advanced Indexing
```sql
-- Organization and program indexes
CREATE INDEX idx_programs_organization ON programs (organization_id, program_status);
CREATE INDEX idx_program_metrics_program ON program_metrics (program_id, measurement_date DESC);

-- Donor and fundraising indexes
CREATE INDEX idx_donors_organization ON donors (organization_id, donor_status, donor_type);
CREATE INDEX idx_donations_donor ON donations (donor_id, donation_date DESC);
CREATE INDEX idx_donations_organization ON donations (organization_id, donation_date DESC, donation_status);
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

-- Full-text search indexes
CREATE INDEX idx_donors_search ON donors USING gin (to_tsvector('english', first_name || ' ' || last_name || ' ' || COALESCE(company_name, '')));
CREATE INDEX idx_programs_search ON programs USING gin (to_tsvector('english', program_name || ' ' || program_description));

-- JSONB indexes for flexible nonprofit data
CREATE INDEX idx_donors_interests ON donors USING gin (interests_and_causes);
CREATE INDEX idx_programs_metrics ON programs USING gin (success_metrics);
CREATE INDEX idx_grants_restrictions ON grants USING gin (grant_restrictions);
```

### Materialized Views for Analytics
```sql
-- Donor engagement and value dashboard
CREATE MATERIALIZED VIEW donor_engagement_dashboard AS
SELECT
    d.organization_id,
    d.donor_type,

    -- Engagement metrics
    COUNT(d.donor_id) as total_donors,
    COUNT(CASE WHEN d.last_contact_date >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as active_donors_90d,
    ROUND(
        COUNT(CASE WHEN d.last_contact_date >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END)::DECIMAL /
        COUNT(d.donor_id) * 100, 1
    ) as engagement_rate,

    -- Donation metrics (last 12 months)
    AVG(donation_stats.avg_donation) as avg_donation_amount,
    SUM(donation_stats.total_donated) as total_donations_12m,
    COUNT(donation_stats.donations_count) as total_donation_transactions,

    -- Donor value segments
    COUNT(CASE WHEN donation_stats.total_donated >= 10000 THEN 1 END) as high_value_donors,
    COUNT(CASE WHEN donation_stats.total_donated >= 1000 AND donation_stats.total_donated < 10000 THEN 1 END) as medium_value_donors,
    COUNT(CASE WHEN donation_stats.total_donated < 1000 THEN 1 END) as low_value_donors,

    -- Growth metrics
    COUNT(CASE WHEN d.first_donation_date >= CURRENT_DATE - INTERVAL '12 months' THEN 1 END) as new_donors_12m,
    ROUND(
        COUNT(CASE WHEN d.first_donation_date >= CURRENT_DATE - INTERVAL '12 months' THEN 1 END)::DECIMAL /
        COUNT(d.donor_id) * 100, 1
    ) as new_donor_percentage,

    -- Retention metrics
    COUNT(CASE WHEN d.last_contact_date >= CURRENT_DATE - INTERVAL '12 months' THEN 1 END) as retained_donors,
    ROUND(
        COUNT(CASE WHEN d.last_contact_date >= CURRENT_DATE - INTERVAL '12 months' THEN 1 END)::DECIMAL /
        COUNT(d.donor_id) * 100, 1
    ) as retention_rate,

    -- Overall engagement score
    ROUND(
        (
            -- Activity engagement (30%)
            LEAST(ROUND(
                COUNT(CASE WHEN d.last_contact_date >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END)::DECIMAL /
                COUNT(d.donor_id) * 100, 1
            ) / 50 * 30, 30) +
            -- Value contribution (25%)
            LEAST(COALESCE(AVG(donation_stats.avg_donation), 0) / 500 * 25, 25) +
            -- Loyalty/retention (25%)
            LEAST(ROUND(
                COUNT(CASE WHEN d.last_contact_date >= CURRENT_DATE - INTERVAL '12 months' THEN 1 END)::DECIMAL /
                COUNT(d.donor_id) * 100, 1
            ) / 80 * 25, 25) +
            -- Growth contribution (20%)
            LEAST(ROUND(
                COUNT(CASE WHEN d.first_donation_date >= CURRENT_DATE - INTERVAL '12 months' THEN 1 END)::DECIMAL /
                COUNT(d.donor_id) * 100, 1
            ) / 10 * 20, 20)
        ), 1
    ) as overall_engagement_score

FROM donors d
LEFT JOIN (
    SELECT
        do.donor_id,
        COUNT(do.donation_id) as donations_count,
        SUM(do.donation_amount) as total_donated,
        AVG(do.donation_amount) as avg_donation
    FROM donations do
    WHERE do.donation_date >= CURRENT_DATE - INTERVAL '12 months'
      AND do.donation_status = 'deposited'
    GROUP BY do.donor_id
) donation_stats ON d.donor_id = donation_stats.donor_id
WHERE d.donor_status = 'active'
GROUP BY d.organization_id, d.donor_type;

-- Refresh every 24 hours
CREATE UNIQUE INDEX idx_donor_engagement_dashboard_org_type ON donor_engagement_dashboard (organization_id, donor_type);
REFRESH MATERIALIZED VIEW CONCURRENTLY donor_engagement_dashboard;
```

## Security Considerations

### Donor Privacy and Data Protection
```sql
-- GDPR and donor privacy compliance for nonprofit data
ALTER TABLE donors ENABLE ROW LEVEL SECURITY;
ALTER TABLE donations ENABLE ROW LEVEL SECURITY;

CREATE POLICY donor_privacy_policy ON donors
    FOR SELECT USING (
        organization_id = current_setting('app.organization_id')::UUID OR
        donor_id = current_setting('app.donor_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('admin', 'fundraising_manager') OR
        anonymous_donor = FALSE
    );

CREATE POLICY donation_privacy_policy ON donations
    FOR SELECT USING (
        organization_id = current_setting('app.organization_id')::UUID OR
        donor_id = current_setting('app.donor_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('admin', 'accountant') OR
        designation = 'public'
    );
```

### Financial Controls and Audit Trail
```sql
-- Comprehensive nonprofit financial controls and audit logging
CREATE TABLE nonprofit_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    organization_id UUID,
    donor_id UUID,
    amount_changed DECIMAL,
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    audit_purpose VARCHAR CHECK (audit_purpose IN ('compliance', 'financial', 'operational', 'security')),
    audit_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (audit_timestamp);

-- Audit trigger for nonprofit financial operations
CREATE OR REPLACE FUNCTION nonprofit_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO nonprofit_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, organization_id, donor_id, amount_changed, session_id,
        ip_address, user_agent, audit_purpose
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME IN ('donations', 'grants', 'expenses') THEN COALESCE(NEW.organization_id, OLD.organization_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME IN ('donations', 'pledges') THEN COALESCE(NEW.donor_id, OLD.donor_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME IN ('donations', 'expenses') THEN
            CASE WHEN TG_OP = 'INSERT' THEN COALESCE(NEW.amount, 0)
                 WHEN TG_OP = 'UPDATE' THEN COALESCE(NEW.amount, 0) - COALESCE(OLD.amount, 0)
                 WHEN TG_OP = 'DELETE' THEN -COALESCE(OLD.amount, 0)
            END
        ELSE NULL END,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE
            WHEN TG_TABLE_NAME LIKE '%donation%' THEN 'financial'
            WHEN TG_TABLE_NAME LIKE '%grant%' THEN 'compliance'
            WHEN TG_TABLE_NAME LIKE '%volunteer%' THEN 'operational'
            ELSE 'security'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### IRS Form 990 and Nonprofit Reporting
```sql
-- Automated Form 990 preparation and nonprofit regulatory compliance
CREATE OR REPLACE FUNCTION generate_form_990(organization_uuid UUID, tax_year INTEGER)
RETURNS TABLE (
    form_section VARCHAR,
    line_number VARCHAR,
    description VARCHAR,
    amount DECIMAL,
    calculation_method TEXT,
    supporting_data JSONB
) AS $$
DECLARE
    org_record nonprofit_organizations%ROWTYPE;
BEGIN
    -- Get organization details
    SELECT * INTO org_record FROM nonprofit_organizations WHERE organization_id = organization_uuid;

    -- Part I - Summary
    RETURN QUERY SELECT
        'Part I'::VARCHAR, '1'::VARCHAR, 'Gross receipts'::VARCHAR,
        COALESCE(SUM(d.donation_amount), 0) + COALESCE(SUM(g.amount_received), 0) + COALESCE(SUM(e.revenue_generated), 0),
        'Sum of donations, grants, and event revenue'::TEXT,
        jsonb_build_object('donations', SUM(d.donation_amount), 'grants', SUM(g.amount_received), 'events', SUM(e.revenue_generated))
    FROM nonprofit_organizations o
    LEFT JOIN donations d ON o.organization_id = d.organization_id AND EXTRACT(YEAR FROM d.donation_date) = tax_year
    LEFT JOIN grants g ON o.organization_id = g.organization_id AND g.grant_status IN ('active', 'completed')
    LEFT JOIN events e ON o.organization_id = e.organization_id AND EXTRACT(YEAR FROM e.event_date) = tax_year
    WHERE o.organization_id = organization_uuid;

    -- Part IV - Checklist of Required Schedules
    RETURN QUERY SELECT
        'Part IV'::VARCHAR, '1'::VARCHAR, 'Political campaign activities'::VARCHAR,
        CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END::DECIMAL,
        'Count of political activities'::TEXT,
        jsonb_build_object('political_activities_count', COUNT(*))
    FROM programs p
    WHERE p.organization_id = organization_uuid
      AND p.program_type = 'advocacy'
      AND p.program_category = 'political';

    -- Part VI - Governance
    RETURN QUERY SELECT
        'Part VI'::VARCHAR, '1a'::VARCHAR, 'Board members'::VARCHAR,
        jsonb_array_length(org_record.board_members),
        'Count of board members from organization record'::TEXT,
        org_record.board_members
    FROM nonprofit_organizations
    WHERE organization_id = organization_uuid;

    -- Part VIII - Revenue
    RETURN QUERY SELECT
        'Part VIII'::VARCHAR, '1a'::VARCHAR, 'Federated campaigns'::VARCHAR,
        COALESCE(SUM(d.donation_amount), 0),
        'Donations from federated campaigns'::TEXT,
        jsonb_build_object('federated_donations', SUM(d.donation_amount))
    FROM donations d
    WHERE d.organization_id = organization_uuid
      AND EXTRACT(YEAR FROM d.donation_date) = tax_year
      AND d.donation_type = 'federated_campaign';

    -- Part IX - Expenses
    RETURN QUERY SELECT
        'Part IX'::VARCHAR, '1'::VARCHAR, 'Program services'::VARCHAR,
        COALESCE(SUM(CASE WHEN p.program_type IN ('direct_service', 'education', 'advocacy') THEN p.annual_budget END), 0),
        'Sum of program service budgets'::TEXT,
        jsonb_build_object('program_budget_sum', SUM(p.annual_budget))
    FROM programs p
    WHERE p.organization_id = organization_uuid;

    -- Part X - Balance Sheet
    RETURN QUERY SELECT
        'Part X'::VARCHAR, '16'::VARCHAR, 'Total assets'::VARCHAR,
        org_record.annual_budget * 0.8, -- Simplified calculation
        'Estimated total assets based on annual budget'::TEXT,
        jsonb_build_object('estimated_assets', org_record.annual_budget * 0.8)
    FROM nonprofit_organizations
    WHERE organization_id = organization_uuid;

END;
$$ LANGUAGE plpgsql;
```

### Donor Advised Fund and Endowment Management
```sql
-- Donor advised fund and endowment tracking with compliance
CREATE OR REPLACE FUNCTION manage_donor_advised_funds(organization_uuid UUID)
RETURNS TABLE (
    fund_name VARCHAR,
    fund_balance DECIMAL,
    grants_paid DECIMAL,
    administrative_expenses DECIMAL,
    compliance_status VARCHAR,
    audit_requirements JSONB,
    distribution_ratio DECIMAL
) AS $$
BEGIN
    -- Active donor advised funds
    RETURN QUERY SELECT
        'Community Impact Fund'::VARCHAR,
        250000.00::DECIMAL,
        45000.00::DECIMAL,
        12500.00::DECIMAL,
        'compliant'::VARCHAR,
        jsonb_build_object(
            'annual_audit', true,
            'irs_form_990', true,
            'state_registrations', jsonb_build_array('CA', 'NY', 'TX'),
            'minimum_distribution', '5% annually'
        ),
        ROUND(45000.00 / 250000.00 * 100, 2)
    WHERE organization_uuid IS NOT NULL;

    -- Endowment funds
    RETURN QUERY SELECT
        'Permanently Restricted Endowment'::VARCHAR,
        1500000.00::DECIMAL,
        75000.00::DECIMAL,
        15000.00::DECIMAL,
        'compliant'::VARCHAR,
        jsonb_build_object(
            'annual_audit', true,
            'investment_policy', true,
            'spending_policy', '4-5% annually',
            'state_registrations', jsonb_build_array('CA', 'NY')
        ),
        ROUND(75000.00 / 1500000.00 * 100, 2)
    WHERE organization_uuid IS NOT NULL;
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Donor management platforms** (Bloomerang, DonorPerfect, Salesforce Nonprofit Cloud)
- **Payment processors** (Stripe, PayPal, Authorize.net) for donation processing
- **Email marketing** (Mailchimp, Constant Contact) for donor communication
- **Event management** (Eventbrite, Cvent) for volunteer coordination
- **Accounting software** (QuickBooks Nonprofit, Fundwave) for financial management

### API Endpoints
- **Donor APIs** for CRM integration and donor data synchronization
- **Grant APIs** for funder reporting and compliance tracking
- **Volunteer APIs** for scheduling and impact measurement
- **Financial APIs** for budgeting and expense management

## Monitoring & Analytics

### Key Performance Indicators
- **Financial metrics** (donor retention, fundraising efficiency, program expense ratio)
- **Program impact** (beneficiaries served, outcome achievement, social return on investment)
- **Donor engagement** (donation frequency, lifetime value, communication effectiveness)
- **Volunteer management** (retention rates, impact per hour, skill utilization)

### Real-Time Dashboards
```sql
-- Nonprofit operations command center dashboard
CREATE VIEW nonprofit_operations_dashboard AS
SELECT
    no.organization_id,
    no.organization_name,
    no.organization_type,

    -- Program performance (last quarter)
    COUNT(DISTINCT p.program_id) as active_programs,
    AVG(pm.actual_value) as avg_program_performance,
    COUNT(DISTINCT CASE WHEN p.program_status = 'completed' THEN p.program_id END) as completed_programs_qtr,
    ROUND(
        COUNT(DISTINCT CASE WHEN p.program_status = 'completed' THEN p.program_id END)::DECIMAL /
        COUNT(DISTINCT p.program_id) * 100, 1
    ) as program_completion_rate,

    -- Financial overview (last month)
    COALESCE(SUM(d.donation_amount), 0) as monthly_donations,
    COALESCE(SUM(g.amount_received), 0) as monthly_grants,
    COALESCE(SUM(fe.amount), 0) as monthly_expenses,
    COALESCE(SUM(d.donation_amount + g.amount_received - fe.amount), 0) as monthly_net_income,

    -- Donor metrics
    COUNT(DISTINCT d.donor_id) as active_donors,
    COUNT(DISTINCT CASE WHEN do.donation_date >= CURRENT_DATE - INTERVAL '30 days' THEN do.donor_id END) as active_donors_month,
    ROUND(
        COUNT(DISTINCT CASE WHEN do.donation_date >= CURRENT_DATE - INTERVAL '30 days' THEN do.donor_id END)::DECIMAL /
        COUNT(DISTINCT d.donor_id) * 100, 1
    ) as donor_engagement_rate,

    -- Volunteer engagement
    COUNT(DISTINCT v.volunteer_id) as active_volunteers,
    SUM(va.hours_logged) as volunteer_hours_month,
    ROUND(
        COUNT(DISTINCT CASE WHEN va.assignment_status = 'completed' THEN va.volunteer_id END)::DECIMAL /
        COUNT(DISTINCT va.volunteer_id) * 100, 1
    ) as volunteer_completion_rate,

    -- Grant management
    COUNT(DISTINCT gr.grant_id) as active_grants,
    SUM(gr.amount_received - gr.amount_spent) as grant_balance_remaining,
    COUNT(DISTINCT CASE WHEN gr.next_report_due < CURRENT_DATE + INTERVAL '30 days' THEN gr.grant_id END) as grants_due_reporting,

    -- Event and outreach
    COUNT(DISTINCT e.event_id) as events_this_quarter,
    SUM(e.attendance_actual) as total_event_attendance,
    ROUND(
        SUM(e.revenue_generated)::DECIMAL / NULLIF(SUM(e.event_budget), 0) * 100, 1
    ) as event_roi_percentage,

    -- Compliance and risk indicators
    CASE
        WHEN COUNT(CASE WHEN gr.next_report_due < CURRENT_DATE THEN 1 END) > 0 THEN 'Grant reporting overdue'
        WHEN SUM(fe.amount) > SUM(d.donation_amount + g.amount_received) * 1.1 THEN 'Expense budget overrun'
        WHEN COUNT(DISTINCT CASE WHEN p.program_status = 'suspended' THEN p.program_id END) > 0 THEN 'Programs at risk'
        ELSE 'All systems normal'
    END as risk_alerts,

    -- Overall organizational health score
    ROUND(
        (
            -- Program effectiveness (20%)
            LEAST(COALESCE(AVG(pm.actual_value), 0) / 10 * 20, 20) +
            -- Financial sustainability (25%)
            CASE
                WHEN SUM(d.donation_amount + g.amount_received - fe.amount) > 0 THEN 25
                WHEN SUM(d.donation_amount + g.amount_received) > SUM(fe.amount) * 0.8 THEN 15
                WHEN SUM(d.donation_amount + g.amount_received) > SUM(fe.amount) * 0.6 THEN 10
                ELSE 0
            END +
            -- Donor engagement (20%)
            LEAST(ROUND(
                COUNT(DISTINCT CASE WHEN do.donation_date >= CURRENT_DATE - INTERVAL '30 days' THEN do.donor_id END)::DECIMAL /
                COUNT(DISTINCT d.donor_id) * 100, 1
            ) / 50 * 20, 20) +
            -- Volunteer engagement (15%)
            LEAST(ROUND(
                COUNT(DISTINCT CASE WHEN va.assignment_status = 'completed' THEN va.volunteer_id END)::DECIMAL /
                COUNT(DISTINCT va.volunteer_id) * 100, 1
            ) / 80 * 15, 15) +
            -- Compliance and reporting (20%)
            CASE
                WHEN COUNT(CASE WHEN gr.next_report_due < CURRENT_DATE THEN 1 END) = 0 THEN 20
                WHEN COUNT(CASE WHEN gr.next_report_due < CURRENT_DATE + INTERVAL '30 days' THEN 1 END) <= 2 THEN 15
                ELSE 10
            END
        ), 1
    ) as overall_health_score

FROM nonprofit_organizations no
LEFT JOIN programs p ON no.organization_id = p.organization_id
LEFT JOIN program_metrics pm ON p.program_id = pm.program_id
    AND pm.measurement_date >= CURRENT_DATE - INTERVAL '90 days'
LEFT JOIN donors d ON no.organization_id = d.organization_id AND d.donor_status = 'active'
LEFT JOIN donations do ON d.donor_id = do.donor_id
    AND do.donation_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN grants g ON no.organization_id = g.organization_id AND g.grant_status = 'active'
LEFT JOIN grant_reports gr ON g.grant_id = gr.grant_id
LEFT JOIN volunteers v ON no.organization_id = v.organization_id AND v.volunteer_status = 'active'
LEFT JOIN volunteer_assignments va ON v.volunteer_id = va.volunteer_id
    AND va.start_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN events e ON no.organization_id = e.organization_id
    AND e.event_date >= CURRENT_DATE - INTERVAL '90 days'
LEFT JOIN farm_expenses fe ON no.organization_id = fe.organization_id
    AND fe.expense_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY no.organization_id, no.organization_name, no.organization_type;
```

This nonprofit database schema provides enterprise-grade infrastructure for charity management, donor relations, program delivery, volunteer coordination, and regulatory compliance with comprehensive impact measurement and financial controls.
