# Food Delivery & Restaurant Management Platform Database Design

## Overview

This comprehensive database schema supports modern food delivery and restaurant management platforms including order processing, delivery logistics, menu management, restaurant operations, and customer experience tracking. The design handles complex order workflows, multi-restaurant operations, real-time delivery tracking, and enterprise food service management.

## Key Features

### 🍽️ Restaurant & Menu Management
- **Multi-restaurant portfolio management** with centralized administration and reporting
- **Dynamic menu management** with item variations, pricing, and availability tracking
- **Inventory integration** with recipe management and stock level monitoring
- **Menu optimization** with performance analytics and automated pricing adjustments

### 🚚 Order Processing & Delivery Logistics
- **Complex order workflows** with multiple order types and preparation stages
- **Real-time delivery tracking** with GPS integration and ETA calculations
- **Multi-channel ordering** supporting app, web, phone, and third-party platforms
- **Order routing optimization** with delivery zones and driver assignments

### 👨‍🍳 Kitchen & Operations Management
- **Kitchen display systems** with order prioritization and preparation tracking
- **Staff scheduling and management** with role-based access and performance tracking
- **Quality control processes** with food safety monitoring and compliance
- **Waste management** with portion control and inventory optimization

## Database Schema Highlights

### Core Tables

#### Restaurant & Location Management
```sql
-- Restaurants master table
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

-- Restaurant locations (for chains)
CREATE TABLE RestaurantLocations (
    LocationID INT IDENTITY(1,1) PRIMARY KEY,
    RestaurantID INT NOT NULL REFERENCES Restaurants(RestaurantID) ON DELETE CASCADE,
    LocationCode NVARCHAR(20) UNIQUE NOT NULL,
    LocationName NVARCHAR(100),

    -- Location-specific details
    Address NVARCHAR(MAX), -- JSON formatted
    Phone NVARCHAR(20),
    ManagerID INT,
    Capacity INT,
    OperatingHours NVARCHAR(MAX), -- JSON formatted

    -- Location status
    Status NVARCHAR(20) DEFAULT 'Active',
    IsDeliveryEnabled BIT DEFAULT 1,
    IsPickupEnabled BIT DEFAULT 1,

    -- Location-specific settings
    PrepTimeMinutes INT DEFAULT 30,
    DeliveryRadiusMiles DECIMAL(4,1) DEFAULT 5.0,
    MinimumOrderAmount DECIMAL(6,2) DEFAULT 15.00,

    -- Constraints
    CONSTRAINT UQ_RestaurantLocations_Code UNIQUE (RestaurantID, LocationCode),
    CONSTRAINT CK_RestaurantLocations_Status CHECK (Status IN ('Active', 'Inactive', 'TemporarilyClosed')),

    -- Indexes
    INDEX IX_RestaurantLocations_Restaurant (RestaurantID),
    INDEX IX_RestaurantLocations_Code (LocationCode),
    INDEX IX_RestaurantLocations_Status (Status)
);
```

#### Menu & Product Management
```sql
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

-- Menu item variants (sizes, customizations)
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

-- Menu item ingredients and recipes
CREATE TABLE MenuItemIngredients (
    IngredientID INT IDENTITY(1,1) PRIMARY KEY,
    ItemID INT NOT NULL REFERENCES MenuItems(ItemID) ON DELETE CASCADE,
    IngredientName NVARCHAR(100) NOT NULL,
    Quantity DECIMAL(8,3),
    Unit NVARCHAR(20), -- grams, ml, pieces, etc.
    IsRequired BIT DEFAULT 1,
    IsAllergen BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_MenuItemIngredients_Item UNIQUE (ItemID, IngredientName),

    -- Indexes
    INDEX IX_MenuItemIngredients_Item (ItemID),
    INDEX IX_MenuItemIngredients_IsAllergen (IsAllergen)
);
```

### Order Processing & Management

#### Customer Orders
```sql
-- Customer orders master table
CREATE TABLE Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    OrderNumber NVARCHAR(50) UNIQUE NOT NULL,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),

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
```

#### Delivery & Logistics Management
```sql
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

-- Delivery assignments and tracking
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

-- Delivery zones and routing
CREATE TABLE DeliveryZones (
    ZoneID INT IDENTITY(1,1) PRIMARY KEY,
    RestaurantID INT NOT NULL REFERENCES Restaurants(RestaurantID),
    ZoneName NVARCHAR(100) NOT NULL,
    ZoneCode NVARCHAR(20) UNIQUE NOT NULL,

    -- Geographic boundaries (JSON polygon coordinates)
    BoundaryCoordinates NVARCHAR(MAX),

    -- Zone settings
    BaseDeliveryFee DECIMAL(6,2) DEFAULT 2.99,
    AdditionalFeePerMile DECIMAL(6,2) DEFAULT 0.50,
    MinimumOrderAmount DECIMAL(6,2) DEFAULT 15.00,
    EstimatedDeliveryTime INT DEFAULT 30, -- Minutes

    -- Status
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT UQ_DeliveryZones_Restaurant UNIQUE (RestaurantID, ZoneCode),

    -- Indexes
    INDEX IX_DeliveryZones_Restaurant (RestaurantID),
    INDEX IX_DeliveryZones_IsActive (IsActive)
);
```

### Restaurant Operations & Analytics

#### Kitchen & Staff Management
```sql
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

-- Kitchen orders display
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
```

## Integration Points

### External Systems
- **Online ordering platforms**: Uber Eats, DoorDash, Grubhub integration
- **Payment processors**: Stripe, Square, PayPal for secure transactions
- **GPS and mapping**: Google Maps, Mapbox for delivery tracking and routing
- **Inventory systems**: Integration with restaurant POS and inventory management
- **Customer CRM**: Loyalty programs and customer data synchronization
- **Analytics platforms**: Google Analytics, restaurant-specific business intelligence

### API Endpoints
- **Restaurant APIs**: Menu management, availability updates, order processing
- **Order APIs**: Real-time order status, delivery tracking, customer notifications
- **Driver APIs**: Route optimization, earnings tracking, performance metrics
- **Analytics APIs**: Sales reporting, customer insights, operational metrics
- **Integration APIs**: Third-party platform synchronization, webhook notifications

## Monitoring & Analytics

### Key Performance Indicators
- **Order Performance**: Average order value, order completion time, order accuracy rate
- **Delivery Performance**: On-time delivery rate, average delivery time, customer satisfaction
- **Restaurant Performance**: Table turnover rate, food cost percentage, labor cost percentage
- **Customer Experience**: Customer retention rate, repeat order rate, Net Promoter Score
- **Financial Performance**: Revenue per available seat hour, delivery fee optimization

### Real-Time Dashboards
```sql
-- Food delivery operations dashboard
CREATE VIEW FoodDeliveryOperationsDashboard AS
SELECT
    -- Order metrics (current day)
    (SELECT COUNT(*) FROM Orders
     WHERE CAST(OrderDate AS DATE) = CAST(GETDATE() AS DATE)
     AND Status NOT IN ('Cancelled')) AS OrdersToday,

    (SELECT SUM(TotalAmount) FROM Orders
     WHERE CAST(OrderDate AS DATE) = CAST(GETDATE() AS DATE)
     AND PaymentStatus = 'Paid') AS RevenueToday,

    (SELECT AVG(TotalAmount) FROM Orders
     WHERE CAST(OrderDate AS DATE) = CAST(GETDATE() AS DATE)
     AND PaymentStatus = 'Paid') AS AverageOrderValue,

    -- Order status breakdown
    (SELECT COUNT(*) FROM Orders WHERE Status = 'Placed') AS OrdersPlaced,
    (SELECT COUNT(*) FROM Orders WHERE Status = 'Preparing') AS OrdersPreparing,
    (SELECT COUNT(*) FROM Orders WHERE Status = 'OutForDelivery') AS OrdersOutForDelivery,
    (SELECT COUNT(*) FROM Orders WHERE Status = 'Delivered') AS OrdersDelivered,

    -- Delivery performance
    (SELECT COUNT(*) FROM DeliveryAssignments
     WHERE CAST(DeliveryDate AS DATE) = CAST(GETDATE() AS DATE)
     AND Status = 'Delivered') AS DeliveriesCompletedToday,

    (SELECT AVG(DATEDIFF(MINUTE, AssignedDate, DeliveryDate)) FROM DeliveryAssignments
     WHERE CAST(DeliveryDate AS DATE) = CAST(GETDATE() AS DATE)
     AND Status = 'Delivered') AS AverageDeliveryTime,

    (SELECT COUNT(*) FROM DeliveryAssignments
     WHERE CAST(DeliveryDate AS DATE) = CAST(GETDATE() AS DATE)
     AND Status = 'Delivered'
     AND DATEDIFF(MINUTE, EstimatedDeliveryTime, DeliveryDate) <= 5) AS OnTimeDeliveries,

    -- Driver performance
    (SELECT COUNT(*) FROM DeliveryDrivers WHERE Status = 'Available') AS AvailableDrivers,
    (SELECT COUNT(*) FROM DeliveryDrivers WHERE Status = 'Busy') AS BusyDrivers,

    (SELECT AVG(AverageRating) FROM DeliveryDrivers
     WHERE TotalDeliveries > 0) AS AverageDriverRating,

    -- Restaurant performance
    (SELECT COUNT(*) FROM Restaurants WHERE Status = 'Active') AS ActiveRestaurants,

    (SELECT COUNT(*) FROM Orders o
     INNER JOIN Restaurants r ON o.RestaurantID = r.RestaurantID
     WHERE CAST(o.OrderDate AS DATE) = CAST(GETDATE() AS DATE)
     AND r.Status = 'Active') AS OrdersFromActiveRestaurants,

    -- Customer metrics
    (SELECT COUNT(DISTINCT CustomerID) FROM Orders
     WHERE CAST(OrderDate AS DATE) = CAST(GETDATE() AS DATE)) AS UniqueCustomersToday,

    (SELECT AVG(Rating) FROM Orders
     WHERE Rating IS NOT NULL
     AND CAST(OrderDate AS DATE) = CAST(GETDATE() AS DATE)) AS AverageCustomerRating,

    -- System health
    (SELECT COUNT(*) FROM Orders
     WHERE Status IN ('Placed', 'Confirmed', 'Preparing')
     AND OrderDate < DATEADD(MINUTE, -60, GETDATE())) AS OrdersDelayedOver1Hour

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This food delivery database schema provides a comprehensive foundation for modern food delivery platforms, supporting multi-restaurant operations, real-time delivery logistics, kitchen management, and enterprise food service analytics while maintaining high performance and customer satisfaction.
