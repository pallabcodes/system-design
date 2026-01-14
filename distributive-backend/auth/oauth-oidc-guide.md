# OAuth 2.0 & OIDC: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: OAuth 2.0 Flows, OIDC, JWT, and PKCE.

> [!IMPORTANT]
> **OAuth 2.0 is for Authorization (Access). OIDC is for Authentication (Identity).**
> If you need to know *who* the user is, you need OIDC. OAuth 2.0 alone only tells you *what* they can access.

---

## 🔐 OAuth 2.0: The 4 Grant Types

### 1. Authorization Code (The Standard)
*   **Use Case**: Server-rendered web apps.
*   **Flow**: Browser redirects to Auth Server → User logs in → Auth Server redirects back with `code` → Your backend exchanges `code` for `access_token`.
*   **Security**: Backend never exposes the `access_token` to the browser.

### 2. Authorization Code + PKCE (Mobile/SPA)
*   **Use Case**: Native Apps, Single-Page Apps (SPAs).
*   **Why PKCE?**: Public clients (JS apps) cannot keep a `client_secret`. PKCE replaces the secret with a `code_verifier` (random string) and `code_challenge` (hash of verifier).
*   **Flow**: Same as Auth Code, but the mobile app generates a `code_verifier` at the start and proves possession by sending it when exchanging the `code`.

### 3. Client Credentials (Machine-to-Machine)
*   **Use Case**: Backend service calling another backend service.
*   **Flow**: No user involved. Service sends `client_id` + `client_secret` → Gets `access_token`.

### 4. Implicit (DEPRECATED)
*   **Use Case**: Legacy SPAs.
*   **Problem**: `access_token` is exposed in the browser URL fragment. Vulnerable to XSS.
*   **Status**: **DO NOT USE**. Use Authorization Code + PKCE instead.

---

## 🆔 OIDC (OpenID Connect)

OIDC adds an **Identity Layer** on top of OAuth 2.0.

| Concept | OAuth 2.0 | OIDC |
| :--- | :--- | :--- |
| **Purpose** | Authorization (What can they do?) | Authentication (Who are they?) |
| **Token** | `access_token` | `access_token` + **`id_token`** |
| **Info** | Scopes (e.g., `read:email`) | Claims (e.g., `sub`, `name`, `email`) |

### The `id_token`
A **JWT** containing user identity claims.
```json
{
  "iss": "https://auth.example.com",   // Issuer
  "sub": "user123",                    // Subject (User ID)
  "aud": "my-app",                     // Audience (Your app)
  "exp": 1678886400,                   // Expiration
  "name": "Jane Doe",
  "email": "jane@example.com"
}
```

---

## 🎫 JWT Best Practices

> [!WARNING]
> **JWTs are NOT encrypted by default**. The payload is Base64-encoded (anyone can read it).
> Do NOT put sensitive data (passwords, SSN) in a JWT.

### Validation Checklist
1.  **Verify Signature**: Use the Auth Server's public key.
2.  **Check `exp`**: Reject expired tokens.
3.  **Check `aud`**: Ensure the token was issued for YOUR application.
4.  **Check `iss`**: Ensure it came from YOUR trusted Auth Server.

---

## 🏛️ Principal Pattern: Token Storage

| Location | Security | Use Case |
| :--- | :--- | :--- |
| **HttpOnly Secure Cookie** | ✅ Best for Browser | Server-rendered apps. XSS cannot access the cookie. |
| **`localStorage`** | ❌ Vulnerable to XSS | Avoid. Any JS on the page can read it. |
| **In-Memory (JS variable)** | ✅ Good for SPA | Cleared on page refresh. Use with silent refresh. |
| **Keychain/Keystore** | ✅ Best for Mobile | iOS Keychain, Android Keystore. |

---

## 🌐 AWS Free Tier Implementation

Yes, you can implement OAuth 2.0 / OIDC on AWS Free Tier:
*   **Amazon Cognito User Pools**: 50,000 MAUs free. Acts as your OIDC Identity Provider.
*   **API Gateway**: Validates JWTs using a Cognito Authorizer.
*   **Lambda**: Your backend logic.

---

## ✅ Principal Architect Checklist

1.  **Use PKCE for all public clients** (SPAs, Mobile).
2.  **Never store tokens in `localStorage`**.
3.  **Validate ALL claims** on the backend (don't trust the client).
4.  **Use short-lived Access Tokens** (15 min) + **long-lived Refresh Tokens** (7 days).
5.  **Rotate Refresh Tokens** on every use (one-time-use pattern).

---

## 🔗 Related Documents
*   [API Gateway Guide](../../infrastructure-techniques/api-gateway-comprehensive.md) — JWT Validation at the Edge.
*   [Service Mesh Guide](../../infrastructure-techniques/service-mesh-comprehensive.md) — mTLS for Service-to-Service Auth.
