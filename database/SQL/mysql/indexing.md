- Index is nothing but an implemantion of B-Tree
- An index applied on the column(s) on which index added

- Indexing makes READ faster but slows down write operations (insert, update, and delete) because each mutation requires to rebalance the B-Tree. Therefore, having many indexeso off course slows down mutations/write operations (insert, update and delete) on the table/entity.

- So, A good rule of thumb : add index on the column which are often used in where clause, join queries.


# Understanding the execution plan (with MySQL)


```sql 
EXPLAIN SELECT * FROM Users where  id = 1 \G ;
```

- take a look at a field i.e. most likely above "possible_keys"  so it might say `type : const` and instead of types (think of it access_types) since this tells us how db is going to access our data and how exactly it is going to use an `index` or `not use an index` to execute this query.

## const/EQ_REF (i.e. basically does kinda binary search to find the single value/row for the query)

-> So, this `const/EQ_REF` basically performs a B-Tree traversal to find a `single value in the index tree` so it could be doing kind `Binary Search` -> this can only be used if the values are unique -> which we can do that like setting Primary key on a column, other way is to set `unique constraints` on a column.

## Common misunderstanding: Does limite 1 enforce uniqueness?

- Because we are still fetching more than 1 rows or all available rows from the table -> then just discarding all except 1 (so this isn't really enforce uniqueness which is why we must use `unique`)

-> So, as traversing on `index tree` from root, going left or right then we'lll eventually find that node that points / refer to that to expected row or no result. So, this is super-fast due logarithmic time complexity. 

## REF/RANGE (these two behave the same way)

- They're known as "index range scan"
- Here, these also traversal on the `index tree` however instead of finding a single value -> it finds the starting point of a range and then they scan from that point on. Let's say we've a query where id > 15 and id < 20 -> so this would traverse on `index tree` to find the first value i.e. 15 and from that point on it will start scanning through the leaf nodes (remember leaf ndoes are connected through doubly linked list) untill it hits the first value value i.e. greater than or equl to 20. And every rows i.e. found during this traversal are the only rows in the database that satisifies this range.


## INDEX 

- This is also known as `Full index scan`

- So unlike above i.e. Range here we are starting literally from the very first `leaf node` then scan through all until the very last `leaf node` so once again there is no limit but off course we are still `indexing` and using `index-tree` to traverlse and look for the result.

## ALL

- This is know as `Full Table Scan`
- It does not use `index` at all so it loads every row of the table into memory then go through them one by one and then omit / discard them based on given filters.

## Common pitfalls

```sql

SELECT sum(total) as total from Orders where Year(created_at) = 2014;

-- if it is slow try putting an index on created_at (for testing)

-- but if it is still slow then

EXPLAIN SELECT sum(total) as total from Orders where Year(created_at) = 2014;

-- then check if there is any `possible_keys` whether i.e. null but we have added index on created_at so what's happening?

-- Well, when usde a function like Year(created_at) database see it like Year(....) so it doesn't see what column(s) passed to the function and this is because you can't gurantee the output that the output of the function has anything to do with `index values` e.g. let's assume you have a function instead of Year that calculates the number of string characters so it returns an integeger but you have the index placed on a field/column i.e. string so that's why it won't work.

-- Therefore, we can't use index or even if added index -> index won't work for below query

SELECT SUM(total) FROM orders WHERE YEAR(created_at) = 2012; 

-- Although, there is function-based indexing avaiable on `postgresql` where insted of putting index on created_at (like we did right now), put it Year(created_at) then it works as a composite_index

N.B: Seems like MySQL 10 does has something similar to function-based indices like PostgreSQL but not as good and limited. Otherwise, another similar approach could be genrated column could work.

* But we should not created like date, hour, month or such generated colums instead use range

EXPLAIN SELECT SUM(total) from orders where created_at between '2004-01-01 00:00:00' and '2004-12-31 11:59:59';

-- While the above query won't improve the query performance/spped but I should see that now `possible_keys` using the index we have added on created_at but for scanning we should see `ALL` so it still does full table scan (row by row) thus it is slow 

* rows: this is not the total no. of rows rather estimated no. of rows which database has to scan through to get the result for this query.

-- Up untill avg query speed 6ms on this table with 3M rows

-- This is again for testing and never be done :: so even if we force index that makes `ALL` to `Range`

SELECT sum(totals) from orders FORCE INDEX (orders_created_at_idx) where created_at between '2004-01-01 00:00:00' and '2004-12-31 11:59:59' 

- But now it jumped to 4s (so 6x-7x slower than before), what happended?

-> It comes down what data is actually being stored on the index (right now i.e. created_at) but the query does sum(total) but we never added any index on `total` column -> so what does database do now -> go over the estimated rows (not the total rows) then it takes the row id then go back to the table fetch coresponding row that is a read from disk, fetch the row take the total column sum and do that 466145 times (this is no. of esitmated rows that it must scan through for this query) so off course i.e. 466145 reads from disk.

* Isn't a full table even worse since it has to do that for 2.4M times?

- Because, database is smart enough to if needed to `FULL table scan` i.e. know from get-go so I need to read everything anyways so it is not gonna read them one by one -> it will actuall batch read them and read a couple thousand at a times and the amount of DISK I/O is gonna be way less.

- Which is why for below query -> Database decided to go with `ALL i.e. Full table scan` i.e. much faster and we did not need mention it explicity (database is smart enough to apply it implicity on the query) ->

SELECT sum(totals) from orders where created_at between '2004-01-01 00:00:00' and '2004-12-31 11:59:59'

- So now, we know why "Database uses `ALL` but query is still slow` so now what? 

- Let's add index on `total` column now we should see instead of all indexing is 'range' -> now it doesn't have to read from DISK anymore

- There could be a fied from below exaplain named `extra` which says `using index` -> in simpler words, what it means this operation can now be performed entirely `in-memory` because MYSQL stores its indices `in-memory` and so here we have put all the data this this query needs on the index so there are no reads from the disk at all -> this is what's called an `INDEX only scan`

EXPLAIN SELECT sum(totals) from orders where created_at between '2004-01-01 00:00:00' and '2004-12-31 11:59:59'

- below query could be now talking <= 100ms for 3M

- So, here we have created the index on totals and created_at (but this could probably work for this query but about other queries?) e.g. also find for a specific user

SELECT sum(totals) from orders where created_at between '2004-01-01 00:00:00' and '2004-12-31 11:59:59';

- now this takes above >= 1s so what's happening ? If we look at `types` it should be all so it is doing `FULL TABLE SCAN` as it is reading from DISK again -> so  it is a same problem we added a column i.e. being used in this query which has no index so then shalle we just add index for `user_id` to solve this as before?

- So, let's say we do add the index on `user_id` column then EXPLAIN

EXPLAIN SELECT sum(totals) from orders where created_at between '2004-01-01 00:00:00' and '2004-12-31 11:59:59';

- So, now it should be doing `range i.e. RANGE SCAN` instead `ALL i.e. FULL TABLE SCAN` however if we look at estimated rows the no. of rows it looks up remain same (even though technically since we are searching for sepcific user and the user could have serveral orders but still that should not be same no. of esitamted rows as before unless the said table has a single user and single user's records which is off course not the case) => So, WHAT's GOING ON? WHAT'S HAPPENING?

## So, let' understand this pitfall

N.B: So, right now we have indices on multiple columns 

[refer to the image below]

- Looking at the above image -> we see the index is sorted first by created_at, then total and then user_id

- Now, here we have two values with same created_at and so they are sorted by `total` and if they have `same created_at and total value` then they are sorted by `USER ID`

- Here's what we must understand about `multi-column indices` -> it works from left to right (read the above point and refer to the image) so you can use this index for a query that uses that "filters on created_at", "filters on `created_at` and `total`, also `created_at and `total` and `user_id`" -> so as you see, you can't skip columns which means again you can be partial like only only taking created_at, created_at and total but you can't do created_at and user_id => so what we are doing here we have a where clause that uses `created_id` and `user_id` so we are skipping `total` that won't work.

- Because, USER ID itself is not sorted rather it is only sorted in respect to the `created_at` and `total` so if we jsut leave out the middle column i.e. `total` (refer to the image) the USER ID column is essentially unsorted so it is still using the index but it is only using up untill "created_at" 

:: The column order in an idex matters so A -> B is not same as B -> A [so how should we solve or order these multi column indexes]

-> so, let's way rearragne and now indexes are like `created_at`, `user_id` and `total` 

:: But this still doesn't work and it still scan through the same no. of estimated rows 466145 but why?

- i.e. due to inequality operators

-> We are using the multi-column indices `left to right` but as soon as there's an inequality operator on any of those column in the index (i.e. created_at) it is as "the index just stops there"

-> We've used BETWEEN i.e. an inequality operator on the `created_at` column and `created_at` is the first column in the index so it's as if our index just stops there and that's exactly why : "THE QUERY PERFORMANCE remains unchanged" whether have `user_id in the query or not` because it doesn't even get to that point -> since `index` here can only used up untill `created_at` due to usage inequality opertators. SOLUTION ?

* user_id -> created_at -> total

- Why don't we put `USER ID` index as first so that it can limit the search to exactly find the user and then limit them further for the orders placed in given year with  `created_at`

- now the query speed will improve but most imporanty estimated rows should siginficantly less too

** So, everything works fine now for when finding total for given yearh for a specific user

- However, for all reports it again slowed down


SELECT sum(totals) from orders where created_at between '2004-01-01 00:00:00' and '2004-12-31 11:59:59';

EXPLAIN SELECT sum(totals) from orders where created_at between '2004-01-01 00:00:00' and '2004-12-31 11:59:59';

- now, this will show `index` i.e. FULL INDEX SCAN (not it isn't same to `ALL`) which means we are still using the index but we're not using it too limiting the number of rows we have to look at -> we are basically starting at very first leaf node then just traverse through all 3M rows which we should see on estimated rows column. BUT WHY?

- So, we have changed the order of indexes and above query doesn't use `USER ID` and since we can only move `left to right` for multi column indexes and we can't skip column (for index arrangmenet)

-- So, as it stands now there is no idex that can satisfy both of these queries thus indexing is a developer concern -> it isn't the concern of the database because an index and a query always have to go together so you don't design an index in a vaccum rather "you always design an index for a query" and only we as developers know how our queries actually look like , how we are accessing the data thus only we know how to write a good index => so, in this case, the dev need to decide :: do I introduce is the repor that's run for all users maybe only run once a year so it really doesn't matter if it takes 600 millieseconds , it's something that you can only decide if you know the context/requirments and how you data is being accessed. 

```

## Different types of Indexes

- Structure : cluster, non-clustered 
- Storage : Rowstore , Columnstore
- Fuctions : Unique, Filtered

-- Some indexes are better for reading and others are for writing performance

- So, When we create an entity e.g. Users -> but behind the scene  it stores the data in a disk (that can be called a data file .mdf) and inside this file -> you have something called `pages`

- It's the samllest unit of datastroage in a database (8kb) and it can store anything (data, metadata, indexes)

- There are two types page: data page, index page 

-N.B: Leaf nodes of constructed B-Tree for the clustered index actually contains the data (data pages) -> from there it builts `INDEX PAGE` -> it stores key value (Pointers) to another page (it doesn't store the actual rows)

- N.B: Here as seen in the above , we don't have each pointer for every row


- So, as data added in the database, fist behing the scene those data gets actually sorted first then stored in data pages then build the B-Tree from it.