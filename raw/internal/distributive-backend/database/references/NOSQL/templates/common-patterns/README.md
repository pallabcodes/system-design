# NoSQL Common Patterns

## Overview

This guide covers common design patterns used across NoSQL databases including DynamoDB, MongoDB, Cassandra, and Redis. These patterns help solve common problems in NoSQL database design.

## Table of Contents

1. [Single Table Design (DynamoDB)](#single-table-design-dynamodb)
2. [Embedding vs Referencing (MongoDB)](#embedding-vs-referencing-mongodb)
3. [Partition Key Design (Cassandra)](#partition-key-design-cassandra)
4. [Caching Patterns (Redis)](#caching-patterns-redis)
5. [Time-Series Patterns](#time-series-patterns)
6. [Event Sourcing Patterns](#event-sourcing-patterns)

## Single Table Design (DynamoDB)

### Pattern Overview

Store multiple entity types in a single table using composite keys with entity type prefixes.

### Example

```javascript
// Users, Orders, Products in one table
{
  PK: "USER#123",
  SK: "PROFILE",
  EntityType: "USER",
  Email: "user@example.com"
}

{
  PK: "USER#123",
  SK: "ORDER#456",
  EntityType: "ORDER",
  OrderNumber: "ORD-001"
}

{
  PK: "PRODUCT#789",
  SK: "METADATA",
  EntityType: "PRODUCT",
  Name: "Laptop"
}
```

### Benefits

* Single table scan for related data
* Atomic transactions across entities
* Reduced RCU/WCU usage

## Embedding vs Referencing (MongoDB)

### Embedding Pattern

Embed related data in the same document:

```javascript
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),
  addresses: [  // Embedded
    { type: "shipping", street: "123 Main St" }
  ]
}
```

### Referencing Pattern

Reference related data using ObjectIds:

```javascript
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),
  orderIds: [ObjectId("..."), ObjectId("...")]  // Referenced
}
```

## Partition Key Design (Cassandra)

### Pattern Overview

Design partition keys to distribute data evenly and support query patterns.

### Example

```cql
-- Partition by customer and date for order queries
CREATE TABLE orders (
    customer_id UUID,
    order_date DATE,
    order_id UUID,
    total_amount DECIMAL,
    PRIMARY KEY ((customer_id, order_date), order_id)
);
```

## Caching Patterns (Redis)

### Cache-Aside Pattern

```javascript
// Check cache first
const cached = await redis.get(`product:${productId}`);
if (cached) return JSON.parse(cached);

// If not in cache, fetch from database
const product = await db.products.findOne({ _id: productId });

// Store in cache
await redis.setEx(`product:${productId}`, 3600, JSON.stringify(product));
return product;
```

### Write-Through Pattern

```javascript
// Write to database and cache
await db.products.updateOne({ _id: productId }, { $set: data });
await redis.setEx(`product:${productId}`, 3600, JSON.stringify(data));
```

## Time-Series Patterns

### Bucket Pattern (MongoDB)

```javascript
{
  sensorId: ObjectId("..."),
  date: ISODate("2024-01-01"),
  readings: [  // Bucket of readings
    { timestamp: ISODate("..."), value: 25.5 },
    { timestamp: ISODate("..."), value: 26.1 }
  ]
}
```

### Time-Series Table (Cassandra)

```cql
CREATE TABLE sensor_readings (
    sensor_id UUID,
    date DATE,
    timestamp TIMESTAMP,
    value DOUBLE,
    PRIMARY KEY ((sensor_id, date), timestamp)
) WITH CLUSTERING ORDER BY (timestamp DESC);
```

## Event Sourcing Patterns

### Event Store (MongoDB)

```javascript
{
  _id: ObjectId("..."),
  aggregateId: ObjectId("..."),
  eventType: "OrderCreated",
  eventData: { orderNumber: "ORD-001", totalAmount: 999.99 },
  timestamp: ISODate("..."),
  version: 1
}
```

## Best Practices

1. **Choose the right pattern** for your use case
2. **Design for access patterns** not data relationships
3. **Consider scalability** from the beginning
4. **Monitor performance** and adjust patterns
5. **Document patterns** used in your system

This guide provides common NoSQL design patterns for building scalable applications.

