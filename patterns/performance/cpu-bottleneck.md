# Pattern: CPU Starvation / Context Switching

## Problem
An application is maximizing its CPU allocation, causing slow processing times, blocked threads, and an inability to handle concurrent requests. Excessive thread context switching can result in high CPU usage with very little actual progress (throughput drop).

## Symptoms
- CPU utilization near 100% on some or all cores.
- High "System" CPU vs "User" CPU (indicating kernel overhead).
- Application throughput drops drastically while latency spikes.
- High "Wait" or "Blocked" threads in application dumps.

## Detection
- **Metrics**: Monitor `process_cpu_seconds_total` (Prometheus) or `top` for CPU load.
- **System Stats**: High `cs` (context switches) in `vmstat`.
- **Flame Graphs**: High time spent in kernel functions or locking primitives (`pthread_mutex_lock`).

## Context
Compute-heavy workloads, improperly optimized algorithms, massive concurrency on fixed-size thread pools.

## Causes
- **Inefficient Algorithms**: O(N^2) or worse logic on large input sizes.
- **Thread Pool Over-sizing**: Too many threads competing for limited CPU cores, causing constant context switches.
- **Hot Locks**: Multiple threads competing for a single lock, forcing threads into sleep/wake cycles.
- **Serialization Overhead**: Repeated JSON/Protobuf parsing on every request.

## Solution
1. **Vertical/Horizontal Scaling**: Add more cores per instance or more instances.
2. **Optimize Critical Paths**: Identify and fix inefficient code paths using Flame Graphs (e.g., `pprof`, `JFR`).
3. **Control Concurrency**: Use bounded thread pools and backpressure to prevent the system from accepting more work than it can process.
4. **Non-Blocking I/O**: Shift to event-driven architectures (e.g., Netty, Node.js, Go channels) to minimize thread context switching.

## Tradeoffs
- Vertical scaling is limited and expensive.
- Horizontal scaling introduces distributed system complexity (e.g., network latency).
- Non-blocking I/O often requires a complex programming model change.

## When to use
- When CPU metrics are consistently saturated and latency is high.
- Before blindly scaling, if the issue is algorithmic inefficiency or lock contention.

## Tags
performance, compute, optimization, scalability, cpu-bottleneck

## Signals
- "cpu utilization near 100"
- "high context switching symptoms"
- "flame graph high kernel time"
- "system load average high but cpu idle"
- "mutex contention bottleneck"

## Related Patterns
- [tail-latency-spikes](tail-latency-spikes.md)
- [unbounded-queue](../anti-patterns/unbounded-queue.md)

## Sources
- General Knowledge
