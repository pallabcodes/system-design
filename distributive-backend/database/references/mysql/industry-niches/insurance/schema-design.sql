-- Insurance Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE InsuranceDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE InsuranceDB;
GO

-- Configure database for insurance compliance
ALTER DATABASE InsuranceDB
SET
    RECOVERY SIMPLE,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON,
    ENCRYPTION ON; -- Enable TDE for sensitive insurance data
GO

-- =============================================
-- POLICY MANAGEMENT
-- =============================================

-- Insurance policies
CREATE TABLE Policies (
    PolicyID INT IDENTITY(1,1) PRIMARY KEY,
    PolicyNumber NVARCHAR(50) UNIQUE NOT NULL,
    PolicyHolderID INT NOT NULL REFERENCES Customers(CustomerID),
    ProductID INT NOT NULL, -- Reference to insurance product catalog
    PolicyType NVARCHAR(50) NOT NULL, -- Auto, Home, Life, Health, Commercial
    CoverageType NVARCHAR(50), -- Liability, Property, Casualty, etc.
    Status NVARCHAR(20) DEFAULT 'Active',

    -- Policy details
    EffectiveDate DATE NOT NULL,
    ExpirationDate DATE NOT NULL,
    RenewalDate DATE,
    PremiumAmount DECIMAL(12,2) NOT NULL,
    PremiumFrequency NVARCHAR(20) DEFAULT 'Annual', -- Annual, SemiAnnual, Quarterly, Monthly

    -- Underwriting information
    UnderwriterID INT,
    RiskScore INT,
    UnderwritingClass NVARCHAR(20),

    -- Billing information
    BillingMethod NVARCHAR(20) DEFAULT 'DirectBill', -- DirectBill, AgencyBill, ListBill
    PaymentPlan NVARCHAR(20) DEFAULT 'Annual', -- Annual, SemiAnnual, Quarterly, Monthly
    NextPaymentDate DATE,

    -- Audit fields
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy INT,
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_Policies_Status CHECK (Status IN ('Quote', 'Active', 'Expired', 'Cancelled', 'Lapsed')),
    CONSTRAINT CK_Policies_Type CHECK (PolicyType IN ('Auto', 'Home', 'Life', 'Health', 'Commercial', 'WorkersComp')),
    CONSTRAINT CK_Policies_Dates CHECK (ExpirationDate > EffectiveDate),
    CONSTRAINT CK_Policies_Premium CHECK (PremiumAmount > 0),

    -- Indexes
    INDEX IX_Policies_Number (PolicyNumber),
    INDEX IX_Policies_Holder (PolicyHolderID),
    INDEX IX_Policies_Type (PolicyType),
    INDEX IX_Policies_Status (Status),
    INDEX IX_Policies_EffectiveDate (EffectiveDate),
    INDEX IX_Policies_ExpirationDate (ExpirationDate),
    INDEX IX_Policies_RenewalDate (RenewalDate)
);

-- Policy coverages
CREATE TABLE PolicyCoverages (
    CoverageID INT IDENTITY(1,1) PRIMARY KEY,
    PolicyID INT NOT NULL REFERENCES Policies(PolicyID) ON DELETE CASCADE,
    CoverageCode NVARCHAR(20) NOT NULL,
    CoverageName NVARCHAR(100) NOT NULL,
    CoverageType NVARCHAR(50), -- Primary, Additional, Rider
    CoverageLimit DECIMAL(15,2),
    Deductible DECIMAL(12,2) DEFAULT 0,
    Premium DECIMAL(10,2),
    Description NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_PolicyCoverages_Type CHECK (CoverageType IN ('Primary', 'Additional', 'Rider', 'Endorsement')),
    CONSTRAINT CK_PolicyCoverages_Limit CHECK (CoverageLimit >= 0),

    -- Indexes
    INDEX IX_PolicyCoverages_Policy (PolicyID),
    INDEX IX_PolicyCoverages_Code (CoverageCode),
    INDEX IX_PolicyCoverages_Type (CoverageType)
);

-- Policy insured objects
CREATE TABLE PolicyInsureds (
    InsuredID INT IDENTITY(1,1) PRIMARY KEY,
    PolicyID INT NOT NULL REFERENCES Policies(PolicyID) ON DELETE CASCADE,
    InsuredType NVARCHAR(50) NOT NULL, -- Vehicle, Property, Person, Business
    InsuredName NVARCHAR(200),
    Relationship NVARCHAR(50), -- Named Insured, Spouse, Child, etc.

    -- Details stored as JSON
    VehicleDetails NVARCHAR(MAX),
    PropertyDetails NVARCHAR(MAX),
    PersonDetails NVARCHAR(MAX),

    -- Indexes
    INDEX IX_PolicyInsureds_Policy (PolicyID),
    INDEX IX_PolicyInsureds_Type (InsuredType)
);

-- =============================================
-- CLAIMS MANAGEMENT
-- =============================================

-- Insurance claims
CREATE TABLE Claims (
    ClaimID INT IDENTITY(1,1) PRIMARY KEY,
    ClaimNumber NVARCHAR(50) UNIQUE NOT NULL,
    PolicyID INT NOT NULL REFERENCES Policies(PolicyID),
    InsuredID INT REFERENCES PolicyInsureds(InsuredID),
    ClaimantID INT REFERENCES Customers(CustomerID),

    -- Claim details
    LossDate DATETIME2 NOT NULL,
    ReportedDate DATETIME2 DEFAULT GETDATE(),
    IncidentDescription NVARCHAR(MAX),
    ClaimAmount DECIMAL(12,2),
    Status NVARCHAR(20) DEFAULT 'Open',

    -- Processing information
    AdjusterID INT,
    AssignedDate DATETIME2,
    InvestigationNotes NVARCHAR(MAX),
    SettlementAmount DECIMAL(12,2),
    SettlementDate DATETIME2,

    -- Fraud detection
    FraudScore DECIMAL(5,2) DEFAULT 0,
    IsSuspicious BIT DEFAULT 0,
    InvestigationRequired BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Claims_Status CHECK (Status IN ('Open', 'Investigating', 'Approved', 'Denied', 'Closed', 'Reopened')),
    CONSTRAINT CK_Claims_Amount CHECK (ClaimAmount >= 0),
    CONSTRAINT CK_Claims_Settlement CHECK (SettlementAmount <= ClaimAmount OR SettlementAmount IS NULL),
    CONSTRAINT CK_Claims_FraudScore CHECK (FraudScore BETWEEN 0 AND 100),

    -- Indexes
    INDEX IX_Claims_Number (ClaimNumber),
    INDEX IX_Claims_Policy (PolicyID),
    INDEX IX_Claims_Insured (InsuredID),
    INDEX IX_Claims_Claimant (ClaimantID),
    INDEX IX_Claims_Status (Status),
    INDEX IX_Claims_LossDate (LossDate),
    INDEX IX_Claims_ReportedDate (ReportedDate),
    INDEX IX_Claims_FraudScore (FraudScore)
);

-- Claim documents
CREATE TABLE ClaimDocuments (
    DocumentID INT IDENTITY(1,1) PRIMARY KEY,
    ClaimID INT NOT NULL REFERENCES Claims(ClaimID) ON DELETE CASCADE,
    DocumentType NVARCHAR(50) NOT NULL, -- Police Report, Photos, Medical Records, Estimates
    DocumentName NVARCHAR(200) NOT NULL,
    FilePath NVARCHAR(500),
    FileSize BIGINT,
    UploadDate DATETIME2 DEFAULT GETDATE(),
    UploadedBy INT,
    IsVerified BIT DEFAULT 0,
    VerificationNotes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_ClaimDocuments_Type CHECK (DocumentType IN ('PoliceReport', 'Photos', 'MedicalRecords', 'Estimates', 'Correspondence', 'Other')),

    -- Indexes
    INDEX IX_ClaimDocuments_Claim (ClaimID),
    INDEX IX_ClaimDocuments_Type (DocumentType),
    INDEX IX_ClaimDocuments_Verified (IsVerified)
);

-- Claim payments
CREATE TABLE ClaimPayments (
    PaymentID INT IDENTITY(1,1) PRIMARY KEY,
    ClaimID INT NOT NULL REFERENCES Claims(ClaimID),
    PaymentType NVARCHAR(20) DEFAULT 'Settlement', -- Settlement, Advance, Supplement
    PaymentAmount DECIMAL(12,2) NOT NULL,
    PaymentDate DATETIME2 DEFAULT GETDATE(),
    PayeeName NVARCHAR(200),
    PaymentMethod NVARCHAR(20), -- Check, EFT, CreditCard
    CheckNumber NVARCHAR(50),
    ReferenceNumber NVARCHAR(100),
    ProcessedBy INT,

    -- Constraints
    CONSTRAINT CK_ClaimPayments_Type CHECK (PaymentType IN ('Settlement', 'Advance', 'Supplement', 'Refund')),
    CONSTRAINT CK_ClaimPayments_Method CHECK (PaymentMethod IN ('Check', 'EFT', 'CreditCard', 'Cash')),

    -- Indexes
    INDEX IX_ClaimPayments_Claim (ClaimID),
    INDEX IX_ClaimPayments_Type (PaymentType),
    INDEX IX_ClaimPayments_Date (PaymentDate)
);

-- =============================================
-- PREMIUM & BILLING MANAGEMENT
-- =============================================

-- Premiums and billing
CREATE TABLE Premiums (
    PremiumID INT IDENTITY(1,1) PRIMARY KEY,
    PolicyID INT NOT NULL REFERENCES Policies(PolicyID),
    BillingPeriod NVARCHAR(20) NOT NULL, -- Annual, SemiAnnual, Quarterly, Monthly
    PeriodStartDate DATE NOT NULL,
    PeriodEndDate DATE NOT NULL,
    BasePremium DECIMAL(12,2) NOT NULL,
    Adjustments DECIMAL(10,2) DEFAULT 0, -- Surcharges, discounts
    Taxes DECIMAL(10,2) DEFAULT 0,
    TotalPremium DECIMAL(12,2) NOT NULL,
    DueDate DATE NOT NULL,
    PaidDate DATE,
    Status NVARCHAR(20) DEFAULT 'Unpaid',

    -- Constraints
    CONSTRAINT CK_Premiums_Status CHECK (Status IN ('Unpaid', 'Paid', 'Overdue', 'Cancelled')),
    CONSTRAINT CK_Premiums_Dates CHECK (PeriodEndDate > PeriodStartDate),
    CONSTRAINT CK_Premiums_Amounts CHECK (TotalPremium > 0),

    -- Indexes
    INDEX IX_Premiums_Policy (PolicyID),
    INDEX IX_Premiums_Period (PeriodStartDate, PeriodEndDate),
    INDEX IX_Premiums_Status (Status),
    INDEX IX_Premiums_DueDate (DueDate)
);

-- Premium payments
CREATE TABLE PremiumPayments (
    PaymentID INT IDENTITY(1,1) PRIMARY KEY,
    PremiumID INT NOT NULL REFERENCES Premiums(PremiumID),
    PaymentAmount DECIMAL(12,2) NOT NULL,
    PaymentDate DATETIME2 DEFAULT GETDATE(),
    PaymentMethod NVARCHAR(20), -- CreditCard, ACH, Check, Cash
    ReferenceNumber NVARCHAR(100),
    ProcessedBy NVARCHAR(100),
    Notes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_PremiumPayments_Method CHECK (PaymentMethod IN ('CreditCard', 'ACH', 'Check', 'Cash', 'Wire')),

    -- Indexes
    INDEX IX_PremiumPayments_Premium (PremiumID),
    INDEX IX_PremiumPayments_Date (PaymentDate),
    INDEX IX_PremiumPayments_Method (PaymentMethod)
);

-- =============================================
-- UNDERWRITING & RISK MANAGEMENT
-- =============================================

-- Underwriting applications
CREATE TABLE UnderwritingApplications (
    ApplicationID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
    ProductID INT NOT NULL,
    ApplicationNumber NVARCHAR(50) UNIQUE NOT NULL,
    SubmissionDate DATETIME2 DEFAULT GETDATE(),
    Status NVARCHAR(20) DEFAULT 'Submitted',

    -- Risk assessment
    RiskScore INT,
    UnderwritingClass NVARCHAR(20),
    RecommendedPremium DECIMAL(12,2),
    UnderwriterNotes NVARCHAR(MAX),

    -- Decision
    Decision NVARCHAR(20), -- Approved, Declined, Referred, Pending
    DecisionDate DATETIME2,
    ApprovedBy INT,

    -- Constraints
    CONSTRAINT CK_UnderwritingApplications_Status CHECK (Status IN ('Submitted', 'UnderReview', 'Approved', 'Declined', 'Withdrawn')),
    CONSTRAINT CK_UnderwritingApplications_Decision CHECK (Decision IN ('Approved', 'Declined', 'Referred', 'Pending')),

    -- Indexes
    INDEX IX_UnderwritingApplications_Customer (CustomerID),
    INDEX IX_UnderwritingApplications_Status (Status),
    INDEX IX_UnderwritingApplications_Decision (Decision),
    INDEX IX_UnderwritingApplications_SubmissionDate (SubmissionDate)
);

-- Loss history
CREATE TABLE LossHistory (
    LossID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT REFERENCES Customers(CustomerID),
    PolicyID INT REFERENCES Policies(PolicyID),
    LossDate DATE NOT NULL,
    LossType NVARCHAR(50) NOT NULL, -- Accident, Theft, Fire, Medical, etc.
    LossAmount DECIMAL(12,2),
    Description NVARCHAR(MAX),
    ReportedTo NVARCHAR(100), -- Police, Fire Dept, etc.
    ReportNumber NVARCHAR(50),
    Status NVARCHAR(20) DEFAULT 'Reported',

    -- Constraints
    CONSTRAINT CK_LossHistory_Status CHECK (Status IN ('Reported', 'Investigating', 'Settled', 'Denied')),

    -- Indexes
    INDEX IX_LossHistory_Customer (CustomerID),
    INDEX IX_LossHistory_Policy (PolicyID),
    INDEX IX_LossHistory_Type (LossType),
    INDEX IX_LossHistory_Date (LossDate),
    INDEX IX_LossHistory_Status (Status)
);

-- =============================================
-- REGULATORY COMPLIANCE
-- =============================================

-- Regulatory filings
CREATE TABLE RegulatoryFilings (
    FilingID INT IDENTITY(1,1) PRIMARY KEY,
    FilingType NVARCHAR(50) NOT NULL, -- Annual Statement, Quarterly Report, etc.
    ReportPeriod NVARCHAR(20), -- 2023Q1, 2023Annual, etc.
    FilingDate DATETIME2 DEFAULT GETDATE(),
    DueDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Draft',

    -- Filing content
    ReportData NVARCHAR(MAX), -- JSON structured data
    FiledWith NVARCHAR(100), -- State Insurance Department, NAIC, etc.
    ConfirmationNumber NVARCHAR(50),
    FilingFee DECIMAL(8,2),

    -- Audit
    PreparedBy NVARCHAR(100),
    ReviewedBy NVARCHAR(100),
    ApprovedBy NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_RegulatoryFilings_Status CHECK (Status IN ('Draft', 'Prepared', 'Reviewed', 'Filed', 'Rejected')),
    CONSTRAINT CK_RegulatoryFilings_Type CHECK (FilingType IN ('AnnualStatement', 'QuarterlyReport', 'MarketConduct', 'FinancialAudit')),

    -- Indexes
    INDEX IX_RegulatoryFilings_Type (FilingType),
    INDEX IX_RegulatoryFilings_Status (Status),
    INDEX IX_RegulatoryFilings_FilingDate (FilingDate),
    INDEX IX_RegulatoryFilings_DueDate (DueDate)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Policy summary view
CREATE VIEW vw_PolicySummary
AS
SELECT
    p.PolicyID,
    p.PolicyNumber,
    c.CompanyName AS PolicyHolder,
    p.PolicyType,
    p.Status,
    p.EffectiveDate,
    p.ExpirationDate,
    p.PremiumAmount,
    COUNT(pc.CoverageID) AS CoverageCount,
    SUM(pc.Premium) AS CoveragePremiumTotal,
    MAX(cl.ReportedDate) AS LastClaimDate,
    COUNT(cl.ClaimID) AS TotalClaims
FROM Policies p
INNER JOIN Customers c ON p.PolicyHolderID = c.CustomerID
LEFT JOIN PolicyCoverages pc ON p.PolicyID = pc.PolicyID
LEFT JOIN Claims cl ON p.PolicyID = cl.PolicyID
WHERE p.Status IN ('Active', 'Expired')
GROUP BY p.PolicyID, p.PolicyNumber, c.CompanyName, p.PolicyType, p.Status,
         p.EffectiveDate, p.ExpirationDate, p.PremiumAmount;
GO

-- Claims processing view
CREATE VIEW vw_ClaimsProcessing
AS
SELECT
    cl.ClaimID,
    cl.ClaimNumber,
    p.PolicyNumber,
    c.CompanyName AS Claimant,
    cl.LossDate,
    cl.ReportedDate,
    cl.ClaimAmount,
    cl.Status,
    cl.FraudScore,
    cl.SettlementAmount,
    cl.SettlementDate,
    DATEDIFF(DAY, cl.ReportedDate, cl.SettlementDate) AS ProcessingDays,
    COUNT(cd.DocumentID) AS DocumentCount
FROM Claims cl
INNER JOIN Policies p ON cl.PolicyID = p.PolicyID
LEFT JOIN Customers c ON cl.ClaimantID = c.CustomerID
LEFT JOIN ClaimDocuments cd ON cl.ClaimID = cd.ClaimID
GROUP BY cl.ClaimID, cl.ClaimNumber, p.PolicyNumber, c.CompanyName, cl.LossDate,
         cl.ReportedDate, cl.ClaimAmount, cl.Status, cl.FraudScore, cl.SettlementAmount, cl.SettlementDate;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update policy last modified date
CREATE TRIGGER TR_Policies_LastModified
ON Policies
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE p
    SET p.LastModifiedDate = GETDATE()
    FROM Policies p
    INNER JOIN inserted i ON p.PolicyID = i.PolicyID;
END;
GO

-- Update premium status when paid
CREATE TRIGGER TR_PremiumPayments_UpdateStatus
ON PremiumPayments
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE pr
    SET pr.Status = 'Paid',
        pr.PaidDate = GETDATE()
    FROM Premiums pr
    INNER JOIN inserted i ON pr.PremiumID = i.PremiumID
    WHERE pr.Status = 'Unpaid';
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Create policy procedure
CREATE PROCEDURE sp_CreatePolicy
    @PolicyHolderID INT,
    @ProductID INT,
    @PolicyType NVARCHAR(50),
    @EffectiveDate DATE,
    @ExpirationDate DATE,
    @PremiumAmount DECIMAL(12,2),
    @UnderwriterID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PolicyNumber NVARCHAR(50);

    -- Generate policy number
    SET @PolicyNumber = 'POL-' + @PolicyType + '-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                       RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                       RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    INSERT INTO Policies (
        PolicyNumber, PolicyHolderID, ProductID, PolicyType, EffectiveDate,
        ExpirationDate, PremiumAmount, UnderwriterID
    )
    VALUES (
        @PolicyNumber, @PolicyHolderID, @ProductID, @PolicyType, @EffectiveDate,
        @ExpirationDate, @PremiumAmount, @UnderwriterID
    );

    SELECT SCOPE_IDENTITY() AS PolicyID, @PolicyNumber AS PolicyNumber;
END;
GO

-- File claim procedure
CREATE PROCEDURE sp_FileClaim
    @PolicyID INT,
    @InsuredID INT = NULL,
    @ClaimantID INT = NULL,
    @LossDate DATETIME2,
    @IncidentDescription NVARCHAR(MAX),
    @ClaimAmount DECIMAL(12,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ClaimNumber NVARCHAR(50);

    -- Generate claim number
    SET @ClaimNumber = 'CLM-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                      RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                      RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    INSERT INTO Claims (
        ClaimNumber, PolicyID, InsuredID, ClaimantID, LossDate,
        IncidentDescription, ClaimAmount
    )
    VALUES (
        @ClaimNumber, @PolicyID, @InsuredID, @ClaimantID, @LossDate,
        @IncidentDescription, @ClaimAmount
    );

    SELECT SCOPE_IDENTITY() AS ClaimID, @ClaimNumber AS ClaimNumber;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample customer
INSERT INTO Customers (CustomerNumber, CompanyName, PrimaryEmail) VALUES
('CUST-000001', 'ABC Manufacturing', 'contact@abc.com');

-- Insert sample policy
INSERT INTO Policies (PolicyNumber, PolicyHolderID, ProductID, PolicyType, EffectiveDate, ExpirationDate, PremiumAmount) VALUES
('POL-AUTO-202412-00001', 1, 1, 'Auto', '2024-01-01', '2025-01-01', 1200.00);

-- Insert sample coverage
INSERT INTO PolicyCoverages (PolicyID, CoverageCode, CoverageName, CoverageType, CoverageLimit, Deductible) VALUES
(1, 'COMP', 'Comprehensive Coverage', 'Primary', 100000.00, 500.00);

-- Insert sample claim
INSERT INTO Claims (ClaimNumber, PolicyID, LossDate, IncidentDescription, ClaimAmount) VALUES
('CLM-202412-00001', 1, '2024-06-15', 'Vehicle accident at intersection', 3500.00);

PRINT 'Insurance database schema created successfully!';
GO
