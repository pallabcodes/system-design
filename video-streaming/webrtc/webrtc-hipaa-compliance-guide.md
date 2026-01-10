# HIPAA Compliant WebRTC Architecture

> **Source**: [HIPAA for Video Developers](https://youtu.be/zsiYgTmbEH0)

> [!IMPORTANT]
> **The Myth**: "I used Twilio, so I am HIPAA compliant."
> **The Reality**: Compliance is a shared responsibility. Using a compliant vendor (BAA) only covers the *infrastructure*. You are liable for the *application logic*.

---

## 🏛️ 1. The Legal Stack (BAA Inheritance)
You cannot build a compliant app on non-compliant infrastructure.

### The Chain of Trust
1.  **Cloud Provider (AWS/GCP)**: Must sign a BAA. You must use "Dedicated Instances" or specific services covered by their BAA (e.g., S3 is covered, standard EC2 is, but spot instances might have caveats).
2.  **CPaaS (Twilio/Vonage)**: Must sign a BAA.
    *   **Caveat**: Most "Pay-as-you-go" tiers DO NOT sign BAAs. You usually need an "Enterprise" contract ($$) to get the BAA.
3.  **Your Service**: You sign a BAA with the Hospital/Doctor.

> **Warning**: If you use a generic TURN server or a cheap signaling host that won't sign a BAA, your entire stack is non-compliant.

---

## 🔒 2. Technical Implementation: The "Zero-PII" Signaling

WebRTC media is encrypted (SRTP). Signaling is the leak risk.

### The Metadata Trap
Developers often casually pass metadata in the signaling layer.
*   **BAD**: `connect({ room: "Dr-Smith-Patient-JohnDoe" })`
    *   The Signal Server logs this. The Logs are now PHI (Protected Health Information).
*   **GOOD**: `connect({ room: "UUID-5829-1029" })`
    *   Map UUIDs to Patients in your secure, encrypted database. The Signal Server never sees the name.

### No PII in URLs
*   **BAD**: `https://telehealth.com/room?patient=John`
    *   Browser History, Proxy Logs, and ISP Logs effectively breach confidentiality.
*   **GOOD**: `https://telehealth.com/room/UUID` + JWT Auth Header.

---

## 🎥 3. Media & Storage Architecture

### E2EE vs Hop-by-Hop
*   **Is E2EE Required?** No. HIPAA requires encryption "In Transit" (DTLS/SRTP covers this) and "At Rest".
*   **Standard SFU**: Decrypting at the server *is legal* under HIPAA as long as the server is secure and covered by a BAA.
*   **Why avoid E2EE?**: It breaks Cloud Recording and Transcriptions, which are often legally required for medical records.

### Secure Recording Storage (AWS S3)
If you record the session:
1.  **Encryption at Rest**: Enable **AWS KMS (Key Management Service)**.
2.  **Lifecycle Policy**: Delete recordings automatically after X years (Retention Policy).
3.  **Access Logs**: Enable S3 Server Access Logging. You must know *exactly* which admin downloaded the video file.

---

## 🛡️ 4. Audit Trails (The "Who Watched What" Log)

HIPAA requires you to track **Access**.

### Required Logs (Database)
| Event | Metadata | Why? |
| :--- | :--- | :--- |
| **Nurse Joined** | `Timestamp`, `NurseID`, `RoomID`, `IP` | Proof of authorization. |
| **Stream Start** | `Timestamp`, `MediaSessionID` | Proof service was delivered. |
| **Admin View** | `AdminID`, `Reason` | **Break-Glass**: If an admin views a live stream for debugging, they must document *why*. |

> **Tech Tip**: Ship these logs to a "Write-Only" archive (e.g., AWS Glacier Vault Lock) so even a rogue admin cannot modify the history.

---

## ✅ Principal Architect Checklist

1.  **Get the BAA First**: Don't write code until Twilio/AWS confirms they will sign.
2.  **Sanitize Logs**: Configure your SFU/Signaling server to **Disable** Verbose Logging in production. A debug log showing "Offering video to IP 1.2.3.4" is PII.
3.  **Ephemeral Tokens**: Use JWTs with short expiry (5 mins) for room access. Do not store long-lived keys in the browser.
4.  **Disconnect Protocol**: If the patient closes the tab, the doctor must be disconnected. Don't leave a "hot mic" room open.

---

## 🔗 Related Documents
*   [WebRTC Recording](./webrtc-recording-guide.md) — Compliance storage costs.
*   [Growth Playbook](./webrtc-growth-playbook-guide.md) — When to upgrade to Enterprise CPaaS plans.
