# Banking Platform Database Design

## Overview

This comprehensive database schema supports modern banking platforms including retail banking, commercial banking, loan processing, wealth management, and regulatory compliance. The design handles complex financial transactions, risk assessment, multi-channel banking, and enterprise-level security with full regulatory compliance.

## Key Features

### 🏦 Core Banking Operations
- **Multi-product banking** with checking, savings, CDs, and business accounts
- **Real-time transaction processing** with instant balance updates and fraud detection
- **Multi-currency support** with automatic conversion and international banking
- **Branch and digital channel integration** for omnichannel banking experience

### 💰 Loan & Credit Management
- **Comprehensive loan origination** with automated underwriting and approval workflows
- **Credit risk assessment** with scoring models and portfolio management
- **Loan servicing and administration** with payment processing and delinquency management
- **Securitization and syndication** support for complex financial products

### 📊 Regulatory Compliance & Risk
- **Anti-Money Laundering (AML)** monitoring with transaction pattern analysis
- **Know Your Customer (KYC)** processes with enhanced due diligence
- **Basel III compliance** with capital adequacy and liquidity reporting
- **Regulatory reporting** automation for FDIC, OCC, and Federal Reserve

## Database Schema Highlights

### Core Tables

#### Customer & Relationship Management
```sql
-- Customer master table with enhanced banking compliance
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
```

#### Account Structure & Products
```sql
-- Account master table with product relationships
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
```

#### Transaction Processing & Ledger
```sql
-- Transaction master table with enhanced banking features
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
```

### Loan & Credit Management

#### Loan Products & Origination
```sql
-- Loan products catalog
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
```

#### Payment Processing & Servicing
```sql
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
```

### Risk Management & Compliance

#### Credit Risk Assessment
```sql
-- Credit scoring and risk assessment
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

-- Watch lists and sanctions screening
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
```

#### Regulatory Reporting
```sql
-- Call report data (for regulatory reporting)
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
```

## Integration Points

### External Systems
- **Core Banking Systems**: Integration with existing banking platforms
- **Credit Bureaus**: Equifax, Experian, TransUnion for credit scoring
- **Payment Networks**: Fedwire, SWIFT, ACH for interbank transfers
- **Regulatory Systems**: Federal Reserve, FDIC, OCC for reporting
- **Financial Exchanges**: Bloomberg, Reuters for market data
- **Credit Card Networks**: Visa, Mastercard for card processing

### API Endpoints
- **Account Management APIs**: Account creation, balance inquiries, statements
- **Transaction APIs**: Money transfers, bill payments, wire transfers
- **Loan APIs**: Application processing, loan servicing, payment processing
- **Risk Management APIs**: Fraud detection, compliance monitoring, alerts
- **Reporting APIs**: Account statements, regulatory reports, analytics

## Monitoring & Analytics

### Key Performance Indicators
- **Financial Performance**: Net interest income, non-interest income, operating expenses
- **Asset Quality**: Non-performing loans, charge-offs, allowance for loan losses
- **Liquidity**: Cash reserves, loan-to-deposit ratio, capital adequacy
- **Customer Metrics**: Customer acquisition cost, retention rates, product penetration
- **Operational Efficiency**: Transaction processing time, error rates, customer satisfaction

### Real-Time Dashboards
```sql
-- Banking operations dashboard
CREATE VIEW BankingOperationsDashboard AS
SELECT
    -- Financial metrics (current month)
    (SELECT SUM(t.Amount) FROM Transactions t
     WHERE t.TransactionType = 'Deposit'
     AND MONTH(t.TransactionDate) = MONTH(GETDATE())
     AND YEAR(t.TransactionDate) = YEAR(GETDATE())) AS DepositsThisMonth,

    (SELECT SUM(t.Amount) FROM Transactions t
     WHERE t.TransactionType = 'Withdrawal'
     AND MONTH(t.TransactionDate) = MONTH(GETDATE())
     AND YEAR(t.TransactionDate) = YEAR(GETDATE())) AS WithdrawalsThisMonth,

    (SELECT COUNT(DISTINCT a.CustomerID) FROM Accounts a WHERE a.Status = 'Active') AS ActiveCustomers,

    (SELECT AVG(a.CurrentBalance) FROM Accounts a WHERE a.Status = 'Active') AS AvgAccountBalance,

    -- Loan portfolio metrics
    (SELECT SUM(l.OutstandingBalance) FROM Loans l WHERE l.Status = 'Active') AS TotalLoanPortfolio,

    (SELECT COUNT(*) FROM Loans l WHERE l.Status = 'Active') AS ActiveLoans,

    (SELECT SUM(lp.TotalPayment) FROM LoanPaymentSchedule lp
     INNER JOIN Loans l ON lp.LoanID = l.LoanID
     WHERE lp.Status = 'Late' AND lp.DueDate < GETDATE()
     AND l.Status = 'Active') AS PastDuePayments,

    -- Risk and compliance metrics
    (SELECT COUNT(*) FROM SuspiciousActivityReports sar
     WHERE MONTH(sar.ReportDate) = MONTH(GETDATE())
     AND YEAR(sar.ReportDate) = YEAR(GETDATE())) AS SARsFiledThisMonth,

    (SELECT COUNT(*) FROM SanctionsScreening ss
     WHERE ss.Status = 'Flagged'
     AND ss.ScreeningDate >= DATEADD(DAY, -30, GETDATE())) AS RecentSanctionsFlags,

    -- Operational metrics
    (SELECT COUNT(*) FROM Transactions t
     WHERE t.Status = 'Posted'
     AND CAST(t.TransactionDate AS DATE) = CAST(GETDATE() AS DATE)) AS TransactionsToday,

    (SELECT AVG(DATEDIFF(MINUTE, t.CreatedDate, t.PostingDate))
     FROM Transactions t
     WHERE t.Status = 'Posted'
     AND t.CreatedDate >= DATEADD(DAY, -7, GETDATE())) AS AvgProcessingTimeMinutes,

    -- Customer service metrics
    (SELECT COUNT(*) FROM Accounts a WHERE a.Status = 'Frozen') AS FrozenAccounts,

    (SELECT COUNT(*) FROM Customers c WHERE c.KYCStatus = 'Pending') AS PendingKYCCustomers

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This banking database schema provides a comprehensive foundation for modern financial institutions, incorporating regulatory compliance, risk management, real-time processing, and enterprise-level security while maintaining high performance and data integrity.
