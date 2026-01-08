# SQL Server Common Patterns & Templates

## Overview

This directory contains reusable SQL Server patterns and templates used by major tech companies. These patterns provide standardized solutions for common database design challenges including audit trails, soft deletes, versioning, multi-tenancy, and performance optimization.

## Table of Contents

1. [Audit Trail Pattern](#audit-trail-pattern)
2. [Soft Delete Pattern](#soft-delete-pattern)
3. [Versioning Pattern](#versioning-pattern)
4. [Multi-Tenancy Patterns](#multi-tenancy-patterns)
5. [Search & Filtering](#search--filtering)
6. [Pagination Patterns](#pagination-patterns)
7. [Caching Patterns](#caching-patterns)
8. [Notification System](#notification-system)
9. [File Storage Pattern](#file-storage-pattern)
10. [Rate Limiting](#rate-limiting)

## Audit Trail Pattern

### Basic Audit Table

```sql
-- Generic audit table for tracking changes
CREATE TABLE AuditLog (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    TableName NVARCHAR(128) NOT NULL,
    RecordID NVARCHAR(255) NOT NULL,  -- Primary key of the audited record
    Operation NVARCHAR(10) NOT NULL CHECK (Operation IN ('INSERT', 'UPDATE', 'DELETE')),
    OldValues NVARCHAR(MAX), -- JSON format
    NewValues NVARCHAR(MAX), -- JSON format
    ChangedBy NVARCHAR(255), -- User who made the change
    ChangedAt DATETIME2 DEFAULT GETDATE(),
    IPAddress NVARCHAR(45),
    UserAgent NVARCHAR(500),
    SessionID UNIQUEIDENTIFIER,

    -- Partitioning by month for large tables
    INDEX IX_AuditLog_ChangedAt CLUSTERED (ChangedAt),
    INDEX IX_AuditLog_TableRecord (TableName, RecordID),
    INDEX IX_AuditLog_Operation (Operation),
    INDEX IX_AuditLog_ChangedBy (ChangedBy)
);

-- Create partition function and scheme for monthly partitions
CREATE PARTITION FUNCTION pf_AuditLog_Monthly (DATETIME2)
AS RANGE RIGHT FOR VALUES
('2024-01-01', '2024-02-01', '2024-03-01', '2024-04-01', '2024-05-01',
 '2024-06-01', '2024-07-01', '2024-08-01', '2024-09-01', '2024-10-01',
 '2024-11-01', '2024-12-01', '2025-01-01');

CREATE PARTITION SCHEME ps_AuditLog_Monthly
AS PARTITION pf_AuditLog_Monthly
ALL TO ([PRIMARY]);
```

### Generic Audit Trigger Function

```sql
-- Generic audit trigger function
CREATE PROCEDURE sp_AuditTrail_Insert
    @TableName NVARCHAR(128),
    @RecordID NVARCHAR(255),
    @Operation NVARCHAR(10),
    @OldValues NVARCHAR(MAX) = NULL,
    @NewValues NVARCHAR(MAX) = NULL,
    @ChangedBy NVARCHAR(255) = NULL,
    @IPAddress NVARCHAR(45) = NULL,
    @UserAgent NVARCHAR(500) = NULL,
    @SessionID UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO AuditLog (
        TableName, RecordID, Operation, OldValues, NewValues,
        ChangedBy, IPAddress, UserAgent, SessionID
    )
    VALUES (
        @TableName, @RecordID, @Operation, @OldValues, @NewValues,
        @ChangedBy, @IPAddress, @UserAgent, @SessionID
    );
END;
GO

-- Example usage in a trigger
CREATE TRIGGER TR_Users_Audit
ON Users
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Operation NVARCHAR(10);
    DECLARE @OldValues NVARCHAR(MAX);
    DECLARE @NewValues NVARCHAR(MAX);

    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @Operation = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @Operation = 'INSERT';
    ELSE
        SET @Operation = 'DELETE';

    -- Convert old values to JSON
    SELECT @OldValues = (
        SELECT * FROM deleted FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    -- Convert new values to JSON
    SELECT @NewValues = (
        SELECT * FROM inserted FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    -- Log the audit trail
    EXEC sp_AuditTrail_Insert
        @TableName = 'Users',
        @RecordID = COALESCE((SELECT CAST(UserID AS NVARCHAR(255)) FROM inserted),
                            (SELECT CAST(UserID AS NVARCHAR(255)) FROM deleted)),
        @Operation = @Operation,
        @OldValues = @OldValues,
        @NewValues = @NewValues,
        @ChangedBy = SYSTEM_USER,
        @SessionID = @@SPID;
END;
GO
```

## Soft Delete Pattern

### Basic Soft Delete

```sql
-- Add soft delete columns to existing table
ALTER TABLE Products
ADD IsDeleted BIT DEFAULT 0,
    DeletedAt DATETIME2 NULL,
    DeletedBy NVARCHAR(255) NULL;

-- Create filtered index for active records
CREATE INDEX IX_Products_Active
ON Products (ProductName, CategoryID)
WHERE IsDeleted = 0;

-- Update queries to filter soft deletes
SELECT * FROM Products WHERE IsDeleted = 0;

-- Soft delete procedure
CREATE PROCEDURE sp_Product_SoftDelete
    @ProductID INT,
    @DeletedBy NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Products
    SET IsDeleted = 1,
        DeletedAt = GETDATE(),
        DeletedBy = @DeletedBy
    WHERE ProductID = @ProductID;
END;
GO

-- Hard delete old soft-deleted records (cleanup job)
CREATE PROCEDURE sp_Product_Cleanup
    @DaysOld INT = 365
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM Products
    WHERE IsDeleted = 1
    AND DeletedAt < DATEADD(DAY, -@DaysOld, GETDATE());
END;
GO
```

### Advanced Soft Delete with Cascade

```sql
-- Soft delete with cascade relationships
CREATE PROCEDURE sp_Order_SoftDelete
    @OrderID INT,
    @DeletedBy NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    -- Soft delete order items first
    UPDATE OrderItems
    SET IsDeleted = 1,
        DeletedAt = GETDATE(),
        DeletedBy = @DeletedBy
    WHERE OrderID = @OrderID;

    -- Soft delete order
    UPDATE Orders
    SET IsDeleted = 1,
        DeletedAt = GETDATE(),
        DeletedBy = @DeletedBy
    WHERE OrderID = @OrderID;

    COMMIT TRANSACTION;
END;
GO

-- Restore soft-deleted records
CREATE PROCEDURE sp_Order_Restore
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    -- Restore order items first
    UPDATE OrderItems
    SET IsDeleted = 0,
        DeletedAt = NULL,
        DeletedBy = NULL
    WHERE OrderID = @OrderID;

    -- Restore order
    UPDATE Orders
    SET IsDeleted = 0,
        DeletedAt = NULL,
        DeletedBy = NULL
    WHERE OrderID = @OrderID;

    COMMIT TRANSACTION;
END;
GO
```

## Versioning Pattern

### Temporal Table Versioning

```sql
-- Create temporal table for automatic versioning
CREATE TABLE ProductVersions (
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(200),
    Price DECIMAL(10,2),
    CategoryID INT,
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.ProductVersions_History));

-- Query current version
SELECT * FROM ProductVersions;

-- Query historical versions
SELECT * FROM ProductVersions
FOR SYSTEM_TIME AS OF '2023-01-01 00:00:00';

-- Query all versions between dates
SELECT * FROM ProductVersions
FOR SYSTEM_TIME BETWEEN '2023-01-01' AND '2023-12-31';

-- Query complete history
SELECT * FROM ProductVersions
FOR SYSTEM_TIME ALL;
```

### Manual Versioning Pattern

```sql
-- Manual versioning table
CREATE TABLE DocumentVersions (
    DocumentID INT,
    VersionNumber INT,
    Title NVARCHAR(200),
    Content NVARCHAR(MAX),
    CreatedBy NVARCHAR(255),
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    IsCurrent BIT DEFAULT 0,
    ChangeDescription NVARCHAR(MAX),

    PRIMARY KEY (DocumentID, VersionNumber),
    INDEX IX_DocumentVersions_Current (DocumentID) WHERE IsCurrent = 1,
    INDEX IX_DocumentVersions_CreatedAt (CreatedAt)
);

-- Versioning trigger
CREATE TRIGGER TR_DocumentVersions
ON Documents
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Mark old version as not current
    UPDATE dv
    SET dv.IsCurrent = 0
    FROM DocumentVersions dv
    INNER JOIN inserted i ON dv.DocumentID = i.DocumentID
    WHERE dv.IsCurrent = 1;

    -- Insert new version
    INSERT INTO DocumentVersions (
        DocumentID, VersionNumber, Title, Content,
        CreatedBy, ChangeDescription
    )
    SELECT
        i.DocumentID,
        ISNULL((
            SELECT MAX(VersionNumber) FROM DocumentVersions
            WHERE DocumentID = i.DocumentID
        ), 0) + 1,
        i.Title,
        i.Content,
        SYSTEM_USER,
        'Updated via trigger'
    FROM inserted i;
END;
GO
```

## Multi-Tenancy Patterns

### Schema-per-Tenant Pattern

```sql
-- Create tenant-specific schemas
CREATE SCHEMA Tenant1;
CREATE SCHEMA Tenant2;

-- Create tenant-specific tables
CREATE TABLE Tenant1.Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    TenantID INT DEFAULT 1,
    Username NVARCHAR(50),
    Email NVARCHAR(255)
);

CREATE TABLE Tenant2.Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    TenantID INT DEFAULT 2,
    Username NVARCHAR(50),
    Email NVARCHAR(255),
    AdditionalField NVARCHAR(100) -- Tenant-specific customization
);

-- Dynamic SQL for tenant-specific queries
CREATE PROCEDURE sp_GetUsersByTenant
    @TenantID INT
AS
BEGIN
    DECLARE @SchemaName NVARCHAR(50) = 'Tenant' + CAST(@TenantID AS NVARCHAR(10));
    DECLARE @SQL NVARCHAR(MAX);

    SET @SQL = 'SELECT * FROM ' + QUOTENAME(@SchemaName) + '.Users';

    EXEC sp_executesql @SQL;
END;
GO
```

### Row-Level Security Pattern

```sql
-- Add tenant column to shared tables
ALTER TABLE Users ADD TenantID INT NOT NULL DEFAULT 1;
ALTER TABLE Orders ADD TenantID INT NOT NULL DEFAULT 1;

-- Create security policy
CREATE SECURITY POLICY TenantSecurityPolicy
ADD FILTER PREDICATE dbo.fn_TenantAccess(TenantID) ON Users,
ADD FILTER PREDICATE dbo.fn_TenantAccess(TenantID) ON Orders;

-- Security function
CREATE FUNCTION dbo.fn_TenantAccess(@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT 1 AS AccessResult
    WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT)
    OR SESSION_CONTEXT(N'TenantID') IS NULL -- Allow system operations
);
GO

-- Set session context for tenant
EXEC sp_set_session_context @key = N'TenantID', @value = 1;
```

### Shared Database with Tenant Column

```sql
-- Shared tables with tenant isolation
CREATE TABLE Tenants (
    TenantID INT IDENTITY(1,1) PRIMARY KEY,
    TenantName NVARCHAR(100),
    Database NVARCHAR(50),
    IsActive BIT DEFAULT 1
);

CREATE TABLE TenantUsers (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    TenantID INT REFERENCES Tenants(TenantID),
    Username NVARCHAR(50),
    Email NVARCHAR(255),
    INDEX IX_TenantUsers_Tenant (TenantID),
    INDEX IX_TenantUsers_Email (Email) WHERE TenantID = 1 -- Filtered index per tenant
);

-- Tenant-specific constraints
ALTER TABLE TenantUsers
ADD CONSTRAINT CK_TenantUsers_Email_Format
CHECK (
    TenantID = 1 AND Email LIKE '%@company1.com' OR
    TenantID = 2 AND Email LIKE '%@company2.com'
);

-- Partitioning by tenant for large tables
CREATE PARTITION FUNCTION pf_Tenant (INT)
AS RANGE LEFT FOR VALUES (1, 2, 3);

CREATE PARTITION SCHEME ps_Tenant
AS PARTITION pf_Tenant
ALL TO ([PRIMARY]);
```

## Search & Filtering

### Advanced Search Template

```sql
-- Advanced search stored procedure
CREATE PROCEDURE sp_AdvancedSearch
    @SearchTerm NVARCHAR(1000) = NULL,
    @CategoryID INT = NULL,
    @MinPrice DECIMAL(10,2) = NULL,
    @MaxPrice DECIMAL(10,2) = NULL,
    @InStockOnly BIT = 0,
    @SortBy NVARCHAR(50) = 'ProductName',
    @SortOrder NVARCHAR(4) = 'ASC',
    @PageNumber INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic search query
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @WhereClause NVARCHAR(MAX) = '';
    DECLARE @OrderBy NVARCHAR(100);

    -- Build WHERE clause
    IF @SearchTerm IS NOT NULL
        SET @WhereClause += ' AND (p.ProductName LIKE @SearchTerm OR p.Description LIKE @SearchTerm)';

    IF @CategoryID IS NOT NULL
        SET @WhereClause += ' AND p.CategoryID = @CategoryID';

    IF @MinPrice IS NOT NULL
        SET @WhereClause += ' AND p.UnitPrice >= @MinPrice';

    IF @MaxPrice IS NOT NULL
        SET @WhereClause += ' AND p.UnitPrice <= @MaxPrice';

    IF @InStockOnly = 1
        SET @WhereClause += ' AND p.UnitsInStock > 0';

    -- Build ORDER BY clause
    SET @OrderBy = CASE @SortBy
        WHEN 'ProductName' THEN 'p.ProductName'
        WHEN 'UnitPrice' THEN 'p.UnitPrice'
        WHEN 'UnitsInStock' THEN 'p.UnitsInStock'
        ELSE 'p.ProductName'
    END + ' ' + @SortOrder;

    -- Build main query
    SET @SQL = '
    SELECT
        p.ProductID,
        p.ProductName,
        p.UnitPrice,
        p.UnitsInStock,
        c.CategoryName,
        ROW_NUMBER() OVER (ORDER BY ' + @OrderBy + ') AS RowNum,
        COUNT(*) OVER () AS TotalCount
    FROM Products p
    INNER JOIN Categories c ON p.CategoryID = c.CategoryID
    WHERE 1=1' + @WhereClause + '
    ORDER BY ' + @OrderBy + '
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;';

    -- Execute with parameters
    EXEC sp_executesql @SQL,
        N'@SearchTerm NVARCHAR(1000), @CategoryID INT, @MinPrice DECIMAL(10,2),
         @MaxPrice DECIMAL(10,2), @Offset INT, @PageSize INT',
        @SearchTerm = CASE WHEN @SearchTerm IS NOT NULL THEN '%' + @SearchTerm + '%' END,
        @CategoryID = @CategoryID,
        @MinPrice = @MinPrice,
        @MaxPrice = @MaxPrice,
        @Offset = (@PageNumber - 1) * @PageSize,
        @PageSize = @PageSize;
END;
GO
```

### Faceted Search

```sql
-- Faceted search results
CREATE PROCEDURE sp_FacetedSearch
    @SearchTerm NVARCHAR(1000) = NULL,
    @SelectedCategories NVARCHAR(MAX) = NULL, -- JSON array
    @PriceRange NVARCHAR(50) = NULL -- JSON object
AS
BEGIN
    SET NOCOUNT ON;

    -- Return search results
    SELECT TOP 100
        ProductID,
        ProductName,
        UnitPrice,
        CategoryName
    FROM Products p
    INNER JOIN Categories c ON p.CategoryID = c.CategoryID
    WHERE (@SearchTerm IS NULL OR p.ProductName LIKE '%' + @SearchTerm + '%')
    AND (@SelectedCategories IS NULL OR c.CategoryID IN (
        SELECT value FROM OPENJSON(@SelectedCategories)
    ))
    AND (@PriceRange IS NULL OR p.UnitPrice BETWEEN
        JSON_VALUE(@PriceRange, '$.min') AND JSON_VALUE(@PriceRange, '$.max')
    );

    -- Return facets
    SELECT
        'Category' AS FacetType,
        c.CategoryName AS FacetValue,
        COUNT(*) AS Count
    FROM Products p
    INNER JOIN Categories c ON p.CategoryID = c.CategoryID
    WHERE (@SearchTerm IS NULL OR p.ProductName LIKE '%' + @SearchTerm + '%')
    GROUP BY c.CategoryID, c.CategoryName
    ORDER BY Count DESC;

    -- Price ranges
    SELECT
        'PriceRange' AS FacetType,
        CASE
            WHEN UnitPrice < 10 THEN 'Under $10'
            WHEN UnitPrice < 50 THEN '$10 - $49'
            WHEN UnitPrice < 100 THEN '$50 - $99'
            ELSE '$100+' END AS FacetValue,
        COUNT(*) AS Count
    FROM Products
    WHERE (@SearchTerm IS NULL OR ProductName LIKE '%' + @SearchTerm + '%')
    GROUP BY CASE
        WHEN UnitPrice < 10 THEN 'Under $10'
        WHEN UnitPrice < 50 THEN '$10 - $49'
        WHEN UnitPrice < 100 THEN '$50 - $99'
        ELSE '$100+' END;
END;
GO
```

## Pagination Patterns

### Offset-Based Pagination

```sql
-- Offset-based pagination
CREATE PROCEDURE sp_GetProducts_Paginated
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @SortBy NVARCHAR(50) = 'ProductName',
    @SortOrder NVARCHAR(4) = 'ASC'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Offset INT = (@PageNumber - 1) * @PageSize;
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @OrderBy NVARCHAR(100);

    SET @OrderBy = CASE @SortBy
        WHEN 'ProductName' THEN 'p.ProductName'
        WHEN 'UnitPrice' THEN 'p.UnitPrice'
        ELSE 'p.ProductName'
    END + ' ' + @SortOrder;

    SET @SQL = '
    SELECT
        p.ProductID,
        p.ProductName,
        p.UnitPrice,
        p.UnitsInStock,
        c.CategoryName,
        COUNT(*) OVER () AS TotalCount
    FROM Products p
    INNER JOIN Categories c ON p.CategoryID = c.CategoryID
    ORDER BY ' + @OrderBy + '
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;';

    EXEC sp_executesql @SQL,
        N'@Offset INT, @PageSize INT',
        @Offset = @Offset,
        @PageSize = @PageSize;
END;
GO
```

### Keyset-Based Pagination (Cursor Pagination)

```sql
-- Keyset-based pagination for better performance
CREATE PROCEDURE sp_GetOrders_Keyset
    @LastOrderID INT = NULL,
    @LastOrderDate DATETIME2 = NULL,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@PageSize)
        OrderID,
        CustomerID,
        OrderDate,
        TotalAmount
    FROM Orders
    WHERE (@LastOrderID IS NULL AND @LastOrderDate IS NULL)
       OR (OrderDate < @LastOrderDate)
       OR (OrderDate = @LastOrderDate AND OrderID < @LastOrderID)
    ORDER BY OrderDate DESC, OrderID DESC;
END;
GO

-- Usage example
-- First page: EXEC sp_GetOrders_Keyset;
-- Next page: EXEC sp_GetOrders_Keyset @LastOrderID = 12345, @LastOrderDate = '2023-12-01';
```

## Caching Patterns

### Application-Level Cache

```sql
-- Cache table for frequently accessed data
CREATE TABLE Cache (
    CacheKey NVARCHAR(500) PRIMARY KEY,
    CacheValue NVARCHAR(MAX),
    ExpiresAt DATETIME2,
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    AccessCount INT DEFAULT 0,
    LastAccessed DATETIME2 DEFAULT GETDATE(),

    INDEX IX_Cache_Expires (ExpiresAt) WHERE ExpiresAt > GETDATE(),
    INDEX IX_Cache_LastAccessed (LastAccessed)
);

-- Cache management procedures
CREATE PROCEDURE sp_Cache_Get
    @CacheKey NVARCHAR(500),
    @CacheValue NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SELECT @CacheValue = CacheValue
    FROM Cache
    WHERE CacheKey = @CacheKey
    AND ExpiresAt > GETDATE();

    IF @@ROWCOUNT > 0
    BEGIN
        UPDATE Cache
        SET AccessCount += 1,
            LastAccessed = GETDATE()
        WHERE CacheKey = @CacheKey;
    END
END;
GO

CREATE PROCEDURE sp_Cache_Set
    @CacheKey NVARCHAR(500),
    @CacheValue NVARCHAR(MAX),
    @ExpirationMinutes INT = 60
AS
BEGIN
    MERGE Cache AS target
    USING (SELECT @CacheKey, @CacheValue, DATEADD(MINUTE, @ExpirationMinutes, GETDATE())) AS source
        (CacheKey, CacheValue, ExpiresAt)
    ON target.CacheKey = source.CacheKey
    WHEN MATCHED THEN
        UPDATE SET CacheValue = source.CacheValue,
                   ExpiresAt = source.ExpiresAt,
                   LastAccessed = GETDATE(),
                   AccessCount = 0
    WHEN NOT MATCHED THEN
        INSERT (CacheKey, CacheValue, ExpiresAt)
        VALUES (source.CacheKey, source.CacheValue, source.ExpiresAt);
END;
GO
```

### Materialized View Cache

```sql
-- Indexed view for expensive aggregations
CREATE VIEW vw_ProductSales WITH SCHEMABINDING
AS
SELECT
    p.ProductID,
    p.ProductName,
    SUM(od.OrderQty * od.UnitPrice) AS TotalSales,
    SUM(od.OrderQty) AS TotalQuantity,
    COUNT_BIG(*) AS OrderCount
FROM Sales.SalesOrderDetail od
INNER JOIN Production.Product p ON od.ProductID = p.ProductID
GROUP BY p.ProductID, p.ProductName;

-- Create unique clustered index to materialize the view
CREATE UNIQUE CLUSTERED INDEX IX_vw_ProductSales
ON vw_ProductSales (ProductID);

-- Create additional indexes for performance
CREATE INDEX IX_vw_ProductSales_ProductName
ON vw_ProductSales (ProductName);

-- Refresh strategy (scheduled job)
CREATE PROCEDURE sp_RefreshProductSalesCache
AS
BEGIN
    SET NOCOUNT ON;

    -- Indexed views are automatically maintained
    -- But we can force refresh if needed
    DBCC FREEPROCCACHE; -- Clear plan cache if necessary
    DBCC FREESESSIONCACHE; -- Clear session cache if necessary
END;
GO
```

## Notification System

### Notification Queue

```sql
-- Notification queue table
CREATE TABLE NotificationQueue (
    NotificationID INT IDENTITY(1,1) PRIMARY KEY,
    Recipient NVARCHAR(255) NOT NULL,
    NotificationType NVARCHAR(50) NOT NULL, -- Email, SMS, Push
    Subject NVARCHAR(500),
    Message NVARCHAR(MAX),
    Priority INT DEFAULT 1, -- 1=Low, 2=Medium, 3=High, 4=Critical
    Status NVARCHAR(20) DEFAULT 'Pending',
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    ScheduledAt DATETIME2 DEFAULT GETDATE(),
    SentAt DATETIME2 NULL,
    RetryCount INT DEFAULT 0,
    MaxRetries INT DEFAULT 3,
    ErrorMessage NVARCHAR(MAX),

    INDEX IX_NotificationQueue_Status_Priority (Status, Priority, ScheduledAt),
    INDEX IX_NotificationQueue_Recipient_Type (Recipient, NotificationType),
    INDEX IX_NotificationQueue_ScheduledAt (ScheduledAt) WHERE Status = 'Pending'
);

-- Notification templates
CREATE TABLE NotificationTemplates (
    TemplateID INT IDENTITY(1,1) PRIMARY KEY,
    TemplateName NVARCHAR(100) UNIQUE,
    SubjectTemplate NVARCHAR(500),
    BodyTemplate NVARCHAR(MAX),
    NotificationType NVARCHAR(50),
    IsActive BIT DEFAULT 1,

    INDEX IX_NotificationTemplates_Type (NotificationType) WHERE IsActive = 1
);
```

### Notification Processing

```sql
-- Queue processing procedure
CREATE PROCEDURE sp_ProcessNotificationQueue
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BatchSize INT = 100;
    DECLARE @MaxRetries INT = 3;

    -- Get pending notifications
    DECLARE @Notifications TABLE (
        NotificationID INT,
        Recipient NVARCHAR(255),
        NotificationType NVARCHAR(50),
        Subject NVARCHAR(500),
        Message NVARCHAR(MAX)
    );

    INSERT INTO @Notifications
    SELECT TOP (@BatchSize)
        NotificationID,
        Recipient,
        NotificationType,
        Subject,
        Message
    FROM NotificationQueue
    WHERE Status = 'Pending'
    AND ScheduledAt <= GETDATE()
    ORDER BY Priority DESC, CreatedAt ASC;

    -- Process each notification
    DECLARE @NotificationID INT;
    DECLARE @Recipient NVARCHAR(255);
    DECLARE @Type NVARCHAR(50);
    DECLARE @Subject NVARCHAR(500);
    DECLARE @Message NVARCHAR(MAX);

    WHILE EXISTS (SELECT 1 FROM @Notifications)
    BEGIN
        SELECT TOP 1
            @NotificationID = NotificationID,
            @Recipient = Recipient,
            @Type = NotificationType,
            @Subject = Subject,
            @Message = Message
        FROM @Notifications;

        BEGIN TRY
            -- Send notification (placeholder - implement actual sending logic)
            EXEC sp_SendNotification @Recipient, @Type, @Subject, @Message;

            -- Mark as sent
            UPDATE NotificationQueue
            SET Status = 'Sent',
                SentAt = GETDATE()
            WHERE NotificationID = @NotificationID;

        END TRY
        BEGIN CATCH
            -- Handle failure
            UPDATE NotificationQueue
            SET Status = CASE WHEN RetryCount >= MaxRetries THEN 'Failed' ELSE 'Pending' END,
                RetryCount = RetryCount + 1,
                ErrorMessage = ERROR_MESSAGE(),
                ScheduledAt = CASE WHEN RetryCount < MaxRetries
                    THEN DATEADD(MINUTE, POWER(2, RetryCount), GETDATE())
                    ELSE ScheduledAt END
            WHERE NotificationID = @NotificationID;
        END CATCH;

        -- Remove processed notification
        DELETE FROM @Notifications WHERE NotificationID = @NotificationID;
    END;
END;
GO
```

## File Storage Pattern

### File Metadata Management

```sql
-- File storage metadata
CREATE TABLE FileStorage (
    FileID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OriginalFileName NVARCHAR(500) NOT NULL,
    StoredFileName NVARCHAR(500) NOT NULL,
    FilePath NVARCHAR(1000),
    FileSize BIGINT NOT NULL,
    ContentType NVARCHAR(100),
    UploadDate DATETIME2 DEFAULT GETDATE(),
    UploadedBy NVARCHAR(255),
    IsDeleted BIT DEFAULT 0,
    DeletedDate DATETIME2 NULL,
    Checksum NVARCHAR(128), -- SHA-256 hash
    Version INT DEFAULT 1,

    INDEX IX_FileStorage_UploadedBy (UploadedBy),
    INDEX IX_FileStorage_IsDeleted (IsDeleted),
    INDEX IX_FileStorage_ContentType (ContentType),
    INDEX IX_FileStorage_UploadDate (UploadDate)
);

-- File chunks for large file support
CREATE TABLE FileChunks (
    FileID UNIQUEIDENTIFIER,
    ChunkIndex INT,
    ChunkData VARBINARY(MAX),
    ChunkSize INT,

    PRIMARY KEY (FileID, ChunkIndex),
    FOREIGN KEY (FileID) REFERENCES FileStorage(FileID)
);

-- File access audit
CREATE TABLE FileAccessLog (
    AccessID INT IDENTITY(1,1) PRIMARY KEY,
    FileID UNIQUEIDENTIFIER REFERENCES FileStorage(FileID),
    AccessedBy NVARCHAR(255),
    AccessType NVARCHAR(20), -- View, Download, Upload, Delete
    AccessDate DATETIME2 DEFAULT GETDATE(),
    IPAddress NVARCHAR(45),

    INDEX IX_FileAccessLog_FileID (FileID, AccessDate),
    INDEX IX_FileAccessLog_AccessedBy (AccessedBy)
);
```

### File Operations

```sql
-- File upload procedure
CREATE PROCEDURE sp_File_Upload
    @OriginalFileName NVARCHAR(500),
    @StoredFileName NVARCHAR(500),
    @FilePath NVARCHAR(1000),
    @FileSize BIGINT,
    @ContentType NVARCHAR(100),
    @UploadedBy NVARCHAR(255),
    @Checksum NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO FileStorage (
        OriginalFileName, StoredFileName, FilePath, FileSize,
        ContentType, UploadedBy, Checksum
    )
    VALUES (
        @OriginalFileName, @StoredFileName, @FilePath, @FileSize,
        @ContentType, @UploadedBy, @Checksum
    );

    SELECT SCOPE_IDENTITY() AS FileID;
END;
GO

-- File access logging trigger
CREATE TRIGGER TR_FileStorage_Access
ON FileStorage
AFTER SELECT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO FileAccessLog (FileID, AccessedBy, AccessType, IPAddress)
    SELECT
        i.FileID,
        SYSTEM_USER,
        'View',
        CONNECTIONPROPERTY('client_net_address')
    FROM inserted i;
END;
GO
```

## Rate Limiting

### Rate Limiting Table

```sql
-- Rate limiting storage
CREATE TABLE RateLimits (
    Identifier NVARCHAR(500) NOT NULL, -- IP, User, API Key
    LimitType NVARCHAR(100) NOT NULL,  -- API, Login, Upload
    Window NVARCHAR(20) NOT NULL,      -- 1m, 1h, 1d
    RequestCount INT DEFAULT 1,
    WindowStart DATETIME2 DEFAULT GETDATE(),
    LastRequest DATETIME2 DEFAULT GETDATE(),

    PRIMARY KEY (Identifier, LimitType, Window),
    INDEX IX_RateLimits_WindowStart (WindowStart),
    INDEX IX_RateLimits_LastRequest (LastRequest)
);

-- Rate limit configurations
CREATE TABLE RateLimitConfig (
    ConfigID INT IDENTITY(1,1) PRIMARY KEY,
    LimitType NVARCHAR(100) UNIQUE,
    RequestsPerMinute INT DEFAULT 60,
    RequestsPerHour INT DEFAULT 1000,
    RequestsPerDay INT DEFAULT 10000,
    BurstLimit INT DEFAULT 100,
    IsActive BIT DEFAULT 1
);
```

### Rate Limiting Functions

```sql
-- Check rate limit function
CREATE FUNCTION fn_CheckRateLimit (
    @Identifier NVARCHAR(500),
    @LimitType NVARCHAR(100),
    @Window NVARCHAR(20)
)
RETURNS BIT
AS
BEGIN
    DECLARE @IsAllowed BIT = 1;
    DECLARE @CurrentCount INT;
    DECLARE @WindowStart DATETIME2;
    DECLARE @Config TABLE (
        RequestsPerMinute INT,
        RequestsPerHour INT,
        RequestsPerDay INT
    );

    -- Get configuration
    INSERT INTO @Config
    SELECT RequestsPerMinute, RequestsPerHour, RequestsPerDay
    FROM RateLimitConfig
    WHERE LimitType = @LimitType AND IsActive = 1;

    -- Calculate window start
    SET @WindowStart = CASE @Window
        WHEN '1m' THEN DATEADD(MINUTE, -1, GETDATE())
        WHEN '1h' THEN DATEADD(HOUR, -1, GETDATE())
        WHEN '1d' THEN DATEADD(DAY, -1, GETDATE())
        ELSE DATEADD(MINUTE, -1, GETDATE())
    END;

    -- Get current count
    SELECT @CurrentCount = RequestCount
    FROM RateLimits
    WHERE Identifier = @Identifier
    AND LimitType = @LimitType
    AND Window = @Window
    AND WindowStart >= @WindowStart;

    -- Check limits
    IF @Window = '1m' AND @CurrentCount >= (SELECT RequestsPerMinute FROM @Config)
        SET @IsAllowed = 0;
    ELSE IF @Window = '1h' AND @CurrentCount >= (SELECT RequestsPerHour FROM @Config)
        SET @IsAllowed = 0;
    ELSE IF @Window = '1d' AND @CurrentCount >= (SELECT RequestsPerDay FROM @Config)
        SET @IsAllowed = 0;

    RETURN @IsAllowed;
END;
GO

-- Record rate limit procedure
CREATE PROCEDURE sp_RecordRateLimit
    @Identifier NVARCHAR(500),
    @LimitType NVARCHAR(100),
    @Window NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    MERGE RateLimits AS target
    USING (VALUES (@Identifier, @LimitType, @Window, GETDATE())) AS source
        (Identifier, LimitType, Window, Now)
    ON target.Identifier = source.Identifier
    AND target.LimitType = source.LimitType
    AND target.Window = source.Window
    WHEN MATCHED THEN
        UPDATE SET
            RequestCount = CASE
                WHEN DATEDIFF(MINUTE, WindowStart, source.Now) >=
                     CASE source.Window
                         WHEN '1m' THEN 1
                         WHEN '1h' THEN 60
                         WHEN '1d' THEN 1440
                         ELSE 1
                     END
                THEN 1
                ELSE RequestCount + 1
            END,
            WindowStart = CASE
                WHEN DATEDIFF(MINUTE, WindowStart, source.Now) >=
                     CASE source.Window
                         WHEN '1m' THEN 1
                         WHEN '1h' THEN 60
                         WHEN '1d' THEN 1440
                         ELSE 1
                     END
                THEN source.Now
                ELSE WindowStart
            END,
            LastRequest = source.Now
    WHEN NOT MATCHED THEN
        INSERT (Identifier, LimitType, Window, WindowStart, LastRequest)
        VALUES (source.Identifier, source.LimitType, source.Window, source.Now, source.Now);
END;
GO
```

These patterns provide reusable solutions for common database design challenges in SQL Server environments, promoting consistency, maintainability, and performance across applications.
