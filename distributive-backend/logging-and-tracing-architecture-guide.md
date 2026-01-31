# Logging & Distributed Tracing: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: OpenTelemetry, ELK/PLG Stack, Sampling Strategies, and Cost Management.

> [!IMPORTANT]
> **The Principal Problem**: Observability is a Big Data problem. At scale, **logging everything is a denial-of-service attack on your wallet**. You must move from "Log Everything" to "Sample Smartly".

---

## 🏗️ The Observability Stack (The 3 Pillars)

| Pillar | Purpose | Tooling (Modern) | Retention |
| :--- | :--- | :--- | :--- |
| **Logs** | "What happened?" (Events) | Loki / Elasticsearch | Short (7-30 days) |
| **Metrics** | "Is it healthy?" (Aggregates) | Prometheus / cortex | Long (1-2 years) |
| **Traces** | "Where did it go?" (Context) | Jaeger / Tempo | Very Short (3 days) |

### The "Golden Signal" (Correlation)
The most critical part of the stack is **Correlation**.
*   User reports error `500`.
*   You find 500 in **Metrics**.
*   You click to see **Trace** `abc-123`.
*   Trace reveals **Log** with `msg="DB Connection Failed"`.
*   **Requirement**: `TraceID` and `SpanID` must be injected into every Log line.

---

## 📡 OpenTelemetry (The Industry Standard)

Vendor lock-in is dead. Use **OpenTelemetry (OTel)** for instrumentation.

### The OTel Collector Architecture
Do not send data from App -> Vendor (DataDog/NewRelic). Send App -> OTel Collector -> Vendor.

```mermaid
graph LR
    App[Microservice A] -->|OTLP| Agent[OTel Agent (Sidecar)]
    App2[Microservice B] -->|OTLP| Agent
    
    Agent -->|Batch| Gateway[OTel Gateway (Cluster)]
    
    Gateway -->|Filter/Sample| ES[Elasticsearch (Logs)]
    Gateway -->|Metrics| Prom[Prometheus]
    Gateway -->|Traces| Tempo[Grafana Tempo]
```

*   **Benefit**: You can switch backends (e.g., DataDog to Grafana) by changing 5 lines of YAML in the Collector, without touching application code.

---

## 📉 Sampling Strategies (Saving Millions)

Tracing every request (Head Sampling 100%) works for startups. For Google-scale, it's impossible.

### 1. Head Sampling (Probabilistic)
"Flip a coin at the start".
*   *Config*: `sampling_rate = 0.01` (1%).
*   *Pros*: Cheap, easy.
*   *Cons*: You might miss the ONE interesting error in the 99% you dropped.

### 2. Tail Sampling (The Holy Grail)
"Keep the whole trace in memory, decide at the end".
*   *Logic*: If `error=true` or `latency > 2s`, KEEP. Else DROP.
*   *Pros*: You keep 100% of errors and slow requests, but store 0% of boring "200 OK" requests.
*   *Cons*: High memory usage on the OTel Gateway (must buffer spans).

> [!TIP]
> **Principal Recommendation**: Use **Tail Sampling** for Traces. It drastically increases signal-to-noise ratio and reduces storage costs by 90%.

---

## 🪵 Logging Best Practices

### 1. Structured Logging (JSON)
Text logs (`2023-01-01 Error processing order`) are greppable but not queryable.
Use JSON:
```json
{"level":"error","ts":"2023-01-01T12:00:00Z","msg":"Failed","order_id":"123","trace_id":"abc"}
```
Now you can query: `logs | json | where order_id == "123"`.

### 2. Log Levels Matter
*   **DEBUG**: Disabled in Prod.
*   **INFO**: "Business Event" (Order Placed). NOT "Function entered".
*   **WARN**: Recoverable issue (Retry).
*   **ERROR**: Operator intervention needed. Alert on this.

### 3. Context Propagation
Always pass `context` (Go) or use `ThreadLocal` (Java) to carry the `TraceID`. If you lose the context, the log is an orphan.

---

## ✅ Principal Architect Checklist

1.  **Deploy OTel Collectors**: Never instrument directly to a backend. decouple early.
2.  **Inject TraceIDs into Logs**: Ensure your logger (Logback/Zap) is configured to pull `TraceID` from the context.
3.  **Implement Tail Sampling**: Set up the rules: `if status >= 400 sample 100%`.
4.  **Cost Control**: Monitor the "Ingestion Rate" daily. If a developer leaves a `DEBUG` log in a tight loop, it can cost $10k/month.
5.  **Alert on Golden Signals**: Latency, Errors, Traffic, Saturation. Do not alert on "CPU > 80%" (that's just good utilization).

---

## 🔗 Related Documents
*   [Multi-Tenancy Observability](../multi-tenancy/multi-tenancy-spring-implementation.md) — Tagging metrics with Tenant ID.
*   [Async Systems](../async-systems-guide.md) — Tracing through Kafka.

## Principal Architect's Q&A

**Q: Do we strictly need to modify code to get Tracing? What about eBPF?**

**A:** As of 2025, **eBPF (Zero-Instrumentation)** is the default for "Red" metrics (Rate, Errors, Duration) and network mapping, but manual code instrumentation is still superior for *business logic* context.
1.  **eBPF Magic**: Tools like Cilium/Tetragon or OTel Auto-Instrumentation can visualize the entire service graph and network calls without a single line of code change. This is "free" observability.
2.  **The Business Gap**: eBPF knows about "HTTP 500", but it doesn't know about "Cart Checkout Failed due to Inventory". For high-value business insights, you still need manual traces: `span.setAttribute("user.id", ...)` and `span.recordException(err)`.
3.  **High Cardinality Cost**: Warning—putting `user_id` in *metrics* labels (Prometheus) allows for millions of time-series, effectively bankrupting your metrics cluster. Put high-cardinality data in *Logs/Traces*, not Metrics.
