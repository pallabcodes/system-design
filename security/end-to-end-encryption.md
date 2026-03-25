Resource: https://youtu.be/oRZoeDRACrY?list=TLGGe0E0nE-F6k4wMjAzMjAyNg (must review)

Based on the transcript of the video "End-to-end encryption: Behind the scenes" by Martin Kleppmann and Diana Vasile, here is a comprehensive extraction of everything discussed in the presentation, from start to end.

### **Introduction and the "True Data" Project**
Martin Kleppmann and Diana Vasile, researchers at the University of Cambridge computer lab, introduce their talk on end-to-end encryption (E2EE). While E2EE has been around for decades, it is only recently hitting the mainstream through messaging apps like Signal and WhatsApp. They introduce their project, "True Data" (spelled "Trve Data"), which aims to bring E2EE to a broader range of applications, such as Google Docs, so users do not have to inherently trust Google's servers.

**The Illusion of the Cloud and HTTPS**
When applications claim to be "secure," they typically mean they run HTTPS (HTTP over TLS/SSL). This encrypts data *in flight*, treating the internet (like a coffee shop Wi-Fi hotspot) as untrusted. However, this model still fundamentally trusts both the end-user devices and the service provider's servers, meaning the servers can read the data in plaintext. 

The speakers remind the audience that "there is no actual Cloud, it's just someone else's computer". When using services like Evernote, Facebook, or Google Docs, users are trusting service providers with sensitive information. True E2EE ensures that data is cipher text all the way from one user's device to another, treating both the internet and the central servers as completely untrusted entities.

### **PGP and RSA Cryptography**
They begin with PGP (Pretty Good Privacy), a system from the 1980s used for encrypting emails and files, noting it is notorious for usability problems. PGP relies on public and private key cryptography, specifically RSA.

**RSA Math Basics:**
*   Keys are generated such that multiplying them in certain mathematical sets yields 1.
*   If Diana wants to encrypt a message `M`, she uses Martin's public key (`M_pub`) and her private key (`D_priv`).
*   Exponentiation is used because it is computationally very difficult (taking millions of years) to reverse engineer the message without the private key.

**Digital Signatures:**
To prove she authored a message, Diana hashes the message and raises it to the power of her private key (`D_priv`), creating a signature. When Martin receives it, he raises the signature to the power of Diana's public key (`D_pub`) to retrieve the hash. If this matches his own hash of the message, he knows Diana definitively authored it.

### **Live Demo: The PGP Process and its Flaws**
To demonstrate, they invite a volunteer, Sam Stokes, onto the stage to play the role of the "Network". Sam will deliver messages but might also act "evil" by copying, tampering, or dropping them.

**The PGP Workflow:**
1.  Diana generates a random symmetric key `K`.
2.  She uses a symmetric cipher (like AES) to encrypt her message and signature under `K`, creating cipher text `C`.
3.  She encrypts the key `K` itself by raising it to the power of Martin's public key (`M_pub`).
4.  She hands this to Sam (the Network), who sneakily copies the message to store in a massive data center before delivering it to Martin.
5.  Martin uses his private key (`M_priv`) to decrypt `K`, then uses `K` to decrypt the message and check the signature. 

**The Catastrophic Flaw of PGP:**
While Sam couldn't read the message in transit, cryptographer Matthew Green compares PGP to a "Museum of 1990s cryptography". The fatal flaw is that if Martin's private key (`M_priv`) is ever compromised in the future (via malware or coercion), it is a total disaster. Sam, having logged years of encrypted messages, can use that single compromised private key to retroactively decrypt every historical message. 

### **Diffie-Hellman and Ratcheting**
To solve the catastrophic failure of key compromise, cryptography requires **forward and backward secrecy**, meaning compromised keys only expose messages for a very short, isolated period. This "self-healing" property is achieved using the **Diffie-Hellman (DH)** key exchange.

**How Diffie-Hellman Works:**
1.  Using public mathematical constants `P` and `G`, Diana chooses a secret random number `X` and sends `G^X` to Martin via Sam.
2.  Martin chooses a secret random number `Y` and sends `G^Y` back to Diana. 
3.  Diana calculates `(G^Y)^X`, and Martin calculates `(G^X)^Y`. Because the operations are commutative, they both arrive at the exact same shared symmetric key `K`. Sam cannot derive `K` just from seeing `G^X` and `G^Y`.

**The Ratchet:**
Once the key `K` is established, Diana and Martin discard `X` and `Y`. For the next message, Diana generates a new `X2`, gets `K2`, and sends `G^X2`. This continuous rolling forward of keys is called a "Ratchet," forming the basis of protocols like Signal and WhatsApp.

### **Overcoming Diffie-Hellman Limitations**

**Problem 1: Asynchronous (Offline) Messaging**
Standard DH requires both parties to be online simultaneously to exchange `G^X` and `G^Y`. This fails for mobile phones that frequently disconnect.
*   **The Solution (Prekeys):** Martin can pre-calculate a massive batch of random `Y` values and their corresponding `G^Y` values, uploading them to a central server. When Diana wants to message an offline Martin, she simply downloads one of his `G^Y` values from the server, calculates `K`, and sends her `G^X` and the encrypted message. When Martin comes online, he fetches `G^X`, retrieves his saved `Y`, computes `K`, and decrypts the message.

**Problem 2: The Man-in-the-Middle (MITM) Attack**
Standard DH lacks authentication, allowing Sam to execute a MITM attack.
*   **The Attack:** Diana sends `G^X`. Sam intercepts it, generates his own secret `W`, and sends `G^W` to Martin pretending it's from Diana. Martin replies with `G^Y`. Sam intercepts it, and sends `G^W` to Diana pretending it's from Martin. 
*   **The Result:** Martin computes a key `K2` based on `W` and `Y`. Diana computes a key `K1` based on `X` and `W`. They both unknowingly share keys with Sam, not each other. Sam can now intercept Diana's messages, decrypt them with `K1`, read/tamper with them, re-encrypt them with `K2`, and pass them to Martin undetected.

### **Authentication, Deniability, and the SIGMA Protocol**
To prevent MITM attacks, the key exchange must be authenticated.

**Signatures vs. MACs:**
*   **Digital Signatures (On the Record):** As shown in PGP, these provide cryptographic, non-repudiable proof of authorship (like a contract) that anyone in the world can verify.
*   **HMACs (Off the Record / Deniable):** For informal chats, users want to know who sent a message without allowing the recipient to cryptographically prove it to a third party. A Message Authentication Code (MAC or HMAC) hashes the message using the shared secret `K`. The receiver knows the sender wrote it because only the two of them share `K`. However, the receiver cannot prove this to the outside world because the receiver themselves *could* have forged the message using their knowledge of `K` (Deniability).

**The SIGMA Protocol:**
To securely establish `K` without MITM vulnerabilities, modern systems (like OTR and IPsec VPNs) use an Authenticated Key Exchange called the **SIGMA Protocol (Sign-and-MAC)**.
1.  Diana sends `G^X`. Martin calculates `K` using his `Y`.
2.  Martin replies with `G^Y`, his public key (`M_pub`), and an HMAC containing `G^X`, `G^Y`, and `M_pub` secured under `K`. Finally, he signs this entire package with his private key (`M_priv`).
3.  Diana calculates `K`, verifies the signature, and verifies the HMAC. 
4.  She responds with her public key and a similar HMAC/signature construction.
This mutually authenticates the key exchange, guaranteeing no man-in-the-middle.

### **Public Key Infrastructure (PKI)**
Even with secure protocols, the "elephant in the room" remains: how do humans reliably exchange their massive, complex public keys?. A system is needed to bind human-friendly identifiers (emails, phone numbers) to public keys.
*   **Certificate Authorities (CAs):** Used in web TLS/SSL (e.g., Let's Encrypt) to bind domain names to public keys, or in national ID systems (like Estonia's) to identify citizens.
*   **Key Directories:** Databases used by iMessage, Signal, and WhatsApp where you query a phone number to get a public key.
*   **Manual Checking:** The PGP "Web of Trust" involving physical key-signing parties and fingerprint checking, which is highly secure but practically limited to "geeky" early adopters.

**Keeping Authorities Honest**
The fundamental flaw with CAs and Key Directories is that they require absolute trust; if Apple or a CA is hacked, an attacker can substitute public keys and bypass all E2EE protections. Solutions to keep these central authorities accountable include:
1.  **Certificate Transparency:** A Google-pushed project requiring CAs to publish a publicly checkable, append-only audit log of all issued certificates.
2.  **Social Proofs:** Used by Keybase to prove ownership of keys via social media accounts.
3.  **Gossip Protocols:** Diana's research involves using background gossiping between user devices to verify key directories, making a total system compromise much harder to execute without detection.

### **Conclusion**
Kleppmann concludes by noting that issues regarding lost private keys and seamless device recovery are massive topics that require a separate talk. He points the audience to reference material that will be tweeted with the slides, and plugs his upcoming book, *Designing Data-Intensive Applications*, offering pre-print copies to attendees at the conference.