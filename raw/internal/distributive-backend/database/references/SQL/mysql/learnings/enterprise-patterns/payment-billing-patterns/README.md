# Payment & Billing Patterns

Real-world payment processing, subscription billing, and financial transaction patterns used by product engineers at Netflix, Stripe, PayPal, Atlassian, and other payment-focused companies.

## 🚀 Subscription Billing Patterns

### The "Netflix-Style Subscription" Pattern
```sql
-- Subscription plans and pricing
CREATE TABLE subscription_plans (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    plan_name VARCHAR(100) NOT NULL,
    plan_code VARCHAR(50) UNIQUE NOT NULL,  -- 'basic', 'standard', 'premium'
    billing_cycle ENUM('monthly', 'quarterly', 'yearly') NOT NULL,
    base_price DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    features JSON NOT NULL,  -- Array of features included
    max_users INT DEFAULT 1,
    max_storage_gb INT DEFAULT 10,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_plan_code (plan_code, is_active),
    INDEX idx_billing_cycle (billing_cycle, base_price),
    INDEX idx_features ((CAST(features->>'$.streaming_quality' AS CHAR(20))))
);

-- User subscriptions
CREATE TABLE user_subscriptions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    plan_id BIGINT NOT NULL,
    subscription_status ENUM('active', 'cancelled', 'paused', 'expired', 'past_due') DEFAULT 'active',
    current_period_start TIMESTAMP NOT NULL,
    current_period_end TIMESTAMP NOT NULL,
    billing_cycle ENUM('monthly', 'quarterly', 'yearly') NOT NULL,
    amount_paid DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    auto_renew BOOLEAN DEFAULT TRUE,
    payment_method_id VARCHAR(100) NULL,
    last_payment_date TIMESTAMP NULL,
    next_billing_date TIMESTAMP NOT NULL,
    cancellation_date TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_active (user_id, subscription_status),
    INDEX idx_subscription_status (subscription_status, next_billing_date),
    INDEX idx_billing_date (next_billing_date),
    INDEX idx_payment_method (payment_method_id)
);

-- Subscription usage tracking
CREATE TABLE subscription_usage (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    subscription_id BIGINT NOT NULL,
    usage_type VARCHAR(50) NOT NULL,  -- 'streaming_hours', 'downloads', 'api_calls'
    usage_date DATE NOT NULL,
    usage_count INT DEFAULT 0,
    usage_limit INT DEFAULT 0,
    usage_percentage DECIMAL(5,2) DEFAULT 0,
    is_over_limit BOOLEAN DEFAULT FALSE,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_usage_date (user_id, usage_type, usage_date),
    INDEX idx_usage_type (usage_type, usage_date),
    INDEX idx_over_limit (is_over_limit, usage_date)
);

-- Subscription billing cycles
CREATE TABLE billing_cycles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    subscription_id BIGINT NOT NULL,
    cycle_number INT NOT NULL,
    cycle_start_date TIMESTAMP NOT NULL,
    cycle_end_date TIMESTAMP NOT NULL,
    billing_amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    payment_status ENUM('pending', 'paid', 'failed', 'refunded') DEFAULT 'pending',
    payment_method_id VARCHAR(100) NULL,
    invoice_id VARCHAR(100) NULL,
    payment_date TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_subscription_cycle (subscription_id, cycle_number),
    INDEX idx_billing_date (cycle_start_date, cycle_end_date),
    INDEX idx_payment_status (payment_status, payment_date)
);
```

### The "Usage-Based Billing" Pattern
```sql
-- Usage-based pricing tiers
CREATE TABLE usage_tiers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    tier_name VARCHAR(100) NOT NULL,
    usage_type VARCHAR(50) NOT NULL,  -- 'api_calls', 'storage_gb', 'bandwidth_gb'
    min_usage INT NOT NULL,
    max_usage INT NULL,  -- NULL for unlimited
    price_per_unit DECIMAL(10,4) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_usage_type (usage_type, min_usage),
    INDEX idx_price (price_per_unit, is_active)
);

-- Usage tracking and billing
CREATE TABLE usage_billing (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    usage_type VARCHAR(50) NOT NULL,
    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,
    total_usage INT NOT NULL,
    tier_breakdown JSON NOT NULL,  -- Usage per tier
    total_amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    billing_status ENUM('pending', 'billed', 'paid', 'overdue') DEFAULT 'pending',
    invoice_id VARCHAR(100) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_period (user_id, usage_type, billing_period_start),
    INDEX idx_billing_period (billing_period_start, billing_period_end),
    INDEX idx_billing_status (billing_status, billing_period_end)
);

-- Usage calculation procedure
DELIMITER $$
CREATE PROCEDURE calculate_usage_billing(
    IN user_id BIGINT,
    IN usage_type VARCHAR(50),
    IN period_start DATE,
    IN period_end DATE
)
BEGIN
    DECLARE total_usage INT;
    DECLARE current_tier_id BIGINT;
    DECLARE current_tier_min INT;
    DECLARE current_tier_max INT;
    DECLARE current_tier_price DECIMAL(10,4);
    DECLARE remaining_usage INT;
    DECLARE tier_usage INT;
    DECLARE total_amount DECIMAL(10,2) DEFAULT 0;
    DECLARE tier_breakdown JSON DEFAULT JSON_ARRAY();
    
    -- Get total usage for the period
    SELECT COALESCE(SUM(usage_count), 0) INTO total_usage
    FROM subscription_usage
    WHERE user_id = user_id
    AND usage_type = usage_type
    AND usage_date BETWEEN period_start AND period_end;
    
    SET remaining_usage = total_usage;
    
    -- Calculate billing by tier
    WHILE remaining_usage > 0 DO
        -- Get current tier
        SELECT 
            id, min_usage, max_usage, price_per_unit
        INTO current_tier_id, current_tier_min, current_tier_max, current_tier_price
        FROM usage_tiers
        WHERE usage_type = usage_type
        AND is_active = TRUE
        AND min_usage <= remaining_usage
        AND (max_usage IS NULL OR max_usage >= remaining_usage)
        ORDER BY min_usage ASC
        LIMIT 1;
        
        IF current_tier_id IS NULL THEN
            -- No tier found, use highest tier
            SELECT 
                id, min_usage, max_usage, price_per_unit
            INTO current_tier_id, current_tier_min, current_tier_max, current_tier_price
            FROM usage_tiers
            WHERE usage_type = usage_type
            AND is_active = TRUE
            ORDER BY min_usage DESC
            LIMIT 1;
        END IF;
        
        -- Calculate usage for this tier
        IF current_tier_max IS NULL THEN
            SET tier_usage = remaining_usage;
        ELSE
            SET tier_usage = LEAST(remaining_usage, current_tier_max - current_tier_min + 1);
        END IF;
        
        -- Calculate amount for this tier
        SET total_amount = total_amount + (tier_usage * current_tier_price);
        
        -- Add to tier breakdown
        SET tier_breakdown = JSON_ARRAY_APPEND(tier_breakdown, '$', JSON_OBJECT(
            'tier_id', current_tier_id,
            'usage', tier_usage,
            'price_per_unit', current_tier_price,
            'amount', tier_usage * current_tier_price
        ));
        
        SET remaining_usage = remaining_usage - tier_usage;
    END WHILE;
    
    -- Insert or update billing record
    INSERT INTO usage_billing (
        user_id, usage_type, billing_period_start, billing_period_end,
        total_usage, tier_breakdown, total_amount
    )
    VALUES (
        user_id, usage_type, period_start, period_end,
        total_usage, tier_breakdown, total_amount
    )
    ON DUPLICATE KEY UPDATE
        total_usage = VALUES(total_usage),
        tier_breakdown = VALUES(tier_breakdown),
        total_amount = VALUES(total_amount);
END$$
DELIMITER ;
```

## 💳 Payment Processing Patterns

### The "Stripe-Style Payment" Pattern
```sql
-- Payment methods
CREATE TABLE payment_methods (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    payment_method_id VARCHAR(100) UNIQUE NOT NULL,  -- External payment method ID
    payment_type ENUM('card', 'bank_account', 'paypal', 'apple_pay', 'google_pay') NOT NULL,
    card_brand VARCHAR(20) NULL,  -- 'visa', 'mastercard', 'amex'
    card_last4 VARCHAR(4) NULL,
    card_exp_month INT NULL,
    card_exp_year INT NULL,
    bank_name VARCHAR(100) NULL,
    bank_last4 VARCHAR(4) NULL,
    is_default BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_user_payment (user_id, is_active),
    INDEX idx_payment_type (payment_type, is_active),
    INDEX idx_default (user_id, is_default)
);

-- Payment transactions
CREATE TABLE payment_transactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(100) UNIQUE NOT NULL,  -- External transaction ID
    user_id BIGINT NOT NULL,
    payment_method_id VARCHAR(100) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    transaction_type ENUM('charge', 'refund', 'dispute', 'transfer') NOT NULL,
    status ENUM('pending', 'succeeded', 'failed', 'cancelled', 'refunded') NOT NULL,
    description TEXT,
    metadata JSON,  -- Additional transaction data
    failure_reason VARCHAR(255) NULL,
    processed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_user_transaction (user_id, created_at),
    INDEX idx_transaction_status (status, created_at),
    INDEX idx_payment_method (payment_method_id, created_at),
    INDEX idx_processed (processed_at)
);

-- Payment intents (for complex payment flows)
CREATE TABLE payment_intents (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    intent_id VARCHAR(100) UNIQUE NOT NULL,
    user_id BIGINT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    payment_method_types JSON NOT NULL,  -- ['card', 'bank_account']
    status ENUM('requires_payment_method', 'requires_confirmation', 'requires_action', 'processing', 'requires_capture', 'canceled', 'succeeded') NOT NULL,
    client_secret VARCHAR(255) NULL,
    confirmation_method ENUM('automatic', 'manual') DEFAULT 'automatic',
    capture_method ENUM('automatic', 'manual') DEFAULT 'automatic',
    setup_future_usage ENUM('off_session', 'on_session') NULL,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_user_intent (user_id, status),
    INDEX idx_intent_status (status, created_at)
);
```

### The "PayPal-Style Refund" Pattern
```sql
-- Refund management
CREATE TABLE refunds (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    refund_id VARCHAR(100) UNIQUE NOT NULL,
    transaction_id VARCHAR(100) NOT NULL,
    user_id BIGINT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    refund_reason ENUM('duplicate', 'fraudulent', 'requested_by_customer', 'expired_uncaptured') NOT NULL,
    refund_status ENUM('pending', 'succeeded', 'failed', 'canceled') NOT NULL,
    refund_method ENUM('instant', 'standard') DEFAULT 'standard',
    refund_destination VARCHAR(50) NULL,  -- 'original_payment_method', 'bank_account'
    failure_reason VARCHAR(255) NULL,
    processed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_transaction_refund (transaction_id, refund_status),
    INDEX idx_user_refund (user_id, created_at),
    INDEX idx_refund_status (refund_status, created_at)
);

-- Dispute management
CREATE TABLE disputes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    dispute_id VARCHAR(100) UNIQUE NOT NULL,
    transaction_id VARCHAR(100) NOT NULL,
    user_id BIGINT NOT NULL,
    dispute_reason ENUM('fraudulent', 'duplicate', 'product_not_received', 'product_not_as_described', 'credit_not_processed', 'general') NOT NULL,
    dispute_status ENUM('warning_needs_response', 'warning_under_review', 'warning_closed', 'needs_response', 'under_review', 'charge_refunded', 'won', 'lost') NOT NULL,
    dispute_amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    evidence JSON,  -- Evidence provided by merchant
    due_date TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_transaction_dispute (transaction_id, dispute_status),
    INDEX idx_user_dispute (user_id, dispute_status),
    INDEX idx_due_date (due_date, dispute_status)
);
```

## 🏢 Enterprise Billing Patterns

### The "Atlassian-Style License Billing" Pattern
```sql
-- License management
CREATE TABLE licenses (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    license_key VARCHAR(100) UNIQUE NOT NULL,
    product_name VARCHAR(100) NOT NULL,  -- 'jira', 'confluence', 'bitbucket'
    license_type ENUM('evaluation', 'developer', 'standard', 'premium', 'enterprise') NOT NULL,
    max_users INT NOT NULL,
    current_users INT DEFAULT 0,
    license_status ENUM('active', 'expired', 'suspended', 'cancelled') DEFAULT 'active',
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    auto_renew BOOLEAN DEFAULT TRUE,
    billing_cycle ENUM('monthly', 'quarterly', 'yearly') NOT NULL,
    license_cost DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_license_key (license_key, license_status),
    INDEX idx_product_license (product_name, license_type),
    INDEX idx_end_date (end_date, license_status)
);

-- License usage tracking
CREATE TABLE license_usage (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    license_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    usage_date DATE NOT NULL,
    login_count INT DEFAULT 0,
    feature_usage JSON,  -- Usage of specific features
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_license_user_date (license_id, user_id, usage_date),
    INDEX idx_license_usage (license_id, usage_date),
    INDEX idx_user_usage (user_id, usage_date)
);

-- License billing cycles
CREATE TABLE license_billing (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    license_id BIGINT NOT NULL,
    billing_cycle_start DATE NOT NULL,
    billing_cycle_end DATE NOT NULL,
    user_count INT NOT NULL,
    per_user_cost DECIMAL(10,2) NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    billing_status ENUM('pending', 'billed', 'paid', 'overdue') DEFAULT 'pending',
    invoice_id VARCHAR(100) NULL,
    payment_date TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_license_cycle (license_id, billing_cycle_start),
    INDEX idx_billing_cycle (billing_cycle_start, billing_cycle_end),
    INDEX idx_billing_status (billing_status, billing_cycle_end)
);
```

### The "Usage-Based Pricing" Pattern
```sql
-- Usage-based pricing for enterprise
CREATE TABLE enterprise_usage (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT NOT NULL,
    usage_type VARCHAR(50) NOT NULL,  -- 'api_calls', 'storage_gb', 'active_users'
    usage_date DATE NOT NULL,
    usage_count BIGINT DEFAULT 0,
    usage_limit BIGINT DEFAULT 0,
    overage_amount BIGINT DEFAULT 0,
    base_cost DECIMAL(10,2) NOT NULL,
    overage_cost DECIMAL(10,2) DEFAULT 0,
    total_cost DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_org_usage_date (organization_id, usage_type, usage_date),
    INDEX idx_usage_type (usage_type, usage_date),
    INDEX idx_organization (organization_id, usage_date)
);

-- Enterprise billing aggregation
CREATE VIEW enterprise_billing_summary AS
SELECT 
    organization_id,
    usage_type,
    DATE_FORMAT(usage_date, '%Y-%m') as billing_month,
    SUM(usage_count) as total_usage,
    SUM(overage_amount) as total_overage,
    SUM(base_cost) as total_base_cost,
    SUM(overage_cost) as total_overage_cost,
    SUM(total_cost) as total_billing_amount,
    currency
FROM enterprise_usage
WHERE usage_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
GROUP BY organization_id, usage_type, DATE_FORMAT(usage_date, '%Y-%m'), currency
ORDER BY organization_id, usage_type, billing_month DESC;
```

## 📊 Billing Analytics & Reporting

### The "Revenue Analytics" Pattern
```sql
-- Revenue tracking
CREATE TABLE revenue_analytics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    revenue_date DATE NOT NULL,
    revenue_type VARCHAR(50) NOT NULL,  -- 'subscription', 'usage', 'one_time'
    product_name VARCHAR(100) NOT NULL,
    region VARCHAR(10) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    gross_revenue DECIMAL(15,2) NOT NULL,
    net_revenue DECIMAL(15,2) NOT NULL,
    refunds DECIMAL(15,2) DEFAULT 0,
    chargebacks DECIMAL(15,2) DEFAULT 0,
    customer_count INT NOT NULL,
    transaction_count INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_revenue_date_type (revenue_date, revenue_type, product_name, region),
    INDEX idx_revenue_date (revenue_date),
    INDEX idx_product_revenue (product_name, revenue_date),
    INDEX idx_region_revenue (region, revenue_date)
);

-- Revenue analytics procedure
DELIMITER $$
CREATE PROCEDURE calculate_daily_revenue(
    IN target_date DATE
)
BEGIN
    -- Calculate subscription revenue
    INSERT INTO revenue_analytics (
        revenue_date, revenue_type, product_name, region, currency,
        gross_revenue, net_revenue, customer_count, transaction_count
    )
    SELECT 
        target_date,
        'subscription' as revenue_type,
        'netflix' as product_name,
        'US' as region,
        'USD' as currency,
        SUM(amount_paid) as gross_revenue,
        SUM(amount_paid) as net_revenue,
        COUNT(DISTINCT user_id) as customer_count,
        COUNT(*) as transaction_count
    FROM user_subscriptions
    WHERE DATE(current_period_start) = target_date
    AND subscription_status = 'active'
    ON DUPLICATE KEY UPDATE
        gross_revenue = VALUES(gross_revenue),
        net_revenue = VALUES(net_revenue),
        customer_count = VALUES(customer_count),
        transaction_count = VALUES(transaction_count);
    
    -- Calculate usage-based revenue
    INSERT INTO revenue_analytics (
        revenue_date, revenue_type, product_name, region, currency,
        gross_revenue, net_revenue, customer_count, transaction_count
    )
    SELECT 
        target_date,
        'usage' as revenue_type,
        'api_service' as product_name,
        'US' as region,
        'USD' as currency,
        SUM(total_amount) as gross_revenue,
        SUM(total_amount) as net_revenue,
        COUNT(DISTINCT user_id) as customer_count,
        COUNT(*) as transaction_count
    FROM usage_billing
    WHERE billing_period_start = target_date
    AND billing_status = 'paid'
    ON DUPLICATE KEY UPDATE
        gross_revenue = VALUES(gross_revenue),
        net_revenue = VALUES(net_revenue),
        customer_count = VALUES(customer_count),
        transaction_count = VALUES(transaction_count);
END$$
DELIMITER ;
```

These payment and billing patterns show the real-world techniques that product engineers use to build scalable payment and billing systems! 🚀
