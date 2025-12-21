-- Hospitality & Hotel Management Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE HospitalityDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE HospitalityDB;
GO

-- Configure database for hospitality performance
ALTER DATABASE HospitalityDB
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
-- PROPERTY & ROOM MANAGEMENT
-- =============================================

-- Hotel properties
CREATE TABLE Properties (
    PropertyID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyCode NVARCHAR(20) UNIQUE NOT NULL,
    PropertyName NVARCHAR(200) NOT NULL,
    PropertyType NVARCHAR(50) DEFAULT 'Hotel', -- Hotel, Resort, Boutique, Serviced Apartment, etc.

    -- Location and contact
    Address NVARCHAR(MAX), -- JSON formatted complete address
    City NVARCHAR(100),
    State NVARCHAR(50),
    Country NVARCHAR(50),
    PostalCode NVARCHAR(20),
    Phone NVARCHAR(20),
    Email NVARCHAR(255),
    Website NVARCHAR(500),

    -- Property details
    StarRating INT CHECK (StarRating BETWEEN 1 AND 5),
    TotalRooms INT NOT NULL,
    TotalFloors INT,
    YearBuilt INT,
    LastRenovated INT,

    -- Operational details
    CheckInTime TIME DEFAULT '15:00',
    CheckOutTime TIME DEFAULT '11:00',
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',
    TimeZone NVARCHAR(50) DEFAULT 'UTC',

    -- Management
    GeneralManager NVARCHAR(100),
    ContactPerson NVARCHAR(100),
    ContactPhone NVARCHAR(20),
    ContactEmail NVARCHAR(255),

    -- Status and settings
    IsActive BIT DEFAULT 1,
    Franchise NVARCHAR(100), -- Marriott, Hilton, IHG, etc.
    Brand NVARCHAR(100),
    ManagementCompany NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_Properties_Type CHECK (PropertyType IN ('Hotel', 'Resort', 'Boutique', 'ServicedApartment', 'VacationRental', 'Hostel')),

    -- Indexes
    INDEX IX_Properties_Code (PropertyCode),
    INDEX IX_Properties_Name (PropertyName),
    INDEX IX_Properties_Type (PropertyType),
    INDEX IX_Properties_City (City),
    INDEX IX_Properties_IsActive (IsActive)
);

-- Room types
CREATE TABLE RoomTypes (
    RoomTypeID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyID INT NOT NULL REFERENCES Properties(PropertyID),
    RoomTypeCode NVARCHAR(20) NOT NULL,
    RoomTypeName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),

    -- Room specifications
    MaxOccupancy INT NOT NULL,
    RoomSize DECIMAL(8,2), -- Square meters/feet
    BedConfiguration NVARCHAR(100), -- 1 King, 2 Queens, etc.
    BathroomType NVARCHAR(50), -- Private, Shared, Ensuite

    -- Amenities and features (JSON arrays)
    StandardAmenities NVARCHAR(MAX), -- ["WiFi", "TV", "MiniBar", "Safe"]
    PremiumAmenities NVARCHAR(MAX), -- ["Balcony", "OceanView", "Jacuzzi"]
    Accessibility NVARCHAR(MAX), -- ["WheelchairAccessible", "HearingImpaired"]

    -- Operational settings
    SmokingAllowed BIT DEFAULT 0,
    PetFriendly BIT DEFAULT 0,
    ConnectingRooms BIT DEFAULT 0,

    -- Pricing
    BaseRate DECIMAL(10,2),
    MinimumRate DECIMAL(10,2),
    MaximumRate DECIMAL(10,2),

    -- Status
    IsActive BIT DEFAULT 1,
    SortOrder INT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_RoomTypes_PropertyCode UNIQUE (PropertyID, RoomTypeCode),
    CONSTRAINT CK_RoomTypes_Occupancy CHECK (MaxOccupancy BETWEEN 1 AND 10),

    -- Indexes
    INDEX IX_RoomTypes_Property (PropertyID),
    INDEX IX_RoomTypes_Code (RoomTypeCode),
    INDEX IX_RoomTypes_IsActive (IsActive),
    INDEX IX_RoomTypes_SortOrder (SortOrder)
);

-- Individual rooms
CREATE TABLE Rooms (
    RoomID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyID INT NOT NULL REFERENCES Properties(PropertyID),
    RoomTypeID INT NOT NULL REFERENCES RoomTypes(RoomTypeID),
    RoomNumber NVARCHAR(20) NOT NULL,
    FloorNumber INT,

    -- Room details
    RoomName NVARCHAR(100),
    RoomStatus NVARCHAR(20) DEFAULT 'Clean', -- Clean, Dirty, OutOfOrder, Maintenance
    HousekeepingStatus NVARCHAR(20) DEFAULT 'Inspected', -- Inspected, Cleaning, Ready, DoNotDisturb

    -- Physical characteristics
    SquareFootage DECIMAL(8,2),
    ViewType NVARCHAR(50), -- Ocean, Mountain, City, Garden, None
    ConnectingRoomID INT REFERENCES Rooms(RoomID),

    -- Maintenance and history
    LastMaintenanceDate DATETIME2,
    NextMaintenanceDate DATETIME2,
    LastRenovationDate DATETIME2,

    -- Operational settings
    SmokingAllowed BIT DEFAULT 0,
    PetAllowed BIT DEFAULT 0,
    IsAccessible BIT DEFAULT 0,

    -- Financial
    RoomCost DECIMAL(10,2), -- Internal cost for profitability analysis

    -- Constraints
    CONSTRAINT UQ_Rooms_PropertyNumber UNIQUE (PropertyID, RoomNumber),
    CONSTRAINT CK_Rooms_Status CHECK (RoomStatus IN ('Clean', 'Dirty', 'OutOfOrder', 'Maintenance')),
    CONSTRAINT CK_Rooms_Housekeeping CHECK (HousekeepingStatus IN ('Inspected', 'Cleaning', 'Ready', 'DoNotDisturb')),

    -- Indexes
    INDEX IX_Rooms_Property (PropertyID),
    INDEX IX_Rooms_Type (RoomTypeID),
    INDEX IX_Rooms_Number (RoomNumber),
    INDEX IX_Rooms_Status (RoomStatus),
    INDEX IX_Rooms_Housekeeping (HousekeepingStatus)
);

-- =============================================
-- GUEST MANAGEMENT
-- =============================================

-- Guest profiles
CREATE TABLE Guests (
    GuestID INT IDENTITY(1,1) PRIMARY KEY,
    GuestNumber NVARCHAR(20) UNIQUE NOT NULL,

    -- Personal information
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    MiddleName NVARCHAR(100),
    DateOfBirth DATE,
    Gender NVARCHAR(20),

    -- Contact information
    Email NVARCHAR(255),
    Phone NVARCHAR(20),
    Mobile NVARCHAR(20),
    Address NVARCHAR(MAX), -- JSON formatted

    -- Guest preferences (JSON)
    RoomPreferences NVARCHAR(MAX), -- ["NonSmoking", "HighFloor", "Quiet"]
    AmenityPreferences NVARCHAR(MAX), -- ["Gym", "Pool", "Spa"]
    DietaryRestrictions NVARCHAR(MAX), -- ["Vegetarian", "GlutenFree", "Kosher"]

    -- Loyalty program
    LoyaltyProgram NVARCHAR(100), -- Hotel chain loyalty program
    LoyaltyNumber NVARCHAR(50),
    LoyaltyTier NVARCHAR(20) DEFAULT 'Bronze', -- Bronze, Silver, Gold, Platinum
    LoyaltyPoints INT DEFAULT 0,

    -- Guest history
    TotalStays INT DEFAULT 0,
    TotalNights INT DEFAULT 0,
    TotalSpent DECIMAL(12,2) DEFAULT 0,
    LastStayDate DATETIME2,
    PreferredRoomType NVARCHAR(100),

    -- Marketing and communication
    EmailOptIn BIT DEFAULT 1,
    SmsOptIn BIT DEFAULT 0,
    MarketingOptIn BIT DEFAULT 1,

    -- Status
    GuestStatus NVARCHAR(20) DEFAULT 'Active', -- Active, VIP, Blacklisted, Inactive
    Notes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_Guests_Status CHECK (GuestStatus IN ('Active', 'VIP', 'Blacklisted', 'Inactive')),
    CONSTRAINT CK_Guests_Tier CHECK (LoyaltyTier IN ('Bronze', 'Silver', 'Gold', 'Platinum')),

    -- Indexes
    INDEX IX_Guests_Number (GuestNumber),
    INDEX IX_Guests_Name (LastName, FirstName),
    INDEX IX_Guests_Email (Email),
    INDEX IX_Guests_LoyaltyNumber (LoyaltyNumber),
    INDEX IX_Guests_Status (GuestStatus)
);

-- =============================================
-- RESERVATION & BOOKING MANAGEMENT
-- =============================================

-- Reservations
CREATE TABLE Reservations (
    ReservationID INT IDENTITY(1,1) PRIMARY KEY,
    ReservationNumber NVARCHAR(50) UNIQUE NOT NULL,
    PropertyID INT NOT NULL REFERENCES Properties(PropertyID),
    GuestID INT NOT NULL REFERENCES Guests(GuestID),

    -- Reservation details
    ReservationType NVARCHAR(20) DEFAULT 'Individual', -- Individual, Group, Event, Corporate
    MarketSegment NVARCHAR(50), -- Leisure, Business, Conference, TourGroup

    -- Stay details
    ArrivalDate DATE NOT NULL,
    DepartureDate DATE NOT NULL,
    Nights INT NOT NULL,
    Adults INT DEFAULT 1,
    Children INT DEFAULT 0,
    Infants INT DEFAULT 0,

    -- Room assignment
    RoomTypeID INT REFERENCES RoomTypes(RoomTypeID),
    RoomID INT REFERENCES Rooms(RoomID), -- Assigned at check-in
    RoomRate DECIMAL(10,2),
    RateCode NVARCHAR(50),

    -- Financial details
    Subtotal DECIMAL(10,2),
    Taxes DECIMAL(10,2),
    Fees DECIMAL(10,2), -- Resort fees, cleaning fees, etc.
    TotalAmount DECIMAL(12,2),
    DepositAmount DECIMAL(10,2),
    DepositPaid BIT DEFAULT 0,

    -- Booking information
    BookingChannel NVARCHAR(50) DEFAULT 'Direct', -- Direct, OTA, GDS, ThirdParty
    BookingReference NVARCHAR(100),
    ConfirmationNumber NVARCHAR(50),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy NVARCHAR(100),

    -- Status and lifecycle
    ReservationStatus NVARCHAR(20) DEFAULT 'Confirmed', -- Tentative, Confirmed, CheckedIn, CheckedOut, Cancelled, NoShow
    CancellationDate DATETIME2,
    CancellationReason NVARCHAR(MAX),
    CancellationPolicy NVARCHAR(MAX),

    -- Guest requests and preferences
    SpecialRequests NVARCHAR(MAX),
    AccessibilityRequirements NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_Reservations_Type CHECK (ReservationType IN ('Individual', 'Group', 'Event', 'Corporate')),
    CONSTRAINT CK_Reservations_Status CHECK (ReservationStatus IN ('Tentative', 'Confirmed', 'CheckedIn', 'CheckedOut', 'Cancelled', 'NoShow')),
    CONSTRAINT CK_Reservations_Dates CHECK (DepartureDate > ArrivalDate),
    CONSTRAINT CK_Reservations_Occupancy CHECK (Adults >= 0 AND Children >= 0 AND Infants >= 0),

    -- Indexes
    INDEX IX_Reservations_Number (ReservationNumber),
    INDEX IX_Reservations_Property (PropertyID),
    INDEX IX_Reservations_Guest (GuestID),
    INDEX IX_Reservations_Type (ReservationType),
    INDEX IX_Reservations_Status (ReservationStatus),
    INDEX IX_Reservations_Arrival (ArrivalDate),
    INDEX IX_Reservations_Departure (DepartureDate),
    INDEX IX_Reservations_Channel (BookingChannel),
    INDEX IX_Reservations_Confirmation (ConfirmationNumber)
);

-- Reservation room assignments
CREATE TABLE ReservationRooms (
    ReservationRoomID INT IDENTITY(1,1) PRIMARY KEY,
    ReservationID INT NOT NULL REFERENCES Reservations(ReservationID) ON DELETE CASCADE,
    RoomTypeID INT NOT NULL REFERENCES RoomTypes(RoomTypeID),
    RoomID INT REFERENCES Rooms(RoomID),

    -- Guest assignment
    GuestName NVARCHAR(200),
    GuestType NVARCHAR(20) DEFAULT 'Adult', -- Adult, Child, Infant

    -- Rate details
    Rate DECIMAL(10,2),
    RateCode NVARCHAR(50),
    RateDescription NVARCHAR(MAX),

    -- Stay dates (may differ for multi-room reservations)
    CheckInDate DATE,
    CheckOutDate DATE,

    -- Constraints
    CONSTRAINT CK_ReservationRooms_Type CHECK (GuestType IN ('Adult', 'Child', 'Infant')),

    -- Indexes
    INDEX IX_ReservationRooms_Reservation (ReservationID),
    INDEX IX_ReservationRooms_RoomType (RoomTypeID),
    INDEX IX_ReservationRooms_Room (RoomID)
);

-- =============================================
-- GUEST STAYS & SERVICES
-- =============================================

-- Guest in-house stays
CREATE TABLE GuestStays (
    StayID INT IDENTITY(1,1) PRIMARY KEY,
    ReservationID INT NOT NULL REFERENCES Reservations(ReservationID),
    GuestID INT NOT NULL REFERENCES Guests(GuestID),
    PropertyID INT NOT NULL REFERENCES Properties(PropertyID),
    RoomID INT NOT NULL REFERENCES Rooms(RoomID),

    -- Stay details
    CheckInDate DATETIME2 NOT NULL,
    CheckOutDate DATETIME2,
    ActualCheckOutDate DATETIME2,
    ExpectedDepartureDate DATETIME2,
    Nights INT,

    -- Guest information
    GuestName NVARCHAR(200),
    GuestPhone NVARCHAR(20),
    GuestEmail NVARCHAR(255),

    -- Financial summary
    RoomCharges DECIMAL(10,2) DEFAULT 0,
    FoodBeverage DECIMAL(10,2) DEFAULT 0,
    OtherCharges DECIMAL(10,2) DEFAULT 0,
    Payments DECIMAL(10,2) DEFAULT 0,
    Balance DECIMAL(10,2) DEFAULT 0,

    -- Status and housekeeping
    StayStatus NVARCHAR(20) DEFAULT 'CheckedIn', -- CheckedIn, CheckedOut, Extended
    HousekeepingStatus NVARCHAR(20) DEFAULT 'Clean', -- Clean, Dirty, DoNotDisturb
    MaintenanceIssues NVARCHAR(MAX), -- JSON array of issues

    -- Guest services
    KeyCardNumber NVARCHAR(50),
    SafeCombination NVARCHAR(10),
    GuestRequests NVARCHAR(MAX), -- JSON array

    -- Constraints
    CONSTRAINT CK_GuestStays_Status CHECK (StayStatus IN ('CheckedIn', 'CheckedOut', 'Extended')),
    CONSTRAINT CK_GuestStays_Housekeeping CHECK (HousekeepingStatus IN ('Clean', 'Dirty', 'DoNotDisturb', 'OutOfOrder')),

    -- Indexes
    INDEX IX_GuestStays_Reservation (ReservationID),
    INDEX IX_GuestStays_Guest (GuestID),
    INDEX IX_GuestStays_Property (PropertyID),
    INDEX IX_GuestStays_Room (RoomID),
    INDEX IX_GuestStays_Status (StayStatus),
    INDEX IX_GuestStays_CheckIn (CheckInDate),
    INDEX IX_GuestStays_CheckOut (CheckOutDate)
);

-- Guest service requests
CREATE TABLE GuestServiceRequests (
    RequestID INT IDENTITY(1,1) PRIMARY KEY,
    StayID INT NOT NULL REFERENCES GuestStays(StayID),
    PropertyID INT NOT NULL REFERENCES Properties(PropertyID),

    -- Request details
    RequestType NVARCHAR(50) NOT NULL, -- Housekeeping, Maintenance, Concierge, FrontDesk
    Category NVARCHAR(50), -- Room Service, Amenities, Information, Transportation
    Subject NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Urgency and priority
    Urgency NVARCHAR(10) DEFAULT 'Normal', -- Low, Normal, High, Emergency
    Priority NVARCHAR(10) DEFAULT 'Normal',

    -- Processing
    Status NVARCHAR(20) DEFAULT 'Open', -- Open, Assigned, InProgress, Completed, Cancelled
    AssignedTo INT,
    AssignedDate DATETIME2,
    CompletedDate DATETIME2,
    Resolution NVARCHAR(MAX),

    -- Guest feedback
    SatisfactionRating INT CHECK (SatisfactionRating BETWEEN 1 AND 5),
    GuestComments NVARCHAR(MAX),

    -- Request metadata
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy NVARCHAR(100), -- Guest or staff
    Source NVARCHAR(20) DEFAULT 'Guest', -- Guest, Staff, System

    -- Constraints
    CONSTRAINT CK_GuestServiceRequests_Type CHECK (RequestType IN ('Housekeeping', 'Maintenance', 'Concierge', 'FrontDesk', 'Security', 'Valet')),
    CONSTRAINT CK_GuestServiceRequests_Urgency CHECK (Urgency IN ('Low', 'Normal', 'High', 'Emergency')),
    CONSTRAINT CK_GuestServiceRequests_Status CHECK (Status IN ('Open', 'Assigned', 'InProgress', 'Completed', 'Cancelled')),

    -- Indexes
    INDEX IX_GuestServiceRequests_Stay (StayID),
    INDEX IX_GuestServiceRequests_Property (PropertyID),
    INDEX IX_GuestServiceRequests_Type (RequestType),
    INDEX IX_GuestServiceRequests_Status (Status),
    INDEX IX_GuestServiceRequests_Urgency (Urgency),
    INDEX IX_GuestServiceRequests_Created (CreatedDate)
);

-- Housekeeping tasks
CREATE TABLE HousekeepingTasks (
    TaskID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyID INT NOT NULL REFERENCES Properties(PropertyID),
    RoomID INT NOT NULL REFERENCES Rooms(RoomID),

    -- Task details
    TaskType NVARCHAR(50) NOT NULL, -- DailyCleaning, DeepCleaning, Turndown, Maintenance
    TaskDescription NVARCHAR(MAX),
    Priority NVARCHAR(10) DEFAULT 'Normal',

    -- Scheduling
    ScheduledDate DATE,
    ScheduledTime TIME,
    DueTime TIME,
    AssignedTo INT, -- Housekeeper ID

    -- Status and completion
    Status NVARCHAR(20) DEFAULT 'Pending', -- Pending, InProgress, Completed, Cancelled
    StartedDateTime DATETIME2,
    CompletedDateTime DATETIME2,
    QualityRating INT CHECK (QualityRating BETWEEN 1 AND 5),

    -- Quality control
    SupervisorID INT,
    InspectionDateTime DATETIME2,
    InspectionNotes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_HousekeepingTasks_Type CHECK (TaskType IN ('DailyCleaning', 'DeepCleaning', 'Turndown', 'Maintenance', 'Setup')),
    CONSTRAINT CK_HousekeepingTasks_Status CHECK (Status IN ('Pending', 'InProgress', 'Completed', 'Cancelled', 'Inspected')),

    -- Indexes
    INDEX IX_HousekeepingTasks_Property (PropertyID),
    INDEX IX_HousekeepingTasks_Room (RoomID),
    INDEX IX_HousekeepingTasks_Type (TaskType),
    INDEX IX_HousekeepingTasks_Status (Status),
    INDEX IX_HousekeepingTasks_Scheduled (ScheduledDate, ScheduledTime),
    INDEX IX_HousekeepingTasks_Assigned (AssignedTo)
);

-- =============================================
-- REVENUE MANAGEMENT
-- =============================================

-- Rate codes
CREATE TABLE RateCodes (
    RateCodeID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyID INT NOT NULL REFERENCES Properties(PropertyID),
    RateCode NVARCHAR(50) NOT NULL,
    RateName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),

    -- Rate structure
    RateType NVARCHAR(20) DEFAULT 'Fixed', -- Fixed, Percentage, Formula
    BaseRate DECIMAL(10,2),
    RateFormula NVARCHAR(MAX), -- JSON formula definition

    -- Validity and restrictions
    StartDate DATE,
    EndDate DATE,
    MinStay INT DEFAULT 1,
    MaxStay INT,
    AdvanceBookingDays INT,

    -- Restrictions
    BlackoutDates NVARCHAR(MAX), -- JSON array of blackout dates
    MinimumRate DECIMAL(10,2),
    MaximumRate DECIMAL(10,2),

    -- Status and availability
    IsActive BIT DEFAULT 1,
    IsPublic BIT DEFAULT 1,
    SortOrder INT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_RateCodes_PropertyCode UNIQUE (PropertyID, RateCode),
    CONSTRAINT CK_RateCodes_Type CHECK (RateType IN ('Fixed', 'Percentage', 'Formula', 'Dynamic')),

    -- Indexes
    INDEX IX_RateCodes_Property (PropertyID),
    INDEX IX_RateCodes_Code (RateCode),
    INDEX IX_RateCodes_IsActive (IsActive),
    INDEX IX_RateCodes_StartDate (StartDate),
    INDEX IX_RateCodes_EndDate (EndDate)
);

-- Daily room rates
CREATE TABLE RoomRates (
    RateID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyID INT NOT NULL REFERENCES Properties(PropertyID),
    RoomTypeID INT NOT NULL REFERENCES RoomTypes(RoomTypeID),
    RateCodeID INT REFERENCES RateCodes(RateCodeID),

    -- Rate details
    RateDate DATE NOT NULL,
    BaseRate DECIMAL(10,2) NOT NULL,
    OverrideRate DECIMAL(10,2), -- Special rate override
    EffectiveRate AS (ISNULL(OverrideRate, BaseRate)),

    -- Availability and inventory
    AvailableRooms INT,
    BlockedRooms INT DEFAULT 0,
    SoldRooms INT DEFAULT 0,

    -- Rate restrictions
    MinStay INT DEFAULT 1,
    MaxStay INT,
    ClosedToArrival BIT DEFAULT 0,
    ClosedToDeparture BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_RoomRates_PropertyRoomDate UNIQUE (PropertyID, RoomTypeID, RateDate),

    -- Indexes
    INDEX IX_RoomRates_Property (PropertyID),
    INDEX IX_RoomRates_RoomType (RoomTypeID),
    INDEX IX_RoomRates_RateCode (RateCodeID),
    INDEX IX_RoomRates_Date (RateDate),
    INDEX IX_RoomRates_EffectiveRate (EffectiveRate)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Current occupancy view
CREATE VIEW vw_CurrentOccupancy
AS
SELECT
    p.PropertyID,
    p.PropertyName,
    p.TotalRooms,

    -- Current occupancy
    (SELECT COUNT(*) FROM GuestStays gs
     WHERE gs.PropertyID = p.PropertyID AND gs.StayStatus = 'CheckedIn') AS OccupiedRooms,

    (SELECT COUNT(*) FROM Rooms r
     WHERE r.PropertyID = p.PropertyID AND r.RoomStatus = 'Clean' AND r.HousekeepingStatus = 'Ready') AS AvailableRooms,

    -- Today's activity
    (SELECT COUNT(*) FROM Reservations res
     WHERE res.PropertyID = p.PropertyID AND res.ArrivalDate = CAST(GETDATE() AS DATE)
     AND res.ReservationStatus = 'Confirmed') AS ExpectedArrivals,

    (SELECT COUNT(*) FROM Reservations res
     WHERE res.PropertyID = p.PropertyID AND res.DepartureDate = CAST(GETDATE() AS DATE)
     AND res.ReservationStatus = 'CheckedIn') AS ExpectedDepartures,

    -- Occupancy percentage
    CASE
        WHEN p.TotalRooms > 0 THEN
            CAST((SELECT COUNT(*) FROM GuestStays gs
                  WHERE gs.PropertyID = p.PropertyID AND gs.StayStatus = 'CheckedIn') AS DECIMAL(5,2)) / p.TotalRooms * 100
        ELSE 0
    END AS OccupancyPercentage

FROM Properties p
WHERE p.IsActive = 1;
GO

-- Revenue summary view
CREATE VIEW vw_RevenueSummary
AS
SELECT
    p.PropertyID,
    p.PropertyName,

    -- Current month revenue
    (SELECT SUM(TotalAmount) FROM Reservations r
     WHERE r.PropertyID = p.PropertyID
     AND MONTH(r.ArrivalDate) = MONTH(GETDATE())
     AND YEAR(r.ArrivalDate) = YEAR(GETDATE())
     AND r.ReservationStatus NOT IN ('Cancelled', 'NoShow')) AS RoomRevenueThisMonth,

    (SELECT SUM(RoomCharges + FoodBeverage + OtherCharges) FROM GuestStays gs
     WHERE gs.PropertyID = p.PropertyID
     AND MONTH(gs.CheckInDate) = MONTH(GETDATE())
     AND YEAR(gs.CheckInDate) = YEAR(GETDATE())) AS TotalRevenueThisMonth,

    -- Average daily rate
    (SELECT AVG(EffectiveRate) FROM RoomRates rr
     WHERE rr.PropertyID = p.PropertyID
     AND MONTH(rr.RateDate) = MONTH(GETDATE())
     AND YEAR(rr.RateDate) = YEAR(GETDATE())) AS AverageDailyRate,

    -- Booking channels
    (SELECT COUNT(*) FROM Reservations r
     WHERE r.PropertyID = p.PropertyID
     AND MONTH(r.CreatedDate) = MONTH(GETDATE())
     AND YEAR(r.CreatedDate) = YEAR(GETDATE())
     AND r.BookingChannel = 'Direct') AS DirectBookings,

    (SELECT COUNT(*) FROM Reservations r
     WHERE r.PropertyID = p.PropertyID
     AND MONTH(r.CreatedDate) = MONTH(GETDATE())
     AND YEAR(r.CreatedDate) = YEAR(GETDATE())
     AND r.BookingChannel = 'OTA') AS OTABookings

FROM Properties p
WHERE p.IsActive = 1;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update guest stay status on check-out
CREATE TRIGGER TR_GuestStays_CheckOut
ON GuestStays
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Update room status when guest checks out
    UPDATE r
    SET r.RoomStatus = 'Dirty',
        r.HousekeepingStatus = 'Cleaning'
    FROM Rooms r
    INNER JOIN inserted i ON r.RoomID = i.RoomID
    WHERE i.StayStatus = 'CheckedOut' AND i.ActualCheckOutDate IS NOT NULL;
END;
GO

-- Update guest loyalty points
CREATE TRIGGER TR_GuestStays_UpdateLoyalty
ON GuestStays
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Add loyalty points for completed stays
    UPDATE g
    SET g.LoyaltyPoints = g.LoyaltyPoints + (i.Nights * 10), -- 10 points per night
        g.TotalStays = g.TotalStays + 1,
        g.TotalNights = g.TotalNights + i.Nights,
        g.TotalSpent = g.TotalSpent + i.RoomCharges,
        g.LastStayDate = i.CheckOutDate
    FROM Guests g
    INNER JOIN inserted i ON g.GuestID = i.GuestID
    WHERE i.StayStatus = 'CheckedOut' AND i.ActualCheckOutDate IS NOT NULL;
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Create reservation procedure
CREATE PROCEDURE sp_CreateReservation
    @PropertyID INT,
    @GuestID INT,
    @ArrivalDate DATE,
    @DepartureDate DATE,
    @Adults INT = 1,
    @Children INT = 0,
    @RoomTypeID INT = NULL,
    @BookingChannel NVARCHAR(50) = 'Direct'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReservationNumber NVARCHAR(50);
    DECLARE @Nights INT = DATEDIFF(DAY, @ArrivalDate, @DepartureDate);

    -- Generate reservation number
    SET @ReservationNumber = 'RES-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                           RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                           RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS NVARCHAR(6)), 6);

    -- Calculate basic rate (simplified - would use rate logic in production)
    DECLARE @RoomRate DECIMAL(10,2) = 150.00; -- Base rate
    DECLARE @Subtotal DECIMAL(10,2) = @RoomRate * @Nights;
    DECLARE @Taxes DECIMAL(10,2) = @Subtotal * 0.12; -- 12% tax
    DECLARE @Total DECIMAL(10,2) = @Subtotal + @Taxes;

    INSERT INTO Reservations (
        ReservationNumber, PropertyID, GuestID, ArrivalDate, DepartureDate,
        Nights, Adults, Children, RoomTypeID, RoomRate, Subtotal, Taxes,
        TotalAmount, BookingChannel
    )
    VALUES (
        @ReservationNumber, @PropertyID, @GuestID, @ArrivalDate, @DepartureDate,
        @Nights, @Adults, @Children, @RoomTypeID, @RoomRate, @Subtotal, @Taxes,
        @Total, @BookingChannel
    );

    SELECT SCOPE_IDENTITY() AS ReservationID, @ReservationNumber AS ReservationNumber;
END;
GO

-- Check-in guest procedure
CREATE PROCEDURE sp_CheckInGuest
    @ReservationID INT,
    @RoomID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    -- Update reservation status
    UPDATE Reservations
    SET ReservationStatus = 'CheckedIn',
        RoomID = @RoomID
    WHERE ReservationID = @ReservationID;

    -- Create guest stay record
    INSERT INTO GuestStays (
        ReservationID, GuestID, PropertyID, RoomID,
        CheckInDate, ExpectedDepartureDate, Nights,
        GuestName, GuestPhone, GuestEmail
    )
    SELECT
        r.ReservationID, r.GuestID, r.PropertyID, @RoomID,
        GETDATE(), r.DepartureDate, r.Nights,
        g.FirstName + ' ' + g.LastName, g.Phone, g.Email
    FROM Reservations r
    INNER JOIN Guests g ON r.GuestID = g.GuestID
    WHERE r.ReservationID = @ReservationID;

    -- Update room status
    UPDATE Rooms
    SET RoomStatus = 'Occupied',
        HousekeepingStatus = 'Occupied'
    WHERE RoomID = @RoomID;

    COMMIT TRANSACTION;

    SELECT SCOPE_IDENTITY() AS StayID;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample property
INSERT INTO Properties (PropertyCode, PropertyName, PropertyType, City, StarRating, TotalRooms) VALUES
('HTL-001', 'Grand Hotel', 'Hotel', 'New York', 4, 200);

-- Insert sample room type
INSERT INTO RoomTypes (PropertyID, RoomTypeCode, RoomTypeName, MaxOccupancy, BaseRate) VALUES
(1, 'STD', 'Standard Room', 2, 150.00);

-- Insert sample room
INSERT INTO Rooms (PropertyID, RoomTypeID, RoomNumber, FloorNumber) VALUES
(1, 1, '101', 1);

-- Insert sample guest
INSERT INTO Guests (GuestNumber, FirstName, LastName, Email) VALUES
('GST-000001', 'John', 'Smith', 'john.smith@email.com');

PRINT 'Hospitality database schema created successfully!';
GO
