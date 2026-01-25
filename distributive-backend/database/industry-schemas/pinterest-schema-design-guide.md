# Pinterest Image Sharing: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Pins, Boards, User Following, Feed Generation, Recommendations — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Querying the database for feed generation at read time. Pinterest pre-computes feeds and uses **fanout-on-write** for active users.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Scaling Pinterest](https://highscalability.com/pinterest-architecture-update-18-million-visitors/) | Original architecture |
| [Pinterest ML for Recommendations](https://medium.com/pinterest-engineering) | PinSage, homefeed |
| [Sharding at Pinterest](https://medium.com/pinterest-engineering/sharding-pinterest-how-we-scaled-our-mysql-fleet-3f341e96ca6f) | MySQL sharding |

---

## 🎯 The Principal Laws of Image Sharing Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Shard by User** | All user data on same shard | user_id in every key |
| **Law 2: Fanout on Write** | Write to follower feeds | Pre-compute home feeds |
| **Law 3: Images in CDN** | DB stores URLs, not bytes | S3/CDN for images |
| **Law 4: Visual Search** | Embeddings for similarity | Vector DB for recommendations |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get home feed | 10M/s | < 50ms | Redis + Cassandra |
| 2 | Get pin details | 50M/s | < 20ms | Cache + MySQL |
| 3 | Get board with pins | 5M/s | < 50ms | MySQL (sharded) |
| 4 | Save pin to board | 1M/s | < 200ms | MySQL + fanout |
| 5 | Create new pin | 100K/s | < 500ms | MySQL + async processing |
| 6 | Get user profile | 2M/s | < 30ms | Cache + MySQL |
| 7 | Follow user/board | 500K/s | < 200ms | MySQL + fanout |
| 8 | Search pins | 1M/s | < 200ms | Elasticsearch |
| 9 | Get similar pins | 5M/s | < 100ms | Vector DB (Milvus) |
| 10 | Get trending pins | 1M/s | < 50ms | Pre-computed cache |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    PINTEREST DATA ARCHITECTURE                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         MySQL (Sharded by user_id)               │
│  ✓ Transactional    ✓ Strong consistency   ✓ Complex joins      │
│                                                                  │
│  • users (profile, settings)                                     │
│  • pins (metadata, not images)                                   │
│  • boards (collections)                                          │
│  • board_pins (many-to-many)                                     │
│  • follows (user→user, user→board)                               │
│  • saves (pin saves by user)                                     │
└─────────────────────────────────────────────────────────────────┘
                              │ CDC + Fanout
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Redis / Cassandra                        │
│  ✓ Pre-computed feeds    ✓ Fast reads   ✓ Horizontal scale      │
│                                                                  │
│  • home_feed:{user_id}                                           │
│  • following_feed:{user_id}                                      │
│  • trending:{country}                                            │
│  • user_stats:{user_id}                                          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         S3 + CDN (CloudFront)                    │
│  ✓ Image storage    ✓ Multiple sizes   ✓ Edge caching           │
│                                                                  │
│  • Original images                                               │
│  • Thumbnails (150x150, 236x, 564x, 736x)                        │
│  • WebP/AVIF variants                                            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Vector DB (Milvus/Pinecone)              │
│  ✓ Image embeddings    ✓ Similarity search   ✓ Recommendations  │
│                                                                  │
│  • pin_embeddings (visual similarity)                            │
│  • user_taste_vectors                                            │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: MySQL DDL (Sharded)

```sql
-- ============================================================
-- PINTEREST SCHEMA: MySQL Production DDL
-- Version: Sharded by user_id
-- Shard Key: user_id % 4096 (Pinterest uses 4096 shards)
-- ============================================================


-- ===========================================
-- SECTION 1: SHARD LOCATOR
-- ===========================================

-- Central lookup table (not sharded)
CREATE TABLE shard_mapping (
    user_id             BIGINT PRIMARY KEY,
    shard_id            INT NOT NULL,  -- 0-4095
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_shard (shard_id)
);


-- ===========================================
-- SECTION 2: USERS (On User's Shard)
-- ===========================================

CREATE TABLE users (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    
    username            VARCHAR(30) NOT NULL UNIQUE,
    email               VARCHAR(255) NOT NULL UNIQUE,
    password_hash       VARCHAR(255) NOT NULL,
    
    -- Profile
    full_name           VARCHAR(100),
    bio                 TEXT,
    website_url         VARCHAR(500),
    location            VARCHAR(100),
    
    -- Profile image
    avatar_url          VARCHAR(500),
    
    -- Stats (denormalized)
    follower_count      INT UNSIGNED DEFAULT 0,
    following_count     INT UNSIGNED DEFAULT 0,
    board_count         INT UNSIGNED DEFAULT 0,
    pin_count           INT UNSIGNED DEFAULT 0,
    
    -- Settings
    is_private          BOOLEAN DEFAULT FALSE,
    email_verified      BOOLEAN DEFAULT FALSE,
    
    -- Account status
    is_active           BOOLEAN DEFAULT TRUE,
    is_verified         BOOLEAN DEFAULT FALSE,  -- Blue check
    
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_username (username),
    INDEX idx_email (email)
);


-- ===========================================
-- SECTION 3: BOARDS (On Creator's Shard)
-- ===========================================

CREATE TABLE boards (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id             BIGINT NOT NULL,  -- Creator, used for sharding
    
    name                VARCHAR(180) NOT NULL,
    description         TEXT,
    
    -- Cover image (auto-selected or manual)
    cover_pin_id        BIGINT,
    
    -- Privacy
    is_secret           BOOLEAN DEFAULT FALSE,
    
    -- Stats (denormalized)
    pin_count           INT UNSIGNED DEFAULT 0,
    follower_count      INT UNSIGNED DEFAULT 0,
    
    -- Collaborators allowed?
    is_collaborative    BOOLEAN DEFAULT FALSE,
    
    -- Category
    category_id         INT,
    
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_user (user_id),
    INDEX idx_user_name (user_id, name)
);


-- ===========================================
-- SECTION 4: PINS (On Creator's Shard)
-- ===========================================

CREATE TABLE pins (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id             BIGINT NOT NULL,  -- Original pinner, used for sharding
    
    -- Image (stored in S3, multiple sizes)
    image_url           VARCHAR(500) NOT NULL,  -- Original
    image_url_236       VARCHAR(500),           -- 236px wide
    image_url_564       VARCHAR(500),           -- 564px wide
    image_url_736       VARCHAR(500),           -- 736px wide
    
    -- Image metadata
    image_width         INT,
    image_height        INT,
    dominant_color      VARCHAR(7),  -- Hex color
    
    -- Content
    title               VARCHAR(100),
    description         TEXT,
    alt_text            VARCHAR(500),  -- Accessibility
    link_url            VARCHAR(2000),  -- Original source
    
    -- Stats (denormalized)
    save_count          INT UNSIGNED DEFAULT 0,
    comment_count       INT UNSIGNED DEFAULT 0,
    reaction_count      INT UNSIGNED DEFAULT 0,
    
    -- Source attribution
    source_pin_id       BIGINT,  -- If re-pinned from another pin
    
    -- ML features (for recommendations)
    embedding_id        VARCHAR(50),  -- Reference to vector DB
    
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_user (user_id),
    INDEX idx_created (created_at DESC),
    INDEX idx_source (source_pin_id)
);


-- ===========================================
-- SECTION 5: BOARD-PIN RELATIONSHIP
-- ===========================================

-- Pins can be saved to multiple boards
-- Stored on BOARD's shard (for efficient board queries)
CREATE TABLE board_pins (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    board_id            BIGINT NOT NULL,
    pin_id              BIGINT NOT NULL,
    
    -- Who saved it to this board
    saved_by_user_id    BIGINT NOT NULL,
    
    -- Position in board (for custom ordering)
    position            INT UNSIGNED,
    
    -- Section within board (optional)
    section_id          BIGINT,
    
    saved_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_board_pin (board_id, pin_id),
    INDEX idx_pin (pin_id),
    INDEX idx_saved_by (saved_by_user_id)
);


-- ===========================================
-- SECTION 6: FOLLOWING
-- ===========================================

-- User follows (stored on FOLLOWER's shard for "who I follow" queries)
CREATE TABLE user_follows (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    follower_id         BIGINT NOT NULL,  -- Shard key
    following_id        BIGINT NOT NULL,
    
    followed_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_follow (follower_id, following_id),
    INDEX idx_following (following_id)
);

-- Board follows (stored on FOLLOWER's shard)
CREATE TABLE board_follows (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    follower_id         BIGINT NOT NULL,  -- Shard key
    board_id            BIGINT NOT NULL,
    board_owner_id      BIGINT NOT NULL,  -- For cross-shard lookup
    
    followed_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_follow (follower_id, board_id),
    INDEX idx_board (board_id)
);


-- ===========================================
-- SECTION 7: USER SAVES (For "Saved" Tab)
-- ===========================================

-- All pins a user has saved (on USER's shard)
CREATE TABLE user_saves (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id             BIGINT NOT NULL,  -- Shard key
    pin_id              BIGINT NOT NULL,
    board_id            BIGINT NOT NULL,
    
    saved_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_save (user_id, pin_id, board_id),
    INDEX idx_user_time (user_id, saved_at DESC)
);


-- ===========================================
-- SECTION 8: COMMENTS AND REACTIONS
-- ===========================================

CREATE TABLE comments (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    pin_id              BIGINT NOT NULL,
    user_id             BIGINT NOT NULL,
    
    comment_text        TEXT NOT NULL,
    
    -- For replies
    parent_id           BIGINT,
    
    -- Reactions on comment
    like_count          INT UNSIGNED DEFAULT 0,
    
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_pin (pin_id),
    INDEX idx_user (user_id),
    INDEX idx_parent (parent_id)
);

CREATE TABLE pin_reactions (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    pin_id              BIGINT NOT NULL,
    user_id             BIGINT NOT NULL,
    
    reaction_type       ENUM('love', 'haha', 'wow', 'good_idea', 'thanks') NOT NULL,
    
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_reaction (pin_id, user_id),
    INDEX idx_user (user_id)
);


-- ===========================================
-- SECTION 9: CATEGORIES AND INTERESTS
-- ===========================================

CREATE TABLE categories (
    id                  INT PRIMARY KEY AUTO_INCREMENT,
    name                VARCHAR(100) NOT NULL UNIQUE,
    slug                VARCHAR(100) NOT NULL UNIQUE,
    parent_id           INT,
    image_url           VARCHAR(500)
);

INSERT INTO categories (id, name, slug) VALUES
    (1, 'Home Decor', 'home-decor'),
    (2, 'Fashion', 'fashion'),
    (3, 'Food & Drink', 'food-drink'),
    (4, 'Art', 'art'),
    (5, 'DIY & Crafts', 'diy-crafts'),
    (6, 'Travel', 'travel'),
    (7, 'Photography', 'photography'),
    (8, 'Weddings', 'weddings'),
    (9, 'Fitness', 'fitness'),
    (10, 'Technology', 'technology');

-- User interests (on USER's shard)
CREATE TABLE user_interests (
    user_id             BIGINT NOT NULL,
    category_id         INT NOT NULL,
    score               DECIMAL(5,4) DEFAULT 0.5,  -- 0-1 interest level
    
    PRIMARY KEY (user_id, category_id)
);
```

---

# Part 4: Feed Generation (Redis/Cassandra)

```python
# ============================================================
# PINTEREST FEED ARCHITECTURE
# ============================================================

"""
Pinterest uses a hybrid approach:
1. Fanout-on-write for users with < 10K followers
2. Fanout-on-read for celebrities (millions of followers)

Feed is stored in Redis (hot) and Cassandra (cold).
"""

# Redis key structure
FEED_KEYS = {
    # Home feed (pins from followed users/boards)
    "home_feed:{user_id}": "ZSET",  # score = timestamp, value = pin_id
    
    # Following feed (chronological)
    "following_feed:{user_id}": "ZSET",
    
    # User's created pins
    "user_pins:{user_id}": "ZSET",
    
    # Board's pins
    "board_pins:{board_id}": "ZSET",
    
    # Trending by country
    "trending:{country_code}": "ZSET",  # score = trending score
    
    # Similar pins cache
    "similar:{pin_id}": "LIST",
}


# Cassandra for persistent feed storage

"""
CREATE KEYSPACE pinterest_feeds
WITH REPLICATION = {'class': 'NetworkTopologyStrategy', 'us-east-1': 3};

USE pinterest_feeds;

-- Home feed by user (most recent first)
CREATE TABLE home_feed_by_user (
    user_id         BIGINT,
    feed_bucket     TEXT,           -- '2024-01' monthly bucket
    created_at      TIMESTAMP,
    pin_id          BIGINT,
    
    -- Denormalized for fast render
    pinner_id       BIGINT,
    pinner_name     TEXT,
    image_url       TEXT,
    title           TEXT,
    
    -- Why in feed
    reason          TEXT,           -- 'following', 'recommended', 'trending'
    
    PRIMARY KEY ((user_id, feed_bucket), created_at, pin_id)
) WITH CLUSTERING ORDER BY (created_at DESC);

-- User's followers (for fanout)
CREATE TABLE followers_by_user (
    user_id         BIGINT,
    follower_id     BIGINT,
    followed_at     TIMESTAMP,
    
    PRIMARY KEY ((user_id), follower_id)
);
"""
```

---

# Part 5: Fanout-on-Write Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    PIN CREATION FANOUT                           │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  User creates    │
│  new Pin         │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌──────────────────┐
│  Write Pin to    │────►│  MySQL (sharded) │
│  database        │     │  pins table      │
└────────┬─────────┘     └──────────────────┘
         │
         │ Async (Kafka)
         ▼
┌──────────────────┐
│  Fanout Worker   │
│                  │
│  1. Get followers│
│  2. Check count  │
└────────┬─────────┘
         │
┌────────┴────────────────┐
│                         │
▼ Followers < 10K         ▼ Followers >= 10K
┌──────────────────┐      ┌──────────────────┐
│  Fanout on Write │      │  Fanout on Read  │
│                  │      │                  │
│  Write pin_id to │      │  Mark user as    │
│  each follower's │      │  "celebrity"     │
│  home_feed in    │      │                  │
│  Redis           │      │  When follower   │
│                  │      │  loads feed:     │
│  O(followers)    │      │  - Merge celeb   │
│  writes          │      │    pins at read  │
└──────────────────┘      └──────────────────┘
```

---

# Part 6: Visual Similarity Search

```python
# ============================================================
# PINTEREST VISUAL SEARCH
# ============================================================

"""
Pinterest uses PinSage (Graph Neural Network) for pin embeddings.
Similar pins are found via ANN (Approximate Nearest Neighbors).
"""

from typing import List
import numpy as np

class VisualSimilarity:
    """
    Stores pin embeddings in a vector database (Milvus/Pinecone).
    """
    
    def __init__(self, vector_db_client):
        self.client = vector_db_client
        self.collection = "pin_embeddings"
        self.dimension = 256  # Embedding dimension
    
    def index_pin(self, pin_id: int, image_url: str):
        """
        Process image through CNN and store embedding.
        Called when pin is created.
        """
        # 1. Download image
        # 2. Run through ResNet/EfficientNet
        # 3. Extract embedding from penultimate layer
        embedding = self._extract_embedding(image_url)
        
        # 4. Store in vector DB
        self.client.insert(
            collection=self.collection,
            vectors=[{
                "id": pin_id,
                "embedding": embedding,
            }]
        )
    
    def find_similar(self, pin_id: int, limit: int = 20) -> List[int]:
        """
        Find visually similar pins using ANN search.
        """
        # Get embedding for source pin
        result = self.client.get(self.collection, pin_id)
        if not result:
            return []
        
        embedding = result["embedding"]
        
        # ANN search
        similar = self.client.search(
            collection=self.collection,
            vector=embedding,
            limit=limit + 1,  # Exclude self
            metric="cosine"
        )
        
        return [r["id"] for r in similar if r["id"] != pin_id]
    
    def _extract_embedding(self, image_url: str) -> np.ndarray:
        """
        Extract visual embedding from image.
        In production, this runs on GPU workers.
        """
        # Pseudo-code
        # image = download(image_url)
        # preprocessed = resize_and_normalize(image)
        # embedding = model.encode(preprocessed)
        # return embedding
        pass
```

---

# Part 7: Sharding Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    PINTEREST SHARDING                            │
└─────────────────────────────────────────────────────────────────┘

Pinterest shards by user_id:
  shard_id = murmur3_hash(user_id) % 4096

All data for a user lives on one shard:
  - Profile
  - Boards (created by user)
  - Pins (created by user)
  - Follows (who user follows)
  - Saves (what user saved)

This enables:
  - Single-shard reads for "my stuff"
  - Consistent transactions per user
  - Horizontal scaling

Trade-offs:
  - Cross-shard queries for global feeds
  - Hot shards for celebrities (mitigated by caching)


Shard lookup:
┌──────────────────┐     ┌──────────────────┐
│  API Request     │────►│  Shard Locator   │
│  user_id: 12345  │     │  (Central MySQL) │
└──────────────────┘     └────────┬─────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │  Shard 2847      │
                         │  (MySQL Instance)│
                         │                  │
                         │  users, pins,    │
                         │  boards, follows │
                         └──────────────────┘
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Shard by user_id | All user data collocated |
| 2 | Fanout on write for < 10K | Async worker handles fanout |
| 3 | Fanout on read for celebrities | Merge at read time |
| 4 | Images in CDN, not DB | Only URLs stored |
| 5 | Visual embeddings indexed | Vector DB for similarity |
| 6 | Denormalized stats | follower_count, pin_count, etc. |
| 7 | Feed in Redis/Cassandra | Pre-computed, not JOIN at read |
| 8 | Cross-shard handled | Async fanout for follows |

---

# Part 8: DynamoDB Single-Table Design

```
============================================================
PINTEREST: DynamoDB Single-Table Design
For high-scale interaction events and user feeds
(MySQL remains primary for core Entities/Sharding)
============================================================

TABLE: pinterest_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (Engagement/Feed queries)
- GSI2: GSI2PK / GSI2SK (Interest/Category queries)

============================================================
ENTITY PATTERNS
============================================================

USER IMPRESSION LOG (For Ads/Recommendations)
  PK: USER#{user_id}
  SK: VIEW#{timestamp}#{pin_id}
  
  Attributes: dwell_time_ms, device_type, experiment_group

HOME FEED (Pre-computed)
  PK: FEED#{user_id}
  SK: SCORE#{ranking_score}#{pin_id}
  
  Attributes: pin_json_blob, source_type (follow, ml)

TRENDING TOPIC
  PK: TREND#{country}#{date}
  SK: TOPIC#{topic_id}
  GSI1PK: TOPIC#{topic_id}
  GSI1SK: TREND#{country}#{date}
  
  Attributes: pin_count, growth_rate

BOARD ACTIVITY LOG (Collaboration)
  PK: BOARD#{board_id}
  SK: EVENT#{timestamp}
  
  Attributes: actor_id, action (add_pin, remove_pin)

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get user's home feed (Top 50)
   Table: PK=FEED#{user_id}, SK > SCORE#0 (Reverse sorted)

2. Get user's recent view history
   Table: PK=USER#{user_id}, SK begins_with "VIEW#"

3. Get trending topics in US
   Table: PK=TREND#US#2023-10-27, SK begins_with "TOPIC#"

4. Get activity stream for group board
   Table: PK=BOARD#{board_id}, SK begins_with "EVENT#"
```

---

# Part 9: Query Examples with EXPLAIN

```sql
-- ============================================================
-- PINTEREST QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Get Board Pins (Sharded MySQL)
-- ===========================================

-- 90% of traffic is "Get Board". Optimized for shard locality.
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    bp.pin_id, p.image_url, p.title, p.image_height
FROM board_pins bp
JOIN pins p ON p.id = bp.pin_id
WHERE bp.board_id = $1
ORDER BY bp.position ASC
LIMIT 50;

-- Expected: Index scan on uk_board_pin (covering), then lookups on `pins` table.
-- NOTE: In production, `pins` table is often on the SAME SHARD (User Shard) 
-- if 99% of pins on a board are created by the user. 
-- For "Saved Pins" (re-pins), cross-shard Multi-Get is needed if not denormalized.


-- ===========================================
-- QUERY 2: User Search (Prefix)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT username, full_name, avatar_url, follower_count
FROM users
WHERE username LIKE 'art%' 
  AND is_active = TRUE
ORDER BY follower_count DESC
LIMIT 10;

-- Expected: Range scan on idx_username.


-- ===========================================
-- QUERY 3: Find Duplicate Pins (For Image Dedup)
-- ===========================================

-- Uses an image hash (e.g., p-hash) stored on pin
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, created_at 
FROM pins
WHERE image_hash = $1
ORDER BY created_at ASC;

-- Expected: Index scan on idx_image_hash.


-- ===========================================
-- QUERY 4: Feed Construction (Fanout Pull - The "Slow" Path)
-- ===========================================

-- Only run for fallback if Redis cache is empty
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    p.id, p.title, p.image_url
FROM user_follows uf
JOIN pins p ON p.user_id = uf.following_id
WHERE uf.follower_id = $1
  AND p.created_at > NOW() - INTERVAL '7 days'
ORDER BY p.created_at DESC
LIMIT 100;

-- Expected: Very Expensive! Scatters to all shards of users I follow.
-- Avoid this in production. Use Pre-computed Feed (Law #2).
```

---

# Part 10: Capacity Planning

```
============================================================
PINTEREST CAPACITY PLANNING
============================================================

ASSUMPTIONS (Huge Scale):
- 400M Monthly Active Users
- 200 Billion Pins (Total)
- 4 Billion Boards
- Read Heavy: 1M QPS (images/feeds)
- Write Heavy: 50K QPS (saves/pins)

============================================================
STORAGE ESTIMATES
============================================================

PINS METADATA (MySQL)
  Rows: 200 Billion
  Row Size: ~500 bytes
  Total: ~100 TB (Sharded logic essential).
  Shards: 4096 shards / 1 TB per shard (approx 25 GB actual data per shard fits in RAM).

IMAGES (S3)
  200B images * 500KB (avg) = 100 PB!
  Cold storage tiering (Glacier) for pins not viewed in >1 year.

FEED (Redis)
  400M users * 50 items * 8 bytes (ID) = 160 GB RAM.
  Manageable cluster.

VECTOR INDEX
  200B vectors * 256 dim * 4 bytes = ~200 TB index.
  Approximation (HNSW) used, shards distributed on specialized Vector service.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

HOME FEED:
- 10M feed refreshes/min.
- Cache Hit Ratio > 99% required.
- Fallback: only show "popular" or "random" if cache misses/fails.

PIN SAVES (The "Action"):
- 50K saves/sec.
- Async write to MySQL (buffer via Kafka).
- Updating "save_count" is a massive hotspot.
- Solution: Buffered counters (Redis -> flush to DB every 10s).

============================================================
SCALING STRATEGY
============================================================

1. SHARDING (Manually Managed)
   - Pinterest manages its own shard map ("Shard 123 is on Host A").
   - Operations: Virtual IP swap for failover.
   - Resharding: Moving data is hard. Pre-allocation (4096 shards) prevents this.

2. DECIDEDLY EVENTUAL CONSISTENCY
   - "Save Count" might be off by 5 minutes.
   - Feed might lag by 1 minute.
   - Acceptable for Discovery user case (not Banking!).

3. IMAGE OPTIMIZATION
   - Converting to WebP saved 30% bandwidth (Petabytes/year).
   - Dynamic resizing at Edge.
```

---

# Part 11: Anti-Patterns to Avoid

```
============================================================
PINTEREST ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: JOINing Follows to Pins at Read Time
-----------------------------------------
WRONG:
  SELECT * FROM follows JOIN pins ...
  -- "Scatter-Gather" query to 1000 shards. Latency = slowest shard.
  
RIGHT:
  -- Fanout-on-Write.
  -- Valid Feed is just a list of IDs in Redis. O(1) fetch.


❌ ANTI-PATTERN 2: Storing Binary Images in MySQL
-----------------------------------------
WRONG:
  BLOB column for image data.
  -- Database cache meant for rows, not 5MB JPEGs.
  
RIGHT:
  -- S3 + CDN. Store URL only.


❌ ANTI-PATTERN 3: Sharding by Pin ID
-----------------------------------------
WRONG:
  Shard Key = pin_id.
  -- User profile page needs to query all shards to find "My Pins".
  
RIGHT:
  -- Shard by User ID.
  -- "My Pins" query hits 1 single shard.


❌ ANTI-PATTERN 4: Hot Shard on "Popular" Board
-----------------------------------------
WRONG:
  Celeb user has 10M followers. Everyone writes to their shard?
  -- Or everyone reads from their shard for feed?
  
RIGHT:
  -- Read Splitting (Fanout-on-read for celebs).
  -- Replicas for high-traffic user shards.


❌ ANTI-PATTERN 5: Sync Image Analysis
-----------------------------------------
WRONG:
  User Upload -> Python CV Analysis -> Save to DB -> Respond 200 OK.
  -- 5 second timeout.
  
RIGHT:
  -- User Upload -> S3 -> SQS -> Worker (Analysis) -> DB Update.
  -- UI shows "Processing..." state.


❌ ANTI-PATTERN 6: Infinite Scroll Limitless Offset
-----------------------------------------
WRONG:
  LIMIT 50 OFFSET 1000000
  -- Scanning 1M rows on next page load.
  
RIGHT:
  -- Cursor-based Pagination.
  -- WHERE id < last_seen_id ORDER BY id DESC LIMIT 50.


❌ ANTI-PATTERN 7: Relying on Likes for Recommendation
-----------------------------------------
WRONG:
  Only using explicit signals (Likes/Saves).
  -- Data is sparse.
  
RIGHT:
  -- Implicit signals (Dwell time, zoom, click-through).
  -- "Visual Similarity" (User looked at a Cat, show more Cats).


❌ ANTI-PATTERN 8: Hard Deleting Pins
-----------------------------------------
WRONG:
  DELETE FROM pins ...
  -- "Broken images" in millions of feeds.
  
RIGHT:
  -- Soft Delete.
  -- Hide from search/feed, but keep URL valid for short term.


❌ ANTI-PATTERN 9: Global Secondary Indexes in Sharded DB
-----------------------------------------
WRONG:
  Trying to maintain a global "Email -> UserID" index across shards.
  
RIGHT:
  -- Use a dedicated "Mapping Table" or Service for mappings.
  -- `email_lookup` table (email_hash -> user_id, shard_id).


❌ ANTI-PATTERN 10: Mixing Online/Offline ML
-----------------------------------------
WRONG:
  Running PyTorch inference inside the API request loop.
  
RIGHT:
  -- Pre-compute embeddings and recommendations offline (Hadoop/Spark).
  -- Load into Key-Value store (Redis/RocksDB) for API serving.
```

---

# Part 12: CDC & Event Streaming

```
============================================================
PINTEREST CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ MySQL       │────►│  Maxwell    │────►│  Kafka          │
│ (Shards)    │     │ (Binlog)    │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ PinSage   │    │ Text Inde │   │ Trust &   │  │ Ads      │
  │ (Graph ML)│    │ (Elastic) │   │ Safety    │  │ Platform │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- pin.created             (Trigger ML, Safety Scan)
- pin.saved               (Update counts, Recs)
- user.followed           (Fanout trigger)
- image.uploaded          (Thumbnail generation)

============================================================
DISASTER RECOVERY
============================================================

RPO: < 1 hour (Images), < 1 min (Metadata)
RTO: < 4 hours

STRATEGY:
1. S3 Replication
   - Cross-Region Replication (CRR) for images.
   - Images are the primary asset.

2. MySQL Slaves
   - Every Master has a hot standby.
   - Automated promotion (Orchestrator).

3. "Static Mode"
   - If Feed Generation fails -> Show "Editors Picks" (static JSON).
   - If Search fails -> Show "Popular Categories".
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- PINTEREST: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / MODERATION LOG
-- ===========================================

CREATE TABLE moderation_log (
    id                  BIGSERIAL PRIMARY KEY,
    actor_id            UUID NOT NULL,
    action_type         VARCHAR(50) NOT NULL,  -- 'remove_pin', 'suspend_user', 'block_domain'
    target_type         VARCHAR(50) NOT NULL,
    target_id           UUID NOT NULL,
    reason              TEXT,
    old_state           JSONB,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- B. PIN MEDIA
-- ===========================================

CREATE TABLE pin_images (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pin_id              UUID NOT NULL REFERENCES pins(id),
    image_type          VARCHAR(20) NOT NULL,  -- 'original', 'thumbnail', 'preview'
    width               INT NOT NULL,
    height              INT NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    cdn_url             VARCHAR(500),
    dominant_color      VARCHAR(7),  -- Hex color for placeholder
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_pin_img ON pin_images(pin_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    channel             VARCHAR(20) NOT NULL,  -- 'push', 'email'
    notification_type   VARCHAR(100) NOT NULL,  -- 'new_follower', 'pin_saved'
    title               VARCHAR(100),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS / DEVELOPER API
-- ===========================================

CREATE TABLE developer_apps (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id            UUID NOT NULL,
    name                VARCHAR(100) NOT NULL,
    client_id           VARCHAR(64) NOT NULL UNIQUE,
    client_secret_hash  VARCHAR(64) NOT NULL,
    redirect_uris       TEXT[],
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
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- G. USER SESSIONS
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_type         VARCHAR(50),
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
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
PINTEREST: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. GRAPH STORE INTERNALS (ZEN / TAO)
============================================================

THE CHALLENGE:
The social graph (follows, boards, pins) is queried 10M times/sec.
RDBMS joins are too slow. KV stores lack structure.

SOLUTION: "ZEN" (Graph Service on HBase/MySQL)
- Nodes: Users, Boards, Pins.
- Edges: Follows, Saves, Likes.
- Data Model: `(id_a, edge_type, id_b, timestamp)`.

CACHING STRATEGY (Look-Aside):
1. Check Memcached for `edge_list:{id_a}:{type}`.
2. Miss? Query MySQL Shard.
3. Write-Through? No. Delete cache on write (Invalidation).

DB SHARDING:
- Shard Key: `id_a` (The subject).
- Logic: All edges originating from User A live on the same shard.
- Scale: 8192 virtual shards mapped to N physical DBs.

============================================================
2. SMART FEED FANOUT (HYBRID)
============================================================

THE ALGORITHM:
1. **Candidate Generation**:
   - Get pins from followed users (Fanout-on-write used here).
   - Get pins from "Interests" (Graph traversal).
   - Get "Related Pins" (Visual Embedding similarity).
   
2. **Scoring/Ranking (ML)**:
   - LightGBM model scores thousands of candidates.
   - Features: User history, Pin freshness, CTR.

3. **Blending**:
   - Mix organic, ads, and recommended content.

PERFORMANCE OPTIMIZATION:
- "Piny" (Signal Collection): Async aggregation of counters (re-pins, clicks) for ML features.
- Pre-computation: "Homefeed Cache" stores the top 200 IDs for a user to serve < 200ms.

============================================================
3. IMAGE SERVING (THE "VISUAL" PART)
============================================================

THUMBNAIL GENERATION:
- Derived Images: Original -> 236px width (feed), 600px (detail), 60x60 (avatar).
- Storage: S3 key = `sha256(image_content)`.
- CDN Strategy: 99% cache hit ratio needed. "Long Tail" images fetched from origin.

VISUAL SEARCH (embedding storage):
- Use `faiss` (Facebook AI Similarity Search) or `pgvector`.
- Store 256-float vector per Image.
- Approximate Nearest Neighbor (ANN) search for "More like this".

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Homefeed Latency (p99)       │ < 800ms │ > 1.5s = PAGE   │
│  Pin Creation Success         │ > 99.9% │ < 99.5% = PAGE  │
│  Image Load Latency (CDN)     │ < 100ms │ > 200ms = WARN  │
│  Graph Query Latency (p99)    │ < 5ms   │ > 20ms = PAGE   │
└─────────────────────────────────────────────────────────────┘

INFRASTRUCTURE METRICS:
- `cache_hit_ratio`: Vital for Zen graph service. Even 1% drop = DB fire.
- `hbase_region_server_load`: For analytics/counting layers.
- `kafka_consumer_lag`: For async feed updates.

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: REDIS CACHE FAILURE (30% NODES DOWN)
Symptom: Graph DB load spikes 100x.
Mitigation:
- "Stale-While-Revalidate": Serve slightly old feed data.
- "Shed Load": Drop non-critical features (e.g., "active now" indicators).
- "Query Leasing": Allow only 1 thread to enable DB for a missing key (thundering herd).

SCENARIO 2: "JUSTIN BIEBER" PINNING
Symptom: Celebrity pins an image. 100M notifications.
Mitigation:
- Silent Fanout: Don't push notifications for massive accounts immediately.
- Batching: update fanout queues in chunks.
- Rate Limit: Cap notifications per received user per hour.

SCENARIO 3: IMAGE PROCESSING BACKLOG
Symptom: User uploads Pin, image stays grey.
Mitigation:
- Priority Queue: Real-time uploads > Batch ingestions.
- On-the-fly Resizing: If thumb missing, Edge Lambda generates it (slower but works).

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

STORAGE TIERING:
- "Warm" Pins (viewed < 30 days): S3 Standard.
- "Cold" Pins (> 1 year, low access): S3 Glacier Instant Retrieval.

COMPRESSION:
- WebP / AVIF: Switching from JPEG saves 30% bandwidth ($$$ CDN bill).
- Vector Quantization: Compress ML embeddings to reduce RAM usage.

SPOT INSTANCES:
- Feed Ranking (ML): Stateless, tolerant to interruption. Run 100% on Spot.
- Image Processing Workers: Run 100% on Spot.
```

---

## 🔗 Related Documents

- [Database Scaling](./database-scaling-guide.md) — Sharding patterns
- [Consistent Hashing](../system-design-notes/consistent-hashing-guide.md) — Shard distribution
- [Netflix Schema](./netflix-schema-design-guide.md) — Similar personalization pattern

