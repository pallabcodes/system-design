# Pattern: Single Point of Failure (SPOF)

## Problem
A critical component in the system architecture has no redundancy or automated failover. If this component fails, the entire system or a major subsystem becomes unavailable, resulting in a total outage.

## Symptoms
- A single node crash results in immediate system-wide downtime.
- Inability to perform rolling or zero-downtime updates.
- "Hard down" scenarios where no traffic can be served until a manual fix occurs.
- High risk during maintenance windows.

## Detection
- **Availability Audits**: Identify any service, database, or network component where `replica_count < 2`.
- **Failure Simulation (Chaos Engineering)**: Shut down a single node and observe if the system stays alive.
- **Dependency Mapping**: Check for single IP addresses or hostnames used for routing without DNS-level failover.

## Context
Databases (single primary), Load Balancers, API Gateways, Network Switches, Monolithic applications.

## Causes
- **Simplicity Over Reliability**: Prioritizing initial speed/cost over long-term availability.
- **Manual Failover**: Lack of automated monitoring or health checks to trigger recovery.
- **Hardware Dependency**: Tight coupling to a specific physical server or static IP.

## Solution
1. **Redundancy (N+1)**: Deploy at least two instances of every critical component across different zones/racks.
2. **Health Checks & Auto-Failover**: Use health checks (e.g., Consul, K8s liveness probes) to automatically route traffic away from failed nodes.
3. **Database Replication**: Set up primary-replica replication with automated failover (e.g., using RDS Multi-AZ or Patroni).
4. **Anycast/DNS Failover**: Use cloud native load balancers or DNS-level failover for top-level entry points.

## Tradeoffs
- Redundancy doubles or triples infrastructure costs.
- Distributed state/replication introduces complexity and potential data consistency issues (split-brain).
- Automated failover can sometimes "fail noisy," causing unnecessary flushes or re-elections.

## When to use
- For any production system with an SLA > 99%.
- For critical paths like identity management, payment processing, or gateway routing.

## Tags
reliability, architecture, anti-pattern, high-availability, spof

## Signals
- "single node failure downtime"
- "high availability database failover"
- "remove single point of failure"
- "automated failover architecture"
- "multi-zone availability strategy"

## Related Patterns
- [circuit-breaker](../reliability/circuit-breaker.md)
- [unbounded-queue](unbounded-queue.md)

## Sources
- raw/internal/system-design-notes/single-point-of-failure-guide.md
