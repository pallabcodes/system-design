Resource: https://youtu.be/kmVUbngCyOw?list=TLGG6H4iI7ZxlfwxNTAyMjAyNg

Based on the transcript of the presentation "AWS re:Invent 2017: Deconstructing SaaS: A Deep Dive into Building Multi-tenant Solu (ARC407)" by Todd Golding, here is an accurate, comprehensive extraction of the content from start to end.

### **Introduction and Scope**
Todd Golding, a Partner Solutions Architect specializing in SaaS, introduces the session as a "400-level" deep dive. Unlike previous years that focused on general principles, this session dissects a specific, deployable reference implementation of a SaaS solution.
*   **Target Audience:** Assumes knowledge of SaaS fundamentals (partitioning, isolation).
*   **The Solution Model:** The reference architecture is a **Pooled Multi-tenant Solution**, meaning infrastructure resources (compute, storage) are shared by all tenants rather than siloed.
*   **Core Topics:** The talk covers Onboarding, Authentication/Identity, Application Services, Storage Partitioning, and Tenant Isolation. Operations (metrics/billing) are touched upon but limited due to time.

### **The Technology Stack**
The reference solution utilizes a standard, high-availability AWS architecture:
*   **Frontend:** AngularJS web app deployed on S3.
*   **Gateway:** Amazon API Gateway. Golding advises using a managed gateway for SaaS to handle throttling (tier-based) and API key management. It utilizes a **Custom Authorizer** (Lambda) for security.
*   **Compute:** Node.js Express microservices running in an Amazon ECS cluster (Auto-scaled).
*   **Storage:** DynamoDB (Pooled).
*   **Identity:** Amazon Cognito (End-to-end identity provider). A mirrored solution using Okta is also mentioned as available.
*   **Infrastructure:** Multi-AZ VPC, Public Subnets (NAT Gateway, Load Balancers), and Private Subnets (App services).

### **1. Onboarding and Registration**
Onboarding is described as an intensive process involving the orchestration of multiple components.
*   **User Experience:** Registration form $\rightarrow$ Success message $\rightarrow$ Email with temp password $\rightarrow$ Login $\rightarrow$ Password change. Cognito handles the heavy lifting of emails and password policies.
*   **Under the Hood (The Registration Service):** When "Register" is clicked, the `Tenant Registration Service` orchestrates three distinct legs:

    **A. User and Identity Provisioning (Cognito):**
    *   **User Pools:** The system provisions a distinct **User Pool per Tenant**. This allows for tenant-specific policies (MFA, password strength).
    *   **Federated Identity:** An Identity Pool is created to bind the User Pool to federated identities.
    *   **OpenID Connect (OIDC) & Custom Claims:** This is crucial. The system extends standard OIDC claims to include SaaS-specific context: `TenantID`, `Role`, `Company`, `Plan`. These attributes become "first-class citizens" in the identity profile.
    *   **IAM Policies:** The system provisions specific IAM policies for every user role needed by the tenant (e.g., Read-Only, Admin) to ensure isolation.

    **B. Tenant Configuration:**
    *   A record is created in a DynamoDB `Tenant` table (Tenant ID, status, plan). Users added later are bound to this existing tenant record.

    **C. Billing Integration:**
    *   **Asynchronous Queue:** The registration service pushes a message to a queue to provision the billing account.
    *   **Why a Queue?** To ensure fault tolerance. If the external billing system is down or slow, it should not block the user from registering and accessing the application.

### **2. Authentication and Login**
The login flow deviates from standard implementations to support the "User Pool per Tenant" model.
1.  **User Manager Service:** The client app first calls a lookup service to determine which User Pool the user belongs to.
2.  **Cognito Authentication:** The app authenticates against the specific User Pool.
3.  **The Result:** A **JSON Web Token (JWT)** is returned.
    *   *Crucial Detail:* Because of the Custom Claims setup during onboarding, this JWT contains both the User Identity *and* the SaaS Identity (Tenant ID, Role). This single token provides the context for all downstream services.

### **3. Application Services (The Developer Experience)**
The goal is to hide multi-tenancy complexity from the microservice developers.
*   **Context Passing:** Every service request includes the JWT (Bearer Token) in the Authorization header. Service-to-service calls propagate this token.
*   **The Token Manager:** A library/helper used by developers to extract data without parsing logic manually.
    *   `getTenantId()`: Extracts Tenant ID from the token for data queries.
    *   `getCredentials()`: Exchanges the token for scoped AWS credentials (Secret Key/Access Key) to access AWS resources securely.

### **4. Security Layer 1: API Gateway Custom Authorizer**
Before traffic hits the microservices, a Lambda Custom Authorizer inspects the incoming JWT.
*   It constructs a policy allowing or denying access to specific API methods.
*   *Example:* If the token indicates an "Admin" role, all methods are allowed. If "Standard User," only GET methods are permitted.
*   This provides a coarse-grained security layer at the edge.

### **5. Storage Partitioning (Data Access)**
*   **DynamoDB:** Uses the **Tenant ID as the Partition Key**. The Sort Key is the resource ID (e.g., Product ID).
*   **Data Access Code:**
    1.  Developer calls `getCredentialsFromToken()` to get scoped security keys.
    2.  Developer configures the query parameters (e.g., `Where TenantID = X`).
    3.  **The DynamoDB Helper:** A custom wrapper was built around the DynamoDB client.
        *   *Reason:* Standard third-party helpers often cache credentials globally or rely on general AWS config. In a pooled SaaS model, credentials must be re-evaluated **per call** to ensure the correct tenant scope is applied.

### **6. Security Layer 2: Tenant Isolation (IAM Policies)**
This is the most critical security layer, ensuring a user *cannot* access another tenant's data even if they try to inject a different Tenant ID in the query.

*   **IAM Policy Structure:** Policies are generated during onboarding.
    *   They use **DynamoDB Leading Keys**.
    *   *Condition:* `dynamodb:LeadingKeys` must match the `${TenantID}`.
    *   This enforces that the credentials used can *only* read/write items where the Partition Key matches the tenant.
*   **Binding Identity to Policy (Cognito Role Matching):**
    *   How does the system know which policy to apply to a specific user?
    *   Cognito **Role Matching Rules** are configured to map the custom attribute `Role` (from the JWT) to a specific IAM Role (which holds the policies).
*   **Runtime Execution:**
    *   The service calls `Cognito Identity: GetCredentialsForIdentity`.
    *   It passes the JWT.
    *   Cognito inspects the `Role` attribute in the token, evaluates the matching rule, assumes the correct IAM Role, and returns the temporary, scoped credentials.
    *   If using a different provider (non-Cognito), developers would manually call the STS `AssumeRole` API to achieve this.

### **7. Client-Side (AngularJS)**
*   **Root Scope:** The client decodes the JWT to extract the `Role` and `TenantID` for display and UI logic.
*   **UI Logic (`isLinkEnabled`):** A helper function checks the user's role against view locations.
*   **Directives:** HTML uses `ng-if` combined with `isLinkEnabled` to hide/show navigation links (e.g., "Users" tab is hidden for non-admins).
*   *Warning:* Golding emphasizes that client-side logic is purely for User Experience. Real security relies entirely on the Server/API Gateway/IAM layers.

### **8. Operations and Caveats**
Golding notes three features are in the architecture but were being added to the downloadable code at the time of the talk:
*   **Billing:** The asynchronous queue integration.
*   **S3 Partitioning:** Using Object Tagging for isolation similarly to DynamoDB.
*   **Metering:**
    *   Architecture: Services $\rightarrow$ Metering Agents $\rightarrow$ Kinesis Firehose $\rightarrow$ Redshift $\rightarrow$ Billing Aggregation.
    *   Meters must consult a Tenant Manager to understand specific SLAs or tier configurations before recording metrics.

### **9. Admin Console**
A simple dashboard is included to demonstrate the "System Admin" view (cross-tenant health) versus the "Tenant Admin" view (single-tenant management).

### **Conclusion and Takeaways**
*   **Identity is Key:** SaaS architecture is fundamentally about binding tenant context to identity and propagating it.
*   **Isolation via Policy:** Use IAM policies and credential scoping to enforce boundaries, not just code logic.
*   **Developer Efficiency:** Abstract complexity into libraries (`TokenManager`, `DynamoDBHelper`) so developers can focus on business logic.
*   **Vertical Slicing:** When building SaaS, do not build in horizontal layers. Build one feature end-to-end (e.g., "Add Product") to prove the entire chain of Identity $\rightarrow$ Policy $\rightarrow$ Isolation works before scaling.


Q: How do OIDC custom claims simplify multi-tenant context propagation?

Q: Can you exaplain how leading keys in IAM prevent cross-tenant access?

Q: Why is a custom authorizer better than standard service-level security?