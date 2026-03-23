# Pattern: Circuit Breaker

## Problem
Preventing a failure or latency spike in one service from cascading to other services by stopping requests to a failing dependency once a failure threshold is reached. Continuing to send requests to a dead service wastes resources and worsens the outage.

## Symptoms
- Increasing latency in the caller service
- Thread pool exhaustion in upstream services
- Cascading failures across the system
- High error rates from a specific dependency propagating up the stack
- System hangs or becomes unresponsive instead of failing fast

## Context
Microservices architectures, Distributed systems with many synchronous network calls, API Gateways.

## Causes
- Slow or unresponsive downstream services.
- Network partitions or packet loss.
- Database timeouts or slow queries in downstream services.
- Resource constraints on the dependency.

## Solution
1. **States**:
   - **Closed**: Normal operation, requests flow through.
   - **Open**: Error threshold exceeded, fail fast immediately (return fallback or error) without making the network call.
   - **Half-Open**: After a timeout, allow limited "test" requests to see if the service has recovered. If successful, transition to Closed. If failed, return to Open.
2. **Failure Threshold**: Trip the circuit if > N% of requests fail over a rolling time window.
3. **Fallback**: Provide a default response (e.g., cached data, empty list, degraded UI) when the circuit is open.

## Tradeoffs
- Requires careful tuning of thresholds, sliding windows, and wait durations.
- Adds complexity to the client-side code and requires robust monitoring.
- Fallbacks might return stale or incomplete data, affecting user experience.

## When to use
- Every synchronous network call in a microservices environment.
- Protecting resources (threads, sockets) from hanging on slow dependencies.
- When graceful degradation is preferred over total failure.

## Tags
reliability, fault-tolerance, microservices, resiliency, fail-fast

## Signals
- "cascading failure"
- "thread pool exhaustion"
- "downstream service timeout"
- "prevent system hang"
- "fail fast on dependency error"

## Sources
- raw/internal/distributive-backend/resiliency-patterns-guide.md
