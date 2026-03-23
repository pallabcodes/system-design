Resource: https://youtu.be/nok0aYiGiYA?list=TLGGP2XsphNkQRMzMTAxMjAyNg



Based on the video transcript provided, here is an accurate and comprehensive extraction of the presentation "Two Go Programs, Three Different Profiling Techniques" by Dave Cheney at GopherCon 2019.

### Introduction
The presentation begins with Dave Cheney introducing the session as a live coding demonstration without slides, aiming to improve the performance of two different Go programs using three different profiling techniques within approximately 43 minutes.

### Program 1: Word Count
**The Setup**
The first program is a simple utility designed to read a piece of text and count the number of words in it.
*   **Logic:** The program iterates through a file byte by byte using a simple state machine. It checks if the current byte is a space and tracks the state of whether it is currently "in a word" to handle multiple consecutive spaces correctly.
*   **Compilation:** To measure execution time accurately without including compilation time, the program is pre-built using `go build`.
*   **Input Data:** The input is the complete text of *Moby Dick*, which is approximately 1.2 megabytes in size.
*   **Initial Performance:** The initial run takes approximately 2.0 seconds. For comparison, the standard `wc` (word count) utility runs effectively instantaneously on the same file. While the two programs output slightly different counts due to different definitions of a "word," the goal is to optimize the execution speed rather than reconcile the logic.

**Profiling Technique 1: CPU Profiling (`pprof`)**
To diagnose the slowness, CPU profiling is applied using `pprof`.
*   **Observation:** Enabling profiling adds overhead, slightly slowing the program down.
*   **Visualization:** The profile visualization shows call stacks. The graph indicates that the program spends zero seconds in the actual `main` logic. Instead, execution time is passed down through `file.Read` and file descriptor operations, culminating in `syscall.Syscall`.
*   **Diagnosis:** The issue is not that system calls are inherently slow, but that there are too many of them. Go's default read operations are unbuffered, meaning the program performs a system call for every single byte.
*   **Runtime Overhead:** The profile shows significant time spent in runtime activities like `pthread_cond_wait`. This occurs because when a thread enters a system call, the Go runtime doesn't know how long it will take. If it takes too long (over ~20 microseconds), the runtime spins up a new thread to service other goroutines. The overhead comes from the constant switching and handoff between threads due to the frequency of unbuffered system calls.

**Optimization 1: Buffering**
*   **Fix:** The code is modified to use buffering (likely `bufio`).
*   **Result:** The runtime drops significantly (an order of magnitude improvement), handling the file much faster.

**Profiling Technique 2: Memory Profiling**
After the first fix, CPU profiling becomes less useful because the program runs so fast that `pprof` (which relies on periodic sampling) captures very few samples, making the data look random or noisy.
*   **New Clue:** Occasionally, samples point to `mallocGC`, indicating memory allocation activity.
*   **Method:** The profiling method is switched to memory profiling. By increasing the sampling rate to 1 (profiling every allocation), the tool reveals that `readByte` is allocating 1.2 megabytes of memory.
*   **Diagnosis:** The program declares an array, slices it, and passes it to `Read`. Since `Read` accepts an `io.Reader` interface, the compiler and runtime cannot determine if the implementation will capture the address of the buffer. Consequently, the buffer "escapes to the heap," causing a new allocation for every call.

**Optimization 2: Buffer Reuse**
*   **Fix:** The code is modified to allocate the buffer once and reuse/reslice it for subsequent calls.
*   **Result:** The runtime drops to approximately 0.2 seconds, which is comparable to the speed of the `wc` utility. The memory profile confirms that allocations are now minimal (mostly just the 4KB buffer).

### Program 2: Mandelbrot Generator
**The Setup**
The second program generates a Mandelbrot fractal image (1024x1024 pixels), requiring the computation of 1 megapixel.
*   **Initial Performance:** It takes approximately 1.6 seconds to run.

**Profiling Technique 1: CPU Profiling**
*   **Analysis:** The CPU profile shows 90% of the time is spent in the `paint` function and `fillPixel`. This code simply iterates over complex numbers to calculate pixel colors and assigns them to fields.
*   **Limitation:** `pprof` accurately identifies *what* code is running (the math), but it doesn't offer a way to optimize it further since the math itself cannot easily be made faster, and field assignment is already basic.

**Profiling Technique 2: Execution Tracer (`trace`)**
To gain different insights, the Execution Tracer (introduced in Go 1.5) is used. It visualizes the program's execution over time.
*   **Visualization:** The trace shows the program is bimodal: first, it computes the image, then it writes the image (indicated by heap activity/GC).
*   **Diagnosis:** The trace reveals a single green line on "Proc 0" while other processors are idle. The program is single-threaded.

**Optimization 1: Per-Pixel Parallelism**
*   **Attempt:** The program is modified to use Go routines to compute every pixel in parallel.
*   **Result:** The performance worsens (1.6s to 1.7s).
*   **Trace Analysis:** The trace takes a long time to load due to the sheer number of goroutines (1 million). It shows many "runnable" goroutines but few actually "running." The overhead of the scheduler managing these goroutines outweighs the tiny amount of work required to compute a single pixel.

**Optimization 2: Per-Row Parallelism**
*   **Attempt:** The strategy is adjusted to compute one row per goroutine (reducing the count from 1 million to 1,024 goroutines).
*   **Result:** The computation time drops drastically to about 200 milliseconds.
*   **Trace Analysis:** The trace loads quickly. It shows 8 processors (Procs) busy with work, chewing through the backlog of goroutines efficiently. The total runtime is now roughly split 50/50 between computing the image and writing it to disk.

**Optimization 3: Worker Pool**
*   **Attempt:** Instead of spawning a goroutine for every row, a worker pool pattern is used (e.g., 8 workers) where workers pull row coordinates from a buffered channel.
*   **Result:** The performance is virtually identical to the per-row goroutine strategy.
*   **Trace Analysis:** The trace shows a fixed number of goroutines (e.g., G10) staying on the same CPUs, processing work sequentially without thrashing. This confirms that for this use case, simple goroutines and worker pools deliver similar performance, and the choice depends on operational preferences (e.g., limiting resource usage via workers).

### Conclusion: Amdahl's Law
The presentation concludes by analyzing the theoretical limits of optimization.
*   **Current State:** The optimized Mandelbrot program spends ~200ms computing and ~200ms writing the image (PNG encoding).
*   **Parallelism Limits:** Even if the computer had 1,000 cores and could reduce the computation time to zero, the total runtime would still be at least 200ms because the image writing phase is sequential and difficult to parallelize.
*   **Amdahl's Law:** This illustrates Amdahl's Law, which states that the maximum speedup of a program is limited by its sequential part. In this case, even with 95% of the work parallelized, the speedup taps out once the parallel portion becomes negligible compared to the sequential portion.
*   **Final Takeaway:** To achieve maximum performance, developers must ensure that as much of the program as possible—including setup, validation, and output—is parallelizable, minimizing the sequential portion.