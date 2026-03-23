Resource: https://youtu.be/mpW5pKGb9JA

Based on the video transcript provided, here is an accurate extraction of the presentation "Orchestrating Microservices with GraphQL" by Greg Kesler from start to end:

**Introduction and Background**
Greg Kesler introduces himself as a Principal Engineer at the Intuit Developer Group. He has been working on the new generation of the Intuit platform API and SDK, serving as a product owner and technical lead. He previously authored "Siebel 2," a language used for creating data services, and is a contributor to the open-source GraphQL Java library.

Intuit is an early adopter of GraphQL, having used it for three years since the spec was opened by Facebook in 2015. The talk focuses on orchestrating requests—using GraphQL as an emerging protocol example, though the problems discussed apply to any chosen protocol.

**The Orchestration Problem**
Kesler describes an API gateway connected to a set of microservices in the financial domain: Company Data, Contact Data, Invoices, Accounting Engine, and Itemization. The API gateway’s role is to unify the API, optimize traffic (minimizing requests over slow networks), and provide location transparency so clients do not need to know where data originates.

**Anatomy of a GraphQL Request**
Kesler presents a specific GraphQL request scenario: A client asks for a Company (ID 12345), the invoices belonging to that company, and the customer associated with those invoices.
*   **Without GraphQL:** This would require a series of REST calls: fetch invoice for the company, then fetch the customer for that invoice, then join them.
*   **With GraphQL:** The gateway decomposes the request, organizes calls to downstream microservices, joins the data, and sends back an object containing the invoice and the associated customer.

**Standard Execution Flow**
The GraphQL engine builds an Abstract Syntax Tree (AST) from the request. This tree contains scalar fields (atomic data) and object nodes. In this example, three field nodes are critical because they represent objects stored in different systems: Company, Invoices, and Contact. These are "relational objects":
*   The Company field fetches data from the Company service.
*   The Invoices field implies fetching invoices using the Company ID.
*   The Contact field implies fetching contacts using the Contact ID found within the fetched invoice.

In standard implementations (like the Facebook reference or GraphQL Java), a "resolver" or "data fetcher" is associated with every field. The engine calls the resolver, the resolver queries its specific service, and the data is returned to the engine to be joined.

**The Limitation: Complex Filtering**
The standard approach fails when the query becomes more complex. Kesler modifies the example query to fetch invoices not just by company, but filtered by a criteria specific to the *associated contact* (e.g., fetching an invoice based on a contact attribute).
*   While GraphQL specs do not strictly define filtering syntax, Intuit (similar to Prisma) allows specifying expressions as arguments to represent domain criteria.
*   **The Issue:** If following the standard execution path, the query for invoices goes to the Invoice Resolver. This resolver has two bad options:
    1.  Try to query invoices by a customer attribute (which the Invoice Service doesn't rely on or access).
    2.  Try to orchestrate the query itself (e.g., fetch contact first), which defeats the purpose of the GraphQL engine normalizing data fetchers.

**The Solution: Dependency Graphs**
Kesler proposes viewing microservices as tables. The Invoice service contains references to Company and Contact. To solve the filtering problem, one can calculate Cartesian products: fetch companies by ID, fetch contacts by the specific attribute, and then find the intersection to determine which invoices to fetch.

To implement this, Intuit utilizes a **Dependency Graph**.
*   **Query Execution:** For the complex query, they build a graph where the Invoice node depends on both the Company and the Contact nodes. By calculating the transitive dependency closure or walking the graph in natural order, they can identify which queries to run.
*   **Parallelism:** They can fetch Company (by ID) and Contact (by criteria) in parallel. Once resolved, they use those results to fetch the Invoice. The final "join" happens in the result node.
*   **Mutations:** The same logic applies to mutations. If creating an invoice requires a customer, the Invoice node depends on the Customer node. The system traverses the graph, creates the customer first, and then the invoice.

**Implementation and Conclusion**
Intuit deploys a combined service that bypasses the standard GraphQL engine's orchestration. They use the GraphQL frontend only to parse requests and map input types. The actual orchestration relies on their custom dependency graph. This approach allows them to orchestrate not just GraphQL, but also REST or JSON-RPC requests similarly.

**Q&A**
When asked if they used an existing library, Kesler confirms they implemented the dependency graph mechanism themselves. It builds graphs for specific keys and derives metadata from object schemas to determine relationships (e.g., composition/parent-child).

Q: How do dependecny graph compares to standard Graphql servers?

Q: How does the gateway handles complex filtering across microservices?

Q: How can dependency graphs optimize cascade mutations?