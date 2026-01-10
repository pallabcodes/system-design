-- OVERVIEW:
------------
-- 1NF: NO Multivalued value for any column
-- 2NF: Each NON-Key should be directly dependent on its single primary key or composite primary key (in case of composite each non-key attributes should be directly dependent on all keys not one or some of them if so it will be partial dependence therefore breaking the 2NF)
-- 3NF: On any of the non-key determines or affects the value of another attribute then that non-key must be separated into another table

-- N.B: Enums are rigid and require schema changes for updates. Lookup tables are more flexible.

CREATE TYPE STATUS AS ENUM ('active', 'inactive', 'suspended', 'blocked');
CREATE TYPE GENDER AS ENUM ('male', 'female', 'others');
CREATE TYPE PRIVACY_LEVEL AS ENUM ('public', 'private', 'restricted');
CREATE TYPE POST_STATUS AS ENUM ('draft', 'awaiting review', 'published', 'blocked', 'age-restricted');
CREATE TYPE POST_VISIBILITY AS ENUM ('public', 'private', 'only-me');
CREATE TYPE NOTIFICATION_TYPE AS ENUM ('email', 'sms', 'push', 'none'); -- Updated to store specific types of notifications
CREATE TYPE PRIVACY_LEVEL AS ENUM ('public', 'followers-only', 'private');
CREATE TYPE POST_TYPE AS ENUM ('text', 'image', 'video', 'link');
CREATE TYPE REACTION_TYPE AS ENUM ('like', 'love', 'haha', 'wow', 'sad', 'angry');
CREATE TYPE COMMENT_STATUS AS ENUM ('approved', 'pending', 'flagged');
CREATE TYPE FRIEND_STATUS AS ENUM ('pending', 'approved', 'blocked', 'none');


-- N.B: lookup tables is far better way that ENUM thus created lookup table

CREATE TABLE IF NOT EXISTS post_status_lookup (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL, # validation should be done in the application layer i.e. draft, awaiting-review, published, blocked, age-restricted
    description TEXT
);

-- DROP TABLE IF EXISTS post_status_lookup cascade;

-- Populate lookup table
INSERT INTO post_status_lookup (name, description)
VALUES ('draft', 'this is in draft'),
       ('awaiting review', 'this is in awaiting-review'),
       ('published', 'this is in published'),
       ('blocked', 'this is in blocked'),
       ('age-restricted', 'this is in age-restricted');


SELECT * FROM post_status_lookup;

-- TABLE (template_users)

CREATE TABLE IF NOT EXISTS template_users
(
    -- User attributes
    user_id             bigserial PRIMARY KEY,
    public_id           varchar(12)           DEFAULT NULL,
    username            varchar(255) NOT NULL UNIQUE,
    email               varchar(255) NOT NULL UNIQUE,
    phone               varchar(20),
    password            varchar(255) NOT NULL,
    first_name          varchar(255) NOT NULL,
    last_name           varchar(255) NOT NULL,
    date_of_birth       DATE         NOT NULL,
    last_login_at       timestamptz,
    status              STATUS       NOT NULL,
    gender              GENDER,
    is_active           boolean               DEFAULT false,
    is_deleted          boolean               DEFAULT false,
    profile_pic         varchar(255),
    bio                 text,
    created_at          timestamptz           DEFAULT current_timestamp,
    updated_at          timestamptz           DEFAULT current_timestamp,

    -- User Preferences
    profile_privacy     PRIVACY_LEVEL         DEFAULT 'public',    -- Profile visibility setting
    notifications       JSONB        NOT NULL DEFAULT '{}'::jsonb, -- Tracks notification preferences
    social_links        JSONB                 DEFAULT '{}'::jsonb, -- JSONB to store multiple social media links if needed
    allow_messages      boolean               DEFAULT true,        -- Message permission

    -- Extracted below fields from above notifications so that below columns can be optimized through indexing
    email_notifications boolean               DEFAULT false,       -- Extracted from notifications JSONB
    sms_notifications   boolean               DEFAULT false,       -- Extracted from notifications JSONB

    version int default 1

    -- UNIQUE (public_id) adds index on public_id
    CONSTRAINT uq_template_users_public_id UNIQUE (public_id)
);

-- TABLE: INSERT ON template_users

INSERT INTO template_users (
    public_id, username, email, phone, password, first_name, last_name,
    date_of_birth, last_login_at, status, gender, is_active, is_deleted, 
    profile_pic, bio, profile_privacy, notifications, social_links, 
    email_notifications, sms_notifications
) VALUES
-- User 1
(
    'AB1234CD56EF', 'john_doe', 'john.doe@example.com', '1234567890', 'hashed_password_1',
    'John', 'Doe', '1990-05-15', '2024-12-01 08:30:00', 'active', 'male', true, false,
    'https://example.com/images/john.jpg', 'Tech enthusiast and avid reader.', 
    'public', '{"email": true, "sms": false}', '{"linkedin": "https://linkedin.com/in/john"}', 
    true, false
),
-- User 2
(
    'XY7890ZW12GH', 'jane_smith', 'jane.smith@example.com', '0987654321', 'hashed_password_2',
    'Jane', 'Smith', '1992-08-25', '2024-11-30 14:45:00', 'active', 'female', true, false,
    'https://example.com/images/jane.jpg', 'Photographer and designer.', 
    'friends', '{"email": true, "sms": true}', '{"twitter": "https://twitter.com/jane"}', 
    true, true
),
-- User 3
(
    'LM1234NO56PQ', 'alex_rivera', 'alex.rivera@example.com', '5678901234', 'hashed_password_3',
    'Alex', 'Rivera', '1985-11-10', '2024-11-29 10:15:00', 'inactive', 'non-binary', false, false,
    NULL, 'Coder and coffee lover.', 
    'private', '{"email": false, "sms": false}', '{}', 
    false, false
),
-- User 4
(
    'UV3456WX78YZ', 'mike_brown', 'mike.brown@example.com', '4561237890', 'hashed_password_4',
    'Mike', 'Brown', '1988-02-20', NULL, 'suspended', 'male', false, true,
    'https://example.com/images/mike.jpg', 'World traveler and foodie.', 
    'public', '{"email": true, "sms": false}', '{"instagram": "https://instagram.com/mike"}', 
    true, false
),
-- User 5
(
    'GH5678IJ90KL', 'emma_watson', 'emma.watson@example.com', '7890123456', 'hashed_password_5',
    'Emma', 'Watson', '1995-12-05', '2024-12-02 09:00:00', 'active', 'female', true, false,
    'https://example.com/images/emma.jpg', 'Music lover and blogger.', 
    'public', '{"email": true, "sms": true}', '{"facebook": "https://facebook.com/emma"}', 
    true, true
);


-- If often the query primarily focuses on status = 'active', a partial index is more efficient.
CREATE INDEX IF NOT EXISTS idx_active_users on template_users where status = 'active';

-- Recommended for key-value queries
CREATE INDEX IF NOT EXISTS idx_notifications ON template_users USING gin (notifications jsonb_path_ops);

-- Indexes on extracted fields for faster lookups
CREATE INDEX idx_email_notifications ON template_users (email_notifications);
CREATE INDEX idx_sms_notifications ON template_users (sms_notifications);

-- Index on user email for faster lookups in user-related queries
CREATE INDEX IF NOT EXISTS idx_user_email ON template_users (email);


-- Index on active user status to efficiently filter users based on status
CREATE INDEX IF NOT EXISTS idx_user_active_status ON template_users (status) WHERE status = 'active';

-- Composite index for user email and status to support complex user queries
CREATE INDEX IF NOT EXISTS idx_user_email_status ON template_users (email, status);


SELECT * FROM template_users;



-- TABLE (user_social_links)

CREATE TABLE user_social_links
(
    user_id  BIGINT REFERENCES template_users (user_id) ON DELETE CASCADE,
    platform VARCHAR(50),
    link     TEXT,
    PRIMARY KEY (user_id, platform)
);

SELECT * FROM user_social_links;


-- TABLE (template_countries)

CREATE TABLE IF NOT EXISTS template_states (
    state_id SERIAL PRIMARY KEY, -- Automatically generates unique integer IDs
    state_name VARCHAR(100) NOT NULL UNIQUE, -- Ensures state names are unique
    state_short VARCHAR(10) NOT NULL UNIQUE CHECK (LENGTH(state_short) <= 10), -- Enforces max length
    
    -- If a country is deleted from template_countries, all states associated with that country in template_states will also be deleted.
    -- Use Case: When the child data has no meaning without the parent data.
    -- country_id BIGINT NOT NULL REFERENCES template_countries (country_id) ON DELETE CASCADE -- Links to countries with enforced integrity
    
    -- If a country is deleted from template_countries, all states associated with that country in template_states will be null.
    -- Use Case: When the child data should persist even if the parent data is deleted, but the reference is no longer valid.
    -- country_id BIGINT NOT NULL REFERENCES template_countries (country_id) ON DELETE SET NULL

    -- If a country is deleted from template_countries, all states associated with that country in template_states will be default value of country_id .
    --  When you want child rows to fall back to a default value upon parent deletion.
    -- country_id BIGINT REFERENCES template_countries (country_id) ON DELETE SET DEFAULT

    -- Behavior: Prevents the deletion or update of the parent row if any child rows reference it.
    -- Use Case: When the child data must always have a valid parent, and deleting or updating the parent is not allowed.

    country_id BIGINT REFERENCES template_countries (country_id) ON UPDATE CASCADE ON DELETE RESTRICT

     -- NO ACTION (Default)
     -- Behavior: Similar to RESTRICT, but the check is deferred until the end of the transaction. If you delete a parent row and don't handle the related child rows within the transaction, it will result in an error.
     -- Use Case: Rarely used directly, but useful when you want strict control over manual updates.

     -- country_id BIGINT REFERENCES template_countries (country_id) ON DELETE NO ACTION

);


CREATE INDEX idx_state_country ON template_states (country_id);

-- TABLE (template_cities)

CREATE TABLE IF NOT EXISTS template_cities
(
    city_id    bigserial PRIMARY KEY,
    city_name  varchar(255) NOT NULL,
    state_id   bigint REFERENCES template_states (state_id) ON DELETE CASCADE,
    country_id bigint REFERENCES template_countries (country_id) ON DELETE CASCADE,
    population integer,
    district   varchar(100),
    created_at timestamptz DEFAULT current_timestamp
);

-- Index on stateId for faster lookups when joining with template_states
CREATE INDEX idx_template_cities_state_id ON template_cities (state_id);

-- Index on countryId for faster lookups when joining with template_countries
CREATE INDEX idx_template_cities_country_id ON template_cities (country_id);

-- Index on cityName if you frequently search by city name
CREATE INDEX idx_template_cities_city_name ON template_cities (city_name);

-- Composite index on state_id and country_id
CREATE INDEX idx_template_cities_state_country ON template_cities (state_id, country_id);

select *
from template_cities;


CREATE TABLE IF NOT EXISTS template_addresses
(
    address_id     bigserial primary key,
    user_id        bigint REFERENCES template_users (user_id) ON UPDATE CASCADE ON DELETE CASCADE,  -- add this column later
    street_address varchar(255) NOT NULL,
    city           varchar(50)  NOT NULL,
    city_id        bigint REFERENCES template_cities (city_id) ON UPDATE CASCADE ON DELETE CASCADE, -- this used when needed city level metadata like population
    postal_code    varchar(20),
    state_id       bigint REFERENCES template_states (state_id) ON UPDATE CASCADE ON DELETE CASCADE,
    country_id     bigint REFERENCES template_countries (country_id) ON UPDATE CASCADE ON DELETE CASCADE,
    is_primary     boolean     DEFAULT false,                                                       -- To identify the primary address
    created_at     timestamptz DEFAULT current_timestamp
);


CREATE UNIQUE INDEX idx_user_primary_address ON template_addresses (user_id) WHERE is_primary = true;

CREATE INDEX idx_template_addresses_state_id ON template_addresses (state_id);
CREATE INDEX idx_template_addresses_country_id ON template_addresses (country_id);

select * from template_addresses;

-- # Q: Why country, state and cities should be in its own table instead of as string value in template_address ?

-- e.g. when a country or state name changes, with `cascade` the linked or reference row in the child table will be updated / deleted automatically;

-- otherwise, it kept a same table then whenever adding for same or different users


-- Therefore, it should be a separate table 



-- #### View for User Profile with Address Information

CREATE VIEW user_profile AS
SELECT u.user_id, u.username, u.email, a.street_address, a.city, a.postal_code, a.country_id
FROM template_users u
INNER JOIN template_addresses a ON u.user_id = a.user_id;


SELECT * from user_profile;

CREATE OR REPLACE FUNCTION get_user_profile(p_user_id bigint)
    RETURNS TABLE
            (
                user_id        bigint,
                username       varchar,
                email          varchar,
                street_address varchar,
                city           varchar,
                postal_code    varchar,
                country_name   varchar
            )
AS
$$
BEGIN
    RETURN QUERY
        SELECT u.user_id, u.username, u.email, a.street_address, a.city, a.postal_code, c.country_name
        FROM template_users u
                 LEFT JOIN template_addresses a ON a.user_id = u.user_id
                 LEFT JOIN template_countries c ON a.country_id = c.country_id
        WHERE u.user_id = p_user_id; -- Using p_user_id to avoid ambiguity
END;
$$ LANGUAGE plpgsql;

SELECT *
FROM get_user_profile(1);

-- drop table if exists template_social_media_posts cascade;

CREATE TABLE IF NOT EXISTS template_social_media_posts
(
    post_id               bigserial PRIMARY KEY,                                        -- UNIQUE ID OF POST
    post_author           bigint REFERENCES template_users (user_id) ON DELETE CASCADE, -- Foreign key to template_users
    post_status           POST_STATUS,                                                  -- e.g. 'pending', 'awaiting for approval'
    post_visibility       POST_VISIBILITY,                                              -- e.g. 'public', 'private', 'only-me', 'restricted'
    is_allowed_to_comment boolean     default true,                                     -- whether to allow commenting on this post
    post_text             text,                                                         -- text content for post
    post_attachment       varchar(255),
    post_type             POST_TYPE,
    media_id              bigint REFERENCES template_media_files (media_id) ON DELETE CASCADE,
    created_at            timestamptz DEFAULT current_timestamp,
    updated_at            timestamptz DEFAULT current_timestamp
);

CREATE INDEX idx_post_author_visibility ON template_social_media_posts (post_author, post_visibility);

CREATE INDEX idx_post_author_status ON template_social_media_posts (post_author, post_status);

-- Replace column in `template_social_media_posts`
ALTER TABLE template_social_media_posts
    ADD COLUMN post_status_id INT REFERENCES post_status_lookup (id);

-- Example query with JOIN
SELECT p.*, s.name AS post_status_name
FROM template_social_media_posts p
         JOIN post_status_lookup s ON p.post_status_id = s.id;

select *
from template_social_media_posts;

-- # Partitioning helps manage large datasets by splitting tables based on range, hash, or list.
-- Range partitioning by post_date
CREATE TABLE template_social_media_posts_partitioned
(
    post_id         BIGSERIAL,
    post_author     BIGINT REFERENCES template_users (user_id) ON DELETE CASCADE,
    post_date       DATE NOT NULL,
    post_status     POST_STATUS,
    post_visibility POST_VISIBILITY,
    post_text       TEXT,
    PRIMARY KEY (post_id, post_date)
) PARTITION BY RANGE (post_date);

-- Partition for posts from 2023
CREATE TABLE IF NOT EXISTS template_social_media_posts_2023
    PARTITION OF template_social_media_posts_partitioned
        FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

-- Partition for posts from 2024 onwards
CREATE TABLE IF NOT EXISTS template_social_media_posts_2024
    PARTITION OF template_social_media_posts_partitioned
        FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- # OPTIMIZATION: Time-Series Clustering
-- WHAT: Cluster the table based on a time-based column (e.g., created_at).
-- WHY: Physically orders rows by time, reducing disk seeks.
-- BENEFIT: Faster queries when filtering/sorting by time ranges (e.g., WHERE created_at > ...).
-- WHEN: Use for time-based data like logs, events, or posts frequently queried by time.

-- Cluster table by created_at index
CREATE INDEX idx_post_created_at
    ON template_social_media_posts (created_at);

CLUSTER template_social_media_posts USING idx_post_created_at;


-- drop table if exists post_likes cascade;

CREATE TABLE IF NOT EXISTS post_likes
(
    post_id  bigint REFERENCES template_social_media_posts (post_id) ON DELETE CASCADE, -- Foreign key to posts
    user_id  bigint REFERENCES template_users (user_id) ON DELETE CASCADE,              -- Foreign key to users
    liked_at timestamptz DEFAULT current_timestamp,                                     -- Timestamp when user liked the post
    PRIMARY KEY (post_id, user_id)                                                      -- Composite primary key (postId, userId)
);

CREATE INDEX idx_post_likes_user_id_post_id ON post_likes (user_id, post_id);

select *
from post_likes;

-- drop table if exists followers_following cascade;

CREATE TABLE IF NOT EXISTS followers_following
(
    follower_id  bigint REFERENCES template_users (user_id) ON DELETE CASCADE, -- User who is following
    following_id bigint REFERENCES template_users (user_id) ON DELETE CASCADE, -- User being followed
    followed_at  timestamptz DEFAULT current_timestamp,                        -- Timestamp of follow action
    PRIMARY KEY (follower_id, following_id)                                    -- Composite key to ensure uniqueness
);

CREATE INDEX idx_follower_id ON followers_following (follower_id);
CREATE INDEX idx_following_id ON followers_following (following_id);

-- CREATE INDEX idx_follower_following_id ON followers_following (followerId, followingId);

-- # De-normalization for Read-Heavy Workloads: Materialized views aggregate data for faster reads.
CREATE MATERIALIZED VIEW user_followers_count AS
SELECT following_id AS user_id, COUNT(*) AS followers_count
FROM followers_following
GROUP BY following_id;

-- Index for fast lookup
CREATE INDEX idx_followers_count ON user_followers_count (user_id);

-- 1. Manual Refresh: By running the below query, the view i.e. user_followers_count will be "manually refresh"
REFRESH MATERIALIZED VIEW user_followers_count;

-- 2. Automatic Refresh (on-demand or scheduled): automatically refresh a materialized view when underlying data changes through a Trigger (programmatically the cron jobs)

-- Create the function to refresh the materialized view
CREATE OR REPLACE FUNCTION refresh_user_followers_count()
    RETURNS trigger AS
$$
BEGIN
    -- Refresh the materialized view whenever there's an insert, update, or delete
    REFRESH MATERIALIZED VIEW user_followers_count;
    RETURN NULL; -- Trigger functions must return a value, but we don't need any specific return here
END;
$$ LANGUAGE plpgsql;

-- Create the trigger to call the function after any insert, update, or delete
CREATE TRIGGER refresh_user_followers_count
    AFTER INSERT OR UPDATE OR DELETE
    ON followers_following -- whenever this table does INSERT, UPDATE OR DELETE this will be trigger
    FOR EACH STATEMENT
    -- so below, instead of refresh_user_followers_count, some other function like below refresh_followers_count could've also worked fine
EXECUTE FUNCTION refresh_user_followers_count(); --

-- 3. Stored Procedure: You can create a stored procedure that automatically refreshes the materialized view:
CREATE OR REPLACE FUNCTION refresh_followers_count() RETURNS void
AS
$$ -- indicates the start of function body
BEGIN
    REFRESH MATERIALIZED VIEW user_followers_count; --  The command to refresh the materialized view user_followers_count
END;
$$ LANGUAGE plpgsql;

-- 4. Using CTE (Common Table Expressions) or Recursive CTE: While CTEs are useful for queries, they don't directly support refreshing materialized views. However, you can use them inside functions to perform complex queries and refresh logic.
-- Here, cte or recursive cte won't be as it is helpful for writing complex queries not for "refreshing view"


-- 5. Dynamic SQL: A dynamic SQL query inside a function can be used to refresh materialized views:
CREATE OR REPLACE FUNCTION refresh_dynamic_view() RETURNS void -- this function returns void
AS
$$ -- Indicates the start of the function’s body
BEGIN --  Marks the start of the procedural block
    EXECUTE 'REFRESH MATERIALIZED VIEW ' || quote_ident('user_followers_count');
END; --  Marks the end of the function block.
$$ LANGUAGE plpgsql; -- Ends the function definition and specifies that PL/pgSQL is used;


select *
from followers_following;

-- To count the followers of the given user below:
-- SELECT COUNT(*)  FROM followers_following WHERE followingId = <user_id>;

-- To count the following count of the given user below:
-- SELECT COUNT(*)  FROM followers_following WHERE followerId = <user_id>;

-- drop table if exists template_comments cascade;

CREATE TABLE IF NOT EXISTS template_comments
(
    comment_id  BIGSERIAL PRIMARY KEY,                                     -- Unique ID for each comment
    user_id     BIGINT      NOT NULL,                                      -- User ID who created the comment
    content     TEXT        NOT NULL,                                      -- Content of the comment
    entity_id   BIGINT      NOT NULL,                                      -- ID of the entity (could be post, media, etc.)
    entity_type VARCHAR(50) NOT NULL,                                      -- Type of the entity (e.g., 'post', 'image', etc.)
    post_id     BIGINT,                                                    -- Specifically for posts (nullable, but used if the comment is linked to a post)
    parent_id   BIGINT,                                                    -- Parent comment ID (for replies)
    thread_id   BIGINT      NOT NULL,                                      -- Thread ID (grouping related comments and replies)
    created_at  TIMESTAMP   DEFAULT NOW(),                                 -- Timestamp when the comment was created
    updated_at  TIMESTAMP   DEFAULT NOW(),                                 -- Timestamp when the comment was last updated
    status      VARCHAR(20) DEFAULT 'active',                              -- Comment status (active, deleted, etc.)
    FOREIGN KEY (user_id) REFERENCES template_users (user_id),             -- User who posted the comment
    FOREIGN KEY (parent_id) REFERENCES template_comments (comment_id),     -- Self-referencing foreign key for replies
    FOREIGN KEY (post_id) REFERENCES template_social_media_posts (post_id) -- Foreign key to posts (optional)
);


-- Index on post_id for optimized lookups: this index helps with queries that filter by post_id
CREATE INDEX IF NOT EXISTS idx_template_comments_post_id ON template_comments (post_id);

-- Q: Why Use `status_id` in Partitioned `template_comments` Table:**
-- 1. **Scalability:**
--    Partitioning helps manage large datasets by splitting data into smaller chunks (based on `created_at`).
--    Storing status as an `ID` (from `comment_status_lookup`) rather than a string (`VARCHAR`) improves performance by making indexing and querying faster.

-- 2. **Ease of Updates:**
--    Using `status_id` allows you to add or modify status types in the `comment_status_lookup` table without needing to update the `template_comments` table directly.
--    This makes it easier to manage status values at scale, especially when adding new statuses.

-- 3. **Performance Optimization:**
--    Integer-based `status_id` is more efficient for indexing and querying, especially in large datasets.
--    It also saves storage space compared to using string-based status values, which is important when handling millions of rows.

-- **Why Not Use `status_id` in `template_comments` Table (Non-Partitioned):**
--    The non-partitioned `template_comments` table can still use a `VARCHAR` or `ENUM` directly for `status` if the dataset is smaller or doesn't require the same level of scalability.
--    For smaller tables, a direct `VARCHAR` or `ENUM` could be simpler and sufficient. However, for large-scale applications with partitioning, using a `status_id` with a lookup table improves performance and flexibility.


-- Partitioning Strategy for Large Dataset


-- DROP TABLE IF EXISTS  template_comments_partitioned cascade;

CREATE TABLE template_comments_partitioned
(
    comment_id BIGSERIAL,
    user_id    BIGINT,
    created_at DATE NOT NULL,
    content    TEXT,
    status_id  INT REFERENCES comment_status_lookup (id),
    PRIMARY KEY (comment_id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE template_comments_2023
    PARTITION OF template_comments_partitioned
        FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE template_comments_2024
    PARTITION OF template_comments_partitioned
        FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- Index on created_at for partitioned table (optional, but improves query performance)
CREATE INDEX IF NOT EXISTS idx_template_comments_created_at
    ON template_comments_partitioned (created_at);

-- Indexing on frequently accessed fields


-- Lookup Table for Comment Status

-- This table holds predefined statuses for comments (approved, pending, etc.)
CREATE TABLE IF NOT EXISTS comment_status_lookup
(
    id   SERIAL PRIMARY KEY,
    name VARCHAR(20) UNIQUE NOT NULL
);

-- Insert default values for comment statuses
INSERT INTO comment_status_lookup (name)
VALUES ('approved'),
       ('pending'),
       ('flagged');

-- Adding foreign key constraint to the partitioned table for status_id
-- This ensures referential integrity with the comment_status_lookup table
ALTER TABLE template_comments_partitioned
    ADD CONSTRAINT fk_status_id FOREIGN KEY (status_id)
        REFERENCES comment_status_lookup (id) ON DELETE CASCADE;

-- View the current state of the template_comments table
SELECT *
FROM template_comments;


CREATE TABLE IF NOT EXISTS template_replies
(
    reply_id   BIGSERIAL PRIMARY KEY,                                 -- Auto-incrementing ID (BIGSERIAL for large scale)
    user_id    BIGINT NOT NULL,                                       -- User ID who created the reply
    content    TEXT   NOT NULL,                                       -- Content of the reply
    parent_id  BIGINT NOT NULL,                                       -- Parent comment's ID (must be referenced in the comments table)
    created_at TIMESTAMP   DEFAULT NOW(),                             -- Timestamp when the reply was created
    updated_at TIMESTAMP   DEFAULT NOW(),                             -- Timestamp when the reply was last updated
    status     VARCHAR(20) DEFAULT 'active',                          -- Reply status (e.g., 'active', 'deleted', etc.)
    thread_id  BIGINT NOT NULL,                                       -- Thread ID (the group of comments and replies)
    FOREIGN KEY (user_id) REFERENCES template_users (user_id),        -- Assuming there's a 'users' table
    FOREIGN KEY (parent_id) REFERENCES template_comments (comment_id) -- Parent comment reference
);

-- DROP INDEX IF EXISTS idx_template_replies;
CREATE INDEX idx_template_replies_parent_comment_id ON template_replies (parent_id);


select *
from template_replies;

-- drop table if exists template_media_files cascade;

-- Social Media Domain: Media Files (optional if you're managing media separately)
CREATE TABLE IF NOT EXISTS template_media_files
(
    media_id         bigserial PRIMARY KEY,
    media_created_by bigint REFERENCES template_users (user_id) ON DELETE CASCADE, -- Foreign key to template_users
    media_type       varchar(50),                                                  -- 'image', 'video', etc.
    media_url        varchar(255),
    created_at       timestamptz DEFAULT current_timestamp
);

select *
from template_media_files;

-- drop table if exists template_friends cascade;

-- Social Media Domain: friends
CREATE TABLE IF NOT EXISTS template_friends
(
    user_id       bigint REFERENCES template_users (user_id) ON DELETE CASCADE,
    friend_id     bigint REFERENCES template_users (user_id) ON DELETE CASCADE,
    friend_status FRIEND_STATUS NOT NULL DEFAULT 'none',
    PRIMARY KEY (user_id, friend_id)
);

select *
from template_friends;

-- drop table if exists template_user_groups cascade;

CREATE TABLE IF NOT EXISTS template_user_groups
(
    group_id          bigserial PRIMARY KEY,                                               -- Unique ID for the group
    group_name        varchar(100) NOT NULL,                                               -- Name of the group
    group_description text,                                                                -- Description of the group
    group_logo        varchar(255),                                                        -- logo of the group
    group_banner      varchar(255),                                                        -- banner of the group
    group_created_by  bigint       REFERENCES template_users (user_id) ON DELETE SET NULL, -- User who created the group
    is_private        boolean     DEFAULT false,                                           -- Option to set group privacy (public/private)
    created_at        timestamptz DEFAULT current_timestamp,                               -- Timestamp when the group was created
    updated_at        timestamptz DEFAULT current_timestamp                                -- Timestamp when the group was updated
);

select *
from template_user_groups;

-- drop table if exists template_group_memberships cascade;

-- User Group Memberships (many-to-many relationship between users and groups) (NOT EXECUTED)
CREATE TABLE IF NOT EXISTS template_group_memberships
(
    group_id  bigint REFERENCES template_user_groups (group_id) ON DELETE CASCADE,
    user_id   bigint REFERENCES template_users (user_id) ON DELETE CASCADE,
    joined_at timestamptz DEFAULT current_timestamp,
    PRIMARY KEY (group_id, user_id)
);

select *
from template_group_memberships;


-- Online shop: products

DROP TABLE IF EXISTS products cascade;

CREATE TABLE IF NOT EXISTS products
(
    product_id     BIGSERIAL PRIMARY KEY,
    product_name   VARCHAR(255)   NOT NULL,
    description    TEXT,
    base_price     DECIMAL(10, 2) NOT NULL,
    category_id    BIGINT         NOT NULL REFERENCES categories (category_id),
    brand_id       BIGINT REFERENCES brands (brand_id),
    stock_quantity INT            NOT NULL DEFAULT 0, -- Available stock for the product
    created_at     TIMESTAMP               DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP               DEFAULT CURRENT_TIMESTAMP
);

-- Insert products
INSERT INTO products (product_name, description, base_price, category_id)
VALUES ('iPhone 14', 'Apple iPhone 14 with 128GB storage', 999.99, 2),        -- Product under 'Mobile Phones'
       ('MacBook Pro 16"', 'Apple MacBook Pro with M1 Pro chip', 2499.99, 3), -- Product under 'Laptops'
       ('Sony Headphones', 'Noise-cancelling Sony headphones', 299.99, 4);
-- Product under 'Headphones'

-- ALTER TABLE products RENAME COLUMN price TO base_price;


select *
from products;

CREATE TABLE IF NOT EXISTS attributes
(
    attribute_id   BIGSERIAL PRIMARY KEY,
    attribute_name VARCHAR(255) NOT NULL
);

-- Insert Sample Data
INSERT INTO attributes (attribute_name)
VALUES ('Color'),
       ('Size'),
       ('Material'),
       ('Storage');


SELECT *
FROM attributes;

CREATE TABLE IF NOT EXISTS attribute_values
(
    value_id     BIGSERIAL PRIMARY KEY,
    attribute_id BIGINT       NOT NULL REFERENCES attributes (attribute_id),
    value_name   VARCHAR(255) NOT NULL
);

-- Insert Sample Data
INSERT INTO attribute_values (attribute_id, value_name)
VALUES (1, 'Green'),
       (1, 'Blue'),
       (2, 'Medium'),
       (2, 'Large');

select *
from attribute_values;

DROP TABLE IF EXISTS product_variant_combination_values cascade;

CREATE TABLE IF NOT EXISTS product_variant_combination_values
(
    combination_value_id BIGSERIAL PRIMARY KEY,
    product_id           BIGINT         NOT NULL REFERENCES products (product_id),
    price                DECIMAL(10, 2) NOT NULL,
    combination_details  JSONB          NOT NULL -- variant combination
);

-- Insert Sample Data
INSERT INTO product_variant_combination_values (product_id, price, combination_details)
VALUES (1, 100.00, '{
  "Color": "Green",
  "Size": "Medium"
}'),        -- Green + Medium
       (1, 120.00, '{
         "Color": "Green",
         "Size": "Large"
       }'), -- Green + Large
       (1, 130.00, '{
         "Color": "Red",
         "Size": "Medium"
       }'), -- Red + Medium
       (1, 150.00, '{
         "Color": "Red",
         "Size": "Large"
       }'); -- Red + Large

SELECT *
from product_variant_combination_values;

-- Given a product, say T-shirt with selected variants Color: Green and Size: Medium
SELECT price
FROM product_variant_combination_values
WHERE product_id = 1 -- T-shirt
  AND combination_details @> '{"Color": "Green", "Size": "Medium"}';

DROP TABLE IF EXISTS categories cascade;

-- flat vs parent-child relationship: when the said attribute is of single type e.g. comment, category but if said attribute is different type size, color then flat

CREATE TABLE IF NOT EXISTS categories
(
    category_id        BIGSERIAL PRIMARY KEY,
    category_name      VARCHAR(255) NOT NULL,
    parent_category_id BIGINT REFERENCES categories (category_id) ON DELETE CASCADE,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- DROP TABLE IF EXISTS brands;

CREATE TABLE IF NOT EXISTS brands
(
    brand_id    BIGSERIAL PRIMARY KEY,
    name        varchar(255) UNIQUE NOT NULL,
    description TEXT
);

-- Insert brands
INSERT INTO brands (name, description)
VALUES ('Apple', 'Premium smartphone and electronics brand'),
       ('Google', 'Google-branded electronics'),
       ('Samsung', 'Popular mobile brand'),
       ('Motorola', 'Affordable mobile phones');

select *
from brands;

DROP TABLE IF EXISTS brand_categories cascade;

CREATE TABLE IF NOT EXISTS brand_categories
(
    brand_id    BIGINT NOT NULL REFERENCES brands (brand_id),        -- Apple, Google
    category_id BIGINT NOT NULL REFERENCES categories (category_id), -- Mobile, Accessories
    PRIMARY KEY (brand_id, category_id)
);

-- Apple belongs to both 'Mobile' and 'Accessories' categories
INSERT INTO brand_categories (brand_id, category_id)
VALUES (1, 2), -- Apple is in Mobile
       (1, 3); -- Apple is also in Accessories


select *
from brand_categories;

-- Get all brands under the "Mobile & Accessories" category:

SELECT *
FROM brands;
select *
from brand_categories;

SELECT *
FROM categories;

select *
from brand_categories;

SELECT b.name AS brand_name
FROM brands b
         JOIN brand_categories bc ON b.brand_id = bc.brand_id
         JOIN categories c ON c.category_id = bc.category_id
WHERE c.category_name = 'Books';

-- TRUNCATE TABLE categories cascade;

INSERT INTO categories (category_name, parent_category_id)
values ('Electronics', null),
       ('Books', null);

INSERT INTO categories (category_name, parent_category_id)
values ('Tablets', 1),
       ('Mobile & Accessories', 1);

select *
from categories;

select c1.category_id as parent_id, c1.category_name as parent, c2.category_name AS sub
from categories c1
         inner join categories c2 on c2.parent_category_id = c1.category_id
ORDER BY c1.category_id;

WITH RECURSIVE category_tree AS (SELECT category_id, category_name, parent_category_id
                                 FROM categories
                                 WHERE parent_category_id IS NULL -- Start with the root categories
                                 UNION ALL
                                 SELECT c.category_id, c.category_name, c.parent_category_id
                                 FROM categories c
                                          INNER JOIN category_tree ct ON c.parent_category_id = ct.category_id)
SELECT *
FROM category_tree;

-- Get Products by Category (Including Subcategories)
WITH RECURSIVE subcategories AS (SELECT category_id
                                 FROM categories
                                 WHERE parent_category_id IS NULL -- Start with the root categories (e.g., Electronics)
                                 UNION ALL
                                 SELECT c.category_id
                                 FROM categories c
                                          INNER JOIN subcategories s ON c.parent_category_id = s.category_id)
SELECT p.product_id, p.product_name, p.description
FROM products p
WHERE p.category_id IN (SELECT category_id FROM subcategories);

-- discount table
-- DROP TABLE IF EXISTS discounts cascade;

-- For now, when a same product multiple discounts, it will be recorded in this `discounts` table
CREATE TABLE IF NOT EXISTS discounts
(
    discount_id    BIGSERIAL PRIMARY KEY,
    discount_code  VARCHAR(50) UNIQUE NOT NULL,                                                  -- Discount code to apply
    discount_type  VARCHAR(10)        NOT NULL CHECK (discount_type IN ('percentage', 'fixed')), -- 'percentage' or 'fixed'
    discount_value DECIMAL(10, 2)     NOT NULL,                                                  -- Discount value (either percentage or fixed amount)
    product_id     BIGINT             NOT NULL REFERENCES products (product_id),                 -- The product this discount applies to
    is_active      BOOLEAN DEFAULT TRUE,                                                         -- To mark if the discount is currently active
    max_uses       INT     DEFAULT 1,                                                            -- Max uses per discount (1 means it can only be used once)
    start_date     TIMESTAMP,                                                                    -- Optional start date for the discount
    end_date       TIMESTAMP                                                                     -- Optional end date for the discount
);

select *
from discounts;

-- DROP TABLE IF EXISTS gift_cards cascade;

CREATE TABLE IF NOT EXISTS gift_cards
(
    gift_card_id    BIGSERIAL PRIMARY KEY,
    gift_card_code  VARCHAR(50) UNIQUE NOT NULL, -- Unique gift card code
    gift_card_value DECIMAL(10, 2)     NOT NULL, -- The value of the gift card
    is_active       BOOLEAN DEFAULT TRUE         -- To indicate if the gift card is still active or valid
);

-- DROP TABLE IF EXISTS user_discount_usage cascade;

CREATE TABLE IF NOT EXISTS user_discount_usage
(
    user_discount_usage_id BIGSERIAL PRIMARY KEY,
    user_id                BIGINT NOT NULL REFERENCES users (user_id),         -- Link to the user
    product_id             BIGINT NOT NULL REFERENCES products (product_id),   -- Link to the product
    discount_id            BIGINT NOT NULL REFERENCES discounts (discount_id), -- Link to the discount
    applied_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,                -- Timestamp of when the discount was applied
    UNIQUE (user_id, product_id, discount_id)                                  -- Ensure discount can only be applied once per product for each user
);

-- DROP TABLE IF EXISTS user_gift_card_usage cascade;
CREATE TABLE IF NOT EXISTS user_gift_card_usage
(
    user_gift_card_usage_id BIGSERIAL PRIMARY KEY,
    user_id                 BIGINT NOT NULL REFERENCES users (user_id),           -- Link to the user
    product_id              BIGINT NOT NULL REFERENCES products (product_id),     -- Link to the product
    gift_card_id            BIGINT NOT NULL REFERENCES gift_cards (gift_card_id), -- Link to the gift card
    applied_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,                  -- Timestamp of when the gift card was used
    UNIQUE (user_id, product_id, gift_card_id)                                    -- Ensure gift card can only be used once per user per product
);

-- Insert a discount (percentage)
INSERT INTO discounts (discount_code, discount_type, discount_value, product_id, start_date, end_date, is_active)
VALUES ('SUMMER2024', 'percentage', 10.00, 1, '2024-06-01', '2024-06-30', TRUE);

-- Insert a discount (fixed amount)
INSERT INTO discounts (discount_code, discount_type, discount_value, product_id, start_date, end_date, is_active)
VALUES ('FLAT50', 'fixed', 50.00, 1, '2024-06-01', '2024-06-30', TRUE);

-- Insert a gift card
INSERT INTO gift_cards (gift_card_code, gift_card_value, is_active)
VALUES ('GIFT100', 100.00, TRUE);


-- Calculating Price Reduction (Final Price Calculation)
WITH applied_discounts AS (
    -- Step 1: Get all valid discounts for the product that have not been used by the user yet
    SELECT SUM(CASE
                   WHEN d.discount_type = 'percentage' THEN (p.base_price * d.discount_value / 100)
                   WHEN d.discount_type = 'fixed' THEN d.discount_value
                   ELSE 0
        END) AS discount_total
    FROM products p
             JOIN discounts d ON p.product_id = d.product_id
    WHERE p.product_id = :product_id
      AND d.is_active = TRUE -- Ensure the discount is active
      AND NOT EXISTS (SELECT 1
                      FROM user_discount_usage u
                      WHERE u.user_id = :user_id
                        AND u.product_id = :product_id
                        AND u.discount_id = d.discount_id)),
     gift_card_applied AS (
         -- Step 2: Check if a valid gift card is used for the product
         SELECT g.gift_card_value
         FROM gift_cards g
         WHERE g.gift_card_id = :gift_card_id
           AND g.is_active = TRUE
           AND NOT EXISTS (SELECT 1
                           FROM user_gift_card_usage gcu
                           WHERE gcu.user_id = :user_id
                             AND gcu.product_id = :product_id
                             AND gcu.gift_card_id = g.gift_card_id))
-- Final price calculation
SELECT p.base_price,
       ad.discount_total,
       gc.gift_card_value,
       (p.base_price - ad.discount_total - COALESCE(gc.gift_card_value, 0)) AS final_price
FROM products p
         JOIN applied_discounts ad ON p.product_id = :product_id
         LEFT JOIN gift_card_applied gc ON true -- No need for condition on NULL here instead used ON true
-- The LEFT JOIN with gc (the gift card data) will still work because if there's no valid gift card for the product, the gift_card_value will simply be NULL, and the COALESCE(gc.gift_card_value, 0) ensures that it is treated as 0 if no gift card is applied.
WHERE p.product_id = :product_id;

-- CREATE MATERIALIZED VIEW mv_stock_summary AS
-- SELECT product_id, SUM(stock_quantity) AS total_stock
-- FROM product_variants
-- GROUP BY product_id;

-- Index on materialized view
-- CREATE INDEX idx_mv_stock_summary_product_id ON mv_stock_summary (product_id);

-- Partitioning the `products` table by the `created_at` year
CREATE TABLE products_y2023 PARTITION OF products
    FOR VALUES FROM ('2023-01-01') TO ('2023-12-31');

CREATE TABLE products_y2024 PARTITION OF products
    FOR VALUES FROM ('2024-01-01') TO ('2024-12-31');

CREATE TABLE IF NOT EXISTS sellers
(
    seller_id              BIGSERIAL PRIMARY KEY,
    user_id                BIGINT              NOT NULL, -- Link to template_users
    store_name             VARCHAR(255)        NOT NULL,
    store_description      TEXT,
    email                  VARCHAR(255) UNIQUE NOT NULL,
    phone_number           VARCHAR(20),
    business_type          VARCHAR(50),                  -- Individual, Small Business, Brand, etc.
    location               VARCHAR(255),                 -- Store location
    seller_tier            VARCHAR(50),                  -- Regular, Premium, Enterprise
    rating                 DECIMAL(3, 2) DEFAULT 5.00,   -- Average seller rating (out of 5)
    review_count           INT           DEFAULT 0,      -- Number of reviews
    return_rate            DECIMAL(5, 2) DEFAULT 0.00,   -- Return rate in percentage
    product_count          INT           DEFAULT 0,      -- Number of products listed
    shipping_method        VARCHAR(255),                 -- Seller's preferred shipping method
    tax_information        VARCHAR(255),                 -- Tax ID, VAT, etc.
    bank_account_details   VARCHAR(255),                 -- For payment transfer
    payment_method         VARCHAR(50),                  -- PayPal, Direct Deposit, etc.
    account_health_metrics JSONB,                        -- JSON object with health metrics (e.g., order defect rate)
    subscription_plan      VARCHAR(50),                  -- Subscription type: Free, Basic, Premium
    premium_features       JSONB,                        -- List of premium features if applicable (e.g., advertising tools)
    created_at             TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES template_users (user_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sellers_store_name_rating
    ON sellers (store_name, rating);

CREATE INDEX IF NOT EXISTS idx_sellers_tier_review_count
    ON sellers (seller_tier, review_count);


CREATE TABLE IF NOT EXISTS wishlist
(
    wishlist_id BIGSERIAL PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users (user_id),       -- User who added the product to the wishlist
    product_id  BIGINT NOT NULL REFERENCES products (product_id), -- Product that is on the wishlist
    added_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,              -- Timestamp when the product was added to the wishlist
    UNIQUE (user_id, product_id)                                  -- Ensure the user can only add a product once to the wishlist
);

select *
from template_users;

-- INSERT INTO wishlist (user_id, product_id)
-- VALUES
-- (1, 1),
-- (1, 2);

select *
from wishlist;

-- DROP TABLE IF EXISTS orders cascade;
CREATE TABLE IF NOT EXISTS orders
(
    order_id            BIGSERIAL PRIMARY KEY,
    user_id             BIGINT         NOT NULL REFERENCES users (user_id), -- User who placed the order
    order_date          TIMESTAMP               DEFAULT CURRENT_TIMESTAMP,
    status              VARCHAR(20)    NOT NULL CHECK (status IN ('pending', 'paid', 'shipped', 'delivered', 'canceled')),
    currency            VARCHAR(10)    NOT NULL DEFAULT 'USD',              -- Currency used in this order
    total_price         DECIMAL(10, 2) NOT NULL,
    shipping_address_id BIGINT REFERENCES template_addresses (address_id),
    billing_address_id  BIGINT REFERENCES template_addresses (address_id),
    payment_method_id   BIGINT REFERENCES template_addresses (address_id)
);


CREATE TABLE IF NOT EXISTS order_items
(
    order_item_id BIGSERIAL PRIMARY KEY,
    order_id      BIGINT         NOT NULL REFERENCES orders (order_id),
    product_id    BIGINT         NOT NULL REFERENCES products (product_id),
    quantity      INT            NOT NULL,
    price         DECIMAL(10, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS payment_methods
(
    payment_method_id BIGSERIAL PRIMARY KEY,
    user_id           BIGINT      NOT NULL REFERENCES users (user_id),
    method_type       VARCHAR(50) NOT NULL, -- e.g., 'credit card', 'PayPal', 'bank transfer'
    details           TEXT        NOT NULL  -- Encrypted or masked payment details
);


