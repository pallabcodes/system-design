-- Task Management Platform Starter Schema (MySQL)
-- Complete schema for task/project management applications with advanced features
-- Adapted for MySQL with JSON support, fulltext search, and MySQL-specific optimizations

-- ===========================================
-- USERS AND TEAMS
-- ===========================================

CREATE TABLE users (
    user_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(200) NOT NULL,
    avatar_url VARCHAR(500),

    -- Profile
    job_title VARCHAR(100),
    department VARCHAR(100),
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,

    -- Preferences
    notification_settings JSON DEFAULT ('{"email": true, "push": true, "desktop": false}'),
    theme_preference ENUM('light', 'dark', 'auto') DEFAULT 'auto',

    -- Activity tracking
    last_login_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_users_email (email),
    INDEX idx_users_username (username),
    INDEX idx_users_active (is_active),
    INDEX idx_users_last_login (last_login_at),
    FULLTEXT INDEX ft_users_name (full_name, job_title)
) ENGINE = InnoDB;

CREATE TABLE teams (
    team_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    team_name VARCHAR(100) NOT NULL,
    team_description TEXT,
    team_type ENUM('department', 'project_team', 'cross_functional', 'external') DEFAULT 'project_team',

    -- Settings
    is_private BOOLEAN DEFAULT FALSE,
    allow_guest_members BOOLEAN DEFAULT FALSE,
    max_members INT DEFAULT 50,

    -- Ownership
    created_by CHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_teams_type (team_type),
    INDEX idx_teams_private (is_private),
    INDEX idx_teams_created_by (created_by),
    FULLTEXT INDEX ft_teams_name_desc (team_name, team_description)
) ENGINE = InnoDB;

CREATE TABLE team_members (
    team_id CHAR(36) NOT NULL,
    user_id CHAR(36) NOT NULL,
    role ENUM('owner', 'admin', 'member', 'guest') DEFAULT 'member',
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (team_id, user_id),
    FOREIGN KEY (team_id) REFERENCES teams(team_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_team_members_user (user_id),
    INDEX idx_team_members_role (role)
) ENGINE = InnoDB;

-- ===========================================
-- PROJECTS AND WORKSPACES
-- ===========================================

CREATE TABLE workspaces (
    workspace_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    workspace_name VARCHAR(100) NOT NULL,
    workspace_description TEXT,

    -- Access control
    is_private BOOLEAN DEFAULT FALSE,
    allowed_domains JSON DEFAULT ('[]'),  -- For domain restrictions

    -- Ownership
    created_by CHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_workspaces_private (is_private),
    INDEX idx_workspaces_created_by (created_by),
    FULLTEXT INDEX ft_workspaces_name_desc (workspace_name, workspace_description)
) ENGINE = InnoDB;

CREATE TABLE projects (
    project_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    workspace_id CHAR(36) NOT NULL,

    project_name VARCHAR(255) NOT NULL,
    project_description TEXT,
    project_key VARCHAR(10) UNIQUE NOT NULL,  -- Like "PROJ", "TASK", etc.

    -- Status and progress
    status ENUM('planning', 'active', 'on_hold', 'completed', 'cancelled') DEFAULT 'planning',
    progress_percentage INT DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),

    -- Timeline
    start_date DATE,
    due_date DATE,
    completed_at TIMESTAMP NULL,

    -- Priority and settings
    priority ENUM('lowest', 'low', 'medium', 'high', 'highest') DEFAULT 'medium',
    project_color VARCHAR(7) DEFAULT '#3498db',  -- Hex color

    -- Metadata
    tags JSON DEFAULT ('[]'),
    custom_fields JSON DEFAULT ('{}'),

    -- Ownership and access
    created_by CHAR(36) NOT NULL,
    team_id CHAR(36) NULL,
    is_archived BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (workspace_id) REFERENCES workspaces(workspace_id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (team_id) REFERENCES teams(team_id) ON DELETE SET NULL,

    INDEX idx_projects_workspace (workspace_id),
    INDEX idx_projects_status (status),
    INDEX idx_projects_team (team_id),
    INDEX idx_projects_due_date (due_date),
    INDEX idx_projects_priority (priority),
    INDEX idx_projects_archived (is_archived),
    INDEX idx_projects_key (project_key),
    FULLTEXT INDEX ft_projects_name_desc (project_name, project_description)
) ENGINE = InnoDB;

-- ===========================================
-- TASK MANAGEMENT
-- ===========================================

CREATE TABLE task_lists (
    list_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    project_id CHAR(36) NOT NULL,

    list_name VARCHAR(255) NOT NULL,
    list_description TEXT,
    list_color VARCHAR(7) DEFAULT '#95a5a6',  -- Hex color

    -- Ordering
    list_order INT DEFAULT 0,

    -- Status
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMP NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (project_id) REFERENCES projects(project_id) ON DELETE CASCADE,

    INDEX idx_lists_project (project_id),
    INDEX idx_lists_order (list_order),
    INDEX idx_lists_completed (is_completed)
) ENGINE = InnoDB;

CREATE TABLE tasks (
    task_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    project_id CHAR(36) NOT NULL,
    list_id CHAR(36) NULL,

    -- Task content
    task_title VARCHAR(500) NOT NULL,
    task_description LONGTEXT,
    task_key VARCHAR(20) UNIQUE NOT NULL,  -- Like "PROJ-123"

    -- Status and progress
    status ENUM('todo', 'in_progress', 'review', 'done', 'cancelled') DEFAULT 'todo',
    priority ENUM('lowest', 'low', 'medium', 'high', 'highest') DEFAULT 'medium',

    -- Assignment
    assigned_to CHAR(36) NULL,
    assigned_by CHAR(36) NULL,
    assigned_at TIMESTAMP NULL,

    -- Timeline
    due_date DATE,
    start_date DATE,
    completed_at TIMESTAMP NULL,
    estimated_hours DECIMAL(6,2),
    actual_hours DECIMAL(6,2),

    -- Progress tracking
    progress_percentage INT DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),

    -- Dependencies and relationships
    parent_task_id CHAR(36) NULL,
    depends_on JSON DEFAULT ('[]'),  -- Array of task IDs

    -- Ordering and grouping
    task_order INT DEFAULT 0,
    labels JSON DEFAULT ('[]'),

    -- Attachments and media
    attachments JSON DEFAULT ('[]'),

    -- Metadata
    custom_fields JSON DEFAULT ('{}'),
    metadata JSON DEFAULT ('{}'),

    -- Audit
    created_by CHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (list_id) REFERENCES task_lists(list_id) ON DELETE SET NULL,
    FOREIGN KEY (assigned_to) REFERENCES users(user_id) ON DELETE SET NULL,
    FOREIGN KEY (assigned_by) REFERENCES users(user_id) ON DELETE SET NULL,
    FOREIGN KEY (parent_task_id) REFERENCES tasks(task_id) ON DELETE SET NULL,
    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_tasks_project (project_id),
    INDEX idx_tasks_list (list_id),
    INDEX idx_tasks_assigned_to (assigned_to),
    INDEX idx_tasks_status (status),
    INDEX idx_tasks_priority (priority),
    INDEX idx_tasks_due_date (due_date),
    INDEX idx_tasks_parent (parent_task_id),
    INDEX idx_tasks_order (task_order),
    INDEX idx_tasks_key (task_key),
    FULLTEXT INDEX ft_tasks_title_desc (task_title, task_description)
) ENGINE = InnoDB;

-- ===========================================
-- TIME TRACKING
-- ===========================================

CREATE TABLE time_entries (
    time_entry_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    task_id CHAR(36) NOT NULL,
    user_id CHAR(36) NOT NULL,

    -- Time details
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NULL,
    duration_minutes INT NULL,  -- Calculated field

    -- Description and categorization
    description TEXT,
    time_entry_type ENUM('work', 'break', 'meeting', 'research') DEFAULT 'work',
    billable BOOLEAN DEFAULT TRUE,

    -- Metadata
    tags JSON DEFAULT ('[]'),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (task_id) REFERENCES tasks(task_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_time_entries_task (task_id),
    INDEX idx_time_entries_user (user_id),
    INDEX idx_time_entries_start (start_time),
    INDEX idx_time_entries_end (end_time),
    INDEX idx_time_entries_type (time_entry_type),
    INDEX idx_time_entries_billable (billable)
) ENGINE = InnoDB;

-- ===========================================
-- COMMENTS AND COLLABORATION
-- ===========================================

CREATE TABLE comments (
    comment_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    task_id CHAR(36) NOT NULL,
    user_id CHAR(36) NOT NULL,

    comment_text LONGTEXT NOT NULL,

    -- Threading support
    parent_comment_id CHAR(36) NULL,

    -- Attachments
    attachments JSON DEFAULT ('[]'),

    -- Edit history
    is_edited BOOLEAN DEFAULT FALSE,
    edited_at TIMESTAMP NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (task_id) REFERENCES tasks(task_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (parent_comment_id) REFERENCES comments(comment_id) ON DELETE CASCADE,

    INDEX idx_comments_task (task_id),
    INDEX idx_comments_user (user_id),
    INDEX idx_comments_parent (parent_comment_id),
    INDEX idx_comments_created (created_at),
    FULLTEXT INDEX ft_comments_text (comment_text)
) ENGINE = InnoDB;

-- ===========================================
-- ACTIVITY LOGGING
-- ===========================================

CREATE TABLE activities (
    activity_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id CHAR(36) NOT NULL,
    entity_type ENUM('project', 'task', 'list', 'comment', 'time_entry') NOT NULL,
    entity_id CHAR(36) NOT NULL,

    -- Activity details
    action_type ENUM('created', 'updated', 'deleted', 'assigned', 'completed', 'commented', 'time_tracked') NOT NULL,
    action_description TEXT NOT NULL,

    -- Changes tracking
    old_values JSON,
    new_values JSON,

    -- Context
    project_id CHAR(36) NULL,
    workspace_id CHAR(36) NULL,

    -- Metadata
    ip_address VARCHAR(45),
    user_agent TEXT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_activities_user (user_id),
    INDEX idx_activities_entity (entity_type, entity_id),
    INDEX idx_activities_action (action_type),
    INDEX idx_activities_project (project_id),
    INDEX idx_activities_workspace (workspace_id),
    INDEX idx_activities_created (created_at)
) ENGINE = InnoDB;

-- ===========================================
-- NOTIFICATIONS
-- ===========================================

CREATE TABLE notifications (
    notification_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    user_id CHAR(36) NOT NULL,

    notification_type ENUM('task_assigned', 'task_due', 'comment_mention', 'project_update', 'deadline_approaching') NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,

    -- Related entities
    entity_type ENUM('project', 'task', 'comment') NULL,
    entity_id CHAR(36) NULL,

    -- Status
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMP NULL,

    -- Action URL (for frontend)
    action_url VARCHAR(500),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_notifications_user (user_id),
    INDEX idx_notifications_type (notification_type),
    INDEX idx_notifications_read (is_read),
    INDEX idx_notifications_created (created_at),
    INDEX idx_notifications_entity (entity_type, entity_id)
) ENGINE = InnoDB;

-- ===========================================
-- TAGS AND LABELS SYSTEM
-- ===========================================

CREATE TABLE tags (
    tag_id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    workspace_id CHAR(36) NOT NULL,

    tag_name VARCHAR(50) NOT NULL,
    tag_color VARCHAR(7) DEFAULT '#3498db',  -- Hex color
    tag_description TEXT,

    -- Usage tracking
    usage_count INT DEFAULT 0,

    created_by CHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (workspace_id) REFERENCES workspaces(workspace_id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE CASCADE,

    UNIQUE KEY unique_workspace_tag (workspace_id, tag_name),

    INDEX idx_tags_workspace (workspace_id),
    INDEX idx_tags_created_by (created_by)
) ENGINE = InnoDB;

CREATE TABLE task_tags (
    task_id CHAR(36) NOT NULL,
    tag_id CHAR(36) NOT NULL,

    added_by CHAR(36) NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (task_id, tag_id),
    FOREIGN KEY (task_id) REFERENCES tasks(task_id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(tag_id) ON DELETE CASCADE,
    FOREIGN KEY (added_by) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_task_tags_tag (tag_id),
    INDEX idx_task_tags_added_by (added_by)
) ENGINE = InnoDB;

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Composite indexes for common queries
CREATE INDEX idx_tasks_project_status ON tasks (project_id, status);
CREATE INDEX idx_tasks_assigned_due ON tasks (assigned_to, due_date);
CREATE INDEX idx_tasks_project_order ON tasks (project_id, task_order);
CREATE INDEX idx_comments_task_created ON comments (task_id, created_at);
CREATE INDEX idx_activities_project_created ON activities (project_id, created_at);
CREATE INDEX idx_notifications_user_read ON notifications (user_id, is_read);

-- ===========================================
-- TRIGGERS FOR AUTOMATION
-- ===========================================

DELIMITER ;;

-- Update task key generation
CREATE TRIGGER generate_task_key BEFORE INSERT ON tasks
FOR EACH ROW
BEGIN
    DECLARE project_key_val VARCHAR(10);
    DECLARE next_number INT;

    -- Get project key
    SELECT project_key INTO project_key_val
    FROM projects WHERE project_id = NEW.project_id;

    -- Get next number for this project
    SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(task_key, '-', -1) AS UNSIGNED)), 0) + 1
    INTO next_number
    FROM tasks WHERE project_id = NEW.project_id;

    SET NEW.task_key = CONCAT(project_key_val, '-', next_number);
END;;

-- Update time entry duration
CREATE TRIGGER calculate_time_duration BEFORE UPDATE ON time_entries
FOR EACH ROW
BEGIN
    IF NEW.end_time IS NOT NULL AND OLD.end_time IS NULL THEN
        SET NEW.duration_minutes = TIMESTAMPDIFF(MINUTE, NEW.start_time, NEW.end_time);
    END IF;
END;;

-- Activity logging trigger
CREATE TRIGGER log_task_updates AFTER UPDATE ON tasks
FOR EACH ROW
BEGIN
    IF OLD.status != NEW.status THEN
        INSERT INTO activities (user_id, entity_type, entity_id, action_type, action_description, old_values, new_values, project_id)
        VALUES (
            COALESCE(NEW.assigned_to, NEW.created_by),
            'task',
            NEW.task_id,
            'updated',
            CONCAT('Task status changed from ', OLD.status, ' to ', NEW.status),
            JSON_OBJECT('status', OLD.status),
            JSON_OBJECT('status', NEW.status),
            NEW.project_id
        );
    END IF;
END;;

-- Notification trigger for task assignment
CREATE TRIGGER notify_task_assignment AFTER UPDATE ON tasks
FOR EACH ROW
BEGIN
    IF OLD.assigned_to IS NULL AND NEW.assigned_to IS NOT NULL THEN
        INSERT INTO notifications (user_id, notification_type, title, message, entity_type, entity_id, action_url)
        VALUES (
            NEW.assigned_to,
            'task_assigned',
            CONCAT('Task Assigned: ', LEFT(NEW.task_title, 50)),
            CONCAT('You have been assigned to task: ', NEW.task_title),
            'task',
            NEW.task_id,
            CONCAT('/tasks/', NEW.task_id)
        );
    END IF;
END;;

DELIMITER ;

-- ===========================================
-- VIEWS FOR COMMON QUERIES
-- =========================================--

-- Task details with all relationships
CREATE VIEW task_details AS
SELECT
    t.*,
    p.project_name,
    p.project_key,
    tl.list_name,
    assignee.full_name AS assignee_name,
    assignor.full_name AS assignor_name,
    creator.full_name AS creator_name,
    TIMESTAMPDIFF(DAY, CURDATE(), t.due_date) AS days_until_due,
    CASE
        WHEN t.due_date < CURDATE() AND t.status != 'done' THEN 'overdue'
        WHEN t.due_date = CURDATE() AND t.status != 'done' THEN 'due_today'
        WHEN t.due_date BETWEEN CURDATE() + INTERVAL 1 DAY AND CURDATE() + INTERVAL 3 DAY AND t.status != 'done' THEN 'due_soon'
        ELSE 'on_track'
    END AS due_status
FROM tasks t
JOIN projects p ON t.project_id = p.project_id
LEFT JOIN task_lists tl ON t.list_id = tl.list_id
LEFT JOIN users assignee ON t.assigned_to = assignee.user_id
LEFT JOIN users assignor ON t.assigned_by = assignor.user_id
LEFT JOIN users creator ON t.created_by = creator.user_id;

-- Project progress summary
CREATE VIEW project_progress AS
SELECT
    p.project_id,
    p.project_name,
    p.status,
    p.progress_percentage,
    COUNT(t.task_id) AS total_tasks,
    COUNT(CASE WHEN t.status = 'done' THEN 1 END) AS completed_tasks,
    COUNT(CASE WHEN t.status IN ('todo', 'in_progress') THEN 1 END) AS active_tasks,
    COUNT(CASE WHEN t.due_date < CURDATE() AND t.status != 'done' THEN 1 END) AS overdue_tasks,
    AVG(CASE WHEN t.status = 'done' THEN TIMESTAMPDIFF(DAY, t.created_at, t.completed_at) END) AS avg_completion_days
FROM projects p
LEFT JOIN tasks t ON p.project_id = t.project_id
GROUP BY p.project_id, p.project_name, p.status, p.progress_percentage;

-- ===========================================
-- STORED PROCEDURES
-- =========================================--

DELIMITER ;;

-- Get user's tasks with filtering
CREATE PROCEDURE get_user_tasks(
    IN p_user_id CHAR(36),
    IN p_status ENUM('todo', 'in_progress', 'review', 'done', 'cancelled'),
    IN p_priority ENUM('lowest', 'low', 'medium', 'high', 'highest'),
    IN p_due_soon BOOLEAN,
    IN p_limit INT,
    IN p_offset INT
)
BEGIN
    SELECT
        t.*,
        p.project_name,
        tl.list_name,
        TIMESTAMPDIFF(DAY, CURDATE(), t.due_date) AS days_until_due
    FROM tasks t
    JOIN projects p ON t.project_id = p.project_id
    LEFT JOIN task_lists tl ON t.list_id = tl.list_id
    WHERE t.assigned_to = p_user_id
      AND (p_status IS NULL OR t.status = p_status)
      AND (p_priority IS NULL OR t.priority = p_priority)
      AND (p_due_soon IS NULL OR p_due_soon = FALSE OR t.due_date BETWEEN CURDATE() AND CURDATE() + INTERVAL 3 DAY)
      AND t.status != 'cancelled'
    ORDER BY
        CASE
            WHEN t.due_date IS NULL THEN 1
            ELSE 0
        END,
        t.due_date ASC,
        t.priority DESC,
        t.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;;

-- Bulk update task status
CREATE PROCEDURE bulk_update_tasks(
    IN p_task_ids JSON,
    IN p_status ENUM('todo', 'in_progress', 'review', 'done', 'cancelled'),
    IN p_user_id CHAR(36)
)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE task_count INT;
    DECLARE current_task_id CHAR(36);

    SET task_count = JSON_LENGTH(p_task_ids);

    WHILE i < task_count DO
        SET current_task_id = JSON_UNQUOTE(JSON_EXTRACT(p_task_ids, CONCAT('$[', i, ']')));

        UPDATE tasks
        SET status = p_status, updated_at = CURRENT_TIMESTAMP
        WHERE task_id = current_task_id;

        SET i = i + 1;
    END WHILE;
END;;

DELIMITER ;

-- ===========================================
-- INITIAL DATA
-- =========================================--

-- Create a default workspace
INSERT INTO workspaces (workspace_id, workspace_name, workspace_description, created_by) VALUES
(UUID(), 'Default Workspace', 'Default workspace for new users', UUID());

-- Create a sample project
INSERT INTO projects (
    project_id, workspace_id, project_name, project_key, project_description, status, created_by
) VALUES (
    UUID(),
    (SELECT workspace_id FROM workspaces LIMIT 1),
    'Sample Project',
    'SP',
    'A sample project to demonstrate the task management system',
    'active',
    UUID()
);

-- Create sample task list
INSERT INTO task_lists (list_id, project_id, list_name, list_description) VALUES
(UUID(), (SELECT project_id FROM projects LIMIT 1), 'To Do', 'Tasks to be started');

-- Create sample task
INSERT INTO tasks (
    task_id, project_id, list_id, task_title, task_description,
    priority, created_by
) VALUES (
    UUID(),
    (SELECT project_id FROM projects LIMIT 1),
    (SELECT list_id FROM task_lists LIMIT 1),
    'Welcome to the Task Management System',
    'This is a sample task to help you get familiar with the system. Feel free to explore and customize it to your needs.',
    'medium',
    UUID()
);

/*
USAGE EXAMPLES:

-- Get user's tasks
CALL get_user_tasks('user-uuid-here', 'in_progress', NULL, TRUE, 10, 0);

-- Bulk update tasks
CALL bulk_update_tasks('["task-uuid-1", "task-uuid-2"]', 'done', 'user-uuid-here');

This schema provides a complete foundation for a modern task management platform with:
- User and team management
- Project workspaces with customizable settings
- Hierarchical task organization with lists
- Time tracking and progress monitoring
- Comments and collaboration features
- Activity logging and notifications
- Tagging system for organization
- Advanced search and filtering
- Performance optimizations

Key features for task management applications:
1. Flexible project structures with custom fields
2. Comprehensive time tracking
3. Real-time notifications and activity feeds
4. Advanced filtering and search capabilities
5. Integration-ready with webhooks and API support
6. Scalable architecture for growing teams

Adapt and extend based on your specific requirements!
*/
