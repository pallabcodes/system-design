# WebRTC Real-Time Voice Bots: The Latency Challenge

> **Source**: [LLMs Meet WebRTC](https://youtu.be/GpueVW3NCe4)

> [!IMPORTANT]
> **The Goal**: Sub-200ms response time for Voice Bots (Human-like conversation).
> **The Reality**: STT (150ms) + LLM (500ms) + TTS (300ms) = **950ms** total. Unusable.
> **The Strategy**: Streaming APIs + Context Caching + Predictive TTS.

---

## 🏗️ 1. The Pipeline: STT → LLM → TTS

Unlike "After Call Work" (which is async), Voice Bots must respond in **real-time**.

```mermaid
graph LR
    User[User speaks] -->|Audio| WebRTC[WebRTC Stream]
    WebRTC -->|Fork| STT[Speech-to-Text]
    STT -->|Transcript| LLM[GPT-4 / Claude]
    LLM -->|Response Text| TTS[Text-to-Speech]
    TTS -->|Audio| WebRTC2[WebRTC Stream Back]
    WebRTC2 --> User2[User hears]
```

### The Latency Breakdown
| Component | Latency | Optimization Target |
| :--- | :--- | :--- |
| **STT (Deepgram/Whisper)** | 150-300ms | Use Streaming API, not Batch. |
| **LLM (GPT-4o)** | 500-2000ms | Cache system prompts. Stream tokens. |
| **TTS (ElevenLabs/PlayHT)** | 300-800ms | Use Streaming TTS. Start playback ASAP. |
| **Network RTT** | 50-100ms | Edge deployment (reduce hops). |

---

## ⚡ 2. Optimization Strategy: The "Dual Processing" Pattern

**The Problem**: 
*   Fast STT produces errors ("their" vs "there").
*   Contextual STT corrects after 2 seconds (too late for LLM).

**The Solution**:
1.  **Fast Track (User-Facing)**: Display rough transcript immediately.
2.  **Slow Track (Bot-Facing)**: Send corrected transcript to LLM.
3.  **Result**: User sees instant feedback. LLM gets accurate context.

### Architecture
```javascript
// Dual Stream
const fastSTT = new Deepgram({ model: 'nova-2', latency: 'low' });
const accurateSTT = new Deepgram({ model: 'nova-2', latency: 'balanced' });

fastSTT.on('transcript', (text) => {
  ui.showTranscript(text); // Instant feedback
});

accurateSTT.on('final', (text) => {
  llm.send(text); // Accurate input
});
```

---

## 🔥 3. The "Streaming TTS" Trick

Standard TTS waits for the full sentence ("Hello, how can I help you?") before generating audio.
**Streaming TTS** generates audio *per-word*.

### The Math
*   **Batch TTS**: 800ms (entire sentence).
*   **Streaming TTS**: 100ms (first word) + 50ms/word.
    *   **Result**: User hears "Hello" after 100ms. Feels instant.

### Implementation (ElevenLabs)
```javascript
const stream = await elevenLabs.textToSpeechStream({
  text: llmResponse,
  voice_id: 'voice_123',
  model_id: 'eleven_turbo_v2',
  stream: true,
});

for await (const chunk of stream) {
  audioTrack.enqueue(chunk); // Feed to WebRTC immediately
}
```

---

## 🛡️ 4. Infrastructure: "AI-SFU" Hybrid

Where do you run the AI? Client (Browser) or Server?

| Architecture | Latency | Cost | Use Case |
| :--- | :--- | :--- | :--- |
| **Client-Side (WebAssembly)** | 🟢 0ms (local) | 🟢 $0/call | Small models (Whisper Tiny). |
| **Edge AI (Cloudflare Workers)** | 🟡 50ms | 🟡 $0.01/call | STT only. LLM too heavy. |
| **Cloud (GPU Cluster)** | 🔴 200ms+ | 🔴 $0.05/call | Full pipeline (STT+LLM+TTS). |

**Principal Architect Pattern**: Run **STT on Edge** (lowest latency). Run **LLM/TTS on GPU Cluster** (requires power).

---

## ✅ Principal Architect Checklist

1.  **Use Streaming everywhere**: Batch APIs are for ACW (After Call Work), not Real-Time Voice.
2.  **Cache System Prompts**: If your LLM "System Prompt" is 2000 tokens, cache it server-side. Only send the new User message (50 tokens).
3.  **Measure "Time to First Word"**: This is the *perceived* latency. Optimize this metric, not "Total Processing Time".
4.  **Fallback to Silence**: If LLM takes >3 seconds, the Bot should say "Let me think..." to fill dead air.

---

## 🔗 Related Documents
*   [GenAI Integration](./webrtc-genai-integration-guide.md) — Async pipeline (ACW).
*   [Computer Vision Patterns](./webrtc-computer-vision-patterns-guide.md) — Client-side AI (MediaPipe).
