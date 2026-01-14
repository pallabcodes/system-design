# CDN Architecture: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Anycast Routing, Cache Invalidation Patterns, and Edge Compute.

> [!IMPORTANT]
> **The Principal Law**: **The Speed of Light is Constant**. You cannot beat 300ms latency from Sydney to New York. You **move the data** to Sydney.
> **The Cache Rule**: "There are only two hard things in Computer Science: Cache Invalidation and Naming Things." — Phil Karlton.

---

## 🌍 How CDNs Actually Work (God Mode)

It's not just "caching static files". It's about Routing and TCP Engineering.

### 1. Anycast Routing (BGP)
*   **Unicast**: 1 IP = 1 Server.
*   **Anycast**: 1 IP (`1.1.1.1`) = 500 Servers globally.
*   **Mechanic**: BGP (Border Gateway Protocol) routes the user to the *topologically closest* data center.
*   **Performance**: If a BGP route flaps, users might get rerouted from London to Paris. This is why "Global Accelerators" exist (AWS Global Accelerator avoids BGP for the middle mile).

### 2. The TCP Window
*   **Problem**: TCP Slow Start takes multiple round-trips to reach full speed.
*   **Solution**: Since the CDN Edge is only 5ms away from the User, the TCP Handshake completes instantly. The CDN maintains a separate, long-lived, high-speed connection to your Origin.
*   **Result**: The user sees the page load instantly essentially because the "Slow Start" happened over 5ms, not 200ms.

---

## 🗑️ Cache Invalidation Strategies

### 1. Purge (Banning)
*   **Action**: "Remove `/images/logo.png` from all 500 edge locations."
*   **Latency**: Takes 150ms to 5 minutes depending on the vendor (Fastly is instant, CloudFront takes minutes).
*   **Cost**: Expensive. Don't build logic relying on constant purging.

### 2. Versioning (Immutable Chunks) - **Preferred**
*   **Action**: Rename file to `/images/logo.v123.png`.
*   **Benefit**: Zero latency. Users on the old HTML see the old logo. Users on the new HTML see the new logo. No race conditions.

### 3. Stale-While-Revalidate
*   **Header**: `Cache-Control: max-age=60, stale-while-revalidate=300`
*   **Behavior**:
    1.  0-60s: Serve fresh cache.
    2.  60-360s: Serve **Stale** content immediately (fast), but trigger a background fetch to Origin to update cache.
    3.  360s+: Block and fetch fresh.

---

## ⚡ Edge Compute (Lambda@Edge / Cloudflare Workers)

Moving logic to the CDN.

*   **UseCase 1: A/B Testing**: Check cookie at Edge, rewrite URL to `/v1/` or `/v2/`. Origin doesn't know.
*   **UseCase 2: Auth**: Validate JWT at Edge. Reject invalid tokens before they hit your expensive API servers.
*   **UseCase 3: Custom Headers**: Add security headers (`HSTS`, `CSP`) at the edge.

---

## ✅ Principal Architect Checklist

1.  **Vary Header is Dangerous**: `Vary: User-Agent` splits the cache by every single browser version. Your Hit Ratio drops to 0%. Use `Vary: Accept-Encoding` mostly.
2.  **Tiered Caching**: Enable "Origin Shield". Edge -> Regional Cache -> Origin. Protects your origin from the "Thundering Herd" of 500 edge locations missing simultaneously.
3.  **Negative Caching**: Don't cache 500 errors. Do cache 404s (for short time) to prevent DDoS attacks on missing files.

---

## 🔗 Related Documents
*   [Proxy Architecture](../../load-balancers-techniques/proxy-architecture-guide.md) — The caching engines often use Nginx/Varnish.
*   [Network Protocols](../../networking/protocol/network-protocols-guide.md) — QUIC and TCP details.
