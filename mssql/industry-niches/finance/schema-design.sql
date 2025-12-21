-- Financial Services Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database with financial compliance settings
CREATE DATABASE FinancialServicesDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE FinancialServicesDB;
GO

-- Configure database for financial compliance
ALTER DATABASE FinancialServicesDB
SET
    RECOVERY FULL,
    PAGE_VERIFY CHECKSUM,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON,
    ENCRYPTION ON, -- Enable TDE for financial data protection
    QUERY_STORE = ON; -- Enable query performance monitoring
GO

-- Create encryption certificate for sensitive financial data
CREATE CERTIFICATE FinancialDataEncryption
WITH SUBJECT = 'Financial Data Encryption Certificate';
GO

-- =============================================
-- CUSTOMER & ACCOUNT MANAGEMENT
-- =============================================

-- Customer master table with KYC compliance
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNumber NVARCHAR(20) UNIQUE NOT NULL,
    CustomerType NVARCHAR(20) NOT NULL, -- Individual, Business, Institutional
    TaxID VARBINARY(128), -- Encrypted SSN/EIN
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
    RiskScore INT DEFAULT 0 CHECK (RiskScore BETWEEN 0 AND 1000),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),

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

-- =============================================
-- ACCOUNT MANAGEMENT
-- =============================================

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
    AvailableBalance AS (CurrentBalance + OverdraftLimit),

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

-- Account balances (historical tracking)
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

-- =============================================
-- TRANSACTION PROCESSING
-- =============================================

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

-- =============================================
-- PAYMENT CARDS & DIGITAL PAYMENTS
-- =============================================

-- Payment cards
CREATE TABLE PaymentCards (
    CardID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    AccountID INT REFERENCES Accounts(AccountID),
    CardNumber VARBINARY(256), -- Encrypted full card number
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
    DailyLimit DECIMAL(10,2) DEFAULT 1000,
    MonthlyLimit DECIMAL(10,2) DEFAULT 5000,

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

-- =============================================
-- RISK MANAGEMENT & COMPLIANCE
-- =============================================

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

-- Compliance checks
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

-- =============================================
-- INVESTMENT & WEALTH MANAGEMENT
-- =============================================

-- Investment accounts
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

-- Securities master
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

-- =============================================
-- ANALYTICS & REPORTING
-- =============================================

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

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Customer account summary view
CREATE VIEW vw_CustomerAccountSummary
AS
SELECT
    c.CustomerID,
    c.CustomerNumber,
    c.FirstName + ' ' + c.LastName AS CustomerName,
    c.CustomerType,
    c.KYCStatus,
    c.RiskScore,
    COUNT(a.AccountID) AS TotalAccounts,
    SUM(a.CurrentBalance) AS TotalBalance,
    AVG(a.CurrentBalance) AS AvgAccountBalance,
    MAX(a.OpenedDate) AS FirstAccountDate,
    MAX(t.TransactionDate) AS LastTransactionDate
FROM Customers c
LEFT JOIN Accounts a ON c.CustomerID = a.CustomerID AND a.Status = 'Active'
LEFT JOIN Transactions t ON a.AccountID = t.AccountID
WHERE c.IsActive = 1
GROUP BY c.CustomerID, c.CustomerNumber, c.FirstName, c.LastName,
         c.CustomerType, c.KYCStatus, c.RiskScore;
GO

-- Account transaction summary view
CREATE VIEW vw_AccountTransactionSummary
AS
SELECT
    a.AccountID,
    a.AccountNumber,
    a.AccountType,
    a.CurrentBalance,
    a.AvailableBalance,
    COUNT(t.TransactionID) AS TransactionCount,
    SUM(CASE WHEN t.TransactionType = 'Deposit' THEN t.Amount ELSE 0 END) AS TotalDeposits,
    SUM(CASE WHEN t.TransactionType = 'Withdrawal' THEN t.Amount ELSE 0 END) AS TotalWithdrawals,
    SUM(CASE WHEN t.TransactionType = 'Fee' THEN t.Amount ELSE 0 END) AS TotalFees,
    MAX(t.TransactionDate) AS LastTransactionDate,
    DATEDIFF(DAY, MAX(t.TransactionDate), GETDATE()) AS DaysSinceLastTransaction
FROM Accounts a
LEFT JOIN Transactions t ON a.AccountID = t.AccountID
WHERE a.Status = 'Active'
GROUP BY a.AccountID, a.AccountNumber, a.AccountType, a.CurrentBalance, a.AvailableBalance;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Account balance update trigger
CREATE TRIGGER TR_Transactions_UpdateBalance
ON Transactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Update account balance
    UPDATE a
    SET a.CurrentBalance = a.CurrentBalance +
        CASE
            WHEN i.TransactionType IN ('Deposit', 'Transfer') THEN i.Amount
            WHEN i.TransactionType IN ('Withdrawal', 'Fee') THEN -i.Amount
            ELSE 0
        END
    FROM Accounts a
    INNER JOIN inserted i ON a.AccountID = i.AccountID
    WHERE i.Status = 'Completed';
END;
GO

-- Fraud detection trigger
CREATE TRIGGER TR_CardTransactions_FraudDetection
ON CardTransactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Simple fraud detection rules
    INSERT INTO FraudAlerts (CardID, AlertType, Severity, Description, RiskScore, TransactionAmount)
    SELECT
        i.CardID,
        'High Amount Transaction',
        'High',
        'Transaction amount exceeds threshold',
        800,
        i.Amount
    FROM inserted i
    WHERE i.Amount > 5000 AND i.Status = 'Approved'

    UNION ALL

    SELECT
        i.CardID,
        'Geographic Anomaly',
        'Medium',
        'Transaction from unusual location',
        600,
        i.Amount
    FROM inserted i
    WHERE i.Latitude IS NOT NULL AND i.Longitude IS NOT NULL
    -- Add geographic distance calculation logic here
    AND i.Status = 'Approved';
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Transfer funds between accounts
CREATE PROCEDURE sp_TransferFunds
    @FromAccountID INT,
    @ToAccountID INT,
    @Amount DECIMAL(15,2),
    @Description NVARCHAR(500) = NULL,
    @TransferType NVARCHAR(20) = 'Internal'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    -- Validate accounts
    IF NOT EXISTS (SELECT 1 FROM Accounts WHERE AccountID = @FromAccountID AND Status = 'Active')
    BEGIN
        RAISERROR('Invalid source account', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Accounts WHERE AccountID = @ToAccountID AND Status = 'Active')
    BEGIN
        RAISERROR('Invalid destination account', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- Check sufficient funds
    DECLARE @AvailableBalance DECIMAL(15,2);
    SELECT @AvailableBalance = AvailableBalance
    FROM Accounts WHERE AccountID = @FromAccountID;

    IF @AvailableBalance < @Amount
    BEGIN
        RAISERROR('Insufficient funds', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- Generate transaction numbers
    DECLARE @TransactionNumber NVARCHAR(50) = 'TXN-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                                            RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) +
                                            RIGHT('00' + CAST(DAY(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                                            RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    -- Insert withdrawal transaction
    INSERT INTO Transactions (
        TransactionNumber, AccountID, TransactionType, Amount,
        Description, RelatedAccountID, Status
    )
    VALUES (
        @TransactionNumber + '-W', @FromAccountID, 'Transfer',
        @Amount, @Description, @ToAccountID, 'Completed'
    );

    -- Insert deposit transaction
    INSERT INTO Transactions (
        TransactionNumber, AccountID, TransactionType, Amount,
        Description, RelatedAccountID, Status
    )
    VALUES (
        @TransactionNumber + '-D', @ToAccountID, 'Transfer',
        @Amount, @Description, @FromAccountID, 'Completed'
    );

    -- Update transaction references
    UPDATE t1
    SET t1.RelatedTransactionID = t2.TransactionID
    FROM Transactions t1
    INNER JOIN Transactions t2 ON t1.RelatedAccountID = t2.AccountID
    WHERE t1.TransactionNumber = @TransactionNumber + '-W'
    AND t2.TransactionNumber = @TransactionNumber + '-D';

    UPDATE t2
    SET t2.RelatedTransactionID = t1.TransactionID
    FROM Transactions t2
    INNER JOIN Transactions t1 ON t2.RelatedAccountID = t1.AccountID
    WHERE t2.TransactionNumber = @TransactionNumber + '-D'
    AND t1.TransactionNumber = @TransactionNumber + '-W';

    COMMIT TRANSACTION;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample customer
INSERT INTO Customers (CustomerNumber, CustomerType, FirstName, LastName, Email, KYCStatus) VALUES
('CUST-000001', 'Individual', 'John', 'Doe', 'john.doe@email.com', 'Approved');

-- Insert sample account
INSERT INTO Accounts (AccountNumber, CustomerID, AccountType, CurrentBalance) VALUES
('CHK-1000001', 1, 'Checking', 5000.00);

-- Insert sample transaction
INSERT INTO Transactions (TransactionNumber, AccountID, TransactionType, Amount, Description) VALUES
('TXN-20231201-00001', 1, 'Deposit', 5000.00, 'Initial deposit');

PRINT 'Financial Services database schema created successfully!';
GO
