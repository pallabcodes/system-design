# E-Commerce Platform Schema Design (SQL Server)

## Overview

This comprehensive e-commerce schema supports online shopping, marketplace functionality, inventory management, order processing, payments, shipping, and customer analytics. The design is optimized for SQL Server with features like temporal tables, full-text search, spatial data types, and clustered indexes.

## Key Features

* **Multi-Vendor Marketplace**: Support for multiple sellers and vendors
* **Complex Product Catalog**: Products with variations, attributes, and media
* **Advanced Inventory Management**: Multi-warehouse, stock tracking, and reservations
* **Order Processing**: Complete order lifecycle from cart to delivery
* **Payment Processing**: Multiple payment methods and providers
* **Shipping & Fulfillment**: Multi-carrier support with tracking
* **Customer Analytics**: Comprehensive user behavior and purchase analytics
* **Review & Rating System**: Product reviews with voting and moderation
* **Promotions & Discounts**: Coupons, discounts, and promotional campaigns
* **Full-Text Search**: SQL Server full-text search capabilities
* **Temporal Tables**: Built-in audit trail using system-versioned temporal tables

## SQL Server Specific Features

### Temporal Tables

The schema uses SQL Server's system-versioned temporal tables for automatic history tracking:

```sql
-- Query historical order data
SELECT * FROM Orders
FOR SYSTEM_TIME AS OF '2024-01-01 10:00:00'
WHERE OrderID = 'order-guid';

-- Query all changes between dates
SELECT * FROM Orders
FOR SYSTEM_TIME BETWEEN '2024-01-01' AND '2024-01-31'
WHERE UserID = 'user-guid';
```

### Full-Text Search

Full-text indexes are created on key text columns for advanced search:

```sql
-- Search products using full-text search
SELECT ProductID, Name, BasePrice
FROM Products
WHERE CONTAINS((Name, Description, SearchKeywords), 'wireless headphones')
  AND Status = 'active'
ORDER BY BasePrice;
```

### Spatial Data Types

Geographic data is stored using SQL Server's GEOGRAPHY type:

```sql
-- Find warehouses near a location
DECLARE @Location GEOGRAPHY = geography::Point(40.7128, -74.0060, 4326);

SELECT WarehouseID, Name,
       Geolocation.STDistance(@Location) / 1000 AS DistanceKm
FROM Warehouses
WHERE Geolocation.STDistance(@Location) <= 50000 -- 50km radius
ORDER BY DistanceKm;
```

### Computed Columns

Persisted computed columns for calculated values:

```sql
-- TotalAmount is automatically calculated
SELECT OrderID, Subtotal, TaxAmount, ShippingAmount, DiscountAmount, TotalAmount
FROM Orders
WHERE OrderID = 'order-guid';
```

## Database Architecture

### Core Entities

#### User Management

```sql
-- Multi-role user system with authentication
CREATE TABLE Users
(
    UserID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    Email NVARCHAR(255) NOT NULL,
    UserType NVARCHAR(20), -- 'customer', 'seller', 'admin'
    -- ... authentication and profile fields
);

-- Flexible address management with spatial data
CREATE TABLE Addresses
(
    AddressID UNIQUEIDENTIFIER PRIMARY KEY,
    UserID UNIQUEIDENTIFIER REFERENCES Users(UserID),
    AddressType NVARCHAR(20), -- 'shipping', 'billing'
    Geolocation GEOGRAPHY, -- SQL Server spatial type
    -- ... complete address fields
);
```

#### Product Catalog

```sql
-- Hierarchical product catalog
CREATE TABLE Categories
(
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    ParentCategoryID INT REFERENCES Categories(CategoryID),
    -- ... category metadata
);

-- Comprehensive product model
CREATE TABLE Products
(
    ProductID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    SKU NVARCHAR(50) UNIQUE NOT NULL,
    Name NVARCHAR(255) NOT NULL,
    CategoryID INT REFERENCES Categories(CategoryID),
    
    -- Pricing with sale support
    BasePrice DECIMAL(10,2) NOT NULL,
    SalePrice DECIMAL(10,2),
    
    -- Inventory tracking
    StockQuantity INT DEFAULT 0,
    StockStatus NVARCHAR(20), -- 'in_stock', 'out_of_stock'
    
    -- Full-text search enabled
    -- ... other fields
);
```

### Shopping Cart & Orders

#### Cart Management

```sql
-- Shopping carts with session support
CREATE TABLE Carts
(
    CartID UNIQUEIDENTIFIER PRIMARY KEY,
    UserID UNIQUEIDENTIFIER REFERENCES Users(UserID),
    SessionID NVARCHAR(255), -- Anonymous users
    -- ... cart metadata
);

-- Cart items with customizations
CREATE TABLE CartItems
(
    CartItemID UNIQUEIDENTIFIER PRIMARY KEY,
    CartID UNIQUEIDENTIFIER REFERENCES Carts(CartID),
    ProductID UNIQUEIDENTIFIER REFERENCES Products(ProductID),
    VariationID UNIQUEIDENTIFIER REFERENCES ProductVariations(VariationID),
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2),
    Customizations NVARCHAR(MAX), -- JSON: Gift wrapping, engraving
);
```

#### Order Processing

```sql
-- Complete order lifecycle with temporal table
CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY,
    OrderNumber NVARCHAR(50) UNIQUE NOT NULL,
    UserID UNIQUEIDENTIFIER REFERENCES Users(UserID),
    
    -- Status tracking
    Status NVARCHAR(30), -- 'pending', 'confirmed', 'shipped', 'delivered'
    PaymentStatus NVARCHAR(20),
    FulfillmentStatus NVARCHAR(20),
    
    -- Financial breakdown (computed column)
    Subtotal DECIMAL(12,2),
    TaxAmount DECIMAL(10,2),
    ShippingAmount DECIMAL(10,2),
    DiscountAmount DECIMAL(10,2),
    TotalAmount AS (Subtotal + TaxAmount + ShippingAmount - DiscountAmount) PERSISTED,
    
    -- Temporal table columns
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.OrdersHistory));
```

### Payments & Financial

#### Payment Methods

```sql
-- Multiple payment methods per user
CREATE TABLE PaymentMethods
(
    PaymentMethodID UNIQUEIDENTIFIER PRIMARY KEY,
    UserID UNIQUEIDENTIFIER REFERENCES Users(UserID),
    Type NVARCHAR(20), -- 'credit_card', 'paypal', 'apple_pay'
    Provider NVARCHAR(50), -- 'stripe', 'paypal', 'braintree'
    
    -- Tokenized for PCI compliance
    ProviderToken NVARCHAR(255),
    LastFour NVARCHAR(4), -- Last 4 digits
    -- ... payment details
);

-- Payment transactions
CREATE TABLE Payments
(
    PaymentID UNIQUEIDENTIFIER PRIMARY KEY,
    OrderID UNIQUEIDENTIFIER REFERENCES Orders(OrderID),
    Amount DECIMAL(12,2),
    Provider NVARCHAR(50),
    ProviderPaymentID NVARCHAR(255) UNIQUE,
    Status NVARCHAR(20), -- 'pending', 'succeeded', 'failed'
    -- ... payment metadata
);
```

### Inventory & Warehousing

#### Multi-Warehouse Support

```sql
-- Warehouse management with spatial data
CREATE TABLE Warehouses
(
    WarehouseID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100),
    Geolocation GEOGRAPHY, -- SQL Server spatial type
    -- ... warehouse details
);

-- Detailed inventory tracking
CREATE TABLE ProductInventory
(
    InventoryID UNIQUEIDENTIFIER PRIMARY KEY,
    ProductID UNIQUEIDENTIFIER REFERENCES Products(ProductID),
    VariationID UNIQUEIDENTIFIER REFERENCES ProductVariations(VariationID),
    WarehouseID INT REFERENCES Warehouses(WarehouseID),
    
    QuantityAvailable INT DEFAULT 0,
    QuantityReserved INT DEFAULT 0,
    QuantityOnOrder INT DEFAULT 0,
    
    -- Warehouse location
    Aisle NVARCHAR(20),
    Shelf NVARCHAR(20),
    Bin NVARCHAR(20),
    
    UNIQUE (ProductID, VariationID, WarehouseID)
);
```

## Usage Examples

### Product Search & Discovery

```sql
-- Advanced product search with full-text search
SELECT
    p.ProductID,
    p.Name,
    p.BasePrice,
    p.AverageRating,
    b.Name AS BrandName,
    c.Name AS CategoryName
FROM Products p
JOIN Brands b ON p.BrandID = b.BrandID
JOIN Categories c ON p.CategoryID = c.CategoryID
WHERE CONTAINS((p.Name, p.Description, p.SearchKeywords), 'wireless headphones')
  AND p.Status = 'active'
  AND p.BasePrice BETWEEN 50 AND 300
ORDER BY p.AverageRating DESC, p.BasePrice
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY;
```

### Order Processing Flow

```sql
-- Complete order creation process
BEGIN TRANSACTION;

-- 1. Create order from cart
DECLARE @OrderID UNIQUEIDENTIFIER = NEWID();
DECLARE @OrderNumber NVARCHAR(50) = 'ORD-' + UPPER(SUBSTRING(CAST(NEWID() AS NVARCHAR(36)), 1, 8));

INSERT INTO Orders (OrderID, OrderNumber, UserID, Subtotal, TaxAmount, ShippingAmount, TotalAmount)
SELECT
    @OrderID,
    @OrderNumber,
    c.UserID,
    SUM(ci.Quantity * ci.UnitPrice),
    SUM(ci.Quantity * ci.UnitPrice) * 0.08, -- 8% tax
    9.99, -- Flat shipping
    SUM(ci.Quantity * ci.UnitPrice) * 1.08 + 9.99
FROM Carts c
JOIN CartItems ci ON c.CartID = ci.CartID
WHERE c.CartID = 'cart-guid'
GROUP BY c.UserID;

-- 2. Create order items
INSERT INTO OrderItems (OrderID, ProductID, VariationID, ProductName, Quantity, UnitPrice)
SELECT
    @OrderID,
    ci.ProductID,
    ci.VariationID,
    p.Name,
    ci.Quantity,
    ci.UnitPrice
FROM CartItems ci
JOIN Products p ON ci.ProductID = p.ProductID
WHERE ci.CartID = 'cart-guid';

-- 3. Clear cart
DELETE FROM CartItems WHERE CartID = 'cart-guid';
DELETE FROM Carts WHERE CartID = 'cart-guid';

COMMIT TRANSACTION;
```

### Inventory Management

```sql
-- Check product availability across warehouses
SELECT
    p.Name AS ProductName,
    w.Name AS WarehouseName,
    pi.QuantityAvailable,
    pi.QuantityReserved,
    pi.QuantityAvailable - pi.QuantityReserved AS AvailableToSell,
    w.Geolocation.Lat AS Latitude,
    w.Geolocation.Long AS Longitude
FROM Products p
CROSS JOIN Warehouses w
LEFT JOIN ProductInventory pi ON p.ProductID = pi.ProductID
    AND w.WarehouseID = pi.WarehouseID
WHERE p.ProductID = 'product-guid'
  AND pi.QuantityAvailable > pi.QuantityReserved
ORDER BY pi.QuantityAvailable - pi.QuantityReserved DESC;
```

### Temporal Table Queries

```sql
-- Query order history at a specific point in time
SELECT OrderID, OrderNumber, Status, TotalAmount, ValidFrom, ValidTo
FROM Orders
FOR SYSTEM_TIME AS OF '2024-01-15 10:00:00'
WHERE UserID = 'user-guid';

-- Query all changes to an order
SELECT OrderID, OrderNumber, Status, TotalAmount, ValidFrom, ValidTo
FROM Orders
FOR SYSTEM_TIME ALL
WHERE OrderID = 'order-guid'
ORDER BY ValidFrom;

-- Query changes between two dates
SELECT OrderID, OrderNumber, Status, TotalAmount, ValidFrom, ValidTo
FROM Orders
FOR SYSTEM_TIME BETWEEN '2024-01-01' AND '2024-01-31'
WHERE UserID = 'user-guid';
```

## Performance Optimizations

### Key Indexes

```sql
-- Product search and filtering
CREATE INDEX IX_Products_Category_Status_Price ON Products (CategoryID, Status, BasePrice);
CREATE INDEX IX_Products_Brand_Status ON Products (BrandID, Status);

-- Order processing
CREATE INDEX IX_Orders_User_Status_Created ON Orders (UserID, Status, CreatedAt DESC);
CREATE INDEX IX_OrderItems_Order_Product ON OrderItems (OrderID, ProductID);

-- Inventory management
CREATE INDEX IX_ProductInventory_Product_Warehouse ON ProductInventory (ProductID, WarehouseID);
```

### Partitioning Strategy

For very large tables, consider partitioning:

```sql
-- Partition orders by date range
CREATE PARTITION FUNCTION PF_Orders_Date (DATETIME2)
AS RANGE RIGHT FOR VALUES ('2024-01-01', '2024-04-01', '2024-07-01', '2024-10-01');

CREATE PARTITION SCHEME PS_Orders_Date
AS PARTITION PF_Orders_Date
TO (FG_Q1, FG_Q2, FG_Q3, FG_Q4, FG_Future);

-- Apply partitioning to Orders table
-- Note: This requires recreating the table with partition scheme
```

## Security Considerations

### Row-Level Security

```sql
-- Enable RLS for multi-tenant marketplace
ALTER TABLE Products ENABLE ROW LEVEL SECURITY;

-- Sellers can only see their own products
CREATE SECURITY POLICY seller_products_policy
ADD FILTER PREDICATE dbo.fn_security_predicate_seller(SellerID) ON Products
WITH (STATE = ON);
```

### Data Encryption

```sql
-- Encrypt sensitive payment data using Always Encrypted
-- Note: Always Encrypted requires application-level changes

-- Or use column-level encryption
CREATE CERTIFICATE PaymentEncryptionCert
WITH SUBJECT = 'Payment Data Encryption';

CREATE SYMMETRIC KEY PaymentDataKey
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE PaymentEncryptionCert;

-- Encrypt payment method tokens
OPEN SYMMETRIC KEY PaymentDataKey
DECRYPTION BY CERTIFICATE PaymentEncryptionCert;

UPDATE PaymentMethods
SET ProviderToken = EncryptByKey(Key_GUID('PaymentDataKey'), ProviderToken);
```

## Monitoring & Analytics

### Key Business Metrics

* **Conversion Rate**: Carts created vs orders completed
* **Average Order Value**: Revenue per order
* **Customer Lifetime Value**: Total revenue per customer
* **Inventory Turnover**: Sales velocity
* **Return Rate**: Percentage of returned orders
* **Customer Satisfaction**: Review ratings and feedback

### Real-time Dashboards

```sql
-- Real-time sales dashboard
CREATE VIEW SalesDashboard AS
SELECT
    (SELECT COUNT(*) FROM Orders WHERE CAST(CreatedAt AS DATE) = CAST(GETDATE() AS DATE)) AS TodaysOrders,
    (SELECT SUM(TotalAmount) FROM Orders WHERE CAST(CreatedAt AS DATE) = CAST(GETDATE() AS DATE)) AS TodaysRevenue,
    (SELECT COUNT(*) FROM Users WHERE CAST(CreatedAt AS DATE) = CAST(GETDATE() AS DATE)) AS NewCustomersToday,
    (SELECT AVG(TotalAmount) FROM Orders WHERE CreatedAt >= DATEADD(DAY, -30, GETDATE())) AS AvgOrderValue30D,
    (SELECT COUNT(*) FROM Products WHERE StockQuantity = 0) AS OutOfStockProducts,
    (SELECT AVG(CAST(Rating AS DECIMAL(3,2))) FROM ProductReviews WHERE CreatedAt >= DATEADD(DAY, -30, GETDATE())) AS AvgRating30D;
```

## Integration Points

### External Systems

* **Payment processors** (Stripe, PayPal, Adyen) for secure transaction processing
* **Shipping carriers** (FedEx, UPS, DHL) for real-time shipping rates and tracking
* **Inventory management systems** (SAP, Oracle) for warehouse synchronization
* **Tax calculation services** (Avalara, TaxJar) for sales tax compliance
* **Fraud detection services** (Sift, Riskified) for transaction security
* **Email marketing platforms** (Mailchimp, Klaviyo) for customer communication

### API Endpoints

* **Order management APIs** for order processing, fulfillment, and tracking
* **Product catalog APIs** for inventory management and product information
* **Customer service APIs** for returns, exchanges, and support tickets
* **Analytics APIs** for sales reporting and business intelligence
* **Marketplace APIs** for vendor management and commission processing

This e-commerce schema provides a solid foundation for building scalable online retail platforms with marketplace capabilities, optimized for SQL Server's advanced features including temporal tables, full-text search, and spatial data types.

