# 🛡️ Secure Migration of MiniLibrary to AWS (Cloud Security)

**CCS6344 Database & Cloud Security | Assignment 2 | Group 28**

This repository contains the complete Infrastructure as Code (IaC), migrated codebase, and security validation suites for migrating the monolithic on-premises MiniLibrary Book Reservation System to a secure, resilient, dual-stack cloud architecture on Amazon Web Services (AWS).

---

## 🏗️ Core Architecture Overview

The system is deployed within a custom VPC in the `us-east-1` region using a strict **Defense-in-Depth** multi-tier topology:

- **Perimeter Layer:** Dual-stack Application Load Balancer (ALB) acting as the single public exposure endpoint, receiving incoming IPv4/IPv6 transit traffic over Ports 80 and 443.
- **Compute Tier:** Amazon EC2 instance (`t3.micro` running Amazon Linux 2023) hosted behind a secure Nginx reverse proxy handler with TLS termination.
- **Database Tier:** Isolated Amazon RDS MySQL 8.0 instance running on private, non-publicly-accessible subnets.
- **Storage Protection:** Default AES-256 server-side encryption across RDS volumes, S3 chronographical data repositories, and root compute blocks.
- **Active Validation & DevSecOps:** Integrated automated CI/CD security pipelines using Bandit SAST, Safety dependency validation, and cfn-lint/Checkov IaC configuration scans.

---

## 📁 Repository Structure

```
minilib-aws/
├── app.py                        # Migrated Flask App (PyMySQL database driver & Fernet Crypto)
├── requirements.txt              # Core application dependency libraries
├── README.md                     # Project landing documentation (This file)
├── cloudformation/
│   └── main.yaml                 # Complete declarative Infrastructure as Code (IaC) template
├── db/
│   ├── schema.sql                # Converted MySQL 8.0 database schema, stored procedures, & RBAC
│   └── seed.sql                  # Cryptographically pre-hashed database test seed values
├── docker/
│   └── Dockerfile                # Containerized runtime image configuration rules (Bonus)
├── scripts/
│   └── backup_to_s3.py           # Cron backup synchronization routine uploading to S3
└── .github/
    └── workflows/
        └── devsecops.yml         # 4-Stage automated continuous security testing pipeline (Bonus)
```

---

## 🛑 AWS Academy Sandbox Environment Constraints

To guarantee successful deployment within the ephemeral AWS Academy Sandbox profile, the infrastructure has been strictly optimized around the following platform limitations:

1. **IAM Restrictions:** Direct custom IAM policy/role creation is blocked. The environment maps all computing assets onto the pre-existing `LabRole` and `LabInstanceProfile`.
2. **RDS Restrictions:** High-availability Multi-AZ deployment rules and Enhanced Monitoring modules are disabled to avoid provisioning errors.
3. **WAF Restrictions:** AWS WAF is locked out in this tier. Protection against brute-force and application DDoS threats is compensated via application-level rate limiting through Flask-Limiter.
4. **Network Lifecycle:** All assets are entirely destroyed when the lab session hits 0:00. The architecture is fully automated via CloudFormation to enable a complete system rebuild under 10 minutes.

---

## 🚀 Step-by-Step Execution Guide

### Step 1: Pre-Deployment Repository Configuration

1. Ensure your personal fork of this repository is set to **Public** visibility so the EC2 boot sequences can run standard `git clone` commands.
2. Open `cloudformation/main.yaml`, navigate to the `UserData` block, and replace the clone fallback endpoint target with your actual public repository path:

```bash
git clone https://github.com/YOUR_USERNAME/minilib-aws.git .
```

---

### Step 2: Provisioning CloudFormation Infrastructure

1. Log into the AWS Academy Console and select **Start Lab**. Once active, open the console interface ensuring your active region target is set to **N. Virginia (us-east-1)**.
2. Navigate to **CloudFormation → Create stack (with new resources) → Upload a template file**, and choose `cloudformation/main.yaml`.
3. Apply stack name `minilib-stack` and fill in the parameters:

| Parameter | Value |
|---|---|
| `DBUsername` | `admin` |
| `DBPassword` | `MiniLibAWS2026!` *(Do not use `@` symbols or spaces)* |
| `FlaskSecretKey` | `mmu-ccs6344-g28-flask-secret-2026` |
| `ICEncryptionKey` | `MiniLibICKey2026ForFernetAES256!!` |
| `KeyPairName` | `vockey` |
| `YourIP` | Your public IP in CIDR notation (e.g. `103.x.x.x/32`) or `0.0.0.0/0` |

4. Proceed through the creation wizard, acknowledge the IAM capabilities checkbox, and hit **Submit**. Allow approximately **10 minutes** for full asset creation until the stack reads `CREATE_COMPLETE`.

---

### Step 3: Server Handshake via CloudShell

1. Open CloudShell by clicking the terminal icon (`>_`) in the top global navigation bar.
2. Query and save your newly deployed EC2 host public IP address profile using the integrated stack lookup wrapper:

```bash
EC2IP=$(aws cloudformation describe-stacks --stack-name minilib-stack \
  --query "Stacks[0].Outputs[?OutputKey=='EC2PublicIP'].OutputValue" \
  --output text) && echo $EC2IP
```

3. Download your session key pair (`labsuser.pem`) from the Academy Details Panel and upload the file into your CloudShell home directory space via **Actions → Upload file**.
4. Set strict read-only profile permissions on the key and SSH directly into the instance node:

```bash
chmod 400 ~/labsuser.pem
ssh -i ~/labsuser.pem ec2-user@$EC2IP
```

---

### Step 4: Verification of Compute Environment

Once connected inside the EC2 terminal session, run these health assessments to ensure setup scripts executed correctly:

```bash
# Confirm user-data logic finalized without error exceptions
tail -20 /var/log/user-data.log

# Verify repo assets pulled successfully into deployment space
ls /opt/minilib/

# Validate local engine state status
curl http://localhost:5000/health
sudo systemctl status nginx
```

---

### Step 5: Relational Database Initialization

Because the backend database instance resides on secure private subnets, initialization scripts must execute directly from your proxying EC2 workspace connection session:

1. Install the localized database client engine and fetch the infrastructure endpoint address:

```bash
sudo dnf install -y mariadb105
RDS=$(aws cloudformation describe-stacks --stack-name minilib-stack \
  --query "Stacks[0].Outputs[?OutputKey=='RDSEndpoint'].OutputValue" \
  --output text) && echo $RDS
```

2. Apply the core system relational schema definitions, security procedures, and role definitions:

```bash
mysql -h $RDS -u admin -p'MiniLibAWS2026!' MiniLibraryDB < /opt/minilib/db/schema.sql
```

3. Inject the production seed profiles, cryptographically pre-hashed passwords, and user records:

```bash
mysql -h $RDS -u admin -p'MiniLibAWS2026!' MiniLibraryDB < /opt/minilib/db/seed.sql
```

4. Validate that all 4 component tables, 7 base records, and 16 backend procedural packages loaded properly:

```bash
mysql -h $RDS -u admin -p'MiniLibAWS2026!' MiniLibraryDB -e \
  "SHOW TABLES; SELECT COUNT(*) AS Books FROM Books; SHOW PROCEDURE STATUS WHERE Db='MiniLibraryDB';"
```

---

### Step 6: Perimeter Load Balancer Route Registration

1. Head back to the global AWS Management Web Console dashboard and open **EC2 → Target Groups**.
2. Click into `minilib-ec2-tg` and select **Register targets**.
3. Choose your running compute instance node, set the target redirection port to `80`, click **Include as pending below**, and finalize by hitting **Register pending targets**. Within roughly a minute, refresh the view to confirm that the health status reads **healthy**.

---

## 👥 Accessing the Live Application

Extract the public routing domain of the Application Load Balancer via the terminal wrapper:

```bash
aws cloudformation describe-stacks --stack-name minilib-stack \
  --query "Stacks[0].Outputs[?OutputKey=='ALBDNSName'].OutputValue" \
  --output text
```

Paste the resulting URL string output directly into your browser tab. The Nginx reverse proxy will automatically handle an internal upgrade redirect from HTTP:80 over to HTTPS:443. Since Route 53 domain verification checks are constrained within student labs, bypass the browser self-signed SSL warning certificate prompt (**Click Advanced → Proceed**) to open the secure landing page.

### Test Seed Accounts

> **All passwords:** `Test@1234`

| Role | Username | Access Level |
|---|---|---|
| Librarian | `admin` | Complete operational dashboard, full audit event tracking logs, and textbook listing inventory controls |
| Member | `ali.hassan` | Enforces Row-Level Security — can only query personal checkout and booking rows |
| Member | `nur.aina` | Verifies data isolation — cross-account rows are completely invisible |

---

## 🎁 Bonus Configurations Evidence Checklist

### 1. Application Containerization (Docker Implementation)

To demonstrate container isolation mechanisms within sandbox constraints, the web service tier can run completely inside an isolated Docker image wrapper directly on the host machine:

```bash
# Connect to EC2 and install the background execution engine
sudo dnf install -y docker
sudo systemctl start docker && sudo systemctl enable docker
sudo usermod -aG docker ec2-user && newgrp docker

# Kill the standard background Flask script execution process loop
sudo pkill -f 'python3 /opt/minilib/app.py' || true

# Assemble the container environment configuration profiles
cd /opt/minilib
sudo docker build -t minilib:latest -f docker/Dockerfile .
grep "export " /opt/minilib/.env | sed 's/^[[:space:]]*export //' | sed 's/"//g' > ~/docker_clean.env

# Launch the secure isolated container instance worker
sudo docker run -d --name minilib --env-file ~/docker_clean.env -p 5000:5000 --restart unless-stopped minilib:latest

# Check local containment health state
sudo docker ps
curl http://localhost:5000/health
```

---

### 2. IPv6 Dual-Stack Network Auditing

The underlying CloudFormation template automatically provisions a fully integrated dual-stack architecture backed by an Amazon-allocated `/56` routing block. Verify network interface cryptographic token attachments via:

```bash
# Check globally-routable inet6 addresses (Ignore link-local fe80:: scopes)
ip addr show | grep 'inet6 '

# Audit external outbound IPv6 handshake connectivity vectors
curl -6 -s https://api64.ipify.org && echo
ping6 -c 3 ipv6.google.com
```

---

### 3. Continuous Integration DevSecOps Automation Suite

Your pipeline workflow file (`.github/workflows/devsecops.yml`) runs an automatic security scanning layout on every code push event targeting the `master` core development stream. The validation sequences handle the following scanning modules:

1. **Bandit Stage:** Scans Python code for injection bugs and insecure configuration structures.
2. **Safety Stage:** Cross-references library files (`requirements.txt`) against CVE exploit tracking indexes.
3. **IaC Lint & Checkov Stage:** Audits CloudFormation configuration rules to prevent open perimeters or unencrypted blocks.
4. **Automated Deploy Stage:** Authenticates over SSH to rebuild and deploy the latest codebase updates.

#### Required GitHub Secrets Mappings

To enable continuous operations, add the following parameters under your repository configuration settings dashboard (**Settings → Secrets and variables → Actions**):

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | Your active temporary lab access key |
| `AWS_SECRET_ACCESS_KEY` | Your active temporary lab secret key |
| `AWS_SESSION_TOKEN` | Your active temporary cryptographic security token |
| `EC2_HOST` | The current public IP address string of the target compute host |
| `EC2_SSH_KEY` | The complete private key contents copied straight out of your `labsuser.pem` file |
| `ALB_DNS` | The clean, un-prefixed domain name string of the ALB instance |

---

## 🔍 Active Security Testing & Validation Suite

Execute these validation checks from an external client machine to verify your system defenses:

### T1: Perimeter Port Isolation Audit

Run an external network scan against the ALB domain to confirm least-privilege boundary rules are enforced:

```bash
nmap -sV <YOUR_ALB_DNS_NAME>
```

> **Expected Output:** Port `80` (HTTP) and Port `443` (HTTPS) must be the only open listening lines. All auxiliary ports (including database port `3306` and compute port `5000`) must return as `filtered` or `closed`.

---

### T2: Application Layer Penetration Verification

Simulate web vulnerability exploit payloads to test the application's input filtering and rate-limiting rules:

```bash
# Attempt an authentication bypass string payload injection attack
curl -s -X POST http://<YOUR_ALB_DNS_NAME>/ \
  -d "username=' OR '1'='1&password=invalid" -L | grep -i "invalid"

# Test application rate limiting by sending 25 rapid requests
for i in {1..25}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://<YOUR_ALB_DNS_NAME>/ \
    -d "username=test&password=bad")
  echo "Request $i: $STATUS"
done
```

> **Expected Results:** The SQL injection attempt is blocked by parameterized queries, returning a standard validation failure alert page. The rate-limiting test will pass the first 20 requests with code `200`, then block subsequent traffic with an HTTP `429 Too Many Requests` status code.

---

## 🧹 Session Teardown

Before your AWS Academy lab session timer hits zero, cleanly destroy your deployed resources to optimize cost controls:

```bash
aws cloudformation delete-stack --stack-name minilib-stack
```
