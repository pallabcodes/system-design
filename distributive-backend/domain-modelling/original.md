Resource: https://youtu.be/MlPQ0FsPxPY?list=TLGGX5ld16Ij8A0wOTAxMjAyNg

Scott Wlaschin’s presentation focuses on how functional programming languages—such as F#, TypeScript, or Scala—can be used to represent **domain models accurately and collaboratively**. He argues that functional programming is not just for mathematics but is an excellent tool for **Domain-Driven Design (DDD)** because it allows the code to act as a shared mental model between developers and non-developers.

### **1. The Philosophy of Design and Collaboration**
The core goal is to reduce "garbage in" by emphasizing **design and thinking before coding**. Wlaschin combines ideas from **Agile** (rapid feedback) and **DDD** (shared language) to ensure that concepts used by domain experts are reflected directly in the code. 
*   **Shared Mental Model:** Everyone on the team (developers, testers, product owners) should use the same words and concepts.
*   **Code as Documentation:** When the common language is embedded in the code, it acts as executable documentation that a non-programmer can understand and provide feedback on within minutes.
*   **Persistence Ignorance:** True domain design focuses on concepts, not database tables, foreign keys, or object-oriented jargon like "factories" or "proxies".

### **2. Modeling with Functional Syntax**
Using F# as an example, Wlaschin demonstrates how to model a domain using simple, composable symbols:
*   **Choices (OR):** Represented by a vertical bar (`|`), this models an "either/or" scenario (e.g., a suit is a Club **or** Diamond **or** Spade **or** Heart).
*   **Pairs (AND):** Represented by a star (`*`), this models a record or a combination of data (e.g., a Card is a Suit **and** a Rank).
*   **Workflows (Verbs):** Represented by an arrow (`->`), this models an action or a use case (e.g., inputting a Deck and outputting a dealt Card and the remaining Deck).
*   **Immutability:** In functional modeling, actions do not "mutate" data; instead, they return a new copy with the changes applied.

### **3. Building with a Composable Type System**
Wlaschin compares functional types to **Lego**, where complex systems are built by connecting small, simple pieces.
*   **Avoiding "Primitive Obsession":** Domain concepts should not be represented by generic types like `string` or `int`. Instead, developers should use **wrapper types** for concepts like `EmailAddress` or `CustomerID` to prevent bugs like mixing up two different kinds of numbers.
*   **Handling Optionality without Nulls:** He asserts that `null` is a "historical accident" and a "lie" because it is not actually a string or an object. Instead, functional languages use an **Option type** (representing "Something" or "Nothing") to explicitly document when data might be missing.
*   **Constrained Types:** Constructors for types like `EmailAddress` or `Quantity` should return an `Option` rather than throwing exceptions, forcing the caller to handle the case where the data is invalid.

### **4. Enhancing Design Logic**
Wlaschin illustrates how to move logic out of documentation and into the type system using a "contact" example:
*   **Replacing Booleans with States:** Instead of a `Boolean` flag like `IsVerified`, a domain should be modeled as a choice between an `UnverifiedEmail` and a `VerifiedEmail`.
*   **Enforcing Rules through Types:** By making certain functions (like `SendPasswordReset`) require a `VerifiedEmail` as input, the code becomes **self-documenting and self-verifying**. It becomes impossible to compile a unit test that tries to send a reset to an unverified email.
*   **"Make Illegal States Unrepresentable":** This is the ultimate goal of functional domain modeling. For example, if a business rule states a user must have either an email or a postal address, the developer should design a **Choice type** that only allows the three valid combinations (Email, Address, or Both), making it physically impossible for the code to represent a state where both are missing.

### **5. The Iterative Process**
The design is not "fixed" at the start but evolves as the developer learns more from domain experts. Because the type system is statically checked, refactoring becomes safer; when a type changes, the compiler identifies every location in the code that needs to be updated, providing confidence that the system remains consistent. 

Wlaschin concludes by recommending that developers **avoid primitive types**, **use choices instead of inheritance**, and always strive to make bad states impossible to represent in their architecture.

***

**Analogy for Understanding**
Functional domain modeling is like **building a physical puzzle where the pieces only fit together if they follow the rules of the house.** If you try to force a "square" piece (an invalid email) into a "round" hole (a verified contact), the puzzle simply won't click into place. Instead of writing a manual explaining that you shouldn't force pieces together, the very **shape of the pieces** (the type system) prevents the mistake from happening in the first place.