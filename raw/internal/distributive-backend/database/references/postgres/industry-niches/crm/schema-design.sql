-- Customer Relationship Management (CRM) Database Schema
-- Comprehensive schema for CRM systems, customer service, sales management, and marketing automation

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- ORGANIZATION AND USER MANAGEMENT
-- ===========================================

CREATE TABLE organizations (
    organization_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_name VARCHAR(255) NOT NULL,
    organization_code VARCHAR(20) UNIQUE NOT NULL,

    -- Organization Details
    industry VARCHAR(50),
    company_size VARCHAR(20) CHECK (company_size IN ('startup', 'small', 'medium', 'large', 'enterprise')),
    website VARCHAR(500),
    description TEXT,

    -- Contact Information
    address JSONB,
    phone VARCHAR(20),
    email VARCHAR(255),

    -- Business Information
    tax_id VARCHAR(50),
    registration_number VARCHAR(50),

    -- Subscription and Billing
    subscription_plan VARCHAR(20) CHECK (subscription_plan IN ('free', 'basic', 'professional', 'enterprise')),
    billing_cycle VARCHAR(20) CHECK (billing_cycle IN ('monthly', 'annual')),
    monthly_fee DECIMAL(8,2),

    -- Status and Settings
    organization_status VARCHAR(20) DEFAULT 'active' CHECK (organization_status IN ('active', 'inactive', 'suspended', 'cancelled')),
    timezone VARCHAR(50) DEFAULT 'UTC',
    locale VARCHAR(10) DEFAULT 'en-US',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),

    -- User Information
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(50) UNIQUE,
    first_name VARCHAR(100),
    last_name VARCHAR(100),

    -- Authentication
    password_hash VARCHAR(255),
    password_salt VARCHAR(255),
    email_verified BOOLEAN DEFAULT FALSE,
    email_verification_token VARCHAR(255),

    -- Profile
    avatar_url VARCHAR(500),
    phone VARCHAR(20),
    job_title VARCHAR(100),
    department VARCHAR(100),

    -- Permissions and Roles
    user_role VARCHAR(30) CHECK (user_role IN ('admin', 'manager', 'sales_rep', 'support_agent', 'viewer')),
    permissions JSONB DEFAULT '[]',

    -- Preferences
    timezone VARCHAR(50) DEFAULT 'UTC',
    locale VARCHAR(10) DEFAULT 'en-US',
    notification_preferences JSONB DEFAULT '{}',

    -- Status
    user_status VARCHAR(20) DEFAULT 'active' CHECK (user_status IN ('active', 'inactive', 'suspended', 'pending_verification')),
    last_login_at TIMESTAMP WITH TIME ZONE,
    password_changed_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- CUSTOMER AND CONTACT MANAGEMENT
-- ===========================================

CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),

    -- Customer Identity
    customer_number VARCHAR(20) UNIQUE,
    customer_type VARCHAR(20) DEFAULT 'individual' CHECK (customer_type IN ('individual', 'business', 'prospect')),

    -- Personal/Business Information
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    company_name VARCHAR(255),
    title VARCHAR(100),

    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(20),
    mobile_phone VARCHAR(20),
    fax VARCHAR(20),

    -- Address Information
    billing_address JSONB,
    shipping_address JSONB,

    -- Demographics
    date_of_birth DATE,
    gender VARCHAR(20),
    marital_status VARCHAR(20),
    education_level VARCHAR(50),
    occupation VARCHAR(100),

    -- Preferences and Interests
    preferred_contact_method VARCHAR(20) CHECK (preferred_contact_method IN ('email', 'phone', 'sms', 'mail')),
    interests JSONB DEFAULT '[]',
    communication_preferences JSONB DEFAULT '{}',

    -- Customer Lifecycle
    lead_source VARCHAR(50),
    lead_score INTEGER DEFAULT 0 CHECK (lead_score >= 0 AND lead_score <= 100),
    lifecycle_stage VARCHAR(30) CHECK (lifecycle_stage IN ('prospect', 'lead', 'qualified', 'customer', 'loyal', 'champion', 'churned')),

    -- Financial Information
    annual_revenue DECIMAL(12,2),
    credit_score INTEGER,
    payment_terms VARCHAR(50),

    -- Status and Assignment
    customer_status VARCHAR(20) DEFAULT 'active' CHECK (customer_status IN ('active', 'inactive', 'prospect', 'lead', 'customer')),
    assigned_to UUID REFERENCES users(user_id),
    tags JSONB DEFAULT '[]',

    -- Important Dates
    first_contact_date DATE,
    last_contact_date DATE,
    next_follow_up_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK ((customer_type = 'business' AND company_name IS NOT NULL) OR
           (customer_type = 'individual' AND first_name IS NOT NULL))
);

CREATE TABLE customer_segments (
    segment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),

    -- Segment Definition
    segment_name VARCHAR(100) NOT NULL,
    segment_description TEXT,
    segment_type VARCHAR(30) CHECK (segment_type IN ('static', 'dynamic', 'behavioral', 'demographic')),

    -- Segment Criteria
    filter_criteria JSONB DEFAULT '{}', -- Dynamic filters for segment membership
    customer_count INTEGER DEFAULT 0,

    -- Segment Management
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES users(user_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer_segment_members (
    segment_id UUID NOT NULL REFERENCES customer_segments(segment_id),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Membership Details
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    added_by UUID REFERENCES users(user_id),

    PRIMARY KEY (segment_id, customer_id)
);

-- ===========================================
-- SALES AND OPPORTUNITY MANAGEMENT
-- ===========================================

CREATE TABLE opportunities (
    opportunity_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Opportunity Details
    opportunity_name VARCHAR(255) NOT NULL,
    opportunity_description TEXT,

    -- Sales Process
    sales_stage VARCHAR(30) CHECK (sales_stage IN (
        'prospecting', 'qualification', 'proposal', 'negotiation', 'closed_won', 'closed_lost'
    )),
    probability_percentage DECIMAL(5,2) CHECK (probability_percentage >= 0 AND probability_percentage <= 100),

    -- Financial Information
    estimated_value DECIMAL(12,2),
    expected_close_date DATE,
    actual_close_date DATE,

    -- Product/Service Information
    products_interested JSONB DEFAULT '[]',
    competitor_info JSONB DEFAULT '{}',

    -- Assignment and Tracking
    assigned_to UUID REFERENCES users(user_id),
    created_by UUID REFERENCES users(user_id),

    -- Status and Dates
    opportunity_status VARCHAR(20) DEFAULT 'open' CHECK (opportunity_status IN ('open', 'won', 'lost', 'cancelled')),
    last_activity_date DATE DEFAULT CURRENT_DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE opportunity_activities (
    activity_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID NOT NULL REFERENCES opportunities(opportunity_id),

    -- Activity Details
    activity_type VARCHAR(30) CHECK (activity_type IN (
        'call', 'email', 'meeting', 'demo', 'proposal', 'follow_up', 'site_visit'
    )),
    activity_subject VARCHAR(255),
    activity_description TEXT,

    -- Timing
    scheduled_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER,

    -- Participants and Assignment
    assigned_to UUID REFERENCES users(user_id),
    participants JSONB DEFAULT '[]',

    -- Outcome and Notes
    outcome VARCHAR(50),
    notes TEXT,

    -- Status
    activity_status VARCHAR(20) DEFAULT 'scheduled' CHECK (activity_status IN ('scheduled', 'completed', 'cancelled', 'no_show')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE quotes (
    quote_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID NOT NULL REFERENCES opportunities(opportunity_id),

    -- Quote Details
    quote_number VARCHAR(30) UNIQUE NOT NULL,
    quote_version INTEGER DEFAULT 1,
    quote_title VARCHAR(255),

    -- Financial Information
    subtotal DECIMAL(12,2),
    discount_percentage DECIMAL(5,2) DEFAULT 0,
    discount_amount DECIMAL(10,2) DEFAULT 0,
    tax_amount DECIMAL(10,2),
    total_amount DECIMAL(12,2),

    -- Terms and Conditions
    payment_terms VARCHAR(100),
    delivery_terms VARCHAR(100),
    warranty_terms TEXT,
    validity_days INTEGER DEFAULT 30,

    -- Status and Approval
    quote_status VARCHAR(20) DEFAULT 'draft' CHECK (quote_status IN ('draft', 'sent', 'approved', 'rejected', 'expired')),
    sent_at TIMESTAMP WITH TIME ZONE,
    approved_at TIMESTAMP WITH TIME ZONE,
    approved_by UUID REFERENCES users(user_id),

    -- Expiration
    expires_at DATE GENERATED ALWAYS AS (
        sent_at::DATE + INTERVAL '1 day' * validity_days
    ) STORED,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE quote_items (
    quote_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quote_id UUID NOT NULL REFERENCES quotes(quote_id) ON DELETE CASCADE,

    -- Product/Service Details
    product_name VARCHAR(255) NOT NULL,
    product_description TEXT,
    product_code VARCHAR(50),

    -- Pricing
    quantity DECIMAL(10,2) NOT NULL DEFAULT 1,
    unit_price DECIMAL(8,2) NOT NULL,
    line_total DECIMAL(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,

    -- Additional Information
    discount_percentage DECIMAL(5,2) DEFAULT 0,
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity > 0),
    CHECK (unit_price >= 0)
);

-- ===========================================
-- CUSTOMER SERVICE AND SUPPORT
-- ===========================================

CREATE TABLE support_tickets (
    ticket_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),
    customer_id UUID REFERENCES customers(customer_id),

    -- Ticket Identification
    ticket_number VARCHAR(30) UNIQUE NOT NULL,
    ticket_subject VARCHAR(255) NOT NULL,

    -- Ticket Details
    ticket_description TEXT,
    ticket_type VARCHAR(30) CHECK (ticket_type IN (
        'question', 'complaint', 'bug_report', 'feature_request',
        'billing_issue', 'technical_support', 'account_issue'
    )),
    ticket_priority VARCHAR(10) CHECK (ticket_priority IN ('low', 'medium', 'high', 'urgent')),

    -- Classification
    category VARCHAR(50),
    subcategory VARCHAR(50),
    tags JSONB DEFAULT '[]',

    -- Assignment and Ownership
    assigned_to UUID REFERENCES users(user_id),
    assigned_by UUID REFERENCES users(user_id),
    assigned_at TIMESTAMP WITH TIME ZONE,

    -- Status and Resolution
    ticket_status VARCHAR(20) DEFAULT 'open' CHECK (ticket_status IN (
        'open', 'in_progress', 'waiting_customer', 'resolved', 'closed', 'escalated'
    )),
    resolution TEXT,
    resolution_category VARCHAR(50),

    -- Customer Satisfaction
    customer_satisfaction_rating INTEGER CHECK (customer_satisfaction_rating BETWEEN 1 AND 5),
    customer_feedback TEXT,

    -- SLA Tracking
    sla_breach BOOLEAN DEFAULT FALSE,
    first_response_time INTERVAL,
    resolution_time INTERVAL,
    sla_target_response_time INTERVAL DEFAULT INTERVAL '24 hours',
    sla_target_resolution_time INTERVAL DEFAULT INTERVAL '7 days',

    -- Communication
    last_customer_response_at TIMESTAMP WITH TIME ZONE,
    last_agent_response_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE ticket_messages (
    message_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(ticket_id) ON DELETE CASCADE,

    -- Message Details
    message_body TEXT NOT NULL,
    message_type VARCHAR(20) CHECK (message_type IN ('customer', 'agent', 'system', 'internal_note')),

    -- Sender Information
    sent_by UUID REFERENCES users(user_id), -- NULL for customer messages
    sender_name VARCHAR(255), -- For customer messages
    sender_email VARCHAR(255), -- For customer messages

    -- Attachments
    attachments JSONB DEFAULT '[]',

    -- Status
    is_internal BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- MARKETING AND CAMPAIGN MANAGEMENT
-- ===========================================

CREATE TABLE campaigns (
    campaign_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),

    -- Campaign Details
    campaign_name VARCHAR(255) NOT NULL,
    campaign_description TEXT,
    campaign_type VARCHAR(30) CHECK (campaign_type IN (
        'email', 'social_media', 'direct_mail', 'telemarketing',
        'webinar', 'trade_show', 'content_marketing', 'paid_ads'
    )),

    -- Campaign Goals
    target_audience JSONB DEFAULT '{}',
    campaign_goal VARCHAR(50),
    expected_roi DECIMAL(5,2),

    -- Budget and Costs
    budget_allocated DECIMAL(10,2),
    actual_cost DECIMAL(10,2) DEFAULT 0,
    cost_per_lead DECIMAL(8,2),

    -- Timeline
    planned_start_date DATE,
    planned_end_date DATE,
    actual_start_date DATE,
    actual_end_date DATE,

    -- Performance Metrics
    target_impressions INTEGER,
    actual_impressions INTEGER DEFAULT 0,
    target_clicks INTEGER,
    actual_clicks INTEGER DEFAULT 0,
    target_conversions INTEGER,
    actual_conversions INTEGER DEFAULT 0,

    -- Status and Assignment
    campaign_status VARCHAR(20) DEFAULT 'planning' CHECK (campaign_status IN (
        'planning', 'active', 'paused', 'completed', 'cancelled'
    )),
    assigned_to UUID REFERENCES users(user_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE campaign_segments (
    campaign_id UUID NOT NULL REFERENCES campaigns(campaign_id),
    segment_id UUID NOT NULL REFERENCES customer_segments(segment_id),

    PRIMARY KEY (campaign_id, segment_id)
);

CREATE TABLE email_templates (
    template_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),

    -- Template Details
    template_name VARCHAR(255) NOT NULL,
    template_subject VARCHAR(255),
    template_body TEXT,

    -- Template Configuration
    template_type VARCHAR(30) CHECK (template_type IN ('welcome', 'newsletter', 'promotional', 'transactional', 'follow_up')),
    variables JSONB DEFAULT '[]', -- Available merge fields

    -- Design and Assets
    header_image_url VARCHAR(500),
    footer_content TEXT,
    styling JSONB DEFAULT '{}',

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES users(user_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE email_sends (
    send_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_id UUID REFERENCES campaigns(campaign_id),

    -- Send Details
    template_id UUID REFERENCES email_templates(template_id),
    segment_id UUID REFERENCES customer_segments(segment_id),

    -- Send Configuration
    send_name VARCHAR(255),
    from_name VARCHAR(255),
    from_email VARCHAR(255),
    reply_to_email VARCHAR(255),

    -- Scheduling
    scheduled_send_time TIMESTAMP WITH TIME ZONE,
    actual_send_time TIMESTAMP WITH TIME ZONE,

    -- Recipients and Performance
    total_recipients INTEGER,
    delivered_count INTEGER DEFAULT 0,
    opened_count INTEGER DEFAULT 0,
    clicked_count INTEGER DEFAULT 0,
    bounced_count INTEGER DEFAULT 0,
    unsubscribed_count INTEGER DEFAULT 0,

    -- Status
    send_status VARCHAR(20) DEFAULT 'scheduled' CHECK (send_status IN ('scheduled', 'sending', 'completed', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

CREATE TABLE interaction_logs (
    interaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID REFERENCES customers(customer_id),
    user_id UUID REFERENCES users(user_id),

    -- Interaction Details
    interaction_type VARCHAR(30) CHECK (interaction_type IN (
        'email_sent', 'email_opened', 'email_clicked', 'call_made', 'call_received',
        'meeting', 'website_visit', 'form_submission', 'social_engagement'
    )),
    interaction_channel VARCHAR(30) CHECK (interaction_channel IN (
        'email', 'phone', 'web', 'social_media', 'in_person', 'direct_mail'
    )),

    -- Content and Context
    subject VARCHAR(255),
    content_summary TEXT,
    campaign_id UUID REFERENCES campaigns(campaign_id),

    -- Timing and Duration
    interaction_date DATE DEFAULT CURRENT_DATE,
    interaction_time TIME DEFAULT CURRENT_TIME,
    duration_seconds INTEGER,

    -- Location and Device (for digital interactions)
    ip_address INET,
    user_agent TEXT,
    location JSONB,

    -- Outcome and Sentiment
    outcome VARCHAR(50),
    sentiment VARCHAR(20) CHECK (sentiment IN ('positive', 'neutral', 'negative')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_period VARCHAR(10) CHECK (report_period IN ('daily', 'weekly', 'monthly', 'quarterly')),

    -- Sales Metrics
    leads_generated INTEGER DEFAULT 0,
    opportunities_created INTEGER DEFAULT 0,
    deals_closed INTEGER DEFAULT 0,
    revenue_generated DECIMAL(15,2) DEFAULT 0,

    -- Conversion Rates
    lead_to_opportunity_rate DECIMAL(5,2),
    opportunity_to_deal_rate DECIMAL(5,2),
    overall_conversion_rate DECIMAL(5,2),

    -- Pipeline Metrics
    total_pipeline_value DECIMAL(15,2),
    average_deal_size DECIMAL(10,2),
    average_sales_cycle_days INTEGER,

    -- Performance by User
    top_performers JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (organization_id, report_date, report_period)
);

CREATE TABLE customer_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(organization_id),

    -- Time Dimensions
    report_date DATE NOT NULL,

    -- Customer Metrics
    total_customers INTEGER DEFAULT 0,
    new_customers INTEGER DEFAULT 0,
    active_customers INTEGER DEFAULT 0,
    churned_customers INTEGER DEFAULT 0,

    -- Engagement Metrics
    email_open_rate DECIMAL(5,2),
    email_click_rate DECIMAL(5,2),
    website_visit_rate DECIMAL(5,2),

    -- Satisfaction Metrics
    average_satisfaction_rating DECIMAL(3,1),
    net_promoter_score DECIMAL(5,2),

    -- Segmentation
    customer_distribution_by_segment JSONB DEFAULT '{}',
    customer_lifecycle_distribution JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (organization_id, report_date)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Organization and user indexes
CREATE INDEX idx_users_organization ON users (organization_id);
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_status ON users (user_status);

-- Customer indexes
CREATE INDEX idx_customers_organization ON customers (organization_id);
CREATE INDEX idx_customers_email ON customers (email);
CREATE INDEX idx_customers_type_status ON customers (customer_type, customer_status);
CREATE INDEX idx_customers_lifecycle ON customers (lifecycle_stage);
CREATE INDEX idx_customers_assigned_to ON customers (assigned_to);

-- Sales indexes
CREATE INDEX idx_opportunities_organization ON opportunities (organization_id);
CREATE INDEX idx_opportunities_customer ON opportunities (customer_id);
CREATE INDEX idx_opportunities_stage ON opportunities (sales_stage, opportunity_status);
CREATE INDEX idx_opportunities_assigned_to ON opportunities (assigned_to);

-- Support indexes
CREATE INDEX idx_support_tickets_organization ON support_tickets (organization_id);
CREATE INDEX idx_support_tickets_customer ON support_tickets (customer_id);
CREATE INDEX idx_support_tickets_status ON support_tickets (ticket_status);
CREATE INDEX idx_support_tickets_assigned_to ON support_tickets (assigned_to);

-- Campaign indexes
CREATE INDEX idx_campaigns_organization ON campaigns (organization_id);
CREATE INDEX idx_campaigns_status ON campaigns (campaign_status);
CREATE INDEX idx_email_sends_campaign ON email_sends (campaign_id);

-- Analytics indexes
CREATE INDEX idx_interaction_logs_customer ON interaction_logs (customer_id, interaction_date DESC);
CREATE INDEX idx_interaction_logs_type ON interaction_logs (interaction_type, interaction_date);
CREATE INDEX idx_sales_analytics_organization ON sales_analytics (organization_id, report_date DESC);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Customer 360-degree view
CREATE VIEW customer_360_view AS
SELECT
    c.customer_id,
    c.customer_number,
    c.first_name || ' ' || c.last_name as customer_name,
    c.company_name,
    c.email,
    c.lifecycle_stage,
    c.lead_score,

    -- Contact and assignment info
    c.assigned_to,
    u.first_name || ' ' || u.last_name as assigned_user,
    c.last_contact_date,

    -- Sales activity
    COUNT(DISTINCT o.opportunity_id) as total_opportunities,
    COUNT(DISTINCT CASE WHEN o.opportunity_status = 'open' THEN o.opportunity_id END) as open_opportunities,
    SUM(CASE WHEN o.opportunity_status = 'won' THEN o.estimated_value END) as total_deals_won,

    -- Support activity
    COUNT(DISTINCT st.ticket_id) as total_tickets,
    COUNT(DISTINCT CASE WHEN st.ticket_status IN ('open', 'in_progress') THEN st.ticket_id END) as open_tickets,
    AVG(st.customer_satisfaction_rating) as avg_satisfaction_rating,

    -- Interaction summary
    COUNT(DISTINCT il.interaction_id) as total_interactions,
    MAX(il.interaction_date) as last_interaction_date,

    -- Financial summary
    SUM(b.total_amount) as total_billed,
    AVG(b.total_amount) as avg_order_value,

    -- Tags and segments
    c.tags,
    STRING_AGG(DISTINCT cs.segment_name, ', ') as segments

FROM customers c
LEFT JOIN users u ON c.assigned_to = u.user_id
LEFT JOIN opportunities o ON c.customer_id = o.customer_id
LEFT JOIN support_tickets st ON c.customer_id = st.customer_id
LEFT JOIN interaction_logs il ON c.customer_id = il.customer_id
LEFT JOIN bills b ON c.customer_id = b.customer_id -- Assuming bills table exists
LEFT JOIN customer_segment_members csm ON c.customer_id = csm.customer_id
LEFT JOIN customer_segments cs ON csm.segment_id = cs.segment_id
WHERE c.customer_status = 'active'
GROUP BY c.customer_id, c.customer_number, c.first_name, c.last_name, c.company_name,
         c.email, c.lifecycle_stage, c.lead_score, c.assigned_to, u.first_name, u.last_name,
         c.last_contact_date, c.tags;

-- Sales pipeline overview
CREATE VIEW sales_pipeline_overview AS
SELECT
    o.organization_id,
    o.sales_stage,
    COUNT(*) as opportunity_count,
    SUM(o.estimated_value) as total_value,
    AVG(o.estimated_value) as avg_opportunity_value,
    AVG(o.probability_percentage) as avg_probability,

    -- Weighted value (value * probability)
    SUM(o.estimated_value * o.probability_percentage / 100) as weighted_value,

    -- Stage performance
    COUNT(CASE WHEN o.last_activity_date >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as active_last_week,
    AVG(EXTRACT(EPOCH FROM (CURRENT_DATE - o.created_at)) / 86400) as avg_days_in_stage,

    -- Conversion metrics
    COUNT(CASE WHEN o.opportunity_status = 'won' THEN 1 END) as won_count,
    COUNT(CASE WHEN o.opportunity_status = 'lost' THEN 1 END) as lost_count

FROM opportunities o
WHERE o.opportunity_status = 'open'
GROUP BY o.organization_id, o.sales_stage
ORDER BY o.organization_id, CASE o.sales_stage
    WHEN 'prospecting' THEN 1
    WHEN 'qualification' THEN 2
    WHEN 'proposal' THEN 3
    WHEN 'negotiation' THEN 4
    WHEN 'closed_won' THEN 5
    WHEN 'closed_lost' THEN 6
END;

-- Support performance dashboard
CREATE VIEW support_performance_dashboard AS
SELECT
    st.organization_id,

    -- Ticket volume
    COUNT(*) as total_tickets,
    COUNT(CASE WHEN st.ticket_status = 'open' THEN 1 END) as open_tickets,
    COUNT(CASE WHEN st.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as tickets_last_30_days,

    -- Resolution metrics
    AVG(EXTRACT(EPOCH FROM (st.updated_at - st.created_at)) / 3600) as avg_resolution_hours,
    COUNT(CASE WHEN st.sla_breach = FALSE THEN 1 END)::DECIMAL / COUNT(*) * 100 as sla_compliance_rate,

    -- Customer satisfaction
    AVG(st.customer_satisfaction_rating) as avg_customer_satisfaction,
    COUNT(CASE WHEN st.customer_satisfaction_rating >= 4 THEN 1 END)::DECIMAL / COUNT(CASE WHEN st.customer_satisfaction_rating IS NOT NULL THEN 1 END) * 100 as satisfaction_rate,

    -- Agent performance
    COUNT(DISTINCT st.assigned_to) as active_agents,
    COUNT(*) / COUNT(DISTINCT st.assigned_to) as avg_tickets_per_agent,

    -- Category breakdown
    jsonb_object_agg(st.category, COUNT(*)) FILTER (WHERE st.category IS NOT NULL) as tickets_by_category,

    -- Priority distribution
    COUNT(CASE WHEN st.ticket_priority = 'urgent' THEN 1 END) as urgent_tickets,
    COUNT(CASE WHEN st.ticket_priority = 'high' THEN 1 END) as high_priority_tickets,
    COUNT(CASE WHEN st.ticket_priority = 'medium' THEN 1 END) as medium_priority_tickets,
    COUNT(CASE WHEN st.ticket_priority = 'low' THEN 1 END) as low_priority_tickets

FROM support_tickets st
WHERE st.created_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY st.organization_id;

-- Campaign performance analysis
CREATE VIEW campaign_performance_analysis AS
SELECT
    c.campaign_id,
    c.campaign_name,
    c.campaign_type,
    c.campaign_status,

    -- Budget and costs
    c.budget_allocated,
    c.actual_cost,
    c.actual_cost / NULLIF(c.budget_allocated, 0) * 100 as budget_utilization,

    -- Performance metrics
    c.actual_impressions,
    c.actual_clicks,
    c.actual_conversions,

    -- Calculated rates
    CASE WHEN c.actual_impressions > 0 THEN c.actual_clicks::DECIMAL / c.actual_impressions * 100 END as click_through_rate,
    CASE WHEN c.actual_clicks > 0 THEN c.actual_conversions::DECIMAL / c.actual_clicks * 100 END as conversion_rate,
    c.cost_per_lead,

    -- ROI calculation
    CASE WHEN c.actual_cost > 0 THEN (c.expected_roi * c.budget_allocated - c.actual_cost) / c.actual_cost * 100 END as roi_percentage,

    -- Timeline
    c.planned_start_date,
    c.actual_start_date,
    c.planned_end_date,
    c.actual_end_date,
    CASE WHEN c.actual_end_date IS NOT NULL THEN c.actual_end_date - c.planned_end_date ELSE CURRENT_DATE - c.planned_end_date END as schedule_variance_days

FROM campaigns c
WHERE c.campaign_status IN ('active', 'completed');

-- ===========================================
-- FUNCTIONS FOR CRM OPERATIONS
-- =========================================--

-- Function to calculate customer lifetime value
CREATE OR REPLACE FUNCTION calculate_customer_ltv(customer_uuid UUID)
RETURNS TABLE (
    total_revenue DECIMAL,
    total_cost DECIMAL,
    lifetime_value DECIMAL,
    average_order_value DECIMAL,
    purchase_frequency DECIMAL,
    customer_lifespan_days INTEGER
) AS $$
DECLARE
    first_purchase DATE;
    last_purchase DATE;
    total_orders INTEGER;
BEGIN
    -- Get customer purchase history
    SELECT
        MIN(o.order_date) as first_order,
        MAX(o.order_date) as last_order,
        COUNT(o.order_id) as order_count,
        SUM(o.total_amount) as revenue,
        AVG(o.total_amount) as avg_order
    INTO first_purchase, last_purchase, total_orders, total_revenue, average_order_value
    FROM orders o  -- Assuming orders table exists
    WHERE o.customer_id = customer_uuid;

    -- Calculate metrics
    RETURN QUERY SELECT
        total_revenue,
        0::DECIMAL as total_cost, -- Would integrate with actual cost data
        total_revenue as lifetime_value, -- Simplified LTV calculation
        average_order_value,
        total_orders::DECIMAL / GREATEST(EXTRACT(EPOCH FROM (last_purchase - first_purchase)) / 30, 1) as purchase_frequency,
        EXTRACT(EPOCH FROM (last_purchase - first_purchase)) / 86400 as customer_lifespan_days;
END;
$$ LANGUAGE plpgsql;

-- Function to score leads based on activity and engagement
CREATE OR REPLACE FUNCTION calculate_lead_score(customer_uuid UUID)
RETURNS INTEGER AS $$
DECLARE
    score INTEGER := 0;
    interaction_count INTEGER;
    recent_activity_count INTEGER;
    opportunity_count INTEGER;
BEGIN
    -- Demographic score
    SELECT CASE
        WHEN annual_revenue > 1000000 THEN 20
        WHEN annual_revenue > 500000 THEN 15
        WHEN annual_revenue > 100000 THEN 10
        ELSE 5
    END INTO score
    FROM customers WHERE customer_id = customer_uuid;

    -- Interaction score
    SELECT COUNT(*) INTO interaction_count
    FROM interaction_logs WHERE customer_id = customer_uuid;

    score := score + LEAST(interaction_count * 2, 20);

    -- Recent activity score
    SELECT COUNT(*) INTO recent_activity_count
    FROM interaction_logs
    WHERE customer_id = customer_uuid
      AND interaction_date >= CURRENT_DATE - INTERVAL '30 days';

    score := score + LEAST(recent_activity_count * 5, 25);

    -- Opportunity score
    SELECT COUNT(*) INTO opportunity_count
    FROM opportunities WHERE customer_id = customer_uuid;

    score := score + LEAST(opportunity_count * 10, 30);

    -- Cap at 100
    RETURN LEAST(score, 100);
END;
$$ LANGUAGE plpgsql;

-- Function to assign leads to sales representatives
CREATE OR REPLACE FUNCTION assign_lead_to_sales_rep(customer_uuid UUID)
RETURNS UUID AS $$
DECLARE
    assigned_rep UUID;
    rep_workload INTEGER;
    min_workload INTEGER := 999;
BEGIN
    -- Find the sales rep with the lowest current workload
    SELECT u.user_id, COUNT(c.customer_id)
    INTO assigned_rep, rep_workload
    FROM users u
    LEFT JOIN customers c ON u.user_id = c.assigned_to AND c.customer_status IN ('prospect', 'lead', 'customer')
    WHERE u.user_role = 'sales_rep'
      AND u.user_status = 'active'
    GROUP BY u.user_id
    HAVING COUNT(c.customer_id) < 50 -- Maximum leads per rep
    ORDER BY COUNT(c.customer_id) ASC
    LIMIT 1;

    -- Assign the lead
    IF assigned_rep IS NOT NULL THEN
        UPDATE customers SET assigned_to = assigned_rep WHERE customer_id = customer_uuid;
    END IF;

    RETURN assigned_rep;
END;
$$ LANGUAGE plpgsql;

-- Function to generate customer insights
CREATE OR REPLACE FUNCTION generate_customer_insights(customer_uuid UUID)
RETURNS TABLE (
    insight_type VARCHAR,
    insight_description TEXT,
    confidence_score DECIMAL,
    recommended_action TEXT
) AS $$
DECLARE
    customer_record customers%ROWTYPE;
    days_since_last_contact INTEGER;
    opportunity_count INTEGER;
    ticket_count INTEGER;
BEGIN
    -- Get customer details
    SELECT * INTO customer_record FROM customers WHERE customer_id = customer_uuid;

    -- Days since last contact
    SELECT EXTRACT(EPOCH FROM (CURRENT_DATE - last_contact_date)) / 86400 INTO days_since_last_contact
    FROM customers WHERE customer_id = customer_uuid;

    -- Check for follow-up opportunities
    IF days_since_last_contact > 30 THEN
        RETURN QUERY SELECT
            'follow_up_needed'::VARCHAR,
            'Customer has not been contacted in ' || days_since_last_contact || ' days',
            0.8,
            'Schedule a follow-up call or email to re-engage the customer';
    END IF;

    -- Check opportunity pipeline
    SELECT COUNT(*) INTO opportunity_count
    FROM opportunities WHERE customer_id = customer_uuid AND opportunity_status = 'open';

    IF opportunity_count = 0 AND customer_record.lifecycle_stage = 'customer' THEN
        RETURN QUERY SELECT
            'upsell_opportunity'::VARCHAR,
            'Existing customer with no active opportunities',
            0.7,
            'Identify potential upsell or cross-sell opportunities';
    END IF;

    -- Check support tickets
    SELECT COUNT(*) INTO ticket_count
    FROM support_tickets WHERE customer_id = customer_uuid AND ticket_status IN ('open', 'in_progress');

    IF ticket_count > 0 THEN
        RETURN QUERY SELECT
            'support_issue'::VARCHAR,
            'Customer has ' || ticket_count || ' open support tickets',
            0.9,
            'Follow up on outstanding support issues to ensure satisfaction';
    END IF;

    -- Lifecycle insights
    IF customer_record.lifecycle_stage = 'prospect' AND customer_record.lead_score > 70 THEN
        RETURN QUERY SELECT
            'ready_for_conversion'::VARCHAR,
            'High-scoring prospect ready for conversion',
            0.85,
            'Move prospect to qualified lead status and begin sales process';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample organization
INSERT INTO organizations (
    organization_name, organization_code, industry, company_size,
    subscription_plan, billing_cycle, monthly_fee
) VALUES (
    'TechCorp Solutions', 'TECH001', 'technology', 'medium',
    'professional', 'monthly', 299.99
);

-- Insert sample user
INSERT INTO users (
    organization_id, email, username, first_name, last_name,
    user_role, job_title
) VALUES (
    (SELECT organization_id FROM organizations WHERE organization_code = 'TECH001' LIMIT 1),
    'john.smith@techcorp.com', 'johnsmith', 'John', 'Smith',
    'sales_rep', 'Senior Sales Representative'
);

-- Insert sample customer
INSERT INTO customers (
    organization_id, customer_number, customer_type, first_name, last_name,
    company_name, email, lifecycle_stage, lead_score
) VALUES (
    (SELECT organization_id FROM organizations WHERE organization_code = 'TECH001' LIMIT 1),
    'CUST001', 'business', 'Jane', 'Doe', 'InnovateLabs Inc',
    'jane.doe@innovatelabs.com', 'qualified', 85
);

-- Insert sample opportunity
INSERT INTO opportunities (
    organization_id, customer_id, opportunity_name, sales_stage,
    probability_percentage, estimated_value, assigned_to
) VALUES (
    (SELECT organization_id FROM organizations WHERE organization_code = 'TECH001' LIMIT 1),
    (SELECT customer_id FROM customers WHERE customer_number = 'CUST001' LIMIT 1),
    'Enterprise Software License', 'proposal', 75.00, 50000.00,
    (SELECT user_id FROM users WHERE email = 'john.smith@techcorp.com' LIMIT 1)
);

-- Insert sample support ticket
INSERT INTO support_tickets (
    organization_id, customer_id, ticket_number, ticket_subject,
    ticket_description, ticket_type, ticket_priority, assigned_to
) VALUES (
    (SELECT organization_id FROM organizations WHERE organization_code = 'TECH001' LIMIT 1),
    (SELECT customer_id FROM customers WHERE customer_number = 'CUST001' LIMIT 1),
    'TKT-001', 'Login Issues with New Account',
    'Customer unable to access the new account dashboard', 'technical_support', 'high',
    (SELECT user_id FROM users WHERE email = 'john.smith@techcorp.com' LIMIT 1)
);

-- This CRM schema provides comprehensive infrastructure for customer relationship management,
-- sales automation, support ticketing, and marketing campaign management.
