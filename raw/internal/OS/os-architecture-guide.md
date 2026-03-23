# OS Architecture: The Principal Architect Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Processes vs Threads, Concurrency Models, and I/O (Epoll).

> [!IMPORTANT]
> **The Principal Law**: **Context Switching is the Enemy**. Every time the CPU switches from User Mode to Kernel Mode, or from Thread A to Thread B, you lose ~1-5 microseconds.
> Use **Async I/O** (Epoll/Kqueue) or **Pinned Threads** to win.

---

## 🧵 Concurrency Models

### 1. Process vs Thread
*   **Process**: Separate Memory Space. Heavy creation (fork). Safe (crash doesn't kill others).
    *   *Example*: Chrome Tabs, Nginx Workers, PostgreSQL.
*   **Thread**: Shared Memory Space. Light creation. Dangerous (one segfault kills the process).
    *   *Example*: Java/Go applications, MySQL.

### 2. The 10k Problem (C10k)
How to handle 10,000 concurrent connections?
*   **Thread-per-Connection** (Apache/Tomcat): 10k threads.
    *   *Result*: Context switching kills CPU. constant memory overhead (1MB stack * 10k = 10GB RAM).
*   **Event Loop / Non-Blocking I/O** (Node.js/Nginx/Redis): 1 thread.
    *   *Result*: Zero switching. Very fast.
    *   *Risk*: CPU-bound work blocks everyone.

---

## 🧠 Memory Management

### 1. Stack vs Heap
*   **Stack**: Local variables. Fast (L1 Cache). Frees automatically.
*   **Heap**: Objects (`new User()`). Slow (Pointer chasing). Needs GC (Garbage Collection).

### 2. Virtual Memory & Paging
*   **Swap**: When RAM is full, OS writes pages to Disk.
*   **Principal Rule**: If your DB starts Swapping, **it is effectively down**. Disable Swap or set `swappiness=0` for production databases.

---

## ⚡ I/O Models

### 1. Blocking I/O
*   `read()` waits forever. Thread sleeps.

### 2. Non-Blocking I/O (O_NONBLOCK)
*   `read()` returns `EAGAIN` if no data. Thread spins (CPU burn).

### 3. I/O Multiplexing (Select/Poll -> Epoll)
*   **Select**: "Here are 1000 connections. Tell me who is ready." (O(N) scan). Slow.
*   **Epoll (Linux)**: "Register these 1000 connections. Wake me up only when one has data." (O(1)).
*   **This is why Nginx/Node.js/Redis are fast.**

---

## ✅ Principal Architect Checklist

1.  **File Descriptors (FD)**: Everything is a file (Sockets, Pipes). `ulimit -n` defaults to 1024. Production needs 65535 or higher.
2.  **Load Average**: `Load 1.0` on 4 cores = 25% busy. `Load 4.0` on 4 cores = 100% busy. `Load 40.0` = System is melting.
3.  **NUMA (Non-Uniform Memory Access)**: On big servers, CPU 1 accessing RAM 2 is slow. Pin processes to CPU 1 + RAM 1 for nanosecond optimization.

---

## 🔗 Related Documents
*   [Redis Deep Dive](../../distributive-backend/database/redis-deep-dive-guide.md) — Single-threaded architecture.
*   [Proxy Architecture](../../load-balancers-techniques/proxy-architecture-guide.md) — Nginx worker model.
