# Financial Services Schema Design

## Overview

This comprehensive financial services schema supports banking, fintech, payments, and regulatory compliance requirements. The design handles customer management, account processing, transaction management, payment processing, loans, and comprehensive compliance tracking.

## Key Features

- **Multi-Customer Types**: Individual and business customers with KYC compliance
- **Comprehensive Account Management**: Checking, savings, credit cards, loans with complex rules
- **Advanced Transaction Processing**: Multi-currency, real-time processing, fraud detection
- **Payment Processing**: Multiple payment methods, tokenization, dispute management
- **Loan Management**: Full loan lifecycle from application to payoff
- **Regulatory Compliance**: KYC, AML, transaction monitoring, audit trails
- **Risk Management**: Real-time risk scoring, suspicious activity reporting
- **Analytics & Reporting**: Comprehensive financial metrics and reporting

## Database Architecture

### Core Entities

#### Customer Management
```sql
-- Multi-type customer support with KYC
CREATE TABLE customers (
    customer_id UUID PRIMARY KEY,
    customer_type VARCHAR(20), -- 'individual', 'business'
    kyc_status VARCHAR(30), -- 'pending', 'approved', 'rejected'
    risk_rating VARCHAR(10), -- 'low', 'medium', 'high', 'critical'
    -- ... comprehensive customer data
);

-- Address management with verification
CREATE TABLE customer_addresses (
    address_id UUID PRIMARY KEY,
    customer_id UUID REFERENCES customers(customer_id),
    address_type VARCHAR(20), -- 'residential', 'business', 'mailing'
    verification_status VARCHAR(20), -- 'verified', 'pending', 'rejected'
    -- ... complete address with geocoding
);
```

#### Account Management
```sql
-- Flexible account types and products
CREATE TABLE account_types (
    account_type_id SERIAL PRIMARY KEY,
    category VARCHAR(30), -- 'checking', 'savings', 'credit_card', 'loan'
    minimum_balance DECIMAL(15,2),
    interest_rate DECIMAL(5,4),
    monthly_fee DECIMAL(8,2),
    -- ... account rules and limits
);

-- Customer accounts with complex balance tracking
CREATE TABLE accounts (
    account_id UUID PRIMARY KEY,
    account_number VARCHAR(50) UNIQUE,
    customer_id UUID REFERENCES customers(customer_id),
    account_type_id INTEGER REFERENCES account_types(account_type_id),
    current_balance DECIMAL(15,2),
    available_balance DECIMAL(15,2), -- Balance minus holds
    credit_limit DECIMAL(15,2), -- For credit accounts
    -- ... comprehensive account data
);
```

### Transaction Processing

#### Transaction Engine
```sql
-- Comprehensive transaction types
CREATE TABLE transaction_types (
    transaction_type_id SERIAL PRIMARY KEY,
    category VARCHAR(30), -- 'deposit', 'withdrawal', 'transfer', 'payment'
    requires_approval BOOLEAN DEFAULT FALSE,
    daily_limit DECIMAL(12,2),
    -- ... transaction rules
);

-- Core transaction table with partitioning
CREATE TABLE transactions (
    transaction_id UUID PRIMARY KEY,
    transaction_type_id INTEGER REFERENCES transaction_types(transaction_type_id),
    from_account_id UUID REFERENCES accounts(account_id),
    to_account_id UUID REFERENCES accounts(account_id),
    amount DECIMAL(15,2) NOT NULL,
    status VARCHAR(20), -- 'pending', 'completed', 'failed'
    risk_score DECIMAL(5,2),
    fraud_flags JSONB DEFAULT '[]',
    -- ... comprehensive transaction data
) PARTITION BY RANGE (initiated_at);
```

#### Balance Management
```sql
-- Account balance snapshots for performance
CREATE TABLE account_balance_snapshots (
    snapshot_id UUID PRIMARY KEY,
    account_id UUID REFERENCES accounts(account_id),
    balance_date DATE NOT NULL,
    opening_balance DECIMAL(15,2),
    closing_balance DECIMAL(15,2),
    minimum_balance DECIMAL(15,2),
    maximum_balance DECIMAL(15,2),
    -- ... daily balance tracking
    UNIQUE (account_id, balance_date)
) PARTITION BY RANGE (balance_date);
```

### Payment Processing

#### Payment Methods
```sql
-- Multiple payment method support
CREATE TABLE payment_methods (
    payment_method_id UUID PRIMARY KEY,
    customer_id UUID REFERENCES customers(customer_id),
    type VARCHAR(20), -- 'credit_card', 'bank_account', 'digital_wallet'
    provider VARCHAR(50), -- 'stripe', 'paypal'
    provider_token VARCHAR(255), -- PCI-compliant tokenization
    is_default BOOLEAN DEFAULT FALSE,
    -- ... payment method details
);

-- Payment intents for processing
CREATE TABLE payment_intents (
    payment_intent_id UUID PRIMARY KEY,
    customer_id UUID REFERENCES customers(customer_id),
    amount DECIMAL(15,2),
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(20), -- 'pending', 'succeeded', 'failed'
    provider_intent_id VARCHAR(255),
    -- ... payment processing data
);
```

#### Dispute Management
```sql
-- Chargeback and dispute handling
CREATE TABLE payment_disputes (
    dispute_id UUID PRIMARY KEY,
    payment_intent_id UUID REFERENCES payment_intents(payment_intent_id),
    reason VARCHAR(50), -- 'fraudulent', 'duplicate', 'product_not_received'
    status VARCHAR(20), -- 'needs_response', 'won', 'lost'
    amount DECIMAL(15,2),
    customer_evidence JSONB DEFAULT '{}',
    -- ... dispute resolution data
);
```

### Cards & Digital Wallets

#### Card Management
```sql
-- Physical and virtual card support
CREATE TABLE cards (
    card_id UUID PRIMARY KEY,
    account_id UUID REFERENCES accounts(account_id),
    card_number_hash VARCHAR(128),
    card_brand VARCHAR(20),
    expiry_month INTEGER,
    expiry_year INTEGER,
    status VARCHAR(20), -- 'active', 'blocked', 'expired'
    pin_hash VARCHAR(255),
    -- ... card security and limits
);

-- Detailed card transaction tracking
CREATE TABLE card_transactions (
    card_transaction_id UUID PRIMARY KEY,
    card_id UUID REFERENCES cards(card_id),
    merchant_name VARCHAR(255),
    transaction_amount DECIMAL(12,2),
    billing_amount DECIMAL(12,2),
    is_international BOOLEAN DEFAULT FALSE,
    risk_score DECIMAL(5,2),
    -- ... comprehensive card transaction data
);
```

### Loan Management

#### Loan Products
```sql
-- Configurable loan products
CREATE TABLE loan_products (
    loan_product_id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    loan_type VARCHAR(30), -- 'personal', 'mortgage', 'business'
    min_amount DECIMAL(15,2),
    max_amount DECIMAL(15,2),
    base_interest_rate DECIMAL(5,4),
    min_term_months INTEGER,
    max_term_months INTEGER,
    -- ... loan terms and fees
);

-- Loan application process
CREATE TABLE loan_applications (
    application_id UUID PRIMARY KEY,
    customer_id UUID REFERENCES customers(customer_id),
    loan_product_id INTEGER REFERENCES loan_products(loan_product_id),
    requested_amount DECIMAL(15,2),
    status VARCHAR(20), -- 'draft', 'approved', 'rejected'
    risk_score DECIMAL(5,2),
    -- ... application and approval data
);
```

#### Active Loans
```sql
-- Loan lifecycle management
CREATE TABLE loans (
    loan_id UUID PRIMARY KEY,
    application_id UUID REFERENCES loan_applications(application_id),
    loan_amount DECIMAL(15,2),
    principal_balance DECIMAL(15,2),
    interest_rate DECIMAL(5,4),
    monthly_payment DECIMAL(10,2),
    status VARCHAR(20), -- 'active', 'paid_off', 'defaulted'
    -- ... comprehensive loan data
);

-- Payment tracking
CREATE TABLE loan_payments (
    loan_payment_id UUID PRIMARY KEY,
    loan_id UUID REFERENCES loans(loan_id),
    payment_amount DECIMAL(10,2),
    principal_paid DECIMAL(12,2),
    interest_paid DECIMAL(10,2),
    payment_type VARCHAR(20), -- 'scheduled', 'extra', 'late'
    -- ... payment allocation data
);
```

### Compliance & Regulatory

#### KYC & AML
```sql
-- Document verification
CREATE TABLE kyc_documents (
    document_id UUID PRIMARY KEY,
    customer_id UUID REFERENCES customers(customer_id),
    document_type VARCHAR(50), -- 'passport', 'drivers_license'
    verification_status VARCHAR(20), -- 'verified', 'pending'
    document_urls JSONB DEFAULT '[]',
    extracted_data JSONB DEFAULT '{}',
    -- ... document verification data
);

-- Suspicious activity reporting
CREATE TABLE suspicious_activity_reports (
    sar_id UUID PRIMARY KEY,
    customer_id UUID REFERENCES customers(customer_id),
    report_type VARCHAR(50), -- 'money_laundering', 'fraud'
    severity VARCHAR(10), -- 'low', 'medium', 'high', 'critical'
    indicators JSONB NOT NULL, -- Red flags identified
    investigation_status VARCHAR(20), -- 'open', 'closed'
    -- ... SAR management data
);
```

#### Transaction Monitoring
```sql
-- Automated monitoring rules
CREATE TABLE monitoring_rules (
    rule_id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    conditions JSONB NOT NULL, -- Complex rule logic
    severity VARCHAR(10),
    actions JSONB NOT NULL, -- Actions to take when triggered
    -- ... rule management data
);
```

## Advanced Features

### Real-Time Risk Scoring

```sql
-- Transaction risk assessment
CREATE OR REPLACE FUNCTION calculate_transaction_risk()
RETURNS TRIGGER AS $$
DECLARE
    risk_factors INTEGER := 0;
    customer_record customers%ROWTYPE;
BEGIN
    -- Get customer risk profile
    SELECT c.* INTO customer_record
    FROM accounts a
    JOIN customers c ON a.customer_id = c.customer_id
    WHERE a.account_id = COALESCE(NEW.from_account_id, NEW.to_account_id);

    -- Risk factor calculation
    IF customer_record.kyc_status != 'approved' THEN risk_factors := risk_factors + 2; END IF;
    IF NEW.amount > 10000 THEN risk_factors := risk_factors + 1; END IF;
    IF NEW.metadata->>'international' = 'true' THEN risk_factors := risk_factors + 1; END IF;

    -- Calculate risk score
    NEW.risk_score := LEAST(risk_factors * 2.0, 10.0);

    -- Flag high-risk transactions
    IF NEW.risk_score >= 7.0 THEN
        NEW.fraud_flags := array_append(NEW.fraud_flags, 'high_risk_transaction');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calculate_transaction_risk
    BEFORE INSERT ON transactions
    FOR EACH ROW EXECUTE FUNCTION calculate_transaction_risk();
```

### Automated Account Number Generation

```sql
-- Auto-generate account numbers by type
CREATE OR REPLACE FUNCTION generate_account_number()
RETURNS TRIGGER AS $$
DECLARE
    account_prefix VARCHAR(3);
    next_sequence INTEGER;
BEGIN
    -- Generate prefix based on account type
    SELECT CASE
        WHEN at.category = 'checking' THEN 'CHK'
        WHEN at.category = 'savings' THEN 'SAV'
        WHEN at.category = 'credit_card' THEN 'CRD'
        WHEN at.category = 'loan' THEN 'LON'
        ELSE 'ACC'
    END INTO account_prefix
    FROM account_types at
    WHERE at.account_type_id = NEW.account_type_id;

    -- Generate account number
    SELECT COALESCE(MAX(CAST(SUBSTRING(account_number FROM 4) AS INTEGER)), 0) + 1
    INTO next_sequence
    FROM accounts
    WHERE account_number LIKE account_prefix || '%';

    NEW.account_number := account_prefix || LPAD(next_sequence::TEXT, 8, '0');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_account_number
    BEFORE INSERT ON accounts
    FOR EACH ROW
    WHEN (NEW.account_number IS NULL)
    EXECUTE FUNCTION generate_account_number();
```

### Balance Auto-Updates

```sql
-- Auto-update account balances on transactions
CREATE OR REPLACE FUNCTION update_account_balance()
RETURNS TRIGGER AS $$
BEGIN
    -- Update from account (debit)
    IF NEW.from_account_id IS NOT NULL AND NEW.status = 'completed' THEN
        UPDATE accounts
        SET current_balance = current_balance - NEW.amount,
            available_balance = available_balance - NEW.amount,
            last_activity_at = CURRENT_TIMESTAMP
        WHERE account_id = NEW.from_account_id;
    END IF;

    -- Update to account (credit)
    IF NEW.to_account_id IS NOT NULL AND NEW.status = 'completed' THEN
        UPDATE accounts
        SET current_balance = current_balance + NEW.amount,
            available_balance = available_balance + NEW.amount,
            last_activity_at = CURRENT_TIMESTAMP
        WHERE account_id = NEW.to_account_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_account_balance
    AFTER INSERT OR UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_account_balance();
```

## Usage Examples

### Account Opening Process

```sql
-- Complete account opening with KYC
BEGIN;

-- Create customer
INSERT INTO customers (
    customer_type, first_name, last_name, email, date_of_birth, kyc_status
) VALUES (
    'individual', 'John', 'Doe', 'john.doe@email.com', '1985-03-15', 'pending'
) RETURNING customer_id INTO customer_id_var;

-- Add address for verification
INSERT INTO customer_addresses (
    customer_id, address_type, street_address, city, state, postal_code
) VALUES (
    customer_id_var, 'residential', '123 Main St', 'Anytown', 'CA', '12345'
);

-- Create account (account number auto-generated)
INSERT INTO accounts (customer_id, account_type_id)
SELECT customer_id_var, account_type_id
FROM account_types WHERE code = 'CHK001';

COMMIT;
```

### Transaction Processing

```sql
-- Process a transfer between accounts
BEGIN;

-- Check transaction limits
SELECT * FROM check_transaction_limits(customer_id, 'transfer', 500.00);

-- Create transaction record
INSERT INTO transactions (
    transaction_type_id, from_account_id, to_account_id,
    amount, description, reference_number
) VALUES (
    (SELECT transaction_type_id FROM transaction_types WHERE code = 'transfer'),
    'from-account-uuid', 'to-account-uuid',
    500.00, 'Transfer to savings', 'TXN-' || gen_random_uuid()
) RETURNING transaction_id INTO txn_id;

-- Update transaction status (would be done by background processor)
UPDATE transactions
SET status = 'completed', processed_at = CURRENT_TIMESTAMP,
    completed_at = CURRENT_TIMESTAMP
WHERE transaction_id = txn_id;

COMMIT;
```

### Loan Application & Approval

```sql
-- Submit loan application
INSERT INTO loan_applications (
    customer_id, loan_product_id, requested_amount, requested_term_months,
    annual_income, credit_score, purpose
) VALUES (
    'customer-uuid', 1, 25000.00, 60, 75000.00, 720, 'Home improvement'
) RETURNING application_id INTO app_id;

-- Approve and create loan (done by loan officer)
UPDATE loan_applications
SET status = 'approved', approved_at = CURRENT_TIMESTAMP
WHERE application_id = app_id;

-- Create loan account and loan record
INSERT INTO accounts (customer_id, account_type_id, account_number)
SELECT customer_id, account_type_id, 'LON-' || gen_random_uuid()
FROM loan_applications la
JOIN account_types at ON at.category = 'loan'
WHERE la.application_id = app_id
RETURNING account_id INTO loan_account_id;

INSERT INTO loans (
    application_id, account_id, loan_amount, term_months, interest_rate
) SELECT application_id, loan_account_id, requested_amount, requested_term_months,
         (SELECT base_interest_rate FROM loan_products WHERE loan_product_id = la.loan_product_id)
FROM loan_applications la WHERE application_id = app_id;
```

### Payment Processing

```sql
-- Process credit card payment
INSERT INTO payment_intents (
    customer_id, amount, currency, description, payment_method_id
) VALUES (
    'customer-uuid', 99.99, 'USD', 'Monthly subscription',
    'payment-method-uuid'
) RETURNING payment_intent_id INTO intent_id;

-- Create transaction record
INSERT INTO transactions (
    transaction_type_id, from_account_id, amount, description,
    payment_intent_id, status
) VALUES (
    (SELECT transaction_type_id FROM transaction_types WHERE code = 'payment'),
    'customer-account-uuid', 99.99, 'Subscription payment',
    intent_id, 'completed'
);
```

## Performance Optimizations

### Partitioning Strategy

```sql
-- Monthly transaction partitions
CREATE TABLE transactions PARTITION BY RANGE (initiated_at);

CREATE TABLE transactions_2024_01 PARTITION OF transactions
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Daily balance snapshots
CREATE TABLE account_balance_snapshots PARTITION BY RANGE (balance_date);

CREATE TABLE balance_snapshots_2024 PARTITION OF account_balance_snapshots
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### Key Indexes

```sql
-- Core performance indexes
CREATE INDEX idx_accounts_customer ON accounts (customer_id);
CREATE INDEX idx_accounts_number ON accounts (account_number);
CREATE INDEX idx_transactions_accounts ON transactions (from_account_id, to_account_id);
CREATE INDEX idx_transactions_date ON transactions (initiated_at);
CREATE INDEX idx_transactions_reference ON transactions (reference_number);
CREATE INDEX idx_payment_intents_customer ON payment_intents (customer_id);
CREATE INDEX idx_cards_account ON cards (account_id);
```

### Query Optimization

```sql
-- Efficient balance calculation
CREATE VIEW account_current_balance AS
SELECT
    a.account_id,
    a.account_number,
    a.current_balance,
    a.available_balance,
    COUNT(t.transaction_id) AS recent_transactions,
    MAX(t.completed_at) AS last_transaction_date
FROM accounts a
LEFT JOIN transactions t ON (t.from_account_id = a.account_id OR t.to_account_id = a.account_id)
    AND t.completed_at >= CURRENT_DATE - INTERVAL '30 days'
    AND t.status = 'completed'
GROUP BY a.account_id, a.account_number, a.current_balance, a.available_balance;

-- Customer risk profile
CREATE VIEW customer_risk_profile AS
SELECT
    c.customer_id,
    c.risk_rating,
    COUNT(CASE WHEN t.risk_score >= 7 THEN 1 END) AS high_risk_transactions,
    COUNT(CASE WHEN sar.sar_id IS NOT NULL THEN 1 END) AS suspicious_reports,
    AVG(t.risk_score) AS avg_transaction_risk,
    MAX(t.completed_at) AS last_transaction_date
FROM customers c
LEFT JOIN accounts a ON c.customer_id = a.customer_id
LEFT JOIN transactions t ON (t.from_account_id = a.account_id OR t.to_account_id = a.account_id)
    AND t.completed_at >= CURRENT_DATE - INTERVAL '90 days'
LEFT JOIN suspicious_activity_reports sar ON c.customer_id = sar.customer_id
    AND sar.created_at >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY c.customer_id, c.risk_rating;
```

## Security Considerations

### Data Encryption

```sql
-- Encrypt sensitive fields
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypted storage for sensitive data
CREATE TABLE encrypted_customer_data (
    customer_id UUID PRIMARY KEY REFERENCES customers(customer_id),
    encrypted_ssn BYTEA, -- Encrypted SSN
    encryption_key_hash VARCHAR(128),
    encrypted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### Row-Level Security

```sql
-- Multi-tenant data isolation
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY account_owner_policy ON accounts
    FOR ALL USING (customer_id = current_user_id());

-- Branch-level access for employees
CREATE POLICY branch_access_policy ON accounts
    FOR SELECT USING (
        branch_id IN (
            SELECT branch_id FROM employee_branches
            WHERE employee_id = current_employee_id()
        )
    );
```

### Audit Trails

```sql
-- Comprehensive audit logging
CREATE TABLE audit_log (
    audit_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    changed_by UUID,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Auto-audit trigger
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, record_id, operation, old_values, new_values, changed_by)
    VALUES (TG_TABLE_NAME, NEW.id, TG_OP, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb, current_user_id());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

## Regulatory Compliance

### KYC Process

```sql
-- KYC document verification workflow
CREATE TABLE kyc_verification_queue (
    queue_id SERIAL PRIMARY KEY,
    customer_id UUID REFERENCES customers(customer_id),
    document_type VARCHAR(50),
    priority VARCHAR(10) DEFAULT 'normal', -- 'low', 'normal', 'high', 'urgent'
    assigned_to UUID, -- Verification agent
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE
);

-- Automated KYC scoring
CREATE OR REPLACE FUNCTION calculate_kyc_score(customer_uuid UUID)
RETURNS DECIMAL(5,2) AS $$
DECLARE
    score DECIMAL(5,2) := 0;
    doc_count INTEGER;
    verified_count INTEGER;
BEGIN
    -- Count verified documents
    SELECT COUNT(*), COUNT(CASE WHEN verification_status = 'verified' THEN 1 END)
    INTO doc_count, verified_count
    FROM kyc_documents
    WHERE customer_id = customer_uuid;

    -- Base score on verification rate
    IF doc_count > 0 THEN
        score := (verified_count::DECIMAL / doc_count) * 100;
    END IF;

    -- Additional scoring factors
    IF EXISTS (SELECT 1 FROM customer_addresses WHERE customer_id = customer_uuid AND verification_status = 'verified') THEN
        score := score + 10;
    END IF;

    RETURN LEAST(score, 100.00);
END;
$$ LANGUAGE plpgsql;
```

### AML Monitoring

```sql
-- Automated transaction monitoring
CREATE OR REPLACE FUNCTION monitor_transaction_for_aml()
RETURNS TRIGGER AS $$
DECLARE
    customer_record customers%ROWTYPE;
    velocity_score DECIMAL(5,2) := 0;
    amount_score DECIMAL(5,2) := 0;
BEGIN
    -- Get customer details
    SELECT c.* INTO customer_record
    FROM accounts a
    JOIN customers c ON a.customer_id = c.customer_id
    WHERE a.account_id = COALESCE(NEW.from_account_id, NEW.to_account_id);

    -- Velocity check (transactions in last 24 hours)
    SELECT COUNT(*) * 10 INTO velocity_score
    FROM transactions
    WHERE (from_account_id = COALESCE(NEW.from_account_id, NEW.to_account_id) OR
           to_account_id = COALESCE(NEW.from_account_id, NEW.to_account_id))
      AND initiated_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
      AND status = 'completed';

    -- Amount threshold check
    IF NEW.amount > 10000 THEN
        amount_score := 20;
    ELSIF NEW.amount > 50000 THEN
        amount_score := 50;
    END IF;

    -- Flag suspicious transactions
    IF velocity_score + amount_score > 30 THEN
        INSERT INTO suspicious_activity_reports (
            customer_id, account_id, transaction_id,
            report_type, severity, description
        ) VALUES (
            customer_record.customer_id,
            COALESCE(NEW.from_account_id, NEW.to_account_id),
            NEW.transaction_id,
            'unusual_activity',
            CASE WHEN velocity_score + amount_score > 50 THEN 'high' ELSE 'medium' END,
            'Suspicious transaction pattern detected'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_aml_monitoring
    AFTER INSERT ON transactions
    FOR EACH ROW EXECUTE FUNCTION monitor_transaction_for_aml();
```

## Integration Points

### External Systems
- **Payment networks** (Visa, Mastercard, ACH) for transaction processing and settlement
- **Credit bureaus** (Experian, Equifax, TransUnion) for credit scoring and reporting
- **Regulatory systems** (FINRA, SEC, FDIC) for compliance reporting and oversight
- **Fraud detection services** for real-time transaction monitoring and risk assessment
- **KYC/AML providers** for identity verification and sanctions screening
- **Banking APIs** for account verification and balance checks
- **Market data feeds** for investment and trading platforms

### API Endpoints
- **Transaction processing APIs** for payments, transfers, and settlements
- **Account management APIs** for balance inquiries and account operations
- **Compliance APIs** for regulatory reporting and audit trails
- **Risk assessment APIs** for fraud detection and AML monitoring
- **Customer service APIs** for support ticket management and resolution
- **Analytics APIs** for financial reporting and business intelligence

## Monitoring & Analytics

### Key Performance Indicators
- **Transaction volume and success rates** (daily/monthly transaction counts, failure rates)
- **Customer acquisition and retention** (account openings, churn rates, lifetime value)
- **Financial performance** (revenue, profit margins, cost per transaction)
- **Risk metrics** (fraud rates, chargeback ratios, compliance violations)
- **Operational efficiency** (processing times, uptime, customer satisfaction)

### Real-Time Dashboards
```sql
-- Financial services analytics dashboard
CREATE VIEW financial_services_dashboard AS
SELECT
    -- Transaction metrics (today)
    (SELECT COUNT(*) FROM transactions WHERE DATE(initiated_at) = CURRENT_DATE) as transactions_today,
    (SELECT SUM(amount) FROM transactions WHERE DATE(initiated_at) = CURRENT_DATE AND status = 'completed') as transaction_volume_today,
    (SELECT AVG(amount) FROM transactions WHERE DATE(initiated_at) = CURRENT_DATE AND status = 'completed') as avg_transaction_amount_today,
    (SELECT COUNT(*) FROM transactions WHERE DATE(initiated_at) = CURRENT_DATE AND status = 'failed')::DECIMAL /
    NULLIF((SELECT COUNT(*) FROM transactions WHERE DATE(initiated_at) = CURRENT_DATE), 0) * 100 as transaction_failure_rate_percent,

    -- Account metrics
    (SELECT COUNT(*) FROM accounts WHERE account_status = 'active') as active_accounts,
    (SELECT COUNT(*) FROM account_openings WHERE DATE(opened_at) >= CURRENT_DATE - INTERVAL '30 days') as accounts_opened_month,
    (SELECT SUM(current_balance) FROM accounts WHERE account_status = 'active') as total_deposits,

    -- Payment processing
    (SELECT COUNT(*) FROM payment_intents WHERE DATE(created_at) = CURRENT_DATE) as payment_intents_today,
    (SELECT COUNT(*) FROM payment_intents WHERE DATE(created_at) = CURRENT_DATE AND status = 'succeeded')::DECIMAL /
    NULLIF((SELECT COUNT(*) FROM payment_intents WHERE DATE(created_at) = CURRENT_DATE), 0) * 100 as payment_success_rate_percent,

    -- Fraud and security
    (SELECT COUNT(*) FROM suspicious_activity_reports WHERE DATE(created_at) = CURRENT_DATE) as fraud_alerts_today,
    (SELECT COUNT(*) FROM chargebacks WHERE DATE(processed_at) >= CURRENT_DATE - INTERVAL '30 days') as chargebacks_month,
    (SELECT COUNT(*) FROM compliance_violations WHERE DATE(detected_at) >= CURRENT_DATE - INTERVAL '30 days') as compliance_violations_month,

    -- Customer service
    (SELECT COUNT(*) FROM support_tickets WHERE ticket_status = 'open') as open_support_tickets,
    (SELECT AVG(EXTRACT(EPOCH FROM (resolved_at - created_at))/3600)
     FROM support_tickets WHERE resolved_at IS NOT NULL AND created_at >= CURRENT_DATE - INTERVAL '30 days') as avg_resolution_time_hours,

    -- Revenue metrics
    (SELECT COALESCE(SUM(fee_amount), 0) FROM transaction_fees WHERE DATE(fee_date) >= CURRENT_DATE - INTERVAL '30 days') as revenue_month,
    (SELECT COALESCE(SUM(interest_amount), 0) FROM interest_accruals WHERE DATE(accrual_date) >= CURRENT_DATE - INTERVAL '30 days') as interest_income_month,

    -- Regulatory compliance
    (SELECT COUNT(*) FROM regulatory_reports WHERE DATE(submitted_at) >= CURRENT_DATE - INTERVAL '7 days') as reports_submitted_week,
    (SELECT COUNT(*) FROM audit_logs WHERE DATE(created_at) >= CURRENT_DATE - INTERVAL '7 days') as audit_events_week,

    -- Performance metrics
    (SELECT AVG(EXTRACT(EPOCH FROM (completed_at - initiated_at)))
     FROM transactions WHERE completed_at IS NOT NULL AND initiated_at >= CURRENT_DATE - INTERVAL '7 days') as avg_processing_time_seconds,
    (SELECT COUNT(*) FROM system_alerts WHERE alert_status = 'active') as active_system_alerts

FROM dual; -- Use a dummy table for single-row result
```

This financial services schema provides a solid foundation for building secure, compliant, and scalable banking and fintech applications that meet regulatory requirements and support complex financial operations.
