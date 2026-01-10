# Edge vs. Cloud AI: The Architectural Strategy Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Latency Physics, Privacy Surface Area, and the "Weight Constraint" of Generative AI.

> [!IMPORTANT]
> **The Principal Trade-off**: Choosing between Edge and Cloud is a battle between **Infinite Compute (Cloud)** and **Minimum Latency (Edge)**. An architect must balance the cost-per-inference against the user's "Time-to-Action."

---

## 🏗️ 1. Decision Matrix: Edge, Cloud, or Hybrid

| Attribute | Edge AI (Local) | Cloud AI (Remote) |
| :--- | :--- | :--- |
| **Latency** | **< 10ms (Real-time)** | 100ms - 2s (Network dependent) |
| **Privacy** | 🟢 Zero-Egress (Data stays local) | 🔴 High-Egress (Must trust provider) |
| **Compute** | Limited by NPU/Mobile GPU | **Unlimited (H100 Clusters)** |
| **Cost** | Fixed (Hardware you own) | **Variable (Per-token / Per-inference)** |
| **Example** | FaceID / Predictive Text | ChatGPT / Midjourney |

---

## 🛡️ 2. Security Risks: The Cloud API Surface Area

While Cloud APIs allow for rapid scaling, they introduce three critical security vectors:

1.  **Intermediate Transit (MITM)**: Even with TLS 1.3, metadata (who is calling, when, and how much data) is exposed to ISPs and potential state actors.
2.  **Provider Data-at-Rest**: You are outsourcing your "Crown Jewels" (User Data). A breach at the AI provider (e.g., OpenAI or Anthropic) leaks your customers' data.
3.  **API Key Leakage**: In a cloud-first world, your API keys are "Golden Tickets." If a developer hardcodes a key or an environment file is exposed, your entire infrastructure budget can be drained in minutes by attackers running "Shadow Inference."

---

## 🧠 3. The "Generative AI" Challenge at the Edge

A common question is: **"Why can't we just run GenAI at the Edge?"**

### The Hardware Wall
Generative AI (LLMs) is fundamentally **ill-suited for edge-only development** due to:
*   **VRAM Hunger**: A 70B parameter model requires ~140GB of VRAM just to load. Most Edge NPUs (Neural Processing Units) struggle with models >7B.
*   **The Quantization Penalty**: To fit models on edge devices, we use "Quantization" (converting 16-bit weights to 4-bit). This drastically reduces the model's "IQ," leading to hallucinations that a server-side model would avoid.
*   **The Power/Heat Paradox**: Running a constant LLM on a smartphone or drone will throttle the CPU due to heat within minutes, or drain the battery entirely.

---

## 🔄 4. The "Intelligent Edge" Pattern: Hybrid AI

For Principal Architects, the answer is rarely "Cloud or Edge"—it is **Hybrid Orchestration**.

1.  **Edge for Classification (The Gatekeeper)**: A small model on the device (e.g., MobileNet) detects a face or a keyword.
2.  **Cloud for Generation (The Brain)**: Only once the event is triggered, the data is encrypted and sent to the cloud for heavy-duty reasoning (GPT-4).
3.  **Local Feedback Loop**: The cloud sends back improved weights periodically to "train" the small edge gatekeeper to be more accurate.

---

## ✅ Principal Architect Checklist

1.  **Assume Network Failure**: If your device is a smart lock or medical sensor, it MUST have an **Edge Fallback**. Never build a system that becomes a "brick" when the Wi-Fi drops.
2.  **Audit the "Per-Inference" Margin**: Cloud AI costs can eat your profit margins at scale. If your app has 1M users making 10 requests/day, a $0.01/inference API will bankrupt you ($300k/month).
3.  **Implement E2EE for AI**: If you must use the Cloud, use **Encrypted Inference** or **Trusted Execution Environments (TEE)** to ensure the AI provider cannot see the raw pixels/text.
4.  **Weight Optimization**: Use frameworks like **TensorFlow Lite** or **CoreML** to optimize for the specific silicon (Apple Neural Engine vs. Qualcomm Hexagon) rather than generic CPU execution.

---

## 🔗 Related Documents
- [Edge AI Processing (Video Focus)](../video-streaming/webrtc/edge-ai-processing-guide.md) — Hardware benchmarks (Pi, Jetson).
- [Computer Vision Patterns](../video-streaming/webrtc/webrtc-computer-vision-patterns-guide.md) — Metadata vs. Pixel signaling.
- [Strategic Marketplace](../video-streaming/webrtc/webrtc-strategic-marketplace-guide.md) — The cost of "Single-Container" AI.
