-- Legal Services & Case Management Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE LegalDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE LegalDB;
GO

-- Configure database for legal compliance
ALTER DATABASE LegalDB
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
-- FIRM & ATTORNEY MANAGEMENT
-- =============================================

-- Legal firms
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

-- Attorneys
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

-- =============================================
-- MATTER & CASE MANAGEMENT
-- =============================================

-- Legal matters
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

-- Matter parties
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

-- =============================================
-- TIME TRACKING & BILLING
-- =============================================

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

-- Billing rules
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

-- Legal invoices
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

-- =============================================
-- DOCUMENT MANAGEMENT
-- =============================================

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

-- Document templates
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

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Matter summary view
CREATE VIEW vw_MatterSummary
AS
SELECT
    lm.MatterID,
    lm.MatterNumber,
    lm.MatterName,
    lm.MatterType,
    lm.CaseStatus,
    lm.Priority,
    lm.OpenDate,
    lm.CloseDate,

    -- Financial summary
    lm.Budget,
    lm.BilledAmount,
    lm.CollectedAmount,
    CASE
        WHEN lm.BilledAmount > 0 THEN (lm.CollectedAmount / lm.BilledAmount) * 100
        ELSE 0
    END AS CollectionRate,

    -- Time tracking summary
    (SELECT SUM(te.DurationHours) FROM TimeEntries te WHERE te.MatterID = lm.MatterID AND te.IsBillable = 1) AS TotalBillableHours,
    (SELECT SUM(te.BilledAmount) FROM TimeEntries te WHERE te.MatterID = lm.MatterID AND te.BillingStatus = 'Billed') AS TotalBilled,

    -- Document count
    (SELECT COUNT(*) FROM LegalDocuments ld WHERE ld.MatterID = lm.MatterID) AS TotalDocuments,

    -- Attorney assignment
    a.FirstName + ' ' + a.LastName AS LeadAttorneyName,

    -- Client information (would join with client table in production)
    lm.ClientID

FROM LegalMatters lm
LEFT JOIN Attorneys a ON lm.LeadAttorneyID = a.AttorneyID
WHERE lm.CaseStatus != 'Closed' OR lm.CloseDate >= DATEADD(MONTH, -6, GETDATE());
GO

-- Billing summary view
CREATE VIEW vw_BillingSummary
AS
SELECT
    li.InvoiceID,
    li.InvoiceNumber,
    lm.MatterNumber,
    lm.MatterName,
    li.InvoiceDate,
    li.DueDate,
    li.TotalAmount,
    li.PaymentStatus,

    -- Aging analysis
    CASE
        WHEN li.PaymentStatus = 'Paid' THEN 0
        WHEN DATEDIFF(DAY, li.DueDate, GETDATE()) <= 0 THEN 0
        WHEN DATEDIFF(DAY, li.DueDate, GETDATE()) <= 30 THEN 1 -- 0-30 days
        WHEN DATEDIFF(DAY, li.DueDate, GETDATE()) <= 60 THEN 2 -- 31-60 days
        WHEN DATEDIFF(DAY, li.DueDate, GETDATE()) <= 90 THEN 3 -- 61-90 days
        ELSE 4 -- 90+ days
    END AS AgingBucket,

    -- Time entries included
    (SELECT COUNT(*) FROM TimeEntries te WHERE te.MatterID = li.MatterID
     AND te.BillingStatus = 'Billed'
     AND te.EntryDate BETWEEN li.BillingPeriodStart AND li.BillingPeriodEnd) AS TimeEntriesCount

FROM LegalInvoices li
INNER JOIN LegalMatters lm ON li.MatterID = lm.MatterID
WHERE li.InvoiceDate >= DATEADD(YEAR, -1, GETDATE());
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update matter billed amount when time entries are billed
CREATE TRIGGER TR_TimeEntries_UpdateMatterBilling
ON TimeEntries
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Update matter billed amount when time entries are marked as billed
    UPDATE lm
    SET lm.BilledAmount = (
        SELECT SUM(te.BilledAmount) FROM TimeEntries te
        WHERE te.MatterID = lm.MatterID AND te.BillingStatus = 'Billed'
    )
    FROM LegalMatters lm
    INNER JOIN inserted i ON lm.MatterID = i.MatterID
    WHERE i.BillingStatus = 'Billed';
END;
GO

-- Update document version control
CREATE TRIGGER TR_LegalDocuments_VersionControl
ON LegalDocuments
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Mark previous versions as not latest
    UPDATE ld
    SET ld.IsLatestVersion = 0
    FROM LegalDocuments ld
    INNER JOIN inserted i ON ld.MatterID = i.MatterID
        AND ld.DocumentName = i.DocumentName
        AND ld.DocumentID != i.DocumentID
    WHERE ld.IsLatestVersion = 1;
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Create new matter procedure
CREATE PROCEDURE sp_CreateMatter
    @MatterName NVARCHAR(500),
    @MatterType NVARCHAR(50),
    @PracticeArea NVARCHAR(100),
    @ClientID INT,
    @LeadAttorneyID INT,
    @EstimatedValue DECIMAL(15,2) = NULL,
    @Description NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MatterNumber NVARCHAR(50);

    -- Generate matter number
    SET @MatterNumber = 'MAT-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                       RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                       RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    INSERT INTO LegalMatters (
        MatterNumber, FirmID, MatterName, MatterDescription, MatterType,
        PracticeArea, ClientID, LeadAttorneyID, EstimatedValue
    )
    VALUES (
        @MatterNumber, 1, @MatterName, @Description, @MatterType,
        @PracticeArea, @ClientID, @LeadAttorneyID, @EstimatedValue
    );

    SELECT SCOPE_IDENTITY() AS MatterID, @MatterNumber AS MatterNumber;
END;
GO

-- Record time entry procedure
CREATE PROCEDURE sp_RecordTimeEntry
    @AttorneyID INT,
    @MatterID INT,
    @StartTime DATETIME2,
    @EndTime DATETIME2,
    @ActivityType NVARCHAR(50),
    @Description NVARCHAR(MAX),
    @IsBillable BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DurationHours DECIMAL(6,2);
    DECLARE @BillingRate DECIMAL(8,2);

    -- Calculate duration
    SET @DurationHours = DATEDIFF(MINUTE, @StartTime, @EndTime) / 60.0;

    -- Get billing rate (simplified - would use billing rules in production)
    SELECT @BillingRate = COALESCE(BillingRate, HourlyRate, 0)
    FROM Attorneys
    WHERE AttorneyID = @AttorneyID;

    INSERT INTO TimeEntries (
        AttorneyID, MatterID, StartTime, EndTime, DurationHours,
        ActivityType, Description, IsBillable, BillingRate,
        BilledAmount
    )
    VALUES (
        @AttorneyID, @MatterID, @StartTime, @EndTime, @DurationHours,
        @ActivityType, @Description, @IsBillable, @BillingRate,
        CASE WHEN @IsBillable = 1 THEN @DurationHours * @BillingRate ELSE 0 END
    );

    SELECT SCOPE_IDENTITY() AS TimeEntryID;
END;
GO

-- Generate invoice procedure
CREATE PROCEDURE sp_GenerateInvoice
    @MatterID INT,
    @BillingPeriodStart DATETIME2,
    @BillingPeriodEnd DATETIME2
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @InvoiceNumber NVARCHAR(50);
    DECLARE @Subtotal DECIMAL(12,2) = 0;

    -- Generate invoice number
    SET @InvoiceNumber = 'INV-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                        RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) +
                        RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS NVARCHAR(6)), 6);

    -- Calculate subtotal from unbilled time entries
    SELECT @Subtotal = SUM(BilledAmount)
    FROM TimeEntries
    WHERE MatterID = @MatterID
    AND BillingStatus = 'Unbilled'
    AND EntryDate BETWEEN @BillingPeriodStart AND @BillingPeriodEnd;

    -- Create invoice
    INSERT INTO LegalInvoices (
        InvoiceNumber, MatterID, BillingPeriodStart, BillingPeriodEnd,
        Subtotal, TotalAmount, DueDate
    )
    VALUES (
        @InvoiceNumber, @MatterID, @BillingPeriodStart, @BillingPeriodEnd,
        @Subtotal, @Subtotal, DATEADD(DAY, 30, GETDATE())
    );

    -- Update time entries to billed status
    UPDATE TimeEntries
    SET BillingStatus = 'Billed'
    WHERE MatterID = @MatterID
    AND BillingStatus = 'Unbilled'
    AND EntryDate BETWEEN @BillingPeriodStart AND @BillingPeriodEnd;

    SELECT SCOPE_IDENTITY() AS InvoiceID, @InvoiceNumber AS InvoiceNumber;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample firm
INSERT INTO LegalFirms (FirmCode, FirmName, FirmType, FoundedDate) VALUES
('LAW-001', 'Smith & Associates LLP', 'LawFirm', '1995-01-01');

-- Insert sample attorney
INSERT INTO Attorneys (AttorneyNumber, FirmID, FirstName, LastName, BarNumber, JobTitle, HourlyRate, BillingRate) VALUES
('ATT-001', 1, 'John', 'Smith', '123456', 'Partner', 350.00, 400.00);

-- Insert sample matter
INSERT INTO LegalMatters (MatterNumber, FirmID, MatterName, MatterType, PracticeArea, ClientID, LeadAttorneyID, EstimatedValue) VALUES
('MAT-202412-00001', 1, 'Patent Infringement Case', 'Litigation', 'IntellectualProperty', 1, 1, 500000.00);

-- Insert sample time entry
INSERT INTO TimeEntries (AttorneyID, MatterID, StartTime, EndTime, DurationHours, ActivityType, Description, BillingRate, BilledAmount) VALUES
(1, 1, '2024-12-15 09:00:00', '2024-12-15 11:00:00', 2.0, 'Research', 'Legal research on patent claims', 400.00, 800.00);

-- Insert sample document
INSERT INTO LegalDocuments (DocumentNumber, MatterID, DocumentName, DocumentType, Author) VALUES
('DOC-202412-00001', 1, 'Complaint Draft', 'Pleading', 1);

PRINT 'Legal database schema created successfully!';
GO
