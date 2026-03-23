# Logistics Industry Database Design

## Overview

This logistics database schema provides a comprehensive foundation for supply chain management, warehouse operations, transportation, and order fulfillment systems. The design handles complex logistics workflows including multi-company operations, inventory management, shipping, and transportation with real-time tracking and analytics.

## Table of Contents

1. [Schema Architecture](#schema-architecture)
2. [Core Components](#core-components)
3. [Inventory Management](#inventory-management)
4. [Order Management](#order-management)
5. [Shipping and Transportation](#shipping-and-transportation)
6. [Warehouse Management](#warehouse-management)
7. [Supply Chain Management](#supply-chain-management)
8. [Analytics and Reporting](#analytics-and-reporting)
9. [Performance Optimization](#performance-optimization)

## Schema Architecture

### Multi-Company Logistics Platform Architecture

```
┌─────────────────────────────────────────────────┐
│               COMPANY MANAGEMENT                │
│  • Multi-tenant companies (manufacturers,       │
│    distributors, carriers, warehouses)          │
└─────────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────────┐
│           LOCATION & FACILITY MGMT              │
│  • Warehouses, Distribution Centers, Ports      │
│  • Geospatial tracking and routing              │
└─────────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────────┐
│        PRODUCT & INVENTORY MANAGEMENT           │
│  • Product catalog, inventory tracking          │
│  • Multi-location stock management              │
└─────────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────────┐
│           ORDER & FULFILLMENT                   │
│  • Sales orders, purchase orders                │
│  • Order processing and fulfillment             │
└─────────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────────┐
│       SHIPPING & TRANSPORTATION                 │
│  • Multi-modal transportation                   │
│  • Real-time shipment tracking                  │
└─────────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────────┐
│       WAREHOUSE & OPERATIONS                    │
│  • Storage optimization, picking/packing        │
│  • Inventory movements and quality control      │
└─────────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────────┐
│         ANALYTICS & OPTIMIZATION                │
│  • Performance metrics, forecasting             │
│  • Route optimization and cost analysis         │
└─────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Multi-Company Support**: Single platform supporting manufacturers, distributors, carriers, and retailers
2. **Real-Time Visibility**: End-to-end supply chain visibility with GPS tracking and IoT integration
3. **Scalable Inventory**: Multi-location inventory management with real-time synchronization
4. **Flexible Fulfillment**: Support for various fulfillment models (B2B, B2C, dropshipping)
5. **Regulatory Compliance**: Hazardous materials handling, customs compliance, and safety standards
6. **Performance Optimization**: Efficient querying for high-volume logistics operations
7. **Cost Transparency**: Detailed cost tracking and analysis for profitability optimization

## Core Components

### Company and Location Management

#### Multi-Company Architecture
- **Company Types**: Manufacturers, distributors, retailers, carriers, 3PL providers, warehouses
- **Hierarchical Locations**: Multi-level warehouse structures with zones and storage locations
- **Geospatial Integration**: GPS coordinates for routing and proximity calculations
- **Compliance Tracking**: Regulatory compliance status for each company and location

#### Location Hierarchy
```sql
-- Hierarchical warehouse structure
CREATE TABLE locations (
    location_id UUID PRIMARY KEY,
    company_id UUID,
    location_type VARCHAR(50),  -- warehouse, distribution_center, store
    parent_location_id UUID,    -- For multi-level warehouses
    location_path LTREE,        -- Hierarchical path for fast queries
    geolocation GEOMETRY(Point, 4326),
    -- ... additional fields
);
```

### Product and Inventory Management

#### Product Catalog
- **Comprehensive Product Data**: Dimensions, weight, hazardous materials classification
- **Multi-Company Products**: Same product sold by different companies with different pricing
- **Packaging Information**: Package types, units per package, shipping requirements
- **Regulatory Compliance**: Hazardous materials, temperature control, special handling

#### Inventory Tracking
```sql
-- Multi-location inventory with allocation tracking
CREATE TABLE inventory (
    inventory_id UUID PRIMARY KEY,
    location_id UUID,
    product_id UUID,
    quantity_on_hand INTEGER,
    quantity_allocated INTEGER,
    quantity_available INTEGER GENERATED ALWAYS AS (
        quantity_on_hand - quantity_allocated
    ) STORED,
    -- ... allocation and availability tracking
);
```

## Inventory Management

### Multi-Location Inventory

#### Stock Allocation
- **Available vs Allocated**: Real-time tracking of committed inventory
- **Safety Stock**: Automatic reorder point calculations
- **Lot Tracking**: Expiration dates, lot numbers, and quality tracking
- **Serial Number Tracking**: Individual item tracking for high-value goods

#### Inventory Optimization
```sql
-- Automated reorder point calculations
CREATE VIEW inventory_reorder_alerts AS
SELECT
    p.product_name,
    l.location_name,
    i.quantity_available,
    i.reorder_point,
    i.safety_stock,
    CASE
        WHEN i.quantity_available <= i.reorder_point THEN 'CRITICAL'
        WHEN i.quantity_available <= i.safety_stock THEN 'WARNING'
        ELSE 'NORMAL'
    END AS alert_level
FROM inventory i
JOIN products p ON i.product_id = p.product_id
JOIN locations l ON i.location_id = l.location_id
WHERE i.quantity_available <= i.reorder_point * 1.5;
```

### Quality and Compliance

#### Quality Control
- **Inspection Requirements**: Configurable quality checks for different products
- **Defect Tracking**: Detailed defect categorization and root cause analysis
- **Quarantine Management**: Automated quarantine processes for non-conforming goods
- **Recall Management**: Product recall tracking and notification systems

## Order Management

### Order Processing Workflow

#### Order Types
- **Sales Orders**: B2B and B2C orders with complex fulfillment requirements
- **Purchase Orders**: Supplier ordering with approval workflows
- **Transfer Orders**: Inter-location inventory transfers
- **Return Orders**: Reverse logistics and return processing

#### Order Fulfillment
```sql
-- Order fulfillment status tracking
CREATE VIEW order_fulfillment_status AS
SELECT
    order_number,
    COUNT(line_item_id) AS total_lines,
    COUNT(CASE WHEN line_status = 'shipped' THEN 1 END) AS shipped_lines,
    CASE
        WHEN COUNT(line_item_id) = COUNT(CASE WHEN line_status = 'shipped' THEN 1 END)
             THEN 'COMPLETE'
        WHEN COUNT(CASE WHEN line_status = 'backordered' THEN 1 END) > 0 THEN 'PARTIAL'
        ELSE 'IN_PROGRESS'
    END AS fulfillment_status
FROM sales_orders so
LEFT JOIN order_line_items oli ON so.order_id = oli.order_id
GROUP BY so.order_id, order_number;
```

### Backorder and Allocation

#### Inventory Allocation
- **Real-Time Allocation**: Automatic inventory allocation during order processing
- **Backorder Management**: Partial fulfillment with automatic backorder creation
- **Allocation Rules**: Priority-based allocation for different customer tiers
- **Allocation Overrides**: Manual allocation for special circumstances

## Shipping and Transportation

### Multi-Modal Transportation

#### Transportation Modes
- **Ground Transportation**: Truck, rail, and local delivery
- **Air Freight**: Express air cargo with customs handling
- **Ocean Freight**: Container shipping with port operations
- **Intermodal**: Multi-mode transportation combinations

#### Carrier Management
```sql
-- Carrier performance tracking
CREATE TABLE carriers (
    carrier_id UUID PRIMARY KEY,
    company_name VARCHAR(255),
    carrier_type VARCHAR(30),  -- LTL, FTL, air, ocean
    service_levels JSONB,      -- Different service tiers
    performance_metrics JSONB, -- On-time delivery, damage rates
    -- ... carrier management fields
);
```

### Real-Time Shipment Tracking

#### GPS and Telematics Integration
- **Real-Time Location**: GPS tracking with route optimization
- **ETA Calculations**: Dynamic delivery time predictions
- **Exception Handling**: Automated alerts for delays and issues
- **Proof of Delivery**: Electronic POD with signature capture

#### Shipment Analytics
```sql
-- Shipment performance analytics
CREATE VIEW shipment_performance AS
SELECT
    s.shipment_id,
    s.shipment_number,
    s.ship_date,
    s.actual_delivery_date,
    s.estimated_delivery_date,
    EXTRACT(EPOCH FROM (s.actual_delivery_date - s.estimated_delivery_date))/86400 AS delivery_variance_days,
    CASE
        WHEN s.actual_delivery_date <= s.estimated_delivery_date THEN 'ON_TIME'
        WHEN s.actual_delivery_date <= s.estimated_delivery_date + INTERVAL '1 day' THEN 'SLIGHT_DELAY'
        ELSE 'SIGNIFICANT_DELAY'
    END AS delivery_performance,
    s.exception_code,
    s.exception_description
FROM shipments s
WHERE s.shipment_status = 'delivered';
```

## Warehouse Management

### Warehouse Operations

#### Storage Optimization
- **Slotting Optimization**: Product placement based on velocity and compatibility
- **Zone Management**: Receiving, storage, picking, packing, and shipping zones
- **Capacity Planning**: Real-time capacity utilization tracking
- **Layout Optimization**: Automated warehouse layout recommendations

#### Picking and Packing

#### Wave Planning
- **Order Batching**: Grouping orders for efficient picking
- **Zone Routing**: Optimized picker routes within warehouse zones
- **Task Assignment**: Automated task distribution to warehouse staff
- **Performance Tracking**: Picker productivity and accuracy metrics

### Inventory Movements

#### Movement Tracking
```sql
-- Comprehensive inventory movement audit trail
CREATE TABLE inventory_movements (
    movement_id UUID PRIMARY KEY,
    inventory_id UUID,
    movement_type VARCHAR(30),  -- receipt, putaway, picking, shipping, adjustment
    quantity_changed INTEGER,
    from_storage_location_id UUID,
    to_storage_location_id UUID,
    performed_by UUID,
    performed_at TIMESTAMP,
    movement_notes TEXT,
    -- ... quality and audit fields
);
```

#### Automated Putaway

#### Slotting Algorithms
- **Velocity-Based Slotting**: Fast-moving items in easily accessible locations
- **Product Affinity**: Related products stored together for efficient picking
- **Seasonal Slotting**: Seasonal products moved to optimal locations
- **ABC Analysis**: High-value items in secure, accessible locations

## Supply Chain Management

### Supplier Relationship Management

#### Supplier Performance
```sql
-- Supplier performance tracking
CREATE TABLE suppliers (
    supplier_id UUID PRIMARY KEY,
    supplier_name VARCHAR(255),
    on_time_delivery_rate DECIMAL(5,2),
    quality_rating DECIMAL(3,1),
    average_lead_time_days INTEGER,
    supplier_status VARCHAR(20),
    -- ... supplier management fields
);
```

#### Purchase Order Management
- **Automated PO Generation**: Reorder point triggered purchase orders
- **Supplier Negotiation**: Contract terms and pricing agreements
- **Quality Assurance**: Supplier quality audit and certification tracking
- **Risk Management**: Supplier risk assessment and diversification strategies

### Demand Planning

#### Forecasting and Planning
- **Historical Analysis**: Trend analysis and seasonality detection
- **Demand Forecasting**: Statistical forecasting models
- **Inventory Optimization**: Safety stock calculations and reorder points
- **Capacity Planning**: Warehouse and transportation capacity planning

## Analytics and Reporting

### Supply Chain Visibility

#### Real-Time Dashboards
```sql
-- Supply chain visibility dashboard
CREATE VIEW supply_chain_dashboard AS
SELECT
    'Inventory_Health' as metric_category,
    COUNT(*) as total_skus,
    SUM(CASE WHEN quantity_available <= reorder_point THEN 1 ELSE 0 END) as low_stock_items,
    AVG(CASE WHEN quantity_on_hand > 0 THEN inventory_turnover_ratio ELSE NULL END) as avg_turnover
FROM inventory i
JOIN locations l ON i.location_id = l.location_id
WHERE l.location_type IN ('warehouse', 'distribution_center')

UNION ALL

SELECT
    'Order_Fulfillment' as metric_category,
    COUNT(*) as active_orders,
    AVG(EXTRACT(EPOCH FROM (actual_ship_date - order_date))/86400) as avg_processing_days,
    SUM(CASE WHEN order_status = 'backordered' THEN 1 ELSE 0 END) as backordered_orders
FROM sales_orders
WHERE order_date >= CURRENT_DATE - INTERVAL '30 days'

UNION ALL

SELECT
    'Transportation' as metric_category,
    COUNT(*) as active_shipments,
    AVG(EXTRACT(EPOCH FROM (actual_delivery_date - ship_date))/86400) as avg_transit_days,
    SUM(CASE WHEN exception_code IS NOT NULL THEN 1 ELSE 0 END) as shipments_with_exceptions
FROM shipments
WHERE ship_date >= CURRENT_DATE - INTERVAL '30 days';
```

### Performance Metrics

#### Key Performance Indicators
- **On-Time Delivery**: Percentage of orders delivered on time
- **Order Accuracy**: Percentage of orders shipped without errors
- **Inventory Turnover**: How quickly inventory is sold and replaced
- **Warehouse Utilization**: Percentage of warehouse capacity used
- **Transportation Costs**: Cost per unit shipped and delivered

#### Cost Analysis
```sql
-- Comprehensive cost analysis
CREATE VIEW logistics_cost_analysis AS
SELECT
    DATE_TRUNC('month', transaction_date) as month,
    SUM(CASE WHEN cost_type = 'shipping' THEN amount ELSE 0 END) as shipping_costs,
    SUM(CASE WHEN cost_type = 'warehouse' THEN amount ELSE 0 END) as warehouse_costs,
    SUM(CASE WHEN cost_type = 'transportation' THEN amount ELSE 0 END) as transportation_costs,
    SUM(CASE WHEN cost_type = 'inventory_carrying' THEN amount ELSE 0 END) as carrying_costs,
    COUNT(DISTINCT order_id) as orders_processed,
    SUM(amount) / COUNT(DISTINCT order_id) as cost_per_order
FROM cost_transactions
WHERE transaction_date >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', transaction_date)
ORDER BY month DESC;
```

## Performance Optimization

### Database Optimization Strategies

#### Indexing Strategy
```sql
-- Critical performance indexes
CREATE INDEX idx_inventory_location_product ON inventory (location_id, product_id);
CREATE INDEX idx_shipments_tracking_status ON shipments (tracking_number, shipment_status);
CREATE INDEX idx_order_line_items_order_status ON order_line_items (order_id, line_status);
CREATE INDEX idx_inventory_movements_inventory_date ON inventory_movements (inventory_id, performed_at DESC);
```

#### Partitioning Strategy
```sql
-- Time-based partitioning for analytics
CREATE TABLE inventory_analytics PARTITION BY RANGE (date_recorded);
CREATE TABLE fulfillment_analytics PARTITION BY RANGE (date_recorded);
CREATE TABLE cost_transactions PARTITION BY RANGE (transaction_date);
```

### Query Optimization

#### Common Query Patterns
```sql
-- Optimized inventory availability query
SELECT
    p.product_name,
    p.sku,
    SUM(i.quantity_available) as total_available,
    SUM(i.quantity_allocated) as total_allocated,
    array_agg(DISTINCT l.location_name) as available_locations
FROM products p
JOIN inventory i ON p.product_id = i.product_id
JOIN locations l ON i.location_id = l.location_id
WHERE i.inventory_status = 'available'
  AND i.quantity_available > 0
GROUP BY p.product_id, p.product_name, p.sku
HAVING SUM(i.quantity_available) > 0
ORDER BY SUM(i.quantity_available) DESC;

-- Optimized shipment tracking
SELECT
    s.shipment_number,
    s.shipment_status,
    s.current_location,
    s.estimated_delivery_date,
    c.company_name as carrier,
    COUNT(si.shipment_item_id) as items_count,
    SUM(si.shipped_quantity) as total_quantity
FROM shipments s
JOIN companies c ON s.carrier_id = c.company_id
LEFT JOIN shipment_items si ON s.shipment_id = si.shipment_id
WHERE s.tracking_number = $1
GROUP BY s.shipment_id, s.shipment_number, s.shipment_status,
         s.current_location, s.estimated_delivery_date, c.company_name;
```

### Caching Strategies

#### Multi-Level Caching
- **Application Cache**: Frequently accessed inventory levels and product data
- **Query Result Cache**: Complex analytics queries with periodic refresh
- **Edge Cache**: Location-specific data cached closer to users
- **CDN Integration**: Static assets and reference data distribution

#### Cache Invalidation
```sql
-- Intelligent cache invalidation for inventory changes
CREATE OR REPLACE FUNCTION invalidate_inventory_cache()
RETURNS TRIGGER AS $$
BEGIN
    -- Invalidate product-specific cache
    PERFORM pg_notify('inventory_cache_invalidate',
                     json_build_object('product_id', NEW.product_id)::text);

    -- Invalidate location-specific cache
    PERFORM pg_notify('location_inventory_invalidate',
                     json_build_object('location_id', NEW.location_id)::text);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_inventory_cache_invalidation
    AFTER UPDATE ON inventory
    FOR EACH ROW EXECUTE FUNCTION invalidate_inventory_cache();
```

## Implementation Considerations

### High-Volume Transaction Processing

#### Order Processing Optimization
- **Asynchronous Processing**: Queue-based order processing for high throughput
- **Batch Operations**: Bulk inventory updates and allocation
- **Optimistic Locking**: Prevent conflicts in concurrent order processing
- **Deadlock Prevention**: Strategic lock ordering and timeout management

#### Real-Time Inventory Updates
```sql
-- Real-time inventory synchronization
CREATE OR REPLACE FUNCTION sync_inventory_changes()
RETURNS TRIGGER AS $$
BEGIN
    -- Publish inventory change events
    PERFORM pg_notify('inventory_changes',
        json_build_object(
            'inventory_id', NEW.inventory_id,
            'product_id', NEW.product_id,
            'location_id', NEW.location_id,
            'old_quantity', OLD.quantity_available,
            'new_quantity', NEW.quantity_available,
            'change_type', TG_OP
        )::text
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_inventory_sync
    AFTER INSERT OR UPDATE OR DELETE ON inventory
    FOR EACH ROW EXECUTE FUNCTION sync_inventory_changes();
```

### Regulatory Compliance

#### Hazardous Materials Handling
- **Hazardous Materials Classification**: Proper classification and documentation
- **Regulatory Compliance Tracking**: DOT, IATA, IMDG compliance
- **Safety Data Sheets**: SDS management and accessibility
- **Emergency Response**: Hazardous spill and incident response procedures

#### Customs and International Shipping
- **Customs Documentation**: Commercial invoices, certificates of origin
- **Tariff Classification**: HS codes and duty calculations
- **Trade Compliance**: Denied party screening and embargo compliance
- **Import/Export Licensing**: License management and tracking

### Integration Capabilities

#### API and Webhook Integration
- **Real-Time Updates**: Webhook notifications for status changes
- **Third-Party Integration**: ERP, TMS, WMS system integration
- **IoT Integration**: Sensor data from transportation and warehouse equipment
- **Mobile Applications**: Driver and warehouse staff mobile applications

#### EDI Integration
```sql
-- EDI transaction processing
CREATE TABLE edi_transactions (
    transaction_id UUID PRIMARY KEY,
    transaction_type VARCHAR(10),  -- 850, 855, 856, 810, etc.
    sender_id VARCHAR(50),
    receiver_id VARCHAR(50),
    transaction_date TIMESTAMP,
    status VARCHAR(20),
    raw_message TEXT,
    parsed_data JSONB,
    -- ... EDI processing fields
);
```

### Scalability Planning

#### Horizontal Scaling
- **Database Sharding**: Product-based or geographic sharding strategies
- **Read Replicas**: Geographic distribution for global operations
- **Microservices Architecture**: Decomposed logistics functions
- **Event-Driven Architecture**: Asynchronous processing for high throughput

#### Performance Monitoring
```sql
-- Comprehensive performance monitoring
CREATE TABLE performance_metrics (
    metric_id UUID PRIMARY KEY,
    metric_name VARCHAR(100),
    metric_value DECIMAL(15,4),
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    component VARCHAR(50),  -- database, application, warehouse, transportation
    location_id UUID,
    severity VARCHAR(20)
);

-- Automated performance alerting
CREATE OR REPLACE FUNCTION check_performance_thresholds()
RETURNS TABLE (
    alert_type VARCHAR(50),
    severity VARCHAR(20),
    description TEXT,
    recommended_action TEXT
) AS $$
BEGIN
    -- Check order processing performance
    RETURN QUERY
    SELECT
        'order_processing_delay'::VARCHAR(50),
        'HIGH'::VARCHAR(20),
        format('Average order processing time: %s minutes', ROUND(avg_processing_time, 1)),
        'Review order processing workflow and resource allocation'::TEXT
    FROM (
        SELECT AVG(EXTRACT(EPOCH FROM (actual_ship_date - order_date))/60) as avg_processing_time
        FROM sales_orders
        WHERE order_date >= CURRENT_DATE - INTERVAL '1 day'
          AND actual_ship_date IS NOT NULL
    ) processing
    WHERE avg_processing_time > 60;  -- More than 1 hour average

    -- Check inventory accuracy
    RETURN QUERY
    SELECT
        'inventory_accuracy'::VARCHAR(50),
        CASE WHEN accuracy_rate < 95 THEN 'CRITICAL' ELSE 'WARNING' END,
        format('Inventory accuracy: %s%%', ROUND(accuracy_rate, 2)),
        'Conduct inventory audit and review counting procedures'::TEXT
    FROM (
        SELECT
            (COUNT(CASE WHEN abs(physical_count - system_count) <= 1 THEN 1 END)::DECIMAL /
             COUNT(*)) * 100 as accuracy_rate
        FROM cycle_counts
        WHERE count_date >= CURRENT_DATE - INTERVAL '30 days'
    ) accuracy
    WHERE accuracy_rate < 98;

END;
$$ LANGUAGE plpgsql;
```

## Integration Points

### External Systems
- **Transportation Management Systems** (TMS) for route optimization and carrier management
- **Warehouse Management Systems** (WMS) for inventory and order fulfillment
- **Enterprise Resource Planning** (ERP) systems for business process integration
- **Carrier APIs** (FedEx, UPS, DHL) for shipping rates and tracking
- **GPS and telematics systems** for real-time vehicle tracking and monitoring
- **Customs and border systems** for international shipment compliance
- **Supplier portals** for purchase order management and vendor collaboration

### API Endpoints
- **Order management APIs** for order processing and status tracking
- **Inventory APIs** for stock levels, availability, and replenishment
- **Shipping APIs** for rate shopping, label generation, and tracking
- **Warehouse APIs** for picking, packing, and fulfillment operations
- **Analytics APIs** for performance metrics and business intelligence
- **Integration APIs** for third-party system connectivity and EDI

## Monitoring & Analytics

### Key Performance Indicators
- **Order fulfillment metrics** (on-time delivery, order accuracy, cycle time)
- **Inventory performance** (stock turnover, carrying costs, stockout rates)
- **Transportation efficiency** (route optimization, fuel consumption, delivery times)
- **Warehouse productivity** (picking accuracy, throughput, labor efficiency)
- **Customer satisfaction** (delivery experience, communication, issue resolution)

### Real-Time Dashboards
```sql
-- Logistics operations dashboard
CREATE VIEW logistics_operations_dashboard AS
SELECT
    -- Order fulfillment (current day)
    (SELECT COUNT(*) FROM orders WHERE DATE(order_date) = CURRENT_DATE) as orders_today,
    (SELECT COUNT(*) FROM orders WHERE DATE(order_date) = CURRENT_DATE AND status = 'shipped')::DECIMAL /
    NULLIF((SELECT COUNT(*) FROM orders WHERE DATE(order_date) = CURRENT_DATE), 0) * 100 as order_fulfillment_rate_today,
    (SELECT AVG(EXTRACT(EPOCH FROM (ship_date - order_date))/86400)
     FROM orders WHERE DATE(order_date) = CURRENT_DATE AND ship_date IS NOT NULL) as avg_order_to_ship_days,

    -- Shipping performance
    (SELECT COUNT(*) FROM shipments WHERE DATE(ship_date) = CURRENT_DATE) as shipments_today,
    (SELECT COUNT(*) FROM shipments WHERE DATE(delivery_date) = CURRENT_DATE) as deliveries_today,
    (SELECT COUNT(*) FROM shipments WHERE DATE(estimated_delivery) = CURRENT_DATE AND delivery_date > estimated_delivery) as late_deliveries_today,

    -- Inventory metrics
    (SELECT SUM(quantity_on_hand * unit_cost) FROM inventory) as total_inventory_value,
    (SELECT COUNT(*) FROM inventory WHERE quantity_on_hand <= reorder_point) as items_below_reorder,
    (SELECT AVG(turnover_ratio) FROM inventory_turnover WHERE calculated_date >= CURRENT_DATE - INTERVAL '30 days') as avg_inventory_turnover,

    -- Warehouse operations
    (SELECT COUNT(*) FROM warehouse_orders WHERE DATE(processed_date) = CURRENT_DATE) as orders_processed_today,
    (SELECT AVG(EXTRACT(EPOCH FROM (completion_time - start_time))/3600)
     FROM warehouse_operations WHERE DATE(operation_date) = CURRENT_DATE) as avg_processing_time_hours,
    (SELECT COUNT(*) FROM picking_errors WHERE DATE(error_date) = CURRENT_DATE) as picking_errors_today,

    -- Transportation metrics
    (SELECT COUNT(*) FROM vehicle_trips WHERE DATE(trip_date) = CURRENT_DATE) as vehicle_trips_today,
    (SELECT AVG(distance_miles) FROM vehicle_trips WHERE DATE(trip_date) = CURRENT_DATE) as avg_trip_distance,
    (SELECT AVG(fuel_efficiency) FROM vehicle_trips WHERE DATE(trip_date) = CURRENT_DATE) as avg_fuel_efficiency,

    -- Customer service
    (SELECT COUNT(*) FROM customer_inquiries WHERE DATE(created_date) = CURRENT_DATE) as inquiries_today,
    (SELECT COUNT(*) FROM customer_inquiries WHERE DATE(created_date) = CURRENT_DATE AND status = 'resolved')::DECIMAL /
    NULLIF((SELECT COUNT(*) FROM customer_inquiries WHERE DATE(created_date) = CURRENT_DATE), 0) * 100 as inquiry_resolution_rate,
    (SELECT AVG(rating) FROM delivery_feedback WHERE DATE(feedback_date) >= CURRENT_DATE - INTERVAL '30 days') as avg_customer_satisfaction,

    -- Financial metrics
    (SELECT COALESCE(SUM(shipping_revenue), 0) FROM shipments WHERE DATE(ship_date) >= DATE_TRUNC('month', CURRENT_DATE)) as shipping_revenue_month,
    (SELECT COALESCE(SUM(carrier_costs), 0) FROM shipments WHERE DATE(ship_date) >= DATE_TRUNC('month', CURRENT_DATE)) as carrier_costs_month,
    (SELECT COALESCE(SUM(warehouse_costs), 0) FROM warehouse_operations WHERE DATE(operation_date) >= DATE_TRUNC('month', CURRENT_DATE)) as warehouse_costs_month,

    -- Quality metrics
    (SELECT COUNT(*) FROM damaged_shipments WHERE DATE(reported_date) >= DATE_TRUNC('month', CURRENT_DATE)) as damaged_shipments_month,
    (SELECT COUNT(*) FROM lost_shipments WHERE DATE(reported_date) >= DATE_TRUNC('month', CURRENT_DATE)) as lost_shipments_month,
    (SELECT COUNT(*) FROM returns WHERE DATE(return_date) >= DATE_TRUNC('month', CURRENT_DATE)) as returns_month

FROM dual; -- Use a dummy table for single-row result
```

This logistics database design provides a comprehensive foundation for modern supply chain management, supporting complex logistics operations with real-time visibility, regulatory compliance, and enterprise scalability.
