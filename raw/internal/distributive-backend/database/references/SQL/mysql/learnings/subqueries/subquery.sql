-- # SUB QUERY : A subquery is a query nested within another query. A subquery is also known as an inner query or nested query.
-- Where to use subquery (SELECT, WHERE, GROUP, HAVING)

-- # Regular Subquery

SELECT name, (SELECT MAX(list_price) FROM products WHERE category_id = 1) AS max_price
FROM categories;

-- Find the country_id for the country = 'United States';
SELECT country_id
from country
where country = 'United States';

-- Second, retrieve cities from the city table where country_id is 103:
SELECT city
FROM city
WHERE country_id = 103
ORDER BY city;

-- basic subquery: Instead of executing two queries, you can combine them into one, making the first query as a subquery and the second query as the main query as follows
SELECT city
FROM city
WHERE country_id = (
    -- SUBQUERY STARTS
    SELECT country_id
    FROM country
    WHERE country = 'United States'
    -- SUBQUERY ENDS
)
ORDER BY city;

select *
from category;

-- Here, just dong `INNER JOIN` so based on the category.category_id matches with whichever film_id pick that
SELECT film_id
FROM film_category
         INNER JOIN category using (category_id)
WHERE name = 'Action';

-- Second, use the query above as a subquery to retrieve the film title from the film table:

-- Using subquery with IN
SELECT film_id,
       title,
       rating,
       length
FROM film
WHERE film_id IN (SELECT film_id
                  FROM film_category
                           INNER JOIN category USING (category_id)
                  WHERE name = 'Action')
ORDER BY film_id;

-- # Correlated Subquery: a correlated subquery is a subquery that references the columns from the outer query.

select film_id, title, length, rating
from film;

-- 1. The outer query retrieves film_id, title, length, rating from film f, and it has film_id (1), title (Action Movie 1), length(120), rating (PG-13)
-- 2. For each row processed by the outer query, the correlated subquery calculates the average length of films that have the same rating as the current row (f.rating) meaning
-- 3. For e.g. when at the first row film_id (1), rating (PG-13), go to subquery and find from tables that `PG-13` here it has 2 rows so get avg((120+110)/2) = 110
-- 4. since, outer query's length i.e. 120 greater so the currently outer row is applicable to part of the output


SELECT film_id, title, length, rating
FROM film f
WHERE length > (SELECT AVG(length)
                FROM film
                WHERE rating = f.rating);

-- # ANY Operator

CREATE TABLE employees
(
    id         SERIAL PRIMARY KEY,
    first_name VARCHAR(255)   NOT NULL,
    last_name  VARCHAR(255)   NOT NULL,
    salary     DECIMAL(10, 2) NOT NULL
);

CREATE TABLE managers
(
    id         SERIAL PRIMARY KEY,
    first_name VARCHAR(255)   NOT NULL,
    last_name  VARCHAR(255)   NOT NULL,
    salary     DECIMAL(10, 2) NOT NULL
);

INSERT INTO employees (first_name, last_name, salary)
VALUES ('Bob', 'Williams', 45000.00),
       ('Charlie', 'Davis', 55000.00),
       ('David', 'Jones', 50000.00),
       ('Emma', 'Brown', 48000.00),
       ('Frank', 'Miller', 52000.00),
       ('Grace', 'Wilson', 49000.00),
       ('Harry', 'Taylor', 53000.00),
       ('Ivy', 'Moore', 47000.00),
       ('Jack', 'Anderson', 56000.00),
       ('Kate', 'Hill', 44000.00),
       ('Liam', 'Clark', 59000.00),
       ('Mia', 'Parker', 42000.00);

INSERT INTO managers(first_name, last_name, salary)
VALUES ('John', 'Doe', 60000.00),
       ('Jane', 'Smith', 55000.00),
       ('Alice', 'Johnson', 58000.00);

select *
from employees;
select *
from managers;

-- 1) Using ANY operator with the = operator example (so salary exist on both employees and managers and so whichever salary from manager matched in employees, pick that)
SELECT *
FROM employees
WHERE salary = ANY (SELECT salary FROM managers);

-- 2) Using ANY operator with > operator example (so salary exist on both employees and managers and as it goes over each employee and then look for salary within manager if it is greater than current row's employees salary then pick it )
SELECT *
FROM employees
WHERE salary > ANY (SELECT salary FROM managers);

-- 3) Using ANY operator with < operator example : The following example uses the ANY operator to find employees who have salaries less than the manager’s salaries:
-- This query finds all employees whose salary is less than at least one other salary in the employees table.
-- It uses the ANY operator to compare each salary with the set of all salaries.
-- The largest salary is excluded because it cannot be less than any other salary.
-- 45000, 55000, 50000, 48000, 52000, 49000, 53000, 47000, 56000, 44000, 59000, 42000 : which is why 59000 excluded since it's highest (no greater amount in employees than this)
SELECT *
FROM employees
WHERE salary < ANY (SELECT salary FROM employees);
-- It returns all the rows with the employee type because they have a value in the salary column less than any value in the set (55K, 58K, and 60K).

-- # ALL Operator

SELECT *
FROM employees
WHERE salary > ALL (select salary from managers);

SELECT *
FROM employees
WHERE salary < ALL (select salary
                    from managers)
ORDER BY salary DESC;


-- # EXISTS Operator

-- Create the customer table
CREATE TABLE customer
(
    customer_id SERIAL PRIMARY KEY,                             -- Auto-incremented customer ID
    store_id    INT         NOT NULL,                           -- Store ID
    first_name  VARCHAR(50) NOT NULL,                           -- Customer's first name
    last_name   VARCHAR(50) NOT NULL,                           -- Customer's last name
    email       VARCHAR(100),                                   -- Customer's email
    address_id  INT         NOT NULL,                           -- Address ID
    activebool  BOOLEAN              DEFAULT TRUE,              -- Whether the customer is active
    create_date DATE        NOT NULL DEFAULT CURRENT_DATE,      -- Creation date
    last_update TIMESTAMP            DEFAULT CURRENT_TIMESTAMP, -- Last update timestamp
    active      INT                  DEFAULT 1                  -- Active status as integer
);

-- Create the payment table
CREATE TABLE payment
(
    payment_id   SERIAL PRIMARY KEY,                            -- Auto-incremented payment ID
    customer_id  INT            NOT NULL,                       -- Foreign key referencing customer
    staff_id     INT            NOT NULL,                       -- Staff ID
    rental_id    INT            NOT NULL,                       -- Rental ID
    amount       DECIMAL(10, 2) NOT NULL,                       -- Payment amount
    payment_date TIMESTAMP      NOT NULL,                       -- Payment date
    FOREIGN KEY (customer_id) REFERENCES customer (customer_id) -- Link to customer
);

-- Insert data into the customer table
INSERT INTO customer (store_id, first_name, last_name, email, address_id, activebool, create_date, last_update, active)
VALUES (1, 'John', 'Doe', 'john.doe@example.com', 101, TRUE, '2024-01-01', '2024-01-15 10:00:00', 1),
       (2, 'Jane', 'Smith', 'jane.smith@example.com', 102, TRUE, '2024-01-02', '2024-01-16 11:00:00', 1),
       (1, 'Alice', 'Johnson', 'alice.j@example.com', 103, FALSE, '2024-01-03', '2024-01-17 12:00:00', 0),
       (2, 'Bob', 'Brown', 'bob.brown@example.com', 104, TRUE, '2024-01-04', '2024-01-18 13:00:00', 1),
       (1, 'Charlie', 'Davis', 'charlie.d@example.com', 105, TRUE, '2024-01-05', '2024-01-19 14:00:00', 1);

-- Insert data into the payment table
INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
VALUES (1, 101, 201, 50.00, '2024-01-20 10:30:00'),
       (2, 102, 202, 30.00, '2024-01-21 11:30:00'),
       (3, 103, 203, 40.00, '2024-01-22 12:30:00'),
       (4, 104, 204, 25.00, '2024-01-23 13:30:00'),
       (5, 105, 205, 60.00, '2024-01-24 14:30:00');

select *
from payment;

SELECT EXISTS(SELECT 1
              FROM payment
              WHERE amount = 0);

SELECT first_name,
       last_name
FROM customer c
WHERE EXISTS (SELECT 1
              FROM payment p
              WHERE p.customer_id = c.customer_id
                AND amount > 11)
ORDER BY first_name,
         last_name;

SELECT first_name,
       last_name
FROM customer c
WHERE NOT EXISTS (SELECT 1
                  FROM payment p
                  WHERE p.customer_id = c.customer_id
                    AND amount > 11)
ORDER BY first_name, last_name;

SELECT first_name, last_name FROM customer WHERE EXISTS(SELECT NULL) ORDER BY first_name, last_name;