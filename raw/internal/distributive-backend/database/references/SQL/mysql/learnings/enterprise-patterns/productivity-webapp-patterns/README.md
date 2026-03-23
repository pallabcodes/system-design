# Productivity WebApp Patterns

Advanced productivity webapp patterns, complex relationships, inheritance patterns, and real-world techniques used by product engineers at Asana, Monday.com, Linear, advanced Atlassian features, and other productivity platforms.

## 📋 Asana-Style Task Management

### The "Hierarchical Task Dependencies" Pattern
```sql
-- Advanced task management with dependencies
CREATE TABLE tasks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    task_id VARCHAR(50) UNIQUE NOT NULL,
    workspace_id BIGINT NOT NULL,
    project_id BIGINT NULL,
    task_name VARCHAR(255) NOT NULL,
    description TEXT,
    task_type ENUM('task', 'subtask', 'milestone', 'section') DEFAULT 'task',
    status ENUM('not_started', 'in_progress', 'waiting_on_others', 'completed', 'cancelled') DEFAULT 'not_started',
    priority ENUM('low', 'normal', 'high', 'urgent') DEFAULT 'normal',
    assignee_id BIGINT NULL,
    created_by BIGINT NOT NULL,
    parent_task_id BIGINT NULL,  -- For subtasks
    section_id BIGINT NULL,  -- For project sections
    due_date DATE NULL,
    due_time TIME NULL,
    start_date DATE NULL,
    estimated_hours DECIMAL(5,2) DEFAULT 0,
    actual_hours DECIMAL(5,2) DEFAULT 0,
    progress_percentage DECIMAL(5,2) DEFAULT 0,
    tags JSON,  -- Array of tags
    custom_fields JSON,  -- Flexible custom fields
    attachments JSON,  -- File attachments
    is_template BOOLEAN DEFAULT FALSE,
    template_id BIGINT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    
    INDEX idx_workspace_task (workspace_id, status, due_date),
    INDEX idx_project_task (project_id, status, due_date),
    INDEX idx_assignee (assignee_id, status, due_date),
    INDEX idx_parent_task (parent_task_id, task_type),
    INDEX idx_section (section_id, task_type),
    INDEX idx_dependencies (due_date, priority, status),
    FULLTEXT INDEX idx_task_search (task_name, description)
);

-- Task dependencies (Asana's "waiting on" feature)
CREATE TABLE task_dependencies (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    dependent_task_id BIGINT NOT NULL,  -- Task that depends on another
    dependency_task_id BIGINT NOT NULL,  -- Task that must be completed first
    dependency_type ENUM('finish_to_start', 'start_to_start', 'finish_to_finish', 'start_to_finish') DEFAULT 'finish_to_start',
    lag_days INT DEFAULT 0,  -- Delay between tasks
    is_critical BOOLEAN DEFAULT FALSE,  -- Critical path dependency
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_task_dependency (dependent_task_id, dependency_task_id),
    INDEX idx_dependent_task (dependent_task_id, dependency_type),
    INDEX idx_dependency_task (dependency_task_id, dependency_type),
    INDEX idx_critical_dependencies (is_critical, dependency_type)
);

-- Task relationships (Asana's "related to" feature)
CREATE TABLE task_relationships (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    source_task_id BIGINT NOT NULL,
    target_task_id BIGINT NOT NULL,
    relationship_type ENUM('duplicates', 'is_duplicated_by', 'blocks', 'is_blocked_by', 'relates_to') DEFAULT 'relates_to',
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_task_relationship (source_task_id, target_task_id, relationship_type),
    INDEX idx_source_task (source_task_id, relationship_type),
    INDEX idx_target_task (target_task_id, relationship_type)
);

-- Task templates and recurring tasks
CREATE TABLE task_templates (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    template_id VARCHAR(50) UNIQUE NOT NULL,
    workspace_id BIGINT NOT NULL,
    template_name VARCHAR(255) NOT NULL,
    template_description TEXT,
    template_data JSON NOT NULL,  -- Complete task structure
    is_recurring BOOLEAN DEFAULT FALSE,
    recurrence_pattern JSON,  -- Cron-like pattern for recurring tasks
    created_by BIGINT NOT NULL,
    usage_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_workspace_templates (workspace_id, is_recurring),
    INDEX idx_template_usage (usage_count DESC, created_at),
    INDEX idx_created_by (created_by, created_at)
);

-- Task time tracking
CREATE TABLE task_time_entries (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    task_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NULL,
    duration_minutes INT NULL,
    description TEXT,
    billable BOOLEAN DEFAULT FALSE,
    hourly_rate DECIMAL(8,2) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_task_time (task_id, start_time),
    INDEX idx_user_time (user_id, start_time),
    INDEX idx_billable_time (billable, start_time)
);
```

### The "Project Portfolio Management" Pattern
```sql
-- Portfolio management (Asana's Portfolios feature)
CREATE TABLE portfolios (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    portfolio_id VARCHAR(50) UNIQUE NOT NULL,
    workspace_id BIGINT NOT NULL,
    portfolio_name VARCHAR(255) NOT NULL,
    description TEXT,
    portfolio_type ENUM('initiative', 'program', 'portfolio') DEFAULT 'portfolio',
    status ENUM('planning', 'active', 'on_hold', 'completed', 'cancelled') DEFAULT 'planning',
    start_date DATE NULL,
    end_date DATE NULL,
    budget_amount DECIMAL(15,2) NULL,
    actual_amount DECIMAL(15,2) NULL,
    owner_id BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_workspace_portfolio (workspace_id, status),
    INDEX idx_portfolio_dates (start_date, end_date),
    INDEX idx_owner (owner_id, status)
);

-- Portfolio-project relationships
CREATE TABLE portfolio_projects (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    portfolio_id BIGINT NOT NULL,
    project_id BIGINT NOT NULL,
    weight_percentage DECIMAL(5,2) DEFAULT 0,  -- Project weight in portfolio
    priority_level INT DEFAULT 0,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_portfolio_project (portfolio_id, project_id),
    INDEX idx_portfolio_projects (portfolio_id, priority_level),
    INDEX idx_project_portfolios (project_id, weight_percentage)
);
```

## 📅 Monday.com-Style Board Management

### The "Dynamic Board Views" Pattern
```sql
-- Monday.com-style boards
CREATE TABLE boards (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    board_id VARCHAR(50) UNIQUE NOT NULL,
    workspace_id BIGINT NOT NULL,
    board_name VARCHAR(255) NOT NULL,
    board_type ENUM('project', 'marketing', 'sales', 'development', 'design', 'custom') DEFAULT 'project',
    board_kind ENUM('public', 'private', 'shareable') DEFAULT 'private',
    board_owner_id BIGINT NOT NULL,
    board_description TEXT,
    board_icon VARCHAR(20),  -- Emoji icon
    board_color VARCHAR(7),  -- Hex color
    is_template BOOLEAN DEFAULT FALSE,
    template_category VARCHAR(100) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_workspace_boards (workspace_id, board_type),
    INDEX idx_board_owner (board_owner_id, created_at),
    INDEX idx_board_templates (is_template, template_category)
);

-- Dynamic board columns (Monday.com's flexible column system)
CREATE TABLE board_columns (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    board_id BIGINT NOT NULL,
    column_id VARCHAR(50) UNIQUE NOT NULL,
    column_title VARCHAR(255) NOT NULL,
    column_type ENUM('text', 'number', 'status', 'date', 'person', 'dropdown', 'checkbox', 'rating', 'file', 'formula', 'link', 'location', 'timeline') NOT NULL,
    column_order INT NOT NULL,
    column_width INT DEFAULT 200,
    is_required BOOLEAN DEFAULT FALSE,
    is_unique BOOLEAN DEFAULT FALSE,
    default_value JSON,  -- Default value for the column
    column_settings JSON,  -- Column-specific settings
    formula_expression TEXT,  -- For formula columns
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_board_columns (board_id, column_order),
    INDEX idx_column_type (column_type, created_at),
    INDEX idx_formula_columns (column_type, formula_expression)
);

-- Board items (Monday.com's items)
CREATE TABLE board_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    item_id VARCHAR(50) UNIQUE NOT NULL,
    board_id BIGINT NOT NULL,
    item_name VARCHAR(255) NOT NULL,
    item_order INT NOT NULL,
    item_status ENUM('active', 'archived', 'deleted') DEFAULT 'active',
    created_by BIGINT NOT NULL,
    assigned_to BIGINT NULL,
    group_id BIGINT NULL,  -- Monday.com groups
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_board_items (board_id, item_order),
    INDEX idx_assigned_to (assigned_to, item_status),
    INDEX idx_group_items (group_id, item_order),
    INDEX idx_created_by (created_by, created_at)
);

-- Dynamic item values (Monday.com's flexible value system)
CREATE TABLE item_column_values (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    item_id BIGINT NOT NULL,
    column_id BIGINT NOT NULL,
    column_value JSON,  -- Flexible value storage
    value_text TEXT,  -- For text search
    value_number DECIMAL(15,4) NULL,  -- For numeric operations
    value_date DATE NULL,  -- For date operations
    updated_by BIGINT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_item_column (item_id, column_id),
    INDEX idx_item_values (item_id, updated_at),
    INDEX idx_column_values (column_id, value_text),
    INDEX idx_numeric_values (column_id, value_number),
    INDEX idx_date_values (column_id, value_date),
    FULLTEXT INDEX idx_value_search (value_text)
);

-- Board views (Monday.com's multiple view types)
CREATE TABLE board_views (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    board_id BIGINT NOT NULL,
    view_id VARCHAR(50) UNIQUE NOT NULL,
    view_name VARCHAR(255) NOT NULL,
    view_type ENUM('table', 'kanban', 'timeline', 'calendar', 'gantt', 'form', 'gallery', 'workload') DEFAULT 'table',
    view_settings JSON NOT NULL,  -- View-specific settings
    is_default BOOLEAN DEFAULT FALSE,
    is_shared BOOLEAN DEFAULT FALSE,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_board_views (board_id, view_type),
    INDEX idx_default_views (board_id, is_default),
    INDEX idx_shared_views (is_shared, view_type)
);
```

## 🚀 Linear-Style Issue Tracking

### The "Advanced Issue Workflow" Pattern
```sql
-- Linear-style issues with advanced workflow
CREATE TABLE linear_issues (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    issue_id VARCHAR(50) UNIQUE NOT NULL,
    team_id BIGINT NOT NULL,
    project_id BIGINT NULL,
    cycle_id BIGINT NULL,  -- Linear's sprint equivalent
    issue_number INT NOT NULL,  -- Sequential number within team
    title VARCHAR(255) NOT NULL,
    description TEXT,
    issue_type ENUM('bug', 'feature', 'improvement', 'task', 'story') DEFAULT 'task',
    priority ENUM('no_priority', 'urgent', 'high', 'medium', 'low') DEFAULT 'no_priority',
    estimate INT NULL,  -- Story points
    assignee_id BIGINT NULL,
    creator_id BIGINT NOT NULL,
    state_id BIGINT NOT NULL,  -- Workflow state
    labels JSON,  -- Array of label IDs
    parent_issue_id BIGINT NULL,  -- For subtasks
    sub_issue_sort_order DECIMAL(10,3) DEFAULT 0,  -- For ordering subtasks
    auto_closed_at TIMESTAMP NULL,
    auto_archived_at TIMESTAMP NULL,
    trashed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_team_issue_number (team_id, issue_number),
    INDEX idx_team_issues (team_id, state_id, priority),
    INDEX idx_project_issues (project_id, state_id),
    INDEX idx_cycle_issues (cycle_id, state_id),
    INDEX idx_assignee (assignee_id, state_id),
    INDEX idx_parent_issue (parent_issue_id, sub_issue_sort_order),
    INDEX idx_auto_archive (auto_archived_at, state_id)
);

-- Linear's workflow states
CREATE TABLE workflow_states (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    team_id BIGINT NOT NULL,
    state_name VARCHAR(100) NOT NULL,
    state_type ENUM('backlog', 'unstarted', 'started', 'completed', 'canceled') NOT NULL,
    state_color VARCHAR(7) NOT NULL,  -- Hex color
    state_order INT NOT NULL,
    is_final BOOLEAN DEFAULT FALSE,  -- Terminal state
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_team_states (team_id, state_order),
    INDEX idx_state_type (state_type, state_order)
);

-- Linear's cycles (sprints)
CREATE TABLE cycles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    team_id BIGINT NOT NULL,
    cycle_name VARCHAR(100) NOT NULL,
    cycle_number INT NOT NULL,  -- Sequential number
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    cycle_status ENUM('future', 'active', 'completed') DEFAULT 'future',
    auto_close_issues BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_team_cycle_number (team_id, cycle_number),
    INDEX idx_team_cycles (team_id, cycle_status, start_date),
    INDEX idx_cycle_dates (start_date, end_date, cycle_status)
);

-- Linear's issue comments with reactions
CREATE TABLE issue_comments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    issue_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    comment_text TEXT NOT NULL,
    comment_type ENUM('comment', 'system') DEFAULT 'comment',
    parent_comment_id BIGINT NULL,  -- For threaded comments
    edited_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_issue_comments (issue_id, created_at),
    INDEX idx_user_comments (user_id, created_at),
    INDEX idx_parent_comment (parent_comment_id, created_at)
);

-- Linear's issue reactions
CREATE TABLE issue_reactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    issue_id BIGINT NOT NULL,
    comment_id BIGINT NULL,  -- NULL for issue reactions
    user_id BIGINT NOT NULL,
    reaction_emoji VARCHAR(10) NOT NULL,  -- Unicode emoji
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_reaction (issue_id, comment_id, user_id, reaction_emoji),
    INDEX idx_issue_reactions (issue_id, reaction_emoji),
    INDEX idx_comment_reactions (comment_id, reaction_emoji),
    INDEX idx_user_reactions (user_id, created_at)
);
```

## 🎯 Advanced Atlassian Patterns

### The "Advanced Jira Workflow Engine" Pattern
```sql
-- Advanced Jira workflow engine
CREATE TABLE workflow_schemes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    scheme_id VARCHAR(50) UNIQUE NOT NULL,
    scheme_name VARCHAR(255) NOT NULL,
    scheme_description TEXT,
    is_default BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_active_schemes (is_active, is_default),
    INDEX idx_created_by (created_by, created_at)
);

-- Workflow definitions
CREATE TABLE workflows (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    workflow_id VARCHAR(50) UNIQUE NOT NULL,
    workflow_name VARCHAR(255) NOT NULL,
    workflow_description TEXT,
    workflow_type ENUM('issue', 'project', 'global') DEFAULT 'issue',
    is_system BOOLEAN DEFAULT FALSE,  -- System workflows can't be modified
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_workflow_type (workflow_type, is_system),
    INDEX idx_created_by (created_by, created_at)
);

-- Workflow steps and transitions
CREATE TABLE workflow_steps (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    workflow_id BIGINT NOT NULL,
    step_id VARCHAR(50) UNIQUE NOT NULL,
    step_name VARCHAR(100) NOT NULL,
    step_type ENUM('start', 'intermediate', 'end') DEFAULT 'intermediate',
    step_order INT NOT NULL,
    step_actions JSON,  -- Available actions for this step
    step_validators JSON,  -- Validation rules
    step_post_functions JSON,  -- Post-execution functions
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_workflow_steps (workflow_id, step_order),
    INDEX idx_step_type (step_type, step_order)
);

-- Workflow transitions
CREATE TABLE workflow_transitions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    workflow_id BIGINT NOT NULL,
    transition_id VARCHAR(50) UNIQUE NOT NULL,
    transition_name VARCHAR(255) NOT NULL,
    from_step_id BIGINT NOT NULL,
    to_step_id BIGINT NOT NULL,
    transition_type ENUM('global', 'directed', 'conditional') DEFAULT 'directed',
    transition_conditions JSON,  -- Conditions that must be met
    transition_validators JSON,  -- Validation rules
    transition_post_functions JSON,  -- Post-execution functions
    transition_screen_id BIGINT NULL,  -- Screen to show during transition
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_workflow_transitions (workflow_id, from_step_id),
    INDEX idx_transition_type (transition_type, from_step_id),
    INDEX idx_to_step (to_step_id, transition_type)
);

-- Advanced issue linking
CREATE TABLE issue_links (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    source_issue_id BIGINT NOT NULL,
    target_issue_id BIGINT NOT NULL,
    link_type ENUM('blocks', 'is_blocked_by', 'duplicates', 'is_duplicated_by', 'relates_to', 'depends_on', 'is_required_by', 'clones', 'is_cloned_by') NOT NULL,
    link_direction ENUM('inward', 'outward') DEFAULT 'outward',
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_issue_link (source_issue_id, target_issue_id, link_type),
    INDEX idx_source_issue (source_issue_id, link_type),
    INDEX idx_target_issue (target_issue_id, link_type),
    INDEX idx_link_type (link_type, created_at)
);

-- Advanced custom fields
CREATE TABLE custom_fields (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    field_id VARCHAR(50) UNIQUE NOT NULL,
    field_name VARCHAR(255) NOT NULL,
    field_type ENUM('text', 'number', 'date', 'datetime', 'select', 'multiselect', 'checkbox', 'radio', 'textarea', 'user', 'group', 'project', 'version', 'component', 'cascading_select', 'url', 'email', 'phone') NOT NULL,
    field_schema JSON NOT NULL,  -- Field configuration
    field_default_value JSON,
    field_validators JSON,  -- Validation rules
    is_required BOOLEAN DEFAULT FALSE,
    is_searchable BOOLEAN DEFAULT TRUE,
    is_global BOOLEAN DEFAULT FALSE,  -- Available across all projects
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_field_type (field_type, is_global),
    INDEX idx_searchable_fields (is_searchable, field_type),
    INDEX idx_created_by (created_by, created_at)
);

-- Custom field values
CREATE TABLE custom_field_values (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    issue_id BIGINT NOT NULL,
    field_id BIGINT NOT NULL,
    field_value JSON,  -- Flexible value storage
    field_text TEXT,  -- For text search
    field_number DECIMAL(15,4) NULL,  -- For numeric operations
    field_date DATE NULL,  -- For date operations
    updated_by BIGINT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_issue_field (issue_id, field_id),
    INDEX idx_issue_field_values (issue_id, field_id),
    INDEX idx_field_values (field_id, field_text),
    INDEX idx_numeric_field_values (field_id, field_number),
    INDEX idx_date_field_values (field_id, field_date),
    FULLTEXT INDEX idx_field_search (field_text)
);
```

## 🔄 Advanced Inheritance Patterns

### The "Polymorphic Task System" Pattern
```sql
-- Polymorphic task system (supports multiple task types)
CREATE TABLE polymorphic_tasks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    task_id VARCHAR(50) UNIQUE NOT NULL,
    taskable_type VARCHAR(50) NOT NULL,  -- 'issue', 'story', 'bug', 'feature'
    taskable_id BIGINT NOT NULL,  -- ID in the specific task table
    workspace_id BIGINT NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL,
    priority VARCHAR(20) DEFAULT 'medium',
    assignee_id BIGINT NULL,
    created_by BIGINT NOT NULL,
    due_date DATE NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_taskable (taskable_type, taskable_id),
    INDEX idx_workspace_tasks (workspace_id, taskable_type, status),
    INDEX idx_assignee (assignee_id, taskable_type, status),
    INDEX idx_polymorphic_search (taskable_type, status, priority)
);

-- Task type-specific attributes
CREATE TABLE task_attributes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    task_id BIGINT NOT NULL,
    attribute_key VARCHAR(100) NOT NULL,
    attribute_value JSON,
    attribute_type ENUM('string', 'number', 'boolean', 'date', 'json') DEFAULT 'string',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_task_attribute (task_id, attribute_key),
    INDEX idx_task_attributes (task_id, attribute_key),
    INDEX idx_attribute_search (attribute_key, attribute_value)
);
```

## 📊 Advanced Analytics Patterns

### The "Productivity Analytics" Pattern
```sql
-- Productivity analytics
CREATE TABLE productivity_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    workspace_id BIGINT NOT NULL,
    metric_date DATE NOT NULL,
    metric_type ENUM('task_completion', 'time_tracking', 'project_velocity', 'team_velocity', 'cycle_time', 'lead_time') NOT NULL,
    metric_value DECIMAL(10,4) NOT NULL,
    metric_unit VARCHAR(20) NOT NULL,  -- 'tasks', 'hours', 'story_points', 'days'
    metric_context JSON,  -- Additional context
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_workspace_metric (workspace_id, metric_date, metric_type),
    INDEX idx_workspace_metrics (workspace_id, metric_type, metric_date),
    INDEX idx_metric_trends (metric_type, metric_date, metric_value)
);

-- Team velocity tracking
CREATE TABLE team_velocity (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    team_id BIGINT NOT NULL,
    sprint_id BIGINT NOT NULL,
    planned_story_points INT DEFAULT 0,
    completed_story_points INT DEFAULT 0,
    planned_tasks INT DEFAULT 0,
    completed_tasks INT DEFAULT 0,
    average_cycle_time_days DECIMAL(5,2) DEFAULT 0,
    average_lead_time_days DECIMAL(5,2) DEFAULT 0,
    sprint_start_date DATE NOT NULL,
    sprint_end_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_team_sprint (team_id, sprint_id),
    INDEX idx_team_velocity (team_id, sprint_start_date),
    INDEX idx_velocity_trends (team_id, completed_story_points, sprint_end_date)
);

-- Time tracking analytics
CREATE TABLE time_tracking_analytics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    project_id BIGINT NULL,
    task_id BIGINT NULL,
    tracking_date DATE NOT NULL,
    total_hours DECIMAL(6,2) DEFAULT 0,
    billable_hours DECIMAL(6,2) DEFAULT 0,
    non_billable_hours DECIMAL(6,2) DEFAULT 0,
    productivity_score DECIMAL(5,2) DEFAULT 0,  -- 0-100
    focus_time_hours DECIMAL(6,2) DEFAULT 0,  -- Deep work time
    meeting_time_hours DECIMAL(6,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_date (user_id, tracking_date),
    INDEX idx_user_productivity (user_id, tracking_date),
    INDEX idx_project_time (project_id, tracking_date),
    INDEX idx_productivity_score (productivity_score DESC, tracking_date)
);
```

These productivity webapp patterns show the real-world techniques that product engineers use to build complex, scalable productivity platforms with advanced inheritance, relationships, and analytics! 🚀
