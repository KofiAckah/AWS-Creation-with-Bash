#!/bin/bash

# --- Global AWS Settings ---
# Choose your preferred region (ensure it matches your CLI config)
REGION="eu-west-1" 

# --- VPC & Networking Constants ---
# The IP range for your custom VPC
VPC_CIDR="10.0.0.0/16"

# The IP range for your specific subnet
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"

# Naming tags to keep resources organized (used for filtering during cleanup)
PROJECT_TAG="Project=AutomationLab"
VPC_NAME="AutomationVPC"
PUBLIC_SUBNET_NAME="AutomationPublicSubnet"
PRIVATE_SUBNET_NAME="AutomationPrivateSubnet"

# --- Output & Logging ---
# The path to your log file
LOG_FILE="setup.log"

# The name of your state file
STATE_FILE=".env"

# Export the variables so they are available to sub-shells if needed
export REGION VPC_CIDR PUBLIC_SUBNET_CIDR PRIVATE_SUBNET_CIDR PROJECT_TAG LOG_FILE STATE_FILE