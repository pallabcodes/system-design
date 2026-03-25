# WebRTC Automated Testing Strategy

> **Source**: [Automated Testing for Real-Time Apps](https://youtu.be/rjWHwMZSXYk)

> [!IMPORTANT]
> **The Challenge**: Testing video is 10x harder than standard web apps (non-deterministic, hardware dependency).
> **The Goal**: Detect **service deterioration** (quality regression) before users do.

---

## 🏗️ The Testing Pyramid (WebRTC Edition)

### 1. Unit Tests (Fast & Isolated)
*   **Scope**: Individual functions/classes (e.g., SDP parsing logic, state machine transitions).
*   **Dependencies**: Mock everything (Signaling, PeerConnection, MediaDevices).
*   **Tools**: Jest (JS), XCode Unit Tests (iOS), JUnit (Android).
*   **Frequency**: Every commit.

### 2. Integration Tests (End-to-End)
*   **Scope**: Full user flows (Login → Join Room → Verify Connected).
*   **Challenge**: "Bleeding Tests" (one test corrupts DB state for next test).
*   **Solution**: Strict resource allocation/cleanup per test.
*   **Tools**: WebDriverIO, Selenium, Appium (Mobile).

### 3. Load Testing (Stress)
*   **Scope**: Infrastructure limits (SFU capacity, scaling triggers).
*   **Metric**: "At what user count does video latency exceed 500ms?"
*   **Tools**: JMeter, TestRTC, K6 (with WebRTC extensions).

---

## 🔍 Verification: How to "See" Video in Code?

Automated tests can't "watch" video easily. Use these proxies:

### Method 1: `getStats()` (The Truth Source)
Programmatically check if bytes are flowing.

```javascript
// Check every 1 second
const stats = await pc.getStats();
let bytesSent = 0;

stats.forEach(report => {
  if (report.type === 'outbound-rtp' && report.mediaType === 'video') {
    bytesSent = report.bytesSent;
  }
});

expect(bytesSent).toBeGreaterThan(0); // Basic check
```

### Method 2: Fake Media & Screenshot Diff
1.  Launch Chrome with `--use-fake-device-for-media-stream`.
2.  Browser sends a generated "spinning pattern".
3.  Test takes screenshot of `<video>` element.
4.  Compare screenshot against "golden master" image.

### Method 3: MOS (Mean Opinion Score)
Calculate a synthetic quality score (1-5) based on stats:
*   **Packet Loss**: < 2%
*   **Jitter**: < 30ms
*   **RTT**: < 100ms

**Formula**:
```javascript
if (packetLoss > 5%) score = 1;
else if (rtt > 400ms) score = 2;
else score = 4.5;
```

---

## 🛠️ Infrastructure & Tools

### CI/CD Pipeline
```mermaid
graph LR
    Dev[Developer Push] --> CI[CI Server]
    CI --> Unit[Unit Tests]
    Unit --> Integration[Integration Tests (Headless Chrome)]
    Integration -->|Success| CD[Deploy to Staging]
    
    subgraph "Nightly Schedule"
        Load[Load Tests (1000 Users)]
    end
```

### The Toolbelt

| Tool | Type | Best For |
| :--- | :--- | :--- |
| **WebDriverIO** | Framework | Browser automation (Chrome/Firefox) |
| **Kite** | Engine | Interoperability testing (Matrix: Chrome vs Safari) |
| **TestRTC** | Service | Managed load testing & network simulation |
| **Appium** | Framework | Mobile automation (iOS/Android) |
| **tc (Linux)** | Utility | Simulating packet loss/throttling (Network conditioning) |

---

## ⚠️ Challenges & Workarounds

### 1. Two-Factor / Authentication
**Problem**: Test bots can't read SMS codes.
**Solution**: Use "Test User" accounts with static OTPs or bypass tokens in Staging.

### 2. UDP Blocking
**Problem**: CI servers (CircleCI, GitHub Actions) often block outbound UDP.
**Solution**:
1.  Force TCP (TURN-TCP).
2.  Use specialized runners (AWS EC2) with open UDP ports.

### 3. "Bleeding Tests"
**Problem**: Test A joins room "Review", Test B tries to create room "Review" → Collision.
**Solution**: Generate UUIDs for every test resource.
```javascript
const roomId = `test-room-${uuidv4()}`;
await createRoom(roomId);
```

---

## 🕵️ The Role of Manual Testing
Automation cannot catch:
*   "Weird noise" from specific microphone hardware.
*   UX "feeling" (jankiness vs smoothness).
*   Edge case interactions (plugging in headset mid-call).

**Rule**: Automate the "Happy Path" (80%). Manual test the "Edge Cases" (20%).

---

## ✅ Principal Architect Checklist

1.  **Enforce Unit Tests**: Mock PeerConnection to test signaling logic thoroughly.
2.  **Use Fake Media**: Always run CI with `--use-fake-device-for-media-stream` (deterministic).
3.  **Monitor "Time to Connect"**: Fail test if P2P connection takes >2 seconds.
4.  **Scheduled Load Tests**: Run nightly stress tests to catch memory leaks or performance regressions.
5.  **Calculate MOS**: Don't just check "is connected", check "is quality good".

---

## 🔗 Related Documents
*   [WebRTC Debugging](./webrtc-debugging-guide.md) — Tools for manual debugging.
*   [Pre-Call Testing](./webrtc-precall-testing-guide.md) — Client-side diagnostics.
