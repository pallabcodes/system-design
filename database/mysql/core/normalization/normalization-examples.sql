-- MySQL Database Normalization Examples
-- Comprehensive examples of 1NF, 2NF, 3NF, BCNF, 4NF, and 5NF normalization
-- With practical examples and denormalization strategies where appropriate

-- ===========================================
-- UNNORMALIZED DATA (0NF) - PROBLEMATIC
-- ===========================================

-- Bad: Everything in one table with repeating groups and multivalued attributes
CREATE TABLE customer_orders_denormalized (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_name VARCHAR(255),
    customer_email VARCHAR(255),
    customer_phone VARCHAR(20),

    -- Order information (repeating group)
    order_1_id INT,
    order_1_date DATE,
    order_1_total DECIMAL(10,2),
    order_1_item_1_name VARCHAR(255),
    order_1_item_1_quantity INT,
    order_1_item_1_price DECIMAL(8,2),
    order_1_item_2_name VARCHAR(255),
    order_1_item_2_quantity INT,
    order_1_item_2_price DECIMAL(8,2),

    order_2_id INT,
    order_2_date DATE,
    order_2_total DECIMAL(10,2),
    -- ... more repeating columns

    -- Customer preferences (multivalued)
    preferred_categories VARCHAR(1000),  -- Comma-separated: "electronics,books,clothing"
    preferred_brands VARCHAR(1000),     -- Comma-separated: "apple,samsung,nike"
    notification_methods VARCHAR(500),  -- Comma-separated: "email,sms,push"

    -- Address information (composite attribute)
    home_address_street VARCHAR(255),
    home_address_city VARCHAR(100),
    home_address_state VARCHAR(50),
    home_address_zip VARCHAR(20),
    work_address_street VARCHAR(255),
    work_address_city VARCHAR(100),
    work_address_state VARCHAR(50),
    work_address_zip VARCHAR(20)
) ENGINE = InnoDB;

-- ===========================================
-- FIRST NORMAL FORM (1NF)
-- ===========================================
-- Rules:
-- 1. All attributes must be atomic (no repeating groups)
-- 2. All attributes must contain only single values
-- 3. Each record must be uniquely identifiable

-- Good: Separate tables for customers, orders, and order items
CREATE TABLE customers_1nf (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_name VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255) UNIQUE NOT NULL,
    customer_phone VARCHAR(20),

    -- Preferences now in separate table (still not fully normalized)
    preferred_categories VARCHAR(1000),  -- Still comma-separated - violates 1NF
    preferred_brands VARCHAR(1000),     -- Still comma-separated - violates 1NF

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE orders_1nf (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    order_date DATE NOT NULL,
    order_total DECIMAL(10,2) NOT NULL,
    order_status ENUM('pending', 'processing', 'shipped', 'delivered') DEFAULT 'pending',

    FOREIGN KEY (customer_id) REFERENCES customers_1nf(customer_id),

    INDEX idx_orders_customer (customer_id),
    INDEX idx_orders_date (order_date),
    INDEX idx_orders_status (order_status)
) ENGINE = InnoDB;

CREATE TABLE order_items_1nf (
    order_item_id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    item_name VARCHAR(255) NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(8,2) NOT NULL,

    FOREIGN KEY (order_id) REFERENCES orders_1nf(order_id) ON DELETE CASCADE,

    INDEX idx_order_items_order (order_id)
) ENGINE = InnoDB;

-- ===========================================
-- SECOND NORMAL FORM (2NF)
-- ===========================================
-- Rules:
-- 1. Must be in 1NF
-- 2. All non-key attributes must depend on the entire primary key
-- 3. No partial dependencies

-- Good: Separate customer preferences into their own table
-- Remove partial dependencies

CREATE TABLE customers_2nf (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_name VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255) UNIQUE NOT NULL,
    customer_phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_customers_email (customer_email)
) ENGINE = InnoDB;

CREATE TABLE customer_preferences_2nf (
    preference_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    preference_type ENUM('category', 'brand', 'notification_method') NOT NULL,
    preference_value VARCHAR(255) NOT NULL,

    FOREIGN KEY (customer_id) REFERENCES customers_2nf(customer_id) ON DELETE CASCADE,
    UNIQUE KEY unique_customer_preference (customer_id, preference_type, preference_value),

    INDEX idx_preferences_customer (customer_id),
    INDEX idx_preferences_type (preference_type)
) ENGINE = InnoDB;

-- Orders and order items remain the same (already in 2NF)
CREATE TABLE orders_2nf (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    order_date DATE NOT NULL,
    order_total DECIMAL(10,2) NOT NULL,
    order_status ENUM('pending', 'processing', 'shipped', 'delivered') DEFAULT 'pending',

    FOREIGN KEY (customer_id) REFERENCES customers_2nf(customer_id),

    INDEX idx_orders_customer (customer_id),
    INDEX idx_orders_date (order_date),
    INDEX idx_orders_status (order_status)
) ENGINE = InnoDB;

CREATE TABLE order_items_2nf (
    order_item_id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    product_id INT NOT NULL,  -- Now references products table
    quantity INT NOT NULL,
    unit_price DECIMAL(8,2) NOT NULL,

    FOREIGN KEY (order_id) REFERENCES orders_2nf(order_id) ON DELETE CASCADE,

    INDEX idx_order_items_order (order_id),
    INDEX idx_order_items_product (product_id)
) ENGINE = InnoDB;

-- ===========================================
-- THIRD NORMAL FORM (3NF)
-- ===========================================
-- Rules:
-- 1. Must be in 2NF
-- 2. No transitive dependencies (non-key attributes can't depend on other non-key attributes)
-- 3. Every non-key attribute must depend directly on the primary key

-- Good: Extract products, addresses, and order calculations into separate tables

CREATE TABLE customers_3nf (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_name VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255) UNIQUE NOT NULL,
    customer_phone VARCHAR(20),
    default_address_id INT,  -- References address, not transitive dependency

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (default_address_id) REFERENCES addresses(address_id),

    INDEX idx_customers_email (customer_email),
    INDEX idx_customers_default_address (default_address_id)
) ENGINE = InnoDB;

-- Separate addresses (eliminates transitive dependency)
CREATE TABLE addresses (
    address_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    address_type ENUM('home', 'work', 'billing', 'shipping') DEFAULT 'home',
    street_address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(50) DEFAULT 'USA',

    FOREIGN KEY (customer_id) REFERENCES customers_3nf(customer_id) ON DELETE CASCADE,

    INDEX idx_addresses_customer (customer_id),
    INDEX idx_addresses_type (address_type),
    INDEX idx_addresses_city (city, state_province)
) ENGINE = InnoDB;

-- Separate products (eliminates transitive dependency on product details)
CREATE TABLE products_3nf (
    product_id INT PRIMARY KEY AUTO_INCREMENT,
    product_name VARCHAR(255) NOT NULL,
    sku VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    category_id INT NOT NULL,
    unit_price DECIMAL(8,2) NOT NULL,
    cost_price DECIMAL(8,2),

    FOREIGN KEY (category_id) REFERENCES categories(category_id),

    INDEX idx_products_sku (sku),
    INDEX idx_products_category (category_id),
    INDEX idx_products_price (unit_price),
    FULLTEXT INDEX ft_products_name_desc (product_name, description)
) ENGINE = InnoDB;

CREATE TABLE categories (
    category_id INT PRIMARY KEY AUTO_INCREMENT,
    category_name VARCHAR(100) NOT NULL,
    parent_category_id INT NULL,
    description TEXT,

    FOREIGN KEY (parent_category_id) REFERENCES categories(category_id),

    INDEX idx_categories_parent (parent_category_id),
    UNIQUE KEY unique_category_name_parent (category_name, parent_category_id)
) ENGINE = InnoDB;

-- Orders now reference products, not store product details
CREATE TABLE orders_3nf (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    order_date DATE NOT NULL,
    shipping_address_id INT,
    billing_address_id INT,
    order_status ENUM('pending', 'processing', 'shipped', 'delivered', 'cancelled') DEFAULT 'pending',

    -- Calculated fields
    subtotal DECIMAL(10,2) DEFAULT 0,
    tax_rate DECIMAL(5,4) DEFAULT 0.08,
    tax_amount DECIMAL(10,2) GENERATED ALWAYS AS (subtotal * tax_rate) STORED,
    shipping_amount DECIMAL(10,2) DEFAULT 0,
    discount_amount DECIMAL(10,2) DEFAULT 0,
    total_amount DECIMAL(10,2) GENERATED ALWAYS AS (subtotal + tax_amount + shipping_amount - discount_amount) STORED,

    FOREIGN KEY (customer_id) REFERENCES customers_3nf(customer_id),
    FOREIGN KEY (shipping_address_id) REFERENCES addresses(address_id),
    FOREIGN KEY (billing_address_id) REFERENCES addresses(address_id),

    INDEX idx_orders_customer (customer_id),
    INDEX idx_orders_date (order_date),
    INDEX idx_orders_status (order_status),
    INDEX idx_orders_shipping_address (shipping_address_id),
    INDEX idx_orders_billing_address (billing_address_id)
) ENGINE = InnoDB;

CREATE TABLE order_items_3nf (
    order_item_id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(8,2) NOT NULL,  -- At time of order
    discount_percentage DECIMAL(5,4) DEFAULT 0,

    FOREIGN KEY (order_id) REFERENCES orders_3nf(order_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products_3nf(product_id),

    INDEX idx_order_items_order (order_id),
    INDEX idx_order_items_product (product_id)
) ENGINE = InnoDB;

-- ===========================================
-- BOYCE-CODD NORMAL FORM (BCNF)
-- ===========================================
-- Rules:
-- 1. Must be in 3NF
-- 2. Every determinant must be a candidate key
-- 3. No non-trivial functional dependencies where the determinant is not a superkey

-- BCNF addresses cases where 3NF is insufficient
-- Example: In a university database, if we have (Student, Course, Instructor)
-- where Instructor determines Course, but Student+Course is the primary key

CREATE TABLE course_enrollments_bcnf (
    student_id INT NOT NULL,
    course_id INT NOT NULL,
    semester VARCHAR(20) NOT NULL,
    grade CHAR(2),

    PRIMARY KEY (student_id, course_id, semester),

    INDEX idx_enrollments_student (student_id),
    INDEX idx_enrollments_course (course_id),
    INDEX idx_enrollments_semester (semester)
) ENGINE = InnoDB;

CREATE TABLE course_instructors_bcnf (
    course_id INT PRIMARY KEY,
    instructor_id INT NOT NULL,
    course_name VARCHAR(255) NOT NULL,
    department VARCHAR(100) NOT NULL,

    FOREIGN KEY (instructor_id) REFERENCES instructors(instructor_id),

    INDEX idx_course_instructors_instructor (instructor_id),
    INDEX idx_course_instructors_dept (department)
) ENGINE = InnoDB;

-- Separate table for instructors (BCNF compliance)
CREATE TABLE instructors (
    instructor_id INT PRIMARY KEY AUTO_INCREMENT,
    instructor_name VARCHAR(255) NOT NULL,
    department VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    hire_date DATE,

    INDEX idx_instructors_dept (department),
    INDEX idx_instructors_email (email)
) ENGINE = InnoDB;

-- ===========================================
-- FOURTH NORMAL FORM (4NF)
-- ===========================================
-- Rules:
-- 1. Must be in BCNF
-- 2. No multi-valued dependencies
-- 3. Non-trivial multi-valued dependencies must be dependencies on a superkey

-- 4NF addresses multi-valued dependencies
-- Example: A product can have multiple colors AND multiple sizes

CREATE TABLE products_4nf (
    product_id INT PRIMARY KEY AUTO_INCREMENT,
    product_name VARCHAR(255) NOT NULL,
    sku VARCHAR(50) UNIQUE NOT NULL,
    base_price DECIMAL(8,2) NOT NULL,
    description TEXT,

    INDEX idx_products_4nf_sku (sku)
) ENGINE = InnoDB;

-- Separate multi-valued attributes into their own tables
CREATE TABLE product_colors_4nf (
    product_id INT NOT NULL,
    color VARCHAR(50) NOT NULL,

    PRIMARY KEY (product_id, color),
    FOREIGN KEY (product_id) REFERENCES products_4nf(product_id) ON DELETE CASCADE,

    INDEX idx_product_colors_product (product_id),
    INDEX idx_product_colors_color (color)
) ENGINE = InnoDB;

CREATE TABLE product_sizes_4nf (
    product_id INT NOT NULL,
    size VARCHAR(20) NOT NULL,
    size_category ENUM('XS', 'S', 'M', 'L', 'XL', 'XXL') NOT NULL,

    PRIMARY KEY (product_id, size),
    FOREIGN KEY (product_id) REFERENCES products_4nf(product_id) ON DELETE CASCADE,

    INDEX idx_product_sizes_product (product_id),
    INDEX idx_product_sizes_category (size_category)
) ENGINE = InnoDB;

CREATE TABLE product_categories_4nf (
    product_id INT NOT NULL,
    category_id INT NOT NULL,

    PRIMARY KEY (product_id, category_id),
    FOREIGN KEY (product_id) REFERENCES products_4nf(product_id) ON DELETE CASCADE,
    FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE CASCADE,

    INDEX idx_product_categories_product (product_id),
    INDEX idx_product_categories_category (category_id)
) ENGINE = InnoDB;

-- ===========================================
-- FIFTH NORMAL FORM (5NF) - DOMAIN/KEY NORMAL FORM
-- ===========================================
-- Rules:
-- 1. Must be in 4NF
-- 2. Every join dependency must be a consequence of the candidate keys
-- 3. No constraints other than domain constraints and key constraints

-- 5NF is rarely needed and can be overkill for most applications
-- Example: Complex many-to-many relationships that need further decomposition

CREATE TABLE research_projects_5nf (
    project_id INT PRIMARY KEY AUTO_INCREMENT,
    project_name VARCHAR(255) NOT NULL,
    budget DECIMAL(12,2),
    start_date DATE,
    end_date DATE,

    INDEX idx_projects_name (project_name),
    INDEX idx_projects_dates (start_date, end_date)
) ENGINE = InnoDB;

-- Separate researchers and their roles (5NF decomposition)
CREATE TABLE project_researchers_5nf (
    project_id INT NOT NULL,
    researcher_id INT NOT NULL,

    PRIMARY KEY (project_id, researcher_id),
    FOREIGN KEY (project_id) REFERENCES research_projects_5nf(project_id) ON DELETE CASCADE,
    FOREIGN KEY (researcher_id) REFERENCES researchers(researcher_id) ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE TABLE project_skills_5nf (
    project_id INT NOT NULL,
    skill_id INT NOT NULL,

    PRIMARY KEY (project_id, skill_id),
    FOREIGN KEY (project_id) REFERENCES research_projects_5nf(project_id) ON DELETE CASCADE,
    FOREIGN KEY (skill_id) REFERENCES skills(skill_id) ON DELETE CASCADE
) ENGINE = InnoDB;

-- Junction table for researcher skills
CREATE TABLE researcher_skills_5nf (
    researcher_id INT NOT NULL,
    skill_id INT NOT NULL,

    PRIMARY KEY (researcher_id, skill_id),
    FOREIGN KEY (researcher_id) REFERENCES researchers(researcher_id) ON DELETE CASCADE,
    FOREIGN KEY (skill_id) REFERENCES skills(skill_id) ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE TABLE researchers (
    researcher_id INT PRIMARY KEY AUTO_INCREMENT,
    researcher_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    department VARCHAR(100),

    INDEX idx_researchers_email (email),
    INDEX idx_researchers_dept (department)
) ENGINE = InnoDB;

CREATE TABLE skills (
    skill_id INT PRIMARY KEY AUTO_INCREMENT,
    skill_name VARCHAR(100) UNIQUE NOT NULL,
    skill_category VARCHAR(50),

    INDEX idx_skills_category (skill_category)
) ENGINE = InnoDB;

-- ===========================================
-- DENORMALIZATION EXAMPLES (When to Break Normalization)
-- ===========================================

-- Read-heavy reporting table (denormalized for performance)
CREATE TABLE order_summary_denorm (
    order_id INT PRIMARY KEY,
    customer_name VARCHAR(255),
    customer_email VARCHAR(255),
    order_date DATE,
    order_total DECIMAL(10,2),
    order_status ENUM('pending', 'processing', 'shipped', 'delivered', 'cancelled'),

    -- Denormalized customer address
    shipping_city VARCHAR(100),
    shipping_state VARCHAR(50),
    shipping_country VARCHAR(50),

    -- Denormalized order items summary
    total_items INT,
    total_quantity INT,
    product_categories TEXT,  -- Comma-separated for reporting

    -- Pre-computed metrics
    days_to_ship INT,
    days_to_deliver INT,
    is_overdue BOOLEAN,

    -- Audit
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_order_summary_customer (customer_name),
    INDEX idx_order_summary_date (order_date),
    INDEX idx_order_summary_status (order_status),
    INDEX idx_order_summary_shipping (shipping_city, shipping_state),
    INDEX idx_order_summary_overdue (is_overdue)
) ENGINE = InnoDB;

-- Materialized view alternative (if using MySQL 8.0+ with views)
CREATE VIEW customer_order_history AS
SELECT
    c.customer_id,
    c.customer_name,
    c.customer_email,
    COUNT(o.order_id) as total_orders,
    SUM(o.total_amount) as total_spent,
    AVG(o.total_amount) as avg_order_value,
    MAX(o.order_date) as last_order_date,
    MIN(o.order_date) as first_order_date,
    GROUP_CONCAT(DISTINCT cat.category_name) as purchased_categories
FROM customers_3nf c
LEFT JOIN orders_3nf o ON c.customer_id = o.customer_id
LEFT JOIN order_items_3nf oi ON o.order_id = oi.order_id
LEFT JOIN products_3nf p ON oi.product_id = p.product_id
LEFT JOIN categories cat ON p.category_id = cat.category_id
WHERE o.order_status != 'cancelled'
GROUP BY c.customer_id, c.customer_name, c.customer_email;

-- ===========================================
-- NORMALIZATION UTILITY FUNCTIONS
-- =========================================--

DELIMITER ;;

-- Function to check normalization level of a table
CREATE FUNCTION check_normalization_level(
    target_schema VARCHAR(64),
    target_table VARCHAR(64)
) RETURNS VARCHAR(100)
DETERMINISTIC
BEGIN
    DECLARE has_repeating_groups BOOLEAN DEFAULT FALSE;
    DECLARE has_partial_deps BOOLEAN DEFAULT FALSE;
    DECLARE has_transitive_deps BOOLEAN DEFAULT FALSE;
    DECLARE has_multi_valued_deps BOOLEAN DEFAULT FALSE;
    DECLARE normalization_level VARCHAR(10);

    -- Simplified checks (would need more complex logic for real implementation)
    SELECT
        CASE WHEN COUNT(*) > 0 THEN TRUE ELSE FALSE END INTO has_repeating_groups
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = target_schema
      AND TABLE_NAME = target_table
      AND COLUMN_NAME LIKE '%\_%\_%';  -- Simple heuristic for repeating groups

    -- Check for potential transitive dependencies
    SELECT
        CASE WHEN COUNT(*) > 1 THEN TRUE ELSE FALSE END INTO has_transitive_deps
    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
    WHERE TABLE_SCHEMA = target_schema
      AND TABLE_NAME = target_table
      AND REFERENCED_TABLE_NAME IS NOT NULL;

    -- Determine normalization level
    IF has_repeating_groups THEN
        SET normalization_level = '0NF';
    ELSEIF has_transitive_deps THEN
        SET normalization_level = '1NF-2NF';
    ELSE
        SET normalization_level = '3NF+';
    END IF;

    RETURN CONCAT('Estimated normalization level: ', normalization_level);
END;;

-- Procedure to generate normalization recommendations
CREATE PROCEDURE generate_normalization_plan(IN target_schema VARCHAR(64), IN target_table VARCHAR(64))
BEGIN
    -- This would analyze the table structure and suggest normalization steps
    SELECT
        'Normalization Analysis for ' || target_schema || '.' || target_table as analysis_header,
        '1. Check for repeating groups in column names' as step_1,
        '2. Identify partial dependencies on composite keys' as step_2,
        '3. Remove transitive dependencies' as step_3,
        '4. Consider BCNF for complex dependencies' as step_4,
        '5. Evaluate 4NF for multi-valued dependencies' as step_5,
        '6. Consider denormalization for read-heavy workloads' as step_6
    UNION ALL
    SELECT '', '', '', '', '', '', ''
    UNION ALL
    SELECT 'Recommendations:', '', '', '', '', '', ''
    UNION ALL
    SELECT '- Extract repeating groups into separate tables', '', '', '', '', '', ''
    UNION ALL
    SELECT '- Create foreign key relationships', '', '', '', '', '', ''
    UNION ALL
    SELECT '- Add appropriate indexes for performance', '', '', '', '', '', ''
    UNION ALL
    SELECT '- Consider materialized views for complex queries', '', '', '', '', '', '';
END;;

DELIMITER ;

-- ===========================================
-- PRACTICAL NORMALIZATION WORKFLOW
-- =========================================--

/*
NORMALIZATION WORKFLOW:

1. Start with Unnormalized Data (0NF)
   - Identify repeating groups
   - Identify multivalued attributes

2. First Normal Form (1NF)
   - Eliminate repeating groups
   - Ensure atomic attributes
   - Create separate tables for related data

3. Second Normal Form (2NF)
   - Remove partial dependencies
   - Ensure all non-key attributes depend on entire primary key

4. Third Normal Form (3NF)
   - Remove transitive dependencies
   - Ensure non-key attributes depend directly on primary key

5. Boyce-Codd Normal Form (BCNF)
   - Remove remaining anomalies
   - Ensure every determinant is a candidate key

6. Fourth Normal Form (4NF)
   - Remove multi-valued dependencies
   - Ensure no independent multivalued attributes

7. Fifth Normal Form (5NF)
   - Remove join dependencies
   - Theoretical normalization (rarely needed)

WHEN TO DENORMALIZE:
- Read-heavy workloads with complex joins
- Real-time reporting requirements
- Performance-critical queries
- Data warehousing scenarios
- When normalization overhead exceeds benefits

BALANCING ACT:
- Normalization = Data integrity, flexibility, maintainability
- Denormalization = Query performance, simplicity
- Choose based on your specific use case and requirements
*/

-- ===========================================
-- EXAMPLE USAGE
-- =========================================--

/*
-- Check normalization level
SELECT check_normalization_level('your_database', 'customer_orders_denormalized');

-- Get normalization recommendations
CALL generate_normalization_plan('your_database', 'customer_orders_denormalized');

-- Example of proper normalized data insertion
INSERT INTO customers_3nf (customer_name, customer_email, customer_phone) VALUES
('John Doe', 'john@example.com', '+1-555-0123');

INSERT INTO addresses (customer_id, address_type, street_address, city, state_province, postal_code) VALUES
(LAST_INSERT_ID(), 'home', '123 Main St', 'Anytown', 'CA', '12345');

INSERT INTO products_3nf (product_name, sku, category_id, unit_price) VALUES
('Laptop', 'LT-001', 1, 999.99);

INSERT INTO orders_3nf (customer_id, shipping_address_id, billing_address_id) VALUES
(LAST_INSERT_ID(), LAST_INSERT_ID(), LAST_INSERT_ID());

This normalization guide demonstrates:
- Progressive normalization from 0NF to 5NF
- Practical examples with real-world scenarios
- When and how to denormalize for performance
- Utility functions for normalization analysis
- Proper indexing strategies for normalized schemas

Normalization ensures data integrity and reduces redundancy,
while denormalization can improve query performance for specific use cases.
*/
