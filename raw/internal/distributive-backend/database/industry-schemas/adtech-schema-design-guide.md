# AdTech / Advertising Platform: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Campaigns, Ads, Targeting, Impressions, Clicks, Bidding, Attribution — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Storing raw impression events in PostgreSQL. Billions/day of ad events require **time-series databases** (ClickHouse, Druid) for analytics. PostgreSQL for campaigns only.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Google Ads Architecture](https://research.google/pubs/) | Auction system |
| [Real-Time Bidding (RTB)](https://www.iab.com/guidelines/rtb-openrtb-api-specification/) | OpenRTB spec |
| [Apache Druid](https://druid.apache.org/) | OLAP for ad analytics |

---

## 🎯 The Principal Laws of AdTech Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Events Are Immutable** | Impressions/clicks never change | Append-only event store |
| **Law 2: Real-Time + Batch** | Auction is real-time, reporting is batch | Lambda architecture |
| **Law 3: Attribution Is Complex** | Multi-touch, time decay | Event joins in analytics DB |
| **Law 4: Money Matters** | Every click costs advertisers | Double-entry for billing |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get campaign details | 1M/s | < 30ms | PostgreSQL + Cache |
| 2 | Get ads for targeting | 100K/s | < 50ms | Redis |
| 3 | Record impression | 1B/day | < 10ms | Kafka → ClickHouse |
| 4 | Record click | 100M/day | < 20ms | Kafka → ClickHouse |
| 5 | Real-time auction (bid) | 10M/s | < 50ms | Redis + ML service |
| 6 | Get campaign stats | 100K/s | < 200ms | ClickHouse |
| 7 | Create/update campaign | 10K/s | < 500ms | PostgreSQL |
| 8 | Budget check | 10M/s | < 10ms | Redis |
| 9 | Attribution query | 10K/s | < 5s | ClickHouse |
| 10 | Billing reconciliation | 1/day | < 1hr | Batch job |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    ADTECH DATA ARCHITECTURE                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                               │
│  ✓ Campaigns    ✓ Ads   ✓ Targeting   ✓ Billing                 │
│                                                                  │
│  • advertisers, campaigns, ad_groups                             │
│  • ads, creatives                                                │
│  • targeting_criteria                                            │
│  • budgets, billing_accounts                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Budget counters    ✓ Ad serving   ✓ Rate limits              │
│                                                                  │
│  • budget:{campaign_id}:daily                                    │
│  • ads:{targeting_key}                                           │
│  • pacing:{campaign_id}                                          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Kafka                                    │
│  ✓ Event ingestion    ✓ Real-time streaming                     │
│                                                                  │
│  • impressions topic (billions/day)                              │
│  • clicks topic                                                  │
│  • conversions topic                                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ClickHouse / Druid                            │
│  ✓ Ad analytics    ✓ Attribution   ✓ Reporting                  │
│                                                                  │
│  • impressions                                                   │
│  • clicks                                                        │
│  • conversions                                                   │
│  • aggregated_stats (materialized)                               │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL (Campaigns)

```sql
-- ============================================================
-- ADTECH SCHEMA: PostgreSQL Production DDL
-- Version: Advertising platform campaigns and billing
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ===========================================
-- SECTION 1: ADVERTISERS
-- ===========================================

CREATE TYPE advertiser_status AS ENUM ('active', 'paused', 'suspended', 'closed');

CREATE TABLE advertisers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identity
    name                VARCHAR(255) NOT NULL,
    legal_name          VARCHAR(255),
    
    -- Contact
    email               VARCHAR(255) NOT NULL,
    phone               VARCHAR(20),
    
    -- Billing
    billing_country     VARCHAR(2) NOT NULL,
    currency            VARCHAR(3) NOT NULL DEFAULT 'USD',
    tax_id              VARCHAR(50),
    
    -- Status
    status              advertiser_status DEFAULT 'active',
    
    -- Stripe for payments
    stripe_customer_id  VARCHAR(50),
    
    -- Spend limits
    monthly_spend_limit BIGINT,  -- In micros (1/1,000,000 of currency)
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- SECTION 2: BILLING ACCOUNTS
-- ===========================================

CREATE TYPE billing_type AS ENUM ('prepaid', 'postpaid', 'credit_line');

CREATE TABLE billing_accounts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    advertiser_id       UUID NOT NULL REFERENCES advertisers(id),
    
    billing_type        billing_type NOT NULL DEFAULT 'prepaid',
    
    -- Balance (for prepaid)
    balance             BIGINT DEFAULT 0,  -- In micros
    
    -- Credit limit (for postpaid/credit)
    credit_limit        BIGINT DEFAULT 0,
    current_spend       BIGINT DEFAULT 0,
    
    -- Payment method
    stripe_payment_method_id VARCHAR(50),
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_billing_advertiser ON billing_accounts(advertiser_id);


-- ===========================================
-- SECTION 3: CAMPAIGNS
-- ===========================================

CREATE TYPE campaign_status AS ENUM (
    'draft', 'pending_review', 'active', 'paused', 'completed', 'rejected'
);

CREATE TYPE campaign_objective AS ENUM (
    'awareness', 'traffic', 'engagement', 'leads', 'conversions', 'app_installs'
);

CREATE TABLE campaigns (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    advertiser_id       UUID NOT NULL REFERENCES advertisers(id),
    billing_account_id  UUID NOT NULL REFERENCES billing_accounts(id),
    
    -- Identity
    name                VARCHAR(255) NOT NULL,
    
    -- Objective
    objective           campaign_objective NOT NULL,
    
    -- Status
    status              campaign_status DEFAULT 'draft',
    
    -- Schedule
    start_date          DATE NOT NULL,
    end_date            DATE,
    
    -- Budget (in micros)
    daily_budget        BIGINT NOT NULL,
    lifetime_budget     BIGINT,
    
    -- Bidding
    bid_strategy        VARCHAR(50) NOT NULL,  -- 'cpc', 'cpm', 'cpa', 'maximize_conversions'
    target_cpa          BIGINT,  -- Target cost per action
    max_cpc             BIGINT,  -- Max cost per click
    
    -- Pacing
    pacing_type         VARCHAR(20) DEFAULT 'standard',  -- 'standard', 'accelerated'
    
    -- Stats (denormalized, updated async)
    impressions         BIGINT DEFAULT 0,
    clicks              BIGINT DEFAULT 0,
    conversions         INT DEFAULT 0,
    spend               BIGINT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_campaigns_advertiser ON campaigns(advertiser_id);
CREATE INDEX idx_campaigns_status ON campaigns(status) WHERE status = 'active';
CREATE INDEX idx_campaigns_dates ON campaigns(start_date, end_date);


-- ===========================================
-- SECTION 4: AD GROUPS
-- ===========================================

CREATE TABLE ad_groups (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_id         UUID NOT NULL REFERENCES campaigns(id),
    
    name                VARCHAR(255) NOT NULL,
    
    -- Status
    status              VARCHAR(20) DEFAULT 'active',  -- 'active', 'paused'
    
    -- Bidding override
    default_bid         BIGINT,  -- Override campaign bid
    
    -- Stats (denormalized)
    impressions         BIGINT DEFAULT 0,
    clicks              BIGINT DEFAULT 0,
    spend               BIGINT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_ad_groups_campaign ON ad_groups(campaign_id);


-- ===========================================
-- SECTION 5: ADS AND CREATIVES
-- ===========================================

CREATE TYPE ad_type AS ENUM ('text', 'image', 'video', 'carousel', 'native');
CREATE TYPE ad_status AS ENUM ('draft', 'pending_review', 'approved', 'rejected', 'paused');

CREATE TABLE ads (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ad_group_id         UUID NOT NULL REFERENCES ad_groups(id),
    
    name                VARCHAR(255),
    ad_type             ad_type NOT NULL,
    status              ad_status DEFAULT 'draft',
    
    -- Creative content
    headline            VARCHAR(90),
    headline2           VARCHAR(90),
    description         VARCHAR(180),
    description2        VARCHAR(180),
    
    -- URLs
    final_url           TEXT NOT NULL,
    display_url         VARCHAR(255),
    
    -- Media
    image_url           TEXT,
    video_url           TEXT,
    
    -- Call to action
    cta_type            VARCHAR(50),  -- 'learn_more', 'shop_now', 'sign_up'
    
    -- Review
    review_status       VARCHAR(20),
    rejection_reason    TEXT,
    reviewed_at         TIMESTAMP WITH TIME ZONE,
    
    -- Stats (denormalized)
    impressions         BIGINT DEFAULT 0,
    clicks              BIGINT DEFAULT 0,
    ctr                 DECIMAL(10,4) DEFAULT 0,  -- Click-through rate
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_ads_ad_group ON ads(ad_group_id);
CREATE INDEX idx_ads_status ON ads(status) WHERE status = 'approved';


-- ===========================================
-- SECTION 6: TARGETING CRITERIA
-- ===========================================

CREATE TABLE targeting_criteria (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ad_group_id         UUID NOT NULL REFERENCES ad_groups(id),
    
    -- Targeting type
    targeting_type      VARCHAR(50) NOT NULL,  -- 'location', 'age', 'gender', 'interest', 'keyword', 'device'
    
    -- Inclusion/exclusion
    is_excluded         BOOLEAN DEFAULT FALSE,
    
    -- Value depends on targeting_type
    -- For location: country/region/city code
    -- For age: '18-24', '25-34', etc.
    -- For interest: interest_id
    -- For keyword: keyword text
    target_value        TEXT NOT NULL,
    
    -- Bid adjustment
    bid_modifier        DECIMAL(5,2) DEFAULT 1.00,  -- 0.10 to 10.00
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_targeting_ad_group ON targeting_criteria(ad_group_id);
CREATE INDEX idx_targeting_type ON targeting_criteria(targeting_type, target_value);


-- ===========================================
-- SECTION 7: CONVERSIONS
-- ===========================================

CREATE TABLE conversion_actions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    advertiser_id       UUID NOT NULL REFERENCES advertisers(id),
    
    name                VARCHAR(255) NOT NULL,
    category            VARCHAR(50),  -- 'purchase', 'signup', 'lead', 'page_view'
    
    -- Attribution
    attribution_model   VARCHAR(50) DEFAULT 'last_click',  -- 'last_click', 'first_click', 'linear', 'time_decay'
    lookback_window_days INT DEFAULT 30,
    
    -- Value
    default_value       BIGINT,
    count_type          VARCHAR(20) DEFAULT 'one',  -- 'one' (unique), 'every' (all)
    
    -- Tracking
    tracking_code       TEXT,  -- JavaScript pixel
    
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_conversions_advertiser ON conversion_actions(advertiser_id);
```

---

# Part 4: ClickHouse DDL (Events)

```sql
-- ============================================================
-- ADTECH SCHEMA: ClickHouse Event Tables
-- Optimized for billions of events per day
-- ============================================================


-- ===========================================
-- IMPRESSIONS (Billions/day)
-- ===========================================

CREATE TABLE impressions
(
    event_id            UUID,
    event_time          DateTime64(3),  -- Millisecond precision
    
    -- Ad hierarchy
    ad_id               UUID,
    ad_group_id         UUID,
    campaign_id         UUID,
    advertiser_id       UUID,
    
    -- Placement
    publisher_id        UUID,
    placement_id        String,
    ad_format           LowCardinality(String),
    
    -- User
    user_id             String,  -- Hashed/anonymous
    device_id           String,
    
    -- Device info
    device_type         LowCardinality(String),  -- 'mobile', 'desktop', 'tablet'
    os                  LowCardinality(String),
    browser             LowCardinality(String),
    
    -- Geo
    country             LowCardinality(FixedString(2)),
    region              LowCardinality(String),
    city                LowCardinality(String),
    
    -- Auction
    winning_bid         UInt64,  -- In micros
    auction_type        LowCardinality(String),  -- 'first_price', 'second_price'
    
    -- Cost
    cost                UInt64,  -- CPM cost in micros
    
    -- Viewability
    is_viewable         UInt8,
    view_time_ms        UInt32,
    
    -- Event date for partitioning
    event_date          Date DEFAULT toDate(event_time)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (advertiser_id, campaign_id, ad_id, event_time)
TTL event_date + INTERVAL 90 DAY;  -- Keep 90 days of raw data


-- ===========================================
-- CLICKS
-- ===========================================

CREATE TABLE clicks
(
    event_id            UUID,
    event_time          DateTime64(3),
    
    -- Link to impression
    impression_id       UUID,
    
    -- Ad hierarchy
    ad_id               UUID,
    ad_group_id         UUID,
    campaign_id         UUID,
    advertiser_id       UUID,
    
    -- User
    user_id             String,
    device_id           String,
    ip_address          IPv4,
    
    -- Click details
    click_url           String,
    landing_page        String,
    
    -- Cost
    cost                UInt64,  -- CPC cost in micros
    
    -- Fraud detection
    is_bot              UInt8,
    is_fraudulent       UInt8,
    fraud_reason        LowCardinality(String),
    
    event_date          Date DEFAULT toDate(event_time)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (advertiser_id, campaign_id, event_time)
TTL event_date + INTERVAL 365 DAY;  -- Keep 1 year


-- ===========================================
-- CONVERSIONS
-- ===========================================

CREATE TABLE conversions
(
    event_id            UUID,
    event_time          DateTime64(3),
    
    -- Attribution
    attributed_click_id UUID,
    attributed_impression_id UUID,
    
    -- Ad hierarchy
    ad_id               UUID,
    campaign_id         UUID,
    advertiser_id       UUID,
    
    -- Conversion action
    conversion_action_id UUID,
    conversion_name     String,
    
    -- Value
    value               UInt64,
    currency            LowCardinality(FixedString(3)),
    
    -- Attribution model used
    attribution_model   LowCardinality(String),
    attribution_credit  Float32,  -- 0.0 to 1.0 (for multi-touch)
    
    -- User
    user_id             String,
    
    event_date          Date DEFAULT toDate(event_time)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (advertiser_id, campaign_id, event_time)
TTL event_date + INTERVAL 365 DAY;


-- ===========================================
-- AGGREGATED STATS (Materialized View)
-- ===========================================

CREATE MATERIALIZED VIEW campaign_stats_daily
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (advertiser_id, campaign_id, ad_group_id, ad_id, date)
AS SELECT
    toDate(event_time) AS date,
    advertiser_id,
    campaign_id,
    ad_group_id,
    ad_id,
    
    count() AS impressions,
    sumIf(1, is_viewable) AS viewable_impressions,
    sum(cost) AS spend
FROM impressions
GROUP BY date, advertiser_id, campaign_id, ad_group_id, ad_id;
```

---

# Part 5: Budget Management (Redis)

```python
# ============================================================
# ADTECH REDIS BUDGET MANAGEMENT
# ============================================================

import redis
from typing import Tuple

class BudgetManager:
    """
    Real-time budget tracking and pacing.
    """
    def __init__(self):
        self.redis = redis.Redis()
    
    def check_and_spend(
        self, 
        campaign_id: str, 
        amount_micros: int
    ) -> Tuple[bool, str]:
        """
        Atomically check budget and deduct if available.
        Returns (allowed, reason).
        """
        daily_key = f"budget:daily:{campaign_id}"
        lifetime_key = f"budget:lifetime:{campaign_id}"
        
        # Lua script for atomic check-and-deduct
        lua_script = """
        local daily_spent = tonumber(redis.call('GET', KEYS[1]) or 0)
        local daily_limit = tonumber(redis.call('GET', KEYS[1] .. ':limit') or 0)
        local lifetime_spent = tonumber(redis.call('GET', KEYS[2]) or 0)
        local lifetime_limit = tonumber(redis.call('GET', KEYS[2] .. ':limit') or 0)
        local amount = tonumber(ARGV[1])
        
        -- Check daily budget
        if daily_limit > 0 and daily_spent + amount > daily_limit then
            return {0, 'DAILY_BUDGET_EXCEEDED'}
        end
        
        -- Check lifetime budget
        if lifetime_limit > 0 and lifetime_spent + amount > lifetime_limit then
            return {0, 'LIFETIME_BUDGET_EXCEEDED'}
        end
        
        -- Deduct
        redis.call('INCRBY', KEYS[1], amount)
        if lifetime_limit > 0 then
            redis.call('INCRBY', KEYS[2], amount)
        end
        
        return {1, 'OK'}
        """
        
        result = self.redis.eval(
            lua_script, 2, 
            daily_key, lifetime_key, 
            amount_micros
        )
        
        return (result[0] == 1, result[1].decode())
    
    def set_daily_budget(self, campaign_id: str, budget_micros: int):
        """Set campaign daily budget limit."""
        self.redis.set(f"budget:daily:{campaign_id}:limit", budget_micros)
    
    def reset_daily_spend(self, campaign_id: str):
        """Called at midnight to reset daily spend."""
        self.redis.set(f"budget:daily:{campaign_id}", 0)
    
    def get_remaining_budget(self, campaign_id: str) -> dict:
        """Get remaining budgets."""
        daily_spent = int(self.redis.get(f"budget:daily:{campaign_id}") or 0)
        daily_limit = int(self.redis.get(f"budget:daily:{campaign_id}:limit") or 0)
        
        return {
            "daily_spent": daily_spent,
            "daily_remaining": max(0, daily_limit - daily_spent),
            "daily_limit": daily_limit,
        }
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Events in ClickHouse | Impressions/clicks not in PostgreSQL |
| 2 | Budget in Redis | Atomic check-and-deduct |
| 3 | Money in micros | 1,000,000 micros = $1 |
| 4 | ClickHouse TTL | 90 days impressions, 1 year clicks |
| 5 | Materialized aggregates | campaign_stats_daily |
| 6 | Fraud flags | is_bot, is_fraudulent |
| 7 | Multi-touch attribution | attribution_credit 0-1 |
| 8 | LowCardinality strings | Device/OS/country optimized |

---

# Part 6: DynamoDB Single-Table Design

```
============================================================
ADTECH: DynamoDB Single-Table Design
For campaign management (not events - those stay in ClickHouse)
============================================================

TABLE: adtech_campaigns
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (status queries)
- GSI2: GSI2PK / GSI2SK (date queries)

============================================================
ENTITY PATTERNS
============================================================

ADVERTISER
  PK: ADV#{advertiser_id}
  SK: PROFILE
  GSI1PK: STATUS#{status}
  GSI1SK: ADV#{advertiser_id}
  
  Attributes: name, email, billing_country, currency, 
              stripe_customer_id, monthly_spend_limit, created_at

BILLING_ACCOUNT
  PK: ADV#{advertiser_id}
  SK: BILLING#{billing_account_id}
  GSI1PK: ADV#{advertiser_id}#BILLING
  GSI1SK: TYPE#{billing_type}
  
  Attributes: billing_type, balance, credit_limit, current_spend,
              stripe_payment_method_id, is_active

CAMPAIGN
  PK: ADV#{advertiser_id}
  SK: CAMP#{campaign_id}
  GSI1PK: STATUS#{status}
  GSI1SK: DATE#{start_date}#CAMP#{campaign_id}
  GSI2PK: ADV#{advertiser_id}#ACTIVE
  GSI2SK: DATE#{start_date}
  
  Attributes: name, objective, status, start_date, end_date,
              daily_budget, lifetime_budget, bid_strategy,
              impressions, clicks, conversions, spend

AD_GROUP
  PK: CAMP#{campaign_id}
  SK: ADGRP#{ad_group_id}
  GSI1PK: ADV#{advertiser_id}#ADGROUPS
  GSI1SK: CAMP#{campaign_id}#ADGRP#{ad_group_id}
  
  Attributes: name, status, default_bid, impressions, clicks, spend

AD
  PK: CAMP#{campaign_id}
  SK: ADGRP#{ad_group_id}#AD#{ad_id}
  GSI1PK: STATUS#{status}#APPROVED
  GSI1SK: ADGRP#{ad_group_id}#AD#{ad_id}
  
  Attributes: name, ad_type, headline, description, final_url,
              image_url, video_url, cta_type, impressions, clicks, ctr

TARGETING_CRITERION
  PK: CAMP#{campaign_id}
  SK: ADGRP#{ad_group_id}#TGT#{targeting_id}
  GSI1PK: TGT_TYPE#{targeting_type}
  GSI1SK: VALUE#{target_value}
  
  Attributes: targeting_type, is_excluded, target_value, bid_modifier

CONVERSION_ACTION
  PK: ADV#{advertiser_id}
  SK: CONV#{conversion_action_id}
  
  Attributes: name, category, attribution_model, lookback_window_days,
              default_value, count_type, tracking_code

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get advertiser with all campaigns
   Table: PK=ADV#{advertiser_id}, SK begins_with "CAMP#"

2. Get all active campaigns (for serving)
   GSI1: PK=STATUS#active

3. Get campaign with all ad groups and ads
   Table: PK=CAMP#{campaign_id} (gets all nested entities)

4. Get approved ads for ad group
   GSI1: PK=STATUS#approved#APPROVED, SK begins_with ADGRP#{ad_group_id}

5. Find all advertisers by status
   GSI1: PK=STATUS#{status}

6. Get campaigns starting today
   GSI1: PK=STATUS#active, SK begins_with DATE#{today}
```

---

# Part 7: ClickHouse Query Examples

```sql
-- ============================================================
-- ADTECH CLICKHOUSE QUERY PATTERNS
-- ============================================================

-- ===========================================
-- QUERY 1: Campaign Performance Report
-- ===========================================

SELECT 
    toDate(event_time) AS date,
    campaign_id,
    count() AS impressions,
    countIf(click_id IS NOT NULL) AS clicks,
    round(clicks / impressions * 100, 2) AS ctr,
    sum(cost) / 1000000 AS spend_usd,
    round(spend_usd / clicks, 2) AS cpc
FROM impressions
LEFT JOIN clicks USING (impression_id)
WHERE advertiser_id = {advertiser_id:UUID}
  AND event_date >= today() - 30
  AND event_date <= today()
GROUP BY date, campaign_id
ORDER BY date DESC, spend_usd DESC;

-- Execution: ~50ms for 100M impressions (partitioned + indexed)


-- ===========================================
-- QUERY 2: Real-Time Dashboard (Last Hour)
-- ===========================================

SELECT 
    toStartOfMinute(event_time) AS minute,
    count() AS impressions,
    uniq(user_id) AS unique_users,
    sum(cost) / 1000000 AS spend
FROM impressions
WHERE advertiser_id = {advertiser_id:UUID}
  AND event_time >= now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute DESC;

-- Uses recent data in memory, ~10ms execution


-- ===========================================
-- QUERY 3: Attribution Report (Multi-Touch)
-- ===========================================

WITH user_journey AS (
    SELECT 
        user_id,
        groupArray(tuple(event_time, campaign_id, 'impression')) AS touchpoints
    FROM impressions
    WHERE advertiser_id = {advertiser_id:UUID}
      AND event_date >= today() - 30
    GROUP BY user_id
),
conversions_with_path AS (
    SELECT 
        c.conversion_action_id,
        c.value,
        uj.touchpoints,
        length(uj.touchpoints) AS touchpoint_count
    FROM conversions c
    JOIN user_journey uj ON c.user_id = uj.user_id
    WHERE c.advertiser_id = {advertiser_id:UUID}
      AND c.event_date >= today() - 30
)
SELECT 
    conversion_action_id,
    count() AS conversions,
    sum(value) / 1000000 AS revenue,
    avg(touchpoint_count) AS avg_touchpoints
FROM conversions_with_path
GROUP BY conversion_action_id;


-- ===========================================
-- QUERY 4: Fraud Detection Report
-- ===========================================

SELECT 
    toDate(event_time) AS date,
    fraud_reason,
    count() AS fraud_clicks,
    sum(cost) / 1000000 AS blocked_spend,
    uniq(user_id) AS unique_fraudsters,
    uniq(ip_address) AS unique_ips
FROM clicks
WHERE advertiser_id = {advertiser_id:UUID}
  AND is_fraudulent = 1
  AND event_date >= today() - 7
GROUP BY date, fraud_reason
ORDER BY date DESC, blocked_spend DESC;


-- ===========================================
-- QUERY 5: Geographic Performance
-- ===========================================

SELECT 
    country,
    region,
    count() AS impressions,
    countIf(c.event_id IS NOT NULL) AS clicks,
    round(clicks / impressions * 100, 2) AS ctr,
    sum(i.cost + coalesce(c.cost, 0)) / 1000000 AS spend
FROM impressions i
LEFT JOIN clicks c ON i.event_id = c.impression_id
WHERE i.advertiser_id = {advertiser_id:UUID}
  AND i.event_date >= today() - 7
GROUP BY country, region
ORDER BY spend DESC
LIMIT 100;


-- ===========================================
-- QUERY 6: Hourly Pacing Check
-- ===========================================

SELECT 
    campaign_id,
    toStartOfHour(event_time) AS hour,
    sum(cost) / 1000000 AS hourly_spend,
    -- Compare to expected pacing
    hourly_spend / (daily_budget / 24) AS pacing_ratio
FROM impressions i
JOIN campaigns c ON i.campaign_id = c.id  -- Federated query
WHERE i.event_date = today()
GROUP BY campaign_id, hour, c.daily_budget
HAVING pacing_ratio > 1.5  -- Overpacing alert
ORDER BY pacing_ratio DESC;
```

---

# Part 8: Capacity Planning

```
============================================================
ADTECH CAPACITY PLANNING
============================================================

ASSUMPTIONS:
- Mid-size ad network
- 1B impressions/day
- 50M clicks/day (5% CTR)
- 1M conversions/day
- 10,000 active campaigns
- 100,000 ads

============================================================
CLICKHOUSE STORAGE (Events)
============================================================

IMPRESSIONS (1B/day):
  Row Size: ~300 bytes (compressed ~50 bytes)
  Daily: 1B × 50B = 50 GB/day
  90-day retention: 4.5 TB
  
  Partitions: Monthly (toYYYYMM)
  Shards: 6 nodes (replication factor 2)
  Per shard: ~750 GB

CLICKS (50M/day):
  Row Size: ~250 bytes (compressed ~40 bytes)
  Daily: 50M × 40B = 2 GB/day
  365-day retention: 730 GB

CONVERSIONS (1M/day):
  Row Size: ~200 bytes (compressed ~35 bytes)
  Daily: 1M × 35B = 35 MB/day
  365-day retention: 12.8 GB

AGGREGATED STATS:
  Pre-aggregated daily stats: ~1 GB/day
  365-day retention: 365 GB

TOTAL CLICKHOUSE: ~6 TB (with replication: 12 TB)

============================================================
POSTGRESQL STORAGE (Campaigns)
============================================================

ADVERTISERS: 50,000 × 500B = 25 MB
CAMPAIGNS: 100,000 × 800B = 80 MB
AD_GROUPS: 500,000 × 400B = 200 MB
ADS: 1,000,000 × 600B = 600 MB
TARGETING: 5,000,000 × 200B = 1 GB

TOTAL POSTGRESQL: ~2 GB + indexes (~1 GB) = 3 GB

============================================================
REDIS CAPACITY
============================================================

BUDGET COUNTERS:
  100,000 campaigns × 3 keys × 50 bytes = 15 MB

AD SERVING CACHE:
  1,000,000 ads × 500 bytes = 500 MB

PACING DATA:
  100,000 campaigns × 100 bytes = 10 MB

TOTAL REDIS: ~600 MB (use 2 GB instance for headroom)

============================================================
KAFKA THROUGHPUT
============================================================

IMPRESSIONS TOPIC:
  1B/day = 11,574 events/sec average
  Peak: 50,000 events/sec
  Message size: 300 bytes
  Throughput: 15 MB/sec peak
  Retention: 7 days = 350 GB
  Partitions: 64 (for parallelism)

CLICKS TOPIC:
  50M/day = 580 events/sec average
  Peak: 2,500 events/sec
  Retention: 7 days = 14 GB
  Partitions: 16

============================================================
SCALING THRESHOLDS
============================================================

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| ClickHouse QPS > 10K | > 50K | Add shards |
| Impression insert lag > 1s | > 10s | Add Kafka partitions |
| Redis memory > 70% | > 90% | Scale Redis cluster |
| Budget check p99 > 5ms | > 20ms | Add Redis replicas |
| PostgreSQL connections > 80% | > 95% | Scale pgbouncer |

============================================================
COST ESTIMATES (AWS)
============================================================

ClickHouse (6x i3.2xlarge):
  $0.624/hr × 6 × 730 hrs = $2,733/month

Kafka (MSK 6 brokers):
  kafka.m5.2xlarge = $1,200/month

Redis (r6g.large cluster):
  $0.126/hr × 730 = $92/month (× 3 nodes = $276)

PostgreSQL (RDS db.r6g.large):
  $0.21/hr × 730 = $153/month (+ replica = $306)

TOTAL: ~$4,500/month for mid-size ad network
```

---

# Part 9: Anti-Patterns to Avoid

```
============================================================
ADTECH ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Storing Impressions in PostgreSQL
-----------------------------------------
WRONG:
  INSERT INTO impressions (event_id, user_id, ad_id, ...)
  VALUES ($1, $2, $3, ...);  -- 1B rows/day!
  
RIGHT:
  -- Kafka → ClickHouse pipeline
  producer.send('impressions', event_data);
  -- ClickHouse ingests from Kafka
  -- PostgreSQL only for campaign metadata


❌ ANTI-PATTERN 2: Synchronous Budget Checks via PostgreSQL
-----------------------------------------
WRONG:
  BEGIN;
  SELECT budget_remaining FROM campaigns WHERE id = $1 FOR UPDATE;
  -- Meanwhile, 1000 other ad requests wait...
  
RIGHT:
  -- Redis atomic budget check (see Part 5)
  budget_manager.check_and_spend(campaign_id, cost)
  -- No locks, O(1) latency, 10M ops/sec


❌ ANTI-PATTERN 3: Joining Events Across Systems
-----------------------------------------
WRONG:
  SELECT * FROM postgres.campaigns c
  JOIN clickhouse.impressions i ON c.id = i.campaign_id;
  -- Cross-system join is disaster
  
RIGHT:
  -- Denormalize campaign info into events at write time
  -- Or use materialized views in ClickHouse
  -- Query single system per request


❌ ANTI-PATTERN 4: Not Using LowCardinality in ClickHouse
-----------------------------------------
WRONG:
  device_type String,  -- 3 unique values stored as full strings
  country String,      -- 200 unique values
  
RIGHT:
  device_type LowCardinality(String),  -- Dictionary encoded
  country LowCardinality(FixedString(2)),
  -- 10x compression improvement


❌ ANTI-PATTERN 5: Click Deduplication at Query Time
-----------------------------------------
WRONG:
  SELECT DISTINCT user_id, ad_id FROM clicks
  WHERE event_date = today();  -- Scans entire table!
  
RIGHT:
  -- Deduplicate at ingestion using Kafka + Redis
  if not redis.setnx(f"click:{user}:{ad}:{hour}", 1, ex=3600):
      return  # Already counted
  -- Or use ReplacingMergeTree in ClickHouse


❌ ANTI-PATTERN 6: Real-Time Attribution
-----------------------------------------
WRONG:
  -- Calculate attribution for every conversion in real-time
  SELECT * FROM impressions WHERE user_id = $1
  ORDER BY event_time;  -- Full scan per conversion!
  
RIGHT:
  -- Batch attribution job (hourly/daily)
  -- Pre-build user journey tables
  -- Use ClickHouse window functions for path analysis


❌ ANTI-PATTERN 7: Unbounded Lookback Queries
-----------------------------------------
WRONG:
  SELECT * FROM impressions
  WHERE advertiser_id = $1;  -- No date filter = full scan
  
RIGHT:
  SELECT * FROM impressions
  WHERE advertiser_id = $1
    AND event_date >= today() - 30;  -- Partition pruning


❌ ANTI-PATTERN 8: Float for Money
-----------------------------------------
WRONG:
  cost FLOAT,  -- $0.001 becomes 0.0009999999...
  
RIGHT:
  cost UInt64,  -- Store in micros (millionths)
  -- 1,000,000 micros = $1.00
  -- No floating point errors


❌ ANTI-PATTERN 9: Single Kafka Partition for Events
-----------------------------------------
WRONG:
  # All events to one partition
  producer.send('impressions', event)
  # Single consumer = bottleneck
  
RIGHT:
  # Partition by advertiser_id for locality
  producer.send('impressions', 
    key=advertiser_id, 
    value=event)
  # Parallel consumers per partition


❌ ANTI-PATTERN 10: No Fraud Detection
-----------------------------------------
WRONG:
  -- Count all clicks, bill advertiser
  INSERT INTO clicks (...) VALUES (...);
  UPDATE campaigns SET spend = spend + cost;
  
RIGHT:
  -- Fraud detection in pipeline
  fraud_score = fraud_detector.score(click)
  if fraud_score > 0.8:
      click.is_fraudulent = True
      click.fraud_reason = fraud_detector.reason
      # Don't charge advertiser
```

---

# Part 10: CDC & Event Streaming

```
============================================================
ADTECH CDC & STREAMING ARCHITECTURE
============================================================

DATA FLOW:

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (campaigns) │     │             │     │  ad.campaigns   │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
                                                  ▼
                                         ┌───────────────┐
                                         │  Flink/Spark  │
                                         │  Streaming    │
                                         └───────┬───────┘
                                                 │
              ┌──────────────────────────────────┼─────────┐
              ▼                                  ▼         ▼
       ┌────────────┐               ┌────────────┐   ┌──────────┐
       │ Redis      │               │ ClickHouse │   │ Advertiser│
       │ Ad Cache   │               │ Stats      │   │ Callbacks │
       └────────────┘               └────────────┘   └──────────┘

============================================================
KAFKA TOPICS
============================================================

ad.impressions (10B+ events/day potential)
  Partitions: 64-256 based on volume
  Key: advertiser_id (locality)
  Retention: 7 days
  Consumers: ClickHouse, fraud detection, pacing

ad.clicks (500M+ events/day)
  Partitions: 32
  Key: advertiser_id
  Retention: 7 days
  Consumers: ClickHouse, attribution, billing

ad.conversions (10M+ events/day)
  Partitions: 16
  Key: advertiser_id
  Retention: 30 days
  Consumers: ClickHouse, attribution, advertiser webhooks

ad.campaigns (CDC from PostgreSQL)
  Partitions: 8
  Log compacted (keep latest state)
  Consumers: Redis cache invalidation, ClickHouse dimension sync

ad.budget-events (spend tracking)
  Partitions: 32
  Key: campaign_id
  Consumers: Budget reconciliation, pacing adjustment

============================================================
FLINK STREAMING JOBS
============================================================

JOB 1: Real-Time Fraud Detection
  Input: ad.clicks
  Processing: ML model scoring, velocity checks
  Output: ad.clicks.validated (with fraud flags)

JOB 2: Pacing Monitor
  Input: ad.impressions
  Processing: Windowed aggregation (1 min tumbling)
  Output: Pacing alerts, budget exhaustion events

JOB 3: Attribution Pipeline
  Input: ad.impressions, ad.clicks, ad.conversions
  Processing: Session windows, path analysis
  Output: Attributed conversions with multi-touch credit

JOB 4: Real-Time Dashboard
  Input: ad.impressions, ad.clicks
  Processing: 1-second tumbling windows
  Output: Metrics to Redis for live dashboards
```

---

# Part 11: Disaster Recovery

```
============================================================
ADTECH DISASTER RECOVERY
============================================================

CRITICAL REQUIREMENT:
- Events are revenue - lost impressions = lost money
- Budget accuracy prevents over/under spend
- RPO: < 1 minute for events, < 5 minutes for campaigns
- RTO: < 15 minutes (ad serving must recover fast)

============================================================
CLICKHOUSE HA SETUP
============================================================

Topology:
  - 3 datacenters (us-east-1, us-west-2, eu-west-1)
  - 2 shards per datacenter
  - Replication factor: 2 (within datacenter)
  - ZooKeeper: 3-node ensemble
  
  Total: 12 ClickHouse nodes
  
Configuration:
  <remote_servers>
    <adtech_cluster>
      <shard>
        <replica><host>ch1-east</host></replica>
        <replica><host>ch2-east</host></replica>
      </shard>
      <shard>
        <replica><host>ch3-east</host></replica>
        <replica><host>ch4-east</host></replica>
      </shard>
  </remote_servers>

Failover:
  - Automatic replica promotion via ZooKeeper
  - Distributed table routes to healthy shards
  - < 30 second failover

============================================================
KAFKA HA SETUP
============================================================

Configuration:
  - 3 brokers minimum per datacenter
  - Replication factor: 3
  - min.insync.replicas: 2
  - unclean.leader.election.enable: false

Cross-Region:
  - MirrorMaker 2 for cross-region replication
  - Active-passive for DR
  - Lag monitoring: < 1 minute acceptable

============================================================
REDIS HA SETUP
============================================================

Cluster Mode:
  - 6 nodes (3 masters, 3 replicas)
  - Automatic failover via Redis Sentinel
  - Cross-AZ deployment

Budget Consistency:
  - Redis writes are source of truth for real-time
  - Hourly reconciliation with PostgreSQL
  - On failover: conservative budget (don't overspend)

============================================================
RECOVERY PROCEDURES
============================================================

SCENARIO 1: ClickHouse Node Failure
  Impact: None (replica takes over)
  Recovery: Automatic
  Data: No loss (replicated)

SCENARIO 2: Kafka Broker Failure
  Impact: Slight latency increase
  Recovery: Automatic leader election
  Data: No loss (min.insync.replicas=2)

SCENARIO 3: Redis Master Failure
  Impact: ~10 second budget check latency spike
  Recovery: Sentinel promotes replica
  Data: Possible ~1 second of spend data (acceptable)

SCENARIO 4: Full Datacenter Failure
  Impact: Regional traffic loss
  Recovery: DNS failover to secondary region
  RTO: < 5 minutes (DNS TTL)
  Data: Events replayed from Kafka mirror

============================================================
BACKUP STRATEGY
============================================================

ClickHouse:
  - Continuous backup to S3 (clickhouse-backup)
  - Daily snapshots with 30-day retention
  - Point-in-time recovery via Kafka replay

PostgreSQL:
  - Streaming replication to DR site
  - WAL archiving to S3
  - Daily pg_dump to S3 (30-day retention)

Redis:
  - RDB snapshots every 15 minutes to S3
  - AOF for sub-second durability
  - Reconstruction from PostgreSQL if total loss

============================================================
TESTING SCHEDULE
============================================================

| Test | Frequency | Target RTO | Notes |
|------|-----------|------------|-------|
| ClickHouse replica failover | Weekly | < 30s | Automated |
| Kafka broker failover | Weekly | < 30s | Automated |
| Redis failover | Weekly | < 10s | Sentinel |
| Full region failover | Quarterly | < 15 min | Manual |
| Kafka replay from backup | Monthly | < 2 hours | Verify data |
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- ADTECH: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / CHANGE HISTORY
-- ===========================================

CREATE TABLE entity_change_log (
    id                  BIGSERIAL PRIMARY KEY,
    entity_type         VARCHAR(50) NOT NULL,  -- 'campaign', 'ad_group', 'creative'
    entity_id           UUID NOT NULL,
    field_name          VARCHAR(100) NOT NULL,
    old_value           TEXT,
    new_value           TEXT,
    changed_by_id       UUID NOT NULL,
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    change_source       VARCHAR(50),  -- 'ui', 'api', 'bulk_import', 'auto_optimization'
    ip_address          INET
) PARTITION BY RANGE (changed_at);

CREATE INDEX idx_ecl_entity ON entity_change_log(entity_type, entity_id);
CREATE INDEX idx_ecl_time ON entity_change_log(changed_at DESC);

CREATE TABLE entity_change_log_2024 PARTITION OF entity_change_log
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE entity_change_log_2025 PARTITION OF entity_change_log
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');


-- ===========================================
-- B. CREATIVE ASSETS / MEDIA STORAGE
-- ===========================================

CREATE TABLE creative_assets (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    advertiser_id       UUID NOT NULL REFERENCES advertisers(id),
    
    -- File metadata
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    width               INT,  -- For images/videos
    height              INT,
    duration_seconds    DECIMAL(10,2),  -- For video/audio
    
    -- Storage
    storage_bucket      VARCHAR(100) NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    cdn_url             VARCHAR(500),
    
    -- Approval
    review_status       VARCHAR(20) DEFAULT 'pending',  -- pending, approved, rejected
    rejection_reason    TEXT,
    reviewed_by         UUID,
    reviewed_at         TIMESTAMP WITH TIME ZONE,
    
    -- Metadata
    uploaded_by_id      UUID NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_asset_adv ON creative_assets(advertiser_id);
CREATE INDEX idx_asset_review ON creative_assets(review_status);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID,
    advertiser_id       UUID,
    
    -- Delivery
    channel             VARCHAR(20) NOT NULL,  -- 'email', 'webhook', 'slack'
    recipient           VARCHAR(255) NOT NULL,
    
    -- Content
    notification_type   VARCHAR(100) NOT NULL,  -- 'budget_exhausted', 'campaign_approved'
    subject             VARCHAR(255),
    body                TEXT NOT NULL,
    payload             JSONB,
    
    -- Status
    status              VARCHAR(20) DEFAULT 'pending',
    retry_count         INT DEFAULT 0,
    scheduled_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    sent_at             TIMESTAMP WITH TIME ZONE,
    failure_reason      TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_notif_status ON notification_queue(status, scheduled_at);


-- ===========================================
-- D. WEBHOOKS / INTEGRATIONS
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    advertiser_id       UUID REFERENCES advertisers(id),
    
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['conversion.received', 'campaign.paused']
    
    is_active           BOOLEAN DEFAULT TRUE,
    failure_count       INT DEFAULT 0,
    
    created_by_id       UUID,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_deliveries (
    id                  BIGSERIAL PRIMARY KEY,
    subscription_id     UUID NOT NULL REFERENCES webhook_subscriptions(id),
    event_type          VARCHAR(100) NOT NULL,
    payload             JSONB NOT NULL,
    response_code       INT,
    response_time_ms    INT,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- E. API KEYS / RATE LIMITING
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    advertiser_id       UUID REFERENCES advertisers(id),
    
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,  -- ['read:campaigns', 'write:reports']
    
    rate_limit_rpm      INT DEFAULT 1000,
    rate_limit_daily    INT DEFAULT 100000,
    
    is_active           BOOLEAN DEFAULT TRUE,
    last_used_at        TIMESTAMP WITH TIME ZONE,
    expires_at          TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_api_key_hash ON api_keys(key_hash);


-- ===========================================
-- F. OAUTH / SSO
-- ===========================================

CREATE TABLE oauth_providers (
    id                  SERIAL PRIMARY KEY,
    provider_type       VARCHAR(50) NOT NULL,  -- 'google', 'okta', 'azure_ad'
    name                VARCHAR(100) NOT NULL,
    client_id           VARCHAR(255) NOT NULL,
    client_secret_enc   BYTEA NOT NULL,
    issuer_url          VARCHAR(500),
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE user_oauth_links (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    provider_id         INT NOT NULL REFERENCES oauth_providers(id),
    external_id         VARCHAR(255) NOT NULL,
    access_token_enc    BYTEA,
    refresh_token_enc   BYTEA,
    token_expires_at    TIMESTAMP WITH TIME ZONE,
    last_login_at       TIMESTAMP WITH TIME ZONE,
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
    device_type         VARCHAR(50),
    ip_address          INET NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_activity_at    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_session_user ON user_sessions(user_id);
CREATE INDEX idx_session_token ON user_sessions(token_hash);


-- ===========================================
-- H. FEATURE FLAGS
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    description         TEXT,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    allowed_advertiser_ids UUID[],
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
ADTECH: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. RTB LATENCY (THE 100MS DEADLINE)
============================================================

THE CHALLENGE:
Bid Request arrives -> We must decide "Bid/NoBid" and "Price" -> Send Response.
Total Budget: 100ms. Network RTT: 20ms. App Logic: 80ms.

DATABASE STRATEGY:
- **No SQL in Critical Path**: PostgreSQL is too slow (5-10ms query + connection overhead).
- **Aerospike / Redis**: Used for User Profile/Budget lookups (sub-millisecond).
- **Embedded Caching**: "Campaign Context" loaded into application memory (Heap).

HOT CAMPAIGN CACHING:
- Top 1000 campaigns loaded in `ConcurrentHashMap` on all bidders.
- Broadcast updates via UDP/gossip protocol or Redis PubSub when budget exhausted.

============================================================
2. BUDGET PACING (DISTRIBUTED COUNTING)
============================================================

THE CHALLENGE:
Client budget: $1000/day.
Throughput: 100k requests/sec across 500 servers.
Risk: "Overspend". We spend $5000 in 1 second before servers sync.

SOLUTION: TOKEN BUCKET with HIERARCHICAL SYNC
1. **Global Allocator (Redis)**: Holds $1000.
2. **Local Allocator (Bidder Node)**: Requests $10 slice from Global.
3. Bidder spends from local $10 slice.
4. When empty, Request another $10.
5. End of Day: "Smooth Pacing" -> artificially slow down token distribution.

============================================================
3. CLICK FRAUD DETECTION (STREAM PROCESSING)
============================================================

THE PATTERNS:
- "Click Farms": 100 clicks from same IP.
- "Botnet": Random IPs, but inhuman timing (1ms duration).

IMPLEMENTATION (Flink/Kafka Streams):
- **Windowed Aggregation**: "Count clicks per IP per 5 min".
- **Bloom Filter**: Check "Is this IP on blacklist?".
- **Action**: If Fraud Detected -> Write to `blocked_ips` Redis set immediately. Next bid request rejected.

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Bid Response Latency (p99)   │ < 80ms  │ > 90ms = PAGE   │
│  Win Rate (Wins / Bids)       │ > 10%   │ < 5% = WARN     │
│  Budget Overspend             │ < 1%    │ > 5% = PAGE     │
│  QPS Drop                     │ N/A     │ -20% = PAGE     │
└─────────────────────────────────────────────────────────────┘

INFRASTRUCTURE METRICS:
- `kafka_end_to_end_latency`: Time from Impression -> Reporting DB.
- `redis_evictions`: DO NOT Evict budget keys (Use `volatile-lru` only on user profiles).

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: REPORTING DB DELAY
Symptom: Advertisers don't see spend update for 4 hours.
Mitigation:
- "Lambda Architecture": Real-time view (Redis/Druid) + Batch view (Postgres/Redshift).
- Show "Estimated Spend" overlay based on bidder telemetry.

SCENARIO 2: ZOMBIE BIDDERS
Symptom: Server disconnected from Redis, keeps bidding infinite money.
Mitigation:
- "Dead Man Switch": Bidder must ping Central Authority every 5s. If ping fails, stop bidding.
- "Max Bid Cap": Hardcoded limit ($100) per campaign per minute in local memory.

SCENARIO 3: CREATIVE QUALITY REJECTION
Symptom: Publisher blocks our ads (malware detected).
Mitigation:
- Pre-Scanning Pipeline: All uploaded images scanned by 3rd party (e.g., The Media Trust).
- Circuit Breaker: If domain X bans us, stop bidding on domain X for 1 hour.

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

DATA RETENTION:
- "Log Level Data" (Every impression row): Keep 30 days (S3 Parquet). Expensive.
- "Aggregated Data" (Daily Spend/Clics): Keep 10 years (Postgres). Cheap.

SPOT INSTANCES (BIDDERS):
- Bidders are stateless.
- Strategy: Run 90% on Spot Fleet. 
- Handling Termination: 2-minute warning -> Drain logic (stop accepting new reqs, flush logs).
```

---

## 🔗 Related Documents

- [Stripe Schema](./stripe-schema-design-guide.md) — Billing integration
- [Database Scaling](./database-scaling-guide.md) — Partitioning patterns
- [Consistent Hashing](../system-design-notes/consistent-hashing-guide.md) — Event distribution
- [Healthcare Schema](./healthcare-schema-design-guide.md) — Similar audit patterns
