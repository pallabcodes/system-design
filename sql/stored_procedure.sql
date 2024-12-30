-- how to use the PostgreSQL CREATE FUNCTION statement to develop user-defined functions

CREATE OR REPLACE function get_film_count(len_from int, len_to int)
    returns int
    language plpgsql
as
$$
declare
    film_count integer;
begin
    -- In the body of the block, use the select into statement to select the number of films whose lengths are between len_from and len_to and assign it to the film_count variable. At the end of the block, use the return statement to return the film_count.
    select count(*) into film_count from film where length between len_from and len_to;
    return film_count;
end;
$$;


-- now, using the named function i.e. get_film_count
select get_film_count(40, 90);

select get_film_count(40, len_to => 90);


-- ## The following example defines the get_film_stat function that has three `out` parameters:
create or replace function get_film_stat(
    out min_len int,
    out max_len int,
    out avg_len numeric)
language plpgsql
as $$
begin
  select min(length),
         max(length),
		 avg(length)::numeric(5,1)
  into min_len, max_len, avg_len -- retrieved data will be saved into
  from film;
end;$$;

select get_film_stat();

select * from get_film_stat();

-- ## The INOUT mode
-- The inout mode is the combination in and out modes.

-- It means that the caller can pass an argument to a function. The function changes the argument and returns the updated value.

-- The following swap function accepts two integers and swap their values:

create or replace function swap(
	inout x int,
	inout y int
)
language plpgsql
as $$
begin
   select x,y into y,x;
end; $$;

select * from swap(10,20);

-- ##

create or replace function get_rental_duration(
	p_customer_id integer
)
returns integer
language plpgsql
as $$
declare
	rental_duration integer;
begin
	select
		sum( extract(day from return_date - rental_date))
	into rental_duration
    from rental
	where customer_id = p_customer_id;

	return rental_duration;
end; $$;

-- The get_rental_function function has the p_customer_id as an in parameter.
-- The following returns the number of rental days of customer id 232:
select * from get_rental_duration(232);

-- Suppose that you want to know the rental duration of a customer from a specific date up to now.
-- To do that, you can add one more parameter p_from_date to the get_retal_duration() function. Alternatively, you can develop a new function with the same name but have two parameters like this:

create or replace function get_rental_duration(
	p_customer_id integer,
	p_from_date date
)
returns integer
language plpgsql
as $$
declare
	rental_duration integer;
begin
	-- get the rental duration based on customer_id
	-- and rental date
	select sum( extract( day from return_date + '12:00:00' - rental_date))
	into rental_duration
	from rental
	where customer_id = p_customer_id and
		  rental_date >= p_from_date;

	-- return the rental duration in days
	return rental_duration;
end; $$;

-- This function shares the same name as the first one, except it has two parameters.
-- In other words, the get_rental_duration(integer) function is overloaded by the get_rental_duration(integer,date) function.
-- The following statement returns the rental duration of the customer id 232 since July 1st 2005:

SELECT get_rental_duration(232,'2005-07-01');

-- PL/pgSQL function overloading and default values
-- In the get_rental_duration(integer,date) function, if you want to set a default value to the second argument like this:

create or replace function get_rental_duration(
	p_customer_id integer,
	p_from_date date default '2005-01-01'
)
returns integer
language plpgsql
as $$
declare
	rental_duration integer;
begin
	select sum(
		extract( day from return_date + '12:00:00' - rental_date)
	)
	into rental_duration
	from rental
	where customer_id= p_customer_id and
		  rental_date >= p_from_date;
	return rental_duration;
end; $$;

-- SELECT get_rental_duration(232); -- ERROR

-- In this case, PostgreSQL could not choose the best candidate function to execute.
-- For the above query there are three functions: PL confused between below 1 or 3, which to execute which is why it throws the ERROR

-- get_rental_duration(p_customer_id integer); -- with no second argument
-- get_rental_duration(p_customer_id integer, p_from_date date)
--get_rental_duration(p_customer_id integer, p_from_date date default '2005-01-01') -- with the default parameter for the 2nd argument