# WebRTC 1.0 Standard & Next Version (NV) Roadmap

> **Source**: [WebRTC 1.0 & Future Roadmap with Bernard Aboba](https://youtu.be/hAUxDq3qIPY)

> [!IMPORTANT]
> **The Milestone**: WebRTC 1.0 reached **W3C Recommendation** (final standard) in 2021.
> **The Future**: WebRTC NV = Collection of specs for IoT, VR gaming, ML, and secure conferencing.

---

## 📜 WebRTC 1.0: Official Recommendation (2021)

### The W3C Process
```mermaid
graph LR
    WD[Working Draft] --> CR[Candidate Recommendation]
    CR --> PR[Proposed Recommendation]
    PR --> REC[Recommendation: FINAL]
```

**Candidate Recommendation (CR)**:
*   Spec is "safe to implement".
*   May have "features at risk" (could be removed).

**Proposed Recommendation (PR)**:
*   Requires **interoperability** (multiple implementations).
*   Requires **implementation experience** (real-world usage).

**Recommendation (REC)**:
*   **Final standard** (no more changes).
*   All IETF RFCs published (referenced as final, not drafts).

---

## 🔄 Unified Plan: The Only Plan (2021+)

### The Old World (Pre-2021)
**Plan B** (Chrome proprietary):
*   Multiple tracks per `m=` line.
*   Simpler for Chrome developers.
*   ❌ Not in standard.

**Unified Plan** (Standard):
*   One track per `m=` line.
*   More verbose SDP.
*   ✅ Official standard.

### The Transition
**2021**: Chrome deprecated Plan B.
**2026**: Plan B completely removed.

**Action**: All apps must use **Unified Plan** (or migration will break).

---

## 🚀 WebRTC NV (Next Version): The Collection

### What Is WebRTC NV?
**Not** a single spec. **Collection** of specs for new use cases.

### The 3 Categories

#### 1. Peer Connection Extensions
| Feature | Use Case | Status (2026) |
| :--- | :--- | :--- |
| **SVC (Scalable Video Coding)** | Adaptive bitrate (1 stream, 3 layers) | ✅ Chrome, Firefox |
| **Insertable Streams** | E2EE with SFU | ✅ Chrome, Firefox |
| **AV1 Codec** | Better compression (30% less bandwidth) | ✅ Chrome (encoding + decoding) |

#### 2. Capture Extensions
| Feature | Use Case | Status (2026) |
| :--- | :--- | :--- |
| **Media Stream Track Insertable Streams** | ML (background blur, virtual backgrounds) | ✅ Chrome, Firefox |
| **Browser Picker Model** | Privacy (no device fingerprinting) | 🟡 Opt-in (multi-year transition) |

#### 3. Standalone Specs (No Peer Connection)
| Feature | Use Case | Status (2026) |
| :--- | :--- | :--- |
| **Web Transport** | Client-server low-latency (cloud gaming) | ✅ Chrome 97+ |
| **Web Codecs** | Custom encoding/decoding (video editor) | ✅ Chrome 94+ |
| **Standalone ICE** | NAT traversal without full WebRTC | 🟡 Draft |

---

## 🔒 Privacy: Browser Picker Model

### The Old Model (Application Picker)
**How it works**:
1.  App calls `enumerateDevices()`.
2.  App gets **list of all cameras/mics**.
3.  App shows menu to user.

**Problem**: Device fingerprinting (track users across sites).

### The New Model (Browser Picker)
**How it works**:
1.  App calls `getUserMedia()`.
2.  **Browser** shows menu (like screen sharing).
3.  App only sees the **selected device**.

**Impact**:
*   ✅ No fingerprinting.
*   ❌ Breaks telehealth apps (can't pre-select "exam camera").

**Timeline**: Multi-year opt-in → Mandatory (2027-2030).

---

## 🌐 Web Transport: The WebSocket Killer

### WebSocket Limitations
*   **Head-of-line blocking**: One lost packet blocks entire stream.
*   **TCP-only**: No unreliable mode (can't drop old video frames).

### Web Transport Features
**Supports**:
*   **Datagrams** (UDP-like, unreliable).
*   **Reliable streams** (TCP-like, ordered).
*   **Unreliable streams** (best-effort, unordered).

### Use Case: Cloud Gaming
```javascript
const transport = new WebTransport('https://game-server.com');
await transport.ready;

// Send player input (unreliable, low latency)
const datagram = transport.datagrams.writable.getWriter();
datagram.write(new Uint8Array([/* input data */]));

// Receive video frames (unreliable, drop old frames)
const videoStream = await transport.createUnidirectionalStream();
// Use Web Codecs to decode
```

**Benefit**: No head-of-line blocking → 50-100ms latency reduction.

---

## 🎨 Web Codecs: Custom Video Processing

### What It Is
Low-level API for **encoding/decoding** video/audio.

### Use Case: Video Editor (Browser-Based)
```javascript
const encoder = new VideoEncoder({
  output: (chunk) => {
    // Send encoded chunk to server or save to file
  },
  error: (e) => console.error(e)
});

encoder.configure({
  codec: 'vp09.00.10.08', // VP9
  width: 1920,
  height: 1080,
  bitrate: 2_000_000,
  framerate: 30
});

// Encode raw video frame
const frame = new VideoFrame(rawPixelData, { timestamp: 0 });
encoder.encode(frame);
```

**Benefit**: Custom quality control (vs WebRTC's automatic adaptation).

---

## 📊 SVC (Scalable Video Coding): The Future of Adaptive Bitrate

### The Old Way (Simulcast)
**Send 3 separate streams**:
*   1080p (high).
*   480p (medium).
*   240p (low).

**Problem**: 3x upload bandwidth.

### The New Way (SVC)
**Send 1 stream with 3 layers**:
*   Base layer: 240p.
*   Enhancement 1: +480p.
*   Enhancement 2: +1080p.

**Benefit**: 1.5x upload bandwidth (vs 3x for simulcast).

**Browser Support** (2026):
*   **Chrome**: ✅ VP9 SVC.
*   **Firefox**: ✅ VP9 SVC.
*   **Safari**: ❌ Not implemented.

---

## 🎮 Zero-Copy Capture: 7x7 Grids & Beyond

### The Problem
**49-person grid** (7x7) = 48 incoming video streams.

**Traditional**:
```
Camera → CPU Buffer → GPU Buffer → Video Tag
```

**Copies**: 2 (CPU → GPU, GPU → Video Tag).

**Result**: 100% GPU usage, janky rendering.

### The Solution: Zero-Copy
**Direct path**:
```
Camera → GPU Buffer → Video Tag
```

**Benefit**: 50% GPU usage reduction.

**Status** (2026): Chrome experimental flag (`--enable-zero-copy-capture`).

---

## ✅ Principal Architect Checklist

1.  **Migrate to Unified Plan** (if using Plan B): Deprecated in 2021, removed in 2026.
2.  **Explore SVC** (vs Simulcast): 50% upload bandwidth savings for multi-quality streams.
3.  **Use Web Transport** (for client-server): Better than WebSockets for gaming, live sports.
4.  **Prepare for Browser Picker Model**: Opt-in today (mandatory 2027-2030). May break device pre-selection.
5.  **Test AV1 Codec**: 30% bandwidth savings vs VP9 (at cost of higher CPU).

---

## 🔗 Related Documents
*   [WebRTC Evolution](./webrtc-evolution-guide.md) — Four eras of WebRTC.
*   [E2EE Implementation](./webrtc-e2ee-implementation-guide.md) — Insertable Streams.
*   [WebRTC Production Readiness](./webrtc-production-readiness-guide.md) — Simulcast vs SVC.
