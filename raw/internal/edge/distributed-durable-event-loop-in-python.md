Resource: https://youtu.be/jxqPWS_LRzw


Based on the video transcript titled "Temporal Python – A Durable, Distributed Asyncio Event Loop," here is an accurate extraction of the presentation from start to end, detailing the problem space, the concept of durable execution, the implementation mechanics, the Temporal platform, and the Q&A session.

### Introduction and the Problem Space
The speaker, Maxim Fateev, draws on his eight and a half years at Amazon to discuss order processing logic. He presents a simplified example of a sequence: checking fraud, preparing shipment, charging, shipping, and sending a confirmation email.

**Why Standard Code Fails**
You cannot write this logic as a standard sequence of code in production because processes crash, APIs fail, and operations may be long-running (e.g., preparing a shipment might take days if out of stock).

**Limitations of Current Approaches**
1.  **Event-Driven Architecture (Queues):** While queues produce state and help with message redelivery, Fateev argues they are a poor choice for large-scale microservice orchestration. They lack good error handling (relying mostly on Dead Letter Queues), do not support long-running operations efficiently, and spread logic across multiple services. This "choreography" results in a dependency mess where every service depends on every other service.
2.  **Orchestration:** A central place defines the transaction, offering better visibility and clear service APIs. However, developers often avoid orchestration because it usually forces them into a poor programming model requiring diagrams, XML, or JSON files instead of normal code. This limits the ability to implement complex business logic.

### The Solution: Durable Execution
Fateev introduces "Durable Execution." Conceptually, this allows code to be guaranteed to complete regardless of failures. If a process crashes, the function migrates to another physical process and continues with variables preserved. It supports API calls or operations that can take days to complete.

**How Durable Execution is Implemented (Replay Mechanism)**
To implement this without "magical RAM," the system uses a replay technique backed by a persistent log:
1.  **Recording History:** When a function runs (e.g., `check_fraud`), its result is recorded in a persisted log.
2.  **Handling Crashes:** If the process crashes after several steps, the system detects the crash and restarts the function from the beginning on a different machine.
3.  **The Replay:** During the restart, when the function attempts to call `check_fraud` again, the system checks the log. Seeing the result is already recorded, it returns that result immediately without making the actual API call.
4.  **Forward Progress:** The function continues replaying until it hits a step not found in the log (e.g., `ship`), at which point it executes the real API call.

**Technical Requirements for Replay**
1.  **Capturing Results:** One practical way to record results is to use an explicit `execute` wrapper function for external API calls, which handles retries and logging.
2.  **Determinism:** For replay to work, code must be deterministic (producing the exact same result and code path given the same inputs).
    *   **No Randomness:** Using standard random functions is prohibited because different branches might be taken during replay.
    *   **Deterministic Time:** Code cannot check system time directly because it changes between the original run and the replay. The system must return the time recorded during the first execution.
3.  **Concurrency:** Concurrent code is typically non-deterministic due to thread context switching controlled by the OS.
    *   **The Python Solution:** Python’s `asyncio` is ideal because it allows the implementation of a custom event loop. This enables full control over task execution order (e.g., a single queue of tasks running in a single thread), guaranteeing that complex parallel tasks run in exactly the same order every time.

**The Event Loop Model**
The system effectively uses two levels of loops. One loop runs tasks until they block on external events (IO). These IO requests are sent out as commands. When external events (like timer firings or command completions) return, they are applied to the program, making new tasks eligible for execution in the `asyncio` loop.

### Introduction to Temporal
Temporal is the open-source implementation of this durable execution system. It handles the ID mapping, failure detection, and log persistence described above.
*   **History:** Started at Uber, currently in production for seven years with thousands of use cases. Early adopters include HashiCorp, Coinbase, Airbnb, and DoorDash.
*   **Scale:** It scales linearly with the database. It has been tested up to 300,000 actions per second.
*   **Architecture:** Temporal is a backend service exposing a gRPC interface running on top of a database. Crucially, the **Temporal service does not run user code**. User code runs in the SDK (worker) which connects to the backend to receive tasks.

### Temporal Python SDK
Fateev demonstrates how to rewrite the order processing example using Temporal Python:
*   **Decorators:** Activities (IO operations) are normal functions decorated with `@activity`. Workflows are classes decorated with `@workflow`.
*   **Execution:** The main logic calls `execute_activity` (replacing the manual capture concept discussed earlier) and defines parameters like timeouts.
*   **Handling Determinism:** The SDK provides safe alternatives for non-deterministic operations, such as `workflow.random` and `workflow.now`. A specialized component detects and fails the workflow if standard non-deterministic calls are used.
*   **Concurrency:** Standard `asyncio` constructs (await, tasks) work natively because the code executes under Temporal's custom event loop.

### Use Cases
*   **Infrastructure Provisioning:** Used by HashiCorp Cloud to orchestrate Terraform and API calls.
*   **Business Process Automation:** Replacements for BPMN.
*   **Customer Lifecycles:** Processes that run forever (e.g., charging a customer once a month).
*   **Payments/Banking:** Used by banks for transaction sagas.
*   **IoT:** Digital twins (workflows representing devices).
*   **Low Code/No Code:** Building interpreters for custom DSLs to provide high-level abstractions to customers while gaining Temporal's durability.

### Q&A Session

**1. Python Environment Management**
*   **Question:** Is the worker environment the same as the main project, or can you specify a specific Python environment?
*   **Answer:** It is just normal Python code linking the SDK as a library. The user fully controls the environment and how workers run. Temporal does not care about the deployment details.

**2. Multi-language Support**
*   **Question:** Can different workers use different languages (e.g., Python workflow calling Java tasks)?
*   **Answer:** Yes. Activities can be written in different languages than workflows. The server treats activity names as strings and serializes arguments, so as long as names match (or interfaces match), it works.

**3. Versioning and Deployments**
*   **Question:** What happens to long-running workflows when code is updated or rearranged?
*   **Answer:** There are two approaches:
    1.  **Versioned Workers:** Run workers for specific versions until old workflows drain.
    2.  **Patching:** Use logic inside the code (e.g., `if old_version: use_old_code else: use_new_code`). During replay, the system remembers which branch was taken previously. This is necessary for workflows running for months where keeping old workers isn't practical.

**4. Database Performance**
*   **Question:** Doesn't backing every function call with a database interaction make it slower than synchronous code?
*   **Answer:** If comparing to in-memory execution, yes, it is slower. If comparing to a system that requires durability (talking to a database anyway), performance is comparable. The backend is highly optimized and scales linearly with the database.

**5. Failure Handling (Rollbacks)**
*   **Question:** If a workflow fails in the middle (e.g., creating a customer in one service but failing in another), is it wrapped in a transaction?
*   **Answer:** Infrastructure failures (crashes) are handled automatically without the workflow noticing. Business-level failures (e.g., "account does not exist") must be handled by the user code, typically using try/catch blocks to run compensations (Sagas).

**6. Implementation Across Languages**
*   **Question:** Since Java, Go, and Python have different concurrency models, how much code is shared vs. language-specific?
*   **Answer:** Temporal aims to be "language native" (e.g., using `asyncio` in Python, blocking calls in Java). To achieve this, they use a Rust-based library underneath that handles the complex state machine (about 90% of the logic), with a thin, language-specific layer on top to handle the integrations.

Q: How is different from standard async io package or not?