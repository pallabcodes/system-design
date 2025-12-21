# Hospitality & Hotel Management Platform Database Design

## Overview

This comprehensive database schema supports modern hospitality and hotel management platforms including property management, reservation systems, guest services, revenue management, and enterprise hospitality operations. The design handles complex booking workflows, multi-property management, guest experience tracking, and hospitality industry compliance.

## Key Features

### 🏨 Property & Room Management
- **Multi-property portfolio management** with centralized administration and reporting
- **Dynamic room inventory** with availability tracking, maintenance scheduling, and housekeeping
- **Room configuration and amenities** with flexible room types, features, and pricing
- **Property facilities management** with spa, restaurant, conference, and recreational amenities

### 📅 Reservation & Booking Management
- **Comprehensive reservation system** with online booking, channel management, and rate structures
- **Dynamic pricing and yield management** with seasonal rates, promotional pricing, and demand forecasting
- **Group and event bookings** with complex requirements, billing, and coordination
- **Booking modifications and cancellations** with policies, fees, and guest communications

### 👥 Guest Experience & Services
- **Guest profile and preference management** with loyalty programs and personalized services
- **Guest services tracking** with requests, complaints, feedback, and satisfaction monitoring
- **Housekeeping and maintenance coordination** with room status, cleaning schedules, and quality control
- **Concierge and amenity services** with reservations, recommendations, and guest assistance

## Database Schema Highlights

### Core Tables

#### Property & Room Management
```sql
-- Hotel properties master table
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

-- Room types and configurations
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
```

#### Reservation & Booking Management
```sql
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

-- Reservations master table
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
```

#### Guest Services & Operations
```sql
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
```

### Revenue Management & Analytics

#### Rate Management
```sql
-- Rate codes and structures
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
```

## Integration Points

### External Systems
- **Online Travel Agencies**: Booking.com, Expedia, TripAdvisor integration
- **Global Distribution Systems**: Amadeus, Sabre, Travelport connectivity
- **Payment Processors**: Stripe, PayPal, Adyen for secure transactions
- **Property Management Systems**: Opera, Amadeus PMS integration
- **Channel Managers**: Rate synchronization across booking platforms
- **Loyalty Programs**: Integration with airline and hotel loyalty systems

### API Endpoints
- **Booking APIs**: Availability search, reservation creation, modification
- **Property APIs**: Rate management, inventory updates, content management
- **Guest APIs**: Profile management, preferences, loyalty program integration
- **Operations APIs**: Housekeeping tasks, maintenance requests, service tracking
- **Analytics APIs**: Revenue management, occupancy reports, guest satisfaction

## Monitoring & Analytics

### Key Performance Indicators
- **Revenue Management**: Average daily rate, revenue per available room, occupancy rates
- **Guest Experience**: Net Promoter Score, guest satisfaction ratings, review scores
- **Operational Efficiency**: Housekeeping productivity, maintenance response times, booking conversion rates
- **Channel Performance**: Online travel agency commissions, direct booking rates, market share
- **Financial Performance**: Gross operating profit, labor cost percentage, food and beverage revenue

### Real-Time Dashboards
```sql
-- Hospitality operations dashboard
CREATE VIEW HospitalityOperationsDashboard AS
SELECT
    -- Occupancy and availability metrics (current state)
    (SELECT COUNT(*) FROM Rooms WHERE RoomStatus = 'Clean' AND HousekeepingStatus = 'Ready') AS AvailableRooms,
    (SELECT COUNT(*) FROM Rooms WHERE RoomStatus IN ('Occupied', 'Dirty')) AS OccupiedRooms,
    (SELECT CAST(AVG(EffectiveRate) AS DECIMAL(10,2)) FROM RoomRates
     WHERE RateDate = CAST(GETDATE() AS DATE)) AS AverageDailyRate,
    (SELECT CAST(AVG(CAST(EffectiveRate AS DECIMAL(10,2))) AS DECIMAL(10,2)) FROM RoomRates
     WHERE RateDate >= DATEADD(DAY, -30, GETDATE())) AS AverageMonthlyRate,

    -- Booking and reservation metrics (current month)
    (SELECT COUNT(*) FROM Reservations
     WHERE MONTH(ArrivalDate) = MONTH(GETDATE())
     AND YEAR(ArrivalDate) = YEAR(GETDATE())) AS BookingsThisMonth,

    (SELECT COUNT(*) FROM Reservations
     WHERE ArrivalDate = CAST(GETDATE() AS DATE)
     AND ReservationStatus = 'Confirmed') AS ArrivalsToday,

    (SELECT COUNT(*) FROM Reservations
     WHERE DepartureDate = CAST(GETDATE() AS DATE)
     AND ReservationStatus = 'CheckedIn') AS DeparturesToday,

    (SELECT SUM(TotalAmount) FROM Reservations
     WHERE MONTH(ArrivalDate) = MONTH(GETDATE())
     AND YEAR(ArrivalDate) = YEAR(GETDATE())
     AND ReservationStatus NOT IN ('Cancelled', 'NoShow')) AS RevenueThisMonth,

    -- Guest service metrics
    (SELECT COUNT(*) FROM GuestServiceRequests
     WHERE Status = 'Open') AS OpenServiceRequests,

    (SELECT COUNT(*) FROM GuestServiceRequests
     WHERE MONTH(CreatedDate) = MONTH(GETDATE())
     AND YEAR(CreatedDate) = YEAR(GETDATE())) AS ServiceRequestsThisMonth,

    (SELECT AVG(CAST(SatisfactionRating AS DECIMAL(3,2))) FROM GuestServiceRequests
     WHERE SatisfactionRating IS NOT NULL
     AND MONTH(CompletedDate) = MONTH(GETDATE())) AS AvgServiceSatisfaction,

    -- Housekeeping performance
    (SELECT COUNT(*) FROM HousekeepingTasks
     WHERE Status = 'Completed'
     AND CAST(CompletedDateTime AS DATE) = CAST(GETDATE() AS DATE)) AS HousekeepingTasksCompletedToday,

    (SELECT COUNT(*) FROM HousekeepingTasks
     WHERE Status IN ('Pending', 'InProgress')
     AND ScheduledDate = CAST(GETDATE() AS DATE)) AS OutstandingHousekeepingTasks,

    (SELECT AVG(CAST(QualityRating AS DECIMAL(3,2))) FROM HousekeepingTasks
     WHERE QualityRating IS NOT NULL
     AND MONTH(CompletedDateTime) = MONTH(GETDATE())) AS AvgHousekeepingQuality,

    -- Guest experience metrics
    (SELECT COUNT(*) FROM GuestStays
     WHERE CheckOutDate IS NULL) AS CurrentGuests,

    (SELECT COUNT(*) FROM Guests
     WHERE LoyaltyTier = 'VIP') AS VIPGuests,

    (SELECT AVG(CAST(LoyaltyPoints AS DECIMAL(10,2))) FROM Guests
     WHERE LoyaltyPoints > 0) AS AvgLoyaltyPoints,

    -- Channel performance (current month)
    (SELECT COUNT(*) FROM Reservations
     WHERE BookingChannel = 'Direct'
     AND MONTH(CreatedDate) = MONTH(GETDATE())) AS DirectBookingsThisMonth,

    (SELECT COUNT(*) FROM Reservations
     WHERE BookingChannel = 'OTA'
     AND MONTH(CreatedDate) = MONTH(GETDATE())) AS OTABookingsThisMonth

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This hospitality database schema provides a comprehensive foundation for modern hotel management platforms, supporting property operations, guest services, revenue management, and enterprise hospitality analytics while maintaining high performance and operational efficiency.
