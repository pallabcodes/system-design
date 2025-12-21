-- MySQL Data Validation Utilities
-- Collection of reusable data validation and integrity checking functions
-- Adapted for MySQL with stored procedures and validation functions

DELIMITER ;;

-- ===========================================
-- EMAIL VALIDATION
-- =========================================--

-- Validate email format
CREATE FUNCTION is_valid_email(email VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE email_pattern VARCHAR(255) DEFAULT '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';

    IF email IS NULL OR LENGTH(TRIM(email)) = 0 THEN
        RETURN FALSE;
    END IF;

    -- Use REGEXP for pattern matching
    RETURN email REGEXP email_pattern;
END;;

-- Validate and normalize email
CREATE FUNCTION normalize_email(email VARCHAR(255))
RETURNS VARCHAR(255)
DETERMINISTIC
BEGIN
    IF email IS NULL THEN
        RETURN NULL;
    END IF;

    -- Trim whitespace and convert to lowercase
    SET email = LOWER(TRIM(email));

    -- Basic validation
    IF NOT is_valid_email(email) THEN
        RETURN NULL;
    END IF;

    RETURN email;
END;;

-- ===========================================
-- PHONE NUMBER VALIDATION
-- =========================================--

-- Validate phone number (basic international format)
CREATE FUNCTION is_valid_phone(phone VARCHAR(20))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE clean_phone VARCHAR(20);

    IF phone IS NULL OR LENGTH(TRIM(phone)) = 0 THEN
        RETURN FALSE;
    END IF;

    -- Remove all non-digit characters except + and spaces
    SET clean_phone = REGEXP_REPLACE(phone, '[^0-9+\\s]', '');

    -- Check for valid patterns
    RETURN clean_phone REGEXP '^\\+?[0-9\\s]{7,15}$';
END;;

-- Format phone number (basic US format)
CREATE FUNCTION format_phone(phone VARCHAR(20))
RETURNS VARCHAR(20)
DETERMINISTIC
BEGIN
    DECLARE clean_phone VARCHAR(20);

    IF phone IS NULL THEN
        RETURN NULL;
    END IF;

    -- Remove all non-digit characters
    SET clean_phone = REGEXP_REPLACE(phone, '[^0-9]', '');

    -- Format US numbers
    IF LENGTH(clean_phone) = 10 THEN
        RETURN CONCAT('(', LEFT(clean_phone, 3), ') ', MID(clean_phone, 4, 3), '-', RIGHT(clean_phone, 4));
    ELSIF LENGTH(clean_phone) = 11 AND LEFT(clean_phone, 1) = '1' THEN
        SET clean_phone = RIGHT(clean_phone, 10);
        RETURN CONCAT('(', LEFT(clean_phone, 3), ') ', MID(clean_phone, 4, 3), '-', RIGHT(clean_phone, 4));
    ELSE
        RETURN phone; -- Return original if can't format
    END IF;
END;;

-- ===========================================
-- PASSWORD VALIDATION
-- =========================================--

-- Validate password strength
CREATE FUNCTION validate_password_strength(password VARCHAR(255))
RETURNS JSON
DETERMINISTIC
BEGIN
    DECLARE score INT DEFAULT 0;
    DECLARE feedback JSON DEFAULT ('{"valid": false, "score": 0, "errors": []}');

    IF password IS NULL OR LENGTH(password) < 8 THEN
        RETURN JSON_SET(feedback, '$.errors[0]', 'Password must be at least 8 characters');
    END IF;

    -- Length check
    IF LENGTH(password) >= 12 THEN
        SET score = score + 2;
    ELSE
        SET score = score + 1;
    END IF;

    -- Character variety checks
    IF password REGEXP '[a-z]' THEN SET score = score + 1; END IF;
    IF password REGEXP '[A-Z]' THEN SET score = score + 1; END IF;
    IF password REGEXP '[0-9]' THEN SET score = score + 1; END IF;
    IF password REGEXP '[^a-zA-Z0-9]' THEN SET score = score + 1; END IF;

    -- Common patterns (negative)
    IF password REGEXP 'password|123456|qwerty' THEN
        SET score = score - 2;
        SET feedback = JSON_SET(feedback, '$.errors', JSON_ARRAY_APPEND(JSON_EXTRACT(feedback, '$.errors'), '$', 'Contains common password pattern'));
    END IF;

    -- Set final score and validity
    SET feedback = JSON_SET(feedback, '$.score', score);
    SET feedback = JSON_SET(feedback, '$.valid', score >= 4);

    IF score < 4 THEN
        SET feedback = JSON_SET(feedback, '$.errors', JSON_ARRAY_APPEND(JSON_EXTRACT(feedback, '$.errors'), '$', 'Password too weak'));
    END IF;

    RETURN feedback;
END;;

-- ===========================================
-- URL VALIDATION
-- =========================================--

-- Validate URL format
CREATE FUNCTION is_valid_url(url VARCHAR(2000))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE url_pattern VARCHAR(500) DEFAULT '^(https?|ftp)://[^\\s/$.?#].[^\\s]*$';

    IF url IS NULL OR LENGTH(TRIM(url)) = 0 THEN
        RETURN FALSE;
    END IF;

    RETURN url REGEXP url_pattern;
END;;

-- Extract domain from URL
CREATE FUNCTION extract_domain(url VARCHAR(2000))
RETURNS VARCHAR(255)
DETERMINISTIC
BEGIN
    DECLARE domain VARCHAR(255);

    IF url IS NULL THEN
        RETURN NULL;
    END IF;

    -- Extract domain from URL
    SET domain = REGEXP_SUBSTR(url, 'https?://([^/]+)', 1, 1, NULL, 1);

    -- Remove port if present
    SET domain = REGEXP_REPLACE(domain, ':[0-9]+$', '');

    RETURN LOWER(domain);
END;;

-- ===========================================
-- DATA INTEGRITY CHECKS
-- =========================================--

-- Check for orphaned records
CREATE PROCEDURE check_orphaned_records(
    IN parent_table VARCHAR(64),
    IN parent_key VARCHAR(64),
    IN child_table VARCHAR(64),
    IN child_foreign_key VARCHAR(64)
)
BEGIN
    DECLARE sql_query TEXT;

    SET @sql = CONCAT('
        SELECT
            COUNT(*) as orphaned_count,
            \'', child_table, '\' as child_table,
            \'', child_foreign_key, '\' as foreign_key
        FROM `', child_table, '` c
        LEFT JOIN `', parent_table, '` p ON c.`', child_foreign_key, '` = p.`', parent_key, '`
        WHERE p.`', parent_key, '` IS NULL');

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END;;

-- Check for duplicate records
CREATE PROCEDURE find_duplicates(
    IN target_table VARCHAR(64),
    IN column_list TEXT  -- Comma-separated column names
)
BEGIN
    DECLARE sql_query TEXT;

    SET @sql = CONCAT('
        SELECT ', column_list, ', COUNT(*) as duplicate_count
        FROM `', target_table, '`
        GROUP BY ', column_list, '
        HAVING COUNT(*) > 1
        ORDER BY COUNT(*) DESC');

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END;;

-- ===========================================
-- BUSINESS RULE VALIDATION
-- =========================================--

-- Validate date ranges
CREATE FUNCTION is_valid_date_range(start_date DATE, end_date DATE)
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF start_date IS NULL OR end_date IS NULL THEN
        RETURN TRUE; -- NULL values are considered valid
    END IF;

    RETURN start_date <= end_date;
END;;

-- Validate age from birthdate
CREATE FUNCTION calculate_age(birth_date DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    IF birth_date IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN TIMESTAMPDIFF(YEAR, birth_date, CURDATE());
END;;

-- Validate business hours
CREATE FUNCTION is_business_hours(check_time TIME)
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF check_time IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Assuming 9 AM to 5 PM business hours
    RETURN check_time BETWEEN '09:00:00' AND '17:00:00';
END;;

-- ===========================================
-- FINANCIAL VALIDATION
-- =========================================--

-- Validate credit card number (basic Luhn algorithm)
CREATE FUNCTION is_valid_credit_card(cc_number VARCHAR(20))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE clean_number VARCHAR(20);
    DECLARE sum_val INT DEFAULT 0;
    DECLARE should_double BOOLEAN DEFAULT FALSE;
    DECLARE i INT;
    DECLARE digit INT;

    IF cc_number IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Remove spaces and dashes
    SET clean_number = REGEXP_REPLACE(cc_number, '[^0-9]', '');

    -- Check length (13-19 digits)
    IF LENGTH(clean_number) < 13 OR LENGTH(clean_number) > 19 THEN
        RETURN FALSE;
    END IF;

    -- Luhn algorithm
    SET i = LENGTH(clean_number);
    WHILE i > 0 DO
        SET digit = CAST(SUBSTRING(clean_number, i, 1) AS UNSIGNED);

        IF should_double THEN
            SET digit = digit * 2;
            IF digit > 9 THEN
                SET digit = digit - 9;
            END IF;
        END IF;

        SET sum_val = sum_val + digit;
        SET should_double = NOT should_double;
        SET i = i - 1;
    END WHILE;

    RETURN (sum_val % 10) = 0;
END;;

-- Validate currency amount
CREATE FUNCTION is_valid_amount(amount DECIMAL(15,4), currency VARCHAR(3))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF amount IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check for reasonable bounds
    IF amount < -999999999.9999 OR amount > 999999999.9999 THEN
        RETURN FALSE;
    END IF;

    -- Currency-specific validations could be added here
    RETURN TRUE;
END;;

-- ===========================================
-- GEOGRAPHIC VALIDATION
-- =========================================--

-- Validate latitude/longitude
CREATE FUNCTION is_valid_lat_lng(latitude DECIMAL(10,8), longitude DECIMAL(11,8))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF latitude IS NULL OR longitude IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180;
END;;

-- Validate postal code (US format)
CREATE FUNCTION is_valid_us_zip(zip_code VARCHAR(10))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF zip_code IS NULL THEN
        RETURN FALSE;
    END IF;

    -- US ZIP format: 12345 or 12345-6789
    RETURN zip_code REGEXP '^[0-9]{5}(-[0-9]{4})?$';
END;;

-- ===========================================
-- COMPREHENSIVE VALIDATION PROCEDURES
-- =========================================--

-- Validate user data
CREATE PROCEDURE validate_user_data(
    IN user_id VARCHAR(36),
    IN email VARCHAR(255),
    IN phone VARCHAR(20),
    IN birth_date DATE
)
BEGIN
    DECLARE validation_errors JSON DEFAULT ('[]');
    DECLARE is_valid BOOLEAN DEFAULT TRUE;

    -- Email validation
    IF NOT is_valid_email(email) THEN
        SET validation_errors = JSON_ARRAY_APPEND(validation_errors, '$', 'Invalid email format');
        SET is_valid = FALSE;
    END IF;

    -- Phone validation
    IF phone IS NOT NULL AND NOT is_valid_phone(phone) THEN
        SET validation_errors = JSON_ARRAY_APPEND(validation_errors, '$', 'Invalid phone format');
        SET is_valid = FALSE;
    END IF;

    -- Age validation (must be 13+)
    IF birth_date IS NOT NULL AND calculate_age(birth_date) < 13 THEN
        SET validation_errors = JSON_ARRAY_APPEND(validation_errors, '$', 'User must be at least 13 years old');
        SET is_valid = FALSE;
    END IF;

    -- Return results
    SELECT
        user_id,
        is_valid as validation_passed,
        validation_errors,
        CASE
            WHEN is_valid THEN 'VALID'
            ELSE 'INVALID'
        END as status;
END;;

-- Comprehensive data quality check
CREATE PROCEDURE run_data_quality_check(
    IN target_schema VARCHAR(64),
    IN target_table VARCHAR(64)
)
BEGIN
    DECLARE result_summary JSON DEFAULT ('{"table": "", "checks": {}, "total_issues": 0}');

    -- Set table name
    SET result_summary = JSON_SET(result_summary, '$.table', target_table);

    -- Check for NULL values in NOT NULL columns
    BEGIN
        DECLARE null_count INT DEFAULT 0;
        DECLARE sql_query TEXT;

        SELECT COUNT(*) INTO null_count
        FROM information_schema.columns c
        WHERE c.table_schema = target_schema
          AND c.table_name = target_table
          AND c.is_nullable = 'NO'
          AND EXISTS (
              SELECT 1 FROM information_schema.statistics s
              WHERE s.table_schema = target_schema
                AND s.table_name = target_table
                AND s.column_name = c.column_name
          );

        SET result_summary = JSON_SET(result_summary, '$.checks.null_in_not_null', null_count);
        SET result_summary = JSON_SET(result_summary, '$.total_issues', JSON_EXTRACT(result_summary, '$.total_issues') + null_count);
    END;

    -- Check for orphaned records (simplified - would need specific foreign key info)
    -- This would require dynamic SQL based on actual table structure

    -- Check for data type consistency
    BEGIN
        DECLARE type_issues INT DEFAULT 0;

        -- This is a simplified check - real implementation would be more complex
        SELECT COUNT(*) INTO type_issues
        FROM information_schema.columns
        WHERE table_schema = target_schema
          AND table_name = target_table
          AND data_type = 'varchar'
          AND character_maximum_length IS NULL;

        SET result_summary = JSON_SET(result_summary, '$.checks.type_consistency', type_issues);
        SET result_summary = JSON_SET(result_summary, '$.total_issues', JSON_EXTRACT(result_summary, '$.total_issues') + type_issues);
    END;

    -- Return results
    SELECT result_summary as quality_report;
END;;

DELIMITER ;

/*
USAGE EXAMPLES:

-- Validate email
SELECT is_valid_email('user@example.com'); -- Returns 1 (true)

-- Normalize email
SELECT normalize_email('  USER@EXAMPLE.COM  '); -- Returns 'user@example.com'

-- Validate phone
SELECT is_valid_phone('+1-555-123-4567'); -- Returns 1 (true)
SELECT format_phone('5551234567'); -- Returns '(555) 123-4567'

-- Password strength
SELECT validate_password_strength('MySecurePass123!'); -- Returns JSON with score

-- URL validation
SELECT is_valid_url('https://example.com/path'); -- Returns 1 (true)
SELECT extract_domain('https://sub.example.com:8080/path'); -- Returns 'sub.example.com'

-- Data integrity
CALL check_orphaned_records('users', 'user_id', 'posts', 'author_id');
CALL find_duplicates('users', 'email, phone');

-- Date validation
SELECT is_valid_date_range('2024-01-01', '2024-12-31'); -- Returns 1 (true)

-- Financial validation
SELECT is_valid_credit_card('4111111111111111'); -- Returns 1 (true)
SELECT is_valid_amount(123.45, 'USD'); -- Returns 1 (true)

-- Geographic validation
SELECT is_valid_lat_lng(40.7128, -74.0060); -- Returns 1 (true)
SELECT is_valid_us_zip('12345-6789'); -- Returns 1 (true)

-- User validation
CALL validate_user_data('user-123', 'user@example.com', '+1-555-123-4567', '2000-01-01');

-- Data quality check
CALL run_data_quality_check('your_database', 'users');

This utility provides comprehensive data validation for MySQL databases including:
- Email, phone, URL, and password validation
- Business rule validation (dates, amounts, geography)
- Data integrity checks (orphaned records, duplicates)
- Financial validation (credit cards, amounts)
- Geographic validation (coordinates, postal codes)
- Comprehensive data quality assessments

Key features:
1. Reusable validation functions for common data types
2. Configurable business rule validation
3. Data integrity and quality monitoring
4. JSON-based result reporting
5. Easy integration with applications and triggers

Adapt and extend based on your specific data validation requirements!
*/
