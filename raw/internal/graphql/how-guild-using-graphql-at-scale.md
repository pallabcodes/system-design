Resource: https://youtu.be/78ufgsWfgVc?list=TLGG3c6H5QKwPqkwODAyMjAyNg

Based on the transcript of the video "How The Guild is using GraphQL at scale" by Uri Goldshtein at The GraphQL Conf 2022, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction**
Uri Goldshtein, a founder and member of "The Guild," introduces the topic: **GraphQL Hive**. Hive is a SaaS service provided by The Guild that is also completely open-source. The talk has two main objectives:
1.  Explain what Hive is and why it is necessary for GraphQL APIs.
2.  Provide a glimpse into how The Guild implements GraphQL at scale internally, covering their backend, frontend, and service architecture, since Hive's entire source code is public.

### **About The Guild**
The Guild is a group of open-source developers who create and maintain popular tools in the GraphQL ecosystem, such as **GraphQL Code Generator**, **GraphQL Mesh**, and **GraphQL Yoga**.
*   **Structure:** Tools are built by the group but maintained under individual names and maintainers.
*   **Philosophy:** They build tools because they need them for their own work with major companies. They prioritize long-term maintenance (some tools have been maintained daily for 4-5 years) and avoiding vendor lock-in. They want users to have the freedom to use specific tools anywhere in their stack.

### **The Evolution: From Inspector to Hive**
To explain Hive, Uri first discusses the history of **GraphQL Inspector**, a tool they created to manage API versioning—a key benefit of GraphQL over other API styles.

**GraphQL Inspector (Static Analysis)**
*   **Function:** It integrates into a Git repository/CI to identify changes between schema versions.
*   **Breaking Changes:** It reports if a PR introduces breaking changes (e.g., removing a field) by statically analyzing the schema and operations.
*   **Capabilities:**
    *   It can fail CI processes to prevent breaking changes from reaching production.
    *   It works via a GitHub Action/App, sending reports and notifications (Slack, etc.).
    *   **Security Audit:** Through a collaboration with **Escape** (creators of **GraphQL Armor**), Inspector can statically analyze source code to recommend security defaults (like depth limiting) specific to that API.
    *   **Code Coverage:** It compares the schema against source code queries to find unused fields or duplicates.
*   **The Limitation:** Inspector relies solely on **static analysis**. In production, static analysis is insufficient because it cannot account for live clients (e.g., an old mobile app version still querying a "removed" field).

### **GraphQL Hive: The Solution**
Hive was created to bridge the gap between static analysis and live production data. It serves as a **Schema Registry** and **Performance Monitoring** tool.

**Key Features:**
1.  **Live Data Integration:** Unlike Inspector, Hive uses live data to determine if a change is breaking. For example, if a field is removed but hasn't been queried in 30 days, Hive (configurable) can classify this as non-breaking, allowing the API to evolve safely.
2.  **Schema Registry & High Availability:**
    *   It checks schema validity and supports merging multiple services (Federation, Schema Stitching, etc.).
    *   It stores the latest schema in a **High Availability CDN** separate from Hive's own infrastructure. If Hive goes down, the user's gateways (Apollo Gateway, Router, Mesh, etc.) can still fetch the schema from the CDN.
3.  **Observability:** It tracks error rates, latency, client usage, and provides lists of the most popular and slowest queries.
4.  **Data Privacy:** The Hive client runs on the user's server and fully obfuscates PII/sensitive data before sending usage statistics to Hive.

**Integration with GraphQL Mesh**
Uri highlights a workflow for companies with legacy services (OpenAPI, gRPC, SOAP) that cannot easily migrate to GraphQL.
*   **Workflow:** These services can run **GraphQL Mesh** locally to convert their protocols (e.g., Swagger) to GraphQL.
*   **Registry:** They publish these schemas to Hive.
*   **Gateway:** A central Gateway reads all schemas from Hive (regardless of the original protocol) and exposes a unified GraphQL API. This allows companies to query legacy REST/SOAP services via GraphQL.

### **The Business Model: Open Source SaaS**
Hive is a unique business case:
*   **SaaS:** It is a hosted cloud service for clients who do not want to manage a registry.
*   **Open Source:** It is fully MIT licensed. The entire codebase is public, including billing logic (Stripe integration), deployment code, and UI.
*   **Self-Hosting:** Companies can self-host Hive if they prefer, giving them full control over their data and infrastructure.

### **The Guild’s Tech Stack (Dogfooding)**
Because Hive is open-source, it serves as a reference architecture for how The Guild builds scalable applications. Uri invites users to explore the **graphql-hive** repository to see their best practices in action:

*   **Frontend:** Built with **Next.js** and **GraphQL Code Generator**. (Uri references a separate talk by Lauren on their specific frontend practices).
*   **Documentation:** Uses **Nextra** (The Guild recently became the main maintainers of this project).
*   **GraphQL Server:** Uses **GraphQL Yoga** with **Envelop** plugins.
*   **Federation:** Uses **GraphQL Modules** and a build process to merge services.
*   **Security:** Protected by **GraphQL Armor**.
*   **Error Tracking:** Integrated with **Sentry**.
*   **Monorepo Management:**
    *   **TurboRepo** for build orchestration.
    *   **Changesets** for release management.
    *   **Bob the Bundler:** A library created by The Guild for bundling code to support both ESM and CommonJS.
*   **Database:**
    *   **Postgres** for transactional data.
    *   **ClickHouse** for handling massive scale and traffic analytics.
*   **Authentication:** Migrated from Auth0 to **SuperTokens** (an open-source alternative) to ensure Hive remains fully self-hostable.
*   **Deployment:** Uses **Pulumi** for infrastructure as code, **Kubernetes**, **Azure**, and **Cloudflare Workers**.

### **Conclusion**
Uri emphasizes that The Guild’s ecosystem has grown from a single library (Codegen) to a full suite of tools that support each other. He invites the community to inspect the Hive codebase to learn, critique, or contribute.

He ends by crediting **Kamil Kisiela**, the individual creator and maintainer of GraphQL Hive. Uri notes that this structure—where projects live under the individuals who build them rather than just "The Guild" brand—is core to their philosophy.