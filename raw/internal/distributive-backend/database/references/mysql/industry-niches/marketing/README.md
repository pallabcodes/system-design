# Marketing & Analytics Platform Database Design

## Overview

This comprehensive database schema supports modern marketing and analytics platforms including customer segmentation, campaign management, performance tracking, attribution modeling, and enterprise marketing analytics. The design handles complex marketing workflows, multi-channel attribution, predictive modeling, and marketing technology stack integration.

## Key Features

### 📊 Customer Analytics & Segmentation
- **Advanced customer profiling** with behavioral data, preferences, and lifecycle tracking
- **Dynamic segmentation** with real-time audience creation and automated targeting
- **Customer journey mapping** with touchpoint tracking and conversion funnel analysis
- **Predictive analytics** with churn prediction, lifetime value modeling, and recommendation engines

### 🎯 Campaign Management & Execution
- **Multi-channel campaign orchestration** with cross-platform coordination and automation
- **A/B testing and experimentation** with statistical significance testing and optimization
- **Personalization engines** with dynamic content delivery and real-time customization
- **Budget optimization** with automated bid management and ROI maximization

### 📈 Performance Measurement & Attribution
- **Multi-touch attribution modeling** with algorithmic attribution and incrementality testing
- **Real-time analytics dashboards** with KPI tracking and alerting systems
- **Marketing mix modeling** with econometric analysis and budget allocation optimization
- **Privacy and compliance management** with GDPR, CCPA, and data governance frameworks

## Database Schema Highlights

### Core Tables

#### Customer Data Platform
```sql
-- Customer profiles and unified identity
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

-- Customer events and behavioral data
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

-- Customer segments and audiences
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
```

#### Marketing Campaigns & Activities
```sql
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

-- Campaign activities and executions
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

-- A/B testing and experiments
CREATE TABLE Experiments (
    ExperimentID INT IDENTITY(1,1) PRIMARY KEY,
    ExperimentCode NVARCHAR(50) UNIQUE NOT NULL,
    ExperimentName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Experiment details
    ExperimentType NVARCHAR(50), -- A/B Test, Multivariate, Bandit
    Hypothesis NVARCHAR(MAX),
    PrimaryMetric NVARCHAR(100), -- ClickRate, ConversionRate, Revenue, etc.

    -- Test configuration
    ControlVariant NVARCHAR(50) DEFAULT 'A',
    TestVariants NVARCHAR(MAX), -- JSON: variant definitions
    SampleSize INT,
    ConfidenceLevel DECIMAL(5,4) DEFAULT 0.95, -- 95% confidence

    -- Timing
    StartDate DATETIME2,
    EndDate DATETIME2,
    DurationDays INT,

    -- Status and results
    Status NVARCHAR(20) DEFAULT 'Draft', -- Draft, Running, Completed, Stopped
    Winner NVARCHAR(50), -- Variant code of the winner
    StatisticalSignificance DECIMAL(5,4), -- p-value
    EffectSize DECIMAL(8,4), -- Effect size (Cohen's d, etc.)

    -- Associated campaign
    CampaignID INT REFERENCES Campaigns(CampaignID),

    -- Constraints
    CONSTRAINT CK_Experiments_Type CHECK (ExperimentType IN ('ABTest', 'Multivariate', 'Bandit', 'Sequential')),
    CONSTRAINT CK_Experiments_Status CHECK (Status IN ('Draft', 'Running', 'Completed', 'Stopped', 'Failed')),
    CONSTRAINT CK_Experiments_Confidence CHECK (ConfidenceLevel BETWEEN 0.8 AND 0.99),

    -- Indexes
    INDEX IX_Experiments_Code (ExperimentCode),
    INDEX IX_Experiments_Type (ExperimentType),
    INDEX IX_Experiments_Status (Status),
    INDEX IX_Experiments_Campaign (CampaignID),
    INDEX IX_Experiments_StartDate (StartDate),
    INDEX IX_Experiments_EndDate (EndDate)
);
```

#### Attribution & Analytics
```sql
-- Attribution models and touchpoints
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

-- Marketing KPIs and metrics
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

-- Metric values and time series
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
```

## Integration Points

### External Systems
- **Marketing Technology Stack**: CRM systems, email platforms, ad servers, analytics tools
- **Data Warehouses**: Integration with enterprise data warehouses and BI platforms
- **Customer Data Platforms**: Real-time synchronization with CDP systems
- **Advertising Platforms**: Google Ads, Facebook Ads, programmatic buying platforms
- **Content Management**: CMS integration for personalized content delivery
- **E-commerce Platforms**: Transaction data and purchase behavior integration

### API Endpoints
- **Customer APIs**: Profile management, segmentation, preference updates
- **Campaign APIs**: Campaign creation, execution, performance monitoring
- **Analytics APIs**: Real-time metrics, predictive modeling, insights generation
- **Attribution APIs**: Touchpoint tracking, attribution calculation, reporting
- **Personalization APIs**: Content recommendations, dynamic messaging, targeting
- **Experimentation APIs**: A/B test setup, results analysis, automated optimization

## Monitoring & Analytics

### Key Performance Indicators
- **Customer Acquisition**: Cost per acquisition, customer lifetime value, conversion rates
- **Campaign Performance**: Click-through rates, conversion rates, return on ad spend
- **Customer Engagement**: Open rates, click rates, time spent, bounce rates
- **Attribution Accuracy**: Model accuracy, incrementality lift, cross-channel impact
- **Predictive Performance**: Model accuracy, recommendation effectiveness, churn prevention

### Real-Time Dashboards
```sql
-- Marketing operations dashboard
CREATE VIEW MarketingOperationsDashboard AS
SELECT
    -- Campaign performance metrics (current active campaigns)
    (SELECT COUNT(*) FROM Campaigns WHERE CampaignStatus = 'Active') AS ActiveCampaigns,
    (SELECT SUM(BudgetAmount) FROM Campaigns WHERE CampaignStatus = 'Active') AS TotalActiveBudget,
    (SELECT AVG(ActualROI) FROM Campaigns WHERE CampaignStatus = 'Completed' AND ActualROI IS NOT NULL) AS AvgCampaignROI,

    -- Customer metrics (last 30 days)
    (SELECT COUNT(*) FROM Customers WHERE AcquisitionDate >= DATEADD(DAY, -30, GETDATE())) AS NewCustomers30Days,
    (SELECT COUNT(*) FROM CustomerEvents WHERE EventDateTime >= DATEADD(DAY, -30, GETDATE()) AND EventType = 'Purchase') AS Purchases30Days,
    (SELECT AVG(CAST(EventProperties AS DECIMAL(10,2))) FROM CustomerEvents WHERE EventDateTime >= DATEADD(DAY, -30, GETDATE()) AND EventType = 'Purchase') AS AvgOrderValue30Days,

    -- Channel performance
    (SELECT SUM(Impressions) FROM CampaignActivities WHERE ExecutedDateTime >= DATEADD(DAY, -30, GETDATE())) AS TotalImpressions30Days,
    (SELECT SUM(Clicks) FROM CampaignActivities WHERE ExecutedDateTime >= DATEADD(DAY, -30, GETDATE())) AS TotalClicks30Days,
    (SELECT CAST(SUM(Clicks) AS DECIMAL(10,4)) / NULLIF(SUM(Impressions), 0) * 100 FROM CampaignActivities WHERE ExecutedDateTime >= DATEADD(DAY, -30, GETDATE())) AS AvgClickThroughRate,

    -- Attribution insights
    (SELECT COUNT(*) FROM AttributionTouchpoints WHERE TouchpointDateTime >= DATEADD(DAY, -30, GETDATE())) AS AttributionTouchpoints30Days,
    (SELECT SUM(TouchpointValue) FROM AttributionTouchpoints WHERE TouchpointDateTime >= DATEADD(DAY, -30, GETDATE())) AS AttributedRevenue30Days,

    -- Experiment status
    (SELECT COUNT(*) FROM Experiments WHERE Status = 'Running') AS RunningExperiments,
    (SELECT COUNT(*) FROM Experiments WHERE Status = 'Completed' AND StatisticalSignificance < 0.05) AS SignificantResults,

    -- Segment health
    (SELECT COUNT(*) FROM CustomerSegments WHERE IsActive = 1) AS ActiveSegments,
    (SELECT AVG(ActualSize) FROM CustomerSegments WHERE IsActive = 1 AND LastRefreshDate >= DATEADD(DAY, -7, GETDATE())) AS AvgSegmentSize,

    -- Data quality metrics
    (SELECT COUNT(*) FROM CustomerEvents WHERE EventDateTime >= DATEADD(DAY, -1, GETDATE())) AS EventsLast24Hours,
    (SELECT COUNT(*) FROM MetricValues WHERE DateRecorded >= DATEADD(DAY, -1, GETDATE()) AND DataQuality = 'Good') AS GoodQualityMetrics,

    -- Predictive performance
    (SELECT AVG(StatisticalSignificance) FROM Experiments WHERE Status = 'Completed' AND StatisticalSignificance IS NOT NULL) AS AvgExperimentSignificance,
    (SELECT COUNT(*) FROM CustomerSegments WHERE SegmentType = 'Predictive' AND IsActive = 1) AS PredictiveSegments

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This marketing database schema provides a comprehensive foundation for modern marketing and analytics platforms, supporting customer insights, campaign orchestration, attribution modeling, and enterprise marketing operations while maintaining data privacy and regulatory compliance.