# SQL Server Replication

## Overview

SQL Server replication is a set of technologies for copying and distributing data and database objects from one database to another, and synchronizing between databases to maintain consistency. This guide covers replication types, configuration, and management.

## Table of Contents

1. [Replication Types](#replication-types)
2. [Snapshot Replication](#snapshot-replication)
3. [Transactional Replication](#transactional-replication)
4. [Merge Replication](#merge-replication)
5. [Peer-to-Peer Replication](#peer-to-peer-replication)
6. [Replication Monitoring](#replication-monitoring)
7. [Enterprise Patterns](#enterprise-patterns)

## Replication Types

### Snapshot Replication

Copies and distributes data exactly as it appears at a specific moment in time.

### Transactional Replication

Distributes changes in near real-time from the publisher to subscribers.

### Merge Replication

Allows bidirectional replication between publisher and subscribers.

### Peer-to-Peer Replication

Allows multiple servers to maintain identical copies of the same database.

## Snapshot Replication

### Setup Snapshot Replication

```sql
-- Configure distributor (run on distributor server)
EXEC sp_adddistributor @distributor = 'DistributorServer';

-- Create distribution database
EXEC sp_adddistributiondb 
    @database = 'distribution',
    @data_folder = 'C:\SQLData',
    @log_folder = 'C:\SQLLogs';
```

### Create Publication

```sql
-- Create snapshot publication
EXEC sp_addpublication
    @publication = 'SalesDB_Publication',
    @publication_type = 0,  -- Snapshot
    @description = 'Snapshot publication for SalesDB';
```

## Transactional Replication

### Setup Transactional Replication

```sql
-- Enable database for replication
EXEC sp_replicationdboption 
    @dbname = 'SalesDB',
    @optname = 'publish',
    @value = 'true';

-- Create transactional publication
EXEC sp_addpublication
    @publication = 'SalesDB_Transactional',
    @publication_type = 0,  -- Transactional
    @sync_method = 'native',
    @repl_freq = 'continuous';
```

## Merge Replication

### Setup Merge Replication

```sql
-- Create merge publication
EXEC sp_addpublication
    @publication = 'SalesDB_Merge',
    @publication_type = 2,  -- Merge
    @sync_method = 'native';
```

## Peer-to-Peer Replication

### Setup Peer-to-Peer

```sql
-- Configure peer-to-peer topology
-- Requires multiple servers with identical schemas
```

## Replication Monitoring

### Monitor Replication Status

```sql
-- Check replication agents
SELECT 
    name AS AgentName,
    status,
    last_run_date,
    last_run_time
FROM msdb.dbo.sysreplicationalerts;

-- Check replication latency
EXEC sp_replmonitorhelppublication;
```

## Enterprise Patterns

### Replication Health Check

```sql
-- Check replication health
SELECT 
    publication,
    status,
    latency,
    last_sync_time
FROM sys.dm_repl_articles;
```

## Best Practices

1. **Choose appropriate replication type** for your use case
2. **Monitor replication latency** regularly
3. **Test failover procedures** in staging
4. **Document replication topology**
5. **Monitor replication agents** for failures
6. **Plan for network bandwidth** requirements
7. **Use appropriate conflict resolution** for merge replication
8. **Backup replication databases** regularly
9. **Monitor replication performance** impact
10. **Document replication procedures**

This guide provides comprehensive SQL Server replication configuration and management techniques.

