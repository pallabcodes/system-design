# Pattern: Distributed Rate Limiting (Token Bucket)

## Problem
Protecting a distributed system from being overwhelmed by too many requests while ensuring fair usage across multiple nodes. Local rate limiting on a single node is insufficient when traffic is spread across a cluster, as a client can still bypass limits by hitting multiple nodes.

## Symptoms
- Service instability and slow responses under high load
- Resource exhaustion (CPU, Memory, File Descriptors)
- One "noisy neighbor" or malicious actor starving other users
- Backend services failing due to sudden traffic bursts
- HTTP 503 or 504 errors spreading across the cluster

## Context
API Gateways, Microservices, Public-facing APIs, Web Scraper mitigation.

## Causes
- Lack of global state for request counts across instances.
- Sudden spikes in traffic (marketing events, DDoS, retry storms).
- Unpredictable client behavior and unbounded request rates.

## Solution
1. **Centralized Store (Redis)**: Use an atomic counter or Token Bucket algorithm implemented in Lua scripts within Redis to maintain a single global state.
2. **Token Bucket Algorithm**: Tokens are added to a "bucket" at a fixed rate. Requests consume tokens. If the bucket is empty, the request is rejected (HTTP 429).
3. **Sliding Window Counter**: Use multiple fixed windows to approximate a sliding window for smoother limiting and avoiding burst edges.

## Tradeoffs
- Centralized stores (Redis) become a single point of failure or bottleneck; if Redis goes down, APIs might fail open or closed.
- Network latency for every rate-limit check adds overhead per request.
- Eventual consistency (if using gossip/local sync) vs strict accuracy (Redis).

## When to use
- API protection and fair-use enforcement.
- Preventing cascading failures from downstream services due to excessive load.
- Monetization tiers (e.g., Free tier vs Premium tier API limits).

## Tags
scalability, security, reliability, api-design, traffic-shaping

## Signals
- "too many requests"
- "429 too many requests"
- "api abuse mitigation"
- "noisy neighbor problem"
- "protect backend from traffic spike"

## Sources
- raw/internal/infrastructure-techniques/rate-limiting-comprehensive.md
