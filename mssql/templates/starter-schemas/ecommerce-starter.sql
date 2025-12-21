-- E-Commerce Starter Schema
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
-- USERS & AUTHENTICATION
-- =============================================

CREATE TABLE Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    PasswordHash NVARCHAR(255),
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Phone NVARCHAR(20),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastLoginDate DATETIME2,
    IsActive BIT DEFAULT 1,
    EmailVerified BIT DEFAULT 0,

    INDEX IX_Users_Email (Email),
    INDEX IX_Users_IsActive (IsActive),
    INDEX IX_Users_CreatedDate (CreatedDate)
);

CREATE TABLE UserAddresses (
    AddressID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL REFERENCES Users(UserID) ON DELETE CASCADE,
    AddressType NVARCHAR(20) DEFAULT 'Shipping', -- Shipping, Billing
    Street NVARCHAR(255),
    City NVARCHAR(100),
    State NVARCHAR(50),
    PostalCode NVARCHAR(20),
    Country NVARCHAR(50) DEFAULT 'USA',
    IsDefault BIT DEFAULT 0,

    INDEX IX_UserAddresses_User (UserID),
    INDEX IX_UserAddresses_Type (AddressType),
    INDEX IX_UserAddresses_IsDefault (UserID) WHERE IsDefault = 1
);

-- =============================================
-- PRODUCTS & CATEGORIES
-- =============================================

CREATE TABLE Categories (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) UNIQUE NOT NULL,
    Description NVARCHAR(MAX),
    ParentCategoryID INT REFERENCES Categories(CategoryID),
    IsActive BIT DEFAULT 1,

    INDEX IX_Categories_Parent (ParentCategoryID) WHERE ParentCategoryID IS NOT NULL,
    INDEX IX_Categories_IsActive (IsActive)
);

CREATE TABLE Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(200) NOT NULL,
    SKU NVARCHAR(50) UNIQUE,
    Description NVARCHAR(MAX),
    Price DECIMAL(10,2) NOT NULL,
    CompareAtPrice DECIMAL(10,2),
    Cost DECIMAL(10,2),
    CategoryID INT REFERENCES Categories(CategoryID),
    Brand NVARCHAR(100),
    Weight DECIMAL(8,2),
    Dimensions NVARCHAR(100), -- JSON: {"length": 10, "width": 5, "height": 2}
    StockQuantity INT DEFAULT 0,
    LowStockThreshold INT DEFAULT 10,
    IsActive BIT DEFAULT 1,
    IsFeatured BIT DEFAULT 0,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    UpdatedDate DATETIME2 DEFAULT GETDATE(),

    INDEX IX_Products_Category (CategoryID),
    INDEX IX_Products_Brand (Brand),
    INDEX IX_Products_IsActive (IsActive),
    INDEX IX_Products_IsFeatured (IsFeatured),
    INDEX IX_Products_Price (Price),
    INDEX IX_Products_Stock (StockQuantity) WHERE StockQuantity <= LowStockThreshold,
    INDEX IX_Products_FullText (ProductName, Description) WHERE IsActive = 1
);

CREATE TABLE ProductImages (
    ImageID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    ImageURL NVARCHAR(500) NOT NULL,
    AltText NVARCHAR(200),
    DisplayOrder INT DEFAULT 0,
    IsPrimary BIT DEFAULT 0,

    INDEX IX_ProductImages_Product (ProductID),
    INDEX IX_ProductImages_IsPrimary (ProductID) WHERE IsPrimary = 1
);

-- =============================================
-- ORDERS & SHOPPING CART
-- =============================================

CREATE TABLE ShoppingCart (
    CartID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT REFERENCES Users(UserID) ON DELETE CASCADE,
    SessionID NVARCHAR(255), -- For anonymous users
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    UpdatedDate DATETIME2 DEFAULT GETDATE(),

    INDEX IX_ShoppingCart_User (UserID),
    INDEX IX_ShoppingCart_Session (SessionID),
    INDEX IX_ShoppingCart_Updated (UpdatedDate)
);

CREATE TABLE CartItems (
    CartItemID INT IDENTITY(1,1) PRIMARY KEY,
    CartID INT NOT NULL REFERENCES ShoppingCart(CartID) ON DELETE CASCADE,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    AddedDate DATETIME2 DEFAULT GETDATE(),

    INDEX IX_CartItems_Cart (CartID),
    INDEX IX_CartItems_Product (ProductID),
    UNIQUE (CartID, ProductID)
);

CREATE TABLE Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT REFERENCES Users(UserID),
    OrderNumber NVARCHAR(50) UNIQUE,
    OrderStatus NVARCHAR(20) DEFAULT 'Pending',
    OrderDate DATETIME2 DEFAULT GETDATE(),
    ShippingAddressID INT REFERENCES UserAddresses(AddressID),
    BillingAddressID INT REFERENCES UserAddresses(AddressID),
    Subtotal DECIMAL(10,2) NOT NULL,
    TaxAmount DECIMAL(10,2) DEFAULT 0,
    ShippingAmount DECIMAL(10,2) DEFAULT 0,
    DiscountAmount DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(10,2) NOT NULL,

    INDEX IX_Orders_User (UserID),
    INDEX IX_Orders_Status (OrderStatus),
    INDEX IX_Orders_Date (OrderDate),
    INDEX IX_Orders_OrderNumber (OrderNumber)
);

CREATE TABLE OrderItems (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES Orders(OrderID) ON DELETE CASCADE,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    Discount DECIMAL(10,2) DEFAULT 0,
    LineTotal DECIMAL(10,2) NOT NULL,

    INDEX IX_OrderItems_Order (OrderID),
    INDEX IX_OrderItems_Product (ProductID)
);

-- =============================================
-- PAYMENTS
-- =============================================

CREATE TABLE PaymentMethods (
    PaymentMethodID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL REFERENCES Users(UserID) ON DELETE CASCADE,
    MethodType NVARCHAR(20) NOT NULL, -- CreditCard, PayPal, BankTransfer
    Provider NVARCHAR(50), -- Visa, Mastercard, PayPal
    LastFour NVARCHAR(4),
    ExpiryMonth INT,
    ExpiryYear INT,
    IsDefault BIT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    INDEX IX_PaymentMethods_User (UserID),
    INDEX IX_PaymentMethods_IsDefault (UserID) WHERE IsDefault = 1
);

CREATE TABLE Payments (
    PaymentID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES Orders(OrderID),
    PaymentMethodID INT REFERENCES PaymentMethods(PaymentMethodID),
    Amount DECIMAL(10,2) NOT NULL,
    Currency NVARCHAR(3) DEFAULT 'USD',
    PaymentStatus NVARCHAR(20) DEFAULT 'Pending',
    TransactionID NVARCHAR(255),
    PaymentDate DATETIME2 DEFAULT GETDATE(),
    ProcessedDate DATETIME2,

    INDEX IX_Payments_Order (OrderID),
    INDEX IX_Payments_Status (PaymentStatus),
    INDEX IX_Payments_Transaction (TransactionID)
);

-- =============================================
-- INVENTORY MANAGEMENT
-- =============================================

CREATE TABLE InventoryTransactions (
    TransactionID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    TransactionType NVARCHAR(20) NOT NULL, -- Sale, Purchase, Adjustment, Return
    Quantity INT NOT NULL,
    ReferenceID INT, -- OrderID, PurchaseOrderID, etc.
    TransactionDate DATETIME2 DEFAULT GETDATE(),
    Notes NVARCHAR(MAX),

    INDEX IX_InventoryTransactions_Product (ProductID),
    INDEX IX_InventoryTransactions_Type (TransactionType),
    INDEX IX_InventoryTransactions_Date (TransactionDate)
);

-- =============================================
-- REVIEWS & RATINGS
-- =============================================

CREATE TABLE ProductReviews (
    ReviewID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    UserID INT REFERENCES Users(UserID),
    Rating INT CHECK (Rating BETWEEN 1 AND 5),
    Title NVARCHAR(200),
    ReviewText NVARCHAR(MAX),
    IsVerified BIT DEFAULT 0,
    IsPublished BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    HelpfulVotes INT DEFAULT 0,

    INDEX IX_ProductReviews_Product (ProductID),
    INDEX IX_ProductReviews_User (UserID),
    INDEX IX_ProductReviews_Rating (Rating),
    INDEX IX_ProductReviews_IsPublished (IsPublished),
    INDEX IX_ProductReviews_CreatedDate (CreatedDate)
);

-- =============================================
-- DISCOUNTS & PROMOTIONS
-- =============================================

CREATE TABLE Discounts (
    DiscountID INT IDENTITY(1,1) PRIMARY KEY,
    DiscountCode NVARCHAR(50) UNIQUE,
    DiscountType NVARCHAR(20) NOT NULL, -- Percentage, FixedAmount
    DiscountValue DECIMAL(10,2) NOT NULL,
    MinimumOrderAmount DECIMAL(10,2),
    MaximumDiscount DECIMAL(10,2),
    UsageLimit INT,
    UsedCount INT DEFAULT 0,
    StartDate DATETIME2,
    EndDate DATETIME2,
    IsActive BIT DEFAULT 1,

    INDEX IX_Discounts_Code (DiscountCode),
    INDEX IX_Discounts_IsActive (IsActive),
    INDEX IX_Discounts_StartEnd (StartDate, EndDate)
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
    p.Price,
    p.CompareAtPrice,
    p.StockQuantity,
    c.CategoryName,
    pi.ImageURL AS PrimaryImage,
    AVG(CAST(pr.Rating AS DECIMAL(3,2))) AS AvgRating,
    COUNT(pr.ReviewID) AS ReviewCount
FROM Products p
INNER JOIN Categories c ON p.CategoryID = c.CategoryID
LEFT JOIN ProductImages pi ON p.ProductID = pi.ProductID AND pi.IsPrimary = 1
LEFT JOIN ProductReviews pr ON p.ProductID = pr.ProductID AND pr.IsPublished = 1
WHERE p.IsActive = 1
GROUP BY p.ProductID, p.ProductName, p.SKU, p.Description, p.Price,
         p.CompareAtPrice, p.StockQuantity, c.CategoryName, pi.ImageURL;
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
    u.FirstName + ' ' + u.LastName AS CustomerName,
    u.Email,
    COUNT(oi.OrderItemID) AS ItemCount,
    SUM(oi.Quantity) AS TotalQuantity
FROM Orders o
INNER JOIN Users u ON o.UserID = u.UserID
INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
GROUP BY o.OrderID, o.OrderNumber, o.OrderDate, o.OrderStatus,
         o.TotalAmount, u.FirstName, u.LastName, u.Email;
GO

-- =============================================
-- BASIC STORED PROCEDURES
-- =============================================

-- Add to cart procedure
CREATE PROCEDURE sp_AddToCart
    @UserID INT = NULL,
    @SessionID NVARCHAR(255) = NULL,
    @ProductID INT,
    @Quantity INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CartID INT;

    -- Get or create cart
    IF @UserID IS NOT NULL
    BEGIN
        SELECT @CartID = CartID FROM ShoppingCart WHERE UserID = @UserID;

        IF @CartID IS NULL
        BEGIN
            INSERT INTO ShoppingCart (UserID) VALUES (@UserID);
            SET @CartID = SCOPE_IDENTITY();
        END
    END
    ELSE IF @SessionID IS NOT NULL
    BEGIN
        SELECT @CartID = CartID FROM ShoppingCart WHERE SessionID = @SessionID;

        IF @CartID IS NULL
        BEGIN
            INSERT INTO ShoppingCart (SessionID) VALUES (@SessionID);
            SET @CartID = SCOPE_IDENTITY();
        END
    END

    -- Add or update cart item
    MERGE CartItems AS target
    USING (SELECT @CartID, @ProductID, @Quantity, p.Price) AS source
        (CartID, ProductID, Quantity, UnitPrice)
    ON target.CartID = source.CartID AND target.ProductID = source.ProductID
    WHEN MATCHED THEN
        UPDATE SET Quantity = Quantity + source.Quantity
    WHEN NOT MATCHED THEN
        INSERT (CartID, ProductID, Quantity, UnitPrice)
        VALUES (source.CartID, source.ProductID, source.Quantity, source.UnitPrice);

    -- Update cart timestamp
    UPDATE ShoppingCart SET UpdatedDate = GETDATE() WHERE CartID = @CartID;
END;
GO

-- Create order procedure
CREATE PROCEDURE sp_CreateOrder
    @UserID INT,
    @ShippingAddressID INT,
    @BillingAddressID INT = NULL,
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
    FROM ShoppingCart sc
    INNER JOIN CartItems ci ON sc.CartID = ci.CartID
    WHERE sc.UserID = @UserID;

    -- Apply discount if provided
    IF @DiscountCode IS NOT NULL
    BEGIN
        SELECT @DiscountAmount = CASE
            WHEN d.DiscountType = 'Percentage' THEN @Subtotal * (d.DiscountValue / 100)
            WHEN d.DiscountType = 'FixedAmount' THEN d.DiscountValue
            ELSE 0
        END
        FROM Discounts d
        WHERE d.DiscountCode = @DiscountCode
        AND d.IsActive = 1
        AND d.StartDate <= GETDATE()
        AND (d.EndDate IS NULL OR d.EndDate >= GETDATE())
        AND (d.UsageLimit IS NULL OR d.UsedCount < d.UsageLimit);
    END

    -- Create order
    INSERT INTO Orders (
        UserID, OrderNumber, ShippingAddressID, BillingAddressID,
        Subtotal, DiscountAmount, TotalAmount
    )
    VALUES (
        @UserID, @OrderNumber, @ShippingAddressID,
        ISNULL(@BillingAddressID, @ShippingAddressID),
        @Subtotal, @DiscountAmount, @Subtotal - @DiscountAmount
    );

    SET @OrderID = SCOPE_IDENTITY();

    -- Move cart items to order items
    INSERT INTO OrderItems (OrderID, ProductID, Quantity, UnitPrice, LineTotal)
    SELECT @OrderID, ci.ProductID, ci.Quantity, ci.UnitPrice,
           ci.Quantity * ci.UnitPrice
    FROM ShoppingCart sc
    INNER JOIN CartItems ci ON sc.CartID = ci.CartID
    WHERE sc.UserID = @UserID;

    -- Update product stock
    UPDATE p
    SET p.StockQuantity = p.StockQuantity - ci.Quantity
    FROM Products p
    INNER JOIN CartItems ci ON p.ProductID = ci.ProductID
    INNER JOIN ShoppingCart sc ON ci.CartID = sc.CartID
    WHERE sc.UserID = @UserID;

    -- Clear cart
    DELETE ci FROM CartItems ci
    INNER JOIN ShoppingCart sc ON ci.CartID = sc.CartID
    WHERE sc.UserID = @UserID;

    DELETE FROM ShoppingCart WHERE UserID = @UserID;

    -- Update discount usage
    IF @DiscountCode IS NOT NULL AND @DiscountAmount > 0
    BEGIN
        UPDATE Discounts
        SET UsedCount = UsedCount + 1
        WHERE DiscountCode = @DiscountCode;
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
('Books', 'Books and publications'),
('Clothing', 'Apparel and fashion items');

-- Insert sample products
INSERT INTO Products (ProductName, SKU, Description, Price, CategoryID, StockQuantity) VALUES
('Wireless Mouse', 'WM-001', 'Ergonomic wireless mouse', 29.99, 1, 50),
('SQL Server Book', 'BK-001', 'Comprehensive SQL Server guide', 49.99, 2, 25),
('T-Shirt', 'TS-001', 'Cotton t-shirt', 19.99, 3, 100);

-- Insert sample user
INSERT INTO Users (Email, FirstName, LastName) VALUES
('john.doe@example.com', 'John', 'Doe');

PRINT 'E-Commerce starter database created successfully!';
GO
