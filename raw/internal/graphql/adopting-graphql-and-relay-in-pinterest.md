Resource: https://youtu.be/9gY1vNw7Kcc

Based on the transcript of the video "Incrementally Adopting GraphQL and Relay at Pinterest," here is an accurate and comprehensive extraction of the presentation from start to end.

### **Introduction and Context**
Mauricio Montalvo, an engineer at Pinterest, introduces the challenge of adopting GraphQL in a large-scale web application.
*   **The Context:** The Pinterest app uses React.js, fetches data via a REST API, and uses Redux for state management.
*   **The Problem:** Like many REST/Redux apps, they faced "over-fetching." Debugging large pages made it unclear why certain extra information was present or if it was actually used.
*   **Initial Solution (Field Selection):** They tried passing parameters to the backend to specify which properties to return. While this worked for small components, it became unmanageable for large pages with 50-100 properties, making it difficult to determine if fields were actually necessary.
*   **The Pivot to GraphQL:** To solve over-fetching properly, they decided to move to GraphQL. The backend team created an API that returns the same models and entities as the REST API but in GraphQL.

### **Finding the Right Migration Strategy**
Montalvo outlines several approaches they considered and why they failed, leading to their final solution.

**Attempt 1: The "One Shot" Migration**
*   **Idea:** Migrate everything at once.
*   **Result:** Impossible. Pinterest has half a billion monthly active users and huge pages. A single PR would contain tons of code changes, be impossible to review, and likely be rejected.

**Attempt 2: Individual GraphQL Requests**
*   **Idea:** Change individual components to talk directly to GraphQL bit by bit.
*   **Result:**
    *   Increased network requests.
    *   Redundant fetching (fetching same data via REST and GraphQL).
    *   Multiple loading states (spinners) appearing in sub-branches of the tree, degrading user experience.
    *   Difficulty managing reusable components used across different surfaces.

**Attempt 3: Scalar Properties (Prop Drilling)**
*   **Idea:** Make components receive only scalar properties so they are agnostic to the data source (REST vs. GraphQL).
*   **Result:** "Prop drilling" hell. Passing data from the top to the bottom of a large tree is messy and breaks encapsulation.

**Attempt 4: Translation Layer**
*   **Idea:** Use a translation function to convert REST data into a common type that the component can use.
*   **Challenge:** REST data is often `snake_case`, while GraphQL is `camelCase`.
*   **Role of Relay:** Relay allows defining fragments for components. Relay generates a type containing exactly the information specified in the fragment.
*   **Implementation:** They created a hook containing a translation function. It takes the REST pin, converts properties (e.g., `publish_date` to `publishDate`), and outputs the Relay-generated type.
*   **Drawback:** Developers have to write repetitive translation code manually, which is bad for developer experience.

### **The Solution: The Relay Migration API**
To solve the repetition, Pinterest automated the translation process.

**The Concept**
*   **Automation:** Relay generates a `reader` object (a JSON representation of the fragment's selected data). By treating this as a graph, they can automate the translation function.
*   **The API:** A set of React hooks that behave like Relay functions but accept arbitrary data sources (REST). This allows backwards compatibility with REST while making components reusable and compliant with GraphQL types.

**Key Components of the API**

1.  **`useMigrationFragment` Hook:**
    *   Replaces Relay's `useFragment`.
    *   **Logic:** If the input is GraphQL data, it calls standard Relay. If the input is "Legacy" (REST) data, it calls the `AutoLegacyTranslator`.

2.  **`AutoLegacyTranslator`:**
    *   It traverses the Relay `reader` object to understand the desired output structure.
    *   It reads from the arbitrary data source (REST input).
    *   It handles naming conventions automatically (converting `snake_case` input to `camelCase` output) to return a GraphQL-shaped object.

### **The Migration Workflow**
Montalvo describes a bottom-up approach to migrating a surface (Root -> Middle -> Leaf).

1.  **Migrating the Leaf Component:**
    *   Implement `useMigrationFragment`. Pass the REST data into the "Legacy" data input. The component now renders using GraphQL-shaped objects.

2.  **Migrating the Middle Component (Handling Fragment Spreads):**
    *   Middle components often spread fragments for their children.
    *   The `AutoLegacyTranslator` identifies fragment spreads in the `reader` object.
    *   **The "Secret":** To ensure the leaf component gets the data it needs, the translator inserts a hidden symbol containing the *original* raw input data into the output object.
    *   When the child (Leaf) calls `useMigrationFragment`, it detects this secret symbol, extracts the original data, and runs its own translation.
    *   **Result:** Components become fully reusable across surfaces that are 100% GraphQL, 100% REST, or in transition.

3.  **Migrating the Root Component:**
    *   **`useMigrationQuery` Hook:** Wraps Relay's `useLazyLoadQuery`.
    *   It accepts a boolean flag (e.g., `useGraphQL`).
    *   If true: Fetches via Relay.
    *   If false: Uses existing REST fetching logic.
    *   It also handles the root-level shape differences (e.g., REST returns a raw object, GraphQL wraps it in a `data` object).

### **Rollout and Cleanup**
*   **A/B Testing:** Because the API allows switching data sources via a boolean flag, teams can run experiments exposing the GraphQL variant to a percentage of traffic to monitor metrics/performance.
*   **Cleanup:** Once a surface is 100% migrated to GraphQL, the migration code (Legacy inputs) is technically dead code. Pinterest created a static analysis script to identify which components no longer need the migration API and can be converted to standard Relay.

### **Advanced Features and Status**
*   **Capabilities:** The API supports arrays, inline fragments, pagination/refetching, and stable references (caching results for use in dependency arrays).
*   **Adoption:** Used by a couple of hundred components and a dozen features at Pinterest.
*   **Relay Resolvers:** Montalvo acknowledges Relay Resolvers as a similar emerging solution but notes Pinterest needed a custom solution before Resolvers were fully ready. He is optimistic about Resolvers for the community.
*   **Next Steps:** Pinterest plans to open-source this project.

### **Q&A Session**
*   **Backend Dependency:** Montalvo confirms this approach relies on the backend having a GraphQL API that mirrors the information available in the REST API.
*   **Mixed Data Sources:** The API allows deciding at the root level which data source to use, which is helpful if a specific surface needs one source over the other.
*   **State Management (Writes):** The talk focused on reading data. For writes/mutations, they have tools to keep the Relay store and Redux store in sync based on the user session, though currently, mutations largely remain in Redux/REST.