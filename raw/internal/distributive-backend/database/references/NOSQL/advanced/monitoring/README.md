# NoSQL Monitoring

## Overview

Monitoring NoSQL databases is essential for maintaining performance, availability, and reliability. This guide covers monitoring strategies for MongoDB, DynamoDB, Cassandra, and Redis.

## Table of Contents

1. [Key Metrics](#key-metrics)
2. [MongoDB Monitoring](#mongodb-monitoring)
3. [DynamoDB Monitoring](#dynamodb-monitoring)
4. [Cassandra Monitoring](#cassandra-monitoring)
5. [Redis Monitoring](#redis-monitoring)
6. [Alerting](#alerting)

## Key Metrics

### Performance Metrics

* **Latency**: P50, P95, P99 response times
* **Throughput**: Operations per second
* **Error Rate**: Failed operations percentage
* **Connection Count**: Active connections

### Resource Metrics

* **CPU Usage**: Processor utilization
* **Memory Usage**: RAM consumption
* **Disk I/O**: Read/write operations
* **Network I/O**: Bandwidth usage

### Database-Specific Metrics

* **MongoDB**: Oplog lag, replication lag, index usage
* **DynamoDB**: Consumed capacity, throttling events
* **Cassandra**: Compaction, repair status, node health
* **Redis**: Hit rate, evictions, memory fragmentation

## MongoDB Monitoring

### Server Status

```javascript
// Get server status
db.serverStatus();

// Key metrics
const status = db.serverStatus();
console.log('Connections:', status.connections);
console.log('Operations:', status.opcounters);
console.log('Memory:', status.mem);
```

### Collection Statistics

```javascript
// Collection stats
db.orders.stats();

// Index usage
db.orders.aggregate([{ $indexStats: {} }]);
```

### Profiling

```javascript
// Enable profiling
db.setProfilingLevel(1, { slowms: 100 });

// Get slow queries
db.system.profile.find().sort({ ts: -1 }).limit(10);
```

### Current Operations

```javascript
// Current operations
db.currentOp();

// Kill slow operation
db.killOp(opid);
```

## DynamoDB Monitoring

### CloudWatch Metrics

```javascript
// Key CloudWatch metrics
// - ConsumedReadCapacityUnits
// - ConsumedWriteCapacityUnits
// - ThrottledRequests
// - UserErrors
// - SystemErrors

// Get table metrics via AWS SDK
const cloudwatch = new AWS.CloudWatch();
const params = {
  MetricName: 'ConsumedReadCapacityUnits',
  Namespace: 'AWS/DynamoDB',
  Dimensions: [
    { Name: 'TableName', Value: 'Orders' }
  ],
  StartTime: new Date(Date.now() - 3600000),
  EndTime: new Date(),
  Period: 300,
  Statistics: ['Average', 'Sum']
};

cloudwatch.getMetricStatistics(params, (err, data) => {
  if (err) console.error(err);
  else console.log(data);
});
```

### Table Metrics

```javascript
// Describe table
const dynamodb = new AWS.DynamoDB();
dynamodb.describeTable({ TableName: 'Orders' }, (err, data) => {
  if (err) console.error(err);
  else {
    console.log('Table size:', data.Table.TableSizeBytes);
    console.log('Item count:', data.Table.ItemCount);
  }
});
```

## Cassandra Monitoring

### Nodetool Commands

```bash
# Node status
nodetool status

# Table statistics
nodetool tablestats keyspace_name.table_name

# Compaction status
nodetool compactionstats

# Repair status
nodetool repair -pr
```

### Metrics

```javascript
// Key metrics to monitor
// - Read latency (P50, P95, P99)
// - Write latency
// - Pending compactions
// - Disk usage
// - Heap usage
```

## Redis Monitoring

### INFO Command

```javascript
// Get Redis info
const info = await client.info();

// Key sections
// - memory: Memory usage
// - stats: Command statistics
// - clients: Client connections
// - replication: Replication status
```

### Memory Usage

```javascript
// Memory info
const memoryInfo = await client.info('memory');
console.log(memoryInfo);

// Check memory usage
const usedMemory = await client.info('memory');
// Parse and monitor used_memory_human
```

### Slow Log

```javascript
// Configure slow log
// In redis.conf:
slowlog-log-slower-than 10000  // Log commands slower than 10ms
slowlog-max-len 128  // Keep last 128 entries

// Get slow log
const slowLog = await client.slowLog('GET', 10);
console.log(slowLog);
```

## Alerting

### Key Alerts

1. **High Latency**: P95 latency > threshold
2. **High Error Rate**: Error rate > 5%
3. **Resource Exhaustion**: CPU/Memory > 80%
4. **Connection Limits**: Connections > 80% of limit
5. **Disk Space**: Disk usage > 85%
6. **Replication Lag**: Lag > threshold

### Alert Configuration

```javascript
// Example alert configuration
const alerts = {
  highLatency: {
    metric: 'p95_latency',
    threshold: 100, // ms
    action: 'notify_team'
  },
  highErrorRate: {
    metric: 'error_rate',
    threshold: 0.05, // 5%
    action: 'page_oncall'
  }
};
```

## Best Practices

1. **Monitor key metrics** continuously
2. **Set up alerts** for critical thresholds
3. **Use dashboards** for visualization
4. **Track trends** over time
5. **Monitor slow queries** and optimize them
6. **Check resource usage** regularly
7. **Monitor replication lag** (if applicable)
8. **Track error rates** and investigate spikes
9. **Monitor capacity** and plan scaling
10. **Review logs** regularly for issues

This guide provides comprehensive monitoring strategies for NoSQL databases.

