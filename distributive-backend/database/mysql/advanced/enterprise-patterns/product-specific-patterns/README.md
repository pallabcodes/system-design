# Product-Specific Patterns

Real-world product-specific patterns, collaboration features, and domain-specific techniques used by product engineers at Atlassian, Slack, Notion, GitHub, and other productivity/product-based companies.

## 🚀 Atlassian-Style Issue Tracking

### The "Jira Issue Management" Pattern
```sql
-- Issue tracking system
CREATE TABLE issues (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    issue_key VARCHAR(20) UNIQUE NOT NULL,  -- 'PROJ-123'
    project_id BIGINT NOT NULL,
    issue_type ENUM('bug', 'story', 'task', 'epic', 'subtask') NOT NULL,
    summary VARCHAR(255) NOT NULL,
    description TEXT,
    status ENUM('to_do', 'in_progress', 'in_review', 'done', 'closed') NOT NULL,
    priority ENUM('lowest', 'low', 'medium', 'high', 'highest') DEFAULT 'medium',
    assignee_id BIGINT NULL,
    reporter_id BIGINT NOT NULL,
    epic_id BIGINT NULL,  -- For epic linking
    parent_issue_id BIGINT NULL,  -- For subtasks
    story_points INT NULL,
    time_estimate_minutes INT DEFAULT 0,
    time_spent_minutes INT DEFAULT 0,
    labels JSON,  -- Array of labels
    components JSON,  -- Array of components
    custom_fields JSON,  -- Flexible custom fields
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP NULL,
    
    INDEX idx_project_issue (project_id, issue_type, status),
    INDEX idx_assignee (assignee_id, status),
    INDEX idx_reporter (reporter_id, created_at),
    INDEX idx_epic (epic_id, issue_type),
    INDEX idx_parent (parent_issue_id),
    INDEX idx_status_priority (status, priority, created_at),
    FULLTEXT INDEX idx_search (summary, description)
);

-- Issue workflow transitions
CREATE TABLE issue_transitions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    issue_id BIGINT NOT NULL,
    from_status VARCHAR(50) NOT NULL,
    to_status VARCHAR(50) NOT NULL,
    transitioned_by BIGINT NOT NULL,
    transition_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    transition_comment TEXT,
    time_spent_minutes INT DEFAULT 0,
    
    INDEX idx_issue_transition (issue_id, transition_date),
    INDEX idx_transition_by (transitioned_by, transition_date),
    INDEX idx_status_change (from_status, to_status, transition_date)
);

-- Issue comments and activity
CREATE TABLE issue_comments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    issue_id BIGINT NOT NULL,
    author_id BIGINT NOT NULL,
    comment_text TEXT NOT NULL,
    comment_type ENUM('comment', 'work_log', 'system') DEFAULT 'comment',
    visibility ENUM('public', 'internal', 'private') DEFAULT 'public',
    parent_comment_id BIGINT NULL,  -- For threaded comments
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_issue_comment (issue_id, created_at),
    INDEX idx_author (author_id, created_at),
    INDEX idx_parent_comment (parent_comment_id, created_at)
);

-- Sprint management
CREATE TABLE sprints (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sprint_name VARCHAR(100) NOT NULL,
    project_id BIGINT NOT NULL,
    sprint_goal TEXT,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    sprint_status ENUM('future', 'active', 'closed') DEFAULT 'future',
    total_story_points INT DEFAULT 0,
    completed_story_points INT DEFAULT 0,
    velocity DECIMAL(5,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_project_sprint (project_id, sprint_status),
    INDEX idx_sprint_dates (start_date, end_date),
    INDEX idx_sprint_status (sprint_status, end_date)
);

-- Sprint issue assignment
CREATE TABLE sprint_issues (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sprint_id BIGINT NOT NULL,
    issue_id BIGINT NOT NULL,
    added_by BIGINT NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_sprint_issue (sprint_id, issue_id),
    INDEX idx_sprint_issues (sprint_id, added_at),
    INDEX idx_issue_sprint (issue_id)
);
```

### The "Confluence Document Management" Pattern
```sql
-- Document management system
CREATE TABLE documents (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    document_key VARCHAR(50) UNIQUE NOT NULL,  -- 'SPACE-123'
    space_id BIGINT NOT NULL,
    title VARCHAR(255) NOT NULL,
    content LONGTEXT,
    content_type ENUM('page', 'blog', 'template', 'draft') DEFAULT 'page',
    status ENUM('draft', 'published', 'archived') DEFAULT 'draft',
    author_id BIGINT NOT NULL,
    parent_page_id BIGINT NULL,  -- For hierarchical pages
    version_number INT DEFAULT 1,
    is_latest_version BOOLEAN DEFAULT TRUE,
    labels JSON,
    metadata JSON,  -- Flexible metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    published_at TIMESTAMP NULL,
    
    INDEX idx_space_document (space_id, content_type, status),
    INDEX idx_author (author_id, created_at),
    INDEX idx_parent (parent_page_id),
    INDEX idx_version (document_key, version_number),
    FULLTEXT INDEX idx_content_search (title, content)
);

-- Document collaboration
CREATE TABLE document_collaborators (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    document_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    permission_level ENUM('view', 'edit', 'admin') DEFAULT 'view',
    added_by BIGINT NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_document_user (document_id, user_id),
    INDEX idx_user_documents (user_id, permission_level),
    INDEX idx_document_permissions (document_id, permission_level)
);

-- Document version history
CREATE TABLE document_versions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    document_id BIGINT NOT NULL,
    version_number INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    content LONGTEXT,
    author_id BIGINT NOT NULL,
    change_summary TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_document_version (document_id, version_number),
    INDEX idx_document_versions (document_id, created_at),
    INDEX idx_author_versions (author_id, created_at)
);
```

## 💬 Slack-Style Messaging Patterns

### The "Channel Management" Pattern
```sql
-- Channel management
CREATE TABLE channels (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    channel_id VARCHAR(20) UNIQUE NOT NULL,  -- 'C1234567890'
    channel_name VARCHAR(80) NOT NULL,
    channel_type ENUM('public', 'private', 'direct', 'group') DEFAULT 'public',
    topic TEXT,
    purpose TEXT,
    creator_id BIGINT NOT NULL,
    member_count INT DEFAULT 0,
    is_archived BOOLEAN DEFAULT FALSE,
    is_general BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    archived_at TIMESTAMP NULL,
    
    INDEX idx_channel_type (channel_type, is_archived),
    INDEX idx_creator (creator_id, created_at),
    INDEX idx_channel_name (channel_name, channel_type)
);

-- Channel members
CREATE TABLE channel_members (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    channel_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_admin BOOLEAN DEFAULT FALSE,
    is_owner BOOLEAN DEFAULT FALSE,
    
    UNIQUE KEY uk_channel_user (channel_id, user_id),
    INDEX idx_user_channels (user_id, joined_at),
    INDEX idx_channel_members (channel_id, joined_at)
);

-- Message threading
CREATE TABLE messages (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    message_id VARCHAR(20) UNIQUE NOT NULL,  -- '1234567890.123456'
    channel_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    message_text TEXT NOT NULL,
    message_type ENUM('message', 'file', 'reaction', 'thread_reply') DEFAULT 'message',
    parent_message_id BIGINT NULL,  -- For thread replies
    thread_timestamp VARCHAR(20) NULL,  -- Slack-style thread timestamp
    is_thread_parent BOOLEAN DEFAULT FALSE,
    thread_reply_count INT DEFAULT 0,
    last_thread_reply_at TIMESTAMP NULL,
    attachments JSON,  -- File attachments, links, etc.
    reactions JSON,  -- Emoji reactions
    edited_at TIMESTAMP NULL,
    deleted_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_channel_message (channel_id, created_at),
    INDEX idx_user_messages (user_id, created_at),
    INDEX idx_parent_message (parent_message_id, created_at),
    INDEX idx_thread_timestamp (thread_timestamp),
    INDEX idx_thread_parent (is_thread_parent, last_thread_reply_at)
);

-- Message reactions
CREATE TABLE message_reactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    message_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    reaction_name VARCHAR(50) NOT NULL,  -- 'thumbsup', 'heart', etc.
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_message_user_reaction (message_id, user_id, reaction_name),
    INDEX idx_message_reactions (message_id, reaction_name),
    INDEX idx_user_reactions (user_id, added_at)
);
```

### The "Slack Workspace Management" Pattern
```sql
-- Workspace management
CREATE TABLE workspaces (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    workspace_id VARCHAR(20) UNIQUE NOT NULL,  -- 'T1234567890'
    workspace_name VARCHAR(100) NOT NULL,
    workspace_domain VARCHAR(100) UNIQUE NOT NULL,
    owner_id BIGINT NOT NULL,
    member_count INT DEFAULT 0,
    plan_type ENUM('free', 'pro', 'business', 'enterprise') DEFAULT 'free',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_workspace_domain (workspace_domain),
    INDEX idx_plan_type (plan_type, member_count),
    INDEX idx_owner (owner_id)
);

-- Workspace members
CREATE TABLE workspace_members (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    workspace_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    member_type ENUM('owner', 'admin', 'member', 'guest') DEFAULT 'member',
    display_name VARCHAR(100) NOT NULL,
    real_name VARCHAR(100),
    email VARCHAR(255) UNIQUE NOT NULL,
    timezone VARCHAR(50) DEFAULT 'UTC',
    status_text VARCHAR(255),
    status_emoji VARCHAR(20),
    is_bot BOOLEAN DEFAULT FALSE,
    is_restricted BOOLEAN DEFAULT FALSE,
    is_ultra_restricted BOOLEAN DEFAULT FALSE,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_workspace_user (workspace_id, user_id),
    INDEX idx_user_workspaces (user_id, member_type),
    INDEX idx_workspace_members (workspace_id, member_type),
    INDEX idx_email (email)
);
```

## 📝 Notion-Style Document Collaboration

### The "Block-Based Content" Pattern
```sql
-- Block-based content system
CREATE TABLE content_blocks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    block_id VARCHAR(50) UNIQUE NOT NULL,
    page_id BIGINT NOT NULL,
    block_type ENUM('text', 'heading', 'list', 'image', 'table', 'code', 'quote', 'divider') NOT NULL,
    block_content JSON NOT NULL,  -- Flexible content structure
    block_order INT NOT NULL,  -- For ordering within page
    parent_block_id BIGINT NULL,  -- For nested blocks
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_page_blocks (page_id, block_order),
    INDEX idx_parent_block (parent_block_id, block_order),
    INDEX idx_block_type (block_type, created_at),
    INDEX idx_created_by (created_by, created_at)
);

-- Page hierarchy
CREATE TABLE pages (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    page_id VARCHAR(50) UNIQUE NOT NULL,
    workspace_id BIGINT NOT NULL,
    title VARCHAR(255) NOT NULL,
    icon VARCHAR(20),  -- Emoji or icon
    cover_image_url VARCHAR(500),
    parent_page_id BIGINT NULL,  -- For hierarchical pages
    page_type ENUM('page', 'database', 'template') DEFAULT 'page',
    is_public BOOLEAN DEFAULT FALSE,
    is_archived BOOLEAN DEFAULT FALSE,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_workspace_pages (workspace_id, page_type, is_archived),
    INDEX idx_parent_page (parent_page_id),
    INDEX idx_created_by (created_by, created_at),
    FULLTEXT INDEX idx_page_search (title)
);

-- Real-time collaboration
CREATE TABLE collaboration_sessions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id VARCHAR(100) UNIQUE NOT NULL,
    page_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    cursor_position JSON,  -- Current cursor position
    selection_range JSON,  -- Text selection range
    is_active BOOLEAN DEFAULT TRUE,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_page_sessions (page_id, is_active),
    INDEX idx_user_sessions (user_id, is_active),
    INDEX idx_last_activity (last_activity)
);

-- Page permissions
CREATE TABLE page_permissions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    page_id BIGINT NOT NULL,
    user_id BIGINT NULL,  -- NULL for public access
    permission_type ENUM('full_access', 'can_edit', 'can_comment', 'can_view') DEFAULT 'can_view',
    granted_by BIGINT NOT NULL,
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_page_user (page_id, user_id),
    INDEX idx_user_permissions (user_id, permission_type),
    INDEX idx_page_permissions (page_id, permission_type)
);
```

## 🔄 GitHub-Style Version Control

### The "Repository Management" Pattern
```sql
-- Repository management
CREATE TABLE repositories (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    repo_id VARCHAR(50) UNIQUE NOT NULL,  -- 'owner/repo-name'
    owner_id BIGINT NOT NULL,
    repo_name VARCHAR(100) NOT NULL,
    description TEXT,
    is_private BOOLEAN DEFAULT FALSE,
    is_fork BOOLEAN DEFAULT FALSE,
    parent_repo_id BIGINT NULL,  -- For forked repositories
    default_branch VARCHAR(100) DEFAULT 'main',
    language VARCHAR(50),
    topics JSON,  -- Array of topics/tags
    star_count INT DEFAULT 0,
    fork_count INT DEFAULT 0,
    watch_count INT DEFAULT 0,
    size_bytes BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_owner_repos (owner_id, is_private),
    INDEX idx_repo_name (repo_name),
    INDEX idx_language (language, star_count),
    INDEX idx_topics ((CAST(topics->>'$.topics' AS CHAR(255))))
);

-- Repository collaborators
CREATE TABLE repo_collaborators (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    repo_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    permission ENUM('admin', 'maintain', 'write', 'triage', 'read') DEFAULT 'read',
    added_by BIGINT NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_repo_user (repo_id, user_id),
    INDEX idx_user_repos (user_id, permission),
    INDEX idx_repo_collaborators (repo_id, permission)
);

-- Issue and PR tracking
CREATE TABLE repository_issues (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    issue_number INT NOT NULL,
    repo_id BIGINT NOT NULL,
    issue_type ENUM('issue', 'pull_request') DEFAULT 'issue',
    title VARCHAR(255) NOT NULL,
    body TEXT,
    state ENUM('open', 'closed', 'merged') DEFAULT 'open',
    author_id BIGINT NOT NULL,
    assignee_id BIGINT NULL,
    milestone_id BIGINT NULL,
    labels JSON,
    comments_count INT DEFAULT 0,
    reactions_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    closed_at TIMESTAMP NULL,
    
    UNIQUE KEY uk_repo_issue (repo_id, issue_number),
    INDEX idx_repo_issues (repo_id, state, created_at),
    INDEX idx_author_issues (author_id, created_at),
    INDEX idx_assignee_issues (assignee_id, state),
    INDEX idx_milestone (milestone_id, state)
);
```

## 📊 Product Analytics Patterns

### The "Feature Usage Tracking" Pattern
```sql
-- Feature usage tracking
CREATE TABLE feature_usage (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    feature_name VARCHAR(100) NOT NULL,
    action_type VARCHAR(50) NOT NULL,  -- 'view', 'create', 'edit', 'delete'
    session_id VARCHAR(100) NULL,
    page_url VARCHAR(500) NULL,
    user_agent TEXT,
    ip_address VARCHAR(45),
    metadata JSON,  -- Additional context
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_user_feature (user_id, feature_name, created_at),
    INDEX idx_feature_usage (feature_name, action_type, created_at),
    INDEX idx_session (session_id, created_at)
);

-- Product analytics dashboard
CREATE VIEW product_analytics_summary AS
SELECT 
    feature_name,
    action_type,
    DATE(created_at) as usage_date,
    COUNT(*) as usage_count,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT session_id) as unique_sessions
FROM feature_usage
WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY feature_name, action_type, DATE(created_at)
ORDER BY feature_name, usage_date DESC;
```

These product-specific patterns show the real-world techniques that product engineers use to build domain-specific features for collaboration, messaging, and productivity tools! 🚀
