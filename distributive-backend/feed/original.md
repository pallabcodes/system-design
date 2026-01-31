Resource: https://youtu.be/Xpx5RYNTQvg

Based on the transcript provided, here is a comprehensive and accurate extraction of the technical presentation "Serving a Billion Personalized News Feeds," detailing the systems, algorithms, and logic used at Facebook (Meta) to rank content and suggest friends.

### Part 1: The News Feed Problem and Scale
The presentation begins by defining the core objective of News Feed: to rank the available inventory of stories to show users the most interesting content at the top. This is critical because interaction rates are significantly higher for content placed "above the fold".

**The Scale of the Problem:**
*   **User Base:** Over 1 billion people visit daily, averaging about 10 visits per day.
*   **Inventory:** Users read hundreds of billions of stories collectively. A typical user reads ~100 stories but has thousands available to them.
*   **Ranking Volume:** The system must rank approximately **15 trillion stories per day**. This volume requires the system to be computationally efficient while running on massive infrastructure.

### Part 2: Product Mechanics and Ranking Logic
The speaker outlines the logic for how stories are presented and refreshed.

**The "New" Definition:**
Originally, the model was strictly time-based (ranking stories that occurred since the last visit). However, the system evolved to a subtractive model: anything the user has *not yet seen* is considered "new," regardless of when it was posted.

**The Ranking Cycle:**
1.  **Inventory Collection:** When a user visits (e.g., at 9:00 AM), the system collects all eligible stories.
2.  **Scoring:** Each story is given a score and sorted.
3.  **Updates:** If the user returns later (e.g., 9:10 AM), the system re-evaluates.
    *   Stories already seen are removed.
    *   Stories not yet seen (even if older) are re-ranked.
    *   Brand new stories are added.
    *   **Dynamic Re-scoring:** Stories with new activity (e.g., a new comment on a previously low-ranked story) are re-scored. A story that was previously buried might jump to the top if new data (like friend interactions) makes it more relevant.

### Part 3: Scoring and Machine Learning Strategy
The core technical challenge is converting a story's features into a single score used for sorting.

**Probability and Value:**
The system frames ranking as a classification problem. It predicts the probability of specific user actions (Click, Like, Comment, Share).
*   **Input:** Labeled data from historical logs (user scrolled past = negative; user interacted = positive).
*   **Output:** A probability vector for different events.
*   **Final Score Calculation:** The system applies "value weights" to these probabilities (e.g., a Comment is weighted heavier than a Like). These weights are determined by business judgment, A/B testing, and user surveys.

**Feature Engineering:**
The most critical features involve the **network structure** and the specific relationships between the user ("Ego") and the story author.
*   **Granularity:** It is not enough to know someone is a "friend." The system models specific relationship dimensions (e.g., a mother’s family posts are important, but her political links might not be; a coworker’s professional posts are relevant, but their personal photos might not be).
*   The feature vector captures these nuances to personalize the score for every specific viewer.

### Part 4: Evolution of the Machine Learning Architecture
The speaker details the progression of the models used for ranking, moving toward a hybrid approach.

**1. Boosted Decision Trees + Logistic Regression (Previous Generation)**
*   **Method:** The team trained boosted decision trees but did not use the boosting output directly. Instead, they treated the trees as **feature transformations**.
*   **Implementation:** The trees learned the structure and splits. The leaves of the trees were treated as boolean features fed into a **Logistic Regression** layer.
*   **Why:** This allowed the system to retrain the linear weights (Logistic Regression) in real-time or near real-time, while the expensive tree structure training occurred less frequently offline.

**2. Deep Neural Networks (Deep Learning)**
*   **Adoption:** Moved to neural networks for better performance.
*   **Constraint:** Running separate deep networks for every prediction type (Like, Comment, Share) was too computationally expensive for 15 trillion rankings.
*   **Solution: Multitask Learning.** They utilized a single network where the lower layers are shared across all event types, branching out only at the top layer for specific predictions.
*   **Benefits:** This drastically reduced cost (predicting "Share" becomes nearly free if "Like" is already computed) and improved accuracy for rare events (transfer learning from frequent events like "Likes" to rare events like "Shares").

**3. The Hybrid Model (Final State)**
To maximize performance, Facebook combined these approaches into a single architecture:
*   **Ensemble:** The system runs Boosted Decision Trees (as feature transforms) AND Deep Neural Networks concurrently.
*   **Sparse Features:** It also includes a sparse Logistic Regression component to handle high-cardinality ID features (User ID, Object ID).
*   **Final Layer:** The outputs of the Trees, the Neural Networks (last hidden layer), and the Sparse Features are all fed into a final Logistic Regression layer.
*   **Result:** This architecture captures the benefits of deep learning, the handling of sparse data, and allows for real-time weight updates.

### Part 5: Dispersion (Graph Structure Feature)
The speaker highlights a specific graph metric called "Dispersion" used to identify close relationships (like spouses) purely from graph topology, without behavioral data.

*   **The Problem with "Embeddedness":** A common metric, Embeddedness (number of mutual friends), fails to distinguish close partners from cliques (like coworkers or classmates).
*   **Dispersion Definition:** This metric measures the extent to which a user's mutual friends with a target person are *not* connected to each other.
    *   If you remove the User and the Target from the graph, does the remaining network of mutual friends fall apart?
    *   **Intuition:** A spouse bridges different unconnected clusters of a person's life (family, high school, work). They know people in all groups, but those groups don't know each other.
*   **Normalized Dispersion:** The metric works best when normalized by Embeddedness.
*   **Performance:**
    *   Dispersion identifies a spouse/partner with much higher accuracy than embeddedness or behavioral metrics like "Profile Viewing" (which decreases over time in long relationships).
    *   For married men, this graph-only metric identifies the spouse correctly ~66% of the time.
    *   High dispersion in a relationship correlates with a lower probability of breaking up.

### Part 6: People You May Know (Friend Recommendations)
The final section covers the recommendation system for finding new friends.

**Search Space and Scope:**
*   Unlike Netflix/Amazon (collaborative filtering), this is a social context problem.
*   **The 2-Hop Limit:** 92% of all new friendships on Facebook occur between people who already share at least one mutual friend (two hops away). Therefore, the system only needs to rank "Friends of Friends" rather than the whole user base.
*   **Volume:** The average user has ~40,000 to 100,000 friends-of-friends. This is due to the **Friendship Paradox**: on average, your friends have more friends than you do (because high-degree nodes are over-represented in friendship networks).

**Features for Friend Prediction:**
1.  **Mutual Friends:** The probability of friendship increases logically with the number of mutual friends.
2.  **Time-Discounted Mutual Friends:** The *age* of the friendship edge matters. Recent friends (e.g., from a new job) are better predictors of other new friends than old connections (e.g., high school friends). The system weights edges based on recency.
3.  **Other Features:** Geography, age, and the user's total friend count (used for calibration).

**Ranking and Caching:**
*   Since the social graph changes slowly (unlike News Feed stories), the system runs the heavy machine learning offline to generate the top ~100 suggestions.
*   **Impression Logic:** To avoid showing the same ignored suggestions repeatedly, the runtime system re-ranks the cached list based on **impression counts**.
*   **Formula:** The probability is roughly the offline quality score divided by the number of times the user has already seen the suggestion.
*   **Result:** Implementing this machine learning approach increased the Click-Through Rate (CTR) for friend requests by 30%.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
Yes. While the "retrieval -> scoring -> ranking" pipeline remains, the models have shifted from Boosted Trees + LogReg to massive **Deep Learning Recommendation Models (DLRM)** and **Transformers**. The "Dispersion" graph features are likely now captured by **Graph Neural Networks (GNNs)** (like GraphSAGE) rather than manual feature engineering.

**Is it scalable?**
**Yes.** The multi-stage approach (Offline generation -> Online distillation -> Edge ranking) is the only way to handle trillions of items.

**What would the architecture look like today?**
1.  **Vector Databases:** Instead of simpler inverted indices for the "Inventory" phase, modern systems use **Vector Search** (FAISS, Pinecone, Milvus) to retrieve "semantically" similar content (Embeddings) in real-time.
2.  **Real-time Feature Stores:** Systems like **Tecton** or **Feast** would manage the point-in-time correctness of features (like "number of likes in last 5 min") effectively, separating the ML logic from the data infrastructure.
3.  **Edge Inference:** For latency, some lightweight ranking (re-sorting the top 100) now happens **on-device** (in the mobile app) to react instantly to user scrolls without a roundtrip.

## Principal Architect's Q&A

**Q: How do I build a News Feed in 2025?**

**A:** Don't use the "Pull" model (Fan-out on Read) for everyone.
1.  **Hybrid Architecture:** Use **Fan-out-on-Write** (Push) for 99% of users (fast reads) and **Fan-out-on-Read** (Pull) for celebrities (avoid writing 100M rows).
2.  **Vector Embeddings**: Your "Scoring" phase should use a **Vector Database** (Milvus/Weaviate). Embed the user's history and the candidate posts into the same space. Dot product = Relevance Score.
3.  **Real-Time Features**: Use a Feature Store (Tecton/Feast) to count "Likes in last 10m" and feed that to the model.