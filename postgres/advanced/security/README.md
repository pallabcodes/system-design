# PostgreSQL Security

## Overview

PostgreSQL provides comprehensive security features for protecting sensitive data, controlling access, and ensuring compliance with industry standards. This guide covers authentication, authorization, encryption, auditing, and compliance features.

## Table of Contents

1. [Authentication Methods](#authentication-methods)
2. [Authorization and Access Control](#authorization-and-access-control)
3. [Data Encryption](#data-encryption)
4. [SSL/TLS Configuration](#ssltls-configuration)
5. [Row Level Security](#row-level-security)
6. [Auditing and Logging](#auditing-and-logging)
7. [Security Extensions](#security-extensions)
8. [Compliance Features](#compliance-features)
9. [Enterprise Security Patterns](#enterprise-security-patterns)

## Authentication Methods

### PostgreSQL Authentication Methods

```sql
-- Configure authentication in pg_hba.conf
-- Example configurations:

-- Local connections with peer authentication
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
local   all             all                                     peer

-- Host connections with MD5 password authentication
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5

-- Host connections with SCRAM-SHA-256
host    all             all             192.168.1.0/24          scram-sha-256

-- Certificate authentication
hostssl all             all             0.0.0.0/0               cert

-- LDAP authentication
host    all             all             0.0.0.0/0               ldap ldapserver=ldap.company.com ldapprefix="cn=" ldapsuffix=",dc=company,dc=com"

-- RADIUS authentication
host    all             all             0.0.0.0/0               radius radiusservers="radius1.company.com:radius2.company.com" radiussecret=secret123
```

### User Management

```sql
-- Create users with different privilege levels
CREATE USER readonly_user WITH PASSWORD 'secure_password';
CREATE USER application_user WITH PASSWORD 'app_password';
CREATE USER admin_user WITH PASSWORD 'admin_password' SUPERUSER;

-- Create roles for role-based access control
CREATE ROLE read_only;
CREATE ROLE read_write;
CREATE ROLE admin;

-- Grant privileges to roles
GRANT CONNECT ON DATABASE healthcare_db TO read_only;
GRANT CONNECT ON DATABASE healthcare_db TO read_write;
GRANT CONNECT ON DATABASE healthcare_db TO admin;

-- Assign users to roles
GRANT read_only TO readonly_user;
GRANT read_write TO application_user;
GRANT admin TO admin_user;

-- Create group roles
CREATE ROLE healthcare_staff;
CREATE ROLE doctors INHERIT healthcare_staff;
CREATE ROLE nurses INHERIT healthcare_staff;
CREATE ROLE administrators INHERIT healthcare_staff;
```

### Password Policies

```sql
-- Set password encryption method
SET password_encryption = 'scram-sha-256';

-- Create users with password policies
CREATE USER temp_user WITH PASSWORD 'TempPass123!'
    VALID UNTIL '2024-12-31';

-- Change password
ALTER USER application_user PASSWORD 'new_secure_password';

-- Force password change
ALTER USER temp_user PASSWORD NULL;  -- User must set password on next login

-- Password history (requires extension)
CREATE EXTENSION passwordhistory;

-- Configure password history
ALTER SYSTEM SET passwordhistory.history_count = 5;
ALTER SYSTEM SET passwordhistory.history_days = 90;
```

## Authorization and Access Control

### Database-Level Privileges

```sql
-- Grant database-level privileges
GRANT CONNECT ON DATABASE healthcare_db TO healthcare_staff;
GRANT CREATE ON DATABASE healthcare_db TO administrators;

-- Revoke privileges
REVOKE CREATE ON DATABASE healthcare_db FROM healthcare_staff;

-- Schema privileges
GRANT USAGE ON SCHEMA patient_data TO healthcare_staff;
GRANT CREATE ON SCHEMA patient_data TO doctors;

-- Table privileges
GRANT SELECT ON patient_records TO read_only;
GRANT SELECT, INSERT, UPDATE ON patient_records TO doctors;
GRANT ALL PRIVILEGES ON patient_records TO administrators;

-- Column-level privileges
GRANT SELECT (patient_id, first_name, last_name) ON patient_records TO nurses;
GRANT SELECT (patient_id, diagnosis, treatment) ON patient_records TO doctors;
REVOKE SELECT (ssn) ON patient_records FROM nurses;
```

### Function Security

```sql
-- Security definer functions (run with creator's privileges)
CREATE OR REPLACE FUNCTION get_patient_record(patient_id_param INTEGER)
RETURNS patient_records AS $$
DECLARE
    result patient_records;
BEGIN
    -- Function runs with creator's privileges, not caller's
    SELECT * INTO result FROM patient_records WHERE patient_id = patient_id_param;
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_patient_record(INTEGER) TO doctors;

-- Security invoker functions (run with caller's privileges)
CREATE OR REPLACE FUNCTION update_patient_status(patient_id_param INTEGER, new_status VARCHAR)
RETURNS VOID AS $$
BEGIN
    -- Function runs with caller's privileges
    UPDATE patient_records
    SET status = new_status, updated_at = CURRENT_TIMESTAMP
    WHERE patient_id = patient_id_param;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Set function search path to prevent search_path attacks
ALTER FUNCTION get_patient_record(INTEGER) SET search_path = patient_data, public;
```

### Default Privileges

```sql
-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA patient_data
    GRANT SELECT ON TABLES TO healthcare_staff;

ALTER DEFAULT PRIVILEGES IN SCHEMA patient_data
    GRANT SELECT, INSERT, UPDATE ON TABLES TO doctors;

ALTER DEFAULT PRIVILEGES IN SCHEMA patient_data
    FOR ROLE doctors
    GRANT SELECT, INSERT, UPDATE ON TABLES TO nurses;

-- Default privileges for functions
ALTER DEFAULT PRIVILEGES IN SCHEMA patient_data
    GRANT EXECUTE ON FUNCTIONS TO healthcare_staff;
```

## Data Encryption

### Transparent Data Encryption (TDE)

```sql
-- PostgreSQL doesn't have built-in TDE like some other databases
-- Use filesystem-level encryption or third-party solutions

-- File system encryption (example with LUKS)
sudo cryptsetup luksFormat /dev/sdb
sudo cryptsetup luksOpen /dev/sdb encrypted_postgres
sudo mkfs.ext4 /dev/mapper/encrypted_postgres
sudo mount /dev/mapper/encrypted_postgres /var/lib/postgresql/data

-- Database-level encryption using pgcrypto extension
CREATE EXTENSION pgcrypto;

-- Encrypt sensitive columns
CREATE TABLE patient_records (
    patient_id SERIAL PRIMARY KEY,
    ssn_encrypted BYTEA,  -- Encrypted SSN
    medical_data TEXT,    -- Regular text (not encrypted)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert encrypted data
INSERT INTO patient_records (ssn_encrypted, medical_data)
VALUES (
    pgp_sym_encrypt('123-45-6789', 'encryption_key'),
    'Patient has normal blood pressure'
);

-- Query encrypted data
SELECT
    patient_id,
    pgp_sym_decrypt(ssn_encrypted, 'encryption_key') AS ssn,
    medical_data
FROM patient_records
WHERE patient_id = 1;
```

### Column-Level Encryption

```sql
-- Encrypt specific sensitive columns
CREATE TABLE credit_cards (
    card_id SERIAL PRIMARY KEY,
    patient_id INTEGER REFERENCES patients(patient_id),
    card_number_encrypted BYTEA,
    expiry_date_encrypted BYTEA,
    cardholder_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Encryption functions
CREATE OR REPLACE FUNCTION encrypt_card_number(card_number TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(card_number, current_setting('app.encryption_key'));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION decrypt_card_number(encrypted_data BYTEA)
RETURNS TEXT AS $$
BEGIN
    RETURN pgp_sym_decrypt(encrypted_data, current_setting('app.encryption_key'));
END;
$$ LANGUAGE plpgsql;

-- Usage
INSERT INTO credit_cards (
    patient_id,
    card_number_encrypted,
    expiry_date_encrypted,
    cardholder_name
) VALUES (
    123,
    encrypt_card_number('4111111111111111'),
    encrypt_card_number('12/25'),
    'John Doe'
);

-- Secure decryption
SELECT
    card_id,
    decrypt_card_number(card_number_encrypted) AS card_number,
    decrypt_card_number(expiry_date_encrypted) AS expiry_date
FROM credit_cards
WHERE patient_id = 123;
```

## SSL/TLS Configuration

### SSL Certificate Setup

```bash
# Generate SSL certificates
# Create CA certificate
openssl req -new -x509 -days 3650 -keyout ca.key -out ca.crt -subj "/C=US/ST=State/L=City/O=Organization/CN=CA"

# Generate server certificate
openssl req -new -keyout server.key -out server.csr -subj "/C=US/ST=State/L=City/O=Organization/CN=postgres.example.com"
openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key -out server.crt

# Set proper permissions
chmod 600 server.key
chown postgres:postgres server.crt server.key

# Configure PostgreSQL for SSL
# postgresql.conf
ssl = on
ssl_cert_file = '/etc/ssl/certs/postgres/server.crt'
ssl_key_file = '/etc/ssl/private/postgres/server.key'
ssl_ca_file = '/etc/ssl/certs/postgres/ca.crt'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL:!SSLv3:!TLSv1'
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'
```

### PostgreSQL SSL Configuration

```sql
-- View SSL status
SELECT
    usename,
    client_addr,
    ssl,
    version AS ssl_version,
    cipher
FROM pg_stat_ssl
JOIN pg_stat_activity ON pg_stat_ssl.pid = pg_stat_activity.pid;

-- Require SSL for specific users
-- pg_hba.conf
hostssl healthcare_db doctors 192.168.1.0/24 scram-sha-256
hostnossl healthcare_db readonly 192.168.1.0/24 scram-sha-256

-- Client certificate authentication
hostssl healthcare_db admin all cert clientcert=1

-- SSL connection parameters in application
-- JDBC example
jdbc:postgresql://localhost:5432/healthcare_db?ssl=true&sslmode=require&sslcert=/path/to/client.crt&sslkey=/path/to/client.key&sslrootcert=/path/to/ca.crt
```

## Row Level Security

### Basic RLS Implementation

```sql
-- Enable Row Level Security on tables
ALTER TABLE patient_records ENABLE ROW LEVEL SECURITY;

-- Create security policies
CREATE POLICY patient_own_records ON patient_records
    FOR ALL
    USING (patient_id = current_setting('app.current_patient_id')::INTEGER);

CREATE POLICY doctor_access ON patient_records
    FOR SELECT, UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM doctor_patient_assignments
            WHERE doctor_id = current_setting('app.current_user_id')::INTEGER
              AND patient_id = patient_records.patient_id
        )
    );

CREATE POLICY admin_full_access ON patient_records
    FOR ALL
    TO administrators
    USING (true);

-- Bypass RLS for specific operations (use carefully)
ALTER TABLE system_logs FORCE ROW LEVEL SECURITY;  -- Even superusers must follow policies
```

### Advanced RLS Policies

```sql
-- Time-based access control
CREATE POLICY recent_records_only ON medical_records
    FOR SELECT
    USING (
        created_at > CURRENT_TIMESTAMP - INTERVAL '2 years' OR
        current_setting('app.user_role') = 'admin'
    );

-- Department-based access
CREATE POLICY department_access ON patient_records
    FOR ALL
    USING (
        department_id IN (
            SELECT department_id FROM user_departments
            WHERE user_id = current_setting('app.current_user_id')::INTEGER
        )
    );

-- Emergency access override
CREATE POLICY emergency_access ON patient_records
    FOR SELECT
    USING (
        current_setting('app.emergency_mode') = 'true' OR
        EXISTS (
            SELECT 1 FROM user_permissions
            WHERE user_id = current_setting('app.current_user_id')::INTEGER
              AND permission = 'emergency_access'
        )
    );
```

### RLS Performance Considerations

```sql
-- Create indexes to support RLS policies
CREATE INDEX idx_patient_records_patient_id ON patient_records (patient_id);
CREATE INDEX idx_doctor_assignments_doctor_id ON doctor_patient_assignments (doctor_id, patient_id);

-- Use immutable functions in policies for better performance
CREATE OR REPLACE FUNCTION get_current_user_departments()
RETURNS INTEGER[] AS $$
    SELECT array_agg(department_id)
    FROM user_departments
    WHERE user_id = current_setting('app.current_user_id')::INTEGER;
$$ LANGUAGE SQL IMMUTABLE;

CREATE POLICY department_policy ON sensitive_data
    FOR ALL
    USING (department_id = ANY (get_current_user_departments()));
```

## Auditing and Logging

### Database Audit Logging

```sql
-- Enable audit logging
CREATE EXTENSION pg_audit;

-- Configure audit logging
ALTER SYSTEM SET pgaudit.log = 'ddl,role,read,write';
ALTER SYSTEM SET pgaudit.log_catalog = off;
ALTER SYSTEM SET pgaudit.log_level = log;
ALTER SYSTEM SET pgaudit.log_parameter = on;
ALTER SYSTEM SET pgaudit.log_relation = 'ddl,write';
ALTER SYSTEM SET pgaudit.log_statement_once = off;

-- Custom audit trigger
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    audit_row audit_log%ROWTYPE;
    old_row JSONB;
    new_row JSONB;
BEGIN
    old_row := CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::JSONB ELSE NULL END;
    new_row := CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::JSONB ELSE NULL END;

    audit_row := (
        DEFAULT,
        TG_TABLE_NAME,
        TG_OP,
        old_row,
        new_row,
        current_setting('app.current_user_id', TRUE)::UUID,
        inet_client_addr(),
        CURRENT_TIMESTAMP
    );

    INSERT INTO audit_log VALUES (audit_row.*);
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Apply audit trigger to sensitive tables
CREATE TRIGGER audit_patient_records
    AFTER INSERT OR UPDATE OR DELETE ON patient_records
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
```

### Audit Log Analysis

```sql
-- Query audit logs
SELECT
    id,
    table_name,
    operation,
    user_id,
    client_addr,
    timestamp,
    old_values->>'patient_id' AS patient_id,
    new_values->>'status' AS new_status,
    old_values->>'status' AS old_status
FROM audit_log
WHERE table_name = 'patient_records'
  AND timestamp >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY timestamp DESC;

-- Audit trail for specific patient
SELECT
    timestamp,
    operation,
    user_id,
    old_values,
    new_values
FROM audit_log
WHERE table_name = 'patient_records'
  AND (old_values->>'patient_id')::INTEGER = 123
   OR (new_values->>'patient_id')::INTEGER = 123
ORDER BY timestamp;

-- Security incident investigation
SELECT
    timestamp,
    user_id,
    client_addr,
    operation,
    table_name,
    old_values,
    new_values
FROM audit_log
WHERE user_id = 'suspicious_user'
  AND timestamp >= '2024-01-01 00:00:00'
ORDER BY timestamp;
```

## Security Extensions

### Additional Security Extensions

```sql
-- Install security extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_audit;
CREATE EXTENSION IF NOT EXISTS sslinfo;
CREATE EXTENSION IF NOT EXISTS auth_delay;  -- Add delay to failed authentications
CREATE EXTENSION IF NOT EXISTS passwordcheck;  -- Enforce password policies

-- Configure auth_delay
ALTER SYSTEM SET auth_delay.milliseconds = 1000;

-- Configure password policies
-- passwordcheck requires configuration in shared_preload_libraries
-- shared_preload_libraries = 'passwordcheck'

-- Set password policy parameters
SET passwordcheck.cracklib = on;
SET passwordcheck.min_length = 12;
SET passwordcheck.min_special = 2;
SET passwordcheck.min_digit = 2;
SET passwordcheck.min_upper = 1;
SET passwordcheck.min_lower = 1;
```

### Security Monitoring

```sql
-- Monitor failed authentication attempts
CREATE TABLE auth_failures (
    id SERIAL PRIMARY KEY,
    username TEXT,
    client_addr INET,
    attempted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Log failed attempts (requires log analysis or triggers)
CREATE OR REPLACE FUNCTION log_auth_failure()
RETURNS event_trigger AS $$
BEGIN
    -- This would be called from external authentication monitoring
    -- For demonstration purposes
    INSERT INTO auth_failures (username, client_addr)
    VALUES (current_setting('app.failed_user'), inet_client_addr());
END;
$$ LANGUAGE plpgsql;

-- Monitor suspicious activities
CREATE OR REPLACE FUNCTION detect_suspicious_activity()
RETURNS TRIGGER AS $$
DECLARE
    recent_failures INTEGER;
BEGIN
    -- Count recent failed attempts for this IP
    SELECT count(*) INTO recent_failures
    FROM auth_failures
    WHERE client_addr = inet_client_addr()
      AND attempted_at > CURRENT_TIMESTAMP - INTERVAL '1 hour';

    IF recent_failures > 5 THEN
        -- Log security incident
        INSERT INTO security_incidents (
            incident_type, description, client_addr, severity
        ) VALUES (
            'brute_force_attempt',
            format('Multiple failed auth attempts from %s', inet_client_addr()),
            inet_client_addr(),
            'high'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### HIPAA Compliance for Healthcare

```sql
-- PHI (Protected Health Information) access logging
CREATE TABLE phi_access_log (
    id SERIAL PRIMARY KEY,
    user_id UUID,
    patient_id INTEGER,
    table_name TEXT,
    operation TEXT,
    accessed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    client_addr INET,
    purpose_of_use TEXT,  -- Required for HIPAA
    user_role TEXT
);

-- Log all PHI access
CREATE OR REPLACE FUNCTION log_phi_access()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO phi_access_log (
        user_id, patient_id, table_name, operation,
        client_addr, purpose_of_use, user_role
    ) VALUES (
        current_setting('app.current_user_id')::UUID,
        COALESCE(NEW.patient_id, OLD.patient_id),
        TG_TABLE_NAME,
        TG_OP,
        inet_client_addr(),
        current_setting('app.purpose_of_use'),
        current_setting('app.user_role')
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Apply PHI logging to all patient tables
CREATE TRIGGER phi_access_patient_records
    AFTER SELECT OR UPDATE ON patient_records
    FOR EACH ROW EXECUTE FUNCTION log_phi_access();

-- Data retention policies
CREATE OR REPLACE FUNCTION enforce_data_retention()
RETURNS TRIGGER AS $$
BEGIN
    -- Automatically delete old audit logs (7 years for HIPAA)
    DELETE FROM phi_access_log
    WHERE accessed_at < CURRENT_TIMESTAMP - INTERVAL '7 years';

    -- Anonymize old patient data
    UPDATE patient_records
    SET ssn = NULL, address = NULL
    WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '10 years'
      AND status = 'deceased';

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Schedule data retention
SELECT cron.schedule('data-retention', '0 2 * * *', 'SELECT enforce_data_retention();');
```

### GDPR Compliance Features

```sql
-- Right to be forgotten implementation
CREATE OR REPLACE FUNCTION gdpr_delete_user(user_id_param UUID)
RETURNS VOID AS $$
DECLARE
    user_record RECORD;
BEGIN
    -- Check if user has right to deletion
    SELECT * INTO user_record FROM users WHERE user_id = user_id_param;

    IF user_record IS NULL THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    -- Log deletion request
    INSERT INTO gdpr_deletion_log (user_id, requested_at, user_data)
    VALUES (user_id_param, CURRENT_TIMESTAMP, row_to_json(user_record));

    -- Anonymize instead of delete (if legally required)
    UPDATE users SET
        first_name = 'Deleted',
        last_name = 'User',
        email = format('deleted_%s@example.com', user_id_param),
        phone = NULL,
        address = NULL,
        date_of_birth = NULL,
        gdpr_deleted = TRUE,
        deleted_at = CURRENT_TIMESTAMP
    WHERE user_id = user_id_param;

    -- Delete or anonymize related data
    UPDATE orders SET customer_data = NULL WHERE customer_id = user_id_param;
    DELETE FROM user_sessions WHERE user_id = user_id_param;

END;
$$ LANGUAGE plpgsql;

-- Data portability export
CREATE OR REPLACE FUNCTION export_user_data(user_id_param UUID)
RETURNS JSONB AS $$
DECLARE
    user_data JSONB;
BEGIN
    -- Collect all user data
    SELECT jsonb_build_object(
        'personal_info', row_to_json(u),
        'orders', (
            SELECT jsonb_agg(row_to_json(o))
            FROM orders o WHERE o.customer_id = user_id_param
        ),
        'preferences', (
            SELECT row_to_json(up) FROM user_preferences up WHERE up.user_id = user_id_param
        ),
        'exported_at', CURRENT_TIMESTAMP
    ) INTO user_data
    FROM users u WHERE u.user_id = user_id_param;

    -- Log export for compliance
    INSERT INTO gdpr_export_log (user_id, exported_at, export_size)
    VALUES (user_id_param, CURRENT_TIMESTAMP, pg_column_size(user_data));

    RETURN user_data;
END;
$$ LANGUAGE plpgsql;

-- Consent management
CREATE TABLE user_consents (
    user_id UUID REFERENCES users(user_id),
    consent_type VARCHAR(100), -- 'marketing', 'analytics', 'third_party'
    consented BOOLEAN DEFAULT FALSE,
    consent_given_at TIMESTAMP WITH TIME ZONE,
    consent_revoked_at TIMESTAMP WITH TIME ZONE,
    ip_address INET,
    user_agent TEXT,
    PRIMARY KEY (user_id, consent_type)
);

-- Check consent before processing
CREATE OR REPLACE FUNCTION has_user_consent(user_id_param UUID, consent_type_param VARCHAR)
RETURNS BOOLEAN AS $$
    SELECT consented AND (consent_revoked_at IS NULL)
    FROM user_consents
    WHERE user_id = user_id_param AND consent_type = consent_type_param;
$$ LANGUAGE SQL;
```

## Enterprise Security Patterns

### Multi-Tenant Security

```sql
-- Row Level Security for multi-tenant applications
ALTER TABLE tenant_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON tenant_data
    FOR ALL
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);

-- Tenant-specific encryption keys
CREATE TABLE tenant_keys (
    tenant_id UUID PRIMARY KEY,
    encryption_key TEXT,  -- Store encrypted or use KMS
    key_version INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tenant-aware encryption functions
CREATE OR REPLACE FUNCTION tenant_encrypt(data TEXT)
RETURNS BYTEA AS $$
DECLARE
    tenant_key TEXT;
BEGIN
    SELECT encryption_key INTO tenant_key
    FROM tenant_keys
    WHERE tenant_id = current_setting('app.current_tenant_id')::UUID;

    RETURN pgp_sym_encrypt(data, tenant_key);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION tenant_decrypt(encrypted_data BYTEA)
RETURNS TEXT AS $$
DECLARE
    tenant_key TEXT;
BEGIN
    SELECT encryption_key INTO tenant_key
    FROM tenant_keys
    WHERE tenant_id = current_setting('app.current_tenant_id')::UUID;

    RETURN pgp_sym_decrypt(encrypted_data, tenant_key);
END;
$$ LANGUAGE plpgsql;
```

### Secure API Access Patterns

```sql
-- API key management
CREATE TABLE api_keys (
    key_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(tenant_id),
    key_name VARCHAR(100),
    api_key_hash VARCHAR(128),  -- Store hash, not plain key
    permissions JSONB,  -- e.g., {"read": true, "write": false, "admin": false}
    rate_limit INTEGER DEFAULT 1000,  -- requests per hour
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE
);

-- API key validation function
CREATE OR REPLACE FUNCTION validate_api_key(api_key_param TEXT)
RETURNS TABLE (
    valid BOOLEAN,
    tenant_id UUID,
    permissions JSONB,
    rate_limit_remaining INTEGER
) AS $$
DECLARE
    key_record api_keys%ROWTYPE;
    requests_this_hour INTEGER;
BEGIN
    -- Find key by hash
    SELECT * INTO key_record
    FROM api_keys
    WHERE api_key_hash = encode(sha256(api_key_param::bytea), 'hex')
      AND is_active = TRUE
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP);

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::JSONB, NULL::INTEGER;
        RETURN;
    END IF;

    -- Check rate limit
    SELECT count(*) INTO requests_this_hour
    FROM api_requests
    WHERE key_id = key_record.key_id
      AND requested_at >= date_trunc('hour', CURRENT_TIMESTAMP);

    IF requests_this_hour >= key_record.rate_limit THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::JSONB, 0;
        RETURN;
    END IF;

    -- Update last used
    UPDATE api_keys SET last_used_at = CURRENT_TIMESTAMP WHERE key_id = key_record.key_id;

    -- Log request
    INSERT INTO api_requests (key_id, requested_at, client_ip)
    VALUES (key_record.key_id, CURRENT_TIMESTAMP, inet_client_addr());

    RETURN QUERY SELECT
        TRUE,
        key_record.tenant_id,
        key_record.permissions,
        key_record.rate_limit - requests_this_hour - 1;
END;
$$ LANGUAGE plpgsql;
```

### Database Firewall and Intrusion Detection

```sql
-- Query pattern monitoring
CREATE TABLE suspicious_queries (
    id SERIAL PRIMARY KEY,
    query_text TEXT,
    user_name TEXT,
    client_addr INET,
    detected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    risk_level VARCHAR(20),  -- 'low', 'medium', 'high', 'critical'
    blocked BOOLEAN DEFAULT FALSE
);

-- Analyze query patterns
CREATE OR REPLACE FUNCTION analyze_query_patterns()
RETURNS VOID AS $$
DECLARE
    query_record RECORD;
    risk_score INTEGER := 0;
BEGIN
    FOR query_record IN
        SELECT
            query,
            usename,
            client_addr,
            count(*) AS frequency
        FROM pg_stat_statements
        JOIN pg_stat_activity ON pg_stat_statements.userid = pg_stat_activity.usesysid
        WHERE query LIKE '%DROP%'
           OR query LIKE '%DELETE%WHERE%1=1%'
           OR query LIKE '%UNION%SELECT%'
        GROUP BY query, usename, client_addr
        HAVING count(*) > 10
    LOOP
        -- Calculate risk score
        risk_score := 0;

        IF query_record.query LIKE '%DROP%' THEN risk_score := risk_score + 50; END IF;
        IF query_record.query LIKE '%DELETE%' THEN risk_score := risk_score + 30; END IF;
        IF query_record.query LIKE '%UNION%' THEN risk_score := risk_score + 40; END IF;
        IF query_record.frequency > 100 THEN risk_score := risk_score + 20; END IF;

        -- Classify risk
        INSERT INTO suspicious_queries (
            query_text, user_name, client_addr, risk_level
        ) VALUES (
            query_record.query,
            query_record.usename,
            query_record.client_addr,
            CASE
                WHEN risk_score >= 80 THEN 'critical'
                WHEN risk_score >= 50 THEN 'high'
                WHEN risk_score >= 20 THEN 'medium'
                ELSE 'low'
            END
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Automated blocking (use with caution)
CREATE OR REPLACE FUNCTION block_suspicious_activity()
RETURNS VOID AS $$
DECLARE
    suspicious_record RECORD;
BEGIN
    FOR suspicious_record IN
        SELECT * FROM suspicious_queries
        WHERE risk_level = 'critical'
          AND detected_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'
          AND NOT blocked
    LOOP
        -- Block user or IP (implementation depends on infrastructure)
        -- This could integrate with external firewall systems

        UPDATE suspicious_queries SET blocked = TRUE
        WHERE id = suspicious_record.id;

        -- Log security incident
        INSERT INTO security_incidents (
            incident_type, description, severity, client_addr
        ) VALUES (
            'suspicious_query_pattern',
            format('Critical risk query pattern detected: %s', left(suspicious_record.query_text, 100)),
            'critical',
            suspicious_record.client_addr
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

This comprehensive security guide covers authentication, authorization, encryption, compliance features, and enterprise security patterns for PostgreSQL databases, with specific focus on healthcare and multi-tenant environments.
