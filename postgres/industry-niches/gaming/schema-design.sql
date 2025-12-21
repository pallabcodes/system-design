-- Gaming Industry Database Schema Design
-- Comprehensive PostgreSQL schema for gaming platforms, including microtransactions,
-- leaderboards, tournaments, player progression, and analytics

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text search

-- ===========================================
-- PLAYER MANAGEMENT
-- ===========================================

-- Core player accounts
CREATE TABLE players (
    player_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    email_verified BOOLEAN DEFAULT FALSE,

    -- Profile Information
    display_name VARCHAR(100),
    avatar_url VARCHAR(500),
    bio TEXT,
    country_code CHAR(2),
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Account Status
    account_status VARCHAR(20) DEFAULT 'active'
        CHECK (account_status IN ('active', 'suspended', 'banned', 'inactive')),
    suspension_reason TEXT,
    suspension_until TIMESTAMP WITH TIME ZONE,

    -- Registration and Activity
    registration_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE,
    last_active_at TIMESTAMP WITH TIME ZONE,

    -- Preferences
    preferred_language VARCHAR(10) DEFAULT 'en',
    email_notifications BOOLEAN DEFAULT TRUE,
    push_notifications BOOLEAN DEFAULT TRUE,

    -- Security
    password_hash VARCHAR(255),
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret VARCHAR(100),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Player devices and sessions
CREATE TABLE player_devices (
    device_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID NOT NULL REFERENCES players(player_id) ON DELETE CASCADE,

    -- Device Information
    device_fingerprint VARCHAR(255) UNIQUE NOT NULL,
    device_type VARCHAR(50),  -- 'mobile', 'desktop', 'console', etc.
    operating_system VARCHAR(100),
    browser_info JSONB,

    -- Session Tracking
    first_seen TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    session_count INTEGER DEFAULT 0,

    -- Trust Level
    is_trusted BOOLEAN DEFAULT FALSE,
    trust_score DECIMAL(3,2) DEFAULT 0.5 CHECK (trust_score BETWEEN 0 AND 1),

    -- Location Data (for fraud detection)
    ip_addresses TEXT[],  -- Array of recent IPs
    geo_locations JSONB,  -- Geographic data

    UNIQUE (player_id, device_fingerprint)
);

-- ===========================================
-- GAME MANAGEMENT
-- ===========================================

-- Game titles and versions
CREATE TABLE games (
    game_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_title VARCHAR(255) NOT NULL,
    game_slug VARCHAR(100) UNIQUE NOT NULL,

    -- Game Metadata
    description TEXT,
    genre VARCHAR(50),  -- 'action', 'rpg', 'strategy', 'sports', etc.
    developer VARCHAR(255),
    publisher VARCHAR(255),

    -- Version and Platform
    current_version VARCHAR(50),
    supported_platforms TEXT[],  -- Array of platforms
    min_system_requirements JSONB,

    -- Release Information
    release_date DATE,
    is_active BOOLEAN DEFAULT TRUE,

    -- Monetization
    monetization_type VARCHAR(50) DEFAULT 'free_to_play'
        CHECK (monetization_type IN ('free_to_play', 'paid', 'subscription', 'mixed')),

    -- Game Settings
    max_players INTEGER,
    is_multiplayer BOOLEAN DEFAULT FALSE,
    has_pvp BOOLEAN DEFAULT FALSE,
    has_pve BOOLEAN DEFAULT FALSE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Game sessions (individual play sessions)
CREATE TABLE game_sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID NOT NULL REFERENCES players(player_id),
    game_id UUID NOT NULL REFERENCES games(game_id),

    -- Session Details
    device_id UUID REFERENCES player_devices(device_id),
    platform VARCHAR(50),
    game_version VARCHAR(50),

    -- Timing
    start_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (end_time - start_time)) / 60
    ) STORED,

    -- Session Metrics
    score BIGINT,
    level_reached INTEGER,
    achievements_unlocked TEXT[],  -- Array of achievement IDs
    items_collected JSONB,

    -- Performance Metrics
    fps_average DECIMAL(5,2),
    ping_average INTEGER,  -- milliseconds
    memory_usage_mb DECIMAL(8,2),

    -- Session Status
    session_status VARCHAR(20) DEFAULT 'active'
        CHECK (session_status IN ('active', 'completed', 'abandoned', 'error')),

    -- Location/Context
    ip_address INET,
    geo_location JSONB,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (start_time);

-- ===========================================
-- PLAYER PROGRESSION
-- ===========================================

-- Player statistics across all games
CREATE TABLE player_stats (
    stat_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID NOT NULL REFERENCES players(player_id),
    game_id UUID NOT NULL REFERENCES games(game_id),

    -- Stat Definition
    stat_name VARCHAR(100) NOT NULL,
    stat_category VARCHAR(50),  -- 'combat', 'social', 'progression', etc.
    stat_value_type VARCHAR(20) DEFAULT 'integer'
        CHECK (stat_value_type IN ('integer', 'decimal', 'boolean', 'text')),

    -- Current Values
    int_value BIGINT,
    decimal_value DECIMAL(15,4),
    boolean_value BOOLEAN,
    text_value TEXT,

    -- Historical Tracking
    lifetime_value BIGINT,  -- Total accumulated value
    best_value BIGINT,       -- Personal best
    first_achieved_at TIMESTAMP WITH TIME ZONE,
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Visibility
    is_public BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,

    UNIQUE (player_id, game_id, stat_name)
);

-- Achievement system
CREATE TABLE achievements (
    achievement_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID NOT NULL REFERENCES games(game_id),

    -- Achievement Details
    achievement_name VARCHAR(255) NOT NULL,
    description TEXT,
    icon_url VARCHAR(500),

    -- Requirements
    requirement_type VARCHAR(50),  -- 'stat_threshold', 'action_count', 'time_based', etc.
    requirement_config JSONB,      -- Flexible configuration for requirements

    -- Rewards
    xp_reward INTEGER DEFAULT 0,
    currency_reward INTEGER DEFAULT 0,
    item_rewards JSONB,  -- Array of item grants

    -- Rarity and Difficulty
    rarity VARCHAR(20) DEFAULT 'common'
        CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),
    difficulty_score INTEGER CHECK (difficulty_score BETWEEN 1 AND 100),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Player achievements
CREATE TABLE player_achievements (
    player_achievement_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID NOT NULL REFERENCES players(player_id),
    achievement_id UUID NOT NULL REFERENCES achievements(achievement_id),

    -- Achievement Progress
    progress_value DECIMAL(10,2) DEFAULT 0,
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMP WITH TIME ZONE,

    -- First completion bonus
    is_first_completion BOOLEAN DEFAULT FALSE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (player_id, achievement_id)
);

-- ===========================================
-- ECONOMY AND MONETIZATION
-- ===========================================

-- Virtual currencies
CREATE TABLE currencies (
    currency_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID REFERENCES games(game_id),  -- NULL for global currencies

    -- Currency Details
    currency_name VARCHAR(100) NOT NULL,
    currency_code VARCHAR(10) UNIQUE NOT NULL,
    currency_symbol VARCHAR(10),

    -- Properties
    is_premium BOOLEAN DEFAULT FALSE,  -- Real money currency
    exchange_rate DECIMAL(10,4),       -- Exchange rate to base currency
    max_balance BIGINT,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Player currency balances
CREATE TABLE player_balances (
    balance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID NOT NULL REFERENCES players(player_id),
    currency_id UUID NOT NULL REFERENCES currencies(currency_id),

    -- Balance
    current_balance BIGINT DEFAULT 0,
    lifetime_earned BIGINT DEFAULT 0,
    lifetime_spent BIGINT DEFAULT 0,

    -- Limits and Bonuses
    daily_earn_limit BIGINT,
    weekly_earn_limit BIGINT,
    bonus_multiplier DECIMAL(3,2) DEFAULT 1.0,

    -- Last Activity
    last_earned_at TIMESTAMP WITH TIME ZONE,
    last_spent_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (player_id, currency_id)
);

-- Transaction ledger for all economic activity
CREATE TABLE transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID NOT NULL REFERENCES players(player_id),

    -- Transaction Details
    transaction_type VARCHAR(50) NOT NULL
        CHECK (transaction_type IN ('purchase', 'reward', 'refund', 'transfer', 'conversion', 'decay')),
    transaction_status VARCHAR(20) DEFAULT 'completed'
        CHECK (transaction_status IN ('pending', 'completed', 'failed', 'cancelled')),

    -- Currency and Amounts
    currency_id UUID NOT NULL REFERENCES currencies(currency_id),
    amount BIGINT NOT NULL,
    balance_before BIGINT,
    balance_after BIGINT,

    -- Context
    game_id UUID REFERENCES games(game_id),
    session_id UUID REFERENCES game_sessions(session_id),
    item_id UUID,  -- Reference to purchased item

    -- External References
    external_transaction_id VARCHAR(255),  -- Payment processor ID
    payment_method VARCHAR(50),            -- 'credit_card', 'paypal', etc.

    -- Metadata
    transaction_metadata JSONB,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE
) PARTITION BY RANGE (created_at);

-- ===========================================
-- ITEMS AND INVENTORY
-- ===========================================

-- Item templates
CREATE TABLE items (
    item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID NOT NULL REFERENCES games(game_id),

    -- Item Definition
    item_name VARCHAR(255) NOT NULL,
    item_description TEXT,
    item_type VARCHAR(50) NOT NULL,  -- 'weapon', 'armor', 'consumable', 'cosmetic', etc.
    item_rarity VARCHAR(20) DEFAULT 'common'
        CHECK (item_rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),

    -- Visual and Audio
    icon_url VARCHAR(500),
    model_url VARCHAR(500),
    sound_effect_url VARCHAR(500),

    -- Stats and Properties
    item_stats JSONB,        -- Key-value pairs for item stats
    item_properties JSONB,   -- Additional properties (durability, stack size, etc.)

    -- Economic Properties
    base_price BIGINT,
    sell_price BIGINT,
    currency_id UUID REFERENCES currencies(currency_id),

    -- Crafting/Upgrade Requirements
    crafting_requirements JSONB,
    upgrade_path JSONB,

    -- Availability
    is_tradable BOOLEAN DEFAULT TRUE,
    is_sellable BOOLEAN DEFAULT TRUE,
    max_stack_size INTEGER DEFAULT 1,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Player inventory
CREATE TABLE player_inventory (
    inventory_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID NOT NULL REFERENCES players(player_id),
    item_id UUID NOT NULL REFERENCES items(item_id),

    -- Quantity and Status
    quantity INTEGER DEFAULT 1,
    is_equipped BOOLEAN DEFAULT FALSE,
    equipped_slot VARCHAR(50),

    -- Item Condition
    durability_current INTEGER,
    durability_max INTEGER,

    -- Acquisition
    acquired_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    acquisition_method VARCHAR(50),  -- 'purchase', 'reward', 'craft', 'drop', etc.
    source_transaction_id UUID REFERENCES transactions(transaction_id),

    -- Expiration
    expires_at TIMESTAMP WITH TIME ZONE,

    -- Custom Properties (enchantments, customizations)
    custom_properties JSONB,

    UNIQUE (player_id, item_id)
);

-- ===========================================
-- COMPETITIVE FEATURES
-- ===========================================

-- Leaderboards
CREATE TABLE leaderboards (
    leaderboard_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID NOT NULL REFERENCES games(game_id),

    -- Leaderboard Configuration
    leaderboard_name VARCHAR(255) NOT NULL,
    leaderboard_type VARCHAR(50) NOT NULL
        CHECK (leaderboard_type IN ('global', 'regional', 'guild', 'seasonal', 'event')),

    -- Scoring
    score_metric VARCHAR(100) NOT NULL,  -- stat_name or custom calculation
    score_type VARCHAR(20) DEFAULT 'higher_better'
        CHECK (score_type IN ('higher_better', 'lower_better', 'time_based')),

    -- Time Windows
    reset_period VARCHAR(20)
        CHECK (reset_period IN ('never', 'daily', 'weekly', 'monthly', 'seasonal')),
    current_period_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    current_period_end TIMESTAMP WITH TIME ZONE,

    -- Limits and Filters
    max_entries INTEGER DEFAULT 100,
    region_filter VARCHAR(10),  -- Country code filter
    min_games_played INTEGER DEFAULT 1,

    -- Rewards
    rewards_config JSONB,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Leaderboard entries
CREATE TABLE leaderboard_entries (
    entry_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    leaderboard_id UUID NOT NULL REFERENCES leaderboards(leaderboard_id),
    player_id UUID NOT NULL REFERENCES players(player_id),

    -- Score and Rank
    score_value DECIMAL(15,4) NOT NULL,
    rank INTEGER,
    previous_rank INTEGER,

    -- Period Tracking
    period_start TIMESTAMP WITH TIME ZONE,
    period_end TIMESTAMP WITH TIME ZONE,
    is_current_period BOOLEAN DEFAULT TRUE,

    -- Metadata
    entry_metadata JSONB,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (leaderboard_id, player_id, period_start)
);

-- Tournaments and events
CREATE TABLE tournaments (
    tournament_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID NOT NULL REFERENCES games(game_id),

    -- Tournament Details
    tournament_name VARCHAR(255) NOT NULL,
    tournament_description TEXT,
    tournament_type VARCHAR(50) DEFAULT 'single_elimination'
        CHECK (tournament_type IN ('single_elimination', 'double_elimination', 'round_robin', 'swiss', 'battle_royale')),

    -- Schedule
    registration_start TIMESTAMP WITH TIME ZONE,
    registration_end TIMESTAMP WITH TIME ZONE,
    tournament_start TIMESTAMP WITH TIME ZONE,
    tournament_end TIMESTAMP WITH TIME ZONE,

    -- Participation
    max_participants INTEGER,
    min_participants INTEGER DEFAULT 2,
    entry_fee BIGINT,
    entry_fee_currency UUID REFERENCES currencies(currency_id),

    -- Rules and Scoring
    rules_config JSONB,
    scoring_config JSONB,

    -- Rewards
    prize_pool JSONB,  -- Distribution of rewards
    total_prize_value BIGINT,

    -- Status
    tournament_status VARCHAR(30) DEFAULT 'draft'
        CHECK (tournament_status IN ('draft', 'registration_open', 'registration_closed', 'in_progress', 'completed', 'cancelled')),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tournament participants and matches
CREATE TABLE tournament_participants (
    participant_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tournament_id UUID NOT NULL REFERENCES tournaments(tournament_id),
    player_id UUID NOT NULL REFERENCES players(player_id),

    -- Registration
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    registration_status VARCHAR(20) DEFAULT 'registered'
        CHECK (registration_status IN ('registered', 'confirmed', 'withdrawn', 'disqualified')),

    -- Tournament Progress
    current_round INTEGER DEFAULT 1,
    final_rank INTEGER,
    total_score DECIMAL(15,4),

    -- Results
    matches_played INTEGER DEFAULT 0,
    matches_won INTEGER DEFAULT 0,
    matches_lost INTEGER DEFAULT 0,

    UNIQUE (tournament_id, player_id)
);

-- ===========================================
-- SOCIAL FEATURES
-- ===========================================

-- Friendships and relationships
CREATE TABLE friendships (
    friendship_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player1_id UUID NOT NULL REFERENCES players(player_id),
    player2_id UUID NOT NULL REFERENCES players(player_id),

    -- Relationship Status
    status VARCHAR(20) DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'blocked', 'removed')),
    requested_by UUID NOT NULL REFERENCES players(player_id),
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    accepted_at TIMESTAMP WITH TIME ZONE,

    -- Friendship Properties
    friendship_level INTEGER DEFAULT 1,
    shared_games TEXT[],  -- Array of common games

    -- Ensure consistent ordering (smaller ID first)
    CHECK (player1_id < player2_id),

    UNIQUE (player1_id, player2_id)
);

-- Guilds/Clans
CREATE TABLE guilds (
    guild_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID REFERENCES games(game_id),  -- NULL for cross-game guilds

    -- Guild Details
    guild_name VARCHAR(100) UNIQUE NOT NULL,
    guild_tag VARCHAR(10) UNIQUE,  -- Short identifier like [ABC]
    description TEXT,

    -- Leadership
    leader_id UUID NOT NULL REFERENCES players(player_id),
    officer_ids UUID[],  -- Array of officer player IDs

    -- Membership
    max_members INTEGER DEFAULT 100,
    member_count INTEGER DEFAULT 0,

    -- Requirements
    join_requirements JSONB,  -- Level, achievements, etc.

    -- Guild Features
    has_voice_chat BOOLEAN DEFAULT FALSE,
    has_text_chat BOOLEAN DEFAULT TRUE,
    has_forum BOOLEAN DEFAULT FALSE,

    -- Status
    is_recruiting BOOLEAN DEFAULT TRUE,
    guild_level INTEGER DEFAULT 1,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Guild membership
CREATE TABLE guild_members (
    membership_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guild_id UUID NOT NULL REFERENCES guilds(guild_id),
    player_id UUID NOT NULL REFERENCES players(player_id),

    -- Membership Details
    role VARCHAR(20) DEFAULT 'member'
        CHECK (role IN ('leader', 'officer', 'member', 'recruit')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Contributions
    contribution_score BIGINT DEFAULT 0,
    games_played_with_guild INTEGER DEFAULT 0,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    UNIQUE (guild_id, player_id)
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

-- Player behavior analytics
CREATE TABLE player_analytics (
    analytic_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID NOT NULL REFERENCES players(player_id),
    game_id UUID REFERENCES games(game_id),

    -- Time Period
    date_recorded DATE DEFAULT CURRENT_DATE,
    hour_recorded INTEGER CHECK (hour_recorded BETWEEN 0 AND 23),

    -- Session Analytics
    sessions_started INTEGER DEFAULT 0,
    total_session_time_minutes DECIMAL(10,2) DEFAULT 0,
    average_session_length DECIMAL(8,2),

    -- Engagement Metrics
    levels_completed INTEGER DEFAULT 0,
    achievements_unlocked INTEGER DEFAULT 0,
    items_purchased INTEGER DEFAULT 0,

    -- Social Metrics
    friends_added INTEGER DEFAULT 0,
    messages_sent INTEGER DEFAULT 0,
    guild_activities INTEGER DEFAULT 0,

    -- Economic Metrics
    currency_earned BIGINT DEFAULT 0,
    currency_spent BIGINT DEFAULT 0,
    transactions_count INTEGER DEFAULT 0,

    -- Technical Metrics
    crashes_experienced INTEGER DEFAULT 0,
    average_fps DECIMAL(5,2),
    average_ping INTEGER,

    UNIQUE (player_id, game_id, date_recorded, hour_recorded)
) PARTITION BY RANGE (date_recorded);

-- Game performance metrics
CREATE TABLE game_metrics (
    metric_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID NOT NULL REFERENCES games(game_id),

    -- Time Period
    date_recorded DATE DEFAULT CURRENT_DATE,
    hour_recorded INTEGER CHECK (hour_recorded BETWEEN 0 AND 23),

    -- Player Metrics
    active_players INTEGER DEFAULT 0,
    new_players INTEGER DEFAULT 0,
    returning_players INTEGER DEFAULT 0,

    -- Session Metrics
    total_sessions INTEGER DEFAULT 0,
    average_session_length DECIMAL(8,2),
    peak_concurrent_players INTEGER DEFAULT 0,

    -- Economic Metrics
    revenue_generated BIGINT DEFAULT 0,
    transactions_count INTEGER DEFAULT 0,
    average_transaction_value DECIMAL(8,2),

    -- Technical Metrics
    server_uptime_percentage DECIMAL(5,2),
    average_response_time_ms DECIMAL(8,2),
    error_rate DECIMAL(5,4),

    UNIQUE (game_id, date_recorded, hour_recorded)
) PARTITION BY RANGE (date_recorded);

-- ===========================================
-- MODERATION AND SUPPORT
-- ===========================================

-- Player reports
CREATE TABLE player_reports (
    report_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reported_player_id UUID NOT NULL REFERENCES players(player_id),
    reporting_player_id UUID NOT NULL REFERENCES players(player_id),

    -- Report Details
    report_category VARCHAR(50) NOT NULL
        CHECK (report_category IN ('cheating', 'harassment', 'inappropriate_content', 'spam', 'griefing', 'other')),
    report_description TEXT NOT NULL,

    -- Context
    game_id UUID REFERENCES games(game_id),
    session_id UUID REFERENCES game_sessions(session_id),
    reported_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Evidence
    evidence_urls TEXT[],  -- Array of screenshot/video URLs
    chat_logs TEXT,

    -- Investigation
    investigation_status VARCHAR(20) DEFAULT 'pending'
        CHECK (investigation_status IN ('pending', 'investigating', 'resolved', 'dismissed')),
    investigated_by UUID REFERENCES users(user_id),
    investigated_at TIMESTAMP WITH TIME ZONE,
    investigation_notes TEXT,

    -- Resolution
    resolution VARCHAR(50),  -- 'warning', 'suspension', 'ban', 'no_action', etc.
    resolution_details TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Prevent duplicate reports
    UNIQUE (reported_player_id, reporting_player_id, reported_at::DATE)
);

-- Support tickets
CREATE TABLE support_tickets (
    ticket_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID NOT NULL REFERENCES players(player_id),

    -- Ticket Details
    ticket_category VARCHAR(50) NOT NULL
        CHECK (ticket_category IN ('technical_issue', 'billing', 'account_recovery', 'report_player', 'feature_request', 'bug_report')),
    ticket_priority VARCHAR(10) DEFAULT 'medium'
        CHECK (ticket_priority IN ('low', 'medium', 'high', 'urgent')),

    -- Issue Description
    ticket_title VARCHAR(255) NOT NULL,
    ticket_description TEXT NOT NULL,

    -- Context
    game_id UUID REFERENCES games(game_id),
    platform VARCHAR(50),
    device_info JSONB,

    -- Status and Assignment
    ticket_status VARCHAR(20) DEFAULT 'open'
        CHECK (ticket_status IN ('open', 'assigned', 'in_progress', 'waiting_for_user', 'resolved', 'closed')),
    assigned_to UUID REFERENCES users(user_id),
    assigned_at TIMESTAMP WITH TIME ZONE,

    -- Resolution
    resolution TEXT,
    resolved_at TIMESTAMP WITH TIME ZONE,
    satisfaction_rating INTEGER CHECK (satisfaction_rating BETWEEN 1 AND 5),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Core player indexes
CREATE INDEX idx_players_username ON players (username);
CREATE INDEX idx_players_email ON players (email);
CREATE INDEX idx_players_status ON players (account_status);
CREATE INDEX idx_players_last_active ON players (last_active_at DESC);

-- Session performance indexes
CREATE INDEX idx_game_sessions_player ON game_sessions (player_id, start_time DESC);
CREATE INDEX idx_game_sessions_game ON game_sessions (game_id, start_time DESC);
CREATE INDEX idx_game_sessions_status ON game_sessions (session_status);

-- Player stats indexes
CREATE INDEX idx_player_stats_player_game ON player_stats (player_id, game_id);
CREATE INDEX idx_player_stats_name ON player_stats (stat_name);
CREATE INDEX idx_player_stats_featured ON player_stats (is_featured, last_updated_at DESC) WHERE is_featured = TRUE;

-- Achievement indexes
CREATE INDEX idx_player_achievements_player ON player_achievements (player_id);
CREATE INDEX idx_player_achievements_completed ON player_achievements (is_completed, completed_at DESC) WHERE is_completed = TRUE;

-- Transaction indexes
CREATE INDEX idx_transactions_player ON transactions (player_id, created_at DESC);
CREATE INDEX idx_transactions_type ON transactions (transaction_type, created_at DESC);
CREATE INDEX idx_transactions_external ON transactions (external_transaction_id);

-- Inventory indexes
CREATE INDEX idx_player_inventory_player ON player_inventory (player_id);
CREATE INDEX idx_player_inventory_item ON player_inventory (item_id);
CREATE INDEX idx_player_inventory_expires ON player_inventory (expires_at) WHERE expires_at IS NOT NULL;

-- Leaderboard indexes
CREATE INDEX idx_leaderboard_entries_board ON leaderboard_entries (leaderboard_id, score_value DESC);
CREATE INDEX idx_leaderboard_entries_player ON leaderboard_entries (player_id);

-- Tournament indexes
CREATE INDEX idx_tournament_participants_tournament ON tournament_participants (tournament_id);
CREATE INDEX idx_tournament_participants_player ON tournament_participants (player_id);

-- Social features indexes
CREATE INDEX idx_friendships_player1 ON friendships (player1_id, status);
CREATE INDEX idx_friendships_player2 ON friendships (player2_id, status);
CREATE INDEX idx_guild_members_guild ON guild_members (guild_id, role);
CREATE INDEX idx_guild_members_player ON guild_members (player_id);

-- Analytics indexes
CREATE INDEX idx_player_analytics_player ON player_analytics (player_id, date_recorded DESC);
CREATE INDEX idx_game_metrics_game ON game_metrics (game_id, date_recorded DESC);

-- Moderation indexes
CREATE INDEX idx_player_reports_reported ON player_reports (reported_player_id, investigation_status);
CREATE INDEX idx_player_reports_reporting ON player_reports (reporting_player_id);
CREATE INDEX idx_support_tickets_player ON support_tickets (player_id, created_at DESC);
CREATE INDEX idx_support_tickets_status ON support_tickets (ticket_status, ticket_priority DESC);

-- ===========================================
-- PARTITIONING SETUP
-- ===========================================

-- Game sessions partitioning (monthly)
CREATE TABLE game_sessions_2024_01 PARTITION OF game_sessions
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE game_sessions_2024_02 PARTITION OF game_sessions
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- Transactions partitioning (daily for high volume)
CREATE TABLE transactions_2024_01_01 PARTITION OF transactions
    FOR VALUES FROM ('2024-01-01') TO ('2024-01-02');

CREATE TABLE transactions_2024_01_02 PARTITION OF transactions
    FOR VALUES FROM ('2024-01-02') TO ('2024-01-03');

-- Analytics partitioning (daily)
CREATE TABLE player_analytics_2024_01 PARTITION OF player_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE game_metrics_2024_01 PARTITION OF game_metrics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Player profile summary
CREATE VIEW player_profile AS
SELECT
    p.player_id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.country_code,
    p.account_status,
    p.registration_date,
    p.last_active_at,

    -- Activity summary
    COALESCE(s.total_sessions, 0) AS total_sessions,
    COALESCE(s.total_playtime_minutes, 0) AS total_playtime_minutes,
    COALESCE(a.total_achievements, 0) AS total_achievements,

    -- Economic summary
    COALESCE(e.total_earned, 0) AS total_currency_earned,
    COALESCE(e.total_spent, 0) AS total_currency_spent,

    -- Social summary
    COALESCE(f.friend_count, 0) AS friend_count,
    g.guild_name,
    g.guild_tag

FROM players p
LEFT JOIN (
    SELECT player_id,
           COUNT(*) AS total_sessions,
           SUM(duration_minutes) AS total_playtime_minutes
    FROM game_sessions
    WHERE session_status = 'completed'
    GROUP BY player_id
) s ON p.player_id = s.player_id
LEFT JOIN (
    SELECT player_id, COUNT(*) AS total_achievements
    FROM player_achievements
    WHERE is_completed = TRUE
    GROUP BY player_id
) a ON p.player_id = a.player_id
LEFT JOIN (
    SELECT player_id,
           SUM(lifetime_earned) AS total_earned,
           SUM(lifetime_spent) AS total_spent
    FROM player_balances
    GROUP BY player_id
) e ON p.player_id = e.player_id
LEFT JOIN (
    SELECT player1_id AS player_id, COUNT(*) AS friend_count
    FROM friendships
    WHERE status = 'accepted'
    GROUP BY player1_id
) f ON p.player_id = f.player_id
LEFT JOIN guild_members gm ON p.player_id = gm.player_id AND gm.is_active = TRUE
LEFT JOIN guilds g ON gm.guild_id = g.guild_id;

-- Game performance dashboard
CREATE VIEW game_performance_dashboard AS
SELECT
    g.game_id,
    g.game_title,
    g.genre,

    -- Player metrics (last 30 days)
    COALESCE(p30.active_players, 0) AS active_players_30d,
    COALESCE(p30.new_players, 0) AS new_players_30d,
    COALESCE(p30.returning_players, 0) AS returning_players_30d,

    -- Session metrics
    COALESCE(s30.total_sessions, 0) AS sessions_30d,
    COALESCE(s30.avg_session_length, 0) AS avg_session_length_30d,

    -- Economic metrics
    COALESCE(e30.revenue, 0) AS revenue_30d,
    COALESCE(e30.transactions, 0) AS transactions_30d,

    -- Technical metrics
    COALESCE(t30.avg_response_time, 0) AS avg_response_time_30d,
    COALESCE(t30.error_rate, 0) AS error_rate_30d

FROM games g
LEFT JOIN (
    SELECT game_id,
           SUM(active_players) AS active_players,
           SUM(new_players) AS new_players,
           SUM(returning_players) AS returning_players
    FROM game_metrics
    WHERE date_recorded >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY game_id
) p30 ON g.game_id = p30.game_id
LEFT JOIN (
    SELECT game_id,
           SUM(total_sessions) AS total_sessions,
           AVG(average_session_length) AS avg_session_length
    FROM game_metrics
    WHERE date_recorded >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY game_id
) s30 ON g.game_id = s30.game_id
LEFT JOIN (
    SELECT game_id,
           SUM(revenue_generated) AS revenue,
           SUM(transactions_count) AS transactions
    FROM game_metrics
    WHERE date_recorded >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY game_id
) e30 ON g.game_id = e30.game_id
LEFT JOIN (
    SELECT game_id,
           AVG(average_response_time_ms) AS avg_response_time,
           AVG(error_rate) AS error_rate
    FROM game_metrics
    WHERE date_recorded >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY game_id
) t30 ON g.game_id = t30.game_id;

-- ===========================================
-- TRIGGERS FOR BUSINESS LOGIC
-- ===========================================

-- Update player last active timestamp
CREATE OR REPLACE FUNCTION update_player_last_active()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE players
    SET last_active_at = CURRENT_TIMESTAMP
    WHERE player_id = NEW.player_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_player_last_active
    AFTER INSERT ON game_sessions
    FOR EACH ROW EXECUTE FUNCTION update_player_last_active();

-- Maintain player balance integrity
CREATE OR REPLACE FUNCTION update_player_balance()
RETURNS TRIGGER AS $$
DECLARE
    balance_change BIGINT;
BEGIN
    -- Calculate balance change
    IF NEW.transaction_type IN ('purchase', 'transfer', 'decay') THEN
        balance_change := -NEW.amount;
    ELSE
        balance_change := NEW.amount;
    END IF;

    -- Update player balance
    INSERT INTO player_balances (player_id, currency_id, current_balance, lifetime_earned, lifetime_spent)
    VALUES (
        NEW.player_id,
        NEW.currency_id,
        balance_change,
        CASE WHEN balance_change > 0 THEN balance_change ELSE 0 END,
        CASE WHEN balance_change < 0 THEN -balance_change ELSE 0 END
    )
    ON CONFLICT (player_id, currency_id) DO UPDATE SET
        current_balance = player_balances.current_balance + balance_change,
        lifetime_earned = player_balances.lifetime_earned + CASE WHEN balance_change > 0 THEN balance_change ELSE 0 END,
        lifetime_spent = player_balances.lifetime_spent + CASE WHEN balance_change < 0 THEN -balance_change ELSE 0 END,
        last_earned_at = CASE WHEN balance_change > 0 THEN CURRENT_TIMESTAMP ELSE player_balances.last_earned_at END,
        last_spent_at = CASE WHEN balance_change < 0 THEN CURRENT_TIMESTAMP ELSE player_balances.last_spent_at END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_player_balance
    AFTER INSERT ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_player_balance();

-- Update guild member count
CREATE OR REPLACE FUNCTION update_guild_member_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE guilds SET member_count = member_count + 1 WHERE guild_id = NEW.guild_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE guilds SET member_count = member_count - 1 WHERE guild_id = OLD.guild_id;
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_guild_member_count
    AFTER INSERT OR DELETE ON guild_members
    FOR EACH ROW EXECUTE FUNCTION update_guild_member_count();

-- This comprehensive gaming database schema provides a solid foundation
-- for modern gaming platforms with support for microtransactions,
-- competitive features, social interactions, and detailed analytics.
