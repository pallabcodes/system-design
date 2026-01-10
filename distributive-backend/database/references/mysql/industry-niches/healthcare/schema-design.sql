-- Healthcare Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database with HIPAA compliance settings
CREATE DATABASE HealthcareDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE HealthcareDB;
GO

-- Configure database for healthcare compliance
ALTER DATABASE HealthcareDB
SET
    RECOVERY FULL,
    PAGE_VERIFY CHECKSUM,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON,
    ENCRYPTION ON; -- Enable TDE for data at rest encryption
GO

-- Create encryption certificate for PHI data
CREATE CERTIFICATE PHIDataEncryption
WITH SUBJECT = 'PHI Data Encryption Certificate';
GO

-- =============================================
-- PATIENT MANAGEMENT
-- =============================================

-- Patient master table with HIPAA compliance
CREATE TABLE Patients (
    PatientID INT IDENTITY(1,1) PRIMARY KEY,
    MRN NVARCHAR(20) UNIQUE NOT NULL,  -- Medical Record Number
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    DateOfBirth DATE NOT NULL,
    Gender CHAR(1) CHECK (Gender IN ('M', 'F', 'O', 'U')),
    SSN VARBINARY(128),  -- Encrypted SSN
    Race NVARCHAR(50),
    Ethnicity NVARCHAR(50),
    PreferredLanguage NVARCHAR(10),
    MaritalStatus NVARCHAR(20),
    Religion NVARCHAR(50),
    Occupation NVARCHAR(100),
    EmergencyContact NVARCHAR(MAX), -- JSON format
    PrimaryCareProviderID INT,
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_Patients_Age CHECK (DATEDIFF(YEAR, DateOfBirth, GETDATE()) >= 0),
    CONSTRAINT CK_Patients_MRN_Format CHECK (MRN LIKE '[A-Z][A-Z]-[0-9][0-9][0-9][0-9][0-9][0-9]'),

    -- Indexes
    INDEX IX_Patients_MRN (MRN),
    INDEX IX_Patients_LastName (LastName),
    INDEX IX_Patients_DateOfBirth (DateOfBirth),
    INDEX IX_Patients_PCP (PrimaryCareProviderID),
    INDEX IX_Patients_IsActive (IsActive)
);

-- Patient identifiers (HIPAA compliant)
CREATE TABLE PatientIdentifiers (
    IdentifierID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT NOT NULL REFERENCES Patients(PatientID) ON DELETE CASCADE,
    IdentifierType NVARCHAR(50) NOT NULL, -- SSN, DriverLicense, Passport, etc.
    IdentifierValue VARBINARY(256) NOT NULL, -- Encrypted
    IssuingAuthority NVARCHAR(100),
    EffectiveDate DATE,
    ExpirationDate DATE,
    IsPrimary BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_PatientIdentifiers_Primary UNIQUE (PatientID, IdentifierType) WHERE IsPrimary = 1,

    -- Indexes
    INDEX IX_PatientIdentifiers_Patient (PatientID),
    INDEX IX_PatientIdentifiers_Type (IdentifierType)
);

-- Patient addresses with privacy controls
CREATE TABLE PatientAddresses (
    AddressID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT NOT NULL REFERENCES Patients(PatientID) ON DELETE CASCADE,
    AddressType NVARCHAR(20) DEFAULT 'Home', -- Home, Work, Temporary
    Street NVARCHAR(255),
    City NVARCHAR(100),
    State NVARCHAR(50),
    ZipCode NVARCHAR(20),
    Country NVARCHAR(50) DEFAULT 'USA',
    Latitude DECIMAL(10,7),
    Longitude DECIMAL(10,7),
    IsActive BIT DEFAULT 1,
    EffectiveDate DATE DEFAULT CAST(GETDATE() AS DATE),
    EndDate DATE,

    -- Indexes
    INDEX IX_PatientAddresses_Patient (PatientID),
    INDEX IX_PatientAddresses_Type (AddressType),
    INDEX IX_PatientAddresses_IsActive (IsActive)
);

-- Patient insurance information
CREATE TABLE PatientInsurance (
    InsuranceID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT NOT NULL REFERENCES Patients(PatientID) ON DELETE CASCADE,
    InsuranceType NVARCHAR(50), -- Primary, Secondary, Tertiary
    PayerName NVARCHAR(100),
    PayerID NVARCHAR(50),
    GroupNumber NVARCHAR(50),
    MemberID NVARCHAR(50),
    PolicyNumber NVARCHAR(50),
    EffectiveDate DATE,
    TerminationDate DATE,
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_PatientInsurance_Dates CHECK (TerminationDate >= EffectiveDate OR TerminationDate IS NULL),

    -- Indexes
    INDEX IX_PatientInsurance_Patient (PatientID),
    INDEX IX_PatientInsurance_IsActive (IsActive),
    INDEX IX_PatientInsurance_Effective (EffectiveDate, TerminationDate)
);

-- =============================================
-- PROVIDER MANAGEMENT
-- =============================================

-- Healthcare providers
CREATE TABLE Providers (
    ProviderID INT IDENTITY(1,1) PRIMARY KEY,
    NPI NVARCHAR(10) UNIQUE NOT NULL, -- National Provider Identifier
    FirstName NVARCHAR(50),
    LastName NVARCHAR(50),
    ProviderType NVARCHAR(50) NOT NULL, -- Physician, Nurse, PA, etc.
    Specialty NVARCHAR(100),
    LicenseNumber NVARCHAR(50),
    LicenseState NVARCHAR(2),
    LicenseExpiration DATE,
    DEA NVARCHAR(20), -- For controlled substances
    Email NVARCHAR(255),
    Phone NVARCHAR(20),
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_Providers_LicenseExpiration CHECK (LicenseExpiration > GETDATE()),

    -- Indexes
    INDEX IX_Providers_NPI (NPI),
    INDEX IX_Providers_Type (ProviderType),
    INDEX IX_Providers_Specialty (Specialty),
    INDEX IX_Providers_IsActive (IsActive)
);

-- Provider credentials and certifications
CREATE TABLE ProviderCredentials (
    CredentialID INT IDENTITY(1,1) PRIMARY KEY,
    ProviderID INT NOT NULL REFERENCES Providers(ProviderID) ON DELETE CASCADE,
    CredentialType NVARCHAR(100) NOT NULL, -- Board Certification, License, etc.
    CredentialNumber NVARCHAR(100),
    IssuingOrganization NVARCHAR(200),
    IssueDate DATE,
    ExpirationDate DATE,
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_ProviderCredentials_Expiration CHECK (ExpirationDate > IssueDate),

    -- Indexes
    INDEX IX_ProviderCredentials_Provider (ProviderID),
    INDEX IX_ProviderCredentials_Type (CredentialType),
    INDEX IX_ProviderCredentials_IsActive (IsActive)
);

-- =============================================
-- CLINICAL DATA MANAGEMENT
-- =============================================

-- Healthcare encounters
CREATE TABLE Encounters (
    EncounterID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT NOT NULL REFERENCES Patients(PatientID),
    ProviderID INT NOT NULL REFERENCES Providers(ProviderID),
    EncounterType NVARCHAR(50) NOT NULL, -- OfficeVisit, HospitalStay, Telemedicine, etc.
    EncounterDate DATETIME2 NOT NULL,
    LocationID INT,
    ChiefComplaint NVARCHAR(MAX),
    Status NVARCHAR(20) DEFAULT 'Scheduled',
    DischargeDisposition NVARCHAR(100),
    LengthOfStay INT, -- In minutes
    FollowUpRequired BIT DEFAULT 0,
    FollowUpDate DATETIME2,
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT CK_Encounters_Status CHECK (Status IN ('Scheduled', 'InProgress', 'Completed', 'Cancelled', 'NoShow')),
    CONSTRAINT CK_Encounters_FollowUp CHECK (
        (FollowUpRequired = 0 AND FollowUpDate IS NULL) OR
        (FollowUpRequired = 1 AND FollowUpDate IS NOT NULL)
    ),

    -- Indexes
    INDEX IX_Encounters_Patient (PatientID),
    INDEX IX_Encounters_Provider (ProviderID),
    INDEX IX_Encounters_Type (EncounterType),
    INDEX IX_Encounters_Date (EncounterDate),
    INDEX IX_Encounters_Status (Status)
);

-- Vital signs and measurements
CREATE TABLE VitalSigns (
    VitalSignID INT IDENTITY(1,1) PRIMARY KEY,
    EncounterID INT NOT NULL REFERENCES Encounters(EncounterID) ON DELETE CASCADE,
    MeasurementType NVARCHAR(50) NOT NULL, -- BloodPressure, HeartRate, Temperature, etc.
    Value DECIMAL(10,3) NOT NULL,
    Unit NVARCHAR(20) NOT NULL,
    MeasuredDate DATETIME2 DEFAULT GETDATE(),
    MeasuredBy INT REFERENCES Providers(ProviderID),

    -- Constraints
    CONSTRAINT CK_VitalSigns_Value CHECK (Value > 0),

    -- Indexes
    INDEX IX_VitalSigns_Encounter (EncounterID),
    INDEX IX_VitalSigns_Type (MeasurementType),
    INDEX IX_VitalSigns_Date (MeasuredDate)
);

-- Patient diagnoses
CREATE TABLE Diagnoses (
    DiagnosisID INT IDENTITY(1,1) PRIMARY KEY,
    EncounterID INT NOT NULL REFERENCES Encounters(EncounterID) ON DELETE CASCADE,
    PatientID INT NOT NULL REFERENCES Patients(PatientID),
    ICD10Code NVARCHAR(10) NOT NULL,
    DiagnosisDescription NVARCHAR(MAX),
    DiagnosisDate DATETIME2 DEFAULT GETDATE(),
    IsPrimary BIT DEFAULT 0,
    Severity NVARCHAR(20), -- Mild, Moderate, Severe
    Status NVARCHAR(20) DEFAULT 'Active', -- Active, Resolved, Chronic
    ProviderID INT REFERENCES Providers(ProviderID),

    -- Constraints
    CONSTRAINT CK_Diagnoses_Status CHECK (Status IN ('Active', 'Resolved', 'Chronic', 'Inactive')),

    -- Indexes
    INDEX IX_Diagnoses_Encounter (EncounterID),
    INDEX IX_Diagnoses_Patient (PatientID),
    INDEX IX_Diagnoses_ICD10 (ICD10Code),
    INDEX IX_Diagnoses_Status (Status),
    INDEX IX_Diagnoses_Provider (ProviderID)
);

-- Problem list (active medical problems)
CREATE TABLE PatientProblems (
    ProblemID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT NOT NULL REFERENCES Patients(PatientID),
    DiagnosisID INT REFERENCES Diagnoses(DiagnosisID),
    ProblemDescription NVARCHAR(MAX) NOT NULL,
    ICD10Code NVARCHAR(10),
    OnsetDate DATE,
    ResolutionDate DATE,
    Status NVARCHAR(20) DEFAULT 'Active',
    Chronic BIT DEFAULT 0,
    ProviderID INT REFERENCES Providers(ProviderID),

    -- Constraints
    CONSTRAINT CK_PatientProblems_Status CHECK (Status IN ('Active', 'Resolved', 'Chronic', 'Inactive')),
    CONSTRAINT CK_PatientProblems_Resolution CHECK (
        (Status IN ('Resolved', 'Inactive') AND ResolutionDate IS NOT NULL) OR
        (Status NOT IN ('Resolved', 'Inactive') AND ResolutionDate IS NULL)
    ),

    -- Indexes
    INDEX IX_PatientProblems_Patient (PatientID),
    INDEX IX_PatientProblems_Status (Status),
    INDEX IX_PatientProblems_Chronic (Chronic)
);

-- =============================================
-- MEDICATIONS AND TREATMENTS
-- =============================================

-- Medications
CREATE TABLE Medications (
    MedicationID INT IDENTITY(1,1) PRIMARY KEY,
    DrugName NVARCHAR(200) NOT NULL,
    GenericName NVARCHAR(200),
    Strength NVARCHAR(50),
    Form NVARCHAR(50), -- Tablet, Capsule, Injection, etc.
    Route NVARCHAR(50), -- Oral, IV, Topical, etc.
    RxNormCode NVARCHAR(20),
    IsActive BIT DEFAULT 1,

    -- Indexes
    INDEX IX_Medications_DrugName (DrugName),
    INDEX IX_Medications_RxNorm (RxNormCode),
    INDEX IX_Medications_IsActive (IsActive)
);

-- Medication orders and prescriptions
CREATE TABLE MedicationOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT NOT NULL REFERENCES Patients(PatientID),
    EncounterID INT REFERENCES Encounters(EncounterID),
    MedicationID INT NOT NULL REFERENCES Medications(MedicationID),
    ProviderID INT NOT NULL REFERENCES Providers(ProviderID),
    OrderDate DATETIME2 DEFAULT GETDATE(),
    StartDate DATE,
    EndDate DATE,
    Dosage NVARCHAR(100),
    Frequency NVARCHAR(100),
    Duration NVARCHAR(50),
    Quantity DECIMAL(10,2),
    Refills INT DEFAULT 0,
    Status NVARCHAR(20) DEFAULT 'Active',
    Instructions NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_MedicationOrders_Dates CHECK (EndDate >= StartDate),
    CONSTRAINT CK_MedicationOrders_Status CHECK (Status IN ('Active', 'Completed', 'Discontinued', 'Held')),

    -- Indexes
    INDEX IX_MedicationOrders_Patient (PatientID),
    INDEX IX_MedicationOrders_Encounter (EncounterID),
    INDEX IX_MedicationOrders_Medication (MedicationID),
    INDEX IX_MedicationOrders_Provider (ProviderID),
    INDEX IX_MedicationOrders_Status (Status),
    INDEX IX_MedicationOrders_StartDate (StartDate)
);

-- Medication administration
CREATE TABLE MedicationAdministration (
    AdminID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES MedicationOrders(OrderID),
    PatientID INT NOT NULL REFERENCES Patients(PatientID),
    AdministeredBy INT REFERENCES Providers(ProviderID),
    AdministeredDate DATETIME2 DEFAULT GETDATE(),
    DoseGiven NVARCHAR(100),
    Route NVARCHAR(50),
    Site NVARCHAR(100), -- For injections
    Notes NVARCHAR(MAX),

    -- Indexes
    INDEX IX_MedicationAdministration_Order (OrderID),
    INDEX IX_MedicationAdministration_Patient (PatientID),
    INDEX IX_MedicationAdministration_Date (AdministeredDate)
);

-- =============================================
-- CLINICAL DOCUMENTATION
-- =============================================

-- Clinical notes and documentation
CREATE TABLE ClinicalNotes (
    NoteID INT IDENTITY(1,1) PRIMARY KEY,
    EncounterID INT NOT NULL REFERENCES Encounters(EncounterID) ON DELETE CASCADE,
    PatientID INT NOT NULL REFERENCES Patients(PatientID),
    ProviderID INT NOT NULL REFERENCES Providers(ProviderID),
    NoteType NVARCHAR(50) NOT NULL, -- ProgressNote, Consultation, ProcedureNote, etc.
    Subject NVARCHAR(200),
    NoteContent NVARCHAR(MAX) NOT NULL,
    NoteDate DATETIME2 DEFAULT GETDATE(),
    TemplateUsed NVARCHAR(100),
    IsSigned BIT DEFAULT 0,
    SignedDate DATETIME2,
    SignedBy INT REFERENCES Providers(ProviderID),

    -- Full-text search
    INDEX IX_ClinicalNotes_FullText (NoteContent) WHERE IsSigned = 1,

    -- Indexes
    INDEX IX_ClinicalNotes_Encounter (EncounterID),
    INDEX IX_ClinicalNotes_Patient (PatientID),
    INDEX IX_ClinicalNotes_Provider (ProviderID),
    INDEX IX_ClinicalNotes_Type (NoteType),
    INDEX IX_ClinicalNotes_Date (NoteDate),
    INDEX IX_ClinicalNotes_IsSigned (IsSigned)
);

-- Structured clinical data (CCD/CDA)
CREATE TABLE ClinicalDocuments (
    DocumentID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT NOT NULL REFERENCES Patients(PatientID),
    DocumentType NVARCHAR(50) NOT NULL, -- CCD, CDA, DischargeSummary, etc.
    DocumentFormat NVARCHAR(20) DEFAULT 'XML', -- XML, JSON, PDF
    DocumentContent NVARCHAR(MAX) NOT NULL,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CreatedBy INT REFERENCES Providers(ProviderID),
    IsCurrent BIT DEFAULT 1,
    Version INT DEFAULT 1,

    -- Full-text search on XML/JSON content
    INDEX IX_ClinicalDocuments_FullText (DocumentContent) WHERE DocumentFormat IN ('XML', 'JSON'),

    -- Indexes
    INDEX IX_ClinicalDocuments_Patient (PatientID),
    INDEX IX_ClinicalDocuments_Type (DocumentType),
    INDEX IX_ClinicalDocuments_IsCurrent (IsCurrent)
);

-- =============================================
-- QUALITY METRICS & ANALYTICS
-- =============================================

-- Quality measures tracking
CREATE TABLE QualityMeasures (
    MeasureID INT IDENTITY(1,1) PRIMARY KEY,
    MeasureName NVARCHAR(200) NOT NULL,
    MeasureCode NVARCHAR(50) UNIQUE,
    Description NVARCHAR(MAX),
    NumeratorDescription NVARCHAR(MAX),
    DenominatorDescription NVARCHAR(MAX),
    MeasureType NVARCHAR(50), -- Process, Outcome, Structure
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE()
);

-- Patient quality measure results
CREATE TABLE PatientQualityMeasures (
    MeasureResultID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT NOT NULL REFERENCES Patients(PatientID),
    MeasureID INT NOT NULL REFERENCES QualityMeasures(MeasureID),
    EncounterID INT REFERENCES Encounters(EncounterID),
    MeasureDate DATETIME2 DEFAULT GETDATE(),
    NumeratorValue BIT, -- Did patient meet the measure
    DenominatorValue BIT DEFAULT 1, -- Was patient eligible
    Exclusions NVARCHAR(MAX), -- JSON array of exclusion reasons

    -- Indexes
    INDEX IX_PatientQualityMeasures_Patient (PatientID),
    INDEX IX_PatientQualityMeasures_Measure (MeasureID),
    INDEX IX_PatientQualityMeasures_Date (MeasureDate)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Patient summary view
CREATE VIEW vw_PatientSummary
AS
SELECT
    p.PatientID,
    p.MRN,
    p.FirstName + ' ' + p.LastName AS PatientName,
    p.DateOfBirth,
    DATEDIFF(YEAR, p.DateOfBirth, GETDATE()) AS Age,
    p.Gender,
    prov.FirstName + ' ' + prov.LastName AS PrimaryCareProvider,
    COUNT(DISTINCT e.EncounterID) AS TotalEncounters,
    COUNT(DISTINCT pp.ProblemID) AS ActiveProblems,
    COUNT(DISTINCT mo.OrderID) AS ActiveMedications,
    MAX(e.EncounterDate) AS LastVisitDate
FROM Patients p
LEFT JOIN Providers prov ON p.PrimaryCareProviderID = prov.ProviderID
LEFT JOIN Encounters e ON p.PatientID = e.PatientID
LEFT JOIN PatientProblems pp ON p.PatientID = pp.PatientID AND pp.Status = 'Active'
LEFT JOIN MedicationOrders mo ON p.PatientID = mo.PatientID AND mo.Status = 'Active'
WHERE p.IsActive = 1
GROUP BY p.PatientID, p.MRN, p.FirstName, p.LastName, p.DateOfBirth, p.Gender,
         prov.FirstName, prov.LastName;
GO

-- Provider dashboard view
CREATE VIEW vw_ProviderDashboard
AS
SELECT
    pr.ProviderID,
    pr.NPI,
    pr.FirstName + ' ' + pr.LastName AS ProviderName,
    pr.ProviderType,
    pr.Specialty,
    COUNT(DISTINCT e.PatientID) AS UniquePatients,
    COUNT(e.EncounterID) AS TotalEncounters,
    AVG(CAST(e.LengthOfStay AS DECIMAL(10,2))) AS AvgEncounterLength,
    COUNT(DISTINCT pc.CredentialID) AS ActiveCredentials,
    MAX(e.EncounterDate) AS LastEncounterDate
FROM Providers pr
LEFT JOIN Encounters e ON pr.ProviderID = e.ProviderID AND e.Status = 'Completed'
LEFT JOIN ProviderCredentials pc ON pr.ProviderID = pc.ProviderID AND pc.IsActive = 1
WHERE pr.IsActive = 1
GROUP BY pr.ProviderID, pr.NPI, pr.FirstName, pr.LastName, pr.ProviderType, pr.Specialty;
GO

-- Quality metrics summary view
CREATE VIEW vw_QualityMetricsSummary
AS
SELECT
    qm.MeasureName,
    qm.MeasureCode,
    COUNT(pqm.MeasureResultID) AS TotalEvaluations,
    SUM(CASE WHEN pqm.NumeratorValue = 1 THEN 1 ELSE 0 END) AS NumeratorCount,
    SUM(CASE WHEN pqm.DenominatorValue = 1 THEN 1 ELSE 0 END) AS DenominatorCount,
    CAST(SUM(CASE WHEN pqm.NumeratorValue = 1 THEN 1 ELSE 0 END) AS DECIMAL(10,2)) /
    NULLIF(SUM(CASE WHEN pqm.DenominatorValue = 1 THEN 1 ELSE 0 END), 0) * 100 AS PerformanceRate,
    MAX(pqm.MeasureDate) AS LastUpdated
FROM QualityMeasures qm
LEFT JOIN PatientQualityMeasures pqm ON qm.MeasureID = pqm.MeasureID
WHERE qm.IsActive = 1
GROUP BY qm.MeasureID, qm.MeasureName, qm.MeasureCode;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Patient age update trigger
CREATE TRIGGER TR_Patients_AgeUpdate
ON Patients
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate age constraints
    IF EXISTS (
        SELECT 1 FROM inserted
        WHERE DATEDIFF(YEAR, DateOfBirth, GETDATE()) < 0
    )
    BEGIN
        RAISERROR('Invalid date of birth - patient cannot be born in the future', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- Encounter status validation trigger
CREATE TRIGGER TR_Encounters_StatusValidation
ON Encounters
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Ensure completed encounters have required fields
    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN deleted d ON i.EncounterID = d.EncounterID
        WHERE i.Status = 'Completed'
        AND d.Status != 'Completed'
        AND (i.DischargeDisposition IS NULL OR i.LengthOfStay IS NULL)
    )
    BEGIN
        RAISERROR('Completed encounters must have discharge disposition and length of stay', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- Medication order validation trigger
CREATE TRIGGER TR_MedicationOrders_Validation
ON MedicationOrders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate DEA requirements for controlled substances
    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN Medications m ON i.MedicationID = m.MedicationID
        INNER JOIN Providers p ON i.ProviderID = p.ProviderID
        WHERE m.DrugName LIKE '%controlled%'
        AND (p.DEA IS NULL OR LEN(p.DEA) = 0)
    )
    BEGIN
        RAISERROR('Provider must have valid DEA number for controlled substances', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample providers
INSERT INTO Providers (NPI, FirstName, LastName, ProviderType, Specialty, LicenseNumber, LicenseState, DEA) VALUES
('1234567890', 'John', 'Smith', 'Physician', 'Internal Medicine', 'MD12345', 'CA', 'BS1234567'),
('0987654321', 'Jane', 'Doe', 'Nurse Practitioner', 'Family Practice', 'NP67890', 'CA', NULL);

-- Insert sample patients
INSERT INTO Patients (MRN, FirstName, LastName, DateOfBirth, Gender, Race, Ethnicity) VALUES
('MR-000001', 'Alice', 'Johnson', '1985-03-15', 'F', 'White', 'Not Hispanic'),
('MR-000002', 'Bob', 'Wilson', '1972-08-22', 'M', 'Black', 'Not Hispanic');

-- Insert sample encounter
INSERT INTO Encounters (PatientID, ProviderID, EncounterType, EncounterDate, ChiefComplaint, Status) VALUES
(1, 1, 'OfficeVisit', GETDATE(), 'Annual physical examination', 'Completed');

-- Insert sample medications
INSERT INTO Medications (DrugName, GenericName, Strength, Form, Route, RxNormCode) VALUES
('Lisinopril', 'Lisinopril', '10mg', 'Tablet', 'Oral', '314076'),
('Metformin', 'Metformin', '500mg', 'Tablet', 'Oral', '6809');

PRINT 'Healthcare database schema created successfully!';
GO
