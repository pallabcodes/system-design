-- Social Media Industry Database Schema Design
-- Comprehensive PostgreSQL schema for social media platforms including posts,
-- relationships, content moderation, analytics, and real-time features

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text search
CREATE EXTENSION IF NOT EXISTS "ltree";    -- For hierarchical comment threads

-- ===========================================
-- USER MANAGEMENT
-- ===========================================

-- Core user accounts
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(30) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    email_verified BOOLEAN DEFAULT FALSE,

    -- Profile Information
    display_name VARCHAR(50),
    bio TEXT,
    website VARCHAR(255),
    avatar_url VARCHAR(500),
    cover_photo_url VARCHAR(500),

    -- Demographics (optional)
    date_of_birth DATE,
    gender VARCHAR(20),
    location VARCHAR(100),
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Account Settings
    is_private BOOLEAN DEFAULT FALSE,
    allow_messages BOOLEAN DEFAULT TRUE,
    email_notifications BOOLEAN DEFAULT TRUE,
    push_notifications BOOLEAN DEFAULT TRUE,

    -- Account Status
    account_status VARCHAR(20) DEFAULT 'active'
        CHECK (account_status IN ('active', 'suspended', 'deactivated', 'banned')),
    suspension_reason TEXT,
    suspension_until TIMESTAMP WITH TIME ZONE,

    -- Verification and Badges
    is_verified BOOLEAN DEFAULT FALSE,
    badges TEXT[],  -- Array of earned badges

    -- Activity Tracking
    last_login_at TIMESTAMP WITH TIME ZONE,
    last_active_at TIMESTAMP WITH TIME ZONE,
    registration_ip INET,
    current_ip INET,

    -- Security
    password_hash VARCHAR(255),
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret VARCHAR(100),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User preferences and privacy settings
CREATE TABLE user_preferences (
    preference_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,

    -- Privacy Settings
    profile_visibility VARCHAR(20) DEFAULT 'public'
        CHECK (profile_visibility IN ('public', 'friends', 'private')),
    posts_visibility VARCHAR(20) DEFAULT 'public'
        CHECK (posts_visibility IN ('public', 'friends', 'private')),
    online_status_visibility VARCHAR(20) DEFAULT 'public'
        CHECK (online_status_visibility IN ('public', 'friends', 'private')),

    -- Content Preferences
    content_filter_level VARCHAR(20) DEFAULT 'moderate'
        CHECK (content_filter_level IN ('strict', 'moderate', 'lenient')),
    blocked_words TEXT[],
    muted_users UUID[],

    -- Notification Preferences
    notify_on_like BOOLEAN DEFAULT TRUE,
    notify_on_comment BOOLEAN DEFAULT TRUE,
    notify_on_follow BOOLEAN DEFAULT TRUE,
    notify_on_message BOOLEAN DEFAULT TRUE,
    notify_on_mention BOOLEAN DEFAULT TRUE,

    -- Language and Localization
    preferred_language VARCHAR(10) DEFAULT 'en',
    content_languages TEXT[] DEFAULT ARRAY['en'],

    UNIQUE (user_id)
);

-- ===========================================
-- CONTENT MANAGEMENT
-- ===========================================

-- Posts (main content type)
CREATE TABLE posts (
    post_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    author_id UUID NOT NULL REFERENCES users(user_id),

    -- Content
    content_type VARCHAR(20) DEFAULT 'text'
        CHECK (content_type IN ('text', 'image', 'video', 'link', 'poll', 'event')),
    title VARCHAR(300),
    content TEXT,
    content_url VARCHAR(1000),  -- For links, videos, etc.

    -- Media Attachments
    media_attachments JSONB,  -- Array of media objects with URLs, types, etc.

    -- Post Settings
    visibility VARCHAR(20) DEFAULT 'public'
        CHECK (visibility IN ('public', 'friends', 'private', 'unlisted')),
    allow_comments BOOLEAN DEFAULT TRUE,
    allow_sharing BOOLEAN DEFAULT TRUE,

    -- Location and Context
    location_name VARCHAR(255),
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    place_id VARCHAR(100),

    -- Tags and Categories
    hashtags TEXT[],
    mentions UUID[],  -- Array of mentioned user IDs
    categories VARCHAR(50)[],
    mood VARCHAR(50),

    -- Engagement Metrics (denormalized for performance)
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    view_count INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Status
    post_status VARCHAR(20) DEFAULT 'published'
        CHECK (post_status IN ('draft', 'scheduled', 'published', 'archived', 'deleted')),

    -- Scheduling
    scheduled_for TIMESTAMP WITH TIME ZONE,

    -- Audit
    edited_at TIMESTAMP WITH TIME ZONE,
    edited_by UUID REFERENCES users(user_id),

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(content, ''))
    ) STORED
);

-- Post metadata (additional structured data)
CREATE TABLE post_metadata (
    metadata_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,

    -- Poll data
    poll_options JSONB,
    poll_expires_at TIMESTAMP WITH TIME ZONE,
    poll_multiple_choice BOOLEAN DEFAULT FALSE,

    -- Event data
    event_start_time TIMESTAMP WITH TIME ZONE,
    event_end_time TIMESTAMP WITH TIME ZONE,
    event_location VARCHAR(255),
    event_max_attendees INTEGER,
    event_rsvp_required BOOLEAN DEFAULT FALSE,

    -- Link preview data
    link_title VARCHAR(300),
    link_description TEXT,
    link_image_url VARCHAR(500),
    link_domain VARCHAR(100),

    -- Video/Audio metadata
    duration_seconds INTEGER,
    video_resolution VARCHAR(20),
    file_size_bytes BIGINT,
    encoding_format VARCHAR(50),

    -- SEO and Analytics
    seo_title VARCHAR(60),
    seo_description VARCHAR(160),
    meta_tags JSONB,

    UNIQUE (post_id)
);

-- ===========================================
-- SOCIAL INTERACTIONS
-- ===========================================

-- User relationships (follows, friendships)
CREATE TABLE user_relationships (
    relationship_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    follower_id UUID NOT NULL REFERENCES users(user_id),
    followed_id UUID NOT NULL REFERENCES users(user_id),

    -- Relationship Type
    relationship_type VARCHAR(20) DEFAULT 'follow'
        CHECK (relationship_type IN ('follow', 'friend_request', 'friend', 'block', 'mute')),

    -- Status
    status VARCHAR(20) DEFAULT 'active'
        CHECK (status IN ('pending', 'accepted', 'active', 'blocked', 'muted')),
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    accepted_at TIMESTAMP WITH TIME ZONE,

    -- Friendship-specific fields
    friendship_level INTEGER DEFAULT 1 CHECK (friendship_level BETWEEN 1 AND 10),
    nickname VARCHAR(50),  -- Friend-specific nickname

    -- Block/Mute metadata
    blocked_reason TEXT,
    muted_until TIMESTAMP WITH TIME ZONE,

    -- Ensure consistent ordering
    CHECK (follower_id < followed_id),

    UNIQUE (follower_id, followed_id)
);

-- Likes and reactions
CREATE TABLE post_reactions (
    reaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(user_id),

    -- Reaction Type
    reaction_type VARCHAR(20) DEFAULT 'like'
        CHECK (reaction_type IN ('like', 'love', 'laugh', 'angry', 'sad', 'wow')),

    -- Context
    reacted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    reaction_weight INTEGER DEFAULT 1,  -- For algorithmic scoring

    -- Device and session info
    device_info JSONB,
    ip_address INET,

    UNIQUE (post_id, user_id)
);

-- Comments and replies (hierarchical)
CREATE TABLE comments (
    comment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(user_id),

    -- Comment Content
    content TEXT NOT NULL,
    content_type VARCHAR(20) DEFAULT 'text'
        CHECK (content_type IN ('text', 'image', 'gif', 'sticker')),

    -- Thread Structure (using ltree for hierarchical queries)
    thread_path LTREE NOT NULL,
    parent_comment_id UUID REFERENCES comments(comment_id),
    depth INTEGER DEFAULT 0 CHECK (depth >= 0),

    -- Engagement
    like_count INTEGER DEFAULT 0,
    reply_count INTEGER DEFAULT 0,
    is_pinned BOOLEAN DEFAULT FALSE,

    -- Status
    comment_status VARCHAR(20) DEFAULT 'published'
        CHECK (comment_status IN ('published', 'pending_moderation', 'deleted', 'hidden')),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    edited_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE,

    -- Moderation
    moderated_by UUID REFERENCES users(user_id),
    moderation_reason TEXT,
    moderation_action VARCHAR(20),

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
);

-- Shares and reposts
CREATE TABLE post_shares (
    share_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    original_post_id UUID NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    sharer_id UUID NOT NULL REFERENCES users(user_id),

    -- Share Content
    share_type VARCHAR(20) DEFAULT 'repost'
        CHECK (share_type IN ('repost', 'quote', 'share_link')),
    quote_text TEXT,

    -- Share Settings
    visibility VARCHAR(20) DEFAULT 'public'
        CHECK (visibility IN ('public', 'friends', 'private')),

    -- Engagement (denormalized)
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Creates a new post entry for the share
    associated_post_id UUID REFERENCES posts(post_id)
);

-- ===========================================
-- MESSAGING SYSTEM
-- ===========================================

-- Conversations (chat threads)
CREATE TABLE conversations (
    conversation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Conversation Type
    conversation_type VARCHAR(20) DEFAULT 'direct'
        CHECK (conversation_type IN ('direct', 'group', 'channel')),

    -- Participants
    participant_ids UUID[] NOT NULL,
    participant_count INTEGER GENERATED ALWAYS AS (array_length(participant_ids, 1)) STORED,

    -- Group/Channel Settings
    conversation_name VARCHAR(100),
    description TEXT,
    avatar_url VARCHAR(500),
    is_private BOOLEAN DEFAULT TRUE,

    -- Group Management
    created_by UUID NOT NULL REFERENCES users(user_id),
    admin_ids UUID[],

    -- Last Activity
    last_message_at TIMESTAMP WITH TIME ZONE,
    last_message_preview TEXT,
    last_message_sender_id UUID REFERENCES users(user_id),

    -- Settings
    message_retention_days INTEGER DEFAULT 365,
    allow_file_sharing BOOLEAN DEFAULT TRUE,
    allow_voice_messages BOOLEAN DEFAULT TRUE,

    -- Status
    conversation_status VARCHAR(20) DEFAULT 'active'
        CHECK (conversation_status IN ('active', 'archived', 'deleted')),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Messages
CREATE TABLE messages (
    message_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(conversation_id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(user_id),

    -- Message Content
    message_type VARCHAR(20) DEFAULT 'text'
        CHECK (message_type IN ('text', 'image', 'video', 'file', 'voice', 'sticker', 'location')),
    content TEXT,
    media_url VARCHAR(1000),
    media_metadata JSONB,

    -- Message Status
    message_status VARCHAR(20) DEFAULT 'sent'
        CHECK (message_status IN ('sending', 'sent', 'delivered', 'read', 'failed')),

    -- Delivery Tracking
    delivered_at TIMESTAMP WITH TIME ZONE,
    read_at TIMESTAMP WITH TIME ZONE,
    read_by UUID[],  -- Array of users who have read the message

    -- Threading (for replies)
    reply_to_message_id UUID REFERENCES messages(message_id),

    -- Reactions
    reactions JSONB,  -- { "user_id": "reaction_type", ... }

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    edited_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE,

    -- Moderation
    moderated BOOLEAN DEFAULT FALSE,
    moderation_reason TEXT,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', COALESCE(content, ''))) STORED
);

-- ===========================================
-- CONTENT MODERATION
-- ===========================================

-- Content reports
CREATE TABLE content_reports (
    report_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES users(user_id),

    -- Reported Content
    content_type VARCHAR(20) NOT NULL
        CHECK (content_type IN ('post', 'comment', 'message', 'user_profile')),
    content_id UUID NOT NULL,  -- References posts, comments, messages, or users
    reported_user_id UUID REFERENCES users(user_id),

    -- Report Details
    report_category VARCHAR(50) NOT NULL
        CHECK (report_category IN ('spam', 'harassment', 'hate_speech', 'violence', 'nudity', 'copyright', 'impersonation', 'other')),
    report_description TEXT,
    severity_level VARCHAR(10) DEFAULT 'medium'
        CHECK (severity_level IN ('low', 'medium', 'high', 'critical')),

    -- Evidence
    evidence_urls TEXT[],
    additional_context TEXT,

    -- Investigation
    investigation_status VARCHAR(20) DEFAULT 'pending'
        CHECK (investigation_status IN ('pending', 'investigating', 'resolved', 'dismissed')),
    investigated_by UUID REFERENCES users(user_id),
    investigated_at TIMESTAMP WITH TIME ZONE,
    investigation_notes TEXT,

    -- Resolution
    resolution_action VARCHAR(50),
    resolution_details TEXT,
    resolved_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Moderation queue
CREATE TABLE moderation_queue (
    queue_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_type VARCHAR(20) NOT NULL,
    content_id UUID NOT NULL,

    -- Moderation Details
    moderation_reason TEXT,
    flagged_by VARCHAR(50),  -- 'automated_system', 'user_report', 'admin_review'
    risk_score DECIMAL(3,2) CHECK (risk_score BETWEEN 0 AND 1),

    -- Queue Management
    priority INTEGER DEFAULT 1 CHECK (priority BETWEEN 1 AND 10),
    assigned_moderator UUID REFERENCES users(user_id),
    assigned_at TIMESTAMP WITH TIME ZONE,

    -- Status
    queue_status VARCHAR(20) DEFAULT 'pending'
        CHECK (queue_status IN ('pending', 'in_review', 'approved', 'rejected', 'escalated')),

    -- Resolution
    moderator_action VARCHAR(50),
    moderator_notes TEXT,
    resolved_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Content filters and rules
CREATE TABLE content_filters (
    filter_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Filter Definition
    filter_name VARCHAR(100) NOT NULL,
    filter_type VARCHAR(20) NOT NULL
        CHECK (filter_type IN ('keyword', 'pattern', 'image_hash', 'behavioral')),

    -- Filter Rules
    keywords TEXT[],
    regex_pattern VARCHAR(500),
    image_hashes TEXT[],
    behavioral_rules JSONB,

    -- Filter Settings
    action VARCHAR(20) DEFAULT 'flag'
        CHECK (action IN ('allow', 'flag', 'block', 'quarantine')),
    severity_score INTEGER DEFAULT 1 CHECK (severity_score BETWEEN 1 AND 10),

    -- Scope
    applies_to TEXT[] DEFAULT ARRAY['posts', 'comments', 'messages'],
    user_groups TEXT[] DEFAULT ARRAY['all'],

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES users(user_id),

    -- Effectiveness Tracking
    trigger_count INTEGER DEFAULT 0,
    false_positive_count INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ANALYTICS AND INSIGHTS
-- ===========================================

-- Content engagement analytics
CREATE TABLE content_analytics (
    analytic_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_type VARCHAR(20) NOT NULL,
    content_id UUID NOT NULL,

    -- Time Period
    date_recorded DATE DEFAULT CURRENT_DATE,
    hour_recorded INTEGER CHECK (hour_recorded BETWEEN 0 AND 23),

    -- Engagement Metrics
    view_count INTEGER DEFAULT 0,
    unique_viewer_count INTEGER DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    save_count INTEGER DEFAULT 0,

    -- Interaction Details
    reaction_breakdown JSONB,  -- Count by reaction type
    top_referrers JSONB,       -- Traffic sources
    geographic_data JSONB,     -- Views by country/region

    -- Content Performance
    average_view_duration_seconds DECIMAL(8,2),
    bounce_rate DECIMAL(5,2),
    completion_rate DECIMAL(5,2),  -- For videos

    -- Social Metrics
    viral_coefficient DECIMAL(4,2),  -- Average shares per view
    conversation_rate DECIMAL(5,2),  -- Comments per view

    -- Technical Metrics
    load_time_ms DECIMAL(8,2),
    error_count INTEGER DEFAULT 0,

    UNIQUE (content_type, content_id, date_recorded, hour_recorded)
) PARTITION BY RANGE (date_recorded);

-- User activity analytics
CREATE TABLE user_activity_analytics (
    analytic_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id),

    -- Time Period
    date_recorded DATE DEFAULT CURRENT_DATE,

    -- Activity Metrics
    posts_created INTEGER DEFAULT 0,
    comments_made INTEGER DEFAULT 0,
    messages_sent INTEGER DEFAULT 0,
    likes_given INTEGER DEFAULT 0,
    follows_made INTEGER DEFAULT 0,

    -- Engagement Metrics
    content_viewed INTEGER DEFAULT 0,
    time_spent_minutes DECIMAL(8,2),
    sessions_count INTEGER DEFAULT 0,
    average_session_length DECIMAL(8,2),

    -- Social Metrics
    followers_gained INTEGER DEFAULT 0,
    followers_lost INTEGER DEFAULT 0,
    current_follower_count INTEGER,

    -- Content Consumption
    feed_scroll_depth DECIMAL(5,2),  -- Percentage of feed viewed
    top_content_categories TEXT[],
    preferred_content_types TEXT[],

    -- Device and Platform
    primary_device_type VARCHAR(20),
    primary_platform VARCHAR(20),
    app_version VARCHAR(20),

    UNIQUE (user_id, date_recorded)
) PARTITION BY RANGE (date_recorded);

-- Platform analytics
CREATE TABLE platform_analytics (
    analytic_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Time Period
    date_recorded DATE DEFAULT CURRENT_DATE,
    hour_recorded INTEGER CHECK (hour_recorded BETWEEN 0 AND 23),

    -- User Metrics
    active_users INTEGER DEFAULT 0,
    new_registrations INTEGER DEFAULT 0,
    total_users INTEGER,

    -- Content Metrics
    posts_created INTEGER DEFAULT 0,
    comments_made INTEGER DEFAULT 0,
    messages_sent INTEGER DEFAULT 0,

    -- Engagement Metrics
    total_views BIGINT DEFAULT 0,
    total_likes BIGINT DEFAULT 0,
    total_shares BIGINT DEFAULT 0,

    -- Technical Metrics
    api_response_time_ms DECIMAL(8,2),
    error_rate DECIMAL(5,2),
    server_uptime_percentage DECIMAL(5,2),

    -- Geographic Data
    top_countries JSONB,
    user_distribution JSONB,

    -- Content Moderation
    reports_received INTEGER DEFAULT 0,
    content_moderated INTEGER DEFAULT 0,
    automoderation_accuracy DECIMAL(5,2),

    UNIQUE (date_recorded, hour_recorded)
) PARTITION BY RANGE (date_recorded);

-- ===========================================
-- NOTIFICATIONS SYSTEM
-- ===========================================

-- Notification templates
CREATE TABLE notification_templates (
    template_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    template_name VARCHAR(100) UNIQUE NOT NULL,

    -- Template Content
    title_template TEXT NOT NULL,
    body_template TEXT NOT NULL,
    action_url_template TEXT,

    -- Template Type
    notification_type VARCHAR(30) NOT NULL
        CHECK (notification_type IN ('like', 'comment', 'follow', 'mention', 'message', 'system', 'marketing')),

    -- Delivery Channels
    email_enabled BOOLEAN DEFAULT TRUE,
    push_enabled BOOLEAN DEFAULT TRUE,
    in_app_enabled BOOLEAN DEFAULT TRUE,

    -- Settings
    priority VARCHAR(10) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    ttl_hours INTEGER DEFAULT 168,  -- 7 days

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User notifications
CREATE TABLE notifications (
    notification_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id),

    -- Notification Content
    template_id UUID REFERENCES notification_templates(template_id),
    custom_title VARCHAR(200),
    custom_body TEXT,
    action_url VARCHAR(1000),

    -- Context
    related_content_type VARCHAR(20),
    related_content_id UUID,
    actor_user_id UUID REFERENCES users(user_id),  -- Who triggered the notification

    -- Delivery Status
    email_sent BOOLEAN DEFAULT FALSE,
    email_sent_at TIMESTAMP WITH TIME ZONE,
    push_sent BOOLEAN DEFAULT FALSE,
    push_sent_at TIMESTAMP WITH TIME ZONE,
    in_app_read BOOLEAN DEFAULT FALSE,
    in_app_read_at TIMESTAMP WITH TIME ZONE,

    -- Status
    notification_status VARCHAR(20) DEFAULT 'pending'
        CHECK (notification_status IN ('pending', 'sent', 'delivered', 'read', 'expired', 'failed')),

    -- Priority and TTL
    priority VARCHAR(10) DEFAULT 'normal',
    expires_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SEARCH AND DISCOVERY
-- ===========================================

-- Search queries and results
CREATE TABLE search_queries (
    query_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(user_id),  -- NULL for anonymous searches

    -- Search Details
    search_query TEXT NOT NULL,
    search_type VARCHAR(20) DEFAULT 'content'
        CHECK (search_type IN ('content', 'users', 'hashtags', 'locations')),
    filters_applied JSONB,

    -- Results
    result_count INTEGER DEFAULT 0,
    clicked_result_id UUID,
    clicked_result_type VARCHAR(20),

    -- Performance
    search_duration_ms INTEGER,
    search_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Context
    ip_address INET,
    user_agent TEXT,
    device_type VARCHAR(20)
);

-- Trending topics and hashtags
CREATE TABLE trending_topics (
    trend_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    topic_type VARCHAR(20) NOT NULL CHECK (topic_type IN ('hashtag', 'keyword', 'location')),
    topic_value VARCHAR(100) NOT NULL,

    -- Trend Metrics
    post_count INTEGER DEFAULT 0,
    unique_users INTEGER DEFAULT 0,
    engagement_score DECIMAL(10,2) DEFAULT 0,

    -- Trend Classification
    trend_category VARCHAR(30),
    is_viral BOOLEAN DEFAULT FALSE,

    -- Geographic Scope
    country_code CHAR(2),
    region VARCHAR(50),

    -- Time Window
    trend_period_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    trend_period_end TIMESTAMP WITH TIME ZONE,

    -- Rank within period
    rank_within_period INTEGER,

    UNIQUE (topic_type, topic_value, trend_period_start)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- User indexes
CREATE INDEX idx_users_username ON users (username);
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_status ON users (account_status);
CREATE INDEX idx_users_created ON users (created_at DESC);
CREATE INDEX idx_users_last_active ON users (last_active_at DESC);

-- Post indexes
CREATE INDEX idx_posts_author ON posts (author_id, created_at DESC);
CREATE INDEX idx_posts_visibility ON posts (visibility, created_at DESC);
CREATE INDEX idx_posts_type ON posts (content_type, created_at DESC);
CREATE INDEX idx_posts_hashtags ON posts USING gin (hashtags);
CREATE INDEX idx_posts_mentions ON posts USING gin (mentions);
CREATE INDEX idx_posts_search ON posts USING gin (search_vector);
CREATE INDEX idx_posts_location ON posts USING gist (point(longitude, latitude));

-- Relationship indexes
CREATE INDEX idx_user_relationships_follower ON user_relationships (follower_id, relationship_type, status);
CREATE INDEX idx_user_relationships_followed ON user_relationships (followed_id, relationship_type, status);

-- Engagement indexes
CREATE INDEX idx_post_reactions_post ON post_reactions (post_id, created_at DESC);
CREATE INDEX idx_post_reactions_user ON post_reactions (user_id, created_at DESC);

-- Comment indexes
CREATE INDEX idx_comments_post ON comments (post_id, created_at DESC);
CREATE INDEX idx_comments_author ON comments (author_id, created_at DESC);
CREATE INDEX idx_comments_thread ON comments USING gist (thread_path);
CREATE INDEX idx_comments_parent ON comments (parent_comment_id);
CREATE INDEX idx_comments_search ON comments USING gin (search_vector);

-- Message indexes
CREATE INDEX idx_messages_conversation ON messages (conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender ON messages (sender_id, created_at DESC);
CREATE INDEX idx_messages_search ON messages USING gin (search_vector);

-- Moderation indexes
CREATE INDEX idx_content_reports_status ON content_reports (investigation_status, created_at DESC);
CREATE INDEX idx_content_reports_category ON content_reports (report_category);
CREATE INDEX idx_moderation_queue_status ON moderation_queue (queue_status, priority DESC);

-- Analytics indexes
CREATE INDEX idx_content_analytics_content ON content_analytics (content_type, content_id, date_recorded DESC);
CREATE INDEX idx_user_activity_user ON user_activity_analytics (user_id, date_recorded DESC);
CREATE INDEX idx_platform_analytics_date ON platform_analytics (date_recorded DESC, hour_recorded);

-- Notification indexes
CREATE INDEX idx_notifications_user ON notifications (user_id, created_at DESC);
CREATE INDEX idx_notifications_status ON notifications (notification_status, created_at DESC);

-- Search indexes
CREATE INDEX idx_search_queries_user ON search_queries (user_id, search_timestamp DESC);
CREATE INDEX idx_search_queries_query ON search_queries USING gin (to_tsvector('english', search_query));
CREATE INDEX idx_trending_topics_period ON trending_topics (trend_period_start DESC, rank_within_period);

-- ===========================================
-- PARTITIONING SETUP
-- ===========================================

-- Analytics partitioning (daily)
CREATE TABLE content_analytics_2024_01 PARTITION OF content_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE user_activity_analytics_2024_01 PARTITION OF user_activity_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE platform_analytics_2024_01 PARTITION OF platform_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- User feed view (simplified - would need more complex logic in production)
CREATE VIEW user_feed AS
SELECT
    p.*,
    u.username,
    u.display_name,
    u.avatar_url,
    u.is_verified,
    CASE WHEN ur.relationship_type = 'follow' AND ur.status = 'active' THEN TRUE ELSE FALSE END AS is_following,
    CASE WHEN pr.reaction_type IS NOT NULL THEN TRUE ELSE FALSE END AS user_liked
FROM posts p
JOIN users u ON p.author_id = u.user_id
LEFT JOIN user_relationships ur ON ur.followed_id = p.author_id AND ur.follower_id = current_setting('app.current_user_id')::UUID
LEFT JOIN post_reactions pr ON pr.post_id = p.post_id AND pr.user_id = current_setting('app.current_user_id')::UUID
WHERE p.post_status = 'published'
  AND (p.visibility = 'public'
       OR (p.visibility = 'friends' AND ur.status = 'active')
       OR p.author_id = current_setting('app.current_user_id')::UUID)
ORDER BY p.created_at DESC;

-- User profile summary
CREATE VIEW user_profile_summary AS
SELECT
    u.user_id,
    u.username,
    u.display_name,
    u.bio,
    u.avatar_url,
    u.cover_photo_url,
    u.is_verified,
    u.location,
    u.website,
    u.created_at,

    -- Follower counts
    COALESCE(follower_counts.follower_count, 0) AS follower_count,
    COALESCE(following_counts.following_count, 0) AS following_count,

    -- Content counts
    COALESCE(post_counts.post_count, 0) AS post_count,
    COALESCE(like_counts.like_count, 0) AS total_likes_received,

    -- Recent activity
    recent_posts.last_post_date,
    recent_posts.last_post_content

FROM users u
LEFT JOIN (
    SELECT followed_id, COUNT(*) AS follower_count
    FROM user_relationships
    WHERE relationship_type = 'follow' AND status = 'active'
    GROUP BY followed_id
) follower_counts ON u.user_id = follower_counts.followed_id
LEFT JOIN (
    SELECT follower_id, COUNT(*) AS following_count
    FROM user_relationships
    WHERE relationship_type = 'follow' AND status = 'active'
    GROUP BY follower_id
) following_counts ON u.user_id = following_counts.follower_id
LEFT JOIN (
    SELECT author_id, COUNT(*) AS post_count
    FROM posts
    WHERE post_status = 'published'
    GROUP BY author_id
) post_counts ON u.user_id = post_counts.author_id
LEFT JOIN (
    SELECT p.author_id, COUNT(*) AS like_count
    FROM posts p
    JOIN post_reactions pr ON p.post_id = pr.post_id
    GROUP BY p.author_id
) like_counts ON u.user_id = like_counts.author_id
LEFT JOIN (
    SELECT author_id,
           MAX(created_at) AS last_post_date,
           (SELECT content FROM posts WHERE author_id = p.author_id AND post_status = 'published' ORDER BY created_at DESC LIMIT 1) AS last_post_content
    FROM posts p
    WHERE post_status = 'published'
    GROUP BY author_id
) recent_posts ON u.user_id = recent_posts.author_id;

-- ===========================================
-- TRIGGERS FOR BUSINESS LOGIC
-- ===========================================

-- Update post engagement counts
CREATE OR REPLACE FUNCTION update_post_engagement_counts()
RETURNS TRIGGER AS $$
DECLARE
    target_post_id UUID;
BEGIN
    -- Determine which post to update
    IF TG_TABLE_NAME = 'post_reactions' THEN
        target_post_id := NEW.post_id;
    ELSIF TG_TABLE_NAME = 'comments' THEN
        target_post_id := NEW.post_id;
    ELSIF TG_TABLE_NAME = 'post_shares' THEN
        target_post_id := NEW.original_post_id;
    END IF;

    -- Update counts
    UPDATE posts SET
        like_count = (
            SELECT COUNT(*) FROM post_reactions
            WHERE post_id = target_post_id AND reaction_type = 'like'
        ),
        comment_count = (
            SELECT COUNT(*) FROM comments
            WHERE post_id = target_post_id AND comment_status = 'published'
        ),
        share_count = (
            SELECT COUNT(*) FROM post_shares
            WHERE original_post_id = target_post_id
        ),
        updated_at = CURRENT_TIMESTAMP
    WHERE post_id = target_post_id;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_post_likes
    AFTER INSERT OR DELETE ON post_reactions
    FOR EACH ROW EXECUTE FUNCTION update_post_engagement_counts();

CREATE TRIGGER trigger_update_post_comments
    AFTER INSERT OR UPDATE OR DELETE ON comments
    FOR EACH ROW EXECUTE FUNCTION update_post_engagement_counts();

CREATE TRIGGER trigger_update_post_shares
    AFTER INSERT OR DELETE ON post_shares
    FOR EACH ROW EXECUTE FUNCTION update_post_engagement_counts();

-- Update conversation last message
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations SET
        last_message_at = NEW.created_at,
        last_message_preview = LEFT(NEW.content, 100),
        last_message_sender_id = NEW.sender_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE conversation_id = NEW.conversation_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_conversation_last_message
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION update_conversation_last_message();

-- Content moderation trigger
CREATE OR REPLACE FUNCTION check_content_moderation()
RETURNS TRIGGER AS $$
DECLARE
    content_text TEXT;
    filter_record RECORD;
    risk_score DECIMAL := 0;
BEGIN
    -- Get content to check
    IF TG_TABLE_NAME = 'posts' THEN
        content_text := COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.content, '');
    ELSIF TG_TABLE_NAME = 'comments' THEN
        content_text := NEW.content;
    ELSIF TG_TABLE_NAME = 'messages' THEN
        content_text := COALESCE(NEW.content, '');
    END IF;

    -- Check against filters
    FOR filter_record IN SELECT * FROM content_filters WHERE is_active = TRUE
    LOOP
        -- Keyword matching
        IF filter_record.keywords IS NOT NULL AND filter_record.keywords != '{}' THEN
            IF content_text ILIKE ANY (SELECT '%' || keyword || '%' FROM unnest(filter_record.keywords) AS keyword) THEN
                risk_score := risk_score + filter_record.severity_score;
            END IF;
        END IF;

        -- Regex matching
        IF filter_record.regex_pattern IS NOT NULL THEN
            IF content_text ~ filter_record.regex_pattern THEN
                risk_score := risk_score + filter_record.severity_score;
            END IF;
        END IF;
    END LOOP;

    -- Flag for moderation if risk score is high
    IF risk_score >= 5 THEN
        INSERT INTO moderation_queue (
            content_type, content_id, moderation_reason,
            flagged_by, risk_score, priority
        ) VALUES (
            TG_TABLE_NAME, COALESCE(NEW.id, NEW.post_id, NEW.comment_id, NEW.message_id),
            'Automated content filter',
            'automated_system',
            LEAST(risk_score / 10.0, 1.0),
            LEAST(CEIL(risk_score / 2), 10)
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_content_moderation_posts
    BEFORE INSERT ON posts
    FOR EACH ROW EXECUTE FUNCTION check_content_moderation();

CREATE TRIGGER trigger_content_moderation_comments
    BEFORE INSERT ON comments
    FOR EACH ROW EXECUTE FUNCTION check_content_moderation();

-- This comprehensive social media database schema provides a solid foundation
-- for modern social platforms with support for real-time feeds, content moderation,
-- analytics, and scalable social interactions.
