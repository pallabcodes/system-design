// Redis Examples and Patterns
// Comprehensive Redis implementations for caching, session management, and data structures

// ===========================================
// BASIC REDIS OPERATIONS
// ===========================================

const redis = require('redis');
const client = redis.createClient();

// Connect to Redis
client.connect();

// Basic string operations
await client.set('user:123:name', 'John Doe');
await client.set('user:123:email', 'john@example.com');
await client.setEx('session:abc123', 3600, JSON.stringify({ userId: 123, role: 'admin' }));

// Get data
const name = await client.get('user:123:name');
const session = JSON.parse(await client.get('session:abc123'));

// Batch operations
await client.mSet([
    'config:app_name', 'MyApp',
    'config:version', '1.0.0',
    'config:maintenance', 'false'
]);

const configs = await client.mGet(['config:app_name', 'config:version', 'config:maintenance']);

// Atomic operations
await client.incr('counter:page_views');
await client.incrBy('user:123:login_count', 1);

// Expiration
await client.expire('temp:key', 300); // 5 minutes
await client.pExpire('temp:key2', 5000); // 5 seconds

// ===========================================
// ADVANCED DATA STRUCTURES
// ===========================================

// Lists - Perfect for queues, stacks, recent items
await client.lPush('recent:searches', 'redis');
await client.lPush('recent:searches', 'mongodb');
await client.lTrim('recent:searches', 0, 9); // Keep only 10 most recent

const recentSearches = await client.lRange('recent:searches', 0, -1);

// Sets - Unique collections, membership testing
await client.sAdd('user:123:interests', 'technology', 'databases', 'redis');
await client.sAdd('user:456:interests', 'technology', 'ai', 'redis');

const commonInterests = await client.sInter('user:123:interests', 'user:456:interests');
const userInterests = await client.sMembers('user:123:interests');

// Sorted Sets - Leaderboards, priority queues
await client.zAdd('leaderboard:scores', [
    { score: 1500, value: 'user:123' },
    { score: 1200, value: 'user:456' },
    { score: 1800, value: 'user:789' }
]);

const topPlayers = await client.zRevRange('leaderboard:scores', 0, 2, { WITHSCORES: true });
const userRank = await client.zRevRank('leaderboard:scores', 'user:123');

// Hashes - Object storage
await client.hSet('user:123', {
    name: 'John Doe',
    email: 'john@example.com',
    role: 'admin',
    last_login: Date.now(),
    login_count: 42
});

const user = await client.hGetAll('user:123');
const userEmail = await client.hGet('user:123', 'email');
await client.hIncrBy('user:123', 'login_count', 1);

// ===========================================
// CACHING PATTERNS
// ===========================================

class RedisCache {
    constructor(client, defaultTTL = 3600) {
        this.client = client;
        this.defaultTTL = defaultTTL;
    }

    async get(key) {
        const value = await this.client.get(key);
        return value ? JSON.parse(value) : null;
    }

    async set(key, value, ttl = null) {
        const serializedValue = JSON.stringify(value);
        const expiration = ttl || this.defaultTTL;

        if (expiration > 0) {
            await this.client.setEx(key, expiration, serializedValue);
        } else {
            await this.client.set(key, serializedValue);
        }
    }

    async delete(key) {
        await this.client.del(key);
    }

    async getOrSet(key, fetcher, ttl = null) {
        let value = await this.get(key);
        if (value === null) {
            value = await fetcher();
            await this.set(key, value, ttl);
        }
        return value;
    }

    async invalidatePattern(pattern) {
        const keys = await this.client.keys(pattern);
        if (keys.length > 0) {
            await this.client.del(keys);
        }
    }
}

// Usage example
const cache = new RedisCache(client);

const userData = await cache.getOrSet(
    `user:${userId}`,
    async () => {
        // Fetch from database
        return await db.query('SELECT * FROM users WHERE id = ?', [userId]);
    },
    1800 // 30 minutes TTL
);

// ===========================================
// SESSION MANAGEMENT
// ===========================================

class SessionManager {
    constructor(client, sessionTTL = 86400) { // 24 hours
        this.client = client;
        this.sessionTTL = sessionTTL;
    }

    async createSession(userId, userData = {}) {
        const sessionId = this.generateSessionId();
        const sessionKey = `session:${sessionId}`;

        const sessionData = {
            userId,
            createdAt: Date.now(),
            lastActivity: Date.now(),
            ...userData
        };

        await this.client.setEx(sessionKey, this.sessionTTL, JSON.stringify(sessionData));
        return sessionId;
    }

    async getSession(sessionId) {
        const sessionKey = `session:${sessionId}`;
        const sessionData = await this.client.get(sessionKey);

        if (!sessionData) return null;

        const session = JSON.parse(sessionData);

        // Update last activity
        session.lastActivity = Date.now();
        await this.client.setEx(sessionKey, this.sessionTTL, JSON.stringify(session));

        return session;
    }

    async destroySession(sessionId) {
        const sessionKey = `session:${sessionId}`;
        await this.client.del(sessionKey);
    }

    async extendSession(sessionId, additionalSeconds = 3600) {
        const sessionKey = `session:${sessionId}`;
        const ttl = await this.client.ttl(sessionKey);

        if (ttl > 0) {
            await this.client.expire(sessionKey, ttl + additionalSeconds);
        }
    }

    generateSessionId() {
        return require('crypto').randomBytes(32).toString('hex');
    }
}

// ===========================================
// RATE LIMITING
// ===========================================

class RateLimiter {
    constructor(client, windowSeconds = 60, maxRequests = 100) {
        this.client = client;
        this.windowSeconds = windowSeconds;
        this.maxRequests = maxRequests;
    }

    async isAllowed(identifier, currentTime = Date.now()) {
        const key = `ratelimit:${identifier}`;
        const windowStart = Math.floor(currentTime / 1000) - this.windowSeconds;

        // Remove old requests outside the window
        await this.client.zRemRangeByScore(key, '-inf', windowStart);

        // Count current requests in window
        const requestCount = await this.client.zCard(key);

        if (requestCount >= this.maxRequests) {
            return { allowed: false, remainingRequests: 0 };
        }

        // Add current request
        await this.client.zAdd(key, [{ score: Math.floor(currentTime / 1000), value: currentTime.toString() }]);

        // Set expiration on the key
        await this.client.expire(key, this.windowSeconds);

        return {
            allowed: true,
            remainingRequests: this.maxRequests - requestCount - 1
        };
    }
}

// Usage
const rateLimiter = new RateLimiter(client, 60, 100); // 100 requests per minute

const result = await rateLimiter.isAllowed('user:123');
if (!result.allowed) {
    throw new Error('Rate limit exceeded');
}

// ===========================================
// DISTRIBUTED LOCKING
// ===========================================

class DistributedLock {
    constructor(client, lockTTL = 30) {
        this.client = client;
        this.lockTTL = lockTTL;
    }

    async acquireLock(lockKey, ownerId, ttl = null) {
        const lockValue = ownerId;
        const expiration = ttl || this.lockTTL;

        const result = await this.client.set(lockKey, lockValue, {
            EX: expiration,
            NX: true // Only set if key doesn't exist
        });

        return result === 'OK';
    }

    async releaseLock(lockKey, ownerId) {
        const script = `
            if redis.call('GET', KEYS[1]) == ARGV[1] then
                return redis.call('DEL', KEYS[1])
            else
                return 0
            end
        `;

        return await this.client.eval(script, {
            keys: [lockKey],
            arguments: [ownerId]
        });
    }

    async extendLock(lockKey, ownerId, additionalSeconds = 30) {
        const script = `
            if redis.call('GET', KEYS[1]) == ARGV[1] then
                return redis.call('EXPIRE', KEYS[1], ARGV[2])
            else
                return 0
            end
        `;

        return await this.client.eval(script, {
            keys: [lockKey],
            arguments: [ownerId, additionalSeconds.toString()]
        });
    }
}

// Usage for critical operations
const lock = new DistributedLock(client);

async function processPayment(paymentId) {
    const lockKey = `lock:payment:${paymentId}`;
    const ownerId = `worker:${process.pid}`;

    if (await lock.acquireLock(lockKey, ownerId, 60)) {
        try {
            // Process payment safely
            await processPaymentLogic(paymentId);
        } finally {
            await lock.releaseLock(lockKey, ownerId);
        }
    } else {
        throw new Error('Payment is being processed by another worker');
    }
}

// ===========================================
// PUB/SUB MESSAGING
// ===========================================

class RedisPubSub {
    constructor(client) {
        this.client = client;
        this.subscriber = client.duplicate();
        this.handlers = new Map();
    }

    async subscribe(channel, handler) {
        await this.subscriber.subscribe(channel, (message) => {
            const data = JSON.parse(message);
            handler(data);
        });
        this.handlers.set(channel, handler);
    }

    async unsubscribe(channel) {
        await this.subscriber.unsubscribe(channel);
        this.handlers.delete(channel);
    }

    async publish(channel, data) {
        await this.client.publish(channel, JSON.stringify(data));
    }

    async publishDelayed(channel, data, delayMs) {
        setTimeout(async () => {
            await this.publish(channel, data);
        }, delayMs);
    }
}

// Usage for real-time notifications
const pubsub = new RedisPubSub(client);

// Subscribe to user notifications
await pubsub.subscribe('user:123:notifications', (notification) => {
    console.log('New notification:', notification);
    // Send push notification, email, etc.
});

// Publish notification
await pubsub.publish('user:123:notifications', {
    type: 'order_update',
    message: 'Your order has been shipped',
    orderId: 'ORD-12345'
});

// ===========================================
// REDIS STREAMS (Advanced Messaging)
// ===========================================

// Add events to stream
await client.xAdd('events:orders', '*', {
    event_type: 'order_created',
    order_id: 'ORD-12345',
    user_id: '123',
    amount: '99.99',
    timestamp: Date.now()
});

// Read from stream
const events = await client.xRead(
    { key: 'events:orders', id: '0' }, // Start from beginning
    { COUNT: 10 } // Read 10 events
);

// Consumer groups for reliable message processing
await client.xGroupCreate('events:orders', 'order_processors', '0', { MKSTREAM: true });

// Read as consumer
const consumerEvents = await client.xReadGroup(
    'order_processors',
    'worker-1',
    { key: 'events:orders', id: '>' }, // Only new messages
    { COUNT: 5, BLOCK: 5000 } // Block for 5 seconds if no messages
);

// Acknowledge processing
if (consumerEvents.length > 0) {
    const streamKey = consumerEvents[0].name;
    const messageIds = consumerEvents[0].messages.map(msg => msg.id);

    await client.xAck('events:orders', 'order_processors', messageIds);
}

// ===========================================
// REDIS CLUSTER OPERATIONS
// ===========================================

// For Redis Cluster, use redis.createCluster
const cluster = redis.createCluster({
    rootNodes: [
        { host: '127.0.0.1', port: 7001 },
        { host: '127.0.0.1', port: 7002 },
        { host: '127.0.0.1', port: 7003 }
    ]
});

// Cluster operations work the same way
await cluster.set('distributed:key', 'value');
const value = await cluster.get('distributed:key');

// ===========================================
// MONITORING AND MAINTENANCE
// ===========================================

// Get Redis info
const info = await client.info();
console.log('Redis version:', info.redis_version);
console.log('Connected clients:', info.connected_clients);
console.log('Memory usage:', info.used_memory_human);

// Monitor commands (for debugging)
const monitor = client.monitor();
monitor.on('monitor', (data) => {
    console.log('Command executed:', data);
});

// Health check
async function healthCheck() {
    try {
        await client.ping();
        return { status: 'healthy', latency: await measureLatency() };
    } catch (error) {
        return { status: 'unhealthy', error: error.message };
    }
}

async function measureLatency() {
    const start = Date.now();
    await client.ping();
    return Date.now() - start;
}

// Cleanup expired keys
await client.flushDb(); // Dangerous - deletes all keys
// Better: Let Redis handle expiration automatically

// ===========================================
// ADVANCED PATTERNS
// ===========================================

// HyperLogLog for unique counting (memory efficient)
await client.pfAdd('unique:visitors:daily', 'user:123', 'user:456', 'user:789');
await client.pfAdd('unique:visitors:daily', 'user:123', 'user:999'); // Duplicate ignored
const uniqueVisitors = await client.pfCount('unique:visitors:daily');

// Bit operations for analytics
await client.setBit('user:features', 0, 1); // Premium feature
await client.setBit('user:features', 1, 1); // Beta access
await client.setBit('user:features', 2, 0); // Email notifications off

const hasPremium = await client.getBit('user:features', 0);

// Geospatial operations
await client.geoAdd('drivers:locations', [
    { longitude: -122.4194, latitude: 37.7749, member: 'driver:1' },
    { longitude: -118.2437, latitude: 34.0522, member: 'driver:2' }
]);

// Find nearby drivers
const nearbyDrivers = await client.geoRadius(
    'drivers:locations',
    -122.4194, 37.7749, // User location
    10, 'km', // 10km radius
    { WITHCOORD: true, WITHDIST: true }
);

// ===========================================
// ERROR HANDLING AND CONNECTION MANAGEMENT
// ===========================================

// Connection with retry logic
async function createResilientClient() {
    const client = redis.createClient({
        retry_strategy: (options) => {
            if (options.error && options.error.code === 'ECONNREFUSED') {
                console.error('Redis server refused connection');
                return new Error('Server refused connection');
            }
            if (options.total_retry_time > 1000 * 60 * 60) {
                console.error('Retry time exhausted');
                return new Error('Retry time exhausted');
            }
            if (options.attempt > 10) {
                console.error('Max retry attempts reached');
                return new Error('Max retry attempts reached');
            }
            // Exponential backoff
            return Math.min(options.attempt * 100, 3000);
        }
    });

    client.on('error', (err) => console.error('Redis Client Error', err));
    client.on('connect', () => console.log('Connected to Redis'));
    client.on('ready', () => console.log('Redis client ready'));
    client.on('end', () => console.log('Redis connection ended'));

    await client.connect();
    return client;
}

// Graceful shutdown
process.on('SIGINT', async () => {
    console.log('Shutting down gracefully...');
    await client.quit();
    process.exit(0);
});

// Export for use in other modules
module.exports = {
    RedisCache,
    SessionManager,
    RateLimiter,
    DistributedLock,
    RedisPubSub
};

/*
USAGE EXAMPLES:

// Basic caching
const cache = new RedisCache(client);
await cache.set('user:123', userData, 1800);
const user = await cache.get('user:123');

// Session management
const sessions = new SessionManager(client);
const sessionId = await sessions.createSession(123, { role: 'admin' });
const session = await sessions.getSession(sessionId);

// Rate limiting
const limiter = new RateLimiter(client, 60, 100);
if (!(await limiter.isAllowed('api:123')).allowed) {
    throw new Error('Rate limit exceeded');
}

// Distributed locking
const lock = new DistributedLock(client);
if (await lock.acquireLock('resource:xyz', 'worker:1')) {
    try {
        // Critical section
    } finally {
        await lock.releaseLock('resource:xyz', 'worker:1');
    }
}

// Pub/Sub messaging
const pubsub = new RedisPubSub(client);
await pubsub.subscribe('notifications', handleNotification);
await pubsub.publish('notifications', { type: 'update', data: payload });

This Redis implementation provides:
- Basic operations with strings, lists, sets, hashes, sorted sets
- Advanced caching patterns with TTL and invalidation
- Session management with automatic expiration
- Rate limiting for API protection
- Distributed locking for concurrency control
- Pub/Sub messaging for real-time features
- Redis Streams for advanced messaging
- Geospatial operations for location-based features
- Monitoring and health checks
- Error handling and connection management

Redis is ideal for:
- Caching (application, database query, API response)
- Session storage
- Real-time analytics and leaderboards
- Rate limiting and throttling
- Distributed locking
- Pub/Sub messaging
- Geospatial queries
- Job queues and background processing
*/
