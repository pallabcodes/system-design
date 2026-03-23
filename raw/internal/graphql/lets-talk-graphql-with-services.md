Resource: https://youtu.be/DszRpn5dQq0

Based on the video transcript, here is an accurate and comprehensive extraction of the presentation "Let's Talk GraphQL With Your Services" by Roy Derks.

### **Introduction and "Pasta" Code**
Roy Derks introduces the topic of using GraphQL with existing services. He opens with a visual metaphor, asking if legacy code looks like "pasta" to the audience. He notes that while one cannot talk to pasta, one can view existing services as legacy code.

**Speaker Background:**
*   Roy Derks can be found on Twitter as `@gethackteam`.
*   He currently works for a renewable energy company called Vandebron.
*   He previously worked for the City of Amsterdam creating open-source projects.
*   He is an author of books on React, React Native, and his most recent book, "Full Stack GraphQL," which covers building servers and clients with React, Node.js, and TypeScript.

### **The Scenario: E-Commerce Platform of the Future**
Derks sets up a scenario where a developer joins a new project or company billed as building "the e-commerce platform of the future."
*   **The Stack:** The technology stack involves a UI built with JavaScript and React, connecting to a REST API, which connects to a Database backend.
*   **The Reality:** Despite the modern frontend, the backend setup (REST API + Database) represents legacy code or a "pretty ball of spaghetti." The goal is to connect the modern frontend to this legacy backend using GraphQL.

**The Problem with REST in this Context:**
1.  **Multiple Requests:** The UI makes three or more separate requests. Every small piece of the UI requires a separate REST API call, which is troublesome for mobile internet users.
2.  **Database Coupling:** The REST API is often directly correlated to the database tables. Every table has a separate API call.
3.  **Over-fetching:** The API returns large amounts of JSON, most of which the UI does not need but must still parse and normalize.

### **The Solution: A GraphQL Data Layer**
The objective is to stop making separate requests and use GraphQL without touching the legacy backend code (the "pasta" or "spaghetti") built by previous developers.

**Option 1: GraphQL Mesh**
Derks mentions using existing libraries like **GraphQL Mesh** (referencing Uri Goldshtein). This is a valid option if one wants to avoid writing custom code and simply contain another service.

**Option 2: Custom Data Access Layer (The focus of the talk)**
The talk focuses on creating a custom **Data Layer** (or Data Access Layer).
*   **Definition:** A layer providing simplified access to the data of a service. In this case, providing simplified access using GraphQL over the legacy code.
*   **Benefits:** It allows for caching, monitoring, and prevents mistakes that come from modifying legacy code that "nobody knows how it runs".
*   **The "Inception" Concept:** Derks acknowledges the philosophical question: "Is my API already a data layer?" Yes, but this approach involves building a data layer *on top* of an existing data layer.

### **Technical Implementation**

**1. From Document to Data ( The Request Flow)**
Derks explains how GraphQL retrieves data:
*   **Step 1:** The client sends a **GraphQL Document** (query).
*   **Step 2:** The server converts the document into an **Abstract Syntax Tree (AST)**. This tree represents the operations, top-level fields (e.g., products), and lower-level fields.
*   **Step 3:** The AST is matched against the **GraphQL Schema** on the server to understand relationships and connections.
*   **Step 4:** **Resolvers** retrieve the actual data based on the schema matching.
*   **Result:** The server outputs JSON matching the requested data structure.

**2. From Data to Server (The Build Flow)**
Constructing the layer works in reverse; the **Data** is the starting point.
*   **Methodologies:** Teams must choose between **Code-First/Resolver-First** (defining resolvers to create the schema) or **Schema-First** (defining the schema first).
*   **The Source of Truth:** The starting point must be the source of truth for the data. This could be:
    *   Swagger/OpenAPI definitions (for APIs).
    *   JSON Schemas.
    *   Migration documents or Mongoose models (for Databases).

**Strategies based on Source of Truth:**
*   **If no source of truth exists:** You should use **Schema-First**, making the schema the new source of truth.
*   **If a source exists:** You can use it to create resolvers via a **Code-First** approach.

**3. Choosing the Foundation: REST vs. Database**
When building the layer, you must decide whether to build on top of the REST API or directly on the Database.
*   **Use Database:** If the REST API is just a one-to-one mapping of the database without normalization.
*   **Use REST API:** If the REST API performs "saving side effects," normalizations, or calls other APIs.

### **Real-World Example: Salesforce Integration**
Derks shares a recent experience implementing this for Salesforce. Salesforce has REST APIs but lacks Swagger definitions; they use a vaguely described endpoint following a JSON API schema.
*   **Process:** Because there was no Swagger, they had to manually check endpoints and map them to **GraphQL Object Types** using `graphql-js`.
*   **Schema Definition:** He demonstrates defining a schema manually by mapping fields (e.g., `product`).
*   **Resolvers:** He shows code examples of resolvers:
    *   A `product` resolver calls a class/method to get a product by ID.
    *   Resolver arguments include `parent`, `args`, `context`, and `info`.
    *   The `info` object is highlighted as useful for exploring details about the AST.
    *   A `category` resolver uses the `parent` object to find the category associated with a product.

### **Conclusion and Summary**
Derks summarizes the decision-making process for teams:
*   **GraphQL Mesh:** Best if you have an existing source of truth and don't want to customize much.
*   **Custom Data Layer:** Best if you need to handle side effects, lack a clear source of truth, or need to create a schema manually from endpoint responses.
*   **Legacy Code Warning:** Building a custom layer risks creating *more* legacy code. It is vital to discuss whether to automate the process or build manually.
*   **Future Scaling:** Once the legacy code is wrapped in GraphQL, you can use **Schema Stitching** or **Federation** to connect it with other services.

Derks concludes by inviting questions via Twitter and directing viewers to his book for a free first chapter.