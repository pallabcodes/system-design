-- Entertainment Industry Database Schema (MySQL)
-- Comprehensive schema for movies, TV, streaming, and live entertainment
-- Adapted for MySQL with JSON support, fulltext search, and performance optimizations

-- ===========================================
-- CONTENT MANAGEMENT
-- ===========================================

CREATE TABLE content (
    content_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    content_type ENUM('movie', 'tv_series', 'tv_episode', 'documentary', 'short_film', 'web_series', 'music_video', 'live_event') NOT NULL,

    -- Basic information
    title VARCHAR(500) NOT NULL,
    original_title VARCHAR(500),
    description LONGTEXT,

    -- Classification
    genres JSON DEFAULT ('[]'),
    subgenres JSON DEFAULT ('[]'),
    content_rating ENUM('G', 'PG', 'PG-13', 'R', 'NC-17', 'TV-Y', 'TV-Y7', 'TV-G', 'TV-PG', 'TV-14', 'TV-MA') DEFAULT 'PG-13',

    -- Production details
    release_date DATE,
    production_year YEAR,
    production_country VARCHAR(100),
    languages JSON DEFAULT ('["English"]'),  -- Multiple languages
    runtime_minutes INT,

    -- Creative credits
    director_id CHAR(36),
    producer_ids JSON DEFAULT ('[]'),
    writer_ids JSON DEFAULT ('[]'),

    -- Financial
    budget DECIMAL(15,2),
    box_office_gross DECIMAL(15,2),

    -- Status and workflow
    content_status ENUM('development', 'pre_production', 'production', 'post_production', 'completed', 'released', 'cancelled') DEFAULT 'development',

    -- Metadata
    imdb_id VARCHAR(20),
    tmdb_id VARCHAR(20),
    keywords JSON DEFAULT ('[]'),
    tags JSON DEFAULT ('[]'),

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by CHAR(36),

    INDEX idx_content_type (content_type),
    INDEX idx_content_release (release_date),
    INDEX idx_content_status (content_status),
    INDEX idx_content_rating (content_rating),
    FULLTEXT INDEX ft_content_title_desc (title, description),
    FULLTEXT INDEX ft_content_keywords (keywords)
) ENGINE = InnoDB;

-- TV Series specific table
CREATE TABLE tv_series (
    series_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    content_id CHAR(36) NOT NULL UNIQUE,

    -- Series details
    total_seasons INT DEFAULT 1,
    total_episodes INT DEFAULT 0,
    episode_runtime_avg INT,
    network VARCHAR(255),  -- Original network
    status ENUM('returning_series', 'ended', 'cancelled', 'in_production', 'planned') DEFAULT 'in_production',

    -- Seasons tracking
    current_season INT DEFAULT 1,
    last_episode_aired DATE,

    -- Franchise info
    franchise_name VARCHAR(255),
    spin_off_of CHAR(36),  -- Reference to another series

    FOREIGN KEY (content_id) REFERENCES content(content_id) ON DELETE CASCADE,
    FOREIGN KEY (spin_off_of) REFERENCES tv_series(series_id),

    INDEX idx_series_network (network),
    INDEX idx_series_status (status),
    INDEX idx_series_franchise (franchise_name)
) ENGINE = InnoDB;

-- TV Episodes
CREATE TABLE tv_episodes (
    episode_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    content_id CHAR(36) NOT NULL,
    series_id CHAR(36) NOT NULL,

    -- Episode details
    season_number INT NOT NULL,
    episode_number INT NOT NULL,
    episode_title VARCHAR(500) NOT NULL,
    episode_description TEXT,

    -- Timing
    air_date DATE,
    runtime_minutes INT,

    -- Guest stars and credits
    guest_stars JSON DEFAULT ('[]'),
    director_id CHAR(36),
    writer_ids JSON DEFAULT ('[]'),

    -- Ratings and viewership
    viewer_rating DECIMAL(3,1),
    viewer_count BIGINT,

    UNIQUE KEY unique_episode (series_id, season_number, episode_number),

    FOREIGN KEY (content_id) REFERENCES content(content_id) ON DELETE CASCADE,
    FOREIGN KEY (series_id) REFERENCES tv_series(series_id) ON DELETE CASCADE,

    INDEX idx_episodes_series_season (series_id, season_number),
    INDEX idx_episodes_air_date (air_date),
    FULLTEXT INDEX ft_episodes_title_desc (episode_title, episode_description)
) ENGINE = InnoDB;

-- ===========================================
-- TALENT MANAGEMENT
-- ===========================================

CREATE TABLE talent (
    talent_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    talent_type ENUM('actor', 'director', 'writer', 'producer', 'composer', 'cinematographer', 'editor', 'sound_designer', 'costume_designer', 'makeup_artist', 'stunt_coordinator', 'other') NOT NULL,

    -- Personal information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    stage_name VARCHAR(200),
    date_of_birth DATE,
    nationality VARCHAR(100),
    biography TEXT,

    -- Contact and representation
    email VARCHAR(255),
    phone VARCHAR(20),
    agent_name VARCHAR(255),
    agent_contact VARCHAR(255),

    -- Professional details
    years_experience INT DEFAULT 0,
    primary_genres JSON DEFAULT ('[]'),
    skills JSON DEFAULT ('[]'),
    awards JSON DEFAULT ('[]'),

    -- Social media and online presence
    website VARCHAR(500),
    social_media JSON DEFAULT ('{}'),  -- {"instagram": "handle", "twitter": "handle"}

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    represented BOOLEAN DEFAULT FALSE,

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_talent_type (talent_type),
    INDEX idx_talent_active (is_active),
    INDEX idx_talent_name (last_name, first_name),
    FULLTEXT INDEX ft_talent_bio (biography, skills)
) ENGINE = InnoDB;

-- Roles and casting
CREATE TABLE content_roles (
    role_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    content_id CHAR(36) NOT NULL,
    talent_id CHAR(36) NOT NULL,

    -- Role details
    role_type ENUM('lead', 'supporting', 'cameo', 'voice', 'director', 'writer', 'producer', 'composer', 'crew') NOT NULL,
    character_name VARCHAR(255),  -- For actors
    role_title VARCHAR(255),      -- For crew (e.g., "Director of Photography")

    -- Compensation
    compensation DECIMAL(12,2),
    compensation_type ENUM('salary', 'percentage', 'daily_rate', 'per_diem') DEFAULT 'salary',

    -- Contract details
    contract_start_date DATE,
    contract_end_date DATE,
    contract_terms JSON DEFAULT ('{}'),

    -- Performance
    role_status ENUM('cast', 'confirmed', 'filming', 'completed', 'credited') DEFAULT 'cast',

    FOREIGN KEY (content_id) REFERENCES content(content_id) ON DELETE CASCADE,
    FOREIGN KEY (talent_id) REFERENCES talent(talent_id) ON DELETE CASCADE,

    INDEX idx_roles_content (content_id),
    INDEX idx_roles_talent (talent_id),
    INDEX idx_roles_type (role_type),
    INDEX idx_roles_status (role_status)
) ENGINE = InnoDB;

-- ===========================================
-- DISTRIBUTION AND PLATFORMS
-- ===========================================

CREATE TABLE platforms (
    platform_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    platform_name VARCHAR(255) NOT NULL,
    platform_type ENUM('streaming', 'theater', 'tv_network', 'cable', 'digital_rental', 'physical_media', 'festival') NOT NULL,

    -- Platform details
    website VARCHAR(500),
    headquarters_country VARCHAR(100),
    launch_date DATE,

    -- Business model
    business_model ENUM('subscription', 'advertising', 'transactional', 'hybrid') DEFAULT 'subscription',
    subscription_tiers JSON DEFAULT ('[]'),

    -- Technical specs
    supported_resolutions JSON DEFAULT ('["SD", "HD", "4K"]'),
    supported_audio JSON DEFAULT ('["stereo", "5.1", "DOLBY_ATMOS"]'),

    -- Regional availability
    available_countries JSON DEFAULT ('[]'),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    INDEX idx_platforms_type (platform_type),
    INDEX idx_platforms_active (is_active),
    FULLTEXT INDEX ft_platforms_name (platform_name)
) ENGINE = InnoDB;

-- Content availability on platforms
CREATE TABLE content_availability (
    availability_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    content_id CHAR(36) NOT NULL,
    platform_id CHAR(36) NOT NULL,

    -- Availability window
    available_from TIMESTAMP NULL,
    available_until TIMESTAMP NULL,
    is_available BOOLEAN DEFAULT TRUE,

    -- Regional restrictions
    allowed_countries JSON DEFAULT ('[]'),
    blocked_countries JSON DEFAULT ('[]'),

    -- Pricing and licensing
    license_type ENUM('exclusive', 'non_exclusive', 'worldwide', 'territorial') DEFAULT 'non_exclusive',
    pricing_model ENUM('subscription_included', 'rental', 'purchase', 'advertising') DEFAULT 'subscription_included',

    -- Quality and features
    max_resolution ENUM('SD', 'HD', '4K', '8K') DEFAULT 'HD',
    has_subtitles BOOLEAN DEFAULT TRUE,
    has_dubs BOOLEAN DEFAULT FALSE,
    audio_languages JSON DEFAULT ('["English"]'),

    FOREIGN KEY (content_id) REFERENCES content(content_id) ON DELETE CASCADE,
    FOREIGN KEY (platform_id) REFERENCES platforms(platform_id) ON DELETE CASCADE,

    UNIQUE KEY unique_content_platform (content_id, platform_id),

    INDEX idx_availability_content (content_id),
    INDEX idx_availability_platform (platform_id),
    INDEX idx_availability_available (is_available),
    INDEX idx_availability_until (available_until)
) ENGINE = InnoDB;

-- ===========================================
-- VIEWERSHIP AND ANALYTICS
-- ===========================================

CREATE TABLE viewing_sessions (
    session_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    user_id CHAR(36),  -- NULL for anonymous viewers
    content_id CHAR(36) NOT NULL,
    platform_id CHAR(36) NOT NULL,

    -- Session details
    session_start TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_end TIMESTAMP NULL,
    duration_seconds INT NULL,
    completion_percentage DECIMAL(5,2) DEFAULT 0,

    -- Device and location
    device_type ENUM('mobile', 'tablet', 'desktop', 'smart_tv', 'console', 'other') DEFAULT 'desktop',
    device_os VARCHAR(50),
    ip_address VARCHAR(45),
    country_code CHAR(2),
    region VARCHAR(100),

    -- Viewing quality
    resolution_used ENUM('SD', 'HD', '4K', '8K') DEFAULT 'HD',
    buffering_events INT DEFAULT 0,
    quality_switches INT DEFAULT 0,

    -- Engagement metrics
    pause_count INT DEFAULT 0,
    rewind_seconds INT DEFAULT 0,
    fast_forward_seconds INT DEFAULT 0,

    FOREIGN KEY (content_id) REFERENCES content(content_id) ON DELETE CASCADE,
    FOREIGN KEY (platform_id) REFERENCES platforms(platform_id) ON DELETE CASCADE,

    INDEX idx_sessions_user (user_id),
    INDEX idx_sessions_content (content_id),
    INDEX idx_sessions_platform (platform_id),
    INDEX idx_sessions_start (session_start),
    INDEX idx_sessions_country (country_code)
) ENGINE = InnoDB;

-- Reviews and ratings
CREATE TABLE reviews (
    review_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    user_id CHAR(36),  -- NULL for anonymous reviews
    content_id CHAR(36) NOT NULL,
    platform_id CHAR(36) NULL,

    -- Review content
    rating DECIMAL(3,1) CHECK (rating >= 1 AND rating <= 10),
    review_title VARCHAR(255),
    review_text LONGTEXT,
    is_critic_review BOOLEAN DEFAULT FALSE,

    -- Review metadata
    helpful_votes INT DEFAULT 0,
    total_votes INT DEFAULT 0,
    review_status ENUM('pending', 'approved', 'rejected', 'spam') DEFAULT 'approved',

    -- Spoiler and content warnings
    contains_spoilers BOOLEAN DEFAULT FALSE,
    content_warnings JSON DEFAULT ('[]'),

    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    moderated_by CHAR(36),
    moderated_at TIMESTAMP NULL,

    FOREIGN KEY (content_id) REFERENCES content(content_id) ON DELETE CASCADE,
    FOREIGN KEY (platform_id) REFERENCES platforms(platform_id) ON DELETE SET NULL,

    INDEX idx_reviews_content (content_id),
    INDEX idx_reviews_user (user_id),
    INDEX idx_reviews_rating (rating),
    INDEX idx_reviews_status (review_status),
    INDEX idx_reviews_created (created_at),
    FULLTEXT INDEX ft_reviews_title_text (review_title, review_text)
) ENGINE = InnoDB;

-- ===========================================
-- REVENUE AND MONETIZATION
-- ===========================================

CREATE TABLE revenue_streams (
    revenue_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    content_id CHAR(36) NOT NULL,
    platform_id CHAR(36) NULL,

    -- Revenue details
    revenue_type ENUM('subscription', 'rental', 'purchase', 'advertising', 'licensing', 'merchandise', 'theatrical', 'streaming') NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',

    -- Time period
    revenue_date DATE NOT NULL,
    fiscal_year YEAR,
    fiscal_quarter INT CHECK (fiscal_quarter >= 1 AND fiscal_quarter <= 4),

    -- Attribution
    viewer_count BIGINT,
    average_price DECIMAL(8,2),
    region VARCHAR(100),

    -- Cost breakdown
    production_cost DECIMAL(12,2) DEFAULT 0,
    distribution_cost DECIMAL(12,2) DEFAULT 0,
    marketing_cost DECIMAL(12,2) DEFAULT 0,
    net_revenue DECIMAL(12,2) GENERATED ALWAYS AS (amount - production_cost - distribution_cost - marketing_cost) STORED,

    FOREIGN KEY (content_id) REFERENCES content(content_id) ON DELETE CASCADE,
    FOREIGN KEY (platform_id) REFERENCES platforms(platform_id) ON DELETE SET NULL,

    INDEX idx_revenue_content (content_id),
    INDEX idx_revenue_platform (platform_id),
    INDEX idx_revenue_type (revenue_type),
    INDEX idx_revenue_date (revenue_date),
    INDEX idx_revenue_quarter (fiscal_year, fiscal_quarter)
) ENGINE = InnoDB;

-- ===========================================
-- VENUES AND LIVE EVENTS
-- ===========================================

CREATE TABLE venues (
    venue_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    venue_name VARCHAR(255) NOT NULL,
    venue_type ENUM('movie_theater', 'concert_hall', 'arena', 'festival_grounds', 'drive_in', 'indoor_theater', 'outdoor_amphitheater') NOT NULL,

    -- Location
    address_line_1 VARCHAR(255),
    address_line_2 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),

    -- Capacity and layout
    total_capacity INT,
    seating_capacity INT,
    standing_capacity INT,
    wheelchair_accessible BOOLEAN DEFAULT TRUE,

    -- Technical specifications
    screen_count INT DEFAULT 1,
    projection_system VARCHAR(100),
    sound_system VARCHAR(100),
    stage_size_sqm DECIMAL(8,2),

    -- Business details
    owner_name VARCHAR(255),
    management_company VARCHAR(255),
    website VARCHAR(500),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    last_renovation_date DATE,

    INDEX idx_venues_type (venue_type),
    INDEX idx_venues_city (city, state_province),
    INDEX idx_venues_active (is_active),
    SPATIAL INDEX idx_venues_location (POINT(latitude, longitude))
) ENGINE = InnoDB;

-- Events and performances
CREATE TABLE events (
    event_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    content_id CHAR(36) NULL,  -- Link to content if applicable
    venue_id CHAR(36) NOT NULL,

    -- Event details
    event_name VARCHAR(500) NOT NULL,
    event_type ENUM('movie_screening', 'live_performance', 'concert', 'theater', 'comedy_show', 'award_ceremony', 'festival', 'other') NOT NULL,
    event_description LONGTEXT,

    -- Schedule
    event_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NULL,
    duration_minutes INT GENERATED ALWAYS AS (
        CASE
            WHEN end_time IS NOT NULL THEN TIMESTAMPDIFF(MINUTE, CONCAT(event_date, ' ', start_time), CONCAT(event_date, ' ', end_time))
            ELSE NULL
        END
    ) STORED,

    -- Capacity and pricing
    total_tickets INT,
    tickets_sold INT DEFAULT 0,
    ticket_price_avg DECIMAL(8,2),
    revenue_total DECIMAL(10,2) DEFAULT 0,

    -- Status
    event_status ENUM('scheduled', 'on_sale', 'sold_out', 'cancelled', 'postponed', 'completed') DEFAULT 'scheduled',

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (content_id) REFERENCES content(content_id) ON DELETE SET NULL,
    FOREIGN KEY (venue_id) REFERENCES venues(venue_id) ON DELETE CASCADE,

    INDEX idx_events_content (content_id),
    INDEX idx_events_venue (venue_id),
    INDEX idx_events_date (event_date),
    INDEX idx_events_type (event_type),
    INDEX idx_events_status (event_status)
) ENGINE = InnoDB;

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Composite indexes for common queries
CREATE INDEX idx_content_release_rating ON content (release_date DESC, content_rating);
CREATE INDEX idx_content_type_status ON content (content_type, content_status);
CREATE INDEX idx_episodes_series_season ON tv_episodes (series_id, season_number, episode_number);
CREATE INDEX idx_roles_content_talent ON content_roles (content_id, talent_id);
CREATE INDEX idx_availability_platform_available ON content_availability (platform_id, is_available);
CREATE INDEX idx_sessions_content_start ON viewing_sessions (content_id, session_start DESC);
CREATE INDEX idx_reviews_content_rating ON reviews (content_id, rating DESC);
CREATE INDEX idx_revenue_content_date ON revenue_streams (content_id, revenue_date DESC);
CREATE INDEX idx_events_venue_date ON events (venue_id, event_date);

-- ===========================================
-- STORED PROCEDURES FOR ENTERTAINMENT ANALYTICS
-- =========================================--

DELIMITER ;;

-- Get content performance analytics
CREATE PROCEDURE get_content_performance(IN content_uuid CHAR(36))
BEGIN
    -- Overall performance metrics
    SELECT
        c.title,
        c.content_type,
        c.release_date,
        c.budget,
        c.box_office_gross,

        -- Viewership metrics
        COUNT(vs.session_id) as total_viewing_sessions,
        AVG(vs.duration_seconds) as avg_watch_time_seconds,
        AVG(vs.completion_percentage) as avg_completion_percentage,

        -- Engagement metrics
        AVG(r.rating) as avg_user_rating,
        COUNT(r.review_id) as total_reviews,
        AVG(r.helpful_votes::DECIMAL / NULLIF(r.total_votes, 0)) as avg_review_helpfulness,

        -- Revenue metrics
        SUM(rs.amount) as total_revenue,
        SUM(rs.net_revenue) as net_revenue,
        AVG(rs.amount / NULLIF(rs.viewer_count, 0)) as revenue_per_viewer

    FROM content c
    LEFT JOIN viewing_sessions vs ON c.content_id = vs.content_id
    LEFT JOIN reviews r ON c.content_id = r.content_id AND r.review_status = 'approved'
    LEFT JOIN revenue_streams rs ON c.content_id = rs.content_id
    WHERE c.content_id = content_uuid
    GROUP BY c.content_id, c.title, c.content_type, c.release_date, c.budget, c.box_office_gross;

    -- Platform performance breakdown
    SELECT
        p.platform_name,
        p.platform_type,
        COUNT(vs.session_id) as sessions,
        AVG(vs.duration_seconds) as avg_watch_time,
        AVG(vs.completion_percentage) as completion_rate,
        COUNT(DISTINCT vs.user_id) as unique_viewers
    FROM content c
    JOIN viewing_sessions vs ON c.content_id = vs.content_id
    JOIN platforms p ON vs.platform_id = p.platform_id
    WHERE c.content_id = content_uuid
    GROUP BY p.platform_id, p.platform_name, p.platform_type
    ORDER BY sessions DESC;

    -- Revenue breakdown by type
    SELECT
        rs.revenue_type,
        SUM(rs.amount) as total_amount,
        COUNT(*) as transaction_count,
        AVG(rs.amount) as avg_transaction
    FROM revenue_streams rs
    WHERE rs.content_id = content_uuid
    GROUP BY rs.revenue_type
    ORDER BY total_amount DESC;
END;;

-- Analyze audience demographics
CREATE PROCEDURE analyze_audience_demographics(IN content_uuid CHAR(36))
BEGIN
    SELECT
        vs.country_code,
        COUNT(*) as total_sessions,
        COUNT(DISTINCT vs.user_id) as unique_users,
        AVG(vs.duration_seconds) as avg_watch_time,
        AVG(vs.completion_percentage) as avg_completion_rate,
        COUNT(CASE WHEN vs.device_type = 'mobile' THEN 1 END) as mobile_sessions,
        COUNT(CASE WHEN vs.device_type = 'desktop' THEN 1 END) as desktop_sessions,
        COUNT(CASE WHEN vs.device_type = 'smart_tv' THEN 1 END) as smart_tv_sessions
    FROM viewing_sessions vs
    WHERE vs.content_id = content_uuid
      AND vs.country_code IS NOT NULL
    GROUP BY vs.country_code
    ORDER BY total_sessions DESC
    LIMIT 20;

    -- Device type analysis
    SELECT
        vs.device_type,
        vs.device_os,
        COUNT(*) as session_count,
        AVG(vs.duration_seconds) as avg_duration,
        AVG(vs.completion_percentage) as completion_rate,
        SUM(vs.buffering_events) as total_buffering_events
    FROM viewing_sessions vs
    WHERE vs.content_id = content_uuid
    GROUP BY vs.device_type, vs.device_os
    ORDER BY session_count DESC;
END;;

-- Calculate content ROI and profitability
CREATE FUNCTION calculate_content_roi(content_uuid CHAR(36))
RETURNS JSON
DETERMINISTIC
BEGIN
    DECLARE budget_val DECIMAL(15,2);
    DECLARE revenue_val DECIMAL(15,2);
    DECLARE marketing_cost DECIMAL(12,2);
    DECLARE total_views BIGINT;
    DECLARE avg_rating DECIMAL(3,1);
    DECLARE roi_result JSON;

    -- Get financial data
    SELECT
        COALESCE(c.budget, 0),
        COALESCE(SUM(rs.amount), 0),
        COALESCE(SUM(rs.marketing_cost), 0),
        COALESCE(SUM(rs.viewer_count), 0),
        COALESCE(AVG(r.rating), 0)
    INTO budget_val, revenue_val, marketing_cost, total_views, avg_rating
    FROM content c
    LEFT JOIN revenue_streams rs ON c.content_id = rs.content_id
    LEFT JOIN reviews r ON c.content_id = r.content_id AND r.review_status = 'approved'
    WHERE c.content_id = content_uuid
    GROUP BY c.content_id, c.budget;

    -- Calculate ROI metrics
    SET roi_result = JSON_OBJECT(
        'total_budget', budget_val,
        'total_revenue', revenue_val,
        'marketing_cost', marketing_cost,
        'net_profit', revenue_val - budget_val - marketing_cost,
        'roi_percentage', CASE
            WHEN budget_val > 0 THEN ROUND(((revenue_val - budget_val - marketing_cost) / budget_val) * 100, 2)
            ELSE NULL
        END,
        'cost_per_viewer', CASE
            WHEN total_views > 0 THEN ROUND((budget_val + marketing_cost) / total_views, 2)
            ELSE NULL
        END,
        'revenue_per_viewer', CASE
            WHEN total_views > 0 THEN ROUND(revenue_val / total_views, 2)
            ELSE NULL
        END,
        'audience_rating', avg_rating,
        'profitability_status', CASE
            WHEN revenue_val - budget_val - marketing_cost > 0 THEN 'profitable'
            WHEN revenue_val > budget_val * 0.5 THEN 'break_even_pending'
            ELSE 'loss'
        END,
        'break_even_viewers', CASE
            WHEN budget_val > 0 THEN CEIL((budget_val + marketing_cost) / (revenue_val / NULLIF(total_views, 0)))
            ELSE NULL
        END
    );

    RETURN roi_result;
END;;

DELIMITER ;

-- ===========================================
-- PARTITIONING FOR ANALYTICS
-- =========================================--

-- Partition viewing sessions by month for analytics
ALTER TABLE viewing_sessions
PARTITION BY RANGE (YEAR(session_start) * 100 + MONTH(session_start)) (
    PARTITION p2024_01 VALUES LESS THAN (202401),
    PARTITION p2024_02 VALUES LESS THAN (202402),
    PARTITION p2024_03 VALUES LESS THAN (202403),
    PARTITION p2024_04 VALUES LESS THAN (202404),
    PARTITION p2024_05 VALUES LESS THAN (202405),
    PARTITION p2024_06 VALUES LESS THAN (202406),
    PARTITION p2024_07 VALUES LESS THAN (202407),
    PARTITION p2024_08 VALUES LESS THAN (202408),
    PARTITION p2024_09 VALUES LESS THAN (202409),
    PARTITION p2024_10 VALUES LESS THAN (202410),
    PARTITION p2024_11 VALUES LESS THAN (202411),
    PARTITION p2024_12 VALUES LESS THAN (202412),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Partition revenue streams by quarter
ALTER TABLE revenue_streams
PARTITION BY RANGE (fiscal_year * 4 + fiscal_quarter) (
    PARTITION q2024_1 VALUES LESS THAN (20241),
    PARTITION q2024_2 VALUES LESS THAN (20242),
    PARTITION q2024_3 VALUES LESS THAN (20243),
    PARTITION q2024_4 VALUES LESS THAN (20244),
    PARTITION q_future VALUES LESS THAN MAXVALUE
);

-- ===========================================
-- INITIAL SAMPLE DATA
-- =========================================--

-- Sample content
INSERT INTO content (content_id, content_type, title, description, genres, content_rating, release_date, runtime_minutes) VALUES
(UUID(), 'movie', 'The Great Adventure', 'An epic tale of discovery and courage', '["Adventure", "Drama"]', 'PG-13', '2024-03-15', 142),
(UUID(), 'tv_series', 'Tech Startup Stories', 'Documentary series about innovative companies', '["Documentary", "Business"]', 'TV-14', '2024-01-01', 45);

-- Sample platforms
INSERT INTO platforms (platform_id, platform_name, platform_type, business_model) VALUES
(UUID(), 'StreamFlix', 'streaming', 'subscription'),
(UUID(), 'CinemaWorld', 'theater', 'transactional'),
(UUID(), 'Prime Video', 'streaming', 'subscription');

-- Sample talent
INSERT INTO talent (talent_id, talent_type, first_name, last_name, nationality) VALUES
(UUID(), 'actor', 'John', 'Smith', 'American'),
(UUID(), 'director', 'Sarah', 'Johnson', 'Canadian');

/*
USAGE EXAMPLES:

-- Get comprehensive content performance
CALL get_content_performance('content-uuid-here');

-- Analyze audience demographics
CALL analyze_audience_demographics('content-uuid-here');

-- Calculate content ROI
SELECT calculate_content_roi('content-uuid-here');

This comprehensive entertainment industry database schema provides enterprise-grade infrastructure for:
- Content production and rights management
- Multi-platform distribution and streaming analytics
- Talent management and casting processes
- Revenue tracking and financial analytics
- Live events and venue management
- Audience engagement and review systems
- Real-time viewership analytics
- Global market analysis and localization

Key features adapted for MySQL:
- UUID primary keys with UUID() function
- JSON data types for flexible metadata (genres, social media, etc.)
- Full-text search for content discovery
- Spatial indexes for venue locations
- Partitioning for time-series analytics
- Stored procedures for complex entertainment analytics

The schema handles traditional theatrical distribution, modern streaming platforms, live events, and comprehensive audience analytics for the entertainment industry.
*/
