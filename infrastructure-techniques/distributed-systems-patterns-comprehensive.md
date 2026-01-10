# Distributed Systems Patterns Comprehensive Guide

## Overview

Distributed systems patterns are fundamental building blocks for designing scalable, reliable, and consistent distributed systems. This comprehensive guide covers CAP theorem, consensus algorithms (Raft, Paxos), eventual consistency, distributed transactions, and enterprise patterns for building production-ready distributed systems.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [CAP Theorem](#cap-theorem)
3. [Consensus Algorithms](#consensus-algorithms)
4. [Eventual Consistency](#eventual-consistency)
5. [Distributed Transactions](#distributed-transactions)
6. [Consistency Models](#consistency-models)
7. [Best Practices](#best-practices)
8. [Real-World Examples](#real-world-examples)

## Core Concepts

### What is a Distributed System?

A distributed system is a collection of independent computers that appear to users as a single coherent system, working together to achieve a common goal.

### Key Challenges

- **Network Partitions**: Network failures splitting the system
- **Consistency**: Ensuring all nodes see the same data
- **Availability**: System remains operational despite failures
- **Partition Tolerance**: System continues despite network partitions
- **Clock Synchronization**: Coordinating time across nodes
- **Failure Detection**: Identifying failed nodes

## CAP Theorem

### Overview

CAP theorem states that a distributed system can guarantee at most two of three properties:
- **Consistency**: All nodes see the same data simultaneously
- **Availability**: System remains operational
- **Partition Tolerance**: System continues despite network partitions

### CAP Trade-offs

#### CP Systems (Consistency + Partition Tolerance)

**Characteristics**:
- Strong consistency guarantees
- May sacrifice availability during partitions
- Use cases: Financial systems, databases

**Example**: Traditional relational databases with ACID properties

```python
# CP System Example - Strong Consistency
class ConsistentStore:
    def write(self, key, value):
        # Write to majority of nodes
        quorum = self.get_quorum()
        for node in quorum:
            node.write(key, value)
        # Wait for acknowledgment from majority
        if not self.wait_for_quorum_ack():
            raise ConsistencyError("Failed to achieve consistency")
    
    def read(self, key):
        # Read from majority to ensure consistency
        quorum = self.get_quorum()
        values = [node.read(key) for node in quorum]
        # Ensure all values are the same
        if not all(v == values[0] for v in values):
            raise ConsistencyError("Inconsistent values")
        return values[0]
```

#### AP Systems (Availability + Partition Tolerance)

**Characteristics**:
- High availability
- Eventual consistency
- Use cases: Social media, content delivery

**Example**: Cassandra, DynamoDB

```python
# AP System Example - High Availability
class AvailableStore:
    def write(self, key, value):
        # Write to any available node
        for node in self.nodes:
            try:
                node.write(key, value)
                return  # Succeed on first successful write
            except NodeUnavailable:
                continue
        # Asynchronously replicate to other nodes
        self.async_replicate(key, value)
    
    def read(self, key):
        # Read from any available node
        for node in self.nodes:
            try:
                return node.read(key)
            except NodeUnavailable:
                continue
        raise UnavailableError("No nodes available")
```

#### CA Systems (Consistency + Availability)

**Characteristics**:
- Strong consistency and availability
- Not partition-tolerant (single-node systems)
- Use cases: Single-server applications

**Note**: CA systems don't exist in truly distributed systems as partition tolerance is required.

### CAP Theorem in Practice

Most distributed systems choose **AP** (Availability + Partition Tolerance) with eventual consistency, as network partitions are inevitable.

## Consensus Algorithms

### Overview

Consensus algorithms ensure that distributed nodes agree on a single value or state, even in the presence of failures.

### Raft Algorithm

#### Core Concepts

- **Leader**: Single leader handles all client requests
- **Followers**: Replicate leader's log
- **Candidate**: Node seeking to become leader
- **Term**: Logical clock for leader election
- **Log**: Sequence of commands to be executed

#### Leader Election

```python
class RaftNode:
    def __init__(self, node_id, nodes):
        self.node_id = node_id
        self.nodes = nodes
        self.state = 'follower'
        self.current_term = 0
        self.voted_for = None
        self.log = []
        self.commit_index = 0
        self.last_applied = 0
    
    def start_election(self):
        self.state = 'candidate'
        self.current_term += 1
        self.voted_for = self.node_id
        
        votes = 1  # Vote for self
        for node in self.nodes:
            if node.request_vote(self.current_term, self.node_id):
                votes += 1
        
        if votes > len(self.nodes) / 2:
            self.become_leader()
    
    def request_vote(self, term, candidate_id):
        if term > self.current_term:
            self.current_term = term
            self.voted_for = candidate_id
            return True
        return False
    
    def become_leader(self):
        self.state = 'leader'
        # Send heartbeat to all followers
        self.send_heartbeat()
```

#### Log Replication

```python
class RaftLeader:
    def append_entry(self, command):
        entry = {
            'term': self.current_term,
            'command': command,
            'index': len(self.log)
        }
        self.log.append(entry)
        
        # Replicate to followers
        for node in self.followers:
            self.replicate_to_follower(node, entry)
    
    def replicate_to_follower(self, follower, entry):
        prev_log_index = len(self.log) - 1
        prev_log_term = self.log[prev_log_index - 1]['term'] if prev_log_index > 0 else 0
        
        success = follower.append_entries(
            term=self.current_term,
            leader_id=self.node_id,
            prev_log_index=prev_log_index,
            prev_log_term=prev_log_term,
            entries=[entry],
            leader_commit=self.commit_index
        )
        
        if success:
            self.update_follower_index(follower, len(self.log))
            self.update_commit_index()
```

### Paxos Algorithm

#### Core Concepts

- **Proposer**: Proposes values
- **Acceptor**: Accepts proposals
- **Learner**: Learns chosen values
- **Quorum**: Majority of acceptors

#### Basic Paxos

```python
class PaxosNode:
    def __init__(self, node_id, acceptors):
        self.node_id = node_id
        self.acceptors = acceptors
        self.proposal_number = 0
    
    def propose(self, value):
        proposal_num = self.generate_proposal_number()
        
        # Phase 1: Prepare
        promises = []
        for acceptor in self.acceptors:
            promise = acceptor.prepare(proposal_num)
            if promise:
                promises.append(promise)
        
        # Check if we have majority
        if len(promises) <= len(self.acceptors) / 2:
            return None
        
        # Find highest accepted value
        highest_value = None
        highest_num = 0
        for promise in promises:
            if promise.accepted_value and promise.accepted_num > highest_num:
                highest_value = promise.accepted_value
                highest_num = promise.accepted_num
        
        # Use highest value or our value
        value_to_propose = highest_value if highest_value else value
        
        # Phase 2: Accept
        accepts = 0
        for acceptor in self.acceptors:
            if acceptor.accept(proposal_num, value_to_propose):
                accepts += 1
        
        if accepts > len(self.acceptors) / 2:
            return value_to_propose
        
        return None
```

### Multi-Paxos

Multi-Paxos optimizes Paxos for multiple consensus instances by electing a leader.

```python
class MultiPaxos:
    def __init__(self, nodes):
        self.nodes = nodes
        self.leader = None
        self.log = []
    
    def elect_leader(self):
        # Use Paxos to elect a stable leader
        leader_id = self.run_paxos("leader_election")
        self.leader = self.nodes[leader_id]
    
    def append(self, value):
        if self.is_leader():
            index = len(self.log)
            # Replicate using leader optimization
            for node in self.followers:
                node.accept(index, self.current_term, value)
            self.log.append(value)
        else:
            # Forward to leader
            self.leader.append(value)
```

## Eventual Consistency

### Overview

Eventual consistency guarantees that if no new updates are made, all replicas will eventually converge to the same value.

### Conflict Resolution Strategies

#### Last-Write-Wins (LWW)

```python
class LastWriteWins:
    def merge(self, value1, value2):
        # Compare timestamps
        if value1.timestamp > value2.timestamp:
            return value1
        return value2
```

#### Vector Clocks

```python
class VectorClock:
    def __init__(self, node_id, nodes):
        self.node_id = node_id
        self.clock = {node: 0 for node in nodes}
    
    def tick(self):
        self.clock[self.node_id] += 1
    
    def update(self, other_clock):
        for node in self.clock:
            self.clock[node] = max(
                self.clock[node],
                other_clock.get(node, 0)
            )
        self.tick()
    
    def compare(self, other):
        # Returns: -1 (happens before), 0 (concurrent), 1 (happens after)
        less = False
        greater = False
        
        all_nodes = set(self.clock.keys()) | set(other.clock.keys())
        for node in all_nodes:
            v1 = self.clock.get(node, 0)
            v2 = other.clock.get(node, 0)
            
            if v1 < v2:
                less = True
            elif v1 > v2:
                greater = True
        
        if less and not greater:
            return -1
        elif greater and not less:
            return 1
        else:
            return 0  # Concurrent
```

#### CRDTs (Conflict-Free Replicated Data Types)

```python
# G-Counter (Grow-only Counter)
class GCounter:
    def __init__(self, node_id, nodes):
        self.node_id = node_id
        self.counters = {node: 0 for node in nodes}
    
    def increment(self):
        self.counters[self.node_id] += 1
    
    def value(self):
        return sum(self.counters.values())
    
    def merge(self, other):
        for node in self.counters:
            self.counters[node] = max(
                self.counters[node],
                other.counters.get(node, 0)
            )

# LWW-Register (Last-Write-Wins Register)
class LWWRegister:
    def __init__(self, node_id):
        self.node_id = node_id
        self.value = None
        self.timestamp = 0
    
    def write(self, value):
        self.value = value
        self.timestamp = time.time()
    
    def read(self):
        return self.value
    
    def merge(self, other):
        if other.timestamp > self.timestamp:
            self.value = other.value
            self.timestamp = other.timestamp
```

### Anti-Entropy

```python
class AntiEntropy:
    def __init__(self, store):
        self.store = store
        self.merkle_tree = MerkleTree()
    
    def sync(self, other_node):
        # Compare Merkle trees
        if self.merkle_tree.root != other_node.merkle_tree.root:
            # Find differences
            differences = self.find_differences(other_node)
            # Exchange missing data
            self.exchange_data(other_node, differences)
    
    def find_differences(self, other):
        # Use Merkle tree to efficiently find differences
        return self.merkle_tree.compare(other.merkle_tree)
```

## Distributed Transactions

### Two-Phase Commit (2PC)

```python
class TwoPhaseCommit:
    def __init__(self, coordinator, participants):
        self.coordinator = coordinator
        self.participants = participants
    
    def execute(self, transaction):
        # Phase 1: Prepare
        votes = []
        for participant in self.participants:
            vote = participant.prepare(transaction)
            votes.append(vote)
        
        # Phase 2: Commit or Abort
        if all(vote == 'YES' for vote in votes):
            for participant in self.participants:
                participant.commit(transaction)
        else:
            for participant in self.participants:
                participant.abort(transaction)
```

### Saga Pattern

#### Choreography-Based Saga

```python
class SagaChoreography:
    def execute_order(self, order):
        # Step 1: Reserve inventory
        inventory_service.reserve(order.items)
        
        # Step 2: Process payment
        payment_service.charge(order.customer_id, order.total)
        
        # Step 3: Ship order
        shipping_service.ship(order)
    
    def compensate_order(self, order):
        # Compensate in reverse order
        shipping_service.cancel_shipment(order)
        payment_service.refund(order.customer_id, order.total)
        inventory_service.release(order.items)
```

#### Orchestration-Based Saga

```python
class SagaOrchestrator:
    def execute_order(self, order):
        steps = [
            ('reserve_inventory', inventory_service.reserve, inventory_service.release),
            ('charge_payment', payment_service.charge, payment_service.refund),
            ('ship_order', shipping_service.ship, shipping_service.cancel_shipment)
        ]
        
        completed_steps = []
        try:
            for step_name, execute, compensate in steps:
                execute(order)
                completed_steps.append((step_name, compensate))
        except Exception as e:
            # Compensate completed steps
            for step_name, compensate in reversed(completed_steps):
                compensate(order)
            raise
```

### Outbox Pattern

```python
class OutboxPattern:
    def process_order(self, order):
        # Start transaction
        with db.transaction():
            # Write to database
            db.save_order(order)
            
            # Write event to outbox (same transaction)
            db.save_outbox_event({
                'event_type': 'order_created',
                'payload': order.to_dict()
            })
        
        # Publish events from outbox (separate process)
        self.publish_outbox_events()
    
    def publish_outbox_events(self):
        events = db.get_unpublished_events()
        for event in events:
            try:
                message_queue.publish(event.event_type, event.payload)
                db.mark_event_published(event.id)
            except Exception as e:
                logger.error(f"Failed to publish event: {e}")
```

## Consistency Models

### Strong Consistency

All reads see the most recent write.

```python
class StrongConsistentStore:
    def write(self, key, value):
        # Write to all replicas synchronously
        for replica in self.replicas:
            replica.write(key, value)
    
    def read(self, key):
        # Read from primary (or quorum)
        return self.primary.read(key)
```

### Eventual Consistency

System will become consistent over time.

```python
class EventuallyConsistentStore:
    def write(self, key, value):
        # Write to local replica
        self.local_replica.write(key, value)
        # Replicate asynchronously
        self.async_replicate(key, value)
    
    def read(self, key):
        # Read from local replica (may be stale)
        return self.local_replica.read(key)
```

### Causal Consistency

Preserves causal relationships between operations.

```python
class CausallyConsistentStore:
    def __init__(self):
        self.vector_clock = VectorClock()
        self.data = {}
    
    def write(self, key, value):
        self.vector_clock.tick()
        self.data[key] = {
            'value': value,
            'clock': self.vector_clock.copy()
        }
    
    def read(self, key):
        entry = self.data.get(key)
        if entry:
            # Check if we can read this (causal consistency)
            if self.vector_clock.happens_after(entry['clock']):
                return entry['value']
        return None
```

### Session Consistency

Guarantees read-your-writes and monotonic reads within a session.

```python
class SessionConsistentStore:
    def __init__(self, session_id):
        self.session_id = session_id
        self.last_write_timestamp = 0
    
    def write(self, key, value):
        timestamp = time.time()
        self.store.write(key, value, timestamp)
        self.last_write_timestamp = timestamp
    
    def read(self, key):
        # Read from replica with timestamp >= last_write_timestamp
        return self.store.read(key, min_timestamp=self.last_write_timestamp)
```

## Best Practices

### 1. Choose Appropriate Consistency Model

- **Strong Consistency**: Financial transactions, critical data
- **Eventual Consistency**: Social feeds, content delivery
- **Causal Consistency**: Collaborative editing, chat systems

### 2. Implement Conflict Resolution

- Use vector clocks for ordering
- Implement CRDTs for conflict-free data types
- Apply domain-specific conflict resolution

### 3. Handle Network Partitions

- Design for partition tolerance
- Implement quorum-based operations
- Use eventual consistency when possible

### 4. Monitor Consistency

- Track replication lag
- Monitor conflict rates
- Alert on consistency violations

## Real-World Examples

### DynamoDB (AP System)

- Eventual consistency by default
- Strong consistency option available
- Conflict resolution with vector clocks

### Cassandra (AP System)

- Tunable consistency levels
- Eventual consistency with quorum options
- Last-write-wins conflict resolution

### Spanner (CP System)

- Strong consistency with TrueTime
- Global transactions
- External consistency guarantees

This comprehensive guide provides enterprise-grade distributed systems patterns for building production-ready distributed systems with appropriate consistency guarantees and fault tolerance.

