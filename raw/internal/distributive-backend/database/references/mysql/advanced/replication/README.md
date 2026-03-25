# SQL Server Replication

## Overview

Replication is a set of technologies for copying and distributing data and database objects from one database to another and then synchronizing between databases to maintain consistency.

## Replication Types

### 1. Transactional Replication
- **Description**: Replicates each change (transaction) incrementally as it occurs.
- **Use Case**: Server-to-server scenarios where you need near real-time consistency (e.g., Reporting Server).
- **Latency**: Very low (seconds).

### 2. Merge Replication
- **Description**: Allows changes to differ at multiple sites (Publisher and Subscribers) and merges them later.
- **Use Case**: Disconnected scenarios (e.g., Mobile POS, Field Agents) where conflict resolution is needed.
- **Complexity**: High (requires GUIDs, tracking tables).

### 3. Snapshot Replication
- **Description**: Distributes data exactly as it appears at a specific moment in time. Does not monitor for updates to the data.
- **Use Case**: Initial sync for other types, or infrequent updates.

## Components

- **Publisher**: The source database instance that makes data available.
- **Distributor**: Stores metadata and history data. also stores transactions for transactional replication.
- **Subscriber**: The destination database instance.
- **Publication**: A collection of articles (tables, stored procs) to be reproduced.
- **Subscription**: A request for a copy of a publication to be delivered to a Subscriber.

## Best Practices

1.  **Primary Keys**: Transactional replication requires a Primary Key on all published tables.
2.  **Separate Distributor**: For high-volume environments, place the Distributor on a separate dedicated server.
3.  **Monitor Latency**: Use Replication Monitor to check for latency and errors.
4.  **Schema Changes**: Be careful with schema changes (DDL) on published tables; use `sp_repladdcolumn` or allow schema replication options.
