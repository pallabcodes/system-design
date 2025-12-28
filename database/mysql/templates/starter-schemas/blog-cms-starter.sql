-- Blog/CMS Platform Starter Schema (MySQL)
-- Minimal but complete schema for content management systems, blogs, and publishing platforms
-- Adapted for MySQL with InnoDB engine, MySQL JSON, and MySQL-specific features

-- ===========================================
-- USERS AND AUTHENTICATION
-- ===========================================

CREATE TABLE users (
    user_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(200),
    bio TEXT,
    avatar_url VARCHAR(500),
    website VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    role ENUM('admin', 'editor', 'author', 'contributor', 'subscriber') DEFAULT 'author',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP NULL,

    INDEX idx_users_email (email),
    INDEX idx_users_username (username),
    INDEX idx_users_active (is_active),
    INDEX idx_users_role (role)
) ENGINE = InnoDB;

CREATE TABLE user_profiles (
    profile_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    user_id CHAR(36) NOT NULL,
    display_name VARCHAR(100),
    location VARCHAR(255),
    social_links JSON DEFAULT ('{}'),  -- {"twitter": "handle", "linkedin": "url"}
    interests JSON DEFAULT ('[]'),     -- Array-like structure using JSON
    notification_preferences JSON DEFAULT ('{"email": true, "push": false}'),

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    UNIQUE KEY unique_user_profile (user_id),

    INDEX idx_profiles_user_id (user_id),
    INDEX idx_profiles_location (location)
) ENGINE = InnoDB;

-- ===========================================
-- CONTENT MANAGEMENT
-- ===========================================

CREATE TABLE categories (
    category_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    category_name VARCHAR(100) NOT NULL,
    slug VARCHAR(120) UNIQUE NOT NULL,
    description TEXT,
    parent_id CHAR(36) NULL,
    category_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (parent_id) REFERENCES categories(category_id) ON DELETE SET NULL,

    INDEX idx_categories_slug (slug),
    INDEX idx_categories_parent (parent_id),
    INDEX idx_categories_active (is_active),
    INDEX idx_categories_order (category_order)
) ENGINE = InnoDB;

CREATE TABLE posts (
    post_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    excerpt TEXT,
    content LONGTEXT,
    featured_image VARCHAR(500),

    -- Status and visibility
    status ENUM('draft', 'published', 'scheduled', 'archived') DEFAULT 'draft',
    visibility ENUM('public', 'private', 'password_protected') DEFAULT 'public',
    password_hash VARCHAR(255) NULL,

    -- Author and timestamps
    author_id CHAR(36) NOT NULL,
    published_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- SEO and metadata
    seo_title VARCHAR(60),
    seo_description VARCHAR(160),
    canonical_url VARCHAR(500),

    -- Content metadata
    word_count INT DEFAULT 0,
    reading_time_minutes INT DEFAULT 0,
    is_featured BOOLEAN DEFAULT FALSE,
    is_sticky BOOLEAN DEFAULT FALSE,

    FOREIGN KEY (author_id) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_posts_author (author_id),
    INDEX idx_posts_status (status),
    INDEX idx_posts_visibility (visibility),
    INDEX idx_posts_published_at (published_at),
    INDEX idx_posts_featured (is_featured),
    INDEX idx_posts_sticky (is_sticky),
    INDEX idx_posts_slug (slug),
    FULLTEXT INDEX ft_posts_title_content (title, content),
    FULLTEXT INDEX ft_posts_excerpt (excerpt)
) ENGINE = InnoDB;

CREATE TABLE post_categories (
    post_id CHAR(36) NOT NULL,
    category_id CHAR(36) NOT NULL,

    PRIMARY KEY (post_id, category_id),
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE CASCADE,

    INDEX idx_post_categories_category (category_id)
) ENGINE = InnoDB;

CREATE TABLE tags (
    tag_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tag_name VARCHAR(50) UNIQUE NOT NULL,
    slug VARCHAR(60) UNIQUE NOT NULL,
    description TEXT,
    color VARCHAR(7) DEFAULT '#3498db', -- Hex color
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_tags_name (tag_name),
    INDEX idx_tags_slug (slug)
) ENGINE = InnoDB;

CREATE TABLE post_tags (
    post_id CHAR(36) NOT NULL,
    tag_id CHAR(36) NOT NULL,

    PRIMARY KEY (post_id, tag_id),
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(tag_id) ON DELETE CASCADE,

    INDEX idx_post_tags_tag (tag_id)
) ENGINE = InnoDB;

-- ===========================================
-- COMMENTS AND INTERACTIONS
-- ===========================================

CREATE TABLE comments (
    comment_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    post_id CHAR(36) NOT NULL,
    author_id CHAR(36) NULL,  -- NULL for guest comments
    parent_id CHAR(36) NULL,  -- For nested replies

    -- Comment content
    author_name VARCHAR(100),
    author_email VARCHAR(255),
    author_website VARCHAR(255),
    content TEXT NOT NULL,

    -- Status and moderation
    status ENUM('pending', 'approved', 'spam', 'trash') DEFAULT 'pending',
    is_approved BOOLEAN DEFAULT FALSE,

    -- Metadata
    author_ip VARCHAR(45),  -- Support IPv6
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    FOREIGN KEY (author_id) REFERENCES users(user_id) ON DELETE SET NULL,
    FOREIGN KEY (parent_id) REFERENCES comments(comment_id) ON DELETE CASCADE,

    INDEX idx_comments_post (post_id),
    INDEX idx_comments_author (author_id),
    INDEX idx_comments_parent (parent_id),
    INDEX idx_comments_status (status),
    INDEX idx_comments_approved (is_approved),
    INDEX idx_comments_created_at (created_at),
    FULLTEXT INDEX ft_comments_content (content)
) ENGINE = InnoDB;

-- ===========================================
-- MEDIA MANAGEMENT
-- ===========================================

CREATE TABLE media (
    media_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL,  -- Size in bytes

    -- Image dimensions (NULL for non-images)
    width INT NULL,
    height INT NULL,

    -- Metadata
    alt_text VARCHAR(255),
    caption TEXT,
    description TEXT,

    -- Upload info
    uploaded_by CHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (uploaded_by) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_media_uploaded_by (uploaded_by),
    INDEX idx_media_mime_type (mime_type),
    INDEX idx_media_created_at (created_at)
) ENGINE = InnoDB;

-- ===========================================
-- ANALYTICS AND METRICS
-- ===========================================

CREATE TABLE post_views (
    view_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    post_id CHAR(36) NOT NULL,
    viewer_ip VARCHAR(45),
    user_agent TEXT,
    referrer_url VARCHAR(500),
    viewed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,

    INDEX idx_views_post (post_id),
    INDEX idx_views_ip (viewer_ip),
    INDEX idx_views_viewed_at (viewed_at)
) ENGINE = InnoDB;

CREATE TABLE post_likes (
    like_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    post_id CHAR(36) NOT NULL,
    user_id CHAR(36) NULL,  -- NULL for anonymous likes
    liked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    UNIQUE KEY unique_post_user_like (post_id, user_id),

    INDEX idx_likes_post (post_id),
    INDEX idx_likes_user (user_id),
    INDEX idx_likes_liked_at (liked_at)
) ENGINE = InnoDB;

-- ===========================================
-- SETTINGS AND CONFIGURATION
-- ===========================================

CREATE TABLE site_settings (
    setting_id INT PRIMARY KEY AUTO_INCREMENT,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value LONGTEXT,
    setting_type ENUM('string', 'integer', 'boolean', 'json', 'array') DEFAULT 'string',
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_settings_key (setting_key),
    INDEX idx_settings_public (is_public)
) ENGINE = InnoDB;

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Composite indexes for common queries
CREATE INDEX idx_posts_author_status ON posts (author_id, status);
CREATE INDEX idx_posts_published_featured ON posts (published_at, is_featured);
CREATE INDEX idx_posts_status_published ON posts (status, published_at);
CREATE INDEX idx_comments_post_status ON comments (post_id, status);
CREATE INDEX idx_comments_created_status ON comments (created_at, status);

-- ===========================================
-- TRIGGERS FOR AUTOMATION
-- ===========================================

DELIMITER ;;

-- Update post word count and reading time
CREATE TRIGGER update_post_metadata BEFORE INSERT ON posts
FOR EACH ROW
BEGIN
    IF NEW.content IS NOT NULL THEN
        SET NEW.word_count = LENGTH(NEW.content) - LENGTH(REPLACE(NEW.content, ' ', '')) + 1;
        SET NEW.reading_time_minutes = CEIL(NEW.word_count / 200); -- 200 words per minute
    END IF;
END;;

-- Update user profile timestamps
CREATE TRIGGER update_user_profile_timestamp BEFORE UPDATE ON user_profiles
FOR EACH ROW
BEGIN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END;;

DELIMITER ;

-- ===========================================
-- INITIAL DATA
-- ===========================================

INSERT INTO site_settings (setting_key, setting_value, setting_type, is_public) VALUES
('site_name', 'My Blog', 'string', TRUE),
('site_description', 'A modern content management system', 'string', TRUE),
('posts_per_page', '10', 'integer', TRUE),
('comments_enabled', 'true', 'boolean', TRUE),
('registration_enabled', 'true', 'boolean', TRUE);

-- Create default admin user (password should be hashed)
INSERT INTO users (user_id, username, email, password_hash, full_name, role, email_verified) VALUES
(UUID(), 'admin', 'admin@example.com', '$2b$10$hashedpasswordhere', 'Site Administrator', 'admin', TRUE);

-- Create default category
INSERT INTO categories (category_id, category_name, slug, description) VALUES
(UUID(), 'Uncategorized', 'uncategorized', 'Default category for posts');

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

CREATE VIEW post_summary AS
SELECT
    p.post_id,
    p.title,
    p.slug,
    p.excerpt,
    p.status,
    p.published_at,
    p.created_at,
    u.username AS author_username,
    u.full_name AS author_name,
    COUNT(DISTINCT pc.category_id) AS category_count,
    COUNT(DISTINCT pt.tag_id) AS tag_count,
    COUNT(DISTINCT pv.view_id) AS view_count,
    COUNT(DISTINCT pl.like_id) AS like_count,
    COUNT(DISTINCT c.comment_id) AS comment_count
FROM posts p
LEFT JOIN users u ON p.author_id = u.user_id
LEFT JOIN post_categories pc ON p.post_id = pc.post_id
LEFT JOIN post_tags pt ON p.post_id = pt.post_id
LEFT JOIN post_views pv ON p.post_id = pv.post_id
LEFT JOIN post_likes pl ON p.post_id = pl.post_id
LEFT JOIN comments c ON p.post_id = c.post_id AND c.status = 'approved'
GROUP BY p.post_id, p.title, p.slug, p.excerpt, p.status, p.published_at, p.created_at, u.username, u.full_name;

-- ===========================================
-- STORED PROCEDURES
-- ===========================================

DELIMITER ;;

-- Get posts with pagination and filtering
CREATE PROCEDURE get_posts(
    IN p_status ENUM('draft', 'published', 'scheduled', 'archived'),
    IN p_author_id CHAR(36),
    IN p_category_id CHAR(36),
    IN p_tag_id CHAR(36),
    IN p_limit INT,
    IN p_offset INT
)
BEGIN
    SELECT
        p.*,
        u.username AS author_username,
        u.full_name AS author_name,
        GROUP_CONCAT(DISTINCT c.category_name) AS categories,
        GROUP_CONCAT(DISTINCT t.tag_name) AS tags
    FROM posts p
    LEFT JOIN users u ON p.author_id = u.user_id
    LEFT JOIN post_categories pc ON p.post_id = pc.post_id
    LEFT JOIN categories c ON pc.category_id = c.category_id
    LEFT JOIN post_tags pt ON p.post_id = pt.post_id
    LEFT JOIN tags t ON pt.tag_id = t.tag_id
    WHERE (p_status IS NULL OR p.status = p_status)
      AND (p_author_id IS NULL OR p.author_id = p_author_id)
      AND (p_category_id IS NULL OR pc.category_id = p_category_id)
      AND (p_tag_id IS NULL OR pt.tag_id = p_tag_id)
    GROUP BY p.post_id
    ORDER BY p.published_at DESC, p.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;;

DELIMITER ;

/*
USAGE EXAMPLES:

-- Get published posts
CALL get_posts('published', NULL, NULL, NULL, 10, 0);

-- Get posts by specific author
CALL get_posts('published', 'user-uuid-here', NULL, NULL, 10, 0);

-- Get posts in specific category
CALL get_posts('published', NULL, 'category-uuid-here', NULL, 10, 0);

This schema provides a complete foundation for a modern blog/CMS platform with:
- User management and authentication
- Content creation and categorization
- Commenting system
- Media management
- Analytics and engagement tracking
- Search functionality (fulltext indexes)
- Configurable settings
- Performance optimizations
- Administrative features

Adapt and extend based on your specific requirements!
*/
