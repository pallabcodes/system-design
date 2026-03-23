# Pre-Call Testing: The Critical Success Factor

> **Source**: [WebRTC Pre-Call Tests](https://youtu.be/FYtLFxpWlwM)

> [!IMPORTANT]
> **The Insight**: Pre-call tests are the **#1 feature** for reducing support tickets.
> **The ROI**: $10k implementation saves $50k+/year in support costs.

---

## 💥 Why WebRTC Calls Fail

### Controllable Factors (30%)
*   **Poor signaling** (slow WebSocket).
*   **No TURN fallback** (firewalls block UDP).
*   **Missing auto-reconnect**.

### Uncontrollable Factors (70%)
*   **User's internet** (coffee shop Wi-Fi = 5 Mbps).
*   **Faulty hardware** (2014 webcam).
*   **Network restrictions** (corporate firewall blocks WebRTC).

**Insight**: Since 70% is uncontrollable, **educate users before they join**.

---

## 🧪 The 7 Components of a Pre-Call Test

### 1. Device Selection
**Purpose**: Let users choose camera/microphone.

```javascript
navigator.mediaDevices.enumerateDevices().then(devices => {
  const cameras = devices.filter(d => d.kind === 'videoinput');
  // Populate dropdown
  cameras.forEach(c => dropdown.add(new Option(c.label, c.deviceId)));
});
```

---

### 2. Visual Preview
**Purpose**: User sees themselves (confirms correct camera).

```html
<video id="preview" autoplay playsinline muted></video>
```

**Insight**: If user sees themselves upside down, they know to rotate iPad.

---

### 3. Audio Level Indicator
**Purpose**: Confirm microphone is working.

**Implementation**:
```javascript
const audioContext = new AudioContext();
const analyser = audioContext.createAnalyser();

navigator.mediaDevices.getUserMedia({ audio: true }).then(stream => {
  const source = audioContext.createMediaStreamSource(stream);
  source.connect(analyser);
  
  const dataArray = new Uint8Array(analyser.frequencyBinCount);
  function checkVolume() {
    analyser.getByteFrequencyData(dataArray);
    const volume = dataArray.reduce((a, b) => a + b) / data Array.length;
    // Show blue bar bouncing to `volume` level
    volumeBar.style.height = `${volume}%`;
    requestAnimationFrame(checkVolume);
  }
  checkVolume();
});
```

---

### 4. Connectivity Check
**Purpose**: Test if app can reach media servers.

**Test**:
```javascript
fetch('https://api.vonage.com/health')
  .then(res => {
    if (res.ok) showMessage('✅ Connection to Vonage: Excellent');
    else showMessage('❌ Cannot reach servers. Check firewall.');
  });
```

---

### 5. Bandwidth Test
**Purpose**: Estimate upload/download speed.

**Commercial Tool**: testRTC, Twilio Network Quality API.
**DIY**: Upload 1 MB file, measure time.

**Result**:
*   **<1 Mbps**: "Fair - Audio only recommended"
*   **1-5 Mbps**: "Good - Video at 480p"
*   **>5 Mbps**: "Excellent - HD video supported"

---

### 6. User Recommendations
**Based on test results**:
*   **Low bandwidth** → "Turn off camera to save bandwidth"
*   **Firewall detected** → "Switch from Guest Wi-Fi to Corporate Network"
*   **Old browser** → "Upgrade to Chrome 120+"

---

### 7. Data Logging (Support Evidence)
**Store for every call attempt**:
```json
{
  "userId": "user123",
  "timestamp": "2026-01-10T15:00:00Z",
  "bandwidth": { "upload": "2.5 Mbps", "download": "10 Mbps" },
  "devices": { "camera": "FaceTime HD", "mic": "Built-in" },
  "browser": "Chrome 120",
  "errors": ["TURN_REQUIRED", "LOW_BANDWIDTH"]
}
```

**Use Case**: User complains → Support checks logs → "Your upload was 0.5 Mbps (minimum is 2 Mbps)."

---

## 🛠️ Implementation Options

### Option 1: CPaaS Built-in
| Vendor | Tool | Features |
| :--- | :--- | :--- |
| **Twilio** | Network Quality API | 1-5 bars (like cell signal) |
| **Vonage** | Pre-Call Test Wrapper | Camera, mic, bandwidth, connectivity |
| **Daily** | `getDailyCallQuality()` | Real-time stats |

**Effort**: 1-2 days (API integration).

---

### Option 2: DIY (Open-Source)
**Tool**: [test.webrtc.org](https://test.webrtc.org)

**Features**:
*   Camera resolution test.
*   Microphone test.
*   Bandwidth test (upload/download).
*   Connectivity test (STUN/TURN).

**Effort**: Redirect users to this site. Zero code.

---

### Option 3: Custom Build
**Libraries**:
*   **WebRTC Diagnostics**: [webrtc-diagnostics](https://github.com/webrtc/samples).
*   **Bandwidth Test**: [speedtest-net](https://github.com/ddsol/speedtest.net).

**Effort**: 1-2 weeks (custom UI + logging).

---

## 📊 ROI Analysis

### Scenario: Telehealth App (10k Calls/Month)

**Before Pre-Call Test**:
*   **Support Tickets**: 500/month (5% of calls fail).
*   **Cost**: 500 * $20/ticket = **$10k/month**.

**After Pre-Call Test**:
*   **Failures Prevented**: 300/month (users fix issues before joining).
*   **Remaining Tickets**: 200/month.
*   **Cost**: 200 * $20/ticket = **$4k/month**.

**Savings**: $6k/month = **$72k/year**.

**Implementation Cost**: $10k (1-2 weeks of dev).

**ROI**: 720% in Year 1.

---

## ✅ Principal Architect Checklist

1.  **Implement Pre-Call Test for Production Apps**: Not optional. It's the #1 support cost reducer.
2.  **Store Test Results**: Log bandwidth, devices, errors for every call. Saves hours of debugging.
3.  **Use Qualitative Labels**: Don't show "2.5 Mbps". Show "Good quality expected".
4.  **Force Settings When Needed**: If bandwidth <1 Mbps, **disable video automatically**.

---

## 🔗 Related Documents
*   [WebRTC Production Challenges](./webrtc-production-challenges-guide.md) — NAT/TURN issues.
*   [WebRTC Production Readiness](./webrtc-production-readiness-guide.md) — Safari testing.
