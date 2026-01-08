> **Sources**: 
> - Andrzej Ludwikowski's talk on practical challenges and operational hazards in Event Sourcing.
> - Greg Young's "Why Event Sourced Systems Fail" - pragmatic critique based on a decade of experience.

---

## 🎯 Core Philosophy

> [!IMPORTANT]
> **In distributed systems, failure is not exceptional—it's the norm.** Design for it.

Event-driven architectures introduce new failure modes compared to monolithic systems. This document covers every failure scenario and its mitigation.

---

## 🧑‍💻 Why Event Sourcing Projects Fail: The Human Element

> [!CAUTION]
> **Greg Young: "80-90% of ES failures stem from the learning curve, not the technology."**

### 1. The Experience Trap

| Mistake | Reality |
| :--- | :--- |
| "I've done backend for 10 years, I can do ES" | ES requires **paradigm-specific experience** |
| "I read a book, I'm ready" | You need hands-on failure experience |
| "Frameworks will save us" | Frameworks can't fix analysis and thinking problems |

**Solution**: Budget 6-12 months for team to build ES-specific intuition. Pair with ES-experienced engineers.

### 2. Versioning Over Time (The #1 Technical Failure)

**Problem**: Logs are kept forever. How do you interpret an event written 2 years ago when business logic has changed?

**Solutions**:

| Strategy | How | When to Use |
| :--- | :--- | :--- |
| **Weak Schemas** | Only add/remove fields, never rename | Default approach |
| **Upcasting** | Transform old events on read | Moderate changes |
| **Store Migration** | Transform events to new store during release | Major schema changes |

**Versioning Infrastructure**:
```java
// Upcaster chain
public Event upcast(Event oldEvent) {
    if (oldEvent.version() < 2) {
        return addDefaultField(oldEvent, "currency", "USD");
    }
    if (oldEvent.version() < 3) {
        return renameField(oldEvent, "amount", "totalAmount");
    }
    return oldEvent;
}
```

### 3. Modeling Events vs. Modeling State

| State-Based Thinking (WRONG) | Event-Based Thinking (RIGHT) |
| :--- | :--- |
| "What is the current balance?" | "What transactions led to this balance?" |
| "Update the record" | "What fact just happened in the business?" |
| Entity attributes | Business decisions and actions |

**The Litmus Test**: Can a business person understand your event names without technical translation?
- ❌ `UserRecordUpdated` (technical)
- ✅ `CustomerPlacedOrder` (business language)

### 4. Eventual Consistency: The "Hiding" Technique

**Greg Young's Pattern**: Return the log position on write.

```
1. Client writes: POST /orders → 201 Created { position: 12345 }
2. Client reads:  GET /orders?after=12345
3. If read model hasn't reached position 12345, return: 
   { status: "Retry-After", position: 12340, target: 12345 }
```

**Implementation**:
```java
// Write side returns position
OrderPlacedEvent event = eventStore.append(orderPlaced);
return new WriteResult(event.getPosition()); // e.g., 12345

// Read side checks position
if (readModel.currentPosition() < requestedPosition) {
    return Response.status(503)
        .header("Retry-After", "2")
        .build();
}
return readModel.getOrders();
```

### 5. CQRS ≠ Event Sourcing

> [!NOTE]
> **They are often used together, but they are NOT the same thing.**

| Concept | Definition | Can Exist Alone? |
| :--- | :--- | :---: |
| **CQRS** | Separate read and write models | ✅ Yes |
| **Event Sourcing** | Append-only event log as source of truth | ✅ Yes |
| **CQRS + ES** | Common combination | ✅ Yes |

**When to Use CQRS Without ES**:
- Read-heavy systems needing read replicas
- Different DB technologies for read vs. write
- No need for full audit history

---

## 📊 Failure Modes Classification

### Producer-Side Failures

| Failure | Cause | Impact | Mitigation |
| :--- | :--- | :--- | :--- |
| **Message Lost Before Send** | Crash after business commit, before publish | Data processed but not propagated | Transactional Outbox |
| **Duplicate Send on Retry** | Network timeout, producer retries | Event processed multiple times | Idempotency keys |
| **Serialization Failure** | Schema mismatch, corrupt data | Message rejected | Schema Registry validation |
| **Broker Unreachable** | Network partition, broker down | Messages pile up | Circuit breaker + local buffer |

### Broker-Side Failures

| Failure | Cause | Impact | Mitigation |
| :--- | :--- | :--- | :--- |
| **Single Broker Down** | Hardware failure, OOM | Partition temporarily unavailable | Replication factor ≥ 3 |
| **All Brokers Down** | Datacenter outage | Complete system halt | Multi-region deployment |
| **Partition Leader Election** | Leader crash | Brief unavailability (~seconds) | Increase `min.insync.replicas` |
| **Disk Full** | Retention misconfigured | New events rejected | Alerting + capacity planning |

### Consumer-Side Failures

| Failure | Cause | Impact | Mitigation |
| :--- | :--- | :--- | :--- |
| **Crash Mid-Processing** | Bug, OOM | Event not committed | At-least-once + idempotency |
| **Poison Message** | Malformed event | Consumer stuck in loop | Dead Letter Queue |
| **Slow Consumer** | DB bottleneck | Lag grows unbounded | Horizontal scaling |
| **Rebalance Storm** | Frequent restarts | Throughput drops | Static group membership |

---

## 🔄 The "Effectively-Once" Myth

> [!CAUTION]
> **Exactly-Once delivery is impossible in distributed systems.** Network failures, retries, and crashes guarantee duplicates or losses.

### What You Can Achieve

| Guarantee | How | Trade-off |
| :--- | :--- | :--- |
| **At-Most-Once** | Don't retry on failure | Potential message loss |
| **At-Least-Once** | Retry until ACK | Potential duplicates |
| **Effectively-Once** | At-Least-Once + Idempotency | Best realistic option |

### Idempotency Patterns

**Pattern 1: Idempotency Key**
```java
// Producer adds unique ID
event.setIdempotencyKey(UUID.randomUUID());

// Consumer checks before processing
if (processedKeys.contains(event.getIdempotencyKey())) {
    return; // Skip duplicate
}
process(event);
processedKeys.add(event.getIdempotencyKey());
```

**Pattern 2: Idempotent Business Logic**
```sql
-- Instead of:
UPDATE accounts SET balance = balance - 50;

-- Use:
UPDATE accounts SET balance = 450 WHERE id = 123;
-- Same result if run twice
```

**Pattern 3: Deduplication Table**
```sql
CREATE TABLE processed_events (
    event_id UUID PRIMARY KEY,
    processed_at TIMESTAMP
);

-- In same transaction as business logic
INSERT INTO processed_events (event_id) VALUES ('uuid-1234')
ON CONFLICT DO NOTHING;
```

---

## 🩹 Healing Commands: Fixing Immutable Events

> [!WARNING]
> **Events are immutable. You cannot UPDATE or DELETE them.**

### The Problem
You published `DepositApplied { amount: 50 }` but it should have been `100`.

### The Solution: Compensating Events

```
Original Stream:
[AccountOpened] → [DepositApplied { amount: 50 }] ← ERROR!

After Healing:
[AccountOpened] → [DepositApplied { amount: 50 }] → [DepositCorrected { 
    originalEventId: "evt-123",
    correctedAmount: 100,
    reason: "JIRA-567: Data entry error"
}]
```

### Healing Event Schema
```json
{
  "eventType": "DepositCorrected",
  "payload": {
    "originalEventId": "evt-123",
    "originalAmount": 50,
    "correctedAmount": 100,
    "reason": "Data entry error",
    "correctedBy": "admin@company.com",
    "jiraTicket": "JIRA-567"
  }
}
```

---

## 🧠 Split Brain: The Cluster Killer

### The Scenario
Network partition occurs. Node A and Node B both believe they are the leader for `User:123`.

```
Before Partition:
[Node A: Leader] ←── connected ──→ [Node B: Follower]

After Partition:
[Node A: Leader] ✕ disconnected ✕ [Node B: "I'm also Leader now!"]
        ↓                                     ↓
   Writes v10                            Writes v10 (CONFLICT!)
```

### Solutions

| Strategy | How | Trade-off |
| :--- | :--- | :--- |
| **Keep Majority** | Only majority partition stays active | Minority side stops accepting writes |
| **Keep Oldest** | Oldest node wins leadership | Simpler, but arbitrary |
| **Lease-Based** | Nodes must hold etcd/ZK lease to write | Lease expiry = brief unavailability |
| **Fencing Tokens** | Every write includes monotonic token | Stale tokens rejected |

### Akka Split-Brain Resolver Config
```hocon
akka.cluster.split-brain-resolver {
  active-strategy = keep-majority
  stable-after = 10s
  down-all-when-unstable = on
}
```

---

## 🗑️ GDPR: The "Right to Forget"

### The Problem
User requests account deletion. But events are immutable!

### Solution: Crypto Shredding

**Step 1: Encrypt PII at Write Time**
```json
{
  "eventType": "UserRegistered",
  "payload": {
    "userId": "user-123",
    "encryptedName": "AES256(John Doe, key-user-123)",
    "encryptedEmail": "AES256(john@email.com, key-user-123)"
  }
}
```

**Step 2: Store Key Separately**
```sql
CREATE TABLE user_keys (
    user_id VARCHAR PRIMARY KEY,
    encryption_key BYTEA
);
```

**Step 3: Delete Key on Forget Request**
```sql
DELETE FROM user_keys WHERE user_id = 'user-123';
-- Events still exist, but PII is now unreadable garbage
```

---

## 🔄 Saga Pattern: Cross-Service Transactions

### Why Sagas?
Traditional 2PC doesn't work in event-driven systems. Use Sagas for eventual consistency.

### Choreography vs Orchestration

| Aspect | Choreography | Orchestration |
| :--- | :--- | :--- |
| **Coordination** | Each service reacts to events | Central coordinator sends commands |
| **Coupling** | Loose | Tighter (to coordinator) |
| **Visibility** | Distributed (hard to track) | Centralized (easy dashboard) |
| **Failure Handling** | Each service handles own compensation | Coordinator handles all compensation |

### Compensation Strategy

| Step | Forward Action | Compensating Action |
| :--- | :--- | :--- |
| 1 | `OrderPlaced` | `OrderCancelled` |
| 2 | `InventoryReserved` | `InventoryReleased` |
| 3 | `PaymentProcessed` | `PaymentRefunded` |
| 4 | `ShipmentCreated` | `ShipmentCancelled` |

### Saga State Machine
```
[Start] → OrderPlaced → InventoryReserved → PaymentProcessed → ShipmentCreated → [Success]
                ↓                ↓                  ↓
           [Compensate] ← InventoryReleased ← PaymentFailed
```

---

## 📈 Scaling Strategies

### Write-Side Scaling

| Strategy | How | When |
| :--- | :--- | :--- |
| **Sharding by Aggregate ID** | Each shard handles subset of aggregates | High throughput needed |
| **Single Writer Principle** | One node per aggregate (Akka Cluster) | Extreme consistency needed |
| **Optimistic Locking** | Version check on write | Moderate contention |

### Read-Side Scaling

| Strategy | How | When |
| :--- | :--- | :--- |
| **Multiple Projections** | Polyglot persistence (ES + Redis + Cassandra) | Different query patterns |
| **Read Replicas** | DB replication | High read volume |
| **Caching** | Redis/Memcached in front of Read Model | Hot data |

---

## 🏛️ Principal Architect Level: Failure Governance

### 1. Failure Budget Policy

| Failure Type | Monthly Budget | Breach Action |
| :--- | :--- | :--- |
| **Duplicate Events** | < 0.01% | Investigate idempotency gaps |
| **Lost Events** | 0% | Immediate incident |
| **Projection Lag > 1 min** | < 5 minutes/month | Scale consumers |
| **Saga Compensation Failures** | < 0.1% | On-call investigation |

### 2. Chaos Engineering Schedule

| Frequency | Test | Owner |
| :--- | :--- | :--- |
| **Weekly** | Kill random consumer | Domain Team |
| **Monthly** | Broker failure simulation | Platform Team |
| **Quarterly** | Full region failover | SRE |
| **Annually** | Split-brain simulation | Architecture Team |

### 3. Incident Classification

| Severity | Definition | Response Time | Example |
| :--- | :--- | :--- | :--- |
| **P1 (Critical)** | Data loss or corruption | 15 minutes | Events permanently lost |
| **P2 (High)** | Degraded but functional | 1 hour | Projection lag > 10 min |
| **P3 (Medium)** | Minor impact | 4 hours | Single consumer slow |
| **P4 (Low)** | No user impact | Next business day | Monitoring gap |

### 4. Runbook Template

```markdown
## Runbook: Consumer Stuck on Poison Message

### Symptoms
- Consumer lag growing
- Same offset for > 5 minutes
- Error logs show repeated failures

### Diagnosis
1. Check consumer logs for exception
2. Identify problematic event ID
3. Verify event payload in Event Store

### Mitigation
1. Manually publish event to DLQ:
   `kafka-console-producer --topic <topic>-dlq < poison_event.json`
2. Commit offset past poison event:
   `kafka-consumer-groups --reset-offsets --to-offset <offset+1>`
3. Restart consumer

### Post-Incident
- [ ] Root cause analysis
- [ ] Schema validation improvement
- [ ] Add contract test
```

### 5. Recovery Time Objectives

| Component | RTO | RPO | Recovery Method |
| :--- | :--- | :--- | :--- |
| **Event Store** | < 1 min | 0 | Auto-failover |
| **Kafka** | < 5 min | 0 | Replica promotion |
| **Projections** | < 15 min | N/A | Replay from Event Store |
| **Saga State** | < 30 min | 0 | Restore from checkpoint |

---

## Summary

> [!IMPORTANT]
> **Failure handling is not optional—it's the architecture.**

**Key Takeaways**:
1. **Exactly-Once is a myth**. Design for Effectively-Once with idempotency.
2. **Events are immutable**. Use Healing Commands for corrections.
3. **Split-Brain will happen**. Test your resolver before production.
4. **GDPR ≠ Delete Events**. Use Crypto Shredding.
5. **Sagas replace 2PC**. Embrace eventual consistency.
6. **Chaos test regularly**. Find failures before they find you.

**Principal Architect Checklist**:
- [ ] Failure budget policy defined
- [ ] Chaos engineering schedule active
- [ ] Incident classification documented
- [ ] Runbooks for all failure modes
- [ ] RTO/RPO targets met and tested
