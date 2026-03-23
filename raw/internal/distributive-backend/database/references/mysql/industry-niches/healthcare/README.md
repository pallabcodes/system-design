# Healthcare Platform Database Design

## Overview

This comprehensive database schema supports modern healthcare information systems including Electronic Health Records (EHR), patient management, clinical workflows, medical billing, and comprehensive compliance with HIPAA and other healthcare regulations. The design handles complex clinical data, regulatory reporting, interoperability standards, and enterprise scalability.

## Key Features

### 🏥 Electronic Health Records (EHR)
- **Comprehensive patient records** with medical history, allergies, medications, and treatments
- **Clinical documentation** supporting various care settings and specialties
- **Structured and unstructured data** handling for complete patient information
- **Longitudinal patient records** across care continuum

### 👥 Patient Management & Care Coordination
- **Patient demographics and identifiers** with privacy protection
- **Care team coordination** across multiple providers and specialties
- **Appointment scheduling and resource management**
- **Patient engagement and communication** tools

### 📊 Clinical Analytics & Reporting
- **Quality metrics and performance indicators** for care quality assessment
- **Population health analytics** for preventive care and outcomes
- **Regulatory reporting** for compliance and accreditation
- **Clinical decision support** with evidence-based guidelines

## Database Schema Highlights

### Core Tables

#### Patient Management
```sql
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
```

#### Provider Management
```sql
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
```

### Clinical Data Management

#### Encounters and Visits
```sql
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
```

#### Diagnoses and Problems
```sql
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
```

#### Medications and Treatments
```sql
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
```

### Advanced Features

#### Clinical Documentation
```sql
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
```

#### Quality Metrics & Analytics
```sql
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
```

## Integration Points

### External Systems
- **Electronic Health Record systems** (Epic, Cerner, Meditech) for comprehensive patient data
- **Laboratory Information Systems** (LIS) for test results and diagnostics
- **Radiology Information Systems** (RIS/PACS) for medical imaging
- **Pharmacy systems** for medication management and dispensing
- **Health Information Exchanges** (HIE) for interoperability
- **Telemedicine platforms** for remote consultations
- **Medical device integrations** for vital signs and monitoring equipment

### API Endpoints
- **HL7 FHIR APIs** for standardized healthcare data exchange
- **Patient management APIs** for demographics, insurance, and medical history
- **Clinical APIs** for appointments, encounters, and treatment plans
- **Billing APIs** for claims processing and insurance verification
- **Reporting APIs** for regulatory compliance and quality metrics
- **Integration APIs** for third-party system connectivity and webhooks

## Monitoring & Analytics

### Key Performance Indicators
- **Patient care quality** (readmission rates, patient satisfaction, treatment outcomes)
- **Operational efficiency** (appointment wait times, resource utilization, staff productivity)
- **Financial performance** (revenue cycle, claim denials, reimbursement rates)
- **Compliance metrics** (audit findings, data breaches, regulatory violations)
- **Clinical outcomes** (infection rates, mortality rates, preventive care measures)

### Real-Time Dashboards
```sql
-- Healthcare operations dashboard
CREATE VIEW HealthcareOperationsDashboard AS
SELECT
    -- Patient care metrics (current month)
    (SELECT COUNT(*) FROM Encounters WHERE DATEPART(MONTH, EncounterDate) = DATEPART(MONTH, GETDATE())
                                         AND DATEPART(YEAR, EncounterDate) = DATEPART(YEAR, GETDATE())) AS EncountersThisMonth,
    (SELECT COUNT(DISTINCT PatientID) FROM Encounters WHERE DATEPART(MONTH, EncounterDate) = DATEPART(MONTH, GETDATE())
                                                       AND DATEPART(YEAR, EncounterDate) = DATEPART(YEAR, GETDATE())) AS UniquePatientsMonth,
    (SELECT AVG(CAST(LengthOfStay AS DECIMAL(10,2))) FROM Encounters
     WHERE LengthOfStay IS NOT NULL
     AND DATEPART(MONTH, EncounterDate) = DATEPART(MONTH, GETDATE())
     AND DATEPART(YEAR, EncounterDate) = DATEPART(YEAR, GETDATE())) AS AvgLengthOfStay,

    -- Appointment metrics
    (SELECT COUNT(*) FROM Encounters WHERE EncounterType = 'OfficeVisit'
                                       AND CAST(EncounterDate AS DATE) = CAST(GETDATE() AS DATE)) AS AppointmentsToday,
    (SELECT COUNT(*) FROM Encounters WHERE EncounterType = 'OfficeVisit'
                                       AND CAST(EncounterDate AS DATE) = CAST(GETDATE() AS DATE)
                                       AND Status = 'Completed') * 100.0 /
     NULLIF((SELECT COUNT(*) FROM Encounters WHERE EncounterType = 'OfficeVisit'
                                              AND CAST(EncounterDate AS DATE) = CAST(GETDATE() AS DATE)), 0) AS AppointmentCompletionRate,

    -- Clinical quality
    (SELECT COUNT(*) FROM PatientProblems WHERE Status = 'Active') AS ActiveProblems,
    (SELECT COUNT(*) FROM Diagnoses WHERE DATEPART(MONTH, DiagnosisDate) = DATEPART(MONTH, GETDATE())
                                      AND DATEPART(YEAR, DiagnosisDate) = DATEPART(YEAR, GETDATE())) AS DiagnosesThisMonth,
    (SELECT COUNT(*) FROM MedicationOrders WHERE Status = 'Active') AS ActiveMedications,

    -- Provider performance
    (SELECT COUNT(DISTINCT ProviderID) FROM Encounters WHERE Status = 'Completed') AS ActiveProviders,
    (SELECT AVG(CAST(LengthOfStay AS DECIMAL(10,2))) FROM Encounters e
     INNER JOIN Providers p ON e.ProviderID = p.ProviderID
     WHERE e.Status = 'Completed'
     AND DATEPART(MONTH, e.EncounterDate) = DATEPART(MONTH, GETDATE())) AS AvgProviderEfficiency,

    -- System health
    (SELECT COUNT(*) FROM ClinicalNotes WHERE IsSigned = 0
                                          AND DATEDIFF(DAY, NoteDate, GETDATE()) > 1) AS UnsignedNotesOver24H,
    (SELECT COUNT(*) FROM Encounters WHERE Status = 'InProgress'
                                       AND DATEDIFF(HOUR, EncounterDate, GETDATE()) > 8) AS LongRunningEncounters

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This healthcare database schema provides a comprehensive foundation for modern healthcare information systems, incorporating regulatory compliance, clinical workflows, and enterprise scalability while maintaining high performance and data integrity.
