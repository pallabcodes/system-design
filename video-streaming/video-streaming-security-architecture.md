# Video Streaming Security: Principal Architect's Guide

> **Level**: Principal Engineer / SDE-3
> **Scope**: DRM, Watermarking, Zero-Trust Pipelines, and Attack Mitigation at Scale.

> [!IMPORTANT]
> **The Reality**: "Security" in video is not just HTTPS. It is a war against **stream ripping**, **credential sharing**, and **global piracy networks**.
> **The Goal**: Economic asymmetry. Make piracy more expensive than the subscription.

---

## 🛡️ The "Zero-Trust" Video Pipeline

Generic "Signed URLs" are insufficient for premium content. We implement a **defense-in-depth** strategy.

```mermaid
graph TD
    Client[Client Device] -->|1. Auth| IDP[Identity Provider]
    IDP -->|2. JWT| STS[Secure Token Service]
    STS -->|3. Short-Lived Access Token| Client
    
    Client -->|4. License Request (Encrypted)| LicenseServer[DRM License Server]
    Client -->|5. Content Request + Token| CDN[CDN Edge]
    
    subgraph "Trusted Execution Environment (TEE)"
        CDM[Content Decryption Module]
    end
    
    LicenseServer -->|6. License Keys| CDM
    CDN -->|7. Encrypted Chunks| Client
    Client -->|8. Decrypt in Hardware| CDM
```

### 1. The Token Strategy (Beyond Simple Signatures)
*   **HMAC vs Asymmetric**: Use **Ed25519** signatures for token generation (faster verification at edge than RSA).
*   **Binding**: Bind tokens to **Client IP** (with CIDR lenience for mobile capability) and **User-Agent Fingerprint**.
*   **Jitter**: Introduce random jitter to token expiration to prevent "thundering herd" renewal storms on your Auth Service.

### 2. Geoblocking 2.0 (VPN Detection)
*   **L3/L4 Checks**: Verify BGP ASN ownership (datacenter IPs vs residential).
*   **Latency Triangulation**: If IP says "London" but TCP RTT is 200ms (from Sydney), flag as proxy.
*   **TCP Fingerprinting**: Analyze TCP window size/scaling factors to detect OS mismatches (e.g., Linux stack spoofing an iPhone).

---

## 🔐 Multi-DRM Architecture (CPIX)

> **Standard**: **CPIX** (Content Protection Information Exchange) is the industry standard XML format for exchanging keys between your **Encoder/Packager** and **DRM Provider**.

### The Flow:
1.  **Key Generaton**: KMS generates a Content Key (CEK).
2.  **CPIX Document**: Packager requests CEK via CPIX API.
3.  **Encryption**: Packager encrypts video segments using `AES-128-CBC` (HLS) or `AES-128-CTR` (DASH).
4.  **Signaling**: Manifest (`.m3u8`/`.mpd`) updated with `pssh` (Protection System Specific Header) boxes.

### DRM Security Levels (The "God Mode" of Access)

| DRM System | Security Level | Implementation | Hardware Requirement | Trust |
| :--- | :--- | :--- | :--- | :--- |
| **Widevine (Google)** | **L1** | **Hardware TEE** | ARM TrustZone / Secure Enclave | High (4K Allowed) |
| **Widevine** | **L3** | Software | None | Low (SD Only) |
| **FairPlay (Apple)** | **Hardware** | Secure Enclave | Apple A-Series / T2 Chips | High |
| **PlayReady (Microsoft)**| **SL3000** | Hardware TEE | TP/Intel SGX | High |

> [!WARNING]
> **Attack Vector**: "L1 Downgrade Attack". Hackers spoof L1 capability to force a 4K stream, then exploit a TEE vulnerability (rare but catastrophic) to dump raw frames.
> **Defense**: **HDCP 2.2 Link Enforcement**. Ensure the HDMI link to the monitor is also encrypted.

---

## 🕵️ Forensic Watermarking ("A/B Variant" Technique)

**Problem**: Client-side watermarking (JavaScript overlay) is easily removed by inspecting the DOM or modifying the shader.
**Solution**: Server-Side A/B Watermarking (The "Invisible Tracker").

### The Architecture
1.  **Pre-computation**: Encoder produces **two versions** of every video segment (Segment A and Segment B).
    *   **Segment A**: Watermarked with binary "0".
    *   **Segment B**: Watermarked with binary "1".
    *   *Note: The watermark is imperceptible (steganography in high-freq luma coefficients).*
2.  **Unique Playlist Generation**: Each user gets a **unique .m3u8** manifest.
    *   User 1 Pattern: A-B-A-A (0100)
    *   User 2 Pattern: B-B-A-B (1101)
3.  **Detection**: If a pirated stream is found, analyze the sequence of A/B segments to reconstruct the User ID.

**Benefits**:
*   **Zero Latency penalty** (pre-encoded).
*   **Unbreakable**: The watermark is burnt into the pixel data of the H.264/H.265 bitstream.

### Research Paper Reference
> *“A/B Watermarking for OTT Video Delivery: Architecture and Performance”* (Streaming Video Alliance Technical Paper).
> *“Robust Video Watermarking against H.264/AVC and HEVC Compression”* (IEEE Transactions).

---

## ☠️ Advanced Attack Scenarios & Mitigations

### 1. Token Theft / Replay
*   **Attack**: User extracts `?token=xyz` from browser network tab and shares it on Reddit.
*   **Defense**: **Token Binding (DPoP)**.
    *   Use **Demonstration of Proof-of-Possession (DPoP)** at the application layer.
    *   The token is bound to a private key held in the browser's `SubtleCrypto` (non-exportable).
    *   Each request includes a signature signed by that private key. The stolen token is useless without the private key.

### 2. CDM Emulation (The "Widevine Guesser")
*   **Attack**: Using a hacked CDM (Content Decryption Module) dll/so to intercept keys.
*   **Defense**: **VMP (Verified Media Path)**.
    *   Widevine requires the browser/CDM binary to be signed.
    *   **Server-Side**: Enable **Service Certificate** verification. The license server challenges the CDM to prove it's a genuine, unmodified binary before issuing keys.

### 3. HDMI Stripping
*   **Attack**: Cheap "HDMI Splitter" strips HDCP encryption, capturing raw 4K.
*   **Defense**: **Cinavia (Audio Watermark)**.
    *   Embeds watermarks in audio track.
    *   Consumer devices (TVs, Blu-ray players) detect Cinavia. If they hear the watermark but don't see the corresponding AACS/DRM handshake, they **mute the audio**.

---

## 📊 Principal Architect Checklist for Launch

1.  **Enforce HDCP 2.2**: For all 4K/UHD content. Fallback to SD if HDCP handshake fails.
2.  **License Rotation**: Rotate encryption keys every **15 minutes** (key rotation). Forces pirates to re-hack frequently.
3.  **Concurrency Limiting**: Implement Redis-backed "Heartbeat" service.
    *   Client sends heartbeat every 30s.
    *   If active_sessions > max_allowed, revoke oldest token.
4.  **Audit TEE Specs**: Don't just say "Widevine". Specify **Widevine L1** requirement for >> 720p.
5.  **A/B Watermarking**: If offering Premium Sports/Cinema, this is mandatory for leak tracing.

---

## 🧠 Relevant Research & Standards
*   **FIPS 140-2**: Security requirements for cryptographic modules (Level 3 required for Hardware DRMs).
*   **EBU R 143**: Cybersecurity for media organizations.
*   **Motion Picture Association (MPA) Content Security Best Practices**: The "Gold Standard" checklist for getting Hollywood content.
