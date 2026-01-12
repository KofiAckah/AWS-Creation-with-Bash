#!/bin/bash

# Source the configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# Function to check if EC2 instance already exists
check_existing_instance() {
    local existing_instance_id=$(load_state "INSTANCE_ID" 2>/dev/null)
    
    if [ -n "$existing_instance_id" ]; then
        log_info "Found existing Instance ID in state file: $existing_instance_id"
        
        # Verify the instance actually exists in AWS and is running
        local instance_state=$(aws ec2 describe-instances \
            --instance-ids "$existing_instance_id" \
            --region "$REGION" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null)
        
        if [ "$instance_state" == "running" ] || [ "$instance_state" == "stopped" ]; then
            log_info "Instance exists in AWS with state: $instance_state. Skipping creation."
            INSTANCE_ID="$existing_instance_id"
            return 0
        else
            log_warn "Instance ID in state file does not exist or terminated. Will create new instance."
            return 1
        fi
    fi
    
    return 1
}

# Function to get the latest Amazon Linux 2 AMI
get_latest_ami() {
    log_section "Getting Latest AMI"
    
    log_info "Fetching latest Amazon Linux 2 AMI ID..."
    
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        "Name=state,Values=available" \
        --region "$REGION" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$AMI_ID" ]; then
        log_error "Failed to fetch AMI ID: $AMI_ID"
        log_section_end "Getting Latest AMI" "failed"
        return 1
    fi
    
    log_info "Latest Amazon Linux 2 AMI ID: $AMI_ID"
    save_state "AMI_ID" "$AMI_ID"
    
    log_section_end "Getting Latest AMI" "success"
    return 0
}

# Function to create user data script
create_user_data_script() {
    log_section "Creating User Data Script"
    
    local user_data_file="/tmp/user_data_${RANDOM}.sh"
    
    log_info "Creating user data script at: $user_data_file"
    
    # Create the user data script
    cat > "$user_data_file" << 'EOF'
#!/bin/bash
# User data script for EC2 instance

# Log file for debugging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== User Data Script Started at $(date) ==="

# Update system packages
echo "Updating system packages..."
yum update -y

# Install Apache web server
echo "Installing Apache HTTP Server..."
yum install -y httpd

# Start and enable Apache
echo "Starting and enabling Apache..."
systemctl start httpd
systemctl enable httpd

# Create the index.html file
echo "Creating index.html..."
cat > /var/www/html/index.html << 'HTMLEOF'
EOF
    
    # Append the index.html content
    if [ -f "${SCRIPT_DIR}/index.html" ]; then
        cat "${SCRIPT_DIR}/index.html" >> "$user_data_file"
    else
        log_error "index.html file not found at ${SCRIPT_DIR}/index.html"
        log_section_end "Creating User Data Script" "failed"
        return 1
    fi
    
    # Complete the user data script
    cat >> "$user_data_file" << 'EOF'
HTMLEOF

# Set proper permissions
echo "Setting file permissions..."
chmod 644 /var/www/html/index.html
chown apache:apache /var/www/html/index.html

# Configure firewall (if firewalld is installed)
if systemctl is-active --quiet firewalld; then
    echo "Configuring firewall..."
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
fi

# Verify Apache is running
if systemctl is-active --quiet httpd; then
    echo "Apache is running successfully!"
else
    echo "ERROR: Apache failed to start!"
    systemctl status httpd
fi

echo "=== User Data Script Completed at $(date) ==="
EOF
    
    # Save the user data file path
    echo "$user_data_file" > /tmp/user_data_path.txt
    
    log_info "User data script created successfully"
    log_section_end "Creating User Data Script" "success"
    return 0
}

# Function to create EC2 instance
create_ec2_instance() {
    log_section "EC2 Instance Creation"
    
    # Check if instance already exists
    if check_existing_instance; then
        log_section_end "EC2 Instance Creation" "success"
        return 0
    fi
    
    # Load required IDs from state file
    SECURITY_GROUP_ID=$(load_state "SECURITY_GROUP_ID" 2>/dev/null)
    PUBLIC_SUBNET_ID=$(load_state "PUBLIC_SUBNET_ID" 2>/dev/null)
    
    if [ -z "$SECURITY_GROUP_ID" ]; then
        log_error "Security Group ID not found. Please run create_security_group.sh first."
        log_section_end "EC2 Instance Creation" "failed"
        return 1
    fi
    
    if [ -z "$PUBLIC_SUBNET_ID" ]; then
        log_error "Public Subnet ID not found. Please run create_network.sh first."
        log_section_end "EC2 Instance Creation" "failed"
        return 1
    fi
    
    # Get latest AMI
    if ! get_latest_ami; then
        log_section_end "EC2 Instance Creation" "failed"
        return 1
    fi
    
    # Create user data script
    if ! create_user_data_script; then
        log_section_end "EC2 Instance Creation" "failed"
        return 1
    fi
    
    # Get user data file path
    local user_data_file=$(cat /tmp/user_data_path.txt)
    
    log_info "Creating EC2 instance..."
    log_info "Instance Type: $INSTANCE_TYPE"
    log_info "AMI ID: $AMI_ID"
    log_info "Security Group: $SECURITY_GROUP_ID"
    log_info "Subnet: $PUBLIC_SUBNET_ID"
    log_info "Key Name: $KEY_NAME"
    
    # Create the EC2 instance
    log_command "aws ec2 run-instances"
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --subnet-id "$PUBLIC_SUBNET_ID" \
        --user-data "file://$user_data_file" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=${PROJECT_TAG%%=*},Value=${PROJECT_TAG#*=}}]" \
        --region "$REGION" \
        --query 'Instances[0].InstanceId' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$INSTANCE_ID" ]; then
        log_error "Failed to create EC2 instance: $INSTANCE_ID"
        rm -f "$user_data_file" /tmp/user_data_path.txt
        log_section_end "EC2 Instance Creation" "failed"
        return 1
    fi
    
    log_info "EC2 instance created successfully: $INSTANCE_ID"
    save_state "INSTANCE_ID" "$INSTANCE_ID"
    
    # Clean up temporary files
    rm -f "$user_data_file" /tmp/user_data_path.txt
    
    # Wait for instance to be running
    log_info "Waiting for instance to be in running state..."
    aws ec2 wait instance-running \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION"
    
    if [ $? -eq 0 ]; then
        log_info "Instance is now running!"
    else
        log_warn "Instance may still be starting up..."
    fi
    
    log_section_end "EC2 Instance Creation" "success"
    return 0
}

# Function to get instance details
get_instance_details() {
    log_section "Getting Instance Details"
    
    # Get instance details
    INSTANCE_DETAILS=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0]' \
        --output json 2>&1)
    
    if [ $? -ne 0 ]; then
        log_error "Failed to get instance details"
        log_section_end "Getting Instance Details" "failed"
        return 1
    fi
    
    # Extract details
    PUBLIC_IP=$(echo "$INSTANCE_DETAILS" | grep -o '"PublicIpAddress": "[^"]*"' | cut -d'"' -f4)
    PRIVATE_IP=$(echo "$INSTANCE_DETAILS" | grep -o '"PrivateIpAddress": "[^"]*"' | cut -d'"' -f4)
    AZ=$(echo "$INSTANCE_DETAILS" | grep -o '"AvailabilityZone": "[^"]*"' | cut -d'"' -f4)
    INSTANCE_STATE=$(echo "$INSTANCE_DETAILS" | grep -o '"Name": "[^"]*"' | head -1 | cut -d'"' -f4)
    
    # Save to state file
    save_state "PUBLIC_IP" "$PUBLIC_IP"
    save_state "PRIVATE_IP" "$PRIVATE_IP"
    save_state "INSTANCE_AZ" "$AZ"
    
    log_info "Public IP: $PUBLIC_IP"
    log_info "Private IP: $PRIVATE_IP"
    log_info "Availability Zone: $AZ"
    log_info "Instance State: $INSTANCE_STATE"
    
    log_section_end "Getting Instance Details" "success"
    return 0
}

# Main execution
main() {
    log_info "=========================================="
    log_info "AWS EC2 Instance Creation Script"
    log_info "=========================================="
    
    # Pre-flight checks
    log_section "Pre-flight Checks"
    check_aws_cli
    check_aws_credentials
    validate_region "$REGION"
    
    # Check if index.html exists
    if [ ! -f "${SCRIPT_DIR}/index.html" ]; then
        log_error "index.html not found at ${SCRIPT_DIR}/index.html"
        log_error "Please ensure index.html exists before running this script"
        exit 1
    fi
    
    log_section_end "Pre-flight Checks" "success"
    
    # Initialize state file
    touch "$STATE_FILE"
    
    # Create EC2 instance
    create_ec2_instance || exit 1
    
    # Get instance details
    get_instance_details || exit 1
    
    # Wait a bit more for user data script to complete
    log_info "Waiting 30 seconds for user data script to complete..."
    sleep 30
    
    # Display summary
    log_summary "EC2 Instance Creation Summary" \
        "Instance ID: $INSTANCE_ID" \
        "Instance Name: $INSTANCE_NAME" \
        "Instance Type: $INSTANCE_TYPE" \
        "AMI ID: $AMI_ID" \
        "" \
        "Network Details:" \
        "  Public IP: $PUBLIC_IP" \
        "  Private IP: $PRIVATE_IP" \
        "  Availability Zone: $AZ" \
        "  Subnet ID: $PUBLIC_SUBNET_ID" \
        "  Security Group ID: $SECURITY_GROUP_ID" \
        "" \
        "Web Server:" \
        "  URL: http://$PUBLIC_IP" \
        "" \
        "SSH Access:" \
        "  Command: ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP" \
        "" \
        "State file: $STATE_FILE" \
        "Log file: $LOG_FILE"
    
    log_info "=========================================="
    log_info "EC2 instance creation completed successfully!"
    log_info "=========================================="
    log_info ""
    log_info "To access your web application:"
    log_info "  Open browser: http://$PUBLIC_IP"
    log_info ""
    log_info "To SSH into your instance:"
    log_info "  ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP"
    log_info ""
    log_info "Note: It may take a few minutes for the web server to be fully configured."
}

# Run main function
main