# Collaborative A/V Architecture: Beyond Video Calls

> **Source**: [Around: The Future of Collaboration](https://youtu.be/bvj0_97BJkw)

> [!IMPORTANT]
> **The Shift**: From "Meetings" (Passive, Grid View) to "Collaboration" (Active, Floating Overlay).
> **The Tech**: Native Electron apps allow **raw access** to audio hardware that browsers block.

---

## 🎧 High-Fidelity Audio Pipeline

Browsers (Chrome) are aggressive with audio processing:
1.  **Auto Gain Control (AGC)**: Constant volume fluctuation.
2.  **Noise Suppression**: Aggressively cuts frequencies, making music/design work impossible.
3.  **Echo Cancellation (AEC)**: Good for speech, bad for "co-located" scenarios.

### The "Echo Terminator" Pattern (Ultrasonic Sync)
**Problem**: 5 people in one room, all on laptops.
**Result**: Screeching feedback loop.

**Solution**:
1.  **Ultrasonic Beacon**: Laptop A emits a high-freq sound (20kHz+).
2.  **DSP detection**: Laptop B hears the beacon via mic.
3.  **Sync**: Software identifies they are effectively "one device" in the audio space.
4.  **Mute Logic**: Only *one* microphone stays open for the group, or DSP subtracts neighbors' input perfectly.

> **Architecture Note**: This requires **Client-Side DSP** (Digital Signal Processing) in C++/WASM. You cannot do this reliably with standard WebRTC APIs in a browser sandbox.

---

## ⚛️ Electron vs Browser for WebRTC

Why build a native app (Electron) instead of a Web App?

| Feature | Browser (Chrome) | Electron (Native) |
| :--- | :--- | :--- |
| **Codecs** | Limited (VP8/9, H.264) | **Any** (Can bundl custom FFmpeg) |
| **Audio Access** | Restricted (processed stream) | **Raw PCM** access via CoreAudio/WASAPI |
| **Global Overlay** | Impossible | **Floating Windows** over other apps (Figma/VS Code) |
| **Updates** | Immediate (Force Refresh) | Controlled (Ignore breaking Chrome updates) |
| **Push to Talk** | Focused window only | **Global hotkey** (System level) |

**Verdict**: For *casual* calls, use Browser. For *work tools*, use Electron.

---

## 📡 MediaSoup SFU Architecture

**MediaSoup** is a unique SFU choice compared to Janus/Jitsi.

### The Code Structure
*   **Core**: C++ (handles RTP/RTCP, SRTP encryption).
*   **Control Plane**: Node.js (handles signaling, room logic).
*   **Communication**: Communication via C++ Worker pipes.

### Scaling: "Pipe to Router" pattern
To scale beyond one CPU core:
1.  **Router A** (Core 1) hosts User 1 & 2.
2.  **Router B** (Core 2) hosts User 3 & 4.
3.  **PipeTransport**: Connects Router A → Router B via internal memory/loopback.

```mermaid
graph TD
    subgraph "Server (Node.js)"
        Worker1[Worker 1 (C++)] --> RouterA
        Worker2[Worker 2 (C++)] --> RouterB
        
        RouterA -- PipeTransport --> RouterB
    end
    
    User1 --> RouterA
    User2 --> RouterA
    
    User3 --> RouterB
    User4 --> RouterB
```

**Why it wins**:
*   **Granularity**: You can run 1 Router per CPU core.
*   **Language**: Engineers write easy JS/TS for logic, get C++ performance for media.

---

## 🎨 The "Floating Head" UX Pattern

**Goal**: "Multi-player Solitaire". Users work *alone together*.

### Implementation
1.  **Background Removal**: Must happen client-side (TensorFlow Lite / Mediapipe).
2.  **Cropping**: Center-crop face to circle.
3.  **Window Management**:
    *   **Mac**: `NSPanel` with `NSWindowStyleMaskHUDWindow`.
    *   **Windows**: `WS_EX_LAYERED | WS_EX_TRANSPARENT` (Click-through).

**Bandwidth Optimization**:
*   Crop happens *before* encoding.
*   Sends 300x300 video (very low bitrate) instead of 720p backdrop (wasted pixels).
*   **Result**: 50kbps per user vs 1000kbps standard.

---

## ✅ Principal Architect Checklist

1.  **Choose Electron for Audio Control**: If your app needs noise suppression better than Chrome's default, or "push-to-talk" while minimized.
2.  **Evaluate MediaSoup for Node.js Teams**: If your backend team knows TS/Node, MediaSoup is the lowest friction SFU.
3.  **Implement Client-Side Cropping**: Don't send pixels that will be masked out. Crop *then* encode to save 80% bandwidth.
4.  **Use Ultrasonic Detection for Hybrid Work**: The "Everyone in one conference room" problem is only solved by identifying proximity (Audio/Bluetooth beacons).

---

## 🔗 Related Documents
*   [WebRTC Scaling](./webrtc-scaling-architecture-guide.md) — Cascading logic.
*   [Edge AI Processing](./edge-ai-processing-guide.md) — Client-side BG removal.
