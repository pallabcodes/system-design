Based on the transcript of the video "stackconf online 2020 | Securing Infrastructure with Keycloak by Rahul Bajaj," here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction**
Rahul Bajaj introduces himself as a software engineer at Red Hat who has completed certifications in DevOps and administration. He invites the audience to reach out via Twitter or GitHub and directs them to his blog. He outlines the agenda for the talk:
1.  Authentication.
2.  JSON Web Tokens (JWTs).
3.  OAuth 2.0.
4.  OpenID Connect.
5.  OAuth 2.0 workflows.
6.  Using Keycloak as an OpenID provider.
7.  Implementing Single Sign-On (SSO) for the Foreman project.

### **Authentication**
Bajaj defines authentication as the process applications use to determine and confirm the identities of users. The main goals are ensuring users see the correct content and, more importantly, securing content against unauthorized users.

**Types of Authentication:**
*   **Password Authentication:** A user enters a username and password. The server authenticates them and replies with a session ID stored in cookies. Subsequent requests use cookies. While common (often used with sticky sessions or Memcached), Bajaj notes this method is not very scalable.
*   **Token-Based Authentication:** To scale applications, Bajaj recommends this method. It involves a payload used to authenticate the user, allowing them access to resources based on the data within that payload.

### **JSON Web Tokens (JWT)**
Bajaj introduces the standard for token-based authentication: the JSON Web Token (JWT).
*   **Structure:** A JWT is a Base64 encoded string comprising three parts, distinguished by colors in his diagram:
    1.  **Header (Pink):** A JSON object containing metadata, usually consisting of the Algorithm (`alg`) and the Type (`typ`).
    2.  **Payload (Blue):** Contains the data/claims.
    3.  **Signature:** Ensures integrity.

**Detailed Breakdown:**
*   **Header:** Contains key-value pairs. Keys are often short three-letter words. `alg` stands for Algorithm, and `typ` stands for Type (usually "JWT").
    *   *Future Spec (Typed JWT):* Bajaj mentions a future specification to address confusion when applications use JWTs for multiple purposes (access tokens, logout tokens, etc.). The proposal is to use a specific type in the header, such as `at+jwt` (Access Token + JWT) to differentiate them.
*   **Payload:** Contains the claims. Standard fields include `jti` (JWT ID), `exp` (expiration), `iat` (issued at), `iss` (issuer), `sub` (subject), and `aud` (audience). Custom keys can also be added via the OpenID provider (like Keycloak).
*   **Signature:** This prevents attackers from simply decoding and modifying the Base64 string. The signature is created by taking the encoded Header, the encoded Payload, and a **Secret** provided by the authorization server. These three elements are encoded together using an algorithm (like HMAC SHA256 or RSA). This ensures the token's trustworthiness.

### **OAuth 2.0**
Bajaj clarifies that "Auth" in OAuth stands for **Authorization**, not authentication.
*   **Use Case:** It is used when an application needs permission to access a resource on another application (e.g., logging in via Google or Facebook).
*   **Analogy:** He compares it to parents visiting an office. They are given a visitor badge (access token) that allows access to common areas but restricts them from the actual workspace.
*   **General Flow:** A client requests access. It must first authenticate with an **Authorization Server**. The server returns an **Access Token**. The client uses this token to access resources from a **Resource Server**.

### **OpenID Connect (OIDC)**
*   **Definition:** OIDC is a thin layer on top of OAuth 2.0. It is an internet standard for Single Sign-On (SSO).
*   **Workflow:** The user authenticates with an OpenID Provider.
*   **The Difference:**
    *   **OAuth 2.0:** Returns an **Access Token** (used to access specific resources).
    *   **OpenID Connect:** Returns an **ID Token**. This token contains the authentication status and user payload information.
    *   *Correction in presentation:* Bajaj corrects a visual error in his slides where he confused the terms, reiterating that OAuth returns access tokens for resources, while OIDC returns ID tokens for identity/authentication information.

### **OAuth 2.0 Workflows**
Bajaj discusses two main workflows:

1.  **Password Grant Flow:** Similar to standard password authentication. The user provides credentials to get an access token. Bajaj notes this is messy and likely to be deprecated.
2.  **Authorization Code Grant Flow:** The industry standard, highly recommended.
    *   **Step 1:** The user/browser attempts to access an application and is redirected to the **Authorization Server**.
    *   **Step 2:** The user authenticates (via username/password, OTP, smart card, etc.).
    *   **Step 3:** If successful, the server returns a **Code** (a string of letters) to the browser.
    *   **Step 4:** The browser/client sends this Code back to the Authorization Server to verify it.
    *   **Step 5:** If the code is accurate, the server returns an **Access Token**, which the client uses to access the application.

### **Keycloak as an OpenID Provider**
Bajaj demonstrates the Keycloak administration console.
*   **Realms:** He creates a realm called "stackconf."
*   **Clients:** Applications to be integrated are registered as "Clients."
*   **Identity Providers:** Keycloak supports social logins (Google, Twitter) and user-defined providers (SAML 2.0, OIDC). For organizations, it supports LDAP and Kerberos.
*   **Authentication Flows:** Supports various bindings/flows like Smart Card, OTP, etc.
*   **Client Settings:** He shows a client configuration screen, highlighting options like "Access Type" (confidential, public, bearer-only) and "Valid Redirect URIs."

### **Security Best Practices & Pitfalls**
Bajaj shares challenges and best practices based on his experience and community discussions.

1.  **Client Access Types:**
    *   **Confidential Clients:** These have a **Secret** (symmetric key) shared between the client and server. Used for server-side applications capable of keeping the secret safe.
    *   **Public Clients:** These **do not use secrets** because they cannot keep them safe (e.g., mobile apps, single-page apps).
    *   *Advice:* Do not just default to "Confidential." Identify if your app is public or confidential and configure it accordingly. The spec advises creating different clients for different access types.

2.  **Redirect URIs:**
    *   Must be very specific.
    *   *Warning:* Do not use wildcards (e.g., `domain/*` or `*.example.com`). This leaves the application vulnerable to attacks.

3.  **PKCE (Proof Key for Code Exchange):**
    *   In public clients using the Authorization Code Flow, the "Code" might be intercepted (e.g., if SSL terminates at the load balancer and traffic becomes plain text).
    *   **PKCE** is an extension that secures the code exchange. It is mandatory for public clients (mobile/JS apps) and considered best practice for all clients to prevent interception attacks.

4.  **Session Management:**
    *   The OIDC spec does not strictly define how to manage sessions (e.g., exact logout timing or token lifespans).
    *   **Refresh Tokens:** Bajaj explains the mechanism:
        *   An Authorization Server issues an Access Token (short-lived) and a Refresh Token (long-lived).
        *   When the Access Token expires, the client sends the Refresh Token to the server to get a new pair (Access Token + Refresh Token).
    *   *Cross-Device Logic:* The spec does not dictate if logging out on a mobile device should log you out on a browser. This logic is up to the application architect.

### **Implementation: SSO with Foreman**
Bajaj explains how they implemented SSO for **Foreman**, a complete lifecycle management tool (provisioning, configuration, monitoring).

**The Architecture:**
1.  **Hammer CLI (Client):** The command-line interface for Foreman.
2.  **Foreman (Server):** The application being accessed.
3.  **Keycloak:** The OpenID Provider.

**The Workflow:**
1.  **Request:** Hammer CLI requests a token.
2.  **Authentication:** The user is redirected to the Keycloak login page (via browser).
3.  **Code/Token Exchange:** Upon successful login, Keycloak returns a code. Hammer exchanges this code for an Access Token.
4.  **Verification:** Hammer passes this Access Token to the Foreman server.
5.  **Validation (Crucial Step):** Foreman cannot simply trust the token. It must validate the JWT. It decodes the header, payload, and signature. It checks:
    *   Does the algorithm match?
    *   Is the signature valid?
    *   Do claims like Audience (`aud`) and Issuer (`iss`) match the expected values?
    *   These parameters are checked against Keycloak's "Well-Known Configuration" endpoint (`.well-known/openid-configuration`), which provides the necessary public keys (`jwks_uri`) and endpoints.
6.  **Session Creation:** If valid, Foreman creates a user in its internal database (if it doesn't exist), creates a session ID, and returns that ID to Hammer for future interactions.

**The Demo:**
Bajaj performs a live demo using the terminal.
*   He runs `hammer auth login --two-factor`.
*   The terminal prompts him to enter a URL in his browser.
*   He copies the URL, logs into Keycloak (using a dummy user "XYZ"), and receives a code.
*   He pastes the code back into the terminal.
*   Hammer exchanges the code for a token, Foreman validates it, creates a session, and logs the user in.
*   He verifies the login by checking a session file on the server.

### **Conclusion and Takeaways**
Bajaj summarizes the three main takeaways:
1.  **Client Registration:** Identify your client type (Public vs. Confidential) and register them correctly.
2.  **Redirect URIs:** Be specific; do not use wildcards.
3.  **Session Management:** Decide on your strategy (Refresh tokens vs. session IDs) based on your specific application architecture.

He concludes by sharing references (blogs, journals, and YouTube videos from Dominic, Brian, and Nate) that helped him prepare and thanks the audience.