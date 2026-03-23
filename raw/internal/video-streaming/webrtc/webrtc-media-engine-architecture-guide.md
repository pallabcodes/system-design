# WebRTC Media Engine: ML-Assisted Audio & Video

> **Scope**: Noise Suppression (RNNoise), Packet Loss Concealment (WaveNet EQ), and Codec State Machines.

> [!IMPORTANT]
> **The Shift**: We are moving from "Hand-Coded Math" (DSP) to "Machine Learning" (ML) at the infrastructure level. Modern WebRTC agents no longer just filter audio; they *reconstruct* it.

---

## 🎙️ 1. Audio Processing: Beyond the Notch Filter

Classical DSP used fixed mathematical rules (e.g., "reduce energy at 50Hz"). Modern WebRTC utilizes **ML-driven classification**.

### RNNoise: The Speech/Noise Classifier
RNNoise uses a GRU (Gated Recurrent Unit) network to process frequency bands.
*   **Mechanism**: It doesn't just "mute" noise; it calculates a gain factor for 22 frequency bands in real-time.
*   **Targeted Noises**: Specifically trained for non-stationary sounds: babies crying, dogs barking, and home renovations.
*   **The Reverb Problem**: Modern ML now solves **"The Glass Room" effect**. Reverb removal (dereverberation) subtracts the delayed reflections of audio bouncing off walls, significantly improving clarity in suboptimal home environments.

### Opus 1.5: The Hybrid Codec
Opus is the "Swiss Army Knife" of audio. It dynamically switches between two internal engines:
1.  **SILK (Voice)**: Optimized for human speech (LP-based). 
2.  **CELT (Music/Noise)**: Optimized for high-fidelity audio (MDCT-based).
3.  **ML Decision**: The encoder uses an internal ML model to analyze signals and decide the Silk/CELT mix per-frame, yielding a 20% improvement in perceived voice transparency.

---

## 🎭 2. Semantic Audio: Accents & Identity

We are entering the era of **Persona-based Audio**, where the goal isn't just "clarity," but "transformation."

*   **Accent Removal**: Real-time transformation of accents (e.g., changing a regional accent to Standard English) to improve intelligibility in global call centers.
*   **Voice Signatures/Identity**: Using a synthetic 5-second sample to generate the user's voice in a different language or tone, while maintaining unique vocal characteristics.
*   **Super-Resolution (Upsscaling)**: At the receiving end, AI can "upscale" a 16kHz voice to 48kHz by hallucinating missing high-frequency harmonics for a "Studio Quality" feel.

---

## 🔄 3. Resiliency: Generative Packet Loss Concealment (PLC)

When a packet is lost, the audio "pops." Historically, we used Zero-Padding or Frame Replication.

### WaveNet EQ (Google Duo)
Instead of repeating the last frame, Google uses a generative model to **hallucinate the next 20ms**.
1.  **ML-Driven FEC**: Beyond simple PLC, architects now use ML to determine the **Forward Error Correction (FEC)** budget dynamically. The machine decides the "protection" level based on 60-second loss history.

---

## 📺 3. Video Manipulation: Generative Overlays

At Google-scale, video processing is moving toward **Semantic Manipulation**.

### Real-Time Inpainting
The future of WebRTC involve "cleaning" the video stream before it hits the encoder.
*   **Privacy Use Case**: Automatically "scribbling out" or blurring sensitive objects (beer bottles, laundry, private documents) in a home office set-up.
*   **Background Maintenance**: Unlike simple "Background Blur" (which just blurs pixels), **Inpainting** uses GenAI to reconstruct the background *behind* the user, ensuring no "ghosting" effects when the user moves.

---

## 📊 5. Responsibility & Implementation Matrix

| Strategy | Implementation | Scalability | Trade-off |
| :--- | :--- | :--- | :--- |
| **External App** | Krisp.ai (Virtual Mic) | 🟢 Zero Infra Cost | 🔴 Requires User Install |
| **SDK-Level** | Daily.co / Vonage | 🟢 Fast TTM | 🔴 Vendor Lock-in |
| **Hardware** | Intel/Nvidia GPU/GPU | **🟢 Best Efficiency** | 🔴 Hardware Dependent |
| **Server-Side** | **Nvidia Maxine** | 🟢 Universal Support | 🔴 High Egress/GPU Cost |

---

## ✅ Principal Architect Checklist

1.  **Audit the "Glass Room"**: Ensure your de-noise stack includes **Dereverberation** for remote workers.
2.  **ML-FEC over Fixed-FEC**: Implement a dynamic error correction budget. Audio packets are cheap; human frustration is expensive.
3.  **Hardware Offloading**: Detect presence of **Nvidia/Intel AI accelerators**. Use them to offload background removal and de-noise to save user battery.
4.  **Privacy Scrutiny**: If processing audio/video on the server (Maxine), you MUST disclose this to the user as E2EE is likely broken.

---

## 🔗 Related Documents
- [Adaptive Bitrate Architecture](./webrtc-adaptive-bitrate-architecture-guide.md) — How the media engine reacts to network drops.
- [Client Performance Guide](./webrtc-client-performance-guide.md) — Running ML in Web Workers.
- [WebRTC Evolution](./webrtc-evolution-guide.md) — The history of Codecs.
