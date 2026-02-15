Resource: https://youtu.be/l2PYEn9vUy0?list=TLGGI3Cu1epZ51cwODAyMjAyNg
 
Based on the transcript of the video "Boost Java Application Efficiency and Slash Costs with GraalVM and Spring AOT" by Tanasin Vivitvorn, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Personal Context**
Tanasin Vivitvorn introduces himself as a software engineer from Thailand, Southeast Asia, currently 44 years old. He shares the personal context of his visit: he joined a company called CYC last year, and shortly after, his mother passed away. He is currently in the area to pick up his mother's ashes from a medical center to return them to Thailand. He arranged this talk with Danny during his free time to share his knowledge.

### **Background and Java History**
Tanasin has worked in the software field for 22 years, starting with Java 2. He recalls that initially, Java had poor performance compared to languages like PHP and was often blamed for garbage collector issues. He became interested in GraalVM because he views it as a "new era" for Java programming.

### **JVM Architecture: JIT vs. AOT**
He explains the architecture of the JVM (Java Virtual Machine) prior to Java 17 and introduces the core concepts of compilation:

*   **JIT (Just-In-Time) Compiler:**
    *   **Concept:** JIT does not compile all code at once. It compiles only the code that is used or initialized at that specific time.
    *   **Mechanism:** It uses a profiler during runtime to check which code needs execution next.
    *   **Pros/Cons:** It allows for dynamic optimization but has slower startup times because it compiles code during the startup phase.

*   **AOT (Ahead-Of-Time) Compiler:**
    *   **Concept:** AOT compiles all code beforehand, placing the code into the text area of the program and the heap into the data section.
    *   **Startup:** AOT offers significantly faster startup times because everything is pre-compiled. Tanasin contrasts this with traditional JVM startup which can take a long time to build and compile.
    *   **Memory Usage:** AOT handles memory better. Traditional Java might consume sufficient memory to start but acquire more during runtime, potentially leading to Out-Of-Memory exceptions. AOT calculates and allocates memory and CPU requirements at the start.
    *   **Optimization:** AOT uses fixed optimization (done at build time), whereas JIT can customize optimization dynamically during runtime.
    *   **Size:** AOT executables are generally larger than JIT applications. JIT only selects the code needed for execution, whereas AOT must compile and include every library and component required into the final application.
    *   **Portability:** JIT is highly portable because it runs on the Virtual Machine; you can distribute classes to any machine with a VM. AOT must be compiled to fit a specific Operating System (OS). However, GraalVM currently supports Mac, Windows, and Linux.

### **GraalVM and Polyglot Capabilities**
Tanasin explains that GraalVM is not just for Java. It supports multiple languages including JavaScript, Ruby, Python, and C.
*   **Truffle Language:** GraalVM uses the Truffle framework to compile these programs into abstract code.
*   **Interoperability:** This allows developers to write a program in Java but call libraries in Python. He gives the example of using Python's extensive machine learning or mathematics libraries directly within a Java application via the JVM API.

### **GraalVM Architecture**
The build process involves taking the Application Library, JDK, and **Substrate VM**.
*   It performs **Pointer Analysis**.
*   It separates code into a **Text Section** (filtered code used for the app) and **Data Memory** (stored in the data section).
*   These are combined to create a standalone application executable.

### **Spring Native and Spring Boot 3**
Tanasin clarifies the relationship between Spring Native and GraalVM. Spring Native was an initiative to combine the VM with the framework, but now, **GraalVM support is natively represented in Spring Boot version 3**.
*   **Application Size:** He notes that while a simple "Hello World" might be kilobytes, a Spring Boot application is typically around 40-60 MB because it bundles the entire Spring framework.

### **Cloud Efficiency**
Using GraalVM/Spring AOT is particularly beneficial for Cloud environments:
*   **Resource Usage:** Traditional Java libraries consume a lot of resources in the cloud. GraalVM runs fast and uses low resources.
*   **Predictability:** Because memory and size are calculated at the start, it helps prevent unexpected Out-Of-Memory exceptions common in cloud deployments.
*   **Packaging:** It allows for specific cloud-native packaging that fits the application needs.

### **Performance Data and Trade-offs**
*   **Memory Consumption:** Tanasin presents data comparing JDK 11 and GraalVM. Running multiple processes (1 to 4) on JDK 11 consumes significantly more resources—more than four times the single-process usage. GraalVM maintains much lower and more stable memory usage.
*   **Build Time (The Disadvantage):** GraalVM takes longer to build.
    *   On a machine with 2 vCPUs and 4GB RAM, building a Spring application (with Actuator, Logging, JPA/Database communication) can take around **10 minutes**.
    *   On modern laptops (8-16 vCPUs, 16-32GB RAM), this time is reduced to **2.5 to 6 minutes**, which he considers acceptable.

### **Demonstration: "Tawx" Application**
Tanasin demonstrates a practical application named "Tawx" that he built using Java and GraalVM.
*   **Architecture:** The application is a Java Swing-based frontend compiled into a Windows `.exe` file using GraalVM.
*   **Visibility:** He notes that usually, Java apps show up as `java` in the task manager. His app shows up as `tawx.exe`.
*   **Functionality:** The application is a screen-sharing agent.
    *   **Server:** A personal server with a frontend developed in React.
    *   **Client Agent:** The Java/GraalVM application captures the screen as images and sends them to the server via **WebSocket**.
    *   **Reasoning:** He chose this method over WebRTC or RTMP because the requirement was to monitor a client machine real-time *without* requiring the user to grant permission or receive a warning, which WebRTC would require.

### **Conclusion**
Tanasin concludes by promising to share the code for the demo later, as it is not yet on his GitHub. He apologizes for his nervousness and English. He ends the presentation with a picture of his mother, mentioning that he picked up her ashes from the duty souvenirs yesterday and asks for prayers for her to rest in heaven.