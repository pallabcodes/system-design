# WebRTC GenAI Integration: Automating the "After-Call"

> **Source**: [Generative AI for ACW](https://youtu.be/s8uvs2xZ8jE)

> [!IMPORTANT]
> **The Metric**: "After Call Work" (ACW) takes 25% of an agent's time.
> **The Fix**: Automate the "Wrap-Up" phase using Generative AI (LLMs).
> **The ROI**: Reducing ACW from 5 mins to 0 mins = 20% Capacity Increase.

---

## 🏗️ 1. Architecture: The Async Pipeline

Unlike Real-time Media (WebRTC), GenAI is slow (Tokens/sec).
We decouple the **Call** (Synchronous) from the **Intelligence** (Asynchronous).

```mermaid
graph TD
    Call[WebRTC Call] -->|Real-time| RTP[Media Server]
    RTP -->|Fork Stream| Recorder[S3 / Storage]
    
    subgraph "Post-Call Pipeline"
        Recorder -->|Audio File| STT[Speech-to-Text API]
        STT -->|Transcript| LLM[LLM (GPT-4 / Claude)]
        LLM -->|Summary/Action Items| CRM[Salesforce/HubSpot]
    end

    Note[Agent hangs up. Pipeline runs in background.]
```

### Key Components
1.  **Orchestrator**: Triggers the pipeline when `call_ended` event fires.
2.  **STT Engine**: Deepgram / Symbl / OpenAI Whisper. (Must support Diarization - identifying *who* spoke).
3.  **LLM Layer**: Summarizes the transcript into JSON.

---

## 🧠 2. The Feedback Loop: Training the Bot

GenAI isn't just for summaries. It's for **Process Mining**.

### The "Giant Feedback Loop"
1.  **Analyze Humans**: AI reads 10,000 human agent transcripts.
2.  **Identify Gaps**: "Agents answer 'How do I reset password' 500 times/day."
3.  **Train Bot**: Update the IVR/Chatbot to handle this specific intent.
4.  **Result**: Deflect 20% of calls to the Bot.

### Sentiment Analysis as a Trigger
*   **Real-time**: If Customer Sentiment < 0.2 (Angry) -> **Escalate** to Supervisor.
*   **Post-call**: If Sentiment ended Negative -> Schedule proactive callback from "Senior Manager".

---

## 🛡️ 3. Security & Compliance (Symbl.ai Model)

**The Black Box Problem**: Sending audio to OpenAI is a privacy risk.
**The Solution**: PII Redaction Middleware.

### The Pipeline
1.  **Input**: Raw Audio.
2.  **Redactor**: Detects "Credit Card", "SSN", "Name". Replaces with `[REDACTED]`.
3.  **LLM**: Processes clean text.
4.  **Output**: Safe Summary.

> **Requirement**: Use a vendor (like Symbl.ai or specialized Vonage APIs) that is SOC2/HIPAA compliant and offers BAA. Do not roll your own connection to generic public LLM endpoints with patient data.

---

## ⚡ 4. Implementation Strategy

| Maturity Level | Feature | Implementation Time |
| :--- | :--- | :--- |
| **Level 1 (MVP)** | **Summary Email**: Send transcript + 3 bullet points to Agent. | 1 Week |
| **Level 2 (CRM)** | **Auto-Populate**: Push structured fields (Deal Size, Next Steps) into Salesforce. | 1 Month |
| **Level 3 (RAG)** | **Agent Assist**: Real-time "Copilot" suggesting answers based on Knowledge Base. | 3 Months |

### The "Scribe" Analogy
Don't ask the Doctor to write the report.
The Doctor (Agent) focuses on the Patient (Customer).
The "Invisible Scribe" (AI) writes the report.

---

## ✅ Principal Architect Checklist

1.  **Diarization is Critical**: If the transcript says "User: Hello" but doesn't know *which* user, the Summary will be garbage. Use Stereo recording (Agent Left / Customer Right).
2.  **Latency vs Cost**: For ACW, latency doesn't matter. Use cheaper "Batch" APIs instead of "Streaming" APIs.
3.  **Hallucination Check**: Force the LLM to output "Confidence Score". If < 0.8, flag for human review.

---

## 🔗 Related Documents
*   [WebRTC Recording](./webrtc-recording-guide.md) — How to generate the files for the pipeline.
*   [Edge AI Processing](./edge-ai-processing-guide.md) — Contrast: Edge AI (Vision) vs Cloud AI (Language).
