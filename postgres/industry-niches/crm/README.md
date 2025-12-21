# Customer Relationship Management (CRM) Database Design

## Overview

This comprehensive database schema supports CRM systems, customer service platforms, sales automation, marketing campaign management, and customer analytics. The design handles complex customer lifecycles, multi-channel interactions, sales pipelines, and support operations.

## Key Features

### 👥 Customer Lifecycle Management
- **360-degree customer profiles** with comprehensive contact and preference data
- **Lead scoring and qualification** with automated nurturing workflows
- **Customer segmentation** with dynamic and behavioral criteria
- **Lifecycle stage tracking** from prospect to loyal customer

### 💼 Sales Force Automation
- **Opportunity and pipeline management** with stage-based workflows
- **Quote and proposal generation** with version control and approval flows
- **Activity tracking** with automated follow-ups and reminders
- **Performance analytics** for sales teams and individuals

### 🎧 Customer Service & Support
- **Multi-channel support ticketing** with SLA management and escalation
- **Knowledge base integration** with automated responses
- **Customer satisfaction tracking** with NPS and feedback analysis
- **Agent performance monitoring** and workload balancing

### 📧 Marketing Automation
- **Campaign management** with multi-channel execution and tracking
- **Email marketing** with templates, A/B testing, and personalization
- **Lead nurturing** with automated drip campaigns and scoring
- **Performance attribution** and ROI measurement

## Database Schema Highlights

### Core Tables

#### Organization & User Management
- **`organizations`** - Multi-tenant organization profiles with subscription management
- **`users`** - User accounts with role-based permissions and preferences

#### Customer Management
- **`customers`** - Comprehensive customer profiles with lifecycle tracking
- **`customer_segments`** - Dynamic customer segmentation with automated membership
- **`customer_segment_members`** - Many-to-many segment membership tracking

#### Sales Management
- **`opportunities`** - Sales opportunities with pipeline tracking and forecasting
- **`opportunity_activities`** - Activity logging and follow-up scheduling
- **`quotes`** - Quote management with versioning and approval workflows
- **`quote_items`** - Detailed quote line items with pricing

#### Support Management
- **`support_tickets`** - Multi-channel support ticketing with SLA tracking
- **`ticket_messages`** - Complete communication threads and internal notes

#### Marketing Management
- **`campaigns`** - Multi-channel marketing campaign management
- **`email_templates`** - Reusable email templates with merge field support
- **`email_sends`** - Email campaign execution and performance tracking

## Key Design Patterns

### 1. Customer 360-Degree View Aggregation
```sql
-- Comprehensive customer view with all interactions and activities
CREATE OR REPLACE FUNCTION get_customer_360_view(customer_uuid UUID)
RETURNS TABLE (
    customer_profile JSONB,
    recent_interactions JSONB,
    active_opportunities JSONB,
    open_tickets JSONB,
    lifetime_value_metrics JSONB,
    engagement_score DECIMAL,
    health_score DECIMAL
) AS $$
DECLARE
    profile_data JSONB;
    interactions_data JSONB;
    opportunities_data JSONB;
    tickets_data JSONB;
    ltv_data JSONB;
BEGIN
    -- Build customer profile
    SELECT jsonb_build_object(
        'customer_id', c.customer_id,
        'customer_number', c.customer_number,
        'name', c.first_name || ' ' || c.last_name,
        'company', c.company_name,
        'email', c.email,
        'lifecycle_stage', c.lifecycle_stage,
        'lead_score', c.lead_score,
        'assigned_to', u.first_name || ' ' || u.last_name,
        'tags', c.tags,
        'segments', (
            SELECT jsonb_agg(cs.segment_name)
            FROM customer_segment_members csm
            JOIN customer_segments cs ON csm.segment_id = cs.segment_id
            WHERE csm.customer_id = c.customer_id
        )
    ) INTO profile_data
    FROM customers c
    LEFT JOIN users u ON c.assigned_to = u.user_id
    WHERE c.customer_id = customer_uuid;

    -- Recent interactions (last 90 days)
    SELECT jsonb_agg(
        jsonb_build_object(
            'date', il.interaction_date,
            'type', il.interaction_type,
            'channel', il.interaction_channel,
            'outcome', il.outcome,
            'sentiment', il.sentiment
        )
    ) INTO interactions_data
    FROM interaction_logs il
    WHERE il.customer_id = customer_uuid
      AND il.interaction_date >= CURRENT_DATE - INTERVAL '90 days'
    ORDER BY il.interaction_date DESC
    LIMIT 10;

    -- Active opportunities
    SELECT jsonb_agg(
        jsonb_build_object(
            'opportunity_id', o.opportunity_id,
            'name', o.opportunity_name,
            'stage', o.sales_stage,
            'value', o.estimated_value,
            'probability', o.probability_percentage,
            'close_date', o.expected_close_date
        )
    ) INTO opportunities_data
    FROM opportunities o
    WHERE o.customer_id = customer_uuid
      AND o.opportunity_status = 'open';

    -- Open support tickets
    SELECT jsonb_agg(
        jsonb_build_object(
            'ticket_id', st.ticket_id,
            'subject', st.ticket_subject,
            'status', st.ticket_status,
            'priority', st.ticket_priority,
            'created', st.created_at,
            'last_update', st.updated_at
        )
    ) INTO tickets_data
    FROM support_tickets st
    WHERE st.customer_id = customer_uuid
      AND st.ticket_status IN ('open', 'in_progress');

    -- Lifetime value metrics
    SELECT jsonb_build_object(
        'total_revenue', COALESCE(SUM(o.total_amount), 0),
        'total_orders', COUNT(o.order_id),
        'average_order_value', AVG(o.total_amount),
        'customer_since', MIN(o.order_date),
        'last_order', MAX(o.order_date)
    ) INTO ltv_data
    FROM orders o  -- Assuming orders table exists
    WHERE o.customer_id = customer_uuid;

    RETURN QUERY SELECT
        profile_data,
        interactions_data,
        opportunities_data,
        tickets_data,
        ltv_data,
        calculate_engagement_score(customer_uuid),
        calculate_customer_health_score(customer_uuid);
END;
$$ LANGUAGE plpgsql;
```

### 2. Dynamic Lead Scoring Engine
```sql
-- Intelligent lead scoring based on multiple factors
CREATE OR REPLACE FUNCTION calculate_dynamic_lead_score(customer_uuid UUID)
RETURNS TABLE (
    total_score INTEGER,
    score_breakdown JSONB,
    scoring_factors JSONB,
    recommended_actions JSONB,
    score_trend VARCHAR
) AS $$
DECLARE
    demographic_score INTEGER := 0;
    behavioral_score INTEGER := 0;
    engagement_score INTEGER := 0;
    firmographic_score INTEGER := 0;
    total_score INTEGER := 0;
    breakdown JSONB := '{}';
    factors JSONB := '{}';
    actions JSONB := '[]';
BEGIN
    -- Demographic scoring
    SELECT CASE
        WHEN c.date_of_birth IS NOT NULL
             AND EXTRACT(YEAR FROM AGE(c.date_of_birth)) BETWEEN 25 AND 55 THEN 20
        WHEN c.education_level IN ('bachelors', 'masters', 'phd') THEN 15
        WHEN c.job_title ILIKE '%director%' OR c.job_title ILIKE '%vp%' OR c.job_title ILIKE '%c_suite%' THEN 15
        ELSE 5
    END INTO demographic_score
    FROM customers c WHERE c.customer_id = customer_uuid;

    -- Behavioral scoring
    SELECT
        CASE WHEN COUNT(*) > 10 THEN 25
             WHEN COUNT(*) > 5 THEN 15
             WHEN COUNT(*) > 2 THEN 10
             ELSE 5 END +
        CASE WHEN MAX(interaction_date) >= CURRENT_DATE - INTERVAL '7 days' THEN 15
             WHEN MAX(interaction_date) >= CURRENT_DATE - INTERVAL '30 days' THEN 10
             ELSE 0 END
    INTO behavioral_score
    FROM interaction_logs WHERE customer_id = customer_uuid;

    -- Engagement scoring
    SELECT
        CASE WHEN COUNT(CASE WHEN interaction_type = 'email_opened' THEN 1 END) > 5 THEN 15 ELSE 0 END +
        CASE WHEN COUNT(CASE WHEN interaction_type = 'website_visit' THEN 1 END) > 3 THEN 10 ELSE 0 END +
        CASE WHEN COUNT(CASE WHEN interaction_type = 'form_submission' THEN 1 END) > 0 THEN 10 ELSE 0 END
    INTO engagement_score
    FROM interaction_logs
    WHERE customer_id = customer_uuid
      AND interaction_date >= CURRENT_DATE - INTERVAL '30 days';

    -- Firmographic scoring
    SELECT CASE
        WHEN c.annual_revenue > 10000000 THEN 20
        WHEN c.annual_revenue > 1000000 THEN 15
        WHEN c.annual_revenue > 100000 THEN 10
        WHEN c.customer_type = 'business' THEN 5
        ELSE 0
    END INTO firmographic_score
    FROM customers c WHERE c.customer_id = customer_uuid;

    -- Calculate total score
    total_score := LEAST(demographic_score + behavioral_score + engagement_score + firmographic_score, 100);

    -- Build breakdown
    breakdown := jsonb_build_object(
        'demographic_score', demographic_score,
        'behavioral_score', behavioral_score,
        'engagement_score', engagement_score,
        'firmographic_score', firmographic_score,
        'total_score', total_score
    );

    -- Build factors
    factors := jsonb_build_object(
        'interaction_count', (SELECT COUNT(*) FROM interaction_logs WHERE customer_id = customer_uuid),
        'recent_interactions', (SELECT COUNT(*) FROM interaction_logs WHERE customer_id = customer_uuid AND interaction_date >= CURRENT_DATE - INTERVAL '7 days'),
        'campaign_responses', (SELECT COUNT(*) FROM interaction_logs WHERE customer_id = customer_uuid AND interaction_type IN ('email_opened', 'email_clicked')),
        'opportunity_count', (SELECT COUNT(*) FROM opportunities WHERE customer_id = customer_uuid)
    );

    -- Recommended actions based on score
    IF total_score >= 80 THEN
        actions := actions || jsonb_build_object('action', 'immediate_sales_contact', 'priority', 'high', 'reason', 'High-quality lead ready for conversion');
    ELSIF total_score >= 60 THEN
        actions := actions || jsonb_build_object('action', 'nurture_campaign', 'priority', 'medium', 'reason', 'Qualified lead requiring nurturing');
    ELSIF total_score >= 30 THEN
        actions := actions || jsonb_build_object('action', 'education_content', 'priority', 'low', 'reason', 'Early stage lead needs education');
    END IF;

    RETURN QUERY SELECT
        total_score,
        breakdown,
        factors,
        actions,
        CASE
            WHEN total_score >= 70 THEN 'increasing'
            WHEN total_score >= 40 THEN 'stable'
            ELSE 'declining'
        END;
END;
$$ LANGUAGE plpgsql;
```

### 3. Sales Pipeline Forecasting
```sql
-- Advanced sales forecasting with weighted pipeline analysis
CREATE OR REPLACE FUNCTION forecast_sales_revenue(
    organization_uuid UUID,
    forecast_period_months INTEGER DEFAULT 6,
    confidence_level DECIMAL DEFAULT 0.8
)
RETURNS TABLE (
    forecast_period DATE,
    best_case_revenue DECIMAL,
    expected_revenue DECIMAL,
    worst_case_revenue DECIMAL,
    pipeline_coverage_ratio DECIMAL,
    risk_factors JSONB,
    recommended_actions JSONB
) AS $$
DECLARE
    forecast_start DATE := DATE_TRUNC('month', CURRENT_DATE);
    period_date DATE;
    pipeline_value DECIMAL;
    conversion_rates JSONB;
    risk_factors JSONB := '[]';
    actions JSONB := '[]';
BEGIN
    -- Get historical conversion rates by stage
    SELECT jsonb_object_agg(
        sales_stage,
        ROUND(AVG(CASE WHEN opportunity_status = 'won' THEN 1.0 ELSE 0.0 END), 2)
    ) INTO conversion_rates
    FROM opportunities
    WHERE organization_id = organization_uuid
      AND created_at >= CURRENT_DATE - INTERVAL '12 months';

    FOR i IN 0..forecast_period_months-1 LOOP
        period_date := forecast_start + INTERVAL '1 month' * i;

        -- Calculate pipeline value for this period
        SELECT SUM(o.estimated_value * (o.probability_percentage / 100.0))
        INTO pipeline_value
        FROM opportunities o
        WHERE o.organization_id = organization_uuid
          AND o.opportunity_status = 'open'
          AND o.expected_close_date >= period_date
          AND o.expected_close_date < period_date + INTERVAL '1 month';

        -- Apply risk adjustments based on pipeline health
        IF pipeline_value < 100000 THEN
            risk_factors := risk_factors || jsonb_build_object(
                'period', period_date,
                'risk_type', 'low_pipeline_coverage',
                'severity', 'high',
                'description', 'Pipeline coverage below target threshold'
            );
            actions := actions || jsonb_build_object(
                'action', 'increase_lead_generation',
                'priority', 'high',
                'target_date', period_date - INTERVAL '30 days'
            );
        END IF;

        -- Calculate forecast ranges
        RETURN QUERY SELECT
            period_date,
            pipeline_value * 1.2 as best_case, -- 20% upside
            pipeline_value as expected_case,
            pipeline_value * 0.8 as worst_case, -- 20% downside
            CASE WHEN (SELECT SUM(estimated_value) FROM opportunities WHERE organization_id = organization_uuid AND opportunity_status = 'open') > 0
                 THEN pipeline_value / (SELECT SUM(estimated_value) FROM opportunities WHERE organization_id = organization_uuid AND opportunity_status = 'open')
                 ELSE 0 END as coverage_ratio,
            risk_factors,
            actions;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 4. Automated Ticket Routing and SLA Management
```sql
-- Intelligent ticket routing with SLA monitoring
CREATE OR REPLACE FUNCTION route_support_ticket(ticket_uuid UUID)
RETURNS TABLE (
    assigned_agent UUID,
    estimated_resolution_time INTERVAL,
    priority_level VARCHAR,
    routing_reason TEXT,
    sla_deadline TIMESTAMP WITH TIME ZONE,
    escalation_triggers JSONB
) AS $$
DECLARE
    ticket_record support_tickets%ROWTYPE;
    assigned_agent_uuid UUID;
    priority VARCHAR;
    resolution_time INTERVAL;
    routing_reason TEXT;
    sla_deadline_ts TIMESTAMP WITH TIME ZONE;
    escalation_triggers JSONB := '{}';
BEGIN
    -- Get ticket details
    SELECT * INTO ticket_record FROM support_tickets WHERE ticket_id = ticket_uuid;

    -- Determine priority based on customer and issue type
    CASE
        WHEN ticket_record.customer_id IN (SELECT customer_id FROM customers WHERE vip_status = TRUE) THEN
            priority := 'urgent';
            resolution_time := INTERVAL '2 hours';
            routing_reason := 'VIP customer priority routing';
        WHEN ticket_record.ticket_type IN ('billing_issue', 'account_issue') THEN
            priority := 'high';
            resolution_time := INTERVAL '4 hours';
            routing_reason := 'Business-critical issue type';
        WHEN ticket_record.ticket_priority = 'urgent' THEN
            priority := 'urgent';
            resolution_time := INTERVAL '1 hour';
            routing_reason := 'Customer-specified urgent priority';
        WHEN ticket_record.ticket_type = 'bug_report' THEN
            priority := GREATEST(ticket_record.ticket_priority::INTEGER, 3)::VARCHAR;
            resolution_time := INTERVAL '24 hours';
            routing_reason := 'Technical issue routing';
        ELSE
            priority := ticket_record.ticket_priority;
            resolution_time := INTERVAL '48 hours';
            routing_reason := 'Standard routing based on priority';
    END CASE;

    -- Find best available agent
    SELECT u.user_id INTO assigned_agent_uuid
    FROM users u
    LEFT JOIN (
        SELECT assigned_to, COUNT(*) as current_load
        FROM support_tickets
        WHERE ticket_status IN ('open', 'in_progress')
          AND assigned_to IS NOT NULL
        GROUP BY assigned_to
    ) agent_load ON u.user_id = agent_load.assigned_to
    WHERE u.user_role IN ('support_agent', 'admin')
      AND u.user_status = 'active'
      AND (u.department = ticket_record.category OR u.department IS NULL)
      AND COALESCE(agent_load.current_load, 0) < 10 -- Max 10 tickets per agent
    ORDER BY
        -- Prioritize by specialization match
        CASE WHEN u.department = ticket_record.category THEN 1 ELSE 2 END,
        -- Then by current workload
        COALESCE(agent_load.current_load, 0),
        -- Finally by performance rating
        u.user_id -- Could add performance metrics here
    LIMIT 1;

    -- Calculate SLA deadline
    sla_deadline_ts := CURRENT_TIMESTAMP + resolution_time;

    -- Set escalation triggers
    escalation_triggers := jsonb_build_object(
        'first_escalation', jsonb_build_object(
            'trigger_time', CURRENT_TIMESTAMP + (resolution_time * 0.5),
            'escalation_level', 'supervisor_notification',
            'action', 'Notify supervisor of approaching SLA breach'
        ),
        'final_escalation', jsonb_build_object(
            'trigger_time', sla_deadline_ts,
            'escalation_level', 'management_escalation',
            'action', 'Escalate to management for SLA breach'
        )
    );

    -- Assign the ticket
    UPDATE support_tickets SET
        assigned_to = assigned_agent_uuid,
        assigned_at = CURRENT_TIMESTAMP,
        ticket_status = 'in_progress'
    WHERE ticket_id = ticket_uuid;

    RETURN QUERY SELECT
        assigned_agent_uuid,
        resolution_time,
        priority,
        routing_reason,
        sla_deadline_ts,
        escalation_triggers;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition interaction logs by month for analytics performance
CREATE TABLE interaction_logs PARTITION BY RANGE (interaction_date);

CREATE TABLE interaction_logs_2024_01 PARTITION OF interaction_logs
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition support tickets by status and date
CREATE TABLE support_tickets PARTITION BY RANGE (created_at);

CREATE TABLE support_tickets_2024_q1 PARTITION OF support_tickets
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

-- Partition email sends by campaign date
CREATE TABLE email_sends PARTITION BY RANGE (scheduled_send_time);

CREATE TABLE email_sends_2024 PARTITION OF email_sends
    FOR VALUES FROM ('2024-01-01 00:00:00') TO ('2025-01-01 00:00:00');
```

### Advanced Indexing
```sql
-- Customer and contact indexes
CREATE INDEX idx_customers_organization ON customers (organization_id, customer_status);
CREATE INDEX idx_customers_email ON customers (email);
CREATE INDEX idx_customers_lifecycle ON customers (lifecycle_stage, lead_score DESC);
CREATE INDEX idx_customers_assigned_to ON customers (assigned_to, last_contact_date DESC);

-- Sales indexes
CREATE INDEX idx_opportunities_organization ON opportunities (organization_id, sales_stage);
CREATE INDEX idx_opportunities_customer ON opportunities (customer_id);
CREATE INDEX idx_opportunities_close_date ON opportunities (expected_close_date) WHERE opportunity_status = 'open';

-- Support indexes
CREATE INDEX idx_support_tickets_organization ON support_tickets (organization_id, ticket_status);
CREATE INDEX idx_support_tickets_customer ON support_tickets (customer_id);
CREATE INDEX idx_support_tickets_assigned_to ON support_tickets (assigned_to, ticket_status);
CREATE INDEX idx_support_tickets_priority ON support_tickets (ticket_priority, created_at DESC);

-- Interaction indexes
CREATE INDEX idx_interaction_logs_customer ON interaction_logs (customer_id, interaction_date DESC);
CREATE INDEX idx_interaction_logs_type ON interaction_logs (interaction_type, interaction_channel);
CREATE INDEX idx_interaction_logs_campaign ON interaction_logs (campaign_id, interaction_date);

-- Campaign indexes
CREATE INDEX idx_campaigns_organization ON campaigns (organization_id, campaign_status);
CREATE INDEX idx_email_sends_campaign ON email_sends (campaign_id, send_status);
```

### Materialized Views for Analytics
```sql
-- Real-time sales dashboard
CREATE MATERIALIZED VIEW sales_dashboard AS
SELECT
    o.organization_id,

    -- Pipeline metrics
    COUNT(CASE WHEN op.sales_stage = 'prospecting' THEN 1 END) as prospects_count,
    COUNT(CASE WHEN op.sales_stage = 'qualification' THEN 1 END) as qualified_leads_count,
    COUNT(CASE WHEN op.sales_stage = 'proposal' THEN 1 END) as proposals_count,
    COUNT(CASE WHEN op.sales_stage = 'negotiation' THEN 1 END) as negotiations_count,

    -- Pipeline value
    SUM(CASE WHEN op.sales_stage = 'prospecting' THEN op.estimated_value END) as prospects_value,
    SUM(CASE WHEN op.sales_stage = 'qualification' THEN op.estimated_value END) as qualified_value,
    SUM(CASE WHEN op.sales_stage = 'proposal' THEN op.estimated_value END) as proposal_value,
    SUM(CASE WHEN op.sales_stage = 'negotiation' THEN op.estimated_value END) as negotiation_value,

    -- Conversion metrics (last 30 days)
    ROUND(
        COUNT(CASE WHEN op.opportunity_status = 'won' AND op.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END)::DECIMAL /
        NULLIF(COUNT(CASE WHEN op.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END), 0) * 100, 2
    ) as monthly_conversion_rate,

    -- Average deal metrics
    AVG(CASE WHEN op.opportunity_status = 'won' THEN op.estimated_value END) as avg_deal_size,
    AVG(CASE WHEN op.opportunity_status = 'won' THEN EXTRACT(EPOCH FROM (op.actual_close_date - op.created_at))/86400 END) as avg_sales_cycle_days,

    -- Forecast (next 3 months)
    SUM(CASE WHEN op.expected_close_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '3 months'
                THEN op.estimated_value * (op.probability_percentage / 100.0) END) as forecasted_revenue_3m

FROM organizations o
LEFT JOIN opportunities op ON o.organization_id = op.organization_id
    AND op.opportunity_status = 'open'
GROUP BY o.organization_id;

-- Refresh every 30 minutes
CREATE UNIQUE INDEX idx_sales_dashboard_org ON sales_dashboard (organization_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY sales_dashboard;
```

## Security Considerations

### Multi-Tenant Data Isolation
```sql
-- Row-level security for multi-tenant CRM
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE opportunities ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_isolation_policy ON customers
    FOR ALL USING (
        organization_id = current_setting('app.organization_id')::UUID OR
        current_setting('app.user_role')::TEXT = 'system_admin'
    );

CREATE POLICY opportunity_access_policy ON opportunities
    FOR ALL USING (
        organization_id = current_setting('app.organization_id')::UUID OR
        assigned_to = current_setting('app.user_id')::UUID OR
        created_by = current_setting('app.user_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('admin', 'sales_manager')
    );

CREATE POLICY support_data_policy ON support_tickets
    FOR SELECT USING (
        organization_id = current_setting('app.organization_id')::UUID OR
        assigned_to = current_setting('app.user_id')::UUID OR
        customer_id IN (
            SELECT customer_id FROM customers
            WHERE assigned_to = current_setting('app.user_id')::UUID
        ) OR
        current_setting('app.user_role')::TEXT IN ('admin', 'support_manager')
    );
```

### Data Encryption and Privacy
```sql
-- Encrypt sensitive customer data
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypt PII data
CREATE OR REPLACE FUNCTION encrypt_pii_data(pii_text TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(pii_text, current_setting('crm.encryption_key'));
END;
$$ LANGUAGE plpgsql;

-- Automated data anonymization for old records
CREATE OR REPLACE FUNCTION anonymize_old_customer_data()
RETURNS INTEGER AS $$
DECLARE
    anonymized_count INTEGER := 0;
BEGIN
    -- Anonymize customers with no activity in 7 years
    UPDATE customers SET
        first_name = 'Anonymized',
        last_name = 'User',
        email = CONCAT('anonymized_', customer_id, '@example.com'),
        phone = NULL,
        date_of_birth = NULL,
        address = NULL,
        anonymized_at = CURRENT_TIMESTAMP
    WHERE last_contact_date < CURRENT_DATE - INTERVAL '7 years'
      AND customer_status = 'inactive';

    GET DIAGNOSTICS anonymized_count = ROW_COUNT;
    RETURN anonymized_count;
END;
$$ LANGUAGE plpgsql;
```

### Audit Trail
```sql
-- Comprehensive CRM audit logging
CREATE TABLE crm_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    organization_id UUID,
    customer_id UUID,
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    change_reason TEXT,
    data_sensitivity VARCHAR(20) CHECK (data_sensitivity IN ('public', 'internal', 'confidential', 'restricted')),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Audit trigger for CRM operations
CREATE OR REPLACE FUNCTION crm_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO crm_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, organization_id, customer_id, session_id, ip_address, user_agent,
        data_sensitivity
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME IN ('customers', 'opportunities', 'support_tickets') THEN COALESCE(NEW.organization_id, OLD.organization_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME IN ('opportunities', 'support_tickets') THEN COALESCE(NEW.customer_id, OLD.customer_id) ELSE NULL END,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE
            WHEN TG_TABLE_NAME = 'customers' THEN 'confidential'
            WHEN TG_TABLE_NAME LIKE '%ticket%' THEN 'internal'
            WHEN TG_TABLE_NAME LIKE '%opportunity%' THEN 'confidential'
            ELSE 'internal'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### GDPR Data Subject Rights Automation
```sql
-- Automated GDPR compliance for data subject requests
CREATE OR REPLACE FUNCTION process_gdpr_request(
    customer_uuid UUID,
    request_type VARCHAR, -- 'access', 'rectify', 'erase', 'portability', 'restrict'
    request_details JSONB DEFAULT '{}'
)
RETURNS TABLE (
    request_id UUID,
    processing_status VARCHAR,
    completion_estimate INTERVAL,
    affected_records INTEGER,
    data_extract JSONB,
    compliance_notes TEXT
) AS $$
DECLARE
    request_uuid UUID;
    affected_count INTEGER := 0;
    extracted_data JSONB := '{}';
    processing_status VARCHAR := 'processing';
BEGIN
    -- Create GDPR request record
    INSERT INTO gdpr_requests (
        customer_id, request_type, request_details, status
    ) VALUES (
        customer_uuid, request_type, request_details, 'processing'
    ) RETURNING request_id INTO request_uuid;

    CASE request_type
        WHEN 'access' THEN
            -- Compile all customer data
            SELECT jsonb_build_object(
                'personal_data', to_jsonb(c.*),
                'opportunities', jsonb_agg(to_jsonb(o.*)),
                'support_tickets', jsonb_agg(to_jsonb(st.*)),
                'interactions', jsonb_agg(to_jsonb(il.*)),
                'campaign_history', jsonb_agg(to_jsonb(es.*))
            ) INTO extracted_data
            FROM customers c
            LEFT JOIN opportunities o ON c.customer_id = o.customer_id
            LEFT JOIN support_tickets st ON c.customer_id = st.customer_id
            LEFT JOIN interaction_logs il ON c.customer_id = il.customer_id
            LEFT JOIN email_sends es ON es.segment_id IN (
                SELECT segment_id FROM customer_segment_members
                WHERE customer_id = c.customer_id
            )
            WHERE c.customer_id = customer_uuid
            GROUP BY c.customer_id;

            affected_count := 1;

        WHEN 'erase' THEN
            -- Soft delete customer data
            UPDATE customers SET
                first_name = 'GDPR_ERASED',
                last_name = 'GDPR_ERASED',
                email = CONCAT('erased_', customer_uuid, '@gdpr.example.com'),
                phone = NULL,
                address = NULL,
                gdpr_erased = TRUE,
                erased_at = CURRENT_TIMESTAMP
            WHERE customer_id = customer_uuid;

            -- Anonymize related data
            UPDATE opportunities SET notes = 'Customer data erased per GDPR' WHERE customer_id = customer_uuid;
            UPDATE support_tickets SET customer_notes = 'Customer data erased per GDPR' WHERE customer_id = customer_uuid;

            affected_count := 1;

        WHEN 'rectify' THEN
            -- Update customer data based on request_details
            UPDATE customers SET
                first_name = COALESCE(request_details->>'first_name', first_name),
                last_name = COALESCE(request_details->>'last_name', last_name),
                email = COALESCE(request_details->>'email', email),
                updated_at = CURRENT_TIMESTAMP
            WHERE customer_id = customer_uuid;

            affected_count := 1;

        WHEN 'restrict' THEN
            -- Restrict processing
            UPDATE customers SET
                processing_restricted = TRUE,
                restriction_reason = request_details->>'reason',
                restricted_at = CURRENT_TIMESTAMP
            WHERE customer_id = customer_uuid;

            affected_count := 1;
    END CASE;

    -- Update request status
    UPDATE gdpr_requests SET
        status = 'completed',
        completed_at = CURRENT_TIMESTAMP,
        affected_records = affected_count
    WHERE request_id = request_uuid;

    RETURN QUERY SELECT
        request_uuid,
        processing_status,
        INTERVAL '24 hours', -- Standard completion time
        affected_count,
        extracted_data,
        'GDPR request processed in accordance with data protection regulations';
END;
$$ LANGUAGE plpgsql;
```

### CCPA Compliance for California Residents
```sql
-- CCPA compliance for California consumer privacy rights
CREATE OR REPLACE FUNCTION process_ccpa_request(
    customer_uuid UUID,
    request_type VARCHAR, -- 'access', 'delete', 'opt_out_sale', 'opt_out_sharing'
    verification_method VARCHAR DEFAULT 'email'
)
RETURNS TABLE (
    request_id UUID,
    verification_required BOOLEAN,
    verification_code VARCHAR,
    processing_status VARCHAR,
    estimated_completion INTERVAL,
    affected_data_categories TEXT[]
) AS $$
DECLARE
    request_uuid UUID;
    verification_code VARCHAR(10);
    customer_state VARCHAR;
    data_categories TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Check if customer is California resident
    SELECT (address->>'state') INTO customer_state
    FROM customers WHERE customer_id = customer_uuid;

    IF customer_state != 'CA' THEN
        RETURN QUERY SELECT
            NULL::UUID, FALSE, NULL::VARCHAR, 'not_applicable'::VARCHAR,
            NULL::INTERVAL, ARRAY[]::TEXT[];
        RETURN;
    END IF;

    -- Generate verification code
    verification_code := UPPER(SUBSTRING(MD5(random()::TEXT), 1, 10));

    -- Create CCPA request
    INSERT INTO ccpa_requests (
        customer_id, request_type, verification_code, verification_method, status
    ) VALUES (
        customer_uuid, request_type, verification_code, verification_method, 'verification_pending'
    ) RETURNING request_id INTO request_uuid;

    -- Determine affected data categories
    CASE request_type
        WHEN 'access' THEN
            data_categories := ARRAY['personal_information', 'commercial_information', 'internet_activity', 'geolocation_data'];
        WHEN 'delete' THEN
            data_categories := ARRAY['personal_information', 'commercial_information', 'internet_activity'];
        WHEN 'opt_out_sale' THEN
            data_categories := ARRAY['commercial_information'];
        WHEN 'opt_out_sharing' THEN
            data_categories := ARRAY['personal_information', 'commercial_information'];
    END CASE;

    RETURN QUERY SELECT
        request_uuid,
        TRUE,
        verification_code,
        'verification_pending'::VARCHAR,
        INTERVAL '45 days', -- CCPA completion deadline
        data_categories;
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Email service providers** (SendGrid, Mailchimp) for campaign delivery
- **Telephony systems** for call center integration
- **Social media platforms** for social CRM and monitoring
- **ERP systems** for order and financial data synchronization

### API Endpoints
- **Customer APIs** for profile management and data synchronization
- **Sales APIs** for opportunity and pipeline management
- **Support APIs** for ticketing and knowledge base integration
- **Marketing APIs** for campaign management and analytics

## Monitoring & Analytics

### Key Performance Indicators
- **Sales performance metrics** (conversion rates, deal sizes, cycle times)
- **Customer satisfaction scores** (NPS, CSAT, support resolution times)
- **Marketing effectiveness** (campaign ROI, lead quality, engagement rates)
- **Operational efficiency** (agent productivity, ticket resolution times)

### Real-Time Dashboards
```sql
-- CRM operations dashboard
CREATE VIEW crm_operations_dashboard AS
SELECT
    org.organization_id,
    org.organization_name,

    -- Customer metrics
    COUNT(DISTINCT c.customer_id) as total_customers,
    COUNT(DISTINCT CASE WHEN c.lifecycle_stage IN ('customer', 'champion') THEN c.customer_id END) as active_customers,
    COUNT(DISTINCT CASE WHEN c.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN c.customer_id END) as new_customers_30d,
    AVG(c.lead_score) as avg_lead_score,

    -- Sales metrics
    COUNT(DISTINCT o.opportunity_id) as total_opportunities,
    COUNT(DISTINCT CASE WHEN o.opportunity_status = 'won' THEN o.opportunity_id END) as won_opportunities,
    SUM(CASE WHEN o.opportunity_status = 'won' THEN o.estimated_value END) as total_revenue_won,
    AVG(CASE WHEN o.opportunity_status = 'won' THEN EXTRACT(EPOCH FROM (o.actual_close_date - o.created_at))/30 END) as avg_sales_cycle_months,

    -- Support metrics
    COUNT(DISTINCT st.ticket_id) as total_tickets,
    COUNT(DISTINCT CASE WHEN st.ticket_status IN ('open', 'in_progress') THEN st.ticket_id END) as open_tickets,
    AVG(EXTRACT(EPOCH FROM (st.updated_at - st.created_at))/3600) as avg_resolution_hours,
    AVG(st.customer_satisfaction_rating) as avg_customer_satisfaction,

    -- Campaign metrics
    COUNT(DISTINCT camp.campaign_id) as active_campaigns,
    SUM(camp.actual_cost) as total_campaign_cost,
    SUM(camp.actual_conversions) as total_conversions,
    ROUND(
        SUM(camp.actual_conversions)::DECIMAL /
        NULLIF(SUM(camp.actual_clicks), 0) * 100, 2
    ) as avg_conversion_rate,

    -- Overall health score
    ROUND(
        (
            -- Customer satisfaction (25%)
            COALESCE(AVG(st.customer_satisfaction_rating), 0) / 5 * 25 +
            -- Sales performance (30%)
            CASE WHEN COUNT(DISTINCT CASE WHEN o.opportunity_status = 'won' THEN o.opportunity_id END) > 0 THEN 30 ELSE 0 END +
            -- Support efficiency (20%)
            CASE WHEN AVG(EXTRACT(EPOCH FROM (st.updated_at - st.created_at))/3600) < 24 THEN 20 ELSE 10 END +
            -- Marketing effectiveness (25%)
            LEAST(COALESCE(ROUND(
                SUM(camp.actual_conversions)::DECIMAL /
                NULLIF(SUM(camp.actual_clicks), 0) * 100, 2
            ), 0) / 10 * 25, 25)
        ), 1
    ) as overall_health_score

FROM organizations org
LEFT JOIN customers c ON org.organization_id = org.organization_id
LEFT JOIN opportunities o ON org.organization_id = o.organization_id
LEFT JOIN support_tickets st ON org.organization_id = st.organization_id
LEFT JOIN campaigns camp ON org.organization_id = camp.organization_id
    AND camp.campaign_status = 'active'
GROUP BY org.organization_id, org.organization_name;
```

This CRM database schema provides enterprise-grade infrastructure for customer relationship management, sales automation, marketing operations, and customer support with comprehensive analytics and compliance features.
