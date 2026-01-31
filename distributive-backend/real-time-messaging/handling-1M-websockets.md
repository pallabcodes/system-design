Resource: https://youtu.be/YiCCD5DPry8 (very important)



Based on the presentation by Eran Yanay titled "Going Infinite: Handling 1 Million Websocket Connections in Go," here is a comprehensive extraction of the content from start to end.

### **Introduction and Goal**
Eran Yanay, an Engineering Manager at Twistlock (acquired by Palo Alto Networks), presents a technical, hands-on talk about scaling a Go application to handle one million concurrent WebSocket connections. The presentation aims to demonstrate the challenges faced when scaling to such high numbers, including limitations within the Go language, the operating system, and hardware resources like memory.

### **The Basic Go Web Server**
The talk begins with a simple example of a Go web server. It uses a handler that returns a "hello" string, associated with the main route, and starts listening on port 8000.
*   **How Go Handles Connections:** When `ListenAndServe` is called, a `Serve` function waits for incoming connections. Upon accepting a connection, it spawns a new goroutine to invoke the associated handler.

### **WebSockets Overview**
WebSockets maintain a full-duplex persistent connection, allowing both client and server to send data at any time with low latency.
*   **The Handshake:** The client sends an HTTP request with an `Upgrade` header. If the server supports the protocol, it replies with an `Upgrade` header to complete the handshake.
*   **Go Implementation:** The official Go documentation notes that the standard WebSocket package lacks features and recommends using third-party libraries. Yanay demonstrates using a third-party library where an `Upgrader` interface wraps the network connection to read and write messages.

### **Challenge 1: File Descriptors (The 1K Limit)**
In the first demo, opening 10 connections works fine, but attempting 2,000 connections results in an `accept: too many open files` error.
*   **The Cause:** In Linux, every resource (files, standard output, socket connections) is represented by a file descriptor. The operating system limits memory usage for open files.
*   **ulimit:** The `ulimit` tool reveals a default soft limit of 1024 open files. Once the application exceeds this (one descriptor per socket), it crashes.
*   **Soft vs. Hard Limits:** The kernel enforces a soft limit (the actual ceiling) and a hard limit (the maximum a soft limit can be raised to). A privileged process can raise the soft limit up to the hard limit.
*   **The Fix:** While `ulimit` can be changed via the command line, it can also be changed programmatically in Go using the `syscall` package (`Getrlimit` to fetch and `Setrlimit` to increase the limit).

### **Challenge 2: Memory Usage (The 50K Limit)**
After fixing the file limit, the server successfully handles 2,000 connections. Scaling to 50,000 connections works but reveals high resource consumption: roughly 1GB of RAM. Yanay uses `pprof` (a Go profiling tool) for deeper analysis rather than relying solely on `top`.
*   **Goroutine Analysis:** The profile shows over 50,000 goroutines. Each connection spawns a goroutine (via `ServeHTTP` -> WebSocket handler) that mostly sleeps/waits for data.
*   **Heap Analysis:** Memory analysis shows the application uses about 700MB. This is driven by three main allocations per connection:
    1.  The HTTP package allocating a 4KB buffer for the request reader.
    2.  Another 4KB buffer for the writer.
    3.  The WebSocket upgrade/hijack mechanism allocating another 4KB buffer.
*   **The Projection:** With each connection requiring a goroutine and multiple buffers, 1 million connections would consume approximately 20GB of RAM.

### **Optimization 1: Reducing Goroutines (Epoll)**
To reduce memory, the reliance on one goroutine per connection must be removed.
*   **Async I/O:** Instead of blocking a goroutine while waiting for data, Linux offers Async I/O options like `select`, `poll`, and `epoll`.
*   **Epoll vs. Select/Poll:** `select` and `poll` are simple but perform poorly at scale. `epoll` is scalable and provides constant performance regardless of connection count.
*   **Implementation:** Using `epoll`, the application creates an instance (`EpollCreate`), registers connections (`EpollCtl`), and waits for events (`EpollWait`). This allows a single thread/goroutine to monitor many connections, drastically reducing the goroutine count.

### **Optimization 2: Reducing Buffers (Zero-Copy Library)**
Even with `epoll`, the standard `net/http` and WebSocket libraries allocate buffers that persist.
*   **The Issue:** The `Hijack` call in the standard update mechanism keeps references to reader/writer buffers, preventing reuse.
*   **The Solution (`gobwas`):** Yanay switches to the `gobwas/ws` library. This library is optimized for performance, offering zero intermediate allocations during I/O, zero-copy upgrades, and a low-level API that allows for better buffer management (e.g., reusing a single buffer or a pool across connections).

### **Challenge 3: Conntrack (The 260K Limit)**
With `epoll` and `gobwas` implemented, the server scales to ~240,000 connections efficiently. However, pushing toward 300,000 triggers a new error in the kernel log: `nf_conntrack: table full`.
*   **The Cause:** `nf_conntrack` (Netfilter Connection Tracking) is a Linux mechanism used by firewalls/IPTables to track the state of connections. To prevent Denial of Service (DoS) attacks and save memory, this table is capped by default at approximately 262,000 entries.
*   **The Fix:** The limit can be raised by writing a higher value to the system file `/proc/sys/net/netfilter/nf_conntrack_max`.

### **Testing Methodology: Scaling to 1 Million**
To test 1 million connections from a single laptop, Yanay encounters the **ephemeral port limit**.
*   **The Barrier:** When opening outgoing connections, Linux allocates a source port from a range limited to about 30,000 ports per IP address.
*   **The Workaround:** He uses Docker to run clients in separate network namespaces. This isolates their networking stacks, allowing each container to open ~30,000 connections, bypassing the host's single IP limit.

### **Final Results and Summary**
After applying all optimizations, the server successfully handles 1 million concurrent connections.
*   **Resource Usage:** The optimized application uses roughly 700MB of RAM for 1 million connections, a 97% reduction from the initial projection of 20GB.
*   **Recap of Steps:**
    1.  **File Descriptors:** Increased limits via `ulimit`/`syscall` to bypass the 1,024 cap.
    2.  **Goroutines:** Implemented `epoll` to remove the 1-goroutine-per-connection requirement.
    3.  **Buffers:** Switched to `gobwas/ws` to minimize buffer allocations.
    4.  **Conntrack:** Increased `nf_conntrack_max` to allow tracking more than 262,000 connections.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
This is a "C10M" (10 Million Concurrent Connections) style ultra-optimization. The techniques (bypassing the Go runtime's one-goroutine-per-conn model in favor of raw `epoll`) are still valid for *maximizing* a single machine's throughput. However, the Go runtime itself has become much more efficient since 2017-2018 (async preemption, better GC), making the standard library capable of handling significantly higher loads than before without such drastic hacks.

**Is it scalable?**
**Yes**, extremely. This architecture is designed for vertical scalability limits. However, optimizing for 1M connections on a *single* node is often considered an anti-pattern in modern cloud engineering due to **Blast Radius**. If that one super-node fails, 1 million clients simultaneously disconnect and try to reconnect (Thundering Herd), essentially DDoS-ing your system.

**What would the architecture look like today?**
1.  **io_uring:** On modern Linux kernels (5.1+), **io_uring** provides a more efficient async I/O interface than `epoll`, allowing for true async submission and completion queues with fewer syscalls. Modern high-perf Go libraries (like `gnet`) are moving towards `io_uring`.
2.  **Horizontal vs Vertical:** Today, we prioritize **Horizontal Scalability**. Instead of tuning one box to hold 1M connections, we would run 20 pods holding 50k connections each on Kubernetes. This is safer and easier to manage.
3.  **QUIC / HTTP/3:** We might use QUIC (UDP) instead of TCP for better performance over unreliable networks, avoiding Head-of-Line blocking.
4.  **eBPF / XDP:** For even more extreme performance (preventing packets from even reaching the standard kernel network stack), modern edge-proxies usage eBPF/XDP, though this is usually for load balancers (Cilium, Katran) rather than application servers.