Resource:

Based on the transcript of the video **"RBS: Inside the Spider’s Web: Dependency Management with Neo4j,"** here is an accurate and comprehensive account of the presentation from start to end.

### **Introduction and Context**
The presentation is delivered by Stelios, representing **Digital Engineering Services**, a division within **RBS (Royal Bank of Scotland)**. He begins by asking the audience about the difficulty of delivering software to production, noting that his team aims to make the process easier.

**The Project Scope:**
*   **Agile Markets:** Approximately two and a half years ago, the team set out to revamp the RBS investment bank's singular dealer platform, known as Agile Markets.
*   **Zambezi:** To support this, they created "Zambezi," a homegrown, open-source style framework designed to accelerate the delivery of electronic customer experiences (digital channels). It utilizes web technologies like HTML on the frontend and microservices on the backend.
*   **Scale:** The project is massive, involving 10 to 20 different delivery teams and a three-digit number of developers.

### **The Problem: Legacy Deployment and Complexity**
 despite creating a modern platform, the team faced significant challenges regarding deployment:
*   **Legacy Processes:** They inherited manual deployment processes involving change requests and isolated installation teams.
*   **The "Butterfly Effect":** The legacy process caused issues where deploying a library to UAT, Dev, or Production resulted in minor changes having huge, negative ramifications, breaking the system.
*   **Regulatory Pressure:** As a highly regulated bank, they frequently had to answer questions regarding the state of the estate (what was deployed, where, when, and which versions). The team felt trapped in a "tangled web" of dependencies between teams and artifacts, which slowed them down.

### **The Solution: Dart**
To address these issues, the team created a tool called **Dart**. They considered extending existing tools like TeamCity but found it wasn't straightforward enough for their specific needs.

**Key Requirements for Dart:**
1.  **Integration with "Golden Source" Systems:** Dart needed to integrate with internal systems like "Gel," a registry of all teams, users, and hosts within the bank.
2.  **Flexibility:** They wanted to expose information via a REST API to support future interfaces (Web UI, mobile clients).
3.  **Transitional Strategy:** The tool needed to integrate with legacy deployment tools initially but allow for a transition toward a strategic goal of cloud deployment (internal, external, or hybrid).

### **Why Neo4j?**
The decision to use Neo4j originated from a whiteboard session where the team mapped out their requirements.
*   **Graph Modeling:** The conceptual diagram looked like a graph. Attempting to model it with an Entity-Relationship Diagram (ERD) for a relational database felt like "fitting a square peg in a round hole".
*   **Schema Flexibility:** They needed the ability to "change the wings of the plane while the plane flies." With Neo4j, they can continuously change the schema and add features every two weeks by simply adding nodes and relationships—something that would be difficult with a relational database,.
*   **Cypher Query Language:** Using Cypher allowed them to perform complex queries naturally (e.g., returning everything attached to an environment at a depth of two). Equivalent SQL queries for determining the "true state" of deployment involved excessive and confusing lines of joins.

### **Technical and Operational Benefits**
**Ease of Integration:**
RBS aspires to a true microservices architecture. Dart itself is a microservice, and embedding Neo4j was simple. It allowed them to spin up a cluster without needing an external housekeeping service, making cloud deployment easier.

**Visibility and Control:**
The team now feels empowered (likened to Peter Parker/Spider-Man) rather than lost.
*   **Real-time Status:** They can instantly identify what is deployed where and for which digital channel.
*   **Audit and Time Travel:** They track who performed deployments and when. They can also "rewind the clock" to see the exact state of an environment (frontend and backend artifacts, hosts) at a specific time in the past.
*   **Early Warning System:** Because they track dependencies (NPM registry, Maven artifacts), they can perform impact analysis. Before upgrading a library, they can see exactly which teams use it and who to contact, avoiding the need to email hundreds of people blindly.

### **Current Success and Future Goals**
**Adoption:**
*   Usage of Dart has grown 50% month-on-month over the last seven months.
*   Developers are getting "hooked" on the automation, leading to increased productivity and the elimination of advanced planning for deployments.
*   The tool is being rolled out to the entire RBS group (including Lombard, NatWest, Ulster Bank), eventually serving an internal market of **10,000 developers**.
*   They are moving from tens of deployments per day to hundreds.

**Future Roadmap:**
*   **Cascaded Regression Testing:** Using the dependency graph to automatically launch tests on downstream systems when a library is released, ensuring updates don't break target environments.
*   **Analytics:** Using the single source of truth to analyze peak productivity times.
*   **Infrastructure Evolution:** Moving everyone toward Platform as a Service (PaaS), OpenShift, Docker containers, and hybrid infrastructure.

### **Conclusion**
The presentation concludes by emphasizing that the value is not just in creating a release management tool, but in using tools like Neo4j to identify and solve friction points in the development process (like building artifacts and pushing to environments). This empowers teams to solve problems and generate valuable additional information,.