Resource: https://youtu.be/aI-wI14D1nw

Based on the video transcript, here is an accurate and comprehensive extraction of the presentation "An introduction to GraphQL security" by Christina Hastenrath, from start to end.

### **Introduction and Background**
Christina Hastenrath, a software engineer at Postman based in California, introduces the topic of GraphQL security. Her interest in the subject began when she built a Gatsby application on top of a WordPress blog using the `wp-graphql` plugin. Before going live, her security team discovered that the GraphQL endpoint revealed authors' email addresses. She worked with the plugin creator, Jason Bahl, and the community to fix this vulnerability, which sparked her interest in securing both her own and third-party GraphQL endpoints.

The presentation covers the building blocks of the GraphQL schema, how hackers and bug bounty hunters retrieve application data, real-world examples of vulnerabilities, and how to start securing endpoints. Hastenrath emphasizes that there is no "one-size-fits-all" solution; mixing and matching different approaches is necessary to minimize risk.

### **GraphQL Schema and Root Types**
GraphQL utilizes a type system defined by the Schema Definition Language (SDL) to describe how the API interacts with the backend. The schema consists of three root types:
*   **Queries:** Used to retrieve data, similar to a GET request in REST.
*   **Mutations:** Used for state-changing activities or modifying data, similar to POST, PUT, or DELETE requests.
*   **Subscriptions:** Used for real-time updates, such as tracking ratio updates between cryptocurrency and fiat money.

Unlike REST APIs, GraphQL does not use standard HTTP methods like GET or POST for different operations in the same way; queries and mutations define the intent.

### **Request and Response Structure**
In a GraphQL request, a client specifies fields and subfields. For example, a query might request a field called `cat` with the argument `name: "snowflake"` and the subfield `breed`. This demonstrates the power of GraphQL: the frontend fetches only the specific data it needs (the breed), even if more information about the cat exists.

To implement GraphQL, support must be added to both the client side (e.g., laptop, phone) and the server side. While resolvers are responsible for bringing data from the backend database, they are outside the scope of this specific talk.

### **Architecture: GraphQL vs. REST**
GraphQL funnels all queries through a single endpoint, regardless of whether the request is a query, mutation, or subscription. In contrast, REST APIs have multiple endpoints based on application entities. As app entities become more complex, REST endpoints become more complex and expensive to maintain.

**Strengths of GraphQL:**
*   **Efficiency:** It fetches exact data, avoiding the "entire menu" problem of REST where unnecessary data is returned.
*   **Network Performance:** A single query can perform multiple operations, whereas REST might require several requests.
*   **Development:** It requires less maintenance on the server side for every API call and is self-documenting, making it easier for new developers to learn.
*   **Versioning:** Unlike REST, GraphQL does not strictly require versioning maintenance.

**Weaknesses of GraphQL:**
*   **Introspection:** This query performs an operation to pull all information from the backend schema via SDL, allowing hackers to see all queries, mutations, and types.
*   **Client Exposure:** The client must share information about the API, commonly accessed via the `/graphiql` developer console.
*   **Complexity:** Queries can become deep and complex because multiple operations can be performed at once.
*   **Rate Limiting and Caching:** These are difficult to implement. For example, unauthorized requests might retrieve cached entries that were stored for authorized responses without checking backend access controls.

### **Why Security is Critical**
Malicious agents can use GraphQL to extract data or map infrastructure. Leaving endpoints unsecured can expose private, sensitive data. As GraphQL is relatively new, there are no established best practices yet, and the specifications do not provide security guidelines.

### **Common Vulnerabilities (OWASP)**
Hastenrath details common risks based on the Open Web Application Security Project (OWASP) consensus:

#### **1. Introspection**
Introspection allows anyone to retrieve the entire schema structure. Hackers often start here.
*   **Method:** A hacker can copy a standard introspection query (available in repos like "PayloadsAllTheThings") and run it against a vulnerable API.
*   **Visualization:** The output can be pasted into tools like **GraphQL Voyager** to visualize the business logic and see how fields connect, aiding in the creation of malicious mutations. This works even on major platforms like the Shopify storefront.
*   **Mitigation:** Disable introspection in production (e.g., using environment keys in Apollo Server), use service endpoint fusing, or use npm packages to disable it. It is also important to note that the endpoint might be nested (e.g., `/api/graphql` rather than just `/graphql`).

#### **2. SQL Injection**
Developers are responsible for security in GraphQL as it interacts with arbitrary code. Any string type field is potentially vulnerable.
*   **Method:** An attacker might add a single quote to an argument to cause a SQL syntax error. Even if no error is thrown, blind time-based injections are possible. Tools like **SQLMap** can be used, or injections can be crafted by hand using "Union Select" to return user IDs, names, and passwords.
*   **Mitigation:** Assume all user input is insecure, apply input validation, use prepared statements with parameterized queries, escape all user input, and enforce least privilege.

#### **3. Batching Attacks**
This involves sending multiple queries or mutations in a single request to bypass rate limits.
*   **Method:** This is often used for brute-force authentication (sending thousands of email/password pairs) or bypassing One-Time Passwords (OTP) by sending all token variants at once. Because it is a single large request, it might not be recognized as a brute-force attack.
*   **Mitigation:** Validate user input and limit the number of attempts on the web server side within the business logic.

#### **4. Denial of Service (DoS)**
Nested queries can turn into loops, causing resource exhaustion on the server.
*   **Mitigation:** Add query depth limiting, pagination for returned data, and application timeouts.

#### **5. Broken Object Level Authorization (BOLA)**
This occurs when authorization is not applied to specific data objects, allowing users to access data they shouldn't.
*   **Method:** Attackers access objects (like blog posts or user data) by manipulating IDs.
*   **Mitigation:** Perform authorization checks on every request, confirm identity with access tokens, implement access controls on all privileged endpoints, and use unpredictable IDs (like GUIDs).

### **Real-World Examples**
Hastenrath shares three specific case studies:
1.  **Arun S. (Pentester):** Discovered a company exposed a "super secret private mutation" intended only for staging cleanup tasks. Using a tool called **InQL Scanner**, he found he could wipe the entire database in production.
2.  **Sam Curry (Samdev):** Demonstrated how to exploit GraphQL's "autocorrect" feature. He observed that GraphQL suggests correct field names if the input is within a certain character length difference, if multiple fields are wrong, and that it is case-sensitive. He wrote an algorithm to brute-force the schema and enumerate field names, arguments, and types even with introspection disabled.
3.  **Instagram/Facebook:** A researcher named Mayur Fartade found a BOLA vulnerability in Instagram's GraphQL API. He could access private/archived posts, stories, and Reels of users without following them simply by knowing the Media ID. Facebook awarded him a $30,000 bounty for this discovery.

### **Securing Your Endpoint**
To secure a GraphQL API, Hastenrath suggests a mix-and-match approach:
*   **Basics:** Disable the endpoint from the domain, create custom schemas (avoid auto-generated ones), validate user input, and implement strong authentication and authorization.
*   **Depth and Complexity:** Enforce maximum query depth so deep or cyclic queries are rejected before execution. Implement query complexity analysis, assigning costs to fields and rejecting queries that exceed a maximum cost.
*   **Timeouts and Throttling:** Use timeouts as a fallback protection and enable throttling based on server time and complexity.

### **Resources and Tools**
The video concludes with recommended resources for learning and testing:
*   **Labs:** "Damn Vulnerable GraphQL Application" (DVGA) by Dolev Farhi and "GraphQL Security Labs".
*   **Tutorials:** "How to GraphQL" security section.
*   **Tools:** Postman (for testing as a client), StackHawk (for security testing), and InQL Scanner.