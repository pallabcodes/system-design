-- =============================================
-- SQL Server Partitioning Examples
-- =============================================

-- 1. Create Filegroups (One for each year, plus primary)
-- Note: In a real script, you would add files to these filegroups.
-- ALTER DATABASE [YourDB] ADD FILEGROUP [FG_2020];
-- ALTER DATABASE [YourDB] ADD FILEGROUP [FG_2021];
-- ...

-- 2. Create Partition Function
-- Range Right: Value belongs to the partition on the right.
-- Partitions: < 2021, 2021, 2022, 2023, >= 2024
CREATE PARTITION FUNCTION PF_Yearly (DATETIME)
AS RANGE RIGHT FOR VALUES 
('2021-01-01', '2022-01-01', '2023-01-01', '2024-01-01');
GO

-- 3. Create Partition Scheme
-- Maps partitions to filegroups.
-- 'PRIMARY' is used here for simplicity; usually distinct filegroups.
CREATE PARTITION SCHEME PS_Yearly
AS PARTITION PF_Yearly
ALL TO ([PRIMARY]);
GO

-- 4. Create Partitioned Table
CREATE TABLE Sales.SalesLog (
    LogID INT IDENTITY(1,1),
    LogDate DATETIME NOT NULL,
    Message VARCHAR(500)
) ON PS_Yearly(LogDate); -- Partitioning by LogDate
GO

-- 5. Sliding Window - Adding a New Partition
-- Set the next filegroup as the next used
ALTER PARTITION SCHEME PS_Yearly NEXT USED [PRIMARY];

-- Split the range to create a new boundary for 2025
ALTER PARTITION FUNCTION PF_Yearly()
SPLIT RANGE ('2025-01-01');
GO

-- 6. Partition Switching (Archiving)
-- Create an empty staging table with SAME structure and ON SAME Filegroup/Scheme
CREATE TABLE Sales.SalesLog_Archive (
    LogID INT IDENTITY(1,1),
    LogDate DATETIME NOT NULL,
    Message VARCHAR(500)
) ON PS_Yearly(LogDate);

-- Switch Partition 1 (Oldest data) to Archive table
-- Note: Requires constraint checks to ensure data is valid for target
ALTER TABLE Sales.SalesLog 
SWITCH PARTITION 1 TO Sales.SalesLog_Archive PARTITION 1;
GO

-- 7. View Partition Info
SELECT 
    p.partition_number,
    p.rows,
    fg.name as filegroup_name
FROM sys.partitions p 
JOIN sys.destination_data_spaces dds ON p.partition_number = dds.destination_id
JOIN sys.filegroups fg ON dds.data_space_id = fg.data_space_id
WHERE object_id = OBJECT_ID('Sales.SalesLog');
GO
