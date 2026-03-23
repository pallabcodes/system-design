# Healthcare / EHR: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Patients, Encounters, Clinical Notes, Medications, Lab Results, HIPAA Compliance — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Exposing PHI (Protected Health Information) without audit logging. Every access to patient data MUST be logged. HIPAA violations = $50K+ per incident.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html) | Compliance requirements |
| [HL7 FHIR](https://www.hl7.org/fhir/) | Healthcare data interoperability |
| [Epic Architecture](https://www.epic.com/) | Industry-leading EHR |

---

## 🎯 The Principal Laws of Healthcare Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Audit Everything** | Every PHI access logged | HIPAA requires 6-year retention |
| **Law 2: Role-Based Access** | Clinicians see different data | Provider type determines visibility |
| **Law 3: Data Never Deleted** | Medical records kept 7+ years | Soft delete, archive |
| **Law 4: Temporal Is Critical** | When was diagnosis made? | effectiveDate on everything |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Get patient demographics | 10M/s | < 50ms | PostgreSQL + Cache |
| 2 | Get patient encounter history | 5M/s | < 100ms | PostgreSQL |
| 3 | Get medications list | 5M/s | < 50ms | PostgreSQL |
| 4 | Search patients | 1M/s | < 200ms | Elasticsearch |
| 5 | Create clinical note | 500K/s | < 500ms | PostgreSQL |
| 6 | Get lab results | 2M/s | < 100ms | PostgreSQL |
| 7 | Check allergies | 1M/s | < 20ms | Cache + PostgreSQL |
| 8 | Schedule appointment | 500K/s | < 500ms | PostgreSQL |
| 9 | Verify insurance eligibility | 100K/s | < 2s | External API |
| 10 | Audit log query | 10K/s | < 1s | PostgreSQL (partitioned) |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    HEALTHCARE DATA ARCHITECTURE                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL (Primary)                     │
│  ✓ HIPAA compliant    ✓ Audit trail   ✓ Row-level security     │
│                                                                  │
│  • patients, patient_identifiers                                 │
│  • encounters, diagnoses                                         │
│  • medications, allergies                                        │
│  • lab_orders, lab_results                                       │
│  • clinical_notes, orders                                        │
│  • appointments, providers                                       │
│  • phi_access_log (audit)                                        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Session cache    ✓ Allergy alerts   ✓ Drug interactions      │
│                                                                  │
│  • patient_allergies:{mrn}                                       │
│  • provider_context:{session_id}                                 │
│  • drug_interactions (lookup)                                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Elasticsearch                            │
│  ✓ Patient search    ✓ Clinical note search                     │
│                                                                  │
│  • patients (name, DOB, MRN, SSN-last4)                          │
│  • clinical_notes (full-text)                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- HEALTHCARE/EHR SCHEMA: PostgreSQL Production DDL
-- Version: HIPAA-compliant EHR with audit logging
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enable row-level security
ALTER DATABASE current_database SET row_security = on;


-- ===========================================
-- SECTION 1: ORGANIZATIONS AND FACILITIES
-- ===========================================

CREATE TABLE organizations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(255) NOT NULL,
    npi                 VARCHAR(10),  -- National Provider Identifier
    tax_id              VARCHAR(20),
    
    address_line1       VARCHAR(255),
    city                VARCHAR(100),
    state               VARCHAR(2),
    zip_code            VARCHAR(10),
    
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE facilities (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id     UUID NOT NULL REFERENCES organizations(id),
    
    name                VARCHAR(255) NOT NULL,
    facility_type       VARCHAR(50),  -- 'hospital', 'clinic', 'lab', 'pharmacy'
    
    address_line1       VARCHAR(255),
    city                VARCHAR(100),
    state               VARCHAR(2),
    zip_code            VARCHAR(10),
    phone               VARCHAR(20),
    
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_facilities_org ON facilities(organization_id);


-- ===========================================
-- SECTION 2: PROVIDERS (Doctors, Nurses, etc.)
-- ===========================================

CREATE TYPE provider_type AS ENUM (
    'physician', 'nurse_practitioner', 'physician_assistant',
    'registered_nurse', 'medical_assistant', 'pharmacist', 'lab_tech'
);

CREATE TABLE providers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id     UUID NOT NULL REFERENCES organizations(id),
    
    -- Identity
    npi                 VARCHAR(10) UNIQUE,  -- National Provider Identifier
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    credentials         VARCHAR(50),  -- 'MD', 'DO', 'NP', 'PA'
    
    provider_type       provider_type NOT NULL,
    specialty           VARCHAR(100),
    
    -- Contact
    email               VARCHAR(255),
    phone               VARCHAR(20),
    
    -- Auth (linked to user system)
    user_id             UUID,
    
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_providers_org ON providers(organization_id);
CREATE INDEX idx_providers_npi ON providers(npi);


-- ===========================================
-- SECTION 3: PATIENTS
-- ===========================================

CREATE TYPE gender AS ENUM ('male', 'female', 'other', 'unknown');
CREATE TYPE patient_status AS ENUM ('active', 'inactive', 'deceased');

CREATE TABLE patients (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id     UUID NOT NULL REFERENCES organizations(id),
    
    -- Medical Record Number (internal)
    mrn                 VARCHAR(20) NOT NULL,
    
    -- Demographics
    first_name          VARCHAR(100) NOT NULL,
    middle_name         VARCHAR(100),
    last_name           VARCHAR(100) NOT NULL,
    date_of_birth       DATE NOT NULL,
    gender              gender,
    
    -- SSN (encrypted at rest)
    ssn_encrypted       BYTEA,
    ssn_last4           VARCHAR(4),
    
    -- Contact
    phone_home          VARCHAR(20),
    phone_mobile        VARCHAR(20),
    email               VARCHAR(255),
    
    -- Address
    address_line1       VARCHAR(255),
    address_line2       VARCHAR(255),
    city                VARCHAR(100),
    state               VARCHAR(2),
    zip_code            VARCHAR(10),
    
    -- Emergency contact
    emergency_contact_name  VARCHAR(255),
    emergency_contact_phone VARCHAR(20),
    emergency_contact_relationship VARCHAR(50),
    
    -- Primary care
    primary_provider_id UUID REFERENCES providers(id),
    
    -- Status
    status              patient_status DEFAULT 'active',
    deceased_at         TIMESTAMP WITH TIME ZONE,
    
    -- Language preference
    preferred_language  VARCHAR(10) DEFAULT 'en',
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_patient_mrn UNIQUE (organization_id, mrn)
);

CREATE INDEX idx_patients_org ON patients(organization_id);
CREATE INDEX idx_patients_name ON patients(last_name, first_name);
CREATE INDEX idx_patients_dob ON patients(date_of_birth);
CREATE INDEX idx_patients_ssn ON patients(ssn_last4) WHERE ssn_last4 IS NOT NULL;


-- Patient identifiers (insurance IDs, etc.)
CREATE TABLE patient_identifiers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id          UUID NOT NULL REFERENCES patients(id),
    
    identifier_type     VARCHAR(50) NOT NULL,  -- 'insurance', 'drivers_license', 'passport'
    identifier_value    VARCHAR(100) NOT NULL,
    issuer              VARCHAR(255),
    
    effective_date      DATE,
    expiration_date     DATE,
    
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_identifiers_patient ON patient_identifiers(patient_id);
CREATE INDEX idx_identifiers_value ON patient_identifiers(identifier_type, identifier_value);


-- ===========================================
-- SECTION 4: ENCOUNTERS (Visits)
-- ===========================================

CREATE TYPE encounter_type AS ENUM (
    'inpatient', 'outpatient', 'emergency', 'observation',
    'telehealth', 'home_health', 'office_visit'
);

CREATE TYPE encounter_status AS ENUM (
    'planned', 'in_progress', 'completed', 'cancelled', 'no_show'
);

CREATE TABLE encounters (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id          UUID NOT NULL REFERENCES patients(id),
    facility_id         UUID NOT NULL REFERENCES facilities(id),
    
    -- Encounter number
    encounter_number    VARCHAR(30) NOT NULL UNIQUE,
    
    encounter_type      encounter_type NOT NULL,
    status              encounter_status DEFAULT 'planned',
    
    -- Providers
    attending_provider_id   UUID REFERENCES providers(id),
    admitting_provider_id   UUID REFERENCES providers(id),
    
    -- Timing
    admission_date      TIMESTAMP WITH TIME ZONE,
    discharge_date      TIMESTAMP WITH TIME ZONE,
    
    -- Location
    room_number         VARCHAR(20),
    bed_number          VARCHAR(20),
    
    -- Chief complaint
    chief_complaint     TEXT,
    
    -- Disposition
    discharge_disposition VARCHAR(50),  -- 'home', 'snf', 'rehab', 'expired'
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_encounters_patient ON encounters(patient_id);
CREATE INDEX idx_encounters_facility ON encounters(facility_id);
CREATE INDEX idx_encounters_date ON encounters(admission_date DESC);
CREATE INDEX idx_encounters_provider ON encounters(attending_provider_id);


-- ===========================================
-- SECTION 5: DIAGNOSES (ICD-10 Codes)
-- ===========================================

CREATE TABLE diagnoses (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id          UUID NOT NULL REFERENCES patients(id),
    encounter_id        UUID REFERENCES encounters(id),
    
    -- ICD-10 code
    icd10_code          VARCHAR(10) NOT NULL,
    description         TEXT NOT NULL,
    
    -- Type
    diagnosis_type      VARCHAR(20) DEFAULT 'secondary',  -- 'principal', 'secondary', 'admitting'
    
    -- Status
    status              VARCHAR(20) DEFAULT 'active',  -- 'active', 'resolved', 'inactive'
    
    -- Timing
    onset_date          DATE,
    resolved_date       DATE,
    
    -- Provider who made diagnosis
    diagnosed_by        UUID REFERENCES providers(id),
    diagnosed_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_diagnoses_patient ON diagnoses(patient_id);
CREATE INDEX idx_diagnoses_encounter ON diagnoses(encounter_id);
CREATE INDEX idx_diagnoses_code ON diagnoses(icd10_code);


-- ===========================================
-- SECTION 6: MEDICATIONS
-- ===========================================

CREATE TYPE medication_status AS ENUM (
    'active', 'completed', 'discontinued', 'on_hold', 'cancelled'
);

CREATE TABLE medications (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id          UUID NOT NULL REFERENCES patients(id),
    encounter_id        UUID REFERENCES encounters(id),
    
    -- Drug info (RxNorm)
    rxnorm_code         VARCHAR(20),
    ndc_code            VARCHAR(20),  -- National Drug Code
    medication_name     VARCHAR(255) NOT NULL,
    generic_name        VARCHAR(255),
    
    -- Dosage
    dose_amount         DECIMAL(10,3),
    dose_unit           VARCHAR(20),  -- 'mg', 'ml', 'units'
    route               VARCHAR(50),  -- 'oral', 'IV', 'topical'
    frequency           VARCHAR(100), -- 'BID', 'TID', 'PRN'
    
    -- Duration
    start_date          DATE NOT NULL,
    end_date            DATE,
    
    -- Status
    status              medication_status DEFAULT 'active',
    
    -- Prescriber
    prescribed_by       UUID REFERENCES providers(id),
    
    -- Pharmacy
    dispense_quantity   INT,
    refills_authorized  INT DEFAULT 0,
    refills_remaining   INT DEFAULT 0,
    
    -- Special instructions
    sig                 TEXT,  -- Prescription directions
    notes               TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_medications_patient ON medications(patient_id);
CREATE INDEX idx_medications_active ON medications(patient_id, status) WHERE status = 'active';


-- ===========================================
-- SECTION 7: ALLERGIES
-- ===========================================

CREATE TYPE allergy_severity AS ENUM ('mild', 'moderate', 'severe', 'life_threatening');
CREATE TYPE allergy_type AS ENUM ('drug', 'food', 'environmental', 'other');

CREATE TABLE allergies (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id          UUID NOT NULL REFERENCES patients(id),
    
    allergy_type        allergy_type NOT NULL,
    
    -- Allergen
    allergen_name       VARCHAR(255) NOT NULL,
    rxnorm_code         VARCHAR(20),  -- For drug allergies
    
    -- Reaction
    reaction            TEXT,
    severity            allergy_severity,
    
    -- Status
    status              VARCHAR(20) DEFAULT 'active',  -- 'active', 'inactive', 'resolved'
    
    -- Verification
    verified            BOOLEAN DEFAULT FALSE,
    verified_by         UUID REFERENCES providers(id),
    verified_at         TIMESTAMP WITH TIME ZONE,
    
    onset_date          DATE,
    recorded_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_allergies_patient ON allergies(patient_id);
CREATE INDEX idx_allergies_active ON allergies(patient_id, status) WHERE status = 'active';


-- ===========================================
-- SECTION 8: LAB RESULTS
-- ===========================================

CREATE TABLE lab_orders (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id          UUID NOT NULL REFERENCES patients(id),
    encounter_id        UUID REFERENCES encounters(id),
    
    -- Order info
    order_number        VARCHAR(30) NOT NULL UNIQUE,
    
    -- LOINC codes for tests ordered
    tests_ordered       JSONB NOT NULL,  -- [{loinc: '2951-2', name: 'Sodium'}]
    
    -- Ordering provider
    ordered_by          UUID REFERENCES providers(id),
    ordered_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Status
    status              VARCHAR(20) DEFAULT 'pending',  -- 'pending', 'in_progress', 'completed', 'cancelled'
    
    -- Priority
    priority            VARCHAR(20) DEFAULT 'routine',  -- 'stat', 'urgent', 'routine'
    
    -- Specimen
    specimen_collected_at TIMESTAMP WITH TIME ZONE,
    specimen_type       VARCHAR(50),  -- 'blood', 'urine', 'csf'
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_lab_orders_patient ON lab_orders(patient_id);
CREATE INDEX idx_lab_orders_encounter ON lab_orders(encounter_id);

CREATE TABLE lab_results (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    lab_order_id        UUID NOT NULL REFERENCES lab_orders(id),
    patient_id          UUID NOT NULL REFERENCES patients(id),
    
    -- Test identification (LOINC)
    loinc_code          VARCHAR(20) NOT NULL,
    test_name           VARCHAR(255) NOT NULL,
    
    -- Result
    value               VARCHAR(100),
    value_numeric       DECIMAL(15,5),
    unit                VARCHAR(50),
    
    -- Reference range
    reference_low       DECIMAL(15,5),
    reference_high      DECIMAL(15,5),
    reference_text      VARCHAR(255),
    
    -- Interpretation
    abnormal_flag       VARCHAR(10),  -- 'H', 'L', 'HH', 'LL', 'N'
    
    -- Status
    status              VARCHAR(20) DEFAULT 'final',  -- 'preliminary', 'final', 'corrected'
    
    -- Timing
    resulted_at         TIMESTAMP WITH TIME ZONE,
    
    -- Comments
    notes               TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_lab_results_order ON lab_results(lab_order_id);
CREATE INDEX idx_lab_results_patient ON lab_results(patient_id);
CREATE INDEX idx_lab_results_loinc ON lab_results(loinc_code);


-- ===========================================
-- SECTION 9: CLINICAL NOTES
-- ===========================================

CREATE TYPE note_type AS ENUM (
    'progress_note', 'history_physical', 'discharge_summary',
    'operative_note', 'consultation', 'nursing_note', 'procedure_note'
);

CREATE TYPE note_status AS ENUM ('draft', 'signed', 'addended', 'corrected');

CREATE TABLE clinical_notes (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id          UUID NOT NULL REFERENCES patients(id),
    encounter_id        UUID NOT NULL REFERENCES encounters(id),
    
    note_type           note_type NOT NULL,
    status              note_status DEFAULT 'draft',
    
    -- Author
    author_id           UUID NOT NULL REFERENCES providers(id),
    
    -- Content
    title               VARCHAR(255),
    content             TEXT NOT NULL,
    
    -- Structured data
    assessment          TEXT,
    plan                TEXT,
    
    -- Signing
    signed_by           UUID REFERENCES providers(id),
    signed_at           TIMESTAMP WITH TIME ZONE,
    
    -- Amendments
    parent_note_id      UUID REFERENCES clinical_notes(id),
    amendment_reason    TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_notes_patient ON clinical_notes(patient_id);
CREATE INDEX idx_notes_encounter ON clinical_notes(encounter_id);
CREATE INDEX idx_notes_author ON clinical_notes(author_id);
CREATE INDEX idx_notes_type ON clinical_notes(note_type);


-- ===========================================
-- SECTION 10: HIPAA AUDIT LOG (Critical!)
-- ===========================================

CREATE TABLE phi_access_log (
    id                  BIGSERIAL PRIMARY KEY,
    
    -- Who accessed
    user_id             UUID NOT NULL,
    provider_id         UUID,
    user_ip             INET,
    user_agent          TEXT,
    session_id          VARCHAR(100),
    
    -- What was accessed
    patient_id          UUID NOT NULL,
    resource_type       VARCHAR(50) NOT NULL,  -- 'patient', 'encounter', 'medication', 'note'
    resource_id         UUID,
    
    -- Action
    action              VARCHAR(20) NOT NULL,  -- 'view', 'create', 'update', 'print', 'export'
    
    -- Context
    reason              TEXT,  -- Required for "break the glass" access
    facility_id         UUID,
    
    -- Timestamp (immutable)
    accessed_at         TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Query/response size (for detecting bulk downloads)
    response_records    INT
) PARTITION BY RANGE (accessed_at);

-- Keep 6 years of audit logs (HIPAA requirement)
CREATE TABLE phi_access_log_y2024 PARTITION OF phi_access_log
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE INDEX idx_audit_user ON phi_access_log(user_id);
CREATE INDEX idx_audit_patient ON phi_access_log(patient_id);
CREATE INDEX idx_audit_time ON phi_access_log(accessed_at DESC);
CREATE INDEX idx_audit_resource ON phi_access_log(resource_type, resource_id);
```

---

# Part 4: HIPAA Audit Logging Function

```sql
-- Automatically log PHI access
CREATE OR REPLACE FUNCTION log_phi_access(
    p_user_id UUID,
    p_patient_id UUID,
    p_resource_type VARCHAR,
    p_resource_id UUID,
    p_action VARCHAR,
    p_reason TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    INSERT INTO phi_access_log (
        user_id, patient_id, resource_type, resource_id, action, reason
    ) VALUES (
        p_user_id, p_patient_id, p_resource_type, p_resource_id, p_action, p_reason
    );
END;
$$ LANGUAGE plpgsql;

-- Example: Log every patient chart view
-- SELECT log_phi_access(
--     current_user_id(), 
--     '123e4567-e89b-12d3-a456-426614174000',
--     'patient', 
--     '123e4567-e89b-12d3-a456-426614174000',
--     'view',
--     NULL
-- );
```

---

# Part 5: Row-Level Security (HIPAA)

```sql
-- Enable RLS on sensitive tables
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE encounters ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinical_notes ENABLE ROW LEVEL SECURITY;

-- Policy: Providers can only see patients at their facility
CREATE POLICY provider_patient_access ON patients
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM provider_facility_access pfa
            JOIN encounters e ON e.facility_id = pfa.facility_id
            WHERE e.patient_id = patients.id
            AND pfa.provider_id = current_setting('app.current_provider_id')::UUID
        )
        OR
        -- Or if they are the primary provider
        primary_provider_id = current_setting('app.current_provider_id')::UUID
    );

-- "Break the glass" for emergencies
CREATE POLICY emergency_access ON patients
    FOR SELECT
    USING (
        current_setting('app.break_glass', true) = 'true'
    );
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | PHI access audit log | Every view/update logged |
| 2 | 6-year audit retention | Partitioned by year |
| 3 | Row-level security | Providers see only their patients |
| 4 | SSN encrypted | pgcrypto, only last4 searchable |
| 5 | Medical record immutability | Amendments, not updates |
| 6 | Standard codes used | ICD-10, LOINC, RxNorm |
| 7 | Break-the-glass | Emergency access with reason |
| 8 | Temporal data | onset_date, resolved_date everywhere |

---

# Part 6: DynamoDB Single-Table Design

```
============================================================
HEALTHCARE EHR: DynamoDB Single-Table Design
For serverless / global distribution scenarios
============================================================

TABLE: ehr_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK (String) / GSI1SK (String)
- GSI2: GSI2PK (String) / GSI2SK (String)
- GSI3: GSI3PK (String) / GSI3SK (String)

============================================================
ENTITY PATTERNS
============================================================

PATIENT
  PK: ORG#{org_id}#PAT#{patient_id}
  SK: PROFILE
  GSI1PK: ORG#{org_id}#MRN#{mrn}
  GSI1SK: PROFILE
  GSI2PK: ORG#{org_id}#SSN4#{ssn_last4}
  GSI2SK: DOB#{date_of_birth}
  
  Attributes: first_name, last_name, dob, gender, phone, email, address, 
              primary_provider_id, status, created_at

ENCOUNTER
  PK: ORG#{org_id}#PAT#{patient_id}
  SK: ENC#{encounter_id}#META
  GSI1PK: ORG#{org_id}#FAC#{facility_id}
  GSI1SK: DATE#{admission_date}#ENC#{encounter_id}
  GSI2PK: ORG#{org_id}#PROV#{attending_provider_id}
  GSI2SK: DATE#{admission_date}#ENC#{encounter_id}
  
  Attributes: encounter_number, encounter_type, status, admission_date,
              discharge_date, chief_complaint, room, bed

DIAGNOSIS (per encounter)
  PK: ORG#{org_id}#PAT#{patient_id}
  SK: ENC#{encounter_id}#DX#{diagnosis_id}
  GSI1PK: ORG#{org_id}#ICD#{icd10_code}
  GSI1SK: DATE#{diagnosed_at}
  
  Attributes: icd10_code, description, diagnosis_type, status, onset_date

MEDICATION
  PK: ORG#{org_id}#PAT#{patient_id}
  SK: MED#{medication_id}
  GSI1PK: ORG#{org_id}#PAT#{patient_id}#MEDSTATUS#{status}
  GSI1SK: START#{start_date}
  GSI2PK: ORG#{org_id}#RXNORM#{rxnorm_code}
  GSI2SK: DATE#{start_date}
  
  Attributes: rxnorm_code, medication_name, dose, route, frequency, 
              start_date, end_date, status, prescribed_by

ALLERGY
  PK: ORG#{org_id}#PAT#{patient_id}
  SK: ALLERGY#{allergy_id}
  GSI1PK: ORG#{org_id}#PAT#{patient_id}#ALLSTATUS#active
  GSI1SK: SEVERITY#{severity}
  
  Attributes: allergen_name, allergy_type, reaction, severity, status

LAB_ORDER
  PK: ORG#{org_id}#PAT#{patient_id}
  SK: LAB#{lab_order_id}#META
  GSI1PK: ORG#{org_id}#LABORD#{order_number}
  GSI1SK: META
  GSI2PK: ORG#{org_id}#FAC#{facility_id}#LABSTATUS#{status}
  GSI2SK: DATE#{ordered_at}
  
  Attributes: order_number, tests_ordered, status, priority, ordered_by

LAB_RESULT
  PK: ORG#{org_id}#PAT#{patient_id}
  SK: LAB#{lab_order_id}#RESULT#{loinc_code}
  GSI1PK: ORG#{org_id}#LOINC#{loinc_code}
  GSI1SK: DATE#{resulted_at}
  
  Attributes: test_name, value, unit, reference_low, reference_high, 
              abnormal_flag, status

CLINICAL_NOTE
  PK: ORG#{org_id}#PAT#{patient_id}
  SK: ENC#{encounter_id}#NOTE#{note_id}
  GSI1PK: ORG#{org_id}#PROV#{author_id}
  GSI1SK: DATE#{created_at}#NOTE#{note_id}
  
  Attributes: note_type, title, content, status, signed_by, signed_at

PHI_ACCESS_LOG (separate table for compliance)
  PK: AUDIT#{year_month}
  SK: TS#{timestamp}#USER#{user_id}#PAT#{patient_id}
  GSI1PK: USER#{user_id}
  GSI1SK: TS#{timestamp}
  GSI2PK: PAT#{patient_id}
  GSI2SK: TS#{timestamp}
  
  Attributes: action, resource_type, resource_id, reason, ip, session_id

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get patient by MRN
   GSI1: PK=ORG#{org_id}#MRN#{mrn}, SK=PROFILE

2. Get all encounters for patient (last 30 days)
   Table: PK=ORG#{org_id}#PAT#{patient_id}, 
          SK begins_with "ENC#" AND SK contains date >= 30_days_ago

3. Get active medications for patient
   GSI1: PK=ORG#{org_id}#PAT#{patient_id}#MEDSTATUS#active

4. Get all allergies for patient
   Table: PK=ORG#{org_id}#PAT#{patient_id}, SK begins_with "ALLERGY#"

5. Get lab results for patient (by date)
   Table: PK=ORG#{org_id}#PAT#{patient_id}, SK begins_with "LAB#"

6. Get notes by provider (for quality review)
   GSI1: PK=ORG#{org_id}#PROV#{provider_id}, SK begins_with "DATE#"

7. Find patients by ICD-10 code (research)
   GSI1: PK=ORG#{org_id}#ICD#{icd10_code}

8. Audit: All accesses by user
   GSI1: PK=USER#{user_id}, SK between TS#{start} and TS#{end}

9. Audit: All accesses to patient
   GSI2: PK=PAT#{patient_id}, SK between TS#{start} and TS#{end}
```

---

# Part 7: Query Examples with EXPLAIN

```sql
-- ============================================================
-- HEALTHCARE QUERY PATTERNS WITH EXPLAIN ANALYSIS
-- ============================================================

-- ===========================================
-- QUERY 1: Get Patient with Active Medications and Allergies
-- ===========================================

-- Query
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT 
    p.id, p.mrn, p.first_name, p.last_name, p.date_of_birth,
    json_agg(DISTINCT jsonb_build_object(
        'medication', m.medication_name,
        'dose', m.dose_amount || ' ' || m.dose_unit,
        'frequency', m.frequency
    )) FILTER (WHERE m.id IS NOT NULL) AS medications,
    json_agg(DISTINCT jsonb_build_object(
        'allergen', a.allergen_name,
        'severity', a.severity,
        'reaction', a.reaction
    )) FILTER (WHERE a.id IS NOT NULL) AS allergies
FROM patients p
LEFT JOIN medications m ON m.patient_id = p.id AND m.status = 'active'
LEFT JOIN allergies a ON a.patient_id = p.id AND a.status = 'active'
WHERE p.organization_id = $1 AND p.mrn = $2
GROUP BY p.id;

-- Expected Plan (GOOD):
-- Nested Loop Left Join  (cost=4.5..50.2 rows=1 width=500) (actual time=0.5..0.8 ms)
--   ->  Index Scan using uk_patient_mrn on patients p  (cost=0.42..8.44 rows=1)
--         Index Cond: ((organization_id = $1) AND (mrn = $2))
--   ->  Index Scan using idx_medications_active on medications m  (cost=0.42..12.5 rows=5)
--         Index Cond: (patient_id = p.id) AND (status = 'active')
--   ->  Index Scan using idx_allergies_active on allergies a  (cost=0.42..8.5 rows=3)
--         Index Cond: (patient_id = p.id) AND (status = 'active')
-- Planning Time: 0.3 ms
-- Execution Time: 1.2 ms


-- ===========================================
-- QUERY 2: Patient's Complete Chart (Encounter History)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
WITH patient_data AS (
    SELECT id FROM patients 
    WHERE organization_id = $1 AND mrn = $2
)
SELECT 
    e.id AS encounter_id,
    e.encounter_number,
    e.encounter_type,
    e.admission_date,
    e.discharge_date,
    e.chief_complaint,
    prov.first_name || ' ' || prov.last_name AS attending_provider,
    (
        SELECT json_agg(jsonb_build_object(
            'code', d.icd10_code, 
            'description', d.description,
            'type', d.diagnosis_type
        ) ORDER BY d.diagnosis_type)
        FROM diagnoses d WHERE d.encounter_id = e.id
    ) AS diagnoses,
    (
        SELECT COUNT(*) FROM clinical_notes n WHERE n.encounter_id = e.id
    ) AS note_count
FROM patient_data pd
JOIN encounters e ON e.patient_id = pd.id
LEFT JOIN providers prov ON prov.id = e.attending_provider_id
WHERE e.admission_date >= NOW() - INTERVAL '1 year'
ORDER BY e.admission_date DESC
LIMIT 20;

-- Key Index: idx_encounters_patient (patient_id, admission_date DESC)
-- Expected: Index scan on encounters, subquery for diagnoses


-- ===========================================
-- QUERY 3: Drug Interaction Check (Critical Path!)
-- ===========================================

-- Check if new medication conflicts with existing medications
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT 
    m.medication_name AS existing_med,
    di.severity,
    di.interaction_description
FROM medications m
JOIN drug_interactions di ON (
    (di.drug1_rxnorm = m.rxnorm_code AND di.drug2_rxnorm = $2)
    OR 
    (di.drug2_rxnorm = m.rxnorm_code AND di.drug1_rxnorm = $2)
)
WHERE m.patient_id = $1 
  AND m.status = 'active'
  AND di.severity IN ('severe', 'contraindicated');

-- Expected: < 5ms with proper index on drug_interactions(drug1_rxnorm, drug2_rxnorm)


-- ===========================================
-- QUERY 4: Audit Log Query (HIPAA Investigation)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT 
    pal.accessed_at,
    u.email AS user_email,
    pal.action,
    pal.resource_type,
    pal.reason,
    pal.user_ip
FROM phi_access_log pal
JOIN users u ON u.id = pal.user_id
WHERE pal.patient_id = $1
  AND pal.accessed_at BETWEEN $2 AND $3
ORDER BY pal.accessed_at DESC
LIMIT 1000;

-- Expected Plan:
-- Index Scan using idx_audit_patient on phi_access_log_y2024 pal
--   Index Cond: (patient_id = $1)
--   Filter: (accessed_at >= $2 AND accessed_at <= $3)
-- Note: Partition pruning should eliminate irrelevant year partitions


-- ===========================================
-- QUERY 5: Lab Results with Trending (Diabetes Panel)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT 
    lr.loinc_code,
    lr.test_name,
    lr.value_numeric,
    lr.unit,
    lr.abnormal_flag,
    lr.resulted_at,
    lr.reference_low,
    lr.reference_high,
    LAG(lr.value_numeric) OVER (
        PARTITION BY lr.loinc_code 
        ORDER BY lr.resulted_at
    ) AS previous_value
FROM lab_results lr
WHERE lr.patient_id = $1
  AND lr.loinc_code IN (
      '2345-7',   -- Glucose
      '4548-4',   -- HbA1c
      '2160-0',   -- Creatinine
      '33914-3'   -- eGFR
  )
  AND lr.resulted_at >= NOW() - INTERVAL '2 years'
ORDER BY lr.loinc_code, lr.resulted_at DESC;

-- Expected: Bitmap Heap Scan on lab_results with ~2ms execution


-- ===========================================
-- QUERY 6: Provider Workload Dashboard
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT 
    p.id AS provider_id,
    p.first_name || ' ' || p.last_name AS provider_name,
    COUNT(DISTINCT e.id) FILTER (
        WHERE e.admission_date >= CURRENT_DATE
    ) AS today_encounters,
    COUNT(DISTINCT e.id) FILTER (
        WHERE e.status = 'in_progress'
    ) AS active_encounters,
    COUNT(DISTINCT cn.id) FILTER (
        WHERE cn.status = 'draft' AND cn.author_id = p.id
    ) AS unsigned_notes
FROM providers p
LEFT JOIN encounters e ON e.attending_provider_id = p.id
    AND e.admission_date >= CURRENT_DATE - INTERVAL '7 days'
LEFT JOIN clinical_notes cn ON cn.author_id = p.id AND cn.status = 'draft'
WHERE p.organization_id = $1 AND p.is_active = TRUE
GROUP BY p.id, p.first_name, p.last_name
ORDER BY active_encounters DESC;

-- Index needed: idx_encounters_provider_date (attending_provider_id, admission_date DESC)
```

---

# Part 8: Capacity Planning

```
============================================================
HEALTHCARE EHR CAPACITY PLANNING
============================================================

ASSUMPTIONS:
- Mid-size hospital network: 10 facilities
- 500,000 active patients
- 2,000 providers
- 50,000 encounters/month
- 7-year data retention (regulatory)

============================================================
TABLE SIZE ESTIMATES
============================================================

PATIENTS
  Rows: 500,000 active + 1,500,000 historical = 2M
  Row Size: ~800 bytes
  Table Size: 2M × 800B = 1.6 GB
  Indexes: ~500 MB
  Total: ~2.1 GB

ENCOUNTERS
  Rate: 50,000/month × 12 × 7 years = 4.2M
  Row Size: ~600 bytes
  Table Size: 4.2M × 600B = 2.5 GB
  Indexes: ~1 GB
  Total: ~3.5 GB

MEDICATIONS
  Avg 15 medications/patient lifetime
  Rows: 2M patients × 15 = 30M
  Row Size: ~500 bytes
  Table Size: 30M × 500B = 15 GB
  Indexes: ~5 GB
  Total: ~20 GB

LAB_RESULTS
  Avg 50 results/encounter
  Rows: 4.2M encounters × 50 = 210M
  Row Size: ~400 bytes
  Table Size: 210M × 400B = 84 GB
  Indexes: ~30 GB
  Total: ~114 GB

CLINICAL_NOTES
  Avg 3 notes/encounter
  Rows: 4.2M × 3 = 12.6M
  Row Size: ~5 KB (text content)
  Table Size: 12.6M × 5KB = 63 GB
  Indexes: ~10 GB
  Full-text search: ~20 GB
  Total: ~93 GB

PHI_ACCESS_LOG (Audit)
  100 accesses/provider/day × 2000 providers = 200K/day
  200K × 365 × 6 years = 438M rows
  Row Size: ~300 bytes
  Table Size: 438M × 300B = 131 GB
  Indexes: ~50 GB
  Total: ~181 GB (partitioned by year)

============================================================
TOTAL STORAGE REQUIREMENTS
============================================================

| Component | Size | Growth/Year |
|-----------|------|-------------|
| Patients | 2 GB | 100 MB |
| Encounters | 3.5 GB | 500 MB |
| Medications | 20 GB | 2 GB |
| Lab Results | 114 GB | 12 GB |
| Clinical Notes | 93 GB | 10 GB |
| Audit Logs | 181 GB | 22 GB |
| **TOTAL** | **~415 GB** | **~47 GB/year** |

+ 20% overhead (VACUUM, temp) = ~500 GB total
+ Replicas (3x for HA) = 1.5 TB total cluster

============================================================
READ/WRITE CAPACITY
============================================================

PEAK HOURS (7am - 7pm):
  Patient lookups: 1,000/min = 17 QPS
  Chart views: 500/min = 8 QPS
  Medication checks: 300/min = 5 QPS
  Lab result views: 400/min = 7 QPS
  Note saves: 100/min = 2 WPS
  Audit writes: 2,000/min = 33 WPS

TOTAL: ~40 QPS reads, ~35 WPS writes (peak)

CONNECTION POOL:
  2,000 providers × 0.5 concurrent = 1,000 connections max
  Recommended: pgbouncer with 200 real connections
  Mode: transaction pooling

============================================================
SCALING THRESHOLDS
============================================================

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Table > 100GB | > 300GB | Partition by date |
| QPS > 1000 | > 5000 | Add read replicas |
| p99 latency > 100ms | > 500ms | Index analysis |
| Audit table > 50GB/year | > 100GB | Archive to S3 |
| Connection pool > 80% | > 95% | Scale pgbouncer |

============================================================
DYNAMODB CAPACITY (if using)
============================================================

Provisioned Mode:
  RCU (Eventually Consistent): 100 RCU base + burst
  RCU (Strongly Consistent): 200 RCU base + burst
  WCU: 50 WCU base + burst

On-Demand Mode (recommended for variable workloads):
  Pay per request: ~$1.25/million reads, ~$6.25/million writes

GSI Overhead:
  Each GSI adds ~20% to write costs
  With 3 GSIs: 1.6x base WCU
```

---

# Part 9: Anti-Patterns to Avoid

```
============================================================
HEALTHCARE EHR ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Storing PHI in Logs
-----------------------------------------
WRONG:
  logger.info(f"Patient {patient.ssn} accessed by {user}")
  
RIGHT:
  logger.info(f"Patient {patient.id} accessed by {user.id}")
  # SSN, name, DOB, etc. NEVER in application logs
  # Use structured audit table for PHI access


❌ ANTI-PATTERN 2: Deleting Medical Records
-----------------------------------------
WRONG:
  DELETE FROM diagnoses WHERE id = $1;
  
RIGHT:
  UPDATE diagnoses 
  SET status = 'entered_in_error', 
      voided_by = $2, 
      voided_at = NOW(),
      void_reason = $3
  WHERE id = $1;
  -- HIPAA requires 6-7 year retention
  -- Legal discovery may need "deleted" records


❌ ANTI-PATTERN 3: Updating Instead of Amending Notes
-----------------------------------------
WRONG:
  UPDATE clinical_notes SET content = $2 WHERE id = $1;
  
RIGHT:
  -- Original note is immutable once signed
  INSERT INTO clinical_notes (
      parent_note_id, note_type, content, 
      amendment_reason, ...
  ) VALUES ($1, 'addendum', $2, $3, ...);
  -- Maintains complete history for legal purposes


❌ ANTI-PATTERN 4: Missing Audit on Read Operations
-----------------------------------------
WRONG:
  SELECT * FROM patients WHERE mrn = $1;
  -- No audit log entry
  
RIGHT:
  -- Application layer MUST log before returning
  async function getPatient(mrn, userId) {
    await auditLog.logAccess(userId, 'patient', mrn, 'view');
    return db.query('SELECT * FROM patients WHERE mrn = $1', [mrn]);
  }


❌ ANTI-PATTERN 5: Flat Patient Table for All Data
-----------------------------------------
WRONG:
  CREATE TABLE patients (
      id UUID PRIMARY KEY,
      allergy_1 TEXT, allergy_2 TEXT, allergy_3 TEXT,  -- Limited!
      med_1 TEXT, med_2 TEXT, ...  -- Sparse columns
  );
  
RIGHT:
  -- Properly normalized with separate tables
  patients → allergies (1:N)
  patients → medications (1:N)
  patients → encounters → diagnoses (hierarchical)


❌ ANTI-PATTERN 6: No Temporal Tracking
-----------------------------------------
WRONG:
  CREATE TABLE medications (
      id UUID PRIMARY KEY,
      patient_id UUID,
      medication_name TEXT,
      is_active BOOLEAN  -- When did it become inactive? Unknown!
  );
  
RIGHT:
  CREATE TABLE medications (
      id UUID PRIMARY KEY,
      patient_id UUID,
      medication_name TEXT,
      status medication_status,
      start_date DATE NOT NULL,
      end_date DATE,
      discontinued_by UUID,
      discontinued_at TIMESTAMP,
      discontinue_reason TEXT
  );


❌ ANTI-PATTERN 7: Querying Audit Logs Without Partitions
-----------------------------------------
WRONG:
  SELECT * FROM phi_access_log 
  WHERE patient_id = $1 
  ORDER BY accessed_at DESC;
  -- Scans 450M rows!
  
RIGHT:
  SELECT * FROM phi_access_log 
  WHERE patient_id = $1 
    AND accessed_at >= NOW() - INTERVAL '90 days'
  ORDER BY accessed_at DESC;
  -- Partition pruning: only scans 1 partition


❌ ANTI-PATTERN 8: Storing Passwords Without Proper Hashing
-----------------------------------------
WRONG:
  password_hash = hashlib.md5(password).hexdigest()
  
RIGHT:
  password_hash = bcrypt.hashpw(password, bcrypt.gensalt(12))
  # For providers accessing PHI, MFA should be required


❌ ANTI-PATTERN 9: No Break-the-Glass Logging
-----------------------------------------
WRONG:
  -- Emergency access bypasses audit
  SET app.break_glass = 'true';
  SELECT * FROM patients WHERE ...;  -- No record of why!
  
RIGHT:
  -- Break-glass MUST have reason and enhanced logging
  CREATE FUNCTION emergency_access(
      p_user_id UUID,
      p_patient_id UUID,
      p_emergency_reason TEXT  -- Required!
  ) RETURNS patients AS $$
  BEGIN
      INSERT INTO phi_access_log (..., reason, access_type)
      VALUES (..., p_emergency_reason, 'emergency');
      RETURN QUERY SELECT * FROM patients WHERE id = p_patient_id;
  END;
  $$;


❌ ANTI-PATTERN 10: Exposing Internal IDs in URLs
-----------------------------------------
WRONG:
  /patients/123e4567-e89b-12d3-a456-426614174000
  -- UUID exposed, could be used for enumeration
  
RIGHT:
  /patients/MRN-00012345
  -- Use business identifier (MRN) in URLs
  -- Or use opaque tokens: /patients/ptn_aBcD3FgH
```

---

# Part 10: Schema Evolution & Migration

```sql
-- ============================================================
-- HEALTHCARE SCHEMA MIGRATIONS
-- ============================================================

-- ===========================================
-- EXAMPLE 1: Adding new column (safe)
-- ===========================================

-- Step 1: Add nullable column
ALTER TABLE patients 
ADD COLUMN preferred_pharmacy_id UUID;

-- Step 2: Backfill in batches (avoid long locks)
DO $$
DECLARE
    batch_size INT := 10000;
    affected INT := 1;
BEGIN
    WHILE affected > 0 LOOP
        UPDATE patients 
        SET preferred_pharmacy_id = (
            SELECT id FROM pharmacies 
            WHERE pharmacies.zip_code = patients.zip_code 
            LIMIT 1
        )
        WHERE id IN (
            SELECT id FROM patients 
            WHERE preferred_pharmacy_id IS NULL 
            LIMIT batch_size
        );
        GET DIAGNOSTICS affected = ROW_COUNT;
        COMMIT;
        PERFORM pg_sleep(0.1);  -- Avoid lock contention
    END LOOP;
END $$;

-- Step 3: Add constraint (after backfill)
ALTER TABLE patients 
ADD CONSTRAINT fk_preferred_pharmacy 
FOREIGN KEY (preferred_pharmacy_id) REFERENCES pharmacies(id);


-- ===========================================
-- EXAMPLE 2: Adding new table (immunizations)
-- ===========================================

CREATE TABLE immunizations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id          UUID NOT NULL REFERENCES patients(id),
    
    -- CVX code (CDC vaccine code)
    cvx_code            VARCHAR(10) NOT NULL,
    vaccine_name        VARCHAR(255) NOT NULL,
    manufacturer        VARCHAR(100),
    lot_number          VARCHAR(50),
    
    -- Administration
    administered_at     TIMESTAMP WITH TIME ZONE NOT NULL,
    administered_by     UUID REFERENCES providers(id),
    site                VARCHAR(50),  -- 'left arm', 'right thigh'
    route               VARCHAR(50),  -- 'intramuscular', 'subcutaneous'
    dose_number         INT,  -- 1, 2, 3 for multi-dose series
    
    -- Expiration
    expiration_date     DATE,
    
    -- Reaction
    reaction            TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_immunizations_patient ON immunizations(patient_id);
CREATE INDEX idx_immunizations_cvx ON immunizations(cvx_code);

-- Grant permissions
GRANT SELECT, INSERT ON immunizations TO ehr_application;


-- ===========================================
-- EXAMPLE 3: Changing enum (add value)
-- ===========================================

-- Adding new encounter type (PostgreSQL 10+)
ALTER TYPE encounter_type ADD VALUE 'virtual_urgent' AFTER 'telehealth';

-- Note: Cannot remove enum values without recreating type


-- ===========================================
-- EXAMPLE 4: Partitioning existing table
-- ===========================================

-- For large audit log, convert to partitioned
-- Step 1: Create new partitioned table
CREATE TABLE phi_access_log_new (
    LIKE phi_access_log INCLUDING ALL
) PARTITION BY RANGE (accessed_at);

-- Step 2: Create partitions
CREATE TABLE phi_access_log_2024 PARTITION OF phi_access_log_new
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE phi_access_log_2025 PARTITION OF phi_access_log_new
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- Step 3: Migrate data (in batches, during maintenance window)
INSERT INTO phi_access_log_new SELECT * FROM phi_access_log;

-- Step 4: Swap tables
ALTER TABLE phi_access_log RENAME TO phi_access_log_old;
ALTER TABLE phi_access_log_new RENAME TO phi_access_log;

-- Step 5: Verify, then drop old table
DROP TABLE phi_access_log_old;
```

---

# Part 11: CDC & Event Streaming

```
============================================================
HEALTHCARE CDC (Change Data Capture) PATTERNS
============================================================

CDC ARCHITECTURE:
┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka Topics   │
│   (source)  │     │ (connector) │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌────────────────┬────────────────┬──────┴─────┐
        ▼                ▼                ▼            ▼
  ┌──────────┐    ┌──────────┐    ┌──────────┐  ┌──────────┐
  │Elasticsearch│  │ Analytics │   │ Audit    │  │ HL7 FHIR │
  │  (search)   │  │ (reports) │   │ Archive  │  │ (interop)│
  └──────────────┘  └──────────┘   └──────────┘  └──────────┘

============================================================
KAFKA TOPICS
============================================================

ehr.patients
  - Patient demographics changes
  - Partition by: organization_id
  - Retention: 7 days (replay for downstream)

ehr.encounters
  - Encounter create/update/close
  - Partition by: facility_id
  - Consumers: analytics, billing

ehr.lab_results
  - New lab results
  - Partition by: patient_id
  - Consumers: alerting (critical values), analytics

ehr.medications
  - Prescription changes
  - Partition by: patient_id
  - Consumers: pharmacy integration, drug interaction alerts

ehr.clinical_notes
  - Note signing events
  - Partition by: provider_id
  - Consumers: quality review, compliance

ehr.audit_events
  - PHI access events (high volume)
  - Partition by: date
  - Consumers: audit archive (S3), SIEM

============================================================
DEBEZIUM CONNECTOR CONFIG
============================================================

{
  "name": "ehr-postgres-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "ehr-primary.db.internal",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "${secrets:debezium-password}",
    "database.dbname": "ehr_production",
    "database.server.name": "ehr",
    
    "table.include.list": "public.patients,public.encounters,public.medications,public.lab_results,public.clinical_notes",
    
    "publication.name": "ehr_publication",
    "slot.name": "debezium_ehr",
    
    "transforms": "unwrap,route",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.route.regex": "ehr\\.public\\.(.*)",
    "transforms.route.replacement": "ehr.$1",
    
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter"
  }
}

============================================================
FHIR INTEROPERABILITY (HL7 FHIR R4)
============================================================

-- Trigger to publish FHIR resources
CREATE OR REPLACE FUNCTION publish_fhir_patient()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('fhir_events', json_build_object(
        'resourceType', 'Patient',
        'id', NEW.id,
        'identifier', json_build_array(
            json_build_object('system', 'urn:mrn', 'value', NEW.mrn)
        ),
        'name', json_build_array(
            json_build_object(
                'family', NEW.last_name,
                'given', ARRAY[NEW.first_name, NEW.middle_name]
            )
        ),
        'birthDate', NEW.date_of_birth,
        'gender', NEW.gender
    )::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_fhir_patient
AFTER INSERT OR UPDATE ON patients
FOR EACH ROW EXECUTE FUNCTION publish_fhir_patient();
```

---

# Part 12: Disaster Recovery

```
============================================================
HEALTHCARE EHR DISASTER RECOVERY
============================================================

COMPLIANCE REQUIREMENTS:
- HIPAA: PHI must be recoverable
- RPO: < 1 hour (regulatory)
- RTO: < 4 hours (clinical operations)

============================================================
BACKUP STRATEGY
============================================================

1. CONTINUOUS WAL ARCHIVING
   - Stream WAL to S3 (encrypted)
   - Retention: 30 days
   - Point-in-time recovery to any second

2. DAILY BASE BACKUPS
   - pg_basebackup to S3
   - Retention: 90 days
   - Full restore in < 2 hours

3. LOGICAL BACKUPS (MONTHLY)
   - pg_dump for selective restore
   - Retention: 7 years (HIPAA)
   - For schema migration testing

============================================================
REPLICATION TOPOLOGY
============================================================

                    ┌─────────────────┐
                    │   Primary DC    │
                    │  (us-east-1a)   │
                    │                 │
                    │  PostgreSQL     │
                    │  Primary        │
                    └────────┬────────┘
                             │ Synchronous
            ┌────────────────┼────────────────┐
            ▼                ▼                ▼
   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
   │ Sync Replica │   │ Sync Replica │   │ Async Replica│
   │ (us-east-1b) │   │ (us-east-1c) │   │ (us-west-2)  │
   │ Read queries │   │ Read queries │   │ DR standby   │
   └─────────────┘   └─────────────┘   └─────────────┘

SYNCHRONOUS COMMIT:
  synchronous_commit = remote_apply
  synchronous_standby_names = 'ANY 1 (replica_1b, replica_1c)'
  
  # Guarantees: No data loss on failover within region

============================================================
FAILOVER PROCEDURES
============================================================

AUTOMATIC (via Patroni/pg_auto_failover):
1. Primary health check fails (3 consecutive)
2. Sync replica promoted to primary
3. DNS updated (< 30 seconds)
4. Clients reconnect automatically

MANUAL (DR failover to us-west-2):
1. Confirm primary region is down
2. Promote async replica: pg_ctl promote
3. Update connection strings / DNS
4. Notify on-call team
5. Verify audit logging is active

============================================================
AUDIT LOG ARCHIVAL (S3)
============================================================

-- Partition management: Archive old partitions
CREATE OR REPLACE FUNCTION archive_old_audit_partitions()
RETURNS void AS $$
DECLARE
    partition_name TEXT;
    cutoff_date DATE := CURRENT_DATE - INTERVAL '2 years';
BEGIN
    FOR partition_name IN
        SELECT inhrelid::regclass::text
        FROM pg_inherits
        WHERE inhparent = 'phi_access_log'::regclass
          AND inhrelid::regclass::text < 'phi_access_log_' || to_char(cutoff_date, 'YYYY')
    LOOP
        -- Export to S3
        EXECUTE format(
            'COPY (SELECT * FROM %I) TO PROGRAM ''aws s3 cp - s3://ehr-audit-archive/%s.csv.gz --sse aws:kms''',
            partition_name,
            partition_name
        );
        
        -- Detach and drop partition
        EXECUTE format('ALTER TABLE phi_access_log DETACH PARTITION %I', partition_name);
        EXECUTE format('DROP TABLE %I', partition_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Schedule: Weekly via pg_cron
SELECT cron.schedule('archive-audit', '0 3 * * 0', 'SELECT archive_old_audit_partitions()');

============================================================
TESTING SCHEDULE
============================================================

| Test | Frequency | RTO Target | Last Test |
|------|-----------|------------|-----------|
| Primary failover | Monthly | < 30s | 2024-01-15 |
| DR failover | Quarterly | < 4 hours | 2024-01-01 |
| Point-in-time restore | Monthly | < 2 hours | 2024-01-20 |
| Audit log retrieval | Quarterly | < 1 hour | 2023-12-01 |
| Backup integrity | Weekly | N/A | Auto |
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- HEALTHCARE: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / CHANGE HISTORY
-- ===========================================

-- Generic change log for any entity (HIPAA-critical)
CREATE TABLE entity_change_log (
    id                  BIGSERIAL PRIMARY KEY,
    entity_type         VARCHAR(50) NOT NULL,  -- 'patient', 'encounter', 'medication'
    entity_id           UUID NOT NULL,
    field_name          VARCHAR(100) NOT NULL,
    old_value           TEXT,
    new_value           TEXT,
    changed_by_id       UUID NOT NULL REFERENCES users(id),
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    change_reason       TEXT,  -- Required for clinical amendments
    ip_address          INET,
    user_agent          TEXT
) PARTITION BY RANGE (changed_at);

CREATE INDEX idx_ecl_entity ON entity_change_log(entity_type, entity_id);
CREATE INDEX idx_ecl_user ON entity_change_log(changed_by_id);
CREATE INDEX idx_ecl_time ON entity_change_log(changed_at DESC);

-- Partitions by year
CREATE TABLE entity_change_log_2024 PARTITION OF entity_change_log
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE entity_change_log_2025 PARTITION OF entity_change_log
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');


-- ===========================================
-- B. ATTACHMENTS / MEDIA STORAGE
-- ===========================================

CREATE TABLE attachments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type         VARCHAR(50) NOT NULL,  -- 'patient', 'encounter', 'clinical_note'
    entity_id           UUID NOT NULL,
    
    -- File metadata
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    
    -- Storage (S3, encrypted at rest)
    storage_bucket      VARCHAR(100) NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    encryption_key_id   VARCHAR(100),  -- KMS key ID
    
    -- Thumbnail for images
    thumbnail_key       VARCHAR(500),
    
    -- Upload metadata
    uploaded_by_id      UUID NOT NULL REFERENCES users(id),
    upload_ip           INET,
    
    -- Virus scan status
    scan_status         VARCHAR(20) DEFAULT 'pending',  -- 'pending', 'clean', 'infected'
    scanned_at          TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at          TIMESTAMP WITH TIME ZONE  -- Soft delete
);

CREATE INDEX idx_attach_entity ON attachments(entity_type, entity_id);
CREATE INDEX idx_attach_user ON attachments(uploaded_by_id);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TYPE notification_channel AS ENUM ('email', 'sms', 'push', 'pager', 'fax');
CREATE TYPE notification_priority AS ENUM ('critical', 'high', 'normal', 'low');

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID REFERENCES users(id),
    
    -- Delivery
    channel             notification_channel NOT NULL,
    recipient           VARCHAR(255) NOT NULL,  -- email, phone, device token
    priority            notification_priority DEFAULT 'normal',
    
    -- Content
    template_id         VARCHAR(100),
    subject             VARCHAR(255),
    body                TEXT NOT NULL,
    payload             JSONB,  -- For push notifications
    
    -- Status
    status              VARCHAR(20) DEFAULT 'pending',  -- pending, sent, failed, bounced
    retry_count         INT DEFAULT 0,
    max_retries         INT DEFAULT 3,
    
    -- Timestamps
    scheduled_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    sent_at             TIMESTAMP WITH TIME ZONE,
    failed_at           TIMESTAMP WITH TIME ZONE,
    failure_reason      TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_notif_status ON notification_queue(status, scheduled_at);
CREATE INDEX idx_notif_user ON notification_queue(user_id);

-- Critical lab result notification template
INSERT INTO notification_queue (user_id, channel, recipient, priority, subject, body)
SELECT 
    p.primary_physician_id,
    'pager',
    pr.pager_number,
    'critical',
    'CRITICAL LAB RESULT',
    format('Patient %s has critical K+ level: %s', p.mrn, lr.value)
FROM lab_results lr
JOIN patients p ON lr.patient_id = p.id
JOIN providers pr ON p.primary_physician_id = pr.id
WHERE lr.is_critical = TRUE AND lr.notified = FALSE;


-- ===========================================
-- D. WEBHOOKS / INTEGRATIONS
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id     UUID REFERENCES organizations(id),
    
    -- Endpoint
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,  -- HMAC signing key
    
    -- Events
    events              TEXT[] NOT NULL,  -- ['patient.created', 'encounter.completed']
    
    -- Filters
    filter_facility_ids UUID[],  -- Only these facilities
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    failure_count       INT DEFAULT 0,
    last_failure_at     TIMESTAMP WITH TIME ZONE,
    
    -- Metadata
    description         VARCHAR(255),
    created_by_id       UUID REFERENCES users(id),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_deliveries (
    id                  BIGSERIAL PRIMARY KEY,
    subscription_id     UUID NOT NULL REFERENCES webhook_subscriptions(id),
    
    -- Request
    event_type          VARCHAR(100) NOT NULL,
    payload             JSONB NOT NULL,
    
    -- Response
    response_code       INT,
    response_body       TEXT,
    response_time_ms    INT,
    
    -- Status
    status              VARCHAR(20) DEFAULT 'pending',  -- pending, success, failed
    retry_count         INT DEFAULT 0,
    next_retry_at       TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_whd_sub ON webhook_deliveries(subscription_id);
CREATE INDEX idx_whd_status ON webhook_deliveries(status, next_retry_at);


-- ===========================================
-- E. API KEYS / RATE LIMITING
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id     UUID REFERENCES organizations(id),
    
    -- Key (store hash only)
    key_prefix          VARCHAR(8) NOT NULL,  -- First 8 chars for identification
    key_hash            VARCHAR(64) NOT NULL UNIQUE,  -- SHA-256
    
    -- Permissions
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,  -- ['read:patients', 'write:encounters']
    
    -- Limits
    rate_limit_rpm      INT DEFAULT 1000,
    rate_limit_daily    INT DEFAULT 100000,
    
    -- IP restrictions
    allowed_ips         INET[],
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    last_used_at        TIMESTAMP WITH TIME ZONE,
    expires_at          TIMESTAMP WITH TIME ZONE,
    
    -- Audit
    created_by_id       UUID REFERENCES users(id),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at          TIMESTAMP WITH TIME ZONE,
    revoked_by_id       UUID REFERENCES users(id)
);

CREATE INDEX idx_api_key_hash ON api_keys(key_hash);
CREATE INDEX idx_api_key_org ON api_keys(organization_id);

-- Rate limit tracking (Redis recommended, but PG fallback)
CREATE UNLOGGED TABLE rate_limit_counters (
    key                 VARCHAR(255) PRIMARY KEY,  -- 'api_key:{id}:rpm' or 'api_key:{id}:daily'
    count               INT NOT NULL DEFAULT 0,
    window_start        TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- F. OAUTH / SSO
-- ===========================================

CREATE TABLE oauth_providers (
    id                  SERIAL PRIMARY KEY,
    organization_id     UUID REFERENCES organizations(id),
    
    -- Provider
    provider_type       VARCHAR(50) NOT NULL,  -- 'okta', 'azure_ad', 'google', 'epic'
    name                VARCHAR(100) NOT NULL,
    
    -- OIDC Config
    client_id           VARCHAR(255) NOT NULL,
    client_secret_enc   BYTEA NOT NULL,  -- Encrypted with app key
    issuer_url          VARCHAR(500),  -- OIDC discovery
    authorization_url   VARCHAR(500),
    token_url           VARCHAR(500),
    userinfo_url        VARCHAR(500),
    
    -- SAML Config (alternative)
    saml_metadata_url   VARCHAR(500),
    saml_entity_id      VARCHAR(255),
    
    -- Mapping
    user_attribute_map  JSONB,  -- {'email': 'mail', 'name': 'displayName'}
    default_role        VARCHAR(50),
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    enforce_mfa         BOOLEAN DEFAULT TRUE,  -- HIPAA requirement
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE user_oauth_links (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL REFERENCES users(id),
    provider_id         INT NOT NULL REFERENCES oauth_providers(id),
    
    -- External identity
    external_id         VARCHAR(255) NOT NULL,
    external_email      VARCHAR(255),
    
    -- Tokens (encrypted)
    access_token_enc    BYTEA,
    refresh_token_enc   BYTEA,
    token_expires_at    TIMESTAMP WITH TIME ZONE,
    
    -- Last login
    last_login_at       TIMESTAMP WITH TIME ZONE,
    last_login_ip       INET,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_user_provider UNIQUE (user_id, provider_id),
    CONSTRAINT uk_external_id UNIQUE (provider_id, external_id)
);


-- ===========================================
-- G. USER SESSIONS
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id),
    
    -- Session token (store hash)
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    
    -- Device info
    device_type         VARCHAR(50),  -- 'web', 'mobile', 'tablet'
    device_name         VARCHAR(100),
    browser             VARCHAR(100),
    os                  VARCHAR(100),
    
    -- Location
    ip_address          INET NOT NULL,
    geo_city            VARCHAR(100),
    geo_country         VARCHAR(2),
    
    -- Status
    is_active           BOOLEAN DEFAULT TRUE,
    mfa_verified        BOOLEAN DEFAULT FALSE,  -- HIPAA: MFA required for PHI
    
    -- Timestamps
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_activity_at    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_session_user ON user_sessions(user_id);
CREATE INDEX idx_session_token ON user_sessions(token_hash);
CREATE INDEX idx_session_active ON user_sessions(user_id, is_active) WHERE is_active = TRUE;

-- Cleanup expired sessions (run daily via pg_cron)
DELETE FROM user_sessions WHERE expires_at < NOW() - INTERVAL '30 days';


-- ===========================================
-- H. FEATURE FLAGS
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    description         TEXT,
    
    -- Rollout
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,  -- 0-100
    
    -- Targeting
    allowed_user_ids    UUID[],
    allowed_org_ids     UUID[],
    allowed_roles       TEXT[],
    
    -- Metadata
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Example: Enable new telehealth UI for 10% of users
INSERT INTO feature_flags (name, description, rollout_percentage)
VALUES ('telehealth_v2_ui', 'New telehealth interface', 10);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
HEALTHCARE: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. AUDIT LOG PERFORMANCE (WRITE-HEAVY)
============================================================

THE CHALLENGE:
HIPAA requires logging EVERY read/write of PHI.
A single page load for a doctor = 50 audit rows.
Risk: Audit logging slows down the clinical app.

SOLUTION: ASYNC LOGGING (FIRE-AND-FORGET)
1. **App Layer**: Writes to local memory buffer or local disk queue.
2. **Log Shipper** (Fluentd/Vector): Pushes to Kafka `ehr.audit_events`.
3. **Consumer**: Batches writes to PostgreSQL Partitioned Table / ClickHouse.

DB INDEXING STRATEGY:
- BRIN Index on `timestamp` (Block Range Index).
- 99% smaller than B-Tree. Perfect for append-only time-series data.

============================================================
2. HL7 INTEGRATION (FIFO QUEUES)
============================================================

THE CHALLENGE:
Receiving Lab Results via HL7 v2 (Pipe delimited text).
Ordering Matters:
- Msg 1: Order Lab (ORM)
- Msg 2: Result Preliminary (ORU)
- Msg 3: Result Final (ORU)

If Msg 3 processes before Msg 2, we have data corruption.

ARCHITECTURE:
- **MLLP Listener**: Termination point for TCP connections.
- **Kafka Partitioning**: Key = `PatientMRN`.
- **Guarantee**: All messages for Patient John Doe go to Partition 5 -> Consumer A.
- **Sequential Processing**: Consumer A must process strictly in offset order.

============================================================
3. DATA DE-IDENTIFICATION (RESEARCH EXPORT)
============================================================

SCENARIO:
Research team wants "All diabetes patients for study", but NO names/SSNs (HIPAA).

IMPLEMENTATION (MASKING VIEWS):
```sql
CREATE VIEW research_patients AS
SELECT 
    id,
    -- Generalize Zip (First 3 digits only - Safe Harbor method)
    concat(substring(zip_code, 1, 3), '00') as zip,
    -- Shift dates (random offset per patient, preserved across tables)
    dob + (patient_salt_days || ' days')::interval as dob_shifted,
    gender
FROM patients;
```

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Chart Load Latency (p99)     │ < 1s    │ > 3s = PAGE     │
│  Prescription send-to-pharmacy│ < 5s    │ > 15s = WARN    │
│  HL7 Processing Lag           │ < 10s   │ > 1m = WARN     │
│  Emergency "Break Glass" Rate │ 0/day   │ > 0 = SECURITY  │
└─────────────────────────────────────────────────────────────┘

INFRASTRUCTURE METRICS:
- `connection_pooling_wait`: High wait = connection leak (common in legacy apps).
- `bloat_ratio`: Audit tables grow fast. Check autovacuum settings.

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: "BREAK THE GLASS" (Emergency Access)
Symptom: Doctor is treating unconscious patient, needs access but isn't assigned care team.
Mechanism:
- UI "Emergency Access" button.
- Backend: Bypass RBAC checks.
- **Critical Side Effect**: Trigger P0 Security Alert to Compliance Officer. Auto-audit.

SCENARIO 2: DRUG INTERACTION SERVICE DOWN
Symptom: Doctor prescribes Warfarin. Alerting API times out.
Mitigation:
- Fail Open vs Fail Closed?
- **Fail Open**: Allow prescription, but flash "INTERACTION CHECK OFFLINE - USE CAUTION".
- Async check: Run check when service back up, page doctor if dangerous.

SCENARIO 3: INCORRECT PATIENT MERGE
Symptom: Two "John Smiths" merged into one.
Recovery:
- "Unmerge" Tool: Uses `entity_change_log` to reverse transactions.
- Hardest problem in Health IT. Prevention: Require 3 matching identifiers (Name, DOB, SSN/MRN).

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

IMAGING STORAGE (PACS):
- MRIs are huge (500MB+).
- Tiering:
  - Recent (Active treatment): SSD / S3 Standard.
  - > 60 days: S3 IA.
  - > 7 years (Archives): S3 Glacier Deep Archive (Cost pennies/GB).

LICENSING (CPT/ICD-10):
- Reference data (Medical Codes) is proprietary.
- Cache locally to avoid hitting expensive API lookups per encounter.
```

---

## 🔗 Related Documents

- [Neobank Schema](./neobank-schema-design-guide.md) — Similar compliance patterns
- [Data Compliance Guide](../system-design-notes/data-compliance-guide.md) — HIPAA, GDPR
- [Database Scaling](./database-scaling-guide.md) — Partitioning audit logs
- [Disaster Recovery Guide](../system-design-notes/disaster-recovery-guide.md) — DR strategies
