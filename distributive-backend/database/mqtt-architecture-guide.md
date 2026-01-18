# MQTT: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: IoT Messaging, QoS Levels, Broker Architecture, and Security.

> [!IMPORTANT]
> **The Principal Rule**: MQTT is designed for **constrained devices** over **unreliable networks**.
> **The Use Case**: Battery-powered sensors, satellites, cars, smart homes. NOT for web backends.

---

## 🎯 When Exactly MQTT?

### The Decision Matrix

| Scenario | Use MQTT? | Why? |
| :--- | :---: | :--- |
| **IoT Sensors** (Temperature, GPS) | ✅ Yes | Low power, small packets, QoS. |
| **Connected Cars** (Ford, Tesla) | ✅ Yes | Intermittent connectivity, last will. |
| **Smart Home** (Alexa, Hue) | ✅ Yes | Lightweight, Pub/Sub. |
| **Web Backend Microservices** | ❌ No | Use Kafka, RabbitMQ, gRPC. |
| **Real-Time Gaming** | ❌ No | Use WebSocket/WebRTC (lower latency). |

### MQTT vs WebSocket vs Kafka

| Factor | MQTT | WebSocket | Kafka |
| :--- | :--- | :--- | :--- |
| **Designed For** | IoT / Constrained Devices | Browser ↔ Server | Backend Stream Processing |
| **Message Size** | Bytes to KB | KB to MB | KB to GB |
| **QoS Guarantees** | ✅ 0, 1, 2 | ❌ None | ✅ At-Least-Once |
| **Retained Messages** | ✅ Yes | ❌ No | ✅ Log Retention |
| **Last Will Testament** | ✅ Yes | ❌ No | ❌ No |
| **Connection Overhead** | Low (Keep-Alive) | Medium (HTTP Upgrade) | High (TCP) |

---

## 🧠 God Mode: QoS Levels

The killer feature of MQTT. Choose your delivery guarantee.

| QoS Level | Name | Behavior | Use Case |
| :--- | :--- | :--- | :--- |
| **0** | At Most Once | Fire and forget. No ACK. May lose message. | Sensor telemetry (Loss OK). |
| **1** | At Least Once | Broker ACKs. Retry until ACK. May duplicate. | Commands (Idempotent OK). |
| **2** | Exactly Once | 4-way handshake. No loss, no duplicates. | Payments, Critical Actions. |

> [!WARNING]
> **QoS 2 is expensive.** It requires 4 packets per message. Use only when duplication is catastrophic.

---

## 🏗️ Broker Architecture

```mermaid
graph TD
    subgraph "Device Network"
        Sensor1[Sensor 1] -->|MQTT 3.1.1| Broker[MQTT Broker]
        Sensor2[Sensor 2] --> Broker
        Car[Connected Car] --> Broker
    end
    
    Broker -->|MQTT Bridge| Cloud[Cloud Broker (AWS IoT)]
    Cloud --> Lambda[Lambda (Process)]
    Cloud --> S3[(S3 Archive)]
    
    subgraph "Broker Internals"
        Broker --> SessionDB[(Session DB)]
        Broker --> MsgStore[(Message Store)]
    end
```

### Popular Brokers

| Broker | Best For | Notes |
| :--- | :--- | :--- |
| **Mosquitto** | Prototyping / Small Scale | Open source, single node. |
| **EMQX** | Enterprise / High Scale | Clustering, millions of connections. |
| **HiveMQ** | Enterprise | Kubernetes native, extensions. |
| **AWS IoT Core** | Serverless | Managed, integrates with Lambda/S3. |
| **VerneMQ** | High Availability | Clustering, MQTT 5.0. |

---

## 🔒 Security

### 1. TLS (Transport Layer Security)
*   Always use TLS 1.2+. MQTT default port is `1883` (unencrypted). Use `8883` for TLS.

### 2. Authentication
*   **Username/Password**: Simple but weak.
*   **X.509 Certificates**: Each device has a client certificate. Best for production.
*   **OAuth 2.0 / JWT**: Modern brokers (HiveMQ) support token-based auth.

### 3. Authorization (ACLs)
*   **Topic-Level ACLs**: `sensor/+/temperature` allows subscribing to any sensor's temperature but not `command/+/restart`.

---

## ✅ Principal Architect Checklist

1.  **Use Wildcard Topics Carefully**: `#` (multi-level) can overwhelm a client if misused.
2.  **Set Clean Session = False for Persistence**: The broker stores messages while the device is offline.
3.  **Use Last Will and Testament (LWT)**: Broker publishes a "device offline" message if the connection drops unexpectedly.
4.  **Monitor Connection Counts**: A poorly coded device that reconnects in a loop can DDoS your broker.
5.  **Use MQTT 5.0**: Adds shared subscriptions (load balancing), reason codes, and properties.

---

## 🔗 Related Documents
*   [VMS Architecture](../video-streaming/vms-architecture-guide.md) — MQTT for camera alerts.
*   [Event-Driven Architecture](./event-driven-architecture-guide.md) — MQTT as an event source.
