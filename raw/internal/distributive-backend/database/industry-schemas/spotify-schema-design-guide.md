# Spotify Music Streaming: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Tracks, Albums, Artists, Playlists, Listening History, Recommendations — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Treating playlists as simple many-to-many. Spotify playlists are **collaborative**, **ordered**, and **versioned** — complex beasts that need careful modeling.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [How Spotify Uses Cassandra](https://engineering.atspotify.com/2021/01/advancing-cassandra/) | NoSQL at scale |
| [Spotify's Event Delivery](https://engineering.atspotify.com/2022/06/event-delivery-the-journey/) | Event-driven architecture |
| [Spotify Recommendations](https://research.atspotify.com/) | ML recommendations |

---

## 🎯 The Principal Laws of Music Streaming Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Read-Heavy Catalog** | Same track metadata read billions of times | Aggressive caching, denormalization |
| **Law 2: Playlist Complexity** | Order matters, collaboration matters | Track ordering via position/rank |
| **Law 3: Listening Is Write-Heavy** | Every play is an event | Cassandra for listening history |
| **Law 4: Recommendations Are Pre-computed** | Too expensive to compute on-the-fly | Daily/hourly batch + cache |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get track metadata | 100M/s | < 10ms | Cache + PostgreSQL |
| 2 | Get album with tracks | 10M/s | < 20ms | Cache + PostgreSQL |
| 3 | Get artist with discography | 5M/s | < 50ms | Cache + PostgreSQL |
| 4 | Get user's playlists | 10M/s | < 20ms | Cache + Cassandra |
| 5 | Get playlist tracks (ordered) | 20M/s | < 30ms | Cassandra |
| 6 | Record listening event (play) | 50M/s | < 100ms | Kafka → Cassandra |
| 7 | Get listening history | 1M/s | < 100ms | Cassandra |
| 8 | Get personalized home page | 10M/s | < 50ms | Pre-computed cache |
| 9 | Search tracks/artists/albums | 5M/s | < 100ms | Elasticsearch |
| 10 | Get Discover Weekly playlist | 5M/s | < 20ms | Pre-computed cache |

---

# Part 2: Database Selection Matrix

```
┌─────────────────────────────────────────────────────────────────┐
│                    SPOTIFY DATA ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                               │
│  ✓ Master catalog    ✓ Complex joins   ✓ ACID for billing       │
│                                                                  │
│  • tracks, albums, artists (catalog)                             │
│  • users, accounts, subscriptions                                │
│  • playlist_metadata                                             │
│  • content_rights, royalties                                     │
└─────────────────────────────────────────────────────────────────┘
                              │ CDC (Debezium)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Apache Cassandra                         │
│  ✓ Playlist tracks    ✓ Listening history   ✓ User libraries    │
│                                                                  │
│  • playlist_tracks_by_playlist                                   │
│  • listening_history_by_user                                     │
│  • user_library_tracks                                           │
│  • user_following_artists                                        │
│  • artist_top_tracks_by_country                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Redis / Memcached                        │
│  ✓ Track cache    ✓ Playlist cache   ✓ Session state            │
│                                                                  │
│  • track:{track_id}                                              │
│  • album:{album_id}                                              │
│  • artist:{artist_id}                                            │
│  • playlist:meta:{playlist_id}                                   │
│  • home:{user_id}                                                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Elasticsearch                            │
│  ✓ Full-text search    ✓ Typeahead   ✓ Fuzzy matching           │
│                                                                  │
│  • tracks_search                                                 │
│  • artists_search                                                │
│  • albums_search                                                 │
│  • playlists_search                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL (Catalog & Accounts)

```sql
-- ============================================================
-- SPOTIFY SCHEMA: PostgreSQL Production DDL
-- Version: Music catalog and account management
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";


-- ===========================================
-- SECTION 1: ARTISTS
-- ===========================================

CREATE TABLE artists (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    spotify_uri         VARCHAR(100) NOT NULL UNIQUE,  -- spotify:artist:xxx
    
    name                VARCHAR(500) NOT NULL,
    bio                 TEXT,
    
    -- Images
    image_url_large     TEXT,
    image_url_medium    TEXT,
    image_url_small     TEXT,
    
    -- Stats (denormalized, updated periodically)
    follower_count      BIGINT DEFAULT 0,
    monthly_listeners   BIGINT DEFAULT 0,
    
    -- Metadata
    genres              TEXT[],
    country             VARCHAR(2),  -- ISO country
    
    -- Verification
    is_verified         BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_artists_name ON artists(name);
CREATE INDEX idx_artists_name_trgm ON artists USING GIN (name gin_trgm_ops);
CREATE INDEX idx_artists_genres ON artists USING GIN (genres);
CREATE INDEX idx_artists_followers ON artists(follower_count DESC);


-- ===========================================
-- SECTION 2: ALBUMS
-- ===========================================

CREATE TYPE album_type AS ENUM ('album', 'single', 'ep', 'compilation');

CREATE TABLE albums (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    spotify_uri         VARCHAR(100) NOT NULL UNIQUE,
    
    name                VARCHAR(500) NOT NULL,
    album_type          album_type NOT NULL DEFAULT 'album',
    
    -- Release info
    release_date        DATE,
    release_date_precision VARCHAR(10),  -- 'day', 'month', 'year'
    
    -- Images
    image_url_large     TEXT,
    image_url_medium    TEXT,
    image_url_small     TEXT,
    
    -- Artist (primary - for display)
    primary_artist_id   UUID REFERENCES artists(id),
    
    -- Stats
    total_tracks        INT NOT NULL DEFAULT 0,
    total_duration_ms   BIGINT DEFAULT 0,
    
    -- Classification
    genres              TEXT[],
    label               VARCHAR(255),
    copyright           TEXT,
    
    -- Availability
    available_markets   TEXT[],  -- ISO country codes
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_albums_artist ON albums(primary_artist_id);
CREATE INDEX idx_albums_name ON albums(name);
CREATE INDEX idx_albums_name_trgm ON albums USING GIN (name gin_trgm_ops);
CREATE INDEX idx_albums_release ON albums(release_date DESC);

-- Album-Artist relationship (many-to-many for collaborations)
CREATE TABLE album_artists (
    album_id            UUID NOT NULL REFERENCES albums(id),
    artist_id           UUID NOT NULL REFERENCES artists(id),
    artist_order        INT NOT NULL DEFAULT 0,
    
    PRIMARY KEY (album_id, artist_id)
);


-- ===========================================
-- SECTION 3: TRACKS
-- ===========================================

CREATE TABLE tracks (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    spotify_uri         VARCHAR(100) NOT NULL UNIQUE,
    isrc                VARCHAR(20),  -- International Standard Recording Code
    
    name                VARCHAR(500) NOT NULL,
    
    -- Album relationship
    album_id            UUID NOT NULL REFERENCES albums(id),
    disc_number         INT DEFAULT 1,
    track_number        INT NOT NULL,
    
    -- Duration
    duration_ms         INT NOT NULL,
    
    -- Audio features (populated by audio analysis)
    tempo               DECIMAL(6,3),  -- BPM
    time_signature      INT,           -- 3, 4, 5, etc.
    key                 INT,           -- 0-11 (C to B)
    mode                INT,           -- 0 = minor, 1 = major
    loudness            DECIMAL(6,3),  -- dB
    
    -- Derived audio features (-1 to 1 or 0 to 1)
    danceability        DECIMAL(5,4),
    energy              DECIMAL(5,4),
    speechiness         DECIMAL(5,4),
    acousticness        DECIMAL(5,4),
    instrumentalness    DECIMAL(5,4),
    liveness            DECIMAL(5,4),
    valence             DECIMAL(5,4),  -- Musical positivity
    
    -- Primary artist (for display)
    primary_artist_id   UUID REFERENCES artists(id),
    
    -- Content flags
    is_explicit         BOOLEAN DEFAULT FALSE,
    is_playable         BOOLEAN DEFAULT TRUE,
    
    -- Stats (denormalized)
    play_count          BIGINT DEFAULT 0,
    popularity          INT DEFAULT 0,  -- 0-100
    
    -- Preview
    preview_url         TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_tracks_album ON tracks(album_id);
CREATE INDEX idx_tracks_artist ON tracks(primary_artist_id);
CREATE INDEX idx_tracks_name ON tracks(name);
CREATE INDEX idx_tracks_name_trgm ON tracks USING GIN (name gin_trgm_ops);
CREATE INDEX idx_tracks_isrc ON tracks(isrc) WHERE isrc IS NOT NULL;
CREATE INDEX idx_tracks_popularity ON tracks(popularity DESC);
CREATE INDEX idx_tracks_genre_tempo ON tracks(tempo, energy, danceability);

-- Track-Artist relationship (features, collaborations)
CREATE TABLE track_artists (
    track_id            UUID NOT NULL REFERENCES tracks(id),
    artist_id           UUID NOT NULL REFERENCES artists(id),
    artist_order        INT NOT NULL DEFAULT 0,
    role                VARCHAR(50) DEFAULT 'primary',  -- 'primary', 'featured', 'remixer'
    
    PRIMARY KEY (track_id, artist_id)
);

CREATE INDEX idx_track_artists_artist ON track_artists(artist_id);


-- ===========================================
-- SECTION 4: USERS AND ACCOUNTS
-- ===========================================

CREATE TYPE subscription_tier AS ENUM ('free', 'premium', 'family', 'student', 'duo');

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    spotify_uri         VARCHAR(100) NOT NULL UNIQUE,
    
    -- Authentication
    email               VARCHAR(255) NOT NULL UNIQUE,
    password_hash       TEXT NOT NULL,
    
    -- Profile
    display_name        VARCHAR(100),
    profile_image_url   TEXT,
    country             VARCHAR(2),
    
    -- Subscription
    subscription_tier   subscription_tier DEFAULT 'free',
    subscription_expiry DATE,
    
    -- Stats
    follower_count      INT DEFAULT 0,
    following_count     INT DEFAULT 0,
    playlist_count      INT DEFAULT 0,
    
    -- Preferences
    explicit_content    BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_active_at      TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_country ON users(country);
CREATE INDEX idx_users_subscription ON users(subscription_tier);


-- ===========================================
-- SECTION 5: PLAYLISTS (Metadata in PostgreSQL)
-- ===========================================

CREATE TABLE playlists (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    spotify_uri         VARCHAR(100) NOT NULL UNIQUE,
    
    -- Ownership
    owner_id            UUID NOT NULL REFERENCES users(id),
    
    -- Metadata
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    image_url           TEXT,
    
    -- Flags
    is_public           BOOLEAN DEFAULT TRUE,
    is_collaborative    BOOLEAN DEFAULT FALSE,
    
    -- Stats (denormalized)
    track_count         INT DEFAULT 0,
    total_duration_ms   BIGINT DEFAULT 0,
    follower_count      INT DEFAULT 0,
    
    -- Versioning for sync
    snapshot_id         VARCHAR(100) NOT NULL,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_playlists_owner ON playlists(owner_id);
CREATE INDEX idx_playlists_name_trgm ON playlists USING GIN (name gin_trgm_ops);
CREATE INDEX idx_playlists_public ON playlists(is_public) WHERE is_public = TRUE;
CREATE INDEX idx_playlists_followers ON playlists(follower_count DESC);


-- ===========================================
-- SECTION 6: USER FOLLOWING
-- ===========================================

CREATE TABLE user_follows_artists (
    user_id             UUID NOT NULL REFERENCES users(id),
    artist_id           UUID NOT NULL REFERENCES artists(id),
    followed_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (user_id, artist_id)
);

CREATE INDEX idx_follows_artist ON user_follows_artists(artist_id);

CREATE TABLE user_follows_users (
    follower_id         UUID NOT NULL REFERENCES users(id),
    following_id        UUID NOT NULL REFERENCES users(id),
    followed_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (follower_id, following_id),
    CONSTRAINT ck_no_self_follow CHECK (follower_id != following_id)
);

CREATE TABLE user_follows_playlists (
    user_id             UUID NOT NULL REFERENCES users(id),
    playlist_id         UUID NOT NULL REFERENCES playlists(id),
    followed_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (user_id, playlist_id)
);
```

---

# Part 4: Cassandra DDL (Playlists, Listening, Libraries)

```cql
-- ============================================================
-- SPOTIFY SCHEMA: Apache Cassandra Production DDL
-- Keyspace: spotify_user_data
-- ============================================================

CREATE KEYSPACE IF NOT EXISTS spotify_user_data
WITH REPLICATION = {
    'class': 'NetworkTopologyStrategy',
    'us-east-1': 3,
    'us-west-2': 3,
    'eu-west-1': 3
}
AND DURABLE_WRITES = true;

USE spotify_user_data;


-- ===========================================
-- PLAYLIST TRACKS
-- Partition: playlist_id
-- Clustering: position (for ordering)
-- ===========================================

CREATE TABLE playlist_tracks (
    playlist_id     UUID,
    position        INT,            -- 0-indexed position in playlist
    added_at        TIMESTAMP,
    added_by        UUID,           -- User who added (for collaborative)
    
    track_id        UUID,
    
    -- Denormalized track metadata (for fast display)
    track_name      TEXT,
    track_duration_ms INT,
    artist_name     TEXT,
    artist_id       UUID,
    album_name      TEXT,
    album_id        UUID,
    album_image_url TEXT,
    is_explicit     BOOLEAN,
    
    PRIMARY KEY ((playlist_id), position)
) WITH CLUSTERING ORDER BY (position ASC)
  AND gc_grace_seconds = 86400;

-- Query: Get all tracks in playlist (ordered)
-- SELECT * FROM playlist_tracks WHERE playlist_id = ?;


-- ===========================================
-- PLAYLIST TRACKS BY ADDED DATE (for history)
-- ===========================================

CREATE TABLE playlist_tracks_by_added (
    playlist_id     UUID,
    added_at        TIMESTAMP,
    position        INT,
    track_id        UUID,
    
    track_name      TEXT,
    artist_name     TEXT,
    added_by        UUID,
    
    PRIMARY KEY ((playlist_id), added_at, position)
) WITH CLUSTERING ORDER BY (added_at DESC);


-- ===========================================
-- USER LIBRARY (Saved Tracks)
-- Partition: user_id
-- Clustering: added_at DESC
-- ===========================================

CREATE TABLE user_saved_tracks (
    user_id         UUID,
    added_at        TIMESTAMP,
    track_id        UUID,
    
    -- Denormalized
    track_name      TEXT,
    track_duration_ms INT,
    artist_name     TEXT,
    artist_id       UUID,
    album_name      TEXT,
    album_id        UUID,
    album_image_url TEXT,
    is_explicit     BOOLEAN,
    
    PRIMARY KEY ((user_id), added_at, track_id)
) WITH CLUSTERING ORDER BY (added_at DESC);

-- Query: Get user's saved tracks
-- SELECT * FROM user_saved_tracks WHERE user_id = ? LIMIT 50;


-- ===========================================
-- USER SAVED ALBUMS
-- ===========================================

CREATE TABLE user_saved_albums (
    user_id         UUID,
    added_at        TIMESTAMP,
    album_id        UUID,
    
    -- Denormalized
    album_name      TEXT,
    artist_name     TEXT,
    artist_id       UUID,
    album_image_url TEXT,
    release_date    DATE,
    total_tracks    INT,
    
    PRIMARY KEY ((user_id), added_at, album_id)
) WITH CLUSTERING ORDER BY (added_at DESC);


-- ===========================================
-- LISTENING HISTORY
-- Partition: user_id + month (bucketed)
-- Clustering: played_at DESC
-- ===========================================

CREATE TABLE listening_history (
    user_id         UUID,
    bucket_month    TEXT,           -- '2024-01'
    played_at       TIMESTAMP,
    
    track_id        UUID,
    context_type    TEXT,           -- 'playlist', 'album', 'artist', 'search'
    context_id      UUID,           -- ID of playlist/album/artist
    
    -- Denormalized
    track_name      TEXT,
    artist_name     TEXT,
    album_name      TEXT,
    
    -- Playback details
    duration_played_ms  INT,
    skipped         BOOLEAN,
    shuffle         BOOLEAN,
    repeat_mode     TEXT,           -- 'off', 'track', 'context'
    
    -- Device
    device_type     TEXT,           -- 'mobile', 'desktop', 'speaker'
    
    PRIMARY KEY ((user_id, bucket_month), played_at)
) WITH CLUSTERING ORDER BY (played_at DESC)
  AND gc_grace_seconds = 86400
  AND default_time_to_live = 31536000  -- 1 year TTL
  AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',
    'compaction_window_size': 7
  };


-- ===========================================
-- RECENTLY PLAYED (Hot Data, Short TTL)
-- Partition: user_id
-- Limit ~50 items
-- ===========================================

CREATE TABLE recently_played (
    user_id         UUID,
    played_at       TIMESTAMP,
    
    track_id        UUID,
    context_type    TEXT,
    context_id      UUID,
    
    track_name      TEXT,
    artist_name     TEXT,
    album_image_url TEXT,
    
    PRIMARY KEY ((user_id), played_at)
) WITH CLUSTERING ORDER BY (played_at DESC)
  AND gc_grace_seconds = 86400
  AND default_time_to_live = 604800;  -- 7 days

-- Query: Get recently played
-- SELECT * FROM recently_played WHERE user_id = ? LIMIT 50;


-- ===========================================
-- ARTIST TOP TRACKS BY COUNTRY
-- Partition: artist_id + country
-- Populated by batch analytics
-- ===========================================

CREATE TABLE artist_top_tracks (
    artist_id       UUID,
    country_code    TEXT,           -- 'US', 'GB', 'DE', etc.
    rank            INT,            -- 1-10
    
    track_id        UUID,
    track_name      TEXT,
    album_name      TEXT,
    album_image_url TEXT,
    play_count      BIGINT,
    
    PRIMARY KEY ((artist_id, country_code), rank)
) WITH CLUSTERING ORDER BY (rank ASC)
  AND gc_grace_seconds = 86400
  AND default_time_to_live = 86400;  -- Refreshed daily


-- ===========================================
-- PERSONALIZED RECOMMENDATIONS
-- Partition: user_id
-- Populated by ML pipelines
-- ===========================================

CREATE TABLE discover_weekly (
    user_id         UUID,
    generated_at    TIMESTAMP,
    position        INT,
    
    track_id        UUID,
    track_name      TEXT,
    artist_name     TEXT,
    artist_id       UUID,
    album_image_url TEXT,
    
    -- Why recommended
    reason_type     TEXT,           -- 'similar_artist', 'similar_track', 'collab_filter'
    reason_id       UUID,           -- Related artist/track ID
    
    PRIMARY KEY ((user_id), position)
) WITH CLUSTERING ORDER BY (position ASC)
  AND default_time_to_live = 604800;  -- Refreshed weekly


CREATE TABLE daily_mix (
    user_id         UUID,
    mix_number      INT,            -- 1-6
    position        INT,
    
    track_id        UUID,
    track_name      TEXT,
    artist_name     TEXT,
    album_image_url TEXT,
    
    PRIMARY KEY ((user_id, mix_number), position)
) WITH CLUSTERING ORDER BY (position ASC)
  AND default_time_to_live = 86400;  -- Refreshed daily


-- ===========================================
-- USER TASTE PROFILE (ML Features)
-- Partition: user_id
-- ===========================================

CREATE TABLE user_taste_profile (
    user_id             UUID PRIMARY KEY,
    
    -- Top genres (weighted)
    top_genres          MAP<TEXT, DECIMAL>,
    
    -- Audio feature averages
    avg_tempo           DECIMAL,
    avg_energy          DECIMAL,
    avg_danceability    DECIMAL,
    avg_valence         DECIMAL,
    avg_acousticness    DECIMAL,
    
    -- Top artists (last 4 weeks)
    top_artist_ids      LIST<UUID>,
    
    -- Listening patterns
    peak_listening_hour INT,        -- 0-23
    avg_session_length_min INT,
    
    updated_at          TIMESTAMP
) WITH gc_grace_seconds = 86400;
```

---

# Part 5: Playlist Track Ordering

```sql
-- PostgreSQL function for playlist reordering
-- Spotify uses a position-based system with gap management

CREATE OR REPLACE FUNCTION reorder_playlist_track(
    p_playlist_id UUID,
    p_track_id UUID,
    p_new_position INT
) RETURNS VOID AS $$
DECLARE
    v_old_position INT;
    v_max_position INT;
BEGIN
    -- In practice, this updates Cassandra via an API call
    -- This shows the logic pattern
    
    -- 1. Get current position
    -- SELECT position INTO v_old_position FROM playlist_tracks...
    
    -- 2. Shift other tracks
    -- If moving down (new > old): shift tracks between old and new UP by 1
    -- If moving up (new < old): shift tracks between new and old DOWN by 1
    
    -- 3. Update target track to new position
    
    -- 4. Update snapshot_id in PostgreSQL for sync
    UPDATE playlists 
    SET snapshot_id = uuid_generate_v4()::text,
        updated_at = NOW()
    WHERE id = p_playlist_id;
END;
$$ LANGUAGE plpgsql;
```

---

# Part 6: Listening Event Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    LISTENING EVENT FLOW                          │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Client App      │
│  (play, skip,    │
│  seek, complete) │
└────────┬─────────┘
         │ Event every track start/end/skip
         ▼
┌──────────────────┐
│  Kafka           │
│  listening-events│
│                  │
│  50M events/day  │
└────────┬─────────┘
         │
    ┌────┴────────────────┬──────────────────┐
    ▼                     ▼                  ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  Flink           │  │  Cassandra       │  │  BigQuery        │
│  (Real-time)     │  │  (User Data)     │  │  (Analytics)     │
│                  │  │                  │  │                  │
│  • Recently      │  │  listening_      │  │  • Royalty       │
│    played update │  │  history         │  │    calculations  │
│  • Taste profile │  │  recently_played │  │  • Charts        │
│    update        │  │                  │  │  • Artist stats  │
└────────┬─────────┘  └──────────────────┘  └──────────────────┘
         │
         ▼
┌──────────────────┐     ┌──────────────────┐
│  ML Pipeline     │────►│  Cassandra       │
│  (Batch)         │     │  (Recommendations)│
│                  │     │                  │
│  • Discover      │     │  discover_weekly │
│    Weekly        │     │  daily_mix       │
│  • Daily Mix     │     │  user_taste_     │
│  • Release Radar │     │  profile         │
└──────────────────┘     └──────────────────┘
```

---

# Part 7: Collaborative Filtering Sketch

```python
# Simplified collaborative filtering for track recommendations
# (Real Spotify uses much more sophisticated ML)

"""
User-Item Matrix (Implicit Feedback):
        Track1  Track2  Track3  Track4  ...
User1    5       0       3       0
User2    0       4       0       5
User3    3       0       4       0
User4    0       5       0       4

Where values = play_count or listen_duration

Finding similar users:
- Use cosine similarity on user vectors
- Users who listen to similar tracks are "similar"

Recommending tracks:
- Find top-K similar users
- Aggregate their top tracks
- Filter out already-listened tracks
- Rank by weighted popularity
"""

from typing import List, Dict
import numpy as np

def get_recommendations(
    user_id: str,
    user_item_matrix: np.ndarray,
    user_index: Dict[str, int],
    track_index: Dict[int, str],
    k_similar_users: int = 50,
    n_recommendations: int = 30
) -> List[str]:
    """
    Simple collaborative filtering.
    In production, this runs in Spark on billions of rows.
    """
    user_idx = user_index[user_id]
    user_vector = user_item_matrix[user_idx]
    
    # Compute cosine similarity with all users
    similarities = []
    for other_idx in range(len(user_item_matrix)):
        if other_idx == user_idx:
            continue
        other_vector = user_item_matrix[other_idx]
        sim = np.dot(user_vector, other_vector) / (
            np.linalg.norm(user_vector) * np.linalg.norm(other_vector) + 1e-9
        )
        similarities.append((other_idx, sim))
    
    # Get top-K similar users
    top_similar = sorted(similarities, key=lambda x: x[1], reverse=True)[:k_similar_users]
    
    # Aggregate track scores from similar users
    track_scores = {}
    for similar_user_idx, similarity in top_similar:
        for track_idx, play_count in enumerate(user_item_matrix[similar_user_idx]):
            if play_count > 0 and user_vector[track_idx] == 0:  # Not already listened
                if track_idx not in track_scores:
                    track_scores[track_idx] = 0
                track_scores[track_idx] += similarity * play_count
    
    # Sort and return top recommendations
    top_tracks = sorted(track_scores.items(), key=lambda x: x[1], reverse=True)
    return [track_index[idx] for idx, _ in top_tracks[:n_recommendations]]
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Playlist tracks in Cassandra | Position-based ordering verified |
---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Playlists in Cassandra | Partitioned by ID, clustered by position |
| 2 | Listening history bucketed | user_id + month partition |
| 3 | Denormalized track metadata | No joins at read time |
| 4 | Snapshot ID for sync | playlist.snapshot_id updated on change |
| 5 | Audio features indexed | tempo, energy, danceability for ML |
| 6 | TTL on recommendations | discover_weekly: 7 days, daily_mix: 1 day |
| 7 | Collaborative playlists | added_by tracked per track |
| 8 | Artist top tracks per country | Partitioned by (artist_id, country) |

---

# Part 7: DynamoDB Single-Table Design

```
============================================================
SPOTIFY: DynamoDB Single-Table Design
For high-scale collaborative sessions and session state
(Cassandra remains Primary for Playlists/Library at Spotify scale)
============================================================

TABLE: spotify_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (Session/User queries)
- GSI2: GSI2PK / GSI2SK (Social/Group queries)

============================================================
ENTITY PATTERNS
============================================================

GROUP LISTENING SESSION (Jam)
  PK: JAM#{jam_id}
  SK: INFO
  
  Attributes: host_id, current_track_id, playback_state

SESSION PARTICIPANT
  PK: JAM#{jam_id}
  SK: USER#{user_id}
  GSI1PK: USER#{user_id}
  GSI1SK: JAM#{jam_id}
  
  Attributes: joined_at, device_id, is_active

LYRICS SYNCHRONIZATION
  PK: TRACK#{track_id}
  SK: LYRICS#{language}
  
  Attributes: sync_json_blob (time: text), provider

PODCAST PROGRESS
  PK: USER#{user_id}
  SK: POD#{episode_id}
  
  Attributes: position_ms, last_played_at, is_completed

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get Jam session state
   Table: PK=JAM#{jam_id}, SK=INFO

2. List participants in a session
   Table: PK=JAM#{jam_id}, SK begins_with "USER#"

3. Find active session for user
   GSI1: PK=USER#{user_id}, SK begins_with "JAM#"

4. Get synced lyrics for a track
   Table: PK=TRACK#{track_id}, SK=LYRICS#EN
```

---

# Part 8: Query Examples with EXPLAIN

```sql
-- ============================================================
-- SPOTIFY QUERY PATTERNS WITH EXPLAIN (Cassandra/Postgres)
-- ============================================================

-- ===========================================
-- QUERY 1: Get Playlist Tracks (Cassandra)
-- ===========================================

-- "Load my workout playlist"
SELECT track_name, artist_name, album_name, duration_ms
FROM playlist_tracks
WHERE playlist_id = ?
ORDER BY position ASC
LIMIT 100;

-- Analysis: Single partition read. Sequential.
-- Fast even for 10,000 song playlists (paginated).


-- ===========================================
-- QUERY 2: Recent Listening History (Cassandra)
-- ===========================================

-- "What was that song I just heard?"
SELECT track_name, artist_name, played_at
FROM listening_history
WHERE user_id = ?
  AND bucket_month = '2023-11'
ORDER BY played_at DESC
LIMIT 50;

-- Analysis: Hits hot partition (current month). Memory-resident.


-- ===========================================
-- QUERY 3: Search Artists (Elasticsearch)
-- ===========================================

-- "Find Taylor Swift"
GET /artist_index/_search
{
  "query": {
    "multi_match": {
      "query": "Taylor Sw",
      "fields": ["name^3", "alias"],
      "type": "bool_prefix"
    }
  }
}

-- Analysis: Prefix search on inverted index. 
-- Ranked by popularity (boost).


-- ===========================================
-- QUERY 4: Calculate Artist Royalties (PostgreSQL/BigQuery)
-- ===========================================

-- "How many streams for Artist X in US?"
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    COUNT(*) as streams,
    SUM(duration_ms) as total_duration
FROM listening_events_archive
WHERE artist_id = $1
  AND country_code = 'US'
  AND played_at >= '2023-01-01';

-- Analysis: Analytical query. NOT run on OLTP DB.
-- Runs on Data Warehouse (BigQuery) over columnar data.
```

---

# Part 9: Capacity Planning

```
============================================================
SPOTIFY CAPACITY PLANNING
============================================================

ASSUMPTIONS (Global Scale):
- 500M Active Users
- 100M Tracks
- 5B Playlists
- Peak Traffic: 5M plays/sec (Global)

============================================================
STORAGE ESTIMATES
============================================================

PLAYLISTS (Cassandra)
  5B playlists * 20 tracks (avg) = 100B rows.
  Row Size: ~200 bytes (denormalized metadata).
  Total: ~20 TB.
  Replication Factor 3 -> 60 TB.

LISTENING HISTORY (Cassandra)
  500M users * 20 plays/day = 10B writes/day.
  Retention: Forever (History is a feature).
  Data Volume: ~1 PB/year.
  Strategy: Move > 1 year old data to Cold Storage (GCS/S3).

AUDIO FILES (CDN)
  100M tracks * 3 qualities (96, 160, 320 kbps).
  Total: ~5 PB of audio files.
  Cached on user devices (Encrypted Cache) to reduce CDN cost.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

TRACK METADATA (Read Critical):
- 50M reads/sec (Every play fetches metadata).
- Must use Memcached/Redis.
- Postgres cannot handle this load.

PLAYLIST UPDATES (Write Heavy):
- 100K updates/sec (Users adding tracks).
- Cassandra optimized for high write throughput.

SEARCH (Compute Heavy):
- 50K searches/sec.
- Elasticsearch cluster size: ~500 nodes.
- Heavy caching of popular queries ("Drake").

============================================================
SCALING STRATEGY
============================================================

1. USER SHARDING (Pod Architecture)
   - Users are assigned to a "Pod" (Shard).
   - A Pod contains all their Playlists, History, Library.
   - 100K users per Pod.
   - Easy to scale horizontally by adding Pods.

2. ASYNC EVENT DELIVERY
   - "Play" button doesn't write to DB directly.
   - It sends an event to Gateway -> Kafka.
   - Consumers update History, Counts, Charts asynchronously.

3. CLIENT-SIDE CACHING
   - Mobile app caches Track Metadata and Audio.
   - Reduces server load by 80%.
   - Syncs "deltas" for playlists (snapshot_id check).
```

---

# Part 10: Anti-Patterns to Avoid

```
============================================================
SPOTIFY ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Ordered List as Linked List
-----------------------------------------
WRONG:
  Table tracks: id, next_track_id, prev_track_id.
  -- Moving track #50 to #2 requires updating 3 rows.
  -- Hard to query "Get page 5".
  
RIGHT:
  -- Position/Rank Column (INT or FLOAT).
  -- `ORDER BY position`.
  -- Renumbering handling in app logic or sparse ranking.


❌ ANTI-PATTERN 2: Deep Verification on Every Play
-----------------------------------------
WRONG:
  On Play: Check Subscription Valid? Check Rights in Country? Check Device Limit?
  -- Latency spike. Music doesn't start.
  
RIGHT:
  -- Token-based access.
  -- Issue "Playback Token" valid for 1 hour.
  -- Client checks local rights cache.


❌ ANTI-PATTERN 3: Joining 5B Playlists Table
-----------------------------------------
WRONG:
  SELECT * FROM playlists JOIN users ...
  
RIGHT:
  -- Denormalize Owner Name into Playlist table.
  -- Cassandra does not support Joins.


❌ ANTI-PATTERN 4: Counting Followers in Real-Time
-----------------------------------------
WRONG:
  SELECT count(*) FROM followers WHERE playlist_id = X
  -- Taylor Swift has 50M followers. Query times out.
  
RIGHT:
  -- Counter Column in Playlist table.
  -- Increment/Decrement on follow/unfollow events.
  -- Reconcile periodically.


❌ ANTI-PATTERN 5: Storing Audio in Database
-----------------------------------------
WRONG:
  BLOB column for MP3 data.
  
RIGHT:
  -- Hash-based storage in CDN (S3/GCS).
  -- DB stores `file_id` (SHA-1 hash).


❌ ANTI-PATTERN 6: Synchronous Recommendations
-----------------------------------------
WRONG:
  User loads "Discover Weekly" -> Python job runs -> Returns list.
  -- 10-second delay.
  
RIGHT:
  -- Pre-compute nightly (Hadoop/Spark).
  -- Store results in Cassandra/Redis.
  -- API just fetches list.


❌ ANTI-PATTERN 7: Ignoring Global Rights
-----------------------------------------
WRONG:
  Showing "Song X" to user in Germany when rights are "US Only".
  -- Legal disaster.
  
RIGHT:
  -- `available_markets` array on Track/Album.
  -- Filter at Edge/API gateway layer.


❌ ANTI-PATTERN 8: Infinite History Scroll without Partitioning
-----------------------------------------
WRONG:
  SELECT * FROM history WHERE user_id = X ORDER BY date.
  -- Partition size > 2GB (Cassandra limit warning).
  
RIGHT:
  -- Partition by `user_id + month_bucket`.
  -- Query one month at a time.


❌ ANTI-PATTERN 9: Single Master for Catalog
-----------------------------------------
WRONG:
  All writes go to 1 Postgres Master.
  
RIGHT:
  -- Catalog changes (New Releases) are infrequent compared to Reads.
  -- Read Replicas x 50.
  -- Shard by Artist ID if write volume grows.


❌ ANTI-PATTERN 10: XML Metadata
-----------------------------------------
WRONG:
  Storing metadata as XML blobs.
  
RIGHT:
  -- Protobuf / Thrift for internal communication.
  -- JSON for public API.
  -- Relational columns for frequent queries.
```

---

# Part 11: CDC & Event Streaming

```
============================================================
SPOTIFY CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (Catalog)   │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ Search    │    │ Cache     │   │ Rights    │  │ Graph    │
  │ Indexer   │    │ Invalidator│  │ Check     │  │ Service  │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- track.updated           (Update Elasticsearch, Cache)
- playlist.modified       (Notify followers, update version)
- user.listened           (Update "Recently Played", Rank)
- subscription.changed    (Update Offline Access)

============================================================
DISASTER RECOVERY
============================================================

RPO: < 15 mins (Playlists), < 1 min (Billing)
RTO: < 1 hour

STRATEGY:
1. Multi-Region Cassandra
   - Data replicated across 3 regions (US, EU, Asia).
   - "Local Quorum" for fast writes, "EACH_QUORUM" for critical sync.

2. Catalog Snapshots
   - Daily snapshot of PostgreSQL Catalog to GCS.
   - PITR (Point-In-Time Recovery) enabled.

3. Degraded Mode
   - If User DB down -> Allow playing "Downloaded/Cached" content.
   - If Recommendations down -> Show "Top 50 Global".
```

---

# Part 12: Production Completeness DDL

```sql
-- ============================================================
-- SPOTIFY: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / LISTENING LOG (Cassandra)
-- ===========================================

CREATE TABLE listening_history (
    user_id             UUID NOT NULL,
    month_bucket        TEXT NOT NULL,  -- '2024-01'
    played_at           TIMESTAMP NOT NULL,
    track_id            UUID NOT NULL,
    context_type        VARCHAR(20),  -- 'playlist', 'album', 'artist_radio'
    context_id          UUID,
    duration_ms         INT,
    device_type         VARCHAR(50),
    country_code        VARCHAR(2),
    PRIMARY KEY ((user_id, month_bucket), played_at, track_id)
) WITH CLUSTERING ORDER BY (played_at DESC);


-- ===========================================
-- B. AUDIO ASSETS (Pointers Only)
-- ===========================================

CREATE TABLE audio_files (
    track_id            UUID NOT NULL,
    quality_level       VARCHAR(20) NOT NULL,  -- 'ogg_96', 'ogg_160', 'ogg_320', 'flac'
    file_hash           VARCHAR(64) NOT NULL,  -- SHA-256
    storage_key         VARCHAR(500) NOT NULL,
    cdn_url_template    VARCHAR(500),
    file_size_bytes     BIGINT NOT NULL,
    duration_ms         INT NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY ((track_id), quality_level)
);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    channel             VARCHAR(20) NOT NULL,  -- 'push', 'email'
    notification_type   VARCHAR(100) NOT NULL,  -- 'new_release', 'playlist_update'
    title               VARCHAR(100),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS (Developer API)
-- ===========================================

CREATE TABLE developer_apps (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id            UUID NOT NULL,
    name                VARCHAR(100) NOT NULL,
    client_id           VARCHAR(64) NOT NULL UNIQUE,
    client_secret_hash  VARCHAR(64) NOT NULL,
    redirect_uris       TEXT[],
    scopes              TEXT[],
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    app_id              UUID NOT NULL REFERENCES developer_apps(id),
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- E. API KEYS
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    app_id              UUID REFERENCES developer_apps(id),
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 100,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- F. OAUTH
-- ===========================================

CREATE TABLE oauth_tokens (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    app_id              UUID NOT NULL REFERENCES developer_apps(id),
    access_token_hash   VARCHAR(64) NOT NULL,
    refresh_token_hash  VARCHAR(64),
    scopes              TEXT[],
    expires_at          TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at          TIMESTAMP WITH TIME ZONE
);


-- ===========================================
-- G. USER SESSIONS / DEVICES
-- ===========================================

CREATE TABLE user_devices (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    device_id           VARCHAR(100) NOT NULL UNIQUE,
    device_type         VARCHAR(50) NOT NULL,  -- 'mobile', 'desktop', 'smart_speaker'
    device_name         VARCHAR(100),
    is_active           BOOLEAN DEFAULT TRUE,
    last_seen_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    device_id           UUID REFERENCES user_devices(id),
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    ip_address          INET NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    target_countries    TEXT[],
    required_plan       VARCHAR(50),  -- 'free', 'premium', 'family'
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 13: Operational Excellence & Internals

```
============================================================
SPOTIFY: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. CASSANDRA PLAYLIST TUNING
============================================================

THE CHALLENGE:
5B+ playlists, some with 10K+ tracks
Partition Key: playlist_id
Risk: Large playlists cause slow reads/writes

PARTITION SIZING:
┌─────────────────────────────────────────────────────────────┐
│  PLAYLIST SIZE  │ STATUS     │ ACTION                      │
├─────────────────────────────────────────────────────────────┤
│  < 500 tracks   │ Healthy    │ Standard path               │
│  500-5000       │ Warning    │ Paginated reads             │
│  > 5000         │ Large      │ Chunked storage             │
└─────────────────────────────────────────────────────────────┘

CHUNKED PLAYLIST STRATEGY:
For playlists > 5000 tracks:
Partition Key: (playlist_id, chunk_number)
Clustering Key: position

COMPACTION STRATEGY:
```cql
-- Playlist tracks (write-heavy, frequent reordering)
ALTER TABLE playlist_tracks WITH compaction = {
    'class': 'LeveledCompactionStrategy',
    'sstable_size_in_mb': 160
};

-- Listening history (time-series)
ALTER TABLE listening_history WITH compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_size': 7,
    'compaction_window_unit': 'DAYS'
};
```

============================================================
2. AUDIO STREAMING OPTIMIZATION
============================================================

CDN ARCHITECTURE:
┌─────────────────────────────────────────────────────────────┐
│  User Request → Edge POP → Origin Shield → S3 Origin       │
│                    ↓                                        │
│              Cache Hit? → Serve immediately                 │
│              Cache Miss? → Fetch + Cache                    │
└─────────────────────────────────────────────────────────────┘

AUDIO FILE STORAGE:
- Format: Ogg Vorbis (96/160/320 kbps)
- Chunk Size: 2-4 second segments
- Hash-based Naming: SHA-256 of content → deduplication
- Storage: S3 with Intelligent Tiering

CACHE STRATEGY:
- Hot Tracks (Top 1000): Always cached at edge (TTL: 7 days)
- Warm Tracks: Regional cache (TTL: 24 hours)
- Cold Tracks: Origin-only, fetch on demand

============================================================
3. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Audio Start Latency (p99)    │ < 500ms │ > 1s = PAGE     │
│  Search Latency (p99)         │ < 200ms │ > 500ms = WARN  │
│  Playlist Load (p99)          │ < 300ms │ > 500ms = WARN  │
│  CDN Cache Hit Rate           │ > 95%   │ < 90% = PAGE    │
│  Cassandra Read (p99)         │ < 50ms  │ > 100ms = WARN  │
└─────────────────────────────────────────────────────────────┘

CASSANDRA METRICS:
- `read_latency_99` per table
- `pending_compactions` (should be < 5)
- `sstables_per_read` (target < 3)
- `tombstone_scanned` (high = cleanup needed)

ELASTICSEARCH METRICS:
- Query latency by type (track, artist, album)
- Index freshness (lag from catalog update)
- Cluster health (red/yellow alerts)

ALERTING RULES:
```yaml
- alert: AudioStartSlow
  expr: histogram_quantile(0.99, audio_start_latency) > 1
  for: 3m
  labels:
    severity: page

- alert: CassandraCompactionHigh
  expr: cassandra_pending_compactions > 10
  for: 10m
  labels:
    severity: warning
```

============================================================
4. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: CDN ORIGIN FAILURE
Impact: New audio fetches fail.
Mitigation:
1. Multi-origin setup (S3 + GCS backup)
2. Edge serves stale if origin down (stale-if-error)
3. Fallback to lower quality audio

SCENARIO 2: SEARCH CLUSTER DEGRADED
Impact: Search returns partial results.
Mitigation:
1. Circuit breaker → return "Popular" results
2. Query timeout: 2s max
3. Elasticsearch rolling restart SOP

SCENARIO 3: PLAYLIST SERVICE OVERLOAD (Viral Playlist)
Impact: Single playlist gets 1M concurrent readers.
Mitigation:
1. Edge cache playlist metadata (30s TTL)
2. Rate limit per playlist_id (10K req/sec)
3. Read-through cache with single-flight

SCENARIO 4: RIGHTS DATABASE UNAVAILABLE
Impact: Cannot validate playback rights.
Mitigation:
1. Cache rights per user session (1 hour)
2. Fail-open for cached users
3. Block new playback, allow current streams

============================================================
5. FINOPS & COST OPTIMIZATION
============================================================

TIERING STRATEGY:
┌─────────────────────────────────────────────────────────────┐
│  DATA              │ AGE       │ STORAGE      │ ACCESS     │
├─────────────────────────────────────────────────────────────┤
│  Audio Files       │ All       │ S3 Glacier   │ CDN cached │
│  Listening History │ < 30 days │ Cassandra    │ Real-time  │
│  Listening History │ > 30 days │ Parquet/S3   │ Batch ML   │
│  Catalog           │ Active    │ PostgreSQL   │ Cached     │
│  Search Index      │ Active    │ Elasticsearch│ Real-time  │
└─────────────────────────────────────────────────────────────┘

COST BREAKDOWN (Estimated Monthly):
- CDN (Cloudflare/Fastly): $800K
- S3 Storage: $150K
- Cassandra: $200K
- Elasticsearch: $100K
- PostgreSQL: $50K
- Total Data Layer: ~$1.3M/month
```

---

## 🔗 Related Documents

- [Netflix Schema](./netflix-schema-design-guide.md) — Similar streaming pattern
- [NoSQL Architecture](./nosql-architecture-guide.md) — Cassandra design
- [JIRA Schema](./jira-schema-design-guide.md) — Complex relationship modeling
