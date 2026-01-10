# NGINX Comprehensive Guide

## Overview

NGINX is a high-performance web server, reverse proxy, load balancer, and HTTP cache that powers over 400 million websites worldwide. This comprehensive guide covers production-ready configurations, advanced load balancing, security, performance optimization, and enterprise patterns.

## Core Concepts

### Architecture
```nginx
# Main contexts (processed in order)
events {        # Connection processing
    worker_connections 1024;
}

http {          # HTTP server configuration
    upstream backend {
        server backend1.example.com:8080;
        server backend2.example.com:8080;
    }

    server {     # Virtual server
        listen 80;
        location / {
            proxy_pass http://backend;
        }
    }
}
```

### Process Model
- **Master Process**: Reads configuration, manages worker processes
- **Worker Processes**: Handle connections (default: 1 per CPU core)
- **Cache Manager/Load Processes**: Handle disk caching and loading

## Load Balancing Algorithms

### Round Robin (Default)
```nginx
upstream backend {
    server backend1.example.com;
    server backend2.example.com;
    server backend3.example.com;
}
```
**Behavior**: Distributes requests sequentially across servers

### Weighted Round Robin
```nginx
upstream backend {
    server backend1.example.com weight=3;
    server backend2.example.com weight=2;
    server backend3.example.com weight=1;
}
```
**Use Case**: When servers have different capacities

### Least Connections
```nginx
upstream backend {
    least_conn;
    server backend1.example.com;
    server backend2.example.com;
    server backend3.example.com;
}
```
**Behavior**: Routes to server with fewest active connections

### IP Hash
```nginx
upstream backend {
    ip_hash;
    server backend1.example.com;
    server backend2.example.com;
    server backend3.example.com;
}
```
**Behavior**: Routes requests from same IP to same server (session persistence)

### Least Time (Commercial NGINX Plus)
```nginx
upstream backend {
    least_time header;
    server backend1.example.com;
    server backend2.example.com;
}
```
**Behavior**: Routes based on response time (header, last_byte)

### Random with Two Choices
```nginx
upstream backend {
    random two;
    server backend1.example.com;
    server backend2.example.com;
    server backend3.example.com;
}
```
**Behavior**: Selects two servers randomly, chooses one with fewer connections

## Health Checks and Failover

### Passive Health Checks
```nginx
upstream backend {
    server backend1.example.com:8080 max_fails=3 fail_timeout=30s;
    server backend2.example.com:8080 max_fails=3 fail_timeout=30s;
    server backend3.example.com:8080 max_fails=3 fail_timeout=30s;
}
```
- `max_fails`: Number of failures before marking server down
- `fail_timeout`: Time server is marked down + time between checks

### Active Health Checks (NGINX Plus)
```nginx
upstream backend {
    zone backend 64k;
    server backend1.example.com:8080;
    server backend2.example.com:8080;

    sticky learn create=$upstream_cookie_session
           lookup=$cookie_session
           zone=client_sessions:1m;
}

server {
    location /health {
        health_check uri=/status
                      interval=2s
                      fails=2
                      passes=5
                      match=ok;
    }
}

match ok {
    status 200;
    header Content-Type = text/html;
    body ~ "status ok";
}
```

## Reverse Proxy Configuration

### Basic Reverse Proxy
```nginx
server {
    listen 80;
    server_name example.com;

    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Advanced Proxy Configuration
```nginx
server {
    listen 80;
    server_name api.example.com;

    location /api/ {
        # Backend configuration
        proxy_pass http://api_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        # Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;

        # Buffering
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;

        # Error handling
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 30s;

        # SSL
        proxy_ssl_verify on;
        proxy_ssl_verify_depth 2;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
    }
}
```

## SSL/TLS Configuration

### Basic SSL Setup
```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    ssl_certificate /etc/ssl/certs/example.com.crt;
    ssl_certificate_key /etc/ssl/private/example.com.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://backend;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name example.com;
    return 301 https://$server_name$request_uri;
}
```

### Advanced SSL Configuration
```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    # SSL Configuration
    ssl_certificate /etc/ssl/certs/example.com.crt;
    ssl_certificate_key /etc/ssl/private/example.com.key;
    ssl_trusted_certificate /etc/ssl/certs/example.com.ca.crt;

    # Protocols and Ciphers
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;

    # Session caching
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    location / {
        proxy_pass http://backend;
    }
}
```

### Let's Encrypt SSL Automation
```nginx
server {
    listen 80;
    server_name example.com www.example.com;

    # ACME challenge for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }

    # Redirect all other HTTP traffic to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name example.com www.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # Include SSL configuration
    include /etc/nginx/ssl.conf;

    location / {
        proxy_pass http://backend;
    }
}
```

## Caching Configuration

### Proxy Cache
```nginx
# HTTP context
proxy_cache_path /tmp/nginx_cache levels=1:2 keys_zone=cache:10m max_size=1g
                 inactive=60m use_temp_path=off;

server {
    listen 80;
    server_name example.com;

    location /api/ {
        proxy_pass http://api_backend;

        # Caching
        proxy_cache cache;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        proxy_cache_valid 200 302 10m;
        proxy_cache_valid 404 1m;
        proxy_cache_use_stale error timeout invalid_header updating;

        # Cache bypass
        proxy_cache_bypass $http_upgrade $http_cache_control;

        # Headers
        add_header X-Cache-Status $upstream_cache_status;
    }
}
```

### Microcaching for Dynamic Content
```nginx
proxy_cache_path /tmp/microcache levels=1:2 keys_zone=microcache:10m max_size=1g
                 inactive=1m use_temp_path=off;

location /api/dynamic/ {
    proxy_pass http://api_backend;

    proxy_cache microcache;
    proxy_cache_key "$scheme$request_method$host$request_uri$is_args$args";
    proxy_cache_valid 200 1m;  # Cache for 1 minute
    proxy_cache_use_stale updating;

    # Bypass cache for authenticated users
    proxy_cache_bypass $cookie_session;
    proxy_no_cache $cookie_session;
}
```

## Rate Limiting

### Basic Rate Limiting
```nginx
# HTTP context
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;

server {
    location /api/ {
        limit_req zone=api burst=20 nodelay;

        # Custom error page
        limit_req_status 429;

        proxy_pass http://api_backend;
    }

    location /auth/login {
        limit_req zone=login burst=10 nodelay;
        proxy_pass http://auth_backend;
    }
}
```

### Advanced Rate Limiting
```nginx
# Multiple zones for different scenarios
limit_req_zone $binary_remote_addr zone=strict:10m rate=5r/s;
limit_req_zone $server_name$binary_remote_addr zone=per_server:10m rate=100r/s;
limit_req_zone $http_x_forwarded_for zone=behind_proxy:10m rate=50r/s;

# Connection limiting
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
limit_conn_zone $server_name zone=server_conn:10m;

server {
    # Connection limits
    limit_conn conn_limit 10;
    limit_conn server_conn 100;

    location /api/ {
        # Multiple rate limits
        limit_req zone=strict burst=10 nodelay;
        limit_req zone=per_server burst=50 nodelay;

        # Dry run mode (log only)
        limit_req_dry_run on;

        proxy_pass http://api_backend;
    }
}
```

## Security Configuration

### Basic Security Headers
```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy strict-origin-when-cross-origin;
    add_header Content-Security-Policy "default-src 'self'";

    # Remove server header
    more_clear_headers Server;

    location / {
        proxy_pass http://backend;
    }
}
```

### DDoS Protection
```nginx
# Limit concurrent connections
limit_conn_zone $binary_remote_addr zone=ddos:10m;
limit_conn ddos 10;

# Rate limiting for suspicious patterns
limit_req_zone $binary_remote_addr zone=ddos_req:10m rate=10r/s;

# Block bad user agents
if ($http_user_agent ~* "(nmap|nikto|dirbuster|sqlmap|wpscan)") {
    return 444;
}

# Block bad referers
if ($http_referer ~* "(spam-site|malicious-site)") {
    return 444;
}

location / {
    limit_req zone=ddos_req burst=20 nodelay;

    # Geo-blocking (requires geoip module)
    if ($geoip_country_code ~ (RU|CN|KP)) {
        return 444;
    }

    proxy_pass http://backend;
}
```

### Web Application Firewall (ModSecurity)
```nginx
server {
    listen 80;
    server_name example.com;

    # ModSecurity
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsecurity/modsecurity.conf;

    location / {
        modsecurity_rules '
            SecRule REQUEST_URI "@contains ../" "id:101,phase:2,t:lowercase,deny,status:404,msg:'Directory traversal attack'"
            SecRule ARGS "@contains <script>" "id:102,phase:2,t:lowercase,deny,status:403,msg:'XSS attack detected'"
        ';

        proxy_pass http://backend;
    }
}
```

## Performance Optimization

### Worker Configuration
```nginx
# Main context
user nginx;
worker_processes auto;
worker_rlimit_nofile 65536;

events {
    worker_connections 2048;
    use epoll;  # Linux
    multi_accept on;
}

http {
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        application/atom+xml
        application/geo+json
        application/javascript
        application/x-javascript
        application/json
        application/ld+json
        application/manifest+json
        application/rdf+xml
        application/rss+xml
        application/xhtml+xml
        application/xml
        font/eot
        font/otf
        font/ttf
        image/svg+xml
        text/css
        text/javascript
        text/plain
        text/xml;

    # Brotli compression (if available)
    brotli on;
    brotli_comp_level 6;
    brotli_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;
}
```

### Static File Optimization
```nginx
server {
    listen 80;
    server_name static.example.com;

    # Static file serving
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";

        # Security headers for static files
        add_header X-Content-Type-Options nosniff;

        # CORS for fonts
        location ~* \.(woff|woff2|ttf|eot)$ {
            add_header Access-Control-Allow-Origin *;
        }

        try_files $uri @proxy;
    }

    location @proxy {
        proxy_pass http://backend;
    }
}
```

## Microservices Configuration

### API Gateway Pattern
```nginx
# Upstream for microservices
upstream auth_service {
    server auth-service:8080;
}

upstream user_service {
    server user-service:8080;
}

upstream product_service {
    server product-service:8080;
}

upstream order_service {
    server order-service:8080;
}

server {
    listen 80;
    server_name api.example.com;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_gateway:10m rate=100r/s;
    limit_req zone=api_gateway burst=200 nodelay;

    # Authentication endpoint
    location /auth/ {
        limit_req zone=api_gateway burst=50 nodelay;
        proxy_pass http://auth_service;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # User management
    location /users/ {
        auth_request /auth/verify;
        proxy_pass http://user_service;
    }

    # Products (public access)
    location /products/ {
        proxy_pass http://product_service;
        proxy_cache product_cache;
    }

    # Orders (authenticated)
    location /orders/ {
        auth_request /auth/verify;
        proxy_pass http://order_service;
    }

    # Health checks
    location /health {
        access_log off;
        return 200 "healthy\n";
    }
}

# Auth verification endpoint
server {
    listen 8080;
    server_name auth.example.com;

    location /verify {
        internal;
        proxy_pass http://auth_service/verify;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI $request_uri;
    }
}
```

### Service Mesh with NGINX
```nginx
# Service discovery with DNS
upstream api_services {
    server api-service.service.consul resolve;
    server api-service-2.service.consul resolve;
}

# Health checks
server {
    listen 80;
    server_name health.example.com;

    location / {
        health_check uri=/status
                      interval=5s
                      fails=3
                      passes=2
                      match=status_ok;
    }
}

match status_ok {
    status 200;
    body ~ "status.*ok";
}

# Circuit breaker pattern
upstream payment_service {
    server payment-1:8080 max_fails=3 fail_timeout=30s;
    server payment-2:8080 max_fails=3 fail_timeout=30s;

    # Fallback to degraded service
    server degraded-payment:8080 backup;
}
```

## Monitoring and Logging

### Access Logging
```nginx
http {
    # Custom log format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    log_format json escape=json
    '{'
        '"time": "$time_iso8601",'
        '"remote_addr": "$remote_addr",'
        '"request": "$request",'
        '"status": $status,'
        '"body_bytes_sent": $body_bytes_sent,'
        '"request_time": $request_time,'
        '"upstream_response_time": "$upstream_response_time",'
        '"http_referer": "$http_referer",'
        '"http_user_agent": "$http_user_agent"'
    '}';

    access_log /var/log/nginx/access.log main;
    access_log /var/log/nginx/access.json json;

    server {
        # Override logging for sensitive endpoints
        location /admin/ {
            access_log /var/log/nginx/admin.log main;
        }

        location /health {
            access_log off;  # Disable logging for health checks
        }
    }
}
```

### Error Logging
```nginx
http {
    error_log /var/log/nginx/error.log warn;
    error_log /var/log/nginx/error_debug.log debug;

    server {
        # Custom error pages
        error_page 404 /404.html;
        error_page 500 502 503 504 /50x.html;

        location = /50x.html {
            root /usr/share/nginx/html;
        }

        # Log errors for debugging
        location /debug {
            error_log /var/log/nginx/debug.log debug;
            return 200 "Debug mode enabled\n";
        }
    }
}
```

### Metrics with Stub Status
```nginx
server {
    listen 80;
    server_name metrics.example.com;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny all;
    }

    # Prometheus metrics (with nginx-prometheus-exporter)
    location /metrics {
        proxy_pass http://127.0.0.1:9113/metrics;
        access_log off;
    }
}
```

## Kubernetes Integration

### NGINX Ingress Controller
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /auth
        pathType: Prefix
        backend:
          service:
            name: auth-service
            port:
              number: 8080
      - path: /users
        pathType: Prefix
        backend:
          service:
            name: user-service
            port:
              number: 8080
      - path: /products
        pathType: Prefix
        backend:
          service:
            name: product-service
            port:
              number: 8080
```

### ConfigMap for NGINX Configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    events {
        worker_connections 1024;
    }

    http {
        upstream backend {
            server app-service:8080;
        }

        server {
            listen 80;
            location / {
                proxy_pass http://backend;
                proxy_set_header Host $host;
            }

            # Health check endpoint
            location /health {
                access_log off;
                return 200 "healthy\n";
            }
        }
    }
```

## Production Deployment

### Docker Configuration
```dockerfile
FROM nginx:alpine

# Copy custom configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY ssl/ /etc/ssl/certs/

# Copy static files
COPY static/ /usr/share/nginx/html/

# Create cache directory
RUN mkdir -p /tmp/nginx_cache && chown nginx:nginx /tmp/nginx_cache

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/health || exit 1

EXPOSE 80 443
```

### SystemD Service
```ini
[Unit]
Description=NGINX - high performance web server
Documentation=https://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /var/run/nginx.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
```

### Ansible Deployment
```yaml
---
- name: Install and configure NGINX
  hosts: webservers
  become: yes

  tasks:
    - name: Install NGINX
      apt:
        name: nginx
        state: present

    - name: Copy NGINX configuration
      template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      notify: reload nginx

    - name: Copy SSL certificates
      copy:
        src: "{{ item }}"
        dest: "/etc/ssl/certs/{{ item | basename }}"
      loop:
        - example.com.crt
        - example.com.key
      notify: reload nginx

    - name: Enable NGINX service
      service:
        name: nginx
        enabled: yes
        state: started

  handlers:
    - name: reload nginx
      service:
        name: nginx
        state: reloaded
```

## Troubleshooting

### Common Issues

#### High CPU Usage
```bash
# Check worker processes
ps aux | grep nginx

# Check configuration syntax
nginx -t

# Enable debug logging
error_log /var/log/nginx/error.log debug;
```

#### Memory Issues
```nginx
# Limit worker processes
worker_processes 4;

# Limit connections
worker_connections 512;

# Monitor memory usage
worker_rlimit_core 500m;
```

#### SSL Handshake Failures
```bash
# Test SSL connection
openssl s_client -connect example.com:443 -servername example.com

# Check certificate validity
openssl x509 -in /etc/ssl/certs/example.com.crt -text -noout
```

#### Performance Issues
```bash
# Check current connections
netstat -antp | grep :80 | wc -l

# Monitor NGINX status
curl http://localhost/nginx_status

# Profile with strace
strace -p $(pgrep nginx | head -1) -c
```

## Best Practices

### Security
1. **Keep NGINX updated** with latest security patches
2. **Use strong SSL/TLS configurations** with modern ciphers
3. **Implement proper access controls** and rate limiting
4. **Regularly audit configurations** and access logs
5. **Use security headers** and CSP policies

### Performance
1. **Tune worker processes** based on CPU cores
2. **Enable compression** for text-based content
3. **Implement caching** for static and dynamic content
4. **Use appropriate load balancing algorithms**
5. **Monitor and optimize** based on metrics

### Monitoring
1. **Enable detailed logging** for troubleshooting
2. **Monitor key metrics** (connections, requests, errors)
3. **Set up alerts** for critical issues
4. **Regularly review logs** for anomalies
5. **Use APM tools** for detailed performance analysis

### Scalability
1. **Horizontal scaling** with multiple NGINX instances
2. **Load balancing** across multiple backend servers
3. **Content delivery networks** for global distribution
4. **Microcaching** for dynamic content
5. **Connection pooling** and keep-alive connections

This comprehensive NGINX guide provides production-ready configurations for high-performance, secure, and scalable web infrastructure. From basic reverse proxy setups to advanced microservices architectures, these patterns cover enterprise-grade deployment scenarios.
