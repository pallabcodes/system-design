# Pattern: Cache Invalidation

## Problem
Data in the cache becomes stale when the source of truth (database) is updated. Serving stale data can lead to business logic errors, poor user experience, or security issues.

## Symptoms
- Users seeing outdated information after making an update
- Inconsistent data across different views or services
- Bug reports about data not saving (even though the DB updated)

## Context
Any system employing caching layers (Redis, Memcached, CDNs, local memory).

## Causes
- Cache TTLs set too long
- Lack of proactive invalidation when data is mutated
- Disconnected systems updating the database without notifying the cache layer

## Solution
1. **Write-Through / Cache-Aside**: Update or delete the cache entry immediately when the application writes to the database.
2. **Event-Driven Invalidation**: Publish a message to a message broker (Kafka/RabbitMQ) or use Change Data Capture (CDC like Debezium) when the DB changes. Consumer services listen and invalidate relevant cache keys.
3. **Versioned Keys**: Embed a version number in the cache key. Increment the version when the data changes, instantly rendering the old key obsolete (it will be garbage collected later).

## Tradeoffs
- Proactive invalidation increases write latency and application complexity.
- Event-driven CDC introduces asynchronous delay, meaning the system is eventually consistent.
- Versioned keys can lead to memory bloat in the cache until old keys expire or are evicted.

## When to use
- When data consistency is highly important but read performance still requires a cache.
- Whenever you implement a caching layer for mutable data.

## Tags
caching, consistency, architecture, data-management

## Signals
- "stale data shown"
- "cache not updating"
- "how to invalidate cache"
- "inconsistent data read"
- "redis stale keys"

## Sources
- raw/internal/infrastructure-techniques/caching-strategies-comprehensive.md
