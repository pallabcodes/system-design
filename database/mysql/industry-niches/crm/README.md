# CRM Platform Database Design

## Overview

This comprehensive database schema supports modern Customer Relationship Management (CRM) platforms including lead management, sales pipeline tracking, customer service, marketing automation, and enterprise analytics. The design handles complex customer interactions, multi-channel communications, sales forecasting, and comprehensive customer lifecycle management.

## Key Features

### 🎯 Lead & Opportunity Management
- **Lead qualification and scoring** with automated nurturing workflows
- **Sales pipeline management** with stages, forecasting, and conversion tracking
- **Opportunity tracking** with products, pricing, and competitive analysis
- **Automated lead assignment** based on territory, capacity, and expertise

### 👥 Customer Service & Support
- **Multi-channel ticketing system** with email, phone, chat, and social media integration
- **Knowledge base management** with articles, FAQs, and self-service portals
- **Customer satisfaction tracking** with surveys, NPS, and feedback analysis
- **Service level agreement (SLA)** monitoring and escalation workflows

### 📊 Marketing Automation & Analytics
- **Campaign management** with multi-channel execution and attribution tracking
- **Customer segmentation** with dynamic lists and behavioral targeting
- **Email marketing** with templates, A/B testing, and deliverability tracking
- **Marketing ROI analysis** with lead scoring and revenue attribution

## Database Schema Highlights

### Core Tables

#### Customer & Contact Management
```sql
-- Customer master table with comprehensive CRM data
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
    IX_Customers_LastContact (LastContactDate)
);

-- Contact persons within customer organizations
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
```

#### Sales Pipeline & Opportunities
```sql
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

-- Opportunity products/line items
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

-- Sales activities and interactions
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
```

### Customer Service & Support

#### Support Tickets & Cases
```sql
-- Support tickets/cases
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

-- Ticket comments and updates
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
```

#### Knowledge Base & Self-Service
```sql
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

-- Article feedback
CREATE TABLE ArticleFeedback (
    FeedbackID INT IDENTITY(1,1) PRIMARY KEY,
    ArticleID INT NOT NULL REFERENCES KnowledgeArticles(ArticleID) ON DELETE CASCADE,
    UserID INT, -- Can be anonymous
    Rating INT CHECK (Rating BETWEEN 1 AND 5),
    Comments NVARCHAR(MAX),
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Indexes
    INDEX IX_ArticleFeedback_Article (ArticleID),
    INDEX IX_ArticleFeedback_Rating (Rating),
    INDEX IX_ArticleFeedback_Date (CreatedDate)
);
```

### Marketing & Campaign Management

#### Marketing Campaigns
```sql
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

-- Email campaigns and templates
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
```

#### Analytics & Reporting
```sql
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
```

## Integration Points

### External Systems
- **Email service providers**: SendGrid, Mailchimp for marketing campaigns
- **Telephony systems**: Twilio, RingCentral for call center integration
- **ERP systems**: SAP, Oracle for order and inventory data
- **Marketing automation**: HubSpot, Marketo for lead nurturing
- **Help desk systems**: Zendesk, ServiceNow for ticket management
- **Analytics platforms**: Google Analytics, Salesforce for reporting

### API Endpoints
- **Customer APIs**: Profile management, contact updates, data synchronization
- **Sales APIs**: Opportunity tracking, pipeline management, forecasting
- **Service APIs**: Ticket creation, knowledge base access, SLA monitoring
- **Marketing APIs**: Campaign management, email sending, analytics
- **Analytics APIs**: Reporting data, dashboard metrics, custom queries

## Monitoring & Analytics

### Key Performance Indicators
- **Sales Performance**: Pipeline velocity, win rates, deal size, sales cycle length
- **Customer Service**: First response time, resolution time, customer satisfaction
- **Marketing Effectiveness**: Lead generation, conversion rates, campaign ROI
- **Customer Health**: Engagement scores, retention rates, churn risk
- **Operational Efficiency**: Process automation, data quality, user adoption

### Real-Time Dashboards
```sql
-- CRM operations dashboard
CREATE VIEW CRMOperationsDashboard AS
SELECT
    -- Sales pipeline metrics (current month)
    (SELECT COUNT(*) FROM Opportunities
     WHERE MONTH(CreatedDate) = MONTH(GETDATE())
     AND YEAR(CreatedDate) = YEAR(GETDATE())) AS NewOpportunities,

    (SELECT SUM(EstimatedValue) FROM Opportunities
     WHERE SalesStage NOT IN ('Closed Won', 'Closed Lost')
     AND MONTH(CreatedDate) = MONTH(GETDATE())) AS PipelineValue,

    (SELECT COUNT(*) FROM Opportunities
     WHERE SalesStage = 'Closed Won'
     AND MONTH(ActualCloseDate) = MONTH(GETDATE())) AS WonOpportunities,

    -- Customer service metrics
    (SELECT COUNT(*) FROM SupportTickets
     WHERE Status IN ('Open', 'In Progress')) AS OpenTickets,

    (SELECT AVG(CAST(DATEDIFF(MINUTE, CreatedDate, ActualResponseTime) AS DECIMAL(10,2)))
     FROM SupportTickets
     WHERE MONTH(CreatedDate) = MONTH(GETDATE())
     AND ActualResponseTime IS NOT NULL) AS AvgResponseTime,

    (SELECT COUNT(*) FROM SupportTickets
     WHERE Status = 'Resolved'
     AND MONTH(ResolvedDate) = MONTH(GETDATE())) AS ResolvedTickets,

    -- Marketing metrics
    (SELECT COUNT(*) FROM MarketingCampaigns
     WHERE Status = 'Active') AS ActiveCampaigns,

    (SELECT SUM(Impressions) FROM MarketingCampaigns
     WHERE MONTH(StartDate) = MONTH(GETDATE())) AS CampaignImpressions,

    (SELECT SUM(Conversions) FROM MarketingCampaigns
     WHERE MONTH(StartDate) = MONTH(GETDATE())) AS CampaignConversions,

    -- Customer metrics
    (SELECT COUNT(*) FROM Customers
     WHERE CustomerType = 'Customer'
     AND MONTH(CreatedDate) = MONTH(GETDATE())) AS NewCustomers,

    (SELECT COUNT(*) FROM Customers
     WHERE LastContactDate < DATEADD(DAY, -30, GETDATE())) AS InactiveCustomers,

    -- Lead metrics
    (SELECT COUNT(*) FROM Customers
     WHERE CustomerType = 'Prospect'
     AND MONTH(CreatedDate) = MONTH(GETDATE())) AS NewLeads,

    (SELECT AVG(CAST(LeadScore AS DECIMAL(10,2))) FROM Customers
     WHERE CustomerType = 'Prospect') AS AvgLeadScore

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This CRM database schema provides a comprehensive foundation for modern customer relationship management platforms, supporting sales, service, and marketing operations with enterprise-level analytics and integration capabilities.
