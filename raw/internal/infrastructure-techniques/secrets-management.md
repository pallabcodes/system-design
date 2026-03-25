Resource: https://youtu.be/I_l7OTBgk3Y?list=TLGG7bYH1I1Jb_8xNTAyMjAyNg

Based on the video transcript, here is an accurate and comprehensive extraction of the presentation "Our Journey Into Secrets Management With Vault," presented by Nevin from TomTom.

### **Introduction and Background**
Nevin introduces himself as a Senior Application Engineer and YAML programmer at TomTom, leading the secret management team. He outlines his career path from a Linux system administrator to cloud operations, security, and finally DevSecOps.

He briefly describes TomTom as a map-making company providing geolocation technology for drivers, carmakers, enterprises, and developers, enabling smart mobility globally.

### **The Story of the Spider (A Lesson in Physical Security)**
Nevin begins with a personal story about managing credentials early in his career. To conquer a fear of spiders, he bought a Brazilian black tarantula and a terrarium. Working as a sysadmin with access to company keys and passwords, he decided to secure them physically.
*   **The Method:** He stored the keys on a USB flash drive, placed it in a plastic zip bag, and hid it inside the tarantula’s terrarium.
*   **The Problem:** While he successfully recovered the keys a few times, the process was inefficient. Every time he needed a credential, he had to open the terrarium, fight his fear and the spider, retrieve the drive, extract the keys, and then reverse the process. He realized this was not an optimal solution.

### **The Evolution of Secret Management**
Nevin outlines the history of managing application credentials:
1.  **Connection Strings:** In the past, with single servers and databases, connection strings were the only place passwords lived.
2.  **Sharing Methods:** As teams grew, sharing became necessary. This evolved from email to Slack, to "password sharing platforms" (text files on shared drives or document management systems), and finally to hardcoded passwords in Git repositories.
3.  **Modern Complexity:** Applications now run as microservices with multiple instances communicating with redundant databases and various frontends/backends. Hardcoded credentials and messy environment variables became unsustainable, necessitating a dedicated secret management solution.

### **TomTom’s Requirements for a Solution**
TomTom gathered requirements from various internal teams:
*   **Audit Team:** Required a single source of truth with audit logs to track who used a password, when, and how.
*   **Developers:** Required programmatic access via an API.
*   **Security Team:** Required secrets to be transmitted securely and encrypted at rest.
*   **S3/Infrastructure Team:** Required a highly available solution running in multiple regions, supporting Infrastructure as Code (IaC).
*   **General:** Required multiple authentication methods (for redundancy) and secret versioning to assist teams that change passwords outside of CI/CD pipelines.

### **The Implementation Timeline**
TomTom chose HashiCorp Vault. Nevin details the lengthy timeline to make it a company standard:
*   **October 2017:** The need for a solution was identified, and Vault Open Source was recommended.
*   **1.5 Years Later:** First Proof of Concept (PoC) running Vault Open Source on a small virtual machine in OpenStack.
*   **2019:** A Kuberentes-focused PoC using the HashiCorp Helm chart.
*   **March 2020:** First Enterprise PoC focusing on exploring modules.
*   **Subsequent PoC:** Focused on comparing Vault Enterprise with other solutions, highlighting Disaster Recovery (DR) and Namespaces as key features.
*   **Documentation Phase:** Extensive writing on architecture and integration, followed by reviews from SRE, Cloud Center of Excellence, and Security teams.
*   **MVP Phase:** Minimum Viable Product with a few "power user" teams providing feedback.
*   **Limited Availability (LA):** Introduced to more teams using basic features like KV store and Namespaces.
*   **Standardization:** Vault was finally signed as the developer productivity standard for secret management.
*   **April (Current Year):** They replaced Consul with Raft storage to simplify the backup restoration process.

### **Developer Experience and Onboarding**
Nevin defines developer experience as essentially "user experience." To streamline adoption, they focused on automation and onboarding.
*   **The Onboarding Process:** Users provide only two pieces of information via a self-service portal: the desired Namespace name and their Active Directory group.
*   **Automation:** A backend pipeline runs Terraform to connect to Vault, configure the namespace and policies, provide admin access to the requested team, and email them guidelines.

### **Challenges and Solutions**
Nevin highlights specific hurdles they faced during adoption:

1.  **Adoption ("Field of Dreams" fallacy):** Just building the solution didn't mean users showed up.
    *   *Solution:* They held monthly stakeholder meetings to showcase use cases and new features, leading to a rise in users.
2.  **Resistance to Change:** Developers disliked rewriting code or migrating from existing solutions (third-party, cloud-native, or homegrown).
    *   *Solution:* They introduced "onboarding calls" with every team to explain how to use Vault in their specific programming languages and push best practices before they started using the system.
3.  **Documentation:** Users typically only read documentation when they encounter problems.
    *   *Solution:* Instead of duplicating official docs, they focused on FAQs, specific TomTom use cases, and provided Terraform samples for managing namespaces.

### **Kubernetes Integration**
To move away from encoded (but unencrypted) static Kubernetes secrets, TomTom created a workflow to integrate K8s with Vault:
1.  **Workflow:** Starts in a GitHub repository containing a Kubernetes reference architecture template.
2.  **Deployment:** An Azure DevOps pipeline uses Terraform to deploy resources from GitHub to Azure Cloud.
3.  **Configuration:** Terraform deploys Kubernetes and the Container Storage Interface (CSI) provider or Vault Agent.
4.  **Auth Setup:** Terraform retrieves the JWT token, host, and certificate from Kubernetes and uses them to configure the Kubernetes Auth Method in Vault for the respective namespace.
5.  **Result:** The cluster and application are ready to consume secrets immediately upon deployment.

### **Monitoring and Telemetry**
TomTom uses Prometheus, Alertmanager, and Grafana to monitor Vault telemetry. Nevin recommends tracking specific metrics:
*   **Inactive/Unused Tokens:** High numbers indicate misconfigurations (e.g., in Auth methods).
*   **Duration of Requests:** Indicates user experience and potential backend/network issues.
*   **Seal Status:** The most critical alert; if Vault is sealed, it is unusable.
*   **Resource Quota Violations:** Helps track potential abuse or misconfiguration by teams using namespaces.

### **Custom Tools Developed**
TomTom built internal tools to improve the user experience:
1.  **Policy Generator:** A Python-based tool that generates HashiCorp Vault policies (in HCL format) from a list of permissions provided by the user. It also checks for bad practices, such as using default permissions or "sudo".
2.  **Secret Expiry Monitor:** Because secrets (like Azure Service Principals) expire, they needed a tracking solution. They built a Prometheus exporter that uses an AppRole to check secret metadata for expiration dates. This allows them to visualize expiry in Grafana dashboards.
    *   *Open Source:* This tool was open-sourced as `vault-assessment-prometheus-exporter` on GitHub. Nevin announced the release of version 1.0 during the talk.

### **Key Takeaways**
Nevin concludes with the following advice:
*   **Necessity:** Secret management is a must for any company with credentials.
*   **Expectations:** Manage user expectations and be prepared to provide help and best practices.
*   **Tooling:** Create tools to assist users in overcoming issues.
*   **Data-Driven:** Monitor everything from user adoption to secret engine usage.
*   **Networking:** Connect with other companies using Vault Enterprise to learn from their mistakes and solutions.
*   **Open Source:** He encourages checking out their open-source Prometheus exporter.


Q: What are the secret benefits of vault namespaces and namespaces?

Q: How does the vault policy generator prevent bad security practices?

Q: Tell me more about the open source Prometheus exporter tool.