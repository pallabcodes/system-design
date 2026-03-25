# Slack/Discord Messaging: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Workspaces, Channels, Messages, Threads, Reactions, Presence — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Fetching ALL messages for a channel. Messages must be **paginated** with cursor-based pagination. Even "unread" requires careful counting.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Slack's Real-time Messaging](https://slack.engineering/real-time-messaging/) | WebSocket architecture |
| [Discord's Data Store](https://discord.com/blog/how-discord-stores-trillions-of-messages) | Cassandra → ScyllaDB |
| [Presence at Scale](https://www.pubnub.com/blog/how-to-design-a-presence-platform/) | Online status |

---

## 🎯 The Principal Laws of Messaging Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Messages Are Append-Only** | Write-heavy, read-sequential | Time-series storage |
| **Law 2: Channels Can Be Huge** | Millions of messages | Partition by channel + time bucket |
| **Law 3: Presence Is Ephemeral** | Online/offline changes constantly | Redis, not PostgreSQL |
| **Law 4: Unread Counts Are Expensive** | Don't count at read time | Maintain counters |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get recent messages (page) | 50M/s | < 50ms | Cassandra/ScyllaDB |
| 2 | Get channel list | 10M/s | < 30ms | PostgreSQL + Cache |
| 3 | Send message | 5M/s | < 100ms | Cassandra + Kafka |
| 4 | Get thread messages | 10M/s | < 50ms | Cassandra |
| 5 | Get unread counts | 20M/s | < 20ms | Redis |
| 6 | Mark channel as read | 10M/s | < 50ms | Redis → PostgreSQL |
| 7 | Get user presence | 10M/s | < 10ms | Redis |
| 8 | Search messages | 1M/s | < 200ms | Elasticsearch |
| 9 | Add reaction | 5M/s | < 100ms | Cassandra |
| 10 | Get channel members | 5M/s | < 30ms | PostgreSQL + Cache |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    MESSAGING DATA ARCHITECTURE                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                               │
│  ✓ Workspaces/teams    ✓ Channels   ✓ Users   ✓ Membership      │
│                                                                  │
│  • workspaces, users, workspace_members                          │
│  • channels, channel_members                                     │
│  • user_channel_state (last_read_at)                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Cassandra/ScyllaDB                       │
│  ✓ Messages (billions)    ✓ Threads   ✓ Reactions               │
│                                                                  │
│  • messages_by_channel (time-bucketed)                           │
│  • messages_by_thread                                            │
│  • reactions_by_message                                          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Unread counts    ✓ Presence   ✓ Typing indicators            │
│                                                                  │
│  • unread:{user_id}:{channel_id}                                 │
│  • presence:{workspace_id}                                       │
│  • typing:{channel_id}                                           │
│  • online:{user_id}                                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         WebSocket Gateway                        │
│  ✓ Real-time delivery    ✓ Pub/Sub   ✓ Connection management    │
│                                                                  │
│  • User connections (millions concurrent)                        │
│  • Channel subscriptions                                         │
│  • Message fanout                                                │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL (Metadata)

```sql
-- ============================================================
-- MESSAGING SCHEMA: PostgreSQL Production DDL
-- Version: Workspace and channel metadata
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";


-- ===========================================
-- SECTION 1: WORKSPACES (Teams)
-- ===========================================

CREATE TYPE workspace_plan AS ENUM ('free', 'pro', 'business', 'enterprise');

CREATE TABLE workspaces (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identity
    name                VARCHAR(100) NOT NULL,
    slug                VARCHAR(50) NOT NULL UNIQUE,  -- team.slack.com
    
    -- Settings
    plan                workspace_plan DEFAULT 'free',
    icon_url            TEXT,
    
    -- Limits
    member_limit        INT,
    storage_limit_gb    INT,
    
    -- Stats (denormalized)
    member_count        INT DEFAULT 0,
    channel_count       INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_workspaces_slug ON workspaces(slug);


-- ===========================================
-- SECTION 2: USERS
-- ===========================================

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Auth
    email               VARCHAR(255) NOT NULL UNIQUE,
    password_hash       TEXT,
    
    -- Profile (workspace-independent)
    display_name        VARCHAR(100),
    avatar_url          TEXT,
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);


-- ===========================================
-- SECTION 3: WORKSPACE MEMBERSHIP
-- ===========================================

CREATE TYPE member_role AS ENUM ('owner', 'admin', 'member', 'guest');
CREATE TYPE member_status AS ENUM ('active', 'invited', 'deactivated');

CREATE TABLE workspace_members (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id        UUID NOT NULL REFERENCES workspaces(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    
    -- Role
    role                member_role DEFAULT 'member',
    status              member_status DEFAULT 'invited',
    
    -- Profile override for this workspace
    display_name        VARCHAR(100),
    title               VARCHAR(100),
    avatar_url          TEXT,
    
    -- Status message
    status_text         VARCHAR(100),
    status_emoji        VARCHAR(50),
    status_expiration   TIMESTAMP WITH TIME ZONE,
    
    -- Notification preferences
    notification_preference VARCHAR(20) DEFAULT 'all',  -- 'all', 'mentions', 'nothing'
    
    -- Timestamps
    joined_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_workspace_member UNIQUE (workspace_id, user_id)
);

CREATE INDEX idx_wm_workspace ON workspace_members(workspace_id);
CREATE INDEX idx_wm_user ON workspace_members(user_id);


-- ===========================================
-- SECTION 4: CHANNELS
-- ===========================================

CREATE TYPE channel_type AS ENUM ('public', 'private', 'direct', 'group_dm');

CREATE TABLE channels (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id        UUID NOT NULL REFERENCES workspaces(id),
    
    -- Identity
    name                VARCHAR(80),  -- NULL for DMs
    topic               VARCHAR(250),
    description         TEXT,
    
    channel_type        channel_type NOT NULL,
    
    -- Creator
    created_by          UUID REFERENCES users(id),
    
    -- Stats
    member_count        INT DEFAULT 0,
    
    -- Archive
    is_archived         BOOLEAN DEFAULT FALSE,
    archived_at         TIMESTAMP WITH TIME ZONE,
    
    -- Last activity (for sorting)
    last_message_at     TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Unique channel name per workspace (for public/private only)
    CONSTRAINT uk_channel_name UNIQUE (workspace_id, name) 
);

CREATE INDEX idx_channels_workspace ON channels(workspace_id);
CREATE INDEX idx_channels_type ON channels(workspace_id, channel_type);
CREATE INDEX idx_channels_last_message ON channels(last_message_at DESC);


-- ===========================================
-- SECTION 5: CHANNEL MEMBERSHIP
-- ===========================================

CREATE TABLE channel_members (
    channel_id          UUID NOT NULL REFERENCES channels(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    
    -- Read state
    last_read_message_id    BIGINT,  -- Snowflake ID
    last_read_at            TIMESTAMP WITH TIME ZONE,
    
    -- Mentions
    mention_count       INT DEFAULT 0,
    
    -- Notifications
    is_muted            BOOLEAN DEFAULT FALSE,
    notification_preference VARCHAR(20) DEFAULT 'default',
    
    -- Starred/pinned
    is_starred          BOOLEAN DEFAULT FALSE,
    
    joined_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (channel_id, user_id)
);

CREATE INDEX idx_cm_user ON channel_members(user_id);
CREATE INDEX idx_cm_unread ON channel_members(user_id, mention_count) WHERE mention_count > 0;


-- ===========================================
-- SECTION 6: DIRECT MESSAGE CHANNELS
-- ===========================================

-- For DMs/Group DMs, store participant info
CREATE TABLE dm_channels (
    channel_id          UUID PRIMARY KEY REFERENCES channels(id),
    
    -- Sorted participant IDs for lookup (for 1:1 DMs)
    participant_hash    VARCHAR(128),  -- Hash of sorted user IDs
    participant_ids     UUID[] NOT NULL,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_dm_hash ON dm_channels(participant_hash);
CREATE INDEX idx_dm_participants ON dm_channels USING GIN (participant_ids);


-- ===========================================
-- SECTION 7: PINS AND BOOKMARKS
-- ===========================================

CREATE TABLE pinned_messages (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    channel_id          UUID NOT NULL REFERENCES channels(id),
    message_id          BIGINT NOT NULL,  -- Snowflake ID
    
    pinned_by           UUID NOT NULL REFERENCES users(id),
    pinned_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_pin UNIQUE (channel_id, message_id)
);

CREATE TABLE bookmarks (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    channel_id          UUID NOT NULL REFERENCES channels(id),
    
    title               VARCHAR(100) NOT NULL,
    link_url            TEXT,
    icon_url            TEXT,
    
    created_by          UUID REFERENCES users(id),
    position            INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_bookmarks_channel ON bookmarks(channel_id);
```

---

# Part 4: Cassandra DDL (Messages)

```cql
-- ============================================================
-- MESSAGING SCHEMA: Cassandra/ScyllaDB Messages
-- Keyspace: messaging
-- ============================================================

CREATE KEYSPACE IF NOT EXISTS messaging
WITH REPLICATION = {
    'class': 'NetworkTopologyStrategy',
    'us-east-1': 3,
    'us-west-2': 3,
    'eu-west-1': 3
};

USE messaging;


-- ===========================================
-- MESSAGES BY CHANNEL (Time-Bucketed)
-- ===========================================

-- Discord's approach: bucket by time window
-- Bucket = channel_id + floor(timestamp / bucket_size)
-- Bucket size: 1 week for active channels, 1 month for quiet ones

CREATE TABLE messages_by_channel (
    channel_id      UUID,
    bucket          TEXT,           -- '2024-W01' for week 1 of 2024
    message_id      BIGINT,         -- Snowflake ID (encodes timestamp)
    
    -- Author
    user_id         UUID,
    username        TEXT,
    avatar_url      TEXT,
    
    -- Content
    content         TEXT,
    
    -- Message type
    message_type    TEXT,           -- 'default', 'system', 'thread_reply'
    
    -- Thread
    thread_id       BIGINT,         -- Parent message ID if this is a reply
    
    -- Attachments
    attachments     LIST<FROZEN<MAP<TEXT, TEXT>>>,
    
    -- Embeds (links, rich previews)
    embeds          LIST<FROZEN<MAP<TEXT, TEXT>>>,
    
    -- Mentions
    mention_user_ids    LIST<UUID>,
    mention_roles       LIST<TEXT>,
    mention_everyone    BOOLEAN,
    mention_channel_ids LIST<UUID>,
    
    -- Reactions (denormalized count)
    reaction_counts MAP<TEXT, INT>,  -- {'thumbsup': 5, 'heart': 3}
    
    -- Edit/delete
    edited_at       TIMESTAMP,
    is_deleted      BOOLEAN,
    
    created_at      TIMESTAMP,
    
    PRIMARY KEY ((channel_id, bucket), message_id)
) WITH CLUSTERING ORDER BY (message_id DESC)
  AND gc_grace_seconds = 86400
  AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',
    'compaction_window_size': 7
  };

-- Query: Get recent messages in channel
-- SELECT * FROM messages_by_channel 
-- WHERE channel_id = ? AND bucket = '2024-W04'
-- LIMIT 50;

-- Query: Paginate with cursor (message_id)
-- SELECT * FROM messages_by_channel 
-- WHERE channel_id = ? AND bucket = '2024-W04' AND message_id < ?
-- LIMIT 50;


-- ===========================================
-- THREAD MESSAGES
-- ===========================================

CREATE TABLE messages_by_thread (
    thread_id       BIGINT,         -- Parent message ID
    message_id      BIGINT,         -- Snowflake ID
    
    user_id         UUID,
    username        TEXT,
    avatar_url      TEXT,
    
    content         TEXT,
    attachments     LIST<FROZEN<MAP<TEXT, TEXT>>>,
    
    edited_at       TIMESTAMP,
    is_deleted      BOOLEAN,
    
    created_at      TIMESTAMP,
    
    PRIMARY KEY ((thread_id), message_id)
) WITH CLUSTERING ORDER BY (message_id ASC);


-- ===========================================
-- REACTIONS
-- ===========================================

CREATE TABLE reactions_by_message (
    message_id      BIGINT,
    emoji           TEXT,           -- ':thumbsup:', 'custom:123'
    user_id         UUID,
    
    username        TEXT,
    
    reacted_at      TIMESTAMP,
    
    PRIMARY KEY ((message_id), emoji, user_id)
);

-- Query: Get all reactions for a message
-- SELECT * FROM reactions_by_message WHERE message_id = ?;

-- For getting all users who reacted with specific emoji
CREATE TABLE reaction_users (
    message_id      BIGINT,
    emoji           TEXT,
    user_id         UUID,
    
    PRIMARY KEY ((message_id, emoji), user_id)
);


-- ===========================================
-- USER'S DM MESSAGES (For search)
-- ===========================================

CREATE TABLE messages_by_user (
    user_id         UUID,
    bucket_month    TEXT,           -- '2024-01'
    message_id      BIGINT,
    
    channel_id      UUID,
    channel_name    TEXT,
    
    content         TEXT,
    
    created_at      TIMESTAMP,
    
    PRIMARY KEY ((user_id, bucket_month), message_id)
) WITH CLUSTERING ORDER BY (message_id DESC)
  AND default_time_to_live = 31536000;  -- 1 year for user's messages
```

---

# Part 5: Redis Patterns

```python
# ============================================================
# MESSAGING REDIS PATTERNS
# ============================================================

import redis
import json
import time
from typing import List, Dict, Optional

class PresenceService:
    """
    User online/offline status.
    """
    def __init__(self):
        self.redis = redis.Redis()
        self.PRESENCE_TTL = 60  # Heartbeat every 30s, TTL 60s
    
    def set_online(self, user_id: str, workspace_id: str):
        """Called on WebSocket connect and periodic heartbeat."""
        now = int(time.time())
        
        # User is online
        self.redis.setex(f"online:{user_id}", self.PRESENCE_TTL, now)
        
        # Add to workspace's online set
        self.redis.zadd(f"presence:{workspace_id}", {user_id: now})
        
        # Publish presence change
        self.redis.publish(f"presence_updates:{workspace_id}", json.dumps({
            "user_id": user_id,
            "status": "online"
        }))
    
    def set_offline(self, user_id: str, workspace_id: str):
        """Called on WebSocket disconnect."""
        self.redis.delete(f"online:{user_id}")
        self.redis.zrem(f"presence:{workspace_id}", user_id)
        
        self.redis.publish(f"presence_updates:{workspace_id}", json.dumps({
            "user_id": user_id,
            "status": "offline"
        }))
    
    def is_online(self, user_id: str) -> bool:
        return self.redis.exists(f"online:{user_id}") == 1
    
    def get_online_users(self, workspace_id: str) -> List[str]:
        """Get all online users in workspace."""
        # Prune stale entries (TTL fallback)
        cutoff = int(time.time()) - self.PRESENCE_TTL
        self.redis.zremrangebyscore(f"presence:{workspace_id}", 0, cutoff)
        
        return [u.decode() for u in self.redis.zrange(f"presence:{workspace_id}", 0, -1)]


class TypingIndicator:
    """
    "User is typing..." indicators.
    """
    def __init__(self):
        self.redis = redis.Redis()
        self.TYPING_TTL = 5  # Typing expires after 5s
    
    def set_typing(self, channel_id: str, user_id: str, username: str):
        """Called when user starts typing."""
        key = f"typing:{channel_id}"
        self.redis.hset(key, user_id, json.dumps({
            "username": username,
            "started_at": int(time.time())
        }))
        self.redis.expire(key, self.TYPING_TTL)
        
        # Publish typing event
        self.redis.publish(f"channel_events:{channel_id}", json.dumps({
            "event": "typing",
            "user_id": user_id,
            "username": username
        }))
    
    def clear_typing(self, channel_id: str, user_id: str):
        """Called when user stops typing or sends message."""
        self.redis.hdel(f"typing:{channel_id}", user_id)
    
    def get_typing_users(self, channel_id: str) -> List[Dict]:
        """Get users currently typing."""
        key = f"typing:{channel_id}"
        now = int(time.time())
        typing = []
        
        for user_id, data in self.redis.hgetall(key).items():
            info = json.loads(data)
            if now - info["started_at"] < self.TYPING_TTL:
                typing.append({
                    "user_id": user_id.decode(),
                    "username": info["username"]
                })
        
        return typing


class UnreadCounter:
    """
    Unread message counts per user per channel.
    """
    def __init__(self):
        self.redis = redis.Redis()
    
    def increment_unread(self, channel_id: str, user_ids: List[str], 
                         is_mention: bool = False):
        """Called when new message is sent to channel."""
        for user_id in user_ids:
            key = f"unread:{user_id}:{channel_id}"
            self.redis.hincrby(key, "count", 1)
            if is_mention:
                self.redis.hincrby(key, "mentions", 1)
    
    def mark_read(self, user_id: str, channel_id: str, message_id: int):
        """Called when user reads channel."""
        key = f"unread:{user_id}:{channel_id}"
        self.redis.delete(key)
        
        # Store last read message ID
        self.redis.set(f"last_read:{user_id}:{channel_id}", message_id)
    
    def get_unread(self, user_id: str, channel_id: str) -> Dict:
        """Get unread count for channel."""
        key = f"unread:{user_id}:{channel_id}"
        data = self.redis.hgetall(key)
        return {
            "count": int(data.get(b"count", 0)),
            "mentions": int(data.get(b"mentions", 0))
        }
    
    def get_all_unread(self, user_id: str) -> Dict[str, Dict]:
        """Get unread counts for all user's channels."""
        pattern = f"unread:{user_id}:*"
        result = {}
        
        for key in self.redis.scan_iter(pattern):
            channel_id = key.decode().split(":")[-1]
            result[channel_id] = self.get_unread(user_id, channel_id)
        
        return result
```

---

# Part 6: Message Fanout (WebSocket)

```
┌─────────────────────────────────────────────────────────────────┐
│                    MESSAGE DELIVERY FLOW                         │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  User sends      │
│  message         │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌──────────────────┐
│  API Server      │────►│  Kafka           │
│                  │     │  messages topic  │
│  1. Validate     │     └────────┬─────────┘
│  2. Generate ID  │              │
│  3. Publish      │              ▼
└──────────────────┘     ┌──────────────────┐
                         │  Message Worker  │
                         │                  │
                         │  1. Write to     │
                         │     Cassandra    │
                         │  2. Index in ES  │
                         │  3. Update unread│
                         └────────┬─────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │  Redis Pub/Sub   │
                         │                  │
                         │  channel_events: │
                         │  {channel_id}    │
                         └────────┬─────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
     ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
     │  WS Gateway  │    │  WS Gateway  │    │  WS Gateway  │
     │  (Node 1)    │    │  (Node 2)    │    │  (Node 3)    │
     │              │    │              │    │              │
     │  Users A, B  │    │  Users C, D  │    │  Users E, F  │
     └──────────────┘    └──────────────┘    └──────────────┘
```

---

# Part 7: Snowflake ID for Messages

```python
# Same Snowflake pattern as Twitter (see twitter-schema-design-guide.md)
# Message IDs are time-sortable for efficient range queries

"""
Benefits for messaging:
1. No need for created_at index - ID encodes time
2. Cursor pagination: WHERE message_id < :cursor
3. Distributed generation - no coordination
4. 64-bit fits in Cassandra BIGINT
"""

def get_bucket_from_message_id(message_id: int) -> str:
    """
    Extract time bucket from Snowflake ID for Cassandra partition.
    """
    EPOCH = 1288834974657
    timestamp_ms = (message_id >> 22) + EPOCH
    
    # Convert to week bucket
    from datetime import datetime
    dt = datetime.fromtimestamp(timestamp_ms / 1000)
    year, week, _ = dt.isocalendar()
    return f"{year}-W{week:02d}"
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Messages time-bucketed | Partition by channel + week |
| 2 | Snowflake IDs | Time-sortable, cursor pagination |
| 3 | Presence in Redis | TTL-based with heartbeat |
| 4 | Typing indicators | 5s TTL, pub/sub |
| 5 | Unread counts maintained | Increment on send, reset on read |
| 6 | Reactions denormalized | reaction_counts on message |
| 7 | Thread replies separated | messages_by_thread table |
| 8 | DM channel lookup | participant_hash for 1:1 |

---

# Part 8: DynamoDB Single-Table Design

```
============================================================
MESSAGING: DynamoDB Single-Table Design
For workspaces, channels, users, and presence (Metadata)
Messages stored in separate table or time-series DB
============================================================

TABLE: messaging_meta
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (Reverse lookup, workspace scan)

============================================================
ENTITY PATTERNS
============================================================

WORKSPACE
  PK: WS#{workspace_id}
  SK: INFO
  
  Attributes: name, domain, plan

CHANNEL
  PK: WS#{workspace_id}
  SK: CHAN#{channel_id}
  GSI1PK: CHAN#{channel_id}
  GSI1SK: INFO
  
  Attributes: name, topic, type (public/private)

USER (in Workspace)
  PK: WS#{workspace_id}
  SK: USER#{user_id}
  GSI1PK: USER#{user_id}
  GSI1SK: WS#{workspace_id}
  
  Attributes: role, status_text, display_name

MEMBERSHIP (Channel)
  PK: CHAN#{channel_id}
  SK: MEM#{user_id}
  GSI1PK: USER#{user_id}
  GSI1SK: CHAN#{channel_id}
  
  Attributes: last_read_msg_id, notifications

DIRECT MESSAGE
  PK: WS#{workspace_id}
  SK: DM#{participant_hash}
  
  Attributes: channel_id, participant_ids

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get workspace details
   Table: PK=WS#{workspace_id}, SK=INFO

2. List all channels in workspace
   Table: PK=WS#{workspace_id}, SK begins_with "CHAN#"

3. Get user profile in workspace
   Table: PK=WS#{workspace_id}, SK=USER#{user_id}

4. Get all workspaces a user belongs to
   GSI1: PK=USER#{user_id}, SK begins_with "WS#"

5. Get all members of a channel
   Table: PK=CHAN#{channel_id}, SK begins_with "MEM#"

6. Get all channels a user is in
   GSI1: PK=USER#{user_id}, SK begins_with "CHAN#"

7. Find existing DM between users A and B
   Table: PK=WS#{workspace_id}, SK=DM#{hash(sort(A,B))}
```

---

# Part 9: Query Examples with EXPLAIN

```sql
-- ============================================================
-- MESSAGING QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Channel List for User (Sidebar)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    c.id, c.name, c.channel_type, 
    c.last_message_at,
    cm.mention_count, cm.is_muted
FROM channel_members cm
JOIN channels c ON c.id = cm.channel_id
WHERE cm.user_id = $1
  AND c.workspace_id = $2
  AND c.is_archived = FALSE
ORDER BY 
    cm.is_starred DESC, 
    c.channel_type ASC, 
    c.name ASC;

-- Expected: Index scan on idx_cm_user, ~5ms


-- ===========================================
-- QUERY 2: Message Search (Full Text)
-- ===========================================

-- NOTE: Usually Elasticsearch, but PostgreSQL fallback:
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    m.message_id, m.content, m.created_at,
    u.display_name, c.name as channel_name
FROM messages_search_idx m -- Assuming a specialized table
JOIN users u ON u.id = m.user_id
JOIN channels c ON c.id = m.channel_id
WHERE m.workspace_id = $1
  AND to_tsvector('english', m.content) @@ plainto_tsquery('english', $2)
LIMIT 20;

-- Expected: Heavy scan if not inverted index.


-- ===========================================
-- QUERY 3: Workspace Analytics (Members)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    count(*) as total_members,
    count(*) FILTER (WHERE role = 'admin') as admins,
    count(*) FILTER (WHERE status = 'active') as active_users,
    date_trunc('month', joined_at) as join_month
FROM workspace_members
WHERE workspace_id = $1
GROUP BY join_month
ORDER BY join_month DESC;

-- Expected: Index scan on idx_wm_workspace, ~15ms


-- ===========================================
-- QUERY 4: Unreads Calculation (PostgreSQL Backup)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    c.id,
    COUNT(m.id) as unread_count
FROM channel_members cm
JOIN channels c ON c.id = cm.channel_id
JOIN messages m ON m.channel_id = c.id
WHERE cm.user_id = $1
  AND m.id > cm.last_read_message_id
GROUP BY c.id;

-- NOTE: Very expensive Query. Do not use in production.
-- Use Redis counters instead (Law #4).
```

---

# Part 10: Capacity Planning

```
============================================================
MESSAGING CAPACITY PLANNING
============================================================

ASSUMPTIONS (Slack Scale):
- 10M DAU
- 500M Messages/Day
- Avg message size: 100 bytes (text), 50KB (embeds/metadata)
- 10% messages have attachments

============================================================
STORAGE ESTIMATES (1 Year)
============================================================

MESSAGES (Cassandra/Scylla)
  Rows: 500M * 365 = 182.5 Billion
  Row Size: ~300 bytes (avg)
  Total: ~55 TB/year
  Replica (3x): ~165 TB/year

ATTACHMENTS (S3)
  50M/day * 1MB avg = 50 TB/day !
  Total: ~18 PB/year
  Retention policies critical.

POSTGRES METADATA
  Users: 10M * 1KB = 10 GB
  Memberships: 10M users * 50 channels = 500M rows
  Total: ~100 GB (Fits in memory)

REDIS STATE
  Presence: 10M users * 100 bytes = 1 GB
  Unreads: 500M memberships * 20 bytes = 10 GB
  Total: ~32 GB RAM Cluster

============================================================
THROUGHPUT
============================================================

INGESTION:
  Avg: 6K msg/sec
  Peak: 100K msg/sec (9am login spike)

FANOUT (WebSocket):
  Avg channel size: 10 users -> 60K events/sec
  Large channel (All Hands): 50K users -> 1 msg = 50K events!
  
  Gateway Strategy:
  - Shard connections by UserID.
  - Broadcast "Channel X has message" to all Gateways.
  - Gateway filters "Do I have users for Channel X?"

============================================================
SCALING STRATEGY
============================================================

1. PARTITIONING (Cassandra)
   - Partition Key: (channel_id, timeframe_bucket)
   - Prevents "Super Partitions" for busy channels.
   - Bucket size: Weekly or Monthly.

2. SEARCH
   - Elasticsearch cluster separate from primary DB.
   - Indexing lag (1-5s) acceptable.
   - Shard by Workspace ID or Time.

3. COLD STORAGE
   - Move messages > 2 years to S3/Parquet.
   - "Search Archive" feature checks S3 (slower).
```

---

# Part 11: Anti-Patterns to Avoid

```
============================================================
MESSAGING ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Fetching All Channel Members for Every Message
-----------------------------------------
WRONG:
  On message send -> Select * from members where channel_id = ?
  -- For #general (50K users), this kills the DB.
  
RIGHT:
  -- Publish to Kafka topic `channel-events`.
  -- WebSocket Gateway handles subscription map in memory.


❌ ANTI-PATTERN 2: Storing Messages in PostgreSQL
-----------------------------------------
WRONG:
  INSERT INTO messages (content, ...)
  -- 182 Billions rows/year. Postgres VACUUM will die.
  -- Index maintenance too slow.
  
RIGHT:
  -- LSM-Tree DB (Cassandra/Scylla/RocksDB).
  -- Write-optimized, append-only.


❌ ANTI-PATTERN 3: Synchronous Typing Indicators
-----------------------------------------
WRONG:
  POST /typing -> DB Update -> Notify
  -- 1000 users typing = 1000 DB writes/sec.
  
RIGHT:
  -- Ephemeral Redis Key (TTL 5s).
  -- No DB persistence. Client-side throttle (send 1 event/sec max).


❌ ANTI-PATTERN 4: Counting Unreads on Read
-----------------------------------------
WRONG:
  SELECT COUNT(*) FROM messages WHERE id > last_read_id
  -- O(N) scan. 
  
RIGHT:
  -- Increment counter on Write. O(1) read.
  -- Redis: HINCRBY unread:{user}:{chan} 1


❌ ANTI-PATTERN 5: Polling for Messages
-----------------------------------------
WRONG:
  Client calls GET /messages every 3s.
  -- Battery drain + Server load.
  
RIGHT:
  -- WebSocket / Long Polling / Server-Sent Events (SSE).


❌ ANTI-PATTERN 6: XML/JSON in Message Content
-----------------------------------------
WRONG:
  content: "<b>Hello</b>"
  -- XSS risk, hard to parse mobile/web differently.
  
RIGHT:
  -- Structured JSON Blocks (Slack Block Kit).
  -- `[{type: "text", text: "Hello", style: "bold"}]`


❌ ANTI-PATTERN 7: Global IDs for Everything
-----------------------------------------
WRONG:
  channel_id SERIAL
  -- Conflict if Merging Workspaces.
  
RIGHT:
  -- UUIDs or Namespaced IDs (workspace_id + local_id).


❌ ANTI-PATTERN 8: Hard Delete Messages
-----------------------------------------
WRONG:
  DELETE FROM messages WHERE id = ?
  -- Tombstones pile up in Cassandra.
  
RIGHT:
  -- Write 'is_deleted = true' column or 'tombstone' column.
  -- Filter on read.


❌ ANTI-PATTERN 9: Storing Presence in DB
-----------------------------------------
WRONG:
  UPDATE users SET is_online = true
  -- The most frequent write in the system!
  
RIGHT:
  -- Redis Only.
  -- "Last Seen" persisted to DB only on session end.


❌ ANTI-PATTERN 10: Mixing Control and Data Plane
-----------------------------------------
WRONG:
  WebSocket handles auth, billing, message save.
  
RIGHT:
  -- WebSocket = Pipe (Delivery only).
  -- API = Logic (Save, Validate, Auth).
```

---

# Part 12: CDC & Disaster Recovery

```
============================================================
MESSAGING CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ Cassandra   │────►│  CDC Agent  │────►│  Kafka          │
│ (Messages)  │     │ (ScyllaCDC) │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │Elasticsearch│   │ Push Notif│   │ Analytics │  │ Audit Log│
  │ (Search)    │   │ (Mobile)  │   │ (Usage)   │  │ (Compliance)│
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- chat.messages.new       (Trigger push, search index)
- chat.channels.created
- chat.users.status       (Presence fanout)
- chat.reactions.added

============================================================
DISASTER RECOVERY
============================================================

RPO: < 1 second (Messages)
RTO: < 10 minutes

STRATEGY:
1. Cassandra Multi-Region
   - Async replication to DR region.
   - Tunable consistency (LOCAL_QUORUM for speed, EACH_QUORUM for safety).

2. Postgres (Metadata)
   - Standard Async Replication.

3. "Dark Mode" (Degraded State)
   - If Search is down -> Disable search bar.
   - If Presence is down -> Show everyone as "Away".
   - If History is down -> Show only real-time messages (WS).

4. Backups
   - Cassandra Snapshots to S3 (Daily).
   - Postgres WAL Archives (Continuous).
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- MESSAGING: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / MODERATION LOG
-- ===========================================

CREATE TABLE moderation_log (
    id                  BIGSERIAL PRIMARY KEY,
    workspace_id        UUID NOT NULL,
    actor_id            UUID NOT NULL,
    action_type         VARCHAR(50) NOT NULL,  -- 'delete_message', 'ban_user', 'archive_channel'
    target_type         VARCHAR(50) NOT NULL,
    target_id           UUID NOT NULL,
    reason              TEXT,
    old_state           JSONB,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- B. FILE ATTACHMENTS
-- ===========================================

CREATE TABLE file_uploads (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id        UUID NOT NULL,
    channel_id          UUID,
    message_id          BIGINT,
    uploader_id         UUID NOT NULL,
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    thumbnail_key       VARCHAR(500),
    preview_key         VARCHAR(500),  -- For PDFs, docs
    is_external         BOOLEAN DEFAULT FALSE,  -- Google Drive, Dropbox link
    external_url        VARCHAR(500),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_file_channel ON file_uploads(channel_id);
CREATE INDEX idx_file_workspace ON file_uploads(workspace_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    workspace_id        UUID,
    channel             VARCHAR(20) NOT NULL,  -- 'push', 'email', 'desktop'
    device_token        VARCHAR(255),
    notification_type   VARCHAR(100) NOT NULL,  -- 'mention', 'dm', 'reaction'
    title               VARCHAR(100),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS / INTEGRATIONS
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id        UUID NOT NULL,
    channel_id          UUID,  -- Channel-specific or workspace-wide
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['message.created', 'user.joined']
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE installed_apps (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id        UUID NOT NULL,
    app_id              UUID NOT NULL,  -- From app directory
    installed_by_id     UUID NOT NULL,
    bot_user_id         UUID,  -- Bot account for app
    scopes              TEXT[],
    access_token_enc    BYTEA,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- E. API KEYS / BOT TOKENS
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id        UUID NOT NULL,
    key_type            VARCHAR(20) NOT NULL,  -- 'bot', 'user', 'service'
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100),
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 100,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- F. SSO (SAML/OIDC)
-- ===========================================

CREATE TABLE sso_providers (
    id                  SERIAL PRIMARY KEY,
    workspace_id        UUID NOT NULL,
    provider_type       VARCHAR(50) NOT NULL,  -- 'okta', 'azure_ad', 'google'
    name                VARCHAR(100) NOT NULL,
    client_id           VARCHAR(255) NOT NULL,
    client_secret_enc   BYTEA NOT NULL,
    issuer_url          VARCHAR(500),
    saml_metadata_url   VARCHAR(500),
    enforce_sso         BOOLEAN DEFAULT FALSE,  -- Require SSO only
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE user_sso_links (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    provider_id         INT NOT NULL REFERENCES sso_providers(id),
    external_id         VARCHAR(255) NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uk_user_provider UNIQUE (user_id, provider_id)
);


-- ===========================================
-- G. USER SESSIONS
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_type         VARCHAR(50),  -- 'desktop', 'mobile', 'browser'
    client_version      VARCHAR(20),
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
    allowed_workspace_ids UUID[],
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
MESSAGING: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. WEBSOCKET GATEWAY SCALING (THE C10M PROBLEM)
============================================================

THE CHALLENGE:
System needs to hold 10M open TCP connections.
Stateful: We must know which "Gateway Node" holds User A's connection.

ARCHITECTURE:
- **Gateway Layer (Golang/Erlang)**: Holds WebSockets. Statelessish.
- **Session Registry (Redis)**: Key `user:123` -> Value `gateway_node_ip:10.0.0.5`.
- **PubSub (Redis/NATS)**: Dispatches messages to standard topics.

SCALING STRATEGY:
- Ephemeral Ports constraint (65k ports per IP).
- Solution: Multiple IP aliases per Gateway Node or multiple load balancers.
- "Thundering Herd": If Gateway crash, 100k clients reconnect. Add Jitter (0-30s) to reconnect logic.

============================================================
2. MESSAGE FANOUT (GROUP CHAT INTERNALS)
============================================================

THE CHALLENGE:
User A sends message to Group G (200k members).
Naive Loop: `for member in group: send(msg)` -> Latency spike.

OPTIMIZATION:
1. **Online-Only Fanout**: Check Session Registry. Only publish to Online members.
2. **Push Notifications (Async)**: For offline members, queue APNS/FCM jobs.
3. **Inbox Deltas**: Clients fetch "missed messages" since `last_msg_id` upon reconnect.

DATABASE WRITE (Cassandra/Scylla):
- Write ONCE to `messages_by_channel`.
- Write fanout POINTERS to `user_inbox` (only if using inbox model, Slack uses Channel model).

============================================================
3. SEARCH INDEXING (HISTORY)
============================================================

THE BOTTLENECK:
"Search in conversation" is high latency.
Full-text search on Cassandra is bad.

SOLUTION: REVERSE INDEX (Elasticsearch/Bleve)
- CDC (Kafka) -> Indexer -> Elastic.
- Index Routing: Route by `workspace_id` or `channel_id` (reduce scatter-gather).
- Tokenization: Edge-n-grams for autocomplete.

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Message Delivery Latency (p99)│ < 200ms │ > 1s = PAGE     │
│  (Send -> ACK)                                            │
├─────────────────────────────────────────────────────────────┤
│  Gateway Connection Count     │ < 100k/node | > 150k = WARN|
│  Push Notification Delivery   │ < 10s   │ > 30s = WARN    │
│  WebSocket Drop Rate          │ < 1%    │ > 5% = PAGE     │
└─────────────────────────────────────────────────────────────┘

METRICS:
- `messages_in` vs `messages_out` (Fanout ratio).
- `redis_memory_usage` (Session registry size).
- `connected_users` by region.

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: ETCD/ZOOKEEPER SPLIT BRAIN
Symptom: Cluster discovery fails.
Mitigation:
- Static Fallback: Hardcoded list of seed nodes.
- Client-side list: Client caches last known good IPs.

SCENARIO 2: MESSAGE STORM (Viral Event)
Symptom: 1000 msg/sec in one channel.
Mitigation:
- Rate Limiting: "Slow Mode" (User can msg once per 10s).
- Client Collapsing: UI updates once per second, batching incoming messages.

SCENARIO 3: HISTORY GAP
Symptom: Mobile client was offline, missed 50 msgs.
Mitigation:
- "Cursor-based Pagination": Client asks `get_messages(after=msg_id_100)`.
- Server fetches from ScyllaDB.

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

MEDIA STORAGE:
- Images/Videos are 80% of cost.
- Deduplication: Check SHA-256 before upload. If exists, just link reference.
- Auto-Expiry: Delete media > 1 year old (Slack Free Tier logic).

COMPUTE:
- Gateway nodes are memory-bound (TCP buffers). Use memory-optimized instances (r6g).
- Protobuf vs JSON: Switch to Protobuf saves 40% bandwidth/CPU.
```

---

## 🔗 Related Documents

- [Twitter Schema](./twitter-schema-design-guide.md) — Snowflake IDs, fanout
- [Netflix Schema](./netflix-schema-design-guide.md) — Cassandra patterns
- [Consistent Hashing](../system-design-notes/consistent-hashing-guide.md) — WebSocket gateway distribution
- [Healthcare Schema](./healthcare-schema-design-guide.md) — Audit patterns
