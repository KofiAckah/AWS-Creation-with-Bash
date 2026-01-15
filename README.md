# AWS Infrastructure Automation with Bash

A comprehensive, production-ready Bash automation toolkit for provisioning and managing complete AWS infrastructure including VPC networking, EC2 instances, security groups, and S3 storage with enterprise-grade logging and state management.

![AWS](https://img.shields.io/badge/AWS-Cloud-orange?logo=amazon-aws)
![Bash](https://img.shields.io/badge/Bash-4.0+-green?logo=gnu-bash)
![License](https://img.shields.io/badge/License-MIT-blue)

## 🚀 Overview

This project provides a robust, modular set of shell scripts to automate the complete lifecycle of AWS infrastructure deployment. Built with DevOps best practices, it features idempotent operations, comprehensive logging, state persistence, and graceful error handling - making infrastructure provisioning reliable, repeatable, and maintainable.

## ✨ Features

### Core Infrastructure Components
- **🔑 Key Pair Management**: Automated EC2 key pair creation with secure permissions
- **🌐 VPC Management**: Automated VPC creation with configurable CIDR blocks and DNS support
- **🔀 Network Segmentation**: Public and private subnet provisioning with intelligent AZ selection
- **🌍 Internet Gateway**: Automatic IGW creation, attachment, and route configuration
- **📊 Route Tables**: Dynamic route table setup with proper subnet associations
- **🔒 Security Groups**: Pre-configured security groups with customizable ingress rules
- **💻 EC2 Instances**: Automated EC2 provisioning with user data scripts
- **📦 S3 Storage**: S3 bucket creation with versioning and public access configuration
- **🌐 Web Server**: Automated Apache installation with custom HTML deployment

### Advanced Capabilities
- **📝 Multi-Level Logging**: DEBUG, INFO, WARN, ERROR, FATAL levels with color-coded output
- **💾 State Management**: Persistent state tracking using `.env` files for idempotency
- **✅ Pre-flight Validation**: AWS CLI, credentials, region, and CIDR block validation
- **🔄 Idempotent Operations**: Safe to run multiple times without resource duplication
- **🏷️ Resource Tagging**: Consistent tagging strategy across all AWS resources
- **🧹 Cleanup Automation**: Complete resource cleanup with dependency management
- **📊 Status Checking**: Resource status verification before operations
- **🎨 Beautiful UI**: Custom HTML dashboard with real-time EC2 metadata display

## 📁 Project Structure

```
AWS_Resource_Creation_Bash/
├── config.sh                    # Central configuration management
├── utils.sh                     # Logging and utility functions
├── create_key_pair.sh           # EC2 key pair creation
├── create_network.sh            # VPC and networking resources
├── create_security_group.sh     # Security group management
├── create_ec2.sh                # EC2 instance provisioning
├── create_s3_bucket.sh          # S3 bucket creation and file upload
├── cleanup_resources.sh         # Complete infrastructure cleanup
├── check_resources.sh           # Resource status verification
├── index.html                   # Web application dashboard
├── welcome.txt                  # S3 welcome file
├── .env                         # State file (auto-generated)
├── setup.log                    # Execution logs (auto-generated)
└── README.md                    # This file
```

## 🏗️ Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Configuration Layer                     │
│                        (config.sh)                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       Utility Layer                          │
│     (utils.sh - Logging, State, Validation)                 │
└─────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼             ▼
         ┌──────────┐  ┌──────────┐  ┌──────────┐
         │ Network  │  │ Security │  │   EC2    │
         │  Layer   │  │  Layer   │  │  Layer   │
         └──────────┘  └──────────┘  └──────────┘
                              │
                              ▼
                       ┌──────────┐
                       │ Storage  │
                       │  Layer   │
                       └──────────┘
```

### Resource Dependencies

```
Key Pair → VPC → Internet Gateway → Subnets → Route Tables → Security Groups → EC2 Instance
                                                                                    │
                                                                                    ▼
                                                                               S3 Bucket
```

## 🛠️ Prerequisites

### Required Software
- **AWS CLI**: Version 2.0 or higher
- **Bash**: Version 4.0 or higher
- **jq** (optional): For JSON parsing
- **git**: For version control

### AWS Requirements
- Valid AWS account
- AWS CLI configured with credentials
- IAM user/role with appropriate permissions

### Required IAM Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "s3:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## 🚀 Quick Start

### 1. Clone and Setup
```bash
git clone <repository-url>
cd AWS_Resource_Creation_Bash
chmod +x *.sh
```

### 2. Configure AWS CLI
```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: eu-west-1
# Default output format: json
```

### 3. Review Configuration
```bash
vim config.sh
# Update region, CIDR blocks, instance types, key name, etc.
```

### 4. Deploy Infrastructure
```bash
# Step 1: Create EC2 Key Pair (MUST BE FIRST!)
./create_key_pair.sh

# Step 2: Create VPC and networking
./create_network.sh

# Step 3: Create Security Group
./create_security_group.sh

# Step 4: Create EC2 Instance with web server
./create_ec2.sh

# Step 5: Create S3 bucket and upload files
./create_s3_bucket.sh
```

### 5. Verify Deployment
```bash
# Check all resources
./check_resources.sh

# Access web application
# Open browser to http://<public-ip>
```

### 6. Cleanup (Optional)
```bash
# Remove all resources (except key pair - must be deleted manually)
./cleanup_resources.sh
```

## 📋 Detailed Usage

### Creating EC2 Key Pair (Required First Step!)

### Network Configuration
```bash
# Region
REGION="eu-west-1"

# VPC CIDR Block
VPC_CIDR="10.0.0.0/16"

# Subnet CIDR Blocks
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"

# Resource Naming
VPC_NAME="AutomationVPC"
PUBLIC_SUBNET_NAME="AutomationPublicSubnet"
PRIVATE_SUBNET_NAME="AutomationPrivateSubnet"
```

### Security Configuration
```bash
# Security Group
SECURITY_GROUP_NAME="AutomationSecurityGroup"

# Access Rules (customize for production!)
SSH_CIDR="0.0.0.0/0"      # ⚠️ Restrict to your IP in production
HTTP_CIDR="0.0.0.0/0"     # Allow public web access
HTTPS_CIDR="0.0.0.0/0"    # Allow secure web access
```

### EC2 Configuration
```bash
# Instance Settings
INSTANCE_TYPE="t3.micro"           # AWS Free Tier eligible
INSTANCE_NAME="AutomationWebServer"
KEY_NAME="AutoKeyPair"             # Your EC2 key pair name
```

### Logging Configuration
```bash
# Log Files
LOG_FILE="setup.log"               # Main log file
STATE_FILE=".env"                  # State persistence file

# Log Level (in utils.sh)
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}  # INFO, DEBUG, WARN, ERROR, FATAL
```

## 📋 Detailed Usage

### Creating Network Infrastructure

```bash
./create_network.sh
```

**What it creates:**
- VPC with DNS support enabled
- Internet Gateway attached to VPC
- Public subnet with auto-assign public IP
- Private subnet
- Public route table with internet gateway route
- Route table associations

**State saved:**
- `VPC_ID`
- `IGW_ID`
- `PUBLIC_SUBNET_ID`
- `PRIVATE_SUBNET_ID`
- `PUBLIC_RT_ID`
- `PUBLIC_RT_ASSOC_ID`

### Creating Security Group

```bash
./create_security_group.sh
```

**What it creates:**
- Security group in your VPC
- SSH ingress rule (port 22)
- HTTP ingress rule (port 80)
- HTTPS ingress rule (port 443)

**State saved:**
- `SECURITY_GROUP_ID`

### Creating EC2 Instance

```bash
./create_ec2.sh
```

**Prerequisites:**
- ✅ Key pair must exist (run `create_key_pair.sh` first)
- ✅ VPC must exist (run `create_network.sh` first)
- ✅ Security group must exist (run `create_security_group.sh` first)

**What it does:**
- Fetches latest Amazon Linux 2 AMI
- Creates EC2 instance with user data script
- Installs and configures Apache web server
- Deploys custom HTML dashboard
- Waits for instance to be running
- Retrieves and displays instance details

**State saved:**
- `INSTANCE_ID`
- `AMI_ID`
- `PUBLIC_IP`
- `PRIVATE_IP`
- `INSTANCE_AZ`

**Access your web application:**
```bash
# Get public IP from state file
cat .env | grep PUBLIC_IP

# Open in browser
http://<public-ip>

# SSH into instance
ssh -i AutoKeyPair.pem ec2-user@<public-ip>
```

### Creating S3 Bucket

```bash
./create_s3_bucket.sh
```

**What it creates:**
- S3 bucket with unique name
- Bucket tagging
- Versioning enabled
- Uploads `welcome.txt` file
- Configures public access (optional)

**State saved:**
- `S3_BUCKET_NAME`
- `WELCOME_FILE_URL`

### Checking Resources

```bash
./check_resources.sh
```

**Output example:**
```
1. VPC:
  Status: ✓ EXISTS
  ID: vpc-0123456789abcdef0

2. Internet Gateway:
  Status: ✓ EXISTS
  ID: igw-0123456789abcdef0

3. Public Subnet:
  Status: ✓ EXISTS
  ID: subnet-0123456789abcdef0

...
```

### Cleanup Resources

```bash
./cleanup_resources.sh
```

**⚠️ Note:** This script does NOT delete the EC2 key pair. You must delete it manually if needed.

**What it does:**
- Backs up state file
- Requests confirmation
- Deletes resources in reverse order:
  1. S3 bucket (empties then deletes)
  2. EC2 instance (terminates and waits)
  3. Security group
  4. Route table (disassociates then deletes)
  5. Subnets (public and private)
  6. Internet gateway (detaches then deletes)
  7. VPC
- Clears state file

## 📝 Logging System

### Log Format
```
[YYYY-MM-DD HH:MM:SS] [LEVEL] [script:line] Message
```

### Example Log Output
```log
[2026-01-12 10:30:45] [INFO] [create_network.sh:45] VPC created successfully: vpc-0123456789abcdef0
[2026-01-12 10:30:46] [DEBUG] [create_network.sh:52] Enabling DNS hostnames for VPC
[2026-01-12 10:30:48] [INFO] [create_network.sh:61] DNS hostnames and DNS support enabled
```

### Log Levels
- **DEBUG**: Detailed operational information (AWS commands, parameters)
- **INFO**: General informational messages (resource creation, status updates)
- **WARN**: Warning messages for non-critical issues
- **ERROR**: Error messages for failures (continues execution)
- **FATAL**: Critical errors that halt execution

### Viewing Logs
```bash
# View entire log
cat setup.log

# Tail logs in real-time
tail -f setup.log

# Filter by level
grep "\[ERROR\]" setup.log
grep "\[INFO\]" setup.log

# View recent entries
tail -n 50 setup.log
```

## 💾 State Management

### State File (.env)
The `.env` file tracks all resource IDs for idempotency and cleanup:

```bash
VPC_ID=vpc-0123456789abcdef0
IGW_ID=igw-0123456789abcdef0
PUBLIC_SUBNET_ID=subnet-0123456789abcdef0
PRIVATE_SUBNET_ID=subnet-0fedcba9876543210
PUBLIC_RT_ID=rtb-0123456789abcdef0
PUBLIC_RT_ASSOC_ID=rtbassoc-0123456789abcdef0
SECURITY_GROUP_ID=sg-0123456789abcdef0
INSTANCE_ID=i-0123456789abcdef0
AMI_ID=ami-0123456789abcdef0
PUBLIC_IP=54.123.45.67
PRIVATE_IP=10.0.1.123
INSTANCE_AZ=eu-west-1a
S3_BUCKET_NAME=automation-lab-bucket-1234567890
WELCOME_FILE_URL=https://automation-lab-bucket-1234567890.s3.eu-west-1.amazonaws.com/welcome.txt
```

### State Functions
```bash
# Save state
save_state "KEY" "value"

# Load state
value=$(load_state "KEY")

# Check state
if [ -n "$(load_state KEY 2>/dev/null)" ]; then
    echo "Resource exists"
fi
```

## 🔒 Security Best Practices

### Key Pair Security

1. **Protect Your Private Key**
   ```bash
   # Ensure proper permissions
   chmod 400 AutoKeyPair.pem
   
   # Store in secure location
   mv AutoKeyPair.pem ~/.ssh/
   ```

2. **Backup Your Key**
   ```bash
   # Create encrypted backup
   gpg -c AutoKeyPair.pem
   
   # Store backup in secure location (AWS S3, password manager, etc.)
   ```

3. **Never Commit Keys to Git**
   ```bash
   # Already in .gitignore
   *.pem
   *.key
   ```

### Production Hardening

1. **Restrict SSH Access**
   ```bash
   # In config.sh, change:
   SSH_CIDR="YOUR_IP/32"  # Replace with your IP
   ```

2. **Use IAM Roles**
   - Attach IAM roles to EC2 instances instead of using access keys
   - Follow principle of least privilege

3. **Enable VPC Flow Logs**
   ```bash
   aws ec2 create-flow-logs \
       --resource-type VPC \
       --resource-ids $VPC_ID \
       --traffic-type ALL \
       --log-destination-type cloud-watch-logs
   ```

4. **Enable S3 Encryption**
   ```bash
   aws s3api put-bucket-encryption \
       --bucket $BUCKET_NAME \
       --server-side-encryption-configuration \
       '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
   ```

5. **Use Private Subnets**
   - Deploy sensitive resources in private subnets
   - Use NAT Gateway for outbound internet access

6. **Enable MFA Delete**
   ```bash
   aws s3api put-bucket-versioning \
       --bucket $BUCKET_NAME \
       --versioning-configuration Status=Enabled,MFADelete=Enabled
   ```

## 🐛 Troubleshooting

### Key Pair Issues

#### Key Pair Already Exists
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

#### Credentials Not Configured
```bash
# Configure AWS credentials
aws configure

# Verify configuration
aws sts get-caller-identity
```

#### Lost Private Key File
**⚠️ If you lose your .pem file, you CANNOT recover it!**
```bash
# Delete the key pair and create a new one
aws ec2 delete-key-pair --key-name AutoKeyPair --region eu-west-1
./create_key_pair.sh
```

#### Permission Denied When Using Key
```bash
# Fix permissions
chmod 400 AutoKeyPair.pem

# Verify
ls -la AutoKeyPair.pem
# Should show: -r--------
```

#### Cannot SSH to Instance
```bash
# 1. Verify key file exists and has correct permissions
ls -la AutoKeyPair.pem

# 2. Check security group allows SSH from your IP
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID

# 3. Verify instance is running
aws ec2 describe-instances --instance-ids $INSTANCE_ID

# 4. Try SSH with verbose output
ssh -i AutoKeyPair.pem -v ec2-user@$PUBLIC_IP
```

---

**Made with ❤️ for the AWS community**

For questions, issues, or contributions, please open an issue or submit a pull request.

**Note**: Always review AWS costs and security implications before deploying to production environments.
