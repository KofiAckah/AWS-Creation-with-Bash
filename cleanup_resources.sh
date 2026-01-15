#!/bin/bash
# Source the configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# Function to cleanup S3 bucket
cleanup_s3_bucket() {
    log_section "S3 Bucket Cleanup"
    
    local bucket_name=$(load_state "S3_BUCKET_NAME" 2>/dev/null)
    
    if [ -z "$bucket_name" ]; then
        log_warn "No S3 bucket found in state file"
        log_section_end "S3 Bucket Cleanup" "success"
        return 0
    fi
    
    log_info "Cleaning up S3 bucket: $bucket_name"
    
    # Check if bucket exists (S3 is global, no region check needed for ls)
    if ! aws s3 ls "s3://$bucket_name" 2>/dev/null >/dev/null; then
        log_warn "S3 bucket does not exist: $bucket_name"
        log_section_end "S3 Bucket Cleanup" "success"
        return 0
    fi
    
    # Empty the bucket first
    log_info "Emptying S3 bucket contents..."
    aws s3 rm "s3://$bucket_name" --recursive 2>&1 | tee -a "$LOG_FILE"
    
    local empty_result=$?
    if [ $empty_result -ne 0 ]; then
        log_warn "Failed to empty S3 bucket (it may already be empty), continuing..."
    fi
    
    # Delete the bucket
    log_info "Deleting S3 bucket..."
    aws s3 rb "s3://$bucket_name" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to delete S3 bucket"
        log_section_end "S3 Bucket Cleanup" "failed"
        return 1
    fi
    
    log_info "S3 bucket deleted successfully"
    log_section_end "S3 Bucket Cleanup" "success"
    
    return 0
}

# Function to cleanup EC2 instance
cleanup_ec2_instance() {
    log_section "EC2 Instance Cleanup"
    
    local instance_id=$(load_state "INSTANCE_ID" 2>/dev/null)
    
    if [ -z "$instance_id" ]; then
        log_warn "No EC2 instance found in state file"
        log_section_end "EC2 Instance Cleanup" "success"
        return 0
    fi
    
    log_info "Terminating EC2 instance: $instance_id"
    
    # Check if instance exists
    if ! aws ec2 describe-instances --instance-ids "$instance_id" --region "$REGION" &> /dev/null; then
        log_warn "EC2 instance does not exist: $instance_id"
        log_section_end "EC2 Instance Cleanup" "success"
        return 0
    fi
    
    # Terminate the instance
    aws ec2 terminate-instances --instance-ids "$instance_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to terminate EC2 instance"
        log_section_end "EC2 Instance Cleanup" "failed"
        return 1
    fi
    
    # Wait for instance to terminate
    log_info "Waiting for instance to terminate..."
    aws ec2 wait instance-terminated --instance-ids "$instance_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_warn "Timeout waiting for instance termination, but continuing..."
    else
        log_info "EC2 instance terminated successfully"
    fi
    
    log_section_end "EC2 Instance Cleanup" "success"
    
    return 0
}

# Function to cleanup Security Group
cleanup_security_group() {
    log_section "Security Group Cleanup"
    
    local sg_id=$(load_state "SECURITY_GROUP_ID" 2>/dev/null)
    
    if [ -z "$sg_id" ]; then
        log_warn "No Security Group found in state file"
        log_section_end "Security Group Cleanup" "success"
        return 0
    fi
    
    log_info "Deleting Security Group: $sg_id"
    
    # Check if security group exists
    if ! aws ec2 describe-security-groups --group-ids "$sg_id" --region "$REGION" &> /dev/null; then
        log_warn "Security Group does not exist: $sg_id"
        log_section_end "Security Group Cleanup" "success"
        return 0
    fi
    
    # Delete the security group
    aws ec2 delete-security-group --group-id "$sg_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to delete Security Group"
        log_section_end "Security Group Cleanup" "failed"
        return 1
    fi
    
    log_info "Security Group deleted successfully"
    log_section_end "Security Group Cleanup" "success"
    
    return 0
}

# Function to cleanup Route Table
cleanup_route_table() {
    log_section "Route Table Cleanup"
    
    local rt_id=$(load_state "PUBLIC_RT_ID" 2>/dev/null)
    local rt_assoc_id=$(load_state "PUBLIC_RT_ASSOC_ID" 2>/dev/null)
    
    if [ -z "$rt_id" ]; then
        log_warn "No Route Table found in state file"
        log_section_end "Route Table Cleanup" "success"
        return 0
    fi
    
    log_info "Cleaning up Route Table: $rt_id"
    
    # Check if route table exists
    if ! aws ec2 describe-route-tables --route-table-ids "$rt_id" --region "$REGION" &> /dev/null; then
        log_warn "Route Table does not exist: $rt_id"
        log_section_end "Route Table Cleanup" "success"
        return 0
    fi
    
    # Disassociate route table if association exists
    if [ -n "$rt_assoc_id" ]; then
        log_info "Disassociating Route Table..."
        aws ec2 disassociate-route-table --association-id "$rt_assoc_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
        
        if [ $? -ne 0 ]; then
            log_warn "Failed to disassociate Route Table, but continuing..."
        fi
    fi
    
    # Delete the route table
    log_info "Deleting Route Table..."
    aws ec2 delete-route-table --route-table-id "$rt_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to delete Route Table"
        log_section_end "Route Table Cleanup" "failed"
        return 1
    fi
    
    log_info "Route Table deleted successfully"
    log_section_end "Route Table Cleanup" "success"
    
    return 0
}

# Function to cleanup Subnets
cleanup_subnets() {
    log_section "Subnets Cleanup"
    
    local public_subnet_id=$(load_state "PUBLIC_SUBNET_ID" 2>/dev/null)
    local private_subnet_id=$(load_state "PRIVATE_SUBNET_ID" 2>/dev/null)
    
    # Delete Public Subnet
    if [ -n "$public_subnet_id" ]; then
        log_info "Deleting Public Subnet: $public_subnet_id"
        
        if aws ec2 describe-subnets --subnet-ids "$public_subnet_id" --region "$REGION" &> /dev/null; then
            aws ec2 delete-subnet --subnet-id "$public_subnet_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
            
            if [ $? -ne 0 ]; then
                log_error "Failed to delete Public Subnet"
                log_section_end "Subnets Cleanup" "failed"
                return 1
            fi
            
            log_info "Public Subnet deleted successfully"
        else
            log_warn "Public Subnet does not exist: $public_subnet_id"
        fi
    fi
    
    # Delete Private Subnet
    if [ -n "$private_subnet_id" ]; then
        log_info "Deleting Private Subnet: $private_subnet_id"
        
        if aws ec2 describe-subnets --subnet-ids "$private_subnet_id" --region "$REGION" &> /dev/null; then
            aws ec2 delete-subnet --subnet-id "$private_subnet_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
            
            if [ $? -ne 0 ]; then
                log_error "Failed to delete Private Subnet"
                log_section_end "Subnets Cleanup" "failed"
                return 1
            fi
            
            log_info "Private Subnet deleted successfully"
        else
            log_warn "Private Subnet does not exist: $private_subnet_id"
        fi
    fi
    
    if [ -z "$public_subnet_id" ] && [ -z "$private_subnet_id" ]; then
        log_warn "No Subnets found in state file"
    fi
    
    log_section_end "Subnets Cleanup" "success"
    
    return 0
}

# Function to cleanup Internet Gateway
cleanup_internet_gateway() {
    log_section "Internet Gateway Cleanup"
    
    local igw_id=$(load_state "IGW_ID" 2>/dev/null)
    local vpc_id=$(load_state "VPC_ID" 2>/dev/null)
    
    if [ -z "$igw_id" ]; then
        log_warn "No Internet Gateway found in state file"
        log_section_end "Internet Gateway Cleanup" "success"
        return 0
    fi
    
    log_info "Cleaning up Internet Gateway: $igw_id"
    
    # Check if IGW exists
    if ! aws ec2 describe-internet-gateways --internet-gateway-ids "$igw_id" --region "$REGION" &> /dev/null; then
        log_warn "Internet Gateway does not exist: $igw_id"
        log_section_end "Internet Gateway Cleanup" "success"
        return 0
    fi
    
    # Detach from VPC if attached
    if [ -n "$vpc_id" ]; then
        log_info "Detaching Internet Gateway from VPC..."
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
        
        if [ $? -ne 0 ]; then
            log_warn "Failed to detach Internet Gateway, but continuing..."
        fi
    fi
    
    # Delete the internet gateway
    log_info "Deleting Internet Gateway..."
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to delete Internet Gateway"
        log_section_end "Internet Gateway Cleanup" "failed"
        return 1
    fi
    
    log_info "Internet Gateway deleted successfully"
    log_section_end "Internet Gateway Cleanup" "success"
    
    return 0
}

# Function to cleanup VPC
cleanup_vpc() {
    log_section "VPC Cleanup"
    
    local vpc_id=$(load_state "VPC_ID" 2>/dev/null)
    
    if [ -z "$vpc_id" ]; then
        log_warn "No VPC found in state file"
        log_section_end "VPC Cleanup" "success"
        return 0
    fi
    
    log_info "Deleting VPC: $vpc_id"
    
    # Check if VPC exists
    if ! aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$REGION" &> /dev/null; then
        log_warn "VPC does not exist: $vpc_id"
        log_section_end "VPC Cleanup" "success"
        return 0
    fi
    
    # Delete the VPC
    aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to delete VPC"
        log_section_end "VPC Cleanup" "failed"
        return 1
    fi
    
    log_info "VPC deleted successfully"
    log_section_end "VPC Cleanup" "success"
    
    return 0
}

# Function to backup state file
backup_state_file() {
    if [ -f "$STATE_FILE" ]; then
        local backup_file="${STATE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$STATE_FILE" "$backup_file"
        log_info "State file backed up to: $backup_file"
    fi
}

# Function to clear state file
clear_state_file() {
    if [ -f "$STATE_FILE" ]; then
        > "$STATE_FILE"
        log_info "State file cleared"
    fi
}

# Main execution
main() {
    log_info "=========================================="
    log_info "AWS Resources Cleanup Script"
    log_info "=========================================="
    
    # Pre-flight checks
    log_section "Pre-flight Checks"
    check_aws_cli
    check_aws_credentials
    validate_region "$REGION"
    log_section_end "Pre-flight Checks" "success"
    
    # Check if state file exists
    if [ ! -f "$STATE_FILE" ]; then
        log_error "State file not found: $STATE_FILE"
        log_error "Cannot proceed with cleanup without state file"
        exit 1
    fi
    
    # Backup state file
    backup_state_file
    
    # Confirm cleanup
    echo ""
    log_warn "WARNING: This will delete ALL resources created by this automation!"
    log_warn "This action CANNOT be undone!"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Starting cleanup process..."
    echo ""
    
    # Cleanup resources in reverse order of creation
    local cleanup_failed=0
    
    # 1. Cleanup S3 bucket
    cleanup_s3_bucket || cleanup_failed=1
    
    # 2. Cleanup EC2 instance
    cleanup_ec2_instance || cleanup_failed=1
    
    # 3. Cleanup Security Group
    cleanup_security_group || cleanup_failed=1
    
    # 4. Cleanup Route Table
    cleanup_route_table || cleanup_failed=1
    
    # 5. Cleanup Subnets
    cleanup_subnets || cleanup_failed=1
    
    # 6. Cleanup Internet Gateway
    cleanup_internet_gateway || cleanup_failed=1
    
    # 7. Cleanup VPC
    cleanup_vpc || cleanup_failed=1
    
    # Clear state file if cleanup was successful
    if [ $cleanup_failed -eq 0 ]; then
        clear_state_file
        
        log_summary "Cleanup Summary" \
            "All resources cleaned up successfully!" \
            "" \
            "Resources deleted:" \
            "  - S3 Bucket" \
            "  - EC2 Instance" \
            "  - Security Group" \
            "  - Route Table" \
            "  - Public Subnet" \
            "  - Private Subnet" \
            "  - Internet Gateway" \
            "  - VPC" \
            "" \
            "Log file: $LOG_FILE"
        
        log_info "Cleanup completed successfully!"
        exit 0
    else
        log_error "Some resources failed to cleanup"
        log_error "Please check the log file for details: $LOG_FILE"
        log_error "You may need to manually delete remaining resources"
        exit 1
    fi
}

# Run main function
main