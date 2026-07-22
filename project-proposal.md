# Project Proposal: Cloud-Native Migration of TechFix

**Course:** Cloud Computing  
**Students:** Filippo Palmieri, [Partner Name]  
**Date:** May 2026

---

## 1. Problem Statement

### 1.1 The Application: TechFix

TechFix is a web application that manages post-sales technical assistance for a consumer goods company. The platform connects three types of users: technicians working at service centers across the territory, internal company staff responsible for documenting known issues, and administrators who oversee the entire system.

The core workflow is straightforward. The company sells products that occasionally develop known malfunctions. When a technician at a service center encounters a problem, they log into TechFix, find the product in the catalog, and consult the list of documented malfunctions along with their solutions. Meanwhile, company staff members are responsible for keeping this knowledge base up to date — they register new malfunctions as they are discovered and document the corresponding repair procedures. The administrator manages the organizational structure: creating user accounts, registering service centers, and deciding which staff members are responsible for which products.

The application is built as a monolithic Laravel 10 application backed by a MySQL database. It provides a public-facing catalog that anyone can browse, a technician area for consulting malfunctions and solutions, a staff area for managing the technical knowledge base, and an administrator area for user and system management. Authentication is role-based, with each role seeing only the functionality relevant to their responsibilities.

On the technical side, the application uses AJAX-powered full-text search for products and malfunctions, supports image uploads for product photos, and implements pagination across all listing views.

### 1.2 Challenges and How We Address Them

The monolithic architecture works well for a small-scale deployment, but introduces limitations when we consider a production scenario with many concurrent users. Not all of these limitations are equally critical, and we do not aim to solve all of them — our project focuses on the ones that are most relevant to the course material.

**Scalability (addressed — using Kubernetes HPA):** The application runs as a single process. If many technicians access the platform simultaneously — for example during a product recall — there is no way to add capacity to handle the spike. We address this by deploying the application on Kubernetes and configuring Horizontal Pod Autoscaling, which automatically creates additional application replicas when load increases.

**Security isolation (addressed — using Network Policies and container hardening):** In the current setup, all components run on the same server with no isolation. Any process can reach the database directly, and the application runs with full system privileges. We address this by deploying each component as a separate container with restricted permissions, and by using Kubernetes Network Policies to control which components can communicate with each other.

**Infrastructure provisioning (addressed — using OpenNebula):** The current deployment is tied to a single fixed server. We address this by using OpenNebula to provision the virtual machines that host our Kubernetes cluster, demonstrating how IaaS can provide the compute layer for a container orchestration platform.

**Manual deployment (partially addressed):** Updates currently require manual server access. By containerizing the application, we make deployments reproducible and version-controlled through Docker images, even without a full CI/CD pipeline.

**Single point of failure (not directly addressed):** The current setup has no redundancy. While Kubernetes provides pod-level restart capabilities, we do not implement full high-availability or database replication in this project, though we discuss how it could be achieved.

### 1.3 Project Goal

The goal is to take an existing, functional monolithic web application and deploy it on a cloud-native stack that combines OpenNebula (IaaS) with Docker and Kubernetes (PaaS), demonstrating horizontal scaling and security hardening in a realistic scenario.

---

## 2. Proposed Solution

### 2.1 Architecture Overview

The system is organized in two layers. The bottom layer is OpenNebula, which provides the virtual machines. The top layer is Kubernetes, which runs inside those VMs and manages the application containers.

We provision two or more Ubuntu virtual machines through OpenNebula: one serves as the Kubernetes control plane, and the others serve as worker nodes where the application containers actually run. A separate VM is dedicated to the MySQL database, which runs directly on the virtual machine rather than inside Kubernetes. These VMs are connected through a virtual network managed by OpenNebula.

Inside the Kubernetes cluster, the application is split into two containerized services: the Laravel application itself (handling all the business logic) and an Nginx web server (receiving user requests and forwarding them to Laravel). The MySQL database lives outside the cluster on its own dedicated VM, and the Laravel containers connect to it over the OpenNebula virtual network. An Ingress resource defines how external traffic reaches the application from outside the cluster.

### 2.2 How Services Are Deployed

The Laravel application is packaged into a Docker image. The build process uses two stages: the first stage installs all PHP dependencies using Composer, and the second stage copies only the application code and the installed dependencies into a minimal PHP-FPM image. This keeps the final image small and free of build tools. The resulting container runs PHP-FPM, which is a process manager that handles incoming PHP requests.

Nginx runs in a separate container. Its job is to accept HTTP connections from users, serve static files directly (stylesheets, JavaScript, product images), and forward dynamic requests to the Laravel container. In Kubernetes, these two containers are deployed together and can communicate over the internal cluster network.

MySQL runs on a dedicated OpenNebula VM, separate from the Kubernetes cluster. We chose this approach because relational databases like MySQL are not well suited to run inside Kubernetes StatefulSets — they need stable storage, predictable performance, and careful handling of writes that container orchestration can complicate. By running MySQL directly on a VM, we get a simpler and more reliable setup: the database has its own dedicated resources, its data lives on the VM's disk without abstraction layers, and backups can be managed with standard tools. The Laravel containers inside Kubernetes connect to this VM over the OpenNebula virtual network using a Kubernetes ExternalService or direct IP configuration.

Finally, we configure a Kubernetes Ingress resource that acts as the entry point for all external traffic. It receives HTTP requests from users' browsers and routes them to the Nginx service inside the cluster.

The key point is that the application services run as containers orchestrated by Kubernetes, while the database runs on a dedicated VM managed by OpenNebula. This separation reflects a real-world best practice — stateless application logic belongs in containers where it can scale easily, while stateful services like databases benefit from the stability of a dedicated machine. It also demonstrates a more nuanced use of OpenNebula: not just as a host for the Kubernetes nodes, but as infrastructure that serves different roles depending on the workload requirements.

### 2.3 Scaling Strategy

We use Kubernetes Horizontal Pod Autoscaling to handle load spikes on the application layer.

The idea is simple: we define a CPU utilization target for the Laravel containers (for example, 70%). Kubernetes continuously monitors the actual CPU usage. When it exceeds the target — meaning the application is under heavy load — Kubernetes automatically creates additional copies of the Laravel container to distribute the work. When the load decreases, it removes the extra copies to free resources.

The use case we target is a product recall scenario. When a recall is announced, many technicians across the territory simultaneously access TechFix to look up the affected product, check its malfunction list, and read the repair solutions. This creates a sudden spike in requests to the catalog and malfunction pages. Without autoscaling, the single application instance would become slow or unresponsive. With HPA, Kubernetes reacts to the increased load within seconds and brings up additional replicas to keep response times acceptable.

During the live demo, we will simulate this scenario using a load generation tool that sends many concurrent requests to the application, and we will show the number of running pods increasing in real time as the load grows.

### 2.4 Security Features

We implement two security measures that address the lack of isolation in the original monolithic deployment.

The first is network-level isolation using Kubernetes Network Policies. By default, any container in a Kubernetes cluster can communicate with any other container — which is essentially the same problem we had on the monolithic server. We define policies that restrict this:

- The MySQL database, running on its dedicated VM, only accepts connections from the Kubernetes cluster's network range (specifically from the Laravel pods). No other machine or service can reach it.
- The Laravel containers only accept traffic from Nginx. They are not directly exposed to the outside world.
- The database VM's firewall is configured to block all outbound internet connections, reducing the risk of data exfiltration.

This means that even if an attacker manages to compromise one container, they cannot easily move laterally to the database or other parts of the system. The database being on a separate VM adds an additional layer of isolation — it is not even in the same network namespace as the application containers.

The second measure is container hardening. We configure all containers to run with the minimum privileges necessary:

- All containers run as a non-root user. This means that even if an attacker exploits a vulnerability in the application, they cannot gain root access to the underlying system.
- The container filesystems are mounted as read-only. The application can only write to specific directories that genuinely need it (Laravel's cache and log directories). This prevents an attacker from modifying application code or planting malicious files.
- We drop all Linux capabilities by default and only grant back the specific ones that are strictly needed. For example, Nginx needs the ability to bind to port 80, but it does not need the ability to modify system settings or load kernel modules.

These restrictions are configured through Kubernetes security settings at the container level, and they represent a significant improvement over the original deployment where the application ran with full server privileges.
