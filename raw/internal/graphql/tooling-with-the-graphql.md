Resource: https://youtu.be/0pjL597IdRU?list=TLGG1_LWm_KRYVwxNTAyMjAyNg

Based on the transcript of the video "Tooling and Processes for Managing GraphQL at Scale" by Mark Larah at GraphQL Galaxy 2021, here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Context**
Mark Larah, a lead on the Client Data API team at Yelp, introduces the talk's focus: the tooling and processes built to make life easier for GraphQL developers at Yelp. His team maintains the GraphQL infrastructure used to build Yelp's web and mobile applications.

**The Scale of GraphQL at Yelp:**
Mark emphasizes the scale to explain why they invest heavily in tooling. GraphQL is the standard for data fetching at Yelp, utilized by hundreds of developers. The ecosystem includes:
*   Over 500 types in the schema.
*   500 active "persisted queries" (queries used in production within the last two weeks).
*   Approximately 10,000 queries per second (QPS).

### **Phase 1: Designing the Query (The "Dream Query")**
The presentation follows the journey of a developer creating a Pull Request (PR) to add a new feature.
*   **Avoiding Bad Schema:** To avoid committing bad schema choices that are costly to remove later, Yelp encourages developers to keep things flexible initially.
*   **The Dream Query:** Developers are encouraged to write a "Dream Query"—the query they wish they could write if the schema were magically available—before defining the actual schema. This helps those new to the company or GraphQL communicate their needs without being intimidated.
*   **Schema Reviewers:** A specific group of reviewers helps point out existing types and guides the design process based on the Dream Query.

### **Phase 2: Prototyping with `graphql-faker`**
Once the query is drafted, developers move to hammering out the schema.
*   **Parallel Development:** To allow backend and frontend work to proceed in parallel, Yelp uses an open-source tool called `graphql-faker`. This tool spins up an IDE (similar to GraphiQL) where developers can add temporary schema and types on the fly.
*   **Mocking Data:** The tool allows querying these new types to get auto-generated `lorem ipsum` data.
*   **Integration:** Yelp has configured this tool to be globally available on developer machines via a single command. It spins up a faker instance pre-configured to talk to real developer instances, allowing developers to mix real schema with work-in-progress schema. This can even be plugged into React apps to test UI components before the backend is finished.

### **Phase 3: Implementation and Architecture**
Once the schema design is finalized, the developer moves to implementation.
*   **Architecture:** Yelp’s architecture consists of various services exposing internal REST APIs. A GraphQL Gateway service (monolithic, Node.js, Apollo Server) talks to these services via resolvers.
*   **The N+1 Problem:** To avoid unnecessary network requests, they use **Data Loaders** (a pattern for batching and caching).

**Scaling Data Loaders (`dataloader-codegen`):**
*   **The Problem:** Writing data loaders by hand for hundreds of internal endpoints is unmaintainable. It leads to inconsistencies in error handling, logging, and typing, as well as confusion over which loader to use for which endpoint,.
*   **The Solution:** Yelp created and open-sourced `dataloader-codegen`. Because Yelp uses Swagger UI to document internal endpoints, they use these specs as the source of truth.
*   **How it Works:** A configuration file generates data loaders for every specified endpoint. This creates a strict one-to-one mapping, meaning developers think in terms of endpoints rather than loaders. This ensures consistent error handling and logging across the board,.

**Resolver Typing:**
*   They use `graphql-code-generator` (from The Guild) to generate types from the schema file to type-check their JavaScript implementation.

### **Phase 4: Validation and Pre-Commit**
Before the code is pushed, Yelp uses **Pre-commit** hooks as an early warning system.
*   **Linting:** They run `graphql-schema-linter` in the terminal immediately after a developer types `git commit`. This checks against naming conventions and style rules without waiting for CI to fail 20 minutes later.

### **Phase 5: The Pull Request and CI Bots**
Once the PR is sent, GitHub bots perform deeper checks:
1.  **Breaking Changes (`schema-check-bot`):**
    *   This uses `graphql-inspector` to detect breaking changes (e.g., removing or renaming a field).
    *   **Usage-Based Validation:** The bot is integrated with production usage logs. If a developer tries to remove a field, the bot checks if that field was used in the last two weeks.
        *   If used: The PR is blocked with a warning listing the affected queries.
        *   If *not* used: The bot allows the breaking change, knowing it won't impact production,.

2.  **Suggestions (`schema-suggestions-bot`):**
    *   This bot looks for issues that are hard to strictly lint, such as naming collisions (e.g., adding `BusinessHours` when `BusinessOpeningHours` already exists).
    *   It uses regex rules to provide inline comments on the PR, which the developer can choose to address or ignore as a false positive,.

### **Phase 6: Human Review and Documentation**
*   **Schema Review Group:** The final step is approval from a human in the Schema Review Group. To join this group, developers must complete a learning module. This ensures consistency and avoids team-specific biases in schema design.
*   **Documentation as a Product:** Mark highlights that for the first year, time was split 50/50 between coding and writing internal documentation.
*   **Opinionated Docs:** Unlike open-source documentation which must remain unopinionated, internal documentation should be highly opinionated ("Just do this"). This saves developers from having to think from first principles for every task,.

**Conclusion:**
Mark concludes by noting that Yelp has open-sourced their schema design guidelines and mentions that they are hiring.