Resource: https://www.youtube.com/watch?v=E708csv4XgY

Based on the transcript provided, here is an accurate and comprehensive extraction of the presentation "Messaging at Scale at Instagram" by Rick Branson, from start to end.

### Introduction and The Feed Problem
Rick Branson introduces the talk by focusing on how Instagram, a "big Python Django shop," handles asynchronous tasks to avoid processing heavy workloads within web requests. The core example provided is the Instagram "Feed," which displays photos from followed accounts in time-ordered sequence.

*   **Naive Approach:** A basic SQL approach would involve fetching all followed accounts, retrieving all their photos, sorting by creation time, and returning the top 10. This creates an infinite scaling problem and wastes data.
*   **Redis Solution:** Instagram maintains a list of media IDs for each user stored in Redis. This is a simple ordered list queried by user ID.
*   **Fan-out on Write:** When a user posts a photo (e.g., media ID 94305), the system must insert that ID into the feeds of all their followers. This approach offers a fixed time cost (O(1)) for reading, which is ideal because they read much more frequently than they write.

### The Need for Asynchronous Tasks
The fan-out approach introduces reliability issues. Database servers can fail, and web requests are "scary places" where operations need to happen quickly.
*   **The "Justin Bieber Problem":** Celebrities have millions of followers. It is impossible to deliver a new post to millions of feeds within the 100–500 millisecond window of a web request.

**The Solution:** An async background task system is used where tasks are inserted into a broker and processed by workers. If a worker crashes or a data center fails, tasks are redistributed to new workers.
*   **Chain Tasks:** To handle large follower counts, Instagram uses "chain tasks." Instead of delivering to all followers at once, they break the work into pieces. A task processes a chunk of followers and recursively calls a new task with a cursor to process the next chunk.
*   **Benefits:** This allows fine-grained load balancing (no worker works on a task for more than a few seconds) and low penalties for failure (work resumes where it left off). They can deliver to 10,000 followers in about 1.5 seconds.

### Other Use Cases and History
Beyond the feed, the async system is used for cross-posting (Twitter/Facebook), search indexing, spam analysis, account deletion, and API callbacks.

**The "Gearman" Era:**
Originally, Instagram used Gearman, a task queue written in C. It lacked framework support, leading to messy ad-hoc worker scripts and cron jobs. In production, Gearman’s persistence (MySQL-based) was too slow, so they ran it in memory. If a box died, tasks were lost. It was polling-based and single-core, and it did not scale well.

### Moving to Celery and Selecting a Broker
They needed a fresh start and chose **Celery**, a distributed task framework for Python that is extensible, feature-rich, and has excellent Django support. The team evaluated three candidates for the message broker:

1.  **Redis:** They already used it and it is fast. However, it is polling-based, replication is "bring your own tooling," and being in-memory meant data loss if memory limits were reached.
2.  **Beanstalk:** A purpose-built task queue (similar to Memcached protocol). It is fast and pushes to consumers. However, it offered **no replication support** at all.
3.  **RabbitMQ:** The option recommended by Celery documentation. It is reasonably fast, spills to disk, and has excellent Celery compatibility. Crucially, the replication setup is incredibly easy ("batteries included")—nodes negotiate master status automatically. The downside was the team didn't know Erlang, but the code was clean enough to read.

### Infrastructure and Topology
Instagram uses RabbitMQ v3 with clusters of two broker nodes that are mirrored and straddle availability zones.
*   **Hardware:** They run on EC2 `c1.xlarge` instances using RAIDed instance storage (avoiding EBS) and are intentionally over-provisioned to handle load spikes.
*   **Monitoring:** They use Sensu to monitor queue length and failure rates, and graphite/statsd for graphing task performance.
*   **Performance:** They use a round-robin approach to select brokers from web boxes. The system pushes about 4,000 tasks per second (sustained) with 25,000 application threads pushing data.
*   **Reliability:** The setup handles over 10,000 connections and survives rolling restarts without issues.

### Configuration and Optimizations
One major motivation for Celery was allowing new engineers to deploy job types quickly using simple decorators and `.delay()` calls.

**Scaling Challenges & "Hacks":**
*   **Multi-Broker Support:** At the time, Celery only supported one broker. Instagram wrote a shim called `kombu-multi-broker` to support round-robin usage of multiple brokers, though this broke some management tools.
*   **Concurrency Models:** They use **Gevent** for network-bound tasks (Facebook/Tumblr API calls, S3 checks) and standard **multiprocessing** for everything else. They use `celery multi` to manage different worker types on the same box.
*   **Splitting Tasks:** For jobs requiring both network I/O and CPU (e.g., spam checks), they split the job: a Gevent task does the network check, and if action is needed, it calls a separate multiprocess task.
*   **Slow Tasks:** Slow tasks can monopolize workers. The solution was separating tasks into different queues: "fast," "default," and a specific isolated queue for "feed delivery" to ensure it never gets backed up.
*   **Concurrency Levels:** They run 14 child processes for fast queues, 12 for feed queues, and 6 for default queues across 30 instances.

### Handling Failures and "Physics"
*   **Retries:** Celery’s retry facility allows tasks to back off (e.g., `countdown=60`) during temporary failures like S3 outages.
*   **Lost Tasks & `acks_late`:** By default, Celery acknowledges (acks) a task *before* execution. If the worker crashes during execution, the task is lost. Instagram uses `acks_late` to ack only *after* completion.
*   **Idempotency:** Using `acks_late` requires tasks to be idempotent (safe to run multiple times) because failures can cause duplicate runs.
*   **FLP Impossibility:** Branson references FLP impossibility to explain that "exactly once" delivery is impossible. You must choose between retrying (risking duplicates) or not retrying (risking data loss). They choose to retry.
*   **Publisher Confirms:** Early on, overloaded brokers dropped tasks because standard AMQP doesn't confirm receipt. They forced "publisher confirms" on, which hurt performance by 25–50% but ensured reliability.

### Rules of Thumb
*   **Avoid Backups:** Do not use async tasks as a backup mechanism for failing systems; queues will just back up and die.
*   **Simple Arguments:** Only pass self-contained, simple data (strings, numbers, lists/dicts) as task arguments. Avoid complex objects because serialization (Pickle) can break across code versions.
*   **Task Duration:** Tasks should execute quickly. Instagram imposes a **soft time limit** of 20 seconds (throws exception) and a **hard time limit** of 30 seconds (kills process).

### Future and Q&A
Looking forward, they want to improve RabbitMQ performance, utilize result storage for distributed computation, and implement a single cluster for control queues to fix the broken management tooling. They also hope to eliminate their custom multi-broker shim now that Celery natively supports multiple brokers.

**Q&A Session:**
*   **Zone Failures:** When a zone goes down, RabbitMQ handles failover via synchronous replication. On the client side, the multi-broker shim detects failures, blacklists the host, and rotates to a different broker.
*   **Updating Tasks:** To update tasks seamlessly, they create proxies (e.g., V2 of a task) or use `**kwargs` for arguments to maintain compatibility during rolling restarts.
*   **Dynamic Queue Switching:** Switching a task from a slow to a fast queue is not dynamic; it requires a configuration change and a deployment roll-out.