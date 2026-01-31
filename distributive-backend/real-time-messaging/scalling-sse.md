Resource: https://youtu.be/bwgYHGJxLKY

Based on the provided transcript, here is a comprehensive and accurate extraction of the video's content, detailing the challenges and solutions for scaling Server-Sent Events (SSE).

### **Introduction and Project Context**
The speaker begins by discussing a recent project involving the implementation of a real-time notification service within a NestJS application. They chose Server-Sent Events (SSE) over WebSockets because SSE is simpler to set up and configure, whereas WebSockets are better suited for use cases requiring bi-directional communication, such as chat applications.

### **The Problem: Production Failures**
While the service worked during development, it failed completely when deployed to production due to the environment configuration. Two specific technologies caused these issues:

1.  **PM2 (Cluster Mode):** The production environment used PM2 to run the Node.js application in cluster mode. This mode creates multiple instances of the application across available machine cores to load balance incoming HTTP requests automatically. However, PM2 documentation states that applications in cluster mode must be stateless. Stateful services like SSE (or WebSockets), which rely on persistent connections, fail because a client might connect to one instance while the trigger request hits a different instance.
2.  **Nginx (Reverse Proxy):** The application sat behind an Nginx reverse proxy to enable SSL. Nginx acted as a load balancer (though PM2 handles this too). The issue arose because Nginx is configured to kill SSE connections after one minute of inactivity.

### **Demonstration of the Problems**
To illustrate these issues and their solutions, the speaker created a demo NestJS application using Docker for Nginx and Redis.

**The Initial Code Setup (Failure Replication)**
In the initial branch, the application uses a standard controller with three routes:
*   A "Hello World" route that returns the process ID (PID) for debugging cluster mode.
*   An SSE route (`/sse`) where the web client establishes a connection. It returns an observable subscribed to an internal event emitter.
*   A trigger route (`/fire-event`) that accepts data via HTTP and pushes it to the event emitter to notify connected clients.

**Demonstrating the PM2 Issue**
*   **Without PM2:** When running normally on port 3000, the application works correctly. A Python HTTP server serves a simple web client that uses the `EventSource` API to connect. Clicking a button hits the trigger endpoint, and the data (including the single PID) is returned to the client successfully.
*   **With PM2:** When running with PM2 across four cores (`pm2 start ... -i 4`), four instances are created. The web client shows different PIDs for requests due to load balancing. Crucially, when the "fire event" button is pressed, the client receives **nothing**. This is because the SSE connection might be established with Instance A, but the HTTP request to fire the event might be routed to Instance B.

**Demonstrating the Nginx Issue**
The speaker configures a Docker container for Nginx, mapping the internal port 80 to external port 8080. The `nginx.conf` sets the application behind the proxy. A specific setting, `proxy_read_timeout`, defaults to 60 seconds.
*   When the web client connects via port 8080, the connection is initially successful (status is blank/open).
*   However, after waiting for one minute without activity, Nginx kills the connection, and the status changes to "closed".
*   The speaker notes that while increasing the timeout number is possible, it is not an ideal solution because it would prevent Nginx from killing other stalled HTTP requests.

### **The Solutions**
The speaker switches to the `master` branch to demonstrate the fixes for both issues.

**Fixing the PM2/Scaling Issue: Redis Pub/Sub**
To ensure all application instances are aware of events regardless of which instance receives the trigger, the speaker introduces a Redis layer using its Pub/Sub (Publish/Subscribe) feature.
*   **Logic:** When an application instance receives a request to fire an event, it publishes that event to a Redis channel. The Redis server then notifies *all* subscribed application instances. Each instance then emits the event to its own connected SSE clients.
*   **Implementation:** The code is updated to use two Redis clients: one for publishing and one for subscribing (a single client cannot do both). The `subscribe` method listens to the Redis subscriber and returns an observable. The `emit` method uses the Redis publisher to push data to the channel.

**Fixing the Nginx Timeout Issue: Heartbeat (Ping)**
To prevent Nginx from closing the connection due to inactivity, the speaker implements a "heartbeat" mechanism.
*   **Implementation:** Inside the service constructor, an interval is set to run every 30 seconds.
*   **Logic:** This interval emits a dummy event (type: `ping`) to the stream. This activity resets the timeout counter in Nginx, keeping the connection alive as long as the client and server remain connected.

### **Final Verification**
The speaker performs a final test with the fixed code:
1.  **Infrastructure:** Docker containers are started, running Nginx (port 8080) and Redis (port 55000).
2.  **Application:** The NestJS application is recompiled and restarted in PM2 cluster mode (4 instances).
3.  **Results:**
    *   **Scaling:** Events are now received successfully by the client, even though the PIDs are different (indicating different instances are handling the requests).
    *   **Persistence:** "Ping" messages appear every 30 seconds. The connection remains open and active indefinitely (longer than the previous 1-minute limit).

The video concludes by confirming that these changes allow the SSE service to scale correctly across multiple cores and persist behind a reverse proxy.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?