-- Manufacturing & Production Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE ManufacturingDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE ManufacturingDB;
GO

-- Configure database for manufacturing performance
ALTER DATABASE ManufacturingDB
SET
    RECOVERY SIMPLE,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON,
    QUERY_STORE = ON; -- Enable query performance monitoring
GO

-- =============================================
-- PRODUCTION PLANNING & EXECUTION
-- =============================================

-- Production orders
CREATE TABLE ProductionOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    OrderNumber NVARCHAR(50) UNIQUE NOT NULL,
    ProductID INT NOT NULL, -- Reference to finished product
    OrderType NVARCHAR(20) DEFAULT 'Production', -- Production, Rework, Prototype
    Priority NVARCHAR(10) DEFAULT 'Normal', -- Low, Normal, High, Urgent

    -- Order details
    PlannedQuantity INT NOT NULL,
    ActualQuantity INT DEFAULT 0,
    UnitOfMeasure NVARCHAR(20) DEFAULT 'Each',
    PlannedStartDate DATETIME2,
    PlannedEndDate DATETIME2,
    ActualStartDate DATETIME2,
    ActualEndDate DATETIME2,

    -- Status and tracking
    Status NVARCHAR(20) DEFAULT 'Planned', -- Planned, Released, InProgress, Completed, Cancelled
    CurrentStage NVARCHAR(100),
    ProgressPercentage DECIMAL(5,2) DEFAULT 0,

    -- Financials
    PlannedCost DECIMAL(12,2),
    ActualCost DECIMAL(12,2),
    CustomerID INT, -- For make-to-order

    -- Audit fields
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy INT,
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_ProductionOrders_Type CHECK (OrderType IN ('Production', 'Rework', 'Prototype', 'Repair')),
    CONSTRAINT CK_ProductionOrders_Priority CHECK (Priority IN ('Low', 'Normal', 'High', 'Urgent')),
    CONSTRAINT CK_ProductionOrders_Status CHECK (Status IN ('Planned', 'Released', 'InProgress', 'Completed', 'Cancelled', 'OnHold')),
    CONSTRAINT CK_ProductionOrders_Progress CHECK (ProgressPercentage BETWEEN 0 AND 100),

    -- Indexes
    INDEX IX_ProductionOrders_Number (OrderNumber),
    INDEX IX_ProductionOrders_Product (ProductID),
    INDEX IX_ProductionOrders_Status (Status),
    INDEX IX_ProductionOrders_Priority (Priority),
    INDEX IX_ProductionOrders_PlannedStart (PlannedStartDate),
    INDEX IX_ProductionOrders_PlannedEnd (PlannedEndDate)
);

-- Bill of Materials (BOM)
CREATE TABLE BillOfMaterials (
    BOMID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    Version NVARCHAR(20) DEFAULT '1.0',
    IsActive BIT DEFAULT 1,
    EffectiveDate DATETIME2 DEFAULT GETDATE(),

    -- BOM metadata
    TotalCost DECIMAL(12,2),
    TotalWeight DECIMAL(8,3),
    CreatedBy INT,
    ApprovedBy INT,
    ApprovedDate DATETIME2,

    -- Constraints
    CONSTRAINT UQ_BillOfMaterials_ProductVersion UNIQUE (ProductID, Version),

    -- Indexes
    INDEX IX_BillOfMaterials_Product (ProductID),
    INDEX IX_BillOfMaterials_IsActive (IsActive),
    INDEX IX_BillOfMaterials_EffectiveDate (EffectiveDate)
);

-- BOM components
CREATE TABLE BOMComponents (
    ComponentID INT IDENTITY(1,1) PRIMARY KEY,
    BOMID INT NOT NULL REFERENCES BillOfMaterials(BOMID) ON DELETE CASCADE,
    MaterialID INT NOT NULL, -- Reference to raw material/product
    ComponentType NVARCHAR(20) DEFAULT 'Material', -- Material, Subassembly, Service

    -- Quantity and requirements
    QuantityRequired DECIMAL(10,4) NOT NULL,
    UnitOfMeasure NVARCHAR(20),
    ScrapFactor DECIMAL(5,4) DEFAULT 0, -- Expected waste/scrap percentage
    LeadTimeDays INT DEFAULT 0,

    -- Costing
    UnitCost DECIMAL(10,2),
    ExtendedCost DECIMAL(12,2),

    -- Constraints
    CONSTRAINT CK_BOMComponents_Type CHECK (ComponentType IN ('Material', 'Subassembly', 'Service', 'Labor')),

    -- Indexes
    INDEX IX_BOMComponents_BOM (BOMID),
    INDEX IX_BOMComponents_Material (MaterialID),
    INDEX IX_BOMComponents_Type (ComponentType)
);

-- Production routing
CREATE TABLE ProductionRouting (
    RoutingID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    Version NVARCHAR(20) DEFAULT '1.0',
    IsActive BIT DEFAULT 1,

    -- Routing metadata
    TotalCycleTime DECIMAL(8,2), -- In minutes
    TotalSetupTime DECIMAL(8,2), -- In minutes
    CreatedBy INT,
    ApprovedBy INT,

    -- Constraints
    CONSTRAINT UQ_ProductionRouting_ProductVersion UNIQUE (ProductID, Version),

    -- Indexes
    INDEX IX_ProductionRouting_Product (ProductID),
    INDEX IX_ProductionRouting_IsActive (IsActive)
);

-- Routing operations
CREATE TABLE RoutingOperations (
    OperationID INT IDENTITY(1,1) PRIMARY KEY,
    RoutingID INT NOT NULL REFERENCES ProductionRouting(RoutingID) ON DELETE CASCADE,
    OperationNumber INT NOT NULL,
    OperationName NVARCHAR(200) NOT NULL,
    WorkCenterID INT, -- Reference to work center/machine

    -- Time standards
    SetupTime DECIMAL(8,2), -- Minutes
    RunTime DECIMAL(8,2), -- Minutes per unit
    MoveTime DECIMAL(8,2), -- Minutes
    QueueTime DECIMAL(8,2), -- Minutes

    -- Quality requirements
    QualityCheckRequired BIT DEFAULT 0,
    InspectionCriteria NVARCHAR(MAX), -- JSON formatted criteria

    -- Constraints
    CONSTRAINT UQ_RoutingOperations_RoutingNumber UNIQUE (RoutingID, OperationNumber),

    -- Indexes
    INDEX IX_RoutingOperations_Routing (RoutingID),
    INDEX IX_RoutingOperations_WorkCenter (WorkCenterID),
    INDEX IX_RoutingOperations_Number (OperationNumber)
);

-- =============================================
-- QUALITY CONTROL & INSPECTION
-- =============================================

-- Quality inspection plans
CREATE TABLE QualityInspectionPlans (
    PlanID INT IDENTITY(1,1) PRIMARY KEY,
    PlanName NVARCHAR(200) NOT NULL,
    ProductID INT,
    PlanType NVARCHAR(20) DEFAULT 'Incoming', -- Incoming, InProcess, Final, Audit

    -- Plan details
    InspectionLevel NVARCHAR(20) DEFAULT 'Normal', -- Reduced, Normal, Tightened
    SampleSize INT,
    AcceptanceCriteria NVARCHAR(MAX), -- JSON formatted criteria
    TestMethods NVARCHAR(MAX), -- JSON array of test methods

    -- Validity
    IsActive BIT DEFAULT 1,
    EffectiveDate DATETIME2 DEFAULT GETDATE(),
    ExpirationDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_QualityInspectionPlans_Type CHECK (PlanType IN ('Incoming', 'InProcess', 'Final', 'Audit')),
    CONSTRAINT CK_QualityInspectionPlans_Level CHECK (InspectionLevel IN ('Reduced', 'Normal', 'Tightened')),

    -- Indexes
    INDEX IX_QualityInspectionPlans_Product (ProductID),
    INDEX IX_QualityInspectionPlans_Type (PlanType),
    INDEX IX_QualityInspectionPlans_IsActive (IsActive)
);

-- Quality inspections
CREATE TABLE QualityInspections (
    InspectionID INT IDENTITY(1,1) PRIMARY KEY,
    PlanID INT REFERENCES QualityInspectionPlans(PlanID),
    OrderID INT REFERENCES ProductionOrders(OrderID),
    BatchLotNumber NVARCHAR(50),
    InspectorID INT NOT NULL,

    -- Inspection details
    InspectionDate DATETIME2 DEFAULT GETDATE(),
    InspectionType NVARCHAR(20), -- Visual, Dimensional, Functional, Chemical
    SampleSize INT,
    DefectsFound INT DEFAULT 0,

    -- Results
    Result NVARCHAR(20) DEFAULT 'Pass', -- Pass, Fail, Conditional, Pending
    Disposition NVARCHAR(50), -- Accept, Reject, Rework, Scrap, UseAsIs
    Notes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_QualityInspections_Type CHECK (InspectionType IN ('Visual', 'Dimensional', 'Functional', 'Chemical', 'Performance')),
    CONSTRAINT CK_QualityInspections_Result CHECK (Result IN ('Pass', 'Fail', 'Conditional', 'Pending')),
    CONSTRAINT CK_QualityInspections_Disposition CHECK (Disposition IN ('Accept', 'Reject', 'Rework', 'Scrap', 'UseAsIs', 'ReturnToSupplier')),

    -- Indexes
    INDEX IX_QualityInspections_Plan (PlanID),
    INDEX IX_QualityInspections_Order (OrderID),
    INDEX IX_QualityInspections_Result (Result),
    INDEX IX_QualityInspections_Date (InspectionDate)
);

-- Quality defects
CREATE TABLE QualityDefects (
    DefectID INT IDENTITY(1,1) PRIMARY KEY,
    InspectionID INT NOT NULL REFERENCES QualityInspections(InspectionID),
    DefectCode NVARCHAR(20) NOT NULL,
    DefectDescription NVARCHAR(500),
    Severity NVARCHAR(10) DEFAULT 'Minor', -- Minor, Major, Critical

    -- Defect details
    QuantityAffected INT DEFAULT 1,
    RootCause NVARCHAR(MAX),
    CorrectiveAction NVARCHAR(MAX),
    PreventiveAction NVARCHAR(MAX),

    -- Resolution
    Status NVARCHAR(20) DEFAULT 'Open', -- Open, Investigating, Resolved, Closed
    ResolvedBy INT,
    ResolvedDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_QualityDefects_Severity CHECK (Severity IN ('Minor', 'Major', 'Critical')),
    CONSTRAINT CK_QualityDefects_Status CHECK (Status IN ('Open', 'Investigating', 'Resolved', 'Closed')),

    -- Indexes
    INDEX IX_QualityDefects_Inspection (InspectionID),
    INDEX IX_QualityDefects_Code (DefectCode),
    INDEX IX_QualityDefects_Severity (Severity),
    INDEX IX_QualityDefects_Status (Status)
);

-- =============================================
-- EQUIPMENT & MAINTENANCE MANAGEMENT
-- =============================================

-- Manufacturing equipment
CREATE TABLE Equipment (
    EquipmentID INT IDENTITY(1,1) PRIMARY KEY,
    EquipmentCode NVARCHAR(50) UNIQUE NOT NULL,
    EquipmentName NVARCHAR(200) NOT NULL,
    EquipmentType NVARCHAR(50) NOT NULL, -- Machine, Tool, Facility, Vehicle

    -- Equipment specifications
    Manufacturer NVARCHAR(100),
    Model NVARCHAR(100),
    SerialNumber NVARCHAR(100),
    InstallationDate DATETIME2,
    PurchaseCost DECIMAL(12,2),

    -- Location and hierarchy
    LocationID INT,
    ParentEquipmentID INT REFERENCES Equipment(EquipmentID),
    Criticality NVARCHAR(10) DEFAULT 'Medium', -- Low, Medium, High, Critical

    -- Operational parameters
    OperatingHours DECIMAL(10,2) DEFAULT 0,
    MaintenanceHours DECIMAL(10,2) DEFAULT 0,
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Maintenance, Down, Retired

    -- Performance metrics
    MTBF DECIMAL(10,2), -- Mean Time Between Failures (hours)
    MTTR DECIMAL(10,2), -- Mean Time To Repair (hours)
    Availability DECIMAL(5,4), -- 0.0000 to 1.0000

    -- Constraints
    CONSTRAINT CK_Equipment_Type CHECK (EquipmentType IN ('Machine', 'Tool', 'Facility', 'Vehicle', 'Software', 'Utility')),
    CONSTRAINT CK_Equipment_Criticality CHECK (Criticality IN ('Low', 'Medium', 'High', 'Critical')),
    CONSTRAINT CK_Equipment_Status CHECK (Status IN ('Active', 'Maintenance', 'Down', 'Retired', 'Standby')),
    CONSTRAINT CK_Equipment_Availability CHECK (Availability BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_Equipment_Code (EquipmentCode),
    INDEX IX_Equipment_Type (EquipmentType),
    INDEX IX_Equipment_Status (Status),
    INDEX IX_Equipment_Location (LocationID),
    INDEX IX_Equipment_Criticality (Criticality)
);

-- Maintenance schedules
CREATE TABLE MaintenanceSchedules (
    ScheduleID INT IDENTITY(1,1) PRIMARY KEY,
    EquipmentID INT NOT NULL REFERENCES Equipment(EquipmentID),
    ScheduleName NVARCHAR(200) NOT NULL,
    ScheduleType NVARCHAR(20) DEFAULT 'Preventive', -- Preventive, Predictive, ConditionBased

    -- Schedule parameters
    IntervalType NVARCHAR(20) DEFAULT 'Time', -- Time, Usage, Condition
    IntervalValue INT NOT NULL, -- Hours, cycles, etc.
    IntervalUnit NVARCHAR(20), -- Hours, Days, Weeks, Months, Cycles

    -- Maintenance details
    EstimatedDuration DECIMAL(6,2), -- Hours
    RequiredSkills NVARCHAR(MAX), -- JSON array of required skills
    PartsRequired NVARCHAR(MAX), -- JSON array of parts

    -- Schedule status
    IsActive BIT DEFAULT 1,
    NextDueDate DATETIME2,
    LastCompletedDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_MaintenanceSchedules_Type CHECK (ScheduleType IN ('Preventive', 'Predictive', 'ConditionBased', 'Regulatory')),
    CONSTRAINT CK_MaintenanceSchedules_IntervalType CHECK (IntervalType IN ('Time', 'Usage', 'Condition', 'Calendar')),
    CONSTRAINT CK_MaintenanceSchedules_IntervalUnit CHECK (IntervalUnit IN ('Hours', 'Days', 'Weeks', 'Months', 'Years', 'Cycles')),

    -- Indexes
    INDEX IX_MaintenanceSchedules_Equipment (EquipmentID),
    INDEX IX_MaintenanceSchedules_Type (ScheduleType),
    INDEX IX_MaintenanceSchedules_IsActive (IsActive),
    INDEX IX_MaintenanceSchedules_NextDue (NextDueDate)
);

-- Maintenance work orders
CREATE TABLE MaintenanceWorkOrders (
    WorkOrderID INT IDENTITY(1,1) PRIMARY KEY,
    WorkOrderNumber NVARCHAR(50) UNIQUE NOT NULL,
    EquipmentID INT NOT NULL REFERENCES Equipment(EquipmentID),
    ScheduleID INT REFERENCES MaintenanceSchedules(ScheduleID),

    -- Work order details
    WorkOrderType NVARCHAR(20) DEFAULT 'Preventive', -- Preventive, Corrective, Predictive
    Priority NVARCHAR(10) DEFAULT 'Medium', -- Low, Medium, High, Critical
    Title NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Scheduling
    RequestedDate DATETIME2 DEFAULT GETDATE(),
    ScheduledDate DATETIME2,
    DueDate DATETIME2,
    CompletedDate DATETIME2,

    -- Assignment and labor
    AssignedTo INT,
    ActualLaborHours DECIMAL(6,2),
    EstimatedLaborHours DECIMAL(6,2),

    -- Costs
    PartsCost DECIMAL(10,2) DEFAULT 0,
    LaborCost DECIMAL(10,2) DEFAULT 0,
    TotalCost DECIMAL(12,2),

    -- Status tracking
    Status NVARCHAR(20) DEFAULT 'Open', -- Open, Scheduled, InProgress, Completed, Cancelled
    DowntimeHours DECIMAL(6,2) DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_MaintenanceWorkOrders_Type CHECK (WorkOrderType IN ('Preventive', 'Corrective', 'Predictive', 'Emergency')),
    CONSTRAINT CK_MaintenanceWorkOrders_Priority CHECK (Priority IN ('Low', 'Medium', 'High', 'Critical')),
    CONSTRAINT CK_MaintenanceWorkOrders_Status CHECK (Status IN ('Open', 'Scheduled', 'InProgress', 'Completed', 'Cancelled', 'OnHold')),

    -- Indexes
    INDEX IX_MaintenanceWorkOrders_Number (WorkOrderNumber),
    INDEX IX_MaintenanceWorkOrders_Equipment (EquipmentID),
    INDEX IX_MaintenanceWorkOrders_Type (WorkOrderType),
    INDEX IX_MaintenanceWorkOrders_Status (Status),
    INDEX IX_MaintenanceWorkOrders_Priority (Priority),
    INDEX IX_MaintenanceWorkOrders_ScheduledDate (ScheduledDate),
    INDEX IX_MaintenanceWorkOrders_DueDate (DueDate)
);

-- =============================================
-- INVENTORY & MATERIALS MANAGEMENT
-- =============================================

-- Raw materials and components
CREATE TABLE Materials (
    MaterialID INT IDENTITY(1,1) PRIMARY KEY,
    MaterialCode NVARCHAR(50) UNIQUE NOT NULL,
    MaterialName NVARCHAR(200) NOT NULL,
    MaterialType NVARCHAR(20) DEFAULT 'Raw', -- Raw, Component, Packaging, Consumable

    -- Specifications
    UnitOfMeasure NVARCHAR(20) DEFAULT 'Each',
    UnitCost DECIMAL(10,2),
    LeadTimeDays INT DEFAULT 0,

    -- Inventory controls
    ReorderPoint INT DEFAULT 0,
    SafetyStock INT DEFAULT 0,
    MaximumStock INT,

    -- Supplier information
    PrimarySupplierID INT,
    AlternateSupplierID INT,

    -- Quality and compliance
    QualitySpecifications NVARCHAR(MAX), -- JSON formatted specs
    IsCertified BIT DEFAULT 0,
    CertificateNumber NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_Materials_Type CHECK (MaterialType IN ('Raw', 'Component', 'Packaging', 'Consumable', 'MRO')),

    -- Indexes
    INDEX IX_Materials_Code (MaterialCode),
    INDEX IX_Materials_Type (MaterialType),
    INDEX IX_Materials_Supplier (PrimarySupplierID)
);

-- Material inventory
CREATE TABLE MaterialInventory (
    InventoryID INT IDENTITY(1,1) PRIMARY KEY,
    MaterialID INT NOT NULL REFERENCES Materials(MaterialID),
    LocationID INT NOT NULL,

    -- Stock levels
    QuantityOnHand DECIMAL(12,4) DEFAULT 0,
    QuantityReserved DECIMAL(12,4) DEFAULT 0,
    QuantityAvailable AS (QuantityOnHand - QuantityReserved),
    QuantityOnOrder DECIMAL(12,4) DEFAULT 0,

    -- Tracking
    LastCountDate DATETIME2,
    LastCountQuantity DECIMAL(12,4),
    LastMovementDate DATETIME2,

    -- Location-specific costs
    UnitCost DECIMAL(10,2),
    LastReceiptDate DATETIME2,

    -- Constraints
    CONSTRAINT UQ_MaterialInventory_MaterialLocation UNIQUE (MaterialID, LocationID),
    CONSTRAINT CK_MaterialInventory_OnHand CHECK (QuantityOnHand >= 0),
    CONSTRAINT CK_MaterialInventory_Reserved CHECK (QuantityReserved >= 0),
    CONSTRAINT CK_MaterialInventory_OnOrder CHECK (QuantityOnOrder >= 0),

    -- Indexes
    INDEX IX_MaterialInventory_Material (MaterialID),
    INDEX IX_MaterialInventory_Location (LocationID),
    INDEX IX_MaterialInventory_Available (QuantityAvailable),
    INDEX IX_MaterialInventory_LastMovement (LastMovementDate)
);

-- Material transactions
CREATE TABLE MaterialTransactions (
    TransactionID INT IDENTITY(1,1) PRIMARY KEY,
    MaterialID INT NOT NULL REFERENCES Materials(MaterialID),
    LocationID INT NOT NULL,
    TransactionType NVARCHAR(20) NOT NULL, -- Receipt, Issue, Transfer, Adjustment, Return

    -- Transaction details
    Quantity DECIMAL(12,4) NOT NULL,
    UnitCost DECIMAL(10,2),
    ReferenceNumber NVARCHAR(50), -- PO, SO, WO number
    ReferenceType NVARCHAR(20), -- PurchaseOrder, SalesOrder, WorkOrder, Transfer

    -- Source/Destination
    FromLocationID INT,
    ToLocationID INT,
    SupplierID INT,

    -- Transaction metadata
    TransactionDate DATETIME2 DEFAULT GETDATE(),
    AuthorizedBy INT,
    Notes NVARCHAR(MAX),

    -- Before/after quantities for audit
    QuantityBefore DECIMAL(12,4),
    QuantityAfter DECIMAL(12,4),

    -- Constraints
    CONSTRAINT CK_MaterialTransactions_Type CHECK (TransactionType IN ('Receipt', 'Issue', 'Transfer', 'Adjustment', 'Return', 'Scrap', 'WriteOff')),

    -- Indexes
    INDEX IX_MaterialTransactions_Material (MaterialID),
    INDEX IX_MaterialTransactions_Location (LocationID),
    INDEX IX_MaterialTransactions_Type (TransactionType),
    INDEX IX_MaterialTransactions_Date (TransactionDate),
    INDEX IX_MaterialTransactions_Reference (ReferenceNumber, ReferenceType)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Production order status view
CREATE VIEW vw_ProductionOrderStatus
AS
SELECT
    po.OrderID,
    po.OrderNumber,
    po.OrderType,
    po.Priority,
    po.Status,
    po.PlannedQuantity,
    po.ActualQuantity,
    po.ProgressPercentage,
    po.PlannedStartDate,
    po.PlannedEndDate,
    po.ActualStartDate,
    po.ActualEndDate,

    -- Status indicators
    CASE
        WHEN po.Status = 'Completed' THEN 'Complete'
        WHEN po.ActualEndDate > po.PlannedEndDate THEN 'Delayed'
        WHEN po.ProgressPercentage < 50 AND GETDATE() > DATEADD(DAY, 7, po.PlannedStartDate) THEN 'At Risk'
        ELSE 'On Track'
    END AS StatusIndicator,

    -- Days remaining
    CASE
        WHEN po.Status IN ('Completed', 'Cancelled') THEN NULL
        WHEN po.ActualEndDate IS NOT NULL THEN DATEDIFF(DAY, po.PlannedEndDate, po.ActualEndDate)
        ELSE DATEDIFF(DAY, GETDATE(), po.PlannedEndDate)
    END AS DaysVariance

FROM ProductionOrders po
WHERE po.Status NOT IN ('Cancelled');
GO

-- Equipment performance view
CREATE VIEW vw_EquipmentPerformance
AS
SELECT
    e.EquipmentID,
    e.EquipmentCode,
    e.EquipmentName,
    e.EquipmentType,
    e.Status,
    e.Criticality,
    e.Availability,
    e.MTBF,
    e.MTTR,

    -- Recent maintenance
    (SELECT COUNT(*) FROM MaintenanceWorkOrders mwo
     WHERE mwo.EquipmentID = e.EquipmentID AND mwo.Status = 'Completed'
     AND mwo.CompletedDate >= DATEADD(MONTH, -3, GETDATE())) AS MaintenanceLast3Months,

    -- Open work orders
    (SELECT COUNT(*) FROM MaintenanceWorkOrders mwo
     WHERE mwo.EquipmentID = e.EquipmentID AND mwo.Status IN ('Open', 'Scheduled', 'InProgress')) AS OpenWorkOrders,

    -- OEE calculation (simplified)
    CASE
        WHEN e.Availability > 0 THEN e.Availability * 0.9 * 0.95 -- Assuming 90% performance, 95% quality
        ELSE 0
    END AS EstimatedOEE

FROM Equipment e
WHERE e.Status != 'Retired';
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update production order progress
CREATE TRIGGER TR_RoutingOperations_UpdateProgress
ON RoutingOperations
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- This would typically be called from production tracking system
    -- Simplified example for progress calculation
    UPDATE po
    SET po.LastModifiedDate = GETDATE()
    FROM ProductionOrders po
    WHERE po.OrderID IN (
        SELECT DISTINCT ro.RoutingID
        FROM inserted i
        INNER JOIN RoutingOperations ro ON i.OperationID = ro.OperationID
    );
END;
GO

-- Update material inventory on transactions
CREATE TRIGGER TR_MaterialTransactions_UpdateInventory
ON MaterialTransactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Update inventory based on transaction type
    UPDATE mi
    SET mi.QuantityOnHand = CASE
            WHEN i.TransactionType = 'Receipt' THEN mi.QuantityOnHand + i.Quantity
            WHEN i.TransactionType = 'Issue' THEN mi.QuantityOnHand - i.Quantity
            WHEN i.TransactionType = 'Transfer' THEN mi.QuantityOnHand - i.Quantity
            WHEN i.TransactionType = 'Return' THEN mi.QuantityOnHand + i.Quantity
            WHEN i.TransactionType = 'Adjustment' THEN i.QuantityAfter
            ELSE mi.QuantityOnHand
        END,
        mi.LastMovementDate = GETDATE(),
        mi.LastReceiptDate = CASE
            WHEN i.TransactionType = 'Receipt' THEN GETDATE()
            ELSE mi.LastReceiptDate
        END
    FROM MaterialInventory mi
    INNER JOIN inserted i ON mi.MaterialID = i.MaterialID AND mi.LocationID = i.LocationID;
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Create production order procedure
CREATE PROCEDURE sp_CreateProductionOrder
    @ProductID INT,
    @PlannedQuantity INT,
    @PlannedStartDate DATETIME2,
    @PlannedEndDate DATETIME2,
    @Priority NVARCHAR(10) = 'Normal',
    @CustomerID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderNumber NVARCHAR(50);

    -- Generate order number
    SET @OrderNumber = 'PROD-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                      RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                      RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    -- Calculate planned cost from BOM
    DECLARE @PlannedCost DECIMAL(12,2) = 0;

    SELECT @PlannedCost = ISNULL(SUM(bc.QuantityRequired * bc.UnitCost), 0)
    FROM BillOfMaterials bom
    INNER JOIN BOMComponents bc ON bom.BOMID = bc.BOMID
    WHERE bom.ProductID = @ProductID AND bom.IsActive = 1;

    INSERT INTO ProductionOrders (
        OrderNumber, ProductID, PlannedQuantity, PlannedStartDate, PlannedEndDate,
        Priority, PlannedCost, CustomerID
    )
    VALUES (
        @OrderNumber, @ProductID, @PlannedQuantity, @PlannedStartDate, @PlannedEndDate,
        @Priority, @PlannedCost, @CustomerID
    );

    SELECT SCOPE_IDENTITY() AS OrderID, @OrderNumber AS OrderNumber;
END;
GO

-- Create maintenance work order procedure
CREATE PROCEDURE sp_CreateMaintenanceWorkOrder
    @EquipmentID INT,
    @Title NVARCHAR(200),
    @Description NVARCHAR(MAX),
    @WorkOrderType NVARCHAR(20) = 'Preventive',
    @Priority NVARCHAR(10) = 'Medium',
    @DueDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @WorkOrderNumber NVARCHAR(50);

    -- Generate work order number
    SET @WorkOrderNumber = 'MWO-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                          RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                          RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    INSERT INTO MaintenanceWorkOrders (
        WorkOrderNumber, EquipmentID, Title, Description, WorkOrderType,
        Priority, DueDate
    )
    VALUES (
        @WorkOrderNumber, @EquipmentID, @Title, @Description, @WorkOrderType,
        @Priority, @DueDate
    );

    SELECT SCOPE_IDENTITY() AS WorkOrderID, @WorkOrderNumber AS WorkOrderNumber;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample equipment
INSERT INTO Equipment (EquipmentCode, EquipmentName, EquipmentType, Manufacturer, Model, Criticality) VALUES
('EQ-001', 'CNC Milling Machine', 'Machine', 'Haas', 'VF-2', 'High'),
('EQ-002', 'Quality Inspection Station', 'Machine', 'Mitutoyo', 'CMM-500', 'Medium');

-- Insert sample material
INSERT INTO Materials (MaterialCode, MaterialName, MaterialType, UnitOfMeasure, UnitCost, ReorderPoint) VALUES
('MAT-001', 'Aluminum Sheet 6061', 'Raw', 'Sheet', 45.50, 100),
('MAT-002', 'Steel Bolts M10', 'Component', 'Each', 0.25, 500);

-- Insert sample production order
INSERT INTO ProductionOrders (OrderNumber, ProductID, PlannedQuantity, PlannedStartDate, PlannedEndDate, Priority) VALUES
('PROD-202412-00001', 1, 500, '2024-12-01', '2024-12-15', 'High');

-- Insert sample BOM
INSERT INTO BillOfMaterials (ProductID, Version, TotalCost) VALUES
(1, '1.0', 225.75);

-- Insert sample BOM component
INSERT INTO BOMComponents (BOMID, MaterialID, ComponentType, QuantityRequired, UnitOfMeasure, UnitCost) VALUES
(1, 1, 'Material', 2.5, 'Sheet', 45.50),
(1, 2, 'Material', 10, 'Each', 0.25);

PRINT 'Manufacturing database schema created successfully!';
GO
