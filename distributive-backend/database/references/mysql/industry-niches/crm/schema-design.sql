-- CRM Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE CRMDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE CRMDB;
GO

-- Configure database for CRM performance
ALTER DATABASE CRMDB
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
-- CUSTOMER & CONTACT MANAGEMENT
-- =============================================

-- Customer master table
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNumber NVARCHAR(20) UNIQUE NOT NULL,
    CompanyName NVARCHAR(200),
    Industry NVARCHAR(100),
    Website NVARCHAR(500),
    AnnualRevenue DECIMAL(15,2),
    EmployeeCount INT,
    CustomerType NVARCHAR(20) DEFAULT 'Prospect', -- Prospect, Customer, Partner, Competitor
    CustomerStatus NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, Closed
    LeadSource NVARCHAR(50), -- Website, Referral, Trade Show, etc.
    LeadScore INT DEFAULT 0,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastContactDate DATETIME2,
    NextFollowUpDate DATETIME2,

    -- Contact information
    PrimaryEmail NVARCHAR(255),
    PrimaryPhone NVARCHAR(20),
    BillingAddress NVARCHAR(MAX), -- JSON format
    ShippingAddress NVARCHAR(MAX), -- JSON format

    -- Constraints
    CONSTRAINT CK_Customers_Type CHECK (CustomerType IN ('Prospect', 'Customer', 'Partner', 'Competitor')),
    CONSTRAINT CK_Customers_Status CHECK (CustomerStatus IN ('Active', 'Inactive', 'Closed')),

    -- Indexes
    INDEX IX_Customers_Number (CustomerNumber),
    INDEX IX_Customers_Company (CompanyName),
    INDEX IX_Customers_Type (CustomerType),
    INDEX IX_Customers_Status (CustomerStatus),
    INDEX IX_Customers_LeadScore (LeadScore),
    INDEX IX_Customers_CreatedDate (CreatedDate),
    INDEX IX_Customers_LastContact (LastContactDate)
);

-- Contact persons
CREATE TABLE Contacts (
    ContactID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Title NVARCHAR(100),
    Department NVARCHAR(100),
    Email NVARCHAR(255) UNIQUE,
    Phone NVARCHAR(20),
    Mobile NVARCHAR(20),
    IsPrimary BIT DEFAULT 0,
    ContactStatus NVARCHAR(20) DEFAULT 'Active',
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastContactDate DATETIME2,

    -- Personal information
    Birthday DATE,
    LinkedInURL NVARCHAR(500),
    TwitterHandle NVARCHAR(50),
    Notes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_Contacts_Status CHECK (ContactStatus IN ('Active', 'Inactive', 'DoNotContact')),

    -- Indexes
    INDEX IX_Contacts_Customer (CustomerID),
    INDEX IX_Contacts_Email (Email),
    INDEX IX_Contacts_IsPrimary (CustomerID) WHERE IsPrimary = 1,
    INDEX IX_Contacts_Status (ContactStatus),
    INDEX IX_Contacts_LastContact (LastContactDate)
);

-- =============================================
-- SALES & OPPORTUNITY MANAGEMENT
-- =============================================

-- Sales opportunities
CREATE TABLE Opportunities (
    OpportunityID INT IDENTITY(1,1) PRIMARY KEY,
    OpportunityNumber NVARCHAR(20) UNIQUE NOT NULL,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    ContactID INT REFERENCES Contacts(ContactID),
    OpportunityName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    OpportunityType NVARCHAR(50), -- New Business, Upsell, Renewal
    SalesStage NVARCHAR(50) NOT NULL, -- Prospecting, Qualification, Proposal, Negotiation, Closed Won, Closed Lost
    Probability DECIMAL(5,2), -- 0.00 to 1.00
    EstimatedValue DECIMAL(15,2),
    ActualValue DECIMAL(15,2),
    ExpectedCloseDate DATE,
    ActualCloseDate DATE,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastUpdatedDate DATETIME2 DEFAULT GETDATE(),

    -- Assignment
    AssignedTo INT, -- Sales rep UserID
    AssignedDate DATETIME2,
    LeadSource NVARCHAR(50),

    -- Competition
    Competitors NVARCHAR(MAX), -- JSON array
    CompetitiveAdvantages NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_Opportunities_Stage CHECK (SalesStage IN ('Prospecting', 'Qualification', 'Proposal', 'Negotiation', 'Closed Won', 'Closed Lost')),
    CONSTRAINT CK_Opportunities_Probability CHECK (Probability BETWEEN 0.00 AND 1.00),

    -- Indexes
    INDEX IX_Opportunities_Number (OpportunityNumber),
    INDEX IX_Opportunities_Customer (CustomerID),
    INDEX IX_Opportunities_Contact (ContactID),
    INDEX IX_Opportunities_Stage (SalesStage),
    INDEX IX_Opportunities_AssignedTo (AssignedTo),
    INDEX IX_Opportunities_ExpectedClose (ExpectedCloseDate),
    INDEX IX_Opportunities_CreatedDate (CreatedDate)
);

-- Opportunity products
CREATE TABLE OpportunityProducts (
    OpportunityProductID INT IDENTITY(1,1) PRIMARY KEY,
    OpportunityID INT NOT NULL REFERENCES Opportunities(OpportunityID) ON DELETE CASCADE,
    ProductID INT, -- Reference to product catalog
    ProductName NVARCHAR(200),
    ProductDescription NVARCHAR(MAX),
    Quantity DECIMAL(10,2) DEFAULT 1,
    UnitPrice DECIMAL(10,2),
    DiscountPercent DECIMAL(5,2) DEFAULT 0,
    LineTotal DECIMAL(10,2),

    -- Constraints
    CONSTRAINT CK_OpportunityProducts_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_OpportunityProducts_Price CHECK (UnitPrice >= 0),
    CONSTRAINT CK_OpportunityProducts_Discount CHECK (DiscountPercent BETWEEN 0 AND 100),

    -- Indexes
    INDEX IX_OpportunityProducts_Opportunity (OpportunityID),
    INDEX IX_OpportunityProducts_Product (ProductID)
);

-- Sales activities
CREATE TABLE SalesActivities (
    ActivityID INT IDENTITY(1,1) PRIMARY KEY,
    OpportunityID INT REFERENCES Opportunities(OpportunityID),
    ContactID INT REFERENCES Contacts(ContactID),
    CustomerID INT REFERENCES Customers(CustomerID),
    ActivityType NVARCHAR(50) NOT NULL, -- Call, Email, Meeting, Demo, etc.
    Subject NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    ActivityDate DATETIME2 DEFAULT GETDATE(),
    DurationMinutes INT,
    CreatedBy INT NOT NULL, -- User who logged the activity
    AssignedTo INT, -- User responsible for the activity
    Status NVARCHAR(20) DEFAULT 'Completed', -- Scheduled, Completed, Cancelled

    -- Communication details
    Direction NVARCHAR(10), -- Inbound, Outbound (for calls/emails)
    Channel NVARCHAR(50), -- Phone, Email, In-Person, Video, etc.

    -- Constraints
    CONSTRAINT CK_SalesActivities_Type CHECK (ActivityType IN ('Call', 'Email', 'Meeting', 'Demo', 'Task', 'Note')),
    CONSTRAINT CK_SalesActivities_Status CHECK (Status IN ('Scheduled', 'Completed', 'Cancelled')),
    CONSTRAINT CK_SalesActivities_Direction CHECK (Direction IN ('Inbound', 'Outbound')),

    -- Indexes
    INDEX IX_SalesActivities_Opportunity (OpportunityID),
    INDEX IX_SalesActivities_Contact (ContactID),
    INDEX IX_SalesActivities_Customer (CustomerID),
    INDEX IX_SalesActivities_Type (ActivityType),
    INDEX IX_SalesActivities_Date (ActivityDate),
    INDEX IX_SalesActivities_CreatedBy (CreatedBy),
    INDEX IX_SalesActivities_Status (Status)
);

-- =============================================
-- CUSTOMER SERVICE & SUPPORT
-- =============================================

-- Support tickets
CREATE TABLE SupportTickets (
    TicketID INT IDENTITY(1,1) PRIMARY KEY,
    TicketNumber NVARCHAR(20) UNIQUE NOT NULL,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    ContactID INT REFERENCES Contacts(ContactID),
    OpportunityID INT REFERENCES Opportunities(OpportunityID),
    Subject NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    Category NVARCHAR(50), -- Technical, Billing, Feature Request, etc.
    Priority NVARCHAR(20) DEFAULT 'Medium', -- Low, Medium, High, Urgent
    Status NVARCHAR(20) DEFAULT 'Open', -- Open, In Progress, Waiting, Resolved, Closed
    Severity NVARCHAR(20) DEFAULT 'Medium', -- Low, Medium, High, Critical

    -- Assignment and ownership
    AssignedTo INT, -- Support agent UserID
    AssignedDate DATETIME2,
    CreatedBy INT NOT NULL,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastUpdatedDate DATETIME2 DEFAULT GETDATE(),
    ResolvedDate DATETIME2,
    ClosedDate DATETIME2,

    -- SLA tracking
    SLAResponseTime DATETIME2, -- When response was required
    SLAResolutionTime DATETIME2, -- When resolution was required
    ActualResponseTime DATETIME2, -- When response actually happened
    ActualResolutionTime DATETIME2, -- When resolution actually happened

    -- Source and channel
    SourceChannel NVARCHAR(50), -- Email, Phone, Chat, Portal, API
    RelatedTickets NVARCHAR(MAX), -- JSON array of related ticket IDs

    -- Constraints
    CONSTRAINT CK_SupportTickets_Priority CHECK (Priority IN ('Low', 'Medium', 'High', 'Urgent')),
    CONSTRAINT CK_SupportTickets_Status CHECK (Status IN ('Open', 'In Progress', 'Waiting', 'Resolved', 'Closed')),
    CONSTRAINT CK_SupportTickets_Severity CHECK (Severity IN ('Low', 'Medium', 'High', 'Critical')),

    -- Indexes
    INDEX IX_SupportTickets_Number (TicketNumber),
    INDEX IX_SupportTickets_Customer (CustomerID),
    INDEX IX_SupportTickets_Contact (ContactID),
    INDEX IX_SupportTickets_Category (Category),
    INDEX IX_SupportTickets_Priority (Priority),
    INDEX IX_SupportTickets_Status (Status),
    INDEX IX_SupportTickets_AssignedTo (AssignedTo),
    INDEX IX_SupportTickets_CreatedDate (CreatedDate),
    INDEX IX_SupportTickets_SourceChannel (SourceChannel)
);

-- Ticket comments
CREATE TABLE TicketComments (
    CommentID INT IDENTITY(1,1) PRIMARY KEY,
    TicketID INT NOT NULL REFERENCES SupportTickets(TicketID) ON DELETE CASCADE,
    CommentText NVARCHAR(MAX) NOT NULL,
    CommentType NVARCHAR(20) DEFAULT 'Comment', -- Comment, Status Change, Assignment, etc.
    IsInternal BIT DEFAULT 0, -- Visible to customer or internal only
    CreatedBy INT NOT NULL,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_TicketComments_Type CHECK (CommentType IN ('Comment', 'Status Change', 'Assignment', 'SLA Update', 'Resolution')),

    -- Indexes
    INDEX IX_TicketComments_Ticket (TicketID),
    INDEX IX_TicketComments_Type (CommentType),
    INDEX IX_TicketComments_IsInternal (IsInternal),
    INDEX IX_TicketComments_CreatedDate (CreatedDate)
);

-- Knowledge base articles
CREATE TABLE KnowledgeArticles (
    ArticleID INT IDENTITY(1,1) PRIMARY KEY,
    ArticleNumber NVARCHAR(20) UNIQUE NOT NULL,
    Title NVARCHAR(200) NOT NULL,
    Content NVARCHAR(MAX) NOT NULL,
    Summary NVARCHAR(500),
    Category NVARCHAR(100),
    Tags NVARCHAR(MAX), -- JSON array
    Status NVARCHAR(20) DEFAULT 'Published', -- Draft, Published, Archived
    CreatedBy INT NOT NULL,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastModifiedBy INT,
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),
    PublishedDate DATETIME2,

    -- Analytics
    ViewCount INT DEFAULT 0,
    HelpfulVotes INT DEFAULT 0,
    TotalVotes INT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_KnowledgeArticles_Status CHECK (Status IN ('Draft', 'Published', 'Archived')),

    -- Indexes
    INDEX IX_KnowledgeArticles_Number (ArticleNumber),
    INDEX IX_KnowledgeArticles_Title (Title),
    INDEX IX_KnowledgeArticles_Category (Category),
    INDEX IX_KnowledgeArticles_Status (Status),
    INDEX IX_KnowledgeArticles_CreatedDate (CreatedDate),
    INDEX IX_KnowledgeArticles_ViewCount (ViewCount)
);

-- =============================================
-- MARKETING & CAMPAIGN MANAGEMENT
-- =============================================

-- Marketing campaigns
CREATE TABLE MarketingCampaigns (
    CampaignID INT IDENTITY(1,1) PRIMARY KEY,
    CampaignName NVARCHAR(200) NOT NULL,
    CampaignType NVARCHAR(50) NOT NULL, -- Email, Social, PPC, Event, etc.
    Description NVARCHAR(MAX),
    Status NVARCHAR(20) DEFAULT 'Draft', -- Draft, Active, Paused, Completed
    Budget DECIMAL(15,2),
    Spent DECIMAL(15,2) DEFAULT 0,
    TargetAudience NVARCHAR(MAX), -- JSON criteria
    StartDate DATETIME2,
    EndDate DATETIME2,
    CreatedBy INT NOT NULL,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Performance metrics
    Impressions INT DEFAULT 0,
    Clicks INT DEFAULT 0,
    Conversions INT DEFAULT 0,
    Revenue DECIMAL(15,2) DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_MarketingCampaigns_Type CHECK (CampaignType IN ('Email', 'Social', 'PPC', 'Event', 'Content', 'Direct Mail')),
    CONSTRAINT CK_MarketingCampaigns_Status CHECK (Status IN ('Draft', 'Active', 'Paused', 'Completed', 'Cancelled')),

    -- Indexes
    INDEX IX_MarketingCampaigns_Type (CampaignType),
    INDEX IX_MarketingCampaigns_Status (Status),
    INDEX IX_MarketingCampaigns_StartDate (StartDate),
    INDEX IX_MarketingCampaigns_EndDate (EndDate),
    INDEX IX_MarketingCampaigns_CreatedDate (CreatedDate)
);

-- Email templates
CREATE TABLE EmailTemplates (
    TemplateID INT IDENTITY(1,1) PRIMARY KEY,
    TemplateName NVARCHAR(200) NOT NULL,
    Subject NVARCHAR(200),
    HTMLContent NVARCHAR(MAX),
    TextContent NVARCHAR(MAX),
    TemplateType NVARCHAR(50), -- Marketing, Transactional, Newsletter
    CreatedBy INT NOT NULL,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_EmailTemplates_Type CHECK (TemplateType IN ('Marketing', 'Transactional', 'Newsletter')),

    -- Indexes
    INDEX IX_EmailTemplates_Name (TemplateName),
    INDEX IX_EmailTemplates_Type (TemplateType),
    INDEX IX_EmailTemplates_CreatedDate (CreatedDate)
);

-- Email campaigns
CREATE TABLE EmailCampaigns (
    EmailCampaignID INT IDENTITY(1,1) PRIMARY KEY,
    CampaignID INT NOT NULL REFERENCES MarketingCampaigns(CampaignID),
    TemplateID INT REFERENCES EmailTemplates(TemplateID),
    SegmentID INT, -- Reference to audience segment
    FromEmail NVARCHAR(255),
    FromName NVARCHAR(200),
    Subject NVARCHAR(200),
    SendDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Draft',

    -- Send statistics
    Recipients INT DEFAULT 0,
    Delivered INT DEFAULT 0,
    Opened INT DEFAULT 0,
    Clicked INT DEFAULT 0,
    Bounced INT DEFAULT 0,
    Unsubscribed INT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_EmailCampaigns_Status CHECK (Status IN ('Draft', 'Scheduled', 'Sending', 'Sent', 'Cancelled')),

    -- Indexes
    INDEX IX_EmailCampaigns_Campaign (CampaignID),
    INDEX IX_EmailCampaigns_Template (TemplateID),
    INDEX IX_EmailCampaigns_Status (Status),
    INDEX IX_EmailCampaigns_SendDate (SendDate)
);

-- =============================================
-- ANALYTICS & REPORTING
-- =============================================

-- Customer analytics
CREATE TABLE CustomerAnalytics (
    AnalyticsID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    Date DATE NOT NULL,
    Interactions INT DEFAULT 0,
    OpportunitiesCreated INT DEFAULT 0,
    TicketsOpened INT DEFAULT 0,
    Revenue DECIMAL(15,2) DEFAULT 0,
    EmailOpens INT DEFAULT 0,
    EmailClicks INT DEFAULT 0,
    WebsiteVisits INT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_CustomerAnalytics_CustomerDate UNIQUE (CustomerID, Date),

    -- Indexes
    INDEX IX_CustomerAnalytics_Customer (CustomerID),
    INDEX IX_CustomerAnalytics_Date (Date)
);

-- Sales performance analytics
CREATE TABLE SalesPerformance (
    PerformanceID INT IDENTITY(1,1) PRIMARY KEY,
    SalesRepID INT NOT NULL,
    Date DATE NOT NULL,
    LeadsAssigned INT DEFAULT 0,
    OpportunitiesCreated INT DEFAULT 0,
    OpportunitiesWon INT DEFAULT 0,
    OpportunitiesLost INT DEFAULT 0,
    Revenue DECIMAL(15,2) DEFAULT 0,
    CallsMade INT DEFAULT 0,
    EmailsSent INT DEFAULT 0,
    MeetingsHeld INT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_SalesPerformance_RepDate UNIQUE (SalesRepID, Date),

    -- Indexes
    INDEX IX_SalesPerformance_SalesRep (SalesRepID),
    INDEX IX_SalesPerformance_Date (Date)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Customer 360 view
CREATE VIEW vw_Customer360
AS
SELECT
    c.CustomerID,
    c.CustomerNumber,
    c.CompanyName,
    c.CustomerType,
    c.CustomerStatus,
    c.LeadScore,
    c.CreatedDate,
    c.LastContactDate,

    -- Contact information
    (SELECT COUNT(*) FROM Contacts WHERE CustomerID = c.CustomerID AND ContactStatus = 'Active') AS ActiveContacts,

    -- Sales information
    (SELECT COUNT(*) FROM Opportunities WHERE CustomerID = c.CustomerID AND SalesStage NOT IN ('Closed Won', 'Closed Lost')) AS OpenOpportunities,
    (SELECT SUM(EstimatedValue) FROM Opportunities WHERE CustomerID = c.CustomerID AND SalesStage NOT IN ('Closed Won', 'Closed Lost')) AS PipelineValue,
    (SELECT SUM(ActualValue) FROM Opportunities WHERE CustomerID = c.CustomerID AND SalesStage = 'Closed Won') AS TotalRevenue,

    -- Service information
    (SELECT COUNT(*) FROM SupportTickets WHERE CustomerID = c.CustomerID AND Status IN ('Open', 'In Progress')) AS OpenTickets,
    (SELECT COUNT(*) FROM SupportTickets WHERE CustomerID = c.CustomerID AND Status = 'Resolved') AS ResolvedTickets,

    -- Marketing information
    (SELECT COUNT(*) FROM EmailCampaigns ec
     INNER JOIN MarketingCampaigns mc ON ec.CampaignID = mc.CampaignID
     WHERE mc.TargetAudience LIKE '%' + CAST(c.CustomerID AS NVARCHAR(10)) + '%') AS CampaignsReceived,

    -- Overall engagement score
    (SELECT AVG(Interactions) FROM CustomerAnalytics WHERE CustomerID = c.CustomerID AND Date >= DATEADD(MONTH, -3, GETDATE())) AS AvgMonthlyInteractions

FROM Customers c
WHERE c.CustomerStatus = 'Active';
GO

-- Sales pipeline view
CREATE VIEW vw_SalesPipeline
AS
SELECT
    o.OpportunityID,
    o.OpportunityNumber,
    o.OpportunityName,
    c.CompanyName,
    o.SalesStage,
    o.Probability,
    o.EstimatedValue,
    o.ExpectedCloseDate,
    DATEDIFF(DAY, GETDATE(), o.ExpectedCloseDate) AS DaysToClose,
    o.AssignedTo,
    o.CreatedDate,

    -- Pipeline metrics
    CASE
        WHEN o.SalesStage IN ('Prospecting', 'Qualification') THEN 'Early Stage'
        WHEN o.SalesStage IN ('Proposal', 'Negotiation') THEN 'Late Stage'
        WHEN o.SalesStage = 'Closed Won' THEN 'Won'
        WHEN o.SalesStage = 'Closed Lost' THEN 'Lost'
        ELSE 'Other'
    END AS PipelineStage,

    -- Weighted value for forecasting
    o.EstimatedValue * (o.Probability / 100) AS WeightedValue

FROM Opportunities o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
WHERE o.SalesStage NOT IN ('Closed Won', 'Closed Lost')
ORDER BY o.EstimatedValue DESC, o.ExpectedCloseDate;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update opportunity last modified date
CREATE TRIGGER TR_Opportunities_LastModified
ON Opportunities
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE o
    SET o.LastUpdatedDate = GETDATE()
    FROM Opportunities o
    INNER JOIN inserted i ON o.OpportunityID = i.OpportunityID;
END;
GO

-- Update customer last contact date
CREATE TRIGGER TR_SalesActivities_UpdateLastContact
ON SalesActivities
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE c
    SET c.LastContactDate = GETDATE()
    FROM Customers c
    INNER JOIN inserted i ON c.CustomerID = i.CustomerID;
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Create opportunity procedure
CREATE PROCEDURE sp_CreateOpportunity
    @CustomerID INT,
    @ContactID INT = NULL,
    @OpportunityName NVARCHAR(200),
    @EstimatedValue DECIMAL(15,2),
    @ExpectedCloseDate DATE,
    @AssignedTo INT = NULL,
    @Description NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OpportunityNumber NVARCHAR(20);

    -- Generate opportunity number
    SET @OpportunityNumber = 'OPP-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                           RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                           RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    INSERT INTO Opportunities (
        OpportunityNumber, CustomerID, ContactID, OpportunityName, Description,
        SalesStage, EstimatedValue, ExpectedCloseDate, AssignedTo, AssignedDate
    )
    VALUES (
        @OpportunityNumber, @CustomerID, @ContactID, @OpportunityName, @Description,
        'Prospecting', @EstimatedValue, @ExpectedCloseDate, @AssignedTo, GETDATE()
    );

    SELECT SCOPE_IDENTITY() AS OpportunityID, @OpportunityNumber AS OpportunityNumber;
END;
GO

-- Create support ticket procedure
CREATE PROCEDURE sp_CreateSupportTicket
    @CustomerID INT,
    @ContactID INT = NULL,
    @Subject NVARCHAR(200),
    @Description NVARCHAR(MAX),
    @Category NVARCHAR(50),
    @Priority NVARCHAR(20) = 'Medium',
    @CreatedBy INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TicketNumber NVARCHAR(20);

    -- Generate ticket number
    SET @TicketNumber = 'TKT-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                       RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                       RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    -- Calculate SLA times based on priority
    DECLARE @SLAResponseTime DATETIME2, @SLAResolutionTime DATETIME2;

    SET @SLAResponseTime = CASE @Priority
        WHEN 'Urgent' THEN DATEADD(HOUR, 1, GETDATE())
        WHEN 'High' THEN DATEADD(HOUR, 4, GETDATE())
        WHEN 'Medium' THEN DATEADD(HOUR, 24, GETDATE())
        ELSE DATEADD(HOUR, 48, GETDATE())
    END;

    SET @SLAResolutionTime = CASE @Priority
        WHEN 'Urgent' THEN DATEADD(HOUR, 4, GETDATE())
        WHEN 'High' THEN DATEADD(HOUR, 24, GETDATE())
        WHEN 'Medium' THEN DATEADD(HOUR, 72, GETDATE())
        ELSE DATEADD(HOUR, 168, GETDATE())
    END;

    INSERT INTO SupportTickets (
        TicketNumber, CustomerID, ContactID, Subject, Description, Category, Priority,
        CreatedBy, SLAResponseTime, SLAResolutionTime
    )
    VALUES (
        @TicketNumber, @CustomerID, @ContactID, @Subject, @Description, @Category, @Priority,
        @CreatedBy, @SLAResponseTime, @SLAResolutionTime
    );

    SELECT SCOPE_IDENTITY() AS TicketID, @TicketNumber AS TicketNumber;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample customer
INSERT INTO Customers (CustomerNumber, CompanyName, CustomerType, PrimaryEmail, Industry) VALUES
('CUST-000001', 'Acme Corporation', 'Customer', 'contact@acme.com', 'Manufacturing');

-- Insert sample contact
INSERT INTO Contacts (CustomerID, FirstName, LastName, Title, Email, IsPrimary) VALUES
(1, 'John', 'Smith', 'CEO', 'john.smith@acme.com', 1);

-- Insert sample opportunity
INSERT INTO Opportunities (OpportunityNumber, CustomerID, ContactID, OpportunityName, SalesStage, EstimatedValue, ExpectedCloseDate) VALUES
('OPP-202412-00001', 1, 1, 'Enterprise Software License', 'Proposal', 150000.00, '2024-12-31');

-- Insert sample support ticket
INSERT INTO SupportTickets (TicketNumber, CustomerID, ContactID, Subject, Description, Category, Priority) VALUES
('TKT-202412-00001', 1, 1, 'Login Issues', 'Unable to access the admin portal', 'Technical', 'High');

PRINT 'CRM database schema created successfully!';
GO
