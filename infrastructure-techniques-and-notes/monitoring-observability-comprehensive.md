# Monitoring & Observability Comprehensive Guide

## Overview

Monitoring and observability are critical for maintaining system health, performance, and reliability in production environments. This comprehensive guide covers metrics collection (Prometheus), visualization (Grafana), logging (ELK Stack), distributed tracing (Jaeger, Zipkin), and enterprise patterns for building observable systems.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [The Three Pillars of Observability](#the-three-pillars-of-observability)
3. [Prometheus Deep Dive](#prometheus-deep-dive)
4. [Grafana Deep Dive](#grafana-deep-dive)
5. [ELK Stack (Elasticsearch, Logstash, Kibana)](#elk-stack)
6. [Distributed Tracing](#distributed-tracing)
7. [OpenTelemetry](#opentelemetry)
8. [Best Practices](#best-practices)
9. [Performance Optimization](#performance-optimization)
10. [Alerting Strategies](#alerting-strategies)

## Core Concepts

### What is Observability?

Observability is the ability to understand the internal state of a system by examining its outputs (metrics, logs, traces). Unlike monitoring, which focuses on known issues, observability helps discover unknown problems.

### Key Differences: Monitoring vs Observability

- **Monitoring**: Predefined metrics and alerts for known issues
- **Observability**: Ability to explore and understand system behavior through metrics, logs, and traces

### The Four Golden Signals

1. **Latency**: Time taken to serve a request
2. **Traffic**: Demand placed on the system
3. **Errors**: Rate of requests that fail
4. **Saturation**: How "full" the service is

## The Three Pillars of Observability

### 1. Metrics

**Definition**: Numerical measurements over time

**Characteristics**:
- Low cardinality (limited unique values)
- High frequency sampling
- Aggregatable
- Efficient storage

**Use Cases**:
- System health monitoring
- Performance tracking
- Capacity planning
- Alerting

### 2. Logs

**Definition**: Discrete events with timestamps

**Characteristics**:
- High cardinality (many unique values)
- Structured or unstructured
- Rich context
- Searchable

**Use Cases**:
- Debugging
- Audit trails
- Security analysis
- Troubleshooting

### 3. Traces

**Definition**: Request flows through distributed systems

**Characteristics**:
- High cardinality
- Context propagation
- Dependency mapping
- Performance analysis

**Use Cases**:
- Distributed system debugging
- Performance optimization
- Dependency analysis
- Request flow visualization

## Prometheus Deep Dive

### Architecture

Prometheus is a time-series database designed for monitoring and alerting, using a pull-based model for metrics collection.

### Core Components

- **Prometheus Server**: Scrapes and stores metrics
- **Exporters**: Expose metrics from various systems
- **Alertmanager**: Handles alert routing and notification
- **Client Libraries**: Instrument applications

### Installation

```bash
# Download Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
tar xvfz prometheus-2.48.0.linux-amd64.tar.gz
cd prometheus-2.48.0

# Start Prometheus
./prometheus --config.file=prometheus.yml
```

### Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'production'
    environment: 'prod'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

# Load rules
rule_files:
  - "alerts/*.yml"

# Scrape configurations
scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Application services
  - job_name: 'user-service'
    scrape_interval: 10s
    metrics_path: '/metrics'
    static_configs:
      - targets: ['user-service:8080']
        labels:
          service: 'user-service'
          environment: 'production'

  # Service discovery with Consul
  - job_name: 'consul-services'
    consul_sd_configs:
      - server: 'consul:8500'
        services: []
    relabel_configs:
      - source_labels: [__meta_consul_service]
        target_label: job
```

### Metric Types

#### Counter

```go
// Go example
import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promauto"
)

var (
    httpRequestsTotal = promauto.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "endpoint", "status"},
    )
)

func handleRequest(method, endpoint string, statusCode int) {
    httpRequestsTotal.WithLabelValues(method, endpoint, fmt.Sprintf("%d", statusCode)).Inc()
}
```

#### Gauge

```go
var (
    activeConnections = promauto.NewGauge(
        prometheus.GaugeOpts{
            Name: "active_connections",
            Help: "Number of active connections",
        },
    )
)

func updateConnections(count int) {
    activeConnections.Set(float64(count))
}
```

#### Histogram

```go
var (
    httpRequestDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "http_request_duration_seconds",
            Help:    "HTTP request duration in seconds",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method", "endpoint"},
    )
)

func recordRequestDuration(method, endpoint string, duration time.Duration) {
    httpRequestDuration.WithLabelValues(method, endpoint).Observe(duration.Seconds())
}
```

#### Summary

```go
var (
    requestSize = promauto.NewSummaryVec(
        prometheus.SummaryOpts{
            Name:       "http_request_size_bytes",
            Help:       "HTTP request size in bytes",
            Objectives: map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
        },
        []string{"method"},
    )
)
```

### PromQL (Prometheus Query Language)

```promql
# Rate of HTTP requests per second
rate(http_requests_total[5m])

# 95th percentile latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate percentage
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100

# CPU usage percentage
100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

### Exporters

#### Node Exporter (System Metrics)

```bash
# Run node exporter
docker run -d \
  --name=node-exporter \
  -p 9100:9100 \
  prom/node-exporter

# Prometheus scrape config
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
```

#### Redis Exporter

```bash
# Run Redis exporter
docker run -d \
  --name=redis-exporter \
  -p 9121:9121 \
  oliver006/redis_exporter \
  --redis.addr=redis:6379
```

#### PostgreSQL Exporter

```bash
# Run PostgreSQL exporter
docker run -d \
  --name=postgres-exporter \
  -p 9187:9187 \
  -e DATA_SOURCE_NAME="postgresql://user:password@postgres:5432/dbname" \
  prometheuscommunity/postgres-exporter
```

### Alerting Rules

```yaml
# alerts.yml
groups:
  - name: application_alerts
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m])) 
          / sum(rate(http_requests_total[5m])) * 100 > 5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }}% for the last 5 minutes"

      - alert: HighLatency
        expr: |
          histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High latency detected"
          description: "95th percentile latency is {{ $value }}s"

      - alert: ServiceDown
        expr: up{job="user-service"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service is down"
          description: "{{ $labels.job }} has been down for more than 1 minute"

  - name: infrastructure_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage"
          description: "CPU usage is {{ $value }}%"

      - alert: HighMemoryUsage
        expr: |
          (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "Memory usage is {{ $value }}%"
```

### Alertmanager Configuration

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'critical-alerts'
    - match:
        severity: warning
      receiver: 'warning-alerts'

receivers:
  - name: 'default'
    slack_configs:
      - channel: '#alerts'
        title: 'Prometheus Alert'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'critical-alerts'
    slack_configs:
      - channel: '#critical-alerts'
        title: '🚨 Critical Alert'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_KEY'

  - name: 'warning-alerts'
    slack_configs:
      - channel: '#warnings'
        title: '⚠️ Warning Alert'
```

## Grafana Deep Dive

### Architecture

Grafana is an open-source analytics and visualization platform for metrics, logs, and traces.

### Installation

```bash
# Docker installation
docker run -d \
  --name=grafana \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana:latest
```

### Data Source Configuration

```yaml
# datasources.yml (Provisioning)
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      timeInterval: "15s"
      httpMethod: POST

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    jsonData:
      maxLines: 1000

  - name: Jaeger
    type: jaeger
    access: proxy
    url: http://jaeger:16686
```

### Dashboard Configuration

```json
{
  "dashboard": {
    "title": "Application Metrics",
    "tags": ["application", "production"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[5m]))",
            "legendFormat": "Requests/sec"
          }
        ],
        "yaxes": [
          {
            "format": "reqps"
          }
        ]
      },
      {
        "id": 2,
        "title": "Error Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{status=~\"5..\"}[5m]))",
            "legendFormat": "Errors/sec"
          }
        ]
      },
      {
        "id": 3,
        "title": "Latency (95th percentile)",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "P95"
          }
        ],
        "yaxes": [
          {
            "format": "s"
          }
        ]
      },
      {
        "id": 4,
        "title": "Service Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up",
            "legendFormat": "{{job}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                {"value": 0, "color": "red"},
                {"value": 1, "color": "green"}
              ]
            }
          }
        }
      }
    ],
    "refresh": "10s",
    "time": {
      "from": "now-6h",
      "to": "now"
    }
  }
}
```

### Advanced Queries

```promql
# Request rate by endpoint
sum by (endpoint) (rate(http_requests_total[5m]))

# Error percentage by service
sum by (service) (rate(http_requests_total{status=~"5.."}[5m])) 
/ sum by (service) (rate(http_requests_total[5m])) * 100

# Top 10 slowest endpoints
topk(10, histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])))

# Request distribution by status code
sum by (status) (rate(http_requests_total[5m]))
```

### Alerting in Grafana

```json
{
  "alert": {
    "name": "High Error Rate",
    "message": "Error rate is above threshold",
    "frequency": "10s",
    "conditions": [
      {
        "query": {
          "queryType": "",
          "refId": "A"
        },
        "reducer": {
          "type": "avg",
          "params": []
        },
        "evaluator": {
          "params": [5],
          "type": "gt"
        }
      }
    ],
    "executionErrorState": "alerting",
    "noDataState": "no_data",
    "notifications": []
  }
}
```

## ELK Stack

### Elasticsearch

#### Installation

```bash
# Docker Compose
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    ports:
      - "9200:9200"
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data

volumes:
  elasticsearch_data:
```

#### Index Template

```json
{
  "index_patterns": ["app-logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1
    },
    "mappings": {
      "properties": {
        "@timestamp": {
          "type": "date"
        },
        "level": {
          "type": "keyword"
        },
        "message": {
          "type": "text"
        },
        "service": {
          "type": "keyword"
        },
        "trace_id": {
          "type": "keyword"
        }
      }
    }
  }
}
```

### Logstash

#### Configuration

```ruby
# logstash.conf
input {
  beats {
    port => 5044
  }
}

filter {
  if [fields][service] == "user-service" {
    grok {
      match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{GREEDYDATA:message}" }
    }
    
    date {
      match => [ "timestamp", "ISO8601" ]
    }
    
    mutate {
      add_field => { "parsed" => "true" }
    }
  }
  
  if [level] == "ERROR" {
    mutate {
      add_tag => [ "error" ]
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "app-logs-%{+YYYY.MM.dd}"
  }
}
```

### Kibana

#### Index Pattern

```json
{
  "title": "app-logs-*",
  "timeFieldName": "@timestamp",
  "fields": [
    {
      "name": "@timestamp",
      "type": "date"
    },
    {
      "name": "level",
      "type": "string"
    },
    {
      "name": "message",
      "type": "string"
    }
  ]
}
```

#### Visualization Queries

```json
{
  "query": {
    "bool": {
      "must": [
        {
          "match": {
            "level": "ERROR"
          }
        },
        {
          "range": {
            "@timestamp": {
              "gte": "now-1h"
            }
          }
        }
      ]
    }
  },
  "aggs": {
    "errors_by_service": {
      "terms": {
        "field": "service.keyword",
        "size": 10
      }
    }
  }
}
```

## Distributed Tracing

### Jaeger

#### Architecture

Jaeger is a distributed tracing system for monitoring and troubleshooting microservices.

#### Installation

```bash
# Docker Compose
version: '3.8'
services:
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"  # UI
      - "14268:14268"  # HTTP collector
      - "6831:6831/udp"  # UDP collector
    environment:
      - COLLECTOR_ZIPKIN_HTTP_PORT=9411
```

#### Instrumentation (Go)

```go
package main

import (
    "github.com/opentracing/opentracing-go"
    "github.com/uber/jaeger-client-go"
    "github.com/uber/jaeger-client-go/config"
)

func initTracer(serviceName string) (opentracing.Tracer, io.Closer, error) {
    cfg := &config.Configuration{
        ServiceName: serviceName,
        Sampler: &config.SamplerConfig{
            Type:  jaeger.SamplerTypeConst,
            Param: 1,
        },
        Reporter: &config.ReporterConfig{
            LogSpans:            true,
            BufferFlushInterval: 1 * time.Second,
            LocalAgentHostPort:  "jaeger:6831",
        },
    }
    
    tracer, closer, err := cfg.NewTracer()
    return tracer, closer, err
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
    span, ctx := opentracing.StartSpanFromContext(r.Context(), "handleRequest")
    defer span.Finish()
    
    // Add tags
    span.SetTag("http.method", r.Method)
    span.SetTag("http.url", r.URL.String())
    
    // Call downstream service
    callDownstreamService(ctx)
    
    span.SetTag("http.status_code", 200)
}
```

### Zipkin

#### Installation

```bash
docker run -d \
  --name=zipkin \
  -p 9411:9411 \
  openzipkin/zipkin:latest
```

#### Instrumentation (Java)

```java
// Spring Boot with Zipkin
@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}

// Add to application.yml
spring:
  zipkin:
    base-url: http://zipkin:9411
  sleuth:
    sampler:
      probability: 1.0
```

## OpenTelemetry

### Overview

OpenTelemetry is a vendor-neutral observability framework providing unified APIs and SDKs for metrics, logs, and traces.

### Installation

```bash
# Go
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/jaeger
go get go.opentelemetry.io/otel/sdk/trace

# Java
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-api</artifactId>
    <version>1.32.0</version>
</dependency>
```

### Instrumentation Example

```go
package main

import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/jaeger"
    "go.opentelemetry.io/otel/sdk/resource"
    "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
)

func initTracer() (*trace.TracerProvider, error) {
    exp, err := jaeger.New(jaeger.WithCollectorEndpoint(jaeger.WithEndpoint("http://jaeger:14268/api/traces")))
    if err != nil {
        return nil, err
    }
    
    tp := trace.NewTracerProvider(
        trace.WithBatcher(exp),
        trace.WithResource(resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceNameKey.String("user-service"),
        )),
    )
    
    otel.SetTracerProvider(tp)
    return tp, nil
}

func handleRequest(ctx context.Context) {
    tracer := otel.Tracer("user-service")
    ctx, span := tracer.Start(ctx, "handleRequest")
    defer span.End()
    
    span.SetAttributes(
        attribute.String("http.method", "GET"),
        attribute.String("http.url", "/users"),
    )
    
    // Business logic
    processRequest(ctx)
}
```

## Best Practices

### 1. Structured Logging

```go
// Structured logging with context
logger.Info("Request processed",
    zap.String("method", "GET"),
    zap.String("path", "/users"),
    zap.Int("status", 200),
    zap.Duration("duration", duration),
    zap.String("trace_id", traceID),
    zap.String("user_id", userID),
)
```

### 2. Correlation IDs

```go
// Add correlation ID to all requests
func correlationIDMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        correlationID := r.Header.Get("X-Correlation-ID")
        if correlationID == "" {
            correlationID = generateUUID()
        }
        
        ctx := context.WithValue(r.Context(), "correlation_id", correlationID)
        w.Header().Set("X-Correlation-ID", correlationID)
        
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

### 3. Metric Cardinality

```go
// Good: Low cardinality
httpRequestsTotal.WithLabelValues("GET", "/users", "200").Inc()

// Bad: High cardinality (user IDs change frequently)
httpRequestsTotal.WithLabelValues("GET", "/users", "200", userID).Inc()
```

### 4. Sampling Strategies

```go
// Sample only errors and slow requests
func shouldSample(duration time.Duration, statusCode int) bool {
    return statusCode >= 500 || duration > 1*time.Second
}
```

## Performance Optimization

### 1. Metric Collection Optimization

- Use histograms for latency instead of multiple gauges
- Batch metric updates when possible
- Use appropriate scrape intervals
- Limit metric cardinality

### 2. Log Aggregation Optimization

- Use structured logging
- Implement log sampling for high-volume endpoints
- Compress logs before transmission
- Use appropriate log levels

### 3. Trace Sampling

```go
// Adaptive sampling based on error rate
func shouldSample(span *trace.Span) bool {
    errorRate := getErrorRate()
    if errorRate > 0.1 {
        return true  // Sample all when errors are high
    }
    return rand.Float64() < 0.01  // Sample 1% normally
}
```

## Alerting Strategies

### Alert Fatigue Prevention

- Use alert grouping
- Implement alert deduplication
- Set appropriate thresholds
- Use alert severity levels

### SLO-Based Alerting

```yaml
# SLO: 99.9% availability
# Alert when error budget is consumed
- alert: ErrorBudgetExhausted
  expr: |
    (1 - sum(rate(http_requests_total{status=~"5.."}[5m])) 
    / sum(rate(http_requests_total[5m]))) < 0.999
  for: 5m
```

This comprehensive guide provides enterprise-grade monitoring and observability patterns for building production-ready observable systems with Prometheus, Grafana, ELK stack, and distributed tracing.

