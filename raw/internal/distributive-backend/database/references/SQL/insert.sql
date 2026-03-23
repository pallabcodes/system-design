-- INSERT ... SELECT i.e. insert data into a table by selecting rows from another table or query.
INSERT INTO products (name, list_price, tax) SELECT name, price, tax_rate FROM temp_products;

-- INSERT with SELECT and JOIN
INSERT INTO products (name, list_price, tax)
SELECT tp.name, tp.price, tp.tax_rate
FROM temp_products tp
JOIN categories c
ON tp.temp_id = c.temp_id
WHERE c.category_name = 'Electronics';


-- INSERT ... ON CONFLICT (UPSERT) i.e. insert data, but handle conflicts by updating existing rows or doing nothing.
INSERT INTO products (product_id, name, list_price)
VALUES (1, 'Product A', 100.00)
ON CONFLICT (product_id)
DO UPDATE SET list_price = EXCLUDED.list_price;

-- ON CONFLICT DO NOTHING:
INSERT INTO products (product_id, name, list_price)
VALUES (1, 'Product A', 100.00)
ON CONFLICT DO NOTHING;



-- COPY Command i.e. efficiently bulk-load data from a file into a table.
COPY products (product_id, name, list_price, tax, discount)
FROM '/path/to/file.csv'
DELIMITER ',' CSV HEADER;

COPY products TO '/path/to/output.csv' DELIMITER ',' CSV HEADER;



-- RETURNING Clause i.e. retrieve data after insertion, such as generated values or computed columns.
INSERT INTO products (name, list_price, tax)
VALUES ('Product B', 150.00, 5)
RETURNING product_id, net_price;

-- Using WITH (Common Table Expressions - CTEs) i.e. combine WITH to insert data derived from CTEs.
WITH new_products AS (
    SELECT 'Product C' AS name, 200.00 AS list_price, 10 AS tax
)
INSERT INTO products (name, list_price, tax)
SELECT name, list_price, tax FROM new_products;


-- INSERT ... DEFAULT VALUES i.e. Insert a row using default values for all columns.
INSERT INTO products DEFAULT VALUES;

-- INSERT with Subqueries i.e. Insert using data derived dynamically via subqueries.
INSERT INTO products (name, list_price, tax)
VALUES (
    'Product D',
    (SELECT MAX(list_price) FROM products) + 50,
    8
);

-- FOREIGN TABLE (for Foreign Data Wrappers) i.e. Insert into foreign tables linked via FDW (Foreign Data Wrappers).
INSERT INTO foreign_products (product_id, name, list_price) VALUES (10, 'Foreign Product', 300.00);

-- EXECUTE (Dynamic SQL) i.e. Use dynamic SQL for inserting data.
DO $$
BEGIN
    EXECUTE 'INSERT INTO products (name, list_price, tax) VALUES ($1, $2, $3)'
    USING 'Dynamic Product', 120.00, 7;
END $$;

-- INSERT VIA PARTITIONED TABLES I.E. When inserting into a partitioned table partitioned_products, PostgreSQL automatically routes data to the appropriate partition.
INSERT INTO partitioned_products (product_id, name, list_price)
VALUES (20, 'Partitioned Product', 400.00);


-- INSERT USING ARRAY (UNNEST) I.E. Insert multiple rows derived from an array.
INSERT INTO products (name, list_price)
SELECT name, price
FROM unnest(ARRAY['Product E', 'Product F'], ARRAY[100.00, 200.00]) AS t(name, price);


-- INSERT USING JSON OR JSONB I.E. Insert multiple rows derived from an array.

INSERT INTO products (name, list_price, tax)
SELECT name, list_price, tax
FROM json_to_recordset('[
    {"name": "JSON Product 1", "list_price": 100.00, "tax": 5},
    {"name": "JSON Product 2", "list_price": 200.00, "tax": 10}
]') AS t(name TEXT, list_price NUMERIC, tax NUMERIC);

-- Batch insert

-- ## Explanation
-- pipelined_table_write:
-- A function provided by the pg_pipelined extension to perform high-performance batched writes.
-- The SQL String:
-- The INSERT INTO query specifies the target table and its columns.
-- The Array of Rows:
-- Data to be inserted is passed as an array of ROW values.
-- products[]:
-- The data is cast to match the structure of the products table.

-- ## When to Use?
-- When you have large volumes of data to insert and need minimal overhead.
-- When working in high-concurrency systems where batching improves performance.
-- For most use cases, this is optional but valuable if you’re dealing with real-time or bulk data ingestion pipelines.

DO $$
BEGIN
    -- Start the pipeline for batch insert
    CALL pipelined_table_write(
        'INSERT INTO products (product_id, name, list_price, tax, discount) VALUES ($1, $2, $3, $4, $5)',
        ARRAY[
            ROW(1, 'Product A', 100.00, 10, 5),
            ROW(2, 'Product B', 200.00, 15, 10),
            ROW(3, 'Product C', 300.00, 8, 3)
        ]::products[]
    );
END $$;
