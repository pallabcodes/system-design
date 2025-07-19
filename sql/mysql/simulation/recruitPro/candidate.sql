-- Production-grade Candidate table for recruitment system (DeNormalized)
CREATE TABLE IF NOT EXISTS Candidate (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Internal unique identifier for candidate',
    uuid CHAR(36) NOT NULL UNIQUE COMMENT 'External UUID for deduplication and security',
    name VARCHAR(100) NOT NULL COMMENT 'Full name of candidate',
    email VARCHAR(100) NOT NULL UNIQUE COMMENT 'Email address, must be unique',
    phone VARCHAR(15) COMMENT 'Phone number',
    resume TEXT COMMENT 'Resume or CV text',
    status ENUM('applied', 'interviewed', 'hired', 'rejected', 'archived') DEFAULT 'applied' COMMENT 'Current status in recruitment pipeline',
    privacy ENUM('public', 'private', 'internal') DEFAULT 'public' COMMENT 'Privacy setting for candidate profile',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
    INDEX idx_candidate_email (email),
    INDEX idx_candidate_status (status),
    INDEX idx_candidate_created_at (created_at),
    INDEX idx_candidate_status_created_at (status, created_at) -- Composite index for status and created_at
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COMMENT='Stores candidate profiles for recruitment system';


-- Normalized Skills Table
CREATE TABLE IF NOT EXISTS Skill (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique skill identifier',
    name VARCHAR(100) NOT NULL UNIQUE COMMENT 'Skill name',
    category VARCHAR(50) COMMENT 'Skill category (e.g., programming, language)'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Master list of skills';

-- Junction table for Candidate <-> Skill (many-to-many)
CREATE TABLE IF NOT EXISTS CandidateSkill (
    candidate_id BIGINT UNSIGNED NOT NULL COMMENT 'FK to Candidate',
    skill_id INT UNSIGNED NOT NULL COMMENT 'FK to Skill',
    proficiency ENUM('beginner','intermediate','advanced','expert') DEFAULT 'beginner' COMMENT 'Skill proficiency',
    years_experience DECIMAL(4,1) COMMENT 'Years of experience',
    PRIMARY KEY (candidate_id, skill_id),
    FOREIGN KEY (candidate_id) REFERENCES Candidate(id) ON DELETE CASCADE,
    FOREIGN KEY (skill_id) REFERENCES Skill(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Links candidates to their skills';

-- Normalized Education Table
CREATE TABLE IF NOT EXISTS Education (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique education record',
    candidate_id BIGINT UNSIGNED NOT NULL COMMENT 'FK to Candidate',
    institution VARCHAR(100) NOT NULL COMMENT 'School/University name',
    degree VARCHAR(100) COMMENT 'Degree or certification',
    field VARCHAR(100) COMMENT 'Field of study',
    start_year YEAR COMMENT 'Start year',
    end_year YEAR COMMENT 'End year',
    FOREIGN KEY (candidate_id) REFERENCES Candidate(id) ON DELETE CASCADE,
    INDEX idx_education_institution_start (institution, start_year) -- Composite index for institution and start_year
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Candidate education history';

-- Normalized Experience Table
CREATE TABLE IF NOT EXISTS Experience (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique experience record',
    candidate_id BIGINT UNSIGNED NOT NULL COMMENT 'FK to Candidate',
    company VARCHAR(100) NOT NULL COMMENT 'Company name',
    title VARCHAR(100) NOT NULL COMMENT 'Job title',
    start_date DATE COMMENT 'Start date',
    end_date DATE COMMENT 'End date',
    description TEXT COMMENT 'Role description',
    FOREIGN KEY (candidate_id) REFERENCES Candidate(id) ON DELETE CASCADE,
    INDEX idx_experience_company_start (company, start_date) -- Composite index for company and start_date
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Candidate work experience';


-- Production-grade Employers/Clients table
CREATE TABLE IF NOT EXISTS Employer (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Internal unique identifier for employer/client',
    uuid CHAR(36) NOT NULL UNIQUE COMMENT 'External UUID for deduplication and security',
    name VARCHAR(100) NOT NULL UNIQUE COMMENT 'Employer name (e.g., Google, Stripe)',
    industry VARCHAR(100) COMMENT 'Industry sector',
    location VARCHAR(100) COMMENT 'Headquarters or main location',
    website VARCHAR(255) COMMENT 'Company website',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
    INDEX idx_employer_name (name),
    INDEX idx_employer_industry (industry)
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COMMENT='Stores employer/client profiles for recruitment system';


-- Production-grade Job table
CREATE TABLE IF NOT EXISTS Job (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Internal unique identifier for job',
    uuid CHAR(36) NOT NULL UNIQUE COMMENT 'External UUID for deduplication and security',
    employer_id BIGINT UNSIGNED NOT NULL COMMENT 'FK to Employer',
    title VARCHAR(100) NOT NULL COMMENT 'Job title',
    description TEXT COMMENT 'Detailed job description',
    location VARCHAR(100) COMMENT 'Job location',
    salary_min DECIMAL(12,2) COMMENT 'Minimum salary',
    salary_max DECIMAL(12,2) COMMENT 'Maximum salary',
    status ENUM('open', 'closed', 'paused', 'filled') DEFAULT 'open' COMMENT 'Job status',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
    INDEX idx_job_title (title),
    INDEX idx_job_status (status),
    INDEX idx_job_location (location),
    INDEX idx_job_status_created_at (status, created_at), -- Composite index for status and created_at
    FOREIGN KEY (employer_id) REFERENCES Employer(id) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COMMENT='Stores job postings for recruitment system';


-- Production-grade Application table
CREATE TABLE IF NOT EXISTS Application (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Internal unique identifier for application',
    uuid CHAR(36) NOT NULL UNIQUE COMMENT 'External UUID for deduplication and security',
    candidate_id BIGINT UNSIGNED NOT NULL COMMENT 'FK to Candidate',
    job_id BIGINT UNSIGNED NOT NULL COMMENT 'FK to Job',
    recruiter_id BIGINT UNSIGNED COMMENT 'FK to Recruiter (optional)',
    status ENUM('applied', 'screening', 'interview', 'offered', 'hired', 'rejected', 'withdrawn') DEFAULT 'applied' COMMENT 'Current status of application',
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Application submission timestamp',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
    INDEX idx_application_status (status),
    INDEX idx_application_applied_at (applied_at),
    INDEX idx_application_status_created_at (status, applied_at), -- Composite index for status and created_at
    FOREIGN KEY (candidate_id) REFERENCES Candidate(id) ON DELETE CASCADE,
    FOREIGN KEY (job_id) REFERENCES Job(id) ON DELETE CASCADE
    -- recruiter_id FK can be added after Recruiter table is defined
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COMMENT='Tracks candidate applications to jobs';


-- Production-grade Recruiter table
CREATE TABLE IF NOT EXISTS Recruiter (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Internal unique identifier for recruiter',
    uuid CHAR(36) NOT NULL UNIQUE COMMENT 'External UUID for deduplication and security',
    name VARCHAR(100) NOT NULL COMMENT 'Recruiter full name',
    email VARCHAR(100) NOT NULL UNIQUE COMMENT 'Recruiter email address',
    phone VARCHAR(15) COMMENT 'Recruiter phone number',
    status ENUM('active', 'inactive', 'archived') DEFAULT 'active' COMMENT 'Recruiter account status',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
    INDEX idx_recruiter_email (email),
    INDEX idx_recruiter_status (status)
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COMMENT='Stores recruiter profiles for recruitment system';


-- Production-grade Interview table
CREATE TABLE IF NOT EXISTS Interview (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Internal unique identifier for interview',
    uuid CHAR(36) NOT NULL UNIQUE COMMENT 'External UUID for deduplication and security',
    application_id BIGINT UNSIGNED NOT NULL COMMENT 'FK to Application',
    recruiter_id BIGINT UNSIGNED COMMENT 'FK to Recruiter (optional)',
    scheduled_at DATETIME NOT NULL COMMENT 'Scheduled date and time for interview',
    feedback TEXT COMMENT 'Feedback from interview',
    status ENUM('scheduled', 'completed', 'cancelled', 'no_show') DEFAULT 'scheduled' COMMENT 'Interview status',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
    INDEX idx_interview_status (status),
    INDEX idx_interview_scheduled_at (scheduled_at),
    FOREIGN KEY (application_id) REFERENCES Application(id) ON DELETE CASCADE
    -- recruiter_id FK can be added after Recruiter table is defined
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COMMENT='Tracks interviews for candidate applications';


-- Production-grade Offer table
CREATE TABLE IF NOT EXISTS Offer (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Internal unique identifier for offer',
    uuid CHAR(36) NOT NULL UNIQUE COMMENT 'External UUID for deduplication and security',
    application_id BIGINT UNSIGNED NOT NULL COMMENT 'FK to Application',
    salary DECIMAL(12,2) NOT NULL COMMENT 'Offered salary',
    benefits TEXT COMMENT 'Benefits offered',
    status ENUM('extended', 'accepted', 'declined', 'expired', 'withdrawn') DEFAULT 'extended' COMMENT 'Offer status',
    extended_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Offer extension timestamp',
    responded_at TIMESTAMP NULL COMMENT 'Timestamp of candidate response',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
    INDEX idx_offer_status (status),
    INDEX idx_offer_extended_at (extended_at),
    FOREIGN KEY (application_id) REFERENCES Application(id) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COMMENT='Tracks job offers extended to candidates';


-- Production-grade Event/Audit table
CREATE TABLE IF NOT EXISTS Event (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Internal unique identifier for event',
    uuid CHAR(36) NOT NULL UNIQUE COMMENT 'External UUID for deduplication and security',
    entity_type ENUM('candidate', 'employer', 'job', 'application', 'recruiter', 'interview', 'offer') NOT NULL COMMENT 'Type of entity affected',
    entity_id BIGINT UNSIGNED NOT NULL COMMENT 'ID of the affected entity',
    action VARCHAR(50) NOT NULL COMMENT 'Action performed (e.g., create, update, delete)',
    performed_by BIGINT UNSIGNED COMMENT 'User/Recruiter who performed the action',
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Timestamp of the event',
    details TEXT COMMENT 'Additional details or JSON payload',
    INDEX idx_event_entity_type (entity_type),
    INDEX idx_event_performed_at (performed_at),
    INDEX idx_event_status_performed_at (entity_type, performed_at) -- Composite index for status and performed_at
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COMMENT='Tracks audit events and changes for compliance and debugging';


-- Reference table for status values (example for extensibility/localization)
CREATE TABLE IF NOT EXISTS Status (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique status identifier',
    entity_type ENUM('candidate', 'job', 'application', 'recruiter', 'interview', 'offer') NOT NULL COMMENT 'Type of entity',
    code VARCHAR(50) NOT NULL COMMENT 'Status code (e.g., applied, hired)',
    label VARCHAR(100) NOT NULL COMMENT 'Human-readable label',
    description TEXT COMMENT 'Description or localization',
    UNIQUE KEY uniq_status_entity_code (entity_type, code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Reference table for status values, extensible and localizable';


-- Resume

-- Store as TEXT or as a reference to a file/blob storage. If storing structured data (e.g., parsed sections), consider additional tables.

-- Status/Privacy

-- ENUM is fine for limited, well-defined values. If values may change or need localization, use reference tables


-- Why Normalize?
-- Avoids redundancy: No repeated skill/education/experience data.
-- Ensures consistency: Skills/education can be updated in one place.
-- Supports complex queries: E.g., find all candidates with “Python” skill.
-- Scales for future: Easy to add new attributes or relationships.