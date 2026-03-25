# Pattern: N+1 Query Problem

## Problem
An application fetches a list of $N$ items and then executes $N$ additional database queries to retrieve related data for each item. This inefficient data access pattern severely degrades performance and database stability.

## Symptoms
- Database query logs show thousands of similar queries (e.g., `SELECT * FROM comments WHERE post_id = ?`) for a single API call.
- Rapid spike in database connection pool usage.
- High CPU usage on the database during read-heavy operations.
- Long API response times even when the initial query is fast.

## Detection
- **Query Logs**: Enable slow query logs or use APM tools to count query frequency per request.
- **Database Metrics**: Spikes in `SELECT` query count per second that correlate with API traffic.
- **Trace Analysis**: Trace spans showing hundreds of sequential database calls.

## Context
Object-Relational Mapping (ORM) tools, REST/GraphQL APIs fetching nested relationships.

## Causes
- **Lazy Loading**: ORMs (e.g., Hibernate, Django ORM) that load related entities only when accessed in a loop.
- **Manual Loops**: Developers manually iterating over result sets to fetch related info.
- **Nested Resolvers**: GraphQL fields that don't use batching or caching for their children.

## Solution
1. **Eager Loading**: Instruct the ORM to fetch related data using SQL `JOIN`s or `IN` clauses (e.g., `.includes()` or `.select_related()`).
2. **Batching (DataLoader)**: Collect all IDs from the parent list and fetch all children in a single query (`WHERE id IN (?)`).
3. **Materialized Views/Denormalization**: Store frequently joined data together in a single table for fast reads.

## Tradeoffs
- Eager loading can lead to "Cartesian Product" issues if joining multiple many-to-many tables.
- Batching increases application memory usage while the results are being processed.
- Denormalization increases storage cost and complexity of data updates.

## When to use
- For any API endpoint returning lists of data with nested objects.
- When DB query count per request is > 10.

## Tags
performance, database, orm, query-optimization, n-plus-one

## Signals
- "too many database queries"
- "orm lazy loading performance"
- "sql query count high"
- "nested graphql resolver slow"
- "dataloader batching strategy"

## Related Patterns
- [cache-stampede](../caching/cache-stampede.md)
- [distributed-rate-limiting](../scalability/distributed-rate-limiting.md)

## Sources
- General Knowledge
