# Retail & Point of Sale Platform Database Design

## Overview

This comprehensive database schema supports modern retail and point-of-sale platforms including inventory management, sales transactions, customer loyalty programs, multi-channel operations, and retail analytics. The design handles complex product catalogs, pricing strategies, inventory tracking, and enterprise retail operations.

## Key Features

### 🛒 Product & Inventory Management
- **Multi-dimensional product catalog** with variants, bundles, and categories
- **Real-time inventory tracking** across multiple locations and channels
- **Advanced pricing strategies** with promotions, discounts, and dynamic pricing
- **Supplier and vendor management** with procurement and ordering workflows

### 💰 Point of Sale & Transactions
- **Multi-channel sales processing** supporting in-store, online, and mobile transactions
- **Complex transaction handling** with returns, exchanges, and gift cards
- **Payment processing integration** with multiple payment methods and currencies
- **Receipt and audit trail** management for compliance and customer service

### 👥 Customer & Loyalty Management
- **Customer profiling** with purchase history, preferences, and segmentation
- **Loyalty program management** with points, rewards, and tier structures
- **Personalized marketing** with targeted promotions and recommendations
- **Customer service tracking** with complaints, returns, and satisfaction metrics

## Database Schema Highlights

### Core Tables

#### Product Management
```sql
-- Product master table with comprehensive retail data
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

-- Product variants (colors, sizes, etc.)
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
```

#### Inventory & Stock Management
```sql
-- Inventory locations (stores, warehouses)
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

-- Stock levels by location and variant
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

-- Stock movements and adjustments
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
```

### Sales & Transactions

#### Sales Transactions
```sql
-- Sales transactions master table
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

-- Returns and exchanges
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
```

#### Customer & Loyalty Management
```sql
-- Customer profiles (extending the basic customer table)
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
```

### Promotions & Pricing

#### Pricing & Promotions
```sql
-- Pricing rules and strategies
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
```

## Integration Points

### External Systems
- **Payment processors**: Stripe, Square, PayPal for transaction processing
- **POS systems**: Square, Toast, Clover for in-store operations
- **Inventory management**: TradeGecko, Cin7 for warehouse operations
- **Loyalty platforms**: Loyalty Gator, FiveStars for customer programs
- **Marketing automation**: Klaviyo, Mailchimp for customer communications
- **Analytics platforms**: Google Analytics, Adobe Analytics for retail insights

### API Endpoints
- **Product APIs**: Catalog management, pricing, inventory updates
- **Transaction APIs**: Sales processing, returns, exchanges, receipts
- **Customer APIs**: Profile management, loyalty, purchase history
- **Inventory APIs**: Stock levels, transfers, reorder alerts
- **Analytics APIs**: Sales reports, customer insights, performance metrics

## Monitoring & Analytics

### Key Performance Indicators
- **Sales Performance**: Daily/weekly/monthly sales, average transaction value, conversion rates
- **Inventory Management**: Stock turnover, out-of-stock incidents, inventory accuracy
- **Customer Metrics**: Customer acquisition cost, lifetime value, retention rates, loyalty program engagement
- **Product Performance**: Best-selling items, profit margins, category performance
- **Operational Efficiency**: Transaction processing time, checkout abandonment rates

### Real-Time Dashboards
```sql
-- Retail operations dashboard
CREATE VIEW RetailOperationsDashboard AS
SELECT
    -- Sales metrics (current day)
    (SELECT SUM(TotalAmount) FROM SalesTransactions
     WHERE CAST(TransactionDate AS DATE) = CAST(GETDATE() AS DATE)
     AND Status = 'Completed') AS TodaySales,

    (SELECT COUNT(*) FROM SalesTransactions
     WHERE CAST(TransactionDate AS DATE) = CAST(GETDATE() AS DATE)
     AND Status = 'Completed') AS TodayTransactions,

    (SELECT AVG(TotalAmount) FROM SalesTransactions
     WHERE CAST(TransactionDate AS DATE) = CAST(GETDATE() AS DATE)
     AND Status = 'Completed') AS AvgTransactionValue,

    -- Inventory metrics
    (SELECT COUNT(*) FROM StockLevels
     WHERE QuantityOnHand <= ReorderPoint) AS ItemsBelowReorderPoint,

    (SELECT SUM(QuantityOnHand * p.BasePrice) FROM StockLevels sl
     INNER JOIN Products p ON sl.ProductID = p.ProductID) AS TotalInventoryValue,

    (SELECT COUNT(*) FROM StockMovements
     WHERE MovementType = 'Sale'
     AND CAST(MovementDate AS DATE) = CAST(GETDATE() AS DATE)) AS ItemsSoldToday,

    -- Customer metrics (current month)
    (SELECT COUNT(*) FROM CustomerProfiles
     WHERE TierStartDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS NewCustomersThisMonth,

    (SELECT AVG(LoyaltyPoints) FROM CustomerProfiles
     WHERE LoyaltyPoints > 0) AS AvgLoyaltyPoints,

    (SELECT COUNT(*) FROM CustomerPurchaseHistory
     WHERE PurchaseDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS ActiveCustomersThisMonth,

    -- Returns and exchanges
    (SELECT COUNT(*) FROM Returns
     WHERE MONTH(ReturnDate) = MONTH(GETDATE())
     AND YEAR(ReturnDate) = YEAR(GETDATE())) AS ReturnsThisMonth,

    (SELECT SUM(ReturnAmount) FROM Returns
     WHERE MONTH(ReturnDate) = MONTH(GETDATE())
     AND YEAR(ReturnDate) = YEAR(GETDATE())) AS ReturnValueThisMonth,

    -- Channel performance
    (SELECT SUM(TotalAmount) FROM SalesTransactions
     WHERE Channel = 'Online'
     AND MONTH(TransactionDate) = MONTH(GETDATE())
     AND YEAR(TransactionDate) = YEAR(GETDATE())) AS OnlineSalesThisMonth,

    (SELECT SUM(TotalAmount) FROM SalesTransactions
     WHERE Channel = 'InStore'
     AND MONTH(TransactionDate) = MONTH(GETDATE())
     AND YEAR(TransactionDate) = YEAR(GETDATE())) AS InStoreSalesThisMonth,

    -- Top performing categories
    (SELECT TOP 1 pc.CategoryName FROM TransactionItems ti
     INNER JOIN Products p ON ti.ProductID = p.ProductID
     INNER JOIN ProductCategories pc ON p.CategoryID = pc.CategoryID
     WHERE ti.TransactionID IN (
         SELECT TransactionID FROM SalesTransactions
         WHERE MONTH(TransactionDate) = MONTH(GETDATE())
         AND YEAR(TransactionDate) = YEAR(GETDATE())
     )
     GROUP BY pc.CategoryID, pc.CategoryName
     ORDER BY SUM(ti.LineTotal) DESC) AS TopCategory

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This retail database schema provides a comprehensive foundation for modern retail platforms, supporting multi-channel operations, inventory management, customer loyalty, and enterprise retail analytics while maintaining high performance and scalability.
