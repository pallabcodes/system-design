# API Gateway Comprehensive Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Gateway Selection, Rate-Limit Bypass, and Production-Grade Deployments.

> [!IMPORTANT]
> **The Principal Trade-off**: An API Gateway is a **Centralized Tax**. Every millisecond of latency added here is paid by every single request. Choose the lightest-weight solution that meets your requirements.

## Overview

API Gateways serve as the single entry point for client requests, providing routing, authentication, rate limiting, request/response transformation, and observability. This comprehensive guide covers production-ready API Gateway implementations including Kong, AWS API Gateway, Envoy, Spring Cloud Gateway, and enterprise patterns for building scalable, secure microservices architectures.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [API Gateway Patterns](#api-gateway-patterns)
3. [Kong Deep Dive](#kong-deep-dive)
4. [AWS API Gateway](#aws-api-gateway)
5. [Envoy Proxy](#envoy-proxy)
6. [Spring Cloud Gateway](#spring-cloud-gateway)
7. [NGINX as API Gateway](#nginx-as-api-gateway)
8. [Best Practices](#best-practices)
9. [Performance Optimization](#performance-optimization)
10. [Security](#security)
11. [Monitoring & Observability](#monitoring--observability)

## Core Concepts

### What is an API Gateway?

An API Gateway is a reverse proxy that sits between clients and backend services, providing a unified interface for API access with cross-cutting concerns like authentication, rate limiting, and request routing.

### Key Responsibilities

- **Request Routing**: Route requests to appropriate backend services
- **Authentication & Authorization**: Verify client identity and permissions
- **Rate Limiting**: Control request rates per client/service
- **Request/Response Transformation**: Modify requests and responses
- **Load Balancing**: Distribute traffic across service instances
- **Caching**: Cache responses to reduce backend load
- **Monitoring**: Track metrics, logs, and traces
- **Security**: SSL termination, WAF, DDoS protection

### Benefits

- **Single Entry Point**: Unified API interface for clients
- **Cross-Cutting Concerns**: Centralized authentication, logging, monitoring
- **Service Decoupling**: Clients don't need to know about backend services
- **Protocol Translation**: Convert between HTTP, gRPC, WebSocket
- **Request Aggregation**: Combine multiple service calls into one
- **Versioning**: Manage multiple API versions

---

## 🏛️ Principal Architect: Gateway Selection Matrix

Choosing the right gateway is a **non-reversible architectural decision**. This matrix aids the selection.

| Gateway | Best For | Latency | Ecosystem | Caveat |
| :--- | :--- | :--- | :--- | :--- |
| **Envoy** | Service Mesh (Istio) | **Lowest** (~1ms) | gRPC, xDS | Complex YAML config |
| **Kong** | Public API Monetization | Low (~3ms) | Plugins, DB-backed | Lua performance ceiling |
| **AWS API Gateway** | Serverless (Lambda) | Medium (~10ms) | Native AWS integration | Vendor Lock-in, Cost at scale |
| **Spring Cloud Gateway** | Java/JVM Backend | Low (~2ms) | Spring Ecosystem | JVM cold-start |
| **NGINX** | High-Volume Static | **Lowest** | Lua (OpenResty) | No native service discovery |

---

## 🛡️ Principal Pattern: Rate Limit Bypass & The "VIP Lane"

Standard rate limiting applies uniformly. A Principal Architect designs **Tiered Access**.

### The "VIP Lane" Pattern
For critical internal services or premium customers, bypass the rate limiter:
```typescript
// VIP Bypass Logic
app.use((req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  
  // Check if the caller is a VIP (internal service or premium tier)
  if (isVipKey(apiKey)) {
    req.skipRateLimiter = true; // Signal to skip rate limiter
  }
  next();
});

// Rate Limiter Middleware
app.use((req, res, next) => {
  if (req.skipRateLimiter) {
    return next(); // Bypass for VIPs
  }
  // Apply standard rate limiting...
});
```

### The "Leaky Bucket" vs "Token Bucket" Decision
| Algorithm | Behavior | Use Case |
| :--- | :--- | :--- |
| **Leaky Bucket** | Constant output rate, smooths bursts. | Billing APIs, Stable Throughput. |
| **Token Bucket** | Allows short bursts up to capacity. | User-facing APIs, Bursty Traffic. |

---

## API Gateway Patterns

### 1. Edge Gateway Pattern

**Architecture**: Single gateway at the edge handling all external traffic.

```
┌─────────────┐
│   Clients   │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  API Gateway    │
│  (Edge)         │
└──────┬──────────┘
       │
       ├──► User Service
       ├──► Product Service
       └──► Order Service
```

**Use Case**: Public-facing APIs, mobile applications

### 2. Backend for Frontend (BFF) Pattern

**Architecture**: Separate gateway per client type (mobile, web, admin).

```
┌──────────┐  ┌──────────┐  ┌──────────┐
│  Mobile  │  │   Web    │  │   Admin  │
│  Client  │  │  Client  │  │  Client  │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │
     ▼             ▼             ▼
┌─────────┐  ┌─────────┐  ┌─────────┐
│ Mobile  │  │  Web    │  │  Admin  │
│   BFF   │  │   BFF   │  │   BFF   │
└────┬────┘  └────┬────┘  └────┬────┘
     │             │             │
     └─────┬───────┴───────┬─────┘
           │               │
     ┌─────┴───────────────┴─────┐
     │    Backend Services       │
     └───────────────────────────┘
```

**Use Case**: Different client requirements, optimized payloads per client

### 3. Gateway Aggregation Pattern

**Architecture**: Gateway aggregates multiple service calls.

```typescript
// Gateway aggregates multiple service calls
app.get('/user/:id/dashboard', async (req, res) => {
  const userId = req.params.id;
  
  // Aggregate calls
  const [user, orders, recommendations] = await Promise.all([
    userService.getUser(userId),
    orderService.getUserOrders(userId),
    recommendationService.getRecommendations(userId)
  ]);
  
  res.json({
    user,
    orders,
    recommendations
  });
});
```

**Use Case**: Mobile clients needing aggregated data, reducing round trips

## Kong Deep Dive

### Architecture

Kong is an open-source API gateway built on NGINX and Lua, providing plugins for extensibility.

### Core Components

- **Kong Server**: Core gateway server
- **Kong Admin API**: Management API for configuration
- **Kong Database**: PostgreSQL or Cassandra for configuration storage
- **Plugins**: Extensible plugins for authentication, rate limiting, etc.

### Installation

```bash
# Docker Compose setup
version: '3.8'
services:
  kong-database:
    image: postgres:13
    environment:
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kong
      POSTGRES_DB: kong
    volumes:
      - kong_data:/var/lib/postgresql/data

  kong-migrations:
    image: kong:latest
    command: kong migrations bootstrap
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
    depends_on:
      - kong-database

  kong:
    image: kong:latest
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
    ports:
      - "8000:8000"  # Proxy port
      - "8443:8443"  # Proxy SSL port
      - "8001:8001"  # Admin API
      - "8444:8444"  # Admin API SSL
    depends_on:
      - kong-migrations

volumes:
  kong_data:
```

### Service and Route Configuration

```bash
# Create a service
curl -i -X POST http://localhost:8001/services/ \
  --data "name=user-service" \
  --data "url=http://user-service:8080"

# Create a route
curl -i -X POST http://localhost:8001/services/user-service/routes \
  --data "hosts[]=api.example.com" \
  --data "paths[]=/api/users"
```

### Authentication Plugins

#### JWT Authentication

```bash
# Enable JWT plugin
curl -X POST http://localhost:8001/services/user-service/plugins \
  --data "name=jwt"

# Create consumer
curl -X POST http://localhost:8001/consumers \
  --data "username=api-client"

# Create JWT credential
curl -X POST http://localhost:8001/consumers/api-client/jwt \
  --data "key=my-secret-key"
```

#### OAuth2 Authentication

```bash
# Enable OAuth2 plugin
curl -X POST http://localhost:8001/services/user-service/plugins \
  --data "name=oauth2" \
  --data "config.scopes=read,write" \
  --data "config.mandatory_scope=true"
```

### Rate Limiting

```bash
# Enable rate limiting
curl -X POST http://localhost:8001/services/user-service/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=100" \
  --data "config.hour=1000" \
  --data "config.policy=local"
```

### Request/Response Transformation

```bash
# Enable request transformation
curl -X POST http://localhost:8001/services/user-service/plugins \
  --data "name=request-transformer" \
  --data "config.add.headers=X-Custom-Header:value" \
  --data "config.add.querystring=api_key:secret"

# Enable response transformation
curl -X POST http://localhost:8001/services/user-service/plugins \
  --data "name=response-transformer" \
  --data "config.remove.headers=X-Internal-Header"
```

### Kong Configuration File

```yaml
# kong.yml (Declarative Configuration)
_format_version: "3.0"

services:
  - name: user-service
    url: http://user-service:8080
    routes:
      - name: user-route
        paths:
          - /api/users
        methods:
          - GET
          - POST
    plugins:
      - name: rate-limiting
        config:
          minute: 100
          hour: 1000
      - name: jwt
        config:
          secret_is_base64: false

  - name: product-service
    url: http://product-service:8080
    routes:
      - name: product-route
        paths:
          - /api/products
    plugins:
      - name: oauth2
        config:
          scopes:
            - read
            - write
```

### Kong Enterprise Features

- **Advanced Analytics**: Real-time analytics and reporting
- **Developer Portal**: Self-service API portal
- **RBAC**: Role-based access control
- **Vault Integration**: Secrets management
- **GraphQL Support**: GraphQL routing and federation

## AWS API Gateway

### Architecture

AWS API Gateway is a fully managed service for creating, publishing, and managing REST and WebSocket APIs.

### API Types

- **REST API**: RESTful HTTP APIs
- **HTTP API**: Low-latency HTTP APIs (newer, cheaper)
- **WebSocket API**: Real-time bidirectional communication

### REST API Setup

```yaml
# CloudFormation template
Resources:
  ApiGateway:
    Type: AWS::ApiGateway::RestApi
    Properties:
      Name: user-service-api
      Description: User Service API Gateway
      EndpointConfiguration:
        Types:
          - REGIONAL

  UserResource:
    Type: AWS::ApiGateway::Resource
    Properties:
      RestApiId: !Ref ApiGateway
      ParentId: !GetAtt ApiGateway.RootResourceId
      PathPart: users

  GetUserMethod:
    Type: AWS::ApiGateway::Method
    Properties:
      RestApiId: !Ref ApiGateway
      ResourceId: !Ref UserResource
      HttpMethod: GET
      AuthorizationType: AWS_IAM
      Integration:
        Type: HTTP_PROXY
        IntegrationHttpMethod: GET
        Uri: http://user-service:8080/users
        RequestParameters:
          integration.request.querystring.id: method.request.querystring.id
```

### HTTP API Setup

```typescript
// AWS CDK example
import * as apigatewayv2 from '@aws-cdk/aws-apigatewayv2';
import * as integrations from '@aws-cdk/aws-apigatewayv2-integrations';

const httpApi = new apigatewayv2.HttpApi(this, 'UserServiceApi', {
  description: 'User Service HTTP API',
  corsPreflight: {
    allowOrigins: ['https://example.com'],
    allowMethods: [apigatewayv2.CorsHttpMethod.GET, apigatewayv2.CorsHttpMethod.POST],
    allowHeaders: ['content-type', 'authorization'],
    maxAge: Duration.days(10)
  }
});

const userServiceIntegration = new integrations.HttpLambdaIntegration(
  'UserServiceIntegration',
  userServiceLambda
);

httpApi.addRoutes({
  path: '/users/{id}',
  methods: [apigatewayv2.HttpMethod.GET],
  integration: userServiceIntegration
});
```

### Authentication & Authorization

#### API Keys

```typescript
// Create API key
const apiKey = new apigateway.ApiKey(this, 'ApiKey', {
  apiKeyName: 'user-service-api-key',
  description: 'API Key for User Service'
});

// Create usage plan
const usagePlan = new apigateway.UsagePlan(this, 'UsagePlan', {
  name: 'user-service-usage-plan',
  apiStages: [{
    api: restApi,
    stage: deploymentStage
  }],
  throttle: {
    rateLimit: 100,
    burstLimit: 200
  },
  quota: {
    limit: 10000,
    period: apigateway.Period.MONTH
  }
});

usagePlan.addApiKey(apiKey);
```

#### Cognito Authorizer

```typescript
// Cognito User Pool
const userPool = new cognito.UserPool(this, 'UserPool', {
  userPoolName: 'user-service-pool'
});

// Authorizer
const authorizer = new apigateway.CognitoUserPoolsAuthorizer(this, 'Authorizer', {
  cognitoUserPools: [userPool]
});

// Method with authorizer
const getUserMethod = new apigateway.Method(this, 'GetUserMethod', {
  httpMethod: 'GET',
  resource: userResource,
  authorizer: authorizer,
  authorizationType: apigateway.AuthorizationType.COGNITO
});
```

### Request/Response Transformation

```yaml
# API Gateway Integration Request Mapping
Integration:
  Type: AWS
  IntegrationHttpMethod: POST
  Uri: arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:user-service/invocations
  RequestTemplates:
    application/json: |
      {
        "userId": "$input.params('id')",
        "headers": {
          #foreach($header in $input.params().header.keySet())
          "$header": "$util.escapeJavaScript($input.params().header.get($header))"
          #end
        }
      }
  IntegrationResponses:
    - StatusCode: 200
      ResponseTemplates:
        application/json: |
          {
            "user": $input.json('$'),
            "timestamp": "$context.requestTime"
          }
```

### Caching

```typescript
// Enable caching
const deploymentStage = new apigateway.Stage(this, 'Stage', {
  deployment: deployment,
  stageName: 'prod',
  cacheClusterEnabled: true,
  cacheClusterSize: '0.5', // GB
  cachingEnabled: true,
  cacheTtl: Duration.minutes(5)
});

// Cache key parameters
const getUserMethod = new apigateway.Method(this, 'GetUserMethod', {
  httpMethod: 'GET',
  resource: userResource,
  requestParameters: {
    'method.request.querystring.id': true
  },
  methodResponses: [{
    statusCode: '200',
    responseParameters: {
      'method.response.header.Cache-Control': true
    }
  }]
});
```

### WebSocket API

```typescript
// WebSocket API
const webSocketApi = new apigatewayv2.WebSocketApi(this, 'WebSocketApi', {
  connectRouteOptions: {
    integration: new integrations.LambdaWebSocketIntegration(connectHandler)
  },
  disconnectRouteOptions: {
    integration: new integrations.LambdaWebSocketIntegration(disconnectHandler)
  }
});

webSocketApi.addRoute('sendMessage', {
  integration: new integrations.LambdaWebSocketIntegration(messageHandler)
});

const stage = new apigatewayv2.WebSocketStage(this, 'Stage', {
  webSocketApi,
  stageName: 'prod',
  autoDeploy: true
});
```

## Envoy Proxy

### Architecture

Envoy is a high-performance C++ proxy designed for cloud-native applications, used as a sidecar proxy in service mesh architectures.

### Core Features

- **HTTP/2 and gRPC**: Native support for modern protocols
- **Advanced Load Balancing**: Multiple algorithms and health checking
- **Observability**: Built-in metrics, tracing, logging
- **Dynamic Configuration**: Hot-reloadable configuration via xDS API

### Basic Configuration

```yaml
# envoy.yaml
static_resources:
  listeners:
    - name: listener_0
      address:
        socket_address:
          address: 0.0.0.0
          port_value: 10000
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: ingress_http
                route_config:
                  name: local_route
                  virtual_hosts:
                    - name: local_service
                      domains: ["*"]
                      routes:
                        - match:
                            prefix: "/"
                          route:
                            cluster: user_service
                http_filters:
                  - name: envoy.filters.http.router

  clusters:
    - name: user_service
      connect_timeout: 0.25s
      type: LOGICAL_DNS
      dns_lookup_family: V4_ONLY
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: user_service
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: user-service
                      port_value: 8080
```

### Advanced Routing

```yaml
# Advanced routing with path-based and header-based routing
route_config:
  virtual_hosts:
    - name: api_service
      domains: ["api.example.com"]
      routes:
        # Path-based routing
        - match:
            path: "/api/v1/users"
          route:
            cluster: user_service_v1
        - match:
            path: "/api/v2/users"
          route:
            cluster: user_service_v2
        
        # Header-based routing
        - match:
            prefix: "/api/users"
            headers:
              - name: "x-api-version"
                exact_match: "v2"
          route:
            cluster: user_service_v2
        
        # Weighted routing (canary)
        - match:
            prefix: "/api/products"
          route:
            weighted_clusters:
              clusters:
                - name: product_service_v1
                  weight: 90
                - name: product_service_v2
                  weight: 10
```

### Rate Limiting

```yaml
# Rate limiting configuration
http_filters:
  - name: envoy.filters.http.ratelimit
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.http.ratelimit.v3.RateLimit
      domain: api_gateway
      rate_limit_service:
        grpc_service:
          envoy_grpc:
            cluster_name: rate_limit_service
  - name: envoy.filters.http.router
```

### Circuit Breaker

```yaml
# Circuit breaker configuration
clusters:
  - name: user_service
    circuit_breakers:
      thresholds:
        - priority: DEFAULT
          max_connections: 1000
          max_pending_requests: 100
          max_requests: 500
          max_retries: 3
        - priority: HIGH
          max_connections: 2000
          max_pending_requests: 200
          max_requests: 1000
```

### Observability

```yaml
# Access logging
http_filters:
  - name: envoy.filters.http.router
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
      dynamic_stats: true

# Tracing
tracing:
  http:
    name: envoy.tracers.zipkin
    typed_config:
      "@type": type.googleapis.com/envoy.config.trace.v3.ZipkinConfig
      collector_cluster: zipkin
      collector_endpoint: "/api/v2/spans"
      shared_span_context: false
```

## Spring Cloud Gateway

### Architecture

Spring Cloud Gateway is a reactive API gateway built on Spring WebFlux, providing routing, filtering, and cross-cutting concerns for Spring-based microservices.

### Basic Setup

```java
// Spring Boot Application
@SpringBootApplication
public class ApiGatewayApplication {
    public static void main(String[] args) {
        SpringApplication.run(ApiGatewayApplication.class, args);
    }
}
```

```yaml
# application.yml
spring:
  cloud:
    gateway:
      routes:
        - id: user-service
          uri: lb://user-service
          predicates:
            - Path=/api/users/**
          filters:
            - StripPrefix=2
            - name: RequestRateLimiter
              args:
                redis-rate-limiter.replenishRate: 10
                redis-rate-limiter.burstCapacity: 20
```

### Route Configuration

```java
@Configuration
public class GatewayConfig {
    
    @Bean
    public RouteLocator customRouteLocator(RouteLocatorBuilder builder) {
        return builder.routes()
            .route("user-service", r -> r
                .path("/api/users/**")
                .uri("lb://user-service"))
            .route("product-service", r -> r
                .path("/api/products/**")
                .and()
                .header("X-API-Version", "v2")
                .uri("lb://product-service-v2"))
            .route("order-service", r -> r
                .path("/api/orders/**")
                .filters(f -> f
                    .addRequestHeader("X-Gateway-Request", "true")
                    .circuitBreaker(config -> config
                        .setName("order-service-circuit")
                        .setFallbackUri("forward:/fallback/order")))
                .uri("lb://order-service"))
            .build();
    }
}
```

### Custom Filters

```java
@Component
public class AuthenticationFilter implements GatewayFilter, Ordered {
    
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();
        String authHeader = request.getHeaders().getFirst("Authorization");
        
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            ServerHttpResponse response = exchange.getResponse();
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return response.setComplete();
        }
        
        // Validate token
        String token = authHeader.substring(7);
        if (!isValidToken(token)) {
            ServerHttpResponse response = exchange.getResponse();
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return response.setComplete();
        }
        
        // Add user info to headers
        ServerHttpRequest modifiedRequest = request.mutate()
            .header("X-User-Id", extractUserId(token))
            .build();
        
        return chain.filter(exchange.mutate().request(modifiedRequest).build());
    }
    
    @Override
    public int getOrder() {
        return -100;
    }
}
```

### Rate Limiting

```java
@Configuration
public class RateLimiterConfig {
    
    @Bean
    public RedisRateLimiter redisRateLimiter() {
        return new RedisRateLimiter(10, 20, 1);
    }
    
    @Bean
    public KeyResolver userKeyResolver() {
        return exchange -> {
            String userId = exchange.getRequest()
                .getHeaders()
                .getFirst("X-User-Id");
            return Mono.just(userId != null ? userId : "anonymous");
        };
    }
}
```

### Circuit Breaker

```java
@Configuration
public class CircuitBreakerConfig {
    
    @Bean
    public RouteLocator circuitBreakerRoutes(RouteLocatorBuilder builder) {
        return builder.routes()
            .route("user-service", r -> r
                .path("/api/users/**")
                .filters(f -> f
                    .circuitBreaker(config -> config
                        .setName("user-service-circuit")
                        .setFallbackUri("forward:/fallback/user")
                        .setRouteId("user-service-fallback")))
                .uri("lb://user-service"))
            .build();
    }
    
    @RestController
    @RequestMapping("/fallback")
    public class FallbackController {
        
        @GetMapping("/user")
        public ResponseEntity<Map<String, Object>> userFallback() {
            Map<String, Object> response = new HashMap<>();
            response.put("status", "service_unavailable");
            response.put("message", "User service is temporarily unavailable");
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(response);
        }
    }
}
```

## NGINX as API Gateway

### Basic API Gateway Configuration

```nginx
# api-gateway.conf
upstream user_service {
    least_conn;
    server user-service-1:8080 max_fails=3 fail_timeout=30s;
    server user-service-2:8080 max_fails=3 fail_timeout=30s;
    server user-service-3:8080 max_fails=3 fail_timeout=30s backup;
}

upstream product_service {
    ip_hash;
    server product-service-1:8080;
    server product-service-2:8080;
}

server {
    listen 80;
    server_name api.example.com;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req zone=api_limit burst=20 nodelay;
    
    # User service routes
    location /api/users {
        limit_req zone=api_limit burst=20;
        
        proxy_pass http://user_service;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-User-ID $http_x_user_id;
        
        # Timeouts
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
        
        # Retry
        proxy_next_upstream error timeout http_502 http_503;
        proxy_next_upstream_tries 3;
    }
    
    # Product service routes
    location /api/products {
        proxy_pass http://product_service;
        proxy_set_header Host $host;
        
        # Caching
        proxy_cache api_cache;
        proxy_cache_valid 200 5m;
        proxy_cache_key "$scheme$request_method$host$request_uri";
    }
}
```

### Authentication with NGINX

```nginx
# JWT validation with lua
location /api {
    access_by_lua_block {
        local jwt = require "resty.jwt"
        local auth_header = ngx.var.http_authorization
        
        if not auth_header then
            ngx.status = 401
            ngx.say("Missing authorization header")
            ngx.exit(401)
        end
        
        local token = string.match(auth_header, "Bearer%s+(.+)")
        if not token then
            ngx.status = 401
            ngx.say("Invalid authorization header format")
            ngx.exit(401)
        end
        
        local jwt_obj = jwt:verify("your-secret-key", token)
        if not jwt_obj.valid then
            ngx.status = 401
            ngx.say("Invalid token")
            ngx.exit(401)
        end
        
        ngx.req.set_header("X-User-ID", jwt_obj.payload.user_id)
    }
    
    proxy_pass http://backend;
}
```

## Best Practices

### 1. Request Aggregation

```typescript
// Aggregate multiple service calls
app.get('/dashboard/:userId', async (req, res) => {
  const userId = req.params.userId;
  
  try {
    const [user, orders, recommendations, notifications] = await Promise.all([
      userService.getUser(userId),
      orderService.getUserOrders(userId),
      recommendationService.getRecommendations(userId),
      notificationService.getNotifications(userId)
    ]);
    
    res.json({
      user,
      orders,
      recommendations,
      notifications
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to aggregate data' });
  }
});
```

### 2. Request/Response Transformation

```typescript
// Transform request for backend compatibility
app.use('/api/v1/users', (req, res, next) => {
  // Transform request
  if (req.body) {
    req.body.api_version = 'v1';
    req.body.timestamp = new Date().toISOString();
  }
  
  // Transform response
  const originalJson = res.json;
  res.json = function(data) {
    const transformed = {
      data: data,
      meta: {
        version: 'v1',
        timestamp: new Date().toISOString()
      }
    };
    return originalJson.call(this, transformed);
  };
  
  next();
});
```

### 3. Caching Strategy

```typescript
// Multi-level caching
const cache = new Map();
const redis = new Redis();

app.get('/api/users/:id', async (req, res) => {
  const userId = req.params.id;
  const cacheKey = `user:${userId}`;
  
  // L1: In-memory cache
  if (cache.has(cacheKey)) {
    return res.json(cache.get(cacheKey));
  }
  
  // L2: Redis cache
  const cached = await redis.get(cacheKey);
  if (cached) {
    const data = JSON.parse(cached);
    cache.set(cacheKey, data);
    return res.json(data);
  }
  
  // L3: Backend service
  const user = await userService.getUser(userId);
  
  // Store in caches
  cache.set(cacheKey, user);
  await redis.setex(cacheKey, 300, JSON.stringify(user));
  
  res.json(user);
});
```

### 4. Error Handling

```typescript
// Centralized error handling
app.use((err, req, res, next) => {
  const errorResponse = {
    error: {
      code: err.code || 'INTERNAL_ERROR',
      message: err.message || 'An unexpected error occurred',
      timestamp: new Date().toISOString(),
      path: req.path
    }
  };
  
  // Log error
  logger.error('API Gateway Error', {
    error: err,
    request: {
      method: req.method,
      path: req.path,
      headers: req.headers
    }
  });
  
  // Return appropriate status
  const statusCode = err.statusCode || 500;
  res.status(statusCode).json(errorResponse);
});
```

## Performance Optimization

### Connection Pooling

```nginx
# NGINX upstream connection pooling
upstream backend {
    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
    
    server backend1:8080;
    server backend2:8080;
}
```

### Caching

- **Response Caching**: Cache responses at gateway level
- **CDN Integration**: Use CDN for static content
- **Cache Invalidation**: Smart cache invalidation strategies
- **Cache Headers**: Proper cache-control headers

### Request Batching

```typescript
// Batch multiple requests
class RequestBatcher {
  private batch: Array<{resolve: Function, reject: Function, request: any}> = [];
  private batchTimeout: NodeJS.Timeout | null = null;
  
  async add(request: any): Promise<any> {
    return new Promise((resolve, reject) => {
      this.batch.push({ resolve, reject, request });
      
      if (this.batch.length >= 10) {
        this.flush();
      } else if (!this.batchTimeout) {
        this.batchTimeout = setTimeout(() => this.flush(), 50);
      }
    });
  }
  
  private async flush() {
    if (this.batchTimeout) {
      clearTimeout(this.batchTimeout);
      this.batchTimeout = null;
    }
    
    const batch = this.batch.splice(0);
    // Execute batch requests
    const results = await Promise.all(
      batch.map(item => this.executeRequest(item.request))
    );
    
    batch.forEach((item, index) => {
      item.resolve(results[index]);
    });
  }
}
```

## Security

### Authentication & Authorization

- **JWT Validation**: Validate JWT tokens at gateway
- **OAuth2/OIDC**: Integrate with identity providers
- **API Keys**: Manage API keys and usage plans
- **mTLS**: Mutual TLS for service-to-service communication

### Rate Limiting

```typescript
// Token bucket rate limiting
class TokenBucket {
  private tokens: number;
  private lastRefill: number;
  
  constructor(
    private capacity: number,
    private refillRate: number
  ) {
    this.tokens = capacity;
    this.lastRefill = Date.now();
  }
  
  consume(tokens: number): boolean {
    this.refill();
    
    if (this.tokens >= tokens) {
      this.tokens -= tokens;
      return true;
    }
    
    return false;
  }
  
  private refill() {
    const now = Date.now();
    const elapsed = (now - this.lastRefill) / 1000;
    const tokensToAdd = elapsed * this.refillRate;
    
    this.tokens = Math.min(this.capacity, this.tokens + tokensToAdd);
    this.lastRefill = now;
  }
}
```

### WAF Integration

- **OWASP Top 10 Protection**: Protect against common vulnerabilities
- **DDoS Protection**: Mitigate distributed denial of service attacks
- **Bot Detection**: Identify and block malicious bots
- **IP Filtering**: Whitelist/blacklist IP addresses

## Monitoring & Observability

### Key Metrics

- **Request Rate**: Requests per second
- **Latency**: P50, P95, P99 latencies
- **Error Rate**: 4xx and 5xx error rates
- **Throughput**: Bytes per second
- **Active Connections**: Current active connections

### Distributed Tracing

```typescript
// Add tracing headers
app.use((req, res, next) => {
  const traceId = req.headers['x-trace-id'] || generateTraceId();
  const spanId = generateSpanId();
  
  req.traceId = traceId;
  req.spanId = spanId;
  
  res.setHeader('X-Trace-ID', traceId);
  res.setHeader('X-Span-ID', spanId);
  
  // Propagate to backend services
  req.headers['x-trace-id'] = traceId;
  req.headers['x-span-id'] = spanId;
  
  next();
});
```

### Logging

```typescript
// Structured logging
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    
    logger.info('API Gateway Request', {
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      duration,
      userAgent: req.headers['user-agent'],
      ip: req.ip,
      traceId: req.traceId
    });
  });
  
  next();
});
```

## Production Deployment Patterns

### High Availability

- Deploy multiple gateway instances
- Use load balancer in front of gateways
- Distribute across availability zones
- Implement health checks and auto-scaling

### Canary Deployments

```yaml
# Canary deployment with Envoy
route_config:
  virtual_hosts:
    - name: api_service
      routes:
        - match:
            prefix: "/api/users"
          route:
            weighted_clusters:
              clusters:
                - name: user_service_v1
                  weight: 95
                - name: user_service_v2
                  weight: 5
```

### Blue-Green Deployments

- Deploy new gateway version alongside old
- Route traffic gradually to new version
- Monitor metrics and errors
- Rollback if issues detected

This comprehensive guide provides enterprise-grade API Gateway patterns and implementations for building scalable, secure microservices architectures with production-ready configurations and best practices.

