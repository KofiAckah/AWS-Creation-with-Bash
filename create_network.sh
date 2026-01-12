#!/bin/bash

# Source the configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# Function to create VPC
create_vpc() {
    log_section "VPC Creation"
    
    log_info "Creating VPC with CIDR block: $VPC_CIDR"
    validate_cidr "$VPC_CIDR" "VPC" || return 1
    
    # Create VPC
    log_command "aws ec2 create-vpc"
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block "$VPC_CIDR" \
        --region "$REGION" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME},{Key=${PROJECT_TAG%%=*},Value=${PROJECT_TAG#*=}}]" \
        --query 'Vpc.VpcId' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$VPC_ID" ]; then
        log_error "Failed to create VPC: $VPC_ID"
        log_section_end "VPC Creation" "failed"
        return 1
    fi
    
    log_info "VPC created successfully: $VPC_ID"
    save_state "VPC_ID" "$VPC_ID"
    
    # Enable DNS hostnames
    log_debug "Enabling DNS hostnames for VPC"
    aws ec2 modify-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --enable-dns-hostnames \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    # Enable DNS support
    log_debug "Enabling DNS support for VPC"
    aws ec2 modify-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --enable-dns-support \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    log_info "DNS hostnames and DNS support enabled for VPC"
    log_section_end "VPC Creation" "success"
    
    return 0
}

# Function to create Internet Gateway
create_internet_gateway() {
    log_section "Internet Gateway Creation"
    
    log_info "Creating Internet Gateway"
    
    log_command "aws ec2 create-internet-gateway"
    IGW_ID=$(aws ec2 create-internet-gateway \
        --region "$REGION" \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-IGW},{Key=${PROJECT_TAG%%=*},Value=${PROJECT_TAG#*=}}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$IGW_ID" ]; then
        log_error "Failed to create Internet Gateway: $IGW_ID"
        log_section_end "Internet Gateway Creation" "failed"
        return 1
    fi
    
    log_info "Internet Gateway created: $IGW_ID"
    save_state "IGW_ID" "$IGW_ID"
    
    # Attach Internet Gateway to VPC
    log_debug "Attaching Internet Gateway to VPC"
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$IGW_ID" \
        --vpc-id "$VPC_ID" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to attach Internet Gateway to VPC"
        log_section_end "Internet Gateway Creation" "failed"
        return 1
    fi
    
    log_info "Internet Gateway attached to VPC successfully"
    log_section_end "Internet Gateway Creation" "success"
    
    return 0
}

# Function to create Public Subnet
create_public_subnet() {
    log_section "Public Subnet Creation"
    
    log_info "Creating Public Subnet with CIDR: $PUBLIC_SUBNET_CIDR"
    validate_cidr "$PUBLIC_SUBNET_CIDR" "Public Subnet" || return 1
    
    # Get first availability zone
    log_debug "Fetching availability zones for region: $REGION"
    AZ=$(aws ec2 describe-availability-zones \
        --region "$REGION" \
        --query 'AvailabilityZones[0].ZoneName' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$AZ" ]; then
        log_error "Failed to fetch availability zones"
        log_section_end "Public Subnet Creation" "failed"
        return 1
    fi
    
    log_info "Selected Availability Zone: $AZ"
    
    log_command "aws ec2 create-subnet (public)"
    PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block "$PUBLIC_SUBNET_CIDR" \
        --availability-zone "$AZ" \
        --region "$REGION" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PUBLIC_SUBNET_NAME},{Key=${PROJECT_TAG%%=*},Value=${PROJECT_TAG#*=}}]" \
        --query 'Subnet.SubnetId' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$PUBLIC_SUBNET_ID" ]; then
        log_error "Failed to create Public Subnet: $PUBLIC_SUBNET_ID"
        log_section_end "Public Subnet Creation" "failed"
        return 1
    fi
    
    log_info "Public Subnet created: $PUBLIC_SUBNET_ID in AZ: $AZ"
    save_state "PUBLIC_SUBNET_ID" "$PUBLIC_SUBNET_ID"
    save_state "PUBLIC_SUBNET_AZ" "$AZ"
    
    # Enable auto-assign public IP
    log_debug "Enabling auto-assign public IP for Public Subnet"
    aws ec2 modify-subnet-attribute \
        --subnet-id "$PUBLIC_SUBNET_ID" \
        --map-public-ip-on-launch \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_warn "Failed to enable auto-assign public IP, but continuing..."
    else
        log_info "Auto-assign public IP enabled for Public Subnet"
    fi
    
    log_section_end "Public Subnet Creation" "success"
    
    return 0
}

# Function to create Private Subnet
create_private_subnet() {
    log_section "Private Subnet Creation"
    
    log_info "Creating Private Subnet with CIDR: $PRIVATE_SUBNET_CIDR"
    validate_cidr "$PRIVATE_SUBNET_CIDR" "Private Subnet" || return 1
    
    # Get second availability zone (or first if only one exists)
    log_debug "Fetching availability zones for region: $REGION"
    AZ=$(aws ec2 describe-availability-zones \
        --region "$REGION" \
        --query 'AvailabilityZones[1].ZoneName' \
        --output text 2>&1)
    
    # If no second AZ, use first
    if [ "$AZ" == "None" ] || [ -z "$AZ" ] || [ "$AZ" == "null" ]; then
        log_warn "Second AZ not available, using first AZ"
        AZ=$(aws ec2 describe-availability-zones \
            --region "$REGION" \
            --query 'AvailabilityZones[0].ZoneName' \
            --output text 2>&1)
    fi
    
    if [ $? -ne 0 ] || [ -z "$AZ" ]; then
        log_error "Failed to fetch availability zones"
        log_section_end "Private Subnet Creation" "failed"
        return 1
    fi
    
    log_info "Selected Availability Zone: $AZ"
    
    log_command "aws ec2 create-subnet (private)"
    PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block "$PRIVATE_SUBNET_CIDR" \
        --availability-zone "$AZ" \
        --region "$REGION" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PRIVATE_SUBNET_NAME},{Key=${PROJECT_TAG%%=*},Value=${PROJECT_TAG#*=}}]" \
        --query 'Subnet.SubnetId' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$PRIVATE_SUBNET_ID" ]; then
        log_error "Failed to create Private Subnet: $PRIVATE_SUBNET_ID"
        log_section_end "Private Subnet Creation" "failed"
        return 1
    fi
    
    log_info "Private Subnet created: $PRIVATE_SUBNET_ID in AZ: $AZ"
    save_state "PRIVATE_SUBNET_ID" "$PRIVATE_SUBNET_ID"
    save_state "PRIVATE_SUBNET_AZ" "$AZ"
    
    log_section_end "Private Subnet Creation" "success"
    
    return 0
}

# Function to create and configure Route Table for Public Subnet
create_public_route_table() {
    log_section "Public Route Table Creation"
    
    log_info "Creating Public Route Table"
    
    log_command "aws ec2 create-route-table"
    PUBLIC_RT_ID=$(aws ec2 create-route-table \
        --vpc-id "$VPC_ID" \
        --region "$REGION" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-Public-RT},{Key=${PROJECT_TAG%%=*},Value=${PROJECT_TAG#*=}}]" \
        --query 'RouteTable.RouteTableId' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$PUBLIC_RT_ID" ]; then
        log_error "Failed to create Public Route Table: $PUBLIC_RT_ID"
        log_section_end "Public Route Table Creation" "failed"
        return 1
    fi
    
    log_info "Public Route Table created: $PUBLIC_RT_ID"
    save_state "PUBLIC_RT_ID" "$PUBLIC_RT_ID"
    
    # Create route to Internet Gateway
    log_debug "Adding route to Internet Gateway"
    aws ec2 create-route \
        --route-table-id "$PUBLIC_RT_ID" \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id "$IGW_ID" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to add route to Internet Gateway"
        log_section_end "Public Route Table Creation" "failed"
        return 1
    fi
    
    log_info "Route to Internet Gateway added successfully"
    
    # Associate route table with public subnet
    log_debug "Associating Route Table with Public Subnet"
    ASSOC_ID=$(aws ec2 associate-route-table \
        --route-table-id "$PUBLIC_RT_ID" \
        --subnet-id "$PUBLIC_SUBNET_ID" \
        --region "$REGION" \
        --query 'AssociationId' \
        --output text 2>&1)
    
    if [ $? -ne 0 ]; then
        log_error "Failed to associate Route Table with Public Subnet"
        log_section_end "Public Route Table Creation" "failed"
        return 1
    fi
    
    log_info "Public Route Table associated with Public Subnet"
    save_state "PUBLIC_RT_ASSOC_ID" "$ASSOC_ID"
    
    log_section_end "Public Route Table Creation" "success"
    
    return 0
}

# Main execution
main() {
    log_info "=========================================="
    log_info "AWS VPC Network Creation Script"
    log_info "=========================================="
    
    # Pre-flight checks
    log_section "Pre-flight Checks"
    check_aws_cli
    check_aws_credentials
    validate_region "$REGION"
    log_section_end "Pre-flight Checks" "success"
    
    # Initialize state file
    touch "$STATE_FILE"
    
    # Create VPC components
    create_vpc || exit 1
    create_internet_gateway || exit 1
    create_public_subnet || exit 1
    create_private_subnet || exit 1
    create_public_route_table || exit 1
    
    # Display summary
    log_summary "VPC Creation Summary" \
        "VPC ID: $VPC_ID" \
        "VPC CIDR: $VPC_CIDR" \
        "" \
        "Internet Gateway ID: $IGW_ID" \
        "" \
        "Public Subnet ID: $PUBLIC_SUBNET_ID" \
        "Public Subnet CIDR: $PUBLIC_SUBNET_CIDR" \
        "Public Subnet AZ: $(load_state PUBLIC_SUBNET_AZ)" \
        "" \
        "Private Subnet ID: $PRIVATE_SUBNET_ID" \
        "Private Subnet CIDR: $PRIVATE_SUBNET_CIDR" \
        "Private Subnet AZ: $(load_state PRIVATE_SUBNET_AZ)" \
        "" \
        "Public Route Table ID: $PUBLIC_RT_ID" \
        "" \
        "State file: $STATE_FILE" \
        "Log file: $LOG_FILE"
    
    log_info "VPC creation completed successfully!"
}

# Run main function
main