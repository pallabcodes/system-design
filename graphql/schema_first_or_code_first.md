Resource: https://youtu.be/kpeVT7J6Bsw

Based on the transcript provided, here is an accurate and comprehensive extraction of the presentation "Schema First, Code First, or Both? Adopting Schema First Development" by Dan Adajian from Expedia Group, from start to end.

### **Introduction and Context**
Dan Adajian, a developer at Expedia Group, introduces the topic as a discussion on combining "Schema First" and "Code First" approaches to GraphQL implementation, rather than debating which is better. He has been with Expedia and working with GraphQL for four years, focusing on lodging shopping (hotels and vacation rentals).

**Expedia Group Context:**
*   Expedia Group powers multiple brands, with the "big three" being Expedia, Vrbo, and Hotels.com.
*   They operate a Federated Supergraph consisting of over 70 GraphQL services and 1,000+ contributors.
*   Scale is a major consideration, making the schema change process critical.

### **Defining the Approaches**
**Schema First:**
*   This involves designing first and implementing later. Specifically, the Schema Definition Language (SDL) is written and maintained separately from the resolver code.
*   **Advantages:** It encourages thinking before doing. It is inclusive, allowing everyone (not just backend engineers) to review the schema because SDL is a universal language. It is easier to enforce best practices and design standards.
*   **Disadvantages:** It is subject to divergence from the implementation (the code might not match the schema). It has higher complexity because you must manage two sources of truth (SDL and code).

**Code First:**
*   The implementation *is* the design. Developers write resolver code, use tooling to generate the SDL, and then publish it.
*   **Advantages:** The schema is always in sync with the implementation. It has lower complexity as developers only maintain the code.
*   **Disadvantages:** You need to know the backend language to design the schema. It is harder to ensure good upfront design when working directly in a backend language.

**The Goal:**
Expedia wanted to "have their cake and eat it too" by combining the inclusivity and design enforcement of Schema First with the synchronization and simplicity of Code First.

### **Milestone 1: Inclusivity in Schema Design**
Schema design is difficult, particularly when supporting native apps where breaking changes are impossible due to old app versions. Upfront design involves backend engineers, frontend engineers (Web, iOS, Android), designers, and product managers.

**The Evolution of Reviews:**
*   Expedia uses `graphql-kotlin`, an open-source library they created that generates SDL from manually defined Kotlin code.
*   Initially, they conducted schema reviews using Markdown files or screenshots of GraphQL Playground. This was better than nothing but relied on templates rather than actual SDL.
*   They moved to reviewing actual SDL to better utilize the universal language, even while using a code-first library. "The customer is always right," meaning consumer developers are best positioned to dictate good schema design.

### **Milestone 2: Tooling and Enforcement**
To improve the process, they implemented a GraphQL Monorepo containing SDL files.
*   **Tooling:** They utilized tools from The Guild, such as GraphQL Inspector (to catch breaking changes) and GraphQL ESLint (for linting).
*   **Linting Example:** Dan provides an example regarding nullability. If a schema defines a list of nullable strings (`[String]`), client developers (e.g., in React) must manually filter out nulls. A lint rule was created to enforce non-nullable elements in lists, simplifying client code significantly.

**The Problem with this Hybrid Approach:**
Despite the reviews, the review artifacts were just documentation. Developers still had to manually copy/paste schema into Kotlin code to implement it.
*   This led to divergence (implementing something different than what was reviewed).
*   It caused human errors, such as typos or incorrect nullability settings, which were often caught too late.
*   Conclusion: Schema reviews were just "niceties," while `graphql-kotlin` remained the source of truth.

### **Milestone 3: Syncing Schema and Implementation**
To ensure the schema and implementation remained in sync, Expedia developed and open-sourced a plugin for GraphQL Code Generator called `graphql-kotlin-codegen`.

**The New Workflow:**
1.  **Before:** Manually translate reviewed SDL to Kotlin -> Review the Kotlin -> `graphql-kotlin` publishes schema.
2.  **After:** Auto-generate Kotlin from the reviewed SDL -> Publish Kotlin to internal libraries -> Upgrade library version in the graph service -> `graphql-kotlin` publishes schema.

**Features of `graphql-kotlin-codegen`:**
*   **Descriptions & Deprecations:** Generates code including descriptions and `@Deprecated` annotations.
*   **Input/Output Enforcement:** Generates annotations to ensure input types are not used as output types, and vice versa.
*   **Enums:** Generates Enum classes and includes a helper function `findByName` to easily lookup values.
*   **Unions:** Since Kotlin lacks native union types, the tool generates a "Marker Interface" (an empty interface) that data classes implement to represent the union.
*   **Directives:** Uses a "Directive Replacements" configuration to replace SDL directives with corresponding Kotlin annotations.

### **Solving Technical Challenges**
The team encountered specific problems with the code generation that required further refinement:

**Problem 1: Resolver Function Divergence**
While data classes were generated, the top-level resolver functions (written manually in the service) could still diverge from the schema (e.g., wrong name, input, or output).
*   **Solution:** The tool generates an interface (open class) with functions that throw a "Not Implemented" error. The source code must inherit from this interface and override the functions. This forces the compiler to ensure the manual implementation matches the schema contract.

**Problem 2: Over-fetching**
If a resolver returns a generated data class, it constructs the entire class. If fields `foo` and `bar` both require expensive calls (e.g., database lookups), the server performs both calls even if the client only requested `foo`.
*   **Solution:** They introduced a "Resolver Interfaces" configuration. For specified types, the tool generates an interface instead of a data class. This forces the developer to implement each field as an independent function. Consequently, only the function for the requested field is executed, preventing over-fetching.

### **Results and Conclusion**
By adopting this workflow, Expedia achieved:
*   **Code Deletion:** Deleted 3,000 lines of redundant code and removed dependencies on 20,000 lines of shared code.
*   **Speed:** Decreased the time to merge schema change PRs by an average of two days.
*   **Reduced Complexity:** Less code to write and review eliminated synchronization errors between design and implementation.

**Summary:**
The approach allows for inclusivity (anyone can design via SDL), synchronization (schema generates the code), and lower complexity. Dan concludes that teams do not need to choose between Schema First and Code First but can use tooling to leverage the benefits of both.

### **Q&A Session**
**Q: What happens if a team changes their mind about a schema field after generation (e.g., they don't want to implement it anymore)?**
**A:** This is similar to a true code-first approach. If the schema is published but not yet used by clients, it is safe to make a breaking change to remove it. If it is already in use, it is too late.

**Q: Where does the manual implementation happen?**
**A:** The generation solves the complexity of types, but developers must still manually implement the logic for fields, especially those with arguments or expensive calls. This is a design decision made during implementation.

**Q: Is the central schema repo used to generate clients, and does having unimplemented fields cause a delay?**
**A:** Yes, clients generate types from the schema. However, they must wait for the backend engineer to finish the implementation before they can consume the API. To mitigate this, Expedia deploys a test graph server with mock data so clients can start working with generated types before the real implementation is complete.

**Q: Why not generate SDL from the Kotlin code via introspection instead of writing it by hand?**
**A:** Generating SDL from Kotlin (Code First) creates the schema only at deploy/publish time. They wanted to write SDL first to utilize tooling like breaking change checks and linting *before* the code is written or published. The current setup requires the manual SDL step to leverage that ecosystem.