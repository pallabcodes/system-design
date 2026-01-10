# Interactive Streaming & Broadcast WebRTC

> **Level**: Principal Architect
> **Scope**: WHIP/WHEP Standards, OBS Integration, and Sub-second Broadcast.

> [!IMPORTANT]
> **The Paradigm Shift**: Replacing RTMP (3-30s latency) with WebRTC (<500ms) for *broadcast* use cases.
> **The Philosophy**: WebRTC is a **"Road"**—the developer decides if they drive a fast motorcycle (Low-Latency) or a heavy freight truck (4K High-Fidelity).

---

## 🛣️ 0. The "Media Road" Philosophy

A common misconception is that WebRTC is only for low-quality, low-latency calls. In reality, it is a high-performance transport layer.

*   **Autonomy of Quality**: Developers can prioritize **Fidelity over Latency**. By increasing the **RTP Playout Jitter Buffer** (e.g., to 3 seconds), you can achieve rock-solid 4K 60fps streams even on jittery public networks.
*   **Beyond the Browser**: WebRTC has no "browser requirement." High-end hardware encoders (Teradek, Blackmagic) and native C++ implementations (WebRTC.lib) allow it to function as a professional broadcast backbone.
*   **Table Stakes Evolution**: In 2003, 480p H.264 over the web was "impossible." Today, 4K sub-second broadcast is "table stakes." Strategy should assume "perfect quality" is always the future standard.
*   **The Laws of Physics**: High-latency protocols (HLS/DASH) are built on a "slow" foundation (TCP/HTTP/Chunking). Trying to make them fast is an **intractable problem**—no amount of optimization can bypass the inherent latency of chunking and TCP handshakes at the edge. It is easier to teach a "fast" protocol (WebRTC) to be high-quality (pace its delivery) than to teach a "slow" protocol to be real-time.

---

## 📡 1. The Death of RTMP: WHIP & WHEP

For 10 years, we used "WebRTC for calls" and "RTMP for streaming".
Now, we use WebRTC for everything.

### Ingest: WHIP (RFC draft)
**WebRTC-HTTP Ingestion Protocol**
*   **Goal**: Let OBS/Hardware Encoders talk to *any* WebRTC Media Server standardly.
*   **Mechanism**: A simple HTTP POST request containing the SDP Offer. Server returns 201 Created with SDP Answer.
*   **Authentication**: Bearer Token standard.

```http
POST /whip/endpoint HTTP/1.1
Host: media-server.com
Authorization: Bearer my-stream-key
Content-Type: application/sdp

v=0
o=- 0 0 IN IP4 127.0.0.1...
(SDP Offer)
```

### Egress: WHEP (RFC draft)
**WebRTC-HTTP Egress Protocol**
*   **Goal**: Standard way for players (HLS.js equivalent for WebRTC) to consume streams.
*   **Mechanism**: HTTP POST to request stream, Server returns SDP Answer (Viewer Connection).

---

## 🎥 2. OBS Studio & Native WebRTC

Previously, OBS streamed RTMP. To use WebRTC, you needed a "virtual camera" or custom fork.
Now, **OBS supports WHIP natively**.

### The Flow
```mermaid
graph LR
    OBS[OBS Studio] -->|WHIP (Opus/H.264)| Edge[Edge Media Server]
    Edge -->|Relay| Origin[Origin Core]
    Origin -->|WHEP| Viewer[Browser Viewer]
    
    subgraph "Latency Budget"
        Note[Total: < 500ms]
    end
```

### Why Native WebRTC > RTMP?
1.  **Multiple Audio Tracks**: RTMP is limited. WebRTC supports surround sound / multiple languages easily.
2.  **B-Frames**: Traditional WebRTC disallowed B-Frames (latency). Modern implementations enable them for quality, trading ~20ms latency for 30% bitrate reduction.
3.  **SVC (Scalable Video Coding)**: OBS can send *one* stream with 3 layers. The SFU forwards appropriate layers to viewers (ABR) *without transcoding*.

---

## 🌍 3. Broadcast-Scale WebRTC (The Millicast Model)

Scaling WebRTC to 1 Million active viewers is harder than HLS.

### The Problem: Connection State
*   **HLS**: Stateless. CDN just serves files.
*   **WebRTC**: Stateful. Every viewer needs a dedicated UDP port and DTLS handshake.

### The Architecture: Geo-Sharded Fanout
1.  **Ingest**: Source connects to *closest* Ingest Node (e.g., London).
2.  **Fiber Backbone**: Stream is replicated to all Regions via private fiber (avoid public internet jitter).
3.  **Last Mile**: 
    *   Viewer in Tokyo connects to `edge-tokyo-01`.
    *   Viewer in NYC connects to `edge-nyc-05`.

### Hardware Encoders vs Browser
*   **Prediction**: Hardware encoders (Teradek) will disappear.
*   **Reality**: Browsers (WebCodecs) + Cloud Power are becoming the encoder.
*   **Use Case**: NASA JPL moved from Satellite to WebRTC for Mars Rover feeds (Real-time monitoring).

---

## ⚙️ 4. AV1 & The Future of Quality

**AV1** is the holy grail for interactive streaming.
*   **Royalty Free**: No MPEG licensing costs.
*   **Efficiency**: 30-50% better than H.264.
*   **Screen Content Coding**: Optimized for text/desktop sharing (perfect for "Remote Desktop" apps).

**Status**:
*   **Ingest**: OBS supports AV1 via WHIP.
*   **Playback**: Chrome/Edge/Firefox support AV1 hardware decoding.
*   **Constraint**: CPU usage for *encoding* is high. Needs NVENC (Nvidia) or Apple Silicon hardware acceleration.

---

## 🏛️ 5. Strategy: Unified Infrastructure

A significant architectural advantage of using WebRTC for *all* tiers (Calls + Interactive + Broadcast) is the **Unified Stack**.

*   **The Trap**: Maintaining two separate systems (WebRTC for calls, HLS/DASH for broadcast) doubles your operational surface area, bug count, and infrastructure cost.
*   **The Principal Solution**: "Grow up" the WebRTC protocol to handle all use cases. While scaling stateful connections is a "solvable training challenge," managing two disjoint architectures is a long-term strategic anchor.

---

---

## 🏎️ 6. The "Sprinter vs. Tractor" Analogy

When choosing a protocol, remember:
*   **WebRTC is a World-Class Sprinter**: Naturally built for speed. Teaching it to run a marathon (high-quality, 3-second buffer broadcast) is possible with "training" (jitter buffer tuning).
*   **Legacy Protocols (HLS) are Heavy-Duty Tractors**: Built for payload, not speed. No matter how much you "train" the tractor, it will never win a 100-meter dash.

---

## 🧪 7. Advanced Q&A: The Principal's Desk

### Q: What technical adjustments allow WebRTC to simulate higher latency?
**A**: To "grow up" the protocol for broadcasting, you move from **Zero-Latency Mode** to **Buffered Mode**.
1.  **RTCPeerConnection Playout Delay**: Setting `playoutDelayHint` (Chrome-specific) or increasing the **Jitter Buffer** manually in the media engine. This allows the receiver to wait for delayed packets, facilitating a "smooth" 4K experience at the cost of ~500ms-2s latency.
2.  **FEC/NACK Tuning**: Instead of immediate retransmission (NACK), you increase the **Forward Error Correction (FEC)** ratio, assuming you have a 1-second "buffer" to reconstruct the signal without a round-trip.

### Q: Why is reducing latency in legacy protocols considered physically impossible?
**A**: **Chunking & Serialization Hostage**. HLS requires a full "chunk" (e.g., 2 seconds) to be written to disk/memory and indexed before it can be served. Even "Low-Latency HLS" relies on TCP's retransmission logic, which introduces **Head-of-Line Blocking**. If a single packet is lost, the whole stream stalls. WebRTC (UDP) allows packets to arrive out of order, which is the only way to maintain a real-time "heartbeat."

### Q: Which specific broadcasting use cases are hardest for WebRTC today?
**A**: 
1.  **Massive Scale without Geo-Fanout**: WebRTC is stateful. Scaling to 10M users without a sophisticated, geo-sharded SFU backbone is exponentially more expensive than serving static HLS files via a generic CDN.
2.  **Ultra-High Resolution (8K) Encoding**: Browsers are not optimized for 8K WebRTC encoding. While playback is fine, ingest requires dedicated hardware encoders (WHIP/WHEP) that support high-profile codecs like AV1 on bare-metal.

---

## ✅ Principal Architect Checklist

1.  **Adopt WHIP**: Stop building custom WebSocket signaling for ingest. Use WHIP so you support OBS/FFmpeg out of the box.
2.  **Kill RTMP**: If you control the player, move to WebRTC-only pipeline. RTMP introduces 2-3s latency at the source.
3.  **Enable SVC**: Use VP9 or AV1 SVC to give mobile users a smooth stream without expensive server-side transcoding.
4.  **Audit Buffer**: Hardware encoders often buffer 3-5s by default. Tune OBS "Zero Latency" mode.
5.  **Simulate "Stream Parties"**: Test the "Clubhouse for Video" scenario—where a viewer suddenly becomes a broadcaster (promoted participant).

---

## 🔗 Related Documents
*   [WebRTC Scaling](./webrtc-scaling-architecture-guide.md) — Underlying fan-out architecture.
*   [WebRTC 1.0 Standard](./webrtc-1.0-standard-guide.md) — Unified Plan details.
*   [Live Streaming Architecture](./live-streaming-architecture-guide.md) — When to fall back to HLS.
