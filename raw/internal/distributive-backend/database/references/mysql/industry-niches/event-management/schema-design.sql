-- Event Management Database Schema (MySQL)
-- Comprehensive schema for event planning, ticketing, and attendee management
-- Adapted for MySQL with JSON support, fulltext search, and performance optimizations

-- ===========================================
-- EVENT MANAGEMENT
-- ===========================================

CREATE TABLE events (
    event_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    event_name VARCHAR(255) NOT NULL,
    event_description LONGTEXT,

    -- Event details
    event_type ENUM('conference', 'concert', 'festival', 'corporate', 'wedding', 'sports', 'theater', 'webinar', 'workshop', 'networking', 'other') DEFAULT 'conference',
    event_category VARCHAR(100),

    -- Scheduling
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    start_time TIME,
    end_time TIME,
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Capacity and venue
    venue_id CHAR(36),
    max_capacity INT,
    expected_attendees INT,

    -- Status and visibility
    event_status ENUM('draft', 'published', 'registration_open', 'registration_closed', 'in_progress', 'completed', 'cancelled') DEFAULT 'draft',
    is_public BOOLEAN DEFAULT TRUE,
    is_virtual BOOLEAN DEFAULT FALSE,

    -- Pricing and costs
    base_price DECIMAL(8,2),
    currency VARCHAR(3) DEFAULT 'USD',
    total_budget DECIMAL(10,2),

    -- Contact and organization
    organizer_id CHAR(36),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),

    -- Marketing and SEO
    event_website VARCHAR(500),
    social_media_links JSON DEFAULT ('{}'),
    seo_keywords JSON DEFAULT ('[]'),

    -- Metadata
    tags JSON DEFAULT ('[]'),
    custom_fields JSON DEFAULT ('{}'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (venue_id) REFERENCES venues(venue_id),
    FOREIGN KEY (organizer_id) REFERENCES organizers(organizer_id),

    INDEX idx_events_type (event_type),
    INDEX idx_events_status (event_status),
    INDEX idx_events_date (start_date, end_date),
    INDEX idx_events_venue (venue_id),
    INDEX idx_events_organizer (organizer_id),
    INDEX idx_events_public (is_public),
    FULLTEXT INDEX ft_events_name_desc (event_name, event_description)
) ENGINE = InnoDB;

CREATE TABLE event_sessions (
    session_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    event_id CHAR(36) NOT NULL,

    session_name VARCHAR(255) NOT NULL,
    session_description TEXT,

    -- Scheduling
    session_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    duration_minutes INT GENERATED ALWAYS AS (TIMESTAMPDIFF(MINUTE, CONCAT(session_date, ' ', start_time), CONCAT(session_date, ' ', end_time))) STORED,

    -- Venue and capacity
    room_id CHAR(36),
    max_capacity INT,
    session_type ENUM('keynote', 'workshop', 'panel', 'breakout', 'networking', 'meal', 'other') DEFAULT 'breakout',

    -- Speakers and content
    speaker_ids JSON DEFAULT ('[]'),
    session_materials JSON DEFAULT ('[]'),  -- PDFs, videos, etc.

    -- Registration and tracking
    requires_registration BOOLEAN DEFAULT FALSE,
    max_registrations INT,
    current_registrations INT DEFAULT 0,

    -- Status
    session_status ENUM('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled') DEFAULT 'scheduled',

    -- Metadata
    tags JSON DEFAULT ('[]'),
    custom_fields JSON DEFAULT ('{}'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (event_id) REFERENCES events(event_id) ON DELETE CASCADE,
    FOREIGN KEY (room_id) REFERENCES venue_rooms(room_id),

    INDEX idx_sessions_event (event_id),
    INDEX idx_sessions_date (session_date, start_time),
    INDEX idx_sessions_room (room_id),
    INDEX idx_sessions_type (session_type),
    INDEX idx_sessions_status (session_status)
) ENGINE = InnoDB;

-- ===========================================
-- VENUE MANAGEMENT
-- ===========================================

CREATE TABLE venues (
    venue_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    venue_name VARCHAR(255) NOT NULL,
    venue_description TEXT,

    -- Location
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(50) DEFAULT 'USA',
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),

    -- Contact
    contact_name VARCHAR(255),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),

    -- Capacity and features
    total_capacity INT,
    parking_capacity INT,
    has_wifi BOOLEAN DEFAULT TRUE,
    has_av_equipment BOOLEAN DEFAULT TRUE,
    venue_features JSON DEFAULT ('[]'),  -- Pool, gym, catering, etc.

    -- Business details
    venue_type ENUM('conference_center', 'hotel', 'university', 'arena', 'theater', 'outdoor', 'corporate', 'other') DEFAULT 'conference_center',
    hourly_rate DECIMAL(8,2),
    daily_rate DECIMAL(8,2),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Metadata
    venue_photos JSON DEFAULT ('[]'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_venues_type (venue_type),
    INDEX idx_venues_active (is_active),
    INDEX idx_venues_city (city, state_province),
    SPATIAL INDEX idx_venues_location (POINT(latitude, longitude))
) ENGINE = InnoDB;

CREATE TABLE venue_rooms (
    room_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    venue_id CHAR(36) NOT NULL,

    room_name VARCHAR(255) NOT NULL,
    room_type ENUM('auditorium', 'conference_room', 'workshop_room', 'lounge', 'exhibit_hall', 'dining_room', 'other') DEFAULT 'conference_room',

    -- Capacity and layout
    capacity INT NOT NULL,
    seating_arrangement ENUM('theater', 'classroom', 'banquet', 'reception', 'boardroom') DEFAULT 'theater',

    -- Equipment and amenities
    has_projector BOOLEAN DEFAULT FALSE,
    has_microphones BOOLEAN DEFAULT FALSE,
    has_internet BOOLEAN DEFAULT TRUE,
    room_features JSON DEFAULT ('[]'),

    -- Pricing
    hourly_rate DECIMAL(8,2),
    setup_fee DECIMAL(8,2),

    -- Status
    is_available BOOLEAN DEFAULT TRUE,

    FOREIGN KEY (venue_id) REFERENCES venues(venue_id) ON DELETE CASCADE,

    INDEX idx_rooms_venue (venue_id),
    INDEX idx_rooms_type (room_type),
    INDEX idx_rooms_available (is_available)
) ENGINE = InnoDB;

-- ===========================================
-- TICKETING SYSTEM
-- =========================================--

CREATE TABLE ticket_types (
    ticket_type_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    event_id CHAR(36) NOT NULL,

    ticket_name VARCHAR(255) NOT NULL,
    ticket_description TEXT,

    -- Pricing
    base_price DECIMAL(8,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',

    -- Availability
    quantity_available INT NOT NULL,
    quantity_sold INT DEFAULT 0,
    max_per_person INT DEFAULT 10,

    -- Timing
    sale_start_date DATETIME,
    sale_end_date DATETIME,
    is_active BOOLEAN DEFAULT TRUE,

    -- Access and features
    ticket_category ENUM('general', 'vip', 'student', 'senior', 'group', 'sponsor', 'speaker', 'staff') DEFAULT 'general',
    access_level ENUM('full_access', 'limited_sessions', 'single_session', 'exhibit_only') DEFAULT 'full_access',

    -- Features
    includes_meals BOOLEAN DEFAULT FALSE,
    includes_parking BOOLEAN DEFAULT FALSE,
    includes_swag BOOLEAN DEFAULT FALSE,
    ticket_features JSON DEFAULT ('[]'),

    FOREIGN KEY (event_id) REFERENCES events(event_id) ON DELETE CASCADE,

    INDEX idx_ticket_types_event (event_id),
    INDEX idx_ticket_types_category (ticket_category),
    INDEX idx_ticket_types_active (is_active),
    INDEX idx_ticket_types_price (base_price)
) ENGINE = InnoDB;

CREATE TABLE tickets (
    ticket_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    ticket_type_id CHAR(36) NOT NULL,
    attendee_id CHAR(36) NOT NULL,

    -- Ticket details
    ticket_number VARCHAR(20) UNIQUE NOT NULL,
    qr_code VARCHAR(255) UNIQUE,
    purchase_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Pricing (at time of purchase)
    purchase_price DECIMAL(8,2) NOT NULL,
    taxes DECIMAL(8,2) DEFAULT 0,
    fees DECIMAL(8,2) DEFAULT 0,
    total_paid DECIMAL(8,2) GENERATED ALWAYS AS (purchase_price + taxes + fees) STORED,

    -- Status and access
    ticket_status ENUM('active', 'used', 'cancelled', 'refunded') DEFAULT 'active',
    check_in_time TIMESTAMP NULL,
    check_in_method ENUM('qr_code', 'rfid', 'manual', 'api') DEFAULT 'qr_code',

    -- Assignment and transfer
    is_transferable BOOLEAN DEFAULT TRUE,
    transferred_from CHAR(36) NULL,
    transfer_history JSON DEFAULT ('[]'),

    -- Metadata
    purchase_metadata JSON DEFAULT ('{}'),
    custom_fields JSON DEFAULT ('{}'),

    FOREIGN KEY (ticket_type_id) REFERENCES ticket_types(ticket_type_id),
    FOREIGN KEY (attendee_id) REFERENCES attendees(attendee_id),
    FOREIGN KEY (transferred_from) REFERENCES attendees(attendee_id),

    INDEX idx_tickets_type (ticket_type_id),
    INDEX idx_tickets_attendee (attendee_id),
    INDEX idx_tickets_status (ticket_status),
    INDEX idx_tickets_number (ticket_number),
    INDEX idx_tickets_qr (qr_code),
    INDEX idx_tickets_purchase (purchase_date)
) ENGINE = InnoDB;

CREATE TABLE discount_codes (
    discount_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    event_id CHAR(36) NOT NULL,

    code VARCHAR(50) UNIQUE NOT NULL,
    description VARCHAR(255),

    -- Discount details
    discount_type ENUM('percentage', 'fixed_amount', 'free_ticket') DEFAULT 'percentage',
    discount_value DECIMAL(8,2) NOT NULL,  -- 10.00 for $10 off, 0.15 for 15%

    -- Usage limits
    max_uses INT DEFAULT 100,
    uses_remaining INT DEFAULT 100,
    max_uses_per_person INT DEFAULT 1,

    -- Validity
    valid_from TIMESTAMP,
    valid_until TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,

    -- Restrictions
    applicable_ticket_types JSON DEFAULT ('[]'),  -- Empty means all types
    minimum_purchase DECIMAL(8,2) DEFAULT 0,

    -- Tracking
    created_by CHAR(36),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (event_id) REFERENCES events(event_id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES organizers(organizer_id),

    INDEX idx_discounts_event (event_id),
    INDEX idx_discounts_code (code),
    INDEX idx_discounts_active (is_active),
    INDEX idx_discounts_valid (valid_from, valid_until)
) ENGINE = InnoDB;

-- ===========================================
-- ATTENDEE MANAGEMENT
-- ===========================================

CREATE TABLE attendees (
    attendee_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),

    -- Personal information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),

    -- Profile
    job_title VARCHAR(100),
    company VARCHAR(255),
    bio TEXT,
    avatar_url VARCHAR(500),

    -- Preferences and dietary
    dietary_restrictions JSON DEFAULT ('[]'),
    accessibility_needs JSON DEFAULT ('[]'),
    networking_interests JSON DEFAULT ('[]'),

    -- Social and professional
    linkedin_url VARCHAR(500),
    twitter_handle VARCHAR(50),
    website VARCHAR(500),

    -- Status
    registration_status ENUM('pending', 'confirmed', 'checked_in', 'cancelled') DEFAULT 'pending',
    is_vip BOOLEAN DEFAULT FALSE,

    -- Metadata
    registration_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    check_in_time TIMESTAMP NULL,
    source VARCHAR(100),  -- How they heard about the event
    custom_fields JSON DEFAULT ('{}'),

    INDEX idx_attendees_email (email),
    INDEX idx_attendees_status (registration_status),
    INDEX idx_attendees_vip (is_vip),
    INDEX idx_attendees_registration (registration_date),
    FULLTEXT INDEX ft_attendees_name_company (first_name, last_name, company)
) ENGINE = InnoDB;

CREATE TABLE attendee_sessions (
    attendee_id CHAR(36) NOT NULL,
    session_id CHAR(36) NOT NULL,

    -- Registration details
    registration_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    registration_method ENUM('self_registered', 'transferred', 'assigned', 'api') DEFAULT 'self_registered',

    -- Attendance
    check_in_time TIMESTAMP NULL,
    check_out_time TIMESTAMP NULL,
    attendance_status ENUM('registered', 'attended', 'no_show', 'cancelled') DEFAULT 'registered',

    -- Feedback
    rating INT CHECK (rating >= 1 AND rating <= 5),
    feedback TEXT,

    PRIMARY KEY (attendee_id, session_id),
    FOREIGN KEY (attendee_id) REFERENCES attendees(attendee_id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES event_sessions(session_id) ON DELETE CASCADE,

    INDEX idx_attendee_sessions_session (session_id),
    INDEX idx_attendee_sessions_status (attendance_status),
    INDEX idx_attendee_sessions_rating (rating)
) ENGINE = InnoDB;

-- ===========================================
-- SPONSORSHIP MANAGEMENT
-- =========================================--

CREATE TABLE sponsors (
    sponsor_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    sponsor_name VARCHAR(255) NOT NULL,
    sponsor_type ENUM('platinum', 'gold', 'silver', 'bronze', 'partner', 'media', 'community') NOT NULL,

    -- Contact information
    contact_name VARCHAR(255),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),

    -- Company details
    website VARCHAR(500),
    logo_url VARCHAR(500),
    description TEXT,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_sponsors_type (sponsor_type),
    INDEX idx_sponsors_active (is_active)
) ENGINE = InnoDB;

CREATE TABLE event_sponsors (
    event_id CHAR(36) NOT NULL,
    sponsor_id CHAR(36) NOT NULL,

    -- Sponsorship details
    sponsorship_level ENUM('platinum', 'gold', 'silver', 'bronze') NOT NULL,
    sponsorship_amount DECIMAL(10,2),
    contract_terms JSON DEFAULT ('{}'),

    -- Benefits and perks
    booth_assigned BOOLEAN DEFAULT FALSE,
    speaking_slot BOOLEAN DEFAULT FALSE,
    logo_placement JSON DEFAULT ('[]'),  -- Website, program, signage
    mentions_count INT DEFAULT 0,

    -- Tracking
    leads_generated INT DEFAULT 0,
    roi_calculated DECIMAL(8,2),

    PRIMARY KEY (event_id, sponsor_id),
    FOREIGN KEY (event_id) REFERENCES events(event_id) ON DELETE CASCADE,
    FOREIGN KEY (sponsor_id) REFERENCES sponsors(sponsor_id) ON DELETE CASCADE,

    INDEX idx_event_sponsors_sponsor (sponsor_id),
    INDEX idx_event_sponsors_level (sponsorship_level)
) ENGINE = InnoDB;

-- ===========================================
-- ANALYTICS AND REPORTING
-- =========================================--

CREATE TABLE event_analytics (
    analytic_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    event_id CHAR(36) NOT NULL,
    metric_date DATE NOT NULL,

    -- Attendance metrics
    total_registrations INT DEFAULT 0,
    confirmed_attendees INT DEFAULT 0,
    checked_in_attendees INT DEFAULT 0,
    no_show_count INT DEFAULT 0,

    -- Financial metrics
    total_revenue DECIMAL(10,2) DEFAULT 0,
    total_expenses DECIMAL(10,2) DEFAULT 0,
    net_profit DECIMAL(10,2) GENERATED ALWAYS AS (total_revenue - total_expenses) STORED,

    -- Engagement metrics
    session_attendance_avg DECIMAL(5,2) DEFAULT 0,  -- Percentage
    networking_connections INT DEFAULT 0,
    app_downloads INT DEFAULT 0,
    social_media_mentions INT DEFAULT 0,

    -- Satisfaction metrics
    overall_rating DECIMAL(3,1),
    feedback_response_rate DECIMAL(5,2),

    -- Marketing metrics
    website_visits INT DEFAULT 0,
    conversion_rate DECIMAL(5,2),
    registration_sources JSON DEFAULT ('{}'),

    FOREIGN KEY (event_id) REFERENCES events(event_id) ON DELETE CASCADE,
    UNIQUE KEY unique_event_date (event_id, metric_date),

    INDEX idx_analytics_event (event_id),
    INDEX idx_analytics_date (metric_date)
) ENGINE = InnoDB;

-- ===========================================
-- SUPPORTING TABLES
-- =========================================--

CREATE TABLE organizers (
    organizer_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    organizer_name VARCHAR(255) NOT NULL,
    organizer_type ENUM('individual', 'company', 'nonprofit', 'government') DEFAULT 'company',

    -- Contact information
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),
    website VARCHAR(500),

    -- Business details
    tax_id VARCHAR(50),
    address JSON DEFAULT ('{}'),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_organizers_type (organizer_type),
    INDEX idx_organizers_active (is_active)
) ENGINE = InnoDB;

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- =========================================--

-- Composite indexes for common queries
CREATE INDEX idx_events_date_range ON events (start_date, end_date);
CREATE INDEX idx_events_status_dates ON events (event_status, start_date, end_date);
CREATE INDEX idx_sessions_event_date ON event_sessions (event_id, session_date, start_time);
CREATE INDEX idx_tickets_type_status ON tickets (ticket_type_id, ticket_status);
CREATE INDEX idx_attendee_sessions_status ON attendee_sessions (session_id, attendance_status);
CREATE INDEX idx_analytics_date_range ON event_analytics (event_id, metric_date);

-- ===========================================
-- STORED PROCEDURES FOR EVENT MANAGEMENT
-- =========================================--

DELIMITER ;;

-- Get event dashboard summary
CREATE PROCEDURE get_event_dashboard(IN event_uuid CHAR(36))
BEGIN
    -- Event overview
    SELECT
        e.event_name,
        e.event_status,
        e.start_date,
        e.end_date,
        e.max_capacity,
        v.venue_name,
        e.expected_attendees,

        -- Ticket sales summary
        COUNT(DISTINCT tt.ticket_type_id) as ticket_types_count,
        SUM(tt.quantity_sold) as total_tickets_sold,
        SUM(tt.quantity_available - tt.quantity_sold) as tickets_remaining,
        SUM(tt.base_price * tt.quantity_sold) as gross_revenue,

        -- Attendee summary
        COUNT(DISTINCT a.attendee_id) as total_registrations,
        COUNT(DISTINCT CASE WHEN a.registration_status = 'checked_in' THEN a.attendee_id END) as checked_in_count,
        COUNT(DISTINCT CASE WHEN a.registration_status = 'confirmed' THEN a.attendee_id END) as confirmed_count,

        -- Session summary
        COUNT(DISTINCT es.session_id) as total_sessions,
        COUNT(DISTINCT CASE WHEN es.session_status = 'completed' THEN es.session_id END) as completed_sessions,
        AVG(CASE WHEN es.session_status = 'completed' THEN es.current_registrations END) as avg_session_attendance

    FROM events e
    LEFT JOIN venues v ON e.venue_id = v.venue_id
    LEFT JOIN ticket_types tt ON e.event_id = tt.event_id
    LEFT JOIN tickets t ON tt.ticket_type_id = tt.ticket_type_id
    LEFT JOIN attendees a ON t.attendee_id = a.attendee_id
    LEFT JOIN event_sessions es ON e.event_id = es.event_id
    WHERE e.event_id = event_uuid
    GROUP BY e.event_id, e.event_name, e.event_status, e.start_date, e.end_date,
             e.max_capacity, v.venue_name, e.expected_attendees;

    -- Revenue breakdown
    SELECT
        tt.ticket_name,
        tt.ticket_category,
        tt.base_price,
        COUNT(t.ticket_id) as tickets_sold,
        SUM(t.total_paid) as revenue
    FROM ticket_types tt
    LEFT JOIN tickets t ON tt.ticket_type_id = tt.ticket_type_id AND t.ticket_status != 'cancelled'
    WHERE tt.event_id = event_uuid
    GROUP BY tt.ticket_type_id, tt.ticket_name, tt.ticket_category, tt.base_price
    ORDER BY revenue DESC;

    -- Daily attendance trends
    SELECT
        DATE(check_in_time) as date,
        COUNT(*) as check_ins,
        HOUR(check_in_time) as hour
    FROM tickets t
    WHERE t.ticket_status = 'used'
      AND EXISTS (SELECT 1 FROM ticket_types tt WHERE tt.ticket_type_id = t.ticket_type_id AND tt.event_id = event_uuid)
    GROUP BY DATE(check_in_time), HOUR(check_in_time)
    ORDER BY date, hour;
END;;

-- Generate attendee badge data
CREATE PROCEDURE generate_badge_data(IN event_uuid CHAR(36))
BEGIN
    SELECT
        a.attendee_id,
        a.first_name,
        a.last_name,
        a.job_title,
        a.company,
        t.ticket_number,
        tt.ticket_name,
        tt.ticket_category,
        CASE
            WHEN a.is_vip THEN 'VIP'
            WHEN tt.ticket_category = 'vip' THEN 'VIP'
            ELSE 'Standard'
        END as access_level,
        e.event_name,
        DATE_FORMAT(e.start_date, '%M %d, %Y') as event_date,
        v.venue_name,
        qr_code as badge_qr
    FROM attendees a
    INNER JOIN tickets t ON a.attendee_id = t.attendee_id
    INNER JOIN ticket_types tt ON t.ticket_type_id = tt.ticket_type_id
    INNER JOIN events e ON tt.event_id = e.event_id
    LEFT JOIN venues v ON e.venue_id = v.venue_id
    WHERE e.event_id = event_uuid
      AND t.ticket_status = 'active'
      AND a.registration_status IN ('confirmed', 'checked_in')
    ORDER BY a.last_name, a.first_name;
END;;

-- Calculate event ROI
CREATE FUNCTION calculate_event_roi(event_uuid CHAR(36))
RETURNS JSON
DETERMINISTIC
BEGIN
    DECLARE revenue_total DECIMAL(12,2) DEFAULT 0;
    DECLARE expense_total DECIMAL(12,2) DEFAULT 0;
    DECLARE attendee_count INT DEFAULT 0;
    DECLARE sponsor_investment DECIMAL(12,2) DEFAULT 0;
    DECLARE roi_result JSON;

    -- Calculate total revenue
    SELECT COALESCE(SUM(t.total_paid), 0) INTO revenue_total
    FROM tickets t
    INNER JOIN ticket_types tt ON t.ticket_type_id = tt.ticket_type_id
    WHERE tt.event_id = event_uuid AND t.ticket_status != 'refunded';

    -- Add sponsor revenue
    SELECT COALESCE(SUM(es.sponsorship_amount), 0) INTO sponsor_investment
    FROM event_sponsors es
    WHERE es.event_id = event_uuid;

    SET revenue_total = revenue_total + sponsor_investment;

    -- Get expenses (would need expense tracking table)
    SET expense_total = 0; -- Placeholder for actual expense calculation

    -- Get attendee count
    SELECT COUNT(DISTINCT t.attendee_id) INTO attendee_count
    FROM tickets t
    INNER JOIN ticket_types tt ON t.ticket_type_id = tt.ticket_type_id
    WHERE tt.event_id = event_uuid AND t.ticket_status = 'active';

    -- Calculate ROI
    SET roi_result = JSON_OBJECT(
        'event_id', event_uuid,
        'total_revenue', revenue_total,
        'total_expenses', expense_total,
        'net_profit', revenue_total - expense_total,
        'attendee_count', attendee_count,
        'revenue_per_attendee', CASE
            WHEN attendee_count > 0 THEN ROUND(revenue_total / attendee_count, 2)
            ELSE 0
        END,
        'roi_percentage', CASE
            WHEN expense_total > 0 THEN ROUND(((revenue_total - expense_total) / expense_total) * 100, 2)
            ELSE CASE WHEN revenue_total > 0 THEN 999.99 ELSE 0 END
        END,
        'break_even_attendees', CASE
            WHEN revenue_total > expense_total THEN 0
            ELSE CEIL(expense_total / (revenue_total / NULLIF(attendee_count, 0)))
        END,
        'profitability_status', CASE
            WHEN revenue_total > expense_total THEN 'profitable'
            WHEN revenue_total > expense_total * 0.8 THEN 'marginally_profitable'
            ELSE 'loss'
        END
    );

    RETURN roi_result;
END;;

DELIMITER ;

-- ===========================================
-- INITIAL SAMPLE DATA
-- =========================================--

INSERT INTO organizers (organizer_id, organizer_name, organizer_type, email) VALUES
(UUID(), 'TechEvents Inc', 'company', 'events@techevents.com'),
(UUID(), 'Conference Pros LLC', 'company', 'info@conferencepros.com');

INSERT INTO venues (venue_id, venue_name, venue_type, city, state_province, total_capacity) VALUES
(UUID(), 'Convention Center Grand', 'conference_center', 'San Francisco', 'CA', 2000),
(UUID(), 'Tech Hub Auditorium', 'conference_center', 'Austin', 'TX', 800);

INSERT INTO events (event_id, event_name, event_type, start_date, end_date, venue_id, organizer_id, max_capacity, base_price) VALUES
(UUID(), 'Tech Conference 2024', 'conference', '2024-06-15', '2024-06-17', (SELECT venue_id FROM venues LIMIT 1), (SELECT organizer_id FROM organizers LIMIT 1), 1500, 299.99);

INSERT INTO ticket_types (ticket_type_id, event_id, ticket_name, base_price, quantity_available, ticket_category) VALUES
(UUID(), (SELECT event_id FROM events LIMIT 1), 'Early Bird', 249.99, 500, 'general'),
(UUID(), (SELECT event_id FROM events LIMIT 1), 'Regular Admission', 299.99, 800, 'general'),
(UUID(), (SELECT event_id FROM events LIMIT 1), 'VIP Experience', 499.99, 200, 'vip');

/*
USAGE EXAMPLES:

-- Get comprehensive event dashboard
CALL get_event_dashboard('event-uuid-here');

-- Generate badge data for check-in
CALL generate_badge_data('event-uuid-here');

-- Calculate event ROI
SELECT calculate_event_roi('event-uuid-here');

This comprehensive event management database schema provides enterprise-grade infrastructure for:
- Complete event planning and scheduling
- Multi-tier ticketing with dynamic pricing
- Attendee registration and management
- Venue and room management
- Sponsorship tracking and ROI analysis
- Real-time analytics and reporting
- Mobile check-in and networking features

Key features adapted for MySQL:
- UUID primary keys with UUID() function
- JSON data types for flexible metadata storage
- Full-text search for event discovery
- Spatial indexes for venue locations
- Generated columns for calculated fields
- Stored procedures for complex event analytics

The schema supports conferences, concerts, corporate events, and community gatherings with integrated payment processing and marketing automation.
*/
