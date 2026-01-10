# Caching Strategies Comprehensive Guide

## Overview

Caching is a critical technique for improving application performance by storing frequently accessed data in fast-access storage. This comprehensive guide covers caching patterns, Redis, Memcached, CDN, and enterprise strategies for building high-performance caching systems.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Caching Patterns](#caching-patterns)
3. [Redis Deep Dive](#redis-deep-dive)
4. [Memcached Deep Dive](#memcached-deep-dive)
5. [CDN Caching](#cdn-caching)
6. [Cache Invalidation](#cache-invalidation)
7. [Performance Optimization](#performance-optimization)
8. [Best Practices](#best-practices)
9. [Monitoring and Observability](#monitoring-and-observability)

## Core Concepts

### What is Caching?

Caching is the process of storing data in a temporary storage location (cache) to reduce access time and improve performance.

### Benefits

- **Performance**: Faster data access
- **Reduced Load**: Less pressure on backend systems
- **Scalability**: Handle more requests
- **Cost Reduction**: Lower database/API costs
- **User Experience**: Faster response times

### Cache Levels

1. **Browser Cache**: Client-side caching
2. **CDN Cache**: Edge caching
3. **Application Cache**: In-memory application cache
4. **Distributed Cache**: Redis, Memcached
5. **Database Cache**: Query result cache

## Caching Patterns

### 1. Cache-Aside (Lazy Loading)

**Pattern**: Application checks cache first, loads from database if miss.

```python
def get_user(user_id):
    # Check cache
    cache_key = f"user:{user_id}"
    user = cache.get(cache_key)
    
    if user is None:
        # Cache miss - load from database
        user = db.get_user(user_id)
        # Store in cache
        cache.set(cache_key, user, ttl=3600)
    
    return user
```

**Use Case**: Read-heavy workloads, flexible cache invalidation

### 2. Write-Through

**Pattern**: Write to cache and database simultaneously.

```python
def update_user(user_id, data):
    # Update database
    user = db.update_user(user_id, data)
    
    # Update cache
    cache_key = f"user:{user_id}"
    cache.set(cache_key, user, ttl=3600)
    
    return user
```

**Use Case**: Write consistency, read-after-write scenarios

### 3. Write-Behind (Write-Back)

**Pattern**: Write to cache immediately, write to database asynchronously.

```python
def update_user(user_id, data):
    # Update cache immediately
    cache_key = f"user:{user_id}"
    cache.set(cache_key, data, ttl=3600)
    
    # Queue database write
    async_queue.enqueue('update_user_db', user_id, data)
    
    return data
```

**Use Case**: High write throughput, eventual consistency acceptable

### 4. Refresh-Ahead

**Pattern**: Proactively refresh cache before expiration.

```python
def get_user(user_id):
    cache_key = f"user:{user_id}"
    user, ttl = cache.get_with_ttl(cache_key)
    
    if user is None:
        # Cache miss
        user = db.get_user(user_id)
        cache.set(cache_key, user, ttl=3600)
    elif ttl < 300:  # Refresh if less than 5 minutes left
        # Refresh in background
        async_queue.enqueue('refresh_user_cache', user_id)
    
    return user
```

**Use Case**: Predictable access patterns, low latency requirements

### 5. Read-Through

**Pattern**: Cache automatically loads from database on miss.

```python
class ReadThroughCache:
    def get(self, key):
        value = self.cache.get(key)
        if value is None:
            # Cache miss - load via loader
            value = self.loader(key)
            self.cache.set(key, value)
        return value
```

**Use Case**: Transparent caching, consistent access pattern

## Redis Deep Dive

### Architecture

Redis is an in-memory data structure store used as a database, cache, and message broker.

### Data Types

#### Strings

```python
import redis

r = redis.Redis(host='localhost', port=6379, db=0)

# Set/Get
r.set('key', 'value')
value = r.get('key')

# Set with expiration
r.setex('key', 3600, 'value')  # Expires in 1 hour
r.set('key', 'value', ex=3600)

# Increment/Decrement
r.incr('counter')
r.decr('counter')
r.incrby('counter', 5)
```

#### Hashes

```python
# Hash operations
r.hset('user:123', 'name', 'John')
r.hset('user:123', 'email', 'john@example.com')
r.hset('user:123', mapping={'name': 'John', 'email': 'john@example.com'})

# Get hash fields
name = r.hget('user:123', 'name')
user = r.hgetall('user:123')

# Increment hash field
r.hincrby('user:123', 'visits', 1)
```

#### Lists

```python
# List operations
r.lpush('queue', 'item1', 'item2')
r.rpush('queue', 'item3')
item = r.lpop('queue')
item = r.rpop('queue')

# Get list range
items = r.lrange('queue', 0, -1)
length = r.llen('queue')
```

#### Sets

```python
# Set operations
r.sadd('tags', 'python', 'redis', 'cache')
members = r.smembers('tags')
is_member = r.sismember('tags', 'python')
r.srem('tags', 'python')

# Set operations
r.sunion('set1', 'set2')
r.sinter('set1', 'set2')
r.sdiff('set1', 'set2')
```

#### Sorted Sets

```python
# Sorted set operations
r.zadd('leaderboard', {'player1': 100, 'player2': 200, 'player3': 150})
top_players = r.zrevrange('leaderboard', 0, 9, withscores=True)
rank = r.zrank('leaderboard', 'player1')
score = r.zscore('leaderboard', 'player1')
```

### Advanced Features

#### Pub/Sub

```python
# Publisher
r.publish('channel', 'message')

# Subscriber
pubsub = r.pubsub()
pubsub.subscribe('channel')
for message in pubsub.listen():
    print(message)
```

#### Transactions

```python
# Multi/Exec transaction
pipe = r.pipeline()
pipe.set('key1', 'value1')
pipe.set('key2', 'value2')
pipe.execute()
```

#### Lua Scripting

```python
# Lua script for atomic operations
script = """
local current = redis.call('GET', KEYS[1])
if current == ARGV[1] then
    return redis.call('SET', KEYS[1], ARGV[2])
else
    return 0
end
"""

r.eval(script, 1, 'key', 'old_value', 'new_value')
```

### Redis Clustering

```bash
# Redis Cluster setup
redis-cli --cluster create \
  127.0.0.1:7000 127.0.0.1:7001 127.0.0.1:7002 \
  127.0.0.1:7003 127.0.0.1:7004 127.0.0.1:7005 \
  --cluster-replicas 1
```

### Redis Sentinel (High Availability)

```bash
# Sentinel configuration
sentinel monitor mymaster 127.0.0.1 6379 2
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 10000
```

### Caching Patterns with Redis

#### Cache-Aside Pattern

```python
def get_user(user_id):
    cache_key = f"user:{user_id}"
    
    # Try cache first
    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)
    
    # Cache miss - load from DB
    user = db.get_user(user_id)
    
    # Store in cache
    r.setex(cache_key, 3600, json.dumps(user))
    
    return user
```

#### Write-Through Pattern

```python
def update_user(user_id, data):
    # Update database
    user = db.update_user(user_id, data)
    
    # Update cache
    cache_key = f"user:{user_id}"
    r.setex(cache_key, 3600, json.dumps(user))
    
    return user
```

#### Cache Warming

```python
def warm_cache():
    # Preload frequently accessed data
    popular_users = db.get_popular_users(limit=100)
    for user in popular_users:
        cache_key = f"user:{user['id']}"
        r.setex(cache_key, 3600, json.dumps(user))
```

## Memcached Deep Dive

### Architecture

Memcached is a high-performance, distributed memory caching system.

### Installation

```bash
# Install Memcached
sudo apt-get install memcached

# Start Memcached
memcached -d -m 64 -p 11211 -u memcache
```

### Basic Operations

```python
import memcache

mc = memcache.Client(['127.0.0.1:11211'])

# Set/Get
mc.set('key', 'value', time=3600)
value = mc.get('key')

# Delete
mc.delete('key')

# Increment/Decrement
mc.incr('counter', 1)
mc.decr('counter', 1)

# Multi-get
values = mc.get_multi(['key1', 'key2', 'key3'])
```

### Memcached vs Redis

| Feature | Memcached | Redis |
|---------|-----------|-------|
| **Data Types** | Strings only | Strings, Hashes, Lists, Sets, Sorted Sets |
| **Persistence** | No | Yes (optional) |
| **Pub/Sub** | No | Yes |
| **Transactions** | No | Yes |
| **Lua Scripting** | No | Yes |
| **Performance** | Faster for simple operations | More features, slightly slower |
| **Use Case** | Simple caching | Complex caching + data structures |

## CDN Caching

### CDN Overview

Content Delivery Networks (CDN) cache content at edge locations close to users.

### Cache Headers

```python
# HTTP cache headers
from flask import Flask, make_response

app = Flask(__name__)

@app.route('/static/<path:filename>')
def static_file(filename):
    response = make_response(send_file(filename))
    
    # Cache-Control
    response.headers['Cache-Control'] = 'public, max-age=3600'
    
    # ETag for validation
    response.headers['ETag'] = generate_etag(filename)
    
    # Last-Modified
    response.headers['Last-Modified'] = get_last_modified(filename)
    
    return response
```

### Cache-Control Directives

- `public`: Can be cached by any cache
- `private`: Only browser can cache
- `no-cache`: Must revalidate before use
- `no-store`: Don't cache at all
- `max-age=3600`: Cache for 1 hour
- `s-maxage=86400`: CDN cache for 1 day

### CDN Invalidation

```python
# Invalidate CDN cache
import boto3

cloudfront = boto3.client('cloudfront')

# Create invalidation
cloudfront.create_invalidation(
    DistributionId='E1234567890',
    InvalidationBatch={
        'Paths': {
            'Quantity': 1,
            'Items': ['/static/image.jpg']
        },
        'CallerReference': str(uuid.uuid4())
    }
)
```

## Cache Invalidation

### Time-Based Expiration (TTL)

```python
# Set expiration time
r.setex('key', 3600, 'value')  # Expires in 1 hour
r.expire('key', 3600)  # Set expiration on existing key
```

### Event-Based Invalidation

```python
def update_user(user_id, data):
    # Update database
    user = db.update_user(user_id, data)
    
    # Invalidate cache
    cache_key = f"user:{user_id}"
    r.delete(cache_key)
    
    # Invalidate related caches
    r.delete(f"user:{user_id}:posts")
    r.delete(f"user:{user_id}:friends")
    
    return user
```

### Tag-Based Invalidation

```python
# Store with tags
def cache_with_tags(key, value, tags, ttl=3600):
    r.setex(key, ttl, value)
    for tag in tags:
        r.sadd(f"tag:{tag}", key)
        r.expire(f"tag:{tag}", ttl)

# Invalidate by tag
def invalidate_tag(tag):
    keys = r.smembers(f"tag:{tag}")
    if keys:
        r.delete(*keys)
    r.delete(f"tag:{tag}")
```

### Version-Based Invalidation

```python
# Versioned cache keys
def get_user(user_id):
    version = r.get(f"user:{user_id}:version") or "1"
    cache_key = f"user:{user_id}:v{version}"
    
    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)
    
    user = db.get_user(user_id)
    r.setex(cache_key, 3600, json.dumps(user))
    return user

# Invalidate by incrementing version
def invalidate_user(user_id):
    r.incr(f"user:{user_id}:version")
```

## Performance Optimization

### Connection Pooling

```python
import redis
from redis.connection import ConnectionPool

# Create connection pool
pool = ConnectionPool(
    host='localhost',
    port=6379,
    max_connections=50,
    decode_responses=True
)

r = redis.Redis(connection_pool=pool)
```

### Pipelining

```python
# Batch operations
pipe = r.pipeline()
for i in range(100):
    pipe.set(f'key{i}', f'value{i}')
pipe.execute()
```

### Compression

```python
import gzip
import json

def set_compressed(key, value, ttl=3600):
    compressed = gzip.compress(json.dumps(value).encode())
    r.setex(key, ttl, compressed)

def get_compressed(key):
    compressed = r.get(key)
    if compressed:
        return json.loads(gzip.decompress(compressed).decode())
    return None
```

### Serialization

```python
import pickle
import json

# JSON (human-readable, slower)
r.set('key', json.dumps(data))
data = json.loads(r.get('key'))

# Pickle (binary, faster)
r.set('key', pickle.dumps(data))
data = pickle.loads(r.get('key'))

# MessagePack (binary, compact)
import msgpack
r.set('key', msgpack.packb(data))
data = msgpack.unpackb(r.get('key'), raw=False)
```

## Best Practices

### 1. Cache Key Design

```python
# Good: Descriptive, namespaced keys
cache_key = f"user:{user_id}:profile"
cache_key = f"product:{product_id}:details"
cache_key = f"order:{order_id}:items"

# Bad: Ambiguous keys
cache_key = f"{user_id}"
cache_key = "data"
```

### 2. Cache Warming

```python
def warm_cache():
    # Preload frequently accessed data
    popular_items = db.get_popular_items(limit=1000)
    for item in popular_items:
        cache_key = f"item:{item['id']}"
        r.setex(cache_key, 3600, json.dumps(item))
```

### 3. Cache Stampede Prevention

```python
import time
import random

def get_user_with_stampede_prevention(user_id):
    cache_key = f"user:{user_id}"
    
    # Try cache
    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)
    
    # Try to acquire lock
    lock_key = f"lock:{cache_key}"
    lock_acquired = r.set(lock_key, "locked", nx=True, ex=5)
    
    if lock_acquired:
        # Load from database
        user = db.get_user(user_id)
        r.setex(cache_key, 3600, json.dumps(user))
        r.delete(lock_key)
        return user
    else:
        # Wait and retry
        time.sleep(random.uniform(0.1, 0.3))
        return get_user_with_stampede_prevention(user_id)
```

### 4. Cache-Aside with Fallback

```python
def get_user_safe(user_id):
    cache_key = f"user:{user_id}"
    
    try:
        cached = r.get(cache_key)
        if cached:
            return json.loads(cached)
    except Exception as e:
        logger.error(f"Cache read error: {e}")
    
    # Fallback to database
    try:
        user = db.get_user(user_id)
        try:
            r.setex(cache_key, 3600, json.dumps(user))
        except Exception as e:
            logger.error(f"Cache write error: {e}")
        return user
    except Exception as e:
        logger.error(f"Database error: {e}")
        raise
```

## Monitoring and Observability

### Redis Monitoring

```bash
# Redis info
redis-cli INFO

# Memory stats
redis-cli INFO memory

# Stats
redis-cli INFO stats

# Monitor commands
redis-cli MONITOR
```

### Key Metrics

- **Hit Rate**: Cache hits / (hits + misses)
- **Memory Usage**: Current memory consumption
- **Evictions**: Number of keys evicted
- **Connections**: Active connections
- **Commands**: Commands per second

### Cache Analytics

```python
# Track cache performance
class CacheMetrics:
    def __init__(self):
        self.hits = 0
        self.misses = 0
    
    def record_hit(self):
        self.hits += 1
    
    def record_miss(self):
        self.misses += 1
    
    def hit_rate(self):
        total = self.hits + self.misses
        return self.hits / total if total > 0 else 0

metrics = CacheMetrics()

def get_user_with_metrics(user_id):
    cache_key = f"user:{user_id}"
    cached = r.get(cache_key)
    
    if cached:
        metrics.record_hit()
        return json.loads(cached)
    else:
        metrics.record_miss()
        user = db.get_user(user_id)
        r.setex(cache_key, 3600, json.dumps(user))
        return user
```

This comprehensive guide provides enterprise-grade caching strategies and implementations for building high-performance caching systems with Redis, Memcached, and CDN integration.

