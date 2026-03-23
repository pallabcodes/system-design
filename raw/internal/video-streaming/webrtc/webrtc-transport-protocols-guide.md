# WebRTC Transport Protocols: The Packet Journey

> **Source**: [Protocols & Ports Explained](https://youtu.be/5zjnB_ZGetU)

> [!IMPORTANT]
> **The Myth**: "WebRTC uses random ports."
> **The Reality**: Modern WebRTC uses **Single-Port Multiplexing** (RFC 9143).

---

## 📦 1. The Protocol Stack

WebRTC is not a single protocol. It is a collection of standards glued together.

### The OSI Model View

| Layer | Protocol | Role |
| :--- | :--- | :--- |
| **App (L7)** | **SDP** | "I want to send Video (VP8) and Data." |
| **Security (L6)** | **DTLS** | Handshake, Key Exchange (Encryption). |
| **Session (L5)** | **SRTP / SCTP** | Encrypted Media / Data. |
| **Transport (L4)** | **UDP / ICE** | Fire-and-forget delivery. NAT Traversal. |
| **Network (L3)** | **IP** | Routing. |

---

## 🧵 2. Multiplexing: The BUNDLE Standard

In 2013, a WebRTC call with Audio+Video used 4 ports (RTP Audio, RTCP Audio, RTP Video, RTCP Video).
Today, we use **BUNDLE**.

### How it works
1.  **Single Port**: Client opens *one* UDP port (e.g., 50000).
2.  **Demultiplexing**:
    *   **STUN Packet**? Handled by ICE Agent.
    *   **DTLS Packet**? Handled by OpenSSL.
    *   **SRTP Packet**? Check SSRC (Synchronization Source ID).
        *   `SSRC=123` -> Audio Decoder.
        *   `SSRC=456` -> Video Decoder.

### Why it matters
*   **Firewall Friendly**: IT Admins only need to see 1 "hole" in the firewall, not 4 dynamic holes.
*   **Faster Setup**: Only 1 pair of candidates to verify.

---

## ⚡ 3. UDP vs TCP: The "Reliability" Trade-off

The source mentions "Couriers vs Trucks". In engineering terms, this is **Head-of-Line Blocking**.

### Why Video Hates TCP
*   **Scenario**: You send Frame 1 (I-Frame) and Frame 2 (P-Frame).
*   **Event**: Packet 50 of Frame 1 is dropped.
*   **TCP**: Stops everything. Retransmits Packet 50. Waits.
    *   *Result*: Frame 2 is ready on client, but TCP stack won't deliver it until Frame 1 is perfect. **Video Freezes**.
*   **UDP**: Ignores drop.
    *   *Result*: Frame 1 glitches (artifact). Frame 2 plays immediately. **Video Flows**.

### SCTP (Data Channels)
SCTP sits on top of UDP but can *emulate* TCP when needed.
*   `ordered: true` (TCP-like): Good for Chat.
*   `ordered: false` (UDP-like): Good for Gaming Inputs (Mouse position).

---

## 📏 4. MTU & Fragmentation

A router can typically handle **1500 bytes** (Ethernet MTU).
A 1080p frame is **20,000 bytes**.

### Fragmentation
WebRTC breaks the frame into RTP packets (approx 1200 bytes each).
*   **Risk**: If *one* IP packet is dropped, the *entire* video frame might be undecodable.
*   **Strategy**:
    *   **NACK**: Receiver asks "Send packet 5 again".
    *   **FEC**: Sender sends "Parity Packets" (redundancy) so receiver can reconstruct packet 5 without asking.

---

---

## 🚀 5. The TCP Fallback Strategy: Performance over Protocol

Sometimes, the firewall wins. You are forced onto **TURN-TCP** (Port 443).
In this "Non-Ideal" scenario, your WebRTC configuration must change.

### Optimization Matrix:
1.  **Disable NACK & RTX**: These "Retransmission" mechanisms conflict with TCP’s internal retransmission. Using both leads to "Retransmission Cascades" that amplify congestion.
2.  **Increase Buffers**: TCP jitter is higher. Increase your Jitter Buffer (min-delay) to 200ms to smooth out the "sawtooth" delivery pattern of TCP.
3.  **Lower Max-Bitrate**: TCP’s congestion window (CWND) is more sensitive than WebRTC's GCC. Hard-cap your video to 70% of the estimated bandwidth to prevent TCP timeouts.

---

## ✅ Principal Architect Checklist

1.  **Force BUNDLE**: Ensure your SDP Offer contains `a=group:BUNDLE 0 1`. If not, legacy browsers might try to open multiple ports.
2.  **Check MTU**: If users are on VPNs (adds headers -> lowers MTU to 1300), your 1400-byte packets will fragment at the IP layer (Bad). Set WebRTC Max Packet Size to 1200.
3.  **Audit Data Channels**: Don't use `ordered: true` for "Live Cursor" tracking. It will lag. Use `ordered: false`, `maxRetransmits: 0`.

---

## 🔗 Related Documents
*   [NAT Traversal](./webrtc-nat-traversal-guide.md) — How ICE finds the port.
*   [WebTransport](./webtransport-architecture-guide.md) — The future replacement for SCTP.
