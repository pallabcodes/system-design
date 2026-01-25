# Authorization Schema Design: SQL & NoSQL Implementation Guide

> **Level**: Principal Architect / Lead DBA (Google-scale)
> **Scope**: Complete Schema Design for RBAC, ReBAC, PBAC with Production Queries in PostgreSQL, MongoDB, DynamoDB, and Cassandra.

> [!CAUTION]
> **The Cardinal Sin**: Designing permissions with `user_id + permission` only. Real systems need **resource-scoped, hierarchical, time-bound, delegatable** permissions.

---

## 🎯 Authorization Models Overview

| Model | Description | Use Case | Complexity |
| :--- | :--- | :--- | :--- |
| **ACL** | Access Control List per resource. | File systems. | Low |
| **RBAC** | Role → Permissions → Users. | Enterprise apps. | Medium |
| **ReBAC** | Relationships define access (owner, member). | Social apps, Google Drive. | High |
| **PBAC** | Policies with conditions (time, IP, attributes). | Financial, Healthcare. | Very High |
| **ABAC** | Attribute-based rules. | Dynamic environments. | Very High |

---

# Part 1: PostgreSQL Schema Design

## 📊 Core RBAC Schema

```sql
-- =============================================================================
-- USERS & GROUPS
-- =============================================================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    parent_group_id UUID REFERENCES groups(id),  -- Hierarchical groups
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_groups (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    added_by UUID REFERENCES users(id),
    PRIMARY KEY (user_id, group_id)
);

CREATE INDEX idx_user_groups_user ON user_groups(user_id);
CREATE INDEX idx_user_groups_group ON user_groups(group_id);

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(100) UNIQUE NOT NULL,          -- 'issues:read', 'issues:write', 'issues:delete'
    name VARCHAR(255) NOT NULL,
    description TEXT,
    resource_type VARCHAR(100),                  -- 'issue', 'project', 'board'
    action VARCHAR(50),                          -- 'read', 'write', 'delete', 'admin'
    is_system BOOLEAN DEFAULT FALSE,             -- Cannot be deleted
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pre-populate system permissions
INSERT INTO permissions (code, name, resource_type, action, is_system) VALUES
('projects:browse', 'Browse Projects', 'project', 'read', TRUE),
('projects:create', 'Create Projects', 'project', 'write', TRUE),
('projects:admin', 'Administer Projects', 'project', 'admin', TRUE),
('issues:read', 'Read Issues', 'issue', 'read', TRUE),
('issues:create', 'Create Issues', 'issue', 'write', TRUE),
('issues:edit', 'Edit Issues', 'issue', 'write', TRUE),
('issues:delete', 'Delete Issues', 'issue', 'delete', TRUE),
('issues:assign', 'Assign Issues', 'issue', 'write', TRUE),
('issues:transition', 'Transition Issues', 'issue', 'write', TRUE),
('comments:add', 'Add Comments', 'comment', 'write', TRUE),
('comments:edit_own', 'Edit Own Comments', 'comment', 'write', TRUE),
('comments:edit_all', 'Edit All Comments', 'comment', 'admin', TRUE),
('comments:delete_all', 'Delete All Comments', 'comment', 'admin', TRUE);

-- =============================================================================
-- ROLES
-- =============================================================================

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_system BOOLEAN DEFAULT FALSE,
    scope VARCHAR(50) DEFAULT 'project',         -- 'global', 'project', 'board'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Role inheritance (role A inherits from role B)
CREATE TABLE role_inheritance (
    parent_role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    child_role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (parent_role_id, child_role_id),
    CHECK (parent_role_id != child_role_id)
);

-- Permissions assigned to roles
CREATE TABLE role_permissions (
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE INDEX idx_role_perms_role ON role_permissions(role_id);

-- Pre-populate system roles
INSERT INTO roles (name, description, is_system, scope) VALUES
('Administrator', 'Full system access', TRUE, 'global'),
('Project Admin', 'Full project access', TRUE, 'project'),
('Developer', 'Standard development access', TRUE, 'project'),
('Viewer', 'Read-only access', TRUE, 'project');

-- =============================================================================
-- RESOURCES (Projects, Boards, etc.)
-- =============================================================================

CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR(10) UNIQUE NOT NULL,             -- 'PROJ', 'ENG', 'HR'
    name VARCHAR(255) NOT NULL,
    description TEXT,
    lead_user_id UUID REFERENCES users(id),
    is_private BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE issues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    issue_number SERIAL,
    issue_key VARCHAR(20) GENERATED ALWAYS AS (
        (SELECT key FROM projects WHERE id = project_id) || '-' || issue_number
    ) STORED,
    summary VARCHAR(500) NOT NULL,
    description TEXT,
    issue_type VARCHAR(50) NOT NULL,             -- 'bug', 'story', 'task', 'epic'
    status VARCHAR(50) DEFAULT 'open',
    priority VARCHAR(20) DEFAULT 'medium',
    reporter_id UUID REFERENCES users(id),
    assignee_id UUID REFERENCES users(id),
    security_level_id UUID,                      -- FK added later
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(project_id, issue_number)
);

CREATE INDEX idx_issues_project ON issues(project_id);
CREATE INDEX idx_issues_reporter ON issues(reporter_id);
CREATE INDEX idx_issues_assignee ON issues(assignee_id);

-- =============================================================================
-- ROLE ASSIGNMENTS (Resource-Scoped)
-- =============================================================================

CREATE TABLE user_project_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    granted_at TIMESTAMPTZ DEFAULT NOW(),
    granted_by UUID REFERENCES users(id),
    expires_at TIMESTAMPTZ,                      -- Time-bound access
    PRIMARY KEY (user_id, project_id, role_id)
);

CREATE INDEX idx_upr_user ON user_project_roles(user_id);
CREATE INDEX idx_upr_project ON user_project_roles(project_id);
CREATE INDEX idx_upr_role ON user_project_roles(role_id);

-- Group-based role assignment
CREATE TABLE group_project_roles (
    group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    granted_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (group_id, project_id, role_id)
);
```

---

## 🔗 ReBAC Schema (Relationship-Based)

```sql
-- =============================================================================
-- RELATIONSHIP TUPLES (Google Zanzibar-style)
-- =============================================================================

-- The core of ReBAC: Who has what relationship to what resource?
CREATE TABLE relationship_tuples (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Subject (who)
    subject_type VARCHAR(50) NOT NULL,           -- 'user', 'group', 'role'
    subject_id UUID NOT NULL,
    subject_relation VARCHAR(50),                -- For nested relationships: 'member'
    
    -- Relation (relationship type)
    relation VARCHAR(50) NOT NULL,               -- 'owner', 'editor', 'viewer', 'member'
    
    -- Object (resource)
    object_type VARCHAR(50) NOT NULL,            -- 'project', 'issue', 'document'
    object_id UUID NOT NULL,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID,
    expires_at TIMESTAMPTZ,
    
    UNIQUE(subject_type, subject_id, relation, object_type, object_id)
);

CREATE INDEX idx_rt_subject ON relationship_tuples(subject_type, subject_id);
CREATE INDEX idx_rt_object ON relationship_tuples(object_type, object_id);
CREATE INDEX idx_rt_relation ON relationship_tuples(relation);

-- Examples:
-- User 123 is 'owner' of project ABC
INSERT INTO relationship_tuples (subject_type, subject_id, relation, object_type, object_id)
VALUES ('user', '123', 'owner', 'project', 'abc');

-- Group 'engineering' has 'editor' on project ABC
INSERT INTO relationship_tuples (subject_type, subject_id, relation, object_type, object_id)
VALUES ('group', 'engineering-group-id', 'editor', 'project', 'abc');

-- User 456 is 'reporter' of issue XYZ
INSERT INTO relationship_tuples (subject_type, subject_id, relation, object_type, object_id)
VALUES ('user', '456', 'reporter', 'issue', 'xyz');

-- =============================================================================
-- PERMISSION DEFINITIONS (Relation → Permissions)
-- =============================================================================

CREATE TABLE relation_permissions (
    object_type VARCHAR(50) NOT NULL,
    relation VARCHAR(50) NOT NULL,
    permission VARCHAR(100) NOT NULL,            -- 'read', 'write', 'delete', 'admin'
    PRIMARY KEY (object_type, relation, permission)
);

-- Define what each relation grants
INSERT INTO relation_permissions VALUES
-- Project relations
('project', 'owner', 'projects:admin'),
('project', 'owner', 'projects:browse'),
('project', 'owner', 'issues:create'),
('project', 'owner', 'issues:edit'),
('project', 'owner', 'issues:delete'),
('project', 'editor', 'projects:browse'),
('project', 'editor', 'issues:create'),
('project', 'editor', 'issues:edit'),
('project', 'viewer', 'projects:browse'),
('project', 'viewer', 'issues:read'),

-- Issue relations
('issue', 'reporter', 'issues:read'),
('issue', 'reporter', 'issues:edit'),
('issue', 'assignee', 'issues:read'),
('issue', 'assignee', 'issues:edit'),
('issue', 'assignee', 'issues:transition'),
('issue', 'watcher', 'issues:read');
```

---

## 🛡️ Issue Security Levels Schema

```sql
-- =============================================================================
-- ISSUE SECURITY
-- =============================================================================

CREATE TABLE security_schemes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE security_levels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scheme_id UUID REFERENCES security_schemes(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    level_order INT DEFAULT 0,                   -- For UI ordering
    UNIQUE(scheme_id, name)
);

CREATE TABLE security_level_members (
    security_level_id UUID REFERENCES security_levels(id) ON DELETE CASCADE,
    member_type VARCHAR(50) NOT NULL,            -- 'user', 'group', 'role', 'reporter', 'assignee'
    member_id UUID,                              -- NULL for 'reporter', 'assignee'
    project_id UUID REFERENCES projects(id),    -- For role-based members
    PRIMARY KEY (security_level_id, member_type, COALESCE(member_id, '00000000-0000-0000-0000-000000000000'))
);

-- Link security scheme to project
CREATE TABLE project_security_schemes (
    project_id UUID PRIMARY KEY REFERENCES projects(id),
    security_scheme_id UUID REFERENCES security_schemes(id)
);

-- Add FK to issues
ALTER TABLE issues ADD CONSTRAINT fk_issue_security 
    FOREIGN KEY (security_level_id) REFERENCES security_levels(id);
```

---

## 📋 EAV Schema for Custom Fields

```sql
-- =============================================================================
-- CUSTOM FIELDS (EAV Pattern)
-- =============================================================================

CREATE TYPE custom_field_type AS ENUM (
    'text', 'number', 'date', 'datetime', 'select', 'multiselect', 
    'user', 'users', 'checkbox', 'url', 'textarea'
);

CREATE TABLE custom_field_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    field_type custom_field_type NOT NULL,
    is_required BOOLEAN DEFAULT FALSE,
    is_searchable BOOLEAN DEFAULT TRUE,
    default_value TEXT,
    options JSONB,                               -- For select/multiselect
    validation_regex VARCHAR(500),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Which projects/issue types use which custom fields
CREATE TABLE custom_field_contexts (
    custom_field_id UUID REFERENCES custom_field_definitions(id) ON DELETE CASCADE,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    issue_type VARCHAR(50),                      -- NULL = all types
    PRIMARY KEY (custom_field_id, project_id, COALESCE(issue_type, '*'))
);

-- The EAV value table
CREATE TABLE custom_field_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id UUID REFERENCES issues(id) ON DELETE CASCADE,
    custom_field_id UUID REFERENCES custom_field_definitions(id) ON DELETE CASCADE,
    
    -- Polymorphic value storage
    text_value TEXT,
    number_value NUMERIC(18,6),
    date_value DATE,
    datetime_value TIMESTAMPTZ,
    user_value UUID REFERENCES users(id),
    json_value JSONB,                            -- For multiselect, users array
    
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(issue_id, custom_field_id)
);

CREATE INDEX idx_cfv_issue ON custom_field_values(issue_id);
CREATE INDEX idx_cfv_field ON custom_field_values(custom_field_id);
CREATE INDEX idx_cfv_text ON custom_field_values(custom_field_id, text_value) WHERE text_value IS NOT NULL;
CREATE INDEX idx_cfv_number ON custom_field_values(custom_field_id, number_value) WHERE number_value IS NOT NULL;
CREATE INDEX idx_cfv_date ON custom_field_values(custom_field_id, date_value) WHERE date_value IS NOT NULL;

-- =============================================================================
-- MATERIALIZED CUSTOM FIELDS (Performance Optimization)
-- =============================================================================

-- Add JSONB column to issues for fast reads
ALTER TABLE issues ADD COLUMN custom_fields JSONB DEFAULT '{}';

-- Trigger to sync EAV → JSONB
CREATE OR REPLACE FUNCTION sync_custom_fields_to_json()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE issues SET custom_fields = (
        SELECT jsonb_object_agg(
            cfd.name,
            COALESCE(cfv.text_value, cfv.number_value::TEXT, cfv.date_value::TEXT, cfv.json_value::TEXT)
        )
        FROM custom_field_values cfv
        JOIN custom_field_definitions cfd ON cfd.id = cfv.custom_field_id
        WHERE cfv.issue_id = NEW.issue_id
    )
    WHERE id = NEW.issue_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_custom_fields
AFTER INSERT OR UPDATE OR DELETE ON custom_field_values
FOR EACH ROW EXECUTE FUNCTION sync_custom_fields_to_json();

-- Now you can query:
-- SELECT * FROM issues WHERE custom_fields->>'Sprint' = 'Sprint 42';
```

---

## ⚡ Production SQL Queries

### Query 1: Check if User Has Permission on Project
```sql
-- Full permission check with role inheritance and group membership
WITH RECURSIVE 
-- Get all groups the user belongs to (including nested)
user_groups_recursive AS (
    SELECT ug.group_id, 0 AS depth
    FROM user_groups ug
    WHERE ug.user_id = $1  -- :user_id
    
    UNION
    
    SELECT g.parent_group_id, ugr.depth + 1
    FROM user_groups_recursive ugr
    JOIN groups g ON g.id = ugr.group_id
    WHERE g.parent_group_id IS NOT NULL AND ugr.depth < 10
),

-- Get all roles assigned to user (direct + via groups)
user_roles AS (
    -- Direct user → project → role
    SELECT upr.role_id
    FROM user_project_roles upr
    WHERE upr.user_id = $1 
      AND upr.project_id = $2  -- :project_id
      AND (upr.expires_at IS NULL OR upr.expires_at > NOW())
    
    UNION
    
    -- Via group → project → role
    SELECT gpr.role_id
    FROM group_project_roles gpr
    WHERE gpr.group_id IN (SELECT group_id FROM user_groups_recursive)
      AND gpr.project_id = $2
),

-- Expand role inheritance
roles_with_inheritance AS (
    SELECT role_id FROM user_roles
    
    UNION
    
    SELECT ri.parent_role_id
    FROM roles_with_inheritance rwi
    JOIN role_inheritance ri ON ri.child_role_id = rwi.role_id
),

-- Get all permissions from all roles
effective_permissions AS (
    SELECT DISTINCT p.code
    FROM roles_with_inheritance rwi
    JOIN role_permissions rp ON rp.role_id = rwi.role_id
    JOIN permissions p ON p.id = rp.permission_id
)

SELECT EXISTS (
    SELECT 1 FROM effective_permissions WHERE code = $3  -- :permission_code
) AS has_permission;
```

### Query 2: Check Issue Access (Including Security Level)
```sql
CREATE OR REPLACE FUNCTION can_access_issue(p_user_id UUID, p_issue_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_project_id UUID;
    v_security_level_id UUID;
    v_reporter_id UUID;
    v_assignee_id UUID;
    v_has_browse BOOLEAN;
    v_passes_security BOOLEAN;
BEGIN
    -- Get issue details
    SELECT project_id, security_level_id, reporter_id, assignee_id
    INTO v_project_id, v_security_level_id, v_reporter_id, v_assignee_id
    FROM issues WHERE id = p_issue_id;
    
    IF NOT FOUND THEN RETURN FALSE; END IF;
    
    -- Check BROWSE_PROJECTS permission
    SELECT EXISTS (
        -- Use the permission check from Query 1
        WITH RECURSIVE user_groups_recursive AS (
            SELECT ug.group_id FROM user_groups ug WHERE ug.user_id = p_user_id
            UNION
            SELECT g.parent_group_id FROM user_groups_recursive ugr
            JOIN groups g ON g.id = ugr.group_id WHERE g.parent_group_id IS NOT NULL
        ),
        user_roles AS (
            SELECT upr.role_id FROM user_project_roles upr
            WHERE upr.user_id = p_user_id AND upr.project_id = v_project_id
            UNION
            SELECT gpr.role_id FROM group_project_roles gpr
            WHERE gpr.group_id IN (SELECT group_id FROM user_groups_recursive)
              AND gpr.project_id = v_project_id
        )
        SELECT 1 FROM user_roles ur
        JOIN role_permissions rp ON rp.role_id = ur.role_id
        JOIN permissions p ON p.id = rp.permission_id
        WHERE p.code = 'projects:browse'
    ) INTO v_has_browse;
    
    IF NOT v_has_browse THEN RETURN FALSE; END IF;
    
    -- Check security level (if set)
    IF v_security_level_id IS NULL THEN
        RETURN TRUE;  -- No security level, accessible
    END IF;
    
    SELECT EXISTS (
        SELECT 1 FROM security_level_members slm
        WHERE slm.security_level_id = v_security_level_id
          AND (
            -- Direct user
            (slm.member_type = 'user' AND slm.member_id = p_user_id)
            -- User is reporter
            OR (slm.member_type = 'reporter' AND v_reporter_id = p_user_id)
            -- User is assignee
            OR (slm.member_type = 'assignee' AND v_assignee_id = p_user_id)
            -- User in group
            OR (slm.member_type = 'group' AND slm.member_id IN (
                SELECT group_id FROM user_groups WHERE user_id = p_user_id
            ))
            -- User has role
            OR (slm.member_type = 'role' AND slm.member_id IN (
                SELECT role_id FROM user_project_roles 
                WHERE user_id = p_user_id AND project_id = v_project_id
            ))
          )
    ) INTO v_passes_security;
    
    RETURN v_passes_security;
END;
$$ LANGUAGE plpgsql;

-- Usage:
SELECT can_access_issue('user-uuid-here', 'issue-uuid-here');
```

### Query 3: Get All Accessible Issues for User
```sql
SELECT i.id, i.issue_key, i.summary, i.status
FROM issues i
JOIN projects p ON p.id = i.project_id
WHERE 
    -- User has BROWSE permission on project
    EXISTS (
        SELECT 1 FROM user_project_roles upr
        JOIN role_permissions rp ON rp.role_id = upr.role_id
        JOIN permissions perm ON perm.id = rp.permission_id
        WHERE upr.user_id = $1
          AND upr.project_id = i.project_id
          AND perm.code = 'projects:browse'
    )
    -- And passes security level check
    AND (
        i.security_level_id IS NULL
        OR EXISTS (
            SELECT 1 FROM security_level_members slm
            WHERE slm.security_level_id = i.security_level_id
              AND (
                (slm.member_type = 'user' AND slm.member_id = $1)
                OR (slm.member_type = 'reporter' AND i.reporter_id = $1)
                OR (slm.member_type = 'assignee' AND i.assignee_id = $1)
                OR (slm.member_type = 'group' AND slm.member_id IN (
                    SELECT group_id FROM user_groups WHERE user_id = $1
                ))
              )
        )
    )
ORDER BY i.created_at DESC
LIMIT 100;
```

### Query 4: Audit Trail Query
```sql
CREATE TABLE permission_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_time TIMESTAMPTZ DEFAULT NOW(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,                -- 'permission_check', 'role_granted', 'access_denied'
    resource_type VARCHAR(50),
    resource_id UUID,
    permission_checked VARCHAR(100),
    result VARCHAR(20),                          -- 'allowed', 'denied'
    reason TEXT,
    ip_address INET,
    user_agent TEXT,
    request_id UUID
);

CREATE INDEX idx_audit_user ON permission_audit_log(user_id, event_time);
CREATE INDEX idx_audit_resource ON permission_audit_log(resource_type, resource_id, event_time);
CREATE INDEX idx_audit_time ON permission_audit_log(event_time);

-- Query: Who accessed issue X in the last 24 hours?
SELECT u.email, pal.action, pal.result, pal.event_time
FROM permission_audit_log pal
JOIN users u ON u.id = pal.user_id
WHERE pal.resource_type = 'issue'
  AND pal.resource_id = $1
  AND pal.event_time >= NOW() - INTERVAL '24 hours'
ORDER BY pal.event_time DESC;
```

---

# Part 2: MongoDB Schema Design

## 📦 Document Schemas

### Users Collection
```javascript
// Collection: users
{
  _id: ObjectId("..."),
  email: "john@example.com",
  passwordHash: "$2b$...",
  displayName: "John Doe",
  isActive: true,
  groups: [
    ObjectId("group1"),
    ObjectId("group2")
  ],
  directRoles: [
    {
      roleId: ObjectId("developer-role"),
      scope: "global"
    }
  ],
  createdAt: ISODate("2024-01-01T00:00:00Z"),
  updatedAt: ISODate("2024-01-15T00:00:00Z")
}

// Index
db.users.createIndex({ email: 1 }, { unique: true });
db.users.createIndex({ groups: 1 });
```

### Projects Collection
```javascript
// Collection: projects
{
  _id: ObjectId("..."),
  key: "PROJ",
  name: "Engineering Project",
  description: "Main engineering project",
  leadUserId: ObjectId("user123"),
  isPrivate: false,
  
  // Embedded role assignments for fast reads
  roleAssignments: [
    {
      principalType: "user",
      principalId: ObjectId("user123"),
      roleId: ObjectId("admin-role"),
      grantedAt: ISODate("2024-01-01T00:00:00Z"),
      expiresAt: null
    },
    {
      principalType: "group",
      principalId: ObjectId("dev-group"),
      roleId: ObjectId("developer-role"),
      grantedAt: ISODate("2024-01-01T00:00:00Z")
    }
  ],
  
  // Security scheme reference
  securitySchemeId: ObjectId("scheme1"),
  
  createdAt: ISODate("2024-01-01T00:00:00Z")
}

// Indexes
db.projects.createIndex({ key: 1 }, { unique: true });
db.projects.createIndex({ "roleAssignments.principalType": 1, "roleAssignments.principalId": 1 });
```

### Roles Collection
```javascript
// Collection: roles
{
  _id: ObjectId("..."),
  name: "Developer",
  description: "Standard development access",
  scope: "project",  // "global", "project", "board"
  isSystem: true,
  
  // Permissions directly embedded
  permissions: [
    "projects:browse",
    "issues:read",
    "issues:create",
    "issues:edit",
    "issues:transition",
    "comments:add"
  ],
  
  // Role inheritance
  inheritsFrom: [
    ObjectId("viewer-role")  // Developer inherits from Viewer
  ],
  
  createdAt: ISODate("2024-01-01T00:00:00Z")
}

// Index
db.roles.createIndex({ name: 1 });
```

### Issues Collection
```javascript
// Collection: issues
{
  _id: ObjectId("..."),
  projectId: ObjectId("project123"),
  issueNumber: 42,
  issueKey: "PROJ-42",  // Denormalized for fast queries
  
  summary: "Fix login bug",
  description: "Users cannot login with SSO",
  issueType: "bug",
  status: "in_progress",
  priority: "high",
  
  reporterId: ObjectId("user456"),
  assigneeId: ObjectId("user789"),
  watcherIds: [ObjectId("user111"), ObjectId("user222")],
  
  // Issue security
  securityLevelId: ObjectId("level-hr-only"),
  
  // Custom fields (denormalized for fast queries)
  customFields: {
    "Sprint": "Sprint 42",
    "Story Points": 5,
    "Team": "Platform"
  },
  
  // Relationships (ReBAC)
  relationships: [
    { relation: "reporter", userId: ObjectId("user456") },
    { relation: "assignee", userId: ObjectId("user789") },
    { relation: "watcher", userId: ObjectId("user111") },
    { relation: "watcher", userId: ObjectId("user222") }
  ],
  
  createdAt: ISODate("2024-01-01T00:00:00Z"),
  updatedAt: ISODate("2024-01-15T00:00:00Z")
}

// Indexes
db.issues.createIndex({ projectId: 1, issueNumber: 1 }, { unique: true });
db.issues.createIndex({ issueKey: 1 }, { unique: true });
db.issues.createIndex({ reporterId: 1 });
db.issues.createIndex({ assigneeId: 1 });
db.issues.createIndex({ "relationships.relation": 1, "relationships.userId": 1 });
db.issues.createIndex({ "customFields.Sprint": 1 });
```

### Security Levels Collection
```javascript
// Collection: securityLevels
{
  _id: ObjectId("..."),
  schemeId: ObjectId("scheme1"),
  name: "HR Eyes Only",
  description: "Only HR team can view",
  members: [
    { type: "role", roleId: ObjectId("hr-role") },
    { type: "group", groupId: ObjectId("hr-group") },
    { type: "reporter" },
    { type: "user", userId: ObjectId("specific-user") }
  ],
  order: 1
}
```

---

## ⚡ MongoDB Production Queries

### Query 1: Check Permission on Project
```javascript
async function hasPermission(userId, projectId, permissionCode) {
  const user = await db.users.findOne({ _id: userId });
  if (!user) return false;
  
  // Get user's groups
  const groupIds = user.groups || [];
  
  // Get project with role assignments
  const project = await db.projects.findOne({ _id: projectId });
  if (!project) return false;
  
  // Find applicable role assignments
  const applicableAssignments = project.roleAssignments.filter(ra => {
    if (ra.expiresAt && ra.expiresAt < new Date()) return false;
    
    return (
      (ra.principalType === 'user' && ra.principalId.equals(userId)) ||
      (ra.principalType === 'group' && groupIds.some(g => g.equals(ra.principalId)))
    );
  });
  
  if (applicableAssignments.length === 0) return false;
  
  // Get role IDs
  const roleIds = applicableAssignments.map(ra => ra.roleId);
  
  // Get roles with inheritance
  const roles = await db.roles.aggregate([
    { $match: { _id: { $in: roleIds } } },
    {
      $graphLookup: {
        from: "roles",
        startWith: "$inheritsFrom",
        connectFromField: "inheritsFrom",
        connectToField: "_id",
        as: "inheritedRoles"
      }
    }
  ]).toArray();
  
  // Collect all permissions
  const allPermissions = new Set();
  roles.forEach(role => {
    role.permissions.forEach(p => allPermissions.add(p));
    role.inheritedRoles.forEach(ir => {
      ir.permissions.forEach(p => allPermissions.add(p));
    });
  });
  
  return allPermissions.has(permissionCode);
}

// Usage
const canEdit = await hasPermission(userId, projectId, 'issues:edit');
```

### Query 2: Get Accessible Issues with Security Check
```javascript
async function getAccessibleIssues(userId, projectId, limit = 100) {
  const user = await db.users.findOne({ _id: userId });
  const groupIds = user.groups || [];
  
  // Get user's roles on this project
  const project = await db.projects.findOne({ _id: projectId });
  const userRoleIds = project.roleAssignments
    .filter(ra => 
      (ra.principalType === 'user' && ra.principalId.equals(userId)) ||
      (ra.principalType === 'group' && groupIds.some(g => g.equals(ra.principalId)))
    )
    .map(ra => ra.roleId);
  
  // Get security levels user can access
  const accessibleLevels = await db.securityLevels.find({
    schemeId: project.securitySchemeId,
    $or: [
      { "members.type": "reporter" },
      { "members.type": "assignee" },
      { "members.type": "user", "members.userId": userId },
      { "members.type": "group", "members.groupId": { $in: groupIds } },
      { "members.type": "role", "members.roleId": { $in: userRoleIds } }
    ]
  }).toArray();
  
  const accessibleLevelIds = accessibleLevels.map(l => l._id);
  
  // Query issues
  return db.issues.aggregate([
    {
      $match: {
        projectId: projectId,
        $or: [
          { securityLevelId: null },
          { securityLevelId: { $in: accessibleLevelIds } },
          { reporterId: userId },
          { assigneeId: userId }
        ]
      }
    },
    { $sort: { createdAt: -1 } },
    { $limit: limit },
    {
      $project: {
        issueKey: 1,
        summary: 1,
        status: 1,
        assigneeId: 1,
        createdAt: 1
      }
    }
  ]).toArray();
}
```

### Query 3: Aggregation for Permission Analytics
```javascript
// Get permission distribution across projects
db.projects.aggregate([
  { $unwind: "$roleAssignments" },
  {
    $group: {
      _id: {
        projectId: "$_id",
        projectKey: "$key",
        roleId: "$roleAssignments.roleId"
      },
      count: { $sum: 1 }
    }
  },
  {
    $lookup: {
      from: "roles",
      localField: "_id.roleId",
      foreignField: "_id",
      as: "role"
    }
  },
  { $unwind: "$role" },
  {
    $project: {
      projectKey: "$_id.projectKey",
      roleName: "$role.name",
      assignmentCount: "$count"
    }
  },
  { $sort: { projectKey: 1, roleName: 1 } }
]);
```

---

# Part 3: DynamoDB Schema Design

## 🔧 Single-Table Design

### Table: AuthorizationTable

| PK | SK | Type | Data |
| :--- | :--- | :--- | :--- |
| `USER#<userId>` | `PROFILE` | User | email, displayName, isActive |
| `USER#<userId>` | `GROUP#<groupId>` | Membership | joinedAt |
| `USER#<userId>` | `ROLE#<projectId>#<roleId>` | RoleAssignment | grantedAt, expiresAt |
| `GROUP#<groupId>` | `METADATA` | Group | name, description |
| `PROJECT#<projectId>` | `METADATA` | Project | key, name, leadUserId |
| `PROJECT#<projectId>` | `ROLE#<roleId>#<principalType>#<principalId>` | RoleGrant | grantedAt |
| `ROLE#<roleId>` | `METADATA` | Role | name, permissions[] |
| `ROLE#<roleId>` | `PERMISSION#<permissionCode>` | RolePermission | - |
| `ISSUE#<issueId>` | `METADATA` | Issue | issueKey, summary, status |
| `ISSUE#<issueId>` | `RELATION#<relation>#<userId>` | IssueRelation | - |

### GSI1: For Querying by Project
| GSI1PK | GSI1SK | 
| :--- | :--- |
| `PROJECT#<projectId>` | `USER#<userId>` |
| `PROJECT#<projectId>` | `ISSUE#<issueId>` |

### GSI2: For Permission Lookups
| GSI2PK | GSI2SK |
| :--- | :--- |
| `PERMISSION#<permissionCode>` | `ROLE#<roleId>` |

```python
import boto3
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('AuthorizationTable')

# =============================================================================
# CREATE OPERATIONS
# =============================================================================

def create_user(user_id, email, display_name):
    table.put_item(Item={
        'PK': f'USER#{user_id}',
        'SK': 'PROFILE',
        'Type': 'User',
        'email': email,
        'displayName': display_name,
        'isActive': True,
        'createdAt': datetime.utcnow().isoformat()
    })

def assign_role_to_user(user_id, project_id, role_id, granted_by, expires_at=None):
    # Write to user's record
    table.put_item(Item={
        'PK': f'USER#{user_id}',
        'SK': f'ROLE#{project_id}#{role_id}',
        'Type': 'RoleAssignment',
        'projectId': project_id,
        'roleId': role_id,
        'grantedAt': datetime.utcnow().isoformat(),
        'grantedBy': granted_by,
        'expiresAt': expires_at,
        'GSI1PK': f'PROJECT#{project_id}',
        'GSI1SK': f'USER#{user_id}'
    })
    
    # Write to project's record for reverse lookup
    table.put_item(Item={
        'PK': f'PROJECT#{project_id}',
        'SK': f'ROLE#{role_id}#user#{user_id}',
        'Type': 'RoleGrant',
        'userId': user_id,
        'grantedAt': datetime.utcnow().isoformat()
    })

def create_role(role_id, name, permissions):
    # Role metadata
    table.put_item(Item={
        'PK': f'ROLE#{role_id}',
        'SK': 'METADATA',
        'Type': 'Role',
        'name': name,
        'permissions': permissions
    })
    
    # Individual permission entries for GSI lookups
    for perm in permissions:
        table.put_item(Item={
            'PK': f'ROLE#{role_id}',
            'SK': f'PERMISSION#{perm}',
            'Type': 'RolePermission',
            'GSI2PK': f'PERMISSION#{perm}',
            'GSI2SK': f'ROLE#{role_id}'
        })

# =============================================================================
# PERMISSION CHECK QUERIES
# =============================================================================

def has_permission(user_id, project_id, permission_code):
    """Check if user has a specific permission on a project."""
    
    # Step 1: Get user's roles on this project
    response = table.query(
        KeyConditionExpression=Key('PK').eq(f'USER#{user_id}') & 
                                Key('SK').begins_with(f'ROLE#{project_id}#')
    )
    
    if not response['Items']:
        return False
    
    # Step 2: Check each role for the permission
    for item in response['Items']:
        role_id = item['roleId']
        
        # Check if role has this permission
        perm_response = table.get_item(Key={
            'PK': f'ROLE#{role_id}',
            'SK': f'PERMISSION#{permission_code}'
        })
        
        if 'Item' in perm_response:
            return True
    
    return False

def get_user_permissions_on_project(user_id, project_id):
    """Get all permissions a user has on a project."""
    
    # Get user's roles on project
    response = table.query(
        KeyConditionExpression=Key('PK').eq(f'USER#{user_id}') & 
                                Key('SK').begins_with(f'ROLE#{project_id}#')
    )
    
    all_permissions = set()
    
    for item in response['Items']:
        role_id = item['roleId']
        
        # Get role metadata with permissions
        role_response = table.get_item(Key={
            'PK': f'ROLE#{role_id}',
            'SK': 'METADATA'
        })
        
        if 'Item' in role_response:
            all_permissions.update(role_response['Item'].get('permissions', []))
    
    return list(all_permissions)

def get_users_with_permission_on_project(project_id, permission_code):
    """Find all users who have a specific permission on a project."""
    
    # Step 1: Find roles that have this permission (via GSI2)
    response = table.query(
        IndexName='GSI2',
        KeyConditionExpression=Key('GSI2PK').eq(f'PERMISSION#{permission_code}')
    )
    
    role_ids = [item['PK'].replace('ROLE#', '') for item in response['Items']]
    
    # Step 2: Find users with these roles on the project (via GSI1)
    users = set()
    
    for role_id in role_ids:
        proj_response = table.query(
            KeyConditionExpression=Key('PK').eq(f'PROJECT#{project_id}') &
                                    Key('SK').begins_with(f'ROLE#{role_id}#user#')
        )
        
        for item in proj_response['Items']:
            users.add(item['userId'])
    
    return list(users)
```

---

# Part 4: Cassandra Schema Design

## 🗺️ Query-First Table Design

```cql
-- =============================================================================
-- KEYSPACE
-- =============================================================================

CREATE KEYSPACE authorization
WITH replication = {'class': 'NetworkTopologyStrategy', 'dc1': 3, 'dc2': 3};

USE authorization;

-- =============================================================================
-- TABLE: User Permissions by Project (Main Query)
-- Query: "What permissions does user X have on project Y?"
-- =============================================================================

CREATE TABLE user_project_permissions (
    user_id UUID,
    project_id UUID,
    permission_code TEXT,
    role_id UUID,
    granted_at TIMESTAMP,
    expires_at TIMESTAMP,
    PRIMARY KEY ((user_id, project_id), permission_code)
) WITH CLUSTERING ORDER BY (permission_code ASC);

-- Insert (denormalized from role)
INSERT INTO user_project_permissions (user_id, project_id, permission_code, role_id, granted_at)
VALUES (uuid(), uuid(), 'issues:edit', uuid(), toTimestamp(now()));

-- Query: Check if user has permission
SELECT * FROM user_project_permissions
WHERE user_id = ? AND project_id = ? AND permission_code = 'issues:edit';

-- Query: Get all permissions for user on project
SELECT permission_code FROM user_project_permissions
WHERE user_id = ? AND project_id = ?;

-- =============================================================================
-- TABLE: Project Role Assignments
-- Query: "Who has what role on project X?"
-- =============================================================================

CREATE TABLE project_role_assignments (
    project_id UUID,
    role_id UUID,
    principal_type TEXT,   -- 'user', 'group'
    principal_id UUID,
    granted_at TIMESTAMP,
    granted_by UUID,
    PRIMARY KEY ((project_id), role_id, principal_type, principal_id)
);

-- Query: Get all role assignments for a project
SELECT * FROM project_role_assignments WHERE project_id = ?;

-- =============================================================================
-- TABLE: User Roles by Project
-- Query: "What roles does user X have on project Y?"
-- =============================================================================

CREATE TABLE user_roles_by_project (
    user_id UUID,
    project_id UUID,
    role_id UUID,
    role_name TEXT,        -- Denormalized
    granted_at TIMESTAMP,
    expires_at TIMESTAMP,
    PRIMARY KEY ((user_id), project_id, role_id)
);

-- Query
SELECT role_id, role_name FROM user_roles_by_project
WHERE user_id = ? AND project_id = ?;

-- =============================================================================
-- TABLE: Issue Security Access
-- Query: "Can user X see issue Y?"
-- =============================================================================

CREATE TABLE issue_security_access (
    issue_id UUID,
    accessor_type TEXT,    -- 'user', 'group', 'role', 'reporter', 'assignee'
    accessor_id UUID,      -- NULL for reporter/assignee
    project_id UUID,
    security_level_id UUID,
    PRIMARY KEY ((issue_id), accessor_type, accessor_id)
);

-- Query: Check if user can access issue
SELECT * FROM issue_security_access
WHERE issue_id = ? AND accessor_type = 'user' AND accessor_id = ?;

-- =============================================================================
-- TABLE: Audit Log
-- Query: "Who accessed resource X in the last 24 hours?"
-- =============================================================================

CREATE TABLE permission_audit_log (
    resource_type TEXT,
    resource_id UUID,
    event_date DATE,       -- Partition by day for time-bounded queries
    event_time TIMESTAMP,
    user_id UUID,
    action TEXT,
    result TEXT,           -- 'allowed', 'denied'
    permission_checked TEXT,
    PRIMARY KEY ((resource_type, resource_id, event_date), event_time)
) WITH CLUSTERING ORDER BY (event_time DESC)
  AND default_time_to_live = 2592000;  -- 30 days TTL

-- Query: Get access log for issue in last 24 hours
SELECT * FROM permission_audit_log
WHERE resource_type = 'issue' 
  AND resource_id = ?
  AND event_date = toDate(now())
LIMIT 100;
```

---

# Part 5: Permission Groups, Rules & Policies (PBAC/ABAC)

## 📦 Permission Groups Schema (SQL)

Permission groups bundle related permissions for easier management.

```sql
-- =============================================================================
-- PERMISSION GROUPS
-- =============================================================================

CREATE TABLE permission_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    category VARCHAR(100),                       -- 'project', 'issue', 'admin', 'security'
    is_system BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Permissions in groups (many-to-many)
CREATE TABLE permission_group_members (
    permission_group_id UUID REFERENCES permission_groups(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (permission_group_id, permission_id)
);

-- Pre-populate permission groups
INSERT INTO permission_groups (name, description, category, is_system) VALUES
('Issue Management', 'All issue-related permissions', 'issue', TRUE),
('Project Administration', 'Project admin permissions', 'project', TRUE),
('Comment Management', 'All comment permissions', 'issue', TRUE),
('Read Only', 'View-only permissions', 'general', TRUE),
('Security Administration', 'Security-related permissions', 'security', TRUE);

-- Populate group members
INSERT INTO permission_group_members (permission_group_id, permission_id)
SELECT pg.id, p.id
FROM permission_groups pg, permissions p
WHERE pg.name = 'Issue Management'
  AND p.code IN ('issues:read', 'issues:create', 'issues:edit', 'issues:delete', 
                 'issues:assign', 'issues:transition');

-- Assign permission groups to roles (instead of individual permissions)
CREATE TABLE role_permission_groups (
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    permission_group_id UUID REFERENCES permission_groups(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_group_id)
);

-- Query: Get all permissions for a role (via groups)
SELECT DISTINCT p.code
FROM roles r
JOIN role_permission_groups rpg ON rpg.role_id = r.id
JOIN permission_group_members pgm ON pgm.permission_group_id = rpg.permission_group_id
JOIN permissions p ON p.id = pgm.permission_id
WHERE r.id = $1;
```

---

## 📜 Rules Schema (SQL)

Rules define **conditions** that must be met for a permission to apply.

```sql
-- =============================================================================
-- RULES (Conditions)
-- =============================================================================

CREATE TYPE rule_operator AS ENUM (
    'equals', 'not_equals', 'contains', 'not_contains',
    'greater_than', 'less_than', 'greater_or_equal', 'less_or_equal',
    'in', 'not_in', 'is_null', 'is_not_null',
    'matches_regex', 'starts_with', 'ends_with'
);

CREATE TYPE rule_attribute_source AS ENUM (
    'user',          -- user.department, user.level, user.country
    'resource',      -- resource.status, resource.priority, resource.type
    'context',       -- context.ip_address, context.time, context.device
    'environment'    -- environment.region, environment.is_production
);

CREATE TABLE rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    
    -- Left-hand side (attribute to check)
    attribute_source rule_attribute_source NOT NULL,
    attribute_path VARCHAR(255) NOT NULL,        -- 'department', 'status', 'ip_address'
    
    -- Operator
    operator rule_operator NOT NULL,
    
    -- Right-hand side (value to compare against)
    compare_value TEXT,                          -- Single value for equals, etc.
    compare_values TEXT[],                       -- Array for 'in', 'not_in'
    compare_attribute_source rule_attribute_source,  -- For comparing two attributes
    compare_attribute_path VARCHAR(255),
    
    -- Metadata
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pre-populate common rules
INSERT INTO rules (name, attribute_source, attribute_path, operator, compare_value) VALUES
-- Time-based rules
('Business Hours Only', 'context', 'hour_of_day', 'greater_or_equal', '9'),
('Before End of Business', 'context', 'hour_of_day', 'less_than', '18'),
('Weekday Only', 'context', 'day_of_week', 'in', NULL),  -- compare_values = ['Mon','Tue','Wed','Thu','Fri']

-- Location-based rules
('Corporate Network', 'context', 'ip_cidr', 'in', NULL),  -- compare_values = ['10.0.0.0/8', '192.168.0.0/16']
('US Region', 'context', 'country_code', 'equals', 'US'),

-- User attribute rules
('Engineering Department', 'user', 'department', 'equals', 'Engineering'),
('Senior Level', 'user', 'level', 'greater_or_equal', '5'),
('Manager Role', 'user', 'job_title', 'contains', 'Manager'),

-- Resource attribute rules
('Open Issues Only', 'resource', 'status', 'in', NULL),  -- ['open', 'in_progress']
('High Priority', 'resource', 'priority', 'equals', 'high'),
('Same Department', 'user', 'department', 'equals', NULL);  -- compare_attribute: resource.department

UPDATE rules SET compare_values = ARRAY['Mon','Tue','Wed','Thu','Fri'] WHERE name = 'Weekday Only';
UPDATE rules SET compare_values = ARRAY['10.0.0.0/8', '192.168.0.0/16'] WHERE name = 'Corporate Network';
UPDATE rules SET compare_values = ARRAY['open', 'in_progress', 'reopened'] WHERE name = 'Open Issues Only';
UPDATE rules SET compare_attribute_source = 'resource', compare_attribute_path = 'department' 
WHERE name = 'Same Department';

-- =============================================================================
-- RULE GROUPS (Combine rules with AND/OR logic)
-- =============================================================================

CREATE TYPE rule_group_logic AS ENUM ('AND', 'OR');

CREATE TABLE rule_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    logic rule_group_logic DEFAULT 'AND',        -- All rules must pass (AND) or any (OR)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE rule_group_members (
    rule_group_id UUID REFERENCES rule_groups(id) ON DELETE CASCADE,
    rule_id UUID REFERENCES rules(id) ON DELETE CASCADE,
    is_negated BOOLEAN DEFAULT FALSE,            -- Invert the rule result
    order_index INT DEFAULT 0,
    PRIMARY KEY (rule_group_id, rule_id)
);

-- Example: Business Hours Rule Group
INSERT INTO rule_groups (name, logic) VALUES ('Business Hours Access', 'AND');

INSERT INTO rule_group_members (rule_group_id, rule_id, order_index)
SELECT rg.id, r.id, 
    CASE r.name 
        WHEN 'Business Hours Only' THEN 1
        WHEN 'Before End of Business' THEN 2
        WHEN 'Weekday Only' THEN 3
    END
FROM rule_groups rg, rules r
WHERE rg.name = 'Business Hours Access'
  AND r.name IN ('Business Hours Only', 'Before End of Business', 'Weekday Only');
```

---

## 📋 Policies Schema (SQL)

Policies combine **subjects**, **permissions**, **resources**, and **rules**.

```sql
-- =============================================================================
-- POLICIES
-- =============================================================================

CREATE TYPE policy_effect AS ENUM ('allow', 'deny');
CREATE TYPE policy_priority AS ENUM ('low', 'medium', 'high', 'critical');

CREATE TABLE policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    
    -- Effect: Allow or Deny
    effect policy_effect NOT NULL DEFAULT 'allow',
    
    -- Priority (deny with higher priority wins)
    priority policy_priority DEFAULT 'medium',
    priority_order INT DEFAULT 100,              -- Numeric for sorting
    
    -- Subject filter (who does this apply to?)
    subject_type VARCHAR(50),                    -- 'user', 'group', 'role', 'any'
    subject_id UUID,                             -- NULL for 'any'
    subject_attribute_rules UUID REFERENCES rule_groups(id),  -- Dynamic subject matching
    
    -- Resource filter (what does this apply to?)
    resource_type VARCHAR(50),                   -- 'project', 'issue', 'any'
    resource_id UUID,                            -- NULL for all resources of type
    resource_attribute_rules UUID REFERENCES rule_groups(id), -- Dynamic resource matching
    
    -- Context rules (when does this apply?)
    context_rules UUID REFERENCES rule_groups(id),
    
    -- Metadata
    is_active BOOLEAN DEFAULT TRUE,
    starts_at TIMESTAMPTZ,                       -- Time-bound policies
    ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES users(id)
);

CREATE INDEX idx_policies_active ON policies(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_policies_subject ON policies(subject_type, subject_id);
CREATE INDEX idx_policies_resource ON policies(resource_type, resource_id);
CREATE INDEX idx_policies_priority ON policies(priority_order DESC);

-- Policy-Permission mapping (what permissions does this policy grant/deny?)
CREATE TABLE policy_permissions (
    policy_id UUID REFERENCES policies(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (policy_id, permission_id)
);

-- Policy-Permission Group mapping
CREATE TABLE policy_permission_groups (
    policy_id UUID REFERENCES policies(id) ON DELETE CASCADE,
    permission_group_id UUID REFERENCES permission_groups(id) ON DELETE CASCADE,
    PRIMARY KEY (policy_id, permission_group_id)
);

-- =============================================================================
-- EXAMPLE POLICIES
-- =============================================================================

-- Policy 1: Developers can edit issues during business hours only
INSERT INTO policies (name, effect, priority, subject_type, resource_type, context_rules) 
VALUES (
    'Developers Edit Issues - Business Hours',
    'allow',
    'medium',
    'role',
    'issue',
    (SELECT id FROM rule_groups WHERE name = 'Business Hours Access')
);

-- Link to Developer role
UPDATE policies SET subject_id = (SELECT id FROM roles WHERE name = 'Developer')
WHERE name = 'Developers Edit Issues - Business Hours';

-- Grant edit permission
INSERT INTO policy_permissions (policy_id, permission_id)
SELECT p.id, perm.id
FROM policies p, permissions perm
WHERE p.name = 'Developers Edit Issues - Business Hours'
  AND perm.code = 'issues:edit';

-- Policy 2: Deny delete for everyone except admins
INSERT INTO policies (name, effect, priority, priority_order, subject_type, resource_type)
VALUES ('Deny Delete Except Admin', 'deny', 'high', 200, 'any', 'issue');

INSERT INTO policy_permissions (policy_id, permission_id)
SELECT p.id, perm.id
FROM policies p, permissions perm
WHERE p.name = 'Deny Delete Except Admin'
  AND perm.code = 'issues:delete';

-- Policy 3: Allow admin override
INSERT INTO policies (name, effect, priority, priority_order, subject_type, resource_type)
VALUES ('Admin Override - Full Access', 'allow', 'critical', 1000, 'role', 'any');

UPDATE policies SET subject_id = (SELECT id FROM roles WHERE name = 'Administrator')
WHERE name = 'Admin Override - Full Access';
```

---

## ⚡ Policy Evaluation Function (SQL)

```sql
-- =============================================================================
-- POLICY DECISION POINT (PDP) FUNCTION
-- =============================================================================

CREATE OR REPLACE FUNCTION evaluate_policies(
    p_user_id UUID,
    p_permission_code VARCHAR(100),
    p_resource_type VARCHAR(50),
    p_resource_id UUID,
    p_context JSONB DEFAULT '{}'::JSONB
) RETURNS TABLE (
    decision VARCHAR(10),
    policy_name VARCHAR(255),
    policy_id UUID,
    reason TEXT
) AS $$
DECLARE
    v_user_roles UUID[];
    v_user_groups UUID[];
    v_user_attrs JSONB;
    v_resource_attrs JSONB;
BEGIN
    -- Get user's roles and groups
    SELECT ARRAY_AGG(DISTINCT role_id) INTO v_user_roles
    FROM user_project_roles WHERE user_id = p_user_id;
    
    SELECT ARRAY_AGG(DISTINCT group_id) INTO v_user_groups
    FROM user_groups WHERE user_id = p_user_id;
    
    -- Get user attributes (for rule evaluation)
    SELECT jsonb_build_object(
        'id', id,
        'email', email,
        'department', COALESCE(custom_fields->>'department', 'unknown'),
        'level', COALESCE((custom_fields->>'level')::INT, 1),
        'country', COALESCE(custom_fields->>'country', 'unknown')
    ) INTO v_user_attrs
    FROM users WHERE id = p_user_id;
    
    -- Get resource attributes
    IF p_resource_type = 'issue' THEN
        SELECT jsonb_build_object(
            'id', id,
            'status', status,
            'priority', priority,
            'issue_type', issue_type,
            'reporter_id', reporter_id,
            'assignee_id', assignee_id
        ) INTO v_resource_attrs
        FROM issues WHERE id = p_resource_id;
    END IF;
    
    -- Find matching policies ordered by priority
    RETURN QUERY
    WITH matching_policies AS (
        SELECT 
            pol.id,
            pol.name,
            pol.effect,
            pol.priority_order,
            -- Check if policy applies to this user
            CASE
                WHEN pol.subject_type = 'any' THEN TRUE
                WHEN pol.subject_type = 'user' AND pol.subject_id = p_user_id THEN TRUE
                WHEN pol.subject_type = 'role' AND pol.subject_id = ANY(v_user_roles) THEN TRUE
                WHEN pol.subject_type = 'group' AND pol.subject_id = ANY(v_user_groups) THEN TRUE
                ELSE FALSE
            END AS subject_matches,
            -- Check if policy applies to this resource
            CASE
                WHEN pol.resource_type = 'any' THEN TRUE
                WHEN pol.resource_type = p_resource_type AND pol.resource_id IS NULL THEN TRUE
                WHEN pol.resource_type = p_resource_type AND pol.resource_id = p_resource_id THEN TRUE
                ELSE FALSE
            END AS resource_matches
        FROM policies pol
        JOIN policy_permissions pp ON pp.policy_id = pol.id
        JOIN permissions perm ON perm.id = pp.permission_id
        WHERE pol.is_active = TRUE
          AND perm.code = p_permission_code
          AND (pol.starts_at IS NULL OR pol.starts_at <= NOW())
          AND (pol.ends_at IS NULL OR pol.ends_at > NOW())
    )
    SELECT 
        mp.effect::VARCHAR(10) AS decision,
        mp.name AS policy_name,
        mp.id AS policy_id,
        'Policy matched: subject=' || 
            CASE WHEN mp.subject_matches THEN 'YES' ELSE 'NO' END ||
            ', resource=' || 
            CASE WHEN mp.resource_matches THEN 'YES' ELSE 'NO' END
        AS reason
    FROM matching_policies mp
    WHERE mp.subject_matches = TRUE AND mp.resource_matches = TRUE
    ORDER BY mp.priority_order DESC
    LIMIT 1;
    
    -- If no policy matched, default deny
    IF NOT FOUND THEN
        RETURN QUERY SELECT 
            'deny'::VARCHAR(10),
            'Default Deny'::VARCHAR(255),
            NULL::UUID,
            'No matching policy found'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Usage:
SELECT * FROM evaluate_policies(
    'user-uuid'::UUID,
    'issues:edit',
    'issue',
    'issue-uuid'::UUID,
    '{"ip_address": "10.0.1.50", "hour_of_day": 14}'::JSONB
);
```

---

## 📦 MongoDB: Permission Groups, Rules & Policies

### Permission Groups Collection
```javascript
// Collection: permissionGroups
{
  _id: ObjectId("..."),
  name: "Issue Management",
  description: "All issue-related permissions",
  category: "issue",
  isSystem: true,
  permissions: [
    "issues:read",
    "issues:create",
    "issues:edit",
    "issues:delete",
    "issues:assign",
    "issues:transition"
  ],
  createdAt: ISODate("2024-01-01T00:00:00Z")
}

db.permissionGroups.createIndex({ name: 1 }, { unique: true });
db.permissionGroups.createIndex({ category: 1 });
```

### Rules Collection
```javascript
// Collection: rules
{
  _id: ObjectId("..."),
  name: "Business Hours Only",
  description: "Allow access only during 9 AM - 6 PM",
  
  // Condition definition
  condition: {
    attributeSource: "context",      // "user", "resource", "context", "environment"
    attributePath: "hourOfDay",
    operator: "between",             // "equals", "in", "greaterThan", "lessThan", "between", "matches"
    value: { min: 9, max: 18 }
  },
  
  isActive: true,
  createdAt: ISODate("2024-01-01T00:00:00Z")
}

// Rule: Same Department
{
  _id: ObjectId("..."),
  name: "Same Department",
  description: "User's department must match resource's department",
  condition: {
    attributeSource: "user",
    attributePath: "department",
    operator: "equals",
    compareAttributeSource: "resource",
    compareAttributePath: "department"
  },
  isActive: true
}

// Rule: Corporate Network
{
  _id: ObjectId("..."),
  name: "Corporate Network",
  condition: {
    attributeSource: "context",
    attributePath: "ipAddress",
    operator: "inCidr",
    value: ["10.0.0.0/8", "192.168.0.0/16", "172.16.0.0/12"]
  },
  isActive: true
}
```

### Rule Groups Collection
```javascript
// Collection: ruleGroups
{
  _id: ObjectId("..."),
  name: "Business Hours Access",
  description: "Requires business hours + corporate network",
  logic: "AND",  // "AND" or "OR"
  rules: [
    { ruleId: ObjectId("business-hours-rule"), negated: false, order: 1 },
    { ruleId: ObjectId("weekday-rule"), negated: false, order: 2 },
    { ruleId: ObjectId("corp-network-rule"), negated: false, order: 3 }
  ],
  createdAt: ISODate("2024-01-01T00:00:00Z")
}
```

### Policies Collection
```javascript
// Collection: policies
{
  _id: ObjectId("..."),
  name: "Developers Edit Issues - Business Hours",
  description: "Developers can edit issues during business hours only",
  
  effect: "allow",  // "allow" or "deny"
  priority: 100,    // Higher priority wins
  
  // Subject (who does this apply to?)
  subject: {
    type: "role",   // "user", "group", "role", "any"
    id: ObjectId("developer-role-id"),
    // OR dynamic matching
    attributeRules: ObjectId("rule-group-id")
  },
  
  // Resource (what does this apply to?)
  resource: {
    type: "issue",  // "project", "issue", "board", "any"
    id: null,       // null = all issues
    attributeRules: null
  },
  
  // Permissions granted/denied
  permissions: ["issues:edit"],
  permissionGroups: [],
  
  // Context rules (when does this apply?)
  contextRules: ObjectId("business-hours-rule-group"),
  
  // Time bounds
  startsAt: null,
  endsAt: null,
  
  isActive: true,
  createdAt: ISODate("2024-01-01T00:00:00Z"),
  createdBy: ObjectId("admin-user")
}

// Policy: Deny Delete Except Admin
{
  _id: ObjectId("..."),
  name: "Deny Delete Except Admin",
  effect: "deny",
  priority: 200,
  subject: { type: "any" },
  resource: { type: "issue" },
  permissions: ["issues:delete"],
  isActive: true
}

// Policy: Admin Override
{
  _id: ObjectId("..."),
  name: "Admin Override - Full Access",
  effect: "allow",
  priority: 1000,
  subject: { type: "role", id: ObjectId("admin-role-id") },
  resource: { type: "any" },
  permissions: ["*"],  // Wildcard for all permissions
  isActive: true
}

db.policies.createIndex({ isActive: 1, priority: -1 });
db.policies.createIndex({ "subject.type": 1, "subject.id": 1 });
db.policies.createIndex({ "resource.type": 1, "resource.id": 1 });
```

### Policy Evaluation Function (MongoDB)
```javascript
async function evaluatePolicy(userId, permissionCode, resourceType, resourceId, context = {}) {
  const user = await db.users.findOne({ _id: userId });
  if (!user) return { decision: "deny", reason: "User not found" };
  
  const userRoles = await db.roles.find({ 
    _id: { $in: user.directRoles?.map(r => r.roleId) || [] } 
  }).toArray();
  const userRoleIds = userRoles.map(r => r._id);
  const userGroupIds = user.groups || [];
  
  // Find all potentially matching policies
  const policies = await db.policies.aggregate([
    {
      $match: {
        isActive: true,
        $or: [
          { permissions: permissionCode },
          { permissions: "*" },
          { permissionGroups: { $exists: true } }
        ],
        $or: [
          { startsAt: null },
          { startsAt: { $lte: new Date() } }
        ],
        $or: [
          { endsAt: null },
          { endsAt: { $gt: new Date() } }
        ]
      }
    },
    { $sort: { priority: -1 } }  // Higher priority first
  ]).toArray();
  
  // Evaluate each policy
  for (const policy of policies) {
    // Check subject match
    const subjectMatches = await matchSubject(policy.subject, userId, userRoleIds, userGroupIds, user);
    if (!subjectMatches) continue;
    
    // Check resource match
    const resourceMatches = matchResource(policy.resource, resourceType, resourceId);
    if (!resourceMatches) continue;
    
    // Check context rules
    if (policy.contextRules) {
      const contextPasses = await evaluateRuleGroup(policy.contextRules, { user, context });
      if (!contextPasses) continue;
    }
    
    // Check if permission is in this policy
    if (!policy.permissions.includes(permissionCode) && !policy.permissions.includes("*")) {
      // Check permission groups
      const permMatches = await db.permissionGroups.findOne({
        _id: { $in: policy.permissionGroups || [] },
        permissions: permissionCode
      });
      if (!permMatches) continue;
    }
    
    // Policy matched!
    return {
      decision: policy.effect,
      policyName: policy.name,
      policyId: policy._id,
      reason: `Matched policy: ${policy.name}`
    };
  }
  
  // Default deny if no policy matched
  return { decision: "deny", reason: "No matching policy found" };
}

async function matchSubject(subject, userId, userRoleIds, userGroupIds, user) {
  if (subject.type === "any") return true;
  if (subject.type === "user" && subject.id.equals(userId)) return true;
  if (subject.type === "role" && userRoleIds.some(r => r.equals(subject.id))) return true;
  if (subject.type === "group" && userGroupIds.some(g => g.equals(subject.id))) return true;
  
  // Dynamic attribute matching
  if (subject.attributeRules) {
    return await evaluateRuleGroup(subject.attributeRules, { user });
  }
  
  return false;
}

function matchResource(resource, resourceType, resourceId) {
  if (resource.type === "any") return true;
  if (resource.type !== resourceType) return false;
  if (resource.id === null) return true;  // All resources of this type
  if (resource.id.equals(resourceId)) return true;
  return false;
}

async function evaluateRuleGroup(ruleGroupId, data) {
  const ruleGroup = await db.ruleGroups.findOne({ _id: ruleGroupId });
  if (!ruleGroup) return true;  // No rules = pass
  
  const results = await Promise.all(
    ruleGroup.rules.map(async ({ ruleId, negated }) => {
      const rule = await db.rules.findOne({ _id: ruleId });
      const result = evaluateRule(rule, data);
      return negated ? !result : result;
    })
  );
  
  if (ruleGroup.logic === "AND") {
    return results.every(r => r === true);
  } else {
    return results.some(r => r === true);
  }
}

function evaluateRule(rule, data) {
  const { attributeSource, attributePath, operator, value, compareAttributeSource, compareAttributePath } = rule.condition;
  
  // Get left-hand value
  let leftValue;
  if (attributeSource === "user") leftValue = data.user?.[attributePath];
  else if (attributeSource === "resource") leftValue = data.resource?.[attributePath];
  else if (attributeSource === "context") leftValue = data.context?.[attributePath];
  
  // Get right-hand value
  let rightValue = value;
  if (compareAttributeSource) {
    if (compareAttributeSource === "user") rightValue = data.user?.[compareAttributePath];
    else if (compareAttributeSource === "resource") rightValue = data.resource?.[compareAttributePath];
  }
  
  // Evaluate operator
  switch (operator) {
    case "equals": return leftValue === rightValue;
    case "notEquals": return leftValue !== rightValue;
    case "in": return Array.isArray(rightValue) && rightValue.includes(leftValue);
    case "notIn": return Array.isArray(rightValue) && !rightValue.includes(leftValue);
    case "greaterThan": return leftValue > rightValue;
    case "lessThan": return leftValue < rightValue;
    case "between": return leftValue >= rightValue.min && leftValue <= rightValue.max;
    case "contains": return String(leftValue).includes(String(rightValue));
    case "matches": return new RegExp(rightValue).test(String(leftValue));
    case "inCidr": return checkIpInCidr(leftValue, rightValue);  // Implement CIDR check
    default: return false;
  }
}

// Usage:
const result = await evaluatePolicy(
  userId,
  "issues:edit",
  "issue",
  issueId,
  { hourOfDay: 14, ipAddress: "10.0.1.50", dayOfWeek: "Wed" }
);
console.log(result);
// { decision: "allow", policyName: "Developers Edit...", reason: "..." }
```

---

## 🔧 DynamoDB: Policies Table Design

```python
# Single Table Design for Policies

# PK: POLICY#<policyId>
# SK: METADATA

# GSI1PK: SUBJECT#<subjectType>#<subjectId>
# GSI1SK: PRIORITY#<priorityOrder>

# GSI2PK: RESOURCE#<resourceType>#<resourceId>
# GSI2SK: PRIORITY#<priorityOrder>

def create_policy(policy_id, name, effect, priority, subject, resource, permissions, context_rules=None):
    table.put_item(Item={
        'PK': f'POLICY#{policy_id}',
        'SK': 'METADATA',
        'name': name,
        'effect': effect,  # 'allow' or 'deny'
        'priority': priority,
        'subject': subject,  # {'type': 'role', 'id': 'role-uuid'}
        'resource': resource,  # {'type': 'issue', 'id': None}
        'permissions': permissions,
        'contextRules': context_rules,
        'isActive': True,
        'createdAt': datetime.utcnow().isoformat(),
        # GSIs
        'GSI1PK': f"SUBJECT#{subject['type']}#{subject.get('id', 'ANY')}",
        'GSI1SK': f"PRIORITY#{str(priority).zfill(5)}",
        'GSI2PK': f"RESOURCE#{resource['type']}#{resource.get('id', 'ANY')}",
        'GSI2SK': f"PRIORITY#{str(priority).zfill(5)}"
    })

def evaluate_policy_dynamo(user_id, permission_code, resource_type, resource_id, context=None):
    # Get user's roles and groups
    user_response = table.query(
        KeyConditionExpression=Key('PK').eq(f'USER#{user_id}')
    )
    user_data = {item['SK']: item for item in user_response['Items']}
    
    user_roles = [sk.split('#')[1] for sk in user_data if sk.startswith('ROLE#')]
    user_groups = [sk.split('#')[1] for sk in user_data if sk.startswith('GROUP#')]
    
    # Build list of subject queries
    subject_queries = [
        f"SUBJECT#any#ANY",
        f"SUBJECT#user#{user_id}"
    ]
    for role_id in user_roles:
        subject_queries.append(f"SUBJECT#role#{role_id}")
    for group_id in user_groups:
        subject_queries.append(f"SUBJECT#group#{group_id}")
    
    # Query policies by subject (via GSI1)
    all_policies = []
    for subject_pk in subject_queries:
        response = table.query(
            IndexName='GSI1',
            KeyConditionExpression=Key('GSI1PK').eq(subject_pk),
            ScanIndexForward=False  # Highest priority first
        )
        all_policies.extend(response['Items'])
    
    # Sort by priority (highest first)
    all_policies.sort(key=lambda p: int(p['GSI1SK'].split('#')[1]), reverse=True)
    
    # Evaluate each policy
    for policy in all_policies:
        if not policy.get('isActive'):
            continue
            
        # Check resource match
        res = policy['resource']
        if res['type'] != 'any' and res['type'] != resource_type:
            continue
        if res.get('id') and res['id'] != resource_id:
            continue
        
        # Check permission match
        if permission_code not in policy['permissions'] and '*' not in policy['permissions']:
            continue
        
        # Check context rules (simplified)
        if policy.get('contextRules'):
            if not evaluate_context_rules(policy['contextRules'], context):
                continue
        
        # Policy matched!
        return {
            'decision': policy['effect'],
            'policyName': policy['name'],
            'reason': f"Matched policy: {policy['name']}"
        }
    
    return {'decision': 'deny', 'reason': 'No matching policy found'}
```

---

## ✅ Principal Architect Checklist

| # | Item | SQL | NoSQL |
| :--- | :--- | :--- | :--- |
| 1 | Permission check is O(1) or O(log n) | Use indexed CTEs | Use lookup tables |
| 2 | Role inheritance is resolvable | Recursive CTE | GraphLookup / Denormalize |
| 3 | Security levels are enforced | JOIN in WHERE | Filter in aggregation |
| 4 | Custom fields are queryable | EAV + JSONB | Embedded + indexed |
| 5 | Audit trail is complete | Trigger + table | TTL + partition by date |
| 6 | Expired grants are excluded | `expires_at > NOW()` | Filter or TTL |
| 7 | Group membership is recursive | Recursive CTE | $graphLookup |
| 8 | Bulk permission check is efficient | Batch query | BatchGetItem |

---

## 🔗 Related Documents
*   [RDBMS Internals](../database/rdbms-internals-guide.md) — Indexing for permission queries.
*   [NoSQL Architecture](../database/nosql-architecture-guide.md) — DynamoDB, Cassandra patterns.
*   [JIRA Authorization](./jira-authorization-guide.md) — JIRA-specific implementation.
