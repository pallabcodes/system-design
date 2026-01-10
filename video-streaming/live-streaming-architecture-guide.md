# Live Streaming Architecture: Principal Architect's Guide

> **Level**: Principal Engineer / SDE-3
> **Scope**: LL-HLS, CMAF, QUIC, Edge Compute, and Scale-out Strategies.

> [!IMPORTANT]
> **The Core Tension**: Global Scale vs. Sub-Second Latency.
> **The Solution**: Hybrid Architecture (WebRTC for <500ms, LL-HLS for <3s, HLS for >10s).

---

## 🏗️ The Latency Pyramid (Protocol Selection)

| Latency Budget | Protocol | Transport | Use Case | Scale Limit |
| :--- | :--- | :--- | :--- | :--- |
| **< 500ms** | **WebRTC** | UDP/SRTP | Betting, Bidding, VoIP | High Cost ($$$) |
| **2 - 5s** | **LL-HLS / DASH** | HTTP/2 or 3 | Sports, "Social Parity" | Infinite ($) |
| **10 - 30s** | **Standard HLS** | HTTP/1.1+ | Linear TV, Events | Infinite ($) |

> **"Social Parity"**: The requirement that a stream is not slower than strict broadcast TV (approx. 6-8s delay) or Twitter/X text updates.

---

## ⚡ Low-Latency HLS (LL-HLS) Internals

Apple's extension to HLS (2019) enables <3s latency at CDN scale.

### 1. The Mechanics of Speed
*   **Partial Segments**: Instead of waiting for a full 6s segment to generate, the encoder publishes 200ms "parts" (`.m4s`).
*   **HTTP/2 Push** (Deprecated) → **H2/H3 Preload Hints**: The server hints to the client "The next part is coming here, request it now."
*   **Blocking Playlist Reloads**: The client asks for the *next* update. The Edge Server holds the request open (Long Polling) until the playlist changes.

### 2. The Delta Playlist
To reduce overhead, the server sends only the *changes* (Deltas) to the playlist, not the full 1MB manifest every 200ms.

```http
GET /playlist.m3u8?_HLS_msn=100&_HLS_part=2
```
*   `_HLS_msn`: Media Sequence Number (wait until segment 100 exists).
*   `_HLS_part`: Part Number (wait until part 2 exists).

---

## 📦 CMAF & Chunked Transfer Encoding

**Common Media Application Format (CMAF)** allows *single-encoding* for both HLS (Apple) and DASH (Android/Web), but its real power is **Chunked Transfer**.

### The "ULL" (Ultra Low Latency) Pipeline

```mermaid
graph LR
    Encoder -->|Chunk 1 (200ms)| Packager
    Packager -->|Chunk 1| CDN
    CDN -->|Chunk 1| Player
    
    Encoder -->|Chunk 2 (200ms)| Packager
    Packager -->|Chunk 2| CDN
    CDN -->|Chunk 2| Player
```

*   **Standard**: Encoder generates 4s segment → Uploads to CDN → CDN available. (Latency ~6s)
*   **Chunked**: Encoder generates 200ms chunk → Writes to HTTP Response stream immediately.
    *   The Player begins decoding frame 1 of the segment *while frame 30 is still being generated* by the encoder.
    *   **Header**: `Transfer-Encoding: chunked`

---

## 🚀 HTTP/3 (QUIC): Killing Head-of-Line Blocking

**Problem**: In TCP (HTTP/1.1 & H2), one lost packet stalls *all* streams until retransmitted (Head-of-Line Blocking).
**Solution**: QUIC (UDP) treats streams independently.

### Impact on Video
*   **Rebuffering**: Drops by 20-30% on weak networks (mobile).
*   **Startup Time**: 0-RTT handshakes mean faster video start.
*   **Live Edge**: Allows players to stay closer to the "live edge" without stalling.

> [!TIP]
> **Implementation**: Enable `h3` on your CDN (Cloudflare/Fastly/CloudFront). Ensure your players (ExoPlayer, AVPlayer, hls.js) prioritize http/3.

---

## 🧠 Edge Compute Optimization

Moving logic to the edge (Cloudflare Workers, AWS Lambda@Edge) solves complex scale problems.

### 1. Personalized Manifests (SSAI)
Server-Side Ad Insertion (SSAI) manipulates the manifest per-user.
*   **Edge Logic**: Inject `ad_segment_01.ts` into the m3u8 for User A, but `ad_segment_02.ts` for User B.
*   **Benefit**: Bypasses ad-blockers, seamless transition (no client-side flickering).

### 2. Request Collapsing (The "Thundering Herd" Shield)
1M users request `segment_100.ts` at the exact same second.
*   **Without Edge**: 1M requests hit the Origin. Origin dies.
*   **With Edge**: Edge holds 999,999 requests, fetches once from Origin, serves all from cache.

---

## 🎬 Real-World Architecture: "The Dual-Path Strategy"

For Sports/Betting apps, we implement a Hybrid approach.

```mermaid
graph TD
    Source[Live Feed] --> Encoder[Encoder]
    
    Encoder -->|Path A: WebRTC| SFU[SFU Network]
    Encoder -->|Path B: LL-HLS| Packager
    
    SFU -->|Sub-second (Premium)| UserVIP[VIP / Better]
    Packager -->|CDN (Scale)| UserFree[Free Viewer / 3s Delay]
    
    subgraph "Failover Logic"
        UserVIP -.->|Network Poor| UserFree
    end
```

### The "Dead Zone" Problem
Switching from WebRTC (Live) to HLS (DVR/Rewind) creates a timeline gap.
*   **WebRTC**: T=0
*   **HLS**: T=-4s
*   **The Jump**: When a user clicks "Rewind", they jump back 4 seconds. The UI must handle this gracefully (e.g., "Catch up to Live" button jumps back to WebRTC).

---

## ✅ Principal Architect Checklist

1.  **Enable IPv6 & QUIC**: Free performance wins on all major CDNs.
2.  **Tune TCP Windows**: For Origin servers, increase `initcwnd` (Initial Congestion Window) to allow larger bursts (essential for 4K segments).
3.  **GOP Alignment**: Ensure Keyframes align perfectly across all bitrates. If they don't, ABR switching will fail (player stalls).
4.  **CMAF**: Standardize on CMAF to halve storage costs (one container for HLS & DASH).
5.  **Origin Shield**: Never expose your Encoder/Origin directly to the internet. Always put a Shield Tier (Nginx/Varnish) in between.

---

## 🔗 Related Documents
*   [WebRTC Scaling Architecture](./webrtc-scaling-architecture-guide.md) — For the sub-second path.
*   [Video Security Architecture](./video-streaming-security-architecture.md) — DRM and Watermarking.
