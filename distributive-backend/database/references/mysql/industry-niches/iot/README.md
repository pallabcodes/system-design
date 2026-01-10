# IoT & Sensor Data Management Platform Database Design

## Overview

This comprehensive database schema supports modern Internet of Things (IoT) platforms including sensor data collection, device management, real-time analytics, predictive maintenance, and industrial automation. The design handles massive-scale time-series data, complex device hierarchies, edge computing integration, and enterprise IoT operations.

## Key Features

### 📡 Device & Sensor Management
- **Device lifecycle management** with registration, configuration, and decommissioning
- **Sensor hierarchy and grouping** with location-based organization and metadata
- **Device firmware and software management** with version control and updates
- **Connectivity management** with protocols, authentication, and security

### 📊 Time-Series Data Collection
- **High-volume data ingestion** with optimized storage for sensor readings
- **Data quality assurance** with validation rules and anomaly detection
- **Data aggregation and downsampling** for efficient long-term storage
- **Real-time processing pipelines** with stream processing and alerting

### 🔧 Predictive Maintenance & Analytics
- **Asset health monitoring** with condition-based maintenance scheduling
- **Predictive analytics** using machine learning models and historical patterns
- **Maintenance work orders** with automated generation and tracking
- **Performance optimization** with trend analysis and capacity planning

## Database Schema Highlights

### Core Tables

#### Device Management
```sql
-- IoT devices master table
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

-- Device sensors and capabilities
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
```

#### Time-Series Data Storage
```sql
-- Sensor readings with optimized time-series storage
CREATE TABLE SensorReadings (
    ReadingID BIGINT IDENTITY(1,1) PRIMARY KEY,
    DeviceID INT NOT NULL REFERENCES Devices(DeviceID),
    SensorID INT NOT NULL REFERENCES DeviceSensors(SensorID),
    Timestamp DATETIME2 NOT NULL DEFAULT GETDATE(),

    -- Measurement data (flexible schema for different sensor types)
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

-- Aggregated sensor data for efficient queries
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
```

#### Alerts & Monitoring
```sql
-- Alert definitions and rules
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

-- Alert instances
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
```

### Asset Management & Maintenance

#### Asset Tracking
```sql
-- Physical assets being monitored
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

-- Maintenance work orders
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
```

#### Analytics & Reporting
```sql
-- Device performance metrics
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

-- Predictive maintenance models
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
```

## Integration Points

### External Systems
- **Edge Computing Platforms**: AWS IoT, Azure IoT Hub, Google Cloud IoT
- **Time-Series Databases**: InfluxDB, TimescaleDB for high-frequency data
- **Stream Processing**: Apache Kafka, AWS Kinesis for real-time data pipelines
- **ML Platforms**: TensorFlow, PyTorch for predictive analytics
- **SCADA Systems**: Industrial control systems integration
- **Asset Management**: CMMS systems for maintenance workflow

### API Endpoints
- **Device Management APIs**: Registration, configuration, monitoring, updates
- **Data Ingestion APIs**: Sensor data upload, batch processing, validation
- **Analytics APIs**: Real-time queries, aggregations, predictive insights
- **Maintenance APIs**: Work order creation, scheduling, completion tracking
- **Alert APIs**: Configuration, notification delivery, escalation

## Monitoring & Analytics

### Key Performance Indicators
- **Device Health**: Uptime, connectivity, data quality, battery life
- **Data Quality**: Completeness, accuracy, timeliness, anomaly rates
- **Maintenance Efficiency**: Mean time between failures, preventive maintenance success
- **Predictive Accuracy**: Model performance, false positive rates, prediction confidence
- **Operational Efficiency**: Alert response time, maintenance completion rates

### Real-Time Dashboards
```sql
-- IoT operations dashboard
CREATE VIEW IoTOperationsDashboard AS
SELECT
    -- Device health metrics (current status)
    (SELECT COUNT(*) FROM Devices WHERE Status = 'Active') AS ActiveDevices,
    (SELECT COUNT(*) FROM Devices WHERE LastSeen < DATEADD(MINUTE, -30, GETDATE())) AS OfflineDevices,
    (SELECT AVG(BatteryLevel) FROM Devices WHERE BatteryLevel IS NOT NULL) AS AvgBatteryLevel,
    (SELECT COUNT(*) FROM Devices WHERE BatteryLevel < 20) AS LowBatteryDevices,

    -- Data collection metrics (last 24 hours)
    (SELECT COUNT(*) FROM SensorReadings
     WHERE Timestamp >= DATEADD(DAY, -1, GETDATE())) AS ReadingsLast24Hours,
    (SELECT COUNT(DISTINCT DeviceID) FROM SensorReadings
     WHERE Timestamp >= DATEADD(DAY, -1, GETDATE())) AS ActiveDevicesLast24Hours,
    (SELECT AVG(AnomalyScore) FROM SensorReadings
     WHERE Timestamp >= DATEADD(DAY, -1, GETDATE()) AND AnomalyScore > 0) AS AvgAnomalyScore,

    -- Alert metrics (current week)
    (SELECT COUNT(*) FROM Alerts
     WHERE AlertTime >= DATEADD(DAY, -7, GETDATE()) AND Status = 'Active') AS ActiveAlerts,
    (SELECT COUNT(*) FROM Alerts
     WHERE AlertTime >= DATEADD(DAY, -7, GETDATE()) AND Status = 'Resolved') AS ResolvedAlerts,
    (SELECT AVG(DATEDIFF(HOUR, AlertTime, ResolvedTime)) FROM Alerts
     WHERE AlertTime >= DATEADD(DAY, -7, GETDATE()) AND Status = 'Resolved') AS AvgResolutionTime,

    -- Maintenance metrics (current month)
    (SELECT COUNT(*) FROM MaintenanceOrders
     WHERE MONTH(RequestedDate) = MONTH(GETDATE())
     AND YEAR(RequestedDate) = YEAR(GETDATE())) AS MaintenanceOrdersThisMonth,
    (SELECT COUNT(*) FROM MaintenanceOrders
     WHERE Status = 'Completed' AND MONTH(CompletedDate) = MONTH(GETDATE())) AS CompletedMaintenance,
    (SELECT COUNT(*) FROM Assets WHERE Status = 'Maintenance') AS AssetsInMaintenance,

    -- Predictive analytics (current week)
    (SELECT COUNT(*) FROM ModelPredictions
     WHERE PredictionTime >= DATEADD(DAY, -7, GETDATE())) AS PredictionsThisWeek,
    (SELECT AVG(ConfidenceScore) FROM ModelPredictions
     WHERE PredictionTime >= DATEADD(DAY, -7, GETDATE())) AS AvgPredictionConfidence,
    (SELECT COUNT(*) FROM ModelPredictions
     WHERE PredictionTime >= DATEADD(DAY, -7, GETDATE()) AND IsAccurate = 1) /
    NULLIF((SELECT COUNT(*) FROM ModelPredictions
     WHERE PredictionTime >= DATEADD(DAY, -7, GETDATE()) AND IsAccurate IS NOT NULL), 0) * 100 AS PredictionAccuracy

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This IoT database schema provides a comprehensive foundation for modern IoT platforms, supporting device management, time-series data processing, predictive maintenance, and enterprise IoT operations while maintaining high performance and scalability.
