-- ============================================
-- ENTERTAINMENT PLATFORM SCHEMA DESIGN
-- ============================================
-- Comprehensive schema for streaming, gaming, social media, and content platforms
-- Supports video streaming, user-generated content, gaming mechanics, social features, and analytics

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "hstore";
CREATE EXTENSION IF NOT EXISTS "postgis";  -- For location-based features

-- ============================================
-- CORE ENTITIES
-- ============================================

-- Users (Viewers, Creators, Gamers)
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    display_name VARCHAR(100),
    avatar_url VARCHAR(500),
    bio TEXT,
    date_of_birth DATE,
    country VARCHAR(100),
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Account settings
    is_verified BOOLEAN DEFAULT FALSE,
    is_creator BOOLEAN DEFAULT FALSE,
    is_premium BOOLEAN DEFAULT FALSE,
    subscription_tier VARCHAR(20) DEFAULT 'free' CHECK (subscription_tier IN ('free', 'basic', 'premium', 'ultimate')),
    subscription_expires_at TIMESTAMP WITH TIME ZONE,

    -- Privacy and preferences
    profile_visibility VARCHAR(20) DEFAULT 'public' CHECK (profile_visibility IN ('public', 'friends', 'private')),
    content_rating_preference VARCHAR(10) DEFAULT 'general' CHECK (content_rating_preference IN ('general', 'mature', 'adult')),

    -- Gaming profile
    gamer_tag VARCHAR(50) UNIQUE,
    gaming_platform VARCHAR(50), -- 'steam', 'epic', 'playstation', 'xbox'
    gaming_experience_level VARCHAR(20) DEFAULT 'casual' CHECK (gaming_experience_level IN ('casual', 'intermediate', 'advanced', 'expert')),

    -- Social features
    follower_count INTEGER DEFAULT 0,
    following_count INTEGER DEFAULT 0,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english',
            username || ' ' || display_name || ' ' || bio || ' ' || gamer_tag
        )
    ) STORED,

    CONSTRAINT chk_age_requirement CHECK (
        date_of_birth IS NULL OR
        EXTRACT(YEAR FROM AGE(date_of_birth)) >= CASE
            WHEN content_rating_preference = 'adult' THEN 18
            ELSE 13
        END
    )
);

-- User preferences and settings
CREATE TABLE user_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    notification_settings JSONB DEFAULT '{
        "email_notifications": true,
        "push_notifications": true,
        "friend_requests": true,
        "content_recommendations": true,
        "game_invites": true,
        "achievement_unlocks": true
    }',
    privacy_settings JSONB DEFAULT '{
        "show_online_status": true,
        "allow_friend_requests": true,
        "show_game_activity": true,
        "allow_direct_messages": true
    }',
    content_filters JSONB DEFAULT '{
        "blocked_categories": [],
        "blocked_users": [],
        "age_restriction": "general"
    }',
    interface_settings JSONB DEFAULT '{
        "theme": "dark",
        "language": "en",
        "timezone": "UTC"
    }'
);

-- ============================================
-- CONTENT MANAGEMENT
-- ============================================

-- Content categories and genres
CREATE TABLE content_categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    slug VARCHAR(120) NOT NULL UNIQUE,
    description TEXT,
    parent_category_id INTEGER REFERENCES content_categories(category_id),

    -- Category metadata
    icon_url VARCHAR(500),
    color_hex VARCHAR(7),
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,

    -- Content type restrictions
    allowed_content_types TEXT[] DEFAULT ARRAY['video', 'stream', 'article', 'game'],
    age_rating VARCHAR(10) DEFAULT 'general' CHECK (age_rating IN ('general', 'teen', 'mature', 'adult')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Content items (videos, streams, articles, games)
CREATE TABLE content_items (
    content_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(300) NOT NULL,
    description TEXT,
    content_type VARCHAR(20) NOT NULL CHECK (content_type IN ('video', 'live_stream', 'article', 'game', 'music', 'podcast', 'clip')),

    -- Categorization
    category_id INTEGER REFERENCES content_categories(category_id),
    tags TEXT[] DEFAULT '{}',
    language VARCHAR(5) DEFAULT 'en',

    -- Content metadata
    duration_seconds INTEGER, -- For videos/audio
    file_size_bytes BIGINT,
    thumbnail_url VARCHAR(500),
    preview_url VARCHAR(500), -- Short preview clip

    -- Media files
    original_file_url VARCHAR(500),
    streaming_urls JSONB DEFAULT '{}', -- Multiple quality versions
    transcript_url VARCHAR(500),

    -- Content creator
    creator_id UUID REFERENCES users(user_id) NOT NULL,
    co_creators UUID[] DEFAULT '{}',

    -- Publishing
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft', 'review', 'published', 'archived', 'deleted')),
    visibility VARCHAR(20) DEFAULT 'public' CHECK (visibility IN ('public', 'unlisted', 'private', 'subscribers_only')),
    publish_at TIMESTAMP WITH TIME ZONE,
    published_at TIMESTAMP WITH TIME ZONE,

    -- Monetization
    is_monetized BOOLEAN DEFAULT FALSE,
    monetization_type VARCHAR(20) CHECK (monetization_type IN ('ads', 'subscription', 'paywall', 'donations', 'sponsorship')),
    price_cents INTEGER DEFAULT 0, -- For paywalled content

    -- Engagement metrics
    view_count BIGINT DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    dislike_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    bookmark_count INTEGER DEFAULT 0,

    -- Quality and ratings
    average_rating DECIMAL(3,2) DEFAULT 0.00,
    total_ratings INTEGER DEFAULT 0,
    content_rating VARCHAR(10) DEFAULT 'general' CHECK (content_rating IN ('general', 'teen', 'mature', 'adult')),

    -- Technical metadata
    video_codec VARCHAR(20),
    audio_codec VARCHAR(20),
    resolution VARCHAR(20), -- '720p', '1080p', '4k'
    bitrate_kbps INTEGER,

    -- Geographic restrictions
    allowed_countries TEXT[] DEFAULT '{}', -- Empty means worldwide
    blocked_countries TEXT[] DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english',
            title || ' ' || description || ' ' || array_to_string(tags, ' ')
        )
    ) STORED,

    CONSTRAINT chk_published_logic CHECK (
        (status = 'published' AND published_at IS NOT NULL) OR
        (status != 'published' AND published_at IS NULL)
    ),
    CONSTRAINT chk_monetization_logic CHECK (
        (is_monetized = TRUE AND monetization_type IS NOT NULL) OR
        (is_monetized = FALSE)
    )
);

-- Content versions (for updates and edits)
CREATE TABLE content_versions (
    version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID REFERENCES content_items(content_id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    title VARCHAR(300),
    description TEXT,
    file_url VARCHAR(500),
    change_summary TEXT,
    is_major_version BOOLEAN DEFAULT FALSE,
    created_by UUID REFERENCES users(user_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (content_id, version_number)
);

-- ============================================
-- STREAMING AND MEDIA
-- ============================================

-- Live streams
CREATE TABLE live_streams (
    stream_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID REFERENCES content_items(content_id) ON DELETE CASCADE,
    streamer_id UUID REFERENCES users(user_id) NOT NULL,

    -- Stream configuration
    stream_key VARCHAR(100) UNIQUE NOT NULL,
    stream_title VARCHAR(200) NOT NULL,
    stream_description TEXT,
    category_id INTEGER REFERENCES content_categories(category_id),

    -- Stream status
    status VARCHAR(20) DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'starting', 'live', 'ended', 'cancelled')),
    is_featured BOOLEAN DEFAULT FALSE,

    -- Streaming details
    rtmp_url VARCHAR(500),
    hls_url VARCHAR(500),
    chat_enabled BOOLEAN DEFAULT TRUE,
    donations_enabled BOOLEAN DEFAULT TRUE,

    -- Schedule
    scheduled_start TIMESTAMP WITH TIME ZONE,
    actual_start TIMESTAMP WITH TIME ZONE,
    actual_end TIMESTAMP WITH TIME ZONE,

    -- Stream metrics
    peak_viewers INTEGER DEFAULT 0,
    total_viewers INTEGER DEFAULT 0,
    total_chat_messages INTEGER DEFAULT 0,
    total_donations_cents INTEGER DEFAULT 0,

    -- Quality settings
    video_quality VARCHAR(20) DEFAULT '720p',
    frame_rate INTEGER DEFAULT 30,
    bitrate_kbps INTEGER DEFAULT 3000,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_stream_timing CHECK (
        (actual_start IS NULL OR actual_end IS NULL) OR
        (actual_start < actual_end)
    )
);

-- Stream viewers and analytics
CREATE TABLE stream_viewers (
    viewer_session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stream_id UUID REFERENCES live_streams(stream_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id), -- NULL for anonymous viewers
    ip_address INET,

    -- Session details
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    left_at TIMESTAMP WITH TIME ZONE,
    watch_duration_seconds INTEGER,

    -- Engagement
    chat_messages_sent INTEGER DEFAULT 0,
    donations_made_cents INTEGER DEFAULT 0,
    reactions_sent INTEGER DEFAULT 0,

    -- Quality metrics
    buffering_events INTEGER DEFAULT 0,
    average_bitrate_kbps INTEGER,

    UNIQUE (stream_id, user_id, joined_at) DEFERRABLE INITIALLY DEFERRED
);

-- ============================================
-- GAMING FEATURES
-- ============================================

-- Games catalog
CREATE TABLE games (
    game_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL UNIQUE,
    slug VARCHAR(220) NOT NULL UNIQUE,
    description TEXT,
    developer VARCHAR(100),
    publisher VARCHAR(100),

    -- Game metadata
    release_date DATE,
    genres TEXT[] DEFAULT '{}',
    platforms TEXT[] DEFAULT '{}', -- 'pc', 'console', 'mobile', 'web'
    age_rating VARCHAR(10) CHECK (age_rating IN ('everyone', 'teen', 'mature', 'adult')),

    -- Media
    cover_image_url VARCHAR(500),
    screenshots JSONB DEFAULT '[]',
    trailer_url VARCHAR(500),

    -- Technical specs
    system_requirements JSONB DEFAULT '{}',
    file_size_gb DECIMAL(6,2),

    -- Store information
    base_price_cents INTEGER DEFAULT 0,
    discount_percentage DECIMAL(5,2) DEFAULT 0.00,
    is_free BOOLEAN DEFAULT FALSE,

    -- Community
    total_players INTEGER DEFAULT 0,
    total_reviews INTEGER DEFAULT 0,
    average_rating DECIMAL(3,2) DEFAULT 0.00,

    -- Status
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'beta', 'coming_soon', 'discontinued')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english',
            title || ' ' || description || ' ' || developer || ' ' || publisher || ' ' ||
            array_to_string(genres, ' ') || ' ' || array_to_string(platforms, ' ')
        )
    ) STORED
);

-- User game library
CREATE TABLE user_game_library (
    library_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    game_id UUID REFERENCES games(game_id) ON DELETE CASCADE,

    -- Ownership details
    ownership_type VARCHAR(20) DEFAULT 'purchased' CHECK (ownership_type IN ('purchased', 'gift', 'subscription', 'free')),
    purchase_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    purchase_price_cents INTEGER,

    -- Gaming activity
    last_played_at TIMESTAMP WITH TIME ZONE,
    total_playtime_hours DECIMAL(8,2) DEFAULT 0.00,
    achievements_unlocked INTEGER DEFAULT 0,
    current_level INTEGER DEFAULT 0,

    -- Game settings and preferences
    user_settings JSONB DEFAULT '{}',
    key_bindings JSONB DEFAULT '{}',

    UNIQUE (user_id, game_id)
);

-- Game sessions and activity tracking
CREATE TABLE game_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    game_id UUID REFERENCES games(game_id) ON DELETE CASCADE,

    -- Session details
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER,

    -- Game progress
    score INTEGER,
    level_reached INTEGER,
    experience_gained INTEGER,
    items_collected JSONB DEFAULT '[]',

    -- Performance metrics
    average_fps DECIMAL(5,1),
    network_latency_ms INTEGER,

    -- Social features
    is_multiplayer BOOLEAN DEFAULT FALSE,
    players_count INTEGER DEFAULT 1,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_session_duration CHECK (
        (ended_at IS NULL) OR
        (ended_at > started_at AND duration_minutes = EXTRACT(EPOCH FROM (ended_at - started_at))/60)
    )
);

-- Achievements and leaderboards
CREATE TABLE achievements (
    achievement_id SERIAL PRIMARY KEY,
    game_id UUID REFERENCES games(game_id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    icon_url VARCHAR(500),

    -- Achievement criteria
    achievement_type VARCHAR(30) CHECK (achievement_type IN (
        'score_threshold', 'level_reached', 'time_based', 'collection',
        'social', 'special_event', 'streak', 'milestone'
    )),
    criteria JSONB NOT NULL, -- Flexible criteria definition

    -- Rewards
    points_reward INTEGER DEFAULT 0,
    badge_reward VARCHAR(50),

    -- Rarity and visibility
    rarity VARCHAR(10) DEFAULT 'common' CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),
    is_hidden BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (game_id, name)
);

-- User achievements
CREATE TABLE user_achievements (
    user_achievement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    achievement_id INTEGER REFERENCES achievements(achievement_id) ON DELETE CASCADE,
    game_id UUID REFERENCES games(game_id),

    earned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    progress_percentage DECIMAL(5,2) DEFAULT 100.00, -- For partial achievements

    UNIQUE (user_id, achievement_id)
);

-- Leaderboards
CREATE TABLE leaderboards (
    leaderboard_id SERIAL PRIMARY KEY,
    game_id UUID REFERENCES games(game_id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,

    -- Leaderboard configuration
    metric_type VARCHAR(30) NOT NULL CHECK (metric_type IN (
        'score', 'level', 'time', 'experience', 'wins', 'streak'
    )),
    sort_order VARCHAR(4) DEFAULT 'DESC' CHECK (sort_order IN ('ASC', 'DESC')),
    reset_period VARCHAR(20) CHECK (reset_period IN ('never', 'daily', 'weekly', 'monthly', 'yearly')),

    -- Constraints
    max_entries INTEGER DEFAULT 1000,
    min_value_threshold DECIMAL(15,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (game_id, name)
);

-- Leaderboard entries
CREATE TABLE leaderboard_entries (
    entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    leaderboard_id INTEGER REFERENCES leaderboards(leaderboard_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    game_id UUID REFERENCES games(game_id),

    -- Entry data
    score_value DECIMAL(15,2) NOT NULL,
    rank INTEGER,
    rank_change INTEGER DEFAULT 0, -- Change from previous period

    -- Metadata
    achieved_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    submission_details JSONB DEFAULT '{}',

    UNIQUE (leaderboard_id, user_id)
);

-- ============================================
-- SOCIAL FEATURES
-- ============================================

-- User relationships (friends, followers)
CREATE TABLE user_relationships (
    relationship_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    following_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    -- Relationship type
    relationship_type VARCHAR(20) DEFAULT 'follow' CHECK (relationship_type IN ('follow', 'friend', 'block', 'mute')),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('pending', 'active', 'blocked')),

    -- Friendship-specific
    initiated_by UUID REFERENCES users(user_id),
    accepted_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (follower_id, following_id),
    CONSTRAINT chk_self_relationship CHECK (follower_id != following_id),
    CONSTRAINT chk_friendship_logic CHECK (
        (relationship_type != 'friend') OR
        (relationship_type = 'friend' AND initiated_by IS NOT NULL AND status IN ('pending', 'active'))
    )
);

-- Direct messages and chat
CREATE TABLE chat_conversations (
    conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_type VARCHAR(20) DEFAULT 'direct' CHECK (conversation_type IN ('direct', 'group', 'channel')),

    -- Conversation details
    title VARCHAR(100), -- For group chats
    description TEXT,
    created_by UUID REFERENCES users(user_id),
    is_private BOOLEAN DEFAULT TRUE,

    -- Group chat settings
    max_participants INTEGER DEFAULT 100,
    requires_invitation BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Conversation participants
CREATE TABLE conversation_participants (
    participant_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID REFERENCES chat_conversations(conversation_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    -- Participant role and permissions
    role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_read_at TIMESTAMP WITH TIME ZONE,

    -- Notification preferences
    is_muted BOOLEAN DEFAULT FALSE,
    notification_settings JSONB DEFAULT '{"mentions_only": false, "all_messages": true}',

    UNIQUE (conversation_id, user_id)
);

-- Messages
CREATE TABLE chat_messages (
    message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID REFERENCES chat_conversations(conversation_id) ON DELETE CASCADE,
    sender_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    -- Message content
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'video', 'file', 'system')),
    content TEXT,
    metadata JSONB DEFAULT '{}', -- For media messages, links, etc.

    -- Message status
    is_edited BOOLEAN DEFAULT FALSE,
    edited_at TIMESTAMP WITH TIME ZONE,
    is_deleted BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMP WITH TIME ZONE,

    -- Thread support (for replying to specific messages)
    parent_message_id UUID REFERENCES chat_messages(message_id),

    -- Reactions and engagement
    reaction_counts JSONB DEFAULT '{}', -- {"thumbs_up": 5, "heart": 3}

    sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', content)
    ) STORED
) PARTITION BY RANGE (sent_at);

-- Message deliveries and reads
CREATE TABLE message_deliveries (
    delivery_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES chat_messages(message_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    -- Delivery status
    status VARCHAR(20) DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'read')),
    status_changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (message_id, user_id)
);

-- ============================================
-- ENGAGEMENT AND INTERACTIONS
-- ============================================

-- Content interactions (likes, dislikes, shares)
CREATE TABLE content_interactions (
    interaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    content_id UUID REFERENCES content_items(content_id) ON DELETE CASCADE,

    -- Interaction type
    interaction_type VARCHAR(20) NOT NULL CHECK (interaction_type IN ('like', 'dislike', 'love', 'laugh', 'angry', 'sad')),
    weight INTEGER DEFAULT 1, -- For ranking algorithms

    -- Context
    interacted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    source VARCHAR(50) DEFAULT 'web', -- 'web', 'mobile', 'api'
    user_agent TEXT,

    UNIQUE (user_id, content_id, interaction_type)
);

-- Comments and replies
CREATE TABLE content_comments (
    comment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID REFERENCES content_items(content_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES content_comments(comment_id) ON DELETE CASCADE, -- For replies

    -- Comment content
    comment_text TEXT NOT NULL,
    is_edited BOOLEAN DEFAULT FALSE,
    edited_at TIMESTAMP WITH TIME ZONE,

    -- Moderation
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'pending', 'flagged', 'removed')),
    moderation_reason TEXT,
    moderated_by UUID REFERENCES users(user_id),
    moderated_at TIMESTAMP WITH TIME ZONE,

    -- Engagement
    like_count INTEGER DEFAULT 0,
    reply_count INTEGER DEFAULT 0,
    is_pinned BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', comment_text)
    ) STORED,

    CONSTRAINT chk_reply_depth CHECK (
        parent_comment_id IS NULL OR
        (SELECT parent_comment_id FROM content_comments WHERE comment_id = content_comments.parent_comment_id) IS NULL
    )
);

-- Bookmarks and watch later
CREATE TABLE user_bookmarks (
    bookmark_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    content_id UUID REFERENCES content_items(content_id) ON DELETE CASCADE,

    -- Bookmark details
    bookmark_type VARCHAR(20) DEFAULT 'watch_later' CHECK (bookmark_type IN ('watch_later', 'favorites', 'playlist')),
    playlist_id UUID, -- For playlist organization
    notes TEXT,
    progress_seconds INTEGER DEFAULT 0, -- Resume watching position

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id, content_id, bookmark_type)
);

-- ============================================
-- RECOMMENDATION SYSTEM
-- ============================================

-- User content preferences
CREATE TABLE user_content_preferences (
    preference_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    -- Content preferences
    preferred_categories INTEGER[] DEFAULT '{}',
    preferred_tags TEXT[] DEFAULT '{}',
    preferred_creators UUID[] DEFAULT '{}',

    -- Gaming preferences
    preferred_genres TEXT[] DEFAULT '{}',
    preferred_platforms TEXT[] DEFAULT '{}',
    skill_level VARCHAR(20),

    -- Content filters
    blocked_categories INTEGER[] DEFAULT '{}',
    blocked_creators UUID[] DEFAULT '{}',
    content_rating_preference VARCHAR(10) DEFAULT 'general',

    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id)
);

-- Content recommendations
CREATE TABLE content_recommendations (
    recommendation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    content_id UUID REFERENCES content_items(content_id) ON DELETE CASCADE,

    -- Recommendation details
    recommendation_score DECIMAL(5,4) NOT NULL CHECK (recommendation_score BETWEEN 0 AND 1),
    recommendation_reason VARCHAR(50), -- 'collaborative_filtering', 'content_based', 'trending', 'social'
    algorithm_version VARCHAR(20),

    -- Context
    source_page VARCHAR(50), -- 'home', 'search', 'related', 'trending'
    position_in_list INTEGER,

    -- User interaction with recommendation
    was_viewed BOOLEAN DEFAULT FALSE,
    was_interacted BOOLEAN DEFAULT FALSE,
    interaction_type VARCHAR(20),

    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '24 hours'),

    UNIQUE (user_id, content_id, generated_at::DATE)
);

-- Content similarity matrix (for content-based recommendations)
CREATE TABLE content_similarity (
    similarity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id_1 UUID REFERENCES content_items(content_id) ON DELETE CASCADE,
    content_id_2 UUID REFERENCES content_items(content_id) ON DELETE CASCADE,

    -- Similarity metrics
    similarity_score DECIMAL(5,4) NOT NULL CHECK (similarity_score BETWEEN 0 AND 1),
    similarity_factors JSONB DEFAULT '{}', -- What makes them similar

    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (content_id_1, content_id_2),
    CONSTRAINT chk_content_order CHECK (content_id_1 < content_id_2)
);

-- ============================================
-- ANALYTICS AND REPORTING
-- ============================================

-- Content view analytics
CREATE TABLE content_view_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID REFERENCES content_items(content_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id), -- NULL for anonymous views
    session_id VARCHAR(255),

    -- View details
    viewed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    watch_duration_seconds INTEGER,
    completion_percentage DECIMAL(5,2),

    -- Context
    source VARCHAR(50), -- 'direct', 'search', 'recommendation', 'social'
    referrer_url VARCHAR(500),
    device_type VARCHAR(20), -- 'desktop', 'mobile', 'tablet', 'tv'
    country VARCHAR(100),

    -- Quality metrics
    buffering_events INTEGER DEFAULT 0,
    average_bitrate_kbps INTEGER,
    dropped_frames INTEGER DEFAULT 0,

    -- Engagement
    liked BOOLEAN DEFAULT FALSE,
    shared BOOLEAN DEFAULT FALSE,
    bookmarked BOOLEAN DEFAULT FALSE,

    UNIQUE (content_id, user_id, viewed_at::DATE, session_id)
) PARTITION BY RANGE (viewed_at);

-- Creator analytics
CREATE TABLE creator_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    date DATE NOT NULL,

    -- Content metrics
    videos_uploaded INTEGER DEFAULT 0,
    total_views BIGINT DEFAULT 0,
    total_watch_time_hours DECIMAL(10,2) DEFAULT 0.00,

    -- Engagement metrics
    total_likes INTEGER DEFAULT 0,
    total_shares INTEGER DEFAULT 0,
    total_comments INTEGER DEFAULT 0,

    -- Subscriber metrics
    new_subscribers INTEGER DEFAULT 0,
    total_subscribers INTEGER,

    -- Revenue metrics
    ad_revenue_cents INTEGER DEFAULT 0,
    subscription_revenue_cents INTEGER DEFAULT 0,
    total_revenue_cents INTEGER DEFAULT 0,

    -- Gaming metrics (for gaming creators)
    game_sessions INTEGER DEFAULT 0,
    achievements_unlocked INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (creator_id, date)
) PARTITION BY RANGE (date);

-- ============================================
-- MONETIZATION AND COMMERCE
-- ============================================

-- Creator sponsorships and brand deals
CREATE TABLE creator_sponsorships (
    sponsorship_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    -- Sponsorship details
    brand_name VARCHAR(100) NOT NULL,
    campaign_name VARCHAR(200),
    sponsorship_type VARCHAR(30) CHECK (sponsorship_type IN ('product_placement', 'affiliate', 'paid_promotion', 'brand_ambassador')),

    -- Terms
    contract_start_date DATE NOT NULL,
    contract_end_date DATE,
    payment_terms JSONB DEFAULT '{}',
    deliverables TEXT,

    -- Compensation
    flat_fee_cents INTEGER,
    performance_bonus JSONB DEFAULT '{}', -- Based on views, engagement, etc.
    total_compensation_cents INTEGER,

    -- Content requirements
    required_mentions TEXT[],
    disclosure_required BOOLEAN DEFAULT TRUE,

    -- Status
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('pending', 'active', 'completed', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_contract_dates CHECK (contract_start_date <= contract_end_date)
);

-- Subscription tiers and benefits
CREATE TABLE subscription_tiers (
    tier_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    display_name VARCHAR(100) NOT NULL,
    description TEXT,

    -- Pricing
    price_cents INTEGER NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    billing_cycle VARCHAR(20) DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly', 'yearly', 'one_time')),

    -- Benefits
    benefits JSONB NOT NULL, -- {"ad_free": true, "early_access": true, "exclusive_content": true}
    max_concurrent_streams INTEGER DEFAULT 1,

    -- Limits
    monthly_watch_hours INTEGER,
    download_quality VARCHAR(10) DEFAULT '720p',

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User subscriptions
CREATE TABLE user_subscriptions (
    subscription_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    tier_id INTEGER REFERENCES subscription_tiers(tier_id),

    -- Subscription details
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'past_due', 'cancelled', 'expired')),
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    current_period_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    current_period_end TIMESTAMP WITH TIME ZONE,
    cancel_at_period_end BOOLEAN DEFAULT FALSE,
    cancelled_at TIMESTAMP WITH TIME ZONE,

    -- Payment information
    payment_method_id VARCHAR(100), -- Reference to payment processor
    last_payment_at TIMESTAMP WITH TIME ZONE,
    next_payment_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id, tier_id, started_at)
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Core user indexes
CREATE INDEX idx_users_username ON users (username);
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_created_at ON users (created_at DESC);
CREATE INDEX idx_users_search ON users USING GIN (search_vector);

-- Content indexes
CREATE INDEX idx_content_items_creator ON content_items (creator_id);
CREATE INDEX idx_content_items_category ON content_items (category_id);
CREATE INDEX idx_content_items_status ON content_items (status);
CREATE INDEX idx_content_items_published_at ON content_items (published_at DESC);
CREATE INDEX idx_content_items_type_status ON content_items (content_type, status);
CREATE INDEX idx_content_items_search ON content_items USING GIN (search_vector);

-- Social features indexes
CREATE INDEX idx_user_relationships_follower ON user_relationships (follower_id, relationship_type);
CREATE INDEX idx_user_relationships_following ON user_relationships (following_id, relationship_type);
CREATE INDEX idx_chat_messages_conversation ON chat_messages (conversation_id, sent_at DESC);
CREATE INDEX idx_conversation_participants_user ON conversation_participants (user_id);

-- Gaming indexes
CREATE INDEX idx_games_genres ON games USING GIN (genres);
CREATE INDEX idx_games_platforms ON games USING GIN (platforms);
CREATE INDEX idx_user_game_library_user ON user_game_library (user_id);
CREATE INDEX idx_game_sessions_user_game ON game_sessions (user_id, game_id, started_at DESC);
CREATE INDEX idx_leaderboard_entries_leaderboard_rank ON leaderboard_entries (leaderboard_id, rank);

-- Engagement indexes
CREATE INDEX idx_content_interactions_content ON content_interactions (content_id, interaction_type);
CREATE INDEX idx_content_interactions_user ON content_interactions (user_id);
CREATE INDEX idx_content_comments_content ON content_comments (content_id, created_at DESC);
CREATE INDEX idx_user_bookmarks_user ON user_bookmarks (user_id, bookmark_type);

-- Analytics indexes
CREATE INDEX idx_content_view_analytics_content ON content_view_analytics (content_id, viewed_at DESC);
CREATE INDEX idx_content_view_analytics_user ON content_view_analytics (user_id, viewed_at DESC);
CREATE INDEX idx_creator_analytics_creator_date ON creator_analytics (creator_id, date DESC);

-- ============================================
-- USEFUL VIEWS
-- ============================================

-- User activity feed
CREATE VIEW user_activity_feed AS
SELECT
    'content_created' AS activity_type,
    ci.creator_id AS user_id,
    ci.content_id AS entity_id,
    ci.title AS entity_title,
    ci.published_at AS activity_timestamp,
    ci.thumbnail_url AS entity_image,
    JSON_BUILD_OBJECT('content_type', ci.content_type, 'category', cc.name) AS metadata
FROM content_items ci
LEFT JOIN content_categories cc ON ci.category_id = cc.category_id
WHERE ci.status = 'published'

UNION ALL

SELECT
    'achievement_unlocked' AS activity_type,
    ua.user_id,
    ua.achievement_id::TEXT AS entity_id,
    a.name AS entity_title,
    ua.earned_at AS activity_timestamp,
    a.icon_url AS entity_image,
    JSON_BUILD_OBJECT('game_id', a.game_id, 'rarity', a.rarity) AS metadata
FROM user_achievements ua
JOIN achievements a ON ua.achievement_id = a.achievement_id

UNION ALL

SELECT
    'game_completed' AS activity_type,
    gs.user_id,
    gs.game_id::TEXT AS entity_id,
    g.title AS entity_title,
    gs.ended_at AS activity_timestamp,
    g.cover_image_url AS entity_image,
    JSON_BUILD_OBJECT('score', gs.score, 'duration', gs.duration_minutes) AS metadata
FROM game_sessions gs
JOIN games g ON gs.game_id = g.game_id
WHERE gs.ended_at IS NOT NULL

ORDER BY activity_timestamp DESC;

-- Content recommendations view
CREATE VIEW personalized_recommendations AS
SELECT
    r.user_id,
    r.content_id,
    ci.title,
    ci.thumbnail_url,
    ci.duration_seconds,
    ci.average_rating,
    r.recommendation_score,
    r.recommendation_reason,
    r.generated_at,
    CASE
        WHEN uvi.viewed_at IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS already_viewed,
    CASE
        WHEN ci.content_type = 'live_stream' AND ls.status = 'live' THEN TRUE
        ELSE FALSE
    END AS is_live
FROM content_recommendations r
JOIN content_items ci ON r.content_id = ci.content_id
LEFT JOIN live_streams ls ON ci.content_id = ls.content_id
LEFT JOIN content_view_analytics uvi ON r.user_id = uvi.user_id
    AND r.content_id = uvi.content_id
    AND uvi.viewed_at >= CURRENT_DATE - INTERVAL '30 days'
WHERE r.expires_at > CURRENT_TIMESTAMP
  AND ci.status = 'published'
  AND ci.visibility = 'public'
ORDER BY r.recommendation_score DESC, r.generated_at DESC;

-- Creator performance dashboard
CREATE VIEW creator_performance_dashboard AS
SELECT
    u.user_id,
    u.display_name,
    u.avatar_url,
    u.is_verified,

    -- Content stats
    COUNT(DISTINCT ci.content_id) AS total_content,
    COUNT(DISTINCT CASE WHEN ci.published_at >= CURRENT_DATE - INTERVAL '30 days' THEN ci.content_id END) AS content_last_30d,

    -- Engagement stats
    COALESCE(SUM(ci.view_count), 0) AS total_views,
    COALESCE(SUM(ci.like_count), 0) AS total_likes,
    COALESCE(SUM(ci.comment_count), 0) AS total_comments,
    ROUND(COALESCE(AVG(ci.average_rating), 0), 1) AS avg_rating,

    -- Subscriber stats
    u.follower_count,
    COALESCE(SUM(ca.new_subscribers), 0) AS new_subscribers_30d,

    -- Revenue stats
    COALESCE(SUM(ca.total_revenue_cents), 0) / 100.0 AS total_revenue_usd,
    COALESCE(SUM(ca.ad_revenue_cents + ca.subscription_revenue_cents), 0) / 100.0 AS revenue_last_30d,

    -- Gaming stats (if applicable)
    COUNT(DISTINCT ua.achievement_id) AS achievements_unlocked,
    COALESCE(SUM(gs.duration_minutes), 0) / 60.0 AS gaming_hours

FROM users u
LEFT JOIN content_items ci ON u.user_id = ci.creator_id AND ci.status = 'published'
LEFT JOIN creator_analytics ca ON u.user_id = ca.creator_id AND ca.date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN user_achievements ua ON u.user_id = ua.user_id
LEFT JOIN game_sessions gs ON u.user_id = gs.user_id AND gs.started_at >= CURRENT_DATE - INTERVAL '30 days'
WHERE u.is_creator = TRUE
GROUP BY u.user_id, u.display_name, u.avatar_url, u.is_verified, u.follower_count;

-- ============================================
-- USEFUL FUNCTIONS
-- ============================================

-- Function to calculate content engagement score
CREATE OR REPLACE FUNCTION calculate_engagement_score(content_uuid UUID)
RETURNS DECIMAL(5,2) AS $$
DECLARE
    views INTEGER;
    likes INTEGER;
    comments INTEGER;
    shares INTEGER;
    age_hours DECIMAL;
    engagement_score DECIMAL(5,2);
BEGIN
    -- Get content metrics
    SELECT
        ci.view_count,
        ci.like_count,
        ci.comment_count,
        ci.share_count,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ci.published_at)) / 3600
    INTO views, likes, comments, shares, age_hours
    FROM content_items ci
    WHERE ci.content_id = content_uuid;

    -- Calculate engagement score (weighted formula)
    engagement_score := (
        (likes * 2.0) +
        (comments * 3.0) +
        (shares * 5.0) +
        (views * 0.1)
    ) / GREATEST(age_hours, 1); -- Normalize by age

    -- Cap at reasonable maximum
    RETURN LEAST(engagement_score, 100.00);
END;
$$ LANGUAGE plpgsql;

-- Function to generate content recommendations
CREATE OR REPLACE FUNCTION generate_content_recommendations(
    target_user_id UUID,
    max_recommendations INTEGER DEFAULT 10
)
RETURNS TABLE (
    content_id UUID,
    recommendation_score DECIMAL(5,4),
    recommendation_reason VARCHAR(50)
) AS $$
BEGIN
    RETURN QUERY
    WITH user_preferences AS (
        SELECT * FROM user_content_preferences WHERE user_id = target_user_id
    ),
    user_history AS (
        -- User's viewing history and interactions
        SELECT
            ci.content_id,
            ci.category_id,
            ci.tags,
            ci.creator_id,
            COALESCE(cva.completion_percentage, 0) AS completion_rate,
            CASE WHEN ci2.interaction_id IS NOT NULL THEN 1 ELSE 0 END AS liked,
            ROW_NUMBER() OVER (ORDER BY cva.viewed_at DESC) AS recency_rank
        FROM content_items ci
        LEFT JOIN content_view_analytics cva ON ci.content_id = cva.content_id AND cva.user_id = target_user_id
        LEFT JOIN content_interactions ci2 ON ci.content_id = ci2.content_id
            AND ci2.user_id = target_user_id AND ci2.interaction_type = 'like'
        WHERE ci.status = 'published'
    ),
    content_candidates AS (
        -- Potential recommendations
        SELECT
            ci.content_id,
            ci.category_id,
            ci.tags,
            ci.creator_id,
            ci.average_rating,
            ci.view_count,
            calculate_engagement_score(ci.content_id) AS engagement_score
        FROM content_items ci
        WHERE ci.status = 'published'
          AND ci.visibility = 'public'
          AND ci.published_at >= CURRENT_DATE - INTERVAL '90 days'
          -- Exclude already viewed content
          AND NOT EXISTS (
              SELECT 1 FROM user_history uh
              WHERE uh.content_id = ci.content_id AND uh.completion_rate > 50
          )
    )
    SELECT
        cc.content_id,
        -- Calculate recommendation score based on multiple factors
        (
            -- Category preference (30%)
            CASE WHEN cc.category_id = ANY((SELECT preferred_categories FROM user_preferences)) THEN 0.3 ELSE 0 END +
            -- Tag overlap (25%)
            CASE WHEN cc.tags && (SELECT preferred_tags FROM user_preferences) THEN 0.25 ELSE 0 END +
            -- Creator following (20%)
            CASE WHEN cc.creator_id = ANY((SELECT preferred_creators FROM user_preferences)) THEN 0.2 ELSE 0 END +
            -- Content quality (15%)
            (cc.average_rating / 5.0) * 0.15 +
            -- Engagement/popularity (10%)
            LEAST(cc.engagement_score / 10.0, 0.1)
        )::DECIMAL(5,4) AS recommendation_score,
        CASE
            WHEN cc.category_id = ANY((SELECT preferred_categories FROM user_preferences)) THEN 'content_based'
            WHEN cc.creator_id = ANY((SELECT preferred_creators FROM user_preferences)) THEN 'creator_based'
            ELSE 'trending'
        END AS recommendation_reason
    FROM content_candidates cc
    ORDER BY recommendation_score DESC
    LIMIT max_recommendations;
END;
$$ LANGUAGE plpgsql;

-- Function to update user follower counts
CREATE OR REPLACE FUNCTION update_user_follower_counts()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Increment follower count for the followed user
        UPDATE users SET follower_count = follower_count + 1
        WHERE user_id = NEW.following_id AND NEW.relationship_type = 'follow';

        -- Increment following count for the follower
        UPDATE users SET following_count = following_count + 1
        WHERE user_id = NEW.follower_id AND NEW.relationship_type = 'follow';

    ELSIF TG_OP = 'DELETE' THEN
        -- Decrement follower count for the followed user
        UPDATE users SET follower_count = GREATEST(follower_count - 1, 0)
        WHERE user_id = OLD.following_id AND OLD.relationship_type = 'follow';

        -- Decrement following count for the follower
        UPDATE users SET following_count = GREATEST(following_count - 1, 0)
        WHERE user_id = OLD.follower_id AND OLD.relationship_type = 'follow';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger to maintain follower counts
CREATE TRIGGER trigger_update_follower_counts
    AFTER INSERT OR DELETE ON user_relationships
    FOR EACH ROW EXECUTE FUNCTION update_user_follower_counts();

-- Function to update content statistics
CREATE OR REPLACE FUNCTION update_content_stats(content_uuid UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE content_items
    SET
        like_count = (SELECT COUNT(*) FROM content_interactions WHERE content_id = content_uuid AND interaction_type = 'like'),
        dislike_count = (SELECT COUNT(*) FROM content_interactions WHERE content_id = content_uuid AND interaction_type = 'dislike'),
        share_count = (SELECT COUNT(*) FROM content_interactions WHERE content_id = content_uuid AND interaction_type = 'share'),
        comment_count = (SELECT COUNT(*) FROM content_comments WHERE content_id = content_uuid AND status = 'active'),
        bookmark_count = (SELECT COUNT(*) FROM user_bookmarks WHERE content_id = content_uuid),
        updated_at = CURRENT_TIMESTAMP
    WHERE content_id = content_uuid;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS FOR AUTOMATION
-- ============================================

-- Auto-update content engagement metrics
CREATE OR REPLACE FUNCTION update_content_engagement()
RETURNS TRIGGER AS $$
BEGIN
    -- Update content statistics
    PERFORM update_content_stats(NEW.content_id);

    -- Update average rating if it's a rating interaction
    IF NEW.interaction_type IN ('like', 'dislike') THEN
        UPDATE content_items
        SET average_rating = (
            SELECT AVG(
                CASE
                    WHEN ci.interaction_type = 'like' THEN 5.0
                    WHEN ci.interaction_type = 'dislike' THEN 1.0
                    ELSE 3.0
                END
            )
            FROM content_interactions ci
            WHERE ci.content_id = NEW.content_id
              AND ci.interaction_type IN ('like', 'dislike')
        )
        WHERE content_id = NEW.content_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_content_engagement
    AFTER INSERT OR UPDATE OR DELETE ON content_interactions
    FOR EACH ROW EXECUTE FUNCTION update_content_engagement();

-- Auto-update game statistics
CREATE OR REPLACE FUNCTION update_game_stats()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE games
    SET
        total_players = (SELECT COUNT(DISTINCT user_id) FROM user_game_library WHERE game_id = NEW.game_id),
        total_reviews = (SELECT COUNT(*) FROM content_reviews WHERE content_id IN (
            SELECT content_id FROM content_items WHERE metadata->>'game_id' = NEW.game_id::TEXT
        )),
        updated_at = CURRENT_TIMESTAMP
    WHERE game_id = NEW.game_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_game_stats
    AFTER INSERT OR UPDATE ON user_game_library
    FOR EACH ROW EXECUTE FUNCTION update_game_stats();

-- Auto-create recommendations for new content
CREATE OR REPLACE FUNCTION generate_content_recommendations_on_publish()
RETURNS TRIGGER AS $$
DECLARE
    rec_record RECORD;
BEGIN
    -- Only for newly published content
    IF NEW.status = 'published' AND (OLD IS NULL OR OLD.status != 'published') THEN
        -- Generate recommendations for active users (simplified - in production this would be more sophisticated)
        FOR rec_record IN
            SELECT user_id FROM users
            WHERE is_active = TRUE
            AND user_id != NEW.creator_id
            LIMIT 1000  -- Limit for performance
        LOOP
            INSERT INTO content_recommendations (
                user_id, content_id, recommendation_score, recommendation_reason
            ) VALUES (
                rec_record.user_id,
                NEW.content_id,
                0.5, -- Base score, would be calculated based on user preferences
                'new_content'
            )
            ON CONFLICT (user_id, content_id, generated_at::DATE)
            DO NOTHING;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_recommendations
    AFTER INSERT OR UPDATE ON content_items
    FOR EACH ROW EXECUTE FUNCTION generate_content_recommendations_on_publish();
