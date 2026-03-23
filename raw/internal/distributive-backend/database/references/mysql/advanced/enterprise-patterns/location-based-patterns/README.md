# Location-Based & Ride-Hailing Patterns

Real-world location-based patterns, ride-hailing algorithms, and geospatial techniques used by product engineers at Uber, Lyft, DoorDash, and other location-based services.

## 🚗 Uber-Style Ride-Hailing Patterns

### The "Driver Location Tracking" Pattern
```sql
-- Driver location and status tracking
CREATE TABLE driver_locations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    driver_id BIGINT NOT NULL,
    latitude DECIMAL(10,8) NOT NULL,
    longitude DECIMAL(11,8) NOT NULL,
    accuracy_meters DECIMAL(5,2) NULL,
    heading_degrees DECIMAL(5,2) NULL,  -- Direction driver is facing
    speed_kmh DECIMAL(5,2) NULL,
    altitude_meters DECIMAL(8,2) NULL,
    location_source ENUM('gps', 'network', 'manual') DEFAULT 'gps',
    is_online BOOLEAN DEFAULT FALSE,
    current_status ENUM('offline', 'online', 'busy', 'on_trip') DEFAULT 'offline',
    vehicle_id BIGINT NULL,
    last_location_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_driver_location (driver_id, is_online, current_status),
    INDEX idx_location_coords (latitude, longitude),
    INDEX idx_online_drivers (is_online, current_status, last_location_update),
    SPATIAL INDEX idx_spatial_location (latitude, longitude)
);

-- Driver availability and preferences
CREATE TABLE driver_availability (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    driver_id BIGINT NOT NULL,
    is_available BOOLEAN DEFAULT TRUE,
    preferred_areas JSON,  -- Array of preferred service areas
    max_trip_distance_km DECIMAL(8,2) NULL,
    min_fare_amount DECIMAL(8,2) NULL,
    vehicle_types JSON,  -- ['uberx', 'comfort', 'xl']
    service_types JSON,  -- ['ride', 'delivery', 'both']
    working_hours JSON,  -- Working schedule
    surge_multiplier_threshold DECIMAL(3,2) DEFAULT 1.5,
    auto_accept_rides BOOLEAN DEFAULT FALSE,
    last_availability_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_driver_availability (driver_id),
    INDEX idx_available_drivers (is_available, last_availability_update),
    INDEX idx_service_types ((CAST(service_types->>'$.types' AS CHAR(50))))
);

-- Driver earnings and incentives
CREATE TABLE driver_earnings (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    driver_id BIGINT NOT NULL,
    trip_id BIGINT NULL,
    earnings_date DATE NOT NULL,
    base_fare DECIMAL(8,2) NOT NULL,
    distance_fare DECIMAL(8,2) NOT NULL,
    time_fare DECIMAL(8,2) NOT NULL,
    surge_multiplier DECIMAL(3,2) DEFAULT 1.0,
    surge_bonus DECIMAL(8,2) DEFAULT 0,
    tip_amount DECIMAL(8,2) DEFAULT 0,
    cancellation_fee DECIMAL(8,2) DEFAULT 0,
    total_earnings DECIMAL(8,2) NOT NULL,
    platform_fee DECIMAL(8,2) NOT NULL,
    net_earnings DECIMAL(8,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_driver_earnings (driver_id, earnings_date),
    INDEX idx_trip_earnings (trip_id),
    INDEX idx_earnings_date (earnings_date, total_earnings)
);
```

### The "Ride Request & Matching" Pattern
```sql
-- Ride requests
CREATE TABLE ride_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(50) UNIQUE NOT NULL,
    rider_id BIGINT NOT NULL,
    pickup_latitude DECIMAL(10,8) NOT NULL,
    pickup_longitude DECIMAL(11,8) NOT NULL,
    dropoff_latitude DECIMAL(10,8) NOT NULL,
    dropoff_longitude DECIMAL(11,8) NOT NULL,
    pickup_address TEXT NOT NULL,
    dropoff_address TEXT NOT NULL,
    estimated_distance_km DECIMAL(8,2) NOT NULL,
    estimated_duration_minutes INT NOT NULL,
    estimated_fare DECIMAL(8,2) NOT NULL,
    vehicle_type ENUM('uberx', 'comfort', 'xl', 'premium') DEFAULT 'uberx',
    request_status ENUM('pending', 'searching', 'matched', 'accepted', 'arrived', 'in_progress', 'completed', 'cancelled') DEFAULT 'pending',
    surge_multiplier DECIMAL(3,2) DEFAULT 1.0,
    priority_level ENUM('normal', 'high', 'urgent') DEFAULT 'normal',
    special_requests JSON,  -- Wheelchair accessible, child seat, etc.
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    matched_at TIMESTAMP NULL,
    accepted_at TIMESTAMP NULL,
    cancelled_at TIMESTAMP NULL,
    
    INDEX idx_rider_requests (rider_id, request_status),
    INDEX idx_request_status (request_status, created_at),
    INDEX idx_pickup_location (pickup_latitude, pickup_longitude),
    INDEX idx_vehicle_type (vehicle_type, request_status),
    SPATIAL INDEX idx_spatial_pickup (pickup_latitude, pickup_longitude),
    SPATIAL INDEX idx_spatial_dropoff (dropoff_latitude, dropoff_longitude)
);

-- Driver-rider matching
CREATE TABLE ride_matches (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id BIGINT NOT NULL,
    driver_id BIGINT NOT NULL,
    match_score DECIMAL(5,2) NOT NULL,  -- 0-100 score
    distance_to_pickup_km DECIMAL(8,2) NOT NULL,
    estimated_arrival_minutes INT NOT NULL,
    driver_rating DECIMAL(3,2) NOT NULL,
    driver_vehicle_type ENUM('uberx', 'comfort', 'xl', 'premium') NOT NULL,
    surge_multiplier DECIMAL(3,2) DEFAULT 1.0,
    match_status ENUM('proposed', 'accepted', 'rejected', 'expired') DEFAULT 'proposed',
    proposed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP NULL,
    response_time_seconds INT NULL,
    
    UNIQUE KEY uk_request_driver (request_id, driver_id),
    INDEX idx_driver_matches (driver_id, match_status),
    INDEX idx_match_score (match_score DESC, proposed_at),
    INDEX idx_distance_pickup (distance_to_pickup_km, match_status)
);

-- Matching algorithm results
CREATE TABLE matching_algorithm_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id BIGINT NOT NULL,
    algorithm_version VARCHAR(20) NOT NULL,
    search_radius_km DECIMAL(8,2) NOT NULL,
    candidates_found INT NOT NULL,
    candidates_evaluated INT NOT NULL,
    top_candidate_driver_id BIGINT NULL,
    top_candidate_score DECIMAL(5,2) NULL,
    matching_criteria JSON,  -- Criteria used for matching
    execution_time_ms INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_request_algorithm (request_id, algorithm_version),
    INDEX idx_algorithm_performance (algorithm_version, execution_time_ms),
    INDEX idx_candidates_found (candidates_found, created_at)
);
```

### The "Nearest Driver Algorithm" Pattern
```sql
-- Nearest driver search function
DELIMITER $$
CREATE FUNCTION calculate_distance_km(
    lat1 DECIMAL(10,8),
    lon1 DECIMAL(11,8),
    lat2 DECIMAL(10,8),
    lon2 DECIMAL(11,8)
) 
RETURNS DECIMAL(8,2)
DETERMINISTIC
BEGIN
    -- Haversine formula for calculating distance between two points
    DECLARE R DECIMAL(8,2) DEFAULT 6371;  -- Earth's radius in km
    DECLARE dlat DECIMAL(10,8);
    DECLARE dlon DECIMAL(11,8);
    DECLARE a DECIMAL(15,10);
    DECLARE c DECIMAL(15,10);
    
    SET dlat = RADIANS(lat2 - lat1);
    SET dlon = RADIANS(lon2 - lon1);
    SET a = SIN(dlat/2) * SIN(dlat/2) + 
            COS(RADIANS(lat1)) * COS(RADIANS(lat2)) * 
            SIN(dlon/2) * SIN(dlon/2);
    SET c = 2 * ATAN2(SQRT(a), SQRT(1-a));
    
    RETURN R * c;
END$$

-- Find nearest available drivers
CREATE PROCEDURE find_nearest_drivers(
    IN pickup_lat DECIMAL(10,8),
    IN pickup_lon DECIMAL(11,8),
    IN vehicle_type VARCHAR(20),
    IN search_radius_km DECIMAL(8,2),
    IN max_drivers INT
)
BEGIN
    SELECT 
        dl.driver_id,
        dl.latitude,
        dl.longitude,
        dl.current_status,
        da.is_available,
        da.vehicle_types,
        da.service_types,
        calculate_distance_km(pickup_lat, pickup_lon, dl.latitude, dl.longitude) as distance_km,
        -- Calculate ETA based on distance and average speed
        ROUND(calculate_distance_km(pickup_lat, pickup_lon, dl.latitude, dl.longitude) / 30 * 60) as eta_minutes,
        -- Calculate match score based on multiple factors
        (
            -- Distance factor (closer is better)
            (1 - (calculate_distance_km(pickup_lat, pickup_lon, dl.latitude, dl.longitude) / search_radius_km)) * 40 +
            -- Driver rating factor
            COALESCE((SELECT AVG(rating) FROM driver_ratings WHERE driver_id = dl.driver_id), 4.0) * 10 +
            -- Availability factor
            (CASE WHEN da.is_available = TRUE THEN 20 ELSE 0 END) +
            -- Vehicle type match factor
            (CASE WHEN JSON_CONTAINS(da.vehicle_types, JSON_QUOTE(vehicle_type)) THEN 20 ELSE 0 END) +
            -- Recent activity factor
            (CASE WHEN dl.last_location_update > DATE_SUB(NOW(), INTERVAL 5 MINUTE) THEN 10 ELSE 0 END)
        ) as match_score
    FROM driver_locations dl
    JOIN driver_availability da ON dl.driver_id = da.driver_id
    WHERE dl.is_online = TRUE
    AND dl.current_status = 'online'
    AND da.is_available = TRUE
    AND JSON_CONTAINS(da.vehicle_types, JSON_QUOTE(vehicle_type))
    AND calculate_distance_km(pickup_lat, pickup_lon, dl.latitude, dl.longitude) <= search_radius_km
    ORDER BY match_score DESC, distance_km ASC
    LIMIT max_drivers;
END$$

-- Real-time driver location update
CREATE PROCEDURE update_driver_location(
    IN driver_id BIGINT,
    IN latitude DECIMAL(10,8),
    IN longitude DECIMAL(11,8),
    IN accuracy_meters DECIMAL(5,2),
    IN heading_degrees DECIMAL(5,2),
    IN speed_kmh DECIMAL(5,2),
    IN current_status VARCHAR(20)
)
BEGIN
    INSERT INTO driver_locations (
        driver_id, latitude, longitude, accuracy_meters, 
        heading_degrees, speed_kmh, current_status
    )
    VALUES (
        driver_id, latitude, longitude, accuracy_meters,
        heading_degrees, speed_kmh, current_status
    )
    ON DUPLICATE KEY UPDATE
        latitude = VALUES(latitude),
        longitude = VALUES(longitude),
        accuracy_meters = VALUES(accuracy_meters),
        heading_degrees = VALUES(heading_degrees),
        speed_kmh = VALUES(speed_kmh),
        current_status = VALUES(current_status),
        last_location_update = NOW();
END$$
DELIMITER ;
```

## 🍕 DoorDash-Style Delivery Patterns

### The "Restaurant & Order Management" Pattern
```sql
-- Restaurant locations and menu
CREATE TABLE restaurants (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    restaurant_id VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    cuisine_type VARCHAR(100) NOT NULL,
    latitude DECIMAL(10,8) NOT NULL,
    longitude DECIMAL(11,8) NOT NULL,
    address TEXT NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    is_open BOOLEAN DEFAULT FALSE,
    preparation_time_minutes INT DEFAULT 20,
    delivery_radius_km DECIMAL(8,2) DEFAULT 5.0,
    minimum_order_amount DECIMAL(8,2) DEFAULT 0,
    delivery_fee DECIMAL(8,2) DEFAULT 0,
    rating DECIMAL(3,2) DEFAULT 0,
    total_orders INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_restaurant_location (latitude, longitude),
    INDEX idx_cuisine_type (cuisine_type, is_active),
    INDEX idx_restaurant_status (is_active, is_open),
    SPATIAL INDEX idx_spatial_restaurant (latitude, longitude)
);

-- Delivery orders
CREATE TABLE delivery_orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(50) UNIQUE NOT NULL,
    customer_id BIGINT NOT NULL,
    restaurant_id BIGINT NOT NULL,
    driver_id BIGINT NULL,
    order_status ENUM('pending', 'confirmed', 'preparing', 'ready', 'picked_up', 'in_transit', 'delivered', 'cancelled') DEFAULT 'pending',
    order_total DECIMAL(10,2) NOT NULL,
    delivery_fee DECIMAL(8,2) NOT NULL,
    tip_amount DECIMAL(8,2) DEFAULT 0,
    total_amount DECIMAL(10,2) NOT NULL,
    pickup_latitude DECIMAL(10,8) NOT NULL,
    pickup_longitude DECIMAL(11,8) NOT NULL,
    delivery_latitude DECIMAL(10,8) NOT NULL,
    delivery_longitude DECIMAL(11,8) NOT NULL,
    estimated_distance_km DECIMAL(8,2) NOT NULL,
    estimated_delivery_time_minutes INT NOT NULL,
    actual_delivery_time_minutes INT NULL,
    special_instructions TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    confirmed_at TIMESTAMP NULL,
    ready_at TIMESTAMP NULL,
    picked_up_at TIMESTAMP NULL,
    delivered_at TIMESTAMP NULL,
    
    INDEX idx_customer_orders (customer_id, order_status),
    INDEX idx_restaurant_orders (restaurant_id, order_status),
    INDEX idx_driver_orders (driver_id, order_status),
    INDEX idx_order_status (order_status, created_at),
    INDEX idx_delivery_location (delivery_latitude, delivery_longitude)
);

-- Driver assignment for deliveries
CREATE TABLE delivery_assignments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    driver_id BIGINT NOT NULL,
    assignment_score DECIMAL(5,2) NOT NULL,
    distance_to_restaurant_km DECIMAL(8,2) NOT NULL,
    distance_to_customer_km DECIMAL(8,2) NOT NULL,
    total_route_distance_km DECIMAL(8,2) NOT NULL,
    estimated_pickup_time_minutes INT NOT NULL,
    estimated_delivery_time_minutes INT NOT NULL,
    assignment_status ENUM('proposed', 'accepted', 'rejected', 'expired') DEFAULT 'proposed',
    proposed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP NULL,
    
    UNIQUE KEY uk_order_driver (order_id, driver_id),
    INDEX idx_driver_assignments (driver_id, assignment_status),
    INDEX idx_assignment_score (assignment_score DESC, proposed_at)
);
```

### The "Multi-Drop Delivery" Pattern
```sql
-- Multi-drop delivery routes
CREATE TABLE delivery_routes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    route_id VARCHAR(50) UNIQUE NOT NULL,
    driver_id BIGINT NOT NULL,
    route_status ENUM('planned', 'in_progress', 'completed', 'cancelled') DEFAULT 'planned',
    total_stops INT NOT NULL,
    total_distance_km DECIMAL(8,2) NOT NULL,
    estimated_duration_minutes INT NOT NULL,
    actual_duration_minutes INT NULL,
    fuel_cost DECIMAL(8,2) DEFAULT 0,
    route_optimization_score DECIMAL(5,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    
    INDEX idx_driver_routes (driver_id, route_status),
    INDEX idx_route_status (route_status, created_at)
);

-- Route stops (restaurants and customers)
CREATE TABLE route_stops (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    route_id BIGINT NOT NULL,
    order_id BIGINT NOT NULL,
    stop_sequence INT NOT NULL,
    stop_type ENUM('pickup', 'delivery') NOT NULL,
    latitude DECIMAL(10,8) NOT NULL,
    longitude DECIMAL(11,8) NOT NULL,
    estimated_arrival_time TIMESTAMP NOT NULL,
    actual_arrival_time TIMESTAMP NULL,
    stop_status ENUM('pending', 'in_progress', 'completed', 'skipped') DEFAULT 'pending',
    wait_time_minutes INT DEFAULT 0,
    
    UNIQUE KEY uk_route_stop (route_id, stop_sequence),
    INDEX idx_route_stops (route_id, stop_sequence),
    INDEX idx_order_stops (order_id, stop_type),
    INDEX idx_stop_status (stop_status, estimated_arrival_time)
);

-- Route optimization algorithm
DELIMITER $$
CREATE PROCEDURE optimize_delivery_route(
    IN driver_id BIGINT,
    IN max_orders INT DEFAULT 5
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE current_lat DECIMAL(10,8);
    DECLARE current_lon DECIMAL(11,8);
    DECLARE route_id VARCHAR(50);
    DECLARE stop_sequence INT DEFAULT 1;
    
    -- Get driver's current location
    SELECT latitude, longitude INTO current_lat, current_lon
    FROM driver_locations
    WHERE driver_id = driver_id
    ORDER BY last_location_update DESC
    LIMIT 1;
    
    -- Create new route
    SET route_id = CONCAT('ROUTE-', UNIX_TIMESTAMP(), '-', driver_id);
    
    INSERT INTO delivery_routes (route_id, driver_id, total_stops, total_distance_km, estimated_duration_minutes)
    VALUES (route_id, driver_id, 0, 0, 0);
    
    -- Find nearby pending orders and optimize route
    -- This would implement a more sophisticated algorithm like:
    -- 1. Nearest neighbor
    -- 2. Genetic algorithm
    -- 3. Ant colony optimization
    -- 4. Machine learning-based optimization
    
    -- For demo purposes, we'll use a simple nearest neighbor approach
    -- In real implementation, this would be much more complex
    
END$$
DELIMITER ;
```

## 📍 Location-Based Analytics

### The "Geospatial Analytics" Pattern
```sql
-- Location-based analytics
CREATE TABLE location_analytics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    location_type ENUM('pickup', 'dropoff', 'driver_location', 'hotspot') NOT NULL,
    latitude DECIMAL(10,8) NOT NULL,
    longitude DECIMAL(11,8) NOT NULL,
    geohash VARCHAR(12) NOT NULL,  -- For spatial indexing
    activity_count INT DEFAULT 0,
    revenue_amount DECIMAL(15,2) DEFAULT 0,
    peak_hour_start TIME,
    peak_hour_end TIME,
    average_wait_time_minutes DECIMAL(5,2) DEFAULT 0,
    surge_multiplier_avg DECIMAL(3,2) DEFAULT 1.0,
    analysis_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_location_analytics (geohash, location_type, analysis_date),
    INDEX idx_activity_count (activity_count DESC, analysis_date),
    INDEX idx_revenue_amount (revenue_amount DESC, analysis_date)
);

-- Hotspot detection
CREATE TABLE hotspots (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    hotspot_id VARCHAR(50) UNIQUE NOT NULL,
    center_latitude DECIMAL(10,8) NOT NULL,
    center_longitude DECIMAL(11,8) NOT NULL,
    radius_km DECIMAL(8,2) NOT NULL,
    hotspot_type ENUM('demand', 'supply', 'surge') NOT NULL,
    intensity_score DECIMAL(5,2) NOT NULL,  -- 0-100
    demand_count INT DEFAULT 0,
    supply_count INT DEFAULT 0,
    surge_multiplier DECIMAL(3,2) DEFAULT 1.0,
    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    
    INDEX idx_hotspot_location (center_latitude, center_longitude),
    INDEX idx_hotspot_type (hotspot_type, intensity_score),
    INDEX idx_hotspot_active (is_active, expires_at),
    SPATIAL INDEX idx_spatial_hotspot (center_latitude, center_longitude)
);

-- Surge pricing zones
CREATE TABLE surge_zones (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    zone_id VARCHAR(50) UNIQUE NOT NULL,
    zone_name VARCHAR(100) NOT NULL,
    center_latitude DECIMAL(10,8) NOT NULL,
    center_longitude DECIMAL(11,8) NOT NULL,
    radius_km DECIMAL(8,2) NOT NULL,
    base_multiplier DECIMAL(3,2) DEFAULT 1.0,
    current_multiplier DECIMAL(3,2) DEFAULT 1.0,
    max_multiplier DECIMAL(3,2) DEFAULT 3.0,
    demand_threshold INT DEFAULT 10,
    supply_threshold INT DEFAULT 5,
    surge_algorithm JSON,  -- Algorithm parameters
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_surge_zones (center_latitude, center_longitude),
    INDEX idx_current_multiplier (current_multiplier DESC, is_active),
    INDEX idx_zone_active (is_active, updated_at)
);

-- Surge pricing calculation
DELIMITER $$
CREATE PROCEDURE calculate_surge_pricing(
    IN zone_id VARCHAR(50)
)
BEGIN
    DECLARE current_demand INT;
    DECLARE current_supply INT;
    DECLARE demand_supply_ratio DECIMAL(5,2);
    DECLARE new_multiplier DECIMAL(3,2);
    DECLARE base_multiplier DECIMAL(3,2);
    DECLARE max_multiplier DECIMAL(3,2);
    
    -- Get zone parameters
    SELECT base_multiplier, max_multiplier INTO base_multiplier, max_multiplier
    FROM surge_zones
    WHERE zone_id = zone_id;
    
    -- Calculate current demand and supply
    SELECT 
        COUNT(*) as demand_count,
        (SELECT COUNT(*) FROM driver_locations dl 
         JOIN surge_zones sz ON calculate_distance_km(dl.latitude, dl.longitude, sz.center_latitude, sz.center_longitude) <= sz.radius_km
         WHERE sz.zone_id = zone_id AND dl.is_online = TRUE AND dl.current_status = 'online') as supply_count
    INTO current_demand, current_supply
    FROM ride_requests rr
    JOIN surge_zones sz ON calculate_distance_km(rr.pickup_latitude, rr.pickup_longitude, sz.center_latitude, sz.center_longitude) <= sz.radius_km
    WHERE sz.zone_id = zone_id 
    AND rr.request_status IN ('pending', 'searching')
    AND rr.created_at > DATE_SUB(NOW(), INTERVAL 5 MINUTE);
    
    -- Calculate demand-supply ratio
    IF current_supply > 0 THEN
        SET demand_supply_ratio = current_demand / current_supply;
    ELSE
        SET demand_supply_ratio = current_demand;
    END IF;
    
    -- Calculate new surge multiplier
    IF demand_supply_ratio > 2.0 THEN
        SET new_multiplier = LEAST(base_multiplier * demand_supply_ratio, max_multiplier);
    ELSE
        SET new_multiplier = base_multiplier;
    END IF;
    
    -- Update surge zone
    UPDATE surge_zones 
    SET current_multiplier = new_multiplier,
        updated_at = NOW()
    WHERE zone_id = zone_id;
    
    -- Log surge calculation
    INSERT INTO surge_calculation_logs (
        zone_id, current_demand, current_supply, 
        demand_supply_ratio, new_multiplier
    )
    VALUES (
        zone_id, current_demand, current_supply,
        demand_supply_ratio, new_multiplier
    );
END$$
DELIMITER ;
```

## 🚀 Real-Time Location Services

### The "Real-Time Tracking" Pattern
```sql
-- Real-time trip tracking
CREATE TABLE trip_tracking (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    trip_id BIGINT NOT NULL,
    driver_id BIGINT NOT NULL,
    rider_id BIGINT NOT NULL,
    latitude DECIMAL(10,8) NOT NULL,
    longitude DECIMAL(11,8) NOT NULL,
    accuracy_meters DECIMAL(5,2) NULL,
    speed_kmh DECIMAL(5,2) NULL,
    heading_degrees DECIMAL(5,2) NULL,
    trip_phase ENUM('pickup', 'in_transit', 'dropoff') NOT NULL,
    estimated_arrival_minutes INT NULL,
    distance_remaining_km DECIMAL(8,2) NULL,
    tracking_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_trip_tracking (trip_id, tracking_timestamp),
    INDEX idx_driver_tracking (driver_id, tracking_timestamp),
    INDEX idx_trip_phase (trip_phase, tracking_timestamp)
);

-- Location-based notifications
CREATE TABLE location_notifications (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    notification_type ENUM('driver_nearby', 'surge_alert', 'promo_zone', 'safety_alert') NOT NULL,
    latitude DECIMAL(10,8) NOT NULL,
    longitude DECIMAL(11,8) NOT NULL,
    notification_message TEXT NOT NULL,
    notification_data JSON,
    is_sent BOOLEAN DEFAULT FALSE,
    sent_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_user_notifications (user_id, is_sent),
    INDEX idx_notification_type (notification_type, created_at),
    INDEX idx_location_notifications (latitude, longitude, notification_type)
);
```

These location-based patterns show the real-world techniques that product engineers use to build scalable ride-hailing and delivery systems! 🚀
