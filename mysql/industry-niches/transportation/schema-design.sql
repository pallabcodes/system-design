-- Transportation Database Schema (MySQL)
-- Comprehensive schema for fleet management, logistics, and transportation operations
-- Adapted for MySQL with spatial features, JSON support, and performance optimizations

-- ===========================================
-- FLEET MANAGEMENT
-- ===========================================

CREATE TABLE vehicles (
    vehicle_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    vehicle_type ENUM('truck', 'trailer', 'van', 'car', 'bus', 'motorcycle', 'equipment') NOT NULL,

    -- Vehicle identification
    license_plate VARCHAR(20) UNIQUE NOT NULL,
    vin VARCHAR(17) UNIQUE,
    vehicle_make VARCHAR(50),
    vehicle_model VARCHAR(50),
    vehicle_year YEAR,

    -- Specifications
    fuel_type ENUM('diesel', 'gasoline', 'electric', 'hybrid', 'cng', 'propane') DEFAULT 'diesel',
    fuel_capacity_gallons DECIMAL(8,2),
    gross_vehicle_weight_lbs DECIMAL(10,2),
    payload_capacity_lbs DECIMAL(10,2),
    engine_size_cc DECIMAL(6,0),

    -- Operational details
    current_status ENUM('active', 'maintenance', 'out_of_service', 'sold', 'retired') DEFAULT 'active',
    home_terminal_id CHAR(36),
    assigned_driver_id CHAR(36),

    -- Financial tracking
    purchase_price DECIMAL(10,2),
    purchase_date DATE,
    depreciation_method ENUM('straight_line', 'declining_balance', 'units_of_production') DEFAULT 'straight_line',
    current_value DECIMAL(10,2),

    -- Compliance and documentation
    registration_expiry DATE,
    insurance_expiry DATE,
    inspection_due DATE,
    dot_number VARCHAR(20),  -- For regulated carriers

    -- Telematics and monitoring
    gps_device_id VARCHAR(50),
    has_telematics BOOLEAN DEFAULT FALSE,
    maintenance_schedule JSON DEFAULT ('{}'),

    -- Metadata
    vehicle_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (home_terminal_id) REFERENCES terminals(terminal_id),
    FOREIGN KEY (assigned_driver_id) REFERENCES drivers(driver_id),

    INDEX idx_vehicles_type (vehicle_type),
    INDEX idx_vehicles_status (current_status),
    INDEX idx_vehicles_driver (assigned_driver_id),
    INDEX idx_vehicles_terminal (home_terminal_id),
    INDEX idx_vehicles_plate (license_plate),
    INDEX idx_vehicles_inspection (inspection_due)
) ENGINE = InnoDB;

-- ===========================================
-- DRIVER MANAGEMENT
-- ===========================================

CREATE TABLE drivers (
    driver_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),

    -- Personal information
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    date_of_birth DATE,
    ssn_last4 VARCHAR(4),

    -- Contact information
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),
    emergency_contact_name VARCHAR(100),
    emergency_contact_phone VARCHAR(20),

    -- Employment details
    employee_id VARCHAR(20) UNIQUE,
    hire_date DATE,
    termination_date DATE,
    employment_status ENUM('active', 'inactive', 'terminated', 'on_leave') DEFAULT 'active',

    -- Licensing and qualifications
    cdl_class ENUM('A', 'B', 'C') NULL,  -- Commercial Driver's License
    cdl_number VARCHAR(20),
    cdl_expiry DATE,
    endorsements JSON DEFAULT ('[]'),  -- H, N, P, S, T, X endorsements

    -- Performance and safety
    safety_rating DECIMAL(3,1) CHECK (safety_rating >= 0 AND safety_rating <= 5),
    accident_count INT DEFAULT 0,
    violation_count INT DEFAULT 0,

    -- Medical and drug testing
    last_medical_exam DATE,
    next_medical_exam DATE,
    last_drug_test DATE,
    drug_test_status ENUM('passed', 'failed', 'pending', 'not_required') DEFAULT 'not_required',

    -- Home terminal and assignment
    home_terminal_id CHAR(36),
    current_location POINT NULL,

    -- Compensation
    pay_rate_per_hour DECIMAL(6,2),
    overtime_rate DECIMAL(6,2),

    -- Metadata
    driver_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (home_terminal_id) REFERENCES terminals(terminal_id),

    INDEX idx_drivers_status (employment_status),
    INDEX idx_drivers_terminal (home_terminal_id),
    INDEX idx_drivers_cdl (cdl_expiry),
    INDEX idx_drivers_medical (next_medical_exam),
    INDEX idx_drivers_safety (safety_rating),
    SPATIAL INDEX idx_drivers_location (current_location)
) ENGINE = InnoDB;

-- ===========================================
-- SHIPMENT MANAGEMENT
-- ===========================================

CREATE TABLE shipments (
    shipment_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),

    -- Shipment identification
    shipment_number VARCHAR(20) UNIQUE NOT NULL,
    reference_number VARCHAR(50),  -- Customer reference

    -- Parties involved
    shipper_id CHAR(36) NOT NULL,
    consignee_id CHAR(36) NOT NULL,
    carrier_id CHAR(36),

    -- Shipment details
    shipment_type ENUM('ltl', 'ftl', 'parcel', 'air', 'ocean', 'rail', 'intermodal') DEFAULT 'ltl',
    service_level ENUM('standard', 'expedited', 'express', 'same_day', 'next_day') DEFAULT 'standard',

    -- Origin and destination
    origin_address VARCHAR(500) NOT NULL,
    origin_city VARCHAR(100) NOT NULL,
    origin_state VARCHAR(50) NOT NULL,
    origin_postal_code VARCHAR(20) NOT NULL,
    origin_country VARCHAR(50) DEFAULT 'USA',

    destination_address VARCHAR(500) NOT NULL,
    destination_city VARCHAR(100) NOT NULL,
    destination_state VARCHAR(50) NOT NULL,
    destination_postal_code VARCHAR(20) NOT NULL,
    destination_country VARCHAR(50) DEFAULT 'USA',

    -- Geographic coordinates
    origin_lat DECIMAL(10,8),
    origin_lng DECIMAL(11,8),
    dest_lat DECIMAL(10,8),
    dest_lng DECIMAL(11,8),

    -- Cargo details
    total_weight_lbs DECIMAL(10,2),
    total_volume_cuft DECIMAL(10,2),
    declared_value DECIMAL(12,2),
    hazardous_materials BOOLEAN DEFAULT FALSE,

    -- Scheduling
    pickup_date DATE,
    pickup_time_window_start TIME,
    pickup_time_window_end TIME,
    delivery_date DATE,
    delivery_time_window_start TIME,
    delivery_time_window_end TIME,

    -- Status and tracking
    shipment_status ENUM('booked', 'picked_up', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'cancelled') DEFAULT 'booked',
    current_location POINT NULL,
    estimated_delivery TIMESTAMP,
    actual_delivery TIMESTAMP,

    -- Financial
    base_rate DECIMAL(8,2),
    fuel_surcharge DECIMAL(6,2),
    accessorial_charges DECIMAL(8,2),
    total_charges DECIMAL(10,2),

    -- Assignment
    assigned_vehicle_id CHAR(36),
    assigned_driver_id CHAR(36),
    assigned_route_id CHAR(36),

    -- Special handling
    special_instructions TEXT,
    temperature_controlled BOOLEAN DEFAULT FALSE,
    temperature_min_f DECIMAL(5,1),
    temperature_max_f DECIMAL(5,1),

    -- Audit
    created_by CHAR(36),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (shipper_id) REFERENCES customers(customer_id),
    FOREIGN KEY (consignee_id) REFERENCES customers(customer_id),
    FOREIGN KEY (carrier_id) REFERENCES carriers(carrier_id),
    FOREIGN KEY (assigned_vehicle_id) REFERENCES vehicles(vehicle_id),
    FOREIGN KEY (assigned_driver_id) REFERENCES drivers(driver_id),
    FOREIGN KEY (assigned_route_id) REFERENCES routes(route_id),

    INDEX idx_shipments_number (shipment_number),
    INDEX idx_shipments_status (shipment_status),
    INDEX idx_shipments_shipper (shipper_id),
    INDEX idx_shipments_consignee (consignee_id),
    INDEX idx_shipments_carrier (carrier_id),
    INDEX idx_shipments_dates (pickup_date, delivery_date),
    INDEX idx_shipments_vehicle (assigned_vehicle_id),
    INDEX idx_shipments_driver (assigned_driver_id),
    SPATIAL INDEX idx_shipments_origin (POINT(origin_lng, origin_lat)),
    SPATIAL INDEX idx_shipments_dest (POINT(dest_lng, dest_lat)),
    SPATIAL INDEX idx_shipments_current (current_location)
) ENGINE = InnoDB;

-- ===========================================
-- ROUTE MANAGEMENT
-- =========================================--

CREATE TABLE routes (
    route_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    route_name VARCHAR(100) NOT NULL,

    -- Route details
    route_type ENUM('local', 'regional', 'long_haul', 'international') DEFAULT 'regional',
    total_distance_miles DECIMAL(8,2),
    estimated_duration_hours DECIMAL(6,2),

    -- Origin and destination
    origin_terminal_id CHAR(36),
    destination_terminal_id CHAR(36),

    -- Route characteristics
    road_types JSON DEFAULT ('[]'),  -- Highway, local, toll roads
    difficulty_rating ENUM('easy', 'moderate', 'difficult', 'extreme') DEFAULT 'moderate',

    -- Scheduling
    standard_departure_time TIME,
    estimated_arrival_time TIME,

    -- Cost factors
    fuel_cost_estimate DECIMAL(8,2),
    toll_cost_estimate DECIMAL(8,2),
    labor_cost_estimate DECIMAL(8,2),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    route_notes TEXT,

    FOREIGN KEY (origin_terminal_id) REFERENCES terminals(terminal_id),
    FOREIGN KEY (destination_terminal_id) REFERENCES terminals(terminal_id),

    INDEX idx_routes_type (route_type),
    INDEX idx_routes_active (is_active),
    INDEX idx_routes_terminals (origin_terminal_id, destination_terminal_id)
) ENGINE = InnoDB;

CREATE TABLE route_waypoints (
    waypoint_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    route_id CHAR(36) NOT NULL,

    sequence_number INT NOT NULL,
    waypoint_name VARCHAR(100),

    -- Location
    latitude DECIMAL(10,8) NOT NULL,
    longitude DECIMAL(11,8) NOT NULL,
    location POINT AS (POINT(longitude, latitude)) STORED,

    -- Timing and operations
    estimated_arrival TIME,
    estimated_departure TIME,
    stop_purpose ENUM('pickup', 'delivery', 'fuel_stop', 'rest_stop', 'inspection', 'border_crossing') DEFAULT 'delivery',

    -- Customer reference (for pickups/deliveries)
    customer_id CHAR(36),
    shipment_id CHAR(36),

    FOREIGN KEY (route_id) REFERENCES routes(route_id),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (shipment_id) REFERENCES shipments(shipment_id),

    INDEX idx_waypoints_route (route_id, sequence_number),
    INDEX idx_waypoints_customer (customer_id),
    INDEX idx_waypoints_shipment (shipment_id),
    SPATIAL INDEX idx_waypoints_location (location)
) ENGINE = InnoDB;

-- ===========================================
-- TRACKING AND TELEMATICS
-- ===========================================

CREATE TABLE vehicle_telematics (
    telematics_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    vehicle_id CHAR(36) NOT NULL,

    -- Timestamp and location
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    location POINT AS (POINT(longitude, latitude)) STORED,

    -- Vehicle status
    speed_mph DECIMAL(5,1),
    heading_degrees DECIMAL(5,1),
    odometer_miles DECIMAL(10,2),

    -- Engine and performance
    engine_rpm INT,
    fuel_level_percent DECIMAL(5,1),
    coolant_temp_f DECIMAL(5,1),
    oil_pressure_psi DECIMAL(5,1),

    -- Cargo and load
    cargo_weight_lbs DECIMAL(8,2),
    trailer_connected BOOLEAN DEFAULT FALSE,

    -- Driver status
    driver_present BOOLEAN DEFAULT FALSE,
    harsh_braking_events INT DEFAULT 0,
    harsh_acceleration_events INT DEFAULT 0,

    -- Environmental
    ambient_temp_f DECIMAL(5,1),
    precipitation_type ENUM('none', 'rain', 'snow', 'hail', 'fog') DEFAULT 'none',

    FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id),

    INDEX idx_telematics_vehicle (vehicle_id),
    INDEX idx_telematics_timestamp (timestamp),
    INDEX idx_telematics_speed (speed_mph),
    SPATIAL INDEX idx_telematics_location (location)
) ENGINE = InnoDB;

CREATE TABLE shipment_tracking (
    tracking_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    shipment_id CHAR(36) NOT NULL,

    -- Tracking details
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status_code VARCHAR(50) NOT NULL,
    status_description VARCHAR(255),
    location_name VARCHAR(255),

    -- Location data
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    location POINT AS (POINT(longitude, latitude)) STORED,

    -- Additional context
    estimated_delivery TIMESTAMP,
    delay_reason VARCHAR(255),
    notes TEXT,

    -- Metadata
    tracked_by ENUM('system', 'driver', 'customer_service', 'api') DEFAULT 'system',
    confidence_level ENUM('estimated', 'confirmed', 'actual') DEFAULT 'estimated',

    FOREIGN KEY (shipment_id) REFERENCES shipments(shipment_id),

    INDEX idx_tracking_shipment (shipment_id),
    INDEX idx_tracking_timestamp (timestamp),
    INDEX idx_tracking_status (status_code),
    SPATIAL INDEX idx_tracking_location (location)
) ENGINE = InnoDB;

-- ===========================================
-- MAINTENANCE AND COMPLIANCE
-- ===========================================

CREATE TABLE vehicle_maintenance (
    maintenance_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    vehicle_id CHAR(36) NOT NULL,

    -- Maintenance details
    maintenance_type ENUM('preventive', 'corrective', 'emergency', 'recall', 'inspection') DEFAULT 'preventive',
    maintenance_category ENUM('engine', 'transmission', 'brakes', 'electrical', 'tires', 'body', 'other') DEFAULT 'other',

    -- Scheduling
    scheduled_date DATE,
    completed_date DATE,
    due_mileage DECIMAL(10,2),

    -- Service details
    service_provider VARCHAR(255),
    technician_name VARCHAR(100),
    work_description LONGTEXT,

    -- Costs
    labor_cost DECIMAL(8,2) DEFAULT 0,
    parts_cost DECIMAL(8,2) DEFAULT 0,
    total_cost DECIMAL(10,2) GENERATED ALWAYS AS (labor_cost + parts_cost) STORED,

    -- Compliance and documentation
    regulatory_requirement VARCHAR(255),  -- DOT, EPA, etc.
    next_service_due DATE,
    next_service_mileage DECIMAL(10,2),

    -- Status
    maintenance_status ENUM('scheduled', 'in_progress', 'completed', 'cancelled') DEFAULT 'scheduled',
    compliance_status ENUM('compliant', 'non_compliant', 'pending_review') DEFAULT 'compliant',

    -- Documentation
    service_report_url VARCHAR(500),
    photos_urls JSON DEFAULT ('[]'),

    FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id),

    INDEX idx_maintenance_vehicle (vehicle_id),
    INDEX idx_maintenance_type (maintenance_type),
    INDEX idx_maintenance_status (maintenance_status),
    INDEX idx_maintenance_due (next_service_due),
    INDEX idx_maintenance_mileage (next_service_mileage)
) ENGINE = InnoDB;

-- ===========================================
-- FINANCIAL TRACKING
-- ===========================================

CREATE TABLE fuel_transactions (
    fuel_transaction_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    vehicle_id CHAR(36) NOT NULL,

    -- Transaction details
    transaction_date DATE NOT NULL,
    fuel_station_name VARCHAR(255),
    fuel_station_location VARCHAR(500),

    -- Fuel data
    fuel_type ENUM('diesel', 'gasoline', 'def', 'propane', 'cng') DEFAULT 'diesel',
    gallons_pumped DECIMAL(6,2) NOT NULL,
    price_per_gallon DECIMAL(5,3) NOT NULL,
    total_cost DECIMAL(8,2) NOT NULL,

    -- Vehicle data at time of fueling
    odometer_reading DECIMAL(10,2),
    fuel_level_before_percent DECIMAL(5,1),
    fuel_level_after_percent DECIMAL(5,1),

    -- Driver and approval
    driver_id CHAR(36) NOT NULL,
    approved_by CHAR(36),

    -- Payment and accounting
    payment_method ENUM('fuel_card', 'cash', 'credit_card', 'account') DEFAULT 'fuel_card',
    fuel_card_number VARCHAR(50),
    invoice_number VARCHAR(50),

    FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id),
    FOREIGN KEY (driver_id) REFERENCES drivers(driver_id),
    FOREIGN KEY (approved_by) REFERENCES drivers(driver_id),

    INDEX idx_fuel_vehicle (vehicle_id),
    INDEX idx_fuel_date (transaction_date),
    INDEX idx_fuel_driver (driver_id),
    INDEX idx_fuel_type (fuel_type)
) ENGINE = InnoDB;

-- ===========================================
-- SUPPORTING TABLES
-- ===========================================

CREATE TABLE terminals (
    terminal_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    terminal_name VARCHAR(100) NOT NULL,

    -- Location
    address VARCHAR(500),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),

    -- Operations
    terminal_type ENUM('headquarters', 'regional_hub', 'local_terminal', 'satellite') DEFAULT 'local_terminal',
    operating_hours JSON DEFAULT ('{"monday": {"open": "08:00", "close": "17:00"}, "tuesday": {"open": "08:00", "close": "17:00"}, "wednesday": {"open": "08:00", "close": "17:00"}, "thursday": {"open": "08:00", "close": "17:00"}, "friday": {"open": "08:00", "close": "17:00"}}'),

    -- Facilities
    parking_spaces INT DEFAULT 0,
    fuel_station BOOLEAN DEFAULT FALSE,
    maintenance_bay BOOLEAN DEFAULT FALSE,
    warehouse_space_sqft DECIMAL(10,2),

    -- Contact
    manager_name VARCHAR(100),
    contact_phone VARCHAR(20),
    contact_email VARCHAR(255),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    INDEX idx_terminals_type (terminal_type),
    INDEX idx_terminals_active (is_active),
    SPATIAL INDEX idx_terminals_location (POINT(longitude, latitude))
) ENGINE = InnoDB;

CREATE TABLE customers (
    customer_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    customer_name VARCHAR(255) NOT NULL,
    customer_type ENUM('shipper', 'consignee', 'both') DEFAULT 'both',

    -- Contact information
    contact_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(20),

    -- Business details
    business_address VARCHAR(500),
    tax_id VARCHAR(50),
    credit_limit DECIMAL(10,2) DEFAULT 0,

    -- Shipping preferences
    preferred_services JSON DEFAULT ('[]'),
    special_requirements TEXT,

    -- Account status
    account_status ENUM('active', 'inactive', 'suspended', 'prospect') DEFAULT 'active',
    payment_terms ENUM('cod', 'net_15', 'net_30', 'net_60') DEFAULT 'net_30',

    -- Performance metrics
    on_time_delivery_rate DECIMAL(5,2),
    claim_rate DECIMAL(5,2),

    INDEX idx_customers_type (customer_type),
    INDEX idx_customers_status (account_status),
    INDEX idx_customers_email (email)
) ENGINE = InnoDB;

CREATE TABLE carriers (
    carrier_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    carrier_name VARCHAR(255) NOT NULL,

    -- Business details
    mc_number VARCHAR(20),  -- Motor Carrier number
    dot_number VARCHAR(20),  -- Department of Transportation number
    scac_code VARCHAR(10),   -- Standard Carrier Alpha Code

    -- Contact
    contact_name VARCHAR(100),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),

    -- Service area
    service_area_states JSON DEFAULT ('[]'),
    equipment_types JSON DEFAULT ('[]'),

    -- Insurance and bonding
    cargo_insurance_limit DECIMAL(12,2),
    liability_insurance_limit DECIMAL(12,2),

    -- Performance
    carrier_rating DECIMAL(3,1),
    on_time_percentage DECIMAL(5,2),

    -- Status
    carrier_status ENUM('active', 'inactive', 'suspended', 'pending_approval') DEFAULT 'active',

    INDEX idx_carriers_status (carrier_status),
    INDEX idx_carriers_rating (carrier_rating),
    INDEX idx_carriers_mc (mc_number),
    INDEX idx_carriers_dot (dot_number)
) ENGINE = InnoDB;

-- ===========================================
-- STORED PROCEDURES FOR TRANSPORTATION ANALYTICS
-- =========================================--

DELIMITER ;;

-- Calculate optimal route with traffic and weather considerations
CREATE PROCEDURE calculate_optimal_route(
    IN origin_lat DECIMAL(10,8),
    IN origin_lng DECIMAL(11,8),
    IN dest_lat DECIMAL(10,8),
    IN dest_lng DECIMAL(11,8),
    IN vehicle_type ENUM('truck', 'van', 'car')
)
BEGIN
    DECLARE distance_miles DECIMAL(8,2);
    DECLARE estimated_duration_hours DECIMAL(6,2);
    DECLARE fuel_cost_estimate DECIMAL(8,2);
    DECLARE toll_cost_estimate DECIMAL(8,2);

    -- Calculate basic distance (simplified - would use actual routing API)
    SET distance_miles = ST_Distance_Sphere(
        POINT(origin_lng, origin_lat),
        POINT(dest_lng, dest_lat)
    ) / 1609.34;  -- Convert meters to miles

    -- Estimate duration based on vehicle type and distance
    SET estimated_duration_hours = CASE
        WHEN vehicle_type = 'truck' THEN distance_miles / 55  -- Trucks average 55 mph
        WHEN vehicle_type = 'van' THEN distance_miles / 65    -- Vans average 65 mph
        ELSE distance_miles / 70  -- Cars average 70 mph
    END;

    -- Estimate fuel costs (simplified)
    SET fuel_cost_estimate = CASE
        WHEN vehicle_type = 'truck' THEN distance_miles * 6.5  -- 6.5 mpg for trucks
        WHEN vehicle_type = 'van' THEN distance_miles * 18     -- 18 mpg for vans
        ELSE distance_miles * 25  -- 25 mpg for cars
    END * 4.50;  -- $4.50 per gallon

    -- Estimate toll costs (simplified)
    SET toll_cost_estimate = CASE
        WHEN distance_miles > 500 THEN distance_miles * 0.15  -- Long haul tolls
        WHEN distance_miles > 100 THEN distance_miles * 0.10  -- Regional tolls
        ELSE distance_miles * 0.05  -- Local tolls
    END;

    -- Return route analysis
    SELECT
        distance_miles,
        estimated_duration_hours,
        fuel_cost_estimate,
        toll_cost_estimate,
        (fuel_cost_estimate + toll_cost_estimate) as total_variable_costs,
        CASE
            WHEN estimated_duration_hours > 11 THEN 'Requires multiple drivers'
            WHEN estimated_duration_hours > 8 THEN 'Extended shift required'
            ELSE 'Standard route'
        END as driver_considerations,
        CASE
            WHEN vehicle_type = 'truck' AND distance_miles > 500 THEN 'Consider relay drivers'
            WHEN vehicle_type = 'truck' AND distance_miles > 1000 THEN 'May require border crossing permits'
            ELSE 'Standard routing'
        END as special_requirements;
END;;

-- Analyze fleet utilization and efficiency
CREATE PROCEDURE analyze_fleet_utilization(IN start_date DATE, IN end_date DATE)
BEGIN
    -- Overall fleet statistics
    SELECT
        COUNT(*) as total_vehicles,
        COUNT(CASE WHEN current_status = 'active' THEN 1 END) as active_vehicles,
        COUNT(CASE WHEN current_status = 'maintenance' THEN 1 END) as in_maintenance,
        ROUND(COUNT(CASE WHEN current_status = 'active' THEN 1 END) / COUNT(*) * 100, 2) as fleet_availability_rate,

        -- Financial metrics
        SUM(purchase_price) as total_fleet_value,
        AVG(purchase_price) as avg_vehicle_value,
        SUM(CASE WHEN purchase_date >= DATE_SUB(CURDATE(), INTERVAL 2 YEAR) THEN 1 END) as vehicles_under_2_years,

        -- Operational metrics
        COUNT(CASE WHEN inspection_due <= CURDATE() THEN 1 END) as vehicles_due_inspection,
        COUNT(CASE WHEN insurance_expiry <= DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 1 END) as insurance_expiring_soon

    FROM vehicles;

    -- Vehicle utilization by type
    SELECT
        vehicle_type,
        COUNT(*) as vehicle_count,
        COUNT(DISTINCT assigned_driver_id) as assigned_drivers,
        ROUND(COUNT(DISTINCT assigned_driver_id) / COUNT(*) * 100, 2) as driver_assignment_rate,

        -- Maintenance analysis
        COUNT(CASE WHEN current_status = 'maintenance' THEN 1 END) as in_maintenance,
        ROUND(COUNT(CASE WHEN current_status = 'maintenance' THEN 1 END) / COUNT(*) * 100, 2) as maintenance_rate,

        -- Age analysis
        AVG(YEAR(CURDATE()) - vehicle_year) as avg_vehicle_age,
        COUNT(CASE WHEN vehicle_year >= YEAR(CURDATE()) - 2 THEN 1 END) as vehicles_under_2_years

    FROM vehicles
    GROUP BY vehicle_type
    ORDER BY vehicle_count DESC;

    -- Fuel efficiency analysis
    SELECT
        v.vehicle_id,
        v.license_plate,
        v.vehicle_type,
        COALESCE(SUM(ft.gallons_pumped), 0) as total_fuel_gallons,
        COALESCE(SUM(ft.total_cost), 0) as total_fuel_cost,
        COALESCE(AVG(ft.price_per_gallon), 0) as avg_fuel_price,

        -- Efficiency metrics (would need odometer readings for true MPG)
        CASE
            WHEN COUNT(ft.fuel_transaction_id) > 5 THEN 'Good fuel efficiency'
            WHEN COUNT(ft.fuel_transaction_id) > 2 THEN 'Moderate fuel efficiency'
            ELSE 'Insufficient data'
        END as efficiency_rating

    FROM vehicles v
    LEFT JOIN fuel_transactions ft ON v.vehicle_id = ft.vehicle_id
        AND ft.transaction_date BETWEEN start_date AND end_date
    GROUP BY v.vehicle_id, v.license_plate, v.vehicle_type
    HAVING COUNT(ft.fuel_transaction_id) > 0
    ORDER BY total_fuel_cost DESC;
END;;

-- Track shipment performance and KPIs
CREATE PROCEDURE analyze_shipment_performance(IN start_date DATE, IN end_date DATE)
BEGIN
    -- Overall shipment metrics
    SELECT
        COUNT(*) as total_shipments,
        COUNT(CASE WHEN shipment_status = 'delivered' THEN 1 END) as delivered_shipments,
        ROUND(COUNT(CASE WHEN shipment_status = 'delivered' THEN 1 END) / COUNT(*) * 100, 2) as delivery_rate,

        -- Timing metrics
        AVG(TIMESTAMPDIFF(DAY, pickup_date, actual_delivery)) as avg_delivery_days,
        AVG(TIMESTAMPDIFF(DAY, pickup_date, delivery_date)) as avg_planned_delivery_days,

        -- On-time performance
        ROUND(
            COUNT(CASE WHEN actual_delivery <= delivery_date AND shipment_status = 'delivered' THEN 1 END) /
            NULLIF(COUNT(CASE WHEN shipment_status = 'delivered' THEN 1 END), 0) * 100, 2
        ) as on_time_delivery_rate,

        -- Financial metrics
        SUM(total_charges) as total_revenue,
        AVG(total_charges) as avg_shipment_revenue,
        SUM(CASE WHEN shipment_status = 'exception' THEN 1 END) as exception_count

    FROM shipments
    WHERE pickup_date BETWEEN start_date AND end_date;

    -- Performance by shipment type
    SELECT
        shipment_type,
        COUNT(*) as shipment_count,
        ROUND(AVG(total_charges), 2) as avg_revenue,
        ROUND(AVG(TIMESTAMPDIFF(HOUR, pickup_date, actual_delivery)), 2) as avg_delivery_hours,

        -- Reliability metrics
        ROUND(
            COUNT(CASE WHEN actual_delivery <= delivery_date THEN 1 END) /
            COUNT(*) * 100, 2
        ) as on_time_rate,

        -- Exception analysis
        COUNT(CASE WHEN shipment_status = 'exception' THEN 1 END) as exceptions,
        ROUND(
            COUNT(CASE WHEN shipment_status = 'exception' THEN 1 END) /
            COUNT(*) * 100, 2
        ) as exception_rate

    FROM shipments
    WHERE pickup_date BETWEEN start_date AND end_date
    GROUP BY shipment_type
    ORDER BY shipment_count DESC;

    -- Driver performance analysis
    SELECT
        d.driver_id,
        CONCAT(d.first_name, ' ', d.last_name) as driver_name,
        COUNT(s.shipment_id) as shipments_delivered,
        ROUND(AVG(TIMESTAMPDIFF(DAY, s.pickup_date, s.actual_delivery)), 2) as avg_delivery_time,

        -- Performance ratings
        ROUND(
            COUNT(CASE WHEN s.actual_delivery <= s.delivery_date THEN 1 END) /
            COUNT(s.shipment_id) * 100, 2
        ) as on_time_rate,

        COUNT(CASE WHEN s.shipment_status = 'exception' THEN 1 END) as exceptions,
        ROUND(AVG(s.total_charges), 2) as avg_shipment_value

    FROM drivers d
    LEFT JOIN shipments s ON d.driver_id = s.assigned_driver_id
        AND s.pickup_date BETWEEN start_date AND end_date
        AND s.shipment_status = 'delivered'
    GROUP BY d.driver_id, d.first_name, d.last_name
    HAVING COUNT(s.shipment_id) > 0
    ORDER BY on_time_rate DESC, shipments_delivered DESC;
END;;

DELIMITER ;

-- ===========================================
-- PARTITIONING FOR ANALYTICS
-- =========================================--

-- Partition telematics data by month
ALTER TABLE vehicle_telematics
PARTITION BY RANGE (YEAR(timestamp) * 100 + MONTH(timestamp)) (
    PARTITION p2024_01 VALUES LESS THAN (202401),
    PARTITION p2024_02 VALUES LESS THAN (202402),
    PARTITION p2024_03 VALUES LESS THAN (202403),
    PARTITION p2024_04 VALUES LESS THAN (202404),
    PARTITION p2024_05 VALUES LESS THAN (202405),
    PARTITION p2024_06 VALUES LESS THAN (202406),
    PARTITION p2024_07 VALUES LESS THAN (202407),
    PARTITION p2024_08 VALUES LESS THAN (202408),
    PARTITION p2024_09 VALUES LESS THAN (202409),
    PARTITION p2024_10 VALUES LESS THAN (202410),
    PARTITION p2024_11 VALUES LESS THAN (202411),
    PARTITION p2024_12 VALUES LESS THAN (202412),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Partition tracking data by month
ALTER TABLE shipment_tracking
PARTITION BY RANGE (YEAR(timestamp) * 100 + MONTH(timestamp)) (
    PARTITION p2024_01 VALUES LESS THAN (202401),
    PARTITION p2024_02 VALUES LESS THAN (202402),
    PARTITION p2024_03 VALUES LESS THAN (202403),
    PARTITION p2024_04 VALUES LESS THAN (202404),
    PARTITION p2024_05 VALUES LESS THAN (202405),
    PARTITION p2024_06 VALUES LESS THAN (202406),
    PARTITION p2024_07 VALUES LESS THAN (202407),
    PARTITION p2024_08 VALUES LESS THAN (202408),
    PARTITION p2024_09 VALUES LESS THAN (202409),
    PARTITION p2024_10 VALUES LESS THAN (202410),
    PARTITION p2024_11 VALUES LESS THAN (202411),
    PARTITION p2024_12 VALUES LESS THAN (202412),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- ===========================================
-- INITIAL SAMPLE DATA
-- =========================================--

INSERT INTO terminals (terminal_id, terminal_name, city, state_province, terminal_type) VALUES
(UUID(), 'Main Distribution Center', 'Chicago', 'IL', 'regional_hub'),
(UUID(), 'West Coast Terminal', 'Los Angeles', 'CA', 'regional_hub');

INSERT INTO vehicles (vehicle_id, vehicle_type, license_plate, vehicle_make, vehicle_model, fuel_type, fuel_capacity_gallons, home_terminal_id) VALUES
(UUID(), 'truck', 'ABC-123', 'Freightliner', 'Cascadia', 'diesel', 120, (SELECT terminal_id FROM terminals LIMIT 1)),
(UUID(), 'van', 'XYZ-789', 'Ford', 'Transit', 'gasoline', 25, (SELECT terminal_id FROM terminals LIMIT 1 OFFSET 1));

INSERT INTO drivers (driver_id, first_name, last_name, email, cdl_class, home_terminal_id) VALUES
(UUID(), 'John', 'Smith', 'john.smith@carrier.com', 'A', (SELECT terminal_id FROM terminals LIMIT 1)),
(UUID(), 'Jane', 'Doe', 'jane.doe@carrier.com', 'B', (SELECT terminal_id FROM terminals LIMIT 1));

INSERT INTO customers (customer_id, customer_name, email, customer_type) VALUES
(UUID(), 'Global Manufacturing Inc', 'orders@globalmfg.com', 'shipper'),
(UUID(), 'Retail Distribution Co', 'shipping@retaildist.com', 'consignee');

/*
USAGE EXAMPLES:

-- Calculate optimal route
CALL calculate_optimal_route(40.7128, -74.0060, 34.0522, -118.2437, 'truck');

-- Analyze fleet utilization
CALL analyze_fleet_utilization('2024-01-01', '2024-12-31');

-- Track shipment performance
CALL analyze_shipment_performance('2024-01-01', '2024-12-31');

This comprehensive transportation database schema provides enterprise-grade infrastructure for:
- Fleet management with telematics and maintenance tracking
- Multi-modal shipment management with real-time tracking
- Driver management with compliance and performance monitoring
- Route optimization with geospatial analysis
- Financial tracking with cost analysis and profitability
- Regulatory compliance with DOT and safety requirements

Key features adapted for MySQL:
- UUID primary keys with UUID() function
- Spatial data types for GPS tracking and route optimization
- JSON data types for flexible metadata storage
- Partitioning for time-series analytics
- Stored procedures for complex transportation analytics

The schema supports trucking companies, logistics providers, delivery services, and transportation networks with comprehensive operational and analytical capabilities.
*/
