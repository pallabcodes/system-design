# WebTransport & Media over QUIC (MoQ): Architecture Guide

> **Level**: Principal Engineer / SDE-3
> **Scope**: HTTP/3, QUIC Datagrams, MoQ Standard, and Cloud Gaming Architecture.

> [!IMPORTANT]
> **The Shift**: WebRTC is a "black box" (Codecs + Transport + Signaling). WebTransport is just the **Transport**.
> **The Benefit**: You bring your own Codec (BYOC) and logic. Goodbye "Offer/Answer" hell.

---

## ⚡ 1. The Protocol Stack: HTTP/3 & QUIC

WebTransport runs on top of **HTTP/3** (which runs on QUIC/UDP).

```mermaid
graph TB
    App[Application Layer (JS)]
    WT[WebTransport]
    H3[HTTP/3]
    QUIC[QUIC Streams & Datagrams]
    UDP[UDP]
    IP[IP]
    
    App --> WT
    WT --> H3
    H3 --> QUIC
    QUIC --> UDP
    UDP --> IP
```

### Key Primitives
1.  **Datagrams**: Fire-and-forget (like UDP). Unreliable, unordered.
    *   *Use Case*: Live player movement, Voice chat (if using Opus directly).
2.  **Streams (Uni-directional)**: Reliable, ordered (like TCP) but *independent*.
    *   *Use Case*: Serving a Video Segment (`.m4s`). If Stream A drops a packet, Stream B **does not stall** (No Head-of-Line Blocking).
3.  **Streams (Bi-directional)**: Request/Response.
    *   *Use Case*: RPC calls ("Join Room", "Chat Message").

---

## 🎥 2. Media over QUIC (MoQ / MoQT)

**MoQ** is the IETF standard aiming to replace HLS/DASH *and* WebRTC for distribution.

### The Architecture
Instead of "Files" (HLS) or "RTP Packets" (WebRTC), MoQ uses **Objects**.

*   **Group**: A collection of objects (e.g., a GOP / Keyframe interval).
*   **Object**: A video frame (or slice of a frame).

### Why MoQ Wins
1.  **Cache friendly**: Intermediary Relays (CDNs) can cache "Objects". WebRTC packets are uncacheable.
2.  **Low Latency**: Uses QUIC Streams to deliver objects. If Frame 2 is lost but Frame 3 arrives, the player can decide what to do (skip or wait), unlike TCP which *forces* waiting.
3.  **Correction**: QUIC handles retransmission natively and efficiently (SACK).

---

## 💻 3. Implementation: WebTransport API

### Client-Side (Browser)
```javascript
const url = 'https://game-server.example.com:4433';
const transport = new WebTransport(url);

// 1. Connection
await transport.ready;
console.log('Connected to QUIC server');

// 2. Sending Unreliable Input (Datagrams)
const writer = transport.datagrams.writable.getWriter();
const inputData = new Uint8Array([0x01, 0xFF]); // Joypad state
writer.write(inputData);

// 3. Receiving Reliable Video (Uni-directional Stream)
const reader = transport.incomingUnidirectionalStreams.getReader();
while (true) {
  const { value: stream, done } = await reader.read();
  if (done) break;
  
  // Read from specific stream (e.g., Video Frame 100)
  handleStream(stream);
}

async function handleStream(stream) {
    const streamReader = stream.getReader();
    // Feed data to WebCodecs (VideoDecoder)
}
```

### Server-Side (Python/aioquic)
```python
from aioquic.asyncio import serve
from aioquic.quic.configuration import QuicConfiguration

# WebTransport handshake is HTTP/3 based
# (Requires specialized H3 server logic)
```

---

## 🎮 4. Use Case: Cloud Gaming

**WebRTC** is bad for Cloud Gaming because:
1.  **Jitter Buffer**: WebRTC tries to play "smoothly", adding latency. Gaming needs "latest frame or nothing".
2.  **Opaque**: You can't control how WebRTC drops frames.

**WebTransport Architecture**:
*   **Input**: Sent as **Datagrams** (Unreliable). If a packet is lost, don't resend it (it's old news).
*   **Video**: Sent as **Quic Streams**. If a keyframe is lost, the server can prioritize retransmitting *only* the keyframe, not the delta frames that depend on it.

---

## ⚖️ Decision Matrix: WebRTC vs WebTransport

| Requirement | Choose **WebRTC** | Choose **WebTransport** |
| :--- | :--- | :--- |
| **Browser Support** | Universal (100%) | Modern (Chrome/Firefox/Edge) |
| **Codecs** | Built-in (VP8/9, H.264, AV1) | **Bring Your Own (WebCodecs)** |
| **P2P** | Yes (ICE/STUN/TURN) | **No** (Client-Server Only) |
| **Echo Cancellation** | **Yes** (Built-in AEC) | No (Must implement in WASM) |
| **Caching** | Impossible | **Possible** (via MoQ Relays) |
| **Dev Effort** | Medium (SDKs exist) | **Extreme** (Build everything) |
| **Compliance History**| 🟢 10+ Years of battle-testing | 🔴 New / Experimental |

> [!WARNING]
> **AEC (Acoustic Echo Cancellation)**: WebTransport does NOT give you the browser's processed audio (Voice Isolation/AEC). You get raw mic input. For voice chat, you must run AEC in WebAssembly (e.g., Rnnoise), which is CPU heavy. **This is why Zoom/Meet won't switch to WebTransport soon.**

---

## 🏛️ 5. Strategy: Infrastructure Consolidation

For a Principal Architect, the most compelling reason to move to **Media over QUIC (MoQ)** isn't just latency—it's **Operational Simplicity**.

*   **The Problem (Fragmented Stack)**: Currently, a real-time app requires **WebRTC Media Servers** (Janus, MediaSoup) + **HTTP API Servers** (Node, GO) + **WebSocket Servers** (Signaling).
*   **The MoQ Vision (Unified Stack)**: QUIC is designed to handle both media objects and HTTP requests on the same port/stack. This enables a **"Single Server Model"**—one infrastructure that covers real-time media, metadata, and traditional services, drastically reducing the "surface area" for bugs and maintenance.

---

## 🛣️ 6. The Existential Dilemma: The "Road" Metaphor

The transition from WebRTC to MoQ represents a high-stakes architectural decision.

### The Bumpy Highway (WebRTC)
Imagine you've driven 50 miles on an old, bumpy highway. You've dealt with the potholes (compliance issues, browser bugs, "Offer/Answer" hell), but you can finally see the city (your product goal) in the distance. 

### The High-Speed Expressway (MoQ)
Suddenly, a new expressway opens at the starting line. It is smoother, faster, and designed for 1000mph speeds. 
*   **The Dilemma**: Do you keep driving on the bumpy road you've already "conquered," or do you drive all the way back to the start and take the expressway?
*   **The Principal Strategic Decision**: If your goal is a 5-year outlook, **start the expressway journey now**. The "Sunk Cost" of WebRTC compliance is significant, but the superior quality of the "QUIC Road" means you will reach your final destination (Global Scale, Unified Infra) faster in the long run.

---

## ✅ Principal Architect Checklist

1.  **Evaluate Sunk Cost**: If your team has spent 3 years mastering WebRTC NAT traversal, acknowledge that starting over with WebTransport is a **"reset"** on compliance and reliability testing.
2.  **Audit Team Expertise**: WebTransport requires specialized C++/Rust/Go knowledge to build the "ByoCodec" logic. Ensure your SDE-3s are ready for low-level media handling.
3.  **Monitor the MoQT Standard**: MoQ Transport (MoQT) is moving fast. Don't build a production stack on a draft that might change next month unless you are prepared to contribute to the RFC.
4.  **Hybrid Approach**: Consider **WebRTC for Ingest** (for OBS/Hardware compatibility) and **MoQ for Distribution** (for CDN-friendly fanout).

---

## 🔗 Related Documents
*   [WebRTC Scaling](./webrtc-scaling-architecture-guide.md) — The alternative P2P path.
*   [Live Streaming Architecture](./live-streaming-architecture-guide.md) — HLS/DASH context.
*   [WebRTC 1.0 Standard](./webrtc-1.0-standard-guide.md) — WebCodecs integration.
