# Redis Pub/Sub Comprehensive Guide

## Overview

Redis Pub/Sub is a lightweight messaging system that enables real-time communication between publishers and subscribers. This comprehensive guide covers Redis Pub/Sub patterns, implementation, performance optimization, and enterprise applications for real-time features.

## Core Concepts

### Architecture
- **Publisher**: Application that sends messages to channels
- **Subscriber**: Application that listens for messages on channels
- **Channel**: Named communication pathway for messages
- **Pattern Matching**: Subscribe to multiple channels with wildcards
- **Fire-and-Forget**: Messages are not persisted or acknowledged

### Basic Operations
```bash
# Subscribe to channels
SUBSCRIBE channel1 channel2

# Publish to channel
PUBLISH channel1 "Hello World"

# Unsubscribe
UNSUBSCRIBE channel1

# Pattern subscription
PSUBSCRIBE news:* sports:*

# Publish to pattern-matched channels
PUBLISH news:technology "New AI breakthrough"
PUBLISH sports:football "Championship results"
```

## Implementation Examples

### Node.js Pub/Sub
```javascript
const redis = require('redis');

// Publisher
class RedisPublisher {
    constructor() {
        this.publisher = redis.createClient({
            host: 'localhost',
            port: 6379
        });
    }

    async connect() {
        await this.publisher.connect();
    }

    async publish(channel, message) {
        try {
            const subscribers = await this.publisher.publish(channel, JSON.stringify(message));
            console.log(`Message sent to ${subscribers} subscribers on channel ${channel}`);
            return subscribers;
        } catch (error) {
            console.error('Publish error:', error);
            throw error;
        }
    }

    async disconnect() {
        await this.publisher.quit();
    }
}

// Subscriber
class RedisSubscriber {
    constructor() {
        this.subscriber = redis.createClient({
            host: 'localhost',
            port: 6379
        });
        this.handlers = new Map();
    }

    async connect() {
        await this.subscriber.connect();
    }

    async subscribe(channel, handler) {
        this.handlers.set(channel, handler);

        await this.subscriber.subscribe(channel, (message, channel) => {
            try {
                const data = JSON.parse(message);
                handler(data, channel);
            } catch (error) {
                console.error('Message parsing error:', error);
            }
        });

        console.log(`Subscribed to channel: ${channel}`);
    }

    async pSubscribe(pattern, handler) {
        this.handlers.set(pattern, handler);

        await this.subscriber.pSubscribe(pattern, (message, channel) => {
            try {
                const data = JSON.parse(message);
                handler(data, channel, pattern);
            } catch (error) {
                console.error('Message parsing error:', error);
            }
        });

        console.log(`Subscribed to pattern: ${pattern}`);
    }

    async unsubscribe(channel) {
        await this.subscriber.unsubscribe(channel);
        this.handlers.delete(channel);
        console.log(`Unsubscribed from channel: ${channel}`);
    }

    async pUnsubscribe(pattern) {
        await this.subscriber.pUnsubscribe(pattern);
        this.handlers.delete(pattern);
        console.log(`Unsubscribed from pattern: ${pattern}`);
    }

    async disconnect() {
        await this.subscriber.quit();
    }
}

// Usage
async function example() {
    const publisher = new RedisPublisher();
    const subscriber = new RedisSubscriber();

    await Promise.all([
        publisher.connect(),
        subscriber.connect()
    ]);

    // Subscribe to channels
    await subscriber.subscribe('user:events', (data, channel) => {
        console.log(`Received on ${channel}:`, data);
    });

    await subscriber.pSubscribe('order:*', (data, channel, pattern) => {
        console.log(`Pattern ${pattern} matched ${channel}:`, data);
    });

    // Publish messages
    await publisher.publish('user:events', {
        type: 'USER_LOGIN',
        userId: '123',
        timestamp: new Date().toISOString()
    });

    await publisher.publish('order:created', {
        type: 'ORDER_CREATED',
        orderId: '456',
        amount: 99.99
    });

    await publisher.publish('order:updated', {
        type: 'ORDER_UPDATED',
        orderId: '456',
        status: 'shipped'
    });

    // Cleanup after some time
    setTimeout(async () => {
        await Promise.all([
            publisher.disconnect(),
            subscriber.disconnect()
        ]);
        process.exit(0);
    }, 5000);
}

example().catch(console.error);
```

### Python Pub/Sub
```python
import redis
import json
import asyncio
from typing import Callable, Dict, Any

class RedisPublisher:
    def __init__(self, host: str = 'localhost', port: int = 6379):
        self.redis_client = redis.Redis(host=host, port=port, decode_responses=True)

    def publish(self, channel: str, message: Dict[str, Any]) -> int:
        """Publish message to channel. Returns number of subscribers."""
        try:
            subscribers = self.redis_client.publish(channel, json.dumps(message))
            print(f"Message sent to {subscribers} subscribers on channel {channel}")
            return subscribers
        except Exception as e:
            print(f"Publish error: {e}")
            raise

class RedisSubscriber:
    def __init__(self, host: str = 'localhost', port: int = 6379):
        self.redis_client = redis.Redis(host=host, port=port, decode_responses=True)
        self.pubsub = self.redis_client.pubsub()
        self.handlers: Dict[str, Callable] = {}

    def subscribe(self, channel: str, handler: Callable[[Dict[str, Any], str], None]):
        """Subscribe to a channel"""
        self.handlers[channel] = handler
        self.pubsub.subscribe(**{channel: self._message_handler})
        print(f"Subscribed to channel: {channel}")

    def psubscribe(self, pattern: str, handler: Callable[[Dict[str, Any], str, str], None]):
        """Subscribe to a pattern"""
        self.handlers[pattern] = handler
        self.pubsub.psubscribe(**{pattern: self._pattern_handler})
        print(f"Subscribed to pattern: {pattern}")

    def _message_handler(self, message):
        """Handle channel messages"""
        if message['type'] == 'message':
            channel = message['channel']
            try:
                data = json.loads(message['data'])
                handler = self.handlers.get(channel)
                if handler:
                    handler(data, channel)
            except json.JSONDecodeError as e:
                print(f"JSON decode error: {e}")

    def _pattern_handler(self, message):
        """Handle pattern messages"""
        if message['type'] == 'pmessage':
            pattern = message['pattern']
            channel = message['channel']
            try:
                data = json.loads(message['data'])
                handler = self.handlers.get(pattern)
                if handler:
                    handler(data, channel, pattern)
            except json.JSONDecodeError as e:
                print(f"JSON decode error: {e}")

    def listen(self):
        """Start listening for messages"""
        print("Starting message listener...")
        for message in self.pubsub.listen():
            pass  # Handlers are called in the message handlers

    def unsubscribe(self, channel: str):
        """Unsubscribe from a channel"""
        self.pubsub.unsubscribe(channel)
        self.handlers.pop(channel, None)
        print(f"Unsubscribed from channel: {channel}")

    def punsubscribe(self, pattern: str):
        """Unsubscribe from a pattern"""
        self.pubsub.punsubscribe(pattern)
        self.handlers.pop(pattern, None)
        print(f"Unsubscribed from pattern: {pattern}")

# Async version
class AsyncRedisSubscriber:
    def __init__(self, host: str = 'localhost', port: int = 6379):
        self.redis_client = redis.asyncio.Redis(host=host, port=port, decode_responses=True)
        self.handlers: Dict[str, Callable] = {}

    async def subscribe(self, channel: str, handler: Callable):
        """Subscribe to a channel asynchronously"""
        self.handlers[channel] = handler

        pubsub = self.redis_client.pubsub()
        await pubsub.subscribe(channel)

        async for message in pubsub.listen():
            if message['type'] == 'message':
                try:
                    data = json.loads(message['data'])
                    await handler(data, channel)
                except json.JSONDecodeError as e:
                    print(f"JSON decode error: {e}")

# Usage
def main():
    publisher = RedisPublisher()
    subscriber = RedisSubscriber()

    # Subscribe to channels
    subscriber.subscribe('user:events', lambda data, channel: print(f"User event: {data}"))
    subscriber.psubscribe('order:*', lambda data, channel, pattern: print(f"Order event on {channel}: {data}"))

    # Start listener in a separate thread
    import threading
    listener_thread = threading.Thread(target=subscriber.listen, daemon=True)
    listener_thread.start()

    # Publish messages
    publisher.publish('user:events', {
        'type': 'USER_LOGIN',
        'userId': '123',
        'timestamp': '2024-01-15T10:30:00Z'
    })

    publisher.publish('order:created', {
        'type': 'ORDER_CREATED',
        'orderId': '456',
        'amount': 99.99
    })

    # Keep running
    input("Press Enter to exit...")

if __name__ == "__main__":
    main()
```

### Java Pub/Sub
```java
import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPubSub;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;

public class RedisPubSubExample {
    private final Jedis publisher;
    private final ObjectMapper objectMapper;

    public RedisPubSubExample() {
        this.publisher = new Jedis("localhost", 6379);
        this.objectMapper = new ObjectMapper();
    }

    // Publisher methods
    public long publish(String channel, Map<String, Object> message) {
        try {
            String jsonMessage = objectMapper.writeValueAsString(message);
            return publisher.publish(channel, jsonMessage);
        } catch (Exception e) {
            System.err.println("Publish error: " + e.getMessage());
            return 0;
        }
    }

    // Subscriber implementation
    public static class MessageSubscriber extends JedisPubSub {
        private final ObjectMapper objectMapper = new ObjectMapper();

        @Override
        public void onMessage(String channel, String message) {
            try {
                Map<String, Object> data = objectMapper.readValue(message, Map.class);
                handleMessage(channel, data);
            } catch (Exception e) {
                System.err.println("Message parsing error: " + e.getMessage());
            }
        }

        @Override
        public void onPMessage(String pattern, String channel, String message) {
            try {
                Map<String, Object> data = objectMapper.readValue(message, Map.class);
                handlePatternMessage(pattern, channel, data);
            } catch (Exception e) {
                System.err.println("Pattern message parsing error: " + e.getMessage());
            }
        }

        @Override
        public void onSubscribe(String channel, int subscribedChannels) {
            System.out.println("Subscribed to channel: " + channel);
        }

        @Override
        public void onUnsubscribe(String channel, int subscribedChannels) {
            System.out.println("Unsubscribed from channel: " + channel);
        }

        @Override
        public void onPUnsubscribe(String pattern, int subscribedChannels) {
            System.out.println("Unsubscribed from pattern: " + pattern);
        }

        private void handleMessage(String channel, Map<String, Object> data) {
            System.out.println("Received on " + channel + ": " + data);

            // Route to appropriate handlers
            if (channel.startsWith("user:")) {
                handleUserEvent(data);
            } else if (channel.startsWith("order:")) {
                handleOrderEvent(data);
            }
        }

        private void handlePatternMessage(String pattern, String channel, Map<String, Object> data) {
            System.out.println("Pattern " + pattern + " matched " + channel + ": " + data);
        }

        private void handleUserEvent(Map<String, Object> event) {
            String type = (String) event.get("type");
            switch (type) {
                case "USER_LOGIN":
                    System.out.println("User logged in: " + event.get("userId"));
                    break;
                case "USER_LOGOUT":
                    System.out.println("User logged out: " + event.get("userId"));
                    break;
                default:
                    System.out.println("Unknown user event: " + type);
            }
        }

        private void handleOrderEvent(Map<String, Object> event) {
            String type = (String) event.get("type");
            switch (type) {
                case "ORDER_CREATED":
                    System.out.println("Order created: " + event.get("orderId"));
                    break;
                case "ORDER_UPDATED":
                    System.out.println("Order updated: " + event.get("orderId"));
                    break;
                default:
                    System.out.println("Unknown order event: " + type);
            }
        }
    }

    public void startSubscriber() {
        Jedis subscriber = new Jedis("localhost", 6379);
        MessageSubscriber messageSubscriber = new MessageSubscriber();

        // Subscribe to channels
        new Thread(() -> {
            subscriber.subscribe(messageSubscriber, "user:events", "order:events");
        }).start();

        // Subscribe to patterns
        new Thread(() -> {
            subscriber.psubscribe(messageSubscriber, "notification:*");
        }).start();
    }

    public static void main(String[] args) {
        RedisPubSubExample example = new RedisPubSubExample();

        // Start subscriber
        example.startSubscriber();

        // Publish messages
        example.publish("user:events", Map.of(
            "type", "USER_LOGIN",
            "userId", "123",
            "timestamp", "2024-01-15T10:30:00Z"
        ));

        example.publish("order:events", Map.of(
            "type", "ORDER_CREATED",
            "orderId", "456",
            "amount", 99.99
        ));

        example.publish("notification:email", Map.of(
            "type", "EMAIL_SENT",
            "recipient", "user@example.com",
            "subject", "Welcome!"
        ));

        // Keep running
        try {
            Thread.sleep(5000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
```

## Advanced Patterns

### Message Routing and Filtering
```javascript
class MessageRouter {
    constructor() {
        this.subscriber = new RedisSubscriber();
        this.routes = new Map();
    }

    async connect() {
        await this.subscriber.connect();
    }

    // Register route handlers
    registerRoute(pattern, handler) {
        this.routes.set(pattern, handler);
    }

    // Start routing messages
    async startRouting() {
        // Subscribe to all messages
        await this.subscriber.pSubscribe('*', async (data, channel, pattern) => {
            const route = this.findMatchingRoute(channel);
            if (route) {
                try {
                    await route.handler(data, channel);
                } catch (error) {
                    console.error(`Route handler error for ${channel}:`, error);
                }
            }
        });
    }

    findMatchingRoute(channel) {
        for (const [pattern, route] of this.routes) {
            if (this.matchesPattern(channel, pattern)) {
                return route;
            }
        }
        return null;
    }

    matchesPattern(channel, pattern) {
        const regex = new RegExp(pattern.replace(/\*/g, '.*'));
        return regex.test(channel);
    }
}

// Usage
const router = new MessageRouter();

// Register routes
router.registerRoute('user:*', {
    handler: async (data, channel) => {
        console.log(`Handling user event on ${channel}:`, data);
        // Process user events
    }
});

router.registerRoute('order:*', {
    handler: async (data, channel) => {
        console.log(`Handling order event on ${channel}:`, data);
        // Process order events
    }
});

await router.connect();
await router.startRouting();
```

### Event-Driven Architecture
```javascript
class EventBus {
    constructor() {
        this.publisher = new RedisPublisher();
        this.subscriber = new RedisSubscriber();
        this.eventHandlers = new Map();
    }

    async connect() {
        await Promise.all([
            this.publisher.connect(),
            this.subscriber.connect()
        ]);
    }

    // Register event handler
    on(eventType, handler) {
        if (!this.eventHandlers.has(eventType)) {
            this.eventHandlers.set(eventType, []);
        }
        this.eventHandlers.get(eventType).push(handler);
    }

    // Publish event
    async emit(eventType, payload) {
        const event = {
            id: this.generateId(),
            type: eventType,
            payload,
            timestamp: new Date().toISOString()
        };

        const channel = `events:${eventType}`;
        await this.publisher.publish(channel, event);

        // Also publish to wildcard channel
        await this.publisher.publish('events:*', event);
    }

    // Start listening for events
    async startListening() {
        await this.subscriber.pSubscribe('events:*', (data, channel, pattern) => {
            this.handleEvent(data);
        });
    }

    async handleEvent(event) {
        const handlers = this.eventHandlers.get(event.type) || [];
        const promises = handlers.map(handler => {
            try {
                return handler(event.payload, event);
            } catch (error) {
                console.error(`Event handler error for ${event.type}:`, error);
                return Promise.resolve(); // Don't let one handler break others
            }
        });

        await Promise.all(promises);
    }

    generateId() {
        return Date.now().toString(36) + Math.random().toString(36).substr(2);
    }

    async disconnect() {
        await Promise.all([
            this.publisher.disconnect(),
            this.subscriber.disconnect()
        ]);
    }
}

// Usage
const eventBus = new EventBus();

// Register event handlers
eventBus.on('user.created', async (payload, event) => {
    console.log('User created:', payload);
    // Send welcome email, create profile, etc.
});

eventBus.on('order.placed', async (payload, event) => {
    console.log('Order placed:', payload);
    // Process payment, update inventory, etc.
});

eventBus.on('notification.sent', async (payload, event) => {
    console.log('Notification sent:', payload);
    // Log notification, update metrics, etc.
});

// Start the event bus
await eventBus.connect();
await eventBus.startListening();

// Emit events
await eventBus.emit('user.created', {
    userId: '123',
    email: 'user@example.com',
    name: 'John Doe'
});

await eventBus.emit('order.placed', {
    orderId: '456',
    userId: '123',
    items: [{ productId: '789', quantity: 2 }],
    total: 199.98
});
```

### Real-Time Chat System
```javascript
class ChatService {
    constructor() {
        this.publisher = new RedisPublisher();
        this.subscriber = new RedisSubscriber();
        this.rooms = new Map(); // roomId -> Set of userIds
    }

    async connect() {
        await Promise.all([
            this.publisher.connect(),
            this.subscriber.connect()
        ]);
    }

    // User joins a chat room
    async joinRoom(roomId, userId, userInfo) {
        if (!this.rooms.has(roomId)) {
            this.rooms.set(roomId, new Set());
            // Subscribe to room messages
            await this.subscriber.subscribe(`chat:room:${roomId}`, (data, channel) => {
                this.handleRoomMessage(roomId, data);
            });
        }

        this.rooms.get(roomId).add(userId);

        // Broadcast join message
        await this.publisher.publish(`chat:room:${roomId}`, {
            type: 'user_joined',
            userId,
            userInfo,
            timestamp: new Date().toISOString()
        });
    }

    // User leaves a chat room
    async leaveRoom(roomId, userId) {
        if (this.rooms.has(roomId)) {
            this.rooms.get(roomId).delete(userId);

            // Broadcast leave message
            await this.publisher.publish(`chat:room:${roomId}`, {
                type: 'user_left',
                userId,
                timestamp: new Date().toISOString()
            });

            // Clean up empty rooms
            if (this.rooms.get(roomId).size === 0) {
                this.rooms.delete(roomId);
                await this.subscriber.unsubscribe(`chat:room:${roomId}`);
            }
        }
    }

    // Send message to room
    async sendMessage(roomId, userId, message) {
        if (!this.rooms.has(roomId) || !this.rooms.get(roomId).has(userId)) {
            throw new Error('User not in room');
        }

        await this.publisher.publish(`chat:room:${roomId}`, {
            type: 'message',
            userId,
            message,
            timestamp: new Date().toISOString()
        });
    }

    // Handle incoming room messages
    handleRoomMessage(roomId, data) {
        switch (data.type) {
            case 'user_joined':
                console.log(`User ${data.userId} joined room ${roomId}`);
                break;
            case 'user_left':
                console.log(`User ${data.userId} left room ${roomId}`);
                break;
            case 'message':
                console.log(`Message in room ${roomId} from ${data.userId}: ${data.message}`);
                break;
        }
    }

    // Get room info
    getRoomInfo(roomId) {
        const users = this.rooms.get(roomId);
        return {
            roomId,
            userCount: users ? users.size : 0,
            users: users ? Array.from(users) : []
        };
    }

    async disconnect() {
        await Promise.all([
            this.publisher.disconnect(),
            this.subscriber.disconnect()
        ]);
    }
}

// Usage
const chatService = new ChatService();
await chatService.connect();

// Simulate users joining and chatting
await chatService.joinRoom('general', 'user1', { name: 'Alice' });
await chatService.joinRoom('general', 'user2', { name: 'Bob' });

await chatService.sendMessage('general', 'user1', 'Hello everyone!');
await chatService.sendMessage('general', 'user2', 'Hi Alice!');

console.log(chatService.getRoomInfo('general'));

await chatService.leaveRoom('general', 'user1');
await chatService.disconnect();
```

### Distributed Task Queue
```javascript
class TaskQueue {
    constructor() {
        this.publisher = new RedisPublisher();
        this.subscriber = new RedisSubscriber();
        this.workers = new Map(); // taskType -> Set of workerIds
        this.processing = new Set(); // Set of taskIds being processed
    }

    async connect() {
        await Promise.all([
            this.publisher.connect(),
            this.subscriber.connect()
        ]);
    }

    // Register a worker for a task type
    async registerWorker(taskType, workerId, handler) {
        if (!this.workers.has(taskType)) {
            this.workers.set(taskType, new Set());
            // Subscribe to task queue
            await this.subscriber.subscribe(`tasks:${taskType}`, async (data, channel) => {
                await this.handleTask(taskType, data);
            });
        }

        this.workers.get(taskType).add(workerId);

        // Store worker handler
        this.workerHandlers = this.workerHandlers || new Map();
        this.workerHandlers.set(`${taskType}:${workerId}`, handler);

        console.log(`Worker ${workerId} registered for ${taskType}`);
    }

    // Submit a task
    async submitTask(taskType, taskData) {
        const task = {
            id: this.generateTaskId(),
            type: taskType,
            data: taskData,
            submittedAt: new Date().toISOString(),
            status: 'queued'
        };

        await this.publisher.publish(`tasks:${taskType}`, task);
        return task.id;
    }

    // Handle incoming tasks
    async handleTask(taskType, task) {
        if (this.processing.has(task.id)) {
            return; // Already being processed
        }

        this.processing.add(task.id);

        try {
            // Find available worker
            const workers = this.workers.get(taskType);
            if (!workers || workers.size === 0) {
                console.log(`No workers available for ${taskType}`);
                return;
            }

            // Select a worker (simple round-robin)
            const workerId = Array.from(workers)[0];

            // Get worker handler
            const handlerKey = `${taskType}:${workerId}`;
            const handler = this.workerHandlers.get(handlerKey);

            if (handler) {
                console.log(`Processing task ${task.id} with worker ${workerId}`);

                // Execute task
                const result = await handler(task.data, task);

                // Publish completion
                await this.publisher.publish('task:completed', {
                    taskId: task.id,
                    result,
                    completedAt: new Date().toISOString()
                });

            } else {
                console.error(`No handler found for ${handlerKey}`);
            }

        } catch (error) {
            console.error(`Task ${task.id} failed:`, error);

            // Publish failure
            await this.publisher.publish('task:failed', {
                taskId: task.id,
                error: error.message,
                failedAt: new Date().toISOString()
            });

        } finally {
            this.processing.delete(task.id);
        }
    }

    generateTaskId() {
        return Date.now().toString(36) + Math.random().toString(36).substr(2);
    }

    async disconnect() {
        await Promise.all([
            this.publisher.disconnect(),
            this.subscriber.disconnect()
        ]);
    }
}

// Usage
const taskQueue = new TaskQueue();
await taskQueue.connect();

// Register workers
await taskQueue.registerWorker('email', 'worker1', async (data, task) => {
    console.log(`Sending email to ${data.to}: ${data.subject}`);
    // Simulate email sending
    await new Promise(resolve => setTimeout(resolve, 1000));
    return { status: 'sent', messageId: 'msg123' };
});

await taskQueue.registerWorker('image_resize', 'worker2', async (data, task) => {
    console.log(`Resizing image ${data.imageUrl} to ${data.width}x${data.height}`);
    // Simulate image processing
    await new Promise(resolve => setTimeout(resolve, 2000));
    return { status: 'completed', outputUrl: 'resized-image.jpg' };
});

// Submit tasks
const emailTaskId = await taskQueue.submitTask('email', {
    to: 'user@example.com',
    subject: 'Welcome!',
    body: 'Welcome to our platform!'
});

const imageTaskId = await taskQueue.submitTask('image_resize', {
    imageUrl: 'original.jpg',
    width: 800,
    height: 600
});

console.log(`Submitted tasks: ${emailTaskId}, ${imageTaskId}`);

// Listen for completion
const completionSubscriber = new RedisSubscriber();
await completionSubscriber.connect();

await completionSubscriber.subscribe('task:completed', (data, channel) => {
    console.log(`Task ${data.taskId} completed:`, data.result);
});

await completionSubscriber.subscribe('task:failed', (data, channel) => {
    console.error(`Task ${data.taskId} failed:`, data.error);
});

// Keep running for a while
setTimeout(async () => {
    await Promise.all([
        taskQueue.disconnect(),
        completionSubscriber.disconnect()
    ]);
}, 10000);
```

## Performance Optimization

### Connection Pooling
```javascript
const Redis = require('ioredis');

class RedisConnectionPool {
    constructor(options = {}) {
        this.pool = new Redis.Cluster([
            { host: 'redis-1', port: 6379 },
            { host: 'redis-2', port: 6379 },
            { host: 'redis-3', port: 6379 }
        ], {
            redisOptions: {
                password: options.password,
                tls: options.tls
            },
            clusterRetryDelay: 100,
            maxRedirections: 16,
            ...options
        });
    }

    async publish(channel, message) {
        return this.pool.publish(channel, message);
    }

    async subscribe(channel, callback) {
        const subscriber = this.pool.duplicate();
        await subscriber.subscribe(channel);
        subscriber.on('message', (ch, message) => {
            if (ch === channel) {
                callback(message, ch);
            }
        });
        return subscriber;
    }
}
```

### Message Compression
```javascript
const snappy = require('snappy');
const msgpack = require('msgpack-lite');

class CompressedPubSub {
    constructor(redisClient) {
        this.redis = redisClient;
        this.compressionThreshold = 1024; // Compress messages > 1KB
    }

    async publish(channel, message) {
        let payload = JSON.stringify(message);

        // Compress large messages
        if (payload.length > this.compressionThreshold) {
            const compressed = await snappy.compress(Buffer.from(payload));
            payload = JSON.stringify({
                _compressed: true,
                data: compressed.toString('base64')
            });
        }

        return this.redis.publish(channel, payload);
    }

    async subscribe(channel, callback) {
        await this.redis.subscribe(channel, async (message, ch) => {
            let data = message;

            try {
                const parsed = JSON.parse(message);

                // Decompress if needed
                if (parsed._compressed) {
                    const compressed = Buffer.from(parsed.data, 'base64');
                    const decompressed = await snappy.uncompress(compressed);
                    data = decompressed.toString();
                } else {
                    data = message;
                }

                const payload = JSON.parse(data);
                callback(payload, ch);
            } catch (error) {
                console.error('Message processing error:', error);
            }
        });
    }
}
```

### Message Batching
```javascript
class BatchedPublisher {
    constructor(redisClient, options = {}) {
        this.redis = redisClient;
        this.batchSize = options.batchSize || 10;
        this.flushInterval = options.flushInterval || 1000;
        this.batches = new Map(); // channel -> messages

        this.flushTimer = setInterval(() => {
            this.flushAll();
        }, this.flushInterval);
    }

    publish(channel, message) {
        if (!this.batches.has(channel)) {
            this.batches.set(channel, []);
        }

        const batch = this.batches.get(channel);
        batch.push(message);

        if (batch.length >= this.batchSize) {
            this.flushChannel(channel);
        }
    }

    async flushChannel(channel) {
        const batch = this.batches.get(channel);
        if (!batch || batch.length === 0) return;

        this.batches.set(channel, []);

        const batchMessage = {
            type: 'batch',
            messages: batch,
            timestamp: new Date().toISOString()
        };

        await this.redis.publish(channel, JSON.stringify(batchMessage));
    }

    async flushAll() {
        for (const channel of this.batches.keys()) {
            await this.flushChannel(channel);
        }
    }

    destroy() {
        if (this.flushTimer) {
            clearInterval(this.flushTimer);
        }
        this.flushAll();
    }
}

class BatchedSubscriber {
    constructor(redisClient) {
        this.redis = redisClient;
    }

    async subscribe(channel, callback) {
        await this.redis.subscribe(channel, (message, ch) => {
            try {
                const data = JSON.parse(message);

                if (data.type === 'batch') {
                    // Handle batched messages
                    for (const msg of data.messages) {
                        callback(msg, ch);
                    }
                } else {
                    // Handle single message
                    callback(data, ch);
                }
            } catch (error) {
                console.error('Batch processing error:', error);
            }
        });
    }
}
```

## Monitoring and Observability

### Metrics Collection
```javascript
class PubSubMonitor {
    constructor(redisClient) {
        this.redis = redisClient;
        this.metrics = {
            messagesPublished: 0,
            messagesReceived: 0,
            channelsActive: new Set(),
            errors: 0,
            avgMessageSize: 0,
            messageSizes: []
        };
    }

    recordPublish(channel, messageSize) {
        this.metrics.messagesPublished++;
        this.metrics.channelsActive.add(channel);
        this.updateMessageSize(messageSize);
    }

    recordReceive(channel) {
        this.metrics.messagesReceived++;
        this.metrics.channelsActive.add(channel);
    }

    recordError() {
        this.metrics.errors++;
    }

    updateMessageSize(size) {
        this.metrics.messageSizes.push(size);
        if (this.metrics.messageSizes.length > 1000) {
            this.metrics.messageSizes.shift(); // Keep last 1000
        }
        this.metrics.avgMessageSize =
            this.metrics.messageSizes.reduce((a, b) => a + b, 0) /
            this.metrics.messageSizes.length;
    }

    getMetrics() {
        return {
            ...this.metrics,
            channelsActive: this.metrics.channelsActive.size,
            throughput: this.calculateThroughput(),
            errorRate: this.calculateErrorRate()
        };
    }

    calculateThroughput() {
        // Messages per second (simplified)
        return this.metrics.messagesReceived / ((Date.now() - this.startTime) / 1000);
    }

    calculateErrorRate() {
        const total = this.metrics.messagesPublished + this.metrics.messagesReceived;
        return total > 0 ? (this.metrics.errors / total) * 100 : 0;
    }

    reset() {
        this.startTime = Date.now();
        this.metrics = {
            messagesPublished: 0,
            messagesReceived: 0,
            channelsActive: new Set(),
            errors: 0,
            avgMessageSize: 0,
            messageSizes: []
        };
    }
}
```

### Health Checks
```javascript
class HealthChecker {
    constructor(redisClient) {
        this.redis = redisClient;
        this.lastHealthCheck = 0;
        this.healthStatus = 'unknown';
    }

    async checkHealth() {
        try {
            const start = Date.now();
            await this.redis.ping();
            const latency = Date.now() - start;

            this.healthStatus = latency < 1000 ? 'healthy' : 'degraded';
            this.lastHealthCheck = Date.now();

            return {
                status: this.healthStatus,
                latency,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            this.healthStatus = 'unhealthy';
            return {
                status: 'unhealthy',
                error: error.message,
                timestamp: new Date().toISOString()
            };
        }
    }

    getHealthStatus() {
        return {
            status: this.healthStatus,
            lastCheck: new Date(this.lastHealthCheck).toISOString(),
            timeSinceLastCheck: Date.now() - this.lastHealthCheck
        };
    }
}
```

## Common Patterns and Use Cases

### Real-Time Notifications
```javascript
class NotificationService {
    constructor() {
        this.publisher = new RedisPublisher();
        this.subscriber = new RedisSubscriber();
        this.userConnections = new Map(); // userId -> Set of connectionIds
    }

    async connect() {
        await Promise.all([
            this.publisher.connect(),
            this.subscriber.connect()
        ]);

        // Subscribe to user-specific notification channels
        await this.subscriber.pSubscribe('notifications:user:*', (data, channel, pattern) => {
            const userId = channel.split(':')[2];
            this.deliverToUser(userId, data);
        });
    }

    // User connects (e.g., via WebSocket)
    userConnected(userId, connectionId) {
        if (!this.userConnections.has(userId)) {
            this.userConnections.set(userId, new Set());
        }
        this.userConnections.get(userId).add(connectionId);
    }

    // User disconnects
    userDisconnected(userId, connectionId) {
        if (this.userConnections.has(userId)) {
            this.userConnections.get(userId).delete(connectionId);
            if (this.userConnections.get(userId).size === 0) {
                this.userConnections.delete(userId);
            }
        }
    }

    // Send notification to user
    async sendNotification(userId, notification) {
        const channel = `notifications:user:${userId}`;
        await this.publisher.publish(channel, {
            id: this.generateId(),
            type: notification.type,
            title: notification.title,
            message: notification.message,
            data: notification.data,
            timestamp: new Date().toISOString()
        });
    }

    // Deliver to user's active connections
    deliverToUser(userId, notification) {
        const connections = this.userConnections.get(userId);
        if (connections) {
            for (const connectionId of connections) {
                // Send via WebSocket, SSE, etc.
                this.sendToConnection(connectionId, notification);
            }
        } else {
            // User not connected, could store for later or send push notification
            this.storeOfflineNotification(userId, notification);
        }
    }

    // Broadcast to all users
    async broadcast(notification) {
        await this.publisher.publish('notifications:broadcast', {
            id: this.generateId(),
            ...notification,
            timestamp: new Date().toISOString()
        });
    }

    generateId() {
        return Date.now().toString(36) + Math.random().toString(36).substr(2);
    }

    sendToConnection(connectionId, notification) {
        // Implementation depends on WebSocket/SSE library
        console.log(`Sending to connection ${connectionId}:`, notification);
    }

    storeOfflineNotification(userId, notification) {
        // Store in database or Redis for later delivery
        console.log(`Storing offline notification for user ${userId}:`, notification);
    }
}
```

### Live Activity Feeds
```javascript
class ActivityFeedService {
    constructor() {
        this.publisher = new RedisPublisher();
        this.subscriber = new RedisSubscriber();
        this.feedSubscribers = new Map(); // feedId -> Set of subscriberIds
    }

    async connect() {
        await Promise.all([
            this.publisher.connect(),
            this.subscriber.connect()
        ]);

        // Subscribe to activity feeds
        await this.subscriber.pSubscribe('feed:*', (data, channel, pattern) => {
            const feedId = channel.split(':')[1];
            this.publishToFeed(feedId, data);
        });
    }

    // Subscribe to a feed
    subscribeToFeed(feedId, subscriberId, callback) {
        if (!this.feedSubscribers.has(feedId)) {
            this.feedSubscribers.set(feedId, new Map());
        }

        this.feedSubscribers.get(feedId).set(subscriberId, callback);
    }

    // Unsubscribe from a feed
    unsubscribeFromFeed(feedId, subscriberId) {
        if (this.feedSubscribers.has(feedId)) {
            this.feedSubscribers.get(feedId).delete(subscriberId);
        }
    }

    // Publish activity to feed
    async publishActivity(feedId, activity) {
        const channel = `feed:${feedId}`;
        const activityMessage = {
            id: this.generateId(),
            type: activity.type,
            actor: activity.actor,
            object: activity.object,
            target: activity.target,
            timestamp: new Date().toISOString(),
            metadata: activity.metadata
        };

        await this.publisher.publish(channel, activityMessage);
        return activityMessage.id;
    }

    // Publish to all feed subscribers
    publishToFeed(feedId, activity) {
        const subscribers = this.feedSubscribers.get(feedId);
        if (subscribers) {
            for (const [subscriberId, callback] of subscribers) {
                try {
                    callback(activity, feedId, subscriberId);
                } catch (error) {
                    console.error(`Feed subscriber error for ${subscriberId}:`, error);
                }
            }
        }
    }

    // Get recent activities (from Redis or database)
    async getRecentActivities(feedId, limit = 50) {
        // Implementation depends on storage strategy
        // Could use Redis lists, sorted sets, or external storage
        return [];
    }

    generateId() {
        return Date.now().toString(36) + Math.random().toString(36).substr(2);
    }
}

// Activity types (following Activity Streams spec)
const ActivityTypes = {
    CREATE: 'Create',
    UPDATE: 'Update',
    DELETE: 'Delete',
    FOLLOW: 'Follow',
    LIKE: 'Like',
    COMMENT: 'Comment',
    SHARE: 'Share'
};

// Usage
const feedService = new ActivityFeedService();
await feedService.connect();

// Subscribe to user feed
feedService.subscribeToFeed('user:123', 'subscriber1', (activity, feedId, subscriberId) => {
    console.log(`Activity in feed ${feedId} for subscriber ${subscriberId}:`, activity);
});

// Publish activities
await feedService.publishActivity('user:123', {
    type: ActivityTypes.CREATE,
    actor: { id: 'user:456', name: 'Jane Doe' },
    object: { type: 'Post', id: 'post:789', content: 'Hello world!' },
    target: { type: 'Feed', id: 'user:123' }
});

await feedService.publishActivity('user:123', {
    type: ActivityTypes.LIKE,
    actor: { id: 'user:999', name: 'Bob Smith' },
    object: { type: 'Post', id: 'post:789' }
});
```

This comprehensive Redis Pub/Sub guide provides production-ready implementations for real-time messaging, event-driven architectures, and high-performance communication patterns. From basic publish/subscribe operations to advanced patterns like event buses, chat systems, and distributed task queues, these implementations cover enterprise-grade messaging scenarios.
