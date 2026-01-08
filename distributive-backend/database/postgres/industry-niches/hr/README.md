# HR & Recruitment Platform Database Design

## Overview

This schema provides a comprehensive database design for Human Resources Management and Recruitment Systems. It supports organizational structure management, employee lifecycle tracking, recruitment workflows, performance management, and compliance reporting.

## Key Features

### 🏢 Organizational Structure
- **Multi-company support** with hierarchical department structures
- **Flexible job positions** with compensation ranges and requirements
- **Employee hierarchy** with manager relationships and reporting lines

### 👥 Employee Lifecycle Management
- **Complete employee profiles** with personal, employment, and demographic data
- **Onboarding and offboarding** tracking
- **Compensation history** and benefits enrollment
- **Work arrangement** tracking (office, remote, hybrid)

### 🎯 Recruitment & Talent Acquisition
- **Job posting management** with detailed requirements and compensation
- **Candidate relationship management** with profile completion tracking
- **Application workflow** from submission to offer acceptance
- **Interview and assessment** tracking

### 📊 Performance Management
- **360-degree performance reviews** with competency ratings
- **Goal setting and tracking** with progress monitoring
- **Development planning** and training program management

### ⏰ Time & Attendance
- **Time tracking** with break management and productive hours calculation
- **Attendance records** with leave type categorization
- **Overtime and leave balance** management

## Database Schema Highlights

### Core Tables

#### Organizational Structure
- **`companies`** - Multi-tenant company information
- **`departments`** - Hierarchical department structure
- **`job_positions`** - Position definitions with compensation ranges
- **`employees`** - Complete employee profiles and employment details

#### Recruitment
- **`job_postings`** - Job advertisements with full-text search
- **`candidates`** - Applicant profiles with skills and preferences
- **`applications`** - Application workflow tracking

#### Performance & Development
- **`performance_reviews`** - Multi-round performance evaluations
- **`goals`** - Goal setting and progress tracking
- **`training_programs`** - Learning and development programs
- **`employee_training`** - Training enrollment and completion

#### Time Management
- **`time_entries`** - Detailed time tracking with breaks
- **`attendance_records`** - Daily attendance and leave tracking

#### Compensation
- **`salary_history`** - Salary change tracking with approval workflow
- **`benefits_enrollment`** - Benefits package management

## Key Design Patterns

### 1. Hierarchical Data Management
```sql
-- Employee hierarchy using recursive CTEs
WITH RECURSIVE emp_hierarchy AS (
    SELECT employee_id, first_name, last_name, manager_id, 0 as level
    FROM employees WHERE manager_id IS NULL

    UNION ALL

    SELECT e.employee_id, e.first_name, e.last_name, e.manager_id, eh.level + 1
    FROM employees e
    JOIN emp_hierarchy eh ON e.manager_id = eh.employee_id
)
SELECT * FROM emp_hierarchy;
```

### 2. Full-Text Search for Recruitment
```sql
-- Job posting search with ranking
SELECT job_posting_id, job_title,
       ts_rank(search_vector, query) as relevance
FROM job_postings, to_tsquery('english', 'software engineer') query
WHERE search_vector @@ query
ORDER BY relevance DESC;
```

### 3. Performance Analytics
```sql
-- Employee performance dashboard
SELECT
    e.employee_id,
    e.first_name,
    e.last_name,
    AVG(pr.overall_rating) as avg_performance_rating,
    COUNT(g.goal_id) as goals_set,
    COUNT(CASE WHEN g.status = 'completed' THEN 1 END) as goals_completed,
    SUM(te.productive_hours) as total_hours_worked
FROM employees e
LEFT JOIN performance_reviews pr ON e.employee_id = pr.employee_id
LEFT JOIN goals g ON e.employee_id = g.employee_id
LEFT JOIN time_entries te ON e.employee_id = te.employee_id
    AND te.work_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY e.employee_id, e.first_name, e.last_name;
```

### 4. Recruitment Funnel Analytics
```sql
-- Application conversion rates
SELECT
    jp.job_title,
    COUNT(a.application_id) as applications,
    COUNT(CASE WHEN a.application_status = 'interview_scheduled' THEN 1 END) as interviews,
    COUNT(CASE WHEN a.application_status = 'offer_extended' THEN 1 END) as offers,
    COUNT(CASE WHEN a.application_status = 'offer_accepted' THEN 1 END) as hires,
    ROUND(100.0 * COUNT(CASE WHEN a.application_status = 'offer_accepted' THEN 1 END) /
          NULLIF(COUNT(a.application_id), 0), 1) as conversion_rate
FROM job_postings jp
LEFT JOIN applications a ON jp.job_posting_id = a.job_posting_id
WHERE jp.posting_status = 'closed'
GROUP BY jp.job_posting_id, jp.job_title;
```

## Performance Optimizations

### Indexes
- **Composite indexes** on frequently queried combinations (employee_id + date)
- **Full-text search indexes** on job descriptions and candidate profiles
- **Partial indexes** for active records and status filtering
- **GIN indexes** for array and JSONB data types

### Partitioning Strategy
```sql
-- Partition time entries by month for performance
CREATE TABLE time_entries_y2024m01 PARTITION OF time_entries
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition performance reviews by year
CREATE TABLE performance_reviews_2024 PARTITION OF performance_reviews
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### Materialized Views
```sql
-- Employee summary for dashboard performance
CREATE MATERIALIZED VIEW employee_summary AS
SELECT
    e.employee_id,
    e.first_name || ' ' || e.last_name as full_name,
    d.department_name,
    jp.position_title,
    e.hire_date,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, e.hire_date)) as years_of_service,
    -- Latest performance rating
    (SELECT overall_rating FROM performance_reviews pr
     WHERE pr.employee_id = e.employee_id
     ORDER BY review_period_end DESC LIMIT 1) as current_rating
FROM employees e
LEFT JOIN departments d ON e.department_id = d.department_id
LEFT JOIN job_positions jp ON e.position_id = jp.position_id
WHERE e.employment_status = 'active';
```

## Security Considerations

### Row Level Security (RLS)
```sql
-- Enable RLS on sensitive tables
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE salary_history ENABLE ROW LEVEL SECURITY;

-- Policies for HR staff access
CREATE POLICY hr_employee_access ON employees
    FOR ALL USING (
        current_user_has_role('hr_admin') OR
        employee_id = current_user_employee_id()
    );

-- Policies for manager access
CREATE POLICY manager_access ON employees
    FOR SELECT USING (
        manager_id = current_user_employee_id() OR
        department_id IN (
            SELECT department_id FROM employees
            WHERE employee_id = current_user_employee_id()
        )
    );
```

### Data Encryption
```sql
-- Encrypt sensitive PII data
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Encrypted storage for sensitive fields
ALTER TABLE employees ADD COLUMN encrypted_ssn bytea;
ALTER TABLE candidates ADD COLUMN encrypted_phone bytea;

-- Encryption functions
CREATE OR REPLACE FUNCTION encrypt_sensitive_data(plain_text text)
RETURNS bytea AS $$
BEGIN
    RETURN pgp_sym_encrypt(plain_text, current_setting('app.encryption_key'));
END;
$$ LANGUAGE plpgsql;
```

## Compliance Features

### GDPR Compliance
- **Data retention policies** with automatic data deletion
- **Consent management** for data processing
- **Right to erasure** implementation
- **Data portability** export functions

### Audit Trail
```sql
-- Comprehensive audit logging
CREATE TABLE hr_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name text NOT NULL,
    record_id UUID NOT NULL,
    operation text NOT NULL,
    old_values jsonb,
    new_values jsonb,
    changed_by UUID REFERENCES employees(employee_id),
    changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);
```

## Integration Points

### External Systems
- **Payroll systems** integration via API/webhooks
- **Learning management systems** for training tracking
- **Applicant tracking systems** for recruitment automation
- **Time clock devices** for attendance tracking

### API Endpoints
- **REST APIs** for employee self-service
- **GraphQL APIs** for complex organizational queries
- **Webhooks** for real-time notifications
- **Bulk import/export** for data migration

## Monitoring & Analytics

### Key Metrics
- **Time-to-fill** for open positions
- **Employee turnover rate** by department
- **Training completion rates**
- **Performance rating distributions**
- **Attendance patterns** and trends

### Dashboard Views
```sql
-- HR dashboard metrics
CREATE VIEW hr_dashboard_metrics AS
SELECT
    -- Recruitment metrics
    (SELECT COUNT(*) FROM job_postings WHERE posting_status = 'published') as open_positions,
    (SELECT AVG(EXTRACT(EPOCH FROM (offer_accepted_at - submitted_at))/86400)
     FROM applications WHERE offer_accepted_at IS NOT NULL) as avg_time_to_hire,

    -- Employee metrics
    (SELECT COUNT(*) FROM employees WHERE employment_status = 'active') as active_employees,
    (SELECT COUNT(*) FROM employees
     WHERE termination_date >= CURRENT_DATE - INTERVAL '30 days') as recent_turnover,

    -- Performance metrics
    (SELECT AVG(overall_rating) FROM performance_reviews
     WHERE review_period_end >= CURRENT_DATE - INTERVAL '12 months') as avg_performance_rating
;
```

This HR database schema provides a solid foundation for building comprehensive human resources management systems with scalability, compliance, and performance in mind.