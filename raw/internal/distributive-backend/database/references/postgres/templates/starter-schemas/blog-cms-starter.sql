-- Blog/CMS Platform Starter Schema
-- Minimal but complete schema for content management systems, blogs, and publishing platforms

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "unaccent";  -- For accent-insensitive search

-- ===========================================
-- USERS AND AUTHENTICATION
-- ===========================================

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(200),
    bio TEXT,
    avatar_url VARCHAR(500),
    website VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    role VARCHAR(20) DEFAULT 'author' CHECK (role IN ('admin', 'editor', 'author', 'contributor', 'subscriber')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE user_profiles (
    profile_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    display_name VARCHAR(100),
    location VARCHAR(255),
    social_links JSONB DEFAULT '{}',  -- {"twitter": "handle", "linkedin": "url"}
    interests TEXT[],
    notification_preferences JSONB DEFAULT '{"email": true, "push": false}',
    UNIQUE (user_id)
);

-- ===========================================
-- CONTENT MANAGEMENT
-- ===========================================

CREATE TABLE categories (
    category_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_name VARCHAR(100) NOT NULL,
    slug VARCHAR(120) UNIQUE NOT NULL,
    description TEXT,
    parent_id UUID REFERENCES categories(category_id),
    color VARCHAR(7),  -- Hex color code
    icon VARCHAR(50),
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tags (
    tag_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tag_name VARCHAR(50) UNIQUE NOT NULL,
    slug VARCHAR(60) UNIQUE NOT NULL,
    color VARCHAR(7),
    description TEXT,
    usage_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE posts (
    post_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    author_id UUID NOT NULL REFERENCES users(user_id),
    title VARCHAR(300) NOT NULL,
    slug VARCHAR(350) UNIQUE NOT NULL,
    excerpt TEXT,
    content TEXT NOT NULL,
    content_format VARCHAR(20) DEFAULT 'markdown' CHECK (content_format IN ('markdown', 'html', 'plaintext')),

    -- Status and Visibility
    post_status VARCHAR(20) DEFAULT 'draft' CHECK (post_status IN ('draft', 'published', 'scheduled', 'archived', 'trashed')),
    visibility VARCHAR(20) DEFAULT 'public' CHECK (visibility IN ('public', 'private', 'password_protected', 'members_only')),
    password_hash VARCHAR(255),  -- For password protected posts

    -- Categories and Tags
    category_id UUID REFERENCES categories(category_id),
    tag_ids UUID[] DEFAULT '{}',  -- Array of tag IDs

    -- Media
    featured_image_url VARCHAR(500),
    featured_image_alt VARCHAR(255),
    media_gallery JSONB DEFAULT '[]',  -- Array of media objects

    -- SEO and Meta
    seo_title VARCHAR(60),
    seo_description VARCHAR(160),
    canonical_url VARCHAR(500),
    noindex BOOLEAN DEFAULT FALSE,

    -- Engagement
    view_count INTEGER DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,

    -- Scheduling
    published_at TIMESTAMP WITH TIME ZONE,
    scheduled_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(excerpt, '') || ' ' || COALESCE(content, ''))
    ) STORED
);

CREATE TABLE post_revisions (
    revision_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    revision_number INTEGER NOT NULL,
    author_id UUID NOT NULL REFERENCES users(user_id),
    title VARCHAR(300),
    content TEXT,
    excerpt TEXT,
    revision_note TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (post_id, revision_number)
);

-- ===========================================
-- COMMENTS AND INTERACTIONS
-- ===========================================

CREATE TABLE comments (
    comment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    author_id UUID REFERENCES users(user_id),  -- NULL for guest comments
    parent_comment_id UUID REFERENCES comments(comment_id),  -- For threaded comments

    -- Comment Content
    author_name VARCHAR(100),  -- For guest comments
    author_email VARCHAR(255),  -- For guest comments
    author_url VARCHAR(255),
    content TEXT NOT NULL,

    -- Comment Status
    comment_status VARCHAR(20) DEFAULT 'approved' CHECK (comment_status IN ('pending', 'approved', 'spam', 'trashed')),
    is_spam BOOLEAN DEFAULT FALSE,

    -- IP and User Agent for spam detection
    author_ip INET,
    user_agent TEXT,

    -- Threading
    thread_level INTEGER DEFAULT 0,
    thread_path LTREE,

    -- Moderation
    moderated_by UUID REFERENCES users(user_id),
    moderated_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE post_likes (
    like_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(user_id),
    like_type VARCHAR(20) DEFAULT 'like' CHECK (like_type IN ('like', 'love', 'laugh', 'angry', 'sad', 'wow')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (post_id, user_id)
);

-- ===========================================
-- MEDIA MANAGEMENT
-- ===========================================

CREATE TABLE media (
    media_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    uploaded_by UUID NOT NULL REFERENCES users(user_id),
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    media_type VARCHAR(20) NOT NULL CHECK (media_type IN ('image', 'video', 'audio', 'document', 'archive')),

    -- Image/Video specific
    width INTEGER,
    height INTEGER,
    duration_seconds INTEGER,  -- For video/audio
    thumbnail_url VARCHAR(500),

    -- Metadata
    alt_text VARCHAR(255),
    caption TEXT,
    description TEXT,
    credit VARCHAR(255),

    -- SEO
    title VARCHAR(100),
    seo_description VARCHAR(160),

    -- Usage tracking
    usage_count INTEGER DEFAULT 0,
    last_used_at TIMESTAMP WITH TIME ZONE,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- PAGES AND NAVIGATION
-- ===========================================

CREATE TABLE pages (
    page_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    author_id UUID NOT NULL REFERENCES users(user_id),
    parent_page_id UUID REFERENCES pages(page_id),

    -- Page Content
    title VARCHAR(300) NOT NULL,
    slug VARCHAR(350) UNIQUE NOT NULL,
    content TEXT,
    content_format VARCHAR(20) DEFAULT 'markdown' CHECK (content_format IN ('markdown', 'html', 'plaintext')),

    -- Page Settings
    page_template VARCHAR(50) DEFAULT 'default',
    show_in_navigation BOOLEAN DEFAULT TRUE,
    navigation_order INTEGER DEFAULT 0,
    is_homepage BOOLEAN DEFAULT FALSE,

    -- SEO
    seo_title VARCHAR(60),
    seo_description VARCHAR(160),
    canonical_url VARCHAR(500),

    -- Status
    page_status VARCHAR(20) DEFAULT 'published' CHECK (page_status IN ('draft', 'published', 'archived')),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE navigation_menus (
    menu_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    menu_name VARCHAR(100) NOT NULL,
    menu_slug VARCHAR(120) UNIQUE NOT NULL,
    menu_location VARCHAR(50),  -- 'header', 'footer', 'sidebar'
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE navigation_items (
    item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    menu_id UUID NOT NULL REFERENCES navigation_menus(menu_id) ON DELETE CASCADE,
    parent_item_id UUID REFERENCES navigation_items(item_id),

    -- Item Details
    item_type VARCHAR(20) NOT NULL CHECK (item_type IN ('page', 'post', 'category', 'tag', 'custom')),
    item_label VARCHAR(100) NOT NULL,
    item_url VARCHAR(500),

    -- References
    page_id UUID REFERENCES pages(page_id),
    post_id UUID REFERENCES posts(post_id),
    category_id UUID REFERENCES categories(category_id),
    tag_id UUID REFERENCES tags(tag_id),

    -- Display
    css_classes VARCHAR(255),
    item_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- SETTINGS AND CONFIGURATION
-- ===========================================

CREATE TABLE site_settings (
    setting_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    setting_type VARCHAR(20) DEFAULT 'string' CHECK (setting_type IN ('string', 'integer', 'boolean', 'json')),
    setting_group VARCHAR(50) DEFAULT 'general',
    is_public BOOLEAN DEFAULT FALSE,
    description TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(user_id)
);

-- ===========================================
-- ANALYTICS AND METRICS
-- ===========================================

CREATE TABLE page_views (
    view_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_type VARCHAR(20) NOT NULL CHECK (content_type IN ('post', 'page', 'category', 'tag', 'author')),
    content_id UUID NOT NULL,
    viewed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    viewer_ip INET,
    user_agent TEXT,
    referrer_url VARCHAR(500),
    session_id VARCHAR(255),
    user_id UUID REFERENCES users(user_id),
    country_code CHAR(2),
    city VARCHAR(100)
) PARTITION BY RANGE (viewed_at); -- this `viewed_at` is the partition key

CREATE TABLE search_queries (
    query_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    search_query TEXT NOT NULL,
    result_count INTEGER DEFAULT 0,
    searched_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    user_id UUID REFERENCES users(user_id),
    ip_address INET,
    user_agent TEXT
);

-- ===========================================
-- EMAIL AND NEWSLETTER
-- ===========================================

CREATE TABLE newsletter_subscriptions (
    subscription_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    subscription_status VARCHAR(20) DEFAULT 'active' CHECK (subscription_status IN ('active', 'unsubscribed', 'bounced', 'complained')),
    subscription_token VARCHAR(100) UNIQUE NOT NULL,
    subscribed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    unsubscribed_at TIMESTAMP WITH TIME ZONE,
    preferences JSONB DEFAULT '{}',  -- Newsletter preferences
    source VARCHAR(50) DEFAULT 'website'  -- How they subscribed
);

CREATE TABLE email_campaigns (
    campaign_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_name VARCHAR(255) NOT NULL,
    campaign_subject VARCHAR(255) NOT NULL,
    campaign_content TEXT NOT NULL,
    campaign_type VARCHAR(30) DEFAULT 'newsletter' CHECK (campaign_type IN ('newsletter', 'promotional', 'transactional', 'announcement')),
    created_by UUID NOT NULL REFERENCES users(user_id),
    scheduled_at TIMESTAMP WITH TIME ZONE,
    sent_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft', 'scheduled', 'sending', 'sent', 'cancelled')),
    recipient_count INTEGER DEFAULT 0,
    open_count INTEGER DEFAULT 0,
    click_count INTEGER DEFAULT 0,
    unsubscribe_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- User indexes
CREATE INDEX idx_users_username ON users (username);
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_role ON users (role);
CREATE INDEX idx_users_active ON users (is_active);

-- Post indexes
CREATE INDEX idx_posts_author ON posts (author_id);
CREATE INDEX idx_posts_status ON posts (post_status);
CREATE INDEX idx_posts_category ON posts (category_id);
CREATE INDEX idx_posts_published ON posts (published_at DESC) WHERE post_status = 'published';
CREATE INDEX idx_posts_search ON posts USING gin (search_vector);
CREATE INDEX idx_posts_tags ON posts USING gin (tag_ids);

-- Comment indexes
CREATE INDEX idx_comments_post ON comments (post_id);
CREATE INDEX idx_comments_author ON comments (author_id);
CREATE INDEX idx_comments_status ON comments (comment_status);
CREATE INDEX idx_comments_thread ON comments USING gist (thread_path);

-- Media indexes
CREATE INDEX idx_media_uploaded_by ON media (uploaded_by);
CREATE INDEX idx_media_type ON media (media_type);
CREATE INDEX idx_media_active ON media (is_active);

-- Analytics indexes
CREATE INDEX idx_page_views_content ON page_views (content_type, content_id);
CREATE INDEX idx_page_views_viewed_at ON page_views (viewed_at DESC);
CREATE INDEX idx_search_queries_searched_at ON search_queries (searched_at DESC);

-- ===========================================
-- PARTITIONING SETUP
-- ===========================================

-- Page views partitioning (monthly)
CREATE TABLE page_views_2024_01 PARTITION OF page_views
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE page_views_2024_02 PARTITION OF page_views
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Published posts view
CREATE VIEW published_posts AS
SELECT
    p.*,
    u.username as author_username,
    u.full_name as author_name,
    c.category_name,
    c.slug as category_slug,
    array_agg(t.tag_name) FILTER (WHERE t.tag_name IS NOT NULL) as tag_names,
    array_agg(t.slug) FILTER (WHERE t.slug IS NOT NULL) as tag_slugs
FROM posts p
JOIN users u ON p.author_id = u.user_id
LEFT JOIN categories c ON p.category_id = c.category_id
LEFT JOIN tags t ON t.tag_id = ANY(p.tag_ids)
WHERE p.post_status = 'published'
  AND p.visibility = 'public'
GROUP BY p.post_id, u.user_id, c.category_id;

-- Popular posts view
CREATE VIEW popular_posts AS
SELECT
    p.*,
    (p.view_count * 1.0 + p.like_count * 2.0 + p.comment_count * 3.0 + p.share_count * 4.0) as popularity_score
FROM posts p
WHERE p.post_status = 'published'
  AND p.published_at >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY popularity_score DESC;

-- Monthly analytics view
CREATE VIEW monthly_analytics AS
SELECT
    DATE_TRUNC('month', pv.viewed_at) as month,
    COUNT(DISTINCT pv.view_id) as total_views,
    COUNT(DISTINCT CASE WHEN pv.content_type = 'post' THEN pv.content_id END) as posts_viewed,
    COUNT(DISTINCT CASE WHEN pv.content_type = 'page' THEN pv.content_id END) as pages_viewed,
    COUNT(DISTINCT pv.user_id) as unique_visitors,
    AVG(EXTRACT(EPOCH FROM (pv.viewed_at - LAG(pv.viewed_at) OVER (ORDER BY pv.viewed_at)))) as avg_session_duration
FROM page_views pv
WHERE pv.viewed_at >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', pv.viewed_at)
ORDER BY month DESC;

-- ===========================================
-- BASIC FUNCTIONS
-- ===========================================

-- Function to update post engagement counts
CREATE OR REPLACE FUNCTION update_post_engagement_counts()
RETURNS TRIGGER AS $$
DECLARE
    target_post_id UUID;
BEGIN
    -- Determine affected post
    IF TG_TABLE_NAME = 'post_likes' THEN
        target_post_id := NEW.post_id;
    ELSIF TG_TABLE_NAME = 'comments' THEN
        target_post_id := NEW.post_id;
    END IF;

    -- Update counts
    UPDATE posts SET
        like_count = (SELECT COUNT(*) FROM post_likes WHERE post_id = target_post_id),
        comment_count = (SELECT COUNT(*) FROM comments WHERE post_id = target_post_id AND comment_status = 'approved'),
        updated_at = CURRENT_TIMESTAMP
    WHERE post_id = target_post_id;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Function to generate slugs
CREATE OR REPLACE FUNCTION generate_slug(input_text TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN LOWER(REPLACE(REPLACE(REPLACE(TRIM(input_text), ' ', '-'), '[^a-zA-Z0-9\-]', ''), '--', '-'));
END;
$$ LANGUAGE plpgsql;

-- Function to update tag usage counts
CREATE OR REPLACE FUNCTION update_tag_usage_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE tags SET
        usage_count = (
            SELECT COUNT(*)
            FROM posts
            WHERE tag_id = ANY(tag_ids)
        ),
        updated_at = CURRENT_TIMESTAMP
    WHERE tag_id = COALESCE(NEW.tag_id, OLD.tag_id);

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- TRIGGERS
-- =========================================--

-- Update post engagement counts
CREATE TRIGGER trigger_update_post_likes
    AFTER INSERT OR DELETE ON post_likes
    FOR EACH ROW EXECUTE FUNCTION update_post_engagement_counts();

CREATE TRIGGER trigger_update_post_comments
    AFTER INSERT OR UPDATE OR DELETE ON comments
    FOR EACH ROW EXECUTE FUNCTION update_post_engagement_counts();

-- Update tag usage
CREATE TRIGGER trigger_update_tag_usage
    AFTER INSERT OR DELETE ON posts
    FOR EACH ROW EXECUTE FUNCTION update_tag_usage_count();

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert admin user
INSERT INTO users (username, email, password_hash, full_name, role) VALUES
('admin', 'admin@example.com', '$2b$10$dummy.hash.here', 'Site Administrator', 'admin');

-- Insert sample categories
INSERT INTO categories (category_name, slug, description, color) VALUES
('Technology', 'technology', 'Posts about technology and programming', '#3498db'),
('Design', 'design', 'UI/UX design and creative work', '#e74c3c'),
('Business', 'business', 'Business and entrepreneurship', '#2ecc71');

-- Insert sample tags
INSERT INTO tags (tag_name, slug, color, description) VALUES
('PostgreSQL', 'postgresql', '#336791', 'Database management system'),
('JavaScript', 'javascript', '#f7df1e', 'Programming language'),
('React', 'react', '#61dafb', 'JavaScript library');

-- Insert sample post
INSERT INTO posts (
    author_id, title, slug, excerpt, content, category_id, tag_ids,
    featured_image_url, seo_title, seo_description, published_at
) VALUES (
    (SELECT user_id FROM users WHERE username = 'admin' LIMIT 1),
    'Welcome to Our Blog',
    'welcome-to-our-blog',
    'Welcome to our new blog platform powered by PostgreSQL',
    '# Welcome!\n\nThis is our first blog post...',
    (SELECT category_id FROM categories WHERE slug = 'technology' LIMIT 1),
    ARRAY[(SELECT tag_id FROM tags WHERE slug = 'postgresql' LIMIT 1)],
    'https://example.com/images/welcome.jpg',
    'Welcome to Our Blog - PostgreSQL Powered',
    'Discover our new blog platform built with modern web technologies and PostgreSQL',
    CURRENT_TIMESTAMP
);

-- This starter schema provides the essential foundation for a blog or CMS platform
-- and can be extended with additional features as needed.
