# Legal Services & Case Management Database Design

## Overview

This comprehensive database schema supports law firm operations, legal case management, document handling, time tracking, billing systems, and regulatory compliance. The design handles complex legal workflows, confidentiality requirements, deadline management, and multi-jurisdictional operations.

## Key Features

### ⚖️ Case and Matter Management
- **Comprehensive case lifecycle tracking** from intake to resolution
- **Multi-jurisdictional support** with court-specific requirements
- **Conflict checking and ethical wall management** for compliance
- **Matter categorization** with practice areas and case types

### 👥 Client Relationship Management
- **Client intake and onboarding** with KYC compliance
- **Client tier management** with relationship tracking
- **Communication preferences** and privacy settings
- **Client satisfaction tracking** and feedback systems

### ⏱️ Time Tracking and Billing
- **Automated time entry** with billing increment rules
- **Matter-based billing** with multiple rate structures
- **Trust account management** with IOLTA compliance
- **Invoice generation** and payment processing

### 📄 Document and Knowledge Management
- **Document versioning and privilege logging** with legal holds
- **Secure document storage** with access controls
- **Court filing tracking** and deadline management
- **Knowledge base** for precedent and research materials

## Database Schema Highlights

### Core Tables

#### Firm and Attorney Management
- **`law_firms`** - Firm profiles with accreditation and compliance tracking
- **`attorneys`** - Attorney credentials, billing rates, and performance metrics
- **`clients`** - Client profiles with KYC status and relationship management

#### Case Management
- **`matters`** - Legal matters with lifecycle tracking and team assignment
- **`documents`** - Document management with privilege and security controls
- **`case_events`** - Court dates, hearings, and case milestones

#### Time and Financial Management
- **`time_entries`** - Time tracking with activity categorization
- **`invoices`** - Billing with line items and payment tracking
- **`expenses`** - Expense management with approval workflows
- **`trust_accounts`** - IOLTA compliance and account management

## Key Design Patterns

### 1. Conflict Checking and Ethical Wall Management
```sql
-- Automated conflict checking for new client matters
CREATE OR REPLACE FUNCTION perform_conflict_check(
    client_uuid UUID,
    matter_description TEXT,
    assigned_attorney UUID
)
RETURNS TABLE (
    conflict_status VARCHAR,
    conflict_severity VARCHAR,
    conflicting_matters JSONB,
    recommended_actions JSONB,
    requires_partner_approval BOOLEAN
) AS $$
DECLARE
    client_record clients%ROWTYPE;
    conflicting_matters_count INTEGER := 0;
    conflict_details JSONB := '[]';
BEGIN
    -- Get client details
    SELECT * INTO client_record FROM clients WHERE client_id = client_uuid;

    -- Check for direct conflicts (same client, opposing parties)
    SELECT COUNT(*), jsonb_agg(jsonb_build_object(
        'matter_id', m.matter_id,
        'matter_title', m.matter_title,
        'opposing_party', m.opposing_party,
        'lead_attorney', a.first_name || ' ' || a.last_name
    ))
    INTO conflicting_matters_count, conflict_details
    FROM matters m
    JOIN attorneys a ON m.lead_attorney_id = a.attorney_id
    WHERE m.client_id = client_uuid
       OR m.opposing_party ILIKE '%' || client_record.company_name || '%'
       OR m.opposing_party ILIKE '%' || client_record.first_name || '%'
       OR (client_record.last_name IS NOT NULL AND m.opposing_party ILIKE '%' || client_record.last_name || '%');

    -- Check for indirect conflicts (related entities)
    IF conflicting_matters_count = 0 THEN
        SELECT COUNT(*), jsonb_agg(jsonb_build_object(
            'matter_id', m.matter_id,
            'conflict_type', 'related_entity',
            'description', 'Matter involves related business entity'
        ))
        INTO conflicting_matters_count, conflict_details
        FROM matters m
        WHERE m.matter_id IN (
            SELECT DISTINCT m2.matter_id
            FROM matters m2
            JOIN clients c2 ON m2.client_id = c2.client_id
            WHERE c2.industry = client_record.industry
              AND c2.client_id != client_uuid
              AND m2.matter_type = 'litigation'
        );
    END IF;

    -- Determine conflict status and actions
    IF conflicting_matters_count > 0 THEN
        RETURN QUERY SELECT
            'conflict_detected'::VARCHAR,
            CASE WHEN conflicting_matters_count > 2 THEN 'high' ELSE 'medium' END::VARCHAR,
            conflict_details,
            jsonb_build_array(
                'Implement ethical wall/screening procedures',
                'Obtain informed consent from all affected parties',
                CASE WHEN conflicting_matters_count > 2 THEN 'Escalate to managing partner for review' ELSE 'Document conflict check results' END
            ),
            (conflicting_matters_count > 2)::BOOLEAN;
    ELSE
        RETURN QUERY SELECT
            'no_conflict'::VARCHAR,
            'none'::VARCHAR,
            '[]'::JSONB,
            jsonb_build_array('Proceed with matter assignment'),
            FALSE::BOOLEAN;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

### 2. Automated Statute of Limitations Tracking
```sql
-- Intelligent statute of limitations monitoring and alerts
CREATE OR REPLACE FUNCTION monitor_statute_of_limitations()
RETURNS TABLE (
    matter_id UUID,
    matter_title VARCHAR,
    statute_type VARCHAR,
    trigger_date DATE,
    expiration_date DATE,
    days_remaining INTEGER,
    alert_level VARCHAR,
    recommended_actions JSONB
) AS $$
DECLARE
    jurisdiction_rules JSONB := '{
        "contract": {"limitation_period": 6, "unit": "years"},
        "tort": {"limitation_period": 2, "unit": "years"},
        "property": {"limitation_period": 10, "unit": "years"},
        "employment": {"limitation_period": 180, "unit": "days"},
        "intellectual_property": {"limitation_period": 3, "unit": "years"}
    }';
    matter_record RECORD;
BEGIN
    FOR matter_record IN
        SELECT
            m.matter_id,
            m.matter_title,
            m.matter_type,
            m.opened_date,
            m.statute_of_limitations,
            CASE
                WHEN m.matter_type = 'transaction' THEN 'contract'
                WHEN m.matter_type = 'litigation' THEN
                    CASE
                        WHEN m.practice_area = 'employment' THEN 'employment'
                        WHEN m.practice_area = 'intellectual_property' THEN 'intellectual_property'
                        ELSE 'tort'
                    END
                ELSE 'contract'
            END as statute_category
        FROM matters m
        WHERE m.matter_status NOT IN ('closed', 'settled', 'dismissed')
          AND m.statute_of_limitations IS NOT NULL
    LOOP
        DECLARE
            limitation_period INTEGER;
            expiration_calc DATE;
            days_remaining_calc INTEGER;
        BEGIN
            -- Get limitation period from rules
            limitation_period := (jurisdiction_rules->matter_record.statute_category->>'limitation_period')::INTEGER;

            -- Calculate expiration date if not set
            IF matter_record.statute_of_limitations IS NULL THEN
                expiration_calc := matter_record.opened_date + INTERVAL '1 year' * limitation_period;
            ELSE
                expiration_calc := matter_record.statute_of_limitations;
            END IF;

            days_remaining_calc := EXTRACT(EPOCH FROM (expiration_calc - CURRENT_DATE)) / 86400;

            -- Generate alerts based on time remaining
            IF days_remaining_calc <= 365 THEN
                RETURN QUERY SELECT
                    matter_record.matter_id,
                    matter_record.matter_title,
                    matter_record.statute_category,
                    matter_record.opened_date,
                    expiration_calc,
                    days_remaining_calc,
                    CASE
                        WHEN days_remaining_calc <= 30 THEN 'critical'
                        WHEN days_remaining_calc <= 90 THEN 'high'
                        WHEN days_remaining_calc <= 180 THEN 'medium'
                        ELSE 'low'
                    END::VARCHAR,
                    CASE
                        WHEN days_remaining_calc <= 30 THEN jsonb_build_array(
                            'Immediate filing required',
                            'Consult with client on urgency',
                            'Consider tolling agreement'
                        )
                        WHEN days_remaining_calc <= 90 THEN jsonb_build_array(
                            'Begin drafting complaint/motion',
                            'Schedule client consultation',
                            'Review evidence availability'
                        )
                        ELSE jsonb_build_array(
                            'Continue standard case preparation',
                            'Monitor deadline calendar'
                        )
                    END;
            END IF;
        END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 3. Dynamic Billing Rate Optimization
```sql
-- Intelligent billing rate optimization based on matter complexity and market rates
CREATE OR REPLACE FUNCTION optimize_billing_rates(
    firm_uuid UUID,
    practice_area_filter VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    attorney_id UUID,
    attorney_name VARCHAR,
    current_rate DECIMAL,
    recommended_rate DECIMAL,
    rate_variance_percentage DECIMAL,
    optimization_reason VARCHAR,
    market_comparison JSONB,
    implementation_impact JSONB
) AS $$
DECLARE
    market_rates JSONB := '{
        "junior_associate": {"min": 200, "avg": 275, "max": 350},
        "senior_associate": {"min": 300, "avg": 425, "max": 550},
        "partner": {"min": 400, "avg": 650, "max": 1000},
        "specialist": {"min": 500, "avg": 750, "max": 1200}
    }';
    attorney_record RECORD;
BEGIN
    FOR attorney_record IN
        SELECT
            a.attorney_id,
            a.first_name || ' ' || a.last_name as attorney_name,
            a.job_title,
            a.hourly_rate,
            a.years_experience,
            a.practice_areas,
            a.client_satisfaction_rating,
            a.case_win_rate,

            -- Performance metrics
            AVG(te.billed_amount / (te.duration_minutes / 60.0)) as effective_rate,
            COUNT(te.time_entry_id) as total_entries,
            AVG(te.work_quality_rating) as avg_quality_rating,

            -- Matter complexity (based on practice area and case value)
            AVG(m.estimated_fee) as avg_matter_value,
            COUNT(CASE WHEN m.matter_status IN ('won', 'settled') THEN 1 END)::DECIMAL /
            COUNT(m.matter_id) as success_rate

        FROM attorneys a
        LEFT JOIN time_entries te ON a.attorney_id = te.attorney_id
            AND te.entry_date >= CURRENT_DATE - INTERVAL '6 months'
        LEFT JOIN matters m ON a.attorney_id = m.lead_attorney_id
        WHERE a.firm_id = firm_uuid
          AND a.work_status = 'active'
          AND (practice_area_filter IS NULL OR practice_area_filter = ANY(a.practice_areas))
        GROUP BY a.attorney_id, a.first_name, a.last_name, a.job_title, a.hourly_rate,
                 a.years_experience, a.practice_areas, a.client_satisfaction_rating, a.case_win_rate
    LOOP
        DECLARE
            attorney_tier VARCHAR;
            market_rate_range JSONB;
            recommended_rate_calc DECIMAL;
            variance_pct DECIMAL;
        BEGIN
            -- Determine attorney tier
            attorney_tier := CASE
                WHEN attorney_record.years_experience < 5 THEN 'junior_associate'
                WHEN attorney_record.years_experience < 10 THEN 'senior_associate'
                WHEN attorney_record.job_title ILIKE '%partner%' THEN 'partner'
                WHEN attorney_record.job_title ILIKE '%specialist%' THEN 'specialist'
                ELSE 'senior_associate'
            END;

            market_rate_range := market_rates->attorney_tier;

            -- Calculate recommended rate based on performance and complexity
            recommended_rate_calc := (market_rate_range->>'avg')::DECIMAL +
                (attorney_record.avg_quality_rating - 3) * 25 +  -- Quality adjustment
                (attorney_record.success_rate - 0.5) * 50 +       -- Success rate adjustment
                LEAST(attorney_record.avg_matter_value / 100000, 2) * 50; -- Complexity adjustment

            -- Ensure rate is within market bounds
            recommended_rate_calc := GREATEST(
                LEAST(recommended_rate_calc, (market_rate_range->>'max')::DECIMAL),
                (market_rate_range->>'min')::DECIMAL
            );

            variance_pct := ((recommended_rate_calc - attorney_record.hourly_rate) / attorney_record.hourly_rate) * 100;

            -- Only recommend changes > 5%
            IF ABS(variance_pct) >= 5 THEN
                RETURN QUERY SELECT
                    attorney_record.attorney_id,
                    attorney_record.attorney_name,
                    attorney_record.hourly_rate,
                    ROUND(recommended_rate_calc, 0),
                    ROUND(variance_pct, 1),
                    CASE
                        WHEN variance_pct > 10 THEN 'Rate significantly below market value - consider increase'
                        WHEN variance_pct < -10 THEN 'Rate above market value - consider decrease or value demonstration'
                        WHEN variance_pct > 0 THEN 'Rate slightly below market - gradual increase recommended'
                        ELSE 'Rate competitive - maintain current pricing'
                    END::VARCHAR,
                    jsonb_build_object(
                        'tier', attorney_tier,
                        'market_range', market_rate_range,
                        'performance_score', attorney_record.avg_quality_rating,
                        'success_rate', attorney_record.success_rate
                    ),
                    jsonb_build_object(
                        'estimated_annual_impact', ROUND(variance_pct * attorney_record.hourly_rate * 2000 / 100, 0),
                        'market_positioning', CASE
                            WHEN recommended_rate_calc >= (market_rate_range->>'max')::DECIMAL THEN 'premium'
                            WHEN recommended_rate_calc >= (market_rate_range->>'avg')::DECIMAL THEN 'competitive'
                            ELSE 'value'
                        END
                    );
            END IF;
        END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 4. Secure Document Management with Audit Trail
```sql
-- Comprehensive document security and audit logging
CREATE OR REPLACE FUNCTION secure_document_access(
    document_uuid UUID,
    user_uuid UUID,
    access_type VARCHAR -- 'view', 'edit', 'download', 'delete'
)
RETURNS TABLE (
    access_granted BOOLEAN,
    access_reason VARCHAR,
    security_clearance_level VARCHAR,
    audit_log_entry JSONB
) AS $$
DECLARE
    document_record documents%ROWTYPE;
    user_record attorneys%ROWTYPE;
    access_granted_val BOOLEAN := FALSE;
    access_reason_val VARCHAR := '';
    clearance_level VARCHAR := 'none';
    audit_entry JSONB;
BEGIN
    -- Get document and user details
    SELECT * INTO document_record FROM documents WHERE document_id = document_uuid;
    SELECT * INTO user_record FROM attorneys WHERE attorney_id = user_uuid;

    -- Check confidentiality level requirements
    CASE document_record.confidentiality_level
        WHEN 'public' THEN
            access_granted_val := TRUE;
            access_reason_val := 'Public document - no restrictions';
            clearance_level := 'public';

        WHEN 'confidential' THEN
            -- Check if user is assigned to the matter
            IF EXISTS (
                SELECT 1 FROM matters m
                WHERE m.matter_id = document_record.matter_id
                  AND (m.lead_attorney_id = user_uuid OR user_uuid = ANY(m.assigned_attorneys))
            ) THEN
                access_granted_val := TRUE;
                access_reason_val := 'Authorized team member access';
                clearance_level := 'confidential';
            ELSE
                access_reason_val := 'Access denied - not assigned to matter';
            END IF;

        WHEN 'privileged' THEN
            -- Only lead attorney and partners can access privileged documents
            IF document_record.author_id = user_uuid OR user_record.job_title ILIKE '%partner%' THEN
                access_granted_val := TRUE;
                access_reason_val := 'Attorney work product privilege';
                clearance_level := 'privileged';
            ELSE
                access_reason_val := 'Access denied - attorney work product privilege';
            END IF;

        WHEN 'highly_sensitive' THEN
            -- Only specific authorized personnel
            IF document_record.author_id = user_uuid OR
               user_record.job_title ILIKE '%managing partner%' THEN
                access_granted_val := TRUE;
                access_reason_val := 'Highly sensitive material - restricted access';
                clearance_level := 'highly_sensitive';
            ELSE
                access_reason_val := 'Access denied - highly sensitive material';
            END IF;
    END CASE;

    -- Additional checks for edit/delete operations
    IF access_granted_val AND access_type IN ('edit', 'delete') THEN
        IF document_record.author_id != user_uuid AND user_record.job_title NOT ILIKE '%partner%' THEN
            access_granted_val := FALSE;
            access_reason_val := 'Edit/delete access limited to document author or partners';
        END IF;
    END IF;

    -- Create audit log entry
    audit_entry := jsonb_build_object(
        'timestamp', CURRENT_TIMESTAMP,
        'document_id', document_uuid,
        'user_id', user_uuid,
        'access_type', access_type,
        'access_granted', access_granted_val,
        'access_reason', access_reason_val,
        'ip_address', inet_client_addr(),
        'user_agent', current_setting('app.user_agent', TRUE)
    );

    -- Log the access attempt
    INSERT INTO document_access_log (
        document_id, user_id, access_type, access_granted,
        access_reason, clearance_level, audit_details
    ) VALUES (
        document_uuid, user_uuid, access_type, access_granted_val,
        access_reason_val, clearance_level, audit_entry
    );

    RETURN QUERY SELECT
        access_granted_val,
        access_reason_val,
        clearance_level,
        audit_entry;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition time entries by month for billing analytics
CREATE TABLE time_entries PARTITION BY RANGE (entry_date);

CREATE TABLE time_entries_2024_01 PARTITION OF time_entries
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition documents by matter for case file organization
CREATE TABLE documents PARTITION BY LIST (matter_id);

-- Partition audit logs by date for compliance retention
CREATE TABLE document_access_log PARTITION BY RANGE (accessed_at);

CREATE TABLE document_access_log_2024 PARTITION OF document_access_log
    FOR VALUES FROM ('2024-01-01 00:00:00') TO ('2025-01-01 00:00:00');
```

### Advanced Indexing
```sql
-- Firm and attorney indexes
CREATE INDEX idx_attorneys_firm_status ON attorneys (firm_id, work_status);
CREATE INDEX idx_attorneys_practice_areas ON attorneys USING gin (practice_areas);
CREATE INDEX idx_clients_firm_tier ON clients (firm_id, client_tier, client_status);

-- Matter and case management indexes
CREATE INDEX idx_matters_firm_status ON matters (firm_id, matter_status);
CREATE INDEX idx_matters_client ON matters (client_id);
CREATE INDEX idx_matters_lead_attorney ON matters (lead_attorney_id);
CREATE INDEX idx_matters_practice_area ON matters (practice_area, matter_type);

-- Time tracking and billing indexes
CREATE INDEX idx_time_entries_attorney_date ON time_entries (attorney_id, entry_date DESC);
CREATE INDEX idx_time_entries_matter_date ON time_entries (matter_id, entry_date DESC);
CREATE INDEX idx_invoices_client_status ON invoices (client_id, invoice_status, invoice_date DESC);
CREATE INDEX idx_invoice_items_invoice ON invoice_items (invoice_id);

-- Document management indexes
CREATE INDEX idx_documents_matter_type ON documents (matter_id, document_type, document_status);
CREATE INDEX idx_documents_author_date ON documents (author_id, created_date DESC);
CREATE INDEX idx_case_events_matter_date ON case_events (matter_id, scheduled_date);

-- Calendar and deadline indexes
CREATE INDEX idx_calendar_events_attendee_date ON calendar_events USING gin (attendees, start_date);
CREATE INDEX idx_deadlines_matter_date ON deadlines (matter_id, deadline_date);
CREATE INDEX idx_deadlines_assigned_status ON deadlines (assigned_to, deadline_status, deadline_date);

-- Financial indexes
CREATE INDEX idx_expenses_matter_status ON expenses (matter_id, approval_status, expense_date DESC);
CREATE INDEX idx_trust_transactions_account_date ON trust_transactions (account_id, transaction_date DESC);
```

### Materialized Views for Analytics
```sql
-- Firm performance dashboard
CREATE MATERIALIZED VIEW firm_performance_dashboard AS
SELECT
    lf.firm_id,
    lf.firm_name,

    -- Financial metrics (last 30 days)
    COALESCE(SUM(i.total_amount), 0) as total_revenue,
    COALESCE(AVG(i.total_amount), 0) as avg_invoice_amount,
    COUNT(CASE WHEN i.invoice_status = 'paid' THEN 1 END)::DECIMAL /
    COUNT(i.invoice_id) * 100 as collection_rate,

    -- Matter metrics
    COUNT(m.matter_id) as total_matters,
    COUNT(CASE WHEN m.matter_status IN ('won', 'settled') THEN 1 END)::DECIMAL /
    COUNT(m.matter_id) * 100 as success_rate,
    AVG(EXTRACT(EPOCH FROM (CURRENT_DATE - m.opened_date)) / 30) as avg_matter_age_months,

    -- Time and billing efficiency
    COALESCE(SUM(te.duration_minutes), 0) / 60.0 as total_billable_hours,
    CASE WHEN SUM(te.duration_minutes) > 0
         THEN (SUM(te.billed_amount) / (SUM(te.duration_minutes) / 60.0))::DECIMAL
         ELSE 0 END as avg_hourly_rate,
    COALESCE(SUM(te.duration_minutes) / COUNT(DISTINCT te.attorney_id) / 160, 0) as avg_utilization_hours,

    -- Client metrics
    COUNT(DISTINCT c.client_id) as total_clients,
    COUNT(DISTINCT CASE WHEN c.client_tier = 'platinum' THEN c.client_id END) as platinum_clients,
    AVG(c.client_satisfaction_rating) as avg_client_satisfaction,

    -- Operational efficiency
    COUNT(CASE WHEN dl.deadline_status = 'overdue' THEN 1 END) as overdue_deadlines,
    COUNT(CASE WHEN dl.deadline_status = 'completed' THEN 1 END)::DECIMAL /
    COUNT(dl.deadline_id) * 100 as deadline_completion_rate,

    -- Overall health score
    ROUND(
        (
            -- Financial health (25%)
            LEAST(COUNT(CASE WHEN i.invoice_status = 'paid' THEN 1 END)::DECIMAL / NULLIF(COUNT(i.invoice_id), 0) * 25, 25) +
            -- Client satisfaction (20%)
            COALESCE(AVG(c.client_satisfaction_rating), 0) / 5 * 20 +
            -- Operational efficiency (20%)
            (1 - COUNT(CASE WHEN dl.deadline_status = 'overdue' THEN 1 END)::DECIMAL / NULLIF(COUNT(dl.deadline_id), 0)) * 20 +
            -- Matter success (20%)
            COUNT(CASE WHEN m.matter_status IN ('won', 'settled') THEN 1 END)::DECIMAL / NULLIF(COUNT(m.matter_id), 0) * 20 +
            -- Attorney utilization (15%)
            LEAST(COALESCE(SUM(te.duration_minutes) / COUNT(DISTINCT te.attorney_id) / 1600, 0) * 15, 15)
        ), 1
    ) as overall_firm_health_score

FROM law_firms lf
LEFT JOIN attorneys a ON lf.firm_id = a.firm_id
LEFT JOIN matters m ON lf.firm_id = m.firm_id
LEFT JOIN clients c ON lf.firm_id = c.firm_id
LEFT JOIN time_entries te ON a.attorney_id = te.attorney_id
    AND te.entry_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN invoices i ON lf.firm_id = i.firm_id
    AND i.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN deadlines dl ON lf.firm_id = dl.matter_id
    AND dl.created_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY lf.firm_id, lf.firm_name;

-- Refresh every 6 hours
CREATE UNIQUE INDEX idx_firm_performance_dashboard ON firm_performance_dashboard (firm_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY firm_performance_dashboard;
```

## Security Considerations

### Attorney-Client Privilege Protection
```sql
-- Comprehensive privilege log management for attorney work product
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE communications ENABLE ROW LEVEL SECURITY;

CREATE POLICY document_privilege_policy ON documents
    FOR SELECT USING (
        confidentiality_level = 'public' OR
        author_id = current_setting('app.user_id')::UUID OR
        current_setting('app.user_role')::TEXT = 'partner' OR
        EXISTS (
            SELECT 1 FROM matters m
            WHERE m.matter_id = documents.matter_id
              AND (m.lead_attorney_id = current_setting('app.user_id')::UUID OR
                   current_setting('app.user_id')::UUID = ANY(m.assigned_attorneys))
        )
    );

CREATE POLICY communication_privilege_policy ON communications
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM matter_participants mp
            WHERE mp.matter_id = communications.matter_id
              AND mp.participant_id = current_setting('app.user_id')::UUID
        ) OR
        communication_type = 'public_court_filing'
    );
```

### Audit Trail and Compliance
```sql
-- Comprehensive legal audit logging for compliance and ethics
CREATE TABLE legal_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    firm_id UUID,
    matter_id UUID,
    client_id UUID,
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    change_reason TEXT,
    ethical_concern BOOLEAN DEFAULT FALSE,
    privilege_impact VARCHAR CHECK (privilege_impact IN ('none', 'potential', 'breach')),
    audit_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (audit_timestamp);

-- Audit trigger for legal operations
CREATE OR REPLACE FUNCTION legal_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO legal_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, firm_id, matter_id, client_id, session_id,
        ip_address, user_agent, ethical_concern, privilege_impact
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME IN ('matters', 'clients') THEN COALESCE(NEW.firm_id, OLD.firm_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME IN ('documents', 'time_entries') THEN COALESCE(NEW.matter_id, OLD.matter_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME IN ('matters', 'invoices') THEN COALESCE(NEW.client_id, OLD.client_id) ELSE NULL END,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE WHEN TG_TABLE_NAME = 'documents' AND (NEW.confidentiality_level = 'privileged' OR OLD.confidentiality_level = 'privileged') THEN TRUE ELSE FALSE END,
        CASE
            WHEN TG_TABLE_NAME = 'documents' AND NEW.confidentiality_level = 'privileged' THEN 'potential'
            WHEN TG_TABLE_NAME = 'communications' THEN 'potential'
            ELSE 'none'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### Automated Bar Association Reporting
```sql
-- Automated compliance reporting for bar association requirements
CREATE OR REPLACE FUNCTION generate_bar_association_report(
    attorney_uuid UUID,
    report_type VARCHAR, -- 'mcled', 'trust_account', 'client_protection'
    report_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
)
RETURNS TABLE (
    report_data JSONB,
    compliance_status VARCHAR,
    certification_eligible BOOLEAN,
    required_actions JSONB,
    next_due_date DATE
) AS $$
DECLARE
    report_data_val JSONB := '{}';
    compliance_val VARCHAR := 'compliant';
    eligible_val BOOLEAN := TRUE;
    actions_val JSONB := '[]';
    next_due_val DATE;
BEGIN
    CASE report_type
        WHEN 'mcled' THEN
            -- Minimum Continuing Legal Education compliance
            SELECT jsonb_build_object(
                'attorney_info', jsonb_build_object(
                    'id', a.attorney_id,
                    'name', a.first_name || ' ' || a.last_name,
                    'bar_number', a.bar_number,
                    'state', a.bar_state
                ),
                'reporting_period', jsonb_build_object('year', report_year),
                'education_hours', jsonb_build_object(
                    'required_hours', 12,
                    'completed_hours', COALESCE(SUM(c.course_hours), 0),
                    'ethics_hours', COALESCE(SUM(CASE WHEN c.course_type = 'ethics' THEN c.course_hours END), 0),
                    'courses_completed', jsonb_agg(jsonb_build_object(
                        'course_name', c.course_name,
                        'provider', c.course_provider,
                        'hours', c.course_hours,
                        'completion_date', c.completion_date
                    ))
                ),
                'compliance_status', CASE
                    WHEN COALESCE(SUM(c.course_hours), 0) >= 12 THEN 'compliant'
                    ELSE 'non_compliant'
                END
            ) INTO report_data_val
            FROM attorneys a
            LEFT JOIN mcled_courses c ON a.attorney_id = c.attorney_id
                AND EXTRACT(YEAR FROM c.completion_date) = report_year
            WHERE a.attorney_id = attorney_uuid
            GROUP BY a.attorney_id, a.first_name, a.last_name, a.bar_number, a.bar_state;

            next_due_val := DATE(report_year + 1 || '-12-31');

        WHEN 'trust_account' THEN
            -- Trust account compliance
            SELECT jsonb_build_object(
                'account_info', jsonb_build_object(
                    'attorney_id', a.attorney_id,
                    'accounts_count', COUNT(ta.account_id),
                    'total_balance', SUM(ta.current_balance)
                ),
                'compliance_checks', jsonb_build_object(
                    'interest_bearing_compliant', COUNT(CASE WHEN ta.interest_bearing = TRUE THEN 1 END),
                    'reconciled_monthly', COUNT(CASE WHEN ta.last_audit_date >= CURRENT_DATE - INTERVAL '35 days' THEN 1 END),
                    'minimum_balance_maintained', COUNT(CASE WHEN ta.current_balance >= ta.minimum_balance THEN 1 END)
                ),
                'audit_trail', jsonb_build_object(
                    'last_audit', MAX(ta.last_audit_date),
                    'audit_frequency', 'monthly',
                    'exceptions_noted', COUNT(CASE WHEN ta.compliance_status = 'non_compliant' THEN 1 END)
                )
            ) INTO report_data_val
            FROM attorneys a
            LEFT JOIN trust_accounts ta ON a.attorney_id = ta.client_id
            WHERE a.attorney_id = attorney_uuid
            GROUP BY a.attorney_id;

            next_due_val := CURRENT_DATE + INTERVAL '1 month';

        WHEN 'client_protection' THEN
            -- Client protection fund compliance
            SELECT jsonb_build_object(
                'attorney_info', jsonb_build_object(
                    'id', a.attorney_id,
                    'name', a.first_name || ' ' || a.last_name,
                    'bar_number', a.bar_number
                ),
                'client_protection', jsonb_build_object(
                    'fund_participation', a.client_protection_fund,
                    'claims_history', COALESCE(jsonb_agg(
                        jsonb_build_object(
                            'claim_date', cpf.claim_date,
                            'amount', cpf.claim_amount,
                            'resolution', cpf.resolution_status
                        )
                    ) FILTER (WHERE cpf.claim_date IS NOT NULL), '[]'::jsonb),
                    'insurance_coverage', a.malpractice_insurance
                ),
                'ethical_compliance', jsonb_build_object(
                    'bar_complaints', COALESCE(COUNT(ec.complaint_id), 0),
                    'disciplinary_actions', COALESCE(COUNT(CASE WHEN ec.disciplinary_action IS NOT NULL THEN 1 END), 0)
                )
            ) INTO report_data_val
            FROM attorneys a
            LEFT JOIN client_protection_fund cpf ON a.attorney_id = cpf.attorney_id
            LEFT JOIN ethical_complaints ec ON a.attorney_id = ec.attorney_id
            WHERE a.attorney_id = attorney_uuid
            GROUP BY a.attorney_id, a.first_name, a.last_name, a.bar_number, a.client_protection_fund, a.malpractice_insurance;

    END CASE;

    -- Determine compliance status and required actions
    IF report_data_val->>'compliance_status' = 'non_compliant' THEN
        compliance_val := 'non_compliant';
        eligible_val := FALSE;
        actions_val := jsonb_build_array(
            'Complete required training/courses',
            'Submit updated compliance documentation',
            'Contact bar association for guidance'
        );
    END IF;

    RETURN QUERY SELECT
        report_data_val,
        compliance_val,
        eligible_val,
        actions_val,
        next_due_val;
END;
$$ LANGUAGE plpgsql;
```

### Matter Management and Workflow Automation
```sql
-- Automated matter lifecycle management with workflow triggers
CREATE OR REPLACE FUNCTION process_matter_workflow_events()
RETURNS TRIGGER AS $$
DECLARE
    matter_record matters%ROWTYPE;
    workflow_actions JSONB := '[]';
BEGIN
    -- Get updated matter record
    SELECT * INTO matter_record FROM matters WHERE matter_id = NEW.matter_id;

    -- Trigger actions based on status changes
    CASE NEW.matter_status
        WHEN 'opened' THEN
            -- Create initial workflow items
            workflow_actions := workflow_actions || jsonb_build_array(
                jsonb_build_object('action', 'create_conflict_check', 'priority', 'high'),
                jsonb_build_object('action', 'schedule_initial_client_meeting', 'priority', 'high'),
                jsonb_build_object('action', 'create_matter_deadlines', 'priority', 'medium')
            );

        WHEN 'discovery' THEN
            workflow_actions := workflow_actions || jsonb_build_array(
                jsonb_build_object('action', 'create_discovery_plan', 'priority', 'high'),
                jsonb_build_object('action', 'schedule_depositions', 'priority', 'medium'),
                jsonb_build_object('action', 'prepare_interrogatories', 'priority', 'medium')
            );

        WHEN 'pre_trial' THEN
            workflow_actions := workflow_actions || jsonb_build_array(
                jsonb_build_object('action', 'file_motion_summary_judgment', 'priority', 'high'),
                jsonb_build_object('action', 'prepare_witness_list', 'priority', 'high'),
                jsonb_build_object('action', 'schedule_trial_preparation', 'priority', 'medium')
            );

        WHEN 'settled' THEN
            workflow_actions := workflow_actions || jsonb_build_array(
                jsonb_build_object('action', 'prepare_settlement_agreement', 'priority', 'high'),
                jsonb_build_object('action', 'schedule_settlement_conference', 'priority', 'high'),
                jsonb_build_object('action', 'close_matter_financially', 'priority', 'medium')
            );

        WHEN 'closed' THEN
            workflow_actions := workflow_actions || jsonb_build_array(
                jsonb_build_object('action', 'archive_case_files', 'priority', 'medium'),
                jsonb_build_object('action', 'send_client_satisfaction_survey', 'priority', 'low'),
                jsonb_build_object('action', 'update_matter_analytics', 'priority', 'low')
            );
    END CASE;

    -- Execute workflow actions
    IF jsonb_array_length(workflow_actions) > 0 THEN
        INSERT INTO workflow_queue (
            matter_id, workflow_actions, triggered_by, created_at
        ) VALUES (
            NEW.matter_id, workflow_actions, current_setting('app.user_id', TRUE)::UUID, CURRENT_TIMESTAMP
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for matter workflow automation
CREATE TRIGGER matter_workflow_trigger
    AFTER UPDATE OF matter_status ON matters
    FOR EACH ROW
    WHEN (OLD.matter_status IS DISTINCT FROM NEW.matter_status)
    EXECUTE FUNCTION process_matter_workflow_events();
```

## Integration Points

### External Systems
- **Court filing systems** (ECF, PACER) for electronic filing
- **Legal research databases** (Westlaw, LexisNexis) for case law research
- **Bar association systems** for CLE tracking and compliance
- **Document management systems** (NetDocuments, iManage) for secure storage

### API Endpoints
- **Matter management APIs** for case lifecycle operations
- **Time tracking APIs** for automated billing integration
- **Document APIs** for secure file access and e-discovery
- **Calendar APIs** for court date and deadline synchronization

## Monitoring & Analytics

### Key Performance Indicators
- **Financial metrics** (realization rates, collection rates, profitability)
- **Matter outcomes** (win rates, settlement rates, case duration)
- **Client satisfaction** (NPS scores, retention rates, referral rates)
- **Operational efficiency** (time to resolution, deadline compliance)

### Real-Time Dashboards
```sql
-- Legal operations command center dashboard
CREATE VIEW legal_operations_dashboard AS
SELECT
    lf.firm_id,
    lf.firm_name,

    -- Matter pipeline and status
    COUNT(m.matter_id) as total_active_matters,
    COUNT(CASE WHEN m.matter_status = 'opened' THEN 1 END) as new_matters_this_month,
    COUNT(CASE WHEN m.matter_status IN ('won', 'settled') THEN 1 END) as successful_matters_this_month,
    ROUND(
        COUNT(CASE WHEN m.matter_status IN ('won', 'settled') THEN 1 END)::DECIMAL /
        COUNT(m.matter_id) * 100, 1
    ) as current_success_rate,

    -- Financial performance (last 30 days)
    COALESCE(SUM(i.total_amount), 0) as monthly_revenue,
    COALESCE(SUM(i.total_amount - i.outstanding_balance), 0) as monthly_collections,
    ROUND(
        SUM(i.total_amount - i.outstanding_balance)::DECIMAL /
        NULLIF(SUM(i.total_amount), 0) * 100, 1
    ) as collection_rate,

    -- Time and billing efficiency
    COALESCE(SUM(te.duration_minutes), 0) / 60.0 as total_billable_hours,
    ROUND(
        SUM(te.billed_amount)::DECIMAL / NULLIF(SUM(te.duration_minutes) / 60.0, 0), 2
    ) as average_hourly_rate,

    -- Client metrics
    COUNT(DISTINCT c.client_id) as active_clients,
    COUNT(DISTINCT CASE WHEN c.client_since >= CURRENT_DATE - INTERVAL '3 months' THEN c.client_id END) as new_clients_quarter,
    AVG(c.client_satisfaction_rating) as avg_client_satisfaction,

    -- Operational alerts
    COUNT(CASE WHEN dl.deadline_date < CURRENT_DATE AND dl.deadline_status != 'completed' THEN 1 END) as overdue_deadlines,
    COUNT(CASE WHEN i.due_date < CURRENT_DATE AND i.invoice_status != 'paid' THEN 1 END) as overdue_invoices,
    COUNT(CASE WHEN o.outage_start IS NOT NULL AND o.outage_status = 'active' THEN 1 END) as active_system_outages,

    -- Attorney workload and utilization
    COUNT(DISTINCT a.attorney_id) as active_attorneys,
    ROUND(
        SUM(te.duration_minutes)::DECIMAL / COUNT(DISTINCT a.attorney_id) / 1600 * 100, 1
    ) as avg_attorney_utilization,

    -- Risk indicators
    COUNT(CASE WHEN m.conflict_check_status = 'conflict_found' THEN 1 END) as matters_with_conflicts,
    COUNT(CASE WHEN ta.compliance_status = 'non_compliant' THEN 1 END) as non_compliant_trust_accounts,

    -- Overall firm health score
    ROUND(
        (
            -- Financial health (20%)
            ROUND(
                SUM(i.total_amount - i.outstanding_balance)::DECIMAL /
                NULLIF(SUM(i.total_amount), 0) * 20, 1
            ) +
            -- Client satisfaction (20%)
            COALESCE(AVG(c.client_satisfaction_rating), 0) / 5 * 20 +
            -- Operational efficiency (20%)
            (1 - COUNT(CASE WHEN dl.deadline_date < CURRENT_DATE AND dl.deadline_status != 'completed' THEN 1 END)::DECIMAL /
             NULLIF(COUNT(dl.deadline_id), 0)) * 20 +
            -- Attorney utilization (15%)
            LEAST(SUM(te.duration_minutes)::DECIMAL / COUNT(DISTINCT a.attorney_id) / 1600 * 15, 15) +
            -- Compliance (15%)
            (1 - COUNT(CASE WHEN ta.compliance_status = 'non_compliant' THEN 1 END)::DECIMAL /
             NULLIF(COUNT(ta.account_id), 0)) * 15 +
            -- Matter success (10%)
            COUNT(CASE WHEN m.matter_status IN ('won', 'settled') THEN 1 END)::DECIMAL /
            NULLIF(COUNT(m.matter_id), 0) * 10
        ), 1
    ) as overall_firm_health_score

FROM law_firms lf
LEFT JOIN attorneys a ON lf.firm_id = a.firm_id AND a.work_status = 'active'
LEFT JOIN matters m ON lf.firm_id = m.firm_id
LEFT JOIN clients c ON lf.firm_id = c.firm_id AND c.client_status = 'active'
LEFT JOIN time_entries te ON a.attorney_id = te.attorney_id
    AND te.entry_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN invoices i ON lf.firm_id = i.firm_id
    AND i.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN deadlines dl ON lf.firm_id = dl.matter_id
    AND dl.created_at >= CURRENT_DATE - INTERVAL '90 days'
LEFT JOIN trust_accounts ta ON lf.firm_id = ta.firm_id
LEFT JOIN system_outages o ON o.outage_start IS NOT NULL
    AND o.outage_end IS NULL
GROUP BY lf.firm_id, lf.firm_name;
```

This legal services database schema provides enterprise-grade infrastructure for law firm operations, case management, regulatory compliance, and client service delivery with comprehensive audit trails and ethical safeguards.
