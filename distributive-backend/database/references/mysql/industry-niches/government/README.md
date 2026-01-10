# Government & Public Services Platform Database Design

## Overview

This comprehensive database schema supports modern government and public services platforms including citizen services, regulatory compliance, public records management, permit processing, and governmental operations. The design handles complex workflows, regulatory requirements, public data transparency, and enterprise government operations.

## Key Features

### 🏛️ Citizen Services & Case Management
- **Citizen portal management** with service requests, applications, and status tracking
- **Case management workflows** with complex approval processes and document handling
- **Multi-agency coordination** with inter-departmental data sharing and collaboration
- **Public records management** with retention policies and FOIA compliance

### 📋 Regulatory Compliance & Licensing
- **Permit and license processing** with automated workflows and fee calculations
- **Regulatory compliance tracking** with inspection schedules and violation management
- **Auditing and reporting** with comprehensive audit trails and compliance reporting
- **Document management** with secure storage, versioning, and access controls

### 🗳️ Public Transparency & Communication
- **Public records access** with FOIA request processing and response tracking
- **Open data initiatives** with data publishing and API access management
- **Public communication** with announcements, alerts, and notification systems
- **Survey and feedback management** with citizen engagement and satisfaction tracking

## Database Schema Highlights

### Core Tables

#### Citizen & Constituent Management
```sql
-- Citizen/constituent master table
CREATE TABLE Citizens (
    CitizenID INT IDENTITY(1,1) PRIMARY KEY,
    CitizenNumber NVARCHAR(50) UNIQUE NOT NULL,
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    MiddleName NVARCHAR(100),
    DateOfBirth DATE,
    SSN VARBINARY(128), -- Encrypted SSN for identity verification

    -- Contact information
    PrimaryAddress NVARCHAR(MAX), -- JSON formatted address
    MailingAddress NVARCHAR(MAX), -- JSON formatted address
    Phone NVARCHAR(20),
    Email NVARCHAR(255),
    PreferredLanguage NVARCHAR(10) DEFAULT 'en',

    -- Demographics for reporting and services
    Gender NVARCHAR(20),
    Ethnicity NVARCHAR(50),
    VeteranStatus BIT DEFAULT 0,
    DisabilityStatus BIT DEFAULT 0,
    HouseholdIncome DECIMAL(12,2),

    -- Government identifiers
    DriversLicense NVARCHAR(50),
    PassportNumber NVARCHAR(50),
    VoterID NVARCHAR(50),

    -- Account status
    RegistrationDate DATETIME2 DEFAULT GETDATE(),
    LastActivityDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, Deceased, Moved

    -- Privacy and consent
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

-- Citizen accounts and authentication
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

    -- Account security
    LastLoginDate DATETIME2,
    FailedLoginAttempts INT DEFAULT 0,
    AccountLocked BIT DEFAULT 0,
    LockoutEndDate DATETIME2,

    -- Preferences
    NotificationPreferences NVARCHAR(MAX), -- JSON: email, sms, push
    AccessibilityPreferences NVARCHAR(MAX), -- JSON: font size, contrast, etc.

    -- Constraints
    CONSTRAINT CK_CitizenAccounts_FailedAttempts CHECK (FailedLoginAttempts >= 0),

    -- Indexes
    INDEX IX_CitizenAccounts_Citizen (CitizenID),
    INDEX IX_CitizenAccounts_Username (Username),
    INDEX IX_CitizenAccounts_Email (Email),
    INDEX IX_CitizenAccounts_IsVerified (IsVerified)
);
```

#### Service Requests & Case Management
```sql
-- Service request master table
CREATE TABLE ServiceRequests (
    RequestID INT IDENTITY(1,1) PRIMARY KEY,
    RequestNumber NVARCHAR(50) UNIQUE NOT NULL,
    CitizenID INT REFERENCES Citizens(CitizenID),

    -- Request details
    ServiceType NVARCHAR(50) NOT NULL, -- Permit, License, Complaint, Information
    Category NVARCHAR(100),
    Subcategory NVARCHAR(100),
    Subject NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Location and jurisdiction
    LocationAddress NVARCHAR(MAX), -- JSON formatted
    Jurisdiction NVARCHAR(100), -- City, County, State agency
    Ward NVARCHAR(10),
    District NVARCHAR(10),

    -- Request status and priority
    Status NVARCHAR(20) DEFAULT 'Submitted', -- Submitted, UnderReview, Approved, Denied, Closed
    Priority NVARCHAR(10) DEFAULT 'Normal', -- Low, Normal, High, Urgent, Emergency
    Urgency NVARCHAR(10) DEFAULT 'Normal',

    -- Assignment and handling
    AssignedTo INT,
    AssignedDepartment NVARCHAR(100),
    AssignedDate DATETIME2,

    -- Dates and deadlines
    SubmittedDate DATETIME2 DEFAULT GETDATE(),
    TargetCompletionDate DATETIME2,
    ActualCompletionDate DATETIME2,
    LastUpdatedDate DATETIME2 DEFAULT GETDATE(),

    -- Financial aspects
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

-- Request workflow and status history
CREATE TABLE RequestStatusHistory (
    HistoryID INT IDENTITY(1,1) PRIMARY KEY,
    RequestID INT NOT NULL REFERENCES ServiceRequests(RequestID) ON DELETE CASCADE,
    OldStatus NVARCHAR(20),
    NewStatus NVARCHAR(20) NOT NULL,
    ChangedBy INT NOT NULL,
    ChangedDate DATETIME2 DEFAULT GETDATE(),
    Comments NVARCHAR(MAX),
    InternalNotes NVARCHAR(MAX),

    -- Workflow metadata
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
```

#### Documents & Records Management
```sql
-- Document master table
CREATE TABLE Documents (
    DocumentID INT IDENTITY(1,1) PRIMARY KEY,
    DocumentNumber NVARCHAR(50) UNIQUE NOT NULL,
    DocumentType NVARCHAR(50) NOT NULL, -- Application, Permit, License, Report, Correspondence

    -- Document metadata
    Title NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    FileName NVARCHAR(255),
    FilePath NVARCHAR(500),
    FileSize BIGINT,
    MIMEType NVARCHAR(100),

    -- Classification and security
    Classification NVARCHAR(20) DEFAULT 'Public', -- Public, Internal, Confidential, Restricted
    Sensitivity NVARCHAR(20) DEFAULT 'Normal', -- Normal, Sensitive, Critical
    RetentionPeriodYears INT DEFAULT 7,

    -- Content and indexing
    ContentText NVARCHAR(MAX), -- Extracted text for search
    Keywords NVARCHAR(MAX), -- JSON array
    Categories NVARCHAR(MAX), -- JSON array

    -- Document lifecycle
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy INT,
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),
    Version NVARCHAR(20) DEFAULT '1.0',
    IsLatestVersion BIT DEFAULT 1,

    -- Retention and disposal
    RetentionStartDate DATETIME2 DEFAULT GETDATE(),
    RetentionEndDate DATETIME2,
    DisposalDate DATETIME2,
    DisposalMethod NVARCHAR(50), -- Delete, Archive, Shred

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
    EntityType NVARCHAR(50) NOT NULL, -- Citizen, Request, Permit, License, Case
    EntityID INT NOT NULL,
    AssociationType NVARCHAR(50) DEFAULT 'Attachment', -- Attachment, Reference, Related
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
```

### Regulatory Compliance & Licensing

#### Permits & Licenses
```sql
-- Permit/license master table
CREATE TABLE PermitsLicenses (
    PermitID INT IDENTITY(1,1) PRIMARY KEY,
    PermitNumber NVARCHAR(50) UNIQUE NOT NULL,
    CitizenID INT REFERENCES Citizens(CitizenID),
    BusinessID INT, -- Reference to business entity

    -- Permit details
    PermitType NVARCHAR(50) NOT NULL, -- Building, Business, Professional, Vehicle, etc.
    Subtype NVARCHAR(100),
    Description NVARCHAR(MAX),

    -- Status and validity
    Status NVARCHAR(20) DEFAULT 'Applied', -- Applied, UnderReview, Approved, Denied, Issued, Expired, Revoked
    ApplicationDate DATETIME2 DEFAULT GETDATE(),
    ApprovalDate DATETIME2,
    IssueDate DATETIME2,
    ExpirationDate DATETIME2,
    RenewalDate DATETIME2,

    -- Fees and payments
    ApplicationFee DECIMAL(10,2) DEFAULT 0,
    LicenseFee DECIMAL(10,2) DEFAULT 0,
    LateFee DECIMAL(10,2) DEFAULT 0,
    TotalPaid DECIMAL(10,2) DEFAULT 0,

    -- Conditions and requirements
    Conditions NVARCHAR(MAX), -- JSON array of conditions
    Requirements NVARCHAR(MAX), -- JSON array of requirements
    InspectionRequired BIT DEFAULT 0,

    -- Assignment and processing
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

-- Permit inspections and compliance
CREATE TABLE PermitInspections (
    InspectionID INT IDENTITY(1,1) PRIMARY KEY,
    PermitID INT NOT NULL REFERENCES PermitsLicenses(PermitID) ON DELETE CASCADE,
    InspectionType NVARCHAR(50) NOT NULL, -- Initial, FollowUp, Final, Compliance
    ScheduledDate DATETIME2 NOT NULL,
    ActualDate DATETIME2,

    -- Inspection details
    InspectorID INT NOT NULL,
    Status NVARCHAR(20) DEFAULT 'Scheduled', -- Scheduled, Completed, Cancelled, Rescheduled
    Result NVARCHAR(20), -- Pass, Fail, Conditional, NotApplicable

    -- Findings and actions
    Findings NVARCHAR(MAX), -- JSON array of findings
    Violations NVARCHAR(MAX), -- JSON array of violations
    CorrectiveActions NVARCHAR(MAX), -- JSON array of required actions
    FollowUpRequired BIT DEFAULT 0,
    FollowUpDate DATETIME2,

    -- Compliance tracking
    ComplianceStatus NVARCHAR(20) DEFAULT 'Pending', -- Pending, Compliant, NonCompliant, Resolved
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
```

#### Public Records & FOIA Management
```sql
-- Public records requests (FOIA)
CREATE TABLE PublicRecordsRequests (
    RequestID INT IDENTITY(1,1) PRIMARY KEY,
    RequestNumber NVARCHAR(50) UNIQUE NOT NULL,
    RequesterType NVARCHAR(20) DEFAULT 'Individual', -- Individual, Media, Business, Government
    RequesterName NVARCHAR(200) NOT NULL,
    RequesterOrganization NVARCHAR(200),

    -- Contact information
    Address NVARCHAR(MAX), -- JSON formatted
    Phone NVARCHAR(20),
    Email NVARCHAR(255),

    -- Request details
    RequestDescription NVARCHAR(MAX) NOT NULL,
    RequestCategory NVARCHAR(50), -- Personnel, Financial, Contracts, Environmental, etc.
    Urgency NVARCHAR(10) DEFAULT 'Normal', -- Normal, Expedited

    -- Processing information
    ReceivedDate DATETIME2 DEFAULT GETDATE(),
    AcknowledgedDate DATETIME2,
    TargetResponseDate DATETIME2,
    ActualResponseDate DATETIME2,

    -- Assignment and review
    AssignedTo INT,
    AssignedDepartment NVARCHAR(100),
    ReviewStatus NVARCHAR(20) DEFAULT 'Received', -- Received, UnderReview, Approved, Denied, Completed

    -- Response details
    ResponseType NVARCHAR(20), -- FullDisclosure, PartialDisclosure, Denied, NoRecords
    ResponseNotes NVARCHAR(MAX),
    AppealFiled BIT DEFAULT 0,
    AppealDate DATETIME2,
    AppealResolution NVARCHAR(MAX),

    -- Fees and costs
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

-- Records released in response
CREATE TABLE PublicRecordsReleases (
    ReleaseID INT IDENTITY(1,1) PRIMARY KEY,
    RequestID INT NOT NULL REFERENCES PublicRecordsRequests(RequestID) ON DELETE CASCADE,
    DocumentID INT REFERENCES Documents(DocumentID),
    ReleaseType NVARCHAR(20) NOT NULL, -- Full, Redacted, Summary, Denial

    -- Release details
    ReleaseDate DATETIME2 DEFAULT GETDATE(),
    ReleasedBy INT NOT NULL,
    ExemptionCode NVARCHAR(50), -- FOIA exemption codes
    RedactionReason NVARCHAR(MAX),

    -- Tracking
    PageCount INT,
    WordCount INT,
    EstimatedReviewTime DECIMAL(6,2), -- Hours

    -- Constraints
    CONSTRAINT CK_PublicRecordsReleases_Type CHECK (ReleaseType IN ('Full', 'Redacted', 'Summary', 'Denial', 'Referral')),

    -- Indexes
    INDEX IX_PublicRecordsReleases_Request (RequestID),
    INDEX IX_PublicRecordsReleases_Document (DocumentID),
    INDEX IX_PublicRecordsReleases_Type (ReleaseType),
    INDEX IX_PublicRecordsReleases_Date (ReleaseDate)
);
```

### Communication & Public Engagement

#### Public Notifications & Alerts
```sql
-- Public notifications and alerts
CREATE TABLE PublicNotifications (
    NotificationID INT IDENTITY(1,1) PRIMARY KEY,
    NotificationNumber NVARCHAR(50) UNIQUE NOT NULL,
    Title NVARCHAR(200) NOT NULL,
    Message NVARCHAR(MAX) NOT NULL,
    NotificationType NVARCHAR(20) DEFAULT 'Information', -- Information, Alert, Emergency, Update

    -- Content and media
    Summary NVARCHAR(500),
    ImageURL NVARCHAR(500),
    DocumentURL NVARCHAR(500),
    VideoURL NVARCHAR(500),

    -- Targeting and distribution
    TargetAudience NVARCHAR(MAX), -- JSON: age, location, interests
    GeographicScope NVARCHAR(MAX), -- JSON: cities, counties, zip codes
    DistributionChannels NVARCHAR(MAX), -- JSON: email, sms, website, social media

    -- Scheduling and validity
    PublishDate DATETIME2 DEFAULT GETDATE(),
    ExpirationDate DATETIME2,
    Priority NVARCHAR(10) DEFAULT 'Normal', -- Low, Normal, High, Urgent

    -- Status and tracking
    Status NVARCHAR(20) DEFAULT 'Draft', -- Draft, Published, Expired, Cancelled
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

-- Citizen feedback and surveys
CREATE TABLE CitizenFeedback (
    FeedbackID INT IDENTITY(1,1) PRIMARY KEY,
    CitizenID INT REFERENCES Citizens(CitizenID),
    FeedbackType NVARCHAR(20) NOT NULL, -- Complaint, Suggestion, Survey, Rating

    -- Feedback content
    Subject NVARCHAR(200),
    Description NVARCHAR(MAX),
    Category NVARCHAR(50),
    Subcategory NVARCHAR(50),

    -- Rating and sentiment
    Rating INT CHECK (Rating BETWEEN 1 AND 5),
    Sentiment NVARCHAR(10), -- Positive, Neutral, Negative
    Priority NVARCHAR(10) DEFAULT 'Normal',

    -- Processing
    Status NVARCHAR(20) DEFAULT 'Received', -- Received, UnderReview, Resolved, Closed
    AssignedTo INT,
    AssignedDate DATETIME2,
    ResolutionDate DATETIME2,
    Resolution NVARCHAR(MAX),

    -- Location and context
    Location NVARCHAR(100),
    ServiceRelated NVARCHAR(100), -- Related service or department
    ContactMethod NVARCHAR(20), -- Phone, Email, Website, InPerson

    -- Metadata
    SubmittedDate DATETIME2 DEFAULT GETDATE(),
    SourceChannel NVARCHAR(20), -- Website, App, Phone, Email, InPerson

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
```

## Integration Points

### External Systems
- **Identity verification systems**: SSN validation, address verification, biometric authentication
- **Payment processing**: Fee collection, fine payment, utility billing integration
- **GIS systems**: Geographic information systems for zoning, permits, and location services
- **Document management**: Secure document storage, OCR, and workflow automation
- **Communication platforms**: Email, SMS, push notifications, and social media integration
- **Reporting systems**: Business intelligence, dashboards, and regulatory reporting

### API Endpoints
- **Citizen Services APIs**: Account management, service requests, document access
- **Permit/License APIs**: Application submission, status tracking, renewal processing
- **Public Records APIs**: FOIA requests, document search, public data access
- **Notification APIs**: Alert distribution, subscription management, delivery tracking
- **Analytics APIs**: Service metrics, citizen engagement, performance reporting

## Monitoring & Analytics

### Key Performance Indicators
- **Service Delivery**: Average response time, completion rates, citizen satisfaction scores
- **Permit Processing**: Application processing time, approval rates, fee collection efficiency
- **Public Engagement**: Website traffic, app usage, social media engagement, survey response rates
- **Compliance**: FOIA response times, inspection completion rates, violation resolution rates
- **Operational Efficiency**: Case processing time, resource utilization, cost per service

### Real-Time Dashboards
```sql
-- Government services dashboard
CREATE VIEW GovernmentServicesDashboard AS
SELECT
    -- Service request metrics (current month)
    (SELECT COUNT(*) FROM ServiceRequests
     WHERE MONTH(SubmittedDate) = MONTH(GETDATE())
     AND YEAR(SubmittedDate) = YEAR(GETDATE())) AS RequestsThisMonth,

    (SELECT COUNT(*) FROM ServiceRequests
     WHERE Status IN ('Approved', 'Closed')
     AND MONTH(ActualCompletionDate) = MONTH(GETDATE())) AS CompletedRequestsThisMonth,

    (SELECT AVG(CAST(DATEDIFF(DAY, SubmittedDate, ActualCompletionDate) AS DECIMAL(10,2)))
     FROM ServiceRequests
     WHERE Status IN ('Approved', 'Closed')
     AND MONTH(ActualCompletionDate) = MONTH(GETDATE())) AS AvgCompletionTime,

    (SELECT COUNT(*) FROM ServiceRequests
     WHERE Status NOT IN ('Approved', 'Closed', 'Denied')
     AND SubmittedDate < DATEADD(DAY, -30, GETDATE())) AS OverdueRequests,

    -- Permit/license metrics
    (SELECT COUNT(*) FROM PermitsLicenses
     WHERE MONTH(ApplicationDate) = MONTH(GETDATE())
     AND YEAR(ApplicationDate) = YEAR(GETDATE())) AS PermitsAppliedThisMonth,

    (SELECT COUNT(*) FROM PermitsLicenses
     WHERE Status = 'Issued'
     AND MONTH(IssueDate) = MONTH(GETDATE())) AS PermitsIssuedThisMonth,

    (SELECT SUM(TotalPaid) FROM PermitsLicenses
     WHERE Status = 'Issued'
     AND MONTH(IssueDate) = MONTH(GETDATE())) AS PermitRevenueThisMonth,

    -- Public records metrics
    (SELECT COUNT(*) FROM PublicRecordsRequests
     WHERE MONTH(ReceivedDate) = MONTH(GETDATE())
     AND YEAR(ReceivedDate) = YEAR(GETDATE())) AS FOIARequestsThisMonth,

    (SELECT COUNT(*) FROM PublicRecordsRequests
     WHERE ReviewStatus = 'Completed'
     AND MONTH(ActualResponseDate) = MONTH(GETDATE())) AS FOIARequestsCompleted,

    (SELECT AVG(CAST(DATEDIFF(DAY, ReceivedDate, ActualResponseDate) AS DECIMAL(10,2)))
     FROM PublicRecordsRequests
     WHERE ReviewStatus = 'Completed'
     AND MONTH(ActualResponseDate) = MONTH(GETDATE())) AS AvgFOIAResponseTime,

    -- Citizen engagement metrics
    (SELECT COUNT(*) FROM CitizenFeedback
     WHERE MONTH(SubmittedDate) = MONTH(GETDATE())
     AND YEAR(SubmittedDate) = YEAR(GETDATE())) AS FeedbackReceivedThisMonth,

    (SELECT AVG(CAST(Rating AS DECIMAL(3,2))) FROM CitizenFeedback
     WHERE Rating IS NOT NULL
     AND MONTH(SubmittedDate) = MONTH(GETDATE())) AS AvgCitizenSatisfaction,

    (SELECT COUNT(*) FROM PublicNotifications
     WHERE Status = 'Published'
     AND PublishDate >= DATEADD(MONTH, -1, GETDATE())) AS NotificationsPublished,

    -- Compliance metrics
    (SELECT COUNT(*) FROM PermitInspections
     WHERE MONTH(ActualDate) = MONTH(GETDATE())
     AND YEAR(ActualDate) = YEAR(GETDATE())) AS InspectionsCompleted,

    (SELECT COUNT(*) FROM PermitInspections
     WHERE Result = 'Fail'
     AND MONTH(ActualDate) = MONTH(GETDATE())) AS FailedInspections,

    (SELECT COUNT(*) FROM Documents
     WHERE RetentionEndDate BETWEEN GETDATE() AND DATEADD(MONTH, 6, GETDATE())) AS DocumentsDueForReview

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This government database schema provides a comprehensive foundation for modern public services platforms, supporting citizen engagement, regulatory compliance, public transparency, and enterprise government operations while maintaining security, auditability, and regulatory compliance.
