# CRM Platform: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Accounts, Contacts, Leads, Opportunities, Activities, Sales Pipeline — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Querying all opportunities for pipeline reports. Pre-aggregate by stage/owner. Real-time pipeline = Redis counters.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Salesforce Multi-Tenancy](https://developer.salesforce.com/wiki/multi_tenant_architecture) | Multi-tenant patterns |
| [HubSpot Architecture](https://www.hubspot.com/product-updates) | Modern CRM design |
| [Lead Scoring Models](https://en.wikipedia.org/wiki/Lead_scoring) | ML for sales |

---

## 🎯 The Principal Laws of CRM Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Multi-Tenant** | Many orgs, one database | org_id on every table |
| **Law 2: Everything Is an Activity** | Calls, emails, meetings | Unified activity stream |
| **Law 3: Pipeline Is Pre-computed** | Can't SUM on every request | Materialized aggregates |
| **Law 4: Custom Fields** | Every org has different fields | EAV or JSONB pattern |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get contact details | 10M/s | < 30ms | PostgreSQL + Cache |
| 2 | Get account with contacts | 5M/s | < 50ms | PostgreSQL |
| 3 | Get my opportunities | 5M/s | < 100ms | PostgreSQL |
| 4 | Update opportunity stage | 1M/s | < 200ms | PostgreSQL |
| 5 | Get pipeline summary | 1M/s | < 50ms | Redis (pre-computed) |
| 6 | Log activity | 5M/s | < 200ms | PostgreSQL |
| 7 | Search contacts | 1M/s | < 200ms | Elasticsearch |
| 8 | Get activity feed | 2M/s | < 100ms | PostgreSQL |
| 9 | Lead assignment | 500K/s | < 500ms | PostgreSQL + Rules |
| 10 | Generate forecast | 100K/s | < 1s | Pre-computed |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    CRM DATA ARCHITECTURE                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                               │
│  ✓ Multi-tenant    ✓ Accounts/Contacts   ✓ Opportunities        │
│                                                                  │
│  • organizations (tenants)                                       │
│  • accounts, contacts                                            │
│  • leads, opportunities                                          │
│  • activities (calls, emails, meetings)                          │
│  • custom_fields, custom_field_values                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Pipeline metrics    ✓ Lead scores   ✓ Session cache          │
│                                                                  │
│  • pipeline:{org_id}:{owner_id}                                  │
│  • lead_score:{lead_id}                                          │
│  • forecast:{org_id}:{period}                                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Elasticsearch                            │
│  ✓ Contact search    ✓ Account search   ✓ Full-text            │
│                                                                  │
│  • contacts, accounts, leads, opportunities                      │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- CRM SCHEMA: PostgreSQL Production DDL
-- Version: Multi-tenant CRM with sales pipeline
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";


-- ===========================================
-- SECTION 1: ORGANIZATIONS (Tenants)
-- ===========================================

CREATE TYPE org_plan AS ENUM ('free', 'starter', 'professional', 'enterprise');

CREATE TABLE organizations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    name                VARCHAR(255) NOT NULL,
    subdomain           VARCHAR(50) NOT NULL UNIQUE,  -- acme.crm.com
    
    -- Plan
    plan                org_plan DEFAULT 'free',
    
    -- Settings
    default_currency    VARCHAR(3) DEFAULT 'USD',
    fiscal_year_start   INT DEFAULT 1,  -- Month 1-12
    
    -- Limits
    user_limit          INT,
    storage_limit_gb    INT,
    
    -- Billing
    stripe_customer_id  VARCHAR(50),
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- SECTION 2: USERS
-- ===========================================

CREATE TYPE user_role AS ENUM ('admin', 'manager', 'sales_rep', 'read_only');

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL REFERENCES organizations(id),
    
    -- Auth
    email               VARCHAR(255) NOT NULL,
    password_hash       TEXT,
    
    -- Profile
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    title               VARCHAR(100),
    phone               VARCHAR(20),
    avatar_url          TEXT,
    
    -- Role
    role                user_role DEFAULT 'sales_rep',
    
    -- Manager (for hierarchy)
    manager_id          UUID REFERENCES users(id),
    
    -- Quota (for sales forecasting)
    monthly_quota       BIGINT,  -- In cents
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_user_email UNIQUE (org_id, email)
);

CREATE INDEX idx_users_org ON users(org_id);
CREATE INDEX idx_users_manager ON users(manager_id);


-- ===========================================
-- SECTION 3: ACCOUNTS (Companies)
-- ===========================================

CREATE TYPE account_type AS ENUM ('prospect', 'customer', 'partner', 'competitor', 'other');

CREATE TABLE accounts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL REFERENCES organizations(id),
    
    -- Basic info
    name                VARCHAR(255) NOT NULL,
    website             VARCHAR(255),
    industry            VARCHAR(100),
    
    -- Type and size
    account_type        account_type DEFAULT 'prospect',
    employee_count      INT,
    annual_revenue      BIGINT,  -- In cents
    
    -- Address
    billing_address     JSONB,
    shipping_address    JSONB,
    
    -- Contact
    phone               VARCHAR(20),
    
    -- Owner
    owner_id            UUID REFERENCES users(id),
    
    -- Parent account (for subsidiaries)
    parent_account_id   UUID REFERENCES accounts(id),
    
    -- Engagement
    last_activity_at    TIMESTAMP WITH TIME ZONE,
    
    -- Custom fields
    custom_fields       JSONB DEFAULT '{}',
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_accounts_org ON accounts(org_id);
CREATE INDEX idx_accounts_owner ON accounts(owner_id);
CREATE INDEX idx_accounts_name ON accounts(org_id, name);
CREATE INDEX idx_accounts_name_trgm ON accounts USING GIN (name gin_trgm_ops);


-- ===========================================
-- SECTION 4: CONTACTS
-- ===========================================

CREATE TABLE contacts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL REFERENCES organizations(id),
    account_id          UUID REFERENCES accounts(id),
    
    -- Name
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    
    -- Title
    title               VARCHAR(100),
    department          VARCHAR(100),
    
    -- Contact info
    email               VARCHAR(255),
    phone               VARCHAR(20),
    mobile              VARCHAR(20),
    
    -- Address
    mailing_address     JSONB,
    
    -- Owner
    owner_id            UUID REFERENCES users(id),
    
    -- Lead source
    lead_source         VARCHAR(100),
    
    -- Engagement
    last_activity_at    TIMESTAMP WITH TIME ZONE,
    
    -- Email preferences
    email_opt_out       BOOLEAN DEFAULT FALSE,
    
    -- Custom fields
    custom_fields       JSONB DEFAULT '{}',
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_contacts_org ON contacts(org_id);
CREATE INDEX idx_contacts_account ON contacts(account_id);
CREATE INDEX idx_contacts_owner ON contacts(owner_id);
CREATE INDEX idx_contacts_email ON contacts(org_id, email);
CREATE INDEX idx_contacts_name ON contacts(org_id, last_name, first_name);


-- ===========================================
-- SECTION 5: LEADS
-- ===========================================

CREATE TYPE lead_status AS ENUM (
    'new', 'contacted', 'qualified', 'unqualified', 'converted'
);

CREATE TABLE leads (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL REFERENCES organizations(id),
    
    -- Name
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    
    -- Company
    company             VARCHAR(255),
    title               VARCHAR(100),
    
    -- Contact
    email               VARCHAR(255),
    phone               VARCHAR(20),
    
    -- Address
    address             JSONB,
    
    -- Source
    lead_source         VARCHAR(100),
    
    -- Status
    status              lead_status DEFAULT 'new',
    
    -- Owner
    owner_id            UUID REFERENCES users(id),
    
    -- Scoring
    lead_score          INT DEFAULT 0,
    
    -- Conversion
    converted_at        TIMESTAMP WITH TIME ZONE,
    converted_account_id UUID REFERENCES accounts(id),
    converted_contact_id UUID REFERENCES contacts(id),
    converted_opportunity_id UUID,
    
    -- Campaign
    campaign_id         UUID,
    
    -- Custom fields
    custom_fields       JSONB DEFAULT '{}',
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_leads_org ON leads(org_id);
CREATE INDEX idx_leads_owner ON leads(owner_id);
CREATE INDEX idx_leads_status ON leads(org_id, status);
CREATE INDEX idx_leads_email ON leads(org_id, email);


-- ===========================================
-- SECTION 6: OPPORTUNITIES (Deals)
-- ===========================================

CREATE TYPE opportunity_stage AS ENUM (
    'prospecting',
    'qualification',
    'needs_analysis',
    'proposal',
    'negotiation',
    'closed_won',
    'closed_lost'
);

CREATE TABLE opportunities (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL REFERENCES organizations(id),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    
    -- Name
    name                VARCHAR(255) NOT NULL,
    
    -- Value
    amount              BIGINT,  -- In cents
    currency            VARCHAR(3) DEFAULT 'USD',
    
    -- Stage
    stage               opportunity_stage DEFAULT 'prospecting',
    probability         INT DEFAULT 0,  -- 0-100%
    
    -- Dates
    close_date          DATE,
    
    -- Owner
    owner_id            UUID NOT NULL REFERENCES users(id),
    
    -- Source
    lead_source         VARCHAR(100),
    
    -- Primary contact
    primary_contact_id  UUID REFERENCES contacts(id),
    
    -- Next step
    next_step           TEXT,
    
    -- If closed
    closed_at           TIMESTAMP WITH TIME ZONE,
    close_reason        TEXT,
    competitor          VARCHAR(255),  -- If lost to competitor
    
    -- Engagement
    last_activity_at    TIMESTAMP WITH TIME ZONE,
    
    -- Custom fields
    custom_fields       JSONB DEFAULT '{}',
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_opps_org ON opportunities(org_id);
CREATE INDEX idx_opps_account ON opportunities(account_id);
CREATE INDEX idx_opps_owner ON opportunities(owner_id);
CREATE INDEX idx_opps_stage ON opportunities(org_id, stage);
CREATE INDEX idx_opps_close_date ON opportunities(close_date);
CREATE INDEX idx_opps_pipeline ON opportunities(org_id, owner_id, stage) 
    WHERE stage NOT IN ('closed_won', 'closed_lost');


-- Opportunity line items (products)
CREATE TABLE opportunity_line_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id      UUID NOT NULL REFERENCES opportunities(id),
    
    product_name        VARCHAR(255) NOT NULL,
    quantity            INT DEFAULT 1,
    unit_price          BIGINT NOT NULL,
    total_price         BIGINT NOT NULL,
    discount_percent    DECIMAL(5,2) DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_line_items_opp ON opportunity_line_items(opportunity_id);


-- ===========================================
-- SECTION 7: ACTIVITIES (Unified)
-- ===========================================

CREATE TYPE activity_type AS ENUM (
    'call', 'email', 'meeting', 'task', 'note', 'event'
);

CREATE TYPE activity_status AS ENUM (
    'not_started', 'in_progress', 'completed', 'waiting', 'deferred'
);

CREATE TABLE activities (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL REFERENCES organizations(id),
    
    -- Type
    activity_type       activity_type NOT NULL,
    
    -- Subject
    subject             VARCHAR(255) NOT NULL,
    description         TEXT,
    
    -- Status
    status              activity_status DEFAULT 'not_started',
    
    -- Timing
    due_date            TIMESTAMP WITH TIME ZONE,
    completed_at        TIMESTAMP WITH TIME ZONE,
    
    -- For calls
    call_duration_sec   INT,
    call_outcome        VARCHAR(50),  -- 'connected', 'voicemail', 'no_answer'
    
    -- For emails
    email_message_id    VARCHAR(255),
    email_direction     VARCHAR(10),  -- 'inbound', 'outbound'
    
    -- For meetings
    meeting_start       TIMESTAMP WITH TIME ZONE,
    meeting_end         TIMESTAMP WITH TIME ZONE,
    meeting_location    TEXT,
    
    -- Owner/assigned to
    owner_id            UUID REFERENCES users(id),
    assigned_to_id      UUID REFERENCES users(id),
    
    -- Related records (polymorphic)
    related_to_type     VARCHAR(50),  -- 'account', 'contact', 'lead', 'opportunity'
    related_to_id       UUID,
    
    -- Additional related contact
    contact_id          UUID REFERENCES contacts(id),
    
    -- Priority
    priority            VARCHAR(20) DEFAULT 'normal',  -- 'high', 'normal', 'low'
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_activities_org ON activities(org_id);
CREATE INDEX idx_activities_owner ON activities(owner_id);
CREATE INDEX idx_activities_related ON activities(related_to_type, related_to_id);
CREATE INDEX idx_activities_due ON activities(due_date) WHERE status != 'completed';
CREATE INDEX idx_activities_type ON activities(org_id, activity_type);


-- ===========================================
-- SECTION 8: PIPELINE STAGES (Customizable)
-- ===========================================

CREATE TABLE pipeline_stages (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL REFERENCES organizations(id),
    
    name                VARCHAR(100) NOT NULL,
    stage_order         INT NOT NULL,
    probability         INT DEFAULT 0,  -- Default probability
    
    -- Is this a closed stage?
    is_closed           BOOLEAN DEFAULT FALSE,
    is_won              BOOLEAN DEFAULT FALSE,
    
    -- Forecast category
    forecast_category   VARCHAR(50),  -- 'pipeline', 'best_case', 'commit', 'closed'
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_stages_org ON pipeline_stages(org_id);


-- ===========================================
-- SECTION 9: CUSTOM FIELDS (EAV Pattern)
-- ===========================================

CREATE TYPE custom_field_type AS ENUM (
    'text', 'number', 'currency', 'date', 'datetime', 
    'checkbox', 'picklist', 'multi_picklist', 'lookup', 'url', 'email'
);

CREATE TABLE custom_field_definitions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL REFERENCES organizations(id),
    
    -- Which object this field belongs to
    object_type         VARCHAR(50) NOT NULL,  -- 'account', 'contact', 'lead', 'opportunity'
    
    -- Field info
    field_name          VARCHAR(100) NOT NULL,
    field_label         VARCHAR(255) NOT NULL,
    field_type          custom_field_type NOT NULL,
    
    -- For picklists
    picklist_values     JSONB,
    
    -- Validation
    is_required         BOOLEAN DEFAULT FALSE,
    default_value       TEXT,
    
    -- Help text
    help_text           TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_custom_field UNIQUE (org_id, object_type, field_name)
);

CREATE INDEX idx_custom_fields_org ON custom_field_definitions(org_id, object_type);
```

---

# Part 4: Pipeline Aggregation (Redis)

```python
# ============================================================
# CRM PIPELINE METRICS (Redis)
# ============================================================

import redis
from typing import Dict

class PipelineMetrics:
    """
    Pre-computed pipeline metrics for fast dashboard loads.
    """
    def __init__(self):
        self.redis = redis.Redis()
    
    def update_pipeline_stats(self, org_id: str, owner_id: str):
        """
        Called when opportunity stage/amount changes.
        Recalculate pipeline for this owner.
        """
        # In production, this would query PostgreSQL
        # and update Redis atomically
        
        key = f"pipeline:{org_id}:{owner_id}"
        
        # Example structure
        pipeline = {
            "prospecting": {"count": 5, "value": 250000},
            "qualification": {"count": 8, "value": 480000},
            "proposal": {"count": 3, "value": 150000},
            "negotiation": {"count": 2, "value": 100000},
            "total_open": {"count": 18, "value": 980000},
            "weighted": 294000,  # Sum of (value × probability)
        }
        
        self.redis.hmset(key, {k: str(v) for k, v in pipeline.items()})
        self.redis.expire(key, 3600)  # 1 hour TTL
    
    def get_pipeline(self, org_id: str, owner_id: str) -> Dict:
        """Get pipeline summary for a sales rep."""
        key = f"pipeline:{org_id}:{owner_id}"
        data = self.redis.hgetall(key)
        
        if not data:
            # Cache miss - recalculate
            self.update_pipeline_stats(org_id, owner_id)
            data = self.redis.hgetall(key)
        
        return {k.decode(): v.decode() for k, v in data.items()}
    
    def get_team_pipeline(self, org_id: str, manager_id: str) -> Dict:
        """Aggregate pipeline for a manager's team."""
        # Get all team members under this manager
        # Aggregate their individual pipelines
        pass
```

---

# Part 5: Lead Assignment Rules

```sql
-- Round-robin lead assignment
CREATE OR REPLACE FUNCTION assign_lead_round_robin(
    p_org_id UUID,
    p_lead_id UUID
) RETURNS UUID AS $$
DECLARE
    v_next_owner_id UUID;
BEGIN
    -- Get next sales rep in rotation
    WITH rotation AS (
        SELECT u.id, 
               ROW_NUMBER() OVER (ORDER BY 
                   COALESCE(
                       (SELECT MAX(assigned_at) 
                        FROM lead_assignments 
                        WHERE owner_id = u.id),
                       '1970-01-01'::TIMESTAMP
                   )
               ) AS rn
        FROM users u
        WHERE u.org_id = p_org_id
          AND u.role = 'sales_rep'
          AND u.is_active = TRUE
    )
    SELECT id INTO v_next_owner_id
    FROM rotation
    WHERE rn = 1;
    
    -- Assign lead
    UPDATE leads 
    SET owner_id = v_next_owner_id,
        updated_at = NOW()
    WHERE id = p_lead_id;
    
    -- Log assignment
    INSERT INTO lead_assignments (lead_id, owner_id, assigned_at)
    VALUES (p_lead_id, v_next_owner_id, NOW());
    
    RETURN v_next_owner_id;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE lead_assignments (
    id                  BIGSERIAL PRIMARY KEY,
    lead_id             UUID NOT NULL REFERENCES leads(id),
    owner_id            UUID NOT NULL REFERENCES users(id),
    assigned_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_assignments_owner ON lead_assignments(owner_id, assigned_at DESC);
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Multi-tenant by org_id | org_id on every table |
| 2 | Pipeline pre-computed | Redis hash by owner |
| 3 | Unified activities | Single table for calls/emails/meetings |
| 4 | Custom fields via JSONB | custom_fields column |
| 5 | Lead scoring | lead_score INT |
| 6 | Round-robin assignment | Function with rotation |
| 7 | Opportunity line items | Products on deals |
| 8 | Manager hierarchy | users.manager_id |

---

# Part 6: DynamoDB Single-Table Design

```
============================================================
CRM: DynamoDB Single-Table Design
Multi-tenant SaaS CRM
============================================================

TABLE: crm_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (cross-org queries, owner queries)
- GSI2: GSI2PK / GSI2SK (email lookups, status queries)

============================================================
ENTITY PATTERNS
============================================================

ORGANIZATION
  PK: ORG#{org_id}
  SK: PROFILE
  
  Attributes: name, subdomain, plan, default_currency, user_limit

USER
  PK: ORG#{org_id}
  SK: USER#{user_id}
  GSI1PK: ORG#{org_id}#ROLE#{role}
  GSI1SK: USER#{user_id}
  GSI2PK: EMAIL#{email}
  GSI2SK: ORG#{org_id}
  
  Attributes: email, first_name, last_name, role, manager_id, quota

ACCOUNT
  PK: ORG#{org_id}
  SK: ACCT#{account_id}
  GSI1PK: ORG#{org_id}#OWNER#{owner_id}
  GSI1SK: ACCT#{account_id}
  GSI2PK: ORG#{org_id}#ACCTTYPE#{account_type}
  GSI2SK: NAME#{name}
  
  Attributes: name, website, industry, account_type, owner_id, 
              annual_revenue, custom_fields

CONTACT
  PK: ORG#{org_id}#ACCT#{account_id}
  SK: CONTACT#{contact_id}
  GSI1PK: ORG#{org_id}#OWNER#{owner_id}
  GSI1SK: CONTACT#{contact_id}
  GSI2PK: ORG#{org_id}#EMAIL#{email}
  GSI2SK: CONTACT#{contact_id}
  
  Attributes: first_name, last_name, email, phone, title, owner_id

LEAD
  PK: ORG#{org_id}
  SK: LEAD#{lead_id}
  GSI1PK: ORG#{org_id}#OWNER#{owner_id}
  GSI1SK: STATUS#{status}#LEAD#{lead_id}
  GSI2PK: ORG#{org_id}#LEADSTATUS#{status}
  GSI2SK: SCORE#{lead_score}#LEAD#{lead_id}
  
  Attributes: first_name, last_name, company, email, phone,
              status, lead_score, owner_id, lead_source

OPPORTUNITY
  PK: ORG#{org_id}#ACCT#{account_id}
  SK: OPP#{opportunity_id}
  GSI1PK: ORG#{org_id}#OWNER#{owner_id}
  GSI1SK: STAGE#{stage}#CLOSE#{close_date}
  GSI2PK: ORG#{org_id}#PIPELINE
  GSI2SK: STAGE#{stage}#AMT#{amount}
  
  Attributes: name, amount, stage, probability, close_date,
              owner_id, primary_contact_id, next_step

ACTIVITY
  PK: ORG#{org_id}
  SK: ACTIVITY#{activity_id}
  GSI1PK: ORG#{org_id}#RELATED#{related_to_type}#{related_to_id}
  GSI1SK: DATE#{created_at}
  GSI2PK: ORG#{org_id}#OWNER#{owner_id}#DUE
  GSI2SK: DATE#{due_date}
  
  Attributes: activity_type, subject, status, due_date, owner_id,
              related_to_type, related_to_id

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get all users in org
   Table: PK=ORG#{org_id}, SK begins_with "USER#"

2. Get user by email (login)
   GSI2: PK=EMAIL#{email}

3. Get account with all contacts
   Table: PK=ORG#{org_id}#ACCT#{account_id}

4. Get my accounts (owner query)
   GSI1: PK=ORG#{org_id}#OWNER#{owner_id}, SK begins_with "ACCT#"

5. Get my leads by status
   GSI1: PK=ORG#{org_id}#OWNER#{owner_id}, SK begins_with STATUS#{status}

6. Get my opportunities (pipeline view)
   GSI1: PK=ORG#{org_id}#OWNER#{owner_id}, SK begins_with "STAGE#"

7. Get activities for record (timeline)
   GSI1: PK=ORG#{org_id}#RELATED#{type}#{id}

8. Get my tasks due soon
   GSI2: PK=ORG#{org_id}#OWNER#{owner_id}#DUE, SK between DATE#{today} and DATE#{next_week}

9. Pipeline by stage (for dashboard)
   GSI2: PK=ORG#{org_id}#PIPELINE, SK begins_with "STAGE#"
```

---

# Part 7: Query Examples with EXPLAIN

```sql
-- ============================================================
-- CRM QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Sales Rep Pipeline Dashboard
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    stage,
    COUNT(*) AS deal_count,
    SUM(amount) AS total_value,
    SUM(amount * probability / 100) AS weighted_value,
    AVG(CURRENT_DATE - created_at::date) AS avg_age_days
FROM opportunities
WHERE org_id = $1
  AND owner_id = $2
  AND stage NOT IN ('closed_won', 'closed_lost')
GROUP BY stage
ORDER BY 
    CASE stage
        WHEN 'prospecting' THEN 1
        WHEN 'qualification' THEN 2
        WHEN 'needs_analysis' THEN 3
        WHEN 'proposal' THEN 4
        WHEN 'negotiation' THEN 5
    END;

-- Expected: Index scan on idx_opps_pipeline, ~5ms


-- ===========================================
-- QUERY 2: Account 360 View
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    a.*,
    (
        SELECT json_agg(jsonb_build_object(
            'id', c.id,
            'name', c.first_name || ' ' || c.last_name,
            'title', c.title,
            'email', c.email
        ))
        FROM contacts c WHERE c.account_id = a.id
    ) AS contacts,
    (
        SELECT json_agg(jsonb_build_object(
            'id', o.id,
            'name', o.name,
            'amount', o.amount,
            'stage', o.stage,
            'close_date', o.close_date
        ))
        FROM opportunities o 
        WHERE o.account_id = a.id 
          AND o.stage NOT IN ('closed_won', 'closed_lost')
    ) AS open_opportunities,
    (
        SELECT SUM(amount) FROM opportunities o
        WHERE o.account_id = a.id AND o.stage = 'closed_won'
    ) AS total_won,
    (
        SELECT json_agg(jsonb_build_object(
            'type', act.activity_type,
            'subject', act.subject,
            'date', act.created_at
        ) ORDER BY act.created_at DESC)
        FROM (
            SELECT * FROM activities 
            WHERE related_to_type = 'account' AND related_to_id = a.id
            ORDER BY created_at DESC LIMIT 10
        ) act
    ) AS recent_activities
FROM accounts a
WHERE a.id = $1 AND a.org_id = $2;

-- Expected: ~10ms with proper indices


-- ===========================================
-- QUERY 3: Lead Scoring Candidates
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    l.*,
    (SELECT COUNT(*) FROM activities 
     WHERE related_to_type = 'lead' AND related_to_id = l.id
     AND activity_type = 'email') AS email_count,
    (SELECT COUNT(*) FROM activities 
     WHERE related_to_type = 'lead' AND related_to_id = l.id
     AND activity_type IN ('call', 'meeting')) AS engagement_count
FROM leads l
WHERE l.org_id = $1
  AND l.status IN ('new', 'contacted')
  AND l.created_at >= NOW() - INTERVAL '30 days'
ORDER BY l.lead_score DESC, l.created_at DESC
LIMIT 50;

-- Expected: ~15ms


-- ===========================================
-- QUERY 4: Quarterly Forecast
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
WITH quarter_opps AS (
    SELECT 
        o.*,
        u.first_name || ' ' || u.last_name AS owner_name,
        u.manager_id
    FROM opportunities o
    JOIN users u ON u.id = o.owner_id
    WHERE o.org_id = $1
      AND o.close_date >= DATE_TRUNC('quarter', CURRENT_DATE)
      AND o.close_date < DATE_TRUNC('quarter', CURRENT_DATE) + INTERVAL '3 months'
      AND o.stage NOT IN ('closed_lost')
)
SELECT 
    owner_id,
    owner_name,
    SUM(CASE WHEN stage = 'closed_won' THEN amount ELSE 0 END) AS closed,
    SUM(CASE WHEN stage IN ('negotiation', 'proposal') THEN amount ELSE 0 END) AS commit,
    SUM(CASE WHEN stage IN ('needs_analysis', 'qualification') THEN amount ELSE 0 END) AS best_case,
    SUM(CASE WHEN stage = 'prospecting' THEN amount ELSE 0 END) AS pipeline,
    SUM(amount * probability / 100) AS weighted_total
FROM quarter_opps
GROUP BY owner_id, owner_name
ORDER BY closed DESC;

-- Expected: ~20ms for quarter data


-- ===========================================
-- QUERY 5: Activity Feed for Record
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    a.id,
    a.activity_type,
    a.subject,
    a.description,
    a.status,
    a.created_at,
    u.first_name || ' ' || u.last_name AS created_by,
    CASE a.activity_type
        WHEN 'call' THEN jsonb_build_object(
            'duration', a.call_duration_sec,
            'outcome', a.call_outcome
        )
        WHEN 'meeting' THEN jsonb_build_object(
            'start', a.meeting_start,
            'end', a.meeting_end,
            'location', a.meeting_location
        )
        ELSE '{}'::jsonb
    END AS details
FROM activities a
JOIN users u ON u.id = a.owner_id
WHERE a.org_id = $1
  AND a.related_to_type = $2
  AND a.related_to_id = $3
ORDER BY a.created_at DESC
LIMIT 50;

-- Expected: ~5ms with idx_activities_related


-- ===========================================
-- QUERY 6: Search Contacts (Fuzzy)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    c.id,
    c.first_name,
    c.last_name,
    c.email,
    c.title,
    a.name AS account_name,
    similarity(c.first_name || ' ' || c.last_name, $2) AS name_score
FROM contacts c
LEFT JOIN accounts a ON a.id = c.account_id
WHERE c.org_id = $1
  AND (
    c.first_name || ' ' || c.last_name ILIKE '%' || $2 || '%'
    OR c.email ILIKE '%' || $2 || '%'
    OR c.first_name || ' ' || c.last_name % $2  -- Trigram similarity
  )
ORDER BY name_score DESC
LIMIT 20;

-- Expected: ~30ms with GIN trigram index
```

---

# Part 8: Capacity Planning

```
============================================================
CRM CAPACITY PLANNING
============================================================

ASSUMPTIONS (Salesforce-scale):
- 100,000 organizations (tenants)
- Avg 50 users per org = 5M users
- Avg 1,000 accounts per org = 100M accounts
- Avg 5 contacts per account = 500M contacts
- Avg 500 opportunities per org = 50M opportunities
- 10 activities per day per user = 18B activities/year

============================================================
TABLE SIZE ESTIMATES
============================================================

ORGANIZATIONS
  Rows: 100K
  Row Size: ~500 bytes
  Total: ~50 MB

USERS
  Rows: 5M
  Row Size: ~400 bytes
  Total: ~2 GB

ACCOUNTS
  Rows: 100M
  Row Size: ~600 bytes
  Total: ~60 GB

CONTACTS
  Rows: 500M
  Row Size: ~500 bytes
  Total: ~250 GB

LEADS
  Rows: 200M (many converted/archived)
  Row Size: ~500 bytes
  Total: ~100 GB

OPPORTUNITIES
  Rows: 50M
  Row Size: ~600 bytes
  Total: ~30 GB

ACTIVITIES
  Rows: 18B (partitioned by year, archived after 2 years)
  Active: 36B events over 2 years
  Row Size: ~400 bytes
  Active Total: ~1.4 TB
  Archived: Moved to S3/Glacier

CUSTOM_FIELD_DEFINITIONS
  Rows: 100K orgs × 50 fields avg = 5M
  Total: ~500 MB

============================================================
TOTAL STORAGE
============================================================

| Table | Size | Partitioned | Sharding |
|-------|------|-------------|----------|
| Organizations | 50 MB | No | No |
| Users | 2 GB | No | By org_id |
| Accounts | 60 GB | No | By org_id |
| Contacts | 250 GB | No | By org_id |
| Leads | 100 GB | No | By org_id |
| Opportunities | 30 GB | No | By org_id |
| Activities | 1.4 TB | By year | By org_id |
| **TOTAL** | **~1.8 TB** | - | - |

+ Indexes (~40%): ~720 GB
+ Total with indexes: ~2.5 TB
+ Replicas (3x): ~7.5 TB cluster

============================================================
MULTI-TENANT SHARDING STRATEGY
============================================================

Shard Key: org_id (consistent hashing)

Shard Distribution:
  - 16 shards initially
  - Each shard: ~150 GB data
  - Large tenants: dedicated shard

Routing:
  shard_id = hash(org_id) % num_shards
  
  # Large tenant override
  if org_id in dedicated_shards:
      return dedicated_shards[org_id]

============================================================
REDIS CAPACITY
============================================================

Pipeline Cache:
  100K orgs × 50 users × 200 bytes = 1 GB

Session Data:
  1M concurrent sessions × 1 KB = 1 GB

Lead Scores:
  200M leads × 10 bytes = 2 GB

Search Cache:
  Recent queries, 1-hour TTL = 500 MB

TOTAL REDIS: ~5 GB (use 16 GB for headroom)

============================================================
SCALING THRESHOLDS
============================================================

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Tenant data > 10GB | > 50GB | Dedicated shard |
| QPS per shard > 5K | > 10K | Add shard |
| Activities table > 500GB | > 1TB | Increase partition frequency |
| Search p99 > 200ms | > 500ms | Add Elasticsearch nodes |
| Redis memory > 70% | > 90% | Scale cluster |

============================================================
COST ESTIMATES (AWS)
============================================================

PostgreSQL (Aurora Serverless v2):
  Base: 16 ACUs × $0.12/hr × 730 = $1,402/month
  Storage: 2.5TB × $0.10 = $250/month
  I/O: ~$200/month
  Total: ~$1,850/month

Redis (ElastiCache r6g.xlarge):
  3 nodes: $693/month

Elasticsearch (3x r6g.xlarge.search):
  $1,188/month

TOTAL: ~$3,700/month for mid-scale SaaS CRM
```

---

# Part 9: Anti-Patterns to Avoid

```
============================================================
CRM ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: No org_id on Every Query
-----------------------------------------
WRONG:
  SELECT * FROM accounts WHERE id = $1;
  -- What if user from Org A guesses Org B's account ID?
  
RIGHT:
  SELECT * FROM accounts WHERE id = $1 AND org_id = $2;
  -- Always filter by org_id for multi-tenant security


❌ ANTI-PATTERN 2: Computing Pipeline in Real-Time
-----------------------------------------
WRONG:
  SELECT stage, SUM(amount) FROM opportunities
  WHERE org_id = $1 GROUP BY stage;
  -- Called on every dashboard load!
  
RIGHT:
  -- Pre-compute in Redis on opportunity change
  pipeline_cache.set(f"pipeline:{org_id}:{owner_id}", stats)
  -- Dashboard reads from cache


❌ ANTI-PATTERN 3: Separate Tables for Each Activity Type
-----------------------------------------
WRONG:
  CREATE TABLE calls (...);
  CREATE TABLE emails (...);
  CREATE TABLE meetings (...);
  -- 6+ tables, complex unions for timeline
  
RIGHT:
  CREATE TABLE activities (
      activity_type activity_type,
      -- Type-specific fields nullable
      call_duration_sec INT,
      email_message_id TEXT,
      meeting_start TIMESTAMP,
      ...
  );
  -- Single table, single query for timeline


❌ ANTI-PATTERN 4: EAV for All Custom Fields
-----------------------------------------
WRONG:
  CREATE TABLE custom_field_values (
      object_id UUID,
      field_name TEXT,
      field_value TEXT
  );
  -- N+1 queries, complex JOINs
  
RIGHT:
  -- Use JSONB column on each entity
  custom_fields JSONB DEFAULT '{}',
  
  -- Query with JSON operators
  WHERE custom_fields->>'industry' = 'Tech'


❌ ANTI-PATTERN 5: No Index on org_id
-----------------------------------------
WRONG:
  CREATE TABLE opportunities (...);
  -- Queries always filter by org_id but no index
  
RIGHT:
  CREATE INDEX idx_opps_org ON opportunities(org_id);
  -- Or composite: idx_opps_org_owner ON opportunities(org_id, owner_id)


❌ ANTI-PATTERN 6: Polymorphic FK Without Type
-----------------------------------------
WRONG:
  related_to_id UUID,
  -- Could be account, contact, lead... but which table?
  
RIGHT:
  related_to_type VARCHAR(50),  -- 'account', 'contact', 'lead'
  related_to_id UUID,
  -- Index: (related_to_type, related_to_id)


❌ ANTI-PATTERN 7: Lead Conversion Loses Data
-----------------------------------------
WRONG:
  -- On conversion, delete lead
  DELETE FROM leads WHERE id = $1;
  
RIGHT:
  -- Mark as converted, link to created records
  UPDATE leads SET 
      status = 'converted',
      converted_at = NOW(),
      converted_account_id = $2,
      converted_contact_id = $3,
      converted_opportunity_id = $4
  WHERE id = $1;


❌ ANTI-PATTERN 8: No Manager Hierarchy
-----------------------------------------
WRONG:
  CREATE TABLE users (
      id UUID,
      org_id UUID,
      role VARCHAR(20)
      -- No way to build org chart
  );
  
RIGHT:
  CREATE TABLE users (
      id UUID,
      org_id UUID,
      role VARCHAR(20),
      manager_id UUID REFERENCES users(id),
      -- Enables roll-up reports, team views
  );


❌ ANTI-PATTERN 9: Pipeline Stages Hardcoded
-----------------------------------------
WRONG:
  stage VARCHAR(50),  -- 'Prospecting', 'Proposal', etc.
  -- Every org stuck with same stages
  
RIGHT:
  CREATE TABLE pipeline_stages (
      org_id UUID,
      name VARCHAR(100),
      stage_order INT,
      probability INT,
      is_won BOOLEAN
  );
  -- Each org customizes their sales process


❌ ANTI-PATTERN 10: No Soft Delete
-----------------------------------------
WRONG:
  DELETE FROM contacts WHERE id = $1;
  -- Gone forever, audit trail broken
  
RIGHT:
  is_deleted BOOLEAN DEFAULT FALSE,
  deleted_at TIMESTAMP,
  deleted_by UUID,
  
  -- All queries: WHERE is_deleted = FALSE
```

---

# Part 10: CDC & Disaster Recovery

```
============================================================
CRM CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (shards)    │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │Elasticsearch│   │ Analytics │   │ Redis     │  │ Webhooks │
  │ (search)    │   │ (BI)      │   │ (cache)   │  │ (integs) │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- crm.accounts (Partition by org_id)
- crm.contacts (Partition by org_id)
- crm.opportunities (Partition by org_id)
- crm.activities (Partition by org_id)
- crm.pipeline-events (For real-time dashboard)

============================================================
DISASTER RECOVERY
============================================================

MULTI-TENANT CONSIDERATIONS:
- Each tenant's data must be recoverable independently
- Large tenants on dedicated shards = faster recovery
- RPO: < 5 minutes
- RTO: < 1 hour

BACKUP STRATEGY:

Per-Shard:
  - Continuous WAL archiving to S3
  - Daily pg_basebackup
  - 30-day retention

Per-Tenant Export (for portability):
  - Weekly logical dump per org
  - Customer can request data export
  - GDPR compliance

FAILOVER:
  - Aurora: Automatic multi-AZ failover
  - Citus: Coordinator failover with HAProxy
  - Redis: Sentinel-managed failover

RECOVERY TESTING:
| Test | Frequency | Target RTO |
|------|-----------|------------|
| Shard failover | Weekly | < 2 min |
| Single tenant restore | Monthly | < 15 min |
| Full DR failover | Quarterly | < 1 hour |
| Cross-region failover | Annually | < 4 hours |
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- CRM: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / CHANGE HISTORY (Per-Tenant Partitioned)
-- ===========================================

CREATE TABLE entity_change_log (
    id                  BIGSERIAL,
    org_id              UUID NOT NULL,  -- Tenant isolation
    entity_type         VARCHAR(50) NOT NULL,  -- 'account', 'contact', 'opportunity'
    entity_id           UUID NOT NULL,
    field_name          VARCHAR(100) NOT NULL,
    old_value           TEXT,
    new_value           TEXT,
    changed_by_id       UUID NOT NULL,
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    change_source       VARCHAR(50),  -- 'ui', 'api', 'workflow', 'import'
    ip_address          INET,
    PRIMARY KEY (org_id, id)
) PARTITION BY LIST (org_id);

-- Per-tenant partitions for large customers
CREATE TABLE entity_change_log_default PARTITION OF entity_change_log DEFAULT;

CREATE INDEX idx_ecl_entity ON entity_change_log(org_id, entity_type, entity_id);


-- ===========================================
-- B. ATTACHMENTS / MEDIA STORAGE
-- ===========================================

CREATE TABLE attachments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL,
    entity_type         VARCHAR(50) NOT NULL,
    entity_id           UUID NOT NULL,
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    storage_bucket      VARCHAR(100) NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    uploaded_by_id      UUID NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_attach_entity ON attachments(org_id, entity_type, entity_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    org_id              UUID NOT NULL,
    user_id             UUID,
    channel             VARCHAR(20) NOT NULL,
    recipient           VARCHAR(255) NOT NULL,
    notification_type   VARCHAR(100) NOT NULL,  -- 'deal_won', 'task_assigned'
    subject             VARCHAR(255),
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
    org_id              UUID NOT NULL,
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['contact.created', 'deal.won']
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
-- E. API KEYS / RATE LIMITING
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id              UUID NOT NULL,
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 1000,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- F. OAUTH / SSO (Per-Tenant Configuration)
-- ===========================================

CREATE TABLE oauth_providers (
    id                  SERIAL PRIMARY KEY,
    org_id              UUID NOT NULL,  -- Each org can have own SSO
    provider_type       VARCHAR(50) NOT NULL,
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
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uk_user_provider UNIQUE (user_id, provider_id)
);


-- ===========================================
-- G. USER SESSIONS
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    org_id              UUID NOT NULL,
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_type         VARCHAR(50),
    ip_address          INET NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS (Per-Tenant)
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    allowed_org_ids     UUID[],
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
CRM: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. MULTI-TENANCY TUNING (RLS PERFORMANCE)
============================================================

THE CHALLENGE:
20,000 Tenants in one Postgres Cluster.
"Neighbor Noise": Tenant A runs a massive report, Tenant B's UI slows down.

ROW LEVEL SECURITY (RLS) INTERNALS:
- **Policy**: `CHECK (org_id = current_setting('app.current_org_id')::uuid)`
- **Performance Impact**: ~5-10% CPU overhead per query. Keys MUST include `org_id`.
- **Index Strategy**: Every index must be composite: `CREATE INDEX idx_leads_email ON leads(org_id, email)`. Brute force scan if `org_id` missing.

SCHEMA-PER-TENANT (ALTERNATIVE):
- Better isolation, but `pg_catalog` bloat limits to ~5000 schemas per DB.
- Use only for "Enterprise" tier tenants.

============================================================
2. CUSTOM OBJECT METADATA (THE "METADATA CACHE")
============================================================

THE CHALLENGE:
`custom_fields` table is queried on every single page load to render UI.
Postgres JOIN is expensive for Metadata.

SOLUTION: APPLICATION-SIDE CACHING
1. **Startup**: App loads all Metadata for Tenant into Heap.
2. **Versioned Cache**:
   - Redis Key: `metadata:{org_id}:hash`.
   - On Load: Check if hash matches local version.
   - If mismatch, fetch full definition from DB.
3. **Write Path**: Any schema change -> Publish "Invalidate" msg to Redis PubSub.

============================================================
3. SEARCH OPTIMIZATION (FUZZY MATCHING)
============================================================

THE CHALLENGE:
Sales rep searches "Jon Smit" -> Expects "John Smith".
Standard `LIKE '%Jon%'` is slow (Sequential Scan).

SOLUTION: TRIGRAM INDEXES (pg_trgm)
```sql
CREATE EXTENSION pg_trgm;
CREATE INDEX trgm_idx_leads_name ON leads USING GIST (name gist_trgm_ops);
```
- Effect: "Similarity Search" runs in milliseconds.
- Query: `SELECT * FROM leads WHERE name % 'Jon Smit' AND org_id = X`.

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  List View Load Time (p99)    │ < 1s    │ > 3s = WARN     │
│  Report Generation Time       │ < 10s   │ > 30s = WARN    │
│  API Rate Limit Rejection     │ < 1%    │ > 5% = INFO     │
│  Workflow Trigger Lag         │ < 2s    │ > 10s = PAGE    │
└─────────────────────────────────────────────────────────────┘

INFRASTRUCTURE METRICS:
- `pg_table_size`: Monitor specific tenants growing out of control (Quota enforcement).
- `cache_miss_rate`: Metadata cache. Resetting this kills DB.

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: "THE MASSIVE IMPORT"
Symptom: Tenant uploads 1M rows via CSV. DB CPU hits 100%.
Mitigation:
- **Resource Governor**: Limit concurrent IOPS per org_id.
- **Bulk API**: Force CSV imports into low-priority queue (Nightly Batch).

SCENARIO 2: CASCADING DELETE
Symptom: Tenant deletes "Account". DB hangs trying to delete 100k related "Contacts" + "Tasks".
Mitigation:
- **Soft Delete**: `is_deleted=true` (Instant).
- **Async GC**: Background job permanently removes rows after 30 days (in batches of 1000).

SCENARIO 3: METADATA CORRUPTION
Symptom: UI trying to render field that doesn't exist.
Mitigation:
- **Schema Validation**: App Layer enforces types before writing `column_definitions`.
- **Safe Mode**: UI renders "Raw Data" if custom widget fails.

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

STORAGE TIERING:
- "Activities" (Emails/Calls) are high volume.
- Strategy: Move activities > 1 year old to S3/DynamoDB (Cold Store).
- UI: Show "Load older history..." button which queries Cold Store.

AUDIT LOGS:
- Enterprise requirement but expensive.
- Optimization: Store diffs only (`old: A, new: B`), not full snapshots.
- Compression: LZ4 on audit partition saves 50%.
```

---

## 🔗 Related Documents

- [E-commerce Schema](./ecommerce-schema-design-guide.md) — Similar multi-tenant pattern
- [Database Scaling](./database-scaling-guide.md) — Sharding by org_id
- [Neobank Schema](./neobank-schema-design-guide.md) — Similar audit patterns
- [Healthcare Schema](./healthcare-schema-design-guide.md) — Similar compliance patterns
