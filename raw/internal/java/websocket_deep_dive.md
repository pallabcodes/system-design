Resource: https://youtu.be/RGrfTds4b9I

Based on the transcript of the video "WebSocket Deep Dive 2/3," here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Speaker Background**
The speaker, John Clingu, introduces himself as an employee at Oracle (formerly Sun Microsystems). His background includes working as a Solaris specialist, Java developer, and IT admin before becoming a product manager for GlassFish and Java EE. He notes that GlassFish is the reference implementation for Java EE and is an open-source commercial product.

He conducts a brief survey of the audience:
*   He asks how many attendees develop on Java EE app servers, specifically Tomcat versus the full Java EE platform or web profile.
*   He asks who has done WebSocket development, noting that few hands were raised.

Clingu mentions that he is using a borrowed slide deck because he is busy preparing for the JavaOne conference and apologizes for his casual attire.

### **Java EE 7 Overview**
Clingu asks the audience about their familiarity with different Java EE versions. Most attendees appear to be using Java EE 6, while some are still on version 5.

He outlines the major themes of Java EE 7, which launched on June 12th of that year:
*   **HTML5 Support:** This includes WebSockets, JSON processing (binding JSON to Java objects), Servlet 3.1 (Non-blocking I/O), and JAX-RS 2.0.
*   **Developer Productivity:** A shift toward annotated Java objects rather than XML configuration.
*   **Component Model Alignment:** Java EE 7 aims to bring JSF managed beans, CDI beans, and Enterprise Java Beans (EJB) toward a single component model, with CDI becoming the "glue" for the platform. He notes that JSF managed beans are heading toward deprecation in favor of CDI.
*   **Concurrency Utilities:** A new feature allowing managed concurrency (submitting jobs to a thread pool) so developers do not have to spawn unmanaged threads.
*   **JMS 2.0:** A simplified API that significantly reduces the lines of code required to send messages.

### **WebSocket Deep Dive**
**The Problem with HTTP:**
Clingu explains that developers historically relied on HTTP (request/response) for client-server communication. Techniques like polling, long polling, Comet, and Ajax were complex workarounds to make the server proactively provide data, but they were still based on HTTP, which was not designed for that purpose.

**The WebSocket Solution:**
*   **Definition:** WebSockets provide a full-duplex, bidirectional connection where both client and server can terminate the connection or send data simultaneously.
*   **Standards:** It is an IETF standard. The W3C defined the JavaScript API for it.
*   **The Upgrade Mechanism:** All communication begins as an HTTP request. The client requests a connection upgrade in the header. If accepted, the HTTP protocol is discarded, leaving a raw TCP connection for sending bytes or text.
*   **Infrastructure:** Because it starts as HTTP, it works through firewalls, proxies, and routers (ports 80 and 443).
*   **Efficiency:** Once the connection is upgraded, there are no HTTP headers or security overheads, resulting in very low latency.
*   **Protocols:** Unlike TCP/IP which has standard layers (FTP, Telnet), developers own the high-level protocol in WebSockets and must define their own message formats.

**Security:**
*   Security is handled during the HTTP handshake (e.g., SSL/TLS via HTTPS).
*   The protocol uses `ws://` for standard and `wss://` for secure connections.
*   Authentication (certificates, forms) occurs during the HTTP connection phase. Once upgraded, any further security (like payload encryption) is the developer's responsibility.

**Framing and Control:**
*   The protocol includes **Ping/Pong frames** to check if the connection is alive.
*   Control frames distinguish between text and binary messages.
*   There is a specific "Close" frame to terminate connections.

**The Handshake Process:**
1.  **Request:** The client sends a request to a host (e.g., `server.example.com`) with an `Upgrade: websocket` header and a security key.
2.  **Negotiation:** The client can specify preferred sub-protocols (e.g., "chat", "superchat"). The server selects the one it supports.
3.  **Response:** The server sends a response confirming the upgrade and the selected protocol.

**API Event Lifecycle:**
Both Java and JavaScript APIs use a callback mechanism based on connection events:
*   **On Open:** Called when the connection is established.
*   **On Message:** Called when a message is received.
*   **On Error:** Called during communication errors (e.g., malformed messages). This does not necessarily close the connection.
*   **On Close:** Called when the connection is terminated.

### **Browser and Network Support**
Clingu displays a chart from `caniuse.com` regarding browser support:
*   **Internet Explorer:** IE10 supports WebSockets; IE9 and earlier do not.
*   **Mobile:** Support varies. For example, the stock Android browser may not support it, but Chrome for Android does.
*   **Proxies:** Older proxies might time out long-lived connections. Newer ones, like the Oracle Traffic Director, natively support WebSockets and keep connections open.

### **Java API for WebSocket (JSR 356)**
*   **Development:** The specification was developed transparently with public mailing lists and is part of Java EE 7.
*   **Availability:** It is included in both the Java EE Web Profile (targeted at web-centric apps) and the full Platform.
*   **Reference Implementation:** The implementation is available on `java.net` under Project WebSocket.

### **Q&A Session**
During the presentation, Clingu answers several audience questions:

*   **Scalability:** When asked about the maximum number of clients, Clingu states there is no defined limit in the spec. It depends on hardware resources. GlassFish was tested with 60,000 concurrent connections.
*   **Node.js vs. Java:** He notes that Node.js is not multi-threaded and is constrained by a single core, whereas the JVM is multi-threaded and can likely handle more connections per server.
*   **Threading Model:** Developers do not handle threads directly. Similar to Servlets, an engine manages the thread pool, and developers simply subscribe to events.
*   **Multiple Connections:** A single browser can have multiple WebSocket connections to different servers or the same server. The developer manages these via different variables.
*   **Connection Pooling:** This is not defined in the Java spec and is an implementation detail. Tyrus (the reference implementation) likely uses non-blocking I/O rather than a thread-per-connection model.
*   **REST over WebSockets:** An audience member asks about layering REST over WebSockets for performance. Clingu argues this would be inefficient because REST relies on HTTP semantics. Re-implementing HTTP on top of WebSockets offers no value over standard TCP/IP.

### **Implementations and Conclusion of Part 2**
*   **Tyrus:** This is the reference implementation (RI) provided by Oracle.
*   **Running Environment:** The API can run on top of a Servlet container (like GlassFish 4) or standalone using frameworks like Grizzly (which uses NIO).
*   **Vendor Support:** Other vendors like Tomcat, Jetty, JBoss, and Caucho are working on implementations.

Clingu concludes this segment by calling for a 7-minute break before proceeding to the coding demonstration.


Q: What is the security risk of "tunneling" through firewalls?

Q: How many concurrentn connections can a Java Websocket server handle?

Q: Tell me about the 'ping' and 'pong' alive check mechanism.


# Resource: https://youtu.be/CTHygf0HHqc

Based on the transcript of the video "WebSocket Deep Dive 3/3," here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Setup**
The speaker resumes the presentation, joking that he consumed more caffeine because he felt he wasn't moving fast enough.
*   **Book Recommendation:** He promotes the book "Java WebSocket Programming" by Danny Coward, the specification lead for WebSockets. He notes the book covers the presentation topics in a friendlier way.
*   **Project Setup:** Using NetBeans (which bundles GlassFish), the speaker creates a new Maven Web Application named `SD Echo` targeting Java EE 7. He ensures he is not using Java EE 6, as WebSockets are only available in EE 7.

### **Coding Demo 1: The Echo Server**
*   **Creating the Endpoint:** He creates a generic Java class named `Echo`. He annotates the class with `@ServerEndpoint("/echo")` to define the relative URL.
*   **Handling Messages:** He explains that developers only need to define the callbacks they care about (`onOpen`, `onMessage`, `onError`, `onClose`). He implements an `@OnMessage` method that takes a String and returns a String, effectively creating an echo service.

### **Q&A: Data Types**
*   **Supported Types:** An audience member asks about return types. The speaker explains the API supports Strings, Booleans, Bytes, and ByteBuffers. Developers can also use InputStreams to read/write arbitrary data.
*   **JSON and Integers:** When asked about passing Integers, the speaker notes the core API understands Strings and Bytes. To pass numbers, one would typically use JSON strings or binary streams and parse them.

### **Coding Demo 2: Client-Side Implementation**
*   **JavaScript Code:** The speaker pastes pre-written JavaScript into `index.html`.
    *   It creates a connection using `new WebSocket(uri)`.
    *   It defines event handlers: `onopen` (logs connection), `onmessage` (delegates to a display function), and `onerror`.
    *   It includes a `doSend` function using `websocket.send(message)`.
*   **Execution and Troubleshooting:**
    *   He attempts to run the app in Chrome. He encounters a 404 error because of a typo in the URL (case sensitivity: `SD Echo` vs. `SD echo`). He corrects the URL to `ws://.../SD Echo/echo`.
    *   **Test:** He successfully connects, sends "hello websocket," and receives "hello websocket" back from the server.
*   **Debugging:** The audience asks about debugging tools. The speaker attempts to show browser developer tools but struggles with Mac keyboard shortcuts and NetBeans behavior, eventually relying on the application's visual output.

### **Coding Demo 3: JSON Processing**
The speaker introduces the **Java API for JSON Processing (JSON-P)**, new in Java EE 7. He explains that it provides a standard API layer over existing implementations (like Jackson or GSON).

*   **Encoders/Decoders:** He explains that WebSocket endpoints can register multiple encoders and decoders to handle different message formats.
*   **Creating a Decoder:**
    *   He creates a class `JavaDecoder` implementing `Decoder.Text<String>`.
    *   **Interface Methods:** He implements the required methods: `init`, `destroy`, `willDecode` (returning `true`), and `decode`.
*   **Parsing JSON:** Inside the `decode` method, he uses `Json.createReader()` to read the input string and `readObject()` to create a `JsonObject`. He extracts the value associated with the key "message" and returns it.
*   **Client Update:** He modifies the client JavaScript to send a JSON string: `{'message': '...'}` rather than plain text.
*   **Testing:** After a "Clean and Build" to resolve deployment issues, the app successfully parses the JSON and echoes the message content.

### **Coding Demo 4: Path Parameters**
*   **Implementation:** The speaker demonstrates how to use path parameters by changing the endpoint annotation to `@ServerEndpoint("/echo/{name}")` and adding `@PathParam("name") String name` to the method signature.
*   **Troubleshooting:** He encounters issues where the browser or server caches old configurations. He manually undeploys and redeploys the application and hardcodes the client URL to include a name (e.g., `SD Echo/echo/jug`) to make it work.

### **Deep Dive Q&A**
**WebSockets vs. REST (JAX-RS):**
*   **Use Cases:** WebSockets are ideal for proactive, asynchronous server-to-client messaging without polling. REST is strictly request-response.
*   **Performance:** WebSockets are better for low-latency applications (e.g., first-person shooters, financial trading) because they avoid the overhead of HTTP headers. The speaker mentions that HTTP overhead can be 20x larger than a small payload like "Hello World".

**Security:**
*   **Encryption:** You can use `wss://` for SSL/TLS encrypted connections (similar to HTTPS).
*   **Authentication:** Authentication happens during the initial HTTP handshake. Once upgraded to a WebSocket, it is a raw TCP stream.
*   **Cookies/Session:** The speaker is unsure if the API exposes cookies directly but notes you can access a `Session` object and `EndpointConfig`. He suggests storing user identity properties in the `Session` map during the handshake.

**Session Management & Broadcasting:**
*   **Broadcasting:** To build a chat app, developers maintain a collection of open `Session` objects. When a message arrives, they iterate through the collection and send the message to all peers using `session.getBasicRemote().sendText()` or `getAsyncRemote()`.

**Connection Lifecycle:**
*   **Failures:** If a client crashes, the underlying socket closes, eventually triggering the `onClose` event on the server, allowing for resource cleanup.
*   **Keep-Alive:** The protocol supports Ping/Pong frames to keep connections alive through proxies that might otherwise kill idle connections.

**Load Balancing:**
*   **The Challenge:** Standard HTTP load balancers might fail because WebSockets create long-lived, stateful connections (stickiness).
*   **Solution:** The speaker admits this is a complex area ("You've stumped the monkey") but suggests that specialized load balancers (like Oracle Traffic Director) are required to handle WebSocket stickiness and high availability.

### **Conclusion**
The speaker concludes the presentation. The host presents him with a "wayback machine" mug as a thank you, and the session ends.