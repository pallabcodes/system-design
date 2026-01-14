# REST API Design: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Resource Modeling, HATEOAS, Versioning, and Idempotency.

> [!IMPORTANT]
> **The Principal Truth**: REST is **not** "just HTTP". It's a set of architectural constraints. Most "REST APIs" are actually **HTTP APIs**. True REST requires HATEOAS (Hypermedia as the Engine of Application State).

---

## 🏛️ The Richardson Maturity Model

| Level | Description | Example |
| :--- | :--- | :--- |
| **Level 0** | HTTP as a transport (RPC-style). | `POST /api` with `{ action: "getUser", id: 1 }` |
| **Level 1** | Resources. | `GET /users/1`, `GET /orders/5` |
| **Level 2** | HTTP Verbs. | `GET`, `POST`, `PUT`, `DELETE` used correctly. |
| **Level 3** | HATEOAS. | Response includes links to related actions. |

**Most APIs Stop at Level 2.** Level 3 (HATEOAS) adds discoverability but increases payload size.

---

## 🧰 Resource Naming Conventions

| Rule | Good | Bad |
| :--- | :--- | :--- |
| Use **nouns**, not verbs. | `/users`, `/orders` | `/getUsers`, `/createOrder` |
| Use **plurals**. | `/users/1` | `/user/1` |
| Use **hyphens**, not underscores. | `/user-profiles` | `/user_profiles` |
| **Nest** related resources (max 2 levels). | `/users/1/orders` | `/users/1/orders/5/items/2` (too deep) |

---

## ⚙️ HTTP Verbs & Status Codes

### Verbs
| Verb | Meaning | Idempotent? | Safe? |
| :--- | :--- | :--- | :--- |
| `GET` | Read | Yes | Yes |
| `POST` | Create | No | No |
| `PUT` | Replace (full update) | Yes | No |
| `PATCH` | Partial update | No* | No |
| `DELETE` | Delete | Yes | No |

*`PATCH` can be idempotent if designed carefully.

### Status Codes
| Code | Meaning | Use Case |
| :--- | :--- | :--- |
| `200 OK` | Success | GET, PUT, PATCH |
| `201 Created` | Resource created | POST |
| `204 No Content` | Success, no body | DELETE |
| `400 Bad Request` | Malformed request | Validation errors |
| `401 Unauthorized` | Not authenticated | Missing/invalid token |
| `403 Forbidden` | Not authorized | Valid token, missing permissions |
| `404 Not Found` | Resource doesn't exist | GET /users/999 |
| `409 Conflict` | Resource conflict | Email already exists |
| `429 Too Many Requests` | Rate limited | Retry-After header |

---

## 🔗 HATEOAS (Level 3 REST)

Responses include links to possible next actions.

```json
{
  "id": 123,
  "status": "pending",
  "_links": {
    "self": { "href": "/orders/123" },
    "cancel": { "href": "/orders/123/cancel", "method": "POST" },
    "pay": { "href": "/orders/123/pay", "method": "POST" }
  }
}
```
**Benefit**: Clients don't hardcode URLs. The server controls the application flow.

**Drawback**: Larger payloads. Rarely used in practice.

---

## 📅 API Versioning

| Strategy | Example | Pros | Cons |
| :--- | :--- | :--- | :--- |
| **URL Path** | `/v1/users` | Explicit, cacheable. | URL pollution. |
| **Query Param** | `/users?version=1` | Easy to ignore. | Not semantic. |
| **Header** | `Accept: application/vnd.api.v1+json` | Clean URL. | Harder to test (requires headers). |

**Recommendation**: Use **URL Path versioning** for public APIs (e.g., `/v1/users`).

---

## 🛡️ Idempotency Keys

For non-idempotent operations (POST), prevent duplicate submissions.

**Client sends**:
```http
POST /orders
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json

{ "item_id": 1, "quantity": 2 }
```

**Server behavior**:
1.  Check if `Idempotency-Key` exists in cache (Redis).
2.  If yes, return the cached response.
3.  If no, process the request, store the response, and return it.

---

## ✅ Principal Architect Checklist

1.  **Model Resources, Not Actions**: Think "nouns" (`/users`), not "verbs" (`/createUser`).
2.  **Use HTTP Status Codes Correctly**: Don't return `200 OK` with `{ "error": "..." }`.
3.  **Implement Idempotency for POSTs**: Critical for payment and order creation endpoints.
4.  **Version from Day 1**: Even if you only have `v1`, plan for `v2`.
5.  **Document with OpenAPI**: Generate SDKs and test clients automatically.

---

## 🔗 Related Documents
*   [gRPC API Design](../gRPC/README.md) — For internal service-to-service communication.
*   [GraphQL API Design](../graphql/README.md) — For flexible client-driven queries.
