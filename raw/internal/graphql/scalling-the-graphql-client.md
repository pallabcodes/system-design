Resource: https://youtu.be/Vo8nqjiKI3A?list=TLGGEMzv95D_UwswODAyMjAyNg

Based on the transcript of the video "Scaling Your GraphQL Client" by Matt Mahoney at GraphQL Conf 2019, here is an accurate and comprehensive extraction of the presentation from start to end.

### **The Hypothetical Scaling Scenario**
The presentation begins with a task: building a fancy profile UI for a brand-new app.
*   **Stage 1 (One Person):** You need a JSON response containing a picture and information. One person builds everything, intimately knowing the server code (PHP/Ruby), the client code, and the description fields.
*   **Stage 2 (Team Growth):** As the app succeeds, the team grows. You become the Tech Lead. You assign someone else to handle image fetching, caching, and consistent rendering so you don't have to worry about it.
*   **Stage 3 (New Features):** The app scales to include new verticals, like "Groups." A group is similar to a profile but has "info" instead of "about" and might be a nested tree (e.g., a group about Geese). These sections need to share infrastructure and components with the profile section.
*   **Stage 4 (Multiple Apps):** Success leads to building more apps. This introduces design conflicts; one app's designer wants square images, while another wants round images. The engineering challenge is reusing the same data pieces while handling slightly different requirements per app.

### **Introduction and Agenda**
Matt Mahoney, a software engineer at Facebook, introduces himself and the topic: models. The talk covers how to model data to scale with an organization, specifically:
1.  **JSON Models:** Basic JSON handling.
2.  **Type Models:** Representing models from the schema.
3.  **Response Models:** Accessing the tree of data returned from the server.
4.  **Fragment Models:** Encapsulating data for specific components.
This reflects the history of how Facebook has worked with its native clients.

### **1. JSON Models**
The GraphQL spec dictates that servers return JSON.
*   **Implementation:** You ignore the schema structure and use getters/keys via a third-party JSON parsing library to access data.
*   **Pros:** It is easy to iterate for a single developer.
*   **Cons:**
    *   **Typos:** It is easy to mistype keys (e.g., writing `URI` instead of `URL`), which is hard to spot.
    *   **No Type Safety:** You might expect a string but get an integer, leading to coercion issues or crashes.
    *   **Under-fetching:** You might try to use data (like "about" info) that you forgot to ask for, resulting in null values.
    *   **Over-fetching:** You might ask for data you don't use, wasting server execution time and user data.
*   **Verdict:** Not recommended for large scale. At Facebook, JSON models are used mostly for tooling or tests where automation catches bugs, rather than in production code.

### **2. Type Models**
To solve JSON issues, you can generate getters and classes based on the schema.
*   **Schema-Based Generation:** You generate Java/Objective-C classes based on the Server Schema Definition Language (SDL). There is a one-to-one mapping between schema fields and class getters.
*   **The Scaling Problem:**
    *   **Aliasing:** If a query aliases `picture` to `lil_pic`, a schema-based model cannot represent that or differentiate it from `big_pic`.
    *   **Size:** Facebook has 30,000 types and 200,000 fields. Shipping 30,000 additional classes with an Android app would be ridiculous and wasteful.
*   **Query-Based Generation:** Instead of the whole schema, models are generated based on what is actually asked for in the app's queries. You pass these models (e.g., `User` model, `Image` model) around the app. An interface like `HasPicModel` allows passing data to renderers.
*   **Remaining Issues:**
    *   **Nullability:** The spec might say a field is non-nullable, but it could still be null in the response. Type models cannot differentiate these states, leading to null pointer exceptions if you access a field (like an image URL) that wasn't actually requested.
    *   **Under-fetching:** You can still access fields in the model that you didn't query, causing crashes.
    *   **Over-fetching:** If you delete a field (e.g., `big_picture`) from a query, you don't know who else in the app might be relying on it. This requires hunting through the entire codebase to prevent build breaks.
*   **Verdict:** Type models do not scale well to many teams because of the difficulty in managing downstream effects of changes. Facebook uses them but they require extensive manual testing.

### **3. Response Models**
The core idea is that GraphQL responses form a tree, and we want to ensure access to pieces of that tree.
*   **Implementation:** Create one class or interface per fragment. Use **Interface Inheritance** to represent fragment spreads.
    *   *Example:* `UserProfile` extends `SquarePic` and `LittlePic`. `SquarePic` extends `CoreImage`.
*   **Pros:**
    *   **Solves Under-fetching:** If you don't spread the fragment, the data isn't there. It becomes a compile-time error to access missing data.
*   **Cons:**
    *   **Over-fetching:** Still possible if someone asks for data they don't use.
    *   **Lack of Encapsulation (The "Core Image" Problem):** Because of inheritance, a parent component has access to all child fields. If the "Core Image" team removes a `URL` field (deciding to use a "smart URL" instead), it breaks every other team that was implicitly using that `URL` field via inheritance. This causes massive build failures and slows down infrastructure teams.
    *   **Multiple Apps:** It is difficult to handle different designs (Square vs. Round) without over-fetching or pulling in unnecessary data from other apps.
*   **Verdict:** Used heavily in Facebook native clients, but they are trying to move away from them due to the encapsulation issues.

### **4. Fragment Models**
Fragment models are similar to response models but enforce **Black Box** encapsulation.
*   **Implementation:** Instead of interface inheritance, you must perform an explicit conversion (e.g., `.as(AppPic)`) to pass a fragment to a function. The converted fragment can be null if the data wasn't requested.
*   **Pros:**
    *   **Correctness:** Allows checking if a specific concrete type exists in a union.
    *   **Solves Under-fetching:** Statically prevents it.
    *   **Reduces Over-fetching:** Because of strict encapsulation, if you see an unused field in a fragment, you can safely delete it knowing it won't break other parts of the app (as they can't access it). This is safe code deletion.
    *   **Build Times:** Reduces build times. Modifying a fragment only requires rebuilding that specific library, not the whole app.
    *   **Scalability:** Scales well to multiple apps with different designs by injecting app-specific fragments based on context.
*   **Verdict:** While they add overhead and complexity compared to raw JSON, they are the most scalable solution. **Relay** was built with fragment models from the ground up. Facebook is currently migrating their native code (Objective-C and Java) from Type/Response models to Fragment models.