Resource: https://youtu.be/SxX2Lja29Ao

Based on the transcript of the video "GraphQL, tRPC, and your tech tool box" by Charles Kornoelje, here is an accurate, comprehensive extraction of the presentation from start to end.

### **Introduction and Context**
Charles Kornoelje, a software developer at Tekton (an e-commerce company selling wrenches, sockets, and screwdrivers), introduces the session. He explains the title "Choosing the right tool" by referencing his work at Tekton, where the goal is to create a world-class shopping experience by selecting the appropriate technology from a "tech toolbox." While the event is a GraphQL conference, the talk focuses on **tRPC** (TypeScript Remote Procedure Call) as a tool for creating type-safe APIs, how to use it, and how it compares to GraphQL.

Charles notes that he leads site performance at Tekton. He clarifies immediately that GraphQL is a fantastic specification, but tRPC is a different tool solving a similar use case.

### **The Communication Problem**
The talk targets developers interested in the latest tools to improve end-user experiences. The core issue addressed is the **"Communication Problem"**—the challenge of developers needing to send and receive data between a client and a server.

**The Scenario:**
*   You are on a small team (3-4 developers).
*   You are likely full-stack developers.
*   You are building a web application using a meta-framework like Next.js, SvelteKit, or Nuxt.
*   Consequently, you have a **tightly coupled server and client relationship** within the repository.

**The Goals:**
To solve this communication problem, the team has specific goals:
1.  **Rapid Iteration:** Developers must be able to create features and fix bugs quickly.
2.  **High Confidence:** Changes should not break the user experience.
3.  **Type Safety:** Leveraging TypeScript to ensure confidence when making changes.

**Existing Solutions:**
Charles lists common ways to solve this:
*   **Rolling your own REST API:** Offloads responsibility to the team but is time-consuming to set up schemas and layers.
*   **OpenAPI:** Used for type-safe APIs.
*   **GraphQL:** Acknowledged as fantastic and used in production by the speaker.
*   **tRPC:** The focus of this talk.

### **What is tRPC?**
Charles defines tRPC using a quote from its documentation: "tRPC allows you to easily build and consume fully typesafe APIs without schemas or code generation."

**Key Characteristics:**
*   **TypeScript Remote Procedure Call:** unlike historical RPCs over TCP/UDP, this works over HTTP.
*   **Concept:** It treats backend endpoints as functions (procedures) that return data. You call these functions from the client.
*   **Sharing Types:** It allows seamless type sharing between frontend and backend without bloating client code with unnecessary JavaScript.
*   **Type Inference:** It leans heavily on TypeScript inference (explained in the demo).
*   **Autocompletion:** Provides editor support for calling backend procedures.
*   **Direct References:** The frontend has a direct reference to backend code, making debugging and refactoring (e.g., "Rename Symbol") safe and easy across the full stack.
*   **Incremental Adoption:** Since they are just function calls, they can be added one by one to a "Brownfield" application.

### **Code Demonstration**
Charles switches to a live code demo (using a StackBlitz example) to illustrate the developer experience.

**1. Basic Query Structure**
*   **Client Side:** The code calls `trpc.greeting.useQuery({ name: 'client' })`. It checks if data exists and renders it. Changing the input string to "GraphQL Conf" updates the output instantly.
*   **Server Side:** Defined by an **App Router** (API Handler) and a **Greeting Procedure** (API Endpoint).
*   **Procedure:** Takes validated input and runs a query (resolver) to return data.

**2. Type Safety and Refactoring**
*   **Navigation:** Charles demonstrates "Command-Clicking" on the `greeting` function in the client code, which jumps directly to the backend definition.
*   **Renaming:** He uses the "Rename Symbol" feature to change `greeting` to `message`. This updates the backend definition and all frontend usages simultaneously without breaking the app.
*   **Breaking Changes:** He changes the input validation on the server from expecting `name` to expecting `text`. TypeScript immediately flags an error on the client because the client is still sending `name`. He updates the client to send `text`, resolving the error.

**3. Type Inference (Output)**
*   Charles adds new fields (`second: 'test'`, `third: 123`) to the return object on the server.
*   Without updating any manual schema, hovering over the `data` object on the client immediately shows the new shape (`text`, `second`, `third`).
*   **No Compilation Step:** Unlike GraphQL or OpenAPI, there is no "save and compile" or "schema generation" step. Changes cascade instantly via the TypeScript compiler.

**4. Creating a New Query (`getUser`)**
*   He adds a `getUser` procedure to the router returning an ID and name.
*   On the client, he types `trpc.` and uses autocompletion to see `getUser` is now available.
*   Renaming `name` to `username` on the server immediately updates the client's type expectations.

**5. Creating a Mutation (`updateUser`)**
*   He defines a mutation using `t.procedure.input(...)`.
*   **Validation:** He uses **Zod** for input validation (though Yup, Joi, or custom validators also work). The input expects a `name` string.
*   **Context:** He accesses the input via the mutation callback parameters. Hovering over `input` confirms it is an object with a string `name` (Type Narrowing).
*   **Implementation:** He simulates updating a user object. He notes that in a real app, this would be a database call.
*   **Client Usage:** He uses `trpc.updateUser.useMutation()`. He creates a handle function to trigger the mutation.
*   **Cache Invalidation:** He briefly shows importing `useContext` to invalidate the client-side cache after the mutation to refresh the data.

### **Technical Breakdown (How it Works)**
Charles clarifies the specific vernacular and mechanics:
*   **Router:** The API Handler.
*   **Procedures:** Endpoints (Queries or Mutations).
*   **Validation:** Critical for TypeScript type guards to infer input/output types correctly.
*   **The "Magic" (Type Sharing):**
    *   The server exports a type `AppRouter`.
    *   The client imports this **Type**.
    *   **Crucial Distinction:** This is *only* a TypeScript type. No JavaScript server code is bundled or sent to the client. In production, there is no shared code, but during development (IDE), the link exists for inference. The client has no idea what is actually on the server at runtime, but the compiler ensures safety during build time.

### **Comparison: GraphQL vs. tRPC**
Charles emphasizes using the right tool for the job (Hammer vs. Wrench).

**GraphQL Use Cases:**
*   Best for large, separated frontend and backend teams.
*   Acts as a contract/common language between engineering teams.
*   Language agnostic (great if backend/frontend are different languages).
*   Large ecosystem and corporate backing de-risk the technology choice.

**tRPC Use Cases:**
*   Easy to version (implicit versioning).
*   Lower ramp-up time (just function calls).
*   Fewer dependencies (only need tRPC, no code-gen tools).
*   Faster feedback loop (changes reflected instantly in editor).
*   **Shared Traits:** Both use HTTP/Websockets and both prevent over-fetching of data.

### **Project Status and Community**
*   **tRPC v10:** Currently in Alpha (at the time of the video). It addresses a performance limitation where the TypeScript compiler would slow down after ~100 procedures. v10 includes performance optimizations.
*   **Creators:** Created by Alex, built on a proof-of-concept by Colin (who was inspired by Blitz RPC).
*   **Adoption:** ~60,000 downloads/week on NPM (small compared to GraphQL's 8 million).
*   **Growth:** Gaining popularity rapidly with 12,000 stars and 50 financial sponsors.

### **Conclusion**
Charles concludes by reiterating that tRPC is a tool to leverage TypeScript for a better developer experience (DX), which leads to a better end-user experience. He hopes tools like tRPC encourage the GraphQL ecosystem to make their type-safety stories more seamless and easier to set up.