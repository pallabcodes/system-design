# Proxy Architecture: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Forward vs Reverse, Transparent Proxies, Nginx Tuning, and Envoy.

> [!IMPORTANT]
> **The Principal Law**: **Proxies are the Nervous System**. They control visibility, routing, and resilience. A bad proxy config kills the best backend.

---

## 🚦 Types of Proxies

### 1. Reverse Proxy (The Shield)
*   **Sit in front of**: Servers.
*   **Protects**: The Backend (hides IP, handles TLS, absorbs DDoS).
*   **Examples**: Nginx, HAProxy, AWS ALB.
*   **Use Case**: Load Balancing, SSL Termination, Caching.

### 2. Forward Proxy (The Tunnel)
*   **Sit in front of**: Clients.
*   **Protects**: The User (hides User IP, filters outgoing traffic).
*   **Examples**: Squid, Zscaler.
*   **Use Case**: Corporate Firewall (Employee traffic filtering), Scraping (Rotation).

### 3. Transparent Proxy
*   **Mechanism**: Intercepts traffic at the network layer (IPtables/eBPF) without the client knowing.
*   **Use Case**: Service Mesh (Istio), ISP Caching.

---

## 🛠️ Nginx Tuning: The God Mode

Nginx defaults are for simplistic hosting. Production needs tuning.

### 1. Worker Processes & Connections
```nginx
# Auto-detect cores. Bind 1 worker to 1 CPU core to avoid Context Switching.
worker_processes auto; 

events {
    # File usage limit (ulimit -n)
    worker_connections 10000; 
    
    # Accept as many connections as possible per event loop
    multi_accept on; 
    
    # Efficient polling on Linux
    use epoll; 
}
```

### 2. Keepalive (The Latency Killer)
By default, Nginx connects to upstream, sends request, and closes.
**Bad**: expensive TCP handshake + TLS handshake per request.
**Good**: Reuse connections.

```nginx
upstream backend {
    server 10.0.0.1:8080;
    
    # Keep 100 idle connections open to the backend
    keepalive 100;
}

server {
    location / {
        proxy_pass http://backend;
        
        # Required for keepalive to work
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
```

### 3. Buffering (The I/O Optimization)
*   **Request Buffering (ON)**: Nginx reads the whole body from Client (slow mobile) before sending to Backend (fast). Frees up Backend threads.
*   **Response Buffering (ON)**: Nginx reads whole response from Backend (fast) before trickling to Client (slow). Frees up Backend memory.
*   **Streaming (OFF)**: If you are doing Server-Sent Events (SSE) or WebSockets, turn buffering **OFF**.

---

## ✅ Principal Architect Checklist

1.  **Terminate TLS Early**: Do not let your Java/Node app handle encryption. It burns CPU. Let Nginx/Envoy do it (AES-NI hardware acceleration).
2.  **Header Sanitization**: Always strip internal headers (`X-Powered-By`, `Server`) at the proxy. Don't leak stack details.
3.  **Request ID Propagation**: Generate `X-Request-ID` at the Edge (Nginx) and pass it everywhere for distributed tracing.
4.  **Graceful Reloads**: Nginx supports `nginx -s reload`. Use it. Never restart the process for a config change.

---

## 🔗 Related Documents
*   [Service Mesh](../../mesh/service-mesh-architecture-guide.md) — Envoy (The modern proxy).
*   [Load Balancers](../../load-balancers-techniques/nginx.md) — Fundamental LB techniques.
