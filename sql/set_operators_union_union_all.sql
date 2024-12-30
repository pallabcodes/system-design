-- # UNION operator allows to combine the result sets of `two or more SELECT statements into a single result set` (final result won't contain the duplicates)

CREATE TABLE top_rated_films
(
    title        VARCHAR NOT NULL,
    release_year SMALLINT
);

CREATE TABLE most_popular_films
(
    title        VARCHAR NOT NULL,
    release_year SMALLINT
);

INSERT INTO top_rated_films(title, release_year)
VALUES ('The Shawshank Redemption', 1994),
       ('The Godfather', 1972),
       ('The Dark Knight', 2008),
       ('12 Angry Men', 1957);

INSERT INTO most_popular_films(title, release_year)
VALUES ('An American Pickle', 2020),
       ('The Godfather', 1972),
       ('The Dark Knight', 2008),
       ('Greyhound', 2020);

SELECT *
FROM top_rated_films; -- This is a  select query on top_rated_films

select *
from most_popular_films;
-- This is a  select query on most_rated_films

-- When combining SELECT queries from 2 SELECT queries if any value exist on both table, then it will pick just once whereas UNION ALL will also keep "DUPLICATE"

-- combine data from the SELECT queries from top_rated_films and most_popular_films
SELECT *
FROM top_rated_films
UNION
SELECT *
FROM most_popular_films;

-- combine data from the SELECT queries from top_rated_films and most_popular_films
SELECT *
FROM top_rated_films
UNION ALL
SELECT *
FROM most_popular_films;

-- # INTERCEPT: when combining both SELECT queries "INTERSECT" only pick the values i.e. available on both
SELECT *
FROM most_popular_films
INTERSECT
SELECT *
FROM top_rated_films;

SELECT *
FROM most_popular_films
INTERSECT
SELECT *
FROM top_rated_films
ORDER BY release_year;
-- by default ASC used


-- # EXCEPT: Only pick the columns that are available on first table i.e. here most_popular_films and not available in the top_rated_films
-- Assume, most_popular_films (A) and top_rated_films (B) so only pick rows from A that doesn't exist in B
SELECT *
FROM most_popular_films
EXCEPT
SELECT *
FROM top_rated_films;

SELECT *
FROM most_popular_films
EXCEPT
SELECT *
FROM top_rated_films
ORDER BY title DESC;