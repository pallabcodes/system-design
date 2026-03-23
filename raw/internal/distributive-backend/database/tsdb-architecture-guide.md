# Time Series Database Architecture: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Gorilla Compression, Compaction, Cardinality, TSDB Internals — With Paper References and Production Patterns

> [!CAUTION]
> **The Cardinal Sin**: Treating a TSDB as "PostgreSQL with timestamps." TSDBs trade query flexibility for **append-only, time-ordered, high-cardinality** optimization. Wrong use = cluster death.

---

## 📚 Required Reading

| Paper | Year | Key Concepts |
| :--- | :--- | :--- |
| [Gorilla: A Fast, Scalable, In-Memory TSDB](https://www.vldb.org/pvldb/vol8/p1816-teller.pdf) | 2015 | Delta-of-delta, XOR compression |
| [Monarch: Google's Planet-Scale Monitoring](https://research.google/pubs/monarch-googles-planet-scale-in-memory-time-series-database/) | 2020 | Multi-zone replication, query federation |
| [Prometheus: Designing and Implementing a Modern Monitoring Solution](https://promcon.io/2017-munich/talks/prometheus-design-and-philosophy/) | 2012 | Pull-based metrics, local storage |

---

## 🎯 The Principal Laws of Time Series

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Append-Only** | Never update historical data | Immutable blocks, efficient compression |
| **Law 2: Time is Primary** | 99% of queries filter by time | Optimize for range scans |
| **Law 3: Cardinality is Doom** | Each unique label combo = 1 series | 1M labels = 1M open files |
| **Law 4: Recent is Hot** | 95% of reads are last 24h | Keep recent data in RAM |

---

# Part 1: Gorilla Compression (Facebook)

**Paper**: [Gorilla: A Fast, Scalable, In-Memory TSDB](https://www.vldb.org/pvldb/vol8/p1816-teller.pdf)

## 📊 The Problem

```
Raw data point: (timestamp: 8 bytes, value: 8 bytes) = 16 bytes

At 1-second resolution, 1 metric for 1 year:
31M samples × 16 bytes = 500MB PER METRIC

With 100K metrics: 50TB/year

We can do better.
```

## ⏱️ Timestamp Compression: Delta-of-Delta

### Observation
```
Timestamps are (usually) monotonically increasing at regular intervals.

Raw: [1704067200, 1704067215, 1704067230, 1704067245, ...]
Δ:   [          ,         15,         15,         15, ...]
ΔΔ:  [          ,           ,          0,          0, ...]

If interval is regular, delta-of-delta is 0!
```

### Encoding Algorithm
```python
def encode_timestamp(prev_ts, prev_delta, current_ts):
    delta = current_ts - prev_ts
    delta_of_delta = delta - prev_delta
    
    if delta_of_delta == 0:
        # Best case: Same interval as before
        write_bits('0')  # 1 bit
        return delta
    
    elif -63 <= delta_of_delta <= 64:
        # Small deviation
        write_bits('10')  # 2 bit header
        write_bits(delta_of_delta, 7)  # 7 bit value (signed)
        # Total: 9 bits
        return delta
    
    elif -255 <= delta_of_delta <= 256:
        write_bits('110')
        write_bits(delta_of_delta, 9)
        # Total: 12 bits
        return delta
    
    elif -2047 <= delta_of_delta <= 2048:
        write_bits('1110')
        write_bits(delta_of_delta, 12)
        # Total: 16 bits
        return delta
    
    else:
        write_bits('1111')
        write_bits(delta_of_delta, 32)
        # Total: 36 bits
        return delta
```

### Real-World Compression
```
Regular 15-second intervals:
- First timestamp: 64 bits
- Subsequent: 1 bit each (delta-of-delta = 0)
- 1000 samples ≈ 64 + 999 = 1063 bits ≈ 133 bytes
- Raw: 8000 bytes
- Compression ratio: 60x

With occasional jitter (±1 second):
- ~50% are 1 bit, ~50% are 9 bits
- 1000 samples ≈ 64 + 500 + 4500 = 5064 bits ≈ 633 bytes
- Compression ratio: 12x
```

## 📈 Value Compression: XOR Encoding

### Observation
```
Consecutive metric values are often similar.

CPU%: [50.1, 50.2, 50.1, 50.3, 50.2, ...]
XOR:  [    , 0x00..01, 0x00..02, 0x00..01, 0x00..01, ...]

Most bits are the same. Store only the different bits.
```

### IEEE 754 Double Layout
```
Sign (1) | Exponent (11) | Mantissa (52) = 64 bits

50.1 = 0 10000000100 1001000011001100110011001100110011001100110011010
50.2 = 0 10000000100 1001001100110011001100110011001100110011001100110

XOR:   0 00000000000 0000001111111111111111111111111111111111111110100

Leading zeros: 14
Trailing zeros: 2
Meaningful bits: 48
```

### Encoding Algorithm
```python
def encode_value(prev_value, current_value):
    xor = prev_value ^ current_value
    
    if xor == 0:
        # Same value as before
        write_bits('0')  # 1 bit
        return
    
    leading_zeros = count_leading_zeros(xor)
    trailing_zeros = count_trailing_zeros(xor)
    meaningful_bits = 64 - leading_zeros - trailing_zeros
    
    # Check if we can reuse previous leading/trailing
    if (leading_zeros >= prev_leading and 
        trailing_zeros >= prev_trailing):
        # Control bit = 1, then 0 (reuse block info)
        write_bits('10')
        write_bits(xor >> trailing_zeros, meaningful_bits)
    else:
        # Control bit = 1, then 1 (new block info)
        write_bits('11')
        write_bits(leading_zeros, 5)   # 0-31
        write_bits(meaningful_bits, 6)  # 0-63
        write_bits(xor >> trailing_zeros, meaningful_bits)
```

### Real-World Compression
```
CPU metric (slowly varying):
- Most XORs have 50+ leading zeros
- Average: 10-15 bits per value
- Raw: 64 bits
- Compression ratio: 4-6x

Counter metric (always increasing):
- XORs change in lower bits
- Average: 20-30 bits per value
- Compression ratio: 2-3x
```

## 🎯 Combined Result

```
Typical Prometheus metrics:
- Timestamp: 1-2 bits average
- Value: 10-15 bits average
- Total: 12-17 bits per sample

Raw: 128 bits (16 bytes)
Compressed: ~14 bits (1.75 bytes)

Compression ratio: ~9x

Paper claims: 1.37 bytes per data point at Facebook scale
```

---

# Part 2: TSDB Storage Architecture

## 📦 Prometheus Local Storage

### Block Structure
```
data/
├── 01BKGV7JC0RY8A6MACW02A2PJD/  # 2-hour block (ULID)
│   ├── meta.json                # Block metadata
│   ├── chunks/
│   │   ├── 000001                # Compressed chunks
│   │   └── 000002
│   ├── index                     # Inverted index
│   └── tombstones                # Deletion markers
├── 01BKGV7JBM69T2G1KAMBER3VE/   # Another block
├── chunks_head/                  # In-memory head block
│   ├── 000001
│   └── 000002
├── wal/                          # Write-ahead log
│   ├── 00000000
│   └── 00000001
└── lock
```

### Write Path
```
1. Sample arrives (scrape or remote_write)
2. Append to Head block (in-memory)
3. Write to WAL (crash recovery)
4. Every 2 hours: Compact head → persistent block
5. Background: Merge small blocks into larger ones

Head Block:
- In-memory, mmap'd chunks
- WAL for durability
- Range: NOW - 2 hours (configurable)

Persistent Block:
- Immutable
- Compressed chunks (Gorilla)
- Inverted index for labels
```

### Compaction
```
Level 0: 2-hour blocks (from head)
         ↓ Compact when 3+ blocks
Level 1: 6-hour blocks
         ↓ Compact when 3+ blocks  
Level 2: 18-hour blocks
         ↓ ...
Level N: Up to retention period

Benefits:
- Fewer files to query
- Better compression
- Merge overlapping data
- Apply tombstones (actually delete)
```

## 🏷️ Index Structure (Inverted Index)

### The Challenge
```
Query: rate(http_requests_total{job="api", method="GET"}[5m])

Need to find all series matching:
- __name__ = "http_requests_total"
- job = "api"
- method = "GET"
```

### Index Format
```
Posting List (label → series IDs):

__name__="http_requests_total" → [1, 5, 12, 47, 89, ...]
job="api"                      → [1, 2, 5, 12, 35, ...]
job="worker"                   → [3, 4, 47, 89, ...]
method="GET"                   → [1, 12, 35, 47, ...]
method="POST"                  → [2, 5, 89, ...]

Query resolution:
  Intersect([1,5,12,47,89], [1,2,5,12,35], [1,12,35,47])
  = [1, 12]

Series ID → (chunk references, label set)
```

### PromQL Execution
```
rate(http_requests_total{job="api"}[5m])

1. Label matching: Find posting list for job="api", __name__="http_requests_total"
2. Intersect lists: Get series IDs [1, 5, 12, ...]
3. Time filtering: For each series, find chunks overlapping [now-5m, now]
4. Chunk decoding: Decompress Gorilla-encoded samples
5. Function: Apply rate() calculation
6. Return results
```

---

# Part 3: Cardinality Management

## 💥 The Cardinality Bomb

```python
# Innocent-looking metric
http_requests_total{
    method="GET",
    path="/users/12345",        # DANGER: User ID in label
    status="200",
    instance="web-1"
}

# If 1M users, this creates 1M series per method × status × instance
# 1M × 3 methods × 5 statuses × 10 instances = 150M series

# Prometheus meltdown:
# - 150M series × ~200 bytes/series = 30GB RAM for index
# - Head compaction: OOM
# - Queries timeout
```

## 📏 Cardinality Limits

### Prometheus Configuration
```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  
  # Limit samples per scrape (default: 0 = unlimited)
  sample_limit: 10000
  
  # Limit labels per series
  label_limit: 30
  label_name_length_limit: 128
  label_value_length_limit: 512

# Per-scrape limits
scrape_configs:
  - job_name: 'high_cardinality_app'
    sample_limit: 50000  # Override global
    
    # Relabeling to drop bad labels
    metric_relabel_configs:
      - source_labels: [path]
        regex: '/users/[0-9]+'
        action: drop  # Don't store user-specific paths
```

### VictoriaMetrics Cardinality Limiter
```yaml
# Limit unique time series per tenant
-search.maxUniqueTimeseries=1000000

# Limit series returned per query
-search.maxSeries=100000

# Cardinality explorer
/api/v1/status/tsdb  # Shows top series by cardinality
```

## 🔍 Cardinality Debugging

```promql
# Count total active series
prometheus_tsdb_head_series

# Series by job
count by (job) ({__name__=~".+"})

# Top 10 metrics by cardinality
topk(10, count by (__name__) ({__name__=~".+"}))

# Find high-cardinality labels
count by (path) (http_requests_total)
# If this returns 1M+ results, "path" is the problem
```

### Script: Find Cardinality Offenders
```python
import requests

def find_high_cardinality(prometheus_url, threshold=10000):
    # Get all label names
    labels = requests.get(f"{prometheus_url}/api/v1/labels").json()["data"]
    
    for label in labels:
        # Count unique values per label
        values = requests.get(
            f"{prometheus_url}/api/v1/label/{label}/values"
        ).json()["data"]
        
        if len(values) > threshold:
            print(f"⚠️  {label}: {len(values)} unique values")
            
            # Find which metrics use this label
            series = requests.get(
                f"{prometheus_url}/api/v1/series",
                params={"match[]": f'{{{label}=~".+"}}'}
            ).json()["data"][:5]
            
            for s in series:
                print(f"   Example: {s['__name__']}")
```

---

# Part 4: Production Patterns

## 📉 Downsampling (Rollups)

```
Problem: Keep 1-second data for 1 year = 31M samples/metric
Solution: Aggregate older data

Retention policy:
- Raw (1s):  7 days
- 1m avg:   30 days
- 1h avg:   1 year
- 1d avg:   Forever

Storage savings:
- Raw: 31M × 7 = 217M samples/metric/year
- With rollups: 217M + 44K + 8.7K + 365 ≈ 217M (but 1 year queryable)
```

### Thanos/Cortex Compactor
```yaml
# Thanos compactor downsampling
thanos:
  compactor:
    retention-resolution-raw: 7d
    retention-resolution-5m: 30d
    retention-resolution-1h: 365d
    
    # Compaction
    consistency-delay: 30m  # Wait for all replicas
    block-sync-concurrency: 20
```

### Recording Rules (Pre-aggregation)
```yaml
# prometheus.rules.yml
groups:
  - name: aggregations
    interval: 1m
    rules:
      # Pre-aggregate high-cardinality metrics
      - record: job:http_requests:rate5m
        expr: sum by (job, method, status) (rate(http_requests_total[5m]))
      
      # Histogram quantiles (expensive to compute on-demand)
      - record: job:http_duration:p99
        expr: histogram_quantile(0.99, sum by (job, le) (rate(http_request_duration_seconds_bucket[5m])))
```

## 🌍 Remote Write/Read (Long-term Storage)

```
             ┌─────────────┐
             │ Prometheus  │
             │ (2h local)  │
             └──────┬──────┘
                    │ remote_write
          ┌─────────┼─────────┐
          │         │         │
    ┌─────▼────┐ ┌──▼───┐ ┌───▼────┐
    │ Cortex   │ │Thanos│ │Victoria│
    │ (S3)     │ │ (S3) │ │Metrics │
    └──────────┘ └──────┘ └────────┘
```

### Remote Write Configuration
```yaml
# prometheus.yml
remote_write:
  - url: "https://cortex.example.com/api/v1/push"
    
    # Batch settings
    queue_config:
      capacity: 10000
      max_shards: 200
      max_samples_per_send: 1000
      batch_send_deadline: 5s
    
    # Retry on failure
    write_relabel_configs:
      - source_labels: [__name__]
        regex: 'go_.*'
        action: drop  # Don't send Go runtime metrics
```

## 🏗️ TSDB Comparison (Production)

| Feature | Prometheus | VictoriaMetrics | Thanos | Cortex |
| :--- | :--- | :--- | :--- | :--- |
| **Storage** | Local disk | Local/Remote | S3/GCS | S3/GCS |
| **HA** | None (use Thanos) | Cluster mode | Sidecar + Store | Ingest replicas |
| **Cardinality Limit** | OOM | 100M+ series | Dependent on Prometheus | Configurable |
| **Retention** | Days-weeks | Unlimited | Unlimited | Unlimited |
| **Query** | PromQL | MetricsQL | PromQL | PromQL |
| **Best For** | Single-node | High cardinality | Easy HA for Prometheus | Multi-tenant SaaS |

---

# Part 5: Production DDL

## InfluxDB Schema (Line Protocol)
```
# Measurement: cpu
# Tags: host, region (indexed, low cardinality)
# Fields: usage_user, usage_system (not indexed)
# Timestamp: nanoseconds

cpu,host=server01,region=us-west usage_user=23.5,usage_system=5.2 1704067200000000000
cpu,host=server02,region=us-east usage_user=45.1,usage_system=12.3 1704067200000000000
```

### Retention Policies
```sql
-- Create retention policy (auto-delete after 7 days)
CREATE RETENTION POLICY "7d" ON "metrics" DURATION 7d REPLICATION 1 DEFAULT;

-- Create downsampled retention
CREATE RETENTION POLICY "30d_5m" ON "metrics" DURATION 30d REPLICATION 1;

-- Continuous query for downsampling
CREATE CONTINUOUS QUERY "cq_5m" ON "metrics"
BEGIN
    SELECT mean(*) INTO "30d_5m"."cpu" FROM "cpu" GROUP BY time(5m), *
END;
```

## TimescaleDB Schema (PostgreSQL)
```sql
-- Hypertable (auto-partitioned by time)
CREATE TABLE metrics (
    time TIMESTAMPTZ NOT NULL,
    metric_name TEXT NOT NULL,
    tags JSONB,
    value DOUBLE PRECISION
);

SELECT create_hypertable('metrics', 'time', 
    chunk_time_interval => INTERVAL '1 day'
);

-- Compression (after 7 days)
ALTER TABLE metrics SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'metric_name',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('metrics', INTERVAL '7 days');

-- Retention (delete after 30 days)
SELECT add_retention_policy('metrics', INTERVAL '30 days');

-- Continuous aggregate (5-minute rollup)
CREATE MATERIALIZED VIEW metrics_5m
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('5 minutes', time) AS bucket,
    metric_name,
    tags,
    avg(value) AS avg_value,
    max(value) AS max_value,
    min(value) AS min_value
FROM metrics
GROUP BY bucket, metric_name, tags;

SELECT add_continuous_aggregate_policy('metrics_5m',
    start_offset => INTERVAL '1 hour',
    end_offset => INTERVAL '5 minutes',
    schedule_interval => INTERVAL '5 minutes'
);
```

## QuestDB Schema (SQL)
```sql
-- Partitioned by day, indexes on symbol columns
CREATE TABLE metrics (
    timestamp TIMESTAMP,
    metric_name SYMBOL capacity 10000 CACHE INDEX,
    host SYMBOL capacity 1000 CACHE INDEX,
    region SYMBOL capacity 100 CACHE INDEX,
    value DOUBLE
) TIMESTAMP(timestamp) PARTITION BY DAY;

-- Insert (optimized for append)
INSERT INTO metrics VALUES (systimestamp(), 'cpu_usage', 'server01', 'us-west', 45.2);

-- Query (parallel scan)
SELECT 
    timestamp,
    avg(value) 
FROM metrics
WHERE metric_name = 'cpu_usage'
  AND timestamp > dateadd('d', -1, systimestamp())
SAMPLE BY 1m;
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Cardinality monitored | Alert if series > 1M |
| 2 | High-cardinality labels identified | No user IDs, request IDs in labels |
| 3 | Retention policies configured | Raw: 7d, Rollup: 30d, Cold: 1y |
| 4 | Recording rules for expensive queries | Pre-aggregate histograms |
| 5 | Remote write configured | Long-term storage in S3/GCS |
| 6 | Compaction tuned | No overlapping blocks |
| 7 | Head block memory sized | ~200 bytes per series |
| 8 | Gorilla understood by team | Paper review session |

---

## 🔗 Related Documents
*   [NoSQL Architecture](./nosql-architecture-guide.md) — LSM compaction patterns.
*   [Replication & Consistency](./replication-consistency-guide.md) — Multi-zone TSDB.
*   [Database Scaling](./database-scaling-guide.md) — TSDB federation.
