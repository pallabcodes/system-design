# Netflix Video Streaming: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Content Catalog, User Profiles, Viewing History, Continue Watching — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Storing viewing history in a relational database. Netflix processes **billions** of viewing events per day — Cassandra for writes, EVCache for reads.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Netflix Media Database (NMDB)](https://netflixtechblog.com/netflix-media-database-media-timeline-976c40f6f3ff) | Media metadata architecture |
| [Viewing Data at Netflix](https://netflixtechblog.com/scaling-time-series-data-storage-part-i-ec2b6d44ba39) | Time-series viewing data |
| [EVCache at Netflix](https://netflixtechblog.com/announcing-evcache-distributed-in-memory-datastore-for-netflix-4e9d62e4c2d6) | Distributed caching |
| [Cassandra at Netflix](https://netflixtechblog.com/tagged/cassandra) | NoSQL at scale |

---

## 🎯 The Principal Laws of Video Streaming Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Write-Heavy Viewing** | Every play/pause/seek is an event | Cassandra for event ingestion |
| **Law 2: Read-Heavy Catalog** | Same movie page viewed millions of times | Cache aggressively with EVCache |
| **Law 3: Profile Isolation** | Kids profile != Adult profile | Partition by profile_id, not user_id |
| **Law 4: Personalization Is King** | Recommendations drive 80% of views | Pre-compute and cache rankings |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get content metadata (title, cast, synopsis) | 10M/s | < 10ms | EVCache + Cassandra |
| 2 | Get personalized home page rows | 5M/s | < 50ms | Pre-computed in Cassandra |
| 3 | Record viewing event (play, pause, seek) | 100M/s | < 100ms | Cassandra (async) |
| 4 | Get "Continue Watching" list | 10M/s | < 20ms | EVCache + Cassandra |
| 5 | Get watch progress for a title | 50M/s | < 10ms | EVCache |
| 6 | Search content | 1M/s | < 100ms | Elasticsearch |
| 7 | Get profile viewing history | 500K/s | < 200ms | Cassandra |
| 8 | Update user preferences | 100K/s | < 200ms | PostgreSQL |
| 9 | Get available subtitles/audio tracks | 5M/s | < 10ms | EVCache |
| 10 | Get regional availability | 10M/s | < 10ms | EVCache |

---

# Part 2: Database Selection Matrix

```
┌─────────────────────────────────────────────────────────────────┐
│                    NETFLIX DATA ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                               │
│  ✓ ACID transactions    ✓ Complex queries   ✓ Small dataset     │
│                                                                  │
│  • accounts (billing, subscription)                              │
│  • users (authentication)                                        │
│  • profiles (per-account)                                        │
│  • payment_methods                                               │
│  • content_rights (licensing)                                    │
└─────────────────────────────────────────────────────────────────┘
                              │ CDC (Debezium)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Apache Cassandra                         │
│  ✓ Billions of writes    ✓ Multi-region   ✓ Linear scale        │
│                                                                  │
│  • viewing_history_by_profile                                    │
│  • continue_watching_by_profile                                  │
│  • content_metadata                                              │
│  • personalized_rows_by_profile                                  │
│  • user_ratings                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │ Populate
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         EVCache (Memcached)                      │
│  ✓ Sub-ms reads    ✓ Global replication   ✓ Write-through       │
│                                                                  │
│  • content_cache:{video_id}                                      │
│  • continue_watching:{profile_id}                                │
│  • watch_progress:{profile_id}:{video_id}                        │
│  • profile_preferences:{profile_id}                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Elasticsearch                            │
│  ✓ Full-text search    ✓ Typeahead   ✓ Faceted search           │
│                                                                  │
│  • content_search (title, actors, genres, etc.)                  │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL (Accounts & Profiles)

```sql
-- ============================================================
-- NETFLIX SCHEMA: PostgreSQL Production DDL
-- Version: Account management and profiles
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ===========================================
-- SECTION 1: ACCOUNTS AND SUBSCRIPTIONS
-- ===========================================

CREATE TYPE subscription_plan AS ENUM ('basic', 'standard', 'premium');
CREATE TYPE subscription_status AS ENUM ('active', 'paused', 'cancelled', 'past_due');
CREATE TYPE payment_status AS ENUM ('pending', 'succeeded', 'failed', 'refunded');

CREATE TABLE accounts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email               VARCHAR(255) NOT NULL UNIQUE,
    password_hash       TEXT NOT NULL,
    
    -- Subscription
    plan                subscription_plan NOT NULL DEFAULT 'basic',
    status              subscription_status NOT NULL DEFAULT 'active',
    max_profiles        INT NOT NULL DEFAULT 5,
    max_streams         INT NOT NULL DEFAULT 1,  -- Concurrent streams
    
    -- Billing
    billing_country     VARCHAR(2) NOT NULL,  -- ISO 3166-1 alpha-2
    billing_currency    VARCHAR(3) NOT NULL DEFAULT 'USD',
    next_billing_date   DATE,
    
    -- Metadata
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    cancelled_at        TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT ck_plan_limits CHECK (
        (plan = 'basic' AND max_streams = 1) OR
        (plan = 'standard' AND max_streams = 2) OR
        (plan = 'premium' AND max_streams = 4)
    )
);

CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_status ON accounts(status) WHERE status = 'active';
CREATE INDEX idx_accounts_billing ON accounts(next_billing_date) WHERE status = 'active';


-- Payment methods
CREATE TABLE payment_methods (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    
    -- Tokenized (never store full PAN)
    stripe_payment_method_id VARCHAR(255),
    card_brand          VARCHAR(20),
    card_last4          VARCHAR(4),
    card_exp_month      INT,
    card_exp_year       INT,
    
    is_default          BOOLEAN DEFAULT FALSE,
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_payment_account ON payment_methods(account_id);


-- ===========================================
-- SECTION 2: PROFILES
-- ===========================================

CREATE TYPE maturity_level AS ENUM ('kids', 'teen', 'adult');

CREATE TABLE profiles (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    
    name                VARCHAR(50) NOT NULL,
    avatar_url          TEXT,
    
    -- Content preferences
    maturity_level      maturity_level NOT NULL DEFAULT 'adult',
    is_kids             BOOLEAN DEFAULT FALSE,
    language            VARCHAR(10) DEFAULT 'en',
    subtitle_language   VARCHAR(10),
    
    -- Autoplay settings
    autoplay_next       BOOLEAN DEFAULT TRUE,
    autoplay_previews   BOOLEAN DEFAULT TRUE,
    
    -- PIN for parental controls
    pin_hash            VARCHAR(60),  -- bcrypt
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_profile_name UNIQUE (account_id, name),
    CONSTRAINT ck_kids_maturity CHECK (
        NOT is_kids OR maturity_level = 'kids'
    )
);

CREATE INDEX idx_profiles_account ON profiles(account_id);


-- ===========================================
-- SECTION 3: CONTENT CATALOG (Master Data)
-- ===========================================

CREATE TYPE content_type AS ENUM ('movie', 'series', 'documentary', 'special');

CREATE TABLE content (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_type        content_type NOT NULL,
    
    -- Basic metadata
    title               VARCHAR(500) NOT NULL,
    original_title      VARCHAR(500),
    synopsis            TEXT,
    tagline             VARCHAR(500),
    
    -- Classification
    maturity_rating     VARCHAR(10) NOT NULL,  -- 'G', 'PG', 'PG-13', 'R', 'NC-17', 'TV-MA'
    release_year        INT,
    runtime_minutes     INT,
    
    -- Assets (URLs to CDN)
    poster_url          TEXT,
    backdrop_url        TEXT,
    trailer_url         TEXT,
    
    -- Aggregated ratings
    imdb_rating         DECIMAL(3,1),
    netflix_match_score DECIMAL(3,2),  -- 0.00 to 1.00
    
    -- Status
    is_original         BOOLEAN DEFAULT FALSE,  -- Netflix Original
    is_available        BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_content_type ON content(content_type);
CREATE INDEX idx_content_year ON content(release_year DESC);
CREATE INDEX idx_content_available ON content(is_available) WHERE is_available = TRUE;

-- Full-text search
CREATE INDEX idx_content_title_fts ON content USING GIN (to_tsvector('english', title || ' ' || COALESCE(synopsis, '')));


-- ===========================================
-- SECTION 4: SERIES STRUCTURE
-- ===========================================

CREATE TABLE seasons (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_id          UUID NOT NULL REFERENCES content(id),
    season_number       INT NOT NULL,
    title               VARCHAR(255),
    synopsis            TEXT,
    release_date        DATE,
    
    CONSTRAINT uk_season UNIQUE (content_id, season_number)
);

CREATE TABLE episodes (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    season_id           UUID NOT NULL REFERENCES seasons(id),
    episode_number      INT NOT NULL,
    
    title               VARCHAR(255) NOT NULL,
    synopsis            TEXT,
    runtime_minutes     INT NOT NULL,
    
    -- This is the actual playable video
    video_id            UUID NOT NULL,  -- Reference to NMDB video asset
    thumbnail_url       TEXT,
    
    release_date        DATE,
    
    CONSTRAINT uk_episode UNIQUE (season_id, episode_number)
);

CREATE INDEX idx_episodes_season ON episodes(season_id);


-- ===========================================
-- SECTION 5: VIDEOS (Playable Assets)
-- ===========================================

-- This table links to Netflix Media Database (NMDB) for actual streaming
CREATE TABLE videos (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_id          UUID NOT NULL REFERENCES content(id),
    episode_id          UUID REFERENCES episodes(id),  -- NULL for movies
    
    -- NMDB reference
    nmdb_asset_id       VARCHAR(255) NOT NULL UNIQUE,
    
    -- Duration for progress tracking
    duration_seconds    INT NOT NULL,
    
    -- Quality tiers available
    has_4k              BOOLEAN DEFAULT FALSE,
    has_hdr             BOOLEAN DEFAULT FALSE,
    has_dolby_vision    BOOLEAN DEFAULT FALSE,
    has_dolby_atmos     BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_videos_content ON videos(content_id);
CREATE INDEX idx_videos_episode ON videos(episode_id) WHERE episode_id IS NOT NULL;


-- ===========================================
-- SECTION 6: AUDIO/SUBTITLE TRACKS
-- ===========================================

CREATE TABLE audio_tracks (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id            UUID NOT NULL REFERENCES videos(id),
    language_code       VARCHAR(10) NOT NULL,  -- 'en', 'es', 'ja'
    language_name       VARCHAR(100) NOT NULL,  -- 'English', 'Spanish'
    track_type          VARCHAR(20) DEFAULT 'original',  -- 'original', 'dubbed'
    is_default          BOOLEAN DEFAULT FALSE,
    
    CONSTRAINT uk_audio_track UNIQUE (video_id, language_code, track_type)
);

CREATE TABLE subtitle_tracks (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id            UUID NOT NULL REFERENCES videos(id),
    language_code       VARCHAR(10) NOT NULL,
    language_name       VARCHAR(100) NOT NULL,
    track_type          VARCHAR(20) DEFAULT 'full',  -- 'full', 'forced', 'cc'
    is_default          BOOLEAN DEFAULT FALSE,
    
    CONSTRAINT uk_subtitle_track UNIQUE (video_id, language_code, track_type)
);


-- ===========================================
-- SECTION 7: GENRES AND TAGS
-- ===========================================

CREATE TABLE genres (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    slug                VARCHAR(100) NOT NULL UNIQUE
);

INSERT INTO genres (name, slug) VALUES
    ('Action', 'action'),
    ('Comedy', 'comedy'),
    ('Drama', 'drama'),
    ('Horror', 'horror'),
    ('Sci-Fi', 'sci-fi'),
    ('Documentary', 'documentary'),
    ('Romance', 'romance'),
    ('Thriller', 'thriller'),
    ('Animation', 'animation'),
    ('Kids', 'kids');

CREATE TABLE content_genres (
    content_id          UUID NOT NULL REFERENCES content(id),
    genre_id            INT NOT NULL REFERENCES genres(id),
    is_primary          BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (content_id, genre_id)
);

CREATE INDEX idx_content_genres_genre ON content_genres(genre_id);


-- ===========================================
-- SECTION 8: REGIONAL AVAILABILITY
-- ===========================================

CREATE TABLE content_availability (
    content_id          UUID NOT NULL REFERENCES content(id),
    country_code        VARCHAR(2) NOT NULL,  -- ISO 3166-1 alpha-2
    
    available_from      DATE NOT NULL,
    available_until     DATE,  -- NULL = indefinite
    
    -- Licensing restrictions
    has_download        BOOLEAN DEFAULT TRUE,
    
    PRIMARY KEY (content_id, country_code)
);

CREATE INDEX idx_availability_country ON content_availability(country_code);
CREATE INDEX idx_availability_dates ON content_availability(available_from, available_until);


-- ===========================================
-- SECTION 9: CAST AND CREW
-- ===========================================

CREATE TABLE people (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(255) NOT NULL,
    photo_url           TEXT,
    bio                 TEXT
);

CREATE TYPE role_type AS ENUM ('actor', 'director', 'writer', 'producer', 'creator');

CREATE TABLE content_credits (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_id          UUID NOT NULL REFERENCES content(id),
    person_id           UUID NOT NULL REFERENCES people(id),
    role_type           role_type NOT NULL,
    character_name      VARCHAR(255),  -- For actors
    billing_order       INT,
    
    CONSTRAINT uk_credit UNIQUE (content_id, person_id, role_type, character_name)
);

CREATE INDEX idx_credits_content ON content_credits(content_id);
CREATE INDEX idx_credits_person ON content_credits(person_id);
```

---

# Part 4: Cassandra DDL (Viewing Data)

```cql
-- ============================================================
-- NETFLIX SCHEMA: Apache Cassandra Production DDL
-- Keyspace: netflix_viewing
-- ============================================================

CREATE KEYSPACE IF NOT EXISTS netflix_viewing
WITH REPLICATION = {
    'class': 'NetworkTopologyStrategy',
    'us-east-1': 3,
    'us-west-2': 3,
    'eu-west-1': 3,
    'ap-southeast-1': 3
}
AND DURABLE_WRITES = true;

USE netflix_viewing;


-- ===========================================
-- VIEWING HISTORY BY PROFILE
-- Partition: profile_id + month (bucketed)
-- Clustering: viewed_at DESC
-- ===========================================

CREATE TABLE viewing_history_by_profile (
    profile_id      UUID,
    bucket_month    TEXT,           -- '2024-01' for partition sizing
    viewed_at       TIMESTAMP,
    video_id        UUID,
    
    -- Denormalized for fast reads
    content_id      UUID,
    content_title   TEXT,
    content_type    TEXT,           -- 'movie', 'episode'
    episode_info    TEXT,           -- 'S1:E3' or NULL for movies
    
    -- Watch stats
    duration_watched_s  INT,
    duration_total_s    INT,
    completed       BOOLEAN,
    
    -- Device info
    device_type     TEXT,           -- 'tv', 'mobile', 'web'
    device_id       TEXT,
    
    PRIMARY KEY ((profile_id, bucket_month), viewed_at)
) WITH CLUSTERING ORDER BY (viewed_at DESC)
  AND gc_grace_seconds = 86400
  AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',
    'compaction_window_size': 7
  };

-- Query: Get recent viewing history for a profile
-- SELECT * FROM viewing_history_by_profile 
-- WHERE profile_id = ? AND bucket_month = '2024-01'
-- LIMIT 50;


-- ===========================================
-- CONTINUE WATCHING (Hot Data)
-- Partition: profile_id
-- Clustering: last_watched_at DESC
-- Limited to ~50 items per profile
-- ===========================================

CREATE TABLE continue_watching_by_profile (
    profile_id      UUID,
    last_watched_at TIMESTAMP,
    video_id        UUID,
    
    -- Denormalized
    content_id      UUID,
    content_title   TEXT,
    content_type    TEXT,
    season_number   INT,
    episode_number  INT,
    episode_title   TEXT,
    thumbnail_url   TEXT,
    
    -- Progress
    progress_seconds    INT,
    duration_seconds    INT,
    progress_percent    INT,
    
    -- Next episode (for series)
    next_episode_id     UUID,
    
    PRIMARY KEY ((profile_id), last_watched_at, video_id)
) WITH CLUSTERING ORDER BY (last_watched_at DESC)
  AND gc_grace_seconds = 86400;

-- Query: Get continue watching list
-- SELECT * FROM continue_watching_by_profile 
-- WHERE profile_id = ?
-- LIMIT 40;


-- ===========================================
-- WATCH PROGRESS (Per Video per Profile)
-- Partition: profile_id
-- Clustering: video_id
-- ===========================================

CREATE TABLE watch_progress (
    profile_id      UUID,
    video_id        UUID,
    
    progress_seconds    INT,
    duration_seconds    INT,
    progress_percent    INT,
    completed           BOOLEAN,
    
    last_watched_at     TIMESTAMP,
    device_type         TEXT,
    
    PRIMARY KEY ((profile_id), video_id)
) WITH gc_grace_seconds = 86400;

-- Query: Get progress for specific video
-- SELECT * FROM watch_progress 
-- WHERE profile_id = ? AND video_id = ?;


-- ===========================================
-- CONTENT METADATA (Cassandra Mirror)
-- Partition: video_id (random distribution OK)
-- Populated from PostgreSQL via CDC
-- ===========================================

CREATE TABLE content_metadata (
    video_id        UUID PRIMARY KEY,
    content_id      UUID,
    content_type    TEXT,
    
    title           TEXT,
    synopsis        TEXT,
    maturity_rating TEXT,
    release_year    INT,
    runtime_minutes INT,
    
    poster_url      TEXT,
    backdrop_url    TEXT,
    
    genres          SET<TEXT>,
    cast_names      LIST<TEXT>,
    director_names  LIST<TEXT>,
    
    -- For series
    season_number   INT,
    episode_number  INT,
    episode_title   TEXT,
    
    -- Availability (populated per region request)
    is_available    BOOLEAN,
    
    updated_at      TIMESTAMP
) WITH gc_grace_seconds = 86400;


-- ===========================================
-- PERSONALIZED ROWS (Pre-computed)
-- Partition: profile_id
-- Clustering: row_rank, content_rank
-- Populated by ML pipelines
-- ===========================================

CREATE TABLE personalized_rows_by_profile (
    profile_id      UUID,
    row_rank        INT,            -- 1 = top row
    row_title       TEXT,           -- 'Top 10 in US', 'Because you watched...'
    row_type        TEXT,           -- 'top10', 'because_watched', 'trending'
    
    -- Content in this row
    content_rank    INT,
    content_id      UUID,
    content_title   TEXT,
    poster_url      TEXT,
    content_type    TEXT,
    match_score     DECIMAL,        -- Personalization score
    
    PRIMARY KEY ((profile_id), row_rank, content_rank)
) WITH CLUSTERING ORDER BY (row_rank ASC, content_rank ASC)
  AND gc_grace_seconds = 86400
  AND default_time_to_live = 86400;  -- Recomputed daily

-- Query: Get home page rows
-- SELECT * FROM personalized_rows_by_profile 
-- WHERE profile_id = ?;


-- ===========================================
-- USER RATINGS
-- Partition: profile_id
-- Clustering: rated_at DESC
-- ===========================================

CREATE TABLE user_ratings_by_profile (
    profile_id      UUID,
    rated_at        TIMESTAMP,
    content_id      UUID,
    
    rating          INT,            -- 1-5 stars or thumbs up/down
    rating_type     TEXT,           -- 'stars', 'thumbs'
    
    -- Denormalized
    content_title   TEXT,
    content_type    TEXT,
    
    PRIMARY KEY ((profile_id), rated_at)
) WITH CLUSTERING ORDER BY (rated_at DESC);

-- Also store by content for aggregation
CREATE TABLE user_ratings_by_content (
    content_id      UUID,
    rated_at        TIMESTAMP,
    profile_id      UUID,
    
    rating          INT,
    rating_type     TEXT,
    
    PRIMARY KEY ((content_id), rated_at)
) WITH CLUSTERING ORDER BY (rated_at DESC)
  AND gc_grace_seconds = 86400;


-- ===========================================
-- MY LIST (Saved for Later)
-- Partition: profile_id
-- ===========================================

CREATE TABLE my_list_by_profile (
    profile_id      UUID,
    added_at        TIMESTAMP,
    content_id      UUID,
    
    -- Denormalized
    content_title   TEXT,
    content_type    TEXT,
    poster_url      TEXT,
    maturity_rating TEXT,
    
    PRIMARY KEY ((profile_id), added_at, content_id)
) WITH CLUSTERING ORDER BY (added_at DESC);
```

---

# Part 5: EVCache (Memcached) Keys

```python
# ============================================================
# NETFLIX SCHEMA: EVCache Key Design
# ============================================================

# ===========================================
# CONTENT METADATA CACHE
# TTL: 1 hour (refreshed via CDC)
# ===========================================

# Key: content:{content_id}
# Value: JSON blob of content metadata
content:550e8400-e29b-41d4-a716-446655440000

# Key: video:{video_id}
# Value: Video metadata including streaming URLs
video:660f9511-f30c-52e5-b827-557766551111

# Key: content:avail:{content_id}:{country_code}
# Value: Availability details for country
content:avail:550e8400:US


# ===========================================
# WATCH PROGRESS CACHE
# TTL: 24 hours (hot path)
# ===========================================

# Key: progress:{profile_id}:{video_id}
# Value: {seconds: 1234, duration: 5678, percent: 21}
progress:profile-123:video-456


# ===========================================
# CONTINUE WATCHING CACHE
# TTL: 1 hour (frequently updated)
# ===========================================

# Key: continue:{profile_id}
# Value: List of continue watching items (top 40)
continue:profile-123


# ===========================================
# PERSONALIZED ROWS CACHE
# TTL: 1 hour (recomputed every few hours)
# ===========================================

# Key: home:{profile_id}
# Value: Pre-computed home page rows
home:profile-123


# ===========================================
# PROFILE PREFERENCES CACHE
# TTL: 1 day
# ===========================================

# Key: prefs:{profile_id}
# Value: Language, maturity, autoplay settings
prefs:profile-123


# ===========================================
# SEARCH TYPEAHEAD CACHE
# TTL: 1 day
# ===========================================

# Key: search:suggest:{prefix}
# Value: Top 10 suggestions for prefix
search:suggest:str
search:suggest:stra
search:suggest:stran
search:suggest:strang
search:suggest:strange
```

---

# Part 6: Viewing Event Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    VIEWING EVENT FLOW                            │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Client App      │
│  (play, pause,   │
│  seek, stop)     │
└────────┬─────────┘
         │ HTTP POST every 30s
         ▼
┌──────────────────┐
│  Viewing Service │
│  (Zuul Gateway)  │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌──────────────────┐
│  Kafka           │────►│  EVCache         │
│  viewing-events  │     │  (Write-through) │
│                  │     │                  │
│  100M events/day │     │  progress:{p}:{v}│
└────────┬─────────┘     │  continue:{p}    │
         │               └──────────────────┘
         │
    ┌────┴────────────────┐
    ▼                     ▼
┌──────────────────┐  ┌──────────────────┐
│  Flink           │  │  Cassandra       │
│  (Stream)        │  │  (Raw Events)    │
│                  │  │                  │
│  • Aggregations  │  │  viewing_history │
│  • Sessionization│  │  watch_progress  │
│  • ML features   │  │  continue_watchng│
└────────┬─────────┘  └──────────────────┘
         │
         ▼
┌──────────────────┐     ┌──────────────────┐
│  Spark           │────►│  Recommendation  │
│  (Batch ML)      │     │  Service         │
│                  │     │                  │
│  • Collaborative │     │  personalized_   │
│    filtering     │     │  rows_by_profile │
│  • Content-based │     └──────────────────┘
└──────────────────┘
```

---

# Part 7: Continue Watching Algorithm

```sql
-- PostgreSQL function to compute continue watching
-- (In practice, this runs in Flink/Spark and writes to Cassandra)

CREATE OR REPLACE FUNCTION get_continue_watching(
    p_profile_id UUID,
    p_limit INT DEFAULT 40
) RETURNS TABLE (
    video_id UUID,
    content_id UUID,
    title TEXT,
    progress_percent INT,
    next_episode_id UUID
) AS $$
BEGIN
    RETURN QUERY
    WITH recent_views AS (
        -- Get recently watched videos with incomplete progress
        SELECT 
            wp.video_id,
            v.content_id,
            c.title,
            wp.progress_percent,
            wp.last_watched_at
        FROM watch_progress wp
        JOIN videos v ON wp.video_id = v.id
        JOIN content c ON v.content_id = c.id
        WHERE wp.profile_id = p_profile_id
          AND wp.completed = FALSE
          AND wp.progress_percent > 5  -- Started watching
          AND wp.last_watched_at > NOW() - INTERVAL '30 days'
    ),
    with_next_episode AS (
        SELECT 
            rv.*,
            -- Find next unwatched episode for series
            (
                SELECT e2.id
                FROM episodes e
                JOIN episodes e2 ON e2.season_id = e.season_id
                WHERE v.episode_id = e.id
                  AND e2.episode_number = e.episode_number + 1
                  AND NOT EXISTS (
                      SELECT 1 FROM watch_progress wp2
                      WHERE wp2.profile_id = p_profile_id
                        AND wp2.video_id = (SELECT id FROM videos WHERE episode_id = e2.id)
                        AND wp2.completed = TRUE
                  )
            ) AS next_episode_id
        FROM recent_views rv
        JOIN videos v ON rv.video_id = v.id
    )
    SELECT 
        wne.video_id,
        wne.content_id,
        wne.title,
        wne.progress_percent,
        wne.next_episode_id
    FROM with_next_episode wne
    ORDER BY wne.last_watched_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Profile isolation | Partition by profile_id, not account_id |
| 2 | Viewing events async | Kafka → Cassandra, no blocking |
| 3 | EVCache for hot paths | progress, continue watching cached |
| 4 | Content CDC to Cassandra | Debezium from PostgreSQL |
| 5 | Monthly bucketing | viewing_history partitioned by month |
| 6 | Personalization pre-computed | ML pipelines write to Cassandra |
| 7 | TTL on row caches | 24h TTL on personalized_rows |
| 8 | Multi-region replication | NetworkTopologyStrategy 4 regions |

---

# Part 7: DynamoDB Single-Table Design

```
============================================================
NETFLIX: DynamoDB Single-Table Design
For high-scale playback sessions and rapid A/B testing
(Cassandra remains Primary for Viewing History at Netflix scale)
============================================================

TABLE: netflix_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (Session/Device queries)
- GSI2: GSI2PK / GSI2SK (Test Group queries)

============================================================
ENTITY PATTERNS
============================================================

PLAYBACK SESSION (Ephemeral)
  PK: SESS#{session_id}
  SK: STATE
  
  Attributes: profile_id, video_id, quality, bitrate, errors

AB TEST ASSIGNMENT
  PK: PROF#{profile_id}
  SK: EXP#{experiment_id}
  GSI2PK: EXP#{experiment_id}
  GSI2SK: GRP#{variant_group}
  
  Attributes: assignment_time, is_active

LIVE EVENT METADATA (e.g. Comedy Special)
  PK: LIVE#{event_id}
  SK: META
  
  Attributes: start_time, stream_url, chat_enabled

DEVICE CAPABILITY REGISTRY
  PK: DEV#{device_id}
  SK: CAP
  
  Attributes: max_res, hdr_support, audio_codecs

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get current playback state (Heartbeat)
   Table: PK=SESS#{session_id}, SK=STATE

2. Get user's experiment groups (Login)
   Table: PK=PROF#{profile_id}, SK begins_with "EXP#"

3. Find users in "Test Group B" for Experiment X
   GSI2: PK=EXP#{exp_id}, SK=GRP#{B}

4. Get capabilities for specific TV
   Table: PK=DEV#{tv_id}, SK=CAP
```

---

# Part 8: Query Examples with EXPLAIN

```sql
-- ============================================================
-- NETFLIX QUERY PATTERNS WITH EXPLAIN (Cassandra/Postgres)
-- ============================================================

-- ===========================================
-- QUERY 1: Get Profile Viewing History (Cassandra)
-- ===========================================

-- "What did I watch last week?"
SELECT video_id, viewed_at, duration_watched_s 
FROM viewing_history_by_profile 
WHERE profile_id = ? 
  AND bucket_month = '2023-11' 
ORDER BY viewed_at DESC;

-- Analysis: Hits single partition. Fast sequential read.
-- Partitioning by month prevents "Mega Partitions" for power users.


-- ===========================================
-- QUERY 2: Continue Watching (Cassandra)
-- ===========================================

-- "Resume where I left off"
SELECT video_id, progress_seconds, thumbnail_url 
FROM continue_watching_by_profile 
WHERE profile_id = ? 
LIMIT 20;

-- Analysis: Single partition read.
-- Data is small (hot set), fits in Memtable/Row Cache.


-- ===========================================
-- QUERY 3: Search Content (Elasticsearch)
-- ===========================================

-- "Find me action movies with Tom Cruise"
GET /content_index/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "cast": "Tom Cruise" } },
        { "term":  { "genre": "action" } }
      ],
      "filter": {
        "term": { "is_available_us": true }
      }
    }
  }
}

-- Analysis: Inverted index intersection. 
-- Filter clause is cached (bitset). Fast.


-- ===========================================
-- QUERY 4: Billing History (PostgreSQL)
-- ===========================================

-- "Show me my invoices"
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, amount, currency, status, billing_period_start
FROM invoices
WHERE account_id = $1
ORDER BY billing_period_start DESC;

-- Expected: Index Scan on idx_invoices_account.
```

---

# Part 9: Capacity Planning

```
============================================================
NETFLIX CAPACITY PLANNING
============================================================

ASSUMPTIONS (Global Scale):
- 250M Subscribers
- 1B Profiles
- Peak Traffic: 100M concurrent streams
- Viewing Events: 10B/day (Heartbeats every minute)

============================================================
STORAGE ESTIMATES
============================================================

VIEWING HISTORY (Cassandra)
  Rows: 10B/day * 100 bytes = 1 TB/day.
  Retention: Forever (User data is sacred).
  Total: ~5 PB historic data.
  Strategy: Tiered Compression. Recent (SSD), Old (HDD).

CONTENT CATALOG (Postgres/EVCache)
  Titles: 20K active titles.
  Metadata: Small (~50 GB). 
  Fits entirely in RAM (EVCache).

VIDEO ASSETS (CDN)
  Files: Petabytes of encoded chunks (A/V).
  Open Connect (OCDN) caches files at ISP edge.
  Database stores pointers (URLs), NOT content.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

PLAYBACK START (Read Critical):
- 50k starts/sec.
- Must return "Manifest" (URLs) in < 50ms.
- 100% Cache Hit Ratio target on manifest generation.

HEARTBEATS (Write Heavy):
- 100M streams * 1 beat/min = 1.6M writes/sec.
- Cassandra handles this easily with wide partitioning.
- Async write path (Client -> Proxy -> Kafka -> Cassandra).

PERSONALIZATION (Compute Heavy):
- Recomputing "Home Page" for 1B profiles.
- Offline Spark jobs run nightly.
- "Nearline" updates for "Because you watched X..." rows.

============================================================
SCALING STRATEGY
============================================================

1. ACTIVE-ACTIVE MULTI-REGION (Island Mode)
   - US-East, US-West, EU-West.
   - User routed to nearest region.
   - Data replicated bi-directionally via Cassandra/Kafka.
   - If US-East falls, route users to US-West.

2. SHARDING BY ACCOUNT
   - EVCache and Cassandra sharded by AccountID/ProfileID.
   - Consistent Hashing ensures even distribution.

3. CACHE WARMING
   - When deploying new code, warm the cache ("Cache Loader").
   - Never let a cold cache hit production traffic.
```

---

# Part 10: Anti-Patterns to Avoid

```
============================================================
NETFLIX ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Storing Viewing History in RDBMS
-----------------------------------------
WRONG:
  INSERT INTO history (user_id, video_id) ...
  -- 1.6M writes/sec kills Postgres WAL.
  
RIGHT:
  -- Cassandra / DynamoDB (LSM Tree storage).
  -- Optimized for append-heavy workloads.


❌ ANTI-PATTERN 2: Joins at Read Time
-----------------------------------------
WRONG:
  SELECT * FROM movies JOIN actors JOIN genres ...
  -- Too slow for "Home Page" load time (target < 50ms).
  
RIGHT:
  -- Denormalization. Store `actors_json` inside `movie` row.
  -- Document store model.


❌ ANTI-PATTERN 3: Global Secondary Indexes (GSI)
-----------------------------------------
WRONG:
  Cassandra: SELECT * FROM history WHERE video_id = X
  -- "Hot Partition" problem if video is popular.
  -- GSI involves scatter-gather.
  
RIGHT:
  -- Materialized View table `history_by_video`.
  -- Duplicate data for queries you need.


❌ ANTI-PATTERN 4: synchronous Network Calls
-----------------------------------------
WRONG:
  API calls Recommendation Service -> waits 500ms.
  
RIGHT:
  -- Hystrix / Resilience4j "Circuit Breakers".
  -- Fallback: If Recs down, show "Popular Titles" (Cached static list).


❌ ANTI-PATTERN 5: One Big Monolith Database
-----------------------------------------
WRONG:
  All services talk to "The DB".
  
RIGHT:
  -- Microservices own their data.
  -- "Billing" DB is separate from "Metadata" DB.
  -- Metadata Service exposes API, hides DB schema.


❌ ANTI-PATTERN 6: Ignoring Region Affinity
-----------------------------------------
WRONG:
  User in France reading from US-East DB.
  -- 100ms latency penalty.
  
RIGHT:
  -- Replicate data to EU-West.
  -- Route user to EU-West. Reads are local (< 1ms).


❌ ANTI-PATTERN 7: Calculating "Top 10" on the Fly
-----------------------------------------
WRONG:
  SELECT count(*) FROM views GROUP BY video_id
  -- Scans billions of rows.
  
RIGHT:
  -- Stream Processing (Flink/Spark Streaming) aggregates counts.
  -- Updates "Top 10" Redis key every minute.


❌ ANTI-PATTERN 8: Hard Delete of Content
-----------------------------------------
WRONG:
  DELETE FROM movies WHERE id = X.
  -- Breaks "History", "My List", "Recommendations".
  
RIGHT:
  -- Soft Delete (`is_available = false`).
  -- Filter out at presentation layer.


❌ ANTI-PATTERN 9: Caching User Data Forever
-----------------------------------------
WRONG:
  Cache `profile_prefs` with no TTL.
  -- Cache fills up with inactive users.
  
RIGHT:
  -- TTL (Time To Live) driven by session activity.
  -- Evict (LRU) when memory full.


❌ ANTI-PATTERN 10: Storing Session State in App Memory
-----------------------------------------
WRONG:
  Java Heap stores "User Session".
  -- Server restart = Logged out users.
  
RIGHT:
  -- Stateless Servers.
  -- Session State in Redis / EVCache.
```

---

# Part 11: CDC & Event Streaming

```
============================================================
NETFLIX CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ Cassandra   │────►│  AEGIST     │────►│  Kafka/Keystone │
│ (History)   │     │ (CDC Tool)  │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ Big Data  │    │ Search    │   │ Recs      │  │ Billing  │
  │ (Iceberg) │    │ Indexer   │   │ Training  │  │ Check    │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- viewing.start           (Update "Continue Watching")
- viewing.end             (Record Duration, Update ML)
- content.update          (Update Search Index, Cache Inval)
- account.churn           (Winback Campaigns)

============================================================
DISASTER RECOVERY
============================================================

RPO: < 1 minute (History), 0 (Billing)
RTO: < 10 minutes

STRATEGY:
1. Region Evacuation
   - If US-East fails, DNS repoints traffic to US-West.
   - Cassandra replication ensures data is already there.

2. Chaos Engineering (Chaos Monkey)
   - Randomly kill nodes/simulated region failure.
   - Ensures system automatically handles failures.

3. Fallback Modes
   - If "Personalized" fails -> Show "Standard".
   - If "Auth" fails -> Allow stream (Fail Open) for known devices? (Biz Decision).
```

---

# Part 12: Production Completeness DDL

```sql
-- ============================================================
-- NETFLIX: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / ACCESS LOG
-- ===========================================

CREATE TABLE content_access_log (
    account_id          UUID NOT NULL,
    profile_id          UUID NOT NULL,
    content_id          UUID NOT NULL,
    action_type         VARCHAR(50) NOT NULL,  -- 'play_start', 'play_end', 'browse'
    device_type         VARCHAR(50),
    device_id           VARCHAR(100),
    ip_address          INET,
    country_code        VARCHAR(2),
    accessed_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY ((account_id, profile_id), accessed_at, content_id)
) WITH CLUSTERING ORDER BY (accessed_at DESC);

-- Cassandra: TTL for auto-expiry after 2 years
-- ALTER TABLE content_access_log WITH default_time_to_live = 63072000;


-- ===========================================
-- B. CONTENT ASSETS (Pointers Only)
-- ===========================================

CREATE TABLE content_assets (
    content_id          UUID NOT NULL,
    asset_type          VARCHAR(50) NOT NULL,  -- 'video_master', 'audio_track', 'subtitle'
    quality_profile     VARCHAR(20),  -- '4k_hdr', '1080p', 'mobile'
    language_code       VARCHAR(10),
    storage_key         VARCHAR(500) NOT NULL,  -- S3/OpenConnect key
    cdn_url_template    VARCHAR(500),
    file_size_bytes     BIGINT,
    duration_ms         BIGINT,
    encoding_profile    VARCHAR(50),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY ((content_id), asset_type, quality_profile, language_code)
);


-- ===========================================
-- C. NOTIFICATIONS QUEUE (EVCache Preferred)
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    account_id          UUID NOT NULL,
    profile_id          UUID,
    channel             VARCHAR(20) NOT NULL,  -- 'push', 'email'
    notification_type   VARCHAR(100) NOT NULL,  -- 'new_episode', 'expiring_soon'
    title               VARCHAR(100),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS (Partner Integrations)
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id          UUID NOT NULL,
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['content.added', 'content.removed']
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- E. API KEYS (Partner API Only)
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id          UUID NOT NULL,
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 100,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- F. OAUTH / DEVICE AUTH
-- ===========================================

CREATE TABLE device_authorizations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL,
    profile_id          UUID,
    device_id           VARCHAR(100) NOT NULL,
    device_type         VARCHAR(50) NOT NULL,
    device_name         VARCHAR(100),
    activation_code     VARCHAR(10),  -- For TV activation flow
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uk_device UNIQUE (account_id, device_id)
);


-- ===========================================
-- G. USER SESSIONS (Viewed via EVCache)
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL,
    profile_id          UUID,
    device_id           UUID REFERENCES device_authorizations(id),
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    ip_address          INET NOT NULL,
    country_code        VARCHAR(2),
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS (A/B Testing at Scale)
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    target_countries    TEXT[],
    target_device_types TEXT[],
    target_plans        TEXT[],  -- 'basic', 'standard', 'premium'
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE ab_test_assignments (
    account_id          UUID NOT NULL,
    experiment_name     VARCHAR(100) NOT NULL,
    variant             VARCHAR(50) NOT NULL,
    assigned_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (account_id, experiment_name)
);
```

---

# Part 13: Operational Excellence & Internals

```
============================================================
NETFLIX: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. CASSANDRA WIDE PARTITION TUNING
============================================================

THE CHALLENGE:
Netflix viewing history: 250M accounts × 1000s of views per account
Partition Key: account_id
Risk: Wide partitions (>100MB) cause compaction hell

PARTITION SIZING GUIDELINES:
┌─────────────────────────────────────────────────────────────┐
│  PARTITION SIZE  │ STATUS     │ ACTION                     │
├─────────────────────────────────────────────────────────────┤
│  < 100 MB        │ Healthy    │ No action                  │
│  100 MB - 1 GB   │ Warning    │ Monitor, plan bucketing    │
│  > 1 GB          │ Critical   │ Immediate bucketing        │
└─────────────────────────────────────────────────────────────┘

BUCKETING STRATEGY (Time Bucketed Partitions):
OLD: viewing_history (account_id)
NEW: viewing_history (account_id, year_month)

Partition Key: (account_id, year_month)
Example: (acc123, '2024-01')

QUERY ADJUSTMENT:
-- Old (unbounded)
SELECT * FROM viewing_history WHERE account_id = ?

-- New (bounded)
SELECT * FROM viewing_history 
WHERE account_id = ? AND year_month IN ('2024-01', '2023-12', '2023-11')

COMPACTION STRATEGY (TWCS for Time-Series):
```cql
ALTER TABLE viewing_history WITH compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_size': 1,
    'compaction_window_unit': 'DAYS'
};
```

WHY TWCS:
- Writes go to today's window only
- Old windows are read-only → no re-compaction
- TTL cleanup is efficient (whole SSTable removal)

============================================================
2. EVCACHE (NETFLIX'S MEMCACHED FORK) INTERNALS
============================================================

ARCHITECTURE:
┌─────────────────────────────────────────────────────────────┐
│                     EVCache Cluster                          │
├─────────────────────────────────────────────────────────────┤
│  App → EVCache Client → Server Pool (Sharded)               │
│                       → Hot-key Detection                   │
│                       → Zone Affinity (Same AZ preference)  │
└─────────────────────────────────────────────────────────────┘

KEY EVCACHE TUNINGS:
- Zone Fallback: If local AZ cache misses, try remote AZ before DB
- Chunking: Large values (>1MB) are auto-chunked across keys
- Write-Through: Dual-write to cache + async to Cassandra

CLUSTER TOPOLOGY:
┌─────────────────────────────────────────────────────────────┐
│  CACHE CLUSTER      │ NODES  │ MEMORY  │ TTL              │
├─────────────────────────────────────────────────────────────┤
│  Catalog            │ 100    │ 64 GB   │ 24 hours         │
│  Viewing History    │ 200    │ 128 GB  │ 30 days          │
│  Personalization    │ 300    │ 256 GB  │ 6 hours          │
│  Session            │ 50     │ 32 GB   │ 1 hour           │
│  Manifest/URLs      │ 100    │ 64 GB   │ 5 minutes        │
└─────────────────────────────────────────────────────────────┘

EVICTION POLICY:
- Default: LRU (Least Recently Used)
- Override for Personalization: LFU (Least Frequently Used)
  - Reason: Daily users should never be evicted
  - Churn users can be evicted

CACHE WARMING:
```
Pre-deployment Steps:
1. Identify top 10M active accounts (last 7 days)
2. Run cache loader job against Cassandra
3. Load viewing_history, preferences, my_list
4. Verify hit rate > 90% before shifting traffic
```

============================================================
3. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Playback Start Latency (p99) │ < 3s    │ > 5s = PAGE     │
│  Manifest Fetch (p99)         │ < 100ms │ > 200ms = PAGE  │
│  Home Page Load (p99)         │ < 500ms │ > 1s = PAGE     │
│  EVCache Hit Rate             │ > 95%   │ < 90% = PAGE    │
│  Cassandra Read Latency (p99) │ < 50ms  │ > 100ms = WARN  │
└─────────────────────────────────────────────────────────────┘

CASSANDRA METRICS TO WATCH:
- `pending_compactions` (should be < 10)
- `read_latency_99th_percentile` per table
- `tombstone_scanned_histogram` (high = bad data model)
- `dropped_mutations` (MUST be 0)
- `sstable_count_per_read` (should be < 5 with TWCS)

EVCACHE METRICS:
- `hit_rate` per cache pool
- `evicted_items_count` (spike = memory pressure)
- `connection_queue_depth` (> 0 = client backpressure)
- `miss_latency` (cache miss → how long to fill)

KAFKA METRICS (CDC):
- `viewing.event` topic: Consumer lag < 30s
- `content.update` topic: Producer throughput
- Partition imbalance check

ALERTING RULES:
```yaml
# Prometheus AlertManager
- alert: CassandraCompactionBacklog
  expr: cassandra_pending_compactions > 20
  for: 10m
  labels:
    severity: warning

- alert: EVCacheHitRateLow
  expr: evcache_hit_rate < 0.90
  for: 5m
  labels:
    severity: page

- alert: PlaybackStartSlow
  expr: histogram_quantile(0.99, playback_start_latency_seconds) > 5
  for: 3m
  labels:
    severity: page
```

============================================================
4. FAILURE MODE ANALYSIS (CHAOS ENGINEERING)
============================================================

SCENARIO 1: EVCACHE CLUSTER FAILURE (SINGLE AZ)
-----------------------------------------
Symptom: 33% of cache requests failing.
Impact: Cassandra load spikes 3x.

Mitigation:
1. Zone Fallback: Client auto-routes to other AZ
2. Circuit Breaker: If latency > 500ms, skip cache
3. Cassandra Read Replicas absorb load
4. Graceful Degradation: Show "Popular Titles" if personalization slow

SCENARIO 2: WIDE PARTITION TIMEOUT
-----------------------------------------
Symptom: Specific accounts have 10+ second reads.
Impact: Account-level degradation.

Mitigation:
1. Query Timeout: 5s hard limit
2. Paginated Reads: LIMIT 100 + Token pagination
3. Background job: Detect > 100MB partitions → flag for compaction
4. Account-specific circuit breaker

SCENARIO 3: CASSANDRA NODE FAILURE (1 of 12 per DC)
-----------------------------------------
Symptom: 8% of reads require cross-rack hop.
Impact: p99 latency increases 20ms.

Mitigation:
1. Replication Factor: 3 (can lose 1 node per DC)
2. Speculative Retry: If primary slow, fire parallel request
3. Operator: Anti-entropy repair runs daily
4. Replacement: Auto-healing with orchestrator

SCENARIO 4: CONTENT CATALOG CACHE STAMPEDE
-----------------------------------------
Symptom: New release → catalog cache TTL expires → 10M requests hit DB.
Impact: PostgreSQL connection exhaustion.

Mitigation:
1. Staggered TTL: Base TTL ± random(0-60s)
2. Single-Flight: One request fills cache, others wait
3. Always-On Cache: Critical catalog never expires
4. Warm-on-Write: CDC triggers cache update

SCENARIO 5: REGION EVACUATION
-----------------------------------------
Symptom: US-East-1 outage.
Impact: 40% of traffic needs rerouting.

Mitigation:
1. Active-Active: All regions serve traffic
2. DNS Failover: Route53 health checks → automatic
3. Data Replication: Cassandra cross-region async
4. Stateless Services: No session affinity required
5. Practice: Chaos Monkey monthly "Chaos Kong" exercise

============================================================
5. FINOPS & COST OPTIMIZATION
============================================================

TIERING STRATEGY:
┌─────────────────────────────────────────────────────────────┐
│  DATA              │ AGE       │ STORAGE      │ ACCESS     │
├─────────────────────────────────────────────────────────────┤
│  Viewing History   │ < 90 days │ Cassandra    │ Real-time  │
│  Viewing History   │ > 90 days │ Iceberg/S3   │ Batch ML   │
│  Content Catalog   │ Active    │ PostgreSQL   │ Cached     │
│  Video Files       │ All       │ S3 + OCDN    │ Edge       │
│  ML Features       │ 7 days    │ Redis        │ Real-time  │
└─────────────────────────────────────────────────────────────┘

CASSANDRA COST OPTIMIZATION:
- i4i instances (NVMe) for hot data
- d3 instances (HDD) for cold/archive
- ZSTD compression: 60%+ savings
- TTL: Auto-purge old viewing data

EVCACHE COST OPTIMIZATION:
- Graviton3 (r7g): 20% cheaper than x86
- Memory tiering: Flash-based EVCache for warm data
- Right-sizing: Monthly capacity review

INSTANCE SIZING (AWS Example):
```
EVCache (Personalization): 100x r7g.4xlarge
EVCache (Catalog):          50x r7g.2xlarge
Cassandra (Hot):            100x i4i.2xlarge
Cassandra (Warm):           50x d3.2xlarge
PostgreSQL (Catalog):       5x db.r6g.4xlarge
Kafka (CDC):                20x kafka.m5.2xlarge
```

COST BREAKDOWN (Estimated Monthly):
- EVCache: $250K
- Cassandra: $400K
- PostgreSQL: $50K
- Kafka: $80K
- S3/OCDN: $500K (video delivery)
- Analytics (Spark/Iceberg): $200K
- Total Data Layer: ~$1.5M/month
```

---

## 🔗 Related Documents

- [NoSQL Architecture](./nosql-architecture-guide.md) — Cassandra internals
- [TSDB Architecture](./tsdb-architecture-guide.md) — Time-series patterns
- [Uber Schema](./uber-schema-design-guide.md) — Similar polyglot pattern
- [Twitter Schema](./twitter-schema-design-guide.md) — Operational Excellence reference
