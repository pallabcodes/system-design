# SQL Reference Materials

## Overview

This directory contains SQL examples and MySQL-specific learning materials.

## Contents

### Generic SQL Files

Basic SQL examples covering:
* `administrator.sql` - Database administration examples
* `alter.sql` - ALTER TABLE examples
* `conditional.sql` - Conditional SQL statements
* `constraints.sql` - Constraint examples
* `datatypes.sql` - Data type examples
* `filtering_data.sql` - WHERE clause examples
* `generated_columns.sql` - Generated/computed columns
* `group.sql` - GROUP BY examples
* `innodb.sql` - InnoDB-specific examples
* `insert.sql` - INSERT statement examples
* `list.sql` - List operations
* `template.sql` - SQL templates
* `users.sql` - User management examples

### MySQL Directory

MySQL-specific learning materials organized into:

#### `learnings/`

Advanced MySQL concepts and patterns:

* **CTEs**: Common Table Expressions (`ctes/advanced.sql`)
* **Denormalizations**: Advanced denormalization patterns (`denormalizations/advanced.sql`)
* **Enterprise Patterns**: Production-ready patterns used by major tech companies
  * Advanced caching, indexing, security
  * Data migration, sharding, multi-tenancy
  * Event sourcing, distributed transactions
  * Location-based patterns, timezone handling
  * And many more...
* **Functions**: User-defined functions (`functions/`)
* **InnoDB**: InnoDB engine specifics (`innodb/advanced.sql`)
* **Joins**: Complex join patterns (`joins/`)
* **Locking**: Advanced locking strategies (`locking/`)
* **Monitoring**: Database monitoring (`monitoring/`)
* **Performance**: Performance optimization (`performaces/`, `query-optimization/`)
* **Replication**: High availability (`replication-ha/`)
* **Stored Procedures**: Stored procedure examples (`stored-procedures/`)
* **Subqueries**: Subquery patterns (`subqueries/`)
* **Transactions**: Transaction management (`transactions/`)
* **Triggers**: Trigger examples (`triggers/`)
* **Views**: View patterns (`views/`)

#### `simulation/`

Real-world schema designs:
* `aws-user/` - AWS user management schema
* `dropbox/` - Dropbox-like file storage schema
* `ecommerce/` - E-commerce platform schema
* `messaging/` - Messaging system schema
* `recruitPro/` - Recruitment platform schema
* `restaurant/` - Restaurant management schema

## Related Documentation

For organized, comprehensive MySQL documentation, see:
* `/references/system-design/mysql/` - Structured MySQL documentation

