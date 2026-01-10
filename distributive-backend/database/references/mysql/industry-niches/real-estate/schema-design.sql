-- Real Estate Database Schema (MySQL)
-- Comprehensive schema for property management, sales, leasing, and analytics
-- Adapted for MySQL with spatial features, JSON support, and performance optimizations

-- ===========================================
-- PROPERTY MANAGEMENT
-- ===========================================

CREATE TABLE properties (
    property_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    property_name VARCHAR(255),

    -- Basic property information
    property_type ENUM('single_family', 'multi_family', 'condo', 'townhouse', 'apartment', 'commercial_office', 'retail', 'industrial', 'land', 'special_purpose') NOT NULL,
    property_subtype VARCHAR(100),
    ownership_type ENUM('fee_simple', 'leasehold', 'condominium', 'cooperative', 'timeshare') DEFAULT 'fee_simple',

    -- Location and address
    street_address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(50) DEFAULT 'USA',
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    location_point POINT AS (POINT(longitude, latitude)) STORED,

    -- Property details
    year_built YEAR,
    total_sqft DECIMAL(10,2),
    lot_size_sqft DECIMAL(10,2),
    bedrooms INT,
    bathrooms DECIMAL(3,1),
    garage_spaces INT DEFAULT 0,
    stories INT DEFAULT 1,

    -- Zoning and legal
    zoning_code VARCHAR(50),
    parcel_number VARCHAR(100) UNIQUE,
    legal_description TEXT,

    -- Current status and market info
    property_status ENUM('available', 'under_contract', 'sold', 'rented', 'off_market', 'foreclosure', 'bank_owned') DEFAULT 'available',
    listing_price DECIMAL(12,2),
    market_value DECIMAL(12,2),

    -- Management and ownership
    owner_id CHAR(36),
    property_manager_id CHAR(36),
    management_company_id CHAR(36),

    -- Metadata
    property_description LONGTEXT,
    property_features JSON DEFAULT ('[]'),  -- Pool, fireplace, hardwood floors, etc.
    custom_fields JSON DEFAULT ('{}'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (owner_id) REFERENCES property_owners(owner_id),
    FOREIGN KEY (property_manager_id) REFERENCES property_managers(manager_id),
    FOREIGN KEY (management_company_id) REFERENCES management_companies(company_id),

    INDEX idx_properties_location (city, state_province),
    INDEX idx_properties_type (property_type, property_subtype),
    INDEX idx_properties_status (property_status),
    INDEX idx_properties_price (listing_price),
    INDEX idx_properties_owner (owner_id),
    INDEX idx_properties_manager (property_manager_id),
    SPATIAL INDEX idx_properties_location_point (location_point)
) ENGINE = InnoDB;

-- ===========================================
-- PROPERTY UNITS (for multi-unit properties)
-- ===========================================

CREATE TABLE property_units (
    unit_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    property_id CHAR(36) NOT NULL,

    -- Unit identification
    unit_number VARCHAR(20) NOT NULL,
    unit_type ENUM('apartment', 'condo', 'townhouse', 'office', 'retail_space', 'warehouse', 'parking') NOT NULL,

    -- Physical details
    floor_number INT,
    square_feet DECIMAL(8,2),
    bedrooms INT,
    bathrooms DECIMAL(3,1),

    -- Rental information
    monthly_rent DECIMAL(8,2),
    security_deposit DECIMAL(8,2),
    is_available BOOLEAN DEFAULT TRUE,
    available_date DATE,

    -- Current tenancy
    current_tenant_id CHAR(36),
    lease_start_date DATE,
    lease_end_date DATE,

    -- Unit features and condition
    unit_features JSON DEFAULT ('[]'),
    condition_rating ENUM('excellent', 'good', 'fair', 'poor', 'needs_repair') DEFAULT 'good',
    last_inspection_date DATE,

    -- Financial tracking
    operating_expenses DECIMAL(8,2) DEFAULT 0,
    maintenance_reserve DECIMAL(8,2) DEFAULT 0,

    FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE,
    FOREIGN KEY (current_tenant_id) REFERENCES tenants(tenant_id),

    INDEX idx_units_property (property_id),
    INDEX idx_units_type (unit_type),
    INDEX idx_units_available (is_available),
    INDEX idx_units_tenant (current_tenant_id),
    INDEX idx_units_rent (monthly_rent)
) ENGINE = InnoDB;

-- ===========================================
-- PROPERTY OWNERS AND MANAGEMENT
-- ===========================================

CREATE TABLE property_owners (
    owner_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    owner_type ENUM('individual', 'company', 'trust', 'partnership', 'llc', 'nonprofit') DEFAULT 'individual',

    -- Owner information
    owner_name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),
    tax_id VARCHAR(50),  -- SSN/EIN

    -- Address (billing address)
    billing_address VARCHAR(500),

    -- Financial details
    preferred_payment_method ENUM('check', 'wire', 'ach', 'paypal') DEFAULT 'check',
    payment_terms_days INT DEFAULT 30,

    -- Relationship management
    account_manager_id CHAR(36),
    relationship_status ENUM('active', 'inactive', 'prospect', 'former') DEFAULT 'active',

    -- Metadata
    owner_since DATE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_owners_type (owner_type),
    INDEX idx_owners_status (relationship_status),
    INDEX idx_owners_manager (account_manager_id)
) ENGINE = InnoDB;

CREATE TABLE property_managers (
    manager_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    manager_name VARCHAR(255) NOT NULL,
    license_number VARCHAR(50) UNIQUE,
    license_state VARCHAR(50),

    -- Contact information
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),
    emergency_phone VARCHAR(20),

    -- Business details
    company_name VARCHAR(255),
    business_address VARCHAR(500),

    -- Service areas
    service_area_cities JSON DEFAULT ('[]'),
    service_area_states JSON DEFAULT ('[]'),

    -- Performance metrics
    average_response_time_hours DECIMAL(4,1),
    customer_satisfaction_rating DECIMAL(3,1),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    background_check_date DATE,
    insurance_expiry DATE,

    INDEX idx_managers_license (license_number, license_state),
    INDEX idx_managers_active (is_active),
    INDEX idx_managers_rating (customer_satisfaction_rating)
) ENGINE = InnoDB;

CREATE TABLE management_companies (
    company_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    company_name VARCHAR(255) NOT NULL,

    -- Business details
    business_address VARCHAR(500),
    tax_id VARCHAR(50),
    insurance_provider VARCHAR(255),

    -- Contact
    primary_contact_name VARCHAR(255),
    primary_email VARCHAR(255),
    primary_phone VARCHAR(20),

    -- Operations
    total_properties_managed INT DEFAULT 0,
    total_units_managed INT DEFAULT 0,
    average_occupancy_rate DECIMAL(5,2),

    -- Compliance
    license_number VARCHAR(50),
    bond_amount DECIMAL(10,2),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_companies_active (is_active),
    INDEX idx_companies_license (license_number)
) ENGINE = InnoDB;

-- ===========================================
-- PROPERTY LISTINGS AND SALES
-- ===========================================

CREATE TABLE property_listings (
    listing_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    property_id CHAR(36) NOT NULL UNIQUE,  -- One active listing per property

    -- Listing details
    listing_type ENUM('sale', 'rent', 'lease') NOT NULL,
    listing_price DECIMAL(12,2) NOT NULL,
    price_per_sqft DECIMAL(8,2) GENERATED ALWAYS AS (listing_price / NULLIF((SELECT total_sqft FROM properties WHERE property_id = property_listings.property_id), 0)) STORED,

    -- Marketing
    headline VARCHAR(255),
    description LONGTEXT,
    virtual_tour_url VARCHAR(500),
    listing_status ENUM('active', 'pending', 'sold', 'rented', 'expired', 'withdrawn') DEFAULT 'active',

    -- Dates
    listed_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expiration_date DATE,
    sold_date TIMESTAMP NULL,

    -- Agent and commission
    listing_agent_id CHAR(36) NOT NULL,
    co_agent_id CHAR(36),
    commission_percentage DECIMAL(4,2) DEFAULT 3.00,
    commission_split DECIMAL(4,2) DEFAULT 100.00,  -- Percentage to listing agent

    -- Marketing budget
    marketing_budget DECIMAL(8,2) DEFAULT 0,
    featured_listing BOOLEAN DEFAULT FALSE,

    -- Analytics
    view_count INT DEFAULT 0,
    favorite_count INT DEFAULT 0,
    inquiry_count INT DEFAULT 0,

    FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE,
    FOREIGN KEY (listing_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (co_agent_id) REFERENCES agents(agent_id),

    INDEX idx_listings_property (property_id),
    INDEX idx_listings_type (listing_type),
    INDEX idx_listings_status (listing_status),
    INDEX idx_listings_price (listing_price),
    INDEX idx_listings_agent (listing_agent_id),
    INDEX idx_listings_featured (featured_listing),
    INDEX idx_listings_date (listed_date DESC)
) ENGINE = InnoDB;

CREATE TABLE listing_agents (
    agent_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    agent_name VARCHAR(255) NOT NULL,
    license_number VARCHAR(50) UNIQUE,
    license_state VARCHAR(50),

    -- Contact and business
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),
    brokerage_name VARCHAR(255),
    brokerage_id CHAR(36),

    -- Performance metrics
    total_listings INT DEFAULT 0,
    total_sales DECIMAL(15,2) DEFAULT 0,
    average_sale_price DECIMAL(12,2),
    average_days_on_market INT,

    -- Status and ratings
    is_active BOOLEAN DEFAULT TRUE,
    agent_rating DECIMAL(3,1),
    review_count INT DEFAULT 0,

    -- Specializations
    specializations JSON DEFAULT ('[]'),  -- Residential, commercial, luxury, etc.

    INDEX idx_agents_license (license_number, license_state),
    INDEX idx_agents_active (is_active),
    INDEX idx_agents_rating (agent_rating DESC),
    INDEX idx_agents_brokerage (brokerage_id)
) ENGINE = InnoDB;

-- ===========================================
-- OFFERS AND TRANSACTIONS
-- ===========================================

CREATE TABLE property_offers (
    offer_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    property_id CHAR(36) NOT NULL,
    buyer_id CHAR(36) NOT NULL,

    -- Offer details
    offer_amount DECIMAL(12,2) NOT NULL,
    offer_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expiration_date TIMESTAMP,
    offer_status ENUM('pending', 'accepted', 'rejected', 'expired', 'withdrawn', 'countered') DEFAULT 'pending',

    -- Financing
    financing_type ENUM('cash', 'conventional', 'fha', 'va', 'seller_financing') DEFAULT 'conventional',
    down_payment_amount DECIMAL(10,2),
    financing_contingency BOOLEAN DEFAULT TRUE,

    -- Conditions and contingencies
    inspection_contingency BOOLEAN DEFAULT TRUE,
    appraisal_contingency BOOLEAN DEFAULT TRUE,
    financing_contingency BOOLEAN DEFAULT TRUE,
    sale_of_home_contingency BOOLEAN DEFAULT FALSE,

    -- Agent information
    buyer_agent_id CHAR(36),
    seller_agent_id CHAR(36),

    -- Notes and terms
    offer_terms LONGTEXT,
    buyer_notes TEXT,
    seller_notes TEXT,

    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    FOREIGN KEY (buyer_id) REFERENCES buyers(buyer_id),
    FOREIGN KEY (buyer_agent_id) REFERENCES listing_agents(agent_id),
    FOREIGN KEY (seller_agent_id) REFERENCES listing_agents(agent_id),

    INDEX idx_offers_property (property_id),
    INDEX idx_offers_buyer (buyer_id),
    INDEX idx_offers_status (offer_status),
    INDEX idx_offers_date (offer_date DESC),
    INDEX idx_offers_expiration (expiration_date)
) ENGINE = InnoDB;

CREATE TABLE sales_transactions (
    transaction_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    property_id CHAR(36) NOT NULL,
    buyer_id CHAR(36) NOT NULL,
    seller_id CHAR(36) NOT NULL,

    -- Transaction details
    sale_price DECIMAL(12,2) NOT NULL,
    closing_date DATE NOT NULL,
    sale_date DATE,

    -- Financial details
    commission_amount DECIMAL(10,2),
    commission_paid BOOLEAN DEFAULT FALSE,
    transfer_taxes DECIMAL(8,2),
    recording_fees DECIMAL(8,2),

    -- Legal and closing
    title_company VARCHAR(255),
    escrow_company VARCHAR(255),
    attorney_name VARCHAR(255),

    -- Status
    transaction_status ENUM('pending', 'closed', 'cancelled') DEFAULT 'pending',

    -- Agents and splits
    listing_agent_id CHAR(36),
    buyer_agent_id CHAR(36),
    listing_commission DECIMAL(8,2),
    buyer_agent_commission DECIMAL(8,2),

    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    FOREIGN KEY (buyer_id) REFERENCES buyers(buyer_id),
    FOREIGN KEY (seller_id) REFERENCES property_owners(owner_id),
    FOREIGN KEY (listing_agent_id) REFERENCES listing_agents(agent_id),
    FOREIGN KEY (buyer_agent_id) REFERENCES listing_agents(agent_id),

    INDEX idx_transactions_property (property_id),
    INDEX idx_transactions_buyer (buyer_id),
    INDEX idx_transactions_seller (seller_id),
    INDEX idx_transactions_date (closing_date),
    INDEX idx_transactions_status (transaction_status)
) ENGINE = InnoDB;

-- ===========================================
-- TENANT AND LEASING MANAGEMENT
-- ===========================================

CREATE TABLE tenants (
    tenant_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),

    -- Personal information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),

    -- Demographics and background
    date_of_birth DATE,
    social_security_last4 VARCHAR(4),
    current_employer VARCHAR(255),
    monthly_income DECIMAL(10,2),

    -- Emergency contact
    emergency_contact_name VARCHAR(255),
    emergency_contact_phone VARCHAR(20),
    emergency_contact_relationship VARCHAR(50),

    -- Rental history
    previous_addresses JSON DEFAULT ('[]'),
    rental_references JSON DEFAULT ('[]'),

    -- Credit and background check
    credit_score INT,
    background_check_date DATE,
    background_check_status ENUM('pending', 'approved', 'denied', 'expired') DEFAULT 'pending',

    -- Status
    tenant_status ENUM('prospect', 'approved', 'active', 'former', 'blacklisted') DEFAULT 'prospect',
    is_active BOOLEAN DEFAULT TRUE,

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_tenants_email (email),
    INDEX idx_tenants_status (tenant_status),
    INDEX idx_tenants_active (is_active),
    INDEX idx_tenants_credit (credit_score)
) ENGINE = InnoDB;

CREATE TABLE leases (
    lease_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    property_id CHAR(36) NOT NULL,
    unit_id CHAR(36),  -- NULL for single-family homes
    tenant_id CHAR(36) NOT NULL,

    -- Lease terms
    lease_type ENUM('residential', 'commercial', 'month_to_month') DEFAULT 'residential',
    lease_start_date DATE NOT NULL,
    lease_end_date DATE,
    monthly_rent DECIMAL(8,2) NOT NULL,
    security_deposit DECIMAL(8,2),

    -- Rent details
    rent_due_day INT DEFAULT 1,
    late_fee_amount DECIMAL(6,2) DEFAULT 50.00,
    late_fee_grace_days INT DEFAULT 5,

    -- Lease conditions
    pet_policy ENUM('no_pets', 'cats_only', 'dogs_only', 'all_pets_allowed', 'case_by_case') DEFAULT 'case_by_case',
    smoking_allowed BOOLEAN DEFAULT FALSE,
    subletting_allowed BOOLEAN DEFAULT FALSE,

    -- Utilities and services
    utilities_included JSON DEFAULT ('[]'),  -- Water, gas, electricity, internet
    parking_spaces INT DEFAULT 0,
    storage_units INT DEFAULT 0,

    -- Status and dates
    lease_status ENUM('draft', 'signed', 'active', 'expired', 'terminated', 'renewed') DEFAULT 'draft',
    signed_date DATE,
    move_in_date DATE,
    move_out_date DATE,

    -- Financial tracking
    total_lease_value DECIMAL(10,2) GENERATED ALWAYS AS (
        monthly_rent * TIMESTAMPDIFF(MONTH, lease_start_date, COALESCE(lease_end_date, DATE_ADD(lease_start_date, INTERVAL 12 MONTH)))
    ) STORED,

    -- Management
    property_manager_id CHAR(36),
    lease_document_url VARCHAR(500),

    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    FOREIGN KEY (unit_id) REFERENCES property_units(unit_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id),
    FOREIGN KEY (property_manager_id) REFERENCES property_managers(manager_id),

    INDEX idx_leases_property (property_id),
    INDEX idx_leases_unit (unit_id),
    INDEX idx_leases_tenant (tenant_id),
    INDEX idx_leases_status (lease_status),
    INDEX idx_leases_dates (lease_start_date, lease_end_date),
    INDEX idx_leases_rent (monthly_rent)
) ENGINE = InnoDB;

-- ===========================================
-- FINANCIAL TRACKING
-- ===========================================

CREATE TABLE rent_payments (
    payment_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    lease_id CHAR(36) NOT NULL,
    tenant_id CHAR(36) NOT NULL,

    -- Payment details
    payment_date DATE NOT NULL,
    payment_period_start DATE NOT NULL,
    payment_period_end DATE NOT NULL,
    amount_due DECIMAL(8,2) NOT NULL,
    amount_paid DECIMAL(8,2) NOT NULL,
    payment_method ENUM('check', 'cash', 'bank_transfer', 'credit_card', 'ach', 'money_order') DEFAULT 'check',

    -- Late fees and adjustments
    late_fee_applied DECIMAL(6,2) DEFAULT 0,
    adjustments DECIMAL(8,2) DEFAULT 0,  -- Credits, prorations, etc.
    adjustment_reason VARCHAR(255),

    -- Status and processing
    payment_status ENUM('pending', 'paid', 'overdue', 'partial', 'returned', 'disputed') DEFAULT 'pending',
    processed_date TIMESTAMP NULL,
    cleared_date TIMESTAMP NULL,

    -- Reference numbers
    check_number VARCHAR(20),
    transaction_id VARCHAR(100),
    receipt_number VARCHAR(50),

    -- Notes
    payment_notes TEXT,

    FOREIGN KEY (lease_id) REFERENCES leases(lease_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id),

    INDEX idx_payments_lease (lease_id),
    INDEX idx_payments_tenant (tenant_id),
    INDEX idx_payments_date (payment_date),
    INDEX idx_payments_status (payment_status),
    INDEX idx_payments_period (payment_period_start, payment_period_end)
) ENGINE = InnoDB;

-- ===========================================
-- MARKET ANALYTICS
-- ===========================================

CREATE TABLE market_data (
    market_data_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),

    -- Location and time
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    zip_code VARCHAR(20),
    data_date DATE NOT NULL,

    -- Price metrics
    median_home_price DECIMAL(10,2),
    average_home_price DECIMAL(10,2),
    price_per_sqft DECIMAL(8,2),

    -- Market activity
    homes_sold INT,
    new_listings INT,
    total_listings INT,
    average_days_on_market INT,

    -- Rental metrics
    median_rent DECIMAL(8,2),
    average_rent DECIMAL(8,2),
    vacancy_rate DECIMAL(5,2),

    -- Market indicators
    price_change_mom DECIMAL(5,2),  -- Month over month
    price_change_yoy DECIMAL(5,2),  -- Year over year
    market_trend ENUM('increasing', 'stable', 'decreasing') DEFAULT 'stable',

    -- Economic indicators
    interest_rates DECIMAL(4,2),
    unemployment_rate DECIMAL(4,2),

    UNIQUE KEY unique_market_data (city, state_province, zip_code, data_date),

    INDEX idx_market_city (city, state_province),
    INDEX idx_market_date (data_date),
    INDEX idx_market_zip (zip_code),
    INDEX idx_market_trend (market_trend)
) ENGINE = InnoDB;

-- ===========================================
-- SUPPORTING TABLES
-- ===========================================

CREATE TABLE buyers (
    buyer_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    buyer_type ENUM('individual', 'couple', 'family', 'investor', 'company') DEFAULT 'individual',

    -- Personal/company info
    buyer_name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(20),

    -- Buying criteria
    property_types JSON DEFAULT ('[]'),
    price_range_min DECIMAL(10,2),
    price_range_max DECIMAL(10,2),
    preferred_locations JSON DEFAULT ('[]'),
    bedroom_requirements INT,
    bathroom_requirements DECIMAL(3,1),

    -- Financial info
    pre_qualified BOOLEAN DEFAULT FALSE,
    financing_type ENUM('cash', 'mortgage', 'fha', 'va', 'conventional'),
    max_down_payment DECIMAL(10,2),

    -- Status
    buyer_status ENUM('active', 'inactive', 'found_home', 'lost_interest') DEFAULT 'active',
    agent_id CHAR(36),

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_buyers_status (buyer_status),
    INDEX idx_buyers_agent (agent_id),
    INDEX idx_buyers_type (buyer_type)
) ENGINE = InnoDB;

-- ===========================================
-- STORED PROCEDURES FOR REAL ESTATE ANALYTICS
-- =========================================--

DELIMITER ;;

-- Calculate property valuation based on comparables
CREATE FUNCTION calculate_property_value(property_uuid CHAR(36))
RETURNS JSON
DETERMINISTIC
BEGIN
    DECLARE property_record JSON;
    DECLARE comparable_sales JSON DEFAULT ('[]');
    DECLARE valuation_result JSON;

    -- Get property details
    SELECT JSON_OBJECT(
        'property_id', p.property_id,
        'address', CONCAT(p.street_address, ', ', p.city, ', ', p.state_province),
        'sqft', p.total_sqft,
        'bedrooms', p.bedrooms,
        'bathrooms', p.bathrooms,
        'year_built', p.year_built,
        'property_type', p.property_type
    ) INTO property_record
    FROM properties p
    WHERE p.property_id = property_uuid;

    -- Find comparable sales (within 1 mile, similar size, recent sales)
    SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
            'sale_price', st.sale_price,
            'sale_date', st.closing_date,
            'sqft', p2.total_sqft,
            'price_per_sqft', st.sale_price / p2.total_sqft,
            'days_on_market', DATEDIFF(st.closing_date, pl.listed_date)
        )
    ) INTO comparable_sales
    FROM sales_transactions st
    JOIN properties p2 ON st.property_id = p2.property_id
    LEFT JOIN property_listings pl ON p2.property_id = pl.property_id
    WHERE p2.city = JSON_UNQUOTE(JSON_EXTRACT(property_record, '$.city'))
      AND p2.state_province = JSON_UNQUOTE(JSON_EXTRACT(property_record, '$.state_province'))
      AND ABS(p2.total_sqft - JSON_UNQUOTE(JSON_EXTRACT(property_record, '$.sqft'))) / JSON_UNQUOTE(JSON_EXTRACT(property_record, '$.sqft')) < 0.2
      AND st.closing_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
    ORDER BY st.closing_date DESC
    LIMIT 5;

    -- Calculate valuation
    SET valuation_result = JSON_OBJECT(
        'property_details', property_record,
        'comparable_sales', comparable_sales,
        'estimated_value', CASE
            WHEN JSON_LENGTH(comparable_sales) > 0 THEN (
                SELECT AVG(price_per_sqft) * JSON_UNQUOTE(JSON_EXTRACT(property_record, '$.sqft'))
                FROM JSON_TABLE(comparable_sales, '$[*]' COLUMNS (
                    price_per_sqft DECIMAL(8,2) PATH '$.price_per_sqft'
                )) comps
            )
            ELSE NULL
        END,
        'confidence_level', CASE
            WHEN JSON_LENGTH(comparable_sales) >= 5 THEN 'high'
            WHEN JSON_LENGTH(comparable_sales) >= 3 THEN 'medium'
            WHEN JSON_LENGTH(comparable_sales) >= 1 THEN 'low'
            ELSE 'insufficient_data'
        END,
        'valuation_date', CURDATE()
    );

    RETURN valuation_result;
END;;

-- Analyze rental property performance
CREATE PROCEDURE analyze_rental_performance(property_uuid CHAR(36))
BEGIN
    -- Financial performance
    SELECT
        p.property_name,
        COUNT(DISTINCT pu.unit_id) as total_units,
        COUNT(DISTINCT l.lease_id) as occupied_units,
        ROUND(COUNT(DISTINCT l.lease_id) / COUNT(DISTINCT pu.unit_id) * 100, 2) as occupancy_rate,

        -- Income metrics
        SUM(pu.monthly_rent) as potential_monthly_income,
        COALESCE(SUM(rp.amount_paid), 0) as actual_monthly_income,
        SUM(pu.monthly_rent) - COALESCE(SUM(rp.amount_paid), 0) as monthly_loss_to_lease,

        -- Expense tracking
        COALESCE(SUM(pu.operating_expenses), 0) as monthly_operating_expenses,
        COALESCE(SUM(rp.amount_paid) - SUM(pu.operating_expenses), 0) as monthly_net_operating_income,

        -- Performance ratios
        CASE
            WHEN SUM(pu.monthly_rent) > 0 THEN ROUND((COALESCE(SUM(rp.amount_paid), 0) / SUM(pu.monthly_rent)) * 100, 2)
            ELSE 0
        END as rent_collection_rate

    FROM properties p
    LEFT JOIN property_units pu ON p.property_id = pu.property_id
    LEFT JOIN leases l ON pu.unit_id = l.unit_id AND l.lease_status = 'active'
    LEFT JOIN rent_payments rp ON l.lease_id = rp.lease_id
        AND rp.payment_date >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
        AND rp.payment_status = 'paid'
    WHERE p.property_id = property_uuid
    GROUP BY p.property_id, p.property_name;

    -- Unit-by-unit breakdown
    SELECT
        pu.unit_number,
        pu.unit_type,
        pu.monthly_rent,
        pu.is_available,
        t.first_name,
        t.last_name,
        t.email,
        l.lease_start_date,
        l.lease_end_date,
        l.lease_status,

        -- Payment history (last 3 months)
        COUNT(rp.payment_id) as payments_last_3_months,
        COALESCE(SUM(rp.amount_paid), 0) as total_paid_last_3_months,
        MAX(rp.payment_date) as last_payment_date,

        -- Delinquency check
        CASE
            WHEN MAX(rp.payment_date) < DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN 'delinquent'
            WHEN MAX(rp.payment_date) < DATE_SUB(CURDATE(), INTERVAL 7 DAY) THEN 'at_risk'
            ELSE 'current'
        END as payment_status

    FROM property_units pu
    LEFT JOIN leases l ON pu.unit_id = l.unit_id AND l.lease_status = 'active'
    LEFT JOIN tenants t ON l.tenant_id = t.tenant_id
    LEFT JOIN rent_payments rp ON l.lease_id = rp.lease_id
        AND rp.payment_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
    WHERE pu.property_id = property_uuid
    GROUP BY pu.unit_id, pu.unit_number, pu.unit_type, pu.monthly_rent, pu.is_available,
             t.tenant_id, t.first_name, t.last_name, t.email, l.lease_start_date, l.lease_end_date, l.lease_status
    ORDER BY pu.unit_number;
END;;

DELIMITER ;

-- ===========================================
-- PARTITIONING FOR ANALYTICS
-- =========================================--

-- Partition sales transactions by year
ALTER TABLE sales_transactions
PARTITION BY RANGE (YEAR(closing_date)) (
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Partition rent payments by month
ALTER TABLE rent_payments
PARTITION BY RANGE (YEAR(payment_date) * 100 + MONTH(payment_date)) (
    PARTITION p2024_01 VALUES LESS THAN (202401),
    PARTITION p2024_02 VALUES LESS THAN (202402),
    PARTITION p2024_03 VALUES LESS THAN (202403),
    PARTITION p2024_04 VALUES LESS THAN (202404),
    PARTITION p2024_05 VALUES LESS THAN (202405),
    PARTITION p2024_06 VALUES LESS THAN (202406),
    PARTITION p2024_07 VALUES LESS THAN (202407),
    PARTITION p2024_08 VALUES LESS THAN (202408),
    PARTITION p2024_09 VALUES LESS THAN (202409),
    PARTITION p2024_10 VALUES LESS THAN (202410),
    PARTITION p2024_11 VALUES LESS THAN (202411),
    PARTITION p2024_12 VALUES LESS THAN (202412),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- ===========================================
-- INITIAL SAMPLE DATA
-- =========================================--

INSERT INTO property_owners (owner_id, owner_name, owner_type, contact_email) VALUES
(UUID(), 'John Smith Properties LLC', 'llc', 'john@smithproperties.com'),
(UUID(), 'Sarah Johnson', 'individual', 'sarah.johnson@email.com');

INSERT INTO property_managers (manager_id, manager_name, license_number, license_state, email) VALUES
(UUID(), 'Mike Davis', 'PM123456', 'CA', 'mike.davis@propertymgmt.com'),
(UUID(), 'Lisa Chen', 'PM789012', 'TX', 'lisa.chen@propertymgmt.com');

INSERT INTO properties (
    property_id, property_name, property_type, street_address, city, state_province, postal_code,
    total_sqft, bedrooms, bathrooms, year_built, listing_price, owner_id, property_manager_id
) VALUES (
    UUID(), 'Oakwood Apartments', 'apartment', '123 Oak Street', 'Springfield', 'IL', '62701',
    15000, NULL, NULL, 2010, 2500000, (SELECT owner_id FROM property_owners LIMIT 1),
    (SELECT manager_id FROM property_managers LIMIT 1)
);

INSERT INTO listing_agents (agent_id, agent_name, license_number, license_state, email, brokerage_name) VALUES
(UUID(), 'Emily Rodriguez', 'RE123456', 'CA', 'emily@realestate.com', 'Premier Realty'),
(UUID(), 'David Kim', 'RE789012', 'TX', 'david@realestate.com', 'City Properties');

INSERT INTO property_listings (
    listing_id, property_id, listing_price, listing_agent_id, headline, description
) VALUES (
    UUID(), (SELECT property_id FROM properties LIMIT 1), 2500000,
    (SELECT agent_id FROM listing_agents LIMIT 1),
    'Prime Investment Opportunity',
    'Well-maintained apartment complex in growing neighborhood with strong rental history.'
);

/*
USAGE EXAMPLES:

-- Calculate property valuation
SELECT calculate_property_value('property-uuid-here');

-- Analyze rental property performance
CALL analyze_rental_performance('property-uuid-here');

This comprehensive real estate database schema provides enterprise-grade infrastructure for:
- Complete property management with geospatial tracking
- Dynamic sales listings with agent commission management
- Residential and commercial leasing with payment tracking
- Offer negotiation and transaction processing
- Market analytics and property valuation
- Tenant screening and lease management
- Performance analytics and reporting

Key features adapted for MySQL:
- UUID primary keys with UUID() function
- JSON data types for flexible property features and metadata
- Spatial indexes for location-based queries
- Generated columns for calculated fields
- Partitioning for time-series data management
- Stored procedures for complex real estate analytics

The schema supports property management companies, real estate agencies, investors, and landlords with comprehensive tracking of all aspects of real estate operations.
*/
