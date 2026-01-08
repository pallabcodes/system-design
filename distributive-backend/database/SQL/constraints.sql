-- Purpose: Primary column(s) simply allows to find the searched row(s) correctly from the all available rows.

-- A table doesn't need to have Primary key (e.g. junction table)
-- A table could have single or multiple primary keys

-- # Primary key

-- Primary key with single column
CREATE TABLE IF NOT EXISTS orders
(
    order_id    SERIAL PRIMARY KEY,
    customer_id VARCHAR(255) NOT NULL,
    order_date  DATE         NOT NULL
);

-- Primary key with multiple columns
CREATE TABLE IF NOT EXISTS order_items
(
    order_id         INT,
    item_no          SERIAL,
    item_description VARCHAR NOT NULL,
    quantity         INTEGER NOT NULL,
    price            DEC(10, 2),
    PRIMARY KEY (order_id, item_no)
);

-- Step 1: Create a new sequence for product_id (by default it will start from 1 which is why it doesn't need to be initialized below)
-- CREATE SEQUENCE products_product_id_seq;

-- Step 2: Attach the sequence to the product_id column as the default
-- ALTER TABLE products ALTER COLUMN product_id SET DEFAULT nextval('products_product_id_seq');

-- Step 3: Add a PRIMARY KEY constraint to the product_id column (if not already done)
-- ALTER TABLE products ADD PRIMARY KEY (product_id);

-- Step 4: Select all from products to verify
SELECT *
FROM products;

CREATE TABLE vendors
(
    name VARCHAR(255)
);

INSERT INTO vendors (name)
VALUES ('Microsoft'),
       ('IBM'),
       ('Apple'),
       ('Samsung')
RETURNING *;

ALTER TABLE vendors
    ADD COLUMN vendor_id SERIAL PRIMARY KEY;

select vendor_id, name
from vendors;

-- Remove the primary key constraint from vendors (not the primary column(s))
ALTER TABLE vendors
    DROP CONSTRAINT vendors_pkey;

-- add it back on the required column(s)
ALTER TABLE vendors
    ADD CONSTRAINT vendors_pkey PRIMARY KEY (vendor_id);

-- # Foreign Key: A foreign key is a column or a group of columns in a table that uniquely identifies a row in another table.

CREATE TABLE users2
(
    user_id  SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE -- Unique constraint on 'username'
);

-- INSERT INTO users2 (username) VALUES ('john'), ('alice');

-- Create the second table with a foreign key that references the unique column instead of a primary column(s)

CREATE TABLE posts
(
    post_id       SERIAL PRIMARY KEY,
    user_username VARCHAR(255),
    content       TEXT,
    FOREIGN KEY (user_username) REFERENCES users (username) -- Foreign key referencing the unique 'username'
);

-- INSERT INTO posts (user_username, content) VALUES ('john', 'This is John''s first post.');


-- Unique Constraint on users.username: The users table has a unique constraint on the username column, which ensures that no two users can have the same username.
-- Foreign Key on posts.user_username: The posts table has a foreign key referencing users.username. Since users.username is unique, this foreign key ensures that each post is linked to a unique user based on their username.

DROP TABLE IF EXISTS customers cascade;
DROP TABLE IF EXISTS contacts cascade;

CREATE TABLE customers
(
    customer_id   INT GENERATED ALWAYS AS IDENTITY,
    customer_name VARCHAR(255) NOT NULL,
    PRIMARY KEY (customer_id)
);

CREATE TABLE contacts
(
    -- can the contact_id be the "Primary key and Foreign key in this table" ?
    contact_id   INT GENERATED ALWAYS AS IDENTITY,
    customer_id  INT,
    contact_name VARCHAR(255) NOT NULL,
    phone        VARCHAR(15),
    email        VARCHAR(100),
    PRIMARY KEY (contact_id),
    CONSTRAINT fk_customer
        FOREIGN KEY (customer_id)
            REFERENCES customers (customer_id) ON DELETE CASCADE
);

INSERT INTO customers(customer_name)
VALUES ('BlueBird Inc'),
       ('Dolphin LLC');

INSERT INTO contacts(customer_id, contact_name, phone, email)
VALUES (1, 'John Doe', '(408)-111-1234', '[[email protected]](../cdn-cgi/l/email-protection.html)'),
       (1, 'Jane Doe', '(408)-111-1235', '[[email protected]](../cdn-cgi/l/email-protection.html)'),
       (2, 'David Wright', '(408)-222-1234', '[[email protected]](../cdn-cgi/l/email-protection.html)');

select *
from contacts;

select *
from customers;

DELETE
FROM customers
WHERE customer_id = 1;

-- Create the contacts table with composite foreign key and primary key
-- CREATE TABLE contacts (
--    contact_id INT GENERATED ALWAYS AS IDENTITY,
--    customer_id INT,
--    contact_name VARCHAR(255) NOT NULL,
--    phone VARCHAR(15),
--    email VARCHAR(100),
--
--    -- Define composite foreign key (customer_id, contact_id)
--    CONSTRAINT fk_customer_contact
--       FOREIGN KEY (customer_id, contact_id)  -- Two columns for foreign key
--       REFERENCES customers (customer_id, contact_id),  -- Referencing composite key from customers table
--
--    PRIMARY KEY(contact_id, customer_id)  -- Composite primary key for contacts table
-- );

-- Adding a composite foreign key after table creation
-- ALTER TABLE contacts
--    ADD CONSTRAINT fk_customer_contact
--    FOREIGN KEY (customer_id, contact_id)  -- Foreign key referencing multiple columns
--    REFERENCES customers (customer_id, contact_id);  -- Parent table columns


-- Add a foreign key constraint to an existing table e.g. customers
ALTER TABLE contacts
    ADD CONSTRAINT fk_customer
        FOREIGN KEY (customer_id) -- Foreign key column
            REFERENCES customers (customer_id);
-- Parent table and column

-- Add a foreign key constraint to an existing table e.g. contacts
ALTER TABLE contacts
    ADD CONSTRAINT fk_contact_name
        FOREIGN KEY (contact_name) -- Foreign key column
            REFERENCES contacts (contact_name);
-- Parent table and column

-- To add a new foreign key constraint, drop the existing and then add new
-- ALTER TABLE child_table DROP CONSTRAINT constraint_fkey;

-- ALTER TABLE child_table
-- ADD CONSTRAINT constraint_fk
-- FOREIGN KEY (fk_columns)
-- REFERENCES parent_table(parent_key_columns)
-- ON DELETE CASCADE;

-- # CHECK

CREATE TABLE IF NOT EXISTS employees
(
    id          SERIAL PRIMARY KEY,
    first_name  VARCHAR(50) NOT NULL,
    last_name   VARCHAR(50) NOT NULL,
    birth_date  DATE        NOT NULL,
    joined_date DATE        NOT NULL,
    salary      numeric CHECK (salary > 0)
);

INSERT INTO employees (first_name, last_name, birth_date, joined_date, salary)
VALUES ('John', 'Doe', '1972-01-01', '2015-07-01', -100000);

ALTER TABLE employees
    ADD CONSTRAINT joined_date_check CHECK ( joined_date > birth_date );

-- This will throw error as expected since here birth_date > joined_date
INSERT INTO employees (first_name, last_name, birth_date, joined_date, salary)
VALUES ('John', 'Doe', '1990-01-01', '1989-01-01', 100000);

-- Removing a CHECK constraint example
ALTER TABLE employees
    DROP CONSTRAINT first_name_check;

-- adding a constraint on a column
ALTER TABLE employees
    ADD CONSTRAINT first_name_check
        CHECK ( LENGTH(TRIM(first_name)) >= 4);

-- This will throw error as expected since here first_name length 2 while expected >= 4
INSERT INTO employees (first_name, last_name, birth_date, joined_date, salary)
VALUES ('Ab', 'Doe', '1990-01-01', '2008-01-01', 100000);

select *
from employees;

-- # UNIQUE
CREATE TABLE person
(
    id         SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    last_name  VARCHAR(50),
    email      VARCHAR(50) UNIQUE
);

INSERT INTO person(first_name, last_name, email)
VALUES ('john', 'doe', 'john@gmail.com');

select *
from person;

-- Creating a UNIQUE constraint on multiple columns (c2, c3 by themselves not needs be unique but when used the combination c2, c3 that combination must be unique)

-- CREATE TABLE table (
--     c1 data_type,
--     c2 data_type,
--     c3 data_type,
--     UNIQUE (c2, c3)
-- );

CREATE TABLE equipment
(
    id       SERIAL PRIMARY KEY,
    name     VARCHAR(50) NOT NULL,
    equip_id VARCHAR(16) NOT NULL
);

-- Step 1: Create a unique index on the `equip_id` column.
CREATE UNIQUE INDEX CONCURRENTLY equipment_equip_id ON equipment (equip_id);

-- This makes the `equip_id` field have a unique constraint.
-- The `CONCURRENTLY` keyword means the index is created without locking the table, so other operations (like inserts or updates) can continue while the index is being built.
-- The unique index ensures that no two rows can have the same `equip_id` value.

-- Step 2: Add a unique constraint to `equip_id`, but reuse the previously created unique index (`equipment_equip_id`).
-- The `USING INDEX` part tells PostgreSQL to use the existing index instead of creating a new one for the unique constraint.

-- N.B: while here it doesn't explicit mention `equip_id` but looking at psql -> "unique_equip_id" UNIQUE CONSTRAINT, btree (equip_id) and since it has already a UNIQUE index thus re-used
-- Reminder: ALTER TABLE statement acquires an exclusive lock on the table. If you have any pending transactions, it will wait for all transactions to complete before changing the table. Therefore, you should check the pg_stat_activity table to see the current pending transactions that are ongoing using the following query:
-- If there are pending transactions on the table, the ALTER TABLE command will wait for those transactions to finish.
-- Once no other operations are blocking the table, the ALTER TABLE operation will acquire the exclusive lock, apply the schema change (like adding the constraint), and then release the lock.
ALTER TABLE equipment
    ADD CONSTRAINT unique_equip_id
        UNIQUE USING INDEX equipment_equip_id;

-- N.B: Here, the `unique_equip_id` constraint reuses the unique index `equipment_equip_id` created in Step 1.
-- It does not create a new index, it simply attaches the constraint to the existing index for uniqueness.

SELECT datid,
       datname,
       usename,
       state
FROM pg_stat_activity;

-- # NOT NULL

CREATE TABLE IF NOT EXISTS invoices
(
    id         SERIAL PRIMARY KEY,
    product_id INT     NOT NULL,
    qty        numeric NOT NULL CHECK (qty > 0),
    net_price  numeric CHECK (net_price > 0)
);

select *
from invoices;


CREATE TABLE production_orders
(
    id          SERIAL PRIMARY KEY,
    description VARCHAR(40) NOT NULL,
    material_id VARCHAR(16),
    qty         NUMERIC,
    start_date  DATE,
    finish_date DATE
);

INSERT INTO production_orders (description)
VALUES ('Make for Infosys inc.');

UPDATE production_orders
SET qty = 1;

ALTER TABLE production_orders
    ALTER COLUMN qty SET NOT NULL;

select *
from production_orders;

UPDATE production_orders
SET material_id = 'ABC',
    start_date  = '2015-09-01',
    finish_date = '2015-09-01';

-- Add not-null constraints to multiple columns:
ALTER TABLE production_orders
    ALTER COLUMN material_id SET NOT NULL,
    ALTER COLUMN start_date SET NOT NULL,
    ALTER COLUMN finish_date SET NOT NULL;

UPDATE production_orders
SET qty = NULL;

-- either email or username could be empty

CREATE TABLE IF NOT EXISTS users_with_constraint_either_username_or_email
(
    id       serial PRIMARY KEY,
    username VARCHAR(50),
    password VARCHAR(50),
    email    VARCHAR(50),
    CONSTRAINT username_email_notnull CHECK (
        NOT (
            (
                username IS NULL
                    OR username = ''
                )
                AND (
                email IS NULL
                    OR email = ''
                )
            )
        )
);

select * from users_with_constraint_either_username_or_email;

INSERT INTO users_with_constraint_either_username_or_email (username, email)
VALUES
	('user1', NULL),
	(NULL, 'some@gmail.com'), -- here username is null or '' but has email so valid
	('user2', 'user2@gmail.com'),
	('user3', ''); -- here username exist but not email but valid as per constraint

select * from users_with_constraint_either_username_or_email;

-- # DEFAULT

CREATE TABLE IF NOT EXISTS logs(
   id SERIAL PRIMARY KEY,
   message TEXT NOT NULL,
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- explicit
INSERT INTO logs(message, created_at) VALUES('Started the server', DEFAULT) RETURNING *;

-- implicit
INSERT INTO logs(message) VALUES('Restarted the server') RETURNING *;

select * from logs;

CREATE TABLE IF NOT EXISTS settings(
   id SERIAL PRIMARY KEY,
   name VARCHAR(50) NOT NULL,
   configuration JSONB DEFAULT '{}'
);

INSERT INTO settings(name) VALUES('global') RETURNING *;

ALTER TABLE settings ALTER COLUMN configuration DROP DEFAULT;

select * from settings;
