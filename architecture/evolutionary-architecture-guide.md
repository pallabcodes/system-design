# Evolutionary Architecture: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ Engineer
> **Scope**: Fitness Functions, Architecture Governance, ArchUnit, Incremental Change — Production Patterns

> [!CAUTION]
> **The Cardinal Sin**: Big Bang Rewrites. 90% of rewrites fail. Evolutionary architecture enables incremental, safe change. If your architecture cannot evolve, it is already legacy.

---

## 📚 Required Reading

| Book/Resource | Author | Topic |
| :--- | :--- | :--- |
| [Building Evolutionary Architectures](https://www.oreilly.com/library/view/building-evolutionary-architectures/9781491986356/) | Ford, Parsons, Kua | Fitness functions |
| [Continuous Delivery](https://martinfowler.com/books/continuousDelivery.html) | Humble, Farley | Deployment pipeline |
| [Team Topologies](https://teamtopologies.com/) | Skelton, Pais | Inverse Conway |

---

## 🎯 The Principal Laws of Evolutionary Architecture

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Change is Constant** | Requirements will change | Design for adaptability |
| **Law 2: Fitness Functions Guide** | Define what "good" looks like | Automated governance |
| **Law 3: Incremental Over Big Bang** | Small changes, fast feedback | Reduce risk |
| **Law 4: Teams Mirror Architecture** | Conway's Law is inevitable | Align teams to structure |

---

# Part 1: Fitness Functions

## 🧪 What is a Fitness Function?

**Definition**: An objective, automated assessment of some architectural characteristic.

```
In biology: Evolution is random, survival determines fitness.
In software: Evolution is GUIDED by automated tests.

Traditional testing: "Does feature X work?"
Fitness functions:   "Does architecture retain property Y?"
```

## 📊 Types of Fitness Functions

| Type | Runs | Tests | Example |
| :--- | :--- | :--- | :--- |
| **Atomic** | Per commit | Single characteristic | No cyclic dependencies |
| **Holistic** | Periodic | System behavior | P99 latency < 100ms |
| **Continuous** | Production | Live system | Chaos engineering |

### Atomic Fitness Functions (CI Pipeline)

```yaml
# .github/workflows/fitness.yml
name: Architectural Fitness

on: [push, pull_request]

jobs:
  architecture:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run ArchUnit Tests
        run: ./gradlew archunitTest
      
      - name: Check Cyclic Dependencies
        run: |
          madge --circular --extensions ts src/
          if [ $? -ne 0 ]; then
            echo "Cyclic dependencies detected!"
            exit 1
          fi
      
      - name: Check Layer Violations
        run: ./gradlew checkLayerDependencies
      
      - name: Lint OpenAPI Schema
        run: spectral lint api/openapi.yaml
      
      - name: Check SQL Migration Backwards Compatibility
        run: |
          # Ensure no DROP COLUMN in migrations
          if grep -r "DROP COLUMN" migrations/; then
            echo "Breaking migration detected!"
            exit 1
          fi
```

### ArchUnit (Java/Kotlin)
```java
// ArchUnit fitness function for layered architecture
@AnalyzeClasses(packages = "com.example.orderservice")
public class LayerFitnessTest {
    
    @ArchTest
    static final ArchRule domainShouldNotDependOnAdapters =
        noClasses()
            .that().resideInAPackage("..domain..")
            .should().dependOnClassesThat()
            .resideInAnyPackage("..adapters..", "..infrastructure..");
    
    @ArchTest
    static final ArchRule controllersShouldOnlyCallUseCases =
        classes()
            .that().resideInAPackage("..controllers..")
            .should().onlyDependOnClassesThat()
            .resideInAnyPackage("..usecases..", "..dto..", "java..", "javax..");
    
    @ArchTest
    static final ArchRule noCyclicDependencies =
        slices()
            .matching("com.example.orderservice.(*)..")
            .should().beFreeOfCycles();
    
    @ArchTest
    static final ArchRule repositoriesOnlyInAdapters =
        classes()
            .that().haveSimpleNameEndingWith("Repository")
            .and().areNotInterfaces()
            .should().resideInAPackage("..adapters..");
}
```

### Go Architecture Tests
```go
// arch_test.go
package arch_test

import (
    "go/ast"
    "go/parser"
    "go/token"
    "path/filepath"
    "strings"
    "testing"
)

func TestDomainHasNoExternalImports(t *testing.T) {
    domainDir := "internal/domain"
    allowedPrefixes := []string{"", "errors", "time", "fmt", "context"}
    
    fset := token.NewFileSet()
    pkgs, err := parser.ParseDir(fset, domainDir, nil, parser.ImportsOnly)
    if err != nil {
        t.Fatal(err)
    }
    
    for _, pkg := range pkgs {
        for fileName, file := range pkg.Files {
            for _, imp := range file.Imports {
                importPath := strings.Trim(imp.Path.Value, "\"")
                
                isAllowed := false
                for _, prefix := range allowedPrefixes {
                    if strings.HasPrefix(importPath, prefix) {
                        isAllowed = true
                        break
                    }
                }
                
                if !isAllowed && strings.Contains(importPath, "/") {
                    t.Errorf("%s imports external package: %s", fileName, importPath)
                }
            }
        }
    }
}

func TestAdaptersImplementPorts(t *testing.T) {
    // Verify all interfaces in domain/ports are implemented
    ports := findInterfaces("internal/domain/ports")
    implementations := findImplementations("internal/adapters")
    
    for _, port := range ports {
        if !containsImplementation(implementations, port) {
            t.Errorf("No implementation found for port: %s", port)
        }
    }
}
```

### Holistic Fitness Functions (Periodic)

```yaml
# Load test as fitness function
name: Performance Fitness

on:
  schedule:
    - cron: '0 2 * * *'  # Nightly

jobs:
  load-test:
    runs-on: ubuntu-latest
    steps:
      - name: Run k6 Load Test
        run: |
          k6 run -e TARGET=$STAGING_URL load-test.js
          
      - name: Check P99 Latency
        run: |
          P99=$(jq '.metrics.http_req_duration.p99' results.json)
          if (( $(echo "$P99 > 100" | bc -l) )); then
            echo "P99 latency $P99 ms exceeds 100ms threshold"
            exit 1
          fi
```

### Continuous Fitness Functions (Production)

```python
# Chaos engineering fitness function
# Runs continuously in production

class ChaosFitness:
    def __init__(self, prometheus_url: str, thresholds: dict):
        self.prom = PrometheusClient(prometheus_url)
        self.thresholds = thresholds
    
    def run_experiment(self, experiment_name: str, action: callable):
        # Record baseline
        baseline_error_rate = self.get_error_rate()
        baseline_latency = self.get_p99_latency()
        
        # Execute chaos action (e.g., kill a pod)
        action()
        
        # Wait for impact
        time.sleep(30)
        
        # Measure impact
        current_error_rate = self.get_error_rate()
        current_latency = self.get_p99_latency()
        
        # Fitness assessment
        error_rate_impact = current_error_rate - baseline_error_rate
        latency_impact = current_latency - baseline_latency
        
        if error_rate_impact > self.thresholds['max_error_rate_increase']:
            self.alert(f"{experiment_name}: Error rate increased by {error_rate_impact}%")
            return False
        
        if latency_impact > self.thresholds['max_latency_increase_ms']:
            self.alert(f"{experiment_name}: Latency increased by {latency_impact}ms")
            return False
        
        return True
```

---

# Part 2: Incremental Change

## 🦎 The Strangler Fig Pattern

```
Old System (Monolith)              New System (Services)
┌─────────────────────┐            ┌────────────────────┐
│                     │            │                    │
│  ┌───────────────┐  │            │  ┌──────────────┐  │
│  │  Billing      │──┼────────────┼──►  BillingAPI  │  │
│  └───────────────┘  │            │  └──────────────┘  │
│                     │            │                    │
│  ┌───────────────┐  │            │                    │
│  │  Orders       │  │◄───────────┼── (still in mono) │
│  └───────────────┘  │            │                    │
│                     │            │                    │
│  ┌───────────────┐  │            │  ┌──────────────┐  │
│  │  Shipping     │──┼────────────┼──►  ShipService │  │
│  └───────────────┘  │            │  └──────────────┘  │
│                     │            │                    │
└─────────────────────┘            └────────────────────┘
         │                                   │
         └───────────────┬───────────────────┘
                         │
            ┌────────────▼────────────┐
            │     Facade/Router       │
            │  (Routes traffic)       │
            └─────────────────────────┘
                         │
                    ┌────▼────┐
                    │ Client  │
                    └─────────┘
```

### Implementation: Feature Flags for Migration
```python
class OrderFacade:
    def __init__(self, legacy_client, new_order_service, feature_flags):
        self.legacy = legacy_client
        self.new_svc = new_order_service
        self.flags = feature_flags
    
    def create_order(self, order_request):
        # Shadow mode: Write to both, compare results
        if self.flags.is_enabled("orders.shadow_mode"):
            legacy_result = self.legacy.create_order(order_request)
            new_result = self.new_svc.create_order(order_request)
            
            if legacy_result != new_result:
                self.log_diff("create_order", legacy_result, new_result)
            
            return legacy_result  # Return legacy for now
        
        # Canary mode: 5% traffic to new service
        if self.flags.is_enabled("orders.canary_mode"):
            if random.random() < 0.05:
                return self.new_svc.create_order(order_request)
            return self.legacy.create_order(order_request)
        
        # Full migration: All traffic to new service
        if self.flags.is_enabled("orders.full_migration"):
            return self.new_svc.create_order(order_request)
        
        return self.legacy.create_order(order_request)
```

## 🔄 Parallel Change (Expand-Contract)

### Step 1: Expand (Add New)
```sql
-- Migration V1: Add new column alongside old
ALTER TABLE users ADD COLUMN full_name VARCHAR(255);

-- Backfill
UPDATE users SET full_name = first_name || ' ' || last_name;

-- Application: Write to BOTH columns
def update_user(user_id, first_name, last_name):
    db.execute("""
        UPDATE users 
        SET first_name = %s, last_name = %s, 
            full_name = %s
        WHERE id = %s
    """, [first_name, last_name, f"{first_name} {last_name}", user_id])
```

### Step 2: Migrate (Switch Readers)
```python
# Old code
def get_display_name(user):
    return f"{user.first_name} {user.last_name}"

# New code (feature flag)
def get_display_name(user):
    if feature_flags.is_enabled("use_full_name"):
        return user.full_name
    return f"{user.first_name} {user.last_name}"
```

### Step 3: Contract (Remove Old)
```sql
-- Migration V2: Remove old columns (after all readers migrated)
ALTER TABLE users DROP COLUMN first_name;
ALTER TABLE users DROP COLUMN last_name;
```

---

# Part 3: Inverse Conway Maneuver

## 🏢 Conway's Law

```
"Organizations which design systems are constrained to produce 
designs which are copies of the communication structures of 
these organizations."
     — Melvin Conway, 1967

If you have:
- UI Team, Backend Team, DBA Team

You will build:
- UI Monolith, Backend Monolith, Shared Database

Even if you wanted microservices.
```

## 🔄 The Inverse Maneuver

```
Step 1: Design the architecture you WANT
Step 2: Reorganize teams to MATCH that architecture
Step 3: Teams naturally build the desired structure

Example:
Desired: Microservices for Orders, Payments, Shipping

Before:        After:
┌──────────┐   ┌─────────────────┐
│ UI Team  │   │ Order Squad     │
├──────────┤   │ (Full Stack)    │
│ API Team │   ├─────────────────┤
├──────────┤   │ Payment Squad   │
│ DBA Team │   │ (Full Stack)    │
└──────────┘   ├─────────────────┤
               │ Shipping Squad  │
               │ (Full Stack)    │
               └─────────────────┘

Each squad owns: UI + API + DB + Ops
```

## 📐 Team Topologies Alignment

| Team Type | Owns | Examples |
| :--- | :--- | :--- |
| **Stream-Aligned** | End-to-end value stream | Order Squad, Checkout Squad |
| **Platform** | Internal tooling for stream teams | CI/CD, Kubernetes, Databases |
| **Enabling** | Helps stream teams adopt new tech | Security coaching, SRE consulting |
| **Complicated Subsystem** | Deep specialist domain | ML models, Payment processor |

```yaml
# Team APIs (explicit contracts)
Order Squad:
  provides:
    - OrderService API (OpenAPI)
    - order-created events (CloudEvents)
  consumes:
    - PaymentService API
    - InventoryService events
  platform_needs:
    - Kubernetes namespace
    - PostgreSQL database
    - Kafka topics
```

---

# Part 4: Last Responsible Moment

## ⏰ Defer Decisions

```
Traditional: Decide database on Day 1 (might be wrong)
Evolutionary: Use Repository interface, decide database when needed

class UserRepository(Protocol):
    def save(self, user: User) -> None: ...
    def find_by_id(self, id: str) -> Optional[User]: ...

# Day 1: Use in-memory (for fast tests)
class InMemoryUserRepository:
    def __init__(self):
        self.users = {}
    
    def save(self, user: User):
        self.users[user.id] = user

# Day 30: Switch to PostgreSQL (when needed)
class PostgresUserRepository:
    def __init__(self, db: Connection):
        self.db = db
    
    def save(self, user: User):
        self.db.execute(...)

# Application code unchanged
```

## 🎯 Decision Irreversibility Matrix

| Decision | Reversibility | When to Decide |
| :--- | :--- | :--- |
| **Programming language** | Hard | Early (team skills) |
| **Cloud provider** | Medium | Early-ish (with abstraction) |
| **Database type** | Medium | After access patterns known |
| **Framework** | Easy | Can change per service |
| **Library version** | Easy | Latest stable |

---

# Part 5: Architecture Governance

## 📋 Architecture Decision Records (ADRs)

```
docs/architecture/decisions/
├── 001-use-golang-for-services.md
├── 002-postgresql-as-primary-database.md
├── 003-kafka-for-event-streaming.md
├── 004-grpc-for-inter-service-communication.md
└── 005-deprecated-rest-for-internal-apis.md
```

### ADR Template
```markdown
# ADR-004: Use gRPC for Inter-Service Communication

## Status
Accepted (2024-01-15)
Supersedes: ADR-002 (REST for all APIs)

## Context
With 15+ microservices, REST overhead is noticeable.
Latency-sensitive paths (order → inventory → payment) need optimization.

## Decision
New inter-service APIs will use gRPC.
Public APIs remain REST for browser compatibility.

## Consequences
- Better: Latency reduced by ~40%
- Better: Type-safe contracts (protobuf)
- Worse: Learning curve for team
- Worse: gRPC-web needed for browser calls

## Fitness Function
- ArchUnit: Services in critical path must use gRPC clients
- Latency SLO: P99 < 50ms for gRPC calls
```

## 📊 Governance Dashboard

```yaml
# metrics/architecture-health.yaml
metrics:
  - name: cyclic_dependencies
    query: "archunit.violations{type='cyclic'}"
    threshold: 0
    severity: critical
  
  - name: layer_violations
    query: "archunit.violations{type='layer'}"
    threshold: 0
    severity: high
  
  - name: api_compatibility_breaks
    query: "spectral.errors{severity='error'}"
    threshold: 0
    severity: critical
  
  - name: tech_debt_issues
    query: "sonarqube.issues{type='CODE_SMELL'}"
    threshold: 100
    severity: warning
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Fitness functions in CI | Pipeline fails on violation |
| 2 | ADRs for major decisions | Git history of decisions |
| 3 | Incremental migration strategy | Strangler/parallel change |
| 4 | Teams aligned to architecture | One team, one service |
| 5 | Last responsible moment applied | Abstractions for deferral |
| 6 | Deploy frequency < 1 day | CI/CD optimized |
| 7 | Architecture dashboard exists | Visibility for all |
| 8 | Tech debt tracked as work | In sprint backlog |

---

## 🔗 Related Documents
*   [Clean Architecture & C4](./clean-c4-guide.md) — Dependency inversion.
*   [Architecture Hard Parts](./hard-parts.md) — Trade-off analysis.
*   [Saga Pattern](../distributive-backend/database/saga/saga-pattern-guide.md) — Distributed workflows.
