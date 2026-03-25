-- ============================================
-- FINANCIAL SERVICES SCHEMA DESIGN
-- ============================================
-- Comprehensive schema for banking, fintech, payments, and financial services
-- Supports accounts, transactions, payments, compliance, and regulatory requirements

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "hstore";
CREATE EXTENSION IF NOT EXISTS "btree_gist"; -- For range types

-- ============================================
-- CORE ENTITIES
-- ============================================

-- Customers (Individuals and Businesses)
CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_type VARCHAR(20) NOT NULL CHECK (customer_type IN ('individual', 'business')),

    -- Basic information
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,

    -- Business information (for business customers)
    business_name VARCHAR(255),
    business_type VARCHAR(50),
    tax_id VARCHAR(50), -- EIN or SSN (encrypted)
    incorporation_date DATE,

    -- Regulatory information
    kyc_status VARCHAR(30) DEFAULT 'pending' CHECK (kyc_status IN (
        'pending', 'in_review', 'approved', 'rejected', 'requires_update'
    )),
    kyc_completed_at TIMESTAMP WITH TIME ZONE,
    risk_rating VARCHAR(10) CHECK (risk_rating IN ('low', 'medium', 'high', 'critical')),

    -- Contact preferences
    email_verified BOOLEAN DEFAULT FALSE,
    phone_verified BOOLEAN DEFAULT FALSE,
    marketing_consent BOOLEAN DEFAULT FALSE,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    account_locked BOOLEAN DEFAULT FALSE,
    lock_reason TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID, -- System user who created the account

    -- Constraints
    CONSTRAINT chk_individual_fields CHECK (
        (customer_type = 'individual' AND first_name IS NOT NULL AND last_name IS NOT NULL AND date_of_birth IS NOT NULL) OR
        (customer_type = 'business' AND business_name IS NOT NULL AND tax_id IS NOT NULL)
    ),
    CONSTRAINT chk_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Customer addresses (for KYC and compliance)
CREATE TABLE customer_addresses (
    address_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(customer_id) ON DELETE CASCADE,

    address_type VARCHAR(20) DEFAULT 'residential' CHECK (address_type IN (
        'residential', 'mailing', 'business', 'previous'
    )),
    is_primary BOOLEAN DEFAULT FALSE,

    -- Address components
    street_address VARCHAR(255) NOT NULL,
    apartment VARCHAR(50),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100),
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(100) DEFAULT 'USA',

    -- Verification
    verification_status VARCHAR(20) DEFAULT 'unverified' CHECK (verification_status IN (
        'unverified', 'pending', 'verified', 'rejected'
    )),
    verification_method VARCHAR(50), -- 'document', 'utility_bill', 'bank_statement'
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Document references (for verification)
    document_urls JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (customer_id, address_type, is_primary) DEFERRABLE INITIALLY DEFERRED
);

-- ============================================
-- ACCOUNT MANAGEMENT
-- ============================================

-- Account types and products
CREATE TABLE account_types (
    account_type_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    code VARCHAR(20) NOT NULL UNIQUE,
    description TEXT,

    -- Account characteristics
    category VARCHAR(30) NOT NULL CHECK (category IN (
        'checking', 'savings', 'credit_card', 'loan', 'investment', 'retirement'
    )),
    is_debit BOOLEAN DEFAULT TRUE,
    currency VARCHAR(3) DEFAULT 'USD',

    -- Limits and fees
    minimum_balance DECIMAL(15,2) DEFAULT 0.00,
    monthly_fee DECIMAL(8,2) DEFAULT 0.00,
    transaction_fee DECIMAL(6,2) DEFAULT 0.00,
    atm_fee DECIMAL(6,2) DEFAULT 0.00,

    -- Interest rates (for savings/investment accounts)
    interest_rate DECIMAL(5,4) DEFAULT 0.0000, -- 0.05% = 0.0005
    compounding_frequency VARCHAR(20) DEFAULT 'monthly' CHECK (compounding_frequency IN (
        'daily', 'weekly', 'monthly', 'quarterly', 'annually'
    )),

    -- Requirements
    minimum_age INTEGER,
    minimum_deposit DECIMAL(15,2),
    requires_kyc BOOLEAN DEFAULT TRUE,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Customer accounts
CREATE TABLE accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_number VARCHAR(50) UNIQUE NOT NULL, -- Human-readable account number
    customer_id UUID REFERENCES customers(customer_id) ON DELETE RESTRICT,
    account_type_id INTEGER REFERENCES account_types(account_type_id),

    -- Account details
    nickname VARCHAR(100),
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN (
        'pending', 'active', 'frozen', 'closed', 'suspended'
    )),

    -- Balances
    current_balance DECIMAL(15,2) DEFAULT 0.00,
    available_balance DECIMAL(15,2) DEFAULT 0.00, -- Current balance minus holds
    minimum_balance DECIMAL(15,2) DEFAULT 0.00,

    -- Credit limits (for credit accounts)
    credit_limit DECIMAL(15,2),
    outstanding_balance DECIMAL(15,2) DEFAULT 0.00,

    -- Interest and fees
    interest_accrued DECIMAL(12,2) DEFAULT 0.00,
    fees_accrued DECIMAL(10,2) DEFAULT 0.00,

    -- Dates
    opened_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP WITH TIME ZONE,
    last_activity_at TIMESTAMP WITH TIME ZONE,

    -- Security
    pin_hash VARCHAR(255), -- For ATM/debit cards
    online_banking_enabled BOOLEAN DEFAULT TRUE,

    -- Overdraft protection
    overdraft_protection BOOLEAN DEFAULT FALSE,
    overdraft_limit DECIMAL(10,2) DEFAULT 0.00,

    -- Branch/location information
    branch_id INTEGER, -- References branches table
    account_officer_id UUID, -- References employees

    -- Metadata
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT chk_positive_balances CHECK (
        current_balance >= 0 AND available_balance >= 0
    ),
    CONSTRAINT chk_credit_limits CHECK (
        (credit_limit IS NULL) OR (credit_limit > 0 AND outstanding_balance <= credit_limit)
    ),
    CONSTRAINT chk_account_dates CHECK (
        (status = 'closed' AND closed_at IS NOT NULL) OR
        (status != 'closed' AND closed_at IS NULL)
    )
);

-- Account holders (for joint accounts)
CREATE TABLE account_holders (
    account_holder_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(customer_id) ON DELETE CASCADE,

    -- Permissions
    role VARCHAR(20) DEFAULT 'owner' CHECK (role IN ('owner', 'authorized_user', 'view_only')),
    can_withdraw BOOLEAN DEFAULT TRUE,
    can_deposit BOOLEAN DEFAULT TRUE,
    can_transfer BOOLEAN DEFAULT TRUE,
    transaction_limit DECIMAL(12,2), -- Daily limit

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    added_by UUID REFERENCES customers(customer_id), -- Who added this holder

    UNIQUE (account_id, customer_id)
);

-- ============================================
-- TRANSACTION PROCESSING
-- ============================================

-- Transaction categories and types
CREATE TABLE transaction_types (
    transaction_type_id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(30) NOT NULL CHECK (category IN (
        'deposit', 'withdrawal', 'transfer', 'payment', 'fee', 'interest',
        'purchase', 'refund', 'adjustment', 'chargeback'
    )),
    description TEXT,

    -- Processing rules
    requires_approval BOOLEAN DEFAULT FALSE,
    approval_limit DECIMAL(12,2), -- Amount requiring approval
    daily_limit DECIMAL(12,2),
    monthly_limit DECIMAL(12,2),

    -- Fees
    fee_amount DECIMAL(8,2) DEFAULT 0.00,
    fee_percentage DECIMAL(5,4) DEFAULT 0.0000,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Core transactions table
CREATE TABLE transactions (
    transaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_type_id INTEGER REFERENCES transaction_types(transaction_type_id),

    -- Account references
    from_account_id UUID REFERENCES accounts(account_id),
    to_account_id UUID REFERENCES accounts(account_id),

    -- Amounts
    amount DECIMAL(15,2) NOT NULL CHECK (amount > 0),
    currency VARCHAR(3) DEFAULT 'USD',
    exchange_rate DECIMAL(10,6) DEFAULT 1.000000, -- For currency conversion

    -- Converted amounts (if applicable)
    amount_in_base_currency DECIMAL(15,2),

    -- Status and processing
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN (
        'pending', 'processing', 'completed', 'failed', 'cancelled', 'reversed'
    )),
    processing_status VARCHAR(30) DEFAULT 'initiated' CHECK (processing_status IN (
        'initiated', 'validated', 'authorized', 'processed', 'settled', 'failed'
    )),

    -- Transaction details
    reference_number VARCHAR(100) UNIQUE, -- External reference
    description TEXT,
    merchant_info JSONB, -- For card transactions
    location_info JSONB, -- ATM location, IP address, etc.

    -- Fees and charges
    fee_amount DECIMAL(10,2) DEFAULT 0.00,
    tax_amount DECIMAL(8,2) DEFAULT 0.00,

    -- Authorization and approval
    requires_approval BOOLEAN DEFAULT FALSE,
    approved_by UUID REFERENCES customers(customer_id),
    approved_at TIMESTAMP WITH TIME ZONE,

    -- Reversal information
    is_reversal BOOLEAN DEFAULT FALSE,
    original_transaction_id UUID REFERENCES transactions(transaction_id),

    -- Risk and compliance
    risk_score DECIMAL(5,2),
    fraud_flags JSONB DEFAULT '[]',

    -- Audit
    initiated_by UUID REFERENCES customers(customer_id),
    initiated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Metadata
    metadata JSONB DEFAULT '{}',
    tags TEXT[],

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english',
            reference_number || ' ' || description || ' ' ||
            COALESCE(merchant_info->>'name', '') || ' ' ||
            array_to_string(tags, ' ')
        )
    ) STORED,

    -- Constraints
    CONSTRAINT chk_transaction_accounts CHECK (
        NOT (from_account_id IS NULL AND to_account_id IS NULL)
    ),
    CONSTRAINT chk_reversal_logic CHECK (
        (is_reversal = FALSE) OR
        (is_reversal = TRUE AND original_transaction_id IS NOT NULL)
    ),
    CONSTRAINT chk_status_timestamps CHECK (
        (status = 'completed' AND completed_at IS NOT NULL) OR
        (status != 'completed')
    )
) PARTITION BY RANGE (initiated_at);

-- Transaction partitions (monthly)
CREATE TABLE transactions_2024_01 PARTITION OF transactions FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE transactions_2024_02 PARTITION OF transactions FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE transactions_2024_03 PARTITION OF transactions FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');

-- Account balance snapshots (for performance and audit)
CREATE TABLE account_balance_snapshots (
    snapshot_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
    balance_date DATE NOT NULL,

    -- Balances
    opening_balance DECIMAL(15,2) NOT NULL,
    closing_balance DECIMAL(15,2) NOT NULL,
    minimum_balance DECIMAL(15,2) NOT NULL,
    maximum_balance DECIMAL(15,2) NOT NULL,

    -- Transaction counts
    debit_count INTEGER DEFAULT 0,
    credit_count INTEGER DEFAULT 0,
    total_transactions INTEGER DEFAULT 0,

    -- Interest and fees
    interest_accrued DECIMAL(12,2) DEFAULT 0.00,
    fees_charged DECIMAL(10,2) DEFAULT 0.00,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (account_id, balance_date)
) PARTITION BY RANGE (balance_date);

-- ============================================
-- PAYMENT PROCESSING
-- ============================================

-- Payment methods
CREATE TABLE payment_methods (
    payment_method_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(customer_id) ON DELETE CASCADE,

    -- Method details
    type VARCHAR(20) NOT NULL CHECK (type IN (
        'bank_account', 'credit_card', 'debit_card', 'digital_wallet', 'cryptocurrency'
    )),
    provider VARCHAR(50), -- 'stripe', 'paypal', 'bank_transfer'

    -- Account/Card details (encrypted in production)
    account_number_hash VARCHAR(128), -- Last 4 digits stored in metadata
    routing_number_hash VARCHAR(128),
    card_last_four VARCHAR(4),
    card_brand VARCHAR(20),
    card_expiry_month INTEGER,
    card_expiry_year INTEGER,

    -- Digital wallet details
    wallet_provider VARCHAR(50), -- 'apple_pay', 'google_pay', 'venmo'
    wallet_token VARCHAR(255),

    -- Verification
    is_verified BOOLEAN DEFAULT FALSE,
    verification_status VARCHAR(20) DEFAULT 'pending',
    verification_method VARCHAR(50),

    -- Status and limits
    is_active BOOLEAN DEFAULT TRUE,
    is_default BOOLEAN DEFAULT FALSE,
    daily_limit DECIMAL(12,2),
    transaction_limit DECIMAL(10,2),

    -- Security
    requires_2fa BOOLEAN DEFAULT FALSE,

    -- Tokenization (PCI compliant)
    provider_token VARCHAR(255),
    provider_customer_id VARCHAR(255),

    -- Metadata
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (customer_id, is_default) DEFERRABLE INITIALLY DEFERRED
);

-- Payment intents (for payment processing)
CREATE TABLE payment_intents (
    payment_intent_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(customer_id),

    -- Payment details
    amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    description TEXT,

    -- Payment method
    payment_method_id UUID REFERENCES payment_methods(payment_method_id),

    -- Status
    status VARCHAR(20) DEFAULT 'requires_payment_method' CHECK (status IN (
        'requires_payment_method', 'requires_confirmation', 'requires_action',
        'processing', 'succeeded', 'canceled', 'requires_capture'
    )),

    -- Processing
    provider VARCHAR(50),
    provider_intent_id VARCHAR(255) UNIQUE,
    client_secret VARCHAR(255), -- For frontend integration

    -- Metadata
    metadata JSONB DEFAULT '{}',

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE,
    canceled_at TIMESTAMP WITH TIME ZONE,

    -- Linked transactions
    transaction_id UUID REFERENCES transactions(transaction_id),

    CONSTRAINT chk_payment_amount CHECK (amount > 0)
);

-- Payment disputes and chargebacks
CREATE TABLE payment_disputes (
    dispute_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_intent_id UUID REFERENCES payment_intents(payment_intent_id),
    transaction_id UUID REFERENCES transactions(transaction_id),

    -- Dispute details
    reason VARCHAR(50) CHECK (reason IN (
        'fraudulent', 'duplicate', 'subscription_canceled', 'product_unacceptable',
        'product_not_received', 'unrecognized', 'credit_not_processed', 'general'
    )),
    status VARCHAR(20) DEFAULT 'needs_response' CHECK (status IN (
        'needs_response', 'under_review', 'won', 'lost', 'warning_closed'
    )),
    amount DECIMAL(15,2) NOT NULL,

    -- Evidence
    customer_evidence JSONB DEFAULT '{}',
    bank_evidence JSONB DEFAULT '{}',

    -- Resolution
    resolution VARCHAR(50),
    resolved_at TIMESTAMP WITH TIME ZONE,

    -- Provider information
    provider_dispute_id VARCHAR(255),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- CARDS AND DIGITAL WALLETS
-- ============================================

-- Physical and virtual cards
CREATE TABLE cards (
    card_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,

    -- Card details
    card_number_hash VARCHAR(128) NOT NULL,
    card_number_last_four VARCHAR(4) NOT NULL,
    card_type VARCHAR(20) NOT NULL CHECK (card_type IN ('debit', 'credit', 'prepaid')),

    -- Card specifications
    card_brand VARCHAR(20) NOT NULL,
    card_network VARCHAR(20) NOT NULL, -- 'visa', 'mastercard', 'amex'
    expiry_month INTEGER NOT NULL CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year INTEGER NOT NULL CHECK (expiry_year >= EXTRACT(YEAR FROM CURRENT_DATE)),

    -- Status
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN (
        'inactive', 'active', 'blocked', 'expired', 'lost', 'stolen', 'closed'
    )),
    is_virtual BOOLEAN DEFAULT FALSE,

    -- Security
    pin_hash VARCHAR(255),
    cvv_hash VARCHAR(128),

    -- Limits and controls
    daily_limit DECIMAL(10,2),
    transaction_limit DECIMAL(8,2),
    atm_limit DECIMAL(8,2),
    online_purchases_enabled BOOLEAN DEFAULT TRUE,
    international_enabled BOOLEAN DEFAULT TRUE,
    contactless_enabled BOOLEAN DEFAULT TRUE,

    -- Tokenization
    provider_token VARCHAR(255),
    digital_wallet_tokens JSONB DEFAULT '{}', -- Apple Pay, Google Pay tokens

    -- Physical card details
    issued_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    activated_at TIMESTAMP WITH TIME ZONE,
    last_used_at TIMESTAMP WITH TIME ZONE,

    -- Emergency controls
    emergency_lock BOOLEAN DEFAULT FALSE,
    lock_reason TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_card_expiry CHECK (
        expiry_year > EXTRACT(YEAR FROM CURRENT_DATE) OR
        (expiry_year = EXTRACT(YEAR FROM CURRENT_DATE) AND expiry_month >= EXTRACT(MONTH FROM CURRENT_DATE))
    )
);

-- Card transactions (detailed card activity)
CREATE TABLE card_transactions (
    card_transaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id UUID REFERENCES cards(card_id) ON DELETE CASCADE,
    transaction_id UUID REFERENCES transactions(transaction_id),

    -- Transaction details
    merchant_name VARCHAR(255),
    merchant_category VARCHAR(100),
    merchant_location JSONB, -- City, country, coordinates

    -- Amount details
    transaction_amount DECIMAL(12,2) NOT NULL,
    billing_amount DECIMAL(12,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    exchange_rate DECIMAL(10,6),

    -- Authorization details
    authorization_code VARCHAR(50),
    approval_code VARCHAR(50),

    -- Processing
    is_online_transaction BOOLEAN DEFAULT TRUE,
    is_international BOOLEAN DEFAULT FALSE,
    is_recurring BOOLEAN DEFAULT FALSE,

    -- Risk assessment
    risk_score DECIMAL(5,2),
    fraud_alert BOOLEAN DEFAULT FALSE,

    -- Settlement
    settlement_date DATE,
    interchange_fee DECIMAL(6,2),

    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- LOANS AND CREDIT
-- ============================================

-- Loan products
CREATE TABLE loan_products (
    loan_product_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(20) NOT NULL UNIQUE,
    description TEXT,

    -- Loan characteristics
    loan_type VARCHAR(30) NOT NULL CHECK (loan_type IN (
        'personal', 'business', 'mortgage', 'auto', 'student', 'credit_line'
    )),
    currency VARCHAR(3) DEFAULT 'USD',

    -- Terms
    min_amount DECIMAL(15,2) NOT NULL,
    max_amount DECIMAL(15,2) NOT NULL,
    min_term_months INTEGER NOT NULL,
    max_term_months INTEGER NOT NULL,

    -- Interest rates
    base_interest_rate DECIMAL(5,4) NOT NULL, -- 5.25% = 0.0525
    variable_rate BOOLEAN DEFAULT FALSE,
    rate_adjustment_frequency VARCHAR(20), -- 'monthly', 'quarterly'

    -- Fees
    origination_fee DECIMAL(8,2) DEFAULT 0.00,
    origination_fee_percentage DECIMAL(5,4) DEFAULT 0.0000,
    late_fee DECIMAL(8,2) DEFAULT 0.00,
    prepayment_penalty DECIMAL(5,4) DEFAULT 0.0000,

    -- Requirements
    minimum_credit_score INTEGER,
    minimum_income DECIMAL(12,2),
    employment_required BOOLEAN DEFAULT TRUE,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Loan applications
CREATE TABLE loan_applications (
    application_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(customer_id),
    loan_product_id INTEGER REFERENCES loan_products(loan_product_id),

    -- Application details
    requested_amount DECIMAL(15,2) NOT NULL,
    requested_term_months INTEGER NOT NULL,
    purpose TEXT,

    -- Financial information
    annual_income DECIMAL(12,2),
    credit_score INTEGER,
    debt_to_income_ratio DECIMAL(5,2),

    -- Employment information
    employer_name VARCHAR(255),
    employment_years INTEGER,
    employment_type VARCHAR(30),

    -- Status
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN (
        'draft', 'submitted', 'under_review', 'approved', 'rejected', 'withdrawn'
    )),
    status_reason TEXT,

    -- Processing
    submitted_at TIMESTAMP WITH TIME ZONE,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    approved_at TIMESTAMP WITH TIME ZONE,
    rejected_at TIMESTAMP WITH TIME ZONE,

    -- Review information
    reviewer_id UUID, -- References employees
    review_notes TEXT,

    -- Risk assessment
    risk_score DECIMAL(5,2),
    risk_rating VARCHAR(10),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_application_amount CHECK (requested_amount > 0),
    CONSTRAINT chk_credit_score CHECK (credit_score IS NULL OR (credit_score >= 300 AND credit_score <= 850))
);

-- Active loans
CREATE TABLE loans (
    loan_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID REFERENCES loan_applications(application_id),
    account_id UUID REFERENCES accounts(account_id), -- Loan account

    -- Loan details
    loan_amount DECIMAL(15,2) NOT NULL,
    term_months INTEGER NOT NULL,
    interest_rate DECIMAL(5,4) NOT NULL,
    origination_fee DECIMAL(8,2) DEFAULT 0.00,

    -- Payment schedule
    monthly_payment DECIMAL(10,2) NOT NULL,
    first_payment_date DATE NOT NULL,
    final_payment_date DATE NOT NULL,

    -- Balances
    principal_balance DECIMAL(15,2) NOT NULL,
    interest_balance DECIMAL(12,2) DEFAULT 0.00,
    fees_balance DECIMAL(10,2) DEFAULT 0.00,

    -- Status
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN (
        'active', 'paid_off', 'defaulted', 'charged_off', 'in_grace_period'
    )),
    delinquency_status VARCHAR(20) DEFAULT 'current' CHECK (delinquency_status IN (
        'current', 'late_1_29', 'late_30_59', 'late_60_89', 'late_90_plus'
    )),

    -- Grace period and late fees
    grace_period_days INTEGER DEFAULT 15,
    last_payment_date DATE,
    next_payment_date DATE,
    days_past_due INTEGER DEFAULT 0,

    -- Collateral (for secured loans)
    collateral_type VARCHAR(50),
    collateral_value DECIMAL(15,2),
    collateral_description TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Loan payments
CREATE TABLE loan_payments (
    loan_payment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id UUID REFERENCES loans(loan_id),
    transaction_id UUID REFERENCES transactions(transaction_id),

    -- Payment details
    payment_date DATE NOT NULL,
    payment_amount DECIMAL(10,2) NOT NULL,

    -- Allocation
    principal_paid DECIMAL(12,2) NOT NULL,
    interest_paid DECIMAL(10,2) NOT NULL,
    fees_paid DECIMAL(8,2) DEFAULT 0.00,

    -- Status
    payment_type VARCHAR(20) DEFAULT 'scheduled' CHECK (payment_type IN (
        'scheduled', 'extra', 'late', 'prepayment'
    )),
    is_late BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- COMPLIANCE AND REGULATORY
-- ============================================

-- KYC/AML documents
CREATE TABLE kyc_documents (
    document_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(customer_id) ON DELETE CASCADE,

    -- Document details
    document_type VARCHAR(50) NOT NULL CHECK (document_type IN (
        'passport', 'drivers_license', 'ssn', 'utility_bill', 'bank_statement',
        'tax_return', 'incorporation_docs', 'business_license'
    )),
    document_number VARCHAR(100),
    issuing_country VARCHAR(100),
    issuing_authority VARCHAR(255),

    -- Validity
    issued_date DATE,
    expiry_date DATE,
    is_expired BOOLEAN GENERATED ALWAYS AS (expiry_date < CURRENT_DATE) STORED,

    -- Verification
    verification_status VARCHAR(20) DEFAULT 'pending' CHECK (verification_status IN (
        'pending', 'verified', 'rejected', 'expired'
    )),
    verified_by UUID, -- References employees
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Files
    document_urls JSONB DEFAULT '[]', -- Multiple file URLs
    extracted_data JSONB DEFAULT '{}', -- OCR/extracted information

    -- Audit
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    uploaded_by UUID REFERENCES customers(customer_id),

    CONSTRAINT chk_document_dates CHECK (issued_date <= expiry_date)
);

-- Suspicious activity reports (SAR)
CREATE TABLE suspicious_activity_reports (
    sar_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(customer_id),
    account_id UUID REFERENCES accounts(account_id),
    transaction_id UUID REFERENCES transactions(transaction_id),

    -- SAR details
    report_type VARCHAR(50) NOT NULL CHECK (report_type IN (
        'money_laundering', 'terrorist_financing', 'fraud', 'unusual_activity'
    )),
    severity VARCHAR(10) NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),

    -- Description and analysis
    description TEXT NOT NULL,
    indicators JSONB NOT NULL, -- Specific red flags identified
    risk_assessment TEXT,

    -- Investigation
    investigator_id UUID, -- References employees
    investigation_status VARCHAR(20) DEFAULT 'open' CHECK (investigation_status IN (
        'open', 'investigating', 'closed_no_action', 'closed_with_action', 'escalated'
    )),
    investigation_notes TEXT,

    -- Regulatory filing
    filed_with_fincen BOOLEAN DEFAULT FALSE,
    fincen_reference_number VARCHAR(50),
    filed_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    reported_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP WITH TIME ZONE
);

-- Transaction monitoring rules
CREATE TABLE monitoring_rules (
    rule_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,

    -- Rule conditions
    conditions JSONB NOT NULL, -- Complex rule logic
    severity VARCHAR(10) NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),

    -- Actions
    actions JSONB NOT NULL, -- What to do when rule triggers

    -- Rule management
    is_active BOOLEAN DEFAULT TRUE,
    priority INTEGER DEFAULT 0,
    false_positive_rate DECIMAL(5,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- ANALYTICS AND REPORTING
-- ============================================

-- Customer analytics
CREATE TABLE customer_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(customer_id) ON DELETE CASCADE,
    date DATE NOT NULL,

    -- Account metrics
    accounts_count INTEGER DEFAULT 0,
    total_balance DECIMAL(15,2) DEFAULT 0.00,

    -- Transaction metrics
    transactions_count INTEGER DEFAULT 0,
    debit_amount DECIMAL(15,2) DEFAULT 0.00,
    credit_amount DECIMAL(15,2) DEFAULT 0.00,

    -- Digital engagement
    login_count INTEGER DEFAULT 0,
    app_sessions INTEGER DEFAULT 0,
    mobile_transactions INTEGER DEFAULT 0,

    -- Risk metrics
    risk_score DECIMAL(5,2),
    fraud_alerts_count INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (customer_id, date)
) PARTITION BY RANGE (date);

-- Account performance metrics
CREATE TABLE account_performance (
    performance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
    month DATE NOT NULL,

    -- Balance metrics
    average_balance DECIMAL(15,2),
    minimum_balance DECIMAL(15,2),
    maximum_balance DECIMAL(15,2),

    -- Transaction metrics
    transaction_count INTEGER DEFAULT 0,
    debit_transaction_count INTEGER DEFAULT 0,
    credit_transaction_count INTEGER DEFAULT 0,

    -- Fee and interest
    fees_charged DECIMAL(10,2) DEFAULT 0.00,
    interest_earned DECIMAL(12,2) DEFAULT 0.00,

    -- Usage metrics
    atm_transactions INTEGER DEFAULT 0,
    online_transactions INTEGER DEFAULT 0,
    mobile_transactions INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (account_id, month)
) PARTITION BY RANGE (month);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Customer indexes
CREATE INDEX idx_customers_email ON customers (email);
CREATE INDEX idx_customers_kyc_status ON customers (kyc_status);
CREATE INDEX idx_customers_type_status ON customers (customer_type, is_active);

-- Account indexes
CREATE INDEX idx_accounts_customer ON accounts (customer_id);
CREATE INDEX idx_accounts_type_status ON accounts (account_type_id, status);
CREATE INDEX idx_accounts_number ON accounts (account_number);
CREATE INDEX idx_accounts_balance ON accounts (current_balance);

-- Transaction indexes
CREATE INDEX idx_transactions_accounts ON transactions (from_account_id, to_account_id);
CREATE INDEX idx_transactions_type_status ON transactions (transaction_type_id, status);
CREATE INDEX idx_transactions_date ON transactions (initiated_at);
CREATE INDEX idx_transactions_reference ON transactions (reference_number);
CREATE INDEX idx_transactions_search ON transactions USING GIN (search_vector);

-- Payment indexes
CREATE INDEX idx_payment_methods_customer ON payment_methods (customer_id);
CREATE INDEX idx_payment_intents_customer ON payment_intents (customer_id);
CREATE INDEX idx_payment_intents_status ON payment_intents (status);

-- Card indexes
CREATE INDEX idx_cards_account ON cards (account_id);
CREATE INDEX idx_cards_status ON cards (status);
CREATE INDEX idx_card_transactions_card ON card_transactions (card_id);

-- Loan indexes
CREATE INDEX idx_loans_customer ON loans (account_id);
CREATE INDEX idx_loans_status ON loans (status);
CREATE INDEX idx_loan_applications_customer ON loan_applications (customer_id);

-- Compliance indexes
CREATE INDEX idx_kyc_documents_customer ON kyc_documents (customer_id);
CREATE INDEX idx_kyc_documents_status ON kyc_documents (verification_status);
CREATE INDEX idx_sar_customer ON suspicious_activity_reports (customer_id);
CREATE INDEX idx_sar_status ON suspicious_activity_reports (investigation_status);

-- Analytics indexes
CREATE INDEX idx_customer_analytics_customer_date ON customer_analytics (customer_id, date DESC);
CREATE INDEX idx_account_performance_account_month ON account_performance (account_id, month DESC);

-- ============================================
-- USEFUL VIEWS
-- ============================================

-- Customer account summary
CREATE VIEW customer_account_summary AS
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.customer_type,
    c.kyc_status,

    -- Account counts and balances
    COUNT(a.account_id) AS total_accounts,
    COALESCE(SUM(a.current_balance), 0) AS total_balance,
    COALESCE(SUM(a.available_balance), 0) AS total_available_balance,
    COALESCE(AVG(a.current_balance), 0) AS avg_account_balance,

    -- Recent activity
    MAX(a.last_activity_at) AS last_account_activity,
    COUNT(CASE WHEN a.last_activity_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS active_accounts_30d,

    -- Credit information
    COALESCE(SUM(a.credit_limit), 0) AS total_credit_limit,
    COALESCE(SUM(a.outstanding_balance), 0) AS total_outstanding_balance,

    -- Risk indicators
    c.risk_rating,
    COUNT(CASE WHEN sar.sar_id IS NOT NULL THEN 1 END) AS sar_count

FROM customers c
LEFT JOIN accounts a ON c.customer_id = a.customer_id AND a.status = 'active'
LEFT JOIN suspicious_activity_reports sar ON c.customer_id = sar.customer_id
    AND sar.created_at >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.customer_type, c.kyc_status, c.risk_rating;

-- Transaction summary view
CREATE VIEW transaction_summary AS
SELECT
    t.transaction_id,
    t.reference_number,
    t.amount,
    t.currency,
    t.status,
    t.transaction_type_id,
    tt.name AS transaction_type,
    tt.category AS transaction_category,

    -- Account information
    fa.account_number AS from_account,
    ta.account_number AS to_account,

    -- Customer information
    fc.customer_id AS from_customer_id,
    fc.first_name || ' ' || fc.last_name AS from_customer_name,
    tc.customer_id AS to_customer_id,
    tc.first_name || ' ' || tc.last_name AS to_customer_name,

    -- Processing information
    t.initiated_at,
    t.processed_at,
    t.completed_at,
    EXTRACT(EPOCH FROM (t.completed_at - t.initiated_at)) / 60 AS processing_minutes,

    -- Risk information
    t.risk_score,
    CASE WHEN array_length(t.fraud_flags, 1) > 0 THEN TRUE ELSE FALSE END AS has_fraud_flags

FROM transactions t
JOIN transaction_types tt ON t.transaction_type_id = tt.transaction_type_id
LEFT JOIN accounts fa ON t.from_account_id = fa.account_id
LEFT JOIN accounts ta ON t.to_account_id = ta.account_id
LEFT JOIN customers fc ON fa.customer_id = fc.customer_id
LEFT JOIN customers tc ON ta.customer_id = tc.customer_id;

-- ============================================
-- USEFUL FUNCTIONS
-- ============================================

-- Function to calculate account balance
CREATE OR REPLACE FUNCTION calculate_account_balance(account_uuid UUID)
RETURNS DECIMAL(15,2) AS $$
DECLARE
    calculated_balance DECIMAL(15,2) := 0;
BEGIN
    -- Calculate balance from transactions
    SELECT COALESCE(SUM(
        CASE
            WHEN from_account_id = account_uuid THEN -amount
            WHEN to_account_id = account_uuid THEN amount
            ELSE 0
        END
    ), 0)
    INTO calculated_balance
    FROM transactions
    WHERE (from_account_id = account_uuid OR to_account_id = account_uuid)
      AND status = 'completed';

    -- Update account balance
    UPDATE accounts
    SET current_balance = calculated_balance,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_id = account_uuid;

    RETURN calculated_balance;
END;
$$ LANGUAGE plpgsql;

-- Function to process loan payment
CREATE OR REPLACE FUNCTION process_loan_payment(
    loan_uuid UUID,
    payment_amount DECIMAL(10,2),
    payment_date DATE DEFAULT CURRENT_DATE
)
RETURNS DECIMAL(10,2) AS $$
DECLARE
    loan_record loans%ROWTYPE;
    interest_due DECIMAL(10,2);
    principal_payment DECIMAL(12,2);
    interest_payment DECIMAL(10,2);
    remaining_payment DECIMAL(10,2);
BEGIN
    -- Get loan details
    SELECT * INTO loan_record FROM loans WHERE loan_id = loan_uuid AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan not found or not active';
    END IF;

    -- Calculate interest due
    interest_due := loan_record.principal_balance * loan_record.interest_rate / 12;

    -- Allocate payment
    interest_payment := LEAST(interest_due, payment_amount);
    remaining_payment := payment_amount - interest_payment;
    principal_payment := LEAST(loan_record.principal_balance, remaining_payment);

    -- Insert payment record
    INSERT INTO loan_payments (
        loan_id, payment_date, payment_amount,
        principal_paid, interest_paid
    ) VALUES (
        loan_uuid, payment_date, payment_amount,
        principal_payment, interest_payment
    );

    -- Update loan balances
    UPDATE loans
    SET
        principal_balance = principal_balance - principal_payment,
        interest_balance = interest_balance - interest_payment,
        last_payment_date = payment_date,
        next_payment_date = payment_date + INTERVAL '1 month',
        status = CASE WHEN principal_balance - principal_payment <= 0 THEN 'paid_off' ELSE 'active' END,
        updated_at = CURRENT_TIMESTAMP
    WHERE loan_id = loan_uuid;

    RETURN payment_amount;
END;
$$ LANGUAGE plpgsql;

-- Function to check transaction limits
CREATE OR REPLACE FUNCTION check_transaction_limits(
    customer_uuid UUID,
    transaction_type_code VARCHAR,
    transaction_amount DECIMAL(15,2)
)
RETURNS TABLE (
    within_limits BOOLEAN,
    daily_used DECIMAL(15,2),
    daily_limit DECIMAL(15,2),
    monthly_used DECIMAL(15,2),
    monthly_limit DECIMAL(15,2)
) AS $$
DECLARE
    tt_record transaction_types%ROWTYPE;
    daily_total DECIMAL(15,2) := 0;
    monthly_total DECIMAL(15,2) := 0;
BEGIN
    -- Get transaction type details
    SELECT * INTO tt_record
    FROM transaction_types
    WHERE code = transaction_type_code;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 0::DECIMAL, 0::DECIMAL, 0::DECIMAL, 0::DECIMAL;
        RETURN;
    END IF;

    -- Calculate daily usage
    SELECT COALESCE(SUM(amount), 0)
    INTO daily_total
    FROM transactions t
    JOIN accounts a ON t.from_account_id = a.account_id OR t.to_account_id = a.account_id
    WHERE a.customer_id = customer_uuid
      AND t.transaction_type_id = tt_record.transaction_type_id
      AND t.status = 'completed'
      AND DATE(t.completed_at) = CURRENT_DATE;

    -- Calculate monthly usage
    SELECT COALESCE(SUM(amount), 0)
    INTO monthly_total
    FROM transactions t
    JOIN accounts a ON t.from_account_id = a.account_id OR t.to_account_id = a.account_id
    WHERE a.customer_id = customer_uuid
      AND t.transaction_type_id = tt_record.transaction_type_id
      AND t.status = 'completed'
      AND DATE_TRUNC('month', t.completed_at) = DATE_TRUNC('month', CURRENT_DATE);

    -- Check limits
    RETURN QUERY SELECT
        (daily_total + transaction_amount <= COALESCE(tt_record.daily_limit, daily_total + transaction_amount + 1)) AND
        (monthly_total + transaction_amount <= COALESCE(tt_record.monthly_limit, monthly_total + transaction_amount + 1)),
        daily_total,
        tt_record.daily_limit,
        monthly_total,
        tt_record.monthly_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS FOR AUTOMATION
-- ============================================

-- Auto-update account balances
CREATE OR REPLACE FUNCTION update_account_balance()
RETURNS TRIGGER AS $$
BEGIN
    -- Update from account balance (debit)
    IF NEW.from_account_id IS NOT NULL AND NEW.status = 'completed' THEN
        UPDATE accounts
        SET current_balance = current_balance - NEW.amount,
            available_balance = available_balance - NEW.amount,
            last_activity_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_id = NEW.from_account_id;
    END IF;

    -- Update to account balance (credit)
    IF NEW.to_account_id IS NOT NULL AND NEW.status = 'completed' THEN
        UPDATE accounts
        SET current_balance = current_balance + NEW.amount,
            available_balance = available_balance + NEW.amount,
            last_activity_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_id = NEW.to_account_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_account_balance
    AFTER INSERT OR UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_account_balance();

-- Risk scoring for transactions
CREATE OR REPLACE FUNCTION calculate_transaction_risk()
RETURNS TRIGGER AS $$
DECLARE
    risk_factors INTEGER := 0;
    customer_record customers%ROWTYPE;
BEGIN
    -- Get customer information
    SELECT c.* INTO customer_record
    FROM accounts a
    JOIN customers c ON a.customer_id = c.customer_id
    WHERE a.account_id = COALESCE(NEW.from_account_id, NEW.to_account_id)
    LIMIT 1;

    -- Risk factor calculation
    IF customer_record.kyc_status != 'approved' THEN risk_factors := risk_factors + 2; END IF;
    IF NEW.amount > 10000 THEN risk_factors := risk_factors + 1; END IF;
    IF NEW.metadata->>'international' = 'true' THEN risk_factors := risk_factors + 1; END IF;

    -- Calculate risk score (0-10 scale)
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

-- Auto-generate account numbers
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

    -- Get next sequence number (simple implementation)
    SELECT COALESCE(MAX(CAST(SUBSTRING(account_number FROM 4) AS INTEGER)), 0) + 1
    INTO next_sequence
    FROM accounts
    WHERE account_number LIKE account_prefix || '%';

    -- Generate account number
    NEW.account_number := account_prefix || LPAD(next_sequence::TEXT, 8, '0');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_account_number
    BEFORE INSERT ON accounts
    FOR EACH ROW
    WHEN (NEW.account_number IS NULL)
    EXECUTE FUNCTION generate_account_number();
