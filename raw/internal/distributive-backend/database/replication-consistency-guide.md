# Replication & Consistency: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Paxos, Raft, TrueTime, CRDTs, Vector Clocks — With Paper References and Production Patterns

> [!CAUTION]
> **The Cardinal Sin**: Assuming "eventually consistent" means "eventually correct." Without proper conflict resolution, eventual consistency means **eventual data loss**.

---

## 📚 Required Reading (Research Papers)

| Paper | Year | Key Concepts |
| :--- | :--- | :--- |
| [Paxos Made Simple](https://lamport.azurewebsites.net/pubs/paxos-simple.pdf) | 2001 | Consensus algorithm |
| [In Search of an Understandable Consensus Algorithm (Raft)](https://raft.github.io/raft.pdf) | 2014 | Leader election, log replication |
| [Spanner: Google's Globally Distributed Database](https://research.google/pubs/spanner-googles-globally-distributed-database/) | 2012 | TrueTime, external consistency |
| [Dynamo: Amazon's Key-value Store](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf) | 2007 | Sloppy quorum, vector clocks |
| [CRDTs: Making δ-CRDTs Delta-State-Based](https://arxiv.org/abs/1603.01529) | 2016 | Conflict-free data types |

---

## 🎯 The Principal Laws of Distributed Consistency

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **CAP Theorem** | Choose 2 of: Consistency, Availability, Partition tolerance | You always have P. Choose C or A. |
| **PACELC** | If Partition: A vs C. Else: Latency vs Consistency | Even without partitions, there's a trade-off |
| **FLP Impossibility** | No async consensus can guarantee termination | All consensus relies on timeouts (failure detectors) |
| **Speed of Light** | NYC → London = 70ms round-trip | Synchronous replication across oceans = 140ms writes |

---

# Part 1: Replication Topologies

## 📡 Single-Leader (Primary-Replica)

```
           Writes
              │
              ▼
        ┌──────────┐
        │  Leader  │  ── WAL/Binlog ──► Follower 1
        └──────────┘                 ├─► Follower 2
                                     └─► Follower 3
              │
              ▼
           Reads (may be stale)
```

### Synchronous vs Asynchronous

| Mode | Durability | Latency | Availability |
| :--- | :--- | :--- | :--- |
| **Sync** | Committed to N replicas | High (wait for replicas) | Low (bloc if replica down) |
| **Async** | Committed to leader only | Low | High |
| **Semi-sync** | 1 sync replica, rest async | Medium | Medium |

### PostgreSQL: Synchronous Replication
```sql
-- postgresql.conf on primary
synchronous_standby_names = 'FIRST 2 (standby1, standby2, standby3)'
-- Waits for first 2 to acknowledge before commit

-- Connection string for routing
-- primary: read-write
-- standby: read-only
host=primary,standby1,standby2 target_session_attrs=read-write
```

### The Replication Lag Problem
```python
# Problem: User writes, then reads from replica
def update_profile(user_id, new_name):
    db.execute("UPDATE users SET name = %s WHERE id = %s", [new_name, user_id])
    
def get_profile(user_id):
    return db.execute("SELECT * FROM users WHERE id = %s", [user_id])
    # Might return OLD data if reading from replica

# Solution 1: Read-your-writes (session token)
def get_profile(user_id, last_write_lsn):
    connection = get_replica_caught_up_to(last_write_lsn)
    return connection.execute("SELECT * FROM users WHERE id = %s", [user_id])

# Solution 2: Sticky sessions (same connection for read/write)
# Solution 3: Always read from primary after write (simple but doesn't scale)
```

## 🔀 Multi-Leader (Active-Active)

```
        DC1                          DC2
    ┌──────────┐                ┌──────────┐
    │ Leader 1 │◄──────────────►│ Leader 2 │
    └──────────┘  Async Sync    └──────────┘
         │                           │
    [Clients]                   [Clients]
```

### When to Use
```
✅ Multiple data centers with local writes
✅ Offline-capable clients (like Git)
✅ Collaborative editing (Google Docs)

❌ Strong consistency required
❌ Transaction isolation required
❌ Simple applications (just use single-leader)
```

### Conflict Detection
```python
# Conflict: Same row updated in both DCs concurrently

# DC1: UPDATE users SET name = 'Alice' WHERE id = 1;  at t=100
# DC2: UPDATE users SET name = 'Bob' WHERE id = 1;    at t=101

# When replication happens, both see both updates.
# Who wins?
```

---

# Part 2: Consensus Algorithms

## ⚖️ Paxos (The Original)

**Paper**: [Paxos Made Simple](https://lamport.azurewebsites.net/pubs/paxos-simple.pdf)

### The Roles
```
Proposer: Proposes values to be agreed upon
Acceptor: Votes on proposals (need majority)
Learner:  Learns the agreed value (often same as Proposer)
```

### The Protocol (Single Decree)
```
Phase 1: PREPARE
  Proposer → Acceptors: "Prepare(n)" where n is proposal number
  Acceptors → Proposer: "Promise(n, v)" if n > any seen, return highest accepted (v)

Phase 2: ACCEPT
  Proposer → Acceptors: "Accept(n, v)" where v is value to propose
  Acceptors → Proposer: "Accepted(n, v)" if proposal still valid

Phase 3: LEARN
  Once majority accepted, Proposer → Learners: "Committed(v)"
```

### Why Paxos is Hard
```
1. Multiple proposers can conflict → livelock
2. Need log of decrees for Multi-Paxos
3. Leader election is implicit (proposal numbers)
4. Reconfiguration is complex

Solution: Use Raft instead.
```

## 🔄 Raft (The Understandable Consensus)

**Paper**: [In Search of an Understandable Consensus Algorithm](https://raft.github.io/raft.pdf)

### The State Machine
```
                    ┌─────────┐
         timeout    │Follower │
        ┌──────────►│         │◄──────────┐
        │           └────┬────┘           │
        │                │ timeout        │ higher term
        │                ▼                │
        │           ┌─────────┐           │
        │           │Candidate│───────────┤
        │           └────┬────┘           │
        │                │ majority votes │
        │                ▼                │
        │           ┌─────────┐           │
        └───────────│ Leader  │───────────┘
                    └─────────┘
```

### Leader Election
```
1. Follower timeout (no heartbeat from leader)
2. Convert to Candidate, increment term, vote for self
3. RequestVote RPC to all peers
4. If majority votes: Become Leader
5. If another leader seen: Become Follower
6. If election timeout: Start new election
```

### Log Replication
```
Leader receives client request:
1. Append entry to local log (uncommitted)
2. AppendEntries RPC to all followers
3. Wait for majority acknowledgment
4. Commit entry (apply to state machine)
5. Send commit index to followers in next heartbeat
6. Respond to client

Log structure:
[term=1, index=1, cmd="x=1"]
[term=1, index=2, cmd="y=2"]
[term=2, index=3, cmd="x=3"]  ← New leader
```

### Safety Properties
```
Election Safety:   At most one leader per term
Leader Append-Only: Leader never overwrites/deletes, only appends
Log Matching:       If two logs have entry with same index+term, 
                    all prior entries are identical
Leader Completeness: If entry committed in term T, it will be in 
                     all leaders' logs for terms > T
State Machine Safety: If server applies entry at index, no other 
                      server applies different entry at same index
```

### etcd/Consul Implementation
```yaml
# etcd cluster configuration
ETCD_INITIAL_CLUSTER: "node1=http://10.0.0.1:2380,node2=http://10.0.0.2:2380,node3=http://10.0.0.3:2380"
ETCD_INITIAL_CLUSTER_STATE: "new"
ETCD_HEARTBEAT_INTERVAL: "100"     # ms between heartbeats
ETCD_ELECTION_TIMEOUT: "1000"      # ms before starting election
ETCD_SNAPSHOT_COUNT: "10000"       # Entries before taking snapshot
```

---

# Part 3: TrueTime & External Consistency

**Paper**: [Spanner: Google's Globally Distributed Database](https://research.google/pubs/spanner-googles-globally-distributed-database/)

## 🕐 The Problem with Wall Clocks

```python
# Node A and Node B both write at "the same time"
# Node A clock: 10:00:00.000
# Node B clock: 10:00:00.003 (3ms ahead due to drift)

# From Node B's perspective, its write is "later"
# But in real time, they might be concurrent

# NTP synchronization: ~100ms accuracy
# That's 100ms of uncertainty in event ordering!
```

## ⏱️ TrueTime API

```
TrueTime.now() returns an interval: [earliest, latest]

tt = TrueTime.now()
tt.earliest = 1704067200000000  # Can't be before this (microseconds)
tt.latest   = 1704067200007000  # Can't be after this
tt.error    = 7ms               # Uncertainty window

GUARANTEE: The true current time is definitely within [earliest, latest]
```

### Implementation
```
Hardware:
- GPS receivers in every datacenter → μs accuracy to UTC
- Atomic clocks as backup → drift < 200μs/second
- Armageddon masters: GPS + atomic clock servers

Software:
- Daemons poll multiple time sources
- Statistical analysis to bound error
- Report [earliest, latest] interval
```

## 🔒 Commit-Wait Protocol

```
Goal: If transaction T1 commits before T2 starts, T1 is visible to T2.
      (External consistency / Linearizability)

Protocol:
1. Acquire locks (Paxos for distributed)
2. Pick commit timestamp s = TrueTime.now().latest
3. WAIT until TrueTime.now().earliest > s  ("commit-wait")
4. Commit and release locks

Why it works:
- We chose s at the END of possible time intervals
- We waited until we were DEFINITELY past s
- Any later transaction starts AFTER our wait completes
- Therefore, any later read sees our write
```

### Latency Cost
```
Typical TrueTime error: 1-7ms (datacenter-local GPS sync)
Commit-wait: Average 7ms delay

Cross-region (no GPS sync): ~100ms+ error
Commit-wait: Up to 100ms delay

This is why Spanner is datacenter-optimized.
```

---

# Part 4: Leaderless Replication & Quorums

**Paper**: [Dynamo: Amazon's Highly Available Key-value Store](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf)

## 📊 Quorum Math

```
N = Total replicas
W = Write quorum (replicas that must acknowledge write)
R = Read quorum (replicas that must respond to read)

For read-your-writes consistency:
W + R > N

For single-key linearizability:
W > N/2 AND R > N/2

Common configurations:
N=3, W=2, R=2 (majority quorum, strong consistency)
N=3, W=1, R=1 (fast but weak, eventual consistency)
N=3, W=3, R=1 (durable writes, fast reads)
```

## 🔄 Read Repair & Anti-Entropy

```python
# Read Repair (opportunistic)
def read(key):
    responses = query_all_replicas(key)
    latest = find_newest_version(responses)
    
    for replica, value in responses:
        if value.version < latest.version:
            # Stale replica found, repair in background
            async_repair(replica, key, latest)
    
    return latest

# Anti-Entropy (background process)
# Merkle trees: Hash of hashes for efficient comparison
def anti_entropy():
    while True:
        for peer in peers:
            my_tree = build_merkle_tree(my_data)
            their_tree = peer.get_merkle_tree()
            
            diff_ranges = find_differences(my_tree, their_tree)
            for range in diff_ranges:
                sync_range(peer, range)
        
        sleep(interval)
```

## 🕐 Version Vectors (Better Than Lamport Clocks)

```python
# Lamport clock: Single integer, can't detect concurrency
# Version vector: One counter per node

# Node A writes: {A: 1}
# Node B writes: {B: 1}
# Both versions have no causal relationship → CONCURRENT

class VersionVector:
    def __init__(self):
        self.clocks = {}  # node_id → counter
    
    def increment(self, node_id):
        self.clocks[node_id] = self.clocks.get(node_id, 0) + 1
    
    def merge(self, other):
        for node_id, counter in other.clocks.items():
            self.clocks[node_id] = max(self.clocks.get(node_id, 0), counter)
    
    def compare(self, other):
        """Returns: 'before', 'after', 'concurrent', 'equal'"""
        dominated = True
        dominates = True
        
        for node_id in set(self.clocks) | set(other.clocks):
            my_val = self.clocks.get(node_id, 0)
            their_val = other.clocks.get(node_id, 0)
            
            if my_val > their_val:
                dominated = False
            if my_val < their_val:
                dominates = False
        
        if dominated and dominates:
            return 'equal'
        elif dominated:
            return 'before'
        elif dominates:
            return 'after'
        else:
            return 'concurrent'
```

---

# Part 5: Conflict Resolution

## ⚔️ Conflict Strategies

| Strategy | How | Pro | Con |
| :--- | :--- | :--- | :--- |
| **LWW** | Highest timestamp wins | Simple | Clock skew causes data loss |
| **App Merge** | Application resolves | Custom logic | Complex, requires user code |
| **CRDTs** | Math guarantees merge | No conflicts | Limited data types |

## 🔢 CRDTs (Conflict-Free Replicated Data Types)

### G-Counter (Grow-only Counter)
```python
class GCounter:
    """Each node has its own counter. Total = sum of all."""
    
    def __init__(self, node_id):
        self.node_id = node_id
        self.counts = {}  # node_id → count
    
    def increment(self):
        self.counts[self.node_id] = self.counts.get(self.node_id, 0) + 1
    
    def value(self):
        return sum(self.counts.values())
    
    def merge(self, other):
        for node_id, count in other.counts.items():
            self.counts[node_id] = max(self.counts.get(node_id, 0), count)

# Node A: {A: 5}
# Node B: {B: 3}
# Merged: {A: 5, B: 3} → value = 8
```

### PN-Counter (Positive-Negative Counter)
```python
class PNCounter:
    """Two G-Counters: one for increments, one for decrements."""
    
    def __init__(self, node_id):
        self.node_id = node_id
        self.p = {}  # Positive counts
        self.n = {}  # Negative counts
    
    def increment(self):
        self.p[self.node_id] = self.p.get(self.node_id, 0) + 1
    
    def decrement(self):
        self.n[self.node_id] = self.n.get(self.node_id, 0) + 1
    
    def value(self):
        return sum(self.p.values()) - sum(self.n.values())
    
    def merge(self, other):
        for node_id, count in other.p.items():
            self.p[node_id] = max(self.p.get(node_id, 0), count)
        for node_id, count in other.n.items():
            self.n[node_id] = max(self.n.get(node_id, 0), count)
```

### LWW-Register (Last-Writer-Wins Register)
```python
class LWWRegister:
    """Value with timestamp. Higher timestamp wins."""
    
    def __init__(self):
        self.value = None
        self.timestamp = 0
    
    def set(self, value, timestamp):
        if timestamp > self.timestamp:
            self.value = value
            self.timestamp = timestamp
    
    def merge(self, other):
        if other.timestamp > self.timestamp:
            self.value = other.value
            self.timestamp = other.timestamp
```

### OR-Set (Observed-Remove Set)
```python
class ORSet:
    """Set where adds and removes don't conflict."""
    
    def __init__(self, node_id):
        self.node_id = node_id
        self.elements = {}  # element → set of (node_id, counter) tags
        self.counter = 0
    
    def add(self, element):
        self.counter += 1
        tag = (self.node_id, self.counter)
        if element not in self.elements:
            self.elements[element] = set()
        self.elements[element].add(tag)
    
    def remove(self, element):
        # Remove all currently known tags
        if element in self.elements:
            self.elements[element] = set()
    
    def contains(self, element):
        return element in self.elements and len(self.elements[element]) > 0
    
    def merge(self, other):
        for element, tags in other.elements.items():
            if element not in self.elements:
                self.elements[element] = set()
            self.elements[element] |= tags

# Concurrent add(x) and remove(x) → x is in set (add wins)
# Because remove only removes KNOWN tags at time of remove
```

---

# Part 6: Hybrid Logical Clocks (HLC)

**Paper**: [Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases](https://cse.buffalo.edu/tech-reports/2014-04.pdf)

## 🕐 The Best of Both Worlds

```python
class HLC:
    """Combines wall clock with logical counter."""
    
    def __init__(self, node_id):
        self.node_id = node_id
        self.wall_time = 0  # Physical time (ms)
        self.logical = 0     # Logical counter
    
    def now(self):
        physical = get_wall_clock()
        
        if physical > self.wall_time:
            self.wall_time = physical
            self.logical = 0
        else:
            self.logical += 1
        
        return (self.wall_time, self.logical, self.node_id)
    
    def receive(self, msg_timestamp):
        """Called when receiving a message with timestamp."""
        msg_wall, msg_logical, _ = msg_timestamp
        physical = get_wall_clock()
        
        if physical > self.wall_time and physical > msg_wall:
            self.wall_time = physical
            self.logical = 0
        elif msg_wall > self.wall_time:
            self.wall_time = msg_wall
            self.logical = msg_logical + 1
        elif msg_wall == self.wall_time:
            self.logical = max(self.logical, msg_logical) + 1
        else:
            self.logical += 1
        
        return (self.wall_time, self.logical, self.node_id)
```

### Properties
```
1. HLC ≥ Physical Time (always)
2. e happened-before f → HLC(e) < HLC(f)
3. Bounded drift from physical time
4. Can be used for snapshot isolation
```

### Used By
```
- CockroachDB: Transaction timestamps
- YugabyteDB: Hybrid time
- MongoDB: Document versions
```

---

# Part 7: Production Patterns

## 📊 Monitoring Replication

### PostgreSQL
```sql
-- Replication lag (on primary)
SELECT 
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;

-- Replication lag (on replica)
SELECT 
    CASE 
        WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
        ELSE EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())
    END AS lag_seconds;
```

### Alert Rules
```yaml
# Prometheus alerting rules
groups:
  - name: replication
    rules:
      - alert: PostgresReplicationLagHigh
        expr: pg_replication_lag_bytes > 100000000  # 100MB
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Replication lag > 100MB"
      
      - alert: PostgresReplicationLagCritical
        expr: pg_replication_lag_seconds > 60
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Replication lag > 60 seconds"
```

## 🔄 Failover Strategies

### Automatic (Risky)
```yaml
# Patroni configuration (PostgreSQL)
failover:
  mode: automatic
  timeout: 30               # Seconds before failover
  minimum_standby_count: 1  # At least 1 standby must be available

# Risk: Split-brain if network partition
# Mitigation: Fencing (STONITH - Shoot The Other Node In The Head)
```

### Semi-Automatic (Recommended)
```yaml
failover:
  mode: manual-with-approval
  # System detects failure, pages oncall
  # Oncall confirms before failover executes
  # Ensures human verification of conditions
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Replication configured for RPO | `SELECT * FROM pg_stat_replication;` |
| 2 | Failover tested quarterly | Chaos engineering: kill primary |
| 3 | Lag monitoring alerting | Alert if lag > 100MB for 5min |
| 4 | Quorum settings match consistency needs | Review W, R, N settings |
| 5 | Clock sync verified | NTP stratum < 3, chrony configured |
| 6 | CRDTs for concurrent writes | Use for counters, sets, registers |
| 7 | No manual LWW without audit | Every LWW overwrite logged |
| 8 | Raft/Paxos understood by team | Paper review sessions |

---

## 🔗 Related Documents
*   [NoSQL Architecture](./nosql-architecture-guide.md) — Bigtable, Spanner, Cassandra.
*   [Database Scaling](./database-scaling-guide.md) — Sharding strategies.
*   [RDBMS Internals](./rdbms-internals-guide.md) — PostgreSQL replication setup.
