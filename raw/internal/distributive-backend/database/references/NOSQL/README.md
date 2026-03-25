# NoSQL Database Schema Design

## Overview

This guide covers comprehensive NoSQL database schema design patterns for major NoSQL databases including DynamoDB, MongoDB, Cassandra, and Redis. Each implementation is optimized for the specific database's strengths, access patterns, and use cases.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Industry Niches](#industry-niches)
3. [Templates](#templates)
4. [Advanced Topics](#advanced-topics)
5. [Best Practices](#best-practices)

## Core Concepts

### Schema Design

Comprehensive schema design patterns for NoSQL databases:

* Embedding vs referencing strategies
* Data modeling patterns
* Document structure optimization
* Relationship patterns

See [core/schema-design/README.md](core/schema-design/README.md) for detailed documentation.

### Indexing

NoSQL indexing strategies for optimal query performance:

* MongoDB indexes (single field, compound, text, geospatial)
* DynamoDB indexes (GSI, LSI)
* Cassandra indexes and materialized views
* Redis data structures

See [core/indexing/README.md](core/indexing/README.md) for detailed documentation.

### Querying

Query patterns and optimization techniques:

* MongoDB query language and aggregation pipelines
* DynamoDB query and scan operations
* Cassandra CQL queries
* Redis operations

See [core/querying/README.md](core/querying/README.md) for detailed documentation.

### Database-Specific Examples

* **MongoDB**: [core/querying/mongodb-examples.js](core/querying/mongodb-examples.js)
* **DynamoDB**: [core/dynamodb-examples.js](core/dynamodb-examples.js)
* **Cassandra**: [core/cassandra-examples.cql](core/cassandra-examples.cql)
* **Redis**: [core/redis-examples.js](core/redis-examples.js)

## Database Types

### Document Databases (MongoDB)

**Best For:**
* Content management systems
* E-commerce platforms
* Real-time analytics
* User profiles and preferences

**Key Features:**
* Flexible schema
* Embedded documents
* Rich query language
* Horizontal scaling with sharding

### Key-Value Databases (DynamoDB, Redis)

**Best For:**
* Session management
* Caching
* Shopping carts
* Real-time leaderboards

**Key Features:**
* Fast read/write performance
* Simple data model
* Automatic scaling
* TTL support

### Wide-Column Databases (Cassandra)

**Best For:**
* Time-series data
* High-write workloads
* Multi-datacenter replication
* Analytics and reporting

**Key Features:**
* Distributed architecture
* High availability
* Linear scalability
* Tunable consistency

## Schema Design Principles

### 1. Design for Access Patterns

Unlike relational databases, NoSQL databases require designing schemas based on how data will be accessed, not how it's related.

**Example:**
```javascript
// DynamoDB: Design partition keys based on query patterns
// Access Pattern: Get all orders for a user
PK: USER#<userId>, SK: ORDER#<orderId>

// Access Pattern: Get order by orderId
PK: ORDER#<orderId>, SK: METADATA
```

### 2. Denormalization

NoSQL databases encourage denormalization to optimize read performance.

**Example:**
```javascript
// MongoDB: Embed frequently accessed data
{
  userId: "123",
  email: "user@example.com",
  orders: [
    {
      orderId: "456",
      productName: "Laptop", // Denormalized
      price: 999.99
    }
  ]
}
```

### 3. Data Modeling Patterns

#### Single-Table Design (DynamoDB)
* Store multiple entity types in one table
* Use composite keys (PK/SK) with entity prefixes
* Use GSIs for alternative access patterns

#### Embedded Documents (MongoDB)
* Embed related data that's frequently accessed together
* Use references for large collections
* Balance between embedding and referencing

#### Partition Key Design (Cassandra)
* Choose partition keys that distribute data evenly
* Avoid hot partitions
* Use clustering keys for sorting

### 4. Indexing Strategies

#### DynamoDB
* Primary key (PK/SK) for main access pattern
* Global Secondary Indexes (GSI) for alternative patterns
* Local Secondary Indexes (LSI) for range queries on sort key

#### MongoDB
* Single field indexes
* Compound indexes
* Text indexes for full-text search
* Geospatial indexes for location queries
* TTL indexes for expiration

#### Cassandra
* Primary key (partition + clustering)
* Materialized views for alternative access patterns
* Secondary indexes (use sparingly)

## Common Patterns

### User Management

**DynamoDB:**
```javascript
{
  PK: "USER#123",
  SK: "PROFILE",
  Email: "user@example.com",
  FirstName: "John",
  LastName: "Doe"
}
```

**MongoDB:**
```javascript
{
  _id: ObjectId("..."),
  email: "user@example.com",
  firstName: "John",
  lastName: "Doe",
  addresses: [
    {
      addressId: ObjectId("..."),
      street: "123 Main St",
      city: "New York"
    }
  ]
}
```

### Product Catalog

**DynamoDB:**
```javascript
{
  PK: "PRODUCT#456",
  SK: "METADATA",
  Name: "Laptop",
  Price: 999.99,
  CategoryId: "789"
}
```

**MongoDB:**
```javascript
{
  _id: ObjectId("..."),
  sku: "LAPTOP-001",
  name: "Laptop",
  price: 999.99,
  categoryId: ObjectId("..."),
  variations: [
    {
      variationId: ObjectId("..."),
      attributes: { color: "black", size: "15inch" },
      priceModifier: 50.00
    }
  ]
}
```

### Shopping Cart

**Redis:**
```javascript
// Hash for cart items
HSET cart:user:123 product:456 quantity 2
HSET cart:user:123 product:789 quantity 1

// Get all cart items
HGETALL cart:user:123
```

**DynamoDB:**
```javascript
{
  PK: "USER#123",
  SK: "CART#456",
  ProductId: "456",
  Quantity: 2,
  UnitPrice: 99.99
}
```

### Order Processing

**MongoDB:**
```javascript
{
  _id: ObjectId("..."),
  orderNumber: "ORD-123456",
  userId: ObjectId("..."),
  status: "pending",
  items: [
    {
      productId: ObjectId("..."),
      productName: "Laptop", // Denormalized
      quantity: 1,
      unitPrice: 999.99
    }
  ],
  totalAmount: 999.99,
  createdAt: ISODate("...")
}
```

## Performance Optimization

### Caching Strategies

**Redis Caching:**
```javascript
// Cache product data
SET product:456 '{"name":"Laptop","price":999.99}' EX 3600

// Cache user session
SET session:abc123 '{"userId":"123","role":"admin"}' EX 1800
```

### Query Optimization

**MongoDB Aggregation:**
```javascript
db.orders.aggregate([
  { $match: { userId: ObjectId("123") } },
  { $group: { _id: null, total: { $sum: "$totalAmount" } } }
])
```

**DynamoDB Query:**
```javascript
// Query with GSI
const params = {
  TableName: 'Ecommerce',
  IndexName: 'GSI1',
  KeyConditionExpression: 'GSI1PK = :userId',
  ExpressionAttributeValues: {
    ':userId': 'USER#123'
  }
};
```

## Scalability Patterns

### Horizontal Scaling

**MongoDB Sharding:**
* Shard by user_id for user data
* Shard by product_id for product catalog
* Use compound shard keys for balanced distribution

**Cassandra Multi-Datacenter:**
* Replicate across datacenters
* Use NetworkTopologyStrategy
* Configure replication factors per datacenter

**DynamoDB On-Demand:**
* Automatic scaling
* Pay per request
* No capacity planning needed

### Data Partitioning

**DynamoDB:**
* Design partition keys for even distribution
* Use sort keys for range queries
* Monitor hot partitions

**Cassandra:**
* Choose partition keys carefully
* Use composite partition keys for better distribution
* Avoid partition key hotspots

## Security Considerations

### Data Encryption

* Encrypt data at rest
* Use TLS for data in transit
* Implement field-level encryption for sensitive data

### Access Control

* Use IAM roles for DynamoDB
* Implement role-based access control in MongoDB
* Use Redis AUTH for authentication
* Implement row-level security where possible

## Monitoring and Analytics

### Key Metrics

* Read/Write throughput
* Latency (P50, P95, P99)
* Error rates
* Cache hit rates
* Storage utilization

### Tools

* **DynamoDB**: CloudWatch, DynamoDB Streams
* **MongoDB**: MongoDB Atlas Monitoring, Ops Manager
* **Cassandra**: nodetool, DataStax OpsCenter
* **Redis**: Redis INFO, Redis Monitor

## Industry Niches

Comprehensive schema designs for various industry verticals:

### E-Commerce
* Products, orders, payments, shipping
* Shopping carts and inventory
* Customer analytics
* Multi-database implementations (DynamoDB, MongoDB)

Each industry niche includes:
* Complete schema designs optimized for specific databases
* README documentation explaining design decisions
* Performance optimization strategies
* Access pattern documentation

See [industry-niches/](industry-niches/) for detailed implementations.

## Templates

### Starter Schemas

Quick-start schemas for common use cases:

* **MongoDB E-Commerce Starter**: Minimal but complete e-commerce schema
* Additional starter schemas coming soon

### Common Patterns

Reusable design patterns:

* Single-table design (DynamoDB)
* Embedding vs referencing (MongoDB)
* Partition key design (Cassandra)
* Caching patterns (Redis)

See [templates/common-patterns/README.md](templates/common-patterns/README.md) for detailed patterns.

## Advanced Topics

### Performance Tuning

Optimization techniques for NoSQL databases:

* Query optimization
* Index optimization
* Schema optimization
* Connection pooling
* Monitoring and profiling

See [advanced/performance-tuning/README.md](advanced/performance-tuning/README.md) for detailed documentation.

### Replication

High availability and data redundancy:

* MongoDB replica sets
* Cassandra multi-datacenter replication
* DynamoDB global tables
* Redis replication

See [advanced/replication/README.md](advanced/replication/README.md) for detailed documentation.

## Best Practices

1. **Choose the right database** for your use case
2. **Design for access patterns** not normalization
3. **Implement proper indexing** for query performance
4. **Use caching** strategically
5. **Monitor performance** and optimize based on metrics
6. **Plan for scaling** from the beginning
7. **Implement proper error handling**
8. **Use transactions** only when necessary
9. **Validate data** at the application level
10. **Document access patterns** and requirements

## Resources

* [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
* [MongoDB Data Modeling](https://docs.mongodb.com/manual/core/data-modeling-introduction/)
* [Cassandra Data Modeling](https://cassandra.apache.org/doc/latest/cassandra/data_modeling/)
* [Redis Data Structures](https://redis.io/topics/data-types-intro)

This guide provides a comprehensive foundation for building scalable applications using NoSQL databases, with each implementation optimized for its specific database's strengths and use cases.

