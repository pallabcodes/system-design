# Event Management Database Design

## Overview

This comprehensive database schema supports event planning, ticketing, venue management, registration systems, and post-event analytics. The design handles complex event workflows from initial planning through execution and evaluation, supporting everything from small workshops to large-scale conferences.

## Key Features

### 🏟️ Venue and Space Management
- **Multi-venue facility management** with space allocation and scheduling
- **Geospatial venue mapping** with capacity planning and accessibility features
- **Dynamic pricing and availability** with blackout dates and maintenance scheduling
- **Equipment and amenity tracking** with setup requirements and restrictions

### 🎫 Registration and Ticketing
- **Multi-tier ticketing systems** with dynamic pricing and early bird discounts
- **Waitlist management** with automated notifications and conversions
- **Payment processing integration** with refunds and transfers
- **Attendee management** with dietary restrictions and accessibility needs

### 📊 Event Analytics and Reporting
- **Real-time attendance tracking** with engagement metrics and location data
- **Post-event analytics** with ROI calculation and performance reporting
- **Registration funnel analysis** with conversion tracking and abandonment rates
- **Financial performance** with budget vs actual analysis and profitability metrics

### 🎤 Speaker and Content Management
- **Speaker recruitment and management** with contracts and compensation tracking
- **Session scheduling and coordination** with AV requirements and timing
- **Content management** with presentation materials and speaker evaluations
- **Speaker performance analytics** with ratings and engagement metrics

## Database Schema Highlights

### Core Tables

#### Venue Management
- **`venues`** - Facility profiles with capacity, amenities, and operational details
- **`venue_spaces`** - Individual rooms/areas with capacity and equipment specifications

#### Event Planning
- **`events`** - Event master records with scheduling, capacity, and budget information
- **`event_sessions`** - Individual sessions with speakers, timing, and logistics
- **`ticket_types`** - Pricing tiers with availability and access levels

#### Registration System
- **`registrations`** - Attendee registrations with payment and status tracking
- **`waitlists`** - Waitlist management with position tracking and notifications

#### Speaker Management
- **`speakers`** - Speaker profiles with expertise, availability, and compensation
- **`speaker_assignments`** - Session assignments with contracts and logistics

## Key Design Patterns

### 1. Dynamic Venue Capacity and Pricing Optimization
```sql
-- Intelligent venue pricing based on demand, seasonality, and utilization
CREATE OR REPLACE FUNCTION optimize_venue_pricing(
    venue_uuid UUID,
    event_date DATE,
    event_type VARCHAR,
    expected_attendance INTEGER
)
RETURNS TABLE (
    venue_space_id UUID,
    space_name VARCHAR,
    base_rate DECIMAL,
    optimized_rate DECIMAL,
    availability_confidence DECIMAL,
    demand_multiplier DECIMAL,
    seasonal_adjustment DECIMAL,
    final_recommended_rate DECIMAL,
    reasoning TEXT
) AS $$
DECLARE
    venue_record venues%ROWTYPE;
    space_record RECORD;
    days_to_event INTEGER;
    seasonal_factor DECIMAL := 1.0;
    demand_factor DECIMAL := 1.0;
BEGIN
    -- Get venue details
    SELECT * INTO venue_record FROM venues WHERE venue_id = venue_uuid;

    -- Calculate days to event
    days_to_event := EXTRACT(EPOCH FROM (event_date - CURRENT_DATE)) / 86400;

    -- Calculate seasonal factors
    CASE EXTRACT(MONTH FROM event_date)
        WHEN 12, 1, 2 THEN seasonal_factor := 1.3; -- Winter holiday season
        WHEN 3, 4, 5 THEN seasonal_factor := 0.9;  -- Spring shoulder season
        WHEN 6, 7, 8 THEN seasonal_factor := 1.4;  -- Summer peak season
        WHEN 9, 10, 11 THEN seasonal_factor := 1.1; -- Fall back-to-school
        ELSE seasonal_factor := 1.0;
    END CASE;

    -- Calculate demand factors based on event type and timing
    CASE
        WHEN days_to_event < 30 AND event_type IN ('conference', 'concert', 'wedding') THEN demand_factor := 1.25;
        WHEN days_to_event < 14 THEN demand_factor := 1.4;
        WHEN days_to_event > 90 THEN demand_factor := 0.85;
        ELSE demand_factor := 1.0;
    END CASE;

    FOR space_record IN
        SELECT
            vs.space_id,
            vs.space_name,
            vs.base_rate_per_hour,
            vs.capacity,

            -- Calculate current utilization for the date
            (SELECT COUNT(*) FROM event_sessions es
             JOIN events e ON es.event_id = e.event_id
             WHERE es.venue_space_id = vs.space_id
               AND e.start_date = event_date) as current_bookings,

            -- Calculate historical utilization patterns
            (SELECT AVG(booking_count) FROM (
                SELECT COUNT(*) as booking_count
                FROM event_sessions es2
                JOIN events e2 ON es2.event_id = e2.event_id
                WHERE es2.venue_space_id = vs.space_id
                  AND EXTRACT(DOW FROM e2.start_date) = EXTRACT(DOW FROM event_date)
                  AND e2.start_date >= CURRENT_DATE - INTERVAL '6 months'
                GROUP BY e2.start_date
            ) historical) as avg_historical_utilization

        FROM venue_spaces vs
        WHERE vs.venue_id = venue_uuid
          AND vs.space_id NOT IN (
              SELECT venue_space_id FROM event_sessions es
              JOIN events e ON es.event_id = e.event_id
              WHERE e.start_date = event_date
                AND es.venue_space_id IS NOT NULL
          )
    LOOP
        DECLARE
            utilization_rate DECIMAL;
            availability_conf DECIMAL;
            optimized_rate DECIMAL;
            reasoning_text TEXT;
        BEGIN
            -- Calculate utilization rate
            utilization_rate := COALESCE(space_record.current_bookings::DECIMAL / 10, 0); -- Assuming 10 possible booking slots per day

            -- Calculate availability confidence
            availability_conf := GREATEST(0, 1 - utilization_rate);

            -- Calculate optimized rate
            optimized_rate := space_record.base_rate_per_hour * seasonal_factor * demand_factor;

            -- Adjust for utilization
            IF utilization_rate > 0.8 THEN
                optimized_rate := optimized_rate * 1.2; -- Premium for high demand
                reasoning_text := 'High demand - premium pricing applied';
            ELSIF utilization_rate < 0.3 THEN
                optimized_rate := optimized_rate * 0.9; -- Discount for low demand
                reasoning_text := 'Low demand - promotional discount applied';
            ELSE
                reasoning_text := 'Standard market rate based on demand and seasonality';
            END IF;

            -- Adjust for capacity utilization
            IF expected_attendance > space_record.capacity * 0.9 THEN
                optimized_rate := optimized_rate * 1.1; -- Capacity premium
                reasoning_text := reasoning_text || ' - capacity utilization premium added';
            END IF;

            RETURN QUERY SELECT
                space_record.space_id,
                space_record.space_name,
                space_record.base_rate_per_hour,
                ROUND(optimized_rate, 2),
                ROUND(availability_conf * 100, 1),
                ROUND(demand_factor, 2),
                ROUND(seasonal_factor, 2),
                ROUND(optimized_rate, 2),
                reasoning_text;
        END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 2. Real-Time Event Attendance and Engagement Tracking
```sql
-- Advanced attendance tracking with engagement analytics and predictive modeling
CREATE OR REPLACE FUNCTION track_event_engagement(event_uuid UUID)
RETURNS TABLE (
    session_id UUID,
    session_name VARCHAR,
    attendance_count INTEGER,
    engagement_score DECIMAL,
    drop_off_rate DECIMAL,
    peak_attendance_time TIME,
    demographic_distribution JSONB,
    interaction_hotspots JSONB,
    satisfaction_prediction DECIMAL,
    recommendations JSONB
) AS $$
DECLARE
    session_record RECORD;
BEGIN
    FOR session_record IN
        SELECT
            es.session_id,
            es.session_name,
            es.session_date,
            es.start_time,
            es.end_time,
            es.max_capacity,

            -- Attendance metrics
            COUNT(at.tracking_id) as total_attendees,
            COUNT(CASE WHEN at.check_in_time IS NOT NULL THEN 1 END) as checked_in,
            AVG(EXTRACT(EPOCH FROM (at.check_out_time - at.check_in_time)) / 60) as avg_duration_minutes,

            -- Engagement metrics
            SUM(at.interactions_count) as total_interactions,
            AVG(at.interactions_count) as avg_interactions_per_attendee,
            COUNT(at.tracking_id) FILTER (WHERE at.duration_minutes > 45) as engaged_attendees,

            -- Location tracking (simplified)
            jsonb_agg(at.location_coordinates) FILTER (WHERE at.location_coordinates IS NOT NULL) as location_data

        FROM event_sessions es
        LEFT JOIN attendance_tracking at ON es.session_id = at.session_id
        WHERE es.event_id = event_uuid
        GROUP BY es.session_id, es.session_name, es.session_date, es.start_time, es.end_time, es.max_capacity
    LOOP
        DECLARE
            engagement_score_val DECIMAL;
            drop_off_rate_val DECIMAL;
            peak_time TIME;
            demographic_data JSONB;
            interaction_data JSONB;
            satisfaction_pred DECIMAL;
            recommendations_val JSONB;
        BEGIN
            -- Calculate engagement score (0-100)
            engagement_score_val := LEAST(
                (
                    -- Attendance rate (30%)
                    (session_record.checked_in::DECIMAL / NULLIF(session_record.total_attendees, 0)) * 30 +
                    -- Duration engagement (25%)
                    (session_record.engaged_attendees::DECIMAL / NULLIF(session_record.checked_in, 0)) * 25 +
                    -- Interaction level (25%)
                    LEAST(session_record.avg_interactions_per_attendee / 5 * 25, 25) +
                    -- Capacity utilization (20%)
                    (session_record.checked_in::DECIMAL / NULLIF(session_record.max_capacity, 0)) * 20
                ), 100
            );

            -- Calculate drop-off rate
            drop_off_rate_val := (
                1 - (session_record.checked_in::DECIMAL / NULLIF(session_record.total_attendees, 0))
            ) * 100;

            -- Find peak attendance time (simplified)
            SELECT start_time + INTERVAL '30 minutes' INTO peak_time
            FROM event_sessions WHERE session_id = session_record.session_id;

            -- Demographic distribution (from registrations)
            SELECT jsonb_build_object(
                'age_groups', jsonb_build_object(
                    '18-24', COUNT(CASE WHEN EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM r.registration_date) BETWEEN 18 AND 24 THEN 1 END),
                    '25-34', COUNT(CASE WHEN EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM r.registration_date) BETWEEN 25 AND 34 THEN 1 END),
                    '35-44', COUNT(CASE WHEN EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM r.registration_date) BETWEEN 35 AND 44 THEN 1 END),
                    '45+', COUNT(CASE WHEN EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM r.registration_date) >= 45 THEN 1 END)
                ),
                'registration_sources', jsonb_object_agg(
                    COALESCE(r.registration_source, 'unknown'),
                    COUNT(*)
                )
            ) INTO demographic_data
            FROM registrations r
            WHERE r.event_id = event_uuid;

            -- Interaction hotspots analysis
            interaction_data := jsonb_build_object(
                'networking_zones', jsonb_build_array('Lobby', 'Refreshment Area'),
                'content_engagement', jsonb_build_object('peak_times', jsonb_build_array('10:00', '14:00')),
                'popular_sessions', jsonb_build_array(session_record.session_name)
            );

            -- Predict satisfaction based on engagement
            satisfaction_pred := 2.5 + (engagement_score_val / 100) * 2.5; -- Scale to 1-5 range

            -- Generate recommendations
            recommendations_val := jsonb_build_array();

            IF drop_off_rate_val > 20 THEN
                recommendations_val := recommendations_val || jsonb_build_object(
                    'type', 'engagement',
                    'priority', 'high',
                    'action', 'Implement interactive elements and Q&A sessions to reduce drop-off'
                );
            END IF;

            IF engagement_score_val < 60 THEN
                recommendations_val := recommendations_val || jsonb_build_object(
                    'type', 'content',
                    'priority', 'medium',
                    'action', 'Review session content and delivery methods for future events'
                );
            END IF;

            IF session_record.checked_in < session_record.max_capacity * 0.7 THEN
                recommendations_val := recommendations_val || jsonb_build_object(
                    'type', 'marketing',
                    'priority', 'medium',
                    'action', 'Enhance promotion strategies to improve attendance rates'
                );
            END IF;

            RETURN QUERY SELECT
                session_record.session_id,
                session_record.session_name,
                session_record.checked_in,
                ROUND(engagement_score_val, 1),
                ROUND(drop_off_rate_val, 1),
                peak_time,
                demographic_data,
                interaction_data,
                ROUND(satisfaction_pred, 1),
                recommendations_val;
        END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 3. Automated Event Financial Forecasting and Budget Optimization
```sql
-- Predictive financial modeling for event planning and budget optimization
CREATE OR REPLACE FUNCTION forecast_event_financials(event_uuid UUID)
RETURNS TABLE (
    forecast_category VARCHAR,
    conservative_estimate DECIMAL,
    expected_estimate DECIMAL,
    optimistic_estimate DECIMAL,
    confidence_level DECIMAL,
    key_assumptions JSONB,
    risk_factors JSONB,
    mitigation_strategies JSONB
) AS $$
DECLARE
    event_record events%ROWTYPE;
    historical_data RECORD;
    market_factors RECORD;
BEGIN
    -- Get event details
    SELECT * INTO event_record FROM events WHERE event_id = event_uuid;

    -- Get historical data from similar events
    SELECT
        AVG(actual_revenue) as avg_revenue,
        STDDEV(actual_revenue) as revenue_stddev,
        AVG(actual_cost) as avg_cost,
        STDDEV(actual_cost) as cost_stddev,
        COUNT(*) as similar_events_count
    INTO historical_data
    FROM events e
    WHERE e.event_type = event_record.event_type
      AND e.start_date >= CURRENT_DATE - INTERVAL '2 years'
      AND e.event_status = 'completed'
      AND e.event_id != event_uuid;

    -- Market factors
    market_factors := jsonb_build_object(
        'seasonal_multiplier', CASE EXTRACT(MONTH FROM event_record.start_date)
            WHEN 12,1,2 THEN 0.9 WHEN 6,7,8 THEN 1.1 ELSE 1.0 END,
        'economic_indicator', 1.02, -- GDP growth factor
        'competition_factor', 0.98  -- Local competition impact
    );

    -- Revenue Forecast
    RETURN QUERY SELECT
        'Revenue Forecast'::VARCHAR,
        -- Conservative: historical average - 1 stddev
        GREATEST(historical_data.avg_revenue - historical_data.revenue_stddev, 0) *
        (market_factors->>'seasonal_multiplier')::DECIMAL *
        (market_factors->>'economic_indicator')::DECIMAL *
        (market_factors->>'competition_factor')::DECIMAL,

        -- Expected: historical average
        historical_data.avg_revenue *
        (market_factors->>'seasonal_multiplier')::DECIMAL *
        (market_factors->>'economic_indicator')::DECIMAL *
        (market_factors->>'competition_factor')::DECIMAL,

        -- Optimistic: historical average + 1 stddev
        historical_data.avg_revenue + historical_data.revenue_stddev *
        (market_factors->>'seasonal_multiplier')::DECIMAL *
        (market_factors->>'economic_indicator')::DECIMAL *
        (market_factors->>'competition_factor')::DECIMAL,

        -- Confidence based on historical data
        LEAST(historical_data.similar_events_count / 10 * 100, 95),

        jsonb_build_object(
            'historical_events_analyzed', historical_data.similar_events_count,
            'market_seasonality', market_factors->>'seasonal_multiplier',
            'economic_conditions', 'moderate_growth',
            'competition_level', 'moderate'
        ),

        jsonb_build_array(
            'Economic downturn reducing discretionary spending',
            'Weather events affecting attendance',
            'Keynote speaker cancellation',
            'Technical issues with virtual components'
        ),

        jsonb_build_array(
            'Diversify revenue streams with sponsorships',
            'Implement flexible cancellation policies',
            'Build contingency budget reserves',
            'Develop backup plans for critical components'
        );

    -- Expense Forecast
    RETURN QUERY SELECT
        'Expense Forecast'::VARCHAR,
        -- Conservative: historical average + 1 stddev
        historical_data.avg_cost + historical_data.cost_stddev,

        -- Expected: historical average
        historical_data.avg_cost,

        -- Optimistic: historical average - 1 stddev
        GREATEST(historical_data.avg_cost - historical_data.cost_stddev, 0),

        LEAST(historical_data.similar_events_count / 10 * 100, 95),

        jsonb_build_object(
            'cost_inflation_rate', 1.03,
            'vendor_price_stability', 'moderate',
            'scale_efficiencies', CASE WHEN event_record.expected_attendance > 500 THEN 'expected' ELSE 'limited' END
        ),

        jsonb_build_array(
            'Vendor price increases',
            'Unexpected facility requirements',
            'Staffing shortages',
            'Equipment rental cost overruns'
        ),

        jsonb_build_array(
            'Lock in vendor contracts early',
            'Build cost contingency into budget',
            'Implement cost monitoring throughout planning',
            'Develop vendor relationship management program'
        );
END;
$$ LANGUAGE plpgsql;
```

### 4. Speaker and Content Performance Analytics
```sql
-- Comprehensive speaker evaluation and content optimization system
CREATE OR REPLACE FUNCTION analyze_speaker_performance(event_uuid UUID)
RETURNS TABLE (
    speaker_id UUID,
    speaker_name VARCHAR,
    session_title VARCHAR,
    audience_rating DECIMAL,
    content_effectiveness DECIMAL,
    delivery_quality DECIMAL,
    overall_score DECIMAL,
    audience_demographics JSONB,
    engagement_metrics JSONB,
    improvement_recommendations JSONB,
    rebooking_potential DECIMAL
) AS $$
DECLARE
    speaker_session RECORD;
BEGIN
    FOR speaker_session IN
        SELECT
            s.speaker_id,
            s.speaker_name,
            es.session_name,
            sa.assignment_id,

            -- Feedback aggregation
            AVG(f.rating) FILTER (WHERE f.feedback_type = 'session_specific') as session_rating,
            COUNT(f.feedback_id) as total_feedback_responses,

            -- Attendance and engagement
            COUNT(at.tracking_id) as session_attendance,
            AVG(at.interactions_count) as avg_interactions,
            AVG(at.duration_minutes) as avg_session_duration,

            -- Session performance factors
            es.session_type,
            es.session_format,
            es.speaking_time_minutes

        FROM speakers s
        JOIN speaker_assignments sa ON s.speaker_id = sa.speaker_id
        JOIN event_sessions es ON sa.session_id = es.session_id
        LEFT JOIN feedback f ON es.session_id = f.session_id
        LEFT JOIN attendance_tracking at ON es.session_id = at.session_id
        WHERE es.event_id = event_uuid
        GROUP BY s.speaker_id, s.speaker_name, es.session_name, sa.assignment_id,
                 es.session_type, es.session_format, es.speaking_time_minutes
    LOOP
        DECLARE
            audience_rating_val DECIMAL;
            content_effectiveness_val DECIMAL;
            delivery_quality_val DECIMAL;
            overall_score_val DECIMAL;
            demographics_data JSONB;
            engagement_data JSONB;
            recommendations_val JSONB;
            rebooking_potential_val DECIMAL;
        BEGIN
            -- Calculate audience rating (from feedback)
            audience_rating_val := COALESCE(speaker_session.session_rating, 3.5);

            -- Calculate content effectiveness (based on engagement and duration)
            content_effectiveness_val := (
                LEAST(speaker_session.avg_interactions / 3 * 40, 40) +  -- Interaction engagement (40%)
                CASE WHEN speaker_session.avg_session_duration > speaker_session.speaking_time_minutes * 0.8
                     THEN 35 ELSE 15 END +  -- Retention rate (35%)
                LEAST(audience_rating_val / 5 * 25, 25)  -- Quality rating (25%)
            );

            -- Calculate delivery quality (based on format and audience response)
            delivery_quality_val := (
                audience_rating_val / 5 * 50 +  -- Audience feedback (50%)
                CASE speaker_session.session_format
                    WHEN 'presentation' THEN 30
                    WHEN 'interactive' THEN 35
                    WHEN 'discussion' THEN 40
                    ELSE 25
                END +  -- Format effectiveness (30%)
                CASE WHEN speaker_session.total_feedback_responses > 10 THEN 20 ELSE 10 END  -- Sample size (20%)
            );

            -- Calculate overall score
            overall_score_val := (
                content_effectiveness_val * 0.5 +
                delivery_quality_val * 0.4 +
                audience_rating_val * 0.1
            );

            -- Audience demographics (from registrations who attended this session)
            SELECT jsonb_build_object(
                'total_attendees', COUNT(DISTINCT r.registration_id),
                'attendee_types', jsonb_object_agg(
                    COALESCE(r.registrant_type, 'unknown'),
                    COUNT(*)
                ),
                'experience_levels', jsonb_build_object(
                    'novice', COUNT(CASE WHEN r.registration_date > event_start - INTERVAL '30 days' THEN 1 END),
                    'experienced', COUNT(CASE WHEN r.registration_date <= event_start - INTERVAL '30 days' THEN 1 END)
                )
            ) INTO demographics_data
            FROM registrations r
            CROSS JOIN (SELECT start_date as event_start FROM events WHERE event_id = event_uuid) e
            WHERE r.event_id = event_uuid;

            -- Engagement metrics
            engagement_data := jsonb_build_object(
                'attendance_rate', speaker_session.session_attendance,
                'avg_interactions', ROUND(speaker_session.avg_interactions, 1),
                'retention_rate', ROUND(speaker_session.avg_session_duration / speaker_session.speaking_time_minutes * 100, 1),
                'feedback_response_rate', speaker_session.total_feedback_responses
            );

            -- Generate improvement recommendations
            recommendations_val := jsonb_build_array();

            IF audience_rating_val < 3.5 THEN
                recommendations_val := recommendations_val || jsonb_build_object(
                    'area', 'content',
                    'priority', 'high',
                    'recommendation', 'Review and update presentation content for better audience engagement'
                );
            END IF;

            IF speaker_session.avg_interactions < 2 THEN
                recommendations_val := recommendations_val || jsonb_build_object(
                    'area', 'interaction',
                    'priority', 'medium',
                    'recommendation', 'Incorporate more interactive elements and Q&A opportunities'
                );
            END IF;

            IF speaker_session.avg_session_duration < speaker_session.speaking_time_minutes * 0.7 THEN
                recommendations_val := recommendations_val || jsonb_build_object(
                    'area', 'delivery',
                    'priority', 'high',
                    'recommendation', 'Work on delivery techniques to improve audience retention'
                );
            END IF;

            -- Calculate rebooking potential (0-100)
            rebooking_potential_val := (
                overall_score_val * 0.6 +  -- Performance score (60%)
                LEAST(speaker_session.total_feedback_responses / 50 * 20, 20) +  -- Experience factor (20%)
                CASE WHEN speaker_session.session_type = 'keynote' THEN 20 ELSE 10 END  -- Demand factor (20%)
            );

            RETURN QUERY SELECT
                speaker_session.speaker_id,
                speaker_session.speaker_name,
                speaker_session.session_name,
                ROUND(audience_rating_val, 1),
                ROUND(content_effectiveness_val, 1),
                ROUND(delivery_quality_val, 1),
                ROUND(overall_score_val, 1),
                demographics_data,
                engagement_data,
                recommendations_val,
                ROUND(LEAST(rebooking_potential_val, 100), 1);
        END LOOP;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition event data by date for time-series analytics
CREATE TABLE events PARTITION BY RANGE (start_date);

CREATE TABLE events_2024 PARTITION OF events
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- Partition registrations by event date
CREATE TABLE registrations PARTITION BY LIST (event_id);

-- Partition attendance tracking by date for real-time analytics
CREATE TABLE attendance_tracking PARTITION BY RANGE (check_in_time);

CREATE TABLE attendance_tracking_2024_01 PARTITION OF attendance_tracking
    FOR VALUES FROM ('2024-01-01 00:00:00') TO ('2024-02-01 00:00:00');
```

### Advanced Indexing
```sql
-- Event and venue indexes
CREATE INDEX idx_events_date_type_status ON events (start_date DESC, event_type, event_status);
CREATE INDEX idx_events_venue_date ON events (venue_id, start_date);
CREATE INDEX idx_event_sessions_event_date ON event_sessions (event_id, session_date DESC);
CREATE INDEX idx_venues_location ON venues USING gist (st_makepoint(longitude, latitude));

-- Registration and ticketing indexes
CREATE INDEX idx_registrations_event_status ON registrations (event_id, registration_status, registration_date DESC);
CREATE INDEX idx_registrations_email ON registrations (email);
CREATE INDEX idx_ticket_types_event_active ON ticket_types (event_id, ticket_status) WHERE ticket_status = 'active';
CREATE INDEX idx_waitlists_event_position ON waitlists (event_id, position);

-- Speaker and vendor indexes
CREATE INDEX idx_speakers_expertise_rating ON speakers USING gin (expertise_areas, rating DESC);
CREATE INDEX idx_speaker_assignments_session_speaker ON speaker_assignments (session_id, speaker_id);
CREATE INDEX idx_vendors_type_rating ON vendors (vendor_type, rating DESC);

-- Sponsorship indexes
CREATE INDEX idx_sponsorship_levels_event_active ON sponsorship_levels (event_id, level_status) WHERE level_status = 'active';
CREATE INDEX idx_event_sponsorships_event_status ON event_sponsorships (event_id, sponsorship_status);

-- Financial indexes
CREATE INDEX idx_event_expenses_event_category ON event_expenses (event_id, expense_category, expense_date DESC);
CREATE INDEX idx_event_revenue_event_source ON event_revenue (event_id, revenue_source, transaction_date DESC);

-- Analytics indexes
CREATE INDEX idx_attendance_tracking_session_time ON attendance_tracking (session_id, check_in_time DESC);
CREATE INDEX idx_feedback_event_rating ON feedback (event_id, rating DESC);
CREATE INDEX idx_event_analytics_event_date ON event_analytics (event_id, report_date DESC);
```

### Materialized Views for Analytics
```sql
-- Event performance dashboard
CREATE MATERIALIZED VIEW event_performance_dashboard AS
SELECT
    e.event_id,
    e.event_name,
    e.event_type,
    e.start_date,
    e.event_status,

    -- Registration metrics
    COUNT(r.registration_id) as total_registrations,
    COUNT(CASE WHEN r.registration_status = 'confirmed' THEN 1 END) as confirmed_registrations,
    COUNT(CASE WHEN r.payment_status = 'completed' THEN 1 END) as paid_registrations,
    ROUND(
        COUNT(CASE WHEN r.payment_status = 'completed' THEN 1 END)::DECIMAL /
        COUNT(r.registration_id) * 100, 1
    ) as payment_completion_rate,

    -- Attendance metrics
    COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END) as actual_attendance,
    ROUND(
        COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END)::DECIMAL /
        COUNT(CASE WHEN r.registration_status = 'confirmed' THEN 1 END) * 100, 1
    ) as attendance_rate,

    -- Financial performance
    COALESCE(SUM(er.amount), 0) as total_revenue,
    COALESCE(SUM(ee.actual_amount), 0) as total_expenses,
    COALESCE(SUM(er.amount - ee.actual_amount), 0) as net_profit,
    ROUND(
        CASE WHEN SUM(er.amount) > 0
             THEN (SUM(er.amount - ee.actual_amount) / SUM(er.amount)) * 100
             ELSE 0 END, 1
    ) as profit_margin_percentage,

    -- Sponsorship metrics
    COUNT(es.sponsorship_id) as total_sponsors,
    COALESCE(SUM(es.sponsorship_amount), 0) as sponsorship_revenue,
    ROUND(
        COALESCE(SUM(es.sponsorship_amount), 0) /
        NULLIF(SUM(er.amount), 0) * 100, 1
    ) as sponsorship_revenue_percentage,

    -- Session performance
    COUNT(es.session_id) as total_sessions,
    ROUND(AVG(f.rating), 1) as avg_session_rating,
    COUNT(CASE WHEN f.rating >= 4 THEN 1 END)::DECIMAL /
    COUNT(f.feedback_id) * 100 as satisfaction_rate,

    -- Operational efficiency
    CASE
        WHEN e.expected_attendance IS NOT NULL AND COUNT(r.registration_id) >= e.expected_attendance * 0.95 THEN 'overbooked'
        WHEN e.expected_attendance IS NOT NULL AND COUNT(r.registration_id) >= e.expected_attendance * 0.8 THEN 'on_track'
        WHEN e.expected_attendance IS NOT NULL AND COUNT(r.registration_id) < e.expected_attendance * 0.8 THEN 'underbooked'
        ELSE 'no_target_set'
    END as registration_health,

    -- Overall event score
    ROUND(
        (
            -- Attendance success (25%)
            LEAST(COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END)::DECIMAL /
                  NULLIF(COUNT(CASE WHEN r.registration_status = 'confirmed' THEN 1 END), 0) * 25, 25) +
            -- Financial performance (25%)
            CASE
                WHEN SUM(er.amount - ee.actual_amount) > e.total_budget * 0.1 THEN 25
                WHEN SUM(er.amount - ee.actual_amount) > 0 THEN 15
                WHEN SUM(er.amount - ee.actual_amount) > e.total_budget * -0.1 THEN 10
                ELSE 0
            END +
            -- Satisfaction rating (20%)
            LEAST(COALESCE(AVG(f.rating), 0) / 5 * 20, 20) +
            -- Operational efficiency (15%)
            CASE WHEN COUNT(CASE WHEN r.payment_status = 'completed' THEN 1 END) = COUNT(r.registration_id) THEN 15
                 WHEN COUNT(CASE WHEN r.payment_status = 'completed' THEN 1 END) >= COUNT(r.registration_id) * 0.9 THEN 12
                 ELSE 5 END +
            -- Sponsorship success (15%)
            LEAST(COUNT(es.sponsorship_id)::DECIMAL / 5 * 15, 15)
        ), 1
    ) as overall_event_score

FROM events e
LEFT JOIN registrations r ON e.event_id = r.event_id
LEFT JOIN event_sessions es ON e.event_id = es.event_id
LEFT JOIN event_revenue er ON e.event_id = er.event_id
LEFT JOIN event_expenses ee ON e.event_id = ee.event_id
LEFT JOIN event_sponsorships es ON e.event_id = es.event_id
LEFT JOIN feedback f ON e.event_id = f.event_id
WHERE e.event_status IN ('completed', 'in_progress')
GROUP BY e.event_id, e.event_name, e.event_type, e.start_date, e.event_status, e.expected_attendance, e.total_budget;

-- Refresh every 30 minutes
CREATE UNIQUE INDEX idx_event_performance_dashboard ON event_performance_dashboard (event_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY event_performance_dashboard;
```

## Security Considerations

### Attendee Data Privacy and Event Security
```sql
-- GDPR and CCPA compliance for event attendee data
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_tracking ENABLE ROW LEVEL SECURITY;

CREATE POLICY registration_privacy_policy ON registrations
    FOR SELECT USING (
        event_id IN (
            SELECT event_id FROM events
            WHERE organizer_id = current_setting('app.user_id')::UUID
        ) OR
        email = current_setting('app.user_email')::VARCHAR OR
        current_setting('app.user_role')::TEXT IN ('admin', 'event_staff')
    );

CREATE POLICY attendance_privacy_policy ON attendance_tracking
    FOR SELECT USING (
        registration_id IN (
            SELECT registration_id FROM registrations
            WHERE event_id IN (
                SELECT event_id FROM events
                WHERE organizer_id = current_setting('app.user_id')::UUID
            )
        ) OR
        current_setting('app.user_role')::TEXT IN ('admin', 'security')
    );
```

### Financial and Sponsorship Data Protection
```sql
-- Secure financial data handling for events
ALTER TABLE event_revenue ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_sponsorships ENABLE ROW LEVEL SECURITY;

CREATE POLICY revenue_security_policy ON event_revenue
    FOR ALL USING (
        event_id IN (
            SELECT event_id FROM events
            WHERE organizer_id = current_setting('app.user_id')::UUID
        ) OR
        current_setting('app.user_role')::TEXT IN ('admin', 'finance')
    );

CREATE POLICY sponsorship_security_policy ON event_sponsorships
    FOR SELECT USING (
        event_id IN (
            SELECT event_id FROM events
            WHERE organizer_id = current_setting('app.user_id')::UUID
        ) OR
        sponsor_id IN (
            SELECT sponsor_id FROM sponsors
            WHERE primary_contact_email = current_setting('app.user_email')::VARCHAR
        ) OR
        current_setting('app.user_role')::TEXT IN ('admin', 'sponsorship_manager')
    );
```

### Audit Trail and Compliance
```sql
-- Comprehensive event management audit logging
CREATE TABLE event_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    event_id UUID,
    session_id UUID,
    registration_id UUID,
    ip_address INET,
    user_agent TEXT,
    change_reason TEXT,
    audit_type VARCHAR CHECK (audit_type IN ('security', 'financial', 'operational', 'compliance')),
    audit_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (audit_timestamp);

-- Audit trigger for event operations
CREATE OR REPLACE FUNCTION event_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO event_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, event_id, session_id, registration_id, ip_address,
        user_agent, audit_type
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        CASE WHEN TG_TABLE_NAME LIKE '%event%' THEN COALESCE(NEW.event_id, OLD.event_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME LIKE '%session%' THEN COALESCE(NEW.session_id, OLD.session_id) ELSE NULL END,
        CASE WHEN TG_TABLE_NAME LIKE '%registration%' THEN COALESCE(NEW.registration_id, OLD.registration_id) ELSE NULL END,
        inet_client_addr(),
        current_setting('app.user_agent', TRUE)::TEXT,
        CASE
            WHEN TG_TABLE_NAME LIKE '%revenue%' OR TG_TABLE_NAME LIKE '%expense%' THEN 'financial'
            WHEN TG_TABLE_NAME LIKE '%registration%' THEN 'operational'
            WHEN TG_TABLE_NAME LIKE '%sponsor%' THEN 'financial'
            ELSE 'operational'
        END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### Event Accessibility and ADA Compliance
```sql
-- Automated accessibility compliance checking for event venues and planning
CREATE OR REPLACE FUNCTION check_event_accessibility_compliance(event_uuid UUID)
RETURNS TABLE (
    compliance_area VARCHAR,
    compliance_status VARCHAR,
    requirements_met INTEGER,
    total_requirements INTEGER,
    compliance_percentage DECIMAL,
    issues_identified JSONB,
    remediation_steps JSONB,
    deadline_date DATE
) AS $$
DECLARE
    event_record events%ROWTYPE;
    venue_record venues%ROWTYPE;
BEGIN
    -- Get event and venue details
    SELECT e.*, v.* INTO event_record, venue_record
    FROM events e
    LEFT JOIN venues v ON e.venue_id = v.venue_id
    WHERE e.event_id = event_uuid;

    -- ADA Venue Accessibility
    RETURN QUERY SELECT
        'ADA Venue Accessibility'::VARCHAR,
        CASE WHEN jsonb_array_length(venue_record.accessibility_features) >= 5 THEN 'compliant' ELSE 'non_compliant' END::VARCHAR,
        LEAST(jsonb_array_length(venue_record.accessibility_features), 5)::INTEGER,
        5,
        LEAST(jsonb_array_length(venue_record.accessibility_features) / 5.0 * 100, 100)::DECIMAL,
        CASE WHEN jsonb_array_length(venue_record.accessibility_features) < 5
             THEN jsonb_build_array('Wheelchair accessible entrances', 'Accessible restrooms', 'Sign language interpreters available', 'Braille signage', 'Accessible parking')
             ELSE '[]'::jsonb END,
        jsonb_build_array(
            'Conduct accessibility audit of venue',
            'Install additional accessibility features',
            'Partner with disability service organizations'
        ),
        event_record.start_date - INTERVAL '30 days';

    -- Registration Accessibility
    RETURN QUERY SELECT
        'Registration Accessibility'::VARCHAR,
        CASE WHEN (SELECT COUNT(*) FROM ticket_types WHERE event_id = event_uuid AND access_level = 'standard') > 0 THEN 'compliant' ELSE 'non_compliant' END::VARCHAR,
        CASE WHEN (SELECT COUNT(*) FROM ticket_types WHERE event_id = event_uuid AND access_level = 'standard') > 0 THEN 1 ELSE 0 END,
        1,
        CASE WHEN (SELECT COUNT(*) FROM ticket_types WHERE event_id = event_uuid AND access_level = 'standard') > 0 THEN 100 ELSE 0 END::DECIMAL,
        CASE WHEN (SELECT COUNT(*) FROM ticket_types WHERE event_id = event_uuid AND access_level = 'standard') = 0
             THEN jsonb_build_array('No accessible registration process available')
             ELSE '[]'::jsonb END,
        jsonb_build_array(
            'Implement accessible online registration',
            'Provide phone registration support',
            'Train staff on accessibility requirements'
        ),
        event_record.start_date - INTERVAL '14 days';

    -- Content Accessibility
    RETURN QUERY SELECT
        'Content Accessibility'::VARCHAR,
        'compliant'::VARCHAR, -- Assume compliant until verified
        1,
        1,
        100.0::DECIMAL,
        '[]'::jsonb,
        jsonb_build_array(
            'Provide captioning for video content',
            'Create accessible presentation materials',
            'Offer sign language interpretation'
        ),
        event_record.start_date - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql;
```

### Financial Reporting and Tax Compliance
```sql
-- Automated tax reporting and financial compliance for event organizers
CREATE OR REPLACE FUNCTION generate_event_tax_report(event_uuid UUID, tax_year INTEGER)
RETURNS TABLE (
    tax_category VARCHAR,
    gross_revenue DECIMAL,
    taxable_revenue DECIMAL,
    tax_rate DECIMAL,
    tax_due DECIMAL,
    filing_deadline DATE,
    compliance_status VARCHAR,
    supporting_documentation JSONB
) AS $$
DECLARE
    event_record events%ROWTYPE;
BEGIN
    -- Get event details
    SELECT * INTO event_record FROM events WHERE event_id = event_uuid;

    -- Ticket Sales Revenue
    RETURN QUERY SELECT
        'Ticket Sales'::VARCHAR,
        COALESCE(SUM(r.final_amount), 0),
        COALESCE(SUM(r.final_amount), 0),
        0.0::DECIMAL, -- Entertainment events may not be taxable
        0.0::DECIMAL,
        DATE(tax_year + 1 || '-03-15'), -- Typical deadline
        'compliant'::VARCHAR,
        jsonb_build_object(
            'transaction_count', COUNT(r.registration_id),
            'average_ticket_price', AVG(r.final_amount),
            'payment_methods', jsonb_object_agg(COALESCE(r.payment_method, 'unknown'), COUNT(*))
        )
    FROM registrations r
    WHERE r.event_id = event_uuid
      AND EXTRACT(YEAR FROM r.registration_date) = tax_year
      AND r.payment_status = 'completed'
    GROUP BY r.event_id;

    -- Sponsorship Revenue
    RETURN QUERY SELECT
        'Sponsorship Revenue'::VARCHAR,
        COALESCE(SUM(es.sponsorship_amount), 0),
        COALESCE(SUM(es.sponsorship_amount), 0),
        0.0::DECIMAL,
        0.0::DECIMAL,
        DATE(tax_year + 1 || '-03-15'),
        'compliant'::VARCHAR,
        jsonb_build_object(
            'sponsor_count', COUNT(es.sponsorship_id),
            'average_sponsorship', AVG(es.sponsorship_amount),
            'sponsorship_levels', jsonb_object_agg(sl.level_name, COUNT(*))
        )
    FROM event_sponsorships es
    JOIN sponsorship_levels sl ON es.level_id = sl.level_id
    WHERE es.event_id = event_uuid
      AND es.payment_status = 'paid'
    GROUP BY es.event_id;

    -- Vendor Expenses (Deductible)
    RETURN QUERY SELECT
        'Vendor Expenses'::VARCHAR,
        COALESCE(SUM(ee.actual_amount), 0),
        0.0::DECIMAL, -- Expenses are deductible
        0.0::DECIMAL,
        0.0::DECIMAL,
        DATE(tax_year + 1 || '-03-15'),
        'compliant'::VARCHAR,
        jsonb_build_object(
            'expense_categories', jsonb_object_agg(ee.expense_category, SUM(ee.actual_amount)),
            'vendor_count', COUNT(DISTINCT ee.vendor_id),
            'largest_expense', MAX(ee.actual_amount)
        )
    FROM event_expenses ee
    WHERE ee.event_id = event_uuid
      AND EXTRACT(YEAR FROM ee.expense_date) = tax_year
    GROUP BY ee.event_id;
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Payment processors** (Stripe, PayPal, Authorize.net) for ticket sales
- **Email marketing** (Mailchimp, Constant Contact) for registration confirmations
- **Event registration** (Eventbrite, Cvent) for attendee management
- **Venue management** (SpaceIQ, Condeco) for facility booking
- **Survey tools** (SurveyMonkey, Typeform) for post-event feedback

### API Endpoints
- **Event APIs** for registration and attendee management
- **Ticketing APIs** for automated ticket generation and validation
- **Venue APIs** for real-time availability and booking
- **Analytics APIs** for performance tracking and reporting

## Monitoring & Analytics

### Key Performance Indicators
- **Registration metrics** (conversion rates, abandonment rates, payment completion)
- **Attendance analytics** (check-in rates, session popularity, engagement scores)
- **Financial performance** (revenue tracking, expense management, ROI calculation)
- **Satisfaction scores** (attendee feedback, speaker ratings, venue reviews)

### Real-Time Dashboards
```sql
-- Event operations command center
CREATE VIEW event_operations_dashboard AS
SELECT
    e.event_id,
    e.event_name,
    e.event_type,
    e.start_date,
    e.event_status,

    -- Registration funnel
    COUNT(CASE WHEN r.registration_status = 'confirmed' THEN 1 END) as confirmed_registrations,
    COUNT(CASE WHEN r.payment_status = 'completed' THEN 1 END) as paid_registrations,
    COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END) as checked_in_attendees,
    ROUND(
        COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END)::DECIMAL /
        COUNT(CASE WHEN r.registration_status = 'confirmed' THEN 1 END) * 100, 1
    ) as attendance_rate,

    -- Revenue tracking
    COALESCE(SUM(CASE WHEN r.payment_status = 'completed' THEN r.final_amount END), 0) as ticket_revenue,
    COALESCE(SUM(es.sponsorship_amount), 0) as sponsorship_revenue,
    COALESCE(SUM(er.amount), 0) as total_revenue,
    COALESCE(SUM(ee.actual_amount), 0) as total_expenses,
    COALESCE(SUM(er.amount - ee.actual_amount), 0) as current_profit,

    -- Session performance
    COUNT(DISTINCT es.session_id) as total_sessions,
    COUNT(DISTINCT at.session_id) as sessions_with_attendance,
    ROUND(AVG(at.duration_minutes), 1) as avg_session_duration,
    ROUND(AVG(f.rating), 1) as avg_satisfaction_rating,

    -- Operational status
    COUNT(CASE WHEN es.session_status = 'completed' THEN 1 END) as completed_sessions,
    COUNT(CASE WHEN vc.contract_status = 'completed' THEN 1 END) as fulfilled_vendor_contracts,
    COUNT(CASE WHEN es.session_status = 'cancelled' THEN 1 END) as cancelled_sessions,

    -- Real-time alerts
    CASE
        WHEN e.start_date < CURRENT_DATE + INTERVAL '1 day' AND COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END) < COUNT(CASE WHEN r.registration_status = 'confirmed' THEN 1 END) * 0.8
        THEN 'Low attendance warning - consider communication campaign'
        WHEN SUM(ee.actual_amount) > e.total_budget * 1.1
        THEN 'Budget overrun alert - expense controls needed'
        WHEN COUNT(CASE WHEN es.session_status = 'cancelled' THEN 1 END) > 0
        THEN 'Session cancellations detected - attendee communication required'
        ELSE 'All systems operating normally'
    END as operational_alerts,

    -- Overall event health score
    ROUND(
        (
            -- Registration success (20%)
            LEAST(COUNT(CASE WHEN r.payment_status = 'completed' THEN 1 END)::DECIMAL /
                  NULLIF(COUNT(r.registration_id), 0) * 20, 20) +
            -- Attendance performance (20%)
            LEAST(COUNT(CASE WHEN r.checked_in = TRUE THEN 1 END)::DECIMAL /
                  NULLIF(COUNT(CASE WHEN r.registration_status = 'confirmed' THEN 1 END), 0) * 20, 20) +
            -- Financial health (20%)
            CASE
                WHEN SUM(er.amount - ee.actual_amount) > 0 THEN 20
                WHEN SUM(er.amount - ee.actual_amount) > e.total_budget * -0.1 THEN 15
                WHEN SUM(er.amount - ee.actual_amount) > e.total_budget * -0.2 THEN 10
                ELSE 5
            END +
            -- Operational efficiency (20%)
            (1 - COUNT(CASE WHEN es.session_status = 'cancelled' THEN 1 END)::DECIMAL /
             NULLIF(COUNT(es.session_id), 0)) * 20 +
            -- Attendee satisfaction (20%)
            LEAST(COALESCE(AVG(f.rating), 0) / 5 * 20, 20)
        ), 1
    ) as overall_event_health_score

FROM events e
LEFT JOIN registrations r ON e.event_id = r.event_id
LEFT JOIN event_sessions es ON e.event_id = es.event_id
LEFT JOIN event_sponsorships es ON e.event_id = es.event_id
LEFT JOIN event_revenue er ON e.event_id = er.event_id
LEFT JOIN event_expenses ee ON e.event_id = er.event_id
LEFT JOIN attendance_tracking at ON r.registration_id = at.registration_id
LEFT JOIN feedback f ON e.event_id = f.event_id
LEFT JOIN vendor_contracts vc ON e.event_id = vc.event_id
WHERE e.event_status IN ('confirmed', 'in_progress', 'completed')
GROUP BY e.event_id, e.event_name, e.event_type, e.start_date, e.event_status, e.total_budget;

-- Event planning and forecasting dashboard
CREATE VIEW event_planning_dashboard AS
SELECT
    v.venue_id,
    v.venue_name,
    v.venue_type,

    -- Venue utilization (next 90 days)
    COUNT(e.event_id) as upcoming_events,
    SUM(e.expected_attendance) as total_expected_attendance,
    ROUND(
        COUNT(e.event_id)::DECIMAL / 90 * 30, 1  -- Events per month average
    ) as avg_events_per_month,

    -- Capacity utilization
    ROUND(
        SUM(e.expected_attendance)::DECIMAL / (COUNT(e.event_id) * v.capacity) * 100, 1
    ) as avg_capacity_utilization,

    -- Revenue potential
    COALESCE(SUM(e.projected_revenue), 0) as total_projected_revenue,
    ROUND(
        COALESCE(SUM(e.projected_revenue), 0) / COUNT(e.event_id), 2
    ) as avg_revenue_per_event,

    -- Event type distribution
    jsonb_object_agg(
        e.event_type,
        COUNT(*)
    ) as event_types_distribution,

    -- Peak booking periods
    COUNT(CASE WHEN EXTRACT(MONTH FROM e.start_date) IN (3,4,5) THEN 1 END) as spring_events,
    COUNT(CASE WHEN EXTRACT(MONTH FROM e.start_date) IN (6,7,8) THEN 1 END) as summer_events,
    COUNT(CASE WHEN EXTRACT(MONTH FROM e.start_date) IN (9,10,11) THEN 1 END) as fall_events,
    COUNT(CASE WHEN EXTRACT(MONTH FROM e.start_date) IN (12,1,2) THEN 1 END) as winter_events,

    -- Demand forecasting
    CASE
        WHEN COUNT(e.event_id) > 10 THEN 'high_demand'
        WHEN COUNT(e.event_id) > 5 THEN 'moderate_demand'
        WHEN COUNT(e.event_id) > 2 THEN 'low_demand'
        ELSE 'very_low_demand'
    END as demand_level,

    -- Pricing optimization opportunities
    CASE
        WHEN ROUND(SUM(e.expected_attendance)::DECIMAL / (COUNT(e.event_id) * v.capacity) * 100, 1) > 80 THEN 'consider_rate_increase'
        WHEN ROUND(SUM(e.expected_attendance)::DECIMAL / (COUNT(e.event_id) * v.capacity) * 100, 1) < 50 THEN 'consider_promotional_rates'
        ELSE 'maintain_current_rates'
    END as pricing_recommendation,

    -- Operational efficiency score
    ROUND(
        (
            -- Capacity utilization (40%)
            LEAST(ROUND(
                SUM(e.expected_attendance)::DECIMAL / (COUNT(e.event_id) * v.capacity) * 100, 1
            ) / 80 * 40, 40) +
            -- Event diversity (30%)
            CASE WHEN jsonb_object_length(jsonb_object_agg(e.event_type, COUNT(*))) > 3 THEN 30
                 WHEN jsonb_object_length(jsonb_object_agg(e.event_type, COUNT(*))) > 1 THEN 20
                 ELSE 10 END +
            -- Revenue stability (30%)
            LEAST(COUNT(CASE WHEN e.projected_revenue > 10000 THEN 1 END)::DECIMAL / COUNT(e.event_id) * 30, 30)
        ), 1
    ) as venue_efficiency_score

FROM venues v
LEFT JOIN events e ON v.venue_id = e.venue_id
    AND e.start_date >= CURRENT_DATE
    AND e.start_date < CURRENT_DATE + INTERVAL '90 days'
    AND e.event_status IN ('confirmed', 'planned')
GROUP BY v.venue_id, v.venue_name, v.venue_type, v.capacity;
```

This event management database schema provides enterprise-grade infrastructure for event planning, execution, and analysis with comprehensive registration, ticketing, venue management, and post-event evaluation capabilities.
