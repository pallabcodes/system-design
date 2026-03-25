# Insurance Platform Database Design

## Overview

This comprehensive database schema supports modern insurance platforms including policy management, claims processing, underwriting, risk assessment, and regulatory compliance. The design handles complex insurance products, actuarial calculations, multi-line policies, and enterprise-level insurance operations.

## Key Features

### 🛡️ Policy Management & Administration
- **Multi-line policy support** with complex coverage combinations and riders
- **Policy lifecycle management** from quotation through renewal and cancellation
- **Flexible premium structures** with installment payments and billing cycles
- **Policyholder management** with beneficiaries, dependents, and coverage changes

### 📋 Claims Processing & Settlement
- **Automated claims intake** with digital documentation and validation workflows
- **Claims assessment and evaluation** with damage estimation and settlement calculations
- **Fraud detection** with automated scoring and investigation workflows
- **Claims payment processing** with check issuance and direct deposit integration

### 📊 Underwriting & Risk Management
- **Risk assessment models** with automated underwriting decision engines
- **Actuarial data management** with loss statistics and premium calculations
- **Reinsurance management** with treaty administration and claims recovery
- **Portfolio risk analysis** with concentration limits and exposure monitoring

## Database Schema Highlights

### Core Tables

#### Policy Management
```sql
-- Insurance policies master table
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

-- Policy coverage details
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

-- Policy insured objects (vehicles, properties, persons)
CREATE TABLE PolicyInsureds (
    InsuredID INT IDENTITY(1,1) PRIMARY KEY,
    PolicyID INT NOT NULL REFERENCES Policies(PolicyID) ON DELETE CASCADE,
    InsuredType NVARCHAR(50) NOT NULL, -- Vehicle, Property, Person, Business
    InsuredName NVARCHAR(200),
    Relationship NVARCHAR(50), -- Named Insured, Spouse, Child, etc.

    -- Vehicle/Property specific fields (stored as JSON)
    VehicleDetails NVARCHAR(MAX), -- {"make": "Toyota", "model": "Camry", "year": 2020}
    PropertyDetails NVARCHAR(MAX), -- {"address": "...", "value": 300000}
    PersonDetails NVARCHAR(MAX), -- {"age": 35, "occupation": "Engineer"}

    -- Indexes
    INDEX IX_PolicyInsureds_Policy (PolicyID),
    INDEX IX_PolicyInsureds_Type (InsuredType)
);
```

#### Claims Management
```sql
-- Insurance claims master table
CREATE TABLE Claims (
    ClaimID INT IDENTITY(1,1) PRIMARY KEY,
    ClaimNumber NVARCHAR(50) UNIQUE NOT NULL,
    PolicyID INT NOT NULL REFERENCES Policies(PolicyID),
    InsuredID INT REFERENCES PolicyInsureds(InsuredID),
    ClaimantID INT REFERENCES Customers(CustomerID), -- May be different from policyholder

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

-- Claim documents and evidence
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
```

### Premium & Billing Management

#### Premium Calculation & Billing
```sql
-- Premium calculations and billing
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
```

### Risk Assessment & Underwriting

#### Underwriting Data
```sql
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

-- Loss history and claims data
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
```

### Regulatory Compliance & Reporting

#### Regulatory Filings
```sql
-- Regulatory reports and filings
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

-- Compliance monitoring
CREATE TABLE ComplianceAudits (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    AuditType NVARCHAR(50) NOT NULL, -- Internal, External, Regulatory
    AuditPeriod NVARCHAR(20),
    StartDate DATETIME2 DEFAULT GETDATE(),
    EndDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'InProgress',

    -- Audit findings
    Findings NVARCHAR(MAX), -- JSON array of findings
    Recommendations NVARCHAR(MAX),
    CorrectiveActions NVARCHAR(MAX),

    -- Results
    OverallRating NVARCHAR(10), -- Excellent, Good, Satisfactory, NeedsImprovement
    AssignedTo NVARCHAR(100),

    -- Constraints
    CONSTRAINT CK_ComplianceAudits_Status CHECK (Status IN ('Planned', 'InProgress', 'Completed', 'FollowUp')),
    CONSTRAINT CK_ComplianceAudits_Type CHECK (AuditType IN ('Internal', 'External', 'Regulatory', 'Quality')),
    CONSTRAINT CK_ComplianceAudits_Rating CHECK (OverallRating IN ('Excellent', 'Good', 'Satisfactory', 'NeedsImprovement')),

    -- Indexes
    INDEX IX_ComplianceAudits_Type (AuditType),
    INDEX IX_ComplianceAudits_Status (Status),
    INDEX IX_ComplianceAudits_StartDate (StartDate),
    INDEX IX_ComplianceAudits_Rating (OverallRating)
);
```

## Integration Points

### External Systems
- **Rating engines**: Automated premium calculation and risk assessment
- **Claims systems**: Third-party claims administration and adjuster networks
- **Payment processors**: Integration with banks and payment gateways
- **Regulatory systems**: State insurance department portals and NAIC databases
- **Reinsurance platforms**: Treaty administration and claims recovery
- **Actuarial software**: Statistical analysis and loss modeling tools

### API Endpoints
- **Policy Management APIs**: Quotes, issuance, changes, and cancellations
- **Claims APIs**: Filing, status tracking, and settlement processing
- **Billing APIs**: Premium calculation, payment processing, and statements
- **Underwriting APIs**: Risk assessment, policy approval, and rating
- **Reporting APIs**: Regulatory filings, performance metrics, and analytics

## Monitoring & Analytics

### Key Performance Indicators
- **Underwriting Performance**: Loss ratios, combined ratios, expense ratios
- **Claims Management**: Average settlement time, claims accuracy, fraud detection rates
- **Customer Satisfaction**: Net Promoter Score, retention rates, complaint resolution
- **Financial Metrics**: Premium growth, profitability by line of business, return on equity
- **Regulatory Compliance**: Audit findings, violation rates, remediation time

### Real-Time Dashboards
```sql
-- Insurance operations dashboard
CREATE VIEW InsuranceOperationsDashboard AS
SELECT
    -- Policy metrics (current month)
    (SELECT COUNT(*) FROM Policies
     WHERE MONTH(CreatedDate) = MONTH(GETDATE())
     AND YEAR(CreatedDate) = YEAR(GETDATE())) AS NewPolicies,

    (SELECT SUM(PremiumAmount) FROM Policies
     WHERE Status = 'Active') AS TotalPremiumsInForce,

    (SELECT COUNT(*) FROM Policies
     WHERE ExpirationDate BETWEEN GETDATE() AND DATEADD(MONTH, 1, GETDATE())
     AND Status = 'Active') AS PoliciesExpiringNextMonth,

    -- Claims metrics (current month)
    (SELECT COUNT(*) FROM Claims
     WHERE MONTH(ReportedDate) = MONTH(GETDATE())
     AND YEAR(ReportedDate) = YEAR(GETDATE())) AS NewClaims,

    (SELECT COUNT(*) FROM Claims
     WHERE Status IN ('Open', 'Investigating')) AS OpenClaims,

    (SELECT AVG(DATEDIFF(DAY, ReportedDate, SettlementDate)) FROM Claims
     WHERE Status = 'Closed' AND SettlementDate IS NOT NULL
     AND MONTH(SettlementDate) = MONTH(GETDATE())) AS AvgSettlementTime,

    (SELECT SUM(ClaimAmount) FROM Claims
     WHERE Status = 'Approved'
     AND MONTH(SettlementDate) = MONTH(GETDATE())) AS ClaimsPaidThisMonth,

    -- Financial metrics
    (SELECT SUM(PaymentAmount) FROM PremiumPayments
     WHERE MONTH(PaymentDate) = MONTH(GETDATE())
     AND YEAR(PaymentDate) = YEAR(GETDATE())) AS PremiumsCollected,

    (SELECT SUM(PaymentAmount) FROM ClaimPayments
     WHERE MONTH(PaymentDate) = MONTH(GETDATE())
     AND YEAR(PaymentDate) = YEAR(GETDATE())) AS ClaimsPaid,

    -- Risk metrics
    (SELECT COUNT(*) FROM Claims
     WHERE FraudScore > 70
     AND MONTH(ReportedDate) = MONTH(GETDATE())) AS HighRiskClaims,

    (SELECT AVG(RiskScore) FROM UnderwritingApplications
     WHERE MONTH(SubmissionDate) = MONTH(GETDATE())) AS AvgRiskScore,

    -- Compliance metrics
    (SELECT COUNT(*) FROM RegulatoryFilings
     WHERE Status = 'Filed'
     AND MONTH(FilingDate) = MONTH(GETDATE())) AS RegulatoryFilingsCompleted,

    (SELECT COUNT(*) FROM ComplianceAudits
     WHERE Status = 'Completed'
     AND MONTH(EndDate) = MONTH(GETDATE())) AS AuditsCompleted

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This insurance database schema provides a comprehensive foundation for modern insurance platforms, supporting policy administration, claims processing, underwriting, and enterprise-level regulatory compliance while maintaining high performance and data integrity.
