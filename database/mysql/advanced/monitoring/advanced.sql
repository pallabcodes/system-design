-- Monitoring & Troubleshooting (performance_schema, sys schema, tools)
-- Enable performance_schema
SHOW VARIABLES LIKE 'performance_schema';
-- Query performance metrics
SELECT * FROM performance_schema.events_statements_summary_by_digest ORDER BY AVG_TIMER_WAIT DESC LIMIT 10;
-- Sys Schema Examples
SELECT * FROM sys.schema_table_statistics ORDER BY rows_read DESC LIMIT 10;
-- Third-party tools: Percona Toolkit, PMM, MySQL Enterprise Monitor
-- ...add more scenarios as needed...
