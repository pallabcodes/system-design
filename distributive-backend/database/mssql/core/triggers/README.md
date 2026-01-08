# SQL Server Triggers

## Overview

Triggers in SQL Server are special stored procedures that automatically execute in response to specific events on a table or view. They are useful for enforcing business rules, maintaining audit trails, and ensuring data consistency.

## Table of Contents

1. [Trigger Types](#trigger-types)
2. [DML Triggers](#dml-triggers)
3. [DDL Triggers](#ddl-triggers)
4. [INSTEAD OF Triggers](#instead-of-triggers)
5. [Trigger Best Practices](#trigger-best-practices)
6. [Enterprise Patterns](#enterprise-patterns)

## Trigger Types

### DML Triggers

Execute in response to INSERT, UPDATE, or DELETE operations.

### DDL Triggers

Execute in response to CREATE, ALTER, or DROP statements.

### INSTEAD OF Triggers

Execute instead of the triggering action.

## DML Triggers

### AFTER INSERT Trigger

```sql
-- Trigger after insert
CREATE TRIGGER trg_Orders_AfterInsert
ON Orders
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Update user order count
    UPDATE u
    SET u.OrderCount = u.OrderCount + 1,
        u.LastOrderDate = i.OrderDate
    FROM Users u
    INNER JOIN inserted i ON u.UserID = i.UserID;
END;
GO
```

### AFTER UPDATE Trigger

```sql
-- Trigger after update
CREATE TRIGGER trg_Orders_AfterUpdate
ON Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Log status changes
    IF UPDATE(Status)
    BEGIN
        INSERT INTO OrderStatusHistory (OrderID, OldStatus, NewStatus, ChangedAt)
        SELECT 
            i.OrderID,
            d.Status AS OldStatus,
            i.Status AS NewStatus,
            GETUTCDATE()
        FROM inserted i
        INNER JOIN deleted d ON i.OrderID = d.OrderID
        WHERE i.Status <> d.Status;
    END
END;
GO
```

### AFTER DELETE Trigger

```sql
-- Trigger after delete
CREATE TRIGGER trg_Orders_AfterDelete
ON Orders
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Archive deleted orders
    INSERT INTO OrdersArchive (OrderID, OrderNumber, UserID, TotalAmount, DeletedAt)
    SELECT OrderID, OrderNumber, UserID, TotalAmount, GETUTCDATE()
    FROM deleted;
END;
GO
```

### Combined Trigger

```sql
-- Trigger handling multiple operations
CREATE TRIGGER trg_Products_Audit
ON Products
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Handle inserts
    IF EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted)
    BEGIN
        INSERT INTO AuditLog (TableName, Operation, RecordID, NewValues, ChangedAt)
        SELECT 
            'Products',
            'INSERT',
            ProductID,
            (SELECT * FROM inserted FOR JSON AUTO),
            GETUTCDATE()
        FROM inserted;
    END
    
    -- Handle updates
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
    BEGIN
        INSERT INTO AuditLog (TableName, Operation, RecordID, OldValues, NewValues, ChangedAt)
        SELECT 
            'Products',
            'UPDATE',
            i.ProductID,
            (SELECT * FROM deleted FOR JSON AUTO),
            (SELECT * FROM inserted FOR JSON AUTO),
            GETUTCDATE()
        FROM inserted i;
    END
    
    -- Handle deletes
    IF EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted)
    BEGIN
        INSERT INTO AuditLog (TableName, Operation, RecordID, OldValues, ChangedAt)
        SELECT 
            'Products',
            'DELETE',
            ProductID,
            (SELECT * FROM deleted FOR JSON AUTO),
            GETUTCDATE()
        FROM deleted;
    END
END;
GO
```

## DDL Triggers

### Database-Level DDL Trigger

```sql
-- Trigger for CREATE TABLE
CREATE TRIGGER trg_Database_CreateTable
ON DATABASE
FOR CREATE_TABLE
AS
BEGIN
    PRINT 'Table created: ' + EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(255)');
    
    -- Log DDL event
    INSERT INTO DDL_Log (EventType, ObjectName, EventDate)
    VALUES (
        'CREATE_TABLE',
        EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(255)'),
        GETDATE()
    );
END;
GO
```

### Server-Level DDL Trigger

```sql
-- Trigger for CREATE DATABASE
CREATE TRIGGER trg_Server_CreateDatabase
ON ALL SERVER
FOR CREATE_DATABASE
AS
BEGIN
    PRINT 'Database created: ' + EVENTDATA().value('(/EVENT_INSTANCE/DatabaseName)[1]', 'NVARCHAR(255)');
END;
GO
```

## INSTEAD OF Triggers

### INSTEAD OF INSERT

```sql
-- Instead of insert trigger
CREATE TRIGGER trg_Orders_InsteadOfInsert
ON Orders
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Validate before insert
    IF EXISTS (
        SELECT 1 FROM inserted i
        WHERE i.TotalAmount < 0
    )
    BEGIN
        RAISERROR('Total amount cannot be negative', 16, 1);
        RETURN;
    END
    
    -- Perform actual insert
    INSERT INTO Orders (OrderID, OrderNumber, UserID, OrderDate, TotalAmount)
    SELECT OrderID, OrderNumber, UserID, OrderDate, TotalAmount
    FROM inserted;
END;
GO
```

### INSTEAD OF UPDATE

```sql
-- Instead of update trigger
CREATE TRIGGER trg_Orders_InsteadOfUpdate
ON Orders
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Prevent status changes to cancelled orders
    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN deleted d ON i.OrderID = d.OrderID
        WHERE d.Status = 'Cancelled' AND i.Status <> d.Status
    )
    BEGIN
        RAISERROR('Cannot modify cancelled orders', 16, 1);
        RETURN;
    END
    
    -- Perform actual update
    UPDATE o
    SET 
        o.Status = i.Status,
        o.UpdatedAt = GETUTCDATE()
    FROM Orders o
    INNER JOIN inserted i ON o.OrderID = i.OrderID;
END;
GO
```

## Trigger Best Practices

### Performance Considerations

```sql
-- Use SET NOCOUNT ON
CREATE TRIGGER trg_Orders_Audit
ON Orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;  -- Reduces network traffic
    
    -- Trigger logic here
END;
GO

-- Avoid cursors in triggers
-- Use set-based operations instead
```

### Error Handling

```sql
-- Trigger with error handling
CREATE TRIGGER trg_Orders_Validate
ON Orders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        -- Validation logic
        IF EXISTS (
            SELECT 1 FROM inserted
            WHERE TotalAmount < 0
        )
        BEGIN
            RAISERROR('Invalid total amount', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END
    END TRY
    BEGIN CATCH
        -- Log error
        INSERT INTO ErrorLog (ErrorNumber, ErrorMessage, ErrorDate)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), GETDATE());
        
        -- Re-throw error
        THROW;
    END CATCH
END;
GO
```

## Enterprise Patterns

### Audit Trail Pattern

```sql
-- Comprehensive audit trigger
CREATE TRIGGER trg_Audit_AllTables
ON Orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Operation NVARCHAR(10);
    
    IF EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted)
        SET @Operation = 'INSERT';
    ELSE IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @Operation = 'UPDATE';
    ELSE
        SET @Operation = 'DELETE';
    
    INSERT INTO AuditLog (
        TableName,
        Operation,
        RecordID,
        OldValues,
        NewValues,
        ChangedBy,
        ChangedAt
    )
    SELECT 
        'Orders',
        @Operation,
        ISNULL(i.OrderID, d.OrderID),
        CASE WHEN @Operation IN ('UPDATE', 'DELETE') 
             THEN (SELECT * FROM deleted FOR JSON AUTO) 
             ELSE NULL END,
        CASE WHEN @Operation IN ('INSERT', 'UPDATE') 
             THEN (SELECT * FROM inserted FOR JSON AUTO) 
             ELSE NULL END,
        SYSTEM_USER,
        GETUTCDATE()
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.OrderID = d.OrderID;
END;
GO
```

### Soft Delete Pattern

```sql
-- Soft delete trigger
CREATE TRIGGER trg_Products_SoftDelete
ON Products
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Update IsDeleted flag instead of deleting
    UPDATE p
    SET 
        p.IsDeleted = 1,
        p.DeletedAt = GETUTCDATE(),
        p.DeletedBy = SYSTEM_USER
    FROM Products p
    INNER JOIN deleted d ON p.ProductID = d.ProductID
    WHERE p.IsDeleted = 0;
END;
GO
```

### Validation Pattern

```sql
-- Business rule validation trigger
CREATE TRIGGER trg_Orders_ValidateBusinessRules
ON Orders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Validate minimum order amount
    IF EXISTS (
        SELECT 1 FROM inserted
        WHERE TotalAmount < 10.00
    )
    BEGIN
        RAISERROR('Minimum order amount is $10.00', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
    
    -- Validate user exists and is active
    IF EXISTS (
        SELECT 1 FROM inserted i
        LEFT JOIN Users u ON i.UserID = u.UserID
        WHERE u.UserID IS NULL OR u.IsActive = 0
    )
    BEGIN
        RAISERROR('Order must be placed by an active user', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO
```

## Managing Triggers

### View Triggers

```sql
-- List all triggers on a table
SELECT 
    name AS TriggerName,
    type_desc AS TriggerType,
    is_disabled AS IsDisabled,
    create_date AS CreatedDate
FROM sys.triggers
WHERE parent_id = OBJECT_ID('Orders');

-- View trigger definition
SELECT OBJECT_DEFINITION(OBJECT_ID('trg_Orders_Audit')) AS TriggerDefinition;
```

### Disable/Enable Triggers

```sql
-- Disable trigger
ALTER TABLE Orders DISABLE TRIGGER trg_Orders_Audit;

-- Enable trigger
ALTER TABLE Orders ENABLE TRIGGER trg_Orders_Audit;

-- Disable all triggers on table
ALTER TABLE Orders DISABLE TRIGGER ALL;

-- Enable all triggers on table
ALTER TABLE Orders ENABLE TRIGGER ALL;
```

### Drop Triggers

```sql
-- Drop trigger
DROP TRIGGER trg_Orders_Audit;

-- Drop DDL trigger
DROP TRIGGER trg_Database_CreateTable ON DATABASE;
```

## Best Practices

1. **Keep triggers simple** and focused on single responsibility
2. **Use SET NOCOUNT ON** to reduce network traffic
3. **Avoid cursors** - use set-based operations
4. **Handle errors** gracefully with TRY-CATCH
5. **Test triggers** thoroughly before deployment
6. **Document trigger purposes** and business rules
7. **Monitor trigger performance** - triggers execute synchronously
8. **Use INSTEAD OF triggers** sparingly
9. **Consider alternatives** like stored procedures or application logic
10. **Review triggers regularly** for optimization opportunities

This guide provides comprehensive SQL Server trigger patterns for enforcing business rules and maintaining data integrity.

