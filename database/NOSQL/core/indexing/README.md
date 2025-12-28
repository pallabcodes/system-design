# MongoDB Indexing

## Overview

Indexes in MongoDB are data structures that improve the speed of data retrieval operations. MongoDB supports various index types optimized for different query patterns and data types. Understanding indexing strategies is crucial for MongoDB performance optimization.

## Table of Contents

1. [Index Fundamentals](#index-fundamentals)
2. [Single Field Indexes](#single-field-indexes)
3. [Compound Indexes](#compound-indexes)
4. [Multikey Indexes](#multikey-indexes)
5. [Text Indexes](#text-indexes)
6. [Geospatial Indexes](#geospatial-indexes)
7. [Hashed Indexes](#hashed-indexes)
8. [TTL Indexes](#ttl-indexes)
9. [Partial Indexes](#partial-indexes)
10. [Sparse Indexes](#sparse-indexes)
11. [Index Strategies](#index-strategies)
12. [Index Monitoring](#index-monitoring)

## Index Fundamentals

### What is an Index?

An index is a data structure that stores a small portion of a collection's data in an easy-to-traverse form. The index stores the value of a specific field or set of fields, ordered by the value of the field.

### Index Types Overview

* **Single Field**: Index on a single field
* **Compound**: Index on multiple fields
* **Multikey**: Index on array fields
* **Text**: Full-text search index
* **Geospatial**: 2dsphere and 2d indexes for location data
* **Hashed**: Hash-based indexes for sharding
* **TTL**: Time-to-live indexes for automatic expiration
* **Partial**: Indexes with filter conditions
* **Sparse**: Indexes that skip documents without the indexed field

### Basic Index Operations

```javascript
// Create index
db.collection.createIndex({ field: 1 });

// Create index with name
db.collection.createIndex({ field: 1 }, { name: "idx_field" });

// Create unique index
db.collection.createIndex({ email: 1 }, { unique: true });

// Create compound index
db.collection.createIndex({ userId: 1, createdAt: -1 });

// Drop index
db.collection.dropIndex("idx_field");

// Drop all indexes (except _id)
db.collection.dropIndexes();

// List indexes
db.collection.getIndexes();

// Get index statistics
db.collection.stats();
```

## Single Field Indexes

### Creating Single Field Indexes

```javascript
// Ascending index
db.users.createIndex({ email: 1 });

// Descending index
db.orders.createIndex({ createdAt: -1 });

// Unique index
db.users.createIndex({ email: 1 }, { unique: true });

// Index with options
db.users.createIndex(
  { email: 1 },
  {
    unique: true,
    background: true,
    name: "idx_email_unique"
  }
);
```

### Query Performance

```javascript
// This query will use the index
db.users.find({ email: "user@example.com" });

// This query will also use the index (equality)
db.users.find({ email: { $in: ["user1@example.com", "user2@example.com"] } });

// Range queries use indexes
db.orders.find({ createdAt: { $gte: ISODate("2024-01-01") } });
```

## Compound Indexes

### Creating Compound Indexes

```javascript
// Compound index: userId (ascending), createdAt (descending)
db.orders.createIndex({ userId: 1, createdAt: -1 });

// Compound index with multiple fields
db.products.createIndex({ categoryId: 1, status: 1, price: 1 });
```

### Index Prefix

Compound indexes support queries on the prefix of the index:

```javascript
// Index: { userId: 1, createdAt: -1, status: 1 }

// Uses index (prefix: userId)
db.orders.find({ userId: ObjectId("...") });

// Uses index (prefix: userId, createdAt)
db.orders.find({ userId: ObjectId("..."), createdAt: { $gte: ISODate("...") } });

// Uses full index
db.orders.find({
  userId: ObjectId("..."),
  createdAt: { $gte: ISODate("...") },
  status: "pending"
});
```

### Sort Order in Compound Indexes

```javascript
// For query: find({ userId: ... }).sort({ createdAt: -1 })
db.orders.createIndex({ userId: 1, createdAt: -1 });  // Correct order

// For query: find({ userId: ... }).sort({ createdAt: 1 })
db.orders.createIndex({ userId: 1, createdAt: 1 });  // Correct order

// For queries with both ascending and descending sorts
db.orders.createIndex({ userId: 1, createdAt: -1 });  // Works for both
```

## Multikey Indexes

### Indexing Arrays

MongoDB automatically creates multikey indexes for array fields:

```javascript
// Create collection with array field
db.products.insertOne({
  name: "Laptop",
  tags: ["electronics", "computers", "laptops"]
});

// Create index on array field
db.products.createIndex({ tags: 1 });

// Query using array element (uses multikey index)
db.products.find({ tags: "electronics" });
```

### Indexing Arrays of Embedded Documents

```javascript
// Collection with array of embedded documents
db.orders.insertOne({
  orderNumber: "ORD-001",
  items: [
    { productId: ObjectId("..."), quantity: 2 },
    { productId: ObjectId("..."), quantity: 1 }
  ]
});

// Index on array of embedded documents
db.orders.createIndex({ "items.productId": 1 });

// Query using indexed field
db.orders.find({ "items.productId": ObjectId("...") });
```

## Text Indexes

### Creating Text Indexes

```javascript
// Single field text index
db.products.createIndex({ name: "text" });

// Multiple field text index
db.products.createIndex({
  name: "text",
  description: "text",
  tags: "text"
});

// Text index with weights
db.products.createIndex(
  {
    name: "text",
    description: "text"
  },
  {
    weights: {
      name: 10,  // Higher weight for name
      description: 5
    },
    name: "idx_text_search"
  }
);
```

### Text Search Queries

```javascript
// Text search query
db.products.find({ $text: { $search: "laptop wireless" } });

// Text search with score
db.products.find(
  { $text: { $search: "laptop wireless" } },
  { score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } });

// Text search with language
db.products.createIndex(
  { description: "text" },
  { default_language: "english" }
);
```

## Geospatial Indexes

### 2dsphere Indexes

For GeoJSON and spherical geometry:

```javascript
// Create 2dsphere index
db.locations.createIndex({ location: "2dsphere" });

// Insert document with GeoJSON
db.locations.insertOne({
  name: "Central Park",
  location: {
    type: "Point",
    coordinates: [-73.965355, 40.782865]
  }
});

// Query nearby locations
db.locations.find({
  location: {
    $near: {
      $geometry: {
        type: "Point",
        coordinates: [-73.965355, 40.782865]
      },
      $maxDistance: 1000  // 1km radius
    }
  }
});
```

### 2d Indexes

For legacy coordinate pairs:

```javascript
// Create 2d index
db.places.createIndex({ location: "2d" });

// Insert document with legacy coordinates [longitude, latitude]
db.places.insertOne({
  name: "Central Park",
  location: [-73.965355, 40.782865]
});

// Query nearby locations
db.places.find({
  location: {
    $near: [-73.965355, 40.782865],
    $maxDistance: 0.01
  }
});
```

## Hashed Indexes

### Creating Hashed Indexes

Hashed indexes are used for sharding:

```javascript
// Create hashed index
db.users.createIndex({ userId: "hashed" });

// Hashed indexes support equality queries
db.users.find({ userId: "user123" });
```

## TTL Indexes

### Creating TTL Indexes

TTL indexes automatically delete documents after a specified time:

```javascript
// Create TTL index (expires after 3600 seconds)
db.sessions.createIndex(
  { createdAt: 1 },
  { expireAfterSeconds: 3600 }
);

// Insert document with timestamp
db.sessions.insertOne({
  sessionId: "abc123",
  userId: ObjectId("..."),
  createdAt: new Date()
});
```

### TTL Index Patterns

```javascript
// Expire documents after 24 hours
db.logs.createIndex(
  { createdAt: 1 },
  { expireAfterSeconds: 86400 }
);

// Expire documents after 30 days
db.tempData.createIndex(
  { expiresAt: 1 },
  { expireAfterSeconds: 0 }  // Uses expiresAt field value
);
```

## Partial Indexes

### Creating Partial Indexes

Partial indexes only index documents that match a filter expression:

```javascript
// Index only active users
db.users.createIndex(
  { email: 1 },
  {
    partialFilterExpression: { isActive: true },
    unique: true
  }
);

// Index only orders with status pending
db.orders.createIndex(
  { createdAt: -1 },
  {
    partialFilterExpression: { status: "pending" }
  }
);
```

## Sparse Indexes

### Creating Sparse Indexes

Sparse indexes skip documents without the indexed field:

```javascript
// Sparse index (skips documents without email)
db.users.createIndex(
  { email: 1 },
  { sparse: true, unique: true }
);

// Sparse index is useful for optional fields
db.products.createIndex(
  { sku: 1 },
  { sparse: true, unique: true }
);
```

## Index Strategies

### ESR Rule (Equality, Sort, Range)

Order index fields: Equality → Sort → Range:

```javascript
// Query: find({ status: "active", categoryId: ... }).sort({ createdAt: -1 }).limit(10)
// Index: { status: 1, categoryId: 1, createdAt: -1 }  // Equality, Equality, Sort

// Query: find({ userId: ... }).sort({ createdAt: -1 })
// Index: { userId: 1, createdAt: -1 }  // Equality, Sort

// Query: find({ userId: ..., createdAt: { $gte: ... } })
// Index: { userId: 1, createdAt: -1 }  // Equality, Range
```

### Covering Indexes

Indexes that contain all fields needed for a query:

```javascript
// Query: find({ userId: ... }, { orderNumber: 1, totalAmount: 1, _id: 0 })
// Index: { userId: 1, orderNumber: 1, totalAmount: 1 }  // Covering index

// This query can be satisfied entirely from the index
db.orders.find(
  { userId: ObjectId("...") },
  { orderNumber: 1, totalAmount: 1, _id: 0 }
);
```

### Index Intersection

MongoDB can use multiple indexes for a single query:

```javascript
// Index 1: { userId: 1 }
// Index 2: { status: 1 }

// Query uses both indexes
db.orders.find({ userId: ObjectId("..."), status: "pending" });
```

## Index Monitoring

### Checking Index Usage

```javascript
// Explain query execution
db.orders.find({ userId: ObjectId("...") }).explain("executionStats");

// Check index usage statistics
db.orders.aggregate([
  { $indexStats: {} }
]);

// Get collection statistics
db.orders.stats();
```

### Index Maintenance

```javascript
// Rebuild index
db.collection.reIndex();

// Check index size
db.collection.stats().indexSizes;

// Monitor index build progress
db.currentOp({ "command.createIndexes": { $exists: true } });
```

## Best Practices

1. **Create indexes on frequently queried fields**
2. **Use compound indexes for multi-field queries**
3. **Follow ESR rule for compound indexes**
4. **Use partial indexes for conditional queries**
5. **Use sparse indexes for optional fields**
6. **Create text indexes for full-text search**
7. **Use geospatial indexes for location queries**
8. **Use TTL indexes for time-based expiration**
9. **Monitor index usage and performance**
10. **Remove unused indexes to save space**

This guide provides comprehensive MongoDB indexing strategies for optimal query performance.

