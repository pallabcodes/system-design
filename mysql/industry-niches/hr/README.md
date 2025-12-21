# HR & Recruitment Platform Database Design

## Overview

This comprehensive database schema supports modern Human Resources and recruitment platforms including employee management, talent acquisition, performance tracking, payroll processing, and compliance management. The design handles complex organizational structures, regulatory compliance, workforce analytics, and enterprise HR operations.

## Key Features

### 👥 Employee Management & Lifecycle
- **Comprehensive employee profiles** with personal information, job details, and career history
- **Organizational structure management** with reporting hierarchies and department structures
- **Employee lifecycle tracking** from onboarding through retirement and alumni relations
- **Workforce diversity and inclusion** tracking with compliance reporting

### 🎯 Recruitment & Talent Acquisition
- **Applicant tracking system** with multi-stage hiring processes and candidate scoring
- **Job requisition management** with approval workflows and budget tracking
- **Talent pool management** with passive candidate engagement and referral tracking
- **Diversity hiring initiatives** with bias reduction and inclusion metrics

### 📊 Performance & Development
- **Performance management** with goal setting, reviews, and feedback cycles
- **Learning & development** tracking with training programs and certifications
- **Succession planning** with talent mapping and leadership development
- **Employee engagement surveys** with action planning and follow-up

## Database Schema Highlights

### Core Tables

#### Employee Management
```sql
-- Employee master table with comprehensive HR data
CREATE TABLE Employees (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeNumber NVARCHAR(20) UNIQUE NOT NULL,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    Phone NVARCHAR(20),
    DateOfBirth DATE,
    Gender NVARCHAR(20),
    SSN VARBINARY(128), -- Encrypted SSN

    -- Employment details
    HireDate DATE NOT NULL,
    EmploymentStatus NVARCHAR(20) DEFAULT 'Active',
    EmployeeType NVARCHAR(20) DEFAULT 'FullTime', -- FullTime, PartTime, Contract, Intern
    JobTitle NVARCHAR(100),
    DepartmentID INT,
    ManagerID INT REFERENCES Employees(EmployeeID),
    WorkLocation NVARCHAR(100),
    RemoteWorkEligible BIT DEFAULT 0,

    -- Compensation
    Salary DECIMAL(12,2),
    HourlyRate DECIMAL(8,2),
    PayFrequency NVARCHAR(20) DEFAULT 'BiWeekly', -- Weekly, BiWeekly, SemiMonthly, Monthly
    OvertimeEligible BIT DEFAULT 1,

    -- Demographics for compliance
    Ethnicity NVARCHAR(50),
    VeteranStatus NVARCHAR(50),
    DisabilityStatus NVARCHAR(50),

    -- System fields
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_Employees_Status CHECK (EmploymentStatus IN ('Active', 'Inactive', 'Terminated', 'OnLeave')),
    CONSTRAINT CK_Employees_Type CHECK (EmployeeType IN ('FullTime', 'PartTime', 'Contract', 'Intern', 'Temporary')),
    CONSTRAINT CK_Employees_Age CHECK (DATEDIFF(YEAR, DateOfBirth, GETDATE()) >= 16),

    -- Indexes
    INDEX IX_Employees_Number (EmployeeNumber),
    INDEX IX_Employees_Email (Email),
    INDEX IX_Employees_Department (DepartmentID),
    INDEX IX_Employees_Manager (ManagerID),
    INDEX IX_Employees_Status (EmploymentStatus),
    INDEX IX_Employees_HireDate (HireDate)
);

-- Department and organizational structure
CREATE TABLE Departments (
    DepartmentID INT IDENTITY(1,1) PRIMARY KEY,
    DepartmentName NVARCHAR(100) NOT NULL,
    DepartmentCode NVARCHAR(20) UNIQUE NOT NULL,
    ParentDepartmentID INT REFERENCES Departments(DepartmentID),
    DepartmentHeadID INT REFERENCES Employees(EmployeeID),
    Location NVARCHAR(100),
    Budget DECIMAL(15,2),
    EmployeeCount INT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Departments_NoSelfReference CHECK (DepartmentID != ParentDepartmentID),

    -- Indexes
    INDEX IX_Departments_Code (DepartmentCode),
    INDEX IX_Departments_Parent (ParentDepartmentID),
    INDEX IX_Departments_Head (DepartmentHeadID)
);
```

#### Recruitment & Hiring
```sql
-- Job requisitions
CREATE TABLE JobRequisitions (
    RequisitionID INT IDENTITY(1,1) PRIMARY KEY,
    RequisitionNumber NVARCHAR(20) UNIQUE NOT NULL,
    JobTitle NVARCHAR(100) NOT NULL,
    DepartmentID INT REFERENCES Departments(DepartmentID),
    Location NVARCHAR(100),
    EmploymentType NVARCHAR(20), -- FullTime, PartTime, Contract, Intern
    SalaryRangeMin DECIMAL(12,2),
    SalaryRangeMax DECIMAL(12,2),
    JobDescription NVARCHAR(MAX),
    Requirements NVARCHAR(MAX),
    Responsibilities NVARCHAR(MAX),

    -- Approval and status
    RequestedBy INT NOT NULL REFERENCES Employees(EmployeeID),
    ApprovedBy INT REFERENCES Employees(EmployeeID),
    Status NVARCHAR(20) DEFAULT 'Draft',
    Priority NVARCHAR(10) DEFAULT 'Medium',
    TargetHireDate DATE,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_JobRequisitions_Status CHECK (Status IN ('Draft', 'PendingApproval', 'Approved', 'Open', 'OnHold', 'Filled', 'Cancelled')),
    CONSTRAINT CK_JobRequisitions_Priority CHECK (Priority IN ('Low', 'Medium', 'High', 'Urgent')),
    CONSTRAINT CK_JobRequisitions_Salary CHECK (SalaryRangeMax >= SalaryRangeMin),

    -- Indexes
    INDEX IX_JobRequisitions_Number (RequisitionNumber),
    INDEX IX_JobRequisitions_Department (DepartmentID),
    INDEX IX_JobRequisitions_Status (Status),
    INDEX IX_JobRequisitions_Created (CreatedDate)
);

-- Job applicants
CREATE TABLE JobApplicants (
    ApplicantID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    Phone NVARCHAR(20),
    Resume NVARCHAR(MAX), -- JSON format with experience, education, skills
    LinkedInURL NVARCHAR(500),
    PortfolioURL NVARCHAR(500),
    CurrentSalary DECIMAL(12,2),
    ExpectedSalary DECIMAL(12,2),

    -- Application tracking
    ApplicationSource NVARCHAR(50), -- CompanyWebsite, Indeed, LinkedIn, Referral
    ReferralEmployeeID INT REFERENCES Employees(EmployeeID),
    AppliedDate DATETIME2 DEFAULT GETDATE(),
    LastActivityDate DATETIME2 DEFAULT GETDATE(),

    -- Indexes
    INDEX IX_JobApplicants_Email (Email),
    INDEX IX_JobApplicants_Source (ApplicationSource),
    INDEX IX_JobApplicants_AppliedDate (AppliedDate)
);

-- Job applications
CREATE TABLE JobApplications (
    ApplicationID INT IDENTITY(1,1) PRIMARY KEY,
    RequisitionID INT NOT NULL REFERENCES JobRequisitions(RequisitionID),
    ApplicantID INT NOT NULL REFERENCES JobApplicants(ApplicantID),
    ApplicationStatus NVARCHAR(20) DEFAULT 'Submitted',
    SubmittedDate DATETIME2 DEFAULT GETDATE(),
    LastUpdatedDate DATETIME2 DEFAULT GETDATE(),
    CurrentStage NVARCHAR(50), -- Screening, Interview, Assessment, Offer, Hired
    Rating INT CHECK (Rating BETWEEN 1 AND 5),
    Notes NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT UQ_JobApplications_Unique UNIQUE (RequisitionID, ApplicantID),
    CONSTRAINT CK_JobApplications_Status CHECK (ApplicationStatus IN ('Submitted', 'UnderReview', 'Shortlisted', 'Interviewed', 'Offered', 'Accepted', 'Rejected', 'Withdrawn')),

    -- Indexes
    INDEX IX_JobApplications_Requisition (RequisitionID),
    INDEX IX_JobApplications_Applicant (ApplicantID),
    INDEX IX_JobApplications_Status (ApplicationStatus),
    INDEX IX_JobApplications_Stage (CurrentStage)
);
```

#### Performance & Development
```sql
-- Performance reviews
CREATE TABLE PerformanceReviews (
    ReviewID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT NOT NULL REFERENCES Employees(EmployeeID),
    ReviewPeriod NVARCHAR(20) NOT NULL, -- Annual, MidYear, Quarterly
    ReviewYear INT NOT NULL,
    ReviewerID INT REFERENCES Employees(EmployeeID),
    ReviewType NVARCHAR(20) DEFAULT 'Annual', -- Self, Manager, Peer, 360
    OverallRating DECIMAL(3,1) CHECK (OverallRating BETWEEN 1.0 AND 5.0),
    ReviewDate DATETIME2 DEFAULT GETDATE(),
    DueDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Draft',

    -- Review content
    Goals NVARCHAR(MAX), -- JSON array of goals
    Accomplishments NVARCHAR(MAX), -- JSON array
    DevelopmentAreas NVARCHAR(MAX), -- JSON array
    ReviewerComments NVARCHAR(MAX),
    EmployeeComments NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_PerformanceReviews_Status CHECK (Status IN ('Draft', 'Submitted', 'UnderReview', 'Completed', 'Acknowledged')),
    CONSTRAINT CK_PerformanceReviews_Type CHECK (ReviewType IN ('Self', 'Manager', 'Peer', '360', 'Annual')),

    -- Indexes
    INDEX IX_PerformanceReviews_Employee (EmployeeID),
    INDEX IX_PerformanceReviews_Reviewer (ReviewerID),
    INDEX IX_PerformanceReviews_Period (ReviewPeriod, ReviewYear),
    INDEX IX_PerformanceReviews_Status (Status)
);

-- Employee goals and objectives
CREATE TABLE EmployeeGoals (
    GoalID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT NOT NULL REFERENCES Employees(EmployeeID),
    GoalTitle NVARCHAR(200) NOT NULL,
    GoalDescription NVARCHAR(MAX),
    GoalCategory NVARCHAR(50), -- Individual, Team, Department, Company
    Priority NVARCHAR(10) DEFAULT 'Medium',
    TargetCompletionDate DATE,
    ActualCompletionDate DATE,
    Status NVARCHAR(20) DEFAULT 'Active',
    ProgressPercentage DECIMAL(5,2) DEFAULT 0,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_EmployeeGoals_Status CHECK (Status IN ('Active', 'Completed', 'Cancelled', 'OnHold')),
    CONSTRAINT CK_EmployeeGoals_Priority CHECK (Priority IN ('Low', 'Medium', 'High')),
    CONSTRAINT CK_EmployeeGoals_Progress CHECK (ProgressPercentage BETWEEN 0 AND 100),

    -- Indexes
    INDEX IX_EmployeeGoals_Employee (EmployeeID),
    INDEX IX_EmployeeGoals_Category (GoalCategory),
    INDEX IX_EmployeeGoals_Status (Status),
    INDEX IX_EmployeeGoals_TargetDate (TargetCompletionDate)
);

-- Training and development
CREATE TABLE TrainingPrograms (
    ProgramID INT IDENTITY(1,1) PRIMARY KEY,
    ProgramName NVARCHAR(200) NOT NULL,
    ProgramType NVARCHAR(50), -- Internal, External, Online, Classroom
    Description NVARCHAR(MAX),
    Provider NVARCHAR(100),
    DurationHours DECIMAL(6,2),
    Cost DECIMAL(10,2),
    MaxParticipants INT,
    StartDate DATETIME2,
    EndDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Active',

    -- Constraints
    CONSTRAINT CK_TrainingPrograms_Status CHECK (Status IN ('Active', 'Completed', 'Cancelled')),
    CONSTRAINT CK_TrainingPrograms_Type CHECK (ProgramType IN ('Internal', 'External', 'Online', 'Classroom', 'Certification')),

    -- Indexes
    INDEX IX_TrainingPrograms_Type (ProgramType),
    INDEX IX_TrainingPrograms_Status (Status),
    INDEX IX_TrainingPrograms_StartDate (StartDate)
);

-- Employee training records
CREATE TABLE EmployeeTraining (
    TrainingID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT NOT NULL REFERENCES Employees(EmployeeID),
    ProgramID INT NOT NULL REFERENCES TrainingPrograms(ProgramID),
    EnrollmentDate DATETIME2 DEFAULT GETDATE(),
    CompletionDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Enrolled',
    Score DECIMAL(5,2),
    CertificateNumber NVARCHAR(50),
    CertificateExpiry DATE,
    Cost DECIMAL(10,2),

    -- Constraints
    CONSTRAINT CK_EmployeeTraining_Status CHECK (Status IN ('Enrolled', 'InProgress', 'Completed', 'Failed', 'Withdrawn')),
    CONSTRAINT UQ_EmployeeTraining_Unique UNIQUE (EmployeeID, ProgramID),

    -- Indexes
    INDEX IX_EmployeeTraining_Employee (EmployeeID),
    INDEX IX_EmployeeTraining_Program (ProgramID),
    INDEX IX_EmployeeTraining_Status (Status),
    INDEX IX_EmployeeTraining_Completion (CompletionDate)
);
```

### Compensation & Benefits

#### Payroll & Compensation
```sql
-- Employee compensation history
CREATE TABLE EmployeeCompensation (
    CompensationID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT NOT NULL REFERENCES Employees(EmployeeID),
    CompensationType NVARCHAR(20) NOT NULL, -- BaseSalary, Bonus, Commission, Overtime
    Amount DECIMAL(12,2) NOT NULL,
    EffectiveDate DATE NOT NULL,
    EndDate DATE,
    PayFrequency NVARCHAR(20), -- Annual, Monthly, Hourly
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_EmployeeCompensation_Type CHECK (CompensationType IN ('BaseSalary', 'Bonus', 'Commission', 'Overtime', 'Allowance')),
    CONSTRAINT CK_EmployeeCompensation_Dates CHECK (EndDate IS NULL OR EndDate > EffectiveDate),

    -- Indexes
    INDEX IX_EmployeeCompensation_Employee (EmployeeID),
    INDEX IX_EmployeeCompensation_Type (CompensationType),
    INDEX IX_EmployeeCompensation_Effective (EffectiveDate)
);

-- Payroll periods
CREATE TABLE PayrollPeriods (
    PeriodID INT IDENTITY(1,1) PRIMARY KEY,
    PeriodName NVARCHAR(50) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    PayDate DATE NOT NULL,
    Status NVARCHAR(20) DEFAULT 'Open',

    -- Constraints
    CONSTRAINT CK_PayrollPeriods_Status CHECK (Status IN ('Open', 'Processing', 'Completed', 'Closed')),
    CONSTRAINT CK_PayrollPeriods_Dates CHECK (EndDate >= StartDate AND PayDate > EndDate),

    -- Indexes
    INDEX IX_PayrollPeriods_StartDate (StartDate),
    INDEX IX_PayrollPeriods_EndDate (EndDate),
    INDEX IX_PayrollPeriods_Status (Status)
);

-- Payroll entries
CREATE TABLE PayrollEntries (
    EntryID INT IDENTITY(1,1) PRIMARY KEY,
    PeriodID INT NOT NULL REFERENCES PayrollPeriods(PeriodID),
    EmployeeID INT NOT NULL REFERENCES Employees(EmployeeID),
    GrossPay DECIMAL(12,2) NOT NULL,
    NetPay DECIMAL(12,2) NOT NULL,
    HoursWorked DECIMAL(6,2),
    OvertimeHours DECIMAL(6,2),

    -- Deductions
    FederalTax DECIMAL(10,2) DEFAULT 0,
    StateTax DECIMAL(10,2) DEFAULT 0,
    SocialSecurity DECIMAL(10,2) DEFAULT 0,
    Medicare DECIMAL(10,2) DEFAULT 0,
    HealthInsurance DECIMAL(10,2) DEFAULT 0,
    Retirement DECIMAL(10,2) DEFAULT 0,
    OtherDeductions DECIMAL(10,2) DEFAULT 0,

    -- Processed information
    ProcessedDate DATETIME2,
    ProcessedBy INT REFERENCES Employees(EmployeeID),

    -- Constraints
    CONSTRAINT CK_PayrollEntries_Amounts CHECK (NetPay <= GrossPay),

    -- Indexes
    INDEX IX_PayrollEntries_Period (PeriodID),
    INDEX IX_PayrollEntries_Employee (EmployeeID),
    INDEX IX_PayrollEntries_ProcessedDate (ProcessedDate)
);
```

#### Employee Relations & Compliance
```sql
-- Employee relations cases
CREATE TABLE EmployeeRelations (
    CaseID INT IDENTITY(1,1) PRIMARY KEY,
    CaseNumber NVARCHAR(20) UNIQUE NOT NULL,
    EmployeeID INT NOT NULL REFERENCES Employees(EmployeeID),
    CaseType NVARCHAR(50) NOT NULL, -- Harassment, Discrimination, Performance, Disciplinary
    Severity NVARCHAR(20) DEFAULT 'Medium',
    Description NVARCHAR(MAX),
    ReportedBy INT REFERENCES Employees(EmployeeID),
    ReportedDate DATETIME2 DEFAULT GETDATE(),
    AssignedTo INT REFERENCES Employees(EmployeeID),
    Status NVARCHAR(20) DEFAULT 'Open',

    -- Investigation and resolution
    InvestigationNotes NVARCHAR(MAX),
    Resolution NVARCHAR(MAX),
    ResolutionDate DATETIME2,
    FollowUpRequired BIT DEFAULT 0,
    FollowUpDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_EmployeeRelations_Type CHECK (CaseType IN ('Harassment', 'Discrimination', 'Performance', 'Disciplinary', 'Grievance', 'Safety')),
    CONSTRAINT CK_EmployeeRelations_Status CHECK (Status IN ('Open', 'Investigating', 'Resolved', 'Closed', 'Escalated')),
    CONSTRAINT CK_EmployeeRelations_Severity CHECK (Severity IN ('Low', 'Medium', 'High', 'Critical')),

    -- Indexes
    INDEX IX_EmployeeRelations_Employee (EmployeeID),
    INDEX IX_EmployeeRelations_Type (CaseType),
    INDEX IX_EmployeeRelations_Status (Status),
    INDEX IX_EmployeeRelations_ReportedDate (ReportedDate)
);

-- Diversity and inclusion tracking
CREATE TABLE DiversityMetrics (
    MetricID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT REFERENCES Employees(EmployeeID),
    MetricType NVARCHAR(50) NOT NULL, -- Ethnicity, Gender, AgeGroup, VeteranStatus
    MetricValue NVARCHAR(100),
    EffectiveDate DATE DEFAULT CAST(GETDATE() AS DATE),
    EndDate DATE,

    -- Constraints
    CONSTRAINT CK_DiversityMetrics_Type CHECK (MetricType IN ('Ethnicity', 'Gender', 'AgeGroup', 'VeteranStatus', 'DisabilityStatus')),

    -- Indexes
    INDEX IX_DiversityMetrics_Employee (EmployeeID),
    INDEX IX_DiversityMetrics_Type (MetricType),
    INDEX IX_DiversityMetrics_EffectiveDate (EffectiveDate)
);
```

## Integration Points

### External Systems
- **Payroll Systems**: ADP, Paychex, Gusto for payroll processing and tax filing
- **Benefits Administration**: Benefits administration platforms for insurance and retirement
- **Learning Management**: LinkedIn Learning, Coursera for training program integration
- **Applicant Tracking**: Greenhouse, Workday for recruitment workflow automation
- **Performance Management**: 15Five, Culture Amp for employee engagement
- **Compliance Systems**: For regulatory reporting and diversity tracking

### API Endpoints
- **Employee Management APIs**: Profile updates, organizational changes, reporting
- **Recruitment APIs**: Job posting, applicant tracking, interview scheduling
- **Performance APIs**: Goal setting, review cycles, feedback collection
- **Payroll APIs**: Compensation changes, payroll processing, tax calculations
- **Analytics APIs**: Workforce metrics, diversity reporting, compliance tracking

## Monitoring & Analytics

### Key Performance Indicators
- **Recruitment Metrics**: Time to fill, cost per hire, quality of hire, offer acceptance rate
- **Employee Retention**: Turnover rate, voluntary vs involuntary separation, retention by tenure
- **Performance Management**: Review completion rates, performance rating distribution, development plan completion
- **Workforce Diversity**: Representation by protected groups, pay equity analysis, inclusion survey results
- **Training & Development**: Training completion rates, skill gap analysis, certification tracking

### Real-Time Dashboards
```sql
-- HR operations dashboard
CREATE VIEW HROperationsDashboard AS
SELECT
    -- Recruitment metrics (current month)
    (SELECT COUNT(*) FROM JobRequisitions
     WHERE MONTH(CreatedDate) = MONTH(GETDATE())
     AND YEAR(CreatedDate) = YEAR(GETDATE())) AS NewRequisitions,

    (SELECT COUNT(*) FROM JobApplications
     WHERE MONTH(SubmittedDate) = MONTH(GETDATE())
     AND YEAR(SubmittedDate) = YEAR(GETDATE())) AS ApplicationsReceived,

    (SELECT COUNT(*) FROM JobApplications
     WHERE ApplicationStatus = 'Accepted'
     AND MONTH(LastUpdatedDate) = MONTH(GETDATE())
     AND YEAR(LastUpdatedDate) = YEAR(GETDATE())) AS OffersAccepted,

    -- Employee metrics
    (SELECT COUNT(*) FROM Employees WHERE EmploymentStatus = 'Active') AS ActiveEmployees,

    (SELECT COUNT(*) FROM Employees
     WHERE MONTH(HireDate) = MONTH(GETDATE())
     AND YEAR(HireDate) = YEAR(GETDATE())) AS NewHires,

    (SELECT COUNT(*) FROM Employees
     WHERE EmploymentStatus = 'Terminated'
     AND MONTH(LastModifiedDate) = MONTH(GETDATE())
     AND YEAR(LastModifiedDate) = YEAR(GETDATE())) AS Terminations,

    -- Performance metrics
    (SELECT COUNT(*) FROM PerformanceReviews
     WHERE Status = 'Completed'
     AND MONTH(ReviewDate) = MONTH(GETDATE())
     AND YEAR(ReviewDate) = YEAR(GETDATE())) AS ReviewsCompleted,

    (SELECT AVG(CAST(OverallRating AS DECIMAL(3,2))) FROM PerformanceReviews
     WHERE Status = 'Completed'
     AND MONTH(ReviewDate) = MONTH(GETDATE())
     AND YEAR(ReviewDate) = YEAR(GETDATE())) AS AvgPerformanceRating,

    -- Training metrics
    (SELECT COUNT(*) FROM EmployeeTraining
     WHERE Status = 'Completed'
     AND MONTH(CompletionDate) = MONTH(GETDATE())
     AND YEAR(CompletionDate) = YEAR(GETDATE())) AS TrainingCompletions,

    (SELECT SUM(DurationHours) FROM EmployeeTraining et
     INNER JOIN TrainingPrograms tp ON et.ProgramID = tp.ProgramID
     WHERE et.Status = 'Completed'
     AND MONTH(et.CompletionDate) = MONTH(GETDATE())
     AND YEAR(et.CompletionDate) = YEAR(GETDATE())) AS TrainingHoursDelivered,

    -- Employee relations
    (SELECT COUNT(*) FROM EmployeeRelations
     WHERE Status IN ('Open', 'Investigating')) AS OpenCases,

    (SELECT COUNT(*) FROM EmployeeRelations
     WHERE MONTH(ReportedDate) = MONTH(GETDATE())
     AND YEAR(ReportedDate) = YEAR(GETDATE())) AS NewCasesReported

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This HR & Recruitment database schema provides a comprehensive foundation for modern human resources platforms, supporting employee management, recruitment processes, performance tracking, and enterprise HR operations while maintaining regulatory compliance and data security.
