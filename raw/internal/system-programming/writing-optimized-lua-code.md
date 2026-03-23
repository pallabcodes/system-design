Resource: https://youtu.be/FfhEdF40nhQ

Based on the transcript of the presentation "Writing optimal Lua code for LuaJIT and OpenResty" by Yichun Zhang (agentzh), here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Context**
Yichun Zhang, a web agent at CloudFlare and creator of OpenResty, introduces the session. He notes that while the title suggests optimizing Lua code, the talk focuses more broadly on optimizing **real-world applications**, targeting OpenResty and LuaJIT users.

**What is OpenResty?**
OpenResty is described fundamentally as **Nginx + LuaJIT**.
*   **Process Model:** It uses a standard Nginx Master Process which forks multiple Worker Processes.
*   **Architecture:** Each worker process has a shared LuaJIT Virtual Machine (VM) instance. This ensures that all concurrent requests handled by a single worker share a single VM. This approach avoids wasting VM instances and allows for cheap state sharing across concurrent requests.
*   **Hooks:** OpenResty provides hooks into different request processing phases of Nginx, allowing users to script the server at a low level.

### **Performance Visualization: The Flame Graph**
To identify bottlenecks, Zhang advocates for **Flame Graphs**, a visualization method invented by Brendan Gregg (formerly of Sun Microsystems).

*   **The Concept:** Zhang uses a "My Day" analogy to explain. If his day is a bar, parts are split into "Processing Email" (30%), which splits further into "Bug Fixes" (10%) and "Verifying Issues".
*   **The Graph:** The x-axis represents the population (width indicates frequency/resource usage), and the y-axis represents the stack depth (call stack). Colors are random.
*   **The Goal:** Optimize the bottlenecks (wide bars) rather than focusing on functions that only take up 5% of execution time.
*   **The Stack:** Optimization requires looking at the whole system stack:
    1.  Operating System Kernel (Bottom)
    2.  System Software (Databases, HTTP Servers)
    3.  VM Implementations (JVM, LuaJIT)
    4.  Scripting Languages (Lua, PHP) (Top)

**Dynamic Tracing (SystemTap)**
To inspect these layers in production without stopping the system, Zhang uses **SystemTap** (similar to DTrace).
*   **Mechanism:** You write a script, and SystemTap compiles it into a Linux kernel module loaded on the fly.
*   **Probes:** It uses `uprobes` to probe user space and `kprobes` to probe the kernel. This allows safe inspection of the entire stack (User + Kernel) simultaneously.

### **Optimizing IO Performance**
Zhang ranks IO as the most critical metric because IO systems (disk/network) are slow compared to CPUs.

**Network IO**
*   **Goal:** Network IO must be **non-blocking** to achieve C10K (handling 10k+ concurrent connections). OpenResty handles millions of concurrent connections by ensuring IO never blocks operating system threads.
*   **The Trap:** Users are free to use Lua libraries that were not designed for OpenResty. These often block heavily.

**Off-CPU Flame Graphs**
To detect blocking, Zhang uses "Off-CPU" flame graphs, which measure the time a process spends waiting (sleeping) rather than running.
*   **Tool:** `sample-bt` (SystemTap script). It requires no collaboration/modification from the target process.
*   **Case Study:** Zhang displays a real production graph where Nginx was slow. The graph showed time spent in `open_file` and `rename`. Nginx usually handles file IO in a blocking manner.
*   **Solution:** They enabled the Nginx file open cache, and the blocking disappeared from the graph.

**OpenResty’s IO Model**
*   **Cosockets:** OpenResty uses coroutines to manage IO. It implements "Light Threads" which are entirely user-space constructs managed by a Lua scheduler, not OS threads.
*   **Synchronization:** It includes Lua-land semaphores for safe synchronization between light threads without deadlocks (due to timeouts).
*   **Full Duplex:** Sockets are full duplex, meaning one light thread can read while another writes to the same socket object simultaneously without locking.
*   **Timers and Sleep:** OpenResty provides asynchronous timers and `ngx.sleep`, which are non-blocking and detach from the current session.

### **Optimizing CPU Performance**
When IO is non-blocking, the CPU becomes the next bottleneck.

**On-CPU Flame Graphs**
These measure time spent actually running on CPU cores.
*   **Sampling:** Zhang emphasizes sampling (e.g., 5 seconds) over instrumentation to minimize overhead in production.
*   **Analysis:** A sample graph shows time spent in `gzip` (compression) and areas without symbols (JIT compiled code).
*   **LuaJIT Bottlenecks:** Zhang shows an example where `lj_alloc` (allocator) appeared frequently. It turned out to be an issue with the stack unwinder in LuaJIT's allocator, which Mike Pall (LuaJIT creator) fixed after Zhang reported it.
*   **Mixed Flame Graphs:** OpenResty tools can generate graphs that mix C-land and Lua-land frames, allowing developers to see if a Lua function calls a C function that becomes a bottleneck.
*   **Lua-Only Flame Graphs:** Using `lj-lua-stacks` (SystemTap), one can generate Lua-specific graphs. This is superior to the built-in LuaJIT profiler because it is non-intrusive, has no overhead after sampling stops, and doesn't alter the process state (no flushing of JIT traces required).

### **Lua Code Optimizations**
Zhang details specific coding practices to avoid bottlenecks in LuaJIT.

**1. Tables**
*   **Creation:** `lj_tab_new` (creating tables) and `resize` (resizing) are expensive.
    *   **Solution:** Use `table.new(narr, nrec)` (OpenResty API) to pre-allocate table size and avoid resizing.
*   **Recycling:** Allocating memory is expensive.
    *   **Solution:** Use `table.clear` to clear a table for reuse without freeing the memory.
*   **Hash Table Quirks:** Lua tables can trigger resizing even if the *number* of keys stays constant, if keys are frequently added and removed. For these cases, OpenResty provides a pure C data structure implementation of a hash table.

**2. Strings**
*   **Concatenation:** Lua strings are interned. Never use `..` or `table.concat` excessively in loops.
*   **Substrings:** Avoid `string.sub` as it creates new GC objects.
*   **Inspection:** Use `string.byte` to inspect characters (returns a number, no GC overhead).

**3. Functions and Closures**
*   **Closures:** Every function declaration inside another function creates a new dynamic closure object (GC object). This shows up as `BC_FNEW` (Bytecode Function New) in flame graphs.
*   **Solution:** Move functions to the top level or use cached closures.

**4. JIT Compilation**
*   **Mechanism:** LuaJIT has a fast interpreter and a JIT compiler. The compiler works on "traces" (hot code paths).
*   **Branching:** LuaJIT relies on **biased branching** (e.g., error handling paths that are rarely taken). **Unbiased branching** (50/50 splits) is bad for the JIT.
*   **NYI (Not Yet Implemented):** OpenResty provides tools to detect which parts of the Lua code abort the JIT compilation (falling back to the interpreter).

**5. Regular Expressions**
*   **The Problem:** Standard Regex engines (like PCRE) use backtracking, which is slow and vulnerable to ReDoS (Regular Expression Denial of Service).
*   **The Solution (`sregex`):** Zhang wrote a new regex engine (`sregex`) based on NFA/DFA (Thompson NFA). It guarantees linear time complexity `O(n)` and constant space `O(1)` (fixed memory footprint).
*   **Benchmark:** In tests involving complex/malicious inputs (like OWASP security rules), `sregex` significantly outperforms PCRE and others, maintaining throughput where others drop to near zero.

### **Memory Optimization**
*   **Memory Flame Graphs:** Used to locate memory leaks by tracing allocations (`malloc`, `GC`).
*   **GC Analysis:** Tools available to analyze the distribution of GC objects (strings, tables, closures) to identify what is consuming memory.

### **Future Directions: DSLs and Specialization**
Zhang proposes that abstractions have a cost. To solve this, he suggests **Business-Level Domain Specific Languages (DSLs)**.
*   **Concept:** Instead of writing generic logic (e.g., a CDN server handling millions of different configs), use a DSL to **generate** specialized Lua code for each specific use case.
*   **Benefit:** This creates linear, specialized code that is easier for the JIT to optimize, avoiding complex branching logic required to handle generic cases.

### **Q&A**
*   **Code Generation:** Optimizing for high-performance often involves specializing code for specific configurations (e.g., generating a specific Lua CDN handler for a client using only 2 out of 100 features).
*   **Flame Graphs Implementation:** SystemTap allows duplicating LuaJIT's stack dumping logic inside the kernel probe. This allows grabbing stack traces without LuaJIT's collaboration, making it safe even if memory reads are invalid (SystemTap handles faults).
*   **Non-Blocking Disk IO:** OpenResty plans to expose AIO (Asynchronous IO) APIs. Currently, Nginx's thread pool mode can also be used to offload blocking IO to dedicated threads.