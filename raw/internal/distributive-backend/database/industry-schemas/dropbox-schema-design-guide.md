# Dropbox Cloud Storage: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: File Metadata, Chunking, Sync State, Sharing Permissions — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Storing file content in the database. Dropbox stores **only metadata** in the DB — actual file chunks go to distributed block storage (S3/GCS).

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Dropbox's Sync Engine](https://dropbox.tech/infrastructure/rewriting-the-heart-of-our-sync-engine) | Nucleus sync architecture |
| [Dropbox's Magic Pocket](https://dropbox.tech/infrastructure/inside-the-magic-pocket) | Exabyte-scale storage |
| [How Dropbox stores your files](https://dropbox.tech/infrastructure/atlas-our-journey-from-a-python-monolith-to-a-managed-platform) | Atlas platform |

---

## 🎯 The Principal Laws of Cloud Storage Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Metadata ≠ Content** | DB stores pointers, not bytes | Chunked block storage for content |
| **Law 2: Sync Is State Machine** | Each file has sync state per device | `sync_journal` per device |
| **Law 3: Sharing Is ACL** | Permissions are hierarchical | Folder shares cascade to children |
| **Law 4: Deduplication Is Key** | Same content = same hash | Content-addressable storage |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | List folder contents | 10M/s | < 50ms | PostgreSQL + Cache |
| 2 | Get file metadata | 50M/s | < 20ms | Cache + PostgreSQL |
| 3 | Upload file (chunked) | 1M/s | < 500ms | PostgreSQL + Block Storage |
| 4 | Get sync changes since cursor | 10M/s | < 100ms | PostgreSQL |
| 5 | Check sharing permissions | 20M/s | < 10ms | Cache + PostgreSQL |
| 6 | Get file revisions | 500K/s | < 100ms | PostgreSQL |
| 7 | Search files by name | 1M/s | < 200ms | Elasticsearch |
| 8 | Get shared folder members | 500K/s | < 50ms | PostgreSQL |
| 9 | Create shared link | 100K/s | < 200ms | PostgreSQL |
| 10 | Sync conflict resolution | 100K/s | < 500ms | PostgreSQL |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    DROPBOX DATA ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Client (Desktop/Mobile)                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Local Files    │  │  SQLite DB      │  │  Sync Engine    │  │
│  │  (File System)  │  │  (Local State)  │  │  (Nucleus)      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└───────────────────────────────┬─────────────────────────────────┘
                                │ Delta Sync
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                               │
│  ✓ File metadata    ✓ Folder hierarchy   ✓ Sharing/ACLs         │
│                                                                  │
│  • namespaces (user roots, shared folders)                       │
│  • files (metadata, not content)                                 │
│  • file_blocks (hash → block mapping)                            │
│  • sync_journal (change log per namespace)                       │
│  • sharing (ACLs, shared links)                                  │
└─────────────────────────────────────────────────────────────────┘
                                │ Content Hash
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Block Storage (Magic Pocket / S3)        │
│  ✓ Content-addressable    ✓ Deduplication   ✓ Erasure coding    │
│                                                                  │
│  • Blocks stored by hash (SHA-256)                               │
│  • Same content across users = one copy                          │
│  • Replicated across zones                                       │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- DROPBOX SCHEMA: PostgreSQL Production DDL
-- Version: File sync and sharing
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";


-- ===========================================
-- SECTION 1: USERS AND ACCOUNTS
-- ===========================================

CREATE TYPE account_type AS ENUM ('basic', 'plus', 'professional', 'business', 'enterprise');

CREATE TABLE accounts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email               VARCHAR(255) NOT NULL UNIQUE,
    password_hash       TEXT NOT NULL,
    
    -- Profile
    display_name        VARCHAR(255),
    profile_photo_url   TEXT,
    
    -- Account type
    account_type        account_type DEFAULT 'basic',
    team_id             UUID,  -- For business accounts
    
    -- Quota
    quota_bytes         BIGINT NOT NULL DEFAULT 2147483648,  -- 2GB default
    used_bytes          BIGINT NOT NULL DEFAULT 0,
    
    -- Settings
    locale              VARCHAR(10) DEFAULT 'en',
    two_factor_enabled  BOOLEAN DEFAULT FALSE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_team ON accounts(team_id) WHERE team_id IS NOT NULL;


-- ===========================================
-- SECTION 2: NAMESPACES (Root Containers)
-- ===========================================

-- A namespace is a root container for files
-- Users have personal namespace + shared folder namespaces
CREATE TYPE namespace_type AS ENUM ('personal', 'shared_folder', 'team_folder');

CREATE TABLE namespaces (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_type      namespace_type NOT NULL,
    
    -- Owner (for personal) or NULL (for shared)
    owner_id            UUID REFERENCES accounts(id),
    
    -- For shared folders
    name                VARCHAR(255),
    
    -- Stats
    file_count          BIGINT DEFAULT 0,
    folder_count        BIGINT DEFAULT 0,
    total_bytes         BIGINT DEFAULT 0,
    
    -- Version for sync
    revision            BIGINT NOT NULL DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_namespaces_owner ON namespaces(owner_id);


-- ===========================================
-- SECTION 3: FILES AND FOLDERS
-- ===========================================

CREATE TYPE entry_type AS ENUM ('file', 'folder');

CREATE TABLE entries (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id        UUID NOT NULL REFERENCES namespaces(id),
    
    -- Path components
    parent_id           UUID REFERENCES entries(id),  -- NULL = root
    name                VARCHAR(255) NOT NULL,
    path_lower          TEXT NOT NULL,  -- Full path, lowercased for lookup
    
    entry_type          entry_type NOT NULL,
    
    -- File-specific (NULL for folders)
    size_bytes          BIGINT,
    content_hash        VARCHAR(64),  -- SHA-256 of content
    
    -- Metadata
    client_modified     TIMESTAMP WITH TIME ZONE,  -- Client's mtime
    server_modified     TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Revision tracking
    revision            BIGINT NOT NULL DEFAULT 1,
    
    -- Soft delete
    is_deleted          BOOLEAN DEFAULT FALSE,
    deleted_at          TIMESTAMP WITH TIME ZONE,
    
    -- Media info (for photos/videos)
    media_info          JSONB,  -- dimensions, duration, location
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_entry_path UNIQUE (namespace_id, path_lower),
    CONSTRAINT uk_entry_parent_name UNIQUE (namespace_id, parent_id, name) 
        WHERE is_deleted = FALSE
);

-- Critical indexes
CREATE INDEX idx_entries_namespace ON entries(namespace_id);
CREATE INDEX idx_entries_parent ON entries(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX idx_entries_path ON entries(namespace_id, path_lower);
CREATE INDEX idx_entries_hash ON entries(content_hash) WHERE content_hash IS NOT NULL;
CREATE INDEX idx_entries_modified ON entries(namespace_id, server_modified DESC);
CREATE INDEX idx_entries_deleted ON entries(namespace_id, is_deleted) WHERE is_deleted = TRUE;

-- Trigram for search
CREATE INDEX idx_entries_name_trgm ON entries USING GIN (name gin_trgm_ops);


-- ===========================================
-- SECTION 4: FILE BLOCKS (Content-Addressable)
-- ===========================================

-- Files are split into 4MB blocks
-- Same block hash = same content (deduplication)
CREATE TABLE blocks (
    hash                VARCHAR(64) PRIMARY KEY,  -- SHA-256
    size_bytes          INT NOT NULL,
    
    -- Storage location
    storage_backend     VARCHAR(50) DEFAULT 'magic_pocket',  -- 'magic_pocket', 's3', 'gcs'
    storage_key         TEXT NOT NULL,  -- Key in block storage
    
    -- Reference counting for dedup
    reference_count     INT NOT NULL DEFAULT 1,
    
    -- Encryption (per-block encryption key, encrypted with master)
    encryption_key_enc  BYTEA,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- File to blocks mapping (ordered)
CREATE TABLE file_blocks (
    file_id             UUID NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    block_index         INT NOT NULL,  -- 0-indexed position
    block_hash          VARCHAR(64) NOT NULL REFERENCES blocks(hash),
    
    -- Offset within file
    offset_bytes        BIGINT NOT NULL,
    
    PRIMARY KEY (file_id, block_index)
);

CREATE INDEX idx_file_blocks_hash ON file_blocks(block_hash);


-- ===========================================
-- SECTION 5: FILE REVISIONS (Version History)
-- ===========================================

CREATE TABLE file_revisions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id             UUID NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    revision            BIGINT NOT NULL,
    
    -- Snapshot of metadata at this revision
    size_bytes          BIGINT NOT NULL,
    content_hash        VARCHAR(64) NOT NULL,
    client_modified     TIMESTAMP WITH TIME ZONE,
    server_modified     TIMESTAMP WITH TIME ZONE NOT NULL,
    
    -- Who made this change
    modified_by         UUID REFERENCES accounts(id),
    
    -- Change type
    change_type         VARCHAR(20) NOT NULL,  -- 'created', 'updated', 'renamed', 'moved'
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_file_revision UNIQUE (file_id, revision)
);

CREATE INDEX idx_revisions_file ON file_revisions(file_id);
CREATE INDEX idx_revisions_modified ON file_revisions(server_modified DESC);


-- ===========================================
-- SECTION 6: SYNC JOURNAL (Change Log)
-- ===========================================

-- Every change to a namespace is recorded for sync
CREATE TABLE sync_journal (
    id                  BIGSERIAL PRIMARY KEY,
    namespace_id        UUID NOT NULL REFERENCES namespaces(id),
    
    -- Cursor position (monotonically increasing per namespace)
    cursor              BIGINT NOT NULL,
    
    -- What changed
    entry_id            UUID NOT NULL REFERENCES entries(id),
    entry_path          TEXT NOT NULL,
    change_type         VARCHAR(20) NOT NULL,  -- 'add', 'update', 'delete', 'move'
    
    -- For moves: old path
    old_path            TEXT,
    
    -- Entry state at this cursor
    entry_snapshot      JSONB NOT NULL,  -- Full entry state for sync
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_namespace_cursor UNIQUE (namespace_id, cursor)
) PARTITION BY RANGE (created_at);

-- Monthly partitions for journal (prune old)
CREATE TABLE sync_journal_y2024m01 PARTITION OF sync_journal
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE INDEX idx_sync_journal_namespace_cursor ON sync_journal(namespace_id, cursor);
CREATE INDEX idx_sync_journal_entry ON sync_journal(entry_id);


-- ===========================================
-- SECTION 7: SHARING AND PERMISSIONS
-- ===========================================

CREATE TYPE access_level AS ENUM ('viewer', 'editor', 'owner');
CREATE TYPE share_status AS ENUM ('pending', 'accepted', 'declined');

-- Shared folder membership
CREATE TABLE shared_folder_members (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id        UUID NOT NULL REFERENCES namespaces(id),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    
    access_level        access_level NOT NULL DEFAULT 'viewer',
    status              share_status NOT NULL DEFAULT 'pending',
    
    -- Who invited
    inviter_id          UUID REFERENCES accounts(id),
    
    -- Member's local path for this folder
    mount_path          TEXT,
    
    invited_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    joined_at           TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT uk_member UNIQUE (namespace_id, account_id)
);

CREATE INDEX idx_members_account ON shared_folder_members(account_id);
CREATE INDEX idx_members_namespace ON shared_folder_members(namespace_id);


-- Shared links (public URLs)
CREATE TABLE shared_links (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entry_id            UUID NOT NULL REFERENCES entries(id),
    
    -- URL components
    link_key            VARCHAR(32) NOT NULL UNIQUE,  -- Random key for URL
    password_hash       TEXT,  -- Optional password protection
    
    -- Permissions
    access_level        access_level NOT NULL DEFAULT 'viewer',
    allow_download      BOOLEAN DEFAULT TRUE,
    
    -- Expiration
    expires_at          TIMESTAMP WITH TIME ZONE,
    
    -- Analytics
    view_count          INT DEFAULT 0,
    download_count      INT DEFAULT 0,
    
    created_by          UUID NOT NULL REFERENCES accounts(id),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_links_entry ON shared_links(entry_id);
CREATE INDEX idx_links_key ON shared_links(link_key);


-- ===========================================
-- SECTION 8: SYNC STATE PER DEVICE
-- ===========================================

CREATE TABLE devices (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID NOT NULL REFERENCES accounts(id),
    
    device_name         VARCHAR(255) NOT NULL,
    device_type         VARCHAR(50) NOT NULL,  -- 'desktop', 'mobile', 'web'
    os                  VARCHAR(100),
    client_version      VARCHAR(50),
    
    -- Sync state
    last_sync_at        TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_devices_account ON devices(account_id);

-- Cursor position per device per namespace
CREATE TABLE device_sync_cursors (
    device_id           UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    namespace_id        UUID NOT NULL REFERENCES namespaces(id) ON DELETE CASCADE,
    
    cursor              BIGINT NOT NULL DEFAULT 0,  -- Last synced cursor
    last_synced_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (device_id, namespace_id)
);


-- ===========================================
-- SECTION 9: CONFLICT RESOLUTION
-- ===========================================

CREATE TABLE sync_conflicts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entry_id            UUID NOT NULL REFERENCES entries(id),
    
    -- Conflicting versions
    server_revision     BIGINT NOT NULL,
    client_revision     BIGINT NOT NULL,
    
    -- Conflict resolution
    resolution          VARCHAR(50),  -- 'server_wins', 'client_wins', 'rename', 'manual'
    conflict_copy_id    UUID REFERENCES entries(id),  -- If renamed to "X (conflict)"
    
    -- Who resolved
    resolved_by         UUID REFERENCES accounts(id),
    resolved_at         TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_conflicts_entry ON sync_conflicts(entry_id);
CREATE INDEX idx_conflicts_unresolved ON sync_conflicts(resolved_at) WHERE resolved_at IS NULL;
```

---

# Part 4: Delta Sync Algorithm

```sql
-- Get changes since last sync cursor
CREATE OR REPLACE FUNCTION get_sync_delta(
    p_namespace_id UUID,
    p_cursor BIGINT,
    p_limit INT DEFAULT 1000
) RETURNS TABLE (
    cursor BIGINT,
    entry_id UUID,
    entry_path TEXT,
    change_type VARCHAR,
    entry_snapshot JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sj.cursor,
        sj.entry_id,
        sj.entry_path,
        sj.change_type,
        sj.entry_snapshot
    FROM sync_journal sj
    WHERE sj.namespace_id = p_namespace_id
      AND sj.cursor > p_cursor
    ORDER BY sj.cursor ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- Usage:
-- SELECT * FROM get_sync_delta('namespace-uuid', 12345, 500);
-- Returns changes after cursor 12345, up to 500 entries


-- Record a change to sync journal
CREATE OR REPLACE FUNCTION record_sync_change(
    p_namespace_id UUID,
    p_entry_id UUID,
    p_change_type VARCHAR
) RETURNS BIGINT AS $$
DECLARE
    v_new_cursor BIGINT;
    v_entry_snapshot JSONB;
BEGIN
    -- Get next cursor for namespace
    UPDATE namespaces 
    SET revision = revision + 1
    WHERE id = p_namespace_id
    RETURNING revision INTO v_new_cursor;
    
    -- Snapshot current entry state
    SELECT jsonb_build_object(
        'id', e.id,
        'name', e.name,
        'path_lower', e.path_lower,
        'entry_type', e.entry_type,
        'size_bytes', e.size_bytes,
        'content_hash', e.content_hash,
        'client_modified', e.client_modified,
        'server_modified', e.server_modified,
        'revision', e.revision,
        'is_deleted', e.is_deleted
    ) INTO v_entry_snapshot
    FROM entries e
    WHERE e.id = p_entry_id;
    
    -- Insert to journal
    INSERT INTO sync_journal (
        namespace_id, cursor, entry_id, entry_path, 
        change_type, entry_snapshot
    )
    SELECT 
        p_namespace_id,
        v_new_cursor,
        p_entry_id,
        e.path_lower,
        p_change_type,
        v_entry_snapshot
    FROM entries e
    WHERE e.id = p_entry_id;
    
    RETURN v_new_cursor;
END;
$$ LANGUAGE plpgsql;
```

---

# Part 5: Permission Check

```sql
-- Check if user can access a path
CREATE OR REPLACE FUNCTION check_access(
    p_account_id UUID,
    p_namespace_id UUID,
    p_required_level access_level
) RETURNS BOOLEAN AS $$
DECLARE
    v_ns_owner_id UUID;
    v_member_level access_level;
BEGIN
    -- Check if owner
    SELECT owner_id INTO v_ns_owner_id
    FROM namespaces WHERE id = p_namespace_id;
    
    IF v_ns_owner_id = p_account_id THEN
        RETURN TRUE;  -- Owner has full access
    END IF;
    
    -- Check shared folder membership
    SELECT access_level INTO v_member_level
    FROM shared_folder_members
    WHERE namespace_id = p_namespace_id
      AND account_id = p_account_id
      AND status = 'accepted';
    
    IF v_member_level IS NULL THEN
        RETURN FALSE;  -- Not a member
    END IF;
    
    -- Check access level hierarchy
    RETURN (
        (p_required_level = 'viewer') OR
        (p_required_level = 'editor' AND v_member_level IN ('editor', 'owner')) OR
        (p_required_level = 'owner' AND v_member_level = 'owner')
    );
END;
$$ LANGUAGE plpgsql STABLE;
```

---

# Part 6: Upload Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    FILE UPLOAD FLOW                              │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Client          │
│  (10MB file)     │
└────────┬─────────┘
         │
         │ 1. Split into 4MB chunks
         │    Hash each chunk (SHA-256)
         ▼
┌──────────────────┐
│  Upload Request  │
│                  │
│  chunks:         │
│  - hash: abc123  │
│  - hash: def456  │
│  - hash: ghi789  │
└────────┬─────────┘
         │
         │ 2. Check which chunks already exist (dedup)
         ▼
┌──────────────────┐
│  Metadata Server │
│  (PostgreSQL)    │
│                  │
│  SELECT hash     │
│  FROM blocks     │
│  WHERE hash IN   │
│  ('abc123',...)  │
│                  │
│  Result: abc123  │
│  exists, others  │
│  don't           │
└────────┬─────────┘
         │
         │ 3. Upload only new chunks
         ▼
┌──────────────────┐     ┌──────────────────┐
│  Upload Missing  │────►│  Block Storage   │
│  Chunks          │     │  (Magic Pocket)  │
│                  │     │                  │
│  def456, ghi789  │     │  Store by hash   │
└────────┬─────────┘     └──────────────────┘
         │
         │ 4. Create file entry and block mappings
         ▼
┌──────────────────┐
│  Commit Upload   │
│                  │
│  INSERT entries  │
│  INSERT file_    │
│  blocks          │
│  UPDATE blocks   │
│  (ref count)     │
│  INSERT sync_    │
│  journal         │
└──────────────────┘
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Content-addressable blocks | Stored by SHA-256 hash |
| 2 | Deduplication working | reference_count on blocks |
| 3 | Sync journal per namespace | Cursor-based delta sync |
| 4 | Device sync cursors | Per device per namespace |
| 5 | Hierarchical ACLs | Folder share → files inherit |
| 6 | Conflict detection | server_revision vs client_revision |
| 7 | Path uniqueness | Unique (namespace, path_lower) |
| 8 | Soft deletes for recovery | is_deleted with timestamp |

---

# Part 7: DynamoDB Single-Table Design

```
============================================================
DROPBOX: DynamoDB Single-Table Design
For high-scale activity logs, sync status, and file locks
(PostgreSQL remains Primary for File System Metadata)
============================================================

TABLE: dropbox_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (Activity/Team queries)
- GSI2: GSI2PK / GSI2SK (Shares/Locks queries)

============================================================
ENTITY PATTERNS
============================================================

ACTIVITY LOG (Immutable Audit)
  PK: NS#{namespace_id}
  SK: ACT#{timestamp}#{actor_id}
  
  Attributes: action_type (edit, view, download), file_path, ip_address

FILE LOCK (Collaboration)
  PK: LOCK#{file_id}
  SK: META
  
  Attributes: locked_by, expires_at, machine_id

SHARED LINK TRAFFIC STATS
  PK: LINK#{link_id}
  SK: STAT#{date}
  
  Attributes: views, downloads, referring_domains_json

DEVICE SYNC STATUS (Ephemeral)
  PK: DEV#{device_id}
  SK: NS#{namespace_id}
  
  Attributes: last_cursor, status (up_to_date, syncing), percent_complete

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get recent activity for a folder (Audit)
   Table: PK=NS#{namespace_id}, SK > ACT#{one_week_ago}

2. Check if file is locked for editing
   Table: PK=LOCK#{file_id}, SK=META

3. Get traffic stats for shared link
   Table: PK=LINK#{link_id}, SK begins_with "STAT#"

4. Get sync status across all devices for a user
   Table: BatchGet(DEV#{iphone}, DEV#{laptop})
```

---

# Part 8: Query Examples with EXPLAIN

```sql
-- ============================================================
-- DROPBOX QUERY PATTERNS WITH EXPLAIN
-- ============================================================

-- ===========================================
-- QUERY 1: Delta Sync (The Heartbeat)
-- ===========================================

-- Used by clients to ask "What changed since cursor X?"
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    entry_id, entry_path, change_type, entry_snapshot
FROM sync_journal
WHERE namespace_id = $1
  AND cursor > $2
ORDER BY cursor ASC
LIMIT 500;

-- Expected: Index scan on idx_sync_journal_namespace_cursor.
-- This MUST be fast (< 10ms) as it runs constantly.


-- ===========================================
-- QUERY 2: Deduplication Check (Upload)
-- ===========================================

-- "Do you already have these blocks?"
EXPLAIN (ANALYZE, BUFFERS)
SELECT hash, reference_count
FROM blocks
WHERE hash IN ('val1', 'val2', 'val3', 'val4', 'val5');

-- Expected: Index Scan on blocks_pkey using IN list. 
-- Fast lookups avoid uploading massive data.


-- ===========================================
-- QUERY 3: List Folder Contents (Recursive? No)
-- ===========================================

-- Flat list of immediate children
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    id, name, entry_type, size_bytes, server_modified
FROM entries
WHERE namespace_id = $1
  AND parent_id = $2
  AND is_deleted = FALSE
ORDER BY name ASC;

-- Expected: Index scan on idx_entries_parent.


-- ===========================================
-- QUERY 4: Find Orphaned Blocks (Garbage Collection)
-- ===========================================

-- Find blocks with 0 references to delete from S3
EXPLAIN (ANALYZE, BUFFERS)
SELECT hash, storage_key
FROM blocks
WHERE reference_count = 0
  AND created_at < NOW() - INTERVAL '7 days';

-- Expected: Seq Scan or Partial Index if created `WHERE ref_count = 0`.
```

---

# Part 9: Capacity Planning

```
============================================================
DROPBOX CAPACITY PLANNING
============================================================

ASSUMPTIONS (Exabyte Scale):
- 1 Billion Users
- 1 Trillion Files
- Avg file size: 1 MB (lots of small docs + photos)
- Metadata DB: The bottleneck.

============================================================
STORAGE ESTIMATES
============================================================

METADATA (PostgreSQL)
  Rows: 1 Trillion entries
  Row Size: ~200 bytes
  Total: ~200 TB Metadata.
  Strategy: Sharding by `namespace_id` (User Root).
  MySQL (Edgestore) or Vitess commonly used at this scale.

BLOCK STORAGE (S3/Magic Pocket)
  Content: 1 Exabyte (1000 PB).
  Deduplication saves ~30% storage globally (viral videos, email attachments).

SYNC JOURNAL
  Rows: 10x File Count (every edit creates a journal entry).
  Pruning: Delete journal entries older than 30 days.
  Full sync required if device offline > 30 days.

============================================================
THROUGHPUT REQUIREMENTS
============================================================

SYNC TRAFFIC (Read Heavy):
- 10M devices polling every minute.
- "Long Polling" reduces DB load (hold connection until change).

UPLOAD TRAFFIC (Write Heavy):
- 1M blocks/sec.
- Metadata writes are small (`file_blocks` insert).
- Bottleneck: Updating `blocks.reference_count` (Hot row if 1M people upload exact same file).
- Solution: Approximate counting or batched updates for viral files.

============================================================
SCALING STRATEGY
============================================================

1. NAMESPACE SHARDING
   - All files for a User (or Shared Folder) live on one DB shard.
   - Atomic transactions possible within namespace.
   - Journal query hits 1 shard.

2. COLD STORAGE
   - Move `file_revisions` > 1 year old to cold DB (RocksDB on HDD).
   - Keeps primary OLTP DB lean.

3. EDGE CACHING
   - Metadata cache at the Edge (PoP).
   - "List Folder" served from Edge Redis if no changes.
```

---

# Part 10: Anti-Patterns to Avoid

```
============================================================
DROPBOX ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Path-based Lookup for Everything
-----------------------------------------
WRONG:
  SELECT * FROM files WHERE path LIKE '/Users/John/Photos/%'
  -- expensive text matching. Renaming folder requires updating 1M rows?
  
RIGHT:
  -- ID-based hierarchy (`parent_id`).
  -- Rename = Update 1 row (the folder). Children follow automatically.


❌ ANTI-PATTERN 2: Storing Content in DB
-----------------------------------------
WRONG:
  file_content BYTEA
  -- DB bloats instantly. Backup/Restore impossible.
  
RIGHT:
  -- CAS (Content Addressable Storage).
  -- DB holds `sha256_hash` -> Block Storage URL.


❌ ANTI-PATTERN 3: Client-Side Deduplication Trust
-----------------------------------------
WRONG:
  Client says "I have block Hash X". Server trusts it.
  -- Malicious client reads others' files by guessing Hashes.
  
RIGHT:
  -- "Proof of Possession".
  -- Server asks: "Send me bytes 10-20 of that block".


❌ ANTI-PATTERN 4: Recursive Folder Size Calculation
-----------------------------------------
WRONG:
  SUM(size) WHERE parent_id IN (recursive subquery)
  -- Kills DB on root folder view.
  
RIGHT:
  -- Denormalized `total_bytes` on Folder object.
  -- Update up the tree on every write (Async task).


❌ ANTI-PATTERN 5: Infinite Version History
-----------------------------------------
WRONG:
  Keep every edit forever for free users.
  -- Storage explosion.
  
RIGHT:
  -- Prune revisions > 30 days (Free) or > 180 days (Pro).
  -- Keep "Delete Markers" for a while to allow undelete.


❌ ANTI-PATTERN 6: Syncing 1 Million Files at Once
-----------------------------------------
WRONG:
  SELECT * FROM journal LIMIT 1000000.
  -- Client crashes OOM. Network times out.
  
RIGHT:
  -- Pagination (Cursor).
  -- Batch size 500. Client consumes stream.


❌ ANTI-PATTERN 7: Hard Deleting Shared Folders
-----------------------------------------
WRONG:
  DELETE FROM namespace WHERE id = ...
  -- What about the other 10 members?
  
RIGHT:
  -- Unmount: Remove `shared_folder_member` row.
  -- Data deletes only when LAST member leaves.
  -- Tombstones for synchronization.


❌ ANTI-PATTERN 8: Blocking Upload on DB Write
-----------------------------------------
WRONG:
  Upload bytes -> DB Transaction -> Return 200.
  -- Slow upload holds DB connection open.
  
RIGHT:
  -- Upload bytes to S3 (Pre-signed URL) -> Success.
  -- Call API with "Done, here is hash".
  -- Short DB transaction.


❌ ANTI-PATTERN 9: Global Unique IDs only
-----------------------------------------
WRONG:
  UUIDs for everything are great, but...
  
RIGHT:
  -- Need `nsp_id` (Namespace ID) in almost all queries for sharding.
  -- Composite Keys `(namespace_id, file_id)` speed up routing.


❌ ANTI-PATTERN 10: Ignoring Case Sensitivity
-----------------------------------------
WRONG:
  "Resume.pdf" and "resume.pdf" exist in same folder.
  -- Windows/Mac users will have sync conflicts (Case preserving, insensitive).
  
RIGHT:
  -- Store `path_display` ("Resume.pdf") and `path_lower` ("resume.pdf").
  -- Unique index on `path_lower`.
```

---

# Part 11: CDC & Event Streaming

```
============================================================
DROPBOX CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│ (Metadata)  │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │ Search    │    │ Thumbnail │   │ Audit     │  │ Notif.   │
  │ Indexer   │    │ Gen       │   │ Logs      │  │ Service  │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

KAFKA TOPICS:
- file.created            (Trigger Thumbnail / Text Extract)
- file.deleted            (Cleanup Blocks Async)
- share.created           (Send Email Invite)
- team.audit              (Compliance Storage)

============================================================
DISASTER RECOVERY
============================================================

RPO: 0 (Metadata), < 15 min (Block Garbage Collection)
RTO: < 1 hour

STRATEGY:
1. Metadata Protection
   - Cross-Region Replication for PostgreSQL (Async).
   - "Magic Pocket" stores blocks in 3+ zones.

2. "Dark Read" Mode
   - If Master DB fails, Clients enter "Read Only" mode.
   - Can download, but uploads queue locally.

3. Soft Delete Everything
   - Nothing is truly deleted immediately.
   - `is_deleted` flag everywhere.
   - "Purge" runs only after 30 days.
   - Protects against accidental "rm -rf /".
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- DROPBOX: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / ACCESS LOG
-- ===========================================

CREATE TABLE file_access_log (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    file_id             UUID NOT NULL,
    action_type         VARCHAR(50) NOT NULL,  -- 'view', 'download', 'share', 'delete'
    access_via          VARCHAR(50),  -- 'web', 'desktop', 'mobile', 'api'
    ip_address          INET,
    device_id           VARCHAR(100),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_access_file ON file_access_log(file_id);
CREATE INDEX idx_access_user ON file_access_log(user_id);


-- ===========================================
-- B. FILE PREVIEWS / THUMBNAILS
-- ===========================================

CREATE TABLE file_previews (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id             UUID NOT NULL REFERENCES files(id),
    preview_type        VARCHAR(20) NOT NULL,  -- 'thumbnail', 'preview', 'pdf_render'
    width               INT,
    height              INT,
    storage_key         VARCHAR(500) NOT NULL,
    generated_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_preview_file ON file_previews(file_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    channel             VARCHAR(20) NOT NULL,  -- 'email', 'push'
    notification_type   VARCHAR(100) NOT NULL,  -- 'file_shared', 'comment_added'
    title               VARCHAR(100),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- D. WEBHOOKS / APP INTEGRATIONS
-- ===========================================

CREATE TABLE registered_apps (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id            UUID NOT NULL,
    name                VARCHAR(100) NOT NULL,
    client_id           VARCHAR(64) NOT NULL UNIQUE,
    client_secret_hash  VARCHAR(64) NOT NULL,
    redirect_uris       TEXT[],
    permission_type     VARCHAR(20) DEFAULT 'full',  -- 'full', 'folder', 'app_folder'
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    app_id              UUID NOT NULL REFERENCES registered_apps(id),
    user_id             UUID NOT NULL,
    url                 VARCHAR(500) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['file.changed', 'folder.shared']
    is_active           BOOLEAN DEFAULT TRUE,
    cursor              VARCHAR(100),  -- For delta sync
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- E. API KEYS / ACCESS TOKENS
-- ===========================================

CREATE TABLE api_tokens (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    app_id              UUID REFERENCES registered_apps(id),
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    token_type          VARCHAR(20) NOT NULL,  -- 'access', 'refresh', 'short_lived'
    scopes              TEXT[],
    expires_at          TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_token_hash ON api_tokens(token_hash);


-- ===========================================
-- F. SSO
-- ===========================================

CREATE TABLE sso_providers (
    id                  SERIAL PRIMARY KEY,
    team_id             UUID NOT NULL,  -- Dropbox Business
    provider_type       VARCHAR(50) NOT NULL,  -- 'okta', 'azure_ad', 'google'
    client_id           VARCHAR(255) NOT NULL,
    client_secret_enc   BYTEA NOT NULL,
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
-- G. USER SESSIONS / DEVICES
-- ===========================================

CREATE TABLE user_devices (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    device_id           VARCHAR(100) NOT NULL UNIQUE,
    device_name         VARCHAR(100),
    device_type         VARCHAR(50),  -- 'desktop', 'mobile', 'web'
    os                  VARCHAR(50),
    app_version         VARCHAR(20),
    last_sync_at        TIMESTAMP WITH TIME ZONE,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    device_id           UUID REFERENCES user_devices(id),
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
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
    allowed_team_ids    UUID[],  -- Business accounts
    required_plan       VARCHAR(50),  -- 'plus', 'professional', 'business'
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
DROPBOX: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. METADATA STORE INTERNALS (EDGESTORE)
============================================================

THE CHALLENGE:
Namespace-based storage. A "Namespace" is a folder tree (Root or Shared Folder).
Objects (Files/Dirs) belong to a Namespace.
Transactionality required within a Namespace (Move file A to B).

SHARDING STRATEGY:
- Shard Key: `namespace_id` (NOT user_id).
- Why? Users share folders. A shared folder exists in one shard. All users Access that shard.
- Hot Namespace Problem: Huge shared folders (Corporate Root).
- Mitigation: Read-replicas for popular namespaces.

DATABASE SCHEMA OPTIMIZATION:
- Do not store full paths (`/home/user/docs/file.txt`).
- Store Parent ID + Name (`parent_id: 100, name: "file.txt"`).
- Pros: O(1) Move/Rename (just change parent_id).
- Cons: Need recursive query (CTE) to build full path.

============================================================
2. BLOCK STORAGE OPTIMIZATION ("MAGIC POCKET")
============================================================

THE 4MB BLOCK MODEL:
- Files are split into 4MB blocks.
- Hash (SHA-256) of block = Block ID.
- Deduplication: If two users upload `ubuntu.iso`, we store blocks once.
- Metadata DB: `file_id -> list[block_ids]`.

STORAGE TIERS (S3 vs On-Prem):
- Hot Blocks (New uploads): S3 Standard / On-prem NVMe.
- Warm Blocks (Access < 30 days): S3 Standard-IA / HDD.
- Cold Blocks (Versions > 30 days): S3 Glacier / Shingled Magnetic Recording (SMR) drives.
- Savings: 80% cost reduction for historical versions.

============================================================
3. OBSERVABILITY (SYNC HEALTH)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Time to Visibility (TTV)     │ < 2s    │ > 5s = WARN     │
│  (Time from Upload → Peer sees change notification)         │
├─────────────────────────────────────────────────────────────┤
│  Upload Success Rate          │ > 99.9% │ < 99.5% = PAGE  │
│  Download Latency (TTFB)      │ < 200ms │ > 500ms = WARN  │
│  Metadata Conflict Rate       │ < 0.1%  │ Spike = INFO    │
└─────────────────────────────────────────────────────────────┘

CLIENT-SIDE METRICS (Desktop Client):
- "Cpu Usage High" events (hashing large files).
- "Database Locked" (SQLite local issues).
- "Clock Skew" (Client time drift > 5m causes auth failures).

SERVER METRICS:
- `notification_server_connections`: # of active long-polls/websockets.
- `block_put_latency`: S3 write performance.
- `qps_per_namespace`: Detect hot shared folders.

============================================================
4. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: SPLIT-BRAIN (CONFLICT FLAPPING)
Symptom: Two users edit same file offline. Both come online.
Mechanism:
- "The Last Writer Wins" is dangerous.
- Strategy: Detected "divergent clock vectors".
- Action: Server accepts first committer. Second committer gets 409 Conflict.
- Client creates "Conflicted Copy (User B's Version)".

SCENARIO 2: MASS DELETE (The "Oops" Moment)
Symptom: User deletes shared folder with 1M files.
Impact: DB writes spike, notifications flood 1000 users.
Mitigation:
- Async Deletion: Mark root as `is_deleted=true`.
- Background "Garbage Collector" slowly reclaims rows/blocks.
- "Undo" Feature: Just flip the boolean back (Time Travel).

SCENARIO 3: QUOTA ENFORCEMENT RACE
Symptom: User with 1GB left uploads parallel 1GB files.
Mitigation:
- `usage_pending` column in Redis.
- Pre-allocate quota at upload start (Reservation pattern).
- Reconciliation job fixes drift nightly.

============================================================
5. FINOPS & COST OPTIMIZATION
============================================================

DEDUPLICATION SAVINGS:
- Global block deduplication saves ~30-40% storage.
- Cross-user deduplication requires "Proof of Possession" (client must send hash + small slice) to prevent privacy attacks (checking if file exists).

METADATA COMPRESSION:
- Namespace trees compress very well.
- Use `ZSTD` for older `audit_log` partitions.

BANDWIDTH OPTIMIZATION:
- Delta Sync (rsync-style): Only upload changed bytes of a 4MB block.
- LAN Sync: Peer-to-peer transfer if devices are on same WiFi (saves cloud bandwidth).
```

---

## 🔗 Related Documents

- [JIRA Schema](./jira-schema-design-guide.md) — Complex ACL patterns
- [NoSQL Architecture](./nosql-architecture-guide.md) — If migrating to Cassandra
- [Replication Consistency](./replication-consistency-guide.md) — Multi-device sync conflicts

