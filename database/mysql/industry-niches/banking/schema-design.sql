-- Banking Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE BankingDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE BankingDB;
GO

-- Configure database for banking compliance
ALTER DATABASE BankingDB
SET
    RECOVERY FULL,
    PAGE_VERIFY CHECKSUM,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON,
    ENCRYPTION ON, -- Enable TDE for banking data protection
    QUERY_STORE = ON; -- Enable query performance monitoring
GO

-- Create encryption certificate for sensitive banking data
CREATE CERTIFICATE BankingDataEncryption
WITH SUBJECT = 'Banking Data Encryption Certificate';
GO

-- =============================================
-- CUSTOMER & RELATIONSHIP MANAGEMENT
-- =============================================

-- Customer master table with banking compliance
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNumber NVARCHAR(20) UNIQUE NOT NULL,
    CustomerType NVARCHAR(20) NOT NULL, -- Retail, Business, Institutional
    TaxID VARBINARY(128), -- Encrypted SSN/EIN
    LegalName NVARCHAR(200) NOT NULL,
    DBA NVARCHAR(200), -- Doing Business As for businesses
    Email NVARCHAR(255),
    Phone NVARCHAR(20),
    DateOfBirth DATE,
    Citizenship NVARCHAR(100),
    ResidencyStatus NVARCHAR(50), -- Citizen, Permanent Resident, Non-Resident
    IsActive BIT DEFAULT 1,
    KYCStatus NVARCHAR(20) DEFAULT 'Pending',
    KYCLastVerified DATETIME2,
    RiskRating NVARCHAR(10), -- Low, Medium, High
    CreditScore INT,
    AnnualIncome DECIMAL(15,2),
    NetWorth DECIMAL(15,2),
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_Customers_CustomerType CHECK (CustomerType IN ('Retail', 'Business', 'Institutional')),
    CONSTRAINT CK_Customers_KYCStatus CHECK (KYCStatus IN ('Pending', 'Approved', 'Rejected', 'Expired')),

    -- Indexes
    INDEX IX_Customers_CustomerNumber (CustomerNumber),
    INDEX IX_Customers_Type (CustomerType),
    INDEX IX_Customers_KYCStatus (KYCStatus),
    INDEX IX_Customers_IsActive (IsActive),
    INDEX IX_Customers_RiskRating (RiskRating)
);

-- Customer relationships and householding
CREATE TABLE CustomerRelationships (
    RelationshipID INT IDENTITY(1,1) PRIMARY KEY,
    PrimaryCustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    RelatedCustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    RelationshipType NVARCHAR(50) NOT NULL, -- Spouse, Business Partner, Subsidiary
    OwnershipPercentage DECIMAL(5,2),
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_CustomerRelationships_Percentage CHECK (OwnershipPercentage BETWEEN 0 AND 100),
    CONSTRAINT UQ_CustomerRelationships_Unique UNIQUE (PrimaryCustomerID, RelatedCustomerID, RelationshipType),

    -- Indexes
    INDEX IX_CustomerRelationships_Primary (PrimaryCustomerID),
    INDEX IX_CustomerRelationships_Related (RelatedCustomerID),
    INDEX IX_CustomerRelationships_Type (RelationshipType)
);

-- =============================================
-- ACCOUNT MANAGEMENT
-- =============================================

-- Account master table
CREATE TABLE Accounts (
    AccountID INT IDENTITY(1,1) PRIMARY KEY,
    AccountNumber NVARCHAR(20) UNIQUE NOT NULL,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    ProductID INT NOT NULL, -- Reference to product catalog
    AccountType NVARCHAR(50) NOT NULL,
    AccountSubType NVARCHAR(50),
    Currency NVARCHAR(3) DEFAULT 'USD',
    Status NVARCHAR(20) DEFAULT 'Active',
    OpenedDate DATETIME2 DEFAULT GETDATE(),
    ClosedDate DATETIME2,
    InterestRate DECIMAL(5,4) DEFAULT 0,
    MinimumBalance DECIMAL(15,2) DEFAULT 0,
    OverdraftLimit DECIMAL(15,2) DEFAULT 0,
    CurrentBalance DECIMAL(15,2) DEFAULT 0,
    AvailableBalance AS (CurrentBalance + OverdraftLimit),
    LedgerBalance DECIMAL(15,2) DEFAULT 0,
    AccruedInterest DECIMAL(15,2) DEFAULT 0,

    -- Account features
    ATMCardIssued BIT DEFAULT 0,
    OnlineBankingEnabled BIT DEFAULT 1,
    MobileBankingEnabled BIT DEFAULT 1,
    CheckWritingEnabled BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Accounts_Status CHECK (Status IN ('Active', 'Inactive', 'Closed', 'Frozen', 'Dormant')),
    CONSTRAINT CK_Accounts_Balance CHECK (CurrentBalance >= -OverdraftLimit),

    -- Indexes
    INDEX IX_Accounts_AccountNumber (AccountNumber),
    INDEX IX_Accounts_Customer (CustomerID),
    INDEX IX_Accounts_Product (ProductID),
    INDEX IX_Accounts_Type (AccountType),
    INDEX IX_Accounts_Status (Status),
    INDEX IX_Accounts_Currency (Currency)
);

-- Account signers and authorizations
CREATE TABLE AccountSigners (
    SignerID INT IDENTITY(1,1) PRIMARY KEY,
    AccountID INT NOT NULL REFERENCES Accounts(AccountID) ON DELETE CASCADE,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    SignerType NVARCHAR(20) DEFAULT 'Owner', -- Owner, Authorized Signer, Power of Attorney
    SignerRole NVARCHAR(50), -- Primary, Secondary, etc.
    CanDeposit BIT DEFAULT 1,
    CanWithdraw BIT DEFAULT 1,
    CanTransfer BIT DEFAULT 1,
    TransactionLimit DECIMAL(15,2),
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT UQ_AccountSigners_AccountCustomer UNIQUE (AccountID, CustomerID),

    -- Indexes
    INDEX IX_AccountSigners_Account (AccountID),
    INDEX IX_AccountSigners_Customer (CustomerID),
    INDEX IX_AccountSigners_Type (SignerType)
);

-- =============================================
-- TRANSACTION PROCESSING
-- =============================================

-- Transaction master table
CREATE TABLE Transactions (
    TransactionID INT IDENTITY(1,1) PRIMARY KEY,
    TransactionNumber NVARCHAR(50) UNIQUE NOT NULL,
    AccountID INT NOT NULL REFERENCES Accounts(AccountID),
    TransactionType NVARCHAR(50) NOT NULL,
    Amount DECIMAL(15,2) NOT NULL,
    Currency NVARCHAR(3) DEFAULT 'USD',
    ExchangeRate DECIMAL(10,6) DEFAULT 1.0,
    TransactionDate DATETIME2 DEFAULT GETDATE(),
    ValueDate DATETIME2 DEFAULT GETDATE(),
    PostingDate DATETIME2 DEFAULT GETDATE(),
    Description NVARCHAR(500),
    ReferenceNumber NVARCHAR(100),
    Channel NVARCHAR(50), -- Branch, ATM, Online, Mobile, API, Wire
    Location NVARCHAR(255),
    BranchID INT,
    TellerID INT,
    Status NVARCHAR(20) DEFAULT 'Posted',

    -- Related accounts and transactions
    RelatedAccountID INT REFERENCES Accounts(AccountID),
    RelatedTransactionID INT REFERENCES Transactions(TransactionID),
    BatchID INT, -- For bulk transactions

    -- Audit and compliance
    CreatedBy NVARCHAR(100),
    ApprovedBy NVARCHAR(100),
    ApprovedDate DATETIME2,
    ReversalTransactionID INT REFERENCES Transactions(TransactionID),

    -- Constraints
    CONSTRAINT CK_Transactions_Status CHECK (Status IN ('Pending', 'Posted', 'Reversed', 'Failed')),
    CONSTRAINT CK_Transactions_Amount CHECK (Amount != 0),

    -- Indexes
    INDEX IX_Transactions_Account (AccountID),
    INDEX IX_Transactions_Type (TransactionType),
    INDEX IX_Transactions_Date (TransactionDate),
    INDEX IX_Transactions_ValueDate (ValueDate),
    INDEX IX_Transactions_Status (Status),
    INDEX IX_Transactions_Reference (ReferenceNumber),
    INDEX IX_Transactions_Channel (Channel)
);

-- General ledger entries
CREATE TABLE LedgerEntries (
    EntryID INT IDENTITY(1,1) PRIMARY KEY,
    TransactionID INT NOT NULL REFERENCES Transactions(TransactionID),
    AccountID INT NOT NULL REFERENCES Accounts(AccountID),
    GLAccount NVARCHAR(50) NOT NULL, -- General ledger account number
    DebitAmount DECIMAL(15,2) DEFAULT 0,
    CreditAmount DECIMAL(15,2) DEFAULT 0,
    EntryDescription NVARCHAR(500),
    EntryDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_LedgerEntries_Amounts CHECK (
        (DebitAmount > 0 AND CreditAmount = 0) OR
        (CreditAmount > 0 AND DebitAmount = 0)
    ),

    -- Indexes
    INDEX IX_LedgerEntries_Transaction (TransactionID),
    INDEX IX_LedgerEntries_Account (AccountID),
    INDEX IX_LedgerEntries_GLAccount (GLAccount),
    INDEX IX_LedgerEntries_Date (EntryDate)
);

-- =============================================
-- LOAN MANAGEMENT
-- =============================================

-- Loan products
CREATE TABLE LoanProducts (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductCode NVARCHAR(20) UNIQUE NOT NULL,
    ProductName NVARCHAR(200) NOT NULL,
    ProductType NVARCHAR(50) NOT NULL, -- Personal, Mortgage, Auto, Business
    Description NVARCHAR(MAX),
    MinAmount DECIMAL(15,2),
    MaxAmount DECIMAL(15,2),
    MinTermMonths INT,
    MaxTermMonths INT,
    InterestRateType NVARCHAR(20), -- Fixed, Variable, Adjustable
    BaseInterestRate DECIMAL(5,4),
    OriginationFee DECIMAL(5,4), -- As percentage
    IsActive BIT DEFAULT 1,

    -- Indexes
    INDEX IX_LoanProducts_Code (ProductCode),
    INDEX IX_LoanProducts_Type (ProductType),
    INDEX IX_LoanProducts_IsActive (IsActive)
);

-- Loan applications
CREATE TABLE LoanApplications (
    ApplicationID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    ProductID INT NOT NULL REFERENCES LoanProducts(ProductID),
    ApplicationNumber NVARCHAR(50) UNIQUE NOT NULL,
    RequestedAmount DECIMAL(15,2) NOT NULL,
    TermMonths INT NOT NULL,
    Purpose NVARCHAR(MAX),
    Status NVARCHAR(20) DEFAULT 'Submitted',
    SubmittedDate DATETIME2 DEFAULT GETDATE(),
    ApprovedDate DATETIME2,
    FundedDate DATETIME2,
    CreditScore INT,
    DebtToIncomeRatio DECIMAL(5,4),
    EmploymentVerification BIT DEFAULT 0,
    PropertyAppraisal DECIMAL(15,2), -- For mortgages
    CoSignerCustomerID INT REFERENCES Customers(CustomerID),

    -- Constraints
    CONSTRAINT CK_LoanApplications_Status CHECK (Status IN ('Submitted', 'Under Review', 'Approved', 'Rejected', 'Withdrawn')),

    -- Indexes
    INDEX IX_LoanApplications_Customer (CustomerID),
    INDEX IX_LoanApplications_Product (ProductID),
    INDEX IX_LoanApplications_Status (Status),
    INDEX IX_LoanApplications_Date (SubmittedDate)
);

-- Loan accounts
CREATE TABLE Loans (
    LoanID INT IDENTITY(1,1) PRIMARY KEY,
    ApplicationID INT NOT NULL REFERENCES LoanApplications(ApplicationID),
    AccountID INT NOT NULL REFERENCES Accounts(AccountID), -- Disbursement account
    LoanNumber NVARCHAR(50) UNIQUE NOT NULL,
    PrincipalAmount DECIMAL(15,2) NOT NULL,
    OutstandingBalance DECIMAL(15,2) NOT NULL,
    TermMonths INT NOT NULL,
    InterestRate DECIMAL(5,4) NOT NULL,
    PaymentFrequency NVARCHAR(20) DEFAULT 'Monthly',
    FirstPaymentDate DATE,
    MaturityDate DATE,
    NextPaymentDate DATE,
    Status NVARCHAR(20) DEFAULT 'Active',

    -- Loan terms
    OriginationFee DECIMAL(15,2),
    PrepaymentPenalty DECIMAL(5,4),
    GracePeriodDays INT DEFAULT 15,

    -- Collateral information
    CollateralType NVARCHAR(50),
    CollateralValue DECIMAL(15,2),
    CollateralDescription NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_Loans_Status CHECK (Status IN ('Active', 'Paid Off', 'Defaulted', 'Foreclosed', 'Charged Off')),
    CONSTRAINT CK_Loans_Balance CHECK (OutstandingBalance >= 0),

    -- Indexes
    INDEX IX_Loans_Application (ApplicationID),
    INDEX IX_Loans_Account (AccountID),
    INDEX IX_Loans_Status (Status),
    INDEX IX_Loans_Maturity (MaturityDate),
    INDEX IX_Loans_NextPayment (NextPaymentDate)
);

-- Loan payment schedule
CREATE TABLE LoanPaymentSchedule (
    ScheduleID INT IDENTITY(1,1) PRIMARY KEY,
    LoanID INT NOT NULL REFERENCES Loans(LoanID) ON DELETE CASCADE,
    PaymentNumber INT NOT NULL,
    DueDate DATE NOT NULL,
    PrincipalAmount DECIMAL(15,2) NOT NULL,
    InterestAmount DECIMAL(15,2) NOT NULL,
    TotalPayment DECIMAL(15,2) NOT NULL,
    Status NVARCHAR(20) DEFAULT 'Pending',

    -- Constraints
    CONSTRAINT UQ_LoanPaymentSchedule_LoanPayment UNIQUE (LoanID, PaymentNumber),
    CONSTRAINT CK_LoanPaymentSchedule_Status CHECK (Status IN ('Pending', 'Paid', 'Late', 'Missed', 'Waived')),

    -- Indexes
    INDEX IX_LoanPaymentSchedule_Loan (LoanID),
    INDEX IX_LoanPaymentSchedule_DueDate (DueDate),
    INDEX IX_LoanPaymentSchedule_Status (Status)
);

-- Loan payments
CREATE TABLE LoanPayments (
    PaymentID INT IDENTITY(1,1) PRIMARY KEY,
    LoanID INT NOT NULL REFERENCES Loans(LoanID),
    ScheduleID INT REFERENCES LoanPaymentSchedule(ScheduleID),
    PaymentAmount DECIMAL(15,2) NOT NULL,
    PrincipalPaid DECIMAL(15,2) DEFAULT 0,
    InterestPaid DECIMAL(15,2) DEFAULT 0,
    LateFees DECIMAL(15,2) DEFAULT 0,
    PaymentDate DATETIME2 DEFAULT GETDATE(),
    PaymentMethod NVARCHAR(50),
    TransactionID INT REFERENCES Transactions(TransactionID),
    ProcessedBy NVARCHAR(100),

    -- Indexes
    INDEX IX_LoanPayments_Loan (LoanID),
    INDEX IX_LoanPayments_Schedule (ScheduleID),
    INDEX IX_LoanPayments_Date (PaymentDate)
);

-- =============================================
-- RISK MANAGEMENT & COMPLIANCE
-- =============================================

-- Credit assessments
CREATE TABLE CreditAssessments (
    AssessmentID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    AssessmentType NVARCHAR(50) NOT NULL, -- Application, Annual Review, AdHoc
    AssessmentDate DATETIME2 DEFAULT GETDATE(),
    CreditScore INT,
    RiskGrade NVARCHAR(5), -- AAA, AA, A, BBB, BB, B, CCC
    PD DECIMAL(8,6), -- Probability of Default
    LGD DECIMAL(5,4), -- Loss Given Default
    EAD DECIMAL(15,2), -- Exposure at Default
    RiskRating NVARCHAR(20),
    RecommendedAction NVARCHAR(MAX),
    AssessedBy NVARCHAR(100),

    -- Indexes
    INDEX IX_CreditAssessments_Customer (CustomerID),
    INDEX IX_CreditAssessments_Type (AssessmentType),
    INDEX IX_CreditAssessments_Date (AssessmentDate),
    INDEX IX_CreditAssessments_RiskGrade (RiskGrade)
);

-- Sanctions screening
CREATE TABLE SanctionsScreening (
    ScreeningID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT REFERENCES Customers(CustomerID),
    TransactionID INT REFERENCES Transactions(TransactionID),
    ScreeningType NVARCHAR(50), -- Customer, Transaction, PEP
    ScreeningDate DATETIME2 DEFAULT GETDATE(),
    MatchFound BIT DEFAULT 0,
    MatchScore DECIMAL(5,2),
    MatchedEntity NVARCHAR(500),
    RiskLevel NVARCHAR(20),
    Status NVARCHAR(20) DEFAULT 'Cleared',
    ReviewedBy NVARCHAR(100),
    ReviewDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_SanctionsScreening_Status CHECK (Status IN ('Cleared', 'Flagged', 'Escalated', 'Blocked')),

    -- Indexes
    INDEX IX_SanctionsScreening_Customer (CustomerID),
    INDEX IX_SanctionsScreening_Transaction (TransactionID),
    INDEX IX_SanctionsScreening_Type (ScreeningType),
    INDEX IX_SanctionsScreening_Status (Status),
    INDEX IX_SanctionsScreening_Date (ScreeningDate)
);

-- Suspicious activity reports
CREATE TABLE SuspiciousActivityReports (
    SARID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT REFERENCES Customers(CustomerID),
    AccountID INT REFERENCES Accounts(AccountID),
    TransactionID INT REFERENCES Transactions(TransactionID),
    ReportDate DATETIME2 DEFAULT GETDATE(),
    FiledWithFinCEN BIT DEFAULT 0,
    FiledDate DATETIME2,
    CaseNumber NVARCHAR(50),
    ActivityDescription NVARCHAR(MAX),
    AmountInvolved DECIMAL(15,2),
    RiskAssessment NVARCHAR(MAX),
    PreparedBy NVARCHAR(100),

    -- Indexes
    INDEX IX_SuspiciousActivityReports_Customer (CustomerID),
    INDEX IX_SuspiciousActivityReports_Date (ReportDate),
    INDEX IX_SuspiciousActivityReports_Filed (FiledWithFinCEN)
);

-- =============================================
-- ANALYTICS & REPORTING
-- =============================================

-- Call report data for regulatory reporting
CREATE TABLE CallReportData (
    ReportID INT IDENTITY(1,1) PRIMARY KEY,
    ReportDate DATE NOT NULL,
    InstitutionID NVARCHAR(20),
    ScheduleCode NVARCHAR(10), -- RI, RC, etc.
    LineItem NVARCHAR(20),
    Amount DECIMAL(18,2),
    Description NVARCHAR(500),
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT UQ_CallReportData_Unique UNIQUE (ReportDate, InstitutionID, ScheduleCode, LineItem),

    -- Indexes
    INDEX IX_CallReportData_ReportDate (ReportDate),
    INDEX IX_CallReportData_Institution (InstitutionID),
    INDEX IX_CallReportData_Schedule (ScheduleCode)
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
    c.LegalName,
    c.CustomerType,
    c.KYCStatus,
    c.RiskRating,
    COUNT(a.AccountID) AS TotalAccounts,
    SUM(a.CurrentBalance) AS TotalBalance,
    AVG(a.CurrentBalance) AS AvgAccountBalance,
    MAX(a.OpenedDate) AS FirstAccountDate,
    MAX(t.TransactionDate) AS LastTransactionDate,
    COUNT(DISTINCT l.LoanID) AS ActiveLoans,
    SUM(l.OutstandingBalance) AS TotalLoanBalance
FROM Customers c
LEFT JOIN Accounts a ON c.CustomerID = a.CustomerID AND a.Status = 'Active'
LEFT JOIN Transactions t ON a.AccountID = t.AccountID
LEFT JOIN Loans l ON c.CustomerID = l.CustomerID AND l.Status = 'Active'
WHERE c.IsActive = 1
GROUP BY c.CustomerID, c.CustomerNumber, c.LegalName, c.CustomerType, c.KYCStatus, c.RiskRating;
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
    SUM(CASE WHEN t.TransactionType IN ('Fee', 'Interest') THEN t.Amount ELSE 0 END) AS TotalFees,
    MAX(t.TransactionDate) AS LastTransactionDate,
    DATEDIFF(DAY, MAX(t.TransactionDate), GETDATE()) AS DaysSinceLastTransaction
FROM Accounts a
LEFT JOIN Transactions t ON a.AccountID = t.AccountID
WHERE a.Status = 'Active'
GROUP BY a.AccountID, a.AccountNumber, a.AccountType, a.CurrentBalance, a.AvailableBalance;
GO

-- Loan portfolio summary view
CREATE VIEW vw_LoanPortfolioSummary
AS
SELECT
    lp.ProductType,
    COUNT(l.LoanID) AS TotalLoans,
    SUM(l.PrincipalAmount) AS TotalPrincipal,
    SUM(l.OutstandingBalance) AS TotalOutstanding,
    AVG(l.InterestRate) AS AvgInterestRate,
    SUM(CASE WHEN l.Status = 'Active' THEN 1 ELSE 0 END) AS ActiveLoans,
    SUM(CASE WHEN l.Status = 'Defaulted' THEN 1 ELSE 0 END) AS DefaultedLoans,
    SUM(CASE WHEN lps.Status = 'Late' AND lps.DueDate < GETDATE() THEN 1 ELSE 0 END) AS PastDuePayments
FROM LoanProducts lp
LEFT JOIN Loans l ON lp.ProductID = l.ProductID
LEFT JOIN LoanPaymentSchedule lps ON l.LoanID = lps.LoanID
GROUP BY lp.ProductID, lp.ProductType;
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

    -- Update account balance for completed transactions
    UPDATE a
    SET a.CurrentBalance = a.CurrentBalance +
        CASE
            WHEN i.TransactionType IN ('Deposit', 'Transfer') THEN i.Amount
            WHEN i.TransactionType IN ('Withdrawal', 'Fee') THEN -i.Amount
            ELSE 0
        END,
        a.LedgerBalance = a.LedgerBalance +
        CASE
            WHEN i.TransactionType IN ('Deposit', 'Transfer') THEN i.Amount
            WHEN i.TransactionType IN ('Withdrawal', 'Fee') THEN -i.Amount
            ELSE 0
        END
    FROM Accounts a
    INNER JOIN inserted i ON a.AccountID = i.AccountID
    WHERE i.Status = 'Posted';
END;
GO

-- Loan balance update trigger
CREATE TRIGGER TR_LoanPayments_UpdateBalance
ON LoanPayments
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Update loan outstanding balance
    UPDATE l
    SET l.OutstandingBalance = l.OutstandingBalance - i.PrincipalPaid
    FROM Loans l
    INNER JOIN inserted i ON l.LoanID = i.LoanID
    WHERE l.Status = 'Active';

    -- Mark loan as paid off if balance is zero
    UPDATE l
    SET l.Status = 'Paid Off',
        l.NextPaymentDate = NULL
    FROM Loans l
    WHERE l.OutstandingBalance <= 0 AND l.Status = 'Active';
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Process account transfer
CREATE PROCEDURE sp_ProcessTransfer
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

    -- Generate transaction number
    DECLARE @TransactionNumber NVARCHAR(50) = 'TXN-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                                            RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) +
                                            RIGHT('00' + CAST(DAY(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                                            RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    -- Insert withdrawal transaction
    INSERT INTO Transactions (
        TransactionNumber, AccountID, TransactionType, Amount,
        Description, RelatedAccountID, Status, TransferType
    )
    VALUES (
        @TransactionNumber + '-W', @FromAccountID, 'Transfer',
        @Amount, @Description, @ToAccountID, 'Posted', @TransferType
    );

    -- Insert deposit transaction
    INSERT INTO Transactions (
        TransactionNumber, AccountID, TransactionType, Amount,
        Description, RelatedAccountID, Status, TransferType
    )
    VALUES (
        @TransactionNumber + '-D', @ToAccountID, 'Transfer',
        @Amount, @Description, @FromAccountID, 'Posted', @TransferType
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
INSERT INTO Customers (CustomerNumber, CustomerType, LegalName, Email, KYCStatus, RiskRating) VALUES
('CUST-000001', 'Retail', 'John Smith', 'john.smith@email.com', 'Approved', 'Low');

-- Insert sample account
INSERT INTO Accounts (AccountNumber, CustomerID, ProductID, AccountType, CurrentBalance) VALUES
('CHK-1000001', 1, 1, 'Checking', 5000.00);

-- Insert sample loan product
INSERT INTO LoanProducts (ProductCode, ProductName, ProductType, MinAmount, MaxAmount, BaseInterestRate) VALUES
('PL-001', 'Personal Loan', 'Personal', 1000, 50000, 0.0899);

-- Insert sample transaction
INSERT INTO Transactions (TransactionNumber, AccountID, TransactionType, Amount, Description) VALUES
('TXN-20231201-00001', 1, 'Deposit', 5000.00, 'Initial deposit');

PRINT 'Banking database schema created successfully!';
GO
