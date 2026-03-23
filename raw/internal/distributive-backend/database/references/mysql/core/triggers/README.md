# SQL Server Triggers

## Overview

A trigger is a special type of stored procedure that automatically executes when an event occurs in the database server. DML triggers execute when a user tries to modify data through a data manipulation language (DML) event. DDL triggers execute in response to a variety of data definition language (DDL) events.

## Types of Triggers

### 1. DML Triggers (Data Manipulation Language)
- **AFTER Triggers**: Execute *after* the action of the `INSERT`, `UPDATE`, `DELETE` statement has occurred.
- **INSTEAD OF Triggers**: Execute *in place of* the triggering action. Useful for views that are not updatable.

### 2. DDL Triggers (Data Definition Language)
- Fires in response to `CREATE`, `ALTER`, `DROP` statements.
- **Usage**: Auditing schema changes, preventing table drops.

### 3. Logon Triggers
- Fires in response to a `LOGON` event.
- **Usage**: Controlling login activity (e.g., limiting sessions per user).

## The Magic Tables: `inserted` and `deleted`

Triggers use two special tables to access data modified by the DML operation:
- **`inserted`**: Use this table to check the new values for `INSERT` or `UPDATE`.
- **`deleted`**: Use this table to check old values for `DELETE` or `UPDATE`.

| Operation | `inserted` Table | `deleted` Table |
| :--- | :--- | :--- |
| **INSERT** | New rows | Empty |
| **DELETE** | Empty | Deleted rows |
| **UPDATE** | New values | Old values |

## Best Practices

1.  **Keep Logic Simple**: Triggers run within the transaction of the DML statement. Long-running triggers lock tables and slow down the application.
2.  **Avoid Returning Results**: Do not use `SELECT` statements that return result sets inside a trigger.
3.  **Handle Multi-Row Operations**: Always write triggers to handle multiple rows. Do not assume `INSERT` or `UPDATE` affects only one row.
4.  **Use `SET NOCOUNT ON`**: Prevents "rows affected" messages from interfering with the application.
5.  **Audit Strategy**: Use triggers for detailed data auditing (saving old/new values to history tables).
