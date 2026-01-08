-- Manufacturing & Production Database Schema
-- Comprehensive schema for manufacturing operations, supply chain management, and production tracking

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================
-- PRODUCT AND BILL OF MATERIALS
-- ===========================================

CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_code VARCHAR(50) UNIQUE NOT NULL,
    product_name VARCHAR(255) NOT NULL,

    -- Product Classification
    product_type VARCHAR(30) CHECK (product_type IN ('finished_good', 'component', 'subassembly', 'raw_material', 'consumable')),
    product_category VARCHAR(100),
    product_family VARCHAR(100),

    -- Product Details
    description TEXT,
    specifications JSONB DEFAULT '{}', -- Technical specifications
    dimensions JSONB DEFAULT '{}', -- Length, width, height, weight
    unit_of_measure VARCHAR(20) DEFAULT 'each',

    -- Lifecycle Management
    product_status VARCHAR(20) DEFAULT 'active' CHECK (product_status IN ('development', 'active', 'obsolete', 'discontinued')),
    introduced_date DATE,
    discontinued_date DATE,

    -- Quality and Compliance
    quality_standard VARCHAR(50), -- ISO 9001, etc.
    certifications TEXT[], -- Safety, environmental certifications
    regulatory_requirements TEXT[],

    -- Cost and Pricing
    standard_cost DECIMAL(12,2),
    selling_price DECIMAL(12,2),
    currency_code CHAR(3) DEFAULT 'USD',

    -- Inventory Management
    reorder_point INTEGER,
    safety_stock INTEGER,
    lead_time_days INTEGER,

    -- Images and Documentation
    primary_image_url VARCHAR(500),
    technical_drawings JSONB DEFAULT '[]', -- Array of drawing URLs
    documentation_urls JSONB DEFAULT '[]',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE bill_of_materials (
    bom_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_product_id UUID NOT NULL REFERENCES products(product_id),
    bom_version VARCHAR(20) NOT NULL DEFAULT '1.0',

    -- BOM Details
    bom_name VARCHAR(255),
    bom_description TEXT,
    effective_date DATE DEFAULT CURRENT_DATE,
    expiration_date DATE,

    -- Status and Approval
    bom_status VARCHAR(20) DEFAULT 'draft' CHECK (bom_status IN ('draft', 'review', 'approved', 'obsolete')),
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,

    -- Cost Rollup
    total_cost DECIMAL(12,2),
    total_weight DECIMAL(8,2),
    total_volume DECIMAL(10,2),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (parent_product_id, bom_version)
);

CREATE TABLE bom_components (
    component_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bom_id UUID NOT NULL REFERENCES bill_of_materials(bom_id) ON DELETE CASCADE,
    component_product_id UUID NOT NULL REFERENCES products(product_id),

    -- Component Details
    quantity_required DECIMAL(10,4) NOT NULL,
    unit_of_measure VARCHAR(20) DEFAULT 'each',
    reference_designator VARCHAR(50), -- For PCB assemblies, etc.

    -- Procurement
    procurement_type VARCHAR(20) DEFAULT 'manufactured' CHECK (procurement_type IN ('manufactured', 'purchased', 'subcontracted')),
    supplier_id UUID, -- References suppliers table
    lead_time_days INTEGER,

    -- Cost and Scrap
    unit_cost DECIMAL(10,2),
    scrap_factor DECIMAL(5,2) DEFAULT 0, -- Percentage waste/scrap

    -- Position in BOM
    sequence_number INTEGER,
    level INTEGER DEFAULT 1, -- BOM level (1 = top level, 2 = subassembly, etc.)

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity_required > 0),
    CHECK (scrap_factor >= 0 AND scrap_factor < 1)
);

-- ===========================================
-- PRODUCTION PLANNING AND SCHEDULING
-- ===========================================

CREATE TABLE production_orders (
    production_order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number VARCHAR(30) UNIQUE NOT NULL,

    -- Order Details
    product_id UUID NOT NULL REFERENCES products(product_id),
    bom_id UUID REFERENCES bill_of_materials(bom_id),
    quantity_ordered INTEGER NOT NULL,

    -- Scheduling
    planned_start_date DATE,
    planned_completion_date DATE,
    actual_start_date DATE,
    actual_completion_date DATE,

    -- Status and Priority
    order_status VARCHAR(30) DEFAULT 'planned' CHECK (order_status IN (
        'planned', 'released', 'in_progress', 'completed', 'cancelled', 'on_hold'
    )),
    priority_level VARCHAR(10) DEFAULT 'normal' CHECK (priority_level IN ('low', 'normal', 'high', 'urgent')),

    -- Production Details
    production_line_id UUID, -- References production lines
    work_center_id UUID, -- References work centers
    routing_id UUID, -- References production routing

    -- Cost and Efficiency
    planned_cost DECIMAL(12,2),
    actual_cost DECIMAL(12,2),
    efficiency_percentage DECIMAL(5,2),

    -- Quality Control
    quality_plan_id UUID, -- References quality plans
    inspection_required BOOLEAN DEFAULT TRUE,

    -- Customer and Sales Order
    sales_order_id UUID, -- References sales orders
    customer_id UUID, -- References customers

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity_ordered > 0)
);

CREATE TABLE work_orders (
    work_order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    production_order_id UUID NOT NULL REFERENCES production_orders(production_order_id) ON DELETE CASCADE,

    -- Work Order Details
    work_order_number VARCHAR(30) UNIQUE NOT NULL,
    operation_sequence INTEGER NOT NULL,
    operation_description TEXT,

    -- Operation Details
    work_center_id UUID NOT NULL,
    machine_id UUID,
    labor_skill_required VARCHAR(50),

    -- Time and Resources
    planned_setup_time DECIMAL(6,2), -- Hours
    planned_run_time DECIMAL(6,2), -- Hours per unit
    planned_labor_hours DECIMAL(6,2),
    planned_machine_hours DECIMAL(6,2),

    -- Actual Times
    actual_setup_time DECIMAL(6,2),
    actual_run_time DECIMAL(6,2),
    actual_labor_hours DECIMAL(6,2),
    actual_machine_hours DECIMAL(6,2),

    -- Status and Progress
    work_order_status VARCHAR(20) DEFAULT 'pending' CHECK (work_order_status IN (
        'pending', 'setup', 'running', 'completed', 'scrapped', 'reworked'
    )),
    quantity_completed INTEGER DEFAULT 0,
    quantity_scrapped INTEGER DEFAULT 0,
    quantity_reworked INTEGER DEFAULT 0,

    -- Quality
    quality_check_required BOOLEAN DEFAULT TRUE,
    quality_check_passed BOOLEAN,

    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- INVENTORY AND MATERIAL MANAGEMENT
-- ===========================================

CREATE TABLE inventory_locations (
    location_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    location_code VARCHAR(20) UNIQUE NOT NULL,
    location_name VARCHAR(255) NOT NULL,

    -- Location Hierarchy
    parent_location_id UUID REFERENCES inventory_locations(location_id),
    location_type VARCHAR(30) CHECK (location_type IN (
        'warehouse', 'production_floor', 'receiving', 'shipping',
        'quarantine', 'scrap', 'subcontractor'
    )),
    location_category VARCHAR(20) CHECK (location_category IN ('internal', 'external', 'virtual')),

    -- Physical Details
    address JSONB,
    capacity_cubic_meters DECIMAL(10,2),
    capacity_weight_kg DECIMAL(10,2),

    -- Operational Details
    is_active BOOLEAN DEFAULT TRUE,
    temperature_controlled BOOLEAN DEFAULT FALSE,
    humidity_controlled BOOLEAN DEFAULT FALSE,
    security_level VARCHAR(20) CHECK (security_level IN ('low', 'medium', 'high', 'restricted')),

    -- Contact Information
    responsible_person VARCHAR(255),
    contact_phone VARCHAR(20),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE inventory_items (
    inventory_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(product_id),
    location_id UUID NOT NULL REFERENCES inventory_locations(location_id),

    -- Inventory Details
    lot_number VARCHAR(50),
    serial_number VARCHAR(100),
    batch_number VARCHAR(50),
    expiration_date DATE,

    -- Quantities
    quantity_on_hand DECIMAL(12,4) DEFAULT 0,
    quantity_reserved DECIMAL(12,4) DEFAULT 0,
    quantity_available DECIMAL(12,4) GENERATED ALWAYS AS (quantity_on_hand - quantity_reserved) STORED,

    -- Cost and Valuation
    unit_cost DECIMAL(10,2),
    total_value DECIMAL(12,2) GENERATED ALWAYS AS (quantity_on_hand * unit_cost) STORED,

    -- Quality and Condition
    quality_status VARCHAR(20) DEFAULT 'good' CHECK (quality_status IN ('good', 'fair', 'poor', 'quarantine', 'scrap')),
    condition_notes TEXT,

    -- Tracking
    received_date DATE DEFAULT CURRENT_DATE,
    last_movement_date DATE,
    last_count_date DATE,

    -- Supplier Information
    supplier_id UUID,
    supplier_lot_number VARCHAR(50),
    purchase_order_id UUID,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (product_id, location_id, lot_number)
);

CREATE TABLE inventory_transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Transaction Details
    transaction_type VARCHAR(30) NOT NULL CHECK (transaction_type IN (
        'receipt', 'issue', 'transfer', 'adjustment', 'scrap', 'count'
    )),
    transaction_reference VARCHAR(50), -- PO number, WO number, etc.

    -- Source and Destination
    source_location_id UUID REFERENCES inventory_locations(location_id),
    destination_location_id UUID REFERENCES inventory_locations(location_id),
    product_id UUID NOT NULL REFERENCES products(product_id),

    -- Quantities
    quantity DECIMAL(12,4) NOT NULL,
    unit_cost DECIMAL(10,2),

    -- Transaction Details
    transaction_date DATE DEFAULT CURRENT_DATE,
    lot_number VARCHAR(50),
    reason_code VARCHAR(20), -- Adjustment reason, etc.

    -- Related Documents
    purchase_order_id UUID,
    sales_order_id UUID,
    production_order_id UUID,
    work_order_id UUID,

    -- Authorization
    authorized_by UUID,
    approved_by UUID,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CHECK (quantity != 0)
);

-- ===========================================
-- SUPPLY CHAIN AND VENDOR MANAGEMENT
-- ===========================================

CREATE TABLE suppliers (
    supplier_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_code VARCHAR(20) UNIQUE NOT NULL,
    supplier_name VARCHAR(255) NOT NULL,

    -- Supplier Classification
    supplier_type VARCHAR(30) CHECK (supplier_type IN ('manufacturer', 'distributor', 'raw_material', 'service', 'subcontractor')),
    supplier_category VARCHAR(50),
    criticality_level VARCHAR(10) CHECK (criticality_level IN ('low', 'medium', 'high', 'critical')),

    -- Contact Information
    contact_person VARCHAR(255),
    email VARCHAR(255),
    phone VARCHAR(20),
    fax VARCHAR(20),
    address JSONB,

    -- Supplier Performance
    on_time_delivery_rate DECIMAL(5,2), -- Percentage
    quality_rating DECIMAL(3,1), -- 1.0 to 5.0
    responsiveness_rating DECIMAL(3,1),
    overall_rating DECIMAL(3,1) GENERATED ALWAYS AS (
        (COALESCE(on_time_delivery_rate, 0) + COALESCE(quality_rating, 0) * 20 +
         COALESCE(responsiveness_rating, 0) * 20) / 100
    ) STORED,

    -- Financial Information
    payment_terms VARCHAR(50) DEFAULT 'net_30',
    credit_limit DECIMAL(12,2),
    current_balance DECIMAL(10,2),

    -- Certifications and Compliance
    certifications TEXT[], -- ISO, safety, quality certifications
    insurance_coverage DECIMAL(12,2),
    insurance_expiry DATE,

    -- Status
    supplier_status VARCHAR(20) DEFAULT 'active' CHECK (supplier_status IN ('active', 'inactive', 'suspended', 'terminated')),
    approved_date DATE,
    last_review_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE purchase_orders (
    purchase_order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_number VARCHAR(30) UNIQUE NOT NULL,

    -- Order Details
    supplier_id UUID NOT NULL REFERENCES suppliers(supplier_id),
    order_date DATE DEFAULT CURRENT_DATE,
    required_date DATE,

    -- Order Status
    po_status VARCHAR(20) DEFAULT 'draft' CHECK (po_status IN (
        'draft', 'approved', 'sent', 'confirmed', 'partially_received',
        'received', 'cancelled', 'closed'
    )),

    -- Financial
    subtotal DECIMAL(12,2),
    tax_amount DECIMAL(12,2),
    total_amount DECIMAL(12,2),

    -- Shipping and Terms
    ship_to_location_id UUID REFERENCES inventory_locations(location_id),
    shipping_terms VARCHAR(100),
    payment_terms VARCHAR(50),

    -- Approval and Processing
    requested_by UUID,
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,

    -- Delivery Tracking
    expected_delivery_date DATE,
    actual_delivery_date DATE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE purchase_order_lines (
    po_line_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(purchase_order_id) ON DELETE CASCADE,

    -- Line Details
    line_number INTEGER NOT NULL,
    product_id UUID NOT NULL REFERENCES products(product_id),
    quantity_ordered DECIMAL(10,4) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,

    -- Line Amounts
    line_total DECIMAL(12,2) GENERATED ALWAYS AS (quantity_ordered * unit_price) STORED,

    -- Delivery Schedule
    required_date DATE,
    promised_date DATE,

    -- Receiving
    quantity_received DECIMAL(10,4) DEFAULT 0,
    quantity_rejected DECIMAL(10,4) DEFAULT 0,

    -- Status
    line_status VARCHAR(20) DEFAULT 'open' CHECK (line_status IN ('open', 'partially_received', 'received', 'cancelled')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (purchase_order_id, line_number)
);

-- ===========================================
-- QUALITY MANAGEMENT AND CONTROL
-- ===========================================

CREATE TABLE quality_plans (
    quality_plan_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_name VARCHAR(255) NOT NULL,
    plan_description TEXT,

    -- Applicable Products/Processes
    applicable_products UUID[], -- Array of product IDs
    applicable_processes TEXT[], -- Process names

    -- Quality Requirements
    quality_standards TEXT[], -- Required standards
    inspection_criteria JSONB NOT NULL, -- Detailed inspection requirements

    -- Sampling Plan
    sampling_method VARCHAR(30) CHECK (sampling_method IN ('fixed', 'percentage', 'aql', 'custom')),
    sample_size INTEGER,
    acceptance_criteria VARCHAR(100),

    -- Status
    plan_status VARCHAR(20) DEFAULT 'active' CHECK (plan_status IN ('draft', 'active', 'obsolete')),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE quality_inspections (
    inspection_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Inspection Details
    inspection_type VARCHAR(30) CHECK (inspection_type IN (
        'incoming', 'in_process', 'final', 'audit', 'calibration'
    )),
    inspection_number VARCHAR(30) UNIQUE NOT NULL,

    -- Related Entities
    product_id UUID REFERENCES products(product_id),
    supplier_id UUID REFERENCES suppliers(supplier_id),
    production_order_id UUID REFERENCES production_orders(production_order_id),
    work_order_id UUID REFERENCES work_orders(work_order_id),

    -- Inspection Details
    inspection_date DATE DEFAULT CURRENT_DATE,
    inspector_id UUID,
    quality_plan_id UUID REFERENCES quality_plans(quality_plan_id),

    -- Results
    sample_size INTEGER,
    defects_found INTEGER DEFAULT 0,
    inspection_result VARCHAR(20) CHECK (inspection_result IN ('pass', 'fail', 'conditional', 'pending')),

    -- Detailed Findings
    inspection_findings JSONB DEFAULT '{}',
    corrective_actions_required TEXT,
    corrective_actions_taken TEXT,

    -- Follow-up
    follow_up_required BOOLEAN DEFAULT FALSE,
    follow_up_date DATE,
    follow_up_completed BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- EQUIPMENT AND MAINTENANCE
-- ===========================================

CREATE TABLE equipment (
    equipment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    equipment_code VARCHAR(20) UNIQUE NOT NULL,
    equipment_name VARCHAR(255) NOT NULL,

    -- Equipment Details
    equipment_type VARCHAR(50) NOT NULL,
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    serial_number VARCHAR(100),

    -- Location and Ownership
    location_id UUID REFERENCES inventory_locations(location_id),
    department VARCHAR(50),
    responsible_person VARCHAR(255),

    -- Technical Specifications
    specifications JSONB DEFAULT '{}',
    power_requirements VARCHAR(100),
    operating_temperature_range VARCHAR(50),

    -- Maintenance and Calibration
    maintenance_schedule JSONB DEFAULT '{}', -- Preventive maintenance schedule
    calibration_required BOOLEAN DEFAULT FALSE,
    calibration_interval_months INTEGER,
    last_calibration_date DATE,
    next_calibration_date DATE,

    -- Status and Condition
    equipment_status VARCHAR(20) DEFAULT 'operational' CHECK (equipment_status IN (
        'operational', 'maintenance', 'repair', 'calibration', 'down', 'retired'
    )),
    condition_rating INTEGER CHECK (condition_rating BETWEEN 1 AND 5), -- 1=poor, 5=excellent

    -- Financial
    acquisition_cost DECIMAL(12,2),
    acquisition_date DATE,
    depreciation_method VARCHAR(30),
    current_value DECIMAL(12,2),

    -- Operational Metrics
    operating_hours DECIMAL(10,2) DEFAULT 0,
    maintenance_cost_ytd DECIMAL(10,2) DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE maintenance_work_orders (
    maintenance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    equipment_id UUID NOT NULL REFERENCES equipment(equipment_id),

    -- Maintenance Details
    maintenance_type VARCHAR(30) CHECK (maintenance_type IN ('preventive', 'corrective', 'predictive', 'calibration')),
    priority_level VARCHAR(10) CHECK (priority_level IN ('low', 'normal', 'high', 'critical')),

    -- Scheduling
    scheduled_date DATE,
    completed_date DATE,
    estimated_duration_hours DECIMAL(4,2),

    -- Work Details
    work_description TEXT,
    parts_required JSONB DEFAULT '[]',
    labor_required DECIMAL(4,2), -- Hours

    -- Status and Results
    maintenance_status VARCHAR(20) DEFAULT 'scheduled' CHECK (maintenance_status IN (
        'scheduled', 'in_progress', 'completed', 'cancelled', 'deferred'
    )),
    work_performed TEXT,
    findings TEXT,

    -- Cost Tracking
    parts_cost DECIMAL(8,2) DEFAULT 0,
    labor_cost DECIMAL(8,2) DEFAULT 0,
    total_cost DECIMAL(8,2) GENERATED ALWAYS AS (parts_cost + labor_cost) STORED,

    -- Quality Control
    quality_check_passed BOOLEAN,
    next_maintenance_date DATE,

    -- Assignment
    assigned_technician VARCHAR(255),
    approved_by VARCHAR(255),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ===========================================
-- PRODUCTION METRICS AND ANALYTICS
-- ===========================================

CREATE TABLE production_metrics (
    metric_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    production_order_id UUID REFERENCES production_orders(production_order_id),
    work_order_id UUID REFERENCES work_orders(work_order_id),
    equipment_id UUID REFERENCES equipment(equipment_id),

    -- Metric Details
    metric_type VARCHAR(50) NOT NULL CHECK (metric_type IN (
        'cycle_time', 'setup_time', 'downtime', 'yield', 'quality',
        'efficiency', 'utilization', 'throughput', 'defect_rate'
    )),
    metric_name VARCHAR(100),
    metric_value DECIMAL(12,4),
    metric_unit VARCHAR(20),

    -- Time Context
    metric_date DATE DEFAULT CURRENT_DATE,
    metric_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Additional Context
    batch_number VARCHAR(50),
    shift VARCHAR(20),
    operator_id UUID,

    -- Quality Context
    quality_grade VARCHAR(10),
    defect_category VARCHAR(50),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (metric_timestamp);

-- Partitioning by month for time-series metrics
CREATE TABLE production_metrics_2024_01 PARTITION OF production_metrics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- ===========================================
-- INDEXES FOR PERFORMANCE
-- ===========================================

-- Product and BOM indexes
CREATE INDEX idx_products_category_status ON products (product_category, product_status);
CREATE INDEX idx_bom_components_bom ON bom_components (bom_id);
CREATE INDEX idx_bom_components_product ON bom_components (component_product_id);

-- Production indexes
CREATE INDEX idx_production_orders_product ON production_orders (product_id);
CREATE INDEX idx_production_orders_status ON production_orders (order_status);
CREATE INDEX idx_production_orders_dates ON production_orders (planned_start_date, planned_completion_date);
CREATE INDEX idx_work_orders_production ON work_orders (production_order_id);
CREATE INDEX idx_work_orders_status ON work_orders (work_order_status);

-- Inventory indexes
CREATE INDEX idx_inventory_items_product_location ON inventory_items (product_id, location_id);
CREATE INDEX idx_inventory_items_expiration ON inventory_items (expiration_date) WHERE expiration_date IS NOT NULL;
CREATE INDEX idx_inventory_transactions_product ON inventory_transactions (product_id, transaction_date DESC);
CREATE INDEX idx_inventory_transactions_date ON inventory_transactions (transaction_date DESC);

-- Supplier indexes
CREATE INDEX idx_suppliers_type_status ON suppliers (supplier_type, supplier_status);
CREATE INDEX idx_purchase_orders_supplier ON purchase_orders (supplier_id);
CREATE INDEX idx_purchase_orders_status ON purchase_orders (po_status);
CREATE INDEX idx_po_lines_po ON purchase_order_lines (purchase_order_id);

-- Quality indexes
CREATE INDEX idx_quality_inspections_product ON quality_inspections (product_id);
CREATE INDEX idx_quality_inspections_result ON quality_inspections (inspection_result);
CREATE INDEX idx_quality_inspections_date ON quality_inspections (inspection_date DESC);

-- Equipment indexes
CREATE INDEX idx_equipment_type_status ON equipment (equipment_type, equipment_status);
CREATE INDEX idx_equipment_location ON equipment (location_id);
CREATE INDEX idx_maintenance_equipment ON maintenance_work_orders (equipment_id);
CREATE INDEX idx_maintenance_status ON maintenance_work_orders (maintenance_status);

-- ===========================================
-- USEFUL VIEWS
-- ===========================================

-- BOM explosion view (showing all levels)
CREATE VIEW bom_explosion AS
WITH RECURSIVE bom_tree AS (
    -- Base level components
    SELECT
        bc.component_id,
        bc.bom_id,
        bc.component_product_id,
        bc.quantity_required,
        bc.level,
        bc.component_product_id as root_product_id,
        ARRAY[bc.component_product_id] as path,
        bc.quantity_required as total_quantity
    FROM bom_components bc
    WHERE bc.level = 1

    UNION ALL

    -- Recursive BOM explosion
    SELECT
        bc.component_id,
        bc.bom_id,
        bc.component_product_id,
        bc.quantity_required,
        bc.level,
        bt.root_product_id,
        bt.path || bc.component_product_id,
        bt.total_quantity * bc.quantity_required
    FROM bom_components bc
    JOIN bom_tree bt ON bc.bom_id IN (
        SELECT b.bom_id FROM bill_of_materials b
        WHERE b.parent_product_id = bt.component_product_id
    )
    WHERE bc.level > 1
)
SELECT * FROM bom_tree;

-- Inventory valuation summary
CREATE VIEW inventory_valuation AS
SELECT
    ii.product_id,
    p.product_name,
    p.product_category,
    il.location_name,

    -- Quantities
    SUM(ii.quantity_on_hand) as total_on_hand,
    SUM(ii.quantity_available) as total_available,
    SUM(ii.quantity_reserved) as total_reserved,

    -- Valuation
    AVG(ii.unit_cost) as avg_unit_cost,
    SUM(ii.total_value) as total_value,
    MIN(ii.expiration_date) as earliest_expiration,

    -- Location breakdown
    COUNT(DISTINCT ii.location_id) as locations_count,
    STRING_AGG(DISTINCT il.location_code, ', ') as location_codes

FROM inventory_items ii
JOIN products p ON ii.product_id = p.product_id
JOIN inventory_locations il ON ii.location_id = il.location_id
WHERE ii.quantity_on_hand > 0
GROUP BY ii.product_id, p.product_name, p.product_category, il.location_name;

-- Production efficiency dashboard
CREATE VIEW production_efficiency AS
SELECT
    po.production_order_id,
    po.order_number,
    p.product_name,
    po.quantity_ordered,
    po.order_status,

    -- Time metrics
    po.planned_completion_date - po.planned_start_date as planned_duration,
    CASE WHEN po.actual_completion_date IS NOT NULL AND po.actual_start_date IS NOT NULL
         THEN po.actual_completion_date - po.actual_start_date
         ELSE NULL END as actual_duration,

    -- Efficiency calculations
    CASE WHEN po.actual_completion_date IS NOT NULL
         THEN ROUND(
             EXTRACT(EPOCH FROM (po.planned_completion_date - po.planned_start_date)) /
             NULLIF(EXTRACT(EPOCH FROM (po.actual_completion_date - po.actual_start_date)), 0) * 100, 2
         )
         ELSE NULL END as schedule_efficiency,

    -- Cost metrics
    po.planned_cost,
    po.actual_cost,
    CASE WHEN po.planned_cost > 0
         THEN ROUND((po.actual_cost / po.planned_cost) * 100, 2)
         ELSE NULL END as cost_variance_percentage,

    -- Work order summary
    COUNT(wo.work_order_id) as total_work_orders,
    COUNT(CASE WHEN wo.work_order_status = 'completed' THEN 1 END) as completed_work_orders,
    SUM(wo.quantity_completed) as total_quantity_completed,
    SUM(wo.quantity_scrapped) as total_quantity_scrapped

FROM production_orders po
JOIN products p ON po.product_id = p.product_id
LEFT JOIN work_orders wo ON po.production_order_id = wo.production_order_id
GROUP BY po.production_order_id, po.order_number, p.product_name,
         po.quantity_ordered, po.order_status, po.planned_start_date,
         po.planned_completion_date, po.actual_start_date,
         po.actual_completion_date, po.planned_cost, po.actual_cost;

-- Supplier performance dashboard
CREATE VIEW supplier_performance AS
SELECT
    s.supplier_id,
    s.supplier_name,
    s.supplier_type,
    s.overall_rating,

    -- Delivery performance
    s.on_time_delivery_rate,
    COUNT(po.purchase_order_id) as total_orders,
    COUNT(CASE WHEN po.actual_delivery_date <= po.expected_delivery_date THEN 1 END) as on_time_deliveries,

    -- Quality metrics
    s.quality_rating,
    COUNT(qi.inspection_id) as total_inspections,
    COUNT(CASE WHEN qi.inspection_result = 'pass' THEN 1 END) as passed_inspections,

    -- Financial metrics
    SUM(po.total_amount) as total_spend,
    AVG(po.total_amount) as avg_order_value,
    s.current_balance,

    -- Recent activity
    MAX(po.order_date) as last_order_date,
    COUNT(CASE WHEN po.order_date >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as orders_last_90_days

FROM suppliers s
LEFT JOIN purchase_orders po ON s.supplier_id = po.supplier_id
LEFT JOIN quality_inspections qi ON s.supplier_id = qi.supplier_id
WHERE s.supplier_status = 'active'
GROUP BY s.supplier_id, s.supplier_name, s.supplier_type, s.overall_rating,
         s.on_time_delivery_rate, s.quality_rating, s.current_balance;

-- ===========================================
-- FUNCTIONS FOR MANUFACTURING OPERATIONS
-- =========================================--

-- Function to calculate BOM cost rollup
CREATE OR REPLACE FUNCTION calculate_bom_cost(bom_uuid UUID)
RETURNS DECIMAL AS $$
DECLARE
    total_cost DECIMAL := 0;
BEGIN
    WITH RECURSIVE bom_cost AS (
        -- Base components
        SELECT
            bc.component_product_id,
            bc.quantity_required,
            p.standard_cost,
            bc.quantity_required * p.standard_cost as component_cost,
            1 as level
        FROM bom_components bc
        JOIN products p ON bc.component_product_id = p.product_id
        WHERE bc.bom_id = bom_uuid

        UNION ALL

        -- Subassembly costs
        SELECT
            bc.component_product_id,
            bc.quantity_required,
            p.standard_cost,
            bc.quantity_required * (
                SELECT COALESCE(SUM(component_cost), p.standard_cost)
                FROM bom_components bc2
                JOIN products p2 ON bc2.component_product_id = p2.product_id
                WHERE bc2.bom_id IN (
                    SELECT bom_id FROM bill_of_materials
                    WHERE parent_product_id = bc.component_product_id
                )
            ),
            bc.level
        FROM bom_components bc
        JOIN products p ON bc.component_product_id = p.product_id
        JOIN bom_cost bcost ON bc.component_product_id = bcost.component_product_id
        WHERE bc.bom_id = bom_uuid AND bc.level > 1
    )
    SELECT SUM(component_cost) INTO total_cost
    FROM bom_cost;

    RETURN total_cost;
END;
$$ LANGUAGE plpgsql;

-- Function to update inventory quantities
CREATE OR REPLACE FUNCTION update_inventory_quantity(
    product_uuid UUID,
    location_uuid UUID,
    quantity_change DECIMAL,
    transaction_type VARCHAR,
    reference_number VARCHAR DEFAULT NULL
)
RETURNS DECIMAL AS $$
DECLARE
    current_quantity DECIMAL;
    new_quantity DECIMAL;
BEGIN
    -- Get current quantity
    SELECT quantity_on_hand INTO current_quantity
    FROM inventory_items
    WHERE product_id = product_uuid AND location_id = location_uuid;

    IF NOT FOUND THEN
        -- Create new inventory item if it doesn't exist
        INSERT INTO inventory_items (product_id, location_id, quantity_on_hand)
        VALUES (product_uuid, location_uuid, GREATEST(quantity_change, 0));
        new_quantity := GREATEST(quantity_change, 0);
    ELSE
        -- Update existing quantity
        new_quantity := current_quantity + quantity_change;
        UPDATE inventory_items
        SET quantity_on_hand = new_quantity,
            last_movement_date = CURRENT_DATE,
            updated_at = CURRENT_TIMESTAMP
        WHERE product_id = product_uuid AND location_id = location_uuid;
    END IF;

    -- Log transaction
    INSERT INTO inventory_transactions (
        transaction_type, transaction_reference,
        source_location_id, destination_location_id, product_id,
        quantity, transaction_date
    ) VALUES (
        transaction_type, reference_number,
        CASE WHEN quantity_change < 0 THEN location_uuid ELSE NULL END,
        CASE WHEN quantity_change > 0 THEN location_uuid ELSE NULL END,
        product_uuid, ABS(quantity_change), CURRENT_DATE
    );

    RETURN new_quantity;
END;
$$ LANGUAGE plpgsql;

-- Function to check material availability for production
CREATE OR REPLACE FUNCTION check_material_availability(production_order_uuid UUID)
RETURNS TABLE (
    component_product_id UUID,
    component_name VARCHAR,
    required_quantity DECIMAL,
    available_quantity DECIMAL,
    shortage_quantity DECIMAL,
    availability_status VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        bc.component_product_id,
        p.product_name,
        bc.quantity_required * po.quantity_ordered as required_quantity,
        COALESCE(SUM(ii.quantity_available), 0) as available_quantity,
        GREATEST(0, (bc.quantity_required * po.quantity_ordered) - COALESCE(SUM(ii.quantity_available), 0)) as shortage_quantity,
        CASE
            WHEN COALESCE(SUM(ii.quantity_available), 0) >= (bc.quantity_required * po.quantity_ordered) THEN 'available'
            WHEN COALESCE(SUM(ii.quantity_available), 0) > 0 THEN 'partial'
            ELSE 'unavailable'
        END as availability_status
    FROM production_orders po
    JOIN bill_of_materials bom ON po.bom_id = bom.bom_id
    JOIN bom_components bc ON bom.bom_id = bc.bom_id
    JOIN products p ON bc.component_product_id = p.product_id
    LEFT JOIN inventory_items ii ON bc.component_product_id = ii.product_id
    WHERE po.production_order_id = production_order_uuid
    GROUP BY bc.component_product_id, p.product_name, bc.quantity_required, po.quantity_ordered;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- SAMPLE DATA INSERTION
-- ===========================================

-- Insert sample product
INSERT INTO products (
    product_code, product_name, product_type, product_category,
    description, standard_cost, reorder_point
) VALUES (
    'WIDGET-001', 'Standard Widget', 'finished_good', 'electronics',
    'A standard widget for industrial use', 25.50, 100
);

-- Insert BOM for the widget
INSERT INTO bill_of_materials (parent_product_id, bom_name, bom_status) VALUES
((SELECT product_id FROM products WHERE product_code = 'WIDGET-001' LIMIT 1), 'Widget BOM v1.0', 'approved');

-- Insert BOM components
INSERT INTO bom_components (bom_id, component_product_id, quantity_required, procurement_type) VALUES
((SELECT bom_id FROM bill_of_materials WHERE bom_name = 'Widget BOM v1.0' LIMIT 1),
 (SELECT product_id FROM products WHERE product_code = 'WIDGET-001' LIMIT 1), 1, 'manufactured');

-- Insert sample production order
INSERT INTO production_orders (
    order_number, product_id, bom_id, quantity_ordered,
    planned_start_date, planned_completion_date
) VALUES (
    'PROD-001', 
    (SELECT product_id FROM products WHERE product_code = 'WIDGET-001' LIMIT 1),
    (SELECT bom_id FROM bill_of_materials WHERE bom_name = 'Widget BOM v1.0' LIMIT 1),
    100, '2024-01-15', '2024-01-20'
);

-- Insert sample supplier
INSERT INTO suppliers (supplier_code, supplier_name, supplier_type, contact_person) VALUES
('SUP-001', 'Global Components Inc.', 'manufacturer', 'John Smith');

-- This manufacturing schema provides comprehensive infrastructure for production planning,
-- inventory management, quality control, and supply chain operations.
