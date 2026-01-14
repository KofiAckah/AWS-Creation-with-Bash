#!/bin/bash

# Source the configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# S3 Bucket Configuration
BUCKET_NAME="automation-lab-bucket-$(date +%s)"
WELCOME_FILE="welcome.txt"

# Function to check if S3 bucket already exists
check_existing_bucket() {
    local existing_bucket=$(load_state "S3_BUCKET_NAME" 2>/dev/null)
    
    if [ -n "$existing_bucket" ]; then
        log_info "Found existing S3 bucket in state file: $existing_bucket"
        
        # Verify the bucket actually exists in AWS
        if aws s3api head-bucket --bucket "$existing_bucket" --region "$REGION" 2>/dev/null; then
            log_info "S3 bucket exists in AWS. Skipping creation."
            BUCKET_NAME="$existing_bucket"
            return 0
        else
            log_warn "S3 bucket in state file does not exist in AWS. Will create new bucket."
            return 1
        fi
    fi
    
    return 1
}

# Function to create S3 bucket
create_s3_bucket() {
    log_section "S3 Bucket Creation"
    
    # Check if bucket already exists
    if check_existing_bucket; then
        log_section_end "S3 Bucket Creation" "success"
        return 0
    fi
    
    log_info "Creating S3 bucket: $BUCKET_NAME"
    
    # Create bucket
    log_command "aws s3api create-bucket"
    
    if [ "$REGION" = "us-east-1" ]; then
        # us-east-1 doesn't need LocationConstraint
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    else
        # Other regions need LocationConstraint
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create S3 bucket: $BUCKET_NAME"
        log_section_end "S3 Bucket Creation" "failed"
        return 1
    fi
    
    log_info "S3 bucket created successfully: $BUCKET_NAME"
    save_state "S3_BUCKET_NAME" "$BUCKET_NAME"
    
    # Add tags to bucket
    log_debug "Adding tags to S3 bucket"
    aws s3api put-bucket-tagging \
        --bucket "$BUCKET_NAME" \
        --tagging "TagSet=[{Key=Name,Value=$BUCKET_NAME},{Key=${PROJECT_TAG%%=*},Value=${PROJECT_TAG#*=}}]" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_warn "Failed to add tags to S3 bucket, but continuing..."
    else
        log_info "Tags added to S3 bucket successfully"
    fi
    
    # Enable versioning (optional but recommended)
    log_debug "Enabling versioning on S3 bucket"
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_warn "Failed to enable versioning, but continuing..."
    else
        log_info "Versioning enabled on S3 bucket"
    fi
    
    log_section_end "S3 Bucket Creation" "success"
    
    return 0
}

# Function to upload welcome file to S3
upload_welcome_file() {
    log_section "Upload Welcome File"
    
    if [ ! -f "$WELCOME_FILE" ]; then
        log_error "Welcome file not found: $WELCOME_FILE"
        log_section_end "Upload Welcome File" "failed"
        return 1
    fi
    
    log_info "Uploading $WELCOME_FILE to S3 bucket: $BUCKET_NAME"
    
    log_command "aws s3 cp"
    aws s3 cp "$WELCOME_FILE" "s3://$BUCKET_NAME/$WELCOME_FILE" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to upload welcome file to S3"
        log_section_end "Upload Welcome File" "failed"
        return 1
    fi
    
    log_info "Welcome file uploaded successfully"
    
    # Make the file publicly readable (optional)
    log_debug "Setting ACL for welcome file"
    aws s3api put-object-acl \
        --bucket "$BUCKET_NAME" \
        --key "$WELCOME_FILE" \
        --acl public-read \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_warn "Failed to set ACL for welcome file, but continuing..."
    else
        log_info "ACL set for welcome file"
    fi
    
    # Get the file URL
    FILE_URL="https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/${WELCOME_FILE}"
    log_info "File URL: $FILE_URL"
    save_state "WELCOME_FILE_URL" "$FILE_URL"
    
    log_section_end "Upload Welcome File" "success"
    
    return 0
}

# Function to enable public access (if needed)
enable_public_access() {
    log_section "Configure Public Access"
    
    log_info "Disabling block public access settings"
    
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_warn "Failed to configure public access settings"
    else
        log_info "Public access configured successfully"
    fi
    
    log_section_end "Configure Public Access" "success"
    
    return 0
}

# Main execution
main() {
    log_info "=========================================="
    log_info "AWS S3 Bucket Creation Script"
    log_info "=========================================="
    
    # Pre-flight checks
    log_section "Pre-flight Checks"
    check_aws_cli
    check_aws_credentials
    validate_region "$REGION"
    log_section_end "Pre-flight Checks" "success"
    
    # Initialize state file
    touch "$STATE_FILE"
    
    # Create S3 bucket
    create_s3_bucket || exit 1
    
    # Enable public access (optional)
    enable_public_access
    
    # Upload welcome file
    upload_welcome_file || exit 1
    
    # Display summary
    log_summary "S3 Bucket Creation Summary" \
        "Bucket Name: $BUCKET_NAME" \
        "Region: $REGION" \
        "Welcome File: $WELCOME_FILE" \
        "File URL: $(load_state WELCOME_FILE_URL)" \
        "" \
        "State file: $STATE_FILE" \
        "Log file: $LOG_FILE"
    
    log_info "S3 bucket creation completed successfully!"
}

# Run main function
main