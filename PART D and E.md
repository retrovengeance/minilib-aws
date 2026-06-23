# MiniLibrary AWS — CCS6344 Assignment 2

**Group 28 | CCS6344 T2610 Database & Cloud Security**

## Repository Structure

```
minilib-aws/
├── app.py                        # Flask application (PyMySQL, Fernet encryption)
├── requirements.txt              # Python dependencies
├── templates/                    # HTML templates (unchanged from Assignment 1)
├── static/                       # CSS/JS assets
├── db/
│   ├── schema.sql                # MySQL schema + stored procedures + RBAC
│   └── seed.sql                  # Test data
├── cloudformation/
│   └── main.yaml                 # Complete IaC — VPC, EC2, RDS, S3, CloudWatch
├── docker/
│   └── Dockerfile                # Container definition (bonus)
├── scripts/
│   └── backup_to_s3.py           # Hourly S3 backup script
└── .github/workflows/
    └── devsecops.yml             # DevSecOps CI/CD pipeline (bonus)
```

---

## Part D: Complete Deployment Guide

### Pre-session checklist (do before starting Academy session)

- [ ] GitHub repo is ready with all files committed
- [ ] Note your DBPassword (min 12 chars, e.g. `MiniLib@AWS2024!`)
- [ ] Note your FlaskSecretKey (long random string)
- [ ] Note your ICEncryptionKey (exactly 32 characters)
- [ ] Have your public IP ready: https://whatismyip.com

**Academy reminder:** Everything deletes when the session timer hits 0:00.
The CloudFormation stack redeploys the entire infrastructure in ~8 minutes.

---

### Step 1 — Launch Academy session

1. Go to https://awsacademy.instructure.com/courses/173098
2. Click **Start Lab** → wait for "Lab status: ready"
3. Click **AWS** to open the console
4. Confirm you are in **us-east-1 (N. Virginia)**

---

### Step 2 — Deploy CloudFormation stack

**Option A: AWS Console (recommended for first deployment)**

1. Go to **CloudFormation** → **Create stack** → **With new resources**
2. Choose **Upload a template file** → upload `cloudformation/main.yaml`
3. Fill parameters:
   - `DBPassword`: `MiniLib@AWS2024!` (or your choice, min 12 chars)
   - `DBUsername`: `admin`
   - `FlaskSecretKey`: `mmu-ccs6344-g28-flask-secret-key-2024`
   - `ICEncryptionKey`: `MiniLibICKey2024ForFernetAES256!!` (exactly 32 chars)
   - `KeyPairName`: `vockey`
   - `YourIP`: your IP from whatismyip.com in CIDR format, e.g. `203.0.113.5/32`
4. Stack name: `minilib-stack`
5. Click **Next** → **Next** → check **"I acknowledge..."** → **Submit**
6. Wait ~8-10 minutes for `CREATE_COMPLETE`

**Option B: AWS CLI in Academy terminal**

```bash
aws cloudformation create-stack \
  --stack-name minilib-stack \
  --template-body file://cloudformation/main.yaml \
  --parameters \
    ParameterKey=DBPassword,ParameterValue='MiniLib@AWS2024!' \
    ParameterKey=DBUsername,ParameterValue=admin \
    ParameterKey=FlaskSecretKey,ParameterValue='mmu-ccs6344-flask-secret-2024' \
    ParameterKey=ICEncryptionKey,ParameterValue='MiniLibICKey2024ForFernetAES256!!' \
    ParameterKey=KeyPairName,ParameterValue=vockey \
    ParameterKey=YourIP,ParameterValue='0.0.0.0/0' \
  --region us-east-1

# Monitor status
aws cloudformation wait stack-create-complete --stack-name minilib-stack

# Get outputs (EC2 IP, RDS endpoint, ALB DNS)
aws cloudformation describe-stacks --stack-name minilib-stack \
  --query 'Stacks[0].Outputs' --output table
```

---

### Step 3 — Set up the database

SSH into EC2 using the vockey.pem downloaded from Academy "Show" credentials:

```bash
# Windows: use PuTTY with labsuser.ppk
# Mac/Linux:
chmod 400 ~/Downloads/labsuser.pem
ssh -i ~/Downloads/labsuser.pem ec2-user@<EC2_PUBLIC_IP>
```

Once inside EC2, run the schema and seed scripts:

```bash
# Get RDS endpoint from CloudFormation outputs or:
RDS_ENDPOINT=$(aws cloudformation describe-stacks --stack-name minilib-stack \
  --query "Stacks[0].Outputs[?OutputKey=='RDSEndpoint'].OutputValue" \
  --output text)

# Install MySQL client
sudo dnf install -y mysql

# Run schema (creates tables, stored procedures, lib_admin, lib_member)
mysql -h $RDS_ENDPOINT -u admin -p'MiniLib@AWS2024!' MiniLibraryDB \
  < /opt/minilib/db/schema.sql

# Run seed data
mysql -h $RDS_ENDPOINT -u admin -p'MiniLib@AWS2024!' MiniLibraryDB \
  < /opt/minilib/db/seed.sql

# Verify tables
mysql -h $RDS_ENDPOINT -u admin -p'MiniLib@AWS2024!' MiniLibraryDB \
  -e "SHOW TABLES; SELECT COUNT(*) FROM Books;"
```

---

### Step 4 — Verify Flask is running

```bash
# Check Flask log
tail -50 /var/log/minilib-flask.log

# Test health endpoint locally
curl http://localhost:5000/health
# Expected: {"status": "ok"}

# Test through nginx
curl http://localhost/health
# Expected: {"status": "ok"}

# Check nginx status
sudo systemctl status nginx
```

---

### Step 5 — Register EC2 in ALB Target Group

CloudFormation creates the Target Group but registration must be done manually
(Academy's IAM restrictions prevent the CloudFormation custom resource approach):

1. AWS Console → **EC2** → **Load Balancing** → **Target Groups**
2. Select **minilib-ec2-tg**
3. **Register targets** → select your EC2 instance → port **80**
4. Wait for health status to show **healthy** (checks `/health`)

---

### Step 6 — Access the application

From **CloudFormation Outputs**, copy `ALBDNSName`:

```
http://minilib-alb-XXXX.us-east-1.elb.amazonaws.com
```

- The ALB forwards HTTP:80 → EC2:80 (nginx)
- nginx redirects HTTP → HTTPS (self-signed cert, browser will warn → proceed anyway)
- nginx proxies HTTPS → Flask:5000

**Test accounts (seed data):**
| Username | Password | Role |
|---|---|---|
| admin | Test@1234 | Librarian |
| ali.hassan | Test@1234 | Member |
| nur.aina | Test@1234 | Member |

---

### Step 7 — Bonus: Run as Docker container

```bash
# Install Docker on EC2
sudo dnf install -y docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user
newgrp docker

# Build the image
cd /opt/minilib
docker build -t minilib:latest -f docker/Dockerfile .

# Stop the plain Flask process
pkill -f "python3 /opt/minilib/app.py" || true

# Run as container (reads env vars from .env file)
docker run -d \
  --name minilib \
  --env-file /opt/minilib/.env \
  -p 5000:5000 \
  --restart unless-stopped \
  minilib:latest

# Verify
docker ps
docker logs minilib
curl http://localhost:5000/health
```

**Screenshot for report:** `docker ps` showing container running + `curl /health` response.

---

### Step 8 — Bonus: Enable AWS Inspector

1. AWS Console → search **Inspector**
2. **Get started** → **Enable Inspector**
3. Select **EC2 scanning** → confirm
4. Add LabInstanceProfile to your EC2 (should already be attached via CloudFormation)
5. Wait 15–30 minutes for initial scan results
6. Screenshot the **Findings** dashboard showing severity breakdown

**For report:** Note finding count by severity, describe one High finding and your remediation.

---

### Step 9 — Verify security controls (Part E evidence)

```bash
# From your LOCAL machine (not EC2):

# 1. Port scan — only port 80 should respond on ALB
nmap -sV <ALB_DNS_NAME>

# 2. SQL injection test — should return login error, not bypass
curl -X POST http://<ALB_DNS>/  \
  -d "username=' OR '1'='1&password=anything" \
  -v

# 3. Rate limiting test (Flask-Limiter WAF substitute)
for i in {1..25}; do
  curl -s -o /dev/null -w "%{http_code}\n" -X POST http://<ALB_DNS>/ \
    -d "username=test&password=wrong"
done
# After 20 requests/minute: should see 429 Too Many Requests

# 4. Verify RDS encryption in console:
# RDS → Databases → minilibrarydb → Configuration tab
# "Encryption: Enabled" — screenshot this

# 5. Check CloudTrail:
# CloudTrail → Event history — show API calls (CreateDBInstance, etc.)
```

---

### Cleanup (before session ends)

```bash
aws cloudformation delete-stack --stack-name minilib-stack
```

Or via console: CloudFormation → minilib-stack → Delete.

---

## Security Controls Summary (for Part D report section)

| Control | Assignment 1 | Assignment 2 (AWS) |
|---|---|---|
| Encryption at rest | TDE AES-256 (SQL Server) | RDS StorageEncrypted AES-256 + EBS encrypted |
| Encryption in transit | Unencrypted (port 1433) | SSL/TLS on PyMySQL + nginx HTTPS (TLS 1.2+) |
| IC number protection | Always Encrypted | Fernet AES-128 at application layer |
| Phone masking | DDM (SQL Server) | Python mask_phone() in Flask |
| Email masking | DDM (SQL Server) | Python mask_email() in Flask |
| RBAC | lib_admin / lib_member (SQL Server logins) | lib_admin / lib_member (MySQL users) |
| Stored procedures | 16 T-SQL signed SPs | 16 MySQL SPs via CALL |
| Rate limiting | Account lockout only | Flask-Limiter (WAF substitute) + account lockout |
| Audit trail | AuditLog table + SQL Server Audit | AuditLog table + CloudTrail |
| Monitoring | None | CloudWatch alarms (CPU, connections, 5xx, storage) |
| Backups | Manual SSMS backup | Automated RDS snapshots + hourly S3 mysqldump |
| Network segmentation | None (single VM) | VPC + public/private subnets + SG + NACL |
| Access control | Windows Firewall | Security Groups (stateful) + NACLs (stateless) |
| IPv6 | None | Dual-stack VPC (/56 Amazon-provided block) |
