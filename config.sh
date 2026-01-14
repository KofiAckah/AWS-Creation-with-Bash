#!/bin/bash

# --- Global AWS Settings ---
REGION="eu-west-1" 

# --- VPC & Networking Constants ---
# The CIDR block for the VPC
VPC_CIDR="10.0.0.0/16"

# The CIDR block for the specific subnet
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"

# Naming tags to keep resources organized (used for filtering during cleanup)
PROJECT_TAG="Project=AutomationLab"
VPC_NAME="AutomationVPC"
PUBLIC_SUBNET_NAME="AutomationPublicSubnet"
PRIVATE_SUBNET_NAME="AutomationPrivateSubnet"

# --- Output & Logging ---
LOG_FILE="setup.log"

# The name of the state file
STATE_FILE=".env"

# --- Security Group Configuration ---
SECURITY_GROUP_NAME="AutomationSecurityGroup"
SECURITY_GROUP_DESCRIPTION="Security group for Automation Lab EC2 instance"

# CIDR blocks for security group rules
SSH_CIDR="0.0.0.0/0"      # SSH access from anywhere (change to your IP for better security)
HTTP_CIDR="0.0.0.0/0"     # HTTP access from anywhere
HTTPS_CIDR="0.0.0.0/0"    # HTTPS access from anywhere

# --- EC2 Instance Configuration ---
INSTANCE_TYPE="t3.micro"
INSTANCE_NAME="AutomationWebServer"
# Note I have already created a key pair in AWS console named "AutoKeyPair"
KEY_NAME="AutoKeyPair"

# Export the variables so they are available to sub-shells if needed
export REGION VPC_CIDR PUBLIC_SUBNET_CIDR PRIVATE_SUBNET_CIDR PROJECT_TAG LOG_FILE STATE_FILE
export SECURITY_GROUP_NAME SECURITY_GROUP_DESCRIPTION SSH_CIDR HTTP_CIDR HTTPS_CIDR
export INSTANCE_TYPE INSTANCE_NAME KEY_NAME