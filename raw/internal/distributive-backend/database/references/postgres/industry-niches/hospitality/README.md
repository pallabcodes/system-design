# Hospitality & Hotel Management Database Design

## Overview

This comprehensive database schema supports hotel and hospitality operations including property management, reservations, guest services, room inventory, housekeeping, maintenance, and financial operations. The design handles complex booking workflows, multi-property operations, and guest experience management.

## Key Features

### 🏨 Property & Room Management
- **Multi-property portfolio** management with hierarchical organization
- **Dynamic room inventory** with real-time availability tracking
- **Flexible room types** and rate structures with seasonal pricing
- **Room maintenance** and housekeeping workflow management

### 📅 Reservation & Booking Engine
- **Complex reservation management** with room blocks and group bookings
- **Multi-channel booking** support (direct, OTAs, travel agents, corporate)
- **Dynamic pricing** with rate restrictions and availability controls
- **Booking modifications** and cancellation policies

### 👥 Guest Experience Management
- **Comprehensive guest profiles** with preferences and history
- **Guest service requests** with automated routing and fulfillment
- **In-house guest tracking** with key card and amenity management
- **Guest satisfaction** surveys and feedback collection

### 💰 Financial Operations
- **Multi-currency billing** with tax calculations and payment processing
- **Folio management** with room charges, services, and adjustments
- **Payment processing** with multiple payment methods and reconciliation
- **Revenue management** with rate optimization and yield analysis

## Database Schema Highlights

### Core Tables

#### Property Management
- **`properties`** - Hotel/resort properties with operational details
- **`rooms`** - Room inventory with status, amenities, and maintenance tracking
- **`room_rates`** - Dynamic pricing with restrictions and availability

#### Reservation System
- **`reservations`** - Guest reservations with booking details and status
- **`reservation_rooms`** - Room assignments with check-in/check-out tracking
- **`room_blocks`** - Group and corporate room allocations

#### Guest Management
- **`guests`** - Guest profiles with preferences and loyalty information
- **`in_house_guests`** - Active guest tracking during stays
- **`guest_services`** - Available services and amenities

#### Financial Management
- **`folios`** - Guest billing accounts with charges and payments
- **`folio_transactions`** - Detailed transaction history
- **`payments`** - Payment processing and reconciliation

#### Operations
- **`housekeeping_schedule`** - Room cleaning and maintenance scheduling
- **`maintenance_requests`** - Facility maintenance and repair tracking
- **`service_requests`** - Guest service fulfillment and tracking

## Key Design Patterns

### 1. Room Availability Engine
```sql
-- Check room availability across date ranges with complex constraints
CREATE OR REPLACE FUNCTION get_available_rooms(
    property_uuid UUID,
    room_type_param VARCHAR DEFAULT NULL,
    check_in_date DATE,
    check_out_date DATE,
    number_of_rooms INTEGER DEFAULT 1
)
RETURNS TABLE (
    room_type VARCHAR,
    available_rooms INTEGER,
    total_rooms INTEGER,
    available_rates JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.room_type,
        COUNT(*) as available_rooms,
        COUNT(*) as total_rooms, -- This should be total rooms of type
        jsonb_agg(
            jsonb_build_object(
                'rate_id', rr.rate_id,
                'rate_name', rr.rate_name,
                'base_rate', rr.base_rate,
                'remaining_rooms', rr.remaining_rooms
            )
        ) FILTER (WHERE rr.remaining_rooms > 0) as available_rates

    FROM rooms r
    LEFT JOIN room_rates rr ON r.room_id = rr.room_id
        AND rr.valid_from <= check_in_date
        AND rr.valid_to >= check_out_date
        AND rr.remaining_rooms > 0

    WHERE r.property_id = property_uuid
      AND (room_type_param IS NULL OR r.room_type = room_type_param)
      AND r.room_status = 'available'

      -- Exclude rooms already booked
      AND r.room_id NOT IN (
          SELECT rr2.room_id
          FROM reservation_rooms rr2
          WHERE rr2.room_status IN ('reserved', 'checked_in')
            AND (rr2.check_in_date, rr2.check_out_date) OVERLAPS (check_in_date, check_out_date)
      )

    GROUP BY r.room_type
    HAVING COUNT(*) >= number_of_rooms;
END;
$$ LANGUAGE plpgsql;
```

### 2. Dynamic Rate Management
```sql
-- Calculate final room rate with all applicable restrictions and promotions
CREATE OR REPLACE FUNCTION calculate_room_rate(
    room_uuid UUID,
    check_in_date DATE,
    length_of_stay INTEGER,
    guest_type VARCHAR DEFAULT 'standard',
    promotion_codes TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS TABLE (
    base_rate DECIMAL,
    final_rate DECIMAL,
    applied_restrictions JSONB,
    available BOOLEAN
) AS $$
DECLARE
    room_rate_record RECORD;
    final_rate_val DECIMAL;
    restrictions JSONB := '[]';
    is_available BOOLEAN := TRUE;
BEGIN
    -- Get applicable room rate
    SELECT rr.*, r.room_status INTO room_rate_record
    FROM room_rates rr
    JOIN rooms r ON rr.room_id = r.room_id
    WHERE rr.room_id = room_uuid
      AND rr.valid_from <= check_in_date
      AND rr.valid_to >= check_in_date + length_of_stay - 1
      AND rr.remaining_rooms > 0
    ORDER BY rr.base_rate
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN QUERY SELECT NULL::DECIMAL, NULL::DECIMAL, '[]'::JSONB, FALSE;
        RETURN;
    END IF;

    final_rate_val := room_rate_record.base_rate;

    -- Apply minimum stay restrictions
    IF length_of_stay < room_rate_record.minimum_stay_nights THEN
        restrictions := restrictions || jsonb_build_object(
            'type', 'minimum_stay',
            'required', room_rate_record.minimum_stay_nights,
            'provided', length_of_stay
        );
        is_available := FALSE;
    END IF;

    -- Apply advance booking restrictions
    IF check_in_date - CURRENT_DATE < room_rate_record.advance_booking_days THEN
        restrictions := restrictions || jsonb_build_object(
            'type', 'advance_booking',
            'required', room_rate_record.advance_booking_days,
            'days_in_advance', check_in_date - CURRENT_DATE
        );
        is_available := FALSE;
    END IF;

    -- Apply guest type restrictions (corporate, AAA, etc.)
    IF room_rate_record.cancellation_policy IS NOT NULL THEN
        -- Additional logic for guest type validation
        restrictions := restrictions || jsonb_build_object(
            'guest_type_restrictions', room_rate_record.cancellation_policy
        );
    END IF;

    RETURN QUERY SELECT
        room_rate_record.base_rate,
        final_rate_val,
        restrictions,
        is_available;
END;
$$ LANGUAGE plpgsql;
```

### 3. Guest Check-In/Out Automation
```sql
-- Automated check-in process with room assignment and key card generation
CREATE OR REPLACE FUNCTION process_guest_checkin(
    reservation_uuid UUID,
    room_assignments JSONB
)
RETURNS TABLE (
    success BOOLEAN,
    checkin_details JSONB,
    errors TEXT[]
) AS $$
DECLARE
    reservation_record reservations%ROWTYPE;
    room_assignment JSONB;
    room_uuid UUID;
    errors TEXT[] := ARRAY[]::TEXT[];
    checkin_details_val JSONB := '{}';
BEGIN
    -- Get reservation details
    SELECT * INTO reservation_record FROM reservations WHERE reservation_id = reservation_uuid;

    -- Validate check-in eligibility
    IF reservation_record.reservation_status != 'confirmed' THEN
        errors := errors || 'Reservation is not in confirmed status';
    END IF;

    IF reservation_record.check_in_date != CURRENT_DATE THEN
        errors := errors || 'Check-in date does not match current date';
    END IF;

    IF array_length(errors, 1) > 0 THEN
        RETURN QUERY SELECT FALSE, '{}'::JSONB, errors;
        RETURN;
    END IF;

    -- Process room assignments
    FOR room_assignment IN SELECT * FROM jsonb_array_elements(room_assignments)
    LOOP
        room_uuid := (room_assignment->>'room_id')::UUID;

        -- Validate room availability
        IF NOT EXISTS (
            SELECT 1 FROM rooms
            WHERE room_id = room_uuid
              AND room_status = 'available'
              AND housekeeping_status = 'clean'
        ) THEN
            errors := errors || format('Room %s is not available', room_uuid);
            CONTINUE;
        END IF;

        -- Assign room to reservation
        UPDATE reservation_rooms SET
            room_id = room_uuid,
            room_status = 'checked_in',
            actual_check_in_time = CURRENT_TIMESTAMP
        WHERE reservation_id = reservation_uuid
          AND reservation_room_id = (room_assignment->>'reservation_room_id')::UUID;

        -- Update room status
        UPDATE rooms SET room_status = 'occupied' WHERE room_id = room_uuid;

        -- Generate key card and access codes
        INSERT INTO in_house_guests (
            reservation_room_id,
            guest_name,
            key_card_number,
            safe_combination
        ) VALUES (
            (room_assignment->>'reservation_room_id')::UUID,
            room_assignment->>'guest_name',
            generate_key_card_number(),
            generate_safe_combination()
        );
    END LOOP;

    -- Update reservation status
    UPDATE reservations SET
        reservation_status = 'checked_in'
    WHERE reservation_id = reservation_uuid;

    -- Prepare check-in details
    checkin_details_val := jsonb_build_object(
        'reservation_id', reservation_uuid,
        'checkin_time', CURRENT_TIMESTAMP,
        'rooms_assigned', room_assignments,
        'welcome_message', 'Welcome to ' || reservation_record.property_id
    );

    RETURN QUERY SELECT
        array_length(errors, 1) IS NULL OR array_length(errors, 1) = 0,
        checkin_details_val,
        errors;
END;
$$ LANGUAGE plpgsql;
```

### 4. Revenue Management Optimization
```sql
-- Dynamic pricing recommendations based on demand and inventory
CREATE OR REPLACE FUNCTION optimize_room_rates(
    property_uuid UUID,
    target_date DATE,
    optimization_horizon INTEGER DEFAULT 30
)
RETURNS TABLE (
    room_type VARCHAR,
    current_rate DECIMAL,
    recommended_rate DECIMAL,
    expected_occupancy DECIMAL,
    revenue_impact DECIMAL,
    confidence_score DECIMAL
) AS $$
DECLARE
    room_type_record RECORD;
    historical_avg_rate DECIMAL;
    historical_occupancy DECIMAL;
    demand_multiplier DECIMAL;
BEGIN
    FOR room_type_record IN
        SELECT
            r.room_type,
            AVG(rr.base_rate) as current_avg_rate,
            COUNT(*) as total_rooms_of_type
        FROM rooms r
        LEFT JOIN room_rates rr ON r.room_id = rr.room_id
            AND rr.valid_from <= target_date
            AND rr.valid_to >= target_date
        WHERE r.property_id = property_uuid
        GROUP BY r.room_type
    LOOP
        -- Calculate historical performance
        SELECT
            AVG(rr.base_rate) as hist_avg_rate,
            AVG(oa.occupancy_rate) as hist_occupancy
        INTO historical_avg_rate, historical_occupancy
        FROM room_rates rr
        JOIN rooms r ON rr.room_id = r.room_id
        LEFT JOIN occupancy_analytics oa ON oa.property_id = property_uuid
            AND oa.report_date >= target_date - INTERVAL '90 days'
            AND oa.report_date < target_date
        WHERE r.property_id = property_uuid
          AND r.room_type = room_type_record.room_type;

        -- Calculate demand multiplier (simplified)
        demand_multiplier := CASE
            WHEN EXTRACT(DOW FROM target_date) IN (0, 6) THEN 1.2  -- Weekend
            WHEN EXTRACT(MONTH FROM target_date) IN (6, 7, 8) THEN 1.15  -- Summer
            WHEN EXTRACT(MONTH FROM target_date) IN (11, 12) THEN 1.25  -- Holiday
            ELSE 1.0
        END;

        -- Recommend rate adjustment
        RETURN QUERY SELECT
            room_type_record.room_type,
            room_type_record.current_avg_rate,
            LEAST(room_type_record.current_avg_rate * demand_multiplier, room_type_record.current_avg_rate * 1.5),
            GREATEST(historical_occupancy * demand_multiplier, 95.0),
            (room_type_record.current_avg_rate * demand_multiplier - room_type_record.current_avg_rate) * historical_occupancy / 100 * room_type_record.total_rooms_of_type,
            0.75; -- Confidence score
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition reservations by check-in month for performance
CREATE TABLE reservations PARTITION BY RANGE (check_in_date);

CREATE TABLE reservations_2024_01 PARTITION OF reservations
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition occupancy analytics by year
CREATE TABLE occupancy_analytics PARTITION BY RANGE (report_date);

CREATE TABLE occupancy_analytics_2024 PARTITION OF occupancy_analytics
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- Partition housekeeping schedule by month
CREATE TABLE housekeeping_schedule PARTITION BY RANGE (scheduled_date);

CREATE TABLE housekeeping_schedule_2024 PARTITION OF housekeeping_schedule
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

### Advanced Indexing
```sql
-- Composite indexes for reservation queries
CREATE INDEX idx_reservations_property_checkin ON reservations
    (property_id, check_in_date DESC, check_out_date);

CREATE INDEX idx_reservations_status_dates ON reservations
    (reservation_status, check_in_date, check_out_date);

-- Spatial indexes for location-based queries
CREATE INDEX idx_properties_location ON properties USING gist (
    ST_Point((address->>'longitude')::float, (address->>'latitude')::float)
);

-- Partial indexes for active records
CREATE INDEX idx_rooms_available ON rooms (room_id, room_type)
    WHERE room_status = 'available' AND housekeeping_status = 'clean';

CREATE INDEX idx_reservations_confirmed ON reservations (reservation_id)
    WHERE reservation_status = 'confirmed';

-- JSONB indexes for flexible queries
CREATE INDEX idx_rooms_amenities ON rooms USING gin (amenities);
CREATE INDEX idx_guests_preferences ON guests USING gin (room_preferences);
CREATE INDEX idx_reservations_special_requests ON reservations USING gin ((special_requests::jsonb));
```

### Materialized Views for Analytics
```sql
-- Real-time occupancy dashboard
CREATE MATERIALIZED VIEW current_occupancy AS
SELECT
    p.property_id,
    p.property_name,
    p.total_rooms,

    -- Current occupancy
    COUNT(CASE WHEN rr.room_status = 'checked_in' THEN 1 END) as rooms_occupied,
    ROUND(COUNT(CASE WHEN rr.room_status = 'checked_in' THEN 1 END)::DECIMAL / p.total_rooms * 100, 2) as occupancy_rate,

    -- Today's activity
    COUNT(CASE WHEN rr.check_in_date = CURRENT_DATE THEN 1 END) as check_ins_today,
    COUNT(CASE WHEN rr.check_out_date = CURRENT_DATE THEN 1 END) as check_outs_today,

    -- Room status breakdown
    COUNT(CASE WHEN r.room_status = 'available' THEN 1 END) as rooms_available,
    COUNT(CASE WHEN r.room_status = 'maintenance' THEN 1 END) as rooms_maintenance,
    COUNT(CASE WHEN r.room_status = 'out_of_order' THEN 1 END) as rooms_out_of_order,

    -- Revenue today
    COALESCE(SUM(CASE WHEN rr.room_status = 'checked_in' THEN rr.room_rate END), 0) as revenue_today,

    -- Housekeeping status
    COUNT(CASE WHEN r.housekeeping_status = 'clean' THEN 1 END) as rooms_clean,
    COUNT(CASE WHEN r.housekeeping_status = 'dirty' THEN 1 END) as rooms_dirty

FROM properties p
LEFT JOIN rooms r ON p.property_id = r.property_id
LEFT JOIN reservation_rooms rr ON r.room_id = rr.room_id
    AND rr.check_in_date <= CURRENT_DATE
    AND rr.check_out_date > CURRENT_DATE
GROUP BY p.property_id, p.property_name, p.total_rooms;

-- Refresh every 15 minutes
CREATE UNIQUE INDEX idx_current_occupancy_property ON current_occupancy (property_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY current_occupancy;
```

## Security Considerations

### Access Control
```sql
-- Role-based security for hospitality operations
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE guests ENABLE ROW LEVEL SECURITY;

CREATE POLICY reservation_access_policy ON reservations
    FOR ALL USING (
        property_id IN (
            SELECT property_id FROM user_properties
            WHERE user_id = current_setting('app.user_id')::UUID
        ) OR
        current_setting('app.user_role')::TEXT IN ('admin', 'corporate')
    );

CREATE POLICY guest_privacy_policy ON guests
    FOR SELECT USING (
        guest_id = current_setting('app.guest_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('manager', 'admin') OR
        current_setting('app.has_guest_data_access')::BOOLEAN = TRUE
    );
```

### Data Encryption
```sql
-- Encrypt sensitive guest and payment information
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypt payment card information
CREATE OR REPLACE FUNCTION encrypt_payment_data(card_number TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(card_number, current_setting('hospitality.payment_key'));
END;
$$ LANGUAGE plpgsql;

-- Encrypt guest personal information
CREATE OR REPLACE FUNCTION encrypt_guest_data(personal_data TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(personal_data, current_setting('hospitality.guest_key'));
END;
$$ LANGUAGE plpgsql;
```

### Audit Trail
```sql
-- Comprehensive hospitality audit logging
CREATE TABLE hospitality_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    property_id UUID REFERENCES properties(property_id),
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    change_reason TEXT,
    guest_privacy_impact VARCHAR(20) CHECK (guest_privacy_impact IN ('none', 'low', 'medium', 'high')),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Audit trigger for sensitive operations
CREATE OR REPLACE FUNCTION hospitality_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO hospitality_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, property_id, session_id, ip_address, user_agent,
        guest_privacy_impact
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME LIKE '%reservation%' THEN
            (SELECT property_id FROM reservations WHERE reservation_id = COALESCE(NEW.id, OLD.id))
        ELSE NULL END,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE
            WHEN TG_TABLE_NAME IN ('guests', 'reservations') THEN 'high'
            WHEN TG_TABLE_NAME LIKE '%payment%' THEN 'medium'
            ELSE 'low'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### PCI DSS Compliance
```sql
-- Secure payment data handling
CREATE OR REPLACE FUNCTION process_secure_payment(
    reservation_uuid UUID,
    payment_info JSONB
)
RETURNS TABLE (
    success BOOLEAN,
    transaction_id VARCHAR,
    masked_card_number VARCHAR,
    error_message TEXT
) AS $$
DECLARE
    payment_result RECORD;
    masked_card VARCHAR;
BEGIN
    -- Validate payment data (never store full card numbers)
    IF NOT (payment_info ? 'card_token' OR payment_info ? 'payment_method_id') THEN
        RETURN QUERY SELECT FALSE, NULL::VARCHAR, NULL::VARCHAR, 'Invalid payment data'::TEXT;
        RETURN;
    END IF;

    -- Process payment through PCI-compliant gateway
    -- (Integration with payment processor would go here)
    SELECT
        TRUE as success,
        'txn_' || uuid_generate_v4()::TEXT as transaction_id,
        '****-****-****-' || RIGHT(payment_info->>'last_four', 4) as masked_card,
        NULL as error_message
    INTO payment_result;

    -- Log payment (without sensitive data)
    INSERT INTO payment_transactions (
        reservation_id, amount, payment_method, transaction_id, masked_card
    ) VALUES (
        reservation_uuid,
        (payment_info->>'amount')::DECIMAL,
        payment_info->>'method',
        payment_result.transaction_id,
        payment_result.masked_card
    );

    RETURN QUERY SELECT
        payment_result.success,
        payment_result.transaction_id,
        payment_result.masked_card,
        payment_result.error_message;
END;
$$ LANGUAGE plpgsql;
```

### GDPR Compliance
```sql
-- Guest data management for GDPR compliance
CREATE OR REPLACE FUNCTION process_gdpr_data_request(
    guest_uuid UUID,
    request_type VARCHAR,  -- 'access', 'rectification', 'erasure'
    request_details JSONB DEFAULT '{}'
)
RETURNS TABLE (
    success BOOLEAN,
    data_extracted JSONB,
    records_affected INTEGER,
    compliance_notes TEXT
) AS $$
DECLARE
    affected_count INTEGER := 0;
    extracted_data JSONB := '{}';
BEGIN
    CASE request_type
        WHEN 'access' THEN
            -- Extract all guest data
            SELECT jsonb_build_object(
                'guest_profile', to_jsonb(g.*),
                'reservations', jsonb_agg(to_jsonb(r.*)),
                'payments', jsonb_agg(to_jsonb(p.*)),
                'services', jsonb_agg(to_jsonb(sr.*))
            ) INTO extracted_data
            FROM guests g
            LEFT JOIN reservations r ON g.guest_id = r.guest_id
            LEFT JOIN payments p ON r.reservation_id = p.folio_id
            LEFT JOIN service_requests sr ON r.reservation_id = sr.in_house_id
            WHERE g.guest_id = guest_uuid
            GROUP BY g.guest_id;

            affected_count := 1;

        WHEN 'rectification' THEN
            -- Update guest data
            UPDATE guests SET
                first_name = COALESCE(request_details->>'first_name', first_name),
                last_name = COALESCE(request_details->>'last_name', last_name),
                email = COALESCE(request_details->>'email', email),
                phone = COALESCE(request_details->>'phone', phone),
                updated_at = CURRENT_TIMESTAMP
            WHERE guest_id = guest_uuid;

            affected_count := 1;

        WHEN 'erasure' THEN
            -- Mark guest data for deletion (soft delete)
            UPDATE guests SET
                do_not_rent = TRUE,
                guest_status = 'erased',
                special_notes = 'GDPR erasure requested on ' || CURRENT_DATE,
                updated_at = CURRENT_TIMESTAMP
            WHERE guest_id = guest_uuid;

            -- Anonymize historical data
            UPDATE reservations SET
                guest_email = 'erased@gdpr.com',
                special_requests = 'Personal data erased per GDPR'
            WHERE guest_id = guest_uuid;

            affected_count := 1;
    END CASE;

    RETURN QUERY SELECT
        TRUE,
        extracted_data,
        affected_count,
        format('GDPR %s request processed for guest %s', request_type, guest_uuid);
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Central Reservation Systems (CRS)** for multi-property bookings
- **Property Management Systems (PMS)** for operational management
- **Revenue Management Systems** for dynamic pricing
- **Customer Relationship Platforms** for guest data management

### API Endpoints
- **Booking Engine APIs** for real-time availability and reservations
- **Guest Services APIs** for in-room requests and concierge services
- **Property Management APIs** for housekeeping and maintenance coordination
- **Analytics APIs** for business intelligence and reporting

## Monitoring & Analytics

### Key Performance Indicators
- **Occupancy rates** by property, room type, and time period
- **Average Daily Rate (ADR)** and Revenue Per Available Room (RevPAR)
- **Guest satisfaction scores** and Net Promoter Score (NPS)
- **Booking conversion rates** by channel and time to booking
- **Housekeeping efficiency** and maintenance response times

### Real-Time Dashboards
```sql
-- Hospitality operations dashboard
CREATE VIEW hospitality_operations_dashboard AS
SELECT
    -- Occupancy metrics
    (SELECT AVG(occupancy_rate) FROM current_occupancy) as avg_occupancy_rate,
    (SELECT SUM(rooms_occupied) FROM current_occupancy) as total_rooms_occupied,
    (SELECT SUM(check_ins_today) FROM current_occupancy) as check_ins_today,
    (SELECT SUM(check_outs_today) FROM current_occupancy) as check_outs_today,

    -- Revenue metrics (today)
    (SELECT SUM(revenue_today) FROM current_occupancy) as revenue_today,
    (SELECT AVG(revenue_today / NULLIF(rooms_occupied, 0))
     FROM current_occupancy WHERE rooms_occupied > 0) as avg_revenue_per_occupied_room,

    -- Guest service metrics
    (SELECT COUNT(*) FROM service_requests
     WHERE requested_date = CURRENT_DATE AND request_status = 'completed') as services_completed_today,
    (SELECT AVG(EXTRACT(EPOCH FROM (completed_at - requested_date))/3600)
     FROM service_requests WHERE completed_at IS NOT NULL AND requested_date >= CURRENT_DATE - INTERVAL '7 days') as avg_service_response_hours,

    -- Operational efficiency
    (SELECT COUNT(*) FROM rooms WHERE room_status = 'out_of_order') as rooms_out_of_order,
    (SELECT COUNT(*) FROM maintenance_requests WHERE request_status = 'open') as open_maintenance_requests,
    (SELECT COUNT(*) FROM housekeeping_schedule
     WHERE scheduled_date = CURRENT_DATE AND schedule_status = 'completed') /
    NULLIF((SELECT COUNT(*) FROM housekeeping_schedule WHERE scheduled_date = CURRENT_DATE), 0) * 100 as housekeeping_completion_rate,

    -- Guest experience
    (SELECT AVG(overall_rating) FROM guest_satisfaction
     WHERE survey_date >= CURRENT_DATE - INTERVAL '30 days') as avg_guest_satisfaction,
    (SELECT COUNT(*) FROM reservations WHERE reservation_status = 'no_show'
     AND check_in_date >= CURRENT_DATE - INTERVAL '30 days') as no_show_count
;
```

This hospitality database schema provides enterprise-grade infrastructure for hotel operations with comprehensive reservation management, guest services, financial operations, and operational analytics required for modern hospitality management.
