Based on the transcript of the video presentation by Bryan Boreham from Weaveworks, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Background**
Bryan Boreham introduces himself as a software engineer at Weaveworks. He explains that his company runs a SaaS system (Weave Cloud) on Kubernetes, which has been in production for over two years. His personal passion is optimization, likening it to a video game where one can spend hours improving the "score". The presentation focuses on using two CNCF projects, Prometheus and Jaeger, to optimize systems, drawing on "war stories" from his work.

### **The Three Rules of Optimization**
Before diving into tools, Boreham establishes three ground rules for software optimization:
1.  **Measure:** You must measure before you act. Do not change things based on guesses.
2.  **Measure the Real System:** Do not rely on tiny benchmarks or blog posts. Measure the actual system doing its actual work.
3.  **Keep Measuring:** Continue measuring after changes are made to understand behavior over time and under different loads.

### **Tool Overview: Prometheus and Jaeger**
**Prometheus:**
Boreham describes Prometheus as a time-series metrics system (measuring quantities that vary over time, like CPU or memory).
*   **Collection:** It uses a central server to request metrics from exporters and service components.
*   **RED Methodology:** He advocates for the RED methodology for internal service metrics: **R**equest rate, **E**rror rate, and **D**elay (Latency).

**Jaeger:**
Jaeger is described as a tool for understanding what a system is actually doing in detail.
*   **Focus:** It tracks the flow of control as it moves from one code part or microservice to another.
*   **Architecture:** Like Prometheus, it collects information from various parts of a distributed system into a central place for analysis.

### **War Story 1: The Case of the Mysterious User Service Latency**
**The Problem:**
Boreham presents a dashboard showing the latency of their user service. He utilizes Prometheus histograms to track the 99th percentile, median, and mean. While the mean and median were fast, the 99th percentile showed spikes, flapping between 0.5 seconds and 4 seconds over a couple of days.

**Investigation:**
1.  **Drilling Down:** By adding the `route` parameter to his Prometheus query, he discovered that one specific request route was steady at 5 seconds while others varied. This illustrated his warning: "Beware of averages," as they can hide important details.
2.  **Instrumentation:** He identified the slow route was hitting the database but lacked detail. He added Jaeger tracing to the code (roughly 3-4 lines of setup plus a library to instrument SQL calls).
3.  **Jaeger UI:** The trace visualization showed the call stack and SQL queries with their time spans.

**The Resolution:**
Surprisingly, the trace data itself did not immediately reveal the problem because the Go SQL library lacked a hook to trace the opening of new connections. The root cause was that connection pooling to the database had been accidentally disabled. Once fixed, the median latency dropped from roughly 22 milliseconds to 4 milliseconds, and the graph flattened out.

### **War Story 2: The Slow Dashboard**
**The Problem:**
Boreham returns to the scenario that opened the talk: a Weave Cloud dashboard that was loading too slowly. The backend system involved is "Weave Cortex," a multi-tenant distributed Prometheus.

**Investigation:**
He presents a Jaeger trace of the slow operation, highlighting two critical findings visible in the trace:
1.  **Errors:** An exclamation mark icon indicated that a cache call was erroring, contributing significantly to the slowness.
2.  **Serialization:** He observed a "long diagonal line" in the trace visualization. To an experienced engineer, this shape indicates operations are being executed one after the other (serialization).

**The Resolution:**
He determined that the operations forming the diagonal line could be parallelized. After code changes, the new trace showed operations starting in parallel, resulting in a significantly faster completion time.

### **Optimization Patterns (Visual Heuristics)**
Boreham distills his experience into specific patterns to look for when viewing Jaeger traces:

*   **Pattern 0: The Longest Span:** Simply look for the bar that is the longest. This offers the biggest return on investment for optimization.
*   **Pattern 0 (Variant): Missing Detail:** If a trace shows a long gap with no detail, you must go back to the code and add instrumentation to that region.
*   **Pattern 1: The Long Diagonal Line:** This indicates sequential processing. Ask if these steps can be parallelized,.
*   **Pattern 2: Identical Lengths:** If multiple spans take exactly the same amount of time, be suspicious. This often indicates a timeout or a hard limit where work is being curtailed.
*   **Pattern 3: Simultaneous Finish:** If spans start at random times (as expected in a dynamic system) but all finish at the exact same moment, look for a resource lock, transaction wait, or interlock that is holding them back.

### **Conclusion**
Boreham concludes by reiterating his main lesson: **Measure, Measure, Measure**. He praises Prometheus and Jaeger as powerful tools for gaining insight into distributed systems and ends with a pitch for his company's hosted services.