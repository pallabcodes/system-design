-- Education Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database with appropriate settings
CREATE DATABASE EducationPlatform
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE EducationPlatform;
GO

-- Enable advanced features
ALTER DATABASE EducationPlatform
SET
    RECOVERY FULL,
    PAGE_VERIFY CHECKSUM,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON;
GO

-- Create filegroups for performance optimization
ALTER DATABASE EducationPlatform
ADD FILEGROUP EducationData;
GO

ALTER DATABASE EducationPlatform
ADD FILE
(
    NAME = 'EducationDataFile',
    FILENAME = 'C:\SQLData\EducationData.ndf',
    SIZE = 100MB,
    FILEGROWTH = 50MB
)
TO FILEGROUP EducationData;
GO

-- =============================================
-- USER MANAGEMENT
-- =============================================

-- Users table with role-based access
CREATE TABLE Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    PasswordHash NVARCHAR(255),
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    Role NVARCHAR(50) NOT NULL CHECK (Role IN ('Student', 'Instructor', 'Admin', 'Parent')),
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastLoginDate DATETIME2,
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),

    -- Indexes
    INDEX IX_Users_Email (Email),
    INDEX IX_Users_Role (Role),
    INDEX IX_Users_IsActive (IsActive),
    INDEX IX_Users_LastLogin (LastLoginDate)
);

-- Student profiles
CREATE TABLE Students (
    StudentID INT PRIMARY KEY REFERENCES Users(UserID) ON DELETE CASCADE,
    StudentNumber NVARCHAR(50) UNIQUE,
    EnrollmentDate DATE,
    GraduationDate DATE,
    AcademicStanding NVARCHAR(50),
    GPA DECIMAL(3,2) CHECK (GPA BETWEEN 0.00 AND 4.00),
    Major NVARCHAR(100),
    AdvisorID INT REFERENCES Users(UserID),
    EmergencyContact NVARCHAR(MAX), -- JSON format

    -- Indexes
    INDEX IX_Students_StudentNumber (StudentNumber),
    INDEX IX_Students_Major (Major),
    INDEX IX_Students_Advisor (AdvisorID),
    INDEX IX_Students_GPA (GPA)
);

-- Instructor profiles
CREATE TABLE Instructors (
    InstructorID INT PRIMARY KEY REFERENCES Users(UserID) ON DELETE CASCADE,
    EmployeeID NVARCHAR(50) UNIQUE,
    Department NVARCHAR(100),
    Title NVARCHAR(100),
    OfficeLocation NVARCHAR(255),
    OfficeHours NVARCHAR(MAX), -- JSON format for complex schedules
    Biography NVARCHAR(MAX),
    Qualifications NVARCHAR(MAX), -- JSON format

    -- Indexes
    INDEX IX_Instructors_EmployeeID (EmployeeID),
    INDEX IX_Instructors_Department (Department)
);

-- =============================================
-- COURSE MANAGEMENT
-- =============================================

-- Courses master table
CREATE TABLE Courses (
    CourseID INT IDENTITY(1,1) PRIMARY KEY,
    CourseCode NVARCHAR(20) UNIQUE NOT NULL,
    CourseName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    Department NVARCHAR(100),
    Credits INT CHECK (Credits > 0),
    DurationWeeks INT CHECK (DurationWeeks > 0),
    DifficultyLevel NVARCHAR(20) CHECK (DifficultyLevel IN ('Beginner', 'Intermediate', 'Advanced')),
    Prerequisites NVARCHAR(MAX), -- JSON array of course IDs
    LearningObjectives NVARCHAR(MAX), -- JSON array
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),

    -- Full-text search
    INDEX IX_Courses_FullText (CourseName, Description) WHERE IsActive = 1,

    -- Indexes
    INDEX IX_Courses_Code (CourseCode),
    INDEX IX_Courses_Department (Department),
    INDEX IX_Courses_IsActive (IsActive)
);

-- Course offerings (specific instances)
CREATE TABLE CourseOfferings (
    OfferingID INT IDENTITY(1,1) PRIMARY KEY,
    CourseID INT NOT NULL REFERENCES Courses(CourseID),
    Semester NVARCHAR(20) NOT NULL,
    Year INT NOT NULL,
    InstructorID INT REFERENCES Instructors(InstructorID),
    MaxEnrollment INT CHECK (MaxEnrollment > 0),
    CurrentEnrollment INT DEFAULT 0 CHECK (CurrentEnrollment >= 0),
    StartDate DATE,
    EndDate DATE,
    Location NVARCHAR(255), -- Physical or virtual
    Status NVARCHAR(20) DEFAULT 'Planned'
        CHECK (Status IN ('Planned', 'Open', 'InProgress', 'Completed', 'Cancelled')),
    Schedule NVARCHAR(MAX), -- JSON format for class schedule

    -- Constraints
    CONSTRAINT CK_CourseOfferings_Dates CHECK (EndDate >= StartDate),
    CONSTRAINT CK_CourseOfferings_Enrollment CHECK (CurrentEnrollment <= MaxEnrollment),

    -- Indexes
    INDEX IX_CourseOfferings_Course (CourseID),
    INDEX IX_CourseOfferings_Instructor (InstructorID),
    INDEX IX_CourseOfferings_Status (Status),
    INDEX IX_CourseOfferings_SemesterYear (Semester, Year),
    INDEX IX_CourseOfferings_Dates (StartDate, EndDate)
);

-- Course modules and lessons
CREATE TABLE CourseModules (
    ModuleID INT IDENTITY(1,1) PRIMARY KEY,
    CourseID INT NOT NULL REFERENCES Courses(CourseID),
    ModuleTitle NVARCHAR(200) NOT NULL,
    ModuleDescription NVARCHAR(MAX),
    SequenceNumber INT NOT NULL,
    IsRequired BIT DEFAULT 1,
    EstimatedHours DECIMAL(4,1) CHECK (EstimatedHours > 0),
    LearningObjectives NVARCHAR(MAX), -- JSON array

    -- Constraints
    CONSTRAINT UQ_CourseModules_Sequence UNIQUE (CourseID, SequenceNumber),

    -- Indexes
    INDEX IX_CourseModules_Course (CourseID),
    INDEX IX_CourseModules_Sequence (SequenceNumber)
);

CREATE TABLE Lessons (
    LessonID INT IDENTITY(1,1) PRIMARY KEY,
    ModuleID INT NOT NULL REFERENCES CourseModules(ModuleID),
    LessonTitle NVARCHAR(200) NOT NULL,
    ContentType NVARCHAR(50) NOT NULL
        CHECK (ContentType IN ('Video', 'Document', 'Quiz', 'Assignment', 'Interactive', 'Discussion')),
    ContentPath NVARCHAR(500),
    SequenceNumber INT NOT NULL,
    DurationMinutes INT CHECK (DurationMinutes > 0),
    IsPreview BIT DEFAULT 0,
    Prerequisites NVARCHAR(MAX), -- JSON array of lesson IDs

    -- Constraints
    CONSTRAINT UQ_Lessons_Sequence UNIQUE (ModuleID, SequenceNumber),

    -- Indexes
    INDEX IX_Lessons_Module (ModuleID),
    INDEX IX_Lessons_Type (ContentType),
    INDEX IX_Lessons_Sequence (SequenceNumber)
);

-- =============================================
-- CONTENT MANAGEMENT
-- =============================================

-- Learning content repository
CREATE TABLE LearningContent (
    ContentID INT IDENTITY(1,1) PRIMARY KEY,
    Title NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    ContentType NVARCHAR(50) NOT NULL,
    ContentPath NVARCHAR(500),
    FileSize BIGINT,
    DurationSeconds INT,
    Tags NVARCHAR(MAX), -- JSON array of tags
    DifficultyLevel NVARCHAR(20) CHECK (DifficultyLevel IN ('Beginner', 'Intermediate', 'Advanced')),
    Language NVARCHAR(10) DEFAULT 'en',
    AccessLevel NVARCHAR(20) DEFAULT 'Public'
        CHECK (AccessLevel IN ('Public', 'Registered', 'Premium', 'Private')),
    CreatedBy INT NOT NULL REFERENCES Users(UserID),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastModifiedDate DATETIME2 DEFAULT GETDATE(),
    IsPublished BIT DEFAULT 0,
    Version NVARCHAR(20) DEFAULT '1.0',

    -- Full-text search
    INDEX IX_LearningContent_FullText (Title, Description, Tags) WHERE IsPublished = 1,

    -- Indexes
    INDEX IX_LearningContent_Type (ContentType),
    INDEX IX_LearningContent_CreatedBy (CreatedBy),
    INDEX IX_LearningContent_IsPublished (IsPublished),
    INDEX IX_LearningContent_AccessLevel (AccessLevel)
);

-- Content versions
CREATE TABLE ContentVersions (
    VersionID INT IDENTITY(1,1) PRIMARY KEY,
    ContentID INT NOT NULL REFERENCES LearningContent(ContentID),
    VersionNumber NVARCHAR(20) NOT NULL,
    ChangeDescription NVARCHAR(MAX),
    ModifiedBy INT NOT NULL REFERENCES Users(UserID),
    ModifiedDate DATETIME2 DEFAULT GETDATE(),
    IsCurrent BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_ContentVersions_Current UNIQUE (ContentID) WHERE IsCurrent = 1,

    -- Indexes
    INDEX IX_ContentVersions_Content (ContentID),
    INDEX IX_ContentVersions_IsCurrent (IsCurrent)
);

-- =============================================
-- STUDENT PROGRESS & ASSESSMENT
-- =============================================

-- Student enrollments
CREATE TABLE Enrollments (
    EnrollmentID INT IDENTITY(1,1) PRIMARY KEY,
    StudentID INT NOT NULL REFERENCES Students(StudentID),
    OfferingID INT NOT NULL REFERENCES CourseOfferings(OfferingID),
    EnrollmentDate DATETIME2 DEFAULT GETDATE(),
    CompletionDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Enrolled'
        CHECK (Status IN ('Enrolled', 'InProgress', 'Completed', 'Withdrawn', 'Failed')),
    Grade NVARCHAR(5),
    GPA DECIMAL(3,2) CHECK (GPA BETWEEN 0.00 AND 4.00),
    ProgressPercentage DECIMAL(5,2) DEFAULT 0.00
        CHECK (ProgressPercentage BETWEEN 0.00 AND 100.00),
    LastAccessedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT UQ_Enrollments_StudentOffering UNIQUE (StudentID, OfferingID),
    CONSTRAINT CK_Enrollments_Completion CHECK (
        (Status IN ('Completed', 'Failed') AND CompletionDate IS NOT NULL) OR
        (Status NOT IN ('Completed', 'Failed') AND CompletionDate IS NULL)
    ),

    -- Indexes
    INDEX IX_Enrollments_Student (StudentID),
    INDEX IX_Enrollments_Offering (OfferingID),
    INDEX IX_Enrollments_Status (Status),
    INDEX IX_Enrollments_Progress (ProgressPercentage)
);

-- Lesson progress tracking
CREATE TABLE LessonProgress (
    ProgressID INT IDENTITY(1,1) PRIMARY KEY,
    EnrollmentID INT NOT NULL REFERENCES Enrollments(EnrollmentID),
    LessonID INT NOT NULL REFERENCES Lessons(LessonID),
    StartedDate DATETIME2 DEFAULT GETDATE(),
    CompletedDate DATETIME2,
    TimeSpentMinutes INT DEFAULT 0,
    CompletionPercentage DECIMAL(5,2) DEFAULT 0.00
        CHECK (CompletionPercentage BETWEEN 0.00 AND 100.00),
    LastAccessedDate DATETIME2 DEFAULT GETDATE(),
    IsCompleted BIT DEFAULT 0,
    Attempts INT DEFAULT 1,

    -- Constraints
    CONSTRAINT UQ_LessonProgress_EnrollmentLesson UNIQUE (EnrollmentID, LessonID),
    CONSTRAINT CK_LessonProgress_Completion CHECK (
        (IsCompleted = 1 AND CompletionPercentage = 100.00 AND CompletedDate IS NOT NULL) OR
        (IsCompleted = 0 AND CompletionPercentage < 100.00)
    ),

    -- Indexes
    INDEX IX_LessonProgress_Enrollment (EnrollmentID),
    INDEX IX_LessonProgress_Lesson (LessonID),
    INDEX IX_LessonProgress_IsCompleted (IsCompleted),
    INDEX IX_LessonProgress_LastAccessed (LastAccessedDate)
);

-- Learning analytics
CREATE TABLE LearningAnalytics (
    AnalyticsID INT IDENTITY(1,1) PRIMARY KEY,
    EnrollmentID INT REFERENCES Enrollments(EnrollmentID),
    LessonID INT REFERENCES Lessons(LessonID),
    EventType NVARCHAR(50) NOT NULL,
    EventTimestamp DATETIME2 DEFAULT GETDATE(),
    DurationSeconds INT,
    UserAgent NVARCHAR(500),
    IPAddress NVARCHAR(45),
    DeviceType NVARCHAR(50),
    Location NVARCHAR(100),
    SessionID UNIQUEIDENTIFIER DEFAULT NEWID(),

    -- Indexes
    INDEX IX_LearningAnalytics_Enrollment (EnrollmentID),
    INDEX IX_LearningAnalytics_EventType (EventType),
    INDEX IX_LearningAnalytics_Timestamp (EventTimestamp),
    INDEX IX_LearningAnalytics_Session (SessionID)
);

-- =============================================
-- ASSESSMENT SYSTEM
-- =============================================

-- Assessments and quizzes
CREATE TABLE Assessments (
    AssessmentID INT IDENTITY(1,1) PRIMARY KEY,
    CourseID INT REFERENCES Courses(CourseID),
    ModuleID INT REFERENCES CourseModules(ModuleID),
    AssessmentTitle NVARCHAR(200) NOT NULL,
    AssessmentType NVARCHAR(50) NOT NULL
        CHECK (AssessmentType IN ('Quiz', 'Exam', 'Assignment', 'Project', 'Discussion')),
    Description NVARCHAR(MAX),
    TotalPoints DECIMAL(6,2) DEFAULT 100.00,
    PassingScore DECIMAL(5,2) DEFAULT 60.00,
    TimeLimitMinutes INT,
    AttemptsAllowed INT DEFAULT 1,
    IsGraded BIT DEFAULT 1,
    IsTimed BIT DEFAULT 0,
    ShuffleQuestions BIT DEFAULT 0,
    ShowAnswersAfter BIT DEFAULT 0,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    DueDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_Assessments_Points CHECK (TotalPoints > 0),
    CONSTRAINT CK_Assessments_Passing CHECK (PassingScore BETWEEN 0 AND TotalPoints),

    -- Indexes
    INDEX IX_Assessments_Course (CourseID),
    INDEX IX_Assessments_Module (ModuleID),
    INDEX IX_Assessments_Type (AssessmentType),
    INDEX IX_Assessments_DueDate (DueDate)
);

-- Questions and answers
CREATE TABLE Questions (
    QuestionID INT IDENTITY(1,1) PRIMARY KEY,
    AssessmentID INT NOT NULL REFERENCES Assessments(AssessmentID),
    QuestionText NVARCHAR(MAX) NOT NULL,
    QuestionType NVARCHAR(50) NOT NULL
        CHECK (QuestionType IN ('MultipleChoice', 'TrueFalse', 'Essay', 'ShortAnswer', 'Matching')),
    Points DECIMAL(5,2) DEFAULT 1.00,
    SequenceNumber INT NOT NULL,
    CorrectAnswer NVARCHAR(MAX), -- JSON for complex answers
    Explanation NVARCHAR(MAX),
    Hints NVARCHAR(MAX), -- JSON array
    Difficulty NVARCHAR(20) DEFAULT 'Medium'
        CHECK (Difficulty IN ('Easy', 'Medium', 'Hard')),

    -- Constraints
    CONSTRAINT CK_Questions_Points CHECK (Points > 0),
    CONSTRAINT UQ_Questions_Sequence UNIQUE (AssessmentID, SequenceNumber),

    -- Indexes
    INDEX IX_Questions_Assessment (AssessmentID),
    INDEX IX_Questions_Type (QuestionType),
    INDEX IX_Questions_Difficulty (Difficulty)
);

-- Answer options for multiple choice
CREATE TABLE AnswerOptions (
    OptionID INT IDENTITY(1,1) PRIMARY KEY,
    QuestionID INT NOT NULL REFERENCES Questions(QuestionID),
    OptionText NVARCHAR(MAX) NOT NULL,
    IsCorrect BIT DEFAULT 0,
    SequenceNumber INT NOT NULL,

    -- Constraints
    CONSTRAINT UQ_AnswerOptions_Sequence UNIQUE (QuestionID, SequenceNumber),

    -- Indexes
    INDEX IX_AnswerOptions_Question (QuestionID),
    INDEX IX_AnswerOptions_IsCorrect (IsCorrect)
);

-- Assessment attempts
CREATE TABLE AssessmentAttempts (
    AttemptID INT IDENTITY(1,1) PRIMARY KEY,
    AssessmentID INT NOT NULL REFERENCES Assessments(AssessmentID),
    StudentID INT NOT NULL REFERENCES Students(StudentID),
    AttemptNumber INT NOT NULL DEFAULT 1,
    StartedDate DATETIME2 DEFAULT GETDATE(),
    SubmittedDate DATETIME2,
    TotalScore DECIMAL(6,2),
    PassingScore DECIMAL(5,2),
    IsPassed BIT,
    TimeSpentMinutes INT,
    Status NVARCHAR(20) DEFAULT 'InProgress'
        CHECK (Status IN ('InProgress', 'Submitted', 'Graded', 'Expired')),

    -- Constraints
    CONSTRAINT UQ_AssessmentAttempts_StudentAssessment UNIQUE (AssessmentID, StudentID, AttemptNumber),

    -- Indexes
    INDEX IX_AssessmentAttempts_Assessment (AssessmentID),
    INDEX IX_AssessmentAttempts_Student (StudentID),
    INDEX IX_AssessmentAttempts_Status (Status),
    INDEX IX_AssessmentAttempts_Submitted (SubmittedDate)
);

-- Attempt answers
CREATE TABLE AttemptAnswers (
    AnswerID INT IDENTITY(1,1) PRIMARY KEY,
    AttemptID INT NOT NULL REFERENCES AssessmentAttempts(AttemptID),
    QuestionID INT NOT NULL REFERENCES Questions(QuestionID),
    AnswerText NVARCHAR(MAX),
    IsCorrect BIT,
    PointsEarned DECIMAL(5,2) DEFAULT 0,
    AnsweredDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT UQ_AttemptAnswers_AttemptQuestion UNIQUE (AttemptID, QuestionID),

    -- Indexes
    INDEX IX_AttemptAnswers_Attempt (AttemptID),
    INDEX IX_AttemptAnswers_Question (QuestionID),
    INDEX IX_AttemptAnswers_IsCorrect (IsCorrect)
);

-- =============================================
-- CERTIFICATION & COMPLIANCE
-- =============================================

-- Certification templates
CREATE TABLE Certifications (
    CertificationID INT IDENTITY(1,1) PRIMARY KEY,
    CertificationName NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    IssuingAuthority NVARCHAR(200),
    ValidityMonths INT,
    Prerequisites NVARCHAR(MAX), -- JSON requirements
    Skills NVARCHAR(MAX), -- JSON array
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Indexes
    INDEX IX_Certifications_Authority (IssuingAuthority)
);

-- Student certifications
CREATE TABLE StudentCertifications (
    StudentCertID INT IDENTITY(1,1) PRIMARY KEY,
    StudentID INT NOT NULL REFERENCES Students(StudentID),
    CertificationID INT NOT NULL REFERENCES Certifications(CertificationID),
    IssueDate DATETIME2 DEFAULT GETDATE(),
    ExpiryDate DATETIME2,
    CertificateNumber NVARCHAR(100) UNIQUE,
    VerificationCode NVARCHAR(100) UNIQUE,
    Status NVARCHAR(20) DEFAULT 'Active'
        CHECK (Status IN ('Active', 'Expired', 'Revoked')),

    -- Constraints
    CONSTRAINT CK_StudentCertifications_Expiry CHECK (ExpiryDate > IssueDate),

    -- Indexes
    INDEX IX_StudentCertifications_Student (StudentID),
    INDEX IX_StudentCertifications_Cert (CertificationID),
    INDEX IX_StudentCertifications_Status (Status),
    INDEX IX_StudentCertifications_Expiry (ExpiryDate)
);

-- =============================================
-- INDEXES AND CONSTRAINTS
-- =============================================

-- Create clustered indexes on primary keys (already done with PRIMARY KEY)

-- Additional non-clustered indexes for performance
CREATE INDEX IX_Enrollments_Composite ON Enrollments (StudentID, Status, EnrollmentDate);
CREATE INDEX IX_LessonProgress_Performance ON LessonProgress (EnrollmentID, IsCompleted, LastAccessedDate);
CREATE INDEX IX_AssessmentAttempts_Performance ON AssessmentAttempts (AssessmentID, Status, SubmittedDate);

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update enrollment progress trigger
CREATE TRIGGER TR_UpdateEnrollmentProgress
ON LessonProgress
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Update enrollment progress percentage
    UPDATE e
    SET e.ProgressPercentage = (
        SELECT CAST(SUM(lp.CompletionPercentage) / COUNT(*) AS DECIMAL(5,2))
        FROM LessonProgress lp
        INNER JOIN Lessons l ON lp.LessonID = l.LessonID
        INNER JOIN CourseModules cm ON l.ModuleID = cm.ModuleID
        INNER JOIN CourseOfferings co ON cm.CourseID = co.CourseID
        WHERE lp.EnrollmentID = e.EnrollmentID
    ),
    e.LastAccessedDate = GETDATE()
    FROM Enrollments e
    WHERE e.EnrollmentID IN (
        SELECT DISTINCT EnrollmentID FROM inserted
        UNION
        SELECT DISTINCT EnrollmentID FROM deleted
    );
END;
GO

-- Assessment grading trigger
CREATE TRIGGER TR_CalculateAssessmentScore
ON AttemptAnswers
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Recalculate total score for affected attempts
    UPDATE aa
    SET aa.TotalScore = (
        SELECT SUM(PointsEarned)
        FROM AttemptAnswers aa2
        WHERE aa2.AttemptID = aa.AttemptID
    ),
    aa.IsPassed = CASE WHEN (
        SELECT SUM(PointsEarned) / a.TotalPoints * 100
        FROM AttemptAnswers aa2
        CROSS JOIN Assessments a
        WHERE aa2.AttemptID = aa.AttemptID AND a.AssessmentID = aa.AssessmentID
    ) >= a.PassingScore THEN 1 ELSE 0 END
    FROM AssessmentAttempts aa
    INNER JOIN Assessments a ON aa.AssessmentID = a.AssessmentID
    WHERE aa.AttemptID IN (
        SELECT DISTINCT AttemptID FROM inserted
    );
END;
GO

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Student dashboard view
CREATE VIEW vw_StudentDashboard
AS
SELECT
    s.StudentID,
    u.FirstName + ' ' + u.LastName AS StudentName,
    c.CourseName,
    co.Semester,
    co.Year,
    e.Status AS EnrollmentStatus,
    e.ProgressPercentage,
    e.Grade,
    COUNT(DISTINCT lp.LessonID) AS CompletedLessons,
    COUNT(DISTINCT l.LessonID) AS TotalLessons,
    AVG(aa.TotalScore) AS AvgAssessmentScore
FROM Students s
INNER JOIN Users u ON s.StudentID = u.UserID
INNER JOIN Enrollments e ON s.StudentID = e.StudentID
INNER JOIN CourseOfferings co ON e.OfferingID = co.OfferingID
INNER JOIN Courses c ON co.CourseID = c.CourseID
LEFT JOIN LessonProgress lp ON e.EnrollmentID = lp.EnrollmentID AND lp.IsCompleted = 1
LEFT JOIN Lessons l ON l.ModuleID IN (
    SELECT ModuleID FROM CourseModules WHERE CourseID = c.CourseID
)
LEFT JOIN AssessmentAttempts aa ON s.StudentID = aa.StudentID
    AND aa.AssessmentID IN (
        SELECT AssessmentID FROM Assessments WHERE CourseID = c.CourseID
    )
GROUP BY s.StudentID, u.FirstName, u.LastName, c.CourseName, co.Semester, co.Year,
         e.Status, e.ProgressPercentage, e.Grade;
GO

-- Course analytics view
CREATE VIEW vw_CourseAnalytics
AS
SELECT
    c.CourseID,
    c.CourseName,
    c.CourseCode,
    COUNT(DISTINCT co.OfferingID) AS TotalOfferings,
    COUNT(DISTINCT e.StudentID) AS TotalEnrollments,
    AVG(e.ProgressPercentage) AS AvgProgress,
    AVG(e.GPA) AS AvgGPA,
    COUNT(DISTINCT CASE WHEN e.Status = 'Completed' THEN e.StudentID END) AS Completions,
    CAST(COUNT(DISTINCT CASE WHEN e.Status = 'Completed' THEN e.StudentID END) AS DECIMAL(10,2)) /
    NULLIF(COUNT(DISTINCT e.StudentID), 0) * 100 AS CompletionRate
FROM Courses c
LEFT JOIN CourseOfferings co ON c.CourseID = co.CourseID
LEFT JOIN Enrollments e ON co.OfferingID = e.OfferingID
WHERE c.IsActive = 1
GROUP BY c.CourseID, c.CourseName, c.CourseCode;
GO

PRINT 'Education Platform database schema created successfully!';
GO
