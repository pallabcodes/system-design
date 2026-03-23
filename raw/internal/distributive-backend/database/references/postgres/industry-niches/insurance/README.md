# Insurance Management Database Design

## Overview

This comprehensive database schema supports insurance operations including policy management, underwriting, claims processing, agent management, and regulatory compliance. The design handles multiple insurance types (auto, home, life, health, commercial) with complex risk assessment and financial processing requirements.

## Key Features

### 🏢 Policyholder Management
- **Multi-entity support** (individuals, businesses, organizations)
- **Comprehensive risk profiling** and classification
- **KYC/AML compliance** and regulatory tracking
- **Flexible communication preferences** and marketing consent

### 📋 Policy Administration
- **Multi-line insurance products** with configurable coverage
- **Complex underwriting workflows** with risk assessment
- **Premium calculation and billing** with multiple payment options
- **Policy lifecycle management** from quote to expiration

### 🚨 Claims Processing
- **Multi-type claim handling** (auto, property, liability, medical)
- **Document management** with OCR processing capabilities
- **Fraud detection** and investigation workflows
- **Payment processing** with approval hierarchies

### 💼 Agent & Distribution Management
- **Commission tracking** and performance analytics
- **License and certification** management
- **Agency relationships** and hierarchy support
- **Sales performance** metrics and reporting

## Database Schema Highlights

### Core Tables

#### Policyholder Management
- **`policyholders`** - Base policyholder information with compliance status
- **`individual_policyholders`** - Personal details and risk factors
- **`business_policyholders`** - Business entity information and operations

#### Product & Policy Management
- **`insurance_products`** - Product definitions with coverage details
- **`policies`** - Policy administration and lifecycle tracking
- **`policy_coverages`** - Detailed coverage breakdowns and limits

#### Claims Processing
- **`claims`** - Claim intake, investigation, and settlement
- **`claim_payments`** - Payment processing and disbursement
- **`claim_documents`** - Document management with metadata

#### Underwriting & Risk
- **`underwriting_applications`** - Application processing workflows
- **`risk_assessments`** - Comprehensive risk scoring and evaluation

#### Distribution & Sales
- **`agents`** - Agent management and performance tracking
- **`agent_commissions`** - Commission calculation and payment

#### Financial Processing
- **`premium_billing`** - Billing cycles and payment tracking
- **`payment_transactions`** - Payment processing and reconciliation

## Key Design Patterns

### 1. Policy Lifecycle Management
```sql
-- Policy status progression with validation
CREATE OR REPLACE FUNCTION update_policy_status(
    policy_uuid UUID,
    new_status VARCHAR,
    change_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    current_status VARCHAR;
    valid_transition BOOLEAN := FALSE;
BEGIN
    -- Get current status
    SELECT policy_status INTO current_status
    FROM policies WHERE policy_id = policy_uuid;

    -- Validate status transitions
    CASE current_status
        WHEN 'quote' THEN
            valid_transition := new_status IN ('application', 'cancelled');
        WHEN 'application' THEN
            valid_transition := new_status IN ('underwriting', 'cancelled');
        WHEN 'underwriting' THEN
            valid_transition := new_status IN ('approved', 'declined');
        WHEN 'approved' THEN
            valid_transition := new_status IN ('issued');
        WHEN 'issued' THEN
            valid_transition := new_status IN ('active', 'cancelled');
        WHEN 'active' THEN
            valid_transition := new_status IN ('cancelled', 'expired', 'lapsed');
        WHEN 'cancelled', 'expired', 'lapsed' THEN
            valid_transition := FALSE; -- Terminal states
    END CASE;

    IF NOT valid_transition THEN
        RAISE EXCEPTION 'Invalid status transition from % to %', current_status, new_status;
    END IF;

    -- Update policy
    UPDATE policies
    SET policy_status = new_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE policy_id = policy_uuid;

    -- Log status change
    INSERT INTO policy_status_history (policy_id, old_status, new_status, change_reason)
    VALUES (policy_uuid, current_status, new_status, change_reason);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
```

### 2. Claims Processing Workflow
```sql
-- Automated claims assignment and routing
CREATE OR REPLACE FUNCTION assign_claim_adjuster(claim_uuid UUID)
RETURNS UUID AS $$
DECLARE
    claim_record claims%ROWTYPE;
    adjuster_uuid UUID;
    workload_count INTEGER;
BEGIN
    -- Get claim details
    SELECT * INTO claim_record FROM claims WHERE claim_id = claim_uuid;

    -- Find adjuster with lowest workload for this claim type
    SELECT a.agent_id, COUNT(c.claim_id) as current_workload
    INTO adjuster_uuid, workload_count
    FROM agents a
    LEFT JOIN claims c ON a.agent_id = c.assigned_adjuster_id
        AND c.claim_status NOT IN ('closed', 'paid')
    WHERE a.agent_type = 'adjuster'
      AND a.agent_status = 'active'
      AND (a.specialties IS NULL OR claim_record.claim_type = ANY(a.specialties))
    GROUP BY a.agent_id
    ORDER BY current_workload ASC, a.last_assignment_at ASC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No available adjuster for claim type: %', claim_record.claim_type;
    END IF;

    -- Assign claim to adjuster
    UPDATE claims
    SET assigned_adjuster_id = adjuster_uuid,
        investigation_start_date = CURRENT_DATE,
        updated_at = CURRENT_TIMESTAMP
    WHERE claim_id = claim_uuid;

    -- Update adjuster's last assignment
    UPDATE agents
    SET last_assignment_at = CURRENT_TIMESTAMP
    WHERE agent_id = adjuster_uuid;

    RETURN adjuster_uuid;
END;
$$ LANGUAGE plpgsql;
```

### 3. Premium Calculation Engine
```sql
-- Dynamic premium calculation based on risk factors
CREATE OR REPLACE FUNCTION calculate_premium(
    product_uuid UUID,
    policyholder_uuid UUID,
    coverage_amount DECIMAL DEFAULT NULL,
    deductible DECIMAL DEFAULT NULL
)
RETURNS DECIMAL AS $$
DECLARE
    base_premium DECIMAL;
    risk_multiplier DECIMAL := 1.0;
    final_premium DECIMAL;
    risk_factors JSONB;
BEGIN
    -- Get product base premium
    SELECT base_premium INTO base_premium
    FROM insurance_products WHERE product_id = product_uuid;

    -- Get risk assessment
    SELECT risk_assessment INTO risk_factors
    FROM underwriting_applications
    WHERE policyholder_id = policyholder_uuid
      AND application_status = 'approved'
    ORDER BY submitted_at DESC
    LIMIT 1;

    -- Apply risk adjustments
    IF risk_factors->>'credit_score' IS NOT NULL THEN
        CASE
            WHEN (risk_factors->>'credit_score')::INTEGER < 600 THEN risk_multiplier := risk_multiplier * 1.5;
            WHEN (risk_factors->>'credit_score')::INTEGER < 700 THEN risk_multiplier := risk_multiplier * 1.2;
            WHEN (risk_factors->>'credit_score')::INTEGER >= 800 THEN risk_multiplier := risk_multiplier * 0.9;
        END CASE;
    END IF;

    -- Apply coverage and deductible adjustments
    IF coverage_amount IS NOT NULL THEN
        risk_multiplier := risk_multiplier * (coverage_amount / 100000); -- Scale factor
    END IF;

    IF deductible IS NOT NULL THEN
        risk_multiplier := risk_multiplier * (1 - deductible / coverage_amount * 0.1);
    END IF;

    -- Calculate final premium
    final_premium := base_premium * risk_multiplier;

    -- Apply minimum and maximum bounds
    SELECT GREATEST(final_premium, ip.minimum_premium)
    INTO final_premium
    FROM insurance_products ip
    WHERE ip.product_id = product_uuid;

    RETURN ROUND(final_premium, 2);
END;
$$ LANGUAGE plpgsql;
```

### 4. Commission Calculation and Payment
```sql
-- Automated commission processing
CREATE OR REPLACE FUNCTION process_agent_commissions(policy_uuid UUID)
RETURNS INTEGER AS $$
DECLARE
    policy_record policies%ROWTYPE;
    agent_record agents%ROWTYPE;
    commission_rate DECIMAL;
    commission_amount DECIMAL;
    processed_count INTEGER := 0;
BEGIN
    -- Get policy and agent details
    SELECT p.*, a.* INTO policy_record, agent_record
    FROM policies p
    JOIN agents a ON p.agent_id = a.agent_id
    WHERE p.policy_id = policy_uuid;

    -- Get commission rate from agent's structure
    commission_rate := (agent_record.commission_structure->>'new_business_rate')::DECIMAL;

    IF commission_rate IS NULL THEN
        commission_rate := 0.10; -- Default 10%
    END IF;

    -- Calculate commission
    commission_amount := policy_record.premium_amount * commission_rate;

    -- Insert commission record
    INSERT INTO agent_commissions (
        agent_id, policy_id, commission_type, commission_amount,
        commission_rate, earned_date
    ) VALUES (
        agent_record.agent_id, policy_uuid, 'new_business',
        commission_amount, commission_rate, CURRENT_DATE
    );

    processed_count := 1;

    -- Update agent totals
    UPDATE agents
    SET total_policies = total_policies + 1,
        total_premium = total_premium + policy_record.premium_amount,
        ytd_policies = ytd_policies + 1,
        ytd_premium = ytd_premium + policy_record.premium_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE agent_id = agent_record.agent_id;

    RETURN processed_count;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition claims by incident year for performance
CREATE TABLE claims PARTITION BY RANGE (EXTRACT(YEAR FROM incident_date));

CREATE TABLE claims_2024 PARTITION OF claims
    FOR VALUES FROM (2024) TO (2025);

-- Partition billing by due date
CREATE TABLE premium_billing PARTITION BY RANGE (due_date);

CREATE TABLE premium_billing_2024_q1 PARTITION OF premium_billing
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');
```

### Advanced Indexing
```sql
-- Full-text search on policy and claim descriptions
CREATE INDEX idx_policies_description_search ON policies
    USING gin (to_tsvector('english', policy_description));

CREATE INDEX idx_claims_description_search ON claims
    USING gin (to_tsvector('english', incident_description));

-- Spatial index for location-based queries
CREATE INDEX idx_claims_location ON claims
    USING gist (ST_Point((incident_location->>'longitude')::float,
                        (incident_location->>'latitude')::float));

-- JSONB indexes for flexible querying
CREATE INDEX idx_underwriting_applications_risk ON underwriting_applications
    USING gin ((application_data->'risk_factors'));

CREATE INDEX idx_policies_coverage ON policies
    USING gin (coverage_limits);
```

### Materialized Views for Analytics
```sql
-- Claims analytics view
CREATE MATERIALIZED VIEW claims_analytics AS
SELECT
    DATE_TRUNC('month', c.incident_date) as incident_month,
    c.claim_type,
    c.claim_status,
    COUNT(*) as claim_count,
    AVG(c.claimed_amount) as avg_claimed_amount,
    AVG(c.approved_amount) as avg_approved_amount,
    SUM(c.paid_amount) as total_paid_amount,

    -- Processing time metrics
    AVG(EXTRACT(EPOCH FROM (c.approval_date - c.reported_date))/86400) as avg_processing_days,
    AVG(EXTRACT(EPOCH FROM (c.payment_date - c.approval_date))/86400) as avg_payment_days,

    -- Fraud metrics
    AVG(c.fraud_score) as avg_fraud_score,
    COUNT(CASE WHEN c.fraud_score > 7 THEN 1 END) as high_fraud_claims

FROM claims c
WHERE c.incident_date >= CURRENT_DATE - INTERVAL '24 months'
GROUP BY DATE_TRUNC('month', c.incident_date), c.claim_type, c.claim_status;

-- Refresh weekly
CREATE UNIQUE INDEX idx_claims_analytics_unique ON claims_analytics (incident_month, claim_type, claim_status);
REFRESH MATERIALIZED VIEW CONCURRENTLY claims_analytics;
```

## Security Considerations

### Data Encryption
```sql
-- Sensitive data encryption functions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypt sensitive policyholder data
CREATE OR REPLACE FUNCTION encrypt_policyholder_data(plain_text TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(plain_text, current_setting('insurance.encryption_key'));
END;
$$ LANGUAGE plpgsql;

-- Row-level security for multi-tenant access
ALTER TABLE policies ENABLE ROW LEVEL SECURITY;

CREATE POLICY agent_policy_access ON policies
    FOR SELECT USING (
        agent_id = current_setting('app.agent_id')::UUID OR
        current_setting('app.user_role')::TEXT = 'admin'
    );
```

### Audit Trail
```sql
-- Comprehensive audit logging
CREATE TABLE insurance_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    changed_by UUID,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    session_id TEXT,
    ip_address INET
) PARTITION BY RANGE (changed_at);

-- Audit trigger function
CREATE OR REPLACE FUNCTION insurance_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO insurance_audit_log (
        table_name, record_id, operation, old_values, new_values,
        changed_by, session_id, ip_address
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr()
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### Regulatory Reporting
```sql
-- Automated regulatory reporting
CREATE OR REPLACE FUNCTION generate_regulatory_report(
    report_type VARCHAR,
    report_period_start DATE,
    report_period_end DATE
)
RETURNS TABLE (
    report_line JSONB,
    report_category TEXT
) AS $$
BEGIN
    -- Insurance statistical reports
    IF report_type = 'statistical' THEN
        RETURN QUERY
        SELECT
            jsonb_build_object(
                'period', report_period_start || ' to ' || report_period_end,
                'policies_issued', COUNT(*),
                'premium_written', SUM(premium_amount),
                'claims_incurred', COUNT(c.claim_id),
                'claims_paid', SUM(c.paid_amount)
            ),
            'summary'::TEXT
        FROM policies p
        LEFT JOIN claims c ON p.policy_id = c.policy_id
            AND c.incident_date BETWEEN report_period_start AND report_period_end
        WHERE p.effective_date BETWEEN report_period_start AND report_period_end;

    -- Claims reporting
    ELSIF report_type = 'claims' THEN
        RETURN QUERY
        SELECT
            jsonb_build_object(
                'claim_id', c.claim_id,
                'policy_number', p.policy_number,
                'claim_type', c.claim_type,
                'incident_date', c.incident_date,
                'paid_amount', c.paid_amount,
                'processing_time_days', EXTRACT(EPOCH FROM (c.payment_date - c.reported_date))/86400
            ),
            'claims'::TEXT
        FROM claims c
        JOIN policies p ON c.policy_id = p.policy_id
        WHERE c.reported_date BETWEEN report_period_start AND report_period_end
          AND c.claim_status = 'paid';
    END IF;
END;
$$ LANGUAGE plpgsql;
```

### Fraud Detection
```sql
-- Automated fraud scoring
CREATE OR REPLACE FUNCTION calculate_fraud_score(claim_uuid UUID)
RETURNS DECIMAL AS $$
DECLARE
    claim_record claims%ROWTYPE;
    fraud_score DECIMAL := 0;
    policy_age_days INTEGER;
    claim_frequency INTEGER;
BEGIN
    -- Get claim details
    SELECT c.* INTO claim_record FROM claims c WHERE c.claim_id = claim_uuid;

    -- Factor 1: Policy age (newer policies slightly higher risk)
    SELECT EXTRACT(EPOCH FROM (CURRENT_DATE - p.effective_date))/86400 INTO policy_age_days
    FROM policies p WHERE p.policy_id = claim_record.policy_id;

    IF policy_age_days < 30 THEN fraud_score := fraud_score + 2;
    ELSIF policy_age_days < 90 THEN fraud_score := fraud_score + 1;
    END IF;

    -- Factor 2: Claim frequency (multiple claims on same policy)
    SELECT COUNT(*) INTO claim_frequency
    FROM claims
    WHERE policy_id = claim_record.policy_id
      AND claim_id != claim_uuid
      AND reported_date >= CURRENT_DATE - INTERVAL '12 months';

    fraud_score := fraud_score + (claim_frequency * 0.5);

    -- Factor 3: Claim amount vs policy coverage ratio
    SELECT c.claimed_amount / p.coverage_amount INTO fraud_score
    FROM policies p WHERE p.policy_id = claim_record.policy_id;

    IF fraud_score > 0.8 THEN fraud_score := fraud_score + 3;
    ELSIF fraud_score > 0.5 THEN fraud_score := fraud_score + 1.5;
    END IF;

    -- Factor 4: Incident timing (claims reported outside business hours)
    IF EXTRACT(HOUR FROM claim_record.reported_date) NOT BETWEEN 9 AND 17 THEN
        fraud_score := fraud_score + 0.5;
    END IF;

    RETURN LEAST(fraud_score, 10.0);
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Credit bureaus** for risk assessment and underwriting
- **Claims adjustment networks** for catastrophe claims
- **Medical billing systems** for health insurance claims
- **Vehicle registration databases** for auto insurance

### API Endpoints
- **Policy administration APIs** for agent and customer portals
- **Claims intake APIs** for mobile apps and third parties
- **Underwriting APIs** for automated risk assessment
- **Reporting APIs** for regulatory compliance

## Monitoring & Analytics

### Key Performance Indicators
- **Loss ratios** by product line and time period
- **Claims processing times** and customer satisfaction
- **Underwriting profitability** and risk-adjusted returns
- **Agent productivity** and commission metrics
- **Regulatory compliance** and audit findings

### Real-time Dashboards
```sql
-- Insurance operations dashboard
CREATE VIEW insurance_operations_dashboard AS
SELECT
    -- Policy metrics
    (SELECT COUNT(*) FROM policies WHERE policy_status = 'active') as active_policies,
    (SELECT SUM(premium_amount) FROM policies WHERE policy_status = 'active') as annualized_premium,
    (SELECT COUNT(*) FROM policies WHERE effective_date >= CURRENT_DATE - INTERVAL '30 days') as new_policies_this_month,

    -- Claims metrics
    (SELECT COUNT(*) FROM claims WHERE claim_status NOT IN ('closed', 'paid')) as open_claims,
    (SELECT AVG(EXTRACT(EPOCH FROM (payment_date - reported_date))/86400)
     FROM claims WHERE payment_date IS NOT NULL AND reported_date >= CURRENT_DATE - INTERVAL '30 days') as avg_claim_processing_days,

    -- Financial metrics
    (SELECT SUM(paid_amount) FROM claims WHERE payment_date >= CURRENT_DATE - INTERVAL '30 days') as claims_paid_this_month,
    (SELECT SUM(billed_amount) FROM premium_billing WHERE billing_status = 'paid' AND created_at >= CURRENT_DATE - INTERVAL '30 days') as premium_collected_this_month,

    -- Risk metrics
    (SELECT COUNT(*) FROM fraud_alerts WHERE created_at >= CURRENT_DATE - INTERVAL '7 days') as fraud_alerts_this_week,
    (SELECT AVG(fraud_score) FROM claims WHERE reported_date >= CURRENT_DATE - INTERVAL '30 days') as avg_fraud_score
;
```

This insurance database schema provides enterprise-grade infrastructure for insurance operations with comprehensive policy management, claims processing, risk assessment, and regulatory compliance capabilities.
