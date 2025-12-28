-- ============================================
-- E-COMMERCE PLATFORM SCHEMA DESIGN (SQL Server)
-- ============================================
-- Comprehensive schema for online shopping, marketplace, and quick commerce
-- Supports products, orders, payments, shipping, inventory, reviews, and analytics
-- Adapted for SQL Server with clustered indexes, filegroups, temporal tables, and SQL Server-specific features

-- ============================================
-- CORE ENTITIES
-- ============================================

-- Users (Customers, Sellers, Administrators)
CREATE TABLE Users
(
    UserID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    Email NVARCHAR(255) NOT NULL,
    PasswordHash NVARCHAR(255),
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Phone NVARCHAR(20),
    DateOfBirth DATE,
    Gender NVARCHAR(10) CHECK (Gender IN ('male', 'female', 'other', 'prefer_not_to_say')),

    -- Account settings
    EmailVerified BIT DEFAULT 0,
    PhoneVerified BIT DEFAULT 0,
    IsActive BIT DEFAULT 1,
    UserType NVARCHAR(20) DEFAULT 'customer' CHECK (UserType IN ('customer', 'seller', 'admin', 'moderator')),
    PreferredLanguage NVARCHAR(5) DEFAULT 'en',

    -- Marketing preferences
    MarketingEmail BIT DEFAULT 0,
    MarketingSMS BIT DEFAULT 0,
    MarketingPush BIT DEFAULT 0,

    -- Authentication
    LastLoginAt DATETIME2,
    LoginCount INT DEFAULT 0,

    -- Timestamps
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    CONSTRAINT UQ_Users_Email UNIQUE (Email),
    CONSTRAINT CK_Email_Format CHECK (Email LIKE '%_@_%._%')
);

-- Full-text search index on user names and email
CREATE FULLTEXT INDEX ON Users(FirstName, LastName, Email) KEY INDEX PK_Users;

-- User addresses for shipping and billing
CREATE TABLE Addresses
(
    AddressID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID) ON DELETE CASCADE,

    -- Address components
    AddressType NVARCHAR(20) DEFAULT 'shipping' CHECK (AddressType IN ('shipping', 'billing')),
    IsDefault BIT DEFAULT 0,
    Label NVARCHAR(50), -- e.g., 'Home', 'Work', 'Mom''s house'

    -- Address fields
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Company NVARCHAR(100),
    StreetAddress NVARCHAR(255) NOT NULL,
    Apartment NVARCHAR(50),
    City NVARCHAR(100) NOT NULL,
    State NVARCHAR(100),
    PostalCode NVARCHAR(20) NOT NULL,
    Country NVARCHAR(100) DEFAULT 'USA',

    -- Geographic data (for delivery optimization)
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),
    Geolocation GEOGRAPHY, -- SQL Server spatial type

    -- Contact info
    Phone NVARCHAR(20),

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_Addresses_UserID (UserID),
    INDEX IX_Addresses_Geolocation (Geolocation) USING GEOGRAPHY_GRID
);

-- ============================================
-- PRODUCT CATALOG
-- ============================================

-- Product categories (hierarchical)
CREATE TABLE Categories
(
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Slug NVARCHAR(120) NOT NULL,
    Description NVARCHAR(MAX),
    ParentCategoryID INT NULL REFERENCES Categories(CategoryID),
    DisplayOrder INT DEFAULT 0,

    -- Category metadata
    ImageURL NVARCHAR(500),
    IsActive BIT DEFAULT 1,
    MetaTitle NVARCHAR(60),
    MetaDescription NVARCHAR(160),

    -- SEO and analytics
    Featured BIT DEFAULT 0,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    CONSTRAINT UQ_Categories_Slug UNIQUE (Slug),
    INDEX IX_Categories_Parent (ParentCategoryID),
    INDEX IX_Categories_Active (IsActive, DisplayOrder)
);

-- Full-text search on categories
CREATE FULLTEXT INDEX ON Categories(Name, Description) KEY INDEX PK_Categories;

-- Brands/Manufacturers
CREATE TABLE Brands
(
    BrandID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Slug NVARCHAR(120) NOT NULL,
    Description NVARCHAR(MAX),
    LogoURL NVARCHAR(500),
    WebsiteURL NVARCHAR(500),
    IsActive BIT DEFAULT 1,

    -- Brand verification
    IsVerified BIT DEFAULT 0,
    VerificationDocuments NVARCHAR(MAX), -- JSON string

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    CONSTRAINT UQ_Brands_Name UNIQUE (Name),
    CONSTRAINT UQ_Brands_Slug UNIQUE (Slug)
);

-- Products
CREATE TABLE Products
(
    ProductID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    SKU NVARCHAR(50) NOT NULL,
    Name NVARCHAR(255) NOT NULL,
    Slug NVARCHAR(280) NOT NULL,
    Description NVARCHAR(MAX),
    ShortDescription NVARCHAR(500),

    -- Categorization
    BrandID INT REFERENCES Brands(BrandID),
    CategoryID INT REFERENCES Categories(CategoryID),

    -- Pricing
    BasePrice DECIMAL(10,2) NOT NULL CHECK (BasePrice >= 0),
    SalePrice DECIMAL(10,2) CHECK (SalePrice >= 0),
    CostPrice DECIMAL(10,2),

    -- Inventory
    StockQuantity INT DEFAULT 0 CHECK (StockQuantity >= 0),
    StockStatus NVARCHAR(20) DEFAULT 'in_stock' CHECK (StockStatus IN ('in_stock', 'out_of_stock', 'on_backorder')),
    LowStockThreshold INT DEFAULT 5,
    TrackInventory BIT DEFAULT 1,

    -- Product status
    Status NVARCHAR(20) DEFAULT 'draft' CHECK (Status IN ('draft', 'active', 'inactive', 'discontinued')),
    Visibility NVARCHAR(20) DEFAULT 'public' CHECK (Visibility IN ('public', 'hidden', 'search_only')),

    -- Physical properties
    Weight DECIMAL(8,3), -- in kg
    Dimensions NVARCHAR(MAX), -- JSON string: {"length": 10, "width": 5, "height": 2, "unit": "cm"}

    -- Shipping
    RequiresShipping BIT DEFAULT 1,
    ShippingClass NVARCHAR(50) DEFAULT 'standard',

    -- Tax
    TaxClass NVARCHAR(50) DEFAULT 'standard',
    TaxRate DECIMAL(5,4),

    -- Media
    MainImageURL NVARCHAR(500),
    GalleryImages NVARCHAR(MAX), -- JSON array of image URLs

    -- SEO
    MetaTitle NVARCHAR(60),
    MetaDescription NVARCHAR(160),
    SearchKeywords NVARCHAR(MAX), -- Comma-separated or JSON array

    -- Sales data (denormalized for performance)
    TotalSales INT DEFAULT 0,
    TotalReviews INT DEFAULT 0,
    AverageRating DECIMAL(3,2) DEFAULT 0.00,

    -- Seller information (for marketplace)
    SellerID UNIQUEIDENTIFIER REFERENCES Users(UserID),

    -- Timestamps
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    CONSTRAINT UQ_Products_SKU UNIQUE (SKU),
    CONSTRAINT UQ_Products_Slug UNIQUE (Slug),
    INDEX IX_Products_CategoryID (CategoryID),
    INDEX IX_Products_BrandID (BrandID),
    INDEX IX_Products_Status (Status),
    INDEX IX_Products_StockStatus (StockStatus),
    INDEX IX_Products_SellerID (SellerID),
    INDEX IX_Products_BasePrice (BasePrice),
    INDEX IX_Products_AverageRating (AverageRating DESC)
);

-- Full-text search on products
CREATE FULLTEXT INDEX ON Products(Name, Description, ShortDescription, SearchKeywords) KEY INDEX PK_Products;

-- Product variations (size, color, etc.)
CREATE TABLE ProductVariations
(
    VariationID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    VariationName NVARCHAR(255), -- "Color: Red, Size: Large"
    Attributes NVARCHAR(MAX) NOT NULL, -- JSON: {"color": "red", "size": "large"}
    SKU NVARCHAR(50),
    PriceModifier DECIMAL(8,2) DEFAULT 0.00,
    StockQuantity INT DEFAULT 0,
    IsAvailable BIT DEFAULT 1,
    ImageURL NVARCHAR(500),

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_ProductVariations_ProductID (ProductID),
    INDEX IX_ProductVariations_SKU (SKU)
);

-- Product images
CREATE TABLE ProductImages
(
    ImageID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    VariationID UNIQUEIDENTIFIER REFERENCES ProductVariations(VariationID),
    ImageURL NVARCHAR(500) NOT NULL,
    AltText NVARCHAR(255),
    DisplayOrder INT DEFAULT 0,
    IsPrimary BIT DEFAULT 0,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_ProductImages_ProductID (ProductID),
    INDEX IX_ProductImages_VariationID (VariationID)
);

-- ============================================
-- SHOPPING CART & ORDERS
-- ============================================

-- Shopping carts
CREATE TABLE Carts
(
    CartID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID UNIQUEIDENTIFIER REFERENCES Users(UserID),
    SessionID NVARCHAR(255), -- For anonymous users
    IsActive BIT DEFAULT 1,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_Carts_UserID (UserID),
    INDEX IX_Carts_SessionID (SessionID)
);

-- Cart items
CREATE TABLE CartItems
(
    CartItemID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    CartID UNIQUEIDENTIFIER NOT NULL REFERENCES Carts(CartID) ON DELETE CASCADE,
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID),
    VariationID UNIQUEIDENTIFIER REFERENCES ProductVariations(VariationID),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    Customizations NVARCHAR(MAX), -- JSON: {"gift_wrapping": true, "engraving": "Happy Birthday"}

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_CartItems_CartID (CartID),
    INDEX IX_CartItems_ProductID (ProductID)
);

-- Orders
CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderNumber NVARCHAR(50) NOT NULL,
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID),

    -- Status tracking
    Status NVARCHAR(30) DEFAULT 'pending' CHECK (Status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded')),
    PaymentStatus NVARCHAR(20) DEFAULT 'pending' CHECK (PaymentStatus IN ('pending', 'paid', 'failed', 'refunded', 'partially_refunded')),
    FulfillmentStatus NVARCHAR(20) DEFAULT 'unfulfilled' CHECK (FulfillmentStatus IN ('unfulfilled', 'partial', 'fulfilled', 'cancelled')),

    -- Financial breakdown
    Subtotal DECIMAL(12,2) NOT NULL DEFAULT 0,
    TaxAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    ShippingAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    DiscountAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    TotalAmount AS (Subtotal + TaxAmount + ShippingAmount - DiscountAmount) PERSISTED,

    -- Addresses
    BillingAddressID UNIQUEIDENTIFIER REFERENCES Addresses(AddressID),
    ShippingAddressID UNIQUEIDENTIFIER REFERENCES Addresses(AddressID),

    -- Payment info
    PaymentMethodID UNIQUEIDENTIFIER,
    PaymentProvider NVARCHAR(50),
    PaymentProviderTransactionID NVARCHAR(255),

    -- Shipping info
    ShippingMethodID INT,
    TrackingNumber NVARCHAR(100),
    Carrier NVARCHAR(50),

    -- Notes
    CustomerNotes NVARCHAR(MAX),
    InternalNotes NVARCHAR(MAX),

    -- Timestamps
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
    ShippedAt DATETIME2,
    DeliveredAt DATETIME2,

    CONSTRAINT UQ_Orders_OrderNumber UNIQUE (OrderNumber),
    INDEX IX_Orders_UserID (UserID),
    INDEX IX_Orders_Status (Status),
    INDEX IX_Orders_CreatedAt (CreatedAt DESC),
    INDEX IX_Orders_OrderNumber (OrderNumber)
);

-- Order items
CREATE TABLE OrderItems
(
    OrderItemID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderID UNIQUEIDENTIFIER NOT NULL REFERENCES Orders(OrderID) ON DELETE CASCADE,
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID),
    VariationID UNIQUEIDENTIFIER REFERENCES ProductVariations(VariationID),

    ProductName NVARCHAR(255) NOT NULL, -- Denormalized for historical accuracy
    SKU NVARCHAR(50),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    TotalPrice AS (Quantity * UnitPrice) PERSISTED,

    -- Fulfillment tracking
    FulfilledQuantity INT DEFAULT 0,
    FulfillmentStatus NVARCHAR(20) DEFAULT 'pending',

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_OrderItems_OrderID (OrderID),
    INDEX IX_OrderItems_ProductID (ProductID)
);

-- ============================================
-- PAYMENTS & FINANCIAL
-- ============================================

-- Payment methods
CREATE TABLE PaymentMethods
(
    PaymentMethodID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID) ON DELETE CASCADE,
    Type NVARCHAR(20) NOT NULL CHECK (Type IN ('credit_card', 'debit_card', 'paypal', 'apple_pay', 'google_pay', 'bank_transfer')),
    Provider NVARCHAR(50), -- 'stripe', 'paypal', 'braintree'

    -- Tokenized for PCI compliance
    ProviderToken NVARCHAR(255),
    LastFour NVARCHAR(4), -- Last 4 digits
    CardBrand NVARCHAR(20), -- 'visa', 'mastercard', 'amex'
    ExpiryMonth INT CHECK (ExpiryMonth BETWEEN 1 AND 12),
    ExpiryYear INT CHECK (ExpiryYear >= YEAR(GETDATE())),

    -- Billing address
    BillingAddressID UNIQUEIDENTIFIER REFERENCES Addresses(AddressID),

    IsDefault BIT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_PaymentMethods_UserID (UserID)
);

-- Payment transactions
CREATE TABLE Payments
(
    PaymentID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderID UNIQUEIDENTIFIER NOT NULL REFERENCES Orders(OrderID),
    PaymentMethodID UNIQUEIDENTIFIER REFERENCES PaymentMethods(PaymentMethodID),

    Amount DECIMAL(12,2) NOT NULL CHECK (Amount > 0),
    Currency NVARCHAR(3) DEFAULT 'USD',
    Provider NVARCHAR(50),
    ProviderPaymentID NVARCHAR(255),
    Status NVARCHAR(20) DEFAULT 'pending' CHECK (Status IN ('pending', 'processing', 'succeeded', 'failed', 'refunded', 'partially_refunded')),

    -- Payment details
    PaymentIntent NVARCHAR(MAX), -- JSON response from payment provider
    FailureReason NVARCHAR(MAX),

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
    ProcessedAt DATETIME2,

    CONSTRAINT UQ_Payments_ProviderPaymentID UNIQUE (ProviderPaymentID),
    INDEX IX_Payments_OrderID (OrderID),
    INDEX IX_Payments_Status (Status),
    INDEX IX_Payments_CreatedAt (CreatedAt DESC)
);

-- Refunds
CREATE TABLE Refunds
(
    RefundID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    PaymentID UNIQUEIDENTIFIER NOT NULL REFERENCES Payments(PaymentID),
    OrderID UNIQUEIDENTIFIER NOT NULL REFERENCES Orders(OrderID),

    Amount DECIMAL(12,2) NOT NULL CHECK (Amount > 0),
    Reason NVARCHAR(100), -- 'customer_request', 'defective_product', 'wrong_item', 'not_delivered'
    Status NVARCHAR(20) DEFAULT 'pending' CHECK (Status IN ('pending', 'processing', 'completed', 'failed')),
    ProviderRefundID NVARCHAR(255),

    RefundedBy UNIQUEIDENTIFIER REFERENCES Users(UserID),
    Notes NVARCHAR(MAX),

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    ProcessedAt DATETIME2,

    INDEX IX_Refunds_PaymentID (PaymentID),
    INDEX IX_Refunds_OrderID (OrderID)
);

-- ============================================
-- INVENTORY & WAREHOUSING
-- ============================================

-- Warehouses
CREATE TABLE Warehouses
(
    WarehouseID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Code NVARCHAR(20) UNIQUE NOT NULL,
    Address NVARCHAR(MAX), -- JSON string
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),
    Geolocation GEOGRAPHY,
    Phone NVARCHAR(20),
    Email NVARCHAR(255),
    IsActive BIT DEFAULT 1,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Product inventory (multi-warehouse)
CREATE TABLE ProductInventory
(
    InventoryID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    VariationID UNIQUEIDENTIFIER REFERENCES ProductVariations(VariationID),
    WarehouseID INT NOT NULL REFERENCES Warehouses(WarehouseID),

    QuantityAvailable INT DEFAULT 0 CHECK (QuantityAvailable >= 0),
    QuantityReserved INT DEFAULT 0 CHECK (QuantityReserved >= 0),
    QuantityOnOrder INT DEFAULT 0 CHECK (QuantityOnOrder >= 0),

    -- Warehouse location
    Aisle NVARCHAR(20),
    Shelf NVARCHAR(20),
    Bin NVARCHAR(20),

    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    CONSTRAINT UQ_ProductInventory_Product_Variation_Warehouse UNIQUE (ProductID, VariationID, WarehouseID),
    INDEX IX_ProductInventory_ProductID (ProductID),
    INDEX IX_ProductInventory_WarehouseID (WarehouseID)
);

-- Inventory transactions (audit trail)
CREATE TABLE InventoryTransactions
(
    TransactionID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    InventoryID UNIQUEIDENTIFIER NOT NULL REFERENCES ProductInventory(InventoryID),
    TransactionType NVARCHAR(20) NOT NULL CHECK (TransactionType IN ('stock_in', 'stock_out', 'adjustment', 'reservation', 'release', 'transfer')),
    QuantityChange INT NOT NULL,
    PreviousQuantity INT NOT NULL,
    NewQuantity INT NOT NULL,
    ReferenceType NVARCHAR(50), -- 'order', 'return', 'adjustment', 'transfer'
    ReferenceID UNIQUEIDENTIFIER,
    PerformedBy UNIQUEIDENTIFIER REFERENCES Users(UserID),
    Notes NVARCHAR(MAX),

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_InventoryTransactions_InventoryID (InventoryID),
    INDEX IX_InventoryTransactions_CreatedAt (CreatedAt DESC),
    INDEX IX_InventoryTransactions_Reference (ReferenceType, ReferenceID)
);

-- ============================================
-- SHIPPING & FULFILLMENT
-- ============================================

-- Shipping methods
CREATE TABLE ShippingMethods
(
    ShippingMethodID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Provider NVARCHAR(50), -- 'fedex', 'ups', 'usps', 'dhl', 'custom'
    BaseCost DECIMAL(8,2) DEFAULT 0,
    CostPerWeight DECIMAL(8,2) DEFAULT 0,
    CostPerItem DECIMAL(8,2) DEFAULT 0,
    MinDeliveryDays INT,
    MaxDeliveryDays INT,
    IsActive BIT DEFAULT 1,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Shipments
CREATE TABLE Shipments
(
    ShipmentID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderID UNIQUEIDENTIFIER NOT NULL REFERENCES Orders(OrderID),
    ShippingMethodID INT REFERENCES ShippingMethods(ShippingMethodID),

    TrackingNumber NVARCHAR(100),
    Carrier NVARCHAR(50),

    -- Status with history
    Status NVARCHAR(30) DEFAULT 'pending' CHECK (Status IN ('pending', 'label_created', 'picked_up', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')),
    StatusHistory NVARCHAR(MAX), -- JSON array of status updates

    ShippedAt DATETIME2,
    EstimatedDeliveryDate DATE,
    ActualDeliveryDate DATE,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    CONSTRAINT UQ_Shipments_TrackingNumber UNIQUE (TrackingNumber),
    INDEX IX_Shipments_OrderID (OrderID),
    INDEX IX_Shipments_TrackingNumber (TrackingNumber),
    INDEX IX_Shipments_Status (Status)
);

-- ============================================
-- REVIEWS & RATINGS
-- ============================================

-- Product reviews
CREATE TABLE ProductReviews
(
    ReviewID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID),
    OrderID UNIQUEIDENTIFIER REFERENCES Orders(OrderID), -- Verified purchase

    Rating INT NOT NULL CHECK (Rating BETWEEN 1 AND 5),
    Title NVARCHAR(200),
    ReviewText NVARCHAR(MAX),
    Pros NVARCHAR(MAX),
    Cons NVARCHAR(MAX),

    -- Media attachments
    Images NVARCHAR(MAX), -- JSON array of image URLs
    Videos NVARCHAR(MAX), -- JSON array of video URLs

    -- Moderation
    Status NVARCHAR(20) DEFAULT 'pending' CHECK (Status IN ('pending', 'approved', 'rejected', 'flagged')),
    IsVerifiedPurchase BIT DEFAULT 0,

    -- Voting system
    HelpfulVotes INT DEFAULT 0,
    TotalVotes INT DEFAULT 0,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
    PublishedAt DATETIME2,

    INDEX IX_ProductReviews_ProductID (ProductID),
    INDEX IX_ProductReviews_UserID (UserID),
    INDEX IX_ProductReviews_Rating (Rating),
    INDEX IX_ProductReviews_Status (Status)
);

-- Review votes
CREATE TABLE ReviewVotes
(
    ReviewVoteID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ReviewID UNIQUEIDENTIFIER NOT NULL REFERENCES ProductReviews(ReviewID) ON DELETE CASCADE,
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID),
    VoteType NVARCHAR(10) CHECK (VoteType IN ('helpful', 'unhelpful')),

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),

    CONSTRAINT UQ_ReviewVotes_Review_User UNIQUE (ReviewID, UserID),
    INDEX IX_ReviewVotes_ReviewID (ReviewID)
);

-- Product questions and answers
CREATE TABLE ProductQuestions
(
    QuestionID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID),
    QuestionText NVARCHAR(MAX) NOT NULL,
    Status NVARCHAR(20) DEFAULT 'pending' CHECK (Status IN ('pending', 'answered', 'closed')),

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_ProductQuestions_ProductID (ProductID),
    INDEX IX_ProductQuestions_UserID (UserID)
);

CREATE TABLE ProductAnswers
(
    AnswerID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    QuestionID UNIQUEIDENTIFIER NOT NULL REFERENCES ProductQuestions(QuestionID) ON DELETE CASCADE,
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID),
    AnswerText NVARCHAR(MAX) NOT NULL,
    IsOfficialAnswer BIT DEFAULT 0,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_ProductAnswers_QuestionID (QuestionID),
    INDEX IX_ProductAnswers_UserID (UserID)
);

-- ============================================
-- PROMOTIONS & DISCOUNTS
-- ============================================

-- Coupons
CREATE TABLE Coupons
(
    CouponID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    Code NVARCHAR(50) NOT NULL,
    DiscountType NVARCHAR(20) NOT NULL CHECK (DiscountType IN ('percentage', 'fixed_amount', 'free_shipping')),
    DiscountValue DECIMAL(8,2) NOT NULL,

    -- Usage controls
    UsageLimit INT,
    PerUserLimit INT DEFAULT 1,
    UsedCount INT DEFAULT 0,

    -- Eligibility rules
    MinimumOrderAmount DECIMAL(8,2),
    ApplicableCategories NVARCHAR(MAX), -- JSON array of category IDs
    ApplicableProducts NVARCHAR(MAX), -- JSON array of product IDs

    -- Validity period
    StartsAt DATETIME2,
    ExpiresAt DATETIME2,
    IsActive BIT DEFAULT 1,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),

    CONSTRAINT UQ_Coupons_Code UNIQUE (Code),
    INDEX IX_Coupons_Code (Code),
    INDEX IX_Coupons_IsActive (IsActive)
);

-- Applied coupons audit
CREATE TABLE AppliedCoupons
(
    AppliedCouponID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    CouponID UNIQUEIDENTIFIER NOT NULL REFERENCES Coupons(CouponID),
    OrderID UNIQUEIDENTIFIER NOT NULL REFERENCES Orders(OrderID),
    DiscountAmount DECIMAL(8,2) NOT NULL,

    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),

    INDEX IX_AppliedCoupons_CouponID (CouponID),
    INDEX IX_AppliedCoupons_OrderID (OrderID)
);

-- ============================================
-- ANALYTICS & REPORTING
-- ============================================

-- Product analytics (partitioned by date)
CREATE TABLE ProductAnalytics
(
    AnalyticsID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID),
    Date DATE NOT NULL,

    PageViews INT DEFAULT 0,
    UniqueVisitors INT DEFAULT 0,
    AddToCartCount INT DEFAULT 0,
    PurchaseCount INT DEFAULT 0,
    Revenue DECIMAL(12,2) DEFAULT 0.00,

    CONSTRAINT UQ_ProductAnalytics_Product_Date UNIQUE (ProductID, Date),
    INDEX IX_ProductAnalytics_ProductID (ProductID),
    INDEX IX_ProductAnalytics_Date (Date DESC)
);

-- Customer analytics
CREATE TABLE CustomerAnalytics
(
    AnalyticsID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID),
    Date DATE NOT NULL,

    SessionCount INT DEFAULT 0,
    OrdersPlaced INT DEFAULT 0,
    TotalSpent DECIMAL(10,2) DEFAULT 0.00,
    ProductsViewed INT DEFAULT 0,

    CONSTRAINT UQ_CustomerAnalytics_User_Date UNIQUE (UserID, Date),
    INDEX IX_CustomerAnalytics_UserID (UserID),
    INDEX IX_CustomerAnalytics_Date (Date DESC)
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Additional composite indexes for common queries
CREATE INDEX IX_Products_Category_Status_Price ON Products(CategoryID, Status, BasePrice);
CREATE INDEX IX_Orders_User_Status_Created ON Orders(UserID, Status, CreatedAt DESC);
CREATE INDEX IX_OrderItems_Order_Product ON OrderItems(OrderID, ProductID);
CREATE INDEX IX_ProductInventory_Product_Warehouse ON ProductInventory(ProductID, WarehouseID);

-- ============================================
-- TEMPORAL TABLES (SQL Server Feature)
-- ============================================

-- Enable system versioning on Orders table for audit trail
ALTER TABLE Orders
ADD ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN DEFAULT GETUTCDATE(),
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo);

ALTER TABLE Orders
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.OrdersHistory));

-- Enable system versioning on Products table
ALTER TABLE Products
ADD ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN DEFAULT GETUTCDATE(),
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo);

ALTER TABLE Products
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.ProductsHistory));

