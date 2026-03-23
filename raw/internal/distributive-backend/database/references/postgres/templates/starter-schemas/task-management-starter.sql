-- Task/Project Management Platform Starter Schema
-- Complete schema for task management, project tracking, and team collaboration

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text search

-- ===========================================
-- USERS AND TEAMS
-- ===========================================

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(200) NOT NULL,
    avatar_url VARCHAR(500),
    timezone VARCHAR(50) DEFAULT 'UTC',
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE teams (
    team_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    team_name VARCHAR(100) NOT NULL,
    team_description TEXT,
    team_type VARCHAR(20) DEFAULT 'project_team' CHECK (team_type IN ('project_team', 'department', 'company', 'external')),
    avatar_url VARCHAR(500),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE team_members (
    team_member_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    team_id UUID NOT NULL REFERENCES teams(team_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    role VARCHAR(30) DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'manager', 'member', 'viewer')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    invited_by UUID REFERENCES users(user_id),
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE (team_id, user_id)
);

-- ===========================================
-- PROJECTS AND WORKSPACES
-- ===========================================

CREATE TABLE workspaces (
    workspace_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_name VARCHAR(100) NOT NULL,
    workspace_description TEXT,
    workspace_type VARCHAR(20) DEFAULT 'team' CHECK (workspace_type IN ('personal', 'team', 'organization')),
    owner_id UUID NOT NULL REFERENCES users(user_id),
    team_id UUID REFERENCES teams(team_id),

    -- Settings
    is_private BOOLEAN DEFAULT FALSE,
    allow_guest_access BOOLEAN DEFAULT FALSE,
    default_view VARCHAR(20) DEFAULT 'list' CHECK (default_view IN ('list', 'board', 'calendar', 'timeline')),

    -- Features
    features_enabled JSONB DEFAULT '{"time_tracking": true, "file_attachments": true, "comments": true}',

    -- Limits
    member_limit INTEGER DEFAULT 10,
    storage_limit_mb INTEGER DEFAULT 100,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE projects (
    project_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id UUID NOT NULL REFERENCES workspaces(workspace_id) ON DELETE CASCADE,

    -- Project Details
    project_name VARCHAR(255) NOT NULL,
    project_key VARCHAR(10) UNIQUE NOT NULL,  -- e.g., 'PROJ', 'WEBSITE'
    project_description TEXT,

    -- Project Settings
    project_status VARCHAR(20) DEFAULT 'planning' CHECK (project_status IN ('planning', 'active', 'on_hold', 'completed', 'cancelled')),
    project_priority VARCHAR(10) DEFAULT 'medium' CHECK (project_priority IN ('lowest', 'low', 'medium', 'high', 'highest')),

    -- Timeline
    start_date DATE,
    end_date DATE,
    estimated_hours DECIMAL(8,2),
    actual_hours DECIMAL(8,2),

    -- Progress Tracking
    progress_percentage DECIMAL(5,2) DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),
    completed_tasks INTEGER DEFAULT 0,
    total_tasks INTEGER DEFAULT 0,

    -- Budget and Cost
    budget DECIMAL(12,2),
    actual_cost DECIMAL(12,2),

    -- Team and Access
    project_lead_id UUID REFERENCES users(user_id),
    team_members UUID[] DEFAULT '{}',  -- Array of user_ids

    -- Project Template
    template_id UUID,  -- For project templates

    -- Custom Fields
    custom_fields JSONB DEFAULT '{}',

    -- Metadata
    color VARCHAR(7),  -- Hex color for UI
    icon VARCHAR(50),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL REFERENCES users(user_id),
    updated_by UUID REFERENCES users(user_id)
);

-- ===========================================
-- TASKS AND SUBTASKS
-- ===========================================

CREATE TABLE task_lists (
    list_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    list_name VARCHAR(255) NOT NULL,
    list_description TEXT,
    list_color VARCHAR(7),
    sort_order INTEGER DEFAULT 0,
    is_done_list BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tasks (
    task_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    list_id UUID REFERENCES task_lists(list_id),

    -- Task Details
    task_title VARCHAR(500) NOT NULL,
    task_description TEXT,
    task_key VARCHAR(20),  -- e.g., 'PROJ-123'

    -- Status and Priority
    task_status VARCHAR(30) DEFAULT 'todo' CHECK (task_status IN ('todo', 'in_progress', 'review', 'done', 'cancelled')),
    task_priority VARCHAR(10) DEFAULT 'medium' CHECK (task_priority IN ('lowest', 'low', 'medium', 'high', 'highest', 'urgent')),

    -- Assignment
    assigned_to UUID REFERENCES users(user_id),
    assigned_by UUID REFERENCES users(user_id),
    assigned_at TIMESTAMP WITH TIME ZONE,

    -- Reporter
    reported_by UUID NOT NULL REFERENCES users(user_id),
    reported_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Scheduling
    start_date DATE,
    due_date DATE,
    estimated_hours DECIMAL(6,2),
    actual_hours DECIMAL(6,2),

    -- Progress
    progress_percentage DECIMAL(5,2) DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Labels and Categories
    labels TEXT[],
    category VARCHAR(50),

    -- Dependencies
    depends_on UUID[],     -- Array of task_ids this task depends on
    blocks UUID[],         -- Array of task_ids this task blocks

    -- Recurring Tasks
    is_recurring BOOLEAN DEFAULT FALSE,
    recurrence_rule TEXT,  -- iCal RRULE format
    parent_task_id UUID REFERENCES tasks(task_id),  -- For recurring task instances

    -- Custom Fields
    custom_fields JSONB DEFAULT '{}',

    -- Position in list/board
    sort_order INTEGER DEFAULT 0,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL REFERENCES users(user_id),
    updated_by UUID REFERENCES users(user_id)
);

CREATE TABLE subtasks (
    subtask_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,

    -- Subtask Details
    subtask_title VARCHAR(300) NOT NULL,
    subtask_description TEXT,
    is_completed BOOLEAN DEFAULT FALSE,

    -- Assignment
    assigned_to UUID REFERENCES users(user_id),

    -- Scheduling
    due_date DATE,

    -- Position
    sort_order INTEGER DEFAULT 0,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE
);

-- ===========================================
-- TIME TRACKING
-- ===========================================

CREATE TABLE time_entries (
    time_entry_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    task_id UUID REFERENCES tasks(task_id),
    project_id UUID REFERENCES projects(project_id),

    -- Time Details
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (end_time - start_time)) / 60
    ) STORED,

    -- Description
    description TEXT,
    is_billable BOOLEAN DEFAULT TRUE,

    -- Status
    time_entry_status VARCHAR(20) DEFAULT 'active' CHECK (time_entry_status IN ('active', 'paused', 'completed', 'deleted')),

    -- Manual Entry
    is_manual_entry BOOLEAN DEFAULT FALSE,
    manual_entry_reason TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL REFERENCES users(user_id)
);

-- ===========================================
-- COMMENTS AND COLLABORATION
-- ===========================================

CREATE TABLE comments (
    comment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(user_id),

    -- Comment Content
    comment_text TEXT NOT NULL,
    is_edited BOOLEAN DEFAULT FALSE,
    edited_at TIMESTAMP WITH TIME ZONE,

    -- Threading (for replies)
    parent_comment_id UUID REFERENCES comments(comment_id),
    thread_level INTEGER DEFAULT 0,

    -- Attachments
    attachments JSONB DEFAULT '[]',  -- Array of file references

    -- Reactions
    reactions JSONB DEFAULT '{}',  -- {"thumbs_up": ["user_id1", "user_id2"], "heart": ["user_id3"]}

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- FILE ATTACHMENTS AND ASSETS
-- ===========================================

CREATE TABLE attachments (
    attachment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID REFERENCES tasks(task_id) ON DELETE CASCADE,
    project_id UUID REFERENCES projects(project_id) ON DELETE CASCADE,
    comment_id UUID REFERENCES comments(comment_id) ON DELETE CASCADE,

    -- File Information
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,

    -- Upload Information
    uploaded_by UUID NOT NULL REFERENCES users(user_id),
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- File Metadata
    file_metadata JSONB DEFAULT '{}',  -- Dimensions, EXIF data, etc.

    -- Access Control
    is_public BOOLEAN DEFAULT FALSE,
    allowed_users UUID[] DEFAULT '{}',

    -- Versioning
    version_number INTEGER DEFAULT 1,
    parent_attachment_id UUID REFERENCES attachments(attachment_id)
);

-- ===========================================
-- ACTIVITY LOGGING AND AUDIT
-- ===========================================

CREATE TABLE activity_log (
    activity_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    workspace_id UUID REFERENCES workspaces(workspace_id),
    project_id UUID REFERENCES projects(project_id),
    task_id UUID REFERENCES tasks(task_id),

    -- Activity Details
    activity_type VARCHAR(50) NOT NULL,
    activity_description TEXT NOT NULL,
    old_value JSONB,
    new_value JSONB,

    -- Context
    ip_address INET,
    user_agent TEXT,
    session_id VARCHAR(255),

    -- Visibility
    is_visible_to_team BOOLEAN DEFAULT TRUE,

    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (created_at);

-- ===========================================
-- NOTIFICATIONS
-- ===========================================

CREATE TABLE notifications (
    notification_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id),

    -- Notification Content
    notification_type VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    action_url VARCHAR(500),

    -- Related Objects
    project_id UUID REFERENCES projects(project_id),
    task_id UUID REFERENCES tasks(task_id),
    comment_id UUID REFERENCES comments(comment_id),

    -- Delivery Status
    email_sent BOOLEAN DEFAULT FALSE,
    email_sent_at TIMESTAMP WITH TIME ZONE,
    in_app_read BOOLEAN DEFAULT FALSE,
    in_app_read_at TIMESTAMP WITH TIME ZONE,
    push_sent BOOLEAN DEFAULT FALSE,
    push_sent_at TIMESTAMP WITH TIME ZONE,

    -- Priority and Expiry
    priority VARCHAR(10) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 days'),

    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INTEGRATIONS AND WEBHOOKS
-- ===========================================

CREATE TABLE webhooks (
    webhook_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id UUID NOT NULL REFERENCES workspaces(workspace_id) ON DELETE CASCADE,

    -- Webhook Configuration
    webhook_name VARCHAR(100) NOT NULL,
    webhook_url VARCHAR(500) NOT NULL,
    webhook_secret VARCHAR(100),  -- For signature verification

    -- Events to Trigger
    events TEXT[] DEFAULT '{}',  -- Array of event types to trigger

    -- Status and Health
    is_active BOOLEAN DEFAULT TRUE,
    last_triggered_at TIMESTAMP WITH TIME ZONE,
    last_success_at TIMESTAMP WITH TIME ZONE,
    failure_count INTEGER DEFAULT 0,

    -- Rate Limiting
    rate_limit_per_minute INTEGER DEFAULT 60,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL REFERENCES users(user_id)
);

CREATE TABLE webhook_deliveries (
    delivery_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    webhook_id UUID NOT NULL REFERENCES webhooks(webhook_id) ON DELETE CASCADE,

    -- Delivery Details
    event_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    response_status INTEGER,
    response_body TEXT,

    -- Timing
    delivered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    response_time_ms INTEGER,

    -- Status
    delivery_status VARCHAR(20) DEFAULT 'success' CHECK (delivery_status IN ('success', 'failed', 'timeout', 'rate_limited')),

    -- Error Information
    error_message TEXT
);

-- ===========================================
-- SEARCH AND INDEXING
-- ===========================================

-- Full-text search setup
CREATE INDEX idx_tasks_search ON tasks USING gin (
    to_tsvector('english', COALESCE(task_title, '') || ' ' || COALESCE(task_description, ''))
);

CREATE INDEX idx_comments_search ON comments USING gin (
    to_tsvector('english', comment_text)
);

CREATE INDEX idx_projects_search ON projects USING gin (
    to_tsvector('english', COALESCE(project_name, '') || ' ' || COALESCE(project_description, ''))
);

-- Fuzzy search indexes
CREATE INDEX idx_users_name_trgm ON users USING gin (full_name gin_trgm_ops);
CREATE INDEX idx_tasks_title_trgm ON tasks USING gin (task_title gin_trgm_ops);
CREATE INDEX idx_projects_name_trgm ON projects USING gin (project_name gin_trgm_ops);

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- User indexes
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_active ON users (is_active);
CREATE INDEX idx_users_created ON users (created_at DESC);

-- Team indexes
CREATE INDEX idx_team_members_team ON team_members (team_id);
CREATE INDEX idx_team_members_user ON team_members (user_id);

-- Workspace indexes
CREATE INDEX idx_workspaces_owner ON workspaces (owner_id);
CREATE INDEX idx_workspaces_team ON workspaces (team_id);

-- Project indexes
CREATE INDEX idx_projects_workspace ON projects (workspace_id);
CREATE INDEX idx_projects_status ON projects (project_status);
CREATE INDEX idx_projects_lead ON projects (project_lead_id);
CREATE INDEX idx_projects_dates ON projects (start_date, end_date);

-- Task indexes
CREATE INDEX idx_tasks_project ON tasks (project_id);
CREATE INDEX idx_tasks_assigned_to ON tasks (assigned_to);
CREATE INDEX idx_tasks_status ON tasks (task_status);
CREATE INDEX idx_tasks_due_date ON tasks (due_date);
CREATE INDEX idx_tasks_created ON tasks (created_at DESC);
CREATE INDEX idx_tasks_list ON tasks (list_id, sort_order);

-- Time tracking indexes
CREATE INDEX idx_time_entries_user ON time_entries (user_id);
CREATE INDEX idx_time_entries_task ON time_entries (task_id);
CREATE INDEX idx_time_entries_project ON time_entries (project_id);
CREATE INDEX idx_time_entries_start_time ON time_entries (start_time DESC);

-- Comment indexes
CREATE INDEX idx_comments_task ON comments (task_id);
CREATE INDEX idx_comments_author ON comments (author_id);
CREATE INDEX idx_comments_parent ON comments (parent_comment_id);
CREATE INDEX idx_comments_created ON comments (created_at DESC);

-- Attachment indexes
CREATE INDEX idx_attachments_task ON attachments (task_id);
CREATE INDEX idx_attachments_project ON attachments (project_id);
CREATE INDEX idx_attachments_comment ON attachments (comment_id);
CREATE INDEX idx_attachments_uploaded_by ON attachments (uploaded_by);

-- Activity log indexes
CREATE INDEX idx_activity_log_user ON activity_log (user_id);
CREATE INDEX idx_activity_log_project ON activity_log (project_id);
CREATE INDEX idx_activity_log_task ON activity_log (task_id);
CREATE INDEX idx_activity_log_created ON activity_log (created_at DESC);

-- Notification indexes
CREATE INDEX idx_notifications_user ON notifications (user_id);
CREATE INDEX idx_notifications_created ON notifications (created_at DESC);
CREATE INDEX idx_notifications_read ON notifications (in_app_read, created_at DESC);

-- ===========================================
-- PARTITIONING SETUP
-- ===========================================

-- Activity log partitioning (monthly)
CREATE TABLE activity_log_2024_01 PARTITION OF activity_log
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE activity_log_2024_02 PARTITION OF activity_log
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- Task overview with project and assignee information
CREATE VIEW task_overview AS
SELECT
    t.task_id,
    t.task_key,
    t.task_title,
    t.task_status,
    t.task_priority,
    t.due_date,
    t.progress_percentage,
    p.project_name,
    p.project_key,
    u_assigned.full_name as assigned_to_name,
    u_reporter.full_name as reported_by_name,
    tl.list_name,
    COUNT(st.subtask_id) as subtask_count,
    COUNT(CASE WHEN st.is_completed THEN 1 END) as completed_subtasks,
    COUNT(c.comment_id) as comment_count,
    t.created_at,
    t.updated_at
FROM tasks t
JOIN projects p ON t.project_id = p.project_id
LEFT JOIN users u_assigned ON t.assigned_to = u_assigned.user_id
LEFT JOIN users u_reporter ON t.reported_by = u_reporter.user_id
LEFT JOIN task_lists tl ON t.list_id = tl.list_id
LEFT JOIN subtasks st ON t.task_id = st.task_id
LEFT JOIN comments c ON t.task_id = c.task_id
GROUP BY t.task_id, t.task_key, t.task_title, t.task_status, t.task_priority,
         t.due_date, t.progress_percentage, p.project_name, p.project_key,
         u_assigned.full_name, u_reporter.full_name, tl.list_name,
         t.created_at, t.updated_at;

-- Project dashboard view
CREATE VIEW project_dashboard AS
SELECT
    p.project_id,
    p.project_name,
    p.project_key,
    p.project_status,
    p.progress_percentage,
    p.start_date,
    p.end_date,

    -- Task counts
    COUNT(t.task_id) as total_tasks,
    COUNT(CASE WHEN t.task_status = 'done' THEN 1 END) as completed_tasks,
    COUNT(CASE WHEN t.task_status = 'in_progress' THEN 1 END) as in_progress_tasks,
    COUNT(CASE WHEN t.due_date < CURRENT_DATE AND t.task_status != 'done' THEN 1 END) as overdue_tasks,

    -- Team information
    COUNT(DISTINCT tm.user_id) as team_members,
    u_lead.full_name as project_lead_name,

    -- Time tracking
    COALESCE(SUM(te.duration_minutes), 0) as total_time_logged,
    COALESCE(AVG(te.duration_minutes), 0) as avg_task_time,

    -- Budget information
    p.budget,
    p.actual_cost,
    p.budget - COALESCE(p.actual_cost, 0) as budget_remaining

FROM projects p
LEFT JOIN tasks t ON p.project_id = t.project_id
LEFT JOIN team_members tm ON p.workspace_id = tm.team_id
LEFT JOIN users u_lead ON p.project_lead_id = u_lead.user_id
LEFT JOIN time_entries te ON p.project_id = te.project_id
GROUP BY p.project_id, p.project_name, p.project_key, p.project_status,
         p.progress_percentage, p.start_date, p.end_date, p.budget,
         p.actual_cost, u_lead.full_name;

-- User workload view
CREATE VIEW user_workload AS
SELECT
    u.user_id,
    u.full_name,
    u.email,

    -- Current assignments
    COUNT(CASE WHEN t.task_status IN ('todo', 'in_progress') THEN 1 END) as active_tasks,
    COUNT(CASE WHEN t.due_date < CURRENT_DATE AND t.task_status != 'done' THEN 1 END) as overdue_tasks,
    COUNT(CASE WHEN t.due_date = CURRENT_DATE AND t.task_status != 'done' THEN 1 END) as due_today,

    -- Time tracking (this week)
    COALESCE(SUM(CASE WHEN te.start_time >= date_trunc('week', CURRENT_DATE) THEN te.duration_minutes END), 0) as time_this_week,
    COALESCE(AVG(te.duration_minutes), 0) as avg_session_length,

    -- Project involvement
    COUNT(DISTINCT t.project_id) as active_projects,
    COUNT(DISTINCT tm.team_id) as teams_count

FROM users u
LEFT JOIN tasks t ON u.user_id = t.assigned_to
LEFT JOIN time_entries te ON u.user_id = te.user_id
LEFT JOIN team_members tm ON u.user_id = tm.user_id AND tm.is_active = TRUE
WHERE u.is_active = TRUE
GROUP BY u.user_id, u.full_name, u.email;

-- ===========================================
-- FUNCTIONS
-- =========================================--

-- Function to calculate project progress
CREATE OR REPLACE FUNCTION calculate_project_progress(project_id_param UUID)
RETURNS DECIMAL(5,2) AS $$
DECLARE
    total_tasks INTEGER;
    completed_tasks INTEGER;
BEGIN
    SELECT
        COUNT(*) as total,
        COUNT(CASE WHEN task_status = 'done' THEN 1 END) as completed
    INTO total_tasks, completed_tasks
    FROM tasks
    WHERE project_id = project_id_param;

    IF total_tasks = 0 THEN
        RETURN 0;
    END IF;

    RETURN (completed_tasks::DECIMAL / total_tasks) * 100;
END;
$$ LANGUAGE plpgsql;

-- Function to update task progress based on subtasks
CREATE OR REPLACE FUNCTION update_task_progress_from_subtasks()
RETURNS TRIGGER AS $$
DECLARE
    task_id_val UUID;
    total_subtasks INTEGER;
    completed_subtasks INTEGER;
    new_progress DECIMAL(5,2);
BEGIN
    -- Get the task ID
    task_id_val := CASE
        WHEN TG_OP = 'DELETE' THEN OLD.task_id
        ELSE NEW.task_id
    END;

    -- Calculate progress from subtasks
    SELECT
        COUNT(*) as total,
        COUNT(CASE WHEN is_completed THEN 1 END) as completed
    INTO total_subtasks, completed_subtasks
    FROM subtasks
    WHERE task_id = task_id_val;

    -- Calculate new progress
    IF total_subtasks = 0 THEN
        new_progress := 0;
    ELSE
        new_progress := (completed_subtasks::DECIMAL / total_subtasks) * 100;
    END IF;

    -- Update task progress
    UPDATE tasks
    SET progress_percentage = new_progress,
        updated_at = CURRENT_TIMESTAMP
    WHERE task_id = task_id_val;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Function to create task activity log
CREATE OR REPLACE FUNCTION log_task_activity()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO activity_log (
        user_id, project_id, task_id, activity_type, activity_description,
        old_value, new_value
    )
    SELECT
        COALESCE(NEW.updated_by, NEW.created_by),
        NEW.project_id,
        NEW.task_id,
        CASE
            WHEN TG_OP = 'INSERT' THEN 'task_created'
            WHEN TG_OP = 'UPDATE' THEN 'task_updated'
            WHEN TG_OP = 'DELETE' THEN 'task_deleted'
        END,
        CASE
            WHEN TG_OP = 'INSERT' THEN 'Task created: ' || NEW.task_title
            WHEN TG_OP = 'UPDATE' THEN 'Task updated: ' || NEW.task_title
            WHEN TG_OP = 'DELETE' THEN 'Task deleted: ' || OLD.task_title
        END,
        CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW) ELSE NULL END;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- TRIGGERS
-- =========================================--

-- Update task progress when subtasks change
CREATE TRIGGER trigger_update_task_progress
    AFTER INSERT OR UPDATE OR DELETE ON subtasks
    FOR EACH ROW EXECUTE FUNCTION update_task_progress_from_subtasks();

-- Log task activities
CREATE TRIGGER trigger_log_task_activity
    AFTER INSERT OR UPDATE OR DELETE ON tasks
    FOR EACH ROW EXECUTE FUNCTION log_task_activity();

-- ===========================================
-- SAMPLE DATA INSERTION
-- =========================================--

-- Insert sample user
INSERT INTO users (username, email, password_hash, full_name) VALUES
('john.doe', 'john.doe@example.com', '$2b$10$dummy.hash.here', 'John Doe');

-- Insert sample workspace
INSERT INTO workspaces (workspace_name, workspace_description, owner_id) VALUES
('Product Development', 'Main product development workspace',
 (SELECT user_id FROM users WHERE username = 'john.doe' LIMIT 1));

-- Insert sample project
INSERT INTO projects (
    workspace_id, project_name, project_key, project_description,
    project_lead_id, created_by
) VALUES (
    (SELECT workspace_id FROM workspaces WHERE workspace_name = 'Product Development' LIMIT 1),
    'Website Redesign', 'WEBSITE', 'Complete redesign of company website',
    (SELECT user_id FROM users WHERE username = 'john.doe' LIMIT 1),
    (SELECT user_id FROM users WHERE username = 'john.doe' LIMIT 1)
);

-- Insert sample task list
INSERT INTO task_lists (project_id, list_name, sort_order) VALUES
((SELECT project_id FROM projects WHERE project_key = 'WEBSITE' LIMIT 1), 'To Do', 1),
((SELECT project_id FROM projects WHERE project_key = 'WEBSITE' LIMIT 1), 'In Progress', 2),
((SELECT project_id FROM projects WHERE project_key = 'WEBSITE' LIMIT 1), 'Done', 3);

-- Insert sample task
INSERT INTO tasks (
    project_id, list_id, task_title, task_description, task_key,
    assigned_to, reported_by, created_by
) VALUES (
    (SELECT project_id FROM projects WHERE project_key = 'WEBSITE' LIMIT 1),
    (SELECT list_id FROM task_lists WHERE list_name = 'To Do' LIMIT 1),
    'Design new homepage', 'Create wireframes and mockups for the new homepage design',
    'WEBSITE-1',
    (SELECT user_id FROM users WHERE username = 'john.doe' LIMIT 1),
    (SELECT user_id FROM users WHERE username = 'john.doe' LIMIT 1),
    (SELECT user_id FROM users WHERE username = 'john.doe' LIMIT 1)
);

-- This starter schema provides the foundation for a comprehensive task and project management platform
-- with support for teams, time tracking, file attachments, and extensive customization options.
