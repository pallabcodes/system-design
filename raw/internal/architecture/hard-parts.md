# Architecture Hard Parts: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ Architect
> **Scope**: Service Granularity, Saga Types, Trade-off Analysis, Coupling Analysis — Decision Framework

> [!CAUTION]
> **The Cardinal Sin**: Seeking "best practices." There are no silver bullets. Every decision is a trade-off. Anyone who tells you otherwise is selling something.

---

## 📚 Required Reading

| Book/Resource | Author | Topic |
| :--- | :--- | :--- |
| [Software Architecture: The Hard Parts](https://www.oreilly.com/library/view/software-architecture-the/9781492086888/) | Ford, Richards, Sadalage, Dehghani | Distributed architecture trade-offs |
| [Building Evolutionary Architectures](https://www.oreilly.com/library/view/building-evolutionary-architectures/9781491986356/) | Ford, Parsons, Kua | Fitness functions |
| [Fundamentals of Software Architecture](https://www.oreilly.com/library/view/fundamentals-of-software/9781492043447/) | Richards, Ford | Architecture characteristics |

---

## 🎯 The Principal Laws of Architecture

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Everything is a Trade-off** | "It depends" is the only correct answer | Document the "why not" for rejected options |
| **Law 2: Context is King** | What works at Google doesn't work at a startup | Know your constraints |
| **Law 3: Coupling is Quantum** | Change one, change all | Map coupling before deciding |
| **Law 4: Least Worst Design** | Every option has flaws | Pick the one with manageable flaws |

---

# Part 1: Service Granularity

## ⚔️ The Eternal Question: How Big Should a Service Be?

```
TOO BIG: Monolith problems (slow deploys, team collisions)
TOO SMALL: Distributed monolith (same problems + network latency)

Sweet spot: Each service is independently deployable, 
            owned by one team, and has a clear business capability.
```

## 💥 Disintegrators (Forces That Split Services)

### 1. Single Responsibility (Functionality)
```
Service A handles:
- User authentication
- User profiles
- User preferences
- Password reset

→ Split: AuthService, ProfileService, PreferencesService
         Each can change independently.
```

### 2. Code Volatility (Rate of Change)
```
Service B handles:
- Core order processing (stable, changes 2x/year)
- Promotional pricing (volatile, changes weekly)

→ Split: OrderService, PricingService
         High-change code doesn't risk stable code.
```

### 3. Scalability Requirements
```
Service C handles:
- Product catalog reads (1M QPS)
- Product catalog writes (10 QPS)

→ Split: CatalogReadService (100 instances), CatalogWriteService (2 instances)
         Don't over-provision for the slow part.
```

### 4. Fault Tolerance
```
Service D handles:
- Payment processing (critical, 99.99% required)
- Email notifications (non-critical, 99% acceptable)

→ Split: PaymentService, NotificationService
         Email failure shouldn't take down payments.
```

### 5. Security Requirements
```
Service E handles:
- Public product listings (no auth)
- PII data management (strict compliance)

→ Split: PublicCatalogService, PIIService (PCI-compliant)
         Different security zones, different networks.
```

## 🔗 Integrators (Forces That Merge Services)

### 1. Transactionality
```
Option A: OrderService + InventoryService + PaymentService
          → Distributed transaction, Saga, eventual consistency
          → Complexity: HIGH

Option B: OrderFulfillmentService (all three together)
          → Single database transaction, ACID
          → Complexity: LOW

If atomic transactions are required, keep them together.
```

### 2. Data Dependencies
```
OrderService needs:
- customer_email (from CustomerService)
- product_price (from CatalogService)
- inventory_count (from InventoryService)

If every request requires 3 network calls, consider:
- Denormalization (copy data locally)
- Merge services
- Event-driven sync (CQRS)
```

### 3. Workflow Coupling
```
Creating an order requires:
1. Validate customer
2. Check inventory
3. Calculate price
4. Create order
5. Reserve inventory
6. Charge payment
7. Send confirmation

If steps 1-7 always run together, orchestrating 7 services
adds complexity without benefit. Consider fewer, larger services.
```

---

# Part 2: The Three Primal Forces

## 🔺 The Saga Triangle

Every distributed workflow makes three architectural choices:

```
                    ┌─────────────────────┐
                    │    COMMUNICATION    │
                    │  Sync ←────→ Async  │
                    └──────────┬──────────┘
                               │
                               │
           ┌───────────────────┴───────────────────┐
           │                                       │
┌──────────┴──────────┐               ┌────────────┴────────────┐
│     CONSISTENCY     │               │      COORDINATION       │
│  Atomic ←──→ Eventual│               │  Orchestration ←→ Choreo │
└─────────────────────┘               └─────────────────────────┘
```

### The 8 Combinations

| # | Communication | Consistency | Coordination | Example |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Sync | Atomic | Orchestration | 2PC (avoid) |
| 2 | Sync | Atomic | Choreography | Chained calls (fragile) |
| 3 | Sync | Eventual | Orchestration | Saga with sync calls |
| 4 | Sync | Eventual | Choreography | Sync event chain |
| 5 | **Async** | Atomic | Orchestration | Rarely used |
| 6 | Async | Atomic | Choreography | Rarely used |
| 7 | **Async** | **Eventual** | **Orchestration** | **Recommended** |
| 8 | Async | Eventual | Choreography | Event-driven (loose) |

### Analysis of Common Patterns

#### Pattern 7: Async + Eventual + Orchestration (Recommended)
```
+ Decoupled (async messages)
+ Explicit workflow (orchestrator)
+ Compensatable (saga rollback)
+ Observable (orchestrator tracks state)

- Orchestrator is SPOF (must be HA)
- Higher latency (async)
- Eventual consistency (not for all use cases)

Best for: Complex multi-step workflows, e-commerce checkout
```

#### Pattern 8: Async + Eventual + Choreography
```
+ Maximum decoupling
+ No SPOF
+ Each service independent

- Hard to understand workflow
- Debugging is nightmare
- Cyclic event dependencies

Best for: Simple flows, event broadcasting (user signed up → welcome email)
```

---

# Part 3: Trade-off Analysis Techniques

## 📊 Weighted Decision Matrix

### Step 1: List Options
```
Options for inter-service communication:
A. Synchronous REST
B. Synchronous gRPC
C. Async message queue
D. Async event streaming (Kafka)
```

### Step 2: List Criteria with Weights
```
Criteria (weights based on YOUR context):

| Criterion | Weight | Why |
| :--- | :--- | :--- |
| Latency | 30% | Real-time user experience |
| Reliability | 25% | Payment critical |
| Debuggability | 20% | Small team |
| Scalability | 15% | Moderate growth expected |
| Team expertise | 10% | Already know REST |
```

### Step 3: Score (1-5) and Calculate
```
| Option | Latency (30%) | Reliability (25%) | Debug (20%) | Scale (15%) | Expertise (10%) | Total |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| REST | 4 (1.2) | 3 (0.75) | 5 (1.0) | 2 (0.3) | 5 (0.5) | 3.75 |
| gRPC | 5 (1.5) | 3 (0.75) | 3 (0.6) | 3 (0.45) | 2 (0.2) | 3.50 |
| Queue | 2 (0.6) | 5 (1.25) | 3 (0.6) | 4 (0.6) | 3 (0.3) | 3.35 |
| Kafka | 3 (0.9) | 5 (1.25) | 2 (0.4) | 5 (0.75) | 1 (0.1) | 3.40 |

Winner: REST (barely)
But: If reliability were 40% instead of 25%, Queue wins.
```

## 🎯 The MECE Principle

**Mutually Exclusive, Collectively Exhaustive**

```
WRONG comparison:
- Option A: Message Queue
- Option B: ESB (Enterprise Service Bus)

ESB CONTAINS a message queue. They're not mutually exclusive.
This comparison is invalid.

RIGHT comparison:
- Option A: Message Queue (point-to-point)
- Option B: Message Queue (pub/sub)
- Option C: Event Stream (Kafka)
- Option D: Direct RPC

These are mutually exclusive and cover the problem space.
```

## 🧠 Model Business Scenarios

Instead of abstract debates, model concrete use cases:

```
Scenario 1: "Add a new payment type (Crypto)"
- Option A (monolith): Change 5 files, deploy all
- Option B (microservices): Add CryptoPaymentAdapter, deploy 1 service

→ Microservices wins for extensibility

Scenario 2: "Process order with multiple payment types split"
- Option A (monolith): Single transaction, easy
- Option B (microservices): Saga across PaymentService1, PaymentService2

→ Monolith wins for transactional integrity

Conclusion: Depends on which scenario is more common/critical.
```

---

# Part 4: Coupling Analysis

## 📐 Types of Coupling

| Type | Definition | Severity | Example |
| :--- | :--- | :--- | :--- |
| **Pathological** | Service A modifies B's internals | 🔴 Worst | Direct DB access |
| **Content** | A depends on B's internal structure | 🔴 Very Bad | Shared mutable state |
| **Common** | Both depend on global data | 🟠 Bad | Shared config DB |
| **Control** | A tells B what to do | 🟡 Medium | Command messages |
| **Stamp** | A sends more data than B needs | 🟡 Medium | Fat DTOs |
| **Data** | A sends exactly what B needs | 🟢 Good | Minimal payloads |
| **Message** | A only knows B's interface | 🟢 Best | Queue contract |

## 🔍 Coupling Detection Patterns

### Static Coupling (Compile Time)
```
Service A imports Service B's types.

Detection:
- Dependency analysis tools (Gradle, Maven)
- Import graphs

Mitigation:
- API contracts (OpenAPI, Protobuf)
- Shared libraries → versioned
```

### Dynamic Coupling (Runtime)
```
Service A calls Service B synchronously.
If B is down, A fails.

Detection:
- Distributed tracing (Jaeger, Zipkin)
- Call graphs from production

Mitigation:
- Circuit breakers
- Async communication
- Fallback responses
```

### Semantic Coupling (Logic)
```
Service A and B both implement "is order valid?" logic.
If validation rules change, both must change.

Detection:
- Code search for duplicate logic
- ADR review

Mitigation:
- Extract to shared service
- Event-driven (A emits, B/C/D react)
```

---

# Part 5: Decision Records (ADRs)

## 📋 Architecture Decision Record Template

```markdown
# ADR-001: Use Event Sourcing for Order Service

## Status
Accepted

## Context
We need to maintain a complete audit trail of all order changes for compliance.
Traditional CRUD loses history.

## Decision
We will implement Event Sourcing for the Order aggregate.
All state changes stored as immutable events.

## Considered Alternatives

### Alternative 1: Audit Log Table
- Pros: Simple, familiar pattern
- Cons: Dual-write problem, can desync from order table
- **Rejected**: Risk of audit inconsistency

### Alternative 2: Database Triggers
- Pros: No application code change
- Cons: Vendor-specific, hard to test, hidden logic
- **Rejected**: Operational complexity

### Alternative 3: Change Data Capture (Debezium)
- Pros: No dual-write, works with existing CRUD
- Cons: Adds Kafka dependency, eventual consistency for audit reads
- **Considered**: Good fallback if Event Sourcing is too complex

## Consequences

### Positive
- Complete audit trail guaranteed
- Temporal queries (state at any point in time)
- Replayable (can rebuild read models)

### Negative
- Team needs to learn Event Sourcing
- Read model eventually consistent
- Storage grows indefinitely (need retention policy)

## Compliance
Legal reviewed and approved for regulatory requirements.

## Date
2024-01-15

## Authors
- @smith (Staff Architect)
- @jones (Principal Engineer)
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Trade-off documented | ADR exists for every major decision |
| 2 | Coupling mapped | Know static, dynamic, semantic coupling |
| 3 | Granularity analyzed | Ran through disintegrators and integrators |
| 4 | Saga type chosen explicitly | Know which of 8 patterns, why |
| 5 | Weighted criteria, not gut | Decision matrix with weights |
| 6 | Scenarios modeled | Tested decision against business use cases |
| 7 | "Least worst" acknowledged | No one pretending it's perfect |
| 8 | Rejected options documented | Future readers know what NOT to do |

---

## 🔗 Related Documents
*   [Saga Pattern](../distributive-backend/database/saga/saga-pattern-guide.md) — Implementation details.
*   [Evolutionary Architecture](./evolutionary-architecture-guide.md) — Fitness functions.
*   [Clean Architecture & C4](./clean-c4-guide.md) — Dependency inversion.