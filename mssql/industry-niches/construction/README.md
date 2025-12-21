# Construction & Project Management Platform Database Design

## Overview

This comprehensive database schema supports modern construction and project management platforms including project planning, resource allocation, subcontractor management, safety tracking, and construction operations. The design handles complex project workflows, regulatory compliance, cost control, and enterprise construction management.

## Key Features

### 🏗️ Project Management & Planning
- **Project lifecycle management** with planning, execution, monitoring, and completion phases
- **Work breakdown structure** with tasks, subtasks, and dependency management
- **Resource allocation** with labor, equipment, and material scheduling
- **Progress tracking** with milestones, deliverables, and performance metrics

### 📋 Contractor & Subcontractor Management
- **Contractor qualification** with licensing, insurance, and performance tracking
- **Subcontractor coordination** with bidding, awards, and contract management
- **Vendor relationships** with procurement, delivery, and quality assurance
- **Compliance monitoring** with certifications, safety records, and regulatory adherence

### 🔧 Safety & Quality Management
- **Safety incident tracking** with reporting, investigation, and corrective actions
- **Quality control processes** with inspections, testing, and defect management
- **Regulatory compliance** with permits, inspections, and documentation
- **Training and certification** tracking for personnel and equipment

## Database Schema Highlights

### Core Tables

#### Project Management
```sql
-- Construction projects master table
CREATE TABLE Projects (
    ProjectID INT IDENTITY(1,1) PRIMARY KEY,
    ProjectNumber NVARCHAR(50) UNIQUE NOT NULL,
    ProjectName NVARCHAR(200) NOT NULL,
    ProjectType NVARCHAR(50) DEFAULT 'Construction', -- Construction, Renovation, Maintenance, Infrastructure

    -- Project details
    Description NVARCHAR(MAX),
    Location NVARCHAR(MAX), -- JSON formatted address and coordinates
    StartDate DATE,
    EndDate DATE,
    PlannedCompletionDate DATE,
    ActualCompletionDate DATE,

    -- Project scope and scale
    TotalArea DECIMAL(12,2), -- Square feet/meters
    TotalBudget DECIMAL(15,2),
    ContractValue DECIMAL(15,2),
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Project status and progress
    Status NVARCHAR(20) DEFAULT 'Planning', -- Planning, Approved, InProgress, OnHold, Completed, Cancelled
    ProgressPercentage DECIMAL(5,2) DEFAULT 0,
    Priority NVARCHAR(10) DEFAULT 'Medium', -- Low, Medium, High, Critical

    -- Client and ownership
    ClientID INT,
    ProjectManagerID INT,
    ArchitectID INT,
    EngineerID INT,

    -- Financial tracking
    BudgetConsumed DECIMAL(15,2) DEFAULT 0,
    InvoicedAmount DECIMAL(15,2) DEFAULT 0,
    PaidAmount DECIMAL(15,2) DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Projects_Type CHECK (ProjectType IN ('Construction', 'Renovation', 'Maintenance', 'Infrastructure', 'Demolition')),
    CONSTRAINT CK_Projects_Status CHECK (Status IN ('Planning', 'Approved', 'InProgress', 'OnHold', 'Completed', 'Cancelled')),
    CONSTRAINT CK_Projects_Priority CHECK (Priority IN ('Low', 'Medium', 'High', 'Critical')),
    CONSTRAINT CK_Projects_Progress CHECK (ProgressPercentage BETWEEN 0 AND 100),
    CONSTRAINT CK_Projects_Dates CHECK (EndDate >= StartDate),

    -- Indexes
    INDEX IX_Projects_Number (ProjectNumber),
    INDEX IX_Projects_Name (ProjectName),
    INDEX IX_Projects_Type (ProjectType),
    INDEX IX_Projects_Status (Status),
    INDEX IX_Projects_StartDate (StartDate),
    INDEX IX_Projects_EndDate (EndDate),
    INDEX IX_Projects_Client (ClientID),
    INDEX IX_Projects_Manager (ProjectManagerID)
);

-- Work breakdown structure (WBS)
CREATE TABLE WBSItems (
    WBSID INT IDENTITY(1,1) PRIMARY KEY,
    ProjectID INT NOT NULL REFERENCES Projects(ProjectID) ON DELETE CASCADE,
    WBSCode NVARCHAR(50) NOT NULL,
    WBSName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Hierarchy
    ParentWBSID INT REFERENCES WBSItems(WBSID),
    Level INT NOT NULL DEFAULT 1,
    Sequence INT,

    -- Scope and details
    PlannedStartDate DATE,
    PlannedEndDate DATE,
    ActualStartDate DATE,
    ActualEndDate DATE,
    PlannedCost DECIMAL(12,2),
    ActualCost DECIMAL(12,2),

    -- Progress and status
    Status NVARCHAR(20) DEFAULT 'NotStarted', -- NotStarted, InProgress, Completed, OnHold, Cancelled
    ProgressPercentage DECIMAL(5,2) DEFAULT 0,
    AssignedTo INT, -- Contractor or internal team

    -- Quality and deliverables
    QualityRequirements NVARCHAR(MAX), -- JSON formatted requirements
    Deliverables NVARCHAR(MAX), -- JSON array of deliverables
    CompletionCriteria NVARCHAR(MAX), -- JSON formatted criteria

    -- Constraints
    CONSTRAINT CK_WBSItems_Status CHECK (Status IN ('NotStarted', 'InProgress', 'Completed', 'OnHold', 'Cancelled')),
    CONSTRAINT CK_WBSItems_Progress CHECK (ProgressPercentage BETWEEN 0 AND 100),
    CONSTRAINT UQ_WBSItems_Code UNIQUE (ProjectID, WBSCode),

    -- Indexes
    INDEX IX_WBSItems_Project (ProjectID),
    INDEX IX_WBSItems_Code (WBSCode),
    INDEX IX_WBSItems_Parent (ParentWBSID),
    INDEX IX_WBSItems_Status (Status),
    INDEX IX_WBSItems_AssignedTo (AssignedTo),
    INDEX IX_WBSItems_PlannedStart (PlannedStartDate)
);
```

#### Contractor & Vendor Management
```sql
-- Contractors and subcontractors
CREATE TABLE Contractors (
    ContractorID INT IDENTITY(1,1) PRIMARY KEY,
    ContractorNumber NVARCHAR(50) UNIQUE NOT NULL,
    CompanyName NVARCHAR(200) NOT NULL,
    ContactPerson NVARCHAR(100),

    -- Company details
    BusinessType NVARCHAR(50), -- General, Electrical, Plumbing, HVAC, etc.
    LicenseNumber NVARCHAR(100),
    LicenseExpiry DATE,
    InsuranceExpiry DATE,
    BondAmount DECIMAL(12,2),

    -- Contact information
    Address NVARCHAR(MAX), -- JSON formatted
    Phone NVARCHAR(20),
    Email NVARCHAR(255),
    Website NVARCHAR(500),

    -- Qualifications and certifications
    Certifications NVARCHAR(MAX), -- JSON array
    Specializations NVARCHAR(MAX), -- JSON array
    EquipmentCapabilities NVARCHAR(MAX), -- JSON array

    -- Performance and rating
    Rating DECIMAL(3,2) CHECK (Rating BETWEEN 1.00 AND 5.00),
    TotalProjects INT DEFAULT 0,
    CompletedProjects INT DEFAULT 0,
    OnTimeDeliveryRate DECIMAL(5,4), -- 0.0000 to 1.0000
    QualityRating DECIMAL(3,2),

    -- Financial
    CreditLimit DECIMAL(12,2),
    PaymentTerms NVARCHAR(100),
    TaxID NVARCHAR(50),

    -- Status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Suspended, Terminated, Blacklisted
    IsPreferred BIT DEFAULT 0,
    IsCertified BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Contractors_Type CHECK (BusinessType IN ('General', 'Electrical', 'Plumbing', 'HVAC', 'Carpentry', 'Masonry', 'Roofing', 'Painting', 'Landscaping', 'Concrete')),
    CONSTRAINT CK_Contractors_Status CHECK (Status IN ('Active', 'Suspended', 'Terminated', 'Blacklisted')),
    CONSTRAINT CK_Contractors_Ratings CHECK (OnTimeDeliveryRate BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_Contractors_Number (ContractorNumber),
    INDEX IX_Contractors_Name (CompanyName),
    INDEX IX_Contractors_Type (BusinessType),
    INDEX IX_Contractors_Status (Status),
    INDEX IX_Contractors_IsPreferred (IsPreferred),
    INDEX IX_Contractors_Rating (Rating DESC)
);

-- Contractor-project relationships
CREATE TABLE ProjectContractors (
    ProjectContractorID INT IDENTITY(1,1) PRIMARY KEY,
    ProjectID INT NOT NULL REFERENCES Projects(ProjectID),
    ContractorID INT NOT NULL REFERENCES Contractors(ContractorID),

    -- Contract details
    ContractType NVARCHAR(20) DEFAULT 'Subcontract', -- Prime, Subcontract, Supplier
    ScopeOfWork NVARCHAR(MAX),
    ContractValue DECIMAL(12,2),
    ContractDate DATE,
    StartDate DATE,
    EndDate DATE,

    -- Financial tracking
    PaidAmount DECIMAL(12,2) DEFAULT 0,
    InvoicedAmount DECIMAL(12,2) DEFAULT 0,
    RetentionAmount DECIMAL(12,2) DEFAULT 0,

    -- Performance tracking
    Status NVARCHAR(20) DEFAULT 'Awarded', -- Awarded, Active, Completed, Terminated
    PerformanceRating DECIMAL(3,2),
    OnTimeCompletion BIT,
    QualityRating DECIMAL(3,2),

    -- Constraints
    CONSTRAINT CK_ProjectContractors_Type CHECK (ContractType IN ('Prime', 'Subcontract', 'Supplier', 'Consultant')),
    CONSTRAINT CK_ProjectContractors_Status CHECK (Status IN ('Awarded', 'Active', 'Completed', 'Terminated')),
    CONSTRAINT UQ_ProjectContractors_Unique UNIQUE (ProjectID, ContractorID),

    -- Indexes
    INDEX IX_ProjectContractors_Project (ProjectID),
    INDEX IX_ProjectContractors_Contractor (ContractorID),
    INDEX IX_ProjectContractors_Type (ContractType),
    INDEX IX_ProjectContractors_Status (Status),
    INDEX IX_ProjectContractors_StartDate (StartDate)
);
```

#### Safety & Quality Management
```sql
-- Safety incidents and accidents
CREATE TABLE SafetyIncidents (
    IncidentID INT IDENTITY(1,1) PRIMARY KEY,
    IncidentNumber NVARCHAR(50) UNIQUE NOT NULL,
    ProjectID INT NOT NULL REFERENCES Projects(ProjectID),

    -- Incident details
    IncidentDate DATETIME2 NOT NULL,
    IncidentTime TIME,
    Location NVARCHAR(200),
    ReportedBy INT NOT NULL,
    IncidentType NVARCHAR(50) NOT NULL, -- Accident, NearMiss, Hazard, PropertyDamage

    -- Description and severity
    Description NVARCHAR(MAX),
    Severity NVARCHAR(20) DEFAULT 'Minor', -- Minor, Serious, Critical, Fatal
    ImmediateActions NVARCHAR(MAX),
    RootCause NVARCHAR(MAX),
    ContributingFactors NVARCHAR(MAX),

    -- Affected parties
    InjuredPerson NVARCHAR(100),
    InjuryType NVARCHAR(50), -- None, Minor, Major, Fatal
    MedicalTreatment BIT DEFAULT 0,
    LostTimeDays INT DEFAULT 0,

    -- Investigation and resolution
    InvestigationStatus NVARCHAR(20) DEFAULT 'Open', -- Open, Investigating, Closed
    AssignedInvestigator INT,
    CorrectiveActions NVARCHAR(MAX), -- JSON array
    PreventiveMeasures NVARCHAR(MAX), -- JSON array
    ResolutionDate DATETIME2,

    -- Financial impact
    CostOfIncident DECIMAL(10,2),
    InsuranceClaimed BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_SafetyIncidents_Type CHECK (IncidentType IN ('Accident', 'NearMiss', 'Hazard', 'PropertyDamage', 'Environmental', 'EquipmentFailure')),
    CONSTRAINT CK_SafetyIncidents_Severity CHECK (Severity IN ('Minor', 'Moderate', 'Serious', 'Critical', 'Fatal')),
    CONSTRAINT CK_SafetyIncidents_Status CHECK (InvestigationStatus IN ('Open', 'Investigating', 'Closed')),
    CONSTRAINT CK_SafetyIncidents_Injury CHECK (InjuryType IN ('None', 'Minor', 'Major', 'Fatal')),

    -- Indexes
    INDEX IX_SafetyIncidents_Number (IncidentNumber),
    INDEX IX_SafetyIncidents_Project (ProjectID),
    INDEX IX_SafetyIncidents_Type (IncidentType),
    INDEX IX_SafetyIncidents_Severity (Severity),
    INDEX IX_SafetyIncidents_Status (InvestigationStatus),
    INDEX IX_SafetyIncidents_Date (IncidentDate)
);

-- Quality inspections and audits
CREATE TABLE QualityInspections (
    InspectionID INT IDENTITY(1,1) PRIMARY KEY,
    InspectionNumber NVARCHAR(50) UNIQUE NOT NULL,
    ProjectID INT NOT NULL REFERENCES Projects(ProjectID),
    WBSID INT REFERENCES WBSItems(WBSID),

    -- Inspection details
    InspectionType NVARCHAR(50) NOT NULL, -- Internal, External, Regulatory, Progress
    ScheduledDate DATETIME2 NOT NULL,
    ActualDate DATETIME2,
    Inspector NVARCHAR(100),
    InspectionAgency NVARCHAR(100),

    -- Scope and coverage
    InspectionScope NVARCHAR(MAX), -- What is being inspected
    Standards NVARCHAR(MAX), -- JSON array of applicable standards
    Checkpoints NVARCHAR(MAX), -- JSON array of inspection points

    -- Results
    Status NVARCHAR(20) DEFAULT 'Scheduled', -- Scheduled, Passed, Failed, Conditional, Rescheduled
    OverallResult NVARCHAR(10), -- Pass, Fail
    Findings NVARCHAR(MAX), -- JSON array of findings
    NonConformities NVARCHAR(MAX), -- JSON array of issues

    -- Follow-up
    CorrectiveActions NVARCHAR(MAX), -- JSON array of required actions
    FollowUpDate DATETIME2,
    ReinspectionRequired BIT DEFAULT 0,

    -- Documentation
    ReportURL NVARCHAR(500),
    Photos NVARCHAR(MAX), -- JSON array of photo URLs

    -- Constraints
    CONSTRAINT CK_QualityInspections_Type CHECK (InspectionType IN ('Internal', 'External', 'Regulatory', 'Progress', 'Final')),
    CONSTRAINT CK_QualityInspections_Status CHECK (Status IN ('Scheduled', 'Passed', 'Failed', 'Conditional', 'Rescheduled', 'Cancelled')),
    CONSTRAINT CK_QualityInspections_Result CHECK (OverallResult IN ('Pass', 'Fail')),

    -- Indexes
    INDEX IX_QualityInspections_Number (InspectionNumber),
    INDEX IX_QualityInspections_Project (ProjectID),
    INDEX IX_QualityInspections_Type (InspectionType),
    INDEX IX_QualityInspections_Status (Status),
    INDEX IX_QualityInspections_Scheduled (ScheduledDate),
    INDEX IX_QualityInspections_Result (OverallResult)
);
```

### Resource & Equipment Management

#### Equipment & Tools Tracking
```sql
-- Construction equipment and tools
CREATE TABLE Equipment (
    EquipmentID INT IDENTITY(1,1) PRIMARY KEY,
    EquipmentNumber NVARCHAR(50) UNIQUE NOT NULL,
    EquipmentName NVARCHAR(100) NOT NULL,
    EquipmentType NVARCHAR(50) NOT NULL, -- HeavyEquipment, Tools, Vehicles, SafetyEquipment

    -- Equipment specifications
    Manufacturer NVARCHAR(100),
    Model NVARCHAR(100),
    SerialNumber NVARCHAR(100),
    PurchaseDate DATE,
    PurchaseCost DECIMAL(12,2),

    -- Maintenance and status
    Status NVARCHAR(20) DEFAULT 'Available', -- Available, InUse, Maintenance, OutOfService
    Location NVARCHAR(100),
    AssignedTo INT, -- Project or person
    LastMaintenanceDate DATETIME2,
    NextMaintenanceDate DATETIME2,

    -- Usage tracking
    TotalHours DECIMAL(8,2) DEFAULT 0,
    FuelConsumption DECIMAL(8,2),
    OperatingCostPerHour DECIMAL(8,2),

    -- Safety and compliance
    SafetyCertifications NVARCHAR(MAX), -- JSON array
    InspectionDueDate DATETIME2,
    InsuranceValue DECIMAL(12,2),

    -- Constraints
    CONSTRAINT CK_Equipment_Type CHECK (EquipmentType IN ('HeavyEquipment', 'Tools', 'Vehicles', 'SafetyEquipment', 'Consumables')),
    CONSTRAINT CK_Equipment_Status CHECK (Status IN ('Available', 'InUse', 'Maintenance', 'OutOfService', 'Retired')),

    -- Indexes
    INDEX IX_Equipment_Number (EquipmentNumber),
    INDEX IX_Equipment_Type (EquipmentType),
    INDEX IX_Equipment_Status (Status),
    INDEX IX_Equipment_AssignedTo (AssignedTo),
    INDEX IX_Equipment_NextMaintenance (NextMaintenanceDate)
);

-- Equipment usage and allocation
CREATE TABLE EquipmentUsage (
    UsageID INT IDENTITY(1,1) PRIMARY KEY,
    EquipmentID INT NOT NULL REFERENCES Equipment(EquipmentID),
    ProjectID INT NOT NULL REFERENCES Projects(ProjectID),

    -- Usage period
    StartDate DATETIME2 NOT NULL,
    EndDate DATETIME2,
    PlannedHours DECIMAL(6,2),
    ActualHours DECIMAL(6,2),

    -- Assignment details
    AssignedTo INT, -- Worker or crew
    TaskDescription NVARCHAR(MAX),
    Location NVARCHAR(100),

    -- Usage tracking
    FuelUsed DECIMAL(6,2),
    OperatingCost DECIMAL(8,2),

    -- Status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Completed, Cancelled

    -- Constraints
    CONSTRAINT CK_EquipmentUsage_Status CHECK (Status IN ('Active', 'Completed', 'Cancelled')),

    -- Indexes
    INDEX IX_EquipmentUsage_Equipment (EquipmentID),
    INDEX IX_EquipmentUsage_Project (ProjectID),
    INDEX IX_EquipmentUsage_StartDate (StartDate),
    INDEX IX_EquipmentUsage_EndDate (EndDate),
    INDEX IX_EquipmentUsage_AssignedTo (AssignedTo)
);

-- Material and inventory management
CREATE TABLE Materials (
    MaterialID INT IDENTITY(1,1) PRIMARY KEY,
    MaterialCode NVARCHAR(50) UNIQUE NOT NULL,
    MaterialName NVARCHAR(200) NOT NULL,
    MaterialType NVARCHAR(50) DEFAULT 'Construction', -- Construction, Electrical, Plumbing, etc.

    -- Specifications
    UnitOfMeasure NVARCHAR(20) DEFAULT 'Each',
    UnitCost DECIMAL(10,2),
    Supplier NVARCHAR(100),

    -- Inventory controls
    ReorderPoint INT DEFAULT 0,
    SafetyStock INT DEFAULT 0,
    LeadTimeDays INT DEFAULT 0,

    -- Quality and compliance
    Specifications NVARCHAR(MAX), -- JSON formatted specs
    Certifications NVARCHAR(MAX), -- JSON array
    IsApproved BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_Materials_Type CHECK (MaterialType IN ('Construction', 'Electrical', 'Plumbing', 'HVAC', 'Finishing', 'Safety', 'Tools')),

    -- Indexes
    INDEX IX_Materials_Code (MaterialCode),
    INDEX IX_Materials_Name (MaterialName),
    INDEX IX_Materials_Type (MaterialType),
    INDEX IX_Materials_IsApproved (IsApproved)
);

-- Material usage on projects
CREATE TABLE MaterialUsage (
    UsageID INT IDENTITY(1,1) PRIMARY KEY,
    MaterialID INT NOT NULL REFERENCES Materials(MaterialID),
    ProjectID INT NOT NULL REFERENCES Projects(ProjectID),
    WBSID INT REFERENCES WBSItems(WBSID),

    -- Usage details
    QuantityUsed DECIMAL(12,4) NOT NULL,
    UnitCost DECIMAL(10,2),
    TotalCost DECIMAL(12,2),
    UsageDate DATETIME2 DEFAULT GETDATE(),

    -- Context
    UsedBy INT, -- Worker who used the material
    Purpose NVARCHAR(MAX),
    Location NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_MaterialUsage_Quantity CHECK (QuantityUsed > 0),

    -- Indexes
    INDEX IX_MaterialUsage_Material (MaterialID),
    INDEX IX_MaterialUsage_Project (ProjectID),
    INDEX IX_MaterialUsage_WBS (WBSID),
    INDEX IX_MaterialUsage_Date (UsageDate)
);
```

## Integration Points

### External Systems
- **Project Management Software**: Integration with Primavera P6, Microsoft Project
- **Accounting Systems**: QuickBooks, SAP, Oracle for financial tracking
- **Document Management**: SharePoint, Procore for document control
- **Safety Management**: Integration with OSHA reporting systems
- **Equipment Management**: GPS tracking, telematics, and maintenance systems
- **Regulatory Systems**: Building department APIs, permit tracking systems

### API Endpoints
- **Project Management APIs**: Project creation, progress tracking, resource allocation
- **Contractor APIs**: Qualification management, bidding, performance tracking
- **Safety APIs**: Incident reporting, investigation tracking, compliance monitoring
- **Quality APIs**: Inspection scheduling, results tracking, corrective actions
- **Equipment APIs**: Usage tracking, maintenance scheduling, availability status

## Monitoring & Analytics

### Key Performance Indicators
- **Project Performance**: On-time delivery, budget adherence, quality metrics
- **Safety Metrics**: Incident rates, lost time accidents, safety training completion
- **Contractor Performance**: On-time completion, quality ratings, cost performance
- **Resource Utilization**: Equipment utilization rates, labor productivity, material waste
- **Financial Performance**: Budget vs actual costs, profit margins, cash flow

### Real-Time Dashboards
```sql
-- Construction operations dashboard
CREATE VIEW ConstructionOperationsDashboard AS
SELECT
    -- Project portfolio overview (current active projects)
    (SELECT COUNT(*) FROM Projects WHERE Status IN ('InProgress', 'Approved')) AS ActiveProjects,
    (SELECT SUM(TotalBudget) FROM Projects WHERE Status IN ('InProgress', 'Approved')) AS TotalActiveBudget,
    (SELECT AVG(ProgressPercentage) FROM Projects WHERE Status IN ('InProgress', 'Approved')) AS AvgProjectProgress,

    -- Project status breakdown
    (SELECT COUNT(*) FROM Projects WHERE Status = 'OnHold') AS OnHoldProjects,
    (SELECT COUNT(*) FROM Projects WHERE Status = 'Completed' AND MONTH(ActualCompletionDate) = MONTH(GETDATE())) AS CompletedThisMonth,

    -- Financial performance
    (SELECT SUM(BudgetConsumed) FROM Projects WHERE Status IN ('InProgress', 'Approved')) AS TotalBudgetConsumed,
    (SELECT SUM(InvoicedAmount - PaidAmount) FROM Projects WHERE Status IN ('InProgress', 'Approved')) AS OutstandingInvoices,

    -- Safety metrics (current month)
    (SELECT COUNT(*) FROM SafetyIncidents
     WHERE MONTH(IncidentDate) = MONTH(GETDATE())
     AND YEAR(IncidentDate) = YEAR(GETDATE())) AS SafetyIncidentsThisMonth,

    (SELECT COUNT(*) FROM SafetyIncidents
     WHERE InjuryType IN ('Major', 'Fatal')
     AND MONTH(IncidentDate) = MONTH(GETDATE())) AS SeriousIncidentsThisMonth,

    -- Quality metrics
    (SELECT COUNT(*) FROM QualityInspections
     WHERE OverallResult = 'Fail'
     AND MONTH(ActualDate) = MONTH(GETDATE())) AS FailedInspectionsThisMonth,

    (SELECT COUNT(*) FROM QualityInspections
     WHERE Status = 'Scheduled'
     AND ScheduledDate >= GETDATE()
     AND ScheduledDate <= DATEADD(DAY, 7, GETDATE())) AS InspectionsDueThisWeek,

    -- Contractor performance
    (SELECT COUNT(*) FROM ProjectContractors WHERE Status = 'Active') AS ActiveContracts,
    (SELECT AVG(PerformanceRating) FROM ProjectContractors WHERE PerformanceRating IS NOT NULL AND Status = 'Completed') AS AvgContractorRating,

    -- Equipment utilization
    (SELECT COUNT(*) FROM Equipment WHERE Status = 'InUse') AS EquipmentInUse,
    (SELECT COUNT(*) FROM Equipment WHERE Status = 'Maintenance') AS EquipmentInMaintenance,
    (SELECT COUNT(*) FROM Equipment WHERE NextMaintenanceDate <= DATEADD(DAY, 30, GETDATE())) AS EquipmentDueForMaintenance,

    -- Resource availability
    (SELECT COUNT(*) FROM Equipment WHERE Status = 'Available') AS AvailableEquipment,
    (SELECT AVG(TotalHours) FROM Equipment WHERE Status = 'Available') AS AvgEquipmentUtilization

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This construction database schema provides a comprehensive foundation for modern construction management platforms, supporting project execution, contractor management, safety compliance, and enterprise construction operations while maintaining regulatory compliance and operational efficiency.
