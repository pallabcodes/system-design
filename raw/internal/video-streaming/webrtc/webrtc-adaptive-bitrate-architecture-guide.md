# WebRTC Adaptive Bitrate: Simulcast, SVC & GCC

> **Scope**: Bandwidth Estimation (BWE), Multi-Layer Encoding, and Congestion Control.

> [!IMPORTANT]
> **The Problem**: A participant with a 10Gbps connection and a participant with a 3G connection are in the same room.
> **The Strategy**: Do not downgrade the high-speed user. Instead, use **Multi-Stream Architecture** at the SFU level.

---

## 📶 1. Bandwidth Estimation (BWE) & GCC

Before we can scale the video, the client must know *how much pipe* it has.

### Google Congestion Control (GCC)
WebRTC uses a "Delay-Based" controller to detect congestion *before* packet loss occurs.
1.  **Relative One-Way Delay**: The client measures the arrival time of packets. If the delay between Packets A and B is increasing, it indicates a **queue build-up** in a router.
2.  **Decision Logic**: 
    *   **Increase**: If delay is stable and loss = 0.
    *   **Hold**: If delay is increasing but loss = 0.
    *   **Decrease**: If delay > threshold or loss > 2%.

---

## 🪜 2. Simulcast: The "Brute Force" Multilayer

In **Simulcast**, the sender uploads **multiple independent versions** of the same video.

### The Architecture
*   **Stream High**: 1080p, 2.5 Mbps (SSRC 1)
*   **Stream Mid**: 480p, 700 kbps (SSRC 2)
*   **Stream Low**: 180p, 150 kbps (SSRC 3)

**The SFU's Role (The "Menu" Model)**:
The SFU acts as a **Waitstaff**. The sender prepares three "dish sizes" (Low/Mid/High). The SFU looks at each guest (viewer) and serves the size they can "finish" (decode) based on:
1.  **Downstream Bandwidth**: Estimated pipe capacity.
2.  **CPU Capacity**: Can the device handle the 2.5 Mbps decode load without overheating?
3.  **UI Layout/Resolution**: If a user is a **Thumbnail**, don't send 1080p.
4.  **Application Priority**: (e.g., A teacher in a classroom gets the High layer; students get Low/Mid unless they raise a hand).

---

## 🧱 3. SVC (Scalable Video Coding): The "Stackable" Multilayer

SVC is more efficient than Simulcast. Instead of independent streams, it sends **Base Layers** and **Enhancement Layers**.

### The Layering Paradox
*   **Base Layer (L0)**: Minimal resolution/frame rate. Required for everyone.
*   **Enhancement Layer (L1)**: Adds "details" (Spatial) or "smoothness" (Temporal) to L0.
*   **Implementation**: Supported by **VP9** and **AV1**. Not supported by H.264 (usually).

**Performance**: SVC saves ~30% upstream bandwidth compared to Simulcast because it doesn't duplicate common video data.

---

## 🛡️ 4. Handling Extreme Congestion: The "Nuclear" Option

When the estimated bandwidth drops below 100kbps (unusable for video):
1.  **Resolution Drop**: 1080p -> 180p.
2.  **Bitrate Throttling**: The encoder is forced to a fixed max bitrate.
3.  **Frame Dropping**: 30fps -> 5fps (slideshow mode).
4.  **Audio Prioritization**: Video is turned off entirely to save the audio stream (the most critical part of a call).

---

## ⚡ 5. Optimization: Energy & Infrastructure Costs

At Google-scale, Simulcast is a strategy to be **"Infrastructure-Lazy"**—offloading the processing cost of multiple bitrates to the user's hardware rather than the server (MCU model).

*   **The Thumbnail Tax**: Sending high-bitrate video to a small thumbnail wastes energy in 4 stages: **Sending** (uplink), **Receiving** (downlink), **Decoding** (CPU/GPU), and **Scaling Down** (GPU).
*   **Application-Aware SFU**: To be truly efficient, the SFU must understand the **Application UI**. If the player window is small, the SFU must automatically "switch down" to the 150kbps layer before the bits even cross the network.

## ✅ Principal Architect Checklist

1.  **Enable Simulcast for >3 Participants**: Never send a single-stream "high quality" video in a group call; you will crush the weakest link.
2.  **Use `transport-cc`**: Prefer Transport-wide Congestion Control over Receiver-side BWE (REMB) for faster reaction to network changes.
3.  **Differentiate Content**: Set `contentHint: 'detail'` for screen shares (prioritize resolution) and `contentHint: 'motion'` for webcam (prioritize frame rate).
4.  **Hardware Acceleration**: Simulcast on 3 streams is CPU-intensive. Always verify the client is using the **Hardware Encoder** (see `webrtc-client-performance-guide.md`).

---

## 🔗 Related Documents
- [WebRTC Scaling](./webrtc-scaling-architecture-guide.md) — SFU replication.
- [Transport Protocols](./webrtc-transport-protocols-guide.md) — SCTP and UDP mechanics.
- [WebRTC Media Engine](./webrtc-media-engine-architecture-guide.md) — How codecs handle bitrates.
