# Entertainment Platform Schema Design

## Overview

This comprehensive entertainment platform schema supports streaming services, gaming platforms, social media features, and content management systems. The design handles video streaming, user-generated content, gaming mechanics, live streaming, social interactions, and advanced recommendation systems.

## Key Features

- **Multi-Content Support**: Videos, live streams, articles, games, music, podcasts
- **Gaming Platform**: Game library, achievements, leaderboards, session tracking
- **Live Streaming**: Real-time streaming with chat and analytics
- **Social Features**: Followers, direct messaging, content interactions
- **Recommendation Engine**: AI-powered content suggestions
- **Creator Economy**: Monetization, sponsorships, subscription tiers
- **Analytics**: Comprehensive user engagement and content performance metrics
- **Real-time Features**: Live chat, notifications, activity feeds

## Database Architecture

### Core Entities

#### User Management
```sql
-- Comprehensive user profiles with gaming and creator features
CREATE TABLE users (
    user_id UUID PRIMARY KEY,
    username VARCHAR(50) UNIQUE,
    display_name VARCHAR(100),
    gamer_tag VARCHAR(50) UNIQUE, -- Gaming identifier
    is_creator BOOLEAN DEFAULT FALSE,
    subscription_tier VARCHAR(20), -- 'free', 'basic', 'premium'
    -- ... comprehensive user data
);

-- Flexible user preferences
CREATE TABLE user_preferences (
    user_id UUID REFERENCES users(user_id),
    notification_settings JSONB,
    privacy_settings JSONB,
    content_filters JSONB,
    interface_settings JSONB
);
```

#### Content Management
```sql
-- Unified content model for all media types
CREATE TABLE content_items (
    content_id UUID PRIMARY KEY,
    title VARCHAR(300),
    content_type VARCHAR(20), -- 'video', 'live_stream', 'game', 'article'
    creator_id UUID REFERENCES users(user_id),
    category_id INTEGER REFERENCES content_categories(category_id),
    tags TEXT[] DEFAULT '{}',
    status VARCHAR(20), -- 'draft', 'published', 'archived'
    monetization_type VARCHAR(20), -- 'ads', 'subscription', 'paywall'
    -- ... comprehensive content metadata
);

-- Content categorization with hierarchy
CREATE TABLE content_categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE,
    parent_category_id INTEGER REFERENCES content_categories(category_id),
    allowed_content_types TEXT[], -- Restrict content types per category
    -- ... category metadata
);
```

### Streaming & Media

#### Live Streaming
```sql
-- Live stream management
CREATE TABLE live_streams (
    stream_id UUID PRIMARY KEY,
    content_id UUID REFERENCES content_items(content_id),
    streamer_id UUID REFERENCES users(user_id),
    stream_key VARCHAR(100) UNIQUE,
    status VARCHAR(20), -- 'scheduled', 'live', 'ended'
    rtmp_url VARCHAR(500),
    hls_url VARCHAR(500),
    chat_enabled BOOLEAN DEFAULT TRUE,
    -- ... stream configuration
);

-- Real-time viewer analytics
CREATE TABLE stream_viewers (
    viewer_session_id UUID PRIMARY KEY,
    stream_id UUID REFERENCES live_streams(stream_id),
    user_id UUID REFERENCES users(user_id),
    joined_at TIMESTAMP WITH TIME ZONE,
    left_at TIMESTAMP WITH TIME ZONE,
    watch_duration_seconds INTEGER,
    -- ... engagement metrics
);
```

#### Media Processing
```sql
-- Multiple quality versions for adaptive streaming
ALTER TABLE content_items
ADD COLUMN streaming_urls JSONB DEFAULT '{}';

-- Example streaming URLs structure
{
  "1080p": "https://cdn.example.com/video_1080p.m3u8",
  "720p": "https://cdn.example.com/video_720p.m3u8",
  "480p": "https://cdn.example.com/video_480p.m3u8",
  "audio_only": "https://cdn.example.com/audio_only.m3u8"
}
```

### Gaming Features

#### Game Catalog
```sql
-- Comprehensive game metadata
CREATE TABLE games (
    game_id UUID PRIMARY KEY,
    title VARCHAR(200) UNIQUE,
    developer VARCHAR(100),
    genres TEXT[] DEFAULT '{}',
    platforms TEXT[] DEFAULT '{}', -- 'pc', 'console', 'mobile'
    age_rating VARCHAR(10), -- 'everyone', 'teen', 'mature'
    base_price_cents INTEGER,
    -- ... game details
);

-- User game library with ownership tracking
CREATE TABLE user_game_library (
    library_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    game_id UUID REFERENCES games(game_id),
    ownership_type VARCHAR(20), -- 'purchased', 'subscription'
    last_played_at TIMESTAMP WITH TIME ZONE,
    total_playtime_hours DECIMAL(8,2),
    achievements_unlocked INTEGER,
    -- ... gaming progress
);
```

#### Achievement System
```sql
-- Flexible achievement framework
CREATE TABLE achievements (
    achievement_id SERIAL PRIMARY KEY,
    game_id UUID REFERENCES games(game_id),
    name VARCHAR(100),
    criteria JSONB NOT NULL, -- Flexible achievement requirements
    rarity VARCHAR(10), -- 'common', 'rare', 'epic', 'legendary'
    points_reward INTEGER DEFAULT 0,
    -- ... achievement metadata
);

-- User achievements with progress tracking
CREATE TABLE user_achievements (
    user_achievement_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    achievement_id INTEGER REFERENCES achievements(achievement_id),
    earned_at TIMESTAMP WITH TIME ZONE,
    progress_percentage DECIMAL(5,2) DEFAULT 100.00,
);
```

#### Leaderboards
```sql
-- Dynamic leaderboard system
CREATE TABLE leaderboards (
    leaderboard_id SERIAL PRIMARY KEY,
    game_id UUID REFERENCES games(game_id),
    name VARCHAR(100),
    metric_type VARCHAR(30), -- 'score', 'time', 'wins'
    reset_period VARCHAR(20), -- 'daily', 'weekly', 'monthly'
    max_entries INTEGER DEFAULT 1000,
    -- ... leaderboard configuration
);

-- Leaderboard entries with ranking
CREATE TABLE leaderboard_entries (
    entry_id UUID PRIMARY KEY,
    leaderboard_id INTEGER REFERENCES leaderboards(leaderboard_id),
    user_id UUID REFERENCES users(user_id),
    score_value DECIMAL(15,2),
    rank INTEGER,
    -- ... ranking data
);
```

### Social Features

#### Relationships & Following
```sql
-- Multi-type user relationships
CREATE TABLE user_relationships (
    relationship_id UUID PRIMARY KEY,
    follower_id UUID REFERENCES users(user_id),
    following_id UUID REFERENCES users(user_id),
    relationship_type VARCHAR(20), -- 'follow', 'friend', 'block'
    status VARCHAR(20), -- 'pending', 'active'
    -- ... relationship metadata
);

-- Prevent self-following
ALTER TABLE user_relationships
ADD CONSTRAINT chk_self_relationship CHECK (follower_id != following_id);
```

#### Messaging System
```sql
-- Chat conversations with multiple types
CREATE TABLE chat_conversations (
    conversation_id UUID PRIMARY KEY,
    conversation_type VARCHAR(20), -- 'direct', 'group', 'channel'
    title VARCHAR(100), -- For group chats
    created_by UUID REFERENCES users(user_id),
    -- ... conversation settings
);

-- Message threading and reactions
CREATE TABLE chat_messages (
    message_id UUID PRIMARY KEY,
    conversation_id UUID REFERENCES chat_conversations(conversation_id),
    sender_id UUID REFERENCES users(user_id),
    content TEXT,
    message_type VARCHAR(20), -- 'text', 'image', 'system'
    parent_message_id UUID, -- For threading
    reaction_counts JSONB DEFAULT '{}',
    -- ... message metadata
) PARTITION BY RANGE (sent_at);
```

### Engagement & Interactions

#### Content Interactions
```sql
-- Unified interaction system
CREATE TABLE content_interactions (
    interaction_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    content_id UUID REFERENCES content_items(content_id),
    interaction_type VARCHAR(20), -- 'like', 'dislike', 'love', 'share'
    weight INTEGER DEFAULT 1, -- For ranking algorithms
    -- ... interaction context
);

-- Prevent duplicate interactions
ALTER TABLE content_interactions
ADD CONSTRAINT unique_user_content_interaction
UNIQUE (user_id, content_id, interaction_type);
```

#### Comments & Discussions
```sql
-- Threaded comment system
CREATE TABLE content_comments (
    comment_id UUID PRIMARY KEY,
    content_id UUID REFERENCES content_items(content_id),
    user_id UUID REFERENCES users(user_id),
    parent_comment_id UUID REFERENCES content_comments(comment_id),
    comment_text TEXT,
    status VARCHAR(20), -- 'active', 'flagged', 'removed'
    like_count INTEGER DEFAULT 0,
    -- ... comment metadata
);

-- Enforce maximum reply depth
ALTER TABLE content_comments
ADD CONSTRAINT chk_reply_depth CHECK (
    parent_comment_id IS NULL OR
    (SELECT parent_comment_id FROM content_comments
     WHERE comment_id = content_comments.parent_comment_id) IS NULL
);
```

### Recommendation System

#### User Preferences
```sql
-- Detailed user preference tracking
CREATE TABLE user_content_preferences (
    preference_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    preferred_categories INTEGER[] DEFAULT '{}',
    preferred_tags TEXT[] DEFAULT '{}',
    preferred_creators UUID[] DEFAULT '{}',
    preferred_genres TEXT[] DEFAULT '{}', -- Gaming preferences
    -- ... comprehensive preferences
);

-- Content similarity for recommendations
CREATE TABLE content_similarity (
    similarity_id UUID PRIMARY KEY,
    content_id_1 UUID REFERENCES content_items(content_id),
    content_id_2 UUID REFERENCES content_items(content_id),
    similarity_score DECIMAL(5,4),
    similarity_factors JSONB DEFAULT '{}',
    -- ... similarity metadata
);
```

#### Personalized Recommendations
```sql
-- Recommendation storage with scoring
CREATE TABLE content_recommendations (
    recommendation_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    content_id UUID REFERENCES content_items(content_id),
    recommendation_score DECIMAL(5,4),
    recommendation_reason VARCHAR(50), -- 'collaborative', 'content_based'
    algorithm_version VARCHAR(20),
    expires_at TIMESTAMP WITH TIME ZONE,
    -- ... recommendation metadata
);

-- Clean up expired recommendations
CREATE OR REPLACE FUNCTION cleanup_expired_recommendations()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM content_recommendations
    WHERE expires_at < CURRENT_TIMESTAMP;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;
```

### Monetization

#### Subscription Tiers
```sql
-- Flexible subscription model
CREATE TABLE subscription_tiers (
    tier_id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE,
    price_cents INTEGER,
    billing_cycle VARCHAR(20), -- 'monthly', 'yearly'
    benefits JSONB NOT NULL, -- {"ad_free": true, "early_access": true}
    max_concurrent_streams INTEGER DEFAULT 1,
    -- ... tier configuration
);

-- User subscriptions with billing
CREATE TABLE user_subscriptions (
    subscription_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    tier_id INTEGER REFERENCES subscription_tiers(tier_id),
    status VARCHAR(20), -- 'active', 'cancelled', 'past_due'
    current_period_end TIMESTAMP WITH TIME ZONE,
    cancel_at_period_end BOOLEAN DEFAULT FALSE,
    -- ... subscription management
);
```

#### Creator Sponsorships
```sql
-- Brand deal management
CREATE TABLE creator_sponsorships (
    sponsorship_id UUID PRIMARY KEY,
    creator_id UUID REFERENCES users(user_id),
    brand_name VARCHAR(100),
    campaign_name VARCHAR(200),
    sponsorship_type VARCHAR(30), -- 'product_placement', 'paid_promotion'
    contract_start_date DATE,
    contract_end_date DATE,
    total_compensation_cents INTEGER,
    -- ... sponsorship terms
);
```

## Advanced Features

### Real-Time Analytics

```sql
-- Comprehensive view analytics
CREATE TABLE content_view_analytics (
    analytics_id UUID PRIMARY KEY,
    content_id UUID REFERENCES content_items(content_id),
    user_id UUID REFERENCES users(user_id),
    viewed_at TIMESTAMP WITH TIME ZONE,
    watch_duration_seconds INTEGER,
    completion_percentage DECIMAL(5,2),
    source VARCHAR(50), -- 'direct', 'recommendation', 'search'
    device_type VARCHAR(20), -- 'desktop', 'mobile', 'tv'
    -- ... detailed analytics
) PARTITION BY RANGE (viewed_at);

-- Real-time creator analytics
CREATE TABLE creator_analytics (
    analytics_id UUID PRIMARY KEY,
    creator_id UUID REFERENCES users(user_id),
    date DATE,
    videos_uploaded INTEGER DEFAULT 0,
    total_views BIGINT DEFAULT 0,
    total_watch_time_hours DECIMAL(10,2) DEFAULT 0.00,
    new_subscribers INTEGER DEFAULT 0,
    ad_revenue_cents INTEGER DEFAULT 0,
    -- ... comprehensive metrics
) PARTITION BY RANGE (date);
```

### Activity Feeds

```sql
-- Unified activity feed generation
CREATE VIEW user_activity_feed AS
SELECT
    'content_created' AS activity_type,
    ci.creator_id AS user_id,
    ci.content_id AS entity_id,
    ci.title AS entity_title,
    ci.published_at AS activity_timestamp,
    ci.thumbnail_url AS entity_image,
    JSON_BUILD_OBJECT('content_type', ci.content_type) AS metadata
FROM content_items ci
WHERE ci.status = 'published'

UNION ALL

SELECT
    'achievement_unlocked' AS activity_type,
    ua.user_id,
    ua.achievement_id::TEXT AS entity_id,
    a.name AS entity_title,
    ua.earned_at AS activity_timestamp,
    a.icon_url AS entity_image,
    JSON_BUILD_OBJECT('game_id', a.game_id) AS metadata
FROM user_achievements ua
JOIN achievements a ON ua.achievement_id = a.achievement_id

ORDER BY activity_timestamp DESC;
```

### Gaming Session Tracking

```sql
-- Detailed gaming session analytics
CREATE TABLE game_sessions (
    session_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    game_id UUID REFERENCES games(game_id),
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER,
    score INTEGER,
    level_reached INTEGER,
    experience_gained INTEGER,
    -- ... session details
);

-- Update user gaming statistics
CREATE OR REPLACE FUNCTION update_user_gaming_stats()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE user_game_library
    SET
        last_played_at = NEW.ended_at,
        total_playtime_hours = total_playtime_hours + (NEW.duration_minutes / 60.0),
        updated_at = CURRENT_TIMESTAMP
    WHERE user_id = NEW.user_id AND game_id = NEW.game_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_gaming_stats
    AFTER INSERT ON game_sessions
    FOR EACH ROW EXECUTE FUNCTION update_user_gaming_stats();
```

## Usage Examples

### Content Publishing Workflow

```sql
-- Complete content publishing process
BEGIN;

-- Create content item
INSERT INTO content_items (
    title, description, content_type, creator_id, category_id,
    status, visibility, tags, duration_seconds
) VALUES (
    'Amazing Gaming Tutorial', 'Learn advanced strategies...',
    'video', 'creator-uuid', 1, 'published', 'public',
    ARRAY['gaming', 'tutorial', 'strategy'], 1800
) RETURNING content_id INTO content_id_var;

-- Set streaming URLs for different qualities
UPDATE content_items
SET streaming_urls = '{
    "1080p": "https://cdn.example.com/tutorial_1080p.m3u8",
    "720p": "https://cdn.example.com/tutorial_720p.m3u8",
    "480p": "https://cdn.example.com/tutorial_480p.m3u8"
}'::jsonb
WHERE content_id = content_id_var;

-- Generate initial recommendations
SELECT generate_content_recommendations('creator-uuid');

COMMIT;
```

### Gaming Achievement System

```sql
-- Award achievement based on game performance
INSERT INTO user_achievements (user_id, achievement_id, game_id)
SELECT
    gs.user_id,
    a.achievement_id,
    gs.game_id
FROM game_sessions gs
CROSS JOIN achievements a
WHERE gs.user_id = 'player-uuid'
  AND gs.score >= (a.criteria->>'min_score')::INTEGER
  AND a.game_id = gs.game_id
  AND NOT EXISTS (
      SELECT 1 FROM user_achievements ua
      WHERE ua.user_id = gs.user_id AND ua.achievement_id = a.achievement_id
  );
```

### Live Streaming Session

```sql
-- Start a live stream
INSERT INTO live_streams (
    content_id, streamer_id, stream_key, title, category_id,
    scheduled_start, rtmp_url, hls_url
) VALUES (
    'content-uuid', 'streamer-uuid', 'unique-stream-key',
    'Live Gaming Session', 5, CURRENT_TIMESTAMP,
    'rtmp://stream.example.com/live', 'https://cdn.example.com/live.m3u8'
) RETURNING stream_id INTO stream_id_var;

-- Update stream status to live
UPDATE live_streams
SET status = 'live', actual_start = CURRENT_TIMESTAMP
WHERE stream_id = stream_id_var;

-- Track viewer joining
INSERT INTO stream_viewers (stream_id, user_id, joined_at)
VALUES (stream_id_var, 'viewer-uuid', CURRENT_TIMESTAMP);
```

### Recommendation Engine

```sql
-- Generate personalized recommendations
SELECT
    cr.content_id,
    ci.title,
    ci.thumbnail_url,
    cr.recommendation_score,
    cr.recommendation_reason
FROM generate_content_recommendations('user-uuid', 20) cr
JOIN content_items ci ON cr.content_id = ci.content_id
ORDER BY cr.recommendation_score DESC;
```

## Performance Optimizations

### Strategic Indexing

```sql
-- Content search and filtering
CREATE INDEX idx_content_items_creator_status ON content_items (creator_id, status);
CREATE INDEX idx_content_items_category_published ON content_items (category_id, published_at DESC);
CREATE INDEX idx_content_items_search ON content_items USING GIN (search_vector);

-- Social features
CREATE INDEX idx_user_relationships_follower_type ON user_relationships (follower_id, relationship_type);
CREATE INDEX idx_chat_messages_conversation_sent ON chat_messages (conversation_id, sent_at DESC);

-- Gaming performance
CREATE INDEX idx_game_sessions_user_started ON game_sessions (user_id, started_at DESC);
CREATE INDEX idx_leaderboard_entries_leaderboard_rank ON leaderboard_entries (leaderboard_id, rank);

-- Analytics
CREATE INDEX idx_content_view_analytics_content_viewed ON content_view_analytics (content_id, viewed_at DESC);
CREATE INDEX idx_creator_analytics_creator_date ON creator_analytics (creator_id, date DESC);
```

### Partitioning Strategy

```sql
-- Time-based partitioning for high-volume tables
CREATE TABLE chat_messages PARTITION BY RANGE (sent_at);
CREATE TABLE content_view_analytics PARTITION BY RANGE (viewed_at);
CREATE TABLE creator_analytics PARTITION BY RANGE (date);

-- Monthly partitions for chat messages
CREATE TABLE chat_messages_2024_01 PARTITION OF chat_messages FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE chat_messages_2024_02 PARTITION OF chat_messages FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
```

### Caching Strategy

```sql
-- Materialized view for popular content
CREATE MATERIALIZED VIEW trending_content AS
SELECT
    ci.content_id,
    ci.title,
    ci.thumbnail_url,
    ci.creator_id,
    u.display_name AS creator_name,
    ci.view_count,
    ci.like_count,
    ci.average_rating,
    calculate_engagement_score(ci.content_id) AS engagement_score,
    ROW_NUMBER() OVER (ORDER BY calculate_engagement_score(ci.content_id) DESC) AS trending_rank
FROM content_items ci
JOIN users u ON ci.creator_id = u.user_id
WHERE ci.status = 'published'
  AND ci.published_at >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY engagement_score DESC
LIMIT 100;

-- Refresh every hour
REFRESH MATERIALIZED VIEW CONCURRENTLY trending_content;
```

## Security Considerations

### Content Moderation

```sql
-- Automated content flagging system
CREATE TABLE content_moderation_flags (
    flag_id UUID PRIMARY KEY,
    content_id UUID REFERENCES content_items(content_id),
    flagged_by UUID REFERENCES users(user_id),
    flag_reason VARCHAR(50), -- 'inappropriate', 'spam', 'copyright'
    severity VARCHAR(10), -- 'low', 'medium', 'high'
    status VARCHAR(20), -- 'pending', 'reviewed', 'resolved'
    reviewed_by UUID REFERENCES users(user_id),
    -- ... moderation workflow
);
```

### Access Control

```sql
-- Row-level security for content visibility
ALTER TABLE content_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY content_visibility_policy ON content_items
    FOR SELECT USING (
        status = 'published' AND (
            visibility = 'public' OR
            (visibility = 'subscribers_only' AND is_subscriber(current_user_id())) OR
            creator_id = current_user_id()
        )
    );
```

## Integration Points

### External Systems
- **Content delivery networks** (CDN) for global media streaming and distribution
- **Video encoding services** for multi-format transcoding and optimization
- **Payment processors** (Stripe, PayPal) for subscription and paywall management
- **Social media APIs** for cross-platform content sharing and engagement
- **Analytics platforms** (Google Analytics, Mixpanel) for user behavior tracking
- **DRM systems** for content protection and digital rights management
- **Ad servers** for programmatic advertising and monetization

### API Endpoints
- **Content management APIs** for upload, processing, and publishing workflows
- **Streaming APIs** for real-time content delivery and adaptive bitrate streaming
- **User engagement APIs** for likes, comments, shares, and social interactions
- **Recommendation APIs** for personalized content discovery and algorithms
- **Analytics APIs** for performance metrics and business intelligence
- **Monetization APIs** for subscription management and revenue tracking

## Monitoring & Analytics

### Key Performance Indicators
- **Content engagement metrics** (views, watch time, completion rates, shares)
- **User acquisition and retention** (subscriber growth, churn rates, lifetime value)
- **Content performance** (top-performing videos, trending topics, audience demographics)
- **Platform health** (streaming quality, uptime, error rates)
- **Monetization effectiveness** (subscription revenue, ad impressions, conversion rates)

### Real-Time Dashboards
```sql
-- Entertainment platform analytics dashboard
CREATE VIEW entertainment_analytics_dashboard AS
SELECT
    -- Content performance (last 7 days)
    (SELECT COUNT(*) FROM content_views WHERE viewed_at >= CURRENT_DATE - INTERVAL '7 days') as total_views_week,
    (SELECT SUM(watch_duration_seconds) FROM content_views WHERE viewed_at >= CURRENT_DATE - INTERVAL '7 days') / 3600 as total_watch_hours_week,
    (SELECT AVG(watch_duration_seconds::DECIMAL / NULLIF(ci.duration_seconds, 0))
     FROM content_views cv
     JOIN content_items ci ON cv.content_id = ci.content_id
     WHERE cv.viewed_at >= CURRENT_DATE - INTERVAL '7 days') as avg_completion_rate,

    -- User engagement
    (SELECT COUNT(*) FROM user_interactions WHERE interaction_date >= CURRENT_DATE - INTERVAL '7 days') as total_interactions_week,
    (SELECT COUNT(DISTINCT user_id) FROM user_sessions WHERE session_date >= CURRENT_DATE - INTERVAL '7 days') as active_users_week,
    (SELECT COUNT(*) FROM subscriptions WHERE subscription_date >= CURRENT_DATE - INTERVAL '7 days') as new_subscriptions_week,

    -- Content creation
    (SELECT COUNT(*) FROM content_items WHERE created_at >= CURRENT_DATE - INTERVAL '7 days') as content_uploaded_week,
    (SELECT COUNT(DISTINCT creator_id) FROM content_items WHERE created_at >= CURRENT_DATE - INTERVAL '7 days') as active_creators_week,
    (SELECT AVG(rating) FROM content_reviews WHERE created_at >= CURRENT_DATE - INTERVAL '7 days') as avg_content_rating,

    -- Gaming metrics (if applicable)
    (SELECT COUNT(*) FROM game_sessions WHERE session_date >= CURRENT_DATE - INTERVAL '7 days') as gaming_sessions_week,
    (SELECT AVG(score) FROM game_sessions WHERE session_date >= CURRENT_DATE - INTERVAL '7 days') as avg_game_score,
    (SELECT COUNT(*) FROM user_achievements WHERE unlocked_at >= CURRENT_DATE - INTERVAL '7 days') as achievements_unlocked_week,

    -- Revenue metrics
    (SELECT COALESCE(SUM(amount), 0) FROM subscription_payments WHERE payment_date >= CURRENT_DATE - INTERVAL '30 days') as subscription_revenue_month,
    (SELECT COUNT(*) FROM ad_impressions WHERE served_at >= CURRENT_DATE - INTERVAL '7 days') as ad_impressions_week,
    (SELECT COUNT(*) FROM purchases WHERE purchase_date >= CURRENT_DATE - INTERVAL '7 days') as digital_purchases_week,

    -- Platform health
    (SELECT COUNT(*) FROM support_tickets WHERE ticket_status = 'open') as open_support_tickets,
    (SELECT AVG(EXTRACT(EPOCH FROM (resolved_at - created_at))/3600)
     FROM support_tickets WHERE resolved_at IS NOT NULL AND created_at >= CURRENT_DATE - INTERVAL '30 days') as avg_resolution_time_hours,

    -- Quality metrics
    (SELECT AVG(overall_rating) FROM content_reviews WHERE created_at >= CURRENT_DATE - INTERVAL '30 days') as avg_user_satisfaction,
    (SELECT COUNT(*) FROM content_flags WHERE status = 'pending' AND flagged_at >= CURRENT_DATE - INTERVAL '7 days') as content_flags_week,
    (SELECT COUNT(*) FROM stream_issues WHERE occurred_at >= CURRENT_DATE - INTERVAL '7 days') as streaming_issues_week,

    -- Growth metrics
    (SELECT COUNT(DISTINCT user_id) FROM user_registrations WHERE registration_date >= CURRENT_DATE - INTERVAL '30 days') as new_users_month,
    (SELECT COUNT(DISTINCT creator_id) FROM creator_applications WHERE applied_at >= CURRENT_DATE - INTERVAL '30 days') as new_creators_month,
    (SELECT AVG(daily_active_users) FROM (
        SELECT COUNT(DISTINCT user_id) as daily_active_users
        FROM user_sessions
        WHERE session_date >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY session_date
    ) dau) as avg_daily_active_users

FROM dual; -- Use a dummy table for single-row result
```

This entertainment platform schema provides a comprehensive foundation for building modern streaming services, gaming platforms, and social media applications with advanced features like real-time interactions, recommendation engines, and comprehensive analytics.
