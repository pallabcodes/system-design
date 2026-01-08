# SQL Server Database Schema Design

## Overview

This guide covers comprehensive SQL Server database schema design, focusing on SQL Server-specific features including temporal tables, full-text search, spatial data types, columnstore indexes, memory-optimized tables, and advanced partitioning strategies.

## Key Features

* **Temporal Tables**: Built-in audit trail with system-versioned temporal tables
* **Full-Text Search**: Advanced text search capabilities
* **Spatial Data Types**: GEOGRAPHY and GEOMETRY for location-based queries
* **Columnstore Indexes**: Optimized for analytics and data warehousing
* **Memory-Optimized Tables**: In-memory OLTP for high-performance scenarios
* **Partitioning**: Range, list, and hash partitioning strategies
* **Filegroups**: Advanced storage management and I/O optimization

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Industry Niches](#industry-niches)
3. [Templates](#templates)
4. [Best Practices](#best-practices)

## Core Concepts

### DDL Schema Design

Comprehensive examples of table creation, constraints, indexes, and schema evolution:

* Basic table creation patterns
* Advanced constraints and relationships
* Computed columns
* Temporal tables
* Partitioning strategies

See [core/ddl-schema-design/README.md](core/ddl-schema-design/README.md) for detailed documentation.

### Indexing Strategies

SQL Server indexing patterns for optimal query performance:

* Clustered vs non-clustered indexes
* Covering indexes with INCLUDE columns
* Filtered indexes
* Columnstore indexes
* Full-text indexes

See [core/indexing/README.md](core/indexing/README.md) for detailed documentation.

### Normalization

Database normalization patterns and denormalization strategies:

* First, second, and third normal forms
* When to denormalize
* Performance vs normalization trade-offs

See [core/normalization/README.md](core/normalization/README.md) for detailed documentation.

## Industry Niches

Comprehensive schema designs for various industry verticals:

### E-Commerce
* Products, orders, payments, shipping
* Inventory management
* Customer analytics
* Review and rating systems

### Healthcare
* Patient records
* Appointments and scheduling
* Medical history
* Billing and insurance

### Banking
* Accounts and transactions
* Loans and credit
* Customer management
* Compliance and auditing

### Transportation
* Fleet management
* Route optimization
* Driver management
* Vehicle tracking

And many more...

Each industry niche includes:
* Complete schema design with SQL Server-specific features
* README documentation explaining design decisions
* Performance optimization strategies
* Security considerations

## Templates

### Starter Schemas

Quick-start schemas for common use cases:

* **E-Commerce Starter**: Minimal but complete e-commerce schema
* **SaaS Multi-Tenant**: Multi-tenant application patterns
* **Task Management**: Project and task tracking
* **Blog CMS**: Content management system

### Utilities

Reusable database utilities:

* **Audit Functions**: Comprehensive audit trail implementation
* **Data Validation**: Data validation utilities
* **Maintenance Functions**: Database maintenance scripts
* **Query Optimization**: Query optimization utilities

## Best Practices

### 1. Filegroup Strategy

* Use PRIMARY for system objects only
* Create separate filegroups for data, indexes, and archives
* Distribute files across multiple drives for I/O performance
* Use filegroups for backup strategies

### 2. Index Design

* Clustered index on primary key (usually)
* Non-clustered indexes for foreign keys and frequently queried columns
* Include columns to create covering indexes
* Filtered indexes for conditional queries
* Columnstore indexes for analytics workloads

### 3. Partitioning Strategy

* Partition large tables by date ranges
* Use partition switching for data archival
* Align indexes with partition scheme
* Monitor partition elimination in query plans

### 4. Temporal Tables

* Use for audit trails and history tracking
* Consider storage requirements for history table
* Use FOR SYSTEM_TIME queries for point-in-time analysis
* Archive old history data periodically

### 5. Performance Optimization

* Use computed columns for calculated values
* Implement proper indexing strategies
* Use columnstore indexes for analytics
* Consider memory-optimized tables for high-throughput scenarios
* Monitor query plans and optimize accordingly

### 6. Security

* Implement row-level security for multi-tenant scenarios
* Use Always Encrypted for sensitive data
* Implement proper access control
* Encrypt sensitive data at rest and in transit

## SQL Server Specific Features

### Temporal Tables

System-versioned temporal tables provide automatic history tracking:

```sql
-- Query historical data
SELECT * FROM Orders
FOR SYSTEM_TIME AS OF '2024-01-01 10:00:00'
WHERE OrderID = 'order-guid';
```

### Full-Text Search

Advanced text search capabilities:

```sql
-- Search products using full-text search
SELECT ProductID, Name, BasePrice
FROM Products
WHERE CONTAINS((Name, Description), 'wireless headphones')
  AND Status = 'active';
```

### Spatial Data Types

Geographic data support:

```sql
-- Find warehouses near a location
DECLARE @Location GEOGRAPHY = geography::Point(40.7128, -74.0060, 4326);

SELECT WarehouseID, Name,
       Geolocation.STDistance(@Location) / 1000 AS DistanceKm
FROM Warehouses
WHERE Geolocation.STDistance(@Location) <= 50000
ORDER BY DistanceKm;
```

### Columnstore Indexes

Optimized for analytics workloads:

```sql
-- Create clustered columnstore index
CREATE CLUSTERED COLUMNSTORE INDEX CCI_SalesFact
ON SalesFact;
```

## Resources

* [SQL Server Documentation](https://docs.microsoft.com/en-us/sql/sql-server/)
* [SQL Server Best Practices](https://docs.microsoft.com/en-us/sql/relational-databases/performance/best-practice-and-performance-checklist-for-sql-server-engine)
* [Temporal Tables Guide](https://docs.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables)
* [Index Design Guide](https://docs.microsoft.com/en-us/sql/relational-databases/sql-server-index-design-guide)

This guide provides a comprehensive foundation for building scalable SQL Server database schemas with enterprise-grade features and performance optimizations.
