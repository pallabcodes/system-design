-- # CASE used to do conditional querying
-- Since CASE is an expression, you can use it in any place where you would use an expression such as SELECT, WHERE, GROUP BY, and HAVING clauses.
-- The CASE expression has two forms: a) General b) Simple

select *
from film;

-- Suppose you want to label the films by their lengths based on the following logic:
-- If the length is less than 50 minutes, the film is short.
-- If the length is greater than 50 minutes and less than or equal to 120 minutes, the film is medium.
-- If the length is greater than 120 minutes, the film is long.
-- To apply this logic, you can use the CASE expression in the SELECT statement as follows:

SELECT film_id,
       title,
       length,
       CASE
           WHEN length > 0
               AND length <= 50 THEN 'Short'
           WHEN length > 50
               AND length <= 120 THEN 'Medium'
           WHEN length > 120 THEN 'Long' END duration
FROM film
ORDER BY title;

-- 1. Using a CASE Statement in a View: This is a general case example
CREATE VIEW film_duration AS
SELECT film_id,
       title,
       length,
       CASE
           WHEN length > 0 AND length <= 50 THEN 'Short'
           WHEN length > 50 AND length <= 120 THEN 'Medium'
           WHEN length > 120 THEN 'Long'
           END AS duration
FROM film
ORDER BY title;

-- with the use of 'aggregate'

SELECT SUM(
               CASE WHEN rental_rate = 0.99 THEN 1 ELSE 0 END
       ) AS "Economy",
       SUM(
               CASE WHEN rental_rate = 2.99 THEN 1 ELSE 0 END
       ) AS "Mass",
       SUM(
               CASE WHEN rental_rate = 4.99 THEN 1 ELSE 0 END
       ) AS "Premium"
FROM film;

SELECT title,
       rating,
       CASE rating
           WHEN 'G' THEN 'General Audiences'
           WHEN 'PG' THEN 'Parental Guidance Suggested'
           WHEN 'PG-13' THEN 'Parents Strongly Cautioned'
           WHEN 'R' THEN 'Restricted'
           WHEN 'NC-17' THEN 'Adults Only'
           END rating_description
FROM film
ORDER BY title;

SELECT SUM(CASE rating WHEN 'G' THEN 1 ELSE 0 END) "General Audiences",
       SUM(
               CASE rating WHEN 'PG' THEN 1 ELSE 0 END
       )                                           "Parental Guidance Suggested",
       SUM(
               CASE rating WHEN 'PG-13' THEN 1 ELSE 0 END
       )                                           "Parents Strongly Cautioned",
       SUM(CASE rating WHEN 'R' THEN 1 ELSE 0 END) "Restricted",
       SUM(
               CASE rating WHEN 'NC-17' THEN 1 ELSE 0 END
       )                                           "Adults Only"
FROM film;

select *
from film_duration;

-- 2. Using a Lookup Table for Segmentation:

CREATE TABLE IF NOT EXISTS film_duration_segment
(
    id         SERIAL PRIMARY KEY,
    min_length INT         NOT NULL,
    max_length INT         NOT NULL,
    category   VARCHAR(50) NOT NULL
);

INSERT INTO film_duration_segment (min_length, max_length, category)
VALUES (1, 50, 'Short'),
       (51, 120, 'Medium'),
       (121, NULL, 'Long');

SELECT f.film_id,
       f.title,
       f.length,
       COALESCE(s.category, 'Unknown') AS duration
FROM film f
         LEFT JOIN film_duration_segment s
                   ON f.length BETWEEN s.min_length AND COALESCE(s.max_length, f.length)
ORDER BY f.title;

--
CREATE TABLE IF NOT EXISTS inventory_items
(
    item_id     SERIAL PRIMARY KEY,
    item_name   VARCHAR(255)   NOT NULL,
    price       NUMERIC(10, 2) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    category_id INTEGER        NOT NULL
);

INSERT INTO inventory_items (item_name, price, category_id)
VALUES ('Laptop', 999.99, 1),
       ('Phone', 599.99, 2),
       ('Mouse', 25.50, 3),
       ('Keyboard', 75.00, 3),
       ('Headphones', 150.75, 4),
       ('Monitor', 250.00, 5);

select *
from inventory_items;

-- Using a View to create the conditional query
CREATE VIEW item_price_category AS
SELECT item_id,
       item_name,
       price,
       CASE
           WHEN price <= 50 THEN 'Low'
           WHEN price > 50 AND price <= 200 THEN 'Medium'
           WHEN price > 200 THEN 'High'
           END AS price_category
FROM public.inventory_items
ORDER BY item_name;

select *
from item_price_category;
-- SELECT * FROM public.item_price_category; public is schema name and it is just optional

-- 4. Using a Lookup Table for Price Categories
CREATE TABLE IF NOT EXISTS price_categories
(
    category_id   SERIAL PRIMARY KEY,
    min_price     NUMERIC(10, 2) NOT NULL,
    max_price     NUMERIC(10, 2) NOT NULL,
    category_name VARCHAR(50)    NOT NULL
);

-- Insert Price Category Data
INSERT INTO price_categories (min_price, max_price, category_name)
VALUES (0, 50, 'Low'),
       (51, 200, 'Medium'),
       (201, 9999, 'High');

SELECT i.item_id,
       i.item_name,
       i.price,
       pc.category_name AS price_category
FROM public.inventory_items i
         LEFT JOIN public.price_categories pc
                   ON i.price BETWEEN pc.min_price AND pc.max_price
ORDER BY i.item_name;

-- Create the partitioned version of the inventory_items table
-- Step 1: Create the Partitioned Table with price in the Primary Key
CREATE TABLE IF NOT EXISTS inventory_items_new
(
    item_id     SERIAL,
    item_name   VARCHAR(255)   NOT NULL,
    price       NUMERIC(10, 2) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    category_id INTEGER        NOT NULL,
    CONSTRAINT inventory_items_new_pkey PRIMARY KEY (item_id, price) -- include price in the primary key
) PARTITION BY RANGE (price);

-- Partition for items with price between 0 and 50
-- Step 2: Create Partitions: Now, you can create the partitions as before, using the price column to define the ranges:

-- Partition for items with price between 0 and 50
CREATE TABLE inventory_items_low PARTITION OF public.inventory_items_new
    FOR VALUES FROM (0) TO (50);

-- Partition for items with price between 50 and 200
CREATE TABLE inventory_items_medium PARTITION OF public.inventory_items_new
    FOR VALUES FROM (50) TO (200);

-- Partition for items with price greater than 200
CREATE TABLE inventory_items_high PARTITION OF public.inventory_items_new
    FOR VALUES FROM (200) TO (MAXVALUE);

-- Step 3: Copy Data from the Old Table to the New Table
-- After creating the partitions, you can proceed to copy the data from the old inventory_items table to the new partitioned table:
INSERT INTO inventory_items_new (item_id, item_name, price, created_at, category_id)
SELECT item_id, item_name, price, created_at, category_id
FROM public.inventory_items;

-- Step 4: Drop the Old Table and Rename the New One

-- Drop the old table
DROP TABLE if exists inventory_items cascade;

-- Rename the new partitioned table to the original name
-- ALTER TABLE public.inventory_items_new RENAME TO inventory_items;

-- Step 5: Query the Partitioned Table
-- You can now query the partitioned inventory_items table, and PostgreSQL will automatically route queries to the appropriate partition:

SELECT *
FROM inventory_items
WHERE price BETWEEN 50 AND 200;
-- Working

-- # COALESCE: it returns the first non-null argument or value

SELECT COALESCE(1, 2);
SELECT COALESCE(null, 2, 1);

CREATE TABLE IF NOT EXISTS items
(
    id       SERIAL PRIMARY KEY,
    product  VARCHAR(100) NOT NULL,
    price    NUMERIC      NOT NULL,
    discount NUMERIC
);

INSERT INTO items (product, price, discount)
VALUES ('A', 1000, 10),
       ('B', 1500, 20),
       ('C', 800, 5),
       ('D', 500, NULL);


select *
from items;
-- so, here product 'D' has discount none i.e. NULL

-- Third, retrieve the net prices of the products from the items table: so when querying for product 'D' which has discount null so when done (price - discount) AS net_price it gets null which is wrong

SELECT product, (price - discount) AS net_price
FROM items;

-- SOLUTION : IN CASE OF DISCOUNT IS NULL THEN ASSUME IT AS 0 LIKE BELOW

SELECT product,
       (
           price - COALESCE(discount, 0) -- so COALESCE allows to have a "fallback value in the correct datatype" to do the calculation here
           ) AS net_price
FROM items;

-- IS NULL
-- SELECT CASE WHEN expression IS NULL THEN replacement ELSE expressionEND AS column_alias;

-- NULLIF: The NULLIF function returns a null value if argument_1 equals to argument_2, otherwise, it returns argument_1.

SELECT NULLIF(1, 1); -- return NULL
SELECT NULLIF(1, 2); -- return 1

CREATE TABLE posts (
  id serial primary key,
  title VARCHAR (255) NOT NULL,
  excerpt VARCHAR (150),
  body TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

INSERT INTO posts (title, excerpt, body)
VALUES
      ('test post 1','test post excerpt 1','test post body 1'),
      ('test post 2','','test post body 2'),
      ('test post 3', null ,'test post body 3')
RETURNING *;

select * from posts;

-- The goal is to retrieve data for displaying them on the post overview page that includes the title and excerpt of each post. To achieve this, you can use the first 40 characters of the post body as the excerpt.
-- Third, use the COALESCE function to handle NULL in the body column:

SELECT
  id,
  title,
  COALESCE (
    excerpt, -- N.B: while it will work if excerpt has "EXPLICITLY" null but in case the column has (implicitly / explicit) empty then it will not correctly
    LEFT(body, 40) -- fallback value so if excerpt doesn't exist then take 40 characters from 'body'
  )
FROM
  posts;

-- FIX with the NULLIF
SELECT
  id,
  title,
  COALESCE (
    NULLIF (excerpt, ''), -- so now it will check for NULL as well as empty value and if either is true then go to fallback value below which is why now it works
    LEFT (body, 40)
  )
FROM
  posts;

CREATE TABLE members (
  id serial PRIMARY KEY,
  first_name VARCHAR (50) NOT NULL,
  last_name VARCHAR (50) NOT NULL,
  gender SMALLINT NOT NULL -- 1: male, 2 female
);

INSERT INTO members (first_name, last_name, gender)
VALUES
  ('John', 'Doe', 1),
  ('David', 'Dave', 1),
  ('Bush', 'Lily', 2)
RETURNING *;

SELECT
  (
    SUM (CASE WHEN gender = 1 THEN 1 ELSE 0 END) / SUM (CASE WHEN gender = 2 THEN 1 ELSE 0 END)
  ) * 100 AS "Male/Female ratio"
FROM
  members;

DELETE FROM members WHERE gender = 2;

SELECT
  (
    SUM (CASE WHEN gender = 1 THEN 1 ELSE 0 END) / NULLIF (
      SUM (CASE WHEN gender = 2 THEN 1 ELSE 0 END),
      0
    )
  ) * 100 AS "Male/Female ratio"
FROM
  members;


-- # CAST: convert one value to another
SELECT
   CAST('true' AS BOOLEAN),
   CAST('false' as BOOLEAN),
   CAST('T' as BOOLEAN),
   CAST('F' as BOOLEAN);

SELECT '2019-06-15 14:30:20'::timestamp; -- DATETIME

SELECT '2019-06-15 14:30:20'::timestamptz; -- DATETIME with the timezone

SELECT
  '15 minute' :: interval,
  '2 hour' :: interval,
  '1 day' :: interval,
  '2 week' :: interval,
  '3 month' :: interval;

SELECT CAST('2024-02-01 12:34:56' AS DATE);

SELECT CAST('30 days' AS TEXT);

SELECT CAST('{"name": "John"}' AS JSONB);

SELECT CAST(9.99 AS INTEGER);

SELECT CAST(ARRAY[1, 2, 3] AS TEXT);

SELECT '{1,2,3}'::INTEGER[] AS result_array;

CREATE TABLE ratings (
  id SERIAL PRIMARY KEY,
  rating VARCHAR (1) NOT NULL
);

INSERT INTO ratings (rating)
VALUES
  ('A'),
  ('B'),
  ('C');

INSERT INTO ratings (rating)
VALUES
  (1),
  (2),
  (3);

SELECT * FROM ratings;

-- Now, we have to convert all values in the rating column into integers, all other A, B, C ratings will be displayed as zero.
SELECT id, CASE WHEN rating~E'^\\d+$' THEN CAST (rating AS INTEGER) ELSE 0 END as rating FROM ratings;