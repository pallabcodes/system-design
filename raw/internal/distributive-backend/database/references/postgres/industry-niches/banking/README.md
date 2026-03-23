# Banking & Financial Services Database Design

## Overview

This comprehensive database schema supports retail and commercial banking operations, including account management, transaction processing, loan origination, credit card services, and regulatory compliance. The design emphasizes security, auditability, and scalability for high-volume financial transactions.

## Key Features

### 🏦 Customer Management
- **Multi-entity customers** (individuals, businesses, non-profits, government)
- **KYC/AML compliance** with risk rating and sanctions screening
- **Customer segmentation** and relationship management
- **Regulatory reporting** capabilities

### 💳 Account & Transaction Processing
- **Multi-currency support** with real-time balance calculations
- **High-volume transaction processing** with partitioning
- **Automated fee calculation** and interest accrual
- **Transaction categorization** for reporting and analytics

### 💳 Cards & Payments
- **Debit and credit card management** with security features
- **Contactless and biometric** payment support
- **Fraud detection** and risk scoring
- **Rewards program** integration

### 🏠 Loans & Credit
- **Loan origination and servicing** across multiple product types
- **Automated payment processing** and delinquency tracking
- **Credit scoring** integration and risk assessment
- **Collateral management** for secured loans

## Database Schema Highlights

### Core Tables

#### Customer Management
- **`customers`** - Base customer information with KYC status
- **`individual_customers`** - Personal customer details and demographics
- **`business_customers`** - Business entity information and structure

#### Account Management
- **`accounts`** - Account master data with balances and limits
- **`account_holders`** - Joint account ownership and authorization
- **`transactions`** - Complete transaction ledger with monthly partitioning

#### Cards & Payments
- **`cards`** - Card management with security and limits
- **`card_transactions`** - Card-specific transaction details and fraud scoring

#### Loans & Credit
- **`loans`** - Loan origination and servicing data
- **`loan_payments`** - Payment processing and amortization
- **`credit_reports`** - Credit scoring and risk assessment

#### Compliance & Security
- **`compliance_events`** - Regulatory compliance tracking
- **`suspicious_activity_reports`** - SAR filing and investigation

## Key Design Patterns

### 1. Transaction Processing with Partitioning
```sql
-- Monthly transaction partitioning for performance
CREATE TABLE transactions_y2024m01 PARTITION OF transactions
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Efficient date-range queries
SELECT * FROM transactions
WHERE transaction_date >= '2024-01-01' AND transaction_date < '2024-02-01';
```

### 2. Real-time Balance Calculations
```sql
-- Account balance with overdraft protection
CREATE OR REPLACE FUNCTION update_account_balance(account_uuid UUID, amount DECIMAL)
RETURNS DECIMAL AS $$
DECLARE
    current_balance DECIMAL;
    available_balance DECIMAL;
    overdraft_limit DECIMAL;
BEGIN
    -- Get current account state
    SELECT a.current_balance, a.available_balance, a.overdraft_limit
    INTO current_balance, available_balance, overdraft_limit
    FROM accounts a WHERE a.account_id = account_uuid;

    -- Update balances
    current_balance := current_balance + amount;
    available_balance := LEAST(current_balance + overdraft_limit, current_balance);

    -- Update account
    UPDATE accounts
    SET current_balance = current_balance,
        available_balance = available_balance,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_id = account_uuid;

    RETURN current_balance;
END;
$$ LANGUAGE plpgsql;
```

### 3. Loan Amortization Calculations
```sql
-- Calculate loan payment schedule
CREATE OR REPLACE FUNCTION calculate_loan_schedule(
    principal DECIMAL,
    interest_rate DECIMAL,
    term_months INTEGER
)
RETURNS TABLE (
    payment_number INTEGER,
    payment_date DATE,
    payment_amount DECIMAL,
    principal_payment DECIMAL,
    interest_payment DECIMAL,
    remaining_balance DECIMAL
) AS $$
DECLARE
    monthly_rate DECIMAL := interest_rate / 12;
    monthly_payment DECIMAL;
    remaining DECIMAL := principal;
    payment_date_val DATE := CURRENT_DATE;
BEGIN
    -- Calculate monthly payment using amortization formula
    monthly_payment := principal * (monthly_rate * POWER(1 + monthly_rate, term_months)) /
                      (POWER(1 + monthly_rate, term_months) - 1);

    FOR i IN 1..term_months LOOP
        -- Calculate interest and principal portions
        interest_payment := remaining * monthly_rate;
        principal_payment := monthly_payment - interest_payment;
        remaining := remaining - principal_payment;

        -- Return payment details
        RETURN QUERY SELECT
            i,
            payment_date_val,
            ROUND(monthly_payment, 2),
            ROUND(principal_payment, 2),
            ROUND(interest_payment, 2),
            ROUND(GREATEST(remaining, 0), 2);

        -- Move to next payment date
        payment_date_val := payment_date_val + INTERVAL '1 month';
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 4. Risk Assessment and Credit Scoring
```sql
-- Calculate customer risk score
CREATE OR REPLACE FUNCTION calculate_customer_risk(customer_uuid UUID)
RETURNS VARCHAR(10) AS $$
DECLARE
    risk_score INTEGER := 0;
    credit_score INTEGER;
    delinquent_accounts INTEGER;
    total_accounts INTEGER;
    utilization_rate DECIMAL;
BEGIN
    -- Get credit report data
    SELECT
        cr.credit_score,
        cr.delinquent_accounts,
        cr.total_accounts,
        cr.utilization_rate
    INTO credit_score, delinquent_accounts, total_accounts, utilization_rate
    FROM credit_reports cr
    WHERE cr.customer_id = customer_uuid
    ORDER BY cr.report_date DESC
    LIMIT 1;

    -- Calculate risk components
    IF credit_score < 580 THEN risk_score := risk_score + 50;
    ELSIF credit_score < 670 THEN risk_score := risk_score + 30;
    ELSIF credit_score < 740 THEN risk_score := risk_score + 10;
    END IF;

    IF delinquent_accounts > 0 THEN risk_score := risk_score + 20; END IF;
    IF utilization_rate > 30 THEN risk_score := risk_score + 15; END IF;

    -- Determine risk rating
    CASE
        WHEN risk_score >= 50 THEN RETURN 'critical';
        WHEN risk_score >= 30 THEN RETURN 'high';
        WHEN risk_score >= 15 THEN RETURN 'medium';
        ELSE RETURN 'low';
    END CASE;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Transaction table partitioning by month
CREATE TABLE transactions PARTITION BY RANGE (transaction_date);

-- Automatic partition creation
CREATE OR REPLACE FUNCTION create_transaction_partition(target_date DATE)
RETURNS VOID AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    start_date := date_trunc('month', target_date);
    end_date := start_date + INTERVAL '1 month';
    partition_name := 'transactions_' || to_char(start_date, 'YYYY_MM');

    EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF transactions
                   FOR VALUES FROM (%L) TO (%L)',
                   partition_name, start_date, end_date);
END;
$$ LANGUAGE plpgsql;
```

### Indexing Strategy
```sql
-- Composite indexes for common queries
CREATE INDEX idx_transactions_account_date ON transactions (account_id, transaction_date DESC);
CREATE INDEX idx_transactions_type_amount ON transactions (transaction_type, amount DESC);
CREATE INDEX idx_accounts_customer_balance ON accounts (customer_id, current_balance DESC);

-- Partial indexes for active records
CREATE INDEX idx_active_accounts ON accounts (account_id) WHERE account_status = 'active';
CREATE INDEX idx_active_loans ON loans (loan_id) WHERE loan_status = 'active';

-- GIN indexes for JSON data
CREATE INDEX idx_accounts_services ON accounts USING gin (enabled_services);
CREATE INDEX idx_cards_location ON card_transactions USING gin (merchant_location);
```

### Materialized Views for Analytics
```sql
-- Daily account activity summary
CREATE MATERIALIZED VIEW daily_account_activity AS
SELECT
    a.account_id,
    DATE_TRUNC('day', t.transaction_date) as activity_date,
    COUNT(*) as transaction_count,
    SUM(t.amount) as total_amount,
    AVG(t.amount) as avg_transaction_amount,
    MIN(t.amount) as min_transaction_amount,
    MAX(t.amount) as max_transaction_amount
FROM accounts a
JOIN transactions t ON a.account_id = t.account_id
WHERE t.transaction_status = 'posted'
  AND t.transaction_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY a.account_id, DATE_TRUNC('day', t.transaction_date);

-- Refresh daily
CREATE INDEX idx_daily_activity_account_date ON daily_account_activity (account_id, activity_date);
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_account_activity;
```

## Security Considerations

### Data Encryption
```sql
-- Sensitive data encryption
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypt card numbers and SSNs
CREATE OR REPLACE FUNCTION encrypt_sensitive_data(plain_text TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(plain_text, current_setting('bank.encryption_key'));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION decrypt_sensitive_data(encrypted_data BYTEA)
RETURNS TEXT AS $$
BEGIN
    RETURN pgp_sym_decrypt(encrypted_data, current_setting('bank.encryption_key'));
END;
$$ LANGUAGE plpgsql;
```

### Row Level Security (RLS)
```sql
-- Enable RLS on sensitive tables
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE cards ENABLE ROW LEVEL SECURITY;

-- Customer data access policy
CREATE POLICY customer_account_access ON accounts
    FOR ALL USING (customer_id = current_setting('app.customer_id')::UUID);

-- Employee access based on role
CREATE POLICY employee_access ON customers
    FOR SELECT USING (
        current_setting('app.employee_role')::TEXT IN ('manager', 'teller', 'admin')
    );
```

### Audit Trail
```sql
-- Comprehensive audit logging
CREATE TABLE audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, session_id, ip_address, user_agent
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### KYC/AML Monitoring
```sql
-- Automated KYC monitoring
CREATE OR REPLACE FUNCTION monitor_kyc_compliance()
RETURNS TABLE (
    customer_id UUID,
    alert_type TEXT,
    alert_severity TEXT,
    alert_description TEXT,
    required_action TEXT
) AS $$
BEGIN
    -- Expired KYC checks
    RETURN QUERY
    SELECT
        c.customer_id,
        'KYC_EXPIRED'::TEXT,
        'HIGH'::TEXT,
        'KYC verification has expired'::TEXT,
        'Require customer to complete KYC verification'::TEXT
    FROM customers c
    WHERE c.kyc_status = 'approved'
      AND c.onboarded_at < CURRENT_DATE - INTERVAL '1 year';

    -- High-risk transactions
    RETURN QUERY
    SELECT
        t.account_id,
        'HIGH_VALUE_TRANSACTION'::TEXT,
        'MEDIUM'::TEXT,
        format('Transaction of $%s detected', t.amount),
        'Review transaction for suspicious activity'::TEXT
    FROM transactions t
    WHERE t.amount > 10000
      AND t.transaction_date = CURRENT_DATE;

    -- Sanctions screening alerts
    RETURN QUERY
    SELECT
        c.customer_id,
        'SANCTIONS_FLAG'::TEXT,
        'CRITICAL'::TEXT,
        'Customer flagged in sanctions screening'::TEXT,
        'Freeze accounts and report to compliance'::TEXT
    FROM customers c
    WHERE c.sanctions_status = 'flagged';
END;
$$ LANGUAGE plpgsql;
```

### Regulatory Reporting
```sql
-- Generate CTR (Currency Transaction Report) data
CREATE OR REPLACE FUNCTION generate_ctr_reports(report_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    customer_id UUID,
    customer_name TEXT,
    total_cash_transactions DECIMAL,
    transaction_count INTEGER,
    report_required BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.customer_id,
        CASE
            WHEN c.customer_type = 'individual' THEN ic.first_name || ' ' || ic.last_name
            ELSE bc.business_name
        END,
        SUM(t.amount) as total_amount,
        COUNT(*) as transaction_count,
        SUM(t.amount) >= 10000 as report_required
    FROM customers c
    LEFT JOIN individual_customers ic ON c.customer_id = ic.customer_id
    LEFT JOIN business_customers bc ON c.customer_id = bc.customer_id
    JOIN accounts a ON c.customer_id = a.customer_id
    JOIN transactions t ON a.account_id = t.account_id
    WHERE t.transaction_date = report_date
      AND t.transaction_type IN ('deposit', 'withdrawal')
      AND t.transaction_channel IN ('branch', 'atm')
    GROUP BY c.customer_id, ic.first_name, ic.last_name, bc.business_name
    HAVING SUM(t.amount) >= 10000;
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Credit bureaus** for credit scoring and reporting
- **Payment processors** for card transaction processing
- **Core banking systems** for account servicing
- **Regulatory agencies** for compliance reporting

### API Endpoints
- **REST APIs** for customer account access
- **Webhooks** for real-time transaction notifications
- **GraphQL APIs** for complex financial queries
- **Bulk APIs** for regulatory reporting

## Monitoring & Analytics

### Key Performance Indicators
- **Transaction volume** and processing times
- **Account opening** and closure rates
- **Loan origination** and default rates
- **Customer acquisition** and retention metrics
- **Compliance violation** rates

### Real-time Dashboards
```sql
-- Banking operations dashboard
CREATE VIEW banking_operations_dashboard AS
SELECT
    -- Transaction metrics
    (SELECT COUNT(*) FROM transactions WHERE transaction_date = CURRENT_DATE) as todays_transactions,
    (SELECT SUM(amount) FROM transactions WHERE transaction_date = CURRENT_DATE) as todays_volume,
    (SELECT AVG(amount) FROM transactions WHERE transaction_date = CURRENT_DATE) as avg_transaction_amount,

    -- Account metrics
    (SELECT COUNT(*) FROM accounts WHERE account_status = 'active') as active_accounts,
    (SELECT COUNT(*) FROM accounts WHERE opened_at >= CURRENT_DATE - INTERVAL '30 days') as new_accounts_this_month,

    -- Loan metrics
    (SELECT COUNT(*) FROM loans WHERE loan_status = 'active') as active_loans,
    (SELECT SUM(current_balance) FROM loans WHERE loan_status = 'active') as total_loan_portfolio,

    -- Risk metrics
    (SELECT COUNT(*) FROM loans WHERE days_past_due > 30) as delinquent_loans,
    (SELECT COUNT(*) FROM compliance_events WHERE resolution_status = 'open') as open_compliance_issues
;
```

This banking database schema provides enterprise-grade financial services infrastructure with comprehensive compliance, security, and performance features required for modern banking operations. 