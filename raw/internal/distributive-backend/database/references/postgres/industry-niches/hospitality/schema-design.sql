-- Hospitality & Hotel Management Database Schema
-- Comprehensive schema for hotel operations, reservations, guest services, and property management

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- PROPERTY AND FACILITY MANAGEMENT
-- ===========================================

CREATE TABLE properties (
    property_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_code VARCHAR(20) UNIQUE NOT NULL,
    property_name VARCHAR(255) NOT NULL,

    -- Property Classification
    property_type VARCHAR(30) CHECK (property_type IN ('hotel', 'resort', 'motel', 'boutique_hotel', 'apartment_hotel', 'extended_stay')),
    star_rating INTEGER CHECK (star_rating BETWEEN 1 AND 5),
    brand_name VARCHAR(100),

    -- Location Information
    address JSONB NOT NULL,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Property Details
    total_rooms INTEGER NOT NULL,
    total_floors INTEGER,
    year_built INTEGER,
    last_renovated INTEGER,

    -- Contact Information
    phone VARCHAR(20),
    email VARCHAR(255),
    website VARCHAR(500),

    -- Operational Details
    check_in_time TIME DEFAULT '15:00',
    check_out_time TIME DEFAULT '11:00',
    front_desk_hours JSONB DEFAULT '{}',

    -- Financial Information
    base_currency CHAR(3) DEFAULT 'USD',
    management_company VARCHAR(255),

    -- Status and Operations
    property_status VARCHAR(20) DEFAULT 'operational' CHECK (property_status IN ('operational', 'under_renovation', 'closed', 'sold')),
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE rooms (
    room_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id) ON DELETE CASCADE,

    -- Room Identification
    room_number VARCHAR(20) NOT NULL,
    room_code VARCHAR(10) UNIQUE NOT NULL,

    -- Room Details
    room_type VARCHAR(50) NOT NULL CHECK (room_type IN ('standard', 'deluxe', 'suite', 'executive', 'presidential', 'penthouse')),
    room_category VARCHAR(30) CHECK (room_category IN ('king', 'queen', 'double', 'twin', 'studio', 'loft')),

    -- Physical Details
    floor_number INTEGER,
    square_footage INTEGER,
    max_occupancy INTEGER DEFAULT 2,
    bed_configuration JSONB DEFAULT '{}', -- [{"type": "king", "count": 1}]

    -- Amenities and Features
    amenities JSONB DEFAULT '[]', -- ["wifi", "minibar", "balcony", "ocean_view"]
    accessibility_features JSONB DEFAULT '[]', -- ["wheelchair_accessible", "hearing_impaired"]
    smoking_allowed BOOLEAN DEFAULT FALSE,

    -- Pricing and Revenue
    base_rate DECIMAL(8,2),
    rack_rate DECIMAL(8,2), -- Published rate
    minimum_rate DECIMAL(8,2),

    -- Operational Status
    room_status VARCHAR(20) DEFAULT 'available' CHECK (room_status IN (
        'available', 'occupied', 'out_of_order', 'maintenance', 'cleaning', 'inspection'
    )),
    housekeeping_status VARCHAR(20) DEFAULT 'clean' CHECK (housekeeping_status IN (
        'clean', 'dirty', 'inspected', 'maintenance_required', 'deep_clean_required'
    )),

    -- Maintenance and History
    last_maintenance_date DATE,
    last_inspection_date DATE,
    maintenance_notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (property_id, room_number)
);

CREATE TABLE room_rates (
    rate_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,

    -- Rate Details
    rate_code VARCHAR(20) NOT NULL,
    rate_name VARCHAR(100),
    rate_description TEXT,

    -- Pricing Structure
    base_rate DECIMAL(8,2) NOT NULL,
    additional_adult_rate DECIMAL(8,2) DEFAULT 0,
    child_rate DECIMAL(8,2) DEFAULT 0,

    -- Rate Period
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL,
    days_of_week INTEGER[], -- 0=Sunday, 1=Monday, etc.

    -- Restrictions and Rules
    minimum_stay_nights INTEGER DEFAULT 1,
    maximum_stay_nights INTEGER,
    advance_booking_days INTEGER, -- Minimum days in advance
    cancellation_policy VARCHAR(50),

    -- Availability and Inventory
    total_rooms_allocated INTEGER, -- Rooms allocated to this rate
    rooms_sold INTEGER DEFAULT 0,
    remaining_rooms INTEGER GENERATED ALWAYS AS (total_rooms_allocated - rooms_sold) STORED,

    -- Status
    rate_status VARCHAR(20) DEFAULT 'active' CHECK (rate_status IN ('active', 'inactive', 'sold_out')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (valid_from <= valid_to),
    CHECK (remaining_rooms >= 0)
);

-- ===========================================
-- RESERVATION AND BOOKING MANAGEMENT
-- ===========================================

CREATE TABLE reservations (
    reservation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_number VARCHAR(30) UNIQUE NOT NULL,

    -- Guest Information
    guest_id UUID, -- References guests table
    guest_title VARCHAR(10),
    guest_first_name VARCHAR(100) NOT NULL,
    guest_last_name VARCHAR(100) NOT NULL,
    guest_email VARCHAR(255),
    guest_phone VARCHAR(20),

    -- Reservation Details
    property_id UUID NOT NULL REFERENCES properties(property_id),
    room_type_requested VARCHAR(50),
    number_of_rooms INTEGER DEFAULT 1,
    number_of_adults INTEGER DEFAULT 1,
    number_of_children INTEGER DEFAULT 0,

    -- Stay Details
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    length_of_stay INTEGER GENERATED ALWAYS AS (check_out_date - check_in_date) STORED,

    -- Financial Information
    total_rate DECIMAL(10,2),
    taxes_and_fees DECIMAL(8,2),
    total_amount DECIMAL(10,2),
    currency_code CHAR(3) DEFAULT 'USD',

    -- Reservation Status
    reservation_status VARCHAR(30) DEFAULT 'confirmed' CHECK (reservation_status IN (
        'tentative', 'confirmed', 'checked_in', 'checked_out', 'cancelled', 'no_show'
    )),
    confirmation_number VARCHAR(20) UNIQUE,

    -- Booking Channel
    booking_channel VARCHAR(30) CHECK (booking_channel IN (
        'direct', 'online', 'ota', 'travel_agent', 'corporate', 'wholesale', 'gds'
    )),
    booking_reference VARCHAR(50), -- External booking reference
    third_party_booking_id VARCHAR(50),

    -- Special Requests and Notes
    special_requests TEXT,
    guest_notes TEXT,
    internal_notes TEXT,

    -- Guest History
    previous_stays INTEGER DEFAULT 0,
    loyalty_member BOOLEAN DEFAULT FALSE,
    vip_status BOOLEAN DEFAULT FALSE,

    -- Cancellation Policy
    cancellation_policy TEXT,
    cancellation_deadline DATE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (check_in_date < check_out_date),
    CHECK (number_of_adults > 0)
);

CREATE TABLE reservation_rooms (
    reservation_room_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_id UUID NOT NULL REFERENCES reservations(reservation_id) ON DELETE CASCADE,

    -- Room Assignment
    room_id UUID REFERENCES rooms(room_id),
    room_rate_id UUID REFERENCES room_rates(rate_id),

    -- Guest Information for this Room
    primary_guest_name VARCHAR(200),
    additional_guests JSONB DEFAULT '[]', -- Array of additional guest names

    -- Stay Details
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    actual_check_in_time TIMESTAMP WITH TIME ZONE,
    actual_check_out_time TIMESTAMP WITH TIME ZONE,

    -- Financial Details
    room_rate DECIMAL(8,2),
    total_room_charges DECIMAL(10,2),
    paid_amount DECIMAL(10,2) DEFAULT 0,
    outstanding_balance DECIMAL(10,2) GENERATED ALWAYS AS (total_room_charges - paid_amount) STORED,

    -- Status
    room_status VARCHAR(20) DEFAULT 'reserved' CHECK (room_status IN (
        'reserved', 'checked_in', 'checked_out', 'cancelled', 'no_show'
    )),
    housekeeping_status VARCHAR(20) DEFAULT 'pending' CHECK (housekeeping_status IN (
        'pending', 'in_progress', 'completed', 'inspected'
    )),

    -- Services and Amenities
    requested_services JSONB DEFAULT '[]', -- Room service, late checkout, etc.

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE room_blocks (
    block_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id),

    -- Block Details
    block_name VARCHAR(255) NOT NULL,
    block_code VARCHAR(20) UNIQUE NOT NULL,
    block_type VARCHAR(30) CHECK (block_type IN ('group', 'tour', 'corporate', 'wedding', 'conference', 'maintenance')),

    -- Room Allocation
    total_rooms_blocked INTEGER NOT NULL,
    rooms_allocated INTEGER DEFAULT 0,
    rooms_picked_up INTEGER DEFAULT 0,
    rooms_available INTEGER GENERATED ALWAYS AS (total_rooms_blocked - rooms_allocated) STORED,

    -- Date Range
    block_start_date DATE NOT NULL,
    block_end_date DATE NOT NULL,

    -- Financial Terms
    contracted_rate DECIMAL(8,2),
    cutoff_date DATE, -- Date after which unsold rooms are released
    cancellation_policy TEXT,

    -- Associated Reservations
    master_reservation_id UUID REFERENCES reservations(reservation_id),

    -- Status
    block_status VARCHAR(20) DEFAULT 'active' CHECK (block_status IN ('active', 'released', 'expired', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (block_start_date <= block_end_date),
    CHECK (rooms_available >= 0)
);

-- ===========================================
-- GUEST SERVICES AND OPERATIONS
-- ===========================================

CREATE TABLE guests (
    guest_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_number VARCHAR(20) UNIQUE,

    -- Personal Information
    title VARCHAR(10),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    date_of_birth DATE,
    gender VARCHAR(20),

    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(20),
    mobile_phone VARCHAR(20),

    -- Address Information
    home_address JSONB,
    business_address JSONB,

    -- Guest Profile
    nationality VARCHAR(50),
    language_primary VARCHAR(10) DEFAULT 'en',
    preferred_room_type VARCHAR(50),
    dietary_restrictions TEXT,
    accessibility_needs TEXT,

    -- Guest History and Loyalty
    total_stays INTEGER DEFAULT 0,
    total_nights INTEGER DEFAULT 0,
    total_spent DECIMAL(12,2) DEFAULT 0,
    first_visit_date DATE,
    last_visit_date DATE,

    -- Loyalty Program
    loyalty_program_member BOOLEAN DEFAULT FALSE,
    loyalty_membership_number VARCHAR(30),
    loyalty_tier VARCHAR(20),

    -- Preferences and Notes
    room_preferences JSONB DEFAULT '{}',
    communication_preferences JSONB DEFAULT '{"email": true, "sms": true, "phone": true}',
    special_notes TEXT,

    -- Status
    guest_status VARCHAR(20) DEFAULT 'active' CHECK (guest_status IN ('active', 'inactive', 'vip', 'blacklisted')),
    do_not_rent BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE in_house_guests (
    in_house_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_room_id UUID NOT NULL REFERENCES reservation_rooms(reservation_room_id),

    -- Guest Details (shadow copy for performance)
    guest_id UUID REFERENCES guests(guest_id),
    guest_name VARCHAR(200) NOT NULL,
    guest_type VARCHAR(20) DEFAULT 'primary' CHECK (guest_type IN ('primary', 'additional', 'companion')),

    -- Stay Information
    check_in_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expected_check_out DATE,
    actual_check_out_time TIMESTAMP WITH TIME ZONE,

    -- Guest Services
    key_card_number VARCHAR(20),
    safe_combination VARCHAR(10),
    room_telephone_extension VARCHAR(10),

    -- Services and Charges
    services_used JSONB DEFAULT '[]', -- Minibar, room service, etc.
    incident_reports JSONB DEFAULT '[]', -- Any issues or incidents

    -- Status
    guest_status VARCHAR(20) DEFAULT 'checked_in' CHECK (guest_status IN ('checked_in', 'checked_out', 'transferred')),

    -- Housekeeping
    housekeeping_instructions TEXT,
    last_housekeeping_service TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE guest_services (
    service_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id),

    -- Service Details
    service_name VARCHAR(100) NOT NULL,
    service_category VARCHAR(30) CHECK (service_category IN (
        'housekeeping', 'room_service', 'concierge', 'spa', 'transportation',
        'business_center', 'fitness', 'pool', 'restaurant', 'bar'
    )),
    service_type VARCHAR(20) CHECK (service_type IN ('complimentary', 'paid', 'premium')),

    -- Service Information
    description TEXT,
    duration_minutes INTEGER,
    price DECIMAL(8,2),

    -- Availability
    available_24_hours BOOLEAN DEFAULT FALSE,
    operating_hours JSONB DEFAULT '{}',
    advance_booking_required BOOLEAN DEFAULT FALSE,
    minimum_advance_hours INTEGER,

    -- Capacity and Resources
    max_capacity INTEGER,
    required_staff INTEGER DEFAULT 1,

    -- Status
    service_status VARCHAR(20) DEFAULT 'active' CHECK (service_status IN ('active', 'inactive', 'maintenance', 'seasonal')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE service_requests (
    request_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    in_house_id UUID NOT NULL REFERENCES in_house_guests(in_house_id),

    -- Request Details
    service_id UUID NOT NULL REFERENCES guest_services(service_id),
    request_description TEXT,

    -- Scheduling
    requested_date DATE DEFAULT CURRENT_DATE,
    requested_time TIME,
    scheduled_date DATE,
    scheduled_time TIME,

    -- Request Status
    request_status VARCHAR(20) DEFAULT 'requested' CHECK (request_status IN (
        'requested', 'scheduled', 'in_progress', 'completed', 'cancelled'
    )),

    -- Assignment and Completion
    assigned_staff_id UUID,
    completed_at TIMESTAMP WITH TIME ZONE,
    completion_notes TEXT,

    -- Billing
    charge_amount DECIMAL(8,2),
    billed BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- FINANCIAL MANAGEMENT AND BILLING
-- ===========================================

CREATE TABLE folios (
    folio_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_room_id UUID NOT NULL REFERENCES reservation_rooms(reservation_room_id),

    -- Folio Details
    folio_number VARCHAR(30) UNIQUE NOT NULL,
    folio_type VARCHAR(20) DEFAULT 'guest' CHECK (folio_type IN ('guest', 'master', 'group', 'incident')),

    -- Financial Summary
    room_charges DECIMAL(10,2) DEFAULT 0,
    service_charges DECIMAL(10,2) DEFAULT 0,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    total_charges DECIMAL(10,2) GENERATED ALWAYS AS (room_charges + service_charges + tax_amount) STORED,

    -- Payments and Adjustments
    payments_received DECIMAL(10,2) DEFAULT 0,
    adjustments DECIMAL(10,2) DEFAULT 0,
    outstanding_balance DECIMAL(10,2) GENERATED ALWAYS AS (total_charges - payments_received + adjustments) STORED,

    -- Billing Information
    billing_instructions TEXT,
    authorized_billing BOOLEAN DEFAULT FALSE,
    credit_limit DECIMAL(10,2),

    -- Status
    folio_status VARCHAR(20) DEFAULT 'open' CHECK (folio_status IN ('open', 'closed', 'transferred', 'written_off')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE folio_transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    folio_id UUID NOT NULL REFERENCES folios(folio_id) ON DELETE CASCADE,

    -- Transaction Details
    transaction_type VARCHAR(30) CHECK (transaction_type IN (
        'room_charge', 'service_charge', 'tax', 'payment', 'adjustment', 'transfer'
    )),
    transaction_description VARCHAR(255),

    -- Financial Details
    amount DECIMAL(10,2) NOT NULL,
    tax_amount DECIMAL(8,2) DEFAULT 0,

    -- Transaction Metadata
    transaction_date DATE DEFAULT CURRENT_DATE,
    posted_by UUID,
    reference_number VARCHAR(50), -- Invoice number, check number, etc.

    -- Related Records
    related_reservation_id UUID REFERENCES reservations(reservation_id),
    related_service_request_id UUID REFERENCES service_requests(request_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (amount != 0)
);

CREATE TABLE payments (
    payment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    folio_id UUID NOT NULL REFERENCES folios(folio_id),

    -- Payment Details
    payment_amount DECIMAL(10,2) NOT NULL,
    payment_date DATE DEFAULT CURRENT_DATE,
    payment_method VARCHAR(30) CHECK (payment_method IN (
        'cash', 'credit_card', 'debit_card', 'check', 'wire_transfer',
        'gift_card', 'loyalty_points', 'direct_billing', 'crypto'
    )),

    -- Payment Information
    payment_reference VARCHAR(100), -- Authorization code, check number, etc.
    card_last_four VARCHAR(4),
    card_type VARCHAR(20),

    -- Processing Details
    processed_by UUID,
    processing_fee DECIMAL(6,2) DEFAULT 0,

    -- Status
    payment_status VARCHAR(20) DEFAULT 'completed' CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded', 'charged_back')),

    -- Additional Details
    payment_notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (payment_amount > 0)
);

-- ===========================================
-- HOUSEKEEPING AND MAINTENANCE
-- ===========================================

CREATE TABLE housekeeping_schedule (
    schedule_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES rooms(room_id),

    -- Schedule Details
    scheduled_date DATE NOT NULL,
    scheduled_time TIME,
    cleaning_type VARCHAR(30) CHECK (cleaning_type IN ('daily', 'deep_clean', 'turnover', 'maintenance', 'inspection')),

    -- Assignment
    assigned_housekeeper_id UUID, -- References staff
    estimated_duration_minutes INTEGER DEFAULT 30,

    -- Status and Completion
    schedule_status VARCHAR(20) DEFAULT 'scheduled' CHECK (schedule_status IN ('scheduled', 'in_progress', 'completed', 'cancelled', 'missed')),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    actual_duration_minutes INTEGER,

    -- Quality Control
    quality_score INTEGER CHECK (quality_score BETWEEN 1 AND 5),
    quality_notes TEXT,
    inspected_by UUID,
    inspected_at TIMESTAMP WITH TIME ZONE,

    -- Issues and Follow-up
    issues_found TEXT,
    follow_up_required BOOLEAN DEFAULT FALSE,
    follow_up_notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (room_id, scheduled_date, cleaning_type)
);

CREATE TABLE maintenance_requests (
    maintenance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id),

    -- Request Details
    request_type VARCHAR(30) CHECK (request_type IN ('repair', 'replacement', 'upgrade', 'preventive', 'emergency')),
    severity_level VARCHAR(10) CHECK (severity_level IN ('low', 'medium', 'high', 'critical')),

    -- Location and Description
    room_id UUID REFERENCES rooms(room_id),
    location_description TEXT,
    problem_description TEXT,

    -- Request Status
    request_status VARCHAR(20) DEFAULT 'reported' CHECK (request_status IN (
        'reported', 'assigned', 'in_progress', 'completed', 'cancelled', 'deferred'
    )),

    -- Assignment and Resolution
    assigned_technician_id UUID,
    priority_level INTEGER CHECK (priority_level BETWEEN 1 AND 5), -- 1=lowest, 5=highest
    estimated_completion_hours DECIMAL(4,2),
    actual_completion_hours DECIMAL(4,2),

    -- Resolution Details
    resolution_description TEXT,
    parts_used JSONB DEFAULT '[]',
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Cost Tracking
    labor_cost DECIMAL(8,2) DEFAULT 0,
    parts_cost DECIMAL(8,2) DEFAULT 0,
    total_cost DECIMAL(8,2) GENERATED ALWAYS AS (labor_cost + parts_cost) STORED,

    -- Audit
    reported_by UUID,
    reported_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,

    CHECK (estimated_completion_hours > 0),
    CHECK (actual_completion_hours >= 0)
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

CREATE TABLE occupancy_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES properties(property_id),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_month DATE,

    -- Occupancy Metrics
    total_rooms_available INTEGER,
    rooms_sold INTEGER,
    occupancy_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN total_rooms_available > 0 THEN (rooms_sold::DECIMAL / total_rooms_available) * 100 ELSE 0 END
    ) STORED,

    -- Revenue Metrics
    room_revenue DECIMAL(12,2) DEFAULT 0,
    food_beverage_revenue DECIMAL(12,2) DEFAULT 0,
    other_revenue DECIMAL(12,2) DEFAULT 0,
    total_revenue DECIMAL(12,2) GENERATED ALWAYS AS (room_revenue + food_beverage_revenue + other_revenue) STORED,

    -- Average Metrics
    average_daily_rate DECIMAL(8,2),
    revenue_per_available_room DECIMAL(8,2) GENERATED ALWAYS AS (
        CASE WHEN total_rooms_available > 0 THEN total_revenue / total_rooms_available ELSE 0 END
    ) STORED,

    -- Guest Metrics
    total_guests INTEGER DEFAULT 0,
    average_guests_per_room DECIMAL(4,2),

    -- Booking Channel Metrics
    direct_bookings INTEGER DEFAULT 0,
    ota_bookings INTEGER DEFAULT 0,
    corporate_bookings INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (property_id, report_date)
);

CREATE TABLE guest_satisfaction (
    satisfaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_id UUID NOT NULL REFERENCES reservations(reservation_id),

    -- Survey Details
    survey_date DATE DEFAULT CURRENT_DATE,
    survey_method VARCHAR(20) CHECK (survey_method IN ('email', 'phone', 'in_person', 'online_form')),

    -- Overall Satisfaction
    overall_rating INTEGER CHECK (overall_rating BETWEEN 1 AND 5),
    likelihood_to_recommend INTEGER CHECK (likelihood_to_recommend BETWEEN 1 AND 10),

    -- Detailed Ratings
    room_quality_rating INTEGER CHECK (room_quality_rating BETWEEN 1 AND 5),
    service_quality_rating INTEGER CHECK (service_quality_rating BETWEEN 1 AND 5),
    value_rating INTEGER CHECK (value_rating BETWEEN 1 AND 5),
    cleanliness_rating INTEGER CHECK (cleanliness_rating BETWEEN 1 AND 5),

    -- Comments and Feedback
    positive_comments TEXT,
    negative_comments TEXT,
    improvement_suggestions TEXT,

    -- Guest Information
    guest_age_group VARCHAR(20) CHECK (guest_age_group IN ('18-24', '25-34', '35-44', '45-54', '55-64', '65+')),
    travel_purpose VARCHAR(30) CHECK (travel_purpose IN ('business', 'leisure', 'family', 'medical', 'other')),

    -- Follow-up
    follow_up_required BOOLEAN DEFAULT FALSE,
    follow_up_notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Property and room indexes
CREATE INDEX idx_properties_type_status ON properties (property_type, property_status);
CREATE INDEX idx_rooms_property_type ON rooms (property_id, room_type);
CREATE INDEX idx_rooms_status ON rooms (room_status, housekeeping_status);

-- Reservation indexes
CREATE INDEX idx_reservations_property_dates ON reservations (property_id, check_in_date, check_out_date);
CREATE INDEX idx_reservations_guest ON reservations (guest_id);
CREATE INDEX idx_reservations_status ON reservations (reservation_status);
CREATE INDEX idx_reservations_dates ON reservations (check_in_date, check_out_date);

-- Room assignment indexes
CREATE INDEX idx_reservation_rooms_reservation ON reservation_rooms (reservation_id);
CREATE INDEX idx_reservation_rooms_room ON reservation_rooms (room_id);
CREATE INDEX idx_reservation_rooms_dates ON reservation_rooms (check_in_date, check_out_date);

-- Guest indexes
CREATE INDEX idx_guests_email ON guests (email);
CREATE INDEX idx_guests_status ON guests (guest_status);
CREATE INDEX idx_in_house_guests_reservation ON in_house_guests (reservation_room_id);

-- Financial indexes
CREATE INDEX idx_folios_reservation ON folios (reservation_room_id);
CREATE INDEX idx_folios_status ON folios (folio_status);
CREATE INDEX idx_folio_transactions_folio ON folio_transactions (folio_id);
CREATE INDEX idx_payments_folio ON payments (folio_id);

-- Service indexes
CREATE INDEX idx_service_requests_in_house ON service_requests (in_house_id);
CREATE INDEX idx_service_requests_service ON service_requests (service_id);
CREATE INDEX idx_service_requests_status ON service_requests (request_status);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Property occupancy dashboard
CREATE VIEW property_occupancy AS
SELECT
    p.property_id,
    p.property_name,
    p.total_rooms,

    -- Current occupancy
    COUNT(rr.reservation_room_id) as rooms_occupied,
    (COUNT(rr.reservation_room_id) * 100.0 / p.total_rooms) as occupancy_percentage,

    -- Today's arrivals and departures
    COUNT(CASE WHEN rr.check_in_date = CURRENT_DATE THEN 1 END) as arrivals_today,
    COUNT(CASE WHEN rr.check_out_date = CURRENT_DATE THEN 1 END) as departures_today,

    -- Revenue today
    COALESCE(SUM(CASE WHEN rr.check_in_date <= CURRENT_DATE AND rr.check_out_date > CURRENT_DATE
                     THEN rr.room_rate END), 0) as revenue_today,

    -- Room status breakdown
    COUNT(CASE WHEN r.room_status = 'available' THEN 1 END) as rooms_available,
    COUNT(CASE WHEN r.room_status = 'occupied' THEN 1 END) as rooms_occupied_total,
    COUNT(CASE WHEN r.room_status = 'out_of_order' THEN 1 END) as rooms_out_of_order,
    COUNT(CASE WHEN r.room_status = 'maintenance' THEN 1 END) as rooms_maintenance,

    -- Housekeeping status
    COUNT(CASE WHEN r.housekeeping_status = 'clean' THEN 1 END) as rooms_clean,
    COUNT(CASE WHEN r.housekeeping_status = 'dirty' THEN 1 END) as rooms_dirty

FROM properties p
LEFT JOIN rooms r ON p.property_id = r.property_id
LEFT JOIN reservation_rooms rr ON r.room_id = rr.room_id
    AND rr.check_in_date <= CURRENT_DATE
    AND rr.check_out_date > CURRENT_DATE
    AND rr.room_status = 'checked_in'
GROUP BY p.property_id, p.property_name, p.total_rooms;

-- Guest stay summary
CREATE VIEW guest_stay_summary AS
SELECT
    r.reservation_id,
    r.reservation_number,
    r.guest_first_name || ' ' || r.guest_last_name as guest_name,
    r.check_in_date,
    r.check_out_date,
    r.length_of_stay,

    -- Financial summary
    r.total_amount,
    COALESCE(SUM(p.payment_amount), 0) as amount_paid,
    r.total_amount - COALESCE(SUM(p.payment_amount), 0) as outstanding_balance,

    -- Room information
    COUNT(rr.reservation_room_id) as number_of_rooms,
    STRING_AGG(DISTINCT rm.room_number, ', ') as room_numbers,

    -- Services used
    COUNT(sr.request_id) as services_requested,
    COUNT(CASE WHEN sr.request_status = 'completed' THEN 1 END) as services_completed,

    -- Satisfaction
    AVG(gs.overall_rating) as average_satisfaction_rating

FROM reservations r
LEFT JOIN reservation_rooms rr ON r.reservation_id = rr.reservation_id
LEFT JOIN rooms rm ON rr.room_id = rm.room_id
LEFT JOIN payments p ON rr.reservation_room_id = p.folio_id
LEFT JOIN service_requests sr ON rr.reservation_room_id = sr.in_house_id
LEFT JOIN guest_satisfaction gs ON r.reservation_id = gs.reservation_id
WHERE r.reservation_status IN ('checked_out', 'checked_in')
GROUP BY r.reservation_id, r.reservation_number, r.guest_first_name, r.guest_last_name,
         r.check_in_date, r.check_out_date, r.length_of_stay, r.total_amount;

-- Revenue analytics dashboard
CREATE VIEW revenue_analytics AS
SELECT
    p.property_id,
    p.property_name,

    -- Monthly metrics (last 12 months)
    DATE_TRUNC('month', CURRENT_DATE) as report_month,
    SUM(oa.room_revenue) as monthly_room_revenue,
    SUM(oa.total_revenue) as monthly_total_revenue,
    AVG(oa.occupancy_rate) as avg_monthly_occupancy,

    -- Year-to-date metrics
    SUM(CASE WHEN DATE_TRUNC('month', oa.report_date) >= DATE_TRUNC('year', CURRENT_DATE)
             THEN oa.total_revenue END) as ytd_revenue,

    -- Key performance indicators
    AVG(oa.average_daily_rate) as avg_daily_rate,
    AVG(oa.revenue_per_available_room) as revpar,

    -- Comparison to previous periods
    LAG(SUM(oa.total_revenue)) OVER (PARTITION BY p.property_id ORDER BY DATE_TRUNC('month', CURRENT_DATE)) as previous_month_revenue,
    CASE WHEN LAG(SUM(oa.total_revenue)) OVER (PARTITION BY p.property_id ORDER BY DATE_TRUNC('month', CURRENT_DATE)) > 0
         THEN ((SUM(oa.total_revenue) - LAG(SUM(oa.total_revenue)) OVER (PARTITION BY p.property_id ORDER BY DATE_TRUNC('month', CURRENT_DATE))) /
               LAG(SUM(oa.total_revenue)) OVER (PARTITION BY p.property_id ORDER BY DATE_TRUNC('month', CURRENT_DATE))) * 100
         ELSE 0 END as revenue_growth_percentage

FROM properties p
LEFT JOIN occupancy_analytics oa ON p.property_id = oa.property_id
    AND oa.report_date >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY p.property_id, p.property_name, DATE_TRUNC('month', CURRENT_DATE);

-- Maintenance and housekeeping dashboard
CREATE VIEW maintenance_dashboard AS
SELECT
    p.property_id,
    p.property_name,

    -- Maintenance metrics
    COUNT(mr.maintenance_id) as open_maintenance_requests,
    COUNT(CASE WHEN mr.request_status = 'in_progress' THEN 1 END) as maintenance_in_progress,
    COUNT(CASE WHEN mr.severity_level = 'critical' THEN 1 END) as critical_maintenance_issues,
    AVG(EXTRACT(EPOCH FROM (mr.completed_at - mr.reported_at))/3600) as avg_resolution_hours,

    -- Housekeeping metrics
    COUNT(hs.schedule_id) as housekeeping_scheduled_today,
    COUNT(CASE WHEN hs.schedule_status = 'completed' THEN 1 END) as housekeeping_completed_today,
    COUNT(CASE WHEN hs.schedule_status = 'missed' THEN 1 END) as housekeeping_missed_today,
    AVG(hs.actual_duration_minutes) as avg_housekeeping_duration,

    -- Room status
    COUNT(CASE WHEN r.room_status = 'out_of_order' THEN 1 END) as rooms_out_of_order,
    COUNT(CASE WHEN r.housekeeping_status = 'deep_clean_required' THEN 1 END) as rooms_needing_deep_clean,

    -- Quality metrics
    AVG(hs.quality_score) as avg_housekeeping_quality_score,
    COUNT(CASE WHEN hs.quality_score < 3 THEN 1 END) as poor_quality_housekeeping

FROM properties p
LEFT JOIN rooms r ON p.property_id = r.property_id
LEFT JOIN maintenance_requests mr ON p.property_id = mr.property_id
    AND mr.request_status NOT IN ('completed', 'cancelled')
LEFT JOIN housekeeping_schedule hs ON r.room_id = hs.room_id
    AND hs.scheduled_date = CURRENT_DATE
GROUP BY p.property_id, p.property_name;

-- ===========================================
-- FUNCTIONS FOR HOSPITALITY OPERATIONS
-- =========================================--

-- Function to check room availability
CREATE OR REPLACE FUNCTION check_room_availability(
    property_uuid UUID,
    room_type_param VARCHAR,
    check_in_date DATE,
    check_out_date DATE,
    number_of_rooms INTEGER DEFAULT 1
)
RETURNS TABLE (
    available_rooms INTEGER,
    total_rooms INTEGER,
    availability_status VARCHAR
) AS $$
DECLARE
    total_rooms_count INTEGER;
    booked_rooms_count INTEGER;
BEGIN
    -- Count total rooms of requested type
    SELECT COUNT(*) INTO total_rooms_count
    FROM rooms
    WHERE property_id = property_uuid
      AND room_type = room_type_param
      AND room_status = 'available';

    -- Count booked rooms for the date range
    SELECT COUNT(DISTINCT rr.room_id) INTO booked_rooms_count
    FROM reservation_rooms rr
    JOIN rooms r ON rr.room_id = r.room_id
    WHERE r.property_id = property_uuid
      AND r.room_type = room_type_param
      AND rr.room_status IN ('reserved', 'checked_in')
      AND (rr.check_in_date, rr.check_out_date) OVERLAPS (check_in_date, check_out_date);

    -- Return availability
    RETURN QUERY SELECT
        GREATEST(total_rooms_count - booked_rooms_count, 0),
        total_rooms_count,
        CASE
            WHEN total_rooms_count - booked_rooms_count >= number_of_rooms THEN 'available'
            WHEN total_rooms_count - booked_rooms_count > 0 THEN 'limited'
            ELSE 'unavailable'
        END;
END;
$$ LANGUAGE plpgsql;

-- Function to create reservation with room assignment
CREATE OR REPLACE FUNCTION create_reservation_with_rooms(
    guest_info JSONB,
    reservation_details JSONB,
    room_assignments JSONB[]
)
RETURNS UUID AS $$
DECLARE
    reservation_uuid UUID;
    room_assignment JSONB;
    room_rate_record RECORD;
    total_amount DECIMAL := 0;
BEGIN
    -- Create reservation
    INSERT INTO reservations (
        reservation_number,
        guest_title, guest_first_name, guest_last_name,
        guest_email, guest_phone,
        property_id, check_in_date, check_out_date,
        number_of_rooms, number_of_adults, number_of_children,
        booking_channel, special_requests
    ) VALUES (
        'RSV-' || UPPER(SUBSTRING(uuid_generate_v4()::TEXT, 1, 8)),
        guest_info->>'title', guest_info->>'first_name', guest_info->>'last_name',
        guest_info->>'email', guest_info->>'phone',
        (reservation_details->>'property_id')::UUID,
        (reservation_details->>'check_in_date')::DATE,
        (reservation_details->>'check_out_date')::DATE,
        (reservation_details->>'number_of_rooms')::INTEGER,
        (reservation_details->>'number_of_adults')::INTEGER,
        COALESCE((reservation_details->>'number_of_children')::INTEGER, 0),
        reservation_details->>'booking_channel',
        reservation_details->>'special_requests'
    ) RETURNING reservation_id INTO reservation_uuid;

    -- Assign rooms
    FOREACH room_assignment IN ARRAY room_assignments
    LOOP
        -- Get room rate
        SELECT rr.*, r.room_number INTO room_rate_record
        FROM room_rates rr
        JOIN rooms r ON rr.room_id = r.room_id
        WHERE rr.rate_id = (room_assignment->>'rate_id')::UUID;

        -- Calculate room charges
        INSERT INTO reservation_rooms (
            reservation_id, room_id, room_rate_id,
            check_in_date, check_out_date,
            primary_guest_name, room_rate, total_room_charges
        ) VALUES (
            reservation_uuid,
            room_rate_record.room_id,
            (room_assignment->>'rate_id')::UUID,
            (reservation_details->>'check_in_date')::DATE,
            (reservation_details->>'check_out_date')::DATE,
            room_assignment->>'guest_name',
            room_rate_record.base_rate,
            room_rate_record.base_rate * ((reservation_details->>'check_out_date')::DATE - (reservation_details->>'check_in_date')::DATE)
        );

        total_amount := total_amount + (room_rate_record.base_rate * ((reservation_details->>'check_out_date')::DATE - (reservation_details->>'check_in_date')::DATE));
    END LOOP;

    -- Update reservation total
    UPDATE reservations
    SET total_rate = total_amount,
        total_amount = total_amount * 1.12 -- Including 12% tax
    WHERE reservation_id = reservation_uuid;

    RETURN reservation_uuid;
END;
$$ LANGUAGE plpgsql;

-- Function to process guest check-in
CREATE OR REPLACE FUNCTION process_guest_check_in(reservation_room_uuid UUID)
RETURNS BOOLEAN AS $$
DECLARE
    reservation_room_record reservation_rooms%ROWTYPE;
    room_record rooms%ROWTYPE;
BEGIN
    -- Get reservation room details
    SELECT * INTO reservation_room_record
    FROM reservation_rooms WHERE reservation_room_id = reservation_room_uuid;

    -- Get room details
    SELECT * INTO room_record FROM rooms WHERE room_id = reservation_room_record.room_id;

    -- Validate check-in
    IF reservation_room_record.check_in_date != CURRENT_DATE THEN
        RAISE EXCEPTION 'Check-in date does not match current date';
    END IF;

    IF room_record.room_status != 'available' THEN
        RAISE EXCEPTION 'Room is not available for check-in';
    END IF;

    -- Update room status
    UPDATE rooms SET room_status = 'occupied' WHERE room_id = room_record.room_id;

    -- Update reservation room
    UPDATE reservation_rooms SET
        room_status = 'checked_in',
        actual_check_in_time = CURRENT_TIMESTAMP
    WHERE reservation_room_id = reservation_room_uuid;

    -- Create in-house guest record
    INSERT INTO in_house_guests (
        reservation_room_id,
        guest_name,
        key_card_number,
        safe_combination
    ) VALUES (
        reservation_room_uuid,
        reservation_room_record.primary_guest_name,
        generate_key_card_number(),
        generate_safe_combination()
    );

    -- Create folio
    INSERT INTO folios (reservation_room_id, folio_number)
    VALUES (reservation_room_uuid, 'FOLIO-' || UPPER(SUBSTRING(uuid_generate_v4()::TEXT, 1, 8))));

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to process guest check-out
CREATE OR REPLACE FUNCTION process_guest_check_out(reservation_room_uuid UUID)
RETURNS DECIMAL AS $$
DECLARE
    folio_record folios%ROWTYPE;
    outstanding_balance DECIMAL;
BEGIN
    -- Get folio for the reservation room
    SELECT * INTO folio_record FROM folios WHERE reservation_room_id = reservation_room_uuid;

    -- Calculate final charges
    outstanding_balance := folio_record.outstanding_balance;

    -- Update reservation room
    UPDATE reservation_rooms SET
        room_status = 'checked_out',
        actual_check_out_time = CURRENT_TIMESTAMP
    WHERE reservation_room_id = reservation_room_uuid;

    -- Update room status
    UPDATE rooms SET
        room_status = 'available',
        housekeeping_status = 'dirty'
    WHERE room_id = (SELECT room_id FROM reservation_rooms WHERE reservation_room_id = reservation_room_uuid);

    -- Update in-house guest
    UPDATE in_house_guests SET
        guest_status = 'checked_out',
        actual_check_out_time = CURRENT_TIMESTAMP
    WHERE reservation_room_id = reservation_room_uuid;

    -- Close folio
    UPDATE folios SET folio_status = 'closed' WHERE folio_id = folio_record.folio_id;

    RETURN outstanding_balance;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample property
INSERT INTO properties (
    property_code, property_name, property_type, star_rating,
    address, total_rooms, check_in_time, check_out_time
) VALUES (
    'HTL001', 'Grand Hotel Resort', 'resort', 4,
    '{"street": "123 Ocean Drive", "city": "Miami Beach", "state": "FL", "zip": "33139"}',
    250, '15:00', '11:00'
);

-- Insert sample rooms
INSERT INTO rooms (property_id, room_number, room_type, floor_number, base_rate) VALUES
((SELECT property_id FROM properties WHERE property_code = 'HTL001' LIMIT 1), '101', 'standard', 1, 199.00),
((SELECT property_id FROM properties WHERE property_code = 'HTL001' LIMIT 1), '102', 'deluxe', 1, 299.00);

-- Insert sample guest
INSERT INTO guests (guest_number, first_name, last_name, email, phone) VALUES
('GST001', 'John', 'Smith', 'john.smith@email.com', '+1-555-0123');

-- Insert sample reservation
INSERT INTO reservations (
    reservation_number, guest_id, guest_first_name, guest_last_name,
    guest_email, property_id, check_in_date, check_out_date,
    total_amount
) VALUES (
    'RSV-001234', (SELECT guest_id FROM guests WHERE guest_number = 'GST001' LIMIT 1),
    'John', 'Smith', 'john.smith@email.com',
    (SELECT property_id FROM properties WHERE property_code = 'HTL001' LIMIT 1),
    '2024-01-15', '2024-01-17', 598.00
);

-- This hospitality schema provides comprehensive infrastructure for hotel operations,
-- reservation management, guest services, and property management.
