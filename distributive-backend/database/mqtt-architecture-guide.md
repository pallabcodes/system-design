# MQTT Architecture: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / IoT Engineer
> **Scope**: QoS Internals, Broker Clustering, Session Management, MQTT 5.0 — Production Patterns

> [!CAUTION]
> **The Cardinal Sin**: Using MQTT for web backend microservices. MQTT is for **constrained devices over unreliable networks** (IoT, vehicles, satellites), not for Kubernetes pods.

---

## 📚 Required Reading

| Resource | Topic |
| :--- | :--- |
| [MQTT 5.0 Spec](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html) | Official protocol specification |
| [HiveMQ MQTT Essentials](https://www.hivemq.com/mqtt-essentials/) | Practical deep dive |
| [EMQX Architecture](https://www.emqx.io/docs/en/latest/design/overview.html) | Broker internals |

---

## 🎯 The Principal Laws of MQTT

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Constrained First** | Designed for 256KB RAM devices | Minimal packet overhead, simple state |
| **Law 2: Network Unreliability** | Assume packet loss, reconnects | QoS and persistent sessions |
| **Law 3: Broker is God** | All messages flow through broker | Broker must be highly available |
| **Law 4: Topics are Strings** | No schema enforcement | Wildcard subscription can overwhelm |

---

# Part 1: Protocol Internals

## 📦 Packet Structure

```
Fixed Header (1-5 bytes):
┌─────────────────────────────────────────────────┐
│ Packet Type (4 bits) │ Flags (4 bits)           │
├─────────────────────────────────────────────────┤
│ Remaining Length (1-4 bytes, variable)          │
└─────────────────────────────────────────────────┘

Remaining Length Encoding:
- Uses continuation bits (like protobuf varints)
- 1 byte: 0-127
- 2 bytes: 128-16,383
- 3 bytes: 16,384-2,097,151
- 4 bytes: 2,097,152-268,435,455 (~256MB max)
```

## ⚡ QoS Deep Dive

### QoS 0: At Most Once (Fire and Forget)
```
Publisher          Broker          Subscriber
    │                 │                 │
    │──PUBLISH (QoS0)►│                 │
    │                 │──PUBLISH────────►
    │                 │                 │
    
Packets: 1
Guarantees: None (message may be lost)
Use case: High-frequency telemetry where loss is acceptable
```

### QoS 1: At Least Once
```
Publisher          Broker          Subscriber
    │                 │                 │
    │──PUBLISH (QoS1)►│                 │
    │◄─────PUBACK─────│                 │
    │                 │──PUBLISH────────►
    │                 │◄─────PUBACK─────│
    
Packets: 2 per hop (4 total)
Guarantees: Delivery (may duplicate)
Danger: If PUBACK lost, publisher retries → duplicate
```

### QoS 2: Exactly Once
```
Publisher          Broker          Subscriber
    │                 │                 │
    │──PUBLISH (QoS2)►│                 │
    │◄─────PUBREC─────│                 │ (Received)
    │──PUBREL────────►│                 │ (Release)
    │◄─────PUBCOMP────│                 │ (Complete)
    │                 │                 │
    │                 │──PUBLISH────────►
    │                 │◄─────PUBREC─────│
    │                 │──PUBREL────────►│
    │                 │◄─────PUBCOMP────│
    
Packets: 4 per hop (8 total)
Guarantees: Exactly once delivery
Cost: 4x latency and bandwidth vs QoS 0
Use case: Payment triggers, critical commands
```

### QoS State Machine
```python
class QoS2State(Enum):
    NONE = 0
    PUBREC_PENDING = 1   # Waiting for PUBREC
    PUBREL_PENDING = 2   # Waiting for PUBCOMP
    COMPLETE = 3

class QoS2Publisher:
    def __init__(self):
        self.pending_messages: Dict[int, QoS2State] = {}
    
    def publish(self, topic: str, payload: bytes, packet_id: int):
        self.pending_messages[packet_id] = QoS2State.PUBREC_PENDING
        self._send_publish(topic, payload, packet_id, qos=2)
    
    def handle_pubrec(self, packet_id: int):
        if packet_id in self.pending_messages:
            self.pending_messages[packet_id] = QoS2State.PUBREL_PENDING
            self._send_pubrel(packet_id)
    
    def handle_pubcomp(self, packet_id: int):
        if packet_id in self.pending_messages:
            self.pending_messages[packet_id] = QoS2State.COMPLETE
            del self.pending_messages[packet_id]
    
    def recover_pending(self):
        """Called on reconnect to resume incomplete flows."""
        for packet_id, state in self.pending_messages.items():
            if state == QoS2State.PUBREC_PENDING:
                # Resend PUBLISH with DUP flag
                self._resend_publish(packet_id, dup=True)
            elif state == QoS2State.PUBREL_PENDING:
                # Resend PUBREL
                self._send_pubrel(packet_id)
```

---

# Part 2: Session Management

## 🔄 Persistent Sessions (Clean Session = False)

```python
class PersistentSession:
    """Broker stores this for each client."""
    
    client_id: str
    subscriptions: Dict[str, int]  # topic → QoS
    pending_qos1_qos2: List[Message]  # Unacknowledged messages
    pending_qos2_received: Set[int]  # Received but not released
    last_packet_id: int
    
    # MQTT 5.0 additions
    session_expiry_interval: int  # Seconds to keep session after disconnect
```

### Session Storage DDL (PostgreSQL)
```sql
CREATE TABLE mqtt_sessions (
    client_id VARCHAR(256) PRIMARY KEY,
    is_connected BOOLEAN DEFAULT false,
    connected_node VARCHAR(100),  -- Which broker node
    last_connected TIMESTAMPTZ,
    last_disconnected TIMESTAMPTZ,
    session_expiry_interval INT DEFAULT 0,  -- 0 = never expire
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE mqtt_subscriptions (
    client_id VARCHAR(256) NOT NULL REFERENCES mqtt_sessions(client_id),
    topic_filter VARCHAR(1024) NOT NULL,
    qos SMALLINT NOT NULL CHECK (qos BETWEEN 0 AND 2),
    no_local BOOLEAN DEFAULT false,      -- MQTT 5.0
    retain_as_published BOOLEAN DEFAULT false,
    retain_handling SMALLINT DEFAULT 0,
    PRIMARY KEY (client_id, topic_filter)
);

CREATE TABLE mqtt_pending_messages (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    client_id VARCHAR(256) NOT NULL REFERENCES mqtt_sessions(client_id),
    packet_id INT NOT NULL,
    topic VARCHAR(1024) NOT NULL,
    payload BYTEA NOT NULL,
    qos SMALLINT NOT NULL,
    state VARCHAR(20) NOT NULL,  -- 'pending', 'pubrec_sent', 'pubrel_sent'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (client_id, packet_id)
);

CREATE INDEX idx_pending_client ON mqtt_pending_messages(client_id);
```

## 📢 Last Will and Testament (LWT)

```json
// Connect packet includes LWT
{
  "clientId": "vehicle-12345",
  "cleanSession": false,
  "will": {
    "topic": "vehicles/12345/status",
    "payload": "{\"status\": \"offline\", \"lastSeen\": 1704067200}",
    "qos": 1,
    "retain": true
  },
  "keepAlive": 30
}
```

### How LWT Works
```
1. Client connects, declares will message
2. Broker stores will (not published yet)
3. Client working normally...
4. Client disconnects UNGRACEFULLY (no DISCONNECT packet)
5. Broker publishes will message
6. Other subscribers see "vehicle-12345 is offline"

Graceful disconnect:
- Client sends DISCONNECT packet
- Broker discards will (not published)
```

---

# Part 3: Broker Clustering

## 🏗️ EMQX Cluster Architecture

```
                    ┌─────────────────────────────┐
                    │      Load Balancer          │
                    │ (HAProxy / AWS NLB / ELB)   │
                    └─────────────┬───────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
   ┌────────┐                ┌────────┐                ┌────────┐
   │ EMQX 1 │◄──────────────►│ EMQX 2 │◄──────────────►│ EMQX 3 │
   └────────┘   Mnesia/Rlog  └────────┘   Mnesia/Rlog  └────────┘
        │                         │                         │
        └─────────────────────────┼─────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │     Session Store          │
                    │ (Built-in / External DB)   │
                    └───────────────────────────┘
```

### Routing Table Synchronization
```
When client subscribes to topic on EMQX-1:
1. EMQX-1 stores local subscription
2. EMQX-1 broadcasts to cluster: "EMQX-1 has subscriber for 'sensors/+/temp'"
3. EMQX-2, EMQX-3 update routing table

When client publishes to topic on EMQX-2:
1. EMQX-2 checks routing table
2. Finds EMQX-1 has subscriber
3. Forwards message to EMQX-1
4. EMQX-1 delivers to local subscriber
```

### emqx.conf (Cluster Configuration)
```hocon
cluster {
    name = emqx_cluster
    discovery_strategy = static
    static {
        seeds = ["emqx1@10.0.0.1", "emqx2@10.0.0.2", "emqx3@10.0.0.3"]
    }
    
    # or DNS-based discovery for Kubernetes
    # discovery_strategy = dns
    # dns {
    #     record_type = srv
    #     name = "emqx.default.svc.cluster.local"
    # }
}

node {
    name = "emqx1@10.0.0.1"
    cookie = "emqx_secret_cookie"  # Must be same across cluster
}

listeners.tcp.default {
    bind = "0.0.0.0:1883"
    max_connections = 1000000
    max_conn_rate = 10000
}

listeners.ssl.default {
    bind = "0.0.0.0:8883"
    ssl_options {
        certfile = "/etc/emqx/certs/server.crt"
        keyfile = "/etc/emqx/certs/server.key"
        cacertfile = "/etc/emqx/certs/ca.crt"
        verify = verify_peer
        fail_if_no_peer_cert = true
    }
}
```

---

# Part 4: MQTT 5.0 Features

## 📊 Key Improvements Over 3.1.1

| Feature | 3.1.1 | 5.0 | Use Case |
| :--- | :--- | :--- | :--- |
| **Reason Codes** | CONNACK only | All packets | Better debugging |
| **Session Expiry** | Clean=true/false | Interval (seconds) | Gradual cleanup |
| **Message Expiry** | None | Per-message | Time-sensitive data |
| **Topic Alias** | None | Short ID for topic | Reduce bandwidth |
| **Response Topic** | Manual | First-class | Request/Response |
| **Shared Subscriptions** | Broker-specific | Standard | Load balancing |
| **User Properties** | None | Key-value headers | Custom metadata |

## 🔄 Shared Subscriptions (Load Balancing)

```
Topic: $share/load-balanced-group/sensors/+/temperature

Clients:
- Worker-1 subscribes: $share/mygroup/sensors/+/temperature
- Worker-2 subscribes: $share/mygroup/sensors/+/temperature
- Worker-3 subscribes: $share/mygroup/sensors/+/temperature

Message arrives on sensors/room1/temperature:
- Broker delivers to ONLY ONE of Worker-1, Worker-2, or Worker-3
- Round-robin by default (strategy is broker-specific)
```

### Request/Response Pattern
```python
# Requester
def send_request(topic: str, payload: bytes, timeout: float) -> bytes:
    response_topic = f"responses/{uuid4()}"
    correlation_id = str(uuid4())
    
    # Subscribe to response
    client.subscribe(response_topic)
    
    # Publish request with response topic
    client.publish(
        topic,
        payload,
        properties=mqtt5.Properties(
            response_topic=response_topic,
            correlation_data=correlation_id.encode()
        )
    )
    
    # Wait for response
    response = wait_for_message(response_topic, correlation_id, timeout)
    client.unsubscribe(response_topic)
    return response

# Responder
def on_message(msg):
    response_topic = msg.properties.response_topic
    correlation_id = msg.properties.correlation_data
    
    # Process and respond
    result = process(msg.payload)
    
    client.publish(
        response_topic,
        result,
        properties=mqtt5.Properties(
            correlation_data=correlation_id
        )
    )
```

---

# Part 5: Security

## 🔐 Authentication Methods

| Method | How | Security | Use Case |
| :--- | :--- | :--- | :--- |
| **Username/Password** | CONNECT packet | Weak (unless TLS) | Simple setups |
| **X.509 Client Cert** | TLS handshake | Strong | Production IoT |
| **JWT Token** | Password field | Strong | Cloud integration |
| **MQTT 5.0 Enhanced Auth** | Multi-step | Very Strong | SCRAM, OAuth |

### Client Certificate Authentication (EMQX)
```hocon
authentication = [
    {
        mechanism = password_based
        backend = built_in_database
        enable = false
    },
    {
        mechanism = x509_client_cert
        enable = true
        ssl_options {
            verify = verify_peer
            fail_if_no_peer_cert = true
        }
        # Extract client_id from certificate CN
        principal {
            cn = "${cert_common_name}"
        }
    }
]
```

### Topic-Level ACL
```hocon
authorization {
    sources = [
        {
            type = file
            enable = true
            path = "/etc/emqx/acl.conf"
        }
    ]
    
    no_match = deny
    deny_action = disconnect
}

# /etc/emqx/acl.conf
# Device can only publish/subscribe to its own topics
{allow, {user, "device-*"}, publish, ["devices/${username}/#"]}.
{allow, {user, "device-*"}, subscribe, ["devices/${username}/#"]}.
{allow, {user, "device-*"}, subscribe, ["commands/${username}/#"]}.
{deny, all}.
```

---

# Part 6: Production Patterns

## 📊 Monitoring Metrics

```yaml
# Prometheus metrics to track
groups:
  - name: mqtt_broker
    rules:
      - alert: MQTTConnectionsHigh
        expr: emqx_connections_count > 900000
        for: 5m
        annotations:
          summary: "Near max connections (1M limit)"
      
      - alert: MQTTMessageQueueBacklog
        expr: emqx_messages_qos1_pending + emqx_messages_qos2_pending > 100000
        for: 1m
        annotations:
          summary: "QoS 1/2 message backlog growing"
      
      - alert: MQTTSubscriptionFlood
        expr: rate(emqx_subscriptions_total[1m]) > 10000
        for: 1m
        annotations:
          summary: "Abnormal subscription rate (possible attack)"
      
      - alert: MQTTRetainedMessages
        expr: emqx_retained_count > 50000
        annotations:
          summary: "Too many retained messages (memory pressure)"
```

## 🔧 Client Best Practices

```python
import paho.mqtt.client as mqtt
from backoff import expo, on_exception

class RobustMQTTClient:
    def __init__(self, client_id: str, broker: str, port: int = 8883):
        self.client = mqtt.Client(client_id=client_id, protocol=mqtt.MQTTv5)
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.client.on_message = self._on_message
        
        # TLS
        self.client.tls_set(
            ca_certs="/path/to/ca.crt",
            certfile="/path/to/client.crt",
            keyfile="/path/to/client.key"
        )
        
        # Last Will
        self.client.will_set(
            topic=f"devices/{client_id}/status",
            payload='{"status": "offline"}',
            qos=1,
            retain=True
        )
        
        self.broker = broker
        self.port = port
    
    @on_exception(expo, Exception, max_tries=10)
    def connect(self):
        self.client.connect(self.broker, self.port, keepalive=30)
        self.client.loop_start()
    
    def _on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code == 0:
            # Resubscribe on reconnect (clean_session=False handles pending msgs)
            client.subscribe("commands/+/#", qos=1)
    
    def _on_disconnect(self, client, userdata, reason_code, properties):
        logging.warning(f"Disconnected: {reason_code}")
        # Paho auto-reconnects if loop_start() is used
    
    def publish_with_retry(self, topic: str, payload: bytes, qos: int = 1):
        result = self.client.publish(topic, payload, qos=qos)
        result.wait_for_publish(timeout=10)
        if not result.is_published():
            raise PublishFailed(f"Failed to publish to {topic}")
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | TLS 1.2+ for all connections | Port 8883, not 1883 |
| 2 | Client certificates for production | Not username/password |
| 3 | ACLs per device/topic | Deny by default |
| 4 | QoS 2 only for critical messages | Monitor QoS2 percentage |
| 5 | Session expiry configured | Not infinite |
| 6 | LWT for all persistent devices | Monitor offline notifications |
| 7 | Shared subscriptions for workers | Load-balanced consumers |
| 8 | Broker cluster with 3+ nodes | Test node failure |

---

## 🔗 Related Documents
*   [GIS Architecture](./gis-architecture-guide.md) — GPS tracking over MQTT.
*   [TSDB Architecture](./tsdb-architecture-guide.md) — Storing MQTT sensor data.
*   [Saga Pattern](./saga/saga-pattern-guide.md) — Command/response over MQTT.
