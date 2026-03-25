-- HR & Recruitment Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE HRDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE HRDB;
GO

-- Configure database for HR compliance
ALTER DATABASE HRDB
SET
    RECOVERY SIMPLE,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON,
    ENCRYPTION ON; -- Enable TDE for HR data protection
GO

-- =============================================
-- EMPLOYEE MANAGEMENT
-- =============================================

-- Employee master table
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

-- Departments
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

-- =============================================
-- RECRUITMENT & HIRING
-- =============================================

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

-- =============================================
-- PERFORMANCE & DEVELOPMENT
-- =============================================

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

-- Employee goals
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

-- Training programs
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

-- =============================================
-- COMPENSATION & BENEFITS
-- =============================================

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

-- =============================================
-- EMPLOYEE RELATIONS & COMPLIANCE
-- =============================================

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

-- Diversity metrics
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

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Employee profile view
CREATE VIEW vw_EmployeeProfile
AS
SELECT
    e.EmployeeID,
    e.EmployeeNumber,
    e.FirstName + ' ' + e.LastName AS FullName,
    e.Email,
    e.JobTitle,
    d.DepartmentName,
    m.FirstName + ' ' + m.LastName AS ManagerName,
    e.HireDate,
    e.EmploymentStatus,
    e.Salary,
    DATEDIFF(YEAR, e.HireDate, GETDATE()) AS YearsOfService,
    e.IsActive
FROM Employees e
LEFT JOIN Departments d ON e.DepartmentID = d.DepartmentID
LEFT JOIN Employees m ON e.ManagerID = m.EmployeeID
WHERE e.IsActive = 1;
GO

-- Recruitment pipeline view
CREATE VIEW vw_RecruitmentPipeline
AS
SELECT
    jr.RequisitionID,
    jr.JobTitle,
    jr.DepartmentID,
    d.DepartmentName,
    jr.Status AS RequisitionStatus,
    COUNT(ja.ApplicationID) AS TotalApplications,
    SUM(CASE WHEN ja.ApplicationStatus IN ('Shortlisted', 'Interviewed', 'Offered', 'Accepted') THEN 1 ELSE 0 END) AS QualifiedApplications,
    SUM(CASE WHEN ja.ApplicationStatus = 'Accepted' THEN 1 ELSE 0 END) AS OffersAccepted
FROM JobRequisitions jr
LEFT JOIN Departments d ON jr.DepartmentID = d.DepartmentID
LEFT JOIN JobApplications ja ON jr.RequisitionID = ja.RequisitionID
GROUP BY jr.RequisitionID, jr.JobTitle, jr.DepartmentID, d.DepartmentName, jr.Status;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update department employee count
CREATE TRIGGER TR_Employees_UpdateDepartmentCount
ON Employees
AFTER INSERT, DELETE, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Update employee count for affected departments
    UPDATE d
    SET d.EmployeeCount = (
        SELECT COUNT(*) FROM Employees e
        WHERE e.DepartmentID = d.DepartmentID AND e.EmploymentStatus = 'Active'
    )
    FROM Departments d
    WHERE d.DepartmentID IN (
        SELECT DISTINCT COALESCE(i.DepartmentID, d.DepartmentID)
        FROM inserted i FULL OUTER JOIN deleted d ON i.EmployeeID = d.EmployeeID
    );
END;
GO

-- Update application last modified date
CREATE TRIGGER TR_JobApplications_LastUpdated
ON JobApplications
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE ja
    SET ja.LastUpdatedDate = GETDATE()
    FROM JobApplications ja
    INNER JOIN inserted i ON ja.ApplicationID = i.ApplicationID;
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Create job requisition procedure
CREATE PROCEDURE sp_CreateJobRequisition
    @JobTitle NVARCHAR(100),
    @DepartmentID INT,
    @RequestedBy INT,
    @JobDescription NVARCHAR(MAX) = NULL,
    @Requirements NVARCHAR(MAX) = NULL,
    @SalaryRangeMin DECIMAL(12,2) = NULL,
    @SalaryRangeMax DECIMAL(12,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RequisitionNumber NVARCHAR(20);

    -- Generate requisition number
    SET @RequisitionNumber = 'REQ-' + CAST(YEAR(GETDATE()) AS NVARCHAR(4)) +
                           RIGHT('00' + CAST(MONTH(GETDATE()) AS NVARCHAR(2)), 2) + '-' +
                           RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

    INSERT INTO JobRequisitions (
        RequisitionNumber, JobTitle, DepartmentID, RequestedBy,
        JobDescription, Requirements, SalaryRangeMin, SalaryRangeMax
    )
    VALUES (
        @RequisitionNumber, @JobTitle, @DepartmentID, @RequestedBy,
        @JobDescription, @Requirements, @SalaryRangeMin, @SalaryRangeMax
    );

    SELECT SCOPE_IDENTITY() AS RequisitionID, @RequisitionNumber AS RequisitionNumber;
END;
GO

-- Submit job application procedure
CREATE PROCEDURE sp_SubmitJobApplication
    @RequisitionID INT,
    @FirstName NVARCHAR(50),
    @LastName NVARCHAR(50),
    @Email NVARCHAR(255),
    @Phone NVARCHAR(20) = NULL,
    @Resume NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    -- Check if applicant already exists
    DECLARE @ApplicantID INT;
    SELECT @ApplicantID = ApplicantID FROM JobApplicants WHERE Email = @Email;

    IF @ApplicantID IS NULL
    BEGIN
        INSERT INTO JobApplicants (FirstName, LastName, Email, Phone, Resume)
        VALUES (@FirstName, @LastName, @Email, @Phone, @Resume);

        SET @ApplicantID = SCOPE_IDENTITY();
    END

    -- Check for duplicate application
    IF EXISTS (SELECT 1 FROM JobApplications WHERE RequisitionID = @RequisitionID AND ApplicantID = @ApplicantID)
    BEGIN
        RAISERROR('Application already submitted for this position', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- Create application
    INSERT INTO JobApplications (RequisitionID, ApplicantID)
    VALUES (@RequisitionID, @ApplicantID);

    SELECT SCOPE_IDENTITY() AS ApplicationID;

    COMMIT TRANSACTION;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample department
INSERT INTO Departments (DepartmentName, DepartmentCode) VALUES
('Information Technology', 'IT');

-- Insert sample employee
INSERT INTO Employees (EmployeeNumber, FirstName, LastName, Email, HireDate, JobTitle, DepartmentID, Salary) VALUES
('EMP-000001', 'John', 'Smith', 'john.smith@company.com', '2020-01-15', 'HR Manager', 1, 75000.00);

-- Insert sample job requisition
INSERT INTO JobRequisitions (RequisitionNumber, JobTitle, DepartmentID, RequestedBy, JobDescription) VALUES
('REQ-202412-00001', 'Software Developer', 1, 1, 'Develop and maintain software applications');

-- Insert sample applicant
INSERT INTO JobApplicants (FirstName, LastName, Email, ApplicationSource) VALUES
('Jane', 'Doe', 'jane.doe@email.com', 'LinkedIn');

PRINT 'HR database schema created successfully!';
GO
