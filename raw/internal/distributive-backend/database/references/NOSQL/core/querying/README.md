# MongoDB Querying

## Overview

MongoDB provides a rich query language for retrieving and manipulating documents. This guide covers comprehensive querying patterns, aggregation pipelines, and performance optimization techniques.

## Table of Contents

1. [Basic Queries](#basic-queries)
2. [Query Operators](#query-operators)
3. [Projection](#projection)
4. [Sorting and Limiting](#sorting-and-limiting)
5. [Aggregation Pipeline](#aggregation-pipeline)
6. [Text Search](#text-search)
7. [Geospatial Queries](#geospatial-queries)
8. [Performance Optimization](#performance-optimization)

## Basic Queries

### Find Operations

```javascript
// Find all documents
db.collection.find();

// Find with filter
db.users.find({ email: "user@example.com" });

// Find one document
db.users.findOne({ email: "user@example.com" });

// Find with projection
db.users.find(
  { email: "user@example.com" },
  { firstName: 1, lastName: 1, _id: 0 }
);
```

### Comparison Operators

```javascript
// Equality
db.products.find({ price: 999.99 });

// Greater than
db.products.find({ price: { $gt: 100 } });

// Greater than or equal
db.products.find({ price: { $gte: 100 } });

// Less than
db.products.find({ price: { $lt: 1000 } });

// Less than or equal
db.products.find({ price: { $lte: 1000 } });

// Not equal
db.products.find({ status: { $ne: "inactive" } });

// In array
db.products.find({ status: { $in: ["active", "pending"] } });

// Not in array
db.products.find({ status: { $nin: ["inactive", "deleted"] } });
```

## Query Operators

### Logical Operators

```javascript
// AND (implicit)
db.orders.find({ userId: ObjectId("..."), status: "pending" });

// AND (explicit)
db.orders.find({
  $and: [
    { userId: ObjectId("...") },
    { status: "pending" }
  ]
});

// OR
db.orders.find({
  $or: [
    { status: "pending" },
    { status: "processing" }
  ]
});

// NOT
db.products.find({
  $not: { price: { $gt: 1000 } }
});

// NOR
db.products.find({
  $nor: [
    { status: "inactive" },
    { price: { $gt: 1000 } }
  ]
});
```

### Element Operators

```javascript
// Exists
db.users.find({ phone: { $exists: true } });

// Type
db.collection.find({ field: { $type: "string" } });
db.collection.find({ field: { $type: "number" } });
db.collection.find({ field: { $type: "objectId" } });
```

### Array Operators

```javascript
// Array contains element
db.products.find({ tags: "electronics" });

// Array contains all elements
db.products.find({ tags: { $all: ["electronics", "computers"] } });

// Array size
db.products.find({ tags: { $size: 3 } });

// Array element match
db.orders.find({
  items: {
    $elemMatch: {
      quantity: { $gt: 5 },
      unitPrice: { $lt: 100 }
    }
  }
});

// Array index
db.products.find({ "tags.0": "electronics" });
```

### Embedded Document Queries

```javascript
// Query nested field
db.users.find({ "address.city": "New York" });

// Query exact match
db.users.find({
  address: {
    street: "123 Main St",
    city: "New York",
    state: "NY"
  }
});
```

## Projection

### Field Selection

```javascript
// Include specific fields
db.users.find({}, { firstName: 1, lastName: 1 });

// Exclude specific fields
db.users.find({}, { password: 0, ssn: 0 });

// Include with exclusion
db.users.find({}, { firstName: 1, lastName: 1, password: 0 });

// Projection with array elements
db.products.find({}, { name: 1, "variations.0": 1 });
```

### Array Slice

```javascript
// Get first 3 elements
db.products.find({}, { tags: { $slice: 3 } });

// Get last 3 elements
db.products.find({}, { tags: { $slice: -3 } });

// Get elements from index with limit
db.products.find({}, { tags: { $slice: [1, 2] } });
```

## Sorting and Limiting

### Sort

```javascript
// Sort ascending
db.orders.find().sort({ createdAt: 1 });

// Sort descending
db.orders.find().sort({ createdAt: -1 });

// Sort multiple fields
db.orders.find().sort({ status: 1, createdAt: -1 });
```

### Limit and Skip

```javascript
// Limit results
db.orders.find().limit(10);

// Skip results
db.orders.find().skip(20);

// Pagination
db.orders.find()
  .sort({ createdAt: -1 })
  .skip(0)
  .limit(10);
```

## Aggregation Pipeline

### Basic Aggregation

```javascript
// Simple aggregation
db.orders.aggregate([
  { $match: { status: "completed" } },
  { $group: { _id: "$userId", total: { $sum: "$totalAmount" } } },
  { $sort: { total: -1 } }
]);
```

### Common Stages

```javascript
// $match - Filter documents
db.orders.aggregate([
  { $match: { status: "pending", totalAmount: { $gt: 100 } } }
]);

// $group - Group and aggregate
db.orders.aggregate([
  {
    $group: {
      _id: "$status",
      count: { $sum: 1 },
      total: { $sum: "$totalAmount" },
      average: { $avg: "$totalAmount" }
    }
  }
]);

// $project - Reshape documents
db.orders.aggregate([
  {
    $project: {
      orderNumber: 1,
      totalAmount: 1,
      year: { $year: "$createdAt" },
      month: { $month: "$createdAt" }
    }
  }
]);

// $lookup - Join collections
db.orders.aggregate([
  {
    $lookup: {
      from: "users",
      localField: "userId",
      foreignField: "_id",
      as: "user"
    }
  }
]);

// $unwind - Deconstruct array
db.orders.aggregate([
  { $unwind: "$items" },
  { $group: { _id: "$items.productId", totalQuantity: { $sum: "$items.quantity" } } }
]);

// $sort - Sort documents
db.orders.aggregate([
  { $sort: { createdAt: -1 } }
]);

// $limit - Limit documents
db.orders.aggregate([
  { $limit: 10 }
]);

// $skip - Skip documents
db.orders.aggregate([
  { $skip: 20 }
]);
```

### Advanced Aggregation

```javascript
// Complex aggregation with multiple stages
db.orders.aggregate([
  // Match pending orders
  { $match: { status: "pending" } },
  
  // Lookup user information
  {
    $lookup: {
      from: "users",
      localField: "userId",
      foreignField: "_id",
      as: "user"
    }
  },
  
  // Unwind user array
  { $unwind: "$user" },
  
  // Project fields
  {
    $project: {
      orderNumber: 1,
      totalAmount: 1,
      userName: { $concat: ["$user.firstName", " ", "$user.lastName"] },
      userEmail: "$user.email"
    }
  },
  
  // Sort by total amount
  { $sort: { totalAmount: -1 } },
  
  // Limit results
  { $limit: 10 }
]);
```

## Text Search

### Text Search Queries

```javascript
// Simple text search
db.products.find({ $text: { $search: "laptop wireless" } });

// Text search with score
db.products.find(
  { $text: { $search: "laptop wireless" } },
  { score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } });

// Text search with language
db.products.find({
  $text: {
    $search: "laptop",
    $language: "en"
  }
});
```

## Geospatial Queries

### Near Queries

```javascript
// Find nearby locations
db.locations.find({
  location: {
    $near: {
      $geometry: {
        type: "Point",
        coordinates: [-73.965355, 40.782865]
      },
      $maxDistance: 1000  // 1km
    }
  }
});

// GeoWithin query
db.locations.find({
  location: {
    $geoWithin: {
      $geometry: {
        type: "Polygon",
        coordinates: [[...]]
      }
    }
  }
});
```

## Performance Optimization

### Explain Plans

```javascript
// Explain query execution
db.orders.find({ userId: ObjectId("...") }).explain("executionStats");

// Explain aggregation
db.orders.aggregate([...]).explain("executionStats");
```

### Index Usage

```javascript
// Force index hint
db.orders.find({ userId: ObjectId("...") }).hint({ userId: 1 });

// Check if index is used
const explain = db.orders.find({ userId: ObjectId("...") }).explain("executionStats");
console.log(explain.executionStats.executionStages.stage);
```

### Query Optimization Tips

1. **Use indexes**: Create indexes on frequently queried fields
2. **Limit results**: Use limit() to reduce result set size
3. **Project fields**: Only return needed fields
4. **Use $match early**: Filter documents early in aggregation pipeline
5. **Avoid large arrays**: Unwind large arrays carefully
6. **Use covered queries**: Create indexes that cover query fields
7. **Monitor performance**: Use explain() to analyze query plans

## Best Practices

1. **Use appropriate operators** for query conditions
2. **Project only needed fields** to reduce network traffic
3. **Use indexes** for frequently queried fields
4. **Optimize aggregation pipelines** by filtering early
5. **Use explain()** to analyze query performance
6. **Limit result sets** to reduce memory usage
7. **Use text indexes** for full-text search
8. **Use geospatial indexes** for location queries
9. **Monitor slow queries** and optimize them
10. **Test queries** with realistic data volumes

This guide provides comprehensive MongoDB querying patterns and optimization techniques for efficient data retrieval.

