# Multiplayer Gaming: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Players, Matches, Leaderboards, Matchmaking, Inventory — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Computing leaderboard ranks at read time. A billion-player game cannot `ORDER BY score`. Use **Redis sorted sets** with periodic snapshots.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Supercell Server Architecture](https://supercell.com/en/blogs/) | Clash of Clans |
| [Riot Games Data Infrastructure](https://technology.riotgames.com/) | League of Legends |
| [Elo Rating System](https://en.wikipedia.org/wiki/Elo_rating_system) | Matchmaking |

---

## 🎯 The Principal Laws of Gaming Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Leaderboards Are Pre-computed** | Can't sort millions at read | Redis ZADD + periodic snapshots |
| **Law 2: Match State Is Ephemeral** | In-progress matches in memory | Redis/memory, not PostgreSQL |
| **Law 3: MMR/Elo for Matchmaking** | Fair matches = fun | Rating system for pairing |
| **Law 4: Inventory Is Valuable** | Virtual items have value | Audit every transaction |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get player profile | 50M/s | < 30ms | Cache + PostgreSQL |
| 2 | Get leaderboard (top 100) | 10M/s | < 20ms | Redis ZSET |
| 3 | Get my rank | 10M/s | < 20ms | Redis ZRANK |
| 4 | Find match | 1M/s | < 5s | Redis + matchmaker |
| 5 | Update match result | 500K/s | < 200ms | PostgreSQL |
| 6 | Get match history | 5M/s | < 100ms | Cassandra |
| 7 | Get inventory | 10M/s | < 50ms | Cache + PostgreSQL |
| 8 | Purchase item | 100K/s | < 500ms | PostgreSQL (ACID) |
| 9 | Grant loot/reward | 1M/s | < 200ms | PostgreSQL |
| 10 | Get friends list | 5M/s | < 50ms | Redis + PostgreSQL |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    GAMING DATA ARCHITECTURE                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                               │
│  ✓ Player accounts    ✓ Inventory   ✓ Match history             │
│                                                                  │
│  • players, player_stats                                         │
│  • items, player_inventory                                       │
│  • matches, match_participants                                   │
│  • transactions (purchases, rewards)                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Leaderboards    ✓ Matchmaking   ✓ Online status   ✓ Sessions │
│                                                                  │
│  • leaderboard:global (ZSET)                                     │
│  • leaderboard:season:{season_id} (ZSET)                         │
│  • matchmaking:queue:{mode} (ZSET by MMR)                        │
│  • online:{player_id}                                            │
│  • match:{match_id} (live state)                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Game Servers                             │
│  ✓ Real-time match    ✓ In-memory state   ✓ Authoritative       │
│                                                                  │
│  • Active match simulation                                       │
│  • Player positions/actions                                      │
│  • Anti-cheat validation                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- GAMING SCHEMA: PostgreSQL Production DDL
-- Version: Multiplayer game with leaderboards and inventory
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ===========================================
-- SECTION 1: PLAYERS
-- ===========================================

CREATE TABLE players (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identity
    username            VARCHAR(30) NOT NULL UNIQUE,
    display_name        VARCHAR(50),
    email               VARCHAR(255) UNIQUE,
    
    -- Auth
    password_hash       TEXT,
    is_guest            BOOLEAN DEFAULT FALSE,
    
    -- Platform links
    steam_id            VARCHAR(50) UNIQUE,
    xbox_id             VARCHAR(50) UNIQUE,
    playstation_id      VARCHAR(50) UNIQUE,
    discord_id          VARCHAR(50) UNIQUE,
    
    -- Profile
    avatar_url          TEXT,
    country             VARCHAR(2),
    
    -- Status
    is_banned           BOOLEAN DEFAULT FALSE,
    banned_until        TIMESTAMP WITH TIME ZONE,
    ban_reason          TEXT,
    
    -- Premium
    is_premium          BOOLEAN DEFAULT FALSE,
    premium_until       TIMESTAMP WITH TIME ZONE,
    
    -- Soft currency
    coins               BIGINT DEFAULT 0,
    gems                BIGINT DEFAULT 0,  -- Premium currency
    
    -- Experience
    level               INT DEFAULT 1,
    xp                  BIGINT DEFAULT 0,
    xp_to_next_level    BIGINT DEFAULT 100,
    
    -- Settings
    settings            JSONB DEFAULT '{}',
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login_at       TIMESTAMP WITH TIME ZONE,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_players_username ON players(username);
CREATE INDEX idx_players_email ON players(email) WHERE email IS NOT NULL;
CREATE INDEX idx_players_level ON players(level DESC);


-- ===========================================
-- SECTION 2: PLAYER STATS (Per Game Mode)
-- ===========================================

CREATE TABLE player_stats (
    id                  BIGSERIAL PRIMARY KEY,
    player_id           UUID NOT NULL REFERENCES players(id),
    game_mode           VARCHAR(50) NOT NULL,  -- 'ranked', 'casual', 'deathmatch'
    season_id           INT,  -- NULL for all-time
    
    -- Matches
    matches_played      INT DEFAULT 0,
    wins                INT DEFAULT 0,
    losses              INT DEFAULT 0,
    draws               INT DEFAULT 0,
    
    -- Win rate
    win_rate            DECIMAL(5,4) GENERATED ALWAYS AS (
        CASE WHEN matches_played > 0 
             THEN wins::DECIMAL / matches_played 
             ELSE 0 END
    ) STORED,
    
    -- Rating (Elo/MMR)
    rating              INT DEFAULT 1000,
    peak_rating         INT DEFAULT 1000,
    
    -- Game-specific stats
    kills               INT DEFAULT 0,
    deaths              INT DEFAULT 0,
    assists             INT DEFAULT 0,
    kda                 DECIMAL(6,2) GENERATED ALWAYS AS (
        CASE WHEN deaths > 0 
             THEN (kills + assists * 0.5) / deaths 
             ELSE kills + assists * 0.5 END
    ) STORED,
    
    -- Time
    time_played_sec     BIGINT DEFAULT 0,
    
    -- Streaks
    current_win_streak  INT DEFAULT 0,
    best_win_streak     INT DEFAULT 0,
    
    -- Custom stats (game-specific)
    custom_stats        JSONB DEFAULT '{}',
    
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_player_stats UNIQUE (player_id, game_mode, season_id)
);

CREATE INDEX idx_stats_player ON player_stats(player_id);
CREATE INDEX idx_stats_rating ON player_stats(game_mode, rating DESC);
CREATE INDEX idx_stats_season ON player_stats(season_id);


-- ===========================================
-- SECTION 3: SEASONS
-- ===========================================

CREATE TABLE seasons (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    
    start_date          TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date            TIMESTAMP WITH TIME ZONE NOT NULL,
    
    -- Rewards
    rewards             JSONB,  -- [{tier: 'gold', item_id: '...'}, ...]
    
    is_active           BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_seasons_active ON seasons(is_active) WHERE is_active = TRUE;


-- ===========================================
-- SECTION 4: MATCHES
-- ===========================================

CREATE TYPE match_status AS ENUM (
    'pending', 'in_progress', 'completed', 'cancelled', 'abandoned'
);

CREATE TABLE matches (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Game mode
    game_mode           VARCHAR(50) NOT NULL,
    season_id           INT REFERENCES seasons(id),
    
    -- Map/Arena
    map_id              VARCHAR(50),
    
    -- Server
    server_region       VARCHAR(20),
    server_id           VARCHAR(50),
    
    -- Status
    status              match_status DEFAULT 'pending',
    
    -- Timing
    scheduled_at        TIMESTAMP WITH TIME ZONE,
    started_at          TIMESTAMP WITH TIME ZONE,
    ended_at            TIMESTAMP WITH TIME ZONE,
    duration_sec        INT,
    
    -- Result
    winner_team         INT,  -- 1, 2, or NULL for draw
    
    -- Match data (replay, events)
    replay_url          TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_matches_mode ON matches(game_mode, created_at DESC);
CREATE INDEX idx_matches_status ON matches(status);
CREATE INDEX idx_matches_season ON matches(season_id);


-- Match participants
CREATE TABLE match_participants (
    id                  BIGSERIAL PRIMARY KEY,
    match_id            UUID NOT NULL REFERENCES matches(id),
    player_id           UUID NOT NULL REFERENCES players(id),
    
    -- Team
    team                INT NOT NULL,  -- 1 or 2
    
    -- Character/Hero/Class selection
    character_id        VARCHAR(50),
    loadout             JSONB,
    
    -- Performance
    kills               INT DEFAULT 0,
    deaths              INT DEFAULT 0,
    assists             INT DEFAULT 0,
    score               INT DEFAULT 0,
    
    -- Custom stats
    stats               JSONB DEFAULT '{}',
    
    -- Result for this player
    result              VARCHAR(20),  -- 'win', 'loss', 'draw', 'abandoned'
    
    -- Rating change
    rating_before       INT,
    rating_after        INT,
    rating_change       INT GENERATED ALWAYS AS (rating_after - rating_before) STORED,
    
    -- Rewards earned
    xp_earned           INT DEFAULT 0,
    coins_earned        INT DEFAULT 0,
    
    -- Performance grade
    grade               VARCHAR(5),  -- 'S+', 'S', 'A', 'B', 'C', 'D'
    mvp                 BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_match_player UNIQUE (match_id, player_id)
);

CREATE INDEX idx_participants_match ON match_participants(match_id);
CREATE INDEX idx_participants_player ON match_participants(player_id);


-- ===========================================
-- SECTION 5: INVENTORY
-- ===========================================

CREATE TYPE item_type AS ENUM (
    'skin', 'weapon', 'character', 'emote', 'consumable', 
    'boost', 'loot_box', 'currency', 'battle_pass'
);

CREATE TYPE item_rarity AS ENUM (
    'common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic'
);

CREATE TABLE items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Basic info
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    
    item_type           item_type NOT NULL,
    rarity              item_rarity NOT NULL,
    
    -- Pricing
    price_coins         INT,
    price_gems          INT,  -- Premium currency
    price_usd           INT,  -- Direct purchase (in cents)
    
    -- Image
    icon_url            TEXT,
    model_url           TEXT,
    
    -- Game data
    stats               JSONB,  -- Weapon stats, etc.
    
    -- Availability
    is_purchasable      BOOLEAN DEFAULT TRUE,
    is_tradeable        BOOLEAN DEFAULT TRUE,
    is_limited          BOOLEAN DEFAULT FALSE,
    available_until     TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_items_type ON items(item_type);
CREATE INDEX idx_items_rarity ON items(rarity);


CREATE TABLE player_inventory (
    id                  BIGSERIAL PRIMARY KEY,
    player_id           UUID NOT NULL REFERENCES players(id),
    item_id             UUID NOT NULL REFERENCES items(id),
    
    -- Quantity (for consumables/currency)
    quantity            INT DEFAULT 1,
    
    -- Acquisition
    source              VARCHAR(50),  -- 'purchase', 'loot_box', 'reward', 'trade', 'gift'
    acquired_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Customization (for skins)
    customization       JSONB,
    
    -- Equipped
    is_equipped         BOOLEAN DEFAULT FALSE,
    equipped_slot       VARCHAR(50),
    
    -- Favorited
    is_favorite         BOOLEAN DEFAULT FALSE,
    
    CONSTRAINT uk_player_item UNIQUE (player_id, item_id)
);

CREATE INDEX idx_inventory_player ON player_inventory(player_id);
CREATE INDEX idx_inventory_equipped ON player_inventory(player_id, is_equipped) 
    WHERE is_equipped = TRUE;


-- ===========================================
-- SECTION 6: TRANSACTIONS (Economy)
-- ===========================================

CREATE TYPE transaction_type AS ENUM (
    'purchase', 'reward', 'trade_in', 'trade_out', 
    'gift_sent', 'gift_received', 'refund', 'admin_grant'
);

CREATE TABLE transactions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id           UUID NOT NULL REFERENCES players(id),
    
    transaction_type    transaction_type NOT NULL,
    
    -- Currency changes
    coins_change        BIGINT DEFAULT 0,
    gems_change         BIGINT DEFAULT 0,
    
    -- Item changes
    item_id             UUID REFERENCES items(id),
    item_quantity       INT DEFAULT 0,
    
    -- For purchases
    price_paid          INT,  -- In cents
    payment_provider    VARCHAR(50),  -- 'stripe', 'apple', 'google'
    payment_ref         VARCHAR(100),
    
    -- Balance after
    coins_after         BIGINT,
    gems_after          BIGINT,
    
    -- Context
    source              VARCHAR(100),  -- 'shop', 'battle_pass', 'loot_box'
    
    -- Idempotency
    idempotency_key     VARCHAR(100) UNIQUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_txn_player ON transactions(player_id, created_at DESC);
CREATE INDEX idx_txn_type ON transactions(transaction_type);


-- ===========================================
-- SECTION 7: FRIENDS
-- ===========================================

CREATE TYPE friend_status AS ENUM ('pending', 'accepted', 'blocked');

CREATE TABLE friendships (
    id                  BIGSERIAL PRIMARY KEY,
    player_id           UUID NOT NULL REFERENCES players(id),
    friend_id           UUID NOT NULL REFERENCES players(id),
    
    status              friend_status DEFAULT 'pending',
    
    -- Who initiated
    initiated_by        UUID NOT NULL REFERENCES players(id),
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    accepted_at         TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT uk_friendship UNIQUE (player_id, friend_id),
    CONSTRAINT ck_no_self_friend CHECK (player_id != friend_id)
);

CREATE INDEX idx_friends_player ON friendships(player_id, status);
CREATE INDEX idx_friends_pending ON friendships(friend_id, status) 
    WHERE status = 'pending';


-- ===========================================
-- SECTION 8: GUILDS/CLANS
-- ===========================================

CREATE TABLE guilds (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    name                VARCHAR(50) NOT NULL UNIQUE,
    tag                 VARCHAR(6) NOT NULL UNIQUE,  -- Clan tag
    description         TEXT,
    
    -- Founder
    founder_id          UUID NOT NULL REFERENCES players(id),
    
    -- Icons
    emblem_url          TEXT,
    
    -- Stats
    member_count        INT DEFAULT 1,
    level               INT DEFAULT 1,
    xp                  BIGINT DEFAULT 0,
    
    -- Trophies/ranking
    trophy_count        INT DEFAULT 0,
    
    -- Settings
    join_type           VARCHAR(20) DEFAULT 'invite_only',  -- 'open', 'invite_only', 'closed'
    min_level           INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_guilds_name ON guilds(name);
CREATE INDEX idx_guilds_trophies ON guilds(trophy_count DESC);

CREATE TABLE guild_members (
    guild_id            UUID NOT NULL REFERENCES guilds(id),
    player_id           UUID NOT NULL REFERENCES players(id),
    
    role                VARCHAR(20) DEFAULT 'member',  -- 'leader', 'co_leader', 'elder', 'member'
    
    -- Contribution
    donated             INT DEFAULT 0,
    received            INT DEFAULT 0,
    
    joined_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (guild_id, player_id)
);

CREATE INDEX idx_guild_members_player ON guild_members(player_id);
```

---

# Part 4: Leaderboards (Redis)

```python
# ============================================================
# GAMING LEADERBOARDS (Redis Sorted Sets)
# ============================================================

import redis
from typing import List, Dict, Optional

class Leaderboard:
    """
    Redis-based leaderboard for millions of players.
    """
    def __init__(self):
        self.redis = redis.Redis()
    
    def update_score(self, leaderboard_key: str, player_id: str, score: int):
        """
        Update player score. O(log(N)).
        """
        self.redis.zadd(leaderboard_key, {player_id: score})
    
    def get_rank(self, leaderboard_key: str, player_id: str) -> Optional[int]:
        """
        Get player's rank (0-indexed). O(log(N)).
        """
        rank = self.redis.zrevrank(leaderboard_key, player_id)
        return rank + 1 if rank is not None else None
    
    def get_score(self, leaderboard_key: str, player_id: str) -> Optional[int]:
        """Get player's score."""
        score = self.redis.zscore(leaderboard_key, player_id)
        return int(score) if score else None
    
    def get_top(self, leaderboard_key: str, limit: int = 100) -> List[Dict]:
        """
        Get top N players. O(log(N) + M).
        """
        results = self.redis.zrevrange(
            leaderboard_key, 0, limit - 1, 
            withscores=True
        )
        
        return [
            {"rank": i + 1, "player_id": player.decode(), "score": int(score)}
            for i, (player, score) in enumerate(results)
        ]
    
    def get_around_me(
        self, leaderboard_key: str, player_id: str, count: int = 5
    ) -> List[Dict]:
        """
        Get players around the given player's rank.
        """
        rank = self.redis.zrevrank(leaderboard_key, player_id)
        if rank is None:
            return []
        
        start = max(0, rank - count)
        end = rank + count
        
        results = self.redis.zrevrange(
            leaderboard_key, start, end, 
            withscores=True
        )
        
        return [
            {"rank": start + i + 1, "player_id": player.decode(), "score": int(score)}
            for i, (player, score) in enumerate(results)
        ]
    
    def get_player_count(self, leaderboard_key: str) -> int:
        """Total players in leaderboard."""
        return self.redis.zcard(leaderboard_key)


# Usage
leaderboard = Leaderboard()

# After a match
leaderboard.update_score("leaderboard:ranked:season_15", player_id, new_rating)

# Get top 100
top_100 = leaderboard.get_top("leaderboard:ranked:season_15", 100)

# Get my rank
my_rank = leaderboard.get_rank("leaderboard:ranked:season_15", player_id)
```

---

# Part 5: Matchmaking Queue (Redis)

```python
# ============================================================
# MATCHMAKING SYSTEM
# ============================================================

import redis
import time
from typing import List, Tuple, Optional

class Matchmaker:
    """
    MMR-based matchmaking using Redis sorted sets.
    """
    def __init__(self):
        self.redis = redis.Redis()
        self.RATING_TOLERANCE = 100  # Initial MMR range
        self.MAX_WAIT_SEC = 120      # Max queue time
        self.TOLERANCE_EXPAND_SEC = 15  # Expand range every N seconds
    
    def join_queue(
        self, 
        queue_key: str, 
        player_id: str, 
        rating: int,
        team_size: int = 1
    ):
        """
        Add player to matchmaking queue.
        Score = rating, for range queries.
        """
        self.redis.zadd(queue_key, {player_id: rating})
        self.redis.hset(f"queue_meta:{player_id}", mapping={
            "queue": queue_key,
            "rating": rating,
            "joined_at": int(time.time()),
            "team_size": team_size
        })
    
    def leave_queue(self, queue_key: str, player_id: str):
        """Remove player from queue."""
        self.redis.zrem(queue_key, player_id)
        self.redis.delete(f"queue_meta:{player_id}")
    
    def find_match(
        self, 
        queue_key: str, 
        players_per_team: int, 
        teams: int = 2
    ) -> Optional[List[str]]:
        """
        Find a suitable match from the queue.
        Returns list of player_ids if match found.
        """
        total_players = players_per_team * teams
        
        # Get all players in queue sorted by rating
        queue = self.redis.zrange(queue_key, 0, -1, withscores=True)
        
        if len(queue) < total_players:
            return None
        
        # Try to find players with similar ratings
        for i in range(len(queue) - total_players + 1):
            candidates = queue[i:i + total_players]
            
            min_rating = candidates[0][1]
            max_rating = candidates[-1][1]
            
            # Check if within tolerance (expand based on wait time)
            if max_rating - min_rating <= self._get_tolerance(candidates):
                player_ids = [p[0].decode() for p in candidates]
                
                # Remove from queue
                for player_id in player_ids:
                    self.leave_queue(queue_key, player_id)
                
                return player_ids
        
        return None
    
    def _get_tolerance(self, candidates: List[Tuple]) -> int:
        """
        Get rating tolerance based on longest wait time in group.
        """
        now = int(time.time())
        max_wait = 0
        
        for player_id, _ in candidates:
            meta = self.redis.hgetall(f"queue_meta:{player_id.decode()}")
            if meta:
                joined_at = int(meta.get(b"joined_at", now))
                wait = now - joined_at
                max_wait = max(max_wait, wait)
        
        # Expand tolerance based on wait time
        expansions = max_wait // self.TOLERANCE_EXPAND_SEC
        return self.RATING_TOLERANCE + (expansions * 50)
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Leaderboard in Redis | ZSET with ZREVRANK |
| 2 | MMR-based matchmaking | Sorted by rating, tolerance expansion |
| 3 | Season-based stats | player_stats.season_id |
| 4 | Transaction audit trail | All currency/item changes logged |
| 5 | Rating change tracked | rating_before, rating_after |
| 6 | Inventory with source | source column for fraud detection |
| 7 | Guild/clan support | Hierarchical roles |
| 8 | Friend relationships | Bidirectional with status |

---

# Part 6: DynamoDB Single-Table Design

```
============================================================
GAMING: DynamoDB Single-Table Design
For high-scale player profiles, inventory, and stats
============================================================

TABLE: gaming_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (search by username/email)
- GSI2: GSI2PK / GSI2SK (social & guild queries)

============================================================
ENTITY PATTERNS
============================================================

PLAYER PROFILE
  PK: PLAYER#{player_id}
  SK: PROFILE
  GSI1PK: USERNAME#{username}
  GSI1SK: PROFILE
  
  Attributes: username, display_name, email, level, xp, 
              coins, gems, created_at, avatar_url

PLAYER LOADOUT (for fast game server fetch)
  PK: PLAYER#{player_id}
  SK: LOADOUT#{mode_id}
  
  Attributes: character_id, weapon_ids, skin_ids, perks

INVENTORY ITEM
  PK: PLAYER#{player_id}
  SK: ITEM#{item_id}
  GSI2PK: PLAYER#{player_id}
  GSI2SK: RARITY#{rarity}
  
  Attributes: item_name, type, rarity, acquired_at, is_equipped

MATCH HISTORY (Recent)
  PK: PLAYER#{player_id}
  SK: MATCH#{timestamp}#{match_id}
  
  Attributes: mode, result, kills, deaths, rating_change

FRIENDSHIP
  PK: PLAYER#{player_id}
  SK: FRIEND#{friend_id}
  GSI2PK: PLAYER#{friend_id}
  GSI2SK: FRIEND_STATUS#{status}
  
  Attributes: status, initiated_by, became_friends_at

GUILD MEMBER
  PK: GUILD#{guild_id}
  SK: MEMBER#{player_id}
  GSI1PK: PLAYER#{player_id}
  GSI1SK: GUILD
  
  Attributes: role, joined_at, contribution_score

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Login (Get profile + loadout)
   Table: PK=PLAYER#{player_id}, SK begins_with "PROFILE" or "LOADOUT"

2. Get player inventory
   Table: PK=PLAYER#{player_id}, SK begins_with "ITEM#"

3. Search player by username
   GSI1: PK=USERNAME#{username}

4. Get guild roster
   Table: PK=GUILD#{guild_id}, SK begins_with "MEMBER#"

5. Check which guild a player belongs to
   GSI1: PK=PLAYER#{player_id}, SK="GUILD"

6. Get player's match history (last 50)
   Table: PK=PLAYER#{player_id}, SK begins_with "MATCH#" (Reverse timestamps)

7. Get player's friends list
   Table: PK=PLAYER#{player_id}, SK begins_with "FRIEND#"
```

---

# Part 7: Query Examples with EXPLAIN

```sql
-- ============================================================
-- GAMING QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Player Profile + Main Stats
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    p.id, p.display_name, p.level, p.xp, p.xp_to_next_level,
    p.avatar_url,
    ps.rating, ps.wins, ps.losses, ps.win_rate,
    ps.kda, ps.matches_played
FROM players p
LEFT JOIN player_stats ps ON ps.player_id = p.id
    AND ps.game_mode = 'ranked'
    AND ps.season_id = (SELECT id FROM seasons WHERE is_active = TRUE)
WHERE p.id = $1;

-- Expected: PK lookup on players, index scan on player_stats, <5ms


-- ===========================================
-- QUERY 2: Inventory Sync (At Login)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    i.id, i.name, i.item_type, i.rarity,
    pi.quantity, pi.is_equipped, pi.equipped_slot,
    pi.customization
FROM player_inventory pi
JOIN items i ON i.id = pi.item_id
WHERE pi.player_id = $1;

-- Expected: Index scan on idx_inventory_player, ~10ms for <500 items


-- ===========================================
-- QUERY 3: Match History with Details
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    m.id AS match_id,
    m.game_mode,
    m.map_id,
    m.ended_at,
    m.duration_sec,
    mp.result,
    mp.character_id,
    mp.kills, mp.deaths, mp.assists,
    mp.rating_change,
    mp.grade
FROM match_participants mp
JOIN matches m ON m.id = mp.match_id
WHERE mp.player_id = $1
ORDER BY m.ended_at DESC
LIMIT 20;

-- Expected: Index scan on idx_participants_player, ~15ms


-- ===========================================
-- QUERY 4: Leaderboard (Top 100 via SQL Fallback)
-- ===========================================

-- NOTE: Normally done via Redis, but for analytics/history:
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    RANK() OVER (ORDER BY ps.rating DESC) as rank,
    p.display_name,
    p.avatar_url,
    ps.rating,
    ps.wins,
    ps.matches_played
FROM player_stats ps
JOIN players p ON p.id = ps.player_id
WHERE ps.game_mode = 'ranked'
  AND ps.season_id = $1
ORDER BY ps.rating DESC
LIMIT 100;

-- Expected: Index scan on idx_stats_rating, partial sort, <50ms


-- ===========================================
-- QUERY 5: Guild Roster with Status
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    gm.role,
    gm.joined_at,
    gm.donated,
    p.display_name,
    p.level,
    p.last_login_at
FROM guild_members gm
JOIN players p ON p.id = gm.player_id
WHERE gm.guild_id = $1
ORDER BY 
    CASE gm.role 
        WHEN 'leader' THEN 1 
        WHEN 'co_leader' THEN 2 
        WHEN 'elder' THEN 3 
        ELSE 4 
    END, 
    gm.joined_at DESC;

-- Expected: Index scan on PK, ~10ms


-- ===========================================
-- QUERY 6: Economy Audit Log
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    t.created_at,
    t.transaction_type,
    t.source,
    t.coins_change,
    t.gems_change,
    i.name AS item_name,
    t.price_paid,
    t.payment_provider
FROM transactions t
LEFT JOIN items i ON i.id = t.item_id
WHERE t.player_id = $1
ORDER BY t.created_at DESC
LIMIT 50;

-- Expected: Index scan on idx_txn_player, ~5ms
```

---

# Part 8: Capacity Planning

```
============================================================
GAMING CAPACITY PLANNING
============================================================

ASSUMPTIONS (Fortnite/Apex Scale):
- 10M DAU (Daily Active Users)
- 100M registered players
- 1M PCU (Peak Concurrent Users)
- Avg 5 matches/day per DAU = 50M matches/day
- Avg 10 players/match = 10 players writing stats per match

============================================================
TABLE SIZE ESTIMATES
============================================================

PLAYERS
  Rows: 100M
  Row Size: ~1KB
  Total: ~100 GB

PLAYER_STATS
  Rows: 100M players × 5 modes × 4 seasons/yr = 2B rows/yr
  Row Size: ~200 bytes
  Total: ~400 GB/year

PLAYER_INVENTORY
  Rows: 100M players × 100 items avg = 10B rows
  Row Size: ~100 bytes
  Total: ~1 TB
  (Note: Heavy read IO at login)

MATCHES
  Rows: 50M/day = 18B/year
  Row Size: ~400 bytes
  Total: ~7.2 TB/year

MATCH_PARTICIPANTS
  Rows: 50M matches × 10 players = 500M/day = 180B/year
  Row Size: ~300 bytes
  Total: ~54 TB/year

TRANSACTIONS
  Rows: 10M/day (purchases + rewards)
  Row Size: ~300 bytes
  Total: ~1 TB/year

============================================================
TOTAL STORAGE
============================================================

| Table | Size (1 Yr) | Partition Strategy |
|-------|-------------|-------------------|
| Players | 100 GB | By Region/Shard |
| Stats | 400 GB | By Season |
| Inventory | 1 TB | By Region/Shard |
| Matches | 7.2 TB | By Month |
| Participants | 54 TB | By Month |
| Transactions | 1 TB | By Month |

+ Indexes (~15%): ~10 TB
+ Total: ~75 TB per year
+ Compression (ZSTD): ~25 TB

============================================================
THROUGHPUT REQUIREMENTS (Peak)
============================================================

LOGIN FLOW (Start of event/season):
- 100K logins/sec
- 100K reads/sec on Players
- 100K reads/sec on Inventory (scan)
- 100K reads/sec on Stats
-> Needs massive read replicas or DynamoDB/Cassandra

MATCHMAKING:
- 1M players in queue
- Redis ZADD/ZREM: 20K ops/sec per region
- Matchmaker logic: Scale horizontally

MATCH COMPLETION (Write heavy):
- 500K matches ending per minute window
- 5M stats updates/min = 83K writes/sec
- 5M history inserts/min = 83K writes/sec
-> Batch writes or queue-based persistence

============================================================
SCALING STRATEGY
============================================================

1. SHARDING (By Player ID)
   - 64 Shards for player data (Players, Inventory, Stats)
   - Consistent hashing on player_id
   - Cross-shard transactions avoided (except gifting, use 2PC)

2. COLD STORAGE
   - Move matches > 30 days to S3/Parquet
   - Keep only "Match Summaries" in hot DB

3. CACHING
   - Redis Memory: ~500 GB for 1M PCU sessions + Leaderboards

============================================================
COST ESTIMATES (AWS)
============================================================

Database (Aurora/DynamoDB Provisioned):
  ~ $20,000 / month

Redis (ElastiCache r6g.2xlarge x 20):
  ~ $15,000 / month

S3 (Archive):
  ~ $1,000 / month

Bandwidth:
  ~ $50,000 / month (High volume game traffic)
```

---

# Part 9: Anti-Patterns to Avoid

```
============================================================
GAMING ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Calculating Leaderboards in SQL
-----------------------------------------
WRONG:
  SELECT rank() OVER (ORDER BY score DESC) FROM stats;
  -- Scanning 100M rows on every request. Site goes down.
  
RIGHT:
  -- Redis Sorted Sets
  ZADD leaderboard 1500 "player_1"
  ZRANK leaderboard "player_1"
  -- O(log N) - microseconds.


❌ ANTI-PATTERN 2: Writing Match State to DB
-----------------------------------------
WRONG:
  UPDATE matches SET player_health = 90 WHERE id = ...
  -- 60 updates/sec per player = DB melt.
  
RIGHT:
  -- State in Game Server Memory
  -- Snapshot to Redis every 10s (optional)
  -- Write to DB ONLY at match end.


❌ ANTI-PATTERN 3: Inventory without Idempotency
-----------------------------------------
WRONG:
  UPDATE inventory SET coins = coins - 100;
  -- Network retry happens -> user charged twice.
  
RIGHT:
  -- Idempotency keys
  INSERT INTO transactions (idempotency_key, ...) VALUES ...
  ON CONFLICT DO NOTHING;


❌ ANTI-PATTERN 4: Trusting the Client
-----------------------------------------
WRONG:
  API: POST /update_stats { "wins": +1 }
  -- Player hacks client, sends fake wins.
  
RIGHT:
  -- Server Authoritative
  Game Server reports result signed with secret key.
  Clients only receive updates.


❌ ANTI-PATTERN 5: Synchronous Third-Party API Calls
-----------------------------------------
WRONG:
  def purchase():
     call_stripe_api()  -- Takes 2 seconds
     update_db()
  -- DB transaction held open for 2s. Connections exhausted.
  
RIGHT:
  -- Async Webhooks
  Initiate payment -> Return "Pending"
  Stripe Webhook -> Update DB -> Notify Client


❌ ANTI-PATTERN 6: Storing JSON Blobs for Everything
-----------------------------------------
WRONG:
  inventory JSONB
  -- Checking "do they have item X" requires parsing 1MB JSON.
  
RIGHT:
  -- Normalized table for items
  TABLE player_inventory (player_id, item_id, quantity)
  -- JSONB only for customization/metadata.


❌ ANTI-PATTERN 7: Global Locks for Matchmaking
-----------------------------------------
WRONG:
  LOCK TABLE queue;
  SELECT * FROM queue WHERE ...
  -- Serializes all matchmaking.
  
RIGHT:
  -- Redis Atomic Operations
  -- Shard queues by Region + Game Mode
  -- No global locks.


❌ ANTI-PATTERN 8: Hard Deletes for Bans
-----------------------------------------
WRONG:
  DELETE FROM players WHERE id = ...
  -- History lost. Can't investigate appeals.
  
RIGHT:
  UPDATE players SET is_banned = true, banned_at = NOW();
  -- Keep data for audit.


❌ ANTI-PATTERN 9: Integers for Global IDs
-----------------------------------------
WRONG:
  id SERIAL PRIMARY KEY
  -- Guessable IDs (account enumeration attack)
  -- Merge conflicts if merging shards.
  
RIGHT:
  id UUID PRIMARY KEY
  -- Random, unguessable, universally unique.


❌ ANTI-PATTERN 10: No Versioning for Items
-----------------------------------------
WRONG:
  UPDATE items SET stats = '{damage: 50}'
  -- Players who bought it yesterday seeing stats change? 
  -- Or existing items corrupted?
  
RIGHT:
  -- Item definitions are versioned or static
  -- Balance changes applied via configuration, not DB update
```

---

# Part 10: CDC & Event Streaming

```
============================================================
GAMING CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (Sharded)   │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ Data Lake │    │ Analytics │   │ Anti-Cheat│  │ Live Ops │
  │ (Parquet) │    │ (Realtime)│   │ (Detection)  │ (Offers) │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- game.events.login      (Geo, Device stats)
- game.events.match_end  (Game balance analysis)
- game.economy.purchase  (Revenue dash)
- game.social.friend     (Graph analysis)
- game.security.ban      (Ban waves)

STREAMING USE CASES:
1. Real-time Fraud: Detect coin usage spikes > 3 sigma.
2. Skill Balancing: Monitor win-rates for heroes/weapons in real-time.
3. Live Ops: Trigger "Special Offer" if player loses 5 matches in a row (churn prevention).

============================================================
DISASTER RECOVERY
============================================================

RPO (Recovery Point Objective): < 1 minute (Economy data is critical)
RTO (Recovery Time Objective): < 15 minutes

STRATEGY:
1. Active-Passive Regions (for Global scale)
   - US-EAST-1 (Active) -> US-WEST-2 (Passive/Read Replica)
   - Global Database (Aurora Global)

2. Game Server DR
   - Stateless servers spawned in any region via Kubernetes/Agones.
   - If region dies, matchmaker redirects new matches to backup region.
   - Running matches are lost (acceptable), but results NOT persisted.

3. Backup Schedule
   - Hourly Snapshots for Point-In-Time Recovery.
   - Continuous WAL archiving.
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- GAMING: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / CHANGE HISTORY (Economy Critical)
-- ===========================================

CREATE TABLE economy_audit_log (
    id                  BIGSERIAL PRIMARY KEY,
    player_id           UUID NOT NULL,
    action_type         VARCHAR(50) NOT NULL,  -- 'currency_add', 'item_trade', 'purchase'
    entity_type         VARCHAR(50) NOT NULL,  -- 'inventory', 'wallet', 'trade'
    entity_id           UUID NOT NULL,
    old_value           JSONB,
    new_value           JSONB,
    change_reason       VARCHAR(100),  -- 'quest_reward', 'admin_grant', 'player_trade'
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    server_id           VARCHAR(50),
    ip_address          INET
) PARTITION BY RANGE (changed_at);

CREATE INDEX idx_audit_player ON economy_audit_log(player_id);
CREATE INDEX idx_audit_time ON economy_audit_log(changed_at DESC);


-- ===========================================
-- B. ATTACHMENTS / MEDIA (User Generated Content)
-- ===========================================

CREATE TABLE player_uploads (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id           UUID NOT NULL REFERENCES players(id),
    upload_type         VARCHAR(50) NOT NULL,  -- 'avatar', 'screenshot', 'replay'
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    storage_bucket      VARCHAR(100) NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    moderation_status   VARCHAR(20) DEFAULT 'pending',  -- pending, approved, rejected
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_upload_player ON player_uploads(player_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE (Push for Mobile)
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    player_id           UUID NOT NULL,
    channel             VARCHAR(20) NOT NULL,  -- 'push_ios', 'push_android', 'in_game'
    device_token        VARCHAR(255),
    notification_type   VARCHAR(100) NOT NULL,  -- 'friend_request', 'match_ready'
    title               VARCHAR(100),
    body                TEXT NOT NULL,
    payload             JSONB,  -- Deep link data
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS / INTEGRATIONS
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guild_id            UUID REFERENCES guilds(id),  -- Guild-level integrations
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['match.completed', 'player.level_up']
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_deliveries (
    id                  BIGSERIAL PRIMARY KEY,
    subscription_id     UUID NOT NULL REFERENCES webhook_subscriptions(id),
    event_type          VARCHAR(100) NOT NULL,
    payload             JSONB NOT NULL,
    response_code       INT,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- E. API KEYS (For Game Servers)
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    server_type         VARCHAR(50) NOT NULL,  -- 'game_server', 'matchmaker', 'analytics'
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 10000,  -- Higher for game servers
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- F. OAUTH / SSO (Platform Links)
-- ===========================================

CREATE TABLE oauth_providers (
    id                  SERIAL PRIMARY KEY,
    provider_type       VARCHAR(50) NOT NULL,  -- 'steam', 'xbox', 'playstation', 'discord', 'twitch'
    name                VARCHAR(100) NOT NULL,
    client_id           VARCHAR(255) NOT NULL,
    client_secret_enc   BYTEA NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE player_platform_links (
    id                  BIGSERIAL PRIMARY KEY,
    player_id           UUID NOT NULL REFERENCES players(id),
    provider_id         INT NOT NULL REFERENCES oauth_providers(id),
    platform_user_id    VARCHAR(255) NOT NULL,  -- Steam ID, Xbox Gamertag, etc.
    platform_username   VARCHAR(100),
    access_token_enc    BYTEA,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uk_player_platform UNIQUE (player_id, provider_id)
);


-- ===========================================
-- G. USER SESSIONS (Multi-Device Support)
-- ===========================================

CREATE TABLE player_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id           UUID NOT NULL REFERENCES players(id),
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    platform            VARCHAR(20) NOT NULL,  -- 'pc', 'mobile', 'console'
    device_id           VARCHAR(100),
    ip_address          INET NOT NULL,
    game_version        VARCHAR(20),
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS (A/B Testing for Games)
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    description         TEXT,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    target_platform     VARCHAR(20),  -- 'pc', 'mobile', 'console', NULL for all
    min_level           INT,  -- Only players above this level
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE ab_test_assignments (
    id                  BIGSERIAL PRIMARY KEY,
    player_id           UUID NOT NULL REFERENCES players(id),
    experiment_name     VARCHAR(100) NOT NULL,
    variant             VARCHAR(50) NOT NULL,  -- 'control', 'treatment_a', 'treatment_b'
    assigned_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uk_player_experiment UNIQUE (player_id, experiment_name)
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
GAMING: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. LEADERBOARD PERFORMANCE (REDIS ZSETS)
============================================================

THE CHALLENGE:
10M Players. "What is my rank?"
`SELECT count(*) FROM scores WHERE score > my_score` -> O(N). Too slow.

SOLUTION: REDIS SORTED SETS (O(log N))
- `ZADD leaderboard 1050 "player_uuid"`
- `ZREVRANK leaderboard "player_uuid"` -> Returns rank instantly.

TUNING:
- **Ziplist vs Skiplist**: Redis stores small sorted sets as arrays (ziplist) for memory efficiency.
- **Sharding**: Single key `leaderboard` is a hot key.
- **Sharded Leaderboard**: range-partition by score? No, rank is global.
- **Approximation**: Update global leaderboard only for top 1000. Use shard-local rank (percentile) for general population.

============================================================
2. GAME STATE SYNC (UDP vs TCP)
============================================================

THE TRADEOFF:
- **TCP (Reliable)**: Inventory updates, Purchasing, Chat.
- **UDP (Fast)**: Player movement (x,y,z), Headshots.

DATABASE ROLE:
- DB is NOT in the game loop (60 ticks/sec).
- **Persistence Frequency**: Autosave every 3-5 mins + OnExit.
- **"The Lost Progress" Risk**: Server crash = 5 mins rollback.
- Mitigation: Write "Checkpoint" to Redis every 30s.

============================================================
3. MATCHMAKING CONCURRENCY
============================================================

THE CHALLENGE:
"Pool" of 100k players. Group them into buckets of 100 based on MMR (Skill).
Problem: "Ticket Contention". Player A grabbed by Match 1 and Match 2 simultaneously.

SOLUTION: REDIS ATOMICITY (LUA SCRIPTS)
- `EVAL` script checks status `IF player.status == 'QUEUED' THEN assign_to_match()`.
- Optimistic Lock: "Check-and-Set".

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Matchmaking Time (p99)       │ < 30s   │ > 2m = WARN     │
│  Login Latency (Auth)         │ < 500ms │ > 2s = PAGE     │
│  In-Game Telemetry Lag        │ < 100ms │ > 200ms = INFO  │
│  Leaderboard Update Lag       │ < 1s    │ > 5s = WARN     │
└─────────────────────────────────────────────────────────────┘

INFRASTRUCTURE METRICS:
- `packet_loss`: Is it the network or the server?
- `redis_cpu`: Lua scripts block the single thread. Keep scripts short (< 5ms).

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: LOGIN STORM (Live Event)
Symptom: Fortnite Concert starts. 5M users login in 1 min.
Mitigation:
- **Login Queue**: Issued "Wait Ticket".
- **Shed Load**: Disable "Friends List" and "Daily Message" to save DB Ops for core Login.

SCENARIO 2: STATE ROLLBACK EXPLOIT
Symptom: Player unplugs ethernet on death to prevent stats save.
Mitigation:
- **Server Authority**: Server decides outcome. Disconnect = Death.
- **Trust No Client**: Never accept `UPDATE stats SET kills = 10` from client. Client sends `Action: Shoot`. Server calculates result.

SCENARIO 3: INVENTORY DUPLICATION
Symptom: Quick trade + disconnect trades item but doesn't remove it.
Mitigation:
- **Two-Phase Commit**:
  1. Lock Inventory A and B.
  2. Swap Items.
  3. Unlock.
- Database Transaction (Serializable Isolation) required for items.

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

TELEMETRY (LOGS):
- Games generate TBs of "Player walked to X" logs.
- Optimization: Sample 1% of sessions for full debug logs.
- Aggregate metrics (heatmaps) on client, send summary only.

SERVER SCALING (Agones/K8s):
- Game Servers are stateful.
- **Scale Down**: Do not kill server with players. Mark "Draining". Wait for match end.
- Spot Instances? Risky for Game Servers (Disconnects). Good for Matchmakers/Lobby.
```

---

## 🔗 Related Documents

- [Twitter Schema](./twitter-schema-design-guide.md) — Similar social graph patterns
- [Database Scaling](./database-scaling-guide.md) — Sharding by region
- [Consistent Hashing](../system-design-notes/consistent-hashing-guide.md) — Game server distribution
- [Healthcare Schema](./healthcare-schema-design-guide.md) — Audit trail patterns for economy
