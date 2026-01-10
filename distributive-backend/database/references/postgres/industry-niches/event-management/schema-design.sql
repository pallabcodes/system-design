-- Event Management Database Schema
-- Comprehensive schema for event planning, ticketing, venue management, and event operations

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- VENUE AND FACILITY MANAGEMENT
-- ===========================================

CREATE TABLE venues (
    venue_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    venue_name VARCHAR(255) NOT NULL,
    venue_code VARCHAR(20) UNIQUE NOT NULL,

    -- Location and Contact
    address JSONB NOT NULL,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Venue Details
    venue_type VARCHAR(50) CHECK (venue_type IN (
        'conference_center', 'hotel', 'stadium', 'arena', 'theater',
        'outdoor_venue', 'museum', 'gallery', 'restaurant', 'park',
        'corporate_office', 'university', 'church', 'community_center'
    )),
    capacity INTEGER,
    indoor_outdoor VARCHAR(20) CHECK (indoor_outdoor IN ('indoor', 'outdoor', 'mixed')),

    -- Facilities and Amenities
    amenities JSONB DEFAULT '[]', -- WiFi, AV equipment, catering, parking, etc.
    accessibility_features JSONB DEFAULT '[]', -- ADA compliance, elevators, etc.

    -- Operational Details
    operating_hours JSONB DEFAULT '{}', -- Hours of operation by day
    maintenance_schedule JSONB DEFAULT '[]', -- Regular maintenance windows
    noise_restrictions TEXT,

    -- Pricing and Availability
    base_rental_rate DECIMAL(8,2),
    peak_season_multiplier DECIMAL(3,2) DEFAULT 1.0,
    minimum_booking_hours INTEGER DEFAULT 4,

    -- Contact and Management
    primary_contact_name VARCHAR(100),
    primary_contact_email VARCHAR(255),
    primary_contact_phone VARCHAR(20),
    venue_manager VARCHAR(100),

    -- Status and Compliance
    venue_status VARCHAR(20) DEFAULT 'active' CHECK (venue_status IN ('active', 'inactive', 'under_maintenance', 'closed')),
    insurance_requirements TEXT,
    liability_coverage DECIMAL(10,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE venue_spaces (
    space_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    venue_id UUID NOT NULL REFERENCES venues(venue_id),

    -- Space Details
    space_name VARCHAR(100) NOT NULL,
    space_code VARCHAR(20) UNIQUE NOT NULL,
    space_type VARCHAR(50) CHECK (space_type IN (
        'ballroom', 'conference_room', 'auditorium', 'exhibit_hall',
        'theater', 'classroom', 'lounge', 'foyer', 'outdoor_space',
        'parking_lot', 'kitchen', 'storage'
    )),

    -- Capacity and Layout
    capacity INTEGER,
    square_footage INTEGER,
    ceiling_height_feet DECIMAL(4,1),
    layout_options JSONB DEFAULT '[]', -- Theater, classroom, reception, etc.

    -- Equipment and Setup
    built_in_av JSONB DEFAULT '[]', -- Projectors, sound systems, etc.
    allowed_equipment JSONB DEFAULT '[]', -- What can be brought in
    setup_restrictions TEXT,

    -- Pricing
    base_rate_per_hour DECIMAL(6,2),
    minimum_hours INTEGER DEFAULT 2,
    overtime_rate DECIMAL(6,2),

    -- Availability
    default_availability JSONB DEFAULT '{}', -- Default available hours
    blackout_dates JSONB DEFAULT '[]', -- Dates when space is unavailable

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- EVENT PLANNING AND MANAGEMENT
-- ===========================================

CREATE TABLE events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_name VARCHAR(255) NOT NULL,
    event_code VARCHAR(20) UNIQUE NOT NULL,

    -- Event Classification
    event_type VARCHAR(50) CHECK (event_type IN (
        'conference', 'concert', 'wedding', 'corporate_meeting',
        'trade_show', 'fundraiser', 'sports_event', 'festival',
        'workshop', 'seminar', 'networking', 'celebration',
        'product_launch', 'award_ceremony', 'graduation', 'retirement'
    )),
    event_category VARCHAR(50),
    target_audience VARCHAR(100),

    -- Event Details
    description TEXT,
    tagline VARCHAR(200),
    theme VARCHAR(100),

    -- Timing and Duration
    start_date DATE NOT NULL,
    end_date DATE,
    start_time TIME,
    end_time TIME,
    timezone VARCHAR(50) DEFAULT 'UTC',
    duration_hours DECIMAL(6,2) GENERATED ALWAYS AS (
        CASE WHEN end_date > start_date THEN
            EXTRACT(EPOCH FROM ((end_date + end_time) - (start_date + start_time))) / 3600
        ELSE
            EXTRACT(EPOCH FROM (end_time - start_time)) / 3600
        END
    ) STORED,

    -- Venue and Location
    venue_id UUID REFERENCES venues(venue_id),
    custom_location JSONB, -- For non-venue events
    virtual_event BOOLEAN DEFAULT FALSE,
    hybrid_event BOOLEAN DEFAULT FALSE,

    -- Capacity and Attendance
    expected_attendance INTEGER,
    maximum_capacity INTEGER,
    minimum_attendance INTEGER,

    -- Event Management
    event_status VARCHAR(30) CHECK (event_status IN (
        'planning', 'confirmed', 'in_progress', 'completed', 'cancelled',
        'postponed', 'rescheduled', 'sold_out', 'on_hold'
    )),
    event_priority VARCHAR(10) CHECK (event_priority IN ('low', 'medium', 'high', 'critical')),

    -- Budget and Financial
    total_budget DECIMAL(10,2),
    projected_revenue DECIMAL(10,2),
    actual_cost DECIMAL(10,2),
    actual_revenue DECIMAL(10,2),

    -- Team and Organization
    organizer_id UUID, -- References user/organizer
    event_team JSONB DEFAULT '[]', -- Team members and roles
    sponsoring_organization VARCHAR(255),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (start_date <= end_date OR end_date IS NULL),
    CHECK (maximum_capacity >= expected_attendance OR maximum_capacity IS NULL)
);

CREATE TABLE event_sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,

    -- Session Details
    session_name VARCHAR(255) NOT NULL,
    session_code VARCHAR(10) UNIQUE NOT NULL,
    session_description TEXT,

    -- Session Type and Format
    session_type VARCHAR(50) CHECK (session_type IN (
        'keynote', 'breakout', 'workshop', 'panel', 'networking',
        'exhibition', 'meal', 'reception', 'ceremony', 'performance'
    )),
    session_format VARCHAR(30) CHECK (session_format IN ('presentation', 'discussion', 'interactive', 'demonstration')),

    -- Timing
    session_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    duration_minutes INTEGER GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (end_time - start_time)) / 60
    ) STORED,

    -- Location and Setup
    venue_space_id UUID REFERENCES venue_spaces(space_id),
    room_setup VARCHAR(50) CHECK (room_setup IN ('theater', 'classroom', 'roundtable', 'reception', 'exhibit')),
    av_requirements JSONB DEFAULT '[]',

    -- Capacity and Registration
    max_capacity INTEGER,
    min_capacity INTEGER,
    registration_required BOOLEAN DEFAULT TRUE,

    -- Content and Speakers
    speaker_id UUID, -- References speaker/presenter
    session_materials JSONB DEFAULT '[]', -- Presentations, handouts, etc.

    -- Status
    session_status VARCHAR(20) DEFAULT 'scheduled' CHECK (session_status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (start_time < end_time)
);

-- ===========================================
-- REGISTRATION AND TICKETING
-- ===========================================

CREATE TABLE ticket_types (
    ticket_type_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,

    -- Ticket Details
    ticket_name VARCHAR(100) NOT NULL,
    ticket_code VARCHAR(20) UNIQUE NOT NULL,
    ticket_description TEXT,

    -- Pricing and Availability
    base_price DECIMAL(8,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    quantity_available INTEGER,
    quantity_sold INTEGER DEFAULT 0,

    -- Sales Periods
    sales_start_date DATE,
    sales_end_date DATE,
    early_bird_deadline DATE,
    early_bird_discount DECIMAL(5,2), -- Percentage discount

    -- Access and Benefits
    access_level VARCHAR(30) CHECK (access_level IN ('standard', 'vip', 'premium', 'platinum', 'speaker', 'staff', 'sponsor')),
    included_sessions JSONB DEFAULT '[]', -- Which sessions this ticket includes
    perks JSONB DEFAULT '[]', -- Additional benefits

    -- Status and Sales
    ticket_status VARCHAR(20) DEFAULT 'active' CHECK (ticket_status IN ('active', 'inactive', 'sold_out', 'cancelled')),
    display_order INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (base_price >= 0),
    CHECK (quantity_sold <= quantity_available OR quantity_available IS NULL)
);

CREATE TABLE registrations (
    registration_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,

    -- Registrant Information
    registrant_type VARCHAR(20) CHECK (registrant_type IN ('individual', 'group', 'organization')),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    organization_name VARCHAR(255),
    title VARCHAR(100),

    -- Contact Information
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    address JSONB,

    -- Registration Details
    registration_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ticket_type_id UUID REFERENCES ticket_types(ticket_type_id),
    quantity INTEGER DEFAULT 1,

    -- Payment and Pricing
    unit_price DECIMAL(8,2),
    total_amount DECIMAL(8,2),
    discount_applied DECIMAL(8,2) DEFAULT 0,
    final_amount DECIMAL(8,2) GENERATED ALWAYS AS (total_amount - discount_applied) STORED,

    -- Payment Processing
    payment_status VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'processing', 'completed', 'failed', 'refunded', 'cancelled')),
    payment_method VARCHAR(30),
    transaction_id VARCHAR(100),

    -- Registration Status
    registration_status VARCHAR(20) DEFAULT 'confirmed' CHECK (registration_status IN (
        'pending', 'confirmed', 'cancelled', 'no_show', 'attended', 'transferred'
    )),
    checked_in BOOLEAN DEFAULT FALSE,
    check_in_time TIMESTAMP WITH TIME ZONE,

    -- Special Requirements
    dietary_restrictions TEXT,
    accessibility_needs TEXT,
    special_requests TEXT,

    -- Marketing and Tracking
    referral_source VARCHAR(100),
    marketing_opt_in BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity > 0),
    CHECK (final_amount >= 0)
);

CREATE TABLE waitlists (
    waitlist_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    ticket_type_id UUID REFERENCES ticket_types(ticket_type_id),

    -- Waitlist Details
    email VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(20),

    -- Waitlist Position
    position INTEGER,
    waitlist_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Status and Notifications
    notification_sent BOOLEAN DEFAULT FALSE,
    notification_date TIMESTAMP WITH TIME ZONE,
    converted_to_registration BOOLEAN DEFAULT FALSE,
    registration_id UUID REFERENCES registrations(registration_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SPEAKERS AND PRESENTERS
-- ===========================================

CREATE TABLE speakers (
    speaker_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    speaker_name VARCHAR(255) NOT NULL,
    speaker_code VARCHAR(10) UNIQUE NOT NULL,

    -- Speaker Profile
    title VARCHAR(100),
    organization VARCHAR(255),
    bio TEXT,
    photo_url VARCHAR(500),

    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(20),
    website VARCHAR(500),
    social_media JSONB DEFAULT '{}',

    -- Expertise and Topics
    expertise_areas TEXT[],
    presentation_topics JSONB DEFAULT '[]',
    languages_spoken TEXT[] DEFAULT ARRAY['English'],

    -- Speaker Details
    speaker_type VARCHAR(30) CHECK (speaker_type IN ('keynote', 'breakout', 'workshop', 'panelist', 'moderator', 'performer')),
    fee_structure VARCHAR(30) CHECK (fee_structure IN ('complimentary', 'honorarium', 'paid', 'travel_only')),
    standard_fee DECIMAL(8,2),

    -- Availability and Preferences
    availability_notes TEXT,
    travel_requirements TEXT,
    technical_requirements JSONB DEFAULT '[]',

    -- Performance History
    past_presentations JSONB DEFAULT '[]',
    rating DECIMAL(3,1), -- Average rating out of 5
    total_presentations INTEGER DEFAULT 0,

    -- Status
    speaker_status VARCHAR(20) DEFAULT 'active' CHECK (speaker_status IN ('active', 'inactive', 'retired')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE speaker_assignments (
    assignment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    speaker_id UUID NOT NULL REFERENCES speakers(speaker_id),
    session_id UUID NOT NULL REFERENCES event_sessions(session_id),

    -- Assignment Details
    role VARCHAR(30) CHECK (role IN ('primary_speaker', 'co_presenter', 'moderator', 'panelist', 'keynote')),
    speaking_order INTEGER,
    speaking_time_minutes INTEGER,

    -- Compensation
    fee_amount DECIMAL(8,2),
    travel_expenses DECIMAL(8,2),
    accommodation_expenses DECIMAL(8,2),

    -- Status and Confirmation
    assignment_status VARCHAR(20) DEFAULT 'invited' CHECK (assignment_status IN ('invited', 'confirmed', 'declined', 'cancelled')),
    invitation_date DATE,
    response_date DATE,
    contract_signed BOOLEAN DEFAULT FALSE,

    -- Materials and Preparation
    presentation_submitted BOOLEAN DEFAULT FALSE,
    materials_deadline DATE,
    rehearsal_required BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- VENDORS AND SUPPLIERS
-- ===========================================

CREATE TABLE vendors (
    vendor_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vendor_name VARCHAR(255) NOT NULL,
    vendor_code VARCHAR(10) UNIQUE NOT NULL,

    -- Vendor Classification
    vendor_type VARCHAR(50) CHECK (vendor_type IN (
        'catering', 'av_equipment', 'decor', 'entertainment', 'photography',
        'transportation', 'security', 'registration', 'printing', 'florists'
    )),
    specialty_services TEXT[],

    -- Business Information
    contact_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(20),
    website VARCHAR(500),

    -- Service Area and Availability
    service_areas TEXT[], -- Geographic areas served
    availability_calendar JSONB DEFAULT '{}',

    -- Pricing and Terms
    standard_rates JSONB DEFAULT '{}',
    minimum_notice_hours INTEGER,
    cancellation_policy TEXT,

    -- Performance and Reliability
    rating DECIMAL(3,1), -- Average rating out of 5
    total_events INTEGER DEFAULT 0,
    on_time_delivery_rate DECIMAL(5,2),

    -- Contracts and Insurance
    insurance_coverage DECIMAL(10,2),
    contract_terms TEXT,
    payment_terms VARCHAR(50),

    -- Status
    vendor_status VARCHAR(20) DEFAULT 'active' CHECK (vendor_status IN ('active', 'inactive', 'blacklisted')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE vendor_contracts (
    contract_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id),
    vendor_id UUID NOT NULL REFERENCES vendors(vendor_id),

    -- Contract Details
    service_description TEXT,
    contract_amount DECIMAL(8,2),
    payment_schedule JSONB DEFAULT '[]',

    -- Terms and Conditions
    start_date DATE,
    end_date DATE,
    deliverables JSONB DEFAULT '[]',
    performance_standards TEXT,

    -- Status and Execution
    contract_status VARCHAR(20) DEFAULT 'draft' CHECK (contract_status IN ('draft', 'signed', 'active', 'completed', 'terminated')),
    signed_date DATE,
    deposit_paid DECIMAL(8,2) DEFAULT 0,

    -- Quality and Performance
    quality_rating INTEGER CHECK (quality_rating BETWEEN 1 AND 5),
    performance_notes TEXT,
    issues_encountered TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (event_id, vendor_id)
);

-- ===========================================
-- SPONSORSHIP AND EXHIBITION MANAGEMENT
-- ===========================================

CREATE TABLE sponsorship_levels (
    level_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,

    -- Level Details
    level_name VARCHAR(100) NOT NULL,
    level_code VARCHAR(20) UNIQUE NOT NULL,

    -- Benefits and Pricing
    sponsorship_fee DECIMAL(8,2) NOT NULL,
    max_sponsors INTEGER,
    current_sponsors INTEGER DEFAULT 0,

    -- Benefits Package
    benefits JSONB DEFAULT '[]', -- Logo placement, speaking slots, booth space, etc.
    booth_space_sqft INTEGER,
    speaking_opportunities INTEGER,

    -- Visibility and Branding
    logo_placement JSONB DEFAULT '[]', -- Website, signage, programs, etc.
    marketing_credits DECIMAL(6,2), -- Social media promotion value

    -- Status
    level_status VARCHAR(20) DEFAULT 'active' CHECK (level_status IN ('active', 'inactive', 'sold_out')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (current_sponsors <= max_sponsors OR max_sponsors IS NULL)
);

CREATE TABLE sponsors (
    sponsor_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sponsor_name VARCHAR(255) NOT NULL,
    sponsor_code VARCHAR(10) UNIQUE NOT NULL,

    -- Company Information
    industry VARCHAR(50),
    company_size VARCHAR(20) CHECK (company_size IN ('startup', 'small', 'medium', 'large', 'enterprise')),
    website VARCHAR(500),

    -- Contact Information
    primary_contact_name VARCHAR(100),
    primary_contact_email VARCHAR(255),
    primary_contact_phone VARCHAR(20),

    -- Marketing Assets
    logo_url VARCHAR(500),
    brand_colors JSONB DEFAULT '[]',
    marketing_materials JSONB DEFAULT '[]',

    -- Sponsorship History
    total_events_sponsored INTEGER DEFAULT 0,
    avg_sponsorship_amount DECIMAL(8,2),
    preferred_sponsorship_levels TEXT[],

    -- Status
    sponsor_status VARCHAR(20) DEFAULT 'active' CHECK (sponsor_status IN ('active', 'inactive', 'prospect')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE event_sponsorships (
    sponsorship_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id),
    sponsor_id UUID NOT NULL REFERENCES sponsors(sponsor_id),
    level_id UUID NOT NULL REFERENCES sponsorship_levels(level_id),

    -- Sponsorship Details
    sponsorship_amount DECIMAL(8,2) NOT NULL,
    payment_status VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'overdue', 'cancelled')),

    -- Benefits Utilization
    benefits_claimed JSONB DEFAULT '[]',
    booth_assigned VARCHAR(50),
    speaking_slot_assigned VARCHAR(100),

    -- Status and Fulfillment
    sponsorship_status VARCHAR(20) DEFAULT 'confirmed' CHECK (sponsorship_status IN ('confirmed', 'active', 'fulfilled', 'cancelled')),
    activation_date DATE,
    fulfillment_deadline DATE,

    -- Performance and ROI
    leads_generated INTEGER DEFAULT 0,
    brand_impressions INTEGER DEFAULT 0,
    roi_measurement TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (event_id, sponsor_id)
);

-- ===========================================
-- FINANCIAL AND EXPENSE MANAGEMENT
-- ===========================================

CREATE TABLE event_expenses (
    expense_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,

    -- Expense Details
    expense_category VARCHAR(50) CHECK (expense_category IN (
        'venue', 'catering', 'av_equipment', 'decor', 'entertainment',
        'marketing', 'staff', 'insurance', 'permits', 'transportation',
        'printing', 'speaker_fees', 'contingency', 'other'
    )),
    expense_description VARCHAR(255),
    vendor_id UUID REFERENCES vendors(vendor_id),

    -- Financial Details
    estimated_amount DECIMAL(8,2),
    actual_amount DECIMAL(8,2),
    currency_code CHAR(3) DEFAULT 'USD',

    -- Payment Information
    payment_date DATE,
    payment_method VARCHAR(30),
    invoice_number VARCHAR(50),

    -- Budget and Approval
    budget_category VARCHAR(50),
    approved_by VARCHAR(100),
    approval_date DATE,

    -- Status
    expense_status VARCHAR(20) DEFAULT 'estimated' CHECK (expense_status IN ('estimated', 'approved', 'incurred', 'paid', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (actual_amount >= 0 OR actual_amount IS NULL)
);

CREATE TABLE event_revenue (
    revenue_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,

    -- Revenue Details
    revenue_source VARCHAR(50) CHECK (revenue_source IN (
        'ticket_sales', 'sponsorships', 'exhibitions', 'catering',
        'merchandise', 'parking', 'donations', 'grants', 'other'
    )),
    revenue_description VARCHAR(255),

    -- Financial Details
    amount DECIMAL(8,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    transaction_date DATE DEFAULT CURRENT_DATE,

    -- Revenue Attribution
    ticket_type_id UUID REFERENCES ticket_types(ticket_type_id),
    sponsorship_id UUID REFERENCES event_sponsorships(sponsorship_id),

    -- Status and Reconciliation
    revenue_status VARCHAR(20) DEFAULT 'received' CHECK (revenue_status IN ('projected', 'received', 'deposited', 'refunded')),
    reconciled BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (amount > 0)
);

-- ===========================================
-- ATTENDANCE AND ENGAGEMENT TRACKING
-- ===========================================

CREATE TABLE attendance_tracking (
    tracking_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    registration_id UUID NOT NULL REFERENCES registrations(registration_id),

    -- Tracking Details
    session_id UUID REFERENCES event_sessions(session_id),
    check_in_time TIMESTAMP WITH TIME ZONE,
    check_out_time TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER GENERATED ALWAYS AS (
        CASE WHEN check_out_time IS NOT NULL AND check_in_time IS NOT NULL
             THEN EXTRACT(EPOCH FROM (check_out_time - check_in_time)) / 60
             ELSE NULL END
    ) STORED,

    -- Engagement Metrics
    interactions_count INTEGER DEFAULT 0,
    materials_downloaded JSONB DEFAULT '[]',
    networking_connections INTEGER DEFAULT 0,

    -- Location Tracking (for large venues)
    location_coordinates JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE feedback (
    feedback_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID REFERENCES events(event_id),
    session_id UUID REFERENCES event_sessions(session_id),
    registration_id UUID REFERENCES registrations(registration_id),

    -- Feedback Details
    feedback_type VARCHAR(30) CHECK (feedback_type IN ('event_overall', 'session_specific', 'speaker_rating', 'venue_feedback')),
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),

    -- Response Details
    feedback_text TEXT,
    submission_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Respondent Information
    respondent_type VARCHAR(20) CHECK (respondent_type IN ('attendee', 'speaker', 'staff', 'sponsor')),
    anonymous BOOLEAN DEFAULT FALSE,

    -- Follow-up
    follow_up_required BOOLEAN DEFAULT FALSE,
    follow_up_notes TEXT,
    follow_up_completed BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

CREATE TABLE event_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(event_id),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_period VARCHAR(10) CHECK (report_period IN ('daily', 'weekly', 'event_total')),

    -- Attendance Metrics
    registered_attendees INTEGER DEFAULT 0,
    actual_attendees INTEGER DEFAULT 0,
    attendance_rate DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN registered_attendees > 0 THEN (actual_attendees::DECIMAL / registered_attendees) * 100 ELSE 0 END
    ) STORED,

    -- Registration Analytics
    registrations_by_type JSONB DEFAULT '{}',
    registration_trends JSONB DEFAULT '[]',
    conversion_funnel JSONB DEFAULT '{}',

    -- Engagement Metrics
    session_attendance JSONB DEFAULT '{}',
    average_session_duration DECIMAL(5,2),
    networking_interactions INTEGER DEFAULT 0,

    -- Financial Performance
    revenue_actual DECIMAL(10,2),
    expenses_actual DECIMAL(10,2),
    profit_loss DECIMAL(10,2) GENERATED ALWAYS AS (revenue_actual - expenses_actual) STORED,

    -- Marketing Effectiveness
    referral_sources JSONB DEFAULT '{}',
    marketing_roi DECIMAL(5,2),
    social_media_engagement JSONB DEFAULT '{}',

    -- Operational Metrics
    on_time_sessions DECIMAL(5,2), -- Percentage
    vendor_performance_ratings JSONB DEFAULT '{}',
    issues_reported INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (event_id, report_date, report_period)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Event and venue indexes
CREATE INDEX idx_events_date_status ON events (start_date DESC, event_status);
CREATE INDEX idx_events_venue ON events (venue_id, start_date);
CREATE INDEX idx_event_sessions_event ON event_sessions (event_id, session_date);
CREATE INDEX idx_venues_location ON venues USING gist (st_makepoint(longitude, latitude));

-- Registration and ticketing indexes
CREATE INDEX idx_registrations_event ON registrations (event_id, registration_date DESC);
CREATE INDEX idx_registrations_email ON registrations (email);
CREATE INDEX idx_ticket_types_event ON ticket_types (event_id, ticket_status);
CREATE INDEX idx_waitlists_event ON waitlists (event_id, position);

-- Speaker and vendor indexes
CREATE INDEX idx_speakers_type ON speakers (speaker_type, rating DESC);
CREATE INDEX idx_speaker_assignments_session ON speaker_assignments (session_id, role);
CREATE INDEX idx_vendors_type ON vendors (vendor_type, rating DESC);
CREATE INDEX idx_vendor_contracts_event ON vendor_contracts (event_id, contract_status);

-- Sponsorship indexes
CREATE INDEX idx_sponsorship_levels_event ON sponsorship_levels (event_id, level_status);
CREATE INDEX idx_event_sponsorships_event ON event_sponsorships (event_id, sponsorship_status);

-- Financial indexes
CREATE INDEX idx_event_expenses_event ON event_expenses (event_id, expense_date DESC);
CREATE INDEX idx_event_revenue_event ON event_revenue (event_id, transaction_date DESC);

-- Tracking and analytics indexes
CREATE INDEX idx_attendance_tracking_session ON attendance_tracking (session_id, check_in_time);
CREATE INDEX idx_feedback_event ON feedback (event_id, rating);
CREATE INDEX idx_event_analytics_event ON event_analytics (event_id, report_date DESC);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Event dashboard overview
CREATE VIEW event_dashboard AS
SELECT
    e.event_id,
    e.event_name,
    e.event_type,
    e.start_date,
    e.event_status,

    -- Registration and attendance
    COUNT(r.registration_id) as total_registrations,
    COUNT(CASE WHEN r.registration_status = 'confirmed' THEN 1 END) as confirmed_registrations,
    COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END) as checked_in_attendees,

    -- Revenue and expenses
    COALESCE(SUM(er.amount), 0) as total_revenue,
    COALESCE(SUM(ee.actual_amount), 0) as total_expenses,
    COALESCE(SUM(er.amount - ee.actual_amount), 0) as current_profit_loss,

    -- Event health indicators
    ROUND(
        COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END)::DECIMAL /
        COUNT(r.registration_id) * 100, 1
    ) as attendance_rate,

    CASE
        WHEN e.maximum_capacity IS NOT NULL AND COUNT(r.registration_id) >= e.maximum_capacity * 0.9 THEN 'near_capacity'
        WHEN COUNT(r.registration_id) >= e.expected_attendance THEN 'on_track'
        WHEN COUNT(r.registration_id) >= e.expected_attendance * 0.8 THEN 'below_expectations'
        ELSE 'needs_attention'
    END as registration_health,

    -- Recent activity
    MAX(r.registration_date) as last_registration,
    MAX(at.check_in_time) as last_check_in,

    -- Critical deadlines
    e.start_date - INTERVAL '7 days' as final_prep_deadline,
    CASE WHEN e.start_date < CURRENT_DATE + INTERVAL '7 days' THEN TRUE ELSE FALSE END as urgent_attention_needed

FROM events e
LEFT JOIN registrations r ON e.event_id = r.event_id
LEFT JOIN event_revenue er ON e.event_id = er.event_id
LEFT JOIN event_expenses ee ON e.event_id = ee.event_id
LEFT JOIN attendance_tracking at ON r.registration_id = at.registration_id
WHERE e.event_status NOT IN ('completed', 'cancelled')
GROUP BY e.event_id, e.event_name, e.event_type, e.start_date, e.event_status,
         e.maximum_capacity, e.expected_attendance;

-- Venue utilization analysis
CREATE VIEW venue_utilization AS
SELECT
    v.venue_id,
    v.venue_name,
    v.venue_type,

    -- Booking metrics
    COUNT(e.event_id) as total_events_hosted,
    COUNT(CASE WHEN e.event_status = 'completed' THEN 1 END) as completed_events,
    ROUND(
        COUNT(CASE WHEN e.event_status = 'completed' THEN 1 END)::DECIMAL /
        COUNT(e.event_id) * 100, 1
    ) as completion_rate,

    -- Revenue analysis
    COALESCE(SUM(e.actual_revenue), 0) as total_revenue_generated,
    COALESCE(AVG(e.actual_revenue), 0) as avg_event_revenue,
    COALESCE(SUM(e.actual_revenue) / COUNT(e.event_id), 0) as revenue_per_event,

    -- Utilization by space
    COUNT(DISTINCT es.venue_space_id) as spaces_utilized,
    jsonb_object_agg(
        COALESCE(vs.space_name, 'Main Venue'),
        COUNT(DISTINCT es.session_id)
    ) FILTER (WHERE vs.space_name IS NOT NULL) as space_usage_breakdown,

    -- Event type distribution
    jsonb_object_agg(
        e.event_type,
        COUNT(*)
    ) as event_type_distribution,

    -- Seasonal patterns
    COUNT(CASE WHEN EXTRACT(MONTH FROM e.start_date) IN (12,1,2) THEN 1 END) as winter_events,
    COUNT(CASE WHEN EXTRACT(MONTH FROM e.start_date) IN (3,4,5) THEN 1 END) as spring_events,
    COUNT(CASE WHEN EXTRACT(MONTH FROM e.start_date) IN (6,7,8) THEN 1 END) as summer_events,
    COUNT(CASE WHEN EXTRACT(MONTH FROM e.start_date) IN (9,10,11) THEN 1 END) as fall_events,

    -- Performance ratings
    ROUND(AVG(f.rating), 1) as avg_venue_rating,
    COUNT(CASE WHEN f.rating >= 4 THEN 1 END)::DECIMAL /
    COUNT(f.feedback_id) * 100 as satisfaction_rate

FROM venues v
LEFT JOIN events e ON v.venue_id = e.venue_id
    AND e.start_date >= CURRENT_DATE - INTERVAL '1 year'
LEFT JOIN event_sessions es ON e.event_id = es.event_id
LEFT JOIN venue_spaces vs ON es.venue_space_id = vs.space_id
LEFT JOIN feedback f ON e.event_id = f.event_id
    AND f.feedback_type = 'venue_feedback'
GROUP BY v.venue_id, v.venue_name, v.venue_type;

-- Financial performance analysis
CREATE VIEW event_financial_performance AS
SELECT
    e.event_id,
    e.event_name,
    e.event_type,
    e.start_date,

    -- Budget vs actual
    e.total_budget,
    COALESCE(SUM(er.amount), 0) as actual_revenue,
    COALESCE(SUM(ee.actual_amount), 0) as actual_expenses,
    COALESCE(SUM(er.amount - ee.actual_amount), 0) as actual_profit,

    -- Budget performance
    ROUND(
        COALESCE(SUM(er.amount), 0) / NULLIF(e.total_budget, 0) * 100, 1
    ) as budget_attainment_percentage,

    CASE
        WHEN COALESCE(SUM(er.amount - ee.actual_amount), 0) > e.total_budget * 0.1 THEN 'exceeded_expectations'
        WHEN COALESCE(SUM(er.amount - ee.actual_amount), 0) > 0 THEN 'met_expectations'
        WHEN COALESCE(SUM(er.amount - ee.actual_amount), 0) > e.total_budget * -0.1 THEN 'below_expectations'
        ELSE 'significant_shortfall'
    END as financial_performance_rating,

    -- Revenue breakdown by source
    jsonb_object_agg(
        COALESCE(er.revenue_source, 'unknown'),
        SUM(er.amount)
    ) as revenue_by_source,

    -- Expense breakdown by category
    jsonb_object_agg(
        COALESCE(ee.expense_category, 'unknown'),
        SUM(ee.actual_amount)
    ) as expenses_by_category,

    -- Key financial ratios
    CASE WHEN COALESCE(SUM(ee.actual_amount), 0) > 0
         THEN ROUND(COALESCE(SUM(er.amount), 0) / SUM(ee.actual_amount) * 100, 1)
         ELSE 0 END as revenue_to_expense_ratio,

    CASE WHEN COALESCE(SUM(er.amount), 0) > 0
         THEN ROUND(COALESCE(SUM(er.amount - ee.actual_amount), 0) / SUM(er.amount) * 100, 1)
         ELSE 0 END as profit_margin_percentage,

    -- Registration and attendance impact
    COUNT(r.registration_id) as total_registrations,
    ROUND(
        COALESCE(SUM(er.amount), 0) / NULLIF(COUNT(r.registration_id), 0), 2
    ) as revenue_per_registration,

    -- Sponsorship performance
    COUNT(es.sponsorship_id) as total_sponsors,
    COALESCE(SUM(es.sponsorship_amount), 0) as total_sponsorship_revenue,
    ROUND(
        COALESCE(SUM(es.sponsorship_amount), 0) / NULLIF(COALESCE(SUM(er.amount), 0), 0) * 100, 1
    ) as sponsorship_revenue_percentage

FROM events e
LEFT JOIN event_revenue er ON e.event_id = er.event_id
LEFT JOIN event_expenses ee ON e.event_id = ee.event_id
LEFT JOIN registrations r ON e.event_id = r.event_id
LEFT JOIN event_sponsorships es ON e.event_id = es.event_id
WHERE e.event_status = 'completed'
GROUP BY e.event_id, e.event_name, e.event_type, e.start_date, e.total_budget;

-- ===========================================
-- FUNCTIONS FOR EVENT OPERATIONS
-- =========================================--

-- Function to calculate event profitability
CREATE OR REPLACE FUNCTION calculate_event_profitability(event_uuid UUID)
RETURNS TABLE (
    event_name VARCHAR,
    total_revenue DECIMAL,
    total_expenses DECIMAL,
    net_profit DECIMAL,
    profit_margin DECIMAL,
    roi_percentage DECIMAL,
    breakeven_attendance INTEGER,
    actual_vs_breakeven VARCHAR
) AS $$
DECLARE
    event_record events%ROWTYPE;
    revenue_total DECIMAL := 0;
    expense_total DECIMAL := 0;
    ticket_revenue DECIMAL := 0;
    registration_count INTEGER := 0;
BEGIN
    -- Get event details
    SELECT * INTO event_record FROM events WHERE event_id = event_uuid;

    -- Calculate total revenue
    SELECT COALESCE(SUM(amount), 0) INTO revenue_total
    FROM event_revenue WHERE event_id = event_uuid;

    -- Calculate total expenses
    SELECT COALESCE(SUM(actual_amount), 0) INTO expense_total
    FROM event_expenses WHERE event_id = event_uuid;

    -- Calculate ticket revenue and attendance
    SELECT COALESCE(SUM(final_amount), 0), COUNT(*)
    INTO ticket_revenue, registration_count
    FROM registrations
    WHERE event_id = event_uuid AND registration_status = 'attended';

    RETURN QUERY SELECT
        event_record.event_name,
        revenue_total,
        expense_total,
        revenue_total - expense_total,
        CASE WHEN revenue_total > 0 THEN ((revenue_total - expense_total) / revenue_total) * 100 ELSE 0 END,
        CASE WHEN expense_total > 0 THEN ((revenue_total - expense_total) / expense_total) * 100 ELSE 0 END,
        CASE WHEN registration_count > 0 THEN CEIL(expense_total / (ticket_revenue / registration_count)) ELSE 0 END,
        CASE
            WHEN registration_count >= CEIL(expense_total / (ticket_revenue / registration_count)) THEN 'profitable'
            ELSE 'below_breakeven'
        END;
END;
$$ LANGUAGE plpgsql;

-- Function to generate event attendance reports
CREATE OR REPLACE FUNCTION generate_attendance_report(event_uuid UUID)
RETURNS TABLE (
    event_name VARCHAR,
    total_registered INTEGER,
    total_attended INTEGER,
    attendance_rate DECIMAL,
    no_show_count INTEGER,
    peak_attendance_time TIME,
    session_popularity JSONB,
    demographic_breakdown JSONB,
    satisfaction_score DECIMAL
) AS $$
DECLARE
    event_record events%ROWTYPE;
BEGIN
    -- Get event details
    SELECT * INTO event_record FROM events WHERE event_id = event_uuid;

    RETURN QUERY
    SELECT
        event_record.event_name,

        -- Registration and attendance totals
        COUNT(r.registration_id) as total_registered,
        COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END) as total_attended,
        ROUND(
            COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END)::DECIMAL /
            COUNT(r.registration_id) * 100, 1
        ) as attendance_rate,
        COUNT(CASE WHEN r.registration_status = 'no_show' THEN 1 END) as no_show_count,

        -- Peak attendance time (simplified - would need more complex analysis)
        (SELECT start_time FROM event_sessions WHERE event_id = event_uuid ORDER BY start_time LIMIT 1) as peak_attendance_time,

        -- Session popularity
        (SELECT jsonb_object_agg(
            COALESCE(es.session_name, 'Unknown Session'),
            COUNT(at.tracking_id)
        ) FROM event_sessions es
        LEFT JOIN attendance_tracking at ON es.session_id = at.session_id
        WHERE es.event_id = event_uuid) as session_popularity,

        -- Demographic breakdown (simplified)
        jsonb_build_object(
            'individual_registrants', COUNT(CASE WHEN r.registrant_type = 'individual' THEN 1 END),
            'organization_registrants', COUNT(CASE WHEN r.registrant_type = 'organization' THEN 1 END),
            'group_registrants', COUNT(CASE WHEN r.registrant_type = 'group' THEN 1 END)
        ) as demographic_breakdown,

        -- Average satisfaction score
        ROUND(AVG(f.rating), 1) as satisfaction_score

    FROM registrations r
    LEFT JOIN feedback f ON r.registration_id = f.registration_id
    WHERE r.event_id = event_uuid
    GROUP BY event_record.event_name;
END;
$$ LANGUAGE plpgsql;

-- Function to optimize ticket pricing
CREATE OR REPLACE FUNCTION optimize_ticket_pricing(event_uuid UUID)
RETURNS TABLE (
    ticket_type VARCHAR,
    current_price DECIMAL,
    optimal_price DECIMAL,
    price_elasticity DECIMAL,
    projected_demand INTEGER,
    projected_revenue DECIMAL,
    confidence_level VARCHAR
) AS $$
DECLARE
    ticket_record RECORD;
BEGIN
    FOR ticket_record IN
        SELECT
            tt.ticket_name,
            tt.base_price,
            tt.quantity_available,
            tt.quantity_sold,
            tt.ticket_type_id,

            -- Calculate demand metrics
            CASE WHEN tt.quantity_available > 0
                 THEN tt.quantity_sold::DECIMAL / tt.quantity_available
                 ELSE 0 END as sell_through_rate,

            -- Calculate average registration timing
            AVG(EXTRACT(EPOCH FROM (r.registration_date::DATE - e.start_date + INTERVAL '60 days')) / 86400) as avg_days_to_sell

        FROM ticket_types tt
        JOIN events e ON tt.event_id = e.event_id
        LEFT JOIN registrations r ON tt.ticket_type_id = r.ticket_type_id
        WHERE tt.event_id = event_uuid
        GROUP BY tt.ticket_type_id, tt.ticket_name, tt.base_price, tt.quantity_available, tt.quantity_sold
    LOOP
        RETURN QUERY SELECT
            ticket_record.ticket_name,
            ticket_record.base_price,

            -- Optimal price calculation (simplified demand-based pricing)
            CASE
                WHEN ticket_record.sell_through_rate > 0.8 THEN ticket_record.base_price * 1.15 -- Increase if selling fast
                WHEN ticket_record.sell_through_rate < 0.3 THEN ticket_record.base_price * 0.9  -- Decrease if selling slow
                ELSE ticket_record.base_price
            END as optimal_price,

            -- Price elasticity (simplified)
            CASE
                WHEN ticket_record.sell_through_rate > 0.8 THEN -1.2 -- Elastic - price sensitive
                WHEN ticket_record.sell_through_rate < 0.3 THEN -0.8  -- Inelastic - less price sensitive
                ELSE -1.0
            END as price_elasticity,

            -- Projected demand at optimal price
            CASE
                WHEN ticket_record.sell_through_rate > 0.8 THEN LEAST(ticket_record.quantity_available, ROUND(ticket_record.quantity_sold * 1.1))
                WHEN ticket_record.sell_through_rate < 0.3 THEN ROUND(ticket_record.quantity_sold * 0.9)
                ELSE ticket_record.quantity_sold
            END as projected_demand,

            -- Projected revenue
            CASE
                WHEN ticket_record.sell_through_rate > 0.8 THEN ROUND(ticket_record.quantity_available * ticket_record.base_price * 1.15)
                WHEN ticket_record.sell_through_rate < 0.3 THEN ROUND(ticket_record.quantity_sold * ticket_record.base_price * 0.9)
                ELSE ticket_record.quantity_sold * ticket_record.base_price
            END as projected_revenue,

            -- Confidence level
            CASE
                WHEN ticket_record.quantity_sold > 50 THEN 'high'
                WHEN ticket_record.quantity_sold > 20 THEN 'medium'
                ELSE 'low'
            END as confidence_level;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample venue
INSERT INTO venues (
    venue_name, venue_code, venue_type, address,
    capacity, operating_hours
) VALUES (
    'Grand Convention Center', 'GCC001', 'conference_center',
    '{"street": "123 Convention Blvd", "city": "Metropolis", "state": "NY", "zip": "10001"}',
    2000, '{"monday": {"open": "06:00", "close": "23:00"}, "friday": {"open": "06:00", "close": "02:00"}}'
);

-- Insert sample event
INSERT INTO events (
    event_name, event_code, event_type, start_date,
    end_date, venue_id, expected_attendance, total_budget
) VALUES (
    'Tech Innovation Summit 2024', 'TIS2024', 'conference',
    '2024-05-15', '2024-05-17',
    (SELECT venue_id FROM venues WHERE venue_code = 'GCC001' LIMIT 1),
    800, 150000.00
);

-- Insert sample ticket type
INSERT INTO ticket_types (
    event_id, ticket_name, ticket_code, base_price,
    quantity_available, sales_start_date, sales_end_date
) VALUES (
    (SELECT event_id FROM events WHERE event_code = 'TIS2024' LIMIT 1),
    'Standard Admission', 'STD001', 299.00,
    600, '2024-01-01', '2024-05-14'
);

-- Insert sample registration
INSERT INTO registrations (
    event_id, first_name, last_name, email,
    ticket_type_id, final_amount, payment_status, registration_status
) VALUES (
    (SELECT event_id FROM events WHERE event_code = 'TIS2024' LIMIT 1),
    'John', 'Smith', 'john.smith@email.com',
    (SELECT ticket_type_id FROM ticket_types WHERE ticket_code = 'STD001' LIMIT 1),
    299.00, 'completed', 'confirmed'
);

-- Insert sample speaker
INSERT INTO speakers (
    speaker_name, speaker_code, title, organization,
    bio, email, expertise_areas
) VALUES (
    'Dr. Sarah Johnson', 'SJ001', 'Chief Technology Officer', 'InnovateCorp',
    'Leading technology executive with 15 years of experience in digital transformation',
    'sarah.johnson@innovatecorp.com', ARRAY['Digital Transformation', 'AI/ML', 'Cloud Computing']
);

-- Insert sample vendor
INSERT INTO vendors (
    vendor_name, vendor_code, vendor_type, contact_name,
    email, specialty_services, rating
) VALUES (
    'Premier Catering Services', 'PCS001', 'catering', 'Maria Rodriguez',
    'maria@premiercatering.com', ARRAY['Corporate Catering', 'Event Catering', 'Dietary Accommodations'], 4.5
);

-- This event management schema provides comprehensive infrastructure for event planning,
-- registration, ticketing, venue management, and post-event analytics.
