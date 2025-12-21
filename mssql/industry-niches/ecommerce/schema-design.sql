-- E-Commerce Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE ECommerceDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE ECommerceDB;
GO

-- Configure database options
ALTER DATABASE ECommerceDB
SET
    RECOVERY SIMPLE,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON;
GO

-- =============================================
-- CUSTOMER MANAGEMENT
-- =============================================

-- Customer accounts
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    PasswordHash NVARCHAR(255),
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Phone NVARCHAR(20),
    DateOfBirth DATE,
    Gender CHAR(1) CHECK (Gender IN ('M', 'F', 'O', 'U')),
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastLoginDate DATETIME2,
    EmailVerified BIT DEFAULT 0,
    MarketingOptIn BIT DEFAULT 0,

    -- Indexes
    INDEX IX_Customers_Email (Email),
    INDEX IX_Customers_IsActive (IsActive),
    INDEX IX_Customers_CreatedDate (CreatedDate),
    INDEX IX_Customers_LastLogin (LastLoginDate)
);

-- Customer addresses
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

-- =============================================
-- PRODUCT CATALOG
-- =============================================

-- Product categories
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
    Weight DECIMAL(8,2),
    Dimensions NVARCHAR(100), -- JSON: {"length": 10, "width": 5, "height": 2}

    -- Full-text search
    INDEX IX_Products_FullText (ProductName, Description, ShortDescription) WHERE IsActive = 1,

    -- Indexes
    INDEX IX_Products_SKU (SKU),
    INDEX IX_Products_Category (CategoryID),
    INDEX IX_Products_Brand (Brand),
    INDEX IX_Products_Type (ProductType),
    INDEX IX_Products_IsActive (IsActive)
);

-- Product images
CREATE TABLE ProductImages (
    ImageID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    ImageURL NVARCHAR(500) NOT NULL,
    AltText NVARCHAR(200),
    DisplayOrder INT DEFAULT 0,
    IsPrimary BIT DEFAULT 0,

    -- Indexes
    INDEX IX_ProductImages_Product (ProductID),
    INDEX IX_ProductImages_IsPrimary (ProductID) WHERE IsPrimary = 1
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

-- =============================================
-- PRICING & PROMOTIONS
-- =============================================

-- Pricing rules
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

-- =============================================
-- INVENTORY MANAGEMENT
-- =============================================

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

-- Inventory transactions
CREATE TABLE InventoryTransactions (
    TransactionID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    VariantID INT REFERENCES ProductVariants(VariantID),
    TransactionType NVARCHAR(20) NOT NULL, -- Sale, Purchase, Adjustment, Return
    Quantity INT NOT NULL,
    ReferenceID INT, -- OrderID, PurchaseOrderID, etc.
    TransactionDate DATETIME2 DEFAULT GETDATE(),
    Notes NVARCHAR(MAX),

    -- Indexes
    INDEX IX_InventoryTransactions_Product (ProductID),
    INDEX IX_InventoryTransactions_Type (TransactionType),
    INDEX IX_InventoryTransactions_Date (TransactionDate)
);

-- =============================================
-- SHOPPING CART & ORDERS
-- =============================================

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

-- =============================================
-- PAYMENT PROCESSING
-- =============================================

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

-- =============================================
-- REVIEWS & RATINGS
-- =============================================

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

-- =============================================
-- ANALYTICS & REPORTING
-- =============================================

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

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Product catalog view
CREATE VIEW vw_ProductCatalog
AS
SELECT
    p.ProductID,
    p.ProductName,
    p.SKU,
    p.Description,
    pv.VariantID,
    pv.VariantName,
    pv.VariantSKU,
    pv.Price,
    pv.CompareAtPrice,
    pv.StockQuantity,
    c.CategoryName,
    pi.ImageURL AS PrimaryImage,
    AVG(CAST(pr.Rating AS DECIMAL(3,2))) AS AvgRating,
    COUNT(pr.ReviewID) AS ReviewCount
FROM Products p
LEFT JOIN ProductVariants pv ON p.ProductID = pv.ProductID AND pv.IsActive = 1
INNER JOIN Categories c ON p.CategoryID = c.CategoryID
LEFT JOIN ProductImages pi ON p.ProductID = pi.ProductID AND pi.IsPrimary = 1
LEFT JOIN ProductReviews pr ON p.ProductID = pr.ProductID AND pr.IsPublished = 1
WHERE p.IsActive = 1
GROUP BY p.ProductID, p.ProductName, p.SKU, p.Description, pv.VariantID,
         pv.VariantName, pv.VariantSKU, pv.Price, pv.CompareAtPrice, pv.StockQuantity,
         c.CategoryName, pi.ImageURL;
GO

-- Order summary view
CREATE VIEW vw_OrderSummary
AS
SELECT
    o.OrderID,
    o.OrderNumber,
    o.OrderDate,
    o.OrderStatus,
    o.TotalAmount,
    c.FirstName + ' ' + c.LastName AS CustomerName,
    c.Email,
    COUNT(oi.OrderItemID) AS ItemCount,
    SUM(oi.Quantity) AS TotalQuantity
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
GROUP BY o.OrderID, o.OrderNumber, o.OrderDate, o.OrderStatus,
         o.TotalAmount, c.FirstName, c.LastName, c.Email;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Add to cart procedure
CREATE PROCEDURE sp_AddToCart
    @CustomerID INT = NULL,
    @SessionID NVARCHAR(255) = NULL,
    @ProductID INT,
    @VariantID INT = NULL,
    @Quantity INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CartID INT;
    DECLARE @UnitPrice DECIMAL(10,2);

    -- Get or create cart
    IF @CustomerID IS NOT NULL
    BEGIN
        SELECT @CartID = CartID FROM ShoppingCarts WHERE CustomerID = @CustomerID;

        IF @CartID IS NULL
        BEGIN
            INSERT INTO ShoppingCarts (CustomerID) VALUES (@CustomerID);
            SET @CartID = SCOPE_IDENTITY();
        END
    END
    ELSE IF @SessionID IS NOT NULL
    BEGIN
        SELECT @CartID = CartID FROM ShoppingCarts WHERE SessionID = @SessionID;

        IF @CartID IS NULL
        BEGIN
            INSERT INTO ShoppingCarts (SessionID) VALUES (@SessionID);
            SET @CartID = SCOPE_IDENTITY();
        END
    END

    -- Get product price
    IF @VariantID IS NOT NULL
        SELECT @UnitPrice = Price FROM ProductVariants WHERE VariantID = @VariantID;
    ELSE
        SELECT @UnitPrice = Price FROM ProductVariants WHERE ProductID = @ProductID AND IsActive = 1;

    -- Add or update cart item
    MERGE CartItems AS target
    USING (SELECT @CartID, @ProductID, @VariantID, @Quantity, @UnitPrice) AS source
        (CartID, ProductID, VariantID, Quantity, UnitPrice)
    ON target.CartID = source.CartID AND target.ProductID = source.ProductID
       AND ISNULL(target.VariantID, 0) = ISNULL(source.VariantID, 0)
    WHEN MATCHED THEN
        UPDATE SET Quantity = Quantity + source.Quantity
    WHEN NOT MATCHED THEN
        INSERT (CartID, ProductID, VariantID, Quantity, UnitPrice)
        VALUES (source.CartID, source.ProductID, source.VariantID, source.Quantity, source.UnitPrice);

    -- Update cart timestamp
    UPDATE ShoppingCarts SET UpdatedDate = GETDATE() WHERE CartID = @CartID;
END;
GO

-- Create order procedure
CREATE PROCEDURE sp_CreateOrder
    @CustomerID INT,
    @ShippingAddressID INT,
    @BillingAddressID INT = NULL,
    @PaymentMethodID INT = NULL,
    @DiscountCode NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @OrderID INT;
    DECLARE @Subtotal DECIMAL(10,2) = 0;
    DECLARE @DiscountAmount DECIMAL(10,2) = 0;
    DECLARE @OrderNumber NVARCHAR(50);

    -- Generate order number
    SET @OrderNumber = 'ORD-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                      RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) +
                      RIGHT('00' + CAST(DAY(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                      RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    -- Get cart items and calculate subtotal
    SELECT @Subtotal = SUM(ci.Quantity * ci.UnitPrice)
    FROM ShoppingCarts sc
    INNER JOIN CartItems ci ON sc.CartID = ci.CartID
    WHERE sc.CustomerID = @CustomerID;

    -- Apply discount if provided
    IF @DiscountCode IS NOT NULL
    BEGIN
        SELECT @DiscountAmount = CASE
            WHEN pr.RuleType = 'Percentage' THEN @Subtotal * (pr.DiscountValue / 100)
            WHEN pr.RuleType = 'Fixed' THEN pr.DiscountValue
            ELSE 0
        END
        FROM PricingRules pr
        WHERE pr.RuleName = @DiscountCode
        AND pr.IsActive = 1
        AND pr.StartDate <= GETDATE()
        AND (pr.EndDate IS NULL OR pr.EndDate >= GETDATE())
        AND (pr.UsageLimit IS NULL OR pr.UsedCount < pr.UsageLimit);
    END

    -- Create order
    INSERT INTO Orders (
        OrderNumber, CustomerID, ShippingAddressID, BillingAddressID,
        Subtotal, DiscountAmount, TotalAmount, PaymentMethod
    )
    VALUES (
        @OrderNumber, @CustomerID, @ShippingAddressID,
        ISNULL(@BillingAddressID, @ShippingAddressID),
        @Subtotal, @DiscountAmount, @Subtotal - @DiscountAmount,
        CASE WHEN @PaymentMethodID IS NOT NULL THEN 'Saved Card' ELSE 'Pending' END
    );

    SET @OrderID = SCOPE_IDENTITY();

    -- Move cart items to order items
    INSERT INTO OrderItems (OrderID, ProductID, VariantID, ProductName, SKU, Quantity, UnitPrice, LineTotal)
    SELECT @OrderID, ci.ProductID, ci.VariantID,
           p.ProductName, ISNULL(pv.VariantSKU, p.SKU),
           ci.Quantity, ci.UnitPrice, ci.Quantity * ci.UnitPrice
    FROM ShoppingCarts sc
    INNER JOIN CartItems ci ON sc.CartID = ci.CartID
    INNER JOIN Products p ON ci.ProductID = p.ProductID
    LEFT JOIN ProductVariants pv ON ci.VariantID = pv.VariantID
    WHERE sc.CustomerID = @CustomerID;

    -- Update product stock
    UPDATE pv
    SET pv.StockQuantity = pv.StockQuantity - ci.Quantity
    FROM ProductVariants pv
    INNER JOIN CartItems ci ON pv.VariantID = ci.VariantID
    INNER JOIN ShoppingCarts sc ON ci.CartID = sc.CartID
    WHERE sc.CustomerID = @CustomerID;

    -- Clear cart
    DELETE ci FROM CartItems ci
    INNER JOIN ShoppingCarts sc ON ci.CartID = sc.CartID
    WHERE sc.CustomerID = @CustomerID;

    DELETE FROM ShoppingCarts WHERE CustomerID = @CustomerID;

    -- Update discount usage
    IF @DiscountCode IS NOT NULL AND @DiscountAmount > 0
    BEGIN
        UPDATE PricingRules
        SET UsedCount = UsedCount + 1
        WHERE RuleName = @DiscountCode;
    END

    SELECT @OrderID AS OrderID, @OrderNumber AS OrderNumber;

    COMMIT TRANSACTION;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample categories
INSERT INTO Categories (CategoryName, Description) VALUES
('Electronics', 'Electronic devices and accessories'),
('Clothing', 'Apparel and fashion items'),
('Books', 'Books and publications');

-- Insert sample products
INSERT INTO Products (ProductName, SKU, Description, CategoryID, Brand) VALUES
('Wireless Mouse', 'WM-001', 'Ergonomic wireless mouse', 1, 'TechBrand'),
('T-Shirt', 'TS-001', 'Cotton t-shirt', 2, 'FashionCo'),
('SQL Server Book', 'BK-001', 'Comprehensive SQL Server guide', 3, 'TechBooks');

-- Insert sample variants
INSERT INTO ProductVariants (ProductID, VariantSKU, VariantName, Price, StockQuantity, Attributes) VALUES
(1, 'WM-001-BLK', 'Wireless Mouse - Black', 29.99, 50, '{"color": "Black"}'),
(2, 'TS-001-L', 'T-Shirt - Large', 19.99, 25, '{"size": "Large"}'),
(3, 'BK-001-EB', 'SQL Server Book - eBook', 49.99, 100, '{"format": "eBook"}');

-- Insert sample customer
INSERT INTO Customers (Email, FirstName, LastName) VALUES
('john.doe@example.com', 'John', 'Doe');

PRINT 'E-Commerce database schema created successfully!';
GO
