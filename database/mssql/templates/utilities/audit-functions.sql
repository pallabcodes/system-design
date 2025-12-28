-- SQL Server Audit Functions Utility
-- Collection of reusable audit and logging functions for SQL Server databases
-- Uses temporal tables and triggers for comprehensive audit trails

-- ===========================================
-- AUDIT TABLE CREATION
-- ===========================================

-- Create generic audit log table
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AuditLog]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[AuditLog]
    (
        AuditID BIGINT IDENTITY(1,1) PRIMARY KEY,
        TableName NVARCHAR(255) NOT NULL,
        RecordID NVARCHAR(255),
        Operation NVARCHAR(20) NOT NULL CHECK (Operation IN ('INSERT', 'UPDATE', 'DELETE')),
        OldValues NVARCHAR(MAX), -- JSON string
        NewValues NVARCHAR(MAX), -- JSON string
        ChangedBy NVARCHAR(255) DEFAULT SUSER_SNAME(),
        ChangedAt DATETIME2 DEFAULT GETUTCDATE(),
        ClientIP NVARCHAR(50),
        SessionUser NVARCHAR(255) DEFAULT SUSER_SNAME(),
        TransactionID BIGINT DEFAULT @@TRANCOUNT
    );

    CREATE INDEX IX_AuditLog_Table_Record ON [dbo].[AuditLog] (TableName, RecordID);
    CREATE INDEX IX_AuditLog_ChangedAt ON [dbo].[AuditLog] (ChangedAt DESC);
    CREATE INDEX IX_AuditLog_ChangedBy ON [dbo].[AuditLog] (ChangedBy);
END
GO

-- ===========================================
-- GENERIC AUDIT TRIGGER FUNCTION
-- ===========================================

-- Generic audit trigger stored procedure
CREATE OR ALTER PROCEDURE [dbo].[sp_AuditTrigger]
    @TableName NVARCHAR(255),
    @Operation NVARCHAR(20),
    @OldValues NVARCHAR(MAX) = NULL,
    @NewValues NVARCHAR(MAX) = NULL,
    @RecordID NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO [dbo].[AuditLog]
    (
        TableName,
        RecordID,
        Operation,
        OldValues,
        NewValues,
        ChangedBy,
        ChangedAt,
        SessionUser
    )
    VALUES
    (
        @TableName,
        @RecordID,
        @Operation,
        @OldValues,
        @NewValues,
        SUSER_SNAME(),
        GETUTCDATE(),
        SUSER_SNAME()
    );
END
GO

-- ===========================================
-- TEMPORAL TABLE UTILITIES
-- ===========================================

-- Function to enable temporal table on existing table
CREATE OR ALTER PROCEDURE [dbo].[sp_EnableTemporalTable]
    @TableName NVARCHAR(255),
    @HistoryTableName NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @HistoryTable NVARCHAR(255);
    
    -- Generate history table name if not provided
    IF @HistoryTableName IS NULL
        SET @HistoryTable = @TableName + 'History'
    ELSE
        SET @HistoryTable = @HistoryTableName;
    
    -- Check if table exists
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = @TableName)
    BEGIN
        RAISERROR('Table %s does not exist', 16, 1, @TableName);
        RETURN;
    END
    
    -- Add temporal columns if they don't exist
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(@TableName) AND name = 'ValidFrom')
    BEGIN
        SET @SQL = 'ALTER TABLE [' + @TableName + '] ADD ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN DEFAULT GETUTCDATE()';
        EXEC sp_executesql @SQL;
    END
    
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(@TableName) AND name = 'ValidTo')
    BEGIN
        SET @SQL = 'ALTER TABLE [' + @TableName + '] ADD ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN DEFAULT CONVERT(DATETIME2, ''9999-12-31 23:59:59.9999999'')';
        EXEC sp_executesql @SQL;
    END
    
    -- Add period for system time
    IF NOT EXISTS (SELECT * FROM sys.periods WHERE object_id = OBJECT_ID(@TableName))
    BEGIN
        SET @SQL = 'ALTER TABLE [' + @TableName + '] ADD PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)';
        EXEC sp_executesql @SQL;
    END
    
    -- Enable system versioning
    SET @SQL = 'ALTER TABLE [' + @TableName + '] SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.[' + @HistoryTable + ']))';
    EXEC sp_executesql @SQL;
    
    PRINT 'Temporal table enabled on ' + @TableName;
END
GO

-- ===========================================
-- AUDIT TRIGGER CREATION UTILITY
-- ===========================================

-- Function to create audit trigger for a table
CREATE OR ALTER PROCEDURE [dbo].[sp_CreateAuditTrigger]
    @TableName NVARCHAR(255),
    @PrimaryKeyColumn NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @TriggerName NVARCHAR(255) = 'trg_' + @TableName + '_Audit';
    DECLARE @PKColumn NVARCHAR(255);
    
    -- Determine primary key column
    IF @PrimaryKeyColumn IS NULL
    BEGIN
        SELECT TOP 1 @PKColumn = c.name
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.object_id = OBJECT_ID(@TableName)
          AND i.is_primary_key = 1
        ORDER BY ic.key_ordinal;
    END
    ELSE
        SET @PKColumn = @PrimaryKeyColumn;
    
    -- Drop existing trigger if it exists
    IF EXISTS (SELECT * FROM sys.triggers WHERE name = @TriggerName)
    BEGIN
        SET @SQL = 'DROP TRIGGER [' + @TriggerName + ']';
        EXEC sp_executesql @SQL;
    END
    
    -- Create INSERT trigger
    SET @SQL = '
    CREATE TRIGGER [' + @TriggerName + '_INSERT]
    ON [' + @TableName + ']
    AFTER INSERT
    AS
    BEGIN
        SET NOCOUNT ON;
        DECLARE @RecordID NVARCHAR(255);
        DECLARE @NewValues NVARCHAR(MAX);
        
        SELECT @RecordID = CAST(' + @PKColumn + ' AS NVARCHAR(255)),
               @NewValues = (SELECT * FROM inserted FOR JSON AUTO)
        FROM inserted;
        
        EXEC [dbo].[sp_AuditTrigger]
            @TableName = ''' + @TableName + ''',
            @Operation = ''INSERT'',
            @NewValues = @NewValues,
            @RecordID = @RecordID;
    END';
    EXEC sp_executesql @SQL;
    
    -- Create UPDATE trigger
    SET @SQL = '
    CREATE TRIGGER [' + @TriggerName + '_UPDATE]
    ON [' + @TableName + ']
    AFTER UPDATE
    AS
    BEGIN
        SET NOCOUNT ON;
        DECLARE @RecordID NVARCHAR(255);
        DECLARE @OldValues NVARCHAR(MAX);
        DECLARE @NewValues NVARCHAR(MAX);
        
        SELECT @RecordID = CAST(d.' + @PKColumn + ' AS NVARCHAR(255)),
               @OldValues = (SELECT * FROM deleted FOR JSON AUTO),
               @NewValues = (SELECT * FROM inserted FOR JSON AUTO)
        FROM deleted d
        INNER JOIN inserted i ON d.' + @PKColumn + ' = i.' + @PKColumn + ';
        
        EXEC [dbo].[sp_AuditTrigger]
            @TableName = ''' + @TableName + ''',
            @Operation = ''UPDATE'',
            @OldValues = @OldValues,
            @NewValues = @NewValues,
            @RecordID = @RecordID;
    END';
    EXEC sp_executesql @SQL;
    
    -- Create DELETE trigger
    SET @SQL = '
    CREATE TRIGGER [' + @TriggerName + '_DELETE]
    ON [' + @TableName + ']
    AFTER DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        DECLARE @RecordID NVARCHAR(255);
        DECLARE @OldValues NVARCHAR(MAX);
        
        SELECT @RecordID = CAST(' + @PKColumn + ' AS NVARCHAR(255)),
               @OldValues = (SELECT * FROM deleted FOR JSON AUTO)
        FROM deleted;
        
        EXEC [dbo].[sp_AuditTrigger]
            @TableName = ''' + @TableName + ''',
            @Operation = ''DELETE'',
            @OldValues = @OldValues,
            @RecordID = @RecordID;
    END';
    EXEC sp_executesql @SQL;
    
    PRINT 'Audit triggers created for ' + @TableName;
END
GO

-- ===========================================
-- QUERY AUDIT LOG
-- ===========================================

-- Function to query audit log for a specific table
CREATE OR ALTER PROCEDURE [dbo].[sp_QueryAuditLog]
    @TableName NVARCHAR(255) = NULL,
    @RecordID NVARCHAR(255) = NULL,
    @StartDate DATETIME2 = NULL,
    @EndDate DATETIME2 = NULL,
    @Operation NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT
        AuditID,
        TableName,
        RecordID,
        Operation,
        OldValues,
        NewValues,
        ChangedBy,
        ChangedAt,
        ClientIP,
        SessionUser
    FROM [dbo].[AuditLog]
    WHERE (@TableName IS NULL OR TableName = @TableName)
      AND (@RecordID IS NULL OR RecordID = @RecordID)
      AND (@StartDate IS NULL OR ChangedAt >= @StartDate)
      AND (@EndDate IS NULL OR ChangedAt <= @EndDate)
      AND (@Operation IS NULL OR Operation = @Operation)
    ORDER BY ChangedAt DESC;
END
GO

-- ===========================================
-- CLEANUP OLD AUDIT RECORDS
-- ===========================================

-- Function to cleanup old audit records
CREATE OR ALTER PROCEDURE [dbo].[sp_CleanupAuditLog]
    @RetentionDays INT = 365,
    @BatchSize INT = 10000
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@RetentionDays, GETUTCDATE());
    DECLARE @RowsDeleted INT = 1;
    DECLARE @TotalDeleted INT = 0;
    
    WHILE @RowsDeleted > 0
    BEGIN
        DELETE TOP (@BatchSize)
        FROM [dbo].[AuditLog]
        WHERE ChangedAt < @CutoffDate;
        
        SET @RowsDeleted = @@ROWCOUNT;
        SET @TotalDeleted = @TotalDeleted + @RowsDeleted;
        
        -- Wait a bit to avoid blocking
        WAITFOR DELAY '00:00:01';
    END
    
    PRINT 'Deleted ' + CAST(@TotalDeleted AS NVARCHAR(20)) + ' audit records older than ' + CAST(@RetentionDays AS NVARCHAR(10)) + ' days';
END
GO

