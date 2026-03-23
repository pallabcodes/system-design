# Pattern: Tail Latency (p99) Spikes

## Problem
A service exhibits high latency at the 99th percentile (p99) while median latency (p50) remains stable. This "long tail" causes inconsistent user experiences and triggers timeouts in upstream services, often without clear resource saturation on the affected node.

## Symptoms
- Stable p50/p95 latency but unpredictable p99/p999 spikes.
- "Micro-stutters" in user interface or API responses.
- Upstream services intermittently reporting `504 Gateway Timeout`.
- No obvious CPU or memory saturation during the spikes.

## Detection
- **Metrics**: Compare `p50` vs `p99` latency on Prometheus/Grafana dashboards. Look for "sawtooth" patterns in latency.
- **Tracing**: Use Distributed Tracing (Jaeger/Zipkin) to find specific requests with large gaps between spans.
- **Logs**: Search for request logs where `duration > threshold`.

## Context
High-throughput microservices, real-time systems, and fan-out architectures where one slow dependency delays the entire aggregate response.

## Causes
- **Garbage Collection (GC)**: "Stop-the-world" pauses in managed languages (Java, Go, Node.js).
- **Resource Contention**: Occasional lock contention or disk I/O wait.
- **Network Jitter**: Packet loss requiring TCP retransmission.
- **Cold Starts**: JIT compilation or connection pool initialization.
- **Noisy Neighbors**: Other processes on the same host consuming shared resources (L3 cache, I/O bandwidth).

## Solution
1. **Hedged Requests**: Send the same request to multiple replicas if the first one doesn't respond within the p95 time.
2. **Tuning GC**: Adjust heap sizes or switch to low-latency GC algorithms (e.g., ZGC in Java).
3. **Connection Pooling**: Keep connections warm to avoid the handshake latency on the critical path.
4. **Asynchronous Processing**: Move non-critical work (logging, analytics) off the request thread.

## Tradeoffs
- Hedged requests increase total system load and cost.
- Low-latency GC may reduce overall throughput in exchange for consistency.
- Async processing can lead to data loss if the service crashes before flushing buffers.

## When to use
- When the "request-success" rate is high but the "user-satisfaction" rate is low due to perceived slowness.
- In fan-out systems where the slowest response dictates total latency.

## Tags
performance, latency, observability, reliability, tail-latency

## Signals
- "p99 latency high p50 normal"
- "microservice tail latency spikes"
- "intermittent slow api response"
- "distributed tracing slow spans"
- "stop the world gc pauses"
- "hedged requests strategy"

## Related Patterns
- [circuit-breaker](../reliability/circuit-breaker.md)
- [cpu-bottleneck](cpu-bottleneck.md)
- [cache-stampede](../caching/cache-stampede.md)

## Sources
- General Knowledge
