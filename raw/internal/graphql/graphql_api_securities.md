Resource: https://youtu.be/OOztEJu0Vts

Based on the transcript of the presentation "Understanding how to hack GraphQL" by Nick Aleks at the GraphQL Wroclaw Meetup, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Agenda**
Nick Aleks, the Chief Hacking Officer for Asec and author of the book "Black Hat GraphQL," introduces the session focused on offensive GraphQL security. He outlines three main learning objectives for the presentation:
1.  **Inefficiency of Traditional Security:** Understanding why traditional security methods for web applications and REST APIs fail to protect GraphQL workloads.
2.  **Hacker Methodology:** explaining how hackers approach and break into GraphQL applications.
3.  **Tooling:** Putting hacker tools into the hands of developers to test their own systems and implement them into CI/CD pipelines.

### **Why Traditional Security Fails**
Traditional security tools, such as Web Application Firewalls (WAFs) and rate monitors, come up short because they are optimized for REST, not GraphQL payloads.
*   **Status Codes:** Traditional WAFs often rely on HTTP status codes (like 401 or 403) to detect brute force attempts. However, GraphQL typically returns a 200 OK status code for all requests, regardless of errors, rendering this logic ineffective.
*   **Client Control:** GraphQL shifts power to the consumer/client, allowing them to batch requests and use aliases. This makes it difficult to uncover the true nature of requests and identify anomalies.

### **Tool 1: Clairvoyance (Schema Extraction)**
Aleks discusses "Introspection," a native GraphQL feature that acts as a blueprint for the API, revealing queries, mutations, and fields. He uses the analogy that while sharing a bank's blueprints doesn't inherently make it insecure, it gives robbers significant information on where weaknesses lie. Consequently, introspection is usually disabled in production.

To bypass disabled introspection, hackers use **Field Suggestions**. When a client sends a typo (e.g., "Pas"), a friendly GraphQL server will suggest corrections based on the schema (e.g., "Did you mean passes or paste?").
*   **Clairvoyance:** This tool exploits field suggestions. It uses a wordlist to brute-force the server, using the "Did you mean?" responses to reconstruct the schema.
*   **Visualization:** Aleks demonstrates this against a "Damn Vulnerable GraphQL Application" (DVGA), showing how Clairvoyance recovered a significant portion of the schema using 3,000 English words.

### **Tool 2: CrackQL (Brute Forcing)**
**CrackQL** is a brute-forcing utility that exploits the GraphQL concept of **Aliases**.
*   **Aliases:** These allow a client to send multiple nested queries in a single HTTP request and specify how the data is returned.
*   **Attack Vector:** CrackQL automates attacks like password brute-forcing, user enumeration, and OTP (One-Time Password) bypass. It takes inputs (like a CSV of usernames and passwords) and programmatically generates a single query containing multiple aliases (Alias 1, Alias 2, etc.).
*   **Bypassing Controls:** By batching requests into a single payload, attackers can fly under the radar of rate limits and complexity analysis.

### **Tool 3: GraphQL Threat Matrix**
Aleks introduces the GraphQL Threat Matrix, a research project tracking security considerations across various GraphQL implementations (Ruby, Java, Python, etc.).
*   **What it Tracks:** The matrix monitors default behaviors, such as whether field suggestions are enabled (most are), and if security controls like query depth limits, cost analysis, or introspection are present.
*   **Purpose:** It helps developers assess how "secure by default" their implementation is and provides hackers a launchpad to identify features to exploit based on the underlying technology.
*   **Validations:** The matrix also tracks "Validations"—rules that ensure queries adhere to the spec. Aleks notes that some implementations lack basic validations (e.g., checking for fragment cycles), meaning a single malicious query could crash the server.

### **Tool 4: GraphW00f (Fingerprinting)**
Similar to how "WafW00f" identifies WAFs, **GraphW00f** sends random queries to a server to identify which GraphQL engine is running (e.g., Graphene, Apollo, Sangria).
*   **Methodology:** It analyzes the subtle differences in error messages and responses. For example, Sangria might reply "fragment a is not used," while Apollo might say "fragment a is never used." These nuances allow the tool to fingerprint the specific implementation.

### **Tool 5: GraphQL Cop (Static Analysis)**
**GraphQL Cop** is a tool designed to be integrated into CI/CD pipelines. It runs scans to highlight vulnerabilities "out of the box".
*   **Checks:** It scans for issues like enabled GET requests (CSRF risk), alias overloading (DoS risk), field duplication, circular queries, and enabled field suggestions.
*   **Performance:** The scan is fast, taking only a few seconds.

### **Educational Resources**
*   **Damn Vulnerable GraphQL Application (DVGA):** An intentionally vulnerable app built on Graphene/Python. It serves as a dojo for learning vulnerabilities. Aleks warns users to run it in an isolated, trusted network, not in production.
*   **Black Hat GraphQL (Book):** Aleks promotes his book, which covers these topics in depth, including how to build a hacking lab.

### **Q&A Session**
1.  **SQL Injection:** When asked if SQL injection is a concern in GraphQL, Aleks answers "100% yes." Just because an application uses GraphQL, it is not immune to traditional vulnerabilities like SQL injection, XSS, or IDOR. The strong typing makes it slightly harder to find, but they are still present.
2.  **SaaS WAF Solutions:** A question was raised about SaaS WAFs preventing attacks like Aliases. Aleks mentions that vendors like Cloudflare (via custom Edge Workers), Inigo, and ThreatX are developing solutions. However, the space is currently immature, often requiring in-house rule creation rather than relying on "out of the box" defaults.
3.  **Production Readiness:** Asked if open GraphQL APIs are ready for production given the immaturity of security tools, Aleks advises caution. He recommends not putting GraphQL in a critical path unless it has undergone a security audit/penetration test and is supported by a security team that understands GraphQL anomalies. However, he does not suggest avoiding it entirely, only that one shouldn't assume it is secure by default.


Q: How can I check if my GraphQL API's vulnerable to SQL injection?

Q: How does 'alias overloading' to DoS work?

Q: Which GraphQL implemenation being considered most secure by default?


# Resource: https://youtu.be/2peiqLuKKgs

Based on the transcript of the video "Understanding GraphQL Security: Protecting Your Server from Abuse" by Erik Guzman, here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Background**
Erik Guzman introduces himself as a full-stack software engineer at a consultancy called Zeal, a Microsoft MVP in developer tools, a content creator, and an open-source contributor. He notes that through his mentoring of both experienced and junior developers, a common theme is a lack of familiarity with the unique security implications of GraphQL. He is also a "Trekkie".

### **The Scenario: Star Trek Lower Deck Devs**
To illustrate the concepts, Guzman sets a themed story involving developers in "Starfleet" implementing a brand new knowledge base interface powered by "Subspace GraphQL".
*   **The Setup:** The API is rolled out everywhere (starships, shuttles, starbases, outposts, and PADDs). The developers, used to REST, applied standard security principles like authorization, rate limiting, and Role-Based Access Control (RBAC).
*   **The Misconception:** The developers believe the job is done and the API is secure.
*   **The Reality:** Guzman quotes *Black Hat GraphQL*: "A feature can turn into a weakness, a misconfiguration can turn into an information leak, and an implementation design flaw can lead to a Denial of Service attack".
*   **False Security:** The devs rely on "security by obscurity," assuming they are safe because the API is internal-only and tools like GraphiQL/Studio are disabled in production.
*   **The Threat:** "Officer O," a Romulan mole within Starfleet, uses the LCARS element inspector to find the API endpoints and exploit the system.

### **Vulnerability 1: Introspection**
*   **The Attack:** Officer O uses introspection (which she brands "Inpection") to conduct reconnaissance. Even if the graphical interface (GraphiQL) is disabled, she can craft a raw query to get schema information back.
*   **The Risk:** This exposes sensitive information and allows probing for new or misconfigured fields.
*   **The Solution:** Disable introspection entirely. Implementation varies by backend server; some are disabled by default, while others require plugins or custom code.

### **Vulnerability 2: Field Suggestions**
*   **The Feature:** When a query has a typo (e.g., missing "Home World"), GraphQL suggests a correction ("Did you mean Home World?").
*   **The Attack:** Even with introspection disabled, Officer O uses automated tools to randomly guess common field names. The "Did you mean?" error messages reveal the actual schema structure.
*   **The Solution:** Disable field suggestions to prevent leaking the schema through error messages.

### **Vulnerability 3: Cyclical Queries (Depth)**
*   **The Attack:** Officer O crafts a query that nests endlessly: fetching Federation, then Starships, then their Captains, then the Ships those Captains serve on, then the Captains of those ships, and so on.
*   **The Impact:** This is a "cyclical request." It hogs memory and CPU, locks up the database and server, and bypasses standard REST-style rate limits because it occurs within a single request.
*   **The Solution:** Apply a **Query Depth Limit**. Restricting the depth (e.g., to 5 or 10 levels) prevents the server from processing indefinitely deep queries.

### **Vulnerability 4: Field Stuffing (Width)**
*   **The Attack:** Officer O adopts the mantra "Mo' fields, mo' problems." Instead of going deep, she goes wide ("Field Stuffing"). She requests large lists (crew members) and packs as many fields as possible into the query.
*   **The Impact:** Even if a request returns a single field, the server must parse and resolve every field requested before returning the data. This wastes CPU cycles and memory, potentially causing a Denial of Service (DoS).
*   **The Solution:**
    1.  **Cost Analysis:** Assign a cost to fields. A simple name might cost 1, while a "Current Location" (requiring live data) might cost 100.
    2.  **Cost Limit:** Set a maximum cost per request (e.g., 500). The parser calculates the total cost before resolution and blocks the request if it exceeds the limit.
    3.  **Pagination:** For fields returning lists (like crew members), use connections/pagination to prevent unbounded retrieval of thousands of records.

### **Vulnerability 5: Aliases**
*   **The Feature:** Aliases allow fetching multiple data points in one request (e.g., fetching Kirk and Spock simultaneously).
*   **The Attack:** Officer O uses aliases on **Mutations** to perform a brute-force attack (e.g., trying to override security codes).
*   **The Impact:**
    *   It bypasses depth, cost, and rate limits because all resolutions happen in one request.
    *   It creates memory issues because the server must track aliases and reassign them after resolution. An unbounded amount of aliases can crash the server.
*   **The Solution:** Limit the number of aliases allowed per request or disable aliases entirely (though disabling them breaks legitimate features).

### **Vulnerability 6: Directives**
*   **The Feature:** Custom directives, such as a translation directive to convert text to Klingon.
*   **The Attack:** Officer O notices the directive takes processing time and repeatedly applies it to fields to overload the server.
*   **The Impact:** Hogging CPU/Memory leads to information overload and crashes.
*   **The Solution:** Disable client-side directives if possible, limit directive usage, and strictly monitor custom directives to ensure they are optimized (e.g., caching, timeouts).

### **Recap and Implementation**
Guzman summarizes the mitigations:
1.  Disable Introspection.
2.  Disable Field Suggestions.
3.  Implement Query Depth Limits.
4.  Implement Cost Limits (customizing costs for expensive fields via APM analysis).
5.  Limit or disable Aliases (especially on mutations).
6.  Disable, limit, or monitor Directives.

### **Tools and Resources**
*   **Platform Specifics:** Customization varies by platform. Ruby GraphQL has depth/complexity limits built-in (but not enabled by default).
*   **GraphQL Armor:** For Node-based servers, Guzman recommends "GraphQL Armor" by The Guild, which enables these protections with good defaults.
*   **Learning Resource:** He recommends the book *Black Hat GraphQL* for learning how to attack (and protect) APIs, noting it includes instructions on setting up Kali Linux.
*   **Blog Post:** He provides a QR code linking to a blog post summarizing the talk.

### **Conclusion**
Guzman thanks the audience for attending his talk instead of "Puppy Playtime," shares his social handle (`@talktomegooseman`), and mentions he will be available at the desk to discuss GraphQL security or why "Picard Season 3 is the best season".


# Resource : https://youtu.be/GihtMPMgpVI

Based on the transcript of the video "OWASP Top 10 in GraphQL: An API Adventure" by Danielle Rosenfeld-Lovell at BSides Canberra 2024, here is an accurate extraction of the presentation from start to end:

### **Introduction and Background**
Danielle Rosenfeld-Lovell introduces herself as a penetration tester (pentester) with a preference for web technologies, who is also dabbling in cloud and secure code review. She shares personal details, noting she is a "proud cat mom" and a prolific knitter.

She outlines the target audience for the talk:
1.  **Security Beginners:** People just getting to know the field. Web applications and APIs are the "bread and butter" of a pentester's daily work, though often not given the enthusiasm they deserve.
2.  **Job Seekers:** Knowledge of the OWASP Top 10 is crucial for employment and frequently appears in job descriptions.

The goal of the presentation is to run through the OWASP Top 10 listings using a "slightly less commonly encountered technology" (GraphQL) as the vehicle for discussion. Specifically, she clarifies that while the Web Application Top 10 was released in 2021, she will be using the **2023 API Security Risk** listing.

### **GraphQL Theory and Concepts**
**Definition:**
GraphQL is described as one of many options for a web front end to talk to a backend server. It is widely supported across frameworks and languages. It was developed by Meta (formerly Facebook) in 2012. It is "graph-y" because it defines an API schema or structure that looks like a hierarchical tree—objects encompass other objects, eventually terminating in "fields" (concrete data).

**GraphQL vs. REST:**
A key differentiator is the endpoint structure:
*   **GraphQL:** You interface with **one single endpoint**.
*   **REST:** Is "resource-oriented," meaning there is one unique URI per resource (e.g., `/dog`, `/dog/bone`). In complex systems, REST leads to a massive number of endpoints, which complicates inventory management and future refactoring. GraphQL's single endpoint offers a security win by requiring less inventory management.

**Schema Definition Language (SDL):**
This is a human-readable, JSON-like language used to facilitate information transmission. It enables GraphQL to be language-agnostic.
*   **Objects:** Entities like `Cat`.
*   **Fields:** Variables defined at runtime (e.g., `name`, `color`, `loud`).
*   **Scalars:** Concrete data types including strings, booleans, floating-point numbers, and integers.
*   **Enums:** Self-defined lists of named values (e.g., selecting specific colors like `beige` or `white`).

**CRUD Operations (Create, Read, Update, Delete):**
Rosenfeld-Lovell explains the core operation types in GraphQL:
1.  **Query:** Handles reading data (e.g., a user accessing their account data).
2.  **Mutation:** Handles data change, including object creation, deletion, and updating variables.
3.  **Subscription:** Handles real-time updates (like emergency SMS notifications). She notes this is less applicable to the talk's context.

**Introspection:**
In a computational sense, this mirrors personal introspection (looking inside oneself). In GraphQL, enabling introspection allows a user to directly query the schema to get all information about how to use the API. It is enabled by default. This is significant for testers because, unlike REST where content discovery can take days, GraphQL introspection hands all API functional information to the tester "on a platter".

### **The Test Environment**
The speaker uses a "Damn Vulnerable GraphQL App" (DVGA), which is easy to set up locally via Docker. The app functions as a public messaging forum allowing public comments and private comments (referred to as "pastes").

### **The OWASP Top 10 (API 2023) Walkthrough**
Rosenfeld-Lovell proceeds through the security risks, noting that OWASP documentation is strong because it is developer-focused and targets root causes and business logic failures rather than just vulnerability classes.

**API 1: Broken Object Level Authorization (BOLA)**
Formerly known as IDOR. This involves an improper ability to read or change something at the object level.
*   *Example:* Identifying an easy-to-enumerate object ID for a paste allows a user to mutate (deface) anyone's public paste due to a lack of authorization controls.

**API 2: Broken Authentication**
*   *Example:* Login bypass or cookie manipulation. In the DVGA lab, a "GraphQL Development Environment" is restricted. However, simply changing a cookie value from `disable` to `enable` bypasses the check, illustrating a failure to tie user identity to a session ID securely.

**API 3: Broken Object Property Level Authorization**
This occurs at the level of a field or variable within an object. It has two sub-classes:
1.  **Excessive Data Exposure:** Seeing every other user's public IP address.
2.  **Mass Assignment:** Manipulating hidden parameters. For example, injecting a `role` parameter and setting it to `admin` in a request where that role was not originally introduced.

**API 4: Unrestricted Resource Consumption**
Tying up computational resources (Denial of Service) or causing excessive operational expenses. GraphQL has two notable susceptibilities:
1.  **Query Batching:** Stacking multiple queries into a single request to bypass rate limits (processed in parallel).
2.  **Recursion:** Nesting queries within queries (due to the hierarchical tree structure) to create a resource-intensive request.
*   *Mitigations:* Max query depth limits, request timeouts, returning cached responses, and cost analysis (though cost analysis can be computationally expensive itself).

**API 5: Broken Function Level Authorization**
Leaving "God-like" administrative operations accessible.
*   *Example:* Running a mutation to `delete_all_pastes` thinking it affects only the user's own data, but actually deleting all data across the entire system.

**API 6: Unrestricted Access to Sensitive Business Flows**
Using automation (bots) to trigger sensitive business functionality.
*   *Examples:* Spamming a message board with 100 comments or scalping concert tickets.
*   *Defense:* Making processes multi-step can help, but determined attackers can script around this. It requires comprehensive protection.

**API 7: Server-Side Request Forgery (SSRF)**
The only specific vulnerability class in the list. This is accessing a network resource in an unintended way.
*   *Example:* Using a vulnerable file import function to access a web service running on the local device. In real scenarios, this often requires "inference-based" investigation.

**API 8: Security Misconfiguration**
A broad category.
*   *Example:* Introspection (mentioned earlier) being enabled, allowing attackers to identify secret administrative functionality easily.

**API 9: Improper Inventory Management**
Poor visibility over what a product does.
1.  **Documentation Blind Spots:** Documentation is missing or unmaintained.
2.  **Data Flow Blind Spots:** Poor oversight on data flowing between the app and third-party services.

**API 10: Unsafe Consumption of APIs**
Providing excessive trust to third-party APIs.
*   *Examples:* Consuming data without input validation (leading to injection vulnerabilities) or sharing sensitive data with a third party without verifying they apply equal security rigors.

### **Conclusion**
Rosenfeld-Lovell concludes that GraphQL is flexible, elegant, and widely supported. Its use of a single endpoint interface is a key difference for testing. The OWASP Top 10 applies to GraphQL just as it does to other architectures, though testing differs due to specific features like introspection and the direct control users have over application logic via queries.



# Resource: https://youtu.be/xEMgrRHlwfI

Based on the transcript of the video "GraphQL Security Vulnerabilities in the wild" by Tristan Kalos, here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Background**
Tristan Kalos introduces himself as the co-founder and CEO of Escape, a GraphQL security company. He is a French engineer in operations research and machine learning who has lived in Argentina, the US, and Spain. He founded Escape because, despite loving GraphQL, he struggled to secure it. Escape is an automated security testing tool that identifies vulnerabilities and provides solutions.

The presentation focuses on a research study conducted over the previous month involving the scanning of over 2,000 GraphQL endpoints to understand the state of GraphQL security in production.

### **Methodology: Finding the Endpoints**
To conduct the study, the team needed to locate GraphQL endpoints on the internet.
*   **The Source:** They started with a list of approximately 200 million domain names.
*   **The Tooling:**
    *   Initially, they used their open-source Python tool, **GraphFinder**. This tool uses subdomain enumeration, script analysis, and brute force to detect GraphQL endpoints.
    *   **The Problem:** Scanning millions of domains with Python was too slow (it would take days).
    *   **The Solution:** They rewrote the scanner completely in **Go** (Golang) to create a faster tool (referred to in the transcript as "Google," likely a transcription error for a specific internal tool name).
*   **The Result:** They successfully identified roughly 2,400 to 2,500 public, open GraphQL endpoints.

### **Methodology: Automated Testing**
Scanning thousands of endpoints manually is impossible, so they needed an automated approach. Tristan outlines two major challenges in automating GraphQL security testing:

1.  **Passing Validation Layers:**
    *   Sending random data (fuzzing) usually fails because APIs block requests that don't match expected formats (e.g., sending a random string instead of a valid ID). The request never reaches the actual code behind the validation layer.
    *   **Solution (Feedback Driven API Exploration):** They developed an algorithm that interacts with the API to learn what data is expected. This allows the scanner to generate requests that make sense from a business perspective (e.g., sending a valid email format instead of a random string) to pass validation.

2.  **Graph Structure:**
    *   Because GraphQL is a graph, proper testing requires going deep into the resolvers and their combinations.
    *   **Solution:** They implemented a **Graph Traversal Algorithm** to recursively explore all paths in the GraphQL specification, ensuring deep coverage of resolvers.

### **Vulnerabilities Tested**
The automated scanner checked for a specific set of vulnerabilities, many of which overlap with topics discussed by Nick (a previous speaker):
*   Rate limits.
*   Query size limits.
*   **Broken Object Level Authorization (BOLA):** Testing if data can be accessed by iterating IDs or without proper authorization.
*   HTTP/SSL errors and misconfigurations.
*   **Information Disclosure:** Leaking source code or server details.
*   Request Forgery.
*   **Injections:** SQL, NoSQL, etc.
*   Sensitive Data leaks (emphasized as very important).

### **Study Results**
They fully scanned 1,600 unauthenticated endpoints (endpoints open to the internet with introspection enabled). The scan took over 400 cumulative hours and raised **46,000 security alerts**.

**Statistics:**
*   **Frequency:** An average of **30 alerts per application**. This indicates that best practices are not widely applied in GraphQL production environments.
*   **Severity:** More than 50% of alerts were Medium severity, and approximately 10% were High severity.
*   **Types of Alerts:**
    *   HTTP misconfigurations (headers) were most common.
    *   **GraphQL Specifics:** A significant number of alerts were related to Complexity, Denial of Service (DoS), and Information Disclosure.
    *   Access Control problems were frequent.
    *   Introspection issues (schema reconstruction).
    *   Critical vulnerabilities like Injections and Request Forgeries were less frequent but still present.

**Breakdown of Specific Vulnerabilities:**
The most common technical vulnerabilities found were:
1.  **Aliasing / No Alias Limits:** Allows batching attacks.
2.  **Directive Overloading:** A DoS vector.
3.  **Field Suggestion Activated:** Even if introspection is disabled.
4.  **Secret Leaks:** Public disclosure of sensitive data without authentication.
5.  **Injections:** SQL and NoSQL (e.g., MongoDB) injections were found, proving they still exist in GraphQL.

Tristan notes that the top vulnerabilities are specific to the GraphQL language, proving that community best practices are not yet well-spread.

### **Deep Dive into Top Vulnerabilities**
Tristan details specific GraphQL flaws found during the study:

1.  **Batching and Aliasing:** Attackers can send multiple queries in a single HTTP request to bypass rate limits (e.g., brute-forcing login credentials).
2.  **Directive Overloading:** Directives are often parsed in quadratic time. A small request (100kb) filled with directives can lock up a server for a minute. This was a common Denial of Service vector.
3.  **Recursive Fragments:** Fragments that call themselves can create infinite recursion and crash the server. While awareness is growing, it remains a frequent issue.
4.  **Field Suggestions (The "Clairvoyance" Attack):**
    *   Many companies disable introspection to hide their schema ("Security by Obscurity").
    *   However, if **Field Suggestions** ("Did you mean X?") are left on, attackers can use tools like **Clairvoyance** to reconstruct the entire schema.
    *   **Real-world Example:** Tristan describes an audit where a company disabled introspection but left suggestions on. The team reconstructed the schema, found an unprotected `updateAdmin` mutation, and successfully changed the admin's username and password without authentication.

### **Sensitive Data Leaks**
The study found over 4,000 potential data leaks.
*   **Findings:** Emails (some support, some sensitive), generic secrets, API keys, AWS tokens, and Adobe client IDs.
*   **Concern:** These were publicly accessible without authentication.
*   **Implication:** Automation allows attackers to find these secrets at scale. If Escape can automate this discovery, malicious actors will too.

### **Conclusion**
Tristan summarizes that they scanned 1,500+ endpoints and found numerous vulnerabilities, particularly those specific to GraphQL (DoS, Access Control) and Secret Leaks. He emphasizes the need for better best practices and recommends the book "Black Hat GraphQL" for the offensive perspective.

### **Q&A Session**
*   **Schema Introspection:** A question was asked about turning off introspection. Tristan reiterated that it is tricky because Field Suggestions must also be disabled, otherwise the schema is still visible.
*   **Separating Public vs. Admin APIs:** A question was asked about whether to split schemas for public users and admin users.
    *   **Tristan's Advice:** If the schemas share 90% of the types, they can be kept together with rigorous testing. However, if they are significantly different, he advises creating separate endpoints to avoid accidentally exposing admin features due to Access Control flaws.
*   **Closing:** The host thanks Tristan and acknowledges the previous speaker, Nick.