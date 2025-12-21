-- Travel & Tourism Database Schema
-- Comprehensive schema for travel agencies, booking platforms, and tourism management

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "postgis"; -- For geospatial data

-- ===========================================
-- DESTINATIONS AND ATTRACTIONS
-- ===========================================

CREATE TABLE destinations (
    destination_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    destination_name VARCHAR(255) NOT NULL,
    destination_code VARCHAR(10) UNIQUE NOT NULL,

    -- Geographic Information
    country VARCHAR(100) NOT NULL,
    region VARCHAR(100),
    city VARCHAR(100),
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),

    -- Destination Details
    description TEXT,
    climate VARCHAR(50),
    time_zone VARCHAR(50) DEFAULT 'UTC',
    currency_code CHAR(3) DEFAULT 'USD',

    -- Tourism Information
    primary_language VARCHAR(50),
    visa_requirements TEXT,
    health_requirements TEXT,
    safety_rating INTEGER CHECK (safety_rating BETWEEN 1 AND 5),

    -- Seasonal Information
    peak_season_start DATE,
    peak_season_end DATE,
    shoulder_season_start DATE,
    shoulder_season_end DATE,
    off_season_start DATE,
    off_season_end DATE,

    -- Operational Status
    destination_status VARCHAR(20) DEFAULT 'active' CHECK (destination_status IN ('active', 'inactive', 'restricted', 'closed')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE attractions (
    attraction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    destination_id UUID NOT NULL REFERENCES destinations(destination_id),

    -- Attraction Details
    attraction_name VARCHAR(255) NOT NULL,
    attraction_type VARCHAR(50) CHECK (attraction_type IN (
        'historical_site', 'museum', 'park', 'beach', 'mountain',
        'zoo', 'aquarium', 'theme_park', 'shopping', 'restaurant',
        'religious_site', 'natural_wonder', 'sports_venue', 'entertainment'
    )),

    -- Location and Access
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),
    address TEXT,

    -- Operational Details
    description TEXT,
    operating_hours JSONB DEFAULT '{}', -- Hours for each day
    ticket_price DECIMAL(8,2),
    duration_minutes INTEGER, -- Typical visit duration

    -- Ratings and Popularity
    average_rating DECIMAL(3,2),
    review_count INTEGER DEFAULT 0,
    popularity_score DECIMAL(5,2), -- Based on visits, reviews, etc.

    -- Accessibility
    wheelchair_accessible BOOLEAN DEFAULT FALSE,
    family_friendly BOOLEAN DEFAULT FALSE,
    age_restriction VARCHAR(20),

    -- Seasonal Availability
    seasonal BOOLEAN DEFAULT FALSE,
    available_from DATE,
    available_to DATE,

    -- Media
    images JSONB DEFAULT '[]',
    virtual_tour_url VARCHAR(500),

    -- Status
    attraction_status VARCHAR(20) DEFAULT 'active' CHECK (attraction_status IN ('active', 'inactive', 'temporarily_closed', 'permanently_closed')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SUPPLIERS AND INVENTORY
-- ===========================================

CREATE TABLE suppliers (
    supplier_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_name VARCHAR(255) NOT NULL,
    supplier_code VARCHAR(20) UNIQUE NOT NULL,

    -- Supplier Classification
    supplier_type VARCHAR(30) CHECK (supplier_type IN (
        'airline', 'hotel', 'car_rental', 'tour_operator',
        'cruise_line', 'rail', 'bus', 'activity_provider', 'restaurant'
    )),
    supplier_category VARCHAR(50),

    -- Contact Information
    contact_person VARCHAR(255),
    email VARCHAR(255),
    phone VARCHAR(20),
    address JSONB,

    -- Business Details
    tax_id VARCHAR(50),
    license_number VARCHAR(100),
    insurance_coverage DECIMAL(12,2),

    -- Performance Metrics
    on_time_performance DECIMAL(5,2), -- Percentage
    customer_rating DECIMAL(3,1),
    contract_terms JSONB DEFAULT '{}',

    -- Geographic Coverage
    service_regions TEXT[], -- Countries or regions served
    service_cities TEXT[], -- Specific cities served

    -- Status
    supplier_status VARCHAR(20) DEFAULT 'active' CHECK (supplier_status IN ('active', 'inactive', 'suspended', 'terminated')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE accommodations (
    accommodation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_id UUID NOT NULL REFERENCES suppliers(supplier_id),

    -- Property Details
    property_name VARCHAR(255) NOT NULL,
    property_code VARCHAR(20) UNIQUE NOT NULL,
    property_type VARCHAR(30) CHECK (property_type IN (
        'hotel', 'resort', 'boutique_hotel', 'apartment', 'villa',
        'hostel', 'motel', 'guesthouse', 'vacation_rental'
    )),

    -- Location
    destination_id UUID REFERENCES destinations(destination_id),
    address JSONB,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    geolocation GEOGRAPHY(POINT, 4326),

    -- Property Information
    star_rating INTEGER CHECK (star_rating BETWEEN 1 AND 5),
    total_rooms INTEGER,
    description TEXT,
    amenities JSONB DEFAULT '[]',

    -- Contact and Policies
    phone VARCHAR(20),
    email VARCHAR(255),
    check_in_time TIME DEFAULT '15:00',
    check_out_time TIME DEFAULT '11:00',
    cancellation_policy TEXT,

    -- Operational Status
    property_status VARCHAR(20) DEFAULT 'active' CHECK (property_status IN ('active', 'inactive', 'maintenance', 'closed')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE room_types (
    room_type_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    accommodation_id UUID NOT NULL REFERENCES accommodations(accommodation_id),

    -- Room Details
    room_type_name VARCHAR(100) NOT NULL,
    room_type_code VARCHAR(20) UNIQUE NOT NULL,
    max_occupancy INTEGER DEFAULT 2,

    -- Physical Details
    bed_configuration JSONB DEFAULT '{}', -- [{"type": "king", "count": 1}]
    room_size_sqft INTEGER,
    view_type VARCHAR(50), -- ocean, city, mountain, garden, etc.

    -- Amenities
    amenities JSONB DEFAULT '[]',
    smoking_allowed BOOLEAN DEFAULT FALSE,

    -- Pricing
    base_rate DECIMAL(8,2),
    currency_code CHAR(3) DEFAULT 'USD',

    -- Availability
    total_rooms_of_type INTEGER NOT NULL,

    -- Status
    room_type_status VARCHAR(20) DEFAULT 'active' CHECK (room_type_status IN ('active', 'inactive', 'maintenance')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- FLIGHTS AND TRANSPORTATION
-- ===========================================

CREATE TABLE airlines (
    airline_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    airline_name VARCHAR(255) NOT NULL,
    iata_code CHAR(2) UNIQUE,
    icao_code CHAR(3) UNIQUE,

    -- Airline Details
    country VARCHAR(100),
    alliance VARCHAR(50), -- Star Alliance, OneWorld, SkyTeam
    fleet_size INTEGER,

    -- Service Information
    service_classes TEXT[], -- Economy, Premium Economy, Business, First
    baggage_allowance JSONB DEFAULT '{}',

    -- Performance
    on_time_performance DECIMAL(5,2),
    customer_rating DECIMAL(3,1),

    -- Status
    airline_status VARCHAR(20) DEFAULT 'active' CHECK (airline_status IN ('active', 'inactive', 'bankrupt')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE flights (
    flight_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    airline_id UUID NOT NULL REFERENCES airlines(airline_id),

    -- Flight Details
    flight_number VARCHAR(10) NOT NULL,
    aircraft_type VARCHAR(50),
    service_class VARCHAR(20) CHECK (service_class IN ('economy', 'premium_economy', 'business', 'first')),

    -- Route Information
    origin_airport VARCHAR(10) NOT NULL,
    destination_airport VARCHAR(10) NOT NULL,
    departure_date DATE NOT NULL,
    departure_time TIME NOT NULL,
    arrival_date DATE NOT NULL,
    arrival_time TIME NOT NULL,

    -- Flight Duration and Distance
    flight_duration INTERVAL,
    distance_miles INTEGER,

    -- Operational Details
    aircraft_registration VARCHAR(10),
    meal_service BOOLEAN DEFAULT FALSE,
    wifi_available BOOLEAN DEFAULT FALSE,

    -- Status and Delays
    flight_status VARCHAR(20) DEFAULT 'scheduled' CHECK (flight_status IN (
        'scheduled', 'boarding', 'departed', 'arrived', 'cancelled', 'delayed'
    )),
    delay_minutes INTEGER DEFAULT 0,
    delay_reason VARCHAR(100),

    -- Capacity and Availability
    total_seats INTEGER,
    available_seats INTEGER,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (available_seats <= total_seats),
    CHECK (departure_date <= arrival_date)
);

-- ===========================================
-- PACKAGES AND ITINERARIES
-- ===========================================

CREATE TABLE travel_packages (
    package_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    package_name VARCHAR(255) NOT NULL,
    package_code VARCHAR(20) UNIQUE NOT NULL,

    -- Package Details
    package_type VARCHAR(30) CHECK (package_type IN (
        'vacation_package', 'adventure_trip', 'cultural_tour',
        'cruise_package', 'business_trip', 'honeymoon_package'
    )),
    description TEXT,

    -- Destination and Duration
    primary_destination_id UUID REFERENCES destinations(destination_id),
    duration_days INTEGER NOT NULL,
    duration_nights INTEGER NOT NULL,

    -- Package Components
    includes_flights BOOLEAN DEFAULT FALSE,
    includes_accommodation BOOLEAN DEFAULT TRUE,
    includes_transfers BOOLEAN DEFAULT FALSE,
    includes_meals BOOLEAN DEFAULT FALSE,
    includes_activities BOOLEAN DEFAULT FALSE,

    -- Pricing
    base_price DECIMAL(10,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    price_per_person BOOLEAN DEFAULT TRUE,

    -- Capacity and Availability
    max_participants INTEGER,
    min_participants INTEGER DEFAULT 1,

    -- Operational Details
    difficulty_level VARCHAR(20) CHECK (difficulty_level IN ('easy', 'moderate', 'challenging', 'extreme')),
    age_requirements VARCHAR(50),
    physical_requirements TEXT,

    -- Seasonal Information
    available_from DATE,
    available_to DATE,
    blackout_dates JSONB DEFAULT '[]',

    -- Status
    package_status VARCHAR(20) DEFAULT 'active' CHECK (package_status IN ('active', 'inactive', 'sold_out', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE package_itineraries (
    itinerary_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    package_id UUID NOT NULL REFERENCES travel_packages(package_id),

    -- Itinerary Details
    day_number INTEGER NOT NULL,
    day_title VARCHAR(255),
    day_description TEXT,

    -- Schedule
    start_time TIME,
    end_time TIME,
    duration_hours DECIMAL(4,2),

    -- Location and Activities
    destination_id UUID REFERENCES destinations(destination_id),
    activities JSONB DEFAULT '[]', -- Array of activity details
    attraction_ids UUID[], -- References to attractions

    -- Meals and Services
    meals_included JSONB DEFAULT '{}', -- {"breakfast": true, "lunch": true, "dinner": false}
    transfers_included BOOLEAN DEFAULT FALSE,

    -- Accommodation
    accommodation_id UUID REFERENCES accommodations(accommodation_id),
    room_type_id UUID REFERENCES room_types(room_type_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (package_id, day_number)
);

-- ===========================================
-- BOOKINGS AND RESERVATIONS
-- ===========================================

CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_number VARCHAR(20) UNIQUE,

    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),

    -- Profile Information
    date_of_birth DATE,
    nationality VARCHAR(100),
    passport_number VARCHAR(50),
    passport_expiry DATE,

    -- Preferences
    preferred_airlines TEXT[],
    preferred_seating VARCHAR(20), -- window, aisle, middle
    dietary_restrictions TEXT[],
    accessibility_needs TEXT,

    -- Travel History
    total_trips INTEGER DEFAULT 0,
    loyalty_membership VARCHAR(50),
    vip_status BOOLEAN DEFAULT FALSE,

    -- Contact Preferences
    email_opt_in BOOLEAN DEFAULT TRUE,
    sms_opt_in BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE bookings (
    booking_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_number VARCHAR(30) UNIQUE NOT NULL,

    -- Customer Information
    customer_id UUID NOT NULL REFERENCES customers(customer_id),
    agent_id UUID, -- References booking agent

    -- Booking Details
    booking_type VARCHAR(30) CHECK (booking_type IN (
        'flight_only', 'hotel_only', 'package', 'multi_destination', 'custom'
    )),
    booking_status VARCHAR(30) DEFAULT 'confirmed' CHECK (booking_status IN (
        'pending', 'confirmed', 'cancelled', 'completed', 'refunded'
    )),

    -- Travel Dates
    departure_date DATE,
    return_date DATE,
    booking_date DATE DEFAULT CURRENT_DATE,

    -- Financial Information
    total_amount DECIMAL(12,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    amount_paid DECIMAL(12,2) DEFAULT 0,
    outstanding_balance DECIMAL(12,2) GENERATED ALWAYS AS (total_amount - amount_paid) STORED,

    -- Payment Information
    payment_method VARCHAR(30),
    payment_reference VARCHAR(100),

    -- Special Requests
    special_requests TEXT,
    customer_notes TEXT,

    -- Travel Documents
    visa_required BOOLEAN DEFAULT FALSE,
    insurance_purchased BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE booking_items (
    booking_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_id UUID NOT NULL REFERENCES bookings(booking_id) ON DELETE CASCADE,

    -- Item Details
    item_type VARCHAR(30) CHECK (item_type IN (
        'flight', 'hotel_room', 'car_rental', 'activity', 'insurance', 'transfer'
    )),
    item_description VARCHAR(500),

    -- Service References
    flight_id UUID REFERENCES flights(flight_id),
    accommodation_id UUID REFERENCES accommodations(accommodation_id),
    room_type_id UUID REFERENCES room_types(room_type_id),
    supplier_id UUID REFERENCES suppliers(supplier_id),

    -- Booking Details
    start_date DATE,
    end_date DATE,
    quantity INTEGER DEFAULT 1,

    -- Pricing
    unit_price DECIMAL(8,2),
    total_price DECIMAL(10,2),
    taxes_and_fees DECIMAL(8,2),

    -- Confirmation
    confirmation_number VARCHAR(50),
    supplier_reference VARCHAR(50),

    -- Status
    item_status VARCHAR(20) DEFAULT 'confirmed' CHECK (item_status IN (
        'confirmed', 'cancelled', 'modified', 'no_show', 'completed'
    )),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (unit_price >= 0),
    CHECK (quantity > 0)
);

-- ===========================================
-- PRICING AND AVAILABILITY
-- ===========================================

CREATE TABLE rate_plans (
    rate_plan_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    accommodation_id UUID REFERENCES accommodations(accommodation_id),
    supplier_id UUID REFERENCES suppliers(supplier_id),

    -- Rate Plan Details
    rate_plan_name VARCHAR(100) NOT NULL,
    rate_plan_code VARCHAR(20) UNIQUE NOT NULL,
    rate_plan_type VARCHAR(30) CHECK (rate_plan_type IN (
        'standard', 'promotional', 'corporate', 'government', 'aaa', 'military'
    )),

    -- Validity Period
    valid_from DATE NOT NULL,
    valid_to DATE,

    -- Pricing Rules
    base_rate DECIMAL(8,2),
    currency_code CHAR(3) DEFAULT 'USD',
    pricing_model VARCHAR(20) CHECK (pricing_model IN ('fixed', 'dynamic', 'yield_management')),

    -- Restrictions
    minimum_stay_nights INTEGER DEFAULT 1,
    maximum_stay_nights INTEGER,
    advance_booking_days INTEGER,
    cancellation_policy TEXT,

    -- Availability
    total_rooms_allocated INTEGER,
    rooms_sold INTEGER DEFAULT 0,
    remaining_rooms INTEGER GENERATED ALWAYS AS (total_rooms_allocated - rooms_sold) STORED,

    -- Status
    rate_plan_status VARCHAR(20) DEFAULT 'active' CHECK (rate_plan_status IN ('active', 'inactive', 'sold_out')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (valid_from <= COALESCE(valid_to, CURRENT_DATE)),
    CHECK (remaining_rooms >= 0)
);

CREATE TABLE seasonal_rates (
    seasonal_rate_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rate_plan_id UUID NOT NULL REFERENCES rate_plans(rate_plan_id),

    -- Seasonal Period
    season_name VARCHAR(50),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    -- Seasonal Pricing
    seasonal_multiplier DECIMAL(4,2) DEFAULT 1.0, -- Rate multiplier for this season
    minimum_rate DECIMAL(8,2),
    maximum_rate DECIMAL(8,2),

    -- Demand Indicators
    expected_occupancy DECIMAL(5,2), -- Expected occupancy percentage

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (start_date < end_date),
    CHECK (seasonal_multiplier > 0)
);

-- ===========================================
-- CUSTOMER SERVICE AND SUPPORT
-- ===========================================

CREATE TABLE support_tickets (
    ticket_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID REFERENCES customers(customer_id),
    booking_id UUID REFERENCES bookings(booking_id),

    -- Ticket Details
    ticket_number VARCHAR(20) UNIQUE NOT NULL,
    ticket_type VARCHAR(30) CHECK (ticket_type IN (
        'booking_inquiry', 'change_request', 'cancellation', 'complaint',
        'refund_request', 'technical_issue', 'lost_luggage', 'medical_emergency'
    )),
    ticket_priority VARCHAR(10) CHECK (ticket_priority IN ('low', 'medium', 'high', 'urgent')),

    -- Ticket Content
    subject VARCHAR(255) NOT NULL,
    description TEXT,
    attachments JSONB DEFAULT '[]',

    -- Status and Assignment
    ticket_status VARCHAR(20) DEFAULT 'open' CHECK (ticket_status IN (
        'open', 'assigned', 'in_progress', 'waiting_customer', 'resolved', 'closed'
    )),
    assigned_agent UUID,
    department VARCHAR(50),

    -- Resolution
    resolution TEXT,
    resolution_satisfaction_rating INTEGER CHECK (resolution_satisfaction_rating BETWEEN 1 AND 5),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    first_response_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,

    -- SLA Tracking
    sla_breach BOOLEAN DEFAULT FALSE,
    response_time_minutes INTEGER GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (first_response_at - created_at)) / 60
    ) STORED,
    resolution_time_hours INTEGER GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (resolved_at - created_at)) / 3600
    ) STORED
);

CREATE TABLE customer_reviews (
    review_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),

    -- Review Subject
    booking_id UUID REFERENCES bookings(booking_id),
    destination_id UUID REFERENCES destinations(destination_id),
    accommodation_id UUID REFERENCES accommodations(accommodation_id),
    supplier_id UUID REFERENCES suppliers(supplier_id),

    -- Review Content
    overall_rating INTEGER CHECK (overall_rating BETWEEN 1 AND 5),
    review_title VARCHAR(255),
    review_text TEXT,

    -- Detailed Ratings
    value_rating INTEGER CHECK (value_rating BETWEEN 1 AND 5),
    location_rating INTEGER CHECK (location_rating BETWEEN 1 AND 5),
    service_rating INTEGER CHECK (service_rating BETWEEN 1 AND 5),
    cleanliness_rating INTEGER CHECK (cleanliness_rating BETWEEN 1 AND 5),

    -- Review Status
    review_status VARCHAR(20) DEFAULT 'published' CHECK (review_status IN ('pending', 'published', 'rejected', 'removed')),

    -- Trip Details
    trip_date DATE,
    trip_type VARCHAR(30) CHECK (trip_type IN ('leisure', 'business', 'family', 'solo', 'group')),

    -- Verification
    verified_purchase BOOLEAN DEFAULT FALSE,
    review_helpful_votes INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP WITH TIME ZONE
);

-- ===========================================
-- ANALYTICS AND REPORTING
-- ===========================================

CREATE TABLE booking_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Time Dimensions
    report_date DATE NOT NULL,
    report_month DATE,

    -- Booking Metrics
    total_bookings INTEGER DEFAULT 0,
    total_revenue DECIMAL(15,2) DEFAULT 0,
    average_booking_value DECIMAL(10,2),

    -- Customer Metrics
    unique_customers INTEGER DEFAULT 0,
    new_customers INTEGER DEFAULT 0,
    repeat_customers INTEGER DEFAULT 0,

    -- Channel Performance
    direct_bookings INTEGER DEFAULT 0,
    online_bookings INTEGER DEFAULT 0,
    agent_bookings INTEGER DEFAULT 0,

    -- Destination Performance
    top_destinations JSONB DEFAULT '[]',
    top_packages JSONB DEFAULT '[]',

    -- Cancellation and No-show
    cancellation_rate DECIMAL(5,2),
    no_show_rate DECIMAL(5,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (report_date)
);

CREATE TABLE destination_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    destination_id UUID NOT NULL REFERENCES destinations(destination_id),

    -- Time Dimensions
    report_date DATE NOT NULL,

    -- Destination Metrics
    total_visitors INTEGER DEFAULT 0,
    average_stay_duration DECIMAL(4,1), -- Days
    average_spend_per_visitor DECIMAL(10,2),

    -- Seasonal Performance
    peak_season_occupancy DECIMAL(5,2),
    shoulder_season_occupancy DECIMAL(5,2),
    off_season_occupancy DECIMAL(5,2),

    -- Attraction Popularity
    top_attractions JSONB DEFAULT '[]',

    -- Economic Impact
    tourism_revenue DECIMAL(15,2),
    jobs_supported INTEGER,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (destination_id, report_date)
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Destination and attraction indexes
CREATE INDEX idx_destinations_country ON destinations (country);
CREATE INDEX idx_destinations_location ON destinations USING gist (ST_Point(longitude, latitude));
CREATE INDEX idx_attractions_destination ON attractions (destination_id);
CREATE INDEX idx_attractions_type ON attractions (attraction_type);

-- Supplier and accommodation indexes
CREATE INDEX idx_suppliers_type ON suppliers (supplier_type, supplier_status);
CREATE INDEX idx_accommodations_destination ON accommodations (destination_id);
CREATE INDEX idx_accommodations_type ON accommodations (property_type, star_rating);

-- Flight and transportation indexes
CREATE INDEX idx_flights_route_date ON flights (origin_airport, destination_airport, departure_date);
CREATE INDEX idx_flights_airline ON flights (airline_id, flight_status);
CREATE INDEX idx_flights_status ON flights (flight_status);

-- Package and booking indexes
CREATE INDEX idx_travel_packages_type ON travel_packages (package_type, package_status);
CREATE INDEX idx_travel_packages_destination ON travel_packages (primary_destination_id);
CREATE INDEX idx_bookings_customer ON bookings (customer_id, booking_date DESC);
CREATE INDEX idx_bookings_status ON bookings (booking_status, departure_date);
CREATE INDEX idx_booking_items_booking ON booking_items (booking_id);

-- Customer service indexes
CREATE INDEX idx_support_tickets_customer ON support_tickets (customer_id, ticket_status);
CREATE INDEX idx_support_tickets_type ON support_tickets (ticket_type, ticket_priority);
CREATE INDEX idx_customer_reviews_subject ON customer_reviews (accommodation_id, overall_rating);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Destination overview with attractions and accommodations
CREATE VIEW destination_overview AS
SELECT
    d.destination_id,
    d.destination_name,
    d.country,
    d.description,
    d.climate,
    d.safety_rating,

    -- Attraction counts
    COUNT(DISTINCT a.attraction_id) as total_attractions,
    COUNT(DISTINCT CASE WHEN a.attraction_type = 'historical_site' THEN a.attraction_id END) as historical_sites,
    COUNT(DISTINCT CASE WHEN a.attraction_type = 'beach' THEN a.attraction_id END) as beaches,
    COUNT(DISTINCT CASE WHEN a.attraction_type = 'museum' THEN a.attraction_id END) as museums,

    -- Accommodation options
    COUNT(DISTINCT acc.accommodation_id) as total_properties,
    AVG(acc.star_rating) as avg_hotel_rating,
    MIN(acc.star_rating) as min_rating,
    MAX(acc.star_rating) as max_rating,

    -- Pricing indicators
    AVG(rt.base_rate) as avg_room_rate,
    MIN(rt.base_rate) as min_room_rate,
    MAX(rt.base_rate) as max_room_rate

FROM destinations d
LEFT JOIN attractions a ON d.destination_id = a.destination_id AND a.attraction_status = 'active'
LEFT JOIN accommodations acc ON d.destination_id = acc.destination_id AND acc.property_status = 'active'
LEFT JOIN room_types rt ON acc.accommodation_id = rt.accommodation_id
WHERE d.destination_status = 'active'
GROUP BY d.destination_id, d.destination_name, d.country, d.description, d.climate, d.safety_rating;

-- Package availability and pricing summary
CREATE VIEW package_availability AS
SELECT
    tp.package_id,
    tp.package_name,
    tp.package_type,
    tp.duration_days,
    d.destination_name,

    -- Pricing
    tp.base_price,
    tp.currency_code,
    CASE WHEN tp.price_per_person THEN 'per person' ELSE 'total' END as pricing_type,

    -- Availability
    tp.max_participants,
    CASE
        WHEN tp.available_from <= CURRENT_DATE AND (tp.available_to IS NULL OR tp.available_to >= CURRENT_DATE) THEN 'available'
        WHEN tp.available_from > CURRENT_DATE THEN 'upcoming'
        ELSE 'season_ended'
    END as availability_status,

    -- Capacity
    CASE
        WHEN tp.max_participants IS NULL THEN 'unlimited'
        WHEN tp.max_participants > 20 THEN 'large_group'
        WHEN tp.max_participants > 10 THEN 'medium_group'
        ELSE 'small_group'
    END as group_size,

    -- Inclusions
    CASE WHEN tp.includes_flights THEN '✓' ELSE '✗' END as flights_included,
    CASE WHEN tp.includes_accommodation THEN '✓' ELSE '✗' END as accommodation_included,
    CASE WHEN tp.includes_meals THEN '✓' ELSE '✗' END as meals_included,
    CASE WHEN tp.includes_activities THEN '✓' ELSE '✗' END as activities_included

FROM travel_packages tp
LEFT JOIN destinations d ON tp.primary_destination_id = d.destination_id
WHERE tp.package_status = 'active'
ORDER BY tp.base_price ASC;

-- Customer booking history and preferences
CREATE VIEW customer_booking_history AS
SELECT
    c.customer_id,
    c.customer_number,
    c.first_name || ' ' || c.last_name as customer_name,
    c.email,

    -- Booking statistics
    COUNT(b.booking_id) as total_bookings,
    COUNT(DISTINCT d.destination_id) as unique_destinations,
    SUM(b.total_amount) as total_spent,
    AVG(b.total_amount) as avg_booking_value,

    -- Travel patterns
    MIN(b.departure_date) as first_trip_date,
    MAX(b.return_date) as last_trip_date,
    AVG(b.return_date - b.departure_date) as avg_trip_length_days,

    -- Preferred destinations
    STRING_AGG(DISTINCT dest.destination_name, ', ') as preferred_destinations,

    -- Booking types
    COUNT(CASE WHEN b.booking_type = 'package' THEN 1 END) as package_bookings,
    COUNT(CASE WHEN b.booking_type = 'flight_only' THEN 1 END) as flight_only_bookings,
    COUNT(CASE WHEN b.booking_type = 'hotel_only' THEN 1 END) as hotel_only_bookings,

    -- Cancellation rate
    ROUND(
        COUNT(CASE WHEN b.booking_status = 'cancelled' THEN 1 END)::DECIMAL /
        NULLIF(COUNT(b.booking_id), 0) * 100, 2
    ) as cancellation_rate,

    -- Loyalty status
    CASE
        WHEN COUNT(b.booking_id) >= 10 AND AVG(b.total_amount) >= 5000 THEN 'platinum'
        WHEN COUNT(b.booking_id) >= 5 OR SUM(b.total_amount) >= 2500 THEN 'gold'
        WHEN COUNT(b.booking_id) >= 2 THEN 'silver'
        ELSE 'bronze'
    END as loyalty_tier

FROM customers c
LEFT JOIN bookings b ON c.customer_id = b.customer_id AND b.booking_status != 'cancelled'
LEFT JOIN booking_items bi ON b.booking_id = bi.booking_id
LEFT JOIN destinations dest ON bi.accommodation_id IN (
    SELECT accommodation_id FROM accommodations WHERE destination_id = dest.destination_id
)
WHERE c.customer_status = 'active'
GROUP BY c.customer_id, c.customer_number, c.first_name, c.last_name, c.email;

-- Revenue and booking analytics dashboard
CREATE VIEW booking_revenue_dashboard AS
SELECT
    DATE_TRUNC('month', b.booking_date) as booking_month,

    -- Booking volume
    COUNT(b.booking_id) as total_bookings,
    COUNT(CASE WHEN b.booking_status = 'confirmed' THEN 1 END) as confirmed_bookings,
    COUNT(CASE WHEN b.booking_status = 'cancelled' THEN 1 END) as cancelled_bookings,

    -- Revenue metrics
    SUM(b.total_amount) as total_booking_value,
    SUM(b.amount_paid) as total_paid,
    SUM(b.outstanding_balance) as total_outstanding,

    -- Average metrics
    AVG(b.total_amount) as avg_booking_value,
    AVG(b.return_date - b.departure_date) as avg_trip_length,

    -- Customer metrics
    COUNT(DISTINCT b.customer_id) as unique_customers,
    COUNT(DISTINCT CASE WHEN c.created_at >= DATE_TRUNC('month', b.booking_date) THEN b.customer_id END) as new_customers,

    -- Channel performance
    COUNT(CASE WHEN b.booking_type = 'package' THEN 1 END) as package_bookings,
    COUNT(CASE WHEN b.booking_type = 'flight_only' THEN 1 END) as flight_bookings,
    COUNT(CASE WHEN b.booking_type = 'hotel_only' THEN 1 END) as hotel_bookings,

    -- Geographic distribution
    COUNT(DISTINCT d.country) as countries_booked,
    STRING_AGG(DISTINCT d.country, ', ') as top_countries

FROM bookings b
LEFT JOIN customers c ON b.customer_id = c.customer_id
LEFT JOIN booking_items bi ON b.booking_id = bi.booking_id
LEFT JOIN accommodations acc ON bi.accommodation_id = acc.accommodation_id
LEFT JOIN destinations d ON acc.destination_id = d.destination_id
WHERE b.booking_date >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', b.booking_date)
ORDER BY booking_month DESC;

-- ===========================================
-- FUNCTIONS FOR TRAVEL OPERATIONS
-- =========================================--

-- Function to check accommodation availability
CREATE OR REPLACE FUNCTION check_accommodation_availability(
    accommodation_uuid UUID,
    room_type_uuid UUID,
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
    -- Get total rooms of specified type
    SELECT rt.total_rooms_of_type INTO total_rooms_count
    FROM room_types rt
    WHERE rt.room_type_id = room_type_uuid AND rt.accommodation_id = accommodation_uuid;

    -- Count booked rooms for the date range
    SELECT COUNT(*) INTO booked_rooms_count
    FROM booking_items bi
    WHERE bi.accommodation_id = accommodation_uuid
      AND bi.room_type_id = room_type_uuid
      AND bi.item_status IN ('confirmed', 'checked_in')
      AND (bi.start_date, bi.end_date) OVERLAPS (check_in_date, check_out_date);

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

-- Function to calculate package pricing
CREATE OR REPLACE FUNCTION calculate_package_price(
    package_uuid UUID,
    number_of_travelers INTEGER DEFAULT 1,
    travel_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    base_price DECIMAL,
    taxes_and_fees DECIMAL,
    total_price DECIMAL,
    price_per_person DECIMAL,
    currency_code VARCHAR
) AS $$
DECLARE
    package_record travel_packages%ROWTYPE;
    seasonal_multiplier DECIMAL := 1.0;
    calculated_price DECIMAL;
BEGIN
    -- Get package details
    SELECT * INTO package_record FROM travel_packages WHERE package_id = package_uuid;

    -- Check if package is available for the travel date
    IF travel_date < COALESCE(package_record.available_from, travel_date) OR
       travel_date > COALESCE(package_record.available_to, travel_date) THEN
        RETURN QUERY SELECT NULL::DECIMAL, NULL::DECIMAL, NULL::DECIMAL, NULL::DECIMAL, NULL::VARCHAR;
        RETURN;
    END IF;

    -- Apply seasonal pricing (simplified)
    IF EXTRACT(MONTH FROM travel_date) IN (6, 7, 8) THEN
        seasonal_multiplier := 1.2; -- Summer peak
    ELSIF EXTRACT(MONTH FROM travel_date) IN (12, 1, 2) THEN
        seasonal_multiplier := 1.15; -- Winter holiday
    END IF;

    calculated_price := package_record.base_price * seasonal_multiplier;

    -- Calculate taxes and fees (simplified 10%)
    taxes_fees := calculated_price * 0.10;

    RETURN QUERY SELECT
        package_record.base_price,
        taxes_fees,
        calculated_price + taxes_fees,
        CASE WHEN package_record.price_per_person THEN (calculated_price + taxes_fees) / number_of_travelers
             ELSE calculated_price + taxes_fees END,
        package_record.currency_code;
END;
$$ LANGUAGE plpgsql;

-- Function to process booking cancellation
CREATE OR REPLACE FUNCTION process_booking_cancellation(
    booking_uuid UUID,
    cancellation_reason TEXT DEFAULT NULL,
    refund_percentage DECIMAL DEFAULT 0
)
RETURNS TABLE (
    success BOOLEAN,
    refund_amount DECIMAL,
    cancellation_fee DECIMAL,
    final_refund DECIMAL
) AS $$
DECLARE
    booking_record bookings%ROWTYPE;
    refund_amt DECIMAL;
    cancel_fee DECIMAL;
BEGIN
    -- Get booking details
    SELECT * INTO booking_record FROM bookings WHERE booking_id = booking_uuid;

    -- Validate cancellation
    IF booking_record.booking_status IN ('cancelled', 'completed') THEN
        RETURN QUERY SELECT FALSE, NULL::DECIMAL, NULL::DECIMAL, NULL::DECIMAL;
        RETURN;
    END IF;

    -- Calculate refund based on cancellation policy and time to departure
    IF booking_record.departure_date <= CURRENT_DATE + INTERVAL '7 days' THEN
        refund_amt := booking_record.total_amount * 0.5; -- 50% refund for late cancellation
    ELSIF booking_record.departure_date <= CURRENT_DATE + INTERVAL '14 days' THEN
        refund_amt := booking_record.total_amount * 0.75; -- 75% refund
    ELSE
        refund_amt := booking_record.total_amount * refund_percentage; -- Custom percentage
    END IF;

    cancel_fee := booking_record.total_amount - refund_amt;

    -- Update booking status
    UPDATE bookings SET
        booking_status = 'cancelled',
        updated_at = CURRENT_TIMESTAMP
    WHERE booking_id = booking_uuid;

    -- Update booking items
    UPDATE booking_items SET
        item_status = 'cancelled'
    WHERE booking_id = booking_uuid;

    -- Process refund (would integrate with payment system)
    UPDATE bookings SET
        outstanding_balance = outstanding_balance - refund_amt
    WHERE booking_id = booking_uuid;

    RETURN QUERY SELECT TRUE, refund_amt, cancel_fee, refund_amt;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample destination
INSERT INTO destinations (
    destination_name, destination_code, country, city,
    latitude, longitude, description, climate, safety_rating
) VALUES (
    'Paris', 'PAR', 'France', 'Paris',
    48.8566, 2.3522, 'City of Light with world-famous museums and cuisine',
    'temperate', 4
);

-- Insert sample attraction
INSERT INTO attractions (
    destination_id, attraction_name, attraction_type,
    description, ticket_price, operating_hours
) VALUES (
    (SELECT destination_id FROM destinations WHERE destination_code = 'PAR' LIMIT 1),
    'Eiffel Tower', 'historical_site',
    'Iconic iron lattice tower and symbol of Paris', 18.00,
    '{"monday": {"open": "09:30", "close": "23:45"}}'
);

-- Insert sample accommodation
INSERT INTO accommodations (
    supplier_id, property_name, property_code, property_type,
    destination_id, star_rating, total_rooms, base_rate
) VALUES (
    gen_random_uuid(), 'Hotel Ritz Paris', 'RITZ_PAR', 'boutique_hotel',
    (SELECT destination_id FROM destinations WHERE destination_code = 'PAR' LIMIT 1),
    5, 159, 800.00
);

-- Insert sample customer
INSERT INTO customers (customer_number, first_name, last_name, email, phone) VALUES
('CUST001', 'John', 'Smith', 'john.smith@email.com', '+1-555-0123');

-- Insert sample booking
INSERT INTO bookings (
    booking_number, customer_id, booking_type,
    departure_date, return_date, total_amount
) VALUES (
    'BK001234', (SELECT customer_id FROM customers WHERE customer_number = 'CUST001' LIMIT 1),
    'package', '2024-06-15', '2024-06-22', 3500.00
);

-- This travel schema provides comprehensive infrastructure for travel booking,
-- destination management, supplier relationships, and customer service.
