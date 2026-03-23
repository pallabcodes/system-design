# Project Starline Architecture: The Future of Telepresence

> **Level**: Principal Architect / Research Engineer
> **Scope**: Volumetric Video, Light Field Displays, Real-Time compression, and Custom WebRTC extensions.

> [!IMPORTANT]
> **The Goal**: "Magic Window". Make the person look 3D and "there" without 3D glasses.
> **The Tech**: 65" Light Field Display + 4 Cameras + 4 IR Sensors + Custom WebRTC + FPGA/GPU Compression.

---

## 🌌 1. The Hardware: "Magic Window" Physics

Standard video is 2D (pixels). Starline is **Volumetric** (voxels/depth).

### The Capture System
*   **Stereo Cameras**: 4 sensors capture different angles to build a depth map.
*   **Infrared Depth Sensors**: Active IR pulses measure exact distance (LiDAR-style) to handle "featureless" surfaces (e.g., a white t-shirt) where stereo vision fails.
*   **Audio**: Beamforming microphone array tracks the mouth to simulate "spatial audio" (sound comes from the mouth's location on screen).

### The Render System (Light Field)
*   **Lenticular Lens**: The display has microscopic lenses sitting on top of the pixels.
*   **Eye Tracking**: Cameras track the viewer's eyes in real-time.
*   **Perspective Correction**: The system renders *two different images* (one for left eye, one for right) interlaced beneath the lenses.
*   **Result**: As you move your head, you see "around" the person (Parallax).

---

## 💾 2. Compression: From 10Gbps to 100Mbps

**Raw Data**: 4x 4K Streams + Depth Maps = ~10 Gbps (Uncompressed).
**Target**: Consumer Internet (30-100 Mbps).

### The Pipeline
1.  **Fusion (Sender)**: Combine RGB + Depth into a 3D Mesh (Geometry + Texture).
2.  **Compression (Sender)**:
    *   **Texture**: Standard HEVC (H.265) hardware encoder.
    *   **Geometry**: Custom "Draco" compression (Google's library for 3D mesh compression).
    *   **Warping**: Transmit a "base view" + "delta views".
3.  **Transmission**: WebRTC Data Channels (for Geometry) + RTP (for Texture).
4.  **Rendering (Receiver)**: GPU shaders reconstruct the light field view based on *local* eye tracking.

> **Why not just Video?** If you send a fixed video, the parallax breaks when the viewer moves their head. You *must* send geometry.

---

## 🌐 3. Networking: The WebRTC Extensions

Standard WebRTC is built for 2D frames. Starline forced Google to modify the stack.

### Bandwidth Management
*   **Requirement**: ~30-100 Mbps constant bitrate. (Zoom uses < 3 Mbps).
*   **Congestion Control**: Tweaked BBR (Bottleneck Bandwidth and Round-trip propagation time) algorithm. Standard GCC (Google Congestion Control) is too timid for such high throughput.

### Latency Budget (Glass-to-Glass)
*   User moves head -> Eye Tracker detects -> GPU renders new view -> Local Display updates.
*   **Constraint**: Motion-to-Photon latency must be **< 20ms** locally to prevent motion sickness.
*   **Network Latency**: Must be **< 100ms** for natural conversation (standard VoIP rule).

### Synchronization
*   **RGB + Depth Sync**: If Texture arrives before Geometry, the face "slides off" the nose.
*   **Solution**: Strict RTP timestamp alignment between the H.265 video stream and the Custom Geometry stream.

---

## 🔮 4. The Future: "Starline in Your Pocket"

Starline started as a $50k booth. The goal is to fit it into a laptop/TV.

### HP + Google Partnership (2025)
*   **Sensors**: Moved from "4 massive cameras" to standard webcam bar (AI depth estimation replaces dedicated IR sensors).
*   **Display**: Standard 2D screen usage (Monoscopic 3D) vs active Lenticular.

### AI Upscaling (NeRFs)
*   Instead of sending heavy geometry, send sparse data and let **NeRFs (Neural Radiance Fields)** hallucinate the missing angles on the consumer's GPU.
*   *Bandwidth*: Drops from 30 Mbps -> 5 Mbps.

---

## ✅ Principal Architect Checklist

1.  **Understanding Volumetric Data**: Stop thinking in pixels. Think in "Textured Mesh".
2.  **Bandwidth Planning**: 3D Telepresence requires fiber-like speeds (50Mbps+ stable upload). It is not 4G friendly yet.
3.  **Latency is Critical**: Parallax lag (moving head vs screen update) causes nausea. The local render loop must be 60fps locked.
4.  **Audio Spatialization**: Audio must be "anchored" to the 3D geometry. If the person leans left, sound comes from the left.

---

## 🔗 Related Documents
*   [WebRTC Evolution](./webrtc-evolution-guide.md) — From VoIP to Holodeck.
*   [Collaborative A/V](./collaborative-av-architecture-guide.md) — The "Around" approach (2D overlay).
