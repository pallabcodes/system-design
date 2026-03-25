CREATE TABLE IF NOT EXISTS users
(
    user_id     BIGSERIAL PRIMARY KEY,                 -- Auto-incrementing primary key (datatype: BIGINT)
    username    VARCHAR(255) NOT NULL UNIQUE,          -- Username, must be unique
    email       VARCHAR(255) NOT NULL UNIQUE,          -- Email address, must be unique
    password    VARCHAR(50)  NOT NULL,
    is_active   BOOLEAN     DEFAULT TRUE,              -- Status if the user account is active or not
    created_at  TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP, -- Account creation timestamp
    updated_at  TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP, -- Timestamp for the last update of the account
    last_login  TIMESTAMPTZ,                           -- Timestamp for the last login time
    preferences JSONB,                                 -- Optional: Stores user preferences like notifications, themes, etc.
    is_deleted  BOOLEAN     DEFAULT FALSE              -- Mark user as deleted without removing from the DB
);

CREATE SEQUENCE role_id_seq START 1;

CREATE TABLE IF NOT EXISTS roles
(
    role_id     INTEGER PRIMARY KEY DEFAULT nextval('role_id_seq'),
    role_name   VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

INSERT INTO roles (role_name, description)
VALUES ('Guest', 'Editor role');

select *
from roles;

-- Create the 'film' table
CREATE TABLE IF NOT EXISTS film
(
    film_id          SERIAL PRIMARY KEY,
    title            VARCHAR(255) NOT NULL,
    description      TEXT,
    release_year     INT,
    language_id      INT          NOT NULL,
    rental_duration  INT           DEFAULT 3,
    rental_rate      NUMERIC(4, 2) DEFAULT 4.99,
    length           INT,
    replacement_cost NUMERIC(5, 2) DEFAULT 19.99,
    rating           VARCHAR(10),
    last_update      TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    special_features TEXT[],
    fulltext         TSVECTOR
);

-- Insert 5 rows of sample data
INSERT INTO film (title, description, release_year, language_id, length, rating)
VALUES
    ('Action Movie 1', 'An action-packed thriller', 2020, 1, 120, 'PG-13'),
    ('Comedy Movie 1', 'A fun and lighthearted comedy', 2021, 1, 90, 'PG'),
    ('Drama Movie 1', 'A serious and emotional drama', 2019, 2, 130, 'R'),
    ('Horror Movie 1', 'A spine-chilling horror film', 2022, 1, 100, 'R'),
    ('Romance Movie 1', 'A touching love story', 2023, 3, 110, 'PG-13');

-- Update each row with a random length between 80 and 180
-- update film SET length = FLOOR(80 + (random() * 101));

-- select all from film
select film_id, title, rating, length from film;

-- SELECT from an existing table (film) and insert into a new table (film_pg)
SELECT film_id,
       title,
       rental_rate
INTO TABLE film_pg
FROM film
WHERE rating = 'PG-13'
  AND rental_duration = 5
ORDER BY title;

-- select all from film_pg
select * from film_pg;

-- SELECT from an existing table (film) and insert into a new table (short_film)
select film_id, title, rating, length
into TEMP TABLE short_film
from film
where rating = 'PG-13'
  AND length >= 80
order by title;

-- N.B: The columns of the new table will have the names and data types associated with the output columns of the SELECT clause.
-- SELECT from an existing table (film) and insert into a new table (short_film) along with `new custom (createdAt, updatedAt) fields and computed fields (length_category)`

SELECT film_id           AS short_film_id,
       title,
       rating,
       length,
       CASE
           WHEN length < 90 THEN 'Short'
           WHEN length BETWEEN 90 AND 120 THEN 'Medium'
           ELSE 'Long'
           END           AS length_category,
       CURRENT_TIMESTAMP AS createdAt,
       CURRENT_TIMESTAMP AS updatedAt
INTO TEMP TABLE short_film
FROM film
WHERE rating = 'PG-13'
  AND length >= 80
ORDER BY title;


-- select all from short_film
select * from short_film order by length desc;

-- drop table if exists short_film cascade;

-- actor – stores actor data including first name and last name.
-- film – stores film data such as title, release year, length, rating, etc.
-- film_actor – stores the relationships between films and actors.
-- category – stores film’s categories data.
-- film_category- stores the relationships between films and categories.

CREATE TABLE IF NOT EXISTS category
(
    category_id SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE
);

INSERT INTO category (name)
VALUES
    ('Action'),
    ('Comedy'),
    ('Drama'),
    ('Horror'),
    ('Romance');


select * from category;

-- remove all rows from the category table
-- TRUNCATE TABLE category CASCADE;

-- Junction table to store the relationship between films and categories
CREATE TABLE IF NOT EXISTS film_category (
    film_id INT REFERENCES film(film_id) ON DELETE CASCADE,
    category_id INT REFERENCES category(category_id) ON DELETE CASCADE,
    PRIMARY KEY (film_id, category_id) -- Composite primary key
);

-- Action Movie 1 is Action and Comedy
INSERT INTO film_category (film_id, category_id) VALUES (1, 1);  -- Action Movie 1 -> Action (1, 2);  -- Action Movie 1 -> Comedy

-- Comedy Movie 1 is Comedy
INSERT INTO film_category (film_id, category_id) VALUES (2, 2);  -- Comedy Movie 1 -> Comedy

-- Drama Movie 1 is Drama and Action
INSERT INTO film_category (film_id, category_id) VALUES (3, 3);  -- Drama Movie 1 -> Drama (3, 1);  -- Drama Movie 1 -> Action

-- Horror Movie 1 is Horror
INSERT INTO film_category (film_id, category_id) VALUES (4, 4);  -- Horror Movie 1 -> Horror

-- Romance Movie 1 is Romance
INSERT INTO film_category (film_id, category_id) VALUES (5, 5);  -- Romance Movie 1 -> Romance

-- The new table i.e. action_film will be created with selected columns with their datatypes so here (action_film_id, title, release_year, length and rating)
CREATE TABLE IF NOT EXISTS action_film
AS
SELECT
    film_id AS action_film_id,
    title,
    release_year,
    length,
    rating
FROM
    film
INNER JOIN film_category USING (film_id)
WHERE
    category_id = 1;

select * from action_film order by title;

-- now, querying to find films with their categories through the junction table i.e. film_category as below
SELECT f.title, c.name
FROM film f
INNER JOIN film_category fc ON f.film_id = fc.film_id
INNER JOIN category c ON fc.category_id = c.category_id;

CREATE TABLE IF NOT EXISTS film_rating (rating, film_count)
AS
SELECT
    rating,
    COUNT (film_id)
FROM
    film
GROUP BY
    rating;

select * from film_rating;



-- store – contains the store data including manager staff and address.
-- inventory – stores inventory data.
-- rental – stores rental data.
-- payment – stores customer’s payments.
-- staff – stores staff data.
-- customer – stores customer data.
-- address – stores address data for staff and customers
-- city – stores city names.
-- country – stores country names.

CREATE TABLE IF NOT EXISTS color (
    color_id INT GENERATED ALWAYS AS IDENTITY, -- it is a newer syntax that does the same as SERIAL
    color_name VARCHAR NOT NULL
);

-- color_id is defined as an identity column with the GENERATED ALWAYS AS IDENTITY syntax,
-- meaning PostgreSQL will automatically generate a value for this column when a new row is inserted.

-- N.B: If you want to insert values manually into the color_id column but still allow automatic generation when not specified, you can use GENERATED BY DEFAULT instead of GENERATED ALWAYS:

INSERT INTO color(color_name) VALUES ('Blue'), ('Green'), ('Red');

-- You cannot explicitly insert a value into this column unless you override this behavior like below.
INSERT INTO color (color_id, color_name)
OVERRIDING SYSTEM VALUE
VALUES(10, 'Orange');

-- Check if the value 10 already exists in the table
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM color WHERE color_id = 10) THEN
        INSERT INTO color(color_id, color_name)
        OVERRIDING SYSTEM VALUE
        VALUES(10, 'Orange');
    ELSE
        -- Raising an exception with a custom error message
        RAISE EXCEPTION 'The color_id 10 already exists. Insertion not allowed.';
    END IF;
END $$;

-- Check if the value 10 already exists in the table (alternative without raising exception)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM color WHERE color_id = 10) THEN
        INSERT INTO color(color_id, color_name)
        OVERRIDING SYSTEM VALUE
        VALUES(10, 'Orange');
        RAISE NOTICE 'Insertion successful: color_id 10 inserted.';
    ELSE
        RAISE NOTICE 'Insertion failed: color_id 10 already exists.';
    END IF;
END $$;



SELECT * FROM color;

CREATE TABLE color2 (
    color_id INT GENERATED BY DEFAULT AS IDENTITY, -- it is a newer syntax that does the same as SERIAL
    color_name VARCHAR NOT NULL
);

INSERT INTO color2(color_name) VALUES ('Red'), ('Green'), ('Blue');
INSERT INTO color2(color_id, color_name) VALUES (10, 'Orange');

select * from color2;