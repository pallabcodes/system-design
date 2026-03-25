# MongoDB Performance Tuning

## Overview

Performance tuning in MongoDB involves optimizing queries, indexes, schema design, and server configuration. This guide covers comprehensive performance optimization techniques for MongoDB.

## Table of Contents

1. [Query Optimization](#query-optimization)
2. [Index Optimization](#index-optimization)
3. [Schema Optimization](#schema-optimization)
4. [Connection Pooling](#connection-pooling)
5. [Write Performance](#write-performance)
6. [Read Performance](#read-performance)
7. [Monitoring and Profiling](#monitoring-and-profiling)

## Query Optimization

### Use Explain Plans

```javascript
// Analyze query execution
db.orders.find({ userId: ObjectId("...") }).explain("executionStats");

// Check execution stats
const explain = db.orders.find({ userId: ObjectId("...") }).explain("executionStats");
console.log(explain.executionStats.executionStages.executionTimeMillis);
console.log(explain.executionStats.executionStages.totalDocsExamined);
console.log(explain.executionStats.executionStages.totalDocsReturned);
```

### Optimize Query Patterns

```javascript
// Bad: Full collection scan
db.products.find({ name: /laptop/i });

// Good: Use text index
db.products.find({ $text: { $search: "laptop" } });

// Bad: Multiple queries
const user = db.users.findOne({ email: "user@example.com" });
const orders = db.orders.find({ userId: user._id });

// Good: Single query with $lookup
db.users.aggregate([
  { $match: { email: "user@example.com" } },
  {
    $lookup: {
      from: "orders",
      localField: "_id",
      foreignField: "userId",
      as: "orders"
    }
  }
]);
```

## Index Optimization

### Create Appropriate Indexes

```javascript
// Compound index for common query pattern
db.orders.createIndex({ userId: 1, createdAt: -1 });

// Partial index for conditional queries
db.orders.createIndex(
  { createdAt: -1 },
  { partialFilterExpression: { status: "pending" } }
);

// Covering index
db.orders.createIndex({ userId: 1, orderNumber: 1, totalAmount: 1 });
```

### Monitor Index Usage

```javascript
// Check index usage statistics
db.orders.aggregate([{ $indexStats: {} }]);

// Identify unused indexes
db.orders.aggregate([
  { $indexStats: {} },
  { $match: { "accesses.ops": { $lt: 100 } } }
]);
```

## Schema Optimization

### Document Size

```javascript
// Keep documents under 1MB
// Use references for large embedded arrays
{
  _id: ObjectId("..."),
  productId: ObjectId("..."),
  name: "Laptop",
  // Reference instead of embedding all reviews
  recentReviewIds: [ObjectId("..."), ObjectId("...")]
}
```

### Denormalization Strategy

```javascript
// Denormalize frequently accessed data
{
  _id: ObjectId("..."),
  orderNumber: "ORD-001",
  userId: ObjectId("..."),
  userEmail: "user@example.com",  // Denormalized
  userName: "John Doe",  // Denormalized
  items: [
    {
      productId: ObjectId("..."),
      productName: "Laptop",  // Denormalized
      quantity: 1,
      unitPrice: 999.99
    }
  ]
}
```

## Connection Pooling

### Configure Connection Pool

```javascript
// Node.js MongoDB driver
const { MongoClient } = require('mongodb');

const client = new MongoClient(uri, {
  maxPoolSize: 50,  // Maximum connections
  minPoolSize: 10,  // Minimum connections
  maxIdleTimeMS: 30000,  // Close idle connections
  serverSelectionTimeoutMS: 5000
});
```

## Write Performance

### Bulk Operations

```javascript
// Bulk insert
const operations = products.map(product => ({
  insertOne: { document: product }
}));

db.products.bulkWrite(operations, { ordered: false });

// Bulk update
db.products.bulkWrite([
  { updateMany: { filter: { status: "active" }, update: { $set: { updatedAt: new Date() } } } }
]);
```

### Write Concerns

```javascript
// Acknowledge write (default)
db.orders.insertOne(order, { w: 1 });

// Majority write concern
db.orders.insertOne(order, { w: "majority" });

// Unacknowledged write (fastest, no guarantee)
db.orders.insertOne(order, { w: 0 });
```

## Read Performance

### Read Preferences

```javascript
// Read from primary (default)
db.orders.find().readPref("primary");

// Read from secondary
db.orders.find().readPref("secondary");

// Read from nearest
db.orders.find().readPref("nearest");
```

### Projection

```javascript
// Only return needed fields
db.users.find({ email: "user@example.com" }, { firstName: 1, lastName: 1 });
```

## Monitoring and Profiling

### Enable Profiling

```javascript
// Set profiling level
db.setProfilingLevel(1, { slowms: 100 });  // Profile slow queries (>100ms)

// Get profiling data
db.system.profile.find().sort({ ts: -1 }).limit(10);
```

### Performance Metrics

```javascript
// Server status
db.serverStatus();

// Collection stats
db.orders.stats();

// Current operations
db.currentOp();

// Database stats
db.stats();
```

## Best Practices

1. **Use indexes** for frequently queried fields
2. **Optimize queries** using explain plans
3. **Use bulk operations** for multiple writes
4. **Configure connection pooling** appropriately
5. **Monitor performance** regularly
6. **Use appropriate write concerns** for your use case
7. **Denormalize strategically** for read performance
8. **Keep documents small** (< 1MB)
9. **Use aggregation pipelines** for complex queries
10. **Profile slow queries** and optimize them

This guide provides comprehensive MongoDB performance tuning techniques for optimal database performance.

