#!/bin/bash

# Source the configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# Function to check if Key Pair already exists
check_existing_key_pair() {
    local existing_key_name=$(load_state "KEY_NAME" 2>/dev/null)
    
    if [ -n "$existing_key_name" ]; then
        log_info "Found existing Key Pair name in state file: $existing_key_name"
        
        # Verify the key pair actually exists in AWS
        if aws ec2 describe-key-pairs --key-names "$existing_key_name" --region "$REGION" &> /dev/null; then
            log_info "Key Pair exists in AWS. Skipping creation."
            KEY_NAME="$existing_key_name"
            return 0
        else
            log_warn "Key Pair name in state file does not exist in AWS. Will create new key pair."
            return 1
        fi
    fi
    
    return 1
}

# Function to create Key Pair
create_key_pair() {
    log_section "Key Pair Creation"
    
    # Check if key pair already exists
    if check_existing_key_pair; then
        log_section_end "Key Pair Creation" "success"
        return 0
    fi
    
    log_info "Creating Key Pair: $KEY_NAME"
    
    # Define the key file path
    KEY_FILE="${SCRIPT_DIR}/${KEY_NAME}.pem"
    
    # Check if the key file already exists locally
    if [ -f "$KEY_FILE" ]; then
        log_warn "Key file already exists locally: $KEY_FILE"
        log_info "Checking if key pair exists in AWS..."
        
        if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" &> /dev/null; then
            log_info "Key Pair already exists in AWS. Using existing key pair."
            save_state "KEY_NAME" "$KEY_NAME"
            log_section_end "Key Pair Creation" "success"
            return 0
        else
            log_warn "Local key file exists but key pair not found in AWS."
            log_info "Backing up existing key file..."
            mv "$KEY_FILE" "${KEY_FILE}.backup.$(date +%s)"
            log_info "Existing key file backed up"
        fi
    fi
    
    # Create Key Pair
    log_command "aws ec2 create-key-pair"
    KEY_MATERIAL=$(aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$REGION" \
        --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=$KEY_NAME},{Key=${PROJECT_TAG%%=*},Value=${PROJECT_TAG#*=}}]" \
        --query 'KeyMaterial' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$KEY_MATERIAL" ]; then
        log_error "Failed to create Key Pair: $KEY_MATERIAL"
        log_section_end "Key Pair Creation" "failed"
        return 1
    fi
    
    log_info "Key Pair created successfully: $KEY_NAME"
    save_state "KEY_NAME" "$KEY_NAME"
    
    # Save the key material to file
    log_info "Saving private key to: $KEY_FILE"
    echo "$KEY_MATERIAL" > "$KEY_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to save private key to file"
        log_section_end "Key Pair Creation" "failed"
        return 1
    fi
    
    # Set proper permissions for the key file
    log_debug "Setting permissions for key file (chmod 400)"
    chmod 400 "$KEY_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to set permissions for key file"
        log_section_end "Key Pair Creation" "failed"
        return 1
    fi
    
    log_info "Private key saved and permissions set successfully"
    log_info "Key file location: $KEY_FILE"
    
    log_section_end "Key Pair Creation" "success"
    
    return 0
}

# Main execution
main() {
    log_info "=========================================="
    log_info "AWS Key Pair Creation Script"
    log_info "=========================================="
    
    # Pre-flight checks
    log_section "Pre-flight Checks"
    check_aws_cli
    check_aws_credentials
    validate_region "$REGION"
    log_section_end "Pre-flight Checks" "success"
    
    # Initialize state file
    touch "$STATE_FILE"
    
    # Create Key Pair
    create_key_pair || exit 1
    
    # Display summary
    log_summary "Key Pair Creation Summary" \
        "Key Pair Name: $KEY_NAME" \
        "Key File Location: ${SCRIPT_DIR}/${KEY_NAME}.pem" \
        "Region: $REGION" \
        "" \
        "IMPORTANT: Keep your private key file secure!" \
        "Use this key to connect to EC2 instances:" \
        "  ssh -i ${KEY_NAME}.pem ec2-user@<instance-ip>"
    
    log_info "Key Pair creation completed successfully!"
}

# Initialize logging
init_logging

# Run main function
main
