# Telecommunications Platform Database Design

## Overview

This comprehensive database schema supports modern telecommunications platforms including network management, subscriber services, billing systems, service provisioning, and regulatory compliance. The design handles complex network topologies, real-time service monitoring, multi-service offerings, and enterprise telecom operations.

## Key Features

### 📡 Network & Infrastructure Management
- **Network topology management** with equipment tracking and connectivity mapping
- **Service provisioning and activation** with automated workflow orchestration
- **Network performance monitoring** with real-time metrics and fault detection
- **Capacity planning and optimization** with predictive analytics and resource allocation

### 👥 Subscriber & Service Management
- **Subscriber lifecycle management** with onboarding, service changes, and deactivation
- **Multi-service offerings** with bundled packages and add-on services
- **Account and billing management** with complex rating plans and usage tracking
- **Customer service operations** with ticketing, troubleshooting, and SLA management

### 📊 Billing & Revenue Management
- **Complex rating and billing** with time-based, volume-based, and quality-based charging
- **Revenue assurance and fraud detection** with real-time monitoring and automated alerts
- **Financial reporting and analytics** with revenue optimization and profitability analysis
- **Regulatory compliance and reporting** with data retention and audit trails

## Database Schema Highlights

### Core Tables

#### Network Infrastructure Management
```sql
-- Network equipment and assets
CREATE TABLE NetworkEquipment (
    EquipmentID INT IDENTITY(1,1) PRIMARY KEY,
    EquipmentCode NVARCHAR(50) UNIQUE NOT NULL,
    EquipmentName NVARCHAR(100) NOT NULL,
    EquipmentType NVARCHAR(50) NOT NULL, -- Router, Switch, Server, Antenna, Cable, etc.

    -- Location and installation
    Location NVARCHAR(MAX), -- JSON formatted coordinates and address
    SiteID INT,
    RackPosition NVARCHAR(20),
    InstallationDate DATETIME2 DEFAULT GETDATE(),

    -- Technical specifications
    Manufacturer NVARCHAR(100),
    Model NVARCHAR(100),
    SerialNumber NVARCHAR(100),
    FirmwareVersion NVARCHAR(50),
    IPAddress NVARCHAR(45),
    MACAddress NVARCHAR(17),

    -- Operational status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Maintenance, Fault, Decommissioned
    OperationalState NVARCHAR(20) DEFAULT 'InService', -- InService, OutOfService, Testing
    LastMaintenanceDate DATETIME2,
    NextMaintenanceDate DATETIME2,

    -- Performance and capacity
    Capacity NVARCHAR(MAX), -- JSON: bandwidth, connections, etc.
    CurrentUtilization DECIMAL(5,2), -- Percentage
    ThresholdWarning DECIMAL(5,2) DEFAULT 80.00,
    ThresholdCritical DECIMAL(5,2) DEFAULT 90.00,

    -- Management
    ManagedBy NVARCHAR(100),
    VendorSupport NVARCHAR(MAX), -- JSON formatted support contacts

    -- Constraints
    CONSTRAINT CK_NetworkEquipment_Type CHECK (EquipmentType IN ('Router', 'Switch', 'Server', 'Firewall', 'LoadBalancer', 'Antenna', 'Cable', 'Splitter', 'Amplifier', 'Converter')),
    CONSTRAINT CK_NetworkEquipment_Status CHECK (Status IN ('Active', 'Maintenance', 'Fault', 'Decommissioned', 'Reserved')),
    CONSTRAINT CK_NetworkEquipment_State CHECK (OperationalState IN ('InService', 'OutOfService', 'Testing', 'Standby')),
    CONSTRAINT CK_NetworkEquipment_Utilization CHECK (CurrentUtilization BETWEEN 0 AND 100),

    -- Indexes
    INDEX IX_NetworkEquipment_Code (EquipmentCode),
    INDEX IX_NetworkEquipment_Type (EquipmentType),
    INDEX IX_NetworkEquipment_Status (Status),
    INDEX IX_NetworkEquipment_Site (SiteID),
    INDEX IX_NetworkEquipment_Utilization (CurrentUtilization)
);

-- Network topology and connections
CREATE TABLE NetworkConnections (
    ConnectionID INT IDENTITY(1,1) PRIMARY KEY,
    ConnectionCode NVARCHAR(50) UNIQUE NOT NULL,

    -- Connection endpoints
    SourceEquipmentID INT NOT NULL REFERENCES NetworkEquipment(EquipmentID),
    TargetEquipmentID INT NOT NULL REFERENCES NetworkEquipment(EquipmentID),
    ConnectionType NVARCHAR(50) NOT NULL, -- Fiber, Copper, Wireless, Microwave

    -- Technical specifications
    Bandwidth NVARCHAR(50), -- 1Gbps, 10Gbps, etc.
    Protocol NVARCHAR(50), -- Ethernet, SONET, ATM, IP
    Distance DECIMAL(10,2), -- Kilometers

    -- Operational status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Maintenance, Fault, Planned
    ActivationDate DATETIME2,
    DeactivationDate DATETIME2,

    -- Performance monitoring
    Latency DECIMAL(8,2), -- Milliseconds
    PacketLoss DECIMAL(5,4), -- Percentage
    Jitter DECIMAL(8,2), -- Milliseconds
    LastTestDate DATETIME2,

    -- Redundancy and backup
    IsPrimary BIT DEFAULT 1,
    BackupConnectionID INT REFERENCES NetworkConnections(ConnectionID),

    -- Constraints
    CONSTRAINT CK_NetworkConnections_Type CHECK (ConnectionType IN ('Fiber', 'Copper', 'Wireless', 'Microwave', 'Satellite', 'DSL', 'Cable')),
    CONSTRAINT CK_NetworkConnections_Status CHECK (Status IN ('Active', 'Maintenance', 'Fault', 'Planned', 'Decommissioned')),
    CONSTRAINT CK_NetworkConnections_PacketLoss CHECK (PacketLoss BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_NetworkConnections_Code (ConnectionCode),
    INDEX IX_NetworkConnections_Source (SourceEquipmentID),
    INDEX IX_NetworkConnections_Target (TargetEquipmentID),
    INDEX IX_NetworkConnections_Type (ConnectionType),
    INDEX IX_NetworkConnections_Status (Status)
);

-- Service areas and coverage
CREATE TABLE ServiceAreas (
    AreaID INT IDENTITY(1,1) PRIMARY KEY,
    AreaCode NVARCHAR(20) UNIQUE NOT NULL,
    AreaName NVARCHAR(100) NOT NULL,
    AreaType NVARCHAR(20) DEFAULT 'Geographic', -- Geographic, Demographic, Custom

    -- Geographic boundaries
    BoundaryCoordinates NVARCHAR(MAX), -- JSON polygon coordinates
    CenterLatitude DECIMAL(10,8),
    CenterLongitude DECIMAL(11,8),
    Radius DECIMAL(8,2), -- Kilometers

    -- Service coverage
    ServiceTypes NVARCHAR(MAX), -- JSON array: Internet, Voice, TV, Mobile
    CoverageLevel NVARCHAR(20) DEFAULT 'Full', -- Full, Partial, Planned

    -- Population and demographics
    Population INT,
    HouseholdCount INT,
    BusinessCount INT,

    -- Network capacity
    MaxBandwidth NVARCHAR(50),
    CurrentSubscribers INT DEFAULT 0,
    CapacityUtilization DECIMAL(5,2),

    -- Status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Planned, UnderConstruction, Maintenance

    -- Constraints
    CONSTRAINT CK_ServiceAreas_Type CHECK (AreaType IN ('Geographic', 'Demographic', 'Custom')),
    CONSTRAINT CK_ServiceAreas_Coverage CHECK (CoverageLevel IN ('Full', 'Partial', 'Planned', 'None')),
    CONSTRAINT CK_ServiceAreas_Status CHECK (Status IN ('Active', 'Planned', 'UnderConstruction', 'Maintenance', 'Decommissioned')),

    -- Indexes
    INDEX IX_ServiceAreas_Code (AreaCode),
    INDEX IX_ServiceAreas_Type (AreaType),
    INDEX IX_ServiceAreas_Status (Status),
    INDEX IX_ServiceAreas_Coverage (CoverageLevel)
);
```

#### Subscriber & Service Management
```sql
-- Subscriber accounts
CREATE TABLE Subscribers (
    SubscriberID INT IDENTITY(1,1) PRIMARY KEY,
    AccountNumber NVARCHAR(50) UNIQUE NOT NULL,

    -- Personal information
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    CompanyName NVARCHAR(200),
    ContactEmail NVARCHAR(255),
    ContactPhone NVARCHAR(20),

    -- Account details
    AccountType NVARCHAR(20) DEFAULT 'Individual', -- Individual, Business, Government
    AccountStatus NVARCHAR(20) DEFAULT 'Active', -- Active, Suspended, Terminated, Pending
    RegistrationDate DATETIME2 DEFAULT GETDATE(),

    -- Billing information
    BillingAddress NVARCHAR(MAX), -- JSON formatted
    PaymentMethod NVARCHAR(20) DEFAULT 'CreditCard', -- CreditCard, DebitCard, ACH, Check, Invoice
    AutoPayEnabled BIT DEFAULT 0,
    CreditLimit DECIMAL(10,2) DEFAULT 0,

    -- Service details
    ServiceAddress NVARCHAR(MAX), -- JSON formatted
    ServiceAreaID INT REFERENCES ServiceAreas(AreaID),
    PrimaryServiceType NVARCHAR(20), -- Internet, Voice, TV, Mobile, Bundle

    -- Account management
    AccountManager NVARCHAR(100),
    SalesChannel NVARCHAR(20), -- Direct, Agent, Partner, Online
    ContractStartDate DATETIME2,
    ContractEndDate DATETIME2,
    MinimumTermMonths INT DEFAULT 0,

    -- Security and access
    SecurityQuestion NVARCHAR(MAX), -- JSON formatted
    TwoFactorEnabled BIT DEFAULT 0,
    LastLoginDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_Subscribers_Type CHECK (AccountType IN ('Individual', 'Business', 'Government', 'NonProfit')),
    CONSTRAINT CK_Subscribers_Status CHECK (AccountStatus IN ('Active', 'Suspended', 'Terminated', 'Pending', 'Cancelled')),
    CONSTRAINT CK_Subscribers_PaymentMethod CHECK (PaymentMethod IN ('CreditCard', 'DebitCard', 'ACH', 'Check', 'Invoice', 'Cash')),
    CONSTRAINT CK_Subscribers_ServiceType CHECK (PrimaryServiceType IN ('Internet', 'Voice', 'TV', 'Mobile', 'Bundle')),

    -- Indexes
    INDEX IX_Subscribers_Number (AccountNumber),
    INDEX IX_Subscribers_Type (AccountType),
    INDEX IX_Subscribers_Status (AccountStatus),
    INDEX IX_Subscribers_Email (ContactEmail),
    INDEX IX_Subscribers_ServiceArea (ServiceAreaID),
    INDEX IX_Subscribers_LastLogin (LastLoginDate DESC)
);

-- Service subscriptions
CREATE TABLE ServiceSubscriptions (
    SubscriptionID INT IDENTITY(1,1) PRIMARY KEY,
    SubscriberID INT NOT NULL REFERENCES Subscribers(SubscriberID) ON DELETE CASCADE,
    ServiceCode NVARCHAR(50) UNIQUE NOT NULL,

    -- Service details
    ServiceType NVARCHAR(50) NOT NULL, -- Internet, Voice, TV, Mobile, Security
    ServiceName NVARCHAR(200) NOT NULL,
    ServiceDescription NVARCHAR(MAX),

    -- Subscription details
    PlanCode NVARCHAR(50),
    PlanName NVARCHAR(100),
    SubscriptionDate DATETIME2 DEFAULT GETDATE(),
    ActivationDate DATETIME2,
    TerminationDate DATETIME2,

    -- Status and lifecycle
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Suspended, Terminated, Pending
    SuspensionReason NVARCHAR(MAX),
    TerminationReason NVARCHAR(MAX),

    -- Billing
    RecurringCharge DECIMAL(8,2), -- Monthly charge
    OneTimeCharge DECIMAL(8,2), -- Activation/setup fee
    BillingCycle NVARCHAR(20) DEFAULT 'Monthly', -- Monthly, Quarterly, Annual

    -- Service parameters
    ServiceParameters NVARCHAR(MAX), -- JSON: speed, channels, minutes, etc.
    EquipmentProvided NVARCHAR(MAX), -- JSON: modem, router, phone, etc.

    -- Technical details
    IPAddress NVARCHAR(45),
    MACAddress NVARCHAR(17),
    PortNumber NVARCHAR(20),

    -- Constraints
    CONSTRAINT CK_ServiceSubscriptions_Type CHECK (ServiceType IN ('Internet', 'Voice', 'TV', 'Mobile', 'Security', 'Cloud', 'IoT')),
    CONSTRAINT CK_ServiceSubscriptions_Status CHECK (Status IN ('Active', 'Suspended', 'Terminated', 'Pending', 'Cancelled')),
    CONSTRAINT CK_ServiceSubscriptions_Cycle CHECK (BillingCycle IN ('Monthly', 'Quarterly', 'Annual', 'OneTime')),

    -- Indexes
    INDEX IX_ServiceSubscriptions_Code (ServiceCode),
    INDEX IX_ServiceSubscriptions_Subscriber (SubscriberID),
    INDEX IX_ServiceSubscriptions_Type (ServiceType),
    INDEX IX_ServiceSubscriptions_Status (Status),
    INDEX IX_ServiceSubscriptions_Plan (PlanCode)
);

-- Service usage tracking
CREATE TABLE ServiceUsage (
    UsageID BIGINT IDENTITY(1,1) PRIMARY KEY, -- Large table for high-volume usage data
    SubscriptionID INT NOT NULL REFERENCES ServiceSubscriptions(SubscriptionID),
    UsageDateTime DATETIME2 NOT NULL DEFAULT GETDATE(),

    -- Usage details
    ServiceType NVARCHAR(50) NOT NULL,
    UsageType NVARCHAR(50), -- Data, Voice, SMS, etc.
    Quantity DECIMAL(12,3) NOT NULL, -- GB, minutes, SMS count, etc.
    Unit NVARCHAR(20), -- GB, Minutes, SMS, etc.

    -- Cost details
    Rate DECIMAL(8,4), -- Cost per unit
    TotalCost DECIMAL(10,2),
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Technical details
    SourceIPAddress NVARCHAR(45),
    Destination NVARCHAR(200), -- For voice calls, websites, etc.
    Duration INT, -- Seconds for calls, sessions, etc.

    -- Quality metrics
    QualityScore DECIMAL(3,2), -- 0.00 to 5.00
    SignalStrength DECIMAL(5,2), -- -100 to 0 dBm for mobile
    BandwidthUsed DECIMAL(10,2), -- Mbps for internet

    -- Processing
    ProcessedDateTime DATETIME2,
    IsBilled BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_ServiceUsage_Type CHECK (ServiceType IN ('Internet', 'Voice', 'TV', 'Mobile', 'Security')),
    CONSTRAINT CK_ServiceUsage_Quality CHECK (QualityScore BETWEEN 0 AND 5),

    -- Indexes
    INDEX IX_ServiceUsage_Subscription (SubscriptionID),
    INDEX IX_ServiceUsage_DateTime (UsageDateTime),
    INDEX IX_ServiceUsage_Type (UsageType),
    INDEX IX_ServiceUsage_IsBilled (IsBilled),
    INDEX IX_ServiceUsage_ProcessedDateTime (ProcessedDateTime)
);
```

#### Billing & Revenue Management
```sql
-- Billing plans and rates
CREATE TABLE BillingPlans (
    PlanID INT IDENTITY(1,1) PRIMARY KEY,
    PlanCode NVARCHAR(50) UNIQUE NOT NULL,
    PlanName NVARCHAR(200) NOT NULL,
    ServiceType NVARCHAR(50) NOT NULL,

    -- Plan details
    PlanDescription NVARCHAR(MAX),
    PlanCategory NVARCHAR(50), -- Basic, Premium, Business, Enterprise

    -- Pricing structure
    BasePrice DECIMAL(8,2), -- Monthly base price
    SetupFee DECIMAL(8,2), -- One-time setup fee
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Usage limits and overage
    IncludedUsage NVARCHAR(MAX), -- JSON: data, minutes, etc.
    OverageRates NVARCHAR(MAX), -- JSON: rates for overages
    SpeedTiers NVARCHAR(MAX), -- JSON: speed options and pricing

    -- Billing rules
    BillingCycle NVARCHAR(20) DEFAULT 'Monthly',
    ProrateMethod NVARCHAR(20) DEFAULT 'Daily', -- Daily, Monthly, None
    EarlyTerminationFee DECIMAL(8,2),

    -- Availability and status
    IsActive BIT DEFAULT 1,
    AvailableFrom DATETIME2,
    AvailableUntil DATETIME2,
    TargetMarket NVARCHAR(50), -- Residential, Business, Government

    -- Constraints
    CONSTRAINT CK_BillingPlans_ServiceType CHECK (ServiceType IN ('Internet', 'Voice', 'TV', 'Mobile', 'Bundle', 'Security')),
    CONSTRAINT CK_BillingPlans_Category CHECK (PlanCategory IN ('Basic', 'Premium', 'Business', 'Enterprise', 'Custom')),
    CONSTRAINT CK_BillingPlans_Cycle CHECK (BillingCycle IN ('Monthly', 'Quarterly', 'Annual')),
    CONSTRAINT CK_BillingPlans_Prorate CHECK (ProrateMethod IN ('Daily', 'Monthly', 'None')),
    CONSTRAINT CK_BillingPlans_Target CHECK (TargetMarket IN ('Residential', 'Business', 'Government', 'All')),

    -- Indexes
    INDEX IX_BillingPlans_Code (PlanCode),
    INDEX IX_BillingPlans_ServiceType (ServiceType),
    INDEX IX_BillingPlans_Category (PlanCategory),
    INDEX IX_BillingPlans_IsActive (IsActive),
    INDEX IX_BillingPlans_TargetMarket (TargetMarket)
);

-- Billing cycles and invoices
CREATE TABLE Invoices (
    InvoiceID INT IDENTITY(1,1) PRIMARY KEY,
    InvoiceNumber NVARCHAR(50) UNIQUE NOT NULL,
    SubscriberID INT NOT NULL REFERENCES Subscribers(SubscriberID),

    -- Billing period
    BillingCycleStart DATETIME2 NOT NULL,
    BillingCycleEnd DATETIME2 NOT NULL,
    InvoiceDate DATETIME2 DEFAULT GETDATE(),
    DueDate DATETIME2 NOT NULL,

    -- Financial details
    Subtotal DECIMAL(10,2) NOT NULL,
    Taxes DECIMAL(10,2) DEFAULT 0,
    Fees DECIMAL(10,2) DEFAULT 0, -- Late fees, service fees, etc.
    Discounts DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(10,2) NOT NULL,

    -- Payment details
    PaymentStatus NVARCHAR(20) DEFAULT 'Unpaid', -- Unpaid, Paid, Overdue, Disputed
    PaymentDate DATETIME2,
    PaymentMethod NVARCHAR(20),
    PaymentReference NVARCHAR(100),

    -- Invoice details
    InvoiceType NVARCHAR(20) DEFAULT 'Regular', -- Regular, Adjustment, Final, Credit
    PreviousBalance DECIMAL(10,2) DEFAULT 0,
    Adjustments DECIMAL(10,2) DEFAULT 0,
    Credits DECIMAL(10,2) DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Invoices_PaymentStatus CHECK (PaymentStatus IN ('Unpaid', 'Paid', 'Partial', 'Overdue', 'Disputed', 'WrittenOff')),
    CONSTRAINT CK_Invoices_Type CHECK (InvoiceType IN ('Regular', 'Adjustment', 'Final', 'Credit', 'Debit')),

    -- Indexes
    INDEX IX_Invoices_Number (InvoiceNumber),
    INDEX IX_Invoices_Subscriber (SubscriberID),
    INDEX IX_Invoices_Status (PaymentStatus),
    INDEX IX_Invoices_DueDate (DueDate),
    INDEX IX_Invoices_InvoiceDate (InvoiceDate),
    INDEX IX_Invoices_PaymentDate (PaymentDate)
);

-- Invoice line items
CREATE TABLE InvoiceLineItems (
    LineItemID INT IDENTITY(1,1) PRIMARY KEY,
    InvoiceID INT NOT NULL REFERENCES Invoices(InvoiceID) ON DELETE CASCADE,
    SubscriptionID INT REFERENCES ServiceSubscriptions(SubscriptionID),

    -- Line item details
    LineItemType NVARCHAR(50) DEFAULT 'Service', -- Service, Usage, Fee, Tax, Discount
    Description NVARCHAR(200) NOT NULL,
    Quantity DECIMAL(10,3) DEFAULT 1,
    UnitPrice DECIMAL(8,2) NOT NULL,
    TotalAmount DECIMAL(10,2) NOT NULL,

    -- Service details
    ServiceType NVARCHAR(50),
    BillingPeriodStart DATETIME2,
    BillingPeriodEnd DATETIME2,

    -- Usage details (for usage-based charges)
    UsageStartDate DATETIME2,
    UsageEndDate DATETIME2,
    ActualUsage DECIMAL(12,3),

    -- Constraints
    CONSTRAINT CK_InvoiceLineItems_Type CHECK (LineItemType IN ('Service', 'Usage', 'Fee', 'Tax', 'Discount', 'Credit', 'Debit')),

    -- Indexes
    INDEX IX_InvoiceLineItems_Invoice (InvoiceID),
    INDEX IX_InvoiceLineItems_Subscription (SubscriptionID),
    INDEX IX_InvoiceLineItems_Type (LineItemType)
);
```

## Integration Points

### External Systems
- **Network Management Systems**: Integration with SNMP, NetFlow, and network monitoring platforms
- **Billing and CRM Systems**: Synchronization with enterprise billing platforms and customer management systems
- **Provisioning Systems**: Automated service activation and configuration management
- **Regulatory Systems**: Compliance reporting to FCC, state regulators, and data retention systems
- **Payment Processors**: Integration with payment gateways and financial institutions
- **IoT and Smart Devices**: Connection with smart meters, routers, and connected devices

### API Endpoints
- **Subscriber APIs**: Account management, service provisioning, billing inquiries
- **Network APIs**: Equipment monitoring, performance metrics, fault management
- **Billing APIs**: Invoice generation, payment processing, usage tracking
- **Service APIs**: Provisioning workflows, service changes, troubleshooting
- **Analytics APIs**: Usage patterns, network performance, revenue analytics
- **Regulatory APIs**: Compliance reporting, audit trails, data export

## Monitoring & Analytics

### Key Performance Indicators
- **Network Performance**: Uptime, latency, packet loss, bandwidth utilization
- **Service Quality**: Service activation time, fault resolution time, customer satisfaction
- **Financial Performance**: ARPU, churn rate, payment collection rates, profitability
- **Operational Efficiency**: Provisioning time, ticket resolution time, resource utilization
- **Regulatory Compliance**: Audit compliance, reporting accuracy, data retention

### Real-Time Dashboards
```sql
-- Telecommunications operations dashboard
CREATE VIEW TelecommunicationsOperationsDashboard AS
SELECT
    -- Network performance metrics (current status)
    (SELECT COUNT(*) FROM NetworkEquipment WHERE Status = 'Active') AS ActiveEquipment,
    (SELECT COUNT(*) FROM NetworkConnections WHERE Status = 'Active') AS ActiveConnections,
    (SELECT AVG(CurrentUtilization) FROM NetworkEquipment WHERE Status = 'Active') AS AvgEquipmentUtilization,
    (SELECT COUNT(*) FROM NetworkEquipment WHERE CurrentUtilization > ThresholdWarning) AS EquipmentOverWarning,

    -- Service quality metrics
    (SELECT COUNT(*) FROM ServiceSubscriptions WHERE Status = 'Active') AS ActiveSubscriptions,
    (SELECT COUNT(*) FROM Subscribers WHERE AccountStatus = 'Active') AS ActiveSubscribers,
    (SELECT AVG(QualityScore) FROM ServiceUsage WHERE UsageDateTime >= DATEADD(DAY, -1, GETDATE())) AS AvgServiceQuality,

    -- Billing and financial metrics
    (SELECT COUNT(*) FROM Invoices WHERE PaymentStatus = 'Unpaid' AND DueDate < GETDATE()) AS OverdueInvoices,
    (SELECT SUM(TotalAmount) FROM Invoices WHERE PaymentStatus = 'Unpaid' AND DueDate < GETDATE()) AS OverdueAmount,
    (SELECT COUNT(*) FROM Invoices WHERE InvoiceDate >= DATEADD(DAY, -30, GETDATE())) AS InvoicesLast30Days,
    (SELECT SUM(TotalAmount) FROM Invoices WHERE InvoiceDate >= DATEADD(DAY, -30, GETDATE()) AND PaymentStatus = 'Paid') AS RevenueLast30Days,

    -- Subscriber metrics
    (SELECT COUNT(*) FROM Subscribers WHERE RegistrationDate >= DATEADD(DAY, -30, GETDATE())) AS NewSubscribers30Days,
    (SELECT COUNT(*) FROM ServiceSubscriptions WHERE Status = 'Terminated' AND TerminationDate >= DATEADD(DAY, -30, GETDATE())) AS ChurnedServices30Days,
    (SELECT CAST((SELECT COUNT(*) FROM ServiceSubscriptions WHERE Status = 'Terminated' AND TerminationDate >= DATEADD(DAY, -30, GETDATE())) AS DECIMAL(10,4)) /
             NULLIF((SELECT COUNT(*) FROM ServiceSubscriptions WHERE Status = 'Active'), 0) * 100) AS MonthlyChurnRate,

    -- Usage and capacity metrics
    (SELECT SUM(Quantity) FROM ServiceUsage WHERE UsageDateTime >= DATEADD(DAY, -1, GETDATE()) AND UsageType = 'Data') AS DataUsageGBYesterday,
    (SELECT AVG(Quantity) FROM ServiceUsage WHERE UsageDateTime >= DATEADD(DAY, -1, GETDATE()) AND UsageType = 'Data') AS AvgDataUsagePerSubscriber,
    (SELECT MAX(Quantity) FROM ServiceUsage WHERE UsageDateTime >= DATEADD(DAY, -1, GETDATE()) AND UsageType = 'Data') AS PeakDataUsage,

    -- Service area coverage
    (SELECT COUNT(*) FROM ServiceAreas WHERE Status = 'Active') AS ActiveServiceAreas,
    (SELECT SUM(Population) FROM ServiceAreas WHERE Status = 'Active') AS TotalCoveredPopulation,
    (SELECT AVG(CapacityUtilization) FROM ServiceAreas WHERE Status = 'Active') AS AvgAreaUtilization,

    -- Operational efficiency
    (SELECT COUNT(*) FROM ServiceSubscriptions WHERE Status = 'Pending') AS PendingActivations,
    (SELECT AVG(DATEDIFF(DAY, SubscriptionDate, ActivationDate)) FROM ServiceSubscriptions WHERE Status = 'Active' AND ActivationDate IS NOT NULL) AS AvgActivationTime,
    (SELECT COUNT(*) FROM NetworkEquipment WHERE Status = 'Fault') AS FaultyEquipment

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This telecommunications database schema provides a comprehensive foundation for modern telecom platforms, supporting network operations, subscriber management, complex billing systems, and enterprise telecom services while maintaining regulatory compliance and operational efficiency.
