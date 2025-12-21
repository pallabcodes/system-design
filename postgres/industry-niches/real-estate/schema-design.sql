-- Real Estate Industry Database Schema Design
-- Comprehensive PostgreSQL schema for real estate management including properties,
-- listings, transactions, tenants, landlords, and property management

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";  -- For geospatial data
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text search

-- ===========================================
-- CORE ENTITIES
-- ===========================================

-- Companies and Organizations
CREATE TABLE companies (
    company_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_name VARCHAR(255) NOT NULL,
    company_type VARCHAR(50) NOT NULL
        CHECK (company_type IN ('realtor', 'property_manager', 'developer', 'appraiser', 'lender', 'title_company', 'insurance')),

    -- Business Information
    license_number VARCHAR(50),
    license_state VARCHAR(2),
    license_expiration DATE,

    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(20),
    website VARCHAR(255),

    -- Address
    address_line_1 VARCHAR(255),
    address_line_2 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',

    -- Status and Compliance
    is_active BOOLEAN DEFAULT TRUE,
    compliance_status VARCHAR(20) DEFAULT 'approved'
        CHECK (compliance_status IN ('pending', 'approved', 'suspended', 'revoked')),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Users (Agents, Managers, Clients)
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(company_id),

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),

    -- Authentication
    password_hash VARCHAR(255),
    two_factor_enabled BOOLEAN DEFAULT FALSE,

    -- Role and Permissions
    user_role VARCHAR(30) NOT NULL
        CHECK (user_role IN ('admin', 'realtor', 'property_manager', 'tenant', 'landlord', 'appraiser', 'lender', 'client')),
    permissions JSONB DEFAULT '{}',

    -- Profile
    avatar_url VARCHAR(500),
    bio TEXT,
    specialties TEXT[],  -- Areas of expertise
    languages TEXT[] DEFAULT ARRAY['English'],

    -- Professional Information
    license_number VARCHAR(50),
    license_state VARCHAR(2),
    years_experience INTEGER,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    last_login_at TIMESTAMP WITH TIME ZONE,

    -- Preferences
    notification_preferences JSONB DEFAULT '{"email": true, "sms": false, "push": true}',

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- PROPERTY MANAGEMENT
-- ===========================================

-- Properties
CREATE TABLE properties (
    property_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES users(user_id),

    -- Property Identification
    property_name VARCHAR(255),
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(50) DEFAULT 'USA',

    -- Geospatial Data
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOMETRY(Point, 4326),

    -- Property Details
    property_type VARCHAR(30) NOT NULL
        CHECK (property_type IN ('single_family', 'multi_family', 'condo', 'townhouse', 'apartment', 'commercial', 'land', 'industrial')),
    property_subtype VARCHAR(50),

    -- Physical Characteristics
    year_built INTEGER,
    total_sqft INTEGER,
    lot_sqft INTEGER,
    bedrooms INTEGER,
    bathrooms DECIMAL(3,1),
    garage_spaces INTEGER,
    parking_spaces INTEGER,

    -- Features and Amenities
    features JSONB,  -- Pool, fireplace, hardwood floors, etc.
    appliances JSONB,  -- Dishwasher, microwave, etc.
    amenities JSONB,  -- Community pool, gym, etc.

    -- Property Condition
    property_condition VARCHAR(20) DEFAULT 'good'
        CHECK (property_condition IN ('excellent', 'good', 'fair', 'poor', 'needs_repair')),

    -- Legal Information
    parcel_id VARCHAR(50),
    zoning_code VARCHAR(20),
    legal_description TEXT,

    -- Status
    property_status VARCHAR(20) DEFAULT 'available'
        CHECK (property_status IN ('available', 'rented', 'sold', 'off_market', 'pending', 'under_contract')),

    -- Valuation
    estimated_value DECIMAL(12,2),
    last_appraisal_date DATE,
    appraisal_company_id UUID REFERENCES companies(company_id),

    -- Management
    property_manager_id UUID REFERENCES users(user_id),
    management_company_id UUID REFERENCES companies(company_id),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', COALESCE(property_name, '') || ' ' ||
                   COALESCE(address_line_1, '') || ' ' || COALESCE(city, ''))
    ) STORED
);

-- Property Units (for multi-unit properties)
CREATE TABLE property_units (
    unit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id) ON DELETE CASCADE,

    -- Unit Identification
    unit_number VARCHAR(20) NOT NULL,
    unit_name VARCHAR(100),

    -- Unit Details
    unit_type VARCHAR(30) DEFAULT 'apartment'
        CHECK (unit_type IN ('apartment', 'condo', 'townhouse', 'office', 'retail', 'storage')),
    floor_number INTEGER,
    sq_ft INTEGER,

    -- Unit Features
    bedrooms INTEGER,
    bathrooms DECIMAL(3,1),
    rent_amount DECIMAL(8,2),
    security_deposit DECIMAL(8,2),

    -- Status
    unit_status VARCHAR(20) DEFAULT 'vacant'
        CHECK (unit_status IN ('vacant', 'occupied', 'maintenance', 'reserved', 'unavailable')),

    -- Current Tenant
    current_tenant_id UUID REFERENCES users(user_id),
    lease_start_date DATE,
    lease_end_date DATE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (property_id, unit_number)
);

-- ===========================================
-- LISTINGS AND MARKET DATA
-- ===========================================

-- Property Listings
CREATE TABLE listings (
    listing_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id),

    -- Listing Details
    listing_type VARCHAR(20) NOT NULL
        CHECK (listing_type IN ('sale', 'rent', 'lease')),
    listing_status VARCHAR(20) DEFAULT 'active'
        CHECK (listing_status IN ('active', 'pending', 'sold', 'rented', 'expired', 'withdrawn')),

    -- Pricing
    list_price DECIMAL(12,2),
    rent_price DECIMAL(8,2),
    price_per_sqft DECIMAL(8,2) GENERATED ALWAYS AS (
        CASE WHEN list_price IS NOT NULL AND total_sqft IS NOT NULL AND total_sqft > 0
             THEN list_price / total_sqft
             ELSE NULL
        END
    ) STORED,

    -- From properties table
    total_sqft INTEGER,
    bedrooms INTEGER,
    bathrooms DECIMAL(3,1),

    -- Marketing
    listing_title VARCHAR(200),
    listing_description TEXT,
    virtual_tour_url VARCHAR(500),
    floor_plan_url VARCHAR(500),

    -- Media
    photos JSONB,  -- Array of photo URLs with metadata
    videos JSONB,  -- Array of video URLs

    -- Listing Agent
    listing_agent_id UUID NOT NULL REFERENCES users(user_id),
    listing_company_id UUID REFERENCES companies(company_id),

    -- Dates
    list_date DATE DEFAULT CURRENT_DATE,
    expiration_date DATE,
    sold_date DATE,
    rented_date DATE,

    -- Marketing Analytics
    view_count INTEGER DEFAULT 0,
    favorite_count INTEGER DEFAULT 0,
    inquiry_count INTEGER DEFAULT 0,

    -- Commission
    commission_rate DECIMAL(5,2),  -- Percentage
    commission_amount DECIMAL(8,2),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (
        (listing_type = 'sale' AND list_price IS NOT NULL) OR
        (listing_type IN ('rent', 'lease') AND rent_price IS NOT NULL)
    )
);

-- Property Valuations and Appraisals
CREATE TABLE property_valuations (
    valuation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id),

    -- Valuation Details
    valuation_date DATE DEFAULT CURRENT_DATE,
    valuation_type VARCHAR(30) NOT NULL
        CHECK (valuation_type IN ('appraisal', 'avm', 'tax_assessment', 'market_analysis')),

    -- Value
    estimated_value DECIMAL(12,2) NOT NULL,
    value_range_low DECIMAL(12,2),
    value_range_high DECIMAL(12,2),
    confidence_score DECIMAL(3,2),  -- 0.00 to 1.00

    -- Valuation Source
    appraiser_id UUID REFERENCES users(user_id),
    appraisal_company_id UUID REFERENCES companies(company_id),
    avm_provider VARCHAR(50),  -- Zillow, Redfin, etc.

    -- Methodology
    valuation_method VARCHAR(50),  -- Sales comparison, income approach, cost approach
    comparable_sales JSONB,  -- Reference to comparable properties

    -- Property Details at Time of Valuation
    property_details JSONB,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id)
);

-- ===========================================
-- TRANSACTIONS AND CONTRACTS
-- ===========================================

-- Transactions (Sales, Rentals)
CREATE TABLE transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID REFERENCES listings(listing_id),

    -- Transaction Details
    transaction_type VARCHAR(20) NOT NULL
        CHECK (transaction_type IN ('sale', 'rental', 'lease')),
    transaction_status VARCHAR(30) DEFAULT 'pending'
        CHECK (transaction_status IN ('pending', 'under_contract', 'closed', 'cancelled', 'terminated')),

    -- Parties Involved
    buyer_id UUID REFERENCES users(user_id),
    seller_id UUID REFERENCES users(user_id),
    tenant_id UUID REFERENCES users(user_id),
    landlord_id UUID REFERENCES users(user_id),

    -- Property Information
    property_id UUID NOT NULL REFERENCES properties(property_id),
    unit_id UUID REFERENCES property_units(unit_id),

    -- Financial Details
    sale_price DECIMAL(12,2),
    rent_amount DECIMAL(8,2),
    security_deposit DECIMAL(8,2),
    commission_amount DECIMAL(8,2),

    -- Dates
    contract_date DATE,
    closing_date DATE,
    lease_start_date DATE,
    lease_end_date DATE,
    move_in_date DATE,

    -- Agents and Companies
    listing_agent_id UUID REFERENCES users(user_id),
    selling_agent_id UUID REFERENCES users(user_id),
    title_company_id UUID REFERENCES companies(company_id),

    -- Financing
    financing_type VARCHAR(30),  -- Cash, conventional, FHA, etc.
    lender_id UUID REFERENCES users(user_id),
    loan_amount DECIMAL(12,2),
    interest_rate DECIMAL(5,2),

    -- Terms and Conditions
    contract_terms JSONB,
    special_conditions TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id)
);

-- Contracts and Agreements
CREATE TABLE contracts (
    contract_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID REFERENCES transactions(transaction_id),

    -- Contract Details
    contract_type VARCHAR(30) NOT NULL
        CHECK (contract_type IN ('purchase_agreement', 'lease_agreement', 'management_agreement', 'listing_agreement')),
    contract_status VARCHAR(20) DEFAULT 'draft'
        CHECK (contract_status IN ('draft', 'pending', 'signed', 'executed', 'terminated')),

    -- Parties
    party_a_id UUID NOT NULL REFERENCES users(user_id),  -- Usually the property owner/seller
    party_b_id UUID REFERENCES users(user_id),           -- Buyer, tenant, agent, etc.
    witnesses JSONB,  -- Array of witness information

    -- Contract Terms
    effective_date DATE,
    expiration_date DATE,
    contract_terms JSONB,
    special_provisions TEXT,

    -- Financial Terms
    total_amount DECIMAL(12,2),
    payment_schedule JSONB,
    penalties_fees JSONB,

    -- Legal
    governing_law VARCHAR(50),
    dispute_resolution VARCHAR(50),

    -- Documents
    contract_document_url VARCHAR(500),
    digital_signature JSONB,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id),
    signed_at TIMESTAMP WITH TIME ZONE,
    signed_by JSONB
);

-- ===========================================
-- LEASING AND TENANCY MANAGEMENT
-- ===========================================

-- Leases
CREATE TABLE leases (
    lease_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id),
    unit_id UUID REFERENCES property_units(unit_id),

    -- Lease Parties
    landlord_id UUID NOT NULL REFERENCES users(user_id),
    tenant_id UUID NOT NULL REFERENCES users(user_id),

    -- Lease Terms
    lease_start_date DATE NOT NULL,
    lease_end_date DATE,
    lease_term_months INTEGER,
    lease_type VARCHAR(20) DEFAULT 'fixed'
        CHECK (lease_type IN ('fixed', 'month_to_month', 'periodic')),

    -- Financial Terms
    monthly_rent DECIMAL(8,2) NOT NULL,
    security_deposit DECIMAL(8,2),
    pet_deposit DECIMAL(8,2),
    last_month_rent BOOLEAN DEFAULT FALSE,

    -- Additional Fees
    application_fee DECIMAL(6,2),
    late_fee DECIMAL(6,2),
    late_fee_grace_days INTEGER DEFAULT 5,

    -- Utilities and Services
    utilities_included JSONB,  -- ['electricity', 'gas', 'water', 'internet']
    services_included JSONB,   -- ['trash', 'maintenance', 'parking']

    -- Lease Conditions
    lease_conditions JSONB,
    tenant_responsibilities JSONB,

    -- Status
    lease_status VARCHAR(20) DEFAULT 'active'
        CHECK (lease_status IN ('draft', 'pending', 'active', 'expired', 'terminated', 'evicted')),

    -- Termination
    termination_date DATE,
    termination_reason TEXT,
    notice_given_date DATE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id)
);

-- Lease Payments
CREATE TABLE lease_payments (
    payment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    lease_id UUID NOT NULL REFERENCES leases(lease_id),

    -- Payment Details
    payment_date DATE DEFAULT CURRENT_DATE,
    payment_amount DECIMAL(8,2) NOT NULL,
    payment_type VARCHAR(20) DEFAULT 'rent'
        CHECK (payment_type IN ('rent', 'deposit', 'fee', 'late_fee', 'damage_repair')),

    -- Payment Method
    payment_method VARCHAR(30),  -- 'check', 'cash', 'bank_transfer', 'credit_card'
    payment_reference VARCHAR(100),  -- Check number, transaction ID

    -- Payment Status
    payment_status VARCHAR(20) DEFAULT 'pending'
        CHECK (payment_status IN ('pending', 'received', 'processed', 'overdue', 'failed', 'refunded')),

    -- Period Covered
    period_start DATE,
    period_end DATE,

    -- Late Fees and Penalties
    late_fee_assessed DECIMAL(6,2) DEFAULT 0,
    days_late INTEGER DEFAULT 0,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    recorded_by UUID REFERENCES users(user_id)
);

-- Maintenance Requests
CREATE TABLE maintenance_requests (
    request_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id),
    unit_id UUID REFERENCES property_units(unit_id),

    -- Request Details
    tenant_id UUID NOT NULL REFERENCES users(user_id),
    request_type VARCHAR(30) NOT NULL
        CHECK (request_type IN ('repair', 'maintenance', 'emergency', 'improvement', 'inspection')),

    -- Description
    request_title VARCHAR(200) NOT NULL,
    request_description TEXT NOT NULL,
    urgency_level VARCHAR(10) DEFAULT 'medium'
        CHECK (urgency_level IN ('low', 'medium', 'high', 'emergency')),

    -- Media
    photos JSONB,
    videos JSONB,

    -- Assignment
    assigned_to UUID REFERENCES users(user_id),
    assigned_at TIMESTAMP WITH TIME ZONE,

    -- Status and Resolution
    request_status VARCHAR(20) DEFAULT 'submitted'
        CHECK (request_status IN ('submitted', 'acknowledged', 'in_progress', 'completed', 'cancelled')),
    resolution_description TEXT,
    resolution_cost DECIMAL(8,2),

    -- Scheduling
    scheduled_date DATE,
    completed_date DATE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id)
);

-- ===========================================
-- MARKET ANALYSIS AND ANALYTICS
-- ===========================================

-- Market Statistics
CREATE TABLE market_statistics (
    statistic_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Geographic Scope
    city VARCHAR(100),
    state_province VARCHAR(50),
    zip_code VARCHAR(20),
    neighborhood VARCHAR(100),

    -- Time Period
    statistic_date DATE DEFAULT CURRENT_DATE,
    period_type VARCHAR(20) DEFAULT 'monthly'
        CHECK (period_type IN ('daily', 'weekly', 'monthly', 'quarterly', 'yearly')),

    -- Market Metrics
    median_home_price DECIMAL(12,2),
    average_home_price DECIMAL(12,2),
    homes_sold INTEGER,
    new_listings INTEGER,
    pending_sales INTEGER,

    -- Price Statistics
    price_per_sqft_median DECIMAL(8,2),
    price_per_sqft_average DECIMAL(8,2),
    price_change_mom DECIMAL(5,2),  -- Month over month
    price_change_yoy DECIMAL(5,2),  -- Year over year

    -- Market Health Indicators
    months_of_inventory DECIMAL(4,1),
    absorption_rate DECIMAL(5,2),
    market_temperature VARCHAR(20),  -- 'cold', 'cool', 'balanced', 'hot', 'boiling'

    -- Rental Metrics
    median_rent DECIMAL(8,2),
    average_rent DECIMAL(8,2),
    vacancy_rate DECIMAL(5,2),
    rental_yield DECIMAL(5,2),

    -- Data Source
    data_source VARCHAR(50),  -- MLS, Zillow, Realtor.com, etc.
    confidence_level VARCHAR(10) DEFAULT 'high'
        CHECK (confidence_level IN ('low', 'medium', 'high')),

    UNIQUE (city, state_province, zip_code, statistic_date, period_type)
) PARTITION BY RANGE (statistic_date);

-- Property Analytics
CREATE TABLE property_analytics (
    analytic_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id),

    -- Time Period
    date_recorded DATE DEFAULT CURRENT_DATE,
    month_year DATE,

    -- Property Performance
    view_count INTEGER DEFAULT 0,
    favorite_count INTEGER DEFAULT 0,
    inquiry_count INTEGER DEFAULT 0,
    offer_count INTEGER DEFAULT 0,

    -- Market Position
    comparable_sales JSONB,
    market_value_estimate DECIMAL(12,2),
    days_on_market_average INTEGER,

    -- Demographic Data
    viewer_demographics JSONB,
    traffic_sources JSONB,

    UNIQUE (property_id, date_recorded)
) PARTITION BY RANGE (date_recorded);

-- ===========================================
-- SHOWINGS AND CLIENT INTERACTIONS
-- ===========================================

-- Property Showings
CREATE TABLE property_showings (
    showing_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID NOT NULL REFERENCES listings(listing_id),

    -- Client Information
    client_id UUID REFERENCES users(user_id),
    client_name VARCHAR(200),
    client_email VARCHAR(255),
    client_phone VARCHAR(20),

    -- Showing Details
    showing_type VARCHAR(20) DEFAULT 'in_person'
        CHECK (showing_type IN ('in_person', 'virtual', 'video_call', 'self_tour')),

    -- Scheduling
    scheduled_date DATE NOT NULL,
    scheduled_start_time TIME NOT NULL,
    scheduled_end_time TIME,
    actual_start_time TIME,
    actual_end_time TIME,

    -- Participants
    showing_agent_id UUID NOT NULL REFERENCES users(user_id),
    additional_agents UUID[],

    -- Property Access
    access_instructions TEXT,
    lockbox_code VARCHAR(20),
    alarm_code VARCHAR(20),

    -- Feedback and Notes
    client_feedback TEXT,
    agent_notes TEXT,
    showing_outcome VARCHAR(30),  -- 'interested', 'not_interested', 'offer_made', etc.

    -- Status
    showing_status VARCHAR(20) DEFAULT 'scheduled'
        CHECK (showing_status IN ('scheduled', 'confirmed', 'completed', 'cancelled', 'no_show')),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id)
);

-- Client Interactions
CREATE TABLE client_interactions (
    interaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Parties Involved
    agent_id UUID NOT NULL REFERENCES users(user_id),
    client_id UUID REFERENCES users(user_id),

    -- Contact Information (if not registered user)
    contact_name VARCHAR(200),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),

    -- Interaction Details
    interaction_type VARCHAR(30) NOT NULL
        CHECK (interaction_type IN ('phone_call', 'email', 'text_message', 'in_person', 'virtual_meeting', 'open_house')),

    -- Content
    interaction_summary TEXT,
    interaction_details JSONB,

    -- Property Context
    property_id UUID REFERENCES properties(property_id),
    listing_id UUID REFERENCES listings(listing_id),

    -- Outcome
    interaction_outcome VARCHAR(30),  -- 'positive', 'neutral', 'negative', 'follow_up_needed'
    next_action_required BOOLEAN DEFAULT FALSE,
    next_action_description TEXT,
    next_action_due_date DATE,

    -- Timing
    interaction_date DATE DEFAULT CURRENT_DATE,
    interaction_time TIME DEFAULT CURRENT_TIME,
    duration_minutes INTEGER,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(user_id)
);

-- ===========================================
-- DOCUMENTS AND COMPLIANCE
-- ===========================================

-- Document Management
CREATE TABLE documents (
    document_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Document Information
    document_name VARCHAR(255) NOT NULL,
    document_type VARCHAR(50) NOT NULL
        CHECK (document_type IN ('contract', 'disclosure', 'inspection', 'appraisal', 'legal', 'financial', 'photo', 'video')),

    -- File Storage
    file_url VARCHAR(500) NOT NULL,
    file_name VARCHAR(255),
    mime_type VARCHAR(100),
    file_size_bytes BIGINT,

    -- Associated Entities
    property_id UUID REFERENCES properties(property_id),
    transaction_id UUID REFERENCES transactions(transaction_id),
    listing_id UUID REFERENCES listings(listing_id),
    user_id UUID REFERENCES users(user_id),

    -- Document Metadata
    document_date DATE,
    expiration_date DATE,
    is_confidential BOOLEAN DEFAULT FALSE,

    -- Legal and Compliance
    requires_signature BOOLEAN DEFAULT FALSE,
    signature_status VARCHAR(20) DEFAULT 'not_required'
        CHECK (signature_status IN ('not_required', 'pending', 'signed', 'expired')),
    digital_signatures JSONB,

    -- Access Control
    access_permissions JSONB,  -- Who can view/edit this document

    -- Status
    document_status VARCHAR(20) DEFAULT 'active'
        CHECK (document_status IN ('active', 'archived', 'deleted')),

    -- Audit
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    uploaded_by UUID REFERENCES users(user_id),
    last_modified TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_modified_by UUID REFERENCES users(user_id)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Core property indexes
CREATE INDEX idx_properties_owner ON properties (owner_id);
CREATE INDEX idx_properties_location ON properties (city, state_province);
CREATE INDEX idx_properties_type_status ON properties (property_type, property_status);
CREATE INDEX idx_properties_geolocation ON properties USING gist (geolocation);
CREATE INDEX idx_properties_search ON properties USING gin (search_vector);

-- Listing indexes
CREATE INDEX idx_listings_property ON listings (property_id);
CREATE INDEX idx_listings_agent ON listings (listing_agent_id);
CREATE INDEX idx_listings_status_type ON listings (listing_status, listing_type);
CREATE INDEX idx_listings_price ON listings (list_price DESC);
CREATE INDEX idx_listings_rent ON listings (rent_price);

-- Transaction indexes
CREATE INDEX idx_transactions_property ON transactions (property_id);
CREATE INDEX idx_transactions_buyers_sellers ON transactions (buyer_id, seller_id);
CREATE INDEX idx_transactions_dates ON transactions (contract_date, closing_date);
CREATE INDEX idx_transactions_status ON transactions (transaction_status);

-- User indexes
CREATE INDEX idx_users_company_role ON users (company_id, user_role);
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_last_login ON users (last_login_at DESC);

-- Lease and tenancy indexes
CREATE INDEX idx_leases_property ON leases (property_id, unit_id);
CREATE INDEX idx_leases_tenant ON leases (tenant_id);
CREATE INDEX idx_leases_dates ON leases (lease_start_date, lease_end_date);
CREATE INDEX idx_lease_payments_lease ON lease_payments (lease_id, payment_date DESC);

-- Maintenance indexes
CREATE INDEX idx_maintenance_requests_property ON maintenance_requests (property_id, unit_id);
CREATE INDEX idx_maintenance_requests_status ON maintenance_requests (request_status, urgency_level);

-- Analytics indexes
CREATE INDEX idx_market_statistics_location ON market_statistics (city, state_province, zip_code, statistic_date DESC);
CREATE INDEX idx_property_analytics_property ON property_analytics (property_id, date_recorded DESC);

-- Document indexes
CREATE INDEX idx_documents_property ON documents (property_id);
CREATE INDEX idx_documents_transaction ON documents (transaction_id);
CREATE INDEX idx_documents_user ON documents (user_id);

-- ===========================================
-- PARTITIONING SETUP
-- ===========================================

-- Analytics partitioning (monthly)
CREATE TABLE market_statistics_2024_01 PARTITION OF market_statistics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE property_analytics_2024_01 PARTITION OF property_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Active listings view
CREATE VIEW active_listings AS
SELECT
    l.*,
    p.property_name,
    p.address_line_1,
    p.city,
    p.state_province,
    p.total_sqft,
    p.bedrooms,
    p.bathrooms,
    u.first_name || ' ' || u.last_name AS agent_name,
    c.company_name AS company_name
FROM listings l
JOIN properties p ON l.property_id = p.property_id
JOIN users u ON l.listing_agent_id = u.user_id
LEFT JOIN companies c ON l.listing_company_id = c.company_id
WHERE l.listing_status = 'active'
  AND (l.expiration_date IS NULL OR l.expiration_date > CURRENT_DATE);

-- Property portfolio view
CREATE VIEW property_portfolio AS
SELECT
    p.*,
    l.list_price,
    l.rent_price,
    l.listing_status,
    COALESCE(r.total_rent, 0) AS monthly_rent_income,
    COALESCE(m.request_count, 0) AS active_maintenance_requests,
    CASE
        WHEN l.listing_type = 'rent' AND l.listing_status = 'rented' THEN 'rented'
        WHEN l.listing_type = 'sale' AND l.listing_status = 'sold' THEN 'sold'
        WHEN l.listing_status = 'active' THEN 'listed'
        ELSE 'available'
    END AS occupancy_status
FROM properties p
LEFT JOIN listings l ON p.property_id = l.property_id AND l.listing_status IN ('active', 'rented', 'sold')
LEFT JOIN (
    SELECT property_id, SUM(monthly_rent) AS total_rent
    FROM leases
    WHERE lease_status = 'active'
    GROUP BY property_id
) r ON p.property_id = r.property_id
LEFT JOIN (
    SELECT property_id, COUNT(*) AS request_count
    FROM maintenance_requests
    WHERE request_status IN ('submitted', 'acknowledged', 'in_progress')
    GROUP BY property_id
) m ON p.property_id = m.property_id;

-- Market trends view
CREATE VIEW market_trends AS
SELECT
    ms.city,
    ms.state_province,
    ms.statistic_date,
    ms.median_home_price,
    ms.average_home_price,
    ms.homes_sold,
    ms.median_rent,
    ms.vacancy_rate,
    ms.market_temperature,

    -- Price changes
    LAG(ms.median_home_price) OVER (
        PARTITION BY ms.city, ms.state_province
        ORDER BY ms.statistic_date
    ) AS prev_month_median_price,

    CASE
        WHEN LAG(ms.median_home_price) OVER (
            PARTITION BY ms.city, ms.state_province
            ORDER BY ms.statistic_date
        ) IS NOT NULL THEN
            ROUND(
                (ms.median_home_price - LAG(ms.median_home_price) OVER (
                    PARTITION BY ms.city, ms.state_province
                    ORDER BY ms.statistic_date
                )) / LAG(ms.median_home_price) OVER (
                    PARTITION BY ms.city, ms.state_province
                    ORDER BY ms.statistic_date
                ) * 100, 2
            )
        ELSE NULL
    END AS price_change_percent

FROM market_statistics ms
WHERE ms.period_type = 'monthly'
ORDER BY ms.city, ms.state_province, ms.statistic_date DESC;

-- Lease payment summary view
CREATE VIEW lease_payment_summary AS
SELECT
    l.lease_id,
    l.property_id,
    l.unit_id,
    l.tenant_id,
    t.first_name || ' ' || t.last_name AS tenant_name,
    l.monthly_rent,
    l.lease_start_date,
    l.lease_end_date,

    -- Payment status for current month
    COALESCE(p.current_month_paid, 0) AS current_month_paid,
    COALESCE(p.current_month_amount, 0) AS current_month_amount,
    CASE
        WHEN COALESCE(p.current_month_paid, 0) >= COALESCE(p.current_month_amount, 0) THEN 'paid'
        WHEN COALESCE(p.current_month_paid, 0) > 0 THEN 'partial'
        ELSE 'unpaid'
    END AS current_payment_status,

    -- Payment history
    COALESCE(ph.total_paid, 0) AS total_paid,
    COALESCE(ph.on_time_payments, 0) AS on_time_payments,
    COALESCE(ph.late_payments, 0) AS late_payments,

    -- Outstanding amounts
    COALESCE(p.current_month_amount, l.monthly_rent) - COALESCE(p.current_month_paid, 0) AS amount_due

FROM leases l
JOIN users t ON l.tenant_id = t.user_id
LEFT JOIN (
    SELECT
        lease_id,
        SUM(CASE WHEN payment_date >= date_trunc('month', CURRENT_DATE)
                      AND payment_date < date_trunc('month', CURRENT_DATE + INTERVAL '1 month')
                 THEN payment_amount ELSE 0 END) AS current_month_paid,
        SUM(CASE WHEN payment_date >= date_trunc('month', CURRENT_DATE)
                      AND payment_date < date_trunc('month', CURRENT_DATE + INTERVAL '1 month')
                 THEN 1 ELSE 0 END) * (SELECT monthly_rent FROM leases WHERE lease_id = lease_payments.lease_id LIMIT 1) AS current_month_amount
    FROM lease_payments
    WHERE payment_status = 'received'
    GROUP BY lease_id
) p ON l.lease_id = p.lease_id
LEFT JOIN (
    SELECT
        lease_id,
        SUM(payment_amount) AS total_paid,
        COUNT(CASE WHEN payment_date <= period_end THEN 1 END) AS on_time_payments,
        COUNT(CASE WHEN payment_date > period_end THEN 1 END) AS late_payments
    FROM lease_payments lp
    CROSS JOIN LATERAL (
        SELECT
            date_trunc('month', payment_date) + INTERVAL '1 month' - INTERVAL '1 day' AS period_end
    ) pd
    WHERE lp.payment_status = 'received'
    GROUP BY lease_id
) ph ON l.lease_id = ph.lease_id
WHERE l.lease_status = 'active';

-- ===========================================
-- TRIGGERS FOR BUSINESS LOGIC
-- ===========================================

-- Update property status based on transactions
CREATE OR REPLACE FUNCTION update_property_status_on_transaction()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.transaction_status = 'closed' THEN
        IF NEW.transaction_type = 'sale' THEN
            UPDATE properties SET property_status = 'sold' WHERE property_id = NEW.property_id;
        ELSIF NEW.transaction_type = 'rental' THEN
            UPDATE properties SET property_status = 'rented' WHERE property_id = NEW.property_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_property_status
    AFTER UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_property_status_on_transaction();

-- Update unit status based on lease
CREATE OR REPLACE FUNCTION update_unit_status_on_lease()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.lease_status = 'active' THEN
        UPDATE property_units SET
            unit_status = 'occupied',
            current_tenant_id = NEW.tenant_id,
            lease_start_date = NEW.lease_start_date,
            lease_end_date = NEW.lease_end_date
        WHERE unit_id = NEW.unit_id;
    ELSIF NEW.lease_status IN ('expired', 'terminated') THEN
        UPDATE property_units SET
            unit_status = 'vacant',
            current_tenant_id = NULL,
            lease_start_date = NULL,
            lease_end_date = NULL
        WHERE unit_id = NEW.unit_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_unit_status
    AFTER INSERT OR UPDATE ON leases
    FOR EACH ROW EXECUTE FUNCTION update_unit_status_on_lease();

-- Calculate commission on transaction close
CREATE OR REPLACE FUNCTION calculate_transaction_commission()
RETURNS TRIGGER AS $$
DECLARE
    commission_rate DECIMAL(5,2);
    sale_amount DECIMAL(12,2);
BEGIN
    IF NEW.transaction_status = 'closed' AND OLD.transaction_status != 'closed' THEN
        -- Get commission rate from listing
        SELECT l.commission_rate INTO commission_rate
        FROM listings l WHERE l.listing_id = NEW.listing_id;

        -- Calculate commission
        IF NEW.transaction_type = 'sale' THEN
            sale_amount := NEW.sale_price;
        ELSE
            -- For rentals, commission might be one month's rent
            sale_amount := NEW.rent_amount;
        END IF;

        NEW.commission_amount := sale_amount * (commission_rate / 100);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calculate_commission
    BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION calculate_transaction_commission();

-- Track property analytics
CREATE OR REPLACE FUNCTION update_property_analytics()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO property_analytics (property_id, view_count, favorite_count, inquiry_count, offer_count)
    VALUES (NEW.property_id, 1, 0, 0, 0)
    ON CONFLICT (property_id, date_recorded)
    DO UPDATE SET
        view_count = property_analytics.view_count + 1;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- This trigger would be called when a property is viewed
-- CREATE TRIGGER trigger_property_view_analytics
--     AFTER INSERT ON property_views
--     FOR EACH ROW EXECUTE FUNCTION update_property_analytics();

-- This comprehensive real estate database schema provides a solid foundation
-- for property management, real estate transactions, leasing, and market analysis
-- with support for multi-company operations and complex real estate workflows.
