Resource: https://youtu.be/pG-NinTx4O4

Based on the transcript of the video **"Multitenant Mystery: Only Rockers in the Building"** by **Thomas Vitale** at Spring I/O 2023, here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Definition**
Thomas Vitale introduces himself as a software engineer, Cloud Architect, and author of *Cloud Native Spring in Action*. He presents the topic of multi-tenant applications, noting that while many developers work with them, they are often challenging to build.

**What is Multi-tenancy?**
Vitale defines multi-tenancy as an architecture where a single running instance of an application simultaneously serves multiple clients (tenants). This is common in SaaS (Software as a Service) solutions.
*   **The Goal:** Optimize costs regarding operations, maintenance, and resources. Instead of spinning up a new instance for every new customer (which is not scalable), all customers share the infrastructure.
*   **The Metaphor:** He compares this to a building inhabited by rock bands. The bands (tenants) share the infrastructure (roof, elevator), but each has a private apartment and storage for their instruments.
*   **The Mystery:** Vitale sets up a premise for the session: a guitar has gone missing from one of the bands and has been replaced by a "fake" duplicate. The audience is tasked with paying attention to solve this mystery by the end of the talk to win a copy of his book.

### **Phase 1: Tenant Resolution and Context**
The first technical step is establishing a standard Spring Boot application (an Instrument Service) and introducing the concept of a tenant.

1.  **Tenant Resolver:** The application needs to identify the tenant from an incoming request (HTTP, RabbitMQ message, or JWT). Vitale defines a `TenantResolver` interface. For a web app, he implements this to look for a custom HTTP header, configurable via properties (e.g., `X-TenantID`).
2.  **Tenant Context:** Once resolved, the tenant ID must be stored where it is accessible for the duration of the request. Vitale creates a `TenantContext` class using a `ThreadLocal` to store the ID, with methods to set, get, and clear the value.
3.  **Interceptor:** He implements a Spring MVC `HandlerInterceptor`.
    *   **Pre-processing:** Intercepts the request, uses the resolver to find the ID, and sets it in the `TenantContext`.
    *   **Post-processing:** Clears the context after the request finishes (whether successful or if an exception occurs) to prevent data leaking to other threads.
    *   **Configuration:** The interceptor is registered via `WebMvcConfigurer`.

### **Phase 2: Data Isolation**
Vitale identifies data isolation as the most critical part of multi-tenancy to ensure customers do not access each other's data. He outlines three main strategies:

1.  **Discriminator Column:** Adding a `tenant_id` column to every table. This is risky because developers must ensure every SQL statement includes the discriminator. If one `WHERE` clause is missed, data leaks.
2.  **Separate Schema:** Using one database but different schemas for each tenant. The connection switches schemas based on the tenant. This is a good trade-off as isolation is handled at the connection level, not the query level.
3.  **Separate Databases:** Maximum isolation but higher resource usage (separate connection pools required).

**Implementation (Separate Schema Strategy):**
Vitale proceeds to implement the **Separate Schema** strategy using Spring Data JPA, Hibernate, and PostgreSQL.
*   **Setup:** He uses Spring Boot 3.1 and Testcontainers. He highlights the new `@ServiceConnection` annotation in Spring Boot 3.1, which automatically configures the application to connect to the Testcontainer (Postgres) without manual property definition.
*   **The Data:** He creates an `Instrument` entity and a repository. He manually creates two schemas in the database: `dukes` and `beans`.
*   **Hibernate Configuration:**
    *   **`CurrentTenantIdentifierResolver`:** An interface that tells Hibernate who the current tenant is by reading from the `TenantContext`. It falls back to the "public" schema if no tenant is found.
    *   **`MultiTenantConnectionProvider`:** An interface that intercepts the database connection. Vitale implements this to take a connection from the datasource and execute a command to set the specific schema (e.g., `SET SCHEMA 'tenant_id'`) before returning it. When the connection is released, it resets to the default schema.
    *   **Registration:** Since these cannot be auto-wired by default, he implements `HibernatePropertiesCustomizer` to explicitly tell Hibernate to use these custom resolver and provider classes.

### **Phase 3: Caching and Observability**
**Caching:**
To improve performance, Vitale enables Spring Cache and adds the `@Cacheable` annotation to the `findAll` endpoint.

**Observability:**
In a multi-tenant system, logs, metrics, and traces must be identifiable by tenant to facilitate troubleshooting.
*   **Logs:** He modifies the Interceptor to add the `tenantID` to the MDC (Mapped Diagnostic Context) so it appears in logs.
*   **Metrics and Traces:** He uses the Micrometer Observation API (standard in Spring Boot 3). He hooks into the `ServerHttpObservationFilter` to add the `tenant.id` as a key-value pair.
    *   **Cardinality Decision:** He chooses to add this as a **High Cardinality** key (for traces) rather than Low Cardinality (for metrics). He explains that unbounded values (like tenant IDs) in metrics can explode cardinality and become expensive, whereas they are safe and useful in traces.

### **Phase 4: The Gateway and Dynamic Routing**
Vitale addresses the issue that clients shouldn't send technical headers like `X-TenantID`. Instead, they use DNS (e.g., `dukes.rock` or `beans.rock`).
*   **Spring Cloud Gateway:** He sets up a gateway service to sit in front of the application.
*   **Routing Logic:** He configures a route using a host predicate (`*.rock`). A filter extracts the subdomain (the tenant name) from the hostname and automatically adds the `X-TenantID` header before forwarding the request to the backend service. This keeps the tenant resolution internal.

### **Phase 5: Security (Authentication)**
The application must handle authentication for different tenants, likely using different Identity Providers (IdPs) or realms.
*   **Dynamic Configuration:** Instead of hardcoding `issuer-uri` in `application.properties`, the application must resolve the provider dynamically based on the tenant.
*   **Implementation Strategy:** Vitale sets up Keycloak with two realms (`dukes` and `beans`). He explains that in Spring Security, one needs to provide a custom `ClientRegistrationRepository` (for the frontend/login) and an `AuthenticationManagerResolver` (for the backend resource server) to verify tokens against the correct realm dynamically.

### **The Mystery Solved**
During the demo, Vitale simulates load and checks the application. The "Dukes" tenant sees their correct instruments. However, when checking the specific "guitar" endpoint:
*   **The Issue:** The Dukes band sees a "fake" guitar (data belonging to the Beans tenant).
*   **Investigation:** Vitale checks the Tempo traces (Grafana stack). He finds that for the request serving the wrong data, there was **no database call**. This implies the response came from the cache.
*   **The Root Cause:** The `@Cacheable` annotation on the controller used the default key generation strategy, which is based only on method parameters. Since the method didn't take a tenant ID as an argument, the cache key was identical for all tenants. The "Beans" tenant accessed the guitar first, caching their data. When "Dukes" requested it, they received the cached "Beans" data.
*   **The Fix:** Vitale implements a custom `KeyGenerator` that incorporates the `TenantContext.getTenantId()` into the cache key. After applying this fix, the data is correctly isolated.

### **Conclusion**
Vitale summarizes the lesson: **Data isolation is the most critical part of multi-tenancy.** Developers must be careful not just with the database, but with every layer, including caching, to ensure data does not leak between tenants.