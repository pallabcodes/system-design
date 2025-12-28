# Manufacturing & Production Database Design

## Overview

This comprehensive database schema supports manufacturing operations including production planning, inventory management, bill of materials (BOM), quality control, equipment maintenance, and supply chain management. The design handles complex manufacturing workflows with multi-level BOMs, production scheduling, and real-time inventory tracking.

## Key Features

### 🏭 Production Planning & Execution
- **Multi-level bill of materials (BOM)** with cost rollup and material requirements planning
- **Production order management** with work orders and operation sequencing
- **Capacity planning** and production scheduling with resource allocation
- **Work-in-progress (WIP)** tracking and production efficiency metrics

### 📦 Inventory & Material Management
- **Multi-location inventory** with lot and serial number tracking
- **Real-time inventory transactions** with audit trails
- **Material requirements planning (MRP)** integration
- **Inventory optimization** with reorder points and safety stock

### 🔧 Quality Control & Assurance
- **Quality inspection plans** with sampling and acceptance criteria
- **Defect tracking** and corrective action management
- **Supplier quality performance** monitoring
- **Compliance and certification** management

### 🔄 Supply Chain Management
- **Supplier performance tracking** and vendor rating systems
- **Purchase order processing** with approval workflows
- **Receiving and inspection** integration
- **Vendor managed inventory** support

## Database Schema Highlights

### Core Tables

#### Product Management
- **`products`** - Product catalog with specifications and lifecycle management
- **`bill_of_materials`** - Multi-level BOM with version control and cost rollup
- **`bom_components`** - BOM component details with procurement and costing

#### Production Management
- **`production_orders`** - Production order lifecycle and scheduling
- **`work_orders`** - Detailed work order execution and time tracking
- **`production_metrics`** - Real-time production performance data

#### Inventory Management
- **`inventory_locations`** - Multi-level warehouse and location management
- **`inventory_items`** - Detailed inventory tracking with lots and conditions
- **`inventory_transactions`** - Complete transaction audit trail

#### Supplier Management
- **`suppliers`** - Supplier profiles with performance ratings
- **`purchase_orders`** - Purchase order processing and tracking
- **`purchase_order_lines`** - Detailed line item management

#### Quality Management
- **`quality_plans`** - Inspection plans and quality requirements
- **`quality_inspections`** - Inspection results and findings
- **`maintenance_work_orders`** - Equipment maintenance and calibration

## Key Design Patterns

### 1. Multi-Level BOM Explosion
```sql
-- Recursive BOM explosion for material requirements planning
WITH RECURSIVE bom_explosion AS (
    -- Top-level components
    SELECT
        bc.component_product_id,
        bc.quantity_required as required_qty,
        1 as level,
        ARRAY[bc.component_product_id] as path
    FROM bom_components bc
    WHERE bc.bom_id = ? AND bc.level = 1

    UNION ALL

    -- Sub-assembly explosion
    SELECT
        bc.component_product_id,
        be.required_qty * bc.quantity_required as required_qty,
        be.level + 1,
        be.path || bc.component_product_id
    FROM bom_components bc
    JOIN bom_explosion be ON bc.bom_id IN (
        SELECT bom_id FROM bill_of_materials
        WHERE parent_product_id = be.component_product_id
    )
    WHERE bc.level > 1
)
SELECT
    p.product_name,
    be.required_qty * ? as total_required,  -- Multiply by production quantity
    ii.quantity_available,
    CASE WHEN ii.quantity_available >= (be.required_qty * ?) THEN 'Available'
         ELSE 'Shortage' END as availability_status
FROM bom_explosion be
JOIN products p ON be.component_product_id = p.product_id
LEFT JOIN inventory_items ii ON p.product_id = ii.product_id;
```

### 2. Production Order Lifecycle Management
```sql
-- Production order status progression with validation
CREATE OR REPLACE FUNCTION update_production_order_status(
    order_uuid UUID,
    new_status VARCHAR,
    notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    current_status VARCHAR;
    order_record production_orders%ROWTYPE;
BEGIN
    -- Get current order details
    SELECT * INTO order_record FROM production_orders
    WHERE production_order_id = order_uuid;

    current_status := order_record.order_status;

    -- Validate status transitions
    CASE current_status
        WHEN 'planned' THEN
            IF new_status NOT IN ('released', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid transition from planned to %', new_status;
            END IF;
        WHEN 'released' THEN
            IF new_status NOT IN ('in_progress', 'cancelled', 'on_hold') THEN
                RAISE EXCEPTION 'Invalid transition from released to %', new_status;
            END IF;
        WHEN 'in_progress' THEN
            IF new_status NOT IN ('completed', 'cancelled', 'on_hold') THEN
                RAISE EXCEPTION 'Invalid transition from in_progress to %', new_status;
            END IF;
        WHEN 'on_hold' THEN
            IF new_status NOT IN ('released', 'in_progress', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid transition from on_hold to %', new_status;
            END IF;
    END CASE;

    -- Update order
    UPDATE production_orders SET
        order_status = new_status,
        actual_start_date = CASE WHEN new_status = 'in_progress' AND actual_start_date IS NULL
                                THEN CURRENT_DATE ELSE actual_start_date END,
        actual_completion_date = CASE WHEN new_status = 'completed' THEN CURRENT_DATE
                                     ELSE actual_completion_date END,
        updated_at = CURRENT_TIMESTAMP
    WHERE production_order_id = order_uuid;

    -- Log status change
    INSERT INTO production_order_history (
        production_order_id, old_status, new_status, changed_by, notes
    ) VALUES (
        order_uuid, current_status, new_status,
        current_setting('app.user_id', TRUE)::UUID, notes
    );

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
```

### 3. Material Requirements Planning (MRP)
```sql
-- Calculate material requirements for production schedule
CREATE OR REPLACE FUNCTION calculate_material_requirements(
    product_uuid UUID,
    quantity_needed INTEGER,
    start_date DATE DEFAULT CURRENT_DATE,
    lead_time_days INTEGER DEFAULT 0
)
RETURNS TABLE (
    component_id UUID,
    component_name VARCHAR,
    total_required DECIMAL,
    available_inventory DECIMAL,
    net_requirement DECIMAL,
    planned_order_date DATE,
    supplier_lead_time INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH component_requirements AS (
        -- Explode BOM to get all required components
        SELECT
            bc.component_product_id,
            bc.quantity_required * quantity_needed as gross_requirement,
            COALESCE((
                SELECT SUM(quantity_available)
                FROM inventory_items ii
                WHERE ii.product_id = bc.component_product_id
            ), 0) as available_qty
        FROM bom_components bc
        WHERE bc.bom_id IN (
            SELECT bom_id FROM bill_of_materials
            WHERE parent_product_id = product_uuid
              AND effective_date <= start_date
              AND (expiration_date IS NULL OR expiration_date > start_date)
        )
    )
    SELECT
        cr.component_product_id,
        p.product_name,
        cr.gross_requirement,
        cr.available_qty,
        GREATEST(cr.gross_requirement - cr.available_qty, 0) as net_requirement,
        start_date - INTERVAL '1 day' * (
            SELECT COALESCE(lead_time_days, 0) FROM suppliers s
            WHERE s.supplier_id IN (
                SELECT supplier_id FROM bom_components
                WHERE component_product_id = cr.component_product_id
            ) LIMIT 1
        ) as planned_order_date,
        (SELECT lead_time_days FROM suppliers s
         WHERE s.supplier_id IN (
             SELECT supplier_id FROM bom_components
             WHERE component_product_id = cr.component_product_id
         ) LIMIT 1) as supplier_lead_time
    FROM component_requirements cr
    JOIN products p ON cr.component_product_id = p.product_id
    WHERE cr.gross_requirement > cr.available_qty;
END;
$$ LANGUAGE plpgsql;
```

### 4. Quality Control Inspection Workflow
```sql
-- Automated quality inspection routing
CREATE OR REPLACE FUNCTION route_quality_inspection(
    source_type VARCHAR,  -- 'incoming', 'production', 'outgoing'
    source_id UUID,
    product_id UUID
)
RETURNS UUID AS $$
DECLARE
    inspection_uuid UUID;
    plan_record quality_plans%ROWTYPE;
    sample_size INTEGER;
    acceptance_criteria VARCHAR;
BEGIN
    -- Find applicable quality plan
    SELECT * INTO plan_record
    FROM quality_plans
    WHERE plan_status = 'active'
      AND (product_id = ANY(applicable_products) OR array_length(applicable_products, 1) IS NULL)
      AND source_type = ANY(applicable_processes)
    ORDER BY created_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No applicable quality plan found for product and process';
    END IF;

    -- Determine sample size and criteria
    sample_size := plan_record.sample_size;
    acceptance_criteria := plan_record.acceptance_criteria;

    -- Create inspection record
    INSERT INTO quality_inspections (
        inspection_type, product_id, quality_plan_id,
        sample_size, inspection_findings
    ) VALUES (
        source_type, product_id, plan_record.quality_plan_id,
        sample_size, plan_record.inspection_criteria
    ) RETURNING inspection_id INTO inspection_uuid;

    -- Link to source
    CASE source_type
        WHEN 'incoming' THEN
            UPDATE purchase_order_lines SET inspection_id = inspection_uuid
            WHERE po_line_id = source_id;
        WHEN 'production' THEN
            UPDATE work_orders SET inspection_id = inspection_uuid
            WHERE work_order_id = source_id;
    END CASE;

    RETURN inspection_uuid;
END;
$$ LANGUAGE plpgsql;
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition production metrics by month for time-series analytics
CREATE TABLE production_metrics PARTITION BY RANGE (metric_timestamp);

CREATE TABLE production_metrics_2024_01 PARTITION OF production_metrics
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition inventory transactions by quarter
CREATE TABLE inventory_transactions PARTITION BY RANGE (transaction_date);

CREATE TABLE inventory_transactions_q1_2024 PARTITION OF inventory_transactions
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');
```

### Advanced Indexing
```sql
-- Composite indexes for production queries
CREATE INDEX idx_production_orders_product_status_dates ON production_orders
    (product_id, order_status, planned_start_date, planned_completion_date);

CREATE INDEX idx_work_orders_production_sequence ON work_orders
    (production_order_id, operation_sequence);

-- Partial indexes for active records
CREATE INDEX idx_active_inventory ON inventory_items (product_id, location_id, quantity_on_hand)
    WHERE quantity_on_hand > 0;

CREATE INDEX idx_open_production_orders ON production_orders (production_order_id)
    WHERE order_status NOT IN ('completed', 'cancelled');

-- GIN indexes for array and JSON data
CREATE INDEX idx_products_specifications ON products USING gin (specifications);
CREATE INDEX idx_bom_components_suppliers ON bom_components USING gin (supplier_id);
```

### Materialized Views for Analytics
```sql
-- Inventory turnover analysis
CREATE MATERIALIZED VIEW inventory_turnover AS
SELECT
    ii.product_id,
    p.product_name,
    p.product_category,

    -- Inventory metrics
    SUM(ii.quantity_on_hand) as total_inventory,
    AVG(ii.unit_cost) as avg_cost,

    -- Turnover calculation (simplified)
    CASE WHEN SUM(ii.quantity_on_hand) > 0 THEN
        (SELECT SUM(ABS(it.quantity))
         FROM inventory_transactions it
         WHERE it.product_id = ii.product_id
           AND it.transaction_date >= CURRENT_DATE - INTERVAL '365 days'
           AND it.transaction_type IN ('issue', 'transfer')
        ) / SUM(ii.quantity_on_hand)
    ELSE 0 END as turnover_ratio,

    -- Days of inventory
    CASE WHEN SUM(ii.quantity_on_hand) > 0 THEN
        365.0 / NULLIF(
            (SELECT SUM(ABS(it.quantity))
             FROM inventory_transactions it
             WHERE it.product_id = ii.product_id
               AND it.transaction_date >= CURRENT_DATE - INTERVAL '365 days'
               AND it.transaction_type IN ('issue', 'transfer')
            ) / SUM(ii.quantity_on_hand), 0
        )
    ELSE 0 END as days_of_inventory

FROM inventory_items ii
JOIN products p ON ii.product_id = p.product_id
GROUP BY ii.product_id, p.product_name, p.product_category
HAVING SUM(ii.quantity_on_hand) > 0;

-- Refresh monthly
CREATE UNIQUE INDEX idx_inventory_turnover_product ON inventory_turnover (product_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY inventory_turnover;
```

## Security Considerations

### Access Control
```sql
-- Role-based access for manufacturing operations
ALTER TABLE production_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY production_access_policy ON production_orders
    FOR ALL USING (
        department = current_setting('app.user_department') OR
        current_setting('app.user_role')::TEXT IN ('manager', 'admin') OR
        assigned_to = current_setting('app.user_id')::UUID
    );

CREATE POLICY inventory_access_policy ON inventory_items
    FOR SELECT USING (
        location_id IN (
            SELECT location_id FROM inventory_locations
            WHERE responsible_person = current_setting('app.user_id')::UUID OR
                  department = current_setting('app.user_department')
        )
    );
```

### Audit Trail
```sql
-- Comprehensive manufacturing audit logging
CREATE TABLE manufacturing_audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id UUID,
    department TEXT,
    workstation_id TEXT,
    shift TEXT,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (changed_at);

-- Audit trigger for critical tables
CREATE OR REPLACE FUNCTION manufacturing_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO manufacturing_audit_log (
        table_name, record_id, operation, old_values, new_values,
        user_id, department, workstation_id, shift
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.user_id', TRUE)::UUID,
        current_setting('app.user_department', TRUE)::TEXT,
        current_setting('app.workstation_id', TRUE)::TEXT,
        current_setting('app.shift', TRUE)::TEXT
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **ERP systems** for financial and order management integration
- **MES (Manufacturing Execution Systems)** for shop floor control
- **PLM (Product Lifecycle Management)** for product data management
- **SCADA systems** for equipment monitoring and control

### API Endpoints
- **Production planning APIs** for order management and scheduling
- **Inventory APIs** for real-time stock levels and transactions
- **Quality management APIs** for inspection and defect tracking
- **Supplier portal APIs** for purchase order and delivery tracking

## Monitoring & Analytics

### Key Performance Indicators
- **Overall Equipment Effectiveness (OEE)** metrics
- **Production yield** and defect rates
- **Inventory turnover** and carrying costs
- **Supplier performance** and on-time delivery rates
- **Quality metrics** and customer satisfaction scores

### Real-Time Dashboards
```sql
-- Manufacturing operations dashboard
CREATE VIEW manufacturing_operations_dashboard AS
SELECT
    -- Production metrics
    (SELECT COUNT(*) FROM production_orders WHERE order_status = 'in_progress') as active_production_orders,
    (SELECT SUM(quantity_completed) FROM work_orders WHERE work_order_status = 'completed'
     AND completed_at >= CURRENT_DATE) as units_produced_today,
    (SELECT AVG(efficiency_percentage) FROM production_orders
     WHERE actual_completion_date IS NOT NULL AND actual_completion_date >= CURRENT_DATE - INTERVAL '30 days') as avg_production_efficiency,

    -- Inventory metrics
    (SELECT COUNT(*) FROM inventory_items WHERE quantity_available <= reorder_point) as items_below_reorder,
    (SELECT SUM(total_value) FROM inventory_valuation) as total_inventory_value,
    (SELECT COUNT(*) FROM inventory_transactions WHERE transaction_date = CURRENT_DATE) as inventory_transactions_today,

    -- Quality metrics
    (SELECT COUNT(*) FROM quality_inspections WHERE inspection_date = CURRENT_DATE AND inspection_result = 'fail') as failed_inspections_today,
    (SELECT AVG(data_quality_score) FROM quality_inspections
     WHERE inspection_date >= CURRENT_DATE - INTERVAL '30 days') as avg_quality_score,

    -- Equipment metrics
    (SELECT COUNT(*) FROM equipment WHERE equipment_status = 'operational') as operational_equipment,
    (SELECT COUNT(*) FROM maintenance_work_orders WHERE maintenance_status = 'scheduled'
     AND scheduled_date <= CURRENT_DATE + INTERVAL '7 days') as upcoming_maintenance
;
```

This manufacturing database schema provides enterprise-grade infrastructure for complex manufacturing operations with comprehensive production planning, inventory management, quality control, and operational analytics capabilities.
