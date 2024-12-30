-- A bunch of helpful functions provided by PostgreSQL

SELECT ROUND(AVG(replacement_cost), 2) avg_replacement_cost
FROM film;

SELECT ROUND(AVG(replacement_cost), 2) avg_replacement_cost
FROM film
         INNER JOIN film_category USING (film_id)
         INNER JOIN category USING (category_id)
WHERE category_id = 7;

SELECT
  COUNT(*)
FROM
  film;

SELECT
  COUNT(*) drama_films
FROM
  film
  INNER JOIN film_category USING(film_id)
  INNER JOIN category USING(category_id)
WHERE
  category_id = 7;

SELECT
  MAX(replacement_cost)
FROM
  film;

SELECT
  film_id,
  title
FROM
  film
WHERE
  replacement_cost =(
    SELECT
      MAX(replacement_cost)
    FROM
      film
  )
ORDER BY
  title;

SELECT
  MIN(replacement_cost)
FROM
  film;

SELECT
  film_id,
  title
FROM
  film
WHERE
  replacement_cost =(
    SELECT
      MIN(replacement_cost)
    FROM
      film
  )
ORDER BY
  title;

SELECT
  rating,
  SUM(rental_duration)
FROM
  film
GROUP BY
  rating
ORDER BY
  rating;

-- ## AVG
SELECT AVG(amount)
FROM payment;

SELECT AVG(amount)::numeric(10,2)
FROM payment;

SELECT AVG(DISTINCT amount)::numeric(10,2)
FROM payment;

SELECT
	AVG(amount)::numeric(10,2),
	SUM(amount)::numeric(10,2)
FROM
	payment;

-- HAS ISSUE
SELECT
  customer_id,
  first_name,
  last_name,
  AVG (amount):: NUMERIC(10, 2)
FROM
  payment
  INNER JOIN customer USING(customer_id)
GROUP BY
  customer_id
ORDER BY
  customer_id;

-- has issue
SELECT
  customer_id,
  first_name,
  last_name,
  AVG (amount):: NUMERIC(10, 2)
FROM
  payment
  INNER JOIN customer USING(customer_id)
GROUP BY
  customer_id
HAVING
  AVG (amount) > 5
ORDER BY
  customer_id;

SELECT
  customer_id,
  COUNT (customer_id)
FROM
  payment
GROUP BY
  customer_id;

-- HAS ISSUE
SELECT
  first_name || ' ' || last_name full_name,
  COUNT (customer_id)
FROM
  payment
INNER JOIN customer USING (customer_id)
GROUP BY
  customer_id;

-- HAS ISSUE
SELECT
  first_name || ' ' || last_name full_name,
  COUNT (customer_id)
FROM
  payment
INNER JOIN customer USING (customer_id)
GROUP BY
  customer_id
HAVING
  COUNT (customer_id) > 40

SELECT
  payment_id,
  customer_id,
  amount
FROM
  payment
WHERE
  amount = (
    SELECT
      MAX (amount)
    FROM
      payment
  );

SELECT
  customer_id,
  MAX (amount)
FROM
  payment
GROUP BY
  customer_id;

SELECT
  customer_id,
  MAX (amount)
FROM
  payment
GROUP BY
  customer_id
HAVING
  MAX(amount) > 8.99;

SELECT
  film_id,
  title,
  rental_rate
FROM
  film
WHERE
  rental_rate = (
    SELECT
      MIN(rental_rate)
    FROM
      film
  );

-- HAS ISSUE
SELECT
  name category,
  MIN(replacement_cost) replacement_cost
FROM
  category
  INNER JOIN film_category USING (category_id)
  INNER JOIN film USING (film_id)
GROUP BY
  name
ORDER BY
  name;

-- HAS ISSUE
SELECT
  name category,
  MIN(replacement_cost) replacement_cost
FROM
  category
  INNER JOIN film_category USING (category_id)
  INNER JOIN film USING (film_id)
GROUP BY
  name
HAVING
  MIN(replacement_cost) > 9.99
ORDER BY
  name;

-- HAS ISSUE
SELECT
  name category, -- field = name, alias = category
  MIN(length) min_length,
  MAX(length) max_length
FROM
  category
  INNER JOIN film_category USING (category_id)
  INNER JOIN film USING (film_id)
GROUP BY
  name
ORDER BY
  name;

select *
from categories;

SELECT
  SUM(amount)
FROM
  payment;

SELECT
  SUM (amount)
FROM
  payment
WHERE
  customer_id = 2000;

--  If you want the SUM() function to return zero instead of NULL in case there is no matching row, you use the COALESCE() function.

SELECT
  COALESCE(SUM(amount), 0 ) total
FROM
  payment
WHERE
  customer_id = 2000;

SELECT
  customer_id,
  SUM (amount) AS total
FROM
  payment
GROUP BY
  customer_id
ORDER BY
  total;

SELECT
  customer_id,
  SUM (amount) AS total
FROM
  payment
GROUP BY
  customer_id
ORDER BY
  total DESC
LIMIT
  5;

SELECT
  customer_id,
  SUM (amount) AS total
FROM
  payment
GROUP BY
  customer_id
HAVING
  SUM(amount) > 200
ORDER BY
  total DESC;

SELECT
  SUM(return_date - rental_date)
FROM
  rental;

-- HAS ISSUE
SELECT
  first_name || ' ' || last_name full_name,
  SUM(return_date - rental_date) rental_duration
FROM
  rental
  INNER JOIN customer USING(customer_id)
GROUP BY
  customer_id
ORDER BY
  full_name;


-- The following example uses the ARRAY_AGG() function to return the list of film titles and a list of actors for each film:
SELECT
    title,
    ARRAY_AGG (first_name || ' ' || last_name) actors
FROM
    film
INNER JOIN film_actor USING (film_id)
INNER JOIN actor USING (actor_id)
GROUP BY
    title
ORDER BY
    title;


-- This example uses the ARRAY_AGG() function to return a list of films and a list of actors for each film sorted by the actor’s first name:
SELECT
    title,
    ARRAY_AGG (
        first_name || ' ' || last_name
        ORDER BY
            first_name
    ) actors
FROM
    film
INNER JOIN film_actor USING (film_id)
INNER JOIN actor USING (actor_id)
GROUP BY
    title
ORDER BY
    title;

-- You can sort the actor list for each film by the actor’s first name and last name as shown in the following query:
SELECT
    title,
    ARRAY_AGG (
        first_name || ' ' || last_name
        ORDER BY
            first_name ASC,
            last_name DESC
    ) actors
FROM
    film
INNER JOIN film_actor USING (film_id)
INNER JOIN actor USING (actor_id)
GROUP BY
    title
ORDER BY
    title;

-- BOOL_AND
DROP TABLE IF EXISTS teams, members cascade;

CREATE TABLE IF NOT EXISTS teams (
    team_id SERIAL PRIMARY KEY,
    team_name VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS projects(
    project_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    active BOOL,
    team_id INT NOT NULL REFERENCES teams(team_id)
);

INSERT INTO teams (team_name)
VALUES
('Team A'),
('Team B'),
('Team C')
RETURNING *;

INSERT INTO projects(name, active, team_id)
VALUES
('Intranet', false, 1),
('AI Chatbot', true, 1),
('Robot', true, 2),
('RPA', true, 2),
('Data Analytics', true, 3),
('BI', NULL, 3)
RETURNING *;

--  The following example uses the BOOL_AND() function to test if all projects are active in the projects table:
SELECT
  BOOL_AND(active)
FROM
  projects;

-- The following example uses the BOOL_AND() function with the GROUP BY clause to check if there are active projects in each team:
SELECT
  team_name,
  BOOL_AND(active) active_projects
FROM
  projects
  INNER JOIN teams USING (team_id)
GROUP BY
  team_name;

-- The following example uses the BOOL_AND() function with the GROUP BY and HAVING clauses to retrieve teams that have active projects:
SELECT
  team_name,
  BOOL_AND(active) active_projects
FROM
  projects
  INNER JOIN teams USING (team_id)
GROUP BY
  team_name
HAVING
  BOOL_AND(active) = true;

-- STRING_AGG

-- This example uses the STRING_AGG() function to return a list of actor’s names for each film from the film table:
SELECT
    f.title,
    STRING_AGG (
	a.first_name || ' ' || a.last_name,
        ','
       ORDER BY
        a.first_name,
        a.last_name
    ) actors
FROM
    film f
INNER JOIN film_actor fa USING (film_id)
INNER JOIN actor a USING (actor_id)
GROUP BY
    f.title;

-- The following example uses the STRING_AGG() function to build an email list for each country, with emails separated by semicolons:
SELECT
    country,
    STRING_AGG (email, ';') email_list
FROM
    customer
INNER JOIN address USING (address_id)
INNER JOIN city USING (city_id)
INNER JOIN country USING (country_id)
GROUP BY
    country
ORDER BY
    country;

-- BOOL_OR
DROP TABLE IF EXISTS teams, members cascade;

CREATE TABLE teams (
    team_id SERIAL PRIMARY KEY,
    team_name VARCHAR(100) NOT NULL
);

CREATE TABLE members (
    member_id SERIAL PRIMARY KEY,
    member_name VARCHAR(100) NOT NULL,
    active bool,
    team_id INT REFERENCES teams(team_id)
);

INSERT INTO teams (team_name)
VALUES
('Team A'),
('Team B'),
('Team C')
RETURNING *;

INSERT INTO members (member_name, team_id, active)
VALUES
('Alice', 1, true),
('Bob', 2, true),
('Charlie', 1, null),
('David', 2, false),
('Peter', 3, false),
('Joe', 3, null)
RETURNING *;

-- The following example uses the BOOL_OR() function to test if there are any active members in the members table:
SELECT
  BOOL_OR(active) active_member_exists
FROM
  members;

-- The following example uses the BOOL_OR() function with the GROUP BY clause to check if there are any active members in each team:
SELECT
  team_name,
  BOOL_OR(active) active_member_exists
FROM
  members
  INNER JOIN teams USING (team_id)
GROUP BY
  team_name;

-- The following example uses the BOOL_OR() function with the GROUP BY and HAVING clauses to retrieve teams that have active members:

SELECT
  team_name,
  BOOL_OR(active) active_member_exists
FROM
  members
  INNER JOIN teams USING (team_id)
GROUP BY
  team_name
HAVING
  BOOL_OR(active) = true;

-- DATE FUNCTIONS
SELECT CURRENT_DATE;

-- retrieve the rentals placed today by using the rental date = CURRENT_DATE
SELECT
  *
FROM
  rental
WHERE
  rental_date = CURRENT_DATE;

DROP TABLE IF EXISTS rental, employees cascade;

CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL
);
INSERT INTO employees (name, date_of_birth)
VALUES
    ('John Doe', '1992-05-15'),
    ('Jane Smith', '1995-08-22'),
    ('Bob Johnson', '1998-11-10')
RETURNING *;


SELECT
  name,
  date_of_birth,
  CURRENT_DATE as today,
  (CURRENT_DATE - date_of_birth) / 365 AS age
FROM
  employees
ORDER BY
  name;

CREATE TABLE delivery(
  delivery_id SERIAL PRIMARY KEY,
  product VARCHAR(255) NOT NULL,
  delivery_date DATE DEFAULT CURRENT_DATE
);

INSERT INTO delivery(product)
VALUES
  ('Sample screen protector');

select *
from delivery;

SELECT CURRENT_TIME;
SELECT CURRENT_TIME(2);

CREATE TABLE log (
    id SERIAL PRIMARY KEY,
    message VARCHAR(255) NOT NULL,
    created_at TIME DEFAULT CURRENT_TIME,
    created_on DATE DEFAULT CURRENT_DATE
);

INSERT INTO log( message )
VALUES('Testing the CURRENT_TIME function');

select *
from log;

CREATE TABLE note (
    id SERIAL PRIMARY KEY,
    message VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO note(message)
VALUES('Testing current_timestamp function');

select *
from note;

select clock_timestamp();

SELECT
  clock_timestamp(),
  pg_sleep(3),
  clock_timestamp(),
  pg_sleep(3),
  clock_timestamp();

-- Using the CLOCK_TIMESTAMP() function to measure the execution time of a statement
CREATE OR REPLACE FUNCTION time_it(
    p_statement TEXT
) RETURNS NUMERIC AS $$
DECLARE
    start_time TIMESTAMP WITH TIME ZONE;
    end_time TIMESTAMP WITH TIME ZONE;
    execution_time NUMERIC; -- ms
BEGIN
    -- Capture start time
    start_time := CLOCK_TIMESTAMP();

    -- Execute the statement
    EXECUTE p_statement;

    -- Capture end time
    end_time := CLOCK_TIMESTAMP();

    -- Calculate execution time in milliseconds
    execution_time := EXTRACT(EPOCH FROM end_time - start_time) * 1000;

    RETURN execution_time;
END;
$$ LANGUAGE plpgsql;

-- use the time_it() function to measure the execution time of the statement that uses the pg_sleep() function:
SELECT time_it('SELECT pg_sleep(1)'); -- it takes almost 1000ms / 1s

select statement_timestamp();

DROP TABLE IF EXISTS logs;

-- start a transaction
BEGIN;
INSERT INTO logs(message, created_at) VALUES('Testing before production', statement_timestamp());
SELECT pg_sleep(3);
INSERT INTO logs(message, created_at) VALUES('bug fixes',statement_timestamp());
SELECT pg_sleep(3);
INSERT INTO logs(message, created_at) VALUES('new module', statement_timestamp());
END;

-- ABORT transaction; -- to abort any ongoing transaction

-- retrieve data from the log table
SELECT * FROM logs where created_at::date = current_date;




-- WINDOW FUNCTIONS

DROP TABLE IF EXISTS products, product_groups cascade;

CREATE TABLE product_groups (
	group_id serial PRIMARY KEY,
	group_name VARCHAR (255) NOT NULL
);

CREATE TABLE products (
	product_id serial PRIMARY KEY,
	product_name VARCHAR (255) NOT NULL,
	price DECIMAL (11, 2),
	group_id INT NOT NULL,
	FOREIGN KEY (group_id) REFERENCES product_groups (group_id)
);

INSERT INTO product_groups (group_name)
VALUES
	('Smartphone'),
	('Laptop'),
	('Tablet');

INSERT INTO products (product_name, group_id,price)
VALUES
	('Microsoft Lumia', 1, 200),
	('HTC One', 1, 400),
	('Nexus', 1, 500),
	('iPhone', 1, 900),
	('HP Elite', 2, 1200),
	('Lenovo Thinkpad', 2, 700),
	('Sony VAIO', 2, 700),
	('Dell Vostro', 2, 800),
	('iPad', 3, 700),
	('Kindle Fire', 3, 150),
	('Samsung Galaxy Tab', 3, 200);

select *
from products;

SELECT
	group_name,
	AVG (price)
FROM
	products
INNER JOIN product_groups USING (group_id)
GROUP BY
	group_name;

-- Similar to an aggregate function, a window function operates on a set of rows. However, it does not reduce the number of rows returned by the query.
-- The term window describes the set of rows on which the window function operates. A window function returns values from the rows in a window.

-- PostgreSQL window function List
-- The following table lists all window functions provided by PostgreSQL.
-- N.B: some aggregate functions such as AVG(), MIN(), MAX(), SUM(), and COUNT() can be also used as window functions.
--
-- CUME_DIST	Return the relative rank of the current row.
-- DENSE_RANK	Rank the current row within its partition without gaps.
-- FIRST_VALUE	Return a value evaluated against the first row within its partition.
-- LAG	Return a value evaluated at the row that is at a specified physical offset row before the current row within the partition.
-- LAST_VALUE	Return a value evaluated against the last row within its partition.
-- LEAD	Return a value evaluated at the row that is offset rows after the current row within the partition.
-- NTILE	Divide rows in a partition as equally as possible and assign each row an integer starting from 1 to the argument value.
-- NTH_VALUE	Return a value evaluated against the nth row in an ordered partition.
-- PERCENT_RANK	Return the relative rank of the current row (rank-1) / (total rows – 1)
-- RANK	Rank the current row within its partition with gaps.
-- ROW_NUMBER	Number the current row within its partition starting from 1.

SELECT
	product_name,
	price,
	group_name,
	-- In this query, the AVG() function works as a window function that operates on a set of rows specified by the OVER clause. Each set of rows is called a window.
	-- syntax of window function -> AVG(price) OVER (PARTITION BY group_name)
	AVG (price) OVER (
	   PARTITION BY group_name
	)
FROM
	products
	INNER JOIN
		product_groups USING (group_id);

SELECT
	product_name,
	group_name,
	price,
	ROW_NUMBER () OVER (
		PARTITION BY group_name
		ORDER BY
			price
	)
FROM
	products
INNER JOIN product_groups USING (group_id);

SELECT
	product_name,
	group_name,
  price,
	RANK () OVER (
		PARTITION BY group_name
		ORDER BY
			price
	)
FROM
	products
INNER JOIN product_groups USING (group_id);

SELECT
	product_name,
	group_name,
	price,
	DENSE_RANK () OVER (
		PARTITION BY group_name
		ORDER BY
			price
	)
FROM
	products
INNER JOIN product_groups USING (group_id);


-- The following statement uses the FIRST_VALUE() to return the lowest price for every product group.
SELECT
	product_name,
	group_name,
	price,
	FIRST_VALUE (price) OVER (
		PARTITION BY group_name
		ORDER BY
			price
	) AS lowest_price_per_group
FROM
	products
INNER JOIN product_groups USING (group_id);

-- The following statement uses the LAST_VALUE() function to return the highest price for every product group.

SELECT
	product_name,
	group_name,
	price,
	LAST_VALUE (price) OVER (
		PARTITION BY group_name
		ORDER BY
			price RANGE BETWEEN UNBOUNDED PRECEDING
		AND UNBOUNDED FOLLOWING
	) AS highest_price_per_group
FROM
	products
INNER JOIN product_groups USING (group_id);

-- The following statement uses the LAG() function to return the prices from the previous row and calculates the difference between the price of the current row and the previous row.

SELECT
	product_name,
	group_name,
	price,
	LAG (price, 1) OVER (
		PARTITION BY group_name
		ORDER BY
			price
	) AS prev_price,
	price - LAG (price, 1) OVER (
		PARTITION BY group_name
		ORDER BY
			price
	) AS cur_prev_diff
FROM
	products
INNER JOIN product_groups USING (group_id);

-- The following statement uses the LEAD() function to return the prices from the next row and calculates the difference between the price of the current row and the next row.

SELECT
	product_name,
	group_name,
	price,
	LEAD (price, 1) OVER (
		PARTITION BY group_name
		ORDER BY
			price
	) AS next_price,
	price - LEAD (price, 1) OVER (
		PARTITION BY group_name
		ORDER BY
			price
	) AS cur_next_diff
FROM
	products
INNER JOIN product_groups USING (group_id);