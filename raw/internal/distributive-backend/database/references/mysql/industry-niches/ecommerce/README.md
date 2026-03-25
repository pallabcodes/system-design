# E-Commerce Platform Database Design

## Overview

This comprehensive database schema supports modern e-commerce platforms including online stores, marketplaces, inventory management, order processing, payment systems, and customer analytics. The design handles high-volume transactions, complex product catalogs, multi-channel sales, and enterprise-level scalability.

## Key Features

### 🛒 Product Catalog & Inventory
- **Multi-vendor marketplace** support with seller management
- **Complex product structures** with variants, bundles, and configurable products
- **Advanced inventory tracking** with stock levels, reservations, and alerts
- **Dynamic pricing** with promotions, discounts, and price rules

### 👥 Customer Experience & Orders
- **Guest and registered checkout** with persistent carts
- **Order lifecycle management** from quote to fulfillment
- **Multi-channel order processing** (web, mobile, API, POS)
- **Customer loyalty programs** and personalized recommendations

### 💳 Payment & Fulfillment
- **Payment gateway integration** with multiple providers
- **Order fulfillment workflows** with shipping and tracking
- **Return and refund management** with automated processing
- **Tax calculation** and compliance across jurisdictions

## Database Schema Highlights

### Core Tables

#### User & Customer Management
```sql
-- Customer accounts with authentication
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    PasswordHash NVARCHAR(255),
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Phone NVARCHAR(20),
    DateOfBirth DATE,
    Gender CHAR(1),
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastLoginDate DATETIME2,
    EmailVerified BIT DEFAULT 0,

    -- Indexes
    INDEX IX_Customers_Email (Email),
    INDEX IX_Customers_IsActive (IsActive),
    INDEX IX_Customers_CreatedDate (CreatedDate)
);

-- Customer addresses for shipping/billing
CREATE TABLE CustomerAddresses (
    AddressID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID) ON DELETE CASCADE,
    AddressType NVARCHAR(20) DEFAULT 'Shipping', -- Shipping, Billing
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Company NVARCHAR(100),
    Street NVARCHAR(255),
    City NVARCHAR(100),
    State NVARCHAR(50),
    PostalCode NVARCHAR(20),
    Country NVARCHAR(50) DEFAULT 'USA',
    Phone NVARCHAR(20),
    IsDefault BIT DEFAULT 0,

    -- Indexes
    INDEX IX_CustomerAddresses_Customer (CustomerID),
    INDEX IX_CustomerAddresses_Type (AddressType),
    INDEX IX_CustomerAddresses_IsDefault (CustomerID) WHERE IsDefault = 1
);
```

#### Product Catalog
```sql
-- Product categories with hierarchy
CREATE TABLE Categories (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),
    ParentCategoryID INT REFERENCES Categories(CategoryID),
    DisplayOrder INT DEFAULT 0,
    IsActive BIT DEFAULT 1,
    ImageURL NVARCHAR(500),
    MetaTitle NVARCHAR(200),
    MetaDescription NVARCHAR(MAX),

    -- Indexes
    INDEX IX_Categories_Parent (ParentCategoryID) WHERE ParentCategoryID IS NOT NULL,
    INDEX IX_Categories_IsActive (IsActive),
    INDEX IX_Categories_DisplayOrder (DisplayOrder)
);

-- Products master table
CREATE TABLE Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    SKU NVARCHAR(50) UNIQUE,
    ProductName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    ShortDescription NVARCHAR(500),
    CategoryID INT REFERENCES Categories(CategoryID),
    Brand NVARCHAR(100),
    SupplierID INT,
    ProductType NVARCHAR(50) DEFAULT 'Simple', -- Simple, Variable, Bundle, Digital
    Visibility NVARCHAR(20) DEFAULT 'Catalog', -- Catalog, Search, Hidden
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    UpdatedDate DATETIME2 DEFAULT GETDATE(),

    -- Full-text search
    INDEX IX_Products_FullText (ProductName, Description, ShortDescription) WHERE IsActive = 1,

    -- Indexes
    INDEX IX_Products_SKU (SKU),
    INDEX IX_Products_Category (CategoryID),
    INDEX IX_Products_Brand (Brand),
    INDEX IX_Products_Type (ProductType),
    INDEX IX_Products_IsActive (IsActive)
);

-- Product variants (sizes, colors, etc.)
CREATE TABLE ProductVariants (
    VariantID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    VariantSKU NVARCHAR(50) UNIQUE,
    VariantName NVARCHAR(200),
    Price DECIMAL(10,2),
    CompareAtPrice DECIMAL(10,2),
    Cost DECIMAL(10,2),
    Weight DECIMAL(8,2),
    StockQuantity INT DEFAULT 0,
    LowStockThreshold INT DEFAULT 5,
    IsActive BIT DEFAULT 1,

    -- Variant attributes stored as JSON
    Attributes NVARCHAR(MAX), -- {"color": "Red", "size": "Large"}

    -- Indexes
    INDEX IX_ProductVariants_Product (ProductID),
    INDEX IX_ProductVariants_SKU (VariantSKU),
    INDEX IX_ProductVariants_IsActive (IsActive),
    INDEX IX_ProductVariants_Stock (StockQuantity)
);
```

#### Pricing & Inventory
```sql
-- Pricing rules and promotions
CREATE TABLE PricingRules (
    RuleID INT IDENTITY(1,1) PRIMARY KEY,
    RuleName NVARCHAR(200) NOT NULL,
    RuleType NVARCHAR(50) NOT NULL, -- Fixed, Percentage, BuyXGetY
    DiscountType NVARCHAR(20), -- Amount, Percentage
    DiscountValue DECIMAL(10,2),
    MinimumQuantity INT DEFAULT 1,
    MaximumQuantity INT,
    AppliesTo NVARCHAR(50), -- Product, Category, Cart
    TargetID INT, -- ProductID or CategoryID
    StartDate DATETIME2,
    EndDate DATETIME2,
    IsActive BIT DEFAULT 1,
    UsageLimit INT,
    UsedCount INT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_PricingRules_Dates CHECK (EndDate > StartDate),

    -- Indexes
    INDEX IX_PricingRules_Type (RuleType),
    INDEX IX_PricingRules_IsActive (IsActive),
    INDEX IX_PricingRules_StartEnd (StartDate, EndDate)
);

-- Inventory tracking
CREATE TABLE Inventory (
    InventoryID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    VariantID INT REFERENCES ProductVariants(VariantID),
    WarehouseID INT,
    QuantityOnHand INT DEFAULT 0,
    QuantityReserved INT DEFAULT 0,
    QuantityAvailable AS (QuantityOnHand - QuantityReserved),
    LastUpdated DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_Inventory_Quantity CHECK (QuantityOnHand >= 0 AND QuantityReserved >= 0),

    -- Indexes
    INDEX IX_Inventory_Product (ProductID),
    INDEX IX_Inventory_Variant (VariantID),
    INDEX IX_Inventory_Warehouse (WarehouseID),
    INDEX IX_Inventory_LastUpdated (LastUpdated)
);
```

### Order Management

#### Shopping Cart & Checkout
```sql
-- Shopping carts
CREATE TABLE ShoppingCarts (
    CartID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT REFERENCES Customers(CustomerID),
    SessionID NVARCHAR(255), -- For anonymous users
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    UpdatedDate DATETIME2 DEFAULT GETDATE(),
    ExpiresAt DATETIME2 DEFAULT DATEADD(HOUR, 24, GETDATE()),

    -- Indexes
    INDEX IX_ShoppingCarts_Customer (CustomerID),
    INDEX IX_ShoppingCarts_Session (SessionID),
    INDEX IX_ShoppingCarts_Expires (ExpiresAt)
);

-- Cart items
CREATE TABLE CartItems (
    CartItemID INT IDENTITY(1,1) PRIMARY KEY,
    CartID INT NOT NULL REFERENCES ShoppingCarts(CartID) ON DELETE CASCADE,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    VariantID INT REFERENCES ProductVariants(VariantID),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    AddedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT UQ_CartItems_CartProduct UNIQUE (CartID, ProductID, VariantID),

    -- Indexes
    INDEX IX_CartItems_Cart (CartID),
    INDEX IX_CartItems_Product (ProductID),
    INDEX IX_CartItems_Variant (VariantID)
);
```

#### Orders & Order Items
```sql
-- Orders master table
CREATE TABLE Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    OrderNumber NVARCHAR(50) UNIQUE NOT NULL,
    CustomerID INT REFERENCES Customers(CustomerID),
    OrderStatus NVARCHAR(20) DEFAULT 'Pending',
    OrderDate DATETIME2 DEFAULT GETDATE(),
    ShippingAddressID INT REFERENCES CustomerAddresses(AddressID),
    BillingAddressID INT REFERENCES CustomerAddresses(AddressID),

    -- Pricing
    Subtotal DECIMAL(10,2) NOT NULL,
    TaxAmount DECIMAL(10,2) DEFAULT 0,
    ShippingAmount DECIMAL(10,2) DEFAULT 0,
    DiscountAmount DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(10,2) NOT NULL,

    -- Additional fields
    Currency NVARCHAR(3) DEFAULT 'USD',
    PaymentMethod NVARCHAR(50),
    Notes NVARCHAR(MAX),
    IPAddress NVARCHAR(45),

    -- Indexes
    INDEX IX_Orders_OrderNumber (OrderNumber),
    INDEX IX_Orders_Customer (CustomerID),
    INDEX IX_Orders_Status (OrderStatus),
    INDEX IX_Orders_Date (OrderDate)
);

-- Order items
CREATE TABLE OrderItems (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES Orders(OrderID) ON DELETE CASCADE,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    VariantID INT REFERENCES ProductVariants(VariantID),
    ProductName NVARCHAR(200), -- Snapshot for historical accuracy
    SKU NVARCHAR(50),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    DiscountAmount DECIMAL(10,2) DEFAULT 0,
    LineTotal DECIMAL(10,2) NOT NULL,

    -- Indexes
    INDEX IX_OrderItems_Order (OrderID),
    INDEX IX_OrderItems_Product (ProductID),
    INDEX IX_OrderItems_Variant (VariantID)
);
```

### Payment Processing

#### Payments & Transactions
```sql
-- Payment methods
CREATE TABLE PaymentMethods (
    PaymentMethodID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID) ON DELETE CASCADE,
    MethodType NVARCHAR(20) NOT NULL, -- CreditCard, PayPal, BankTransfer
    Provider NVARCHAR(50), -- Visa, Mastercard, PayPal
    LastFour NVARCHAR(4),
    ExpiryMonth INT,
    ExpiryYear INT,
    IsDefault BIT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    -- Encrypted card data (in production, use proper tokenization)
    EncryptedCardData VARBINARY(MAX),

    -- Indexes
    INDEX IX_PaymentMethods_Customer (CustomerID),
    INDEX IX_PaymentMethods_IsDefault (CustomerID) WHERE IsDefault = 1,
    INDEX IX_PaymentMethods_IsActive (IsActive)
);

-- Payment transactions
CREATE TABLE Payments (
    PaymentID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES Orders(OrderID),
    PaymentMethodID INT REFERENCES PaymentMethods(PaymentMethodID),
    Amount DECIMAL(10,2) NOT NULL,
    Currency NVARCHAR(3) DEFAULT 'USD',
    PaymentStatus NVARCHAR(20) DEFAULT 'Pending',
    TransactionID NVARCHAR(255),
    AuthorizationCode NVARCHAR(100),
    PaymentDate DATETIME2 DEFAULT GETDATE(),
    ProcessedDate DATETIME2,
    GatewayResponse NVARCHAR(MAX), -- JSON response from payment gateway

    -- Indexes
    INDEX IX_Payments_Order (OrderID),
    INDEX IX_Payments_Status (PaymentStatus),
    INDEX IX_Payments_Transaction (TransactionID),
    INDEX IX_Payments_Date (PaymentDate)
);
```

### Advanced Features

#### Reviews & Ratings
```sql
-- Product reviews
CREATE TABLE ProductReviews (
    ReviewID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    CustomerID INT REFERENCES Customers(CustomerID),
    OrderID INT REFERENCES Orders(OrderID),
    Rating INT CHECK (Rating BETWEEN 1 AND 5),
    Title NVARCHAR(200),
    ReviewText NVARCHAR(MAX),
    IsVerified BIT DEFAULT 0, -- Verified purchase
    IsPublished BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    HelpfulVotes INT DEFAULT 0,
    TotalVotes INT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_ProductReviews_Votes CHECK (HelpfulVotes <= TotalVotes),

    -- Full-text search
    INDEX IX_ProductReviews_FullText (Title, ReviewText) WHERE IsPublished = 1,

    -- Indexes
    INDEX IX_ProductReviews_Product (ProductID),
    INDEX IX_ProductReviews_Customer (CustomerID),
    INDEX IX_ProductReviews_Rating (Rating),
    INDEX IX_ProductReviews_IsPublished (IsPublished)
);

-- Review responses
CREATE TABLE ReviewResponses (
    ResponseID INT IDENTITY(1,1) PRIMARY KEY,
    ReviewID INT NOT NULL REFERENCES ProductReviews(ReviewID) ON DELETE CASCADE,
    ResponderID INT NOT NULL, -- Admin or seller
    ResponseText NVARCHAR(MAX) NOT NULL,
    ResponseDate DATETIME2 DEFAULT GETDATE(),
    IsFromSeller BIT DEFAULT 0,

    -- Indexes
    INDEX IX_ReviewResponses_Review (ReviewID),
    INDEX IX_ReviewResponses_Date (ResponseDate)
);
```

#### Analytics & Reporting
```sql
-- Product analytics
CREATE TABLE ProductAnalytics (
    AnalyticsID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    Date DATE NOT NULL,
    Views INT DEFAULT 0,
    Clicks INT DEFAULT 0,
    AddToCarts INT DEFAULT 0,
    Purchases INT DEFAULT 0,
    Revenue DECIMAL(10,2) DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_ProductAnalytics_ProductDate UNIQUE (ProductID, Date),

    -- Indexes
    INDEX IX_ProductAnalytics_Product (ProductID),
    INDEX IX_ProductAnalytics_Date (Date)
);

-- Customer analytics
CREATE TABLE CustomerAnalytics (
    AnalyticsID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    Date DATE NOT NULL,
    OrdersCount INT DEFAULT 0,
    TotalSpent DECIMAL(10,2) DEFAULT 0,
    ItemsPurchased INT DEFAULT 0,
    AvgOrderValue DECIMAL(10,2),
    LastOrderDate DATETIME2,

    -- Constraints
    CONSTRAINT UQ_CustomerAnalytics_CustomerDate UNIQUE (CustomerID, Date),

    -- Indexes
    INDEX IX_CustomerAnalytics_Customer (CustomerID),
    INDEX IX_CustomerAnalytics_Date (Date)
);
```

## Integration Points

### External Systems
- **Payment Gateways**: Stripe, PayPal, Authorize.net, Braintree
- **Shipping Carriers**: FedEx, UPS, USPS, DHL with real-time tracking
- **Tax Services**: Avalara, TaxJar for automated tax calculation
- **Email Marketing**: Mailchimp, Klaviyo for customer communications
- **Inventory Management**: Integration with warehouse management systems
- **ERP Systems**: QuickBooks, SAP for financial integration
- **POS Systems**: Square, Clover for omnichannel retail

### API Endpoints
- **Product Management APIs**: Catalog management and inventory updates
- **Order Processing APIs**: Order creation, status updates, fulfillment
- **Customer Management APIs**: Profile management and preferences
- **Payment APIs**: Payment processing and transaction management
- **Analytics APIs**: Sales reporting and business intelligence
- **Integration APIs**: Webhooks for real-time data synchronization

## Monitoring & Analytics

### Key Performance Indicators
- **Conversion rates**: Cart abandonment, checkout completion
- **Sales performance**: Revenue trends, product performance, category analysis
- **Customer metrics**: Customer acquisition cost, lifetime value, retention rates
- **Operational efficiency**: Order processing time, shipping accuracy, return rates
- **Inventory metrics**: Stock turnover, out-of-stock incidents, overstock alerts

### Real-Time Dashboards
```sql
-- E-commerce operations dashboard
CREATE VIEW ECommerceDashboard AS
SELECT
    -- Today's sales metrics
    (SELECT COUNT(*) FROM Orders WHERE CAST(OrderDate AS DATE) = CAST(GETDATE() AS DATE)) AS OrdersToday,
    (SELECT SUM(TotalAmount) FROM Orders WHERE CAST(OrderDate AS DATE) = CAST(GETDATE() AS DATE)) AS RevenueToday,
    (SELECT AVG(TotalAmount) FROM Orders WHERE CAST(OrderDate AS DATE) = CAST(GETDATE() AS DATE)) AS AvgOrderValueToday,

    -- Week-over-week comparison
    (SELECT COUNT(*) FROM Orders WHERE OrderDate >= DATEADD(DAY, -7, GETDATE())) AS OrdersLast7Days,
    (SELECT COUNT(*) FROM Orders WHERE OrderDate >= DATEADD(DAY, -14, GETDATE()) AND OrderDate < DATEADD(DAY, -7, GETDATE())) AS OrdersPrev7Days,
    CASE WHEN (SELECT COUNT(*) FROM Orders WHERE OrderDate >= DATEADD(DAY, -14, GETDATE()) AND OrderDate < DATEADD(DAY, -7, GETDATE())) > 0
         THEN CAST((
             (SELECT COUNT(*) FROM Orders WHERE OrderDate >= DATEADD(DAY, -7, GETDATE())) * 100.0 /
             (SELECT COUNT(*) FROM Orders WHERE OrderDate >= DATEADD(DAY, -14, GETDATE()) AND OrderDate < DATEADD(DAY, -7, GETDATE()))
         ) - 100 AS DECIMAL(10,2)) ELSE NULL END AS OrderGrowthPercent,

    -- Cart and conversion metrics
    (SELECT COUNT(*) FROM ShoppingCarts WHERE UpdatedDate >= DATEADD(HOUR, -24, GETDATE())) AS ActiveCarts24H,
    (SELECT COUNT(*) FROM ShoppingCarts sc
     INNER JOIN Orders o ON sc.CustomerID = o.CustomerID
     WHERE sc.UpdatedDate >= DATEADD(HOUR, -24, GETDATE())
     AND o.OrderDate >= DATEADD(HOUR, -24, GETDATE())) * 100.0 /
    NULLIF((SELECT COUNT(*) FROM ShoppingCarts WHERE UpdatedDate >= DATEADD(HOUR, -24, GETDATE())), 0) AS ConversionRate24H,

    -- Inventory alerts
    (SELECT COUNT(*) FROM Products p
     INNER JOIN ProductVariants pv ON p.ProductID = pv.ProductID
     WHERE pv.StockQuantity <= pv.LowStockThreshold AND pv.IsActive = 1) AS LowStockProducts,
    (SELECT COUNT(*) FROM Products WHERE IsActive = 1) AS TotalActiveProducts,

    -- Customer metrics
    (SELECT COUNT(*) FROM Customers WHERE CreatedDate >= DATEADD(DAY, -30, GETDATE())) AS NewCustomers30Days,
    (SELECT AVG(TotalAmount) FROM Orders WHERE OrderDate >= DATEADD(DAY, -30, GETDATE())) AS AvgOrderValue30Days,

    -- Payment status
    (SELECT COUNT(*) FROM Payments WHERE PaymentStatus = 'Pending' AND PaymentDate >= DATEADD(HOUR, -24, GETDATE())) AS PendingPayments24H,
    (SELECT COUNT(*) FROM Payments WHERE PaymentStatus = 'Failed' AND PaymentDate >= DATEADD(HOUR, -24, GETDATE())) AS FailedPayments24H

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This e-commerce database schema provides a comprehensive foundation for modern online retail platforms, supporting high-volume transactions, complex product catalogs, multi-channel sales, and enterprise-level analytics while maintaining high performance and scalability.
