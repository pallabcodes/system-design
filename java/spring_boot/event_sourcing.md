Resource: https://youtu.be/_d4mAi3qkDA (review mandatory)

**Introduction to Event Sourcing and the Context**
The speaker, Michael from Klarna, shares the lessons learned and problems encountered over two years of implementing **event sourcing** and **CQRS** in their systems. Fundamentally, event sourcing involves storing everything that happens to an entity (like an order) instead of merely updating its current state. For instance, instead of updating a database row with a new amount, a completely new row stating "order amount updated" is added to the log. 

**Problem 1: Testing and Backward Compatibility**
The team encountered a significant challenge regarding testing. While they had standard unit and black-box tests, a new issue arose: when a schema element changed (like adding a new field to an order), old events in production still needed to function correctly. Because the production database lacked the new field for old orders, it caused a production failure.

*   **The Solution:** They started writing tests that immediately write the specific state of an order to the database whenever it changes. This creates a historical record of how orders have looked over time, ensuring all standard operations continue to work securely.

**Problem 2: Monitoring Missed Events**
Standard monitoring successfully caught HTTP 500 errors and network failures, but it could not detect if an expected event simply failed to happen. For example, if the Order Service sends an event to Kafka (acting as a message queue) and a consumer is supposed to read it and index it into Elasticsearch, standard metrics wouldn't reveal if a specific event got lost in Kafka or the network.

*   **The Solution:** Inspired by the "Hansel and Gretel" breadcrumb trail, they implemented an event matching system. When the Order Service creates an order, it emits a specific "I created an order" event to a separate Kafka channel. The consumer correspondingly emits an "I indexed this order" event. By matching these, if the Order Service's event isn't matched by a consumer event within a **10-minute threshold**, the team receives an alert. This breadcrumb system also easily verifies if a bug fix in the consumer successfully handles all past unhandled events.

**Problem 3: Keeping Domain Boundaries Small**
A major source of internal conflict was protecting the domain boundary. Because the Order Service creates orders and many other services consume them, other teams began treating the Order Service like a general message bus. For instance, a Checkout Service wanted to pass customer purchase analytics through the order event. The Order Service team had to say "no" because customer analytics do not belong on an order aggregate.

*   **The Solution:** It is crucial to say "no" to protect the domain; otherwise, the domain grows excessively, leading to validation problems and unwanted dependencies. However, simply saying "no" causes anger and friction. The proper approach is to help the other teams build an appropriate separate service (like a Customer Service) or establish a different communication channel to handle their specific data needs without polluting the order domain.

**Problem 4: The Lack of Event Schemas**
Initially, the team avoided defining strict event schemas because they thought sending JSON was sufficient and that strict schemas (like Avro) were only useful for performance optimization.

*   **The Lesson:** This proved to be a mistake. Without schemas, consumers struggled to build their own domain models based only on examples or DTOs. Having a schema allows consumers to automatically generate usable code and provides built-in versioning for free. The team now generates schemas from their DTOs, acknowledging that spending just a couple of days defining schemas initially would have prevented many problems.

**Problem 5: Event Ordering and Network Speed**
While Kafka guarantees the order of messages once they are in the queue, asynchronous network behavior can disrupt the logical order of operations. If the Order Service creates an order in the database and immediately returns an HTTP response, a client might instantly send a second request to update that new order. Because sending to Kafka is asynchronous and networks are unreliable (especially across multiple service instances), the "update" event might reach the consumer before the "create" event. This caused consumers to angrily complain about receiving updates for orders that did not yet exist.
*   **The Solution:** They removed direct Kafka sending from the Order Service. Instead, they introduced a **new, dedicated service that reads directly from the database**, ordering events precisely by aggregate ID and aggregate version. This strictly partitioned service ensures events are sent to Kafka in the exact, correct chronological order without skipping.

**The Good Things: Massive Advantages of Event Sourcing**
Despite the challenges, the speaker highlighted that event sourcing provided exceptional benefits:
*   **Consistently fast queries:** Database indexing is incredibly simple because it usually relies on just one column, entirely avoiding the need to optimize for complex joins.
*   **Easy replication of immutable data:** Copying data is as simple as sending messages from Kafka to another database, effortlessly achieving master-master replication across different data centers.
*   **Restricted querying forces best practices:** Because you cannot easily query the raw event data directly, it strictly forces developers to "do it right" by moving queries elsewhere, creating specific read models (e.g., in Elasticsearch) optimized for exact use cases.
*   **Encourages good domain models:** It naturally pushes developers to keep their domain models small and cleanly separated.
*   **Permanent historical data:** Nothing is ever deleted. If the business requests a complete history of orders from two years ago, the team can easily provide a dedicated endpoint containing that entire, perfect history within ten minutes.

The speaker highly recommends event sourcing, suggesting teams start with a small implementation first, noting that overall it makes developers' lives much better.