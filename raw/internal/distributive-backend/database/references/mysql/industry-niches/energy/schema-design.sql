-- Energy & Utilities Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE EnergyDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE EnergyDB;
GO

-- Configure database for energy performance
ALTER DATABASE EnergyDB
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
-- POWER GENERATION & INFRASTRUCTURE
-- =============================================

-- Power generation facilities
CREATE TABLE PowerPlants (
    PlantID INT IDENTITY(1,1) PRIMARY KEY,
    PlantCode NVARCHAR(20) UNIQUE NOT NULL,
    PlantName NVARCHAR(200) NOT NULL,
    PlantType NVARCHAR(50) NOT NULL, -- Coal, Gas, Nuclear, Hydro, Solar, Wind, Geothermal

    -- Location and capacity
    Location NVARCHAR(MAX), -- JSON formatted coordinates and address
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),
    InstalledCapacity DECIMAL(12,3), -- MW
    OperationalCapacity DECIMAL(12,3), -- MW
    Efficiency DECIMAL(5,4), -- 0.0000 to 1.0000

    -- Operational details
    CommissionDate DATE,
    ExpectedLifespan INT, -- Years
    CurrentStatus NVARCHAR(20) DEFAULT 'Operational', -- Operational, Maintenance, Decommissioned, Standby

    -- Technical specifications
    FuelType NVARCHAR(50),
    CoolingSystem NVARCHAR(50),
    EmissionControls NVARCHAR(MAX), -- JSON array

    -- Regulatory and compliance
    RegulatoryApprovals NVARCHAR(MAX), -- JSON formatted approvals
    EnvironmentalPermits NVARCHAR(MAX), -- JSON formatted permits

    -- Management
    Operator NVARCHAR(100),
    Owner NVARCHAR(100),
    MaintenanceContractor NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_PowerPlants_Type CHECK (PlantType IN ('Coal', 'Gas', 'Nuclear', 'Hydro', 'Solar', 'Wind', 'Geothermal', 'Biomass', 'Tidal')),
    CONSTRAINT CK_PowerPlants_Status CHECK (CurrentStatus IN ('Operational', 'Maintenance', 'Decommissioned', 'Standby', 'UnderConstruction')),
    CONSTRAINT CK_PowerPlants_Efficiency CHECK (Efficiency BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_PowerPlants_Code (PlantCode),
    INDEX IX_PowerPlants_Type (PlantType),
    INDEX IX_PowerPlants_Status (CurrentStatus),
    INDEX IX_PowerPlants_Location (Latitude, Longitude)
);

-- Grid substations
CREATE TABLE Substations (
    SubstationID INT IDENTITY(1,1) PRIMARY KEY,
    SubstationCode NVARCHAR(20) UNIQUE NOT NULL,
    SubstationName NVARCHAR(200) NOT NULL,
    SubstationType NVARCHAR(50) DEFAULT 'Distribution', -- Transmission, Distribution, Switching

    -- Location and specifications
    Location NVARCHAR(MAX), -- JSON formatted
    VoltageLevel NVARCHAR(20), -- 69kV, 138kV, 345kV, etc.
    Capacity DECIMAL(10,2), -- MVA
    AreaServed NVARCHAR(200),

    -- Operational status
    Status NVARCHAR(20) DEFAULT 'Operational', -- Operational, Maintenance, Fault, Decommissioned
    CommissionDate DATE,
    LastMaintenanceDate DATETIME2,
    NextMaintenanceDate DATETIME2,

    -- Equipment and capabilities
    Transformers INT DEFAULT 0,
    CircuitBreakers INT DEFAULT 0,
    Switches INT DEFAULT 0,
    ProtectionSystems NVARCHAR(MAX), -- JSON array

    -- Constraints
    CONSTRAINT CK_Substations_Type CHECK (SubstationType IN ('Transmission', 'Distribution', 'Switching', 'Converter')),
    CONSTRAINT CK_Substations_Status CHECK (Status IN ('Operational', 'Maintenance', 'Fault', 'Decommissioned')),

    -- Indexes
    INDEX IX_Substations_Code (SubstationCode),
    INDEX IX_Substations_Type (SubstationType),
    INDEX IX_Substations_Status (Status),
    INDEX IX_Substations_Voltage (VoltageLevel)
);

-- Power transmission lines
CREATE TABLE PowerLines (
    LineID INT IDENTITY(1,1) PRIMARY KEY,
    LineCode NVARCHAR(20) UNIQUE NOT NULL,
    LineName NVARCHAR(200) NOT NULL,
    LineType NVARCHAR(20) DEFAULT 'Overhead', -- Overhead, Underground, Submarine

    -- Technical specifications
    Voltage NVARCHAR(20),
    Length DECIMAL(10,2), -- Kilometers
    ConductorType NVARCHAR(100),
    Insulation NVARCHAR(50),

    -- Connectivity
    FromSubstationID INT REFERENCES Substations(SubstationID),
    ToSubstationID INT REFERENCES Substations(SubstationID),
    Route NVARCHAR(MAX), -- JSON formatted coordinates

    -- Operational data
    Status NVARCHAR(20) DEFAULT 'Operational', -- Operational, Maintenance, Fault, Decommissioned
    Capacity DECIMAL(10,2), -- MW
    CurrentLoad DECIMAL(10,2), -- MW
    Losses DECIMAL(5,4), -- Percentage

    -- Maintenance and history
    InstallationDate DATE,
    LastInspection DATETIME2,
    NextInspection DATETIME2,

    -- Constraints
    CONSTRAINT CK_PowerLines_Type CHECK (LineType IN ('Overhead', 'Underground', 'Submarine')),
    CONSTRAINT CK_PowerLines_Status CHECK (Status IN ('Operational', 'Maintenance', 'Fault', 'Decommissioned')),
    CONSTRAINT CK_PowerLines_Losses CHECK (Losses BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_PowerLines_Code (LineCode),
    INDEX IX_PowerLines_Type (LineType),
    INDEX IX_PowerLines_Status (Status),
    INDEX IX_PowerLines_FromSubstation (FromSubstationID),
    INDEX IX_PowerLines_ToSubstation (ToSubstationID)
);

-- =============================================
-- SMART METERING SYSTEM
-- =============================================

-- Smart meters
CREATE TABLE SmartMeters (
    MeterID INT IDENTITY(1,1) PRIMARY KEY,
    MeterNumber NVARCHAR(50) UNIQUE NOT NULL,
    MeterType NVARCHAR(20) DEFAULT 'Electricity', -- Electricity, Gas, Water

    -- Installation details
    CustomerID INT NOT NULL,
    ServiceAddress NVARCHAR(MAX), -- JSON formatted
    InstallationDate DATETIME2 DEFAULT GETDATE(),
    ActivationDate DATETIME2,

    -- Technical specifications
    Manufacturer NVARCHAR(100),
    Model NVARCHAR(50),
    SerialNumber NVARCHAR(100),
    VoltageRating NVARCHAR(20),
    CurrentRating NVARCHAR(20),

    -- Communication and connectivity
    CommunicationType NVARCHAR(20) DEFAULT 'Cellular', -- Cellular, WiFi, Zigbee, PLC
    IPAddress NVARCHAR(45),
    MACAddress NVARCHAR(17),
    SignalStrength DECIMAL(5,2), -- -100 to 0 dBm

    -- Operational status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, Fault, Maintenance, Tampered
    LastReading DATETIME2,
    LastCommunication DATETIME2,
    BatteryLevel DECIMAL(5,2), -- 0.00 to 100.00

    -- Configuration
    ReadingInterval INT DEFAULT 15, -- Minutes
    TariffID INT,
    TimeZone NVARCHAR(50) DEFAULT 'UTC',

    -- Constraints
    CONSTRAINT CK_SmartMeters_Type CHECK (MeterType IN ('Electricity', 'Gas', 'Water', 'Heat')),
    CONSTRAINT CK_SmartMeters_CommType CHECK (CommunicationType IN ('Cellular', 'WiFi', 'Zigbee', 'PLC', 'Ethernet', 'Satellite')),
    CONSTRAINT CK_SmartMeters_Status CHECK (Status IN ('Active', 'Inactive', 'Fault', 'Maintenance', 'Tampered', 'Disconnected')),
    CONSTRAINT CK_SmartMeters_Battery CHECK (BatteryLevel BETWEEN 0 AND 100),

    -- Indexes
    INDEX IX_SmartMeters_Number (MeterNumber),
    INDEX IX_SmartMeters_Type (MeterType),
    INDEX IX_SmartMeters_Customer (CustomerID),
    INDEX IX_SmartMeters_Status (Status),
    INDEX IX_SmartMeters_LastReading (LastReading),
    INDEX IX_SmartMeters_LastCommunication (LastCommunication)
);

-- Meter readings (partitioned for performance)
CREATE TABLE MeterReadings (
    ReadingID BIGINT IDENTITY(1,1) PRIMARY KEY, -- Large table, use BIGINT
    MeterID INT NOT NULL REFERENCES SmartMeters(MeterID),
    ReadingDateTime DATETIME2 NOT NULL,

    -- Consumption data
    Consumption DECIMAL(12,3) NOT NULL, -- kWh, cubic meters, etc.
    ReadingType NVARCHAR(20) DEFAULT 'Actual', -- Actual, Estimated, Manual
    Quality NVARCHAR(10) DEFAULT 'Good', -- Good, Estimated, Manual

    -- Technical data
    Voltage DECIMAL(8,2), -- Volts (for electricity)
    Current DECIMAL(8,2), -- Amps (for electricity)
    PowerFactor DECIMAL(5,4), -- 0.0000 to 1.0000 (for electricity)

    -- Environmental data
    Temperature DECIMAL(6,2),
    Humidity DECIMAL(5,2),

    -- Validation and processing
    IsValidated BIT DEFAULT 0,
    ValidationMethod NVARCHAR(50),
    ProcessedDateTime DATETIME2,

    -- Constraints
    CONSTRAINT CK_MeterReadings_Type CHECK (ReadingType IN ('Actual', 'Estimated', 'Manual')),
    CONSTRAINT CK_MeterReadings_Quality CHECK (Quality IN ('Good', 'Estimated', 'Manual', 'Suspect', 'Bad')),
    CONSTRAINT CK_MeterReadings_PowerFactor CHECK (PowerFactor BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_MeterReadings_Meter (MeterID),
    INDEX IX_MeterReadings_DateTime (ReadingDateTime),
    INDEX IX_MeterReadings_Type (ReadingType),
    INDEX IX_MeterReadings_IsValidated (IsValidated),
    INDEX IX_MeterReadings_ProcessedDateTime (ProcessedDateTime)
);

-- =============================================
-- BILLING & CUSTOMER MANAGEMENT
-- =============================================

-- Tariffs and pricing
CREATE TABLE Tariffs (
    TariffID INT IDENTITY(1,1) PRIMARY KEY,
    TariffCode NVARCHAR(20) UNIQUE NOT NULL,
    TariffName NVARCHAR(200) NOT NULL,
    UtilityType NVARCHAR(20) DEFAULT 'Electricity', -- Electricity, Gas, Water

    -- Tariff structure
    RateType NVARCHAR(20) DEFAULT 'Fixed', -- Fixed, TimeOfUse, Tiered, Demand
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Base rates
    BaseRate DECIMAL(8,4), -- Per unit (kWh, cubic meter, etc.)
    ServiceCharge DECIMAL(8,2), -- Monthly service fee
    DemandCharge DECIMAL(8,4), -- Per kW of demand (electricity)

    -- Time-of-use rates (JSON)
    TimeOfUseRates NVARCHAR(MAX), -- Peak, OffPeak, Shoulder rates

    -- Tiered rates (JSON)
    TieredRates NVARCHAR(MAX), -- Tier thresholds and rates

    -- Validity period
    EffectiveDate DATE NOT NULL,
    EndDate DATE,

    -- Status
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_Tariffs_Type CHECK (UtilityType IN ('Electricity', 'Gas', 'Water', 'Heat')),
    CONSTRAINT CK_Tariffs_RateType CHECK (RateType IN ('Fixed', 'TimeOfUse', 'Tiered', 'Demand', 'Seasonal')),

    -- Indexes
    INDEX IX_Tariffs_Code (TariffCode),
    INDEX IX_Tariffs_Type (UtilityType),
    INDEX IX_Tariffs_IsActive (IsActive),
    INDEX IX_Tariffs_EffectiveDate (EffectiveDate)
);

-- Customer accounts
CREATE TABLE CustomerAccounts (
    AccountID INT IDENTITY(1,1) PRIMARY KEY,
    AccountNumber NVARCHAR(50) UNIQUE NOT NULL,

    -- Customer information
    CustomerName NVARCHAR(200) NOT NULL,
    ContactPerson NVARCHAR(100),
    BillingAddress NVARCHAR(MAX), -- JSON formatted
    ServiceAddress NVARCHAR(MAX), -- JSON formatted

    -- Contact details
    Phone NVARCHAR(20),
    Email NVARCHAR(255),
    EmergencyContact NVARCHAR(MAX), -- JSON formatted

    -- Account details
    AccountType NVARCHAR(20) DEFAULT 'Residential', -- Residential, Commercial, Industrial
    ServiceType NVARCHAR(50), -- Electricity, Gas, Water, Combined
    AccountStatus NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, Suspended, Closed

    -- Billing configuration
    BillingCycle NVARCHAR(20) DEFAULT 'Monthly', -- Monthly, Bimonthly, Quarterly
    PaymentTerms NVARCHAR(20) DEFAULT 'Net30', -- Net15, Net30, Net45
    AutoPay BIT DEFAULT 0,

    -- Credit and history
    CreditLimit DECIMAL(10,2) DEFAULT 1000.00,
    CurrentBalance DECIMAL(10,2) DEFAULT 0,
    LastPaymentDate DATETIME2,
    AccountOpenDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_CustomerAccounts_Type CHECK (AccountType IN ('Residential', 'Commercial', 'Industrial', 'Government')),
    CONSTRAINT CK_CustomerAccounts_Status CHECK (AccountStatus IN ('Active', 'Inactive', 'Suspended', 'Closed', 'Pending')),
    CONSTRAINT CK_CustomerAccounts_Cycle CHECK (BillingCycle IN ('Monthly', 'Bimonthly', 'Quarterly', 'Annual')),
    CONSTRAINT CK_CustomerAccounts_Terms CHECK (PaymentTerms IN ('Net15', 'Net30', 'Net45', 'Net60')),

    -- Indexes
    INDEX IX_CustomerAccounts_Number (AccountNumber),
    INDEX IX_CustomerAccounts_Type (AccountType),
    INDEX IX_CustomerAccounts_Status (AccountStatus),
    INDEX IX_CustomerAccounts_LastPayment (LastPaymentDate)
);

-- Invoices and billing
CREATE TABLE Invoices (
    InvoiceID INT IDENTITY(1,1) PRIMARY KEY,
    InvoiceNumber NVARCHAR(50) UNIQUE NOT NULL,
    AccountID INT NOT NULL REFERENCES CustomerAccounts(AccountID),

    -- Billing period
    BillingStartDate DATE NOT NULL,
    BillingEndDate DATE NOT NULL,
    InvoiceDate DATETIME2 DEFAULT GETDATE(),
    DueDate DATE NOT NULL,

    -- Amounts
    PreviousBalance DECIMAL(10,2) DEFAULT 0,
    CurrentCharges DECIMAL(10,2) NOT NULL,
    Taxes DECIMAL(10,2) DEFAULT 0,
    Adjustments DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(10,2) NOT NULL,

    -- Consumption details
    TotalConsumption DECIMAL(12,3),
    PeakDemand DECIMAL(10,2), -- kW for electricity
    BillingDays INT,

    -- Status and payment
    Status NVARCHAR(20) DEFAULT 'Unpaid', -- Unpaid, Paid, Overdue, Disputed, Cancelled
    PaymentDate DATETIME2,
    PaymentMethod NVARCHAR(20),
    PaymentReference NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_Invoices_Status CHECK (Status IN ('Unpaid', 'Paid', 'Overdue', 'Disputed', 'Cancelled', 'WrittenOff')),

    -- Indexes
    INDEX IX_Invoices_Number (InvoiceNumber),
    INDEX IX_Invoices_Account (AccountID),
    INDEX IX_Invoices_Status (Status),
    INDEX IX_Invoices_DueDate (DueDate),
    INDEX IX_Invoices_InvoiceDate (InvoiceDate),
    INDEX IX_Invoices_PaymentDate (PaymentDate)
);

-- Payments
CREATE TABLE Payments (
    PaymentID INT IDENTITY(1,1) PRIMARY KEY,
    PaymentReference NVARCHAR(50) UNIQUE NOT NULL,
    AccountID INT NOT NULL REFERENCES CustomerAccounts(AccountID),

    -- Payment details
    PaymentDate DATETIME2 DEFAULT GETDATE(),
    Amount DECIMAL(10,2) NOT NULL,
    PaymentMethod NVARCHAR(20) DEFAULT 'Check', -- Check, CreditCard, DebitCard, ACH, Cash, Online

    -- Processing information
    Processor NVARCHAR(50), -- Bank, Stripe, PayPal, etc.
    TransactionID NVARCHAR(100),
    AuthorizationCode NVARCHAR(20),
    ProcessingFee DECIMAL(6,2),

    -- Applied to invoices
    AppliedToInvoices NVARCHAR(MAX), -- JSON array of invoice applications

    -- Status
    Status NVARCHAR(20) DEFAULT 'Processed', -- Pending, Processed, Failed, Refunded, Chargeback

    -- Constraints
    CONSTRAINT CK_Payments_Method CHECK (PaymentMethod IN ('Check', 'CreditCard', 'DebitCard', 'ACH', 'Cash', 'Online', 'WireTransfer')),
    CONSTRAINT CK_Payments_Status CHECK (Status IN ('Pending', 'Processed', 'Failed', 'Refunded', 'Chargeback', 'Disputed')),

    -- Indexes
    INDEX IX_Payments_Reference (PaymentReference),
    INDEX IX_Payments_Account (AccountID),
    INDEX IX_Payments_Method (PaymentMethod),
    INDEX IX_Payments_Status (Status),
    INDEX IX_Payments_Date (PaymentDate)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Energy consumption summary
CREATE VIEW vw_EnergyConsumption
AS
SELECT
    m.MeterID,
    m.MeterNumber,
    m.MeterType,
    ca.AccountNumber,
    ca.CustomerName,

    -- Consumption by month
    YEAR(mr.ReadingDateTime) AS Year,
    MONTH(mr.ReadingDateTime) AS Month,
    SUM(mr.Consumption) AS TotalConsumption,
    AVG(mr.Consumption) AS AvgDailyConsumption,
    MAX(mr.Consumption) AS PeakConsumption,
    MIN(mr.Consumption) AS MinConsumption,

    -- Billing days
    COUNT(*) AS ReadingCount,
    DATEDIFF(DAY, MIN(mr.ReadingDateTime), MAX(mr.ReadingDateTime)) AS DaysInPeriod

FROM SmartMeters m
INNER JOIN MeterReadings mr ON m.MeterID = mr.MeterID
LEFT JOIN CustomerAccounts ca ON m.CustomerID = ca.AccountID
WHERE mr.IsValidated = 1
GROUP BY m.MeterID, m.MeterNumber, m.MeterType, ca.AccountNumber, ca.CustomerName,
         YEAR(mr.ReadingDateTime), MONTH(mr.ReadingDateTime);
GO

-- Billing summary view
CREATE VIEW vw_BillingSummary
AS
SELECT
    ca.AccountID,
    ca.AccountNumber,
    ca.CustomerName,
    ca.AccountType,

    -- Current billing period
    (SELECT MAX(InvoiceDate) FROM Invoices i WHERE i.AccountID = ca.AccountID) AS LastInvoiceDate,
    (SELECT SUM(TotalAmount) FROM Invoices i WHERE i.AccountID = ca.AccountID AND i.Status = 'Unpaid') AS OutstandingBalance,
    (SELECT COUNT(*) FROM Invoices i WHERE i.AccountID = ca.AccountID AND i.Status = 'Unpaid') AS UnpaidInvoices,

    -- Payment history
    (SELECT MAX(PaymentDate) FROM Payments p WHERE p.AccountID = ca.AccountID) AS LastPaymentDate,
    (SELECT SUM(Amount) FROM Payments p WHERE p.AccountID = ca.AccountID AND p.Status = 'Processed') AS TotalPaid,

    -- Consumption summary
    (SELECT SUM(TotalConsumption) FROM Invoices i WHERE i.AccountID = ca.AccountID AND YEAR(i.BillingEndDate) = YEAR(GETDATE())) AS AnnualConsumption

FROM CustomerAccounts ca
WHERE ca.AccountStatus = 'Active';
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update customer balance on invoice creation
CREATE TRIGGER TR_Invoices_UpdateBalance
ON Invoices
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE ca
    SET ca.CurrentBalance = ca.CurrentBalance + i.TotalAmount
    FROM CustomerAccounts ca
    INNER JOIN inserted i ON ca.AccountID = i.AccountID;
END;
GO

-- Update customer balance on payment
CREATE TRIGGER TR_Payments_UpdateBalance
ON Payments
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE ca
    SET ca.CurrentBalance = ca.CurrentBalance - i.Amount,
        ca.LastPaymentDate = i.PaymentDate
    FROM CustomerAccounts ca
    INNER JOIN inserted i ON ca.AccountID = i.AccountID
    WHERE i.Status = 'Processed';
END;
GO

-- Update invoice status on payment
CREATE TRIGGER TR_Payments_UpdateInvoiceStatus
ON Payments
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- This is a simplified version - production would need more complex payment allocation logic
    UPDATE i
    SET i.Status = 'Paid',
        i.PaymentDate = ins.PaymentDate,
        i.PaymentMethod = ins.PaymentMethod,
        i.PaymentReference = ins.PaymentReference
    FROM Invoices i
    INNER JOIN inserted ins ON i.AccountID = ins.AccountID
    WHERE i.Status = 'Unpaid'
    AND ins.Status = 'Processed';
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Process meter readings procedure
CREATE PROCEDURE sp_ProcessMeterReadings
    @MeterID INT,
    @ReadingDateTime DATETIME2,
    @Consumption DECIMAL(12,3),
    @ReadingType NVARCHAR(20) = 'Actual'
AS
BEGIN
    SET NOCOUNT ON;

    -- Insert the reading
    INSERT INTO MeterReadings (
        MeterID, ReadingDateTime, Consumption, ReadingType
    )
    VALUES (
        @MeterID, @ReadingDateTime, @Consumption, @ReadingType
    );

    -- Update meter last reading timestamp
    UPDATE SmartMeters
    SET LastReading = @ReadingDateTime
    WHERE MeterID = @MeterID;

    SELECT SCOPE_IDENTITY() AS ReadingID;
END;
GO

-- Generate invoice procedure
CREATE PROCEDURE sp_GenerateInvoice
    @AccountID INT,
    @BillingStartDate DATE,
    @BillingEndDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @InvoiceNumber NVARCHAR(50);
    DECLARE @TotalConsumption DECIMAL(12,3) = 0;
    DECLARE @CurrentCharges DECIMAL(10,2) = 0;
    DECLARE @Taxes DECIMAL(10,2) = 0;

    -- Generate invoice number
    SET @InvoiceNumber = 'INV-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                        RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) +
                        RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS NVARCHAR(6)), 6);

    -- Calculate consumption (simplified - would use actual meter data)
    SELECT @TotalConsumption = SUM(mr.Consumption)
    FROM SmartMeters sm
    INNER JOIN MeterReadings mr ON sm.MeterID = mr.MeterID
    WHERE sm.CustomerID = @AccountID
    AND CAST(mr.ReadingDateTime AS DATE) BETWEEN @BillingStartDate AND @BillingEndDate;

    -- Calculate charges (simplified - would use tariff logic)
    SET @CurrentCharges = @TotalConsumption * 0.12; -- $0.12 per unit
    SET @Taxes = @CurrentCharges * 0.08; -- 8% tax

    -- Create invoice
    INSERT INTO Invoices (
        InvoiceNumber, AccountID, BillingStartDate, BillingEndDate,
        CurrentCharges, Taxes, TotalAmount, TotalConsumption
    )
    VALUES (
        @InvoiceNumber, @AccountID, @BillingStartDate, @BillingEndDate,
        @CurrentCharges, @Taxes, @CurrentCharges + @Taxes, @TotalConsumption
    );

    SELECT SCOPE_IDENTITY() AS InvoiceID, @InvoiceNumber AS InvoiceNumber;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample power plant
INSERT INTO PowerPlants (PlantCode, PlantName, PlantType, InstalledCapacity, OperationalCapacity, Efficiency) VALUES
('PP-001', 'Sunrise Solar Farm', 'Solar', 100.0, 95.0, 0.85);

-- Insert sample substation
INSERT INTO Substations (SubstationCode, SubstationName, VoltageLevel, Capacity) VALUES
('SUB-001', 'Downtown Substation', '138kV', 150.0);

-- Insert sample power line
INSERT INTO PowerLines (LineCode, LineName, Voltage, Length, Capacity) VALUES
('LINE-001', 'Main Transmission Line', '138kV', 25.5, 200.0);

-- Insert sample tariff
INSERT INTO Tariffs (TariffCode, TariffName, BaseRate, ServiceCharge) VALUES
('RES-001', 'Residential Standard', 0.12, 15.00);

-- Insert sample customer account
INSERT INTO CustomerAccounts (AccountNumber, CustomerName, AccountType) VALUES
('ACC-000001', 'John Smith', 'Residential');

-- Insert sample smart meter
INSERT INTO SmartMeters (MeterNumber, CustomerID, MeterType) VALUES
('MTR-000001', 1, 'Electricity');

-- Insert sample meter reading
INSERT INTO MeterReadings (MeterID, ReadingDateTime, Consumption) VALUES
(1, GETDATE(), 125.50);

PRINT 'Energy database schema created successfully!';
GO