# Pattern: Cache Stampede (Thundering Herd)

## Problem
When a frequently accessed, expensive-to-calculate cache key expires, multiple concurrent requests simultaneously find a cache miss and all proceed to hit the database to regenerate the value, potentially causing a database crash or latency spike.

## Symptoms
- Sudden spike in database CPU and connection pool load at predictable intervals.
- p99 latency spikes that correlate with cache TTL expiration times.
- "Missing" cache keys followed by heavy database I/O.
- Cascading failures as the database becomes unresponsive.

## Detection
- **Cache Metrics**: Monitor `cache_miss` rate. Look for spikes in misses followed by database load spikes.
- **Correlations**: Compare cache `expire` events with database `SELECT` query spikes.
- **Distributed Tracing**: Identify requests that simultaneously wait for the same database query.

## Context
High-traffic distributed systems with expensive cache generation (e.g., complex SQL joins, remote API calls).

## Causes
- **Fixed TTL**: Thousands of requests hitting the same key exactly at the moment it expires.
- **Hot Keys**: Extremely popular content being cached on a single key.
- **Slow Generation**: Data takes seconds, not milliseconds, to regenerate.

## Solution
1. **Distributed Mutex (Locking)**: Only the first request to miss acquires a lock (e.g., `SET NX`) to regenerate the value; others wait or return a stale value.
2. **Probabilistic Early Expiration (PER)**: Refresh the cache *before* it expires based on a random probability function that increases as time nears the TTL.
3. **X-Fetch Algorithm**: A variation of PER that uses the time taken to generate the value to dynamically calculate the refresh window.

## Tradeoffs
- Locking adds latency and complexity (deadlock management).
- PER requires storing "time to generate" metadata and tuning constants.
- Stale value fallbacks might not be acceptable for some business use cases.

## When to use
- When data regeneration is expensive (e.g., multi-second SQL queries).
- In systems where one cache miss can trigger thousands of backend calls.

## Tags
caching, performance, reliability, thundering-herd, database-load

## Signals
- "cache miss spike database crash"
- "p99 latency spikes on cache expire"
- "prevent thundering herd redis"
- "probabilistic early expiration algorithm"
- "database connection pool exhausted on miss"

## Related Patterns
- [tail-latency-spikes](../performance/tail-latency-spikes.md)
- [hot-key-problem](hot-key-problem.md)
- [distributed-rate-limiting](../scalability/distributed-rate-limiting.md)

## Sources
- raw/internal/infrastructure-techniques/caching-strategies-comprehensive.md
