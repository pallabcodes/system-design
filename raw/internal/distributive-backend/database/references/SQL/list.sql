-- ## List Enums
SELECT n.nspname   AS schema,
       t.typname   AS enum_name,
       e.enumlabel AS value
FROM pg_type t
         JOIN pg_enum e ON t.oid = e.enumtypid
         JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
ORDER BY schema, enum_name, e.enumlabel;

-- Display all values by each ENUM
SELECT n.nspname                                          AS "Schema",
       t.typname                                          AS "Enum Name",
       string_agg(e.enumlabel, ', ' ORDER BY e.enumlabel) AS "Enum Values"
FROM pg_type t
         JOIN
     pg_enum e ON t.oid = e.enumtypid
         JOIN
     pg_catalog.pg_namespace n ON n.oid = t.typnamespace
GROUP BY n.nspname, t.typname
ORDER BY "Schema", "Enum Name";

-- ## List functions
SELECT n.nspname                                   AS schema,
       p.proname                                   AS function_name,
       pg_catalog.pg_get_function_result(p.oid)    AS return_type,
       pg_catalog.pg_get_function_arguments(p.oid) AS arguments
FROM pg_catalog.pg_proc p
         JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE pg_catalog.pg_function_is_visible(p.oid)
  AND n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
ORDER BY schema, function_name;


-- ## List triggers
SELECT t.tgname    AS trigger_name,
       c.relname   AS table_name,
       n.nspname   AS schema,
       t.tgenabled AS enabled,
       p.proname   AS trigger_function
FROM pg_catalog.pg_trigger t
         JOIN
     pg_catalog.pg_class c ON c.oid = t.tgrelid
         LEFT JOIN
     pg_catalog.pg_namespace n ON n.oid = c.relnamespace
         LEFT JOIN
     pg_catalog.pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal                                    -- Exclude internal triggers
  AND n.nspname NOT IN ('pg_catalog', 'information_schema') -- Exclude internal schemas
ORDER BY schema, table_name, trigger_name;


-- ## List views
SELECT table_schema AS schema,
       table_name   AS view_name
FROM information_schema.views
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY schema, view_name;


-- ## Drop the existing function first
DROP FUNCTION IF EXISTS count_template_tables();

-- ## Create the updated function
CREATE OR REPLACE FUNCTION count_template_tables()
    RETURNS TABLE
            (
                table_name_out text,
                row_count      bigint
            )
AS
$$
DECLARE
    rec RECORD; -- Declare a variable to hold each row of the loop
BEGIN
    -- Loop through all tables starting with "template"
    FOR rec IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_name LIKE 'template%' -- Filter tables starting with "template"
          AND table_schema = 'public' -- Specify the schema (public in this case)
        LOOP
            -- Dynamically count rows for each table and return the result
            RETURN QUERY EXECUTE format('SELECT %L, COUNT(*) FROM public.%I', rec.table_name, rec.table_name);
        END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- ## Get all the tables and its total row counts from each table

SELECT *
FROM count_template_tables();
-- All tables that exist or starts with 'template_'

SELECT table_name
FROM information_schema.tables
WHERE table_name LIKE 'template_%'
  AND table_schema = 'public';