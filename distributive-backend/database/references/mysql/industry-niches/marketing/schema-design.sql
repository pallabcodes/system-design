-- Marketing & Analytics Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE MarketingDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE MarketingDB;
GO

-- Configure database for marketing analytics performance
ALTER DATABASE MarketingDB
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
-- CUSTOMER DATA PLATFORM
-- =============================================

-- Customer profiles
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNumber NVARCHAR(50) UNIQUE NOT NULL,
    MasterCustomerID INT REFERENCES Customers(CustomerID), -- For identity resolution

    -- Identity information
    Email NVARCHAR(255),
    Phone NVARCHAR(20),
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    DateOfBirth DATE,
    Gender NVARCHAR(10),

    -- Contact preferences
    EmailOptIn BIT DEFAULT 1,
    SmsOptIn BIT DEFAULT 0,
    PushOptIn BIT DEFAULT 0,
    DirectMailOptIn BIT DEFAULT 0,

    -- Profile enrichment
    Company NVARCHAR(200),
    JobTitle NVARCHAR(100),
    Industry NVARCHAR(100),
    IncomeRange NVARCHAR(50),
    Education NVARCHAR(50),

    -- Geographic data
    Address NVARCHAR(MAX), -- JSON formatted
    City NVARCHAR(100),
    State NVARCHAR(50),
    Country NVARCHAR(100),
    PostalCode NVARCHAR(20),
    TimeZone NVARCHAR(50),

    -- Customer lifecycle
    CustomerStatus NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, Churned, Prospect
    CustomerSegment NVARCHAR(100),
    CustomerValue NVARCHAR(20), -- High, Medium, Low
    AcquisitionDate DATETIME2,
    FirstPurchaseDate DATETIME2,
    LastActivityDate DATETIME2,

    -- Privacy and consent
    PrivacyConsent NVARCHAR(MAX), -- JSON formatted consent records
    DataRetention NVARCHAR(MAX), -- JSON formatted retention policies

    -- Constraints
    CONSTRAINT CK_Customers_Status CHECK (CustomerStatus IN ('Active', 'Inactive', 'Churned', 'Prospect', 'Lead')),
    CONSTRAINT CK_Customers_Value CHECK (CustomerValue IN ('High', 'Medium', 'Low')),
    CONSTRAINT CK_Customers_Gender CHECK (Gender IN ('Male', 'Female', 'Other', 'PreferNotToSay')),

    -- Indexes
    INDEX IX_Customers_Number (CustomerNumber),
    INDEX IX_Customers_Email (Email),
    INDEX IX_Customers_Phone (Phone),
    INDEX IX_Customers_Status (CustomerStatus),
    INDEX IX_Customers_Segment (CustomerSegment),
    INDEX IX_Customers_LastActivity (LastActivityDate DESC),
    INDEX IX_Customers_Acquisition (AcquisitionDate)
);

-- Customer events (partitioned for performance)
CREATE TABLE CustomerEvents (
    EventID BIGINT IDENTITY(1,1) PRIMARY KEY, -- Large table for high-volume events
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),

    -- Event metadata
    EventType NVARCHAR(100) NOT NULL, -- PageView, Purchase, EmailOpen, CartAbandon, etc.
    EventCategory NVARCHAR(50), -- Acquisition, Engagement, Conversion, Retention
    EventSource NVARCHAR(50), -- Website, MobileApp, Email, Social, PaidAds, etc.

    -- Event data
    EventDateTime DATETIME2 NOT NULL DEFAULT GETDATE(),
    SessionID NVARCHAR(100),
    CampaignID NVARCHAR(100),
    Channel NVARCHAR(50),

    -- Event properties (JSON)
    EventProperties NVARCHAR(MAX), -- Flexible event data storage

    -- Geographic and device data
    IPAddress NVARCHAR(45),
    UserAgent NVARCHAR(MAX),
    DeviceType NVARCHAR(50), -- Desktop, Mobile, Tablet
    Browser NVARCHAR(50),
    OperatingSystem NVARCHAR(50),
    Location NVARCHAR(MAX), -- JSON: city, region, country

    -- Attribution data
    UTMSource NVARCHAR(100),
    UTMMedium NVARCHAR(100),
    UTMCampaign NVARCHAR(100),
    UTMContent NVARCHAR(100),
    UTMTerm NVARCHAR(100),

    -- Processing metadata
    ProcessedDateTime DATETIME2,
    IsProcessed BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_CustomerEvents_Type CHECK (EventType IN ('PageView', 'Purchase', 'EmailOpen', 'EmailClick', 'CartAbandon', 'FormSubmit', 'Download', 'Registration', 'Login', 'Search', 'SocialShare', 'VideoView')),
    CONSTRAINT CK_CustomerEvents_Category CHECK (EventCategory IN ('Acquisition', 'Engagement', 'Conversion', 'Retention', 'Advocacy')),
    CONSTRAINT CK_CustomerEvents_Source CHECK (EventSource IN ('Website', 'MobileApp', 'Email', 'SocialMedia', 'PaidAds', 'OrganicSearch', 'Direct', 'Referral')),

    -- Indexes
    INDEX IX_CustomerEvents_Customer (CustomerID),
    INDEX IX_CustomerEvents_Type (EventType),
    INDEX IX_CustomerEvents_Category (EventCategory),
    INDEX IX_CustomerEvents_Source (EventSource),
    INDEX IX_CustomerEvents_DateTime (EventDateTime),
    INDEX IX_CustomerEvents_Session (SessionID),
    INDEX IX_CustomerEvents_Campaign (CampaignID),
    INDEX IX_CustomerEvents_IsProcessed (IsProcessed)
);

-- Customer segments
CREATE TABLE CustomerSegments (
    SegmentID INT IDENTITY(1,1) PRIMARY KEY,
    SegmentCode NVARCHAR(50) UNIQUE NOT NULL,
    SegmentName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Segment definition
    SegmentType NVARCHAR(20) DEFAULT 'Dynamic', -- Static, Dynamic, Predictive
    SegmentCriteria NVARCHAR(MAX), -- JSON: rules for dynamic segments

    -- Segment properties
    SegmentCategory NVARCHAR(50), -- Demographic, Behavioral, Geographic, etc.
    ParentSegmentID INT REFERENCES CustomerSegments(SegmentID),

    -- Population and refresh
    EstimatedSize INT,
    ActualSize INT,
    LastRefreshDate DATETIME2,
    RefreshFrequency NVARCHAR(20), -- RealTime, Hourly, Daily, Weekly

    -- Usage and performance
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_CustomerSegments_Type CHECK (SegmentType IN ('Static', 'Dynamic', 'Predictive')),
    CONSTRAINT CK_CustomerSegments_Category CHECK (SegmentCategory IN ('Demographic', 'Behavioral', 'Geographic', 'Transactional', 'Engagement', 'Lifecycle')),
    CONSTRAINT CK_CustomerSegments_Frequency CHECK (RefreshFrequency IN ('RealTime', 'Hourly', 'Daily', 'Weekly', 'Monthly')),

    -- Indexes
    INDEX IX_CustomerSegments_Code (SegmentCode),
    INDEX IX_CustomerSegments_Type (SegmentType),
    INDEX IX_CustomerSegments_Category (SegmentCategory),
    INDEX IX_CustomerSegments_IsActive (IsActive),
    INDEX IX_CustomerSegments_LastRefresh (LastRefreshDate)
);

-- =============================================
-- CAMPAIGN MANAGEMENT
-- =============================================

-- Marketing campaigns
CREATE TABLE Campaigns (
    CampaignID INT IDENTITY(1,1) PRIMARY KEY,
    CampaignCode NVARCHAR(50) UNIQUE NOT NULL,
    CampaignName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Campaign details
    CampaignType NVARCHAR(50), -- Email, Social, PaidSearch, Display, etc.
    CampaignObjective NVARCHAR(100), -- Awareness, Consideration, Conversion, Retention
    CampaignStatus NVARCHAR(20) DEFAULT 'Draft', -- Draft, Planned, Active, Paused, Completed, Cancelled

    -- Timing and scheduling
    PlannedStartDate DATETIME2,
    PlannedEndDate DATETIME2,
    ActualStartDate DATETIME2,
    ActualEndDate DATETIME2,

    -- Budget and targeting
    BudgetAmount DECIMAL(12,2),
    BudgetCurrency NVARCHAR(3) DEFAULT 'USD',
    TargetAudience NVARCHAR(MAX), -- JSON: segment IDs and criteria
    GeographicTargeting NVARCHAR(MAX), -- JSON: locations

    -- Creative assets
    CreativeAssets NVARCHAR(MAX), -- JSON: images, videos, copy
    LandingPages NVARCHAR(MAX), -- JSON: URLs and descriptions

    -- Campaign metadata
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy NVARCHAR(100),
    ModifiedDate DATETIME2 DEFAULT GETDATE(),
    ModifiedBy NVARCHAR(100),

    -- Performance tracking
    ExpectedROI DECIMAL(5,4),
    ActualROI DECIMAL(5,4),

    -- Constraints
    CONSTRAINT CK_Campaigns_Type CHECK (CampaignType IN ('Email', 'SocialMedia', 'PaidSearch', 'DisplayAds', 'ContentMarketing', 'Event', 'DirectMail', 'SMS', 'PushNotification')),
    CONSTRAINT CK_Campaigns_Objective CHECK (CampaignObjective IN ('Awareness', 'Consideration', 'Conversion', 'Retention', 'Advocacy', 'LeadGeneration')),
    CONSTRAINT CK_Campaigns_Status CHECK (CampaignStatus IN ('Draft', 'Planned', 'Active', 'Paused', 'Completed', 'Cancelled')),

    -- Indexes
    INDEX IX_Campaigns_Code (CampaignCode),
    INDEX IX_Campaigns_Type (CampaignType),
    INDEX IX_Campaigns_Status (CampaignStatus),
    INDEX IX_Campaigns_StartDate (PlannedStartDate),
    INDEX IX_Campaigns_EndDate (PlannedEndDate)
);

-- Campaign activities
CREATE TABLE CampaignActivities (
    ActivityID INT IDENTITY(1,1) PRIMARY KEY,
    CampaignID INT NOT NULL REFERENCES Campaigns(CampaignID) ON DELETE CASCADE,
    ActivityCode NVARCHAR(50) UNIQUE NOT NULL,
    ActivityName NVARCHAR(200) NOT NULL,

    -- Activity details
    ActivityType NVARCHAR(50), -- EmailSend, AdPlacement, SocialPost, etc.
    Channel NVARCHAR(50), -- Email, Facebook, GoogleAds, etc.
    Platform NVARCHAR(50), -- Mailchimp, HubSpot, Google Analytics, etc.

    -- Scheduling
    ScheduledDateTime DATETIME2,
    ExecutedDateTime DATETIME2,
    DurationMinutes INT,

    -- Targeting and content
    TargetSegment NVARCHAR(MAX), -- JSON: segment criteria
    Content NVARCHAR(MAX), -- JSON: subject, body, images
    Creative NVARCHAR(MAX), -- JSON: ad copy, images, videos

    -- Execution status
    Status NVARCHAR(20) DEFAULT 'Scheduled', -- Scheduled, Executing, Completed, Failed, Cancelled
    ExecutionNotes NVARCHAR(MAX),

    -- Performance data (populated post-execution)
    Impressions INT DEFAULT 0,
    Clicks INT DEFAULT 0,
    Conversions INT DEFAULT 0,
    Spend DECIMAL(10,2) DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_CampaignActivities_Type CHECK (ActivityType IN ('EmailSend', 'AdPlacement', 'SocialPost', 'ContentPublish', 'EventPromotion', 'SMSBlast', 'PushNotification')),
    CONSTRAINT CK_CampaignActivities_Status CHECK (Status IN ('Scheduled', 'Executing', 'Completed', 'Failed', 'Cancelled')),

    -- Indexes
    INDEX IX_CampaignActivities_Campaign (CampaignID),
    INDEX IX_CampaignActivities_Type (ActivityType),
    INDEX IX_CampaignActivities_Channel (Channel),
    INDEX IX_CampaignActivities_Status (Status),
    INDEX IX_CampaignActivities_Scheduled (ScheduledDateTime),
    INDEX IX_CampaignActivities_Executed (ExecutedDateTime)
);

-- =============================================
-- ATTRIBUTION & ANALYTICS
-- =============================================

-- Attribution touchpoints
CREATE TABLE AttributionTouchpoints (
    TouchpointID BIGINT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    ConversionID NVARCHAR(100), -- Links to conversion event

    -- Touchpoint data
    TouchpointDateTime DATETIME2 NOT NULL,
    Channel NVARCHAR(50) NOT NULL,
    Campaign NVARCHAR(100),
    Source NVARCHAR(100),
    Medium NVARCHAR(100),
    Content NVARCHAR(100),

    -- Attribution values (calculated)
    FirstTouchAttribution DECIMAL(5,4) DEFAULT 0,
    LastTouchAttribution DECIMAL(5,4) DEFAULT 0,
    LinearAttribution DECIMAL(5,4) DEFAULT 0,
    TimeDecayAttribution DECIMAL(5,4) DEFAULT 0,
    PositionBasedAttribution DECIMAL(5,4) DEFAULT 0,
    DataDrivenAttribution DECIMAL(5,4) DEFAULT 0,

    -- Touchpoint value
    TouchpointValue DECIMAL(10,2), -- Revenue attributed to this touchpoint
    InteractionType NVARCHAR(50), -- Click, View, Open, Purchase, etc.

    -- Processing metadata
    AttributionModel NVARCHAR(50), -- FirstTouch, LastTouch, Linear, etc.
    ProcessedDateTime DATETIME2,
    IsProcessed BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_AttributionTouchpoints_Channel CHECK (Channel IN ('Email', 'Social', 'PaidSearch', 'Display', 'Organic', 'Direct', 'Referral')),
    CONSTRAINT CK_AttributionTouchpoints_Interaction CHECK (InteractionType IN ('Impression', 'Click', 'Open', 'View', 'Download', 'Purchase', 'Registration', 'Lead')),
    CONSTRAINT CK_AttributionTouchpoints_Model CHECK (AttributionModel IN ('FirstTouch', 'LastTouch', 'Linear', 'TimeDecay', 'PositionBased', 'DataDriven', 'Custom')),

    -- Indexes
    INDEX IX_AttributionTouchpoints_Customer (CustomerID),
    INDEX IX_AttributionTouchpoints_Conversion (ConversionID),
    INDEX IX_AttributionTouchpoints_Channel (Channel),
    INDEX IX_AttributionTouchpoints_DateTime (TouchpointDateTime),
    INDEX IX_AttributionTouchpoints_IsProcessed (IsProcessed)
);

-- Marketing metrics
CREATE TABLE MarketingMetrics (
    MetricID INT IDENTITY(1,1) PRIMARY KEY,
    MetricCode NVARCHAR(50) UNIQUE NOT NULL,
    MetricName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),

    -- Metric definition
    MetricCategory NVARCHAR(50), -- Acquisition, Engagement, Conversion, Retention, Revenue
    MetricType NVARCHAR(20), -- Count, Rate, Ratio, Value, Average
    CalculationMethod NVARCHAR(MAX), -- SQL or formula for calculation

    -- Data source
    DataSource NVARCHAR(100), -- Table or system where data comes from
    UpdateFrequency NVARCHAR(20), -- RealTime, Hourly, Daily, Weekly

    -- Thresholds and alerts
    TargetValue DECIMAL(12,4),
    WarningThreshold DECIMAL(12,4),
    CriticalThreshold DECIMAL(12,4),

    -- Status
    IsActive BIT DEFAULT 1,
    LastCalculated DATETIME2,

    -- Constraints
    CONSTRAINT CK_MarketingMetrics_Category CHECK (MetricCategory IN ('Acquisition', 'Engagement', 'Conversion', 'Retention', 'Revenue', 'Cost', 'ROI')),
    CONSTRAINT CK_MarketingMetrics_Type CHECK (MetricType IN ('Count', 'Rate', 'Ratio', 'Value', 'Average', 'Percentage')),
    CONSTRAINT CK_MarketingMetrics_Frequency CHECK (UpdateFrequency IN ('RealTime', 'Hourly', 'Daily', 'Weekly', 'Monthly')),

    -- Indexes
    INDEX IX_MarketingMetrics_Code (MetricCode),
    INDEX IX_MarketingMetrics_Category (MetricCategory),
    INDEX IX_MarketingMetrics_IsActive (IsActive),
    INDEX IX_MarketingMetrics_LastCalculated (LastCalculated)
);

-- Metric values
CREATE TABLE MetricValues (
    ValueID BIGINT IDENTITY(1,1) PRIMARY KEY,
    MetricID INT NOT NULL REFERENCES MarketingMetrics(MetricID),
    DateRecorded DATETIME2 NOT NULL DEFAULT GETDATE(),
    TimeGranularity NVARCHAR(20) DEFAULT 'Daily', -- Hourly, Daily, Weekly, Monthly

    -- Metric value
    MetricValue DECIMAL(15,4),
    PreviousValue DECIMAL(15,4),
    ChangePercent DECIMAL(8,4),

    -- Context
    CampaignID INT REFERENCES Campaigns(CampaignID),
    Channel NVARCHAR(50),
    Segment NVARCHAR(100),

    -- Quality indicators
    IsEstimated BIT DEFAULT 0,
    ConfidenceLevel DECIMAL(5,4),
    DataQuality NVARCHAR(20) DEFAULT 'Good', -- Good, Estimated, Incomplete, Bad

    -- Constraints
    CONSTRAINT CK_MetricValues_Granularity CHECK (TimeGranularity IN ('Hourly', 'Daily', 'Weekly', 'Monthly', 'Yearly')),
    CONSTRAINT CK_MetricValues_Quality CHECK (DataQuality IN ('Good', 'Estimated', 'Incomplete', 'Bad')),

    -- Indexes
    INDEX IX_MetricValues_Metric (MetricID),
    INDEX IX_MetricValues_Date (DateRecorded),
    INDEX IX_MetricValues_Granularity (TimeGranularity),
    INDEX IX_MetricValues_Campaign (CampaignID),
    INDEX IX_MetricValues_Channel (Channel)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Campaign performance view
CREATE VIEW vw_CampaignPerformance
AS
SELECT
    c.CampaignID,
    c.CampaignName,
    c.CampaignType,
    c.CampaignStatus,
    c.BudgetAmount,
    c.ActualROI,

    -- Performance metrics
    (SELECT SUM(ca.Impressions) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) AS TotalImpressions,
    (SELECT SUM(ca.Clicks) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) AS TotalClicks,
    (SELECT SUM(ca.Conversions) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) AS TotalConversions,
    (SELECT SUM(ca.Spend) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) AS TotalSpend,

    -- Calculated metrics
    CASE
        WHEN (SELECT SUM(ca.Impressions) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) > 0
        THEN CAST((SELECT SUM(ca.Clicks) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) AS DECIMAL(10,4)) /
             (SELECT SUM(ca.Impressions) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) * 100
        ELSE 0
    END AS ClickThroughRate,

    CASE
        WHEN (SELECT SUM(ca.Clicks) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) > 0
        THEN CAST((SELECT SUM(ca.Conversions) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) AS DECIMAL(10,4)) /
             (SELECT SUM(ca.Clicks) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) * 100
        ELSE 0
    END AS ConversionRate,

    CASE
        WHEN (SELECT SUM(ca.Spend) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) > 0
        THEN CAST((SELECT SUM(ca.Conversions) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID) AS DECIMAL(10,4)) /
             (SELECT SUM(ca.Spend) FROM CampaignActivities ca WHERE ca.CampaignID = c.CampaignID)
        ELSE 0
    END AS CostPerConversion

FROM Campaigns c
WHERE c.CampaignStatus IN ('Active', 'Completed');
GO

-- Customer journey view
CREATE VIEW vw_CustomerJourney
AS
SELECT
    ce.CustomerID,
    c.FirstName + ' ' + c.LastName AS CustomerName,
    c.CustomerSegment,
    ce.EventDateTime,
    ce.EventType,
    ce.EventCategory,
    ce.Channel,
    ce.CampaignID,

    -- Attribution data
    at.FirstTouchAttribution,
    at.LastTouchAttribution,
    at.TouchpointValue,

    -- Event sequence
    ROW_NUMBER() OVER (PARTITION BY ce.CustomerID ORDER BY ce.EventDateTime) AS EventSequence

FROM CustomerEvents ce
INNER JOIN Customers c ON ce.CustomerID = c.CustomerID
LEFT JOIN AttributionTouchpoints at ON ce.CustomerID = at.CustomerID
    AND CAST(ce.EventDateTime AS DATE) = CAST(at.TouchpointDateTime AS DATE)
WHERE ce.EventDateTime >= DATEADD(DAY, -90, GETDATE()) -- Last 90 days
ORDER BY ce.CustomerID, ce.EventDateTime;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update customer last activity date
CREATE TRIGGER TR_CustomerEvents_UpdateLastActivity
ON CustomerEvents
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE c
    SET c.LastActivityDate = i.EventDateTime
    FROM Customers c
    INNER JOIN inserted i ON c.CustomerID = i.CustomerID
    WHERE i.EventDateTime > ISNULL(c.LastActivityDate, '1900-01-01');
END;
GO

-- Update campaign actual dates
CREATE TRIGGER TR_CampaignActivities_UpdateCampaignDates
ON CampaignActivities
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Update campaign actual start date
    UPDATE c
    SET c.ActualStartDate = (
        SELECT MIN(ca.ExecutedDateTime)
        FROM CampaignActivities ca
        WHERE ca.CampaignID = c.CampaignID AND ca.Status = 'Completed'
    )
    FROM Campaigns c
    WHERE c.CampaignID IN (
        SELECT DISTINCT CampaignID FROM inserted WHERE Status = 'Completed'
    );

    -- Update campaign actual end date
    UPDATE c
    SET c.ActualEndDate = (
        SELECT MAX(ca.ExecutedDateTime)
        FROM CampaignActivities ca
        WHERE ca.CampaignID = c.CampaignID AND ca.Status = 'Completed'
    )
    FROM Campaigns c
    WHERE c.CampaignID IN (
        SELECT DISTINCT CampaignID FROM inserted WHERE Status = 'Completed'
    );
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Process customer event procedure
CREATE PROCEDURE sp_ProcessCustomerEvent
    @CustomerID INT,
    @EventType NVARCHAR(100),
    @EventCategory NVARCHAR(50),
    @EventSource NVARCHAR(50),
    @EventProperties NVARCHAR(MAX) = NULL,
    @SessionID NVARCHAR(100) = NULL,
    @CampaignID NVARCHAR(100) = NULL,
    @Channel NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO CustomerEvents (
        CustomerID, EventType, EventCategory, EventSource,
        EventProperties, SessionID, CampaignID, Channel
    )
    VALUES (
        @CustomerID, @EventType, @EventCategory, @EventSource,
        @EventProperties, @SessionID, @CampaignID, @Channel
    );

    SELECT SCOPE_IDENTITY() AS EventID;
END;
GO

-- Create campaign procedure
CREATE PROCEDURE sp_CreateCampaign
    @CampaignName NVARCHAR(200),
    @CampaignType NVARCHAR(50),
    @CampaignObjective NVARCHAR(100),
    @BudgetAmount DECIMAL(12,2),
    @PlannedStartDate DATETIME2,
    @PlannedEndDate DATETIME2,
    @CreatedBy NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CampaignCode NVARCHAR(50);

    -- Generate campaign code
    SET @CampaignCode = 'CMP-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                       RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                       RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS NVARCHAR(4)), 4);

    INSERT INTO Campaigns (
        CampaignCode, CampaignName, CampaignType, CampaignObjective,
        BudgetAmount, PlannedStartDate, PlannedEndDate, CreatedBy
    )
    VALUES (
        @CampaignCode, @CampaignName, @CampaignType, @CampaignObjective,
        @BudgetAmount, @PlannedStartDate, @PlannedEndDate, @CreatedBy
    );

    SELECT SCOPE_IDENTITY() AS CampaignID, @CampaignCode AS CampaignCode;
END;
GO

-- Calculate attribution procedure
CREATE PROCEDURE sp_CalculateAttribution
    @ConversionEventID BIGINT,
    @AttributionModel NVARCHAR(50) = 'Linear'
AS
BEGIN
    SET NOCOUNT ON;

    -- This is a simplified attribution calculation
    -- In production, this would be much more complex

    DECLARE @CustomerID INT;
    DECLARE @ConversionDate DATETIME2;
    DECLARE @TouchpointCount INT;

    -- Get conversion details
    SELECT @CustomerID = CustomerID, @ConversionDate = EventDateTime
    FROM CustomerEvents
    WHERE EventID = @ConversionEventID;

    -- Count touchpoints in attribution window (30 days)
    SELECT @TouchpointCount = COUNT(*)
    FROM CustomerEvents
    WHERE CustomerID = @CustomerID
    AND EventDateTime >= DATEADD(DAY, -30, @ConversionDate)
    AND EventDateTime <= @ConversionDate;

    -- Simple linear attribution
    IF @AttributionModel = 'Linear' AND @TouchpointCount > 0
    BEGIN
        UPDATE CustomerEvents
        SET EventProperties = JSON_MODIFY(ISNULL(EventProperties, '{}'), '$.AttributionValue', 1.0 / @TouchpointCount)
        WHERE CustomerID = @CustomerID
        AND EventDateTime >= DATEADD(DAY, -30, @ConversionDate)
        AND EventDateTime <= @ConversionDate;
    END
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample customer
INSERT INTO Customers (CustomerNumber, FirstName, LastName, Email, CustomerSegment) VALUES
('CUST-000001', 'John', 'Smith', 'john.smith@email.com', 'HighValue');

-- Insert sample campaign
INSERT INTO Campaigns (CampaignCode, CampaignName, CampaignType, BudgetAmount, PlannedStartDate, PlannedEndDate) VALUES
('CMP-202412-0001', 'Holiday Email Campaign', 'Email', 5000.00, '2024-12-01', '2024-12-31');

-- Insert sample customer event
INSERT INTO CustomerEvents (CustomerID, EventType, EventCategory, EventSource, Channel, CampaignID) VALUES
(1, 'EmailOpen', 'Engagement', 'Email', 'Newsletter', 'CMP-202412-0001');

-- Insert sample metric
INSERT INTO MarketingMetrics (MetricCode, MetricName, MetricCategory, MetricType, UpdateFrequency) VALUES
('EMAIL_OPEN_RATE', 'Email Open Rate', 'Engagement', 'Rate', 'Daily');

PRINT 'Marketing database schema created successfully!';
GO