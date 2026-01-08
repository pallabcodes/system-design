-- Trigger is a database object that executes automatically (based on INSERT, UPDATE, DELETE, TRUNCATE) run a function

-- DROP TABLE IF EXISTS employees;

CREATE TABLE IF NOT EXISTS employees
(
    id         INT GENERATED ALWAYS AS IDENTITY,
    first_name VARCHAR(40) NOT NULL,
    last_name  VARCHAR(40) NOT NULL,
    PRIMARY KEY (id)
);

-- DROP TABLE IF EXISTS employee_audits cascade;

-- Suppose that when the name of an employee changes, you want to log it in a separate table called employee_audits :
CREATE TABLE IF NOT EXISTS employee_audits
(
    id          INT GENERATED ALWAYS AS IDENTITY,
    employee_id INT         NOT NULL,
    last_name   VARCHAR(40) NOT NULL,
    changed_on  TIMESTAMP   NOT NULL
);

-- The function inserts the old last name into the employee_audits table including employee id, last name, and the time of change if the last name of an employee changes.
-- The OLD represents the row before the update while the NEW represents the new row that will be updated. The OLD.last_name returns the last name before the update and the NEW.last_name returns the new last name.
CREATE OR REPLACE FUNCTION log_last_name_changes()
    RETURNS TRIGGER
    LANGUAGE PLPGSQL
AS
$$
BEGIN
    IF NEW.last_name <> OLD.last_name THEN
        RAISE NOTICE 'Trigger fired: % -> %', OLD.last_name, NEW.last_name;
        INSERT INTO employee_audits(employee_id, last_name, changed_on)
        VALUES (OLD.id, OLD.last_name, NOW());
    END IF;

    RETURN NEW;
END;
$$;


-- Second, bind the trigger function to the employees table. The trigger name is last_name_changes. Before the value of the last_name column is updated, the trigger function is automatically invoked to log the changes.

-- DROP TRIGGER IF EXISTS last_name_changes ON employees;

CREATE TRIGGER last_name_changes
    BEFORE UPDATE
    ON employees
    FOR EACH ROW
EXECUTE PROCEDURE log_last_name_changes();

INSERT INTO employees (first_name, last_name)
VALUES ('John', 'Doe');

INSERT INTO employees (first_name, last_name)
VALUES ('Lily', 'Bush');

select *
from employees;

-- so Lily Bush changes her last name to Lily Brown.
UPDATE employees
SET last_name = 'Brown'
WHERE ID = 2;

select *
from employees;

SELECT *
FROM employee_audits;

-- PostgreSQL DROP TRIGGER statement example
-- First, create a function that validates the username of a staff. The username is not null and its length must be at least 8.

CREATE FUNCTION check_staff_user()
    RETURNS TRIGGER
AS
$$
BEGIN
    IF length(NEW.username) < 8 OR NEW.username IS NULL THEN
        RAISE EXCEPTION 'The username cannot be less than 8 characters';
    END IF;
    IF NEW.NAME IS NULL THEN
        RAISE EXCEPTION 'Username cannot be NULL';
    END IF;
    RETURN NEW;
END;
$$
    LANGUAGE plpgsql;

-- Second, create a new trigger on the staff table of the sample database to check the username of a staff. This trigger will fire whenever you insert or update a row in the staff table:

-- CREATE TRIGGER username_check
--     BEFORE INSERT OR UPDATE
--     ON staff
--     FOR EACH ROW
-- EXECUTE PROCEDURE check_staff_user();

-- DROP TRIGGER username_check ON staff;

-- ## ALTER TRIGGER

-- DROP TABLE IF EXISTS employees;

CREATE TABLE IF NOT EXISTS employees(
   employee_id INT GENERATED ALWAYS AS IDENTITY,
   first_name VARCHAR(50) NOT NULL,
   last_name VARCHAR(50) NOT NULL,
   salary decimal(11,2) NOT NULL DEFAULT 0,
   PRIMARY KEY(employee_id)
);

CREATE OR REPLACE FUNCTION check_salary()
  RETURNS TRIGGER
  LANGUAGE PLPGSQL
  AS
$$
BEGIN
	IF (NEW.salary - OLD.salary) / OLD.salary >= 1 THEN
		RAISE 'The salary increment cannot that high.';
	END IF;

	RETURN NEW;
END;
$$;


CREATE TRIGGER before_update_salary
  BEFORE UPDATE
  ON employees
  FOR EACH ROW
  EXECUTE PROCEDURE check_salary();

INSERT INTO employees(first_name, last_name, salary)
VALUES('John','Doe',100000);

--  This update query should throw error as intended
UPDATE employees
SET salary = 200000
WHERE employee_id = 1;

ALTER TRIGGER before_update_salary
ON employees
RENAME TO salary_before_update;

-- The following example illustrates how to change the check_salary function of the salary_before_update trigger to validate_salary using transaction

BEGIN;
DROP TRIGGER IF EXISTS salary_before_update
ON employees;
CREATE TRIGGER salary_before_udpate
  BEFORE UPDATE
  ON employees
  FOR EACH ROW
  EXECUTE PROCEDURE validate_salary();
COMMIT;

-- ## BEFORE INSERT: TRIGGER

DROP TABLE IF EXISTS inventory, inventory_stat cascade;

-- First, create a table called inventory to store inventory data:
CREATE TABLE IF NOT EXISTS inventory(
    product_id INT PRIMARY KEY,
    quantity INT NOT NULL DEFAULT 0
);

-- Second, create a table called inventory_stat that stores the total quantity of all products:
CREATE TABLE IF NOT EXISTS inventory_stat(
    total_qty INT
);

-- Third, define a function that increases the total quantity in the inventory_stat before a row is inserted into the inventory table:

CREATE OR REPLACE FUNCTION update_total_qty()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS
$$
DECLARE
   p_row_count INT;
BEGIN
   SELECT COUNT(*) FROM inventory_stat
   INTO p_row_count;
   IF p_row_count > 0 THEN
      UPDATE inventory_stat
      SET total_qty = total_qty + NEW.quantity;
   ELSE
      INSERT INTO inventory_stat(total_qty)
      VALUES(new.quantity);
   END IF;
   RETURN NEW;
END;
$$;

-- If the inventory_stat table has no rows, the function inserts a new row with the quantity being inserted into the inventory table. Otherwise, it updates the existing quantity.
-- Fourth, define a BEFORE INSERT trigger associated with the inventory table:

CREATE TRIGGER inventory_before_insert
BEFORE INSERT
ON inventory
FOR EACH ROW
EXECUTE FUNCTION update_total_qty();

-- Fifth, insert a row into the inventory table:
INSERT INTO inventory(product_id, quantity)
VALUES(1, 100)
RETURNING *;

SELECT * FROM inventory_stat;

INSERT INTO inventory(product_id, quantity)
VALUES(2, 200)
RETURNING *;

SELECT * FROM inventory_stat;

-- ## AFTER INSERT: TRIGGER

-- DROP TABLE IF EXISTS members cascade;

-- First, create a new table called members to store the member data:
CREATE TABLE IF NOT EXISTS members (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE
);

-- Second, create another table called memberships to store the memberships of the members:
CREATE TABLE IF NOT EXISTS memberships (
    id SERIAL PRIMARY KEY,
    member_id INT NOT NULL REFERENCES members(id),
    membership_type VARCHAR(50) NOT NULL DEFAULT 'free'
);

-- Third, define a trigger function that inserts a default free membership for every member:
CREATE OR REPLACE FUNCTION create_membership_after_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO memberships (member_id)
    VALUES (NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Fourth, define an AFTER INSERT trigger on the members table, specifying that it should execute the create_membership_after_insert() function for each row inserted:

CREATE TRIGGER after_insert_member_trigger
AFTER INSERT ON members
FOR EACH ROW
EXECUTE FUNCTION create_membership_after_insert();

-- Fifth, insert a new row into the members table:
INSERT INTO members(name, email)
VALUES('John Doe', '[[email protected]](../cdn-cgi/l/email-protection.html)')
RETURNING *;

-- Use an AFTER INSERT trigger to call a function automatically after an INSERT operation successfully on the associated table.
select *
from memberships;

--  ## BEFORE UPDATE: TRIGGER
DROP TABLE IF EXISTS employees;

CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    salary NUMERIC NOT NULL
);

CREATE OR REPLACE FUNCTION fn_before_update_salary()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.salary < OLD.salary THEN
        RAISE EXCEPTION 'New salary cannot be less than current salary';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_update_salary_trigger
BEFORE UPDATE OF salary ON employees
FOR EACH ROW
EXECUTE FUNCTION fn_before_update_salary();

INSERT INTO employees(name, salary)
VALUES
   ('John Doe', 70000),
   ('Jane Doe', 80000)
RETURNING *;

-- Below update query should throw error as intended
UPDATE employees
SET salary = salary * 0.9
WHERE id = 1;

-- AFTER UPDATE: TRIGGER

CREATE TABLE IF NOT EXISTS salaries(
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    salary NUMERIC NOT NULL
);

CREATE TABLE salary_changes (
    id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    old_salary NUMERIC NOT NULL,
    new_salary NUMERIC NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION log_salary_change()
RETURNS TRIGGER
AS
$$
BEGIN
    INSERT INTO salary_changes (employee_id, old_salary, new_salary)
    VALUES (NEW.id, OLD.salary, NEW.salary);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_update_salary_trigger
AFTER UPDATE OF salary ON salaries
FOR EACH ROW
EXECUTE FUNCTION log_salary_change();

INSERT INTO salaries(name, salary)
VALUES
   ('John Doe', 90000),
   ('Jane Doe', 95000)
RETURNING *;

UPDATE salaries
SET salary = salary * 1.05
WHERE id = 1;

select *
from salary_changes;

-- BEFORE DELETE: TRIGGER
DROP TABLE IF EXISTS products cascade;

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    status BOOLEAN NOT NULL DEFAULT true
);

INSERT INTO products (name, price, status)
VALUES
  ('A', 10.99, true),
  ('B', 20.49, false),
  ('C', 15.79, true)
RETURNING *;

CREATE OR REPLACE FUNCTION fn_before_delete_product()
RETURNS TRIGGER
AS
$$
BEGIN
    RAISE EXCEPTION 'Deletion from the products table is not allowed.';
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER before_delete_product_trigger
BEFORE DELETE ON products
FOR EACH ROW
EXECUTE FUNCTION fn_before_delete_product();

-- Below query throws error to prevent deletion as intended
DELETE FROM products where id = 1;

-- AFTER DELETE: TRIGGER
DROP TABLE IF EXISTS employees cascade;

CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    salary NUMERIC(10, 2) NOT NULL
);

INSERT INTO employees(name, salary)
VALUES
   ('John Doe', 90000),
   ('Jane Doe', 80000)
RETURNING *;

CREATE TABLE employee_archives(
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,

    salary NUMERIC(10, 2) NOT NULL,
    deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION archive_deleted_employee()
RETURNS TRIGGER
AS
$$
BEGIN
    INSERT INTO employee_archives(id, name, salary)
    VALUES (OLD.id, OLD.name, OLD.salary);

    RETURN OLD;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER after_delete_employee_trigger
AFTER DELETE ON employees
FOR EACH ROW
EXECUTE FUNCTION archive_deleted_employee();

select *
from employees;

DELETE FROM employees
WHERE id = 1
RETURNING *;

select *
from employee_archives;

-- INSTEAD OF: TRIGGER

-- Drop existing tables and cascade dependencies
DROP TABLE IF EXISTS employees, salaries CASCADE;

-- Create employees table
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

-- Create salaries table
CREATE TABLE salaries (
    employee_id INT,
    effective_date DATE NOT NULL,
    salary DECIMAL(10, 2) NOT NULL DEFAULT 0,
    PRIMARY KEY (employee_id, effective_date),
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE
);

-- Create view for employee salaries
CREATE VIEW employee_salaries AS
SELECT
    e.employee_id,
    e.name,
    s.salary,
    s.effective_date
FROM employees e
JOIN salaries s ON e.employee_id = s.employee_id;

-- Create function for INSTEAD OF trigger
CREATE OR REPLACE FUNCTION update_employee_salaries()
RETURNS TRIGGER AS
$$
DECLARE
    p_employee_id INT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Insert new employee and retrieve employee_id
        INSERT INTO employees (name)
        VALUES (NEW.name)
        RETURNING employee_id INTO p_employee_id;

        -- Insert corresponding salary record
        INSERT INTO salaries (employee_id, effective_date, salary)
        VALUES (p_employee_id, NEW.effective_date, NEW.salary);

    ELSIF TG_OP = 'UPDATE' THEN
        -- Update salary record
        UPDATE salaries
        SET salary = NEW.salary
        WHERE employee_id = NEW.employee_id
          AND effective_date = NEW.effective_date;

    ELSIF TG_OP = 'DELETE' THEN
        -- Delete salary record
        DELETE FROM salaries
        WHERE employee_id = OLD.employee_id
          AND effective_date = OLD.effective_date;

        -- Optionally delete the employee if no salaries exist
        DELETE FROM employees
        WHERE employee_id = OLD.employee_id
          AND NOT EXISTS (
              SELECT 1 FROM salaries WHERE employee_id = OLD.employee_id
          );
    END IF;

    RETURN NULL; -- INSTEAD OF triggers must return NULL
END;
$$
LANGUAGE plpgsql;

-- Create trigger for employee_salaries view
CREATE TRIGGER instead_of_employee_salaries
INSTEAD OF INSERT OR UPDATE OR DELETE
ON employee_salaries
FOR EACH ROW
EXECUTE FUNCTION update_employee_salaries();

-- Insert initial data into employees and salaries tables
INSERT INTO employees (name)
VALUES ('Alice'), ('Bob')
RETURNING *;

INSERT INTO salaries
VALUES
    (1, '2024-03-01', 60000.00),
    (2, '2024-03-01', 70000.00)
RETURNING *;

-- Insert a new employee and salary via the view
INSERT INTO employee_salaries (name, salary, effective_date)
VALUES ('Charlie', 75000.00, '2024-03-01');

-- Verify inserts
SELECT * FROM employees;
SELECT * FROM salaries;

-- Update the salary for employee_id = 3
UPDATE employee_salaries
SET salary = 95000
WHERE employee_id = 3;

-- Verify updates
SELECT * FROM salaries;

-- Delete employee_id = 3
DELETE FROM employee_salaries
WHERE employee_id = 3;

-- Verify deletes
SELECT * FROM employees;
SELECT * FROM salaries;

-- BEFORE TRUNCATE: TRIGGER
    -- Drop the companies table if it exists
DROP TABLE IF EXISTS companies CASCADE;

-- Create the companies table
CREATE TABLE companies (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

-- Insert initial data into the companies table
INSERT INTO companies (name)
VALUES
    ('Apple'),
    ('Microsoft'),
    ('Google')
RETURNING *;

-- Verify the inserts
SELECT * FROM companies;

-- Create a function to prevent truncation
CREATE OR REPLACE FUNCTION before_truncate_companies()
RETURNS TRIGGER AS
$$
BEGIN
    RAISE EXCEPTION 'Truncating the companies table is not allowed';
    RETURN NULL; -- Triggers must return NULL for statement-level triggers
END;
$$
LANGUAGE plpgsql;

-- Create a BEFORE TRUNCATE trigger on the companies table
CREATE TRIGGER before_truncate_companies_trigger
BEFORE TRUNCATE ON companies
FOR EACH STATEMENT
EXECUTE FUNCTION before_truncate_companies();

-- Attempt to truncate the companies table
DO $$
BEGIN
    BEGIN
        TRUNCATE TABLE companies;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Attempted to truncate the companies table but was prevented by the trigger.';
    END;
END;
$$;

-- Verify that the table still contains data
SELECT * FROM companies;

-- DISABLE TRIGGER: When you disable a trigger, it remains in the database but won’t activate when an event associated with the trigger occurs

-- Suppose you want to disable the trigger associated with the employees table, you can use the following statement:
ALTER TABLE employees
DISABLE TRIGGER log_last_name_changes;

-- To disable all triggers associated with the employees table, you use the following statement:
ALTER TABLE employees
DISABLE TRIGGER ALL;

-- ENABLE TRIGGER

ALTER TABLE employees
ENABLE TRIGGER salary_before_update;

ALTER TABLE employees
ENABLE TRIGGER ALL;

-- ADVANCED TRIGGERS :

-- EVENT TRIGGER: mainly used for Auditing DDL commands, monitoring activities.
-- Drop the audits table if it exists
DROP TABLE IF EXISTS audits CASCADE;

-- Create the audits table to store audit logs
CREATE TABLE audits (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    event VARCHAR(50) NOT NULL,
    command TEXT NOT NULL,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Verify the audits table creation
SELECT * FROM audits;

-- Create the event trigger function
CREATE OR REPLACE FUNCTION audit_command()
RETURNS EVENT_TRIGGER
AS $$
BEGIN
    -- Insert an audit log into the audits table
    INSERT INTO audits (username, event, command)
    VALUES (session_user, TG_EVENT, TG_TAG);
END;
$$ LANGUAGE plpgsql;

-- Drop the event trigger if it exists
DROP EVENT TRIGGER IF EXISTS audit_ddl_commands;

-- Create an event trigger for DDL commands
CREATE EVENT TRIGGER audit_ddl_commands
ON ddl_command_end
EXECUTE FUNCTION audit_command();

-- Execute a DDL command to test the event trigger
CREATE TABLE regions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

-- Retrieve and verify the audit log from the audits table
SELECT * FROM audits;


-- CONDITIONAL TRIGGER

-- Drop tables if they exist to ensure a clean slate
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS customer_stats CASCADE;

-- Step 1: Create the 'orders' table
CREATE TABLE orders (
    order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INT NOT NULL,
    total_amount NUMERIC NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL
);

-- Step 2: Create the 'customer_stats' table
CREATE TABLE customer_stats (
    customer_id INT PRIMARY KEY,
    total_spent NUMERIC NOT NULL DEFAULT 0
);

-- Verify the creation of tables
SELECT * FROM orders;
SELECT * FROM customer_stats;

-- Step 3: Create an AFTER INSERT trigger to insert rows into 'customer_stats'
CREATE OR REPLACE FUNCTION insert_customer_stats()
RETURNS TRIGGER
AS $$
BEGIN
   INSERT INTO customer_stats (customer_id)
   VALUES (NEW.customer_id)
   ON CONFLICT (customer_id) DO NOTHING; -- Avoid duplicate entries
   RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER insert_customer_stats_trigger
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION insert_customer_stats();

-- Step 4: Create an AFTER UPDATE trigger with a WHEN condition
CREATE OR REPLACE FUNCTION update_customer_stats()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.status = 'completed' THEN
        -- Update the total_spent column in 'customer_stats'
        UPDATE customer_stats
        SET total_spent = total_spent + NEW.total_amount
        WHERE customer_id = NEW.customer_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_customer_stats_trigger
AFTER UPDATE ON orders
FOR EACH ROW
WHEN (OLD.status <> 'completed' AND NEW.status = 'completed')
EXECUTE FUNCTION update_customer_stats();

-- Step 5: Insert rows into 'orders'
INSERT INTO orders (customer_id, total_amount, status)
VALUES
    (1, 100, 'pending'),
    (2, 200, 'pending');

-- Verify the contents of 'customer_stats' after the insert
SELECT * FROM customer_stats;

-- Step 6: Update order statuses to 'completed'
UPDATE orders
SET status = 'completed'
WHERE customer_id IN (1, 2);

-- Verify the contents of 'customer_stats' after the update
SELECT * FROM customer_stats;
