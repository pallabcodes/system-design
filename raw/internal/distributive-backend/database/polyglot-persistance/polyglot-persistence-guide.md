# Polyglot Persistence: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ Data Architect
> **Scope**: Multi-Model Databases, Trade-off Analysis, Migration Patterns — Decision Framework

> [!CAUTION]
> **The Cardinal Sin**: Adding a new database because "it's the right tool for the job" without considering operational overhead. Every new database is +1 on-call rotation, +1 backup system, +1 security audit.

---

## 📚 Required Reading

| Resource | Topic |
| :--- | :--- |
| [Designing Data-Intensive Applications](https://dataintensive.net/) | Martin Kleppmann's masterpiece |
| [AWS Well-Architected Framework - Data](https://docs.aws.amazon.com/wellarchitected/latest/framework/perf-data.html) | Cloud data patterns |
| [Multi-Model DBs (MarkLogic)](https://www.marklogic.com/wp-content/uploads/2020/07/multi-model-databases-oreilly.pdf) | When one DB handles multiple models |

---

## 🎯 The Principal Laws of Polyglot Persistence

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Schema Tax is Unavoidable** | Write-time (RDBMS) or Read-time (Document) | Choose where complexity lives |
| **Law 2: Operational Cost > Feature Benefit** | New DB = new failure mode | Consider multi-model first |
| **Law 3: Access Pattern Drives Model** | How you query > how you store | Design for reads |
| **Law 4: Consistency Boundaries** | Each DB has its own ACID scope | Cross-DB transactions are sagas |

---

# Part 1: The Data Model Spectrum

## 📊 Complete Model Comparison

| Model | Structure | Schema | Best O(1) Query | Worst Query | Example DBs |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Key-Value** | Hash map | None | GET by key | Range scan | Redis, DynamoDB, Memcached |
| **Wide-Column** | Sparse table | Per-row | Row + Column family | Cross-row aggregation | Bigtable, Cassandra, HBase |
| **Document** | Nested JSON | Schema-on-read | GET by ID | Cross-collection join | MongoDB, Couchbase, Firestore |
| **Relational** | Tables + FK | Schema-on-write | PK lookup | Cartesian product | PostgreSQL, MySQL, Spanner |
| **Graph** | Nodes + Edges | Node/Edge types | 1-hop traversal | Full graph traversal | Neo4j, Neptune, TigerGraph |
| **Time-Series** | Time-indexed | Column-typed | Time range + series | Ad-hoc cross-series | TimescaleDB, InfluxDB, Prometheus |
| **Search** | Inverted index | Mapping | Term lookup | Scoring over billions | Elasticsearch, OpenSearch, Solr |
| **Vector** | Embeddings | Dimension | ANN similarity | Exact NN search | Pinecone, Milvus, pgvector |

## 🧠 Decision Matrix

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                    ACCESS PATTERN                        │
                    ├───────────┬───────────┬───────────┬───────────┬─────────┤
                    │ Key-Only  │ Scans     │ Joins     │ Traversal │ Search  │
┌───────────────┬───┼───────────┼───────────┼───────────┼───────────┼─────────┤
│ Extreme Speed │ R │ Key-Value │ Cassandra │ N/A       │ N/A       │ N/A     │
│               │   │ (Redis)   │           │           │           │         │
├───────────────┼───┼───────────┼───────────┼───────────┼───────────┼─────────┤
│ Write-Heavy   │ W │ Key-Value │ Cassandra │ Document  │ Graph     │ Search  │
│ (Logs, IoT)   │   │ (Dynamo)  │ Wide-Col  │ (append)  │ (edges)   │ (async) │
├───────────────┼───┼───────────┼───────────┼───────────┼───────────┼─────────┤
│ Read-Heavy    │ R │ Key-Value │ Any       │ RDBMS     │ Graph     │ Search  │
│ (Product cat) │   │ + Cache   │ + Replica │ + Index   │           │         │
├───────────────┼───┼───────────┼───────────┼───────────┼───────────┼─────────┤
│ Analytics     │ A │ N/A       │ Wide-Col  │ OLAP      │ Graph     │ Search  │
│               │   │           │ + Spark   │ (Redshift)│ Analytics │ Agg     │
├───────────────┼───┼───────────┼───────────┼───────────┼───────────┼─────────┤
│ Consistency   │ C │ Redis     │ N/A       │ RDBMS     │ N/A       │ N/A     │
│ Critical      │   │ (w/ Lua)  │           │ (Spanner) │           │         │
└───────────────┴───┴───────────┴───────────┴───────────┴───────────┴─────────┘
```

---

# Part 2: Model Deep Dives

## 🔑 Key-Value Stores

### When to Use
```
✅ Session storage (opaque blob per session ID)
✅ Cache layer (computed results, denormalized views)
✅ Rate limiting (counters with TTL)
✅ Feature flags (simple key → JSON config)
✅ Queue (Redis Lists/Streams)

❌ Complex queries (you CAN'T query the value)
❌ Relationships between entities
❌ Reporting/analytics
```

### Production Pattern: Rate Limiter
```python
import redis
from datetime import datetime

class RateLimiter:
    def __init__(self, redis_client: redis.Redis, limit: int, window_seconds: int):
        self.redis = redis_client
        self.limit = limit
        self.window = window_seconds
    
    def is_allowed(self, key: str) -> tuple[bool, int]:
        """Returns (allowed, remaining_requests)."""
        now = int(datetime.utcnow().timestamp())
        window_start = now - self.window
        
        pipe = self.redis.pipeline()
        # Remove old entries
        pipe.zremrangebyscore(key, '-inf', window_start)
        # Add current request
        pipe.zadd(key, {str(now): now})
        # Count requests in window
        pipe.zcard(key)
        # Set TTL
        pipe.expire(key, self.window)
        
        results = pipe.execute()
        request_count = results[2]
        
        if request_count > self.limit:
            return False, 0
        return True, self.limit - request_count

# Usage
limiter = RateLimiter(redis.Redis(), limit=100, window_seconds=60)
allowed, remaining = limiter.is_allowed(f"rate:{user_id}")
```

## 📄 Document Stores

### When to Use
```
✅ Self-contained entities (blog posts, product listings)
✅ Variable schema (different products have different attributes)
✅ Rapid prototyping (schema flexibility)
✅ Content management (articles with nested sections)

❌ High-frequency partial updates to large documents
❌ Cross-document transactions (limited support)
❌ Complex joins (server-side aggregation is expensive)
❌ Strong consistency requirements
```

### Production Pattern: Product Catalog
```javascript
// MongoDB schema

// Collection: products
{
  _id: ObjectId("..."),
  sku: "LAPTOP-2024-001",
  name: "Pro Laptop 15",
  category: "electronics",
  
  // Common fields
  price: { amount: 1299.99, currency: "USD" },
  inventory: { quantity: 45, warehouse: "WH-01" },
  status: "active",
  
  // Category-specific fields (schemaless advantage)
  specifications: {
    cpu: "Apple M3",
    ram_gb: 16,
    storage_gb: 512,
    display_inches: 15.3,
    battery_hours: 18
  },
  
  // Nested arrays
  images: [
    { url: "...", alt: "Front view", primary: true },
    { url: "...", alt: "Side view" }
  ],
  
  // Denormalized for read performance
  brand: { id: "brand-apple", name: "Apple" },
  
  // Audit
  createdAt: ISODate("2024-01-01T00:00:00Z"),
  updatedAt: ISODate("2024-01-15T12:00:00Z")
}

// Indexes
db.products.createIndex({ sku: 1 }, { unique: true });
db.products.createIndex({ category: 1, status: 1, "price.amount": 1 });
db.products.createIndex({ "specifications.cpu": 1 });  // For filtering
db.products.createIndex({ name: "text", "specifications.cpu": "text" });  // Full-text
```

## 🏛️ Relational Databases

### When to Use
```
✅ Complex relationships (many-to-many, self-referential)
✅ ACID transactions across tables
✅ Complex queries (GROUP BY, WINDOW, CTEs)
✅ Data integrity (FK constraints, CHECK constraints)
✅ Multi-team data sharing (schema is the contract)

❌ Simple key-value access (overkill)
❌ Schemaless/rapidly changing structure
❌ Extreme write throughput (locks contention)
❌ Horizontal scaling without NewSQL
```

### Production Pattern: Financial Ledger
```sql
-- Double-entry accounting with strong consistency

CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
    name VARCHAR(255) NOT NULL,
    currency CHAR(3) NOT NULL,
    balance NUMERIC(18, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE journal_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    description TEXT NOT NULL,
    posted_at TIMESTAMPTZ NOT NULL,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE journal_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_entry_id UUID NOT NULL REFERENCES journal_entries(id),
    account_id UUID NOT NULL REFERENCES accounts(id),
    amount NUMERIC(18, 2) NOT NULL,  -- Positive = debit, Negative = credit
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Constraint: Every journal entry must balance (debits = credits)
CREATE OR REPLACE FUNCTION check_journal_balance()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT SUM(amount) FROM journal_lines WHERE journal_entry_id = NEW.journal_entry_id) != 0 THEN
        RAISE EXCEPTION 'Journal entry does not balance';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_journal_balance
AFTER INSERT ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_journal_balance();

-- Transaction: Transfer with double-entry
CREATE OR REPLACE FUNCTION transfer(
    p_from_account UUID,
    p_to_account UUID,
    p_amount NUMERIC,
    p_description TEXT,
    p_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_entry_id UUID;
BEGIN
    -- Create journal entry
    INSERT INTO journal_entries (description, posted_at, created_by)
    VALUES (p_description, NOW(), p_user_id)
    RETURNING id INTO v_entry_id;
    
    -- Debit from source (reduce asset or increase expense)
    INSERT INTO journal_lines (journal_entry_id, account_id, amount)
    VALUES (v_entry_id, p_from_account, -p_amount);
    
    -- Credit to destination (increase asset or reduce expense)
    INSERT INTO journal_lines (journal_entry_id, account_id, amount)
    VALUES (v_entry_id, p_to_account, p_amount);
    
    -- Update balances
    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from_account;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to_account;
    
    RETURN v_entry_id;
END;
$$ LANGUAGE plpgsql;
```

## 🕸️ Graph Databases

### When to Use
```
✅ Social networks (friends of friends)
✅ Recommendation engines (co-purchase, co-view)
✅ Fraud detection (suspicious transaction patterns)
✅ Knowledge graphs (entity relationships)
✅ Dependency analysis (service maps, impact analysis)

❌ Tabular data without relationships
❌ Time-series data
❌ Simple CRUD applications
❌ Heavy aggregation/reporting
```

### Production Pattern: Fraud Detection (Neo4j)
```cypher
// Create nodes
CREATE (u:User {id: 'user-123', email: 'alice@example.com'})
CREATE (d:Device {id: 'device-abc', fingerprint: 'abc123'})
CREATE (c:Card {id: 'card-456', last4: '1234'})
CREATE (a:Address {id: 'addr-789', hash: 'xyz'})

// Create relationships
MATCH (u:User {id: 'user-123'}), (d:Device {id: 'device-abc'})
CREATE (u)-[:USES_DEVICE {first_seen: datetime()}]->(d)

MATCH (u:User {id: 'user-123'}), (c:Card {id: 'card-456'})
CREATE (u)-[:OWNS_CARD]->(c)

MATCH (u:User {id: 'user-123'}), (a:Address {id: 'addr-789'})
CREATE (u)-[:SHIPS_TO]->(a)

// Fraud query: Find users sharing devices with known fraudsters
MATCH (fraudster:User {is_fraudster: true})-[:USES_DEVICE]->(d:Device)<-[:USES_DEVICE]-(suspect:User)
WHERE suspect.is_fraudster IS NULL
RETURN suspect, d, fraudster, count(*) as shared_devices
ORDER BY shared_devices DESC

// Fraud query: Ring detection (accounts connected via shared entities)
MATCH path = (u1:User)-[:OWNS_CARD|USES_DEVICE|SHIPS_TO*1..3]-(shared)-[:OWNS_CARD|USES_DEVICE|SHIPS_TO*1..3]-(u2:User)
WHERE u1 <> u2
  AND NOT (u1)-[:KNOWS]-(u2)  // Not explicitly connected
WITH u1, u2, count(distinct shared) as connections
WHERE connections >= 3
RETURN u1, u2, connections
```

---

# Part 3: Multi-Model in Single Database

## 🔧 PostgreSQL: The Swiss Army Knife

```sql
-- Relational: Standard tables
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE
);

-- Document: JSONB columns
CREATE TABLE events (
    id UUID PRIMARY KEY,
    event_type VARCHAR(50),
    payload JSONB,  -- Schemaless data
    created_at TIMESTAMPTZ
);

CREATE INDEX idx_events_payload ON events USING GIN (payload jsonb_path_ops);

-- Key-Value: Unlogged table for cache
CREATE UNLOGGED TABLE cache (
    key VARCHAR(255) PRIMARY KEY,
    value BYTEA,
    expires_at TIMESTAMPTZ
);

-- Time-Series: TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE metrics (
    time TIMESTAMPTZ NOT NULL,
    metric_name TEXT NOT NULL,
    value DOUBLE PRECISION
);

SELECT create_hypertable('metrics', 'time');

-- Graph: Apache AGE extension
CREATE EXTENSION IF NOT EXISTS age;

SELECT create_graph('social');

SELECT * FROM cypher('social', $$
    CREATE (a:Person {name: 'Alice'})-[:KNOWS]->(b:Person {name: 'Bob'})
    RETURN a, b
$$) AS (a agtype, b agtype);

-- Full-Text Search: Built-in
ALTER TABLE products ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', name || ' ' || description)) STORED;

CREATE INDEX idx_products_fts ON products USING GIN (tsv);

SELECT * FROM products WHERE tsv @@ to_tsquery('laptop & pro');

-- Vector: pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE embeddings (
    id UUID PRIMARY KEY,
    content TEXT,
    embedding vector(1536)  -- OpenAI dimension
);

CREATE INDEX idx_embeddings_ann ON embeddings USING ivfflat (embedding vector_cosine_ops);

SELECT * FROM embeddings
ORDER BY embedding <=> '[0.1, 0.2, ...]'::vector
LIMIT 10;
```

### When to Use Multi-Model vs Specialized DB

| Factor | Use PostgreSQL Multi-Model | Use Specialized DB |
| :--- | :--- | :--- |
| **Workload size** | < 100GB | > 1TB |
| **Ops team size** | < 10 engineers | Dedicated data team |
| **Latency requirements** | P99 < 100ms OK | P99 < 10ms required |
| **Write throughput** | < 10K TPS | > 100K TPS |
| **Feature depth** | 80% use case | Need 100% features |
| **Cross-model transactions** | Required | Not needed |

---

# Part 4: Polyglot Data Flow Patterns

## 🔄 CQRS: Command Query Responsibility Segregation

```
                    Command                              Query
                       │                                   │
                       ▼                                   ▼
              ┌─────────────────┐               ┌─────────────────┐
              │ Command Handler │               │  Query Handler  │
              └────────┬────────┘               └────────┬────────┘
                       │                                 │
                       ▼                                 ▼
              ┌─────────────────┐               ┌─────────────────┐
              │  PostgreSQL     │               │  Elasticsearch  │
              │  (Source of     │──CDC/Event──►│  (Optimized for │
              │   Truth)        │               │   Search)       │
              └─────────────────┘               └─────────────────┘
```

### Implementation: Order System
```python
# Write side: PostgreSQL
async def create_order(order: CreateOrderCommand) -> Order:
    async with db.transaction():
        # Insert order
        order_id = await db.execute(
            "INSERT INTO orders (customer_id, total) VALUES ($1, $2) RETURNING id",
            order.customer_id, order.total
        )
        
        # Insert order items
        for item in order.items:
            await db.execute(
                "INSERT INTO order_items (order_id, product_id, quantity) VALUES ($1, $2, $3)",
                order_id, item.product_id, item.quantity
            )
        
        # Publish event (via outbox pattern)
        await db.execute(
            "INSERT INTO outbox (aggregate_type, aggregate_id, event_type, payload) VALUES ($1, $2, $3, $4)",
            "Order", order_id, "OrderCreated", json.dumps(order.dict())
        )
        
        return Order(id=order_id, ...)

# Read side: Elasticsearch (async projection via Kafka consumer)
async def handle_order_created(event: OrderCreatedEvent):
    order_doc = {
        "id": event.order_id,
        "customer": {
            "id": event.customer_id,
            "name": await get_customer_name(event.customer_id)  # Denormalize
        },
        "items": [
            {
                "product_id": item.product_id,
                "product_name": await get_product_name(item.product_id),  # Denormalize
                "quantity": item.quantity
            }
            for item in event.items
        ],
        "total": event.total,
        "created_at": event.timestamp
    }
    
    await es.index(index="orders", id=event.order_id, document=order_doc)

# Query side: Elasticsearch
async def search_orders(query: str, filters: dict) -> List[Order]:
    response = await es.search(
        index="orders",
        query={
            "bool": {
                "must": [
                    {"multi_match": {"query": query, "fields": ["customer.name", "items.product_name"]}}
                ],
                "filter": [
                    {"range": {"total": {"gte": filters.get("min_total", 0)}}}
                ]
            }
        },
        sort=[{"created_at": "desc"}],
        size=20
    )
    return [Order(**hit["_source"]) for hit in response["hits"]["hits"]]
```

---

# Part 5: Operational Considerations

## 📊 Database Ops Overhead Matrix

| DB Category | Backup Complexity | HA Complexity | Monitoring | Security Audit |
| :--- | :--- | :--- | :--- | :--- |
| **PostgreSQL** | pg_dump/WAL | Patroni/RDS | pg_stat | Row Security |
| **MongoDB** | mongodump/oplog | Replica Set | Atlas | Built-in |
| **Redis** | RDB/AOF | Sentinel/Cluster | redis-cli | ACLs (6.0+) |
| **Elasticsearch** | Snapshots | Multi-node | _cat APIs | X-Pack |
| **DynamoDB** | On-Demand/PITR | Built-in | CloudWatch | IAM |
| **Neo4j** | neo4j-admin | Causal Cluster | Procedures | RBAC |

### Cost Per Database
```
Adding a new database to your stack:

Direct costs:
- License (if enterprise)
- Compute/storage
- Cross-region replication

Hidden costs:
- On-call rotation expansion
- Training for engineers
- Backup verification
- Security audits
- Monitoring dashboards
- Disaster recovery testing
- Schema migration tooling
- Data lifecycle management

Rule of thumb:
  Total cost ≈ 3x direct infrastructure cost
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Evaluated multi-model in existing DB first | PostgreSQL can do 80%? |
| 2 | Access pattern documented before choosing | Read/write ratio known |
| 3 | Cross-DB consistency handled | Saga or eventual consistency |
| 4 | Ops team can support new DB | Training plan exists |
| 5 | Backup/restore tested | Tested recovery time |
| 6 | Data lifecycle defined | Retention, archival, deletion |
| 7 | Security audit complete | Encryption, access control |
| 8 | Monitoring dashboards exist | Per-DB metrics visible |

---

## 🔗 Related Documents
*   [NoSQL Architecture](./nosql-architecture-guide.md) — DynamoDB, Cassandra, Bigtable.
*   [RDBMS Internals](./rdbms-internals-guide.md) — PostgreSQL deep dive.
*   [Saga Pattern](./saga/saga-pattern-guide.md) — Cross-DB transactions.
