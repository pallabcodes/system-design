# NoSQL Security

## Overview

Security in NoSQL databases involves authentication, authorization, encryption, and network security. This guide covers security best practices for MongoDB, DynamoDB, Cassandra, and Redis.

## Table of Contents

1. [Authentication](#authentication)
2. [Authorization](#authorization)
3. [Encryption](#encryption)
4. [Network Security](#network-security)
5. [Audit Logging](#audit-logging)

## Authentication

### MongoDB Authentication

```javascript
// Enable authentication
// In mongod.conf:
security:
  authorization: enabled

// Create user
use admin
db.createUser({
  user: "admin",
  pwd: "secure_password",
  roles: [{ role: "root", db: "admin" }]
});

// Authenticate connection
const client = new MongoClient(uri, {
  auth: {
    username: "admin",
    password: "secure_password"
  }
});
```

### DynamoDB Authentication

```javascript
// Use IAM roles and policies
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB({
  region: 'us-east-1',
  credentials: new AWS.EnvironmentCredentials('AWS')
});

// IAM Policy Example
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:123456789012:table/Orders"
    }
  ]
}
```

### Redis Authentication

```javascript
// Set password in redis.conf
requirepass your_secure_password

// Authenticate connection
const redis = require('redis');
const client = redis.createClient({
  password: 'your_secure_password'
});
```

## Authorization

### MongoDB Role-Based Access Control

```javascript
// Create role
use admin
db.createRole({
  role: "readWriteOrders",
  privileges: [
    {
      resource: { db: "ecommerce", collection: "orders" },
      actions: ["find", "insert", "update", "remove"]
    }
  ],
  roles: []
});

// Assign role to user
db.createUser({
  user: "order_manager",
  pwd: "secure_password",
  roles: [{ role: "readWriteOrders", db: "ecommerce" }]
});
```

### DynamoDB IAM Policies

```javascript
// Fine-grained access control with IAM
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "dynamodb:Query",
      "Resource": "arn:aws:dynamodb:us-east-1:123456789012:table/Orders",
      "Condition": {
        "ForAllValues:StringEquals": {
          "dynamodb:LeadingKeys": ["${aws:userid}"]
        }
      }
    }
  ]
}
```

## Encryption

### Encryption at Rest

**MongoDB:**
* Use encrypted storage volumes
* Enable WiredTiger encryption
* Use key management services (KMS)

**DynamoDB:**
* Enable encryption at rest (default)
* Use AWS KMS for key management

**Cassandra:**
* Use transparent data encryption (TDE)
* Encrypt commit logs and SSTables

### Encryption in Transit

```javascript
// MongoDB: Use TLS/SSL
const client = new MongoClient(uri, {
  tls: true,
  tlsCertificateKeyFile: "/path/to/client.pem",
  tlsCAFile: "/path/to/ca.pem"
});

// Redis: Use TLS
const client = redis.createClient({
  socket: {
    tls: true,
    cert: fs.readFileSync('/path/to/client.crt'),
    key: fs.readFileSync('/path/to/client.key'),
    ca: fs.readFileSync('/path/to/ca.crt')
  }
});
```

### Field-Level Encryption

**MongoDB:**
```javascript
// Use client-side field-level encryption
const client = new MongoClient(uri, {
  autoEncryption: {
    keyVaultNamespace: "encryption.__keyVault",
    kmsProviders: {
      aws: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
      }
    }
  }
});
```

## Network Security

### Firewall Rules

* Restrict database access to specific IP addresses
* Use VPCs and security groups (AWS)
* Implement network segmentation

### Connection Security

```javascript
// MongoDB: Whitelist IP addresses
// In mongod.conf:
net:
  bindIp: 127.0.0.1,10.0.0.0/24

// Redis: Bind to specific interface
// In redis.conf:
bind 127.0.0.1 10.0.0.1
```

## Audit Logging

### MongoDB Audit Log

```javascript
// Enable audit log
// In mongod.conf:
auditLog:
  destination: file
  format: JSON
  path: /var/log/mongodb/audit.json

// Audit filter
auditLog:
  filter: '{ "users": { $elemMatch: { user: "admin" } } }'
```

### DynamoDB CloudTrail

* Enable AWS CloudTrail for DynamoDB API calls
* Monitor all table operations
* Set up alerts for suspicious activity

## Best Practices

1. **Enable authentication** for all databases
2. **Use strong passwords** and rotate them regularly
3. **Implement least privilege** access control
4. **Encrypt data at rest** and in transit
5. **Use network security** (firewalls, VPCs)
6. **Enable audit logging** for compliance
7. **Regular security audits** and penetration testing
8. **Keep databases updated** with security patches
9. **Use key management services** for encryption keys
10. **Monitor access** and set up alerts

This guide provides comprehensive security practices for NoSQL databases.

