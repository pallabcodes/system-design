-- Banking & Financial Services Database Schema
-- Comprehensive schema for retail and commercial banking operations

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- CUSTOMERS AND ACCOUNTS
-- ===========================================

CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_type VARCHAR(20) NOT NULL CHECK (customer_type IN ('individual', 'business', 'non_profit', 'government')),

    -- Personal/Business Information
    tax_id VARCHAR(20) UNIQUE, -- SSN/EIN encrypted
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),

    -- Status and Risk
    customer_status VARCHAR(20) DEFAULT 'active' CHECK (customer_status IN ('active', 'inactive', 'suspended', 'closed')),
    risk_rating VARCHAR(10) CHECK (risk_rating IN ('low', 'medium', 'high', 'critical')),
    kyc_status VARCHAR(20) DEFAULT 'pending' CHECK (kyc_status IN ('pending', 'in_review', 'approved', 'rejected', 'expired')),

    -- Regulatory Compliance
    pep_status BOOLEAN DEFAULT FALSE, -- Politically Exposed Person
    sanctions_check_date DATE,
    sanctions_status VARCHAR(20) DEFAULT 'cleared' CHECK (sanctions_status IN ('cleared', 'flagged', 'blocked')),

    -- Account Management
    onboarded_at TIMESTAMP WITH TIME ZONE,
    relationship_manager_id UUID, -- References employees
    branch_id UUID, -- References branches

    -- Preferences
    preferred_language VARCHAR(10) DEFAULT 'en',
    communication_preferences JSONB DEFAULT '{"email": true, "sms": false, "push": true}',

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID
);

-- Individual customer details
CREATE TABLE individual_customers (
    customer_id UUID PRIMARY KEY REFERENCES customers(customer_id) ON DELETE CASCADE,

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(20),
    marital_status VARCHAR(20) CHECK (marital_status IN ('single', 'married', 'divorced', 'widowed')),

    -- Identification
    ssn_encrypted BYTEA, -- Encrypted SSN
    drivers_license VARCHAR(50),
    passport_number VARCHAR(50),

    -- Address
    residential_address JSONB, -- Full address structure
    mailing_address JSONB,    -- May differ from residential

    -- Employment
    employment_status VARCHAR(30) CHECK (employment_status IN ('employed', 'self_employed', 'unemployed', 'student', 'retired', 'homemaker')),
    employer_name VARCHAR(255),
    job_title VARCHAR(100),
    annual_income DECIMAL(15,2),

    -- Additional Details
    citizenship VARCHAR(100),
    residency_status VARCHAR(50) DEFAULT 'citizen' CHECK (residency_status IN ('citizen', 'permanent_resident', 'visa', 'undocumented')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Business customer details
CREATE TABLE business_customers (
    customer_id UUID PRIMARY KEY REFERENCES customers(customer_id) ON DELETE CASCADE,

    -- Business Information
    business_name VARCHAR(255) NOT NULL,
    legal_business_name VARCHAR(255),
    business_type VARCHAR(50) CHECK (business_type IN ('corporation', 'llc', 'partnership', 'sole_proprietorship', 'non_profit', 'government')),
    industry VARCHAR(100),
    business_description TEXT,

    -- Registration
    ein VARCHAR(20) UNIQUE, -- Employer Identification Number
    state_of_incorporation VARCHAR(50),
    date_of_incorporation DATE,

    -- Financial Information
    annual_revenue DECIMAL(15,2),
    number_of_employees INTEGER,

    -- Authorized Signers
    authorized_signers JSONB DEFAULT '[]', -- Array of authorized individuals

    -- Business Address
    business_address JSONB,
    mailing_address JSONB,

    -- Contact Information
    primary_contact_name VARCHAR(200),
    primary_contact_title VARCHAR(100),
    primary_contact_phone VARCHAR(20),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ACCOUNT MANAGEMENT
-- ===========================================

CREATE TABLE accounts (
    account_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Account Details
    account_number VARCHAR(20) UNIQUE NOT NULL,
    account_type VARCHAR(30) NOT NULL CHECK (account_type IN (
        'checking', 'savings', 'money_market', 'cd', 'ira', 'business_checking',
        'business_savings', 'commercial_loan', 'personal_loan', 'mortgage', 'credit_card'
    )),
    account_subtype VARCHAR(50), -- Specific product variant

    -- Status and Lifecycle
    account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN ('pending', 'active', 'frozen', 'closed', 'suspended')),
    opened_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP WITH TIME ZONE,

    -- Financial Details
    currency_code CHAR(3) DEFAULT 'USD',
    current_balance DECIMAL(15,2) DEFAULT 0,
    available_balance DECIMAL(15,2) DEFAULT 0,
    minimum_balance DECIMAL(12,2) DEFAULT 0,

    -- Interest and Fees
    interest_rate DECIMAL(5,4) DEFAULT 0, -- Annual percentage
    interest_accrued DECIMAL(12,2) DEFAULT 0,
    monthly_fee DECIMAL(8,2) DEFAULT 0,
    overdraft_limit DECIMAL(10,2) DEFAULT 0,

    -- Linked Accounts and Services
    linked_accounts JSONB DEFAULT '[]', -- Linked external accounts
    enabled_services JSONB DEFAULT '{}', -- Enabled features like bill_pay, wire_transfers

    -- Access Control
    primary_owner_id UUID REFERENCES individual_customers(customer_id),
    authorized_signers JSONB DEFAULT '[]', -- Additional authorized users

    -- Branch and Relationship
    branch_id UUID,
    relationship_manager_id UUID,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (current_balance >= -overdraft_limit),
    CHECK (available_balance <= current_balance + overdraft_limit)
);

-- Account holders (for joint accounts)
CREATE TABLE account_holders (
    account_holder_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Authorization Level
    authorization_level VARCHAR(20) DEFAULT 'view' CHECK (authorization_level IN ('owner', 'authorized_signer', 'view_only')),
    ownership_percentage DECIMAL(5,2), -- For business accounts

    -- Access Permissions
    can_transact BOOLEAN DEFAULT FALSE,
    can_transfer BOOLEAN DEFAULT FALSE,
    transaction_limit DECIMAL(12,2),

    -- Status
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'revoked')),

    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    added_by UUID,

    UNIQUE (account_id, customer_id)
);

-- ===========================================
-- TRANSACTIONS AND LEDGER
-- ===========================================

CREATE TABLE transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES accounts(account_id),

    -- Transaction Details
    transaction_type VARCHAR(30) NOT NULL CHECK (transaction_type IN (
        'deposit', 'withdrawal', 'transfer', 'fee', 'interest', 'payment',
        'check', 'atm', 'pos', 'online', 'wire', 'ach', 'bill_pay'
    )),
    transaction_subtype VARCHAR(50), -- More specific categorization

    -- Amounts
    amount DECIMAL(12,2) NOT NULL,
    fee_amount DECIMAL(8,2) DEFAULT 0,
    net_amount DECIMAL(12,2) GENERATED ALWAYS AS (amount - fee_amount) STORED,

    -- Counterparty Information
    counterparty_account_id UUID REFERENCES accounts(account_id),
    counterparty_name VARCHAR(255),
    counterparty_account_number VARCHAR(50),

    -- Transaction Metadata
    transaction_date DATE DEFAULT CURRENT_DATE,
    posted_date DATE,
    effective_date DATE DEFAULT CURRENT_DATE,
    value_date DATE DEFAULT CURRENT_DATE, -- Date when funds become available

    -- Reference Information
    reference_number VARCHAR(100) UNIQUE,
    external_reference VARCHAR(100), -- Third-party reference
    memo TEXT,

    -- Channel and Location
    transaction_channel VARCHAR(30) DEFAULT 'branch' CHECK (transaction_channel IN (
        'branch', 'atm', 'online', 'mobile', 'phone', 'api', 'check', 'wire'
    )),
    location_details JSONB, -- ATM location, IP address, etc.

    -- Status and Processing
    transaction_status VARCHAR(20) DEFAULT 'posted' CHECK (transaction_status IN (
        'pending', 'posted', 'failed', 'reversed', 'disputed'
    )),
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Regulatory Reporting
    regulatory_category VARCHAR(50),
    reportable BOOLEAN DEFAULT FALSE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,

    -- Constraints
    CHECK (amount > 0),
    CHECK (fee_amount >= 0),
    CHECK (transaction_date <= CURRENT_DATE)
) PARTITION BY RANGE (transaction_date);

-- Transaction partitions (monthly)
CREATE TABLE transactions_2024_01 PARTITION OF transactions
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE transactions_2024_02 PARTITION OF transactions
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- ===========================================
-- CARDS AND PAYMENTS
-- ===========================================

CREATE TABLE cards (
    card_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Card Details
    card_number_encrypted BYTEA NOT NULL, -- Encrypted card number
    card_type VARCHAR(20) NOT NULL CHECK (card_type IN ('debit', 'credit', 'atm', 'prepaid')),
    card_network VARCHAR(20) CHECK (card_network IN ('visa', 'mastercard', 'amex', 'discover')),

    -- Physical Card
    card_design VARCHAR(50),
    embossed_name VARCHAR(100),
    expiration_date DATE NOT NULL,

    -- Virtual Card (for digital wallets)
    is_virtual BOOLEAN DEFAULT FALSE,
    virtual_card_url VARCHAR(500),

    -- Status and Lifecycle
    card_status VARCHAR(20) DEFAULT 'active' CHECK (card_status IN ('active', 'inactive', 'blocked', 'expired', 'lost', 'stolen')),
    issued_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    activated_at TIMESTAMP WITH TIME ZONE,
    expired_at TIMESTAMP WITH TIME ZONE,

    -- Limits and Controls
    daily_limit DECIMAL(10,2),
    transaction_limit DECIMAL(8,2),
    atm_limit DECIMAL(8,2),
    international_allowed BOOLEAN DEFAULT TRUE,

    -- Security Features
    pin_required BOOLEAN DEFAULT TRUE,
    chip_enabled BOOLEAN DEFAULT TRUE,
    contactless_enabled BOOLEAN DEFAULT TRUE,
    biometric_enabled BOOLEAN DEFAULT FALSE,

    -- Rewards (for credit cards)
    rewards_program VARCHAR(50),
    rewards_balance DECIMAL(10,2) DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (expiration_date > CURRENT_DATE)
);

-- Card transactions
CREATE TABLE card_transactions (
    card_transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id UUID NOT NULL REFERENCES cards(card_id),
    transaction_id UUID NOT NULL REFERENCES transactions(transaction_id),

    -- Card-specific Details
    merchant_name VARCHAR(255),
    merchant_category_code VARCHAR(10),
    merchant_location JSONB, -- City, country, coordinates
    pos_entry_mode VARCHAR(20), -- Chip, swipe, contactless, manual

    -- Authorization Details
    authorization_code VARCHAR(20),
    response_code VARCHAR(3), -- ISO 8583 response code

    -- Fraud Detection
    fraud_score DECIMAL(5,2),
    fraud_flags JSONB DEFAULT '[]',

    -- Settlement
    settlement_date DATE,
    interchange_fee DECIMAL(6,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- LOANS AND CREDIT
-- ===========================================

CREATE TABLE loans (
    loan_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),
    account_id UUID REFERENCES accounts(account_id), -- Linked account for payments

    -- Loan Details
    loan_type VARCHAR(30) NOT NULL CHECK (loan_type IN (
        'personal', 'auto', 'mortgage', 'business', 'student', 'home_equity', 'credit_line'
    )),
    loan_number VARCHAR(20) UNIQUE NOT NULL,

    -- Financial Terms
    principal_amount DECIMAL(15,2) NOT NULL,
    interest_rate DECIMAL(5,4) NOT NULL,
    term_months INTEGER NOT NULL,
    origination_fee DECIMAL(8,2) DEFAULT 0,

    -- Outstanding Balances
    current_balance DECIMAL(15,2) NOT NULL,
    principal_paid DECIMAL(15,2) DEFAULT 0,
    interest_paid DECIMAL(15,2) DEFAULT 0,

    -- Payment Schedule
    payment_frequency VARCHAR(20) DEFAULT 'monthly' CHECK (payment_frequency IN ('weekly', 'biweekly', 'monthly', 'quarterly')),
    next_payment_date DATE,
    payment_amount DECIMAL(10,2), -- Calculated monthly payment
    remaining_payments INTEGER,

    -- Status and Lifecycle
    loan_status VARCHAR(20) DEFAULT 'active' CHECK (loan_status IN ('application', 'approved', 'funded', 'active', 'paid_off', 'defaulted', 'foreclosed')),
    origination_date DATE DEFAULT CURRENT_DATE,
    maturity_date DATE,
    paid_off_date DATE,

    -- Collateral (for secured loans)
    collateral_type VARCHAR(50),
    collateral_value DECIMAL(15,2),
    collateral_description TEXT,

    -- Risk Assessment
    credit_score_at_origination INTEGER,
    debt_to_income_ratio DECIMAL(5,2),
    loan_to_value_ratio DECIMAL(5,2), -- For mortgages

    -- Servicing
    servicing_officer_id UUID,
    last_payment_date DATE,
    days_past_due INTEGER DEFAULT 0,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (principal_amount > 0),
    CHECK (interest_rate >= 0 AND interest_rate <= 1),
    CHECK (current_balance >= 0)
);

-- Loan payments
CREATE TABLE loan_payments (
    payment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    loan_id UUID NOT NULL REFERENCES loans(loan_id),
    transaction_id UUID REFERENCES transactions(transaction_id),

    -- Payment Details
    payment_date DATE DEFAULT CURRENT_DATE,
    payment_amount DECIMAL(10,2) NOT NULL,
    principal_amount DECIMAL(12,2) NOT NULL,
    interest_amount DECIMAL(10,2) NOT NULL,

    -- Payment Type
    payment_type VARCHAR(20) DEFAULT 'scheduled' CHECK (payment_type IN ('scheduled', 'extra', 'late', 'advance')),

    -- Status
    payment_status VARCHAR(20) DEFAULT 'posted' CHECK (payment_status IN ('pending', 'posted', 'returned', 'failed')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (payment_amount = principal_amount + interest_amount)
);

-- Credit scoring and risk
CREATE TABLE credit_reports (
    report_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Report Details
    report_date DATE DEFAULT CURRENT_DATE,
    credit_score INTEGER,
    credit_score_provider VARCHAR(50) DEFAULT 'internal',

    -- Credit History
    total_accounts INTEGER DEFAULT 0,
    open_accounts INTEGER DEFAULT 0,
    delinquent_accounts INTEGER DEFAULT 0,
    charge_offs INTEGER DEFAULT 0,

    -- Credit Utilization
    total_credit_limit DECIMAL(15,2) DEFAULT 0,
    total_balance DECIMAL(15,2) DEFAULT 0,
    utilization_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN total_credit_limit > 0 THEN (total_balance / total_credit_limit) * 100 ELSE 0 END
    ) STORED,

    -- Report Data
    report_data JSONB, -- Full credit report details

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- COMPLIANCE AND REGULATORY
-- ===========================================

CREATE TABLE compliance_events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID REFERENCES customers(customer_id),
    account_id UUID REFERENCES accounts(account_id),
    transaction_id UUID REFERENCES transactions(transaction_id),

    -- Event Details
    event_type VARCHAR(50) NOT NULL, -- kyc_update, sanctions_check, large_transaction, etc.
    event_severity VARCHAR(20) DEFAULT 'info' CHECK (event_severity IN ('info', 'warning', 'critical')),

    -- Event Data
    event_data JSONB NOT NULL,
    event_description TEXT,

    -- Resolution
    resolution_status VARCHAR(20) DEFAULT 'open' CHECK (resolution_status IN ('open', 'investigating', 'resolved', 'escalated')),
    resolved_by UUID,
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,

    -- Regulatory Reporting
    reportable BOOLEAN DEFAULT FALSE,
    reported_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

-- Suspicious activity reports (SAR)
CREATE TABLE suspicious_activity_reports (
    sar_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID REFERENCES customers(customer_id),
    account_id UUID REFERENCES accounts(account_id),

    -- Report Details
    report_date DATE DEFAULT CURRENT_DATE,
    report_type VARCHAR(50) NOT NULL,
    activity_description TEXT NOT NULL,

    -- Financial Details
    amount_involved DECIMAL(15,2),
    transaction_count INTEGER,
    time_period_days INTEGER,

    -- Investigation
    investigation_status VARCHAR(20) DEFAULT 'open' CHECK (investigation_status IN ('open', 'investigating', 'closed', 'referred')),
    investigator_id UUID,
    investigation_notes TEXT,

    -- Filing
    filed_with_fincen BOOLEAN DEFAULT FALSE,
    fincen_filing_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Customer indexes
CREATE INDEX idx_customers_type_status ON customers (customer_type, customer_status);
CREATE INDEX idx_customers_risk_rating ON customers (risk_rating);
CREATE INDEX idx_customers_email ON customers (email);

-- Account indexes
CREATE INDEX idx_accounts_customer ON accounts (customer_id);
CREATE INDEX idx_accounts_type_status ON accounts (account_type, account_status);
CREATE INDEX idx_accounts_number ON accounts (account_number);
CREATE INDEX idx_accounts_balance ON accounts (current_balance DESC);

-- Transaction indexes
CREATE INDEX idx_transactions_account_date ON transactions (account_id, transaction_date DESC);
CREATE INDEX idx_transactions_type_status ON transactions (transaction_type, transaction_status);
CREATE INDEX idx_transactions_amount ON transactions (amount DESC);
CREATE INDEX idx_transactions_date_posted ON transactions (posted_date DESC);

-- Card indexes
CREATE INDEX idx_cards_account ON cards (account_id);
CREATE INDEX idx_cards_customer ON cards (customer_id);
CREATE INDEX idx_cards_status ON cards (card_status);
CREATE INDEX idx_cards_expiration ON cards (expiration_date);

-- Loan indexes
CREATE INDEX idx_loans_customer ON loans (customer_id);
CREATE INDEX idx_loans_type_status ON loans (loan_type, loan_status);
CREATE INDEX idx_loans_maturity ON loans (maturity_date);
CREATE INDEX idx_loans_next_payment ON loans (next_payment_date);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Customer account summary
CREATE VIEW customer_account_summary AS
SELECT
    c.customer_id,
    CASE
        WHEN c.customer_type = 'individual' THEN ic.first_name || ' ' || ic.last_name
        ELSE bc.business_name
    END as customer_name,
    c.customer_type,
    c.customer_status,

    -- Account counts
    COUNT(a.account_id) as total_accounts,
    COUNT(CASE WHEN a.account_type LIKE '%checking%' THEN 1 END) as checking_accounts,
    COUNT(CASE WHEN a.account_type LIKE '%savings%' THEN 1 END) as savings_accounts,
    COUNT(CASE WHEN a.account_type LIKE '%loan%' THEN 1 END) as loan_accounts,

    -- Total balances
    COALESCE(SUM(a.current_balance), 0) as total_balance,
    COALESCE(SUM(CASE WHEN a.account_type LIKE '%checking%' THEN a.current_balance END), 0) as checking_balance,
    COALESCE(SUM(CASE WHEN a.account_type LIKE '%savings%' THEN a.current_balance END), 0) as savings_balance,

    -- Credit relationships
    COALESCE(SUM(CASE WHEN a.account_type LIKE '%loan%' THEN a.current_balance END), 0) as total_debt,
    COUNT(CASE WHEN card.card_status = 'active' THEN 1 END) as active_cards,

    -- Recent activity
    MAX(t.transaction_date) as last_transaction_date,
    COUNT(CASE WHEN t.transaction_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as recent_transactions

FROM customers c
LEFT JOIN individual_customers ic ON c.customer_id = ic.customer_id
LEFT JOIN business_customers bc ON c.customer_id = bc.customer_id
LEFT JOIN accounts a ON c.customer_id = a.customer_id AND a.account_status = 'active'
LEFT JOIN cards card ON c.customer_id = card.customer_id AND card.card_status = 'active'
LEFT JOIN transactions t ON a.account_id = t.account_id
GROUP BY c.customer_id, c.customer_type, c.customer_status, ic.first_name, ic.last_name, bc.business_name;

-- Account transaction summary
CREATE VIEW account_transaction_summary AS
SELECT
    a.account_id,
    a.account_number,
    a.account_type,
    a.current_balance,
    a.available_balance,

    -- Transaction counts by type
    COUNT(CASE WHEN t.transaction_type = 'deposit' THEN 1 END) as deposit_count,
    COUNT(CASE WHEN t.transaction_type = 'withdrawal' THEN 1 END) as withdrawal_count,
    COUNT(CASE WHEN t.transaction_type = 'transfer' THEN 1 END) as transfer_count,
    COUNT(CASE WHEN t.transaction_type = 'fee' THEN 1 END) as fee_count,

    -- Transaction amounts
    COALESCE(SUM(CASE WHEN t.transaction_type = 'deposit' THEN t.amount END), 0) as total_deposits,
    COALESCE(SUM(CASE WHEN t.transaction_type = 'withdrawal' THEN t.amount END), 0) as total_withdrawals,
    COALESCE(SUM(CASE WHEN t.transaction_type = 'fee' THEN t.fee_amount END), 0) as total_fees,

    -- Date ranges
    MIN(t.transaction_date) as first_transaction_date,
    MAX(t.transaction_date) as last_transaction_date,

    -- Recent activity (last 30 days)
    COUNT(CASE WHEN t.transaction_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as recent_transaction_count,
    COALESCE(SUM(CASE WHEN t.transaction_date >= CURRENT_DATE - INTERVAL '30 days' THEN t.amount END), 0) as recent_activity_amount

FROM accounts a
LEFT JOIN transactions t ON a.account_id = t.account_id AND t.transaction_status = 'posted'
WHERE a.account_status = 'active'
GROUP BY a.account_id, a.account_number, a.account_type, a.current_balance, a.available_balance;

-- Loan portfolio summary
CREATE VIEW loan_portfolio_summary AS
SELECT
    l.loan_type,
    COUNT(*) as loan_count,
    SUM(l.principal_amount) as total_principal,
    SUM(l.current_balance) as total_outstanding,
    AVG(l.interest_rate) as avg_interest_rate,
    AVG(l.current_balance) as avg_loan_balance,

    -- Performance metrics
    COUNT(CASE WHEN l.days_past_due > 0 THEN 1 END) as delinquent_loans,
    COUNT(CASE WHEN l.days_past_due > 30 THEN 1 END) as seriously_delinquent_loans,
    COUNT(CASE WHEN l.loan_status = 'paid_off' THEN 1 END) as paid_off_loans,

    -- Risk metrics
    AVG(l.debt_to_income_ratio) as avg_dti,
    AVG(l.loan_to_value_ratio) as avg_ltv,
    AVG(cr.credit_score) as avg_credit_score

FROM loans l
LEFT JOIN credit_reports cr ON l.customer_id = cr.customer_id
    AND cr.report_date >= CURRENT_DATE - INTERVAL '6 months'
WHERE l.loan_status IN ('active', 'paid_off')
GROUP BY l.loan_type;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample individual customer
INSERT INTO customers (customer_type, tax_id, email, phone, customer_status, kyc_status) VALUES
('individual', '123-45-6789', 'john.doe@email.com', '+1-555-0123', 'active', 'approved');

INSERT INTO individual_customers (
    customer_id, first_name, last_name, date_of_birth, ssn_encrypted,
    residential_address, employment_status, annual_income
) VALUES (
    (SELECT customer_id FROM customers WHERE email = 'john.doe@email.com' LIMIT 1),
    'John', 'Doe', '1985-03-15', encrypt_sensitive_data('123-45-6789'),
    '{"street": "123 Main St", "city": "Anytown", "state": "CA", "zip": "12345"}',
    'employed', 75000
);

-- Insert sample account
INSERT INTO accounts (
    customer_id, account_number, account_type, current_balance,
    available_balance, interest_rate
) VALUES (
    (SELECT customer_id FROM customers WHERE email = 'john.doe@email.com' LIMIT 1),
    '1234567890', 'checking', 5000.00, 5000.00, 0.0001
);

-- Insert sample transaction
INSERT INTO transactions (
    account_id, transaction_type, amount, transaction_date,
    posted_date, reference_number, memo
) VALUES (
    (SELECT account_id FROM accounts WHERE account_number = '1234567890' LIMIT 1),
    'deposit', 5000.00, CURRENT_DATE, CURRENT_DATE,
    'DEP001', 'Initial deposit'
);

-- This banking schema provides a comprehensive foundation for retail and commercial banking
-- with support for accounts, transactions, loans, cards, and regulatory compliance.
