# Twitter/X Social Networking: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Tweets, Social Graph, Timelines, Notifications, Trending — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Computing home timeline at read time. Twitter uses **fanout-on-write** for normal users and **fanout-on-read** for celebrities to balance latency vs. write amplification.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Twitter's 2012 Timeline Architecture](https://www.infoq.com/presentations/Twitter-Timeline-Scalability/) | Original fanout design |
| [TAO: Facebook's Graph Store](https://www.usenix.org/conference/atc13/technical-sessions/presentation/bronson) | Graph storage patterns |
| [Timelines at Scale](https://www.youtube.com/watch?v=QmDiXP_Oq3o) | Hybrid fanout approach |

---

## 🎯 The Principal Laws of Social Networking Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Graph Is Core** | Follows, blocks, mutes are edges | Dedicated graph storage |
| **Law 2: Hybrid Fanout** | Small accounts: fanout-on-write; Large: fanout-on-read | Celebrity tweets merged at read |
| **Law 3: Timeline Is Ranked** | Not just chronological | ML ranking + chronological blend |
| **Law 4: Delete Is Hard** | Tweets can be deleted | Soft delete + async cleanup |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get home timeline | 100M/s | < 100ms | Redis + Cassandra |
| 2 | Get user profile | 50M/s | < 50ms | Cache + PostgreSQL |
| 3 | Post tweet | 10K/s | < 500ms | PostgreSQL + fanout |
| 4 | Get user's tweets | 20M/s | < 50ms | Cassandra |
| 5 | Follow/unfollow user | 1M/s | < 200ms | PostgreSQL + async |
| 6 | Like tweet | 5M/s | < 100ms | Redis → Cassandra |
| 7 | Retweet | 1M/s | < 200ms | PostgreSQL + fanout |
| 8 | Search tweets | 5M/s | < 200ms | Elasticsearch |
| 9 | Get trending topics | 10M/s | < 50ms | Pre-computed cache |
| 10 | Get notifications | 10M/s | < 100ms | Cassandra |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    TWITTER DATA ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                               │
│  ✓ ACID    ✓ Users/accounts   ✓ Tweet metadata                  │
│                                                                  │
│  • users (profiles, settings)                                    │
│  • tweets (content, metadata)                                    │
│  • follows (graph edges)                                         │
│  • blocks, mutes                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │ CDC + Fanout
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Home timelines    ✓ Counters   ✓ Rate limits                 │
│                                                                  │
│  • timeline:{user_id} (ZSET, tweet_ids by score)                 │
│  • user_tweets:{user_id} (ZSET)                                  │
│  • tweet_likes:{tweet_id} (COUNT)                                │
│  • trending:{country} (ZSET)                                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Apache Cassandra                         │
│  ✓ Timelines (persistent)   ✓ Notifications   ✓ DMs             │
│                                                                  │
│  • home_timeline_by_user                                         │
│  • tweets_by_user                                                │
│  • notifications_by_user                                         │
│  • direct_messages                                               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Graph Store (FlockDB style)              │
│  ✓ Follow graph    ✓ Bidirectional lookups   ✓ Counts           │
│                                                                  │
│  • following edges                                               │
│  • follower edges (reverse index)                                │
│  • block/mute edges                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- TWITTER SCHEMA: PostgreSQL Production DDL
-- Version: Social networking with graph and timelines
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";


-- ===========================================
-- SECTION 1: USERS
-- ===========================================

CREATE TABLE users (
    id                  BIGINT PRIMARY KEY,  -- Snowflake ID
    
    -- Identity
    username            VARCHAR(15) NOT NULL UNIQUE,  -- @handle
    email               VARCHAR(255) NOT NULL UNIQUE,
    phone_number        VARCHAR(20),
    
    -- Profile
    display_name        VARCHAR(50),
    bio                 VARCHAR(160),
    location            VARCHAR(30),
    website             VARCHAR(100),
    birth_date          DATE,
    
    -- Images
    profile_image_url   TEXT,
    banner_image_url    TEXT,
    
    -- Stats (denormalized, updated async)
    followers_count     INT DEFAULT 0,
    following_count     INT DEFAULT 0,
    tweets_count        INT DEFAULT 0,
    likes_count         INT DEFAULT 0,
    
    -- Verification
    is_verified         BOOLEAN DEFAULT FALSE,
    verified_type       VARCHAR(20),  -- 'blue', 'gold', 'gray'
    
    -- Settings
    is_private          BOOLEAN DEFAULT FALSE,
    is_suspended        BOOLEAN DEFAULT FALSE,
    suspended_reason    TEXT,
    
    -- Timestamps
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_username_trgm ON users USING GIN (username gin_trgm_ops);
CREATE INDEX idx_users_created ON users(created_at);


-- ===========================================
-- SECTION 2: TWEETS
-- ===========================================

CREATE TYPE tweet_type AS ENUM ('tweet', 'reply', 'retweet', 'quote');

CREATE TABLE tweets (
    id                  BIGINT PRIMARY KEY,  -- Snowflake ID (encodes timestamp)
    user_id             BIGINT NOT NULL REFERENCES users(id),
    
    -- Content
    content             VARCHAR(280),
    tweet_type          tweet_type NOT NULL DEFAULT 'tweet',
    
    -- Reply chain
    in_reply_to_tweet_id    BIGINT REFERENCES tweets(id),
    in_reply_to_user_id     BIGINT REFERENCES users(id),
    conversation_id         BIGINT,  -- Root tweet of thread
    
    -- Retweet/Quote
    retweeted_tweet_id  BIGINT REFERENCES tweets(id),
    quoted_tweet_id     BIGINT REFERENCES tweets(id),
    
    -- Media (stored in S3/CDN)
    media_urls          TEXT[],
    media_types         TEXT[],  -- 'image', 'video', 'gif'
    
    -- Engagement (denormalized)
    reply_count         INT DEFAULT 0,
    retweet_count       INT DEFAULT 0,
    quote_count         INT DEFAULT 0,
    like_count          INT DEFAULT 0,
    view_count          BIGINT DEFAULT 0,
    bookmark_count      INT DEFAULT 0,
    
    -- Entities (extracted at write time)
    hashtags            TEXT[],
    mentions            BIGINT[],  -- User IDs
    urls                TEXT[],
    
    -- Settings
    reply_restriction   VARCHAR(20) DEFAULT 'everyone',  -- 'everyone', 'following', 'mentioned'
    
    -- Moderation
    is_deleted          BOOLEAN DEFAULT FALSE,
    deleted_at          TIMESTAMP WITH TIME ZONE,
    is_withheld         BOOLEAN DEFAULT FALSE,
    withheld_countries  TEXT[],
    
    -- Timestamps
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_tweets_user ON tweets(user_id, created_at DESC);
CREATE INDEX idx_tweets_reply ON tweets(in_reply_to_tweet_id) WHERE in_reply_to_tweet_id IS NOT NULL;
CREATE INDEX idx_tweets_conversation ON tweets(conversation_id);
CREATE INDEX idx_tweets_created ON tweets(created_at DESC);
CREATE INDEX idx_tweets_hashtags ON tweets USING GIN (hashtags);
CREATE INDEX idx_tweets_mentions ON tweets USING GIN (mentions);


-- ===========================================
-- SECTION 3: SOCIAL GRAPH (Follows)
-- ===========================================

-- Follows stored in PostgreSQL for ACID, replicated to graph store
CREATE TABLE follows (
    follower_id         BIGINT NOT NULL REFERENCES users(id),
    following_id        BIGINT NOT NULL REFERENCES users(id),
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (follower_id, following_id),
    CONSTRAINT ck_no_self_follow CHECK (follower_id != following_id)
);

-- For "who do I follow" queries
CREATE INDEX idx_follows_follower ON follows(follower_id);
-- For "who follows me" queries
CREATE INDEX idx_follows_following ON follows(following_id);


-- Blocks and mutes
CREATE TABLE blocks (
    blocker_id          BIGINT NOT NULL REFERENCES users(id),
    blocked_id          BIGINT NOT NULL REFERENCES users(id),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE mutes (
    muter_id            BIGINT NOT NULL REFERENCES users(id),
    muted_id            BIGINT NOT NULL REFERENCES users(id),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (muter_id, muted_id)
);


-- ===========================================
-- SECTION 4: ENGAGEMENTS
-- ===========================================

CREATE TABLE likes (
    user_id             BIGINT NOT NULL REFERENCES users(id),
    tweet_id            BIGINT NOT NULL REFERENCES tweets(id),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (user_id, tweet_id)
);

CREATE INDEX idx_likes_tweet ON likes(tweet_id);
CREATE INDEX idx_likes_user ON likes(user_id, created_at DESC);


CREATE TABLE bookmarks (
    user_id             BIGINT NOT NULL REFERENCES users(id),
    tweet_id            BIGINT NOT NULL REFERENCES tweets(id),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (user_id, tweet_id)
);

CREATE INDEX idx_bookmarks_user ON bookmarks(user_id, created_at DESC);


-- ===========================================
-- SECTION 5: HASHTAGS AND TRENDS
-- ===========================================

CREATE TABLE hashtags (
    id                  BIGSERIAL PRIMARY KEY,
    tag                 VARCHAR(100) NOT NULL UNIQUE,
    tweet_count         BIGINT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_hashtags_tag ON hashtags(tag);

-- Trending topics (pre-computed hourly)
CREATE TABLE trending_topics (
    id                  BIGSERIAL PRIMARY KEY,
    country_code        VARCHAR(2),  -- NULL for global
    
    rank                INT NOT NULL,
    topic_type          VARCHAR(20),  -- 'hashtag', 'keyword', 'event'
    topic               TEXT NOT NULL,
    
    tweet_count         BIGINT,
    
    computed_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    valid_until         TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_trending_country ON trending_topics(country_code, computed_at DESC);


-- ===========================================
-- SECTION 6: DIRECT MESSAGES
-- ===========================================

CREATE TABLE conversations (
    id                  BIGINT PRIMARY KEY,  -- Snowflake ID
    
    -- For 1:1, store both user IDs sorted
    participant_ids     BIGINT[] NOT NULL,
    
    -- Group DM
    is_group            BOOLEAN DEFAULT FALSE,
    group_name          VARCHAR(100),
    group_image_url     TEXT,
    
    -- Last message preview
    last_message_id     BIGINT,
    last_message_at     TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_conversations_participants ON conversations USING GIN (participant_ids);

CREATE TABLE direct_messages (
    id                  BIGINT PRIMARY KEY,  -- Snowflake ID
    conversation_id     BIGINT NOT NULL REFERENCES conversations(id),
    sender_id           BIGINT NOT NULL REFERENCES users(id),
    
    content             TEXT,
    media_url           TEXT,
    
    -- Read receipts
    read_by             BIGINT[],
    
    is_deleted          BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_dm_conversation ON direct_messages(conversation_id, created_at DESC);


-- ===========================================
-- SECTION 7: NOTIFICATIONS
-- ===========================================

CREATE TYPE notification_type AS ENUM (
    'like', 'retweet', 'quote', 'reply', 'mention',
    'follow', 'follow_request', 'dm'
);

CREATE TABLE notifications (
    id                  BIGINT PRIMARY KEY,  -- Snowflake ID
    user_id             BIGINT NOT NULL REFERENCES users(id),
    
    notification_type   notification_type NOT NULL,
    
    -- Actor (who did the action)
    actor_id            BIGINT REFERENCES users(id),
    
    -- Target
    tweet_id            BIGINT REFERENCES tweets(id),
    
    -- Multiple actors for grouped notifications
    actor_ids           BIGINT[],  -- "X and 5 others liked your tweet"
    
    is_read             BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(user_id, is_read) WHERE is_read = FALSE;
```

---

# Part 4: Cassandra DDL (Timelines)

```cql
-- ============================================================
-- TWITTER SCHEMA: Apache Cassandra Timelines
-- Keyspace: twitter_timelines
-- ============================================================

CREATE KEYSPACE IF NOT EXISTS twitter_timelines
WITH REPLICATION = {
    'class': 'NetworkTopologyStrategy',
    'us-east-1': 3,
    'us-west-2': 3,
    'eu-west-1': 3
};

USE twitter_timelines;


-- ===========================================
-- HOME TIMELINE (Fanout destination)
-- ===========================================

CREATE TABLE home_timeline_by_user (
    user_id         BIGINT,
    tweet_id        BIGINT,         -- Snowflake ID (encodes time)
    
    -- Denormalized for rendering
    author_id       BIGINT,
    author_username TEXT,
    author_name     TEXT,
    author_avatar   TEXT,
    author_verified BOOLEAN,
    
    content         TEXT,
    tweet_type      TEXT,           -- 'tweet', 'retweet', 'quote'
    media_preview   TEXT,           -- First media URL
    
    -- Engagement counts (snapshot, may be slightly stale)
    reply_count     INT,
    retweet_count   INT,
    like_count      INT,
    
    -- For retweets: who retweeted
    retweeted_by_id     BIGINT,
    retweeted_by_name   TEXT,
    
    created_at      TIMESTAMP,
    
    PRIMARY KEY ((user_id), tweet_id)
) WITH CLUSTERING ORDER BY (tweet_id DESC)
  AND gc_grace_seconds = 86400
  AND default_time_to_live = 604800;  -- 7 days, prune old tweets

-- Query: Get home timeline
-- SELECT * FROM home_timeline_by_user WHERE user_id = ? LIMIT 50;


-- ===========================================
-- USER'S TWEETS (Profile page)
-- ===========================================

CREATE TABLE tweets_by_user (
    user_id         BIGINT,
    tweet_id        BIGINT,
    
    content         TEXT,
    tweet_type      TEXT,
    
    reply_count     INT,
    retweet_count   INT,
    like_count      INT,
    view_count      BIGINT,
    
    media_urls      LIST<TEXT>,
    
    in_reply_to_tweet_id BIGINT,
    quoted_tweet_id      BIGINT,
    
    created_at      TIMESTAMP,
    
    PRIMARY KEY ((user_id), tweet_id)
) WITH CLUSTERING ORDER BY (tweet_id DESC);


-- ===========================================
-- NOTIFICATIONS
-- ===========================================

CREATE TABLE notifications_by_user (
    user_id             BIGINT,
    notification_id     BIGINT,     -- Snowflake ID
    
    notification_type   TEXT,
    
    actor_id            BIGINT,
    actor_username      TEXT,
    actor_avatar        TEXT,
    
    tweet_id            BIGINT,
    tweet_preview       TEXT,
    
    is_read             BOOLEAN,
    
    created_at          TIMESTAMP,
    
    PRIMARY KEY ((user_id), notification_id)
) WITH CLUSTERING ORDER BY (notification_id DESC)
  AND default_time_to_live = 2592000;  -- 30 days


-- ===========================================
-- FOLLOWERS/FOLLOWING LISTS
-- ===========================================

CREATE TABLE followers_by_user (
    user_id         BIGINT,
    follower_id     BIGINT,
    
    follower_username   TEXT,
    follower_name       TEXT,
    follower_avatar     TEXT,
    follower_bio        TEXT,
    
    followed_at     TIMESTAMP,
    
    PRIMARY KEY ((user_id), follower_id)
);

CREATE TABLE following_by_user (
    user_id         BIGINT,
    following_id    BIGINT,
    
    following_username  TEXT,
    following_name      TEXT,
    following_avatar    TEXT,
    
    followed_at     TIMESTAMP,
    
    PRIMARY KEY ((user_id), following_id)
);
```

---

# Part 5: Fanout Service

```python
# ============================================================
# TWITTER FANOUT SERVICE
# ============================================================

"""
Fanout strategies:
1. Small accounts (< 10K followers): Fanout-on-write
   - When user tweets, write to all followers' timelines
   - Fast reads, O(followers) writes

2. Large accounts (>= 10K followers): Fanout-on-read
   - Don't fanout at write time
   - At read time, merge celebrity tweets into timeline
   - Slow reads, O(1) writes
"""

import redis
from cassandra.cluster import Cluster
from typing import List

CELEBRITY_THRESHOLD = 10000

class FanoutService:
    def __init__(self):
        self.redis = redis.Redis()
        self.cassandra = Cluster(['cassandra1', 'cassandra2']).connect('twitter_timelines')
    
    def on_tweet_created(self, tweet: dict, author: dict):
        """
        Called when a tweet is created.
        Decides fanout strategy based on follower count.
        """
        follower_count = author['followers_count']
        
        if follower_count < CELEBRITY_THRESHOLD:
            # Fanout-on-write for small accounts
            self._fanout_to_followers(tweet, author)
        else:
            # For celebrities, just mark tweet for read-time merge
            self._mark_celebrity_tweet(tweet, author)
    
    def _fanout_to_followers(self, tweet: dict, author: dict):
        """
        Write tweet to all followers' timelines.
        """
        # Get all followers (paginated in production)
        followers = self._get_followers(author['id'])
        
        # Prepare denormalized tweet data
        timeline_entry = {
            'tweet_id': tweet['id'],
            'author_id': author['id'],
            'author_username': author['username'],
            'author_name': author['display_name'],
            'author_avatar': author['profile_image_url'],
            'author_verified': author['is_verified'],
            'content': tweet['content'],
            'tweet_type': tweet['tweet_type'],
            'created_at': tweet['created_at'],
        }
        
        # Write to each follower's timeline (async in production)
        for follower_id in followers:
            # Redis for hot data
            self.redis.zadd(
                f"timeline:{follower_id}",
                {tweet['id']: tweet['id']}  # Score = tweet_id (timestamp encoded)
            )
            self.redis.zremrangebyrank(f"timeline:{follower_id}", 0, -801)  # Keep 800
            
            # Cassandra for persistence
            self.cassandra.execute(
                """
                INSERT INTO home_timeline_by_user 
                (user_id, tweet_id, author_id, author_username, content, created_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (follower_id, tweet['id'], author['id'], 
                 author['username'], tweet['content'], tweet['created_at'])
            )
    
    def _mark_celebrity_tweet(self, tweet: dict, author: dict):
        """
        For celebrities, store tweet for read-time merge.
        """
        # Store in celebrity tweets set for merge during read
        self.redis.zadd(
            f"celebrity_tweets:{author['id']}",
            {tweet['id']: tweet['id']}
        )
        self.redis.zremrangebyrank(f"celebrity_tweets:{author['id']}", 0, -101)
    
    def get_home_timeline(self, user_id: int, limit: int = 50) -> List[dict]:
        """
        Get home timeline, merging celebrity tweets at read time.
        """
        # Get base timeline from Redis
        tweet_ids = self.redis.zrevrange(
            f"timeline:{user_id}", 0, limit - 1
        )
        
        # Get celebrities this user follows
        celebrity_ids = self._get_followed_celebrities(user_id)
        
        # Merge celebrity tweets
        for celeb_id in celebrity_ids:
            celeb_tweets = self.redis.zrevrange(
                f"celebrity_tweets:{celeb_id}", 0, 10
            )
            tweet_ids.extend(celeb_tweets)
        
        # Sort by tweet_id (timestamp) and take top N
        tweet_ids = sorted(set(tweet_ids), reverse=True)[:limit]
        
        # Fetch full tweet data (from cache or Cassandra)
        return self._hydrate_tweets(tweet_ids)
    
    def _get_followers(self, user_id: int) -> List[int]:
        """Get follower IDs (paginated in production)."""
        pass
    
    def _get_followed_celebrities(self, user_id: int) -> List[int]:
        """Get celebrity IDs that this user follows."""
        pass
    
    def _hydrate_tweets(self, tweet_ids: List[int]) -> List[dict]:
        """Fetch full tweet data for IDs."""
        pass
```

---

# Part 6: Snowflake ID Generator

```python
# ============================================================
# SNOWFLAKE ID GENERATOR
# Twitter's distributed unique ID system
# ============================================================

"""
Snowflake ID structure (64 bits):
- 1 bit: sign (always 0)
- 41 bits: timestamp (milliseconds since epoch, ~69 years)
- 10 bits: machine ID (1024 machines)
- 12 bits: sequence (4096 IDs per millisecond per machine)

Advantages:
- Sortable by time (no need for created_at index)
- Distributed generation (no central coordinator)
- 64-bit fits in BIGINT
"""

import time
import threading

EPOCH = 1288834974657  # Twitter epoch (Nov 4, 2010)

class SnowflakeGenerator:
    def __init__(self, machine_id: int):
        if not 0 <= machine_id < 1024:
            raise ValueError("Machine ID must be 0-1023")
        
        self.machine_id = machine_id
        self.sequence = 0
        self.last_timestamp = -1
        self.lock = threading.Lock()
    
    def next_id(self) -> int:
        with self.lock:
            timestamp = self._current_time()
            
            if timestamp < self.last_timestamp:
                raise Exception("Clock moved backwards!")
            
            if timestamp == self.last_timestamp:
                self.sequence = (self.sequence + 1) & 0xFFF  # 12 bits
                if self.sequence == 0:
                    # Sequence exhausted, wait for next ms
                    timestamp = self._wait_next_ms(timestamp)
            else:
                self.sequence = 0
            
            self.last_timestamp = timestamp
            
            # Compose ID
            id = (
                ((timestamp - EPOCH) << 22) |  # 41 bits timestamp
                (self.machine_id << 12) |       # 10 bits machine
                self.sequence                    # 12 bits sequence
            )
            
            return id
    
    def _current_time(self) -> int:
        return int(time.time() * 1000)
    
    def _wait_next_ms(self, last_ts: int) -> int:
        ts = self._current_time()
        while ts <= last_ts:
            ts = self._current_time()
        return ts
    
    @staticmethod
    def extract_timestamp(snowflake_id: int) -> int:
        """Extract timestamp from Snowflake ID."""
        return ((snowflake_id >> 22) + EPOCH)
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Snowflake IDs | Time-sortable, distributed generation |
| 2 | Hybrid fanout | < 10K: write-time, >= 10K: read-time merge |
| 3 | Social graph indexed both ways | follower_id, following_id indexes |
| 4 | Denormalized timeline entries | No joins at read time |
| 5 | Soft delete for tweets | is_deleted flag, deleted_at timestamp |
| 6 | Trending pre-computed | trending_topics refreshed hourly |
| 7 | Notifications by user | Cassandra with TTL |
| 8 | Redis timeline cache | 800 entries, LRU eviction |

---

# Part 7: DynamoDB Single-Table Design

```
============================================================
TWITTER: DynamoDB Single-Table Design
For core entities and timelines at scale
============================================================

TABLE: twitter_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (user timeline, following)
- GSI2: GSI2PK / GSI2SK (search, notifications)

============================================================
ENTITY PATTERNS
============================================================

USER
  PK: USER#{user_id}
  SK: PROFILE
  GSI2PK: USERNAME#{username}
  GSI2SK: PROFILE
  
  Attributes: username, display_name, followers_count, following_count

TWEET
  PK: TWEET#{tweet_id}
  SK: META
  GSI1PK: USER#{user_id}
  GSI1SK: TWEET#{timestamp}
  
  Attributes: content, user_id, created_at, reply_count, like_count

TIMELINE ENTRY (Fanout)
  PK: USER#{user_id}
  SK: HOME#{timestamp}#{tweet_id}
  
  Attributes: tweet_id, author_id, summary_alert

FOLLOW EDGE
  PK: USER#{follower_id}
  SK: FOLLOWS#{following_id}
  GSI1PK: USER#{following_id}
  GSI1SK: FOLLOWER#{follower_id}
  
  Attributes: created_at

LIKE ACTION
  PK: TWEET#{tweet_id}
  SK: LIKE#{user_id}
  GSI1PK: USER#{user_id}
  GSI1SK: LIKED#{timestamp}
  
  Attributes: created_at

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get user profile
   Table: PK=USER#{user_id}, SK=PROFILE

2. Get user by username
   GSI2: PK=USERNAME#{username}

3. Get user's tweets (Profile timeline)
   GSI1: PK=USER#{user_id}, SK begins_with "TWEET#" (Reverse sorted)

4. Get home timeline (Materialized view)
   Table: PK=USER#{user_id}, SK begins_with "HOME#" (Reverse sorted)

5. Get tweet details
   Table: PK=TWEET#{tweet_id}, SK=META

6. Get users I follow
   Table: PK=USER#{my_id}, SK begins_with "FOLLOWS#"

7. Get my followers
   GSI1: PK=USER#{my_id}, SK begins_with "FOLLOWER#"

8. Get likes on a tweet
   Table: PK=TWEET#{tweet_id}, SK begins_with "LIKE#"
```

---

# Part 8: Query Examples with EXPLAIN

```sql
-- ============================================================
-- TWITTER QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Home Timeline Build (Pull Model)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    t.id,
    t.content,
    t.created_at,
    u.username,
    u.display_name,
    u.profile_image_url
FROM follows f
JOIN tweets t ON t.user_id = f.following_id
JOIN users u ON u.id = t.user_id
WHERE f.follower_id = $1
  AND t.created_at > NOW() - INTERVAL '24 hours'
ORDER BY t.created_at DESC
LIMIT 50;

-- NOTE: This "Pull" query kills DBs at scale. 
-- Used only for low-traffic users or development.
-- Expected: Nested Loop Join, expensive for many followings.


-- ===========================================
-- QUERY 2: User Profile Tweets
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    id, content, created_at, reply_count, retweet_count, like_count, media_urls
FROM tweets
WHERE user_id = $1
  AND is_deleted = FALSE
ORDER BY created_at DESC
LIMIT 20;

-- Expected: Index scan on idx_tweets_user, ~2ms


-- ===========================================
-- QUERY 3: Detailed Tweet View (Thread)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    t.id, t.content, u.username,
    -- Recursive CTE usually better, but for single level:
    r.id AS reply_id, r.content AS reply_content
FROM tweets t
JOIN users u ON u.id = t.user_id
LEFT JOIN tweets r ON r.in_reply_to_tweet_id = t.id
WHERE t.id = $1
ORDER BY r.like_count DESC
LIMIT 50;

-- Expected: Index scan on PK and idx_tweets_reply, ~5ms


-- ===========================================
-- QUERY 4: Trending Hashtags (Global)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    topic,
    tweet_count,
    rank
FROM trending_topics
WHERE country_code IS NULL
  AND computed_at > NOW() - INTERVAL '1 hour'
ORDER BY rank ASC
LIMIT 10;

-- Expected: Index scan on idx_trending_country, <1ms (cached)


-- ===========================================
-- QUERY 5: Followers List (Pagination)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    u.id, u.username, u.display_name, u.bio
FROM follows f
JOIN users u ON u.id = f.follower_id
WHERE f.following_id = $1
  AND f.follower_id > $2  -- Cursor based pagination
ORDER BY f.follower_id ASC
LIMIT 20;

-- Expected: Index scan on idx_follows_following, ~10ms


-- ===========================================
-- QUERY 6: Search Tweets (Full Text)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    t.id, t.content, ts_headline(t.content, q)
FROM tweets t,
     plainto_tsquery('english', $1) q
WHERE to_tsvector('english', t.content) @@ q
ORDER BY t.created_at DESC
LIMIT 20;

-- Expected: GIN index scan (if added), otherwise seq scan (slow)
-- In prod, use Elasticsearch.
```

---

# Part 9: Capacity Planning

```
============================================================
TWITTER CAPACITY PLANNING
============================================================

ASSUMPTIONS (Scale X):
- 500M DAU
- 500M Tweets/day (average)
- 100B Follow edges (200 avg per user)
- Peak: 1M writes/sec (World Cup finals)

============================================================
STORAGE ESTIMATES (1 Year)
============================================================

TWEETS
  Rows: 500M * 365 = 182.5 Billion
  Row Size: ~200 bytes (compressed)
  Total: ~36.5 TB
  Replica (3x): ~110 TB

MEDIA
  Assume 20% tweets have media (avg 500KB)
  Total: 36.5B * 0.2 * 500KB = 3.6 PB
  (Stored in S3/Blob, not DB)

SOCIAL GRAPH (Follows)
  Rows: 100 Billion
  Row Size: ~32 bytes (2 BIGINTs + TS)
  Total: ~3.2 TB
  RAM Requirements (Graph): ~1 TB for caching hot edges

TIMELINES (Fanout)
  500M Users * 800 tweets cached = 400 Billion entries
  Row Size: ~80 bytes
  Total: ~32 TB (Cassandra/Redis)

============================================================
THROUGHPUT REQUIREMENTS
============================================================

WRITE PATH:
  Tweets: 6K/sec avg, 50K/sec peak
  Fanout: 6K * 500 followers = 3M writes/sec avg!
  -> Requires massive Redis/Cassandra write bandwidth.

READ PATH:
  Home Timeline: 300K/sec avg
  User Timeline: 100K/sec avg
  -> 99% served from Redis cache.

BANDWIDTH:
  Ingress: ~10 Gbps
  Egress (Media): ~500 Gbps

============================================================
SCALING STRATEGY
============================================================

1. SHARDING (By ID)
   - Snowflake IDs are time-sortable.
   - Shard Tweets by (tweet_id >> 22) / time_bucket? NO.
   - Shard Tweets by user_id for locality? 
   - Twitter approach: Shard by Tweet ID (random dist) + Lookup Service (Gizzard/Manhattan).

2. CACHING (Redis Clusters)
   - Timeline Cache: Ephemeral, LRU.
   - User Cache: Persistent, write-through.
   - Tweet Cache: Hot tweets (viral) need local caching on app servers.

3. ARCHIVAL
   - Tweets > 5 years -> Cold Storage (Hadoop/S3).
   - "Search" queries hit indexers, not primary DB.
```

---

# Part 10: Anti-Patterns to Avoid

```
============================================================
TWITTER ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: "Pull" Model for Everyone
-----------------------------------------
WRONG:
  SELECT * FROM tweets WHERE user_id IN (SELECT following...);
  -- With 500 following, this query kills the DB.
  
RIGHT:
  -- Fanout-on-write. Pre-compute the timeline list.
  SELECT * FROM tweets WHERE id IN (redis.get_timeline(me));


❌ ANTI-PATTERN 2: Using AUTO_INCREMENT IDs
-----------------------------------------
WRONG:
  id SERIAL PRIMARY KEY
  -- Leaks growth rate, requires central lock for inserts.
  
RIGHT:
  -- Snowflake IDs.
  -- Distributed, k-ordered, high throughput.


❌ ANTI-PATTERN 3: Synchronous Media Upload
-----------------------------------------
WRONG:
  POST /tweet { "image": "binary_data..." }
  -- Blocks connection for seconds.
  
RIGHT:
  -- 1. POST /media/upload -> Returns media_id
  -- 2. POST /tweet { "media_ids": [...] } -> Fast metadata write.


❌ ANTI-PATTERN 4: Counting Likes in Real-Time
-----------------------------------------
WRONG:
  SELECT COUNT(*) FROM likes WHERE tweet_id = ?
  -- For a viral tweet (1M likes), this times out.
  
RIGHT:
  -- Denormalized counter in Tweets table.
  -- Incremented via Redis or Async job.
  -- "Approximate" counts for UI.


❌ ANTI-PATTERN 5: Recursive Reply Chains in SQL
-----------------------------------------
WRONG:
  WITH RECURSIVE thread AS ...
  -- Complex to optimize, deep trees hurt performance.
  
RIGHT:
  -- Store `conversation_id` explicitly.
  -- Fetch all tweets with `conversation_id = X`.
  -- Reconstruct tree in application memory (client-side).


❌ ANTI-PATTERN 6: Hard Deletes for Tweets
-----------------------------------------
WRONG:
  DELETE FROM tweets WHERE id = ?
  -- Fragmentation, expensive row movements.
  
RIGHT:
  -- Soft Delete: `is_deleted = true`.
  -- Garbage Collection: Async process deletes old rows during off-peak.


❌ ANTI-PATTERN 7: Following Limits Enforced by Count
-----------------------------------------
WRONG:
  if (SELECT count(*) FROM follows...) > 5000: fail
  -- Count scan is slow.
  
RIGHT:
  -- Denormalized `following_count` on User profile.
  -- Check user.following_count > 5000.


❌ ANTI-PATTERN 8: Storing Media in Database
-----------------------------------------
WRONG:
  image_blob BYTEA
  -- Bloats DB pages, ruins cache locality.
  
RIGHT:
  -- Store in S3/GCS.
  -- Store URL/Path in DB.


❌ ANTI-PATTERN 9: Global Transactions for Actions
-----------------------------------------
WRONG:
  BEGIN; Insert Like; Update Count; COMMIT;
  -- Contention on hot rows (viral tweets).
  
RIGHT:
  -- Insert Like (Fire & Forget/Queue).
  -- Update Count (Async aggregation or Redis incr).


❌ ANTI-PATTERN 10: Assuming 100% Consistency
-----------------------------------------
WRONG:
  User A tweets, User B must see it in 1ms.
  -- Requires synchronous fanout, kills availability.
  
RIGHT:
  -- Eventual Consistency.
  -- "5 seconds delay" is acceptable for timelines.
```

---

# Part 11: CDC & Disaster Recovery

```
============================================================
TWITTER CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (Tweets)    │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │Search Idx │    │ Fanout    │   │ Trend Calc│  │ Safety   │
  │ (Elastic) │    │ Service   │   │ (Flink)   │  │ (Mod)    │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- twitter.tweets.created  (Fanout trigger)
- twitter.users.updated   (Profile cache invalidation)
- twitter.engagements     (Likes/RTs -> notification/trends)
- twitter.media.uploaded  (Processing pipeline)

============================================================
DISASTER RECOVERY
============================================================

Core Philosophy: "Tweets Must Flow"
- Write availability > Read consistency.

FAILOVER STRATEGY:
1. Multi-Region Active-Active
   - Tweets written to local DC (e.g., US-West).
   - Async replicated to US-East, EU.
   - Conflict Resolvers: Last-Writer-Wins (LWW) usually sufficient for social content.

2. Graph Store DR
   - Periodic snapshots of Graph edges.
   - If Graph DB fails, fallback to Postgres replicas (slower, but functional).

3. Cached Timelines
   - If Redis fails, timelines are empty.
   - "Rebuild" service runs: query recent tweets from Followings -> populate Redis.
   - Expensive, so run with reduced fidelity (e.g., top 100 friends only).

BACKUP:
- Tweets are immutable (mostly).
- Continuous backup to HDFS/S3.
- Monthly "Snapshot" of user graph.
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- TWITTER: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / MODERATION LOG
-- ===========================================

CREATE TABLE moderation_log (
    id                  BIGSERIAL PRIMARY KEY,
    actor_id            BIGINT NOT NULL,  -- Moderator/System
    action_type         VARCHAR(50) NOT NULL,  -- 'suspend', 'unsuspend', 'delete_tweet'
    target_type         VARCHAR(50) NOT NULL,  -- 'user', 'tweet'
    target_id           BIGINT NOT NULL,
    reason              TEXT NOT NULL,
    old_state           JSONB,
    new_state           JSONB,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address          INET
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_mod_target ON moderation_log(target_type, target_id);


-- ===========================================
-- B. MEDIA / ATTACHMENTS
-- ===========================================

CREATE TABLE media (
    id                  BIGINT PRIMARY KEY,  -- Snowflake ID
    tweet_id            BIGINT REFERENCES tweets(id),
    user_id             BIGINT NOT NULL REFERENCES users(id),
    media_type          VARCHAR(20) NOT NULL,  -- 'image', 'video', 'gif'
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    width               INT,
    height              INT,
    duration_ms         INT,  -- For video
    storage_key         VARCHAR(500) NOT NULL,
    cdn_url             VARCHAR(500),
    thumbnail_key       VARCHAR(500),
    alt_text            VARCHAR(1000),
    blurhash            VARCHAR(100),  -- Low-res placeholder
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_media_tweet ON media(tweet_id);
CREATE INDEX idx_media_user ON media(user_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             BIGINT NOT NULL,
    channel             VARCHAR(20) NOT NULL,  -- 'push_ios', 'push_android', 'email'
    device_token        VARCHAR(255),
    notification_type   VARCHAR(100) NOT NULL,  -- 'like', 'retweet', 'follow', 'mention'
    title               VARCHAR(100),
    body                TEXT NOT NULL,
    payload             JSONB,  -- Deep link data
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS (For Developer API)
-- ===========================================

CREATE TABLE developer_apps (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id            BIGINT NOT NULL REFERENCES users(id),
    name                VARCHAR(100) NOT NULL,
    description         TEXT,
    website_url         VARCHAR(500),
    callback_url        VARCHAR(500),
    client_id           VARCHAR(64) NOT NULL UNIQUE,
    client_secret_hash  VARCHAR(64) NOT NULL,
    tier                VARCHAR(20) DEFAULT 'basic',  -- basic, pro, enterprise
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    app_id              UUID NOT NULL REFERENCES developer_apps(id),
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['tweet.create', 'dm.receive']
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- E. API KEYS / RATE LIMITING
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    app_id              UUID REFERENCES developer_apps(id),
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100),
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 300,  -- API v2 limit
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- F. OAUTH
-- ===========================================

CREATE TABLE oauth_tokens (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             BIGINT NOT NULL REFERENCES users(id),
    app_id              UUID NOT NULL REFERENCES developer_apps(id),
    access_token_hash   VARCHAR(64) NOT NULL,
    refresh_token_hash  VARCHAR(64),
    scopes              TEXT[],
    expires_at          TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at          TIMESTAMP WITH TIME ZONE
);


-- ===========================================
-- G. USER SESSIONS
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             BIGINT NOT NULL REFERENCES users(id),
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_type         VARCHAR(50),
    device_name         VARCHAR(100),
    ip_address          INET NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS (For A/B Testing)
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    target_countries    TEXT[],
    min_account_age_days INT,  -- Only old accounts
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
TWITTER: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. FANOUT ENGINE INTERNALS
============================================================

ARCHITECTURE:
Tweet Posted → Fanout Service → Redis XADD → Worker Fleet → Timeline Updates

FANOUT STRATEGIES:
┌─────────────────────────────────────────────────────────────┐
│  ACCOUNT TYPE      │ FOLLOWERS  │ STRATEGY              │
├─────────────────────────────────────────────────────────────┤
│  Normal User       │ < 10K      │ Pure Push (Fanout)    │
│  Power User        │ 10K-1M     │ Push + Async Queue    │
│  Celebrity         │ > 1M       │ Pull at Read Time     │
│  "Justin Bieber"   │ > 100M     │ Read-time Only        │
└─────────────────────────────────────────────────────────────┘

FANOUT WORKER CONFIGURATION:
- Worker Pool: 10,000 workers (Go/Scala)
- Batch Size: 5,000 timeline updates per batch
- Target Latency: < 5 seconds from tweet → all timelines updated
- Backpressure: Kafka consumer lag alarm at 30s

CELEBRITY EXEMPTION LIST:
- Maintained as Redis SET: celebrity_users
- Threshold: follower_count > 1,000,000
- Updated hourly via cron job
- Read-path checks: IF author IN celebrity_set → merge at read

============================================================
2. REDIS CLUSTER CONFIGURATION
============================================================

CLUSTER TOPOLOGY (Timeline Cluster):
┌─────────────────────────────────────────────────────────────┐
│  ROLE          │ NODES  │ MEMORY   │ SHARDS              │
├─────────────────────────────────────────────────────────────┤
│  Timeline      │ 300    │ 256 GB   │ 1000 (hash slots)   │
│  Counters      │ 50     │ 128 GB   │ 200                 │
│  Rate Limit    │ 20     │ 64 GB    │ 100                 │
│  Trending      │ 10     │ 128 GB   │ 50 (per region)     │
└─────────────────────────────────────────────────────────────┘

REDIS.CONF TUNING:
```redis
# Timeline cluster settings
maxmemory 256gb
maxmemory-policy allkeys-lru

# Hash slot optimization
hash-max-ziplist-entries 512
hash-max-ziplist-value 64

# ZSET optimization (timelines)
zset-max-ziplist-entries 128
zset-max-ziplist-value 64

# Disable persistence (Redis as cache)
appendonly no
save ""

# Cluster config
cluster-enabled yes
cluster-node-timeout 5000
cluster-require-full-coverage no  # Keep serving if some slots unavailable
```

TIMELINE DATA STRUCTURE:
Key: timeline:{user_id}
Type: SORTED SET (ZSET)
Score: Snowflake ID (embeds timestamp)
Value: tweet_id
Max Size: 800 entries (trimmed via ZREMRANGEBYRANK)

OPERATIONS:
- ZADD timeline:{uid} {snowflake_id} {tweet_id}  -- Write
- ZREVRANGE timeline:{uid} 0 49 WITHSCORES      -- Read top 50
- ZREMRANGEBYRANK timeline:{uid} 0 -801         -- Trim to 800

============================================================
3. HYBRID FANOUT IMPLEMENTATION
============================================================

READ PATH (Home Timeline):
1. Get user's timeline from Redis: ZREVRANGE timeline:{uid} 0 49
2. Get celebrity list user follows: SMEMBERS celeb_following:{uid}
3. For each celebrity: Get latest 5 tweets from tweets_by_user
4. Merge by Snowflake ID score
5. Apply ML ranking (optional)
6. Return ordered list

OPTIMIZATION: CELEBRITY TWEET CACHE
```
Key: celeb_tweets:{user_id}
TTL: 60 seconds
Content: Pre-ranked top 10 tweets
Update: On each tweet, invalidate cache
```

FANOUT QUEUE DESIGN (Kafka):
Topics:
- fanout.tweets.high-priority (celebrities, trending)
- fanout.tweets.normal (regular users)
- fanout.tweets.low-priority (old accounts, batch eligible)

Consumer Groups:
- fanout-workers (100 consumers)
- Partition by: user_id % 1000

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Timeline Load Latency (p99)  │ < 100ms │ > 200ms = PAGE  │
│  Tweet Post Latency (p99)     │ < 500ms │ > 1s = PAGE     │
│  Fanout Completion %          │ > 99%   │ < 95% = PAGE    │
│  Redis Hit Rate               │ > 95%   │ < 90% = WARN    │
│  Graph Query Latency (p99)    │ < 50ms  │ > 100ms = WARN  │
└─────────────────────────────────────────────────────────────┘

REDIS METRICS TO WATCH:
- `used_memory` vs `maxmemory` (should never hit 100%)
- `evicted_keys` (should be low, means cache is working)
- `keyspace_hits / (keyspace_hits + keyspace_misses)` (hit rate)
- `instantaneous_ops_per_sec` (baseline: 500K-1M ops/sec)
- `connected_clients` (watch for connection leaks)
- `cluster_state` (should always be "ok")

POSTGRESQL METRICS:
- `pg_stat_activity` wait events (especially `LWLock:*`)
- Replication lag: `pg_stat_replication.replay_lag`
- Transaction wraparound: `age(datfrozenxid)` < 500M
- Connection pool utilization: PgBouncer wait count

KAFKA METRICS (Fanout):
- Consumer Lag: `kafka_consumer_group_lag`
- Partition Skew: Check for hot partitions (celebrity tweets)
- Producer Throughput: Should handle 10K tweets/sec burst

ALERTING RULES:
```yaml
# Prometheus AlertManager
- alert: TimelineLatencyHigh
  expr: histogram_quantile(0.99, timeline_load_latency_seconds) > 0.2
  for: 5m
  labels:
    severity: page

- alert: FanoutBacklog
  expr: kafka_consumer_group_lag{topic="fanout.tweets"} > 100000
  for: 2m
  labels:
    severity: page

- alert: RedisEvictionSpike
  expr: rate(redis_evicted_keys[5m]) > 1000
  for: 3m
  labels:
    severity: warning
```

============================================================
5. FAILURE MODE ANALYSIS (CHAOS ENGINEERING)
============================================================

SCENARIO 1: REDIS CLUSTER PARTIAL FAILURE
-----------------------------------------
Symptom: Some hash slots unavailable.
Impact: ~10% of timeline reads fail.

Mitigation:
1. cluster-require-full-coverage = no (already set)
2. Client retry with exponential backoff
3. Fallback: Query Cassandra for persistent timeline
4. Circuit breaker: After 3 Redis failures, use Cassandra-only path

SCENARIO 2: FANOUT QUEUE BACKLOG (Viral Tweet)
-----------------------------------------
Symptom: Celebrity tweets cause 100M writes.
Impact: Fanout latency > 5 minutes.

Mitigation:
1. Celebrity detection: Skip fanout for accounts > 1M followers
2. Merge at read time (already implemented)
3. Priority queues: Non-celebrity tweets get priority
4. Adaptive batch size: Increase to 10K during backlog

SCENARIO 3: THUNDERING HERD ON CELEBRITY PROFILE
-----------------------------------------
Symptom: 10M users load same profile simultaneously.
Impact: PostgreSQL CPU spike, connection exhaustion.

Mitigation:
1. Edge caching (CDN): Cache profile for 30s at edge
2. Read-through cache: Single-flight pattern (Go: singleflight)
3. Rate limit: 1000 req/sec per user_id
4. Circuit breaker: If > 5000 req/sec, return cached version

SCENARIO 4: TIMELINE CACHE EVICTION STORM
-----------------------------------------
Symptom: Memory pressure causes mass eviction.
Impact: Cache miss → Cassandra overload.

Mitigation:
1. LRU eviction (already configured)
2. Tiered caching: Hot users in Redis, warm in local cache
3. Cache warming: On deploy, pre-populate top 1M users
4. Admission control: Don't cache single-access timelines

SCENARIO 5: SNOWFLAKE ID GENERATOR FAILURE
-----------------------------------------
Symptom: ID generation service down.
Impact: Cannot post tweets.

Mitigation:
1. Each data center has independent Snowflake workers
2. Client-side ID generation fallback (UUIDv7)
3. Queue tweets in Kafka with placeholder ID
4. Backfill IDs when service recovers

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

TIERING STRATEGY:
┌─────────────────────────────────────────────────────────────┐
│  DATA              │ AGE       │ STORAGE      │ ACCESS     │
├─────────────────────────────────────────────────────────────┤
│  Timelines         │ Current   │ Redis        │ 100M/s     │
│  Timelines         │ > 7 days  │ Cassandra    │ 10M/s      │
│  Tweets            │ < 30 days │ PostgreSQL   │ 20M/s      │
│  Tweets            │ > 30 days │ Parquet/S3   │ Batch only │
│  Media             │ All       │ S3 + CDN     │ Edge cache │
└─────────────────────────────────────────────────────────────┘

REDIS COST OPTIMIZATION:
- Use Redis Cluster vs Elasticache: ~40% savings
- Graviton3 (ARM) instances: ~20% savings
- Memory-optimized (r7g) for timeline cluster
- Compute-optimized (c7g) for rate limiting

COMPRESSION:
- Tweets: ZSTD compression in Cassandra (60% reduction)
- Media: WebP for images, AV1 for video
- Timeline IDs: Varint encoding (8 bytes → 2-4 bytes)

INSTANCE SIZING (AWS Example):
```
Timeline Redis:     100x r7g.4xlarge (128 GB each)
Counter Redis:      20x r7g.2xlarge
PostgreSQL:         10x db.r6g.8xlarge (Primary + Replicas)
Cassandra:          50x i4g.4xlarge (SSD optimized)
Fanout Workers:     100x c7g.xlarge (Spot instances OK)
```

COST BREAKDOWN (Estimated Monthly):
- Redis (Timelines): $150K
- PostgreSQL RDS: $80K
- Cassandra (Self-managed): $100K
- Kafka (MSK): $50K
- S3 (Media): $200K
- Total Compute: ~$600K/month for core data layer
```

---

## 🔗 Related Documents

- [Pinterest Schema](./pinterest-schema-design-guide.md) — Similar fanout pattern
- [Consistent Hashing](../system-design-notes/consistent-hashing-guide.md) — Shard distribution
- [Database Scaling](./database-scaling-guide.md) — Sharding strategies
- [Healthcare Schema](./healthcare-schema-design-guide.md) — Audit trail patterns (for Safety/Moderation logs)
- [Uber Schema](./uber-schema-design-guide.md) — Operational Excellence reference
