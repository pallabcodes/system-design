# Service Discovery Comprehensive Guide

## Overview

Service discovery is a critical component of distributed systems that enables services to dynamically locate and communicate with each other without hardcoded network addresses. This comprehensive guide covers service discovery patterns, implementations (Consul, Eureka, etcd), best practices, and enterprise patterns for building resilient microservices architectures.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Service Discovery Patterns](#service-discovery-patterns)
3. [Implementation Technologies](#implementation-technologies)
4. [Consul Deep Dive](#consul-deep-dive)
5. [Eureka Deep Dive](#eureka-deep-dive)
6. [etcd Deep Dive](#etcd-deep-dive)
7. [Kubernetes Service Discovery](#kubernetes-service-discovery)
8. [Best Practices](#best-practices)
9. [Performance Optimization](#performance-optimization)
10. [Security](#security)
11. [Monitoring & Observability](#monitoring--observability)

## Core Concepts

### What is Service Discovery?

Service discovery is the automatic detection of services and their network locations in a distributed system. It eliminates the need for hardcoded IP addresses and enables dynamic service communication.

### Key Components

- **Service Registry**: Central database storing service information (name, IP, port, health status)
- **Service Registration**: Process of services announcing their availability
- **Service Lookup**: Querying the registry to find service instances
- **Health Checking**: Monitoring service availability and removing failed instances
- **Load Balancing**: Distributing requests across multiple service instances

### Benefits

- **Dynamic Scaling**: Services can be added/removed without configuration changes
- **Fault Tolerance**: Failed services automatically removed from routing
- **Load Distribution**: Automatic load balancing across healthy instances
- **Zero Configuration**: Services discover each other automatically
- **High Availability**: Multiple registry instances prevent single points of failure

## Service Discovery Patterns

### 1. Client-Side Discovery

**Architecture**: Client queries registry and selects service instance directly.

```typescript
// Client-side discovery example
class ServiceDiscoveryClient {
  constructor(private registry: ServiceRegistry) {}

  async discoverService(serviceName: string): Promise<ServiceInstance[]> {
    // Query registry
    const instances = await this.registry.getInstances(serviceName);
    
    // Filter healthy instances
    const healthyInstances = instances.filter(i => i.health === 'healthy');
    
    // Apply load balancing
    return this.loadBalance(healthyInstances);
  }

  private loadBalance(instances: ServiceInstance[]): ServiceInstance {
    // Round-robin selection
    const index = Math.floor(Math.random() * instances.length);
    return instances[index];
  }
}
```

**Advantages**:
- Direct service-to-service communication
- No additional proxy component
- Client has full control over selection logic

**Disadvantages**:
- Client complexity increases
- Must implement load balancing logic
- Coupling to registry API

### 2. Server-Side Discovery

**Architecture**: Load balancer queries registry and routes requests.

```nginx
# NGINX server-side discovery configuration
upstream backend {
    # Dynamic service discovery via Consul
    consul 127.0.0.1:8500 service=user-service resolve;
}

server {
    listen 80;
    location / {
        proxy_pass http://backend;
    }
}
```

**Advantages**:
- Client simplicity (no discovery logic)
- Centralized load balancing
- Automatic failover

**Disadvantages**:
- Additional component (load balancer)
- Extra network hop
- Single point of failure risk

### 3. Service Mesh Discovery

**Architecture**: Service mesh (Istio, Linkerd) handles discovery transparently.

```yaml
# Istio VirtualService for service discovery
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: user-service
spec:
  hosts:
  - user-service
  http:
  - match:
    - headers:
        version:
          exact: v1
    route:
    - destination:
        host: user-service
        subset: v1
      weight: 80
    - destination:
        host: user-service
        subset: v2
      weight: 20
```

**Advantages**:
- Rich metadata (version, region, load)
- Advanced traffic management
- Built-in security (mTLS)
- Comprehensive observability

**Disadvantages**:
- High complexity
- Resource overhead (sidecar proxies)
- Learning curve

## Implementation Technologies

### Comparison Matrix

| Technology | Type | Language | CAP | Use Case |
|------------|------|----------|-----|----------|
| **Consul** | Service Discovery + Config | Go | CP | Multi-datacenter, service mesh |
| **Eureka** | Service Discovery | Java | AP | Netflix-style microservices |
| **etcd** | Distributed Key-Value | Go | CP | Kubernetes, distributed config |
| **Zookeeper** | Coordination Service | Java | CP | Kafka, Hadoop ecosystems |
| **Kubernetes** | Orchestration | Go | CP | Container orchestration |

## Consul Deep Dive

### Architecture

Consul provides service discovery, health checking, and distributed configuration with multi-datacenter support.

### Core Components

- **Agents**: Run on every node, maintain service catalog
- **Servers**: Maintain cluster state, handle queries
- **Clients**: Lightweight agents that forward requests to servers
- **Service Catalog**: Registry of all services and health status

### Installation and Setup

```bash
# Download Consul
wget https://releases.hashicorp.com/consul/1.17.0/consul_1.17.0_linux_amd64.zip
unzip consul_1.17.0_linux_amd64.zip
sudo mv consul /usr/local/bin/

# Start Consul agent (development)
consul agent -dev

# Start Consul server (production)
consul agent -server -bootstrap-expect=3 \
  -data-dir=/opt/consul \
  -node=server-1 \
  -bind=192.168.1.10 \
  -client=0.0.0.0 \
  -ui
```

### Service Registration

#### 1. Service Definition File

```json
{
  "service": {
    "name": "user-service",
    "id": "user-service-1",
    "tags": ["api", "v1", "production"],
    "port": 8080,
    "address": "192.168.1.10",
    "check": {
      "http": "http://192.168.1.10:8080/health",
      "interval": "10s",
      "timeout": "3s",
      "deregister_critical_service_after": "30s"
    },
    "meta": {
      "version": "1.2.3",
      "environment": "production",
      "region": "us-east-1"
    }
  }
}
```

#### 2. Register via API

```bash
# Register service via HTTP API
curl --request PUT \
  --data @service-definition.json \
  http://localhost:8500/v1/agent/service/register
```

#### 3. Register via Code

```go
// Go example
package main

import (
    "github.com/hashicorp/consul/api"
    "log"
)

func registerService() {
    config := api.DefaultConfig()
    config.Address = "localhost:8500"
    
    client, err := api.NewClient(config)
    if err != nil {
        log.Fatal(err)
    }
    
    registration := &api.AgentServiceRegistration{
        ID:      "user-service-1",
        Name:    "user-service",
        Tags:    []string{"api", "v1"},
        Port:    8080,
        Address: "192.168.1.10",
        Check: &api.AgentServiceCheck{
            HTTP:     "http://192.168.1.10:8080/health",
            Interval: "10s",
            Timeout:  "3s",
        },
    }
    
    err = client.Agent().ServiceRegister(registration)
    if err != nil {
        log.Fatal(err)
    }
}
```

### Service Discovery

#### Query Services

```bash
# Get all instances of a service
curl http://localhost:8500/v1/health/service/user-service?passing

# Response
[
  {
    "Service": {
      "ID": "user-service-1",
      "Service": "user-service",
      "Tags": ["api", "v1"],
      "Address": "192.168.1.10",
      "Port": 8080,
      "Meta": {
        "version": "1.2.3"
      }
    },
    "Checks": [
      {
        "Status": "passing",
        "Output": "HTTP GET http://192.168.1.10:8080/health: 200 OK"
      }
    ]
  }
]
```

#### DNS-Based Discovery

```bash
# Query via DNS
dig @127.0.0.1 -p 8600 user-service.service.consul

# Get specific instance
dig @127.0.0.1 -p 8600 user-service-1.user-service.service.consul

# Get instances with tag
dig @127.0.0.1 -p 8600 v1.user-service.service.consul
```

### Health Checks

Consul supports multiple health check types:

```json
{
  "check": {
    "id": "user-service-health",
    "name": "User Service Health Check",
    "http": "http://localhost:8080/health",
    "interval": "10s",
    "timeout": "3s",
    "deregister_critical_service_after": "30s"
  }
}
```

**Health Check Types**:
- **HTTP**: HTTP endpoint check
- **TCP**: TCP connection check
- **Script**: Custom script execution
- **TTL**: Time-to-live based check
- **Docker**: Container health check
- **gRPC**: gRPC health check

### Multi-Datacenter Setup

```hcl
# consul.hcl - Multi-datacenter configuration
datacenter = "us-east-1"
primary_datacenter = "us-east-1"

retry_join = [
  "192.168.1.10",
  "192.168.1.11",
  "192.168.1.12"
]

connect {
  enabled = true
}

ports {
  grpc = 8502
}

acl {
  enabled = true
  default_policy = "deny"
  down_policy = "extend-cache"
}
```

### Consul Connect (Service Mesh)

```hcl
# Service mesh configuration
connect {
  enabled = true
  ca_provider = "consul"
  
  proxy {
    defaults {
      config {
        bind_address = "127.0.0.1"
        bind_port = 20000
      }
    }
  }
}
```

## Eureka Deep Dive

### Architecture

Eureka is Netflix's service discovery solution designed for high availability and eventual consistency (AP system).

### Core Components

- **Eureka Server**: Service registry server
- **Eureka Client**: Service registration and discovery client
- **Service Instance**: Registered service with metadata
- **Replication**: Peer-to-peer replication between servers

### Setup

#### Eureka Server

```java
// Spring Boot Eureka Server
@SpringBootApplication
@EnableEurekaServer
public class EurekaServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(EurekaServerApplication.class, args);
    }
}
```

```yaml
# application.yml
server:
  port: 8761

eureka:
  instance:
    hostname: localhost
  client:
    register-with-eureka: false
    fetch-registry: false
    service-url:
      defaultZone: http://${eureka.instance.hostname}:${server.port}/eureka/
```

#### Eureka Client (Service Registration)

```java
// Spring Boot Eureka Client
@SpringBootApplication
@EnableEurekaClient
public class UserServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(UserServiceApplication.class, args);
    }
}
```

```yaml
# application.yml
spring:
  application:
    name: user-service

eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
  instance:
    prefer-ip-address: true
    lease-renewal-interval-in-seconds: 30
    lease-expiration-duration-in-seconds: 90
```

### Service Discovery

```java
// Using Eureka client for service discovery
@Service
public class MovieServiceClient {
    
    @Autowired
    private DiscoveryClient discoveryClient;
    
    @Autowired
    private RestTemplate restTemplate;
    
    public Movie getMovie(Long id) {
        List<ServiceInstance> instances = 
            discoveryClient.getInstances("movie-service");
        
        if (instances.isEmpty()) {
            throw new RuntimeException("No movie-service instances available");
        }
        
        // Load balancing
        ServiceInstance instance = instances.get(
            (int) (Math.random() * instances.size())
        );
        
        String url = String.format("http://%s:%d/movies/%d",
            instance.getHost(), instance.getPort(), id);
        
        return restTemplate.getForObject(url, Movie.class);
    }
}
```

### Eureka with Ribbon (Load Balancing)

```java
@Configuration
public class RibbonConfig {
    
    @Bean
    @LoadBalanced
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
}

// Usage with load balancing
@Service
public class MovieServiceClient {
    
    @Autowired
    private RestTemplate restTemplate;
    
    public Movie getMovie(Long id) {
        // Ribbon automatically load balances
        return restTemplate.getForObject(
            "http://movie-service/movies/{id}", 
            Movie.class, 
            id
        );
    }
}
```

### High Availability Setup

```yaml
# eureka-server-1.yml
eureka:
  client:
    service-url:
      defaultZone: http://eureka-server-2:8761/eureka/,http://eureka-server-3:8761/eureka/

# eureka-server-2.yml
eureka:
  client:
    service-url:
      defaultZone: http://eureka-server-1:8761/eureka/,http://eureka-server-3:8761/eureka/

# eureka-server-3.yml
eureka:
  client:
    service-url:
      defaultZone: http://eureka-server-1:8761/eureka/,http://eureka-server-2:8761/eureka/
```

## etcd Deep Dive

### Architecture

etcd is a distributed, reliable key-value store used for service discovery and configuration management, particularly in Kubernetes.

### Core Concepts

- **Key-Value Store**: Simple key-value database
- **Watch**: Real-time notifications on key changes
- **Lease**: Time-to-live for keys
- **Transactions**: Atomic operations
- **Raft Consensus**: Distributed consensus algorithm

### Installation

```bash
# Download etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.5.9/etcd-v3.5.9-linux-amd64.tar.gz
tar xzf etcd-v3.5.9-linux-amd64.tar.gz
cd etcd-v3.5.9-linux-amd64
sudo cp etcd etcdctl /usr/local/bin/

# Start etcd (single node)
etcd --name node1 \
  --data-dir /var/lib/etcd \
  --listen-client-urls http://0.0.0.0:2379 \
  --advertise-client-urls http://localhost:2379
```

### Service Registration

```bash
# Register service with TTL
etcdctl put /services/user-service/instance-1 \
  '{"host":"192.168.1.10","port":8080}' \
  --lease=60

# Create lease
LEASE_ID=$(etcdctl lease grant 60 | awk '{print $2}')

# Put with lease
etcdctl put /services/user-service/instance-1 \
  '{"host":"192.168.1.10","port":8080}' \
  --lease=$LEASE_ID

# Keep lease alive
etcdctl lease keep-alive $LEASE_ID
```

### Service Discovery

```bash
# Get all service instances
etcdctl get /services/user-service/instance-1 --prefix

# Watch for changes
etcdctl watch /services/user-service/ --prefix
```

### Go Client Example

```go
package main

import (
    "context"
    "encoding/json"
    "log"
    "time"
    
    clientv3 "go.etcd.io/etcd/client/v3"
)

type ServiceInstance struct {
    Host string `json:"host"`
    Port int    `json:"port"`
}

func registerService() {
    cli, err := clientv3.New(clientv3.Config{
        Endpoints:   []string{"localhost:2379"},
        DialTimeout: 5 * time.Second,
    })
    if err != nil {
        log.Fatal(err)
    }
    defer cli.Close()
    
    // Create lease
    lease, err := cli.Grant(context.TODO(), 60)
    if err != nil {
        log.Fatal(err)
    }
    
    // Register service
    instance := ServiceInstance{
        Host: "192.168.1.10",
        Port: 8080,
    }
    data, _ := json.Marshal(instance)
    
    _, err = cli.Put(context.TODO(),
        "/services/user-service/instance-1",
        string(data),
        clientv3.WithLease(lease.ID))
    if err != nil {
        log.Fatal(err)
    }
    
    // Keep lease alive
    ch, kaerr := cli.KeepAlive(context.TODO(), lease.ID)
    if kaerr != nil {
        log.Fatal(kaerr)
    }
    
    go func() {
        for ka := range ch {
            log.Printf("Lease kept alive: %v", ka)
        }
    }()
}
```

### Watch for Service Changes

```go
func watchServices(cli *clientv3.Client) {
    watchChan := cli.Watch(context.Background(),
        "/services/user-service/",
        clientv3.WithPrefix())
    
    for watchResp := range watchChan {
        for _, event := range watchResp.Events {
            switch event.Type {
            case clientv3.EventTypePut:
                log.Printf("Service registered: %s", string(event.Kv.Key))
            case clientv3.EventTypeDelete:
                log.Printf("Service deregistered: %s", string(event.Kv.Key))
            }
        }
    }
}
```

## Kubernetes Service Discovery

### Native Service Discovery

Kubernetes provides built-in service discovery through DNS and Service objects.

### Service Types

```yaml
# ClusterIP (default) - Internal service discovery
apiVersion: v1
kind: Service
metadata:
  name: user-service
spec:
  selector:
    app: user-service
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: ClusterIP
```

```yaml
# NodePort - External access
apiVersion: v1
kind: Service
metadata:
  name: user-service
spec:
  type: NodePort
  selector:
    app: user-service
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080
```

```yaml
# LoadBalancer - Cloud provider load balancer
apiVersion: v1
kind: Service
metadata:
  name: user-service
spec:
  type: LoadBalancer
  selector:
    app: user-service
  ports:
    - port: 80
      targetPort: 8080
```

### DNS-Based Discovery

```bash
# Service DNS format
# <service-name>.<namespace>.svc.cluster.local

# Example
user-service.default.svc.cluster.local

# Short form (same namespace)
user-service
```

### Service Discovery in Code

```go
// Kubernetes client for service discovery
package main

import (
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/rest"
)

func discoverService() {
    config, err := rest.InClusterConfig()
    if err != nil {
        log.Fatal(err)
    }
    
    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        log.Fatal(err)
    }
    
    // Get service endpoints
    endpoints, err := clientset.CoreV1().Endpoints("default").
        Get(context.TODO(), "user-service", metav1.GetOptions{})
    
    for _, subset := range endpoints.Subsets {
        for _, address := range subset.Addresses {
            log.Printf("Service instance: %s:%d",
                address.IP, subset.Ports[0].Port)
        }
    }
}
```

## Best Practices

### 1. Service Naming Conventions

- Use lowercase with hyphens: `user-service`, `movie-service`
- Be descriptive but concise
- Include environment when needed: `user-service-prod`
- Version in metadata, not name

### 2. Health Check Implementation

```typescript
// Comprehensive health check endpoint
app.get('/health', async (req, res) => {
  const health = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    checks: {
      database: await checkDatabase(),
      cache: await checkCache(),
      externalApi: await checkExternalApi()
    }
  };
  
  const allHealthy = Object.values(health.checks)
    .every(check => check.status === 'healthy');
  
  health.status = allHealthy ? 'healthy' : 'unhealthy';
  
  res.status(allHealthy ? 200 : 503).json(health);
});
```

### 3. Registration Patterns

- **Self-Registration**: Service registers itself on startup
- **Third-Party Registration**: Sidecar or orchestrator handles registration
- **Automatic Registration**: Kubernetes, Docker Swarm handle automatically

### 4. Load Balancing Strategies

- **Round Robin**: Equal distribution
- **Least Connections**: Route to instance with fewest active connections
- **Weighted**: Based on instance capacity
- **Health-Aware**: Only route to healthy instances
- **Geographic**: Route based on region/latency

### 5. Failure Handling

- **Circuit Breaker**: Prevent cascading failures
- **Retry with Backoff**: Exponential backoff for transient failures
- **Fallback**: Alternative service or cached response
- **Graceful Degradation**: Continue with reduced functionality

## Performance Optimization

### Caching Strategies

```typescript
// Cache service instances locally
class CachedServiceDiscovery {
  private cache: Map<string, ServiceInstance[]> = new Map();
  private cacheTTL: number = 30000; // 30 seconds
  
  async getInstances(serviceName: string): Promise<ServiceInstance[]> {
    const cached = this.cache.get(serviceName);
    if (cached && Date.now() - cached.timestamp < this.cacheTTL) {
      return cached.instances;
    }
    
    const instances = await this.registry.getInstances(serviceName);
    this.cache.set(serviceName, {
      instances,
      timestamp: Date.now()
    });
    
    return instances;
  }
}
```

### Connection Pooling

- Reuse connections to registry
- Implement connection pooling
- Use HTTP/2 for multiplexing
- Batch queries when possible

### Registry Clustering

- Deploy multiple registry instances
- Use load balancer for registry access
- Implement read replicas for high read throughput
- Distribute registry across availability zones

## Security

### Authentication and Authorization

```hcl
# Consul ACL configuration
acl {
  enabled = true
  default_policy = "deny"
  
  tokens {
    agent = "master-token"
    default = "read-only-token"
  }
}
```

### mTLS Implementation

- Use mutual TLS for service-to-service communication
- Certificate rotation and management
- Service identity verification
- Encrypted registry communication

### Network Policies

- Restrict network access with firewalls
- Use service mesh for network-level security
- Implement network segmentation
- Monitor and audit access patterns

## Monitoring & Observability

### Key Metrics

- **Registration Success Rate**: Percentage of successful registrations
- **Discovery Latency**: Time to discover service instances
- **Registry Availability**: Uptime of service registry
- **Health Check Success Rate**: Percentage of passing health checks
- **Service Instance Count**: Number of registered instances per service

### Dashboards

- Service catalog overview
- Health check status
- Registration/deregistration events
- Load balancing distribution
- Error rates and latency

### Alerting

- Registry unavailability
- High discovery latency
- Service registration failures
- Health check failures
- Unusual service count changes

## Production Deployment Patterns

### Multi-Region Setup

- Deploy registry in each region
- Replicate service catalog across regions
- Route traffic to nearest healthy instance
- Handle network partitions gracefully

### Disaster Recovery

- Regular backups of registry state
- Cross-region replication
- Automated failover procedures
- Service catalog recovery procedures

### Capacity Planning

- Monitor registry load and capacity
- Scale registry horizontally
- Optimize health check frequency
- Balance consistency vs availability

This comprehensive guide provides enterprise-grade service discovery patterns and implementations for building resilient, scalable microservices architectures.

