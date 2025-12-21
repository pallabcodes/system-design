-- Travel & Tourism Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE TravelDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE TravelDB;
GO

-- Configure database for travel performance
ALTER DATABASE TravelDB
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
-- SUPPLIER & PRODUCT MANAGEMENT
-- =============================================

-- Travel suppliers
CREATE TABLE Suppliers (
    SupplierID INT IDENTITY(1,1) PRIMARY KEY,
    SupplierCode NVARCHAR(20) UNIQUE NOT NULL,
    SupplierName NVARCHAR(200) NOT NULL,
    SupplierType NVARCHAR(50) NOT NULL, -- Airline, Hotel, TourOperator, CarRental, Rail, Bus

    -- Contact information
    ContactPerson NVARCHAR(100),
    Phone NVARCHAR(20),
    Email NVARCHAR(255),
    Website NVARCHAR(500),
    Address NVARCHAR(MAX), -- JSON formatted

    -- Business relationship
    ContractStartDate DATETIME2,
    ContractEndDate DATETIME2,
    CommissionRate DECIMAL(5,4), -- 0.0000 to 1.0000
    PaymentTerms NVARCHAR(100),
    CreditLimit DECIMAL(12,2),

    -- Performance
    Rating DECIMAL(3,2) CHECK (Rating BETWEEN 1.00 AND 5.00),
    IsPreferred BIT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    -- Operational details
    BookingLeadTime INT, -- Hours/days required for booking
    CancellationPolicy NVARCHAR(MAX), -- JSON formatted
    SupportedCurrencies NVARCHAR(MAX), -- JSON array

    -- Constraints
    CONSTRAINT CK_Suppliers_Type CHECK (SupplierType IN ('Airline', 'Hotel', 'TourOperator', 'CarRental', 'Rail', 'Bus', 'Ferry', 'Cruise', 'Activity', 'Transfer')),

    -- Indexes
    INDEX IX_Suppliers_Code (SupplierCode),
    INDEX IX_Suppliers_Type (SupplierType),
    INDEX IX_Suppliers_IsActive (IsActive),
    INDEX IX_Suppliers_IsPreferred (IsPreferred)
);

-- Travel products
CREATE TABLE TravelProducts (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductCode NVARCHAR(50) UNIQUE NOT NULL,
    ProductName NVARCHAR(200) NOT NULL,
    ProductType NVARCHAR(50) NOT NULL, -- Flight, Hotel, Tour, CarRental, Activity
    SupplierID INT NOT NULL REFERENCES Suppliers(SupplierID),

    -- Product details
    Description NVARCHAR(MAX),
    Category NVARCHAR(100), -- Economy, Business, Luxury, Adventure, etc.
    Location NVARCHAR(200), -- City, region, or specific location
    Duration NVARCHAR(50), -- For tours: 3 days, 1 week, etc.

    -- Pricing
    BasePrice DECIMAL(10,2),
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',
    MinimumPrice DECIMAL(10,2),
    MaximumPrice DECIMAL(10,2),

    -- Availability
    IsAvailable BIT DEFAULT 1,
    BookingLeadTime INT DEFAULT 0, -- Hours required for booking
    CancellationPolicy NVARCHAR(MAX), -- JSON formatted

    -- Specifications (JSON based on type)
    Specifications NVARCHAR(MAX), -- Flight: airline, aircraft; Hotel: stars, amenities; etc.

    -- Marketing content
    Images NVARCHAR(MAX), -- JSON array of image URLs
    Highlights NVARCHAR(MAX), -- JSON array of key features
    IncludedServices NVARCHAR(MAX), -- JSON array of what's included

    -- Status
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastUpdatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_TravelProducts_Type CHECK (ProductType IN ('Flight', 'Hotel', 'Tour', 'CarRental', 'Activity', 'Transfer', 'Cruise', 'Rail', 'Bus', 'Ferry')),

    -- Indexes
    INDEX IX_TravelProducts_Code (ProductCode),
    INDEX IX_TravelProducts_Type (ProductType),
    INDEX IX_TravelProducts_Supplier (SupplierID),
    INDEX IX_TravelProducts_Category (Category),
    INDEX IX_TravelProducts_IsActive (IsActive),
    INDEX IX_TravelProducts_Location (Location)
);

-- =============================================
-- FLIGHT MANAGEMENT
-- =============================================

-- Flight schedules
CREATE TABLE FlightSchedules (
    ScheduleID INT IDENTITY(1,1) PRIMARY KEY,
    FlightNumber NVARCHAR(20) NOT NULL,
    AirlineID INT NOT NULL REFERENCES Suppliers(SupplierID),
    AircraftType NVARCHAR(50),

    -- Route
    OriginAirport NVARCHAR(10) NOT NULL, -- IATA code
    DestinationAirport NVARCHAR(10) NOT NULL,
    Distance INT, -- Nautical miles

    -- Schedule
    DepartureTime TIME NOT NULL,
    ArrivalTime TIME NOT NULL,
    FlightDuration INT, -- Minutes
    TimeZone NVARCHAR(50),

    -- Operations
    DaysOfOperation NVARCHAR(7), -- 1234567 (1=Monday, 7=Sunday)
    IsActive BIT DEFAULT 1,
    EffectiveStartDate DATE,
    EffectiveEndDate DATE,

    -- Capacity
    TotalSeats INT,
    EconomySeats INT,
    BusinessSeats INT,
    FirstClassSeats INT,

    -- Constraints
    CONSTRAINT CK_FlightSchedules_Days CHECK (LEN(DaysOfOperation) <= 7),
    CONSTRAINT UQ_FlightSchedules_Flight UNIQUE (FlightNumber, EffectiveStartDate),

    -- Indexes
    INDEX IX_FlightSchedules_Flight (FlightNumber),
    INDEX IX_FlightSchedules_Route (OriginAirport, DestinationAirport),
    INDEX IX_FlightSchedules_Airline (AirlineID),
    INDEX IX_FlightSchedules_IsActive (IsActive)
);

-- Flight instances
CREATE TABLE FlightInstances (
    InstanceID INT IDENTITY(1,1) PRIMARY KEY,
    ScheduleID INT NOT NULL REFERENCES FlightSchedules(ScheduleID),
    FlightDate DATE NOT NULL,
    FlightNumber NVARCHAR(20) NOT NULL,

    -- Flight times
    DepartureTime DATETIME2 NOT NULL,
    ArrivalTime DATETIME2 NOT NULL,
    ActualDepartureTime DATETIME2,
    ActualArrivalTime DATETIME2,

    -- Aircraft and crew
    AircraftRegistration NVARCHAR(20),
    Captain NVARCHAR(100),
    FirstOfficer NVARCHAR(100),

    -- Status
    Status NVARCHAR(20) DEFAULT 'Scheduled', -- Scheduled, Boarding, Departed, Arrived, Cancelled, Delayed
    DelayMinutes INT DEFAULT 0,
    DelayReason NVARCHAR(MAX),

    -- Load
    TotalSeats INT,
    AvailableSeats INT,
    BookedSeats INT,

    -- Constraints
    CONSTRAINT CK_FlightInstances_Status CHECK (Status IN ('Scheduled', 'Boarding', 'Departed', 'Arrived', 'Cancelled', 'Delayed')),
    CONSTRAINT UQ_FlightInstances_ScheduleDate UNIQUE (ScheduleID, FlightDate),

    -- Indexes
    INDEX IX_FlightInstances_Schedule (ScheduleID),
    INDEX IX_FlightInstances_Date (FlightDate),
    INDEX IX_FlightInstances_Status (Status),
    INDEX IX_FlightInstances_FlightNumber (FlightNumber, FlightDate)
);

-- Flight fares
CREATE TABLE FlightFares (
    FareID INT IDENTITY(1,1) PRIMARY KEY,
    ScheduleID INT NOT NULL REFERENCES FlightSchedules(ScheduleID),
    FareBasisCode NVARCHAR(20) NOT NULL,
    FareClass NVARCHAR(10) NOT NULL, -- Y, J, F, etc.

    -- Pricing
    BaseFare DECIMAL(10,2) NOT NULL,
    Taxes DECIMAL(10,2) DEFAULT 0,
    TotalFare DECIMAL(10,2) NOT NULL,

    -- Availability
    AvailableSeats INT,
    MinimumStay INT, -- Days
    MaximumStay INT, -- Days
    AdvancePurchase INT, -- Days required

    -- Policies
    CancellationPolicy NVARCHAR(MAX), -- JSON formatted
    ChangePolicy NVARCHAR(MAX), -- JSON formatted
    BaggageAllowance NVARCHAR(MAX), -- JSON formatted

    -- Validity
    EffectiveDate DATE,
    DiscontinueDate DATE,
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_FlightFares_Class CHECK (FareClass IN ('Y', 'B', 'H', 'K', 'L', 'M', 'N', 'Q', 'V', 'W', 'S', 'T', 'O', 'I', 'X', 'J', 'C', 'D', 'I', 'Z', 'F', 'A', 'P')),

    -- Indexes
    INDEX IX_FlightFares_Schedule (ScheduleID),
    INDEX IX_FlightFares_Class (FareClass),
    INDEX IX_FlightFares_IsActive (IsActive)
);

-- =============================================
-- HOTEL MANAGEMENT
-- =============================================

-- Hotel properties
CREATE TABLE HotelProperties (
    PropertyID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyCode NVARCHAR(20) UNIQUE NOT NULL,
    PropertyName NVARCHAR(200) NOT NULL,
    SupplierID INT NOT NULL REFERENCES Suppliers(SupplierID),

    -- Location
    Address NVARCHAR(MAX), -- JSON formatted
    City NVARCHAR(100),
    Country NVARCHAR(100),
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),

    -- Property info
    StarRating INT CHECK (StarRating BETWEEN 1 AND 5),
    TotalRooms INT,
    PropertyType NVARCHAR(50), -- Hotel, Resort, Apartment, Villa, etc.
    CheckInTime TIME DEFAULT '15:00',
    CheckOutTime TIME DEFAULT '11:00',

    -- Amenities
    Amenities NVARCHAR(MAX), -- JSON array
    Policies NVARCHAR(MAX), -- JSON object

    -- Status
    IsActive BIT DEFAULT 1,
    LastUpdated DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_HotelProperties_Type CHECK (PropertyType IN ('Hotel', 'Resort', 'Apartment', 'Villa', 'Hostel', 'Boutique', 'Business', 'Airport')),

    -- Indexes
    INDEX IX_HotelProperties_Code (PropertyCode),
    INDEX IX_HotelProperties_Supplier (SupplierID),
    INDEX IX_HotelProperties_City (City),
    INDEX IX_HotelProperties_IsActive (IsActive)
);

-- Hotel room types
CREATE TABLE HotelRoomTypes (
    RoomTypeID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyID INT NOT NULL REFERENCES HotelProperties(PropertyID),
    RoomTypeCode NVARCHAR(20) NOT NULL,
    RoomTypeName NVARCHAR(100) NOT NULL,

    -- Specifications
    MaxOccupancy INT NOT NULL,
    BedConfiguration NVARCHAR(100),
    RoomSize DECIMAL(8,2), -- Square meters
    BathroomType NVARCHAR(50),

    -- Amenities
    Amenities NVARCHAR(MAX), -- JSON array
    ViewType NVARCHAR(50),

    -- Inventory
    TotalRooms INT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT UQ_HotelRoomTypes_PropertyCode UNIQUE (PropertyID, RoomTypeCode),
    CONSTRAINT CK_HotelRoomTypes_Occupancy CHECK (MaxOccupancy BETWEEN 1 AND 10),

    -- Indexes
    INDEX IX_HotelRoomTypes_Property (PropertyID),
    INDEX IX_HotelRoomTypes_IsActive (IsActive)
);

-- Hotel rates
CREATE TABLE HotelRates (
    RateID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyID INT NOT NULL REFERENCES HotelProperties(PropertyID),
    RoomTypeID INT NOT NULL REFERENCES HotelRoomTypes(RoomTypeID),

    -- Rate details
    RateDate DATE NOT NULL,
    RateCode NVARCHAR(50),
    BaseRate DECIMAL(10,2) NOT NULL,
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Availability
    AvailableRooms INT,
    MinimumStay INT DEFAULT 1,
    MaximumStay INT,

    -- Restrictions
    ClosedToArrival BIT DEFAULT 0,
    ClosedToDeparture BIT DEFAULT 0,
    RateRestrictions NVARCHAR(MAX), -- JSON formatted

    -- Constraints
    CONSTRAINT UQ_HotelRates_PropertyRoomDate UNIQUE (PropertyID, RoomTypeID, RateDate),

    -- Indexes
    INDEX IX_HotelRates_Property (PropertyID),
    INDEX IX_HotelRates_RoomType (RoomTypeID),
    INDEX IX_HotelRates_Date (RateDate),
    INDEX IX_HotelRates_Available (AvailableRooms)
);

-- =============================================
-- TOUR MANAGEMENT
-- =============================================

-- Tour packages
CREATE TABLE TourPackages (
    PackageID INT IDENTITY(1,1) PRIMARY KEY,
    PackageCode NVARCHAR(20) UNIQUE NOT NULL,
    PackageName NVARCHAR(200) NOT NULL,
    SupplierID INT REFERENCES Suppliers(SupplierID),

    -- Details
    Description NVARCHAR(MAX),
    Category NVARCHAR(50), -- Adventure, Cultural, Beach, City, Nature, etc.
    Duration INT, -- Days
    MinParticipants INT DEFAULT 1,
    MaxParticipants INT,

    -- Itinerary
    Destinations NVARCHAR(MAX), -- JSON array
    Activities NVARCHAR(MAX), -- JSON array
    IncludedServices NVARCHAR(MAX), -- JSON array

    -- Pricing
    BasePrice DECIMAL(10,2) NOT NULL,
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',
    PricePerPerson BIT DEFAULT 1,

    -- Availability
    IsActive BIT DEFAULT 1,
    BookingLeadTime INT DEFAULT 0, -- Days required
    CancellationPolicy NVARCHAR(MAX), -- JSON formatted

    -- Marketing
    Images NVARCHAR(MAX), -- JSON array
    Highlights NVARCHAR(MAX), -- JSON array
    Difficulty NVARCHAR(20), -- Easy, Moderate, Challenging, Extreme

    -- Constraints
    CONSTRAINT CK_TourPackages_Category CHECK (Category IN ('Adventure', 'Cultural', 'Beach', 'City', 'Nature', 'Luxury', 'Budget', 'Family', 'Romantic', 'Business')),
    CONSTRAINT CK_TourPackages_Difficulty CHECK (Difficulty IN ('Easy', 'Moderate', 'Challenging', 'Extreme')),

    -- Indexes
    INDEX IX_TourPackages_Code (PackageCode),
    INDEX IX_TourPackages_Category (Category),
    INDEX IX_TourPackages_IsActive (IsActive),
    INDEX IX_TourPackages_Duration (Duration)
);

-- Tour departures
CREATE TABLE TourDepartures (
    DepartureID INT IDENTITY(1,1) PRIMARY KEY,
    PackageID INT NOT NULL REFERENCES TourPackages(PackageID),
    DepartureDate DATE NOT NULL,
    ReturnDate DATE,

    -- Capacity
    TotalCapacity INT NOT NULL,
    AvailableSeats INT NOT NULL,
    MinimumParticipants INT DEFAULT 1,

    -- Pricing
    BasePrice DECIMAL(10,2),
    SingleSupplement DECIMAL(10,2), -- For solo travelers
    ChildDiscount DECIMAL(5,4), -- 0.0000 to 1.0000

    -- Status
    Status NVARCHAR(20) DEFAULT 'Available', -- Available, Guaranteed, Closed, Cancelled
    BookingCutoff DATE,

    -- Constraints
    CONSTRAINT CK_TourDepartures_Status CHECK (Status IN ('Available', 'Guaranteed', 'Closed', 'Cancelled', 'Full')),
    CONSTRAINT CK_TourDepartures_Capacity CHECK (AvailableSeats <= TotalCapacity),

    -- Indexes
    INDEX IX_TourDepartures_Package (PackageID),
    INDEX IX_TourDepartures_Date (DepartureDate),
    INDEX IX_TourDepartures_Status (Status),
    INDEX IX_TourDepartures_Available (AvailableSeats)
);

-- =============================================
-- CUSTOMER & BOOKING MANAGEMENT
-- =============================================

-- Travel customers
CREATE TABLE TravelCustomers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNumber NVARCHAR(20) UNIQUE NOT NULL,

    -- Personal info
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    Phone NVARCHAR(20),
    DateOfBirth DATE,

    -- Travel documents
    PassportNumber NVARCHAR(20),
    PassportExpiry DATE,
    PassportCountry NVARCHAR(100),
    NationalID NVARCHAR(50),

    -- Preferences
    PreferredAirline NVARCHAR(100),
    PreferredSeat NVARCHAR(20), -- Window, Aisle, Middle
    DietaryRestrictions NVARCHAR(MAX), -- JSON array
    AccessibilityNeeds NVARCHAR(MAX), -- JSON array

    -- Loyalty
    LoyaltyProgram NVARCHAR(100),
    LoyaltyNumber NVARCHAR(50),
    MembershipLevel NVARCHAR(20) DEFAULT 'Standard', -- Standard, Gold, Platinum

    -- History
    TotalBookings INT DEFAULT 0,
    TotalSpent DECIMAL(12,2) DEFAULT 0,
    LastBookingDate DATETIME2,

    -- Marketing
    EmailOptIn BIT DEFAULT 1,
    SmsOptIn BIT DEFAULT 0,

    -- Status
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_TravelCustomers_Level CHECK (MembershipLevel IN ('Standard', 'Gold', 'Platinum', 'VIP')),

    -- Indexes
    INDEX IX_TravelCustomers_Number (CustomerNumber),
    INDEX IX_TravelCustomers_Email (Email),
    INDEX IX_TravelCustomers_Name (LastName, FirstName),
    INDEX IX_TravelCustomers_IsActive (IsActive)
);

-- Travel bookings
CREATE TABLE TravelBookings (
    BookingID INT IDENTITY(1,1) PRIMARY KEY,
    BookingNumber NVARCHAR(50) UNIQUE NOT NULL,
    CustomerID INT NOT NULL REFERENCES TravelCustomers(CustomerID),

    -- Booking details
    BookingType NVARCHAR(20) DEFAULT 'Individual', -- Individual, Group, Corporate, Family
    BookingChannel NVARCHAR(50) DEFAULT 'Direct', -- Direct, OTA, Agency, Corporate
    BookingReference NVARCHAR(100),

    -- Travel dates
    DepartureDate DATE,
    ReturnDate DATE,
    BookingDate DATETIME2 DEFAULT GETDATE(),

    -- Financial
    Subtotal DECIMAL(12,2) NOT NULL,
    Taxes DECIMAL(10,2) DEFAULT 0,
    Fees DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(12,2) NOT NULL,
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Status
    PaymentStatus NVARCHAR(20) DEFAULT 'Pending', -- Pending, Paid, Refunded, Cancelled
    BookingStatus NVARCHAR(20) DEFAULT 'Confirmed', -- Tentative, Confirmed, Cancelled, Completed
    ConfirmationNumber NVARCHAR(50),

    -- Travel details
    Origin NVARCHAR(100),
    Destination NVARCHAR(100),
    Travelers INT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_TravelBookings_Type CHECK (BookingType IN ('Individual', 'Group', 'Corporate', 'Family')),
    CONSTRAINT CK_TravelBookings_Channel CHECK (BookingChannel IN ('Direct', 'OTA', 'Agency', 'Corporate', 'Mobile', 'CallCenter')),
    CONSTRAINT CK_TravelBookings_PaymentStatus CHECK (PaymentStatus IN ('Pending', 'Paid', 'Partial', 'Refunded', 'Cancelled')),
    CONSTRAINT CK_TravelBookings_Status CHECK (BookingStatus IN ('Tentative', 'Confirmed', 'Modified', 'Cancelled', 'Completed', 'NoShow')),

    -- Indexes
    INDEX IX_TravelBookings_Number (BookingNumber),
    INDEX IX_TravelBookings_Customer (CustomerID),
    INDEX IX_TravelBookings_Type (BookingType),
    INDEX IX_TravelBookings_Status (BookingStatus),
    INDEX IX_TravelBookings_PaymentStatus (PaymentStatus),
    INDEX IX_TravelBookings_Departure (DepartureDate),
    INDEX IX_TravelBookings_Return (ReturnDate),
    INDEX IX_TravelBookings_BookingDate (BookingDate)
);

-- Booking segments
CREATE TABLE BookingSegments (
    SegmentID INT IDENTITY(1,1) PRIMARY KEY,
    BookingID INT NOT NULL REFERENCES TravelBookings(BookingID) ON DELETE CASCADE,
    SegmentType NVARCHAR(20) NOT NULL, -- Flight, Hotel, Car, Tour, Activity
    SegmentOrder INT NOT NULL,

    -- Product and supplier
    ProductID INT REFERENCES TravelProducts(ProductID),
    SupplierID INT REFERENCES Suppliers(SupplierID),

    -- Segment details
    StartDate DATETIME2 NOT NULL,
    EndDate DATETIME2,
    Location NVARCHAR(200),
    Description NVARCHAR(MAX),

    -- Pricing
    BasePrice DECIMAL(10,2) NOT NULL,
    Taxes DECIMAL(10,2) DEFAULT 0,
    TotalPrice DECIMAL(10,2) NOT NULL,

    -- Status and booking reference
    Status NVARCHAR(20) DEFAULT 'Confirmed', -- Confirmed, Cancelled, Modified, Pending
    SupplierBookingRef NVARCHAR(100),
    ConfirmationNumber NVARCHAR(100),

    -- Traveler assignment
    TravelerName NVARCHAR(200),
    TravelerDetails NVARCHAR(MAX), -- JSON with passport, preferences, etc.

    -- Constraints
    CONSTRAINT CK_BookingSegments_Type CHECK (SegmentType IN ('Flight', 'Hotel', 'CarRental', 'Tour', 'Activity', 'Transfer', 'Rail', 'Bus', 'Cruise')),
    CONSTRAINT CK_BookingSegments_Status CHECK (Status IN ('Confirmed', 'Pending', 'Cancelled', 'Modified', 'Completed')),

    -- Indexes
    INDEX IX_BookingSegments_Booking (BookingID),
    INDEX IX_BookingSegments_Type (SegmentType),
    INDEX IX_BookingSegments_Order (BookingID, SegmentOrder),
    INDEX IX_BookingSegments_Status (Status),
    INDEX IX_BookingSegments_StartDate (StartDate)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Booking summary view
CREATE VIEW vw_BookingSummary
AS
SELECT
    tb.BookingID,
    tb.BookingNumber,
    tb.BookingDate,
    tc.FirstName + ' ' + tc.LastName AS CustomerName,
    tb.BookingType,
    tb.BookingChannel,
    tb.TotalAmount,
    tb.BookingStatus,
    tb.PaymentStatus,

    -- Travel dates
    tb.DepartureDate,
    tb.ReturnDate,
    DATEDIFF(DAY, tb.DepartureDate, tb.ReturnDate) AS TripDuration,

    -- Segment count
    (SELECT COUNT(*) FROM BookingSegments bs WHERE bs.BookingID = tb.BookingID) AS SegmentCount,

    -- Flight segments
    (SELECT COUNT(*) FROM BookingSegments bs WHERE bs.BookingID = tb.BookingID AND bs.SegmentType = 'Flight') AS FlightSegments,

    -- Hotel segments
    (SELECT COUNT(*) FROM BookingSegments bs WHERE bs.BookingID = tb.BookingID AND bs.SegmentType = 'Hotel') AS HotelSegments

FROM TravelBookings tb
INNER JOIN TravelCustomers tc ON tb.CustomerID = tc.CustomerID
WHERE tb.BookingStatus != 'Cancelled';
GO

-- Revenue summary view
CREATE VIEW vw_RevenueSummary
AS
SELECT
    DATEPART(YEAR, BookingDate) AS Year,
    DATEPART(MONTH, BookingDate) AS Month,

    -- Booking counts
    COUNT(*) AS TotalBookings,
    SUM(CASE WHEN BookingStatus = 'Completed' THEN 1 ELSE 0 END) AS CompletedBookings,
    SUM(CASE WHEN BookingStatus = 'Cancelled' THEN 1 ELSE 0 END) AS CancelledBookings,

    -- Revenue
    SUM(TotalAmount) AS TotalRevenue,
    SUM(CASE WHEN PaymentStatus = 'Paid' THEN TotalAmount ELSE 0 END) AS PaidRevenue,
    SUM(CASE WHEN PaymentStatus = 'Refunded' THEN TotalAmount ELSE 0 END) AS RefundedRevenue,

    -- Average values
    AVG(TotalAmount) AS AverageBookingValue,
    AVG(Travelers) AS AverageTravelers,

    -- Channel performance
    SUM(CASE WHEN BookingChannel = 'Direct' THEN TotalAmount ELSE 0 END) AS DirectRevenue,
    SUM(CASE WHEN BookingChannel = 'OTA' THEN TotalAmount ELSE 0 END) AS OTARevenue

FROM TravelBookings
WHERE BookingDate >= DATEADD(YEAR, -1, GETDATE())
GROUP BY DATEPART(YEAR, BookingDate), DATEPART(MONTH, BookingDate)
ORDER BY Year DESC, Month DESC;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update customer booking history
CREATE TRIGGER TR_TravelBookings_UpdateCustomer
ON TravelBookings
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Update customer totals
    UPDATE tc
    SET tc.TotalBookings = (
            SELECT COUNT(*) FROM TravelBookings tb
            WHERE tb.CustomerID = tc.CustomerID AND tb.BookingStatus != 'Cancelled'
        ),
        tc.TotalSpent = (
            SELECT SUM(TotalAmount) FROM TravelBookings tb
            WHERE tb.CustomerID = tc.CustomerID AND tb.PaymentStatus = 'Paid'
        ),
        tc.LastBookingDate = (
            SELECT MAX(BookingDate) FROM TravelBookings tb
            WHERE tb.CustomerID = tc.CustomerID
        )
    FROM TravelCustomers tc
    INNER JOIN inserted i ON tc.CustomerID = i.CustomerID;
END;
GO

-- Update flight availability
CREATE TRIGGER TR_BookingSegments_UpdateFlightAvailability
ON BookingSegments
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Update flight instance availability (simplified)
    UPDATE fi
    SET fi.AvailableSeats = fi.TotalSeats - (
        SELECT COUNT(*) FROM BookingSegments bs
        INNER JOIN TravelBookings tb ON bs.BookingID = tb.BookingID
        WHERE bs.ProductID IN (
            SELECT ProductID FROM TravelProducts
            WHERE ProductType = 'Flight' AND Specifications LIKE '%' + fi.FlightNumber + '%'
        ) AND tb.BookingStatus = 'Confirmed'
    )
    FROM FlightInstances fi
    WHERE EXISTS (
        SELECT 1 FROM inserted i
        WHERE i.ProductID IN (
            SELECT ProductID FROM TravelProducts
            WHERE ProductType = 'Flight' AND Specifications LIKE '%' + fi.FlightNumber + '%'
        )
    );
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Search flights procedure
CREATE PROCEDURE sp_SearchFlights
    @Origin NVARCHAR(10),
    @Destination NVARCHAR(10),
    @DepartureDate DATE,
    @ReturnDate DATE = NULL,
    @Passengers INT = 1,
    @CabinClass NVARCHAR(20) = 'Economy'
AS
BEGIN
    SET NOCOUNT ON;

    -- Search outbound flights
    SELECT
        fi.FlightNumber,
        fs.OriginAirport,
        fs.DestinationAirport,
        fi.DepartureTime,
        fi.ArrivalTime,
        fi.FlightDuration,
        ff.TotalFare,
        ff.FareClass,
        fi.AvailableSeats
    FROM FlightInstances fi
    INNER JOIN FlightSchedules fs ON fi.ScheduleID = fs.ScheduleID
    INNER JOIN FlightFares ff ON fs.ScheduleID = ff.ScheduleID
    WHERE fs.OriginAirport = @Origin
    AND fs.DestinationAirport = @Destination
    AND CAST(fi.DepartureTime AS DATE) = @DepartureDate
    AND fi.Status = 'Scheduled'
    AND fi.AvailableSeats >= @Passengers
    AND ff.FareClass = CASE
        WHEN @CabinClass = 'Economy' THEN 'Y'
        WHEN @CabinClass = 'Business' THEN 'J'
        WHEN @CabinClass = 'First' THEN 'F'
        ELSE 'Y'
    END
    AND ff.IsActive = 1;

    -- Search return flights if specified
    IF @ReturnDate IS NOT NULL
    BEGIN
        SELECT
            fi.FlightNumber,
            fs.OriginAirport,
            fs.DestinationAirport,
            fi.DepartureTime,
            fi.ArrivalTime,
            fi.FlightDuration,
            ff.TotalFare,
            ff.FareClass,
            fi.AvailableSeats
        FROM FlightInstances fi
        INNER JOIN FlightSchedules fs ON fi.ScheduleID = fs.ScheduleID
        INNER JOIN FlightFares ff ON fs.ScheduleID = ff.ScheduleID
        WHERE fs.OriginAirport = @Destination
        AND fs.DestinationAirport = @Origin
        AND CAST(fi.DepartureTime AS DATE) = @ReturnDate
        AND fi.Status = 'Scheduled'
        AND fi.AvailableSeats >= @Passengers
        AND ff.IsActive = 1;
    END
END;
GO

-- Create booking procedure
CREATE PROCEDURE sp_CreateBooking
    @CustomerID INT,
    @BookingType NVARCHAR(20) = 'Individual',
    @BookingChannel NVARCHAR(50) = 'Direct',
    @DepartureDate DATE = NULL,
    @ReturnDate DATE = NULL,
    @Origin NVARCHAR(100) = NULL,
    @Destination NVARCHAR(100) = NULL,
    @Travelers INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BookingNumber NVARCHAR(50);

    -- Generate booking number
    SET @BookingNumber = 'BK-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                        RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                        RIGHT('0000000' + CAST(ABS(CHECKSUM(NEWID())) % 10000000 AS NVARCHAR(7)), 7);

    -- Create booking (amounts will be updated when segments are added)
    INSERT INTO TravelBookings (
        BookingNumber, CustomerID, BookingType, BookingChannel,
        DepartureDate, ReturnDate, Origin, Destination, Travelers,
        Subtotal, TotalAmount
    )
    VALUES (
        @BookingNumber, @CustomerID, @BookingType, @BookingChannel,
        @DepartureDate, @ReturnDate, @Origin, @Destination, @Travelers,
        0, 0
    );

    SELECT SCOPE_IDENTITY() AS BookingID, @BookingNumber AS BookingNumber;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample supplier
INSERT INTO Suppliers (SupplierCode, SupplierName, SupplierType, CommissionRate) VALUES
('AA', 'American Airlines', 'Airline', 0.05);

-- Insert sample customer
INSERT INTO TravelCustomers (CustomerNumber, FirstName, LastName, Email) VALUES
('CUST-000001', 'John', 'Smith', 'john.smith@email.com');

-- Insert sample flight schedule
INSERT INTO FlightSchedules (FlightNumber, AirlineID, OriginAirport, DestinationAirport, DepartureTime, ArrivalTime, FlightDuration, DaysOfOperation) VALUES
('AA101', 1, 'JFK', 'LAX', '08:00', '11:30', 330, '1234567');

-- Insert sample flight fare
INSERT INTO FlightFares (ScheduleID, FareBasisCode, FareClass, BaseFare, Taxes, TotalFare, AvailableSeats) VALUES
(1, 'YBASE', 'Y', 299.00, 45.50, 344.50, 150);

PRINT 'Travel database schema created successfully!';
GO
