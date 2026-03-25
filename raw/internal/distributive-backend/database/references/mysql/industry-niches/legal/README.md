# Legal Services & Case Management Platform Database Design

## Overview

This comprehensive database schema supports modern legal services and case management platforms including matter management, document assembly, calendar and deadline tracking, client communications, and regulatory compliance. The design handles complex legal workflows, document management, time tracking, and enterprise legal operations.

## Key Features

### ⚖️ Matter & Case Management
- **Comprehensive matter lifecycle management** with case initiation, progress tracking, and resolution
- **Multi-party case handling** with clients, opposing parties, witnesses, and court personnel
- **Case classification and categorization** with practice areas, jurisdictions, and complexity levels
- **Conflict checking and ethical walls** with automated conflict detection and resolution

### 📄 Document Management & Assembly
- **Advanced document assembly** with clause libraries, templates, and automated document generation
- **Version control and redlining** with change tracking and collaboration features
- **Document security and access control** with encryption, digital signatures, and audit trails
- **Integration with court filing systems** and electronic discovery platforms

### 📅 Time Tracking & Billing Management
- **Detailed time entry and tracking** with matter-based billing and productivity analytics
- **Rate management and billing rules** with client-specific rates and retainer tracking
- **Invoice generation and collection** with trust accounting and payment processing
- **Financial reporting and profitability analysis** with matter and client profitability metrics

## Database Schema Highlights

### Core Tables

#### Firm & Practice Management
```sql
-- Legal firms and offices
CREATE TABLE LegalFirms (
    FirmID INT IDENTITY(1,1) PRIMARY KEY,
    FirmCode NVARCHAR(20) UNIQUE NOT NULL,
    FirmName NVARCHAR(200) NOT NULL,
    FirmType NVARCHAR(20) DEFAULT 'LawFirm', -- LawFirm, Corporation, Government

    -- Firm details
    Description NVARCHAR(MAX),
    PracticeAreas NVARCHAR(MAX), -- JSON array of practice areas
    Jurisdictions NVARCHAR(MAX), -- JSON array of licensed jurisdictions

    -- Contact information
    Address NVARCHAR(MAX), -- JSON formatted
    Phone NVARCHAR(20),
    Email NVARCHAR(255),
    Website NVARCHAR(500),

    -- Business details
    BarNumber NVARCHAR(50),
    TaxID NVARCHAR(50),
    InsurancePolicy NVARCHAR(100),

    -- Management
    ManagingPartner NVARCHAR(100),
    OfficeManager NVARCHAR(100),
    BillingContact NVARCHAR(100),

    -- Status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, Dissolved
    FoundedDate DATE,
    IncorporationDate DATE,

    -- Constraints
    CONSTRAINT CK_LegalFirms_Type CHECK (FirmType IN ('LawFirm', 'Corporation', 'Government', 'NonProfit')),
    CONSTRAINT CK_LegalFirms_Status CHECK (Status IN ('Active', 'Inactive', 'Dissolved', 'Merged')),

    -- Indexes
    INDEX IX_LegalFirms_Code (FirmCode),
    INDEX IX_LegalFirms_Name (FirmName),
    INDEX IX_LegalFirms_Type (FirmType),
    INDEX IX_LegalFirms_Status (Status)
);

-- Attorneys and legal professionals
CREATE TABLE Attorneys (
    AttorneyID INT IDENTITY(1,1) PRIMARY KEY,
    AttorneyNumber NVARCHAR(20) UNIQUE NOT NULL,
    FirmID INT NOT NULL REFERENCES LegalFirms(FirmID),

    -- Personal information
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    MiddleName NVARCHAR(100),
    PreferredName NVARCHAR(100),

    -- Professional details
    BarNumber NVARCHAR(50) UNIQUE,
    BarAdmissionDate DATE,
    BarState NVARCHAR(50),
    PracticeAreas NVARCHAR(MAX), -- JSON array

    -- Employment details
    JobTitle NVARCHAR(100), -- Partner, Associate, Paralegal, etc.
    Department NVARCHAR(100),
    HireDate DATE,
    TerminationDate DATE,
    EmploymentStatus NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, Terminated, Retired

    -- Compensation
    HourlyRate DECIMAL(8,2),
    AnnualSalary DECIMAL(10,2),
    BillingRate DECIMAL(8,2), -- May differ from hourly rate

    -- Contact information
    OfficePhone NVARCHAR(20),
    MobilePhone NVARCHAR(20),
    Email NVARCHAR(255),
    OfficeAddress NVARCHAR(MAX), -- JSON formatted

    -- Professional development
    Certifications NVARCHAR(MAX), -- JSON array
    ContinuingEducation NVARCHAR(MAX), -- JSON formatted credits
    LastBarRenewal DATE,

    -- Constraints
    CONSTRAINT CK_Attorneys_Status CHECK (EmploymentStatus IN ('Active', 'Inactive', 'Terminated', 'Retired', 'OnLeave')),
    CONSTRAINT CK_Attorneys_JobTitle CHECK (JobTitle IN ('Partner', 'Associate', 'SeniorAssociate', 'JuniorAssociate', 'Paralegal', 'LegalAssistant', 'Clerk', 'Administrator')),

    -- Indexes
    INDEX IX_Attorneys_Number (AttorneyNumber),
    INDEX IX_Attorneys_Firm (FirmID),
    INDEX IX_Attorneys_BarNumber (BarNumber),
    INDEX IX_Attorneys_Name (LastName, FirstName),
    INDEX IX_Attorneys_Status (EmploymentStatus),
    INDEX IX_Attorneys_Email (Email)
);
```

#### Matter & Case Management
```sql
-- Legal matters and cases
CREATE TABLE LegalMatters (
    MatterID INT IDENTITY(1,1) PRIMARY KEY,
    MatterNumber NVARCHAR(50) UNIQUE NOT NULL,
    FirmID INT NOT NULL REFERENCES LegalFirms(FirmID),

    -- Matter details
    MatterName NVARCHAR(500) NOT NULL,
    MatterDescription NVARCHAR(MAX),
    MatterType NVARCHAR(50) NOT NULL, -- Litigation, Transaction, Regulatory, etc.

    -- Classification
    PracticeArea NVARCHAR(100), -- Corporate, Litigation, IntellectualProperty, etc.
    SubPracticeArea NVARCHAR(100),
    Jurisdiction NVARCHAR(100), -- State, Federal, International
    CourtVenue NVARCHAR(200),

    -- Parties involved
    ClientID INT NOT NULL,
    OpposingParty NVARCHAR(MAX), -- JSON array of opposing parties
    ThirdParties NVARCHAR(MAX), -- JSON array of witnesses, experts, etc.

    -- Case details
    CaseNumber NVARCHAR(100),
    FilingDate DATE,
    CaseStatus NVARCHAR(20) DEFAULT 'Open', -- Open, Closed, Settled, Dismissed

    -- Importance and priority
    Priority NVARCHAR(10) DEFAULT 'Medium', -- Low, Medium, High, Critical
    Complexity NVARCHAR(10) DEFAULT 'Medium', -- Low, Medium, High
    EstimatedValue DECIMAL(15,2),

    -- Assignment
    LeadAttorneyID INT REFERENCES Attorneys(AttorneyID),
    AssignedAttorneys NVARCHAR(MAX), -- JSON array of attorney IDs
    Paralegals NVARCHAR(MAX), -- JSON array of paralegal IDs

    -- Dates and deadlines
    OpenDate DATETIME2 DEFAULT GETDATE(),
    CloseDate DATETIME2,
    StatuteOfLimitations DATE,
    NextCourtDate DATETIME2,
    KeyDeadlines NVARCHAR(MAX), -- JSON array of important dates

    -- Financial
    Budget DECIMAL(12,2),
    BilledAmount DECIMAL(12,2) DEFAULT 0,
    CollectedAmount DECIMAL(12,2) DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_LegalMatters_Type CHECK (MatterType IN ('Litigation', 'Transaction', 'Regulatory', 'Compliance', 'IntellectualProperty', 'Employment', 'RealEstate', 'Bankruptcy', 'Family', 'Criminal')),
    CONSTRAINT CK_LegalMatters_Status CHECK (CaseStatus IN ('Open', 'Closed', 'Settled', 'Dismissed', 'Appealed', 'Pending')),
    CONSTRAINT CK_LegalMatters_Priority CHECK (Priority IN ('Low', 'Medium', 'High', 'Critical')),
    CONSTRAINT CK_LegalMatters_Complexity CHECK (Complexity IN ('Low', 'Medium', 'High')),

    -- Indexes
    INDEX IX_LegalMatters_Number (MatterNumber),
    INDEX IX_LegalMatters_Firm (FirmID),
    INDEX IX_LegalMatters_Type (MatterType),
    INDEX IX_LegalMatters_Status (CaseStatus),
    INDEX IX_LegalMatters_Priority (Priority),
    INDEX IX_LegalMatters_LeadAttorney (LeadAttorneyID),
    INDEX IX_LegalMatters_OpenDate (OpenDate),
    INDEX IX_LegalMatters_CloseDate (CloseDate)
);

-- Matter parties and relationships
CREATE TABLE MatterParties (
    PartyID INT IDENTITY(1,1) PRIMARY KEY,
    MatterID INT NOT NULL REFERENCES LegalMatters(MatterID) ON DELETE CASCADE,

    -- Party details
    PartyType NVARCHAR(50) NOT NULL, -- Client, OpposingParty, Witness, Expert, Judge, etc.
    PartyName NVARCHAR(200) NOT NULL,
    PartyRole NVARCHAR(100), -- Plaintiff, Defendant, Counsel, etc.

    -- Contact information
    ContactInfo NVARCHAR(MAX), -- JSON formatted contact details
    Representation NVARCHAR(MAX), -- JSON: represented by which attorney/firm

    -- Relationship to matter
    InvolvementLevel NVARCHAR(20) DEFAULT 'Primary', -- Primary, Secondary, Tertiary
    DateAdded DATETIME2 DEFAULT GETDATE(),
    DateRemoved DATETIME2,

    -- Status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, Withdrawn, Deceased

    -- Constraints
    CONSTRAINT CK_MatterParties_Type CHECK (PartyType IN ('Client', 'OpposingParty', 'Witness', 'Expert', 'Judge', 'CourtClerk', 'Mediator', 'Arbitrator')),
    CONSTRAINT CK_MatterParties_Involvement CHECK (InvolvementLevel IN ('Primary', 'Secondary', 'Tertiary')),
    CONSTRAINT CK_MatterParties_Status CHECK (Status IN ('Active', 'Inactive', 'Withdrawn', 'Deceased', 'Merged')),

    -- Indexes
    INDEX IX_MatterParties_Matter (MatterID),
    INDEX IX_MatterParties_Type (PartyType),
    INDEX IX_MatterParties_Status (Status)
);

-- Matter milestones and events
CREATE TABLE MatterMilestones (
    MilestoneID INT IDENTITY(1,1) PRIMARY KEY,
    MatterID INT NOT NULL REFERENCES LegalMatters(MatterID) ON DELETE CASCADE,

    -- Milestone details
    MilestoneName NVARCHAR(200) NOT NULL,
    MilestoneDescription NVARCHAR(MAX),
    MilestoneType NVARCHAR(50), -- Filing, Hearing, Discovery, Settlement, etc.

    -- Timing
    PlannedDate DATETIME2,
    ActualDate DATETIME2,
    DueDate DATETIME2,
    ReminderDate DATETIME2,

    -- Status and completion
    Status NVARCHAR(20) DEFAULT 'Pending', -- Pending, Completed, Overdue, Cancelled
    CompletionPercentage DECIMAL(5,2) DEFAULT 0,
    AssignedTo INT REFERENCES Attorneys(AttorneyID),

    -- Documentation
    DocumentsRequired NVARCHAR(MAX), -- JSON array of required documents
    DocumentsAttached NVARCHAR(MAX), -- JSON array of attached documents

    -- Notes and outcomes
    Notes NVARCHAR(MAX),
    Outcome NVARCHAR(MAX), -- JSON formatted outcome details

    -- Constraints
    CONSTRAINT CK_MatterMilestones_Type CHECK (MilestoneType IN ('Filing', 'Hearing', 'Discovery', 'Mediation', 'Arbitration', 'Trial', 'Settlement', 'Appeal', 'Compliance', 'Review')),
    CONSTRAINT CK_MatterMilestones_Status CHECK (Status IN ('Pending', 'InProgress', 'Completed', 'Overdue', 'Cancelled')),
    CONSTRAINT CK_MatterMilestones_Completion CHECK (CompletionPercentage BETWEEN 0 AND 100),

    -- Indexes
    INDEX IX_MatterMilestones_Matter (MatterID),
    INDEX IX_MatterMilestones_Type (MilestoneType),
    INDEX IX_MatterMilestones_Status (Status),
    INDEX IX_MatterMilestones_PlannedDate (PlannedDate),
    INDEX IX_MatterMilestones_DueDate (DueDate),
    INDEX IX_MatterMilestones_AssignedTo (AssignedTo)
);
```

#### Time Tracking & Billing
```sql
-- Time entries
CREATE TABLE TimeEntries (
    TimeEntryID INT IDENTITY(1,1) PRIMARY KEY,
    AttorneyID INT NOT NULL REFERENCES Attorneys(AttorneyID),
    MatterID INT NOT NULL REFERENCES LegalMatters(MatterID),

    -- Time details
    EntryDate DATETIME2 DEFAULT GETDATE(),
    StartTime DATETIME2,
    EndTime DATETIME2,
    DurationHours DECIMAL(6,2), -- Calculated from start/end time

    -- Work description
    ActivityType NVARCHAR(50), -- Research, Drafting, Meeting, Court, etc.
    Description NVARCHAR(MAX),
    Narrative NVARCHAR(MAX), -- Detailed description for billing

    -- Billing details
    IsBillable BIT DEFAULT 1,
    BillingRate DECIMAL(8,2),
    BilledAmount DECIMAL(10,2),
    BillingStatus NVARCHAR(20) DEFAULT 'Unbilled', -- Unbilled, Billed, WrittenOff, NoCharge

    -- Time entry metadata
    Location NVARCHAR(100), -- Office, Court, ClientSite, Remote
    WasOvertime BIT DEFAULT 0,
    RequiresApproval BIT DEFAULT 0,
    ApprovedBy INT REFERENCES Attorneys(AttorneyID),
    ApprovedDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_TimeEntries_ActivityType CHECK (ActivityType IN ('Research', 'Drafting', 'Review', 'Meeting', 'PhoneCall', 'Email', 'CourtAppearance', 'Deposition', 'Discovery', 'Negotiation', 'Travel', 'Administrative')),
    CONSTRAINT CK_TimeEntries_BillingStatus CHECK (BillingStatus IN ('Unbilled', 'Billed', 'WrittenOff', 'NoCharge', 'PendingApproval')),
    CONSTRAINT CK_TimeEntries_Duration CHECK (DurationHours > 0 AND DurationHours <= 24),

    -- Indexes
    INDEX IX_TimeEntries_Attorney (AttorneyID),
    INDEX IX_TimeEntries_Matter (MatterID),
    INDEX IX_TimeEntries_Date (EntryDate),
    INDEX IX_TimeEntries_IsBillable (IsBillable),
    INDEX IX_TimeEntries_BillingStatus (BillingStatus),
    INDEX IX_TimeEntries_ApprovedBy (ApprovedBy)
);

-- Billing rules and rates
CREATE TABLE BillingRules (
    RuleID INT IDENTITY(1,1) PRIMARY KEY,
    ClientID INT NOT NULL,
    MatterID INT REFERENCES LegalMatters(MatterID),

    -- Rule scope
    RuleType NVARCHAR(20) DEFAULT 'Client', -- Client, Matter, PracticeArea
    IsDefault BIT DEFAULT 0,

    -- Rate structure
    HourlyRate DECIMAL(8,2),
    FlatFee DECIMAL(10,2),
    RetainerAmount DECIMAL(12,2),
    MinimumBillingIncrement DECIMAL(4,2) DEFAULT 0.1, -- Bill in 6-minute increments

    -- Activity rates
    ActivityRates NVARCHAR(MAX), -- JSON: different rates for different activities

    -- Billing preferences
    BillableActivities NVARCHAR(MAX), -- JSON: which activities are billable
    NonBillableActivities NVARCHAR(MAX), -- JSON: which activities are not billable
    RoundUpRule NVARCHAR(20) DEFAULT 'Nearest', -- Nearest, AlwaysUp, AlwaysDown

    -- Effective dates
    EffectiveDate DATE DEFAULT CAST(GETDATE() AS DATE),
    EndDate DATE,

    -- Status
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_BillingRules_Type CHECK (RuleType IN ('Client', 'Matter', 'PracticeArea', 'Default')),
    CONSTRAINT CK_BillingRules_RoundUp CHECK (RoundUpRule IN ('Nearest', 'AlwaysUp', 'AlwaysDown')),

    -- Indexes
    INDEX IX_BillingRules_Client (ClientID),
    INDEX IX_BillingRules_Matter (MatterID),
    INDEX IX_BillingRules_Type (RuleType),
    INDEX IX_BillingRules_IsActive (IsActive),
    INDEX IX_BillingRules_EffectiveDate (EffectiveDate)
);

-- Invoices and billing
CREATE TABLE LegalInvoices (
    InvoiceID INT IDENTITY(1,1) PRIMARY KEY,
    InvoiceNumber NVARCHAR(50) UNIQUE NOT NULL,
    MatterID INT NOT NULL REFERENCES LegalMatters(MatterID),

    -- Invoice details
    InvoiceDate DATETIME2 DEFAULT GETDATE(),
    BillingPeriodStart DATETIME2,
    BillingPeriodEnd DATETIME2,
    DueDate DATETIME2,

    -- Financial details
    Subtotal DECIMAL(12,2) NOT NULL,
    Taxes DECIMAL(10,2) DEFAULT 0,
    Expenses DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(12,2) NOT NULL,

    -- Payment details
    PaymentStatus NVARCHAR(20) DEFAULT 'Unpaid', -- Unpaid, Paid, Partial, Overdue
    PaymentDate DATETIME2,
    PaymentTerms NVARCHAR(50) DEFAULT 'Net30',

    -- Invoice content
    TimeEntries NVARCHAR(MAX), -- JSON array of time entry IDs
    Expenses NVARCHAR(MAX), -- JSON array of expense IDs
    Description NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_LegalInvoices_PaymentStatus CHECK (PaymentStatus IN ('Unpaid', 'Paid', 'Partial', 'Overdue', 'WrittenOff', 'Disputed')),

    -- Indexes
    INDEX IX_LegalInvoices_Number (InvoiceNumber),
    INDEX IX_LegalInvoices_Matter (MatterID),
    INDEX IX_LegalInvoices_Status (PaymentStatus),
    INDEX IX_LegalInvoices_Date (InvoiceDate),
    INDEX IX_LegalInvoices_DueDate (DueDate)
);
```

#### Document Management & Assembly
```sql
-- Legal documents
CREATE TABLE LegalDocuments (
    DocumentID INT IDENTITY(1,1) PRIMARY KEY,
    DocumentNumber NVARCHAR(50) UNIQUE NOT NULL,
    MatterID INT NOT NULL REFERENCES LegalMatters(MatterID),

    -- Document details
    DocumentName NVARCHAR(500) NOT NULL,
    DocumentType NVARCHAR(50), -- Contract, Pleading, Brief, Memo, etc.
    DocumentCategory NVARCHAR(100), -- Filed, Internal, Client, etc.

    -- Version control
    VersionNumber DECIMAL(4,1) DEFAULT 1.0,
    IsLatestVersion BIT DEFAULT 1,
    PreviousVersionID INT REFERENCES LegalDocuments(DocumentID),

    -- Content and storage
    FilePath NVARCHAR(1000),
    FileSize BIGINT,
    MIMEType NVARCHAR(100),
    Checksum NVARCHAR(128), -- SHA-256 hash for integrity

    -- Document metadata
    Author INT REFERENCES Attorneys(AttorneyID),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    ModifiedDate DATETIME2 DEFAULT GETDATE(),
    ReviewedBy INT REFERENCES Attorneys(AttorneyID),
    ReviewedDate DATETIME2,

    -- Security and access
    SecurityLevel NVARCHAR(20) DEFAULT 'Internal', -- Public, Internal, Confidential, AttorneyEyesOnly
    AccessPermissions NVARCHAR(MAX), -- JSON: who can access

    -- Document status
    Status NVARCHAR(20) DEFAULT 'Draft', -- Draft, Review, Approved, Filed, Executed
    WorkflowStage NVARCHAR(50),

    -- Legal metadata
    FiledWithCourt BIT DEFAULT 0,
    CourtFilingDate DATETIME2,
    ExecutionDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_LegalDocuments_Type CHECK (DocumentType IN ('Contract', 'Pleading', 'Brief', 'Memo', 'Correspondence', 'Discovery', 'Exhibit', 'Transcript', 'Form', 'Template')),
    CONSTRAINT CK_LegalDocuments_Category CHECK (DocumentCategory IN ('Filed', 'Internal', 'Client', 'Public', 'Privileged')),
    CONSTRAINT CK_LegalDocuments_Security CHECK (SecurityLevel IN ('Public', 'Internal', 'Confidential', 'AttorneyEyesOnly')),
    CONSTRAINT CK_LegalDocuments_Status CHECK (Status IN ('Draft', 'Review', 'Approved', 'Filed', 'Executed', 'Archived', 'Withdrawn')),

    -- Indexes
    INDEX IX_LegalDocuments_Number (DocumentNumber),
    INDEX IX_LegalDocuments_Matter (MatterID),
    INDEX IX_LegalDocuments_Type (DocumentType),
    INDEX IX_LegalDocuments_Status (Status),
    INDEX IX_LegalDocuments_Author (Author),
    INDEX IX_LegalDocuments_IsLatest (IsLatestVersion),
    INDEX IX_LegalDocuments_CreatedDate (CreatedDate)
);

-- Document templates and clauses
CREATE TABLE DocumentTemplates (
    TemplateID INT IDENTITY(1,1) PRIMARY KEY,
    TemplateCode NVARCHAR(50) UNIQUE NOT NULL,
    TemplateName NVARCHAR(200) NOT NULL,

    -- Template details
    TemplateType NVARCHAR(50), -- Contract, Pleading, Letter, etc.
    PracticeArea NVARCHAR(100),
    Jurisdiction NVARCHAR(100),

    -- Content
    TemplateContent NVARCHAR(MAX), -- Template structure with placeholders
    ClauseLibrary NVARCHAR(MAX), -- JSON array of available clauses
    Variables NVARCHAR(MAX), -- JSON: required variables for assembly

    -- Usage and approval
    IsApproved BIT DEFAULT 0,
    ApprovedBy INT REFERENCES Attorneys(AttorneyID),
    ApprovalDate DATETIME2,

    -- Version control
    VersionNumber DECIMAL(4,1) DEFAULT 1.0,
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy INT REFERENCES Attorneys(AttorneyID),

    -- Constraints
    CONSTRAINT CK_DocumentTemplates_Type CHECK (TemplateType IN ('Contract', 'Pleading', 'Brief', 'Memo', 'Letter', 'Agreement', 'Form', 'Template')),

    -- Indexes
    INDEX IX_DocumentTemplates_Code (TemplateCode),
    INDEX IX_DocumentTemplates_Type (TemplateType),
    INDEX IX_DocumentTemplates_PracticeArea (PracticeArea),
    INDEX IX_DocumentTemplates_IsActive (IsActive),
    INDEX IX_DocumentTemplates_IsApproved (IsApproved)
);

-- Document assembly sessions
CREATE TABLE DocumentAssembly (
    AssemblyID INT IDENTITY(1,1) PRIMARY KEY,
    MatterID INT NOT NULL REFERENCES LegalMatters(MatterID),
    TemplateID INT REFERENCES DocumentTemplates(TemplateID),

    -- Assembly details
    AssemblyName NVARCHAR(200) NOT NULL,
    InitiatedBy INT NOT NULL REFERENCES Attorneys(AttorneyID),
    InitiatedDate DATETIME2 DEFAULT GETDATE(),

    -- Assembly data
    TemplateVariables NVARCHAR(MAX), -- JSON: values for template variables
    SelectedClauses NVARCHAR(MAX), -- JSON: selected clauses and their content
    CustomContent NVARCHAR(MAX), -- JSON: custom additions/modifications

    -- Generated document
    GeneratedDocumentID INT REFERENCES LegalDocuments(DocumentID),
    GenerationStatus NVARCHAR(20) DEFAULT 'InProgress', -- InProgress, Completed, Failed
    CompletionDate DATETIME2,

    -- Review and approval
    ReviewedBy INT REFERENCES Attorneys(AttorneyID),
    ReviewStatus NVARCHAR(20) DEFAULT 'Pending', -- Pending, Approved, Rejected, RequiresChanges
    ReviewNotes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_DocumentAssembly_Status CHECK (GenerationStatus IN ('InProgress', 'Completed', 'Failed', 'Cancelled')),
    CONSTRAINT CK_DocumentAssembly_ReviewStatus CHECK (ReviewStatus IN ('Pending', 'Approved', 'Rejected', 'RequiresChanges')),

    -- Indexes
    INDEX IX_DocumentAssembly_Matter (MatterID),
    INDEX IX_DocumentAssembly_Template (TemplateID),
    INDEX IX_DocumentAssembly_InitiatedBy (InitiatedBy),
    INDEX IX_DocumentAssembly_Status (GenerationStatus),
    INDEX IX_DocumentAssembly_ReviewStatus (ReviewStatus)
);
```

## Integration Points

### External Systems
- **Court filing systems** integration with e-filing platforms and PACER
- **Document management** systems integration with DMS platforms
- **Calendar and docketing** systems for deadline management
- **Legal research databases** integration with Westlaw, LexisNexis
- **Client relationship management** systems for client intake and management
- **Financial and accounting** systems for billing and trust accounting

### API Endpoints
- **Matter management APIs**: Case creation, updates, and status tracking
- **Document APIs**: Document upload, version control, and sharing
- **Time tracking APIs**: Time entry recording and approval workflows
- **Billing APIs**: Invoice generation, payment processing, and reporting
- **Calendar APIs**: Deadline management, court date tracking, and scheduling
- **Client portal APIs**: Self-service access for clients to view matters and documents

## Monitoring & Analytics

### Key Performance Indicators
- **Matter performance**: Resolution time, success rates, profitability by matter type
- **Attorney productivity**: Billable hours, realization rates, matter capacity
- **Client satisfaction**: Client retention rates, NPS scores, responsiveness metrics
- **Financial performance**: Collection rates, write-offs, profitability analysis
- **Compliance metrics**: Ethical wall breaches, deadline compliance, document security

### Real-Time Dashboards
```sql
-- Legal operations dashboard
CREATE VIEW LegalOperationsDashboard AS
SELECT
    -- Matter portfolio overview
    (SELECT COUNT(*) FROM LegalMatters WHERE CaseStatus = 'Open') AS OpenMatters,
    (SELECT COUNT(*) FROM LegalMatters WHERE CaseStatus = 'Closed' AND CloseDate >= DATEADD(MONTH, -1, GETDATE())) AS MattersClosedLastMonth,
    (SELECT AVG(DATEDIFF(DAY, OpenDate, CloseDate)) FROM LegalMatters WHERE CaseStatus = 'Closed' AND CloseDate >= DATEADD(MONTH, -3, GETDATE())) AS AvgMatterResolutionDays,

    -- Financial performance
    (SELECT SUM(BilledAmount) FROM LegalMatters WHERE CaseStatus = 'Open') AS TotalBilledOnOpenMatters,
    (SELECT SUM(CollectedAmount) FROM LegalMatters WHERE CaseStatus = 'Open') AS TotalCollectedOnOpenMatters,
    (SELECT AVG(BilledAmount - CollectedAmount) FROM LegalMatters WHERE CaseStatus = 'Open') AS AvgOutstandingBalance,

    -- Time tracking metrics
    (SELECT SUM(DurationHours) FROM TimeEntries WHERE EntryDate >= DATEADD(MONTH, -1, GETDATE()) AND IsBillable = 1) AS BillableHoursLastMonth,
    (SELECT SUM(BilledAmount) FROM TimeEntries WHERE EntryDate >= DATEADD(MONTH, -1, GETDATE()) AND BillingStatus = 'Billed') AS BilledAmountLastMonth,
    (SELECT CAST(SUM(CASE WHEN BillingStatus = 'Billed' THEN BilledAmount ELSE 0 END) AS DECIMAL(15,4)) /
             NULLIF(SUM(CASE WHEN IsBillable = 1 THEN DurationHours * BillingRate ELSE 0 END), 0) * 100
     FROM TimeEntries WHERE EntryDate >= DATEADD(MONTH, -1, GETDATE())) AS RealizationRateLastMonth,

    -- Document management
    (SELECT COUNT(*) FROM LegalDocuments WHERE CreatedDate >= DATEADD(DAY, -30, GETDATE())) AS DocumentsCreatedLastMonth,
    (SELECT COUNT(*) FROM LegalDocuments WHERE Status = 'Filed' AND FiledWithCourt = 1 AND CourtFilingDate >= DATEADD(DAY, -30, GETDATE())) AS DocumentsFiledLastMonth,

    -- Deadline and milestone tracking
    (SELECT COUNT(*) FROM MatterMilestones WHERE Status = 'Pending' AND DueDate < GETDATE()) AS OverdueMilestones,
    (SELECT COUNT(*) FROM MatterMilestones WHERE Status = 'Completed' AND ActualDate > PlannedDate) AS DelayedMilestones,

    -- Attorney utilization
    (SELECT COUNT(*) FROM Attorneys WHERE EmploymentStatus = 'Active') AS ActiveAttorneys,
    (SELECT AVG(HourlyRate) FROM Attorneys WHERE EmploymentStatus = 'Active') AS AvgAttorneyHourlyRate,
    (SELECT AVG(CAST(SUM(te.DurationHours) AS DECIMAL(10,2))) FROM TimeEntries te
     WHERE te.EntryDate >= DATEADD(MONTH, -1, GETDATE())
     GROUP BY te.AttorneyID) AS AvgMonthlyHoursPerAttorney,

    -- Client metrics
    (SELECT COUNT(DISTINCT ClientID) FROM LegalMatters WHERE CaseStatus = 'Open') AS ActiveClients,
    (SELECT COUNT(*) FROM LegalMatters WHERE OpenDate >= DATEADD(YEAR, -1, GETDATE())) AS NewMattersLastYear,

    -- Quality and compliance
    (SELECT COUNT(*) FROM TimeEntries WHERE RequiresApproval = 1 AND ApprovedDate IS NULL) AS PendingTimeApprovals,
    (SELECT COUNT(*) FROM LegalDocuments WHERE SecurityLevel = 'AttorneyEyesOnly') AS PrivilegedDocuments

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This legal services database schema provides a comprehensive foundation for modern legal practice management platforms, supporting case management, document assembly, time tracking, billing, and enterprise legal operations while maintaining regulatory compliance and data security.
