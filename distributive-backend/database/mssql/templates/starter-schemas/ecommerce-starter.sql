-- E-commerce Platform Starter Schema (SQL Server)
-- Minimal but complete schema for launching an e-commerce platform
-- Includes essential tables for products, orders, users, and inventory

-- ===========================================
-- USERS AND AUTHENTICATION
-- ===========================================

CREATE TABLE Users
(
    UserID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    Email NVARCHAR(255) UNIQUE NOT NULL,
    PasswordHash NVARCHAR(255) NOT NULL,
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Phone NVARCHAR(20),
    IsActive BIT DEFAULT 1,
    EmailVerified BIT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE UserAddresses
(
    AddressID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID) ON DELETE CASCADE,
    AddressType NVARCHAR(20) DEFAULT 'shipping' CHECK (AddressType IN ('billing', 'shipping')),
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    Company NVARCHAR(100),
    AddressLine1 NVARCHAR(255) NOT NULL,
    AddressLine2 NVARCHAR(255),
    City NVARCHAR(100) NOT NULL,
    StateProvince NVARCHAR(50) NOT NULL,
    PostalCode NVARCHAR(20) NOT NULL,
    Country NVARCHAR(50) DEFAULT 'USA',
    Phone NVARCHAR(20),
    IsDefault BIT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- ===========================================
-- PRODUCTS AND CATALOG
-- ===========================================

CREATE TABLE Categories
(
    CategoryID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    CategoryName NVARCHAR(100) NOT NULL,
    Slug NVARCHAR(120) UNIQUE NOT NULL,
    Description NVARCHAR(MAX),
    ParentID UNIQUEIDENTIFIER REFERENCES Categories(CategoryID),
    IsActive BIT DEFAULT 1,
    SortOrder INT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE Products
(
    ProductID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductName NVARCHAR(255) NOT NULL,
    Slug NVARCHAR(280) UNIQUE NOT NULL,
    Description NVARCHAR(MAX),
    ShortDescription NVARCHAR(500),
    SKU NVARCHAR(100) UNIQUE NOT NULL,
    Barcode NVARCHAR(50),
    CategoryID UNIQUEIDENTIFIER REFERENCES Categories(CategoryID),
    Brand NVARCHAR(100),
    IsActive BIT DEFAULT 1,
    IsFeatured BIT DEFAULT 0,
    TrackInventory BIT DEFAULT 1,
    WeightGrams INT,
    DimensionsJSON NVARCHAR(MAX),  -- JSON: {"length": 10, "width": 5, "height": 2}
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE ProductVariants
(
    VariantID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    VariantName NVARCHAR(255),  -- e.g., "Size: Large, Color: Red"
    SKU NVARCHAR(100) UNIQUE,
    Price DECIMAL(10,2) NOT NULL,
    CompareAtPrice DECIMAL(10,2),
    CostPrice DECIMAL(10,2),
    InventoryQuantity INT DEFAULT 0,
    IsAvailable BIT DEFAULT 1,
    WeightGrams INT,
    Option1 NVARCHAR(100),  -- Size
    Option2 NVARCHAR(100),  -- Color
    Option3 NVARCHAR(100),  -- Material
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE ProductImages
(
    ImageID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID) ON DELETE CASCADE,
    VariantID UNIQUEIDENTIFIER REFERENCES ProductVariants(VariantID),
    ImageURL NVARCHAR(500) NOT NULL,
    AltText NVARCHAR(255),
    DisplayOrder INT DEFAULT 0,
    IsPrimary BIT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- ===========================================
-- SHOPPING CART
-- ===========================================

CREATE TABLE Carts
(
    CartID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID UNIQUEIDENTIFIER REFERENCES Users(UserID),
    SessionID NVARCHAR(255),  -- For anonymous users
    IsActive BIT DEFAULT 1,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE CartItems
(
    CartItemID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    CartID UNIQUEIDENTIFIER NOT NULL REFERENCES Carts(CartID) ON DELETE CASCADE,
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID),
    VariantID UNIQUEIDENTIFIER REFERENCES ProductVariants(VariantID),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- ===========================================
-- ORDERS
-- ===========================================

CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderNumber NVARCHAR(50) UNIQUE NOT NULL,
    UserID UNIQUEIDENTIFIER NOT NULL REFERENCES Users(UserID),
    Status NVARCHAR(20) DEFAULT 'pending' CHECK (Status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled')),
    
    -- Addresses
    ShippingAddressID UNIQUEIDENTIFIER REFERENCES UserAddresses(AddressID),
    BillingAddressID UNIQUEIDENTIFIER REFERENCES UserAddresses(AddressID),
    
    -- Financials
    Subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
    TaxAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    ShippingAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    DiscountAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    TotalAmount AS (Subtotal + TaxAmount + ShippingAmount - DiscountAmount) PERSISTED,
    
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE OrderItems
(
    OrderItemID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderID UNIQUEIDENTIFIER NOT NULL REFERENCES Orders(OrderID) ON DELETE CASCADE,
    ProductID UNIQUEIDENTIFIER NOT NULL REFERENCES Products(ProductID),
    VariantID UNIQUEIDENTIFIER REFERENCES ProductVariants(VariantID),
    ProductName NVARCHAR(255) NOT NULL,  -- Denormalized for historical accuracy
    SKU NVARCHAR(100),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    TotalPrice AS (Quantity * UnitPrice) PERSISTED,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- ===========================================
-- INDEXES
-- ===========================================

CREATE INDEX IX_UserAddresses_UserID ON UserAddresses(UserID);
CREATE INDEX IX_Products_CategoryID ON Products(CategoryID);
CREATE INDEX IX_Products_SKU ON Products(SKU);
CREATE INDEX IX_ProductVariants_ProductID ON ProductVariants(ProductID);
CREATE INDEX IX_ProductImages_ProductID ON ProductImages(ProductID);
CREATE INDEX IX_Carts_UserID ON Carts(UserID);
CREATE INDEX IX_CartItems_CartID ON CartItems(CartID);
CREATE INDEX IX_Orders_UserID ON Orders(UserID);
CREATE INDEX IX_Orders_Status ON Orders(Status);
CREATE INDEX IX_OrderItems_OrderID ON OrderItems(OrderID);

