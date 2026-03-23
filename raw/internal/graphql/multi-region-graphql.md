Resource: https://youtu.be/dedmrILQpeA

Based on the provided transcript, here is an accurate and comprehensive extraction of the presentation "Going From Zero to Building Multi-Region GraphQL Applications" by Nikhil Chandrappa.

### **Introduction and Motivation**
Nikhil Chandrappa introduces himself as a software engineer at YugabyteDB, a distributed SQL company. He works on the drivers and ecosystem team, building integrations with popular developer tools. He notes that the company has seen significant interest from their community and users to build first-class support for GraphQL.

He explains that GraphQL is gaining rapid adoption because it gives UX developers autonomy over querying data, allowing them to retrieve only what they need. As a database company working daily with backend and API developers, YugabyteDB felt it was important to understand the server-side concepts of GraphQL architecture. Specifically, they wanted to understand how the GraphQL server abstracts the database for querying and mutating data, as well as advanced features like pagination, filtering, and eventing.

### **The Evaluation Process and Use Case**
The team wanted to compare GraphQL against general REST API development, where a developer understands the business domain, creates domain objects, and implements access patterns. To evaluate how a GraphQL server looks in this context, they chose a real-world **E-commerce** use case.

They selected E-commerce because:
1.  It is a well-known domain.
2.  It presents challenges for UX developers (building immersive experiences).
3.  It presents challenges for API developers (handling random traffic, scaling based on user traffic, and ensuring high availability).

In a standard microservices architecture for E-commerce, multiple services expose REST APIs consumed by UI applications. The team wanted to evaluate how well a GraphQL server could utilize native database capabilities, perform efficiently, and how easy it would be to get to production.

### **Implementation Iterations**

**Iteration 1: Simple Data (Product Catalog)**
They started with a simple table, the "Product Catalog," which did not have complex access patterns (inputting a product ID to get product details).
*   **Result:** This was a "quick win." Unlike previous methods where complex JSON objects were sent in the response, GraphQL allowed client applications to retrieve only the specific data they needed.

**Iteration 2: Complex Data (Product Ranking)**
Once comfortable, they introduced a more complex dataset: "Product Ranking." This required filtering data based on categories and sorting based on ranking. Some of this processing happened in the database, while some filtering occurred at the API layer.
*   **Observation:** Performing CRUD (Create, Read, Update, Delete) operations against these tables was fast and easy, leading to faster prototyping and reducing the back-and-forth communication required between UX and API developers.
*   **The Pivot:** However, as they added more tables, they realized that manually building all the domain mappings and resolvers was a complex task. Consequently, they pivoted to using popular open-source GraphQL server implementations instead of building everything from scratch.

**Iteration 3: Subscriptions (Order Management)**
In their research of open-source tools, they found first-class support for event-based systems using GraphQL subscriptions. They applied this to an "Order Management System" to track user orders and statuses.
*   **Result:** This solved the issue of polling for data; the system simply received notifications whenever there was a new status update.
*   **Benchmarking:** To determine if this setup could handle the scale and SLA requirements of their existing APIs, they benchmarked the GraphQL subscriptions. They were able to scale to meet their requirements successfully.

### **Resiliency and Cloud Native Deployment**
The final step addressed the requirements of cloud-native applications: resilience and the ability to withstand outages.
*   **The Test:** They took the GraphQL servers and deployed them with a **stretched YugabyteDB cluster**.
*   **Resiliency Testing:** They performed tests by taking out an entire region or specific machines within a region to simulate outages.
*   **Result:** The application remained resilient, providing the team with the confidence to take the solution to production.

### **Conclusion**
Chandrappa concludes that GraphQL simplifies the feedback loop between API developers and UX developers. Furthermore, he states that GraphQL becomes very powerful when it is able to utilize the capabilities of modern cloud-native applications.

Q: How do GraphQL subscriptions handle scale compared to REST polling?

Q: What are the benefits of using a stretched YugabyteDB cluster?

Q: Why did the team pivot to open source graphql implementations?