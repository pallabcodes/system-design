Resource: https://youtu.be/N7crSqyYZB4

Based on the video transcript, here is a comprehensive extraction of the presentation "GraphQL in an enterprise - PayPal's story and best practices" by Shruti Kapoor, from start to end.

### **Introduction and Personal Context**
Shruti Kapoor, a Senior Software Engineer at PayPal, begins by setting the stage for discussing GraphQL adoption in an enterprise. She introduces herself and shares her social media presence, specifically highlighting her activity on Twitter and Twitch. She discusses the personal toll of the pandemic, noting "pandemic fatigue" and the loss of collaboration and the simple joy of working in cafes. To combat the isolation of working from home, she started Twitch streaming co-working sessions where community members can hang out and work on side projects together for a couple of hours.

### **Shruti’s Journey and the State of GraphQL**
Before joining PayPal, Shruti had no knowledge of GraphQL, assuming it was related to graph data structures or GraphCMS. Upon joining PayPal, she was assigned to build an internal tools app that required consuming five APIs: one new Rust API being built from scratch and four existing APIs owned by other teams. At the time, most existing APIs were REST, and her team was building a new Node.js app.

In 2018, GraphQL was very new at PayPal, with the Checkout team serving as trailblazers. There was little internal infrastructure support, and adoption was driven by teams taking it on as side projects. Since 2018, the landscape has changed significantly. Major enterprises like Twitter, Facebook, Lyft, KLM, Intuit, Audi, and Atlassian are using GraphQL in production. The GraphQL Foundation now maintains the spec, and PayPal is a member.

Javascript is currently the most common implementation (GraphQL.js), and surveys like State of JS 2020 show it generates the highest interest among developers.

### **PayPal’s GraphQL Adoption Statistics**
PayPal has invested heavily in the technology:
*   There are approximately 50 apps in production using GraphQL.
*   Braintree released its public API in GraphQL.
*   The internal Slack community has nearly 500 members.
*   The Node infrastructure team provides support to spin up GraphQL servers and client-side apps instantly.
*   Internal training materials are available, and GraphQL has become the default pattern for new apps across teams like Checkout and Payments.

### **Challenges with REST APIs**
PayPal decided to adopt GraphQL to solve specific challenges they faced with their existing REST APIs:
1.  **Over-fetching:** Internal tool apps were fetching massive amounts of data from REST endpoints that were never used by the client.
2.  **Round Trips:** To get specific data (e.g., a user profile), the client often had to make an initial call just to retrieve an ID or username required for the subsequent profile call.
3.  **Versioning:** When APIs were updated to new versions (e.g., v2), clients integrated with older versions would miss updates because they didn't want to reintegrate.
4.  **Integration Experience:** Because APIs were built by different teams, naming conventions were inconsistent (e.g., "id" vs. other names), and documentation varied, making integration difficult.

### **Criteria for a New Solution**
When looking for a solution, PayPal required specific features:
*   **Freedom of Tech:** The solution needed to allow the use of any programming language on both the client and server side.
*   **Unified API:** They wanted to provide a single API experience (like the Braintree SDK) so they wouldn't have to convert SDKs for different languages.
*   **Uniform Frontend/Backend Layer:** They needed a layer to orchestrate APIs while providing a uniform frontend experience (Node.js/React).
*   **Easy Integration:** New teams or subsidiaries needed to integrate without prior domain knowledge (e.g., integrating with the Identity API without knowing PayPal specifics).
*   **Analytics:** They needed to understand exactly what data clients were fetching to solve over-fetching issues.

### **The Versioning Dilemma**
A common recurring problem was how to add new data. Adding a new version is good for breaking changes but leaves old clients behind. Adding a new endpoint or query parameters to an existing endpoint leads to pollution and trade-offs. GraphQL became the ideal candidate to solve this because it supports "One Endpoint," allowing unlimited updates without versioning.

### **Why GraphQL Was Chosen**
*   **Field Level Instrumentation:** Resolvers on every field allow PayPal to track usage and deprecate fields intelligently.
*   **Client Control:** Clients dictate the exact data they need, solving over-fetching.
*   **Developer Productivity:** Tools like GraphiQL and Playground allow developers to explore the API and fire requests without context switching.
*   **Schema as Contract:** The schema fostered collaboration between backend, frontend, and UX teams. "UI-powered schemas" meant the frontend could work independently once the contract was established.

### **Approaches to Adopting GraphQL in Enterprise**
Shruti outlines three main adoption patterns:
1.  **GraphQL Wrapper over REST:** Converting one API at a time or using a gateway layer to consume downstream REST APIs. This is useful when the backend remains in REST but a UI-driven API is needed.
2.  **REST Wrapper over GraphQL:** Building the ground-up layer in GraphQL but adding a REST wrapper to support clients that still require REST.
3.  **Coexistence:** Running both side-by-side, segmented by market segment or business logic.

### **PayPal’s Adoption Strategy**
PayPal utilized a mix of strategies:
*   **The "Try First" App:** They started with a low-impact internal tool (the Merchant App) to experiment without risking customer-facing impact.
*   **Standalone APIs:** New APIs were built in GraphQL from scratch.
*   **Orchestration:** Used heavily by frontend-heavy teams. The Checkout app is a "guiding light" example using a large GraphQL layer that orchestrates existing REST APIs and contains new business logic. Other teams use GraphQL purely as a proxy to downstream REST APIs.

### **Case Study: The First App**
For the internal tools app, the goal was to reduce data sent to the client. By using GraphQL:
*   They removed **Redux** entirely. Since they could request data in the exact shape needed, client-side formatting and state management were unnecessary.
*   Network requests became faster because no extra data was stored or fetched.
*   It functioned effectively as an orchestration layer, allowing the frontend team to reap GraphQL benefits without owning the downstream REST APIs or facing backend resistance.

### **Current Status and Benefits**
Currently, most frontend applications at PayPal are moving to GraphQL as the default UI pattern. While there is still some backend resistance, the orchestration model allows progress without "boiling the ocean." They are adopting it team-by-team but moving toward a **Federated One Graph** approach.

**Key Wins:**
*   **Performance:** Clients fetch only what they need, removing client-side overhead.
*   **Productivity:** Instant API exploration prevented time lost finding dependencies.
*   **Feature Shipping:** Features are shipped to the endpoint and clients consume them when ready, removing versioning headaches.

### **Common Misconceptions**
Shruti addresses questions they frequently fielded:
1.  **Graph Database Required?** No. You only need relationships between data types, not a graph DB.
2.  **Is it like SQL?** No. It is a query language for APIs, not databases.
3.  **Only for Javascript?** No. GraphQL is a spec implementable in any language.
4.  **Must Burn Down REST?** No. They can live side-by-side.
5.  **Security/Database Exposure:** You do not have to expose your entire database or sensitive data. You can implement auth/auth and choose exactly what to expose.

### **Lessons Learned**
1.  **Pick a Small First App:** Use a demo or low-impact app to test the fit.
2.  **Build Schema Together:** This improves team collaboration.
3.  **Orchestration is Powerful:** You don't need to change the entire stack.
4.  **Do Not Map 1-to-1:** A major mistake was creating a GraphQL schema that exactly mirrored the REST API. This added boilerplate without leveraging GraphQL's filtering capabilities. It required updating three places for every change.
5.  **Free Type Safety:** You get Typescript support and type checking out of the box.
6.  **Performance Warning:** GraphQL does not magically fix performance; the API is only as fast as its slowest downstream endpoint.

### **Challenges Faced**
*   **Error Handling and Caching:** GraphQL returns 200 OK for errors, requiring deep parsing of the error object to handle specific logic (like 404s vs 500s).
*   **Unknown Schema:** It is difficult to build a GraphQL API if you don't know the schema upfront.
*   **One Graph Ownership:** Coordinating a single graph across multiple teams with different adoption stages creates ownership challenges.

### **Checklist for Adoption**
Shruti provides a guide for those starting out:
*   **Assess:** Identify architecture problems, consumers, and where tools like auth and analytics fit.
*   **Build vs. Buy:** Determine if you build from scratch or wrap existing tools. Plan for training and measuring success (performance vs. productivity vs. time to market).
*   **Sell to Leadership:** Focus on collaboration and developer productivity. Use incremental adoption. Engage architects and domain experts.

### **Conclusion**
GraphQL is here to stay, but it is not perfect. Teams should evaluate if it is the right fit before jumping on the hype train. She recommends engaging with the community and reading resources like the PayPal Tech Blog and the book "Production Ready GraphQL". The talk concludes with a developer joke.