-- Replication, High Availability, Backup/Restore
-- Replication Status
SHOW SLAVE STATUS; -- For classic replication
SHOW REPLICA STATUS; -- For newer MySQL
-- GTID Monitoring
SHOW VARIABLES LIKE 'gtid_mode';
-- Backup Example (mysqldump)
-- shell: mysqldump -u root -p --single-transaction --quick --lock-tables=false dbname > backup.sql
-- Restore Example
-- shell: mysql -u root -p dbname < backup.sql
-- ...add more scenarios as needed...
