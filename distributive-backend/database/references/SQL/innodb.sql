SET GLOBAL innodb_buffer_pool_size = 8;  -- Adjust based on your RAM
SET GLOBAL innodb_flush_log_at_trx_commit = 2;
SET GLOBAL innodb_flush_method = O_DIRECT;
SET GLOBAL foreign_key_checks = 0;
SET GLOBAL unique_checks = 0;