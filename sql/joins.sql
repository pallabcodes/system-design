-- # Join: simply combining columns from one (self-join) or more tables based on the values of the common columns between related tables. The common columns are typically the primary key columns of the first table and the foreign key columns of the second table.
-- N.B: PostgreSQL supports inner join, left join, right join, full outer join, cross join, natural join, and a special kind of join called self-join.

CREATE TABLE basket_a
(
    a       INT PRIMARY KEY,
    fruit_a VARCHAR(100) NOT NULL
);

CREATE TABLE basket_b
(
    b       INT PRIMARY KEY,
    fruit_b VARCHAR(100) NOT NULL
);

INSERT INTO basket_a (a, fruit_a)
VALUES (1, 'Apple'),
       (2, 'Orange'),
       (3, 'Banana'),
       (4, 'Cucumber');

INSERT INTO basket_b (b, fruit_b)
VALUES
--     (1, 'Orange'),
--     (2, 'Apple'),
--     (3, 'Watermelon'),
--     (4, 'Pear'),
(5, 'Mango');


select ba.a as id, ba.fruit_a as fruit_A, bb.b as alternate_id, bb.fruit_b as fruit_B
from basket_a ba
         inner join basket_b bb on ba.a = bb.b;

select ba.a as id, ba.fruit_a as fruit_A, bb.b as alternate_id, bb.fruit_b as fruit_B
from basket_a ba
         right join basket_b bb on ba.a = bb.b;

SELECT a,
       fruit_a,
       b,
       fruit_b
FROM basket_a
         FULL OUTER JOIN basket_b
                         ON fruit_a = fruit_b;

-- using table alias to self join

SELECT f1.title,
       f2.title,
       f1.length
FROM film f1
         INNER JOIN film f2
                    ON f1.film_id <> f2.film_id AND
                       f1.length = f2.length;

-- # INNER JOIN: only pick the rows i.e. matched on the both tables else don't

SELECT customer_id,
       first_name,
       last_name,
       amount,
       payment_date
FROM customer
         INNER JOIN payment USING (customer_id) -- when both tables uses same column i.e. customer_id, better to use the using syntax
ORDER BY payment_date;


SELECT c.customer_id,
       c.first_name,
       c.last_name,
       p.amount,
       p.payment_date
FROM customer c
         INNER JOIN payment p ON p.customer_id = c.customer_id -- without the using syntax
ORDER BY p.payment_date;

-- inner join three tables

SELECT c.customer_id,
       c.first_name || ' ' || c.last_name customer_name,
       s.first_name || ' ' || s.last_name staff_name,
       p.amount,
       p.payment_date
FROM customer c
         INNER JOIN payment p USING (customer_id)
         INNER JOIN staff s using (staff_id)
ORDER BY payment_date;

-- # LEFT JOIN
SELECT film.film_id,
       film.title,
       inventory.inventory_id
FROM film
         LEFT JOIN inventory ON inventory.film_id = film.film_id
ORDER BY film.title; -- SELECT, WHERE, GROUP, HAVING, ORDER, LIMIT

SELECT f.film_id,
       f.title,
       i.inventory_id
FROM film f
         LEFT JOIN inventory i USING (film_id)
WHERE i.film_id IS NULL
ORDER BY f.title;

-- RIGHT JOIN

SELECT film.film_id,
       film.title,
       inventory.inventory_id
FROM inventory
         RIGHT JOIN film
                    ON film.film_id = inventory.film_id
ORDER BY film.title;

SELECT f.film_id,
       f.title,
       i.inventory_id
FROM inventory i
         RIGHT JOIN film f USING (film_id)
WHERE i.inventory_id IS NULL
ORDER BY f.title;

-- SELF JOIN
CREATE TABLE employee
(
    employee_id INT PRIMARY KEY,
    first_name  VARCHAR(255) NOT NULL,
    last_name   VARCHAR(255) NOT NULL,
    manager_id  INT,
    FOREIGN KEY (manager_id) REFERENCES employee (employee_id) ON DELETE CASCADE
);

INSERT INTO employee (employee_id, first_name, last_name, manager_id)
VALUES (1, 'Windy', 'Hays', NULL),
       (2, 'Ava', 'Christensen', 1),
       (3, 'Hassan', 'Conner', 1),
       (4, 'Anna', 'Reeves', 2),
       (5, 'Sau', 'Norman', 2),
       (6, 'Kelsie', 'Hays', 3),
       (7, 'Tory', 'Goff', 3),
       (8, 'Salley', 'Lester', 3);

SELECT *
FROM employee;

-- So, only get employees and their manager
SELECT e.first_name || ' ' || e.last_name employee, -- employee name
       m.first_name || ' ' || m.last_name manager   -- employee's manager
FROM employee e
         INNER JOIN employee m ON m.employee_id = e.manager_id
ORDER BY manager;

/**
 * Let's assume there are film_id [1, 2, 3]
 * Logic:
 * 1. The condition `films[i].film_id > films[j].film_id` ensures:
 *    - Self-pairs (e.g., [1, 1]) are skipped, as a film cannot pair with itself.
 *    - Duplicate pairs (e.g., both [1, 2] and [2, 1]) are avoided by processing only one direction.
 *      For instance, if [1, 2] is checked, [2, 1] is ignored.
 * 2. The films are compared for equal lengths to find valid pairs.
 *
 * Without the `>`, all combinations (including duplicates and self-pairs) would be included.
 * Example:
 * Input: films = [{ film_id: 1 }, { film_id: 2 }, { film_id: 3 }]
 * Output: Valid pairs like [ { film1: "Film B", film2: "Film A" } ].
 *
 * SQL Equivalent:
 * SELECT f1.title, f2.title, f1.length
 * FROM film f1
 * INNER JOIN film f2 ON f1.film_id > f2.film_id AND f1.length = f2.length;
 * ****With the f1.film_id > f2.film_id condition, you only get: (2, 1), (3, 1), (3, 2)****
 */


SELECT f1.title,
       f2.title,
       f1.length
FROM film f1
         INNER JOIN film f2 ON f1.film_id > f2.film_id -- assume film has
    AND f1.length = f2.length;

-- FULL OUTER JOIN

-- DROP TABLE IF EXISTS departments, employees;

CREATE TABLE departments
(
    department_id   serial PRIMARY KEY,
    department_name VARCHAR(255) NOT NULL
);

CREATE TABLE employees
(
    employee_id   serial PRIMARY KEY,
    employee_name VARCHAR(255),
    department_id INTEGER
);


INSERT INTO departments (department_name)
VALUES ('Sales'),
       ('Marketing'),
       ('HR'),
       ('IT'),
       ('Production');
INSERT INTO employees (employee_name, department_id)
VALUES ('Bette Nicholson', 1),
       ('Christian Gable', 1),
       ('Joe Swank', 2),
       ('Fred Costner', 3),
       ('Sandra Kilmer', 4),
       ('Julia Mcqueen', NULL);


SELECT employee_name,
       department_name
FROM employees e
         FULL OUTER JOIN departments d
                         ON d.department_id = e.department_id;

SELECT employee_name,
       department_name
FROM employees e
         FULL OUTER JOIN departments d
                         ON d.department_id = e.department_id
WHERE employee_name IS NULL;

SELECT employee_name,
       department_name
FROM employees e
         FULL OUTER JOIN departments d
                         ON d.department_id = e.department_id
WHERE department_name IS NULL;

-- CROSS JOIN: a cross-join allows you to join two tables by combining each row from the first table with every row from the second table, resulting in a complete combination of all rows.

DROP TABLE IF EXISTS T1;

CREATE TABLE
    T1
(
    LABEL CHAR(1) PRIMARY KEY
);

DROP TABLE IF EXISTS T2;

CREATE TABLE
    T2
(
    score INT PRIMARY KEY
);

INSERT INTO T1 (LABEL)
VALUES ('A'),
       ('B');

INSERT INTO T2 (score)
VALUES (1),
       (2),
       (3);

-- The following statement uses the CROSS JOIN operator to join T1 table with T2 table:
select *
from T1; -- A, B
select *
from T2; -- 1, 2, 3

SELECT *
FROM T1
         CROSS JOIN T2;
-- so for 1 it prints A, B, and so for 2 and 3 therefore it prints pairs or for each value from T2 T1 will print

-- # (AVOID USING) NATURAL JOIN: A natural join is a join that creates an implicit join based on the same column names in the joined tables.

DROP TABLE IF EXISTS categories, products;

CREATE TABLE categories
(
    category_id   SERIAL PRIMARY KEY,
    category_name VARCHAR(255) NOT NULL
);

CREATE TABLE products
(
    product_id   serial PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    category_id  INT          NOT NULL,
    FOREIGN KEY (category_id) REFERENCES categories (category_id)
);

INSERT INTO categories (category_name)
VALUES ('Smartphone'),
       ('Laptop'),
       ('Tablet'),
       ('VR')
RETURNING *;

INSERT INTO products (product_name, category_id)
VALUES ('iPhone', 1),
       ('Samsung Galaxy', 1),
       ('HP Elite', 2),
       ('Lenovo Thinkpad', 2),
       ('iPad', 3),
       ('Kindle Fire', 3)
RETURNING *;

-- The following statement uses the NATURAL JOIN clause to join the products table with the categories table:
-- N.B: This statement performs an inner join using the category_id column.

-- 1) Basic PostgreSQL NATURAL JOIN example
SELECT * FROM products NATURAL JOIN categories;

-- 2) Using PostgreSQL NATURAL JOIN to perform a LEFT JOIN
SELECT * FROM categories NATURAL LEFT JOIN products;
