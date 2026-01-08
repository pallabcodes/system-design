CREATE TABLE IF NOT EXISTS contacts(
   id SERIAL PRIMARY KEY,
   first_name VARCHAR(50) NOT NULL,
   last_name VARCHAR(50) NOT NULL,
   full_name VARCHAR(101) GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED,
   email VARCHAR(300) UNIQUE
);

INSERT INTO contacts(first_name, last_name, email)
VALUES
   ('John', 'Doe', 'john@gmail.com'),
   ('Jane', 'Doe', 'jane@gmail.com')
RETURNING *;

select * from contacts;

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    list_price DECIMAL(10, 2) NOT NULL,
    tax DECIMAL(5, 2) DEFAULT 0,
    discount DECIMAL(5, 2) DEFAULT 0,
    net_price DECIMAL(10, 2) GENERATED ALWAYS AS ((list_price + (list_price * tax / 100)) - (list_price * discount / 100)) STORED
);

INSERT INTO products (name, list_price, tax, discount)
VALUES
    ('A', 100.00, 10.00, 5.00),
    ('B', 50.00, 8.00, 0.00),
    ('C', 120.00, 12.50, 10.00)
RETURNING *;

select * from products;