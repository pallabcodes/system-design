# WebRTC Infrastructure Automation: Terraform & Ansible

> **Source**: [Automating WebRTC Infrastructure](https://youtu.be/As52yLuNOp8)

> [!IMPORTANT]
> **The Problem**: WebRTC has "Moving Parts" (ICE Servers, Media Servers, Signaling). Manual deployment guarantees configuration drift and failure.
> **The Solution**: Infrastructure as Code (IaC). Terraform for *Resources*, Ansible for *Configuration*.

---

## 🏗️ 1. The Automation Stack

We separate **Provisioning** (Hardware) from **Configuration** (Software).

| Tool | Role | Example Task |
| :--- | :--- | :--- |
| **Terraform** | **Provisioning** | Create EC2 `t3.large`, Open Security Group UDP 10000-60000. |
| **Ansible** | **Configuration** | Install `coturn`, Edit `turnserver.conf`, Restart Service. |
| **Packer** | **Packaging** | (Advanced) Bake `janus` into a Golden AMI so boot time is <30s. |

### Why Agentless?
The guide recommends **Ansible** because it uses SSH. You don't need to install a "Agent" on the destination server. This reduces the attack surface on your sensitive Media Servers.

---

## 🛠️ 2. Core Components to Automate

### A. The ICE Server (Coturn)
This is your most critical infrastructure. If this fails, 20% of calls drop.

*   **Terraform**:
    *   **Elastic IP (EIP)**: Mandatory. Changing the IP of a TURN server breaks existing client configs.
    *   **Security Groups**:
        *   UDP/TCP 3478 (STUN/TURN).
        *   **UDP/TCP 443 (TLS TURN)** -> *Critical for Enterprise bypass*.
        *   UDP 49152-65535 (Relay Range).
*   **Ansible**:
    *   Template `turnserver.conf`.
    *   Inject `static-auth-secret` from an Encrypted Vault (AWS Secrets Manager), **never git**.

### B. The Media Server (Janus/MediaSoup)
This is your scaling layer.

*   **Terraform**:
    *   **Auto Scaling Group (ASG)**: Define scaling policies (CPU > 60%).
    *   **Placement Groups**: Use "Cluster" placement for low-latency inter-node communication.
*   **Ansible**:
    *   Install dependencies (`libmicrohttpd`, `libnice`).
    *   Config `janus.jcfg` to bind to the **Private IP** (for security) but advertise the **Public IP** (for ICE).

---

## 🔄 3. Production Workflow: Mutable vs Immutable

### Level 1: Mutable (The "Ansible at Runtime" Pattern)
1.  Terraform launches generic Ubuntu EC2.
2.  Terraform passes `user_data` script to call Ansible.
3.  Ansible installs Janus (takes 5-10 mins).
*   **Pros**: Easy to update config (just run Ansible again).
*   **Cons**: Scaling is **slow**. New nodes take 10 mins to join the cluster.

### Level 2: Immutable (The "Golden Image" Pattern)
1.  **Packer** builds an AMI with Janus pre-installed.
2.  Terraform launches that AMI.
3.  Node is ready in 30 seconds.
*   **Pros**: Lightning fast scaling.
*   **Cons**: To update config, you must rebuild the AMI and "Roll" the cluster.

---

## 🛡️ 4. Principal Architect Checklist

1.  **Hardcode Nothing**: Do not put `turn_secret = "password"` in your `.tf` files. Use `data "aws_secretsmanager_secret"` to fetch it at runtime.
2.  **Separate State**: Keep your `network` state (VPC, Subnets) separate from your `app` state (EC2). You don't want to accidentally delete your VPC while updating a Janus config.
3.  **Tag Everything**: `CostCenter = WebRTC`. Bandwidth costs will be high; you need to know exactly which ASG caused the spill.
4.  **Use "Cluster" Strategy**: Combining Terraform + Ansible is great for Day 1. For Day 2 (Scale), move to **Packer + Terraform** (Immutable) to minimize boot times during traffic spikes.

---

## 🔗 Related Documents
*   [WebRTC Scaling](./webrtc-scaling-architecture-guide.md) — Why you need Auto Scaling Groups.
*   [NAT Traversal](./webrtc-nat-traversal-guide.md) — The detailed port requirements for Coturn.
