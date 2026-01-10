# Domain-Specific Denormalization Patterns

Advanced denormalization strategies, performance optimizations, and real-world techniques used by product engineers at Uber, Netflix, Spotify, Medium, Stripe, and other billion-dollar revenue platforms.

## 🚗 Ride-Hailing & Transportation Denormalization

### The "Real-Time Driver Matching" Pattern
```sql
-- Denormalized driver availability for real-time matching
CREATE TABLE driver_availability_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    driver_id BIGINT NOT NULL,
    driver_name VARCHAR(100) NOT NULL,
    driver_rating DECIMAL(3,2) DEFAULT 0.0,
    driver_status ENUM('online', 'offline', 'busy', 'on_break') DEFAULT 'offline',
    current_location POINT NOT NULL,
    current_lat DECIMAL(10,8) NOT NULL,
    current_lng DECIMAL(10,8) NOT NULL,
    vehicle_type ENUM('economy', 'premium', 'luxury', 'xl', 'bike') NOT NULL,
    vehicle_model VARCHAR(100),
    vehicle_color VARCHAR(50),
    license_plate VARCHAR(20),
    is_available BOOLEAN DEFAULT TRUE,
    current_load INT DEFAULT 0,
    max_load INT DEFAULT 1,
    last_location_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_status_change TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    total_rides INT DEFAULT 0,
    total_earnings DECIMAL(10,2) DEFAULT 0.0,
    avg_rating DECIMAL(3,2) DEFAULT 0.0,
    completion_rate DECIMAL(5,2) DEFAULT 100.0,
    response_time_avg_seconds INT DEFAULT 0,
    -- Denormalized preferences
    preferred_areas JSON,  -- Areas driver prefers to work
    accepted_payment_methods JSON,  -- Cash, card, digital wallets
    languages_spoken JSON,  -- Languages driver can speak
    special_capabilities JSON,  -- Wheelchair accessible, pet friendly, etc.
    
    SPATIAL INDEX idx_driver_location (current_location),
    INDEX idx_driver_status_availability (driver_status, is_available, vehicle_type),
    INDEX idx_driver_rating (driver_rating DESC),
    INDEX idx_last_location_update (last_location_update),
    INDEX idx_driver_earnings (total_earnings DESC)
);

-- Denormalized ride requests for quick matching
CREATE TABLE ride_requests_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(100) UNIQUE NOT NULL,
    customer_id BIGINT NOT NULL,
    customer_name VARCHAR(100) NOT NULL,
    customer_rating DECIMAL(3,2) DEFAULT 0.0,
    pickup_location POINT NOT NULL,
    pickup_lat DECIMAL(10,8) NOT NULL,
    pickup_lng DECIMAL(10,8) NOT NULL,
    dropoff_location POINT NOT NULL,
    dropoff_lat DECIMAL(10,8) NOT NULL,
    dropoff_lng DECIMAL(10,8) NOT NULL,
    estimated_distance_km DECIMAL(8,2),
    estimated_duration_minutes INT,
    estimated_fare DECIMAL(8,2),
    vehicle_type_preference ENUM('economy', 'premium', 'luxury', 'xl', 'bike'),
    request_status ENUM('pending', 'matched', 'picked_up', 'completed', 'cancelled') DEFAULT 'pending',
    payment_method ENUM('cash', 'card', 'digital_wallet') NOT NULL,
    surge_multiplier DECIMAL(3,2) DEFAULT 1.0,
    -- Denormalized customer preferences
    customer_preferences JSON,  -- Preferred drivers, routes, etc.
    special_requirements JSON,  -- Wheelchair, pet, child seat, etc.
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    matched_at TIMESTAMP NULL,
    picked_up_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    
    SPATIAL INDEX idx_pickup_location (pickup_location),
    SPATIAL INDEX idx_dropoff_location (dropoff_location),
    INDEX idx_request_status_vehicle (request_status, vehicle_type_preference),
    INDEX idx_created_at (created_at),
    INDEX idx_estimated_fare (estimated_fare DESC)
);
```

### The "Surge Pricing & Demand Prediction" Pattern
```sql
-- Denormalized surge pricing data
CREATE TABLE surge_pricing_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    area_id BIGINT NOT NULL,
    area_name VARCHAR(100) NOT NULL,
    area_center POINT NOT NULL,
    area_center_lat DECIMAL(10,8) NOT NULL,
    area_center_lng DECIMAL(10,8) NOT NULL,
    time_slot TIMESTAMP NOT NULL,
    hour_of_day INT NOT NULL,
    day_of_week INT NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    is_holiday BOOLEAN DEFAULT FALSE,
    weather_condition VARCHAR(50),
    temperature_celsius DECIMAL(4,1),
    -- Demand metrics
    active_requests INT DEFAULT 0,
    available_drivers INT DEFAULT 0,
    demand_supply_ratio DECIMAL(5,2) DEFAULT 0.0,
    surge_multiplier DECIMAL(3,2) DEFAULT 1.0,
    base_fare DECIMAL(8,2) NOT NULL,
    surge_fare DECIMAL(8,2) NOT NULL,
    -- Historical data
    avg_surge_last_week DECIMAL(3,2) DEFAULT 1.0,
    avg_surge_last_month DECIMAL(3,2) DEFAULT 1.0,
    peak_hour_multiplier DECIMAL(3,2) DEFAULT 1.0,
    -- Events and external factors
    nearby_events JSON,  -- Concerts, sports, etc.
    traffic_conditions VARCHAR(50),
    public_transport_status VARCHAR(50),
    
    UNIQUE KEY uk_area_time (area_id, time_slot),
    SPATIAL INDEX idx_area_center (area_center),
    INDEX idx_time_slot (time_slot),
    INDEX idx_surge_multiplier (surge_multiplier DESC),
    INDEX idx_demand_supply_ratio (demand_supply_ratio DESC)
);
```

## 🎬 Streaming & Video Platform Denormalization

### The "Content Discovery & Recommendations" Pattern
```sql
-- Denormalized content for fast discovery
CREATE TABLE content_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    content_id VARCHAR(100) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    content_type ENUM('movie', 'tv_show', 'documentary', 'standup', 'reality') NOT NULL,
    genre_tags JSON NOT NULL,  -- ['action', 'comedy', 'drama']
    cast_members JSON,  -- ['actor1', 'actor2', 'director']
    director VARCHAR(100),
    release_year INT,
    duration_minutes INT,
    rating ENUM('G', 'PG', 'PG-13', 'R', 'NC-17') NOT NULL,
    language VARCHAR(50) DEFAULT 'English',
    subtitles_available JSON,  -- ['English', 'Spanish', 'French']
    -- Quality and format
    max_quality ENUM('4K', '1080p', '720p', '480p') DEFAULT '1080p',
    hdr_available BOOLEAN DEFAULT FALSE,
    dolby_atmos BOOLEAN DEFAULT FALSE,
    -- Engagement metrics
    total_views BIGINT DEFAULT 0,
    avg_rating DECIMAL(3,2) DEFAULT 0.0,
    rating_count INT DEFAULT 0,
    watch_time_minutes BIGINT DEFAULT 0,
    completion_rate DECIMAL(5,2) DEFAULT 0.0,
    -- Trending metrics
    views_last_24h INT DEFAULT 0,
    views_last_7d INT DEFAULT 0,
    views_last_30d INT DEFAULT 0,
    trending_score DECIMAL(10,2) DEFAULT 0.0,
    -- Content features
    is_original BOOLEAN DEFAULT FALSE,
    is_featured BOOLEAN DEFAULT FALSE,
    is_trending BOOLEAN DEFAULT FALSE,
    is_new_release BOOLEAN DEFAULT FALSE,
    -- Metadata
    thumbnail_url VARCHAR(500),
    trailer_url VARCHAR(500),
    poster_url VARCHAR(500),
    content_tags JSON,  -- Additional tags for recommendations
    similar_content_ids JSON,  -- Pre-computed similar content
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FULLTEXT INDEX idx_title_description (title, description),
    INDEX idx_content_type_genre (content_type, genre_tags),
    INDEX idx_release_year (release_year DESC),
    INDEX idx_trending_score (trending_score DESC),
    INDEX idx_total_views (total_views DESC),
    INDEX idx_avg_rating (avg_rating DESC),
    INDEX idx_is_featured (is_featured, trending_score DESC)
);

-- Denormalized user viewing history
CREATE TABLE user_viewing_history_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    content_id VARCHAR(100) NOT NULL,
    content_title VARCHAR(255) NOT NULL,
    content_type ENUM('movie', 'tv_show', 'documentary', 'standup', 'reality') NOT NULL,
    genre_tags JSON NOT NULL,
    watch_start_time TIMESTAMP NOT NULL,
    watch_end_time TIMESTAMP NULL,
    watch_duration_minutes INT DEFAULT 0,
    watch_percentage DECIMAL(5,2) DEFAULT 0.0,
    device_type ENUM('mobile', 'tablet', 'desktop', 'tv', 'console') NOT NULL,
    quality_watched ENUM('4K', '1080p', '720p', '480p') NOT NULL,
    user_rating INT NULL,  -- 1-5 stars
    user_review TEXT,
    -- Denormalized content metadata
    content_release_year INT,
    content_duration_minutes INT,
    content_avg_rating DECIMAL(3,2),
    content_genre_primary VARCHAR(50),
    -- User behavior
    rewatch_count INT DEFAULT 0,
    is_favorite BOOLEAN DEFAULT FALSE,
    is_in_watchlist BOOLEAN DEFAULT FALSE,
    -- Recommendation signals
    recommended_by_algorithm VARCHAR(50),
    recommendation_score DECIMAL(5,2),
    
    INDEX idx_user_content (user_id, content_id),
    INDEX idx_user_watch_time (user_id, watch_start_time DESC),
    INDEX idx_content_views (content_id, watch_start_time DESC),
    INDEX idx_genre_watch_time (content_genre_primary, watch_start_time DESC),
    INDEX idx_user_rating (user_id, user_rating DESC)
);
```

## 🎵 Music Streaming Denormalization

### The "Playlist & Music Discovery" Pattern
```sql
-- Denormalized tracks for fast playback
CREATE TABLE tracks_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    track_id VARCHAR(100) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    artist_name VARCHAR(255) NOT NULL,
    artist_id BIGINT NOT NULL,
    album_name VARCHAR(255) NOT NULL,
    album_id BIGINT NOT NULL,
    album_art_url VARCHAR(500),
    duration_seconds INT NOT NULL,
    genre_tags JSON NOT NULL,  -- ['pop', 'rock', 'electronic']
    mood_tags JSON,  -- ['energetic', 'chill', 'romantic']
    language VARCHAR(50) DEFAULT 'English',
    release_year INT,
    explicit_content BOOLEAN DEFAULT FALSE,
    -- Audio quality
    bitrate_kbps INT DEFAULT 320,
    sample_rate_hz INT DEFAULT 44100,
    audio_format ENUM('mp3', 'aac', 'flac', 'wav') DEFAULT 'aac',
    -- Engagement metrics
    total_plays BIGINT DEFAULT 0,
    total_likes INT DEFAULT 0,
    total_shares INT DEFAULT 0,
    total_downloads INT DEFAULT 0,
    avg_rating DECIMAL(3,2) DEFAULT 0.0,
    -- Trending metrics
    plays_last_24h INT DEFAULT 0,
    plays_last_7d INT DEFAULT 0,
    plays_last_30d INT DEFAULT 0,
    trending_score DECIMAL(10,2) DEFAULT 0.0,
    -- Track features
    is_explicit BOOLEAN DEFAULT FALSE,
    is_featured BOOLEAN DEFAULT FALSE,
    is_new_release BOOLEAN DEFAULT FALSE,
    is_playlist_favorite BOOLEAN DEFAULT FALSE,
    -- Audio features (for recommendations)
    tempo_bpm INT,
    energy_level DECIMAL(3,2),  -- 0.0 to 1.0
    danceability DECIMAL(3,2),
    valence DECIMAL(3,2),  -- Positivity
    acousticness DECIMAL(3,2),
    instrumentalness DECIMAL(3,2),
    -- Similar tracks (pre-computed)
    similar_track_ids JSON,
    
    FULLTEXT INDEX idx_title_artist (title, artist_name),
    INDEX idx_artist_id (artist_id),
    INDEX idx_album_id (album_id),
    INDEX idx_genre_tags (genre_tags),
    INDEX idx_trending_score (trending_score DESC),
    INDEX idx_total_plays (total_plays DESC),
    INDEX idx_release_year (release_year DESC),
    INDEX idx_energy_tempo (energy_level DESC, tempo_bpm)
);

-- Denormalized playlists
CREATE TABLE playlists_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    playlist_id VARCHAR(100) UNIQUE NOT NULL,
    playlist_name VARCHAR(255) NOT NULL,
    creator_id BIGINT NOT NULL,
    creator_name VARCHAR(255) NOT NULL,
    is_public BOOLEAN DEFAULT TRUE,
    is_collaborative BOOLEAN DEFAULT FALSE,
    description TEXT,
    cover_image_url VARCHAR(500),
    -- Playlist metrics
    total_tracks INT DEFAULT 0,
    total_duration_minutes INT DEFAULT 0,
    total_followers INT DEFAULT 0,
    total_plays BIGINT DEFAULT 0,
    avg_rating DECIMAL(3,2) DEFAULT 0.0,
    -- Genre and mood aggregation
    primary_genre VARCHAR(50),
    genre_distribution JSON,  -- {'pop': 0.3, 'rock': 0.7}
    mood_distribution JSON,  -- {'energetic': 0.4, 'chill': 0.6}
    -- Engagement metrics
    plays_last_24h INT DEFAULT 0,
    plays_last_7d INT DEFAULT 0,
    plays_last_30d INT DEFAULT 0,
    new_followers_last_7d INT DEFAULT 0,
    -- Playlist features
    is_featured BOOLEAN DEFAULT FALSE,
    is_trending BOOLEAN DEFAULT FALSE,
    is_editorial BOOLEAN DEFAULT FALSE,
    -- Track list (denormalized for fast access)
    track_list JSON,  -- Array of track objects with basic info
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_creator_id (creator_id),
    INDEX idx_is_public (is_public, total_followers DESC),
    INDEX idx_primary_genre (primary_genre, total_followers DESC),
    INDEX idx_total_followers (total_followers DESC),
    INDEX idx_is_featured (is_featured, total_followers DESC),
    FULLTEXT INDEX idx_playlist_name_description (playlist_name, description)
);
```

## 📝 Blogging & Content Platform Denormalization

### The "Content Publishing & Discovery" Pattern
```sql
-- Denormalized articles for fast reading
CREATE TABLE articles_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    article_id VARCHAR(100) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    subtitle VARCHAR(500),
    content LONGTEXT NOT NULL,
    excerpt TEXT,
    author_id BIGINT NOT NULL,
    author_name VARCHAR(255) NOT NULL,
    author_avatar_url VARCHAR(500),
    author_followers_count INT DEFAULT 0,
    author_verified BOOLEAN DEFAULT FALSE,
    -- Content metadata
    publication_name VARCHAR(255),
    publication_id BIGINT,
    category_tags JSON NOT NULL,  -- ['technology', 'programming', 'ai']
    topic_tags JSON,  -- ['machine-learning', 'python', 'tutorial']
    reading_time_minutes INT DEFAULT 0,
    word_count INT DEFAULT 0,
    language VARCHAR(10) DEFAULT 'en',
    -- Content features
    has_images BOOLEAN DEFAULT FALSE,
    has_videos BOOLEAN DEFAULT FALSE,
    has_code_blocks BOOLEAN DEFAULT FALSE,
    is_premium BOOLEAN DEFAULT FALSE,
    is_featured BOOLEAN DEFAULT FALSE,
    is_editor_pick BOOLEAN DEFAULT FALSE,
    -- Engagement metrics
    total_views BIGINT DEFAULT 0,
    total_likes INT DEFAULT 0,
    total_comments INT DEFAULT 0,
    total_shares INT DEFAULT 0,
    total_bookmarks INT DEFAULT 0,
    avg_reading_time_actual_minutes DECIMAL(5,2) DEFAULT 0.0,
    completion_rate DECIMAL(5,2) DEFAULT 0.0,
    -- Trending metrics
    views_last_24h INT DEFAULT 0,
    views_last_7d INT DEFAULT 0,
    views_last_30d INT DEFAULT 0,
    trending_score DECIMAL(10,2) DEFAULT 0.0,
    -- SEO and discovery
    seo_title VARCHAR(255),
    seo_description TEXT,
    canonical_url VARCHAR(500),
    -- Content status
    status ENUM('draft', 'published', 'archived', 'deleted') DEFAULT 'draft',
    published_at TIMESTAMP NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FULLTEXT INDEX idx_title_content (title, content),
    INDEX idx_author_id (author_id),
    INDEX idx_publication_id (publication_id),
    INDEX idx_category_tags (category_tags),
    INDEX idx_trending_score (trending_score DESC),
    INDEX idx_total_views (total_views DESC),
    INDEX idx_published_at (published_at DESC),
    INDEX idx_is_featured (is_featured, trending_score DESC),
    INDEX idx_reading_time (reading_time_minutes)
);

-- Denormalized user reading history
CREATE TABLE user_reading_history_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    article_id VARCHAR(100) NOT NULL,
    article_title VARCHAR(255) NOT NULL,
    author_name VARCHAR(255) NOT NULL,
    category_tags JSON NOT NULL,
    reading_start_time TIMESTAMP NOT NULL,
    reading_end_time TIMESTAMP NULL,
    reading_duration_minutes INT DEFAULT 0,
    reading_percentage DECIMAL(5,2) DEFAULT 0.0,
    device_type ENUM('mobile', 'tablet', 'desktop') NOT NULL,
    -- User actions
    user_liked BOOLEAN DEFAULT FALSE,
    user_bookmarked BOOLEAN DEFAULT FALSE,
    user_shared BOOLEAN DEFAULT FALSE,
    user_commented BOOLEAN DEFAULT FALSE,
    -- Denormalized article metadata
    article_reading_time_minutes INT,
    article_category_primary VARCHAR(50),
    article_trending_score DECIMAL(10,2),
    -- Recommendation signals
    recommended_by_algorithm VARCHAR(50),
    recommendation_score DECIMAL(5,2),
    
    INDEX idx_user_article (user_id, article_id),
    INDEX idx_user_reading_time (user_id, reading_start_time DESC),
    INDEX idx_article_views (article_id, reading_start_time DESC),
    INDEX idx_category_reading (article_category_primary, reading_start_time DESC)
);
```

## 💳 Fintech & Payment Platform Denormalization

### The "Transaction Processing & Analytics" Pattern
```sql
-- Denormalized transactions for fast processing
CREATE TABLE transactions_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(100) UNIQUE NOT NULL,
    merchant_id BIGINT NOT NULL,
    merchant_name VARCHAR(255) NOT NULL,
    merchant_category VARCHAR(100),
    merchant_location_country VARCHAR(50),
    merchant_location_city VARCHAR(100),
    customer_id BIGINT NOT NULL,
    customer_name VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255),
    customer_phone VARCHAR(20),
    -- Transaction details
    amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    transaction_type ENUM('purchase', 'refund', 'chargeback', 'dispute') DEFAULT 'purchase',
    payment_method ENUM('credit_card', 'debit_card', 'bank_transfer', 'digital_wallet', 'crypto') NOT NULL,
    card_network ENUM('visa', 'mastercard', 'amex', 'discover') NULL,
    card_last_4 VARCHAR(4),
    -- Risk and fraud
    risk_score DECIMAL(5,2) DEFAULT 0.0,
    fraud_score DECIMAL(5,2) DEFAULT 0.0,
    is_flagged BOOLEAN DEFAULT FALSE,
    flag_reason VARCHAR(255),
    -- Transaction status
    status ENUM('pending', 'processing', 'completed', 'failed', 'cancelled', 'refunded') DEFAULT 'pending',
    gateway_response JSON,
    -- Fees and charges
    processing_fee DECIMAL(10,2) DEFAULT 0.0,
    interchange_fee DECIMAL(10,2) DEFAULT 0.0,
    network_fee DECIMAL(10,2) DEFAULT 0.0,
    total_fees DECIMAL(10,2) DEFAULT 0.0,
    -- Denormalized customer data
    customer_risk_level ENUM('low', 'medium', 'high') DEFAULT 'low',
    customer_total_transactions INT DEFAULT 0,
    customer_total_spent DECIMAL(15,2) DEFAULT 0.0,
    customer_avg_transaction_amount DECIMAL(10,2) DEFAULT 0.0,
    -- Denormalized merchant data
    merchant_risk_level ENUM('low', 'medium', 'high') DEFAULT 'low',
    merchant_total_transactions INT DEFAULT 0,
    merchant_total_volume DECIMAL(15,2) DEFAULT 0.0,
    merchant_avg_transaction_amount DECIMAL(10,2) DEFAULT 0.0,
    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    
    INDEX idx_transaction_id (transaction_id),
    INDEX idx_merchant_id (merchant_id),
    INDEX idx_customer_id (customer_id),
    INDEX idx_status_created (status, created_at),
    INDEX idx_amount (amount DESC),
    INDEX idx_risk_score (risk_score DESC),
    INDEX idx_created_at (created_at DESC),
    INDEX idx_payment_method (payment_method, created_at DESC),
    INDEX idx_merchant_category (merchant_category, created_at DESC)
);

-- Denormalized fraud detection data
CREATE TABLE fraud_detection_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(100) NOT NULL,
    customer_id BIGINT NOT NULL,
    customer_email VARCHAR(255),
    customer_phone VARCHAR(20),
    customer_ip_address VARCHAR(45),
    customer_device_id VARCHAR(100),
    customer_location_country VARCHAR(50),
    customer_location_city VARCHAR(100),
    customer_location_lat DECIMAL(10,8),
    customer_location_lng DECIMAL(10,8),
    -- Transaction context
    amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    merchant_id BIGINT NOT NULL,
    merchant_category VARCHAR(100),
    merchant_country VARCHAR(50),
    -- Behavioral patterns
    customer_transaction_count_24h INT DEFAULT 0,
    customer_transaction_count_7d INT DEFAULT 0,
    customer_transaction_count_30d INT DEFAULT 0,
    customer_total_spent_24h DECIMAL(15,2) DEFAULT 0.0,
    customer_total_spent_7d DECIMAL(15,2) DEFAULT 0.0,
    customer_total_spent_30d DECIMAL(15,2) DEFAULT 0.0,
    customer_avg_transaction_amount DECIMAL(10,2) DEFAULT 0.0,
    -- Device and location patterns
    device_transaction_count_24h INT DEFAULT 0,
    device_transaction_count_7d INT DEFAULT 0,
    ip_transaction_count_24h INT DEFAULT 0,
    ip_transaction_count_7d INT DEFAULT 0,
    -- Velocity checks
    velocity_score DECIMAL(5,2) DEFAULT 0.0,
    location_velocity_score DECIMAL(5,2) DEFAULT 0.0,
    amount_velocity_score DECIMAL(5,2) DEFAULT 0.0,
    -- Risk indicators
    is_new_customer BOOLEAN DEFAULT FALSE,
    is_new_device BOOLEAN DEFAULT FALSE,
    is_new_location BOOLEAN DEFAULT FALSE,
    is_new_merchant BOOLEAN DEFAULT FALSE,
    is_high_value_transaction BOOLEAN DEFAULT FALSE,
    is_international_transaction BOOLEAN DEFAULT FALSE,
    -- Fraud scores
    overall_fraud_score DECIMAL(5,2) DEFAULT 0.0,
    behavioral_fraud_score DECIMAL(5,2) DEFAULT 0.0,
    device_fraud_score DECIMAL(5,2) DEFAULT 0.0,
    location_fraud_score DECIMAL(5,2) DEFAULT 0.0,
    -- Decision
    fraud_decision ENUM('approve', 'review', 'decline') DEFAULT 'approve',
    decision_reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_transaction_id (transaction_id),
    INDEX idx_customer_id (customer_id),
    INDEX idx_overall_fraud_score (overall_fraud_score DESC),
    INDEX idx_fraud_decision (fraud_decision, created_at),
    INDEX idx_customer_device (customer_id, customer_device_id),
    INDEX idx_customer_ip (customer_id, customer_ip_address),
    INDEX idx_created_at (created_at DESC)
);
```

## 🏭 Warehousing & Logistics Denormalization

### The "Inventory Management & Fulfillment" Pattern
```sql
-- Denormalized inventory for fast operations
CREATE TABLE inventory_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    product_sku VARCHAR(100) UNIQUE NOT NULL,
    product_category VARCHAR(100) NOT NULL,
    product_brand VARCHAR(100),
    warehouse_id BIGINT NOT NULL,
    warehouse_name VARCHAR(255) NOT NULL,
    warehouse_location_country VARCHAR(50) NOT NULL,
    warehouse_location_city VARCHAR(100) NOT NULL,
    warehouse_location_lat DECIMAL(10,8),
    warehouse_location_lng DECIMAL(10,8),
    -- Inventory levels
    available_quantity INT NOT NULL DEFAULT 0,
    reserved_quantity INT NOT NULL DEFAULT 0,
    in_transit_quantity INT NOT NULL DEFAULT 0,
    damaged_quantity INT NOT NULL DEFAULT 0,
    total_quantity INT GENERATED ALWAYS AS (available_quantity + reserved_quantity + in_transit_quantity + damaged_quantity) STORED,
    -- Product specifications
    product_dimensions JSON,  -- {'length': 10, 'width': 5, 'height': 2, 'weight': 0.5}
    product_weight_kg DECIMAL(8,3),
    product_volume_cubic_m DECIMAL(8,3),
    storage_requirements JSON,  -- ['refrigerated', 'fragile', 'hazardous']
    -- Demand forecasting
    avg_daily_demand DECIMAL(8,2) DEFAULT 0.0,
    demand_volatility DECIMAL(5,2) DEFAULT 0.0,
    reorder_point INT DEFAULT 0,
    reorder_quantity INT DEFAULT 0,
    lead_time_days INT DEFAULT 0,
    -- Performance metrics
    stockout_count_30d INT DEFAULT 0,
    stockout_days_30d INT DEFAULT 0,
    fill_rate_30d DECIMAL(5,2) DEFAULT 100.0,
    turnover_rate_30d DECIMAL(5,2) DEFAULT 0.0,
    -- Cost and pricing
    unit_cost DECIMAL(10,2) DEFAULT 0.0,
    unit_price DECIMAL(10,2) DEFAULT 0.0,
    total_inventory_value DECIMAL(15,2) GENERATED ALWAYS AS (available_quantity * unit_cost) STORED,
    -- Location optimization
    storage_zone VARCHAR(50),
    storage_rack VARCHAR(50),
    storage_level VARCHAR(50),
    storage_position VARCHAR(50),
    -- Supplier information
    primary_supplier_id BIGINT,
    primary_supplier_name VARCHAR(255),
    supplier_lead_time_days INT DEFAULT 0,
    -- Last updates
    last_restocked_at TIMESTAMP NULL,
    last_audit_at TIMESTAMP NULL,
    last_movement_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_product_sku (product_sku),
    INDEX idx_warehouse_product (warehouse_id, product_id),
    INDEX idx_available_quantity (available_quantity),
    INDEX idx_reorder_point (reorder_point),
    INDEX idx_product_category (product_category),
    INDEX idx_warehouse_location (warehouse_location_country, warehouse_location_city),
    INDEX idx_last_movement (last_movement_at DESC),
    SPATIAL INDEX idx_warehouse_location_spatial (warehouse_location_lat, warehouse_location_lng)
);

-- Denormalized order fulfillment
CREATE TABLE order_fulfillment_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(100) UNIQUE NOT NULL,
    customer_id BIGINT NOT NULL,
    customer_name VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255),
    customer_phone VARCHAR(20),
    customer_address JSON NOT NULL,
    -- Order details
    order_total DECIMAL(15,2) NOT NULL,
    shipping_cost DECIMAL(8,2) DEFAULT 0.0,
    tax_amount DECIMAL(8,2) DEFAULT 0.0,
    order_status ENUM('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled') DEFAULT 'pending',
    payment_status ENUM('pending', 'paid', 'failed', 'refunded') DEFAULT 'pending',
    -- Shipping details
    shipping_method ENUM('standard', 'express', 'overnight', 'same_day') DEFAULT 'standard',
    shipping_carrier VARCHAR(50),
    tracking_number VARCHAR(100),
    estimated_delivery_date DATE,
    actual_delivery_date DATE,
    -- Fulfillment details
    fulfillment_warehouse_id BIGINT,
    fulfillment_warehouse_name VARCHAR(255),
    fulfillment_warehouse_location VARCHAR(255),
    picker_id BIGINT,
    picker_name VARCHAR(255),
    packer_id BIGINT,
    packer_name VARCHAR(255),
    -- Performance metrics
    order_processing_time_minutes INT DEFAULT 0,
    picking_time_minutes INT DEFAULT 0,
    packing_time_minutes INT DEFAULT 0,
    shipping_time_hours INT DEFAULT 0,
    total_fulfillment_time_hours INT DEFAULT 0,
    -- Denormalized order items
    order_items JSON,  -- Array of items with product details
    total_items_count INT DEFAULT 0,
    total_weight_kg DECIMAL(8,3) DEFAULT 0.0,
    total_volume_cubic_m DECIMAL(8,3) DEFAULT 0.0,
    -- Customer satisfaction
    delivery_rating INT NULL,  -- 1-5 stars
    delivery_feedback TEXT,
    -- Timestamps
    order_created_at TIMESTAMP NOT NULL,
    order_confirmed_at TIMESTAMP NULL,
    order_processing_started_at TIMESTAMP NULL,
    order_shipped_at TIMESTAMP NULL,
    order_delivered_at TIMESTAMP NULL,
    
    INDEX idx_order_id (order_id),
    INDEX idx_customer_id (customer_id),
    INDEX idx_order_status (order_status, order_created_at),
    INDEX idx_fulfillment_warehouse (fulfillment_warehouse_id),
    INDEX idx_tracking_number (tracking_number),
    INDEX idx_order_created_at (order_created_at DESC),
    INDEX idx_estimated_delivery (estimated_delivery_date),
    INDEX idx_shipping_method (shipping_method, order_created_at DESC)
);
```

## 🎮 Gaming & Social Platform Denormalization

### The "User Engagement & Social Features" Pattern
```sql
-- Denormalized user profiles for social features
CREATE TABLE user_profiles_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNIQUE NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    avatar_url VARCHAR(500),
    cover_photo_url VARCHAR(500),
    bio TEXT,
    location VARCHAR(255),
    website_url VARCHAR(500),
    -- Social metrics
    followers_count INT DEFAULT 0,
    following_count INT DEFAULT 0,
    posts_count INT DEFAULT 0,
    likes_received_count BIGINT DEFAULT 0,
    comments_received_count BIGINT DEFAULT 0,
    shares_received_count BIGINT DEFAULT 0,
    total_engagement BIGINT GENERATED ALWAYS AS (likes_received_count + comments_received_count + shares_received_count) STORED,
    -- Activity metrics
    last_active_at TIMESTAMP NULL,
    days_since_joined INT DEFAULT 0,
    posts_last_7d INT DEFAULT 0,
    posts_last_30d INT DEFAULT 0,
    engagement_rate DECIMAL(5,2) DEFAULT 0.0,
    -- User status
    is_verified BOOLEAN DEFAULT FALSE,
    is_private BOOLEAN DEFAULT FALSE,
    is_banned BOOLEAN DEFAULT FALSE,
    account_status ENUM('active', 'suspended', 'deleted') DEFAULT 'active',
    -- Preferences and settings
    privacy_settings JSON,
    notification_settings JSON,
    theme_preference ENUM('light', 'dark', 'auto') DEFAULT 'auto',
    language_preference VARCHAR(10) DEFAULT 'en',
    -- Gaming specific (if applicable)
    gaming_stats JSON,  -- {'level': 50, 'xp': 15000, 'achievements': ['first_win', '100_games']}
    favorite_games JSON,
    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_username (username),
    INDEX idx_followers_count (followers_count DESC),
    INDEX idx_total_engagement (total_engagement DESC),
    INDEX idx_last_active (last_active_at DESC),
    INDEX idx_posts_count (posts_count DESC),
    INDEX idx_is_verified (is_verified, followers_count DESC),
    FULLTEXT INDEX idx_display_name_bio (display_name, bio)
);

-- Denormalized posts for fast social feed
CREATE TABLE posts_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    post_id VARCHAR(100) UNIQUE NOT NULL,
    author_id BIGINT NOT NULL,
    author_username VARCHAR(50) NOT NULL,
    author_display_name VARCHAR(100) NOT NULL,
    author_avatar_url VARCHAR(500),
    author_followers_count INT DEFAULT 0,
    author_is_verified BOOLEAN DEFAULT FALSE,
    -- Post content
    content TEXT,
    content_type ENUM('text', 'image', 'video', 'link', 'poll', 'game_result') DEFAULT 'text',
    media_urls JSON,  -- Array of media URLs
    hashtags JSON,  -- Array of hashtags
    mentions JSON,  -- Array of mentioned users
    -- Engagement metrics
    likes_count INT DEFAULT 0,
    comments_count INT DEFAULT 0,
    shares_count INT DEFAULT 0,
    views_count BIGINT DEFAULT 0,
    total_engagement INT GENERATED ALWAYS AS (likes_count + comments_count + shares_count) STORED,
    engagement_rate DECIMAL(5,2) DEFAULT 0.0,
    -- Trending metrics
    likes_last_1h INT DEFAULT 0,
    likes_last_24h INT DEFAULT 0,
    comments_last_1h INT DEFAULT 0,
    comments_last_24h INT DEFAULT 0,
    trending_score DECIMAL(10,2) DEFAULT 0.0,
    -- Post features
    is_featured BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_edited BOOLEAN DEFAULT FALSE,
    is_sensitive BOOLEAN DEFAULT FALSE,
    -- Location and context
    location_name VARCHAR(255),
    location_lat DECIMAL(10,8),
    location_lng DECIMAL(10,8),
    -- Gaming specific (if applicable)
    game_name VARCHAR(100),
    game_result JSON,  -- {'score': 1500, 'rank': 1, 'achievements': ['new_record']}
    -- Post status
    status ENUM('published', 'draft', 'archived', 'deleted') DEFAULT 'published',
    visibility ENUM('public', 'followers', 'private') DEFAULT 'public',
    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_author_id (author_id),
    INDEX idx_created_at (created_at DESC),
    INDEX idx_trending_score (trending_score DESC),
    INDEX idx_total_engagement (total_engagement DESC),
    INDEX idx_content_type (content_type, created_at DESC),
    INDEX idx_hashtags (hashtags),
    INDEX idx_is_featured (is_featured, trending_score DESC),
    FULLTEXT INDEX idx_content (content),
    SPATIAL INDEX idx_location (location_lat, location_lng)
);
```

These domain-specific denormalization patterns provide comprehensive strategies for optimizing performance across all major high-revenue domains, enabling fast queries, real-time analytics, and scalable operations! 🚀
```
