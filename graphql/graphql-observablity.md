Resource: https://youtu.be/Retjj8_O9JE


Based on the transcript of the presentation "GraphQL Observability with Elastic and OpenTelemetry" by Michael Staib at NDC Copenhagen 2022, here is an accurate and comprehensive extraction of the content from start to end.

### Introduction to GraphQL in Production
The speaker begins by defining the scope of the talk: exploring GraphQL observability to identify production issues before customers report them. While applicable to REST or gRPC, GraphQL presents unique challenges.

**The Core Problem:**
*   In GraphQL, the frontend developer decides the shape of the request, reversing the traditional backend-driven responsibility. While this empowers frontend developers, it poses risks for the backend if requests become too large or complex.
*   **Architecture Complexity:** Simple setups (a thin GraphQL layer over logic) are manageable. However, enterprise environments are complex, often treating GraphQL as a gateway over existing domain services (REST, gRPC, Thrift).
*   **The Netflix Example:** The speaker cites Netflix's architecture where a gateway splits into domain services, which further split into microservices. In such scenarios, debugging performance degradation or identifying "who broke what" is extremely difficult.

### Debugging Approaches
The speaker introduces a demo cryptocurrency application that has a known performance issue.

1.  **Local Debugging ("Poor Man's Approach"):**
    *   A developer typically runs the app locally and checks logs (Console/Serilog).
    *   In the demo, a single request triggers multiple SQL and REST requests. However, locally, this looks fast because there is no load or scale pressure.

2.  **Apollo Tracing (Deprecated):**
    *   Early in GraphQL's history, Apollo introduced a tracing format included in the response payload.
    *   **Downsides:** It bloats the response size (dangerous in production), requires a manual "pull" (you have to execute a query to see data), and only shows resolver execution time, not underlying system behavior. It is effectively deprecated.

### Observability and OpenTelemetry
The talk shifts to the solution: **Observability**.
*   **Historical Context:** In the past, companies (like a Swiss insurance company cited) spent years building custom observability platforms because standards didn't exist.
*   **OpenTelemetry (OTEL):** This is the modern standard, merged from OpenTracing and OpenSensors. It is vendor-neutral (unlike using a specific vendor's agent) and supported by major tech companies like Microsoft.
*   **Current Status:** At the time of the talk, OTEL for .NET is in Release Candidate (RC) status, but highly recommended over vendor lock-in.

**Concepts:**
*   **MELT:** Metrics, Events, Logs, and Traces.
*   **Architecture:** You instrument the application $\rightarrow$ Collect data $\rightarrow$ Export to a backend (Elastic, Honeycomb, Jaeger).
*   **The Collector:** In production, a "Collector" service runs locally (e.g., sidecar) to batch data before sending it to the backend.

### Implementation Demo
The speaker walks through instrumenting the .NET GraphQL server (using Hot Chocolate) to report to Elastic.

**Step 1: Resource Builder**
*   The service must be identified using a `ResourceBuilder`.
*   Metadata is added: Service Name (`coin-api`), Namespace (`demo`), Version (`1.0.0`), and Environment attributes. This helps filter data (e.g., Production vs. Development) in the backend.

**Step 2: Instrumentation**
*   **Metrics:** Added via `OpenTelemetry.Instrumentation.Http` and `AspNetCore`.
*   **Databases:** Telemetry is available for drivers like Entity Framework, Postgres, and MongoDB (e.g., Jimmy Bogart’s library).
*   **Hot Chocolate:** The speaker uses the `HotChocolate.Diagnostics` package to automatically generate events.
*   **Tracing:** Setup includes HTTP Client, ASP.NET Core, and Hot Chocolate instrumentation.

**Step 3: Exporter (OTLP)**
*   The demo uses the OTLP (OpenTelemetry Protocol) exporter to send data natively to Elastic.
*   Configuration requires the Elastic endpoint and authorization headers (API Key).

### Analyzing Data in Elastic
Once data is flowing, the speaker navigates the Elastic Observability interface.

1.  **Service Map:**
    *   Elastic visualizes the architecture: `CoinAPI` talks to `PriceAPI` (an Azure Function) and `Postgres`.
    *   It includes anomaly detection, warning if the system state deviates from the norm.

2.  **Refining Traces (Activity Enricher):**
    *   **Problem:** By default, requests are aggregated under generic HTTP middleware names, making it hard to distinguish GraphQL queries.
    *   **Solution:** The speaker implements a custom `ActivityEnricher`. This class overrides the root activity's display name with the GraphQL operation name.
    *   **Implementation:** Using the .NET Activity API, the enricher acts as a hook to rewrite telemetry metadata before export.

3.  **Root Cause Analysis:**
    *   With the enricher, the trace shows the specific query: `DashboardContainerQuery`.
    *   **Drill Down:** The trace reveals the `assets` field (aliased as `ticker` by the frontend) triggers a `PriceService`.
    *   **The Bug:** The `PriceService` is executing a suspicious SQL query pattern—specifically, performing a `COUNT` operation followed by fetching data, repeated multiple times. This N+1 or inefficient data fetching strategy is identified as the bottleneck causing pressure.

### Custom Metrics and Alerting
To move from reactive debugging to proactive alerting, the speaker introduces **Custom Metrics**.

**1. Creating a Meter:**
*   Using the new .NET `Meter` API, the speaker creates a meter named `demo.graphql`.
*   A Counter is defined (`requests`) to track the volume of incoming requests.

**2. Hooking into GraphQL Events:**
*   An `ExecutionDiagnosticEventListener` (or interceptor) is created in Hot Chocolate.
*   On every `ExecuteRequest` event, the counter is incremented.
*   This is registered in the Dependency Injection container (`AddMeter`, `AddDiagnostics`).

**3. Visualization and Alerting:**
*   In the Elastic dashboard, this custom metric appears under `requests`.
*   **Anomaly Detection:** Users can define rules (e.g., "If request count or SQL query count deviates from the normal baseline, send an email or Teams message").
*   This allows developers to be notified immediately if a deployment changes the performance characteristics (e.g., jumping from 1 SQL query to 6 SQL queries per request).

### Conclusion
The speaker summarizes that OpenTelemetry combined with tools like Elastic (or alternatives like Honeycomb and Jaeger) provides a cost-effective and flexible way to secure production environments. He emphasizes that with .NET 7, OpenTelemetry will likely reach full release status, making it the ideal time to adopt it.