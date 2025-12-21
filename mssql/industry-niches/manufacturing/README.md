# Manufacturing & Production Platform Database Design

## Overview

This comprehensive database schema supports modern manufacturing and production platforms including production planning, quality control, inventory management, equipment monitoring, and supply chain optimization. The design handles complex production workflows, quality assurance processes, maintenance scheduling, and enterprise manufacturing operations.

## Key Features

### 🏭 Production Planning & Execution
- **Production scheduling** with capacity planning, resource allocation, and bottleneck management
- **Work order management** with bill of materials, routing, and production tracking
- **Quality control processes** with inspection plans, testing procedures, and defect tracking
- **Performance monitoring** with OEE (Overall Equipment Effectiveness) calculations

### 📊 Inventory & Supply Chain Management
- **Raw materials tracking** with supplier management, procurement, and stock levels
- **Work-in-progress inventory** with production stage tracking and costing
- **Finished goods management** with warehousing, distribution, and sales integration
- **Supplier performance monitoring** with quality metrics and delivery tracking

### 🔧 Equipment & Maintenance Management
- **Asset management** with equipment hierarchy, specifications, and documentation
- **Preventive maintenance scheduling** with work orders, parts management, and technician assignments
- **Downtime tracking** with root cause analysis and MTTR/MTBF calculations
- **Calibration and certification** management for critical equipment

## Database Schema Highlights

### Core Tables

#### Production Planning & Execution
```sql
-- Production orders master table
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

-- Production routing and operations
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
```

#### Quality Control & Inspection
```sql
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

-- Quality defects and non-conformances
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
```

### Equipment & Maintenance Management

#### Equipment Assets
```sql
-- Manufacturing equipment and assets
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

-- Equipment maintenance schedules
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
```

### Inventory & Supply Chain

#### Materials & Inventory Management
```sql
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

-- Material inventory by location
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
```

## Integration Points

### External Systems
- **ERP Systems**: SAP, Oracle, Microsoft Dynamics for financial and operational integration
- **PLM Systems**: Product lifecycle management for BOM and routing data
- **MES Systems**: Manufacturing execution systems for real-time production tracking
- **SCADA Systems**: Supervisory control and data acquisition for equipment monitoring
- **IoT Platforms**: Sensor data integration for predictive maintenance
- **Quality Management**: Integration with quality control and compliance systems

### API Endpoints
- **Production APIs**: Order management, scheduling, progress tracking
- **Inventory APIs**: Stock levels, material movements, reorder alerts
- **Quality APIs**: Inspection results, defect tracking, compliance reporting
- **Maintenance APIs**: Work orders, equipment status, preventive scheduling
- **Analytics APIs**: Production metrics, equipment performance, quality trends

## Monitoring & Analytics

### Key Performance Indicators
- **Production Efficiency**: OEE (Overall Equipment Effectiveness), cycle time, throughput
- **Quality Performance**: Defect rates, first-pass yield, customer complaints
- **Maintenance Effectiveness**: MTBF, MTTR, preventive maintenance compliance
- **Inventory Performance**: Inventory turnover, stockout rates, carrying costs
- **Supplier Performance**: On-time delivery, quality acceptance, lead times

### Real-Time Dashboards
```sql
-- Manufacturing operations dashboard
CREATE VIEW ManufacturingOperationsDashboard AS
SELECT
    -- Production metrics (current month)
    (SELECT COUNT(*) FROM ProductionOrders
     WHERE MONTH(CreatedDate) = MONTH(GETDATE())
     AND YEAR(CreatedDate) = YEAR(GETDATE())) AS OrdersCreatedThisMonth,

    (SELECT COUNT(*) FROM ProductionOrders
     WHERE Status = 'Completed'
     AND MONTH(CompletedDate) = MONTH(GETDATE())) AS OrdersCompletedThisMonth,

    (SELECT AVG(ProgressPercentage) FROM ProductionOrders
     WHERE Status IN ('InProgress', 'Released')) AS AvgOrderProgress,

    (SELECT SUM(ActualQuantity) FROM ProductionOrders
     WHERE Status = 'Completed'
     AND MONTH(CompletedDate) = MONTH(GETDATE())) AS UnitsProducedThisMonth,

    -- Quality metrics (current month)
    (SELECT COUNT(*) FROM QualityInspections
     WHERE MONTH(InspectionDate) = MONTH(GETDATE())
     AND YEAR(InspectionDate) = YEAR(GETDATE())) AS InspectionsThisMonth,

    (SELECT COUNT(*) FROM QualityInspections
     WHERE Result = 'Fail'
     AND MONTH(InspectionDate) = MONTH(GETDATE())) AS FailedInspectionsThisMonth,

    (SELECT COUNT(*) FROM QualityDefects
     WHERE MONTH(ResolvedDate) = MONTH(GETDATE())) AS DefectsResolvedThisMonth,

    -- Equipment performance
    (SELECT COUNT(*) FROM Equipment WHERE Status = 'Active') AS ActiveEquipment,

    (SELECT COUNT(*) FROM Equipment WHERE Status = 'Down') AS EquipmentDown,

    (SELECT COUNT(*) FROM MaintenanceWorkOrders
     WHERE Status = 'Open' AND Priority IN ('High', 'Critical')) AS UrgentMaintenanceOrders,

    (SELECT AVG(Availability) FROM Equipment WHERE Availability > 0) AS AvgEquipmentAvailability,

    -- Inventory metrics
    (SELECT COUNT(*) FROM MaterialInventory
     WHERE QuantityOnHand <= ReorderPoint) AS ItemsBelowReorderPoint,

    (SELECT SUM(QuantityOnHand * UnitCost) FROM MaterialInventory) AS TotalInventoryValue,

    (SELECT COUNT(*) FROM MaterialTransactions
     WHERE TransactionType = 'Issue'
     AND CAST(TransactionDate AS DATE) = CAST(GETDATE() AS DATE)) AS MaterialIssuesToday

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This manufacturing database schema provides a comprehensive foundation for modern production platforms, supporting complex manufacturing operations, quality management, equipment maintenance, and enterprise production analytics while maintaining high performance and operational efficiency.
