-- Retail & Point of Sale Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE RetailDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE RetailDB;
GO

-- Configure database for retail performance
ALTER DATABASE RetailDB
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
-- PRODUCT MANAGEMENT
-- =============================================

-- Products
CREATE TABLE Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductCode NVARCHAR(50) UNIQUE NOT NULL,
    ProductName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    ProductType NVARCHAR(20) DEFAULT 'Physical', -- Physical, Digital, Service
    CategoryID INT,
    Brand NVARCHAR(100),
    Manufacturer NVARCHAR(100),

    -- Pricing and cost
    BasePrice DECIMAL(10,2) NOT NULL,
    Cost DECIMAL(10,2),
    MSRP DECIMAL(10,2),
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Inventory and availability
    IsActive BIT DEFAULT 1,
    IsDiscontinued BIT DEFAULT 0,
    TrackInventory BIT DEFAULT 1,
    ReorderPoint INT DEFAULT 0,
    TargetStockLevel INT,

    -- Product attributes
    Weight DECIMAL(8,3), -- In kg
    Dimensions NVARCHAR(50), -- LxWxH format
    Color NVARCHAR(50),
    Size NVARCHAR(50),
    Material NVARCHAR(100),

    -- Metadata
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),
    Tags NVARCHAR(MAX), -- JSON array of tags

    -- Constraints
    CONSTRAINT CK_Products_Type CHECK (ProductType IN ('Physical', 'Digital', 'Service')),
    CONSTRAINT CK_Products_Price CHECK (BasePrice >= 0),
    CONSTRAINT CK_Products_Cost CHECK (Cost >= 0),

    -- Indexes
    INDEX IX_Products_Code (ProductCode),
    INDEX IX_Products_Name (ProductName),
    INDEX IX_Products_Category (CategoryID),
    INDEX IX_Products_Brand (Brand),
    INDEX IX_Products_IsActive (IsActive),
    INDEX IX_Products_Type (ProductType)
);

-- Product variants
CREATE TABLE ProductVariants (
    VariantID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    VariantCode NVARCHAR(50) UNIQUE NOT NULL,
    VariantName NVARCHAR(200),
    SKU NVARCHAR(50) UNIQUE,
    AdditionalPrice DECIMAL(8,2) DEFAULT 0,

    -- Variant attributes
    Color NVARCHAR(50),
    Size NVARCHAR(50),
    Style NVARCHAR(50),
    Material NVARCHAR(100),

    -- Inventory specific to variant
    StockQuantity INT DEFAULT 0,
    ReservedQuantity INT DEFAULT 0,
    AvailableQuantity AS (StockQuantity - ReservedQuantity),

    -- Images and media
    ImageURL NVARCHAR(500),
    ThumbnailURL NVARCHAR(500),

    -- Constraints
    CONSTRAINT CK_ProductVariants_Price CHECK (AdditionalPrice >= 0),
    CONSTRAINT CK_ProductVariants_Stock CHECK (StockQuantity >= 0),
    CONSTRAINT CK_ProductVariants_Reserved CHECK (ReservedQuantity >= 0),

    -- Indexes
    INDEX IX_ProductVariants_Product (ProductID),
    INDEX IX_ProductVariants_Code (VariantCode),
    INDEX IX_ProductVariants_SKU (SKU),
    INDEX IX_ProductVariants_Available (AvailableQuantity)
);

-- Product categories
CREATE TABLE ProductCategories (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL,
    ParentCategoryID INT REFERENCES ProductCategories(CategoryID),
    Description NVARCHAR(MAX),
    ImageURL NVARCHAR(500),
    IsActive BIT DEFAULT 1,
    DisplayOrder INT DEFAULT 0,

    -- SEO and marketing
    MetaTitle NVARCHAR(100),
    MetaDescription NVARCHAR(300),
    URLSlug NVARCHAR(100) UNIQUE,

    -- Constraints
    CONSTRAINT CK_ProductCategories_NoSelfReference CHECK (CategoryID != ParentCategoryID),

    -- Indexes
    INDEX IX_ProductCategories_Parent (ParentCategoryID),
    INDEX IX_ProductCategories_IsActive (IsActive),
    INDEX IX_ProductCategories_Order (DisplayOrder),
    INDEX IX_ProductCategories_Slug (URLSlug)
);

-- =============================================
-- INVENTORY MANAGEMENT
-- =============================================

-- Inventory locations
CREATE TABLE InventoryLocations (
    LocationID INT IDENTITY(1,1) PRIMARY KEY,
    LocationCode NVARCHAR(20) UNIQUE NOT NULL,
    LocationName NVARCHAR(100) NOT NULL,
    LocationType NVARCHAR(20) DEFAULT 'Store', -- Store, Warehouse, DistributionCenter
    Address NVARCHAR(MAX), -- JSON formatted address
    Phone NVARCHAR(20),
    ManagerID INT, -- Store manager

    -- Location settings
    IsActive BIT DEFAULT 1,
    OperatingHours NVARCHAR(MAX), -- JSON: {"monday": "9-5", "tuesday": "9-5"}
    TimeZone NVARCHAR(50) DEFAULT 'UTC',

    -- Constraints
    CONSTRAINT CK_InventoryLocations_Type CHECK (LocationType IN ('Store', 'Warehouse', 'DistributionCenter', 'Online')),

    -- Indexes
    INDEX IX_InventoryLocations_Code (LocationCode),
    INDEX IX_InventoryLocations_Type (LocationType),
    INDEX IX_InventoryLocations_IsActive (IsActive)
);

-- Stock levels
CREATE TABLE StockLevels (
    StockID INT IDENTITY(1,1) PRIMARY KEY,
    LocationID INT NOT NULL REFERENCES InventoryLocations(LocationID),
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    VariantID INT REFERENCES ProductVariants(VariantID),

    -- Stock quantities
    QuantityOnHand INT DEFAULT 0,
    QuantityReserved INT DEFAULT 0,
    QuantityAvailable AS (QuantityOnHand - QuantityReserved),
    QuantityOnOrder INT DEFAULT 0,

    -- Stock tracking
    LastCountDate DATETIME2,
    LastCountQuantity INT,
    ReorderPoint INT DEFAULT 0,
    TargetStockLevel INT,

    -- Location-specific pricing
    LocalPrice DECIMAL(10,2),
    LocalCost DECIMAL(10,2),

    -- Constraints
    CONSTRAINT UQ_StockLevels_LocationProduct UNIQUE (LocationID, ProductID, VariantID),
    CONSTRAINT CK_StockLevels_OnHand CHECK (QuantityOnHand >= 0),
    CONSTRAINT CK_StockLevels_Reserved CHECK (QuantityReserved >= 0),
    CONSTRAINT CK_StockLevels_OnOrder CHECK (QuantityOnOrder >= 0),

    -- Indexes
    INDEX IX_StockLevels_Location (LocationID),
    INDEX IX_StockLevels_Product (ProductID, VariantID),
    INDEX IX_StockLevels_Available (QuantityAvailable),
    INDEX IX_StockLevels_Reorder (LocationID) WHERE QuantityOnHand <= ReorderPoint
);

-- Stock movements
CREATE TABLE StockMovements (
    MovementID INT IDENTITY(1,1) PRIMARY KEY,
    LocationID INT NOT NULL REFERENCES InventoryLocations(LocationID),
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    VariantID INT REFERENCES ProductVariants(VariantID),

    -- Movement details
    MovementType NVARCHAR(20) NOT NULL, -- Sale, Purchase, Transfer, Adjustment, Return
    Quantity INT NOT NULL,
    ReferenceNumber NVARCHAR(50), -- Order/Sale/Transfer number
    ReferenceType NVARCHAR(20), -- Sale, PurchaseOrder, Transfer, Adjustment

    -- Movement metadata
    MovementDate DATETIME2 DEFAULT GETDATE(),
    Reason NVARCHAR(MAX),
    AuthorizedBy INT,
    Notes NVARCHAR(MAX),

    -- Before/after quantities for audit
    QuantityBefore INT,
    QuantityAfter INT,

    -- Constraints
    CONSTRAINT CK_StockMovements_Type CHECK (MovementType IN ('Sale', 'Purchase', 'Transfer', 'Adjustment', 'Return', 'Damage', 'Loss')),
    CONSTRAINT CK_StockMovements_ReferenceType CHECK (ReferenceType IN ('Sale', 'PurchaseOrder', 'Transfer', 'Adjustment', 'Return')),

    -- Indexes
    INDEX IX_StockMovements_Location (LocationID, MovementDate DESC),
    INDEX IX_StockMovements_Product (ProductID, VariantID, MovementDate DESC),
    INDEX IX_StockMovements_Type (MovementType, MovementDate DESC),
    INDEX IX_StockMovements_Reference (ReferenceNumber, ReferenceType)
);

-- =============================================
-- SALES & TRANSACTIONS
-- =============================================

-- Sales transactions
CREATE TABLE SalesTransactions (
    TransactionID INT IDENTITY(1,1) PRIMARY KEY,
    TransactionNumber NVARCHAR(50) UNIQUE NOT NULL,
    LocationID INT REFERENCES InventoryLocations(LocationID),
    CustomerID INT REFERENCES Customers(CustomerID),

    -- Transaction details
    TransactionDate DATETIME2 DEFAULT GETDATE(),
    TransactionType NVARCHAR(20) DEFAULT 'Sale', -- Sale, Return, Exchange
    Channel NVARCHAR(20) DEFAULT 'InStore', -- InStore, Online, Mobile, Phone
    Status NVARCHAR(20) DEFAULT 'Completed', -- Pending, Completed, Cancelled, Refunded

    -- Financial summary
    Subtotal DECIMAL(10,2) NOT NULL,
    TaxAmount DECIMAL(10,2) DEFAULT 0,
    DiscountAmount DECIMAL(10,2) DEFAULT 0,
    ShippingAmount DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(10,2) NOT NULL,

    -- Payment information
    PaymentMethod NVARCHAR(20), -- Cash, CreditCard, DebitCard, GiftCard, Check
    PaymentReference NVARCHAR(100),
    CurrencyCode NVARCHAR(3) DEFAULT 'USD',

    -- Transaction metadata
    SalesAssociateID INT,
    RegisterID INT,
    ReceiptNumber NVARCHAR(50),
    Notes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_SalesTransactions_Type CHECK (TransactionType IN ('Sale', 'Return', 'Exchange', 'Void')),
    CONSTRAINT CK_SalesTransactions_Channel CHECK (Channel IN ('InStore', 'Online', 'Mobile', 'Phone', 'Kiosk')),
    CONSTRAINT CK_SalesTransactions_Status CHECK (Status IN ('Pending', 'Completed', 'Cancelled', 'Refunded')),
    CONSTRAINT CK_SalesTransactions_Amounts CHECK (TotalAmount >= 0),

    -- Indexes
    INDEX IX_SalesTransactions_Number (TransactionNumber),
    INDEX IX_SalesTransactions_Location (LocationID, TransactionDate DESC),
    INDEX IX_SalesTransactions_Customer (CustomerID, TransactionDate DESC),
    INDEX IX_SalesTransactions_Type (TransactionType, TransactionDate DESC),
    INDEX IX_SalesTransactions_Status (Status),
    INDEX IX_SalesTransactions_Date (TransactionDate DESC),
    INDEX IX_SalesTransactions_Channel (Channel, TransactionDate DESC)
);

-- Transaction line items
CREATE TABLE TransactionItems (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    TransactionID INT NOT NULL REFERENCES SalesTransactions(TransactionID) ON DELETE CASCADE,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    VariantID INT REFERENCES ProductVariants(VariantID),

    -- Item details
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    LineTotal DECIMAL(10,2) NOT NULL,
    DiscountAmount DECIMAL(8,2) DEFAULT 0,
    TaxAmount DECIMAL(8,2) DEFAULT 0,

    -- Item metadata
    SerialNumber NVARCHAR(100),
    WarrantyPeriod NVARCHAR(50),
    ReturnEligible BIT DEFAULT 1,
    ReturnPeriodDays INT DEFAULT 30,

    -- Constraints
    CONSTRAINT CK_TransactionItems_Quantity CHECK (Quantity != 0),
    CONSTRAINT CK_TransactionItems_Price CHECK (UnitPrice >= 0),

    -- Indexes
    INDEX IX_TransactionItems_Transaction (TransactionID),
    INDEX IX_TransactionItems_Product (ProductID, VariantID)
);

-- Returns
CREATE TABLE Returns (
    ReturnID INT IDENTITY(1,1) PRIMARY KEY,
    ReturnNumber NVARCHAR(50) UNIQUE NOT NULL,
    OriginalTransactionID INT NOT NULL REFERENCES SalesTransactions(TransactionID),
    CustomerID INT REFERENCES Customers(CustomerID),

    -- Return details
    ReturnDate DATETIME2 DEFAULT GETDATE(),
    ReturnReason NVARCHAR(100),
    Status NVARCHAR(20) DEFAULT 'Pending', -- Pending, Approved, Received, Processed, Rejected

    -- Financial details
    ReturnAmount DECIMAL(10,2) NOT NULL,
    RefundAmount DECIMAL(10,2),
    ExchangeTransactionID INT REFERENCES SalesTransactions(TransactionID),

    -- Processing information
    ProcessedBy INT,
    ProcessedDate DATETIME2,
    AuthorizedBy INT,
    AuthorizedDate DATETIME2,
    Notes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_Returns_Status CHECK (Status IN ('Pending', 'Approved', 'Received', 'Processed', 'Rejected', 'Cancelled')),

    -- Indexes
    INDEX IX_Returns_Number (ReturnNumber),
    INDEX IX_Returns_OriginalTransaction (OriginalTransactionID),
    INDEX IX_Returns_Customer (CustomerID),
    INDEX IX_Returns_Status (Status),
    INDEX IX_Returns_Date (ReturnDate DESC)
);

-- =============================================
-- CUSTOMER & LOYALTY MANAGEMENT
-- =============================================

-- Customer profiles
CREATE TABLE CustomerProfiles (
    ProfileID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    ProfileData NVARCHAR(MAX), -- JSON: preferences, demographics, interests

    -- Loyalty program
    LoyaltyNumber NVARCHAR(50) UNIQUE,
    LoyaltyTier NVARCHAR(20) DEFAULT 'Bronze', -- Bronze, Silver, Gold, Platinum
    LoyaltyPoints INT DEFAULT 0,
    LifetimePoints INT DEFAULT 0,
    TierStartDate DATETIME2,
    TierExpiryDate DATETIME2,

    -- Purchase history summary
    TotalPurchases INT DEFAULT 0,
    TotalSpent DECIMAL(12,2) DEFAULT 0,
    AverageOrderValue DECIMAL(10,2) DEFAULT 0,
    LastPurchaseDate DATETIME2,
    FavoriteCategory NVARCHAR(100),

    -- Communication preferences
    EmailOptIn BIT DEFAULT 1,
    SmsOptIn BIT DEFAULT 0,
    MarketingOptIn BIT DEFAULT 1,
    PreferredContactMethod NVARCHAR(20) DEFAULT 'Email',

    -- Constraints
    CONSTRAINT UQ_CustomerProfiles_Customer UNIQUE (CustomerID),
    CONSTRAINT CK_CustomerProfiles_Tier CHECK (LoyaltyTier IN ('Bronze', 'Silver', 'Gold', 'Platinum')),
    CONSTRAINT CK_CustomerProfiles_ContactMethod CHECK (PreferredContactMethod IN ('Email', 'Phone', 'SMS', 'Mail')),

    -- Indexes
    INDEX IX_CustomerProfiles_LoyaltyNumber (LoyaltyNumber),
    INDEX IX_CustomerProfiles_Tier (LoyaltyTier),
    INDEX IX_CustomerProfiles_Points (LoyaltyPoints DESC),
    INDEX IX_CustomerProfiles_LastPurchase (LastPurchaseDate DESC)
);

-- Customer purchase history
CREATE TABLE CustomerPurchaseHistory (
    HistoryID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    TransactionID INT NOT NULL REFERENCES SalesTransactions(TransactionID),

    -- Purchase summary
    PurchaseDate DATETIME2 DEFAULT GETDATE(),
    TotalAmount DECIMAL(10,2) NOT NULL,
    ItemsPurchased INT NOT NULL,
    PointsEarned INT DEFAULT 0,
    PointsRedeemed INT DEFAULT 0,

    -- Purchase analytics
    PurchaseChannel NVARCHAR(20),
    PurchaseLocation NVARCHAR(100),
    PromotionApplied NVARCHAR(100),

    -- Constraints
    CONSTRAINT UQ_CustomerPurchaseHistory_Unique UNIQUE (CustomerID, TransactionID),

    -- Indexes
    INDEX IX_CustomerPurchaseHistory_Customer (CustomerID, PurchaseDate DESC),
    INDEX IX_CustomerPurchaseHistory_Transaction (TransactionID),
    INDEX IX_CustomerPurchaseHistory_Date (PurchaseDate DESC),
    INDEX IX_CustomerPurchaseHistory_Channel (PurchaseChannel)
);

-- =============================================
-- PROMOTIONS & PRICING
-- =============================================

-- Pricing rules
CREATE TABLE PricingRules (
    RuleID INT IDENTITY(1,1) PRIMARY KEY,
    RuleName NVARCHAR(200) NOT NULL,
    RuleType NVARCHAR(20) NOT NULL, -- FixedPrice, PercentageDiscount, BuyXGetY, Bundle
    Description NVARCHAR(MAX),

    -- Rule conditions (JSON)
    Conditions NVARCHAR(MAX), -- {"categories": ["electronics"], "min_quantity": 2}

    -- Rule actions (JSON)
    Actions NVARCHAR(MAX), -- {"discount_percentage": 10, "max_discount": 50}

    -- Rule validity
    StartDate DATETIME2,
    EndDate DATETIME2,
    IsActive BIT DEFAULT 1,
    Priority INT DEFAULT 0, -- Higher priority rules apply first

    -- Constraints
    CONSTRAINT CK_PricingRules_Type CHECK (RuleType IN ('FixedPrice', 'PercentageDiscount', 'AmountDiscount', 'BuyXGetY', 'Bundle', 'VolumeDiscount')),

    -- Indexes
    INDEX IX_PricingRules_Type (RuleType),
    INDEX IX_PricingRules_IsActive (IsActive),
    INDEX IX_PricingRules_Priority (Priority DESC),
    INDEX IX_PricingRules_StartDate (StartDate),
    INDEX IX_PricingRules_EndDate (EndDate)
);

-- Product promotions
CREATE TABLE ProductPromotions (
    PromotionID INT IDENTITY(1,1) PRIMARY KEY,
    PromotionName NVARCHAR(200) NOT NULL,
    PromotionType NVARCHAR(20) NOT NULL, -- Seasonal, Clearance, FlashSale, Loyalty
    Description NVARCHAR(MAX),

    -- Promotion details
    DiscountType NVARCHAR(20), -- Percentage, FixedAmount, BuyXGetY
    DiscountValue DECIMAL(10,2),
    MinimumPurchase DECIMAL(10,2),
    MaximumDiscount DECIMAL(10,2),

    -- Validity
    StartDate DATETIME2 NOT NULL,
    EndDate DATETIME2 NOT NULL,
    IsActive BIT DEFAULT 1,

    -- Target products (JSON array of product IDs or categories)
    TargetProducts NVARCHAR(MAX),
    TargetCustomers NVARCHAR(MAX), -- JSON: loyalty tiers, customer segments

    -- Usage tracking
    UsageLimit INT,
    UsageCount INT DEFAULT 0,
    PerCustomerLimit INT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_ProductPromotions_Type CHECK (PromotionType IN ('Seasonal', 'Clearance', 'FlashSale', 'Loyalty', 'NewCustomer', 'Bundle')),
    CONSTRAINT CK_ProductPromotions_DiscountType CHECK (DiscountType IN ('Percentage', 'FixedAmount', 'BuyXGetY', 'FreeShipping')),

    -- Indexes
    INDEX IX_ProductPromotions_Type (PromotionType),
    INDEX IX_ProductPromotions_IsActive (IsActive),
    INDEX IX_ProductPromotions_StartDate (StartDate),
    INDEX IX_ProductPromotions_EndDate (EndDate)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Product catalog view
CREATE VIEW vw_ProductCatalog
AS
SELECT
    p.ProductID,
    p.ProductCode,
    p.ProductName,
    p.Description,
    pc.CategoryName,
    p.Brand,
    p.BasePrice,
    p.MSRP,
    p.IsActive,
    p.IsDiscontinued,

    -- Stock summary across all locations
    (SELECT SUM(sl.QuantityOnHand) FROM StockLevels sl WHERE sl.ProductID = p.ProductID) AS TotalStock,
    (SELECT SUM(sl.QuantityAvailable) FROM StockLevels sl WHERE sl.ProductID = p.ProductID) AS TotalAvailable,

    -- Variant count
    (SELECT COUNT(*) FROM ProductVariants pv WHERE pv.ProductID = p.ProductID) AS VariantCount,

    -- Recent sales
    (SELECT SUM(ti.Quantity) FROM TransactionItems ti
     INNER JOIN SalesTransactions st ON ti.TransactionID = st.TransactionID
     WHERE ti.ProductID = p.ProductID AND st.Status = 'Completed'
     AND st.TransactionDate >= DATEADD(MONTH, -1, GETDATE())) AS SalesLastMonth

FROM Products p
LEFT JOIN ProductCategories pc ON p.CategoryID = pc.CategoryID
WHERE p.IsActive = 1;
GO

-- Sales performance view
CREATE VIEW vw_SalesPerformance
AS
SELECT
    st.TransactionID,
    st.TransactionNumber,
    st.TransactionDate,
    st.TotalAmount,
    st.Channel,
    st.PaymentMethod,
    c.CompanyName AS CustomerName,
    cp.LoyaltyTier,
    il.LocationName,

    -- Transaction details
    (SELECT COUNT(*) FROM TransactionItems ti WHERE ti.TransactionID = st.TransactionID) AS ItemCount,
    (SELECT SUM(ti.Quantity) FROM TransactionItems ti WHERE ti.TransactionID = st.TransactionID) AS TotalQuantity,

    -- Customer segment
    CASE
        WHEN cp.TotalSpent > 10000 THEN 'High Value'
        WHEN cp.TotalSpent > 1000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS CustomerSegment

FROM SalesTransactions st
LEFT JOIN Customers c ON st.CustomerID = c.CustomerID
LEFT JOIN CustomerProfiles cp ON st.CustomerID = cp.CustomerID
LEFT JOIN InventoryLocations il ON st.LocationID = il.LocationID
WHERE st.Status = 'Completed';
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update stock levels on sales
CREATE TRIGGER TR_TransactionItems_UpdateStock
ON TransactionItems
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Get location from transaction
    DECLARE @LocationID INT;
    SELECT @LocationID = st.LocationID
    FROM SalesTransactions st
    INNER JOIN inserted i ON st.TransactionID = i.TransactionID;

    -- Update stock levels (simplified - assumes single location for demo)
    UPDATE sl
    SET sl.QuantityOnHand = sl.QuantityOnHand - i.Quantity,
        sl.LastCountDate = GETDATE()
    FROM StockLevels sl
    INNER JOIN inserted i ON sl.ProductID = i.ProductID
        AND (sl.VariantID = i.VariantID OR (sl.VariantID IS NULL AND i.VariantID IS NULL))
    WHERE sl.LocationID = @LocationID;
END;
GO

-- Update customer loyalty points
CREATE TRIGGER TR_SalesTransactions_UpdateLoyalty
ON SalesTransactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Calculate points earned (1 point per $10 spent)
    DECLARE @PointsEarned INT;
    SELECT @PointsEarned = FLOOR(i.TotalAmount / 10)
    FROM inserted i;

    -- Update customer profile
    UPDATE cp
    SET cp.LoyaltyPoints = cp.LoyaltyPoints + @PointsEarned,
        cp.LifetimePoints = cp.LifetimePoints + @PointsEarned,
        cp.TotalPurchases = cp.TotalPurchases + 1,
        cp.TotalSpent = cp.TotalSpent + i.TotalAmount,
        cp.LastPurchaseDate = i.TransactionDate,
        cp.AverageOrderValue = (cp.TotalSpent + i.TotalAmount) / (cp.TotalPurchases + 1)
    FROM CustomerProfiles cp
    INNER JOIN inserted i ON cp.CustomerID = i.CustomerID;
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Process sale transaction procedure
CREATE PROCEDURE sp_ProcessSale
    @LocationID INT,
    @CustomerID INT = NULL,
    @Items NVARCHAR(MAX), -- JSON array of items: [{"productId": 1, "variantId": null, "quantity": 2, "price": 29.99}]
    @PaymentMethod NVARCHAR(20),
    @SalesAssociateID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @TransactionID INT;
    DECLARE @TransactionNumber NVARCHAR(50);
    DECLARE @Subtotal DECIMAL(10,2) = 0;
    DECLARE @TaxRate DECIMAL(5,4) = 0.08; -- 8% tax rate

    -- Generate transaction number
    SET @TransactionNumber = 'TXN-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                           RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                           RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS NVARCHAR(6)), 6);

    -- Create transaction header
    INSERT INTO SalesTransactions (
        TransactionNumber, LocationID, CustomerID, TransactionType, Channel,
        Status, Subtotal, PaymentMethod, SalesAssociateID
    )
    VALUES (
        @TransactionNumber, @LocationID, @CustomerID, 'Sale', 'InStore',
        'Completed', 0, @PaymentMethod, @SalesAssociateID
    );

    SET @TransactionID = SCOPE_IDENTITY();

    -- Process items (simplified - in production, parse JSON and process each item)
    -- This is a placeholder for the actual item processing logic

    -- Calculate totals (placeholder values)
    SET @Subtotal = 100.00; -- Would be calculated from items
    UPDATE SalesTransactions
    SET Subtotal = @Subtotal,
        TaxAmount = @Subtotal * @TaxRate,
        TotalAmount = @Subtotal + (@Subtotal * @TaxRate)
    WHERE TransactionID = @TransactionID;

    SELECT @TransactionID AS TransactionID, @TransactionNumber AS TransactionNumber;

    COMMIT TRANSACTION;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample customer
INSERT INTO Customers (CustomerNumber, CompanyName, PrimaryEmail) VALUES
('CUST-000001', 'John Doe', 'john.doe@email.com');

-- Insert sample category
INSERT INTO ProductCategories (CategoryName, Description) VALUES
('Electronics', 'Electronic devices and accessories');

-- Insert sample product
INSERT INTO Products (ProductCode, ProductName, CategoryID, BasePrice, Brand) VALUES
('PROD-001', 'Wireless Headphones', 1, 199.99, 'AudioTech');

-- Insert sample variant
INSERT INTO ProductVariants (ProductID, VariantCode, VariantName, SKU, Color) VALUES
(1, 'PROD-001-BLK', 'Wireless Headphones - Black', 'ATH-WH-BLK', 'Black');

-- Insert sample location
INSERT INTO InventoryLocations (LocationCode, LocationName, LocationType) VALUES
('STORE-001', 'Main Store', 'Store');

-- Insert sample stock
INSERT INTO StockLevels (LocationID, ProductID, VariantID, QuantityOnHand) VALUES
(1, 1, 1, 50);

PRINT 'Retail database schema created successfully!';
GO
