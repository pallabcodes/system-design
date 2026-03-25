# Rate Limiting Comprehensive Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Token Bucket, Leaky Bucket, Sliding Window, and Distributed Rate Limiting.

> [!WARNING]
> **The Distributed Challenge**: Rate limiting on a single server is trivial. Rate limiting across a cluster requires **Shared State (Redis)** or **Token Allocation** per node. This guide covers both.

## Overview

Rate limiting is a critical technique for controlling the rate of requests to protect services from abuse, ensure fair resource usage, and maintain system stability. This comprehensive guide covers rate limiting algorithms, implementation patterns, distributed rate limiting, and enterprise strategies for building production-ready rate limiting systems.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Rate Limiting Algorithms](#rate-limiting-algorithms)
3. [Implementation Patterns](#implementation-patterns)
4. [Distributed Rate Limiting](#distributed-rate-limiting)
5. [API Gateway Integration](#api-gateway-integration)
6. [Best Practices](#best-practices)
7. [Performance Optimization](#performance-optimization)
8. [Monitoring and Observability](#monitoring-and-observability)

## Core Concepts

### What is Rate Limiting?

Rate limiting is the practice of controlling the number of requests a client can make to a service within a specified time period.

### Benefits

- **Protection**: Prevent abuse and DDoS attacks
- **Fair Usage**: Ensure fair resource distribution
- **Stability**: Maintain system stability under load
- **Cost Control**: Manage API costs and resource usage
- **Quality of Service**: Prioritize important clients

### Rate Limiting Dimensions

- **Rate**: Requests per time period (e.g., 100 requests/minute)
- **Burst**: Maximum sudden spike allowed
- **Quota**: Total requests per period (e.g., 10,000 requests/day)
- **Concurrency**: Maximum simultaneous requests

## Rate Limiting Algorithms

### 1. Token Bucket

**Algorithm**: Tokens are added to a bucket at a fixed rate. Requests consume tokens.

```python
import time
from threading import Lock

class TokenBucket:
    def __init__(self, capacity, refill_rate):
        self.capacity = capacity
        self.refill_rate = refill_rate  # tokens per second
        self.tokens = capacity
        self.last_refill = time.time()
        self.lock = Lock()
    
    def consume(self, tokens=1):
        with self.lock:
            self._refill()
            if self.tokens >= tokens:
                self.tokens -= tokens
                return True
            return False
    
    def _refill(self):
        now = time.time()
        elapsed = now - self.last_refill
        tokens_to_add = elapsed * self.refill_rate
        self.tokens = min(self.capacity, self.tokens + tokens_to_add)
        self.last_refill = now
    
    def get_available_tokens(self):
        with self.lock:
            self._refill()
            return self.tokens
```

**Use Case**: Burst traffic handling, smooth rate limiting

### 2. Leaky Bucket

**Algorithm**: Requests are added to a bucket that leaks at a constant rate.

```python
class LeakyBucket:
    def __init__(self, capacity, leak_rate):
        self.capacity = capacity
        self.leak_rate = leak_rate  # requests per second
        self.queue = []
        self.last_leak = time.time()
        self.lock = Lock()
    
    def add_request(self, request):
        with self.lock:
            self._leak()
            if len(self.queue) < self.capacity:
                self.queue.append(request)
                return True
            return False
    
    def _leak(self):
        now = time.time()
        elapsed = now - self.last_leak
        requests_to_process = int(elapsed * self.leak_rate)
        
        for _ in range(min(requests_to_process, len(self.queue))):
            if self.queue:
                self.queue.pop(0)
        
        self.last_leak = now
```

**Use Case**: Smooth output rate, traffic shaping

### 3. Fixed Window

**Algorithm**: Count requests in fixed time windows.

```python
from collections import defaultdict
from datetime import datetime, timedelta

class FixedWindow:
    def __init__(self, max_requests, window_seconds):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.windows = defaultdict(int)
        self.lock = Lock()
    
    def is_allowed(self, key):
        with self.lock:
            now = datetime.now()
            window_start = now.replace(
                second=0,
                microsecond=0
            ) - timedelta(seconds=now.second % self.window_seconds)
            window_key = f"{key}:{window_start.timestamp()}"
            
            if self.windows[window_key] < self.max_requests:
                self.windows[window_key] += 1
                return True
            return False
    
    def cleanup_old_windows(self):
        with self.lock:
            cutoff = datetime.now() - timedelta(seconds=self.window_seconds * 2)
            cutoff_timestamp = cutoff.timestamp()
            self.windows = {
                k: v for k, v in self.windows.items()
                if float(k.split(':')[1]) > cutoff_timestamp
            }
```

**Use Case**: Simple rate limiting, low memory usage

**Problem**: Burst at window boundaries

### 4. Sliding Window Log

**Algorithm**: Maintain a log of all requests, count requests in sliding window.

```python
from collections import deque

class SlidingWindowLog:
    def __init__(self, max_requests, window_seconds):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.logs = defaultdict(deque)
        self.lock = Lock()
    
    def is_allowed(self, key):
        with self.lock:
            now = time.time()
            window_start = now - self.window_seconds
            
            # Remove old entries
            log = self.logs[key]
            while log and log[0] < window_start:
                log.popleft()
            
            # Check limit
            if len(log) < self.max_requests:
                log.append(now)
                return True
            return False
```

**Use Case**: Precise rate limiting, accurate counting

**Problem**: High memory usage for high-traffic keys

### 5. Sliding Window Counter

**Algorithm**: Use multiple fixed windows to approximate sliding window.

```python
class SlidingWindowCounter:
    def __init__(self, max_requests, window_seconds, num_windows=10):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.num_windows = num_windows
        self.window_size = window_seconds / num_windows
        self.windows = defaultdict(lambda: defaultdict(int))
        self.lock = Lock()
    
    def is_allowed(self, key):
        with self.lock:
            now = time.time()
            current_window = int(now / self.window_size)
            
            # Count requests in sliding window
            count = 0
            for i in range(self.num_windows):
                window_id = current_window - i
                count += self.windows[key][window_id]
            
            if count < self.max_requests:
                self.windows[key][current_window] += 1
                return True
            return False
    
    def cleanup_old_windows(self, key):
        with self.lock:
            now = time.time()
            cutoff_window = int((now - self.window_seconds) / self.window_size)
            self.windows[key] = {
                k: v for k, v in self.windows[key].items()
                if k > cutoff_window
            }
```

**Use Case**: Balance between accuracy and memory

### 6. Adaptive Rate Limiting

**Algorithm**: Adjust rate limits based on system load.

```python
class AdaptiveRateLimiter:
    def __init__(self, base_rate, min_rate, max_rate):
        self.base_rate = base_rate
        self.min_rate = min_rate
        self.max_rate = max_rate
        self.current_rate = base_rate
        self.bucket = TokenBucket(max_rate, base_rate)
        self.system_load = 0.0
    
    def is_allowed(self):
        # Adjust rate based on system load
        if self.system_load > 0.8:
            self.current_rate = self.min_rate
        elif self.system_load < 0.3:
            self.current_rate = self.max_rate
        else:
            # Linear interpolation
            self.current_rate = self.min_rate + (
                (self.max_rate - self.min_rate) * (1 - self.system_load)
            )
        
        # Update bucket refill rate
        self.bucket.refill_rate = self.current_rate
        
        return self.bucket.consume()
    
    def update_system_load(self, load):
        self.system_load = load
```

## Implementation Patterns

### Redis-Based Rate Limiting

#### Token Bucket with Redis

```python
import redis
import time

class RedisTokenBucket:
    def __init__(self, redis_client, key_prefix='rate_limit'):
        self.redis = redis_client
        self.key_prefix = key_prefix
    
    def is_allowed(self, key, capacity, refill_rate, tokens=1):
        redis_key = f"{self.key_prefix}:{key}"
        now = time.time()
        
        # Lua script for atomic operation
        lua_script = """
        local key = KEYS[1]
        local capacity = tonumber(ARGV[1])
        local refill_rate = tonumber(ARGV[2])
        local tokens_requested = tonumber(ARGV[3])
        local now = tonumber(ARGV[4])
        
        local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
        local current_tokens = tonumber(bucket[1]) or capacity
        local last_refill = tonumber(bucket[2]) or now
        
        -- Refill tokens
        local elapsed = now - last_refill
        local tokens_to_add = elapsed * refill_rate
        current_tokens = math.min(capacity, current_tokens + tokens_to_add)
        
        -- Check if enough tokens
        if current_tokens >= tokens_requested then
            current_tokens = current_tokens - tokens_requested
            redis.call('HMSET', key, 'tokens', current_tokens, 'last_refill', now)
            redis.call('EXPIRE', key, math.ceil(capacity / refill_rate))
            return {1, current_tokens}
        else
            redis.call('HMSET', key, 'tokens', current_tokens, 'last_refill', now)
            redis.call('EXPIRE', key, math.ceil(capacity / refill_rate))
            return {0, current_tokens}
        end
        """
        
        result = self.redis.eval(
            lua_script,
            1,
            redis_key,
            capacity,
            refill_rate,
            tokens,
            now
        )
        
        return result[0] == 1, result[1]
```

#### Sliding Window with Redis

```python
class RedisSlidingWindow:
    def __init__(self, redis_client, key_prefix='rate_limit'):
        self.redis = redis_client
        self.key_prefix = key_prefix
    
    def is_allowed(self, key, max_requests, window_seconds):
        redis_key = f"{self.key_prefix}:{key}"
        now = time.time()
        window_start = now - window_seconds
        
        # Use sorted set to store request timestamps
        pipe = self.redis.pipeline()
        pipe.zremrangebyscore(redis_key, 0, window_start)
        pipe.zcard(redis_key)
        pipe.zadd(redis_key, {str(now): now})
        pipe.expire(redis_key, window_seconds)
        results = pipe.execute()
        
        current_count = results[1]
        return current_count < max_requests
```

### In-Memory Rate Limiting

```python
from functools import lru_cache
from threading import Lock

class InMemoryRateLimiter:
    def __init__(self):
        self.limiters = {}
        self.lock = Lock()
    
    def get_limiter(self, key, max_requests, window_seconds):
        with self.lock:
            if key not in self.limiters:
                self.limiters[key] = SlidingWindowLog(max_requests, window_seconds)
            return self.limiters[key]
    
    def is_allowed(self, key, max_requests, window_seconds):
        limiter = self.get_limiter(key, max_requests, window_seconds)
        return limiter.is_allowed(key)
```

## Distributed Rate Limiting

### Centralized Rate Limiting

```python
class CentralizedRateLimiter:
    def __init__(self, redis_client):
        self.redis = redis_client
        self.token_bucket = RedisTokenBucket(redis_client)
    
    def is_allowed(self, client_id, rate_limit_config):
        return self.token_bucket.is_allowed(
            client_id,
            rate_limit_config['capacity'],
            rate_limit_config['refill_rate']
        )
```

### Distributed Rate Limiting (Token Allocation)

```python
class DistributedRateLimiter:
    def __init__(self, node_id, total_nodes, redis_client):
        self.node_id = node_id
        self.total_nodes = total_nodes
        self.redis = redis_client
        self.local_bucket = TokenBucket(100, 10)  # Local allocation
    
    def is_allowed(self, client_id, global_rate):
        # Each node gets a portion of the global rate
        local_rate = global_rate / self.total_nodes
        local_capacity = global_rate / self.total_nodes
        
        # Check local bucket first
        if self.local_bucket.consume():
            return True
        
        # Try to borrow from shared pool
        shared_key = f"shared_pool:{client_id}"
        return self.redis.decr(shared_key) >= 0
```

### Consistent Hashing for Rate Limiting

```python
import hashlib

class ConsistentHashRateLimiter:
    def __init__(self, nodes, redis_clients):
        self.nodes = nodes
        self.redis_clients = redis_clients
        self.ring = {}
        
        # Build consistent hash ring
        for node in nodes:
            for i in range(100):  # Virtual nodes
                hash_key = self._hash(f"{node}:{i}")
                self.ring[hash_key] = node
    
    def _hash(self, key):
        return int(hashlib.md5(key.encode()).hexdigest(), 16)
    
    def get_node(self, client_id):
        hash_key = self._hash(client_id)
        sorted_keys = sorted(self.ring.keys())
        
        for key in sorted_keys:
            if hash_key <= key:
                return self.ring[key]
        return self.ring[sorted_keys[0]]
    
    def is_allowed(self, client_id, max_requests, window_seconds):
        node = self.get_node(client_id)
        redis_client = self.redis_clients[node]
        limiter = RedisSlidingWindow(redis_client)
        return limiter.is_allowed(client_id, max_requests, window_seconds)
```

## API Gateway Integration

### NGINX Rate Limiting

```nginx
# limit_req_zone
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

server {
    location /api {
        limit_req zone=api_limit burst=20 nodelay;
        proxy_pass http://backend;
    }
}

# limit_conn_zone
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

server {
    location /api {
        limit_conn conn_limit 10;
        proxy_pass http://backend;
    }
}
```

### Kong Rate Limiting

```bash
# Enable rate limiting plugin
curl -X POST http://localhost:8001/services/user-service/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=100" \
  --data "config.hour=1000" \
  --data "config.policy=local"
```

### AWS API Gateway Rate Limiting

```python
# Usage plan and API key
import boto3

apigateway = boto3.client('apigateway')

# Create usage plan
usage_plan = apigateway.create_usage_plan(
    name='standard-plan',
    throttle={
        'rateLimit': 100,
        'burstLimit': 200
    },
    quota={
        'limit': 10000,
        'period': 'DAY'
    }
)

# Associate with API key
apigateway.create_usage_plan_key(
    usagePlanId=usage_plan['id'],
    keyId=api_key_id,
    keyType='API_KEY'
)
```

## Best Practices

### 1. Multiple Rate Limit Tiers

```python
class TieredRateLimiter:
    def __init__(self):
        self.tiers = {
            'free': {'requests_per_minute': 10, 'requests_per_hour': 100},
            'basic': {'requests_per_minute': 100, 'requests_per_hour': 1000},
            'premium': {'requests_per_minute': 1000, 'requests_per_hour': 10000}
        }
    
    def is_allowed(self, client_id, tier):
        config = self.tiers.get(tier, self.tiers['free'])
        return self.check_limits(client_id, config)
```

### 2. Rate Limit Headers

```python
from flask import Flask, Response

app = Flask(__name__)

@app.after_request
def add_rate_limit_headers(response):
    rate_limit_info = get_rate_limit_info(request.remote_addr)
    response.headers['X-RateLimit-Limit'] = rate_limit_info['limit']
    response.headers['X-RateLimit-Remaining'] = rate_limit_info['remaining']
    response.headers['X-RateLimit-Reset'] = rate_limit_info['reset_time']
    return response
```

### 3. Graceful Degradation

```python
def handle_request():
    if not rate_limiter.is_allowed(client_id):
        # Return 429 with retry-after header
        return Response(
            'Rate limit exceeded',
            status=429,
            headers={'Retry-After': '60'}
        )
    return process_request()
```

## Performance Optimization

### 1. Caching Rate Limit State

```python
class CachedRateLimiter:
    def __init__(self, redis_client, cache_ttl=60):
        self.redis = redis_client
        self.cache = {}
        self.cache_ttl = cache_ttl
    
    def is_allowed(self, key, max_requests, window_seconds):
        # Check local cache first
        if key in self.cache:
            cached_time, cached_allowed = self.cache[key]
            if time.time() - cached_time < self.cache_ttl:
                return cached_allowed
        
        # Check Redis
        allowed = self.redis_check(key, max_requests, window_seconds)
        
        # Update cache
        self.cache[key] = (time.time(), allowed)
        return allowed
```

### 2. Batch Operations

```python
def check_multiple_limits(client_ids, rate_limit_config):
    pipe = redis_client.pipeline()
    for client_id in client_ids:
        pipe.eval(lua_script, 1, f"rate_limit:{client_id}", ...)
    results = pipe.execute()
    return dict(zip(client_ids, results))
```

## Monitoring and Observability

### Metrics

- **Rate Limit Hits**: Number of allowed requests
- **Rate Limit Violations**: Number of rejected requests
- **Rate Limit by Tier**: Distribution across tiers
- **Top Violators**: Clients exceeding limits most

### Alerting

```python
def check_rate_limit_health():
    violation_rate = get_violation_rate()
    if violation_rate > 0.1:  # More than 10% violations
        alert("High rate limit violation rate")
    
    top_violator = get_top_violator()
    if top_violator['violations'] > 1000:
        alert(f"Potential abuse detected: {top_violator['client_id']}")
```

This comprehensive guide provides enterprise-grade rate limiting patterns and implementations for building production-ready rate limiting systems with various algorithms and distributed architectures.

