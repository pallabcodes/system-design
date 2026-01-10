# WebRTC Computer Vision Patterns: Attention & Privacy

> **Source**: [Attention Detection with MediaPipe](https://youtu.be/0CDQwzLORUM)

> [!IMPORTANT]
> **The Paradigm Shift**: Don't send video to the cloud for analysis.
> **The Fix**: Process on the Client (TensorFlow.js/MediaPipe). Send **Metadata** (JSON), not Pixels.

---

## 🏗️ 1. Architecture: The "Metadata-First" Signal

Traditional AI sends the stream to a server. This is slow, expensive, and privacy-invasive.
The modern pattern keeps the pixels on the user's laptop.

### The Flow
1.  **Capture**: `getUserMedia` gets the webcam stream.
2.  **Inference**: **TensorFlow MediaPipe** runs locally (GPU/WASM) to extract Face Landmarks.
3.  **Compute**: Calculate "Attention Score" (Integer 0-4) from Yaw/Pitch/Roll.
4.  **Signal**: Broadcast **only the score** to other participants via Data Channel or Signal Server.

**Bandwidth Impact**:
*   Video AI (Server-Side): **2 Mbps** upload per user.
*   Metadata AI (Client-Side): **200 Bytes** per second.

---

## 🧠 2. The Algorithm: Head Pose Estimation

How do you measure "Engagement" without recording the user?
**Head Pose** (Yaw, Pitch, Roll) is a strong proxy for attention.

### The "Attention Score" Formula
1.  **Extract Landmarks**: Eye corners, Nose tip.
2.  **Calculate Vectors**:
    *   **Yaw**: Side-to-side (Looking at second monitor?).
    *   **Pitch**: Up-and-down (Looking at phone?).
    *   **Roll**: Tilt (Sleeping?).
3.  **Normalize**: Map angles to a 0-1 confidence interval.
4.  **Product**: `Score = (YawFactor * PitchFactor * RollFactor) * 4`.

**Output Levels**:
*   **0-1**: Distracted (Looking away).
*   **2-3**: Passive (Listening).
*   **3-4**: Engaged (Staring at camera).

---

## 🛡️ 3. Privacy & Compliance (GDPR)

### "Compute on Edge" Advantage
*   **GDPR**: If you send a video of a face to the cloud, you are processing Biometric Data (High Risk).
*   **Legal Hack**: If the face **never leaves the device**, and you only transmit the integer "4", you are likely *not* processing Biometric Data in the cloud. You are processing "Metadata".
*   **Performance**: Zero latency. The user sees their own attention score update instantly.

---

## ⚡ 4. Implementation Optimization: The Throttling Pattern

**Naive Implementation**:
```javascript
// BAD: Floods signaling server (60 messages/sec)
function onFrame(results) {
  const score = calculateScore(results);
  signalServer.send({ type: 'attention', value: score });
}
```

**Principal Architect Implementation**:
1.  **Debounce**: Only calculate every 10th frame (3 iterations/sec is enough for "Attention").
2.  **Thresholding**: Only send update if score changes by > 0.5.
3.  **Transport**:
    *   **Data Channel**: Use for high-frequency (10Hz) updates.
    *   **Signal Server**: Use for low-frequency (0.2Hz) "Report Card" summaries to the Host.

---

## ✅ Principal Architect Checklist

1.  **Audit the Frame Rate**: Don't run Face Mesh at 60fps. It burns the user's battery. Cap AI at 10fps.
2.  **Use Web Workers**: Move MediaPipe Loop to a Worker Thread (see [Client Performance Guide](./webrtc-client-performance-guide.md)).
3.  **Fallback**: What if the user has no GPU? Detect `low-end device` and disable AI automatically.
4.  **Contextual Mapping**: Correlate "Attention Drops" with "Speaker Logs" (Transcription timestamp) to generate a "Boredom Heatmap" for the presenter.

---

## 🔗 Related Documents
*   [Client Performance Guide](./webrtc-client-performance-guide.md) — How to run MediaPipe in a Worker.
*   [Edge AI Processing](./edge-ai-processing-guide.md) — Server-side alternatives for IoT.
*   [Collaborative AV](./collaborative-av-architecture-guide.md) — Uses for metadata signaling.
