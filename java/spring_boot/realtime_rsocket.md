Resource: https://youtu.be/-EoXSAaRe5c

Based on the transcript of the video presentation "RSocket - Future Reactive Application Protocol" by Oleh Dokuka, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction**
Oleh Dokuka introduces himself as a software engineer from Kyiv, Ukraine, focused on distributed systems. He is a contributor to Project Reactor (described as similar to RxJava but better for the server-side) and a committer to the RSocket project. The presentation aims to explain the challenges of modern engineering, why RSocket fits those needs, and demonstrate the technology via code.

### **The History of Protocols**
To understand the need for RSocket, Dokuka reviews the history of networking protocols:
*   **The 90s:** Engineers focused on connecting computers. Companies like Microsoft invented proprietary protocols (like IPX/SPX) to lock users into their platforms. These eventually lost out to open standards like TCP.
*   **The Millennium:** The focus shifted to building applications communicating over these protocols. Proprietary options like CORBA and DCOM appeared but failed against community-driven open standards. HTTP emerged as the standard, followed by a period of "opinionated" web application development (Web 2.0).
*   **The API Era:** As APIs exposed databases and services, protocols like SOAP and XML-RPC were used. Eventually, REST became the dominant architectural style for communication.

### **Current Challenges in the Cloud-Native Era**
Dokuka analyzes the current landscape based on industry reports:
*   **Microservices Growth:** There has been massive growth in microservices and distributed systems over the last five years.
*   **Multi-Cloud Complexity:** Deployments now span AWS, Azure, and Google Cloud, creating operational challenges regarding security, connectivity, and port exposure.
*   **Unreliable Networks:** Developers must contend with the inherent unreliability of networks in distributed systems.

**What is needed to solve these problems:**
1.  **Reliable Network & Proper Messaging:** A protocol that abstracts the bits and bytes, allowing developers to focus purely on the message.
2.  **High Performance:** Protocols like HTTP/1.0 are inefficient due to connection overhead (opening/closing connections). High-load platforms (e.g., exchanges) need protocols capable of handling millions of requests per second.
3.  **Flexibility:** The traditional Request/Response pattern is insufficient for modern real-time streaming needs. While HTTP is moving toward streaming, it is not fully there yet.
4.  **Stability:** The protocol must ensure stability in the face of unreliable networks.
5.  **Edge/IoT Support:** The protocol should work on everything from servers to mobile phones, teapots, and Arduino devices.

Dokuka argues that while HTTP/2 is an upgrade and HTTP/3 is in development, HTTP remains a document-oriented protocol not originally designed for microservices. He suggests a mindset shift is required.

### **Introduction to RSocket**
RSocket is an open-source, Layer 5/6 (OSI model) binary messaging protocol developed by companies handling massive traffic (like Netflix and Facebook) to solve specific microservice challenges.
*   **Reactive Streams Semantics:** RSocket follows Reactive Streams, making streaming a first-class citizen.
*   **Capabilities:** It supports resilience, application-level flow control, and various communication patterns (RPC, etc.).
*   **Performance:** It is described as "blazing fast"—potentially 10 times faster than HTTP with fewer resources.

**Key Technical Features:**
*   **Binary Messaging:** You provide a payload (data + metadata), and RSocket handles the fragmentation, delivery, and reassembly. It is efficient and allows for compression.
*   **Multiplexing:** It uses a single connection for multiple logical streams, distinguishing messages by Stream ID. This eliminates the need to open multiple connections.
*   **Transport Agnostic:** Unlike HTTP/2 (bound to TCP), RSocket can run over TCP, WebSocket, Aeron, or QUIC. Developers can switch transports without changing business logic.
*   **Resilience & Backpressure:** It prevents "Out of Memory" errors using flow control. A client can request exactly the number of items it can handle (e.g., 10 items). The server respects this and only sends that amount.
*   **Leasing:** This feature prevents servers from being overwhelmed by clients. The server can dictate its capacity to the client, acting as a built-in rate limiter/circuit breaker.

**Communication Patterns:**
RSocket supports more than just Request/Response:
*   **Request-Stream:** Receive a stream of updates.
*   **Fire-and-Forget:** Send a message without waiting for a response (efficient for logging).
*   **Request-Channel:** Bi-directional streaming.
*   **Peer-to-Peer:** Once a connection is established, client and server become peers. A server can initiate a request to the client (e.g., checking the battery status of a connected mobile phone) without the client needing to poll.

### **Code Demonstration**
Dokuka demonstrates RSocket using Java (server) and JavaScript (client).

**Java Server:**
*   Uses `RSocketFactory` (or newer APIs) to create a server.
*   Implements the `RSocket` interface, specifically the `requestStream` method.
*   Utilizes Project Reactor (`Flux`) to return a stream of messages.
*   The setup allows for configuration of resume-ability (reconnecting without data loss on network switches) and fragmentation (breaking large files into small frames).

**JavaScript Client:**
*   Uses `RSocketClient` connecting via WebSocket.
*   The code demonstrates symmetry: the API looks very similar to the server-side code.

**Live Demo of Backpressure:**
*   Dokuka runs the application and connects via a browser.
*   In the browser console, he creates a subscription but requests `0` items. No data is sent.
*   He then manually requests `1` item, then `10` items. The server responds with exactly that amount, demonstrating the "pull" model of backpressure over the network.

### **Ecosystem and Future Outlook**
**Language Support:**
RSocket supports Java, JavaScript, C++, Rust, Go, Python, and others. It enables polyglot architectures where different languages communicate seamlessly.

**Extensions and Tools:**
*   **RSocket-RPC:** Uses Protobuf generation for a familiar RPC experience.
*   **Spring Boot:** An RSocket starter is available for easy integration.
*   **GraphQL:** Supports RSocket over GraphQL.

**Current Status & Disadvantages:**
*   **Adoption:** It is currently in the "Innovators" stage and not yet widely adopted by huge enterprises.
*   **Documentation:** Dokuka admits documentation is lacking and invites the community to help write blogs and guides.
*   **Implementation Gaps:** Some languages (like Swift) lack implementation.

**The "Micro-Network" Vision (RSocket Broker):**
Dokuka concludes by introducing the **RSocket Broker**.
*   **Concept:** Similar to how network routers connect computers using routing protocols to discover paths, the RSocket Broker acts as a router for microservices.
*   **Function:** Instead of connecting Service A directly to Service B, both connect to the Broker. The Broker handles routing, discovery, and load balancing.
*   **Goal:** To build a transparent "micro-network" where applications communicate peer-to-peer logically, mediated by the Broker.

### **Conclusion**
Dokuka encourages the audience to join the Reactive Foundation and the community Discord to ask questions, as there was no time for a live Q&A.


# Resource: https://youtu.be/GcBl9byna68?list=TLGG03ntU0nWKIAxNTAyMjAyNg


Based on the transcript of the video "Developing a RSocket Server with Spring Boot: From Zero to AWS EC2 deployment," here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Resources**
The video begins with the goal of the tutorial: standing up an RSocket server using Spring Boot and deploying it to an AWS EC2 instance to make it accessible globally.
*   **Resources:** Viewers are directed to the presenter's website (`hbrown.dev`) for a full article, a list of commands used on EC2, and a link to the GitHub repository to clone the code.
*   **What is RSocket?** It is an application protocol initially developed by Netflix, now open source. Unlike HTTP (Request/Response), RSocket supports:
    *   **Single Request/Stream Response:** One request yields a stream of results.
    *   **Fire-and-Forget:** Send a request without waiting for a response.
    *   **Bi-directional Streaming:** Two-way communication where client and server update each other.

### **Project Setup (Spring Boot)**
The project is created using `start.spring.io` with the following settings:
*   **Project:** Gradle Project.
*   **Language:** Kotlin.
*   **Java Version:** 11.
*   **Packaging:** Jar.
*   **Dependencies:** The only required dependency is **RSocket** (found under Messaging).
*   **Build File:** The presenter reviews the `build.gradle.kts` file. It includes standard Spring Boot plugins. He adds an optional dependency: `assertj` (for testing assertions).

### **Code Implementation**
**1. The Controller**
*   The class is annotated with `@Controller`.
*   Unlike Spring MVC which uses `@RequestMapping`, RSocket uses `@MessageMapping` to specify the path to access the function.

**2. Data and Service Layer**
*   **Domain Object:** A `Contact` data class is created containing an ID (optional), first name, last name, mobile number, and email.
*   **Service Interface:** `ContactService` is created.
*   **Implementation:** A hard-coded implementation uses a `ConcurrentMap` as an in-memory database with four test entries.
*   **Search Logic:** A `SearchCriteria` DTO is used to filter results. The logic iterates through the map to check if the first name, last name, mobile, or email contains the search values (ignoring case).

**3. Testing the Service**
*   A Spring Boot Test is written specifically for the Service layer.
*   **Logic:** It searches for the name "Brian".
*   **Assertions:** It asserts the result is not null, contains a single entry, and the first entry has an ID of 2.
*   **Reactor:** The presenter notes RSocket uses Project Reactor (`Flux` and `Mono`). The test subscribes to the `Flux`, requests unbounded elements, receives `onNext`, and then `onComplete`.

**4. Controller Test (RSocket Client)**
*   A test is written to verify the Controller.
*   **Setup:** It injects `RSocketRequester.Builder` and the `@LocalRSocketServerPort`.
*   **Building the Request:** These injections are used to build an `RSocketRequester`.
*   **Execution:** The test specifies the route, sends the `SearchCriteria` data (searching for "Brian"), and retrieves the result mapped to the `Contact` object.
*   **Output:** The `Flux` is converted to a list, and the same assertions used in the Service test are applied (Size 1, ID 2).

### **Configuration and Local Execution**
*   **application.properties:** The only required configuration is the server port: `spring.rsocket.server.port`.
    *   Optional configs shown: Logging settings and lazy initialization.
*   **RSC Tool:** The presenter recommends a command-line tool called `rsc` for testing RSocket endpoints.
*   **Local Test:**
    *   The application is started via the IDE.
    *   **Single Result Test:** A JSON command is sent via `rsc` searching for name "Brian". It returns a mapped JSON object.
    *   **Streaming Test:** A request is sent searching for mobile "3" and email ".co.za".
    *   **Streaming Result:** The output is **not** a single JSON document (like an array). It is three separate JSON items printed sequentially. This demonstrates the efficiency of streaming (getting results as they are available rather than waiting for the whole list).
    *   **Flux vs. Mono:** The presenter explains this streaming behavior is because the return type is `Flux`. If it were `Mono<List<Contact>>`, it would return a single list object.

### **AWS EC2 Deployment**
**1. Launching the Instance**
*   Navigate to AWS Console -> Services -> Compute -> EC2.
*   Click **Launch Instance**.
*   **AMI:** Select Amazon Linux 2 (Free Tier eligible).
*   **Instance Type:** Select `t3.large` (chosen for speed during the demo, though `t3.micro` is free tier eligible).
*   **Storage:** Default 8GB SSD.
*   **Tags:** None added.

**2. Security Group Configuration**
*   Default: SSH (Port 22) is enabled.
*   **RSocket Port:** A custom TCP rule is added for **Port 5000**.
*   **Source:** Set to "Anywhere" (0.0.0.0/0) for the demo.

**3. Finalizing Launch**
*   Review settings and click Launch.
*   **Key Pair:** Select an existing key pair (or create new) to enable SSH access.
*   The instance initializes (status changes from "Initializing" to "Running").

**4. Connecting to the Instance**
*   Select the instance and click "Connect" to get instructions.
*   **Permissions:** Run `chmod 400` on the private key file locally.
*   **SSH:** Copy the provided SSH command (`ssh -i key.pem ec2-user@dns-address`).
*   Run the command in the terminal to connect.

**5. Server Setup**
*   **Update:** Run `sudo yum update`.
*   **Install Java:** Run `sudo amazon-linux-extras install java-openjdk11`. Verify with `java -version`.

**6. Deploying the Application**
*   **SCP:** Use the `scp` command to copy the compiled JAR file from the local machine to the remote EC2 instance.
    *   Command structure: `scp -i key.pem path/to/jar ec2-user@remote-dns:/home/ec2-user`.
*   **File Structure:**
    *   Create a directory: `mkdir rsocket-server`.
    *   Move the JAR into it.
    *   Create subdirectories: `bin` and `logs`.
*   **Configuration:**
    *   Create `application.properties` inside the directory.
    *   Paste the configuration (specifically setting the port to 5000 to match the AWS Security Group).

**7. Scripting Startup/Shutdown**
*   **Startup Script:** Create `startup.sh`. Content includes the `java -jar` command pointing to the config file and outputting logs to the `logs` directory. Make executable (`chmod +x`).
*   **Shutdown Script:** Create `shutdown.sh`. Content includes commands to find the PID and kill the process. Make executable.

**8. Remote Execution and Testing**
*   Run `./bin/startup.sh`.
*   Check logs (`tail -f logs/rsocket-server.log`) to confirm startup.
*   **Remote Test:** Use the `rsc` tool on the local machine, pointing it to the **AWS Public DNS** and **Port 5000**.
*   The test confirms functionality by returning data from the remote server.

### **Cleanup**
*   Run `./bin/shutdown.sh` on the EC2 instance. Verify connection is refused.
*   In AWS Console:
    1.  **Stop** the instance (wait for "Stopped" state).
    2.  **Terminate** the instance (wait for "Terminated" state) to ensure no billing occurs.

The video concludes by reminding viewers that all commands and code are available on the blog and GitHub repository.


Q: How do I pick between Flux or mono here?

Q: How does RSocket handle reconnections if my network drops out?

Q: What happens when I send a fire-and-forget request to spring?
