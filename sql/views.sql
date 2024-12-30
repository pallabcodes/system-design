-- A view is a named query stored in the PostgreSQL database server. A view is defined based on one or more tables which are known as base tables, and the query that defines the view is referred to as a defining query.
-- N.B: A named query that will periodically refresh from the source or base table

-- Views do not store data except the materialized views. In PostgreSQL, you can create special views called materialized views that store data physically and periodically refresh it from the base tables.
-- The materialized views are handy in various scenarios, providing faster data access to a remote server and serving as an effective caching mechanism.

CREATE TABLE cities
(
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(255),
    population INT,
    country    VARCHAR(50)
);

INSERT INTO cities (name, population, country)
VALUES ('New York', 8419600, 'US'),
       ('Los Angeles', 3999759, 'US'),
       ('Chicago', 2716000, 'US'),
       ('Houston', 2323000, 'US'),
       ('London', 8982000, 'UK'),
       ('Manchester', 547627, 'UK'),
       ('Birmingham', 1141816, 'UK'),
       ('Glasgow', 633120, 'UK'),
       ('San Francisco', 884363, 'US'),
       ('Seattle', 744955, 'US'),
       ('Liverpool', 498042, 'UK'),
       ('Leeds', 789194, 'UK'),
       ('Austin', 978908, 'US'),
       ('Boston', 694583, 'US'),
       ('Manchester', 547627, 'UK'),
       ('Sheffield', 584853, 'UK'),
       ('Philadelphia', 1584138, 'US'),
       ('Phoenix', 1680992, 'US'),
       ('Bristol', 463377, 'UK'),
       ('Detroit', 673104, 'US');

SELECT *
FROM cities;

-- 1) Creating an updatable but the FROM clause can reference only a single table or another updatable view as below
CREATE VIEW city_us
AS
SELECT *
FROM cities
WHERE country = 'US';

select *
from city_us;

INSERT INTO city_us(name, population, country)
VALUES ('San Jose', 983459, 'US');

SELECT *
FROM cities
WHERE name = 'San Jose';
SELECT *
FROM city_us
WHERE name = 'San Jose';

UPDATE city_us
SET population = 1000000
WHERE name = 'New York';

SELECT *
FROM cities
WHERE name = 'New York';

DELETE
FROM city_us
WHERE id = 21;

SELECT *
FROM cities
WHERE id = 21;

-- since this view uses join so when it comes to update postgresql don't know which table to update
-- CREATE VIEW invalid_view AS
-- SELECT e.id, e.name, e.salary, d.department_name
-- FROM employees e
-- JOIN departments d ON e.id = d.manager_id;

-- which is why when tried to update this view, it fails
-- UPDATE invalid_view SET salary = 5000 WHERE id = 1;

CREATE TABLE employees2
(
    id            SERIAL PRIMARY KEY,
    first_name    VARCHAR(50) NOT NULL,
    last_name     VARCHAR(50) NOT NULL,
    department_id INT,
    employee_type VARCHAR(20)
        CHECK (employee_type IN ('FTE', 'Contractor'))
);

INSERT INTO employees2 (first_name, last_name, department_id, employee_type)
VALUES ('John', 'Doe', 1, 'FTE'),
       ('Jane', 'Smith', 2, 'FTE'),
       ('Bob', 'Johnson', 1, 'Contractor'),
       ('Alice', 'Williams', 3, 'FTE'),
       ('Charlie', 'Brown', 2, 'Contractor'),
       ('Eva', 'Jones', 1, 'FTE'),
       ('Frank', 'Miller', 3, 'FTE'),
       ('Grace', 'Davis', 2, 'Contractor'),
       ('Henry', 'Clark', 1, 'FTE'),
       ('Ivy', 'Moore', 3, 'Contractor');

CREATE OR REPLACE VIEW fte AS
SELECT id,
       first_name,
       last_name,
       department_id,
       employee_type
FROM employees2
WHERE employee_type = 'FTE';

select *
from fte;

INSERT INTO fte(first_name, last_name, department_id, employee_type)
VALUES ('John', 'Smith', 1, 'Contractor');

-- To ensure that we can insert only employees with the type FTE into the employees table via the fte view, you can use the WITH CHECK OPTION:

CREATE OR REPLACE VIEW fte AS
SELECT id,
       first_name,
       last_name,
       department_id,
       employee_type
FROM employees2
WHERE employee_type = 'FTE'
WITH CHECK OPTION;

-- THIS BELOW QUERY FAIL BECAUSE FTE ONLY ACCEPTS NOW employee_type: 'FTE' so employee_type must only be 'FTE'
INSERT INTO fte(first_name, last_name, department_id, employee_type)
VALUES ('John', 'Snow', 1, 'Contractor');

UPDATE fte
SET last_name = 'Doe'
WHERE id = 2;

CREATE OR REPLACE VIEW fte AS
SELECT id,
       first_name,
       last_name,
       department_id,
       employee_type
FROM employees2
WHERE employee_type = 'FTE';

CREATE OR REPLACE VIEW fte_1
AS
SELECT id,
       first_name,
       last_name,
       department_id,
       employee_type
FROM fte
WHERE department_id = 1
WITH LOCAL CHECK OPTION;

SELECT *
FROM fte_1;

-- so, this insert query runs successfully
INSERT INTO fte_1(first_name, last_name, department_id, employee_type)
VALUES ('Miller', 'Jackson', 1, 'Contractor');

-- which can be ensured by running the below query, as it shows exact data just inserted
SELECT *
FROM employees2
WHERE first_name = 'Miller'
  and last_name = 'Jackson';

CREATE OR REPLACE VIEW fte_1
AS
SELECT id,
       first_name,
       last_name,
       department_id,
       employee_type
FROM fte
WHERE department_id = 1
WITH CASCADED CHECK OPTION;

-- now, it fails now fte_1 ensures its base view (or table) 's check (which is here fte that only allow fte for employee_type), so below a query fails
INSERT INTO fte_1(first_name, last_name, department_id, employee_type)
VALUES ('Peter', 'Taylor', 1, 'Contractor');

CREATE VIEW film_type
AS
SELECT title, rating
FROM film;

ALTER VIEW film_type RENAME TO film_view;


ALTER VIEW film_view
SET (check_option = local);

ALTER VIEW film_view
RENAME title TO film_title;

select *
from film_view;

-- Materialized views cache the result set of an expensive query and allow you to refresh data periodically
-- The materialized views can be useful in many cases that require fast data access. Therefore, you often find them in data warehouses and business intelligence application

CREATE MATERIALIZED VIEW rental_by_category
AS
 SELECT c.name AS category,
    sum(p.amount) AS total_sales
   FROM (((((payment p
     JOIN rental r ON ((p.rental_id = r.rental_id)))
     JOIN inventory i ON ((r.inventory_id = i.inventory_id)))
     JOIN film f ON ((i.film_id = f.film_id)))
     JOIN film_category fc ON ((f.film_id = fc.film_id)))
     JOIN category c ON ((fc.category_id = c.category_id)))
  GROUP BY c.name
  ORDER BY sum(p.amount) DESC
WITH NO DATA;

-- But querying right now, it will give the following error

-- [Err] ERROR: materialized view "rental_by_category" has not been populated
-- HINT: Use the REFRESH MATERIALIZED VIEW command.
SELECT * FROM rental_by_category;

-- Second, load data into the materialized view using the REFRESH MATERIALIZED VIEW statement: and now it will work
SELECT * FROM rental_by_category;

-- However, to refresh it with CONCURRENTLY option, you need to create a UNIQUE index for the view first.

CREATE UNIQUE INDEX rental_category
ON rental_by_category (category);

REFRESH MATERIALIZED VIEW CONCURRENTLY rental_by_category;

-- Summary
-- A materialized view is a view that stores data that comes from the base tables.
-- Use the CREATE MATERIALIZED VIEW statement to create a materialized view.
-- Use the REFRESH MATERIALIZED VIEW statement to load data from the base tables into the view.
-- Use the DROP MATERIALIZED VIEW statement to drop a materialized view.

-- ## PostgreSQL Recursive View: In PostgreSQL, a recursive view is a view whose defining query references the view name itself
-- A recursive view can be useful in performing hierarchical or recursive queries on hierarchical data structures stored in the database.

-- Creating a recursive view example
-- The following recursive query returns the employee and their managers including the CEO using a common table expression (CTE):

WITH RECURSIVE reporting_line AS (
  SELECT
    employee_id,
    full_name AS subordinates
  FROM
    employees
  WHERE
    manager_id IS NULL
  UNION ALL
  SELECT
    e.employee_id,
    (
      rl.subordinates || ' > ' || e.full_name
    ) AS subordinates
  FROM
    employees e
    INNER JOIN reporting_line rl ON e.manager_id = rl.employee_id
)
SELECT
  employee_id,
  subordinates
FROM
  reporting_line
ORDER BY
  employee_id;


CREATE RECURSIVE VIEW reporting_line (employee_id, subordinates) AS
SELECT
  employee_id,
  full_name AS subordinates
FROM
  employees
WHERE
  manager_id IS NULL
UNION ALL
SELECT
  e.employee_id,
  (
    rl.subordinates || ' > ' || e.full_name
  ) AS subordinates
FROM
  employees e
  INNER JOIN reporting_line rl ON e.manager_id = rl.employee_id;

-- To view the reporting line of the employee id 10, you can query directly from the view:

SELECT
  subordinates
FROM
  reporting_line
WHERE
  employee_id = 10;

-- listing views though postgrsql command
SELECT
  table_schema,
  table_name
FROM
  information_schema.views
WHERE
  table_schema NOT IN (
    'information_schema', 'pg_catalog'
  )
ORDER BY
  table_schema,
  table_name;

-- Listing materialized views
-- To retrieve all materialized views, you can query them from the pg_matviews view:

SELECT * FROM pg_matviews\G;
-- only get the materialized view
SELECT
  matviewname AS materialized_view_name
FROM
  pg_matviews
ORDER BY
  materialized_view_name;