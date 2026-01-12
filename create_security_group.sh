#!/bin/bash

# Source the configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# Function to check if Security Group already exists
check_existing_sg() {
    local existing_sg_id=$(load_state "SECURITY_GROUP_ID" 2>/dev/null)
    
    if [ -n "$existing_sg_id" ]; then
        log_info "Found existing Security Group ID in state file: $existing_sg_id"
        
        # Verify the security group actually exists in AWS
        if aws ec2 describe-security-groups --group-ids "$existing_sg_id" --region "$REGION" &> /dev/null; then
            log_info "Security Group exists in AWS. Skipping creation."
            SECURITY_GROUP_ID="$existing_sg_id"
            return 0
        else
            log_warn "Security Group ID in state file does not exist in AWS. Will create new security group."
            return 1
        fi
    fi
    
    return 1
}

# Function to create Security Group
create_security_group() {
    log_section "Security Group Creation"
    
    # Check if security group already exists
    if check_existing_sg; then
        log_section_end "Security Group Creation" "success"
        return 0
    fi
    
    # Load VPC_ID from state file
    VPC_ID=$(load_state "VPC_ID" 2>/dev/null)
    
    if [ -z "$VPC_ID" ]; then
        log_error "VPC_ID not found in state file. Please run create_network.sh first."
        log_section_end "Security Group Creation" "failed"
        return 1
    fi
    
    log_info "Creating Security Group in VPC: $VPC_ID"
    
    # Create Security Group
    log_command "aws ec2 create-security-group"
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "$SECURITY_GROUP_DESCRIPTION" \
        --vpc-id "$VPC_ID" \
        --region "$REGION" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SECURITY_GROUP_NAME},{Key=${PROJECT_TAG%%=*},Value=${PROJECT_TAG#*=}}]" \
        --query 'GroupId' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$SECURITY_GROUP_ID" ]; then
        log_error "Failed to create Security Group: $SECURITY_GROUP_ID"
        log_section_end "Security Group Creation" "failed"
        return 1
    fi
    
    log_info "Security Group created successfully: $SECURITY_GROUP_ID"
    save_state "SECURITY_GROUP_ID" "$SECURITY_GROUP_ID"
    
    # Add SSH rule (port 22)
    log_debug "Adding SSH ingress rule (port 22)"
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 22 \
        --cidr "$SSH_CIDR" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to add SSH rule"
        log_section_end "Security Group Creation" "failed"
        return 1
    fi
    
    log_info "SSH rule added successfully"
    
    # Add HTTP rule (port 80)
    log_debug "Adding HTTP ingress rule (port 80)"
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 80 \
        --cidr "$HTTP_CIDR" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to add HTTP rule"
        log_section_end "Security Group Creation" "failed"
        return 1
    fi
    
    log_info "HTTP rule added successfully"
    
    # Add HTTPS rule (port 443)
    log_debug "Adding HTTPS ingress rule (port 443)"
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 443 \
        --cidr "$HTTPS_CIDR" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to add HTTPS rule"
        log_section_end "Security Group Creation" "failed"
        return 1
    fi
    
    log_info "HTTPS rule added successfully"
    
    log_section_end "Security Group Creation" "success"
    
    return 0
}

# Main execution
main() {
    log_info "=========================================="
    log_info "AWS Security Group Creation Script"
    log_info "=========================================="
    
    # Pre-flight checks
    log_section "Pre-flight Checks"
    check_aws_cli
    check_aws_credentials
    validate_region "$REGION"
    log_section_end "Pre-flight Checks" "success"
    
    # Initialize state file
    touch "$STATE_FILE"
    
    # Create Security Group
    create_security_group || exit 1
    
    # Display summary
    log_summary "Security Group Creation Summary" \
        "Security Group ID: $SECURITY_GROUP_ID" \
        "Security Group Name: $SECURITY_GROUP_NAME" \
        "VPC ID: $VPC_ID" \
        "" \
        "Inbound Rules:" \
        "  - SSH (Port 22): $SSH_CIDR" \
        "  - HTTP (Port 80): $HTTP_CIDR" \
        "  - HTTPS (Port 443): $HTTPS_CIDR" \
        "" \
        "State file: $STATE_FILE" \
        "Log file: $LOG_FILE"
    
    log_info "Security Group creation completed successfully!"
}

# Run main function
main