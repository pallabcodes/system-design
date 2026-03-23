Based on the transcript of the video presentation "Web Scale SSO" by Justin Minich at DevConf, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Problem Statement**
Justin Minich, representing Red Hat IT, introduces the topic of how his team manages Red Hat's Single Sign-On (SSO) servers. These servers are critical for users logging into `access.redhat.com`, filing cases, downloading software, and accessing other Red Hat websites.
*   **The Stakes:** SSO is vital. If it goes down, Red Hat cannot process transactions ("take your money") or run numerous applications, leading to significant backlash against the IT team.

### **Why Open Source?**
Red Hat prioritizes using open source software for financial, philosophical, and practical reasons.
*   **Flexibility:** Open source allows for custom implementations to meet specific business requirements. For example, legal requirements might dictate that software cannot be sold to specific countries, which must be enforced during the login flow.
*   **Data Usage and Integration:** Running their own open source stack allows them to link SSO data with other internal data for data mining. If a user frequently looks at "OpenShift," the login flow could be customized to direct them to an OpenShift page with a discount on their next login. This level of customization and per-user modification is not typically available with proprietary software or SaaS SSO providers.

### **Hybrid Cloud Strategy**
Red Hat focuses on hybrid cloud deployment to prevent vendor lock-in.
*   **Vendor Independence:** Just as people worried about Microsoft writing their own standards, similar concerns exist regarding Amazon (AWS). Therefore, Red Hat runs SSO both on-site in their data centers and across other cloud vendors.
*   **"Clumsy Kyle" Prevention:** Minich notes that human error is inevitable—whether it is an internal employee ("Clumsy Kyle" or a "cowboy admin") or a cloud vendor making a mistake. Even expensive services like Azure or AWS experience outages due to human error. Hosting systems in multiple places mitigates this risk.
*   **Competitive Risk:** Hosting data with a cloud provider who might eventually become a direct competitor poses a business risk (e.g., price hikes or direct product competition). Red Hat spreads their setup to avoid this vulnerability,.

### **Infrastructure Architecture**
Minich details the specific infrastructure used to run the SSO system:
*   **Three Sites:** The system runs across three different sites.
*   **Global Load Balancing:** Requests are routed to the closest geographical site.
*   **Local Load Balancers:** Each site has its own load balancer.
*   **Components per Site:**
    *   **RH-SSO:** Four "beefy" Virtual Machines (VMs) running Red Hat Single Sign-On (the productized version of the upstream project Keycloak).
    *   **JDG (JBoss Data Grid):** Used for caching, downstream from Infinispan.
    *   **MariaDB:** Stores data, utilizing **Galera** for replication.
*   **Replication:** JDG shares information between sites, and Galera shares database information between sites.
*   **Performance:** The system sustains about 1 million unique logins daily and successfully handled a full data center outage where users could still log in (even if other Red Hat services failed).
*   **Management:** **Ansible** is used for release management and infrastructure provisioning (standing up VMs/instances in Red Hat Virtualization, OpenStack, or AWS).

### **Software Features and Customization**
*   **RH-SSO / Keycloak:** Described as stable, flexible, multi-tenant, and capable of federation. It supports standard protocols (SAML, OIDC, OAuth), Kerberos/LDAP federation, and social logins. It is manageable via GUI or REST API,.
*   **Brokered Logins:** Red Hat is exploring allowing cloud vendors (like Azure) to talk to their Identity Providers (IDPs). This allows customers running VMs in Azure to seamlessly access the Red Hat support portal without rigorous re-registration,.
*   **Custom SPIs:** Because Keycloak is flexible, Red Hat writes custom Service Provider Interfaces (SPIs). They pull user data from **MongoDB** (rather than standard LDAP/Kerberos) and make REST API calls to internal services for legal checks and user/group information.

### **Core Technologies Deep Dive**
*   **Infinispan / JBoss Data Grid (JDG):** A distributed in-memory key-value store (similar to Redis or Memcached). Red Hat configures it in a replicated manner so all sites have the same data. It stores **runtime information** (user sessions, offline tokens), allowing users to "hop" between data centers without re-authenticating. If a user loses a sticky session or a data center fails, they remain logged in at the new site,.
*   **MariaDB & Galera:** MariaDB stores Keycloak configuration (client integrations for SAML/OIDC) and caches some user info.
    *   **Synchronous Replication:** Galera is used for synchronous replication to prevent race conditions.
    *   **Race Condition Example:** Red Hat has valid use cases where a single account logs into two different data centers within the same second (often automated systems). Without synchronous replication, this caused conflicts.
    *   **OIDC Authorization Code Flow Issue:** In some cases, a client would get a code from Data Center 1 (DC1), hand it to a backend server, and the backend server would immediately try to swap that code for a token at Data Center 2 (DC2). If utilizing standard asynchronous replication, DC2 would not yet know about the code, causing a failure. Synchronous replication solved this.

### **Custom "Special Sauce"**
Red Hat has extended the core products with:
*   **User Federation Backends:** Custom queries to MongoDB and legal check systems.
*   **Flow Customization:** Different user classes see different login/registration flows (e.g., different legal terms).
*   **Docker Auth:** They implemented support for Docker authentication, allowing authenticated container downloads from the Red Hat container catalog to run through the SSO servers,.

### **Future Plans and Considerations**
Minich outlines what the team is considering for the future:
*   **Scaling Strategy:** They are debating horizontal vs. vertical scaling. Currently, they use large VMs (8 cores, 8GB memory) which sometimes get taxed by unoptimized custom code. They are considering moving back to containers (e.g., many small containers vs. fewer large VMs).
*   **Auto-scaling:** They want to improve auto-scaling, which is currently a manual process triggered when high load is noticed.
*   **Site Distribution:** They are questioning if "cheaper and more diverse" is better. Instead of highly available clusters in specific availability zones (AZs), they might prefer single servers in many different regions to serve users locally,.
*   **Deployment Techniques:** They want to implement Blue/Green or Canary deployments (e.g., sending 10% of traffic to a new feature in AWS US-East only) to test features safely.
*   **Chaos Monkey:** As they run active-active-active, troubleshooting is difficult. Logs are spread across data centers and providers with different hardware profiles (AWS t2.large vs Azure instances). They need better centralized logging (Splunk) and performance profiling to manage this complexity.
*   **Cloud Data Enrichment:** They plan to query SaaS vendors for user data during login to enrich SAML assertions or OIDC tokens.
*   **Site Management Automation:** Currently, managing the global load balancer involves a difficult web interface or contacting professional services. They want to script these actions (e.g., a script to "bring down Data Center 2").

### **Q&A Session**
*   **Geographic Distribution:** Currently, the distribution is poor. Sites are in US East and potentially US West, but all are within the United States.
*   **User Data Storage:** User credentials (usernames, passwords) are stored in a MongoDB database, accessed via a custom Keycloak SPI. This MongoDB is geo-replicated,.
*   **GDPR:** The US-only hosting is due to "poor planning," not GDPR concerns.
*   **Software Version:** They are running RH-SSO version 7.2 in production.
*   **Issues:** They faced bugs and challenges implementing the active-active-active hybrid cloud setup with Galera and JDG, as product support for this specific configuration was still growing at the time. They worked closely with engineering to resolve these.
*   **Concurrent Login Use Case:** The scenario where an account logs into multiple data centers simultaneously involves automation tests and a specific vendor that resells Red Hat subscriptions via on-site appliances. This vendor scrapes the Red Hat login page and enters credentials across all their deployed devices simultaneously.
*   **Resourcing/Staffing:** Running this infrastructure requires significant effort. Red Hat has over 120-130 SSO integrations.
    *   **SaaS Vendor Challenges:** Integrating with SaaS vendors is time-consuming (sometimes 6 months) because vendors often write custom SAML libraries instead of using standard ones, leading to broken implementations.
    *   **Complexity:** Minich describes JDG/Keycloak clustering as "black magic," requiring specialized knowledge, whereas MariaDB is considered "easy stuff",,.