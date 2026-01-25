# Leader Election: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Raft Leader Election, Lease-Based Locks, Fencing Tokens, Split-Brain Prevention — Production Patterns

> [!CAUTION]
> **The Cardinal Sin**: Implementing your own leader election. Use ZooKeeper, etcd, or Consul. Every custom implementation has subtle bugs that surface at 3 AM.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Raft Paper](https://raft.github.io/raft.pdf) | Leader election, log replication |
| [Chubby: Lock Service for Loosely-Coupled Systems](https://research.google/pubs/the-chubby-lock-service-for-loosely-coupled-distributed-systems/) | Google's lock service |
| [How to do distributed locking (Martin Kleppmann)](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html) | Fencing tokens |

---

## 🎯 The Principal Laws of Leader Election

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Avoid If Possible** | Leader = SPOF | Prefer sharding, idempotent consumers |
| **Law 2: Leases Not Locks** | Locks can deadlock | Leases auto-expire |
| **Law 3: Fencing is Mandatory** | Old leaders can still act | Storage must reject stale writes |
| **Law 4: GC Pauses Kill** | 15s GC pause > 10s lease | Check clock after every pause |

---

# Part 1: When Leader Election is Actually Needed

## ✅ Valid Use Cases
```
- Single-writer database (primary selection)
- Scheduled job coordination (only one runs cron)
- Singleton services (metrics aggregator)
- Resource locks (batch job preventing duplicate runs)
```

## ❌ Better Alternatives
```
- Partitioned workloads (each node owns a shard)
- Idempotent consumers (all nodes process, dedupe downstream)
- Stateless workers (any node can handle any request)
- CRDTs (conflict-free data types, no coordination needed)
```

---

# Part 2: Algorithms Deep Dive

## 🗳️ Raft Leader Election

### State Machine
```
                    ┌─────────────────┐
         timeout    │    Follower     │
        ┌──────────►│                 │◄──────────┐
        │           └────────┬────────┘           │
        │                    │ timeout            │ discovers leader
        │                    ▼                    │ or higher term
        │           ┌─────────────────┐           │
        │           │    Candidate    │───────────┤
        │           └────────┬────────┘           │
        │                    │ majority votes     │
        │                    ▼                    │
        │           ┌─────────────────┐           │
        └───────────│     Leader      │───────────┘
             loses  └─────────────────┘
           election
```

### Implementation (Simplified)
```python
import random
import threading
import time
from enum import Enum
from dataclasses import dataclass
from typing import Optional, List

class State(Enum):
    FOLLOWER = "follower"
    CANDIDATE = "candidate"
    LEADER = "leader"

@dataclass
class RaftNode:
    node_id: str
    peers: List[str]
    
    current_term: int = 0
    voted_for: Optional[str] = None
    state: State = State.FOLLOWER
    
    election_timeout: float = 0  # Randomized
    last_heartbeat: float = 0
    
    leader_id: Optional[str] = None
    
    def reset_election_timeout(self):
        """Randomize between 150-300ms to prevent split votes."""
        self.election_timeout = random.uniform(0.15, 0.3)
        self.last_heartbeat = time.time()
    
    def election_timeout_elapsed(self) -> bool:
        return time.time() - self.last_heartbeat > self.election_timeout
    
    def start_election(self):
        """Convert to candidate and request votes."""
        self.state = State.CANDIDATE
        self.current_term += 1
        self.voted_for = self.node_id
        
        votes = 1  # Vote for self
        
        for peer in self.peers:
            if self.request_vote(peer):
                votes += 1
        
        if votes > len(self.peers) // 2:
            self.become_leader()
        else:
            self.state = State.FOLLOWER
    
    def request_vote(self, peer: str) -> bool:
        """RPC: Request vote from peer."""
        # In real implementation: gRPC/HTTP call
        response = rpc_call(peer, "RequestVote", {
            "term": self.current_term,
            "candidate_id": self.node_id,
            "last_log_index": len(self.log),
            "last_log_term": self.log[-1].term if self.log else 0
        })
        
        if response.term > self.current_term:
            self.current_term = response.term
            self.state = State.FOLLOWER
            return False
        
        return response.vote_granted
    
    def become_leader(self):
        """Won election, start sending heartbeats."""
        self.state = State.LEADER
        self.leader_id = self.node_id
        
        # Send initial heartbeat immediately
        self.send_heartbeats()
        
        # Start heartbeat timer (every 50ms)
        self.heartbeat_timer = threading.Timer(0.05, self.heartbeat_loop)
        self.heartbeat_timer.start()
    
    def handle_append_entries(self, term: int, leader_id: str):
        """Receive heartbeat from leader."""
        if term >= self.current_term:
            self.current_term = term
            self.state = State.FOLLOWER
            self.leader_id = leader_id
            self.reset_election_timeout()
```

## 🔒 Lease-Based Election (Production Standard)

### Concept
```
Leader acquires exclusive lease for time T (e.g., 10 seconds).
Leader renews lease every T/3 (e.g., 3 seconds).
If leader fails to renew, lease expires.
Another node acquires the lease.

Key insight: Clock skew + network delay must be << T
```

### etcd Lease Implementation
```python
import etcd3

class EtcdLeaderElection:
    def __init__(self, etcd_client, name: str, ttl: int = 10):
        self.client = etcd_client
        self.name = name
        self.ttl = ttl
        self.lease = None
        self.is_leader = False
    
    async def campaign(self, value: str):
        """Try to become leader. Blocks until leadership acquired."""
        self.lease = self.client.lease(self.ttl)
        
        # Create election key with lease
        key = f"/election/{self.name}/leader"
        
        # Try to create key (fails if exists)
        success, _ = self.client.transaction(
            compare=[
                self.client.transactions.version(key) == 0
            ],
            success=[
                self.client.transactions.put(key, value, lease=self.lease)
            ],
            failure=[]
        )
        
        if success:
            self.is_leader = True
            # Keep lease alive
            self.lease.keepalive()
        else:
            # Wait for current leader to fail
            self.watch_for_leader_death(key)
    
    def resign(self):
        """Voluntarily give up leadership."""
        if self.lease:
            self.lease.revoke()
        self.is_leader = False
    
    def watch_for_leader_death(self, key: str):
        """Watch key and campaign again when it's deleted."""
        events_iterator, cancel = self.client.watch(key)
        for event in events_iterator:
            if isinstance(event, etcd3.events.DeleteEvent):
                cancel()
                self.campaign()
                break

# Usage
client = etcd3.client()
election = EtcdLeaderElection(client, "my-service")

try:
    await election.campaign(value=f"node-{node_id}")
    while election.is_leader:
        # Do leader work
        process_as_leader()
finally:
    election.resign()
```

### Kubernetes Leader Election
```yaml
# Kubernetes Lease object for leader election
apiVersion: coordination.k8s.io/v1
kind: Lease
metadata:
  name: my-service-leader
  namespace: default
spec:
  holderIdentity: "pod-abc123"
  leaseDurationSeconds: 15
  acquireTime: "2024-01-01T00:00:00Z"
  renewTime: "2024-01-01T00:00:05Z"
  leaseTransitions: 3
```

```go
// Go: client-go leader election
import (
    "k8s.io/client-go/tools/leaderelection"
    "k8s.io/client-go/tools/leaderelection/resourcelock"
)

func runWithLeaderElection(ctx context.Context, id string) {
    lock := &resourcelock.LeaseLock{
        LeaseMeta: metav1.ObjectMeta{
            Name:      "my-service-leader",
            Namespace: "default",
        },
        Client: client.CoordinationV1(),
        LockConfig: resourcelock.ResourceLockConfig{
            Identity: id,
        },
    }
    
    leaderelection.RunOrDie(ctx, leaderelection.LeaderElectionConfig{
        Lock:          lock,
        LeaseDuration: 15 * time.Second,
        RenewDeadline: 10 * time.Second,
        RetryPeriod:   2 * time.Second,
        Callbacks: leaderelection.LeaderCallbacks{
            OnStartedLeading: func(ctx context.Context) {
                // Start leader work
                runLeaderLoop(ctx)
            },
            OnStoppedLeading: func() {
                // Lost leadership
                log.Info("Lost leadership, shutting down")
                os.Exit(0)  // Fail fast
            },
            OnNewLeader: func(identity string) {
                if identity != id {
                    log.Info("New leader elected", "leader", identity)
                }
            },
        },
    })
}
```

---

# Part 3: Split-Brain Prevention

## 💀 The Problem

```
Timeline:
T0:  NodeA is leader, has lease until T10
T5:  NodeA enters GC pause (15 seconds)
T10: Lease expires, NodeB becomes leader
T15: NodeA wakes up
T16: NodeA writes to DB (thinks it's still leader)
T17: NodeB writes to DB (is the actual leader)

Result: Both nodes wrote → DATA CORRUPTION
```

## 🛡️ Solution 1: Fencing Tokens

```
Every lease grant includes a monotonic epoch/token.

Epoch 1: NodeA becomes leader
Epoch 2: NodeB becomes leader (after A's lease expires)

Storage layer tracks max_epoch_seen.
Rejects any write with epoch < max_epoch_seen.
```

### Implementation
```python
class FencedStorage:
    def __init__(self):
        self.data = {}
        self.max_epoch_seen = 0
    
    def write(self, key: str, value: any, epoch: int):
        """Write only if epoch is current."""
        if epoch < self.max_epoch_seen:
            raise StaleEpochError(
                f"Epoch {epoch} < max seen {self.max_epoch_seen}"
            )
        
        self.max_epoch_seen = max(self.max_epoch_seen, epoch)
        self.data[key] = value
        return True

class LeaderWithFencing:
    def __init__(self, storage: FencedStorage, lock_service):
        self.storage = storage
        self.lock_service = lock_service
        self.current_epoch = 0
    
    def acquire_leadership(self):
        # etcd/ZK returns epoch with lease
        lease, epoch = self.lock_service.acquire_lease("leader")
        self.current_epoch = epoch
        return lease
    
    def write_as_leader(self, key: str, value: any):
        # Always include epoch in write
        try:
            self.storage.write(key, value, self.current_epoch)
        except StaleEpochError:
            # We're a zombie leader!
            self.step_down()
            raise NotLeaderError()
```

### ZooKeeper Sequential Znodes
```
/election/leader-0000000001  (NodeA)
/election/leader-0000000002  (NodeB, after A dies)

The sequence number IS the fencing token.
```

## 🛡️ Solution 2: Check-Then-Act (Weaker)

```python
class CarefulLeader:
    def __init__(self, lock_service):
        self.lock_service = lock_service
        self.lease = None
    
    def do_work(self):
        # Check before every critical section
        if not self.still_hold_lease():
            raise NotLeaderError()
        
        # GC pause could happen HERE
        
        # Do work...
        self.write_to_db()
    
    def still_hold_lease(self) -> bool:
        # Check clock: lease_expiry - now > safety_margin
        return self.lease.expires_at - time.time() > 2.0
```

> [!WARNING]
> **This is NOT sufficient alone.** A GC pause AFTER the check but BEFORE the write can still cause split-brain. Use fencing tokens.

---

# Part 4: Production Patterns

## 📊 Monitoring

```yaml
# Prometheus metrics
groups:
  - name: leader_election
    rules:
      - alert: NoLeader
        expr: sum(leader_election_is_leader) == 0
        for: 1m
        annotations:
          summary: "No leader elected for 1 minute"
      
      - alert: MultipleLeaders
        expr: sum(leader_election_is_leader) > 1
        for: 10s
        labels:
          severity: critical
        annotations:
          summary: "SPLIT BRAIN: Multiple leaders detected"
      
      - alert: LeaderFlapping
        expr: increase(leader_election_transitions_total[10m]) > 5
        annotations:
          summary: "Leader changing too frequently"
      
      - alert: LeaseRenewalSlow
        expr: |
          histogram_quantile(0.99, rate(leader_lease_renewal_duration_seconds_bucket[5m])) 
          > 
          (leader_lease_ttl_seconds * 0.3)
        annotations:
          summary: "Lease renewal taking >30% of lease TTL"
```

## 🔧 Best Practices

### 1. Fail Fast on Leadership Loss
```python
def leader_loop():
    while is_leader():
        try:
            process_batch()
        except NotLeaderError:
            log.error("Lost leadership, shutting down")
            sys.exit(1)  # Let orchestrator restart us

# Don't try to gracefully become follower.
# Crash and let Kubernetes/systemd restart you.
```

### 2. Lease TTL Sizing
```
lease_ttl > 3 * (network_rtt + max_gc_pause + clock_skew)

Example:
  network_rtt = 10ms
  max_gc_pause = 500ms (Go/Rust) or 5s (Java without tuning)
  clock_skew = 100ms

  lease_ttl > 3 * (10 + 500 + 100) = 1830ms

For Java with 5s GC pauses: lease_ttl > 15s
Renewal interval: 5s
```

### 3. Graceful Shutdown
```python
def shutdown():
    # 1. Stop accepting new work
    stop_processing()
    
    # 2. Resign leadership BEFORE process death
    election.resign()
    
    # 3. Wait for in-flight work to complete
    wait_for_in_flight(timeout=10)
    
    # 4. Exit
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown)
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Using battle-tested library (etcd, ZK, Consul) | Not custom implementation |
| 2 | Fencing tokens implemented | Storage rejects stale epochs |
| 3 | Fail-fast on leadership loss | Process exits, not graceful |
| 4 | Lease TTL accounts for GC | TTL > 3x max pause |
| 5 | Monitoring for split-brain | Alert on multiple leaders |
| 6 | Clock sync verified | NTP configured, chrony running |
| 7 | Graceful resignation on shutdown | Resign before exit |
| 8 | Documented why leader is needed | Not just "because" |

---

## 🔗 Related Documents
*   [Replication & Consistency](../distributive-backend/database/replication-consistency-guide.md) — Raft/Paxos details.
*   [Distributed Systems Patterns](./distributed-systems-patterns-comprehensive.md) — Broader patterns.
*   [Sharding Architecture](../sharding-techniques-and-notes/sharding-architecture-guide.md) — Alternative to leaders.
