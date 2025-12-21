-- Marketing & Analytics Database Schema
-- Comprehensive schema for marketing automation, campaign management, analytics, and customer insights

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "postgis"; -- For geo-targeting

-- ===========================================
-- ORGANIZATION AND CAMPAIGN MANAGEMENT
-- ===========================================

CREATE TABLE marketing_organizations (
    organization_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_name VARCHAR(255) NOT NULL,
    organization_code VARCHAR(20) UNIQUE NOT NULL,

    -- Organization Details
    industry VARCHAR(50),
    company_size VARCHAR(20) CHECK (company_size IN ('startup', 'small', 'medium', 'large', 'enterprise')),
    website VARCHAR(500),
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Subscription and Billing
    subscription_plan VARCHAR(20) CHECK (subscription_plan IN ('free', 'starter', 'professional', 'enterprise')),
    monthly_budget DECIMAL(10,2),
    api_rate_limit INTEGER,

    -- Settings
    data_retention_days INTEGER DEFAULT 365,
    gdpr_compliance BOOLEAN DEFAULT TRUE,
    ccpa_compliance BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE campaigns (
    campaign_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES marketing_organizations(organization_id),

    -- Campaign Identity
    campaign_name VARCHAR(255) NOT NULL,
    campaign_code VARCHAR(20) UNIQUE NOT NULL,
    campaign_description TEXT,

    -- Campaign Type and Goals
    campaign_type VARCHAR(30) CHECK (campaign_type IN (
        'email', 'social_media', 'paid_search', 'display_ads', 'content_marketing',
        'influencer', 'affiliate', 'video', 'podcast', 'events', 'webinars'
    )),
    primary_goal VARCHAR(50) CHECK (primary_goal IN (
        'brand_awareness', 'lead_generation', 'sales', 'engagement', 'retention',
        'product_promotion', 'event_registration', 'newsletter_signup'
    )),
    secondary_goals JSONB DEFAULT '[]',

    -- Budget and Spend
    budget_allocated DECIMAL(10,2),
    budget_spent DECIMAL(10,2) DEFAULT 0,
    budget_currency CHAR(3) DEFAULT 'USD',

    -- Targeting
    target_audience JSONB DEFAULT '{}', -- Demographics, interests, behaviors
    geographic_targeting JSONB DEFAULT '[]', -- Countries, regions, cities
    device_targeting JSONB DEFAULT '[]', -- Desktop, mobile, tablet

    -- Creative Assets
    campaign_assets JSONB DEFAULT '[]', -- Images, videos, copy variations

    -- Scheduling
    planned_start_date DATE,
    planned_end_date DATE,
    actual_start_date DATE,
    actual_end_date DATE,

    -- Performance Tracking
    tracking_pixels JSONB DEFAULT '[]', -- Conversion pixels, retargeting
    utm_parameters JSONB DEFAULT '{}', -- UTM tracking parameters

    -- Status and Approval
    campaign_status VARCHAR(20) DEFAULT 'draft' CHECK (campaign_status IN (
        'draft', 'pending_approval', 'approved', 'active', 'paused', 'completed', 'cancelled'
    )),
    approval_required BOOLEAN DEFAULT TRUE,
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (planned_start_date <= planned_end_date),
    CHECK (actual_start_date <= actual_end_date)
);

-- ===========================================
-- AUDIENCE AND SEGMENTATION
-- ===========================================

CREATE TABLE audience_segments (
    segment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES marketing_organizations(organization_id),

    -- Segment Definition
    segment_name VARCHAR(100) NOT NULL,
    segment_description TEXT,
    segment_type VARCHAR(20) CHECK (segment_type IN ('static', 'dynamic', 'lookalike', 'retargeting')),

    -- Segment Criteria
    filter_criteria JSONB DEFAULT '{}', -- Dynamic filter rules
    segment_size INTEGER DEFAULT 0, -- Estimated/actual size

    -- Data Sources
    data_sources JSONB DEFAULT '[]', -- CRM, website, social media, etc.

    -- Segment Health
    last_refreshed TIMESTAMP WITH TIME ZONE,
    refresh_frequency INTERVAL DEFAULT INTERVAL '24 hours',
    segment_health_score DECIMAL(3,1), -- 1-10 scale

    -- Usage Tracking
    campaigns_used_in UUID[], -- Array of campaign IDs
    last_used TIMESTAMP WITH TIME ZONE,

    -- Status
    segment_status VARCHAR(20) DEFAULT 'active' CHECK (segment_status IN ('active', 'inactive', 'archived')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE contacts (
    contact_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES marketing_organizations(organization_id),

    -- Identity and Contact
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),
    first_name VARCHAR(100),
    last_name VARCHAR(100),

    -- Profile Data
    date_of_birth DATE,
    gender VARCHAR(20),
    location JSONB, -- City, state, country, postal code

    -- Marketing Profile
    lead_score DECIMAL(5,2) DEFAULT 0 CHECK (lead_score >= 0 AND lead_score <= 100),
    lifecycle_stage VARCHAR(20) CHECK (lifecycle_stage IN (
        'prospect', 'lead', 'mql', 'sql', 'customer', 'champion', 'churned'
    )),

    -- Preferences and Consent
    email_opt_in BOOLEAN DEFAULT TRUE,
    sms_opt_in BOOLEAN DEFAULT FALSE,
    marketing_consent_given BOOLEAN DEFAULT FALSE,
    consent_date DATE,
    consent_source VARCHAR(50),

    -- Behavioral Data
    first_touch_channel VARCHAR(30),
    last_touch_channel VARCHAR(30),
    total_page_views INTEGER DEFAULT 0,
    total_sessions INTEGER DEFAULT 0,

    -- Financial Data
    lifetime_value DECIMAL(10,2) DEFAULT 0,
    average_order_value DECIMAL(8,2),
    total_orders INTEGER DEFAULT 0,

    -- Segmentation
    segment_memberships UUID[], -- Array of segment IDs
    tags JSONB DEFAULT '[]',

    -- Status and Compliance
    contact_status VARCHAR(20) DEFAULT 'active' CHECK (contact_status IN ('active', 'inactive', 'bounced', 'unsubscribed', 'complaint')),
    gdpr_erased BOOLEAN DEFAULT FALSE,
    last_activity_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE contact_segments (
    contact_id UUID NOT NULL REFERENCES contacts(contact_id),
    segment_id UUID NOT NULL REFERENCES audience_segments(segment_id),

    -- Membership Details
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    added_by VARCHAR(50), -- 'system', 'manual', 'import'
    expiration_date DATE, -- For temporary segments

    PRIMARY KEY (contact_id, segment_id)
);

-- ===========================================
-- CONTENT AND CREATIVE MANAGEMENT
-- ===========================================

CREATE TABLE content_library (
    content_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES marketing_organizations(organization_id),

    -- Content Details
    content_title VARCHAR(255) NOT NULL,
    content_type VARCHAR(30) CHECK (content_type IN (
        'blog_post', 'email', 'landing_page', 'social_post', 'video',
        'infographic', 'whitepaper', 'case_study', 'webinar', 'image', 'document'
    )),
    content_description TEXT,

    -- Content Body
    content_body TEXT,
    content_html TEXT,
    content_json JSONB,

    -- Metadata
    author VARCHAR(100),
    tags JSONB DEFAULT '[]',
    categories JSONB DEFAULT '[]',

    -- SEO and Performance
    seo_title VARCHAR(60),
    seo_description VARCHAR(160),
    seo_keywords TEXT[],
    slug VARCHAR(255) UNIQUE,

    -- Assets
    featured_image_url VARCHAR(500),
    attachments JSONB DEFAULT '[]',

    -- Publishing
    publish_status VARCHAR(20) DEFAULT 'draft' CHECK (publish_status IN ('draft', 'scheduled', 'published', 'archived')),
    published_at TIMESTAMP WITH TIME ZONE,
    scheduled_publish_date TIMESTAMP WITH TIME ZONE,

    -- Performance
    view_count INTEGER DEFAULT 0,
    engagement_score DECIMAL(5,2) DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE email_templates (
    template_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES marketing_organizations(organization_id),

    -- Template Details
    template_name VARCHAR(255) NOT NULL,
    template_category VARCHAR(30) CHECK (template_category IN (
        'welcome', 'newsletter', 'promotional', 'transactional',
        'onboarding', 'reengagement', 'announcement'
    )),
    template_description TEXT,

    -- Template Content
    subject_line VARCHAR(255),
    preheader_text VARCHAR(100),
    template_html TEXT,
    template_json JSONB,

    -- Design Elements
    template_style JSONB DEFAULT '{}', -- Colors, fonts, layout
    brand_assets JSONB DEFAULT '{}', -- Logo, colors, fonts

    -- Dynamic Elements
    merge_fields JSONB DEFAULT '[]', -- Available personalization fields
    dynamic_blocks JSONB DEFAULT '[]', -- Editable content blocks

    -- Testing and Optimization
    ab_test_enabled BOOLEAN DEFAULT FALSE,
    ab_test_variations JSONB DEFAULT '[]',

    -- Status and Usage
    template_status VARCHAR(20) DEFAULT 'active' CHECK (template_status IN ('active', 'inactive', 'archived')),
    usage_count INTEGER DEFAULT 0,
    last_used TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- CAMPAIGN EXECUTION AND DELIVERY
-- ===========================================

CREATE TABLE campaign_sends (
    send_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_id UUID NOT NULL REFERENCES campaigns(campaign_id),

    -- Send Configuration
    send_name VARCHAR(255),
    send_type VARCHAR(20) CHECK (send_type IN ('email', 'sms', 'push', 'social', 'display')),

    -- Recipients
    segment_id UUID REFERENCES audience_segments(segment_id),
    recipient_count INTEGER,
    recipient_list JSONB, -- For small sends or manual lists

    -- Content
    content_id UUID REFERENCES content_library(content_id),
    template_id UUID REFERENCES email_templates(template_id),
    subject_line VARCHAR(255),
    content_body TEXT,

    -- Personalization
    personalization_rules JSONB DEFAULT '{}',

    -- Scheduling
    scheduled_send_time TIMESTAMP WITH TIME ZONE,
    actual_send_time TIMESTAMP WITH TIME ZONE,

    -- Delivery Status
    send_status VARCHAR(20) DEFAULT 'scheduled' CHECK (send_status IN (
        'scheduled', 'sending', 'completed', 'failed', 'cancelled'
    )),
    delivery_progress DECIMAL(5,2) DEFAULT 0, -- Percentage complete

    -- Performance Tracking
    tracking_enabled BOOLEAN DEFAULT TRUE,
    tracking_pixel_url VARCHAR(500),
    unsubscribe_url VARCHAR(500),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE email_deliveries (
    delivery_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    send_id UUID NOT NULL REFERENCES campaign_sends(send_id),
    contact_id UUID NOT NULL REFERENCES contacts(contact_id),

    -- Delivery Details
    message_id VARCHAR(255) UNIQUE, -- SMTP message ID
    recipient_email VARCHAR(255),
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,

    -- Delivery Status
    delivery_status VARCHAR(20) DEFAULT 'sent' CHECK (delivery_status IN (
        'sent', 'delivered', 'bounced', 'complained', 'unsubscribed'
    )),
    bounce_reason VARCHAR(100),
    bounce_type VARCHAR(20) CHECK (bounce_type IN ('hard', 'soft')),

    -- Engagement Tracking
    opened_at TIMESTAMP WITH TIME ZONE,
    open_count INTEGER DEFAULT 0,
    last_open_at TIMESTAMP WITH TIME ZONE,

    -- Click Tracking
    clicked_at TIMESTAMP WITH TIME ZONE,
    click_count INTEGER DEFAULT 0,
    last_click_at TIMESTAMP WITH TIME ZONE,
    clicked_links JSONB DEFAULT '[]',

    -- Device and Location
    user_agent TEXT,
    ip_address INET,
    geo_location JSONB,

    -- Conversion Tracking
    converted BOOLEAN DEFAULT FALSE,
    conversion_type VARCHAR(50),
    conversion_value DECIMAL(8,2),
    converted_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ANALYTICS AND TRACKING
-- ===========================================

CREATE TABLE events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES marketing_organizations(organization_id),

    -- Event Details
    event_type VARCHAR(50) CHECK (event_type IN (
        'page_view', 'form_submission', 'button_click', 'video_play',
        'file_download', 'email_open', 'email_click', 'purchase',
        'lead_created', 'opportunity_created', 'customer_created'
    )),
    event_name VARCHAR(100),

    -- Event Context
    contact_id UUID REFERENCES contacts(contact_id),
    campaign_id UUID REFERENCES campaigns(campaign_id),
    content_id UUID REFERENCES content_library(content_id),

    -- Event Data
    event_data JSONB DEFAULT '{}',
    event_value DECIMAL(8,2),
    event_category VARCHAR(50),

    -- Technical Details
    session_id VARCHAR(255),
    user_agent TEXT,
    ip_address INET,
    geo_location JSONB,

    -- Attribution
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    utm_term VARCHAR(100),
    utm_content VARCHAR(100),

    -- Device and Browser
    device_type VARCHAR(20) CHECK (device_type IN ('desktop', 'mobile', 'tablet')),
    browser VARCHAR(50),
    operating_system VARCHAR(50),

    -- Timing
    event_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (event_timestamp);

-- Create partitions for events (example for 2024)
CREATE TABLE events_2024_01 PARTITION OF events
    FOR VALUES FROM ('2024-01-01 00:00:00') TO ('2024-02-01 00:00:00');

CREATE TABLE campaign_performance (
    performance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_id UUID NOT NULL REFERENCES campaigns(campaign_id),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_hour INTEGER CHECK (report_hour BETWEEN 0 AND 23),

    -- Delivery Metrics
    sent_count INTEGER DEFAULT 0,
    delivered_count INTEGER DEFAULT 0,
    bounced_count INTEGER DEFAULT 0,

    -- Engagement Metrics
    opened_count INTEGER DEFAULT 0,
    unique_opened_count INTEGER DEFAULT 0,
    clicked_count INTEGER DEFAULT 0,
    unique_clicked_count INTEGER DEFAULT 0,

    -- Conversion Metrics
    converted_count INTEGER DEFAULT 0,
    conversion_value DECIMAL(10,2) DEFAULT 0,

    -- Negative Metrics
    unsubscribed_count INTEGER DEFAULT 0,
    complained_count INTEGER DEFAULT 0,

    -- Calculated Rates
    delivery_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN sent_count > 0 THEN (delivered_count::DECIMAL / sent_count) * 100 ELSE 0 END
    ) STORED,
    open_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN delivered_count > 0 THEN (unique_opened_count::DECIMAL / delivered_count) * 100 ELSE 0 END
    ) STORED,
    click_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN delivered_count > 0 THEN (unique_clicked_count::DECIMAL / delivered_count) * 100 ELSE 0 END
    ) STORED,
    conversion_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN unique_clicked_count > 0 THEN (converted_count::DECIMAL / unique_clicked_count) * 100 ELSE 0 END
    ) STORED,

    -- Cost Metrics
    spend DECIMAL(8,2) DEFAULT 0,
    cost_per_acquisition DECIMAL(6,2) GENERATED ALWAYS AS (
        CASE WHEN converted_count > 0 THEN spend / converted_count ELSE 0 END
    ) STORED,
    return_on_ad_spend DECIMAL(6,2) GENERATED ALWAYS AS (
        CASE WHEN spend > 0 THEN conversion_value / spend ELSE 0 END
    ) STORED,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (campaign_id, report_date, report_hour)
);

-- ===========================================
-- ATTRIBUTION AND JOURNEY ANALYSIS
-- =========================================--

CREATE TABLE touchpoints (
    touchpoint_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contact_id UUID NOT NULL REFERENCES contacts(contact_id),
    campaign_id UUID REFERENCES campaigns(campaign_id),

    -- Touchpoint Details
    touchpoint_type VARCHAR(30) CHECK (touchpoint_type IN (
        'email', 'social_media', 'paid_search', 'organic_search',
        'direct', 'referral', 'display_ad', 'video', 'podcast'
    )),
    touchpoint_channel VARCHAR(50),

    -- Timing and Sequence
    touchpoint_date DATE DEFAULT CURRENT_DATE,
    touchpoint_time TIME DEFAULT CURRENT_TIME,
    touchpoint_sequence INTEGER, -- Position in customer journey

    -- Attribution Value
    attribution_model VARCHAR(20) CHECK (attribution_model IN (
        'first_touch', 'last_touch', 'linear', 'time_decay', 'position_based'
    )),
    attributed_value DECIMAL(8,2) DEFAULT 0,

    -- Content and Creative
    content_id UUID REFERENCES content_library(content_id),
    creative_name VARCHAR(100),
    landing_page VARCHAR(500),

    -- Technical Details
    referrer_url VARCHAR(500),
    device_type VARCHAR(20),
    geo_location JSONB,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE conversion_funnels (
    funnel_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES marketing_organizations(organization_id),

    -- Funnel Definition
    funnel_name VARCHAR(255) NOT NULL,
    funnel_description TEXT,
    conversion_goal VARCHAR(50) CHECK (conversion_goal IN (
        'lead', 'customer', 'sale', 'subscription', 'download', 'registration'
    )),

    -- Funnel Steps
    funnel_steps JSONB NOT NULL, -- Array of step definitions with events

    -- Funnel Performance
    total_entrances INTEGER DEFAULT 0,
    total_conversions INTEGER DEFAULT 0,
    conversion_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN total_entrances > 0 THEN (total_conversions::DECIMAL / total_entrances) * 100 ELSE 0 END
    ) STORED,

    -- Time Analysis
    average_time_to_convert INTERVAL,
    funnel_drop_off_points JSONB DEFAULT '{}',

    -- Status
    funnel_status VARCHAR(20) DEFAULT 'active' CHECK (funnel_status IN ('active', 'inactive', 'archived')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Organization and campaign indexes
CREATE INDEX idx_campaigns_organization ON campaigns (organization_id, campaign_status);
CREATE INDEX idx_campaigns_dates ON campaigns (planned_start_date, planned_end_date);
CREATE INDEX idx_campaigns_type ON campaigns (campaign_type, primary_goal);

-- Contact and segment indexes
CREATE INDEX idx_contacts_organization ON contacts (organization_id, contact_status);
CREATE INDEX idx_contacts_email ON contacts (email);
CREATE INDEX idx_contacts_score ON contacts (lead_score DESC);
CREATE INDEX idx_audience_segments_org ON audience_segments (organization_id, segment_status);

-- Content indexes
CREATE INDEX idx_content_library_org ON content_library (organization_id, publish_status);
CREATE INDEX idx_content_library_type ON content_library (content_type, created_at DESC);
CREATE INDEX idx_email_templates_org ON email_templates (organization_id, template_status);

-- Delivery and tracking indexes
CREATE INDEX idx_campaign_sends_campaign ON campaign_sends (campaign_id, send_status);
CREATE INDEX idx_email_deliveries_send ON email_deliveries (send_id, delivery_status);
CREATE INDEX idx_email_deliveries_contact ON email_deliveries (contact_id, sent_at DESC);

-- Analytics indexes
CREATE INDEX idx_events_organization ON events (organization_id, event_timestamp DESC);
CREATE INDEX idx_events_contact ON events (contact_id, event_timestamp DESC);
CREATE INDEX idx_events_type ON events (event_type, event_timestamp);
CREATE INDEX idx_campaign_performance_campaign ON campaign_performance (campaign_id, report_date DESC);

-- Attribution indexes
CREATE INDEX idx_touchpoints_contact ON touchpoints (contact_id, touchpoint_date DESC);
CREATE INDEX idx_touchpoints_campaign ON touchpoints (campaign_id, touchpoint_sequence);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Campaign performance dashboard
CREATE VIEW campaign_performance_dashboard AS
SELECT
    c.campaign_id,
    c.campaign_name,
    c.campaign_type,
    c.campaign_status,
    c.primary_goal,

    -- Budget and spend
    c.budget_allocated,
    c.budget_spent,
    ROUND(c.budget_spent / NULLIF(c.budget_allocated, 0) * 100, 1) as budget_utilization,

    -- Timeline
    c.planned_start_date,
    c.actual_start_date,
    c.planned_end_date,
    c.actual_end_date,

    -- Performance metrics (aggregated)
    SUM(cp.sent_count) as total_sent,
    SUM(cp.delivered_count) as total_delivered,
    ROUND(AVG(cp.delivery_rate), 2) as avg_delivery_rate,
    ROUND(AVG(cp.open_rate), 2) as avg_open_rate,
    ROUND(AVG(cp.click_rate), 2) as avg_click_rate,
    ROUND(AVG(cp.conversion_rate), 2) as avg_conversion_rate,

    -- Engagement totals
    SUM(cp.opened_count) as total_opens,
    SUM(cp.clicked_count) as total_clicks,
    SUM(cp.converted_count) as total_conversions,
    SUM(cp.conversion_value) as total_conversion_value,

    -- Cost metrics
    SUM(cp.spend) as total_spend,
    ROUND(AVG(cp.cost_per_acquisition), 2) as avg_cpa,
    ROUND(AVG(cp.return_on_ad_spend), 2) as avg_roas,

    -- Negative metrics
    SUM(cp.bounced_count) as total_bounces,
    SUM(cp.unsubscribed_count) as total_unsubscribes,
    SUM(cp.complained_count) as total_complaints,

    -- Overall score (weighted)
    ROUND(
        (
            COALESCE(AVG(cp.delivery_rate), 0) * 0.2 +
            COALESCE(AVG(cp.open_rate), 0) * 0.3 +
            COALESCE(AVG(cp.click_rate), 0) * 0.3 +
            COALESCE(AVG(cp.conversion_rate), 0) * 0.2
        ), 2
    ) as overall_performance_score

FROM campaigns c
LEFT JOIN campaign_performance cp ON c.campaign_id = cp.campaign_id
WHERE c.campaign_status IN ('active', 'completed')
GROUP BY c.campaign_id, c.campaign_name, c.campaign_type, c.campaign_status,
         c.primary_goal, c.budget_allocated, c.budget_spent,
         c.planned_start_date, c.actual_start_date, c.planned_end_date, c.actual_end_date;

-- Customer journey analysis
CREATE VIEW customer_journey_analysis AS
SELECT
    c.contact_id,
    c.first_name || ' ' || c.last_name as customer_name,
    c.email,
    c.lifecycle_stage,
    c.lead_score,

    -- Journey metrics
    COUNT(t.touchpoint_id) as total_touchpoints,
    MIN(t.touchpoint_date) as first_touch_date,
    MAX(t.touchpoint_date) as last_touch_date,
    MAX(t.touchpoint_sequence) as journey_length,

    -- Channel mix
    COUNT(CASE WHEN t.touchpoint_type = 'email' THEN 1 END) as email_touchpoints,
    COUNT(CASE WHEN t.touchpoint_type = 'social_media' THEN 1 END) as social_touchpoints,
    COUNT(CASE WHEN t.touchpoint_type = 'paid_search' THEN 1 END) as paid_search_touchpoints,
    COUNT(CASE WHEN t.touchpoint_type = 'organic_search' THEN 1 END) as organic_search_touchpoints,

    -- Attribution
    SUM(t.attributed_value) as total_attributed_value,
    STRING_AGG(DISTINCT t.touchpoint_channel, ', ') as touchpoint_channels,

    -- Conversion path
    STRING_AGG(
        t.touchpoint_type || ':' || t.touchpoint_sequence::TEXT,
        ' -> ' ORDER BY t.touchpoint_sequence
    ) as conversion_path,

    -- Journey health
    CASE
        WHEN c.lifecycle_stage = 'customer' AND COUNT(t.touchpoint_id) > 10 THEN 'high_engagement'
        WHEN c.lifecycle_stage IN ('lead', 'mql', 'sql') AND COUNT(t.touchpoint_id) > 5 THEN 'good_progression'
        WHEN c.lifecycle_stage = 'prospect' AND COUNT(t.touchpoint_id) > 2 THEN 'early_engagement'
        WHEN COUNT(t.touchpoint_id) = 0 THEN 'no_engagement'
        ELSE 'low_engagement'
    END as journey_health

FROM contacts c
LEFT JOIN touchpoints t ON c.contact_id = t.contact_id
WHERE c.contact_status = 'active'
GROUP BY c.contact_id, c.first_name, c.last_name, c.email, c.lifecycle_stage, c.lead_score;

-- Content performance analysis
CREATE VIEW content_performance_analysis AS
SELECT
    cl.content_id,
    cl.content_title,
    cl.content_type,
    cl.publish_status,
    cl.published_at,

    -- Engagement metrics
    cl.view_count,
    cl.engagement_score,

    -- Event analysis
    COUNT(CASE WHEN e.event_type = 'page_view' THEN 1 END) as page_views,
    COUNT(CASE WHEN e.event_type = 'button_click' THEN 1 END) as button_clicks,
    COUNT(CASE WHEN e.event_type = 'form_submission' THEN 1 END) as form_submissions,
    COUNT(CASE WHEN e.event_type = 'video_play' THEN 1 END) as video_plays,

    -- Conversion metrics
    COUNT(CASE WHEN e.event_type IN ('lead_created', 'customer_created', 'purchase') THEN 1 END) as conversions,
    SUM(CASE WHEN e.event_type IN ('lead_created', 'customer_created', 'purchase') THEN e.event_value END) as conversion_value,

    -- Performance ratios
    ROUND(
        COUNT(CASE WHEN e.event_type = 'button_click' THEN 1 END)::DECIMAL /
        NULLIF(COUNT(CASE WHEN e.event_type = 'page_view' THEN 1 END), 0) * 100, 2
    ) as click_through_rate,

    ROUND(
        COUNT(CASE WHEN e.event_type IN ('lead_created', 'customer_created', 'purchase') THEN 1 END)::DECIMAL /
        NULLIF(COUNT(CASE WHEN e.event_type = 'page_view' THEN 1 END), 0) * 100, 2
    ) as conversion_rate,

    -- Time-based analysis
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - cl.published_at)) / 86400 as days_since_publish,

    ROUND(
        COUNT(CASE WHEN e.event_type = 'page_view' THEN 1 END)::DECIMAL /
        NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - cl.published_at)) / 86400, 0), 2
    ) as avg_daily_views

FROM content_library cl
LEFT JOIN events e ON cl.content_id = e.content_id
WHERE cl.publish_status = 'published'
GROUP BY cl.content_id, cl.content_title, cl.content_type, cl.publish_status, cl.published_at, cl.view_count, cl.engagement_score;

-- ===========================================
-- FUNCTIONS FOR MARKETING OPERATIONS
-- =========================================--

-- Function to calculate campaign ROI
CREATE OR REPLACE FUNCTION calculate_campaign_roi(campaign_uuid UUID)
RETURNS TABLE (
    campaign_name VARCHAR,
    total_spend DECIMAL,
    total_revenue DECIMAL,
    gross_profit DECIMAL,
    roi_percentage DECIMAL,
    payback_period_days INTEGER,
    roi_category VARCHAR
) AS $$
DECLARE
    campaign_record campaigns%ROWTYPE;
    total_revenue DECIMAL := 0;
    total_spend DECIMAL := 0;
    gross_profit DECIMAL := 0;
    roi_pct DECIMAL := 0;
    payback_days INTEGER := 0;
BEGIN
    -- Get campaign details
    SELECT * INTO campaign_record FROM campaigns WHERE campaign_id = campaign_uuid;

    -- Calculate total spend
    total_spend := campaign_record.budget_spent;

    -- Calculate revenue from campaign performance
    SELECT COALESCE(SUM(conversion_value), 0) INTO total_revenue
    FROM campaign_performance WHERE campaign_id = campaign_uuid;

    -- Calculate gross profit (simplified - no cost of goods)
    gross_profit := total_revenue - total_spend;

    -- Calculate ROI
    IF total_spend > 0 THEN
        roi_pct := (gross_profit / total_spend) * 100;
    END IF;

    -- Calculate payback period (simplified daily spend)
    IF total_spend > 0 AND campaign_record.actual_end_date IS NOT NULL AND campaign_record.actual_start_date IS NOT NULL THEN
        payback_days := EXTRACT(EPOCH FROM (campaign_record.actual_end_date - campaign_record.actual_start_date)) / 86400;
    END IF;

    RETURN QUERY SELECT
        campaign_record.campaign_name,
        total_spend,
        total_revenue,
        gross_profit,
        ROUND(roi_pct, 2),
        payback_days,
        CASE
            WHEN roi_pct >= 200 THEN 'excellent'
            WHEN roi_pct >= 100 THEN 'good'
            WHEN roi_pct >= 0 THEN 'break_even'
            WHEN roi_pct >= -50 THEN 'concerning'
            ELSE 'poor'
        END;
END;
$$ LANGUAGE plpgsql;

-- Function to generate personalized content recommendations
CREATE OR REPLACE FUNCTION recommend_content_for_contact(contact_uuid UUID, max_recommendations INTEGER DEFAULT 5)
RETURNS TABLE (
    content_id UUID,
    content_title VARCHAR,
    content_type VARCHAR,
    relevance_score DECIMAL,
    recommendation_reason VARCHAR
) AS $$
DECLARE
    contact_record contacts%ROWTYPE;
    contact_segments UUID[];
    contact_tags JSONB;
BEGIN
    -- Get contact details
    SELECT * INTO contact_record FROM contacts WHERE contact_id = contact_uuid;

    -- Get contact segments and tags
    SELECT array_agg(segment_id), tags INTO contact_segments, contact_tags
    FROM contacts c
    LEFT JOIN contact_segments cs ON c.contact_id = cs.contact_id
    WHERE c.contact_id = contact_uuid
    GROUP BY c.tags;

    RETURN QUERY
    SELECT
        cl.content_id,
        cl.content_title,
        cl.content_type,

        -- Calculate relevance score based on various factors
        ROUND(
            (
                -- Lifecycle stage relevance
                CASE
                    WHEN cl.tags ? contact_record.lifecycle_stage THEN 0.4
                    WHEN cl.categories ? contact_record.lifecycle_stage THEN 0.3
                    ELSE 0.1
                END +
                -- Tag matching
                CASE WHEN cl.tags ?| (SELECT array_agg(value) FROM jsonb_array_elements_text(contact_tags)) THEN 0.3 ELSE 0 END +
                -- Segment relevance
                CASE WHEN cl.content_id IN (
                    SELECT content_id FROM content_segment_associations
                    WHERE segment_id = ANY(contact_segments)
                ) THEN 0.3 ELSE 0 END +
                -- Engagement history
                CASE WHEN EXISTS (
                    SELECT 1 FROM events e
                    WHERE e.contact_id = contact_uuid
                      AND e.content_id = cl.content_id
                      AND e.event_type IN ('page_view', 'button_click')
                ) THEN 0.2 ELSE 0 END
            ), 2
        ) as relevance_score,

        -- Recommendation reason
        CASE
            WHEN cl.tags ? contact_record.lifecycle_stage THEN 'Matches your lifecycle stage'
            WHEN cl.categories ? contact_record.lifecycle_stage THEN 'Relevant to your interests'
            WHEN cl.content_id IN (
                SELECT content_id FROM content_segment_associations
                WHERE segment_id = ANY(contact_segments)
            ) THEN 'Personalized for your segment'
            WHEN EXISTS (
                SELECT 1 FROM events e
                WHERE e.contact_id = contact_uuid
                  AND e.content_id = cl.content_id
            ) THEN 'Based on your previous engagement'
            ELSE 'Popular content'
        END as recommendation_reason

    FROM content_library cl
    WHERE cl.publish_status = 'published'
      AND cl.content_type IN ('blog_post', 'email', 'landing_page', 'whitepaper')
    ORDER BY relevance_score DESC, cl.engagement_score DESC
    LIMIT max_recommendations;
END;
$$ LANGUAGE plpgsql;

-- Function to optimize campaign budget allocation
CREATE OR REPLACE FUNCTION optimize_campaign_budget(organization_uuid UUID, total_budget DECIMAL, time_horizon_days INTEGER DEFAULT 30)
RETURNS TABLE (
    campaign_id UUID,
    campaign_name VARCHAR,
    recommended_budget DECIMAL,
    expected_conversions INTEGER,
    expected_roi DECIMAL,
    optimization_reason VARCHAR
) AS $$
DECLARE
    campaign_record RECORD;
    total_historical_conversions INTEGER := 0;
    total_historical_spend DECIMAL := 0;
BEGIN
    -- Get historical performance data
    SELECT
        SUM(cp.converted_count) as total_conversions,
        SUM(cp.spend) as total_spend
    INTO total_historical_conversions, total_historical_spend
    FROM campaigns c
    JOIN campaign_performance cp ON c.campaign_id = cp.campaign_id
    WHERE c.organization_id = organization_uuid
      AND c.campaign_status = 'completed'
      AND cp.report_date >= CURRENT_DATE - INTERVAL '90 days';

    FOR campaign_record IN
        SELECT
            c.campaign_id,
            c.campaign_name,
            c.campaign_type,
            c.primary_goal,
            AVG(cp.conversion_rate) as avg_conversion_rate,
            AVG(cp.return_on_ad_spend) as avg_roas,
            SUM(cp.converted_count) as historical_conversions,
            SUM(cp.spend) as historical_spend
        FROM campaigns c
        LEFT JOIN campaign_performance cp ON c.campaign_id = cp.campaign_id
        WHERE c.organization_id = organization_uuid
          AND c.campaign_status IN ('active', 'draft')
        GROUP BY c.campaign_id, c.campaign_name, c.campaign_type, c.primary_goal
    LOOP
        RETURN QUERY SELECT
            campaign_record.campaign_id,
            campaign_record.campaign_name,

            -- Recommended budget allocation
            CASE
                WHEN campaign_record.avg_roas > 2.0 THEN total_budget * 0.25 -- High ROI campaigns get more
                WHEN campaign_record.avg_roas > 1.5 THEN total_budget * 0.20
                WHEN campaign_record.avg_roas > 1.0 THEN total_budget * 0.15
                ELSE total_budget * 0.10 -- Low ROI campaigns get less
            END as recommended_budget,

            -- Expected conversions based on historical performance
            CASE
                WHEN campaign_record.historical_spend > 0 THEN
                    ROUND((campaign_record.historical_conversions / campaign_record.historical_spend) *
                          CASE
                              WHEN campaign_record.avg_roas > 2.0 THEN total_budget * 0.25
                              WHEN campaign_record.avg_roas > 1.5 THEN total_budget * 0.20
                              WHEN campaign_record.avg_roas > 1.0 THEN total_budget * 0.15
                              ELSE total_budget * 0.10
                          END)
                ELSE 0
            END as expected_conversions,

            -- Expected ROI
            COALESCE(campaign_record.avg_roas, 1.0) as expected_roi,

            -- Optimization reasoning
            CASE
                WHEN campaign_record.avg_roas > 2.0 THEN 'High historical ROI - allocate more budget'
                WHEN campaign_record.avg_roas > 1.5 THEN 'Good historical ROI - maintain allocation'
                WHEN campaign_record.avg_roas > 1.0 THEN 'Moderate ROI - monitor closely'
                WHEN campaign_record.avg_roas IS NULL THEN 'New campaign - conservative allocation'
                ELSE 'Low ROI - reduce allocation and optimize'
            END as optimization_reason;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample organization
INSERT INTO marketing_organizations (
    organization_name, organization_code, industry,
    subscription_plan, monthly_budget
) VALUES (
    'TechGrowth Inc', 'TGI001', 'technology',
    'professional', 50000.00
);

-- Insert sample campaign
INSERT INTO campaigns (
    organization_id, campaign_name, campaign_code,
    campaign_type, primary_goal, budget_allocated,
    planned_start_date, planned_end_date, target_audience
) VALUES (
    (SELECT organization_id FROM marketing_organizations WHERE organization_code = 'TGI001' LIMIT 1),
    'Q1 Product Launch Campaign', 'Q1PLAUNCH',
    'email', 'lead_generation', 15000.00,
    '2024-01-01', '2024-03-31',
    '{"industry": ["technology", "software"], "job_title": ["CTO", "VP Engineering", "Director IT"]}'
);

-- Insert sample audience segment
INSERT INTO audience_segments (
    organization_id, segment_name, segment_description,
    segment_type, filter_criteria, segment_size
) VALUES (
    (SELECT organization_id FROM marketing_organizations WHERE organization_code = 'TGI001' LIMIT 1),
    'Enterprise Tech Decision Makers', 'CTO, CIO, and IT Directors at companies with 500+ employees',
    'dynamic', '{"company_size": ["large", "enterprise"], "job_title": ["CTO", "CIO", "Director IT", "VP Technology"]}',
    2500
);

-- Insert sample contact
INSERT INTO contacts (
    organization_id, email, first_name, last_name,
    lifecycle_stage, lead_score, location, tags
) VALUES (
    (SELECT organization_id FROM marketing_organizations WHERE organization_code = 'TGI001' LIMIT 1),
    'sarah.johnson@techcorp.com', 'Sarah', 'Johnson',
    'mql', 78.5, '{"city": "San Francisco", "state": "CA", "country": "USA"}',
    '["enterprise", "technology", "decision_maker"]'
);

-- Insert sample content
INSERT INTO content_library (
    organization_id, content_title, content_type,
    content_description, author, publish_status,
    seo_title, seo_description, tags
) VALUES (
    (SELECT organization_id FROM marketing_organizations WHERE organization_code = 'TGI001' LIMIT 1),
    'The Future of Enterprise Software', 'blog_post',
    'Exploring emerging trends in enterprise software development', 'Marketing Team', 'published',
    'Future of Enterprise Software | TechGrowth', 'Discover the latest trends shaping enterprise software development and deployment',
    '["enterprise", "software", "technology", "trends"]'
);

-- Insert sample event (page view)
INSERT INTO events (
    organization_id, contact_id, event_type,
    event_data, utm_campaign, device_type, geo_location
) VALUES (
    (SELECT organization_id FROM marketing_organizations WHERE organization_code = 'TGI001' LIMIT 1),
    (SELECT contact_id FROM contacts WHERE email = 'sarah.johnson@techcorp.com' LIMIT 1),
    'page_view',
    '{"page_url": "/blog/future-enterprise-software", "page_title": "The Future of Enterprise Software", "time_on_page": 180}',
    'Q1PLAUNCH', 'desktop',
    '{"city": "San Francisco", "region": "CA", "country": "US"}'
);

-- This marketing analytics schema provides comprehensive infrastructure for campaign management,
-- audience segmentation, content marketing, and performance analytics.
