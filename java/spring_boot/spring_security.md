Resource: https://youtu.be/3nsnUmEaZ1U

Based on the provided transcript, here is an accurate and comprehensive extraction of the presentation "Building secure cloud native applications with spring boot and spring" by Andreas Falk from start to end.

**Introduction and Speaker Background**
Andreas Falk introduces himself and notes that while he is not primarily a security expert, he was impressed by the OWASP AppSec community in Amsterdam and wanted to present a session from a "Builder's view" or developer's perspective. He works for Novatec Consulting in Stuttgart, deals with Agile, Java EE, Spring, Cloud, and DevOps, and is an OWASP member.

**The Developer Mindset and Security**
Falk observes that developers love building software and adopting new technologies (Java 8/9, new hypes), but they generally do not fall in love with security. Developers dislike "management bullshit" (micro-controlling), but they dislike security almost as much.

In a daily Agile environment, a developer deals with a massive stack: Java, DevOps, Cloud, Single Page Applications (Angular/Reactive JS), Testing, Microservices, NoSQL, and Big Data. While developers are expected to be "cross-functional," security is rarely included in that skillset.

The reasons developers struggle with security are:
*   They do not feel like security experts.
*   Frameworks and APIs are not secure by default. Falk references a talk by Jim Manico about the need for secure-by-default APIs.

**Spring Boot and Secure Defaults (Live Demo)**
Falk introduces `start.spring.io` as the "second most important page" for Spring developers after Google. He demonstrates how to build a secure application from scratch:
1.  He selects a Maven project and adds dependencies for "Web" and "Security" (or Cloud Security for OAuth).
2.  Downloading the project provides a zip file containing an application that is secure by default.
3.  Upon starting the application, the console displays a generated default security password for the user "user".
4.  Falk demonstrates logging in via Basic Authentication using this generated password.
5.  He shows how to configure a static password (e.g., "secret") to replace the random generation.

This default application includes recommended security headers automatically:
*   Strict Transport Security (if SSL is used).
*   X-Content-Type-Options.
*   X-Frame-Options.
*   XSS Protection.

During a brief Q&A, Falk confirms that while Basic Auth is the default, Form Login is also supported.

**Defining Cloud Native**
Falk defines "Cloud Native" not just as technology (Docker/Containers), but as a culture.
*   **Culture:** Moving away from silos where developers hand off code to operations. In the old model, operations might delay deployment for months to check stability or security. Cloud Native requires Continuous Delivery to deploy fast and frequently.
*   **Maturity Model:**
    *   *Level 0 (Cloud Ready):* Self-contained artifacts (e.g., embedded Tomcat) with all dependencies included.
    *   *Level 1 (Cloud Friendly):* Horizontal scaling (multiple instances) rather than vertical scaling.
    *   *Level 2 (Resilient):* Self-repairing applications using isolation and circuit breakers, acknowledging that failures will happen.
    *   *Level 3 (Microservices):* API design first.
*   He references the "12 Factor App" methodology for further reading.

**Microservices Architecture**
The industry is moving from Monoliths (often becoming a "Ball of Mud") to Microservices.
*   **Characteristics:** Small pieces built by small teams (4-5 people). They are language agnostic (Java, C#, Python) and communicate via lightweight protocols (REST, messaging). They are loosely coupled; if one process breaks, the whole system does not fail. They allow scaling of individual processes.
*   **Technology:** On the Java side, there is a direct connection to Spring Boot. It provides auto-configuration, embedded containers, and builds JARs instead of WARs. It includes production-ready features like monitoring and health indicators.

**DevSecOps**
Falk discusses the "Secure Cloud Native" aspect. In typical DevOps, teams do Scrum and Continuous Deployment, but security is often handled via a single penetration test at the end of the process.
*   **The Problem:** Attackers operate on a 24/7 schedule and can attack any deployment. Testing only once before production is insufficient.
*   **The Solution:** Security must be integrated into every step of the development process:
    1.  Vision.
    2.  Product Backlog (Evil User Stories).
    3.  Sprint (Development/Testing).
    4.  Releasable Increment.
    5.  Operations (monitoring third-party libraries).

**Spring Security Features**
Spring Security is presented as a secure-by-default, configurable framework.
*   **Authentication/Authorization:** Supports Basic and Form login. Authorization is available at the UI, Method, and Database levels.
*   **Secure Defaults:**
    *   Authentication required for all endpoints.
    *   Session Fixation protection (new session ID upon login).
    *   Secure and HTTP-only session cookies.
    *   CSRF (Cross-Site Request Forgery) protection (handles tokens automatically).
    *   Security Headers: Caching disabled for sensitive content, X-Content-Type-Options, X-Frame-Options, XSS protection, and HSTS (Strict Transport Security).
    *   Content Security Policy (CSP) can also be configured to disable inline JavaScript.
*   **Password Encoding:** Spring provides an interface (`matches` and `encode`). It handles encryption and salting internally so developers never handle decrypted passwords. It avoids unsafe algorithms like MD5 or Base64.
*   **Input Validation:** Falk clarifies that Spring Security does *not* do input validation. This must be handled by the application (e.g., Bean Validation, Regex allow-listing). Spring Security only provides headers to prevent XSS.

**Cloud Security and OAuth2**
In Cloud architectures with multiple clients (SPA, Mobile, Server-side UIs), simple authentication like shared credentials (passwords) does not work.
*   **OAuth2:** Used to replace credential sharing.
*   **Roles:** OAuth Client (acts on behalf of user), Authorization Server (deals with credentials), and Resource Server (serves resources).
*   **Implementation:** Falk notes that creating a "Tweetable" OAuth application in Spring requires only two annotations to get a full Authorization Server. It supports basic access tokens as well as signed JWT (JSON Web Tokens) with public/private keys.

**Runtime Application Self-Protection (RASP)**
Falk introduces the concept of real-time security using **OWASP AppSensor**.
*   **Concept:** Instead of just detecting intrusions later, the application detects and reacts to attacks in real-time.
*   **Mechanism:**
    1.  Define **Detection Points** (e.g., multiple failed logins, large data uploads).
    2.  **Policy:** Determines if events constitute an attack.
    3.  **Response:** The application reacts (e.g., logout user, shut down part of the app, notify admin).
*   **Dashboard:** Falk shows a dashboard view where administrators can see activity logs and attacks (authentication events, input validation events) occurring in real-time.

**Conclusion**
Falk wraps up by summarizing the platform:
*   **Spring IO Platform:** Manages dependencies and updates third-party libraries when security leaks are detected.
*   **The Stack:** Spring Boot/Security (Secure defaults), Spring Cloud (Circuit breakers/Service discovery), OAuth libraries, and AppSensor for real-time protection.
*   **Future Wishes:** Falk expresses a desire for more "Secure by Default" developer APIs, citing Angular 2's strict XSS defenses and clear naming of "unsafe" APIs as a good example.

He concludes by sharing his GitHub for samples and recommending Jim Manico's book "Iron-Clad Java".