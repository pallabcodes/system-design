# MongoDB Replication

## Overview

MongoDB replication provides high availability and data redundancy through replica sets. This guide covers replica set configuration, management, and best practices.

## Table of Contents

1. [Replica Set Fundamentals](#replica-set-fundamentals)
2. [Replica Set Configuration](#replica-set-configuration)
3. [Replica Set Operations](#replica-set-operations)
4. [Read Preferences](#read-preferences)
5. [Write Concerns](#write-concerns)
6. [Failover and Recovery](#failover-and-recovery)

## Replica Set Fundamentals

### What is a Replica Set?

A replica set is a group of MongoDB instances that maintain the same data set. It provides:
* High availability through automatic failover
* Data redundancy through replication
* Read scaling through secondary reads

### Replica Set Members

* **Primary**: Accepts all write operations
* **Secondaries**: Replicate data from primary, can serve reads
* **Arbiter**: Votes in elections but doesn't hold data

## Replica Set Configuration

### Initialize Replica Set

```javascript
// Start MongoDB instances
mongod --replSet "rs0" --port 27017
mongod --replSet "rs0" --port 27018
mongod --replSet "rs0" --port 27019

// Connect to primary and initialize
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "localhost:27017" },
    { _id: 1, host: "localhost:27018" },
    { _id: 2, host: "localhost:27019" }
  ]
});
```

### Add Members

```javascript
// Add secondary
rs.add("localhost:27020");

// Add arbiter
rs.addArb("localhost:27021");
```

### Remove Members

```javascript
// Remove member
rs.remove("localhost:27020");
```

## Replica Set Operations

### Check Status

```javascript
// Replica set status
rs.status();

// Configuration
rs.conf();

// Is master
db.isMaster();
```

### Step Down Primary

```javascript
// Step down primary (forces election)
rs.stepDown();
```

## Read Preferences

### Read Preference Modes

```javascript
// Primary (default)
db.orders.find().readPref("primary");

// Primary preferred
db.orders.find().readPref("primaryPreferred");

// Secondary
db.orders.find().readPref("secondary");

// Secondary preferred
db.orders.find().readPref("secondaryPreferred");

// Nearest
db.orders.find().readPref("nearest");
```

## Write Concerns

### Write Concern Levels

```javascript
// Acknowledge write (default)
db.orders.insertOne(order, { w: 1 });

// Majority write concern
db.orders.insertOne(order, { w: "majority" });

// Custom write concern
db.orders.insertOne(order, {
  w: 2,  // Wait for 2 members
  wtimeout: 5000  // Timeout after 5 seconds
});
```

## Failover and Recovery

### Automatic Failover

MongoDB automatically elects a new primary if the current primary becomes unavailable.

### Manual Recovery

```javascript
// Restart failed member
// MongoDB will automatically catch up
```

## Best Practices

1. **Use odd number of members** (3, 5, 7) for proper voting
2. **Deploy across data centers** for disaster recovery
3. **Use appropriate write concerns** for data durability
4. **Monitor replica set status** regularly
5. **Test failover scenarios** in staging
6. **Use read preferences** to distribute read load
7. **Configure oplog size** appropriately
8. **Monitor replication lag**
9. **Backup regularly** from secondary members
10. **Document replica set configuration**

This guide provides comprehensive MongoDB replication configuration and management techniques.

