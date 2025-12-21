# Database Sharding: Scaling Your Database

## What is Sharding?

**Database sharding** is a technique that partitions a database across multiple servers/nodes to handle increased load and improve performance.

## How Sharding Works

1. **Data Partitioning**: Your database data is split into smaller chunks called **logical shards**
2. **Distribution**: These logical shards are distributed across different database nodes called **physical shards**
3. **Independence**: Each shard operates independently and doesn't share data or resources with other shards

## When Do You Need Sharding?

- Your application becomes popular and database gets overloaded
- Traditional scaling methods (vertical scaling) are insufficient
- You need to distribute load across multiple servers

## Key Benefits

- **Scalability**: Handle more data and users
- **Performance**: Faster queries due to smaller data sets per shard
- **Availability**: If one shard fails, others continue working

## Important Notes

- Shards are independent but may contain duplicate reference tables for efficiency
- Each shard contains a subset of your complete dataset
- Sharding is a horizontal scaling solution

---

# Advantages of Sharding

## 1. **Horizontal Scalability**
**Problem Solved**: Database size limits and performance bottlenecks

### How it Works
- Distribute data across multiple servers instead of one large server
- Each shard handles a subset of the total data
- Can add more shards as your data grows

### Example
```
Before Sharding:
Single Server: 1TB database, 10M users
- Query time: 5-10 seconds
- Storage limit: 2TB max

After Sharding:
5 Shards: 200GB each, 2M users per shard
- Query time: 0.5-1 second
- Total capacity: 10TB+ (unlimited scaling)
```

## 2. **Improved Query Performance**
**Problem Solved**: Slow queries on large datasets

### How it Works
- Queries only search relevant shards instead of entire database
- Smaller indexes per shard = faster lookups
- Parallel processing across multiple shards

### Example
```
Searching for users in "California":
- Without sharding: Scan 10M records
- With geographic sharding: Scan only 2M records in US-West shard
- Performance improvement: 5x faster
```

## 3. **High Availability & Fault Tolerance**
**Problem Solved**: Single point of failure

### How it Works
- If one shard fails, others continue operating
- Can replicate individual shards for backup
- Graceful degradation instead of complete outage

### Example
```
Shard 1 (US-East): 2M users ✅
Shard 2 (US-West): 2M users ✅  
Shard 3 (Europe): 2M users ❌ (failed)
Shard 4 (Asia): 2M users ✅
Shard 5 (Global): 2M users ✅

Result: 80% of users still have access
```

## 4. **Geographic Distribution**
**Problem Solved**: Latency for global users

### How it Works
- Place shards closer to users
- Reduce network latency
- Comply with data residency laws

### Example
```
User in Tokyo queries data:
- Without sharding: 200ms latency (US server)
- With sharding: 20ms latency (Asia shard)
- 10x faster response time
```

## 5. **Cost Optimization**
**Problem Solved**: Expensive vertical scaling

### How it Works
- Use multiple smaller, cheaper servers instead of one expensive server
- Scale incrementally as needed
- Better resource utilization

### Example
```
Vertical Scaling (expensive):
- 1 server: 64 cores, 1TB RAM, 10TB storage = $50,000/month

Horizontal Scaling (cost-effective):
- 10 servers: 8 cores, 128GB RAM, 1TB storage each = $25,000/month
- 50% cost savings with better performance
```

## 6. **Flexible Resource Allocation**
**Problem Solved**: Uneven resource usage

### How it Works
- Allocate more resources to busy shards
- Scale individual shards independently
- Optimize for different workload patterns

### Example
```
E-commerce during Black Friday:
- Product catalog shard: 10x normal traffic → Add more replicas
- User profiles shard: Normal traffic → Keep current resources
- Orders shard: 5x normal traffic → Scale up temporarily
```

## 7. **Better Backup & Recovery**
**Problem Solved**: Long backup times and recovery windows

### How it Works
- Backup individual shards in parallel
- Faster recovery of specific data
- Reduced risk of complete data loss

### Example
```
Backup Times:
- Single database: 8 hours to backup 1TB
- 10 shards: 30 minutes each = 30 minutes total
- 16x faster backup process
```

## 8. **Easier Maintenance**
**Problem Solved**: Complex maintenance on large databases

### How it Works
- Maintain smaller, manageable databases
- Update schemas on individual shards
- Test changes on subset of data first

### Example
```
Schema Migration:
- Single database: High risk, affects all users
- Sharded database: Migrate one shard at a time
- Rollback capability per shard
```

## Trade-offs to Consider

### **Complexity**
- More complex application logic
- Need for distributed transaction handling
- Cross-shard query coordination

### **Data Consistency**
- Eventual consistency across shards
- Complex joins across shards
- Referential integrity challenges

### **Operational Overhead**
- More servers to manage
- Monitoring multiple shards
- Backup and recovery complexity

---

# Sharding Techniques

Sharding can be classified as **algorithmic** or **dynamic**.

## 1. **Algorithmic Sharding**

**How it Works**: The client doesn't need any help figuring out which database is in a given partition. Uses a sharding function to locate data.

### Example
```sql
-- Simple sharding function: hash(key) % NUM_DB
Shard 0: user_id % 4 = 0 (users: 4, 8, 12, 16...)
Shard 1: user_id % 4 = 1 (users: 1, 5, 9, 13...)
Shard 2: user_id % 4 = 2 (users: 2, 6, 10, 14...)
Shard 3: user_id % 4 = 3 (users: 3, 7, 11, 15...)
```

### Key Characteristics
- **Single database reads**: With partition key, reads are done in a single database
- **Cross-shard queries**: Without partition key, each database node must be searched
- **Even distribution**: Data is split only by the sharding function
- **No payload consideration**: Doesn't consider data size or space usage
- **Fine-grained partitions**: Reduces hotspots by having many partitions per database

### Use Cases
- Key-value databases with uniform value sizes
- Simple, predictable access patterns
- When partition key is always available

## 2. **Dynamic Sharding**

Reference: https://medium.com/@sourabhatta1819/sharding-technique-in-database-f936641bf71d

**How it Works**: An external locator service determines the location of entries. Clients consult the locator service first.

### Implementation Options
```sql
-- Option 1: Individual key mapping (few partition keys)
| partition_key | database_id | location |
|---------------|-------------|----------|
| user_123      | db_1        | east     |
| user_456      | db_2        | west     |

-- Option 2: Range-based mapping (many partition keys)
| key_range_start | key_range_end | database_id | location |
|-----------------|---------------|-------------|----------|
| 1               | 1000000       | db_1        | east     |
| 1000001         | 2000000       | db_2        | west     |
```

### Key Characteristics
- **External locator**: Separate service tracks partition locations
- **Flexible mapping**: Can place any data on any shard
- **Easy resharding**: Can move data without redistribution
- **Primary key efficiency**: Operations by primary key become trivial
- **Query optimization**: Other queries become more efficient as locator structure changes

### Use Cases
- Complex business logic requirements
- Multi-tenant applications
- When you need flexible data placement

## Comparison

| Aspect | Algorithmic Sharding | Dynamic Sharding |
|--------|---------------------|------------------|
| **Complexity** | Simple | Complex |
| **Performance** | Fast (no lookup) | Slower (lookup required) |
| **Flexibility** | Low | High |
| **Resharding** | Difficult | Easy |
| **Use Case** | Simple, uniform data | Complex, variable data |

## Important Considerations

### **Algorithmic Sharding**
- Avoid non-partitioned queries (they don't scale with cluster size)
- Ensure even data distribution across partitions
- Best for key-value stores with uniform data sizes

### **Dynamic Sharding**
- Locator service becomes a critical component
- Consider caching locator lookups for performance
- Plan for locator service high availability

---

# Database Partitioning: Horizontal vs Vertical

## Horizontal Partitioning (Row-based)

**Horizontal partitioning** splits a table by **rows** across multiple databases or servers.

### How it Works
- Each partition contains **all columns** but **different rows**
- Data is distributed based on a **partition key** (e.g., user_id, date, region)

### Example
```
Users Table (Original):
| user_id | name | email | country | created_date |
|---------|------|-------|---------|--------------|
| 1       | John | j@... | US      | 2023-01-01   |
| 2       | Jane | j@... | UK      | 2023-01-02   |
| 3       | Bob  | b@... | US      | 2023-01-03   |

Partition 1 (US users):
| user_id | name | email | country | created_date |
|---------|------|-------|---------|--------------|
| 1       | John | j@... | US      | 2023-01-01   |
| 3       | Bob  | b@... | US      | 2023-01-03   |

Partition 2 (UK users):
| user_id | name | email | country | created_date |
|---------|------|-------|---------|--------------|
| 2       | Jane | j@... | UK      | 2023-01-02   |
```

### Use Cases
- **Sharding**: Distribute data across multiple servers
- **Time-based partitioning**: Separate data by date ranges
- **Geographic partitioning**: Split by region/country

## Vertical Partitioning (Column-based)

**Vertical partitioning** splits a table by **columns** into multiple tables.

### How it Works
- Each partition contains **all rows** but **different columns**
- Related columns are grouped together

### Example
```
Users Table (Original):
| user_id | name | email | bio | preferences | last_login | created_date |
|---------|------|-------|-----|-------------|------------|--------------|
| 1       | John | j@... | ... | {...}       | 2024-01-01 | 2023-01-01   |
| 2       | Jane | j@... | ... | {...}       | 2024-01-02 | 2023-01-02   |

Core User Data:
| user_id | name | email | created_date |
|---------|------|-------|--------------|
| 1       | John | j@... | 2023-01-01   |
| 2       | Jane | j@... | 2023-01-02   |

User Profile Data:
| user_id | bio | preferences |
|---------|-----|-------------|
| 1       | ... | {...}       |
| 2       | ... | {...}       |

User Activity Data:
| user_id | last_login |
|---------|------------|
| 1       | 2024-01-01 |
| 2       | 2024-01-02 |
```

### Use Cases
- **Normalization**: Separate frequently vs rarely accessed data
- **Security**: Isolate sensitive columns
- **Performance**: Keep hot data separate from cold data

## Comparison

| Aspect | Horizontal Partitioning | Vertical Partitioning |
|--------|------------------------|----------------------|
| **Split By** | Rows | Columns |
| **Data Distribution** | Across servers | Across tables |
| **Use Case** | Scaling (sharding) | Optimization |
| **Complexity** | Higher (distributed queries) | Lower (joins) |
| **Performance** | Better for large datasets | Better for specific queries |

## When to Use Each

### Choose Horizontal Partitioning When:
- You have **millions of rows** and need to scale
- Data can be **naturally separated** (by date, region, etc.)
- You need **distributed processing**

### Choose Vertical Partitioning When:
- You have **wide tables** with many columns
- Some columns are **rarely accessed**
- You want to **optimize specific queries**
- **Security** requires column isolation