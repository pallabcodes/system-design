# Pattern: Unbounded Queue

## Problem
A system component accepts work (requests, messages, tasks) into a queue without a maximum size limit. If the arrival rate of work consistently exceeds the processing rate, the queue grows infinitely until the system crashes due to resource exhaustion.

## Symptoms
- Slow but steady increase in memory consumption leading to Out of Memory (OOM) crashes
- Exponentially increasing latency as items sit in the queue for longer periods
- "Death spiral": GC pauses increase as memory fills, further slowing down processing and accelerating queue growth
- Inability to gracefully degrade under heavy load

## Context
Message Brokers, Thread Pool Task Queues, In-memory application buffers, Microservices handling asynchronous tasks.

## Causes
- Default configuration of threading libraries or data structures (e.g., `LinkedBlockingQueue` without capacity).
- Unpredictable traffic spikes combined with slow downstream processing.
- A producer that is much faster than the consumer.

## Solution
1. **Bounded Queues**: Explicitly set a maximum capacity on all queues.
2. **Backpressure / Load Shedding**: When the queue is full, reject new requests immediately (HTTP 503) to signal to the client to slow down.
3. **Drop Oldest/Newest**: Depending on business logic, drop the oldest message or the newest message when the queue is full.
4. **Scale Consumers**: If the queue frequently fills up, trigger auto-scaling to add more consumer instances.

## Tradeoffs
- Dropping messages means data loss; requires robust client retry logic or acceptable business loss.
- Defining the "right" queue size requires capacity planning and understanding memory limits.

## When to use
- In EVERY asynchronous processing pipeline. Never use an unbounded queue in production.
- When designing APIs that can be subjected to sudden bursts of traffic.

## Tags
anti-pattern, reliability, performance, messaging, backpressure

## Signals
- "out of memory on queue"
- "application death spiral"
- "latency increasing indefinitely"
- "unbounded queue crash"
- "implementing backpressure"

## Sources
- General Knowledge
