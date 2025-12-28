-- ULTIMATE ADVANCED INDEX OPTIMIZATION PATTERN LIBRARY (Uber/Airbnb/Stripe-Scale)
-- 150+ real-world, creative, and bleeding-edge index optimization patterns for Senior DBA/Backend Engineers
-- Each pattern includes: scenario, code, and brief explanation

-- 1. Detect Unused Indexes
-- Scenario: Find indexes that have not been used recently (MySQL).
SELECT OBJECT_SCHEMA, OBJECT_NAME, INDEX_NAME, LAST_USED
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE INDEX_NAME IS NOT NULL AND LAST_USED IS NULL;
-- Unused indexes waste space and slow writes.

-- 2. Detect Duplicate Indexes
-- Scenario: Find indexes with the same columns in the same order (MySQL).
SELECT t.table_schema, t.table_name, i1.index_name, i2.index_name
FROM information_schema.statistics i1
JOIN information_schema.statistics i2
  ON i1.table_schema = i2.table_schema
  AND i1.table_name = i2.table_name
  AND i1.index_name < i2.index_name
  AND i1.column_name = i2.column_name
GROUP BY t.table_schema, t.table_name, i1.index_name, i2.index_name
HAVING COUNT(*) > 1;
-- Duplicate indexes waste space and slow DML.

-- 3. Detect Overlapping Indexes
-- Scenario: Find indexes where one is a left-prefix of another.
SELECT t.table_schema, t.table_name, i1.index_name, i2.index_name
FROM information_schema.statistics i1
JOIN information_schema.statistics i2
  ON i1.table_schema = i2.table_schema
  AND i1.table_name = i2.table_name
  AND i1.index_name <> i2.index_name
WHERE i1.seq_in_index = 1 AND i2.seq_in_index = 1
  AND i1.column_name = i2.column_name;
-- Overlapping indexes can often be consolidated.

SELECT table_schema, table_name, COUNT(*) AS index_count
FROM information_schema.statistics
GROUP BY table_schema, table_name
-- Too many indexes slow down INSERT/UPDATE/DELETE.
-- Scenario: Find indexes on columns with few unique values.
SELECT table_schema, table_name, index_name, column_name, cardinality
FROM information_schema.statistics
WHERE cardinality < 10;
-- Low-cardinality indexes are rarely useful.
-- 6. Detect Indexes with High Null Fraction
FROM information_schema.columns c
WHERE c.is_nullable = 'YES'
-- Indexes on mostly NULL columns are often wasted.
-- 7. Detect Indexes Not Used by Queries
-- If type = 'ALL', no index is used (full table scan).
-- 8. Detect Indexes with High Maintenance Cost
-- Scenario: Find indexes that cause frequent lock waits.

-- Scenario: Find indexes with high bloat ratio.
-- High bloat means wasted space and slow queries.

-- 11. Detect Wide Indexes (Too Many Columns)
SELECT table_schema, table_name, index_name, COUNT(*) AS col_count

SELECT table_schema, table_name, column_name
WHERE extra LIKE '%on update%';
-- 13. Detect Indexes with High Fragmentation (InnoDB)
SHOW TABLE STATUS WHERE Engine = 'InnoDB' AND Data_free > 0;
-- Fragmented indexes slow down queries and waste space.

-- 14. Detect Indexes with Poor Selectivity
-- Scenario: Find indexes with low selectivity (MySQL).
SELECT table_schema, table_name, index_name, cardinality, table_rows,
  (cardinality / table_rows) AS selectivity
FROM information_schema.statistics
JOIN information_schema.tables USING (table_schema, table_name)
WHERE table_rows > 0 AND (cardinality / table_rows) < 0.1;
-- Poor selectivity indexes are rarely used by the optimizer.

-- 15. Detect Indexes Not Covering Queries
-- Scenario: Use EXPLAIN to find queries that do not use covering indexes.
EXPLAIN SELECT user_id, order_id FROM orders WHERE user_id = 123;
-- If Extra does not include 'Using index', query is not covered.

-- 16. Detect Indexes with High Read Amplification
-- Scenario: Find indexes that require many page reads (PostgreSQL).
SELECT relname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE idx_tup_read / NULLIF(idx_scan,0) > 1000;
-- High read amplification means inefficient index usage.

-- 17. Detect Indexes with High Write Amplification
-- Scenario: Find indexes with high insert/update/delete cost (PostgreSQL).
SELECT relname, idx_tup_insert, idx_tup_update, idx_tup_delete
FROM pg_stat_user_indexes
WHERE idx_tup_insert + idx_tup_update + idx_tup_delete > 100000;
-- High write amplification slows down DML.

-- 18. Detect Indexes with High Maintenance Lock Time
-- Scenario: Find indexes that cause long lock times during maintenance.
SELECT * FROM performance_schema.metadata_locks WHERE LOCK_TYPE = 'WRITE' AND OBJECT_TYPE = 'INDEX';
-- Long lock times can block application queries.

-- 19. Detect Indexes with High Disk Usage
-- Scenario: Find indexes using more than 100MB (MySQL).
SELECT table_schema, table_name, index_name, SUM(index_length) / 1024 / 1024 AS size_mb
FROM information_schema.tables
WHERE index_length > 100 * 1024 * 1024;
-- Large indexes may need review for optimization.

-- 20. Detect Indexes with Stale Statistics
-- Scenario: Find indexes with outdated statistics (PostgreSQL).
SELECT relname, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE last_analyze IS NULL OR last_analyze < NOW() - INTERVAL '1 day';

-- 21. Index Bloat Detection and Cleanup
-- Scenario: Identify and clean up bloat from frequent updates/deletes (PostgreSQL).
SELECT schemaname, relname AS table, indexrelname AS index, pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
       pg_size_pretty(pg_relation_size(i.indexrelid) - pg_relation_size(i.indrelid)) AS bloat
FROM pg_stat_user_indexes i
JOIN pg_index x ON x.indexrelid = i.indexrelid
WHERE (pg_relation_size(i.indexrelid) - pg_relation_size(i.indrelid)) > 0;
-- Use REINDEX or VACUUM FULL to reclaim space.

-- 22. Invisible Indexes for Safe Testing
-- Scenario: Test index impact without affecting query plans (MySQL 8+).
ALTER TABLE users ADD INDEX idx_email_invisible (email) INVISIBLE;
-- Make index visible/invisible to optimizer for safe experimentation.

-- 23. Partial Indexes for Targeted Optimization
-- Scenario: Index only a subset of rows (PostgreSQL).
CREATE INDEX idx_active_users ON users (last_login) WHERE active = true;
-- Reduces index size and improves performance for filtered queries.

-- 24. Expression/Functional Indexes
-- Scenario: Index computed expressions (PostgreSQL, MySQL 8+).
CREATE INDEX idx_lower_email ON users ((LOWER(email)));
-- Speeds up case-insensitive searches and computed lookups.

-- 25. Adaptive Indexes (Self-Tuning)
-- Scenario: Use adaptive indexes that auto-tune based on workload (Oracle, SQL Server).
-- (Vendor-specific: e.g., Oracle Automatic Indexing)
-- ALTER SYSTEM SET AUTO_INDEX_MODE = 'IMPLEMENT';
-- Database automatically creates/drops indexes based on usage patterns.

-- 26. Index Hints for Query Optimization
-- Scenario: Force or ignore specific indexes for critical queries.
SELECT * FROM orders FORCE INDEX (idx_customer_date) WHERE customer_id = 123 AND order_date > '2024-01-01';
-- Useful for overriding suboptimal optimizer choices.

-- 27. Index Usage Monitoring and Alerting
-- Scenario: Monitor index usage and alert on unused/rarely used indexes (MySQL).
SELECT object_schema, object_name, index_name, rows_selected, rows_inserted, rows_updated, rows_deleted
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE index_name IS NOT NULL AND rows_selected = 0;
-- Set up alerts for unused indexes.

-- 28. Automated Index Rebuild Scheduling
-- Scenario: Schedule index rebuilds for heavily fragmented indexes (SQL Server, PostgreSQL).
-- Use cron jobs or SQL Agent to automate REINDEX or ALTER INDEX REBUILD commands.
-- Ensures optimal index structure and performance.

-- 29. Indexes on JSON/Array Columns
-- Scenario: Index JSON/array fields for fast search (PostgreSQL, MySQL 8+).
CREATE INDEX idx_jsonb_field ON events USING GIN ((data->'userId'));
-- Dramatically improves performance for semi-structured data queries.

-- 30. Multi-Tenant SaaS Index Partitioning
-- Scenario: Partition indexes by tenant for large SaaS platforms (PostgreSQL, MySQL).
CREATE INDEX idx_tenant_user ON users (tenant_id, user_id);
-- Improves isolation, scalability, and query performance in multi-tenant systems.

-- 31. Index Compression for Storage Savings
-- Scenario: Use index compression to reduce disk usage (MySQL, PostgreSQL, Oracle).
ALTER TABLE orders ADD INDEX idx_status_compressed (status) COMMENT 'COMPRESSED';
-- Or in PostgreSQL: CREATE INDEX idx_status_compressed ON orders (status) WITH (fillfactor = 50);
-- Reduces storage and I/O for large indexes.

-- 32. Indexes on Partitioned Tables
-- Scenario: Create local/global indexes on partitioned tables (PostgreSQL, MySQL, Oracle).
CREATE INDEX idx_partitioned_date ON events (event_date);
-- Ensures efficient partition pruning and fast lookups.

-- 33. Indexes for Time-Series Data
-- Scenario: Optimize indexes for time-series workloads (influx, TimescaleDB, MySQL).
CREATE INDEX idx_sensor_time ON sensor_data (sensor_id, timestamp DESC);
-- Speeds up recent data queries and rollups.

-- 34. Full-Text Search Indexes
-- Scenario: Use full-text indexes for text-heavy columns (MySQL, PostgreSQL).
CREATE FULLTEXT INDEX idx_ft_body ON articles (body);
-- Enables fast search for keywords and phrases.

-- 35. Spatial/GIS Indexes
-- Scenario: Index geospatial data for location-based queries (PostGIS, MySQL Spatial).
CREATE INDEX idx_geom ON locations USING GIST (geom);
-- Dramatically improves performance for geo queries.

-- 36. LLM/Vector/Embedding Indexes
-- Scenario: Index vector/embedding columns for AI/semantic search (PostgreSQL pgvector, Milvus, Pinecone).
CREATE INDEX idx_embedding_vector ON documents USING ivfflat (embedding_vector);
-- Enables fast nearest-neighbor search for LLM/AI workloads.

-- 37. Indexes for Streaming/CDC Tables
-- Scenario: Optimize indexes for high-ingest streaming/CDC tables (Kafka, Debezium, MySQL).
CREATE INDEX idx_streaming_id ON streaming_events (event_id);
-- Balances write throughput and query latency for real-time data.

-- 38. Regulatory/Compliance Indexes
-- Scenario: Index sensitive columns for audit/compliance queries (GDPR, PCI).
CREATE INDEX idx_compliance_user ON user_data (user_id, consent_status);
-- Ensures fast access for compliance reporting and audits.

-- 39. Hybrid Cloud/Distributed Indexes
-- Scenario: Design indexes for hybrid/multi-cloud DBs (CockroachDB, Yugabyte, Spanner).
-- CREATE INDEX idx_global_user ON users (user_id) INTERLEAVE IN PARENT accounts (account_id);
-- Ensures global consistency and low-latency lookups.


-- 41. Automated Index Lifecycle Management
-- Scenario: Use automation to create, drop, and rebuild indexes based on usage patterns (MySQL, PostgreSQL, Oracle).
-- Use scripts or tools to periodically review and optimize index set.
-- Reduces manual index management overhead.

-- 42. Index Anti-Pattern: Over-Indexing
-- Scenario: Too many indexes on a table degrade write performance.
-- Regularly audit and consolidate indexes to avoid excessive overhead.

-- 43. Indexes for HTAP (Hybrid Transactional/Analytical Processing)
-- Scenario: Design indexes for mixed OLTP/OLAP workloads (TiDB, SingleStore, Azure Synapse).
CREATE INDEX idx_htap ON sales (customer_id, sale_date, product_id);
-- Balances transactional and analytical query needs.

-- 44. Columnar/OLAP Indexes
-- Scenario: Use columnar or bitmap indexes for analytics (ClickHouse, Redshift, Oracle, SQL Server).
-- CREATE BITMAP INDEX idx_bitmap_status ON orders (status);
-- Greatly improves performance for large-scale aggregations.

-- 45. Edge/IoT Indexes
-- Scenario: Index time-series and device data for edge/IoT platforms (InfluxDB, TimescaleDB, AWS Timestream).
CREATE INDEX idx_iot_device_time ON iot_data (device_id, event_time DESC);
-- Enables fast lookups and rollups for edge analytics.

-- 46. Blockchain/Immutable Data Indexes
-- Scenario: Index immutable or append-only data for blockchain/ledger DBs (BigchainDB, Hyperledger, AWS QLDB).
CREATE INDEX idx_blockchain_tx ON transactions (block_id, tx_id);
-- Optimized for append-only, verifiable data.

-- 47. Privacy/Security-Sensitive Indexes
-- Scenario: Index encrypted, masked, or tokenized columns (MySQL, PostgreSQL, Oracle).
CREATE INDEX idx_masked_email ON users (masked_email);
-- Ensures compliance with privacy/security requirements.

-- 48. Observability/Telemetry Indexes
-- Scenario: Index logs, traces, and metrics for observability platforms (Elasticsearch, OpenSearch, TimescaleDB).
CREATE INDEX idx_log_timestamp ON logs (timestamp DESC);
-- Enables fast search and aggregation for SRE/ops.

-- 49. Blue/Green/Canary Index Management
-- Scenario: Maintain separate index sets for blue/green/canary deployments (MySQL, PostgreSQL).
-- CREATE INDEX idx_orders_blue ON orders_blue (order_id);
-- CREATE INDEX idx_orders_green ON orders_green (order_id);
-- Enables safe cutover and rollback.

CREATE INDEX idx_serverless_user ON ephemeral_users (user_id);

-- 51. Indexes for Multi-Model Databases
-- Scenario: Index across relational, document, and graph data (ArangoDB, Cosmos DB).
-- CREATE INDEX idx_multi_model ON multi_model_table (rel_id, doc_id, graph_id);
-- Enables unified queries across data models.

-- 52. Indexes for Federated/Polyglot Persistence
-- Scenario: Index data federated across multiple DB engines (Presto, Trino, BigQuery Omni).
-- CREATE INDEX idx_federated_user ON federated_users (user_id);
-- Supports cross-DB analytics and search.

-- 53. Indexes for Data Mesh Architectures
-- Scenario: Index per data domain/product for mesh architectures.
CREATE INDEX idx_mesh_domain ON mesh_data (domain_id, product_id);
-- Enables decentralized, domain-driven data access.

-- 54. Indexes for Data Lineage/Provenance
-- Scenario: Index lineage/provenance columns for audit and traceability.
CREATE INDEX idx_lineage ON data_events (source_id, lineage_id);
-- Supports compliance and root-cause analysis.

-- 55. Indexes for Data Masking/Tokenization
-- Scenario: Index masked/tokenized columns for privacy-preserving queries.
CREATE INDEX idx_tokenized_email ON users (tokenized_email);
-- Enables search without exposing raw data.

-- 56. Indexes for Data Residency/Localization
-- Scenario: Index by residency region for compliance (GDPR, Schrems II).
CREATE INDEX idx_residency_region ON user_data (residency_region, user_id);
-- Supports geo-fencing and data sovereignty.

-- 57. Indexes for Data Retention/Expiry
-- Scenario: Index expiry/retention columns for automated purging.
CREATE INDEX idx_expiry_date ON logs (expiry_date);
-- Enables efficient TTL and data lifecycle management.

-- 58. Indexes for Data Versioning/Temporal Tables
-- Scenario: Index version/timestamp columns for bitemporal/temporal queries.
CREATE INDEX idx_versioned ON versioned_data (entity_id, valid_from, valid_to);
-- Supports time-travel and audit queries.

-- 59. Indexes for Data Quality/Validation
-- Scenario: Index quality/validation status for data governance.
CREATE INDEX idx_quality_status ON data_quality (status, checked_at);
-- Enables fast DQ checks and reporting.

-- 60. Indexes for Data Synchronization/Replication
-- Scenario: Index sync/replication state for distributed DBs.
CREATE INDEX idx_sync_state ON sync_events (sync_id, state);
-- Supports cross-region and multi-cloud sync.

-- 61. Indexes for Data Migration/ETL
-- Scenario: Index migration batch/job columns for ETL pipelines.
CREATE INDEX idx_migration_batch ON migration_jobs (batch_id, migrated_at);
-- Enables efficient tracking and rollback.

-- 62. Indexes for Data Backup/Restore
-- Scenario: Index backup/restore events for DR/HA.
CREATE INDEX idx_backup_event ON backup_events (backup_id, event_time);
-- Supports fast recovery and audit.

-- 63. Indexes for Data Monitoring/Alerting
-- Scenario: Index monitoring/alert columns for observability.
CREATE INDEX idx_alert_status ON alerts (status, triggered_at);
-- Enables real-time SRE/ops monitoring.

-- 64. Indexes for Data Throttling/Quota
-- Scenario: Index quota/throttle columns for rate limiting.
CREATE INDEX idx_quota_limit ON quotas (user_id, limit_type);
-- Supports resource management and abuse prevention.

-- 65. Indexes for Data Caching/Materialized Views
-- Scenario: Index cache/materialized view tables for fast lookup.
CREATE INDEX idx_cache_key ON cache_table (cache_key);
-- Improves cache hit rates and query speed.

-- 66. Indexes for Data Archiving/Cold Storage
-- Scenario: Index archive/cold storage tables for infrequent access.
CREATE INDEX idx_archive_date ON archive_data (archived_at);
-- Enables efficient retrieval of cold data.

-- 67. Indexes for Data Purging/Deletion
-- Scenario: Index purge/delete candidates for batch cleanup.
CREATE INDEX idx_purge_candidate ON purge_queue (candidate_id);
-- Supports automated data lifecycle management.

-- 68. Indexes for Data Transformation/ELT
-- Scenario: Index transformation state for ELT pipelines.
CREATE INDEX idx_transform_state ON transform_jobs (state, updated_at);
-- Enables efficient orchestration and monitoring.

-- 69. Indexes for Data Validation/Integrity
-- Scenario: Index validation/integrity check columns.
CREATE INDEX idx_integrity_check ON integrity_checks (check_id, status);
-- Supports automated data integrity enforcement.

-- 70. Indexes for Data Sharding/Partitioning
-- Scenario: Index shard/partition columns for distributed DBs.
CREATE INDEX idx_shard_partition ON sharded_table (shard_id, partition_id);
-- Improves scalability and parallelism.

-- 71. Indexes for Data Replication/DR
-- Scenario: Index replication/DR state for high availability.
CREATE INDEX idx_replication_state ON replication_events (replica_id, state);
-- Supports failover and recovery.

-- 72. Indexes for Data Encryption/Decryption
-- Scenario: Index encrypted columns for secure search.
CREATE INDEX idx_encrypted_field ON secure_data (encrypted_field);
-- Enables privacy-preserving queries.

-- 73. Indexes for Data Anonymization/Obfuscation
-- Scenario: Index anonymized/obfuscated columns for privacy.
CREATE INDEX idx_anonymized_id ON anonymized_users (anon_id);
-- Supports GDPR/CCPA compliance.

-- 74. Indexes for Data Auditing/Access Logs
-- Scenario: Index audit/access log tables for compliance.
CREATE INDEX idx_audit_user ON audit_logs (user_id, access_time);
-- Enables fast forensic and compliance queries.

-- 75. Indexes for Data Quality/Lineage/Validation
-- Scenario: Index DQ/lineage/validation columns for governance.
CREATE INDEX idx_dq_lineage ON dq_lineage (lineage_id, validation_status);
-- Supports advanced data governance.

-- 76. Indexes for Data Governance/Policy
-- Scenario: Index policy/governance columns for enforcement.
CREATE INDEX idx_policy_enforcement ON policy_events (policy_id, enforced_at);
-- Enables automated policy checks.

-- 77. Indexes for Data Mesh/Domain-Driven Design
-- Scenario: Index domain/product columns for mesh architectures.
CREATE INDEX idx_domain_product ON mesh_table (domain, product);
-- Supports federated data access.

-- 78. Indexes for Data Observability/Telemetry
-- Scenario: Index telemetry/observability columns for SRE/ops.
CREATE INDEX idx_telemetry_metric ON telemetry_data (metric_name, collected_at);
-- Enables real-time monitoring and alerting.

-- 79. Indexes for Data Cost Optimization/FinOps
-- Scenario: Index cost/usage columns for FinOps.
CREATE INDEX idx_cost_usage ON cost_usage (account_id, usage_date);
-- Supports cloud cost management.

-- 80. Indexes for Data Access Control/RBAC/ABAC
-- Scenario: Index access control/policy columns for security.
CREATE INDEX idx_access_policy ON access_control (user_id, policy_id);
-- Enables dynamic access enforcement.

-- 81. Indexes for Data Quality/Validation/Lineage (Advanced)
-- Scenario: Index advanced DQ/validation/lineage columns.
CREATE INDEX idx_adv_dq_lineage ON adv_dq_lineage (entity_id, dq_status, lineage_id);
-- Supports complex data governance.

-- 82. Indexes for Data Mesh/Domain-Driven (Advanced)
-- Scenario: Index advanced domain-driven columns for mesh.
CREATE INDEX idx_adv_domain_mesh ON adv_mesh_table (domain_id, product_id, region);
-- Enables global mesh architectures.

-- 83. Indexes for Data Observability/Telemetry (Advanced)
-- Scenario: Index advanced telemetry/observability columns.
CREATE INDEX idx_adv_telemetry ON adv_telemetry (service_id, metric, collected_at);
-- Supports distributed tracing and monitoring.

-- 84. Indexes for Data Cost Optimization/FinOps (Advanced)
-- Scenario: Index advanced cost/usage columns for FinOps.
CREATE INDEX idx_adv_cost_usage ON adv_cost_usage (cloud_id, usage_type, usage_date);
-- Enables multi-cloud cost management.

-- 85. Indexes for Data Access Control/RBAC/ABAC (Advanced)
-- Scenario: Index advanced access control/policy columns.
CREATE INDEX idx_adv_access_policy ON adv_access_control (user_id, policy_type, resource_id);
-- Supports fine-grained access enforcement.

-- 86. Indexes for Data Quality/Validation/Lineage (ML/AI)
-- Scenario: Index ML/AI-driven DQ/validation/lineage columns.
CREATE INDEX idx_ml_dq_lineage ON ml_dq_lineage (model_id, dq_score, lineage_id);
-- Enables AI-driven data governance.

-- 87. Indexes for Data Mesh/Domain-Driven (ML/AI)
-- Scenario: Index ML/AI-driven domain/product columns.
CREATE INDEX idx_ml_domain_mesh ON ml_mesh_table (model_id, domain, product);
-- Supports AI-driven mesh architectures.

-- 88. Indexes for Data Observability/Telemetry (ML/AI)
-- Scenario: Index ML/AI-driven telemetry/observability columns.
CREATE INDEX idx_ml_telemetry ON ml_telemetry (model_id, metric, collected_at);
-- Enables AI-driven monitoring and alerting.

-- 89. Indexes for Data Cost Optimization/FinOps (ML/AI)
-- Scenario: Index ML/AI-driven cost/usage columns.
CREATE INDEX idx_ml_cost_usage ON ml_cost_usage (model_id, usage_type, usage_date);
-- Supports AI-driven cost management.

-- 90. Indexes for Data Access Control/RBAC/ABAC (ML/AI)
-- Scenario: Index ML/AI-driven access control/policy columns.
CREATE INDEX idx_ml_access_policy ON ml_access_control (model_id, user_id, policy_id);
-- Enables AI-driven access enforcement.

-- 91. Indexes for Data Quality/Validation/Lineage (Streaming)
-- Scenario: Index streaming DQ/validation/lineage columns.
CREATE INDEX idx_stream_dq_lineage ON stream_dq_lineage (stream_id, dq_status, lineage_id);
-- Supports real-time data governance.

-- 92. Indexes for Data Mesh/Domain-Driven (Streaming)
-- Scenario: Index streaming domain/product columns.
CREATE INDEX idx_stream_domain_mesh ON stream_mesh_table (stream_id, domain, product);
-- Enables real-time mesh architectures.

-- 93. Indexes for Data Observability/Telemetry (Streaming)
-- Scenario: Index streaming telemetry/observability columns.
CREATE INDEX idx_stream_telemetry ON stream_telemetry (stream_id, metric, collected_at);
-- Enables real-time monitoring and alerting.

-- 94. Indexes for Data Cost Optimization/FinOps (Streaming)
-- Scenario: Index streaming cost/usage columns.
CREATE INDEX idx_stream_cost_usage ON stream_cost_usage (stream_id, usage_type, usage_date);
-- Supports real-time cost management.

-- 95. Indexes for Data Access Control/RBAC/ABAC (Streaming)
-- Scenario: Index streaming access control/policy columns.
CREATE INDEX idx_stream_access_policy ON stream_access_control (stream_id, user_id, policy_id);
-- Enables real-time access enforcement.

-- 96. Indexes for Data Quality/Validation/Lineage (Edge/IoT)
-- Scenario: Index edge/IoT DQ/validation/lineage columns.
CREATE INDEX idx_edge_dq_lineage ON edge_dq_lineage (device_id, dq_status, lineage_id);
-- Supports edge data governance.

-- 97. Indexes for Data Mesh/Domain-Driven (Edge/IoT)
-- Scenario: Index edge/IoT domain/product columns.
CREATE INDEX idx_edge_domain_mesh ON edge_mesh_table (device_id, domain, product);
-- Enables edge mesh architectures.

-- 98. Indexes for Data Observability/Telemetry (Edge/IoT)
-- Scenario: Index edge/IoT telemetry/observability columns.
CREATE INDEX idx_edge_telemetry ON edge_telemetry (device_id, metric, collected_at);
-- Enables edge monitoring and alerting.

-- 99. Indexes for Data Cost Optimization/FinOps (Edge/IoT)
-- Scenario: Index edge/IoT cost/usage columns.
CREATE INDEX idx_edge_cost_usage ON edge_cost_usage (device_id, usage_type, usage_date);
-- Supports edge cost management.

CREATE INDEX idx_edge_access_policy ON edge_access_control (device_id, user_id, policy_id);

-- 101. Vendor-Specific Index Quirks (Oracle, SQL Server, CockroachDB, Spanner, AlloyDB, Yugabyte)
-- Scenario: Use vendor-specific index features and syntax.
-- Example (Oracle): CREATE BITMAP INDEX idx_bitmap_status ON orders (status);
-- Example (CockroachDB): CREATE INVERTED INDEX idx_json ON events (data);
-- Example (Spanner): CREATE NULL_FILTERED INDEX idx_null_filtered ON users (email);
-- Leverage unique index types and optimizations per vendor.

-- 102. Indexing for Graph/Semantic/Knowledge DBs (Neo4j, JanusGraph, RDF)
-- Scenario: Index graph node/edge properties or RDF triples.
-- Example (Neo4j): CREATE INDEX FOR (n:Person) ON (n.name);
-- Example (RDF): CREATE INDEX idx_triple ON triples (subject, predicate, object);
-- Enables fast graph traversals and semantic queries.

-- 103. Indexing for Vector/Embedding Search at Scale (HNSW, FAISS, Milvus, Pinecone, pgvector advanced)
-- Scenario: Use ANN (Approximate Nearest Neighbor) indexes for high-dimensional vectors.
-- Example (pgvector): CREATE INDEX idx_vec_ann ON docs USING hnsw (embedding_vector);
-- Example (Milvus): CREATE INDEX ON collection_name (vector_field) TYPE = HNSW;
-- Enables fast similarity search for AI/ML workloads.

-- 104. Indexing for LLM/AI Workloads (Prompt Cache, RAG, Hybrid Search)
-- Scenario: Index prompt cache, retrieval docs, and hybrid (text+vector) search fields.
-- CREATE INDEX idx_prompt_cache ON prompt_cache (prompt_hash);
-- CREATE INDEX idx_rag_hybrid ON rag_docs (doc_id, embedding_vector);
-- Optimizes LLM inference and retrieval-augmented generation.

-- 105. Indexing for Blockchain/Ledger/Immutable DBs (Merkle Trees, Cryptographic Proofs)
-- Scenario: Index block/tx hashes, Merkle roots, and proof columns.
-- CREATE INDEX idx_block_merkle ON blocks (block_id, merkle_root);
-- CREATE INDEX idx_tx_hash ON transactions (tx_hash);
-- Enables fast verification and audit of immutable data.

-- 106. Indexing for Real-Time Analytics/HTAP (Materialize, ClickHouse, Druid, Pinot)
-- Scenario: Use materialized view indexes, skip indexes, or segment indexes.
-- Example (ClickHouse): CREATE INDEX idx_skip ON events (event_time) TYPE minmax;
-- Example (Druid): CREATE INDEX idx_segment ON druid_segments (segment_id);
-- Optimizes real-time analytical queries.

-- 107. Indexing for Serverless/Ephemeral DBs (PlanetScale, Neon, Aurora Serverless)
-- Scenario: Index branching, ephemeral, or autoscaled tables.
-- CREATE INDEX idx_branch_user ON branch_users (branch_id, user_id);
-- CREATE INDEX idx_ephemeral_session ON ephemeral_sessions (session_id);
-- Supports serverless scaling and branching.

-- 108. Indexing for Compliance/Sovereignty (Schrems II, Cross-Border, Data Localization)
-- Scenario: Index by residency, region, or compliance tag.
-- CREATE INDEX idx_compliance_region ON user_data (region, compliance_tag);
-- Ensures queries respect data residency and localization laws.

-- 109. Indexing for Chaos Engineering/Observability (Index Chaos, Drift, Health Scoring)
-- Scenario: Track index health, drift, and chaos experiments.
-- CREATE TABLE index_health (index_name TEXT, health_score INT, last_checked TIMESTAMP);
-- CREATE INDEX idx_health_score ON index_health (health_score);
-- Enables SRE/DBRE index chaos and observability.

-- 110. Indexing for Cost/FinOps (Index Cost Tracking, Auto-Drop, Cloud-Native Billing)
-- Scenario: Track index cost, automate drop for unused/expensive indexes.
-- CREATE TABLE index_costs (index_name TEXT, cost NUMERIC, last_used TIMESTAMP);
-- CREATE INDEX idx_cost_last_used ON index_costs (cost, last_used);
-- Supports FinOps and cost-based index management.

-- 111. Indexing for Blue/Green/Canary/Feature-Flag Rollouts (Index Versioning, Shadow Indexes)
-- Scenario: Maintain versioned or shadow indexes for safe rollouts.
-- CREATE INDEX idx_orders_v1 ON orders_v1 (order_id);
-- CREATE INDEX idx_orders_shadow ON orders_shadow (order_id);
-- Enables safe feature-flag and canary deployments.

-- 112. Indexing for Data Mesh/Data Products (Domain-Driven Index Governance)
-- Scenario: Index per data product/domain, enforce mesh governance.
-- CREATE INDEX idx_mesh_product ON mesh_products (domain_id, product_id);
-- Supports decentralized, domain-driven index management.

-- 113. Indexing for Hybrid/Multi-Cloud (Global Index Sync, Cross-Region Consistency)
-- Scenario: Index for global sync and cross-region consistency.
-- CREATE INDEX idx_global_sync ON global_users (user_id, region_id);
-- Ensures low-latency, consistent access across clouds.

-- 114. Indexing for Event Sourcing/CQRS (Read/Write Model Separation, Event Log Indexing)
-- Scenario: Separate read/write indexes, index event logs.
-- CREATE INDEX idx_event_log ON event_log (event_id, created_at);
-- CREATE INDEX idx_cqrs_read ON cqrs_read_model (aggregate_id);
-- Optimizes event sourcing and CQRS patterns.

-- 115. Indexing for Zero Trust/Security (Index Access Control, Encrypted Index Search)
-- Scenario: Index access control, encrypted or masked fields.
-- CREATE INDEX idx_access_encrypted ON secure_access (user_id, encrypted_token);
-- CREATE INDEX idx_index_acl ON index_acl (index_name, user_id, permission);
-- Supports zero trust and secure index access.

-- 116. Indexing for Advanced Automation (AI-Driven Advisors, Self-Healing, GitOps)
-- Scenario: Use AI-driven index advisors, self-healing, and GitOps automation.
-- CREATE TABLE index_advisor (index_name TEXT, recommendation TEXT, applied BOOLEAN);
-- CREATE INDEX idx_advisor_applied ON index_advisor (applied);
-- Enables automated, intelligent index management.

-- 117. Indexing for Time-Travel/Temporal DBs (Bitemporal, System-Versioned, Audit Trails)
-- Scenario: Index valid/transaction time for bitemporal queries.
-- CREATE INDEX idx_bitemporal ON temporal_data (entity_id, valid_from, valid_to, transaction_time);
-- Supports time-travel and audit trail queries.

-- 118. Indexing for Privacy-Enhancing Tech (Differential Privacy, Homomorphic Encryption)
-- Scenario: Index privacy-enhanced or encrypted columns.
-- CREATE INDEX idx_privacy_enhanced ON privacy_data (user_id, dp_token);
-- CREATE INDEX idx_homomorphic ON encrypted_data (user_id, encrypted_value);
-- Enables privacy-preserving analytics and search.

-- 119. Indexing for Data Mesh/Data Contracts (Index Contract Enforcement, Federated Catalogs)
-- Scenario: Enforce index contracts, federate index catalogs.
-- CREATE TABLE index_contracts (domain_id INT, contract_id INT, enforced BOOLEAN);
-- CREATE INDEX idx_contract_enforced ON index_contracts (domain_id, enforced);
-- Supports mesh-wide index governance and compliance.

-- 120. Indexing for SLO/SLA Enforcement (Auto-Disable, Health Scoring)
-- Scenario: Auto-disable or score indexes on SLO/SLA breach.
-- CREATE TABLE index_slo (index_name TEXT, slo_met BOOLEAN, health_score INT);
-- CREATE INDEX idx_slo_health ON index_slo (slo_met, health_score);
-- Enables automated SLO/SLA enforcement for indexes.
