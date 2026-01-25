# Neobank Digital Banking: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Accounts, Transactions, Ledger, Cards, Multi-Currency, Compliance — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Mutable balances. The ledger is **immutable** and **append-only**. Balances are always **derived** from summing ledger entries. Never update a balance field directly.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Revolut's Event-Driven Architecture](https://www.abnasia.org/2022/12/revolut-system-design.html) | PostgreSQL + event store |
| [Double-Entry Bookkeeping](https://en.wikipedia.org/wiki/Double-entry_bookkeeping) | Core ledger concept |
| [PSD2 / Open Banking](https://www.ecb.europa.eu/paym/intro/mip-online/2018/html/1803_revisedpsd.en.html) | EU compliance |
| [AML/KYC Requirements](https://www.fincen.gov/resources/statutes-and-regulations/bank-secrecy-act) | Anti-money laundering |

---

## 🎯 The Principal Laws of Digital Banking Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Immutable Ledger** | Entries append-only, never update | Corrections = new reversal entries |
| **Law 2: Double-Entry** | Every debit has a credit | Ledger always balances to zero |
| **Law 3: Audit Everything** | Every state change logged | Compliance requires full history |
| **Law 4: Multi-Currency Native** | Currency on every money field | FX at transaction time, not display |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get account balance | 10M/s | < 10ms | Cache + derived from ledger |
| 2 | Get transaction history | 5M/s | < 50ms | PostgreSQL (partitioned) |
| 3 | Transfer money (internal) | 100K/s | < 500ms | PostgreSQL (ACID) |
| 4 | Transfer money (external SWIFT/SEPA) | 10K/s | < 2s | PostgreSQL + async queue |
| 5 | Currency exchange | 50K/s | < 200ms | PostgreSQL + FX service |
| 6 | Get card transactions | 1M/s | < 50ms | PostgreSQL + Cache |
| 7 | Freeze/unfreeze card | 10K/s | < 100ms | PostgreSQL (real-time) |
| 8 | KYC verification check | 100K/s | < 50ms | PostgreSQL + Cache |
| 9 | Check spending limits | 500K/s | < 20ms | Redis |
| 10 | Generate statement | 10K/s | < 5s | Async job |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    NEOBANK DATA ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL (Primary)                     │
│  ✓ ACID transactions    ✓ Immutable ledger   ✓ Compliance       │
│                                                                  │
│  • customers, accounts                                           │
│  • ledger_entries (append-only, source of truth)                 │
│  • transactions                                                  │
│  • cards, card_transactions                                      │
│  • fx_rates, fx_orders                                           │
│  • kyc_records, aml_flags                                        │
└─────────────────────────────────────────────────────────────────┘
                              │ CDC (Debezium)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Balance cache    ✓ Rate limits   ✓ Session state             │
│                                                                  │
│  • balance:{account_id}                                          │
│  • daily_spend:{card_id}                                         │
│  • rate_limit:{customer_id}                                      │
│  • fx_rate:{from}:{to}                                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Kafka                                    │
│  ✓ Event sourcing    ✓ Async processing   ✓ Audit trail         │
│                                                                  │
│  • account-events                                                │
│  • transaction-events                                            │
│  • card-events                                                   │
│  • compliance-events                                             │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    External Integrations                         │
│                                                                  │
│  • SWIFT / SEPA (international transfers)                        │
│  • Visa / Mastercard (card processing)                           │
│  • KYC providers (Onfido, Jumio)                                 │
│  • AML screening (ComplyAdvantage)                               │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- NEOBANK SCHEMA: PostgreSQL Production DDL
-- Version: Digital banking with immutable ledger
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ===========================================
-- SECTION 1: CUSTOMERS
-- ===========================================

CREATE TYPE customer_type AS ENUM ('personal', 'business');
CREATE TYPE kyc_status AS ENUM ('pending', 'in_progress', 'verified', 'rejected', 'expired');

CREATE TABLE customers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identity
    customer_type       customer_type NOT NULL DEFAULT 'personal',
    email               VARCHAR(255) NOT NULL UNIQUE,
    phone_number        VARCHAR(20) NOT NULL UNIQUE,
    
    -- Personal details
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    date_of_birth       DATE,
    nationality         VARCHAR(2),  -- ISO 3166-1 alpha-2
    
    -- Business details (for business accounts)
    business_name       VARCHAR(255),
    company_number      VARCHAR(50),
    tax_id              VARCHAR(50),
    
    -- Address
    address_line1       VARCHAR(255),
    address_line2       VARCHAR(255),
    city                VARCHAR(100),
    state               VARCHAR(100),
    postal_code         VARCHAR(20),
    country             VARCHAR(2) NOT NULL,  -- ISO 3166-1 alpha-2
    
    -- KYC/AML
    kyc_status          kyc_status DEFAULT 'pending',
    kyc_verified_at     TIMESTAMP WITH TIME ZONE,
    kyc_expires_at      TIMESTAMP WITH TIME ZONE,
    risk_score          INT DEFAULT 0,  -- 0-100
    pep_status          BOOLEAN DEFAULT FALSE,  -- Politically Exposed Person
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    is_locked           BOOLEAN DEFAULT FALSE,
    locked_reason       TEXT,
    
    -- Timestamps
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_phone ON customers(phone_number);
CREATE INDEX idx_customers_kyc ON customers(kyc_status);


-- ===========================================
-- SECTION 2: ACCOUNTS
-- ===========================================

CREATE TYPE account_type AS ENUM ('checking', 'savings', 'trading', 'vault');
CREATE TYPE account_status AS ENUM ('active', 'frozen', 'closed');

CREATE TABLE accounts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    
    -- Account info
    account_number      VARCHAR(30) NOT NULL UNIQUE,  -- Internal
    iban                VARCHAR(34),  -- International Bank Account Number
    sort_code           VARCHAR(10),  -- UK sort code
    routing_number      VARCHAR(10),  -- US routing
    
    account_type        account_type NOT NULL DEFAULT 'checking',
    currency            VARCHAR(3) NOT NULL,  -- ISO 4217
    
    -- Name
    name                VARCHAR(100) DEFAULT 'Main Account',
    
    -- Status
    status              account_status DEFAULT 'active',
    
    -- Balance (DERIVED - cached from ledger, never update directly)
    -- This is for read performance only. Ledger is source of truth.
    cached_balance      BIGINT NOT NULL DEFAULT 0,  -- In smallest currency unit
    cached_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Limits
    daily_transfer_limit    BIGINT DEFAULT 100000,  -- In cents
    monthly_transfer_limit  BIGINT DEFAULT 1000000,
    
    -- Timestamps
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    closed_at           TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_accounts_customer ON accounts(customer_id);
CREATE INDEX idx_accounts_iban ON accounts(iban) WHERE iban IS NOT NULL;
CREATE INDEX idx_accounts_number ON accounts(account_number);
CREATE INDEX idx_accounts_status ON accounts(status);


-- ===========================================
-- SECTION 3: LEDGER (Immutable, Append-Only)
-- ===========================================

-- The CORE of the banking system
-- Every money movement is a ledger entry
-- Balances are ALWAYS derived by summing entries

CREATE TYPE entry_type AS ENUM ('debit', 'credit');

CREATE TABLE ledger_entries (
    id                  BIGSERIAL PRIMARY KEY,
    
    -- Transaction grouping (all entries in a txn share this)
    transaction_id      UUID NOT NULL,
    
    -- Account affected
    account_id          UUID NOT NULL REFERENCES accounts(id),
    
    -- Entry details
    entry_type          entry_type NOT NULL,
    amount              BIGINT NOT NULL,  -- Always positive
    currency            VARCHAR(3) NOT NULL,
    
    -- Running balance at this point (for faster queries)
    balance_after       BIGINT NOT NULL,
    
    -- Timestamp (immutable)
    posted_at           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    -- Description
    description         TEXT,
    
    -- Reference to source
    reference_type      VARCHAR(50),  -- 'transfer', 'card_txn', 'fee', 'interest', 'fx'
    reference_id        UUID,
    
    -- Contra account (for double-entry visibility)
    contra_account_id   UUID REFERENCES accounts(id),
    
    -- Immutability: no UPDATE or DELETE allowed
    -- Corrections are made by posting reversal entries
    
    CONSTRAINT ck_positive_amount CHECK (amount > 0)
) PARTITION BY RANGE (posted_at);

-- Monthly partitions (keep 7 years for compliance)
CREATE TABLE ledger_entries_y2024m01 PARTITION OF ledger_entries
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE ledger_entries_y2024m02 PARTITION OF ledger_entries
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
-- ... create partitions programmatically

CREATE INDEX idx_ledger_txn ON ledger_entries(transaction_id);
CREATE INDEX idx_ledger_account ON ledger_entries(account_id, posted_at DESC);
CREATE INDEX idx_ledger_posted ON ledger_entries(posted_at DESC);
CREATE INDEX idx_ledger_reference ON ledger_entries(reference_type, reference_id);


-- ===========================================
-- SECTION 4: TRANSACTIONS
-- ===========================================

CREATE TYPE transaction_type AS ENUM (
    'internal_transfer',      -- Between own accounts
    'peer_transfer',          -- To another customer
    'external_transfer',      -- SWIFT/SEPA/ACH
    'card_purchase',
    'card_atm',
    'fx_exchange',
    'fee',
    'interest',
    'refund',
    'reversal'
);

CREATE TYPE transaction_status AS ENUM (
    'pending',
    'processing',
    'completed',
    'failed',
    'reversed',
    'cancelled'
);

CREATE TABLE transactions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Idempotency
    idempotency_key     VARCHAR(255) UNIQUE,
    
    -- Parties
    from_account_id     UUID REFERENCES accounts(id),
    to_account_id       UUID REFERENCES accounts(id),
    
    -- Type and status
    transaction_type    transaction_type NOT NULL,
    status              transaction_status NOT NULL DEFAULT 'pending',
    
    -- Amount
    amount              BIGINT NOT NULL,
    currency            VARCHAR(3) NOT NULL,
    
    -- For FX transactions
    fx_rate             DECIMAL(18, 8),
    fx_amount           BIGINT,  -- Amount in target currency
    fx_currency         VARCHAR(3),
    
    -- Fees
    fee_amount          BIGINT DEFAULT 0,
    fee_currency        VARCHAR(3),
    
    -- External transfer details
    beneficiary_name    VARCHAR(255),
    beneficiary_iban    VARCHAR(34),
    beneficiary_bic     VARCHAR(11),
    payment_reference   VARCHAR(140),
    
    -- Card transaction details
    card_id             UUID,
    merchant_name       VARCHAR(255),
    merchant_category   VARCHAR(10),  -- MCC code
    merchant_country    VARCHAR(2),
    
    -- Metadata
    description         TEXT,
    notes               TEXT,
    metadata            JSONB,
    
    -- Timestamps
    initiated_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at        TIMESTAMP WITH TIME ZONE,
    failed_at           TIMESTAMP WITH TIME ZONE,
    
    -- Failure info
    failure_code        VARCHAR(50),
    failure_reason      TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_txn_from ON transactions(from_account_id);
CREATE INDEX idx_txn_to ON transactions(to_account_id);
CREATE INDEX idx_txn_status ON transactions(status);
CREATE INDEX idx_txn_type ON transactions(transaction_type);
CREATE INDEX idx_txn_initiated ON transactions(initiated_at DESC);
CREATE INDEX idx_txn_idempotency ON transactions(idempotency_key);


-- ===========================================
-- SECTION 5: CARDS
-- ===========================================

CREATE TYPE card_type AS ENUM ('virtual', 'physical');
CREATE TYPE card_status AS ENUM ('pending', 'active', 'frozen', 'blocked', 'expired', 'cancelled');
CREATE TYPE card_brand AS ENUM ('visa', 'mastercard');

CREATE TABLE cards (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    
    -- Card details (encrypted at rest)
    card_number_enc     BYTEA,  -- Encrypted, full PAN never in logs
    card_last4          VARCHAR(4) NOT NULL,
    expiry_month        INT NOT NULL,
    expiry_year         INT NOT NULL,
    cvv_enc             BYTEA,  -- Encrypted
    
    card_type           card_type NOT NULL,
    card_brand          card_brand NOT NULL DEFAULT 'visa',
    
    -- Status
    status              card_status DEFAULT 'pending',
    
    -- Personalization
    name_on_card        VARCHAR(26),
    card_name           VARCHAR(50),  -- "Travel Card"
    
    -- Limits (in cents)
    daily_spend_limit   BIGINT DEFAULT 500000,  -- $5000
    monthly_spend_limit BIGINT DEFAULT 2000000,
    single_txn_limit    BIGINT DEFAULT 100000,
    atm_daily_limit     BIGINT DEFAULT 50000,
    
    -- Controls
    online_enabled      BOOLEAN DEFAULT TRUE,
    contactless_enabled BOOLEAN DEFAULT TRUE,
    atm_enabled         BOOLEAN DEFAULT TRUE,
    international_enabled BOOLEAN DEFAULT TRUE,
    
    -- PIN
    pin_set             BOOLEAN DEFAULT FALSE,
    pin_tries_remaining INT DEFAULT 3,
    pin_blocked         BOOLEAN DEFAULT FALSE,
    
    -- Physical card
    shipping_address    JSONB,
    tracking_number     VARCHAR(100),
    delivered_at        TIMESTAMP WITH TIME ZONE,
    
    -- Tokenization (Apple Pay, Google Pay)
    dpan                VARCHAR(19),  -- Device PAN
    
    -- Timestamps
    activated_at        TIMESTAMP WITH TIME ZONE,
    frozen_at           TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_cards_account ON cards(account_id);
CREATE INDEX idx_cards_customer ON cards(customer_id);
CREATE INDEX idx_cards_status ON cards(status);
CREATE INDEX idx_cards_last4 ON cards(card_last4);


-- Card transactions (from card network)
CREATE TABLE card_transactions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id             UUID NOT NULL REFERENCES cards(id),
    transaction_id      UUID REFERENCES transactions(id),
    
    -- Authorization
    authorization_code  VARCHAR(20),
    network_ref         VARCHAR(50),  -- Visa/MC reference
    
    -- Amount
    amount              BIGINT NOT NULL,
    currency            VARCHAR(3) NOT NULL,
    billing_amount      BIGINT NOT NULL,  -- In account currency
    billing_currency    VARCHAR(3) NOT NULL,
    fx_rate             DECIMAL(18, 8),
    
    -- Merchant
    merchant_name       VARCHAR(255),
    merchant_id         VARCHAR(50),
    merchant_category   VARCHAR(10),  -- MCC
    merchant_city       VARCHAR(100),
    merchant_country    VARCHAR(2),
    
    -- Status
    status              VARCHAR(20) NOT NULL,  -- 'authorized', 'cleared', 'declined', 'reversed'
    
    -- For auth hold
    authorized_at       TIMESTAMP WITH TIME ZONE,
    cleared_at          TIMESTAMP WITH TIME ZONE,
    
    -- Decline reason
    decline_code        VARCHAR(20),
    decline_reason      TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_card_txn_card ON card_transactions(card_id);
CREATE INDEX idx_card_txn_auth ON card_transactions(authorization_code);
CREATE INDEX idx_card_txn_created ON card_transactions(created_at DESC);


-- ===========================================
-- SECTION 6: FX RATES AND ORDERS
-- ===========================================

CREATE TABLE fx_rates (
    id                  BIGSERIAL PRIMARY KEY,
    from_currency       VARCHAR(3) NOT NULL,
    to_currency         VARCHAR(3) NOT NULL,
    
    -- Rates
    bid_rate            DECIMAL(18, 8) NOT NULL,  -- We buy at
    ask_rate            DECIMAL(18, 8) NOT NULL,  -- We sell at
    mid_rate            DECIMAL(18, 8) NOT NULL,
    
    -- Valid period
    valid_from          TIMESTAMP WITH TIME ZONE NOT NULL,
    valid_to            TIMESTAMP WITH TIME ZONE,
    
    -- Source
    source              VARCHAR(50) DEFAULT 'interbank',
    
    CONSTRAINT uk_fx_rate UNIQUE (from_currency, to_currency, valid_from)
);

CREATE INDEX idx_fx_rates_pair ON fx_rates(from_currency, to_currency, valid_from DESC);

CREATE TABLE fx_orders (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id      UUID NOT NULL REFERENCES transactions(id),
    
    -- Conversion
    from_account_id     UUID NOT NULL REFERENCES accounts(id),
    to_account_id       UUID NOT NULL REFERENCES accounts(id),
    
    from_amount         BIGINT NOT NULL,
    from_currency       VARCHAR(3) NOT NULL,
    to_amount           BIGINT NOT NULL,
    to_currency         VARCHAR(3) NOT NULL,
    
    -- Rate used
    rate                DECIMAL(18, 8) NOT NULL,
    rate_type           VARCHAR(20),  -- 'market', 'limit'
    
    -- Markup
    markup_percent      DECIMAL(5,4),
    markup_amount       BIGINT,
    
    executed_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_fx_orders_txn ON fx_orders(transaction_id);


-- ===========================================
-- SECTION 7: KYC AND COMPLIANCE
-- ===========================================

CREATE TABLE kyc_records (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    
    -- Verification type
    verification_type   VARCHAR(50) NOT NULL,  -- 'identity', 'address', 'selfie', 'document'
    
    -- Provider
    provider            VARCHAR(50),  -- 'onfido', 'jumio'
    provider_ref        VARCHAR(100),
    
    -- Status
    status              VARCHAR(20) NOT NULL,  -- 'pending', 'passed', 'failed', 'review'
    
    -- Document details
    document_type       VARCHAR(50),  -- 'passport', 'drivers_license', 'id_card'
    document_country    VARCHAR(2),
    document_number_enc BYTEA,  -- Encrypted
    document_expiry     DATE,
    
    -- Result
    result_details      JSONB,
    rejection_reason    TEXT,
    
    -- Risk
    risk_signals        JSONB,
    
    verified_at         TIMESTAMP WITH TIME ZONE,
    expires_at          TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_kyc_customer ON kyc_records(customer_id);
CREATE INDEX idx_kyc_status ON kyc_records(status);

-- AML suspicious activity
CREATE TABLE aml_alerts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    transaction_id      UUID REFERENCES transactions(id),
    
    -- Alert details
    alert_type          VARCHAR(50) NOT NULL,  -- 'large_cash', 'unusual_pattern', 'sanctioned_country'
    severity            VARCHAR(20) NOT NULL,  -- 'low', 'medium', 'high', 'critical'
    
    -- Status
    status              VARCHAR(20) DEFAULT 'open',  -- 'open', 'investigating', 'cleared', 'sar_filed'
    
    -- Details
    description         TEXT,
    risk_indicators     JSONB,
    
    -- Investigation
    assigned_to         UUID,  -- Compliance officer
    notes               TEXT,
    resolution          TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    resolved_at         TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_aml_customer ON aml_alerts(customer_id);
CREATE INDEX idx_aml_status ON aml_alerts(status);


-- ===========================================
-- SECTION 8: AUDIT LOG (Immutable)
-- ===========================================

CREATE TABLE audit_log (
    id                  BIGSERIAL PRIMARY KEY,
    
    -- What changed
    entity_type         VARCHAR(50) NOT NULL,  -- 'customer', 'account', 'card', 'transaction'
    entity_id           UUID NOT NULL,
    action              VARCHAR(50) NOT NULL,  -- 'create', 'update', 'status_change'
    
    -- Who changed it
    actor_type          VARCHAR(20) NOT NULL,  -- 'customer', 'admin', 'system'
    actor_id            UUID,
    
    -- Change details
    old_values          JSONB,
    new_values          JSONB,
    
    -- Context
    ip_address          INET,
    user_agent          TEXT,
    request_id          UUID,
    
    -- Timestamp (immutable)
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE TABLE audit_log_y2024m01 PARTITION OF audit_log
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_actor ON audit_log(actor_type, actor_id);
CREATE INDEX idx_audit_created ON audit_log(created_at DESC);
```

---

# Part 4: Double-Entry Transfer Function

```sql
-- Transfer money with double-entry ledger
CREATE OR REPLACE FUNCTION transfer_money(
    p_from_account_id UUID,
    p_to_account_id UUID,
    p_amount BIGINT,
    p_currency VARCHAR(3),
    p_description TEXT,
    p_idempotency_key VARCHAR DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_transaction_id UUID := uuid_generate_v4();
    v_from_balance BIGINT;
    v_to_balance BIGINT;
    v_from_currency VARCHAR(3);
    v_to_currency VARCHAR(3);
BEGIN
    -- Check idempotency
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_transaction_id 
        FROM transactions 
        WHERE idempotency_key = p_idempotency_key;
        
        IF FOUND THEN
            RETURN v_transaction_id;  -- Already processed
        END IF;
    END IF;

    -- Lock accounts in consistent order (prevent deadlock)
    IF p_from_account_id < p_to_account_id THEN
        PERFORM 1 FROM accounts WHERE id = p_from_account_id FOR UPDATE;
        PERFORM 1 FROM accounts WHERE id = p_to_account_id FOR UPDATE;
    ELSE
        PERFORM 1 FROM accounts WHERE id = p_to_account_id FOR UPDATE;
        PERFORM 1 FROM accounts WHERE id = p_from_account_id FOR UPDATE;
    END IF;

    -- Get current balances and currencies
    SELECT cached_balance, currency INTO v_from_balance, v_from_currency
    FROM accounts WHERE id = p_from_account_id;
    
    SELECT cached_balance, currency INTO v_to_balance, v_to_currency
    FROM accounts WHERE id = p_to_account_id;

    -- Validate currencies match
    IF v_from_currency != p_currency THEN
        RAISE EXCEPTION 'Currency mismatch: account is %, transfer is %', v_from_currency, p_currency;
    END IF;

    -- Check sufficient balance
    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds: balance %, transfer %', v_from_balance, p_amount;
    END IF;

    -- Create transaction record
    INSERT INTO transactions (
        id, idempotency_key, from_account_id, to_account_id,
        transaction_type, status, amount, currency, description, completed_at
    ) VALUES (
        v_transaction_id, p_idempotency_key, p_from_account_id, p_to_account_id,
        'internal_transfer', 'completed', p_amount, p_currency, p_description, NOW()
    );

    -- Create DEBIT entry (money leaving from_account)
    INSERT INTO ledger_entries (
        transaction_id, account_id, entry_type, amount, currency,
        balance_after, description, reference_type, reference_id, contra_account_id
    ) VALUES (
        v_transaction_id, p_from_account_id, 'debit', p_amount, p_currency,
        v_from_balance - p_amount, p_description, 'transfer', v_transaction_id, p_to_account_id
    );

    -- Create CREDIT entry (money entering to_account)
    INSERT INTO ledger_entries (
        transaction_id, account_id, entry_type, amount, currency,
        balance_after, description, reference_type, reference_id, contra_account_id
    ) VALUES (
        v_transaction_id, p_to_account_id, 'credit', p_amount, 
        CASE WHEN v_from_currency = v_to_currency THEN p_currency ELSE v_to_currency END,
        v_to_balance + p_amount, p_description, 'transfer', v_transaction_id, p_from_account_id
    );

    -- Update cached balances (for read performance)
    UPDATE accounts SET cached_balance = cached_balance - p_amount, cached_at = NOW()
    WHERE id = p_from_account_id;
    
    UPDATE accounts SET cached_balance = cached_balance + p_amount, cached_at = NOW()
    WHERE id = p_to_account_id;

    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql;
```

---

# Part 5: Balance Calculation (Source of Truth)

```sql
-- Calculate TRUE balance from ledger (use for reconciliation)
CREATE OR REPLACE FUNCTION calculate_account_balance(
    p_account_id UUID,
    p_as_of TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) RETURNS BIGINT AS $$
DECLARE
    v_balance BIGINT;
BEGIN
    SELECT COALESCE(
        SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END),
        0
    ) INTO v_balance
    FROM ledger_entries
    WHERE account_id = p_account_id
      AND posted_at <= p_as_of;
    
    RETURN v_balance;
END;
$$ LANGUAGE plpgsql STABLE;

-- Reconcile cached balance with ledger
CREATE OR REPLACE FUNCTION reconcile_balance(p_account_id UUID) 
RETURNS TABLE (
    cached_balance BIGINT,
    ledger_balance BIGINT,
    discrepancy BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.cached_balance,
        calculate_account_balance(p_account_id) AS ledger_balance,
        a.cached_balance - calculate_account_balance(p_account_id) AS discrepancy
    FROM accounts a
    WHERE a.id = p_account_id;
END;
$$ LANGUAGE plpgsql;
```

---

# Part 6: Spending Limits (Redis)

```python
# Real-time spending limit checks in Redis

import redis
from datetime import date, timedelta

class SpendingLimitChecker:
    def __init__(self):
        self.redis = redis.Redis()
    
    def check_and_reserve(
        self, 
        card_id: str, 
        amount: int,  # In cents
        txn_type: str = 'purchase'
    ) -> tuple[bool, str]:
        """
        Check if transaction is within limits and reserve the amount.
        Returns (allowed, reason).
        """
        today = date.today().isoformat()
        month = date.today().strftime('%Y-%m')
        
        # Keys
        daily_key = f"spend:daily:{card_id}:{today}"
        monthly_key = f"spend:monthly:{card_id}:{month}"
        
        # Get limits from cache or DB
        limits = self._get_limits(card_id)
        
        # Check single transaction limit
        if amount > limits['single_txn_limit']:
            return False, 'EXCEEDS_SINGLE_TXN_LIMIT'
        
        # Check daily limit
        current_daily = int(self.redis.get(daily_key) or 0)
        if current_daily + amount > limits['daily_spend_limit']:
            return False, 'EXCEEDS_DAILY_LIMIT'
        
        # Check monthly limit
        current_monthly = int(self.redis.get(monthly_key) or 0)
        if current_monthly + amount > limits['monthly_spend_limit']:
            return False, 'EXCEEDS_MONTHLY_LIMIT'
        
        # Reserve the amount (will be confirmed or released)
        pipe = self.redis.pipeline()
        pipe.incrby(daily_key, amount)
        pipe.expire(daily_key, 86400 * 2)  # 2 days TTL
        pipe.incrby(monthly_key, amount)
        pipe.expire(monthly_key, 86400 * 35)  # ~35 days TTL
        pipe.execute()
        
        return True, 'APPROVED'
    
    def release_reservation(self, card_id: str, amount: int):
        """Release reserved amount on decline or timeout."""
        today = date.today().isoformat()
        month = date.today().strftime('%Y-%m')
        
        pipe = self.redis.pipeline()
        pipe.decrby(f"spend:daily:{card_id}:{today}", amount)
        pipe.decrby(f"spend:monthly:{card_id}:{month}", amount)
        pipe.execute()
    
    def _get_limits(self, card_id: str) -> dict:
        """Get card limits from cache or DB."""
        key = f"limits:{card_id}"
        limits = self.redis.hgetall(key)
        
        if not limits:
            # Fetch from DB and cache
            # card = db.query(Card).get(card_id)
            # limits = {...}
            # self.redis.hmset(key, limits)
            pass
        
        return {
            'single_txn_limit': int(limits.get(b'single_txn_limit', 100000)),
            'daily_spend_limit': int(limits.get(b'daily_spend_limit', 500000)),
            'monthly_spend_limit': int(limits.get(b'monthly_spend_limit', 2000000)),
        }
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Immutable ledger | No UPDATE/DELETE on ledger_entries |
| 2 | Double-entry | Every debit has matching credit |
| 3 | Idempotency keys | transactions.idempotency_key unique |
| 4 | Balance from ledger | calculate_account_balance() as truth |
| 5 | Multi-currency native | currency on every money column |
| 6 | KYC/AML records | kyc_records, aml_alerts tables |
| 7 | Card encryption | PAN and CVV encrypted at rest |
| 8 | Audit trail | audit_log for all changes |

---

# Part 7: DynamoDB Single-Table Design

```
============================================================
NEOBANK: DynamoDB Single-Table Design
For high-scale transaction history and audit logs
(PostgreSQL usually Primary for Ledger, DynamoDB for History)
============================================================

TABLE: banking_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (Merchant/Category queries)
- GSI2: GSI2PK / GSI2SK (Status/Audit queries)

============================================================
ENTITY PATTERNS
============================================================

ACCOUNT PROFILE (Read Model)
  PK: ACCT#{account_id}
  SK: INFO
  
  Attributes: balance, currency, status, tier

TRANSACTION HISTORY (Immutable)
  PK: ACCT#{account_id}
  SK: TXN#{timestamp}#{txn_id}
  GSI1PK: ACCT#{account_id}
  GSI1SK: CAT#{merchant_category}
  
  Attributes: amount, merchant, status, running_balance

CARD CONTROLS
  PK: CARD#{card_id}
  SK: CONTROLS
  
  Attributes: is_frozen, online_limit, atm_limit

KYC DOCUMENT
  PK: CUST#{customer_id}
  SK: KYC#{doc_id}
  
  Attributes: doc_type, status, verification_date

AUDIT LOG (Compliance)
  PK: AUDIT#{entity_id}
  SK: VER#{version_id}
  GSI2PK: AUDIT#{date}
  GSI2SK: ACTOR#{actor_id}
  
  Attributes: changes_json, actor_ip, reasoning

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get account balance (Fast Read)
   Table: PK=ACCT#{account_id}, SK=INFO

2. Get recent transactions (App View)
   Table: PK=ACCT#{account_id}, SK begins_with "TXN#" (Reverse sorted)

3. Get transactions by category (Spending Insights)
   GSI1: PK=ACCT#{account_id}, SK begins_with "CAT#Travel"

4. Get card security settings
   Table: PK=CARD#{card_id}, SK=CONTROLS

5. Get audit history for a user
   Table: PK=AUDIT#{customer_id}, SK begins_with "VER#"

6. Get daily portal audit (Compliance)
   GSI2: PK=AUDIT#{2023-10-27}, SK begins_with "ACTOR#"
```

---

# Part 8: Query Examples with EXPLAIN

```sql
-- ============================================================
-- NEOBANK QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Ledger Reconciliation (The "Truth" Query)
-- ===========================================

-- Summing 1M rows is expensive. Partition pruning is essential.
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    currency,
    SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) as computed_balance
FROM ledger_entries
WHERE account_id = $1
  AND posted_at >= '2024-01-01' -- Hits specific partition
GROUP BY currency;

-- Expected: Index scan on idx_ledger_account per partition.
-- If analyzing >1 year, use pre-calculated monthly snapshots.


-- ===========================================
-- QUERY 2: Transaction List with Merchant Info
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    t.id, t.amount, t.currency, t.status, t.merchant_name,
    c.card_last4,
    t.completed_at
FROM transactions t
LEFT JOIN cards c ON c.id = t.card_id
WHERE t.from_account_id = $1
  AND t.created_at > NOW() - INTERVAL '30 days'
ORDER BY t.created_at DESC
LIMIT 20;

-- Expected: Index scan on idx_txn_from + created_at desc, ~5ms


-- ===========================================
-- QUERY 3: Fraud Detection (Velocity Check)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) 
FROM transactions
WHERE from_account_id = $1
  AND created_at > NOW() - INTERVAL '1 hour'
  AND transaction_type = 'card_purchase'
  AND status = 'completed';

-- Expected: Index scan on idx_txn_from (covering index preferred), ~2ms


-- ===========================================
-- QUERY 4: Find Global Exposure (AML)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    c.id, c.first_name, c.last_name, 
    SUM(t.amount) as total_outflow
FROM transactions t
JOIN accounts a ON a.id = t.from_account_id
JOIN customers c ON c.id = a.customer_id
WHERE t.beneficiary_bic LIKE 'RU%'  -- High risk region
  AND t.created_at > NOW() - INTERVAL '24 hours'
GROUP BY c.id
HAVING SUM(t.amount) > 1000000; -- > $10k

-- Expected: Seq scan on active transactions (~100K rows), <200ms
```

---

# Part 9: Capacity Planning

```
============================================================
NEOBANK CAPACITY PLANNING
============================================================

ASSUMPTIONS (Revolut/Monzo Scale):
- 20M Customers
- 1B Transactions/Year
- Peak: 2,000 TPS (Transactions Per Second)
- Ledger growth: ~5B rows/year (5 entries per txn avg)

============================================================
STORAGE ESTIMATES (1 Year)
============================================================

LEDGER ENTRIES (Append-Only)
  Rows: 5 Billion
  Row Size: ~150 bytes
  Total: ~750 GB/year
  Retention: 7 Years -> 5.25 TB (Partitioned by Month)

TRANSACTIONS (Metadata)
  Rows: 1 Billion
  Row Size: ~500 bytes (with JSONB metadata)
  Total: ~500 GB/year

KYC DOCUMENTS
  Images stored in S3 (Encrypted).
  Metadata in DB: ~20 GB.

AUDIT LOGS
  JSON diffs are heavy.
  ~2 TB/year. Move to Cold Storage after 90 days.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

CARD PROCESSING (Critical Path):
- Auth window: < 200ms
- Redis for balance check is avoiding DB hits.
- Async write to DB for transaction record.

LEDGER WRITES:
- Highly serialized per account (row locks).
- Max throughput per SINGLE account is limited (~100 TPS).
- Global throughput scales horizontally (sharding by account_id).

REPORTING:
- End-of-Day (EOD) processing.
- Massive read spike on Read Replicas.
- Daily snapshots generated for Data Warehouse.

============================================================
SCALING STRATEGY
============================================================

1. SHARDING (By Account ID)
   - Citus or application-level sharding.
   - Cross-shard transfers need 2-Phase Commit (2PC) or Saga.
   
2. ARCHIVAL
   - Move Ledger partitions > 2 years to S3/Parquet.
   - Serve old statements from Data Lake, not OLTP DB.

3. CACHING
   - Balance cache in Redis is critical.
   - Invalidation: On every Ledger insert, update Redis.
```

---

# Part 10: Anti-Patterns to Avoid

```
============================================================
NEOBANK ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Updating Balance in Place
-----------------------------------------
WRONG:
  UPDATE accounts SET balance = balance - 100;
  -- No history. Verify bug? Impossible.
  
RIGHT:
  -- INSERT INTO ledger (debit 100).
  -- Balance is derived or cached (with version check).


❌ ANTI-PATTERN 2: Using Floats for Money
-----------------------------------------
WRONG:
  amount FLOAT = 10.1
  -- Rounding errors accumulate -> Audit failure.
  
RIGHT:
  -- BIGINT (micros/cents) or DECIMAL(20, 4).
  -- Always integer math.


❌ ANTI-PATTERN 3: Implicit Currency
-----------------------------------------
WRONG:
  amount = 100
  -- Is this USD? EUR? GPB?
  
RIGHT:
  -- Composite type: {amount: 100, currency: 'USD'}
  -- Enforced at DB level.


❌ ANTI-PATTERN 4: Storing PAN (Card Number) in Plaintext
-----------------------------------------
WRONG:
  card_number VARCHAR
  -- PCI-DSS violation. Fines + Shutdown.
  
RIGHT:
  -- Store only tokenized ID (from Stripe/Marqeta).
  -- If issuer: Encrypt with HSM-managed keys (separate salt).


❌ ANTI-PATTERN 5: Synchronous Third-Party Calls in Txn
-----------------------------------------
WRONG:
  Begin Txn -> Call KYC Provider -> Commit
  -- Provider down = DB locks held for 30s.
  
RIGHT:
  -- Async workflow.
  -- State: PENDING_KYC -> Webhook -> ACTIVE.


❌ ANTI-PATTERN 6: Hard Deleting Accounts
-----------------------------------------
WRONG:
  DELETE FROM accounts WHERE id = ...
  -- Illegal in banking (regulatory retention required).
  
RIGHT:
  -- Soft delete: `status = 'closed'`.
  -- Retain data for 7+ years.


❌ ANTI-PATTERN 7: Over-locking the Ledger
-----------------------------------------
WRONG:
  LOCK TABLE ledger;
  -- Global lock halts all banking.
  
RIGHT:
  -- Row-level lock on `accounts` table only.
  -- Append-only inserts on `ledger`.


❌ ANTI-PATTERN 8: Mixing OLTP and Analytics
-----------------------------------------
WRONG:
  SELECT SUM(balance) FROM accounts;
  -- Runs on Primary DB -> Latency spike for card payments.
  
RIGHT:
  -- Run analytics on Read Replica or Data Warehouse (Snowflake).


❌ ANTI-PATTERN 9: Assuming Exchange Rates are Static
-----------------------------------------
WRONG:
  rate = 1.2
  -- Rates change every second.
  
RIGHT:
  -- Timestamped rates: `rate_at_txn_time`.
  -- Store the specific rate used for THAT transaction.


❌ ANTI-PATTERN 10: Missing Idempotency
-----------------------------------------
WRONG:
  Retry transfer -> Double debit.
  -- Customer rage.
  
RIGHT:
  -- Idempotency keys on all money movement APIs.
  -- DB unique constraint on `idempotency_key`.
```

---

# Part 11: CDC & Event Streaming

```
============================================================
NEOBANK CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (Primary)   │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ Fraud Eng │    │ Ledger    │   │ Notific.  │  │ Reg. Rep │
  │ (Realtime)│    │ Reconciler│   │ (Mobile)  │  │ (Daily)  │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- bank.ledger.posted      (Trigger recalc, notify user)
- bank.cards.auth         (Fraud analysis)
- bank.kyc.updates        (Unlock account)
- bank.audit.logs         (To long-term WORM storage)

============================================================
DISASTER RECOVERY
============================================================

RPO: 0 (Zero Data Loss) - Required for Banking
RTO: < 15 minutes

STRATEGY:
1. Sync Replication
    - PostgreSQL Synchronous Commit to at least 1 standby.
    - Performance penalty acceptable for data safety.

2. Multi-Region Active-Passive
    - US-EAST-1 (Active) -> US-WEST-2 (Passive).
    - Failover only in catastrophic regional outing.

3. "Bunker" Backup
    - Continuous WAL shipping to an isolated, air-gapped account.
    - Protects against Ransomware/Malicious Admin deletion.
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- NEOBANK: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / REGULATORY TRAIL (SOC2/PCI Critical)
-- ===========================================

CREATE TABLE entity_change_log (
    id                  BIGSERIAL PRIMARY KEY,
    entity_type         VARCHAR(50) NOT NULL,  -- 'account', 'transaction', 'user_kyc'
    entity_id           UUID NOT NULL,
    field_name          VARCHAR(100) NOT NULL,
    old_value           TEXT,  -- Encrypted for sensitive fields
    new_value           TEXT,
    changed_by_id       UUID NOT NULL,
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    change_reason       TEXT NOT NULL,  -- Regulatory requirement
    approval_id         UUID,  -- For dual-control changes
    ip_address          INET,
    user_agent          TEXT
) PARTITION BY RANGE (changed_at);

-- 7-year retention required (PCI-DSS, SOX)
CREATE INDEX idx_ecl_entity ON entity_change_log(entity_type, entity_id);


-- ===========================================
-- B. DOCUMENT STORAGE (KYC)
-- ===========================================

CREATE TABLE user_documents (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id),
    document_type       VARCHAR(50) NOT NULL,  -- 'passport', 'utility_bill', 'selfie'
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    storage_bucket      VARCHAR(100) NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    encryption_key_id   VARCHAR(100) NOT NULL,  -- KMS key
    verification_status VARCHAR(20) DEFAULT 'pending',
    verified_at         TIMESTAMP WITH TIME ZONE,
    expires_at          DATE,  -- Document expiry
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_doc_user ON user_documents(user_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    channel             VARCHAR(20) NOT NULL,  -- 'push', 'sms', 'email'
    recipient           VARCHAR(255) NOT NULL,
    notification_type   VARCHAR(100) NOT NULL,  -- 'transaction_alert', 'login_otp'
    priority            VARCHAR(10) DEFAULT 'normal',  -- 'critical' for fraud alerts
    subject             VARCHAR(255),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS (Partner APIs)
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id          UUID NOT NULL,
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['payment.completed', 'kyc.approved']
    ip_whitelist        INET[],  -- Security requirement
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_deliveries (
    id                  BIGSERIAL PRIMARY KEY,
    subscription_id     UUID NOT NULL REFERENCES webhook_subscriptions(id),
    event_type          VARCHAR(100) NOT NULL,
    payload             JSONB NOT NULL,
    response_code       INT,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- E. API KEYS (Partner Integration)
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id          UUID,
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,  -- ['read:accounts', 'initiate:payments']
    rate_limit_rpm      INT DEFAULT 100,
    ip_whitelist        INET[],
    is_active           BOOLEAN DEFAULT TRUE,
    expires_at          TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at          TIMESTAMP WITH TIME ZONE
);


-- ===========================================
-- F. SSO / MFA
-- ===========================================

CREATE TABLE mfa_devices (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id),
    device_type         VARCHAR(50) NOT NULL,  -- 'totp', 'sms', 'hardware_key'
    device_name         VARCHAR(100),
    secret_enc          BYTEA,  -- Encrypted TOTP secret
    phone_number        VARCHAR(20),
    is_primary          BOOLEAN DEFAULT FALSE,
    last_used_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE oauth_providers (
    id                  SERIAL PRIMARY KEY,
    provider_type       VARCHAR(50) NOT NULL,
    client_id           VARCHAR(255) NOT NULL,
    client_secret_enc   BYTEA NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- G. USER SESSIONS (High Security)
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id),
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_fingerprint  VARCHAR(100),  -- Device fingerprinting
    device_type         VARCHAR(50),
    ip_address          INET NOT NULL,
    geo_country         VARCHAR(2),
    is_active           BOOLEAN DEFAULT TRUE,
    mfa_verified        BOOLEAN DEFAULT FALSE,
    risk_score          DECIMAL(3,2),  -- 0.00 - 1.00
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);

-- Step-up auth for high-risk sessions
CREATE INDEX idx_session_risk ON user_sessions(risk_score) WHERE risk_score > 0.7;


-- ===========================================
-- H. FEATURE FLAGS
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    allowed_user_ids    UUID[],
    required_tier       VARCHAR(20),  -- 'basic', 'premium', 'metal'
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 13: Operational Excellence & Internals

```
============================================================
NEOBANK: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. LEDGER SCALING (THE "HOT WALLET" PROBLEM)
============================================================

THE CHALLENGE:
A "Platform Account" (House Wallet) receives 1000 payouts/sec.
Row-level locks (`SELECT FOR UPDATE`) serialize these transactions -> 100 TPS max.

SOLUTION: BALANCE SHARDING
Instead of 1 row per account, use N rows.
Table: `balance_shards(account_id, shard_id, amount)`.

Write Path:
- Pick random shard_id (1..10).
- `UPDATE balance_shards SET amount = amount + ? WHERE account_id = ? AND shard_id = ?`

Read Path:
- `SELECT SUM(amount) FROM balance_shards WHERE account_id = ?`

BACKGROUND RECONCILIATION:
- Nightly job sums all shards and collapses them into shard 1 to prevent unbounded growth.

============================================================
2. FRAUD DETECTION LATENCY (SYNC VS ASYNC)
============================================================

THE CRITICAL PATH:
Card Swipe -> Neobank Gateway -> (Fraud Check) -> Ledger Debit -> Approve.
SLA: < 200ms total. Fraud Check budget: 50ms.

ARCHITECTURE:
1. Fast Path (Sync): Rule Engine (Redis).
   - Rules: "Txn > $1000?", "Country != Home?", "Velocity > 5 txns/min?".
   - Data: `Redis Counters` (Atomic increments).

2. Slow Path (Async): ML Model.
   - Post-Auth analysis in Kafka consumer.
   - If probability > 0.9, lock account (for future transactions).
   - "Soft Decline": Decline txn but trigger SMS verification.

============================================================
3. IDEMPOTENCY INTERNALS
============================================================

THE RISK:
Upstream Processor (Visa/Mastercard) times out. They retry.
We must NOT debit user twice.

IMPLEMENTATION:
1. Request arrives with `trace_id`.
2. Check `idempotency_store` (Redis/DynamoDB).
   - Key: `txn:{trace_id}`.
   - Value: `status: PROCESSING, created_at: ...`.
3. IF exists AND processing: Return 429 (Wait).
4. IF exists AND completed: Return saved response.
5. IF missing: `INSERT INTO ledger ...` (DB Unique Constraint on `trace_id`).

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Auth Latency (p99)           │ < 500ms │ > 1s = PAGE     │
│  Ledger Invariant Check       │ 0 err   │ > 0 = PAGE (P0) │
│  Gateway Success Rate         │ > 99.99%│ < 99.9% = PAGE  │
│  Fraud False Positive Rate    │ < 0.1%  │ > 0.5% = WARN   │
└─────────────────────────────────────────────────────────────┘

DB METRICS:
- `xact_rollup_time`: Duration of open transactions. Long txns blocks vacuum.
- `deadlocks`: High concurrency on hot accounts.

BUSINESS METRICS:
- `total_assets_under_management`: Real-time sum of all credit balances.
- `float_discrepancy`: Sum(Internal Ledger) vs Sum(Bank Partner Account).

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: PARTNER BANK DOWNTIME
Symptom: External ACH transfers fail.
Mitigation:
- Queue transfers internally (`status = 'PENDING_PARTNER'`).
- Retry with exponential backoff.
- Notify users: "Transfer initiated (Partner Delays)".

SCENARIO 2: LEDGER CORRUPTION (Double Spend)
Symptom: `Sum(credits) != Sum(debits)`.
Mitigation:
- "The Circuit Breaker": If invariant check fails, freeze all money movement.
- Distributed Tracing (OpenTelemetry) to identify the race condition.
- Immutable Ledger: Never UPDATE ledger rows, only INSERT corrective rows.

SCENARIO 3: KYC PROVIDER LATENCY
Symptom: New User Signups hang.
Mitigation:
- Async Onboarding: "Account Created (Limited)".
- Allow login, but block transfers until KYC webhook returns.

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

TIERING STRATEGY:
- "Active Ledger": Past 90 days. PostgreSQL (NVMe).
- "Archive Ledger": Past 7 years. S3 (Parquet). Query via Athena/Trino.

FRAUD VENDOR COSTS:
- External KYC checks cost $1-$2 per user.
- Cache KYC results: "Verified User" status is valid for 1 year.
- Internal Watchlist: Check internal "Bad Actor" DB before calling expensive external vendor.
```

---

## 🔗 Related Documents

- [Stripe Schema](./stripe-schema-design-guide.md) — Payment processing integration
- [Database Scaling](./database-scaling-guide.md) — Partitioning ledger tables
- [Data Compliance](../system-design-notes/data-compliance-guide.md) — PCI-DSS, GDPR
