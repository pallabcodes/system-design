# Financial Services Platform Database Design

## Overview

This comprehensive database schema supports modern financial services platforms including retail banking, investment management, payment processing, risk management, and regulatory compliance. The design handles complex financial transactions, multi-currency operations, real-time analytics, and enterprise-level security.

## Key Features

### 🏦 Core Banking & Accounts
- **Multi-product account management** with checking, savings, CDs, and investment accounts
- **Complex transaction processing** with real-time balance updates and transaction history
- **Multi-currency support** with automatic currency conversion and exchange rate management
- **Account hierarchies** supporting personal, business, and institutional clients

### 💳 Payment Processing & Cards
- **Credit and debit card management** with real-time authorization and settlement
- **Payment gateway integration** with fraud detection and chargeback processing
- **Digital wallet functionality** with tokenization and secure payment methods
- **International payment support** with compliance and sanctions screening

### 📊 Risk Management & Compliance
- **Real-time risk scoring** with fraud detection and anti-money laundering (AML) systems
- **Regulatory reporting** with automated compliance monitoring and audit trails
- **Know Your Customer (KYC)** processes with document verification and identity management
- **Transaction monitoring** with suspicious activity reporting and case management

## Database Schema Highlights

### Core Tables

#### Customer & Account Management
```sql
-- Customer master table with KYC compliance
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNumber NVARCHAR(20) UNIQUE NOT NULL,
    CustomerType NVARCHAR(20) NOT NULL, -- Individual, Business, Institutional
    TaxID NVARCHAR(20), -- SSN/EIN (encrypted)
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    CompanyName NVARCHAR(200),
    Email NVARCHAR(255),
    Phone NVARCHAR(20),
    DateOfBirth DATE,
    Citizenship NVARCHAR(100),
    IsActive BIT DEFAULT 1,
    KYCStatus NVARCHAR(20) DEFAULT 'Pending', -- Pending, Approved, Rejected, Expired
    KYCLastVerified DATETIME2,
    RiskScore INT DEFAULT 0,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_Customers_CustomerType CHECK (CustomerType IN ('Individual', 'Business', 'Institutional')),
    CONSTRAINT CK_Customers_KYCStatus CHECK (KYCStatus IN ('Pending', 'Approved', 'Rejected', 'Expired')),

    -- Indexes
    INDEX IX_Customers_CustomerNumber (CustomerNumber),
    INDEX IX_Customers_Type (CustomerType),
    INDEX IX_Customers_KYCStatus (KYCStatus),
    INDEX IX_Customers_IsActive (IsActive),
    INDEX IX_Customers_RiskScore (RiskScore)
);

-- Customer addresses with verification
CREATE TABLE CustomerAddresses (
    AddressID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID) ON DELETE CASCADE,
    AddressType NVARCHAR(20) DEFAULT 'Primary', -- Primary, Mailing, Business
    Street NVARCHAR(255),
    City NVARCHAR(100),
    State NVARCHAR(50),
    PostalCode NVARCHAR(20),
    Country NVARCHAR(50) DEFAULT 'USA',
    IsVerified BIT DEFAULT 0,
    VerifiedDate DATETIME2,
    VerificationMethod NVARCHAR(50),

    -- Indexes
    INDEX IX_CustomerAddresses_Customer (CustomerID),
    INDEX IX_CustomerAddresses_Type (AddressType),
    INDEX IX_CustomerAddresses_IsVerified (IsVerified)
);
```

#### Account Structure
```sql
-- Account master table
CREATE TABLE Accounts (
    AccountID INT IDENTITY(1,1) PRIMARY KEY,
    AccountNumber NVARCHAR(20) UNIQUE NOT NULL,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    AccountType NVARCHAR(50) NOT NULL, -- Checking, Savings, CD, Investment, Loan
    AccountSubType NVARCHAR(50), -- Personal, Business, etc.
    ProductID INT, -- Reference to product catalog
    Currency NVARCHAR(3) DEFAULT 'USD',
    Status NVARCHAR(20) DEFAULT 'Active',
    OpenedDate DATETIME2 DEFAULT GETDATE(),
    ClosedDate DATETIME2,
    InterestRate DECIMAL(5,4) DEFAULT 0,
    MinimumBalance DECIMAL(15,2) DEFAULT 0,
    OverdraftLimit DECIMAL(15,2) DEFAULT 0,
    CurrentBalance DECIMAL(15,2) DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Accounts_Status CHECK (Status IN ('Active', 'Inactive', 'Closed', 'Frozen')),
    CONSTRAINT CK_Accounts_Balance CHECK (CurrentBalance >= -OverdraftLimit),

    -- Indexes
    INDEX IX_Accounts_AccountNumber (AccountNumber),
    INDEX IX_Accounts_Customer (CustomerID),
    INDEX IX_Accounts_Type (AccountType),
    INDEX IX_Accounts_Status (Status),
    INDEX IX_Accounts_Currency (Currency)
);

-- Account balances (for historical tracking)
CREATE TABLE AccountBalances (
    BalanceID INT IDENTITY(1,1) PRIMARY KEY,
    AccountID INT NOT NULL REFERENCES Accounts(AccountID),
    BalanceDate DATETIME2 NOT NULL,
    OpeningBalance DECIMAL(15,2) NOT NULL,
    ClosingBalance DECIMAL(15,2) NOT NULL,
    AverageBalance DECIMAL(15,2),

    -- Constraints
    CONSTRAINT UQ_AccountBalances_AccountDate UNIQUE (AccountID, BalanceDate),

    -- Indexes
    INDEX IX_AccountBalances_Account (AccountID),
    INDEX IX_AccountBalances_Date (BalanceDate)
);
```

#### Transaction Processing
```sql
-- Transaction master table
CREATE TABLE Transactions (
    TransactionID INT IDENTITY(1,1) PRIMARY KEY,
    TransactionNumber NVARCHAR(50) UNIQUE NOT NULL,
    AccountID INT NOT NULL REFERENCES Accounts(AccountID),
    TransactionType NVARCHAR(50) NOT NULL, -- Deposit, Withdrawal, Transfer, Fee, Interest
    Amount DECIMAL(15,2) NOT NULL,
    Currency NVARCHAR(3) DEFAULT 'USD',
    ExchangeRate DECIMAL(10,6) DEFAULT 1.0,
    TransactionDate DATETIME2 DEFAULT GETDATE(),
    ValueDate DATETIME2 DEFAULT GETDATE(),
    Description NVARCHAR(500),
    ReferenceNumber NVARCHAR(100),
    Channel NVARCHAR(50), -- Branch, ATM, Online, Mobile, API
    Location NVARCHAR(255),
    Status NVARCHAR(20) DEFAULT 'Completed',

    -- Related accounts for transfers
    RelatedAccountID INT REFERENCES Accounts(AccountID),
    RelatedTransactionID INT REFERENCES Transactions(TransactionID),

    -- Audit fields
    CreatedBy NVARCHAR(100),
    ApprovedBy NVARCHAR(100),
    ApprovedDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_Transactions_Status CHECK (Status IN ('Pending', 'Completed', 'Failed', 'Reversed')),
    CONSTRAINT CK_Transactions_Amount CHECK (Amount != 0),

    -- Indexes
    INDEX IX_Transactions_Account (AccountID),
    INDEX IX_Transactions_Type (TransactionType),
    INDEX IX_Transactions_Date (TransactionDate),
    INDEX IX_Transactions_Status (Status),
    INDEX IX_Transactions_Reference (ReferenceNumber)
);

-- Transaction categories for reporting
CREATE TABLE TransactionCategories (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL,
    CategoryType NVARCHAR(50), -- Income, Expense, Transfer, Fee
    IsActive BIT DEFAULT 1,

    -- Indexes
    INDEX IX_TransactionCategories_Type (CategoryType),
    INDEX IX_TransactionCategories_IsActive (IsActive)
);
```

### Payment Cards & Digital Wallets

#### Card Management
```sql
-- Payment cards
CREATE TABLE PaymentCards (
    CardID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    AccountID INT REFERENCES Accounts(AccountID),
    CardNumber VARBINARY(256), -- Encrypted
    LastFour NVARCHAR(4),
    CardType NVARCHAR(20), -- Debit, Credit
    Network NVARCHAR(20), -- Visa, Mastercard, Amex
    ExpiryMonth INT,
    ExpiryYear INT,
    CVV VARBINARY(128), -- Encrypted
    Status NVARCHAR(20) DEFAULT 'Active',
    IssuedDate DATETIME2 DEFAULT GETDATE(),
    ActivatedDate DATETIME2,
    PINHash NVARCHAR(255),
    DailyLimit DECIMAL(10,2),
    MonthlyLimit DECIMAL(10,2),

    -- Constraints
    CONSTRAINT CK_PaymentCards_Status CHECK (Status IN ('Active', 'Inactive', 'Blocked', 'Expired')),
    CONSTRAINT CK_PaymentCards_Expiry CHECK (ExpiryYear >= YEAR(GETDATE())),

    -- Indexes
    INDEX IX_PaymentCards_Customer (CustomerID),
    INDEX IX_PaymentCards_Account (AccountID),
    INDEX IX_PaymentCards_Status (Status),
    INDEX IX_PaymentCards_LastFour (LastFour)
);

-- Card transactions
CREATE TABLE CardTransactions (
    CardTransactionID INT IDENTITY(1,1) PRIMARY KEY,
    CardID INT NOT NULL REFERENCES PaymentCards(CardID),
    TransactionID INT REFERENCES Transactions(TransactionID),
    MerchantName NVARCHAR(200),
    MerchantCategory NVARCHAR(100),
    Amount DECIMAL(10,2) NOT NULL,
    Currency NVARCHAR(3) DEFAULT 'USD',
    TransactionDate DATETIME2 DEFAULT GETDATE(),
    AuthorizationCode NVARCHAR(20),
    ReferenceNumber NVARCHAR(50),
    Status NVARCHAR(20) DEFAULT 'Approved',

    -- Fraud detection
    RiskScore INT DEFAULT 0,
    IsFlagged BIT DEFAULT 0,
    FlaggedReason NVARCHAR(500),

    -- Location data
    Latitude DECIMAL(10,7),
    Longitude DECIMAL(10,7),
    IPAddress NVARCHAR(45),

    -- Indexes
    INDEX IX_CardTransactions_Card (CardID),
    INDEX IX_CardTransactions_Date (TransactionDate),
    INDEX IX_CardTransactions_Status (Status),
    INDEX IX_CardTransactions_IsFlagged (IsFlagged)
);
```

### Risk Management & Compliance

#### Fraud Detection
```sql
-- Fraud alerts and cases
CREATE TABLE FraudAlerts (
    AlertID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT REFERENCES Customers(CustomerID),
    AccountID INT REFERENCES Accounts(AccountID),
    CardID INT REFERENCES PaymentCards(CardID),
    AlertType NVARCHAR(50) NOT NULL, -- Suspicious Transaction, Unusual Pattern, etc.
    Severity NVARCHAR(20) DEFAULT 'Medium',
    Description NVARCHAR(MAX),
    AlertDate DATETIME2 DEFAULT GETDATE(),
    Status NVARCHAR(20) DEFAULT 'Open',
    AssignedTo NVARCHAR(100),
    Resolution NVARCHAR(MAX),
    ResolvedDate DATETIME2,

    -- Risk scoring
    RiskScore INT,
    TransactionAmount DECIMAL(15,2),
    Location NVARCHAR(255),

    -- Constraints
    CONSTRAINT CK_FraudAlerts_Status CHECK (Status IN ('Open', 'Investigating', 'Resolved', 'Closed')),
    CONSTRAINT CK_FraudAlerts_Severity CHECK (Severity IN ('Low', 'Medium', 'High', 'Critical')),

    -- Indexes
    INDEX IX_FraudAlerts_Customer (CustomerID),
    INDEX IX_FraudAlerts_Type (AlertType),
    INDEX IX_FraudAlerts_Status (Status),
    INDEX IX_FraudAlerts_Date (AlertDate),
    INDEX IX_FraudAlerts_RiskScore (RiskScore)
);

-- Suspicious activity patterns
CREATE TABLE SuspiciousPatterns (
    PatternID INT IDENTITY(1,1) PRIMARY KEY,
    PatternName NVARCHAR(200) NOT NULL,
    PatternType NVARCHAR(50), -- Transaction Velocity, Amount Threshold, Geographic
    ThresholdValue DECIMAL(15,2),
    TimeWindowMinutes INT,
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Indexes
    INDEX IX_SuspiciousPatterns_Type (PatternType),
    INDEX IX_SuspiciousPatterns_IsActive (IsActive)
);
```

#### Regulatory Reporting
```sql
-- Regulatory reports and filings
CREATE TABLE RegulatoryReports (
    ReportID INT IDENTITY(1,1) PRIMARY KEY,
    ReportType NVARCHAR(100) NOT NULL, -- SAR, CTR, AML, KYC
    ReportPeriod NVARCHAR(20), -- Daily, Weekly, Monthly, Quarterly
    ReportDate DATETIME2 DEFAULT GETDATE(),
    DueDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Pending',
    FiledDate DATETIME2,
    ConfirmationNumber NVARCHAR(100),
    ReportData NVARCHAR(MAX), -- JSON structured data

    -- Audit fields
    PreparedBy NVARCHAR(100),
    ReviewedBy NVARCHAR(100),
    ApprovedBy NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_RegulatoryReports_Status CHECK (Status IN ('Pending', 'Prepared', 'Reviewed', 'Filed', 'Rejected')),

    -- Indexes
    INDEX IX_RegulatoryReports_Type (ReportType),
    INDEX IX_RegulatoryReports_Status (Status),
    INDEX IX_RegulatoryReports_Date (ReportDate),
    INDEX IX_RegulatoryReports_DueDate (DueDate)
);

-- Compliance monitoring
CREATE TABLE ComplianceChecks (
    CheckID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT REFERENCES Customers(CustomerID),
    AccountID INT REFERENCES Accounts(AccountID),
    CheckType NVARCHAR(50) NOT NULL, -- KYC, AML, Sanctions, PEP
    CheckDate DATETIME2 DEFAULT GETDATE(),
    Status NVARCHAR(20) DEFAULT 'Passed',
    Result NVARCHAR(MAX), -- JSON detailed results
    RiskLevel NVARCHAR(20),
    NextReviewDate DATETIME2,
    ReviewedBy NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_ComplianceChecks_Status CHECK (Status IN ('Passed', 'Failed', 'Pending', 'Requires Review')),

    -- Indexes
    INDEX IX_ComplianceChecks_Customer (CustomerID),
    INDEX IX_ComplianceChecks_Type (CheckType),
    INDEX IX_ComplianceChecks_Status (Status),
    INDEX IX_ComplianceChecks_Date (CheckDate),
    INDEX IX_ComplianceChecks_NextReview (NextReviewDate)
);
```

### Advanced Features

#### Investment & Wealth Management
```sql
-- Investment accounts and portfolios
CREATE TABLE InvestmentAccounts (
    InvestmentAccountID INT IDENTITY(1,1) PRIMARY KEY,
    AccountID INT NOT NULL REFERENCES Accounts(AccountID),
    PortfolioName NVARCHAR(200),
    InvestmentStrategy NVARCHAR(100),
    RiskTolerance NVARCHAR(20), -- Conservative, Moderate, Aggressive
    TargetAllocation NVARCHAR(MAX), -- JSON asset allocation targets
    CurrentValue DECIMAL(15,2),
    LastRebalanced DATETIME2,

    -- Indexes
    INDEX IX_InvestmentAccounts_Account (AccountID),
    INDEX IX_InvestmentAccounts_Strategy (InvestmentStrategy)
);

-- Securities and holdings
CREATE TABLE Securities (
    SecurityID INT IDENTITY(1,1) PRIMARY KEY,
    Symbol NVARCHAR(20) UNIQUE NOT NULL,
    SecurityName NVARCHAR(200) NOT NULL,
    SecurityType NVARCHAR(50), -- Stock, Bond, ETF, Mutual Fund, Crypto
    AssetClass NVARCHAR(50), -- Equity, Fixed Income, Alternative
    CurrentPrice DECIMAL(10,2),
    MarketCap DECIMAL(15,2),
    LastUpdated DATETIME2 DEFAULT GETDATE(),

    -- Indexes
    INDEX IX_Securities_Symbol (Symbol),
    INDEX IX_Securities_Type (SecurityType),
    INDEX IX_Securities_AssetClass (AssetClass)
);

-- Portfolio holdings
CREATE TABLE PortfolioHoldings (
    HoldingID INT IDENTITY(1,1) PRIMARY KEY,
    InvestmentAccountID INT NOT NULL REFERENCES InvestmentAccounts(InvestmentAccountID),
    SecurityID INT NOT NULL REFERENCES Securities(SecurityID),
    Quantity DECIMAL(15,6) NOT NULL,
    AverageCost DECIMAL(10,2),
    CurrentValue DECIMAL(15,2),
    UnrealizedGainLoss DECIMAL(15,2),
    LastUpdated DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT UQ_PortfolioHoldings_AccountSecurity UNIQUE (InvestmentAccountID, SecurityID),

    -- Indexes
    INDEX IX_PortfolioHoldings_Account (InvestmentAccountID),
    INDEX IX_PortfolioHoldings_Security (SecurityID),
    INDEX IX_PortfolioHoldings_LastUpdated (LastUpdated)
);
```

#### Real-Time Analytics
```sql
-- Customer financial analytics
CREATE TABLE CustomerAnalytics (
    AnalyticsID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    Date DATE NOT NULL,
    TotalBalance DECIMAL(15,2),
    TotalDeposits DECIMAL(15,2),
    TotalWithdrawals DECIMAL(15,2),
    TransactionCount INT,
    AvgTransactionAmount DECIMAL(10,2),
    RiskScoreChange INT,
    LastActivityDate DATETIME2,

    -- Constraints
    CONSTRAINT UQ_CustomerAnalytics_CustomerDate UNIQUE (CustomerID, Date),

    -- Indexes
    INDEX IX_CustomerAnalytics_Customer (CustomerID),
    INDEX IX_CustomerAnalytics_Date (Date)
);

-- Account performance metrics
CREATE TABLE AccountPerformance (
    PerformanceID INT IDENTITY(1,1) PRIMARY KEY,
    AccountID INT NOT NULL REFERENCES Accounts(AccountID),
    Date DATE NOT NULL,
    OpeningBalance DECIMAL(15,2),
    ClosingBalance DECIMAL(15,2),
    NetDeposits DECIMAL(15,2),
    NetWithdrawals DECIMAL(15,2),
    InterestEarned DECIMAL(10,2),
    FeesCharged DECIMAL(10,2),
    ReturnOnAssets DECIMAL(5,4),

    -- Constraints
    CONSTRAINT UQ_AccountPerformance_AccountDate UNIQUE (AccountID, Date),

    -- Indexes
    INDEX IX_AccountPerformance_Account (AccountID),
    INDEX IX_AccountPerformance_Date (Date)
);
```

## Integration Points

### External Systems
- **Payment Networks**: Visa, Mastercard, ACH, wire transfer systems
- **Credit Bureaus**: Equifax, Experian, TransUnion for credit scoring
- **Regulatory Systems**: FinCEN, OFAC for sanctions and AML compliance
- **Market Data Providers**: Bloomberg, Reuters for investment data
- **Core Banking Systems**: Integration with existing banking platforms
- **Financial Exchanges**: Direct market access for trading platforms

### API Endpoints
- **Account Management APIs**: Account creation, balance inquiries, transaction history
- **Payment Processing APIs**: Card authorization, settlement, chargebacks
- **Risk Management APIs**: Fraud detection, compliance monitoring, alerts
- **Investment APIs**: Portfolio management, trading, market data
- **Regulatory APIs**: Automated reporting, compliance checks, audit trails

## Monitoring & Analytics

### Key Performance Indicators
- **Financial Performance**: Net interest income, fee revenue, operating expenses, profitability ratios
- **Risk Metrics**: Non-performing assets, charge-off rates, risk-weighted assets, capital adequacy
- **Customer Metrics**: Customer acquisition cost, lifetime value, retention rates, satisfaction scores
- **Operational Efficiency**: Transaction processing time, system uptime, error rates
- **Compliance Metrics**: Regulatory violations, audit findings, remediation time

### Real-Time Dashboards
```sql
-- Financial services operations dashboard
CREATE VIEW FinancialServicesDashboard AS
SELECT
    -- Financial metrics (current month)
    (SELECT COUNT(*) FROM Transactions
     WHERE TransactionDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS MonthlyTransactions,
    (SELECT SUM(Amount) FROM Transactions
     WHERE TransactionType = 'Deposit'
     AND TransactionDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS MonthlyDeposits,
    (SELECT SUM(Amount) FROM Transactions
     WHERE TransactionType = 'Withdrawal'
     AND TransactionDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS MonthlyWithdrawals,
    (SELECT AVG(CurrentBalance) FROM Accounts WHERE Status = 'Active') AS AvgAccountBalance,

    -- Risk and compliance metrics
    (SELECT COUNT(*) FROM FraudAlerts
     WHERE AlertDate >= DATEADD(DAY, -30, GETDATE())
     AND Status = 'Open') AS OpenFraudAlerts,
    (SELECT COUNT(*) FROM Customers
     WHERE KYCStatus = 'Pending') AS PendingKYCCustomers,
    (SELECT COUNT(*) FROM ComplianceChecks
     WHERE Status = 'Failed'
     AND CheckDate >= DATEADD(DAY, -30, GETDATE())) AS FailedComplianceChecks,

    -- Customer metrics
    (SELECT COUNT(*) FROM Customers
     WHERE CreatedDate >= DATEADD(MONTH, -1, GETDATE())) AS NewCustomersMonth,
    (SELECT COUNT(*) FROM Accounts WHERE Status = 'Active') AS ActiveAccounts,
    (SELECT COUNT(*) FROM PaymentCards WHERE Status = 'Active') AS ActiveCards,

    -- System health
    (SELECT COUNT(*) FROM CardTransactions
     WHERE TransactionDate >= DATEADD(HOUR, -24, GETDATE())
     AND Status = 'Approved') * 100.0 /
    NULLIF((SELECT COUNT(*) FROM CardTransactions
            WHERE TransactionDate >= DATEADD(HOUR, -24, GETDATE())), 0) AS CardApprovalRate,

    -- Investment metrics
    (SELECT SUM(CurrentValue) FROM InvestmentAccounts) AS TotalAssetsUnderManagement,
    (SELECT AVG(CAST(r.RiskScore AS DECIMAL(10,2))) FROM Customers c
     INNER JOIN FraudAlerts r ON c.CustomerID = r.CustomerID
     WHERE r.Status = 'Open') AS AverageCustomerRiskScore

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This financial services database schema provides a comprehensive foundation for modern banking and financial platforms, incorporating regulatory compliance, risk management, real-time processing, and enterprise-level security while maintaining high performance and data integrity.
