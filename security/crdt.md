Resource: https://youtu.be/Exr0iY_D-vw?list=TLGG9oQsySTni-cwMjAzMjAyNg (review must)

**Introduction and Context**
Matthew Weidner, a third-year PhD student at Carnegie Mellon University (working with Heather Miller, who could not attend), presents on making web applications collaborative using composable Conflict-free Replicated Data Types (CRDTs). He defines collaborative apps as those where a small group of users work together to edit shared state, such as Google Docs, shared notepads, or whiteboards. 

**The Challenge of Adding Collaboration**
Weidner uses a simple recipe book app as a running example. Initially, it is a static, single-user application (about 200 lines of TypeScript, HTML, and CSS) that runs purely in the browser. To make this app collaborative, developers traditionally rely on full-stack architectures involving cloud servers, sync protocols, and user accounts. However, this traditional approach introduces significant downsides:
*   **Cost and Complexity:** It requires money to host servers and potentially starting a company to manage it at scale.
*   **Privacy:** Users lose data privacy (e.g., exposing secret family recipes to server admins).
*   **Longevity and Offline Use:** If the server shuts down, the app dies. The app also will not work offline.
*   **Open Source Friction:** Even if the source code is public, another developer cannot easily fork and republish the app without setting up and paying for the same heavy server infrastructure.

The goal is to achieve the collaboration of modern web apps while retaining the simplicity, privacy, and low deployment cost of static, single-user apps.

**The Solution: Client-Side CRDTs**
Drawing on the "True Data" research by Martin Kleppmann (Weidner's former MPhil advisor at Cambridge), the core idea is to shift the single point of truth away from a central server. Instead, the application state is stored in client-side Conflict-free Replicated Data Types (CRDTs). 

When a user makes a change (e.g., Grandma editing the ingredient "carrot" to "carroot" by calling a text CRDT insertion function), the CRDT sends a message encoding the effect of that change to other users. 
*   **True Copies:** Each client possesses a "true copy" of the state, allowing the app to work offline and sync changes later.
*   **Eventual Consistency:** As long as clients can eventually exchange messages, they will converge to the exact same state, regardless of message ordering or delivery time.

**The `collabs` Library and Architecture**
Weidner introduces **collabs**, a new TypeScript library released on npm that provides collaborative versions of ordinary data types (text, maps, arrays, registers). 
Using `collabs`, the architecture changes: the app's frontend connects to internal `collabs` data structures instead of normal data structures, which then connect to a network layer.

Crucially, the network requirement is only that it provides "broadcast messaging". Because CRDTs handle message ordering and eventual consistency, developers can use *any* network to pass these messages, completely avoiding monolithic server lock-in. Alternatives include:
*   WebRTC or IPFS.
*   Group chat protocols like Matrix.
*   "Sneakernet" (mailing USB sticks).

**Converting the App**
To make the recipe app collaborative, developers replace standard types with `collabs` types. For example, a text string becomes a collaborative text, numbers become a special collaborative number, and units use a Last-Writer-Wins (LWW) register (which resolves simultaneous edits based on wall-clock time). 
This increases the code from 211 lines to about 500 lines (though effectively ~300 lines when factoring out reusable boilerplate). Once converted, the app can be hosted purely as static files on a platform like GitHub Pages.

**Live Demonstrations**
Weidner showcases three demos:
1.  **Matrix-backed Collaborative Recipe Book (with End-to-End Encryption):** He demonstrates editing recipes across two browser windows connected via a 4G mobile hotspot. The network layer is outsourced to **Matrix** (via the Element client), an open-standard group chat protocol. Because it uses Matrix, the communication is inherently end-to-end encrypted; if a user types a sensitive password (like "hunter2"), it is entirely hidden from network adversaries or server admins.
2.  **LAN / Server-Free Collaboration:** To prove messages do not need a central server, he disconnects his 4G connection and runs the app using `libp2p` via localhost (noting the peer-to-peer phone connection was flaky during the presentation). The clients find each other using multicast DNS, allowing collaboration on airplanes or in the field without broader internet access.
3.  **Complex App Conversion (Horse Gene Editor):** He demonstrates a complex shared whiteboard, rich text editor, and a highly niche "horse gene editor" originally built as a static site 10 years prior by artist Jennifer Hoffman. Using `collabs`, Weidner made it collaborative in a single weekend without building custom backend infrastructure.

**Why Build a New CRDT Library?**
Addressing the existence of other CRDT libraries (like Riak, yjs, and automerge), Weidner outlines three unique properties of `collabs`:

**1. Flexible and Extensible:**
Developers can create and add new collaborative data types without forking the library's source code. For example, Weidner implemented a complex algorithm from a POPL 2020 paper by Martin Kleppmann concerning moving elements in list CRDTs (allowing an ingredient to be moved in a list without destroying text edits happening concurrently). 

**2. Composable:**
Writing CRDTs from scratch is difficult, requiring mathematical proofs for correctness. `collabs` provides composition techniques so developers can glue existing correct CRDTs together to create new ones safely. 
*   *Basic Composition:* Kleppmann's movable list was easily implemented by combining a collaborative set of `(value, position)` pairs with a pre-built `DenseLocalList` class.
*   *Advanced Composition (The Gingerbread Problem):* Imagine doubling a recipe (multiplying flour from 3 to 6 cups). Concurrently, your cousin reduces the flour to 2.8 cups. Standard LWW registers would blindly pick one edit (e.g., 2.8 cups), losing the intent to double the recipe and resulting in ruined cookies. `collabs` solves this using a technique called the **Semi-Direct Product** (published by Weidner, Miller, and Chris Meiklejohn at ICFP 2020). It mathematically combines the "multiply" operation with the "set" operation, resulting in 5.6 cups, matching user intuition.

**3. Keeps Data Model and Type Safety:**
Unlike some CRDT libraries that force data into unstructured JSON maps (losing object-oriented structure), `collabs` allows developers to keep their original classes, constructors, instance fields, and encapsulation, maintaining strong TypeScript typing.

**Q&A Session Extraction**
*   **Schema Evolution/Unknown Fields:** When asked how the library handles adding new fields to an object in newer versions, Weidner notes they haven't solved it yet but plans to use a Protobuf-like approach where clients simply ignore instance fields they do not recognize.
*   **Implementation of the Gingerbread Example:** Weidner shows the code, explaining it combines a `multNumber` (multiplication operation) and an LWW register. When multiplied, it multiplies all known numbers and uses the semi-direct product to safely multiply any new numbers that appeared concurrently.
*   **User-Defined Conflict Resolution:** A question asked if users could define how conflicts are resolved. Weidner states it is tricky because custom resolutions might break the mathematical correctness guarantees required for convergence, though it would be ideal.
*   **Network Setup:** Weidner displays the code showing how the core app logic is kept completely agnostic from the network. A generic `BroadcastNetwork` interface is implemented specifically for Matrix to pipe messages to the group chat, or via `libp2p` using multicast DNS and TCP connections for peer-to-peer.
*   **Defaulting to LAN:** He confirms the LAN setup works automatically on home networks (where peer-to-peer isn't blocked). A future goal is to build a user-friendly wrapper so non-technical users can easily select their desired network.
*   **Future Plans:** Next steps include addressing technical debt and fully integrating a feature (currently in alpha) that allows users to save the entire collaborative state to a file and load it later to resume collaboration.
*   **Language Portability:** Because the system simply involves data structures passing messages, it is highly flexible. He notes other libraries like automerge are moving to Rust and WebAssembly, hinting at broad portability potential.