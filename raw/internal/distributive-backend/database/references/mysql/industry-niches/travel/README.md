# Travel & Tourism Platform Database Design

## Overview

This comprehensive database schema supports modern travel and tourism platforms including flight bookings, hotel reservations, tour packages, car rentals, and comprehensive travel management. The design handles complex itineraries, multi-supplier integrations, dynamic pricing, and enterprise travel operations.

## Key Features

### ✈️ Flight & Transportation Management
- **Flight inventory and scheduling** with real-time availability and pricing
- **Multi-segment itineraries** with connections, layovers, and complex routing
- **Transportation integration** with trains, buses, ferries, and ground transportation
- **Dynamic pricing and yield management** with fare classes and revenue optimization

### 🏨 Accommodation & Hotel Booking
- **Hotel inventory management** with room types, rates, and availability
- **Complex booking scenarios** with multi-room, long-stay, and corporate rates
- **Property management integration** with channel managers and PMS systems
- **Alternative accommodations** including vacation rentals and resorts

### 🎯 Tour & Package Management
- **Tour package creation** with bundled services and dynamic pricing
- **Itinerary management** with day-by-day activities and transportation
- **Supplier management** with contracts, commissions, and performance tracking
- **Custom tour creation** with personalized experiences and group bookings

## Database Schema Highlights

### Core Tables

#### Supplier & Product Management
```sql
-- Travel suppliers (airlines, hotels, tour operators)
CREATE TABLE Suppliers (
    SupplierID INT IDENTITY(1,1) PRIMARY KEY,
    SupplierCode NVARCHAR(20) UNIQUE NOT NULL,
    SupplierName NVARCHAR(200) NOT NULL,
    SupplierType NVARCHAR(50) NOT NULL, -- Airline, Hotel, TourOperator, CarRental, Rail, Bus

    -- Contact and business information
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

    -- Supplier rating and performance
    Rating DECIMAL(3,2) CHECK (Rating BETWEEN 1.00 AND 5.00),
    IsPreferred BIT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    -- Operational details
    BookingLeadTime INT, -- Hours/days required for booking
    CancellationPolicy NVARCHAR(MAX), -- JSON formatted policies
    SupportedCurrencies NVARCHAR(MAX), -- JSON array

    -- Constraints
    CONSTRAINT CK_Suppliers_Type CHECK (SupplierType IN ('Airline', 'Hotel', 'TourOperator', 'CarRental', 'Rail', 'Bus', 'Ferry', 'Cruise', 'Activity', 'Transfer')),

    -- Indexes
    INDEX IX_Suppliers_Code (SupplierCode),
    INDEX IX_Suppliers_Type (SupplierType),
    INDEX IX_Suppliers_IsActive (IsActive),
    INDEX IX_Suppliers_IsPreferred (IsPreferred)
);

-- Travel products (flights, hotels, tours, etc.)
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

    -- Pricing and availability
    BasePrice DECIMAL(10,2),
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',
    MinimumPrice DECIMAL(10,2),
    MaximumPrice DECIMAL(10,2),

    -- Availability and booking
    IsAvailable BIT DEFAULT 1,
    BookingLeadTime INT DEFAULT 0, -- Hours required for booking
    CancellationPolicy NVARCHAR(MAX), -- JSON formatted

    -- Product specifications (JSON based on type)
    Specifications NVARCHAR(MAX), -- Flight: airline, aircraft; Hotel: stars, amenities; etc.

    -- Marketing and content
    Images NVARCHAR(MAX), -- JSON array of image URLs
    Highlights NVARCHAR(MAX), -- JSON array of key features
    IncludedServices NVARCHAR(MAX), -- JSON array of what's included

    -- Status and metadata
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
```

#### Flight & Transportation Management
```sql
-- Flight schedules and routes
CREATE TABLE FlightSchedules (
    ScheduleID INT IDENTITY(1,1) PRIMARY KEY,
    FlightNumber NVARCHAR(20) NOT NULL,
    AirlineID INT NOT NULL REFERENCES Suppliers(SupplierID),
    AircraftType NVARCHAR(50),

    -- Route information
    OriginAirport NVARCHAR(10) NOT NULL, -- IATA code
    DestinationAirport NVARCHAR(10) NOT NULL,
    Distance INT, -- Nautical miles

    -- Schedule details
    DepartureTime TIME NOT NULL,
    ArrivalTime TIME NOT NULL,
    FlightDuration INT, -- Minutes
    TimeZone NVARCHAR(50),

    -- Operational details
    DaysOfOperation NVARCHAR(7), -- 1234567 (1=Monday, 7=Sunday)
    IsActive BIT DEFAULT 1,
    EffectiveStartDate DATE,
    EffectiveEndDate DATE,

    -- Flight classes and capacity
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

-- Flight instances (specific flights)
CREATE TABLE FlightInstances (
    InstanceID INT IDENTITY(1,1) PRIMARY KEY,
    ScheduleID INT NOT NULL REFERENCES FlightSchedules(ScheduleID),
    FlightDate DATE NOT NULL,
    FlightNumber NVARCHAR(20) NOT NULL,

    -- Flight details
    DepartureTime DATETIME2 NOT NULL,
    ArrivalTime DATETIME2 NOT NULL,
    ActualDepartureTime DATETIME2,
    ActualArrivalTime DATETIME2,

    -- Aircraft and crew
    AircraftRegistration NVARCHAR(20),
    Captain NVARCHAR(100),
    FirstOfficer NVARCHAR(100),

    -- Status and delays
    Status NVARCHAR(20) DEFAULT 'Scheduled', -- Scheduled, Boarding, Departed, Arrived, Cancelled, Delayed
    DelayMinutes INT DEFAULT 0,
    DelayReason NVARCHAR(MAX),

    -- Load and availability
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

-- Flight pricing and fare classes
CREATE TABLE FlightFares (
    FareID INT IDENTITY(1,1) PRIMARY KEY,
    ScheduleID INT NOT NULL REFERENCES FlightSchedules(ScheduleID),
    FareBasisCode NVARCHAR(20) NOT NULL,
    FareClass NVARCHAR(10) NOT NULL, -- Y, J, F, etc.

    -- Pricing
    BaseFare DECIMAL(10,2) NOT NULL,
    Taxes DECIMAL(10,2) DEFAULT 0,
    TotalFare DECIMAL(10,2) NOT NULL,

    -- Availability and booking
    AvailableSeats INT,
    MinimumStay INT, -- Days
    MaximumStay INT, -- Days
    AdvancePurchase INT, -- Days required

    -- Restrictions and rules
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
```

#### Hotel & Accommodation Management
```sql
-- Hotel properties
CREATE TABLE HotelProperties (
    PropertyID INT IDENTITY(1,1) PRIMARY KEY,
    PropertyCode NVARCHAR(20) UNIQUE NOT NULL,
    PropertyName NVARCHAR(200) NOT NULL,
    SupplierID INT NOT NULL REFERENCES Suppliers(SupplierID),

    -- Location and details
    Address NVARCHAR(MAX), -- JSON formatted
    City NVARCHAR(100),
    Country NVARCHAR(100),
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),

    -- Property information
    StarRating INT CHECK (StarRating BETWEEN 1 AND 5),
    TotalRooms INT,
    PropertyType NVARCHAR(50), -- Hotel, Resort, Apartment, Villa, etc.
    CheckInTime TIME DEFAULT '15:00',
    CheckOutTime TIME DEFAULT '11:00',

    -- Amenities and features
    Amenities NVARCHAR(MAX), -- JSON array
    Policies NVARCHAR(MAX), -- JSON object with policies

    -- Operational status
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

    -- Room specifications
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

-- Hotel rates and availability
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
    RateRestrictions NVARCHAR(MAX), -- JSON formatted restrictions

    -- Constraints
    CONSTRAINT UQ_HotelRates_PropertyRoomDate UNIQUE (PropertyID, RoomTypeID, RateDate),

    -- Indexes
    INDEX IX_HotelRates_Property (PropertyID),
    INDEX IX_HotelRates_RoomType (RoomTypeID),
    INDEX IX_HotelRates_Date (RateDate),
    INDEX IX_HotelRates_Available (AvailableRooms)
);
```

### Booking & Reservation Management

#### Customer & Traveler Management
```sql
-- Travel customers
CREATE TABLE TravelCustomers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNumber NVARCHAR(20) UNIQUE NOT NULL,

    -- Personal information
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

    -- Preferences and history
    PreferredAirline NVARCHAR(100),
    PreferredSeat NVARCHAR(20), -- Window, Aisle, Middle
    DietaryRestrictions NVARCHAR(MAX), -- JSON array
    AccessibilityNeeds NVARCHAR(MAX), -- JSON array

    -- Loyalty and status
    LoyaltyProgram NVARCHAR(100),
    LoyaltyNumber NVARCHAR(50),
    MembershipLevel NVARCHAR(20) DEFAULT 'Standard', -- Standard, Gold, Platinum

    -- Travel history
    TotalBookings INT DEFAULT 0,
    TotalSpent DECIMAL(12,2) DEFAULT 0,
    LastBookingDate DATETIME2,

    -- Marketing preferences
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

-- Travel bookings master table
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

    -- Financial summary
    Subtotal DECIMAL(12,2) NOT NULL,
    Taxes DECIMAL(10,2) DEFAULT 0,
    Fees DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(12,2) NOT NULL,
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Payment and status
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

-- Booking segments (flights, hotels, etc.)
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
```

### Tour & Package Management

#### Tour Packages
```sql
-- Tour packages
CREATE TABLE TourPackages (
    PackageID INT IDENTITY(1,1) PRIMARY KEY,
    PackageCode NVARCHAR(20) UNIQUE NOT NULL,
    PackageName NVARCHAR(200) NOT NULL,
    SupplierID INT REFERENCES Suppliers(SupplierID),

    -- Package details
    Description NVARCHAR(MAX),
    Category NVARCHAR(50), -- Adventure, Cultural, Beach, City, Nature, etc.
    Duration INT, -- Days
    MinParticipants INT DEFAULT 1,
    MaxParticipants INT,

    -- Itinerary highlights
    Destinations NVARCHAR(MAX), -- JSON array of places
    Activities NVARCHAR(MAX), -- JSON array of activities
    IncludedServices NVARCHAR(MAX), -- JSON array

    -- Pricing
    BasePrice DECIMAL(10,2) NOT NULL,
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',
    PricePerPerson BIT DEFAULT 1,

    -- Availability and booking
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

-- Tour itineraries
CREATE TABLE TourItineraries (
    ItineraryID INT IDENTITY(1,1) PRIMARY KEY,
    PackageID INT NOT NULL REFERENCES TourPackages(PackageID) ON DELETE CASCADE,
    DayNumber INT NOT NULL,
    DayTitle NVARCHAR(200),

    -- Day details
    Description NVARCHAR(MAX),
    Activities NVARCHAR(MAX), -- JSON array
    Meals NVARCHAR(MAX), -- JSON array: Breakfast, Lunch, Dinner
    Accommodation NVARCHAR(200),

    -- Location and transportation
    Location NVARCHAR(200),
    Departure NVARCHAR(200), -- From location
    Arrival NVARCHAR(200), -- To location
    Transportation NVARCHAR(100), -- Flight, Bus, Train, etc.

    -- Timing
    StartTime TIME,
    EndTime TIME,

    -- Constraints
    CONSTRAINT UQ_TourItineraries_PackageDay UNIQUE (PackageID, DayNumber),

    -- Indexes
    INDEX IX_TourItineraries_Package (PackageID),
    INDEX IX_TourItineraries_Day (DayNumber)
);

-- Tour departures and pricing
CREATE TABLE TourDepartures (
    DepartureID INT IDENTITY(1,1) PRIMARY KEY,
    PackageID INT NOT NULL REFERENCES TourPackages(PackageID),
    DepartureDate DATE NOT NULL,
    ReturnDate DATE,

    -- Capacity and availability
    TotalCapacity INT NOT NULL,
    AvailableSeats INT NOT NULL,
    MinimumParticipants INT DEFAULT 1,

    -- Pricing by departure
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
```

## Integration Points

### External Systems
- **Global Distribution Systems**: Amadeus, Sabre, Travelport for flight and hotel inventory
- **Online Travel Agencies**: Expedia, Booking.com, TripAdvisor for channel management
- **Payment Processors**: Stripe, PayPal, Adyen for secure transactions
- **Supplier APIs**: Airline reservation systems, hotel PMS, car rental systems
- **Customer Systems**: CRM integration, loyalty programs, customer service
- **Regulatory Systems**: Passport validation, visa requirements, customs information

### API Endpoints
- **Search APIs**: Flight search, hotel availability, tour packages, pricing
- **Booking APIs**: Reservation creation, modification, cancellation processing
- **Inventory APIs**: Real-time availability updates, rate management
- **Customer APIs**: Profile management, booking history, preferences
- **Supplier APIs**: Content updates, booking confirmations, cancellations
- **Analytics APIs**: Revenue reporting, booking trends, performance metrics

## Monitoring & Analytics

### Key Performance Indicators
- **Booking Performance**: Conversion rates, average booking value, booking lead times
- **Revenue Management**: Average revenue per booking, margin analysis, channel performance
- **Customer Experience**: Booking completion rates, modification frequency, cancellation rates
- **Supplier Performance**: On-time performance, booking accuracy, issue resolution rates
- **Operational Efficiency**: Booking processing time, system uptime, API performance

### Real-Time Dashboards
```sql
-- Travel booking dashboard
CREATE VIEW TravelBookingDashboard AS
SELECT
    -- Daily booking metrics
    (SELECT COUNT(*) FROM TravelBookings
     WHERE CAST(BookingDate AS DATE) = CAST(GETDATE() AS DATE)
     AND BookingStatus != 'Cancelled') AS BookingsToday,

    (SELECT SUM(TotalAmount) FROM TravelBookings
     WHERE CAST(BookingDate AS DATE) = CAST(GETDATE() AS DATE)
     AND PaymentStatus = 'Paid') AS RevenueToday,

    (SELECT AVG(TotalAmount) FROM TravelBookings
     WHERE CAST(BookingDate AS DATE) = CAST(GETDATE() AS DATE)
     AND PaymentStatus = 'Paid') AS AverageBookingValue,

    -- Monthly performance
    (SELECT COUNT(*) FROM TravelBookings
     WHERE MONTH(BookingDate) = MONTH(GETDATE())
     AND YEAR(BookingDate) = YEAR(GETDATE())
     AND BookingStatus != 'Cancelled') AS BookingsThisMonth,

    (SELECT SUM(TotalAmount) FROM TravelBookings
     WHERE MONTH(BookingDate) = MONTH(GETDATE())
     AND YEAR(BookingDate) = YEAR(GETDATE())
     AND PaymentStatus = 'Paid') AS RevenueThisMonth,

    -- Channel performance
    (SELECT COUNT(*) FROM TravelBookings
     WHERE BookingChannel = 'Direct'
     AND MONTH(BookingDate) = MONTH(GETDATE())) AS DirectBookingsThisMonth,

    (SELECT COUNT(*) FROM TravelBookings
     WHERE BookingChannel = 'OTA'
     AND MONTH(BookingDate) = MONTH(GETDATE())) AS OTABookingsThisMonth,

    -- Booking status overview
    (SELECT COUNT(*) FROM TravelBookings
     WHERE BookingStatus = 'Confirmed') AS ConfirmedBookings,

    (SELECT COUNT(*) FROM TravelBookings
     WHERE BookingStatus = 'Cancelled'
     AND MONTH(BookingDate) = MONTH(GETDATE())) AS CancellationsThisMonth,

    -- Upcoming departures
    (SELECT COUNT(*) FROM BookingSegments
     WHERE SegmentType = 'Flight'
     AND StartDate >= GETDATE()
     AND StartDate <= DATEADD(DAY, 7, GETDATE())) AS FlightsDepartingNextWeek,

    -- Supplier performance
    (SELECT COUNT(*) FROM Suppliers
     WHERE Rating >= 4.0 AND IsActive = 1) AS HighRatedSuppliers,

    -- Customer metrics
    (SELECT COUNT(*) FROM TravelCustomers
     WHERE CAST(CreatedDate AS DATE) = CAST(GETDATE() AS DATE)) AS NewCustomersToday,

    (SELECT COUNT(*) FROM TravelCustomers
     WHERE TotalBookings > 5) AS HighValueCustomers

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This travel database schema provides a comprehensive foundation for modern travel and tourism platforms, supporting complex bookings, multi-supplier integrations, dynamic pricing, and enterprise travel operations while maintaining high performance and regulatory compliance.
