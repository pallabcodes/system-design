Resource: https://www.youtube.com/watch?v=NHkHT8crEl4

Based on the provided transcript, here is an accurate and comprehensive extraction of the presentation "Verizon Centralizes Data into a Data Lake in Real Time for Analytics," from start to end.

**Introduction and Audience Interaction**
Arvind Rajagopalan from Verizon and Jordan Marx from Attunity introduce themselves as the final presenters of the day. Arvind notes that his team is working on building a data lake for back-office functions across finance and supply chain. Jordan explains that Attunity helps support SAP environments, specifically mapping SAP data, which is traditionally difficult, and managing enterprise-grade, high-volume environments. Jordan asks the audience about their data landscapes, inquiring if they have data silos, multi-ERP landscapes, and if they wish to marry transactional data with analytics outside of ERPs.

**Verizon’s Context and the Shift to Real-Time**
Arvind describes Verizon as a large telco provider involved in enterprise wireless and media services, noting the recent close of the Yahoo deal. He discusses the industry-wide driver for Big Data, noting that traditional capturing methods miss much of the generated data. While traditional databases and warehouses exist, there is a shift toward Hadoop and in-memory processing.

Arvind emphasizes the move from batch mode—where jobs ran overnight—to a real-time enterprise model. Because the digital economy operates 24/7 globally, there is a need to stream and process data in real-time to make timely decisions, such as changing offers or prices.

**Architectural Evolution: From App-Centric to Data-Centric**
Arvind outlines Verizon's historical "App-Centric Model," where finance and supply chain applications (ERP, payment, collection, settlement systems) relied on one-to-one interfaces to pass data. This model created data silos. Verizon is moving toward a "Data-Centric Model" (Data Lake), which centralizes data to remove hardware limitations regarding storage and archiving while enabling seamless data sharing between applications.

He provides a specific use case regarding Total Cost of Ownership (TCO) analysis for network operations. Traditionally, tying network assets/inventory to financials (depreciation, maintenance overhead) was difficult. By centralizing data in a lake, they can now tie this data together for better analysis.

**Drivers for the Data Lake**
Arvind details the drivers for this migration:
*   **Data Reservoir:** Removing constraints on which columns or rows to store; the entire dataset is brought in.
*   **Active Archive:** Combining historical and active transactional data in one place for revenue assurance and billing use cases.
*   **Convergence of Analytics and Data:** enabling ad-hoc analysis and discovery without giving users direct access to production databases.
*   **Self-Service:** Moving away from extensive IT development lifecycles (modeling, ETL) to a "schema-on-read" approach.
*   **ETL Offload:** Reducing the compute/storage burden on transactional systems by moving processing work to the centralized database.

**Verizon’s Architecture and Ingestion Framework**
Arvind presents the high-level architecture. Data sources (ERPs) feed into the ingestion layer using Attunity Replicate. Once in the data lake, security is applied, followed by a semantic model using tools like Kyvos, with consumption via visualization tools like Tableau and Qlik, and machine learning via the H2O platform.

The solution addresses challenges such as managing data in motion (real-time Change Data Capture), scaling to Verizon's volume (110+ million wireless customers), handling breadth/depth of data, and ensuring traceability/lineage for finance.

Arvind details the specific ingestion improvements:
*   **Old Architecture (2-Hop):** Used GoldenGate and SLT for SAP, loading into a stage Oracle database, then using Sqoop to load into Hadoop.
*   **New Architecture (1-Hop):** Uses Attunity Replicate to read directly from logs and deliver to Hadoop. This works across their two large SAP platforms and PeopleSoft platforms.
*   **Micro-Batches:** Once data lands in Hadoop, they run micro-batches (every 5–10 minutes) to merge inserts, updates, and deletes into the HDFS files to ensure the latest transactions are shown.

**Attunity’s Capabilities and SAP Integration**
Jordan Marx elaborates on Attunity’s role. They focus on the OLTP layer, mapping and extracting from relational databases, mainframes, and ERPs. The tool, Replicate, creates real-time event publications with caching mechanisms to persist datasets. It supports various targets including Redshift, Hortonworks, HDInsight, and SAP HANA.

Jordan highlights the "ease of use" for SAP integration. Attunity abstracts away the underlying tables (often four-letter acronyms) and helps map the complex SAP data model. The key selling point for Verizon was handling SAP's complexity and providing the lightest possible impact on the source operation by reading logs rather than using trigger-based extraction.

Jordan notes a shift in telecommunications, observing that companies like Verizon are becoming "data companies to the max," needing fast customer profiling to support business models like subsidized services via advertising (similar to emerging markets).

**Business Outcomes and Governance**
Arvind describes business outcomes, such as providing a "One Verizon" view of spend and allowing AP teams to calculate working capital in minutes rather than days. Real-time data also supports revenue-share agreements with vendors and advertising partners.

He outlines key migration considerations:
*   **Master Data Management (MDM):** Essential for a "single version of the truth".
*   **Data Quality:** Deduplication and referential integrity.
*   **Security:** Authentication, authorization, and encryption (at rest and in motion).
*   **Compliance:** Data masking for regulatory requirements.
*   **Governance Tool:** Verizon uses Collibra for data governance in finance.

**Demonstration of Automation**
Jordan performs a quick demo of Attunity Replicate and a secondary product (Attunity Compose) released that week. The tool automates the ingestion and "merge" process (reconciling inserts/updates) and automatically generates the necessary Hive infrastructure (DDL). Jordan demonstrates generating 50 statements and moving 10 tables in under a minute, handling the underlying complexity of HCatalog and automation. Arvind confirms this automation is a huge differentiator, allowing them to scale to replicating 200,000 tables to Hadoop in real-time.

**Q&A Session**
*   **Network Bandwidth:** When asked about network impact, Arvind explains that streaming data in real-time throughout the day actually optimizes network usage compared to sending massive batch files overnight.
*   **Streaming Philosophy:** Jordan notes that data lakes only work when data landing is consistent. The goal is to turn every part of the business into a "publisher," changing yesterday's processes into fully latent, real-time environments.
*   **SQL Server Support:** Jordan confirms Attunity reads directly from SQL Server transaction logs (no triggers), a capability they have had since 2005.
*   **SAP Pool and Cluster Tables:** A specific question is asked about "pool and cluster tables." Jordan explains that Attunity abstracts the proprietary SAP structures (decoding the logic that requires multiple table joins) and natively replicates them as standard tables immediately upon landing.
*   **Migration Utility:** The metadata modeling capability comes from a migration utility Attunity purchased years ago that has been vetted in roughly 200 implementations.
*   **Unstructured Data:** Jordan confirms they can handle semi-structured or unstructured data as long as it has a relational background (like Teradata or DBF).