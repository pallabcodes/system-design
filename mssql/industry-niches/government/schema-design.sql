-- Government & Public Services Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE GovernmentDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE GovernmentDB;
GO

-- Configure database for government compliance and security
ALTER DATABASE GovernmentDB
SET
    RECOVERY SIMPLE,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON,
    ENCRYPTION ON; -- Enable TDE for sensitive government data
GO

-- =============================================
-- CITIZEN MANAGEMENT
-- =============================================

-- Citizens
CREATE TABLE Citizens (
    CitizenID INT IDENTITY(1,1) PRIMARY KEY,
    CitizenNumber NVARCHAR(50) UNIQUE NOT NULL,
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    MiddleName NVARCHAR(100),
    DateOfBirth DATE,
    SSN VARBINARY(128), -- Encrypted SSN

    -- Contact information
    PrimaryAddress NVARCHAR(MAX), -- JSON formatted address
    MailingAddress NVARCHAR(MAX), -- JSON formatted address
    Phone NVARCHAR(20),
    Email NVARCHAR(255),
    PreferredLanguage NVARCHAR(10) DEFAULT 'en',

    -- Demographics
    Gender NVARCHAR(20),
    Ethnicity NVARCHAR(50),
    VeteranStatus BIT DEFAULT 0,
    DisabilityStatus BIT DEFAULT 0,
    HouseholdIncome DECIMAL(12,2),

    -- Government identifiers
    DriversLicense NVARCHAR(50),
    PassportNumber NVARCHAR(50),
    VoterID NVARCHAR(50),

    -- Status
    RegistrationDate DATETIME2 DEFAULT GETDATE(),
    LastActivityDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Active',

    -- Privacy consents
    PrivacyConsent BIT DEFAULT 0,
    MarketingConsent BIT DEFAULT 0,
    DataSharingConsent BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Citizens_Status CHECK (Status IN ('Active', 'Inactive', 'Deceased', 'Moved', 'DoNotContact')),

    -- Indexes
    INDEX IX_Citizens_Number (CitizenNumber),
    INDEX IX_Citizens_Name (LastName, FirstName),
    INDEX IX_Citizens_Email (Email),
    INDEX IX_Citizens_Status (Status),
    INDEX IX_Citizens_RegistrationDate (RegistrationDate),
    INDEX IX_Citizens_LastActivity (LastActivityDate)
);

-- Citizen accounts
CREATE TABLE CitizenAccounts (
    AccountID INT IDENTITY(1,1) PRIMARY KEY,
    CitizenID INT NOT NULL REFERENCES Citizens(CitizenID),
    Username NVARCHAR(100) UNIQUE,
    Email NVARCHAR(255) UNIQUE,
    PasswordHash NVARCHAR(256),
    IsVerified BIT DEFAULT 0,
    VerificationToken NVARCHAR(256),
    TwoFactorEnabled BIT DEFAULT 0,
    TwoFactorSecret NVARCHAR(256),

    -- Security
    LastLoginDate DATETIME2,
    FailedLoginAttempts INT DEFAULT 0,
    AccountLocked BIT DEFAULT 0,
    LockoutEndDate DATETIME2,

    -- Preferences
    NotificationPreferences NVARCHAR(MAX), -- JSON
    AccessibilityPreferences NVARCHAR(MAX), -- JSON

    -- Constraints
    CONSTRAINT CK_CitizenAccounts_FailedAttempts CHECK (FailedLoginAttempts >= 0),

    -- Indexes
    INDEX IX_CitizenAccounts_Citizen (CitizenID),
    INDEX IX_CitizenAccounts_Username (Username),
    INDEX IX_CitizenAccounts_Email (Email),
    INDEX IX_CitizenAccounts_IsVerified (IsVerified)
);

-- =============================================
-- SERVICE REQUESTS & CASE MANAGEMENT
-- =============================================

-- Service requests
CREATE TABLE ServiceRequests (
    RequestID INT IDENTITY(1,1) PRIMARY KEY,
    RequestNumber NVARCHAR(50) UNIQUE NOT NULL,
    CitizenID INT REFERENCES Citizens(CitizenID),

    -- Request details
    ServiceType NVARCHAR(50) NOT NULL,
    Category NVARCHAR(100),
    Subcategory NVARCHAR(100),
    Subject NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Location
    LocationAddress NVARCHAR(MAX), -- JSON
    Jurisdiction NVARCHAR(100),
    Ward NVARCHAR(10),
    District NVARCHAR(10),

    -- Status and priority
    Status NVARCHAR(20) DEFAULT 'Submitted',
    Priority NVARCHAR(10) DEFAULT 'Normal',
    Urgency NVARCHAR(10) DEFAULT 'Normal',

    -- Assignment
    AssignedTo INT,
    AssignedDepartment NVARCHAR(100),
    AssignedDate DATETIME2,

    -- Dates
    SubmittedDate DATETIME2 DEFAULT GETDATE(),
    TargetCompletionDate DATETIME2,
    ActualCompletionDate DATETIME2,
    LastUpdatedDate DATETIME2 DEFAULT GETDATE(),

    -- Financial
    FeeAmount DECIMAL(10,2) DEFAULT 0,
    FeePaid BIT DEFAULT 0,
    PaymentReference NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_ServiceRequests_Status CHECK (Status IN ('Submitted', 'UnderReview', 'InProgress', 'Approved', 'Denied', 'Closed', 'OnHold')),
    CONSTRAINT CK_ServiceRequests_Priority CHECK (Priority IN ('Low', 'Normal', 'High', 'Urgent', 'Emergency')),
    CONSTRAINT CK_ServiceRequests_Urgency CHECK (Urgency IN ('Low', 'Normal', 'High', 'Critical')),

    -- Indexes
    INDEX IX_ServiceRequests_Number (RequestNumber),
    INDEX IX_ServiceRequests_Citizen (CitizenID),
    INDEX IX_ServiceRequests_Type (ServiceType),
    INDEX IX_ServiceRequests_Status (Status),
    INDEX IX_ServiceRequests_Priority (Priority),
    INDEX IX_ServiceRequests_SubmittedDate (SubmittedDate),
    INDEX IX_ServiceRequests_TargetCompletion (TargetCompletionDate),
    INDEX IX_ServiceRequests_AssignedTo (AssignedTo)
);

-- Request status history
CREATE TABLE RequestStatusHistory (
    HistoryID INT IDENTITY(1,1) PRIMARY KEY,
    RequestID INT NOT NULL REFERENCES ServiceRequests(RequestID) ON DELETE CASCADE,
    OldStatus NVARCHAR(20),
    NewStatus NVARCHAR(20) NOT NULL,
    ChangedBy INT NOT NULL,
    ChangedDate DATETIME2 DEFAULT GETDATE(),
    Comments NVARCHAR(MAX),
    InternalNotes NVARCHAR(MAX),

    -- Workflow
    WorkflowStep NVARCHAR(100),
    AssignedTo INT,
    DueDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_RequestStatusHistory_Status CHECK (NewStatus IN ('Submitted', 'UnderReview', 'InProgress', 'Approved', 'Denied', 'Closed', 'OnHold')),

    -- Indexes
    INDEX IX_RequestStatusHistory_Request (RequestID),
    INDEX IX_RequestStatusHistory_Status (NewStatus),
    INDEX IX_RequestStatusHistory_ChangedDate (ChangedDate),
    INDEX IX_RequestStatusHistory_ChangedBy (ChangedBy)
);

-- =============================================
-- DOCUMENTS & RECORDS MANAGEMENT
-- =============================================

-- Documents
CREATE TABLE Documents (
    DocumentID INT IDENTITY(1,1) PRIMARY KEY,
    DocumentNumber NVARCHAR(50) UNIQUE NOT NULL,
    DocumentType NVARCHAR(50) NOT NULL,

    -- Metadata
    Title NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    FileName NVARCHAR(255),
    FilePath NVARCHAR(500),
    FileSize BIGINT,
    MIMEType NVARCHAR(100),

    -- Classification
    Classification NVARCHAR(20) DEFAULT 'Public',
    Sensitivity NVARCHAR(20) DEFAULT 'Normal',
    RetentionPeriodYears INT DEFAULT 7,

    -- Content
    ContentText NVARCHAR(MAX), -- For search
    Keywords NVARCHAR(MAX), -- JSON
    Categories NVARCHAR(MAX), -- JSON

    -- Lifecycle
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy INT,
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),
    Version NVARCHAR(20) DEFAULT '1.0',
    IsLatestVersion BIT DEFAULT 1,

    -- Retention
    RetentionStartDate DATETIME2 DEFAULT GETDATE(),
    RetentionEndDate DATETIME2,
    DisposalDate DATETIME2,
    DisposalMethod NVARCHAR(50),

    -- Constraints
    CONSTRAINT CK_Documents_Classification CHECK (Classification IN ('Public', 'Internal', 'Confidential', 'Restricted')),
    CONSTRAINT CK_Documents_Sensitivity CHECK (Sensitivity IN ('Normal', 'Sensitive', 'Critical')),
    CONSTRAINT CK_Documents_Disposal CHECK (DisposalMethod IN ('Delete', 'Archive', 'Shred', 'Transfer')),

    -- Indexes
    INDEX IX_Documents_Number (DocumentNumber),
    INDEX IX_Documents_Type (DocumentType),
    INDEX IX_Documents_Classification (Classification),
    INDEX IX_Documents_CreatedDate (CreatedDate),
    INDEX IX_Documents_IsLatest (IsLatestVersion),
    INDEX IX_Documents_RetentionEnd (RetentionEndDate)
);

-- Document associations
CREATE TABLE DocumentAssociations (
    AssociationID INT IDENTITY(1,1) PRIMARY KEY,
    DocumentID INT NOT NULL REFERENCES Documents(DocumentID) ON DELETE CASCADE,
    EntityType NVARCHAR(50) NOT NULL,
    EntityID INT NOT NULL,
    AssociationType NVARCHAR(50) DEFAULT 'Attachment',
    IsPrimary BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_DocumentAssociations_Type CHECK (EntityType IN ('Citizen', 'ServiceRequest', 'Permit', 'License', 'Case', 'Property', 'Business')),
    CONSTRAINT CK_DocumentAssociations_AssociationType CHECK (AssociationType IN ('Attachment', 'Reference', 'Related', 'Required', 'Supporting')),

    -- Indexes
    INDEX IX_DocumentAssociations_Document (DocumentID),
    INDEX IX_DocumentAssociations_Entity (EntityType, EntityID),
    INDEX IX_DocumentAssociations_Type (AssociationType),
    INDEX IX_DocumentAssociations_IsPrimary (IsPrimary)
);

-- =============================================
-- PERMITS & LICENSES
-- =============================================

-- Permits and licenses
CREATE TABLE PermitsLicenses (
    PermitID INT IDENTITY(1,1) PRIMARY KEY,
    PermitNumber NVARCHAR(50) UNIQUE NOT NULL,
    CitizenID INT REFERENCES Citizens(CitizenID),
    BusinessID INT,

    -- Details
    PermitType NVARCHAR(50) NOT NULL,
    Subtype NVARCHAR(100),
    Description NVARCHAR(MAX),

    -- Status
    Status NVARCHAR(20) DEFAULT 'Applied',
    ApplicationDate DATETIME2 DEFAULT GETDATE(),
    ApprovalDate DATETIME2,
    IssueDate DATETIME2,
    ExpirationDate DATETIME2,
    RenewalDate DATETIME2,

    -- Fees
    ApplicationFee DECIMAL(10,2) DEFAULT 0,
    LicenseFee DECIMAL(10,2) DEFAULT 0,
    LateFee DECIMAL(10,2) DEFAULT 0,
    TotalPaid DECIMAL(10,2) DEFAULT 0,

    -- Requirements
    Conditions NVARCHAR(MAX), -- JSON
    Requirements NVARCHAR(MAX), -- JSON
    InspectionRequired BIT DEFAULT 0,

    -- Assignment
    AssignedTo INT,
    ReviewedBy INT,
    ApprovedBy INT,

    -- Constraints
    CONSTRAINT CK_PermitsLicenses_Status CHECK (Status IN ('Applied', 'UnderReview', 'Approved', 'Denied', 'Issued', 'Expired', 'Revoked', 'Suspended')),
    CONSTRAINT CK_PermitsLicenses_Type CHECK (PermitType IN ('Building', 'Business', 'Professional', 'Vehicle', 'Event', 'Health', 'Environmental', 'Fire', 'Zoning')),

    -- Indexes
    INDEX IX_PermitsLicenses_Number (PermitNumber),
    INDEX IX_PermitsLicenses_Citizen (CitizenID),
    INDEX IX_PermitsLicenses_Type (PermitType),
    INDEX IX_PermitsLicenses_Status (Status),
    INDEX IX_PermitsLicenses_ApplicationDate (ApplicationDate),
    INDEX IX_PermitsLicenses_ExpirationDate (ExpirationDate),
    INDEX IX_PermitsLicenses_AssignedTo (AssignedTo)
);

-- Permit inspections
CREATE TABLE PermitInspections (
    InspectionID INT IDENTITY(1,1) PRIMARY KEY,
    PermitID INT NOT NULL REFERENCES PermitsLicenses(PermitID) ON DELETE CASCADE,
    InspectionType NVARCHAR(50) NOT NULL,
    ScheduledDate DATETIME2 NOT NULL,
    ActualDate DATETIME2,

    -- Details
    InspectorID INT NOT NULL,
    Status NVARCHAR(20) DEFAULT 'Scheduled',
    Result NVARCHAR(20),

    -- Findings
    Findings NVARCHAR(MAX), -- JSON
    Violations NVARCHAR(MAX), -- JSON
    CorrectiveActions NVARCHAR(MAX), -- JSON
    FollowUpRequired BIT DEFAULT 0,
    FollowUpDate DATETIME2,

    -- Compliance
    ComplianceStatus NVARCHAR(20) DEFAULT 'Pending',
    ResolutionNotes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_PermitInspections_Type CHECK (InspectionType IN ('Initial', 'FollowUp', 'Final', 'Compliance', 'Reinspection')),
    CONSTRAINT CK_PermitInspections_Status CHECK (Status IN ('Scheduled', 'Completed', 'Cancelled', 'Rescheduled', 'NoShow')),
    CONSTRAINT CK_PermitInspections_Result CHECK (Result IN ('Pass', 'Fail', 'Conditional', 'NotApplicable')),
    CONSTRAINT CK_PermitInspections_Compliance CHECK (ComplianceStatus IN ('Pending', 'Compliant', 'NonCompliant', 'Resolved')),

    -- Indexes
    INDEX IX_PermitInspections_Permit (PermitID),
    INDEX IX_PermitInspections_Type (InspectionType),
    INDEX IX_PermitInspections_Status (Status),
    INDEX IX_PermitInspections_Result (Result),
    INDEX IX_PermitInspections_ScheduledDate (ScheduledDate),
    INDEX IX_PermitInspections_Inspector (InspectorID)
);

-- =============================================
-- PUBLIC RECORDS & FOIA
-- =============================================

-- Public records requests
CREATE TABLE PublicRecordsRequests (
    RequestID INT IDENTITY(1,1) PRIMARY KEY,
    RequestNumber NVARCHAR(50) UNIQUE NOT NULL,
    RequesterType NVARCHAR(20) DEFAULT 'Individual',
    RequesterName NVARCHAR(200) NOT NULL,
    RequesterOrganization NVARCHAR(200),

    -- Contact
    Address NVARCHAR(MAX), -- JSON
    Phone NVARCHAR(20),
    Email NVARCHAR(255),

    -- Request
    RequestDescription NVARCHAR(MAX) NOT NULL,
    RequestCategory NVARCHAR(50),
    Urgency NVARCHAR(10) DEFAULT 'Normal',

    -- Processing
    ReceivedDate DATETIME2 DEFAULT GETDATE(),
    AcknowledgedDate DATETIME2,
    TargetResponseDate DATETIME2,
    ActualResponseDate DATETIME2,

    -- Assignment
    AssignedTo INT,
    AssignedDepartment NVARCHAR(100),
    ReviewStatus NVARCHAR(20) DEFAULT 'Received',

    -- Response
    ResponseType NVARCHAR(20),
    ResponseNotes NVARCHAR(MAX),
    AppealFiled BIT DEFAULT 0,
    AppealDate DATETIME2,
    AppealResolution NVARCHAR(MAX),

    -- Fees
    EstimatedCost DECIMAL(10,2),
    ActualCost DECIMAL(10,2),
    FeeWaived BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_PublicRecordsRequests_RequesterType CHECK (RequesterType IN ('Individual', 'Media', 'Business', 'Government', 'Legal', 'Academic')),
    CONSTRAINT CK_PublicRecordsRequests_Category CHECK (RequestCategory IN ('Personnel', 'Financial', 'Contracts', 'Environmental', 'Permits', 'Meetings', 'Correspondence', 'Policies')),
    CONSTRAINT CK_PublicRecordsRequests_Urgency CHECK (Urgency IN ('Normal', 'Expedited')),
    CONSTRAINT CK_PublicRecordsRequests_Status CHECK (ReviewStatus IN ('Received', 'UnderReview', 'Approved', 'Denied', 'Completed', 'Appealed')),
    CONSTRAINT CK_PublicRecordsRequests_ResponseType CHECK (ResponseType IN ('FullDisclosure', 'PartialDisclosure', 'Denied', 'NoRecords', 'Referred')),

    -- Indexes
    INDEX IX_PublicRecordsRequests_Number (RequestNumber),
    INDEX IX_PublicRecordsRequests_Type (RequesterType),
    INDEX IX_PublicRecordsRequests_Category (RequestCategory),
    INDEX IX_PublicRecordsRequests_Status (ReviewStatus),
    INDEX IX_PublicRecordsRequests_ReceivedDate (ReceivedDate),
    INDEX IX_PublicRecordsRequests_TargetResponse (TargetResponseDate),
    INDEX IX_PublicRecordsRequests_AssignedTo (AssignedTo)
);

-- Records releases
CREATE TABLE PublicRecordsReleases (
    ReleaseID INT IDENTITY(1,1) PRIMARY KEY,
    RequestID INT NOT NULL REFERENCES PublicRecordsRequests(RequestID) ON DELETE CASCADE,
    DocumentID INT REFERENCES Documents(DocumentID),
    ReleaseType NVARCHAR(20) NOT NULL,

    -- Details
    ReleaseDate DATETIME2 DEFAULT GETDATE(),
    ReleasedBy INT NOT NULL,
    ExemptionCode NVARCHAR(50),
    RedactionReason NVARCHAR(MAX),

    -- Tracking
    PageCount INT,
    WordCount INT,
    EstimatedReviewTime DECIMAL(6,2),

    -- Constraints
    CONSTRAINT CK_PublicRecordsReleases_Type CHECK (ReleaseType IN ('Full', 'Redacted', 'Summary', 'Denial', 'Referral')),

    -- Indexes
    INDEX IX_PublicRecordsReleases_Request (RequestID),
    INDEX IX_PublicRecordsReleases_Document (DocumentID),
    INDEX IX_PublicRecordsReleases_Type (ReleaseType),
    INDEX IX_PublicRecordsReleases_Date (ReleaseDate)
);

-- =============================================
-- PUBLIC COMMUNICATIONS
-- =============================================

-- Public notifications
CREATE TABLE PublicNotifications (
    NotificationID INT IDENTITY(1,1) PRIMARY KEY,
    NotificationNumber NVARCHAR(50) UNIQUE NOT NULL,
    Title NVARCHAR(200) NOT NULL,
    Message NVARCHAR(MAX) NOT NULL,
    NotificationType NVARCHAR(20) DEFAULT 'Information',

    -- Content
    Summary NVARCHAR(500),
    ImageURL NVARCHAR(500),
    DocumentURL NVARCHAR(500),
    VideoURL NVARCHAR(500),

    -- Targeting
    TargetAudience NVARCHAR(MAX), -- JSON
    GeographicScope NVARCHAR(MAX), -- JSON
    DistributionChannels NVARCHAR(MAX), -- JSON

    -- Scheduling
    PublishDate DATETIME2 DEFAULT GETDATE(),
    ExpirationDate DATETIME2,
    Priority NVARCHAR(10) DEFAULT 'Normal',

    -- Status
    Status NVARCHAR(20) DEFAULT 'Draft',
    PublishedBy INT NOT NULL,
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),

    -- Analytics
    ViewCount INT DEFAULT 0,
    ClickCount INT DEFAULT 0,
    EngagementRate DECIMAL(5,4),

    -- Constraints
    CONSTRAINT CK_PublicNotifications_Type CHECK (NotificationType IN ('Information', 'Alert', 'Emergency', 'Update', 'Advisory')),
    CONSTRAINT CK_PublicNotifications_Priority CHECK (Priority IN ('Low', 'Normal', 'High', 'Urgent')),
    CONSTRAINT CK_PublicNotifications_Status CHECK (Status IN ('Draft', 'Published', 'Expired', 'Cancelled')),
    CONSTRAINT CK_PublicNotifications_Engagement CHECK (EngagementRate BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_PublicNotifications_Number (NotificationNumber),
    INDEX IX_PublicNotifications_Type (NotificationType),
    INDEX IX_PublicNotifications_Status (Status),
    INDEX IX_PublicNotifications_PublishDate (PublishDate),
    INDEX IX_PublicNotifications_ExpirationDate (ExpirationDate),
    INDEX IX_PublicNotifications_Priority (Priority)
);

-- Citizen feedback
CREATE TABLE CitizenFeedback (
    FeedbackID INT IDENTITY(1,1) PRIMARY KEY,
    CitizenID INT REFERENCES Citizens(CitizenID),
    FeedbackType NVARCHAR(20) NOT NULL,

    -- Content
    Subject NVARCHAR(200),
    Description NVARCHAR(MAX),
    Category NVARCHAR(50),
    Subcategory NVARCHAR(50),

    -- Rating
    Rating INT CHECK (Rating BETWEEN 1 AND 5),
    Sentiment NVARCHAR(10),
    Priority NVARCHAR(10) DEFAULT 'Normal',

    -- Processing
    Status NVARCHAR(20) DEFAULT 'Received',
    AssignedTo INT,
    AssignedDate DATETIME2,
    ResolutionDate DATETIME2,
    Resolution NVARCHAR(MAX),

    -- Context
    Location NVARCHAR(100),
    ServiceRelated NVARCHAR(100),
    ContactMethod NVARCHAR(20),

    -- Metadata
    SubmittedDate DATETIME2 DEFAULT GETDATE(),
    SourceChannel NVARCHAR(20),

    -- Constraints
    CONSTRAINT CK_CitizenFeedback_Type CHECK (FeedbackType IN ('Complaint', 'Suggestion', 'Survey', 'Rating', 'Question', 'Praise')),
    CONSTRAINT CK_CitizenFeedback_Sentiment CHECK (Sentiment IN ('Positive', 'Neutral', 'Negative')),
    CONSTRAINT CK_CitizenFeedback_Status CHECK (Status IN ('Received', 'UnderReview', 'InProgress', 'Resolved', 'Closed', 'Escalated')),
    CONSTRAINT CK_CitizenFeedback_Priority CHECK (Priority IN ('Low', 'Normal', 'High', 'Urgent')),
    CONSTRAINT CK_CitizenFeedback_ContactMethod CHECK (ContactMethod IN ('Phone', 'Email', 'Website', 'App', 'InPerson', 'Mail')),

    -- Indexes
    INDEX IX_CitizenFeedback_Citizen (CitizenID),
    INDEX IX_CitizenFeedback_Type (FeedbackType),
    INDEX IX_CitizenFeedback_Status (Status),
    INDEX IX_CitizenFeedback_SubmittedDate (SubmittedDate),
    INDEX IX_CitizenFeedback_Category (Category),
    INDEX IX_CitizenFeedback_Rating (Rating)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Service request summary view
CREATE VIEW vw_ServiceRequestSummary
AS
SELECT
    sr.RequestID,
    sr.RequestNumber,
    sr.ServiceType,
    sr.Status,
    sr.Priority,
    sr.SubmittedDate,
    sr.TargetCompletionDate,
    sr.ActualCompletionDate,
    c.FirstName + ' ' + c.LastName AS CitizenName,

    -- Status indicators
    CASE
        WHEN sr.Status IN ('Approved', 'Closed') THEN 'Completed'
        WHEN sr.ActualCompletionDate > sr.TargetCompletionDate THEN 'Overdue'
        WHEN sr.Status = 'Submitted' AND sr.SubmittedDate < DATEADD(DAY, -7, GETDATE()) THEN 'Stalled'
        ELSE 'In Progress'
    END AS StatusIndicator,

    -- Days calculations
    DATEDIFF(DAY, sr.SubmittedDate, ISNULL(sr.ActualCompletionDate, GETDATE())) AS DaysOpen,
    CASE
        WHEN sr.TargetCompletionDate IS NOT NULL THEN DATEDIFF(DAY, GETDATE(), sr.TargetCompletionDate)
        ELSE NULL
    END AS DaysToDue

FROM ServiceRequests sr
LEFT JOIN Citizens c ON sr.CitizenID = c.CitizenID
WHERE sr.Status NOT IN ('Closed');
GO

-- Permit status view
CREATE VIEW vw_PermitStatus
AS
SELECT
    pl.PermitID,
    pl.PermitNumber,
    pl.PermitType,
    pl.Status,
    pl.ApplicationDate,
    pl.ApprovalDate,
    pl.IssueDate,
    pl.ExpirationDate,
    c.FirstName + ' ' + c.LastName AS ApplicantName,

    -- Status calculations
    CASE
        WHEN pl.Status = 'Expired' THEN 'Expired'
        WHEN pl.ExpirationDate < GETDATE() THEN 'Expired'
        WHEN pl.Status = 'Issued' AND pl.ExpirationDate < DATEADD(MONTH, 3, GETDATE()) THEN 'Expiring Soon'
        WHEN pl.Status = 'Issued' THEN 'Active'
        WHEN pl.Status = 'Applied' AND pl.ApplicationDate < DATEADD(DAY, -30, GETDATE()) THEN 'Delayed'
        ELSE 'Processing'
    END AS StatusIndicator,

    -- Days calculations
    DATEDIFF(DAY, pl.ApplicationDate, ISNULL(pl.IssueDate, GETDATE())) AS ProcessingDays,
    CASE
        WHEN pl.ExpirationDate IS NOT NULL THEN DATEDIFF(DAY, GETDATE(), pl.ExpirationDate)
        ELSE NULL
    END AS DaysToExpiration

FROM PermitsLicenses pl
LEFT JOIN Citizens c ON pl.CitizenID = c.CitizenID;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update citizen last activity
CREATE TRIGGER TR_ServiceRequests_UpdateLastActivity
ON ServiceRequests
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE c
    SET c.LastActivityDate = GETDATE()
    FROM Citizens c
    INNER JOIN inserted i ON c.CitizenID = i.CitizenID;
END;
GO

-- Update request last modified date
CREATE TRIGGER TR_RequestStatusHistory_UpdateLastModified
ON RequestStatusHistory
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE sr
    SET sr.LastUpdatedDate = GETDATE()
    FROM ServiceRequests sr
    INNER JOIN inserted i ON sr.RequestID = i.RequestID;
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Submit service request procedure
CREATE PROCEDURE sp_SubmitServiceRequest
    @CitizenID INT,
    @ServiceType NVARCHAR(50),
    @Subject NVARCHAR(200),
    @Description NVARCHAR(MAX),
    @Category NVARCHAR(100) = NULL,
    @Priority NVARCHAR(10) = 'Normal',
    @LocationAddress NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RequestNumber NVARCHAR(50);

    -- Generate request number
    SET @RequestNumber = 'SR-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                        RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                        RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS NVARCHAR(6)), 6);

    -- Calculate target completion date based on priority
    DECLARE @TargetCompletionDate DATETIME2;
    SET @TargetCompletionDate = CASE @Priority
        WHEN 'Low' THEN DATEADD(DAY, 30, GETDATE())
        WHEN 'Normal' THEN DATEADD(DAY, 14, GETDATE())
        WHEN 'High' THEN DATEADD(DAY, 7, GETDATE())
        WHEN 'Urgent' THEN DATEADD(DAY, 3, GETDATE())
        WHEN 'Emergency' THEN DATEADD(DAY, 1, GETDATE())
        ELSE DATEADD(DAY, 14, GETDATE())
    END;

    INSERT INTO ServiceRequests (
        RequestNumber, CitizenID, ServiceType, Category, Subject, Description,
        Priority, LocationAddress, TargetCompletionDate
    )
    VALUES (
        @RequestNumber, @CitizenID, @ServiceType, @Category, @Subject, @Description,
        @Priority, @LocationAddress, @TargetCompletionDate
    );

    SELECT SCOPE_IDENTITY() AS RequestID, @RequestNumber AS RequestNumber;
END;
GO

-- Process permit application procedure
CREATE PROCEDURE sp_ProcessPermitApplication
    @PermitType NVARCHAR(50),
    @CitizenID INT,
    @Description NVARCHAR(MAX),
    @ApplicationFee DECIMAL(10,2) = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PermitNumber NVARCHAR(50);

    -- Generate permit number
    SET @PermitNumber = 'P' + UPPER(LEFT(@PermitType, 1)) + '-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                       RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                       RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    INSERT INTO PermitsLicenses (
        PermitNumber, CitizenID, PermitType, Description, ApplicationFee
    )
    VALUES (
        @PermitNumber, @CitizenID, @PermitType, @Description, @ApplicationFee
    );

    SELECT SCOPE_IDENTITY() AS PermitID, @PermitNumber AS PermitNumber;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample citizen
INSERT INTO Citizens (CitizenNumber, FirstName, LastName, Email, Phone) VALUES
('CIT-000001', 'John', 'Doe', 'john.doe@email.com', '555-0101');

-- Insert sample service request
INSERT INTO ServiceRequests (RequestNumber, CitizenID, ServiceType, Subject, Description, Category) VALUES
('SR-202412-000001', 1, 'Permit', 'Building Permit Application', 'Need permit for home renovation', 'Building');

-- Insert sample permit
INSERT INTO PermitsLicenses (PermitNumber, CitizenID, PermitType, Description) VALUES
('PB-202412-00001', 1, 'Building', 'Home renovation permit');

-- Insert sample document
INSERT INTO Documents (DocumentNumber, DocumentType, Title, Classification) VALUES
('DOC-202412-00001', 'Application', 'Building Permit Application', 'Public');

PRINT 'Government database schema created successfully!';
GO
