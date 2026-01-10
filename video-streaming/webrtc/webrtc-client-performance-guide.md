# WebRTC Client Performance: Liberating the Main Thread

> **Source**: [Offscreen Canvas & WebCodecs](https://youtu.be/kabSBPiNfD8)

> [!IMPORTANT]
> **The Bottleneck**: The Browser Main Thread. It handles UI (React/DOM), JavaScript logic, and WebRTC events.
> **The Fix**: Move media processing to **Worker Threads** via OffscreenCanvas and WebCodecs.

---

## 🏎️ 1. OffscreenCanvas: 60FPS UI + 60FPS Video

**Problem**:
*   You have a 4K Video feed.
*   You render a dynamic "Face Filter" (WebGL) on top.
*   The UI freezes (Updates DOM) -> Video stutters. Video processes -> UI freezes.

**Solution**:
1.  **Main Thread**: Handles DOM elements (Buttons, Chat).
2.  **Worker Thread**: Handles the `<canvas>` rendering.
3.  **Mechanism**: `canvas.transferControlToOffscreen()`.

```javascript
// Main Thread
const canvas = document.getElementById('my-video-canvas');
const offscreen = canvas.transferControlToOffscreen();
const worker = new Worker('video-worker.js');
worker.postMessage({ canvas: offscreen }, [offscreen]); // Zero-copy transfer

// Worker Thread
onmessage = (evt) => {
  const canvas = evt.data.canvas;
  const ctx = canvas.getContext('2d'); // or 'webgl'
  // Render loop runs independent of UI jank
  requestAnimationFrame(drawVideo);
};
```

---

## 🧩 2. WebCodecs: Bypassing the Black Box

Standard `RTCPeerConnection` is a "Black Box". You give it a stream, it encodes it. You have no control.

**WebCodecs API** exposes the raw:
*   `VideoEncoder` / `VideoDecoder`
*   `AudioEncoder` / `AudioDecoder`

### Use Case: Cloud Gaming / Virtual Desktop
You don't need SRTP/ICE/DTLS overhead. You just want raw frames over WebSocket/WebTransport.

```javascript
// decoding-worker.js
const decoder = new VideoDecoder({
  output: (frame) => {
    // Draw raw YUV frame to WebGL texture instantly
    renderFrame(frame);
    frame.close();
  },
  error: (e) => console.error(e),
});

decoder.configure({
  codec: 'vp8',
  codedWidth: 1920,
  codedHeight: 1080,
});

// Feed raw bytes from WebSocket
socket.onmessage = (chunk) => {
  const chunk = new EncodedVideoChunk({
    type: 'key',
    timestamp: 0,
    data: chunk.data
  });
  decoder.decode(chunk);
};
```

### Advantages
1.  **Latency**: Zero-copy capability (Decoder -> WebGL).
2.  **Control**: Manually decide when to drop frames (skip non-keyframes) rather than letting WebRTC decide.
3.  **Performance**: Hardware Accelerated access via OS (VideoToolbox/NVENC).

---

## 💾 3. Insertable Streams: Two Flavors

WebRTC now lets you intercept media at two points in the pipeline: **Before Encode** (Raw) and **After Encode** (Packetized).

### A. Raw Streams (`MediaStreamTrackProcessor`)
**Use Case**: Background Blur, Face Filters (Snapchat style).
**Mechanism**: Access raw `VideoFrame` objects (YUV/RGBA) before they hit the encoder.

```javascript
// 1. Ingest Camera
const stream = await navigator.mediaDevices.getUserMedia({ video: true });
const track = stream.getVideoTracks()[0];

// 2. Breakout Box
const processor = new MediaStreamTrackProcessor({ track });
const generator = new MediaStreamTrackGenerator({ kind: 'video' });

// 3. Transform Loop (Worker)
const transformer = new TransformStream({
  async transform(frame, controller) {
    // MediaPipe SelfieSegmentation Logic here
    const newFrame = await applyBackgroundBlur(frame); 
    frame.close(); // Important: Release memory
    controller.enqueue(newFrame);
  }
});

// 4. Pipe to Generator
processor.readable.pipeThrough(transformer).pipeTo(generator.writable);

// 5. Send modified stream
const pc = new RTCPeerConnection();
pc.addTrack(generator); 
```

### B. Encoded Streams (`createEncodedStreams`)
**Use Case**: End-to-End Encryption (E2EE).
**Mechanism**: Access `RTCEncodedVideoFrame` (VP8/H.264 bytes) after the encoder.

```javascript
const sender = pc.addTrack(track);
const streams = sender.createEncodedStreams();
const transformer = new TransformStream({
  transform(chunk, controller) {
    // Encrypt the payload here (AES-GCM)
    // The browser doesn't know it's encrypted, just sees bytes.
    const encryptedData = encrypt(chunk.data);
    chunk.data = encryptedData;
    controller.enqueue(chunk);
  }
});
streams.readable.pipeThrough(transformer).pipeTo(streams.writable);
```

> **Warning**: Doing heavy CV logic (Blur) on 30fps 1080p video in JS is risky. ALWAYS offload the `transformer` logic to a **Web Worker** or use **WebGL/WASM**.

---

### C. Real-World Pattern: Dynamic Overlays (The "QR Code" Pipeline)

How to add a burned-in QR code or Text Ticker without killing the CPU?

1.  **The Factory**: Create a `Canvas` worker that accepts commands (`drawQR`, `drawText`).
2.  **The Pipeline**:
    *   **Input**: `VideoFrame` (Raw YUV).
    *   **Process**: Draw Frame to OffscreenCanvas -> Overlay QR Image -> `new VideoFrame(canvas)`.
    *   **Output**: Stream to Peer.
3.  **Optimization**: Only redraw the QR code when it changes. Cache it as an `ImageBitmap`.

```javascript
// Inside Worker
let qrBitmap = null; // Cache

onmessage = async (msg) => {
  if (msg.type === 'UPDATE_QR') {
    qrBitmap = await createImageBitmap(msg.blob);
  }
};

const transformer = new TransformStream({
  transform(frame, controller) {
    // 1. Draw Video
    ctx.drawImage(frame, 0, 0);
    // 2. Draw Cached QR (Zero CPU overhead vs generating it every frame)
    if (qrBitmap) ctx.drawImage(qrBitmap, 10, 10);
    
    // 3. Output
    const newFrame = new VideoFrame(canvas, { timestamp: frame.timestamp });
    frame.close();
    controller.enqueue(newFrame);
  }
});
```

---

## ✅ Principal Architect Checklist

1.  **Profile the Main Thread**: Use Chrome DevTools "Performance" tab. If "Scripting" > 30% during a call, you need OffscreenCanvas.
2.  **Use WebCodecs for Custom Transport**: Building a Zoom clone? Stay on WebRTC. Building a Stadia clone? Use WebTransport + WebCodecs.
3.  **Zero-Copy is King**: Minimizing `ArrayBuffer` copies between Main Thread and Worker is critical. Use `transferables` in `postMessage`.
4.  **Hardware Acceleration**: WebCodecs is the only way to reliably check if Hardware Acceleration is active (`await VideoEncoder.isConfigSupported()`).

---

## 🔗 Related Documents
*   [WebTransport Architecture](./webtransport-architecture-guide.md) — The transport layer for WebCodecs.
*   [WebRTC Evolution](./webrtc-evolution-guide.md) — History of these APIs.
