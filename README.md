# 🗳️ Campus Voting Platform - Cloud-Native Architecture

![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)
![Amazon SQS](https://img.shields.io/badge/Amazon_SQS-FF4F8B?style=for-the-badge&logo=amazon-sqs&logoColor=white)

A highly available, scalable, and secure microservices-based voting platform designed for university campus elections. Developed as a graduation project for the **National Telecommunication Institute (NTI)**, this system is built and provisioned entirely via Infrastructure as Code (IaC) to handle concentrated traffic spikes while optimizing cloud compute costs.

*Based on the [Docker Example Voting App](https://github.com/dockersamples/example-voting-app/tree/main).*

## 🏗️ Architecture Overview

The system is decoupled into three primary microservices (Frontend, Voting API, and Results/Worker) deployed on AWS serverless container infrastructure.

*   **Compute:** Amazon ECS on Fargate (Serverless Containers).
*   **Database:** Amazon Aurora Serverless v2 (PostgreSQL) for transactional data integrity.
*   **Queue:** Amazon SQS for rapid, decoupled vote ingestion and reliable message processing.
*   **Traffic Distribution:** Application Load Balancer (ALB).
*   **Security:** AWS WAF (Web Application Firewall) attached to the ALB.
*   **Image Management:** Amazon ECR (Elastic Container Registry).
*   **Infrastructure Provisioning:** Terraform.

## 📊 Business Case & Load Scenario

This architecture was specifically engineered and load-tested for the following campus election parameters:
*   **Target Audience:** 30,000 eligible students.
*   **Peak Traffic:** ~5,000 votes concentrated within the first hour of the election opening.
*   **Election Window:** 7 active days.

### 💰 FinOps & Cost Optimization Strategy
To minimize AWS billing while guaranteeing High Availability (HA), the infrastructure utilizes a **Scheduled Scaling** strategy:
*   **Baseline (Off-season):** System runs on a minimal footprint (1 ECS Task, 0.5 Aurora ACU) to allow historical result viewing at ~$100/month.
*   **Peak (Election Week):** ECS Tasks scale out across Availability Zones (e.g., 5 total tasks across services) and Aurora scales up (up to 2-4 ACUs) to absorb the 5,000 votes/hour spike seamlessly.
*   *Alternative implemented:* Ephemeral Teardown (Terraform `destroy`) outside of election weeks, retaining only DB Snapshots and S3 Audit Logs for a fraction of the cost.

## 🛡️ Security Implementations

*   **DDoS & Bot Protection:** AWS WAF implements Rate-Based Rules to prevent vote-flooding and malicious automated scripts.
*   **Restricted Admin Endpoint:** The `/results` endpoint is highly restricted. Depending on the environment state, it utilizes either:
    *   **AWS WAF IP Whitelisting:** Blocking all external access except for authorized university admin IP ranges.
    *   **ALB Authentication:** Delegating authentication directly to the Load Balancer before traffic reaches the Fargate containers.

## 🚀 Deployment (Terraform)

### Prerequisites
*   AWS CLI configured with appropriate IAM permissions.
*   Terraform installed (`>= v1.0.0`).
*   Docker installed for building and pushing images.

### Steps

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/3deljunior/Voting-Platform.git](https://github.com/3deljunior/Voting-Platform.git)
   cd Voting-Platform

2. **Push Images to ECR:**
   ```bash
   aws ecr get-login-password --region <your-region> | docker login --username AWS --password-stdin <your-account-id>.dkr.ecr.<your-region>.amazonaws.com
   docker build -t voting-app .
   docker tag voting-app:latest <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/voting-app:latest
   docker push <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/voting-app:latest
   ```

3. **Provision Infrastructure:**
   ```bash
   cd terraform
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

## 👨‍💻 Author

**Youssef Adel**
*   Cloud & DevOps Engineer
*   [LinkedIn](https://www.linkedin.com/in/youssef-3del/)
*   [GitHub](https://github.com/3deljunior)
