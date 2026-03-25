-- ============================================
-- EDUCATIONAL PLATFORM SCHEMA DESIGN
-- ============================================
-- Comprehensive schema for online education, distance learning, and LMS
-- Supports multiple user types, course management, assessments, and analytics

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "hstore";

-- ============================================
-- CORE ENTITIES
-- ============================================

-- Users (Students, Instructors, Administrators)
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    profile_picture_url VARCHAR(500),
    bio TEXT,
    timezone VARCHAR(50) DEFAULT 'UTC',
    language VARCHAR(10) DEFAULT 'en',
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    email_verification_token VARCHAR(255),
    password_reset_token VARCHAR(255),
    password_reset_expires TIMESTAMP WITH TIME ZONE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT chk_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_language_length CHECK (char_length(language) BETWEEN 2 AND 10)
);

-- User roles and permissions
CREATE TABLE roles (
    role_id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    is_system_role BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert default roles
INSERT INTO roles (name, description, is_system_role) VALUES
('student', 'Regular student user', TRUE),
('instructor', 'Course instructor and content creator', TRUE),
('admin', 'Platform administrator', TRUE),
('moderator', 'Content moderator', TRUE);

CREATE TABLE user_roles (
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    role_id INTEGER REFERENCES roles(role_id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID REFERENCES users(user_id),
    expires_at TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (user_id, role_id),

    CONSTRAINT chk_no_future_expiry CHECK (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
);

-- Institutions/Organizations
CREATE TABLE institutions (
    institution_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    website_url VARCHAR(500),
    logo_url VARCHAR(500),
    address JSONB, -- {"street", "city", "state", "postal_code", "country"}
    contact_email VARCHAR(255),
    contact_phone VARCHAR(50),
    is_verified BOOLEAN DEFAULT FALSE,
    verification_documents JSONB DEFAULT '[]',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User institution affiliations
CREATE TABLE user_institutions (
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    institution_id UUID REFERENCES institutions(institution_id) ON DELETE CASCADE,
    affiliation_type VARCHAR(50) CHECK (affiliation_type IN ('student', 'staff', 'faculty', 'alumni', 'guest')),
    enrollment_date DATE,
    graduation_date DATE,
    student_id VARCHAR(50), -- Institution-specific student ID
    department VARCHAR(100),
    major VARCHAR(100),
    gpa DECIMAL(3,2),
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB DEFAULT '{}',
    PRIMARY KEY (user_id, institution_id)
);

-- ============================================
-- COURSE MANAGEMENT
-- ============================================

-- Course categories and subjects
CREATE TABLE course_categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    parent_category_id INTEGER REFERENCES course_categories(category_id),
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Courses
CREATE TABLE courses (
    course_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(300) NOT NULL,
    subtitle VARCHAR(500),
    description TEXT NOT NULL,
    short_description VARCHAR(500),
    category_id INTEGER REFERENCES course_categories(category_id),
    institution_id UUID REFERENCES institutions(institution_id),

    -- Course metadata
    language VARCHAR(10) DEFAULT 'en',
    level VARCHAR(20) CHECK (level IN ('beginner', 'intermediate', 'advanced', 'expert')),
    duration_hours DECIMAL(6,2), -- Estimated completion time
    price DECIMAL(10,2) DEFAULT 0.00,
    currency VARCHAR(3) DEFAULT 'USD',

    -- Status and visibility
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft', 'review', 'published', 'archived')),
    visibility VARCHAR(20) DEFAULT 'public' CHECK (visibility IN ('public', 'private', 'unlisted')),
    enrollment_type VARCHAR(20) DEFAULT 'open' CHECK (enrollment_type IN ('open', 'invitation_only', 'paid')),

    -- Learning objectives and prerequisites
    learning_objectives TEXT[],
    prerequisites TEXT[],
    skills_covered TEXT[],

    -- Media and resources
    thumbnail_url VARCHAR(500),
    trailer_video_url VARCHAR(500),
    welcome_message TEXT,

    -- Settings
    max_students INTEGER, -- NULL for unlimited
    allow_self_enrollment BOOLEAN DEFAULT TRUE,
    requires_approval BOOLEAN DEFAULT FALSE,
    certificate_enabled BOOLEAN DEFAULT TRUE,
    discussion_enabled BOOLEAN DEFAULT TRUE,

    -- Instructor and ownership
    instructor_id UUID REFERENCES users(user_id) NOT NULL,
    co_instructors UUID[] DEFAULT '{}',

    -- Timestamps
    published_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english',
            title || ' ' || subtitle || ' ' ||
            description || ' ' || array_to_string(skills_covered, ' ')
        )
    ) STORED,

    -- Constraints
    CONSTRAINT chk_positive_price CHECK (price >= 0),
    CONSTRAINT chk_positive_duration CHECK (duration_hours > 0),
    CONSTRAINT chk_published_date CHECK (published_at IS NULL OR published_at >= created_at)
);

-- Course modules/sections
CREATE TABLE course_modules (
    module_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(course_id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL,
    is_preview BOOLEAN DEFAULT FALSE,
    estimated_duration_minutes INTEGER,
    prerequisite_module_id UUID REFERENCES course_modules(module_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (course_id, display_order)
);

-- Course content items (lessons, quizzes, assignments)
CREATE TABLE content_items (
    content_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id UUID REFERENCES course_modules(module_id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    content_type VARCHAR(50) NOT NULL CHECK (content_type IN ('video', 'text', 'quiz', 'assignment', 'download', 'live_session')),
    display_order INTEGER NOT NULL,

    -- Content-specific fields
    video_url VARCHAR(500),
    video_duration_seconds INTEGER,
    text_content TEXT,
    download_url VARCHAR(500),
    download_filename VARCHAR(255),

    -- Settings
    is_required BOOLEAN DEFAULT TRUE,
    is_preview BOOLEAN DEFAULT FALSE,
    estimated_duration_minutes INTEGER,

    -- Quiz/Assignment specific
    quiz_id UUID, -- References quizzes table
    assignment_id UUID, -- References assignments table

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (module_id, display_order)
);

-- ============================================
-- QUIZZES AND ASSESSMENTS
-- ============================================

-- Quizzes
CREATE TABLE quizzes (
    quiz_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL,
    description TEXT,
    course_id UUID REFERENCES courses(course_id) ON DELETE CASCADE,
    module_id UUID REFERENCES course_modules(module_id) ON DELETE CASCADE,
    content_id UUID REFERENCES content_items(content_id) ON DELETE CASCADE,

    -- Quiz settings
    time_limit_minutes INTEGER,
    passing_score_percentage DECIMAL(5,2), -- 0.00 to 100.00
    max_attempts INTEGER DEFAULT 1,
    shuffle_questions BOOLEAN DEFAULT FALSE,
    show_answers_after BOOLEAN DEFAULT TRUE,

    -- Grading
    is_graded BOOLEAN DEFAULT TRUE,
    weight DECIMAL(5,2) DEFAULT 1.00, -- Weight in final grade

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_passing_score_range CHECK (passing_score_percentage BETWEEN 0 AND 100),
    CONSTRAINT chk_positive_weight CHECK (weight > 0)
);

-- Quiz questions
CREATE TABLE quiz_questions (
    question_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID REFERENCES quizzes(quiz_id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    question_type VARCHAR(20) NOT NULL CHECK (question_type IN ('multiple_choice', 'true_false', 'short_answer', 'essay', 'matching')),
    display_order INTEGER NOT NULL,
    points DECIMAL(5,2) DEFAULT 1.00,
    explanation TEXT, -- Correct answer explanation

    -- Question-specific data
    options JSONB, -- For multiple choice: [{"text": "Option A", "is_correct": true}, ...]
    correct_answer TEXT, -- For short answer
    matching_pairs JSONB, -- For matching questions

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (quiz_id, display_order),
    CONSTRAINT chk_positive_points CHECK (points > 0)
);

-- ============================================
-- ENROLLMENT AND PROGRESS TRACKING
-- ============================================

-- Course enrollments
CREATE TABLE enrollments (
    enrollment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    course_id UUID REFERENCES courses(course_id) ON DELETE CASCADE,

    -- Enrollment details
    enrollment_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    enrollment_type VARCHAR(20) DEFAULT 'self' CHECK (enrollment_type IN ('self', 'invited', 'assigned', 'purchased')),
    enrollment_status VARCHAR(20) DEFAULT 'active' CHECK (enrollment_status IN ('active', 'completed', 'dropped', 'suspended')),

    -- Progress tracking
    progress_percentage DECIMAL(5,2) DEFAULT 0.00,
    completed_at TIMESTAMP WITH TIME ZONE,
    last_accessed_at TIMESTAMP WITH TIME ZONE,

    -- Completion and grading
    final_grade DECIMAL(5,2),
    certificate_issued BOOLEAN DEFAULT FALSE,
    certificate_url VARCHAR(500),

    -- Settings and preferences
    notification_preferences JSONB DEFAULT '{"email": true, "push": false}',
    completion_deadline DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id, course_id),
    CONSTRAINT chk_progress_range CHECK (progress_percentage BETWEEN 0 AND 100),
    CONSTRAINT chk_grade_range CHECK (final_grade IS NULL OR final_grade BETWEEN 0 AND 100)
);

-- Content progress tracking
CREATE TABLE content_progress (
    progress_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID REFERENCES enrollments(enrollment_id) ON DELETE CASCADE,
    content_id UUID REFERENCES content_items(content_id) ON DELETE CASCADE,

    -- Progress data
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMP WITH TIME ZONE,
    time_spent_seconds INTEGER DEFAULT 0,
    last_position_seconds INTEGER DEFAULT 0, -- For videos

    -- Quiz/Assignment results
    score DECIMAL(5,2),
    attempts_count INTEGER DEFAULT 0,
    last_attempt_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (enrollment_id, content_id),
    CONSTRAINT chk_score_range CHECK (score IS NULL OR score BETWEEN 0 AND 100)
);

-- Quiz attempts and answers
CREATE TABLE quiz_attempts (
    attempt_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID REFERENCES enrollments(enrollment_id) ON DELETE CASCADE,
    quiz_id UUID REFERENCES quizzes(quiz_id) ON DELETE CASCADE,
    attempt_number INTEGER NOT NULL,

    -- Attempt details
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    time_spent_seconds INTEGER,

    -- Results
    score DECIMAL(5,2),
    is_passed BOOLEAN,
    answers JSONB, -- Store user answers

    UNIQUE (enrollment_id, quiz_id, attempt_number),
    CONSTRAINT chk_attempt_score CHECK (score IS NULL OR score BETWEEN 0 AND 100)
);

-- ============================================
-- CERTIFICATES AND ACHIEVEMENTS
-- ============================================

-- Certificates
CREATE TABLE certificates (
    certificate_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID REFERENCES enrollments(enrollment_id) ON DELETE CASCADE,

    -- Certificate details
    certificate_number VARCHAR(50) UNIQUE NOT NULL,
    certificate_type VARCHAR(50) DEFAULT 'course_completion',
    title VARCHAR(300) NOT NULL,
    description TEXT,
    issued_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Issuer information
    issued_by UUID REFERENCES users(user_id),
    institution_id UUID REFERENCES institutions(institution_id),

    -- Verification
    verification_code VARCHAR(100) UNIQUE,
    qr_code_url VARCHAR(500),
    pdf_url VARCHAR(500),

    -- Metadata
    metadata JSONB DEFAULT '{}',
    is_revoked BOOLEAN DEFAULT FALSE,
    revoked_at TIMESTAMP WITH TIME ZONE,
    revocation_reason TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Achievements/Badges
CREATE TABLE achievements (
    achievement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT NOT NULL,
    icon_url VARCHAR(500),
    achievement_type VARCHAR(50) CHECK (achievement_type IN ('course_completion', 'streak', 'skill_mastery', 'social', 'milestone')),

    -- Criteria
    criteria JSONB NOT NULL, -- {"type": "courses_completed", "value": 5}
    points INTEGER DEFAULT 0,

    -- Visibility and availability
    is_active BOOLEAN DEFAULT TRUE,
    rarity VARCHAR(20) DEFAULT 'common' CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User achievements
CREATE TABLE user_achievements (
    user_achievement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    achievement_id UUID REFERENCES achievements(achievement_id) ON DELETE CASCADE,

    earned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    earned_through UUID, -- Could reference enrollment_id, course_id, etc.

    UNIQUE (user_id, achievement_id)
);

-- ============================================
-- DISCUSSION AND SOCIAL FEATURES
-- ============================================

-- Discussion threads
CREATE TABLE discussion_threads (
    thread_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(course_id) ON DELETE CASCADE,
    module_id UUID REFERENCES course_modules(module_id) ON DELETE SET NULL,
    content_id UUID REFERENCES content_items(content_id) ON DELETE SET NULL,

    -- Thread details
    title VARCHAR(300) NOT NULL,
    content TEXT NOT NULL,
    author_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    -- Thread metadata
    is_pinned BOOLEAN DEFAULT FALSE,
    is_locked BOOLEAN DEFAULT FALSE,
    view_count INTEGER DEFAULT 0,
    reply_count INTEGER DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', title || ' ' || content)
    ) STORED
);

-- Discussion replies
CREATE TABLE discussion_replies (
    reply_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID REFERENCES discussion_threads(thread_id) ON DELETE CASCADE,
    parent_reply_id UUID REFERENCES discussion_replies(reply_id) ON DELETE CASCADE, -- For nested replies
    author_id UUID REFERENCES users(user_id) ON DELETE CASCADE,

    content TEXT NOT NULL,
    is_solution BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', content)
    ) STORED
);

-- Thread/reply votes
CREATE TABLE discussion_votes (
    vote_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    thread_id UUID REFERENCES discussion_threads(thread_id) ON DELETE CASCADE,
    reply_id UUID REFERENCES discussion_replies(reply_id) ON DELETE CASCADE,
    vote_type VARCHAR(10) CHECK (vote_type IN ('up', 'down')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Ensure one vote per user per item
    UNIQUE (user_id, thread_id),
    UNIQUE (user_id, reply_id),

    -- Vote must be on either thread or reply, not both
    CONSTRAINT chk_vote_target CHECK (
        (thread_id IS NOT NULL AND reply_id IS NULL) OR
        (thread_id IS NULL AND reply_id IS NOT NULL)
    )
);

-- ============================================
-- ANALYTICS AND REPORTING
-- ============================================

-- Learning analytics
CREATE TABLE learning_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    course_id UUID REFERENCES courses(course_id) ON DELETE CASCADE,

    -- Time tracking
    total_time_spent_seconds INTEGER DEFAULT 0,
    sessions_count INTEGER DEFAULT 0,
    average_session_duration_seconds INTEGER,

    -- Progress metrics
    completion_percentage DECIMAL(5,2) DEFAULT 0.00,
    modules_completed INTEGER DEFAULT 0,
    quizzes_passed INTEGER DEFAULT 0,
    assignments_submitted INTEGER DEFAULT 0,

    -- Engagement metrics
    forum_posts_count INTEGER DEFAULT 0,
    forum_replies_count INTEGER DEFAULT 0,
    peers_helped_count INTEGER DEFAULT 0,

    -- Performance metrics
    average_quiz_score DECIMAL(5,2),
    current_streak_days INTEGER DEFAULT 0,
    longest_streak_days INTEGER DEFAULT 0,

    -- Last updated
    last_activity_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id, course_id)
);

-- Course analytics (aggregated data)
CREATE TABLE course_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(course_id) ON DELETE CASCADE,
    date DATE NOT NULL,

    -- Enrollment metrics
    new_enrollments INTEGER DEFAULT 0,
    total_enrollments INTEGER,
    active_learners INTEGER DEFAULT 0,

    -- Completion metrics
    completions_today INTEGER DEFAULT 0,
    total_completions INTEGER DEFAULT 0,
    completion_rate DECIMAL(5,2),

    -- Engagement metrics
    total_time_spent_seconds INTEGER DEFAULT 0,
    average_time_per_learner_seconds INTEGER,
    forum_activity_count INTEGER DEFAULT 0,

    -- Performance metrics
    average_quiz_score DECIMAL(5,2),
    average_completion_time_days DECIMAL(6,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (course_id, date)
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Core user indexes
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_active ON users (is_active) WHERE is_active = TRUE;
CREATE INDEX idx_users_created_at ON users (created_at);

-- Course indexes
CREATE INDEX idx_courses_category ON courses (category_id);
CREATE INDEX idx_courses_instructor ON courses (instructor_id);
CREATE INDEX idx_courses_status ON courses (status);
CREATE INDEX idx_courses_published_at ON courses (published_at);
CREATE INDEX idx_courses_search ON courses USING GIN (search_vector);

-- Enrollment indexes
CREATE INDEX idx_enrollments_user ON enrollments (user_id);
CREATE INDEX idx_enrollments_course ON enrollments (course_id);
CREATE INDEX idx_enrollments_status ON enrollments (enrollment_status);
CREATE INDEX idx_enrollments_progress ON enrollments (progress_percentage);

-- Content progress indexes
CREATE INDEX idx_content_progress_enrollment ON content_progress (enrollment_id);
CREATE INDEX idx_content_progress_content ON content_progress (content_id);
CREATE INDEX idx_content_progress_completed ON content_progress (is_completed) WHERE is_completed = TRUE;

-- Discussion indexes
CREATE INDEX idx_discussion_threads_course ON discussion_threads (course_id);
CREATE INDEX idx_discussion_replies_thread ON discussion_replies (thread_id);
CREATE INDEX idx_discussion_threads_search ON discussion_threads USING GIN (search_vector);
CREATE INDEX idx_discussion_replies_search ON discussion_replies USING GIN (search_vector);

-- Analytics indexes
CREATE INDEX idx_learning_analytics_user ON learning_analytics (user_id);
CREATE INDEX idx_learning_analytics_course ON learning_analytics (course_id);
CREATE INDEX idx_course_analytics_course_date ON course_analytics (course_id, date DESC);

-- ============================================
-- PARTITIONING FOR LARGE TABLES
-- ============================================

-- Partition enrollments by year
CREATE TABLE enrollments_y2024 PARTITION OF enrollments
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE enrollments_y2025 PARTITION OF enrollments
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- Partition course analytics by month
CREATE TABLE course_analytics PARTITION BY RANGE (date);

-- Create monthly partitions dynamically
DO $$
DECLARE
    partition_date DATE := '2024-01-01';
    partition_name TEXT;
BEGIN
    FOR i IN 0..23 LOOP  -- 2 years of monthly partitions
        partition_name := 'course_analytics_y' || TO_CHAR(partition_date, 'YYYY') || '_m' || TO_CHAR(partition_date, 'MM');
        EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF course_analytics FOR VALUES FROM (%L) TO (%L)',
            partition_name, partition_date, partition_date + INTERVAL '1 month');
        partition_date := partition_date + INTERVAL '1 month';
    END LOOP;
END $$;

-- ============================================
-- USEFUL VIEWS
-- ============================================

-- Course overview with enrollment stats
CREATE VIEW course_overview AS
SELECT
    c.course_id,
    c.title,
    c.subtitle,
    c.level,
    c.price,
    c.status,
    cat.name AS category_name,
    u.first_name || ' ' || u.last_name AS instructor_name,
    c.published_at,

    -- Enrollment stats
    COUNT(e.enrollment_id) AS total_enrollments,
    COUNT(CASE WHEN e.enrollment_status = 'active' THEN 1 END) AS active_enrollments,
    COUNT(CASE WHEN e.enrollment_status = 'completed' THEN 1 END) AS completed_enrollments,
    ROUND(AVG(e.progress_percentage), 2) AS avg_progress_percentage,
    ROUND(AVG(e.final_grade), 2) AS avg_final_grade,

    -- Course stats
    c.duration_hours,
    array_length(c.learning_objectives, 1) AS objectives_count,
    array_length(c.skills_covered, 1) AS skills_count

FROM courses c
LEFT JOIN course_categories cat ON c.category_id = cat.category_id
LEFT JOIN users u ON c.instructor_id = u.user_id
LEFT JOIN enrollments e ON c.course_id = e.course_id
GROUP BY c.course_id, c.title, c.subtitle, c.level, c.price, c.status,
         cat.name, u.first_name, u.last_name, c.published_at, c.duration_hours,
         c.learning_objectives, c.skills_covered;

-- Student progress dashboard
CREATE VIEW student_progress_dashboard AS
SELECT
    e.enrollment_id,
    e.user_id,
    u.first_name || ' ' || u.last_name AS student_name,
    c.course_id,
    c.title AS course_title,
    e.enrollment_date,
    e.progress_percentage,
    e.enrollment_status,
    e.final_grade,
    e.completed_at,

    -- Progress details
    COUNT(cp.content_id) AS total_items,
    COUNT(CASE WHEN cp.is_completed THEN 1 END) AS completed_items,
    SUM(cp.time_spent_seconds) AS total_time_spent_seconds,
    MAX(cp.completed_at) AS last_activity_date,

    -- Quiz performance
    ROUND(AVG(qa.score), 2) AS avg_quiz_score,
    COUNT(CASE WHEN qa.is_passed THEN 1 END) AS passed_quizzes,
    COUNT(qa.attempt_id) AS total_quiz_attempts

FROM enrollments e
JOIN users u ON e.user_id = u.user_id
JOIN courses c ON e.course_id = c.course_id
LEFT JOIN content_progress cp ON e.enrollment_id = cp.enrollment_id
LEFT JOIN quiz_attempts qa ON e.enrollment_id = qa.enrollment_id
GROUP BY e.enrollment_id, e.user_id, u.first_name, u.last_name,
         c.course_id, c.title, e.enrollment_date, e.progress_percentage,
         e.enrollment_status, e.final_grade, e.completed_at;

-- ============================================
-- USEFUL FUNCTIONS
-- ============================================

-- Function to calculate course progress
CREATE OR REPLACE FUNCTION calculate_course_progress(enrollment_uuid UUID)
RETURNS DECIMAL(5,2) AS $$
DECLARE
    total_items INTEGER;
    completed_items INTEGER;
    progress_percentage DECIMAL(5,2);
BEGIN
    SELECT COUNT(*), COUNT(CASE WHEN cp.is_completed THEN 1 END)
    INTO total_items, completed_items
    FROM enrollments e
    JOIN course_modules cm ON e.course_id = cm.course_id
    JOIN content_items ci ON cm.module_id = ci.module_id
    LEFT JOIN content_progress cp ON ci.content_id = cp.content_id AND cp.enrollment_id = e.enrollment_id
    WHERE e.enrollment_id = enrollment_uuid;

    IF total_items = 0 THEN
        progress_percentage := 0.00;
    ELSE
        progress_percentage := ROUND((completed_items::DECIMAL / total_items) * 100, 2);
    END IF;

    -- Update enrollment progress
    UPDATE enrollments
    SET progress_percentage = progress_percentage,
        updated_at = CURRENT_TIMESTAMP
    WHERE enrollment_id = enrollment_uuid;

    RETURN progress_percentage;
END;
$$ LANGUAGE plpgsql;

-- Function to issue certificates
CREATE OR REPLACE FUNCTION issue_certificate(enrollment_uuid UUID)
RETURNS UUID AS $$
DECLARE
    cert_id UUID;
    enrollment_record RECORD;
BEGIN
    -- Get enrollment details
    SELECT e.*, c.title, c.instructor_id, c.institution_id, u.first_name || ' ' || u.last_name AS student_name
    INTO enrollment_record
    FROM enrollments e
    JOIN courses c ON e.course_id = c.course_id
    JOIN users u ON e.user_id = u.user_id
    WHERE e.enrollment_id = enrollment_uuid
      AND e.enrollment_status = 'completed'
      AND e.final_grade >= 70; -- Minimum passing grade

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Enrollment not eligible for certificate';
    END IF;

    -- Generate certificate
    INSERT INTO certificates (
        enrollment_id,
        certificate_number,
        title,
        description,
        issued_by,
        institution_id,
        verification_code
    ) VALUES (
        enrollment_uuid,
        'CERT-' || UPPER(SUBSTRING(MD5(random()::text) FROM 1 FOR 8)),
        'Certificate of Completion: ' || enrollment_record.title,
        'This certifies that ' || enrollment_record.student_name || ' has successfully completed the course ' || enrollment_record.title,
        enrollment_record.instructor_id,
        enrollment_record.institution_id,
        encode(gen_random_bytes(16), 'hex')
    ) RETURNING certificate_id INTO cert_id;

    -- Update enrollment
    UPDATE enrollments
    SET certificate_issued = TRUE,
        updated_at = CURRENT_TIMESTAMP
    WHERE enrollment_id = enrollment_uuid;

    RETURN cert_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS FOR AUTOMATION
-- ============================================

-- Update course updated_at timestamp
CREATE OR REPLACE FUNCTION update_course_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE courses SET updated_at = CURRENT_TIMESTAMP WHERE course_id = NEW.course_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_course_updated_at
    AFTER INSERT OR UPDATE ON course_modules
    FOR EACH ROW EXECUTE FUNCTION update_course_updated_at();

CREATE TRIGGER trigger_update_course_updated_at_content
    AFTER INSERT OR UPDATE ON content_items
    FOR EACH ROW EXECUTE FUNCTION update_course_updated_at();

-- Auto-calculate progress when content is completed
CREATE OR REPLACE FUNCTION auto_calculate_progress()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_completed AND (OLD.is_completed IS NULL OR NOT OLD.is_completed) THEN
        PERFORM calculate_course_progress(NEW.enrollment_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_auto_calculate_progress
    AFTER INSERT OR UPDATE ON content_progress
    FOR EACH ROW EXECUTE FUNCTION auto_calculate_progress();

-- Update discussion thread reply counts
CREATE OR REPLACE FUNCTION update_thread_reply_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE discussion_threads
    SET reply_count = (
        SELECT COUNT(*) FROM discussion_replies WHERE thread_id = NEW.thread_id
    )
    WHERE thread_id = NEW.thread_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_reply_count
    AFTER INSERT OR DELETE ON discussion_replies
    FOR EACH ROW EXECUTE FUNCTION update_thread_reply_count();
