# Advanced Inheritance Patterns & Polymorphic Associations

Real-world inheritance patterns, polymorphic associations, and ingenious techniques used by product engineers to handle complex domain models efficiently.

## 🎪 Polymorphic Association Mastery

### The "Generic Comment System" Pattern
```sql
-- Universal comment system (comments on posts, photos, videos, products, etc.)
CREATE TABLE comments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    commentable_type VARCHAR(50) NOT NULL,  -- 'Post', 'Photo', 'Video', 'Product'
    commentable_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    content TEXT NOT NULL,
    parent_id BIGINT NULL,  -- For nested comments
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Polymorphic indexes
    INDEX idx_commentable (commentable_type, commentable_id, created_at DESC),
    INDEX idx_user_comments (user_id, created_at DESC),
    INDEX idx_nested_comments (parent_id, created_at),
    INDEX idx_commentable_user (commentable_type, commentable_id, user_id)
);

-- Optimized comment queries
-- Get all comments for a post
SELECT c.*, u.name as user_name, u.avatar_url
FROM comments c
JOIN users u ON c.user_id = u.id
WHERE c.commentable_type = 'Post' 
AND c.commentable_id = 123
ORDER BY c.created_at DESC;

-- Get user's recent comments across all types
SELECT c.*, 
       CASE c.commentable_type
           WHEN 'Post' THEN p.title
           WHEN 'Photo' THEN ph.caption
           WHEN 'Video' THEN v.title
           ELSE NULL
       END as item_title
FROM comments c
LEFT JOIN posts p ON c.commentable_type = 'Post' AND c.commentable_id = p.id
LEFT JOIN photos ph ON c.commentable_type = 'Photo' AND c.commentable_id = ph.id
LEFT JOIN videos v ON c.commentable_type = 'Video' AND c.commentable_id = v.id
WHERE c.user_id = 456
ORDER BY c.created_at DESC;
```

### The "Universal Like System" Pattern
```sql
-- Generic like system (likes on posts, comments, photos, etc.)
CREATE TABLE likes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    likeable_type VARCHAR(50) NOT NULL,
    likeable_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    reaction_type ENUM('like', 'love', 'haha', 'wow', 'sad', 'angry') DEFAULT 'like',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Unique constraint prevents duplicate likes
    UNIQUE KEY uk_like_unique (likeable_type, likeable_id, user_id),
    INDEX idx_likeable (likeable_type, likeable_id, reaction_type),
    INDEX idx_user_likes (user_id, created_at DESC),
    INDEX idx_likeable_count (likeable_type, likeable_id, reaction_type)
);

-- Optimized like queries with counts
-- Get like counts for a post
SELECT 
    reaction_type,
    COUNT(*) as count
FROM likes 
WHERE likeable_type = 'Post' 
AND likeable_id = 123
GROUP BY reaction_type;

-- Get user's liked items
SELECT l.*,
       CASE l.likeable_type
           WHEN 'Post' THEN p.title
           WHEN 'Photo' THEN ph.caption
           WHEN 'Comment' THEN c.content
           ELSE NULL
       END as item_content
FROM likes l
LEFT JOIN posts p ON l.likeable_type = 'Post' AND l.likeable_id = p.id
LEFT JOIN photos ph ON l.likeable_type = 'Photo' AND l.likeable_id = ph.id
LEFT JOIN comments c ON l.likeable_type = 'Comment' AND l.likeable_id = c.id
WHERE l.user_id = 456
ORDER BY l.created_at DESC;
```

### The "Smart Notification System" Pattern
```sql
-- Universal notification system
CREATE TABLE notifications (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    notifiable_type VARCHAR(50) NOT NULL,  -- 'User', 'Group', 'Channel'
    notifiable_id BIGINT NOT NULL,
    notification_type VARCHAR(100) NOT NULL,  -- 'like', 'comment', 'follow', 'mention'
    data JSON NOT NULL,  -- Flexible notification data
    read_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_notifiable (notifiable_type, notifiable_id, read_at, created_at DESC),
    INDEX idx_notification_type (notification_type, created_at),
    INDEX idx_unread (notifiable_type, notifiable_id, read_at) WHERE read_at IS NULL
);

-- Notification data examples
INSERT INTO notifications (notifiable_type, notifiable_id, notification_type, data) VALUES
('User', 123, 'like', '{"post_id": 456, "liker_name": "John Doe", "post_title": "My Post"}'),
('User', 123, 'comment', '{"post_id": 456, "commenter_name": "Jane Smith", "comment": "Great post!"}'),
('User', 123, 'follow', '{"follower_name": "Bob Wilson", "follower_id": 789}'),
('Group', 456, 'mention', '{"post_id": 789, "mentioned_by": "Alice", "post_content": "Check out this group!"}');
```

## 🏗️ Single Table Inheritance (STI) Patterns

### The "User Types" STI Pattern
```sql
-- Single table for all user types
CREATE TABLE users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    user_type ENUM('customer', 'admin', 'vendor', 'moderator', 'support') NOT NULL,
    
    -- Common fields
    name VARCHAR(100) NOT NULL,
    avatar_url VARCHAR(500),
    status ENUM('active', 'inactive', 'suspended', 'deleted') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Customer-specific fields
    phone VARCHAR(20),
    shipping_address JSON,
    billing_address JSON,
    preferences JSON,
    
    -- Admin-specific fields
    role VARCHAR(50),
    permissions JSON,
    last_login TIMESTAMP NULL,
    
    -- Vendor-specific fields
    company_name VARCHAR(200),
    business_type VARCHAR(100),
    tax_id VARCHAR(50),
    commission_rate DECIMAL(5,2),
    
    -- Moderator-specific fields
    moderation_level ENUM('junior', 'senior', 'lead') DEFAULT 'junior',
    assigned_categories JSON,
    
    -- Support-specific fields
    support_level ENUM('tier1', 'tier2', 'tier3') DEFAULT 'tier1',
    specializations JSON,
    
    -- Type-specific indexes
    INDEX idx_user_type_status (user_type, status, created_at),
    INDEX idx_customer_email (email) WHERE user_type = 'customer',
    INDEX idx_admin_role (role, last_login) WHERE user_type = 'admin',
    INDEX idx_vendor_company (company_name, business_type) WHERE user_type = 'vendor',
    INDEX idx_moderator_level (moderation_level, assigned_categories) WHERE user_type = 'moderator',
    INDEX idx_support_level (support_level, specializations) WHERE user_type = 'support'
);

-- Type-specific queries
-- Get all customers
SELECT id, email, name, phone, shipping_address, preferences
FROM users 
WHERE user_type = 'customer' 
AND status = 'active';

-- Get admins with specific role
SELECT id, email, name, role, permissions, last_login
FROM users 
WHERE user_type = 'admin' 
AND role = 'super_admin';

-- Get vendors with commission info
SELECT id, email, name, company_name, business_type, commission_rate
FROM users 
WHERE user_type = 'vendor' 
AND status = 'active';
```

### The "Content Types" STI Pattern
```sql
-- Single table for all content types
CREATE TABLE content_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    content_type ENUM('post', 'photo', 'video', 'story', 'poll', 'article') NOT NULL,
    user_id BIGINT NOT NULL,
    
    -- Common fields
    title VARCHAR(255),
    description TEXT,
    visibility ENUM('public', 'private', 'friends', 'custom') DEFAULT 'public',
    status ENUM('draft', 'published', 'archived', 'deleted') DEFAULT 'published',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Post-specific fields
    content TEXT,
    tags JSON,
    
    -- Photo-specific fields
    image_url VARCHAR(500),
    image_metadata JSON,
    filter_type VARCHAR(50),
    location VARCHAR(200),
    
    -- Video-specific fields
    video_url VARCHAR(500),
    thumbnail_url VARCHAR(500),
    duration INT,  -- in seconds
    video_metadata JSON,
    
    -- Story-specific fields
    story_type ENUM('text', 'image', 'video', 'poll') DEFAULT 'text',
    expires_at TIMESTAMP,
    background_color VARCHAR(7),
    
    -- Poll-specific fields
    question TEXT,
    options JSON,
    end_date TIMESTAMP,
    allow_multiple BOOLEAN DEFAULT FALSE,
    
    -- Article-specific fields
    article_content LONGTEXT,
    reading_time INT,  -- in minutes
    category VARCHAR(100),
    tags JSON,
    
    -- Type-specific indexes
    INDEX idx_content_type_user (content_type, user_id, created_at DESC),
    INDEX idx_content_visibility (visibility, created_at DESC),
    INDEX idx_post_content (content_type, content) WHERE content_type = 'post',
    INDEX idx_photo_location (content_type, location) WHERE content_type = 'photo',
    INDEX idx_video_duration (content_type, duration) WHERE content_type = 'video',
    INDEX idx_story_expires (content_type, expires_at) WHERE content_type = 'story',
    INDEX idx_poll_end_date (content_type, end_date) WHERE content_type = 'poll',
    INDEX idx_article_category (content_type, category) WHERE content_type = 'article'
);
```

## 🏛️ Class Table Inheritance (CTI) Patterns

### The "Payment Methods" CTI Pattern
```sql
-- Base payment table
CREATE TABLE payments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    status ENUM('pending', 'processing', 'completed', 'failed', 'refunded') DEFAULT 'pending',
    payment_type ENUM('credit_card', 'paypal', 'bank_transfer', 'crypto', 'gift_card') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_user_payments (user_id, created_at DESC),
    INDEX idx_payment_status (status, created_at),
    INDEX idx_payment_type (payment_type, status)
);

-- Credit card payments
CREATE TABLE credit_card_payments (
    payment_id BIGINT PRIMARY KEY,
    card_last4 VARCHAR(4) NOT NULL,
    card_brand VARCHAR(20) NOT NULL,
    card_exp_month TINYINT NOT NULL,
    card_exp_year SMALLINT NOT NULL,
    billing_address JSON,
    transaction_id VARCHAR(100),
    FOREIGN KEY (payment_id) REFERENCES payments(id),
    INDEX idx_card_brand (card_brand, created_at),
    INDEX idx_transaction (transaction_id)
);

-- PayPal payments
CREATE TABLE paypal_payments (
    payment_id BIGINT PRIMARY KEY,
    paypal_email VARCHAR(255) NOT NULL,
    paypal_transaction_id VARCHAR(100),
    payer_id VARCHAR(100),
    FOREIGN KEY (payment_id) REFERENCES payments(id),
    INDEX idx_paypal_email (paypal_email),
    INDEX idx_paypal_transaction (paypal_transaction_id)
);

-- Bank transfer payments
CREATE TABLE bank_transfer_payments (
    payment_id BIGINT PRIMARY KEY,
    bank_name VARCHAR(100) NOT NULL,
    account_last4 VARCHAR(4) NOT NULL,
    routing_number VARCHAR(20),
    transfer_reference VARCHAR(100),
    FOREIGN KEY (payment_id) REFERENCES payments(id),
    INDEX idx_bank_name (bank_name),
    INDEX idx_transfer_reference (transfer_reference)
);

-- Crypto payments
CREATE TABLE crypto_payments (
    payment_id BIGINT PRIMARY KEY,
    cryptocurrency VARCHAR(20) NOT NULL,
    wallet_address VARCHAR(255) NOT NULL,
    transaction_hash VARCHAR(255),
    block_number BIGINT,
    FOREIGN KEY (payment_id) REFERENCES payments(id),
    INDEX idx_cryptocurrency (cryptocurrency),
    INDEX idx_transaction_hash (transaction_hash)
);
```

## 🔄 Concrete Table Inheritance (CTI) Patterns

### The "Product Types" CTI Pattern
```sql
-- Physical products
CREATE TABLE physical_products (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    sku VARCHAR(100) UNIQUE NOT NULL,
    weight DECIMAL(8,2),
    dimensions JSON,  -- {length, width, height}
    stock_quantity INT DEFAULT 0,
    category_id BIGINT,
    brand_id BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_sku (sku),
    INDEX idx_category_price (category_id, price),
    INDEX idx_brand_stock (brand_id, stock_quantity),
    INDEX idx_weight (weight) WHERE weight IS NOT NULL
);

-- Digital products
CREATE TABLE digital_products (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    sku VARCHAR(100) UNIQUE NOT NULL,
    file_url VARCHAR(500),
    file_size BIGINT,  -- in bytes
    file_type VARCHAR(50),
    download_limit INT,  -- -1 for unlimited
    license_type ENUM('single_use', 'multi_use', 'subscription') DEFAULT 'single_use',
    category_id BIGINT,
    brand_id BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_sku (sku),
    INDEX idx_category_price (category_id, price),
    INDEX idx_file_type (file_type),
    INDEX idx_license_type (license_type)
);

-- Service products
CREATE TABLE service_products (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    sku VARCHAR(100) UNIQUE NOT NULL,
    service_type ENUM('consultation', 'maintenance', 'installation', 'training') NOT NULL,
    duration_hours INT,
    location_type ENUM('remote', 'onsite', 'hybrid') DEFAULT 'remote',
    availability_schedule JSON,
    provider_id BIGINT,
    category_id BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_sku (sku),
    INDEX idx_service_type (service_type, price),
    INDEX idx_provider_availability (provider_id, availability_schedule),
    INDEX idx_location_type (location_type)
);
```

## 🎯 Advanced Polymorphic Query Patterns

### The "Universal Search" Pattern
```sql
-- Search across all content types
CREATE TABLE search_index (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    searchable_type VARCHAR(50) NOT NULL,
    searchable_id BIGINT NOT NULL,
    search_text TEXT NOT NULL,
    search_vector TEXT GENERATED ALWAYS AS (
        CONCAT_WS(' ', 
            COALESCE(title, ''),
            COALESCE(description, ''),
            COALESCE(content, '')
        )
    ) STORED,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FULLTEXT INDEX idx_search_vector (search_vector),
    INDEX idx_searchable (searchable_type, searchable_id),
    INDEX idx_created (created_at DESC)
);

-- Universal search query
SELECT 
    searchable_type,
    searchable_id,
    MATCH(search_vector) AGAINST('search term' IN BOOLEAN MODE) as relevance_score
FROM search_index
WHERE MATCH(search_vector) AGAINST('search term' IN BOOLEAN MODE)
ORDER BY relevance_score DESC
LIMIT 20;
```

### The "Activity Feed" Pattern
```sql
-- Universal activity tracking
CREATE TABLE activities (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    activity_type VARCHAR(50) NOT NULL,  -- 'post_created', 'photo_uploaded', 'comment_added'
    subject_type VARCHAR(50) NOT NULL,   -- 'Post', 'Photo', 'Comment'
    subject_id BIGINT NOT NULL,
    object_type VARCHAR(50) NULL,        -- 'User', 'Group', 'Event'
    object_id BIGINT NULL,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_user_activities (user_id, created_at DESC),
    INDEX idx_subject (subject_type, subject_id),
    INDEX idx_activity_type (activity_type, created_at),
    INDEX idx_object (object_type, object_id)
);

-- Activity feed query
SELECT 
    a.*,
    CASE a.subject_type
        WHEN 'Post' THEN p.title
        WHEN 'Photo' THEN ph.caption
        WHEN 'Comment' THEN c.content
        ELSE NULL
    END as subject_content,
    CASE a.object_type
        WHEN 'User' THEN u.name
        WHEN 'Group' THEN g.name
        WHEN 'Event' THEN e.title
        ELSE NULL
    END as object_name
FROM activities a
LEFT JOIN posts p ON a.subject_type = 'Post' AND a.subject_id = p.id
LEFT JOIN photos ph ON a.subject_type = 'Photo' AND a.subject_id = ph.id
LEFT JOIN comments c ON a.subject_type = 'Comment' AND a.subject_id = c.id
LEFT JOIN users u ON a.object_type = 'User' AND a.object_id = u.id
LEFT JOIN groups g ON a.object_type = 'Group' AND a.object_id = g.id
LEFT JOIN events e ON a.object_type = 'Event' AND a.object_id = e.id
WHERE a.user_id = 123
ORDER BY a.created_at DESC
LIMIT 50;
```

## 🚀 Performance Optimization Hacks

### The "Materialized View" Pattern
```sql
-- Materialized view for polymorphic counts
CREATE TABLE polymorphic_counts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    countable_type VARCHAR(50) NOT NULL,
    countable_id BIGINT NOT NULL,
    count_type VARCHAR(50) NOT NULL,  -- 'likes', 'comments', 'views'
    count_value INT DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_countable_type (countable_type, countable_id, count_type),
    INDEX idx_countable (countable_type, countable_id),
    INDEX idx_count_type (count_type, count_value DESC)
);

-- Update counts procedure
DELIMITER $$
CREATE PROCEDURE update_polymorphic_counts()
BEGIN
    -- Update like counts
    INSERT INTO polymorphic_counts (countable_type, countable_id, count_type, count_value)
    SELECT likeable_type, likeable_id, 'likes', COUNT(*)
    FROM likes
    GROUP BY likeable_type, likeable_id
    ON DUPLICATE KEY UPDATE 
        count_value = VALUES(count_value),
        last_updated = NOW();
    
    -- Update comment counts
    INSERT INTO polymorphic_counts (countable_type, countable_id, count_type, count_value)
    SELECT commentable_type, commentable_id, 'comments', COUNT(*)
    FROM comments
    GROUP BY commentable_type, commentable_id
    ON DUPLICATE KEY UPDATE 
        count_value = VALUES(count_value),
        last_updated = NOW();
END$$
DELIMITER ;
```

### The "Denormalized Polymorphic" Pattern
```sql
-- Denormalized table for fast polymorphic queries
CREATE TABLE polymorphic_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    subject_type VARCHAR(50) NOT NULL,
    subject_id BIGINT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    view_count INT DEFAULT 0,
    share_count INT DEFAULT 0,
    engagement_score DECIMAL(5,2) DEFAULT 0,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_subject (subject_type, subject_id),
    INDEX idx_engagement (engagement_score DESC),
    INDEX idx_activity (last_activity DESC),
    INDEX idx_likes (like_count DESC),
    INDEX idx_comments (comment_count DESC)
);

-- Update summary procedure
DELIMITER $$
CREATE PROCEDURE update_polymorphic_summary()
BEGIN
    INSERT INTO polymorphic_summary (subject_type, subject_id, like_count, comment_count)
    SELECT 
        l.likeable_type,
        l.likeable_id,
        COUNT(DISTINCT l.id) as like_count,
        COUNT(DISTINCT c.id) as comment_count
    FROM likes l
    LEFT JOIN comments c ON l.likeable_type = c.commentable_type AND l.likeable_id = c.commentable_id
    GROUP BY l.likeable_type, l.likeable_id
    ON DUPLICATE KEY UPDATE 
        like_count = VALUES(like_count),
        comment_count = VALUES(comment_count),
        engagement_score = (VALUES(like_count) * 1 + VALUES(comment_count) * 2),
        last_activity = NOW();
END$$
DELIMITER ;
```

These patterns show the real-world inheritance and polymorphic techniques that product engineers use to build scalable, maintainable systems! 🚀
