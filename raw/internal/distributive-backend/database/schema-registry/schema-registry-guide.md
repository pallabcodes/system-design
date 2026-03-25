# Schema Registry: The Google Principal Architect Guide

> **Level**: Google L6+ / Principal Architect / Staff+ Data Engineer
> **Scope**: Avro/Protobuf Schema Evolution, Compatibility Rules, Registry Architecture — Production Patterns

> [!CAUTION]
> **The Cardinal Sin**: Deploying schema changes without compatibility checks. One breaking change → consumers crash → data pipeline down → revenue lost.

---

## 📚 Required Reading

| Resource | Topic |
| :--- | :--- |
| [Confluent Schema Registry](https://docs.confluent.io/platform/current/schema-registry/index.html) | Industry standard |
| [Avro Specification](https://avro.apache.org/docs/current/spec.html) | Schema evolution rules |
| [Protocol Buffers](https://developers.google.com/protocol-buffers/docs/proto3) | Google's format |

---

## 🎯 The Principal Laws of Schema Management

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Schema is Contract** | Producers and consumers agree on structure | Breaking contract breaks integration |
| **Law 2: Evolution is Inevitable** | Business requirements change | Plan for backward/forward compatibility |
| **Law 3: Registry is Critical Path** | New producers/consumers need schema | Must be highly available |
| **Law 4: ID Over Schema** | Message contains ID, not full schema | Schema fetch happens at startup |

---

# Part 1: Why Schema Registry?

## 💀 The Problem Without Registry

```
Producer App                           Consumer App
 (Java)                                  (Python)
    │                                       │
    │ serialize(User)                       │
    ▼                                       ▼
┌─────────────┐                      ┌─────────────┐
│ Raw Bytes:  │──────Kafka─────────► │ How to      │
│ 0x4A6F686E..│                      │ deserialize?│
└─────────────┘                      └─────────────┘
                                           │
                                      ??? ERROR!

Options without registry:
1. Embed full schema in every message (huge overhead)
2. Share schema files via git (versioning nightmare)
3. Self-describing format like JSON (no evolution rules)
```

## ✅ The Solution: Centralized Registry

```
┌────────────────────────────────────────────────────────────────┐
│                      Schema Registry                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Subject: user-value                                      │   │
│  │ Version 1: {name: string, email: string}                │   │
│  │ Version 2: {name: string, email: string, age: int?}     │   │
│  │ Version 3: ...                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Subject: order-value                                     │   │
│  │ Version 1: {orderId: string, amount: decimal}           │   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
        │                                      │
        │ GET /schemas/ids/42                  │ POST /subjects/user/versions
        ▼                                      ▼
┌─────────────┐                         ┌─────────────┐
│ Consumer    │                         │ Producer    │
│ (startup)   │                         │ (startup)   │
└─────────────┘                         └─────────────┘
```

### Wire Format (Confluent)
```
Message:
┌────────────────────────────────────────────┐
│ Magic Byte │ Schema ID │ Avro Payload       │
│ (1 byte)   │ (4 bytes) │ (variable)         │
│ 0x00       │ 0x0000002A│ 0x4A6F686E...      │
└────────────────────────────────────────────┘

Total overhead: 5 bytes per message
vs. embedding full schema: 500+ bytes
```

---

# Part 2: Schema Evolution

## 🔄 Compatibility Modes

| Mode | Rule | When to Use |
| :--- | :--- | :--- |
| **BACKWARD** | New schema can read old data | Default. Deploy consumers first. |
| **FORWARD** | Old schema can read new data | Deploy producers first. |
| **FULL** | Both directions | Strictest. Most flexible deployment. |
| **NONE** | No checks | Testing only. Never in prod. |
| **BACKWARD_TRANSITIVE** | BACKWARD across all versions | Long-running consumers |
| **FORWARD_TRANSITIVE** | FORWARD across all versions | Long-running producers |
| **FULL_TRANSITIVE** | FULL across all versions | Maximum safety |

## 📋 Safe vs Breaking Changes

### Adding Fields (Safe if Optional)
```avro
// Version 1
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "email", "type": "string"}
  ]
}

// Version 2 - BACKWARD COMPATIBLE
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "email", "type": "string"},
    {"name": "age", "type": ["null", "int"], "default": null}  // Optional with default
  ]
}

// Old consumer reads v2 data: age field is ignored
// New consumer reads v1 data: age defaults to null
```

### Removing Fields (Safe if Optional)
```avro
// Version 1
{
  "fields": [
    {"name": "firstName", "type": "string"},
    {"name": "middleName", "type": ["null", "string"], "default": null},  // Optional
    {"name": "lastName", "type": "string"}
  ]
}

// Version 2 - FORWARD COMPATIBLE (old readers can read new data)
{
  "fields": [
    {"name": "firstName", "type": "string"},
    // middleName removed
    {"name": "lastName", "type": "string"}
  ]
}

// Old consumer reads v2 data: uses default for missing middleName
```

### Breaking Changes (ALWAYS AVOID)
```avro
// ❌ Renaming a field
{"name": "email"} → {"name": "emailAddress"}

// ❌ Changing field type (incompatible)
{"name": "age", "type": "int"} → {"name": "age", "type": "string"}

// ❌ Removing required field without default
{"name": "id", "type": "string"}  // Cannot remove

// ❌ Adding required field without default
{"name": "newField", "type": "string"}  // Must have default
```

### Safe Evolution Checklist
```
✅ Add optional field with default
✅ Remove optional field with default
✅ Add new enum value (if reader uses default)
✅ Widen numeric type (int → long)
✅ Add alias to field (keeping old name)

❌ Remove required field
❌ Add required field without default
❌ Rename field (without alias)
❌ Change field type incompatibly
❌ Reorder fields (in some formats)
```

---

# Part 3: Registry Architecture

## 🏗️ High Availability Setup

```
                    ┌─────────────────────────────────┐
                    │       Load Balancer             │
                    │   (HAProxy / AWS ALB)           │
                    └───────────────┬─────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
 ┌──────────────┐           ┌──────────────┐           ┌──────────────┐
 │ Registry 1   │           │ Registry 2   │           │ Registry 3   │
 │ (Leader)     │           │ (Follower)   │           │ (Follower)   │
 └──────┬───────┘           └──────┬───────┘           └──────┬───────┘
        │                          │                          │
        └──────────────────────────┼──────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │    Kafka (_schemas topic)   │
                    │    (Storage backend)        │
                    └─────────────────────────────┘
```

### Confluent Schema Registry Config
```properties
# schema-registry.properties

# Listeners
listeners=http://0.0.0.0:8081

# Kafka bootstrap
kafkastore.bootstrap.servers=kafka1:9092,kafka2:9092,kafka3:9092
kafkastore.topic=_schemas
kafkastore.topic.replication.factor=3

# Leader election
leader.eligibility=true
master.eligibility=true

# HA mode
mode=LEADER_FOLLOWER  # or READWRITE vs READONLY

# Security
kafkastore.security.protocol=SASL_SSL
kafkastore.sasl.mechanism=PLAIN
kafkastore.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="registry" password="secret";

# Compatibility default
schema.compatibility.level=BACKWARD_TRANSITIVE
```

## 📡 REST API

### Register Schema
```bash
# Register new version
curl -X POST http://registry:8081/subjects/user-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schemaType": "AVRO",
    "schema": "{\"type\":\"record\",\"name\":\"User\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"email\",\"type\":\"string\"}]}"
  }'

# Response: {"id": 42}
```

### Get Schema by ID
```bash
curl http://registry:8081/schemas/ids/42

# Response:
{
  "schema": "{\"type\":\"record\",\"name\":\"User\",...}"
}
```

### Check Compatibility
```bash
curl -X POST http://registry:8081/compatibility/subjects/user-value/versions/latest \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schema": "{...new schema...}"
  }'

# Response: {"is_compatible": true}
# or: {"is_compatible": false, "messages": ["...reason..."]}
```

### Set Compatibility Level
```bash
curl -X PUT http://registry:8081/config/user-value \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"compatibility": "FULL_TRANSITIVE"}'
```

---

# Part 4: Client Integration

## 🐍 Python Producer with Schema Registry

```python
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField

# Schema Registry client
schema_registry_conf = {
    'url': 'http://registry:8081',
    'basic.auth.user.info': 'user:password'  # If secured
}
schema_registry_client = SchemaRegistryClient(schema_registry_conf)

# Define schema
user_schema = """
{
  "type": "record",
  "name": "User",
  "namespace": "com.example",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "email", "type": "string"},
    {"name": "age", "type": ["null", "int"], "default": null}
  ]
}
"""

# Create serializer (auto-registers schema)
avro_serializer = AvroSerializer(
    schema_registry_client,
    user_schema,
    lambda user, ctx: dict(user)  # to_dict function
)

# Producer
producer_conf = {
    'bootstrap.servers': 'kafka:9092',
    'client.id': 'user-producer'
}
producer = Producer(producer_conf)

def produce_user(user: dict):
    producer.produce(
        topic='users',
        key=user['id'].encode('utf-8'),
        value=avro_serializer(user, SerializationContext('users', MessageField.VALUE)),
        on_delivery=lambda err, msg: print(f"Delivered: {msg.topic()}/{msg.partition()}")
    )
    producer.flush()

# Usage
produce_user({
    'id': 'user-123',
    'email': 'alice@example.com',
    'age': 30
})
```

## ☕ Java Consumer with Schema Registry

```java
import io.confluent.kafka.serializers.KafkaAvroDeserializer;
import io.confluent.kafka.serializers.KafkaAvroDeserializerConfig;
import org.apache.kafka.clients.consumer.*;
import org.apache.avro.generic.GenericRecord;

import java.util.*;

public class UserConsumer {
    public static void main(String[] args) {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, "kafka:9092");
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "user-consumers");
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, KafkaAvroDeserializer.class);
        
        // Schema Registry
        props.put(KafkaAvroDeserializerConfig.SCHEMA_REGISTRY_URL_CONFIG, "http://registry:8081");
        props.put(KafkaAvroDeserializerConfig.SPECIFIC_AVRO_READER_CONFIG, false);  // GenericRecord
        
        // Auto-fetch schemas
        props.put(KafkaAvroDeserializerConfig.AUTO_REGISTER_SCHEMAS, false);  // Consumer doesn't register
        
        Consumer<String, GenericRecord> consumer = new KafkaConsumer<>(props);
        consumer.subscribe(Collections.singletonList("users"));
        
        while (true) {
            ConsumerRecords<String, GenericRecord> records = consumer.poll(Duration.ofMillis(100));
            for (ConsumerRecord<String, GenericRecord> record : records) {
                GenericRecord user = record.value();
                System.out.printf("User: id=%s, email=%s, age=%s%n",
                    user.get("id"),
                    user.get("email"),
                    user.get("age")  // May be null for old records
                );
            }
        }
    }
}
```

---

# Part 5: Protobuf Support

## 📋 Protobuf Schema

```protobuf
// user.proto
syntax = "proto3";

package com.example;

message User {
  string id = 1;
  string email = 2;
  optional int32 age = 3;  // proto3 optional (explicit presence)
  
  // Nested message
  Address address = 4;
  
  // Enum
  UserStatus status = 5;
}

message Address {
  string street = 1;
  string city = 2;
  string country = 3;
}

enum UserStatus {
  UNKNOWN = 0;
  ACTIVE = 1;
  INACTIVE = 2;
  DELETED = 3;
}
```

### Register Protobuf Schema
```bash
curl -X POST http://registry:8081/subjects/user-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schemaType": "PROTOBUF",
    "schema": "syntax = \"proto3\";\n\npackage com.example;\n\nmessage User {\n  string id = 1;\n  string email = 2;\n  optional int32 age = 3;\n}"
  }'
```

### Protobuf Evolution Rules
```protobuf
// ✅ Safe: Add new field with new tag
message User {
  string id = 1;
  string email = 2;
  string phone = 3;  // NEW - safe, old readers ignore
}

// ✅ Safe: Mark field as deprecated (don't reuse tag)
message User {
  string id = 1;
  reserved 2;  // email removed, tag reserved
  string phone = 3;
}

// ❌ Breaking: Reuse tag number
message User {
  string id = 1;
  string nickname = 2;  // WRONG - tag 2 was email (string → string OK, but semantics changed)
}

// ❌ Breaking: Change tag number for existing field
message User {
  string id = 10;  // WRONG - was tag 1
}
```

---

# Part 6: Production Patterns

## 🔄 CI/CD Schema Validation

```yaml
# .github/workflows/schema-check.yml
name: Schema Compatibility Check

on:
  pull_request:
    paths:
      - 'schemas/**'

jobs:
  check-compatibility:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Check Avro Compatibility
        run: |
          for schema in schemas/*.avsc; do
            subject=$(basename "$schema" .avsc)-value
            echo "Checking $subject..."
            
            response=$(curl -s -X POST \
              "$SCHEMA_REGISTRY_URL/compatibility/subjects/$subject/versions/latest" \
              -H "Content-Type: application/vnd.schemaregistry.v1+json" \
              -d "{\"schema\": $(cat $schema | jq -c '.' | jq -Rs .)}")
            
            is_compatible=$(echo "$response" | jq -r '.is_compatible')
            
            if [ "$is_compatible" != "true" ]; then
              echo "❌ $subject is NOT compatible"
              echo "$response" | jq '.messages'
              exit 1
            fi
            
            echo "✅ $subject is compatible"
          done
        env:
          SCHEMA_REGISTRY_URL: ${{ secrets.SCHEMA_REGISTRY_URL }}
```

## 📊 Monitoring

```yaml
# Prometheus alerting rules
groups:
  - name: schema_registry
    rules:
      - alert: SchemaRegistryDown
        expr: up{job="schema-registry"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Schema Registry is down"
      
      - alert: SchemaRegistryHighLatency
        expr: histogram_quantile(0.99, rate(schema_registry_request_duration_seconds_bucket[5m])) > 0.5
        for: 5m
        annotations:
          summary: "Schema Registry P99 latency > 500ms"
      
      - alert: SchemaCompatibilityFailures
        expr: increase(schema_registry_compatibility_check_failures_total[1h]) > 10
        annotations:
          summary: "Many schema compatibility failures (potential breaking changes)"
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Registry HA with 3+ nodes | Test node failure |
| 2 | BACKWARD_TRANSITIVE as default | Check global config |
| 3 | CI/CD compatibility checks | PR fails on breaking change |
| 4 | No NONE compatibility in prod | Audit subject configs |
| 5 | Schema caching in clients | Startup time < 5s |
| 6 | Reserved fields documented | All removed fields marked reserved |
| 7 | Subject naming convention | `<topic>-key` / `<topic>-value` |
| 8 | Schema documentation | README per subject |

---

## 🔗 Related Documents
*   [Saga Pattern](./saga/saga-pattern-guide.md) — Event schema for sagas.
*   [NoSQL Architecture](./nosql-architecture-guide.md) — JSONB schema evolution.
*   [Replication & Consistency](./replication-consistency-guide.md) — Schema across regions.
