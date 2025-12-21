# Travel & Tourism Database Design

## Overview

This comprehensive database schema supports travel agencies, online travel booking platforms, and tourism operations including destination management, supplier relationships, package creation, booking workflows, and customer service. The design handles complex multi-supplier itineraries, dynamic pricing, availability management, and comprehensive customer support.

## Key Features

### 🌍 Destination & Attraction Management
- **Global destination database** with geographic data and tourism information
- **Attraction catalog** with ratings, reviews, and operational details
- **Seasonal availability** and capacity management
- **Cultural and safety information** for informed travel planning

### ✈️ Supplier & Inventory Management
- **Multi-supplier ecosystem** including airlines, hotels, tour operators
- **Real-time availability** tracking across all service types
- **Contract and performance management** with supplier ratings
- **Dynamic pricing** and yield management capabilities

### 📦 Package & Itinerary Design
- **Flexible package creation** combining flights, hotels, activities
- **Day-by-day itineraries** with detailed scheduling and logistics
- **Customizable components** with optional add-ons and upgrades
- **Multi-destination routing** and complex travel planning

### 💺 Booking & Reservation Engine
- **Unified booking platform** for all travel services
- **Real-time inventory management** with overbooking protection
- **Multi-currency pricing** and payment processing
- **Automated confirmations** and supplier integrations

### 👥 Customer Experience Management
- **Personalized customer profiles** with preferences and history
- **Loyalty program integration** and VIP status management
- **Comprehensive customer support** with ticketing and resolution tracking
- **Review and feedback systems** for continuous improvement

## Database Schema Highlights

### Core Tables

#### Destination Management
- **`destinations`** - Geographic locations with tourism metadata and seasonal information
- **`attractions`** - Tourist attractions with ratings, amenities, and accessibility features
- **`suppliers`** - Service providers including airlines, hotels, and tour operators

#### Accommodation & Transportation
- **`accommodations`** - Hotel and lodging properties with room types and amenities
- **`room_types`** - Detailed room configurations with pricing and availability
- **`airlines`** - Airline information with fleet and service details
- **`flights`** - Flight schedules with real-time status and availability

#### Package Creation
- **`travel_packages`** - Pre-configured travel packages with pricing and inclusions
- **`package_itineraries`** - Day-by-day activity and accommodation scheduling
- **`rate_plans`** - Pricing strategies with seasonal adjustments and restrictions

#### Booking System
- **`customers`** - Traveler profiles with preferences and travel history
- **`bookings`** - Reservation records with financial and operational details
- **`booking_items`** - Individual service components within bookings

#### Customer Service
- **`support_tickets`** - Customer service requests with SLA tracking
- **`customer_reviews`** - Feedback and ratings for continuous improvement

## Key Design Patterns

### 1. Dynamic Availability Management
```sql
-- Check availability across multiple suppliers and services
CREATE OR REPLACE FUNCTION check_multi_service_availability(
    destination_uuid UUID,
    check_in_date DATE,
    check_out_date DATE,
    room_type_preferences VARCHAR[] DEFAULT ARRAY[]::VARCHAR[],
    budget_limit DECIMAL DEFAULT NULL
)
RETURNS TABLE (
    accommodation_name VARCHAR,
    room_type VARCHAR,
    available_rooms INTEGER,
    nightly_rate DECIMAL,
    total_cost DECIMAL,
    rating DECIMAL,
    distance_from_center DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        acc.property_name,
        rt.room_type_name,
        avail.available_rooms,
        rt.base_rate,
        rt.base_rate * (check_out_date - check_in_date),
        acc.star_rating,
        ST_Distance(acc.geolocation, dest.geolocation) / 1609.34 as distance_miles -- Convert meters to miles
    FROM accommodations acc
    JOIN destinations dest ON acc.destination_id = dest.destination_id
    JOIN room_types rt ON acc.accommodation_id = rt.accommodation_id
    CROSS JOIN LATERAL check_accommodation_availability(
        acc.accommodation_id, rt.room_type_id, check_in_date, check_out_date, 1
    ) avail
    WHERE acc.destination_id = destination_uuid
      AND acc.property_status = 'active'
      AND rt.room_type_status = 'active'
      AND avail.available_rooms > 0
      AND (array_length(room_type_preferences, 1) = 0 OR rt.room_type_name = ANY(room_type_preferences))
      AND (budget_limit IS NULL OR rt.base_rate * (check_out_date - check_in_date) <= budget_limit)
    ORDER BY rt.base_rate ASC, acc.star_rating DESC;
END;
$$ LANGUAGE plpgsql;
```

### 2. Package Pricing Engine with Seasonal Adjustments
```sql
-- Calculate dynamic package pricing with seasonal adjustments
CREATE OR REPLACE FUNCTION calculate_dynamic_package_price(
    package_uuid UUID,
    travel_date DATE,
    number_of_travelers INTEGER DEFAULT 2,
    add_ons JSONB DEFAULT '{}'
)
RETURNS TABLE (
    base_package_price DECIMAL,
    seasonal_adjustment DECIMAL,
    add_ons_total DECIMAL,
    taxes_and_fees DECIMAL,
    total_price DECIMAL,
    price_per_person DECIMAL,
    currency_code VARCHAR,
    pricing_breakdown JSONB
) AS $$
DECLARE
    package_record travel_packages%ROWTYPE;
    seasonal_multiplier DECIMAL := 1.0;
    base_price DECIMAL;
    add_ons_price DECIMAL := 0;
    tax_rate DECIMAL := 0.10; -- 10% tax
    breakdown JSONB := '{}';
BEGIN
    -- Get package details
    SELECT * INTO package_record FROM travel_packages WHERE package_id = package_uuid;

    -- Calculate base price
    base_price := package_record.base_price;
    IF package_record.price_per_person THEN
        base_price := base_price * number_of_travelers;
    END IF;

    -- Apply seasonal adjustments
    CASE EXTRACT(MONTH FROM travel_date)
        WHEN 6, 7, 8 THEN -- Summer peak
            seasonal_multiplier := 1.3;
        WHEN 12, 1, 2 THEN -- Winter holidays
            seasonal_multiplier := 1.25;
        WHEN 3, 4, 9, 10 THEN -- Shoulder seasons
            seasonal_multiplier := 1.1;
        ELSE -- Off-peak
            seasonal_multiplier := 0.9;
    END CASE;

    -- Calculate add-ons pricing
    IF add_ons ? 'insurance' THEN
        add_ons_price := add_ons_price + (50 * number_of_travelers);
    END IF;
    IF add_ons ? 'transfers' THEN
        add_ons_price := add_ons_price + 100;
    END IF;
    IF add_ons ? 'vip_services' THEN
        add_ons_price := add_ons_price + (200 * number_of_travelers);
    END IF;

    -- Build pricing breakdown
    breakdown := jsonb_build_object(
        'base_package', base_price,
        'seasonal_adjustment', base_price * (seasonal_multiplier - 1),
        'add_ons', add_ons_price,
        'subtotal_before_tax', (base_price * seasonal_multiplier) + add_ons_price,
        'taxes_and_fees', ((base_price * seasonal_multiplier) + add_ons_price) * tax_rate
    );

    RETURN QUERY SELECT
        base_price,
        base_price * (seasonal_multiplier - 1),
        add_ons_price,
        (base_price * seasonal_multiplier + add_ons_price) * tax_rate,
        (base_price * seasonal_multiplier + add_ons_price) * (1 + tax_rate),
        ((base_price * seasonal_multiplier + add_ons_price) * (1 + tax_rate)) / number_of_travelers,
        package_record.currency_code,
        breakdown;
END;
$$ LANGUAGE plpgsql;
```

### 3. Intelligent Itinerary Recommendations
```sql
-- Generate personalized itinerary recommendations based on preferences
CREATE OR REPLACE FUNCTION recommend_personalized_itinerary(
    destination_uuid UUID,
    traveler_type VARCHAR, -- 'family', 'business', 'adventure', 'cultural', 'relaxation'
    duration_days INTEGER DEFAULT 7,
    budget_level VARCHAR DEFAULT 'moderate', -- 'budget', 'moderate', 'luxury'
    interests VARCHAR[] DEFAULT ARRAY[]::VARCHAR[]
)
RETURNS TABLE (
    day_number INTEGER,
    recommended_activities JSONB,
    suggested_accommodation JSONB,
    estimated_daily_cost DECIMAL,
    total_itinerary_cost DECIMAL,
    confidence_score DECIMAL
) AS $$
DECLARE
    destination_record destinations%ROWTYPE;
    activity_preferences TEXT[];
    accommodation_budget DECIMAL;
    daily_budget DECIMAL;
BEGIN
    -- Get destination details
    SELECT * INTO destination_record FROM destinations WHERE destination_id = destination_uuid;

    -- Set preferences based on traveler type
    CASE traveler_type
        WHEN 'family' THEN
            activity_preferences := ARRAY['theme_park', 'museum', 'zoo', 'beach', 'shopping'];
        WHEN 'business' THEN
            activity_preferences := ARRAY['business_center', 'conference', 'networking'];
        WHEN 'adventure' THEN
            activity_preferences := ARRAY['mountain', 'sports_venue', 'natural_wonder'];
        WHEN 'cultural' THEN
            activity_preferences := ARRAY['historical_site', 'museum', 'religious_site'];
        WHEN 'relaxation' THEN
            activity_preferences := ARRAY['beach', 'spa', 'resort'];
        ELSE
            activity_preferences := interests;
    END CASE;

    -- Set budget levels
    CASE budget_level
        WHEN 'budget' THEN accommodation_budget := 100; daily_budget := 50;
        WHEN 'moderate' THEN accommodation_budget := 200; daily_budget := 100;
        WHEN 'luxury' THEN accommodation_budget := 500; daily_budget := 300;
    END CASE;

    -- Generate day-by-day recommendations
    FOR day IN 1..duration_days LOOP
        RETURN QUERY
        SELECT
            day,
            -- Recommended activities for the day
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'attraction_id', a.attraction_id,
                    'name', a.attraction_name,
                    'type', a.attraction_type,
                    'rating', a.average_rating,
                    'duration', a.duration_minutes,
                    'cost', a.ticket_price
                )
            )
            FROM attractions a
            WHERE a.destination_id = destination_uuid
              AND a.attraction_status = 'active'
              AND a.attraction_type = ANY(activity_preferences)
            ORDER BY a.average_rating DESC, a.popularity_score DESC
            LIMIT 3),

            -- Suggested accommodation
            (SELECT jsonb_build_object(
                'accommodation_id', acc.accommodation_id,
                'name', acc.property_name,
                'rating', acc.star_rating,
                'estimated_cost', rt.base_rate
            )
            FROM accommodations acc
            JOIN room_types rt ON acc.accommodation_id = rt.accommodation_id
            WHERE acc.destination_id = destination_uuid
              AND acc.property_status = 'active'
              AND rt.base_rate <= accommodation_budget
            ORDER BY acc.star_rating DESC, rt.base_rate ASC
            LIMIT 1),

            daily_budget,
            daily_budget * duration_days + (accommodation_budget * duration_days),
            0.85; -- Confidence score
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 4. Customer Support Automation
```sql
-- Automated support ticket routing and SLA management
CREATE OR REPLACE FUNCTION process_support_ticket(
    customer_uuid UUID,
    booking_uuid UUID,
    ticket_details JSONB
)
RETURNS TABLE (
    ticket_id UUID,
    ticket_number VARCHAR,
    assigned_agent UUID,
    estimated_resolution_time INTERVAL,
    priority_level VARCHAR,
    escalation_required BOOLEAN
) AS $$
DECLARE
    ticket_uuid UUID;
    ticket_number_gen VARCHAR;
    priority VARCHAR;
    escalation_needed BOOLEAN := FALSE;
    estimated_resolution INTERVAL;
    assigned_agent_uuid UUID;
BEGIN
    -- Determine priority based on ticket type and customer status
    CASE ticket_details->>'ticket_type'
        WHEN 'medical_emergency' THEN
            priority := 'urgent';
            escalation_needed := TRUE;
            estimated_resolution := INTERVAL '1 hour';
        WHEN 'lost_luggage', 'flight_cancellation' THEN
            priority := 'high';
            estimated_resolution := INTERVAL '4 hours';
        WHEN 'booking_change', 'complaint' THEN
            priority := 'medium';
            estimated_resolution := INTERVAL '24 hours';
        ELSE
            priority := 'low';
            estimated_resolution := INTERVAL '48 hours';
    END CASE;

    -- Check customer VIP status
    IF EXISTS (SELECT 1 FROM customers WHERE customer_id = customer_uuid AND vip_status = TRUE) THEN
        priority := CASE WHEN priority = 'low' THEN 'medium' ELSE 'high' END;
        estimated_resolution := estimated_resolution / 2;
    END IF;

    -- Check booking urgency (departure within 24 hours)
    IF booking_uuid IS NOT NULL AND EXISTS (
        SELECT 1 FROM bookings
        WHERE booking_id = booking_uuid
          AND departure_date <= CURRENT_DATE + INTERVAL '1 day'
    ) THEN
        priority := 'high';
        estimated_resolution := estimated_resolution / 2;
    END IF;

    -- Generate ticket number
    ticket_number_gen := 'TKT-' || UPPER(SUBSTRING(uuid_generate_v4()::TEXT, 1, 8));

    -- Assign agent based on priority and department
    SELECT agent_id INTO assigned_agent_uuid
    FROM support_agents
    WHERE department = ticket_details->>'department'
      AND current_workload < max_workload
      AND (priority = 'urgent' OR specialization = ticket_details->>'ticket_type')
    ORDER BY current_workload ASC
    LIMIT 1;

    -- Create ticket
    INSERT INTO support_tickets (
        customer_id, booking_id, ticket_number, ticket_type, ticket_priority,
        subject, description, assigned_agent, department
    ) VALUES (
        customer_uuid, booking_uuid, ticket_number_gen,
        ticket_details->>'ticket_type', priority,
        ticket_details->>'subject', ticket_details->>'description',
        assigned_agent_uuid, ticket_details->>'department'
    ) RETURNING ticket_id INTO ticket_uuid;

    -- Update agent workload
    IF assigned_agent_uuid IS NOT NULL THEN
        UPDATE support_agents SET current_workload = current_workload + 1
        WHERE agent_id = assigned_agent_uuid;
    END IF;

    RETURN QUERY SELECT
        ticket_uuid,
        ticket_number_gen,
        assigned_agent_uuid,
        estimated_resolution,
        priority,
        escalation_needed;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition bookings by month for performance
CREATE TABLE bookings PARTITION BY RANGE (booking_date);

CREATE TABLE bookings_2024_01 PARTITION OF bookings
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition customer reviews by year
CREATE TABLE customer_reviews PARTITION BY RANGE (created_at);

CREATE TABLE customer_reviews_2024 PARTITION OF customer_reviews
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- Partition support tickets by month
CREATE TABLE support_tickets PARTITION BY RANGE (created_at);

CREATE TABLE support_tickets_2024_01 PARTITION OF support_tickets
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

### Advanced Indexing
```sql
-- Composite indexes for booking queries
CREATE INDEX idx_bookings_customer_date ON bookings (customer_id, booking_date DESC, departure_date);
CREATE INDEX idx_bookings_status_departure ON bookings (booking_status, departure_date);

-- Spatial indexes for location-based searches
CREATE INDEX idx_destinations_geolocation ON destinations USING gist (geolocation);
CREATE INDEX idx_attractions_geolocation ON attractions USING gist (geolocation);
CREATE INDEX idx_accommodations_geolocation ON accommodations USING gist (geolocation);

-- Full-text search for destinations and attractions
CREATE INDEX idx_destinations_search ON destinations USING gin (to_tsvector('english', destination_name || ' ' || description));
CREATE INDEX idx_attractions_search ON attractions USING gin (to_tsvector('english', attraction_name || ' ' || description));

-- Partial indexes for active records
CREATE INDEX idx_active_packages ON travel_packages (package_id) WHERE package_status = 'active';
CREATE INDEX idx_available_flights ON flights (flight_id) WHERE flight_status = 'scheduled' AND available_seats > 0;

-- JSONB indexes for flexible queries
CREATE INDEX idx_booking_items_services ON booking_items USING gin ((item_details::jsonb));
CREATE INDEX idx_support_tickets_metadata ON support_tickets USING gin ((ticket_metadata::jsonb));
```

### Materialized Views for Analytics
```sql
-- Real-time booking dashboard
CREATE MATERIALIZED VIEW booking_dashboard AS
SELECT
    DATE_TRUNC('day', b.booking_date) as booking_date,

    -- Booking metrics
    COUNT(b.booking_id) as total_bookings,
    COUNT(CASE WHEN b.booking_status = 'confirmed' THEN 1 END) as confirmed_bookings,
    SUM(b.total_amount) as total_revenue,
    AVG(b.total_amount) as avg_booking_value,

    -- Customer metrics
    COUNT(DISTINCT b.customer_id) as unique_customers,
    COUNT(DISTINCT CASE WHEN c.created_at >= DATE_TRUNC('month', CURRENT_DATE) THEN b.customer_id END) as new_customers,

    -- Channel performance
    COUNT(CASE WHEN b.booking_type = 'package' THEN 1 END) as package_bookings,
    COUNT(CASE WHEN b.booking_type = 'flight_only' THEN 1 END) as flight_bookings,
    COUNT(CASE WHEN b.booking_type = 'hotel_only' THEN 1 END) as hotel_bookings,

    -- Geographic performance
    jsonb_object_agg(d.country, COUNT(*)) FILTER (WHERE d.country IS NOT NULL) as bookings_by_country,

    -- Cancellation metrics
    ROUND(
        COUNT(CASE WHEN b.booking_status = 'cancelled' THEN 1 END)::DECIMAL /
        NULLIF(COUNT(b.booking_id), 0) * 100, 2
    ) as cancellation_rate

FROM bookings b
LEFT JOIN customers c ON b.customer_id = c.customer_id
LEFT JOIN booking_items bi ON b.booking_id = bi.booking_id
LEFT JOIN accommodations acc ON bi.accommodation_id = acc.accommodation_id
LEFT JOIN destinations d ON acc.destination_id = d.destination_id
WHERE b.booking_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY DATE_TRUNC('day', b.booking_date)
ORDER BY booking_date DESC;

-- Refresh hourly
CREATE UNIQUE INDEX idx_booking_dashboard_date ON booking_dashboard (booking_date);
REFRESH MATERIALIZED VIEW CONCURRENTLY booking_dashboard;
```

## Security Considerations

### Access Control
```sql
-- Role-based security for travel operations
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY booking_access_policy ON bookings
    FOR ALL USING (
        customer_id = current_setting('app.customer_id')::UUID OR
        agent_id = current_setting('app.agent_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('travel_agent', 'admin') OR
        EXISTS (
            SELECT 1 FROM booking_items bi
            JOIN accommodations acc ON bi.accommodation_id = acc.accommodation_id
            JOIN suppliers s ON acc.supplier_id = s.supplier_id
            WHERE bi.booking_id = bookings.booking_id
              AND s.contact_person = current_setting('app.user_email')::TEXT
        )
    );

CREATE POLICY customer_privacy_policy ON customers
    FOR SELECT USING (
        customer_id = current_setting('app.customer_id')::UUID OR
        current_setting('app.user_role')::TEXT IN ('agent', 'admin') OR
        current_setting('app.has_customer_data_access')::BOOLEAN = TRUE
    );
```

### Data Encryption
```sql
-- Encrypt sensitive customer and payment information
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypt passport and payment data
CREATE OR REPLACE FUNCTION encrypt_sensitive_data(sensitive_text TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(sensitive_text, current_setting('travel.encryption_key'));
END;
$$ LANGUAGE plpgsql;

-- Mask sensitive data in logs and reports
CREATE OR REPLACE FUNCTION mask_personal_data(original_text TEXT, data_type VARCHAR)
RETURNS TEXT AS $$
BEGIN
    CASE data_type
        WHEN 'passport' THEN
            RETURN LEFT(original_text, 2) || REPEAT('*', LENGTH(original_text) - 6) || RIGHT(original_text, 4);
        WHEN 'phone' THEN
            RETURN LEFT(original_text, 3) || REPEAT('*', LENGTH(original_text) - 6) || RIGHT(original_text, 3);
        WHEN 'email' THEN
            RETURN LEFT(SPLIT_PART(original_text, '@', 1), 2) || REPEAT('*', LENGTH(SPLIT_PART(original_text, '@', 1)) - 2) || '@' || SPLIT_PART(original_text, '@', 2);
        ELSE
            RETURN original_text;
    END CASE;
END;
$$ LANGUAGE plpgsql;
```

### Audit Trail
```sql
-- Comprehensive travel booking audit logging
CREATE TABLE travel_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    customer_id UUID,
    booking_id UUID,
    session_id TEXT,
    ip_address INET,
    user_agent TEXT,
    change_reason TEXT,
    privacy_impact VARCHAR(20) CHECK (privacy_impact IN ('high', 'medium', 'low', 'none')),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Audit trigger for booking operations
CREATE OR REPLACE FUNCTION travel_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO travel_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, customer_id, booking_id, session_id, ip_address, user_agent,
        privacy_impact
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME IN ('bookings', 'customers') THEN COALESCE(NEW.customer_id, OLD.customer_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME LIKE '%booking%' THEN COALESCE(NEW.booking_id, OLD.booking_id) ELSE NULL END,
        current_setting('app.session_id', TRUE)::TEXT,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE
            WHEN TG_TABLE_NAME = 'customers' THEN 'high'
            WHEN TG_TABLE_NAME LIKE '%booking%' THEN 'medium'
            WHEN TG_TABLE_NAME LIKE '%payment%' THEN 'high'
            ELSE 'low'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### GDPR Compliance for Travel Data
```sql
-- Handle GDPR data subject access requests
CREATE OR REPLACE FUNCTION process_gdpr_sar(
    customer_uuid UUID,
    request_type VARCHAR  -- 'access', 'rectify', 'erase', 'portability'
)
RETURNS TABLE (
    request_id UUID,
    processing_status VARCHAR,
    data_extracted JSONB,
    records_affected INTEGER,
    completion_estimate INTERVAL
) AS $$
DECLARE
    request_uuid UUID;
    extracted_data JSONB := '{}';
    affected_count INTEGER := 0;
BEGIN
    -- Create GDPR request record
    INSERT INTO gdpr_requests (
        customer_id, request_type, request_status
    ) VALUES (
        customer_uuid, request_type, 'processing'
    ) RETURNING request_id INTO request_uuid;

    CASE request_type
        WHEN 'access' THEN
            -- Extract all customer data
            SELECT jsonb_build_object(
                'personal_data', to_jsonb(c.*),
                'bookings', jsonb_agg(to_jsonb(b.*)),
                'reviews', jsonb_agg(to_jsonb(cr.*)),
                'support_tickets', jsonb_agg(to_jsonb(st.*))
            ) INTO extracted_data
            FROM customers c
            LEFT JOIN bookings b ON c.customer_id = b.customer_id
            LEFT JOIN customer_reviews cr ON c.customer_id = cr.customer_id
            LEFT JOIN support_tickets st ON c.customer_id = st.customer_id
            WHERE c.customer_id = customer_uuid
            GROUP BY c.customer_id;

            affected_count := 1;

        WHEN 'erase' THEN
            -- Soft delete customer data
            UPDATE customers SET
                email = 'erased@gdpr.com',
                phone = NULL,
                passport_number = NULL,
                gdpr_erased = TRUE,
                erased_at = CURRENT_TIMESTAMP
            WHERE customer_id = customer_uuid;

            -- Anonymize historical data
            UPDATE bookings SET
                special_requests = 'Personal data erased per GDPR',
                customer_notes = NULL
            WHERE customer_id = customer_uuid;

            affected_count := jsonb_array_length(extracted_data->'bookings') +
                            jsonb_array_length(extracted_data->'reviews') +
                            jsonb_array_length(extracted_data->'support_tickets');

        WHEN 'rectify' THEN
            -- Update customer data (implementation would depend on specific rectification request)
            affected_count := 1;

        WHEN 'portability' THEN
            -- Export data in portable format
            extracted_data := jsonb_build_object(
                'export_format', 'GDPR_Portability_JSON',
                'export_date', CURRENT_TIMESTAMP,
                'data', extracted_data
            );
            affected_count := 1;
    END CASE;

    -- Update request status
    UPDATE gdpr_requests SET
        request_status = 'completed',
        completed_at = CURRENT_TIMESTAMP,
        records_affected = affected_count
    WHERE request_id = request_uuid;

    RETURN QUERY SELECT
        request_uuid,
        'completed'::VARCHAR,
        extracted_data,
        affected_count,
        INTERVAL '0 hours';
END;
$$ LANGUAGE plpgsql;
```

### Travel Industry Regulations
```sql
-- Compliance monitoring for travel regulations
CREATE OR REPLACE FUNCTION check_travel_compliance(
    booking_uuid UUID
)
RETURNS TABLE (
    compliance_status VARCHAR,
    compliance_issues JSONB,
    required_actions JSONB,
    risk_level VARCHAR
) AS $$
DECLARE
    booking_record bookings%ROWTYPE;
    customer_record customers%ROWTYPE;
    issues JSONB := '[]';
    actions JSONB := '[]';
    risk VARCHAR := 'low';
BEGIN
    -- Get booking and customer details
    SELECT * INTO booking_record FROM bookings WHERE booking_id = booking_uuid;
    SELECT * INTO customer_record FROM customers WHERE customer_id = booking_record.customer_id;

    -- Check passport validity
    IF customer_record.passport_expiry <= booking_record.return_date + INTERVAL '6 months' THEN
        issues := issues || jsonb_build_object(
            'type', 'passport_expiry',
            'severity', 'high',
            'message', 'Passport expires within 6 months of return date'
        );
        actions := actions || jsonb_build_object(
            'action', 'renew_passport',
            'priority', 'urgent',
            'deadline', booking_record.departure_date - INTERVAL '30 days'
        );
        risk := 'high';
    END IF;

    -- Check visa requirements
    IF EXISTS (
        SELECT 1 FROM booking_items bi
        JOIN accommodations acc ON bi.accommodation_id = acc.accommodation_id
        JOIN destinations d ON acc.destination_id = d.destination_id
        WHERE bi.booking_id = booking_uuid
          AND d.visa_requirements IS NOT NULL
          AND customer_record.nationality NOT IN (
              SELECT unnest(string_to_array(d.visa_free_countries, ','))
          )
    ) THEN
        issues := issues || jsonb_build_object(
            'type', 'visa_required',
            'severity', 'high',
            'message', 'Visa required for destination'
        );
        actions := actions || jsonb_build_object(
            'action', 'obtain_visa',
            'priority', 'high',
            'deadline', booking_record.departure_date - INTERVAL '60 days'
        );
        risk := GREATEST(risk, 'high');
    END IF;

    -- Check health requirements
    IF EXISTS (
        SELECT 1 FROM booking_items bi
        JOIN accommodations acc ON bi.accommodation_id = acc.accommodation_id
        JOIN destinations d ON acc.destination_id = d.destination_id
        WHERE bi.booking_id = booking_uuid
          AND d.health_requirements IS NOT NULL
    ) THEN
        issues := issues || jsonb_build_object(
            'type', 'health_requirements',
            'severity', 'medium',
            'message', 'Health requirements for destination'
        );
        actions := actions || jsonb_build_object(
            'action', 'check_vaccinations',
            'priority', 'medium',
            'deadline', booking_record.departure_date - INTERVAL '30 days'
        );
    END IF;

    RETURN QUERY SELECT
        CASE WHEN jsonb_array_length(issues) = 0 THEN 'compliant' ELSE 'non_compliant' END,
        issues,
        actions,
        risk;
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Global Distribution Systems (GDS)** for airline and hotel inventory
- **Payment gateways** for secure transaction processing
- **Identity verification services** for KYC and compliance
- **Weather APIs** for travel planning and alerts

### API Endpoints
- **Search and booking APIs** for real-time availability and reservations
- **Supplier integration APIs** for inventory synchronization
- **Customer service APIs** for support ticket management
- **Analytics APIs** for business intelligence and reporting

## Monitoring & Analytics

### Key Performance Indicators
- **Booking conversion rates** and revenue per available inventory
- **Customer satisfaction scores** and Net Promoter Score
- **Supplier performance metrics** and on-time delivery rates
- **Cancellation and no-show rates** with trend analysis
- **Geographic demand patterns** and seasonal performance

### Real-Time Dashboards
```sql
-- Travel operations dashboard
CREATE VIEW travel_operations_dashboard AS
SELECT
    -- Booking performance (today)
    (SELECT COUNT(*) FROM bookings WHERE DATE(booking_date) = CURRENT_DATE) as bookings_today,
    (SELECT SUM(total_amount) FROM bookings WHERE DATE(booking_date) = CURRENT_DATE) as revenue_today,
    (SELECT AVG(total_amount) FROM bookings WHERE DATE(booking_date) = CURRENT_DATE) as avg_booking_value_today,

    -- Inventory status
    (SELECT COUNT(*) FROM accommodations WHERE property_status = 'active') as active_properties,
    (SELECT COUNT(*) FROM flights WHERE flight_status = 'scheduled' AND departure_date >= CURRENT_DATE) as upcoming_flights,
    (SELECT AVG(available_seats) FROM flights WHERE flight_status = 'scheduled' AND departure_date = CURRENT_DATE) as avg_available_seats,

    -- Customer service metrics
    (SELECT COUNT(*) FROM support_tickets WHERE ticket_status = 'open') as open_support_tickets,
    (SELECT AVG(EXTRACT(EPOCH FROM (resolved_at - created_at))/3600)
     FROM support_tickets WHERE resolved_at IS NOT NULL AND created_at >= CURRENT_DATE - INTERVAL '7 days') as avg_resolution_time_hours,

    -- Quality metrics
    (SELECT AVG(overall_rating) FROM customer_reviews WHERE created_at >= CURRENT_DATE - INTERVAL '30 days') as avg_customer_rating,
    (SELECT COUNT(*) FROM bookings WHERE booking_status = 'cancelled' AND booking_date >= CURRENT_DATE - INTERVAL '7 days') /
    NULLIF((SELECT COUNT(*) FROM bookings WHERE booking_date >= CURRENT_DATE - INTERVAL '7 days'), 0) * 100 as cancellation_rate_percent,

    -- Geographic performance
    (SELECT jsonb_object_agg(country, booking_count)
     FROM (SELECT d.country, COUNT(b.booking_id) as booking_count
           FROM bookings b
           JOIN booking_items bi ON b.booking_id = bi.booking_id
           JOIN accommodations acc ON bi.accommodation_id = acc.accommodation_id
           JOIN destinations d ON acc.destination_id = d.destination_id
           WHERE b.booking_date >= CURRENT_DATE - INTERVAL '30 days'
           GROUP BY d.country) subq) as bookings_by_country
;
```

This travel database schema provides enterprise-grade infrastructure for travel booking platforms, destination management, supplier relationships, and comprehensive customer service operations required for modern travel and tourism businesses.
