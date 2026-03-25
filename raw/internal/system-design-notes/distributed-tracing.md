# Distributed Tracing: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: OpenTelemetry, W3C Trace Context, Sampling Strategies, Tail-Based Sampling — Production Patterns

> [!CAUTION]
> **The Cardinal Sin**: Rolling your own tracing. Use OpenTelemetry. Any custom solution will be incompatible with the ecosystem and impossible to maintain at scale.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Dapper, a Large-Scale Distributed Tracing System](https://research.google/pubs/pub36356/) | Google's tracing infrastructure |
| [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/) | CNCF standard |
| [W3C Trace Context](https://www.w3.org/TR/trace-context/) | Context propagation standard |

---

## 🎯 The Principal Laws of Distributed Tracing

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: 100% Instrumentation** | All services must propagate context | One gap breaks the trace |
| **Law 2: Low Overhead** | Tracing should be < 3% CPU | Sample if needed |
| **Law 3: Cardinality Control** | Limit unique tag values | High cardinality kills storage |
| **Law 4: Trace ID Correlation** | Logs, metrics, traces share ID | One click from alert to trace |

---

# Part 1: Core Concepts

## 📐 Trace Structure

```
Trace (abc-123-def-456)
├── Span: API Gateway (10ms)
│   ├── Span: Auth Service (5ms)
│   │   └── Span: Redis GET (1ms)
│   └── Span: Order Service (50ms)
│       ├── Span: Inventory Check (10ms)
│       │   └── Span: PostgreSQL Query (5ms)
│       ├── Span: Payment Service (30ms)
│       │   ├── Span: Stripe API (25ms)
│       │   └── Span: PostgreSQL Insert (3ms)
│       └── Span: Kafka Publish (2ms)
└── Total: 60ms

Trace = Tree of Spans
Span = Single unit of work (function call, RPC, DB query)
Span Context = trace_id + span_id + trace_flags + trace_state
```

## 🔤 Span Anatomy

```python
# What a span contains
{
    "trace_id": "abc123def456789012345678",     # 128-bit unique ID
    "span_id": "1234567890abcdef",               # 64-bit span ID
    "parent_span_id": "fedcba0987654321",        # Parent span
    "operation_name": "HTTP GET /api/orders",    # What this span represents
    "service_name": "order-service",             # Which service
    
    "start_time": "2024-01-15T10:30:15.123Z",
    "end_time": "2024-01-15T10:30:15.183Z",
    "duration_ms": 60,
    
    "status": "OK",  # OK, ERROR, UNSET
    
    "attributes": {
        "http.method": "GET",
        "http.url": "https://api.example.com/orders/123",
        "http.status_code": 200,
        "user.id": "user-456",
        "order.id": "order-789"
    },
    
    "events": [
        {"name": "cache.miss", "timestamp": "..."},
        {"name": "retry.attempt", "timestamp": "...", "attributes": {"attempt": 2}}
    ],
    
    "links": [
        {"trace_id": "other-trace-id", "span_id": "...", "attributes": {"relationship": "caused_by"}}
    ]
}
```

---

# Part 2: W3C Trace Context

## 📋 HTTP Header Format

```
traceparent: 00-abc123def456789012345678-1234567890abcdef-01
             │   │                        │                │
             │   │                        │                └─ trace-flags (01 = sampled)
             │   │                        └─ parent-span-id (64-bit hex)
             │   └─ trace-id (128-bit hex)
             └─ version (00 = current)

tracestate: vendor1=opaque_value,vendor2=other_value
            └─ Vendor-specific propagation data
```

## 💻 Context Propagation (Go)

```go
import (
    "context"
    "net/http"
    
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/propagation"
    "go.opentelemetry.io/otel/trace"
)

// Incoming request: Extract context from headers
func HandleRequest(w http.ResponseWriter, r *http.Request) {
    // Extract trace context from headers
    ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
    
    // Start a new span as child of extracted context
    tracer := otel.Tracer("order-service")
    ctx, span := tracer.Start(ctx, "HandleOrderRequest")
    defer span.End()
    
    // Add attributes
    span.SetAttributes(
        attribute.String("http.method", r.Method),
        attribute.String("order.id", r.URL.Query().Get("id")),
    )
    
    // Call downstream service
    callPaymentService(ctx, orderID)
}

// Outgoing request: Inject context into headers
func callPaymentService(ctx context.Context, orderID string) error {
    req, _ := http.NewRequestWithContext(ctx, "POST", "http://payment-service/charge", nil)
    
    // Inject trace context into outgoing headers
    otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))
    
    return http.DefaultClient.Do(req)
}
```

## 💻 Context Propagation (Python)

```python
from opentelemetry import trace
from opentelemetry.propagate import inject, extract
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

tracer = trace.get_tracer(__name__)

# Incoming request
def handle_request(request):
    # Extract trace context
    ctx = extract(request.headers)
    
    with tracer.start_as_current_span("handle_order", context=ctx) as span:
        span.set_attribute("order.id", request.order_id)
        
        # Call downstream
        call_payment_service(request.order_id)

# Outgoing request
def call_payment_service(order_id):
    headers = {}
    inject(headers)  # Inject current trace context
    
    response = requests.post(
        "http://payment-service/charge",
        headers=headers,
        json={"order_id": order_id}
    )
    return response
```

---

# Part 3: OpenTelemetry Setup

## 🔧 Collector Architecture

```
                    ┌─────────────────────────────────────────┐
                    │         OpenTelemetry Collector         │
                    │                                         │
                    │  ┌─────────┐  ┌──────────┐  ┌────────┐ │
  Services ────────►│  │Receivers│→ │Processors│→ │Exporters│─┼────► Jaeger
  (OTLP)            │  └─────────┘  └──────────┘  └────────┘ │
                    │                                         │────► Tempo
                    │  Receivers: OTLP, Jaeger, Zipkin       │
                    │  Processors: Batch, Filter, Sample     │────► Honeycomb
                    │  Exporters: OTLP, Jaeger, Zipkin       │
                    └─────────────────────────────────────────┘
```

### Collector Configuration
```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
  
  # Also receive from legacy Jaeger/Zipkin apps
  jaeger:
    protocols:
      grpc:
        endpoint: 0.0.0.0:14250
  zipkin:
    endpoint: 0.0.0.0:9411

processors:
  # Batch spans for efficiency
  batch:
    timeout: 1s
    send_batch_size: 1024
  
  # Add resource attributes
  resource:
    attributes:
      - key: environment
        value: production
        action: upsert
      - key: service.namespace
        value: checkout
        action: upsert
  
  # Tail-based sampling (sample based on span content)
  tail_sampling:
    decision_wait: 10s
    num_traces: 50000
    policies:
      - name: errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: slow-traces
        type: latency
        latency:
          threshold_ms: 1000
      - name: sample-rest
        type: probabilistic
        probabilistic:
          sampling_percentage: 10

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true
  
  jaeger:
    endpoint: jaeger:14250
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp, jaeger, zipkin]
      processors: [resource, tail_sampling, batch]
      exporters: [otlp/tempo, jaeger]
```

## 💻 Service Instrumentation (Go)

```go
package main

import (
    "context"
    "log"
    "net/http"
    
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/propagation"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func initTracer() func() {
    ctx := context.Background()
    
    // Create OTLP exporter
    exporter, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithEndpoint("otel-collector:4317"),
        otlptracegrpc.WithInsecure(),
    )
    if err != nil {
        log.Fatal(err)
    }
    
    // Create resource with service info
    res, _ := resource.Merge(
        resource.Default(),
        resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceName("order-service"),
            semconv.ServiceVersion("1.2.3"),
            semconv.DeploymentEnvironment("production"),
        ),
    )
    
    // Create tracer provider
    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(res),
        sdktrace.WithSampler(sdktrace.ParentBased(sdktrace.TraceIDRatioBased(0.1))),
    )
    
    otel.SetTracerProvider(tp)
    otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
        propagation.TraceContext{},
        propagation.Baggage{},
    ))
    
    return func() { tp.Shutdown(ctx) }
}

func main() {
    cleanup := initTracer()
    defer cleanup()
    
    // Wrap HTTP handler with automatic instrumentation
    handler := http.HandlerFunc(handleOrder)
    wrappedHandler := otelhttp.NewHandler(handler, "HandleOrder")
    
    http.Handle("/orders", wrappedHandler)
    log.Fatal(http.ListenAndServe(":8080", nil))
}
```

---

# Part 4: Sampling Strategies

## 📊 Sampling Types

| Type | Where | Pros | Cons |
| :--- | :--- | :--- | :--- |
| **Head-Based** | At trace start | Simple, low overhead | Might miss interesting traces |
| **Tail-Based** | At trace end (collector) | Can sample based on content | Higher memory, more complex |
| **Adaptive** | Dynamic | Adjusts to load | Complex to configure |

## 🎯 Head-Based Sampling

```go
// At service startup
sampler := sdktrace.ParentBased(
    sdktrace.TraceIDRatioBased(0.1),  // 10% of new traces
    // Always sample if parent was sampled
    // Never sample if parent was not sampled
)
```

## 🎯 Tail-Based Sampling (Collector)

```yaml
# Sample ALL errors and slow traces, 10% of everything else
tail_sampling:
  policies:
    # Always keep errors
    - name: errors-policy
      type: status_code
      status_code:
        status_codes: [ERROR]
    
    # Always keep slow traces (>1s)
    - name: latency-policy
      type: latency
      latency:
        threshold_ms: 1000
    
    # Always keep traces with specific attributes
    - name: vip-users
      type: string_attribute
      string_attribute:
        key: user.tier
        values: ["premium", "enterprise"]
    
    # Sample 10% of remaining traces
    - name: probabilistic-policy
      type: probabilistic
      probabilistic:
        sampling_percentage: 10
```

---

# Part 5: Correlating Signals

## 🔗 Trace ID in Logs

```go
// Structured logging with trace context
func HandleOrder(ctx context.Context, order Order) error {
    span := trace.SpanFromContext(ctx)
    traceID := span.SpanContext().TraceID().String()
    spanID := span.SpanContext().SpanID().String()
    
    log.WithFields(log.Fields{
        "trace_id": traceID,
        "span_id":  spanID,
        "order_id": order.ID,
    }).Info("Processing order")
    
    // ... business logic
}

// Log output (JSON)
{
    "timestamp": "2024-01-15T10:30:15.123Z",
    "level": "info",
    "message": "Processing order",
    "trace_id": "abc123def456789012345678",
    "span_id": "1234567890abcdef",
    "order_id": "order-789"
}
```

## 🔗 Trace ID in Metrics (Exemplars)

```go
// Prometheus metrics with trace exemplar
import "go.opentelemetry.io/otel/exporters/prometheus"

// When recording a metric, attach trace context
histogram.Record(ctx, duration,
    metric.WithAttributes(
        attribute.String("http.method", "GET"),
        attribute.String("http.status_code", "200"),
    ),
)

// Prometheus output includes exemplar
# HELP http_request_duration_seconds Request duration
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",le="0.1"} 24054
http_request_duration_seconds_bucket{method="GET",le="0.5"} 33444 # {trace_id="abc123..."}
```

---

# Part 6: Production Patterns

## 📊 Monitoring Tracing Infrastructure

```yaml
# Alerting rules for collector
groups:
  - name: opentelemetry
    rules:
      - alert: OTelCollectorSpansDropped
        expr: rate(otelcol_processor_dropped_spans[5m]) > 0
        for: 5m
        annotations:
          summary: "OTel Collector dropping spans"
      
      - alert: OTelCollectorHighLatency
        expr: histogram_quantile(0.99, rate(otelcol_receiver_latency_bucket[5m])) > 0.1
        annotations:
          summary: "OTel Collector receive latency > 100ms"
      
      - alert: TracingBackendDown
        expr: up{job="tempo"} == 0 or up{job="jaeger"} == 0
        for: 1m
        labels:
          severity: critical
```

## 🔧 Common Issues

### Missing Spans (Broken Traces)
```
Symptom: Trace shows gaps (parent span has no children)

Causes:
1. Context not propagated in async calls
2. Different propagation format (B3 vs W3C)
3. Sampling decision mismatch

Fix:
- Verify all HTTP clients inject headers
- Use same propagator everywhere
- Use parent-based sampling
```

### High Cardinality
```
Symptom: Storage exploding, queries slow

Cause: Unique values in span attributes
  BAD:  span.set_attribute("order.id", order_id)  # Millions of unique values
  
Fix: 
  - Move high-cardinality to span events or logs
  - Use sampling for detailed debugging
  - Keep attributes to bounded sets (status codes, regions)
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | OpenTelemetry SDK in all services | Check dependency tree |
| 2 | W3C Trace Context propagation | Verify traceparent header |
| 3 | Collector in production | HA deployment (3+ replicas) |
| 4 | Tail-based sampling for errors | 100% error capture |
| 5 | Trace ID in all logs | Grep logs by trace_id |
| 6 | Exemplars in metrics | Click from metric to trace |
| 7 | Sampling rate documented | Know actual sample % |
| 8 | Cardinality limits enforced | Max unique attribute values |

---

## 🔗 Related Documents
*   [Monitoring & Observability](../infrastructure-techniques/monitoring-observability-comprehensive.md) — Metrics and logs.
*   [Service Discovery](./service-discovery.md) — Service topology.
*   [Saga Pattern](../distributive-backend/database/saga/saga-pattern-guide.md) — Distributed transaction tracing.
