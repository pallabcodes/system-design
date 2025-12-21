-- Food Delivery & Restaurant Management Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE FoodDeliveryDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE FoodDeliveryDB;
GO

-- Configure database for food delivery performance
ALTER DATABASE FoodDeliveryDB
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
-- RESTAURANT MANAGEMENT
-- =============================================

-- Restaurants
CREATE TABLE Restaurants (
    RestaurantID INT IDENTITY(1,1) PRIMARY KEY,
    RestaurantCode NVARCHAR(20) UNIQUE NOT NULL,
    RestaurantName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Location and contact
    Address NVARCHAR(MAX), -- JSON formatted complete address
    City NVARCHAR(100),
    State NVARCHAR(50),
    Country NVARCHAR(50),
    PostalCode NVARCHAR(20),
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),

    -- Contact information
    Phone NVARCHAR(20),
    Email NVARCHAR(255),
    Website NVARCHAR(500),

    -- Business details
    CuisineType NVARCHAR(50), -- Italian, Chinese, FastFood, FineDining, etc.
    PriceRange NVARCHAR(10) DEFAULT '$$', -- $, $$, $$$, $$$$
    Capacity INT, -- Seating capacity
    OperatingHours NVARCHAR(MAX), -- JSON: {"monday": "11-22", "tuesday": "11-22"}

    -- Business status
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Inactive, TemporarilyClosed, PermanentlyClosed
    IsDeliveryEnabled BIT DEFAULT 1,
    IsPickupEnabled BIT DEFAULT 1,
    IsDineInEnabled BIT DEFAULT 1,

    -- Management
    ManagerID INT,
    FranchiseID INT, -- For chain restaurants
    Rating DECIMAL(3,2) CHECK (Rating BETWEEN 1.00 AND 5.00),

    -- Financial
    CommissionRate DECIMAL(5,4) DEFAULT 0.25, -- Platform commission
    ServiceFee DECIMAL(6,2) DEFAULT 2.99, -- Per order fee

    -- Operational settings
    PrepTimeMinutes INT DEFAULT 30,
    DeliveryRadiusMiles DECIMAL(4,1) DEFAULT 5.0,
    MinimumOrderAmount DECIMAL(6,2) DEFAULT 15.00,

    -- Constraints
    CONSTRAINT CK_Restaurants_Cuisine CHECK (CuisineType IN ('Italian', 'Chinese', 'Mexican', 'Indian', 'American', 'Japanese', 'Thai', 'Mediterranean', 'FastFood', 'FineDining', 'Cafe', 'Pizza', 'Burger', 'Seafood', 'Vegetarian', 'Other')),
    CONSTRAINT CK_Restaurants_Status CHECK (Status IN ('Active', 'Inactive', 'TemporarilyClosed', 'PermanentlyClosed')),
    CONSTRAINT CK_Restaurants_PriceRange CHECK (PriceRange IN ('$', '$$', '$$$', '$$$$')),
    CONSTRAINT CK_Restaurants_Commission CHECK (CommissionRate BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_Restaurants_Code (RestaurantCode),
    INDEX IX_Restaurants_Name (RestaurantName),
    INDEX IX_Restaurants_Cuisine (CuisineType),
    INDEX IX_Restaurants_Status (Status),
    INDEX IX_Restaurants_City (City),
    INDEX IX_Restaurants_IsDeliveryEnabled (IsDeliveryEnabled),
    INDEX IX_Restaurants_Rating (Rating DESC)
);

-- Menu categories
CREATE TABLE MenuCategories (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    RestaurantID INT NOT NULL REFERENCES Restaurants(RestaurantID) ON DELETE CASCADE,
    CategoryName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),
    DisplayOrder INT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    -- Category settings
    ImageURL NVARCHAR(500),
    Color NVARCHAR(7), -- Hex color code
    IsPopular BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_MenuCategories_Restaurant UNIQUE (RestaurantID, CategoryName),

    -- Indexes
    INDEX IX_MenuCategories_Restaurant (RestaurantID),
    INDEX IX_MenuCategories_IsActive (IsActive),
    INDEX IX_MenuCategories_DisplayOrder (DisplayOrder)
);

-- Menu items
CREATE TABLE MenuItems (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    RestaurantID INT NOT NULL REFERENCES Restaurants(RestaurantID) ON DELETE CASCADE,
    CategoryID INT NOT NULL REFERENCES MenuCategories(CategoryID),
    ItemCode NVARCHAR(50) UNIQUE NOT NULL,
    ItemName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),

    -- Pricing and availability
    BasePrice DECIMAL(6,2) NOT NULL,
    IsAvailable BIT DEFAULT 1,
    IsPopular BIT DEFAULT 0,
    IsVegetarian BIT DEFAULT 0,
    IsVegan BIT DEFAULT 0,
    IsGlutenFree BIT DEFAULT 0,
    SpiceLevel NVARCHAR(10), -- None, Mild, Medium, Hot, VeryHot

    -- Preparation details
    PrepTimeMinutes INT DEFAULT 15,
    Calories INT,
    ServingSize NVARCHAR(50),

    -- Images and media
    ImageURL NVARCHAR(500),
    ThumbnailURL NVARCHAR(500),

    -- Nutritional information (JSON)
    NutritionalInfo NVARCHAR(MAX),

    -- Allergens (JSON array)
    Allergens NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_MenuItems_SpiceLevel CHECK (SpiceLevel IN ('None', 'Mild', 'Medium', 'Hot', 'VeryHot')),

    -- Indexes
    INDEX IX_MenuItems_Restaurant (RestaurantID),
    INDEX IX_MenuItems_Category (CategoryID),
    INDEX IX_MenuItems_Code (ItemCode),
    INDEX IX_MenuItems_IsAvailable (IsAvailable),
    INDEX IX_MenuItems_IsPopular (IsPopular)
);

-- Menu item variants
CREATE TABLE MenuItemVariants (
    VariantID INT IDENTITY(1,1) PRIMARY KEY,
    ItemID INT NOT NULL REFERENCES MenuItems(ItemID) ON DELETE CASCADE,
    VariantName NVARCHAR(100) NOT NULL, -- Small, Medium, Large, Extra Cheese, etc.
    VariantType NVARCHAR(50) DEFAULT 'Size', -- Size, Customization, AddOn
    AdditionalPrice DECIMAL(6,2) DEFAULT 0,
    IsDefault BIT DEFAULT 0,
    DisplayOrder INT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_MenuItemVariants_Type CHECK (VariantType IN ('Size', 'Customization', 'AddOn', 'Remove')),
    CONSTRAINT UQ_MenuItemVariants_ItemName UNIQUE (ItemID, VariantName),

    -- Indexes
    INDEX IX_MenuItemVariants_Item (ItemID),
    INDEX IX_MenuItemVariants_Type (VariantType),
    INDEX IX_MenuItemVariants_IsActive (IsActive)
);

-- =============================================
-- ORDER MANAGEMENT
-- =============================================

-- Customer orders
CREATE TABLE Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    OrderNumber NVARCHAR(50) UNIQUE NOT NULL,
    CustomerID INT NOT NULL,

    -- Order details
    RestaurantID INT NOT NULL REFERENCES Restaurants(RestaurantID),
    OrderType NVARCHAR(20) DEFAULT 'Delivery', -- Delivery, Pickup, DineIn, DriveThru
    OrderChannel NVARCHAR(20) DEFAULT 'App', -- App, Web, Phone, ThirdParty, POS

    -- Order status and timing
    Status NVARCHAR(20) DEFAULT 'Placed', -- Placed, Confirmed, Preparing, Ready, OutForDelivery, Delivered, Cancelled
    OrderDate DATETIME2 DEFAULT GETDATE(),
    RequestedDeliveryTime DATETIME2,
    ActualDeliveryTime DATETIME2,
    EstimatedPrepTime INT, -- Minutes
    EstimatedDeliveryTime INT, -- Minutes

    -- Financial details
    Subtotal DECIMAL(8,2) NOT NULL,
    TaxAmount DECIMAL(8,2) DEFAULT 0,
    DeliveryFee DECIMAL(6,2) DEFAULT 0,
    ServiceFee DECIMAL(6,2) DEFAULT 0,
    TipAmount DECIMAL(6,2) DEFAULT 0,
    DiscountAmount DECIMAL(6,2) DEFAULT 0,
    TotalAmount DECIMAL(8,2) NOT NULL,

    -- Payment information
    PaymentMethod NVARCHAR(20), -- CreditCard, DebitCard, Cash, DigitalWallet, PayPal
    PaymentStatus NVARCHAR(20) DEFAULT 'Pending', -- Pending, Paid, Failed, Refunded
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Delivery information
    DeliveryAddress NVARCHAR(MAX), -- JSON formatted
    DeliveryInstructions NVARCHAR(MAX),
    DriverID INT,
    VehicleType NVARCHAR(20), -- Car, Bike, Scooter, Walking

    -- Special instructions
    CustomerNotes NVARCHAR(MAX),
    AllergyNotes NVARCHAR(MAX),

    -- Quality and feedback
    Rating DECIMAL(3,2), -- Customer rating 1.0-5.0
    Feedback NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_Orders_Type CHECK (OrderType IN ('Delivery', 'Pickup', 'DineIn', 'DriveThru', 'Catering')),
    CONSTRAINT CK_Orders_Channel CHECK (OrderChannel IN ('App', 'Web', 'Phone', 'ThirdParty', 'POS', 'Kiosk')),
    CONSTRAINT CK_Orders_Status CHECK (Status IN ('Placed', 'Confirmed', 'Preparing', 'Ready', 'OutForDelivery', 'Delivered', 'Cancelled', 'Refunded')),
    CONSTRAINT CK_Orders_PaymentMethod CHECK (PaymentMethod IN ('CreditCard', 'DebitCard', 'Cash', 'DigitalWallet', 'PayPal', 'ApplePay', 'GooglePay')),
    CONSTRAINT CK_Orders_PaymentStatus CHECK (PaymentStatus IN ('Pending', 'Paid', 'Failed', 'Refunded')),
    CONSTRAINT CK_Orders_VehicleType CHECK (VehicleType IN ('Car', 'Bike', 'Scooter', 'Walking', 'Drone')),

    -- Indexes
    INDEX IX_Orders_Number (OrderNumber),
    INDEX IX_Orders_Customer (CustomerID),
    INDEX IX_Orders_Restaurant (RestaurantID),
    INDEX IX_Orders_Type (OrderType),
    INDEX IX_Orders_Status (Status),
    INDEX IX_Orders_Channel (OrderChannel),
    INDEX IX_Orders_OrderDate (OrderDate),
    INDEX IX_Orders_RequestedDeliveryTime (RequestedDeliveryTime),
    INDEX IX_Orders_PaymentStatus (PaymentStatus),
    INDEX IX_Orders_Driver (DriverID)
);

-- Order items
CREATE TABLE OrderItems (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES Orders(OrderID) ON DELETE CASCADE,
    ItemID INT NOT NULL REFERENCES MenuItems(ItemID),
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(6,2) NOT NULL,
    TotalPrice DECIMAL(8,2) NOT NULL,

    -- Item customizations
    SpecialInstructions NVARCHAR(MAX),
    VariantsSelected NVARCHAR(MAX), -- JSON array of selected variants

    -- Preparation status
    PrepStatus NVARCHAR(20) DEFAULT 'Pending', -- Pending, Preparing, Ready, Served
    PreparedBy INT,
    PreparedDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_OrderItems_PrepStatus CHECK (PrepStatus IN ('Pending', 'Preparing', 'Ready', 'Served', 'Cancelled')),

    -- Indexes
    INDEX IX_OrderItems_Order (OrderID),
    INDEX IX_OrderItems_Item (ItemID),
    INDEX IX_OrderItems_PrepStatus (PrepStatus)
);

-- =============================================
-- DELIVERY MANAGEMENT
-- =============================================

-- Delivery drivers
CREATE TABLE DeliveryDrivers (
    DriverID INT IDENTITY(1,1) PRIMARY KEY,
    DriverNumber NVARCHAR(20) UNIQUE NOT NULL,
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    Phone NVARCHAR(20),

    -- Driver details
    DateOfBirth DATE,
    LicenseNumber NVARCHAR(50),
    LicenseExpiry DATE,
    VehicleType NVARCHAR(20), -- Car, Bike, Scooter
    VehicleMake NVARCHAR(50),
    VehicleModel NVARCHAR(50),
    VehicleColor NVARCHAR(30),

    -- Work status
    Status NVARCHAR(20) DEFAULT 'Available', -- Available, Busy, Offline, Suspended
    CurrentLocation NVARCHAR(MAX), -- JSON: lat, lng, timestamp
    LastLocationUpdate DATETIME2,

    -- Performance metrics
    TotalDeliveries INT DEFAULT 0,
    AverageRating DECIMAL(3,2) DEFAULT 5.0,
    OnTimeDeliveryRate DECIMAL(5,4) DEFAULT 1.0, -- 0.0000 to 1.0000

    -- Account status
    IsActive BIT DEFAULT 1,
    HireDate DATETIME2 DEFAULT GETDATE(),
    TerminationDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_DeliveryDrivers_Status CHECK (Status IN ('Available', 'Busy', 'Offline', 'Suspended', 'Terminated')),
    CONSTRAINT CK_DeliveryDrivers_VehicleType CHECK (VehicleType IN ('Car', 'Bike', 'Scooter', 'Walking')),
    CONSTRAINT CK_DeliveryDrivers_Rating CHECK (AverageRating BETWEEN 1.0 AND 5.0),
    CONSTRAINT CK_DeliveryDrivers_OnTimeRate CHECK (OnTimeDeliveryRate BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_DeliveryDrivers_Number (DriverNumber),
    INDEX IX_DeliveryDrivers_Name (LastName, FirstName),
    INDEX IX_DeliveryDrivers_Email (Email),
    INDEX IX_DeliveryDrivers_Status (Status),
    INDEX IX_DeliveryDrivers_IsActive (IsActive),
    INDEX IX_DeliveryDrivers_AverageRating (AverageRating DESC)
);

-- Delivery assignments
CREATE TABLE DeliveryAssignments (
    AssignmentID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES Orders(OrderID),
    DriverID INT NOT NULL REFERENCES DeliveryDrivers(DriverID),

    -- Assignment details
    AssignedDate DATETIME2 DEFAULT GETDATE(),
    AcceptedDate DATETIME2,
    PickupDate DATETIME2,
    DeliveryDate DATETIME2,

    -- Status tracking
    Status NVARCHAR(20) DEFAULT 'Assigned', -- Assigned, Accepted, PickedUp, OutForDelivery, Delivered, Failed
    EstimatedDeliveryTime DATETIME2,
    ActualDeliveryTime DATETIME2,

    -- Location tracking
    PickupLocation NVARCHAR(MAX), -- JSON formatted
    DeliveryLocation NVARCHAR(MAX), -- JSON formatted
    CurrentLocation NVARCHAR(MAX), -- JSON formatted (real-time updates)

    -- Performance
    DistanceMiles DECIMAL(6,2),
    TravelTimeMinutes INT,
    CustomerRating DECIMAL(3,2), -- 1.0 to 5.0
    CustomerFeedback NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT UQ_DeliveryAssignments_Order UNIQUE (OrderID),
    CONSTRAINT CK_DeliveryAssignments_Status CHECK (Status IN ('Assigned', 'Accepted', 'PickedUp', 'OutForDelivery', 'Delivered', 'Failed', 'Cancelled')),

    -- Indexes
    INDEX IX_DeliveryAssignments_Order (OrderID),
    INDEX IX_DeliveryAssignments_Driver (DriverID),
    INDEX IX_DeliveryAssignments_Status (Status),
    INDEX IX_DeliveryAssignments_AssignedDate (AssignedDate),
    INDEX IX_DeliveryAssignments_DeliveryDate (DeliveryDate)
);

-- =============================================
-- RESTAURANT OPERATIONS
-- =============================================

-- Restaurant staff
CREATE TABLE RestaurantStaff (
    StaffID INT IDENTITY(1,1) PRIMARY KEY,
    RestaurantID INT NOT NULL REFERENCES Restaurants(RestaurantID) ON DELETE CASCADE,
    StaffNumber NVARCHAR(20) UNIQUE NOT NULL,

    -- Personal information
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(255),
    Phone NVARCHAR(20),

    -- Employment details
    JobTitle NVARCHAR(50), -- Manager, Chef, Server, Driver, KitchenStaff
    Department NVARCHAR(50), -- Kitchen, Service, Delivery, Management
    HireDate DATETIME2 DEFAULT GETDATE(),
    TerminationDate DATETIME2,
    IsActive BIT DEFAULT 1,

    -- Work schedule
    WeeklyHours INT DEFAULT 40,
    HourlyRate DECIMAL(6,2),

    -- Performance
    Rating DECIMAL(3,2) DEFAULT 3.0, -- 1.0 to 5.0
    LastPerformanceReview DATETIME2,

    -- Constraints
    CONSTRAINT CK_RestaurantStaff_JobTitle CHECK (JobTitle IN ('Manager', 'Chef', 'SousChef', 'LineCook', 'Server', 'Bartender', 'Host', 'Driver', 'KitchenStaff', 'Cleaner')),
    CONSTRAINT CK_RestaurantStaff_Department CHECK (Department IN ('Kitchen', 'Service', 'Delivery', 'Management', 'Operations')),
    CONSTRAINT CK_RestaurantStaff_Rating CHECK (Rating BETWEEN 1.0 AND 5.0),

    -- Indexes
    INDEX IX_RestaurantStaff_Restaurant (RestaurantID),
    INDEX IX_RestaurantStaff_Number (StaffNumber),
    INDEX IX_RestaurantStaff_JobTitle (JobTitle),
    INDEX IX_RestaurantStaff_Department (Department),
    INDEX IX_RestaurantStaff_IsActive (IsActive)
);

-- Kitchen orders
CREATE TABLE KitchenOrders (
    KitchenOrderID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES Orders(OrderID) ON DELETE CASCADE,
    RestaurantID INT NOT NULL REFERENCES Restaurants(RestaurantID),

    -- Order details for kitchen
    OrderNumber NVARCHAR(50),
    OrderType NVARCHAR(20),
    CustomerName NVARCHAR(200),
    SpecialInstructions NVARCHAR(MAX),

    -- Timing
    OrderTime DATETIME2 DEFAULT GETDATE(),
    EstimatedPrepTime INT,
    ActualPrepTime INT,
    ReadyTime DATETIME2,

    -- Status tracking
    Status NVARCHAR(20) DEFAULT 'Received', -- Received, Preparing, Ready, Served, Cancelled
    Priority NVARCHAR(10) DEFAULT 'Normal', -- Low, Normal, High, Urgent
    AssignedStation NVARCHAR(50), -- Grill, Fry, Salad, Pizza, etc.

    -- Quality control
    PreparedBy INT REFERENCES RestaurantStaff(StaffID),
    QualityCheckBy INT REFERENCES RestaurantStaff(StaffID),
    QualityRating NVARCHAR(10), -- Good, Satisfactory, NeedsImprovement

    -- Constraints
    CONSTRAINT CK_KitchenOrders_Status CHECK (Status IN ('Received', 'Preparing', 'Ready', 'Served', 'Cancelled')),
    CONSTRAINT CK_KitchenOrders_Priority CHECK (Priority IN ('Low', 'Normal', 'High', 'Urgent')),
    CONSTRAINT CK_KitchenOrders_Quality CHECK (QualityRating IN ('Good', 'Satisfactory', 'NeedsImprovement')),

    -- Indexes
    INDEX IX_KitchenOrders_Order (OrderID),
    INDEX IX_KitchenOrders_Restaurant (RestaurantID),
    INDEX IX_KitchenOrders_Status (Status),
    INDEX IX_KitchenOrders_OrderTime (OrderTime),
    INDEX IX_KitchenOrders_AssignedStation (AssignedStation)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Order summary view
CREATE VIEW vw_OrderSummary
AS
SELECT
    o.OrderID,
    o.OrderNumber,
    o.OrderDate,
    r.RestaurantName,
    o.OrderType,
    o.OrderChannel,
    o.Status,
    o.TotalAmount,
    o.PaymentStatus,

    -- Delivery info
    o.RequestedDeliveryTime,
    o.ActualDeliveryTime,
    CASE
        WHEN o.ActualDeliveryTime IS NOT NULL AND o.RequestedDeliveryTime IS NOT NULL
        THEN DATEDIFF(MINUTE, o.RequestedDeliveryTime, o.ActualDeliveryTime)
        ELSE NULL
    END AS DeliveryDelayMinutes,

    -- Driver info
    d.FirstName + ' ' + d.LastName AS DriverName,
    d.VehicleType,

    -- Order items count
    (SELECT COUNT(*) FROM OrderItems oi WHERE oi.OrderID = o.OrderID) AS ItemCount,

    -- Customer rating
    o.Rating,
    o.Feedback

FROM Orders o
INNER JOIN Restaurants r ON o.RestaurantID = r.RestaurantID
LEFT JOIN DeliveryDrivers d ON o.DriverID = d.DriverID
WHERE o.Status != 'Cancelled';
GO

-- Restaurant performance view
CREATE VIEW vw_RestaurantPerformance
AS
SELECT
    r.RestaurantID,
    r.RestaurantName,
    r.CuisineType,
    r.Status,
    r.Rating,

    -- Today's orders
    (SELECT COUNT(*) FROM Orders o
     WHERE o.RestaurantID = r.RestaurantID
     AND CAST(o.OrderDate AS DATE) = CAST(GETDATE() AS DATE)
     AND o.Status NOT IN ('Cancelled')) AS OrdersToday,

    (SELECT SUM(o.TotalAmount) FROM Orders o
     WHERE o.RestaurantID = r.RestaurantID
     AND CAST(o.OrderDate AS DATE) = CAST(GETDATE() AS DATE)
     AND o.PaymentStatus = 'Paid') AS RevenueToday,

    -- Average order value
    (SELECT AVG(o.TotalAmount) FROM Orders o
     WHERE o.RestaurantID = r.RestaurantID
     AND CAST(o.OrderDate AS DATE) = CAST(GETDATE() AS DATE)
     AND o.PaymentStatus = 'Paid') AS AvgOrderValueToday,

    -- Delivery performance
    (SELECT COUNT(*) FROM Orders o
     WHERE o.RestaurantID = r.RestaurantID
     AND CAST(o.OrderDate AS DATE) = CAST(GETDATE() AS DATE)
     AND o.OrderType = 'Delivery'
     AND o.Status = 'Delivered') AS DeliveriesCompletedToday,

    -- Customer satisfaction
    (SELECT AVG(o.Rating) FROM Orders o
     WHERE o.RestaurantID = r.RestaurantID
     AND o.Rating IS NOT NULL
     AND CAST(o.OrderDate AS DATE) = CAST(GETDATE() AS DATE)) AS AvgRatingToday

FROM Restaurants r
WHERE r.Status = 'Active';
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update order totals when items change
CREATE TRIGGER TR_OrderItems_UpdateTotals
ON OrderItems
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Update order subtotal based on order items
    UPDATE o
    SET o.Subtotal = (
        SELECT SUM(TotalPrice) FROM OrderItems oi WHERE oi.OrderID = o.OrderID
    ),
    o.TotalAmount = (
        SELECT SUM(TotalPrice) FROM OrderItems oi WHERE oi.OrderID = o.OrderID
    ) + o.TaxAmount + o.DeliveryFee + o.ServiceFee - o.DiscountAmount
    FROM Orders o
    WHERE o.OrderID IN (
        SELECT DISTINCT OrderID FROM inserted
        UNION
        SELECT DISTINCT OrderID FROM deleted
    );
END;
GO

-- Update driver performance metrics
CREATE TRIGGER TR_DeliveryAssignments_UpdateDriverMetrics
ON DeliveryAssignments
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Update driver delivery count and rating
    UPDATE dd
    SET dd.TotalDeliveries = (
            SELECT COUNT(*) FROM DeliveryAssignments da
            WHERE da.DriverID = dd.DriverID AND da.Status = 'Delivered'
        ),
        dd.AverageRating = (
            SELECT AVG(CustomerRating) FROM DeliveryAssignments da
            WHERE da.DriverID = dd.DriverID AND da.CustomerRating IS NOT NULL
        ),
        dd.OnTimeDeliveryRate = (
            SELECT CAST(COUNT(*) AS DECIMAL(5,4)) / NULLIF(COUNT(*), 0) FROM DeliveryAssignments da
            WHERE da.DriverID = dd.DriverID AND da.Status = 'Delivered'
            AND ABS(DATEDIFF(MINUTE, da.EstimatedDeliveryTime, da.ActualDeliveryTime)) <= 10
        )
    FROM DeliveryDrivers dd
    INNER JOIN inserted i ON dd.DriverID = i.DriverID;
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Create order procedure
CREATE PROCEDURE sp_CreateOrder
    @CustomerID INT,
    @RestaurantID INT,
    @OrderType NVARCHAR(20) = 'Delivery',
    @OrderChannel NVARCHAR(20) = 'App',
    @RequestedDeliveryTime DATETIME2 = NULL,
    @DeliveryAddress NVARCHAR(MAX) = NULL,
    @SpecialInstructions NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderNumber NVARCHAR(50);
    DECLARE @EstimatedPrepTime INT;
    DECLARE @EstimatedDeliveryTime INT;

    -- Generate order number
    SET @OrderNumber = 'ORD-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                      RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) +
                      RIGHT('00' + CAST(DAY(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                      RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    -- Get restaurant prep time
    SELECT @EstimatedPrepTime = PrepTimeMinutes FROM Restaurants WHERE RestaurantID = @RestaurantID;

    -- Calculate delivery time (prep time + 30 minutes delivery)
    SET @EstimatedDeliveryTime = @EstimatedPrepTime + 30;

    -- Create order (amounts will be updated when items are added)
    INSERT INTO Orders (
        OrderNumber, CustomerID, RestaurantID, OrderType, OrderChannel,
        RequestedDeliveryTime, EstimatedPrepTime, EstimatedDeliveryTime,
        DeliveryAddress, CustomerNotes
    )
    VALUES (
        @OrderNumber, @CustomerID, @RestaurantID, @OrderType, @OrderChannel,
        @RequestedDeliveryTime, @EstimatedPrepTime, @EstimatedDeliveryTime,
        @DeliveryAddress, @SpecialInstructions
    );

    SELECT SCOPE_IDENTITY() AS OrderID, @OrderNumber AS OrderNumber;
END;
GO

-- Assign delivery driver procedure
CREATE PROCEDURE sp_AssignDeliveryDriver
    @OrderID INT,
    @DriverID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if driver is available
    IF NOT EXISTS (SELECT 1 FROM DeliveryDrivers WHERE DriverID = @DriverID AND Status = 'Available')
    BEGIN
        RAISERROR('Driver is not available', 16, 1);
        RETURN;
    END

    -- Assign driver to order
    INSERT INTO DeliveryAssignments (OrderID, DriverID, Status)
    VALUES (@OrderID, @DriverID, 'Assigned');

    -- Update order with driver
    UPDATE Orders SET DriverID = @DriverID WHERE OrderID = @OrderID;

    -- Update driver status
    UPDATE DeliveryDrivers SET Status = 'Busy' WHERE DriverID = @DriverID;

    SELECT SCOPE_IDENTITY() AS AssignmentID;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample restaurant
INSERT INTO Restaurants (RestaurantCode, RestaurantName, CuisineType, City, IsDeliveryEnabled) VALUES
('RST-001', 'Mario''s Italian Kitchen', 'Italian', 'New York', 1);

-- Insert sample menu category
INSERT INTO MenuCategories (RestaurantID, CategoryName, DisplayOrder) VALUES
(1, 'Pasta', 1);

-- Insert sample menu item
INSERT INTO MenuItems (RestaurantID, CategoryID, ItemCode, ItemName, BasePrice, IsPopular) VALUES
(1, 1, 'SPAG-001', 'Spaghetti Carbonara', 18.99, 1);

-- Insert sample driver
INSERT INTO DeliveryDrivers (DriverNumber, FirstName, LastName, Email, VehicleType) VALUES
('DRV-001', 'John', 'Smith', 'john.smith@delivery.com', 'Bike');

-- Insert sample order
INSERT INTO Orders (OrderNumber, CustomerID, RestaurantID, OrderType, Status, Subtotal, TotalAmount) VALUES
('ORD-20241215-00001', 1, 1, 'Delivery', 'Placed', 18.99, 26.98);

PRINT 'Food delivery database schema created successfully!';
GO
