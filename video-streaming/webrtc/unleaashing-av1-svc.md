resource: https://www.youtube.com/watch?v=OJYEnAKHOaQ

This episode of **WebRTC Live** features Arin Sime and guest **Sergio Garcia Murillo**, a principal engineer at Millicast and founder of Medooze, discussing the implementation of **AV1 Scalable Video Coding (SVC)** and its impact on the next generation of live video.

### **1. Real-Time Streaming and the "Super League" Context**
The conversation begins with a discussion on the business of sports streaming, triggered by a Real Madrid vs. Chelsea football match. 
*   **Direct-to-Consumer Trends:** Sergio notes that top football clubs want to bypass intermediaries to stream directly to fans, personalizing the experience and capturing higher revenue than traditional TV rights.
*   **The Latency Barrier:** For industries like sports betting or interactive "watch parties," traditional streaming delays of 5 to 30 seconds are unacceptable; true real-time communication is required.

### **2. AV1: The Next Step in Video Codecs**
AV1 is described as an evolutionary step designed to provide **higher quality and larger image sizes at lower bitrates**. 
*   **Efficiency:** It aims for 20% to 30% less bitrate than VP9 for high-quality content like 4K at 60fps.
*   **Low-Bandwidth Resilience:** A significant use case is maintaining video in poor network conditions, such as streaming QVGA resolution at only 30 kbps.
*   **Mobile Constraints:** Currently, AV1 is more CPU-intensive and lacks hardware encoders on mobile devices, making it less ideal for standard mobile resolutions compared to VP9 or H.264 at this time.

### **3. Technical Innovations: SVC and Dependency Descriptors**
A major portion of the talk focuses on how AV1 handles **Scalable Video Coding (SVC)**.
*   **Generic Dependency Descriptor:** The WebRTC community (led by Google) developed a "codec-agnostic" way to express frame dependencies. This allows an **SFU (Selective Forwarding Unit)** to manage spatial and temporal layers without needing specific code for every new codec.
*   **End-to-End Encryption (E2EE):** AV1 was designed from the start to support E2EE. By placing the dependency information in an **RTP header extension** rather than the payload, an SFU can decide which packets to forward or drop without having to decrypt the actual video data.
*   **Error Recovery:** Because the SFU understands the importance of each packet through the descriptor, it can choose not to request a retransmission (NACK) for non-essential frames, reducing overall delay and bandwidth.

### **4. SVC Modes and Implementation**
Sergio demonstrates a patch for Chrome that allows developers to control various scalability modes:
*   **L-Modes:** Standard spatial and temporal layers (e.g., L1T2).
*   **K-Modes (Keyframe Modes):** These shift the timing of keyframes across different layers to prevent massive bandwidth spikes, leading to a smoother bitrate and a more reliable stream.
*   **S-Modes (KSBC):** Similar to **simulcast**, these send independent layers within a single RTP session. This makes switching at the SFU level more efficient than traditional simulcast because all packets arrive in a single ordered sequence.

### **5. The Future of Broadcast: WHIP and Beyond**
The discussion concludes with the shift from legacy protocols to modern WebRTC standards for broadcasting.
*   **WHIP (WebRTC-HTTP Ingestion Protocol):** This is a new effort at the IETF to create a standardized "ingest" protocol to replace **RTMP**. It will allow hardware encoders (like those from Teradek or AJA) to stream directly to platforms like Millicast or YouTube with WebRTC's low latency.
*   **Broadcast Quality:** Future goals include bringing professional broadcast features to WebRTC, such as **10-bit color, HDR (High Dynamic Range), 4:4:4 chroma subsampling, and multi-channel audio (Multi-Opus)**.
*   **Current Progress:** While the bitrate "ramp-up" in Chrome is currently slow for AV1, Sergio notes that speeds are improving rapidly, with SVC now capable of reaching over 30fps at VGA resolutions on standard desktops.

***

**Analogy for Understanding**
The **AV1 Dependency Descriptor** is like a **smart luggage tag** on a suitcase. In older systems, a security guard (the SFU) would have to open the suitcase (decrypt the video) to see if the contents were important. With AV1, the "tag" on the outside tells the guard exactly what’s inside and how important it is. If the plane is too heavy, the guard can see the tag and throw away a "luxury item" (a high-resolution layer) while keeping the "essentials" (the base video layer), all without ever needing the key to the suitcase.