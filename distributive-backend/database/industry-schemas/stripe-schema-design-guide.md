# Stripe Payments: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Payment Processing, Subscriptions, Webhooks, Multi-Currency Ledger — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Storing full card numbers. PCI-DSS compliance means **tokenization** — store only Stripe IDs, never PANs.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Stripe's Payment Intents](https://stripe.com/docs/payments/payment-intents) | Modern payment flow |
| [Stripe Webhooks Best Practices](https://stripe.com/docs/webhooks/best-practices) | Idempotency |
| [PCI DSS Requirements](https://www.pcisecuritystandards.org/) | Compliance |
| [Double-Entry Bookkeeping](https://en.wikipedia.org/wiki/Double-entry_bookkeeping) | Ledger patterns |

---

## 🎯 The Principal Laws of Payment Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Never Store PANs** | Full card numbers = immediate fail | Tokenize everything with Stripe |
| **Law 2: Idempotency Keys** | Webhooks can retry | Deduplicate on idempotency_key |
| **Law 3: Double-Entry Ledger** | Every debit has a credit | Transaction balances to zero |
| **Law 4: Stripe Is Source of Truth** | Your DB is a mirror | Sync via webhooks, not polling |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get customer payment methods | 1M/s | < 50ms | PostgreSQL + Cache |
| 2 | Create payment intent | 100K/s | < 200ms | PostgreSQL + Stripe API |
| 3 | Process webhook event | 50K/s | < 500ms | PostgreSQL |
| 4 | Get subscription status | 500K/s | < 20ms | PostgreSQL + Cache |
| 5 | Get customer invoice history | 100K/s | < 100ms | PostgreSQL |
| 6 | Record ledger entry | 100K/s | < 100ms | PostgreSQL |
| 7 | Get account balance | 500K/s | < 20ms | Cache + Ledger query |
| 8 | Retry failed payment | 10K/s | < 2s | PostgreSQL + Stripe API |
| 9 | Generate payout | 10K/s | < 1s | PostgreSQL + Stripe API |
| 10 | Fraud check | 100K/s | < 50ms | ML Service |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    PAYMENT SYSTEM ARCHITECTURE                   │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Your Frontend   │────►│  Your Backend    │────►│  Stripe API      │
│  (Stripe.js)     │     │  (Payment Svc)   │     │                  │
│                  │     │                  │     │  • Charges       │
│  Card → Token    │     │  Token → PI      │     │  • Subscriptions │
│  (Client-side)   │     │  (Server-side)   │     │  • Payouts       │
└──────────────────┘     └────────┬─────────┘     └────────┬─────────┘
                                  │                        │
                                  │                        │ Webhooks
                                  ▼                        ▼
                         ┌──────────────────────────────────┐
                         │           PostgreSQL              │
                         │                                   │
                         │  • customers (stripe_customer_id) │
                         │  • payment_methods (tokenized)    │
                         │  • payments (stripe_charge_id)    │
                         │  • subscriptions                  │
                         │  • webhook_events (idempotency)   │
                         │  • ledger_entries (double-entry)  │
                         └──────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- STRIPE SCHEMA: PostgreSQL Production DDL
-- Version: Payment processing and subscription management
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ===========================================
-- SECTION 1: CUSTOMERS
-- ===========================================

CREATE TABLE customers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Stripe reference (source of truth)
    stripe_customer_id  VARCHAR(50) UNIQUE,  -- cus_xxx
    
    -- Local user reference
    user_id             UUID NOT NULL,  -- FK to your users table
    
    -- Contact (mirrored from Stripe)
    email               VARCHAR(255) NOT NULL,
    name                VARCHAR(255),
    phone               VARCHAR(50),
    
    -- Billing address
    address_line1       VARCHAR(255),
    address_line2       VARCHAR(255),
    city                VARCHAR(100),
    state               VARCHAR(100),
    postal_code         VARCHAR(20),
    country             VARCHAR(2),  -- ISO 3166-1 alpha-2
    
    -- Default payment
    default_payment_method_id UUID,
    
    -- Account balance (in smallest currency unit, e.g., cents)
    balance             BIGINT DEFAULT 0,
    currency            VARCHAR(3) DEFAULT 'usd',
    
    -- Metadata
    tax_id              VARCHAR(50),
    tax_exempt          VARCHAR(20) DEFAULT 'none',  -- 'none', 'exempt', 'reverse'
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_customers_stripe ON customers(stripe_customer_id);
CREATE INDEX idx_customers_user ON customers(user_id);
CREATE INDEX idx_customers_email ON customers(email);


-- ===========================================
-- SECTION 2: PAYMENT METHODS (Tokenized)
-- ===========================================

CREATE TYPE payment_method_type AS ENUM ('card', 'bank_account', 'sepa_debit', 'ideal', 'paypal');

CREATE TABLE payment_methods (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    
    -- Stripe reference (source of truth)
    stripe_pm_id        VARCHAR(50) UNIQUE,  -- pm_xxx
    
    method_type         payment_method_type NOT NULL,
    
    -- Card details (safe to store - no PAN)
    card_brand          VARCHAR(20),   -- visa, mastercard, amex
    card_last4          VARCHAR(4),
    card_exp_month      INT,
    card_exp_year       INT,
    card_fingerprint    VARCHAR(50),   -- For duplicate detection
    card_funding        VARCHAR(20),   -- credit, debit, prepaid
    
    -- Bank account (for ACH)
    bank_name           VARCHAR(255),
    bank_last4          VARCHAR(4),
    bank_routing_number VARCHAR(20),   -- Safe to store
    
    -- Billing details
    billing_name        VARCHAR(255),
    billing_email       VARCHAR(255),
    billing_address     JSONB,
    
    -- Status
    is_default          BOOLEAN DEFAULT FALSE,
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_pm_customer ON payment_methods(customer_id);
CREATE INDEX idx_pm_stripe ON payment_methods(stripe_pm_id);
CREATE INDEX idx_pm_fingerprint ON payment_methods(card_fingerprint) WHERE card_fingerprint IS NOT NULL;

-- Add FK to customers
ALTER TABLE customers 
ADD CONSTRAINT fk_customer_default_pm 
FOREIGN KEY (default_payment_method_id) REFERENCES payment_methods(id);


-- ===========================================
-- SECTION 3: PRODUCTS AND PRICES
-- ===========================================

CREATE TABLE products (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stripe_product_id   VARCHAR(50) UNIQUE,  -- prod_xxx
    
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    
    -- Metadata
    is_active           BOOLEAN DEFAULT TRUE,
    metadata            JSONB,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TYPE price_type AS ENUM ('one_time', 'recurring');
CREATE TYPE billing_interval AS ENUM ('day', 'week', 'month', 'year');

CREATE TABLE prices (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id          UUID NOT NULL REFERENCES products(id),
    stripe_price_id     VARCHAR(50) UNIQUE,  -- price_xxx
    
    price_type          price_type NOT NULL,
    
    -- Amount (in smallest currency unit)
    unit_amount         BIGINT NOT NULL,
    currency            VARCHAR(3) NOT NULL,
    
    -- Recurring billing
    billing_interval    billing_interval,
    interval_count      INT DEFAULT 1,
    
    -- Trial
    trial_period_days   INT,
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_prices_product ON prices(product_id);
CREATE INDEX idx_prices_stripe ON prices(stripe_price_id);


-- ===========================================
-- SECTION 4: SUBSCRIPTIONS
-- ===========================================

CREATE TYPE subscription_status AS ENUM (
    'incomplete', 'incomplete_expired', 'trialing', 
    'active', 'past_due', 'canceled', 'unpaid', 'paused'
);

CREATE TABLE subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    stripe_subscription_id VARCHAR(50) UNIQUE,  -- sub_xxx
    
    status              subscription_status NOT NULL,
    
    -- Current period
    current_period_start TIMESTAMP WITH TIME ZONE,
    current_period_end   TIMESTAMP WITH TIME ZONE,
    
    -- Trial
    trial_start         TIMESTAMP WITH TIME ZONE,
    trial_end           TIMESTAMP WITH TIME ZONE,
    
    -- Cancellation
    cancel_at_period_end BOOLEAN DEFAULT FALSE,
    canceled_at         TIMESTAMP WITH TIME ZONE,
    
    -- Payment
    default_payment_method_id UUID REFERENCES payment_methods(id),
    latest_invoice_id   UUID,  -- FK added after invoices table
    
    -- Metadata
    metadata            JSONB,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_subs_customer ON subscriptions(customer_id);
CREATE INDEX idx_subs_stripe ON subscriptions(stripe_subscription_id);
CREATE INDEX idx_subs_status ON subscriptions(status);
CREATE INDEX idx_subs_period_end ON subscriptions(current_period_end);

-- Subscription items (line items)
CREATE TABLE subscription_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id     UUID NOT NULL REFERENCES subscriptions(id),
    stripe_item_id      VARCHAR(50) UNIQUE,  -- si_xxx
    
    price_id            UUID NOT NULL REFERENCES prices(id),
    quantity            INT DEFAULT 1,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_sub_items_sub ON subscription_items(subscription_id);


-- ===========================================
-- SECTION 5: INVOICES
-- ===========================================

CREATE TYPE invoice_status AS ENUM (
    'draft', 'open', 'paid', 'void', 'uncollectible'
);

CREATE TABLE invoices (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    subscription_id     UUID REFERENCES subscriptions(id),
    stripe_invoice_id   VARCHAR(50) UNIQUE,  -- in_xxx
    
    -- Invoice number (for display)
    invoice_number      VARCHAR(50) UNIQUE,
    
    status              invoice_status NOT NULL,
    
    -- Amounts (in smallest currency unit)
    subtotal            BIGINT NOT NULL DEFAULT 0,
    tax                 BIGINT DEFAULT 0,
    total               BIGINT NOT NULL DEFAULT 0,
    amount_due          BIGINT NOT NULL DEFAULT 0,
    amount_paid         BIGINT DEFAULT 0,
    amount_remaining    BIGINT DEFAULT 0,
    currency            VARCHAR(3) NOT NULL,
    
    -- Period
    period_start        TIMESTAMP WITH TIME ZONE,
    period_end          TIMESTAMP WITH TIME ZONE,
    
    -- Due date
    due_date            DATE,
    
    -- Payment
    payment_intent_id   UUID,  -- FK added after payments table
    
    -- URLs
    hosted_invoice_url  TEXT,
    invoice_pdf_url     TEXT,
    
    -- Timestamps
    finalized_at        TIMESTAMP WITH TIME ZONE,
    paid_at             TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_invoices_customer ON invoices(customer_id);
CREATE INDEX idx_invoices_stripe ON invoices(stripe_invoice_id);
CREATE INDEX idx_invoices_subscription ON invoices(subscription_id) WHERE subscription_id IS NOT NULL;
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_due ON invoices(due_date) WHERE status = 'open';

-- Add FK to subscriptions
ALTER TABLE subscriptions 
ADD CONSTRAINT fk_sub_latest_invoice 
FOREIGN KEY (latest_invoice_id) REFERENCES invoices(id);

-- Invoice line items
CREATE TABLE invoice_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_id          UUID NOT NULL REFERENCES invoices(id),
    stripe_item_id      VARCHAR(50),  -- ii_xxx
    
    description         TEXT NOT NULL,
    quantity            INT DEFAULT 1,
    unit_amount         BIGINT NOT NULL,
    amount              BIGINT NOT NULL,
    currency            VARCHAR(3) NOT NULL,
    
    -- Reference to price/product
    price_id            UUID REFERENCES prices(id),
    
    -- Period (for prorations)
    period_start        TIMESTAMP WITH TIME ZONE,
    period_end          TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_invoice_items_invoice ON invoice_items(invoice_id);


-- ===========================================
-- SECTION 6: PAYMENTS (PaymentIntents / Charges)
-- ===========================================

CREATE TYPE payment_status AS ENUM (
    'requires_payment_method', 'requires_confirmation', 'requires_action',
    'processing', 'requires_capture', 'canceled', 'succeeded', 'failed'
);

CREATE TABLE payments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id         UUID REFERENCES customers(id),
    
    -- Stripe references
    stripe_payment_intent_id VARCHAR(50) UNIQUE,  -- pi_xxx
    stripe_charge_id    VARCHAR(50) UNIQUE,       -- ch_xxx
    
    -- Idempotency (critical for retry safety)
    idempotency_key     VARCHAR(255) UNIQUE,
    
    status              payment_status NOT NULL,
    
    -- Amount
    amount              BIGINT NOT NULL,
    amount_received     BIGINT DEFAULT 0,
    currency            VARCHAR(3) NOT NULL,
    
    -- Payment method used
    payment_method_id   UUID REFERENCES payment_methods(id),
    
    -- Metadata
    description         TEXT,
    statement_descriptor VARCHAR(22),
    metadata            JSONB,
    
    -- Outcome
    failure_code        VARCHAR(50),
    failure_message     TEXT,
    
    -- Risk
    risk_level          VARCHAR(20),  -- 'normal', 'elevated', 'highest'
    risk_score          INT,
    
    -- Refund tracking
    amount_refunded     BIGINT DEFAULT 0,
    refunded            BOOLEAN DEFAULT FALSE,
    
    -- Invoice link
    invoice_id          UUID REFERENCES invoices(id),
    
    -- Timestamps
    captured_at         TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_payments_customer ON payments(customer_id);
CREATE INDEX idx_payments_stripe_pi ON payments(stripe_payment_intent_id);
CREATE INDEX idx_payments_stripe_ch ON payments(stripe_charge_id);
CREATE INDEX idx_payments_idempotency ON payments(idempotency_key);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_invoice ON payments(invoice_id) WHERE invoice_id IS NOT NULL;

-- Add FK to invoices
ALTER TABLE invoices 
ADD CONSTRAINT fk_invoice_payment 
FOREIGN KEY (payment_intent_id) REFERENCES payments(id);


-- ===========================================
-- SECTION 7: REFUNDS
-- ===========================================

CREATE TYPE refund_status AS ENUM ('pending', 'succeeded', 'failed', 'canceled');
CREATE TYPE refund_reason AS ENUM ('duplicate', 'fraudulent', 'requested_by_customer');

CREATE TABLE refunds (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_id          UUID NOT NULL REFERENCES payments(id),
    stripe_refund_id    VARCHAR(50) UNIQUE,  -- re_xxx
    
    status              refund_status NOT NULL,
    reason              refund_reason,
    
    amount              BIGINT NOT NULL,
    currency            VARCHAR(3) NOT NULL,
    
    -- Reason description
    description         TEXT,
    
    -- Failure info
    failure_reason      VARCHAR(50),
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_refunds_payment ON refunds(payment_id);
CREATE INDEX idx_refunds_stripe ON refunds(stripe_refund_id);


-- ===========================================
-- SECTION 8: WEBHOOK EVENTS (Idempotency)
-- ===========================================

CREATE TABLE webhook_events (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stripe_event_id     VARCHAR(50) UNIQUE NOT NULL,  -- evt_xxx
    
    event_type          VARCHAR(100) NOT NULL,  -- 'payment_intent.succeeded'
    api_version         VARCHAR(20),
    
    -- Raw payload (for debugging/replay)
    payload             JSONB NOT NULL,
    
    -- Processing status
    processed           BOOLEAN DEFAULT FALSE,
    processed_at        TIMESTAMP WITH TIME ZONE,
    
    -- Error tracking
    processing_error    TEXT,
    retry_count         INT DEFAULT 0,
    next_retry_at       TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_webhooks_stripe ON webhook_events(stripe_event_id);
CREATE INDEX idx_webhooks_type ON webhook_events(event_type);
CREATE INDEX idx_webhooks_unprocessed ON webhook_events(processed) WHERE processed = FALSE;
CREATE INDEX idx_webhooks_retry ON webhook_events(next_retry_at) WHERE processed = FALSE AND next_retry_at IS NOT NULL;


-- ===========================================
-- SECTION 9: DOUBLE-ENTRY LEDGER
-- ===========================================

-- Account types for ledger
CREATE TYPE ledger_account_type AS ENUM (
    'asset',      -- What we own (cash, receivables)
    'liability',  -- What we owe (customer balances, refunds payable)
    'revenue',    -- Income
    'expense'     -- Costs
);

CREATE TABLE ledger_accounts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code                VARCHAR(20) UNIQUE NOT NULL,
    name                VARCHAR(100) NOT NULL,
    account_type        ledger_account_type NOT NULL,
    currency            VARCHAR(3) NOT NULL DEFAULT 'usd',
    
    -- Current balance (denormalized, updated by trigger)
    balance             BIGINT NOT NULL DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Standard accounts
INSERT INTO ledger_accounts (code, name, account_type) VALUES
    ('1000', 'Cash', 'asset'),
    ('1100', 'Stripe Receivables', 'asset'),
    ('1200', 'Accounts Receivable', 'asset'),
    ('2000', 'Customer Balances', 'liability'),
    ('2100', 'Refunds Payable', 'liability'),
    ('4000', 'Revenue', 'revenue'),
    ('4100', 'Subscription Revenue', 'revenue'),
    ('5000', 'Processing Fees', 'expense'),
    ('5100', 'Refund Expense', 'expense');

-- Ledger entries (append-only, immutable)
CREATE TABLE ledger_entries (
    id                  BIGSERIAL PRIMARY KEY,
    
    -- Journal reference (groups entries)
    journal_id          UUID NOT NULL,
    journal_date        DATE NOT NULL,
    
    -- Entry details
    account_id          UUID NOT NULL REFERENCES ledger_accounts(id),
    debit               BIGINT DEFAULT 0,
    credit              BIGINT DEFAULT 0,
    currency            VARCHAR(3) NOT NULL,
    
    -- Reference to source transaction
    reference_type      VARCHAR(50),  -- 'payment', 'refund', 'subscription'
    reference_id        UUID,
    
    -- Description
    description         TEXT,
    
    -- Immutability marker
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT ck_debit_xor_credit CHECK (
        (debit > 0 AND credit = 0) OR (debit = 0 AND credit > 0)
    )
) PARTITION BY RANGE (journal_date);

-- Monthly partitions
CREATE TABLE ledger_entries_y2024m01 PARTITION OF ledger_entries
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE INDEX idx_ledger_journal ON ledger_entries(journal_id);
CREATE INDEX idx_ledger_account ON ledger_entries(account_id);
CREATE INDEX idx_ledger_reference ON ledger_entries(reference_type, reference_id);
CREATE INDEX idx_ledger_date ON ledger_entries(journal_date);


-- ===========================================
-- SECTION 10: PAYOUTS (To Connected Accounts)
-- ===========================================

CREATE TYPE payout_status AS ENUM ('pending', 'in_transit', 'paid', 'failed', 'canceled');

CREATE TABLE payouts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stripe_payout_id    VARCHAR(50) UNIQUE,  -- po_xxx
    
    -- Destination
    destination_type    VARCHAR(50) NOT NULL,  -- 'bank_account', 'card'
    destination_last4   VARCHAR(4),
    
    amount              BIGINT NOT NULL,
    currency            VARCHAR(3) NOT NULL,
    
    status              payout_status NOT NULL,
    
    -- Dates
    arrival_date        DATE,
    
    -- Failure info
    failure_code        VARCHAR(50),
    failure_message     TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_payouts_stripe ON payouts(stripe_payout_id);
CREATE INDEX idx_payouts_status ON payouts(status);
```

---

# Part 4: Idempotent Webhook Handler

```sql
-- Process webhook event idempotently
CREATE OR REPLACE FUNCTION process_webhook_event(
    p_stripe_event_id VARCHAR,
    p_event_type VARCHAR,
    p_payload JSONB
) RETURNS BOOLEAN AS $$
DECLARE
    v_already_processed BOOLEAN;
BEGIN
    -- Check if already processed (idempotency)
    SELECT processed INTO v_already_processed
    FROM webhook_events
    WHERE stripe_event_id = p_stripe_event_id
    FOR UPDATE SKIP LOCKED;
    
    IF v_already_processed IS NOT NULL THEN
        IF v_already_processed THEN
            -- Already successfully processed
            RETURN TRUE;
        END IF;
        -- Being processed by another worker, skip
        RETURN FALSE;
    END IF;
    
    -- Insert new event
    INSERT INTO webhook_events (stripe_event_id, event_type, payload)
    VALUES (p_stripe_event_id, p_event_type, p_payload)
    ON CONFLICT (stripe_event_id) DO NOTHING;
    
    -- Process based on event type
    CASE p_event_type
        WHEN 'payment_intent.succeeded' THEN
            PERFORM handle_payment_succeeded(p_payload);
        WHEN 'payment_intent.payment_failed' THEN
            PERFORM handle_payment_failed(p_payload);
        WHEN 'customer.subscription.created' THEN
            PERFORM handle_subscription_created(p_payload);
        WHEN 'customer.subscription.updated' THEN
            PERFORM handle_subscription_updated(p_payload);
        WHEN 'customer.subscription.deleted' THEN
            PERFORM handle_subscription_deleted(p_payload);
        WHEN 'invoice.paid' THEN
            PERFORM handle_invoice_paid(p_payload);
        WHEN 'invoice.payment_failed' THEN
            PERFORM handle_invoice_failed(p_payload);
        ELSE
            -- Unknown event type, log but don't fail
            NULL;
    END CASE;
    
    -- Mark as processed
    UPDATE webhook_events
    SET processed = TRUE, processed_at = NOW()
    WHERE stripe_event_id = p_stripe_event_id;
    
    RETURN TRUE;
    
EXCEPTION WHEN OTHERS THEN
    -- Log error, increment retry
    UPDATE webhook_events
    SET processing_error = SQLERRM,
        retry_count = retry_count + 1,
        next_retry_at = NOW() + (retry_count * INTERVAL '1 minute')
    WHERE stripe_event_id = p_stripe_event_id;
    
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;


-- Handle payment succeeded
CREATE OR REPLACE FUNCTION handle_payment_succeeded(p_payload JSONB)
RETURNS VOID AS $$
DECLARE
    v_pi_id VARCHAR;
    v_amount BIGINT;
    v_currency VARCHAR;
    v_journal_id UUID;
BEGIN
    v_pi_id := p_payload->'data'->'object'->>'id';
    v_amount := (p_payload->'data'->'object'->>'amount_received')::BIGINT;
    v_currency := p_payload->'data'->'object'->>'currency';
    v_journal_id := uuid_generate_v4();
    
    -- Update payment status
    UPDATE payments
    SET status = 'succeeded',
        amount_received = v_amount,
        captured_at = NOW(),
        updated_at = NOW()
    WHERE stripe_payment_intent_id = v_pi_id;
    
    -- Create ledger entries (double-entry)
    -- Debit: Cash (asset increases)
    INSERT INTO ledger_entries (journal_id, journal_date, account_id, debit, currency, reference_type, reference_id, description)
    SELECT v_journal_id, CURRENT_DATE, la.id, v_amount, v_currency, 'payment', p.id, 'Payment received'
    FROM ledger_accounts la, payments p
    WHERE la.code = '1000' AND p.stripe_payment_intent_id = v_pi_id;
    
    -- Credit: Revenue (revenue increases)
    INSERT INTO ledger_entries (journal_id, journal_date, account_id, credit, currency, reference_type, reference_id, description)
    SELECT v_journal_id, CURRENT_DATE, la.id, v_amount, v_currency, 'payment', p.id, 'Revenue recognized'
    FROM ledger_accounts la, payments p
    WHERE la.code = '4000' AND p.stripe_payment_intent_id = v_pi_id;
    
    -- Update account balances
    UPDATE ledger_accounts SET balance = balance + v_amount WHERE code = '1000';
    UPDATE ledger_accounts SET balance = balance + v_amount WHERE code = '4000';
END;
$$ LANGUAGE plpgsql;
```

---

# Part 5: Subscription Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    SUBSCRIPTION LIFECYCLE                        │
└─────────────────────────────────────────────────────────────────┘

                    ┌─────────────┐
                    │  incomplete │ ─── requires payment method
                    └──────┬──────┘
                           │ payment succeeded
                           ▼
┌─────────────────┐  ┌───────────┐  ┌─────────────────┐
│  incomplete_    │  │ trialing  │──►│    active       │
│  expired        │  └───────────┘   └────────┬────────┘
└─────────────────┘   trial ends              │
                           │                  │ payment fails
                           ▼                  ▼
                    ┌───────────┐       ┌───────────┐
                    │  active   │◄──────│ past_due  │
                    └─────┬─────┘ retry └─────┬─────┘
                          │ succeeds          │ exhausted
                          │                   ▼
                   ┌──────┴──────┐      ┌───────────┐
                   │             │      │  unpaid   │
                   │  cancel_at  │      └───────────┘
                   │  period_end │
                   └──────┬──────┘
                          │ period ends
                          ▼
                    ┌───────────┐
                    │ canceled  │
                    └───────────┘
```

---

# Part 6: Multi-Currency Support

```sql
-- Exchange rates (updated daily)
CREATE TABLE exchange_rates (
    id                  SERIAL PRIMARY KEY,
    base_currency       VARCHAR(3) NOT NULL DEFAULT 'usd',
    target_currency     VARCHAR(3) NOT NULL,
    rate                DECIMAL(18, 8) NOT NULL,
    valid_from          DATE NOT NULL,
    valid_to            DATE,
    
    CONSTRAINT uk_rate UNIQUE (base_currency, target_currency, valid_from)
);

CREATE INDEX idx_rates_lookup ON exchange_rates(base_currency, target_currency, valid_from);

-- Convert amount between currencies
CREATE OR REPLACE FUNCTION convert_currency(
    p_amount BIGINT,
    p_from_currency VARCHAR,
    p_to_currency VARCHAR,
    p_date DATE DEFAULT CURRENT_DATE
) RETURNS BIGINT AS $$
DECLARE
    v_rate DECIMAL;
BEGIN
    IF p_from_currency = p_to_currency THEN
        RETURN p_amount;
    END IF;
    
    SELECT rate INTO v_rate
    FROM exchange_rates
    WHERE base_currency = p_from_currency
      AND target_currency = p_to_currency
      AND valid_from <= p_date
      AND (valid_to IS NULL OR valid_to > p_date)
    ORDER BY valid_from DESC
    LIMIT 1;
    
    IF v_rate IS NULL THEN
        RAISE EXCEPTION 'Exchange rate not found for % to %', p_from_currency, p_to_currency;
    END IF;
    
    RETURN ROUND(p_amount * v_rate);
END;
$$ LANGUAGE plpgsql STABLE;
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | No PANs stored | Only stripe_pm_id, last4, fingerprint |
| 2 | Idempotency keys | webhook_events.stripe_event_id unique |
| 3 | Double-entry ledger | Every debit has matching credit |
| 4 | Webhook retry logic | retry_count, next_retry_at |
| 5 | Subscription state machine | All transitions defined |
| 6 | Invoice → Payment linkage | payment_intent_id on invoices |
| 7 | Refund tracking | amount_refunded on payments |
| 8 | Multi-currency support | currency on all money columns |

---

# Part 7: DynamoDB Single-Table Design

```
============================================================
STRIPE: DynamoDB Single-Table Design
For high-scale webhook logs and idempotency keys
(PostgreSQL remains Primary for Ledger and Relational Data)
============================================================

TABLE: stripe_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (Customer/Subscription queries)
- GSI2: GSI2PK / GSI2SK (Event/Status queries)

============================================================
ENTITY PATTERNS
============================================================

WEBHOOK EVENT LOG (Immutable)
  PK: EVT#{event_id}
  SK: INFO
  
  Attributes: type, payload_json, processed_at, status

IDEMPOTENCY LOCK
  PK: LOCK#{idempotency_key}
  SK: META
  
  Attributes: created_at, expires_at, response_payload

CUSTOMER SUBSCRIPTION HISTORY
  PK: CUST#{customer_id}
  SK: SUB#{subscription_id}#{timestamp}
  GSI1PK: CUST#{customer_id}
  GSI1SK: STATUS#{status}
  
  Attributes: plan_id, status, period_end

API REQUEST LOG (Audit)
  PK: REQ#{request_id}
  SK: INFO
  GSI2PK: API#{user_id}
  GSI2SK: TS#{timestamp}
  
  Attributes: endpoint, method, response_code, latency_ms

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Check if webhook event processed (Idempotency)
   Table: PK=EVT#{event_id}, SK=INFO

2. Get logic lock for transaction
   Table: PK=LOCK#{key}, SK=META (Consistent Read)

3. Get subscription audit history
   Table: PK=CUST#{customer_id}, SK begins_with "SUB#"

4. Get API logs for a user (Troubleshooting)
   GSI2: PK=API#{user_id}, SK > TS#{yesterday}
```

---

# Part 8: Query Examples with EXPLAIN

```sql
-- ============================================================
-- STRIPE QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Monthly Recurring Revenue (MRR)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    DATE_TRUNC('month', created_at) as month,
    SUM(p.unit_amount * si.quantity) / 100.0 as mrr_usd
FROM subscriptions s
JOIN subscription_items si ON si.subscription_id = s.id
JOIN prices p ON p.id = si.price_id
WHERE s.status IN ('active', 'trialing')
  AND p.billing_interval = 'month'
GROUP BY 1
ORDER BY 1 DESC;

-- Expected: Hash Join between active subs and items. 
-- Ensure idx_subs_status exists.


-- ===========================================
-- QUERY 2: Find Unpaid Invoices (Dunning)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    i.id, i.customer_id, i.amount_due, i.due_date,
    c.email, c.stripe_customer_id
FROM invoices i
JOIN customers c ON c.id = i.customer_id
WHERE i.status = 'open'
  AND i.due_date < CURRENT_DATE
  AND i.amount_due > 0
ORDER BY i.due_date ASC;

-- Expected: Index scan on idx_invoices_due.


-- ===========================================
-- QUERY 3: Ledger Reconciliation (Cash vs Stripe)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    la.name,
    SUM(le.debit - le.credit) as balance
FROM ledger_entries le
JOIN ledger_accounts la ON la.id = le.account_id
WHERE le.journal_date BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY la.name;

-- Expected: Parallel Seq Scan on partition `ledger_entries_y2023`.
-- Essential query for Accounting closing.


-- ===========================================
-- QUERY 4: Webhook Failure Analysis
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    event_type, 
    COUNT(*) as failure_count,
    AVG(retry_count) as avg_retries
FROM webhook_events
WHERE processed = FALSE
  AND created_at > NOW() - INTERVAL '24 hours'
GROUP BY event_type;

-- Expected: Index scan on idx_webhooks_unprocessed.
```

---

# Part 9: Capacity Planning

```
============================================================
STRIPE CAPACITY PLANNING
============================================================

ASSUMPTIONS (Scale X):
- 1B API Requests/Day
- 50M Webhook Events/Day
- 10M Active Subscriptions
- 99.999% Availability Required (Five 9s)

============================================================
STORAGE ESTIMATES
============================================================

LEDGER (PostgreSQL)
  Strictly append-only.
  Rows: 1B/year (20 entries per payment).
  Row Size: ~200 bytes.
  Total: ~200 GB/year.
  Retention: Forever (Financial Record).

WEBHOOK LOGS
  Rows: 15B/year.
  Total: ~15 TB/year.
  Strategy: Move processed events to S3/Data Lake after 7 days.
  Keep only "Failed/Pending" in hot DB.

API IDEMPOTENCY KEYS (Redis/Dynamo)
  TTL: 24 hours (Stripe standard).
  Size: 1KB per key.
  Volume: 1B keys rolling window = 1 TB RAM/Storage.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

PAYMENT PROCESSING (Write Critical):
- 1000 TPS sustained, 10K TPS peak (Black Friday).
- Latency P99 < 500ms.
- Bottlebeck: Locking row for Inventory/Balance.

WEBHOOK INGESTION (Write Heavy):
- 50K events/sec via SQS/Kafka.
- Postgres Worker pool must process active events.
- "Thundering Herd" protection: Jutter retires.

REPORTING (Read Heavy):
- "Get Dashboard" queries sum millions of rows.
- Use Pre-aggregated Materialized Views updated by triggers.

============================================================
SCALING STRATEGY
============================================================

1. SHARDING (By Merchant/Account)
   - Data for "Uber" lives on Shard 1, "Lyft" on Shard 2.
   - Global lookup table for Account -> Shard mapping.

2. HOT WALLET PATTERN
   - Don't write to one "Corporate Cash" account row for every txn.
   - Shard the internal cash account (Cash_1, Cash_2... Cash_N).
   - Randomly pick 1 to credit. Sum all for total.

3. READ REPLICAS
   - 10 Replicas for Dashboard reads.
   - 1 Master for Writes.
   - synchronous_commit = on (for Payments, never lose data).
```

---

# Part 10: Anti-Patterns to Avoid

```
============================================================
STRIPE ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Storing Card Numbers (PAN)
-----------------------------------------
WRONG:
  INSERT INTO cards (number, cvc) ...
  -- Instant PCI violation. Audit failure.
  
RIGHT:
  -- Tokenize via Stripe Elements (JS).
  -- Store `pm_12345` (Payment Method ID).


❌ ANTI-PATTERN 2: Trusting Client-Side Prices
-----------------------------------------
WRONG:
  POST /checkout { amount: 1000 }
  -- User can edit HTML to send { amount: 1 }.
  
RIGHT:
  -- Pass `price_id`. Server looks up amount from DB.
  -- Compare calculated total with Stripe session total.


❌ ANTI-PATTERN 3: Processing Webhooks Synchronously
-----------------------------------------
WRONG:
  Receive Webhook -> Update DB -> Send Email -> Return 200.
  -- If Email fails, Stripe thinks DB update failed and retries.
  -- Double credit!
  
RIGHT:
  -- Receive Webhook -> Push to Queue -> Return 200.
  -- Worker processes Queue idempotently.


❌ ANTI-PATTERN 4: Polling for Payment Status
-----------------------------------------
WRONG:
  While status == 'processing': poll Stripe API.
  -- Rate limits will ban you.
  
RIGHT:
  -- Listen for `payment_intent.succeeded` webhook.
  -- UI shows "Processing" until WebSocket pushes success.


❌ ANTI-PATTERN 5: Modifying Ledger Entries
-----------------------------------------
WRONG:
  UPDATE ledger SET amount = 50 WHERE id = 123.
  -- Fraud vector. Unauditable.
  
RIGHT:
  -- Immutable Rows.
  -- To fix error: Insert "Correction Debit" and "Correction Credit".


❌ ANTI-PATTERN 6: Floating Point Money
-----------------------------------------
WRONG:
  price = 19.99 (float)
  -- 0.1 + 0.2 = 0.300000004.
  
RIGHT:
  -- Integer Cents: 1999.
  -- Currency column on every row.


❌ ANTI-PATTERN 7: Global Locks on Payout
-----------------------------------------
WRONG:
  LOCK TABLE payments; -- to calculate payout
  -- Stops all checkout traffic.
  
RIGHT:
  -- Select available balance using MVCC (Snapshot Isolation).
  -- Mark items as "Included in Payout X" using a batch update ID.


❌ ANTI-PATTERN 8: Ignoring Idempotency on Retries
-----------------------------------------
WRONG:
  Network timeout on "Charge Card". Retry immediately.
  -- Customer charged twice.
  
RIGHT:
  -- Send `Idempotency-Key: uuid` header to Stripe.
  -- Stripe returns cached "Success" for same key.


❌ ANTI-PATTERN 9: Hard Deleting Customers
-----------------------------------------
WRONG:
  DELETE FROM customers WHERE id = 1.
  -- Orphand payments. Broken history.
  
RIGHT:
  -- GDPR "Right to be Forgotten" requires scrubbing PII (name/email).
  -- Keep Transaction ID / Amount / Date for Tax Audits.


❌ ANTI-PATTERN 10: Using Stripe as Primary DB
-----------------------------------------
WRONG:
  GET /v1/customers to find user email.
  -- Slow, Rate limited.
  
RIGHT:
  -- Sync Stripe data to local Postgres.
  -- Use local DB for reads, Stripe for writes.
```

---

# Part 11: CDC & Event Streaming

```
============================================================
STRIPE CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (Ledger)    │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ Fraud     │    │ ERP Sync  │   │ Analytics │  │ Email    │
  │ Detection │    │ (NetSuite)│   │ (Looker)  │  │ Receipt  │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- payment.captured        (Send Receipt, Credit Balance)
- subscription.churned    (Trigger Win-back email)
- invoice.finalized       (Sync to NetSuite/Xero)
- dispute.created         (Alert Risk Team)

============================================================
DISASTER RECOVERY
============================================================

RPO: 0 (Zero Data Loss) - Financial Requirement
RTO: < 15 minutes

STRATEGY:
1. Multi-Region Active-Passive
   - Primary: us-east-1. Standby: us-west-2.
   - Async replication for Read Replicas.
   - Sync replication for "Bunker" node (ensure 0 data loss).

2. Point-In-Time Recovery (PITR)
   - WAL Archiving every 60 seconds.
   - Recovery Drill every quarter.

3. "Circuit Breaker"
   - If DB is down, queue API requests in Redis/Kafka.
   - Replay once DB is up.
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- STRIPE: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / CHANGE HISTORY (PCI Critical)
-- ===========================================

CREATE TABLE entity_change_log (
    id                  BIGSERIAL PRIMARY KEY,
    account_id          UUID NOT NULL,
    entity_type         VARCHAR(50) NOT NULL,  -- 'customer', 'subscription', 'payout_settings'
    entity_id           UUID NOT NULL,
    field_name          VARCHAR(100) NOT NULL,
    old_value           TEXT,  -- Masked for sensitive
    new_value           TEXT,
    changed_by_type     VARCHAR(20) NOT NULL,  -- 'user', 'api', 'system'
    changed_by_id       UUID,
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address          INET,
    api_key_id          UUID
) PARTITION BY RANGE (changed_at);

-- 7-year retention (PCI-DSS)
CREATE INDEX idx_ecl_entity ON entity_change_log(account_id, entity_type, entity_id);


-- ===========================================
-- B. DOCUMENT STORAGE (Identity Verification)
-- ===========================================

CREATE TABLE identity_documents (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    document_type       VARCHAR(50) NOT NULL,  -- 'passport', 'business_license'
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    encryption_key_id   VARCHAR(100) NOT NULL,
    verification_status VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    account_id          UUID NOT NULL,
    channel             VARCHAR(20) NOT NULL,  -- 'email', 'webhook'
    recipient           VARCHAR(255) NOT NULL,
    notification_type   VARCHAR(100) NOT NULL,  -- 'payout_sent', 'dispute_opened'
    subject             VARCHAR(255),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS (Core Feature)
-- ===========================================

CREATE TABLE webhook_endpoints (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    enabled_events      TEXT[] NOT NULL,  -- ['payment_intent.succeeded', '*']
    api_version         VARCHAR(20),
    status              VARCHAR(20) DEFAULT 'enabled',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_events (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL,
    event_type          VARCHAR(100) NOT NULL,
    api_version         VARCHAR(20),
    data                JSONB NOT NULL,
    pending_webhooks    INT DEFAULT 0,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE TABLE webhook_attempts (
    id                  BIGSERIAL PRIMARY KEY,
    webhook_event_id    UUID NOT NULL REFERENCES webhook_events(id),
    endpoint_id         UUID NOT NULL REFERENCES webhook_endpoints(id),
    response_code       INT,
    response_body       TEXT,
    response_time_ms    INT,
    status              VARCHAR(20) DEFAULT 'pending',
    next_retry_at       TIMESTAMP WITH TIME ZONE,
    attempt_number      INT DEFAULT 1,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- E. API KEYS (Live/Test Mode)
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    key_type            VARCHAR(20) NOT NULL,  -- 'secret', 'publishable', 'restricted'
    mode                VARCHAR(10) NOT NULL,  -- 'live', 'test'
    key_prefix          VARCHAR(8) NOT NULL,  -- 'sk_live_', 'pk_test_'
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100),
    permissions         JSONB,  -- For restricted keys
    rate_limit_rpm      INT DEFAULT 100,
    is_active           BOOLEAN DEFAULT TRUE,
    last_used_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_api_key_hash ON api_keys(key_hash);


-- ===========================================
-- F. OAUTH (Platform Connect)
-- ===========================================

CREATE TABLE oauth_applications (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    name                VARCHAR(100) NOT NULL,
    client_id           VARCHAR(64) NOT NULL UNIQUE,
    redirect_uris       TEXT[],
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE oauth_authorizations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    connected_account_id UUID NOT NULL REFERENCES accounts(id),
    application_id      UUID NOT NULL REFERENCES oauth_applications(id),
    access_token_hash   VARCHAR(64) NOT NULL,
    refresh_token_hash  VARCHAR(64),
    scopes              TEXT[],
    stripe_user_id      VARCHAR(50),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at          TIMESTAMP WITH TIME ZONE
);


-- ===========================================
-- G. USER SESSIONS
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    account_id          UUID NOT NULL,
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_type         VARCHAR(50),
    ip_address          INET NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    mfa_verified        BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS (Test Mode Beta)
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    allowed_account_ids UUID[],
    required_plan       VARCHAR(50),  -- 'startup', 'scale', 'enterprise'
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
STRIPE: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. IDEMPOTENCY KEY INTERNALS
============================================================

THE CHALLENGE:
Network timeouts are inevitable. If a client retries a charge, we must not charge twice.
Metric: 0.000000% tolerance for double-charges.

IMPLEMENTATION (ATOMIC LOCKING):
1. Client sends `Idempotency-Key: random_uuid` header.
2. API Layer checks Redis: `GET idempotency:{key}`
   - IF "processing": Return 409 Conflict (Client waits/retries).
   - IF "completed": Return saved response JSON (from Redis/DB).
   - IF missing: `SETNX idempotency:{key} "processing" EX 24h`

DATABASE CONSTRAINT (Ultimate Safety):
Table: idempotency_keys
Columns: (key_hash, user_id, request_params_hash, response_code, response_body)
Constraint: UNIQUE(user_id, key_hash)

RACE CONDITION PREVENTION:
- The `SETNX` in Redis is the "Fast Lock".
- The `INSERT UNIQUE` in Postgres is the "Hard Lock".
- If DB insert fails with UniqueViolation, we fetch the existing result.

============================================================
2. LEDGER INTEGRITY (DOUBLE-ENTRY)
============================================================

INVARIANT CHECKING (The "Nightly Reconciliation"):
A background job runs strict checks on the Ledger table:
1. Sum(credits) - Sum(debits) MUST == 0 for every transaction_group.
2. Balance(Account) MUST == Sum(all_ledger_entries_for_account).
3. Sequence numbers MUST be contiguous (no gaps).

LOCKING STRATEGY (Hot Wallet Problem):
Challenge: "Platform Account" receives 1000 payments/sec. Row lock contention.
Solution: "Balance Buffering" via Redis or App-Layer Aggregation.
- Write raw `ledger_entries` (Append Only) - High throughput.
- Update `balances` table asynchronously (e.g., every 1s or via trigger).
- For READS: `balance = stored_balance + sum(recent_entries)`.

============================================================
3. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  API Availability             │ > 99.99%│ < 99.9% = PAGE  │
│  p99 Charge Latency           │ < 2s    │ > 4s = WARN     │
│  Webhook Delivery Success     │ > 99.5% │ < 99% = PAGE    │
│  Ledger Invariant Violation   │ 0       │ > 0 = PAGE (P0) │
│  Idempotency Replays          │ N/A     │ Spike = INFO    │
└─────────────────────────────────────────────────────────────┘

POSTGRES METRICS:
- `txid_current`: Watch for rapid ID consumption (32-bit wrap risk, though huge in 64-bit).
- `dead_tuples`: High update rate on `balances` causes bloat. Tune autovacuum scale factor.
- `temp_files`: Complex reporting queries spilling to disk.

REDIS METRICS (Rate Limiters):
- `expired_keys`: High rate is normal (sliding windows expiring).
- `rejected_connections`: Client pool exhaustion.

ALERTING RULES:
```yaml
- alert: LedgerImbalance
  expr: stripe_ledger_invariant_check != 0
  labels: { severity: critical }

- alert: WebhookBacklog
  expr: webhook_queue_depth > 50000
  for: 5m
  labels: { severity: warning }
```

============================================================
4. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: UPSTREAM BANK GATEWAY TIMEOUT
Symptom: Payment API hangs for 30s.
Impact: Clients retry, risking double charge (mitigated by Idempotency).
Mitigation:
- Circuit Breaker: Fail fast if Bank X is down.
- "Pending" State: Record charge as `status='pending_processor'`.
- Polling: Background job polls Bank API for final status.

SCENARIO 2: WEBHOOK SYSTEM OUTAGE
Symptom: Merchants don't know payment succeeded.
Impact: Supply execution delayed.
Mitigation:
- Durability: Kafka/SQS stores events for 7 days.
- Exponential Backoff: Retry at 1m, 5m, 1h, 6h, 1d, 3d.
- Manual Replay API: Allow merchants to request event replay.

SCENARIO 3: "HOT WALLET" CONTENTION
Symptom: DB CPU spikes due to lock waits on one row.
Impact: API latency increases for all users.
Mitigation:
- Sharded Balances: Split hot account into 10 sub-rows (`balance_shard_1`...`balance_shard_10`).
- Randomly pick shard to credit. Sum all shards for total.

============================================================
5. FINOPS & COST OPTIMIZATION
============================================================

TIERING STRATEGY:
┌─────────────────────────────────────────────────────────────┐
│  DATA              │ AGE       │ STORAGE      │ ACCESS     │
├─────────────────────────────────────────────────────────────┤
│  Active Charges    │ < 1 year  │ PostgreSQL   │ Real-time  │
│  Historical Txns   │ > 1 year  │ S3 (Iceberg) │ Reporting  │
│  Events/Logs       │ > 30 days │ S3 (ZSTD)    │ Audit      │
│  PCI Data (Cards)  │ Active    │ Vault (Enc)  │ Tokenized  │
└─────────────────────────────────────────────────────────────┘

ARCHIVAL STRATEGY:
- "Cold" customers (churned > 2 years) moved to archival tables.
- `charges_archive_2020`, `charges_archive_2021` (Partitioned).
- Saves expensive NVMe storage on primary DB.

INSTANCE SIZING:
- Primary DB: r6g.16xlarge (512GB RAM) for working set.
- Reporting DB: Read Replicas (x5) for merchant dashboards.
```

---

## 🔗 Related Documents

- [JIRA Schema](./jira-schema-design-guide.md) — Complex entity relationships
- [Authorization Guide](./authorization-schema-design-guide.md) — ACL patterns for team billing
- [Database Scaling](./database-scaling-guide.md) — Sharding by customer_id
