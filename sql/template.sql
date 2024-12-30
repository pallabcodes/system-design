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

-- othherwise, it kept a same table then whenever adding for same or different users