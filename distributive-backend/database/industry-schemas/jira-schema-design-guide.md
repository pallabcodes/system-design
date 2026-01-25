# Atlassian JIRA: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: RBAC, Workflows, Permission Schemes, Custom Fields — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Storing permissions inline with entities. JIRA's genius is the *scheme-based* architecture — define once, apply to many projects.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Atlassian entitymodel.xml](https://confluence.atlassian.com/jira/database-schema-754915558.html) | Official schema reference |
| [Zanzibar: Google's Auth System](https://research.google/pubs/pub48190/) | Relationship-based ACL |
| [RBAC (NIST)](https://csrc.nist.gov/projects/role-based-access-control) | Role-Based Access Control standard |

---

## 🎯 The Principal Laws of JIRA Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Scheme Indirection** | Permissions → Schemes → Projects | Change one scheme, affect 100 projects |
| **Law 2: Context Is King** | Custom field visibility = f(project, issue type) | `fieldconfigurationscheme` + `configurationcontext` |
| **Law 3: Workflow Per Issue Type** | Not one workflow per project | `workflowscheme` maps (project, issuetype) → workflow |
| **Law 4: Roles ≠ Groups** | Project roles are per-project | Groups are global, roles are contextual |

---

# Part 1: Access Pattern Analysis

Before designing tables, we **start with queries**. These are the 10 most critical access patterns:

| # | Access Pattern | Frequency | Latency SLA |
| :--- | :--- | :--- | :--- |
| 1 | Get issues in project by status | 1000/s | < 50ms |
| 2 | Can user X perform action Y on issue Z? | 10000/s | < 10ms |
| 3 | Get user's visible projects | 500/s | < 100ms |
| 4 | Transition issue (workflow) | 200/s | < 200ms |
| 5 | Get sprint backlog with rank | 300/s | < 50ms |
| 6 | Search issues by JQL | 100/s | < 500ms |
| 7 | Get custom field values for issue | 2000/s | < 20ms |
| 8 | Get project permission scheme | 100/s | < 10ms |
| 9 | Get workflow for (project, issue type) | 500/s | < 10ms |
| 10 | Bulk update issue assignee | 10/s | < 2s |

---

# Part 2: NoSQL Design (DynamoDB Single-Table)

## 🔑 Partition Key Strategy

JIRA's data is **project-centric** with **user access patterns**. We use a composite key design.

```
┌─────────────────────────────────────────────────────────────────┐
│                    SINGLE-TABLE DESIGN                          │
├─────────────────────────────────────────────────────────────────┤
│ Entity         │ PK                  │ SK                       │
├────────────────┼─────────────────────┼──────────────────────────┤
│ Project        │ ORG#<org_id>        │ PROJECT#<project_key>    │
│ Issue          │ PROJECT#<key>       │ ISSUE#<issue_key>        │
│ Comment        │ ISSUE#<issue_key>   │ COMMENT#<timestamp>#<id> │
│ Worklog        │ ISSUE#<issue_key>   │ WORKLOG#<timestamp>#<id> │
│ Sprint         │ BOARD#<board_id>    │ SPRINT#<sprint_id>       │
│ SprintIssue    │ SPRINT#<sprint_id>  │ RANK#<rank>#ISSUE#<key>  │
│ UserProject    │ USER#<user_id>      │ PROJECT#<project_key>    │
│ PermScheme     │ ORG#<org_id>        │ PERMSCHEME#<scheme_id>   │
│ SchemeMapping  │ PROJECT#<key>       │ SCHEME#<type>            │
└─────────────────────────────────────────────────────────────────┘
```

## 📐 DynamoDB DDL

```python
# Terraform / CloudFormation equivalent
{
  "TableName": "jira-main",
  "KeySchema": [
    {"AttributeName": "PK", "KeyType": "HASH"},
    {"AttributeName": "SK", "KeyType": "RANGE"}
  ],
  "AttributeDefinitions": [
    {"AttributeName": "PK", "AttributeType": "S"},
    {"AttributeName": "SK", "AttributeType": "S"},
    {"AttributeName": "GSI1PK", "AttributeType": "S"},
    {"AttributeName": "GSI1SK", "AttributeType": "S"},
    {"AttributeName": "GSI2PK", "AttributeType": "S"},
    {"AttributeName": "GSI2SK", "AttributeType": "S"}
  ],
  "GlobalSecondaryIndexes": [
    {
      "IndexName": "GSI1",  # Issues by assignee
      "KeySchema": [
        {"AttributeName": "GSI1PK", "KeyType": "HASH"},  # USER#<assignee>
        {"AttributeName": "GSI1SK", "KeyType": "RANGE"}  # STATUS#<status>#ISSUE#<key>
      ],
      "Projection": {"ProjectionType": "ALL"}
    },
    {
      "IndexName": "GSI2",  # Issues by status across project
      "KeySchema": [
        {"AttributeName": "GSI2PK", "KeyType": "HASH"},  # PROJECT#<key>#STATUS#<status>
        {"AttributeName": "GSI2SK", "KeyType": "RANGE"}  # UPDATED#<timestamp>
      ],
      "Projection": {"ProjectionType": "KEYS_ONLY"}
    }
  ],
  "BillingMode": "PAY_PER_REQUEST"
}
```

## 📝 Issue Item Example

```json
{
  "PK": "PROJECT#ACME",
  "SK": "ISSUE#ACME-1234",
  "GSI1PK": "USER#john.doe",
  "GSI1SK": "STATUS#IN_PROGRESS#ISSUE#ACME-1234",
  "GSI2PK": "PROJECT#ACME#STATUS#IN_PROGRESS",
  "GSI2SK": "UPDATED#2024-01-15T10:30:00Z",
  
  "entity_type": "ISSUE",
  "issue_key": "ACME-1234",
  "project_key": "ACME",
  "issue_type": "BUG",
  "summary": "Login button not working",
  "description": "...",
  "status": "IN_PROGRESS",
  "priority": "HIGH",
  "assignee_id": "john.doe",
  "reporter_id": "jane.smith",
  "created_at": "2024-01-10T08:00:00Z",
  "updated_at": "2024-01-15T10:30:00Z",
  "resolution": null,
  "labels": ["frontend", "urgent"],
  "components": ["auth-service"],
  "fix_versions": ["2.1.0"],
  "sprint_id": "SPRINT-42",
  "story_points": 5,
  "rank": "0|hzzzzz:"
}
```

## 🔍 Query Patterns (DynamoDB)

### Pattern 1: Get all issues in project by status
```python
response = table.query(
    KeyConditionExpression="PK = :pk AND begins_with(SK, :sk)",
    FilterExpression="status = :status",
    ExpressionAttributeValues={
        ":pk": "PROJECT#ACME",
        ":sk": "ISSUE#",
        ":status": "IN_PROGRESS"
    }
)
# OR use GSI2 for optimized status queries:
response = table.query(
    IndexName="GSI2",
    KeyConditionExpression="GSI2PK = :pk",
    ExpressionAttributeValues={
        ":pk": "PROJECT#ACME#STATUS#IN_PROGRESS"
    },
    ScanIndexForward=False,  # Most recently updated first
    Limit=50
)
```

### Pattern 2: Get user's assigned issues
```python
response = table.query(
    IndexName="GSI1",
    KeyConditionExpression="GSI1PK = :pk AND begins_with(GSI1SK, :sk)",
    ExpressionAttributeValues={
        ":pk": "USER#john.doe",
        ":sk": "STATUS#"
    }
)
```

---

# Part 3: SQL Design (PostgreSQL)

## 📊 Entity Relationship Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         JIRA CORE SCHEMA                                  │
└──────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │   cwd_user      │
                    │ (Crowd/Users)   │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                              ▼
     ┌─────────────────┐           ┌─────────────────┐
     │   cwd_group     │           │  project_role   │
     │ (Global Groups) │           │ (Per-Project)   │
     └────────┬────────┘           └────────┬────────┘
              │                              │
              ▼                              ▼
     ┌─────────────────┐           ┌─────────────────┐
     │ cwd_membership  │           │  role_actor     │
     │ (User ↔ Group)  │           │ (User/Group →   │
     └─────────────────┘           │  Project Role)  │
                                   └────────┬────────┘
                                            │
┌─────────────────┐                         │
│    project      │◄────────────────────────┘
│                 │
│ • permission_   │──────┐
│   scheme_id     │      │
│ • workflow_     │      │
│   scheme_id     │      │
│ • notification_ │      │
│   scheme_id     │      │
└────────┬────────┘      │
         │               │
         ▼               ▼
┌─────────────────┐  ┌─────────────────┐
│   jiraissue     │  │ permission_     │
│                 │  │ scheme          │
│ • project_id    │  │                 │
│ • issue_type    │  │ → scheme_       │
│ • status        │  │   permissions   │
│ • assignee      │  └─────────────────┘
│ • reporter      │
└────────┬────────┘
         │
    ┌────┴────┬──────────┬──────────┐
    ▼         ▼          ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────────┐
│comment │ │worklog │ │issue_  │ │customfield │
│        │ │        │ │link    │ │value       │
└────────┘ └────────┘ └────────┘ └────────────┘
```

---

## 🗄️ Complete DDL

### Core User/Group Tables (Embedded Crowd)

```sql
-- ============================================================
-- JIRA SCHEMA: PostgreSQL Production DDL
-- Version: Compatible with JIRA 9.x
-- ============================================================

-- ===========================================
-- SECTION 1: USERS AND GROUPS (Embedded Crowd)
-- ===========================================

CREATE TABLE cwd_directory (
    id                  BIGINT PRIMARY KEY,
    directory_name      VARCHAR(255) NOT NULL,
    directory_type      VARCHAR(60) NOT NULL,  -- 'INTERNAL', 'LDAP', 'CROWD'
    active              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE cwd_user (
    id                  BIGINT PRIMARY KEY,
    directory_id        BIGINT NOT NULL REFERENCES cwd_directory(id),
    user_name           VARCHAR(255) NOT NULL,
    lower_user_name     VARCHAR(255) NOT NULL,
    display_name        VARCHAR(255),
    email_address       VARCHAR(255),
    active              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_cwd_user_lower_name_dir UNIQUE (lower_user_name, directory_id)
);

CREATE INDEX idx_cwd_user_email ON cwd_user(email_address);
CREATE INDEX idx_cwd_user_active ON cwd_user(active) WHERE active = TRUE;

CREATE TABLE cwd_group (
    id                  BIGINT PRIMARY KEY,
    directory_id        BIGINT NOT NULL REFERENCES cwd_directory(id),
    group_name          VARCHAR(255) NOT NULL,
    lower_group_name    VARCHAR(255) NOT NULL,
    description         TEXT,
    group_type          VARCHAR(60) DEFAULT 'GROUP',
    active              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_cwd_group_name_dir UNIQUE (lower_group_name, directory_id)
);

CREATE TABLE cwd_membership (
    id                  BIGINT PRIMARY KEY,
    parent_id           BIGINT NOT NULL REFERENCES cwd_group(id),
    child_user_id       BIGINT REFERENCES cwd_user(id),
    child_group_id      BIGINT REFERENCES cwd_group(id),
    membership_type     VARCHAR(20) NOT NULL DEFAULT 'GROUP_USER',  -- 'GROUP_USER', 'GROUP_GROUP'
    
    CONSTRAINT ck_membership_xor CHECK (
        (child_user_id IS NOT NULL AND child_group_id IS NULL) OR
        (child_user_id IS NULL AND child_group_id IS NOT NULL)
    ),
    CONSTRAINT uk_membership UNIQUE (parent_id, child_user_id, child_group_id)
);

CREATE INDEX idx_membership_user ON cwd_membership(child_user_id) WHERE child_user_id IS NOT NULL;
CREATE INDEX idx_membership_group ON cwd_membership(parent_id);


-- ===========================================
-- SECTION 2: PROJECT ROLES
-- ===========================================

CREATE TABLE project_role (
    id                  BIGINT PRIMARY KEY,
    name                VARCHAR(255) NOT NULL UNIQUE,
    description         TEXT,
    role_type           VARCHAR(60) DEFAULT 'PROJECT_ROLE'
);

-- Default project roles
INSERT INTO project_role (id, name, description) VALUES
    (10002, 'Administrators', 'A project role for project administrators'),
    (10001, 'Developers', 'A project role for developers'),
    (10000, 'Users', 'A project role for users');

CREATE TABLE role_actor (
    id                  BIGINT PRIMARY KEY,
    project_role_id     BIGINT NOT NULL REFERENCES project_role(id),
    project_id          BIGINT NOT NULL,  -- FK to project added after project table
    role_type           VARCHAR(60) NOT NULL,  -- 'atlassian-user-role-actor', 'atlassian-group-role-actor'
    role_type_parameter VARCHAR(255) NOT NULL,  -- user_key or group_name
    
    CONSTRAINT uk_role_actor UNIQUE (project_role_id, project_id, role_type, role_type_parameter)
);

CREATE INDEX idx_role_actor_project ON role_actor(project_id);
CREATE INDEX idx_role_actor_parameter ON role_actor(role_type_parameter);


-- ===========================================
-- SECTION 3: PERMISSION SCHEMES
-- ===========================================

CREATE TABLE permission_scheme (
    id                  BIGINT PRIMARY KEY,
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    default_scheme      BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Default scheme
INSERT INTO permission_scheme (id, name, description, default_scheme) VALUES
    (0, 'Default Permission Scheme', 'Default permissions for all projects', TRUE);

CREATE TABLE scheme_permissions (
    id                  BIGINT PRIMARY KEY,
    scheme_id           BIGINT NOT NULL REFERENCES permission_scheme(id) ON DELETE CASCADE,
    permission_key      VARCHAR(64) NOT NULL,  -- 'BROWSE_PROJECTS', 'CREATE_ISSUES', 'EDIT_ISSUES', etc.
    permission_type     VARCHAR(64) NOT NULL,  -- 'group', 'projectrole', 'user', 'assignee', 'reporter'
    parameter           VARCHAR(255),          -- group name, role id, or user key
    
    CONSTRAINT uk_scheme_perm UNIQUE (scheme_id, permission_key, permission_type, parameter)
);

CREATE INDEX idx_scheme_perm_key ON scheme_permissions(permission_key);
CREATE INDEX idx_scheme_perm_scheme ON scheme_permissions(scheme_id);

-- Permission Key Reference (JIRA Standard)
COMMENT ON COLUMN scheme_permissions.permission_key IS 
'Standard JIRA permissions:
PROJECT: ADMINISTER_PROJECTS, BROWSE_PROJECTS
ISSUES: CREATE_ISSUES, EDIT_ISSUES, TRANSITION_ISSUES, SCHEDULE_ISSUES, MOVE_ISSUES, 
        ASSIGN_ISSUES, ASSIGNABLE_USER, RESOLVE_ISSUES, CLOSE_ISSUES, MODIFY_REPORTER,
        DELETE_ISSUES, LINK_ISSUES, SET_ISSUE_SECURITY, VIEW_DEV_TOOLS,
        VIEW_READONLY_WORKFLOW, MANAGE_WATCHERS, EDIT_ALL_WORKLOGS, 
        EDIT_OWN_WORKLOGS, DELETE_ALL_WORKLOGS, DELETE_OWN_WORKLOGS,
        WORK_ON_ISSUES, ADD_COMMENTS, EDIT_ALL_COMMENTS, EDIT_OWN_COMMENTS,
        DELETE_ALL_COMMENTS, DELETE_OWN_COMMENTS, CREATE_ATTACHMENTS,
        DELETE_ALL_ATTACHMENTS, DELETE_OWN_ATTACHMENTS';

-- Example: Allow group 'jira-developers' to create issues
INSERT INTO scheme_permissions (id, scheme_id, permission_key, permission_type, parameter) VALUES
    (1, 0, 'BROWSE_PROJECTS', 'group', 'jira-users'),
    (2, 0, 'CREATE_ISSUES', 'group', 'jira-users'),
    (3, 0, 'EDIT_ISSUES', 'projectrole', '10001'),  -- Developers role
    (4, 0, 'TRANSITION_ISSUES', 'projectrole', '10001'),
    (5, 0, 'ASSIGN_ISSUES', 'projectrole', '10001'),
    (6, 0, 'ADMINISTER_PROJECTS', 'projectrole', '10002');  -- Administrators role


-- ===========================================
-- SECTION 4: WORKFLOW SCHEMES
-- ===========================================

CREATE TABLE workflow (
    id                  BIGINT PRIMARY KEY,
    workflow_name       VARCHAR(255) NOT NULL UNIQUE,
    description         TEXT,
    is_default          BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE workflow_step (
    id                  BIGINT PRIMARY KEY,
    workflow_id         BIGINT NOT NULL REFERENCES workflow(id) ON DELETE CASCADE,
    step_name           VARCHAR(255) NOT NULL,
    linked_status_id    BIGINT NOT NULL,  -- FK to issue_status
    step_order          INT NOT NULL DEFAULT 0,
    
    CONSTRAINT uk_workflow_step UNIQUE (workflow_id, linked_status_id)
);

CREATE TABLE workflow_transition (
    id                  BIGINT PRIMARY KEY,
    workflow_id         BIGINT NOT NULL REFERENCES workflow(id) ON DELETE CASCADE,
    transition_name     VARCHAR(255) NOT NULL,
    from_step_id        BIGINT REFERENCES workflow_step(id),  -- NULL = initial transition
    to_step_id          BIGINT NOT NULL REFERENCES workflow_step(id),
    screen_id           BIGINT,  -- Optional transition screen
    
    CONSTRAINT uk_workflow_trans UNIQUE (workflow_id, from_step_id, to_step_id)
);

CREATE TABLE workflow_transition_condition (
    id                  BIGINT PRIMARY KEY,
    transition_id       BIGINT NOT NULL REFERENCES workflow_transition(id) ON DELETE CASCADE,
    condition_type      VARCHAR(255) NOT NULL,  -- Plugin key, e.g., 'jira.permission.condition'
    condition_config    JSONB  -- Condition-specific configuration
);

CREATE TABLE workflow_scheme (
    id                  BIGINT PRIMARY KEY,
    name                VARCHAR(255) NOT NULL UNIQUE,
    description         TEXT,
    default_workflow_id BIGINT REFERENCES workflow(id),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE workflow_scheme_entity (
    id                  BIGINT PRIMARY KEY,
    scheme_id           BIGINT NOT NULL REFERENCES workflow_scheme(id) ON DELETE CASCADE,
    issue_type_id       VARCHAR(255),  -- NULL = default mapping
    workflow_id         BIGINT NOT NULL REFERENCES workflow(id),
    
    CONSTRAINT uk_wf_scheme_entity UNIQUE (scheme_id, issue_type_id)
);


-- ===========================================
-- SECTION 5: ISSUE TYPES AND STATUSES
-- ===========================================

CREATE TABLE issue_type (
    id                  VARCHAR(60) PRIMARY KEY,  -- UUID or numeric string
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    icon_url            VARCHAR(500),
    is_subtask          BOOLEAN DEFAULT FALSE,
    style               VARCHAR(60) DEFAULT 'default',  -- 'default', 'subtask'
    sequence            INT NOT NULL DEFAULT 0
);

-- Default issue types
INSERT INTO issue_type (id, name, description, is_subtask, sequence) VALUES
    ('10001', 'Bug', 'A problem which impairs or prevents functions', FALSE, 1),
    ('10002', 'Task', 'A task that needs to be done', FALSE, 2),
    ('10003', 'Story', 'A user story', FALSE, 3),
    ('10004', 'Epic', 'A collection of related Stories', FALSE, 4),
    ('10005', 'Sub-task', 'A sub-task of an issue', TRUE, 5);

CREATE TABLE issue_status (
    id                  BIGINT PRIMARY KEY,
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    icon_url            VARCHAR(500),
    status_category_id  INT NOT NULL DEFAULT 2,  -- 1=To Do, 2=In Progress, 3=Done
    sequence            INT NOT NULL DEFAULT 0
);

-- Default statuses
INSERT INTO issue_status (id, name, status_category_id, sequence) VALUES
    (1, 'Open', 1, 1),
    (3, 'In Progress', 2, 2),
    (4, 'Reopened', 1, 3),
    (5, 'Resolved', 3, 4),
    (6, 'Closed', 3, 5),
    (10001, 'To Do', 1, 6),
    (10002, 'Done', 3, 7);


-- ===========================================
-- SECTION 6: PROJECTS
-- ===========================================

CREATE TABLE project_category (
    id                  BIGINT PRIMARY KEY,
    name                VARCHAR(255) NOT NULL UNIQUE,
    description         TEXT
);

CREATE TABLE project (
    id                  BIGINT PRIMARY KEY,
    project_key         VARCHAR(10) NOT NULL UNIQUE,
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    lead_user_id        BIGINT REFERENCES cwd_user(id),
    url                 VARCHAR(500),
    project_type_key    VARCHAR(60) DEFAULT 'software',  -- 'software', 'service_desk', 'business'
    category_id         BIGINT REFERENCES project_category(id),
    
    -- Scheme associations
    permission_scheme_id     BIGINT REFERENCES permission_scheme(id),
    workflow_scheme_id       BIGINT REFERENCES workflow_scheme(id),
    notification_scheme_id   BIGINT,
    issue_type_scheme_id     BIGINT,
    field_config_scheme_id   BIGINT,
    issue_security_scheme_id BIGINT,
    
    counter             BIGINT NOT NULL DEFAULT 0,  -- For issue numbering
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_project_key ON project(project_key);
CREATE INDEX idx_project_lead ON project(lead_user_id);
CREATE INDEX idx_project_perm_scheme ON project(permission_scheme_id);

-- Add FK to role_actor now that project exists
ALTER TABLE role_actor ADD CONSTRAINT fk_role_actor_project 
    FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


-- ===========================================
-- SECTION 7: ISSUES
-- ===========================================

CREATE TABLE jiraissue (
    id                  BIGINT PRIMARY KEY,
    project_id          BIGINT NOT NULL REFERENCES project(id),
    issue_num           BIGINT NOT NULL,  -- The number part of PROJ-123
    issue_type_id       VARCHAR(60) NOT NULL REFERENCES issue_type(id),
    summary             VARCHAR(500) NOT NULL,
    description         TEXT,
    
    -- Status and workflow
    status_id           BIGINT NOT NULL REFERENCES issue_status(id),
    resolution_id       BIGINT,
    resolution_date     TIMESTAMP WITH TIME ZONE,
    
    -- People
    reporter_id         BIGINT REFERENCES cwd_user(id),
    assignee_id         BIGINT REFERENCES cwd_user(id),
    
    -- Priority and severity
    priority_id         BIGINT NOT NULL DEFAULT 3,
    security_level_id   BIGINT,
    
    -- Hierarchy
    parent_id           BIGINT REFERENCES jiraissue(id),
    epic_id             BIGINT REFERENCES jiraissue(id),
    
    -- Time tracking
    original_estimate   BIGINT,  -- seconds
    time_spent          BIGINT,  -- seconds
    remaining_estimate  BIGINT,  -- seconds
    
    -- Planning
    story_points        DECIMAL(10,2),
    rank                VARCHAR(255),  -- LexoRank for ordering
    
    -- Dates
    due_date            DATE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Version tracking (optimistic locking)
    version             BIGINT NOT NULL DEFAULT 0,
    
    CONSTRAINT uk_issue_key UNIQUE (project_id, issue_num)
);

-- Critical indexes for performance
CREATE INDEX idx_issue_project ON jiraissue(project_id);
CREATE INDEX idx_issue_status ON jiraissue(status_id);
CREATE INDEX idx_issue_assignee ON jiraissue(assignee_id) WHERE assignee_id IS NOT NULL;
CREATE INDEX idx_issue_reporter ON jiraissue(reporter_id);
CREATE INDEX idx_issue_type ON jiraissue(issue_type_id);
CREATE INDEX idx_issue_created ON jiraissue(created_at DESC);
CREATE INDEX idx_issue_updated ON jiraissue(updated_at DESC);
CREATE INDEX idx_issue_epic ON jiraissue(epic_id) WHERE epic_id IS NOT NULL;
CREATE INDEX idx_issue_parent ON jiraissue(parent_id) WHERE parent_id IS NOT NULL;

-- Composite index for common dashboard query
CREATE INDEX idx_issue_project_status ON jiraissue(project_id, status_id);
CREATE INDEX idx_issue_assignee_status ON jiraissue(assignee_id, status_id) WHERE assignee_id IS NOT NULL;

-- GIN index for full-text search
CREATE INDEX idx_issue_summary_fts ON jiraissue USING GIN (to_tsvector('english', summary));


-- ===========================================
-- SECTION 8: ISSUE RELATIONSHIPS
-- ===========================================

CREATE TABLE issue_link_type (
    id                  BIGINT PRIMARY KEY,
    link_name           VARCHAR(255) NOT NULL,
    inward_description  VARCHAR(255) NOT NULL,   -- "is blocked by"
    outward_description VARCHAR(255) NOT NULL,   -- "blocks"
    style               VARCHAR(60) DEFAULT 'default'
);

INSERT INTO issue_link_type (id, link_name, inward_description, outward_description) VALUES
    (10000, 'Blocks', 'is blocked by', 'blocks'),
    (10001, 'Cloners', 'is cloned by', 'clones'),
    (10002, 'Duplicate', 'is duplicated by', 'duplicates'),
    (10003, 'Relates', 'relates to', 'relates to');

CREATE TABLE issue_link (
    id                  BIGINT PRIMARY KEY,
    link_type_id        BIGINT NOT NULL REFERENCES issue_link_type(id),
    source_issue_id     BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    destination_issue_id BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_issue_link UNIQUE (link_type_id, source_issue_id, destination_issue_id),
    CONSTRAINT ck_no_self_link CHECK (source_issue_id != destination_issue_id)
);

CREATE INDEX idx_issue_link_source ON issue_link(source_issue_id);
CREATE INDEX idx_issue_link_dest ON issue_link(destination_issue_id);


-- ===========================================
-- SECTION 9: COMMENTS AND WORKLOGS
-- ===========================================

CREATE TABLE issue_comment (
    id                  BIGINT PRIMARY KEY,
    issue_id            BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    author_id           BIGINT NOT NULL REFERENCES cwd_user(id),
    update_author_id    BIGINT REFERENCES cwd_user(id),
    body                TEXT NOT NULL,
    visibility_type     VARCHAR(60),  -- 'group', 'role'
    visibility_value    VARCHAR(255),  -- group name or role id
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_comment_issue ON issue_comment(issue_id);
CREATE INDEX idx_comment_author ON issue_comment(author_id);
CREATE INDEX idx_comment_created ON issue_comment(created_at DESC);

CREATE TABLE worklog (
    id                  BIGINT PRIMARY KEY,
    issue_id            BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    author_id           BIGINT NOT NULL REFERENCES cwd_user(id),
    update_author_id    BIGINT REFERENCES cwd_user(id),
    time_spent          BIGINT NOT NULL,  -- seconds
    start_date          TIMESTAMP WITH TIME ZONE NOT NULL,
    work_description    TEXT,
    visibility_type     VARCHAR(60),
    visibility_value    VARCHAR(255),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_worklog_issue ON worklog(issue_id);
CREATE INDEX idx_worklog_author ON worklog(author_id);


-- ===========================================
-- SECTION 10: CUSTOM FIELDS
-- ===========================================

CREATE TABLE custom_field (
    id                  BIGINT PRIMARY KEY,
    field_name          VARCHAR(255) NOT NULL,
    field_type_key      VARCHAR(255) NOT NULL,  -- 'com.atlassian.jira.plugin.system.customfieldtypes:textfield'
    description         TEXT,
    default_value       TEXT,
    is_global           BOOLEAN DEFAULT TRUE,  -- Available in all projects
    is_required         BOOLEAN DEFAULT FALSE,
    search_key          VARCHAR(255) UNIQUE,   -- 'cf[10001]'
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Custom field configuration context (which projects/issue types)
CREATE TABLE field_configuration_context (
    id                  BIGINT PRIMARY KEY,
    custom_field_id     BIGINT NOT NULL REFERENCES custom_field(id) ON DELETE CASCADE,
    project_id          BIGINT REFERENCES project(id),  -- NULL = all projects
    issue_type_id       VARCHAR(60) REFERENCES issue_type(id),  -- NULL = all issue types
    
    CONSTRAINT uk_field_context UNIQUE (custom_field_id, project_id, issue_type_id)
);

-- Custom field values (EAV pattern - necessary for flexibility)
CREATE TABLE custom_field_value (
    id                  BIGINT PRIMARY KEY,
    issue_id            BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    custom_field_id     BIGINT NOT NULL REFERENCES custom_field(id) ON DELETE CASCADE,
    
    -- Value columns (only one populated based on field type)
    string_value        TEXT,
    number_value        DECIMAL(18,6),
    date_value          TIMESTAMP WITH TIME ZONE,
    text_value          TEXT,
    option_id           BIGINT,  -- For select/radio fields
    
    parent_key          VARCHAR(255),  -- For cascading selects
    
    CONSTRAINT uk_cf_value UNIQUE (issue_id, custom_field_id, parent_key)
);

CREATE INDEX idx_cfv_issue ON custom_field_value(issue_id);
CREATE INDEX idx_cfv_field ON custom_field_value(custom_field_id);
CREATE INDEX idx_cfv_string ON custom_field_value(custom_field_id, string_value) WHERE string_value IS NOT NULL;
CREATE INDEX idx_cfv_number ON custom_field_value(custom_field_id, number_value) WHERE number_value IS NOT NULL;

-- Custom field options (for select lists)
CREATE TABLE custom_field_option (
    id                  BIGINT PRIMARY KEY,
    custom_field_id     BIGINT NOT NULL REFERENCES custom_field(id) ON DELETE CASCADE,
    parent_option_id    BIGINT REFERENCES custom_field_option(id),  -- For cascading
    option_value        VARCHAR(255) NOT NULL,
    sequence            INT NOT NULL DEFAULT 0,
    disabled            BOOLEAN DEFAULT FALSE
);


-- ===========================================
-- SECTION 11: AGILE (BOARDS AND SPRINTS)
-- ===========================================

CREATE TABLE agile_board (
    id                  BIGINT PRIMARY KEY,
    name                VARCHAR(255) NOT NULL,
    board_type          VARCHAR(60) NOT NULL,  -- 'scrum', 'kanban'
    owner_id            BIGINT REFERENCES cwd_user(id),
    filter_id           BIGINT NOT NULL,  -- Saved filter defining board scope
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE board_project (
    board_id            BIGINT NOT NULL REFERENCES agile_board(id) ON DELETE CASCADE,
    project_id          BIGINT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    PRIMARY KEY (board_id, project_id)
);

CREATE TABLE sprint (
    id                  BIGINT PRIMARY KEY,
    board_id            BIGINT NOT NULL REFERENCES agile_board(id) ON DELETE CASCADE,
    name                VARCHAR(255) NOT NULL,
    goal                TEXT,
    state               VARCHAR(60) NOT NULL DEFAULT 'FUTURE',  -- 'FUTURE', 'ACTIVE', 'CLOSED'
    start_date          TIMESTAMP WITH TIME ZONE,
    end_date            TIMESTAMP WITH TIME ZONE,
    complete_date       TIMESTAMP WITH TIME ZONE,
    sequence            INT NOT NULL DEFAULT 0
);

CREATE INDEX idx_sprint_board ON sprint(board_id);
CREATE INDEX idx_sprint_state ON sprint(state);

CREATE TABLE sprint_issue (
    sprint_id           BIGINT NOT NULL REFERENCES sprint(id) ON DELETE CASCADE,
    issue_id            BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    rank                VARCHAR(255),  -- LexoRank
    added_at            TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (sprint_id, issue_id)
);

CREATE INDEX idx_sprint_issue_rank ON sprint_issue(sprint_id, rank);


-- ===========================================
-- SECTION 12: LABELS AND COMPONENTS
-- ===========================================

CREATE TABLE label (
    id                  BIGINT PRIMARY KEY,
    issue_id            BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    label_text          VARCHAR(255) NOT NULL,
    
    CONSTRAINT uk_label UNIQUE (issue_id, label_text)
);

CREATE INDEX idx_label_text ON label(label_text);
CREATE INDEX idx_label_issue ON label(issue_id);

CREATE TABLE component (
    id                  BIGINT PRIMARY KEY,
    project_id          BIGINT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    component_name      VARCHAR(255) NOT NULL,
    description         TEXT,
    lead_user_id        BIGINT REFERENCES cwd_user(id),
    assignee_type       VARCHAR(60) DEFAULT 'PROJECT_DEFAULT',  -- 'PROJECT_DEFAULT', 'COMPONENT_LEAD', 'PROJECT_LEAD', 'UNASSIGNED'
    
    CONSTRAINT uk_component UNIQUE (project_id, component_name)
);

CREATE TABLE issue_component (
    issue_id            BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    component_id        BIGINT NOT NULL REFERENCES component(id) ON DELETE CASCADE,
    PRIMARY KEY (issue_id, component_id)
);


-- ===========================================
-- SECTION 13: VERSIONS (FIX/AFFECTS)
-- ===========================================

CREATE TABLE project_version (
    id                  BIGINT PRIMARY KEY,
    project_id          BIGINT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    version_name        VARCHAR(255) NOT NULL,
    description         TEXT,
    sequence            INT,
    released            BOOLEAN DEFAULT FALSE,
    archived            BOOLEAN DEFAULT FALSE,
    release_date        DATE,
    start_date          DATE,
    
    CONSTRAINT uk_version UNIQUE (project_id, version_name)
);

CREATE TABLE issue_fix_version (
    issue_id            BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    version_id          BIGINT NOT NULL REFERENCES project_version(id) ON DELETE CASCADE,
    PRIMARY KEY (issue_id, version_id)
);

CREATE TABLE issue_affects_version (
    issue_id            BIGINT NOT NULL REFERENCES jiraissue(id) ON DELETE CASCADE,
    version_id          BIGINT NOT NULL REFERENCES project_version(id) ON DELETE CASCADE,
    PRIMARY KEY (issue_id, version_id)
);
```

---

# Part 4: Permission Check Algorithm

The most critical query in JIRA: **Can user X do action Y on issue Z?**

```sql
-- ============================================================
-- PERMISSION CHECK: Can user browse issues in a project?
-- ============================================================

CREATE OR REPLACE FUNCTION check_permission(
    p_user_id BIGINT,
    p_permission_key VARCHAR,
    p_project_id BIGINT,
    p_issue_id BIGINT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_has_permission BOOLEAN := FALSE;
    v_scheme_id BIGINT;
BEGIN
    -- 1. Get the permission scheme for the project
    SELECT permission_scheme_id INTO v_scheme_id
    FROM project WHERE id = p_project_id;
    
    -- 2. Check each permission granting mechanism
    SELECT EXISTS (
        SELECT 1 FROM scheme_permissions sp
        WHERE sp.scheme_id = v_scheme_id
          AND sp.permission_key = p_permission_key
          AND (
              -- Grant to group
              (sp.permission_type = 'group' AND EXISTS (
                  SELECT 1 FROM cwd_membership cm
                  JOIN cwd_group g ON cm.parent_id = g.id
                  WHERE cm.child_user_id = p_user_id
                    AND g.lower_group_name = LOWER(sp.parameter)
              ))
              OR
              -- Grant to project role
              (sp.permission_type = 'projectrole' AND EXISTS (
                  SELECT 1 FROM role_actor ra
                  WHERE ra.project_id = p_project_id
                    AND ra.project_role_id = sp.parameter::BIGINT
                    AND (
                        (ra.role_type = 'atlassian-user-role-actor' 
                         AND ra.role_type_parameter = (SELECT user_name FROM cwd_user WHERE id = p_user_id))
                        OR
                        (ra.role_type = 'atlassian-group-role-actor' AND EXISTS (
                            SELECT 1 FROM cwd_membership cm
                            JOIN cwd_group g ON cm.parent_id = g.id
                            WHERE cm.child_user_id = p_user_id
                              AND g.lower_group_name = LOWER(ra.role_type_parameter)
                        ))
                    )
              ))
              OR
              -- Grant to reporter (issue-level)
              (sp.permission_type = 'reporter' AND p_issue_id IS NOT NULL AND EXISTS (
                  SELECT 1 FROM jiraissue WHERE id = p_issue_id AND reporter_id = p_user_id
              ))
              OR
              -- Grant to assignee (issue-level)
              (sp.permission_type = 'assignee' AND p_issue_id IS NOT NULL AND EXISTS (
                  SELECT 1 FROM jiraissue WHERE id = p_issue_id AND assignee_id = p_user_id
              ))
              OR
              -- Grant to specific user
              (sp.permission_type = 'user' AND EXISTS (
                  SELECT 1 FROM cwd_user WHERE id = p_user_id AND user_name = sp.parameter
              ))
          )
    ) INTO v_has_permission;
    
    RETURN v_has_permission;
END;
$$ LANGUAGE plpgsql STABLE;

-- Usage:
-- SELECT check_permission(123, 'BROWSE_PROJECTS', 456);
-- SELECT check_permission(123, 'EDIT_ISSUES', 456, 789);
```

---

# Part 5: Common Queries with EXPLAIN

### Query 1: Get user's visible projects

```sql
-- Get all projects a user can browse
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.project_key, p.name
FROM project p
WHERE check_permission(:user_id, 'BROWSE_PROJECTS', p.id);

-- Optimized version with materialized permissions
CREATE MATERIALIZED VIEW user_project_access AS
SELECT DISTINCT 
    u.id AS user_id,
    p.id AS project_id,
    p.project_key,
    p.name AS project_name
FROM cwd_user u
CROSS JOIN project p
WHERE check_permission(u.id, 'BROWSE_PROJECTS', p.id);

CREATE UNIQUE INDEX idx_upa_user_project ON user_project_access(user_id, project_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY user_project_access;

-- Now query is O(1):
SELECT project_key, project_name 
FROM user_project_access 
WHERE user_id = :user_id;
```

### Query 2: Sprint board with ranked issues

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    j.id,
    (SELECT project_key FROM project WHERE id = j.project_id) || '-' || j.issue_num AS issue_key,
    j.summary,
    j.status_id,
    s.name AS status_name,
    j.assignee_id,
    j.story_points,
    si.rank
FROM sprint_issue si
JOIN jiraissue j ON si.issue_id = j.id
JOIN issue_status s ON j.status_id = s.id
WHERE si.sprint_id = :sprint_id
ORDER BY si.rank;
```

---

# Part 6: Polyglot Integration Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                    JIRA DATA FLOW                                │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   PostgreSQL     │     │   Elasticsearch  │     │   Redis          │
│   (Primary)      │────►│   (Search)       │     │   (Cache)        │
│                  │ CDC │                  │     │                  │
│ • Issues         │     │ • Full-text      │     │ • Session        │
│ • Permissions    │     │ • JQL queries    │     │ • Permission     │
│ • Workflows      │     │ • Faceted search │     │   cache          │
│ • Users/Groups   │     │                  │     │ • Board config   │
└──────────────────┘     └──────────────────┘     └──────────────────┘
         │
         │ CDC (Debezium)
         ▼
┌──────────────────┐
│   Kafka          │
│                  │
│ • issue-events   │
│ • audit-log      │
│ • webhooks       │
└──────────────────┘
```

---

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Permission schemes decoupled | Change scheme → affects all linked projects |
| 2 | Workflow per (project, issuetype) | `workflow_scheme_entity` checked |
| 3 | Custom fields EAV pattern | `custom_field_value` handles any type |
| 4 | LexoRank for ordering | `rank` column on issues/sprint_issue |
| 5 | Optimistic locking | `version` column on jiraissue |
| 6 | Permission check < 10ms | Materialized view or cache |
| 7 | No N+1 on board load | Single query with JOINs |
| 8 | Partial indexes on assignee | WHERE assignee_id IS NOT NULL |

---

# Part 5: Query Examples with EXPLAIN

```sql
-- ============================================================
-- JIRA QUERY PATTERNS WITH EXPLAIN (PostgreSQL)
-- ============================================================

-- ===========================================
-- QUERY 1: Get Backlog for Board (Ranked)
-- ===========================================

-- "Show me the top 50 issues for this board"
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    i.id, i.summary, i.issue_num, i.priority_id
FROM jiraissue i
JOIN board_project bp ON i.project_id = bp.project_id
WHERE bp.board_id = $1
  AND i.status_id NOT IN (6) -- Not Closed
ORDER BY i.rank ASC
LIMIT 50;

-- Analysis: Index Scan on issue_rank.
-- Note: LexoRank allows string sorting to match visual order.


-- ===========================================
-- QUERY 2: Check Permission ("Can User Edit Issue?")
-- ===========================================

-- "Does John have EDIT_ISSUES on PROJ-123?"
-- Complex 5-way join: User -> Group -> Role -> Scheme -> Permission
EXPLAIN (ANALYZE, BUFFERS)
SELECT 1
FROM scheme_permissions sp
JOIN project p ON p.permission_scheme_id = sp.scheme_id
JOIN jiraissue i ON i.project_id = p.id
WHERE i.id = $1 -- Issue ID
  AND sp.permission_key = 'EDIT_ISSUES'
  AND (
    (sp.permission_type = 'group' AND sp.parameter IN (SELECT group_name FROM user_groups WHERE user_id = $2))
    OR
    (sp.permission_type = 'projectrole' AND sp.parameter IN (SELECT role_id FROM user_roles WHERE user_id = $2 AND project_id = p.id))
    OR
    (sp.permission_type = 'assignee' AND i.assignee_id = $2)
    OR
    (sp.permission_type = 'user' AND sp.parameter = $2)
  );

-- Analysis: Critical hot path. Often cached in application memory (Ehcache).
-- Database fallback must use verifying indexes on sp(scheme_id).


-- ===========================================
-- QUERY 3: Search Custom Field Value (EAV)
-- ===========================================

-- "Find issues where 'Customer ID' (cf[1001]) = 'C-555'"
EXPLAIN (ANALYZE, BUFFERS)
SELECT issue_id
FROM custom_field_value
WHERE custom_field_id = 1001
  AND string_value = 'C-555';

-- Analysis: Partial Index Scan (idx_cfv_string).
-- Only rows with string_value are scanned.


-- ===========================================
-- QUERY 4: JQL Search "project = P AND status = Open"
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, summary
FROM jiraissue
WHERE project_id = 100
  AND status_id = 1;

-- Analysis: Uses composite index idx_issue_project_status.
-- Extremely fast.
```

---

# Part 6: Capacity Planning

```
============================================================
JIRA DATACENTER CAPACITY PLANNING
============================================================

ASSUMPTIONS (Enterprise Scale):
- 10,000 Users
- 5 Million Issues
- 500 Projects
- 500k Comments/Worklogs per month

============================================================
STORAGE ESTIMATES
============================================================

ISSUES (PostgreSQL)
  5M issues * 2KB avg = 10 GB.
  Small data, but text search adds overhead.
  GIN Indexes take 30-50% of table size.

CUSTOM FIELD VALUES (EAV Bloat)
  Avg 20 custom fields per issue.
  5M * 20 = 100M rows in `custom_field_value`.
  100M * 100 bytes = 10 GB.
  Table partitioning recommended (PARTITION BY custom_field_id).

ATTACHMENTS (Filesystem/S3)
  5M issues * 0.5 attachments * 1MB avg = 2.5 TB.
  Store on S3 or NFS. Database stores pointers.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

READS (Heavy):
- "Dashboard Load": 50 reqs/sec complex aggregate.
- "Issue View": 200 reqs/sec simple lookups.
- "Permission Check": 5000 checks/sec (Must be cached).

WRITES (Moderate):
- 20-50 transitions/sec.
- "Bulk Edit" spikes (1000 updates in 1 tx).
- Lucene/Elasticsearch Indexing is the bottleneck (Async queue).

COMPUTE (Indexing):
- Re-indexing 5M issues takes ~2-4 hours.
- Critical to keep index sync with DB.

============================================================
SCALING STRATEGY
============================================================

1. READ REPLICAS
   - Direct JQL searches to Read Replicas.
   - Dashboards hit Replicas.
   - Only Writes hit Master.

2. ARCHIVING
   - "Archived Projects" feature moves data to `jiraissue_archived`.
   - Keeps live index small (performance gain).

3. DATABASE PARTITIONING
   - Partition `worklog` and `issue_comment` by Year.
   - Keeps active dataset small.

4. CACHING (The Savior)
   - Do NOT run permission SQL for every click.
   - Cache: User -> [List of Project Roles]
   - Cache: Scheme -> [List of Permissions]
   - Invalidate cache on Admin config change.
```

---

# Part 7: Anti-Patterns to Avoid

```
============================================================
JIRA ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Permissions in Issue Table
-----------------------------------------
WRONG:
  Table: issue (id, can_view_group_id, can_edit_group_id)
  -- Changing a group permission requires updating 1M issues.
  
RIGHT:
  -- Scheme Architecture.
  -- Change 1 Scheme row -> applied to all Projects instantly.


❌ ANTI-PATTERN 2: Integer Ranking
-----------------------------------------
WRONG:
  Table: issue (id, rank_int)
  -- Moving issue 1 to position 5 requires updating rows 2,3,4,5.
  -- Rank Collision and Verify Loop issues.
  
RIGHT:
  -- LexoRank (String based ranking).
  -- "0|abc:" -> "0|abd:" -> "0|abe:".
  -- Insert "0|abcz:" between "abc" and "abd". No shift required.


❌ ANTI-PATTERN 3: Thousands of Custom Fields
-----------------------------------------
WRONG:
  Admins create "Start Date " "Start Date" "Begin Date".
  -- custom_field_value table hits 1 Billion rows.
  -- Performance degradation globally.
  
RIGHT:
  -- Field Configuration Schemes.
  -- Reuse 1 generic "Date" field for different contexts.


❌ ANTI-PATTERN 4: Synchronous Webhooks
-----------------------------------------
WRONG:
  Transactional Update -> Fire HTTP Webhook -> Wait for 200 OK.
  -- Slow 3rd party tool blocks JIRA saving.
  
RIGHT:
  -- Async Event Queue.
  -- Transition saves to DB.
  -- Background thread fires Webhook.


❌ ANTI-PATTERN 5: Polling for Updates
-----------------------------------------
WRONG:
  React frontend polls /api/issue/123 every 2s.
  -- 10k users = 5000 reqs/sec.
  
RIGHT:
  -- WebSocket / SignalR for "Issue Updated" push.
  -- "Stale State" warning in UI.


❌ ANTI-PATTERN 6: Hard Deleting Issues
-----------------------------------------
WRONG:
  DELETE FROM jiraissue WHERE id = 1.
  -- Breaks child links, worklogs, agile history.
  
RIGHT:
  -- Soft Delete (status = 'Deleted').
  -- Or complete "Issue Delete" service that cleans up FKs properly.


❌ ANTI-PATTERN 7: Storing JSON in Text Fields
-----------------------------------------
WRONG:
  Storing standard data in a text custom field as JSON.
  -- Cannot index. Cannot search via JQL.
  
RIGHT:
  -- Plugin with ActiveObjects (Separate Tables) for structured data.
  -- Or PropertyStore (Key-Value) for simple meta.


❌ ANTI-PATTERN 8: Global JavaScript Hacks
-----------------------------------------
WRONG:
  Injecting JS into "Announcement Banner" to hide fields.
  -- Security risk. Breaks on upgrade.
  
RIGHT:
  -- Behaviors Plugin (Server-side logic).
  -- Field Configurations (Native visibility control).
```

---

# Part 8: CDC & Event Streaming

```
============================================================
JIRA CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (Core)      │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ Elastic   │    │ Automation│   │ Webhook   │  │ Audit    │
  │ Indexer   │    │ Automation│   │ Service   │  │ Log      │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- issue.created           (Trigger Auto-assign)
- issue.updated           (Update Search Index)
- worklog.added           (Update Timesheet App)
- project.deleted         (Cleanup External Resources)

============================================================
DISASTER RECOVERY
============================================================

RPO: < 5 minutes
RTO: < 1 hour

STRATEGY:
1. Shared Filesystem (NFS/EFS)
   - `data/` directory contains attachments, avatars, index snapshots.
   - Must be replicated to DR site (DataSync/Rsync).

2. Database Replication
   - Async streaming replication to DR region.
   - XML Backup (Native JIRA) is too slow for large instances. Use DB Dump.

3. Index Rebuilding
   - Index is NOT replicated (it's filesystem based).
   - In DR, copy the snapshot, then "catch up" using DB changes.
   - Or start fresh Background Reindex (slower).
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- JIRA: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / CHANGE HISTORY
-- ===========================================

CREATE TABLE entity_change_log (
    id                  BIGSERIAL PRIMARY KEY,
    project_id          UUID NOT NULL,
    entity_type         VARCHAR(50) NOT NULL,  -- 'issue', 'project', 'workflow'
    entity_id           UUID NOT NULL,
    field_name          VARCHAR(100) NOT NULL,
    old_value           TEXT,
    new_value           TEXT,
    changed_by_id       UUID NOT NULL,
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    change_source       VARCHAR(50),  -- 'ui', 'api', 'automation', 'import'
    ip_address          INET
) PARTITION BY RANGE (changed_at);

CREATE INDEX idx_ecl_entity ON entity_change_log(project_id, entity_type, entity_id);


-- ===========================================
-- B. ATTACHMENTS
-- ===========================================

CREATE TABLE attachments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    issue_id            UUID NOT NULL REFERENCES issues(id),
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    thumbnail_key       VARCHAR(500),
    uploaded_by_id      UUID NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_attach_issue ON attachments(issue_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    project_id          UUID,
    channel             VARCHAR(20) NOT NULL,  -- 'email', 'slack', 'teams'
    notification_type   VARCHAR(100) NOT NULL,  -- 'issue_assigned', 'comment_mentioned'
    subject             VARCHAR(255),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS / INTEGRATIONS
-- ===========================================

CREATE TABLE app_links (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    app_type            VARCHAR(50) NOT NULL,  -- 'bitbucket', 'confluence', 'github', 'slack'
    name                VARCHAR(100) NOT NULL,
    base_url            VARCHAR(500) NOT NULL,
    client_id           VARCHAR(100),
    client_secret_enc   BYTEA,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id          UUID REFERENCES projects(id),  -- NULL = global
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['issue:created', 'sprint:completed']
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_deliveries (
    id                  BIGSERIAL PRIMARY KEY,
    subscription_id     UUID NOT NULL REFERENCES webhook_subscriptions(id),
    event_type          VARCHAR(100) NOT NULL,
    payload             JSONB NOT NULL,
    response_code       INT,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- E. API KEYS / PERSONAL ACCESS TOKENS
-- ===========================================

CREATE TABLE api_tokens (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    token_name          VARCHAR(100) NOT NULL,
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    scopes              TEXT[] NOT NULL,
    last_used_at        TIMESTAMP WITH TIME ZONE,
    expires_at          TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at          TIMESTAMP WITH TIME ZONE
);


-- ===========================================
-- F. SSO (SAML/OIDC)
-- ===========================================

CREATE TABLE sso_providers (
    id                  SERIAL PRIMARY KEY,
    provider_type       VARCHAR(50) NOT NULL,  -- 'okta', 'azure_ad', 'google', 'crowd'
    name                VARCHAR(100) NOT NULL,
    client_id           VARCHAR(255) NOT NULL,
    client_secret_enc   BYTEA NOT NULL,
    issuer_url          VARCHAR(500),
    saml_metadata_url   VARCHAR(500),
    enforce_sso         BOOLEAN DEFAULT FALSE,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE user_sso_links (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    provider_id         INT NOT NULL REFERENCES sso_providers(id),
    external_id         VARCHAR(255) NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uk_user_provider UNIQUE (user_id, provider_id)
);


-- ===========================================
-- G. USER SESSIONS
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_type         VARCHAR(50),
    ip_address          INET NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    allowed_project_ids UUID[],
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ===========================================
-- I. SAVED FILTERS / VIEWS
-- ===========================================

CREATE TABLE saved_filters (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id            UUID NOT NULL,
    name                VARCHAR(100) NOT NULL,
    jql                 TEXT NOT NULL,  -- JQL query string
    description         TEXT,
    is_favorite         BOOLEAN DEFAULT FALSE,
    share_type          VARCHAR(20) DEFAULT 'private',  -- 'private', 'project', 'global'
    shared_with_projects UUID[],
    shared_with_groups  TEXT[],
    column_config       JSONB,  -- Custom columns
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_filter_owner ON saved_filters(owner_id);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
JIRA: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. WORKFLOW ENGINE INTERNALS (OSWorkflow)
============================================================

THE CHALLENGE:
Workflows are state machines. JIRA allows custom Groovy scripts, post-functions, and validators on every transition.
Key Risk: "Long Running Transitions" blocking the HTTP thread.

DB REPRESENTATION:
- `os_wfentry`: The process instance (Issue ID).
- `os_currentstep`: Where is it now? (Status ID).
- `os_historystep`: Audit trail of where it was.

OPTIMIZATION:
- Transition IDs are critical. Indexed scan on `node_association` table.
- "Draft Workflows": Stored as XML blob in `draft_workflow_scheme`.
- Validation: Do NOT put external API calls (e.g., GitHub check) in the synchronous transition path. Use Webhooks (async).

============================================================
2. SEARCH INDEXING INTERNALS (LUCENE)
============================================================

ARCHITECTURE:
PostgreSQL (Source of Truth) -> Indexer Thread -> Lucene Index (Speed layer).

LATENCY GAP:
- When you update an issue, it is NOT immediately searchable.
- "Reindex Lag": Typically < 1s, but can spike to minutes during bulk edits.

TUNING:
- "Background Reindexing": Uses `entity_change_log` to catch up.
- "Index Sharding": Split index by Project ID or Year.
- RAM Buffer: Allocate 50% of Heap to Lucene Cache (not just DB connection pool).

JQL OPTIMIZATION:
- Bad JQL: `description ~ "foo"` (Text scan).
- Good JQL: `project = "PROJ" AND status = "Open"`.
- Cardinality: Always filter by Project/IssueType first (highest selectivity).

============================================================
3. CUSTOM FIELD PERFORMANCE (THE EAV PROBLEM)
============================================================

THE BOTTLENECK:
Startups have 10 custom fields. Enterprises have 2000.
Query: `SELECT * FROM customfieldvalue WHERE ...` (Billions of rows).

MITIGATION:
1. Columnar Indexing (If using PostgreSQL 12+): Use `jsonb` for "sparse" custom fields instead of EAV rows.
2. Caching: "Custom Field Context" cache. Only load fields relevant to the current Project/IssueType.
3. Archival: Move `customfieldvalue` rows for Closed issues > 2 years old to `archived_issues` table.

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Issue View Load Time (p99)   │ < 1s    │ > 3s = WARN     │
│  JQL Search Latency (p99)     │ < 500ms │ > 2s = WARN     │
│  Web/API Availability         │ > 99.9% │ < 99.5% = PAGE  │
│  Index Replication Lag        │ < 5s    │ > 30s = PAGE    │
│  Mail Queue Depth             │ < 1000  │ > 5000 = INFO   │
└─────────────────────────────────────────────────────────────┘

DB METRICS:
- `db_connection_pool_utilization`: JIRA is notoriously connection-hungry.
- `slow_query_count`: Watch for JQL queries doing full table scans.

JVM METRICS:
- `heap_usage`: Garbage Collection pauses cause "JIRA Freezes".
- `thread_stuck_count`: Threads waiting on DB locks > 60s.

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: "REINDEXING LOOP OF DEATH"
Symptom: Admin triggers "Full Foreground Reindex". System locks up for 4 hours.
Mitigation:
- "Background Reindex" only.
- DC/Cluster mode: Reindex one node at a time, keeping others active.

SCENARIO 2: MAIL QUEUE BACKLOG
Symptom: 100k emails queued. Notification delays.
Mitigation:
- Separate Mail Server (SMTP) from Application Server.
- "Batched Notifications": Group updates into 1 email every 10 mins.

SCENARIO 3: "NOISY NEIGHBOR" PROJECT
Symptom: One team running an automation script updates 1k issues/sec.
Mitigation:
- Rate Limiting: Per-user token bucket (REST API).
- Bulk API Limits: Max 50 issues per batch.
- Isolate "Bot Users" to a dedicated node (Data Center).

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

STORAGE TIERING:
- Attachments (S3): Move artifacts to S3 IA (Infrequent Access) after 90 days.
- DB Archival: "Archiving Plugin" moves closed projects to separate Read-Only DB schema.

INSTANCE SIZING (Enterprise Scale):
- App Nodes: 4x c6g.4xlarge (Compute optimized for Java).
- Database: db.r6g.8xlarge (Memory optimized for PG buffer pool).
- Index Node: i3en.2xlarge (NVMe SSD for Lucene IOPS).
```

---

## 🔗 Related Documents

- [Authorization Schema Design](./authorization-schema-design-guide.md) — Generic RBAC/ABAC patterns
- [NoSQL Architecture](./nosql-architecture-guide.md) — DynamoDB single-table design
- [Database Scaling](./database-scaling-guide.md) — Sharding strategies
