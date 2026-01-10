-- IoT & Sensor Data Management Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE IoTDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE IoTDB;
GO

-- Configure database for IoT time-series data
ALTER DATABASE IoTDB
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
-- PARTITIONING SETUP FOR TIME-SERIES DATA
-- =============================================

-- Create partition function for sensor readings (by month)
CREATE PARTITION FUNCTION pf_SensorReadings_Monthly(DATETIME2)
AS RANGE RIGHT FOR VALUES (
    '2024-01-01', '2024-02-01', '2024-03-01', '2024-04-01', '2024-05-01', '2024-06-01',
    '2024-07-01', '2024-08-01', '2024-09-01', '2024-10-01', '2024-11-01', '2024-12-01',
    '2025-01-01', '2025-02-01', '2025-03-01', '2025-04-01', '2025-05-01', '2025-06-01'
);
GO

-- Create partition scheme for sensor readings
CREATE PARTITION SCHEME ps_SensorReadings
AS PARTITION pf_SensorReadings_Monthly
TO (fg_202401, fg_202402, fg_202403, fg_202404, fg_202405, fg_202406,
    fg_202407, fg_202408, fg_202409, fg_202410, fg_202411, fg_202412,
    fg_202501, fg_202502, fg_202503, fg_202504, fg_202505, fg_202506,
    fg_future);
GO

-- =============================================
-- DEVICE MANAGEMENT
-- =============================================

-- IoT devices
CREATE TABLE Devices (
    DeviceID INT IDENTITY(1,1) PRIMARY KEY,
    DeviceSerialNumber NVARCHAR(100) UNIQUE NOT NULL,
    DeviceType NVARCHAR(50) NOT NULL, -- Sensor, Actuator, Gateway, Controller
    DeviceModel NVARCHAR(100),
    Manufacturer NVARCHAR(100),
    FirmwareVersion NVARCHAR(50),
    HardwareVersion NVARCHAR(50),

    -- Location and installation
    LocationID INT,
    InstallationDate DATETIME2 DEFAULT GETDATE(),
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),
    Altitude DECIMAL(7,2),

    -- Operational status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, Maintenance, Retired
    LastSeen DATETIME2,
    LastMaintenanceDate DATETIME2,
    NextMaintenanceDate DATETIME2,
    BatteryLevel DECIMAL(5,2), -- Percentage for battery-powered devices

    -- Connectivity and security
    IPAddress NVARCHAR(45),
    MACAddress NVARCHAR(17),
    ConnectionType NVARCHAR(20), -- WiFi, Ethernet, Cellular, LoRa, Bluetooth
    EncryptionKey NVARCHAR(256), -- Encrypted
    AuthenticationToken NVARCHAR(256), -- Encrypted

    -- Metadata
    Configuration NVARCHAR(MAX), -- JSON configuration data
    Tags NVARCHAR(MAX), -- JSON array of tags
    CustomProperties NVARCHAR(MAX), -- JSON custom properties

    -- Constraints
    CONSTRAINT CK_Devices_Status CHECK (Status IN ('Active', 'Inactive', 'Maintenance', 'Retired', 'Offline')),
    CONSTRAINT CK_Devices_Battery CHECK (BatteryLevel BETWEEN 0 AND 100),
    CONSTRAINT CK_Devices_Type CHECK (DeviceType IN ('Sensor', 'Actuator', 'Gateway', 'Controller', 'Camera', 'Meter')),

    -- Indexes
    INDEX IX_Devices_Serial (DeviceSerialNumber),
    INDEX IX_Devices_Type (DeviceType),
    INDEX IX_Devices_Status (Status),
    INDEX IX_Devices_Location (LocationID),
    INDEX IX_Devices_LastSeen (LastSeen),
    INDEX IX_Devices_Model (DeviceModel)
);

-- Device sensors
CREATE TABLE DeviceSensors (
    SensorID INT IDENTITY(1,1) PRIMARY KEY,
    DeviceID INT NOT NULL REFERENCES Devices(DeviceID) ON DELETE CASCADE,
    SensorType NVARCHAR(50) NOT NULL, -- Temperature, Humidity, Pressure, Motion, etc.
    SensorName NVARCHAR(100),
    Unit NVARCHAR(20), -- Celsius, %, PSI, lux, etc.
    MeasurementRange NVARCHAR(50), -- -40 to 85°C, 0-100%, etc.
    Accuracy NVARCHAR(20), -- ±0.5°C, ±2%, etc.
    SamplingRate INT, -- Samples per second
    IsActive BIT DEFAULT 1,

    -- Calibration and maintenance
    LastCalibrationDate DATETIME2,
    CalibrationDueDate DATETIME2,
    CalibrationIntervalDays INT DEFAULT 365,

    -- Constraints
    CONSTRAINT CK_DeviceSensors_Type CHECK (SensorType IN ('Temperature', 'Humidity', 'Pressure', 'Motion', 'Light', 'Sound', 'Voltage', 'Current', 'Flow', 'Level', 'GPS', 'Acceleration', 'Gyroscope')),

    -- Indexes
    INDEX IX_DeviceSensors_Device (DeviceID),
    INDEX IX_DeviceSensors_Type (SensorType),
    INDEX IX_DeviceSensors_IsActive (IsActive)
);

-- =============================================
-- TIME-SERIES DATA STORAGE
-- =============================================

-- Sensor readings (partitioned table)
CREATE TABLE SensorReadings (
    ReadingID BIGINT IDENTITY(1,1) PRIMARY KEY,
    DeviceID INT NOT NULL REFERENCES Devices(DeviceID),
    SensorID INT NOT NULL REFERENCES DeviceSensors(SensorID),
    Timestamp DATETIME2 NOT NULL DEFAULT GETDATE(),

    -- Measurement data
    RawValue DECIMAL(18,6),
    ProcessedValue DECIMAL(18,6),
    Unit NVARCHAR(20),
    Quality NVARCHAR(20) DEFAULT 'Good', -- Good, Suspect, Bad

    -- Metadata
    SequenceNumber BIGINT, -- For ordering within device
    BatchID UNIQUEIDENTIFIER, -- For bulk imports
    Source NVARCHAR(20) DEFAULT 'Direct', -- Direct, Gateway, Edge

    -- Quality and validation
    IsValidated BIT DEFAULT 0,
    ValidationNotes NVARCHAR(MAX),
    AnomalyScore DECIMAL(5,4) DEFAULT 0, -- 0.0000 to 1.0000

    -- Constraints
    CONSTRAINT CK_SensorReadings_Quality CHECK (Quality IN ('Good', 'Suspect', 'Bad')),
    CONSTRAINT CK_SensorReadings_Anomaly CHECK (AnomalyScore BETWEEN 0 AND 1),

    -- Indexes (optimized for time-series queries)
    INDEX IX_SensorReadings_DeviceTime (DeviceID, Timestamp) WHERE Timestamp >= DATEADD(DAY, -30, GETDATE()),
    INDEX IX_SensorReadings_SensorTime (SensorID, Timestamp) WHERE Timestamp >= DATEADD(DAY, -30, GETDATE()),
    INDEX IX_SensorReadings_TimeOnly (Timestamp) WHERE Timestamp >= DATEADD(DAY, -7, GETDATE()),
    INDEX IX_SensorReadings_Quality (Quality),
    INDEX IX_SensorReadings_Anomaly (AnomalyScore DESC) WHERE AnomalyScore > 0.5
) ON ps_SensorReadings(Timestamp); -- Partitioned by timestamp

-- Sensor aggregates
CREATE TABLE SensorAggregates (
    AggregateID BIGINT IDENTITY(1,1) PRIMARY KEY,
    DeviceID INT NOT NULL REFERENCES Devices(DeviceID),
    SensorID INT NOT NULL REFERENCES DeviceSensors(SensorID),
    AggregateType NVARCHAR(20) NOT NULL, -- Hourly, Daily, Weekly, Monthly
    StartTime DATETIME2 NOT NULL,
    EndTime DATETIME2 NOT NULL,

    -- Aggregate values
    MinValue DECIMAL(18,6),
    MaxValue DECIMAL(18,6),
    AvgValue DECIMAL(18,6),
    StdDev DECIMAL(18,6),
    SampleCount INT,
    SumValue DECIMAL(24,6),

    -- Quality metrics
    GoodReadings INT DEFAULT 0,
    SuspectReadings INT DEFAULT 0,
    BadReadings INT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_SensorAggregates_Type CHECK (AggregateType IN ('Hourly', 'Daily', 'Weekly', 'Monthly')),
    CONSTRAINT CK_SensorAggregates_Time CHECK (EndTime > StartTime),

    -- Indexes
    INDEX IX_SensorAggregates_DeviceSensor (DeviceID, SensorID, AggregateType),
    INDEX IX_SensorAggregates_TimeRange (StartTime, EndTime),
    INDEX IX_SensorAggregates_TypeTime (AggregateType, StartTime)
);

-- =============================================
-- ALERTS & MONITORING
-- =============================================

-- Alert rules
CREATE TABLE AlertRules (
    RuleID INT IDENTITY(1,1) PRIMARY KEY,
    RuleName NVARCHAR(200) NOT NULL,
    RuleType NVARCHAR(20) DEFAULT 'Threshold', -- Threshold, Trend, Anomaly, Predictive
    Description NVARCHAR(MAX),

    -- Rule conditions (JSON)
    Conditions NVARCHAR(MAX), -- {"sensor_type": "Temperature", "operator": ">", "value": 80, "duration": 300}

    -- Alert settings
    Severity NVARCHAR(10) DEFAULT 'Medium', -- Low, Medium, High, Critical
    IsActive BIT DEFAULT 1,
    NotificationChannels NVARCHAR(MAX), -- JSON array: ["email", "sms", "webhook"]
    CooldownMinutes INT DEFAULT 60, -- Minimum time between alerts

    -- Constraints
    CONSTRAINT CK_AlertRules_Type CHECK (RuleType IN ('Threshold', 'Trend', 'Anomaly', 'Predictive')),
    CONSTRAINT CK_AlertRules_Severity CHECK (Severity IN ('Low', 'Medium', 'High', 'Critical')),

    -- Indexes
    INDEX IX_AlertRules_Type (RuleType),
    INDEX IX_AlertRules_IsActive (IsActive),
    INDEX IX_AlertRules_Severity (Severity)
);

-- Alerts
CREATE TABLE Alerts (
    AlertID BIGINT IDENTITY(1,1) PRIMARY KEY,
    RuleID INT NOT NULL REFERENCES AlertRules(RuleID),
    DeviceID INT NOT NULL REFERENCES Devices(DeviceID),
    SensorID INT REFERENCES DeviceSensors(SensorID),
    AlertTime DATETIME2 DEFAULT GETDATE(),

    -- Alert details
    AlertMessage NVARCHAR(MAX),
    Severity NVARCHAR(10),
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Acknowledged, Resolved, FalsePositive

    -- Triggering data
    TriggerValue DECIMAL(18,6),
    ThresholdValue DECIMAL(18,6),
    Condition NVARCHAR(50),

    -- Resolution
    AcknowledgedBy INT,
    AcknowledgedTime DATETIME2,
    ResolvedBy INT,
    ResolvedTime DATETIME2,
    ResolutionNotes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_Alerts_Status CHECK (Status IN ('Active', 'Acknowledged', 'Resolved', 'FalsePositive')),

    -- Indexes
    INDEX IX_Alerts_Device (DeviceID, AlertTime DESC),
    INDEX IX_Alerts_Rule (RuleID, AlertTime DESC),
    INDEX IX_Alerts_Status (Status, AlertTime DESC),
    INDEX IX_Alerts_Severity (Severity, AlertTime DESC),
    INDEX IX_Alerts_Time (AlertTime DESC)
);

-- =============================================
-- ASSET MANAGEMENT & MAINTENANCE
-- =============================================

-- Assets
CREATE TABLE Assets (
    AssetID INT IDENTITY(1,1) PRIMARY KEY,
    AssetNumber NVARCHAR(50) UNIQUE NOT NULL,
    AssetName NVARCHAR(200) NOT NULL,
    AssetType NVARCHAR(50) NOT NULL, -- Equipment, Vehicle, Building, Infrastructure
    Category NVARCHAR(50),
    Manufacturer NVARCHAR(100),
    Model NVARCHAR(100),
    SerialNumber NVARCHAR(100),

    -- Location and installation
    LocationID INT,
    InstallationDate DATETIME2,
    PurchaseDate DATETIME2,
    WarrantyExpiration DATETIME2,
    ExpectedLifespanYears INT,

    -- Financial information
    PurchasePrice DECIMAL(15,2),
    CurrentValue DECIMAL(15,2),
    DepreciationMethod NVARCHAR(20), -- StraightLine, DecliningBalance
    AccumulatedDepreciation DECIMAL(15,2),

    -- Operational status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Maintenance, Retired, Scrapped
    HealthScore DECIMAL(5,2) DEFAULT 1.0, -- 0.00 to 1.00 (1.0 = perfect health)

    -- Maintenance schedule
    MaintenanceIntervalDays INT,
    LastMaintenanceDate DATETIME2,
    NextMaintenanceDate DATETIME2,

    -- Associated devices
    PrimaryDeviceID INT REFERENCES Devices(DeviceID),
    BackupDeviceID INT REFERENCES Devices(DeviceID),

    -- Constraints
    CONSTRAINT CK_Assets_Status CHECK (Status IN ('Active', 'Maintenance', 'Retired', 'Scrapped')),
    CONSTRAINT CK_Assets_Health CHECK (HealthScore BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_Assets_Number (AssetNumber),
    INDEX IX_Assets_Type (AssetType),
    INDEX IX_Assets_Status (Status),
    INDEX IX_Assets_Health (HealthScore),
    INDEX IX_Assets_NextMaintenance (NextMaintenanceDate)
);

-- Maintenance orders
CREATE TABLE MaintenanceOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    OrderNumber NVARCHAR(50) UNIQUE NOT NULL,
    AssetID INT NOT NULL REFERENCES Assets(AssetID),
    OrderType NVARCHAR(20) DEFAULT 'Preventive', -- Preventive, Corrective, Predictive, Emergency
    Priority NVARCHAR(10) DEFAULT 'Medium', -- Low, Medium, High, Critical

    -- Order details
    Title NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    RequestedDate DATETIME2 DEFAULT GETDATE(),
    ScheduledDate DATETIME2,
    DueDate DATETIME2,
    CompletedDate DATETIME2,

    -- Assignment and status
    AssignedTo INT,
    Status NVARCHAR(20) DEFAULT 'Open', -- Open, Scheduled, InProgress, Completed, Cancelled
    EstimatedHours DECIMAL(6,2),
    ActualHours DECIMAL(6,2),
    EstimatedCost DECIMAL(10,2),
    ActualCost DECIMAL(10,2),

    -- Work details
    PartsUsed NVARCHAR(MAX), -- JSON array of parts
    WorkPerformed NVARCHAR(MAX),
    TechnicianNotes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_MaintenanceOrders_Type CHECK (OrderType IN ('Preventive', 'Corrective', 'Predictive', 'Emergency')),
    CONSTRAINT CK_MaintenanceOrders_Priority CHECK (Priority IN ('Low', 'Medium', 'High', 'Critical')),
    CONSTRAINT CK_MaintenanceOrders_Status CHECK (Status IN ('Open', 'Scheduled', 'InProgress', 'Completed', 'Cancelled')),

    -- Indexes
    INDEX IX_MaintenanceOrders_Asset (AssetID),
    INDEX IX_MaintenanceOrders_Type (OrderType),
    INDEX IX_MaintenanceOrders_Status (Status),
    INDEX IX_MaintenanceOrders_Priority (Priority),
    INDEX IX_MaintenanceOrders_DueDate (DueDate),
    INDEX IX_MaintenanceOrders_ScheduledDate (ScheduledDate)
);

-- =============================================
-- ANALYTICS & PREDICTIVE MODELS
-- =============================================

-- Device metrics
CREATE TABLE DeviceMetrics (
    MetricID BIGINT IDENTITY(1,1) PRIMARY KEY,
    DeviceID INT NOT NULL REFERENCES Devices(DeviceID),
    MetricDate DATE NOT NULL,
    UptimePercentage DECIMAL(5,2), -- 0.00 to 100.00
    DataPointsCollected INT DEFAULT 0,
    AlertsGenerated INT DEFAULT 0,
    MaintenanceEvents INT DEFAULT 0,
    BatteryDrainRate DECIMAL(5,2), -- Percentage per day
    ConnectivityScore DECIMAL(5,2), -- 0.00 to 100.00 (connection quality)
    DataQualityScore DECIMAL(5,2), -- 0.00 to 100.00

    -- Constraints
    CONSTRAINT UQ_DeviceMetrics_DeviceDate UNIQUE (DeviceID, MetricDate),
    CONSTRAINT CK_DeviceMetrics_Uptime CHECK (UptimePercentage BETWEEN 0 AND 100),
    CONSTRAINT CK_DeviceMetrics_Connectivity CHECK (ConnectivityScore BETWEEN 0 AND 100),
    CONSTRAINT CK_DeviceMetrics_Quality CHECK (DataQualityScore BETWEEN 0 AND 100),

    -- Indexes
    INDEX IX_DeviceMetrics_Device (DeviceID),
    INDEX IX_DeviceMetrics_Date (MetricDate),
    INDEX IX_DeviceMetrics_Uptime (UptimePercentage)
);

-- Predictive models
CREATE TABLE PredictiveModels (
    ModelID INT IDENTITY(1,1) PRIMARY KEY,
    ModelName NVARCHAR(200) NOT NULL,
    ModelType NVARCHAR(50) NOT NULL, -- Regression, Classification, AnomalyDetection
    TargetVariable NVARCHAR(100), -- What the model predicts
    Algorithm NVARCHAR(50), -- LinearRegression, RandomForest, NeuralNetwork
    Accuracy DECIMAL(5,4), -- 0.0000 to 1.0000
    TrainingDate DATETIME2 DEFAULT GETDATE(),
    LastRetrained DATETIME2,
    IsActive BIT DEFAULT 1,

    -- Model metadata
    TrainingData NVARCHAR(MAX), -- JSON: dataset info, features used
    ModelParameters NVARCHAR(MAX), -- JSON: hyperparameters
    PerformanceMetrics NVARCHAR(MAX), -- JSON: precision, recall, F1-score

    -- Constraints
    CONSTRAINT CK_PredictiveModels_Type CHECK (ModelType IN ('Regression', 'Classification', 'AnomalyDetection', 'Forecasting')),
    CONSTRAINT CK_PredictiveModels_Accuracy CHECK (Accuracy BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_PredictiveModels_Type (ModelType),
    INDEX IX_PredictiveModels_IsActive (IsActive),
    INDEX IX_PredictiveModels_Accuracy (Accuracy DESC)
);

-- Model predictions
CREATE TABLE ModelPredictions (
    PredictionID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ModelID INT NOT NULL REFERENCES PredictiveModels(ModelID),
    DeviceID INT NOT NULL REFERENCES Devices(DeviceID),
    PredictionTime DATETIME2 DEFAULT GETDATE(),
    PredictionHorizon NVARCHAR(20), -- 1hour, 1day, 1week, 1month

    -- Prediction results
    PredictedValue DECIMAL(18,6),
    ConfidenceScore DECIMAL(5,4), -- 0.0000 to 1.0000
    PredictionRange NVARCHAR(MAX), -- JSON: {"min": 10, "max": 15}

    -- Actual outcome (filled later)
    ActualValue DECIMAL(18,6),
    PredictionError DECIMAL(18,6),
    IsAccurate BIT,

    -- Constraints
    CONSTRAINT CK_ModelPredictions_Horizon CHECK (PredictionHorizon IN ('1hour', '6hours', '1day', '1week', '1month')),
    CONSTRAINT CK_ModelPredictions_Confidence CHECK (ConfidenceScore BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_ModelPredictions_Device (DeviceID, PredictionTime DESC),
    INDEX IX_ModelPredictions_Model (ModelID, PredictionTime DESC),
    INDEX IX_ModelPredictions_Time (PredictionTime DESC)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Device status view
CREATE VIEW vw_DeviceStatus
AS
SELECT
    d.DeviceID,
    d.DeviceSerialNumber,
    d.DeviceType,
    d.DeviceModel,
    d.Manufacturer,
    d.Status,
    d.LastSeen,
    d.BatteryLevel,
    d.ConnectionType,
    DATEDIFF(MINUTE, d.LastSeen, GETDATE()) AS MinutesSinceLastSeen,

    -- Device health indicators
    CASE
        WHEN DATEDIFF(MINUTE, d.LastSeen, GETDATE()) > 30 THEN 'Offline'
        WHEN d.BatteryLevel < 20 THEN 'Low Battery'
        WHEN d.Status = 'Maintenance' THEN 'Maintenance'
        ELSE 'Healthy'
    END AS HealthStatus,

    -- Recent activity
    (SELECT COUNT(*) FROM SensorReadings sr
     WHERE sr.DeviceID = d.DeviceID AND sr.Timestamp >= DATEADD(HOUR, -24, GETDATE())) AS ReadingsLast24Hours,
    (SELECT COUNT(*) FROM Alerts a
     WHERE a.DeviceID = d.DeviceID AND a.Status = 'Active') AS ActiveAlerts

FROM Devices d
WHERE d.Status != 'Retired';
GO

-- Asset health overview
CREATE VIEW vw_AssetHealth
AS
SELECT
    a.AssetID,
    a.AssetNumber,
    a.AssetName,
    a.AssetType,
    a.Status,
    a.HealthScore,
    a.LastMaintenanceDate,
    a.NextMaintenanceDate,

    -- Associated device information
    d.DeviceSerialNumber,
    d.Status AS DeviceStatus,
    d.LastSeen AS DeviceLastSeen,

    -- Recent maintenance
    (SELECT COUNT(*) FROM MaintenanceOrders mo
     WHERE mo.AssetID = a.AssetID AND mo.Status = 'Completed'
     AND mo.CompletedDate >= DATEADD(MONTH, -6, GETDATE())) AS MaintenanceLast6Months,

    -- Active alerts
    (SELECT COUNT(*) FROM Alerts al
     INNER JOIN Devices d2 ON al.DeviceID = d2.DeviceID
     WHERE d2.DeviceID = a.PrimaryDeviceID AND al.Status = 'Active') AS ActiveAlerts

FROM Assets a
LEFT JOIN Devices d ON a.PrimaryDeviceID = d.DeviceID
WHERE a.Status IN ('Active', 'Maintenance');
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update device last seen timestamp
CREATE TRIGGER TR_SensorReadings_UpdateLastSeen
ON SensorReadings
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d
    SET d.LastSeen = i.Timestamp
    FROM Devices d
    INNER JOIN inserted i ON d.DeviceID = i.DeviceID
    WHERE i.Timestamp > ISNULL(d.LastSeen, '1900-01-01');
END;
GO

-- Auto-create aggregates (simplified example for hourly aggregates)
CREATE TRIGGER TR_SensorReadings_Aggregates
ON SensorReadings
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- This is a simplified example - in production, you'd use scheduled jobs
    -- for batch aggregation to avoid performance issues with triggers

    INSERT INTO SensorAggregates (
        DeviceID, SensorID, AggregateType, StartTime, EndTime,
        MinValue, MaxValue, AvgValue, SampleCount, GoodReadings
    )
    SELECT
        i.DeviceID,
        i.SensorID,
        'Hourly',
        DATEADD(HOUR, DATEDIFF(HOUR, 0, i.Timestamp), 0),
        DATEADD(HOUR, DATEDIFF(HOUR, 0, i.Timestamp) + 1, 0),
        MIN(i.ProcessedValue),
        MAX(i.ProcessedValue),
        AVG(i.ProcessedValue),
        COUNT(*),
        SUM(CASE WHEN i.Quality = 'Good' THEN 1 ELSE 0 END)
    FROM inserted i
    WHERE NOT EXISTS (
        SELECT 1 FROM SensorAggregates sa
        WHERE sa.DeviceID = i.DeviceID
        AND sa.SensorID = i.SensorID
        AND sa.AggregateType = 'Hourly'
        AND sa.StartTime = DATEADD(HOUR, DATEDIFF(HOUR, 0, i.Timestamp), 0)
    )
    GROUP BY i.DeviceID, i.SensorID, DATEADD(HOUR, DATEDIFF(HOUR, 0, i.Timestamp), 0);
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Register new device procedure
CREATE PROCEDURE sp_RegisterDevice
    @DeviceSerialNumber NVARCHAR(100),
    @DeviceType NVARCHAR(50),
    @DeviceModel NVARCHAR(100),
    @Manufacturer NVARCHAR(100),
    @Latitude DECIMAL(10,8) = NULL,
    @Longitude DECIMAL(11,8) = NULL,
    @LocationID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Devices (
        DeviceSerialNumber, DeviceType, DeviceModel, Manufacturer,
        Latitude, Longitude, LocationID, Status
    )
    VALUES (
        @DeviceSerialNumber, @DeviceType, @DeviceModel, @Manufacturer,
        @Latitude, @Longitude, @LocationID, 'Active'
    );

    SELECT SCOPE_IDENTITY() AS DeviceID;
END;
GO

-- Ingest sensor data procedure
CREATE PROCEDURE sp_IngestSensorData
    @DeviceSerialNumber NVARCHAR(100),
    @SensorType NVARCHAR(50),
    @Value DECIMAL(18,6),
    @Timestamp DATETIME2 = NULL,
    @Quality NVARCHAR(20) = 'Good'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @DeviceID INT, @SensorID INT;

    -- Get device ID
    SELECT @DeviceID = DeviceID FROM Devices
    WHERE DeviceSerialNumber = @DeviceSerialNumber AND Status = 'Active';

    IF @DeviceID IS NULL
    BEGIN
        RAISERROR('Device not found or not active', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- Get or create sensor
    SELECT @SensorID = SensorID FROM DeviceSensors
    WHERE DeviceID = @DeviceID AND SensorType = @SensorType AND IsActive = 1;

    IF @SensorID IS NULL
    BEGIN
        INSERT INTO DeviceSensors (DeviceID, SensorType, IsActive)
        VALUES (@DeviceID, @SensorType, 1);

        SET @SensorID = SCOPE_IDENTITY();
    END

    -- Insert reading
    INSERT INTO SensorReadings (
        DeviceID, SensorID, Timestamp, RawValue, ProcessedValue, Quality
    )
    VALUES (
        @DeviceID, @SensorID, ISNULL(@Timestamp, GETDATE()),
        @Value, @Value, @Quality
    );

    COMMIT TRANSACTION;

    SELECT SCOPE_IDENTITY() AS ReadingID;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample devices
INSERT INTO Devices (DeviceSerialNumber, DeviceType, DeviceModel, Manufacturer, Latitude, Longitude) VALUES
('DEV-001', 'Sensor', 'TempSens-2000', 'SensorTech', 40.7128, -74.0060),
('DEV-002', 'Gateway', 'IoT-GW-Pro', 'ConnectIoT', 40.7128, -74.0060);

-- Insert sample sensors
INSERT INTO DeviceSensors (DeviceID, SensorType, SensorName, Unit) VALUES
(1, 'Temperature', 'Ambient Temperature', 'Celsius'),
(1, 'Humidity', 'Relative Humidity', '%');

-- Insert sample readings
INSERT INTO SensorReadings (DeviceID, SensorID, Timestamp, RawValue, ProcessedValue, Quality) VALUES
(1, 1, '2024-01-15 10:00:00', 23.5, 23.5, 'Good'),
(1, 2, '2024-01-15 10:00:00', 65.2, 65.2, 'Good');

-- Insert sample asset
INSERT INTO Assets (AssetNumber, AssetName, AssetType, Manufacturer, Model) VALUES
('AST-001', 'HVAC Unit 1', 'Equipment', 'ClimateCorp', 'HVAC-5000');

PRINT 'IoT database schema created successfully!';
GO
