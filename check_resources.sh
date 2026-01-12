#!/bin/bash

# Source the configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# Function to check resource status
check_resource_status() {
    local resource_type=$1
    local resource_id=$2
    local command=$3
    
    if [ -z "$resource_id" ]; then
        echo "  Status: Not found in state file"
        return 1
    fi
    
    if eval "$command" &> /dev/null; then
        echo "  Status: ✓ EXISTS"
        echo "  ID: $resource_id"
        return 0
    else
        echo "  Status: ✗ NOT FOUND (in state file but not in AWS)"
        echo "  ID: $resource_id"
        return 1
    fi
}

# Main execution
main() {
    log_info "=========================================="
    log_info "AWS Resources Status Check"
    log_info "=========================================="
    echo ""
    
    # Pre-flight checks
    check_aws_cli || exit 1
    check_aws_credentials || exit 1
    
    # Check if state file exists
    if [ ! -f "$STATE_FILE" ]; then
        log_error "State file not found: $STATE_FILE"
        exit 1
    fi
    
    echo "Checking resources status..."
    echo ""
    
    # VPC
    echo "1. VPC:"
    check_resource_status "VPC" "$(load_state VPC_ID 2>/dev/null)" \
        "aws ec2 describe-vpcs --vpc-ids $(load_state VPC_ID 2>/dev/null) --region $REGION"
    echo ""
    
    # Internet Gateway
    echo "2. Internet Gateway:"
    check_resource_status "IGW" "$(load_state IGW_ID 2>/dev/null)" \
        "aws ec2 describe-internet-gateways --internet-gateway-ids $(load_state IGW_ID 2>/dev/null) --region $REGION"
    echo ""
    
    # Public Subnet
    echo "3. Public Subnet:"
    check_resource_status "Subnet" "$(load_state PUBLIC_SUBNET_ID 2>/dev/null)" \
        "aws ec2 describe-subnets --subnet-ids $(load_state PUBLIC_SUBNET_ID 2>/dev/null) --region $REGION"
    echo ""
    
    # Private Subnet
    echo "4. Private Subnet:"
    check_resource_status "Subnet" "$(load_state PRIVATE_SUBNET_ID 2>/dev/null)" \
        "aws ec2 describe-subnets --subnet-ids $(load_state PRIVATE_SUBNET_ID 2>/dev/null) --region $REGION"
    echo ""
    
    # Route Table
    echo "5. Route Table:"
    check_resource_status "Route Table" "$(load_state PUBLIC_RT_ID 2>/dev/null)" \
        "aws ec2 describe-route-tables --route-table-ids $(load_state PUBLIC_RT_ID 2>/dev/null) --region $REGION"
    echo ""
    
    # Security Group
    echo "6. Security Group:"
    check_resource_status "Security Group" "$(load_state SECURITY_GROUP_ID 2>/dev/null)" \
        "aws ec2 describe-security-groups --group-ids $(load_state SECURITY_GROUP_ID 2>/dev/null) --region $REGION"
    echo ""
    
    # EC2 Instance
    echo "7. EC2 Instance:"
    local instance_id=$(load_state INSTANCE_ID 2>/dev/null)
    if [ -n "$instance_id" ]; then
        if aws ec2 describe-instances --instance-ids "$instance_id" --region "$REGION" &> /dev/null; then
            local state=$(aws ec2 describe-instances --instance-ids "$instance_id" --region "$REGION" \
                --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null)
            echo "  Status: ✓ EXISTS (State: $state)"
            echo "  ID: $instance_id"
            
            if [ "$state" == "running" ]; then
                local public_ip=$(load_state PUBLIC_IP 2>/dev/null)
                echo "  Public IP: $public_ip"
            fi
        else
            echo "  Status: ✗ NOT FOUND"
            echo "  ID: $instance_id"
        fi
    else
        echo "  Status: Not found in state file"
    fi
    echo ""
    
    # S3 Bucket
    echo "8. S3 Bucket:"
    local bucket_name=$(load_state S3_BUCKET_NAME 2>/dev/null)
    if [ -n "$bucket_name" ]; then
        if aws s3 ls "s3://$bucket_name" --region "$REGION" &> /dev/null; then
            echo "  Status: ✓ EXISTS"
            echo "  Name: $bucket_name"
            
            # Count objects in bucket
            local object_count=$(aws s3 ls "s3://$bucket_name" --recursive --region "$REGION" 2>/dev/null | wc -l)
            echo "  Objects: $object_count"
        else
            echo "  Status: ✗ NOT FOUND"
            echo "  Name: $bucket_name"
        fi
    else
        echo "  Status: Not found in state file"
    fi
    echo ""
    
    echo "=========================================="
    echo "Status check complete!"
    echo "=========================================="
}

# Run main function
main