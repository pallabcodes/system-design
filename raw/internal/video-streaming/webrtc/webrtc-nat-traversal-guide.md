# WebRTC NAT Traversal Architecture: ICE, STUN, & TURN

> **Source**: [STUN & TURN Explained](https://youtu.be/N5cqu0kTIsw)

> [!IMPORTANT]
> **The Reality**: 20% of calls fail without TURN. 5% fail *even with* Standard TURN.
> **The Goal**: 100% Connectivity via Multipath ICE and Protocol Fallbacks.

---

## 🧊 1. The Anatomy of ICE (Interactive Connectivity Establishment)

ICE is the logic that finds the "best path" through the internet maze.
It gathers **Candidates**:
1.  **Host**: Direct LAN IP (e.g., `192.168.1.5`). Fast but useless over internet.
2.  **Srflx (Server Reflexive)**: Public IP discovered via **STUN** (UDP).
3.  **Relay**: Proxy IP via **TURN** (UDP/TCP/TLS).

### The "Symmetric NAT" Problem
STUN works for "Cone NAT" (Home Routers). It fails for "Symmetric NAT" (Enterprise Firewalls).
*   **Cone NAT**: Internal `IP:Port` maps to same Public `IP:Port` for all destinations.
*   **Symmetric NAT**: Internal `IP:Port` maps to *different* Public `IP:Ports` depending on destination.
*   **Result**: P2P fails. You *must* use TURN.

---

## 🛡️ 2. TURN Architecture at Scale

### Protocol Waterfall (Latency vs Reachability)
Your ICE agent should try candidates in this order:

| Protocol | Latency | Success Rate | Cost |
| :--- | :--- | :--- | :--- |
| **UDP P2P (STUN)** | 🟢 50ms | 🟡 80% | 🟢 $0 |
| **UDP Relay (TURN)** | 🟡 70ms | 🟢 90% | 🔴 $0.09/GB |
| **TCP Relay (TURN)** | 🔴 100ms+ | 🟢 95% | 🔴 $0.09/GB |
| **TLS Relay (TURNS)** | 🔴 120ms+ | 🟢 100% | 🔴 High CPU |

### The "3478" Trap
*   **Standard Port**: 3478.
*   **Problem**: Strict firewalls block non-HTTP ports.
*   **Solution**: Run TURN on Port 443.
    *   **Caveat**: If you also run a web server on the same IP, you need a multiplexer (like `nginx` stream module or `coturn`'s built-in support) to distinguish Traffic.

---

## 🔒 3. Security: "TURNS" and DPI Evasion

**Deep Packet Inspection (DPI)** can see "This packet on port 443 looks like UDP/RTP, not HTTP. Block it."

### The Solution: `turns:` (TURN over TLS)
*   **Mechanism**: The client wraps the TURN packet inside a standard TLS envelope.
*   **Firewall View**: Sees an encrypted SSL connection to port 443. Looks like Gmail or Salesforce.
*   **Performance Hit**: Double encryption.
    *   WebRTC encrypts media (SRTP).
    *   TURN encrypts tunnel (TLS).
    *   **Result**: Higher CPU load on the TURN server.

### Authentication: Ephemeral Credentials
To prevent bandwidth theft (people using your TURN server for their torrents):
1.  **Secret**: Shared secret between App Server and TURN Server.
2.  **Generate**: User requests creds.
    ```javascript
    username = timestamp + ":" + userid;
    password = HMAC_SHA1(secret, username);
    ```
3.  **Validate**: TURN server checks if `timestamp` is recent.

---

## 🏗️ 4. Geo-Distribution Strategy

Users connect to the *closest* TURN server, but that server might need to talk to a distant peer.

**Topology**:
*   **User A (Tokyo)** -> TURN (Tokyo).
*   **User B (NY)**.
*   **Path**: User A -> TURN (Tokyo) -> Public Internet -> User B.
    *   **Better**: User A -> TURN (Tokyo) -> **Fiber Backbone** -> TURN (NY) -> User B. (Requires "Cloud Relay" or cascading).

---

## ✅ Principal Architect Checklist

1.  **Enable IPv6**: Many mobile networks are IPv6-only. NAT64/DNS64 handles translation, but native IPv6 STUN/TURN is faster (no NAT).
2.  **Audit Candidate List**: Don't send 20 candidates. It slows down connection time. Filter out useless local interfaces (e.g., VPN virtual adapters).
3.  **Monitor "Relay %"**: If >30% of your calls use TURN, check your STUN config. You might be failing P2P unnecessarily.
4.  **Test with "Tricolize"**: Use Trickle ICE tools to verify your `turns:` endpoint actually bypasses firewalls.

---

## 🔗 Related Documents
*   [WebRTC Scaling](./webrtc-scaling-architecture-guide.md) — Cost impact of TURN.
*   [WebRTC Troubleshooting](./webrtc-debugging-guide.md) — ICE error codes.
