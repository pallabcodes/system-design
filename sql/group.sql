-- # GROUP BY: FROM -> WHERE -> GROUP BY -> HAVING -> SELECT -> DISTINCT -> ORDER BY -> LIMIT

-- Using PostgreSQL GROUP BY with SUM() function example
SELECT customer_id,
       SUM(amount)
FROM payment
GROUP BY customer_id
ORDER BY SUM(amount) DESC;

-- Using PostgreSQL GROUP BY clause with the JOIN clause
SELECT first_name || ' ' || last_name full_name,
       SUM(amount)                    amount
FROM payment
         INNER JOIN customer USING (customer_id)
GROUP BY full_name
ORDER BY amount DESC;

-- Using PostgreSQL GROUP BY with COUNT() function example
SELECT staff_id,
       COUNT(payment_id)
FROM payment
GROUP BY staff_id;

-- Using PostgreSQL GROUP BY with multiple columns
SELECT customer_id,
       staff_id,
       SUM(amount)
FROM payment
GROUP BY staff_id,
         customer_id
ORDER BY customer_id;

-- Using PostgreSQL GROUP BY clause with a date column
SELECT payment_date::date payment_date,
       SUM(amount)        sum
FROM payment
GROUP BY payment_date::date
ORDER BY payment_date DESC;

-- # HAVING
SELECT customer_id,
       SUM(amount) amount
FROM payment
GROUP BY customer_id
HAVING SUM(amount) > 200
ORDER BY amount DESC;

SELECT customer_id,
       store_id,
       COUNT(customer_id) AS customers
FROM customer
GROUP BY store_id, customer_id
HAVING COUNT(customer_id) > 1;

select *
from customer;

-- When using GROUP BY; the selected columns must be part aggregate function i.e. MIN, MAX, AVG, SUM, COUNT or GROUP BY
SELECT customer_id,
       store_id,
       COUNT(customer_id) AS customers
FROM customer
GROUP BY store_id, customer_id
HAVING count(customer_id) > 0;
-- HAVING COUNT(customer_id) > 1

-- count the unique customers from per store
SELECT store_id, COUNT(DISTINCT customer_id) AS customers
FROM customer
GROUP BY store_id
HAVING COUNT(DISTINCT customer_id) > 1;

-- If you need both customer_id and store_id in the output but still want to filter based on COUNT(customer_id), consider using a window function instead of GROUP BY:
SELECT customer_id,
       store_id,
       COUNT(*) OVER (PARTITION BY store_id) AS customers
FROM customer
WHERE customer > 1;

-- # GROUPING SETS: how to use the PostgreSQL GROUPING SETS clause to generate multiple grouping sets in a query.

DROP TABLE IF EXISTS sales;

CREATE TABLE sales
(
    brand    VARCHAR NOT NULL,
    segment  VARCHAR NOT NULL,
    quantity INT     NOT NULL,
    PRIMARY KEY (brand, segment)
);

INSERT INTO sales (brand, segment, quantity)
VALUES ('ABC', 'Premium', 100),
       ('ABC', 'Basic', 200),
       ('XYZ', 'Premium', 100),
       ('XYZ', 'Basic', 300)
RETURNING *;

select *
from sales;

--  the following query uses the GROUP BY clause to return the number of products sold by brand and segment. In other words, it defines a grouping set of the brand and segment which is denoted by (brand, segment)
SELECT brand,
       segment,
       SUM(quantity)
FROM sales
GROUP BY brand,
         segment;

-- The following query finds the number of products sold by a brand. It defines a grouping set (brand)
SELECT brand,
       SUM(quantity)
FROM sales
GROUP BY brand;

-- The following query finds the number of products sold by segment. It defines a grouping set (segment):

SELECT segment,
       SUM(quantity)
FROM sales
GROUP BY segment;

-- The following query finds the number of products sold for all brands and segments. It defines an empty grouping set which is denoted by ().

SELECT SUM(quantity)
FROM sales;

-- Because UNION ALL requires all result sets to have the same number of columns with compatible data types, you need to adjust the queries by adding NULL to the selection list of each as shown below:

SELECT brand,
       segment,
       SUM(quantity)
FROM sales
GROUP BY brand,
         segment

UNION ALL

SELECT brand,
       NULL,
       SUM(quantity)
FROM sales
GROUP BY brand

UNION ALL

SELECT NULL,
       segment,
       SUM(quantity)
FROM sales
GROUP BY segment

UNION ALL

SELECT NULL,
       NULL,
       SUM(quantity)
FROM sales;

-- Even though the above query works as you expected, it has two main problems.
------------------------------------------------------------------------------
-- First, it is quite lengthy.
-- Second, it has a performance issue because PostgreSQL has to scan the sales table separately for each query.

-- To make it more efficient, PostgreSQL provides the GROUPING SETS clause which is the subclause of the GROUP BY clause.
------------------------------------------------------------------------------------------------------------------------
-- The GROUPING SETS allows you to define multiple grouping sets in the same query.

SELECT brand,
       segment,
       SUM(quantity)
FROM sales
GROUP BY
    GROUPING SETS ( (brand, segment),
                    (brand),
                    (segment),
    ()
    );

-- The column_name or expression must match with the one specified in the GROUP BY clause.
-- The GROUPING() function returns bit 0 if the argument is a member of the current grouping set and 1 otherwise.

SELECT GROUPING(brand)   grouping_brand,
       GROUPING(segment) grouping_segment,
       brand,
       segment,
       SUM(quantity)
FROM sales
GROUP BY
    GROUPING SETS ( (brand),
                    (segment),
    ()
    )
ORDER BY brand,
         segment;

-- As shown in the screenshot, when the value in the grouping_brand is 0, the sum column shows the subtotal of the brand.
-- When the value in the grouping_segment is zero, the sum column shows the subtotal of the segment.
-- You can use the GROUPING() function in the HAVING clause to find the subtotal of each brand like this:

SELECT GROUPING(brand)   grouping_brand,
       GROUPING(segment) grouping_segment,
       brand,
       segment,
       SUM(quantity)
FROM sales
GROUP BY
    GROUPING SETS ( (brand),
                    (segment),
    ()
    )
HAVING GROUPING(brand) = 0
ORDER BY brand,
         segment;

-- # CUBE

SELECT brand,
       segment,
       SUM(quantity)
FROM sales
GROUP BY
    CUBE (brand, segment)
ORDER BY brand,
         segment;

SELECT brand,
       segment,
       SUM(quantity)
FROM sales
GROUP BY brand,
    CUBE ( segment)
ORDER BY brand,
         segment;

-- # ROLLUP: ROLLUP is a subclause of the GROUP BY clause that offers a shorthand for defining multiple grouping sets. A grouping set is a set of columns by which you group

-- The following query uses the ROLLUP clause to find the number of products sold by brand (subtotal) and by all brands and segments (total).

-- As you can see clearly from the below query, the third row shows the sales of the ABC brand, the sixth row displays sales of the XYZ brand. The last row shows the grand total for all brands and segments. In this example, the hierarchy is brand > segment.

SELECT
    brand,
    segment,
    SUM (quantity)
FROM
    sales
GROUP BY
    ROLLUP (brand, segment)
ORDER BY
    brand,
    segment;

-- In this case, the hierarchy is the segment > brand.
SELECT
    segment,
    brand,
    SUM (quantity)
FROM
    sales
GROUP BY
    ROLLUP (segment, brand)
ORDER BY
    segment,
    brand;

-- The following statement performs a partial roll-up:

SELECT
    segment,
    brand,
    SUM (quantity)
FROM
    sales
GROUP BY
    segment,
    ROLLUP (brand)
ORDER BY
    segment,
    brand;

CREATE TABLE IF NOT EXISTS rental (
    rental_id SERIAL PRIMARY KEY,
    rental_date TIMESTAMP NOT NULL,
    inventory_id INT NOT NULL,
    customer_id INT NOT NULL,
    return_date TIMESTAMP,
    staff_id INT NOT NULL,
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id)
VALUES
    ('2024-11-30 10:00:00', 101, 1, '2024-12-05 14:00:00', 1),
    ('2024-11-29 09:30:00', 102, 2, '2024-12-03 12:00:00', 2),
    ('2024-11-28 11:15:00', 103, 3, '2024-12-01 16:30:00', 1),
    ('2024-11-27 14:45:00', 104, 4, '2024-12-02 18:00:00', 3),
    ('2024-11-26 08:20:00', 105, 5, '2024-11-30 10:45:00', 2);

-- The following statement finds the number of rental per day, month, and year by using the ROLLUP:
SELECT
    EXTRACT (YEAR FROM rental_date) y,
    EXTRACT (MONTH FROM rental_date) M,
    EXTRACT (DAY FROM rental_date) d,
    COUNT (rental_id)
FROM
    rental
GROUP BY
    ROLLUP (
        EXTRACT (YEAR FROM rental_date),
        EXTRACT (MONTH FROM rental_date),
        EXTRACT (DAY FROM rental_date)
    );

select * from customer;


SELECT c1.customer_id, c2.customer_id, c1.first_name, c2.first_name FROM customer c1 INNER JOIN customer c2 on c1.customer_id = c2.customer_id;