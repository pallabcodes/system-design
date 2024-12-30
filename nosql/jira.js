// # Model: user_contacts
db.user_contacts.insertOne({
    user_id: new ObjectId(),
    provider: '8670364849',
    type: 'mobile',
    is_primary: true
  });
  
  db.user_contacts.createIndex({ user_id: 1 });
  db.user_contacts.createIndex({ provider: 1 });
  
  db.user_contacts.find();
  
  db.users.createIndex({ user_id: 1});
  // db.users.createIndex({ user_id: 1}, { partialFilterExpression: { is_primary: 1 } });
  
  // # Model: users
  db.users.insertOne({
    user_id: new ObjectId(),  // MongoDB's unique identifier
    username: 'johndoe',
    slug: 'john-doe',  // Automatically generated URL-friendly version of the username
    password: 'hashedpassword',
    first_name: 'John',
    last_name: 'Doe',
    date_of_birth: '1990-01-01',  // Store as a string in 'YYYY-MM-DD' format
    last_login_at: new Date(),
    status: 'active',  // Enum: 'active', 'inactive', 'suspended'
    gender: 'male',
    is_deleted: false,
    profile_pic: 'profile.jpg',
    bio: 'This is a bio.',
    created_at: new Date(),
    updated_at: new Date(),
    profile_privacy: 'public',  // Assume privacy level is a string
    notifications: {},
    social_links: {},
    allow_messages: true,
    email_notifications: false,  // Extracted from notifications JSONB
    sms_notifications: false,   // Extracted from notifications JSONB
    version: 1
  });
  
  db.users.createIndex({user_id: 1});
  // When searching by only status: 1 then indexing will work but also when searching by status: 1, status: active then composite index will work
  db.users.createIndex({ status: 1 }, { partialFilterExpression: { status: 'active' } });
  db.users.createIndex({ notifications: 'text' });
  db.users.createIndex({ email_notifications: 1 });
  db.users.createIndex({ sms_notifications: 1 });
  db.users.createIndex({ email: 1 }, {unique: true});
  db.users.createIndex({ username: 1 }, {unique: true});
  db.users.createIndex({ email: 1, status: 1 });
  
  db.users.find({});
  
  // # Model: roles
  db.roles.insertMany([
    {
      "role_id": 1,
      "role_title": "ADMIN",
      "isDeleted": false,
      "inherit_permissions": false,
      "parent_role_id": null  // No parent for Admin
    },
    {
      "role_id": 2,
      "role_title": "PROJECT MANAGER",
      "isDeleted": false,
      "inherit_permissions": true,
      "parent_role_id": 1  // Inherits permissions from Admin
    },
    {
      "role_id": 3,
      "role_title": "DEVELOPER",
      "isDeleted": false,
      "inherit_permissions": false,
      "parent_role_id": null  // No inheritance, standalone role
    },
    {
      "role_id": 4,
      "role_title": "TESTER",
      "isDeleted": false,
      "inherit_permissions": false,
      "parent_role_id": null  // No inheritance, standalone role
    }
  ]);
  
  db.roles.find();
  
  // # Model: permissions
  db.permissions.insertMany([
    {
      "permission_id": 1,
      "permission_type": "ticket",
      "permission_slug": "ticket",
      "permission_hash": "ticket_auto-generated_id",
      "permission_title": "ASSIGN_TICKET",
      "permission_description": "Allowed to assign ticket",
      "isDeleted": false
    },
    {
      "permission_id": 2,
      "permission_type": "sprint",
      "permission_slug": "sprint",
      "permission_hash": "sprint_auto-generated_id",
      "permission_title": "CREATE_SPRINT",
      "permission_description": "Allowed to create sprint",
      "isDeleted": false
    },
    {
      "permission_id": 3,
      "permission_type": "team",
      "permission_slug": "team",
      "permission_hash": "team_auto-generated_id",
      "permission_title": "CREATE_TEAM",
      "permission_description": "Allowed to create team",
      "isDeleted": false
    }
  ]);
  
  // db.getCollection("permissions").drop();
  
  db.permissions.find();
  
  // Model: User_roles
  db.user_roles.insertMany([
    {
      "user_id": "userId-1",
      "role_id": 1,  // ADMIN
      "resource_permissions": [1, 2, 3]  // Permissions for ticket, sprint, and team
    },
    {
      "user_id": "userId-2",
      "role_id": 2,  // PROJECT MANAGER
      "resource_permissions": [1, 2]  // Permissions for ticket and sprint
    },
    {
      "user_id": "userId-3",
      "role_id": 3,  // DEVELOPER
      "resource_permissions": [1]  // Permissions for ticket only
    },
    {
      "user_id": "userId-4",
      "role_id": 4,  // TESTER
      "resource_permissions": [1]  // Permissions for ticket only
    }
  ]);
  
  // db.getCollection("user_roles").drop();
  
  db.user_roles.find();
  
  // Model: User_Permissions
  
  db.user_permissions.insertMany([
    {
      "user_id": "userId-1",
      "permissions": [1, 2, 3],  // Permissions inherited from Admin
      "isDeleted": false
    },
    {
      "user_id": "userId-2",
      "permissions": [1, 2],  // Permissions for Project Manager
      "isDeleted": false
    },
    {
      "user_id": "userId-3",
      "permissions": [1],  // Permissions for Developer
      "isDeleted": false
    },
    {
      "user_id": "userId-4",
      "permissions": [1],  // Permissions for Tester
      "isDeleted": false
    }
  ]);
  
  //db.getCollection('user_permissions').drop();
  
  db.user_permissions.find();
  
  // Model: Resources
  db.resources.insertMany([
    {
      "resource_type": "ticket",
      "resource_name": "Bug #123",
      "resource_context": {
        "project_id": ObjectId("64a7f4e0e4b0a5c3a6e9e0d6"),
        "sprint_id": ObjectId("64a7f370e4b0a5c3a6e9e0d4")
      },
      "attributes": {
        "status": "open",
        "assigned_to": ObjectId("64a7f2c8e4b0a5c3a6e9e0d2"),
        "severity": "critical"
      },
      "created_at": ISODate("2024-12-01T00:00:00Z")
    },
    {
      "resource_type": "project",
      "resource_name": "Project ABC",
      "resource_context": {},
      "attributes": {
        "status": "active",
        "created_by": ObjectId("64a7f2c8e4b0a5c3a6e9e0d2")
      },
      "created_at": ISODate("2024-12-01T00:00:00Z")
    }
  ]);
  
  //db.getCollection('resources').drop();
  
  db.resources.find();
  
  // # Model: Resource_Permissions
  db.resource_permissions.insertMany([
    {
      "_id": ObjectId(),
      "resource_id": ObjectId("64a7f4e0e4b0a5c3a6e9e0d6"),  // References a resource
      "permission_id": 1,  // ASSIGN_TICKET
      "meta": {
        "reason": "Critical bug fix",
        "valid_from": "2024-12-01T00:00:00Z",
        "valid_to": "2024-12-15T23:59:59Z"
      },
      "createdAt": ISODate("2024-12-01T12:00:00Z"),
      "updatedAt": ISODate("2024-12-01T12:00:00Z")
    },
    {
      "_id": ObjectId(),
      "resource_id": ObjectId("64a7f370e4b0a5c3a6e9e0d4"),  // Sprint resource
      "permission_id": 2,  // CREATE_SPRINT
      "meta": { "reason": "Critical bug fix", "valid_from": "2024-12-01T00:00:00Z", "valid_to": "2024-12-15T23:59:59Z" },
      "createdAt": ISODate("2024-12-01T12:00:00Z"),
      "updatedAt": ISODate("2024-12-01T12:00:00Z")
    }
  ]);
  
  //db.getCollection('resource_permissions').drop();
  
  db.resource_permissions.find();
  
  // Model: tickets
  
  db.tickets.insertOne({
    "task_id": "task-123",
    "task_title": "Fix bug in ticketing system",
    "task_description": "Resolve issue with assigning tickets",
    "parent_task": null,
    "priority": "high",
    "severity": "SEV5", // Critical(SEV1), High(SEV2), Medium(SEV3), and Low(SEV4)
    "original_estimation": 2,
    "story_point": 1,
    "assigned_to": ObjectId("64a7f2c8e4b0a5c3a6e9e0d2"),
    "sprint_id": ObjectId("64a7f370e4b0a5c3a6e9e0d4"),
    "reported_by": ObjectId("64a7f2c8e4b0a5c3a6e9e0d3"),
    "due_date": ISODate("2024-12-15T00:00:00Z"),
    "created_at": ISODate("2024-12-01T12:00:00Z"),
    "updated_at": ISODate("2024-12-01T12:00:00Z")
  });
  
  //db.getCollection('tickets').drop();
  
  db.tickets.find();
  
  // Model: work_log_for_tickets
  db.work_log_for_tickets.insertOne({
    ticket_id: 1,
    original_estimation: new Date(),
    story_point: 1,
    users: [{
      duration: new Date(),
      logged_by: 1
    }],
  });
  
  db.work_log_for_tickets.createIndex({ ticket_id: 1 }, { unique: true });
  db.work_log_for_tickets.createIndex({ "users.logged_by": 1 });
  db.work_log_for_tickets.createIndex({ "users.duration": 1 });
  db.work_log_for_tickets.createIndex({ original_estimation: 1 });
  db.work_log_for_tickets.createIndex({ story_point: 1 });
  
  db.work_log_for_tickets.find();
  
  // Model: Sprints
  db.sprints.insertMany([
    {
      "project_id": 101,        // Reference to a Project
      "name": "Sprint 1",
      "start_date": new Date("2024-12-01"),
      "end_date": new Date("2024-12-14"),
      "goal": "Complete user registration feature",
      "status": "active",        // active, completed, or upcoming
      "sprint_log": "example_logo",
      "tickets": [
        { "ticket_id": 1 },
        { "ticket_id": 2 }
      ]
    }
  ]);
  
  db.getCollection('sprints').drop();
  
  db.sprints.createIndex({ "project_id": 1 });
  db.sprints.createIndex({ "start_date": 1 });
  db.sprints.createIndex({ "end_date": 1 });
  
  db.sprints.find();
  
  // MODEL: Teams
  db.teams.insertMany([
    {
      "name": "Frontend Team",
      "project_id": 101,         // Reference to Project
      "members": [
        { "user_id": 1, "role": "Developer" },
        { "user_id": 2, "role": "Designer" }
      ]
    },
    {
      "name": "Backend Team",
      "project_id": 102,
      "members": [
        { "user_id": 3, "role": "Developer" },
        { "user_id": 4, "role": "Tester" }
      ]
    }
  ]);
  
  db.getCollection("teams").drop();
  
  db.teams.find();
  
  // MODEL: Project_settings
  db.project_settings.insertOne({
    "project_id": 101,         // Reference to Project
    "visibility": "private",   // private, public, or internal
    "preferred_language": "en",
    "timezone": "GMT",
    "notifications_enabled": true
  });
  
  //db.getCollection('project_settings').drop();
  
  db.project_groups.createIndex({ "project_id": 1 });
  db.project_groups.createIndex({ "group_name": 1 });
  
  db.getCollection('project_settings').find();
  
  // MODEL: Project_Groups
  db.project_groups.insertMany([
    {
      "project_id": 101,        // Reference to Project
      "group_name": "Core Team",
      "team_ids": [1, 2],       // References to Team collections
      "description": "Main group handling the core features of the project"
    },
    {
      "project_id": 102,
      "group_name": "Testing Group",
      "team_ids": [3],
      "description": "Group responsible for quality assurance and testing"
    }
  ]);
  
  //db.getCollection('project_groups').drop();
  
  db.project_groups.find();
  
  // MODEL: Milestones
  db.milestones.insertMany([
    {
      "project_id": 101,        // Reference to Project
      "name": "Milestone 1",
      "due_date": new Date("2024-12-14"),
      "goal": "Complete MVP",
      "checklist": [],
      "status": "active"         // active, completed, or upcoming
    },
    {
      "project_id": 102,
      "name": "Release Version 2.0",
      "due_date": new Date("2024-12-28"),
      "goal": "Version 2.0 ready for production",
      "checklist": [],
      "status": "upcoming"
    }
  ]);
  
  //db.getCollection('milestones').drop();
  
  db.milestones.createIndex({ "project_id": 1 });
  db.milestones.createIndex({ "due_date": 1 });
  
  db.milestones.find();
  
  // MODEL: Releases
  db.releases.insertMany([
    {
      "project_id": 101,        // Reference to Project
      "version": "1.0.0",
      "release_date": new Date("2024-12-15"),
      "notes": "Initial public release with basic features",
      "checklist": [], // based on this a progress bar percentage can be made
      "status": "released"      // released, in-progress, planned
    },
    {
      "project_id": 102,
      "version": "2.0.0",
      "release_date": new Date("2024-12-29"),
      "checklist": [],
      "notes": "Major update with performance improvements",
      "status": "planned"
    }
  ]);
  
  //db.getCollection('releases').drop();
  
  db.releases.createIndex({ "project_id": 1 });
  db.releases.createIndex({ "release_date": 1 });
  
  db.releases.find();