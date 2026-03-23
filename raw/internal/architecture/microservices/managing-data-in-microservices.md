Resrouce: https://youtu.be/E8-e-3fRHBw


Based on the transcript provided, here is an accurate, comprehensive extraction of the presentation "Managing Data in Microservices" by Randy Shoup, covering the talk from start to end without skipping details.

### Introduction and Background
Randy Shoup, VP of Engineering at Stitch Fix, introduces himself and his background, which includes roles as a "roving CTO," Director of Engineering for Google App Engine, and Chief Engineer at eBay for 6.5 years.

**Stitch Fix Context**
Shoup explains the Stitch Fix business model to motivate the need for data-driven microservices. Stitch Fix is a clothing retailer that combines art and science. Instead of customers choosing clothes, they fill out a detailed style profile (100 questions), and the company sends five hand-picked items. Customers keep what they like and return the rest.

Unique to their industry, Stitch Fix maintains a nearly 1:1 ratio between software engineers (~100) and data scientists/algorithm developers (~80, many with PhDs in astrophysics or biochemistry). This intelligence is applied across the supply chain:
*   **Buying:** Quantities and timing.
*   **Inventory Management:** Logistics and storage optimization.
*   **Demand Prediction:** crucial because overestimating demand means waste, while underestimating means failing to serve customers.

**The Styling Process (Humans + Machines)**
Shoup details the "Styling" workflow:
1.  **Machines:** Algorithms churn through data to score inventory and generate a probability that a client will buy a specific item.
2.  **Humans:** 3,500 stylists view these algorithmic recommendations and curate the final five items, applying context that machines miss (e.g., a request for a "sexy date night" outfit).
The philosophy is that humans and machines are better combined than either is alone.

### Organizational Foundations
Before discussing microservices technology, Shoup outlines the necessary organizational pillars: Small Teams, Practices, and Culture.

**1. Small Teams**
Teams are domain-aligned with well-defined responsibilities. They are cross-functional, possessing all necessary skills within the team to build their service (excluding hardware or OS functioning).

**2. Practices: TDD and Continuous Delivery**
*   **Test-Driven Development (TDD):** Tests speed up development by preventing regressions and providing the courage to refactor. Shoup argues against the excuse "we don't have time to do it right," countering with "Do you have time to do it twice?". He notes that Stitch Fix does not have a global bug tracking system because they fix bugs immediately upon discovery rather than building a backlog of half-finished work.
*   **Continuous Delivery:** Stitch Fix has 50–60 applications deployed multiple times a day. Small batch sizes make error diagnosis easier and allow for rapid experimentation, which is critical for their data science teams.

**3. Culture: DevOps**
Shoup defines DevOps as end-to-end ownership. The team that builds the service owns it from design to retirement. There are no separate QA or Ops teams; engineers are responsible for feature quality, performance, and maintenance ("You build it, you run it").

### The Evolution to Microservices
Shoup reviews the architectural history of major tech companies to illustrate that no one starts with microservices:
*   **eBay:** Started as a monolithic Perl app (1995), moved to a Monolithic C++ app (reaching 3.4 million lines of code in a single DLL), then to Java, and finally to polyglot microservices.
*   **Twitter:** Started as a "Monorail" (Ruby on Rails monolith), moved to Scala services, and then to microservices.
*   **Amazon:** Started as a monolith (C++ and Perl application named "Obidos"), moved to services, then microservices.

**Key Takeaway:** If you are a startup, a monolith is the correct choice. If you don't regret your early technology decisions later, you likely over-engineered. Microservices are a solution for specific scales (like eBay or Netflix).

### Microservices Definition and Persistence
Shoup defines microservices not by lines of code, but by the scope of the interface. They must be modular, independent, single-purpose, and have isolated persistence.

**Isolated Persistence**
A microservice must own its data store. No other service should access that data except through the published service interface. This can be achieved by:
1.  The team operating their own database instances (e.g., Postgres).
2.  Using a managed persistence service (e.g., DynamoDB), provided the service has an isolated slice/schema.

**Events as a First-Class Construct**
Shoup proposes "Events" (state changes) as the fourth fundamental building block of architecture, alongside presentation, application logic, and persistence. The interface of a service includes:
*   Synchronous Request/Response.
*   Events Produced.
*   Events Consumed.
*   Bulk Reads/Writes (ETL).

### Extracting Microservices from a Monolithic Database
Stitch Fix is in the process of moving from a shared monolithic database (where all entities live) to microservices. Shoup outlines the extraction strategy:
1.  **Create a Service:** Build a service for a specific domain (e.g., Client Service).
2.  **Redirect Access:** Change all applications to access the data via the Service Interface rather than the shared database table.
3.  **Move the Data:** Once all access is via the service, move the table from the shared database to a private database owned by the service.
4.  **Repeat:** Do this for Items, SKUs, etc. Boundaries are drawn around both the application logic and the data.

### Managing Data: Patterns and Techniques
Shoup details three areas where microservices make data management harder compared to monoliths: Shared Data, Joins, and Transactions.

**1. Shared Data**
*   **Principle:** Every piece of data is owned by a single service. Any other copy is a read-only, non-authoritative cache.
*   **Technique A (Synchronous):** Service A asks Service B for data in real-time (e.g., Fulfillment asks Customer Service for an address).
*   **Technique B (Asynchronous Cache):** Service B listens to events from Service A to update a local cache (e.g., Fulfillment updates its local address record when "Address Updated" event fires).
*   **Technique C (Shared Library):** For metadata that changes very rarely (e.g., list of US States, fabric types), distribute it as a code library.

**2. Joins**
*   **Technique A (App-Side Join):** The client application fetches data from Service A and Service B separately and combines them for the user (e.g., fetching Customer info and Order info for an Order History page).
*   **Technique B (Materialized Views):** A service maintains a denormalized cache of joined data. It listens to events from multiple services (e.g., "Item" and "Feedback") and updates a local "Item Feedback" table. This is similar to how search engines, analytics systems, and NoSQL stores work.

**3. Transactions**
Shoup advises against distributed transactions (Two-Phase Commit) as they kill scalability. Instead, he suggests using **Sagas**.
*   **Concept:** Model the transaction as a workflow or state machine of individual atomic transactions strung together by events.
*   **Rollback:** If a step fails, run the state machine in reverse using **compensating operations** to undo previous steps.
*   **Examples:** Payment processing (Visa/Banks don't do distributed transactions; they use workflows) and expense approval chains.
*   **Serverless:** Shoup notes that Serverless (Functions as a Service) is an excellent implementation for Sagas because the logic is small, stateless, and event-triggered.

### Conclusion and Q&A
Shoup concludes by reiterating the necessity of small teams, ownership culture, and microservices for scaling, and mentions Stitch Fix is hiring across the US.

**Q&A: Event Delivery**
A question is asked regarding "exactly once" delivery and out-of-order events.
*   **Exactly Once:** Shoup states this is impossible (FLP result). Do not rely on it.
*   **At Least Once:** You must choose "at least once" delivery (sender retries until success). This leads to duplicates.
*   **Idempotency:** To handle duplicates, consumers must be idempotent (doing the operation multiple times yields the same result as doing it once).
*   **Out of Order:** If ordering matters, the consumer must maintain state (e.g., using techniques like vector clocks, CRDTs, or tombstones) to reconcile creates, updates, and deletes arriving out of sequence.