# Database Systems Reference

## Overview

This directory contains comprehensive database reference materials organized by database system. Each database system follows a consistent structure with core concepts, advanced topics, industry-specific schemas, and templates.

## Directory Structure

```
database/
├── mysql/          # MySQL database reference
├── postgres/       # PostgreSQL database reference
├── mssql/          # SQL Server database reference
├── nosql/          # NoSQL databases reference (MongoDB, DynamoDB, Cassandra, Redis)
└── SQL/            # Legacy SQL examples (generic SQL files)
```

## Database Systems

### MySQL (`mysql/`)

Comprehensive MySQL reference with:
* **Core Concepts**: Schema design, normalization, querying, indexing, constraints, functions, triggers, views, partitioning
* **Advanced Topics**: Backup/recovery, monitoring, performance-tuning, replication, security, enterprise patterns
* **Industry Niches**: 29+ industry-specific schemas
* **Templates**: Starter schemas, simulation schemas, utilities, common patterns

See [mysql/README.md](mysql/README.md) for detailed documentation.

### PostgreSQL (`postgres/`)

Comprehensive PostgreSQL reference with:
* **Core Concepts**: Schema design, normalization, querying, indexing, constraints, functions, triggers, views, partitioning
* **Advanced Topics**: Backup/recovery, monitoring, performance-tuning, replication, security
* **Industry Niches**: 29+ industry-specific schemas
* **Templates**: Starter schemas, utilities, common patterns

See [postgres/README.md](postgres/README.md) for detailed documentation.

### SQL Server (`mssql/`)

Comprehensive SQL Server reference with:
* **Core Concepts**: Schema design, normalization, querying, indexing, constraints, functions, triggers, views, partitioning
* **Advanced Topics**: Backup/recovery, monitoring, performance-tuning, replication, security
* **Industry Niches**: E-commerce and other industry schemas
* **Templates**: Starter schemas, utilities, common patterns

See [mssql/README.md](mssql/README.md) for detailed documentation.

### NoSQL (`nosql/`)

Comprehensive NoSQL reference covering:
* **MongoDB**: Document database patterns and examples
* **DynamoDB**: Key-value database patterns and examples
* **Cassandra**: Wide-column database patterns and examples
* **Redis**: In-memory database patterns and examples
* **Core Concepts**: Schema design, indexing, querying
* **Advanced Topics**: Performance-tuning, replication, security, monitoring
* **Industry Niches**: E-commerce implementations
* **Templates**: Starter schemas, common patterns

See [nosql/README.md](nosql/README.md) for detailed documentation.

## Legacy Directories

### SQL/ (`SQL/`)

Legacy directory containing:
* Generic SQL example files
* Old MySQL learning materials (deprecated - see `mysql/` instead)

**Note**: This directory is kept for reference. New content should be added to the database-specific directories (`mysql/`, `postgres/`, `mssql/`).


## Consistent Structure

All database systems follow the same organizational pattern:

```
{database-system}/
├── core/                    # Core database concepts
│   ├── schema-design/       # Schema design patterns
│   ├── indexing/           # Indexing strategies
│   ├── querying/           # Query patterns
│   ├── normalization/      # Normalization principles
│   ├── constraints/        # Constraint patterns
│   ├── functions/          # Function patterns
│   ├── triggers/          # Trigger patterns
│   ├── views/             # View patterns
│   └── partitioning/      # Partitioning strategies
├── advanced/               # Advanced topics
│   ├── backup-recovery/   # Backup and recovery
│   ├── monitoring/        # Monitoring strategies
│   ├── performance-tuning/# Performance optimization
│   ├── replication/       # Replication patterns
│   └── security/          # Security best practices
├── industry-niches/        # Industry-specific schemas
│   ├── ecommerce/         # E-commerce schemas
│   ├── healthcare/        # Healthcare schemas
│   └── ...                # Many more industries
└── templates/             # Templates and utilities
    ├── starter-schemas/   # Quick-start schemas
    ├── common-patterns/   # Common design patterns
    └── utilities/         # Helper functions and scripts
```

## Usage

1. **Choose your database system** (mysql, postgres, mssql, nosql)
2. **Navigate to core/** for fundamental concepts
3. **Check advanced/** for production-ready patterns
4. **Browse industry-niches/** for domain-specific examples
5. **Use templates/** for quick starts

## Best Practices

* Use database-specific directories for new content
* Follow the consistent structure pattern
* Document design decisions in README files
* Include both SQL/NoSQL examples where applicable
* Keep schemas normalized but performance-optimized

This directory provides a comprehensive reference for all major database systems with consistent organization and documentation.
