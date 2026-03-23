# Timezone & Daylight Saving Time Patterns

Real-world timezone handling patterns, daylight saving time (DST) management, and global time coordination techniques used by product engineers at Atlassian, Netflix, Uber, Airbnb, and other global companies.

## 🚀 Global Timezone Management

### The "Multi-Timezone User" Pattern
```sql
-- User timezone preferences
CREATE TABLE user_timezones (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNIQUE NOT NULL,
    timezone_name VARCHAR(50) NOT NULL,  -- 'America/New_York', 'Europe/London'
    timezone_offset_minutes INT NOT NULL,  -- Current offset in minutes
    dst_enabled BOOLEAN DEFAULT TRUE,
    preferred_time_format ENUM('12h', '24h') DEFAULT '12h',
    working_hours_start TIME DEFAULT '09:00:00',
    working_hours_end TIME DEFAULT '17:00:00',
    working_days JSON,  -- ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']
    last_timezone_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_timezone (timezone_name),
    INDEX idx_offset (timezone_offset_minutes),
    INDEX idx_user (user_id)
);

-- Timezone-aware events
CREATE TABLE timezone_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,  -- 'meeting', 'deadline', 'reminder'
    title VARCHAR(255) NOT NULL,
    description TEXT,
    start_time_utc TIMESTAMP NOT NULL,
    end_time_utc TIMESTAMP NOT NULL,
    timezone_name VARCHAR(50) NOT NULL,
    created_by BIGINT NOT NULL,
    attendees JSON,  -- Array of user IDs
    is_recurring BOOLEAN DEFAULT FALSE,
    recurrence_pattern JSON,  -- For recurring events
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_start_time (start_time_utc),
    INDEX idx_timezone (timezone_name),
    INDEX idx_created_by (created_by),
    INDEX idx_attendees ((CAST(attendees->>'$.user_ids' AS CHAR(255))))
);

-- Timezone conversion functions
DELIMITER $$
CREATE FUNCTION convert_to_user_timezone(
    utc_time TIMESTAMP,
    user_timezone VARCHAR(50)
) 
RETURNS TIMESTAMP
DETERMINISTIC
BEGIN
    -- Convert UTC time to user's timezone
    RETURN CONVERT_TZ(utc_time, 'UTC', user_timezone);
END$$

CREATE FUNCTION convert_from_user_timezone(
    local_time TIMESTAMP,
    user_timezone VARCHAR(50)
) 
RETURNS TIMESTAMP
DETERMINISTIC
BEGIN
    -- Convert user's local time to UTC
    RETURN CONVERT_TZ(local_time, user_timezone, 'UTC');
END$$

CREATE FUNCTION get_timezone_offset(
    timezone_name VARCHAR(50),
    target_date DATE
) 
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE offset_minutes INT;
    
    -- Get timezone offset for specific date (handles DST)
    SELECT TIMESTAMPDIFF(MINUTE, UTC_TIMESTAMP(), CONVERT_TZ(UTC_TIMESTAMP(), 'UTC', timezone_name))
    INTO offset_minutes;
    
    RETURN offset_minutes;
END$$
DELIMITER ;
```

### The "DST Transition Handling" Pattern
```sql
-- DST transition tracking
CREATE TABLE dst_transitions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timezone_name VARCHAR(50) NOT NULL,
    transition_type ENUM('spring_forward', 'fall_back') NOT NULL,
    transition_date DATE NOT NULL,
    transition_time TIME NOT NULL,
    offset_before INT NOT NULL,  -- Offset before transition (minutes)
    offset_after INT NOT NULL,   -- Offset after transition (minutes)
    year INT NOT NULL,
    
    UNIQUE KEY uk_timezone_transition (timezone_name, year, transition_type),
    INDEX idx_transition_date (transition_date),
    INDEX idx_timezone (timezone_name, transition_date)
);

-- DST-aware scheduling
CREATE TABLE dst_aware_schedules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    schedule_name VARCHAR(100) NOT NULL,
    timezone_name VARCHAR(50) NOT NULL,
    start_time_local TIME NOT NULL,  -- Local time (not UTC)
    end_time_local TIME NOT NULL,
    days_of_week JSON NOT NULL,  -- ['monday', 'tuesday', etc.]
    dst_handling ENUM('ignore', 'adjust', 'duplicate', 'skip') DEFAULT 'adjust',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_timezone_schedule (timezone_name, is_active),
    INDEX idx_dst_handling (dst_handling)
);

-- DST transition detection
DELIMITER $$
CREATE PROCEDURE detect_dst_transitions()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE timezone_name VARCHAR(50);
    DECLARE current_offset INT;
    DECLARE previous_offset INT;
    DECLARE current_date DATE;
    
    DECLARE timezone_cursor CURSOR FOR
        SELECT DISTINCT tz.timezone_name
        FROM user_timezones tz
        WHERE tz.dst_enabled = TRUE;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN timezone_cursor;
    
    transition_loop: LOOP
        FETCH timezone_cursor INTO timezone_name;
        IF done THEN
            LEAVE transition_loop;
        END IF;
        
        -- Check for DST transitions in the next 30 days
        SET current_date = CURDATE();
        
        WHILE current_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY) DO
            -- Get offset for current date
            SELECT get_timezone_offset(timezone_name, current_date) INTO current_offset;
            
            -- Get offset for previous date
            SELECT get_timezone_offset(timezone_name, DATE_SUB(current_date, INTERVAL 1 DAY)) INTO previous_offset;
            
            -- If offset changed, it's a DST transition
            IF current_offset != previous_offset THEN
                INSERT INTO dst_transitions (
                    timezone_name, 
                    transition_type, 
                    transition_date, 
                    transition_time,
                    offset_before,
                    offset_after,
                    year
                )
                VALUES (
                    timezone_name,
                    CASE 
                        WHEN current_offset > previous_offset THEN 'spring_forward'
                        ELSE 'fall_back'
                    END,
                    current_date,
                    '02:00:00',
                    previous_offset,
                    current_offset,
                    YEAR(current_date)
                )
                ON DUPLICATE KEY UPDATE
                    offset_before = VALUES(offset_before),
                    offset_after = VALUES(offset_after);
            END IF;
            
            SET current_date = DATE_ADD(current_date, INTERVAL 1 DAY);
        END WHILE;
    END LOOP;
    
    CLOSE timezone_cursor;
END$$
DELIMITER ;
```

## 🎯 Global Meeting & Scheduling Patterns

### The "Cross-Timezone Meeting" Pattern
```sql
-- Cross-timezone meeting scheduling
CREATE TABLE cross_timezone_meetings (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    meeting_title VARCHAR(255) NOT NULL,
    organizer_id BIGINT NOT NULL,
    organizer_timezone VARCHAR(50) NOT NULL,
    proposed_start_time_utc TIMESTAMP NOT NULL,
    proposed_end_time_utc TIMESTAMP NOT NULL,
    meeting_duration_minutes INT NOT NULL,
    attendees JSON NOT NULL,  -- Array of user IDs with their timezones
    timezone_conflicts JSON,  -- Conflicts for each attendee
    best_time_slots JSON,     -- Suggested time slots for all attendees
    status ENUM('draft', 'scheduled', 'completed', 'cancelled') DEFAULT 'draft',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_organizer (organizer_id, status),
    INDEX idx_start_time (proposed_start_time_utc),
    INDEX idx_attendees ((CAST(attendees->>'$.user_ids' AS CHAR(255))))
);

-- Meeting timezone optimization
DELIMITER $$
CREATE PROCEDURE optimize_meeting_time(
    IN meeting_id BIGINT
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE attendee_id BIGINT;
    DECLARE attendee_timezone VARCHAR(50);
    DECLARE working_start TIME;
    DECLARE working_end TIME;
    DECLARE working_days JSON;
    
    DECLARE attendee_cursor CURSOR FOR
        SELECT 
            JSON_UNQUOTE(JSON_EXTRACT(attendees, CONCAT('$[', numbers.n, '].user_id'))) as user_id,
            ut.timezone_name,
            ut.working_hours_start,
            ut.working_hours_end,
            ut.working_days
        FROM cross_timezone_meetings cm
        CROSS JOIN (
            SELECT 0 as n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
            UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9
        ) numbers
        JOIN user_timezones ut ON ut.user_id = JSON_UNQUOTE(JSON_EXTRACT(cm.attendees, CONCAT('$[', numbers.n, '].user_id')))
        WHERE cm.id = meeting_id
        AND JSON_EXTRACT(cm.attendees, CONCAT('$[', numbers.n, '].user_id')) IS NOT NULL;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN attendee_cursor;
    
    attendee_loop: LOOP
        FETCH attendee_cursor INTO attendee_id, attendee_timezone, working_start, working_end, working_days;
        IF done THEN
            LEAVE attendee_loop;
        END IF;
        
        -- Calculate local time for this attendee
        -- Check if it falls within working hours
        -- Store conflicts and suggestions
        
    END LOOP;
    
    CLOSE attendee_cursor;
END$$
DELIMITER ;
```

### The "Working Hours Validation" Pattern
```sql
-- Working hours validation
CREATE TABLE working_hours_validation (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    timezone_name VARCHAR(50) NOT NULL,
    proposed_time_utc TIMESTAMP NOT NULL,
    local_time TIMESTAMP NOT NULL,
    is_within_working_hours BOOLEAN NOT NULL,
    working_hours_start TIME NOT NULL,
    working_hours_end TIME NOT NULL,
    day_of_week VARCHAR(20) NOT NULL,
    is_working_day BOOLEAN NOT NULL,
    validation_result ENUM('valid', 'outside_hours', 'non_working_day', 'holiday') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_user_validation (user_id, validation_result),
    INDEX idx_proposed_time (proposed_time_utc),
    INDEX idx_working_hours (is_within_working_hours, is_working_day)
);

-- Working hours validation function
DELIMITER $$
CREATE FUNCTION validate_working_hours(
    user_id BIGINT,
    proposed_time_utc TIMESTAMP
) 
RETURNS ENUM('valid', 'outside_hours', 'non_working_day', 'holiday')
READS SQL DATA
BEGIN
    DECLARE user_timezone VARCHAR(50);
    DECLARE local_time TIMESTAMP;
    DECLARE working_start TIME;
    DECLARE working_end TIME;
    DECLARE working_days JSON;
    DECLARE day_of_week VARCHAR(20);
    DECLARE local_time_only TIME;
    
    -- Get user timezone and working hours
    SELECT 
        ut.timezone_name,
        ut.working_hours_start,
        ut.working_hours_end,
        ut.working_days
    INTO user_timezone, working_start, working_end, working_days
    FROM user_timezones ut
    WHERE ut.user_id = user_id;
    
    -- Convert to local time
    SET local_time = convert_to_user_timezone(proposed_time_utc, user_timezone);
    SET local_time_only = TIME(local_time);
    SET day_of_week = LOWER(DAYNAME(local_time));
    
    -- Check if it's a working day
    IF JSON_CONTAINS(working_days, JSON_QUOTE(day_of_week)) = 0 THEN
        RETURN 'non_working_day';
    END IF;
    
    -- Check if it's within working hours
    IF local_time_only < working_start OR local_time_only > working_end THEN
        RETURN 'outside_hours';
    END IF;
    
    -- Check for holidays (would integrate with holiday calendar)
    -- For now, return valid
    RETURN 'valid';
END$$
DELIMITER ;
```

## 🌍 Global Content & Scheduling Patterns

### The "Content Release Scheduling" Pattern
```sql
-- Global content release scheduling (Netflix-style)
CREATE TABLE global_content_releases (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    content_id BIGINT NOT NULL,
    content_title VARCHAR(255) NOT NULL,
    content_type ENUM('movie', 'series', 'documentary', 'show') NOT NULL,
    release_strategy ENUM('global_simultaneous', 'regional_staggered', 'timezone_based') NOT NULL,
    global_release_time_utc TIMESTAMP NOT NULL,
    regional_releases JSON,  -- Different release times per region
    timezone_releases JSON,  -- Different release times per timezone
    target_regions JSON,     -- Target regions for release
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_content (content_id, is_active),
    INDEX idx_release_time (global_release_time_utc),
    INDEX idx_release_strategy (release_strategy)
);

-- Regional release time calculation
CREATE TABLE regional_release_times (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    content_id BIGINT NOT NULL,
    region_code VARCHAR(10) NOT NULL,  -- 'US', 'EU', 'APAC'
    timezone_name VARCHAR(50) NOT NULL,
    local_release_time TIMESTAMP NOT NULL,
    utc_release_time TIMESTAMP NOT NULL,
    release_window_start TIME DEFAULT '00:00:00',
    release_window_end TIME DEFAULT '23:59:59',
    is_primary_release BOOLEAN DEFAULT FALSE,
    
    UNIQUE KEY uk_content_region (content_id, region_code),
    INDEX idx_region_timezone (region_code, timezone_name),
    INDEX idx_utc_release (utc_release_time)
);

-- Content release optimization
DELIMITER $$
CREATE PROCEDURE optimize_global_release(
    IN content_id BIGINT,
    IN target_regions JSON
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE region_code VARCHAR(10);
    DECLARE timezone_name VARCHAR(50);
    DECLARE optimal_time TIME;
    
    DECLARE region_cursor CURSOR FOR
        SELECT 
            JSON_UNQUOTE(JSON_EXTRACT(target_regions, CONCAT('$[', numbers.n, '].region'))) as region,
            JSON_UNQUOTE(JSON_EXTRACT(target_regions, CONCAT('$[', numbers.n, '].timezone'))) as timezone
        FROM (
            SELECT 0 as n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
        ) numbers
        WHERE JSON_EXTRACT(target_regions, CONCAT('$[', numbers.n, '].region')) IS NOT NULL;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN region_cursor;
    
    region_loop: LOOP
        FETCH region_cursor INTO region_code, timezone_name;
        IF done THEN
            LEAVE region_loop;
        END IF;
        
        -- Calculate optimal release time for this region
        -- Consider local viewing patterns, timezone, etc.
        SET optimal_time = '20:00:00';  -- 8 PM local time
        
        -- Insert regional release time
        INSERT INTO regional_release_times (
            content_id, region_code, timezone_name, 
            local_release_time, utc_release_time
        )
        VALUES (
            content_id,
            region_code,
            timezone_name,
            CONCAT(CURDATE(), ' ', optimal_time),
            convert_from_user_timezone(CONCAT(CURDATE(), ' ', optimal_time), timezone_name)
        )
        ON DUPLICATE KEY UPDATE
            local_release_time = VALUES(local_release_time),
            utc_release_time = VALUES(utc_release_time);
    END LOOP;
    
    CLOSE region_cursor;
END$$
DELIMITER ;
```

## 🕐 Timezone-Aware Analytics

### The "Timezone Analytics" Pattern
```sql
-- Timezone-based user activity analytics
CREATE TABLE timezone_analytics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    timezone_name VARCHAR(50) NOT NULL,
    activity_date DATE NOT NULL,
    activity_hour_local INT NOT NULL,  -- 0-23 in user's local time
    activity_count INT DEFAULT 0,
    session_duration_minutes INT DEFAULT 0,
    peak_activity_hour BOOLEAN DEFAULT FALSE,
    is_working_hours BOOLEAN DEFAULT FALSE,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_date_hour (user_id, activity_date, activity_hour_local),
    INDEX idx_timezone_activity (timezone_name, activity_date, activity_hour_local),
    INDEX idx_peak_activity (peak_activity_hour, activity_date)
);

-- Timezone activity aggregation
CREATE VIEW timezone_activity_summary AS
SELECT 
    timezone_name,
    activity_date,
    activity_hour_local,
    SUM(activity_count) as total_activities,
    AVG(session_duration_minutes) as avg_session_duration,
    COUNT(DISTINCT user_id) as active_users,
    CASE 
        WHEN SUM(activity_count) > (
            SELECT AVG(daily_activity) 
            FROM (
                SELECT SUM(activity_count) as daily_activity
                FROM timezone_analytics ta2
                WHERE ta2.timezone_name = ta.timezone_name
                AND ta2.activity_date >= DATE_SUB(ta.activity_date, INTERVAL 7 DAY)
                GROUP BY ta2.activity_date
            ) daily_avg
        ) THEN TRUE
        ELSE FALSE
    END as is_peak_hour
FROM timezone_analytics ta
WHERE activity_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY timezone_name, activity_date, activity_hour_local
ORDER BY timezone_name, activity_date, activity_hour_local;
```

### The "DST Impact Analysis" Pattern
```sql
-- DST transition impact analysis
CREATE TABLE dst_impact_analysis (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timezone_name VARCHAR(50) NOT NULL,
    transition_date DATE NOT NULL,
    transition_type ENUM('spring_forward', 'fall_back') NOT NULL,
    metric_name VARCHAR(50) NOT NULL,  -- 'user_activity', 'meeting_attendance', 'system_usage'
    pre_transition_value DECIMAL(15,2) NOT NULL,
    post_transition_value DECIMAL(15,2) NOT NULL,
    impact_percentage DECIMAL(5,2) NOT NULL,
    analysis_period_days INT DEFAULT 7,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_timezone_transition (timezone_name, transition_date, transition_type),
    INDEX idx_impact (impact_percentage DESC),
    INDEX idx_metric (metric_name, transition_date)
);

-- DST impact calculation
DELIMITER $$
CREATE PROCEDURE analyze_dst_impact(
    IN timezone_name VARCHAR(50),
    IN transition_date DATE,
    IN transition_type VARCHAR(20)
)
BEGIN
    DECLARE pre_transition_activity DECIMAL(15,2);
    DECLARE post_transition_activity DECIMAL(15,2);
    DECLARE impact_percentage DECIMAL(5,2);
    
    -- Calculate activity before DST transition
    SELECT AVG(activity_count) INTO pre_transition_activity
    FROM timezone_analytics
    WHERE timezone_name = timezone_name
    AND activity_date BETWEEN DATE_SUB(transition_date, INTERVAL 7 DAY) AND transition_date;
    
    -- Calculate activity after DST transition
    SELECT AVG(activity_count) INTO post_transition_activity
    FROM timezone_analytics
    WHERE timezone_name = timezone_name
    AND activity_date BETWEEN transition_date AND DATE_ADD(transition_date, INTERVAL 7 DAY);
    
    -- Calculate impact percentage
    SET impact_percentage = ((post_transition_activity - pre_transition_activity) / pre_transition_activity) * 100;
    
    -- Store impact analysis
    INSERT INTO dst_impact_analysis (
        timezone_name, transition_date, transition_type,
        metric_name, pre_transition_value, post_transition_value,
        impact_percentage
    )
    VALUES (
        timezone_name, transition_date, transition_type,
        'user_activity', pre_transition_activity, post_transition_activity,
        impact_percentage
    );
END$$
DELIMITER ;
```

These timezone patterns show the real-world techniques that product engineers use to handle global time coordination and DST transitions! 🚀
