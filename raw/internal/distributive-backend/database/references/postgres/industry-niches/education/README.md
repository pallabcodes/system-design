# Educational Platform Schema Design

## Overview

This schema design provides a comprehensive foundation for an educational platform supporting online education, distance learning, and Learning Management System (LMS) functionality. The design supports multiple user types, course management, assessments, progress tracking, certifications, and analytics.

## Key Features

- **Multi-User Support**: Students, instructors, administrators, and moderators
- **Institution Management**: Support for schools, universities, and organizations
- **Comprehensive Course Management**: Modules, content items, quizzes, and assignments
- **Progress Tracking**: Detailed learning analytics and progress monitoring
- **Certification System**: Automated certificate generation and verification
- **Discussion Forums**: Social learning with threaded discussions
- **Advanced Analytics**: Learning metrics and reporting
- **Scalable Architecture**: Partitioning, indexing, and performance optimizations

## Database Architecture

### Core Entities

#### Users & Authentication
```sql
-- User management with role-based access control
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    -- ... additional fields
);

-- Role-based permissions
CREATE TABLE user_roles (
    user_id UUID REFERENCES users(user_id),
    role_id INTEGER REFERENCES roles(role_id),
    PRIMARY KEY (user_id, role_id)
);
```

#### Institution Management
```sql
-- Support for multiple institutions
CREATE TABLE institutions (
    institution_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    -- ... institution details
);

-- User-institution relationships
CREATE TABLE user_institutions (
    user_id UUID REFERENCES users(user_id),
    institution_id UUID REFERENCES institutions(institution_id),
    affiliation_type VARCHAR(50), -- student, faculty, staff, etc.
    -- ... affiliation details
);
```

### Course Management

#### Course Structure
```sql
-- Main course entity
CREATE TABLE courses (
    course_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(300) NOT NULL,
    description TEXT NOT NULL,
    instructor_id UUID REFERENCES users(user_id),
    category_id INTEGER REFERENCES course_categories(category_id),
    price DECIMAL(10,2) DEFAULT 0.00,
    status VARCHAR(20) DEFAULT 'draft',
    -- ... course metadata
);

-- Hierarchical course structure
CREATE TABLE course_modules (
    module_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(course_id),
    title VARCHAR(200) NOT NULL,
    display_order INTEGER NOT NULL,
    -- ... module details
);

-- Content items within modules
CREATE TABLE content_items (
    content_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id UUID REFERENCES course_modules(module_id),
    title VARCHAR(200) NOT NULL,
    content_type VARCHAR(50), -- video, text, quiz, assignment
    -- ... content details
);
```

#### Assessment System
```sql
-- Quiz management
CREATE TABLE quizzes (
    quiz_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL,
    passing_score_percentage DECIMAL(5,2),
    max_attempts INTEGER DEFAULT 1,
    -- ... quiz settings
);

-- Question management
CREATE TABLE quiz_questions (
    question_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID REFERENCES quizzes(quiz_id),
    question_text TEXT NOT NULL,
    question_type VARCHAR(20), -- multiple_choice, true_false, etc.
    options JSONB, -- For multiple choice questions
    -- ... question details
);
```

### Enrollment & Progress Tracking

#### Enrollment Management
```sql
-- Course enrollments
CREATE TABLE enrollments (
    enrollment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    course_id UUID REFERENCES courses(course_id),
    enrollment_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    progress_percentage DECIMAL(5,2) DEFAULT 0.00,
    final_grade DECIMAL(5,2),
    -- ... enrollment details
    UNIQUE (user_id, course_id)
);

-- Content progress tracking
CREATE TABLE content_progress (
    progress_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID REFERENCES enrollments(enrollment_id),
    content_id UUID REFERENCES content_items(content_id),
    is_completed BOOLEAN DEFAULT FALSE,
    time_spent_seconds INTEGER DEFAULT 0,
    -- ... progress details
    UNIQUE (enrollment_id, content_id)
);
```

#### Quiz Attempts
```sql
-- Track quiz attempts and results
CREATE TABLE quiz_attempts (
    attempt_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID REFERENCES enrollments(enrollment_id),
    quiz_id UUID REFERENCES quizzes(quiz_id),
    attempt_number INTEGER NOT NULL,
    score DECIMAL(5,2),
    is_passed BOOLEAN,
    answers JSONB, -- Store user answers
    -- ... attempt details
);
```

### Certification & Achievements

#### Certificate Management
```sql
-- Digital certificates
CREATE TABLE certificates (
    certificate_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID REFERENCES enrollments(enrollment_id),
    certificate_number VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(300) NOT NULL,
    verification_code VARCHAR(100) UNIQUE,
    -- ... certificate details
);

-- Achievement system
CREATE TABLE achievements (
    achievement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    criteria JSONB NOT NULL, -- Achievement requirements
    points INTEGER DEFAULT 0,
    -- ... achievement details
);
```

### Discussion & Social Features

#### Forum System
```sql
-- Discussion threads
CREATE TABLE discussion_threads (
    thread_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(course_id),
    title VARCHAR(300) NOT NULL,
    content TEXT NOT NULL,
    author_id UUID REFERENCES users(user_id),
    -- ... thread details
);

-- Threaded replies
CREATE TABLE discussion_replies (
    reply_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID REFERENCES discussion_threads(thread_id),
    parent_reply_id UUID REFERENCES discussion_replies(reply_id), -- Nested replies
    content TEXT NOT NULL,
    -- ... reply details
);

-- Voting system
CREATE TABLE discussion_votes (
    vote_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    thread_id UUID REFERENCES discussion_threads(thread_id),
    reply_id UUID REFERENCES discussion_replies(reply_id),
    vote_type VARCHAR(10), -- 'up', 'down'
    -- Constraints ensure one vote per user per item
    UNIQUE (user_id, thread_id),
    UNIQUE (user_id, reply_id)
);
```

## Advanced Features

### Full-Text Search

```sql
-- Courses with full-text search
ALTER TABLE courses
ADD COLUMN search_vector TSVECTOR
GENERATED ALWAYS AS (
    to_tsvector('english',
        title || ' ' || subtitle || ' ' ||
        description || ' ' || array_to_string(skills_covered, ' ')
    )
) STORED;

CREATE INDEX idx_courses_search ON courses USING GIN (search_vector);

-- Search courses
SELECT course_id, title, ts_rank(search_vector, query) AS relevance
FROM courses, to_tsquery('english', 'database performance') query
WHERE search_vector @@ query
ORDER BY relevance DESC;
```

### Analytics & Reporting

```sql
-- Learning analytics
CREATE TABLE learning_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    course_id UUID REFERENCES courses(course_id),
    total_time_spent_seconds INTEGER DEFAULT 0,
    completion_percentage DECIMAL(5,2) DEFAULT 0.00,
    average_quiz_score DECIMAL(5,2),
    -- ... detailed metrics
    UNIQUE (user_id, course_id)
);

-- Course analytics (aggregated)
CREATE TABLE course_analytics (
    analytics_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(course_id),
    date DATE NOT NULL,
    new_enrollments INTEGER DEFAULT 0,
    active_learners INTEGER DEFAULT 0,
    completion_rate DECIMAL(5,2),
    -- ... aggregated metrics
    UNIQUE (course_id, date)
);
```

### Partitioning Strategy

```sql
-- Partition enrollments by year for performance
CREATE TABLE enrollments PARTITION BY RANGE (enrollment_date);

CREATE TABLE enrollments_y2024 PARTITION OF enrollments
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE enrollments_y2025 PARTITION OF enrollments
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- Partition analytics by month
CREATE TABLE course_analytics PARTITION BY RANGE (date);
```

## Usage Examples

### Course Enrollment Process

```sql
-- Enroll a student in a course
INSERT INTO enrollments (user_id, course_id, enrollment_type)
VALUES ('student-uuid', 'course-uuid', 'self');

-- Mark content as completed
INSERT INTO content_progress (enrollment_id, content_id, is_completed, time_spent_seconds)
VALUES ('enrollment-uuid', 'content-uuid', TRUE, 1800);

-- Auto-calculate progress (trigger-based)
SELECT calculate_course_progress('enrollment-uuid');
```

### Quiz Attempt Flow

```sql
-- Start a quiz attempt
INSERT INTO quiz_attempts (enrollment_id, quiz_id, attempt_number)
VALUES ('enrollment-uuid', 'quiz-uuid', 1);

-- Submit answers
UPDATE quiz_attempts
SET completed_at = CURRENT_TIMESTAMP,
    answers = '{"q1": "A", "q2": "B", "q3": "C"}'::jsonb,
    score = 85.5,
    is_passed = TRUE
WHERE attempt_id = 'attempt-uuid';
```

### Certificate Issuance

```sql
-- Issue certificate for completed course
SELECT issue_certificate('enrollment-uuid') AS certificate_id;

-- Verify certificate
SELECT c.*, e.final_grade, co.title AS course_title
FROM certificates c
JOIN enrollments e ON c.enrollment_id = e.enrollment_id
JOIN courses co ON e.course_id = co.course_id
WHERE c.verification_code = 'user-provided-code';
```

## Useful Views

### Course Overview Dashboard

```sql
CREATE VIEW course_overview AS
SELECT
    c.course_id,
    c.title,
    c.level,
    c.price,
    cat.name AS category_name,
    u.first_name || ' ' || u.last_name AS instructor_name,

    -- Enrollment statistics
    COUNT(e.enrollment_id) AS total_enrollments,
    COUNT(CASE WHEN e.enrollment_status = 'active' THEN 1 END) AS active_enrollments,
    ROUND(AVG(e.progress_percentage), 2) AS avg_progress_percentage,
    ROUND(AVG(e.final_grade), 2) AS avg_final_grade

FROM courses c
LEFT JOIN course_categories cat ON c.category_id = cat.category_id
LEFT JOIN users u ON c.instructor_id = u.user_id
LEFT JOIN enrollments e ON c.course_id = e.course_id
GROUP BY c.course_id, c.title, c.level, c.price, cat.name, u.first_name, u.last_name;
```

### Student Progress Dashboard

```sql
CREATE VIEW student_progress_dashboard AS
SELECT
    e.enrollment_id,
    e.user_id,
    u.first_name || ' ' || u.last_name AS student_name,
    c.title AS course_title,
    e.progress_percentage,
    e.final_grade,

    -- Detailed progress
    COUNT(cp.content_id) AS total_items,
    COUNT(CASE WHEN cp.is_completed THEN 1 END) AS completed_items,
    ROUND(AVG(qa.score), 2) AS avg_quiz_score

FROM enrollments e
JOIN users u ON e.user_id = u.user_id
JOIN courses c ON e.course_id = c.course_id
LEFT JOIN content_progress cp ON e.enrollment_id = cp.enrollment_id
LEFT JOIN quiz_attempts qa ON e.enrollment_id = qa.enrollment_id
GROUP BY e.enrollment_id, e.user_id, u.first_name, u.last_name, c.title, e.progress_percentage, e.final_grade;
```

## Performance Optimizations

### Key Indexes

```sql
-- Core performance indexes
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_enrollments_user_course ON enrollments (user_id, course_id);
CREATE INDEX idx_content_progress_enrollment ON content_progress (enrollment_id);
CREATE INDEX idx_course_analytics_course_date ON course_analytics (course_id, date DESC);

-- Full-text search indexes
CREATE INDEX idx_courses_search ON courses USING GIN (search_vector);
CREATE INDEX idx_discussions_search ON discussion_threads USING GIN (search_vector);
```

### Query Optimization Examples

```sql
-- Optimized enrollment query with covering index
SELECT user_id, course_id, progress_percentage, enrollment_status
FROM enrollments
WHERE user_id = $1 AND enrollment_status = 'active'
ORDER BY enrollment_date DESC;

-- Efficient progress calculation
WITH course_content AS (
    SELECT course_id, COUNT(*) AS total_items
    FROM course_modules cm
    JOIN content_items ci ON cm.module_id = ci.module_id
    GROUP BY course_id
),
user_progress AS (
    SELECT e.course_id, COUNT(cp.content_id) AS completed_items
    FROM enrollments e
    LEFT JOIN content_progress cp ON e.enrollment_id = cp.enrollment_id AND cp.is_completed = TRUE
    WHERE e.user_id = $1
    GROUP BY e.course_id
)
SELECT
    c.course_id,
    c.title,
    ROUND((up.completed_items::DECIMAL / cc.total_items) * 100, 2) AS progress_percentage
FROM courses c
JOIN course_content cc ON c.course_id = cc.course_id
LEFT JOIN user_progress up ON c.course_id = up.course_id
WHERE c.status = 'published';
```

## Security Considerations

### Row Level Security (RLS)

```sql
-- Enable RLS on sensitive tables
ALTER TABLE enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE certificates ENABLE ROW LEVEL SECURITY;

-- Students can only see their own enrollments
CREATE POLICY student_enrollment_policy ON enrollments
    FOR ALL USING (user_id = current_user_id());

-- Instructors can see enrollments for their courses
CREATE POLICY instructor_enrollment_policy ON enrollments
    FOR SELECT USING (
        course_id IN (
            SELECT course_id FROM courses WHERE instructor_id = current_user_id()
        )
    );
```

### Data Encryption

```sql
-- Encrypt sensitive data
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Store encrypted certificates
CREATE TABLE certificate_keys (
    certificate_id UUID PRIMARY KEY REFERENCES certificates(certificate_id),
    encrypted_pdf BYTEA,
    encryption_key_hash VARCHAR(128),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

## Monitoring & Maintenance

### Key Metrics to Monitor

- **Enrollment Growth**: Daily/weekly enrollment rates
- **Course Completion Rates**: Percentage of students completing courses
- **Average Session Duration**: Time spent per learning session
- **Quiz Performance**: Average scores and pass rates
- **Forum Activity**: Posts and engagement rates
- **Certificate Issuance**: Completion and certification rates

### Maintenance Tasks

```sql
-- Archive old data
CREATE TABLE archived_enrollments (LIKE enrollments INCLUDING ALL);
INSERT INTO archived_enrollments
SELECT * FROM enrollments
WHERE enrollment_date < CURRENT_DATE - INTERVAL '2 years';

DELETE FROM enrollments WHERE enrollment_date < CURRENT_DATE - INTERVAL '2 years';

-- Update analytics
REFRESH MATERIALIZED VIEW CONCURRENTLY course_completion_stats;

-- Reindex for performance
REINDEX INDEX CONCURRENTLY idx_content_progress_enrollment;
```

## Integration Points

### External Systems
- **Learning Management Systems** (LMS) like Canvas, Moodle, Blackboard for course delivery
- **Video conferencing platforms** (Zoom, Microsoft Teams) for live sessions
- **Assessment engines** for automated testing and grading
- **Payment processors** (Stripe, PayPal) for course monetization
- **Content delivery networks** (Cloudflare, Akamai) for media streaming
- **Student information systems** for enrollment and transcript management
- **Certification authorities** for credential verification

### API Endpoints
- **Course management APIs** for content creation and delivery
- **Enrollment APIs** for student registration and access control
- **Progress tracking APIs** for learning analytics and reporting
- **Assessment APIs** for quiz administration and grading
- **Certification APIs** for credential issuance and verification

## Monitoring & Analytics

### Key Performance Indicators
- **Course completion rates** and student retention metrics
- **Assessment performance** and learning outcome measurements
- **Platform engagement** with time spent and activity levels
- **Revenue metrics** for course sales and subscription models
- **Student satisfaction** and Net Promoter Scores

### Real-Time Dashboards
```sql
-- Education platform analytics dashboard
CREATE VIEW education_analytics_dashboard AS
SELECT
    -- Enrollment metrics (current month)
    (SELECT COUNT(*) FROM enrollments WHERE DATE(enrollment_date) >= DATE_TRUNC('month', CURRENT_DATE)) as enrollments_this_month,
    (SELECT COUNT(*) FROM enrollments WHERE enrollment_status = 'active') as active_enrollments,
    (SELECT AVG(progress_percentage) FROM course_progress WHERE last_accessed >= CURRENT_DATE - INTERVAL '30 days') as avg_course_progress,

    -- Course performance
    (SELECT COUNT(*) FROM courses WHERE course_status = 'published') as published_courses,
    (SELECT AVG(rating) FROM course_reviews WHERE created_at >= CURRENT_DATE - INTERVAL '90 days') as avg_course_rating,
    (SELECT COUNT(*) FROM course_completions WHERE completion_date >= CURRENT_DATE - INTERVAL '30 days') as completions_this_month,

    -- Student engagement
    (SELECT COUNT(DISTINCT student_id) FROM course_progress WHERE last_accessed >= CURRENT_DATE - INTERVAL '7 days') as active_students_week,
    (SELECT AVG(duration_minutes) FROM learning_sessions WHERE session_date >= CURRENT_DATE - INTERVAL '7 days') as avg_session_duration,
    (SELECT COUNT(*) FROM forum_posts WHERE created_at >= CURRENT_DATE - INTERVAL '7 days') as forum_activity_week,

    -- Assessment metrics
    (SELECT AVG(score_percentage) FROM quiz_attempts WHERE attempt_date >= CURRENT_DATE - INTERVAL '30 days') as avg_quiz_score,
    (SELECT COUNT(*) FROM certificates WHERE issued_date >= CURRENT_DATE - INTERVAL '30 days') as certificates_issued_month,

    -- Platform health
    (SELECT COUNT(*) FROM support_tickets WHERE ticket_status = 'open') as open_support_tickets,
    (SELECT AVG(EXTRACT(EPOCH FROM (resolved_at - created_at))/3600)
     FROM support_tickets WHERE resolved_at IS NOT NULL AND created_at >= CURRENT_DATE - INTERVAL '30 days') as avg_resolution_time_hours,

    -- Financial metrics (if applicable)
    (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE payment_date >= CURRENT_DATE - INTERVAL '30 days') as revenue_this_month,
    (SELECT COUNT(*) FROM course_purchases WHERE purchase_date >= CURRENT_DATE - INTERVAL '30 days') as course_sales_month

FROM dual; -- Use a dummy table for single-row result
```

This schema provides a solid foundation for building a comprehensive educational platform. The design supports scalability, performance, and extensibility while maintaining data integrity and providing rich analytics capabilities.
