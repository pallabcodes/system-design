# CQRS: Command Query Responsibility Segregation

> **Source**: Marco Lenzo's presentation on the mechanics, benefits, and challenges of Event Sourcing and CQRS.

> **Source**: Gulo Wooden - "CQRS & Event Sourcing: The Riddle Game"

---

## 🎯 What is CQRS?

**CQRS** separates operations that **change state** (Commands) from those that **retrieve data** (Queries).

```
Traditional (Single Model):
┌─────────────────────────────────────────┐
│           Application Model             │
│  ┌─────────────┐   ┌─────────────┐      │
│  │   Create    │   │    Read     │      │
│  │   Update    │   │    List     │      │
│  │   Delete    │   │    Search   │      │
│  └─────────────┘   └─────────────┘      │
│              Same Database              │
└─────────────────────────────────────────┘

CQRS (Separated Models):
┌─────────────────┐   ┌─────────────────┐
│  Command Side   │   │   Query Side    │
│   (Write Model) │   │  (Read Model)   │
│  ┌───────────┐  │   │  ┌───────────┐  │
│  │  Create   │  │   │  │   Read    │  │
│  │  Update   │──┼──▶│  │   List    │  │
│  │  Delete   │  │   │  │   Search  │  │
│  └───────────┘  │   │  └───────────┘  │
│   Write DB      │   │    Read DB      │
└─────────────────┘   └─────────────────┘
```

---

## 🔗 CQRS + Event Sourcing Relationship

> [!NOTE]
> **Greg Young: "CQRS is a stepping stone to Event Sourcing."**

| Concept | Role in ES+CQRS |
| :--- | :--- |
| **Command Side** | Populates the Event Log (appends events) |
| **Query Side** | Materializes Read Models from events |
| **Event Store** | Source of truth (append-only log) |
| **Projections** | Transforms events into queryable views |

> [!TIP]
> **♟️ Chess Analogy**:
> *   **CRUD (Snapshot)**: A photo of the board at the end of the game. It tells you who won, but not how. You can't see "why" the Queen is missing.
> *   **Event Sourcing (Notation Sheet)**: The list of every move (`e4`, `Nf3`, `Qxd5`). To get the current state, you replay the moves. You can also "time travel" to see the board state at Move 10.

### Integration Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client                                  │
│           ┌──────────┐              ┌──────────┐                │
│           │ Commands │              │ Queries  │                │
│           └────┬─────┘              └────┬─────┘                │
└────────────────┼─────────────────────────┼──────────────────────┘
                 │                         │
                 ▼                         ▼
┌────────────────────────┐   ┌────────────────────────────────────┐
│     Command Service    │   │         Query Service              │
│  ┌──────────────────┐  │   │  ┌───────────┐  ┌───────────────┐  │
│  │   Aggregate      │  │   │  │  SQL DB   │  │  Elasticsearch│  │
│  │   Validation     │  │   │  │  (Lists)  │  │   (Search)    │  │
│  │   Business Rules │  │   │  └───────────┘  └───────────────┘  │
│  └────────┬─────────┘  │   │         ▲              ▲           │
└───────────┼────────────┘   └─────────┼──────────────┼───────────┘
            │                          │              │
            ▼                          │              │
┌────────────────────────┐             │              │
│      Event Store       │─────────────┴──────────────┘
│   (Append-Only Log)    │    Projections
└────────────────────────┘
```

---

## 📊 Command vs Query Characteristics

| Aspect | Command Side | Query Side |
| :--- | :--- | :--- |
| **Operation** | Write (mutate state) | Read (retrieve data) |
| **Consistency** | Strong (transactional) | Eventual (projections lag) |
| **Model** | Domain objects (Aggregates) | Denormalized views |
| **Scaling** | Vertical (consistency) | Horizontal (read replicas) |
| **Caching** | Rarely | Heavily |

---

## ✅ Benefits of CQRS

### 1. Independent Scaling

| Scenario | Solution |
| :--- | :--- |
| Read-heavy workload (90% reads) | Scale query service horizontally |
| Write-heavy workload (batch imports) | Optimize write path only |
| Different query patterns | Multiple read models (SQL, Elasticsearch, Graph) |

### 2. Optimized Data Models

**Write Model** (normalized, consistent):
```sql
-- Aggregate root with business rules
CREATE TABLE orders (
    id UUID PRIMARY KEY,
    customer_id UUID REFERENCES customers(id),
    status VARCHAR(50),
    version INT  -- Optimistic concurrency
);

CREATE TABLE order_items (
    id UUID PRIMARY KEY,
    order_id UUID REFERENCES orders(id),
    product_id UUID,
    quantity INT
);
```

**Read Model** (denormalized, fast):
```sql
-- Pre-joined, pre-aggregated for dashboard
CREATE TABLE order_dashboard (
    order_id UUID PRIMARY KEY,
    customer_name VARCHAR(255),
    customer_email VARCHAR(255),
    total_items INT,
    total_amount DECIMAL,
    status VARCHAR(50),
    created_at TIMESTAMP
);
```

### 3. Polyglot Persistence

| Query Type | Optimal Storage |
| :--- | :--- |
| Transactional lists | PostgreSQL |
| Full-text search | Elasticsearch |
| Graph traversal | Neo4j |
| Time-series analytics | TimescaleDB |
| Real-time dashboards | Redis |

### 4. Auditing and Time Travel

```java
// Replay to any point in time
List<Event> events = eventStore.getEventsUpTo(orderId, timestamp);
Order historicalOrder = Order.rehydrate(events);
```

### 5. Disaster Recovery

```
Traditional Migration:
1. Write complex SQL migration scripts
2. Test on staging
3. Pray nothing breaks
4. Rollback if failed (data loss risk)

CQRS + ES Migration:
1. Deploy new service with new schema
2. Replay all events to new read model
3. Verify parity
4. Switch traffic
5. If issues, just switch back (no data loss)
```

---

## ⚠️ Challenges and Mitigations

### 1. Architectural Complexity

| Challenge | Mitigation |
| :--- | :--- |
| More services to deploy | Use Kubernetes, managed services |
| Event log + projections to maintain | Start with single read model, add as needed |
| Team needs new skills | Invest in training, pair with experienced devs |

### 2. Eventual Consistency

**The Problem**: User writes, then immediately reads, but sees stale data.

**Solutions**:

| Pattern | How |
| :--- | :--- |
| **Sync Projection** | Update read model in same transaction (no lag, but slower) |
| **Read Your Writes** | Return write position, client waits for read model to catch up |
| **Optimistic UI** | Client assumes success, shows local update immediately |
| **Causal Consistency** | Track causation, ensure dependent reads wait |

**Read Your Writes Implementation**:
```java
// Write returns position
WriteResult result = commandService.placeOrder(order);
long position = result.getPosition(); // e.g., 12345

// Client passes position to read
OrderView view = queryService.getOrder(orderId, position);
// Query service waits if read model is behind position
```

### 3. Event Evolution

**Problem**: Event schema changes, but old events are immutable.

**Solution: Upcaster Chain**:
```java
public class OrderPlacedUpcaster {
    public OrderPlaced upcast(OrderPlaced event) {
        if (event.getVersion() < 2) {
            // v1 → v2: Add currency field
            return event.withCurrency("USD");
        }
        if (event.getVersion() < 3) {
            // v2 → v3: Rename field
            return event.withTotalAmount(event.getAmount());
        }
        return event;
    }
}
```

### 4. Performance (Hydration)

**Problem**: Replaying 1M events to rebuild state = slow.

**Solution: Snapshots**:
```java
public Order loadOrder(UUID orderId) {
    // Try snapshot first
    Snapshot snapshot = snapshotStore.getLatest(orderId);
    Order order = snapshot != null 
        ? Order.fromSnapshot(snapshot)
        : new Order();
    
    // Replay only events after snapshot
    long fromPosition = snapshot != null ? snapshot.getPosition() : 0;
    List<Event> events = eventStore.getEvents(orderId, fromPosition);
    events.forEach(order::apply);
    
    return order;
}
```

---

## 🏛️ Principal Architect Level: CQRS Governance

### 1. When to Use CQRS

| Scenario | CQRS? | Why |
| :--- | :---: | :--- |
| Read/Write ratio highly asymmetric | ✅ | Independent scaling |
| Complex domain with many views | ✅ | Optimized read models |
| Strict audit requirements | ✅ | Event log is audit trail |
| Simple CRUD app | ❌ | Overkill |
| Small team, tight deadline | ❌ | Complexity overhead |

### 2. Consistency SLA by Read Model

| Read Model | Max Lag SLO | Use Case |
| :--- | :--- | :--- |
| **Real-time Dashboard** | < 1 second | Trading, monitoring |
| **User-facing List** | < 5 seconds | E-commerce, banking |
| **Analytics** | < 1 hour | Reporting, BI |
| **Archival** | < 24 hours | Compliance, backup |

### 3. Read Model Deployment Strategy

| Strategy | How | When |
| :--- | :--- | :--- |
| **Blue-Green** | Deploy new, replay, switch | Schema changes |
| **Canary** | Route % traffic to new | Logic changes |
| **Shadow** | Dual write, compare | Validation |

### 4. Projection Ownership

| Read Model | Owner | Sync Mechanism |
| :--- | :--- | :--- |
| Order List (SQL) | Order Team | Kafka subscription |
| Order Search (ES) | Search Team | Kafka subscription |
| Customer 360 (composite) | Data Platform | CDC + Kafka |

### 5. Technology Choices

| Component | Recommended | When |
| :--- | :--- | :--- |
| **Event Store** | EventStoreDB, Postgres | High reliability |
| **Message Bus** | Kafka, Pulsar | High throughput |
| **Read Models** | Postgres, Elasticsearch | Depends on query pattern |
| **Framework** | Axon, Marten | Want batteries included |

---

## 📚 Framework Comparison

| Framework | Language | Pros | Cons |
| :--- | :--- | :--- | :--- |
| **Axon** | Java | Well-documented, tooling | Heavy, opinionated |
| **Marten** | .NET | Postgres-native, simple | .NET only |
| **Eventuous** | .NET | Lightweight, modern | Smaller community |
| **Akka Persistence** | Scala/Java | Actor model, proven | Learning curve |

---

## Summary

> [!IMPORTANT]
> **CQRS is about optimizing reads and writes independently—it's not just about Event Sourcing.**

**Key Takeaways**:
1. **Separate Command and Query** models for independent optimization.
2. **CQRS ≠ Event Sourcing**, but they work great together.
3. **Eventual Consistency is solvable** (Read Your Writes, Optimistic UI).
4. **Polyglot Persistence** enables optimal storage per query pattern.
5. **Use CQRS when you have asymmetric read/write patterns** or complex views.
6. **Don't use CQRS for simple CRUD**—it adds complexity.

**Principal Architect Checklist**:
- [ ] Read/Write ratio analyzed
- [ ] Consistency SLAs per read model defined
- [ ] Projection ownership documented
- [ ] Deployment strategy selected
- [ ] Framework chosen based on team skills
