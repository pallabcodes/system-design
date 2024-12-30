-- # Common Table Expression (CTE) : A common table expression (CTE) allows you to create a temporary result set within a query.
-- N.B: A CTE helps you enhance the readability of a complex query by breaking it down into smaller and more reusable parts

-- WITH cte_name (column1, column2, ...) AS (
--     -- CTE query
--     SELECT ...
-- )
-- -- Main query using the CTE
-- SELECT ...
-- FROM cte_name;

-- in this syntax:

-- WITH clause: Introduce the common table expression (CTE). It is followed by the name of the CTE and a list of column names in parentheses. The column list is optional and is only necessary if you want to explicitly define the columns for the CTE.
-- CTE name: Specify the name of the CTE. The CTE name exists within the scope of the query. Ensure that the CTE name is unique within the query.
-- Column List (optional): Specify the list of column names within the parentheses after the CTE name. If not specified, the columns implicitly inherit the column names from SELECT statement inside the CTE.
-- AS keyword: The AS keyword indicates the beginning of the CTE definition.
-- CTE query: This is a query that defines the CTE, which may include JOINs, WHERE, GROUP BY clauses, and other valid SQL constructs.
-- Main query: After defining the CTE, you can reference it in the main query by its name. In the main query, you can use the CTE as if it were a regular table, simplifying the structure of complex queries.


-- 1) Basic PostgreSQL common table expression example
WITH action_films AS (
  SELECT
    f.title,
    f.length
  FROM
    film f
    INNER JOIN film_category fc USING (film_id)
    INNER JOIN category c USING(category_id)
  WHERE
    c.name = 'Action'
)
SELECT * FROM action_films;

-- 2) Join a CTE with a table example

WITH cte_rental AS (
  SELECT
    staff_id,
    COUNT(rental_id) rental_count
  FROM
    rental
  GROUP BY
    staff_id
)
SELECT
  s.staff_id,
  first_name,
  last_name,
  rental_count
FROM
  staff s
  INNER JOIN cte_rental USING (staff_id); -- Here, used cte_rental as a regular table

-- 3) Multiple CTEs example

WITH film_stats AS (
    -- CTE 1: Calculate film statistics
    SELECT
        AVG(rental_rate) AS avg_rental_rate,
        MAX(length) AS max_length,
        MIN(length) AS min_length
    FROM film
),
customer_stats AS (
    -- CTE 2: Calculate customer statistics
    SELECT
        COUNT(DISTINCT customer_id) AS total_customers,
        SUM(amount) AS total_payments
    FROM payment
)
-- Main query using the CTEs
SELECT
    ROUND((SELECT avg_rental_rate FROM film_stats), 2) AS avg_film_rental_rate,
    (SELECT max_length FROM film_stats) AS max_film_length,
    (SELECT min_length FROM film_stats) AS min_film_length,
    (SELECT total_customers FROM customer_stats) AS total_customers,
    (SELECT total_payments FROM customer_stats) AS total_payments;

-- Use a common table expression (CTE) to create a temporary result set within a query.
-- Leverage CTEs to simplify complex queries and make them more readable.

-- # Recursive CTE : A recursive CTE allows you to perform recursion within a query using the WITH RECURSIVE syntax.

-- WITH RECURSIVE cte AS (
--     SELECT id, follower_count
--     FROM followers
--     WHERE user_id = 1
--     UNION ALL
--     SELECT f.id, f.follower_count
--     FROM followers f
--     JOIN cte ON f.followed_by = cte.id
-- )
-- SELECT * FROM cte;

DROP TABLE IF EXISTS employees cascade;

CREATE TABLE employees (
  employee_id SERIAL PRIMARY KEY,
  full_name VARCHAR NOT NULL,
  manager_id INT
);

INSERT INTO employees (employee_id, full_name, manager_id)
VALUES
  (1, 'Michael North', NULL),
  (2, 'Megan Berry', 1),
  (3, 'Sarah Berry', 1),
  (4, 'Zoe Black', 1),
  (5, 'Tim James', 1),
  (6, 'Bella Tucker', 2),
  (7, 'Ryan Metcalfe', 2),
  (8, 'Max Mills', 2),
  (9, 'Benjamin Glover', 2),
  (10, 'Carolyn Henderson', 3),
  (11, 'Nicola Kelly', 3),
  (12, 'Alexandra Climo', 3),
  (13, 'Dominic King', 3),
  (14, 'Leonard Gray', 4),
  (15, 'Eric Rampling', 4),
  (16, 'Piers Paige', 7),
  (17, 'Ryan Henderson', 7),
  (18, 'Frank Tucker', 8),
  (19, 'Nathan Ferguson', 8),
  (20, 'Kevin Rampling', 8);

-- 2) Basic PostgreSQL recursive query example: the following statement uses a recursive CTE to find all subordinates of the manager with the id 2.

WITH RECURSIVE subordinates AS (
  SELECT
    employee_id,
    manager_id,
    full_name
  FROM
    employees
  WHERE
    employee_id = 2
  UNION
  SELECT
    e.employee_id,
    e.manager_id,
    e.full_name
  FROM
    employees e
    INNER JOIN subordinates s ON s.employee_id = e.manager_id
)
SELECT * FROM subordinates;