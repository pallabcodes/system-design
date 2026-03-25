Resource: https://www.youtube.com/watch?v=9vBRjGgdyTY

Based on the transcript provided, here is an accurate and comprehensive extraction of the presentation "Real-Time Search and Recommendation at Scale Using Embeddings and Hopsworks" from start to end.

### Introduction: The Challenge of Operational ML
The presentation begins by acknowledging that personalized search and recommendations are hard problems. To create value with AI, organizations typically start by organizing their data in lakes or warehouses for Business Intelligence (BI). Data scientists often begin with "laptop ML," fitting curves to data locally. The next step is building prediction services, often starting with batch prediction services like Spotify Weekly, which runs a batch program over 200 million users once a week to deliver predictions.

However, batch processing is distinct from operational ML with real-time data, exemplified by TikTok, which learns user behavior immediately as they scroll to update features and state, even if the models are static. Operational ML can also occur with batch data, such as a surfing website predicting wave heights once per day.

### The Project: Personalized Search for Python Developers
The talk focuses on the highest business value level: personalized search and recommendations, specifically targeted at Python developers. This task traditionally requires significant infrastructure: access to enterprise data, a feature store for features, a vector database for embeddings and similarity search, and model serving capabilities. Traditionally, this would require a team of data engineers, data scientists, and ML engineers, but this presentation demonstrates how to achieve it using Python and notebooks on the Hopsworks platform.

**The Platform:**
The project uses Hopsworks, the first open-source feature store. It is Python-centric and includes model serving capabilities and a vector database. It connects enterprise data to the infrastructure required for personalized search and recommendations at scale, utilizing a vector database based on **OpenSearch** and model serving via **KServe**.

### Recommendation Systems Overview
Recommendation systems typically operate in domains like retail or streaming.
*   **Item-to-Item:** Recommending items based on similarity to other purchased items.
*   **User-to-Item (Personalized):** Includes user attributes (history, preferences, age, location) to make recommendations.

While collaborative filtering and content-based filtering are common approaches, this presentation focuses on the **Two-Tower Model** using embeddings for personalized search.

**Batch vs. Real-Time Architectures:**
*   **Batch Recommendations:** Standard architectures (like Spotify Weekly or Netflix's older systems) involve raw data flowing into a feature store, a daily/hourly program computing predictions, storing them in a database (e.g., Cassandra), and consuming them when the user logs in. This is also used for predictive analytics.
*   **Real-Time Recommendations (Retrieval and Ranking):** This architecture, pioneered by YouTube and used by TikTok, is necessary when dealing with millions of items (e.g., an H&M clothing dataset).

### The Retrieval and Ranking Architecture
The process involves going from millions/billions of items down to a few hundred candidates (Retrieval/Candidate Generation) and then ordering them (Ranking).

**1. Retrieval (Candidate Generation):**
To go from billions of items to hundreds, a **vector database** is used. The system computes embeddings from user features, item features, and context (e.g., search queries or last clicked item) to find best candidate items. This requires history and context from the feature store and models served via KServe.

**2. Embeddings:**
An embedding is a mapping of discrete/categorical variables to a dense representation (an array of floats). This allows for **similarity search**. For example, images or words can be converted to embeddings to find similar items or perform arithmetic (e.g., "fast" + "faster" = "fastest").

**3. The Two-Tower Model:**
This model maps the user space into the item space by jointly training user embeddings and query embeddings. This builds an index of items. When a search or click occurs, the system uses a nearest neighbor index to find items closest to the embedding containing user personal features and recent interactions.

**4. Filtering:**
After retrieval, static filtering can be applied (e.g., removing R-rated movies for underage users) directly in the similarity search. Dynamic filtering (e.g., removing recently bought items) requires looking up dynamic features in the feature store.

**5. Ranking:**
The retrieved candidate IDs are enriched with features for both the item and the user from the feature store. A ranking model (often a fast model) is used to sort these candidates to ensure diversity and relevance.

### The Role of the Feature Store
In this architecture, the web-facing application (e.g., Node.js) is stateless and does not store user history. The feature store provides pre-computed features (history, context, trends) to enrich feature vectors for predictions and similarity search.

**Data Ingestion:**
Using the H&M Kaggle dataset as an example, data consists of Users, Items, and Transactions (the link between users and items). These are written into **Feature Groups** (tables of features).
*   **Offline API:** Used to select features (e.g., ranking view) and create training data.
*   **Online API:** Used to serve pre-computed feature vectors at very low latency.
*   **Writing Data:** Can be done via Python Pandas, Spark, Flink, or by mounting external tables (Snowflake/Databricks).

**The Feedback Loop:**
To train the ranking model and compute embeddings, the system must log user actions. A click might be given a score, and a purchase a higher score; this information is used to create training data.

### Implementation Details
**Infrastructure Flow:**
1.  Users/Items/Transactions flow from the warehouse/Kafka to the Feature Store.
2.  Features are retrieved to train three models: User Embedding Model, Item Embedding Model, and Ranking Model.
3.  Item embeddings are written to the approximate nearest neighbor index in OpenSearch via a Spark or Python app.

**Training the Two-Tower Model:**
The Item Tower receives item features; the User Tower receives user features. The loss function determines if the point in embedding space for the user query is close to the item actually bought. Common loss functions include cosine loss, dot product, or sigmoid.

**Training the Ranking Model:**
This model uses logged ground truth (clicks/purchases as labels). It requires positive examples (clicks) and many negative examples (no clicks). Gradient Boosted Decision Trees are typically used for speed. In the demo, embeddings are trained in TensorFlow, and the ranking model in **CatBoost**, then stored in the Hopsworks model registry designed for KServe.

**The Runtime Flow:**
1.  **User Query:** A user provides input (text, purchase, or session history).
2.  **Feature Lookup:** User identity is used to retrieve pre-computed features (age, preferences, recent history) from the feature store.
3.  **Embedding:** These features are sent to the embedding model (hosted in KServe or embedded) to receive an array of floats.
4.  **Similarity Search:** This embedding is sent to OpenSearch to retrieve ~250 candidate item IDs.
5.  **Filtering:** Candidates are filtered (e.g., remove items already bought).
6.  **Batch Feature Lookup:** The system must look up features for all 250 candidate IDs plus the user features from the feature store. This requires very low latency.
7.  **Ranking:** The batch of 250 feature vectors is sent to the ranking model, scored, sorted, and returned to the user.
8.  **Logging:** Outcomes (clicks/non-clicks) are logged back to the feature store for future training.

**Performance Scale:**
Hopsworks uses **RonDB** (an in-memory database) which allows for high performance. In a benchmark comparison with Spotify involving Aerospike, Redis, and Cassandra, RonDB handled 2 million operations per second with 6 nodes. For a batch lookup of 250 items, the p99 latency was under 30 milliseconds (compared to 40ms for Aerospike).

### Code Walkthrough (The Notebooks)
The presenter demonstrates the implementation using seven Python notebooks.

**Notebook 1: Feature Engineering**
*   Reads CSVs (Articles, Customers, Transactions) into Pandas dataframes.
*   Performs feature engineering and writes them to **Feature Groups**.
*   Feature Groups have versions (important for MLOps and schema changes), primary keys, and must have the online store enabled for low latency retrieval.
*   Transactions include an event time column for point-in-time correct joins.

**Notebook 2: Feature Views**
*   Creates a **Feature View** using a domain-specific language to join features from different groups.
*   Handles the complex "point-in-time join" problem (selecting the correct feature value valid at the specific time of the transaction) without writing complex SQL.
*   The Feature View registers the schema and allows creating training data (CSV/TFRecords).

**Notebook 3: Training the Two-Tower Model**
*   Uses **TensorFlow Recommenders**.
*   Converts training data into a TensorFlow dataset.
*   Defines a User Tower (Keras model with user features like age) and an Item Tower (item features).
*   Trains the model jointly and uploads it to the model registry with its schema and signature.

**Notebook 4: Populating the Vector Index**
*   Reads all items and uses the Item Tower to compute embeddings for them.
*   Writes these embeddings to the OpenSearch KNN index (using Faiss engine) via a bulk insert.

**Notebook 5 & 6: Training the Ranking Model**
*   Creates a Feature View for ranking data.
*   Generates training data with negative examples (using a ratio of 10 negative examples to 1 positive example).
*   Retrieves training/test splits and trains a **CatBoost** model.
*   Uploads the model, metrics, and schema to the registry.

**Notebook 7: Deployment with KServe**
*   Deploys the solution not as a full microservice, but using KServe.
*   Uses a **Transformer** component (Python code running in a Docker container) that runs before the **Predictor** (Model).
*   The Transformer implements the logic: connecting to the feature store, retrieving features, and querying OpenSearch.
*   The resulting deployment provides a prediction service accessible via a frontend.

### Conclusion
The speaker recommends capturing **untransformed** feature logs to enable continuous system improvement. The presentation concludes by inviting users to try the Hopsworks Serverless platform (app.hopsworks.ai), which offers a free tier, to build and demonstrate full prediction services rather than just models.