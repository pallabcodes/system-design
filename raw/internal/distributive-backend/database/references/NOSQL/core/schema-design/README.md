# MongoDB Schema Design

## Overview

MongoDB schema design differs significantly from relational database design. Instead of normalizing data across multiple tables, MongoDB encourages embedding related data in documents and using references when necessary. This guide covers comprehensive schema design patterns, best practices, and enterprise-level patterns for MongoDB.

## Table of Contents

1. [Schema Design Principles](#schema-design-principles)
2. [Embedding vs Referencing](#embedding-vs-referencing)
3. [Data Modeling Patterns](#data-modeling-patterns)
4. [Document Structure](#document-structure)
5. [Relationships](#relationships)
6. [Advanced Patterns](#advanced-patterns)
7. [Performance Considerations](#performance-considerations)

## Schema Design Principles

### Design for Application Access Patterns

Unlike relational databases, MongoDB schemas should be designed based on how your application queries and updates data, not on data relationships.

**Key Principles:**
* Design for how data is accessed, not how it's related
* Embed data that's frequently accessed together
* Reference data that's accessed independently or changes frequently
* Denormalize for read performance
* Consider document size limits (16MB per document)

### Example: User Profile with Addresses

```javascript
// Good: Embed addresses if frequently accessed with user
{
  _id: ObjectId("..."),
  email: "user@example.com",
  firstName: "John",
  lastName: "Doe",
  addresses: [
    {
      addressId: ObjectId("..."),
      type: "shipping",
      street: "123 Main St",
      city: "New York",
      state: "NY",
      zipCode: "10001"
    }
  ]
}

// Alternative: Reference if addresses are large or frequently updated
{
  _id: ObjectId("..."),
  email: "user@example.com",
  firstName: "John",
  lastName: "Doe",
  addressIds: [ObjectId("..."), ObjectId("...")]
}
```

## Embedding vs Referencing

### When to Embed

Embed documents when:
* Data is frequently accessed together
* Data has a one-to-few relationship
* Data doesn't change frequently
* Data is small in size
* You need atomic updates across related data

**Example: Product with Variations**

```javascript
{
  _id: ObjectId("..."),
  sku: "LAPTOP-001",
  name: "Laptop",
  price: 999.99,
  variations: [  // Embedded: small, frequently accessed together
    {
      variationId: ObjectId("..."),
      attributes: { color: "black", size: "15inch" },
      priceModifier: 50.00,
      stockQuantity: 10
    }
  ]
}
```

### When to Reference

Reference documents when:
* Data is accessed independently
* Data has a one-to-many or many-to-many relationship
* Data changes frequently
* Data is large in size
* You need to avoid document size limits

**Example: Orders with Products**

```javascript
// Order document
{
  _id: ObjectId("..."),
  orderNumber: "ORD-123456",
  userId: ObjectId("..."),  // Reference to users collection
  items: [
    {
      productId: ObjectId("..."),  // Reference to products collection
      productName: "Laptop",  // Denormalized for historical accuracy
      quantity: 1,
      unitPrice: 999.99
    }
  ],
  totalAmount: 999.99
}
```

## Data Modeling Patterns

### One-to-One Relationships

**Pattern: Embed**

```javascript
{
  _id: ObjectId("..."),
  email: "user@example.com",
  profile: {  // One-to-one: embed
    firstName: "John",
    lastName: "Doe",
    dateOfBirth: ISODate("1990-01-01"),
    bio: "Software developer"
  }
}
```

### One-to-Few Relationships

**Pattern: Embed**

```javascript
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),
  addresses: [  // One-to-few: embed
    { type: "shipping", street: "123 Main St", city: "NYC" },
    { type: "billing", street: "456 Oak Ave", city: "LA" }
  ]
}
```

### One-to-Many Relationships

**Pattern: Reference**

```javascript
// Parent document
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),
  email: "user@example.com"
}

// Child documents
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),  // Reference
  orderNumber: "ORD-001",
  totalAmount: 999.99
}
```

### Many-to-Many Relationships

**Pattern: Reference with Denormalization**

```javascript
// Product document
{
  _id: ObjectId("..."),
  name: "Laptop",
  categoryIds: [ObjectId("..."), ObjectId("...")]  // Many-to-many
}

// Category document
{
  _id: ObjectId("..."),
  name: "Electronics",
  productIds: [ObjectId("..."), ObjectId("...")]  // Denormalized for performance
}
```

## Document Structure

### Flat vs Nested Documents

**Flat Structure (Preferred for Queries)**

```javascript
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),
  email: "user@example.com",
  firstName: "John",
  lastName: "Doe",
  addressStreet: "123 Main St",  // Flat structure
  addressCity: "New York",
  addressState: "NY"
}
```

**Nested Structure (For Related Data)**

```javascript
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),
  email: "user@example.com",
  name: {
    first: "John",
    last: "Doe"
  },
  address: {  // Nested for related data
    street: "123 Main St",
    city: "New York",
    state: "NY"
  }
}
```

### Array Patterns

**Array of Embedded Documents**

```javascript
{
  _id: ObjectId("..."),
  productId: ObjectId("..."),
  reviews: [  // Array of embedded documents
    {
      userId: ObjectId("..."),
      rating: 5,
      comment: "Great product!",
      createdAt: ISODate("...")
    }
  ]
}
```

**Array of References**

```javascript
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),
  orderIds: [ObjectId("..."), ObjectId("...")]  // Array of references
}
```

## Relationships

### Parent References

Store reference to parent in child document:

```javascript
// Order document (child)
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),  // Parent reference
  orderNumber: "ORD-001",
  totalAmount: 999.99
}
```

### Child References

Store array of child references in parent:

```javascript
// User document (parent)
{
  _id: ObjectId("..."),
  email: "user@example.com",
  orderIds: [ObjectId("..."), ObjectId("...")]  // Child references
}
```

### Two-Way Referencing

Store references in both documents:

```javascript
// User document
{
  _id: ObjectId("..."),
  email: "user@example.com",
  orderIds: [ObjectId("..."), ObjectId("...")]
}

// Order document
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),
  orderNumber: "ORD-001"
}
```

## Advanced Patterns

### Bucket Pattern

For time-series data or high-cardinality arrays:

```javascript
// Bucket documents for sensor readings
{
  _id: ObjectId("..."),
  sensorId: ObjectId("..."),
  date: ISODate("2024-01-01"),
  readings: [  // Bucket of readings for the day
    { timestamp: ISODate("..."), value: 25.5 },
    { timestamp: ISODate("..."), value: 26.1 }
  ]
}
```

### Extended Reference Pattern

Store frequently accessed fields from referenced document:

```javascript
{
  _id: ObjectId("..."),
  orderNumber: "ORD-001",
  userId: ObjectId("..."),
  userEmail: "user@example.com",  // Extended reference
  userName: "John Doe",  // Extended reference
  items: [
    {
      productId: ObjectId("..."),
      productName: "Laptop",  // Extended reference
      productSku: "LAPTOP-001",  // Extended reference
      quantity: 1,
      unitPrice: 999.99
    }
  ]
}
```

### Subset Pattern

Store subset of frequently accessed data:

```javascript
{
  _id: ObjectId("..."),
  productId: ObjectId("..."),
  name: "Laptop",
  recentReviews: [  // Subset of all reviews
    {
      userId: ObjectId("..."),
      rating: 5,
      comment: "Great!",
      createdAt: ISODate("...")
    }
  ],
  totalReviews: 150  // Count of all reviews
}
```

### Computed Pattern

Store computed/aggregated values:

```javascript
{
  _id: ObjectId("..."),
  productId: ObjectId("..."),
  name: "Laptop",
  totalSales: 1250,  // Computed: sum of all orders
  averageRating: 4.5,  // Computed: average of all reviews
  totalReviews: 150  // Computed: count of all reviews
}
```

### Schema Versioning Pattern

Handle schema evolution:

```javascript
{
  _id: ObjectId("..."),
  schemaVersion: 2,  // Schema version
  email: "user@example.com",
  // Version 2 fields
  profile: {
    firstName: "John",
    lastName: "Doe"
  }
  // Old version 1 fields can be migrated or kept for backward compatibility
}
```

## Performance Considerations

### Document Size

* MongoDB has a 16MB document size limit
* Keep documents under 1MB for optimal performance
* Use references for large embedded arrays
* Consider the bucket pattern for unbounded arrays

### Index Strategy

* Create indexes on frequently queried fields
* Create compound indexes for multi-field queries
* Use sparse indexes for optional fields
* Consider partial indexes for conditional queries

### Query Patterns

* Design documents to match query patterns
* Embed data accessed together
* Denormalize for read performance
* Use aggregation pipelines for complex queries

### Write Patterns

* Consider write performance when denormalizing
* Use transactions for multi-document updates
* Batch writes when possible
* Consider write concerns for durability

## Best Practices

1. **Design for queries**: Structure documents based on how they're accessed
2. **Embed vs Reference**: Embed for one-to-few, reference for one-to-many
3. **Denormalize strategically**: Denormalize for read performance, normalize for write performance
4. **Consider document size**: Keep documents under 1MB, use references for large data
5. **Index appropriately**: Create indexes on frequently queried fields
6. **Use appropriate data types**: Use appropriate BSON types for better performance
7. **Plan for growth**: Design schemas that can scale
8. **Version schemas**: Handle schema evolution gracefully
9. **Monitor performance**: Use explain plans and monitoring tools
10. **Test with real data**: Test schema designs with realistic data volumes

This guide provides a comprehensive foundation for MongoDB schema design, focusing on patterns and practices that optimize for MongoDB's document model and query patterns.

